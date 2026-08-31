/* ============================================================
   BadmintonCourtManagement — Backup & Restore Runtime Verification
   Script : backup_restore_runtime.sql
   Mục đích: Thực hiện BACKUP DATABASE thật, RESTORE VERIFYONLY thật,
             RESTORE DATABASE thật sang DB mới và SO SÁNH / ASSERTION KHẮT KHE:
             - Số dòng TOÀN BỘ 5 BẢNG LÕI (Source vs Restored)
             - Checksum / Data Hash TOÀN BỘ 5 BẢNG LÕI (Source vs Restored)
             - Object counts (Tables, Views, Functions, SPs, Triggers)
             NẾU MISMATCH BẤT KỲ ĐIỂM NÀO: THROW LỖI 59999.
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

-- 4. KIỂM TRA SO SÁNH TRỰC TIẾP SOURCE VS RESTORED & HARD ASSERTION
DECLARE @SrcUsers INT, @ResUsers INT;
DECLARE @SrcCourts INT, @ResCourts INT;
DECLARE @SrcBookings INT, @ResBookings INT;
DECLARE @SrcLogs INT, @ResLogs INT;
DECLARE @SrcNotifs INT, @ResNotifs INT;

DECLARE @SrcUsersChk INT, @ResUsersChk INT;
DECLARE @SrcCourtsChk INT, @ResCourtsChk INT;
DECLARE @SrcBookingsChk INT, @ResBookingsChk INT;
DECLARE @SrcLogsChk INT, @ResLogsChk INT;
DECLARE @SrcNotifsChk INT, @ResNotifsChk INT;

-- Đếm dòng 5 bảng
SELECT @SrcUsers = COUNT(*) FROM BadmintonCourtManagement_ProductTest.dbo.Users;
SELECT @ResUsers = COUNT(*) FROM BadmintonCourtManagement_ProductTest_RestoreVerify.dbo.Users;

SELECT @SrcCourts = COUNT(*) FROM BadmintonCourtManagement_ProductTest.dbo.Courts;
SELECT @ResCourts = COUNT(*) FROM BadmintonCourtManagement_ProductTest_RestoreVerify.dbo.Courts;

SELECT @SrcBookings = COUNT(*) FROM BadmintonCourtManagement_ProductTest.dbo.Bookings;
SELECT @ResBookings = COUNT(*) FROM BadmintonCourtManagement_ProductTest_RestoreVerify.dbo.Bookings;

SELECT @SrcLogs = COUNT(*) FROM BadmintonCourtManagement_ProductTest.dbo.ActivityLogs;
SELECT @ResLogs = COUNT(*) FROM BadmintonCourtManagement_ProductTest_RestoreVerify.dbo.ActivityLogs;

SELECT @SrcNotifs = COUNT(*) FROM BadmintonCourtManagement_ProductTest.dbo.Notifications;
SELECT @ResNotifs = COUNT(*) FROM BadmintonCourtManagement_ProductTest_RestoreVerify.dbo.Notifications;

-- Checksum dữ liệu toàn bộ 5 bảng lõi
SELECT @SrcUsersChk = CHECKSUM_AGG(BINARY_CHECKSUM(UserId, Username, Role, PhoneNumber, Email, IsActive)) FROM BadmintonCourtManagement_ProductTest.dbo.Users;
SELECT @ResUsersChk = CHECKSUM_AGG(BINARY_CHECKSUM(UserId, Username, Role, PhoneNumber, Email, IsActive)) FROM BadmintonCourtManagement_ProductTest_RestoreVerify.dbo.Users;

SELECT @SrcCourtsChk = CHECKSUM_AGG(BINARY_CHECKSUM(CourtId, CourtName, PricePerHour, PricePerThreeHours, IsActive)) FROM BadmintonCourtManagement_ProductTest.dbo.Courts;
SELECT @ResCourtsChk = CHECKSUM_AGG(BINARY_CHECKSUM(CourtId, CourtName, PricePerHour, PricePerThreeHours, IsActive)) FROM BadmintonCourtManagement_ProductTest_RestoreVerify.dbo.Courts;

SELECT @SrcBookingsChk = CHECKSUM_AGG(BINARY_CHECKSUM(BookingId, UserId, CourtId, StartTime, EndTime, Status, TotalCost)) FROM BadmintonCourtManagement_ProductTest.dbo.Bookings;
SELECT @ResBookingsChk = CHECKSUM_AGG(BINARY_CHECKSUM(BookingId, UserId, CourtId, StartTime, EndTime, Status, TotalCost)) FROM BadmintonCourtManagement_ProductTest_RestoreVerify.dbo.Bookings;

SELECT @SrcLogsChk = CHECKSUM_AGG(BINARY_CHECKSUM(LogId, UserId, BookingId, Action, OldStatus, NewStatus, CreatedAt)) FROM BadmintonCourtManagement_ProductTest.dbo.ActivityLogs;
SELECT @ResLogsChk = CHECKSUM_AGG(BINARY_CHECKSUM(LogId, UserId, BookingId, Action, OldStatus, NewStatus, CreatedAt)) FROM BadmintonCourtManagement_ProductTest_RestoreVerify.dbo.ActivityLogs;

SELECT @SrcNotifsChk = CHECKSUM_AGG(BINARY_CHECKSUM(NotificationId, UserId, BookingId, Message, IsRead, CreatedAt)) FROM BadmintonCourtManagement_ProductTest.dbo.Notifications;
SELECT @ResNotifsChk = CHECKSUM_AGG(BINARY_CHECKSUM(NotificationId, UserId, BookingId, Message, IsRead, CreatedAt)) FROM BadmintonCourtManagement_ProductTest_RestoreVerify.dbo.Notifications;

-- Đếm đối tượng
DECLARE @SrcTables INT, @ResTables INT;
DECLARE @SrcViews INT, @ResViews INT;
DECLARE @SrcFunctions INT, @ResFunctions INT;
DECLARE @SrcSPs INT, @ResSPs INT;
DECLARE @SrcTriggers INT, @ResTriggers INT;

SELECT @SrcTables = COUNT(*) FROM BadmintonCourtManagement_ProductTest.sys.tables WHERE is_ms_shipped = 0 AND name NOT LIKE '\_%' ESCAPE '\';
SELECT @ResTables = COUNT(*) FROM BadmintonCourtManagement_ProductTest_RestoreVerify.sys.tables WHERE is_ms_shipped = 0 AND name NOT LIKE '\_%' ESCAPE '\';

SELECT @SrcViews = COUNT(*) FROM BadmintonCourtManagement_ProductTest.sys.views WHERE is_ms_shipped = 0;
SELECT @ResViews = COUNT(*) FROM BadmintonCourtManagement_ProductTest_RestoreVerify.sys.views WHERE is_ms_shipped = 0;

SELECT @SrcFunctions = COUNT(*) FROM BadmintonCourtManagement_ProductTest.sys.objects WHERE type IN ('FN', 'IF', 'TF') AND is_ms_shipped = 0;
SELECT @ResFunctions = COUNT(*) FROM BadmintonCourtManagement_ProductTest_RestoreVerify.sys.objects WHERE type IN ('FN', 'IF', 'TF') AND is_ms_shipped = 0;

SELECT @SrcSPs = COUNT(*) FROM BadmintonCourtManagement_ProductTest.sys.procedures WHERE is_ms_shipped = 0;
SELECT @ResSPs = COUNT(*) FROM BadmintonCourtManagement_ProductTest_RestoreVerify.sys.procedures WHERE is_ms_shipped = 0;

SELECT @SrcTriggers = COUNT(*) FROM BadmintonCourtManagement_ProductTest.sys.triggers WHERE is_ms_shipped = 0;
SELECT @ResTriggers = COUNT(*) FROM BadmintonCourtManagement_ProductTest_RestoreVerify.sys.triggers WHERE is_ms_shipped = 0;

PRINT N'------------------------------------------------------------';
PRINT N'>>> SO SÁNH CHI TIẾT TOÀN BỘ 5 BẢNG LÕI SOURCE VS RESTORED:';
PRINT N'    Users        : Source=' + CAST(@SrcUsers AS VARCHAR(10)) + N', Restored=' + CAST(@ResUsers AS VARCHAR(10)) + N', ChecksumMatch=' + CASE WHEN @SrcUsersChk = @ResUsersChk THEN N'YES' ELSE N'NO' END;
PRINT N'    Courts       : Source=' + CAST(@SrcCourts AS VARCHAR(10)) + N', Restored=' + CAST(@ResCourts AS VARCHAR(10)) + N', ChecksumMatch=' + CASE WHEN @SrcCourtsChk = @ResCourtsChk THEN N'YES' ELSE N'NO' END;
PRINT N'    Bookings     : Source=' + CAST(@SrcBookings AS VARCHAR(10)) + N', Restored=' + CAST(@ResBookings AS VARCHAR(10)) + N', ChecksumMatch=' + CASE WHEN @SrcBookingsChk = @ResBookingsChk THEN N'YES' ELSE N'NO' END;
PRINT N'    ActivityLogs : Source=' + CAST(@SrcLogs AS VARCHAR(10)) + N', Restored=' + CAST(@ResLogs AS VARCHAR(10)) + N', ChecksumMatch=' + CASE WHEN @SrcLogsChk = @ResLogsChk THEN N'YES' ELSE N'NO' END;
PRINT N'    Notifications: Source=' + CAST(@SrcNotifs AS VARCHAR(10)) + N', Restored=' + CAST(@ResNotifs AS VARCHAR(10)) + N', ChecksumMatch=' + CASE WHEN @SrcNotifsChk = @ResNotifsChk THEN N'YES' ELSE N'NO' END;
PRINT N'    Objects      : Tables(' + CAST(@ResTables AS VARCHAR(10)) + N'), Views(' + CAST(@ResViews AS VARCHAR(10)) + N'), Functions(' + CAST(@ResFunctions AS VARCHAR(10)) + N'), SPs(' + CAST(@ResSPs AS VARCHAR(10)) + N'), Triggers(' + CAST(@ResTriggers AS VARCHAR(10)) + N')';
PRINT N'------------------------------------------------------------';

-- HARD ASSERTION: Mismatch bất kỳ điểm nào sẽ THROW lỗi ngay lập tức
IF @SrcUsers <> @ResUsers OR @SrcUsersChk <> @ResUsersChk
   OR @SrcCourts <> @ResCourts OR @SrcCourtsChk <> @ResCourtsChk
   OR @SrcBookings <> @ResBookings OR @SrcBookingsChk <> @ResBookingsChk
   OR @SrcLogs <> @ResLogs OR @SrcLogsChk <> @ResLogsChk
   OR @SrcNotifs <> @ResNotifs OR @SrcNotifsChk <> @ResNotifsChk
   OR @SrcTables <> @ResTables OR @ResTables <> 5
   OR @SrcViews <> @ResViews OR @ResViews <> 4
   OR @SrcFunctions <> @ResFunctions OR @ResFunctions <> 2
   OR @SrcSPs <> @ResSPs OR @ResSPs <> 17
   OR @SrcTriggers <> @ResTriggers OR @ResTriggers <> 6
BEGIN
    THROW 59999, N'ASSERTION FAILED: Phát hiện dữ liệu hoặc đối tượng sau Restore không khớp với Source DB!', 1;
END;

PRINT N'>>> [ASSERTION PASS]: Toàn bộ dữ liệu 5 bảng, Checksum 5 bảng và 17 SPs sau Restore khớp 100% với Source DB!';
GO

-- 5. Dọn dẹp DB tạm sau khi assertion thành công
USE master;
GO
IF DB_ID(N'BadmintonCourtManagement_ProductTest_RestoreVerify') IS NOT NULL
BEGIN
    ALTER DATABASE BadmintonCourtManagement_ProductTest_RestoreVerify SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE BadmintonCourtManagement_ProductTest_RestoreVerify;
    PRINT N'>>> [CLEANUP] Đã drop BadmintonCourtManagement_ProductTest_RestoreVerify an toàn.';
END;
GO
