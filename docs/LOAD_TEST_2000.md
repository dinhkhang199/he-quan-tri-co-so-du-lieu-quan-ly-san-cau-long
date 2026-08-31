# Phân tích: 2000 người đăng nhập + bấm "Đặt sân" cùng một lúc

> Tài liệu phân tích kiến trúc, dựa trên đọc mã nguồn thật (`app/src/server/db/sessionDb.ts`,
> `app/src/server/routes/{auth,bookings}.ts`, `database/06_procedures.sql`, `database/07_triggers.sql`).
> **Chưa chạy đo thật** — công cụ đo nằm ở `tests/load/` + `app/scripts/loadtest_*.mjs`.

## 1. Tin tốt: TÍNH ĐÚNG ĐẮN không bị phá

`sp_BookCourt` mở transaction rồi khóa **hàng sân** trước khi làm bất cứ việc gì:

```sql
BEGIN TRAN;
    SELECT CourtId FROM dbo.Courts WITH (UPDLOCK, ROWLOCK, HOLDLOCK) WHERE CourtId = @CourtId;
    -- đọc lại IsActive dưới khóa (chống TOCTOU với sp_DeactivateCourt)
    -- kiểm tra overlap với BOOKED
    INSERT INTO dbo.Bookings ... N'PENDING' ...
COMMIT;
```

`sp_ApproveBooking` khóa **cùng một hàng sân, cùng chế độ**, rồi `UPDLOCK` hàng booking và re-check overlap. Trigger `trg_Bookings_PreventBookedOverlap` là lưới an toàn cuối (51001).

Hệ quả với 2000 request đồng thời:

- Không có 2 `BOOKED` chồng khung giờ trên cùng sân (kiểm chứng bằng mục 9 của `observe_contention.sql`).
- Không lost update trạng thái, không TOCTOU với `sp_DeactivateCourt`.
- Tiền (`TotalCost`) luôn do DB tính, client không chèn được.

**=> Về mặt "đúng/sai dữ liệu", hệ thống chịu được 2000 người.**

## 2. Hệ quả nghiệp vụ gây sốc: 2000 PENDING đều THÀNH CÔNG

Contract cho phép nhiều `PENDING` chồng khung giờ (seed b4 & b9 chính là ca đó). Overlap chỉ chặn với `BOOKED`.

Nên nếu 2000 người cùng đặt **sân 01, 19:00–20:00 ngày mai**:

| Bước | Kết quả |
| --- | --- |
| 2000 lần `sp_BookCourt` | **2000 booking PENDING đều tạo thành công** (HTTP 201) |
| Trigger sinh kèm | 2000 dòng `ActivityLogs` + 2000 `Notifications` gửi cho **1 chủ sân** |
| Chủ sân duyệt | Người đầu tiên → `BOOKED`; **1999 lần approve sau đều lỗi 50035/51001** |
| Trải nghiệm | 2000 khách đều tưởng "đặt được", rồi 1999 người bị từ chối sau |

Đây là **thiết kế**, không phải bug — nhưng ở tải cao nó thành 3 vấn đề thật:

1. Không có nguyên tắc "ai trước được trước" ở tầng dữ liệu; ai được chọn phụ thuộc chủ sân bấm cái nào.
2. Không có giới hạn: một khách có thể tạo vô hạn PENDING cùng khung giờ (không CHECK/UNIQUE, không rate limit) → spam/DoS rẻ tiền.
3. Hộp thông báo chủ sân bị 2000 dòng cho **một** khung giờ.

**Đề xuất (cần chủ dự án quyết vì đụng contract §3):** hoặc thêm `UNIQUE`/filtered index chặn 1 khách 1 PENDING trên cùng (sân, khung giờ), hoặc auto-reject phần còn lại khi một booking được approve, hoặc gom thông báo theo khung giờ.

## 3. Điểm nghẽn thật #1 — mỗi phiên đăng nhập giữ RIÊNG 1 connection SQL

`SessionDb.createSession()` tạo `ConnectionPool` với `pool = { min: 1, max: 1 }` cho **từng** phiên web, và giữ đến khi logout (cookie sống 8 giờ). Đây là hệ quả bắt buộc của bảo mật Option A: `sp_Login` set `SESSION_CONTEXT` trên chính connection đó, và `bcm_app` bị `DENY EXECUTE ON sys.sp_set_session_context` nên không thể dựng lại context trên connection khác.

=> **2000 người đăng nhập = 2000 connection SQL Server sống song song**, cộng 2000 TLS handshake (`encrypt: true`) trong vài giây.

Hậu quả theo thứ tự xuất hiện:

| Ngưỡng | Chuyện xảy ra |
| --- | --- |
| ~vài trăm connection | Node bận đàm phán TLS; `connectionTimeout = 5000ms` (mặc định `DB_CONNECT_TIMEOUT_MS`) bắt đầu bắn `ConnectionError` → login trả 500 |
| > `max workers` (thường 512 với 4 core) | Wait type `THREADPOOL` xuất hiện; connection mới xếp hàng, request cũ đứng im |
| Express Edition | Trần 1 socket / 4 core / 1410 MB buffer pool → CPU và bộ nhớ chạm nóc trước cả giới hạn connection |
| Node/Linux | Mỗi connection = 1 socket = 1 fd; `ulimit -n` mặc định 1024 → `EMFILE` (trên Windows ít gặp hơn) |

Còn nữa: `express-session` đang dùng **MemoryStore mặc định** (không cấu hình store), và bản đồ `sessionId → connection` nằm trong RAM của **một** process Node. Nghĩa là:

- Không thể scale ngang (2 process/2 pod là hỏng ngay, trừ khi sticky session).
- Restart server = 2000 phiên chết cùng lúc → tất cả nhận 401 "Phiên đăng nhập đã hết hạn".

**Không có rate limit, không có hàng đợi, không có trần số phiên** ở `app.ts` — không gì cản được cơn bão.

## 4. Điểm nghẽn thật #2 — khóa hàng sân biến mọi thứ thành hàng một

`UPDLOCK, ROWLOCK, HOLDLOCK` trên `dbo.Courts` nghĩa là: **mỗi sân, tại một thời điểm, chỉ 1 transaction đặt/duyệt được chạy.**

Với 6 sân (1 inactive → 5 dùng được), độ song song tối đa là 5 — bất kể máy bao nhiêu core.

Mỗi transaction bên trong khóa còn phải làm:

1. `EXISTS` overlap trên `Bookings`
2. `fn_CalculateBookingCost` (scalar UDF)
3. `INSERT` 1 dòng `Bookings`
4. **4 trigger** `AFTER INSERT`: `AuditInsert` (+1 dòng `ActivityLogs`), `NotifyInsert` (+1 dòng `Notifications`), `PreventBookedOverlap`, và phần `ValidateState`
5. Ghi log của cả 3 bảng + **toàn bộ index** (5 index mới thêm ở `IMP-03` cũng nằm trong đoạn khóa này)

Ước lượng: 1 transaction ≈ 3–8 ms trên SQL Express dùng ổ SSD.

| Kịch bản | Song song | Ước tính tổng thời gian cho 2000 booking | Độ trễ người cuối hàng |
| --- | --- | --- | --- |
| `--slot=same` (tất cả 1 sân) | 1 | 2000 × ~5 ms ≈ **10–20 giây** | ~10–20 s |
| `--slot=spread` (5 sân) | 5 | ≈ **2–5 giây** | ~2–5 s |

Vấn đề: `LOCK_TIMEOUT` mặc định là vô hạn nên request **không tự chết**, chúng chỉ xếp hàng — trong khi driver `mssql` mặc định `requestTimeout = 15000 ms`. Kết quả kinh điển: nhóm người cuối hàng nhận **timeout ở tầng app trong khi transaction vẫn đang chạy dưới DB**. (Vì vậy `loadtest_db.mjs` mặc định nâng `requestTimeout` lên 60 s — để đo đúng độ trễ thật thay vì đo cái timeout.)

Mỗi lần bấm "Đặt sân" còn tốn **2 round-trip** trên cùng connection đó, vì route gọi `verifySessionContext()` (một `SELECT SESSION_CONTEXT(...)`) trước khi gọi `sp_BookCourt`.

## 5. Những thứ vỡ theo (thứ cấp)

| Hiện tượng | Nguyên nhân trong mã |
| --- | --- |
| Danh sách sân chậm/treo trước cả khi đặt | `getSharedPool` chỉ có `max = 10` (`DB_CONNECTION_POOL_MAX`), `sp_GetAvailableCourts` gọi UDF cho từng sân; 2000 người xem sân → xếp hàng ở tarn |
| Lỗi 1205 (deadlock) hiện ra khi trộn đặt/duyệt/hủy/deactivate | Có map sang HTTP 409 + thông báo "vui lòng thử lại", nhưng **không có retry tự động** ở cả server lẫn client → người dùng tự bấm lại |
| Kết quả không xác định ở phút cuối | `sp_BookCourt` chặn quá khứ bằng `SYSDATETIME()`; nếu request xếp hàng 20 s và khung giờ sát hiện tại → có người nhận 50016 dù bấm cùng lúc với người thành công |
| Log/DB phình nhanh | `RECOVERY FULL` + không có backup log trong lúc test; 2000 booking = 6000+ dòng (Bookings + ActivityLogs + Notifications), autogrow file có thể gây stall |
| Node event loop trễ | 1 process, 2000 promise + 2000 socket TLS; `console.error` mỗi request lỗi cũng là I/O đồng bộ |

## 6. Dự đoán kết quả cụ thể (để so với số đo thật)

SQL Server Express 2022, 4 core, SSD, `--slot=same`, 2000 user:

| Chỉ số | Dự đoán |
| --- | --- |
| Đăng nhập thành công | ~60–90% (phần còn lại `ConnectionError`/timeout 5 s) |
| Throughput đăng nhập | ~50–200 login/s (nghẽn ở TLS + tạo connection) |
| `sp_BookCourt` thành công | Gần 100% số phiên đăng nhập được (khóa chỉ làm chậm, không làm sai) |
| Throughput đặt sân | ~100–300 booking/s khi rải sân; **~150–250/s nhưng tuần tự nếu dồn 1 sân** |
| p99 độ trễ đặt sân | 5–20 giây khi dồn 1 sân |
| Wait type nổi bật | `LCK_M_U` trên `Courts`, `WRITELOG`, có thể `THREADPOOL` |
| Số `BOOKED` overlap sai | **0** (đây là tiêu chí phải giữ) |

## 7. Nếu muốn thật sự chịu 2000 người: cần đổi kiến trúc

Các cách sửa, xếp theo tỷ lệ lợi/rủi ro (chưa áp dụng — cần bạn quyết vì đụng bảo mật Option A và contract):

1. **Bỏ mô hình 1 connection/1 phiên.** Truyền actor bằng tham số `@SessionUserId` đã được app xác thực (SP đã nhận tham số này) hoặc dùng một wrapper SP đặt `SESSION_CONTEXT` ngay trong cùng batch, rồi dùng pool chung 50–100 connection. Đây là thay đổi *bắt buộc* để scale, nhưng phải đánh giá lại KNOWN-06 (chống impersonation).
2. **Rate limit + hàng đợi ở tầng app**: giới hạn login/s theo IP, chặn số phiên đồng thời, trả 429 thay vì để SQL Server chết.
3. **Retry tự động** 1205 và lock timeout (3 lần, backoff ngẫu nhiên) trong `bookings.ts` / `manager.ts`.
4. **`SET LOCK_TIMEOUT 5000`** đầu `sp_BookCourt`/`sp_ApproveBooking`: thà trả lỗi "hệ thống đang quá tải" nhanh còn hơn để 2000 người treo vô hạn.
5. **Giảm việc trong đoạn khóa**: chuyển audit/notification sang xử lý sau (queue/job) thay vì 4 trigger đồng bộ; hoặc gộp `Notifications` theo khung giờ.
6. **Thay MemoryStore** bằng store ngoài (Redis/SQL) để scale ngang được.
7. **Chuyển `sp_GetAvailableCourts` sang `NOT EXISTS` dạng set-based** (đã ghi trong `docs/DB_IMPROVEMENTS.md`) và tăng `DB_CONNECTION_POOL_MAX` cho pool công khai.
8. **Nếu ở Express Edition**: đây là trần cứng (1 socket / 1410 MB). Muốn 2000 người thật thì cần Standard/Developer hoặc Azure SQL.

## 8. Cách lấy số liệu thật

Xem `tests/load/README.md`. Tóm tắt:

```powershell
sqlcmd -S ".\SQLEXPRESS" -E -f 65001 -i tests\load\seed_load_users.sql
cd app
node scripts/loadtest_db.mjs --users=2000 --slot=same
# cửa sổ khác, TRONG LÚC chạy:
sqlcmd -S ".\SQLEXPRESS" -E -f 65001 -i tests\load\observe_contention.sql
# xong:
sqlcmd -S ".\SQLEXPRESS" -E -f 65001 -i tests\load\cleanup_load_users.sql
```

Gợi ý leo thang: 50 → 200 → 500 → 1000 → 2000 user, ghi lại p95 và tỉ lệ lỗi ở từng mức để tìm điểm gãy thay vì chỉ biết "2000 thì chết".

> Theo contract §17: mọi con số ở mục 6 là **dự đoán**, chưa phải bằng chứng. Chỉ ghi vào
> `evidence/` sau khi có log thật của lần chạy.
