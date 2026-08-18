/* ============================================================
   PHANTOM READ DEMO - Session A  (tests/concurrency)
   Domain: Bookings trên 1 SÂN (C4) trong 1 NGÀY — predicate theo tập row

   CÁCH CHẠY (cờ _PhTestSync, không cần canh giờ một cách chính xác):
     1. Cửa sổ A chạy phantom_session_A.sql
     2. Trong ~5 giây cửa sổ B chạy phantom_session_B.sql

   PHASE UNSAFE (READ COMMITTED):
     - A mở tran, đếm predicate ngày D+10: n1
     - B INSERT 1 booking cùng predicate (sentinel ...001) rồi commit → cờ
     - A đếm lại: n2 > n1 → tập kết quả TĂNG THÊM ROW = PHANTOM READ
     - KẾT LUẬN UNSAFE: n2 > n1 (phantom xảy ra)
   PHASE FIXED (SERIALIZABLE):
     - A SERIALIZABLE, đếm predicate ngày D+11: f1 (range-scan giữ khóa)
     - B INSERT cùng predicate (sentinel ...002) → BỊ BLOCKED tới khi A xong
     - A đếm lại: f1 = f2 (ổn định) → PHANTOM bị ngăn, commit → B thoát
     - KẾT LUẬN FIXED  : f1 = f2 (không phantom)
   ============================================================ */

USE BadmintonCourtManagement;
GO
SET NOCOUNT ON;
SET XACT_ABORT OFF;
GO

DROP TABLE IF EXISTS dbo._PhTestSync;
CREATE TABLE dbo._PhTestSync (Flag NVARCHAR(60) PRIMARY KEY, SetAt DATETIME2 NOT NULL DEFAULT SYSDATETIME());
GO

-- ============================================================
-- Cleanup cũ (chạy lại được): 3 bước theo FK trước khi test
--   Notifications → ActivityLogs → Bookings (sentinel ...001/002)
-- ============================================================
DECLARE @s1 UNIQUEIDENTIFIER = 'B0000A00-0000-0000-0000-000000000001';
DECLARE @s2 UNIQUEIDENTIFIER = 'B0000A00-0000-0000-0000-000000000002';
DELETE n FROM dbo.Notifications n JOIN dbo.Bookings b ON b.BookingId = n.BookingId
WHERE b.BookingId IN (@s1, @s2);
DELETE al FROM dbo.ActivityLogs al JOIN dbo.Bookings b ON b.BookingId = al.BookingId
WHERE b.BookingId IN (@s1, @s2);
DELETE FROM dbo.Bookings WHERE BookingId IN (@s1, @s2);
GO

-- ============================================================
-- PHASE UNSAFE (READ COMMITTED) — ngày D+10
-- ============================================================
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
DECLARE @Dx Date = DATEADD(DAY, 10, CAST(GETDATE() AS Date));
DECLARE @c4 UNIQUEIDENTIFIER = 'C1000001-0000-0000-0000-000000000004';
DECLARE @n1 INT = -1, @n2 INT = -1;
DECLARE @waited INT = 0;
PRINT N'[A] ==== PHASE UNSAFE (READ COMMITTED) ====';

INSERT INTO dbo._PhTestSync(Flag) SELECT N'PH_A_READY' WHERE NOT EXISTS (SELECT 1 FROM dbo._PhTestSync WHERE Flag=N'PH_A_READY');

BEGIN TRAN;
    SELECT @n1 = COUNT(*) FROM dbo.Bookings
    WHERE CourtId = @c4 AND CAST(StartTime AS Date) = @Dx;
    PRINT N'[A] Lần đọc 1 (COUNT): ' + CAST(@n1 AS NVARCHAR(10));

    -- Chờ B INSERT + COMMIT booking sentinel ...001 (cùng predicate)
    WHILE NOT EXISTS (SELECT 1 FROM dbo._PhTestSync WHERE Flag = N'PH_B_UNSAFE_DONE') AND @waited < 90
    BEGIN
        WAITFOR DELAY '00:00:01';
        SET @waited = @waited + 1;
    END;
    IF NOT EXISTS (SELECT 1 FROM dbo._PhTestSync WHERE Flag = N'PH_B_UNSAFE_DONE')
        PRINT N'[A] Timeout chờ B (UNSAFE).';

    SELECT @n2 = COUNT(*) FROM dbo.Bookings
    WHERE CourtId = @c4 AND CAST(StartTime AS Date) = @Dx;
    PRINT N'[A] Lần đọc 2 (COUNT): ' + CAST(@n2 AS NVARCHAR(10));

    IF @n2 > @n1
        PRINT N'[A] >>> Tập kết quả TĂNG THÊM ROW sau commit của B → PHANTOM READ: ' + CAST(@n1 AS NVARCHAR(10)) + N' → ' + CAST(@n2 AS NVARCHAR(10)) + N'.';
    ELSE
        PRINT N'[A] >>> Không thấy phantom (B chưa chạy kịp?)';
COMMIT;
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
GO

-- ============================================================
-- PHASE FIXED (SERIALIZABLE) — ngày D+11
-- ============================================================
SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
DECLARE @Dx2 DATE = DATEADD(DAY, 11, CAST(GETDATE() AS DATE));
DECLARE @c4b2 UNIQUEIDENTIFIER = 'C1000001-0000-0000-0000-000000000004';
DECLARE @f1 INT = -1, @f2 INT = -1;
DECLARE @waited2 INT = 0;
PRINT N'[A] ==== PHASE FIXED (SERIALIZABLE) ====';

INSERT INTO dbo._PhTestSync(Flag) SELECT N'PH_FXA_START' WHERE NOT EXISTS (SELECT 1 FROM dbo._PhTestSync WHERE Flag=N'PH_FXA_START');

BEGIN TRAN;
    SELECT @f1 = COUNT(*) FROM dbo.Bookings
    WHERE CourtId = @c4b2 AND CAST(StartTime AS Date) = @Dx2;
    PRINT N'[A] FIXED lần đọc 1 (COUNT): ' + CAST(@f1 AS NVARCHAR(10));

    -- Chờ B (đợi PH_FXA_START + 1s) đã chạy tới INSERT → đang BLOCKED ở range lock.
    -- Dùng NOLOCK khi đọc bảng cờ: nếu không, A (SERIALIZABLE) sẽ khóa CHÍNH bảng
    -- _PhTestSync và chặn B cắm cờ PH_FXB_TRY → stalemate (A chờ cờ B block bởi A).
    WHILE NOT EXISTS (SELECT 1 FROM dbo._PhTestSync WITH (NOLOCK) WHERE Flag = N'PH_FXB_TRY') AND @waited2 < 90
    BEGIN
        WAITFOR DELAY '00:00:01';
        SET @waited2 = @waited2 + 1;
    END;
    IF NOT EXISTS (SELECT 1 FROM dbo._PhTestSync WITH (NOLOCK) WHERE Flag = N'PH_FXB_TRY')
        PRINT N'[A] Timeout chờ B (FIXED / TRY).';

    -- Chờ thêm 2s để B chắc chắn đã bị BLOCK (đang thử INSERT)
    WAITFOR DELAY '00:00:02';

    SELECT @f2 = COUNT(*) FROM dbo.Bookings
    WHERE CourtId = @c4b2 AND CAST(StartTime AS Date) = @Dx2;
    PRINT N'[A] FIXED lần đọc 2 (COUNT): ' + CAST(@f2 AS NVARCHAR(10));

    IF @f1 = @f2
        PRINT N'[A] >>> SERIALIZABLE: range lock giữ predicate ổn định (f1 = f2) → PHANTOM bị ngăn.';
    ELSE
        PRINT N'[A] >>> FAIL: count đổi (phantom vẫn lọt)?';
COMMIT;
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;

-- Chờ B thoát insert (PH_FXB_DONE) để đóng demo
INSERT INTO dbo._PhTestSync(Flag) SELECT N'PH_A_DONE' WHERE NOT EXISTS (SELECT 1 FROM dbo._PhTestSync WHERE Flag=N'PH_A_DONE');
SET @waited2 = 0;
WHILE NOT EXISTS (SELECT 1 FROM dbo._PhTestSync WHERE Flag = N'PH_FXB_DONE') AND @waited2 < 90
BEGIN
    WAITFOR DELAY '00:00:01';
    SET @waited2 = @waited2 + 1;
END;
IF NOT EXISTS (SELECT 1 FROM dbo._PhTestSync WHERE Flag = N'PH_FXB_DONE')
    PRINT N'[A] Timeout chờ B (FIXED / DONE).';
GO

-- ============================================================
-- Cleanup: 3 bước theo FK (Notifications → ActivityLogs → Bookings)
-- ============================================================
DECLARE @s1b UNIQUEIDENTIFIER = 'B0000A00-0000-0000-0000-000000000001';
DECLARE @s2b UNIQUEIDENTIFIER = 'B0000A00-0000-0000-0000-000000000002';
DELETE n FROM dbo.Notifications n JOIN dbo.Bookings b ON b.BookingId = n.BookingId
WHERE b.BookingId IN (@s1b, @s2b);
DELETE al FROM dbo.ActivityLogs al JOIN dbo.Bookings b ON b.BookingId = al.BookingId
WHERE b.BookingId IN (@s1b, @s2b);
DELETE FROM dbo.Bookings WHERE BookingId IN (@s1b, @s2b);
PRINT N'[A] Cleanup hoàn tất (sentinel B0000A00-...-0001/0002): Notifications → ActivityLogs → Bookings.';
GO