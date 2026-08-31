/**
 * Server configuration.
 * Secrets are read from process.env (loaded from app/.env in dev; see .env.example).
 * No real secrets are committed.
 */

export interface AppConfig {
  dbServer: string;
  /** Optional fixed TCP port; avoids flaky SQL Browser instance discovery. */
  dbPort: number | null;
  dbDatabase: string;
  dbUser: string;
  dbPassword: string;
  dbTrustServerCertificate: boolean;
  dbPoolMax: number;
  dbConnectTimeoutMs: number;
  /** Optional SMTP relay. Required in production for email password recovery. */
  smtpHost: string | null;
  smtpPort: number;
  smtpSecure: boolean;
  smtpUser: string | null;
  smtpPassword: string | null;
  mailFrom: string | null;
  /** LOCK_TIMEOUT (ms) đặt trên connection của app; -1 = chờ vô hạn (mặc định SQL Server). */
  dbLockTimeoutMs: number;
  /** Trần số phiên đăng nhập đồng thời (mỗi phiên giữ 1 connection SQL); 0 = không giới hạn. */
  maxSessionConnections: number;
  /** Số lần gọi POST /api/auth/login tối đa mỗi phút cho một IP; 0 = tắt. */
  loginRateLimitPerMinute: number;
  /** Public register/forgot/reset requests per IP per minute; 0 disables. */
  authMutationRateLimitPerMinute: number;
  sessionSecret: string;
  /** Absolute lifetime shared by the browser cookie and its dedicated SQL connection. */
  sessionTtlMs: number;
  /** Maximum time a dedicated SQL session may remain unused. */
  sessionIdleTimeoutMs: number;
  /** Frequency at which expired SQL sessions are swept. */
  sessionSweepIntervalMs: number;
  port: number;
  isProd: boolean;
  /** Serve dist/client from the compiled server (enabled by npm start). */
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

function positiveDuration(name: string, fallback: number): number {
  const value = Number(process.env[name] ?? fallback);
  return Number.isFinite(value) && value > 0 ? Math.trunc(value) : fallback;
}

function optional(name: string): string | null {
  const value = process.env[name]?.trim();
  return value ? value : null;
}

export function loadConfig(): AppConfig {
  const isProd = process.env.NODE_ENV === 'production';
  const smtpHost = optional('SMTP_HOST');
  const smtpUser = optional('SMTP_USER');
  const smtpPassword = optional('SMTP_PASSWORD');
  const mailFrom = optional('MAIL_FROM');
  if ((smtpUser && !smtpPassword) || (!smtpUser && smtpPassword)) {
    throw new Error('SMTP_USER and SMTP_PASSWORD must be configured together.');
  }
  if (isProd && (!smtpHost || !mailFrom)) {
    throw new Error('Missing email config: SMTP_HOST and MAIL_FROM are required in production.');
  }

  return {
    dbServer: process.env.DB_SERVER ?? 'localhost\\SQLEXPRESS',
    dbPort: process.env.DB_PORT ? Number(process.env.DB_PORT) : null,
    dbDatabase: process.env.DB_DATABASE ?? 'BadmintonCourtManagement',
    dbUser: required('DB_USER'),
    dbPassword: required('DB_PASSWORD'),
    dbTrustServerCertificate: (process.env.DB_TRUST_SERVER_CERTIFICATE ?? 'true') === 'true',
    dbPoolMax: Number(process.env.DB_CONNECTION_POOL_MAX ?? 10),
    dbConnectTimeoutMs: Number(process.env.DB_CONNECT_TIMEOUT_MS ?? 5000),
    smtpHost,
    smtpPort: Number(process.env.SMTP_PORT ?? 587),
    smtpSecure: (process.env.SMTP_SECURE ?? 'false') === 'true',
    smtpUser,
    smtpPassword,
    mailFrom,
    // Quá tải thì thà báo lỗi nhanh (SQL 1222) còn hơn treo vô hạn sau hàng khoá của dbo.Courts.
    dbLockTimeoutMs: Number(process.env.DB_LOCK_TIMEOUT_MS ?? 5000),
    maxSessionConnections: Number(process.env.MAX_SESSION_CONNECTIONS ?? 200),
    loginRateLimitPerMinute: Number(process.env.LOGIN_RATE_LIMIT_PER_MINUTE ?? 60),
    authMutationRateLimitPerMinute: Number(process.env.AUTH_MUTATION_RATE_LIMIT_PER_MINUTE ?? 10),
    sessionSecret: required('SESSION_SECRET'),
    sessionTtlMs: positiveDuration('SESSION_TTL_MS', 1000 * 60 * 60 * 8),
    sessionIdleTimeoutMs: positiveDuration('SESSION_IDLE_TIMEOUT_MS', 1000 * 60 * 30),
    sessionSweepIntervalMs: positiveDuration('SESSION_SWEEP_INTERVAL_MS', 1000 * 60),
    port: Number(process.env.APP_PORT ?? 3000),
    isProd,
    serveClient: process.argv.includes('--serve-client') || process.env.SERVE_CLIENT === 'true',
  };
}
