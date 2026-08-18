/* ============================================================
   DIRTY READ DEMO - Session B  (tests/concurrency)
   Domain: Court.PricePerHour (sân C5)

   UNSAFE : READ UNCOMMITTED → B ĐỌC ĐƯỢC giá 200.000 CHƯA COMMIT của A
            (rồi A rollback → giá đó không tồn tại thật = DIRTY READ).
   FIXED  : READ COMMITTED (mặc định) → B bị block, chỉ đọc giá đã commit.
   ============================================================ */

USE BadmintonCourtManagement;
GO
SET NOCOUNT ON;
SET XACT_ABORT OFF;
GO

IF OBJECT_ID('dbo._DRTestSync', 'U') IS NULL
    CREATE TABLE dbo._DRTestSync (Flag NVARCHAR(60) PRIMARY KEY, SetAt DATETIME2 NOT NULL DEFAULT SYSDATETIME());
-- KHÔNG xóa bảng ở B: A tạo mới đầu demo.
GO

-- ============================================================
-- PHASE UNSAFE (READ UNCOMMITTED)
-- ============================================================
PRINT N'[B] ==== PHASE UNSAFE (READ UNCOMMITTED) ====';
DECLARE @c5 UNIQUEIDENTIFIER = N'C1000001-0000-0000-0000-000000000005';
DECLARE @val DECIMAL(12,0);
DECLARE @waited INT = 0;

-- Chờ A đã UPDATE 200.000 nhưng CHƯA commit (cờ DR_A_UNSAFE_START)
WHILE NOT EXISTS (SELECT 1 FROM dbo._DRTestSync WHERE Flag = N'DR_A_UNSAFE_START') AND @waited < 90
BEGIN
    WAITFOR DELAY '00:00:01';
    SET @waited = @waited + 1;
END;
IF NOT EXISTS (SELECT 1 FROM dbo._DRTestSync WHERE Flag = N'DR_A_UNSAFE_START')
    PRINT N'[B] Timeout chờ A (UNSAFE).';

-- 2s để A chắc chắn đã xong lệnh UPDATE chưa commit
WAITFOR DELAY '00:00:02';

SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SELECT @val = PricePerHour FROM dbo.Courts WHERE CourtId = @c5;
PRINT N'[B] Đọc được PricePerHour = ' + CAST(@val AS NVARCHAR(20)) + N' — DÙ A CHƯA COMMIT.';

IF @val = 200000
    INSERT INTO dbo._DRTestSync(Flag) SELECT N'DR_B_UNSAFE_READ_200000' WHERE NOT EXISTS (SELECT 1 FROM dbo._DRTestSync WHERE Flag=N'DR_B_UNSAFE_READ_200000');

PRINT N'[B] Nếu đọc được 200.000 mà A sau đó rollback → DIRTY READ (đọc dữ liệu chưa commit).';
GO

-- ============================================================
-- PHASE FIXED (READ COMMITTED, mặc định) — B bị block, không thấy giá dirty
-- ============================================================
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
PRINT N'[B] ==== PHASE FIXED (READ COMMITTED) ====';
DECLARE @c5b UNIQUEIDENTIFIER = N'C1000001-0000-0000-0000-000000000005';
DECLARE @val2 DECIMAL(12,0);
DECLARE @waited2 INT = 0;

-- Chờ A đã UPDATE 200.000 chưa commit (cờ DR_A_FIX_START)
WHILE NOT EXISTS (SELECT 1 FROM dbo._DRTestSync WHERE Flag = N'DR_A_FIX_START') AND @waited2 < 90
BEGIN
    WAITFOR DELAY '00:00:01';
    SET @waited2 = @waited2 + 1;
END;
IF NOT EXISTS (SELECT 1 FROM dbo._DRTestSync WHERE Flag = N'DR_A_FIX_START')
    PRINT N'[B] Timeout chờ A (FIXED).';

WAITFOR DELAY '00:00:02';

INSERT INTO dbo._DRTestSync(Flag) SELECT N'DR_B_FIX_TRY' WHERE NOT EXISTS (SELECT 1 FROM dbo._DRTestSync WHERE Flag=N'DR_B_FIX_TRY');
PRINT N'[B] SELECT (READ COMMITTED) → nếu A còn giữ UPDATE chưa commit, lệnh này BỊ BLOCK tới khi A kết thúc tran, không đọc được 200.000 dirty.';
SELECT @val2 = PricePerHour FROM dbo.Courts WHERE CourtId = @c5b;
PRINT N'[B] Hết block. Giá đọc được (đã commit) = ' + CAST(@val2 AS NVARCHAR(20)) + N'.';

IF @val2 = 100000
    INSERT INTO dbo._DRTestSync(Flag) SELECT N'DR_B_FIX_READ_COMMITTED' WHERE NOT EXISTS (SELECT 1 FROM dbo._DRTestSync WHERE Flag=N'DR_B_FIX_READ_COMMITTED');

PRINT N'[B] Không đọc được 200.000 chưa commit → DIRTY READ bị ngăn (READ COMMITTED mặc định).';
GO