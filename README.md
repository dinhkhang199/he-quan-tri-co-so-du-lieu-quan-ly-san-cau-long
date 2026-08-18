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
| 14 | `13_deadlock_demo_session_A.sql` | DL-01 deadlock + DL-02 lock-order fix + DL-03 regression (Window A) |
| 15 | `14_deadlock_demo_session_B.sql` | DL-01/DL-02/DL-03 (Window B) |
| 16 | `15_backup_restore_demo.sql` | Backup → VERIFYONLY → restore DB kiểm thử → so sánh (RC-01) |

> Lưu ý thứ tự đã ĐƯỢC KHÓA theo contract (00→15). Không đảo `02_seed`
> sau trigger vì contract cố định thứ tự; dữ liệu audit/notification demo
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

## Bảo mật phiên làm việc (Session / register)

Mọi SP nghiệp vụ (đặt sân, duyệt, từ chối, hủy, hoàn thành, dashboard,
thông báo…) **bắt buộc** phiên đăng nhập qua `sp_Login` trước (Option A):

- `sp_Login` thiết lập `SESSION_CONTEXT('UserId')` / `('Role')`.
- Nếu SESSION_CONTEXT rỗng → SP **THROW** (không fallback xuống `@UserId` tùy ý).
- `GetMyBookings` / `GetNotifications` dùng **chỉ** actor từ SESSION_CONTEXT;
  truyền `@UserId` khác actor → THROW 51054/51060.
- Test âm tính: SP-11..SP-21 (không phiên + impersonation từng quyền).
- **Ngoại lệ công khai (Guest)**: duyệt sân rảnh **không** yêu cầu đăng nhập —
  truy cập public qua `sp_GetAvailableCourts` và view `vw_AvailableCourts`.
  Mọi SP nghiệp vụ có ghi dữ liệu/đổi trạng thái vẫn bắt buộc
  `sp_Login` + actor từ SESSION_CONTEXT.

## Lock ordering (deadlock + lost update)

Các SP chuyển trạng thái booking dùng **MỘT thứ tự khóa** Court → Booking:

- `sp_ApproveBooking` / `sp_BookCourt`: khóa `Courts` (UPDLOCK+HOLDLOCK) trước.
- `sp_RejectBooking` / `sp_CancelBooking` / `sp_CompleteBooking`: đọc CourtId làm
  **locator** (chưa giữ khóa), khóa `Courts` trước, rồi đọc lại booking dưới khóa
  (anti-TOCTOU), kiểm tra lại CourtId/ownership/status/thời gian dưới khóa.
- Hai session approve/cancel cùng booking sẽ **block tuần tự**, không xoay vòng
  chờ khóa chéo → không deadlock (DL-03 regression).

## Test concurrency/phantom/deadlock (cần 2 cửa sổ SSMS)

Thứ tự chạy chuẩn cho bản Phase 1:

1. **Build sạch** theo thứ tự khóa: 00 → 01 → 02 → 03 → 04 → 05 → 06 → 07 → 08.
2. **09** (phiên đơn) — toàn PASS (47/47; gồm SEC-01..05 chống giả mạo
   SESSION_CONTEXT).
3. **10** phantom (Window A).
4. **11** (A) + **12** (B) concurrency — cùng lúc (cách ≤ 60s).
5. **13** (A) + **14** (B) deadlock — cùng lúc (cách ≤ 2s).
6. **15** backup/restore RC-01.

> Các demo cô lập giao dịch (lost update / dirty read / non-repeatable /
> phantom dạng cờ) và **TOCTOU regression** nằm ở `tests/concurrency/`
> (xem `tests/concurrency/README.md`) — chúng là demo/bằng chứng, **không thuộc**
> canonical build 00→15 và không làm thay đổi object set sản xuất.
> Chạy giữa bước 5 và 6 để có bằng chứng đầy đủ; C1 phải ACTIVE trước TOCTOU.

- **Phantom (10)**: chạy ở cửa sổ A; khi A in “ĐANG CHỜ 8 giây”, chạy câu
  `INSERT` (in trong script) ở cửa sổ B. Đọc lại sẽ thấy phantom
  (READ COMMITTED); phần SERIALIZABLE thì INSERT của B bị range-lock chặn tới
  khi A kết thúc → không phantom. Kết thúc bằng `ROLLBACK` ở cả hai cửa sổ.
- **Concurrency (11/12)**: chạy 11 ở A rồi 12 ở B (trong vòng ~60 giây).
  Hai script tự đồng bộ bằng cờ trong bảng tạm `_CCTestSync`:
  - `CC-01`: A approve `b4`, B approve `b9` (2 PENDING overlap cùng sân C1) →
    đua nhau, nhiều nhất **1 BOOKED** (assertion ≤ 1 ở cả A và B).
  - `CC-02`: A giữ khóa C5 (giá 150000), B UPDATE lên 120000 bị **block** tới
    khi A COMMIT → giá cuối 120000, không lost update (assertion ở A).
  - Không cần canh giờ chính xác; nếu thiếu cửa sổ kia, script in FAIL rõ ràng.
- **Deadlock (13/14)**: chạy cùng lúc (≤ 2 giây). 1 cửa sổ in “VICTIM: bị
  deadlock (1205)” ở `DL-01` (kịch bản lỗi — thứ tự khóa chéo). Sau đó **cả 2**
  tự chạy tiếp `DL-02` (cùng lock order → không deadlock) và `DL-03`
  (regression Approve vs Cancel bằng SP thật, cùng booking, sân C3 →
  không 1205; assertion PASS ở cuối).

## RC-01 (khôi phục dữ liệu)

`15_backup_restore_demo.sql`:

- BACKUP → RESTORE VERIFYONLY → restore sang db riêng
  `BadmintonCourtManagement_Verify`.
- **Hard-fail bằng THROW** khi: không xác định được thư mục backup/data
  (`52020`), lệch số lượng Users/Courts/Bookings (`52021`), lệch chi tiết
  booking (`52022`). Exit code 0 = RC-01 PASS thực sự.

## Definition of Done (trích contract)
- [x] DB tạo sạch từ SQL Server (00→08 không lỗi) — xem
  `evidence/final_00.txt` … `evidence/final_08.txt`.
- [x] 5 bảng lõi + PK/FK/UNIQUE/CHECK/INDEX đúng contract.
- [x] 4 Views, 2 Functions, 14 SP, 6 Triggers.
- [x] `09_tests_functional.sql` toàn PASS (47/47) — gồm test âm tính
  SESSION_CONTEXT (Option A) SP-11..SP-21 và SEC-01..05 chống giả mạo
  SESSION_CONTEXT. Xem `evidence/final_09.txt` + `evidence/PHASE1_TEST_REPORT.md`.
- [x] CC-01/CC-02, PH-01/PH-02, DL-01/DL-02/DL-03, lost update / dirty read /
  non-repeatable read / phantom / TOCTOU có bằng chứng 2 session
  (`evidence/final_*.txt`).
- [x] RC-01 backup/restore khớp dữ liệu lõi (THROW khi lệch) —
  `evidence/final_15.txt`.
- [ ] UI gọi DB đúng contract (app/ - làm ở giai đoạn sau).
- [x] Không còn cú pháp MySQL/PostgreSQL/Supabase.

## Cấu trúc
```
BadmintonCourtManagement/
├─ database/      ← canonical build 00..15 (phần bắt buộc, không có 16/17)
├─ app/           ← (trống - làm sau: login, đặt sân, dashboard…)
├─ tests/concurrency/  ← demo cô lập giao dịch + TOCTOU regression
│                      (Lost Update, Dirty Read, Non-repeatable Read, Phantom Read,
│                       TOCTOU) — ngoài canonical build; xem tests/concurrency/README.md
├─ evidence/      ← bằng chứng chạy test (final_* + PHASE1_TEST_REPORT.md)
└─ README.md
```

## Ghi chú quan trọng
- Mọi SP nghiệp vụ có: validation quyền + state + input + transaction
  `SET XACT_ABORT ON + BEGIN TRAN + COMMIT/ROLLBACK + THROW`.
- App được cấm INSERT/UPDATE/DELETE trực tiếp bảng lõi (`08_security`);
  chỉ đi qua SP (SP dùng `WITH EXECUTE AS OWNER`). SP luôn kiểm tra
  `SESSION_CONTEXT` (Option A) - không dùng `@UserId` tùy ý khi chưa đăng nhập.
- Booking vượt giờ hoạt động / quá 3h / quá khứ / sai 30 phút bị chặn ở `sp_BookCourt`.
- Overlap đúng contract: `[Start, End)`, chỉ chạm biên là không overlap.
- Seed (`02_seed.sql`) KHÔNG dùng `DISABLE TRIGGER ALL`: chỉ tạm tắt
  (có điều kiện `IF OBJECT_ID ...`) đúng 2 trigger sinh side-effect
  (`trg_Bookings_AuditInsert`, `trg_Bookings_NotifyInsert`) và luôn bật lại
  trong mọi nhánh lỗi; trigger an toàn state/overlap vẫn hoạt động.