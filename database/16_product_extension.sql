/* ============================================================
   BadmintonCourtManagement — Product Extension
   Script : 16_product_extension.sql
   Mục đích: Mở rộng tính năng đăng ký và khôi phục mật khẩu (Phase C + D).
   Phân loại: PRODUCT EXTENSION OBJECTS (không thay thế 14 core SPs).
   ============================================================ */

USE BadmintonCourtManagement;
GO
SET XACT_ABORT ON;
SET QUOTED_IDENTIFIER ON;
GO

-- 1. Thêm các cột phục vụ Email & Password Reset vào bảng Users (nếu chưa có)
IF COL_LENGTH(N'dbo.Users', N'Email') IS NULL
    ALTER TABLE dbo.Users ADD Email NVARCHAR(254) NULL;
GO

IF COL_LENGTH(N'dbo.Users', N'PasswordResetCodeHash') IS NULL
    ALTER TABLE dbo.Users ADD PasswordResetCodeHash VARBINARY(64) NULL;
GO

IF COL_LENGTH(N'dbo.Users', N'PasswordResetExpiresAt') IS NULL
    ALTER TABLE dbo.Users ADD PasswordResetExpiresAt DATETIME2(0) NULL;
GO

IF COL_LENGTH(N'dbo.Users', N'PasswordResetAttempts') IS NULL
    ALTER TABLE dbo.Users ADD PasswordResetAttempts TINYINT NOT NULL CONSTRAINT DF_Users_PasswordResetAttempts DEFAULT (0);
GO

-- 2. Seed Email cho các tài khoản mặc định
UPDATE dbo.Users
SET Email = CASE Username
    WHEN N'manager'       THEN N'manager@badmintonpro.local'
    WHEN N'courtmanager1' THEN N'courtmanager1@badmintonpro.local'
    WHEN N'courtmanager2' THEN N'courtmanager2@badmintonpro.local'
    WHEN N'customer1'     THEN N'customer1@badmintonpro.local'
    WHEN N'customer2'     THEN N'customer2@badmintonpro.local'
    WHEN N'customer3'     THEN N'customer3@badmintonpro.local'
    WHEN N'inactive_user' THEN N'inactive@badmintonpro.local'
    ELSE Email
END
WHERE Email IS NULL
  AND Username IN (N'manager', N'courtmanager1', N'courtmanager2', N'customer1', N'customer2', N'customer3', N'inactive_user');
GO

-- 3. Check constraint cho định dạng Email
IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = N'CK_Users_Email_Format')
    ALTER TABLE dbo.Users WITH CHECK ADD CONSTRAINT CK_Users_Email_Format CHECK (
        Email IS NULL OR (LEN(Email) BETWEEN 5 AND 254 AND Email NOT LIKE N'% %' AND Email LIKE N'%_@_%._%')
    );
GO

-- 4. Standard non-filtered index cho Email (tra cứu nhanh, không kích hoạt lỗi QUOTED_IDENTIFIER của legacy harness)
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_Users_Email' AND object_id = OBJECT_ID(N'dbo.Users'))
    CREATE INDEX IX_Users_Email ON dbo.Users(Email);
GO

-- ============================================================
-- 5. SP EXTENSION 1: sp_Register (Đăng ký tài khoản CUSTOMER mới)
-- ============================================================
IF OBJECT_ID(N'dbo.sp_Register', N'P') IS NOT NULL DROP PROCEDURE dbo.sp_Register;
GO
CREATE PROCEDURE dbo.sp_Register
    @Username    NVARCHAR(50),
    @Password    NVARCHAR(200),
    @PhoneNumber NVARCHAR(20),
    @Email       NVARCHAR(254) = NULL
WITH EXECUTE AS OWNER
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    -- Chuẩn hóa và validate input
    SET @Username = LTRIM(RTRIM(@Username));
    SET @PhoneNumber = LTRIM(RTRIM(@PhoneNumber));
    SET @Email = NULLIF(LTRIM(RTRIM(@Email)), N'');

    IF @Username IS NULL OR LEN(@Username) < 3 OR LEN(@Username) > 50
        THROW 50205, N'Tên đăng nhập phải dài từ 3 đến 50 ký tự.', 1;

    IF @Password IS NULL OR LEN(@Password) < 8
        THROW 50206, N'Mật khẩu phải có ít nhất 8 ký tự.', 1;

    IF @PhoneNumber IS NULL OR LEN(@PhoneNumber) < 9 OR LEN(@PhoneNumber) > 15 OR @PhoneNumber LIKE N'%[^0-9]%'
        THROW 50207, N'Số điện thoại không hợp lệ (phải gồm 9–15 chữ số).', 1;

    IF @Email IS NOT NULL AND (LEN(@Email) < 5 OR LEN(@Email) > 254 OR @Email LIKE N'% %' OR @Email NOT LIKE N'%_@_%._%')
        THROW 50208, N'Email không hợp lệ.', 1;

    -- Kiểm tra trùng lặp
    IF EXISTS (SELECT 1 FROM dbo.Users WHERE Username = @Username)
        THROW 50201, N'Tên đăng nhập đã tồn tại trong hệ thống.', 1;

    IF EXISTS (SELECT 1 FROM dbo.Users WHERE PhoneNumber = @PhoneNumber)
        THROW 50202, N'Số điện thoại đã được đăng ký cho tài khoản khác.', 1;

    IF @Email IS NOT NULL AND EXISTS (SELECT 1 FROM dbo.Users WHERE Email = @Email)
        THROW 50204, N'Email đã được đăng ký cho tài khoản khác.', 1;

    DECLARE @NewUserId UNIQUEIDENTIFIER = NEWID();
    DECLARE @PasswordHash VARBINARY(64) = HASHBYTES('SHA2_256', N'bcms|' + @Password);

    BEGIN TRY
        BEGIN TRAN;
            INSERT INTO dbo.Users (UserId, Username, PasswordHash, Role, PhoneNumber, Email, IsActive)
            VALUES (@NewUserId, @Username, @PasswordHash, N'CUSTOMER', @PhoneNumber, @Email, 1);
        COMMIT TRAN;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRAN;
        THROW;
    END CATCH;

    SELECT UserId, Username, Role, PhoneNumber, Email, IsActive, CreatedAt
    FROM dbo.Users
    WHERE UserId = @NewUserId;
END
GO

-- ============================================================
-- 6. SP EXTENSION 2: sp_RequestPasswordReset (Yêu cầu mã OTP khôi phục mật khẩu)
-- ============================================================
IF OBJECT_ID(N'dbo.sp_RequestPasswordReset', N'P') IS NOT NULL DROP PROCEDURE dbo.sp_RequestPasswordReset;
GO
CREATE PROCEDURE dbo.sp_RequestPasswordReset
    @Username NVARCHAR(50),
    @Email    NVARCHAR(254)
WITH EXECUTE AS OWNER
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @Username = LTRIM(RTRIM(@Username));
    SET @Email = LTRIM(RTRIM(@Email));

    DECLARE @TargetUserId UNIQUEIDENTIFIER;
    DECLARE @StoredEmail NVARCHAR(254);
    DECLARE @IsActive BIT;

    SELECT @TargetUserId = UserId, @StoredEmail = Email, @IsActive = IsActive
    FROM dbo.Users WITH (UPDLOCK, HOLDLOCK)
    WHERE Username = @Username;

    -- Chống account enumeration: nếu sai tài khoản / email / inactive, throw mã 50210
    IF @TargetUserId IS NULL OR @StoredEmail IS NULL OR LOWER(@StoredEmail) <> LOWER(@Email) OR @IsActive <> 1
        THROW 50210, N'Thông tin tài khoản không khớp.', 1;

    -- Sinh mã OTP 6 chữ số ngẫu nhiên
    DECLARE @RandomBinary VARBINARY(4) = CRYPT_GEN_RANDOM(4);
    DECLARE @RandomNum INT = ABS(CAST(@RandomBinary AS INT)) % 1000000;
    DECLARE @ResetCode NVARCHAR(6) = RIGHT(N'000000' + CAST(@RandomNum AS NVARCHAR(6)), 6);
    DECLARE @ResetCodeHash VARBINARY(64) = HASHBYTES('SHA2_256', N'bcms-reset|' + @ResetCode);
    DECLARE @ExpiresAt DATETIME2(0) = DATEADD(MINUTE, 10, SYSDATETIME());

    BEGIN TRY
        BEGIN TRAN;
            UPDATE dbo.Users
            SET PasswordResetCodeHash = @ResetCodeHash,
                PasswordResetExpiresAt = @ExpiresAt,
                PasswordResetAttempts = 0
            WHERE UserId = @TargetUserId;
        COMMIT TRAN;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRAN;
        THROW;
    END CATCH;

    SELECT @TargetUserId AS UserId, @Username AS Username, @StoredEmail AS Email, @ResetCode AS ResetCode, @ExpiresAt AS ExpiresAt;
END
GO

-- ============================================================
-- 7. SP EXTENSION 3: sp_ResetPassword (Xác thực OTP và đặt lại mật khẩu)
-- ============================================================
IF OBJECT_ID(N'dbo.sp_ResetPassword', N'P') IS NOT NULL DROP PROCEDURE dbo.sp_ResetPassword;
GO
CREATE PROCEDURE dbo.sp_ResetPassword
    @Username    NVARCHAR(50),
    @Email       NVARCHAR(254),
    @ResetCode   NVARCHAR(20),
    @NewPassword NVARCHAR(200)
WITH EXECUTE AS OWNER
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @Username = LTRIM(RTRIM(@Username));
    SET @Email = LTRIM(RTRIM(@Email));
    SET @ResetCode = LTRIM(RTRIM(@ResetCode));

    IF @ResetCode IS NULL OR LEN(@ResetCode) <> 6 OR @ResetCode LIKE N'%[^0-9]%'
        THROW 50212, N'Mã khôi phục không đúng hoặc không hợp lệ.', 1;

    IF @NewPassword IS NULL OR LEN(@NewPassword) < 8
        THROW 50206, N'Mật khẩu phải có ít nhất 8 ký tự.', 1;

    DECLARE @TargetUserId UNIQUEIDENTIFIER;
    DECLARE @StoredHash VARBINARY(64);
    DECLARE @StoredExpiry DATETIME2(0);
    DECLARE @StoredAttempts TINYINT;
    DECLARE @StoredEmail NVARCHAR(254);
    DECLARE @IsActive BIT;

    BEGIN TRY
        BEGIN TRAN;
            SELECT @TargetUserId = UserId,
                   @StoredHash = PasswordResetCodeHash,
                   @StoredExpiry = PasswordResetExpiresAt,
                   @StoredAttempts = PasswordResetAttempts,
                   @StoredEmail = Email,
                   @IsActive = IsActive
            FROM dbo.Users WITH (UPDLOCK, HOLDLOCK)
            WHERE Username = @Username;

            IF @TargetUserId IS NULL OR @StoredEmail IS NULL OR LOWER(@StoredEmail) <> LOWER(@Email) OR @IsActive <> 1
                THROW 50210, N'Thông tin tài khoản không khớp.', 1;

            IF @StoredHash IS NULL OR @StoredExpiry IS NULL OR @StoredExpiry <= SYSDATETIME() OR @StoredAttempts >= 5
                THROW 50211, N'Mã khôi phục đã hết hạn hoặc không còn hiệu lực.', 1;

            DECLARE @InputHash VARBINARY(64) = HASHBYTES('SHA2_256', N'bcms-reset|' + @ResetCode);

            IF @InputHash <> @StoredHash
            BEGIN
                UPDATE dbo.Users
                SET PasswordResetAttempts = CASE WHEN PasswordResetAttempts < 5 THEN PasswordResetAttempts + 1 ELSE 5 END
                WHERE UserId = @TargetUserId;
                COMMIT TRAN;
                THROW 50212, N'Mã khôi phục không đúng hoặc không hợp lệ.', 1;
            END;

            -- Mật khẩu đúng: Cập nhật PasswordHash và hủy mã reset
            DECLARE @NewHash VARBINARY(64) = HASHBYTES('SHA2_256', N'bcms|' + @NewPassword);
            UPDATE dbo.Users
            SET PasswordHash = @NewHash,
                PasswordResetCodeHash = NULL,
                PasswordResetExpiresAt = NULL,
                PasswordResetAttempts = 0
            WHERE UserId = @TargetUserId;

        COMMIT TRAN;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRAN;
        THROW;
    END CATCH;

    SELECT @TargetUserId AS UserId, @Username AS Username;
END
GO

-- ============================================================
-- 8. Phân quyền bảo mật cho vai trò bcm_app_role
-- ============================================================
IF DATABASE_PRINCIPAL_ID(N'bcm_app_role') IS NOT NULL
BEGIN
    GRANT EXECUTE ON dbo.sp_Register TO bcm_app_role;
    GRANT EXECUTE ON dbo.sp_RequestPasswordReset TO bcm_app_role;
    GRANT EXECUTE ON dbo.sp_ResetPassword TO bcm_app_role;
END;
GO

PRINT N'[OK] Product Extension 16: Users extended columns + sp_Register, sp_RequestPasswordReset, sp_ResetPassword đã được tạo và cấp quyền.';
GO
