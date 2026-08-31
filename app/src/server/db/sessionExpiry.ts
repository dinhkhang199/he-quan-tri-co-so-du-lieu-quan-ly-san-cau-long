export interface SessionTimestamps { createdAt: number; lastUsedAt: number }
export interface SessionExpiryPolicy { ttlMs: number; idleTimeoutMs: number }

export function isSessionExpired(
  timestamps: SessionTimestamps,
  policy: SessionExpiryPolicy,
  now = Date.now(),
): boolean {
  return now - timestamps.createdAt >= policy.ttlMs || now - timestamps.lastUsedAt >= policy.idleTimeoutMs;
}

export function touchSession(timestamps: SessionTimestamps, now = Date.now()): void {
  timestamps.lastUsedAt = Math.max(timestamps.lastUsedAt, now);
}

export function expiredSessionIds<T extends SessionTimestamps>(
  sessions: Iterable<readonly [string, T]>,
  policy: SessionExpiryPolicy,
  now = Date.now(),
): string[] {
  return [...sessions].filter(([, value]) => isSessionExpired(value, policy, now)).map(([id]) => id);
}
