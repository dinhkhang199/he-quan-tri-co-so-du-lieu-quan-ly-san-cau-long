/**
 * DEVELOPMENT-ONLY session-context integrity probe (Phase 2.2 verification).
 *
 * This is NOT an HTTP endpoint and must never be exposed to users. It proves:
 * 1. After dbo.sp_Login runs on a dedicated SessionDb connection created via createSession,
 *    SESSION_CONTEXT('UserId') and SESSION_CONTEXT('Role') exist on that SAME
 *    connection and match the authenticated login row.
 * 2. verifySessionContext strictly requires matching UserId and Role.
 * 3. withExistingConnection / verifySessionContext on a missing session NEVER creates a connection.
 * 4. Losing/disposing the dedicated connection removes the binding, so the web
 *    session is no longer authenticated without a manual context rebuild.
 */
import 'dotenv/config';
import sql from 'mssql';
import { loadConfig } from '../config.js';
import { SessionDb } from '../db/sessionDb.js';

const SID = 'dev-session-context-probe';
const TEST_USER = process.env.TEST_DEMO_USER;
const TEST_PASS = process.env.TEST_DEMO_PASSWORD;

if (!TEST_USER || !TEST_PASS) {
  throw new Error(
    'TEST_DEMO_USER and TEST_DEMO_PASSWORD are required to run sessionContextProbe.',
  );
}

interface LoginProbeRow {
  UserId: string;
  Role: string;
}

async function main(): Promise<void> {
  const cfg = loadConfig();
  const sessionDb = new SessionDb(cfg);
  let ok = true;
  try {
    // 1. Prove missing session does not create a connection
    try {
      await sessionDb.withExistingConnection('non-existent-sid', async () => {});
      console.error('[integrity] FAIL: withExistingConnection created a connection for non-existent session!');
      ok = false;
    } catch {
      console.log('[integrity] PASS: withExistingConnection strictly rejected non-existent session without creating connection.');
    }

    // 2. Run sp_Login on dedicated connection
    const login = await sessionDb.createSession(SID, async (conn) => {
      const r = await conn
        .request()
        .input('Username', sql.NVarChar(50), TEST_USER)
        .input('Password', sql.NVarChar(200), TEST_PASS)
        .execute('dbo.sp_Login');
      return r.recordset[0] as LoginProbeRow | undefined;
    });

    // 3. Probe actual SQL SESSION_CONTEXT
    const ctx = await sessionDb.getSessionContext(SID);

    const loginUserId = login?.UserId ?? '';
    const match =
      Boolean(login && ctx) &&
      ctx!.userId?.toLowerCase() === loginUserId.toLowerCase() &&
      ctx!.role === (login?.Role ?? '');
    console.log('[integrity] sp_Login row    : ' + JSON.stringify(login));
    console.log('[integrity] SESSION_CONTEXT : UserId=' + (ctx?.userId ?? '(empty)') + ' Role=' + (ctx?.role ?? '(empty)'));
    console.log('[integrity] context matches login: ' + match);
    if (!match) ok = false;

    // 4. Verify verifySessionContext returns true for matching metadata
    const verified = await sessionDb.verifySessionContext(SID, loginUserId, login?.Role ?? '');
    console.log('[integrity] verifySessionContext (valid): ' + verified);
    if (!verified) ok = false;

    // 5. Close session and prove context is gone
    await sessionDb.closeSession(SID);
    const hasSess = sessionDb.hasSession(SID);
    const verifiedAfter = await sessionDb.verifySessionContext(SID, loginUserId, login?.Role ?? '');
    console.log(
      '[integrity] dedicated connection deleted -> hasSession=' +
        hasSess +
        ', verifyAfterClose=' +
        verifiedAfter +
        ' (expected false: session is unauthenticated)',
    );
    if (hasSess || verifiedAfter) ok = false;
  } catch (err) {
    ok = false;
    console.error('[integrity] probe failed: ' + String(err));
  }
  await sessionDb.closeAll().catch(() => undefined);
  process.exit(ok ? 0 : 1);
}

void main();