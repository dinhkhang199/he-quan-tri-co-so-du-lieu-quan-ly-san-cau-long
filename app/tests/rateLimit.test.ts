import assert from 'node:assert/strict';
import test from 'node:test';
import type { NextFunction, Request, Response } from 'express';
import { createRateLimiter } from '../src/server/middleware/rateLimit.js';

test('login limiter accepts up to limit then returns 429', () => {
  const limiter = createRateLimiter(2, 60_000);
  let nextCalls = 0;
  let status = 200;
  const req = { ip: '127.0.0.1', socket: {} } as Request;
  const res = {
    setHeader: () => undefined,
    status(code: number) { status = code; return this; },
    json: () => undefined,
  } as unknown as Response;
  const next = (() => { nextCalls += 1; }) as NextFunction;
  limiter(req, res, next);
  limiter(req, res, next);
  limiter(req, res, next);
  assert.equal(nextCalls, 2);
  assert.equal(status, 429);
});

test('rate limiter supports custom message and options object', () => {
  const customMessage = 'Quá nhiều lần thử đăng ký. Vui lòng thử lại sau.';
  const limiter = createRateLimiter(1, { windowMs: 10_000, message: customMessage });
  let status = 200;
  let responseBody: unknown = null;
  const req = { ip: '10.0.0.1', socket: {} } as Request;
  const res = {
    setHeader: () => undefined,
    status(code: number) { status = code; return this; },
    json(data: unknown) { responseBody = data; return this; },
  } as unknown as Response;
  const next = (() => undefined) as NextFunction;
  limiter(req, res, next);
  limiter(req, res, next);
  assert.equal(status, 429);
  assert.deepEqual(responseBody, { error: { code: null, message: customMessage } });
});
