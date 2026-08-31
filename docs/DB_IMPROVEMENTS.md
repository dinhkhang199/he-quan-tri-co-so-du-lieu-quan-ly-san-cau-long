# Cải tiến Database & chống quá tải

Thư mục này ghi lại **mọi thay đổi sau bản bàn giao đầu tiên**, lý do, và tác
động tới contract `QuanLySanCauLong_IMPLEMENTATION_CONTRACT_v2.0`.

Nguyên tắc chung khi sửa:

- Không đụng vào **số lượng đối tượng** mà contract chốt: 5 bảng / 4 view /
  2 function / 14 stored procedure / 6 trigger.
- Không đổi quy tắc nghiệp vụ (06:00–22:00, 1–3 giờ, bước 30 phút, công thức
  giá, điều kiện trùng giờ, sơ đồ trạng thái).
- Chỉ thêm CHECK / INDEX / UNIQUE — đúng phạm vi contract §5.2 cho phép.
- Không phá các demo trong `tests/concurrency` (chúng cần phiên B **chặn thật**).

---

## 1. Sửa lỗi thật

### FIX-NULLROLE — `database/06_procedures.sql`

**Lỗi:** 6 stored procedure kiểm tra quyền bằng

```sql
SELECT @Role = Role FROM dbo.Users WHERE UserId = @SessionUserId AND IsActive = 1;
IF @Role <> N'MANAGER' THROW ...
```

Trong SQL Server, `NULL <> N'MANAGER'` cho ra `UNKNOWN`, không phải `TRUE`.
Nên nếu `@SessionUserId` không tồn tại hoặc đã bị `IsActive = 0` thì `@Role`
bằng `NULL` và câu `IF` **không THROW** → đi qua cả chốt quyền.

**Sửa:** thêm chốt `NULL` tường minh vào `sp_RejectBooking`,
`sp_CompleteBooking`, `sp_CreateCourt`, `sp_UpdateCourt`, `sp_DeactivateCourt`,
`sp_GetDashboard`:

```sql
IF @Role IS NULL
    THROW 500xx, N'Người dùng không tồn tại hoặc đã bị vô hiệu hóa.', 1;
```

Dùng đúng mã lỗi đã có của từng SP (50040 / 50060 / 50070 / 50080 / 50090 /
50110) — không phát sinh mã lỗi mới. Tổng cộng file có 9 chỗ
`IF @Role IS NULL`.

---

## 2. Cải tiến toàn vẹn dữ liệu (IMP-01, IMP-02) — `01_tables_constraints.sql`

Trước đây các quy tắc giờ/giá chỉ được kiểm tra trong stored procedure. Nếu ai
đó ghi trực tiếp vào bảng (ví dụ bằng quyền `sysadmin` khi sửa tay), dữ liệu
rác vẫn vào được. Các CHECK sau đưa luật xuống tầng bảng:

| Constraint | Ý nghĩa |
| --- | --- |
| `CK_Bookings_Duration_60_180` | 60 ≤ thời lượng ≤ 180 phút |
| `CK_Bookings_Slot30` | Giờ bắt đầu/kết thúc rơi đúng bước 30 phút |
| `CK_Bookings_OperatingHours` | Nằm trong 06:00–22:00 |
| `CK_Bookings_SameDay` | Không vắt qua nửa đêm |
| `CK_Bookings_TotalCost_GE0` | Tiền không âm |
| `CK_Users_Username_NotBlank`, `CK_Users_PhoneNumber_Digits` | Chất lượng dữ liệu người dùng |
| `CK_Courts_CourtName_NotBlank`, `CK_Courts_Address_NotBlank` | Chất lượng dữ liệu sân |
| `CK_Notifications_Message_NotBlank` | Thông báo rỗng là vô nghĩa |

> Vi phạm CHECK sinh lỗi SQL **547**, đã có sẵn trong bản đồ lỗi của app.

**Cố tình KHÔNG thêm:** CHECK `PricePerThreeHours <= PricePerHour * 3`. Đó là
chính sách giá (có thể đắt hơn theo mùa), không phải ràng buộc toàn vẹn.

---

## 3. IMP-03 — Index cho các truy vấn nóng (`03_indexes.sql`)

| Index | Phục vụ |
| --- | --- |
| `IX_Bookings_Booked_Court_Time` (filtered `Status = N'BOOKED'`) | Kiểm tra trùng giờ trong `sp_BookCourt` / `sp_ApproveBooking` / `fn_IsCourtAvailable` |
| `IX_Bookings_Pending_Court_Time` (filtered `Status = N'PENDING'`) | Hàng chờ duyệt của chủ sân |
| `IX_Bookings_User_Start` | `sp_GetMyBookings` |
| `IX_Bookings_Start_Status` | Dashboard theo ngày/trạng thái |
| `IX_Notifications_Unread` (filtered `IsRead = 0`) | Badge thông báo |

**Đánh đổi phải nói rõ:** mỗi index làm `INSERT`/`UPDATE` tốn thêm công ghi, và
phần ghi đó nằm **trong** giao dịch đang giữ khoá hàng `dbo.Courts`. Ở quy mô
đồ án, lợi ích đọc lớn hơn rất nhiều chi phí ghi; ở quy mô hàng nghìn người
thì phải đo lại bằng `sys.dm_db_index_usage_stats` rồi cắt index không dùng.

Tất cả đều bọc trong `IF NOT EXISTS (SELECT 1 FROM sys.indexes ...)` nên chạy
lại script nhiều lần không lỗi.

---

## 4. IMP-04 → IMP-08 (các chỉnh nhỏ)

| Mã | File | Nội dung |
| --- | --- | --- |
| IMP-04 | `06_procedures.sql` | `sp_GetAvailableCourts` không gọi `fn_IsCourtAvailable` hai lần cho mỗi hàng nữa; cột kết quả thành `CAST(1 AS BIT) AS IsAvailable`, WHERE vẫn lọc bằng hàm → giảm một nửa số lần gọi scalar UDF |
| IMP-05 | `04_functions.sql` | Làm tròn tiền phần lẻ một lần ở cuối cùng, tránh sai số đồng thịnh khi cộng dần |
| IMP-06 | `02_seed.sql` | 2 thông báo mẫu trước đây trỏ sai người; nay gắn đúng chủ booking |
| IMP-07 | `09_tests_functional.sql` | Test SP-07 tự căn giờ về bước 30 phút và kụp trong 06:00–22:00 (trước đây chạy sớm/muộn sẽ fail oan) |
| IMP-08 | `10_tests_transactions.sql` | Demo phantom: tăng cửa số chờ 8s → 20s, và **RAISERROR nếu không thấy phantom** thay vì chỉ in "chưa thấy" — test không được phép im lặng pass |

---

## 5. Chống quá tải (sau bài thử 2000 người đặt sân cùng lúc)

Bối cảnh và số liệu dự đoán: `docs/LOAD_TEST_2000.md`.
Bộ công cụ đo thật: `tests/load/` + `app/scripts/loadtest_*.mjs`.

Kết luận quan trọng nhất: **tính đúng đắn không hề bị phá** — `sp_BookCourt`
và `sp_ApproveBooking` đều khoá hàng `dbo.Courts` bằng
`WITH (UPDLOCK, ROWLOCK, HOLDLOCK)` rồi mới kiểm tra trùng giờ, nên không bao
giờ có hai BOOKED trùng nhau. Các cải tiến dưới đây chỉ xử lý **trải nghiệm
khi tắc** và **sức chịu tải**, không phải sửa lỗi logic.

### IMP-09 — Chặn spam PENDING bằng UNIQUE filtered index

`03_indexes.sql`:

```sql
CREATE UNIQUE INDEX UQ_Bookings_OnePendingPerUserSlot
    ON dbo.Bookings (UserId, CourtId, StartTime)
    WHERE Status = N'PENDING';
```

- Contract cho phép nhiều PENDING chồng giờ (chỉ BOOKED mới độc quyền), nên
  **hai khách khác nhau vẫn đặt cùng khung giờ** → demo CC-01 (hai PENDING
  tranh nhau khi duyệt) và dữ liệu seed **không đổi**.
- Điểm bị chặn: **cùng một khách** bấm đặt 50 lần cùng sân — cùng giờ.
- Đã đối chiếu seed: 15 booking mẫu, hai bản ghi PENDING chồng giờ trên sân 1
là của **hai UserId khác nhau** → tạo index không thất bại.
- Vi phạm sinh lỗi SQL **2601**, app dịch thành "Bạn đã có một yêu cầu đặt sân
  đang chờ duyệt..." và trả HTTP 409.
- **Giới hạn:** chỉ chống spam của một người. 2000 người khác nhau vẫn tạo
  được 2000 PENDING — đúng theo contract.

### IMP-10 — LOCK_TIMEOUT + tự thử lại 1205/1222

- `app/src/server/db/sessionDb.ts`: sau khi mở connection cho phiên, chạy
  `SET LOCK_TIMEOUT <DB_LOCK_TIMEOUT_MS>` (mặc định 5000ms). Mặc định của SQL
  Server là **chờ vô hạn**, trong khi driver `mssql` tự bỏ sau ~15s — tức người
  dùng thấy lỗi nhưng giao dịch **vẫn chạy** trong SQL. Nay SQL tự huỷ (1222).
- **Cố tình KHÔNG đặt `SET LOCK_TIMEOUT` trong stored procedure**: các demo
  `tests/concurrency` cần phiên B chặn thật 8–20 giây để lấy bằng chứng
  (`evidence/`). Đặt trong SP là xóa sạch bằng chứng đó.
- `app/src/server/db/retry.ts` (`withTransientRetry`): thử tối đa 3 lần với
  backoff **có jitter ngẫu nhiên** cho `sp_BookCourt`, `sp_CancelBooking`,
  `sp_ApproveBooking`, `sp_RejectBooking`, `sp_CompleteBooking`.
  Chỉ retry đúng hai mã: **1205** (deadlock victim) và **1222** (lock timeout).
  An toàn vì mọi SP đều `SET XACT_ABORT ON` + `ROLLBACK` trong `CATCH` → giao
  dịch đã hủy sạch, chạy lại không sinh booking đôi hay log đôi.
  Không retry lỗi nghiệp vụ 5xxxx/51xxx (chạy lại cũng sai y như vậy).
- HTTP: 1222 → **503** kèm thông báo "hệ thống đang quá tải"; 1205 giữ 409.

### IMP-11 — Trần phiên đồng thời + rate limit đăng nhập

Mô hình bảo mật Option A (SESSION_CONTEXT) bắt buộc **mỗi phiên giữ riêng một
connection SQL** suốt 8 giờ. Vì vậy số người đăng nhập = số connection.
2000 người đăng nhập = 2000 connection + 2000 lần bắt tay TLS vào SQL Server
Express → hết worker thread, `THREADPOOL` wait, có thể hết file descriptor.

- `MAX_SESSION_CONNECTIONS` (mặc định 200): vượt trần thì `/api/auth/login`
  trả **503 + Retry-After** thay vì để SQL Server tụt. Kiểm tra **sau** khi
  đóng phiên cũ nên người đang đăng nhập lại không bị chặn oan.
- `LOGIN_RATE_LIMIT_PER_MINUTE` (mặc định 60): sliding window theo IP,
  vượt thì **429 + Retry-After**.
- `SESSION_TTL_MS` (mặc định 28.800.000 = 8 giờ): cookie không rolling và
  connection SQL dùng cùng thời hạn tuyệt đối.
- `SESSION_IDLE_TIMEOUT_MS` (mặc định 1.800.000 = 30 phút) và
  `SESSION_SWEEP_INTERVAL_MS` (60.000 = 1 phút): IMP-13 ghi
  `createdAt`/`lastUsedAt`, quét và đóng connection bỏ rơi kể cả khi trình duyệt
  biến mất mà không gọi logout. Logic quyết định expiry nằm riêng trong
  `sessionExpiry.ts`, không import driver SQL và có 12 unit test SX-01…SX-12.
- Cả hai đều là bộ đếm trong bộ nhớ tiến trình → **không thêm dependency nào**
  vào `app/package.json`. Đổi lại: chỉ đúng khi chạy một tiến trình Node.
  Muốn chạy nhiều tiến trình thì cần store dùng chung (Redis).
- Để tắt: đặt `0`. Để quay về hành vi cũ của khoá: `DB_LOCK_TIMEOUT_MS=-1`.

Biến môi trường mới đã được ghi trong `app/.env.example`.

### IMP-15 — `sp_GetAvailableCourts` tự bảo vệ input

Public procedure không còn phụ thuộc riêng vào validation HTTP. Bảy guard chạy
đúng thứ tự như app và ném mã riêng: 50120 NULL; 50121 start >= end; 50122 lệch
bước 30 phút; 50123 qua ngày; 50124 ngoài 60–180 phút; 50125 ngoài 06:00–22:00;
50126 quá khứ. Các mã đều được map trong `spError.ts`; không thêm object SQL.

---

## 6. Những việc CỐ TÌNH KHÔNG LÀM

| Việc | Lý do không làm |
| --- | --- |
| Bỏ mô hình 1 connection/phiên, dùng pool chung | Đó là nền của bảo mật Option A và của phòng chống giả danh (KNOWN-06). Đổi là phải thiết kế và duyệt lại toàn bộ |
| Tự động REJECT các PENDING còn lại khi duyệt một cái | Phá demo CC-01 và sơ đồ chuyển trạng thái §3.4 |
| CHECK `PricePerThreeHours <= PricePerHour * 3` | Chính sách giá, không phải toàn vẹn dữ liệu |
| `WITH SCHEMABINDING` cho function | Làm khó sửa lưỢc đồ về sau, lợi ích không đáng |
| Redis session store / SQL Standard / scale ngang | Chỉ cần cho môi trường thật, ngoài phạm vi đồ án |

---

## 7. Phải chạy lại gì sau khi áp dụng

Tất cả thay đổi ở trên **chưa từng được chạy trên SQL Server thật** trong môi
trường soạn thảo. Theo contract §17 (không kết luận khi chưa có bằng chứng),
phải tự chạy lại trên máy có SQL Server rồi mới cập nhật `evidence/`:

```powershell
# 1. Dụng lại database từ đầu
sqlcmd -S ".\SQLEXPRESS" -E -f 65001 -i database\00_create_database.sql
# ... lần lượt 01 → 08

# 2. Test chức năng (mong đợi 47/47 PASS)
sqlcmd -S ".\SQLEXPRESS" -E -f 65001 -i database\09_tests_functional.sql

# 3. Test giao dịch / isolation (IMP-08 nay sẽ FAIL nếu không thấy phantom)
sqlcmd -S ".\SQLEXPRESS" -E -f 65001 -i database\10_tests_transactions.sql

# 4. Các demo hai phiên trong tests\concurrency (xem README)
```

Sau đó, nếu muốn số liệu tải thật thay cho dự đoán:
`tests/load/README.md`.

---

## IMP-12 — Chặn crash khi lỗi ném ra không phải object (phát hiện bởi test SE-07)

`mapSqlError()` trong `app/src/shared/spError.ts` trước đây đọc thẳng `err.number`.
Nếu tầng dưới ném `null`, chuỗi hoặc số (driver hoặc `Promise.reject('...')`),
hàm này sẽ ném `TypeError` → client nhận 500 trắng thay vì thông báo tiếng Việt.

Đã thêm chạn đầu hàm `errNumber()`:

```ts
if (err === null || (typeof err !== 'object' && typeof err !== 'function')) return null;
```

Bộ test tự động cho toàn bộ cải tiến: xem `docs/TEST_MATRIX.md`,
`app/tests/*.test.ts` (71 ca, đã chạy PASS), `tests/static/check_static.py`
(83 kiểm tra, đã chạy PASS) và `tests/regression/imp_regression.sql`
(55 ca, cần SQL Server).
