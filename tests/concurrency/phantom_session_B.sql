/* ============================================================
   PHANTOM READ DEMO - Session B  (tests/concurrency)
   Domain: Bookings, predicate CourtId C4 + 1 ngày cụ thể

   PHASE UNSAFE (READ COMMITTED của A):
     - chờ cờ PH_A_READY → INSERT sentinel B0000A00-...-0001 cùng predicate
       ngày D+10 rồi COMMIT → báo PH_B_UNSAFE_DONE → A đếm lại thấy +1 row
   PHASE FIXED  (SERIALIZABLE của A):
     - chờ cờ PH_FXA_START → báo PH_FXB_TRY rồi INSERT sentinel ...0002
       ngày D+11 → BỊ BLOCKED bởi range lock của A tới khi A commit → thoát,
       báo PH_FXB_DONE (không thể đổi count của A trong lúc A đang đọc)
   ============================================================ */

USE BadmintonCourtManagement;
GO
SET NOCOUNT ON;
SET XACT_ABORT OFF;
GO

IF OBJECT_ID('dbo._PhTestSync', 'U') IS NULL
    CREATE TABLE dbo._PhTestSync (Flag NVARCHAR(60) PRIMARY KEY, SetAt DATETIME2 NOT NULL DEFAULT SYSDATETIME());
-- KHÔNG xóa bảng ở B: A tạo mới đầu demo.
GO

-- ============================================================
-- PHASE UNSAFE
-- ============================================================
PRINT N'[B] ==== PHASE UNSAFE ====';
DECLARE @c4 UNIQUEIDENTIFIER = 'C1000001-0000-0000-0000-000000000004';
DECLARE @cus1 UNIQUEIDENTIFIER = 'A1000001-0000-0000-0000-000000000004';
DECLARE @s1 UNIQUEIDENTIFIER = 'B0000A00-0000-0000-0000-000000000001';
DECLARE @Dx DATE = DATEADD(DAY, 10, CAST(GETDATE() AS DATE));
DECLARE @waited INT = 0;

-- Chờ A mở tran và đọc lần 1 (PH_A_READY - A đã đếm trước)
WHILE NOT EXISTS (SELECT 1 FROM dbo._PhTestSync WHERE Flag = N'PH_A_READY') AND @waited < 90
BEGIN
    WAITFOR DELAY '00:00:01';
    SET @waited = @waited + 1;
END;
IF NOT EXISTS (SELECT 1 FROM dbo._PhTestSync WHERE Flag = N'PH_A_READY')
    PRINT N'[B] Timeout chờ A (UNSAFE).';

INSERT INTO dbo.Bookings (BookingId, UserId, CourtId, StartTime, EndTime, Status, TotalCost)
VALUES (@s1, @cus1, @c4,
        DATETIMEFROMPARTS(YEAR(@Dx), MONTH(@Dx), DAY(@Dx), 6, 0, 0, 0),
        DATETIMEFROMPARTS(YEAR(@Dx), MONTH(@Dx), DAY(@Dx), 7, 0, 0, 0),
        N'PENDING', 100000);
PRINT N'[B] Đã INSERT + COMMIT sentinel ...0001 (ngày ' + CONVERT(NVARCHAR(10), @Dx, 120) + N').';
INSERT INTO dbo._PhTestSync(Flag) SELECT N'PH_B_UNSAFE_DONE' WHERE NOT EXISTS (SELECT 1 FROM dbo._PhTestSync WHERE Flag=N'PH_B_UNSAFE_DONE');
GO

-- ============================================================
-- PHASE FIXED
-- ============================================================
PRINT N'[B] ==== PHASE FIXED ====';
DECLARE @c4b UNIQUEIDENTIFIER = 'C1000001-0000-0000-0000-000000000004';
DECLARE @cus1b UNIQUEIDENTIFIER = 'A1000001-0000-0000-0000-000000000004';
DECLARE @s2 UNIQUEIDENTIFIER = 'B0000A00-0000-0000-0000-000000000002';
DECLARE @Dx2 DATE = DATEADD(DAY, 11, CAST(GETDATE() AS DATE));
DECLARE @waited2 INT = 0;

-- Chờ A SERIALIZABLE đã đọc lần 1 (<PH_FXA_START>)
WHILE NOT EXISTS (SELECT 1 FROM dbo._PhTestSync WHERE Flag = N'PH_FXA_START') AND @waited2 < 90
BEGIN
    WAITFOR DELAY '00:00:01';
    SET @waited2 = @waited2 + 1;
END;
IF NOT EXISTS (SELECT 1 FROM dbo._PhTestSync WHERE Flag = N'PH_FXA_START')
    PRINT N'[B] Timeout chờ A (FIXED).';

-- Chờ 1s để A chắc chắn đã giữ range lock từ lần COUNT đầu
WAITFOR DELAY '00:00:01';

-- Báo "B sắp cố INSERT" (autocommit, A thấy được) — sau đó INSERT này bị BLOCKED
INSERT INTO dbo._PhTestSync(Flag) SELECT N'PH_FXB_TRY' WHERE NOT EXISTS (SELECT 1 FROM dbo._PhTestSync WHERE Flag=N'PH_FXB_TRY');
PRINT N'[B] INSERT sentinel ...0002 (ngày ' + CONVERT(NVARCHAR(10), @Dx2, 120) + N') → nếu A đang SERIALIZABLE, lệnh này BỊ BLOCKED tới khi A kết thúc test...';

INSERT INTO dbo.Bookings (BookingId, UserId, CourtId, StartTime, EndTime, Status, TotalCost)
VALUES (@s2, @cus1b, @c4b,
        DATETIMEFROMPARTS(YEAR(@Dx2), MONTH(@Dx2), DAY(@Dx2), 6, 0, 0, 0),
        DATETIMEFROMPARTS(YEAR(@Dx2), MONTH(@Dx2), DAY(@Dx2), 7, 0, 0, 0),
        N'PENDING', 100000);
PRINT N'[B] Hết block → INSERT thành công sau khi A kết thúc (A không thấy trong lúc đọc).';
INSERT INTO dbo._PhTestSync(Flag) SELECT N'PH_FXB_DONE' WHERE NOT EXISTS (SELECT 1 FROM dbo._PhTestSync WHERE Flag=N'PH_FXB_DONE');
GO