/**
 * Shared SQL connection pool.
 * Used for PUBLIC/guest procedures that need no SESSION_CONTEXT
 * (e.g. sp_GetAvailableCourts, health checks). Protected business procedures
 * must go through SessionDb instead (see sessionDb.ts).
 */
import sql from 'mssql';
import type { AppConfig } from '../config.js';
import { buildSqlConfig } from './connection.js';

let pool: sql.ConnectionPool | null = null;

export async function getSharedPool(cfg: AppConfig): Promise<sql.ConnectionPool> {
  if (!pool || !pool.connected) {
    pool = await new sql.ConnectionPool(buildSqlConfig(cfg)).connect();
  }
  return pool;
}

export async function runShared<T>(cfg: AppConfig, handler: (r: sql.Request) => Promise<T>): Promise<T> {
  const p = await getSharedPool(cfg);
  return handler(p.request());
}

export async function closeSharedPool(): Promise<void> {
  if (pool && pool.connected) {
    await pool.close();
    pool = null;
  }
}