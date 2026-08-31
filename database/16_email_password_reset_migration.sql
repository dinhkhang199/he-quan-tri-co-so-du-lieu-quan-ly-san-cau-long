/* Nâng cấp DB hiện có: thêm email phục vụ đăng ký và khôi phục mật khẩu.
   Sau script này, chạy lại database/06_procedures.sql để cập nhật sp_Login. */
USE BadmintonCourtManagement;
GO
SET XACT_ABORT ON;
SET QUOTED_IDENTIFIER ON;
GO

IF COL_LENGTH(N'dbo.Users', N'Email') IS NULL
    ALTER TABLE dbo.Users ADD Email NVARCHAR(254) NULL;
GO

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

IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = N'CK_Users_Email_Format')
    ALTER TABLE dbo.Users WITH CHECK ADD CONSTRAINT CK_Users_Email_Format CHECK (
        Email IS NULL OR (LEN(Email) BETWEEN 5 AND 254 AND Email NOT LIKE N'% %' AND Email LIKE N'%_@_%._%')
    );
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'UQ_Users_Email_NotNull' AND object_id = OBJECT_ID(N'dbo.Users'))
    CREATE UNIQUE INDEX UQ_Users_Email_NotNull ON dbo.Users(Email) WHERE Email IS NOT NULL;
GO

PRINT N'[OK] Email migration: Users.Email + format check + unique filtered index.';
GO
