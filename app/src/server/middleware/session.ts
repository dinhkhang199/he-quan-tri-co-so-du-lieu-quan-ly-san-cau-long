import session from 'express-session';
import type { AppConfig } from '../config.js';

/**
 * HTTP app-session cookie.
 * The SQL SESSION_CONTEXT binding happens inside SessionDb keyed by req.session.id;
 * the cookie itself carries only a session id, never UserId/Role/authorization truth.
 */
export function createSessionMiddleware(cfg: AppConfig) {
  return session({
    secret: cfg.sessionSecret,
    name: 'badmintonpro.sid',
    resave: false,
    saveUninitialized: false,
    cookie: {
      httpOnly: true,
      sameSite: 'lax',
      secure: false, // local dev over http; enable behind TLS in production
      maxAge: 1000 * 60 * 60 * 8, // 8h
    },
  });
}