/* ============================================================
   BadmintonCourtManagement
   Script : 11_tests_concurrency_session_A.sql   (SSMS Window A)
   Nội dung:
     CC-01: 2 session approve 2 PENDING overlap cùng sân -> tối đa 1 BOOKED
     CC-02: Lock wait - không lost update, kết quả theo thứ tự tuần tự hợp lệ
   CÁCH CHẠY:
     1. Mở 2 cửa sổ SSMS.
     2. Cửa sổ A chạy script này.
     3. Trong 5 giây A chờ, mở cửa sổ B và chạy script 12.
     4. Quay lại A xem kết quả.
   ============================================================ */

USE BadmintonCourtManagement;
GO
SET NOCOUNT ON;
SET XACT_ABORT OFF;
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
PRINT N'[CC-01] >>> 5 giây chờ: hãy mở SSMS Window B và chạy script 12_tests_concurrency_session_B.sql <<<';
WAITFOR DELAY '00:00:05';
GO

-- ============================================================
-- CỬA SỔ A: approve b4
-- ============================================================
PRINT N'[CC-01-WindowA] Bắt đầu approve b4...';
BEGIN TRY
    EXEC dbo.sp_ApproveBooking @SessionUserId='A1000001-0000-0000-0000-000000000001',
                               @BookingId='B1000001-0000-0000-0000-000000000004';
    PRINT N'[CC-01-WindowA] b4 đã BOOKED thành công.';
END TRY
BEGIN CATCH
    PRINT N'[CC-01-WindowA] b4 approve bị từ chối: ' + ERROR_MESSAGE();
END CATCH;
GO

-- ============================================================
-- Kiểm chứng: chỉ 1 BOOKED overlap ở khung đó
-- ============================================================
DECLARE @d1 DATE = DATEADD(DAY,1,CAST(GETDATE() AS DATE));
DECLARE @t06 datetime2(0) = DATETIMEFROMPARTS(YEAR(@d1),MONTH(@d1),DAY(@d1),6,0,0,0);
DECLARE @t09 datetime2(0) = DATETIMEFROMPARTS(YEAR(@d1),MONTH(@d1),DAY(@d1),9,0,0,0);
SELECT COUNT(*) AS BookedCount_on_slot
FROM dbo.Bookings
WHERE CourtId='C1000001-0000-0000-0000-000000000001'
  AND Status=N'BOOKED'
  AND StartTime < @t09 AND EndTime > @t06;

SELECT BookingId, Status
FROM dbo.Bookings
WHERE BookingId IN ('B1000001-0000-0000-0000-000000000004','B1000001-0000-0000-0000-000000000009');
GO

PRINT N'[CC-01] Nếu BookedCount_on_slot = 1 và b4/b9 không cùng BOOKED → PASS.';
PRINT N'';

-- ============================================================
-- CC-02 : Lock wait - không lost update (contract 7.5/CC-02)
-- Window A giữ khóa cây sân C5 rồi commit; Window B cập nhật cùng dòng
-- phải chờ rồi mới ghi -> không mất cập nhật.
-- ============================================================
PRINT N'[CC-02-WindowA] Bắt đầu tran: UPDATE Courts C5 (giữ khóa ~8 giây).';
BEGIN TRAN;
    UPDATE dbo.Courts SET PricePerHour = 150000, UpdatedAt = SYSDATETIME()
    WHERE CourtId = 'C1000001-0000-0000-0000-000000000005';
    PRINT N'[CC-02-WindowA] Đã update (khóa đang giữ). >>> 8 giây: chạy script 12 (Window B) <<<';
    WAITFOR DELAY '00:00:08';
COMMIT;
PRINT N'[CC-02-WindowA] Commit xong.';
GO

-- Kiểm chứng giá cuối (nên là giá Window B ghi sau khi hết block)
SELECT CourtId, PricePerHour FROM dbo.Courts WHERE CourtId='C1000001-0000-0000-0000-000000000005';
PRINT N'[CC-02] Nếu Window B update 120000, giá cuối = 120000 -> không mất cập nhật.';
GO