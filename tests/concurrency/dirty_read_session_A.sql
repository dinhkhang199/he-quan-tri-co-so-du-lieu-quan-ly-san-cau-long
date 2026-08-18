/* ============================================================
   DIRTY READ DEMO - Session A  (tests/concurrency)
   Domain: Court.PricePerHour (sân C5, baseline 100.000 VNĐ)

   CÁCH CHẠY (cờ _DRTestSync, không cần canh giờ chính xác):
     1. Cửa sổ A chạy dirty_read_session_A.sql
     2. Trong ~5 giây cửa sổ B chạy dirty_read_session_B.sql

   PHASE UNSAFE (A đổi giá NHƯNG chưa commit; B đọc ở READ UNCOMMITTED):
     - A BEGIN TRAN rồi UPDATE C5 = 200.000 (chưa commit), báo cờ DR_A_UNSAFE_START
     - B chờ cờ + 2s, đọc READ UNCOMMITTED → thấy 200.000 DÙ CHƯA COMMIT
       (báo DR_B_UNSAFE_READ_200000)
     - A ROLLBACK → giá 200.000 biến mất = DIRTY READ (B đọc dữ liệu chưa commit)
   PHASE FIXED (B đọc ở READ COMMITTED - mặc định):
     - A BEGIN TRAN rồi UPDATE C5 = 200.000 (chưa commit), báo cờ DR_A_FIX_START
     - B SELECT ở READ COMMITTED → BỊ BLOCK tới khi A kết thúc tran → chỉ đọc được
       giá ĐÃ COMMIT (100.000 sau rollback) = KHÔNG dirty read
   ============================================================ */

USE BadmintonCourtManagement;
GO
SET NOCOUNT ON;
SET XACT_ABORT OFF;
GO

-- Bảng cờ đồng bộ test (riêng cho dirty-read). A tạo MỚI ở đầu để luôn sạch cờ.
DROP TABLE IF EXISTS dbo._DRTestSync;
CREATE TABLE dbo._DRTestSync (Flag NVARCHAR(60) PRIMARY KEY, SetAt DATETIME2 NOT NULL DEFAULT SYSDATETIME());
GO

-- ============================================================
-- PHASE UNSAFE : dirty read
-- ============================================================
DECLARE @c5 UNIQUEIDENTIFIER = N'C1000001-0000-0000-0000-000000000005';
DECLARE @waited INT = 0;

UPDATE dbo.Courts SET PricePerHour = 100000, UpdatedAt = SYSDATETIME() WHERE CourtId = @c5;
PRINT N'[A] ==== PHASE UNSAFE ==== Baseline PricePerHour C5 = 100.000';

-- Báo "A sắp mở tran đổi 200.000 chưa commit"; mở tran NGAY sau đó.
INSERT INTO dbo._DRTestSync(Flag) SELECT N'DR_A_UNSAFE_START' WHERE NOT EXISTS (SELECT 1 FROM dbo._DRTestSync WHERE Flag=N'DR_A_UNSAFE_START');

BEGIN TRAN;
    UPDATE dbo.Courts
    SET PricePerHour = 200000, UpdatedAt = SYSDATETIME()
    WHERE CourtId = @c5;
    PRINT N'[A] Đã UPDATE PricePerHour = 200.000 (CHƯA COMMIT). Cờ đã báo → B sẽ đọc được giá dirty này.';

    -- Chờ B (READ UNCOMMITTED) đọc xong 200.000 (DR_B_UNSAFE_READ_200000)
    WHILE NOT EXISTS (SELECT 1 FROM dbo._DRTestSync WHERE Flag = N'DR_B_UNSAFE_READ_200000') AND @waited < 90
    BEGIN
        WAITFOR DELAY '00:00:01';
        SET @waited = @waited + 1;
    END;
    IF NOT EXISTS (SELECT 1 FROM dbo._DRTestSync WHERE Flag = N'DR_B_UNSAFE_READ_200000')
        PRINT N'[A] Timeout chờ B (UNSAFE).';

    PRINT N'[A] B đã đọc 200.000 dù chưa commit → mình ROLLBACK để phơi bày dữ liệu dirty.';
ROLLBACK;

PRINT N'[A] Đã ROLLBACK: giá 200.000 chưa từng tồn tại thật, nay biến mất → đó là DIRTY READ.';
SELECT PricePerHour AS FinalPrice_C5 FROM dbo.Courts WHERE CourtId = @c5;
GO

-- ============================================================
-- PHASE FIXED : READ COMMITTED của B - B không thể đọc giá dirty
-- ============================================================
DECLARE @c5b UNIQUEIDENTIFIER = N'C1000001-0000-0000-0000-000000000005';
DECLARE @waited2 INT = 0;

UPDATE dbo.Courts SET PricePerHour = 100000, UpdatedAt = SYSDATETIME() WHERE CourtId = @c5b;
PRINT N'[A] ==== PHASE FIXED ==== Baseline PricePerHour C5 = 100.000';

INSERT INTO dbo._DRTestSync(Flag) SELECT N'DR_A_FIX_START' WHERE NOT EXISTS (SELECT 1 FROM dbo._DRTestSync WHERE Flag=N'DR_A_FIX_START');

BEGIN TRAN;
    UPDATE dbo.Courts
    SET PricePerHour = 200000, UpdatedAt = SYSDATETIME()
    WHERE CourtId = @c5b;
    PRINT N'[A] Đã UPDATE PricePerHour = 200.000 (CHƯA COMMIT). Chờ B (READ COMMITTED) chạy tới SELECT và bị BLOCK.';

    -- Chờ B báo đã tới SELECT (đang bị block bởi X-lock C5 chưa commit này)
    WHILE NOT EXISTS (SELECT 1 FROM dbo._DRTestSync WITH (NOLOCK) WHERE Flag = N'DR_B_FIX_TRY') AND @waited2 < 90
    BEGIN
        WAITFOR DELAY '00:00:01';
        SET @waited2 = @waited2 + 1;
    END;
    IF NOT EXISTS (SELECT 1 FROM dbo._DRTestSync WITH (NOLOCK) WHERE Flag = N'DR_B_FIX_TRY')
        PRINT N'[A] Timeout chờ B (FIXED / TRY).';

    PRINT N'[A] B đang bị khóa (không đọc được 200.000). Mình ROLLBACK để nhả block cho B đọc giá đã commit.';
ROLLBACK;

-- Chờ B đọc xong giá đã commit (100.000) rồi chốt kết luận
DECLARE @waited3 INT = 0;
WHILE NOT EXISTS (SELECT 1 FROM dbo._DRTestSync WHERE Flag = N'DR_B_FIX_READ_COMMITTED') AND @waited3 < 90
BEGIN
    WAITFOR DELAY '00:00:01';
    SET @waited3 = @waited3 + 1;
END;
IF NOT EXISTS (SELECT 1 FROM dbo._DRTestSync WHERE Flag = N'DR_B_FIX_READ_COMMITTED')
    PRINT N'[A] Timeout chờ B (FIXED / READ).';
ELSE
    PRINT N'[A] >>> B đọc được giá ĐÃ COMMIT (100.000) chứ không phải 200.000 dirty → DIRTY READ bị ngăn.';
GO

-- ---- Cleanup ----
UPDATE dbo.Courts SET PricePerHour = 100000, UpdatedAt = SYSDATETIME()
WHERE CourtId = 'C1000001-0000-0000-0000-000000000005';
PRINT N'[A] Cleanup xong: PricePerHour C5 trở về 100.000.';
GO