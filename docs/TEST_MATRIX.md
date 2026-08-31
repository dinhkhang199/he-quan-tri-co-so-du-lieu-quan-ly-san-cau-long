# TEST MATRIX — tự test từng khả năng có thể xảy ra

Tài liệu này liệt kê **tất cả** tình huống đã được nghĩ ra cho các cải tiến
FIX-NULLROLE, IMP-01 → IMP-15, kèm **nơi test** và **trạng thái thật**.

Quy ước trung thực (contract §17 — không kểt quả khi chưa có bằng chứng):

- ✅ **ĐÃ CHẠY** — chạy thật, có log, pass.
- ⏳ **CẦN SQL SERVER** — script đã viết sẵn, chỉ chạy được trên máy có SQL Server.

Máy có SQL Server + `sqlcmd` có thể dựng lại DB và gom toàn bộ log bằng một lệnh
(lưu ý: bước 00 sẽ xóa/tạo lại database `BadmintonCourtManagement`):

```powershell
powershell -ExecutionPolicy Bypass -File tests\run_all_evidence.ps1 -AppPassword "MatKhauManh#2026"
```

Log và `SUMMARY.csv` được ghi vào `evidence\patched\`. Chỉ dùng dòng PASS từ
summary sau khi script thực sự chạy xong; sự tồn tại của runner không phải bằng chứng.

---

## 1. Tầng app — ĐÃ CHẠY (71/71 PASS)

```bash
cd app
node --import tsx --test tests/retry.test.ts
node --import tsx --test tests/rateLimit.test.ts
node --import tsx --test tests/sessionExpiry.test.ts
node --import tsx --test tests/time.test.ts
node --import tsx --test tests/spError.test.ts
```

### 1.1 `tests/retry.test.ts` — IMP-10 tự thử lại (11 ca) ✅

| ID | Khả năng |
|---|---|
| RT-01 | Thành công ngay lần đầu → không thử lại |
| RT-02 | Deadlock 1205 lần 1, thành công lần 2 |
| RT-03 | Lock timeout 1222 lần 1–2, thành công lần 3 |
| RT-04 | Lỗi tạm thời liên tục → dừng ở 3 lần, ném lỗi cuối |
| RT-05 | Lỗi nghiệp vụ (50021 trùng giờ) → KHÔNG thử lại (quan trọng: tránh đặt trùng 2 lần) |
| RT-06 | Lỗi mạng/không có mã số → không thử lại |
| RT-07 | `err.code` dạng chuỗi `'1205'` vẫn nhận ra |
| RT-08 | `isTransientSqlError` đúng cho 1205/1222, sai cho 2601/50021/`null` |
| RT-09 | Backoff tăng dần (lần 2 chờ lâu hơn lần 1) |
| RT-10 | Jitter khác nhau giữa các lần (không đụng độ đồng loạt) |
| RT-11 | `attempts = 1` → không thử lại gì cả |

### 1.2 `tests/rateLimit.test.ts` — IMP-11 chống dồn đăng nhập (9 ca) ✅

| ID | Khả năng |
|---|---|
| RL-01 | Dưới ngưỡng → cho qua |
| RL-02 | Vượt ngưỡng → 429 |
| RL-03 | Thân phản hồi 429 có thông báo tiếng Việt |
| RL-04 | Có header `Retry-After` |
| RL-05 | Hết cửa sổ thời gian → đếm lại từ đầu |
| RL-06 | Đếm riêng theo IP (IP khác không bị ảnh hưởng) |
| RL-07 | `limit = 0` → tắt hẳn bộ giới hạn |
| RL-08 | Không có IP → gộp vào khoá `unknown`, không crash |
| RL-09 | 2000 request từ cùng 1 IP → đúng `limit` cái đầu đi qua, phần còn lại 429 |

### 1.3 `tests/time.test.ts` — luật khung giờ (30 ca) ✅

Bản đầy đủ các ca: thiếu tham số, chuỗi rác, `06:15` (lệch bước 30′),
giây lẻ, `end <= start`, qua đêm, 30′ (thiếu), 3h30′ (vượt), đúng 60′,
đúng 180′, biên `06:00`, biên `22:00`, `05:30`, `22:30`, giờ đã trôi qua,
định dạng `YYYY-MM-DD HH:MM:SS`, `minutesOfDay`, `toSqlDate` không bị lệch
UTC, GUID hợp lệ / hoa thường / thiếu ký tự / có ký tự lạ, `courtId` rỗng,
thứ tự ưu tiên thông báo lỗi (parse → bước → end>start → cùng ngày →
thỏi lượng → khung hoạt động → quá khứ).

### 1.4 `tests/spError.test.ts` — dịch lỗi SQL (9 ca) ✅

| ID | Khả năng |
|---|---|
| SE-01…SE-05 | Mã nghiệp vụ 50001/50011/50021/51054… → thông báo tiếng Việt đúng |
| SE-06 | 1222 (chờ khoá quá lâu) → câu “hệ thống đang quá tải” |
| SE-07 | **Ném `null` / chuỗi / số thay vì `Error` → không được crash** (tìm ra bug thật, xem §5) |
| SE-08 | 2601 (đã có yêu cầu chờ duyệt) → thông báo riêng |
| SE-09 | Mã lạ → câu mặc định, không lộ stack trace ra client |

### 1.5 `tests/sessionExpiry.test.ts` — IMP-13 vòng đời connection phiên (12 ca) ✅

| ID | Khả năng |
|---|---|
| SX-01…SX-06 | TTL/idle trước biên, đúng biên, vượt biên; timestamp tương lai không bị đóng oan |
| SX-07…SX-09 | Có thể tắt từng deadline trong logic thuần; touch không lùi đồng hồ/đổi createdAt |
| SX-10…SX-11 | Bộ quét chọn đúng id; hoạt động mới chỉ kéo idle, không kéo TTL tuyệt đối |
| SX-12 | 2000 phiên bỏ rơi bị quét sạch, phiên đang dùng vẫn còn |

---

## 2. Kiểm tra tĩnh toàn bộ mã SQL + app — ĐÃ CHẠY (83/83 PASS)

```bash
python3 tests/static/check_static.py
```

Bao gồm: 9 SP đều có chạn `IF @Role IS NULL`; đúng 5 bảng / 4 view /
2 function / 14 SP / 6 trigger như contract; 10 CHECK constraint IMP-01;
14 index đều có `IF NOT EXISTS`; `UQ_Bookings_OnePendingPerUserSlot` có filter
`Status = N'PENDING'`; công thức giá IMP-05 có `ROUND(...)`; IMP-04 `CAST(1 AS BIT)`;
seed không có 2 PENDING trùng bộ ba; bản đồ mã lỗi SQL ↔ app khớp từng mã;
HTTP status 1205→409, 1222→503, 2601→409 ở cả 4 nhánh; không có
`SET LOCK_TIMEOUT` trong file SQL; `.env.example` có đủ biến session mới;
build server có emit; IMP-13 reaper và IMP-15 50120–50126 đúng thứ tự;
không còn plaintext password; 157/173 batch T-SQL parse được bằng `sqlglot`.

> **Cảnh báo trung thực:** 16 batch còn lại `sqlglot` không đọc được là do
> bản thân `sqlglot` chưa hỗ trợ vài cú pháp T-SQL (`GRANT ... ON`, `PRINT N'...'`,
> `MERGE`), **không phải lỗi của project**. Chỉ SQL Server mới phán quyết cuối.

---

## 3. Tầng DB — CẦN SQL SERVER (55 ca đã viết sẵn)

```bat
sqlcmd -S ".\SQLEXPRESS" -E -f 65001 -i tests\regression\imp_regression.sql
```

Mọi test đều nằm trong `BEGIN TRAN ... ROLLBACK` → không làm bẩn dữ liệu.

| Nhóm | ID | Khả năng được test |
|---|---|---|
| A. FIX-NULLROLE | RG-01…RG-09 | 9 SP nghiệp vụ bị gọi với UserId không tồn tại → phải throw đúng mã (50010/50030/50040/50050/50060/50070/50080/50090/50110) |
| | RG-10…RG-12 | User có thật nhưng `IsActive = 0` → vẫn phải bị chặn |
| B. IMP-01 CHECK | RG-13 | Booking 30 phút |
| | RG-14 | Booking 4 giờ |
| | RG-15 | Bắt đầu 08:15 (lệch bước 30′) |
| | RG-16 | Có giây lẻ 08:30:30 |
| | RG-17 | Bắt đầu 05:00 (chưa mở cửa) |
| | RG-18 | Kết thúc 23:00 (đã đóng cửa) |
| | RG-19 | Vắt qua nửa đêm |
| | RG-20 | `TotalCost` âm |
| | RG-21 | Username < 3 ký tự |
| | RG-22 | Số điện thoại có chữ |
| | RG-23 | Tên sân toàn khoảng trắng |
| | RG-24 | Địa chỉ sân rỗng |
| | RG-25 | Nội dung thông báo rỗng |
| | **RG-26** | **Đối chứng: dữ liệu HỢP LỆ vẫn vào được** (CHECK không chặn oan) |
| C. IMP-09 index | RG-27 | Cùng người spam 2 PENDING trùng → 2601 |
| | **RG-28** | **Đối chứng: 2 khách KHÁC nhau vẫn PENDING cùng giờ** (không phá CC-01) |
| | RG-29 | 1 BOOKED + 1 PENDING cùng giờ → index không can thiệp |
| | RG-30 | Cùng người, 2 khung giờ khác nhau |
| | RG-31 | Cùng người, 2 sân khác nhau, cùng giờ |
| | RG-32 | Bị từ chối rồi đặt lại đúng khung giờ đó |
| | RG-33 | Metadata index: tồn tại, `is_unique`, `has_filter` |
| | RG-44 | Dữ liệu đang có không vi phạm ràng buộc mới |
| D. IMP-05 giá | RG-34…RG-38 | 60 / 90 / 120 / 150 / 180 phút → đúng số tiền |
| | RG-39 | Nghịch lý giá: có sân nào mà 2,5 giờ đắt hơn 3 giờ không |
| | RG-40 | Chi phí >= 0 và nguyên đồng |
| E. Bất biến | RG-41 | IMP-04 còn nguyên trong `sp_GetAvailableCourts` |
| | RG-42 | Không SP nào có `SET LOCK_TIMEOUT` (để demo tranh khoá còn đúng) |
| | RG-43 | Đủ 5/4/2/14/6 đối tượng theo contract |
| F. IMP-15 | RG-45…RG-51 | 7 guard input của `sp_GetAvailableCourts` ném đúng 50120…50126 |
| | RG-52 | Đối chứng 09:00–10:30 hợp lệ vẫn trả danh sách sân |
| | RG-53 | `CourtId` không tồn tại trả danh sách rỗng, không throw |
| G. Ownership | RG-54 | `bcm_app` không SESSION_CONTEXT đọc `vw_AllBookings` nhận 0 dòng |
| | RG-55 | Sysadmin vẫn thấy đủ booking cho functional/transaction/backup test |

### Các bộ test DB đã có từ trước (cũng cần SQL Server)

| Script | Nội dung |
|---|---|
| `database/09_tests_functional.sql` | 47 ca nghiệp vụ (đăng nhập, đặt sân, duyệt, huῷ, phân quyền) |
| `database/10_tests_transactions.sql` | ACID, isolation level, rollback |
| `tests/concurrency/*` | Lost update, dirty read, phantom, deadlock — chạy 2 cửa sổ sqlcmd |
| `tests/load/*` + `app/scripts/loadtest_db.mjs` | 2000 người đăng nhập và bấm đặt cùng lúc |

---

## 4. Những khả năng KHÔNG thể tự test ở máy này

| Khả năng | Vì sao | Chạy ở đâu |
|---|---|---|
| Khoá `UPDLOCK/HOLDLOCK`, deadlock 1205, `LOCK_TIMEOUT` 1222 | cần SQL Server thật | `tests/concurrency`, `imp_regression` |
| Unique filtered index chặn ở tầng DB | cần SQL Server thật | RG-27…RG-33 |
| Thứ tự đọc index / query plan | cần SQL Server thật | `SET STATISTICS IO ON` |
| Số liệu thực 2000 người (p95, tỷ lệ 429/503) | cần DB + máy thật | `docs/LOAD_TEST_2000.md` |

Build production và ESLint đã chạy lại ngày 2026-08-22: `npm run build` và
`npm run lint` đều PASS; smoke-test `npm start` trả HTTP 200 cho SPA đã bundle.

---

## 5. Lỗi THẬT do bộ test này phát hiện

**IMP-12 — `errNumber()` crash khi lỗi ném ra không phải object.**

Ca SE-07 ném `null` vào `mapSqlError()` và code cũ đọc `err.number` →
`TypeError: Cannot read properties of null`. Ở thực tế, một lỗi ném từ driver
hoặc từ `Promise.reject()` dạng chuỗi sẽ làm **500 trắng** thay vì thông báo
tiếng Việt. Đã sửa bằng chạn đầu hàm trong `app/src/shared/spError.ts`:

```ts
if (err === null || (typeof err !== 'object' && typeof err !== 'function')) return null;
```

Sau khi sửa: 71/71 test app PASS.
