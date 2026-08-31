/** Pure session-expiry policy (IMP-13). This module deliberately has no mssql import. */

export interface SessionTimestamps {
  createdAt: number;
  lastUsedAt: number;
}

export interface SessionExpiryPolicy {
  ttlMs: number;
  idleTimeoutMs: number;
}

export type SessionExpiryReason = 'ttl' | 'idle' | null;

function elapsedAtLeast(since: number, durationMs: number, now: number): boolean {
  return Number.isFinite(durationMs) && durationMs > 0 && now - since >= durationMs;
}

/** Absolute TTL takes precedence when both deadlines are reached. */
export function sessionExpiryReason(
  timestamps: SessionTimestamps,
  policy: SessionExpiryPolicy,
  now = Date.now(),
): SessionExpiryReason {
  if (elapsedAtLeast(timestamps.createdAt, policy.ttlMs, now)) return 'ttl';
  if (elapsedAtLeast(timestamps.lastUsedAt, policy.idleTimeoutMs, now)) return 'idle';
  return null;
}

export function isSessionExpired(
  timestamps: SessionTimestamps,
  policy: SessionExpiryPolicy,
  now = Date.now(),
): boolean {
  return sessionExpiryReason(timestamps, policy, now) !== null;
}

/** Record activity without allowing a backwards clock sample to reduce lastUsedAt. */
export function touchSession(timestamps: SessionTimestamps, now = Date.now()): void {
  timestamps.lastUsedAt = Math.max(timestamps.lastUsedAt, now);
}

/** Collect ids only; the caller owns connection closing and queue serialization. */
export function expiredSessionIds<T extends SessionTimestamps>(
  sessions: Iterable<readonly [string, T]>,
  policy: SessionExpiryPolicy,
  now = Date.now(),
): string[] {
  const ids: string[] = [];
  for (const [id, timestamps] of sessions) {
    if (isSessionExpired(timestamps, policy, now)) ids.push(id);
  }
  return ids;
}
