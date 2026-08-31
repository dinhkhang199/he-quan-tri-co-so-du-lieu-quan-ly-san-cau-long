/**
 * SQL Server connection config shared by the pool and session connections.
 * Uses the Phase 1 application login `bcm_app` (created by database/08_security.sql).
 */
import type { config as MssqlConfig } from 'mssql';
import type { AppConfig } from '../config.js';

export function buildSqlConfig(cfg: AppConfig): MssqlConfig {
  const config: MssqlConfig = {
    server: cfg.dbServer,
    database: cfg.dbDatabase,
    user: cfg.dbUser,
    password: cfg.dbPassword,
    connectionTimeout: cfg.dbConnectTimeoutMs,
    options: {
      trustServerCertificate: cfg.dbTrustServerCertificate,
      encrypt: true,
    },
    pool: {
      max: cfg.dbPoolMax,
      min: 0,
      idleTimeoutMillis: 30000,
    },
  };
  if (cfg.dbPort !== null) config.port = cfg.dbPort;
  return config;
}
