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
import { createRateLimiter } from './middleware/rateLimit.js';
import { errorHandler } from './middleware/errorHandler.js';
import type { SessionDb } from './db/index.js';

export function createApp(cfg: AppConfig, sessionDb: SessionDb): express.Express {
  const app = express();

  app.disable('x-powered-by');
  if (cfg.isProd) app.set('trust proxy', 1);
  app.use(express.json());
  app.use(createSessionMiddleware(cfg));

  app.use('/api', createHealthRouter(cfg, () => sessionDb.activeCount()));
  // IMP-11: chặn bão đăng nhập trước khi nó biến thành bão connection SQL.
  // Mỗi lần đăng nhập thành công = 1 connection SQL riêng giữ suốt 8 giờ.
  app.use(
    '/api/auth/login',
    createRateLimiter({
      limit: cfg.loginRateLimitPerMinute,
      message: 'Quá nhiều lần đăng nhập từ địa chỉ này. Vui lòng thử lại sau một phút.',
    }),
  );
  const authMutationLimiter = createRateLimiter({
    limit: cfg.authMutationRateLimitPerMinute,
    message: 'Bạn gửi quá nhiều yêu cầu tài khoản. Vui lòng thử lại sau một phút.',
  });
  app.use('/api/auth/register', authMutationLimiter);
  app.use('/api/auth/password/forgot', authMutationLimiter);
  app.use('/api/auth/password/reset', authMutationLimiter);
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
    // Compiled app.js lives in dist/server; Vite emits the SPA to dist/client.
    const clientDir = fileURLToPath(new URL('../client/', import.meta.url));
    const clientIndex = fileURLToPath(new URL('../client/index.html', import.meta.url));
    app.use(express.static(clientDir));
    app.get('*', (_req, res) => {
      res.sendFile(clientIndex);
    });
    app.all('*', (_req, res) => {
      res.status(404).json({ error: { message: 'Không tìm thấy tài nguyên này.' } });
    });
  } else {
    app.all('*', (_req, res) => {
      res.status(404).json({ error: { message: 'Không tìm thấy tài nguyên này.' } });
    });
  }

  app.use(errorHandler);
  return app;
}
