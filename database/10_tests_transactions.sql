/* ============================================================
   BadmintonCourtManagement
   Script : 10_tests_transactions.sql
   Mục đích: Transaction demo + Phantom Read (contract 7.2, 7.4)
   - TX-PART : transaction + rollback, không partial write
   - PH-01   : READ COMMITTED → phantom có thể xảy ra
   - PH-02   : SERIALIZABLE  → phantom bị ngăn, transaction đối thủ phải chờ
   CÁCH CHẠY PHANTOM: cần 2 cửa số SSMS.
   - Cửa sổ A: chạy script này (chạy hết).
   - Khi A đang hiện "ĐANG CHỜ ...", mở cửa sổ B, copy đoạn WINDOW B
     (phần comment tương ứng) vào và chạy, rồi quay lại chờ A kết thúc.
   ============================================================ */

USE BadmintonCourtManagement;
GO

SET NOCOUNT ON;
SET XACT_ABORT OFF;   -- phần demo phantom dùng tran mở thủ công
GO

DECLARE @c6 UNIQUEIDENTIFIER = 'C1000001-0000-0000-0000-000000000006';
DECLARE @d1 DATE = DATEADD(DAY,1,CAST(GETDATE() AS DATE));
DECLARE @t06 datetime2(0) = DATETIMEFROMPARTS(YEAR(@d1),MONTH(@d1),DAY(@d1),6,0,0,0);
DECLARE @n1 INT, @n2 INT;
GO   -- (biến được khai báo lại ở từng phần bên dưới cho rõ ràng)
GO

-- ============================================================
-- PH-01: READ COMMITTED → PHANTOM (chạy ở CỬA SỔ A)
-- ============================================================
USE BadmintonCourtManagement;
GO
SET NOCOUNT ON;
GO

DECLARE @c6 UNIQUEIDENTIFIER = 'C1000001-0000-0000-0000-000000000006';
DECLARE @d1 DATE = DATEADD(DAY,1,CAST(GETDATE() AS DATE));
DECLARE @t06 datetime2(0) = DATETIMEFROMPARTS(YEAR(@d1),MONTH(@d1),DAY(@d1),6,0,0,0);
DECLARE @n1 INT, @n2 INT;

SET TRANSACTION ISOLATION LEVEL READ COMMITTED;

PRINT N'';
PRINT N'=================================================================';
PRINT N'[PH-01] READ COMMITTED - PHANTOM DEMO';
PRINT N'  >>> Trong lúc A đang chờ "WAITFOR <<<", mở SSMS #2 và chạy:';
PRINT N'      +----------------------------------------------';
PRINT N'      |  USE BadmintonCourtManagement;               |';
PRINT N'      |  INSERT INTO dbo.Bookings                    |';
PRINT N'      |    (UserId, CourtId, StartTime, EndTime,     |';
PRINT N'      |     Status, TotalCost)                       |';
PRINT N'      |  SELECT ''A1000001-0000-0000-0000-000000000004'' |';
PRINT N'      |       , ''C1000001-0000-0000-0000-000000000006'' |';
PRINT N'      |       , DATETIMEFROMPARTS(YEAR(DATEADD(DAY,1,CAST(GETDATE() AS DATE))),MONTH(DATEADD(DAY,1,CAST(GETDATE() AS DATE))),DAY(DATEADD(DAY,1,CAST(GETDATE() AS DATE))),6,0,0,0)';
PRINT N'      |       , DATETIMEFROMPARTS(YEAR(DATEADD(DAY,1,CAST(GETDATE() AS DATE))),MONTH(DATEADD(DAY,1,CAST(GETDATE() AS DATE))),DAY(DATEADD(DAY,1,CAST(GETDATE() AS DATE))),7,0,0,0)';
PRINT N'      |       , N''PENDING'', 100000);               |';
PRINT N'      +----------------------------------------------';
PRINT N'=================================================================';

BEGIN TRAN;

    SELECT @n1 = COUNT(*) FROM dbo.Bookings
    WHERE CourtId = @c6 AND StartTime = @t06;
    PRINT N'[PH-01] Lần đọc 1: ' + CAST(@n1 AS VARCHAR(10)) + N' booking (trước khi B insert)';

    PRINT N'[PH-01] >>> ĐANG CHỜ 8 giây: chạy insert "WINDOW B" ở cửa sổ #2 rồi quay lại <<<';
    WAITFOR DELAY '00:00:08';

    SELECT @n2 = COUNT(*) FROM dbo.Bookings
    WHERE CourtId = @c6 AND StartTime = @t06;
    PRINT N'[PH-01] Lần đọc 2: ' + CAST(@n2 AS VARCHAR(10)) + N' booking (sau khi B commit)';

    IF @n2 > @n1
        PRINT N'[PH-01] >>> KẾT LUẬN: PHANTOM xảy ra trong READ COMMITTED (tập kết quả đổi sau commit của session khác).';
    ELSE
        PRINT N'[PH-01] Chưa thấy phantom - nhớ chạy insert ở cửa sổ #2 trong lúc WAITFOR.';

ROLLBACK;
GO

-- ------------------------------------------------------------
-- PH-02: SERIALIZABLE → KHÔNG phantom (chạy CỬA SỔ A, tiếp tục)
-- ============================================================
SET NOCOUNT ON;
GO
DECLARE @c6 UNIQUEIDENTIFIER = 'C1000001-0000-0000-0000-000000000006';
DECLARE @d1 DATE = DATEADD(DAY,1,CAST(GETDATE() AS DATE));
DECLARE @t06 datetime2(0) = DATETIMEFROMPARTS(YEAR(@d1),MONTH(@d1),DAY(@d1),6,0,0,0);
DECLARE @n1 INT, @n2 INT;

SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;

PRINT N'';
PRINT N'=================================================================';
PRINT N'[PH-02] SERIALIZABLE - PHANTOM KHÔNG XẢY RA';
PRINT N'  >>> Trong lúc A đang chờ, mở SSMS #2 và chạy cùng câu INSERT';
PRINT N'      (giống WINDOW B nhưng thay UserId bởi một CUSTOMER khác).';
PRINT N'      Câu INSERT của cửa sổ #2 sẽ BỊ TREO (blocked) tới khi A kết thúc.';
PRINT N'=================================================================';

BEGIN TRAN;

    SELECT @n1 = COUNT(*) FROM dbo.Bookings
    WHERE CourtId = @c6 AND StartTime = @t06;
    PRINT N'[PH-02] Lần đọc 1: ' + CAST(@n1 AS VARCHAR(10)) + N' booking';

    PRINT N'[PH-02] >>> ĐANG CHỜ 10 giây: chạy insert ở cửa sổ #2 (sẽ bị blocked) rồi quay lại <<<';
    WAITFOR DELAY '00:00:10';

    SELECT @n2 = COUNT(*) FROM dbo.Bookings
    WHERE CourtId = @c6 AND StartTime = @t06;
    PRINT N'[PH-02] Lần đọc 2: ' + CAST(@n2 AS VARCHAR(10)) + N' booking (ổn định vì B chưa ghi được)';

    IF @n1 = @n2
        PRINT N'[PH-02] >>> KẾT LUẬN: SERIALIZABLE ngăn phantom (predicate ổn định; insert đối thủ bị range lock chặn tới khi A kết thúc).';
    ELSE
        PRINT N'[PH-02] Có phantom - kiểm tra lại isolation level.';

ROLLBACK;   -- sau rollback, insert treo ở cửa sổ #2 mới hoàn tất
GO

-- Reset isolation level về mặc định
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
GO

PRINT N'';
PRINT N'--- Hết 10_tests_transactions.sql. Xem thêm 11/12 (concurrency), 13/14 (deadlock), 15 (backup/restore). ---';
GO