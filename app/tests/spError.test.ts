/**
 * Test bản đồ lỗi SQL → thông báo tiếng Việt (app/src/shared/spError.ts),
 * bao gồm hai mã mới của IMP-09/IMP-10: 1222 và 2601.
 *
 * Chạy: cd app && node --import tsx --test tests/spError.test.ts
 */
import { strict as assert } from 'node:assert';
import test from 'node:test';
import { mapSqlError } from '../src/shared/spError.js';

const sqlError = (number: number): Error =>
  Object.assign(new Error(`Mock SQL error ${number}`), { number });

test('SE-01 1205 deadlock có thông báo ổn định', () => {
  const m = mapSqlError(sqlError(1205));
  assert.equal(m.code, 1205);
  assert.ok(m.message && m.message.length > 0);
});

test('SE-02 1222 lock timeout (IMP-10) đã được ánh xạ', () => {
  const m = mapSqlError(sqlError(1222));
  assert.equal(m.code, 1222);
  assert.ok(m.message?.includes('quá tải'), m.message ?? 'null');
});

test('SE-03 2601 trùng unique index (IMP-09) đã được ánh xạ', () => {
  const m = mapSqlError(sqlError(2601));
  assert.equal(m.code, 2601);
  assert.ok(m.message?.includes('chờ duyệt'), m.message ?? 'null');
});

test('SE-04 các mã nghiệp vụ chính và IMP-15 vẫn có thông báo riêng', () => {
  for (const code of [
    50001, 50002, 50011, 50012, 50013, 50021,
    50120, 50121, 50122, 50123, 50124, 50125, 50126,
    50200, 50201, 50202, 50203, 50210, 50211, 50212, 50213,
  ]) {
    const m = mapSqlError(sqlError(code));
    assert.equal(m.code, code);
    assert.ok(m.message && m.message.length > 0, `mã ${code} thiếu thông báo`);
  }
});

test('SE-05 mã lạ → không bịa thông báo, dùng fallback', () => {
  const m = mapSqlError(sqlError(987654));
  assert.equal(m.code, 987654);
  assert.equal(m.message, null);
  assert.ok(m.fallback.length > 0);
});

test('SE-06 lỗi không phải lỗi SQL → code null, giữ technical', () => {
  const m = mapSqlError(new Error('socket hang up'));
  assert.equal(m.code, null);
  assert.equal(m.message, null);
  assert.ok(m.technical.includes('socket hang up'));
});

test('SE-07 giá trị ném ra không phải Error cũng không làm vỡ hàm', () => {
  for (const thrown of ['boom', 42, null, undefined, { weird: true }]) {
    const m = mapSqlError(thrown);
    assert.equal(m.message, null);
    assert.ok(typeof m.technical === 'string');
  }
});

test('SE-08 lỗi mang thuộc tính `code` dạng số cũng đọc được', () => {
  const m = mapSqlError(Object.assign(new Error('x'), { code: 2601 }));
  assert.equal(m.code, 2601);
  assert.ok(m.message);
});

test('SE-09 thông báo không lọt chi tiết kỹ thuật ra ngoài', () => {
  const m = mapSqlError(sqlError(1205));
  assert.ok(!m.message!.toLowerCase().includes('mock sql error'));
  // Việc nêu mã 1205 trong thông báo là chủ ý (để đối chiếu log), nhưng
  // nội dung lỗi gốc của mssql thì không được lọt ra ngoài.
  assert.ok(!m.message!.includes('Error:'));
  assert.ok(m.technical.includes('Mock SQL error'), 'chi tiết kỹ thuật vẫn phải có cho log');
});
