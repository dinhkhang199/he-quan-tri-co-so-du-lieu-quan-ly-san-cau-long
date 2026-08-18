/* ============================================================
   NON-REPEATABLE READ DEMO - Session B  (tests/concurrency)
   Domain: Court.PricePerHour (sân C5)

   UNSAFE : UPDATE C5 = 120.000 rồi COMMIT trong lúc A đang mở 2 lần đọc
            → A thấy 100.000 rồi 120.000 (non-repeatable read).
   FIXED  : với REPEATABLE READ của A → B bị block tới khi A kết thúc tran.
   ============================================================ */

USE BadmintonCourtManagement;
GO
SET NOCOUNT ON;
SET XACT_ABORT OFF;
GO

IF OBJECT_ID('dbo._NRTestSync', 'U') IS NULL
    CREATE TABLE dbo._NRTestSync (Flag NVARCHAR(60) PRIMARY KEY, SetAt DATETIME2 NOT NULL DEFAULT SYSDATETIME());
-- KHÔNG xóa bảng ở B: A tạo mới đầu demo.
GO

-- ============================================================
-- PHASE UNSAFE
-- ============================================================
PRINT N'[B] ==== PHASE UNSAFE ====';
DECLARE @c5 UNIQUEIDENTIFIER = N'C1000001-0000-0000-0000-000000000005';
DECLARE @waited INT = 0;

-- Chờ A đã đọc lần 1 (cờ NR_A_UNSAFE_START), chờ thêm 2s cho A chắc chắn xong lần đọc 1
WHILE NOT EXISTS (SELECT 1 FROM dbo._NRTestSync WHERE Flag = N'NR_A_UNSAFE_START') AND @waited < 90
BEGIN
    WAITFOR DELAY '00:00:01';
    SET @waited = @waited + 1;
END;
IF NOT EXISTS (SELECT 1 FROM dbo._NRTestSync WHERE Flag = N'NR_A_UNSAFE_START')
    PRINT N'[B] Timeout chờ A (UNSAFE).';

WAITFOR DELAY '00:00:02';

BEGIN TRAN;
    UPDATE dbo.Courts
    SET PricePerHour = 120000, UpdatedAt = SYSDATETIME()
    WHERE CourtId = @c5;
COMMIT;
PRINT N'[B] Đã UPDATE + COMMIT C5 = 120.000 ngay giữa 2 lần đọc của A.';
INSERT INTO dbo._NRTestSync(Flag) SELECT N'NR_B_UNSAFE_DONE' WHERE NOT EXISTS (SELECT 1 FROM dbo._NRTestSync WHERE Flag=N'NR_B_UNSAFE_DONE');
GO

-- ============================================================
-- PHASE FIXED (A dùng REPEATABLE READ → B bị block tới khi A xong)
-- ============================================================
PRINT N'[B] ==== PHASE FIXED ====';
DECLARE @c5b UNIQUEIDENTIFIER = N'C1000001-0000-0000-0000-000000000005';
DECLARE @waited2 INT = 0;

-- Chờ A đã giữ S-lock C5 (cờ NR_A_FIX_START), chờ thêm 2s cho A chắc chắn xong lần đọc 1
WHILE NOT EXISTS (SELECT 1 FROM dbo._NRTestSync WHERE Flag = N'NR_A_FIX_START') AND @waited2 < 90
BEGIN
    WAITFOR DELAY '00:00:01';
    SET @waited2 = @waited2 + 1;
END;
IF NOT EXISTS (SELECT 1 FROM dbo._NRTestSync WHERE Flag = N'NR_A_FIX_START')
    PRINT N'[B] Timeout chờ A (FIXED).';

WAITFOR DELAY '00:00:02';

INSERT INTO dbo._NRTestSync(Flag) SELECT N'NR_B_FIX_TRY' WHERE NOT EXISTS (SELECT 1 FROM dbo._NRTestSync WHERE Flag=N'NR_B_FIX_TRY');
PRINT N'[B] UPDATE C5 = 120.000 → nếu A đang REPEATABLE READ (giữ S-lock), lệnh này BỊ BLOCKED tới khi A kết thúc tran...';
BEGIN TRAN;
    UPDATE dbo.Courts
    SET PricePerHour = 120000, UpdatedAt = SYSDATETIME()
    WHERE CourtId = @c5b;
COMMIT;
PRINT N'[B] Hết block → C5 = 120.000 đã commit KHÔNG thay đổi trong lúc A đang đọc → NON-REPEATABLE READ bị ngăn.';
INSERT INTO dbo._NRTestSync(Flag) SELECT N'NR_B_FIX_DONE' WHERE NOT EXISTS (SELECT 1 FROM dbo._NRTestSync WHERE Flag=N'NR_B_FIX_DONE');
GO