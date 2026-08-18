# PHASE1_TEST_REPORT

Final verification run — branch `phase1-db-hardening`, NOT committed (review gate).
All evidence = `evidence/final_*` captured from THIS run only. No stale `build*` referenced.

Instance: `.\SQLEXPRESS` (SQL Server 2022 Express), DB `BadmintonCourtManagement`.

## 1. Build sạch 00 → 08 — `evidence/final_00..08.txt`

All steps exit=0, no `Msg`/`LỖI`. Canonical build: 00 → 01 → 02 → 03 → 04 → 05
→ 06 → 07 → 08 (14 SP, 6 triggers). TOCTOU demo KHÔNG nằm trong canonical build
(thuộc `tests/concurrency/`).

Object counts after 08 (invariant):

| Object | Count |
|---|---|
| Tables | 5 |
| Views | 4 |
| Functions | 2 |
| Procedures | 14 |
| Triggers | 6 |

Seed: Users=7, Courts=6, Bookings=15, ActivityLogs=3, Notifications=2.

## 2. 09_tests_functional — `evidence/final_09.txt`

Result: **47 total / 47 passed / 0 failed** (exit=0) — gồm SEC-01..05:

| Test | Mục đích | Kết quả |
|---|---|---|
| SEC-01 | `bcm_app` tự gán SESSION_CONTEXT(UserId) → bị chặn | PASS (EXECUTE denied `sp_set_session_context`) |
| SEC-02 | `bcm_app` tự gán SESSION_CONTEXT(Role) → bị chặn | PASS (EXECUTE denied) |
| SEC-03 | `sp_Login` (bcm_app) tạo context MANAGER hợp lệ | PASS (UserId+Role đúng, ENFORCED) |
| SEC-04 | Giả mạo manager rồi approve → bị chặn | PASS (không set được context → approve không chạy) |
| SEC-05 | Guest browse `sp_GetAvailableCourts` public (no session) | PASS (5 sân trống) |

P0 SESSION_CONTEXT security = **Option A**: `DENY EXECUTE ON sys.sp_set_session_context`
ở master scope cho login `bcm_app` (đã xác minh trên instance qua
`sys.database_permissions` — state `DENY`, live chạy dưới `EXECUTE AS USER
bcm_app`); chỉ `sp_Login` (trusted execution context) tạo được context.
SP-11..SP-21 (không phiên/impersonation/cross-user/forged @SessionUserId) cũng PASS.

## 3. Phantom — 10_tests_transactions (canonical/manual) vs evidence

`database/10_tests_transactions.sql` được giữ làm script canonical/theo dõi tay
(2 cửa sổ SSMS). **Lưu ý**: `evidence/final_10.txt` của lần chạy này KHÔNG quan
sát được phantom ở READ COMMITTED — script in `first count = 0, second count = 0,
"Chưa thấy phantom"`.

**Bằng chứng PH-01/PH-02 có giá trị của lần chạy này** là
`evidence/final_phantom_A.txt` + `evidence/final_phantom_B.txt`
(demo 2 session có cờ đồng bộ `_PhTestSync`, thuộc `tests/concurrency/`):

- **UNSAFE READ COMMITTED (PH-01 failed)**: COUNT **0 → 1** sau khi Session B
  INSERT + COMMIT → phantom hiện rõ.
- **FIXED SERIALIZABLE (PH-02 PASS)**: **f1 = f2 = 0**; INSERT của B bị
  range-lock chặn tới khi A kết thúc → không phantom.

## 4. Isolation anomalies (2 session, cờ đồng bộ) — `evidence/final_*`

| Demo | Files | UNSAFE | FIXED |
|---|---|---|---|
| Lost Update | `final_lostupdate_A/B.txt` | stale 100.000 → ghi đè 150.000 (mất +20.000) | UPDLOCK nối tiếp → **170.000** "ASSERTION PASS" |
| Dirty Read | `final_dirtyread_A/B.txt` | A 200.000 chưa commit; B READ UNCOMMITTED đọc **200000**; A rollback | READ COMMITTED → B bị block, đọc **100000** committed |
| Non-repeatable | `final_nonrepeat_A/B.txt` | A đọc 100000 → 120000 | REPEATABLE READ: 2 lần đọc đều 100000 |
| Phantom | `final_phantom_A/B.txt` | COUNT 0 → 1 (thêm row sau commit B) | SERIALIZABLE: f1=f2=0, B bị block |

## 5. CC-01 / CC-02 — `evidence/final_11.txt`, `final_12.txt`

- CC-01: approve cạnh tranh b4/b9 overlap sân C1 → nhiều nhất 1 BOOKED
  (`ASSERTION PASS: BookedCount_on_slot <= 1`; Window B: tối đa 1 BOOKED).
- CC-02: A giữ khóa C5, B UPDATE bị block → final 120.000
  (`ASSERTION PASS: giá cuối = 120000`).

## 6. DL-01 / DL-02 / DL-03 — `evidence/final_13.txt`, `final_14.txt`

- DL-01 (khóa chéo, cố ý): **deadlock 1205, victim = A** lần chạy này (B commit
  bình thường); cả 2 bọc TRY/CATCH nên tiếp tục.
- DL-02 (lock order Court→Booking nhất quán): cả A và B commit, **không deadlock**.
- DL-03 (REGRESSION SP thật, cùng booking PENDING sân C3): A `sp_ApproveBooking`
  BOOKED (giữ khóa), B `sp_CancelBooking` bị BLOCK rồi CANCELLED sau khi A nhả
  khóa → `Trạng thái cuối: CANCELLED`, **ASSERTION PASS cả 2 window**.
- `_DLTestSync` làm đồng bộ DL-03 định hình (bỏ race). 1205 chỉ xuất hiện là
  victim DL-01.

## 7. TOCTOU regression — `evidence/final_toctou_A.txt`, `final_toctou_B.txt`

`tests/concurrency/toctou_booking_vs_deactivate_session_A/B.sql` (đã di chuyển
từ `database/16,17`, KHÔNG thuộc canonical build 00→15).

- B (MANAGER) giữ UPDLOCK sân C1 rồi deactivate + commit trong lúc A
  (CUSTOMER) đang chạy `sp_BookCourt`.
- `sp_BookCourt` đọc LẠI IsActive dưới khóa (UPDLOCK+ROWLOCK+HOLDLOCK) → THROW
  **50013** (sân inactive), **KHÔNG tạo PENDING** trên C1.
- `ASSERTION PASS: court inactive (IsActive=0) và KHÔNG có PENDING mới ... -
  không TOCTOU`.

## 8. RC-01 backup/restore — `evidence/final_15.txt`

BACKUP → RESTORE VERIFYONLY → restore sang `BadmintonCourtManagement_Verify`
DB riêng → so sánh: Users **7=7**, Courts **6=6**, Bookings **15=15**, chi tiết
Bookings khớp 100%. Exit=0. Sau RC-01, DB `_Verify` được dọn (còn lại duy nhất
`BadmintonCourtManagement`).

## 9. Cleanup / residue cuối (deterministic)

Trước RC-01 đã dọn: sentinel DL-03 (`B0000000-...-D030...0001`) theo thứ tự FK
(Notifications → ActivityLogs → Bookings), drop 6 bảng cờ test (`_LUTestSync`,
`_DRTestSync`, `_NRTestSync`, `_PhTestSync`, `_TOCTouSync`, `_DLTestSync`),
reactivate C1.

Kết quả residue (đã xác minh bằng query):

| Item | Giá trị |
|---|---|
| Users | 7 |
| Courts | 6 |
| Bookings | 15 |
| Sync/helper tables | 0 |
| C1 IsActive | 1 |
| C5 PricePerHour | 100000 |

## 10. Kiểm tra cuối

- Toàn bộ `evidence/final_*`: không có `Msg 20x/15x/30x`, `ASSERTION FAIL`,
  `Timeout chờ`, `FAIL:`; `1205` chỉ là victim của DL-01.
- Object set invariants thoả: Tables=5, Views=4, Fn=2, Procedures=14, Triggers=6.
- Nguồn: TOCTOU regression nằm ở `tests/concurrency/`, canonical build giữ 00→15.