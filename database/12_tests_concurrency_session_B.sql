/* ============================================================
   BadmintonCourtManagement
   Script : 12_tests_concurrency_session_B.sql   (SSMS Window B)
   Nội dung:
     CC-01: approve b9 (PENDING overlap với b4) - một session thắng, một bị từ chối
     CC-02: UPDATE Courts C5 trong lúc Window A đang giữ khóa -> bị block, không lost update
   CÁCH CHẠY: xem hướng dẫn script 11.
     - Window B chạy TRONG VÒNG ~60 giây sau khi Window A chạy script 11.
     - Mọi đồng bộ qua cờ _CCTestSync (B chờ CC01_A_READY / CC02_A_HOLD),
       không cần canh giờ chính xác.
   Option A: manager phải login (sp_ApproveBooking cần SESSION_CONTEXT).
   ============================================================ */

USE BadmintonCourtManagement;
GO
SET NOCOUNT ON;
SET XACT_ABORT OFF;
GO

-- Bảng cờ đồng bộ test (A tạo; B tạo lại nếu chưa có - không xóa nội dung của A)
IF OBJECT_ID('dbo._CCTestSync', 'U') IS NULL
    CREATE TABLE dbo._CCTestSync (Flag NVARCHAR(60) PRIMARY KEY, SetAt DATETIME2 NOT NULL DEFAULT SYSDATETIME());
GO

-- ============================================================
-- CC-01 Window B : approve b9
-- Nếu A đã approve b4 trước đó -> b9 bị từ chối (50035) → PHÙ HỢP.
-- Nếu B chạy trước A -> b9 BOOKED, A sẽ bị chặn. Đều hợp lệ, chỉ 1 thắng.
-- ============================================================
-- Đợi A hoàn tất reset (cờ CC01_A_READY) rồi mới vào cuộc đua
PRINT N'[CC-01-WindowB] Đợi Window A sẵn sàng (cờ CC01_A_READY)...';
DECLARE @w1 INT = 0;
WHILE @w1 < 600 AND NOT EXISTS (SELECT 1 FROM dbo._CCTestSync WHERE Flag = N'CC01_A_READY')
BEGIN
    WAITFOR DELAY '00:00:00:100';
    SET @w1 = @w1 + 1;
END
IF NOT EXISTS (SELECT 1 FROM dbo._CCTestSync WHERE Flag = N'CC01_A_READY')
    PRINT N'[CC-01-WindowB] >>> CẢNH BÁO: không thấy Window A (timeout 60s). Vẫn thử approve của mình. <<<';

EXEC dbo.sp_Login @Username=N'manager', @Password=N'manager123';
INSERT INTO dbo._CCTestSync (Flag) VALUES (N'CC01_B_READY');
PRINT N'[CC-01-WindowB] >>> B sẵn sàng - đua approve b9 với Window A. <<<';
BEGIN TRY
    -- Đua approve b9 (A đang approve b4 cùng lúc; ai lấy khóa C1 trước thì thắng)
    EXEC dbo.sp_ApproveBooking @SessionUserId='A1000001-0000-0000-0000-000000000001',
                               @BookingId='B1000001-0000-0000-0000-000000000009';
    PRINT N'[CC-01-WindowB] b9 đã BOOKED thành công.';
END TRY
BEGIN CATCH
    PRINT N'[CC-01-WindowB] b9 approve bị từ chối (hợp lệ nếu b4 đã BOOKED trước): ' + ERROR_MESSAGE();
END CATCH;
GO

-- Assertion CC-01: tối đa 1 trong (b4,b9) ở trạng thái BOOKED
DECLARE @booked INT =
    (SELECT COUNT(*) FROM dbo.Bookings
     WHERE BookingId IN ('B1000001-0000-0000-0000-000000000004','B1000001-0000-0000-0000-000000000009')
       AND Status = N'BOOKED');
SELECT BookingId, Status
FROM dbo.Bookings
WHERE BookingId = 'B1000001-0000-0000-0000-000000000009';
IF @booked <= 1
    PRINT N'[CC-01-WindowB] ASSERTION PASS: tối đa 1 trong (b4,b9) BOOKED.';
ELSE
    PRINT N'[CC-01-WindowB] ASSERTION FAIL: cả 2 đều BOOKED (sai)!';
PRINT N'[CC-01-WindowB] >>> CC-02 sẽ tự đồng bộ: chờ A báo CC02_A_HOLD (không cần thao tác tay). <<<';
GO

-- ============================================================
-- CC-02 Window B : update cùng dòng sân C5
-- Window A đang giữ khóa (UPDATE chưa commit). Lệnh này sẽ BLOCKED
-- tới khi A commit, sau đó ghi tiếp -> không mất cập nhật.
-- ============================================================
PRINT N'[CC-02-WindowB] Đợi Window A giữ khóa C5 (cờ CC02_A_HOLD)...';
-- A đặt cờ A_HOLD TRONG transaction (chưa COMMIT) ngay sau khi UPDATE C5 đã giữ khóa,
-- nên B phải đọc NOLOCK để thấy cờ đúng lúc A đang giữ khóa -> UPDATE của B
-- CHẮC CHẮN bị block (không phải chờ may mắn).
DECLARE @w2 INT = 0;
WHILE @w2 < 600 AND NOT EXISTS (SELECT 1 FROM dbo._CCTestSync WITH (NOLOCK) WHERE Flag = N'CC02_A_HOLD')
BEGIN
    WAITFOR DELAY '00:00:00:100';
    SET @w2 = @w2 + 1;
END
IF NOT EXISTS (SELECT 1 FROM dbo._CCTestSync WITH (NOLOCK) WHERE Flag = N'CC02_A_HOLD')
    PRINT N'[CC-02-WindowB] >>> CẢNH BÁO: không thấy A giữ khóa (timeout 60s) - có thể không bị block. <<<';

-- Báo sẵn sàng NGAY TRƯỚC khi UPDATE: A chỉ COMMIT sau khi thấy cờ này,
-- nên UPDATE này CHẮC CHẮN gặp khóa của A đang giữ (block thật).
INSERT INTO dbo._CCTestSync (Flag) VALUES (N'CC02_B_READY');
PRINT N'[CC-02-WindowB] UPDATE C5 (sẽ bị block tới khi Window A COMMIT)...';
UPDATE dbo.Courts SET PricePerHour = 120000, UpdatedAt = SYSDATETIME()
WHERE CourtId = 'C1000001-0000-0000-0000-000000000005';
PRINT N'[CC-02-WindowB] Update hoàn tất sau khi hết block. Giá cuối = 120000 (không lost update).';
INSERT INTO dbo._CCTestSync (Flag) VALUES (N'CC02_B_DONE');
PRINT N'[CC-02-WindowB] ASSERTION (xem Window A): giá cuối khi A đọc phải là 120000.';
GO