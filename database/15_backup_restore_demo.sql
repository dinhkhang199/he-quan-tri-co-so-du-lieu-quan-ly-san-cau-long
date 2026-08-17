/* ============================================================
   BadmintonCourtManagement
   Script : 15_backup_restore_demo.sql
   Mục đích: bằng chứng phục hồi (contract 8) - RC-01
     BACKUP -> RESTORE VERIFYONLY -> RESTORE sang DB kiểm thử -> so sánh dữ liệu lõi
   LƯU Ý : database dùng RECOVERY FULL (xem 00). Đổi @BackupRoot nếu cần.
   ============================================================ */

SET NOCOUNT ON;
GO

-- Đường dẫn backup (đổi nếu cần - MỌI đường dẫn bên dưới phải thay theo)
DECLARE @VerifyDb NVARCHAR(200) = N'BadmintonCourtManagement_Verify';
DECLARE @BackupDir NVARCHAR(500) = N'D:\SQLServer\MSSQL16.MSSQLSERVER\MSSQL\Backup';
DECLARE @DataDir   NVARCHAR(500) = N'D:\SQLServer\MSSQL16.MSSQLSERVER\MSSQL\DATA';

-- ============================================================
-- Bước 0: dọn DB kiểm thử cũ (nếu có)
-- ============================================================
IF DB_ID(@VerifyDb) IS NOT NULL
BEGIN
    DECLARE @sql NVARCHAR(500) = N'ALTER DATABASE ' + QUOTENAME(@VerifyDb) + N' SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE ' + QUOTENAME(@VerifyDb) + N';';
    EXEC sp_executesql @sql;
    PRINT N'[RC-01] Đã dọn DB kiểm thử cũ.';
END
GO

-- ============================================================
-- Bước 1: BACKUP DATABASE
-- ============================================================
BACKUP DATABASE [BadmintonCourtManagement]
TO DISK = N'D:\SQLServer\MSSQL16.MSSQLSERVER\MSSQL\Backup\BadmintonCourtManagement.bak'
WITH INIT, FORMAT, STATS = 10;
PRINT N'[RC-01] BACKUP hoàn tất.';
GO

-- ============================================================
-- Bước 2: RESTORE VERIFYONLY - kiểm tra backup hợp lệ
-- ============================================================
RESTORE VERIFYONLY
FROM DISK = N'D:\SQLServer\MSSQL16.MSSQLSERVER\MSSQL\Backup\BadmintonCourtManagement.bak';
PRINT N'[RC-01] RESTORE VERIFYONLY: backup hợp lệ.';
GO

-- ============================================================
-- Bước 3: RESTORE sang DB kiểm thử BadmintonCourtManagement_Verify
-- ============================================================
DECLARE @DataName NVARCHAR(128), @LogName NVARCHAR(128);
SELECT TOP 1 @DataName = [name] FROM BadmintonCourtManagement.sys.database_files WHERE type = 0;
SELECT TOP 1 @LogName  = [name] FROM BadmintonCourtManagement.sys.database_files WHERE type = 1;

DECLARE @restoreSql NVARCHAR(MAX) = N'
RESTORE DATABASE [BadmintonCourtManagement_Verify]
FROM DISK = N''D:\SQLServer\MSSQL16.MSSQLSERVER\MSSQL\Backup\BadmintonCourtManagement.bak''
WITH
    MOVE N''' + @DataName + N''' TO N''D:\SQLServer\MSSQL16.MSSQLSERVER\MSSQL\DATA\Verify_' + @DataName + N'.mdf'',
    MOVE N''' + @LogName + N''' TO N''D:\SQLServer\MSSQL16.MSSQLSERVER\MSSQL\DATA\Verify_' + @LogName + N'.ldf'',
    REPLACE;';
EXEC sp_executesql @restoreSql;
PRINT N'[RC-01] RESTORE sang DB kiểm thử hoàn tất.';
GO

-- ============================================================
-- Bước 4: SO SÁNH dữ liệu lõi (DB gốc vs DB restore)
-- ============================================================
DECLARE @MainUsers INT, @VerifyUsers INT;
DECLARE @MainCourts INT, @VerifyCourts INT;
DECLARE @MainBookings INT, @VerifyBookings INT;

SELECT @MainUsers   = COUNT(*) FROM [BadmintonCourtManagement].dbo.Users;
SELECT @VerifyUsers = COUNT(*) FROM [BadmintonCourtManagement_Verify].dbo.Users;
SELECT @MainCourts   = COUNT(*) FROM [BadmintonCourtManagement].dbo.Courts;
SELECT @VerifyCourts = COUNT(*) FROM [BadmintonCourtManagement_Verify].dbo.Courts;
SELECT @MainBookings   = COUNT(*) FROM [BadmintonCourtManagement].dbo.Bookings;
SELECT @VerifyBookings = COUNT(*) FROM [BadmintonCourtManagement_Verify].dbo.Bookings;

PRINT N'[RC-01] So sánh:';
PRINT N'  Users    : gốc=' + CAST(@MainUsers AS VARCHAR(10))   + N' | restore=' + CAST(@VerifyUsers AS VARCHAR(10));
PRINT N'  Courts   : gốc=' + CAST(@MainCourts AS VARCHAR(10))  + N' | restore=' + CAST(@VerifyCourts AS VARCHAR(10));
PRINT N'  Bookings : gốc=' + CAST(@MainBookings AS VARCHAR(10)) + N' | restore=' + CAST(@VerifyBookings AS VARCHAR(10));

IF @MainUsers = @VerifyUsers AND @MainCourts = @VerifyCourts AND @MainBookings = @VerifyBookings
    PRINT N'>> Khớp số lượng.';
ELSE
    PRINT N'>> LỆCH SỐ LƯỢNG - kiểm tra lại.';
GO

-- So sánh chi tiết vài booking quan trọng + checksum tổng thể
IF EXISTS
(
    SELECT 1
    FROM [BadmintonCourtManagement].dbo.Bookings a
    FULL OUTER JOIN [BadmintonCourtManagement_Verify].dbo.Bookings b
        ON b.BookingId = a.BookingId
    WHERE a.BookingId IS NULL OR b.BookingId IS NULL
       OR a.UserId <> b.UserId OR a.CourtId <> b.CourtId
       OR a.StartTime <> b.StartTime OR a.EndTime <> b.EndTime
       OR a.Status <> b.Status OR a.TotalCost <> b.TotalCost
)
    PRINT N'[RC-01] Có khác biệt chi tiết booking giữa gốc và restore!';
ELSE
    PRINT N'[RC-01] Bookings khớp 100% (userId/courtId/time/status/cost).';
GO

-- ============================================================
-- Bước 5: dọn DB kiểm thử (tùy chọn)
-- ============================================================
-- IF DB_ID(N'BadmintonCourtManagement_Verify') IS NOT NULL
-- BEGIN
--     ALTER DATABASE [BadmintonCourtManagement_Verify] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
--     DROP DATABASE [BadmintonCourtManagement_Verify];
--     PRINT N'[RC-01] Đã dọn DB kiểm thử.';
-- END
-- GO

PRINT N'--- Hết 15_backup_restore_demo.sql. ---';
GO