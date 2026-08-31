/**
 * Server configuration.
 * Secrets are read from process.env (loaded from app/.env in dev; see .env.example).
 * No real secrets are committed.
 */

export interface AppConfig {
  dbServer: string;
  dbPort: number | null;
  dbDatabase: string;
  dbUser: string;
  dbPassword: string;
  dbTrustServerCertificate: boolean;
  dbPoolMax: number;
  dbConnectTimeoutMs: number;
  sessionSecret: string;
  sessionTtlMs: number;
  sessionIdleTimeoutMs: number;
  sessionSweepIntervalMs: number;
  loginRateLimitPerMinute: number;
  port: number;
  isProd: boolean;
  serveClient: boolean;
}

/** Read one env value with a required check (config template prohibits committed secrets). */
function required(name: string): string {
  const value = process.env[name];
  if (!value || value.startsWith('__CHANGE_ME')) {
    throw new Error(`Missing config: ${name}. Copy app/.env.example to app/.env and fill it.`);
  }
  return value;
}

export function loadConfig(): AppConfig {
  return {
    dbServer: process.env.DB_SERVER ?? 'localhost\\SQLEXPRESS',
    dbPort: process.env.DB_PORT ? Number(process.env.DB_PORT) : null,
    dbDatabase: process.env.DB_DATABASE ?? 'BadmintonCourtManagement',
    dbUser: required('DB_USER'),
    dbPassword: required('DB_PASSWORD'),
    dbTrustServerCertificate: (process.env.DB_TRUST_SERVER_CERTIFICATE ?? 'true') === 'true',
    dbPoolMax: Number(process.env.DB_CONNECTION_POOL_MAX ?? 10),
    dbConnectTimeoutMs: Number(process.env.DB_CONNECT_TIMEOUT_MS ?? 5000),
    sessionSecret: required('SESSION_SECRET'),
    sessionTtlMs: Number(process.env.SESSION_TTL_MS ?? 1000 * 60 * 60 * 8),
    sessionIdleTimeoutMs: Number(process.env.SESSION_IDLE_TIMEOUT_MS ?? 1000 * 60 * 30),
    sessionSweepIntervalMs: Number(process.env.SESSION_SWEEP_INTERVAL_MS ?? 1000 * 60),
    loginRateLimitPerMinute: Number(process.env.LOGIN_RATE_LIMIT_PER_MINUTE ?? 60),
    port: Number(process.env.APP_PORT ?? 3000),
    isProd: process.env.NODE_ENV === 'production',
    serveClient: process.argv.includes('--serve-client'),
  };
}
