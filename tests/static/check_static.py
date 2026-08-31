#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Kiem tra TINH (static) toan bo project: SQL + app.
Chay duoc o bat ky may nao co Python 3, KHONG can SQL Server, KHONG can npm install.

    python3 tests/static/check_static.py

Muc dich: bat cac loi co the phat hien ma khong can chay DB
(so luong doi tuong, guard @Role IS NULL, XACT_ABORT, ROLLBACK/THROW,
index duoc bao ve boi IF NOT EXISTS, seed co an toan voi unique index moi,
ma loi SQL <-> ban do loi cua app, retry bao quanh cac SP thay doi du lieu,
bien moi trong .env.example khop config.ts...).

Neu co thu vien sqlglot thi parse them tung batch T-SQL (chi canh bao, khong
tinh la FAIL, vi sqlglot khong ho tro tron ven moi cu phap T-SQL).
"""
from __future__ import annotations

import io
import os
import re
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
DB = os.path.join(ROOT, 'database')
APP = os.path.join(ROOT, 'app')

results: list[tuple[str, str, bool, str]] = []


def read(path: str) -> str:
    with io.open(path, encoding='utf-8-sig', errors='replace') as f:
        return f.read()


def check(tid: str, name: str, ok: bool, note: str = '') -> None:
    results.append((tid, name, bool(ok), note))


SQL = {name: read(os.path.join(DB, name)) for name in sorted(os.listdir(DB)) if name.endswith('.sql')}


def app_file(rel: str) -> str:
    return read(os.path.join(APP, rel))


# ---------------------------------------------------------------- SQL: dem doi tuong
def count(pattern: str, text: str) -> int:
    return len(re.findall(pattern, text, re.IGNORECASE))


EXPECTED_COUNTS = [
    ('ST-01', 'Tables = 5', r'^\s*CREATE\s+TABLE', '01_tables_constraints.sql', 5),
    ('ST-02', 'Views = 4', r'CREATE\s+VIEW', '05_views.sql', 4),
    ('ST-03', 'Functions = 2', r'CREATE\s+FUNCTION', '04_functions.sql', 2),
    ('ST-04', 'Procedures = 14', r'CREATE\s+PROCEDURE', '06_procedures.sql', 14),
    ('ST-05', 'Triggers = 6', r'CREATE\s+TRIGGER', '07_triggers.sql', 6),
]
for tid, name, pat, fname, expected in EXPECTED_COUNTS:
    got = len(re.findall(pat, SQL[fname], re.IGNORECASE | re.MULTILINE))
    check(tid, name, got == expected, 'thuc te = %d' % got)

# ---------------------------------------------------------------- SQL: tung stored procedure
proc_text = SQL['06_procedures.sql']
proc_blocks: dict[str, str] = {}
marks = [(m.start(), m.group(1)) for m in re.finditer(r'CREATE\s+PROCEDURE\s+dbo\.(\w+)', proc_text, re.IGNORECASE)]
for i, (pos, pname) in enumerate(marks):
    end = marks[i + 1][0] if i + 1 < len(marks) else len(proc_text)
    proc_blocks[pname] = proc_text[pos:end]

missing_xact = [p for p, b in proc_blocks.items() if 'SET XACT_ABORT ON' not in b]
check('ST-06', 'Moi SP deu co SET XACT_ABORT ON', not missing_xact, ', '.join(missing_xact))

missing_rollback = [
    p for p, b in proc_blocks.items()
    if 'BEGIN TRAN' in b.upper() and not ('ROLLBACK' in b.upper() and 'THROW;' in b.upper())
]
check('ST-07', 'SP co transaction deu ROLLBACK + THROW lai trong CATCH', not missing_rollback, ', '.join(missing_rollback))

session_procs = {p: b for p, b in proc_blocks.items() if '@SessionUserId' in b}
no_role_guard = [p for p, b in session_procs.items() if 'IF @Role IS NULL' not in b and '@Role' in b]
check('ST-08', 'FIX-NULLROLE: moi SP doc @Role deu chan @Role IS NULL', not no_role_guard, ', '.join(no_role_guard))
check('ST-09', 'So luong guard "IF @Role IS NULL" = 9', proc_text.count('IF @Role IS NULL') == 9,
      'thuc te = %d' % proc_text.count('IF @Role IS NULL'))

check('ST-10', 'KHONG co SET LOCK_TIMEOUT trong bat ky script SQL nao (chi dat o tang app)',
      not any('SET LOCK_TIMEOUT' in t.upper() for t in SQL.values()))

naked_dynamic = [n for n, t in SQL.items() if re.search(r'EXEC\s*\(\s*@', t, re.IGNORECASE)]
check('ST-11', 'Khong co dynamic SQL ghep chuoi (EXEC(@sql))', not naked_dynamic, ', '.join(naked_dynamic))

# ---------------------------------------------------------------- SQL: index / constraint
idx = SQL['03_indexes.sql']
create_idx = re.findall(r'CREATE\s+(?:UNIQUE\s+)?(?:NONCLUSTERED\s+)?INDEX\s+(\w+)', idx, re.IGNORECASE)
check('ST-12', 'Moi CREATE INDEX deu duoc bao ve boi IF NOT EXISTS',
      count(r'IF\s+NOT\s+EXISTS', idx) >= len(create_idx),
      '%d index / %d guard' % (len(create_idx), count(r'IF\s+NOT\s+EXISTS', idx)))

for name in ['IX_Bookings_Booked_Court_Time', 'IX_Bookings_Pending_Court_Time', 'IX_Bookings_User_Start',
             'IX_Bookings_Start_Status', 'IX_Notifications_Unread']:
    check('ST-13', 'IMP-02 con index %s' % name, name in idx)

check('ST-14', 'IMP-09 co UQ_Bookings_OnePendingPerUserSlot', 'UQ_Bookings_OnePendingPerUserSlot' in idx)
check('ST-15', 'IMP-09 la filtered index chi ap dung cho PENDING',
      bool(re.search(r"UQ_Bookings_OnePendingPerUserSlot.*?WHERE\s+Status\s*=\s*N'PENDING'", idx, re.S | re.I)))
check('ST-16', 'IMP-09 dung dung khoa (UserId, CourtId, StartTime)',
      bool(re.search(r'UQ_Bookings_OnePendingPerUserSlot.*?\(\s*UserId\s*,\s*CourtId\s*,\s*StartTime\s*\)', idx, re.S | re.I)))
check('ST-17', 'Filtered index yeu cau SET QUOTED_IDENTIFIER ON trong cung script',
      'SET QUOTED_IDENTIFIER ON' in idx)

constraints = SQL['01_tables_constraints.sql']
for cname in ['CK_Users_Username_NotBlank', 'CK_Users_PhoneNumber_Digits', 'CK_Courts_CourtName_NotBlank',
              'CK_Courts_Address_NotBlank', 'CK_Bookings_Duration_60_180', 'CK_Bookings_Slot30',
              'CK_Bookings_OperatingHours', 'CK_Bookings_SameDay', 'CK_Bookings_TotalCost_GE0',
              'CK_Notifications_Message_NotBlank']:
    check('ST-18', 'IMP-01 con CHECK %s' % cname, cname in constraints)

# ---------------------------------------------------------------- SQL: seed an toan voi IMP-09
seed = SQL['02_seed.sql']
guid = r"'([0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12})'"
pending_rows = []
for line in seed.splitlines():
    if "PENDING" not in line:
        continue
    ids = re.findall(guid, line)
    times = re.findall(r'@[A-Za-z0-9_]+', line)
    if len(ids) >= 3:
        # (BookingId, UserId, CourtId) theo thu tu xuat hien trong INSERT seed
        pending_rows.append((ids[1], ids[2], times[0] if times else ''))
keys = [r for r in pending_rows]
check('ST-19', 'Seed khong co 2 PENDING trung (UserId, CourtId, StartTime) -> khong vo IMP-09',
      len(keys) == len(set(keys)), '%d dong PENDING doc duoc' % len(keys))

# ---------------------------------------------------------------- Ma loi SQL <-> app
thrown = set()
for fname in ['06_procedures.sql', '07_triggers.sql']:
    thrown |= {int(n) for n in re.findall(r'THROW\s+(\d{5})', SQL[fname])}

sp_error_ts = app_file('src/shared/spError.ts')
mapped = {int(n) for n in re.findall(r'^\s*(\d{4,6}):', sp_error_ts, re.MULTILINE)}

unmapped = sorted(c for c in thrown if c not in mapped)
check('ST-20', 'Moi ma loi 5xxxx SQL nem ra deu co thong bao tieng Viet trong app',
      not unmapped, 'chua anh xa: %s' % (unmapped or 'khong co'))

ghost = sorted(c for c in mapped if 50000 <= c < 60000 and c not in thrown)
check('ST-21', 'App khong anh xa ma loi 5xxxx khong ton tai trong SQL', not ghost, 'du thua: %s' % (ghost or 'khong co'))

for code in (1205, 1222, 2601):
    check('ST-22', 'App co thong bao cho ma he thong %d' % code, code in mapped)

# ---------------------------------------------------------------- App: retry + status
bookings = app_file('src/server/routes/bookings.ts')
manager = app_file('src/server/routes/manager.ts')

check('ST-23', 'bookings.ts import withTransientRetry', 'withTransientRetry' in bookings)
check('ST-24', 'manager.ts import withTransientRetry', 'withTransientRetry' in manager)
check('ST-25', 'sp_BookCourt duoc bao boi retry',
      bool(re.search(r'withTransientRetry\((?:.|\n){0,2000}?sp_BookCourt', bookings)))
check('ST-26', 'sp_CancelBooking (khach huy) duoc bao boi retry',
      bool(re.search(r'withTransientRetry\((?:.|\n){0,2000}?sp_CancelBooking', bookings)))
check('ST-27', '4 SP cua quan ly duoc bao boi retry',
      bool(re.search(r'withTransientRetry\((?:.|\n){0,2000}?SP\[action\]', manager)))

def maps_status(text: str, code: int, status: int) -> int:
    """Dem so ham anh xa `mapped.code === <code>` -> `return <status>`."""
    return len(re.findall(r'code\s*===\s*%d\D{0,60}?return\s+%d' % (code, status), text))


check('ST-28', 'bookings.ts tra 503 cho ma 1222 o ca 3 ham status',
      maps_status(bookings, 1222, 503) == 3, '%d/3 ham' % maps_status(bookings, 1222, 503))
check('ST-29', 'manager.ts tra 503 cho ma 1222', maps_status(manager, 1222, 503) >= 1)
check('ST-30', 'bookings.ts tra 409 cho ma 2601 (trung PENDING)', maps_status(bookings, 2601, 409) >= 1)
check('ST-31', 'bookings.ts giu 409 cho deadlock 1205', maps_status(bookings, 1205, 409) >= 1)

# ---------------------------------------------------------------- App: config / env / thu tu middleware
config_ts = app_file('src/server/config.ts')
env_example = app_file('.env.example')
for var, key in [('DB_LOCK_TIMEOUT_MS', 'dbLockTimeoutMs'),
                 ('MAX_SESSION_CONNECTIONS', 'maxSessionConnections'),
                 ('LOGIN_RATE_LIMIT_PER_MINUTE', 'loginRateLimitPerMinute')]:
    check('ST-32', 'Bien %s co trong .env.example' % var, var in env_example)
    check('ST-33', 'config.ts doc %s -> %s' % (var, key), var in config_ts and key in config_ts)

app_ts = app_file('src/server/app.ts')
pos_limiter = app_ts.find("'/api/auth/login'")
pos_auth = app_ts.find("app.use('/api/auth',")
check('ST-34', 'Rate limiter dang truoc router /api/auth (neu sau thi vo dung)',
      pos_limiter != -1 and pos_auth != -1 and pos_limiter < pos_auth)

session_db = app_file('src/server/db/sessionDb.ts')
check('ST-35', 'sessionDb dat SET LOCK_TIMEOUT o tang app', 'SET LOCK_TIMEOUT' in session_db)
check('ST-36', 'sessionDb co tran so phien (TooManySessionsError)', 'TooManySessionsError' in session_db)
check('ST-37', 'auth.ts tra 503 khi qua tran so phien',
      'TooManySessionsError' in app_file('src/server/routes/auth.ts'))

# ---------------------------------------------------------------- IMP-13 / IMP-15 / production regression
package_json = app_file('package.json')
check('ST-39', 'package co build:server phat sinh JavaScript server',
      '"build:server": "tsc -p tsconfig.server.json"' in package_json)
check('ST-40', 'build goi build:server truoc Vite',
      bool(re.search(r'"build"\s*:\s*"npm run build:server.*?vite build"', package_json)))
check('ST-41', 'typecheck server van dung --noEmit',
      bool(re.search(r'"typecheck"\s*:\s*"tsc -p tsconfig.server.json --noEmit', package_json)))
check('ST-42', 'npm test bao gom 12 ca sessionExpiry',
      '"test"' in package_json and 'sessionExpiry.test.ts' in package_json)

for var, key in [('SESSION_TTL_MS', 'sessionTtlMs'),
                 ('SESSION_IDLE_TIMEOUT_MS', 'sessionIdleTimeoutMs'),
                 ('SESSION_SWEEP_INTERVAL_MS', 'sessionSweepIntervalMs')]:
    check('ST-43', 'IMP-13 bien %s co trong .env.example' % var, var in env_example)
    check('ST-44', 'IMP-13 config %s -> %s' % (var, key), var in config_ts and key in config_ts)

session_middleware = app_file('src/server/middleware/session.ts')
session_expiry = app_file('src/server/db/sessionExpiry.ts')
server_index = app_file('src/server/index.ts')
check('ST-45', 'Cookie va SQL session dung chung sessionTtlMs', 'maxAge: cfg.sessionTtlMs' in session_middleware)
check('ST-46', 'sessionExpiry.ts la logic thuan, khong import mssql',
      "from 'mssql'" not in session_expiry and 'from "mssql"' not in session_expiry)
check('ST-47', 'SessionDb luu createdAt', 'createdAt' in session_db)
check('ST-48', 'SessionDb luu/cap nhat lastUsedAt', 'lastUsedAt' in session_db and 'touchSession' in session_db)
check('ST-49', 'SessionDb co sweepExpiredSessions', 'sweepExpiredSessions' in session_db)
check('ST-50', 'SessionDb co startReaper idempotent', 'startReaper' in session_db and 'if (this.reaper) return' in session_db)
check('ST-51', 'SessionDb co stopReaper', 'stopReaper' in session_db and 'clearInterval' in session_db)
check('ST-52', 'index.ts bat reaper khi khoi dong', 'sessionDb.startReaper()' in server_index)
check('ST-53', 'SessionDb dung policy thuan de quyet dinh expiry',
      all(token in session_db for token in ['expiredSessionIds', 'isSessionExpired', 'touchSession']))

all_bookings_view = SQL['05_views.sql']
check('ST-54', 'vw_AllBookings tu scope context va mien tru sysadmin/dbo',
      all(token in all_bookings_view for token in ["SESSION_CONTEXT(N'Role')", "SESSION_CONTEXT(N'UserId')",
                                                   "IS_SRVROLEMEMBER(N'sysadmin')", "USER_NAME() = N'dbo'"]))

available_proc = proc_blocks.get('sp_GetAvailableCourts', '')
available_codes = [50120, 50121, 50122, 50123, 50124, 50125, 50126]
check('ST-55', 'IMP-15 co du 7 ma loi 50120-50126',
      all(('THROW %d' % code) in available_proc for code in available_codes))
positions = [available_proc.find('THROW %d' % code) for code in available_codes]
check('ST-56', 'IMP-15 guard dung thu tu app', all(pos >= 0 for pos in positions) and positions == sorted(positions))
courts_route = app_file('src/server/routes/courts.ts')
check('ST-57', 'Route available tra 400 cho 50120-50126',
      all(str(code) in courts_route for code in available_codes) and 'return 400' in courts_route)
check('ST-58', 'spError.ts map du 50120-50126', all(code in mapped for code in available_codes))
check('ST-59', 'Duration ngoai 60-180 cung nem 50124',
      bool(re.search(r'@Minutes\s*<\s*60\s+OR\s+@Minutes\s*>\s*180\s+THROW\s+50124', available_proc, re.I)))
regression = read(os.path.join(ROOT, 'tests', 'regression', 'imp_regression.sql'))
check('ST-60', 'Regression co du RG-45 den RG-55',
      all(('RG-%d' % n) in regression for n in range(45, 56)))

# ---------------------------------------------------------------- Tuy chon: parse T-SQL bang sqlglot
parse_note = 'bo qua (khong co sqlglot)'
parse_ok = True
try:
    import sqlglot  # type: ignore
    from sqlglot.errors import ParseError  # type: ignore

    bad: list[str] = []
    total = 0
    for fname, text in SQL.items():
        batches = re.split(r'(?im)^\s*GO\s*$', text)
        for i, batch in enumerate(batches):
            if not batch.strip():
                continue
            total += 1
            try:
                sqlglot.parse(batch, dialect='tsql')
            except ParseError as exc:
                bad.append('%s#batch%d: %s' % (fname, i + 1, str(exc).splitlines()[0][:90]))
            except Exception:  # sqlglot con thieu mot so cu phap T-SQL
                pass
    parse_note = '%d/%d batch parse duoc' % (total - len(bad), total)
    if bad:
        parse_note += ' | can xem tay: ' + ' ; '.join(bad[:6])
except ImportError:
    pass
check('ST-38', 'Parse T-SQL (sqlglot, chi tham khao)', parse_ok, parse_note)

# ---------------------------------------------------------------- In ket qua
failed = [r for r in results if not r[2]]
print('=' * 78)
print('KIEM TRA TINH — %d muc' % len(results))
print('=' * 78)
for tid, name, ok, note in results:
    print('%-6s %-4s %s%s' % (tid, 'PASS' if ok else 'FAIL', name, (' [%s]' % note) if note else ''))
print('-' * 78)
print('PASS: %d | FAIL: %d' % (len(results) - len(failed), len(failed)))
sys.exit(1 if failed else 0)
