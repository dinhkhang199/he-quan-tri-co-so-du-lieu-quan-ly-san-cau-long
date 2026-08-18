/* ============================================================
   BadmintonCourtManagement
   Script : 13_deadlock_demo_session_A.sql   (SSMS Window A)
Nội dung:
     DL-01: tái hiện DEADLOCK (khóa chéo Courts <> Bookings) -> một trong hai
            session là victim (1205). Các UPDATE khóa chéo được bọc TRY/CATCH
            nên dù A hay B là victim, cả 2 đều tiếp tục chạy DL-02/DL-03.
     DL-02: fix bằng lock ordering nhất quán (Court -> Booking) -> hết deadlock
     DL-03: REGRESSION - Approve (A) vs Cancel (B) bằng SP sản xuất thật trên
            cùng booking PENDING (sân C3) -> không deadlock 1205.
   CÁCH CHẠY:
      1. Mở 2 cửa sổ SSMS.
      2. Chạy 13 ở cửa sổ A và 14 ở cửa sổ B GẦN NHƯ CÙNG LÚC (không quá 2 giây).
      3. Xem 1 trong 2 cửa sổ in "VICTIM: bị deadlock (1205)" - đó là DL-01.
      4. Cả 2 cửa sổ chạy tiếp DL-02 (không deadlock) và DL-03 (không deadlock)
         rồi in ASSERTION PASS/FAIL ở cuối.
   ============================================================ */

USE BadmintonCourtManagement;
GO
SET NOCOUNT ON;
SET XACT_ABORT OFF;
GO

-- Bảng cờ đồng bộ cho DL-03 (chi tiết DL-03 được đồng bộ để B không chạy
-- cancel trước khi A đã tạo booking). A tạo mới ở đầu như các demo khác.
DROP TABLE IF EXISTS dbo._DLTestSync;
CREATE TABLE dbo._DLTestSync (Flag NVARCHAR(60) PRIMARY KEY, SetAt DATETIME2 NOT NULL DEFAULT SYSDATETIME());
GO

-- ============================================================
-- DL-01 (buggy): A khóa Courts C1 -> chờ -> khóa Bookings b1
-- B khóa Bookings b1 -> chờ -> khóa Courts C1   (xem 14)
-- -> chu kỳ chờ khóa = deadlock
-- ============================================================
PRINT N'[DL-01-WindowA] Bắt đầu: A muốn khóa theo thứ tự Courts(C1) -> Bookings(b1) (kịch bản lỗi).';
DECLARE @dl1VictimA INT = 0;
BEGIN TRY
    BEGIN TRAN;
        UPDATE dbo.Courts SET UpdatedAt = SYSDATETIME()
        WHERE CourtId = 'C1000001-0000-0000-0000-000000000001';
        PRINT N'[DL-01-WindowA] Đã khóa Courts C1. Chờ 3 giây để B khóa Bookings b1...';
        WAITFOR DELAY '00:00:03';

        -- Bước này A phải chờ khóa Bookings b1 (đang do B giữ) -> chu kỳ chờ -> deadlock
        UPDATE dbo.Bookings SET UpdatedAt = SYSDATETIME()
        WHERE BookingId = 'B1000001-0000-0000-0000-000000000001';
        PRINT N'[DL-01-WindowA] Đã ghi Bookings b1 (không bị deadlock).';
    COMMIT;
    PRINT N'[DL-01-WindowA] Transaction A commit thành công (deadlock không rơi vào A).';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 1205
    BEGIN
        SET @dl1VictimA = 1;
        PRINT N'[DL-01-WindowA] >>> VICTIM: bị deadlock (1205). Transaction bị ROLLBACK - đúng bản chất deadlock.';
    END
    ELSE
        PRINT N'[DL-01-WindowA] Lỗi khác: ' + CAST(ERROR_NUMBER() AS VARCHAR(10)) + N' ' + ERROR_MESSAGE();
    IF XACT_STATE() <> 0 ROLLBACK;
END CATCH
IF @dl1VictimA = 1
    PRINT N'[DL-01-WindowA] Kết luận DL-01: A là deadlock victim.';
ELSE
    PRINT N'[DL-01-WindowA] Kết luận DL-01: deadlock có victim (B) - A commit bình thường.';
GO

-- ============================================================
-- DL-02 (fix): cả A và B đều khóa theo cùng thứ tự Courts -> Bookings
-- Không còn chu kỳ chờ -> không deadlock. (chạy cùng với 14 phần DL-02)
-- ============================================================
PRINT N'';
PRINT N'[DL-02-WindowA] FIX: lock ordering nhất quán Court -> Booking.';
BEGIN TRY
    BEGIN TRAN;
        UPDATE dbo.Courts SET UpdatedAt = SYSDATETIME()
        WHERE CourtId = 'C1000001-0000-0000-0000-000000000002';
        PRINT N'[DL-02-WindowA] Đã khóa Courts C2. Chờ 3 giây...';
        WAITFOR DELAY '00:00:03';
        UPDATE dbo.Bookings SET UpdatedAt = SYSDATETIME()
        WHERE BookingId = 'B1000001-0000-0000-0000-000000000005';
        PRINT N'[DL-02-WindowA] Đã khóa Bookings b5. Hoàn tất.';
    COMMIT;
    PRINT N'[DL-02-WindowA] >>> Commit thành công - KHÔNG deadlock với lock ordering nhất quán.';
END TRY
BEGIN CATCH
    PRINT N'[DL-02-WindowA] Lỗi: ' + ERROR_MESSAGE();
    IF XACT_STATE() <> 0 ROLLBACK;
END CATCH;
GO

-- ============================================================
-- DL-03 (REGRESSION - dùng SP sản xuất thật): Approve vs Cancel/Reject
-- cùng 1 booking PENDING trên cùng sân, chạy 2 session song song.
-- Mục đích: chứng minh sp_ApproveBooking và sp_CancelBooking/sp_RejectBooking
-- dùng CHUNG một thứ tự khóa Court -> Booking nên KHÔNG tạo deadlock 1205
-- (review P0 lock order). Window A giữ khóa qua nested transaction để
-- Window B bị block xác định (không phải chờ may mắn).
-- ============================================================
PRINT N'';
PRINT N'[DL-03-WindowA] REGRESSION: Approve (A) vs Cancel (B) cùng booking - lock ordering Court->Booking.';

-- Dọn booking DL-03 cũ (chạy lại được)
DELETE FROM dbo.ActivityLogs  WHERE BookingId = 'B0000000-0000-0000-0000-D03000000001';
DELETE FROM dbo.Notifications WHERE BookingId = 'B0000000-0000-0000-0000-D03000000001';
DELETE FROM dbo.Bookings     WHERE BookingId = 'B0000000-0000-0000-0000-D03000000001';
GO

DECLARE @dl3Court UNIQUEIDENTIFIER = 'C1000001-0000-0000-0000-000000000003';
DECLARE @dl3Start datetime2(0), @dl3End datetime2(0);
DECLARE @dl3 DATE = DATEADD(DAY,2,CAST(GETDATE() AS DATE));
SET @dl3Start = DATETIMEFROMPARTS(YEAR(@dl3),MONTH(@dl3),DAY(@dl3),18,0,0,0);
SET @dl3End   = DATETIMEFROMPARTS(YEAR(@dl3),MONTH(@dl3),DAY(@dl3),19,0,0,0);

-- Tạo booking PENDING dùng cho kịch bản (nếu chưa có)
IF NOT EXISTS (SELECT 1 FROM dbo.Bookings WHERE BookingId='B0000000-0000-0000-0000-D03000000001')
    INSERT INTO dbo.Bookings (BookingId, UserId, CourtId, StartTime, EndTime, Status, TotalCost)
    VALUES ('B0000000-0000-0000-0000-D03000000001', 'A1000001-0000-0000-0000-000000000005',
            @dl3Court, @dl3Start, @dl3End, N'PENDING', 100000);

-- Báo A đã tạo booking (autocommit) -> B (Window B) chỉ cancel sau khi đã có booking
INSERT INTO dbo._DLTestSync(Flag) SELECT N'DL3_A_READY' WHERE NOT EXISTS (SELECT 1 FROM dbo._DLTestSync WHERE Flag=N'DL3_A_READY');

-- Option A: manager phải login trước khi dùng SP nghiệp vụ
EXEC dbo.sp_Login @Username=N'manager', @Password=N'manager123';

PRINT N'[DL-03-WindowA] >>> 5 giây: chạy 14_deadlock_demo_session_B.sql (Window B) NGAY <<<';
GO

-- A giữ khóa qua nested transaction: sp_ApproveBooking tự commit nội bộ,
-- khóa vẫn giữ tới khi transaction ngoài COMMIT -> ép B phải block.
DECLARE @dl3Deadlock INT = 0;
BEGIN TRAN;
    BEGIN TRY
        EXEC dbo.sp_ApproveBooking @SessionUserId='A1000001-0000-0000-0000-000000000001',
                                   @BookingId='B0000000-0000-0000-0000-D03000000001';
        PRINT N'[DL-03-WindowA] Approve thành công (booking BOOKED). Vẫn giữ khóa 4s để B chạy.';
    END TRY
    BEGIN CATCH
        IF ERROR_NUMBER() = 1205
        BEGIN
            SET @dl3Deadlock = 1;
            PRINT N'[DL-03-WindowA] >>> FAIL: gặp deadlock 1205!';
        END
        ELSE
            PRINT N'[DL-03-WindowA] Approve lỗi nghiệp vụ: ' + ERROR_MESSAGE();
    END CATCH;
    WAITFOR DELAY '00:00:04';
IF XACT_STATE() = 1
BEGIN
    COMMIT;
    PRINT N'[DL-03-WindowA] Đã nhả khóa (COMMIT outer).';
END
ELSE IF XACT_STATE() = -1
BEGIN
    ROLLBACK;
    PRINT N'[DL-03-WindowA] Outer transaction bị abort (đã ROLLBACK) - không phải deadlock.';
END
ELSE
    PRINT N'[DL-03-WindowA] Không còn outer transaction mở (nội bộ SP đã xử lý) - không phải deadlock.';

IF @dl3Deadlock = 1
    PRINT N'[DL-03-WindowA] ASSERTION FAIL: deadlock xảy ra - lock order KHÔNG nhất quán.';
ELSE
    PRINT N'[DL-03-WindowA] ASSERTION PASS: không deadlock - lock ordering Court->Booking thống nhất.';

-- Kiểm tra trạng thái cuối (A approve xong; B có thể đã cancel tiếp theo -> CANCELLED/B OOKED)
DECLARE @dl3Wait INT = 0;
WHILE NOT EXISTS (SELECT 1 FROM dbo._DLTestSync WHERE Flag = N'DL3_B_DONE') AND @dl3Wait < 90
BEGIN
    WAITFOR DELAY '00:00:01';
    SET @dl3Wait = @dl3Wait + 1;
END;
IF NOT EXISTS (SELECT 1 FROM dbo._DLTestSync WHERE Flag = N'DL3_B_DONE')
    PRINT N'[DL-03-WindowA] Timeout chờ B hoàn tất cancel.';
DECLARE @st NVARCHAR(20);
SELECT @st = Status FROM dbo.Bookings WHERE BookingId='B0000000-0000-0000-0000-D03000000001';
PRINT N'[DL-03-WindowA] Trạng thái cuối booking DL-03: ' + @st;
PRINT N'';
GO