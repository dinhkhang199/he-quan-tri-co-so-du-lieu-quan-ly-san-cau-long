/**
 * LOAD TEST — tầng HTTP (Express + express-session + SessionDb)
 *
 * Mô phỏng đúng hành vi người dùng thật: POST /api/auth/login (nhận cookie)
 * → POST /api/bookings với cookie đó. Đo cả chi phí tầng web (Node 1 luồng,
 * MemoryStore của express-session, số file descriptor/socket) — những thứ mà
 * loadtest_db.mjs không thấy.
 *
 * Cách chạy (từ thư mục app/, server phải đang chạy):
 *   node scripts/loadtest_http.mjs --users=2000 --slot=same
 *
 * Tham số: --users, --slot=same|spread, --courts, --day, --base=http://localhost:3000
 */
const argv = new Map(
  process.argv.slice(2).map((a) => {
    const [k, v = 'true'] = a.replace(/^--/, '').split('=');
    return [k, v];
  }),
);
const USERS = Number(argv.get('users') ?? 2000);
const SLOT = argv.get('slot') ?? 'same';
const COURTS = Math.min(5, Math.max(1, Number(argv.get('courts') ?? 5)));
const DAY_OFFSET = Number(argv.get('day') ?? 1);
const BASE = argv.get('base') ?? `http://localhost:${process.env.APP_PORT ?? 3000}`;
const PASSWORD = argv.get('password') ?? 'load123';

const COURT_IDS = [1, 2, 3, 4, 5].map((i) => `C1000001-0000-0000-0000-00000000000${i}`);

const pad = (n) => String(n).padStart(2, '0');
function slotFor(i) {
  const courtId = SLOT === 'same' ? COURT_IDS[0] : COURT_IDS[i % COURTS];
  const hour = SLOT === 'same' ? 7 : 7 + (Math.floor(i / COURTS) % 14);
  const d = new Date();
  d.setDate(d.getDate() + DAY_OFFSET);
  const day = `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
  return {
    courtId,
    startTime: `${day}T${pad(hour)}:00:00`,
    endTime: `${day}T${pad(hour + 1)}:00:00`,
  };
}

const pct = (arr, p) => {
  if (arr.length === 0) return 0;
  const s = [...arr].sort((a, b) => a - b);
  return Math.round(s[Math.min(s.length - 1, Math.floor((p / 100) * s.length))]);
};
const summary = (name, ms) =>
  `${name.padEnd(14)} n=${String(ms.length).padEnd(6)} p50=${pct(ms, 50)}ms p90=${pct(ms, 90)}ms p95=${pct(ms, 95)}ms p99=${pct(ms, 99)}ms max=${Math.round(Math.max(0, ...ms))}ms`;

const tally = new Map();
const note = (k) => tally.set(k, (tally.get(k) ?? 0) + 1);

async function loginHttp(i) {
  const username = 'loadtest' + String(i + 1).padStart(6, '0');
  const t0 = performance.now();
  const res = await fetch(`${BASE}/api/auth/login`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ username, password: PASSWORD }),
  });
  const ms = performance.now() - t0;
  const setCookie = res.headers.get('set-cookie');
  if (!res.ok || !setCookie) {
    note(`login HTTP ${res.status}`);
    throw new Error(`login ${res.status}`);
  }
  return { cookie: setCookie.split(';')[0], ms };
}

async function bookHttp(session, i) {
  const t0 = performance.now();
  const res = await fetch(`${BASE}/api/bookings`, {
    method: 'POST',
    headers: { 'content-type': 'application/json', cookie: session.cookie },
    body: JSON.stringify(slotFor(i)),
  });
  const ms = performance.now() - t0;
  let code = '';
  if (!res.ok) {
    const body = await res.json().catch(() => ({}));
    code = body?.error?.code ? ` code=${body.error.code}` : '';
  }
  note(`book HTTP ${res.status}${code}`);
  return { ms, ok: res.ok };
}

console.log(`\n=== LOAD TEST HTTP: ${USERS} user → ${BASE} (slot=${SLOT}) ===\n`);

const tL = performance.now();
const loginRes = await Promise.allSettled([...Array(USERS).keys()].map(loginHttp));
const loginWall = performance.now() - tL;
const sessions = loginRes.filter((r) => r.status === 'fulfilled').map((r) => r.value);
for (const r of loginRes) if (r.status === 'rejected') note(`login error: ${String(r.reason?.message ?? r.reason).slice(0, 50)}`);

console.log('--- PHA 1: ĐĂNG NHẬP ---');
console.log(summary('POST /login', sessions.map((s) => s.ms)));
console.log(`thành công=${sessions.length}/${USERS}  wall=${Math.round(loginWall)}ms => ~${Math.round((sessions.length / loginWall) * 1000)} login/s\n`);

const tB = performance.now();
const bookRes = await Promise.allSettled(sessions.map((s, i) => bookHttp(s, i)));
const bookWall = performance.now() - tB;
const okMs = bookRes.filter((r) => r.status === 'fulfilled' && r.value.ok).map((r) => r.value.ms);
const allMs = bookRes.filter((r) => r.status === 'fulfilled').map((r) => r.value.ms);

console.log('--- PHA 2: ĐẶT SÂN ĐỒNG THỜI ---');
console.log(summary('POST /bookings', allMs));
console.log(`201 Created=${okMs.length}  wall=${Math.round(bookWall)}ms => ~${Math.round((okMs.length / bookWall) * 1000)} booking/s\n`);

console.log('--- KẾT QUẢ THEO MÃ HTTP ---');
for (const [k, v] of [...tally.entries()].sort((a, b) => b[1] - a[1])) console.log(`  ${String(v).padStart(6)}  ${k}`);

console.log('\nGỢI Ý: gọi GET /api/health trong lúc test để xem sessionDb.activeCount() (số connection SQL đang bị giữ).');
process.exit(0);
