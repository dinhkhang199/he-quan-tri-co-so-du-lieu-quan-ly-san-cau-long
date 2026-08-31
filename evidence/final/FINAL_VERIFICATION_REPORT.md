# Final verification report

- Date: 2026-08-31 (Asia/Bangkok)
- Start main: `c6ca8899f305db39751b25d824048d875d0bad01`
- Start course-final: `e18cadfbc75267210b65ee051b72034ad837a710`
- SQL Server: local `MSI\SQLEXPRESS` / SQL Server 2022 Express
- Node: v24.14.1; npm: 11.11.0
- Runtime evidence used disposable `BadmintonCourtManagement_FinalTest`, with schema/logic copied from source and only database identifiers changed. The working `BadmintonCourtManagement` database was not altered.

## App

| Gate | Status | Evidence |
|---|---|---|
| typecheck / lint / 8 unit tests / build | PASS | final command output; `dist/server/index.js` verified |
| production `npm start` health | PASS | `app_health.json`, `app_server_stdout.txt` |
| production SPA fallback | PASS | `/manager/bookings` HTTP 200 returned Vite root |
| API smoke | PASS | `api_smoke.json`: wrong=401, inactive=403, guest=5 courts, unauth booking=401, create=201/PENDING, history=true, manager approve=200, dashboard=true |

## Database

| Gate | Status | Evidence |
|---|---|---|
| clean 00→08 | PASS | `db_00_create_database.txt` … `db_08_security.txt` |
| object contract 5/4/2/14/6 | PASS | `object_contract.txt` |
| functional 09 | PASS (47/47, 0 FAIL) | `db_09_tests_functional.txt` |
| transaction/rollback 10 + functional rollback assertions | PASS | `db_10_tests_transactions.txt`, `db_09_tests_functional.txt` |
| concurrent approve 11/12 | PASS (`BookedCount <= 1`) | `cc_session_a.txt`, `cc_session_b.txt` |
| deadlock 13/14 | PASS; actual victim 1205; fixed ordering completed | `deadlock_A.txt`, `deadlock_B.txt` |
| audit actor | PASS | `audit_actor.txt` |
| backup / VERIFYONLY / restore | PASS; restored booking count matched | `backup_restore.txt` |

## Isolation anomalies (two real sqlcmd sessions each)

| Case | UNSAFE | FIXED | Evidence |
|---|---|---|---|
| Lost Update | PASS: final 150000, B update lost | PASS: final 170000 | `lost_update_A.txt`, `lost_update_B.txt` |
| Dirty Read | PASS: B read uncommitted 200000, A rolled back | PASS: B read committed 100000 | `dirty_read_A.txt`, `dirty_read_B.txt` |
| Non-repeatable Read | PASS: A read 100000 then 120000 | PASS: both reads 100000 | `nonrepeatable_A.txt`, `nonrepeatable_B.txt` |
| Phantom Read | PASS: count 0 then 1 | PASS: SERIALIZABLE count 0 then 0 | `phantom_A.txt`, `phantom_B.txt` |

## UI-01 → UI-07

- UI-01 PASS by API runtime (wrong/inactive/valid login).
- UI-02 PASS by API runtime (guest search; unauthenticated booking rejected).
- UI-03 PASS by API + DB runtime (PENDING creation and history reconciliation).
- UI-04 PASS by API runtime (manager approve reflected by DB).
- UI-05 PASS by functional security assertions; visual browser NOT AUTOMATED.
- UI-06 PASS by actual DB 1205 + HTTP mapping unit test; browser visual retry control STATIC verified.
- UI-07 PASS by dashboard API runtime and stored-procedure-backed response.

## Security and dependencies

- SQL login test used a separate test-only principal; no real password or session secret is recorded here.
- Scope-creep search contains none of the prohibited registration/reset/SMTP production files.
- `npm audit --omit=dev`: 2 moderate React Router advisories; available fix requires breaking v7 upgrade. No production high/critical vulnerability. Full audit reports 3 moderate + 1 high (the high is development tooling).
