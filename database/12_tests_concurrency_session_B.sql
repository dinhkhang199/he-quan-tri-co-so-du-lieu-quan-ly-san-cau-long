/* ============================================================
   BadmintonCourtManagement
   Script : 12_tests_concurrency_session_B.sql   (SSMS Window B)
   Nội dung:
     CC-01: approve b9 (PENDING overlap với b4) - phải trả 50035 nếu b4 đã BOOKED
     CC-02: UPDATE Courts C5 trong lúc Window A đang giữ khóa -> bị block, không lost update
   CÁCH CHẠY: xem hướng dẫn script 11 (chạy cửa sổ B TRONG lúc A chờ).
   ============================================================ */

USE BadmintonCourtManagement;
GO
SET NOCOUNT ON;
SET XACT_ABORT OFF;
GO

-- ============================================================
-- CC-01 Window B : approve b9
-- Nếu A đã commit b4=BOOKED trước đó -> b9 bị từ chối (50035) → PHÙ HỢP.
-- Nếu cả hai cùng chạy tranh nhau -> một session thắng, một bị từ chối.
-- ============================================================
PRINT N'[CC-01-WindowB] Bắt đầu approve b9...';
BEGIN TRY
    EXEC dbo.sp_ApproveBooking @SessionUserId='A1000001-0000-0000-0000-000000000001',
                               @BookingId='B1000001-0000-0000-0000-000000000009';
    PRINT N'[CC-01-WindowB] b9 đã BOOKED thành công.';
END TRY
BEGIN CATCH
    PRINT N'[CC-01-WindowB] b9 approve bị từ chối (đúng nếu b4 đã BOOKED): ' + ERROR_MESSAGE();
END CATCH;
GO

-- Kiểm chứng b9 sau approve
SELECT BookingId, Status
FROM dbo.Bookings
WHERE BookingId = 'B1000001-0000-0000-0000-000000000009';
PRINT N'[CC-01-WindowB] Kết quả: tối đa 1 trong (b4,b9) ở trạng thái BOOKED.';
GO

-- ============================================================
-- CC-02 Window B : update cùng dòng sân C5
-- Window A đang giữ khóa (UPDATE chưa commit). Lệnh này sẽ BLOCKED
-- tới khi A commit, sau đó ghi tiếp -> không mất cập nhật.
-- ============================================================
PRINT N'[CC-02-WindowB] UPDATE C5 (sẽ bị block nếu A đang giữ khóa)...';
UPDATE dbo.Courts SET PricePerHour = 120000, UpdatedAt = SYSDATETIME()
WHERE CourtId = 'C1000001-0000-0000-0000-000000000005';
PRINT N'[CC-02-WindowB] Update hoàn tất sau khi hết block. Giá cuối = 120000.';
GO

-- Reset giá về baseline 100000 để không ảnh hưởng các test khác
UPDATE dbo.Courts SET PricePerHour = 100000, UpdatedAt = SYSDATETIME()
WHERE CourtId = 'C1000001-0000-0000-0000-000000000005';
PRINT N'[CC-02-WindowB] Đã reset PricePerHour C5 về 100.000 (baseline).';
GO