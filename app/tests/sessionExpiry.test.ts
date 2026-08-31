import { strict as assert } from 'node:assert';
import test from 'node:test';
import {
  expiredSessionIds,
  isSessionExpired,
  sessionExpiryReason,
  touchSession,
  type SessionExpiryPolicy,
  type SessionTimestamps,
} from '../src/server/db/sessionExpiry.js';

const policy: SessionExpiryPolicy = { ttlMs: 8_000, idleTimeoutMs: 1_800 };

function timestamps(createdAt = 1_000, lastUsedAt = createdAt): SessionTimestamps {
  return { createdAt, lastUsedAt };
}

test('SX-01 phiên chưa chạm TTL/idle còn sống', () => {
  assert.equal(isSessionExpired(timestamps(1_000, 1_500), policy, 2_000), false);
});

test('SX-02 đúng biên TTL thì hết hạn', () => {
  assert.equal(sessionExpiryReason(timestamps(1_000, 8_900), policy, 9_000), 'ttl');
});

test('SX-03 vượt TTL thì hết hạn', () => {
  assert.equal(isSessionExpired(timestamps(1_000, 9_000), policy, 9_001), true);
});

test('SX-04 đúng biên idle timeout thì hết hạn', () => {
  assert.equal(sessionExpiryReason(timestamps(1_000, 2_000), policy, 3_800), 'idle');
});

test('SX-05 TTL được ưu tiên khi cả hai deadline cùng hết', () => {
  assert.equal(sessionExpiryReason(timestamps(1_000, 1_000), policy, 9_000), 'ttl');
});

test('SX-06 timestamp ở tương lai không bị kết luận hết hạn', () => {
  assert.equal(isSessionExpired(timestamps(5_000, 5_000), policy, 4_000), false);
});

test('SX-07 TTL <= 0 được coi là tắt trong logic thuần', () => {
  assert.equal(isSessionExpired(timestamps(1_000, 9_900), { ttlMs: 0, idleTimeoutMs: 1_800 }, 10_000), false);
});

test('SX-08 idle timeout <= 0 được coi là tắt trong logic thuần', () => {
  assert.equal(isSessionExpired(timestamps(9_000, 1_000), { ttlMs: 8_000, idleTimeoutMs: 0 }, 2_801), false);
});

test('SX-09 touch chỉ tăng lastUsedAt, không đổi createdAt', () => {
  const value = timestamps(1_000, 1_500);
  touchSession(value, 2_500);
  touchSession(value, 2_000);
  assert.deepEqual(value, { createdAt: 1_000, lastUsedAt: 2_500 });
});

test('SX-10 bộ quét chỉ chọn đúng id hết hạn', () => {
  const sessions: Array<readonly [string, SessionTimestamps]> = [
    ['ttl', timestamps(1_000, 8_900)],
    ['idle', timestamps(8_000, 8_000)],
    ['live', timestamps(8_000, 9_500)],
  ];
  assert.deepEqual(expiredSessionIds(sessions, policy, 10_000), ['ttl', 'idle']);
});

test('SX-11 hoạt động gần đây tránh idle timeout nhưng không kéo dài TTL tuyệt đối', () => {
  const value = timestamps(1_000, 1_000);
  touchSession(value, 8_900);
  assert.equal(isSessionExpired(value, policy, 8_999), false);
  assert.equal(sessionExpiryReason(value, policy, 9_000), 'ttl');
});

test('SX-12 quét sạch 2000 phiên bỏ rơi nhưng giữ phiên đang dùng', () => {
  const sessions: Array<readonly [string, SessionTimestamps]> = [];
  for (let i = 0; i < 2_000; i += 1) {
    sessions.push([`abandoned-${i}`, timestamps(1_000, 1_000)]);
  }
  sessions.push(['active', timestamps(8_000, 9_900)]);

  const expired = expiredSessionIds(sessions, policy, 10_000);
  assert.equal(expired.length, 2_000);
  assert.equal(expired.includes('active'), false);
});
