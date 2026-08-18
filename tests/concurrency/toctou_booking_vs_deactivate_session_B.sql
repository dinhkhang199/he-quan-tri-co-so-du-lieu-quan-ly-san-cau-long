/* ============================================================
   BadmintonCourtManagement
   Script : toctou_booking_vs_deactivate_session_B.sql  (tests/concurrency)
   (di chuyển từ database/17_toctou_session_B.sql — demo/regression,
    KHÔNG thuộc canonical build 00->15)
   Window B - MANAGER deactivator
   Nội dung:
     TOC-01: REGRESSION TOCTOU (KNOWN-09 FIX trong sp_BookCourt).
       Window B (MANAGER) nắm UPDLOCK sân C1 trong transaction chưa commit,
       báo cờ TOC_B_HOLD. Window A (CUSTOMER) gọi sp_BookCourt:
         - check pre-txn: sân ACTIVE (đọc qua - đây là cửa sổ TOCTOU)
         - vào transaction rồi BLOCK chờ khóa UPDLOCK (đang do B giữ)
       B giữ khóa đủ lâu (chờ A vào + 2 giây) rồi UPDATE IsActive=0 và COMMIT.
       -> khóa nhả, A được cấp khóa; với FIX sp_BookCourt đọc LẠI IsActive
          dưới khóa -> thấy 0 -> THROW 50013, không tạo PENDING.
     KẾT LUẬN: in rõ B deactivate + commit thành công trong khi A đang chờ.
   CÁCH CHẠY:
     1. Window A chạy toctou_booking_vs_deactivate_session_A.sql
     2. Trong ~30 giây Window B chạy toctou_booking_vs_deactivate_session_B.sql
     3. Đồng bộ bằng cờ _TOCTouSync; B tự chờ cờ TOC_A_START.
   ============================================================ */

USE BadmintonCourtManagement;
GO
SET NOCOUNT ON;
SET XACT_ABORT OFF;
GO

-- ============================================================
-- Bảng cờ đồng bộ test (tạo nếu chưa có; chỉ dọn cờ Window B)
-- ============================================================
IF OBJECT_ID('dbo._TOCTouSync', 'U') IS NULL
    CREATE TABLE dbo._TOCTouSync (Flag NVARCHAR(60) PRIMARY KEY, SetAt DATETIME2 NOT NULL DEFAULT SYSDATETIME());
DELETE FROM dbo._TOCTouSync WHERE Flag IN (N'TOC_B_HOLD', N'TOC_B_DONE');
GO

-- Court mục tiêu: C1 (cùng với Window A)
DECLARE @court UNIQUEIDENTIFIER = N'C1000001-0000-0000-0000-000000000001';
DECLARE @mgr   UNIQUEIDENTIFIER = N'A1000001-0000-0000-0000-000000000001';
DECLARE @waited INT = 0;

-- Chờ A báo sẵn sàng (tối đa 60 giây)
WHILE NOT EXISTS (SELECT 1 FROM dbo._TOCTouSync WHERE Flag = N'TOC_A_START') AND @waited < 60
BEGIN
    WAITFOR DELAY '00:00:01';
    SET @waited = @waited + 1;
END;

IF NOT EXISTS (SELECT 1 FROM dbo._TOCTouSync WHERE Flag = N'TOC_A_START')
BEGIN
    PRINT N'[TOC-01-WindowB] Timeout chờ TOC_A_START (A không chạy?) - FAIL';
END
ELSE
BEGIN
    PRINT N'[TOC-01-WindowB] A đã vào. B nắm UPDLOCK sân C1 (chưa commit)...';
    BEGIN TRY
        BEGIN TRAN;
            -- Giữ khóa UPDLOCK sân: cùng hint sp_DeactivateCourt/sp_BookCourt dùng
            SELECT CourtId FROM dbo.Courts WITH (UPDLOCK, ROWLOCK) WHERE CourtId = @court;
            PRINT N'[TOC-01-WindowB] Đã giữ UPDLOCK C1. Báo cờ TOC_B_HOLD, chờ 2s để A chắc chắn BLOCK trong sp_BookCourt...';
            INSERT INTO dbo._TOCTouSync(Flag) SELECT N'TOC_B_HOLD' WHERE NOT EXISTS (SELECT 1 FROM dbo._TOCTouSync WHERE Flag = N'TOC_B_HOLD');

            -- Chờ A kịp vào trong sp_BookCourt và BLOCK trên khóa này
            -- (A đã báo TOC_A_START trước khi gọi sp_BookCourt; trong lúc B giữ khóa
            --  A chắc chắn bị chặn ở SELECT UPDLOCK đầu tiên trong transaction)
            WAITFOR DELAY '00:00:04';

            -- DEACTIVATE: UPDATE IsActive=0, giữ transaction vài giây nữa để giao
            -- với A đang chờ, rồi COMMIT để nhả khóa cho A
            UPDATE dbo.Courts SET IsActive = 0, UpdatedAt = SYSDATETIME() WHERE CourtId = @court;
            PRINT N'[TOC-01-WindowB] Deactivate C1 (IsActive=0) trong transaction, chờ 2s để A vỡ khóa, rồi COMMIT...';
            WAITFOR DELAY '00:00:02';
        COMMIT;
        PRINT N'[TOC-01-WindowB] COMMIT xong (khóa nhả). A sẽ đánh giá lại sân dưới khóa.';
        INSERT INTO dbo._TOCTouSync(Flag) SELECT N'TOC_B_DONE' WHERE NOT EXISTS (SELECT 1 FROM dbo._TOCTouSync WHERE Flag = N'TOC_B_DONE');
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK;
        PRINT N'[TOC-01-WindowB] Lỗi Window B: ' + CAST(ERROR_NUMBER() AS VARCHAR(10)) + N' ' + ERROR_MESSAGE();
    END CATCH;
END;
GO