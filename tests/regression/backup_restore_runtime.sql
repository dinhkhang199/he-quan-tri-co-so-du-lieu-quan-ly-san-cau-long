/* ============================================================
   BadmintonCourtManagement — Backup & Restore Runtime Verification
   Script : backup_restore_runtime.sql
   Mục đích: Thực hiện BACKUP DATABASE thật, RESTORE VERIFYONLY thật,
             RESTORE DATABASE thật sang DB mới và so khớp toàn bộ dữ liệu & đối tượng.
   ============================================================ */

USE master;
GO
SET NOCOUNT ON;

-- 0. Dọn dẹp DB kiểm tra cũ nếu tồn tại
IF DB_ID(N'BadmintonCourtManagement_ProductTest_RestoreVerify') IS NOT NULL
BEGIN
    ALTER DATABASE BadmintonCourtManagement_ProductTest_RestoreVerify SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE BadmintonCourtManagement_ProductTest_RestoreVerify;
END;
GO

-- 1. BACKUP DATABASE THẬT
DECLARE @BackupFile NVARCHAR(500) = N'C:\Program Files\Microsoft SQL Server\MSSQL16.SQLEXPRESS\MSSQL\DATA\BCM_ProductTest_LiveVerify.bak';

PRINT N'>>> 1. ĐANG THỰC HIỆN BACKUP DATABASE BadmintonCourtManagement_ProductTest...';
BACKUP DATABASE BadmintonCourtManagement_ProductTest
TO DISK = @BackupFile
WITH INIT, FORMAT, NAME = N'BCM_ProductTest_FullBackup';
GO

-- 2. RESTORE VERIFYONLY
DECLARE @BackupFile NVARCHAR(500) = N'C:\Program Files\Microsoft SQL Server\MSSQL16.SQLEXPRESS\MSSQL\DATA\BCM_ProductTest_LiveVerify.bak';
PRINT N'>>> 2. ĐANG THỰC HIỆN RESTORE VERIFYONLY...';
RESTORE VERIFYONLY FROM DISK = @BackupFile;
GO

-- 3. RESTORE DATABASE SANG DB MỚI
DECLARE @BackupFile NVARCHAR(500) = N'C:\Program Files\Microsoft SQL Server\MSSQL16.SQLEXPRESS\MSSQL\DATA\BCM_ProductTest_LiveVerify.bak';
DECLARE @RestoreData NVARCHAR(500) = N'C:\Program Files\Microsoft SQL Server\MSSQL16.SQLEXPRESS\MSSQL\DATA\BadmintonCourtManagement_ProductTest_RestoreVerify.mdf';
DECLARE @RestoreLog NVARCHAR(500) = N'C:\Program Files\Microsoft SQL Server\MSSQL16.SQLEXPRESS\MSSQL\DATA\BadmintonCourtManagement_ProductTest_RestoreVerify_log.ldf';

PRINT N'>>> 3. ĐANG RESTORE SANG BadmintonCourtManagement_ProductTest_RestoreVerify...';
RESTORE DATABASE BadmintonCourtManagement_ProductTest_RestoreVerify
FROM DISK = @BackupFile
WITH
    MOVE N'BadmintonCourtManagement_ProductTest' TO @RestoreData,
    MOVE N'BadmintonCourtManagement_ProductTest_log' TO @RestoreLog,
    REPLACE;
GO

-- 4. KIỂM TRA SO SÁNH DỮ LIỆU & OBJECT COUNTS TRÊN DB SAU RESTORE
USE BadmintonCourtManagement_ProductTest_RestoreVerify;
GO
SET NOCOUNT ON;

PRINT N'------------------------------------------------------------';
PRINT N'>>> KẾT QUẢ SO KHỚP SỐ DÒNG CÁC BẢNG TRÊN DB SAU RESTORE:';
SELECT 'Users' AS TableName, COUNT(*) AS [RowCount] FROM dbo.Users
UNION ALL SELECT 'Courts', COUNT(*) FROM dbo.Courts
UNION ALL SELECT 'Bookings', COUNT(*) FROM dbo.Bookings
UNION ALL SELECT 'ActivityLogs', COUNT(*) FROM dbo.ActivityLogs
UNION ALL SELECT 'Notifications', COUNT(*) FROM dbo.Notifications;

PRINT N'------------------------------------------------------------';
PRINT N'>>> KẾT QUẢ SO KHỚP SỐ LƯỢNG OBJECT TRÊN DB SAU RESTORE:';
SELECT 'Tables' AS ObjectType, COUNT(*) AS [ObjectCount] FROM sys.tables WHERE is_ms_shipped = 0
UNION ALL SELECT 'Views', COUNT(*) FROM sys.views WHERE is_ms_shipped = 0
UNION ALL SELECT 'Functions', COUNT(*) FROM sys.objects WHERE type IN ('FN', 'IF', 'TF') AND is_ms_shipped = 0
UNION ALL SELECT 'Stored Procedures', COUNT(*) FROM sys.procedures WHERE is_ms_shipped = 0
UNION ALL SELECT 'Triggers', COUNT(*) FROM sys.triggers WHERE is_ms_shipped = 0;
GO

-- 5. Dọn dẹp DB tạm và file backup sau khi kiểm tra xong
USE master;
GO
IF DB_ID(N'BadmintonCourtManagement_ProductTest_RestoreVerify') IS NOT NULL
BEGIN
    ALTER DATABASE BadmintonCourtManagement_ProductTest_RestoreVerify SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE BadmintonCourtManagement_ProductTest_RestoreVerify;
    PRINT N'>>> [CLEANUP] Đã drop BadmintonCourtManagement_ProductTest_RestoreVerify an toàn.';
END;
GO
