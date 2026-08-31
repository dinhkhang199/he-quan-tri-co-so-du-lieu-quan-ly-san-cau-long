/* ============================================================
   BadmintonCourtManagement — Product Extension Test Suite
   Script : auth_features.sql
   Mục đích: Kiểm thử toàn diện các tính năng Register, Forgot & Reset Password
   ============================================================ */

USE BadmintonCourtManagement;
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
DELETE FROM dbo.ActivityLogs WHERE UserId IN (SELECT UserId FROM dbo.Users WHERE Username LIKE 'reg_test_%');
DELETE FROM dbo.Users WHERE Username LIKE 'reg_test_%';
GO

-- TEST 1: Register CUSTOMER thành công
DECLARE @u1 NVARCHAR(50) = N'reg_test_user_01';
DECLARE @p1 NVARCHAR(200) = N'StrongPass123';
DECLARE @phone1 NVARCHAR(20) = N'0981112233';
DECLARE @email1 NVARCHAR(254) = N'reg_test_01@badmintonpro.local';

BEGIN TRY
    EXEC dbo.sp_Register @Username=@u1, @Password=@p1, @PhoneNumber=@phone1, @Email=@email1;
    IF EXISTS (SELECT 1 FROM dbo.Users WHERE Username=@u1 AND Role=N'CUSTOMER' AND IsActive=1)
        INSERT INTO #AuthResults VALUES('REG-01', N'Đăng ký tài khoản CUSTOMER thành công', 1, N'Tài khoản đã tạo với Role=CUSTOMER');
    ELSE
        INSERT INTO #AuthResults VALUES('REG-01', N'Đăng ký tài khoản CUSTOMER thành công', 0, N'Không tìm thấy user sau đăng ký');
END TRY
BEGIN CATCH
    INSERT INTO #AuthResults VALUES('REG-01', N'Đăng ký tài khoản CUSTOMER thành công', 0, ERROR_MESSAGE());
END CATCH;

-- TEST 2: Đăng ký trùng Username -> lỗi 50201
BEGIN TRY
    EXEC dbo.sp_Register @Username=@u1, @Password=N'OtherPass123', @PhoneNumber=N'0989998877', @Email=N'other@badmintonpro.local';
    INSERT INTO #AuthResults VALUES('REG-02', N'Chặn đăng ký trùng Username', 0, N'Không bị chặn');
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50201
        INSERT INTO #AuthResults VALUES('REG-02', N'Chặn đăng ký trùng Username', 1, N'Bị chặn đúng mã 50201');
    ELSE
        INSERT INTO #AuthResults VALUES('REG-02', N'Chặn đăng ký trùng Username', 0, N'Mã lỗi: ' + CAST(ERROR_NUMBER() AS VARCHAR(10)));
END CATCH;

-- TEST 3: Đăng ký trùng Phone -> lỗi 50202
BEGIN TRY
    EXEC dbo.sp_Register @Username=N'reg_test_diff_user', @Password=N'OtherPass123', @PhoneNumber=@phone1, @Email=N'diff@badmintonpro.local';
    INSERT INTO #AuthResults VALUES('REG-03', N'Chặn đăng ký trùng Số điện thoại', 0, N'Không bị chặn');
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50202
        INSERT INTO #AuthResults VALUES('REG-03', N'Chặn đăng ký trùng Số điện thoại', 1, N'Bị chặn đúng mã 50202');
    ELSE
        INSERT INTO #AuthResults VALUES('REG-03', N'Chặn đăng ký trùng Số điện thoại', 0, N'Mã lỗi: ' + CAST(ERROR_NUMBER() AS VARCHAR(10)));
END CATCH;

-- TEST 4: Đăng ký trùng Email -> lỗi 50204
BEGIN TRY
    EXEC dbo.sp_Register @Username=N'reg_test_diff_user2', @Password=N'OtherPass123', @PhoneNumber=N'0989991122', @Email=@email1;
    INSERT INTO #AuthResults VALUES('REG-04', N'Chặn đăng ký trùng Email', 0, N'Không bị chặn');
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50204
        INSERT INTO #AuthResults VALUES('REG-04', N'Chặn đăng ký trùng Email', 1, N'Bị chặn đúng mã 50204');
    ELSE
        INSERT INTO #AuthResults VALUES('REG-04', N'Chặn đăng ký trùng Email', 0, N'Mã lỗi: ' + CAST(ERROR_NUMBER() AS VARCHAR(10)));
END CATCH;

-- TEST 5: Đăng nhập bằng tài khoản vừa tạo qua sp_Login
BEGIN TRY
    EXEC dbo.sp_Login @Username=@u1, @Password=@p1;
    IF CONVERT(VARCHAR(20), SESSION_CONTEXT(N'Role')) = N'CUSTOMER'
        INSERT INTO #AuthResults VALUES('REG-05', N'Đăng nhập tài khoản mới tạo qua sp_Login', 1, N'SESSION_CONTEXT=CUSTOMER');
    ELSE
        INSERT INTO #AuthResults VALUES('REG-05', N'Đăng nhập tài khoản mới tạo qua sp_Login', 0, N'Context không khớp');
END TRY
BEGIN CATCH
    INSERT INTO #AuthResults VALUES('REG-05', N'Đăng nhập tài khoản mới tạo qua sp_Login', 0, ERROR_MESSAGE());
END CATCH;

-- TEST 6: Request password reset với thông tin đúng -> sinh code 6 chữ số
DECLARE @code NVARCHAR(6);
BEGIN TRY
    DECLARE @tblReset TABLE (UserId UNIQUEIDENTIFIER, Username NVARCHAR(50), Email NVARCHAR(254), ResetCode NVARCHAR(6), ExpiresAt DATETIME2(0));
    INSERT INTO @tblReset
    EXEC dbo.sp_RequestPasswordReset @Username=@u1, @Email=@email1;

    SET @code = (SELECT TOP 1 ResetCode FROM @tblReset);
    IF LEN(@code) = 6 AND @code NOT LIKE N'%[^0-9]%'
        INSERT INTO #AuthResults VALUES('RST-01', N'Yêu cầu khôi phục mật khẩu sinh mã 6 số', 1, N'Mã OTP: ' + @code);
    ELSE
        INSERT INTO #AuthResults VALUES('RST-01', N'Yêu cầu khôi phục mật khẩu sinh mã 6 số', 0, N'Mã không đúng định dạng');
END TRY
BEGIN CATCH
    INSERT INTO #AuthResults VALUES('RST-01', N'Yêu cầu khôi phục mật khẩu sinh mã 6 số', 0, ERROR_MESSAGE());
END CATCH;

-- TEST 7: Request reset với thông tin sai -> lỗi 50210
BEGIN TRY
    EXEC dbo.sp_RequestPasswordReset @Username=@u1, @Email=N'wrong_email@badmintonpro.local';
    INSERT INTO #AuthResults VALUES('RST-02', N'Yêu cầu khôi phục sai email bị chặn', 0, N'Không bị chặn');
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50210
        INSERT INTO #AuthResults VALUES('RST-02', N'Yêu cầu khôi phục sai email bị chặn', 1, N'Lỗi 50210 (chống enumeration)');
    ELSE
        INSERT INTO #AuthResults VALUES('RST-02', N'Yêu cầu khôi phục sai email bị chặn', 0, N'Mã lỗi: ' + CAST(ERROR_NUMBER() AS VARCHAR(10)));
END CATCH;

-- TEST 8: Reset password nhập sai mã -> tăng attempt + lỗi 50212
BEGIN TRY
    EXEC dbo.sp_ResetPassword @Username=@u1, @Email=@email1, @ResetCode=N'000000', @NewPassword=N'NewPassword999';
    INSERT INTO #AuthResults VALUES('RST-03', N'Nhập sai mã OTP bị từ chối', 0, N'Không bị chặn');
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50212
        INSERT INTO #AuthResults VALUES('RST-03', N'Nhập sai mã OTP bị từ chối', 1, N'Lỗi 50212 mã không đúng');
    ELSE
        INSERT INTO #AuthResults VALUES('RST-03', N'Nhập sai mã OTP bị từ chối', 0, N'Mã lỗi: ' + CAST(ERROR_NUMBER() AS VARCHAR(10)));
END CATCH;

-- TEST 9: Reset password đúng mã -> thành công
DECLARE @newPass NVARCHAR(200) = N'BrandNewPass888';
BEGIN TRY
    EXEC dbo.sp_ResetPassword @Username=@u1, @Email=@email1, @ResetCode=@code, @NewPassword=@newPass;
    INSERT INTO #AuthResults VALUES('RST-04', N'Đặt lại mật khẩu với mã OTP đúng thành công', 1, N'Cập nhật PasswordHash và hủy mã OTP');
END TRY
BEGIN CATCH
    INSERT INTO #AuthResults VALUES('RST-04', N'Đặt lại mật khẩu với mã OTP đúng thành công', 0, ERROR_MESSAGE());
END CATCH;

-- TEST 10: Đăng nhập bằng mật khẩu mới -> thành công
BEGIN TRY
    EXEC dbo.sp_Login @Username=@u1, @Password=@newPass;
    IF CONVERT(VARCHAR(20), SESSION_CONTEXT(N'Role')) = N'CUSTOMER'
        INSERT INTO #AuthResults VALUES('RST-05', N'Đăng nhập bằng mật khẩu mới thành công', 1, N'sp_Login xác thực thành công');
    ELSE
        INSERT INTO #AuthResults VALUES('RST-05', N'Đăng nhập bằng mật khẩu mới thành công', 0, N'sp_Login thất bại');
END TRY
BEGIN CATCH
    INSERT INTO #AuthResults VALUES('RST-05', N'Đăng nhập bằng mật khẩu mới thành công', 0, ERROR_MESSAGE());
END CATCH;

-- TEST 11: Đăng nhập bằng mật khẩu cũ -> phải thất bại (50001)
BEGIN TRY
    EXEC dbo.sp_Login @Username=@u1, @Password=@p1;
    INSERT INTO #AuthResults VALUES('RST-06', N'Mật khẩu cũ không còn hiệu lực', 0, N'Vẫn đăng nhập được bằng mật khẩu cũ (sai)');
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        INSERT INTO #AuthResults VALUES('RST-06', N'Mật khẩu cũ không còn hiệu lực', 1, N'Lỗi 50001: sai mật khẩu');
    ELSE
        INSERT INTO #AuthResults VALUES('RST-06', N'Mật khẩu cũ không còn hiệu lực', 0, N'Mã lỗi: ' + CAST(ERROR_NUMBER() AS VARCHAR(10)));
END CATCH;

-- Dọn dẹp sau test
DELETE FROM dbo.ActivityLogs WHERE UserId IN (SELECT UserId FROM dbo.Users WHERE Username LIKE 'reg_test_%');
DELETE FROM dbo.Users WHERE Username LIKE 'reg_test_%';

SELECT id, name, CASE WHEN [pass]=1 THEN N'PASS' ELSE N'FAIL' END AS Result, note
FROM #AuthResults
ORDER BY id;
GO
