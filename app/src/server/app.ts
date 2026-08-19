import express from 'express';
import type { AppConfig } from './config.js';
import { createHealthRouter } from './routes/health.js';
import { createAuthRouter } from './routes/auth.js';
import { createCourtsRouter } from './routes/courts.js';
import { createBookingsRouter } from './routes/bookings.js';
import { createManagerRouter } from './routes/manager.js';
import { createSessionMiddleware } from './middleware/session.js';
import { errorHandler } from './middleware/errorHandler.js';
import type { SessionDb } from './db/index.js';

export function createApp(cfg: AppConfig, sessionDb: SessionDb): express.Express {
  const app = express();

  app.disable('x-powered-by');
  app.use(express.json());
  app.use(createSessionMiddleware(cfg));

  app.use('/api', createHealthRouter(cfg, () => sessionDb.activeCount()));
  app.use('/api/auth', createAuthRouter(sessionDb));
  app.use('/api/courts', createCourtsRouter(cfg));
  app.use('/api/bookings', createBookingsRouter(sessionDb));
  app.use('/api/manager/bookings', createManagerRouter(sessionDb));

  app.use('/api', (_req, res) => {
    res.status(404).json({ error: { message: 'Không tìm thấy API endpoint này.' } });
  });

  app.all('*', (_req, res) => {
    res.status(404).json({ error: { message: 'Không tìm thấy tài nguyên này.' } });
  });

  app.use(errorHandler);
  return app;
}