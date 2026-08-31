import assert from 'node:assert/strict';
import test from 'node:test';
import { hoursUntilVietnamWallClock, vietnamWallClockToEpoch } from '../src/shared/time.js';

const now = Date.UTC(2026, 7, 31, 3, 0, 0); // 10:00 Asia/Ho_Chi_Minh

test('Vietnam wall-clock cancellation hint is inclusive at exactly three hours', () => {
  assert.equal(hoursUntilVietnamWallClock('2026-08-31T13:00:00.000Z', now), 3);
});

test('Vietnam wall-clock cancellation hint rejects 2h59 and accepts more than 3h', () => {
  assert.ok(hoursUntilVietnamWallClock('2026-08-31T12:59:00.000Z', now) < 3);
  assert.ok(hoursUntilVietnamWallClock('2026-08-31T13:30:00.000Z', now) > 3);
});

test('parser ignores misleading Z and uses stored Vietnam wall-clock digits', () => {
  assert.equal(vietnamWallClockToEpoch('2026-08-31T10:00:00.000Z'), now);
});
