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
   • 4 Views                                            • 1 Check Constraint (CK_Users_Email_Format)
   • 2 Functions (fn_CalculateBookingCost,              • 1 Index (IX_Users_Email)
                  fn_IsCourtAvailable)                  • 3 Stored Procedures mở rộng:
   • 14 Stored Procedures cốt lõi                         - sp_Register
   • 6 Triggers ràng buộc trạng thái & overlap            - sp_RequestPasswordReset
   • Mô hình bảo mật Option A (SESSION_CONTEXT)           - sp_ResetPassword
   • Cơ chế Dedicated Connection (SessionDb)            • Dịch vụ SMTP Mailer gửi mã OTP
   • 4 Kịch bản Transaction Anomaly (Lost Update,       • Rate Limiting mở rộng cho Auth endpoints
     Dirty Read, Non-repeatable Read, Phantom Read)     • Giao diện /register và /forgot-password
   • Deadlock 1205 & Lock Ordering (Court -> Booking)   • Bộ Auth Validators độc lập & Unit Tests
`

---

## 2. Danh mục Đối tượng Database chi tiết

### 2.1. Đối tượng Cốt lõi Môn học (Course Core - 100% Nguyên bản & Đã Verified)

| Loại | Số lượng | Chi tiết |
|---|---|---|
| **Bảng (Tables)** | **5** | Users, Courts, Bookings, ActivityLogs, Notifications |
| **Khung nhìn (Views)** | **4** | w_AvailableCourts, w_BookingHistory, w_AdminDashboard, w_AllBookings |
| **Hàm (Functions)** | **2** | n_CalculateBookingCost, n_IsCourtAvailable |
| **Thủ tục (Stored Procedures)** | **14** | sp_Login, sp_BookCourt, sp_ApproveBooking, sp_RejectBooking, sp_CancelBooking, sp_CompleteBooking, sp_CreateCourt, sp_UpdateCourt, sp_DeactivateCourt, sp_GetAvailableCourts, sp_GetMyBookings, sp_GetNotifications, sp_MarkNotificationRead, sp_GetDashboard |
| **Triggers** | **6** | 	rg_Bookings_AuditInsert, 	rg_Bookings_AuditStatus, 	rg_Bookings_NotifyInsert, 	rg_Bookings_NotifyStatus, 	rg_Bookings_ValidateState, 	rg_Bookings_PreventBookedOverlap |

*Lưu ý bảo vệ đề tài:* Toàn bộ 14 Stored Procedures cốt lõi giữ nguyên 100% chữ ký tham số, logic khóa Court -> Booking, xử lý tương tranh và cơ chế kiểm soát phiên SESSION_CONTEXT.

---

### 2.2. Đối tượng Mở rộng Sản phẩm (Product Extension Objects)

| Đối tượng | Mục đích | Ràng buộc & Bảo mật |
|---|---|---|
| Users.Email | Lưu trữ email phục vụ đăng ký và nhận OTP khôi phục mật khẩu. | NVARCHAR(254) NULL, format check CK_Users_Email_Format |
| Users.PasswordResetCodeHash | Lưu hash SHA-256 mã OTP khôi phục mật khẩu (cms-reset\|<code>). | VARBINARY(64) NULL, không lưu plaintext |
| Users.PasswordResetExpiresAt | Thời điểm hết hạn của mã OTP (mặc định 10 phút). | DATETIME2(0) NULL |
| Users.PasswordResetAttempts | Đếm số lần nhập sai mã OTP (tối đa 5 lần). | TINYINT NOT NULL DEFAULT 0 |
| IX_Users_Email | Index hỗ trợ tra cứu người dùng qua email. | Non-clustered standard index |
| dbo.sp_Register | Đăng ký tài khoản CUSTOMER mới từ giao diện web. | Kiểm tra trùng lặp Username (50201), Phone (50202), Email (50204); mã hóa mật khẩu SHA2_256(N'bcms\|' + @Password). |
| dbo.sp_RequestPasswordReset | Sinh mã OTP 6 chữ số và lưu hash, chuẩn bị gửi email. | Chống account enumeration (lỗi 50210); sinh OTP qua CRYPT_GEN_RANDOM(4). |
| dbo.sp_ResetPassword | Kiểm tra OTP, số lần thử (< 5), thời hạn và cập nhật mật khẩu mới. | Đổi mật khẩu thành công sẽ hủy mã reset và xóa số lần thử. |

---

## 3. Các Luồng Nghiệp Vụ Mở Rộng

### 3.1. Luồng Đăng ký Khách hàng Mới (Customer Registration)
1. Người dùng mở trang /register, nhập thông tin (Tên đăng nhập, SĐT, Email, Mật khẩu, Xác nhận mật khẩu).
2. Frontend/Backend xác thực qua bộ validator chuẩn (uthValidation.ts).
3. Endpoint POST /api/auth/register (được bảo vệ bởi Rate Limiter) gọi dbo.sp_Register trên kết nối shared pool.
4. Tài khoản được tạo với vai trò CUSTOMER và kích hoạt sẵn (IsActive = 1).
5. Người dùng chuyển sang /login để đăng nhập.

### 3.2. Luồng Khôi phục Mật khẩu (Password Recovery Flow)
1. Người dùng mở trang /forgot-password, nhập Tên đăng nhập và Email.
2. Endpoint POST /api/auth/password/forgot gọi dbo.sp_RequestPasswordReset:
   - Nếu thông tin khớp: hệ thống sinh mã 6 số ngẫu nhiên, lưu hash với thời hạn 10 phút và gửi email qua SMTP (hoặc hiển thị mã dev trên môi trường local).
   - Nếu thông tin không khớp: hệ thống trả thông điệp chung (200 OK) để chống dò quét tài khoản (account enumeration).
3. Người dùng nhập mã OTP 6 chữ số và mật khẩu mới.
4. Endpoint POST /api/auth/password/reset gọi dbo.sp_ResetPassword:
   - Kiểm tra mã OTP: nếu sai, tăng số lần thử. Khi đạt 5 lần sai hoặc quá 10 phút, mã bị vô hiệu hóa.
   - Nếu đúng: cập nhật PasswordHash, xóa mã OTP và đặt lại số lần thử về 0.
5. Người dùng đăng nhập thành công với mật khẩu mới.

---

## 4. Bảo mật & Quy tắc An toàn

1. **Không can thiệp sp_Login**: sp_Login chỉ thực hiện đúng trách nhiệm đăng nhập và thiết lập SESSION_CONTEXT.
2. **Không lưu mã OTP dạng văn bản thuần**: Chỉ lưu trữ giá trị băm SHA2_256('bcms-reset|' + OTP).
3. **Dedicated Session Connection**: Mọi thao tác sau khi đăng nhập vẫn duy trì trên một kết nối SQL riêng biệt thuộc về web session, bảo vệ toàn vẹn SESSION_CONTEXT('UserId') và SESSION_CONTEXT('Role').
4. **Không lộ bí mật trong mã nguồn**: Cấu hình SMTP và Database Password nằm trong file .env (không đưa vào git).
