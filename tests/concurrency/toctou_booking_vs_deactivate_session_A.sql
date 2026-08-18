/* ============================================================
   BadmintonCourtManagement
   Script : toctou_booking_vs_deactivate_session_A.sql  (tests/concurrency)
   (di chuyển từ database/16_toctou_session_A.sql — demo/regression,
    KHÔNG thuộc canonical build 00->15)
   Window A - CUSTOMER booker
   Nội dung:
     TOC-01: REGRESSION TOCTOU (KNOWN-09 FIX trong sp_BookCourt).
       Người đặt sân (A) vs người ngừng hoạt động sân (B = MANAGER) cạnh tranh
       trên cùng court. B nắm UPDLOCK sân, READY; A gọi sp_BookCourt chạy:
         (1) check pre-txn: sân vẫn ACTIVE -> đọc qua (đang còn mở khóa B)
         (2) vào transaction, chờ khóa UPDLOCK (bị B giữ) -> BLOCK
       B UPDATE IsActive=0 + COMMIT => khóa nhả, A được cấp khóa.
       Với FIX: sp_BookCourt ĐỌC LẠI IsActive DƯỚI khóa -> thấy 0 -> THROW 50013,
       KHÔNG tạo PENDING (đúng contract).
       Không có FIX: A bỏ qua re-check và INSERT PENDING trên sân đã inactive
       (TOCTOU).
     KẾT LUẬN TOC-01: phải in THROW 50013 + KHÔNG có PENDING mới trên C1.
   CÁCH CHẠY:
     1. Window A chạy toctou_booking_vs_deactivate_session_A.sql
     2. Trong ~60 giây Window B chạy toctou_booking_vs_deactivate_session_B.sql
     3. Đồng bộ bằng cờ bảng _TOCTouSync (không cần canh giờ chính xác).
     4. Sau khi cả 2 xong: A in ASSERTION PASS/FAIL.
   ============================================================ */

USE BadmintonCourtManagement;
GO
SET NOCOUNT ON;
SET XACT_ABORT OFF;
GO

-- ============================================================
-- Bảng cờ đồng bộ test (drop cuối cả 2 session)
-- ============================================================
IF OBJECT_ID('dbo._TOCTouSync', 'U') IS NULL
    CREATE TABLE dbo._TOCTouSync (Flag NVARCHAR(60) PRIMARY KEY, SetAt DATETIME2 NOT NULL DEFAULT SYSDATETIME());
-- Chỉ dọn cờ của riêng Window A để không xóa cờ B đang dùng
DELETE FROM dbo._TOCTouSync WHERE Flag IN (N'TOC_A_START', N'TOC_A_DONE');
GO

-- Court mục tiêu: C1, khung tương lai D2[07:00-08:00] (trống theo seed)
DECLARE @court UNIQUEIDENTIFIER = N'C1000001-0000-0000-0000-000000000001';
DECLARE @d2  DATE = DATEADD(DAY, 2, CAST(GETDATE() AS DATE));
DECLARE @s   datetime2(0) = DATETIMEFROMPARTS(YEAR(@d2),MONTH(@d2),DAY(@d2),7,0,0,0);
DECLARE @e   datetime2(0) = DATETIMEFROMPARTS(YEAR(@d2),MONTH(@d2),DAY(@d2),8,0,0,0);
DECLARE @cus1 UNIQUEIDENTIFIER = N'A1000001-0000-0000-0000-000000000004';

-- Báo sẵn sàng để B biết A đã vào (A sẽ chờ cờ TOC_B_HOLD)
INSERT INTO dbo._TOCTouSync(Flag) SELECT N'TOC_A_START' WHERE NOT EXISTS (SELECT 1 FROM dbo._TOCTouSync WHERE Flag = N'TOC_A_START');

-- ============================================================
-- TOC-01 : A cạnh tranh với B (deactivate) trên cùng court
-- ============================================================
DECLARE @tocErr  INT = 0;
DECLARE @tocMsg  NVARCHAR(400) = N'';
DECLARE @bid UNIQUEIDENTIFIER = NULL;
DECLARE @cost DECIMAL(12,0) = NULL;
DECLARE @waited INT = 0;

-- Chờ B nắm UPDLOCK sân (cờ TOC_B_HOLD), tối đa 60 giây
WHILE NOT EXISTS (SELECT 1 FROM dbo._TOCTouSync WHERE Flag = N'TOC_B_HOLD') AND @waited < 60
BEGIN
    WAITFOR DELAY '00:00:01';
    SET @waited = @waited + 1;
END;

IF NOT EXISTS (SELECT 1 FROM dbo._TOCTouSync WHERE Flag = N'TOC_B_HOLD')
BEGIN
    PRINT N'[TOC-01-WindowA] Timeout chờ TOC_B_HOLD (B không chạy?) - FAIL';
END
ELSE
BEGIN
    PRINT N'[TOC-01-WindowA] B đã giữ UPDLOCK sân. A gọi sp_BookCourt (phải bị chặn khóa, rồi reject sau khi B deactivate+commit)...';
    BEGIN TRY
        EXEC dbo.sp_Login @Username=N'customer1', @Password=N'cus1pass';
        EXEC dbo.sp_BookCourt @UserId=@cus1, @CourtId=@court, @StartTime=@s, @EndTime=@e,
             @BookingId=@bid OUTPUT, @TotalCost=@cost OUTPUT;
        PRINT N'[TOC-01-WindowA] sp_BookCourt: SUCCESS (sai - không bị từ chối!)';
    END TRY
    BEGIN CATCH
        SET @tocErr = ERROR_NUMBER();
        SET @tocMsg = ERROR_MESSAGE();
    END CATCH;

    IF @tocErr = 50013
        PRINT N'[TOC-01-WindowA] sp_BookCourt bị từ chối 50013 (sân inactive) sau khi B deactivate+commit - TOCTOU FIX hoạt động.';
    ELSE IF @tocErr <> 0
        PRINT N'[TOC-01-WindowA] Lỗi khác: ' + CAST(@tocErr AS VARCHAR(10)) + N' ' + @tocMsg;
END;

-- Báo A xong; chờ B xong (TOC_B_DONE) rồi verify
INSERT INTO dbo._TOCTouSync(Flag) SELECT N'TOC_A_DONE' WHERE NOT EXISTS (SELECT 1 FROM dbo._TOCTouSync WHERE Flag = N'TOC_A_DONE');
SET @waited = 0;
WHILE NOT EXISTS (SELECT 1 FROM dbo._TOCTouSync WHERE Flag = N'TOC_B_DONE') AND @waited < 60
BEGIN
    WAITFOR DELAY '00:00:01';
    SET @waited = @waited + 1;
END;
GO

-- ============================================================
-- ASSERTION TOC-01: court inactive + không có PENDING mới trên khung đó
-- ============================================================
DECLARE @d2 DATE = DATEADD(DAY, 2, CAST(GETDATE() AS DATE));
DECLARE @s  datetime2(0) = DATETIMEFROMPARTS(YEAR(@d2),MONTH(@d2),DAY(@d2),7,0,0,0);
DECLARE @e  datetime2(0) = DATETIMEFROMPARTS(YEAR(@d2),MONTH(@d2),DAY(@d2),8,0,0,0);
DECLARE @court UNIQUEIDENTIFIER = N'C1000001-0000-0000-0000-000000000001';
DECLARE @active BIT;
DECLARE @pend INT;
SELECT @active = IsActive FROM dbo.Courts WHERE CourtId = @court;
SELECT @pend = COUNT(*) FROM dbo.Bookings
WHERE CourtId = @court AND Status = N'PENDING'
  AND StartTime = @s AND EndTime = @e;  -- chỉ đếm PENDING đúng khung giao dịch đang tranh chấp

IF @active = 0 AND @pend = 0
    PRINT N'[TOC-01] ASSERTION PASS: court inactive (IsActive=0) và KHÔNG có PENDING mới trên khung D2[07-08] - không TOCTOU.';
ELSE
    PRINT N'[TOC-01] ASSERTION FAIL: active=' + CAST(@active AS VARCHAR(1)) + N', PENDING khung này=' + CAST(@pend AS VARCHAR(3));

-- Dọn cờ của demo này (2 script; để script final dọn bảng)
GO