/* ============================================================
   BadmintonCourtManagement
   Script : 11_tests_concurrency_session_A.sql   (SSMS Window A)
   Nội dung:
     CC-01: 2 session approve 2 PENDING overlap cùng sân -> tối đa 1 BOOKED
     CC-02: Lock wait - không lost update, kết quả tuần tự hợp lệ
   Option A: mọi SP nghiệp vụ gọi sp_Login trước (SESSION_CONTEXT bắt buộc).

   CÁCH CHẠY (2 cửa sổ SSMS) - đồng bộ bằng cờ trong bảng _CCTestSync,
   KHÔNG cần canh giờ chính xác:
     STEP 1: Cửa sổ A chạy script này (11).
     STEP 2: Trong vòng ~60 giây, cửa sổ B chạy script 12.
     STEP 3: Cả 2 tự đồng bộ bằng cờ:
             - CC-01: A chờ cờ CC01_B_READY, B chờ cờ CC01_A_READY,
               rồi cả 2 đua approve (b4 vs b9) -> nhiều nhất 1 BOOKED.
             - CC-02: A giữ khóa C5 (cờ CC02_A_HOLD), B báo CC02_B_READY
               rồi UPDATE -> bị block tới khi A COMMIT; B ghi 120000,
               cờ CC02_B_DONE; A đọc 120000 -> không lost update.
     Nếu một cửa sổ không chạy, cửa sổ còn lại timeout (30 s/lần) và in FAIL
     rõ ràng, KHÔNG treo vô hạn.
   ============================================================ */

USE BadmintonCourtManagement;
GO
SET NOCOUNT ON;
SET XACT_ABORT OFF;
GO

-- ============================================================
-- Bảng cờ đồng bộ test (chỉ dùng cho demo 2-session; bị drop cuối script)
-- ============================================================
IF OBJECT_ID('dbo._CCTestSync', 'U') IS NULL
    CREATE TABLE dbo._CCTestSync (Flag NVARCHAR(60) PRIMARY KEY, SetAt DATETIME2 NOT NULL DEFAULT SYSDATETIME());
DELETE FROM dbo._CCTestSync;
GO

-- ============================================================
-- CC-01 : Approve cạnh tranh (contract 7.3)
-- Seed b4 & b9 là 2 PENDING overlap cùng sân C1, khung D1[06:00-09:00]
-- ============================================================
-- RESET: xóa booking do test tạo từ các lần chạy trước (09) để sân C1
-- không còn BOOKED overlap ngoài seed (tránh approve b4/b9 dính 50035).
DELETE n
FROM dbo.Notifications n
JOIN dbo.Bookings b ON b.BookingId = n.BookingId
WHERE b.BookingId NOT LIKE 'B1000001-0000-0000-0000-%';
GO
DELETE al
FROM dbo.ActivityLogs al
JOIN dbo.Bookings b ON b.BookingId = al.BookingId
WHERE b.BookingId NOT LIKE 'B1000001-0000-0000-0000-%';
GO
DELETE FROM dbo.Bookings
WHERE BookingId NOT LIKE 'B1000001-0000-0000-0000-%';
GO

-- Bước sẵn sàng: đưa b4/b9 về PENDING (chạy lại được)
DECLARE @d1 DATE = DATEADD(DAY,1,CAST(GETDATE() AS DATE));
DECLARE @t06 datetime2(0) = DATETIMEFROMPARTS(YEAR(@d1),MONTH(@d1),DAY(@d1),6,0,0,0);
DECLARE @t09 datetime2(0) = DATETIMEFROMPARTS(YEAR(@d1),MONTH(@d1),DAY(@d1),9,0,0,0);

-- Xóa audit/notification/booking cũ của b4,b9 trước khi reset (tránh vi phạm FK)
DELETE FROM dbo.ActivityLogs  WHERE BookingId IN ('B1000001-0000-0000-0000-000000000004','B1000001-0000-0000-0000-000000000009');
DELETE FROM dbo.Notifications WHERE BookingId IN ('B1000001-0000-0000-0000-000000000004','B1000001-0000-0000-0000-000000000009');
DELETE FROM dbo.Bookings WHERE BookingId IN
   ('B1000001-0000-0000-0000-000000000004', 'B1000001-0000-0000-0000-000000000009');

IF NOT EXISTS (SELECT 1 FROM dbo.Bookings WHERE BookingId = 'B1000001-0000-0000-0000-000000000004')
    INSERT INTO dbo.Bookings (BookingId, UserId, CourtId, StartTime, EndTime, Status, TotalCost)
    VALUES ('B1000001-0000-0000-0000-000000000004', 'A1000001-0000-0000-0000-000000000006',
            'C1000001-0000-0000-0000-000000000001', @t06, @t09, N'PENDING', 270000);

IF NOT EXISTS (SELECT 1 FROM dbo.Bookings WHERE BookingId = 'B1000001-0000-0000-0000-000000000009')
    INSERT INTO dbo.Bookings (BookingId, UserId, CourtId, StartTime, EndTime, Status, TotalCost)
    VALUES ('B1000001-0000-0000-0000-000000000009', 'A1000001-0000-0000-0000-000000000005',
            'C1000001-0000-0000-0000-000000000001', @t06, @t09, N'PENDING', 270000);

PRINT N'[CC-01] Đã sẵn sàng 2 PENDING overlap (b4, b9).';
-- Option A: manager phải đăng nhập trước khi dùng sp_ApproveBooking
EXEC dbo.sp_Login @Username=N'manager', @Password=N'manager123';
PRINT N'[CC-01-WindowA] Manager đã login (SESSION_CONTEXT sẵn sàng).';

-- Đồng bộ CC-01: A báo sẵn sàng, chờ B báo CC01_B_READY rồi cả 2 đua approve
INSERT INTO dbo._CCTestSync (Flag) VALUES (N'CC01_A_READY');
PRINT N'[CC-01-WindowA] >>> Đã sẵn sàng. Chờ Window B (script 12) báo CC01_B_READY (tối đa 30s)... <<<';
DECLARE @w1 INT = 0;
WHILE @w1 < 300 AND NOT EXISTS (SELECT 1 FROM dbo._CCTestSync WHERE Flag = N'CC01_B_READY')
BEGIN
    WAITFOR DELAY '00:00:00:100';
    SET @w1 = @w1 + 1;
END
IF NOT EXISTS (SELECT 1 FROM dbo._CCTestSync WHERE Flag = N'CC01_B_READY')
    PRINT N'[CC-01-WindowA] >>> CẢNH BÁO: không thấy Window B trong 30s - không phải race thật. <<<';
GO

-- ============================================================
-- CỬA SỔ A: approve b4 (đua với B đang approve b9)
-- ============================================================
PRINT N'[CC-01-WindowA] Bắt đầu approve b4...';
BEGIN TRY
    EXEC dbo.sp_ApproveBooking @SessionUserId='A1000001-0000-0000-0000-000000000001',
                               @BookingId='B1000001-0000-0000-0000-000000000004';
    PRINT N'[CC-01-WindowA] b4 đã BOOKED thành công.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 1205
        PRINT N'[CC-01-WindowA] >>> Lỗi 1205 trong approve (cần xem lại lock order).';
    ELSE
        PRINT N'[CC-01-WindowA] b4 approve bị từ chối: ' + ERROR_MESSAGE();
END CATCH;
GO

-- ============================================================
-- Kiểm chứng CC-01: tối đa 1 BOOKED overlap ở khung đó (assertion)
-- ============================================================
DECLARE @d1 DATE = DATEADD(DAY,1,CAST(GETDATE() AS DATE));
DECLARE @t06 datetime2(0) = DATETIMEFROMPARTS(YEAR(@d1),MONTH(@d1),DAY(@d1),6,0,0,0);
DECLARE @t09 datetime2(0) = DATETIMEFROMPARTS(YEAR(@d1),MONTH(@d1),DAY(@d1),9,0,0,0);
DECLARE @nBooked INT =
    (SELECT COUNT(*) FROM dbo.Bookings
     WHERE CourtId='C1000001-0000-0000-0000-000000000001'
       AND Status=N'BOOKED' AND StartTime < @t09 AND EndTime > @t06);
SELECT @nBooked AS BookedCount_on_slot;

SELECT BookingId, Status
FROM dbo.Bookings
WHERE BookingId IN ('B1000001-0000-0000-0000-000000000004','B1000001-0000-0000-0000-000000000009');

IF @nBooked <= 1
    PRINT N'[CC-01] ASSERTION PASS: BookedCount_on_slot <= 1 (không tạo 2 BOOKED overlap).';
ELSE
    PRINT N'[CC-01] ASSERTION FAIL: có hơn 1 BOOKED overlap trên sân!';
PRINT N'';
GO

-- ============================================================
-- CC-02 : Lock wait - không lost update (contract 7.5/CC-02)
-- A giữ khóa C5 (giá 150000); B báo sẵn sàng rồi UPDATE phải bị block.
-- Khi A COMMIT, B ghi 120000 (không lost). A đọc cuối = 120000.
-- ============================================================
PRINT N'[CC-02-WindowA] Bắt đầu: sẽ giữ khóa C5, nhiều nhất 1 khóa UPDATE tồn tại.';
EXEC dbo.sp_Login @Username=N'manager', @Password=N'manager123';
BEGIN TRAN;
    UPDATE dbo.Courts SET PricePerHour = 150000, UpdatedAt = SYSDATETIME()
    WHERE CourtId = 'C1000001-0000-0000-0000-000000000005';
    PRINT N'[CC-02-WindowA] Đã update C5=150000 (khóa đang giữ). Báo A_HOLD; chờ B báo CC02_B_READY...';
    INSERT INTO dbo._CCTestSync (Flag) VALUES (N'CC02_A_HOLD');

    DECLARE @w2 INT = 0;
    WHILE @w2 < 300 AND NOT EXISTS (SELECT 1 FROM dbo._CCTestSync WHERE Flag = N'CC02_B_READY')
    BEGIN
        WAITFOR DELAY '00:00:00:100';
        SET @w2 = @w2 + 1;
    END
    IF NOT EXISTS (SELECT 1 FROM dbo._CCTestSync WHERE Flag = N'CC02_B_READY')
        PRINT N'[CC-02-WindowA] >>> CẢNH BÁO: không thấy B báo CC02_B_READY (timeout 30s). <<<';
COMMIT;
PRINT N'[CC-02-WindowA] Commit xong (nhả khóa). B sẽ ghi tiếp 120000 sau khi hết block.';

-- Chờ B ghi xong (cờ CC02_B_DONE) rồi mới đọc giá cuối để không đọc trước khi B ghi
DECLARE @w3 INT = 0;
WHILE @w3 < 300 AND NOT EXISTS (SELECT 1 FROM dbo._CCTestSync WHERE Flag = N'CC02_B_DONE')
BEGIN
    WAITFOR DELAY '00:00:00:100';
    SET @w3 = @w3 + 1;
END
GO

-- Kiểm chứng giá cuối (phải là giá B ghi sau khi hết block = 120000)
DECLARE @price DECIMAL(12,0);
SELECT @price = PricePerHour FROM dbo.Courts WHERE CourtId='C1000001-0000-0000-0000-000000000005';
SELECT @price AS FinalPrice_C5;
IF @price = 120000
    PRINT N'[CC-02] ASSERTION PASS: giá cuối = 120000 (UPDATE của B không bị lost).';
ELSE
    PRINT N'[CC-02] ASSERTION FAIL (B không ghi được hoặc không chạy): giá cuối = ' + CAST(@price AS VARCHAR(20));
PRINT N'';
GO

-- Reset giá C5 về baseline 100000 (SAU khi A đã đọc FinalPrice) để không ảnh hưởng test khác
UPDATE dbo.Courts SET PricePerHour = 100000, UpdatedAt = SYSDATETIME()
WHERE CourtId = 'C1000001-0000-0000-0000-000000000005';
PRINT N'[CC-02-WindowA] Đã reset PricePerHour C5 về 100.000 (baseline).';

-- Dọn bảng cờ (chỉ khi B đã xong; nếu B chưa xong thì để lại để B không lỗi)
IF EXISTS (SELECT 1 FROM dbo._CCTestSync WHERE Flag = N'CC02_B_DONE')
BEGIN
    DROP TABLE dbo._CCTestSync;
    PRINT N'[CC-02-WindowA] Đã dọn bảng cờ _CCTestSync.';
END
GO

PRINT N'--- Hết 11_tests_concurrency_session_A.sql. Xem assertion PASS/FAIL ở trên. ---';
GO