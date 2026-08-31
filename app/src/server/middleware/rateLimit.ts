import type { NextFunction, Request, Response } from 'express';

export function createRateLimiter(limit: number, windowMs = 60_000) {
  const hits = new Map<string, number[]>();
  return (req: Request, res: Response, next: NextFunction): void => {
    if (limit <= 0) return next();
    const now = Date.now();
    const key = req.ip ?? req.socket.remoteAddress ?? 'unknown';
    const recent = (hits.get(key) ?? []).filter((stamp) => stamp > now - windowMs);
    if (recent.length >= limit) {
      res.setHeader('Retry-After', String(Math.ceil(windowMs / 1000)));
      res.status(429).json({ error: { message: 'Quá nhiều lần đăng nhập. Vui lòng thử lại sau một phút.' } });
      return;
    }
    recent.push(now);
    hits.set(key, recent);
    next();
  };
}
