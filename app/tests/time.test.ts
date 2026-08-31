/**
 * Test luật khung giờ ở tầng API (app/src/server/time.ts) — phải trùng với
 * luật trong dbo.sp_BookCourt: 06:00–22:00, bước 30 phút, 1–3 giờ,
 * cùng một ngày, không đầt được trong quá khứ.
 *
 * Chạy: cd app && node --import tsx --test tests/time.test.ts
 */
import { strict as assert } from 'node:assert';
import test from 'node:test';
import {
  formatWallClock,
  isValidCourtId,
  isValidGuid,
  minutesOfDay,
  parseWallClock,
  toSqlDate,
  validateWindow,
  vietnamWallNow,
} from '../src/server/time.js';

const p2 = (n: number): string => (n < 10 ? `0${n}` : String(n));

/** Ngày dịch theo múi giờ sân (Asia/Ho_Chi_Minh), dạng YYYY-MM-DD. */
function dayOffset(offset: number): string {
  const now = vietnamWallNow();
  const d = new Date(Date.UTC(now.year, now.month - 1, now.day + offset));
  return `${d.getUTCFullYear()}-${p2(d.getUTCMonth() + 1)}-${p2(d.getUTCDate())}`;
}

const TOMORROW = dayOffset(1);
const YESTERDAY = dayOffset(-1);
const DAY_AFTER = dayOffset(2);

const at = (hhmmss: string, day: string = TOMORROW): string => `${day}T${hhmmss}`;

function expectOk(startHhmm: string, endHhmm: string, minutes: number): void {
  const r = validateWindow(at(startHhmm), at(endHhmm), 'đặt');
  assert.equal(r.ok, true, `${startHhmm}→${endHhmm} phải hợp lệ nhưng bị: ${r.ok ? '' : r.message}`);
  if (r.ok) assert.equal(r.durationMinutes, minutes);
}

function expectFail(startHhmm: string, endHhmm: string, needle: string, endDay?: string): void {
  const r = validateWindow(at(startHhmm), at(endHhmm, endDay), 'đặt');
  assert.equal(r.ok, false, `${startHhmm}→${endHhmm} phải bị từ chối`);
  if (!r.ok) assert.ok(r.message.includes(needle), `thông báo "${r.message}" phải chứa "${needle}"`);
}

// ---------- Nhóm hợp lệ ----------

test('TW-01 đúng 1 giờ (tối thiểu)', () => expectOk('08:00:00', '09:00:00', 60));
test('TW-02 1 giờ 30 (bước 30 phút)', () => expectOk('08:30:00', '10:00:00', 90));
test('TW-03 2 giờ', () => expectOk('14:00:00', '16:00:00', 120));
test('TW-04 đúng 3 giờ (tối đa)', () => expectOk('06:00:00', '09:00:00', 180));
test('TW-05 biên mở cửa 06:00', () => expectOk('06:00:00', '07:00:00', 60));
test('TW-06 biên đóng cửa 22:00', () => expectOk('21:00:00', '22:00:00', 60));
test('TW-07 sát biên đóng cửa, 3 giờ 19:00–22:00', () => expectOk('19:00:00', '22:00:00', 180));

test('TW-08 startSql/endSql đúng định dạng DATETIME2(0) cho SQL', () => {
  const r = validateWindow(at('08:00:00'), at('09:30:00'), 'đặt');
  assert.equal(r.ok, true);
  if (r.ok) {
    assert.equal(r.startSql, `${TOMORROW} 08:00:00`);
    assert.equal(r.endSql, `${TOMORROW} 09:30:00`);
    assert.equal(r.durationMinutes, 90);
  }
});

// ---------- Nhóm thời lượng ----------

test('TW-09 30 phút → dưới tối thiểu', () => expectFail('08:00:00', '08:30:00', 'Thể tích'.slice(0, 0) + 'tối thiểu'));
test('TW-10 3 giờ 30 → vượt tối đa', () => expectFail('08:00:00', '11:30:00', 'tối đa'));
test('TW-11 4 giờ → vượt tối đa', () => expectFail('08:00:00', '12:00:00', 'tối đa'));

// ---------- Nhóm bước 30 phút ----------

test('TW-12 phút 15 ở giờ bắt đầu → từ chối', () =>
  expectFail('08:15:00', '09:15:00', 'bước 30 phút'));
test('TW-13 phút 45 ở giờ kết thúc → từ chối', () =>
  expectFail('08:00:00', '09:45:00', 'bước 30 phút'));
test('TW-14 có giây khác 0 → từ chối', () => expectFail('08:00:30', '09:00:00', 'bước 30 phút'));

// ---------- Nhóm thứ tự/ngày ----------

test('TW-15 kết thúc = bắt đầu → từ chối', () =>
  expectFail('08:00:00', '08:00:00', 'phải sau giờ bắt đầu'));
test('TW-16 kết thúc trước bắt đầu → từ chối', () =>
  expectFail('10:00:00', '09:00:00', 'phải sau giờ bắt đầu'));
test('TW-17 qua đêm (23:00 → 00:00 ngày sau) → từ chối', () =>
  expectFail('23:00:00', '00:00:00', 'không được qua đêm', DAY_AFTER));

// ---------- Nhóm giờ hoạt động ----------

test('TW-18 bắt đầu 05:30 (trước giờ mở) → từ chối', () =>
  expectFail('05:30:00', '06:30:00', '06:00'));
test('TW-19 kết thúc 22:30 (sau giờ đóng) → từ chối', () =>
  expectFail('21:30:00', '22:30:00', '22:00'));
test('TW-20 cả khung nằm ngoài giờ (23:00–24:00 không tồn tại) → từ chối', () => {
  const r = validateWindow(at('23:00:00'), at('24:00:00'), 'đặt');
  assert.equal(r.ok, false);
});

// ---------- Nhóm quá khứ ----------

test('TW-21 hôm qua → từ chối vì đã trôi qua', () => {
  const r = validateWindow(`${YESTERDAY}T08:00:00`, `${YESTERDAY}T09:00:00`, 'đặt');
  assert.equal(r.ok, false);
  if (!r.ok) assert.ok(r.message.includes('trôi qua'), r.message);
});

// ---------- Nhóm dữ liệu rác ----------

test('TW-22 chuỗi rỗng → yêu cầu chọn lại', () => {
  const r = validateWindow('', '', 'đặt');
  assert.equal(r.ok, false);
  if (!r.ok) assert.ok(r.message.includes('Vui lòng chọn'), r.message);
});

test('TW-23 không phải chuỗi (null/số/object) → từ chối', () => {
  for (const bad of [null, undefined, 42, {}, [], true]) {
    const r = validateWindow(bad, at('09:00:00'), 'đặt');
    assert.equal(r.ok, false, `giá trị ${JSON.stringify(bad)} phải bị từ chối`);
  }
});

test('TW-24 sai định dạng (thiếu T, có Z, thiếu giây) → từ chối', () => {
  const bads = [
    `${TOMORROW} 08:00:00`,
    `${TOMORROW}T08:00:00Z`,
    `${TOMORROW}T08:00`,
    `${TOMORROW}T8:00:00`,
    'hom nay 8 gio',
  ];
  for (const bad of bads) {
    const r = validateWindow(bad, at('09:00:00'), 'đặt');
    assert.equal(r.ok, false, `"${bad}" phải bị từ chối`);
  }
});

test('TW-25 ngày không tồn tại (30/02, 31/04, tháng 13) → từ chối', () => {
  for (const bad of ['2027-02-30T08:00:00', '2027-04-31T08:00:00', '2027-13-01T08:00:00']) {
    const r = validateWindow(bad, '2027-04-30T09:00:00', 'đặt');
    assert.equal(r.ok, false, `"${bad}" phải bị từ chối`);
  }
});

test('TW-26 SQL injection trong tham số thỏi gian bị chặn ngay ở regex', () => {
  const r = validateWindow(`${TOMORROW}T08:00:00'; DROP TABLE dbo.Bookings; --`, at('09:00:00'), 'đặt');
  assert.equal(r.ok, false);
});

// ---------- Phụ trợ ----------

test('TW-27 parseWallClock/formatWallClock đi vòng tròn đúng', () => {
  const t = parseWallClock('2027-03-09T21:30:00');
  assert.ok(t);
  assert.equal(minutesOfDay(t!), 21 * 60 + 30);
  assert.equal(formatWallClock(t!), '2027-03-09 21:30:00');
});

test('TW-28 toSqlDate giữ nguyên số giờ (không bị lệch múi giờ)', () => {
  const t = parseWallClock('2027-03-09T18:00:00')!;
  const d = toSqlDate(t);
  assert.equal(d.getUTCFullYear(), 2027);
  assert.equal(d.getUTCMonth() + 1, 3);
  assert.equal(d.getUTCDate(), 9);
  assert.equal(d.getUTCHours(), 18, '18:00 phải vẫn là 18:00, không thành 11:00');
  assert.equal(d.getUTCMinutes(), 0);
});

test('TW-29 isValidGuid / isValidCourtId nhận đúng GUID', () => {
  assert.equal(isValidGuid('C1000001-0000-0000-0000-000000000001'), true);
  assert.equal(isValidGuid('c1000001-0000-0000-0000-000000000001'), true);
  assert.equal(isValidCourtId('C1000001-0000-0000-0000-000000000001'), true);
  assert.equal(isValidGuid('C1000001-0000-0000-0000-00000000000'), false, 'thiếu 1 ký tự');
  assert.equal(isValidGuid('not-a-guid'), false);
  assert.equal(isValidGuid("' OR 1=1--"), false);
  assert.equal(isValidGuid(123), false);
  assert.equal(isValidGuid(null), false);
  assert.equal(isValidGuid(undefined), false);
});

test('TW-30 subject đổi đúng từ ngữ thông báo (tìm / đặt)', () => {
  const a = validateWindow(at('05:00:00'), at('06:00:00'), 'tìm');
  const b = validateWindow(at('05:00:00'), at('06:00:00'), 'đặt');
  assert.equal(a.ok, false);
  assert.equal(b.ok, false);
  if (!a.ok && !b.ok) {
    assert.ok(a.message.includes('tìm'));
    assert.ok(b.message.includes('đặt'));
  }
});
