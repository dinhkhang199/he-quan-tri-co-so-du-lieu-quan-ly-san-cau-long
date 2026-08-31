/**
 * Test cho IMP-11: createRateLimiter (app/src/server/middleware/rateLimit.ts).
 *
 * Chạy: cd app && node --import tsx --test tests/rateLimit.test.ts
 */
import { strict as assert } from 'node:assert';
import test from 'node:test';
import { createRateLimiter } from '../src/server/middleware/rateLimit.js';

interface FakeRes {
  statusCode: number | null;
  headers: Record<string, string>;
  body: unknown;
  setHeader(name: string, value: string): void;
  status(code: number): FakeRes;
  json(body: unknown): FakeRes;
}

function makeRes(): FakeRes {
  const res: FakeRes = {
    statusCode: null,
    headers: {},
    body: undefined,
    setHeader(name, value) {
      res.headers[name] = value;
    },
    status(code) {
      res.statusCode = code;
      return res;
    },
    json(body) {
      res.body = body;
      return res;
    },
  };
  return res;
}

function makeReq(ip?: string, remoteAddress?: string): any {
  return { ip, socket: { remoteAddress } };
}

/** Gọi middleware một lần, trả về { passed, res }. */
function hit(limiter: any, ip?: string, remoteAddress?: string) {
  const res = makeRes();
  let passed = false;
  limiter(makeReq(ip, remoteAddress), res as any, () => {
    passed = true;
  });
  return { passed, res };
}

test('RL-01 dưới ngưỡng thì cho qua', () => {
  const limiter = createRateLimiter({ limit: 3 });
  for (let i = 1; i <= 3; i += 1) {
    const { passed, res } = hit(limiter, '10.0.0.1');
    assert.equal(passed, true, `lần ${i} phải được qua`);
    assert.equal(res.statusCode, null);
  }
});

test('RL-02 vượt ngưỡng → 429 + Retry-After + thông báo tiếng Việt', () => {
  const limiter = createRateLimiter({ limit: 2 });
  hit(limiter, '10.0.0.2');
  hit(limiter, '10.0.0.2');
  const { passed, res } = hit(limiter, '10.0.0.2');
  assert.equal(passed, false, 'yêu cầu thứ 3 phải bị chặn');
  assert.equal(res.statusCode, 429);
  assert.equal(res.headers['Retry-After'], '60');
  const body = res.body as { error: { code: null; message: string } };
  assert.equal(body.error.code, null);
  assert.match(body.error.message, /quá nhiều/i);
});

test('RL-03 đếm riêng theo từng IP', () => {
  const limiter = createRateLimiter({ limit: 1 });
  assert.equal(hit(limiter, '10.0.0.3').passed, true);
  assert.equal(hit(limiter, '10.0.0.3').passed, false, 'IP cũ đã hết lượt');
  assert.equal(hit(limiter, '10.0.0.4').passed, true, 'IP khác phải còn lượt riêng');
});

test('RL-04 hết cửa sổ thời gian thì được phép lại', async () => {
  const limiter = createRateLimiter({ limit: 1, windowMs: 80 });
  assert.equal(hit(limiter, '10.0.0.5').passed, true);
  assert.equal(hit(limiter, '10.0.0.5').passed, false);
  await new Promise((r) => setTimeout(r, 120));
  assert.equal(hit(limiter, '10.0.0.5').passed, true, 'sau khi cửa sổ trôi qua phải được qua');
});

test('RL-05 limit = 0 nghĩa là tắt hẳn (không chặn ai)', () => {
  const limiter = createRateLimiter({ limit: 0 });
  for (let i = 0; i < 50; i += 1) {
    assert.equal(hit(limiter, '10.0.0.6').passed, true);
  }
});

test('RL-06 limit âm cũng coi như tắt', () => {
  const limiter = createRateLimiter({ limit: -5 });
  for (let i = 0; i < 10; i += 1) {
    assert.equal(hit(limiter, '10.0.0.7').passed, true);
  }
});

test('RL-07 không có req.ip thì dùng socket.remoteAddress', () => {
  const limiter = createRateLimiter({ limit: 1 });
  assert.equal(hit(limiter, undefined, '192.168.1.10').passed, true);
  assert.equal(hit(limiter, undefined, '192.168.1.10').passed, false, 'cùng remoteAddress → cùng bộ đếm');
  assert.equal(hit(limiter, undefined, '192.168.1.11').passed, true, 'remoteAddress khác → bộ đếm khác');
});

test('RL-08 không biết IP thì vẫn chặn được (không crash)', () => {
  const limiter = createRateLimiter({ limit: 1 });
  assert.equal(hit(limiter).passed, true);
  assert.equal(hit(limiter).passed, false);
});

test('RL-09 thông báo tự định nghĩa được tôn trọng', () => {
  const limiter = createRateLimiter({ limit: 1, message: 'CHẶN RỒI' });
  hit(limiter, '10.0.0.8');
  const { res } = hit(limiter, '10.0.0.8');
  const body = res.body as { error: { message: string } };
  assert.equal(body.error.message, 'CHẶN RỒI');
});
