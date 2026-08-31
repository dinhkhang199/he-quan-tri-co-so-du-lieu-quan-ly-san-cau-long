import session from 'express-session';
import type { AppConfig } from '../config.js';

/** Cookie name for the app web session (also used to clear it on logout). */
export const SESSION_COOKIE_NAME = 'badmintonpro.sid';

/**
 * HTTP app-session cookie.
 * The SQL SESSION_CONTEXT binding happens inside SessionDb keyed by req.session.id;
 * the cookie itself carries only a session id, never UserId/Role/authorization truth.
 */
export function createSessionMiddleware(cfg: AppConfig) {
  return session({
    secret: cfg.sessionSecret,
    name: SESSION_COOKIE_NAME,
    resave: false,
    saveUninitialized: false,
    rolling: false,
    cookie: {
      httpOnly: true,
      sameSite: 'lax',
      secure: cfg.isProd,
      maxAge: cfg.sessionTtlMs,
    },
  });
}
