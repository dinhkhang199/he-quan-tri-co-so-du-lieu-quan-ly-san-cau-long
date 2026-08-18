/* ============================================================
   BadmintonCourtManagement
   Script : 15_backup_restore_demo.sql
   Mục đích: bằng chứng phục hồi (contract 8) - RC-01
     BACKUP -> RESTORE VERIFYONLY -> RESTORE sang DB kiểm thử -> so sánh dữ liệu lõi
   LƯU Ý : database dùng RECOVERY FULL (xem 00).
   Đường dẫn backup/data KHÔNG hard-code cho 1 máy:
   - Mặc định: lấy thư mục Backup + DATA mặc định của INSTANCE hiện tại
     (SERVERPROPERTY('InstanceDefaultBackupPath') + thư mục chứa master.mdf).
   - Muốn dùng thư mục riêng: đổi BIẾN MÔI TRƯỜNG ở bước CONFIG bên dưới.
   ============================================================ */

SET NOCOUNT ON;
GO

-- ============================================================
-- CONFIG (đổi 2 biến này nếu muốn dùng thư mục khác instance default)
--     @OverrideBackupDir / @OverrideDataDir = NULL → dùng instance default.
--     Giá trị phải là đường dẫn tuyệt đối có sẵn trên máy, vd:
--     N'D:\SQLBackup\'  và  N'D:\SQLData\'
-- ============================================================
DECLARE @OverrideBackupDir NVARCHAR(500) = NULL;
DECLARE @OverrideDataDir   NVARCHAR(500) = NULL;

DECLARE @VerifyDb NVARCHAR(200) = N'BadmintonCourtManagement_Verify';
DECLARE @BackupDir NVARCHAR(500) = CAST(SERVERPROPERTY('InstanceDefaultBackupPath') AS NVARCHAR(500));
DECLARE @DataDir   NVARCHAR(500);

-- Thư mục DATA: lấy từ vị trí file master.mdf của instance
SELECT @DataDir = LEFT(physical_name, CHARINDEX('\', REVERSE(physical_name), 2) * -1 + LEN(physical_name) + 1)
FROM sys.master_files
WHERE database_id = 1 AND type = 0;

IF @OverrideBackupDir IS NOT NULL SET @BackupDir = @OverrideBackupDir;
IF @OverrideDataDir   IS NOT NULL SET @DataDir   = @OverrideDataDir;

IF RIGHT(@BackupDir, 1) <> N'\' SET @BackupDir = @BackupDir + N'\';
IF RIGHT(@DataDir, 1)   <> N'\' SET @DataDir   = @DataDir + N'\';

-- Lưu cấu hình vào temp table (tồn tại xuyên qua nhiều batch)
IF OBJECT_ID('tempdb..#BCMConfig') IS NOT NULL DROP TABLE #BCMConfig;
CREATE TABLE #BCMConfig (ConfigKey NVARCHAR(50) PRIMARY KEY, ConfigValue NVARCHAR(600));
INSERT INTO #BCMConfig (ConfigKey, ConfigValue)
VALUES (N'VerifyDb', @VerifyDb), (N'BackupDir', @BackupDir), (N'DataDir', @DataDir);

PRINT N'[RC-01] VerifyDb  : ' + @VerifyDb;
PRINT N'[RC-01] Backup dir: ' + ISNULL(@BackupDir, N'<null>');
PRINT N'[RC-01] Data dir  : ' + ISNULL(@DataDir,   N'<null>');
IF @BackupDir IS NULL OR @DataDir IS NULL
    THROW 52020, N'RC-01 LỖI: không xác định được thư mục backup/data. Hãy set @OverrideBackupDir/@OverrideDataDir.', 1;
GO

-- ============================================================
-- Bước 0: dọn DB kiểm thử cũ (nếu có)
-- ============================================================
DECLARE @v0 NVARCHAR(200) = (SELECT ConfigValue FROM #BCMConfig WHERE ConfigKey = N'VerifyDb');
IF DB_ID(@v0) IS NOT NULL
BEGIN
    DECLARE @sql0 NVARCHAR(500) = N'ALTER DATABASE ' + QUOTENAME(@v0) + N' SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE ' + QUOTENAME(@v0) + N';';
    EXEC sp_executesql @sql0;
    PRINT N'[RC-01] Đã dọn DB kiểm thử cũ.';
END
ELSE
    PRINT N'[RC-01] Không có DB kiểm thử cũ phải dọn.';
GO

-- ============================================================
-- Bước 1: BACKUP DATABASE
-- ============================================================
DECLARE @bk NVARCHAR(600) = (SELECT ConfigValue FROM #BCMConfig WHERE ConfigKey = N'BackupDir');
DECLARE @BackupFile NVARCHAR(700) = @bk + N'BadmintonCourtManagement.bak';
DECLARE @backupSql NVARCHAR(MAX) = N'
BACKUP DATABASE [BadmintonCourtManagement]
TO DISK = N''' + @BackupFile + N'''
WITH INIT, FORMAT, STATS = 10;';
PRINT N'[RC-01] => ' + @BackupFile;
EXEC sp_executesql @backupSql;
PRINT N'[RC-01] BACKUP hoàn tất.';
GO

-- ============================================================
-- Bước 2: RESTORE VERIFYONLY - kiểm tra backup hợp lệ
-- ============================================================
DECLARE @bk2 NVARCHAR(600) = (SELECT ConfigValue FROM #BCMConfig WHERE ConfigKey = N'BackupDir');
DECLARE @verifySql NVARCHAR(MAX) = N'RESTORE VERIFYONLY FROM DISK = N''' + @bk2 + N'BadmintonCourtManagement.bak'';';
EXEC sp_executesql @verifySql;
PRINT N'[RC-01] RESTORE VERIFYONLY: backup hợp lệ.';
GO

-- ============================================================
-- Bước 3: RESTORE sang DB kiểm thử
-- ============================================================
DECLARE @v3 NVARCHAR(200) = (SELECT ConfigValue FROM #BCMConfig WHERE ConfigKey = N'VerifyDb');
DECLARE @dt NVARCHAR(600) = (SELECT ConfigValue FROM #BCMConfig WHERE ConfigKey = N'DataDir');
DECLARE @bk3 NVARCHAR(600) = (SELECT ConfigValue FROM #BCMConfig WHERE ConfigKey = N'BackupDir');

DECLARE @DataName NVARCHAR(128), @LogName NVARCHAR(128);
SELECT TOP 1 @DataName = [name] FROM [BadmintonCourtManagement].sys.database_files WHERE type = 0;
SELECT TOP 1 @LogName  = [name] FROM [BadmintonCourtManagement].sys.database_files WHERE type = 1;

DECLARE @restoreSql NVARCHAR(MAX) = N'
RESTORE DATABASE ' + QUOTENAME(@v3) + N'
FROM DISK = N''' + @bk3 + N'BadmintonCourtManagement.bak''
WITH
    MOVE N''' + @DataName + N''' TO N''' + @dt + N'Verify_' + @DataName + N'.mdf'',
    MOVE N''' + @LogName + N''' TO N''' + @dt + N'Verify_' + @LogName + N'.ldf'',
    REPLACE;';
PRINT N'[RC-01] Restore data files vào: ' + @dt;
EXEC sp_executesql @restoreSql;
PRINT N'[RC-01] RESTORE sang DB kiểm thử hoàn tất.';
GO

-- ============================================================
-- Bước 4: SO SÁNH dữ liệu lõi (DB gốc vs DB restore)
-- ============================================================
GO

-- So sánh thực tế (cách an toàn: dùng dynamic name đã biết)
DECLARE @VerifyName NVARCHAR(200) = (SELECT ConfigValue FROM #BCMConfig WHERE ConfigKey = N'VerifyDb');
PRINT N'[RC-01] --- So sánh dữ liệu lõi ---';
EXEC(N'
    DECLARE @u1 INT, @c1 INT, @b1 INT;
    DECLARE @u2 INT, @c2 INT, @b2 INT;
    SELECT @u1 = COUNT(*) FROM [BadmintonCourtManagement].dbo.Users;
    SELECT @c1 = COUNT(*) FROM [BadmintonCourtManagement].dbo.Courts;
    SELECT @b1 = COUNT(*) FROM [BadmintonCourtManagement].dbo.Bookings;
    SELECT @u2 = COUNT(*) FROM [' + @VerifyName + N'].dbo.Users;
    SELECT @c2 = COUNT(*) FROM [' + @VerifyName + N'].dbo.Courts;
    SELECT @b2 = COUNT(*) FROM [' + @VerifyName + N'].dbo.Bookings;
    PRINT N''[RC-01] Users    : goc=''   + CAST(@u1 AS VARCHAR(10)) + N'' | restore='' + CAST(@u2 AS VARCHAR(10));
    PRINT N''[RC-01] Courts   : goc=''   + CAST(@c1 AS VARCHAR(10)) + N'' | restore='' + CAST(@c2 AS VARCHAR(10));
    PRINT N''[RC-01] Bookings : goc=''   + CAST(@b1 AS VARCHAR(10)) + N'' | restore='' + CAST(@b2 AS VARCHAR(10));
    IF @u1 <> @u2 OR @c1 <> @c2 OR @b1 <> @b2
        THROW 52021, N''RC-01 FAIL: số lượng lệch giữa DB gốc và DB restore.'', 1;
    PRINT N''[RC-01] >> Khớp số lượng.'';

    -- So sánh chi tiết booking (bookingId/user/court/time/status/cost) + sentinel
    IF EXISTS (
        SELECT 1
        FROM [BadmintonCourtManagement].dbo.Bookings a
        FULL OUTER JOIN [' + @VerifyName + N'].dbo.Bookings b
            ON b.BookingId = a.BookingId
        WHERE a.BookingId IS NULL OR b.BookingId IS NULL
           OR a.UserId <> b.UserId OR a.CourtId <> b.CourtId
           OR a.StartTime <> b.StartTime OR a.EndTime <> b.EndTime
           OR a.Status <> b.Status OR a.TotalCost <> b.TotalCost
    )
        THROW 52022, N''RC-01 FAIL: chi tiết booking giữa gốc và restore khác nhau.'', 1;
    PRINT N''[RC-01] Bookings khớp 100% (userId/courtId/time/status/cost).'';
');
GO

-- ============================================================
-- Bước 5: dọn DB kiểm thử (tùy chọn)
-- ============================================================
-- DECLARE @v5 NVARCHAR(200) = (SELECT ConfigValue FROM #BCMConfig WHERE ConfigKey = N'VerifyDb');
-- IF DB_ID(@v5) IS NOT NULL
-- BEGIN
--     DECLARE @sql5 NVARCHAR(500) = N'ALTER DATABASE ' + QUOTENAME(@v5) + N' SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE ' + QUOTENAME(@v5) + N';';
--     EXEC sp_executesql @sql5;
--     PRINT N'[RC-01] Đã dọn DB kiểm thử.';
-- END
-- GO

PRINT N'--- Hết 15_backup_restore_demo.sql. ---';
GO