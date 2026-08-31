import assert from 'node:assert/strict';
import test from 'node:test';
import { expiredSessionIds, isSessionExpired, touchSession } from '../src/server/db/sessionExpiry.js';

test('expires by idle time and absolute TTL', () => {
  const policy = { ttlMs: 1000, idleTimeoutMs: 200 };
  assert.equal(isSessionExpired({ createdAt: 0, lastUsedAt: 850 }, policy, 1000), true);
  assert.equal(isSessionExpired({ createdAt: 0, lastUsedAt: 950 }, policy, 1000), true);
});

test('touch and collection preserve live sessions', () => {
  const entry = { createdAt: 100, lastUsedAt: 100 };
  touchSession(entry, 250);
  assert.equal(entry.lastUsedAt, 250);
  assert.deepEqual(expiredSessionIds([['live', entry], ['old', { createdAt: 0, lastUsedAt: 0 }]], { ttlMs: 500, idleTimeoutMs: 200 }, 300), ['old']);
});
