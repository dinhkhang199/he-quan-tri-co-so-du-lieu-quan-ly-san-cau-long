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

export interface SessionContextValues {
  userId: string | null;
  role: string | null;
}

export class SessionDb {
  private readonly sessions = new Map<string, SessionConnection>();
  private readonly cfg: AppConfig;

  constructor(cfg: AppConfig) {
    this.cfg = cfg;
  }

  /**
   * Create a fresh dedicated connection for a new authenticated session and run sp_Login.
   * This is the ONLY method that creates a new SessionDb connection pool.
   * If `fn` fails, the newly created connection is immediately disposed.
   */
  async createSession<T>(sessionId: string, fn: (conn: sql.ConnectionPool) => Promise<T>): Promise<T> {
    // If an old connection exists under this sessionId, close it first.
    await this.closeSession(sessionId).catch(() => undefined);

    const connConfig = buildSqlConfig(this.cfg);
    // Dedicated single-connection pool for the whole session. min = max = 1 keeps
    // the one connection (and its SESSION_CONTEXT) alive for the session lifetime;
    // tarn only reaps idle connections beyond the min, so this one is never closed
    // between requests (idleTimeoutMillis must be > 0 for tarn, hence 30000).
    connConfig.pool = { ...connConfig.pool, max: 1, min: 1, idleTimeoutMillis: 30000 };
    const conn = new sql.ConnectionPool(connConfig);
    await conn.connect();

    const holder: SessionConnection = { conn, queue: Promise.resolve() };
    this.sessions.set(sessionId, holder);

    try {
      const result = await fn(conn);
      return result;
    } catch (err) {
      await this.closeSession(sessionId).catch(() => undefined);
      throw err;
    }
  }

  /**
   * Run a callback on an EXISTING dedicated session connection, serialized.
   * This NEVER creates a new connection, NEVER reconnects, and NEVER rebuilds context.
   * If no live connection exists for `sessionId`, throws an Error.
   */
  async withExistingConnection<T>(sessionId: string, fn: (conn: sql.ConnectionPool) => Promise<T>): Promise<T> {
    const holder = this.sessions.get(sessionId);
    if (!holder || !holder.conn.connected) {
      throw new Error('No active SQL session connection');
    }
    const run = holder.queue.then(() => fn(holder.conn));
    holder.queue = run.catch(() => undefined);
    return run;
  }

  /** Standard access for authenticated calls; requires an existing connection. */
  async withConnection<T>(sessionId: string, fn: (conn: sql.ConnectionPool) => Promise<T>): Promise<T> {
    return this.withExistingConnection(sessionId, fn);
  }

  /**
   * Probes the actual SQL SESSION_CONTEXT on the existing dedicated connection.
   * NEVER creates a connection. Returns { userId, role } read directly from SQL.
   * If connection is missing or query fails, closes the session and returns null.
   */
  async getSessionContext(sessionId: string): Promise<SessionContextValues | null> {
    try {
      return await this.withExistingConnection(sessionId, async (conn) => {
        const result = await conn.request().query<{ UserId: string | null; Role: string | null }>(
          `SELECT
            CONVERT(nvarchar(36), SESSION_CONTEXT(N'UserId')) AS UserId,
            CONVERT(nvarchar(32), SESSION_CONTEXT(N'Role')) AS Role;`
        );
        const row = result.recordset[0];
        return {
          userId: row?.UserId ?? null,
          role: row?.Role ?? null,
        };
      });
    } catch {
      await this.closeSession(sessionId).catch(() => undefined);
      return null;
    }
  }

  /**
   * Verifies that the existing dedicated connection's SESSION_CONTEXT matches expected values.
   * Returns true ONLY if:
   * 1. A live SessionDb entry exists.
   * 2. SQL returns non-null UserId matching expectedUserId (case-insensitive).
   * 3. SQL returns non-null Role matching expectedRole exactly.
   * If verification fails for any reason, closes/evicts the session and returns false.
   */
  async verifySessionContext(sessionId: string, expectedUserId: string, expectedRole: string): Promise<boolean> {
    const ctx = await this.getSessionContext(sessionId);
    if (!ctx || !ctx.userId || !ctx.role) {
      await this.closeSession(sessionId).catch(() => undefined);
      return false;
    }
    const matches =
      ctx.userId.toLowerCase() === expectedUserId.toLowerCase() &&
      ctx.role === expectedRole;
    if (!matches) {
      await this.closeSession(sessionId).catch(() => undefined);
      return false;
    }
    return true;
  }

  /** Close the session's dedicated connection and evict it (discards SESSION_CONTEXT). */
  async closeSession(sessionId: string): Promise<void> {
    const holder = this.sessions.get(sessionId);
    if (!holder) return;
    this.sessions.delete(sessionId);
    await holder.queue.catch(() => undefined);
    try {
      await holder.conn.close();
    } catch {
      // Best-effort close
    }
  }

  /** True when a live dedicated connection is still registered for this session. */
  hasSession(sessionId: string): boolean {
    const holder = this.sessions.get(sessionId);
    return Boolean(holder && holder.conn.connected);
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