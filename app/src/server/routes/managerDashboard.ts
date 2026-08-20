import { Router } from 'express';
import sql from 'mssql';
import type { SessionDb } from '../db/index.js';
import { mapSqlError } from '../../shared/spError.js';
import type { MappedError } from '../../shared/spError.js';
import type {
  DashboardDailyRevenue,
  DashboardOverview,
  DashboardTopCourt,
  ManagerDashboardResponse,
} from '../../shared/types.js';

/**
 * Manager / Court Manager dashboard API (Phase 2.9) —
 * authenticated MANAGER / COURT_MANAGER only.
 *
 * GET /api/manager/dashboard
 *
 * The route runs on the authenticated SESSION_CONTEXT connection (SessionDb)
 * AFTER verifySessionContext(sessionId, userId, role):
 *   - dbo.sp_GetDashboard derives the actor ONLY from SESSION_CONTEXT, rejects
 *     a caller-supplied @SessionUserId that differs (THROW 50110), and applies
 *     the role/owner scope INSIDE SQL Server:
 *       MANAGER        -> system-wide aggregates;
 *       COURT_MANAGER  -> aggregates filtered to courts WHERE c.OwnerId =
 *                         SESSION_CONTEXT('UserId') (the aggregate never leaves
 *                         SQL unscoped — nothing is filtered in Node/React);
 *   - ActiveUsers is the DB-wide count of dbo.Users WHERE IsActive = 1 in both
 *     branches (that is what the procedure computes); TheoreticalRevenue is the
 *     sum of TotalCost for BOOKED + COMPLETED bookings in the scoped branch.
 *
 * The request never carries UserId/Role/OwnerId/scope; the only client input is
 * the authenticated web + SQL session. Authorization truth is the SQL
 * SESSION_CONTEXT + the Stored Procedure — never the browser.
 */

/** Serialize a failure for the HTTP client: code + safe Vietnamese message ONLY. */
function serializeError(mapped: MappedError) {
  console.error(`[managerDashboard] request failed (code=${mapped.code ?? 'none'}): ${mapped.technical}`);
  return {
    code: mapped.code,
    message: mapped.message ?? mapped.fallback,
  };
}

/**
 * Safe HTTP status for an sp_GetDashboard failure (exact THROW codes from
 * 06_procedures.sql). 50110 also covers the "session missing" case; the route
 * already gated role, so if it fires the web identity is out of sync with SQL.
 */
function dashboardStatus(mapped: MappedError): number {
  if (mapped.code === 1205) return 409; // deadlock victim: safe manual retry
  return 500;
}

export function createManagerDashboardRouter(sessionDb: SessionDb): Router {
  const router = Router();

  /**
   * GET /api/manager/dashboard — the actor's dashboard aggregates.
   *
   * The scope is NOT applied in Node/React — it is applied INSIDE
   * dbo.sp_GetDashboard from SESSION_CONTEXT on the authenticated session
   * connection. The @SessionUserId param binding carries the server-derived
   * session user only; the SP re-validates it against the context
   * (impersonation -> 50110). The three result sets are mapped by exact order.
   */
  router.get('/', async (req, res) => {
    const user = req.session.user;
    if (!user) {
      res.status(401).json({ error: { code: null, message: 'Chưa đăng nhập.' } });
      return;
    }
    if (user.role !== 'MANAGER' && user.role !== 'COURT_MANAGER') {
      res.status(403).json({ error: { code: null, message: 'Chỉ MANAGER/COURT_MANAGER được xem dashboard.' } });
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
      const result = await sessionDb.withExistingConnection(sessionId, async (conn) => {
        const r = conn.request().input('SessionUserId', sql.UniqueIdentifier, user.userId);
        return await r.execute('dbo.sp_GetDashboard');
      });

      // Exact result-set order from 06_procedures.sql:
      // [0] overview, [1] daily revenue (7-day window), [2] top courts.
      const [overviewRows, dailyRows, topCourtRows] = result.recordsets as unknown as [
        DashboardOverview[],
        DashboardDailyRevenue[],
        DashboardTopCourt[],
      ];

      const overviewRow = overviewRows?.[0];
      const overview: DashboardOverview = {
        PendingCount: Number(overviewRow?.PendingCount ?? 0),
        BookedCount: Number(overviewRow?.BookedCount ?? 0),
        TheoreticalRevenue: Number(overviewRow?.TheoreticalRevenue ?? 0),
        ActiveUsers: Number(overviewRow?.ActiveUsers ?? 0),
      };

      const daily: DashboardDailyRevenue[] = (dailyRows ?? []).map((row) => ({
        Date: row.Date,
        DailyRevenue: Number(row.DailyRevenue ?? 0),
      }));

      const topCourts: DashboardTopCourt[] = (topCourtRows ?? []).map((row) => ({
        CourtName: String(row.CourtName ?? ''),
        BookingCount: Number(row.BookingCount ?? 0),
        Revenue: Number(row.Revenue ?? 0),
      }));

      const body: ManagerDashboardResponse = { overview, daily, topCourts };
      res.json(body);
    } catch (err) {
      if (err instanceof Error && err.message === 'No active SQL session connection') {
        delete req.session.user;
        res.status(401).json({ error: { code: null, message: 'Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại.' } });
        return;
      }
      const mapped = mapSqlError(err);
      if (mapped.code === 50110) {
        // Actor/session problem reported by the SP -> re-login required.
        delete req.session.user;
        res.status(401).json({ error: { code: null, message: mapped.message ?? 'Phiên đăng nhập không hợp lệ. Vui lòng đăng nhập lại.' } });
        return;
      }
      res.status(dashboardStatus(mapped)).json({ error: serializeError(mapped) });
    }
  });

  return router;
}