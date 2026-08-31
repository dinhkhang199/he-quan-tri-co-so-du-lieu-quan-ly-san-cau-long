# Load test — 2000 người đăng nhập + đặt sân cùng lúc

Bộ công cụ này **không** thuộc `database/00..15` (contract §14 khóa cấu trúc đó). Nó chỉ để đo tải và chứng minh bằng số liệu.

## 0. Yêu cầu

- SQL Server (Express cũng được) + database đã build xong `00 → 08`.
- Node ≥ 20, đã `npm install` trong `app/`, đã có `app/.env` (DB_USER=`bcm_app`, DB_PASSWORD=…).

## 1. Nạp 2000 account thử tải (chạy bằng quyền sysadmin)

```powershell
sqlcmd -S ".\SQLEXPRESS" -E -f 65001 -i tests\load\seed_load_users.sql
```

Tạo `loadtest000001` … `loadtest002000`, password `load123`, role `CUSTOMER`. Script chạy lại được.

## 2A. Bão tải ở tầng DATABASE (bỏ qua HTTP)

```powershell
cd app
node scripts/loadtest_db.mjs --users=2000 --slot=same     # tất cả tranh 1 sân / 1 khung giờ
node scripts/loadtest_db.mjs --users=2000 --slot=spread   # rải trên 5 sân × 14 khung giờ
```

Mô phỏng đúng `SessionDb`: mỗi user = 1 ConnectionPool riêng (`min = max = 1`), `sp_Login` một lần, rồi tất cả cùng gọi `sp_BookCourt`.

## 2B. Bão tải ở tầng HTTP (Express + express-session)

```powershell
# cửa sổ 1
cd app; npm run dev:server
# cửa sổ 2
cd app; node scripts/loadtest_http.mjs --users=2000 --slot=same
```

## 3. Quan sát tranh chấp TRONG LÚC bão tải (cửa sổ thứ 3, sysadmin)

```powershell
sqlcmd -S ".\SQLEXPRESS" -E -f 65001 -i tests\load\observe_contention.sql
```

Cái cần nhìn:

| Mục | Ý nghĩa |
| --- | --- |
| 1 | Số session của `bcm_app` ≈ số người đã đăng nhập (1 connection / 1 phiên) |
| 2–4 | `LCK_M_U` / `request_status = WAIT` trên `dbo.Courts` = lock convoy trên hàng sân |
| 5 | `THREADPOOL` > 0 = đã hết worker thread, SQL bắt đầu từ chối/xếp hàng kết nối |
| 6 | `MaxWorkers` vs `Connections` — trần thật của instance |
| 9 | **Phải trả về 0 dòng**: không có 2 `BOOKED` overlap → tính đúng đắn còn nguyên |

## 4. Dọn dẹp (bắt buộc trước khi chạy lại `09_tests_functional.sql`)

```powershell
sqlcmd -S ".\SQLEXPRESS" -E -f 65001 -i tests\load\cleanup_load_users.sql
```

Kỳ vọng sau cleanup: `Users=7, Courts=6, Bookings=15, ActivityLogs=3, Notifications=2`.

> Nếu muốn sạch tuyệt đối: chạy lại `01 → 08` rồi `09`.

## 5. Phân tích kết quả kỳ vọng

Xem `docs/LOAD_TEST_2000.md`.
