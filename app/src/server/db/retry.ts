/**
 * Retry cho các lỗi SQL Server "tạm thời" (transient) — IMP-10.
 *
 * Chỉ retry đúng 2 mã lỗi, và CHỈ vì cả hai đều bảo đảm giao dịch đã ROLLBACK
 * hoàn toàn trước khi lỗi bay về app (mọi Stored Procedure trong
 * database/06_procedures.sql đều SET XACT_ABORT ON + IF XACT_STATE() <> 0
 * ROLLBACK trong CATCH):
 *
 *   1205 — Deadlock victim. SQL Server đã tự huỷ giao dịch này để giải deadlock.
 *          Microsoft khuyến nghị chạy lại nguyên khối công việc.
 *   1222 — Lock request time out (do SET LOCK_TIMEOUT ở SessionDb). Giao dịch
 *          bị huỷ vì chờ hàng khoá dbo.Courts quá lâu, không có thay đổi nào
 *          được ghi.
 *
 * KHÔNG retry các lỗi nghiệp vụ 5xxxx/51xxx (trùng giờ, sai trạng thái, sai
 * quyền...) vì chạy lại cũng sẽ thất bại y như vậy.
 *
 * Vì giao dịch đã rollback, retry là AN TOÀN: không tạo booking trùng, không
 * ghi 2 lần ActivityLogs/Notifications (trigger chạy trong cùng giao dịch đã
 * bị huỷ).
 */

const TRANSIENT_SQL_ERROR_NUMBERS = new Set<number>([1205, 1222]);

/** True nếu lỗi là deadlock victim (1205) hoặc lock timeout (1222). */
export function isTransientSqlError(err: unknown): boolean {
  const num = (err as { number?: unknown } | null | undefined)?.number;
  return typeof num === 'number' && TRANSIENT_SQL_ERROR_NUMBERS.has(num);
}

export type TransientRetryOptions = {
  /** Tổng số lần thử (kể cả lần đầu). Mặc định 3. */
  attempts?: number;
  /** Trễ cơ bản trước lần thử lại đầu tiên, ms. Mặc định 40ms. */
  baseDelayMs?: number;
  /** Nhãn để ghi log (thường là tên Stored Procedure). */
  label?: string;
};

/**
 * Chạy `fn`, tự thử lại khi gặp 1205/1222 với backoff + jitter ngẫu nhiên.
 * Jitter là bắt buộc: nếu 2000 request cùng retry đúng một thời điểm thì chỉ
 * dồn thêm một đợt tranh khoá mới (retry storm).
 *
 * Lỗi cuối cùng vẫn được throw nguyên trạng để route map sang HTTP status và
 * thông báo tiếng Việt như trước (mapSqlError không đổi).
 */
export async function withTransientRetry<T>(
  fn: () => Promise<T>,
  options: TransientRetryOptions = {},
): Promise<T> {
  const attempts = Math.max(1, options.attempts ?? 3);
  const baseDelayMs = Math.max(1, options.baseDelayMs ?? 40);
  const label = options.label ?? 'sql';

  let lastError: unknown;
  for (let attempt = 1; attempt <= attempts; attempt += 1) {
    try {
      return await fn();
    } catch (err) {
      lastError = err;
      if (!isTransientSqlError(err) || attempt === attempts) {
        throw err;
      }
      const num = (err as { number?: number }).number;
      const delay = Math.round(baseDelayMs * 2 ** (attempt - 1) * (1 + Math.random()));
      console.warn(
        `[retry] ${label}: lỗi tạm thời ${num} ở lần thử ${attempt}/${attempts}, thử lại sau ${delay}ms`,
      );
      await new Promise((resolve) => setTimeout(resolve, delay));
    }
  }
  throw lastError;
}
