# TÀI LIỆU MỞ RỘNG SẢN PHẨM (PRODUCT EXTENSION)
## Hệ Thống Quản Lý Đặt Sân Cầu Lông (BadmintonCourtManagement)

Tài liệu này phân định ranh giới kiến trúc rõ ràng giữa **Phần Cốt Lõi Khóa Học (Course Core)** và **Phần Mở Rộng Sản Phẩm (Product Extension)** nhằm phục vụ mục đích thẩm định và báo cáo đề tài.

---

## 1. Phân định Ranh giới Kiến trúc

`
                      HỆ THỐNG BADMINTON PRO (PRODUCT-EXTENDED)
                                       │
            ┌──────────────────────────┴──────────────────────────┐
            ▼                                                     ▼
   COURSE CORE (Bắt buộc môn học)                       PRODUCT EXTENSION (Nhóm mở rộng)
   ─────────────────────────────                       ─────────────────────────────────
   • 5 Bảng cốt lõi                                     • 4 Cột mở rộng bảng Users (Email, Reset)
   • 4 Views cốt lõi                                    • 1 Check Constraint (CK_Users_Email_Format)
   • 2 Functions (fn_CalculateBookingCost,              • 1 Index (IX_Users_Email)
                  fn_IsCourtAvailable)                  • 3 Stored Procedures mở rộng:
   • 14 Stored Procedures cốt lõi                         - sp_Register (bắt buộc Email, sp_getapplock)
   • 6 Triggers ràng buộc trạng thái & overlap            - sp_RequestPasswordReset (OTP safe BIGINT)
   • Mô hình bảo mật Option A (SESSION_CONTEXT)           - sp_ResetPassword (lockout & single-use)
   • Cơ chế Dedicated Connection (SessionDb)            • Dịch vụ SMTP Mailer gửi mã OTP
   • 4 Kịch bản Transaction Anomaly (Lost Update,       • Rate Limiting mở rộng cho Auth endpoints
     Dirty Read, Non-repeatable Read, Phantom Read)     • Giao diện /register và /forgot-password
   • Deadlock 1205 & Thứ tự khóa (Court -> Booking)     • Bộ Auth Validators độc lập & Unit Tests
`

---

## 2. Danh mục Đối tượng Database chi tiết (Database Isolation: BadmintonCourtManagement_ProductTest)

### 2.1. Đối tượng Cốt lõi Môn học (Course Core - 100% Nguyên bản & Đã Verified)

| Loại | Số lượng | Chi tiết |
|---|---|---|
| **Bảng (Tables)** | **5** | Users, Courts, Bookings, ActivityLogs, Notifications |
| **Khung nhìn (Views)** | **4** | w_AvailableCourts, w_BookingHistory, w_AdminDashboard, w_AllBookings |
| **Hàm (Functions)** | **2** | n_CalculateBookingCost, n_IsCourtAvailable |
| **Thủ tục (Stored Procedures)** | **14** | sp_Login, sp_BookCourt, sp_ApproveBooking, sp_RejectBooking, sp_CancelBooking, sp_CompleteBooking, sp_CreateCourt, sp_UpdateCourt, sp_DeactivateCourt, sp_GetAvailableCourts, sp_GetMyBookings, sp_GetNotifications, sp_MarkNotificationRead, sp_GetDashboard |
| **Triggers** | **6** | 	rg_Bookings_AuditInsert, 	rg_Bookings_AuditStatus, 	rg_Bookings_NotifyInsert, 	rg_Bookings_NotifyStatus, 	rg_Bookings_ValidateState, 	rg_Bookings_PreventBookedOverlap |

*Tổng số Stored Procedures:* **14 (Core) + 3 (Extension) = 17 Stored Procedures**.

---

### 2.2. Đối tượng Mở rộng Sản phẩm (Product Extension Objects)

| Đối tượng | Mục đích | Ràng buộc & Bảo mật |
|---|---|---|
| Users.Email | Lưu trữ email bắt buộc phục vụ đăng ký và nhận OTP khôi phục mật khẩu. | NVARCHAR(254) NULL, format check CK_Users_Email_Format |
| Users.PasswordResetCodeHash | Lưu hash SHA-256 mã OTP khôi phục mật khẩu (cms-reset\|<code>). | VARBINARY(64) NULL, không lưu plaintext |
| Users.PasswordResetExpiresAt | Thời điểm hết hạn của mã OTP (mặc định 10 phút). | DATETIME2(0) NULL |
| Users.PasswordResetAttempts | Đếm số lần nhập sai mã OTP (tối đa 5 lần). | TINYINT NOT NULL DEFAULT 0 |
| IX_Users_Email | Index hỗ trợ tra cứu người dùng qua email. | Non-clustered standard index |
| dbo.sp_Register | Đăng ký tài khoản CUSTOMER mới từ giao diện web (bắt buộc Email). | Registration email uniqueness được serialization trong dbo.sp_Register bằng transaction-scoped sys.sp_getapplock (khóa tài nguyên BCMS_Register_Email_<email>), bảo đảm an toàn tương tranh tuyệt đối mà không phá cấu trúc 5 bảng lõi. |
| dbo.sp_RequestPasswordReset | Sinh mã OTP 6 chữ số ngẫu nhiên an toàn (sử dụng toán tử 64-bit tránh tràn số ABS INT_MIN). | Chống account enumeration (lỗi 50210); yêu cầu mã mới sẽ vô hiệu hóa mã cũ. |
| dbo.sp_ResetPassword | Kiểm tra OTP, số lần thử (< 5), thời hạn và cập nhật mật khẩu mới. | Đổi mật khẩu thành công sẽ hủy hoàn toàn mã reset (Single-use, chống replay). |

---

## 3. Trạng thái Dịch vụ Email (SMTP Status)

- **DEV FALLBACK**: **PASS** (Trong môi trường phát triển / kiểm thử khi chưa cấu hình SMTP máy chủ thật, mã OTP 6 chữ số được trả về trong response phát triển để kiểm thử tự động).
- **LIVE SMTP**: **NOT RUN** (Hệ thống đã tích hợp sẵn transport 
odemailer với cấu hình linh hoạt qua biến môi trường SMTP_HOST, SMTP_PORT, SMTP_USER, SMTP_PASSWORD; chưa kích hoạt gửi thư thực tế trên máy chủ SMTP ngoài).

---

## 4. Bảng Kiểm Thử Toàn Diện (Test Evidence Matrix)

| Hạng mục kiểm thử | Công cụ / Script | Kết quả | Chi tiết |
|---|---|---|---|
| **Course Functional Tests** | database/09_tests_functional.sql | **47/47 PASS** | Toàn bộ 21 SP tests, 3 TX tests, 4 Trigger tests, 5 Table invariants, View & Function tests đạt 100%. |
| **Audit Actor Regression** | 	ests/regression/audit_actor.sql | **PASS** | Xác nhận ActivityLogs ghi đúng actor phiên đăng nhập (Manager, Customer). |
| **Product Extension Tests** | 	ests/regression/auth_features.sql | **16/16 PASS** | Kiểm thử đăng ký bắt buộc email, chống trùng lặp, hash OTP, chống tràn số, chống enumeration, khóa 5 lần sai, hết hạn 10p, single-use, đổi mật khẩu và vô hiệu mật khẩu cũ. |
| **Real Concurrent Email (CC-EMAIL-01)** | 	ests/concurrency/register_email_session_A.sql & _B.sql | **PASS** | 2 phiên chạy đồng thời cùng Email: 1 phiên thành công, 1 phiên bị chặn lỗi 50204 qua sp_getapplock, COUNT(*) = 1. |
| **Real Backup / Restore Verification** | 	ests/regression/backup_restore_runtime.sql | **PASS** | BACKUP DATABASE ➔ RESTORE VERIFYONLY ➔ RESTORE sang BadmintonCourtManagement_ProductTest_RestoreVerify. So khớp 100% 5 bảng lõi và 5/4/2/17/6 objects. |
| **Transaction Anomalies (Demo)** | database/10_tests_transactions.sql | **PASS** | Kiểm chứng cơ chế ngăn ngừa Phantom Read bằng mức cô lập SERIALIZABLE. |
| **Concurrency CC-01** | database/11_*.sql & database/12_*.sql | **PASS** | Approve tương tranh trên 2 booking overlap -> đúng 1 BOOKED, 1 bị từ chối; không lost update. |
| **Deadlock DL-01/DL-02/DL-03** | database/13_*.sql & database/14_*.sql | **PASS** | Bắt lỗi 1205 deadlock victim và chứng minh lock ordering Court -> Booking giải quyết triệt để deadlock. |
| **Lost Update Concurrency** | 	ests/concurrency/lost_update_*.sql | **PASS** | Unsafe mất update (+20k), Fixed với UPDLOCK thực hiện tuần tự (+70k). |
| **Dirty Read Concurrency** | 	ests/concurrency/dirty_read_*.sql | **PASS** | Unsafe đọc dirty 200k, Fixed với READ COMMITTED chặn đọc giá trị uncommitted. |
| **Non-repeatable Read** | 	ests/concurrency/nonrepeatable_*.sql | **PASS** | Unsafe đọc 100k rồi 120k, Fixed với REPEATABLE READ giữ S-lock ổn định 100k. |
| **Phantom Read Concurrency** | 	ests/concurrency/phantom_*.sql | **PASS** | Unsafe tăng số dòng 0 -> 1, Fixed với SERIALIZABLE range lock giữ vững 0 -> 0. |
| **TypeScript Typecheck** | 	sc (Server + Client) | **0 errors** | Kiểm tra tĩnh toàn bộ mã nguồn Server & Client. |
| **ESLint Static Analysis** | eslint . --max-warnings=0 | **0 warnings / 0 errors** | Tuân thủ toàn bộ quy chuẩn code linting. |
| **App Unit Tests** | 
ode --import tsx --test tests/*.test.ts | **16/16 PASS** | Kiểm thử validator, rate limiter, session db, spError mapping, time parser. |
| **Production Build** | 
pm run build | **PASS** | Build server TSC và Client Vite thành công (dist bundle 264 kB). |
| **Live E2E Smoke Test** | 
ode dist/server/index.js --serve-client | **12/12 PASS** | Kiểm thử luồng thực tế trên DB cô lập: Health ➔ Missing Email Rejected (400) ➔ Valid Register ➔ Duplicate (409) ➔ Login ➔ Me ➔ Search Court ➔ Logout ➔ Forgot Password ➔ OTP Reset ➔ Re-login thành công. |

---

## 5. Báo cáo Thẩm định Giao diện (Visual Inspection - NOT AUTOMATED)

Các màn hình được kiểm tra tĩnh trên 3 ngưỡng kích thước:
- **Desktop (1440px)**: Bố cục lưới 3 cột cho danh sách sân, 4 thẻ KPI bảng điều khiển, Sidebar cố định 288px, Demo Drawer mở rộng 480px.
- **Laptop (1024px)**: Bố cục lưới 2 cột cho danh sách sân, 2 cột cho KPI, bảng quản lý cuộn ngang an toàn với tiêu đề cố định.
- **Mobile (~390px)**: Thanh điều hướng rút gọn với drawer menu trượt, thẻ sân và lịch sử đặt sân xếp chồng 1 cột, nút bấm toàn chiều rộng chuẩn cảm ứng (>44px).
- **Trang Xác thực (/login, /register, /forgot-password)**: Card nổi trung tâm với viền mềm mại, huy hiệu nổi, form helper và hiển thị thông báo lỗi/thành công rõ ràng.
