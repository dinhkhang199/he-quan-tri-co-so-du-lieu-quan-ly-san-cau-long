/* ============================================================
   LOST UPDATE DEMO - Session B  (tests/concurrency)
   Domain: Court.PricePerHour (sân C5, baseline 100.000 VNĐ)

   CÁCH CHẠY: đồng bộ với Session A (xem file A).
   PHASE UNSAFE: chờ cờ LU_A_STALE → B đọc 100.000 → ghi +20.000 = 120.000
                 rồi COMMIT, báo LU_B_UNSAFE_DONE. A dùng stale 100.000 ghi
                 150.000 → B mất +20.000 (lost update).
   PHASE FIXED : chờ cờ LU_FXA_DONE (A đã giữ UPDLOCK C5). B chạy SELECT
                 UPDLOCK → bị BLOCK tới khi A commit 150.000 → B đọc 150.000
                 → ghi +20.000 = 170.000 (nối tiếp, không mất), báo LU_FXB_DONE.
   ============================================================ */

USE BadmintonCourtManagement;
GO
SET NOCOUNT ON;
SET XACT_ABORT OFF;
GO

IF OBJECT_ID('dbo._LUTestSync', 'U') IS NULL
    CREATE TABLE dbo._LUTestSync (Flag NVARCHAR(60) PRIMARY KEY, SetAt DATETIME2 NOT NULL DEFAULT SYSDATETIME());
-- KHÔNG xóa bảng ở B: A (chạy trước) tạo mới; nếu B xóa sẽ mất cờ A đặt.
GO

-- ============================================================
-- PHASE UNSAFE
-- ============================================================
DECLARE @c5 UNIQUEIDENTIFIER = N'C1000001-0000-0000-0000-000000000005';
DECLARE @oldPrice DECIMAL(12,0);
DECLARE @waited INT = 0;
PRINT N'[B] ==== PHASE UNSAFE ====';

-- Chờ A đã đọc stale (cờ LU_A_STALE)
WHILE NOT EXISTS (SELECT 1 FROM dbo._LUTestSync WHERE Flag = N'LU_A_STALE') AND @waited < 90
BEGIN
    WAITFOR DELAY '00:00:01';
    SET @waited = @waited + 1;
END;
IF NOT EXISTS (SELECT 1 FROM dbo._LUTestSync WHERE Flag = N'LU_A_STALE')
    PRINT N'[B] Timeout chờ A (UNSAFE).';

SELECT @oldPrice = PricePerHour FROM dbo.Courts WHERE CourtId = @c5;
PRINT N'[B] Đọc PricePerHour: ' + CAST(@oldPrice AS NVARCHAR(20));
UPDATE dbo.Courts
SET PricePerHour = @oldPrice + 20000, UpdatedAt = SYSDATETIME()
WHERE CourtId = @c5;
PRINT N'[B] UNSAFE: Commit 120.000 (B ghi +20.000).';
INSERT INTO dbo._LUTestSync(Flag) SELECT N'LU_B_UNSAFE_DONE' WHERE NOT EXISTS (SELECT 1 FROM dbo._LUTestSync WHERE Flag=N'LU_B_UNSAFE_DONE');
GO

-- ============================================================
-- PHASE FIXED
-- ============================================================
DECLARE @c5b UNIQUEIDENTIFIER = N'C1000001-0000-0000-0000-000000000005';
DECLARE @fixedOld DECIMAL(12,0);
DECLARE @waited2 INT = 0;
PRINT N'[B] ==== PHASE FIXED ====';

-- Chờ A báo bắt đầu PHASE FIXED (LU_FXA_START - A sẽ giữ UPDLOCK C5 ngay sau đó)
WHILE NOT EXISTS (SELECT 1 FROM dbo._LUTestSync WHERE Flag = N'LU_FXA_START') AND @waited2 < 90
BEGIN
    WAITFOR DELAY '00:00:01';
    SET @waited2 = @waited2 + 1;
END;
IF NOT EXISTS (SELECT 1 FROM dbo._LUTestSync WHERE Flag = N'LU_FXA_START')
    PRINT N'[B] Timeout chờ A (FIXED).';

-- Chờ 2s để A chắc chắn đã giữ xong UPDLOCK C5 trong transaction
WAITFOR DELAY '00:00:02';

-- Nếu A còn giữ UPDLOCK, SELECT này sẽ BLOCK tới khi A commit 150.000
PRINT N'[B] SELECT WITH UPDLOCK → đợi A commit, bị block cho tới khi khóa nhả...';
SELECT @fixedOld = PricePerHour
FROM dbo.Courts WITH (UPDLOCK, ROWLOCK)
WHERE CourtId = @c5b;
PRINT N'[B] Hết block. Đọc số mới nhất: ' + CAST(@fixedOld AS NVARCHAR(20)) + N' → cộng 20.000 nối tiếp.';
UPDATE dbo.Courts
SET PricePerHour = @fixedOld + 20000, UpdatedAt = SYSDATETIME()
WHERE CourtId = @c5b;
PRINT N'[B] FIXED: Ghi xong → Final = 170.000 (không lost update).';
INSERT INTO dbo._LUTestSync(Flag) SELECT N'LU_FXB_DONE' WHERE NOT EXISTS (SELECT 1 FROM dbo._LUTestSync WHERE Flag=N'LU_FXB_DONE');
GO