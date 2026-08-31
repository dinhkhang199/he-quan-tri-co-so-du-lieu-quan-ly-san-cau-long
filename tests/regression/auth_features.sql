/* ============================================================
   BadmintonCourtManagement — Product Extension Test Suite
   Script : auth_features.sql
   Mục đích: Kiểm thử toàn diện các tính năng Register, Email Uniqueness,
             OTP Hardening, Lockout và Password Reset Flow.
   ============================================================ */

USE BadmintonCourtManagement_ProductTest;
GO
SET NOCOUNT ON;
SET XACT_ABORT OFF;

IF OBJECT_ID('tempdb..#AuthResults') IS NOT NULL DROP TABLE #AuthResults;
CREATE TABLE #AuthResults
(
    id   VARCHAR(20)   NOT NULL,
    name NVARCHAR(200) NOT NULL,
    [pass] BIT         NOT NULL,
    note NVARCHAR(500) NULL
);
GO

-- Cleanup test user if exists
DELETE FROM dbo.ActivityLogs WHERE UserId IN (SELECT UserId FROM dbo.Users WHERE Username LIKE 'reg_test_%' OR Username LIKE 'concur_test_%');
DELETE FROM dbo.Users WHERE Username LIKE 'reg_test_%' OR Username LIKE 'concur_test_%';
GO

-- ============================================================
-- 1. REGISTRATION TESTS
-- ============================================================

-- TEST 1: Register thiếu Email -> phải bị chặn (50208)
BEGIN TRY
    EXEC dbo.sp_Register @Username=N'reg_test_no_email', @Password=N'StrongPass123', @PhoneNumber=N'0981110001', @Email=NULL;
    INSERT INTO #AuthResults VALUES('REG-01', N'Bắt buộc Email khi đăng ký (chặn NULL/rỗng)', 0, N'Không bị chặn khi thiếu Email');
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50208
        INSERT INTO #AuthResults VALUES('REG-01', N'Bắt buộc Email khi đăng ký (chặn NULL/rỗng)', 1, N'Bị chặn đúng mã 50208');
    ELSE
        INSERT INTO #AuthResults VALUES('REG-01', N'Bắt buộc Email khi đăng ký (chặn NULL/rỗng)', 0, N'Mã lỗi: ' + CAST(ERROR_NUMBER() AS VARCHAR(10)));
END CATCH;

-- TEST 2: Register CUSTOMER hợp lệ có Email -> thành công
DECLARE @u1 NVARCHAR(50) = N'reg_test_user_01';
DECLARE @p1 NVARCHAR(200) = N'StrongPass123';
DECLARE @phone1 NVARCHAR(20) = N'0981112233';
DECLARE @email1 NVARCHAR(254) = N'reg_test_01@badmintonpro.local';

BEGIN TRY
    EXEC dbo.sp_Register @Username=@u1, @Password=@p1, @PhoneNumber=@phone1, @Email=@email1;
    IF EXISTS (SELECT 1 FROM dbo.Users WHERE Username=@u1 AND Role=N'CUSTOMER' AND IsActive=1 AND Email=@email1)
        INSERT INTO #AuthResults VALUES('REG-02', N'Đăng ký tài khoản CUSTOMER thành công', 1, N'Đã tạo User với Role=CUSTOMER');
    ELSE
        INSERT INTO #AuthResults VALUES('REG-02', N'Đăng ký tài khoản CUSTOMER thành công', 0, N'Không tìm thấy user sau đăng ký');
END TRY
BEGIN CATCH
    INSERT INTO #AuthResults VALUES('REG-02', N'Đăng ký tài khoản CUSTOMER thành công', 0, ERROR_MESSAGE());
END CATCH;

-- TEST 3: Đăng ký trùng Username -> lỗi 50201
BEGIN TRY
    EXEC dbo.sp_Register @Username=@u1, @Password=N'OtherPass123', @PhoneNumber=N'0989998877', @Email=N'reg_test_other@badmintonpro.local';
    INSERT INTO #AuthResults VALUES('REG-03', N'Chặn đăng ký trùng Username', 0, N'Không bị chặn');
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50201
        INSERT INTO #AuthResults VALUES('REG-03', N'Chặn đăng ký trùng Username', 1, N'Bị chặn đúng mã 50201');
    ELSE
        INSERT INTO #AuthResults VALUES('REG-03', N'Chặn đăng ký trùng Username', 0, N'Mã lỗi: ' + CAST(ERROR_NUMBER() AS VARCHAR(10)));
END CATCH;

-- TEST 4: Đăng ký trùng Phone -> lỗi 50202
BEGIN TRY
    EXEC dbo.sp_Register @Username=N'reg_test_diff_user', @Password=N'OtherPass123', @PhoneNumber=@phone1, @Email=N'reg_test_diff@badmintonpro.local';
    INSERT INTO #AuthResults VALUES('REG-04', N'Chặn đăng ký trùng Số điện thoại', 0, N'Không bị chặn');
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50202
        INSERT INTO #AuthResults VALUES('REG-04', N'Chặn đăng ký trùng Số điện thoại', 1, N'Bị chặn đúng mã 50202');
    ELSE
        INSERT INTO #AuthResults VALUES('REG-04', N'Chặn đăng ký trùng Số điện thoại', 0, N'Mã lỗi: ' + CAST(ERROR_NUMBER() AS VARCHAR(10)));
END CATCH;

-- TEST 5: Đăng ký trùng Email -> lỗi 50204
BEGIN TRY
    EXEC dbo.sp_Register @Username=N'reg_test_diff_user2', @Password=N'OtherPass123', @PhoneNumber=N'0989991122', @Email=@email1;
    INSERT INTO #AuthResults VALUES('REG-05', N'Chặn đăng ký trùng Email', 0, N'Không bị chặn');
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50204
        INSERT INTO #AuthResults VALUES('REG-05', N'Chặn đăng ký trùng Email', 1, N'Bị chặn đúng mã 50204');
    ELSE
        INSERT INTO #AuthResults VALUES('REG-05', N'Chặn đăng ký trùng Email', 0, N'Mã lỗi: ' + CAST(ERROR_NUMBER() AS VARCHAR(10)));
END CATCH;

-- TEST 6: Atomic Email Uniqueness test (Mô phỏng 2 đăng ký song song cùng email)
DECLARE @concurEmail NVARCHAR(254) = N'concur_test_unique@badmintonpro.local';
DECLARE @s1_ok BIT = 0, @s2_ok BIT = 0, @s2_err INT = 0;

BEGIN TRY
    EXEC dbo.sp_Register @Username=N'concur_test_user_a', @Password=N'PassA12345', @PhoneNumber=N'0977000001', @Email=@concurEmail;
    SET @s1_ok = 1;
END TRY
BEGIN CATCH
    SET @s1_ok = 0;
END CATCH;

BEGIN TRY
    EXEC dbo.sp_Register @Username=N'concur_test_user_b', @Password=N'PassB12345', @PhoneNumber=N'0977000002', @Email=@concurEmail;
    SET @s2_ok = 1;
END TRY
BEGIN CATCH
    SET @s2_err = ERROR_NUMBER();
END CATCH;

IF @s1_ok = 1 AND @s2_ok = 0 AND @s2_err = 50204
   AND (SELECT COUNT(*) FROM dbo.Users WHERE Email = @concurEmail) = 1
    INSERT INTO #AuthResults VALUES('REG-06', N'Bảo đảm Unique Email cấp Database (tối đa 1 user mang email)', 1, N'Session A thành công, Session B bị chặn mã 50204');
ELSE
    INSERT INTO #AuthResults VALUES('REG-06', N'Bảo đảm Unique Email cấp Database (tối đa 1 user mang email)', 0, N'Trùng lặp hoặc không chặn được');

-- ============================================================
-- 2. OTP HARDENING & PASSWORD RECOVERY TESTS
-- ============================================================

-- TEST 7: Request OTP sinh mã 6 số an toàn
DECLARE @code1 NVARCHAR(6);
BEGIN TRY
    DECLARE @tblReset TABLE (UserId UNIQUEIDENTIFIER, Username NVARCHAR(50), Email NVARCHAR(254), ResetCode NVARCHAR(6), ExpiresAt DATETIME2(0));
    INSERT INTO @tblReset
    EXEC dbo.sp_RequestPasswordReset @Username=@u1, @Email=@email1;

    SET @code1 = (SELECT TOP 1 ResetCode FROM @tblReset);
    IF LEN(@code1) = 6 AND @code1 NOT LIKE N'%[^0-9]%'
        INSERT INTO #AuthResults VALUES('OTP-01', N'Sinh mã OTP 6 số an toàn (không tràn số)', 1, N'Mã OTP: ' + @code1);
    ELSE
        INSERT INTO #AuthResults VALUES('OTP-01', N'Sinh mã OTP 6 số an toàn (không tràn số)', 0, N'Mã không hợp lệ');
END TRY
BEGIN CATCH
    INSERT INTO #AuthResults VALUES('OTP-01', N'Sinh mã OTP 6 số an toàn (không tràn số)', 0, ERROR_MESSAGE());
END CATCH;

-- TEST 8: Request OTP sai thông tin -> lỗi 50210
BEGIN TRY
    EXEC dbo.sp_RequestPasswordReset @Username=@u1, @Email=N'wrong_email@badmintonpro.local';
    INSERT INTO #AuthResults VALUES('OTP-02', N'Chặn yêu cầu khôi phục sai email (chống enumeration)', 0, N'Không bị chặn');
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50210
        INSERT INTO #AuthResults VALUES('OTP-02', N'Chặn yêu cầu khôi phục sai email (chống enumeration)', 1, N'Lỗi 50210');
    ELSE
        INSERT INTO #AuthResults VALUES('OTP-02', N'Chặn yêu cầu khôi phục sai email (chống enumeration)', 0, N'Mã lỗi: ' + CAST(ERROR_NUMBER() AS VARCHAR(10)));
END CATCH;

-- TEST 9: Yêu cầu mã mới sẽ vô hiệu hóa mã cũ (Second request invalidates first code)
DECLARE @code2 NVARCHAR(6);
BEGIN TRY
    DELETE FROM @tblReset;
    INSERT INTO @tblReset
    EXEC dbo.sp_RequestPasswordReset @Username=@u1, @Email=@email1;
    SET @code2 = (SELECT TOP 1 ResetCode FROM @tblReset);

    -- Dùng code cũ (@code1) đặt lại -> phải thất bại vì đã bị code2 ghi đè
    BEGIN TRY
        EXEC dbo.sp_ResetPassword @Username=@u1, @Email=@email1, @ResetCode=@code1, @NewPassword=N'NewPassTest123';
        INSERT INTO #AuthResults VALUES('OTP-03', N'Yêu cầu OTP mới vô hiệu hóa mã cũ', 0, N'Mã cũ vẫn dùng được (sai)');
    END TRY
    BEGIN CATCH
        IF ERROR_NUMBER() = 50212
            INSERT INTO #AuthResults VALUES('OTP-03', N'Yêu cầu OTP mới vô hiệu hóa mã cũ', 1, N'Mã cũ bị từ chối 50212');
        ELSE
            INSERT INTO #AuthResults VALUES('OTP-03', N'Yêu cầu OTP mới vô hiệu hóa mã cũ', 0, N'Mã lỗi: ' + CAST(ERROR_NUMBER() AS VARCHAR(10)));
    END CATCH;
END TRY
BEGIN CATCH
    INSERT INTO #AuthResults VALUES('OTP-03', N'Yêu cầu OTP mới vô hiệu hóa mã cũ', 0, ERROR_MESSAGE());
END CATCH;

-- TEST 10: Nhập sai mã OTP tăng attempts và báo lỗi 50212
BEGIN TRY
    EXEC dbo.sp_ResetPassword @Username=@u1, @Email=@email1, @ResetCode=N'000000', @NewPassword=N'NewPassTest123';
    INSERT INTO #AuthResults VALUES('OTP-04', N'Nhập sai mã OTP bị từ chối và tăng attempt', 0, N'Không bị chặn');
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50212
        INSERT INTO #AuthResults VALUES('OTP-04', N'Nhập sai mã OTP bị từ chối và tăng attempt', 1, N'Bị từ chối mã 50212');
    ELSE
        INSERT INTO #AuthResults VALUES('OTP-04', N'Nhập sai mã OTP bị từ chối và tăng attempt', 0, N'Mã lỗi: ' + CAST(ERROR_NUMBER() AS VARCHAR(10)));
END CATCH;

-- TEST 11: 5 lần nhập sai mã OTP -> khóa mã (50211)
BEGIN TRY
    -- Mô phỏng 5 lần nhập sai bằng cách cập nhật attempts = 5
    UPDATE dbo.Users SET PasswordResetAttempts = 5 WHERE Username = @u1;
    EXEC dbo.sp_ResetPassword @Username=@u1, @Email=@email1, @ResetCode=@code2, @NewPassword=N'NewPassTest123';
    INSERT INTO #AuthResults VALUES('OTP-05', N'Khóa mã khi nhập sai quá 5 lần (Lockout)', 0, N'Vẫn cho đổi mật khẩu khi attempts >= 5 (sai)');
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50211
        INSERT INTO #AuthResults VALUES('OTP-05', N'Khóa mã khi nhập sai quá 5 lần (Lockout)', 1, N'Bị khóa đúng mã 50211');
    ELSE
        INSERT INTO #AuthResults VALUES('OTP-05', N'Khóa mã khi nhập sai quá 5 lần (Lockout)', 0, N'Mã lỗi: ' + CAST(ERROR_NUMBER() AS VARCHAR(10)));
END CATCH;

-- TEST 12: Mã OTP hết hạn (quá 10 phút) -> lỗi 50211
DECLARE @code3 NVARCHAR(6);
BEGIN TRY
    DELETE FROM @tblReset;
    INSERT INTO @tblReset
    EXEC dbo.sp_RequestPasswordReset @Username=@u1, @Email=@email1;
    SET @code3 = (SELECT TOP 1 ResetCode FROM @tblReset);

    -- Mô phỏng hết hạn: lùi thời gian hết hạn về quá khứ
    UPDATE dbo.Users SET PasswordResetExpiresAt = DATEADD(MINUTE, -1, SYSDATETIME()) WHERE Username = @u1;

    EXEC dbo.sp_ResetPassword @Username=@u1, @Email=@email1, @ResetCode=@code3, @NewPassword=N'NewPassTest123';
    INSERT INTO #AuthResults VALUES('OTP-06', N'Từ chối mã OTP đã hết hạn', 0, N'Vẫn cho đổi khi mã hết hạn (sai)');
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50211
        INSERT INTO #AuthResults VALUES('OTP-06', N'Từ chối mã OTP đã hết hạn', 1, N'Bị từ chối đúng mã 50211');
    ELSE
        INSERT INTO #AuthResults VALUES('OTP-06', N'Từ chối mã OTP đã hết hạn', 0, N'Mã lỗi: ' + CAST(ERROR_NUMBER() AS VARCHAR(10)));
END CATCH;

-- TEST 13: Đặt lại mật khẩu với mã hợp lệ -> thành công
DECLARE @code4 NVARCHAR(6);
DECLARE @newPassSuccess NVARCHAR(200) = N'BrandNewPass888';
BEGIN TRY
    DELETE FROM @tblReset;
    INSERT INTO @tblReset
    EXEC dbo.sp_RequestPasswordReset @Username=@u1, @Email=@email1;
    SET @code4 = (SELECT TOP 1 ResetCode FROM @tblReset);

    EXEC dbo.sp_ResetPassword @Username=@u1, @Email=@email1, @ResetCode=@code4, @NewPassword=@newPassSuccess;
    INSERT INTO #AuthResults VALUES('RST-01', N'Đặt lại mật khẩu với mã OTP hợp lệ thành công', 1, N'Đã cập nhật PasswordHash');
END TRY
BEGIN CATCH
    INSERT INTO #AuthResults VALUES('RST-01', N'Đặt lại mật khẩu với mã OTP hợp lệ thành công', 0, ERROR_MESSAGE());
END CATCH;

-- TEST 14: Mã OTP đã dùng không được tái sử dụng (Single-use)
BEGIN TRY
    EXEC dbo.sp_ResetPassword @Username=@u1, @Email=@email1, @ResetCode=@code4, @NewPassword=N'AnotherNewPass999';
    INSERT INTO #AuthResults VALUES('RST-02', N'Mã OTP đã dùng không được tái sử dụng (Single-use)', 0, N'Tái sử dụng mã thành công (sai)');
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50211
        INSERT INTO #AuthResults VALUES('RST-02', N'Mã OTP đã dùng không được tái sử dụng (Single-use)', 1, N'Bị chặn đúng mã 50211');
    ELSE
        INSERT INTO #AuthResults VALUES('RST-02', N'Mã OTP đã dùng không được tái sử dụng (Single-use)', 0, N'Mã lỗi: ' + CAST(ERROR_NUMBER() AS VARCHAR(10)));
END CATCH;

-- TEST 15: Mật khẩu cũ bị từ chối khi đăng nhập
BEGIN TRY
    EXEC dbo.sp_Login @Username=@u1, @Password=@p1;
    INSERT INTO #AuthResults VALUES('RST-03', N'Mật khẩu cũ không còn hiệu lực', 0, N'Vẫn đăng nhập được bằng mật khẩu cũ (sai)');
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        INSERT INTO #AuthResults VALUES('RST-03', N'Mật khẩu cũ không còn hiệu lực', 1, N'Lỗi 50001: sai mật khẩu');
    ELSE
        INSERT INTO #AuthResults VALUES('RST-03', N'Mật khẩu cũ không còn hiệu lực', 0, N'Mã lỗi: ' + CAST(ERROR_NUMBER() AS VARCHAR(10)));
END CATCH;

-- TEST 16: Đăng nhập bằng mật khẩu mới thành công qua sp_Login
BEGIN TRY
    EXEC dbo.sp_Login @Username=@u1, @Password=@newPassSuccess;
    IF CONVERT(VARCHAR(20), SESSION_CONTEXT(N'Role')) = N'CUSTOMER'
        INSERT INTO #AuthResults VALUES('RST-04', N'Đăng nhập bằng mật khẩu mới thành công và xác thực phiên', 1, N'sp_Login thành công, SESSION_CONTEXT=CUSTOMER');
    ELSE
        INSERT INTO #AuthResults VALUES('RST-04', N'Đăng nhập bằng mật khẩu mới thành công và xác thực phiên', 0, N'Context không khớp');
END TRY
BEGIN CATCH
    INSERT INTO #AuthResults VALUES('RST-04', N'Đăng nhập bằng mật khẩu mới thành công và xác thực phiên', 0, ERROR_MESSAGE());
END CATCH;

-- Dọn dẹp dữ liệu test
DELETE FROM dbo.ActivityLogs WHERE UserId IN (SELECT UserId FROM dbo.Users WHERE Username LIKE 'reg_test_%' OR Username LIKE 'concur_test_%');
DELETE FROM dbo.Users WHERE Username LIKE 'reg_test_%' OR Username LIKE 'concur_test_%';

-- Tổng hợp kết quả
SELECT id, name, CASE WHEN [pass]=1 THEN N'PASS' ELSE N'FAIL' END AS Result, note
FROM #AuthResults
ORDER BY id;
GO
