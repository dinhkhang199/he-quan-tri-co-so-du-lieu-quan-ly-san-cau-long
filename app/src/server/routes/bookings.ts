import { Router } from 'express';
import sql from 'mssql';
import type { SessionDb } from '../db/index.js';
import { mapSqlError } from '../../shared/spError.js';
import type { MappedError } from '../../shared/spError.js';
import type { BookingCreateResponse, CostEstimateResponse } from '../../shared/types.js';
import { isValidCourtId, validateWindow } from '../time.js';

/**
 * Customer booking API (Phase 2.4) — authenticated CUSTOMER only.
 *
 * POST /api/bookings      { courtId, startTime, endTime }
 * GET  /api/bookings/estimate?courtId=...&startTime=...&endTime=...
 *
 * Both routes run on the authenticated SESSION_CONTEXT connection (SessionDb):
 * the request carries ONLY the court + wall-clock window. Authorization,
 * ownership, pricing and booking validity are decided by dbo.sp_BookCourt /
 * dbo.fn_CalculateBookingCost on that connection. The browser is never
 * trusted for UserId/Role/status/cost, and the shared (public) SQL pool is
 * never used here.
 *
 * sp_BookCourt (06_procedures.sql) requires:
 *   - SESSION_CONTEXT('UserId') set by sp_Login, matching @UserId
 *   - role CUSTOMER
 *   - a valid active court
 *   - a valid future 06:00-22:00, 30-min-boundary, 1-3h, same-day window
 *   - no overlapping BOOKED booking on the same court
 * and INSERTs exactly one PENDING row (triggers emit audit + owner notification).
 */

/** Mirrors the auth API error shape without leaking credentials/SQL internals. */
function serializeError(mapped: MappedError) {
  return {
    code: mapped.code,
    message: mapped.message ?? mapped.fallback,
    technical: process.env.NODE_ENV === 'test' || process.env.NODE_ENV === 'production' ? undefined : mapped.technical,
  };
}

/**
 * HTTP status for a failure mapped from a real dbo.sp_BookCourt error code
 * (06_procedures.sql). Business validity errors stay 4xx with a stable message;
 * unknown/system errors become 500.
 */
function bookingFailureStatus(mapped: MappedError): number {
  if (mapped.code === 1205) return 409; // deadlock victim: safe retry
  if (mapped.code === 50021) return 409; // overlapping BOOKED booking
  if (mapped.code === 50011) return 403; // only CUSTOMER may book
  if (mapped.code !== null) return 400; // every other known THROW is a bad request
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
          .input('StartTime', sql.DateTime2(0), window.startSql)
          .input('EndTime', sql.DateTime2(0), window.endSql);
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
      const output = await sessionDb.withExistingConnection(sessionId, async (conn) => {
        const r = conn
          .request()
          .input('UserId', sql.UniqueIdentifier, user.userId)
          .input('CourtId', sql.UniqueIdentifier, courtId)
          .input('StartTime', sql.DateTime2(0), window.startSql)
          .input('EndTime', sql.DateTime2(0), window.endSql)
          .output('BookingId', sql.UniqueIdentifier)
          .output('TotalCost', sql.Decimal(12, 0));
        const result = await r.execute('dbo.sp_BookCourt');
        return {
          bookingId: result.output.BookingId as string | undefined,
          totalCost: result.output.TotalCost as number | undefined,
        };
      });

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
      res.status(bookingFailureStatus(mapped)).json(serializeError(mapped));
    }
  });

  return router;
}
