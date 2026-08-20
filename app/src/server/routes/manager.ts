import { Router } from 'express';
import sql from 'mssql';
import type { SessionDb } from '../db/index.js';
import { mapSqlError } from '../../shared/spError.js';
import type { MappedError } from '../../shared/spError.js';
import { isValidGuid } from '../time.js';
import type {
  ManagerBooking,
  ManagerBookingsResponse,
  ManagerMutationResponse,
} from '../../shared/types.js';

/**
 * Manager / Court Manager booking management API (Phase 2.6) —
 * authenticated MANAGER / COURT_MANAGER only.
 *
 * GET  /api/manager/bookings
 * POST /api/manager/bookings/:bookingId/approve
 * POST /api/manager/bookings/:bookingId/reject
 * POST /api/manager/bookings/:bookingId/cancel
 * POST /api/manager/bookings/:bookingId/complete
 *
 * Every route runs on the authenticated SESSION_CONTEXT connection (SessionDb)
 * AFTER verifySessionContext(sessionId, userId, role):
 *   - the booking list is a FIXED SELECT from dbo.vw_AllBookings whose WHERE
 *     uses SESSION_CONTEXT(N'Role')/SESSION_CONTEXT(N'UserId') IN SQL, so
 *     COURT_MANAGER rows are scoped to `OwnerId = actor` BEFORE they leave SQL
 *     Server (the view exposes c.OwnerId as OwnerId, 05_views.sql);
 *   - every mutation executes dbo.sp_ApproveBooking / sp_RejectBooking /
 *     sp_CancelBooking / sp_CompleteBooking, which re-validate role, ownership,
 *     state and (for approve) overlap under lock inside the procedure.
 *
 * The request never carries UserId/Role/OwnerId/Status; the only client input is
 * the bookingId route parameter (validated as a GUID). Authorization truth is
 * the SQL SESSION_CONTEXT + these Stored Procedures — never the browser.
 */

/**
 * Serialize a failure for the HTTP client: code + safe Vietnamese message ONLY.
 * Raw SQL/driver detail is logged server-side and must never be serialized into
 * the HTTP response in any environment.
 */
function serializeError(mapped: MappedError) {
  console.error(`[manager] request failed (code=${mapped.code ?? 'none'}): ${mapped.technical}`);
  return {
    code: mapped.code,
    message: mapped.message ?? mapped.fallback,
  };
}

/**
 * Safe HTTP status for a dbo.sp_ApproveBooking/RejectBooking/CancelBooking/
 * CompleteBooking failure (exact THROW codes from 06_procedures.sql).
 * Session/actor codes reuse the SQL number for both the "no active user" and
 * SESSION_CONTEXT checks; the route already gated role, so if one of these
 * fires the caller's web identity is out of sync with SQL → 401 + re-login.
 */
function managerMutationStatus(mapped: MappedError): number {
  if (mapped.code === 1205) return 409; // deadlock victim: safe manual retry
  if (mapped.code === 50032 || mapped.code === 50041 || mapped.code === 50051 || mapped.code === 50061) return 404; // not found
  if (mapped.code === 50033 || mapped.code === 50042 || mapped.code === 50054 || mapped.code === 50056 || mapped.code === 50063) return 403; // ownership / self-only
  if (
    mapped.code === 50034 || // only PENDING may approve
    mapped.code === 50035 || // approve overlap with an existing BOOKED
    mapped.code === 50043 || // only PENDING may reject
    mapped.code === 50052 || // COMPLETED/REJECTED cannot cancel
    mapped.code === 50053 || // already CANCELLED
    mapped.code === 50055 || // (defensive) customer 3h rule
    mapped.code === 50058 || // cancel race
    mapped.code === 50062 || // only BOOKED may complete
    mapped.code === 50064 || // complete race
    mapped.code === 51000 || // invalid state transition (trigger)
    mapped.code === 51001 // overlap with existing BOOKED (trigger)
  )
    return 409; // state/deadline/overlap conflict
  if (mapped.code === 50031 || mapped.code === 50057) return 403; // insufficient role
  if (mapped.code === 50030 || mapped.code === 50040 || mapped.code === 50050 || mapped.code === 50060) return 401; // actor/session mismatch
  return mapped.code === null ? 500 : 500;
}

/** Safe HTTP status for the booking-list read (a view SELECT, not an SP THROW). */
function managerListStatus(mapped: MappedError): number {
  if (mapped.code === 1205) return 409; // read deadlock victim: safe retry
  return 500;
}

export function createManagerRouter(sessionDb: SessionDb): Router {
  const router = Router();

  /**
   * GET /api/manager/bookings — authenticated manager booking list (Phase 2.6).
   *
   * The scope is NOT applied in Node/React — it is applied in the SQL WHERE
   * clause using SESSION_CONTEXT on the authenticated session connection:
   *   MANAGER          → all rows
   *   COURT_MANAGER    → only rows whose OwnerId = SESSION_CONTEXT('UserId')
   * The @param binding carries nothing user-derived; identity comes from the
   * verified SQL session only. Columns are the explicit vw_AllBookings columns.
   */
  router.get('/', async (req, res) => {
    const user = req.session.user;
    if (!user) {
      res.status(401).json({ error: { code: null, message: 'Chưa đăng nhập.' } });
      return;
    }
    if (user.role !== 'MANAGER' && user.role !== 'COURT_MANAGER') {
      res.status(403).json({ error: { code: null, message: 'Chỉ MANAGER/COURT_MANAGER được xem danh sách booking.' } });
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
        // Explicit safe columns from dbo.vw_AllBookings (05_views.sql). The view
        // exposes c.OwnerId AS OwnerId — the court-owner scope for COURT_MANAGER.
        const result = await conn.request().query<ManagerBooking>(`
          SELECT
            BookingId,
            UserId,
            CustomerUsername,
            CustomerPhone,
            CourtId,
            CourtName,
            SurfaceType,
            SizeType,
            OwnerId,
            PricePerHour,
            StartTime,
            EndTime,
            Status,
            StatusLabel,
            TotalCost,
            CreatedAt,
            UpdatedAt
          FROM dbo.vw_AllBookings
          WHERE
            CONVERT(nvarchar(20), SESSION_CONTEXT(N'Role')) = N'MANAGER'
            OR (
              CONVERT(nvarchar(20), SESSION_CONTEXT(N'Role')) = N'COURT_MANAGER'
              AND OwnerId = TRY_CONVERT(uniqueidentifier, SESSION_CONTEXT(N'UserId'))
            )
          ORDER BY StartTime DESC;
        `);
        return result.recordset;
      });

      const body: ManagerBookingsResponse = {
        bookings: rows.map((row) => ({
          ...row,
          Status: row.Status as ManagerBooking['Status'],
          TotalCost: Number(row.TotalCost ?? 0),
          PricePerHour: Number(row.PricePerHour ?? 0),
        })),
        count: rows.length,
      };
      res.json(body);
    } catch (err) {
      if (err instanceof Error && err.message === 'No active SQL session connection') {
        delete req.session.user;
        res.status(401).json({ error: { code: null, message: 'Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại.' } });
        return;
      }
      const mapped = mapSqlError(err);
      res.status(managerListStatus(mapped)).json({ error: serializeError(mapped) });
    }
  });

  function runMutation(action: 'approve' | 'reject' | 'cancel' | 'complete') {
    const SP: Record<typeof action, string> = {
      approve: 'dbo.sp_ApproveBooking',
      reject: 'dbo.sp_RejectBooking',
      cancel: 'dbo.sp_CancelBooking',
      complete: 'dbo.sp_CompleteBooking',
    };
    const NEW_STATUS: Record<typeof action, ManagerMutationResponse['status']> = {
      approve: 'BOOKED',
      reject: 'REJECTED',
      cancel: 'CANCELLED',
      complete: 'COMPLETED',
    };

    return async (req: Parameters<Parameters<Router['post']>[1]>[0], res: Parameters<Parameters<Router['post']>[1]>[1]) => {
      const user = req.session.user;
      if (!user) {
        res.status(401).json({ error: { code: null, message: 'Chưa đăng nhập.' } });
        return;
      }
      if (user.role !== 'MANAGER' && user.role !== 'COURT_MANAGER') {
        res.status(403).json({ error: { code: null, message: 'Chỉ MANAGER/COURT_MANAGER được thao tác booking.' } });
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
        await sessionDb.withExistingConnection(sessionId, async (conn) => {
          const r = conn
            .request()
            .input('SessionUserId', sql.UniqueIdentifier, user.userId)
            .input('BookingId', sql.UniqueIdentifier, rawBookingId);
          await r.execute(SP[action]);
        });

        const body: ManagerMutationResponse = { bookingId: rawBookingId, status: NEW_STATUS[action] };
        res.json(body);
      } catch (err) {
        if (err instanceof Error && err.message === 'No active SQL session connection') {
          delete req.session.user;
          res.status(401).json({ error: { code: null, message: 'Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại.' } });
          return;
        }
        const mapped = mapSqlError(err);
        if (mapped.code === 50030 || mapped.code === 50040 || mapped.code === 50050 || mapped.code === 50060) {
          // Actor/session problem reported by the SP → re-login required.
          delete req.session.user;
          res.status(401).json({ error: { code: null, message: mapped.message ?? 'Phiên đăng nhập không hợp lệ. Vui lòng đăng nhập lại.' } });
          return;
        }
        res.status(managerMutationStatus(mapped)).json({ error: serializeError(mapped) });
      }
    };
  }

  router.post('/:bookingId/approve', runMutation('approve'));
  router.post('/:bookingId/reject', runMutation('reject'));
  router.post('/:bookingId/cancel', runMutation('cancel'));
  router.post('/:bookingId/complete', runMutation('complete'));

  return router;
}