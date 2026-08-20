import 'dotenv/config';
import { loadConfig } from './config.js';
import { createApp } from './app.js';
import { SessionDb } from './db/sessionDb.js';
import { closeSharedPool } from './db/pool.js';

async function main(): Promise<void> {
  const cfg = loadConfig();
  const sessionDb = new SessionDb(cfg);
  const app = createApp(cfg, sessionDb);

  const server = app.listen(cfg.port, () => {
    console.log(`[badmintonpro] app listening on http://localhost:${cfg.port}`);
  });

  const shutdown = async () => {
    console.log('[badmintonpro] shutting down...');
    server.close();
    await sessionDb.closeAll();
    await closeSharedPool();
    process.exit(0);
  };
  process.on('SIGINT', shutdown);
  process.on('SIGTERM', shutdown);
}

main().catch((err) => {
  console.error('[badmintonpro] failed to start:', err);
  process.exit(1);
});
