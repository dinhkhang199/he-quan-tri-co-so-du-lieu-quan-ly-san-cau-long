import type { NextFunction, Request, Response } from 'express';

/**
 * Rate limit đơn giản trong bộ nhớ (sliding window) — IMP-11.
 *
 * Mục đích duy nhất: chặn bão đăng nhập. Mỗi lần POST /api/auth/login thành
 * công sẽ tạo MỘT connection SQL riêng cho phiên đó (SessionDb, min=max=1) và
 * giữ suốt 8 giờ theo cookie. Không có trần thì 2000 người đăng nhập cùng lúc
 * = 2000 connection + 2000 lần bắt tay TLS đập vào SQL Server Express.
 *
 * Cố ý KHÔNG dùng thư viện ngoài (không thêm dependency vào app/package.json):
 * bộ đếm nằm trong tiến trình Node. Nếu sau này chạy nhiều tiến trình thì phải
 * đổi sang store dùng chung (Redis) — xem docs/LOAD_TEST_2000.md.
 */
export type RateLimiterOptions = {
  /** Số request tối đa trong một cửa sổ. <= 0 nghĩa là tắt hẳn. */
  limit: number;
  /** Độ dài cửa sổ, ms. Mặc định 60_000 (1 phút). */
  windowMs?: number;
  /** Thông báo tiếng Việt trả về khi bị chặn. */
  message?: string;
};

export function createRateLimiter(options: RateLimiterOptions) {
  const windowMs = options.windowMs ?? 60_000;
  const message = options.message ?? 'Bạn gửi quá nhiều yêu cầu. Vui lòng thử lại sau một phút.';
  /** IP -> danh sách mốc thời gian request còn trong cửa sổ. */
  const hits = new Map<string, number[]>();

  // Dọn rác định kỳ để Map không phình vô hạn; unref() để không giữ process sống.
  const sweeper = setInterval(() => {
    const cutoff = Date.now() - windowMs;
    for (const [key, stamps] of hits) {
      const kept = stamps.filter((t) => t > cutoff);
      if (kept.length === 0) hits.delete(key);
      else hits.set(key, kept);
    }
  }, windowMs);
  sweeper.unref();

  return function rateLimit(req: Request, res: Response, next: NextFunction): void {
    if (options.limit <= 0) {
      next();
      return;
    }
    const key = req.ip ?? req.socket.remoteAddress ?? 'unknown';
    const now = Date.now();
    const cutoff = now - windowMs;
    const stamps = (hits.get(key) ?? []).filter((t) => t > cutoff);

    if (stamps.length >= options.limit) {
      hits.set(key, stamps);
      res.setHeader('Retry-After', String(Math.ceil(windowMs / 1000)));
      res.status(429).json({ error: { code: null, message } });
      return;
    }

    stamps.push(now);
    hits.set(key, stamps);
    next();
  };
}
