# BadmintonCourtManagement — Quản lý sân cầu lông

Hệ thống quản lý đặt sân cầu lông (BadmintonPro) — dự án bài tập cơ sở dữ liệu,
triển khai đầy đủ trên **Microsoft SQL Server + T-SQL** với ứng dụng web
**TypeScript (Node.js + React)**.

## Nội dung

1. [Tính năng chính](#tính-năng-chính)
2. [Vai trò](#vai-trò)
3. [Công nghệ](#công-nghệ)
4. [Kiến trúc tổng quan](#kiến-trúc-tổng-quan)
5. [Cài đặt Database](#cài-đặt-database)
6. [Cài đặt ứng dụng](#cài-đặt-ứng-dụng)
7. [Biến môi trường](#biến-môi-trường)
8. [Tài khoản Demo](#tài-khoản-demo)
9. [Chạy ứng dụng](#chạy-ứng-dụng)
10. [Luồng Demo](#luồng-demo)
11. [Kiểm thử & Bằng chứng](#kiểm-thử--bằng-chứng)
12. [Mô hình Bảo mật](#mô-hình-bảo-mật)
13. [Hạn chế & Quy tắc Kinh doanh](#hạn-chế--quy-tắc-kinh-doanh)
14. [Demo Kỹ thuật](#demo-kỹ-thuật)
15. [Cấu trúc kho](#cấu-trúc-kho)

---

## Tính năng chính

### CUSTOMER
- Đăng nhập
- Tìm kiếm sân trống (public, không cần đăng nhập)
- Xem chi phí dự kiến trước khi đặt
- Tạo booking (trạng thái PENDING)
- Lịch sử đặt sân — xem, hủy theo quy tắc trạng thái/thời gian
- Thông báo & đánh dấu đã đọc

### MANAGER
- Bảng điều khiển (Dashboard) — tổng quan hệ thống
- Quản lý booking — duyệt / từ chối / hoàn thành / hủy
- Quản lý sân — tạo / cập nhật / ngừng hoạt động (soft delete)
- Thông báo
- Drawer Demo Kỹ thuật (đọc-only)

### COURT_MANAGER
- Giao diện giống MANAGER, phạm vi dữ liệu giới hạn theo sân sở hữu
- Dashboard theo phạm vi sân sở hữu
- Quản lý sân/booking chỉ trên sân của mình
- Thông báo

---

## Vai trò

| Vai trò | Phạm vi |
|---------|---------|
| **MANAGER** | Toàn hệ thống — tất cả sân, booking, dashboard |
| **COURT_MANAGER** | Chỉ sân sở hữu — booking, dashboard, quản lý sân giới hạn theo OwnerId |
| **CUSTOMER** | Tìm sân, đặt sân, lịch sử, thông báo |

Không có vai trò `ADMIN` chung. Không có tự đăng ký (registration).

---

## Công nghệ

| Thành phần | Lựa chọn |
|-----------|---------|
| Database | Microsoft SQL Server 2019+ (T-SQL) |
| Backend | Express 4 + TypeScript (chạy qua `tsx`) |
| Frontend | React 18 + TypeScript + Vite |
| SQL Driver | `mssql` v11 (tedious) |
| Session | `express-session` + SessionDb dedicated connection |
| Routing | Express (`/api/*`) + React Router |

Chi tiết kiến trúc: `app/ARCHITECTURE.md`

---

## Kiến trúc tổng quan

```
Browser → Vite dev server (port 5173, proxy /api → 3000)
              ↓
         Express (port 3000)
              ↓
    ┌─────────┴─────────┐
    │   Shared pool      │  ← sp_GetAvailableCourts (guest)
    │   (no session)     │
    ├────────────────────┤
    │   SessionDb        │  ← Mỗi web session giữ 1 SQL connection riêng
    │   (sp_Login once)  │     SESSION_CONTEXT('UserId', 'Role') giữ nguyên
    └─────────┬─────────┘
              ↓
         SQL Server
    ┌─────────┴─────────┐
    │  14 Stored Procs   │  ← Tất cả nghiệp vụ đi qua SP
    │  6 Triggers        │
    │  4 Views           │
    │  2 Functions       │
    └───────────────────┘
```

**Quy tắc cốt lõi:** Ứng dụng **không bao giờ** gửi `UserId`, `Role`, `OwnerId`,
`Status`, `TotalCost` từ trình duyệt. Tất cả quyền hạn, giá cả, trạng thái
được quyết định bởi Stored Procedures trên SQL Server.

---

## Cài đặt Database

### Yêu cầu
- SQL Server 2019 trở lên
- sqlcmd hoặc SSMS

### Thứ tự cài đặt (NORMAL — scripts 00–08)

> **Quan trọng:** Tất cả script SQL chứa tiếng Việt phải chạy với `-f 65001` trên Windows.

```bash
# Khởi tạo database
sqlcmd -S ".\SQLEXPRESS" -i database\00_create_database.sql

# Bảng + ràng buộc
sqlcmd -S ".\SQLEXPRESS" -f 65001 -i database\01_tables_constraints.sql

# Seed dữ liệu demo
sqlcmd -S ".\SQLEXPRESS" -f 65001 -i database\02_seed.sql

# Index
sqlcmd -S ".\SQLEXPRESS" -i database\03_indexes.sql

# Functions
sqlcmd -S ".\SQLEXPRESS" -f 65001 -i database\04_functions.sql

# Views
sqlcmd -S ".\SQLEXPRESS" -f 65001 -i database\05_views.sql

# Stored Procedures
sqlcmd -S ".\SQLEXPRESS" -f 65001 -i database\06_procedures.sql

# Triggers
sqlcmd -S ".\SQLEXPRESS" -f 65001 -i database\07_triggers.sql

# Security (role + user + DENY) — yêu cầu mật khẩu SQL
sqlcmd -S ".\SQLEXPRESS" -f 65001 -i database\08_security.sql -v BCM_APP_PASSWORD="<YOUR_LOCAL_PASSWORD>"
```

> **Lưu ý bảo mật:** Chọn mật khẩu cho SQL login `bcm_app` và sử dụng **cùng giá trị**
> với `DB_PASSWORD` trong file `app/.env`. Không commit `app/.env`. Không đặt mật khẩu
> thật vào README hoặc bất kỳ file nào trong kho.

Hoặc chạy tuần tự trong SSMS: `00` → `01` → `02` → `03` → `04` → `05` → `06` → `07` → `08`.
Khi chạy trong SSMS, bạn cần khai báo biến SQLCMD thủ công trước script:
```sql
:SETVAR BCM_APP_PASSWORD "<YOUR_LOCAL_PASSWORD>"
```

### Kiểm thử chức năng (sau khi cài đặt xong)

```bash
# Test matrix phiên đơn — kỳ vọng 47/47 PASS
sqlcmd -S ".\SQLEXPRESS" -f 65001 -i database\09_tests_functional.sql
```

### Scripts khác (để riêng, KHÔNG chạy khi cài đặt)

| Script | Mục đích |
|--------|----------|
| `10_tests_transactions.sql` | Phantom demo (1 cửa sổ) |
| `11 + 12` | Concurrency demo (2 cửa sổ) |
| `13 + 14` | Deadlock demo (2 cửa sổ) |
| `15_backup_restore_demo.sql` | Backup/Restore RC-01 |

Xem `tests/concurrency/README.md` và section [Kiểm thử & Bằng chứng](#kiểm-thử--bằng-chứng).

---

## Cài đặt ứng dụng

### Yêu cầu
- Node.js >= 20
- npm
- SQL Server đã cài đặt database (xem trên)

### Cài đặt

```bash
cd app
npm install

# Tạo file cấu hình từ template
copy .env.example .env
# Chỉnh sửa .env — điền password SQL và session secret
```

### Biến môi trường

| Biến | Mô tả | Mặc định |
|------|-------|---------|
| `DB_SERVER` | SQL Server instance | `localhost\SQLEXPRESS` |
| `DB_DATABASE` | Tên database | `BadmintonCourtManagement` |
| `DB_USER` | SQL login | `bcm_app` |
| `DB_PASSWORD` | SQL password | **bắt buộc điền** |
| `DB_TRUST_SERVER_CERTIFICATE` | Chấp nhận self-signed cert | `true` |
| `DB_CONNECTION_POOL_MAX` | Số kết nối pool tối đa | `10` |
| `DB_CONNECT_TIMEOUT_MS` | Timeout kết nối (ms) | `5000` |
| `SESSION_SECRET` | Secret ký session cookie | **bắt buộc điền** |
| `APP_PORT` | Cổng backend | `3000` |
| `VITE_DEV_PORT` | Cổng Vite dev server | `5173` |

**KHÔNG** commit file `.env` — nó đã bị `.gitignore`.

---

## Tài khoản Demo

Tài khoản được seed bởi `database/02_seed.sql` (hash `SHA2_256(N'bcms|' + password)`):

| Username | Password | Vai trò |
|----------|----------|---------|
| `manager` | `manager123` | MANAGER |
| `courtmanager1` | `cm1pass` | COURT_MANAGER |
| `courtmanager2` | `cm2pass` | COURT_MANAGER |
| `customer1` | `cus1pass` | CUSTOMER |
| `customer2` | `cus2pass` | CUSTOMER |
| `customer3` | `cus3pass` | CUSTOMER |
| `inactive_user` | `inactive1` | CUSTOMER (inactive — đăng nhập bị từ chối) |

**Seed chứa 6 sân** (thuộc courtmanager1 và courtmanager2, 1 sân inactive) và **15 booking** demo ở các trạng thái khác nhau.

---

## Chạy ứng dụng

### Development (khuyến nghị cho demo)

```bash
cd app

# Chạy cả backend + frontend cùng lúc
npm run dev
# → Server: http://localhost:3000
# → Frontend: http://localhost:5173
```

Hoặc chạy riêng:

```bash
npm run dev:server   # Backend trên port 3000
npm run dev:client   # Vite dev server trên port 5173, proxy /api → 3000
```

### Kiểm tra code

```bash
npm run typecheck   # TypeScript check
npm run lint        # ESLint
npm run build       # Typecheck + Vite production build
```

### Production build

```bash
npm run build       # Output: app/dist/
npm run start       # Chạy production (cần build trước)
```

---

## Luồng Demo

### 1. Guest tìm sân
1. Mở `http://localhost:5173/courts`
2. Chọn ngày + khung giờ → "Tìm sân trống"
3. Kết quả đến từ `sp_GetAvailableCourts` — DB là nguồn gốc duy nhất

### 2. CUSTOMER đặt sân
1. Đăng nhập `customer1` / `cus1pass`
2. Chọn sân → chuyển sang trang `/booking/:courtId?startTime=...&endTime=...`
3. Xem chi phí dự kiến (từ `fn_CalculateBookingCost`)
4. "Xác nhận đặt sân" → tạo PENDING booking qua `sp_BookCourt`
5. Kiểm tra lịch sử: `/my-bookings` → thấy booking PENDING

### 3. MANAGER duyệt booking
1. Đăng nhập `manager` / `manager123`
2. `/manager/bookings` → thấy danh sách booking
3. Duyệt booking PENDING → "Duyệt" → trạng thái thành BOOKED
4. Hoặc "Từ chối" → REJECTED

### 4. CUSTOMER thấy trạng thái mới
1. Đăng nhập lại `customer1`
2. `/my-bookings` → thấy trạng thái BOOKED
3. `/notifications` → thấy thông báo trạng thái (tạo bởi trigger)

### 5. Quy tắc hủy
- **PENDING**: CUSTOMER có thể hủy bất kỳ lúc nào
- **BOOKED**: CUSTOMER chỉ được hủy khi còn >= 3 giờ trước StartTime
- **COMPLETED / REJECTED**: không thể hủy

### 6. Quản lý sân
1. MANAGER/COURT_MANAGER → `/manager/courts`
2. Tạo / cập nhật / ngừng hoạt động sân
3. Sân ngừng hoạt động là soft delete (`IsActive = 0`)

---

## Kiểm thử & Bằng chứng

### Test chức năng (47/47 PASS)

```bash
# Chạy lại test matrix
sqlcmd -S ".\SQLEXPRESS" -f 65001 -i database\09_tests_functional.sql
```

Bằng chứng: `evidence/final_09.txt`, `evidence/PHASE1_TEST_REPORT.md`

### Phantom (READ COMMITTED / SERIALIZABLE)

```bash
# 1 cửa sổ SSMS
sqlcmd -S ".\SQLEXPRESS" -f 65001 -i database\10_tests_transactions.sql
```

Bằng chứng: `evidence/final_10.txt`, `evidence/final_phantom_A.txt` + `_B.txt`

### Concurrency (2 cửa sổ — chạy đồng thời)

```bash
# Cửa sổ A
sqlcmd -S ".\SQLEXPRESS" -f 65001 -i database\11_tests_concurrency_session_A.sql -o evidence\final_11.txt
# Cửa sổ B (chạy sau A ~3 giây)
sqlcmd -S ".\SQLEXPRESS" -f 65001 -i database\12_tests_concurrency_session_B.sql -o evidence\final_12.txt
```

Kịch bản:
- **CC-01**: Hai PENDING overlap cùng sân → nhiều nhất 1 BOOKED
- **CC-02**: Khóa đọc viết → không lost update

Bằng chứng: `evidence/final_11.txt` + `final_12.txt`

### Deadlock (2 cửa sổ — chạy đồng thời, cách nhau <= 2 giây)

```bash
# Cửa sổ A
sqlcmd -S ".\SQLEXPRESS" -f 65001 -i database\13_deadlock_demo_session_A.sql -o evidence\final_13.txt
# Cửa sổ B
sqlcmd -S ".\SQLEXPRESS" -f 65001 -i database\14_deadlock_demo_session_B.sql -o evidence\final_14.txt
```

Kịch bản:
- **DL-01**: Thứ tự khóa chéo → SQL Server chọn victim (lỗi 1205)
- **DL-02**: Cùng thứ tự khóa → không deadlock
- **DL-03**: Approve vs Cancel qua SP thật → không 1205

Bằng chứng: `evidence/final_13.txt` + `final_14.txt`

### Backup/Restore (RC-01)

```bash
sqlcmd -S ".\SQLEXPRESS" -f 65001 -i database\15_backup_restore_demo.sql
```

Bằng chứng: `evidence/final_15.txt`

### Demo cô lập giao dịch (bên ngoài canonical build)

Chi tiết trong `tests/concurrency/README.md`. Các demo này:
- Lost Update, Dirty Read, Non-repeatable Read, Phantom Read, TOCTOU
- Chạy trên 2 cửa sổ sqlcmd riêng biệt
- Không thay đổi object set sản xuất

---

## Mô hình Bảo mật

### SQL Session Security (Option A)

- **`bcm_app`**: SQL login duy nhất của ứng dụng
- **`bcm_app_role`**: database role — được EXECUTE các SP, bị DENY DML trực tiếp lên bảng
- **`SESSION_CONTEXT`**: `sp_Login` thiết lập `SESSION_CONTEXT('UserId')` / `('Role')` trên kết nối dedicated

### Kết nối Session (SessionDb)

- Mỗi web session (cookie) giữ **một kết nối SQL riêng biệt**
- `sp_Login` chạy **một lần duy nhất** trên kết nối đó
- Tất cả SP nghiệp vụ chạy trên **cùng kết nối** → SESSION_CONTEXT luôn hợp lệ
- Khi mất kết nối → yêu cầu đăng nhập lại
- `sp_GetAvailableCourts` (guest) chạy trên shared pool — không cần session

### DENY trực tiếp

`bcm_app` bị từ chối:
- INSERT/UPDATE/DELETE trên `Users`, `Courts`, `Bookings`, `Notifications`, `ActivityLogs`
- EXECUTE `sys.sp_set_session_context`

Tất cả thao tác ghi dữ liệu **phải** đi qua Stored Procedures.

---

## Hạn chế & Quy tắc Kinh doanh

### Đặt sân
- Khung giờ hoạt động: **06:00–22:00**
- Bước nhảy: **30 phút**
- Thời lượng: **tối thiểu 1 giờ**, **tối đa 3 giờ**
- Không đặt trong quá khứ
- `StartTime < EndTime`, cùng ngày
- Khoảng trùng: `[StartTime, EndTime)` — chạm biên không tính trùng

### Trạng thái booking

```
PENDING → BOOKED → COMPLETED
PENDING → REJECTED
PENDING → CANCELLED
BOOKED  → CANCELLED
```

Không thể khôi phục từ trạng thái cuối cùng.

### Hủy booking
- CUSTOMER + PENDING: luôn được
- CUSTOMER + BOOKED: chỉ khi còn >= 3 giờ trước StartTime
- MANAGER/COURT_MANAGER: theo quy tắc SP (không áp dụng ràng buộc 3 giờ)

### Quản lý sân
- Soft delete: `IsActive = 0`
- Không có tính năng kích hoạt lại (Activate)
- Không có hard DELETE

### Gía
- Baseline seed: `PricePerHour = 100.000đ`, `PricePerThreeHours = 270.000đ`
- Revenue trên Dashboard là **theoretical booking value** — không phải tiền thực thu

---

## Demo Kỹ thuật

Trang `/manager/bookings` có Drawer Demo Kỹ thuật (đọc-only, giáo dục):

| Tab | Nội dung |
|-----|---------|
| Approve cạnh tranh | Giải thích CC-01: hai PENDING overlap → nhiều nhất 1 BOOKED |
| Deadlock | Giải thích DL-01: cyclic lock wait → SQL Server victim 1205 |
| Phantom Read | Giải thích PH-01/PH-02: READ COMMITTED phantom → SERIALIZABLE prevent |

Drawer **không**:
- Thực thi SQL tuỳ ý
- Gây deadlock
- Thay đổi dữ liệu nghiệp vụ
- Hiển thị thông tin đăng nhập

Bằng chứng thực tế nằm trong `database/` và `evidence/`.

---

## Cấu trúc kho

```
BadmintonCourtManagement/
├── AGENTS.md                      ← Hướng dẫn cho coding agent
├── README.md                      ← Tài liệu này
├── app/                           ← Ứng dụng web Phase 2
│   ├── ARCHITECTURE.md            ← Kiến trúc + quyết định thiết kế
│   ├── .env.example               ← Template biến môi trường
│   ├── package.json
│   ├── src/
│   │   ├── shared/                ← Contract + types + error map
│   │   ├── server/                ← Express + routes + SessionDb
│   │   └── frontend/              ← React pages + components + styles
│   └── ...
├── database/                      ← SQL Server scripts (Phase 1)
│   ├── 00_create_database.sql     ← Tạo database
│   ├── 01_tables_constraints.sql  ← 5 bảng + PK/FK/CHECK
│   ├── 02_seed.sql                ← Dữ liệu demo (7 users, 6 courts, 15 bookings)
│   ├── 03_indexes.sql
│   ├── 04_functions.sql           ← 2 functions
│   ├── 05_views.sql               ← 4 views
│   ├── 06_procedures.sql          ← 14 stored procedures
│   ├── 07_triggers.sql            ← 6 triggers
│   ├── 08_security.sql            ← Role + DENY
│   ├── 09_tests_functional.sql    ← 47/47 test matrix
│   ├── 10_tests_transactions.sql  ← Phantom demo
│   ├── 11_tests_concurrency_session_A.sql
│   ├── 12_tests_concurrency_session_B.sql
│   ├── 13_deadlock_demo_session_A.sql
│   ├── 14_deadlock_demo_session_B.sql
│   └── 15_backup_restore_demo.sql ← RC-01
├── tests/concurrency/             ← Demo cô lập giao dịch
│   ├── README.md
│   └── *_session_{A,B}.sql        ← Lost Update, Dirty Read, etc.
├── evidence/                      ← Bằng chứng chạy test
│   ├── final_00.txt … final_15.txt
│   └── PHASE1_TEST_REPORT.md
├── design/                        ← Stitch UI export (locked)
│   └── stitch_badminton_court_management_system/
└── docs/                          ← Tài liệu Phase 2
    ├── IMPLEMENTATION_PLAN.md
    ├── PHASE2_CONTEXT.md
    └── UI_SCREEN_MAP.md
```

---

## Database Object Summary

| Loại | Số lượng | Chi tiết |
|------|----------|---------|
| Tables | 5 | Users, Courts, Bookings, ActivityLogs, Notifications |
| Views | 4 | vw_AvailableCourts, vw_BookingHistory, vw_AdminDashboard, vw_AllBookings |
| Functions | 2 | fn_CalculateBookingCost, fn_IsCourtAvailable |
| Stored Procedures | 14 | sp_Login, sp_BookCourt, sp_ApproveBooking, sp_RejectBooking, sp_CancelBooking, sp_CompleteBooking, sp_CreateCourt, sp_UpdateCourt, sp_DeactivateCourt, sp_GetAvailableCourts, sp_GetMyBookings, sp_GetNotifications, sp_MarkNotificationRead, sp_GetDashboard |
| Triggers | 6 | trg_Bookings_AuditInsert, trg_Bookings_AuditStatus, trg_Bookings_NotifyInsert, trg_Bookings_NotifyStatus, trg_Bookings_ValidateState, trg_Bookings_PreventBookedOverlap |

---

## API Routes

| Endpoint | Method | Xác thực | Mô tả |
|----------|--------|---------|-------|
| `/api/health` | GET | Public | Health check |
| `/api/auth/login` | POST | Public | Đăng nhập |
| `/api/auth/me` | GET | Session | Kiểm tra phiên |
| `/api/auth/logout` | POST | Session | Đăng xuất |
| `/api/courts/available` | GET | Public | Tìm sân trống |
| `/api/bookings` | POST | CUSTOMER | Tạo booking |
| `/api/bookings/estimate` | GET | CUSTOMER | Chi phí dự kiến |
| `/api/bookings/mine` | GET | CUSTOMER | Lịch sử đặt sân |
| `/api/bookings/:id/cancel` | POST | CUSTOMER | Hủy booking |
| `/api/manager/bookings` | GET | MANAGER/CM | Danh sách booking |
| `/api/manager/bookings/:id/approve` | POST | MANAGER/CM | Duyệt booking |
| `/api/manager/bookings/:id/reject` | POST | MANAGER/CM | Từ chối booking |
| `/api/manager/bookings/:id/cancel` | POST | MANAGER/CM | Hủy booking |
| `/api/manager/bookings/:id/complete` | POST | MANAGER/CM | Hoàn thành booking |
| `/api/manager/courts` | GET | MANAGER/CM | Danh sách sân |
| `/api/manager/courts` | POST | MANAGER/CM | Tạo sân |
| `/api/manager/courts/:id` | PUT | MANAGER/CM | Cập nhật sân |
| `/api/manager/courts/:id/deactivate` | POST | MANAGER/CM | Ngừng hoạt động sân |
| `/api/manager/dashboard` | GET | MANAGER/CM | Dashboard |
| `/api/notifications` | GET | Auth | Thông báo |
| `/api/notifications/:id/read` | POST | Auth | Đánh dấu đã đọc |

---

## Frontend Routes

| Path | Vai trò | Màn hình |
|------|---------|---------|
| `/login` | Guest | Đăng nhập |
| `/courts` | Guest + CUSTOMER | Tìm kiếm sân |
| `/booking/:courtId` | CUSTOMER | Chi tiết & tạo booking |
| `/my-bookings` | CUSTOMER | Lịch sử đặt sân |
| `/notifications` | CUSTOMER | Thông báo |
| `/manager/dashboard` | MANAGER / COURT_MANAGER | Bảng điều khiển |
| `/manager/bookings` | MANAGER / COURT_MANAGER | Quản lý booking |
| `/manager/courts` | MANAGER / COURT_MANAGER | Quản lý sân |
| `/manager/notifications` | MANAGER / COURT_MANAGER | Thông báo |

Không có `/register`, `/admin/*`, `/courtmanager/*`.

---

## Error Handling

API sử dụng envelope lỗi chuẩn:

```json
{
  "error": {
    "code": 50035,
    "message": "Không thể approve: booking overlap với một BOOKED khác trên cùng sân."
  }
}
```

- `code`: SQL error number từ THROW (null nếu lỗi không xác định)
- `message`: Thông báo an toàn tiếng Việt (mapped từ `spError.ts`)
- Chi tiết kỹ thuật chỉ ghi log server-side, KHÔNG gửi về client
- Xung đột trạng thái/trùng lặp: HTTP 409
- SQL Server deadlock: error 1205 → HTTP 409 + hướng dẫn thử lại

---

## Wall-clock DateTime

Booking `StartTime` / `EndTime` sử dụng `DATETIME2(0)` trên SQL Server,
được xử lý như **giờ wall-clock** (giờ địa phương), KHÔNG phải UTC.

Ví dụ:
- Trình duyệt chọn: `2026-08-20 18:00`
- SQL Server lưu: `2026-08-20 18:00:00`

Không có chuyển đổi timezone. Server chuyển đổi an toàn trước khi truyền
cho driver SQL để đảm bảo digits wall-clock được bảo toàn.

---

*Không có Phase 2.13 — đây là phiên bản cuối cùng.*
