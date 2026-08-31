import { Router } from 'express';
import sql from 'mssql';
import type { UserRole } from '../../shared/contract.js';
import type { AuthUser } from '../../shared/types.js';
import { mapSqlError } from '../../shared/spError.js';
import type { MappedError } from '../../shared/spError.js';
import type { AppConfig } from '../config.js';
import { runShared, type SessionDb } from '../db/index.js';
import { SESSION_COOKIE_NAME } from '../middleware/session.js';
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

/** Raw dbo.sp_Register result row. */
interface RegisterRow {
  UserId: string;
  Username: string;
  Role: string;
  PhoneNumber: string;
  Email: string | null;
  IsActive: boolean | number;
  CreatedAt: Date | string;
}

/** Raw dbo.sp_RequestPasswordReset result row. */
interface ResetRequestRow {
  UserId: string;
  Username: string;
  Email: string;
  ResetCode: string;
  ExpiresAt: Date | string;
}

/** The only privileged application roles (GUEST exists in DB but is not a login role). */
const APP_ROLES: readonly UserRole[] = ['MANAGER', 'COURT_MANAGER', 'CUSTOMER'];
const UNAUTHENTICATED_MESSAGE = 'Chưa đăng nhập.';

function toIso(value: Date | string | null): string | null {
  if (value == null) return null;
  return value instanceof Date ? value.toISOString() : String(value);
}

function maskEmail(email: string): string {
  const atIndex = email.indexOf('@');
  if (atIndex <= 1) return email;
  const user = email.slice(0, atIndex);
  const domain = email.slice(atIndex);
  const visible = user.slice(0, Math.min(2, user.length));
  return `${visible}***${domain}`;
}

/** Safe HTTP status for an auth failure mapped from the SQL error. */
function authFailureStatus(mapped: MappedError): number {
  if (mapped.code === 50001) return 401;
  if (mapped.code === 50002) return 403;
  if (mapped.code === 50201 || mapped.code === 50202 || mapped.code === 50204) return 409;
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
 * Authentication API.
 * - sp_Register: public registration of new CUSTOMER accounts via shared connection pool.
 * - sp_RequestPasswordReset: request OTP recovery code via email/shared connection.
 * - sp_ResetPassword: reset password with valid OTP via shared connection.
 * - sp_Login: runs exactly once on the session's dedicated SQL connection (see SessionDb);
 *   that connection is kept for the web-session lifetime so SESSION_CONTEXT survives.
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
      res.status(400).json({ error: { code: null, message: 'Vui lòng nhập đầy đủ thông tin đăng ký bao gồm email.' } });
      return;
    }

    const username = normalizeUsername(body.username);
    const phoneNumber = normalizePhone(body.phoneNumber);
    const email = normalizeEmail(body.email);

    const validationError =
      usernameError(username) ??
      phoneError(phoneNumber) ??
      emailError(email) ??
      passwordError(body.password);

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
          .input('PhoneNumber', sql.NVarChar(20), phoneNumber)
          .input('Email', sql.NVarChar(254), email)
          .execute('dbo.sp_Register');
        return result.recordset[0] as RegisterRow | undefined;
      });

      if (!row) throw new Error('sp_Register returned no user row.');

      res.status(201).json({
        message: 'Đăng ký thành công. Bạn có thể đăng nhập ngay.',
        user: { userId: row.UserId, username: row.Username, role: row.Role },
      });
    } catch (err) {
      const mapped = mapSqlError(err);
      res.status(authFailureStatus(mapped)).json({ error: serializeError(mapped) });
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
          .input('Email', sql.NVarChar(254), email)
          .execute('dbo.sp_RequestPasswordReset');
        return result.recordset[0] as ResetRequestRow | undefined;
      });

      let emailSent = false;
      if (row) {
        try {
          emailSent = (await sendPasswordResetMail(cfg, row.Email, row.ResetCode)).sent;
        } catch (mailError) {
          console.error(`[auth] không thể gửi email khôi phục: ${String(mailError)}`);
          // In production, do not return 503 to avoid side-channel account enumeration.
          // Failure is logged server-side and identical generic 200 response is returned.
        }
      }

      const baseResponse = {
        message: 'Nếu thông tin khớp, mã khôi phục đã được gửi qua email và có hiệu lực trong 10 phút.',
        expiresInSeconds: 600,
      };

      if (cfg.isProd) {
        res.json(baseResponse);
        return;
      }

      res.json({
        ...baseResponse,
        matched: true,
        emailMasked: row ? maskEmail(row.Email) : undefined,
        emailSent,
        ...(row?.ResetCode ? { developmentCode: row.ResetCode } : {}),
      });
    } catch (err) {
      const mapped = mapSqlError(err);
      // Account enumeration protection: return identical generic message on unknown user
      if (mapped.code === 50210) {
        const baseResponse = {
          message: 'Nếu thông tin khớp, mã khôi phục đã được gửi qua email và có hiệu lực trong 10 phút.',
          expiresInSeconds: 600,
        };
        if (cfg.isProd) {
          res.json(baseResponse);
          return;
        }
        res.json({
          ...baseResponse,
          matched: false,
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
          .input('Email', sql.NVarChar(254), email)
          .input('ResetCode', sql.NVarChar(20), body.resetCode)
          .input('NewPassword', sql.NVarChar(200), body.password)
          .execute('dbo.sp_ResetPassword');
      });

      res.json({ message: 'Đổi mật khẩu thành công. Bạn có thể đăng nhập bằng mật khẩu mới.' });
    } catch (err) {
      const mapped = mapSqlError(err);
      if (mapped.code === 50210 || mapped.code === 50211 || mapped.code === 50212) {
        console.error(`[auth] reset password rejected (code=${mapped.code}): ${mapped.message}`);
        res.status(400).json({
          error: {
            code: null,
            message: 'Mã khôi phục hoặc thông tin tài khoản không hợp lệ.',
          },
        });
        return;
      }
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
