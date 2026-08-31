import { Router } from 'express';
import sql from 'mssql';
import type { SessionDb } from '../db/index.js';
import { withTransientRetry } from '../db/retry.js';
import { mapSqlError } from '../../shared/spError.js';
import type { MappedError } from '../../shared/spError.js';
import type { BookingStatus } from '../../shared/contract.js';
import type {
  BookingCreateResponse,
  CancelBookingResponse,
  CostEstimateResponse,
  MyBooking,
  MyBookingsResponse,
} from '../../shared/types.js';
import { isValidCourtId, isValidGuid, toSqlDate, validateWindow } from '../time.js';

/**
 * Customer booking API (Phase 2.4 + 2.5) — authenticated CUSTOMER only.
 *
 * POST /api/bookings                    { courtId, startTime, endTime }
 * GET  /api/bookings/estimate?courtId=...&startTime=...&endTime=...
 * GET  /api/bookings/mine
 * POST /api/bookings/:bookingId/cancel
 *
 * All routes run on the authenticated SESSION_CONTEXT connection (SessionDb):
 * the request carries ONLY the court + wall-clock window (+ booking id for
 * cancellation). Authorization, ownership, pricing and booking validity are
 * decided by dbo.sp_BookCourt / dbo.fn_CalculateBookingCost /
 * dbo.sp_GetMyBookings / dbo.sp_CancelBooking on that connection. The browser is
 * never trusted for UserId/Role/status/cost, and the shared (public) SQL pool is
 * never used here.
 *
 * sp_BookCourt (06_procedures.sql) requires:
 *   - SESSION_CONTEXT('UserId') set by sp_Login, matching @UserId
 *   - role CUSTOMER
 *   - a valid active court
 *   - a valid future 06:00-22:00, 30-min-boundary, 1-3h, same-day window
 *   - no overlapping BOOKED booking on the same court
 * and INSERTs exactly one PENDING row (triggers emit audit + owner notification).
 *
 * sp_GetMyBookings returns ONLY the SESSION_CONTEXT actor's own rows.
 * sp_CancelBooking re-validates ownership/state/3h-deadline under lock; the
 * request carries no authority/state fields.
 */

/** Serialize a failure for the HTTP client: code + safe Vietnamese message ONLY.
 * Raw SQL/driver detail is logged server-side and never serialized to the
 * response, in every environment (including dev). */
function serializeError(mapped: MappedError) {
  console.error(`[bookings] request failed (code=${mapped.code ?? 'none'}): ${mapped.technical}`);
  return {
    code: mapped.code,
    message: mapped.message ?? mapped.fallback,
  };
}

/**
 * HTTP status for a failure mapped from a real dbo.sp_BookCourt error code
 * (06_procedures.sql). Business validity errors stay 4xx with a stable message;
 * unknown/system errors become 500.
 */
function bookingFailureStatus(mapped: MappedError): number {
  if (mapped.code === 1205) return 409; // deadlock victim: safe retry
  if (mapped.code === 1222) return 503; // IMP-10: lock timeout → quá tải tạm thời, thử lại sau
  if (mapped.code === 2601) return 409; // IMP-09: đã có PENDING trùng của chính người này
  if (mapped.code === 50021) return 409; // overlapping BOOKED booking
  if (mapped.code === 50011) return 403; // only CUSTOMER may book
  if (mapped.code !== null) return 400; // every other known THROW is a bad request
  return 500;
}

/** Safe HTTP status for a dbo.sp_CancelBooking failure (exact THROW codes). */
function cancelFailureStatus(mapped: MappedError): number {
  if (mapped.code === 1205) return 409; // deadlock victim: safe retry
  if (mapped.code === 1222) return 503; // IMP-10: lock timeout → quá tải tạm thời, thử lại sau
  if (mapped.code === 50051) return 404; // booking not found
  if (mapped.code === 50054 || mapped.code === 50056 || mapped.code === 50057) return 403; // ownership/permission
  if (mapped.code === 50052 || mapped.code === 50053 || mapped.code === 50055 || mapped.code === 50058) return 409; // state/deadline/race
  if (mapped.code !== null) return 400;
  return 500;
}

/** Safe HTTP status for a dbo.sp_GetMyBookings failure. */
function historyFailureStatus(mapped: MappedError): number {
  if (mapped.code === 51054) return 401; // session context empty/mismatched → re-login
  if (mapped.code === 1205) return 409; // deadlock victim: safe retry
  if (mapped.code === 1222) return 503; // IMP-10: lock timeout → quá tải tạm thời, thử lại sau
  if (mapped.code !== null) return 400;
  return 500;
}

export function createBookingsRouter(sessionDb: SessionDb): Router {
  const router = Router();

  /**
   * Pre-confirm cost estimate for the booking detail screen (Phase 2.4).
   *
   * GET /api/bookings/estimate?courtId=...&startTime=...&endTime=...
   *
   * Belongs to the authenticated CUSTOMER booking flow (same security as the
   * create route): it runs on the dedicated SessionDb connection after the SQL
   * SESSION_CONTEXT has been verified, never on the shared pool. The estimate is
   * computed BY THE DATABASE through dbo.fn_CalculateBookingCost — the app
   * contains no cost formula. The value is display-only ("Chi phí dự kiến"); the
   * authoritative TotalCost still comes from dbo.sp_BookCourt after the booking
   * is created. totalCost is null when the court does not exist.
   */
  router.get('/estimate', async (req, res) => {
    const user = req.session.user;
    if (!user) {
      res.status(401).json({ error: { code: null, message: 'Chưa đăng nhập.' } });
      return;
    }
    if (user.role !== 'CUSTOMER') {
      res.status(403).json({ error: { code: null, message: 'Chỉ CUSTOMER mới xem được chi phí dự kiến.' } });
      return;
    }

    const sessionId = req.session.id;
    const contextOk = await sessionDb.verifySessionContext(sessionId, user.userId, user.role);
    if (!contextOk) {
      delete req.session.user;
      res.status(401).json({ error: { code: null, message: 'Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại.' } });
      return;
    }

    const window = validateWindow(req.query.startTime, req.query.endTime, 'đặt');
    if (!window.ok) {
      res.status(400).json({ error: { code: null, message: window.message } });
      return;
    }
    const courtId = req.query.courtId;
    if (!isValidCourtId(courtId)) {
      res.status(400).json({ error: { code: null, message: 'Mã sân (courtId) không hợp lệ.' } });
      return;
    }

    try {
      const rows = await sessionDb.withExistingConnection(sessionId, async (conn) => {
        const r = conn
          .request()
          .input('CourtId', sql.UniqueIdentifier, courtId)
          .input('StartTime', sql.DateTime2(0), toSqlDate(window.start))
          .input('EndTime', sql.DateTime2(0), toSqlDate(window.end));
        const result = await r.query<{ TotalCost: number | null }>(
          'SELECT CONVERT(decimal(12,0), dbo.fn_CalculateBookingCost(@CourtId, @StartTime, @EndTime)) AS TotalCost;',
        );
        return result.recordset;
      });

      const body: CostEstimateResponse = {
        totalCost: rows[0]?.TotalCost ?? null,
        courtId: courtId as string,
        startTime: window.startSql.replace(' ', 'T'),
        endTime: window.endSql.replace(' ', 'T'),
      };
      res.json(body);
    } catch (err) {
      // The dedicated SQL connection is gone (e.g. server restart, logout race).
      if (err instanceof Error && err.message === 'No active SQL session connection') {
        delete req.session.user;
        res.status(401).json({ error: { code: null, message: 'Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại.' } });
        return;
      }
      // The estimate is best-effort: any SQL/DB-side failure (including a
      // permission problem on fn_CalculateBookingCost) surfaces as a server
      // error and the UI degrades to "—" without blocking the booking flow.
      const mapped = mapSqlError(err);
      res.status(500).json({ error: { code: mapped.code, message: mapped.message ?? mapped.fallback } });
    }
  });

  /**
   * GET /api/bookings/mine — authenticated CUSTOMER history (Phase 2.5).
   *
   * Executes dbo.sp_GetMyBookings on the existing SessionDb connection after
   * verifying SESSION_CONTEXT. The SP derives the owner strictly from
   * SESSION_CONTEXT('UserId') (KNOWN-06: no fallback, impersonation rejected);
   * the @UserId we pass comes from the authenticated Express session and must
   * equal the SQL actor. No client-supplied identity is accepted.
   */
  router.get('/mine', async (req, res) => {
    const user = req.session.user;
    if (!user) {
      res.status(401).json({ error: { code: null, message: 'Chưa đăng nhập.' } });
      return;
    }
    if (user.role !== 'CUSTOMER') {
      res.status(403).json({ error: { code: null, message: 'Chỉ CUSTOMER mới xem được lịch sử đặt sân.' } });
      return;
    }

    const sessionId = req.session.id;
    const contextOk = await sessionDb.verifySessionContext(sessionId, user.userId, user.role);
    if (!contextOk) {
      delete req.session.user;
      res.status(401).json({ error: { code: null, message: 'Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại.' } });
      return;
    }

    try {
      const rows = await sessionDb.withExistingConnection(sessionId, async (conn) => {
        const r = conn.request().input('UserId', sql.UniqueIdentifier, user.userId);
        const result = await r.execute('dbo.sp_GetMyBookings');
        return result.recordset as Array<{
          BookingId: string;
          CourtId: string;
          CourtName: string;
          CourtAddress: string;
          StartTime: Date;
          EndTime: Date;
          Status: string;
          TotalCost: number | null;
          CreatedAt: Date;
        }>;
      });

      const bookings: MyBooking[] = rows.map((row) => ({
        BookingId: row.BookingId,
        CourtId: row.CourtId,
        CourtName: row.CourtName,
        CourtAddress: row.CourtAddress,
        StartTime: row.StartTime,
        EndTime: row.EndTime,
        Status: row.Status as BookingStatus,
        TotalCost: Number(row.TotalCost ?? 0),
        CreatedAt: row.CreatedAt,
      }));

      const body: MyBookingsResponse = { bookings, count: bookings.length };
      res.json(body);
    } catch (err) {
      if (err instanceof Error && err.message === 'No active SQL session connection') {
        delete req.session.user;
        res.status(401).json({ error: { code: null, message: 'Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại.' } });
        return;
      }
      const mapped = mapSqlError(err);
      res.status(historyFailureStatus(mapped)).json({ error: serializeError(mapped) });
    }
  });

  /**
   * POST /api/bookings/:bookingId/cancel — authenticated CUSTOMER cancellation
   * (Phase 2.5).
   *
   * The body/URL carries ONLY the booking id. dbo.sp_CancelBooking re-validates
   * under lock: actor (SESSION_CONTEXT), ownership, state and the 3-hour
   * BOOKED deadline (50050..50058). On success the booking becomes CANCELLED and
   * the UI refreshes history from the DB instead of patching local state.
   */
  router.post('/:bookingId/cancel', async (req, res) => {
    const user = req.session.user;
    if (!user) {
      res.status(401).json({ error: { code: null, message: 'Chưa đăng nhập.' } });
      return;
    }
    if (user.role !== 'CUSTOMER') {
      res.status(403).json({ error: { code: null, message: 'Chỉ CUSTOMER mới được hủy booking.' } });
      return;
    }

    const sessionId = req.session.id;
    const contextOk = await sessionDb.verifySessionContext(sessionId, user.userId, user.role);
    if (!contextOk) {
      delete req.session.user;
      res.status(401).json({ error: { code: null, message: 'Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại.' } });
      return;
    }

    const rawBookingId = req.params.bookingId;
    if (!isValidGuid(rawBookingId)) {
      res.status(400).json({ error: { code: null, message: 'Mã booking không hợp lệ.' } });
      return;
    }

    try {
      // IMP-10: tự thử lại khi gặp deadlock (1205) / lock timeout (1222).
      // An toàn vì sp_CancelBooking dùng SET XACT_ABORT ON + ROLLBACK trong CATCH.
      await withTransientRetry(
        () =>
          sessionDb.withExistingConnection(sessionId, async (conn) => {
            const r = conn
              .request()
              .input('SessionUserId', sql.UniqueIdentifier, user.userId)
              .input('BookingId', sql.UniqueIdentifier, rawBookingId);
            await r.execute('dbo.sp_CancelBooking');
          }),
        { label: 'dbo.sp_CancelBooking' },
      );

      const body: CancelBookingResponse = { bookingId: rawBookingId, status: 'CANCELLED' };
      res.json(body);
    } catch (err) {
      if (err instanceof Error && err.message === 'No active SQL session connection') {
        delete req.session.user;
        res.status(401).json({ error: { code: null, message: 'Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại.' } });
        return;
      }
      const mapped = mapSqlError(err);
      if (mapped.code === 50050) {
        // Actor/user/context problem reported by the SP → re-login required.
        delete req.session.user;
        res.status(401).json({ error: { code: null, message: mapped.message ?? 'Phiên đăng nhập không hợp lệ. Vui lòng đăng nhập lại.' } });
        return;
      }
      res.status(cancelFailureStatus(mapped)).json({ error: serializeError(mapped) });
    }
  });

  router.post('/', async (req, res) => {
    const user = req.session.user;
    if (!user) {
      res.status(401).json({ error: { code: null, message: 'Chưa đăng nhập.' } });
      return;
    }
    if (user.role !== 'CUSTOMER') {
      res.status(403).json({ error: { code: null, message: 'Chỉ CUSTOMER mới được tạo booking.' } });
      return;
    }

    const sessionId = req.session.id;
    // Verify the real SQL SESSION_CONTEXT on the dedicated connection matches the
    // Express session (evicts the session and 401s when it does not).
    const contextOk = await sessionDb.verifySessionContext(sessionId, user.userId, user.role);
    if (!contextOk) {
      delete req.session.user;
      res.status(401).json({ error: { code: null, message: 'Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại.' } });
      return;
    }

    const { courtId, startTime, endTime } = (req.body ?? {}) as {
      courtId?: unknown;
      startTime?: unknown;
      endTime?: unknown;
    };

    const window = validateWindow(startTime, endTime, 'đặt');
    if (!window.ok) {
      res.status(400).json({ error: { code: null, message: window.message } });
      return;
    }
    if (!isValidCourtId(courtId)) {
      res.status(400).json({ error: { code: null, message: 'Mã sân (courtId) không hợp lệ.' } });
      return;
    }

    try {
      // IMP-10: đây là điểm nóng nhất khi nhiều người bấm "Đặt sân" cùng lúc —
      // sp_BookCourt khoá hàng dbo.Courts (UPDLOCK, ROWLOCK, HOLDLOCK) nên mọi
      // người đặt cùng một sân bị xếp hàng. Tự thử lại khi 1205/1222 để khách
      // không phải tự bấm lại; giao dịch đã rollback nên không sinh booking đôi.
      const output = await withTransientRetry(
        () =>
          sessionDb.withExistingConnection(sessionId, async (conn) => {
            const r = conn
              .request()
              .input('UserId', sql.UniqueIdentifier, user.userId)
              .input('CourtId', sql.UniqueIdentifier, courtId)
              .input('StartTime', sql.DateTime2(0), toSqlDate(window.start))
              .input('EndTime', sql.DateTime2(0), toSqlDate(window.end))
              .output('BookingId', sql.UniqueIdentifier)
              .output('TotalCost', sql.Decimal(12, 0));
            const result = await r.execute('dbo.sp_BookCourt');
            return {
              bookingId: result.output.BookingId as string | undefined,
              totalCost: result.output.TotalCost as number | undefined,
            };
          }),
        { label: 'dbo.sp_BookCourt' },
      );

      if (!output.bookingId || output.totalCost == null) {
        res.status(500).json({ error: { code: null, message: 'Không nhận được kết quả từ hệ thống. Vui lòng thử lại.' } });
        return;
      }

      const body: BookingCreateResponse = {
        booking: {
          BookingId: output.bookingId,
          CourtId: courtId,
          StartTime: window.startSql.replace(' ', 'T'),
          EndTime: window.endSql.replace(' ', 'T'),
          Status: 'PENDING',
          TotalCost: Number(output.totalCost),
        },
      };
      res.status(201).json(body);
    } catch (err) {
      // The dedicated SQL connection is gone (e.g. server restart, logout race).
      if (err instanceof Error && err.message === 'No active SQL session connection') {
        delete req.session.user;
        res.status(401).json({ error: { code: null, message: 'Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại.' } });
        return;
      }
      const mapped = mapSqlError(err);
      res.status(bookingFailureStatus(mapped)).json({ error: serializeError(mapped) });
    }
  });

  return router;
}
