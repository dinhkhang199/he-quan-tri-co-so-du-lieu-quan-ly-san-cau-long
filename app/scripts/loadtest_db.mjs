/**
 * LOAD TEST — tầng DATABASE (bỏ qua HTTP/Express)
 *
 * Mô phỏng đúng cơ chế SessionDb của app: MỖI "người dùng" = 1 ConnectionPool
 * riêng (min = max = 1) → sp_Login trên connection đó → giữ nguyên connection đó
 * để SESSION_CONTEXT sống → rồi TẤT CẢ cùng gọi sp_BookCourt một lúc.
 *
 * Cách chạy (từ thư mục app/, vì cần node_modules/mssql và .env):
 *   node scripts/loadtest_db.mjs --users=2000 --slot=same
 *   node scripts/loadtest_db.mjs --users=500  --slot=spread --courts=5
 *
 * Tham số:
 *   --users=N       số phiên đăng nhập đồng thời (mặc định 2000)
 *   --slot=same     tất cả đặt CÙNG sân + CÙNG khung giờ (worst case, test tranh chấp)
 *   --slot=spread   rải đều trên nhiều sân + nhiều khung giờ (test thông lượng)
 *   --courts=K      số sân dùng khi slot=spread (1..5; sân 06 inactive nên loại)
 *   --login-batch=B đăng nhập theo lô B (mặc định 0 = bắn hết cùng lúc)
 *   --day=D         đặt sân cho ngày hiện tại + D (mặc định 1 = ngày mai)
 *   --request-timeout=MS  (mặc định 60000; mssql default 15000 sẽ timeout hàng loạt)
 *
 * Yêu cầu trước khi chạy:
 *   sqlcmd -S ".\SQLEXPRESS" -E -f 65001 -i ..\tests\load\seed_load_users.sql
 */
import 'dotenv/config';
import sql from 'mssql';

// ---------- tham số ----------
const argv = new Map(
  process.argv.slice(2).map((a) => {
    const [k, v = 'true'] = a.replace(/^--/, '').split('=');
    return [k, v];
  }),
);
const USERS = Number(argv.get('users') ?? 2000);
const SLOT = argv.get('slot') ?? 'same';
const COURTS = Math.min(5, Math.max(1, Number(argv.get('courts') ?? 5)));
const LOGIN_BATCH = Number(argv.get('login-batch') ?? 0);
const DAY_OFFSET = Number(argv.get('day') ?? 1);
const REQUEST_TIMEOUT = Number(argv.get('request-timeout') ?? 60000);
const PASSWORD = argv.get('password') ?? 'load123';

const COURT_IDS = [1, 2, 3, 4, 5].map(
  (i) => `C1000001-0000-0000-0000-00000000000${i}`,
);

const cfg = {
  server: process.env.DB_SERVER ?? 'localhost\\SQLEXPRESS',
  database: process.env.DB_DATABASE ?? 'BadmintonCourtManagement',
  user: process.env.DB_USER,
  password: process.env.DB_PASSWORD,
  connectionTimeout: Number(process.env.DB_CONNECT_TIMEOUT_MS ?? 15000),
  requestTimeout: REQUEST_TIMEOUT,
  options: {
    trustServerCertificate: (process.env.DB_TRUST_SERVER_CERTIFICATE ?? 'true') === 'true',
    encrypt: true,
  },
  pool: { max: 1, min: 1, idleTimeoutMillis: 30000 },
};

if (!cfg.user || !cfg.password) {
  console.error('Thiếu DB_USER / DB_PASSWORD. Hãy chạy từ thư mục app/ (có file .env).');
  process.exit(1);
}

// ---------- tiện ích thống kê ----------
const pct = (arr, p) => {
  if (arr.length === 0) return 0;
  const s = [...arr].sort((a, b) => a - b);
  return Math.round(s[Math.min(s.length - 1, Math.floor((p / 100) * s.length))]);
};
const summary = (name, ms) =>
  `${name.padEnd(16)} n=${String(ms.length).padEnd(6)} p50=${pct(ms, 50)}ms p90=${pct(ms, 90)}ms p95=${pct(ms, 95)}ms p99=${pct(ms, 99)}ms max=${Math.round(Math.max(0, ...ms))}ms`;

const errors = new Map();
const noteError = (err) => {
  const key = err?.number ? `SQL ${err.number}` : err?.code ? String(err.code) : (err?.message ?? 'unknown').slice(0, 60);
  errors.set(key, (errors.get(key) ?? 0) + 1);
};

// ---------- 1. ĐĂNG NHẬP ĐỒNG THỜI ----------
async function login(i) {
  const username = 'loadtest' + String(i + 1).padStart(6, '0');
  const pool = new sql.ConnectionPool(cfg);
  const t0 = performance.now();
  await pool.connect();
  const r = await pool
    .request()
    .input('Username', sql.NVarChar(50), username)
    .input('Password', sql.NVarChar(200), PASSWORD)
    .execute('dbo.sp_Login');
  return { pool, userId: r.recordset[0].UserId, ms: performance.now() - t0, username };
}

// ---------- 2. ĐẶT SÂN ĐỒNG THỜI ----------
// Tính giờ NGAY TRÊN SQL SERVER để tránh lệch múi giờ giữa Node và SQL.
const BOOK_BATCH = `
DECLARE @d DATE = CAST(DATEADD(DAY, @DayOffset, SYSDATETIME()) AS DATE);
DECLARE @s DATETIME2(0) = DATEADD(MINUTE, @StartMinute, CAST(@d AS DATETIME2(0)));
DECLARE @e DATETIME2(0) = DATEADD(MINUTE, 60, @s);
DECLARE @bid UNIQUEIDENTIFIER, @cost DECIMAL(12,0);
EXEC dbo.sp_BookCourt
     @UserId = @UserId, @CourtId = @CourtId,
     @StartTime = @s, @EndTime = @e,
     @BookingId = @bid OUTPUT, @TotalCost = @cost OUTPUT;
SELECT @bid AS BookingId, @cost AS TotalCost, @s AS StartTime, @e AS EndTime;`;

async function book(session, i) {
  // slot=same  : mọi người đặt sân 01, 07:00-08:00 ngày mai  → tranh chấp tối đa
  // slot=spread: rải trên COURTS sân × 15 khung giờ (07:00..21:00)
  const courtId = SLOT === 'same' ? COURT_IDS[0] : COURT_IDS[i % COURTS];
  const startMinute = SLOT === 'same' ? 7 * 60 : (7 + (Math.floor(i / COURTS) % 14)) * 60;
  const t0 = performance.now();
  const r = await session.pool
    .request()
    .input('UserId', sql.UniqueIdentifier, session.userId)
    .input('CourtId', sql.UniqueIdentifier, courtId)
    .input('DayOffset', sql.Int, DAY_OFFSET)
    .input('StartMinute', sql.Int, startMinute)
    .query(BOOK_BATCH);
  return { ms: performance.now() - t0, bookingId: r.recordset[0]?.BookingId };
}

// ---------- chạy ----------
console.log(`\n=== LOAD TEST DB: ${USERS} phiên đăng nhập → ${USERS} lần đặt sân (slot=${SLOT}) ===`);
console.log(`server=${cfg.server} db=${cfg.database} login=${cfg.user} requestTimeout=${REQUEST_TIMEOUT}ms\n`);

const sessions = [];
const loginMs = [];
let loginFail = 0;

const tLogin = performance.now();
const indices = [...Array(USERS).keys()];
const batches = LOGIN_BATCH > 0
  ? Array.from({ length: Math.ceil(USERS / LOGIN_BATCH) }, (_, b) => indices.slice(b * LOGIN_BATCH, (b + 1) * LOGIN_BATCH))
  : [indices];

for (const batch of batches) {
  const settled = await Promise.allSettled(batch.map(login));
  for (const s of settled) {
    if (s.status === 'fulfilled') {
      sessions.push(s.value);
      loginMs.push(s.value.ms);
    } else {
      loginFail++;
      noteError(s.reason);
    }
  }
}
const loginWall = performance.now() - tLogin;

console.log('--- PHA 1: ĐĂNG NHẬP ---');
console.log(summary('login', loginMs));
console.log(`thành công=${sessions.length}  thất bại=${loginFail}  tổng thời gian=${Math.round(loginWall)}ms  => ~${Math.round((sessions.length / loginWall) * 1000)} login/s`);
console.log(`connection SQL đang giữ: ${sessions.length} (đúng bằng số phiên đăng nhập — đây là hệ quả của SESSION_CONTEXT Option A)\n`);

// PHA 2: barrier — tất cả bấm "Đặt sân" cùng một lúc
const bookMs = [];
let bookOk = 0;
let bookFail = 0;
const tBook = performance.now();
const results = await Promise.allSettled(sessions.map((s, i) => book(s, i)));
const bookWall = performance.now() - tBook;
for (const r of results) {
  if (r.status === 'fulfilled') {
    bookOk++;
    bookMs.push(r.value.ms);
  } else {
    bookFail++;
    noteError(r.reason);
  }
}

console.log('--- PHA 2: ĐẶT SÂN ĐỒNG THỜI ---');
console.log(summary('sp_BookCourt', bookMs));
console.log(`thành công=${bookOk}  thất bại=${bookFail}  tổng thời gian=${Math.round(bookWall)}ms  => ~${Math.round((bookOk / bookWall) * 1000)} booking/s`);

if (errors.size > 0) {
  console.log('\n--- PHÂN LOẠI LỖI ---');
  for (const [k, v] of [...errors.entries()].sort((a, b) => b[1] - a[1])) {
    console.log(`  ${String(v).padStart(6)}  ${k}`);
  }
}

// PHA 3: kiểm tra bất biến nghiệp vụ + dọn connection
if (sessions.length > 0) {
  try {
    const check = await sessions[0].pool.request().query(`
      SELECT COUNT(*) AS PendingCungKhung
      FROM dbo.Bookings
      WHERE CourtId = '${COURT_IDS[0]}'
        AND Status = N'PENDING'
        AND StartTime = DATEADD(MINUTE, ${7 * 60}, CAST(CAST(DATEADD(DAY, ${DAY_OFFSET}, SYSDATETIME()) AS DATE) AS DATETIME2(0)));`);
    console.log(`\nSố PENDING chồng nhau trên sân 01 / 07:00: ${check.recordset[0].PendingCungKhung}`);
    console.log('(HỢP LỆ theo contract: PENDING được phép overlap; chỉ BOOKED mới độc quyền khung giờ)');
  } catch (e) {
    noteError(e);
  }
}

await Promise.allSettled(sessions.map((s) => s.pool.close()));
console.log('\nĐã đóng toàn bộ connection. Chạy tests/load/observe_contention.sql TRONG LÚC test để xem khoá/wait.');
process.exit(0);
