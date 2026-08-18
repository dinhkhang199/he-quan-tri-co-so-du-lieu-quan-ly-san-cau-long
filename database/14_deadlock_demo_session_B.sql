/* ============================================================
   BadmintonCourtManagement
   Script : 14_deadlock_demo_session_B.sql   (SSMS Window B)
   Nội dung: xem hướng dẫn script 13. Phần B khóa theo thứ tự NGƯỢC với A
             trong DL-01, và cùng thứ tự Courts->Bookings trong DL-02.
   ============================================================ */

USE BadmintonCourtManagement;
GO
SET NOCOUNT ON;
SET XACT_ABORT OFF;
GO

IF OBJECT_ID('dbo._DLTestSync', 'U') IS NULL
    CREATE TABLE dbo._DLTestSync (Flag NVARCHAR(60) PRIMARY KEY, SetAt DATETIME2 NOT NULL DEFAULT SYSDATETIME());
-- KHÔNG xóa bảng ở B: A tạo mới đầu demo.
GO

-- ============================================================
-- DL-01 (buggy): B khóa Bookings b1 -> chờ -> khóa Courts C1
-- NGƯỢC thứ tự với A (Courts C1 -> Bookings b1) => tạo chu kỳ chờ
-- ============================================================
PRINT N'[DL-01-WindowB] Bắt đầu: B muốn khóa theo thứ tự Bookings(b1) -> Courts(C1) (kịch bản lỗi).';
DECLARE @dl1VictimB INT = 0;
BEGIN TRY
    BEGIN TRAN;
        UPDATE dbo.Bookings SET UpdatedAt = SYSDATETIME()
        WHERE BookingId = 'B1000001-0000-0000-0000-000000000001';
        PRINT N'[DL-01-WindowB] Đã khóa Bookings b1. Chờ 3 giây để A khóa Courts C1...';
        WAITFOR DELAY '00:00:03';

        -- Bước này B phải chờ khóa Courts C1 (đang do A giữ) -> chu kỳ chờ -> deadlock
        UPDATE dbo.Courts SET UpdatedAt = SYSDATETIME()
        WHERE CourtId = 'C1000001-0000-0000-0000-000000000001';
        PRINT N'[DL-01-WindowB] Đã ghi Courts C1 (không bị deadlock).';
    COMMIT;
    PRINT N'[DL-01-WindowB] Transaction B commit thành công (deadlock không rơi vào B).';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 1205
    BEGIN
        SET @dl1VictimB = 1;
        PRINT N'[DL-01-WindowB] >>> VICTIM: bị deadlock (1205). Transaction bị ROLLBACK - đúng bản chất deadlock.';
    END
    ELSE
        PRINT N'[DL-01-WindowB] Lỗi khác: ' + CAST(ERROR_NUMBER() AS VARCHAR(10)) + N' ' + ERROR_MESSAGE();
    IF XACT_STATE() <> 0 ROLLBACK;
END CATCH
IF @dl1VictimB = 1
    PRINT N'[DL-01-WindowB] Kết luận DL-01: B là deadlock victim.';
ELSE
    PRINT N'[DL-01-WindowB] Kết luận DL-01: deadlock có victim (A) - B commit bình thường.';
GO

-- ============================================================
-- DL-02 (fix): B cũng khóa theo Courts -> Bookings (cùng thứ tự với A)
-- ============================================================
PRINT N'';
PRINT N'[DL-02-WindowB] FIX: lock ordering nhất quán Court -> Booking.';
BEGIN TRY
    BEGIN TRAN;
        UPDATE dbo.Courts SET UpdatedAt = SYSDATETIME()
        WHERE CourtId = 'C1000001-0000-0000-0000-000000000002';
        PRINT N'[DL-02-WindowB] Đã khóa Courts C2. Chờ 3 giây...';
        WAITFOR DELAY '00:00:03';
        UPDATE dbo.Bookings SET UpdatedAt = SYSDATETIME()
        WHERE BookingId = 'B1000001-0000-0000-0000-000000000005';
        PRINT N'[DL-02-WindowB] Đã khóa Bookings b5. Hoàn tất.';
    COMMIT;
    PRINT N'[DL-02-WindowB] >>> Commit thành công - KHÔNG deadlock với lock ordering nhất quán.';
END TRY
BEGIN CATCH
    PRINT N'[DL-02-WindowB] Lỗi: ' + ERROR_MESSAGE();
    IF XACT_STATE() <> 0 ROLLBACK;
END CATCH;
GO

-- ============================================================
-- DL-03 (REGRESSION - dùng SP sản xuất thật): Approve (A) vs Cancel (B)
-- cùng 1 booking PENDING trên cùng sân C3, chạy song song.
-- Window B: cancel booking DL-03. Với lock ordering Court->Booking thống nhất,
-- B chỉ block (chờ Court lock của A) chứ không deadlock 1205.
-- ============================================================
PRINT N'';
PRINT N'[DL-03-WindowB] Bắt đầu cancel booking DL-03 (sẽ bị block tới khi A nhả khóa)...';
GO

-- Chờ A (Window A) đã tạo booking DL-03 (cờ DL3_A_READY) rồi mới cancel
DECLARE @dl3Wait INT = 0;
WHILE NOT EXISTS (SELECT 1 FROM dbo._DLTestSync WHERE Flag = N'DL3_A_READY') AND @dl3Wait < 90
BEGIN
    WAITFOR DELAY '00:00:01';
    SET @dl3Wait = @dl3Wait + 1;
END;
IF NOT EXISTS (SELECT 1 FROM dbo._DLTestSync WHERE Flag = N'DL3_A_READY')
    PRINT N'[DL-03-WindowB] Timeout chờ A tạo booking.';
-- 2s để A chắc chắn đã bắt đầu approve (giữ khóa Court C3)
WAITFOR DELAY '00:00:02';
GO

-- Option A: cancel cần phiên đăng nhập (manager)
EXEC dbo.sp_Login @Username=N'manager', @Password=N'manager123';
BEGIN TRY
    EXEC dbo.sp_CancelBooking @SessionUserId='A1000001-0000-0000-0000-000000000001',
                              @BookingId='B0000000-0000-0000-0000-D03000000001';
    PRINT N'[DL-03-WindowB] Cancel thành công (booking CANCELLED) sau khi hết block.';
    PRINT N'[DL-03-WindowB] ASSERTION PASS: không deadlock; phép cancel thực hiện tuần tự sau approve.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 1205
        PRINT N'[DL-03-WindowB] >>> FAIL: gặp deadlock 1205 (lock order không nhất quán)!';
    ELSE IF ERROR_NUMBER() = 50052
        PRINT N'[DL-03-WindowB] Không cancel được (booking đã CANCELLED/hoặc A chưa kịp khóa) - không phải deadlock.';
    ELSE
        PRINT N'[DL-03-WindowB] Cancel lỗi nghiệp vụ (không deadlock): ' + ERROR_MESSAGE();
END CATCH;
-- Báo B đã hoàn tất cancel (để Window A đọc trạng thái cuối)
INSERT INTO dbo._DLTestSync(Flag) SELECT N'DL3_B_DONE' WHERE NOT EXISTS (SELECT 1 FROM dbo._DLTestSync WHERE Flag=N'DL3_B_DONE');
PRINT N'';