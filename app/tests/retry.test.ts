/**
 * Test cho IMP-10: withTransientRetry (app/src/server/db/retry.ts).
 *
 * Chạy: cd app && node --import tsx --test tests/retry.test.ts
 * Không cần SQL Server, không cần npm install (chỉ dùng node:test + tsx).
 */
import { strict as assert } from 'node:assert';
import test from 'node:test';
import { isTransientSqlError, withTransientRetry } from '../src/server/db/retry.js';

/** Giả lập lỗi mssql: RequestError mang thuộc tính `number`. */
function sqlError(number: number): Error {
  return Object.assign(new Error(`SQL error ${number}`), { number });
}

/** Tắt log của retry để kết quả test dễ đọc. */
const quiet = { warn: console.warn };
test.before(() => {
  console.warn = () => {};
});
test.after(() => {
  console.warn = quiet.warn;
});

test('RT-01 thành công ngay lần đầu thì không thử lại', async () => {
  let calls = 0;
  const result = await withTransientRetry(async () => {
    calls += 1;
    return 'ok';
  });
  assert.equal(result, 'ok');
  assert.equal(calls, 1);
});

test('RT-02 deadlock 1205 rồi thành công → thử lại đúng 1 lần', async () => {
  let calls = 0;
  const result = await withTransientRetry(
    async () => {
      calls += 1;
      if (calls === 1) throw sqlError(1205);
      return 'booked';
    },
    { baseDelayMs: 1 },
  );
  assert.equal(result, 'booked');
  assert.equal(calls, 2);
});

test('RT-03 lock timeout 1222 rồi thành công → thử lại đúng 1 lần', async () => {
  let calls = 0;
  const result = await withTransientRetry(
    async () => {
      calls += 1;
      if (calls === 1) throw sqlError(1222);
      return 'booked';
    },
    { baseDelayMs: 1 },
  );
  assert.equal(result, 'booked');
  assert.equal(calls, 2);
});

test('RT-04 1205 liên tục → dừng ở 3 lần và ném lại lỗi gốc', async () => {
  let calls = 0;
  await assert.rejects(
    () =>
      withTransientRetry(
        async () => {
          calls += 1;
          throw sqlError(1205);
        },
        { baseDelayMs: 1 },
      ),
    (err: unknown) => {
      assert.equal((err as { number?: number }).number, 1205);
      return true;
    },
  );
  assert.equal(calls, 3, 'phải thử tối đa 3 lần, không được thử vô hạn');
});

test('RT-05 lỗi nghiệp vụ (50021 trùng giờ BOOKED) KHÔNG được thử lại', async () => {
  let calls = 0;
  await assert.rejects(() =>
    withTransientRetry(async () => {
      calls += 1;
      throw sqlError(50021);
    }),
  );
  assert.equal(calls, 1);
});

test('RT-06 lỗi UNIQUE 2601 (IMP-09) KHÔNG được thử lại', async () => {
  let calls = 0;
  await assert.rejects(() =>
    withTransientRetry(async () => {
      calls += 1;
      throw sqlError(2601);
    }),
  );
  assert.equal(calls, 1);
});

test('RT-07 lỗi thường (không có số SQL) KHÔNG được thử lại', async () => {
  let calls = 0;
  await assert.rejects(() =>
    withTransientRetry(async () => {
      calls += 1;
      throw new Error('No active SQL session connection');
    }),
  );
  assert.equal(calls, 1);
});

test('RT-08 attempts = 1 → không thử lại dù là 1205', async () => {
  let calls = 0;
  await assert.rejects(() =>
    withTransientRetry(
      async () => {
        calls += 1;
        throw sqlError(1205);
      },
      { attempts: 1 },
    ),
  );
  assert.equal(calls, 1);
});

test('RT-09 backoff tăng dần (lần chờ thứ hai dài hơn lần đầu)', async () => {
  const stamps: number[] = [];
  await assert.rejects(() =>
    withTransientRetry(
      async () => {
        stamps.push(Date.now());
        throw sqlError(1222);
      },
      { baseDelayMs: 40 },
    ),
  );
  assert.equal(stamps.length, 3);
  const gap1 = stamps[1]! - stamps[0]!;
  const gap2 = stamps[2]! - stamps[1]!;
  assert.ok(gap1 >= 35, `gap1 = ${gap1}ms, phải >= ~40ms`);
  assert.ok(gap2 > gap1, `gap2 (${gap2}ms) phải lớn hơn gap1 (${gap1}ms)`);
});

test('RT-10 có jitter: hai lần chạy không ra cùng một độ trễ', async () => {
  const measure = async (): Promise<number> => {
    const t0 = Date.now();
    await assert.rejects(() =>
      withTransientRetry(
        async () => {
          throw sqlError(1205);
        },
        { baseDelayMs: 30 },
      ),
    );
    return Date.now() - t0;
  };
  const runs = [await measure(), await measure(), await measure(), await measure()];
  const unique = new Set(runs);
  assert.ok(unique.size > 1, `jitter không hoạt động, các lần chạy đều = ${runs.join(', ')}ms`);
});

test('RT-11 isTransientSqlError phân loại đúng từng mã lỗi', () => {
  assert.equal(isTransientSqlError(sqlError(1205)), true, '1205 deadlock');
  assert.equal(isTransientSqlError(sqlError(1222)), true, '1222 lock timeout');
  assert.equal(isTransientSqlError(sqlError(2601)), false, '2601 unique index');
  assert.equal(isTransientSqlError(sqlError(2627)), false, '2627 unique constraint');
  assert.equal(isTransientSqlError(sqlError(547)), false, '547 CHECK/FK');
  assert.equal(isTransientSqlError(sqlError(50021)), false, '50021 trùng giờ');
  assert.equal(isTransientSqlError(sqlError(51001)), false, '51001 trigger overlap');
  assert.equal(isTransientSqlError(new Error('boom')), false);
  assert.equal(isTransientSqlError(null), false);
  assert.equal(isTransientSqlError(undefined), false);
  assert.equal(isTransientSqlError('1205'), false, 'chuỗi "1205" không phải lỗi SQL');
});
