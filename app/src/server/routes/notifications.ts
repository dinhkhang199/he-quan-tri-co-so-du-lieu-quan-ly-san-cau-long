import { Router } from 'express';
import sql from 'mssql';
import type { SessionDb } from '../db/index.js';
import { mapSqlError } from '../../shared/spError.js';
import type { MappedError } from '../../shared/spError.js';
import { isValidGuid } from '../time.js';
import type {
  MarkNotificationReadResponse,
  Notification,
  NotificationsResponse,
} from '../../shared/types.js';

/**
 * Shared authenticated notification API (Phase 2.6) —
 * CUSTOMER / MANAGER / COURT_MANAGER.
 *
 * GET  /api/notifications                list actor's notifications
 * POST /api/notifications/:id/read       mark one notification read
 *
 * Every route runs on the authenticated SESSION_CONTEXT connection (SessionDb)
 * AFTER verifySessionContext(sessionId, userId, role):
 *   - dbo.sp_GetNotifications derives the actor ONLY from SESSION_CONTEXT and
 *     rejects any caller-supplied UserId that differs (THROW 51060);
 *   - dbo.sp_MarkNotificationRead updates only rows WHERE NotificationId = ...
 *     AND UserId = SESSION_CONTEXT actor (THROW 50100 when nothing matches);
 *   - the notification table has NO direct SELECT/UPDATE grant — the SPs are
 *     the ONLY access path (they run WITH EXECUTE AS OWNER).
 *
 * Identification is USER-specific: a MANAGER does not see other users'
 * notifications; the SP simply returns the authenticated actor's rows. The
 * request never carries UserId/Role/IsRead/BookingId — the browser sends only
 * the validated NotificationId route parameter for mark-read. Authorization
 * truth is the SQL SESSION_CONTEXT + the procedures — never the browser.
 */

/** Serialize a failure for the HTTP client: code + safe Vietnamese message ONLY. */
function serializeError(mapped: MappedError) {
  console.error(`[notifications] request failed (code=${mapped.code ?? 'none'}): ${mapped.technical}`);
  return {
    code: mapped.code,
    message: mapped.message ?? mapped.fallback,
  };
}

/** Safe HTTP status for the read mutation (exact THROW codes from 06_procedures.sql). */
function readStatus(mapped: MappedError): number {
  if (mapped.code === 1205) return 409; // deadlock victim: safe manual retry
  if (mapped.code === 50100) return 404; // notification not found for this user
  return 500;
}

/** Safe HTTP status for the notification list read. */
function listStatus(mapped: MappedError): number {
  if (mapped.code === 1205) return 409; // read deadlock victim: safe retry
  return 500;
}

/** The SP works for any authenticated actor (no role check); GUI roles only. */
function isNotificationRole(role: string): boolean {
  return role === 'CUSTOMER' || role === 'MANAGER' || role === 'COURT_MANAGER';
}

export function createNotificationsRouter(sessionDb: SessionDb): Router {
  const router = Router();

  /**
   * GET /api/notifications — the authenticated actor's notifications.
   * The actor is derived IN SQL by dbo.sp_GetNotifications from SESSION_CONTEXT
   * ('UserId', 'Role' set by sp_Login); @UserId is the server-derived session
   * user and the SP re-validates it against the context (impersonation -> 51060).
   */
  router.get('/', async (req, res) => {
    const user = req.session.user;
    if (!user) {
      res.status(401).json({ error: { code: null, message: 'Chưa đăng nhập.' } });
      return;
    }
    if (!isNotificationRole(user.role)) {
      res.status(403).json({ error: { code: null, message: 'Tài khoản không được phép xem thông báo.' } });
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
        const result = await conn
          .request()
          .input('UserId', sql.UniqueIdentifier, user.userId)
          .input('UnreadOnly', sql.Bit, false)
          .execute('dbo.sp_GetNotifications');
        return result.recordset as Notification[];
      });

      const body: NotificationsResponse = {
        notifications: rows.map((row) => ({
          NotificationId: row.NotificationId,
          UserId: row.UserId,
          BookingId: row.BookingId ?? null,
          Message: row.Message,
          IsRead: Boolean(row.IsRead),
          CreatedAt: row.CreatedAt,
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
      if (mapped.code === 51060) {
        // Actor/session problem reported by the SP -> re-login required.
        delete req.session.user;
        res.status(401).json({ error: { code: null, message: mapped.message ?? 'Phiên đăng nhập không hợp lệ. Vui lòng đăng nhập lại.' } });
        return;
      }
      res.status(listStatus(mapped)).json(serializeError(mapped));
    }
  });

  /**
   * POST /api/notifications/:notificationId/read — mark one notification read.
   * dbo.sp_MarkNotificationRead enforces ownership in SQL: it UPDATEs only
   * WHERE NotificationId = @NotificationId AND UserId = the SESSION_CONTEXT
   * actor. A foreign/unknown NotificationId matches nothing -> THROW 50100 and
   * the target notification is left unchanged (the actor stays authenticated).
   */
  router.post('/:notificationId/read', async (req, res) => {
    const user = req.session.user;
    if (!user) {
      res.status(401).json({ error: { code: null, message: 'Chưa đăng nhập.' } });
      return;
    }
    if (!isNotificationRole(user.role)) {
      res.status(403).json({ error: { code: null, message: 'Tài khoản không được phép thao tác thông báo.' } });
      return;
    }

    const sessionId = req.session.id;
    const contextOk = await sessionDb.verifySessionContext(sessionId, user.userId, user.role);
    if (!contextOk) {
      delete req.session.user;
      res.status(401).json({ error: { code: null, message: 'Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại.' } });
      return;
    }

    const rawNotificationId = req.params.notificationId;
    if (!isValidGuid(rawNotificationId)) {
      res.status(400).json({ error: { code: null, message: 'Mã thông báo không hợp lệ.' } });
      return;
    }

    try {
      await sessionDb.withExistingConnection(sessionId, async (conn) => {
        const r = conn
          .request()
          .input('SessionUserId', sql.UniqueIdentifier, user.userId)
          .input('NotificationId', sql.UniqueIdentifier, rawNotificationId);
        await r.execute('dbo.sp_MarkNotificationRead');
      });

      const body: MarkNotificationReadResponse = { notificationId: rawNotificationId };
      res.json(body);
    } catch (err) {
      if (err instanceof Error && err.message === 'No active SQL session connection') {
        delete req.session.user;
        res.status(401).json({ error: { code: null, message: 'Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại.' } });
        return;
      }
      const mapped = mapSqlError(err);
      if (mapped.code === 51061) {
        // Actor/session problem reported by the SP -> re-login required.
        delete req.session.user;
        res.status(401).json({ error: { code: null, message: mapped.message ?? 'Phiên đăng nhập không hợp lệ. Vui lòng đăng nhập lại.' } });
        return;
      }
      res.status(readStatus(mapped)).json(serializeError(mapped));
    }
  });

  return router;
}