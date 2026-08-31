# PRODUCT EXTENSION PLAN — BadmintonCourtManagement

Tài liệu này xác định phạm vi, quyết định kiến trúc và lộ trình tích hợp an toàn các tính năng mở rộng sản phẩm từ teammate-work (commit 087aef3) vào nhánh product-extended dựa trên baseline chuẩn môn học main (commit 5dcfc13).

---

## 1. Audit thay đổi từ teammate-work

### 1.1. Các thay đổi ĐÁNG LẤY (Porting / Reimplementing)
1. **Luồng xác thực khách hàng mở rộng**:
   - Đăng ký tài khoản CUSTOMER mới (/register, sp_Register, POST /api/auth/register).
   - Quên mật khẩu qua email OTP (/forgot-password, sp_RequestPasswordReset, POST /api/auth/password/forgot).
   - Đặt lại mật khẩu (sp_ResetPassword, POST /api/auth/password/reset).
2. **Bảo mật & Validation**:
   - Bộ validation độc lập authValidation.ts (kiểm tra username, phone, email, password độ dài và định dạng).
   - Rate limiting cho các endpoint auth (/login, /register, /password/forgot, /password/reset) với bộ dọn dẹp bộ nhớ định kỳ.
   - Mã OTP được hash an toàn (SHA-256), có hạn 10 phút, giới hạn tối đa 5 lần thử sai, hủy sau khi dùng.
3. **Dịch vụ Email (SMTP Mailer)**:
   - Module passwordResetMail.ts sử dụng nodemailer gửi email OTP khôi phục mật khẩu.
   - Graceful fallback cho môi trường dev/local nếu chưa cấu hình SMTP (không làm crash hệ thống, trả OTP dev chỉ khi non-production).
4. **Cải tiến UI/UX**:
   - Layout xác thực hiện đại AuthPageLayout.tsx.
   - Nút bật/tắt hiển thị mật khẩu ở form đăng nhập/đăng ký.
   - Các màn hình đăng ký (RegisterPage.tsx), quên mật khẩu (ForgotPasswordPage.tsx).
   - Tinh chỉnh style, spacing, card shadows, responsive layout.

### 1.2. Các thay đổi KHÔNG LẤY (Rejected) và Lý do
1. **Thiết kế hack sp_Login @Action = ...**:
   - *Lý do*: Teammate gộp 4 hành động (LOGIN, REGISTER, REQUEST_RESET, RESET_PASSWORD) vào sp_Login. Điều này vi phạm hợp đồng cốt lõi 14 SPs của môn học và làm rối loạn cơ chế gán SESSION_CONTEXT.
   - *Giải pháp*: Giữ nguyên sp_Login chỉ làm nhiệm vụ đăng nhập. Tạo 3 Stored Procedures riêng biệt cho phần mở rộng: dbo.sp_Register, dbo.sp_RequestPasswordReset, dbo.sp_ResetPassword.
2. **Giao diện Trung Thu / Pixel Art toàn diện (festival.css, 1200+ dòng)**:
   - *Lý do*: Đổi toàn bộ màu sắc sang đỏ cam #b7442d, font Lora/Be Vietnam Pro, thay icon cầu lông bằng lồng đèn/mặt trăng. Điều này vi phạm AGENTS.md rule 10 (thương hiệu BadmintonPro teal #00796F, Hanken Grotesk, icon sports_badminton).
   - *Giải pháp*: Giữ chuẩn nhận diện BadmintonPro, chỉ lấy bố cục component hiện đại, animation mượt mà.
3. **Xóa bỏ các file chứng cứ evidence/final/*, docs/DEMO_RUNBOOK.md, tests/regression/audit_actor.sql**:
   - *Lý do*: Đây là các chứng cứ và kịch bản demo quan trọng của môn học đã được verified.
   - *Giải pháp*: Giữ nguyên toàn bộ evidence/, docs/DEMO_RUNBOOK.md, tests/regression/audit_actor.sql.
4. **Sửa đổi logic Stored Procedures cốt lõi trong database/06_procedures.sql**:
   - *Lý do*: Gây rủi ro hồi quy (regression) cho 47/47 functional tests và các test tương tranh.
   - *Giải pháp*: Giữ nguyên 14 SPs gốc trong database/06_procedures.sql. Các SP mở rộng được tổ chức thành file migration/extension riêng.

---

## 2. Danh mục File phân loại

| File | Hành động | Ghi chú |
|---|---|---|
| database/01..08 | GIỮ MAIN | 100% giữ nguyên định nghĩa cơ sở dữ liệu khóa môn |
| database/09..15 | GIỮ MAIN | Toàn bộ test và demo tương tranh của môn học |
| database/16_product_extension.sql | TẠO MỚI | Migration thêm cột Users & 3 SP mở rộng |
| app/src/server/routes/auth.ts | PORT CÓ CHỌN LỌC | Giữ cơ chế session/login của main, thêm register, forgot, reset |
| app/src/server/authValidation.ts | PORT | Bộ validator chuẩn |
| app/src/server/mail/passwordResetMail.ts | PORT | Gửi email OTP |
| app/src/server/middleware/rateLimit.ts | PORT CÓ CHỌN LỌC | Mở rộng rate limit cho auth endpoints |
| app/src/server/config.ts | PORT CÓ CHỌN LỌC | Bổ sung biến môi trường SMTP |
| app/src/frontend/components/AuthPageLayout.tsx | PORT CÓ ĐIỀU CHỈNH | Thiết kế layout auth chuẩn BadmintonPro teal |
| app/src/frontend/pages/LoginPage.tsx | PORT CÓ ĐIỀU CHỈNH | Giữ login logic main, thêm show/hide password, link register/forgot |
| app/src/frontend/pages/RegisterPage.tsx | PORT | Màn hình đăng ký |
| app/src/frontend/pages/ForgotPasswordPage.tsx | PORT | Màn hình khôi phục mật khẩu |
| app/src/frontend/App.tsx | MODIFY | Đăng ký route /register, /forgot-password |
| app/src/frontend/api/client.ts | PORT CÓ CHỌN LỌC | Bổ sung API client functions |
| app/src/frontend/styles/components.css | PORT CÓ CHỌN LỌC | Style cho auth form |
| app/tests/* | PORT & EXPAND | Thêm unit test authValidation, rateLimit, mailer |
| docs/PRODUCT_EXTENSION.md | TẠO MỚI | Tài liệu phân định Course Core vs Product Extension |

---

## 3. Kế hoạch Database Migration

Tạo script database/16_product_extension.sql bao gồm:
1. **Mở rộng bảng Users**:
   - Email NVARCHAR(254) NULL
   - PasswordResetCodeHash VARBINARY(64) NULL
   - PasswordResetExpiresAt DATETIME2(0) NULL
   - PasswordResetAttempts TINYINT NOT NULL DEFAULT 0
   - Check constraint CK_Users_Email_Format
   - Filtered unique index UQ_Users_Email_NotNull
2. **Seed Email cho các user mẫu**:
   - manager@badmintonpro.local, courtmanager1@badmintonpro.local, v.v.
3. **Tạo 3 Stored Procedures mở rộng**:
   - dbo.sp_Register
   - dbo.sp_RequestPasswordReset
   - dbo.sp_ResetPassword
4. **Phân quyền bảo mật**:
   - GRANT EXECUTE ON dbo.sp_Register TO bcm_app_role;
   - GRANT EXECUTE ON dbo.sp_RequestPasswordReset TO bcm_app_role;
   - GRANT EXECUTE ON dbo.sp_ResetPassword TO bcm_app_role;

---

## 4. Kế hoạch Kiểm thử & Hồi quy

Mỗi phase thực hiện xong phải chạy:
1. **Frontend / Backend Unit & Build Check**:
   - npm run typecheck
   - npm run lint
   - npm test
   - npm run build
2. **Database Functional & Concurrency Regression**:
   - database/09_tests_functional.sql (47/47 PASS)
   - database/10_tests_transactions.sql
   - database/11 & 12 (Concurrency)
   - database/13 & 14 (Deadlock)
   - database/15 (Backup/Restore)
   - tests/regression/audit_actor.sql
3. **Product Flow Verification**:
   - Register user mới -> Đăng nhập bằng user mới -> Đặt sân -> Xem lịch sử
   - Forgot password -> Nhận mã OTP -> Đổi mật khẩu -> Đăng nhập bằng mật khẩu mới
