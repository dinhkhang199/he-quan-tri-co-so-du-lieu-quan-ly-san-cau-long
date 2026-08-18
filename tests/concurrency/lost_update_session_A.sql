/* ============================================================
   LOST UPDATE DEMO - Session A  (tests/concurrency)
   Domain: Court.PricePerHour (sân C5, baseline 100.000 VNĐ)

   CÁCH CHẠY (cờ _LUTestSync + một khoảng WAITFOR tĩnh, không cần canh giờ chính xác):
     1. Cửa sổ A chạy lost_update_session_A.sql
     2. Trong ~5 giây cửa sổ B chạy lost_update_session_B.sql

   PHASE UNSAFE (READ COMMITTED, đọc rồi ghi bằng stale value):
     - A đọc 100.000 (stale), báo cờ LU_A_STALE (ngoài transaction để B thấy ngay)
     - B đọc 100.000 → update +20.000 = 120.000 → commit → báo LU_B_UNSAFE_DONE
     - A dựa trên giá CŨ ghi +50.000 = 150.000 → GHI ĐÈ B → lost update
     - KẾT LUẬN UNSAFE: Final = 150.000 (B mất +20.000)
   PHASE FIXED (UPDLOCK: B bị block tới khi A commit → nối tiếp):
     - A giữ UPDLOCK C5 trong 6 giây rồi commit 150.000 (hết block)
     - B thoát block, đọc 150.000 → ghi +20.000 = 170.000
     - KẾT LUẬN FIXED  : Final = 170.000 (không lost update)
   ============================================================ */

USE BadmintonCourtManagement;
GO
SET NOCOUNT ON;
SET XACT_ABORT OFF;
GO

-- Bảng cờ đồng bộ test (riêng cho lost-update). A tạo MỚI ở đầu để luôn sạch cờ.
DROP TABLE IF EXISTS dbo._LUTestSync;
CREATE TABLE dbo._LUTestSync (Flag NVARCHAR(60) PRIMARY KEY, SetAt DATETIME2 NOT NULL DEFAULT SYSDATETIME());
GO

-- ============================================================
-- PHASE UNSAFE : lost update (stale read -> overwrite)
-- ============================================================
DECLARE @c5 UNIQUEIDENTIFIER = N'C1000001-0000-0000-0000-000000000005';
DECLARE @oldPrice DECIMAL(12,0);
DECLARE @unsafeFinal DECIMAL(12,0);
DECLARE @waited INT = 0;

UPDATE dbo.Courts SET PricePerHour = 100000, UpdatedAt = SYSDATETIME() WHERE CourtId = @c5;
PRINT N'[A] ==== PHASE UNSAFE ====  Baseline PricePerHour C5 = 100.000';

-- Đọc stale (AUTOCOMMIT, không giữ khóa) rồi báo cờ NGOÀI transaction → B thấy ngay
SELECT @oldPrice = PricePerHour FROM dbo.Courts WHERE CourtId = @c5;
PRINT N'[A] Đọc PricePerHour (stale): ' + CAST(@oldPrice AS NVARCHAR(20));
INSERT INTO dbo._LUTestSync(Flag) SELECT N'LU_A_STALE' WHERE NOT EXISTS (SELECT 1 FROM dbo._LUTestSync WHERE Flag=N'LU_A_STALE');

-- Chờ B (đã đọc 100.000) ghi +20.000 và commit (LU_B_UNSAFE_DONE)
WHILE NOT EXISTS (SELECT 1 FROM dbo._LUTestSync WHERE Flag = N'LU_B_UNSAFE_DONE') AND @waited < 90
BEGIN
    WAITFOR DELAY '00:00:01';
    SET @waited = @waited + 1;
END;
IF NOT EXISTS (SELECT 1 FROM dbo._LUTestSync WHERE Flag = N'LU_B_UNSAFE_DONE')
    PRINT N'[A] Timeout chờ B (UNSAFE).';

-- A ghi dựa trên giá CŨ (100.000) → ghi đè giá B (120.000)
UPDATE dbo.Courts
SET PricePerHour = @oldPrice + 50000, UpdatedAt = SYSDATETIME()
WHERE CourtId = @c5;
PRINT N'[A] Đã ghi từ stale 100.000 -> 150.000 (ghi đè B).';

SELECT @unsafeFinal = PricePerHour FROM dbo.Courts WHERE CourtId = @c5;
PRINT N'[A] KẾT LUẬN UNSAFE: Final = ' + CAST(@unsafeFinal AS NVARCHAR(20));
IF @unsafeFinal = 150000
    PRINT N'[A] >>> LOST UPDATE xảy ra (B mất +20.000) - đúng kịch bản unsafe.';
ELSE
    PRINT N'[A] >>> Không phải 150.000 (bất thường).';
GO

-- ============================================================
-- PHASE FIXED : UPDLOCK (B bị block tới khi A commit -> nối tiếp)
-- ============================================================
DECLARE @c5b UNIQUEIDENTIFIER = N'C1000001-0000-0000-0000-000000000005';
DECLARE @fixedOld DECIMAL(12,0);
DECLARE @fixedFinal DECIMAL(12,0);
DECLARE @waited2 INT = 0;

UPDATE dbo.Courts SET PricePerHour = 100000, UpdatedAt = SYSDATETIME()
WHERE CourtId = @c5b;
PRINT N'[A] ==== PHASE FIXED ====  Baseline reset 100.000';

-- Báo "A sắp vào PHASE FIXED" NGOÀI transaction và lấy khóa ngay sau đó:
-- B đợi cờ này rồi chờ thêm 2s để chắc chắn A đã giữ xong UPDLOCK C5.
INSERT INTO dbo._LUTestSync(Flag) SELECT N'LU_FXA_START' WHERE NOT EXISTS (SELECT 1 FROM dbo._LUTestSync WHERE Flag=N'LU_FXA_START');

BEGIN TRAN;
    SELECT @fixedOld = PricePerHour
    FROM dbo.Courts WITH (UPDLOCK, ROWLOCK)
    WHERE CourtId = @c5b;
    PRINT N'[A] FIXED: Đọc (giữ UPDLOCK) = ' + CAST(@fixedOld AS NVARCHAR(20)) + N', chờ B block, giữ khóa 6 giây...';

    -- B (đợi LU_FXA_START + 2s) chạy SELECT UPDLOCK trong khoảng này và bị BLOCK
    WAITFOR DELAY '00:00:06';

    UPDATE dbo.Courts
    SET PricePerHour = @fixedOld + 50000, UpdatedAt = SYSDATETIME()
    WHERE CourtId = @c5b;
COMMIT;
PRINT N'[A] FIXED: A commit 150.000 → B đang block sẽ thoát và đọc số mới.';

-- Chờ B ghi xong (LU_FXB_DONE) rồi verify
WHILE NOT EXISTS (SELECT 1 FROM dbo._LUTestSync WHERE Flag = N'LU_FXB_DONE') AND @waited2 < 90
BEGIN
    WAITFOR DELAY '00:00:01';
    SET @waited2 = @waited2 + 1;
END;
IF NOT EXISTS (SELECT 1 FROM dbo._LUTestSync WHERE Flag = N'LU_FXB_DONE')
    PRINT N'[A] Timeout chờ B (FIXED).';

SELECT @fixedFinal = PricePerHour FROM dbo.Courts WHERE CourtId = @c5b;
PRINT N'[A] KẾT LUẬN FIXED: Final = ' + CAST(@fixedFinal AS NVARCHAR(20));
IF @fixedFinal = 170000
    PRINT N'[A] >>> ASSERTION PASS: 170.000 → KHÔNG lost update (A 150.000 + B 20.000 nối tiếp).';
ELSE
    PRINT N'[A] >>> ASSERTION FAIL: Final ≠ 170.000.';
GO

-- ============================================================
-- Cleanup: reset baseline về 100.000
-- ============================================================
UPDATE dbo.Courts SET PricePerHour = 100000, UpdatedAt = SYSDATETIME()
WHERE CourtId = 'C1000001-0000-0000-0000-000000000005';
PRINT N'[A] Cleanup: PricePerHour C5 đã reset về 100.000.';
GO