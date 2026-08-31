import express from 'express';
import { fileURLToPath } from 'node:url';
import type { AppConfig } from './config.js';
import { createHealthRouter } from './routes/health.js';
import { createAuthRouter } from './routes/auth.js';
import { createCourtsRouter } from './routes/courts.js';
import { createBookingsRouter } from './routes/bookings.js';
import { createManagerRouter } from './routes/manager.js';
import { createManagerCourtsRouter } from './routes/managerCourts.js';
import { createManagerDashboardRouter } from './routes/managerDashboard.js';
import { createNotificationsRouter } from './routes/notifications.js';
import { createSessionMiddleware } from './middleware/session.js';
import { errorHandler } from './middleware/errorHandler.js';
import type { SessionDb } from './db/index.js';
import { createRateLimiter } from './middleware/rateLimit.js';

export function createApp(cfg: AppConfig, sessionDb: SessionDb): express.Express {
  const app = express();

  app.disable('x-powered-by');
  if (cfg.isProd) app.set('trust proxy', 1);
  app.use(express.json());
  app.use(createSessionMiddleware(cfg));

  app.use('/api', createHealthRouter(cfg, () => sessionDb.activeCount()));
  app.use('/api/auth/login', createRateLimiter(cfg.loginRateLimitPerMinute, { message: 'Quá nhiều lần đăng nhập. Vui lòng thử lại sau một phút.' }));
  app.use('/api/auth/register', createRateLimiter(cfg.registerRateLimitPerMinute, { message: 'Quá nhiều lần thử đăng ký. Vui lòng thử lại sau một phút.' }));
  app.use('/api/auth', createAuthRouter(cfg, sessionDb));
  app.use('/api/courts', createCourtsRouter(cfg));
  app.use('/api/bookings', createBookingsRouter(sessionDb));
  app.use('/api/manager/bookings', createManagerRouter(sessionDb));
  app.use('/api/manager/courts', createManagerCourtsRouter(sessionDb));
  app.use('/api/manager/dashboard', createManagerDashboardRouter(sessionDb));
  app.use('/api/notifications', createNotificationsRouter(sessionDb));

  app.use('/api', (_req, res) => {
    res.status(404).json({ error: { message: 'Không tìm thấy API endpoint này.' } });
  });

  if (cfg.serveClient) {
    const clientDir = fileURLToPath(new URL('../client/', import.meta.url));
    const clientIndex = fileURLToPath(new URL('../client/index.html', import.meta.url));
    app.use(express.static(clientDir));
    app.get('*', (_req, res) => res.sendFile(clientIndex));
  } else {
    app.all('*', (_req, res) => {
      res.status(404).json({ error: { message: 'Không tìm thấy tài nguyên này.' } });
    });
  }

  app.use(errorHandler);
  return app;
}
