import type { NextFunction, Request, Response } from 'express';

export interface RateLimiterOptions {
  message?: string;
  windowMs?: number;
}

export function createRateLimiter(
  limit: number,
  optionsOrWindowMs: number | RateLimiterOptions = 60_000,
) {
  const options: RateLimiterOptions =
    typeof optionsOrWindowMs === 'number'
      ? { windowMs: optionsOrWindowMs }
      : optionsOrWindowMs;
  const windowMs = options.windowMs ?? 60_000;
  const message = options.message ?? 'Quá nhiều yêu cầu. Vui lòng thử lại sau một phút.';

  const hits = new Map<string, number[]>();
  const cleanup = setInterval(() => {
    const cutoff = Date.now() - windowMs;
    for (const [key, stamps] of hits) {
      const recent = stamps.filter((stamp) => stamp > cutoff);
      if (recent.length === 0) hits.delete(key);
      else hits.set(key, recent);
    }
  }, windowMs);
  cleanup.unref();

  return (req: Request, res: Response, next: NextFunction): void => {
    if (limit <= 0) return next();
    const now = Date.now();
    const key = req.ip ?? req.socket.remoteAddress ?? 'unknown';
    const recent = (hits.get(key) ?? []).filter((stamp) => stamp > now - windowMs);
    if (recent.length >= limit) {
      res.setHeader('Retry-After', String(Math.ceil(windowMs / 1000)));
      res.status(429).json({ error: { code: null, message } });
      return;
    }
    recent.push(now);
    hits.set(key, recent);
    next();
  };
}
