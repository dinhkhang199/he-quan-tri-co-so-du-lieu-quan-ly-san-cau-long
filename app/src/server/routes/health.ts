import { Router } from 'express';
import type { AppConfig } from '../config.js';
import { runShared } from '../db/index.js';

/**
 * SuccessFlag is the minimal start/health contract for Phase 2.0:
 * - checks the process is alive
 * - optionally probes the shared (no-session) pool to confirm SQL Server reachability
 * The health probe must not crash the app when the DB is unreachable.
 */
export function createHealthRouter(cfg: AppConfig, activeSessions: () => number): Router {
  const router = Router();

  router.get('/health', async (_req, res) => {
    let db: 'ok' | 'unreachable' | 'not-configured' = 'not-configured';
    if (cfg.dbUser && cfg.dbPassword) {
      try {
        await runShared(cfg, async (r) => r.query('SELECT 1 AS ok'));
        db = 'ok';
      } catch {
        db = 'unreachable';
      }
    }
    res.json({
      status: 'ok',
      service: 'badmintoncourtmanagement-app',
      phase: '2.12',
      db,
      activeSessionConnections: activeSessions(),
      time: new Date().toISOString(),
    });
  });

  return router;
}