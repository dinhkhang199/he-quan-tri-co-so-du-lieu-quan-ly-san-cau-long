import { Router } from 'express';
import sql from 'mssql';
import type { UserRole } from '../../shared/contract.js';
import type { AuthUser } from '../../shared/types.js';
import { mapSqlError } from '../../shared/spError.js';
import type { MappedError } from '../../shared/spError.js';
import type { SessionDb } from '../db/index.js';
import { SESSION_COOKIE_NAME } from '../middleware/session.js';

declare module 'express-session' {
  interface SessionData {
    user?: AuthUser;
  }
}

/** Raw dbo.sp_Login result row (exact columns returned by the SP). */
interface LoginRow {
  UserId: string;
  Username: string;
  Role: string;
  IsActive: boolean | number;
  LastLogin: Date | string | null;
}

/** The only privileged application roles (GUEST exists in DB but is not a login role). */
const APP_ROLES: readonly UserRole[] = ['MANAGER', 'COURT_MANAGER', 'CUSTOMER'];
const UNAUTHENTICATED_MESSAGE = 'Chưa đăng nhập.';

function toIso(value: Date | string | null): string | null {
  if (value == null) return null;
  return value instanceof Date ? value.toISOString() : String(value);
}

/** Safe HTTP status for an auth failure mapped from the SQL error. */
function authFailureStatus(mapped: MappedError): number {
  if (mapped.code === 50001) return 401;
  if (mapped.code === 50002) return 403;
  // A system-level failure (connection, unknown code) is a server problem, not a 4xx business error.
  return mapped.code === null ? 500 : 400;
}

/** Serialize a failure for the HTTP client: code + safe Vietnamese message ONLY.
 * Raw SQL/driver detail is logged server-side and never serialized to the
 * response, in every environment (including dev). */
function serializeError(mapped: MappedError) {
  console.error(`[auth] request failed (code=${mapped.code ?? 'none'}): ${mapped.technical}`);
  return {
    code: mapped.code,
    message: mapped.message ?? mapped.fallback,
  };
}

/**
 * Authentication API. sp_Login runs exactly once on the session's dedicated
 * SQL connection (see SessionDb); that connection is kept for the web-session
 * lifetime so SESSION_CONTEXT survives. Session id is regenerated BEFORE the
 * dedicated connection is acquired, so the binding never points at an old id.
 */
export function createAuthRouter(sessionDb: SessionDb): Router {
  const router = Router();

  router.post('/login', async (req, res) => {
    const { username, password } = (req.body ?? {}) as { username?: unknown; password?: unknown };
    if (typeof username !== 'string' || username.length === 0 || typeof password !== 'string' || password.length === 0) {
      res.status(400).json({ error: { code: null, message: 'Vui lòng nhập tên đăng nhập và mật khẩu.' } });
      return;
    }

    const oldSessionId = req.session.id;
    try {
      await new Promise<void>((resolve, reject) => {
        req.session.regenerate((err) => (err ? reject(err) : resolve()));
      });
    } catch {
      res.status(500).json({ error: { code: null, message: 'Không thể khởi tạo phiên đăng nhập. Vui lòng thử lại.' } });
      return;
    }

    // Old binding (if any, e.g. a re-login) is keyed by the pre-regeneration id; drop it.
    const sessionId = req.session.id;
    await sessionDb.closeSession(oldSessionId).catch(() => undefined);

    let row: LoginRow | undefined;
    try {
      row = await sessionDb.createSession(sessionId, async (conn) => {
        const r = await conn
          .request()
          .input('Username', sql.NVarChar(50), username)
          .input('Password', sql.NVarChar(200), password)
          .execute('dbo.sp_Login');
        return r.recordset[0] as LoginRow | undefined;
      });
    } catch (err) {
      // createSession disposes the attempted connection on error
      const mapped = mapSqlError(err);
      res.status(authFailureStatus(mapped)).json({ error: serializeError(mapped) });
      return;
    }

    if (!row || !APP_ROLES.includes(row.Role as UserRole)) {
      await sessionDb.closeSession(sessionId).catch(() => undefined);
      res.status(403).json({ error: { code: null, message: 'Đăng nhập thất bại: tài khoản không có quyền truy cập.' } });
      return;
    }

    const user: AuthUser = {
      userId: row.UserId,
      username: row.Username,
      role: row.Role as UserRole,
      isActive: Boolean(row.IsActive),
      lastLogin: toIso(row.LastLogin),
    };
    req.session.user = user;
    res.json({ user });
  });

  router.get('/me', async (req, res) => {
    const user = req.session.user;
    if (!user) {
      res.status(401).json({ error: { code: null, message: UNAUTHENTICATED_MESSAGE } });
      return;
    }

    const sessionId = req.session.id;
    // Probe actual SQL SESSION_CONTEXT on the existing connection:
    // Requires that the connection exists in the registry AND that SQL returns
    // non-null SESSION_CONTEXT('UserId') and SESSION_CONTEXT('Role') matching user metadata.
    const isValid = await sessionDb.verifySessionContext(sessionId, user.userId, user.role);
    if (!isValid) {
      delete req.session.user;
      res.status(401).json({ error: { code: null, message: UNAUTHENTICATED_MESSAGE } });
      return;
    }

    res.json({ user });
  });

  router.post('/logout', async (req, res) => {
    // Closing the dedicated connection discards SESSION_CONTEXT; destroying the
    // Express session invalidates the web session. Both must stay idempotent.
    await sessionDb.closeSession(req.session.id).catch(() => undefined);
    await new Promise<void>((resolve) => {
      req.session.destroy(() => resolve());
    });
    res.clearCookie(SESSION_COOKIE_NAME);
    res.status(204).send();
  });

  return router;
}