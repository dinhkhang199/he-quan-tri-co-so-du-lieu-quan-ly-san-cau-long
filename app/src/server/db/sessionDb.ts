/**
 * SessionDb — the SESSION_CONTEXT-safe data access mechanism.
 *
 * Phase 1 uses Option A session security: `sp_Login` sets SESSION_CONTEXT('UserId')
 * / SESSION_CONTEXT('Role') on the CURRENT SQL connection, and `bcm_app` is DENYed
 * direct EXECUTE on sys.sp_set_session_context (it cannot fake a context itself).
 * All protected procedures (sp_GetMyBookings, sp_BookCourt, ...) read that context.
 *
 * => Every authenticated app session holds ONE dedicated SQL connection for the
 *    session lifetime. sp_Login runs exactly once on it; all later protected calls
 *    for that user run on the SAME connection so the context always exists and is
 *    never spliced across pooled connections. On logout/expiry the connection is
 *    closed, which discards the context.
 *
 * Work within a session is serialized so two concurrent requests can never
 * interleave SESSION_CONTEXT state on the same connection.
 *
 * mssql v11 removed the module-level Connection class: the dedicated connection
 * is a ConnectionPool capped at pool.max = 1, guaranteeing exactly one underlying
 * SQL connection for the whole session.
 */
import sql from 'mssql';
import type { AppConfig } from '../config.js';
import { buildSqlConfig } from './connection.js';

interface SessionConnection {
  conn: sql.ConnectionPool;
  /** Promise chain that serializes work on this connection. */
  queue: Promise<unknown>;
}

export class SessionDb {
  private readonly sessions = new Map<string, SessionConnection>();
  private readonly cfg: AppConfig;

  constructor(cfg: AppConfig) {
    this.cfg = cfg;
  }

  /** Run a callback on the session's dedicated connection, serialized. */
  async withConnection<T>(sessionId: string, fn: (conn: sql.ConnectionPool) => Promise<T>): Promise<T> {
    const holder = await this.acquire(sessionId);
    const run = holder.queue.then(() => fn(holder.conn));
    holder.queue = run.catch(() => undefined);
    return run;
  }

  /** Create the dedicated connection for a session on first use. */
  private async acquire(sessionId: string): Promise<SessionConnection> {
    const existing = this.sessions.get(sessionId);
    if (existing) return existing;

    const connConfig = buildSqlConfig(this.cfg);
    connConfig.pool = { ...connConfig.pool, max: 1, min: 1, idleTimeoutMillis: 0 };
    const conn = new sql.ConnectionPool(connConfig);
    await conn.connect();
    const holder: SessionConnection = { conn, queue: Promise.resolve() };
    this.sessions.set(sessionId, holder);
    return holder;
  }

  /** Close the session's dedicated connection and evict it (discards SESSION_CONTEXT). */
  async closeSession(sessionId: string): Promise<void> {
    const holder = this.sessions.get(sessionId);
    if (!holder) return;
    this.sessions.delete(sessionId);
    await holder.queue.catch(() => undefined);
    await holder.conn.close();
  }

  /** Number of live session connections (diagnostics/health). */
  activeCount(): number {
    return this.sessions.size;
  }

  /** Close every session connection (server shutdown). */
  async closeAll(): Promise<void> {
    const ids = [...this.sessions.keys()];
    await Promise.all(ids.map((id) => this.closeSession(id)));
  }
}