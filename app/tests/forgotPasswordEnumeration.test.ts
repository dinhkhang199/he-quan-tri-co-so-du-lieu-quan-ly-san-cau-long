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

async function simulateForgot(app: express.Express, body: Record<string, unknown>) {
  return new Promise<{ status: number; body: Record<string, unknown> }>((resolve) => {
    const server = app.listen(0, async () => {
      const address = server.address();
      const port = typeof address === 'object' && address ? address.port : 0;
      try {
        const res = await fetch(`http://127.0.0.1:${port}/auth/password/forgot`, {
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

test('forgot password endpoint in production returns identical response shape for (1) matched + mail success, (2) matched + mail failure, (3) unmatched', async () => {
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

  // 1. Matched account + normal mailer (customer1)
  const matchedNormal = await simulateForgot(app1, {
    username: 'customer1',
    email: 'customer1@badmintonpro.local',
  });

  // 2. Matched account + failing SMTP (customer1 on app2)
  const matchedMailFailure = await simulateForgot(app2, {
    username: 'customer1',
    email: 'customer1@badmintonpro.local',
  });

  // 3. Unmatched account (non-existent user on app1)
  const unmatched = await simulateForgot(app1, {
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
