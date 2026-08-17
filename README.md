# BadmintonCourtManagement — Quản lý sân cầu lông

Triển khai theo **QuanLySanCauLong_IMPLEMENTATION_CONTRACT_v2.0** trên
**Microsoft SQL Server** + **T-SQL**. Chỉ phụ trách phần kỹ thuật
(Database + Test/Evidence). Không dùng cú pháp MySQL/PostgreSQL/Supabase.

## Yêu cầu môi trường
- SQL Server 2019 trở lên (script dùng `COMPATIBILITY_LEVEL = 150`).
- SSMS (SQL Server Management Studio) để chạy script.

## Cách chạy từ đầu (DB-01: Create DB từ rỗng)

Chạy tuần tự trong SSMS, đúng thứ tự:

| # | Script | Mục đích |
|---|--------|----------|
| 1 | `00_create_database.sql` | Tạo database `BadmintonCourtManagement` (xóa DB cũ nếu có) |
| 2 | `01_tables_constraints.sql` | 5 bảng lõi + PK/FK/UNIQUE/CHECK |
| 3 | `02_seed.sql` | Seed dữ liệu demo cố định, chạy lại được |
| 4 | `03_indexes.sql` | Index phục vụ overlap/dashboard |
| 5 | `04_functions.sql` | `fn_CalculateBookingCost`, `fn_IsCourtAvailable` |
| 6 | `05_views.sql` | `vw_AvailableCourts`, `vw_BookingHistory`, `vw_AdminDashboard`, `vw_AllBookings` |
| 7 | `06_procedures.sql` | 14 Stored Procedures (có `WITH EXECUTE AS OWNER`) |
| 8 | `07_triggers.sql` | 6 Triggers (set-based, multi-row) |
| 9 | `08_security.sql` | Role `bcm_app_role`, user `bcm_app`, DENY DML trực tiếp lên bảng lõi |
| 10 | `09_tests_functional.sql` | Test matrix phiên đơn (DB/FN/SP/TR/TX/INV) + summary |
| 11 | `10_tests_transactions.sql` | Phantom demo (2 cửa sổ SSMS) |
| 12 | `11_tests_concurrency_session_A.sql` | CC-01 approve cạnh tranh, CC-02 lock wait (Window A) |
| 13 | `12_tests_concurrency_session_B.sql` | CC-01/CC-02 (Window B) |
| 14 | `13_deadlock_demo_session_A.sql` | DL-01 deadlock + DL-02 lock-ordering fix (Window A) |
| 15 | `14_deadlock_demo_session_B.sql` | DL-01/DL-02 (Window B) |
| 16 | `15_backup_restore_demo.sql` | Backup → VERIFYONLY → restore DB kiểm thử → so sánh (RC-01) |

> Lưu ý thứ tự đã ĐƯỢC KHÓA theo contract (00→15). Không đảo `02_seed`
> sau trigger vì contract cố định thứ tự; dữ liệu audio/notification demo
> trong seed là dòng mẫu, còn mọi thao tác runtime đi qua trigger.

## Tài khoản seed (demo)
| Username | Password | Role |
|---|---|---|
| `manager` | `manager123` | MANAGER |
| `courtmanager1` | `cm1pass` | COURT_MANAGER |
| `courtmanager2` | `cm2pass` | COURT_MANAGER |
| `customer1` | `cus1pass` | CUSTOMER |
| `customer2` | `cus2pass` | CUSTOMER |
| `customer3` | `cus3pass` | CUSTOMER |
| `inactive_user` | `inactive1` | CUSTOMER (inactive) |

Hash: `SHA2_256(N'bcms|' + password)` — **không lưu plaintext**.

## Test concurrency/phantom/deadlock (cần 2 cửa sổ SSMS)
- **Phantom**: chạy `10_tests_transactions.sql` ở cửa sổ A; trong lúc A
  hiện "ĐANG CHỜ", chạy câu `INSERT` (có in trong script) ở cửa sổ B.
  READ COMMITTED → phantom (PH-01); SERIALIZABLE → insert B bị blocked
  (PH-02). Kết thúc bằng `ROLLBACK` ở cả hai cửa sổ.
- **Concurrency**: chạy script 11 (A) rồi script 12 (B) gần như cùng lúc;
  SSMS sẽ/hiện bảng "BookedCount_on_slot = 1" → PASS (CC-01).
  Phần CC-02 lock wait: A giữ khóa 8 giây, B phải chờ rồi ghi, không lost update.
- **Deadlock**: chạy script 13 (A) và 14 (B) cùng lúc → 1 cửa sổ nhận
  **error 1205** (DL-01). Với DL-02 (lock ordering Court→Booking) comment
  phần DL-01 ở cả 2 file, bỏ comment DL-02 → không còn deadlock.

## Definition of Done (trích contract)
- [ ] DB tạo sạch từ SQL Server (00→08 không lỗi).
- [x] 5 bảng lõi + PK/FK/UNIQUE/CHECK/INDEX đúng contract.
- [x] 4 Views, 2 Functions, 14 SP, 6 Triggers chạy đúng.
- [ ] `09_tests_functional.sql` cho toàn PASS (Test matrix DB/FN/SP/TR/TX/INV).
- [ ] CC-01/CC-02, PH-01/PH-02, DL-01/DL-02 có bằng chứng từ 2 session.
- [ ] RC-01 backup/restore khớp dữ liệu lõi.
- [ ] UI gọi DB đúng contract (app/ - làm ở giai đoạn sau).
- [ ] Không còn cú pháp MySQL/PostgreSQL/Supabase.

## Cấu trúc
```
BadmintonCourtManagement/
├─ database/      ← 00..15 + security (phần bắt buộc)
├─ app/           ← (trống - làm sau: login, đặt sân, dashboard…)
├─ tests/         ← (trống - test tự động app nếu có)
├─ evidence/      ← chỗ lưu screenshot/capture bằng chứng chạy test
└─ README.md
```

## Ghi chú quan trọng
- Mọi SP nghiệp vụ có: validation quyền + state + input + transaction
  `SET XACT_ABORT ON + BEGIN TRAN + COMMIT/ROLLBACK + THROW`.
- App được cấm INSERT/UPDATE/DELETE trực tiếp bảng lõi (`08_security`);
  chỉ đi qua SP (SP dùng `WITH EXECUTE AS OWNER`).
- Booking vượt giờ hoạt động / quá 3h / quá khứ / sai 30 phút bị chặn ở `sp_BookCourt`.
- Overlap đúng contract: `[Start, End)`, chỉ chạm biên là không overlap.