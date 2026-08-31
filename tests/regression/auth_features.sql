/* ============================================================
   Kiểm thử tích hợp đăng ký + quên/đặt lại mật khẩu trên SQL Server thật.
   Chạy sau database/00..08. Dữ liệu kiểm thử có khóa cố định và được dọn
   ở đầu/cuối script nên có thể chạy lại.
   ============================================================ */

USE BadmintonCourtManagement;
GO
SET NOCOUNT ON;
SET XACT_ABORT OFF;
GO

IF OBJECT_ID('tempdb..#AuthResult') IS NOT NULL DROP TABLE #AuthResult;
CREATE TABLE #AuthResult
(
    Id VARCHAR(10) NOT NULL,
    Name NVARCHAR(200) NOT NULL,
    [Pass] BIT NOT NULL,
    Note NVARCHAR(500) NULL
);

DECLARE @Username NVARCHAR(50) = N'codex_auth_test';
DECLARE @Phone NVARCHAR(20) = N'0999999101';
DECLARE @OtherPhone NVARCHAR(20) = N'0999999102';
DECLARE @OldPassword NVARCHAR(200) = N'MatKhauCu1';
DECLARE @NewPassword NVARCHAR(200) = N'MatKhauMoi2';
DECLARE @UserId UNIQUEIDENTIFIER;

-- Mục tiêu xóa được giới hạn bởi đúng hai username/phone dành riêng cho test.
DELETE FROM dbo.Users
WHERE Username IN (@Username, N'codex_auth_other')
   OR PhoneNumber IN (@Phone, @OtherPhone);

BEGIN TRY
    EXEC dbo.sp_Login @Username=@Username, @Password=@OldPassword,
        @Action=N'REGISTER', @PhoneNumber=@Phone;
    SELECT @UserId = UserId FROM dbo.Users WHERE Username=@Username;
    INSERT #AuthResult VALUES ('AF-01', N'Đăng ký tài khoản hợp lệ', IIF(@UserId IS NOT NULL, 1, 0), CONVERT(NVARCHAR(36), @UserId));
END TRY
BEGIN CATCH
    INSERT #AuthResult VALUES ('AF-01', N'Đăng ký tài khoản hợp lệ', 0, CONCAT(N'err=', ERROR_NUMBER(), N': ', ERROR_MESSAGE()));
END CATCH;

INSERT #AuthResult
SELECT 'AF-02', N'Đăng ký luôn tạo CUSTOMER active',
       IIF(Role=N'CUSTOMER' AND IsActive=1, 1, 0), CONCAT(N'role=', Role, N', active=', IsActive)
FROM dbo.Users WHERE UserId=@UserId;

BEGIN TRY
    EXEC dbo.sp_Login @Username=@Username, @Password=@OldPassword,
        @Action=N'REGISTER', @PhoneNumber=@OtherPhone;
    INSERT #AuthResult VALUES ('AF-03', N'Chặn trùng username', 0, N'Không phát sinh lỗi');
END TRY
BEGIN CATCH
    INSERT #AuthResult VALUES ('AF-03', N'Chặn trùng username', IIF(ERROR_NUMBER()=50201,1,0), CONCAT(N'err=', ERROR_NUMBER()));
END CATCH;

BEGIN TRY
    EXEC dbo.sp_Login @Username=N'codex_auth_other', @Password=@OldPassword,
        @Action=N'REGISTER', @PhoneNumber=@Phone;
    INSERT #AuthResult VALUES ('AF-04', N'Chặn trùng số điện thoại', 0, N'Không phát sinh lỗi');
END TRY
BEGIN CATCH
    INSERT #AuthResult VALUES ('AF-04', N'Chặn trùng số điện thoại', IIF(ERROR_NUMBER()=50202,1,0), CONCAT(N'err=', ERROR_NUMBER()));
END CATCH;

BEGIN TRY
    EXEC dbo.sp_Login @Username=N'codex_auth_other', @Password=N'weak',
        @Action=N'REGISTER', @PhoneNumber=@OtherPhone;
    INSERT #AuthResult VALUES ('AF-05', N'Chặn mật khẩu yếu', 0, N'Không phát sinh lỗi');
END TRY
BEGIN CATCH
    INSERT #AuthResult VALUES ('AF-05', N'Chặn mật khẩu yếu', IIF(ERROR_NUMBER()=50203,1,0), CONCAT(N'err=', ERROR_NUMBER()));
END CATCH;

BEGIN TRY
    EXEC dbo.sp_Login @Username=N'tên lỗi', @Password=@OldPassword,
        @Action=N'REGISTER', @PhoneNumber=@OtherPhone;
    INSERT #AuthResult VALUES ('AF-06', N'Chặn username không hợp lệ', 0, N'Không phát sinh lỗi');
END TRY
BEGIN CATCH
    INSERT #AuthResult VALUES ('AF-06', N'Chặn username không hợp lệ', IIF(ERROR_NUMBER()=50200,1,0), CONCAT(N'err=', ERROR_NUMBER()));
END CATCH;

DECLARE @CodeTable TABLE (ResetCode NVARCHAR(6), ExpiresAt DATETIME2(0), PhoneLast4 NVARCHAR(4));
INSERT @CodeTable EXEC dbo.sp_Login @Username=@Username, @Action=N'REQUEST_RESET', @PhoneNumber=@Phone;
DECLARE @Code NVARCHAR(6), @ExpiresAt DATETIME2(0);
SELECT @Code=ResetCode, @ExpiresAt=ExpiresAt FROM @CodeTable;

INSERT #AuthResult VALUES ('AF-07', N'Tạo mã khôi phục 6 chữ số, hết hạn sau khoảng 10 phút',
    IIF(@Code NOT LIKE N'%[^0-9]%' AND LEN(@Code)=6 AND DATEDIFF(MINUTE,SYSDATETIME(),@ExpiresAt) BETWEEN 9 AND 10,1,0),
    CONCAT(N'codeLength=', LEN(@Code), N', expiry=', CONVERT(NVARCHAR(30),@ExpiresAt,126)));

INSERT #AuthResult
SELECT 'AF-08', N'DB chỉ lưu hash mã và đặt số lần sai về 0',
       IIF(PasswordResetCodeHash=HASHBYTES('SHA2_256',N'bcms-reset|'+@Code)
           AND DATALENGTH(PasswordResetCodeHash)=32 AND PasswordResetAttempts=0,1,0),
       CONCAT(N'hashBytes=',DATALENGTH(PasswordResetCodeHash),N', attempts=',PasswordResetAttempts)
FROM dbo.Users WHERE UserId=@UserId;

BEGIN TRY
    EXEC dbo.sp_Login @Username=@Username, @Action=N'REQUEST_RESET', @PhoneNumber=N'0999999998';
    INSERT #AuthResult VALUES ('AF-09', N'Không cấp mã khi username/phone không khớp', 0, N'Không phát sinh lỗi');
END TRY
BEGIN CATCH
    INSERT #AuthResult VALUES ('AF-09', N'Không cấp mã khi username/phone không khớp', IIF(ERROR_NUMBER()=50210,1,0), CONCAT(N'err=',ERROR_NUMBER()));
END CATCH;

DECLARE @WrongCode NVARCHAR(6)=CASE WHEN @Code=N'000000' THEN N'000001' ELSE N'000000' END;
BEGIN TRY
    EXEC dbo.sp_Login @Username=@Username, @Password=@NewPassword, @Action=N'RESET_PASSWORD', @PhoneNumber=@Phone, @ResetCode=@WrongCode;
    INSERT #AuthResult VALUES ('AF-10', N'Mã sai bị chặn', 0, N'Không phát sinh lỗi');
END TRY
BEGIN CATCH
    INSERT #AuthResult VALUES ('AF-10', N'Mã sai bị chặn', IIF(ERROR_NUMBER()=50212,1,0), CONCAT(N'err=',ERROR_NUMBER()));
END CATCH;

INSERT #AuthResult
SELECT 'AF-11', N'Mỗi mã sai tăng bộ đếm', IIF(PasswordResetAttempts=1,1,0), CONCAT(N'attempts=',PasswordResetAttempts)
FROM dbo.Users WHERE UserId=@UserId;

EXEC dbo.sp_Login @Username=@Username, @Password=@NewPassword, @Action=N'RESET_PASSWORD', @PhoneNumber=@Phone, @ResetCode=@Code;
INSERT #AuthResult
SELECT 'AF-12', N'Mã đúng đổi mật khẩu và vô hiệu hóa mã ngay',
       IIF(PasswordHash=HASHBYTES('SHA2_256',N'bcms|'+@NewPassword)
           AND PasswordResetCodeHash IS NULL AND PasswordResetExpiresAt IS NULL AND PasswordResetAttempts=0,1,0),
       N'Kiểm tra hash mới và reset fields'
FROM dbo.Users WHERE UserId=@UserId;

BEGIN TRY
    EXEC dbo.sp_Login @Username=@Username, @Password=@OldPassword;
    INSERT #AuthResult VALUES ('AF-13', N'Mật khẩu cũ không đăng nhập được', 0, N'Không phát sinh lỗi');
END TRY
BEGIN CATCH
    INSERT #AuthResult VALUES ('AF-13', N'Mật khẩu cũ không đăng nhập được', IIF(ERROR_NUMBER()=50001,1,0), CONCAT(N'err=',ERROR_NUMBER()));
END CATCH;

BEGIN TRY
    EXEC dbo.sp_Login @Username=@Username, @Password=@NewPassword;
    INSERT #AuthResult VALUES ('AF-14', N'Mật khẩu mới đăng nhập được', 1, N'PASS');
END TRY
BEGIN CATCH
    INSERT #AuthResult VALUES ('AF-14', N'Mật khẩu mới đăng nhập được', 0, CONCAT(N'err=',ERROR_NUMBER(),N': ',ERROR_MESSAGE()));
END CATCH;

DELETE FROM @CodeTable;
INSERT @CodeTable EXEC dbo.sp_Login @Username=@Username, @Action=N'REQUEST_RESET', @PhoneNumber=@Phone;
SELECT @Code=ResetCode FROM @CodeTable;
UPDATE dbo.Users SET PasswordResetExpiresAt=DATEADD(SECOND,-1,SYSDATETIME()) WHERE UserId=@UserId;
BEGIN TRY
    EXEC dbo.sp_Login @Username=@Username, @Password=@OldPassword, @Action=N'RESET_PASSWORD', @PhoneNumber=@Phone, @ResetCode=@Code;
    INSERT #AuthResult VALUES ('AF-15', N'Mã hết hạn bị chặn', 0, N'Không phát sinh lỗi');
END TRY
BEGIN CATCH
    INSERT #AuthResult VALUES ('AF-15', N'Mã hết hạn bị chặn', IIF(ERROR_NUMBER()=50211,1,0), CONCAT(N'err=',ERROR_NUMBER()));
END CATCH;

SELECT Id, Name, [Pass], Note FROM #AuthResult ORDER BY Id;

DECLARE @Failed INT=(SELECT COUNT(*) FROM #AuthResult WHERE [Pass]=0);
DELETE FROM dbo.Users WHERE UserId=@UserId OR Username IN (@Username,N'codex_auth_other') OR PhoneNumber IN (@Phone,@OtherPhone);

IF @Failed > 0
BEGIN
    DECLARE @Message NVARCHAR(2048)=CONCAT(@Failed,N' kiểm thử auth SQL thất bại.');
    THROW 51000, @Message, 1;
END;

PRINT N'PASS: 15/15 kiểm thử SQL đăng ký và quên mật khẩu.';
GO
