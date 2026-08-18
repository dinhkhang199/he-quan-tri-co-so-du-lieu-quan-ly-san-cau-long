/* ============================================================
   NON-REPEATABLE READ DEMO - Session A  (tests/concurrency)
   Domain: Court.PricePerHour (sân C5, baseline 100.000 VNĐ)

   CÁCH CHẠY (cờ _NRTestSync, không cần canh giờ chính xác):
     1. Cửa sổ A chạy nonrepeatable_session_A.sql
     2. Trong ~5 giây cửa sổ B chạy nonrepeatable_session_B.sql

   PHASE UNSAFE (READ COMMITTED):
     - A mở tran, đọc C5 lần 1 = 100.000
     - B UPDATE + COMMIT C5 = 120.000 ngay giữa 2 lần đọc của A
     - A đọc lần 2 = 120.000 (KHÁC lần 1) → NON-REPEATABLE READ
   PHASE FIXED (REPEATABLE READ):
     - A đọc lần 1 giữ S-lock C5 tới hết tran
     - B UPDATE C5 = 120.000 → BỊ BLOCKED tới khi A kết thúc
     - A đọc lần 2 = 100.000 (giống lần 1) → NON-REPEATABLE bị ngăn
   ============================================================ */

USE BadmintonCourtManagement;
GO
SET NOCOUNT ON;
SET XACT_ABORT OFF;
GO

-- Bảng cờ đồng bộ test (riêng cho non-repeatable). A tạo MỚI ở đầu để luôn sạch cờ.
DROP TABLE IF EXISTS dbo._NRTestSync;
CREATE TABLE dbo._NRTestSync (Flag NVARCHAR(60) PRIMARY KEY, SetAt DATETIME2 NOT NULL DEFAULT SYSDATETIME());
GO

-- ============================================================
-- PHASE UNSAFE (READ COMMITTED): 2 lần đọc cùng 1 dòng khác nhau
-- ============================================================
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
DECLARE @c5 UNIQUEIDENTIFIER = N'C1000001-0000-0000-0000-000000000005';
DECLARE @r1 DECIMAL(12,0), @r2 DECIMAL(12,0);
DECLARE @waited INT = 0;

UPDATE dbo.Courts SET PricePerHour = 100000, UpdatedAt = SYSDATETIME() WHERE CourtId = @c5;
PRINT N'[A] ==== PHASE UNSAFE ==== Baseline PricePerHour C5 = 100.000';

INSERT INTO dbo._NRTestSync(Flag) SELECT N'NR_A_UNSAFE_START' WHERE NOT EXISTS (SELECT 1 FROM dbo._NRTestSync WHERE Flag=N'NR_A_UNSAFE_START');

BEGIN TRAN;
    SELECT @r1 = PricePerHour FROM dbo.Courts WHERE CourtId = @c5;
    PRINT N'[A] Lần đọc 1 (trong tran): ' + CAST(@r1 AS NVARCHAR(20));

    -- Chờ B UPDATE + COMMIT C5 = 120.000 (cờ NR_B_UNSAFE_DONE)
    WHILE NOT EXISTS (SELECT 1 FROM dbo._NRTestSync WHERE Flag = N'NR_B_UNSAFE_DONE') AND @waited < 90
    BEGIN
        WAITFOR DELAY '00:00:01';
        SET @waited = @waited + 1;
    END;
    IF NOT EXISTS (SELECT 1 FROM dbo._NRTestSync WHERE Flag = N'NR_B_UNSAFE_DONE')
        PRINT N'[A] Timeout chờ B (UNSAFE).';

    SELECT @r2 = PricePerHour FROM dbo.Courts WHERE CourtId = @c5;
    PRINT N'[A] Lần đọc 2 (trong tran): ' + CAST(@r2 AS NVARCHAR(20));

    IF @r1 <> @r2
        PRINT N'[A] >>> CÙNG 1 dòng C5, 2 lần đọc KHÁC nhau (' + CAST(@r1 AS NVARCHAR(20)) + N' → ' + CAST(@r2 AS NVARCHAR(20)) + N') → NON-REPEATABLE READ.';
    ELSE
        PRINT N'[A] >>> Hai lần đọc giống nhau (B chưa chạy kịp?).';
COMMIT;
GO

-- ============================================================
-- PHASE FIXED (REPEATABLE READ): B bị block, 2 lần đọc giống nhau
-- ============================================================
SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;
DECLARE @c5b UNIQUEIDENTIFIER = N'C1000001-0000-0000-0000-000000000005';
DECLARE @f1 DECIMAL(12,0), @f2 DECIMAL(12,0);
DECLARE @waited2 INT = 0;

UPDATE dbo.Courts SET PricePerHour = 100000, UpdatedAt = SYSDATETIME() WHERE CourtId = @c5b;
PRINT N'[A] ==== PHASE FIXED ==== Baseline PricePerHour C5 = 100.000';

INSERT INTO dbo._NRTestSync(Flag) SELECT N'NR_A_FIX_START' WHERE NOT EXISTS (SELECT 1 FROM dbo._NRTestSync WHERE Flag=N'NR_A_FIX_START');

BEGIN TRAN;
    SELECT @f1 = PricePerHour FROM dbo.Courts WHERE CourtId = @c5b;
    PRINT N'[A] FIXED lần đọc 1 (giữ S-lock C5 tới hết tran): ' + CAST(@f1 AS NVARCHAR(20));

    -- Chờ B đã chạy tới UPDATE (cờ NR_B_FIX_TRY → B đang bị block bởi S-lock này)
    WHILE NOT EXISTS (SELECT 1 FROM dbo._NRTestSync WITH (NOLOCK) WHERE Flag = N'NR_B_FIX_TRY') AND @waited2 < 90
    BEGIN
        WAITFOR DELAY '00:00:01';
        SET @waited2 = @waited2 + 1;
    END;
    IF NOT EXISTS (SELECT 1 FROM dbo._NRTestSync WITH (NOLOCK) WHERE Flag = N'NR_B_FIX_TRY')
        PRINT N'[A] Timeout chờ B (FIXED / TRY).';

    -- Chờ thêm 2s để B chắc chắn đã bị BLOCK ở lệnh UPDATE
    WAITFOR DELAY '00:00:02';

    SELECT @f2 = PricePerHour FROM dbo.Courts WHERE CourtId = @c5b;
    PRINT N'[A] FIXED lần đọc 2: ' + CAST(@f2 AS NVARCHAR(20));

    IF @f1 = @f2
        PRINT N'[A] >>> Khóa chia sẻ giữ tới hết tran → 2 lần đọc GIỐNG nhau → NON-REPEATABLE READ bị ngăn.';
    ELSE
        PRINT N'[A] >>> FAIL: 2 lần đọc khác nhau?';
COMMIT;
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;

-- Chờ B thoát block + commit (NR_B_FIX_DONE) để đóng demo
DECLARE @waited3 INT = 0;
INSERT INTO dbo._NRTestSync(Flag) SELECT N'NR_A_DONE' WHERE NOT EXISTS (SELECT 1 FROM dbo._NRTestSync WHERE Flag=N'NR_A_DONE');
WHILE NOT EXISTS (SELECT 1 FROM dbo._NRTestSync WHERE Flag = N'NR_B_FIX_DONE') AND @waited3 < 90
BEGIN
    WAITFOR DELAY '00:00:01';
    SET @waited3 = @waited3 + 1;
END;
IF NOT EXISTS (SELECT 1 FROM dbo._NRTestSync WHERE Flag = N'NR_B_FIX_DONE')
    PRINT N'[A] Timeout chờ B (FIXED / DONE).';
GO

-- ---- Cleanup ----
UPDATE dbo.Courts SET PricePerHour = 100000, UpdatedAt = SYSDATETIME()
WHERE CourtId = 'C1000001-0000-0000-0000-000000000005';
PRINT N'[A] Cleanup xong: PricePerHour C5 trở về 100.000.';
GO