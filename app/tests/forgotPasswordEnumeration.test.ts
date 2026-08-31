import 'dotenv/config';
import test from 'node:test';
import assert from 'node:assert/strict';
import express from 'express';
import session from 'express-session';
import { createAuthRouter } from '../src/server/routes/auth.js';
import { loadConfig } from '../src/server/config.js';
import type { SessionDb } from '../src/server/db/sessionDb.js';

const mockSessionDb: SessionDb = {
  get: () => undefined,
  create: async () => ({
    userId: 'mock-user-id',
    username: 'mockuser',
    role: 'CUSTOMER',
    connection: {} as unknown as import('mssql').ConnectionPool,
    lastActive: Date.now(),
    createdAt: Date.now(),
  }),
  destroy: async () => {},
  touch: () => {},
  count: () => 0,
  cleanup: async () => {},
};

async function simulateRequest(
  app: express.Express,
  path: string,
  body: Record<string, unknown>,
) {
  return new Promise<{ status: number; body: Record<string, unknown> }>((resolve) => {
    const server = app.listen(0, async () => {
      const address = server.address();
      const port = typeof address === 'object' && address ? address.port : 0;
      try {
        const res = await fetch(`http://127.0.0.1:${port}${path}`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(body),
        });
        const json = (await res.json()) as Record<string, unknown>;
        resolve({ status: res.status, body: json });
      } finally {
        server.close();
      }
    });
  });
}

test('forgot password endpoint in production returns identical response shape for (1) matched + fallback, (2) matched + simulated SMTP failure, (3) unmatched', async () => {
  const baseConfig = loadConfig();

  // App 1: Production config with default / fallback mailer
  const prodConfig1 = { ...baseConfig, isProd: true };
  const app1 = express();
  app1.use(express.json());
  app1.use(session({ secret: 'test', resave: false, saveUninitialized: false }));
  app1.use('/auth', createAuthRouter(prodConfig1, mockSessionDb));

  // App 2: Production config with failing SMTP host (simulating SMTP throw)
  const prodConfigFailingSmtp = {
    ...baseConfig,
    isProd: true,
    smtpHost: '127.0.0.1',
    smtpPort: 65530, // Unreachable port causing sendMail to throw
    smtpUser: 'baduser',
    smtpPassword: 'badpassword',
    mailFrom: 'noreply@badmintonpro.local',
  };
  const app2 = express();
  app2.use(express.json());
  app2.use(session({ secret: 'test', resave: false, saveUninitialized: false }));
  app2.use('/auth', createAuthRouter(prodConfigFailingSmtp, mockSessionDb));

  // 1. Matched account + fallback mailer (customer1)
  const matchedNormal = await simulateRequest(app1, '/auth/password/forgot', {
    username: 'customer1',
    email: 'customer1@badmintonpro.local',
  });

  // 2. Matched account + simulated SMTP failure (customer1 on app2)
  const matchedMailFailure = await simulateRequest(app2, '/auth/password/forgot', {
    username: 'customer1',
    email: 'customer1@badmintonpro.local',
  });

  // 3. Unmatched account (non-existent user on app1)
  const unmatched = await simulateRequest(app1, '/auth/password/forgot', {
    username: 'non_existent_user_999',
    email: 'unknown@example.com',
  });

  // PROOF 1: All 3 responses have identical HTTP Status (200 OK)
  assert.equal(matchedNormal.status, 200);
  assert.equal(matchedMailFailure.status, 200);
  assert.equal(unmatched.status, 200);

  // PROOF 2: All 3 responses have identical response keys ['expiresInSeconds', 'message']
  const expectedKeys = ['expiresInSeconds', 'message'];
  assert.deepEqual(Object.keys(matchedNormal.body).sort(), expectedKeys);
  assert.deepEqual(Object.keys(matchedMailFailure.body).sort(), expectedKeys);
  assert.deepEqual(Object.keys(unmatched.body).sort(), expectedKeys);

  // PROOF 3: All 3 responses have identical generic message and expiresInSeconds
  assert.equal(matchedNormal.body.message, unmatched.body.message);
  assert.equal(matchedMailFailure.body.message, unmatched.body.message);
  assert.equal(matchedNormal.body.expiresInSeconds, 600);
  assert.equal(matchedMailFailure.body.expiresInSeconds, 600);
  assert.equal(unmatched.body.expiresInSeconds, 600);

  // PROOF 4: Zero side-channel leaks across all 3 scenarios
  for (const resp of [matchedNormal, matchedMailFailure, unmatched]) {
    assert.equal(resp.body.emailMasked, undefined);
    assert.equal(resp.body.matched, undefined);
    assert.equal(resp.body.developmentCode, undefined);
    assert.equal(resp.body.emailSent, undefined);
  }
});

test('password reset endpoint normalizes failure responses (50210 nonexistent, 50211 no OTP, 50212 wrong OTP) into identical generic 400 error', async () => {
  const baseConfig = loadConfig();
  const prodConfig = { ...baseConfig, isProd: true };
  const app = express();
  app.use(express.json());
  app.use(session({ secret: 'test', resave: false, saveUninitialized: false }));
  app.use('/auth', createAuthRouter(prodConfig, mockSessionDb));

  // Case 1: Nonexistent account (triggers SQL 50210)
  const nonexistent = await simulateRequest(app, '/auth/password/reset', {
    username: 'non_existent_user_999',
    email: 'nonexistent@example.com',
    resetCode: '123456',
    password: 'NewValidPassword123',
    confirmPassword: 'NewValidPassword123',
  });

  // Case 2: Existing account without requested OTP or expired (customer2 - triggers SQL 50211)
  const noOtp = await simulateRequest(app, '/auth/password/reset', {
    username: 'customer2',
    email: 'customer2@badmintonpro.local',
    resetCode: '123456',
    password: 'NewValidPassword123',
    confirmPassword: 'NewValidPassword123',
  });

  // Case 3: Existing account with requested OTP but wrong code entered (triggers SQL 50212)
  // First request OTP for customer1:
  await simulateRequest(app, '/auth/password/forgot', {
    username: 'customer1',
    email: 'customer1@badmintonpro.local',
  });
  // Then submit wrong OTP code:
  const wrongOtp = await simulateRequest(app, '/auth/password/reset', {
    username: 'customer1',
    email: 'customer1@badmintonpro.local',
    resetCode: '000000',
    password: 'NewValidPassword123',
    confirmPassword: 'NewValidPassword123',
  });

  // PROOF 1: All 3 failure scenarios return identical HTTP 400 Bad Request
  assert.equal(nonexistent.status, 400);
  assert.equal(noOtp.status, 400);
  assert.equal(wrongOtp.status, 400);

  // PROOF 2: All 3 return identical generic public message with code: null
  const expectedPublicError = {
    code: null,
    message: 'Mã khôi phục hoặc thông tin tài khoản không hợp lệ.',
  };
  assert.deepEqual(nonexistent.body, { error: expectedPublicError });
  assert.deepEqual(noOtp.body, { error: expectedPublicError });
  assert.deepEqual(wrongOtp.body, { error: expectedPublicError });
});
