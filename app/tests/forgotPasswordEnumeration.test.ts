import 'dotenv/config';
import test from 'node:test';
import assert from 'node:assert/strict';
import express from 'express';
import session from 'express-session';
import { createAuthRouter } from '../src/server/routes/auth.js';
import { loadConfig } from '../src/server/config.js';
import type { SessionDb } from '../src/server/sessionDb.js';

const mockSessionDb: SessionDb = {
  get: () => undefined,
  create: async () => ({
    userId: 'mock-user-id',
    username: 'mockuser',
    role: 'CUSTOMER',
    connection: {} as any,
    lastActive: Date.now(),
    createdAt: Date.now(),
  }),
  destroy: async () => {},
  touch: () => {},
  count: () => 0,
  cleanup: async () => {},
};

test('forgot password endpoint in production returns identical response shape for matched and unmatched accounts', async () => {
  const baseConfig = loadConfig();
  const prodConfig = { ...baseConfig, isProd: true };
  const router = createAuthRouter(prodConfig, mockSessionDb);

  const app = express();
  app.use(express.json());
  app.use(session({ secret: 'test', resave: false, saveUninitialized: false }));
  app.use('/auth', router);

  async function simulateForgot(body: Record<string, unknown>) {
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

  // 1. Matched account (e.g. customer1)
  const matched = await simulateForgot({
    username: 'customer1',
    email: 'customer1@badmintonpro.local',
  });

  // 2. Unmatched account (non-existent user)
  const unmatched = await simulateForgot({
    username: 'non_existent_user_999',
    email: 'unknown@example.com',
  });

  // PROOF: Both responses have identical HTTP Status (200)
  assert.equal(matched.status, 200);
  assert.equal(unmatched.status, 200);

  // PROOF: Both responses have identical keys
  assert.deepEqual(Object.keys(matched.body).sort(), ['expiresInSeconds', 'message']);
  assert.deepEqual(Object.keys(unmatched.body).sort(), ['expiresInSeconds', 'message']);

  // PROOF: Both responses have identical message and expiresInSeconds
  assert.equal(matched.body.message, unmatched.body.message);
  assert.equal(matched.body.expiresInSeconds, 600);
  assert.equal(unmatched.body.expiresInSeconds, 600);

  // PROOF: Neither response leaks diagnostic fields in production
  assert.equal(matched.body.emailMasked, undefined);
  assert.equal(unmatched.body.emailMasked, undefined);
  assert.equal(matched.body.matched, undefined);
  assert.equal(unmatched.body.matched, undefined);
  assert.equal(matched.body.developmentCode, undefined);
  assert.equal(unmatched.body.developmentCode, undefined);
});
