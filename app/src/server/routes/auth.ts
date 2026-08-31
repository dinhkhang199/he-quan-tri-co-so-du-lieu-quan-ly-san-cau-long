import { Router } from 'express';
import sql from 'mssql';
import type { UserRole } from '../../shared/contract.js';
import type { AuthUser } from '../../shared/types.js';
import { mapSqlError } from '../../shared/spError.js';
import type { MappedError } from '../../shared/spError.js';
import type { SessionDb } from '../db/index.js';
import { TooManySessionsError } from '../db/index.js';
import { runShared } from '../db/pool.js';
import { SESSION_COOKIE_NAME } from '../middleware/session.js';
import type { AppConfig } from '../config.js';
import {
  emailError,
  normalizeEmail,
  normalizePhone,
  normalizeUsername,
  passwordError,
  phoneError,
  resetCodeError,
  usernameError,
} from '../authValidation.js';
import { sendPasswordResetMail } from '../mail/passwordResetMail.js';

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

interface RegisterRow {
  UserId: string;
  Username: string;
  PhoneNumber: string;
  Email: string;
  Role: string;
  IsActive: boolean | number;
  CreatedAt: Date | string;
}

interface ResetRequestRow {
  ResetCode: string;
  ExpiresAt: Date | string;
  Email: string;
}

function maskEmail(value: string): string {
  const [localPart, domain] = value.split('@');
  if (!localPart || !domain) return '***';
  const visible = localPart.slice(0, Math.min(2, localPart.length));
  return `${visible}${'*'.repeat(Math.max(3, localPart.length - visible.length))}@${domain}`;
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
export function createAuthRouter(cfg: AppConfig, sessionDb: SessionDb): Router {
  const router = Router();

  router.post('/register', async (req, res) => {
    const body = (req.body ?? {}) as Record<string, unknown>;
    if (
      typeof body.username !== 'string' ||
      typeof body.phoneNumber !== 'string' ||
      typeof body.email !== 'string' ||
      typeof body.password !== 'string' ||
      typeof body.confirmPassword !== 'string'
    ) {
      res.status(400).json({ error: { code: null, message: 'Vui lòng nhập đầy đủ thông tin đăng ký.' } });
      return;
    }

    const username = normalizeUsername(body.username);
    const phoneNumber = normalizePhone(body.phoneNumber);
    const email = normalizeEmail(body.email);
    const validationError =
      usernameError(username) ?? phoneError(phoneNumber) ?? emailError(email) ?? passwordError(body.password);
    if (validationError) {
      res.status(400).json({ error: { code: null, message: validationError } });
      return;
    }
    if (body.password !== body.confirmPassword) {
      res.status(400).json({ error: { code: null, message: 'Mật khẩu xác nhận không khớp.' } });
      return;
    }

    try {
      const row = await runShared(cfg, async (request) => {
        const result = await request
          .input('Username', sql.NVarChar(50), username)
          .input('Password', sql.NVarChar(200), body.password)
          .input('Action', sql.NVarChar(20), 'REGISTER')
          .input('PhoneNumber', sql.NVarChar(20), phoneNumber)
          .input('Email', sql.NVarChar(254), email)
          .execute('dbo.sp_Login');
        return result.recordset[0] as RegisterRow | undefined;
      });
      if (!row) throw new Error('REGISTER returned no user row.');
      res.status(201).json({
        message: 'Đăng ký thành công. Bạn có thể đăng nhập ngay.',
        user: { userId: row.UserId, username: row.Username, role: row.Role },
      });
    } catch (err) {
      const mapped = mapSqlError(err);
      const status =
        mapped.code === 50201 || mapped.code === 50202 || mapped.code === 50204
          ? 409
          : mapped.code === null
            ? 500
            : 400;
      res.status(status).json({ error: serializeError(mapped) });
    }
  });

  router.post('/password/forgot', async (req, res) => {
    const body = (req.body ?? {}) as Record<string, unknown>;
    if (typeof body.username !== 'string' || typeof body.email !== 'string') {
      res.status(400).json({ error: { code: null, message: 'Vui lòng nhập tên đăng nhập và email.' } });
      return;
    }
    const username = normalizeUsername(body.username);
    const email = normalizeEmail(body.email);
    const validationError = usernameError(username) ?? emailError(email);
    if (validationError) {
      res.status(400).json({ error: { code: null, message: validationError } });
      return;
    }

    try {
      const row = await runShared(cfg, async (request) => {
        const result = await request
          .input('Username', sql.NVarChar(50), username)
          .input('Action', sql.NVarChar(20), 'REQUEST_RESET')
          .input('Email', sql.NVarChar(254), email)
          .execute('dbo.sp_Login');
        return result.recordset[0] as ResetRequestRow | undefined;
      });
      let emailSent = false;
      if (row) {
        try {
          emailSent = (await sendPasswordResetMail(cfg, row.Email, row.ResetCode)).sent;
        } catch (mailError) {
          console.error(`[auth] không thể gửi email khôi phục: ${String(mailError)}`);
          if (cfg.isProd) {
            res.status(503).json({
              error: { code: null, message: 'Chưa thể gửi email khôi phục. Vui lòng thử lại sau.' },
            });
            return;
          }
        }
      }
      res.json({
        message: 'Nếu thông tin khớp, mã khôi phục đã được gửi qua email và có hiệu lực trong 10 phút.',
        expiresInSeconds: 600,
        emailMasked: row ? maskEmail(row.Email) : undefined,
        ...(cfg.isProd || !row ? {} : { developmentCode: row.ResetCode, matched: true, emailSent }),
      });
    } catch (err) {
      const mapped = mapSqlError(err);
      // Không để lộ username/phone nào tồn tại. Sai danh tính vẫn nhận cùng thông báo 200.
      if (mapped.code === 50210) {
        res.json({
          message: 'Nếu thông tin khớp, mã khôi phục đã được gửi qua email và có hiệu lực trong 10 phút.',
          expiresInSeconds: 600,
          // Never expose this signal in production. It exists only so the
          // local classroom demo does not advance without an actual code.
          ...(cfg.isProd ? {} : { matched: false }),
        });
        return;
      }
      res.status(mapped.code === null ? 500 : 400).json({ error: serializeError(mapped) });
    }
  });

  router.post('/password/reset', async (req, res) => {
    const body = (req.body ?? {}) as Record<string, unknown>;
    if (
      typeof body.username !== 'string' ||
      typeof body.email !== 'string' ||
      typeof body.resetCode !== 'string' ||
      typeof body.password !== 'string' ||
      typeof body.confirmPassword !== 'string'
    ) {
      res.status(400).json({ error: { code: null, message: 'Vui lòng nhập đầy đủ thông tin đặt lại mật khẩu.' } });
      return;
    }
    const username = normalizeUsername(body.username);
    const email = normalizeEmail(body.email);
    const validationError =
      usernameError(username) ?? emailError(email) ?? resetCodeError(body.resetCode) ?? passwordError(body.password);
    if (validationError) {
      res.status(400).json({ error: { code: null, message: validationError } });
      return;
    }
    if (body.password !== body.confirmPassword) {
      res.status(400).json({ error: { code: null, message: 'Mật khẩu xác nhận không khớp.' } });
      return;
    }

    try {
      await runShared(cfg, async (request) => {
        await request
          .input('Username', sql.NVarChar(50), username)
          .input('Password', sql.NVarChar(200), body.password)
          .input('Action', sql.NVarChar(20), 'RESET_PASSWORD')
          .input('Email', sql.NVarChar(254), email)
          .input('ResetCode', sql.NVarChar(20), body.resetCode)
          .execute('dbo.sp_Login');
      });
      res.json({ message: 'Đổi mật khẩu thành công. Bạn có thể đăng nhập bằng mật khẩu mới.' });
    } catch (err) {
      const mapped = mapSqlError(err);
      res.status(mapped.code === null ? 500 : 400).json({ error: serializeError(mapped) });
    }
  });

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
      // IMP-11: đạt trần số phiên đồng thời → từ chối có kiểm soát (503) thay vì
      // mở thêm connection cho tới khi SQL Server Express hết worker/bộ nhớ.
      if (err instanceof TooManySessionsError) {
        console.error(`[auth] từ chối đăng nhập: đạt trần ${err.limit} phiên đồng thời`);
        res.setHeader('Retry-After', '30');
        res.status(503).json({
          error: {
            code: null,
            message: 'Hệ thống đang có quá nhiều người đăng nhập cùng lúc. Vui lòng thử lại sau ít phút.',
          },
        });
        return;
      }
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
