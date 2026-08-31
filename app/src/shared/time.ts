const VIETNAM_OFFSET_MS = 7 * 60 * 60 * 1000;

/** Parse SQL DATETIME2 wall-clock digits as an Asia/Ho_Chi_Minh instant. */
export function vietnamWallClockToEpoch(value: Date | string): number {
  const raw = typeof value === 'string' ? value : value.toISOString();
  const match = raw.match(/^(\d{4})-(\d{2})-(\d{2})[T ](\d{2}):(\d{2})(?::(\d{2}))?/);
  if (!match) return Number.NaN;
  const [, y, m, d, hh, mm, ss = '0'] = match;
  return Date.UTC(Number(y), Number(m) - 1, Number(d), Number(hh), Number(mm), Number(ss)) - VIETNAM_OFFSET_MS;
}

/** UX hint only; dbo.sp_CancelBooking remains authoritative. */
export function hoursUntilVietnamWallClock(value: Date | string, nowEpochMs = Date.now()): number {
  return (vietnamWallClockToEpoch(value) - nowEpochMs) / 3_600_000;
}
