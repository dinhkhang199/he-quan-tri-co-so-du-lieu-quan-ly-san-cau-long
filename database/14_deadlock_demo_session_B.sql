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

-- ============================================================
-- DL-01 (buggy): B khóa Bookings b1 -> chờ -> khóa Courts C1
-- NGƯỢC thứ tự với A (Courts C1 -> Bookings b1) => tạo chu kỳ chờ
-- ============================================================
PRINT N'[DL-01-WindowB] Bắt đầu: B muốn khóa theo thứ tự Bookings(b1) -> Courts(C1).';
BEGIN TRAN;
    UPDATE dbo.Bookings SET UpdatedAt = SYSDATETIME()
    WHERE BookingId = 'B1000001-0000-0000-0000-000000000001';
    PRINT N'[DL-01-WindowB] Đã khóa Bookings b1. Chờ 3 giây để A khóa Courts C1...';
    WAITFOR DELAY '00:00:03';

    BEGIN TRY
        UPDATE dbo.Courts SET UpdatedAt = SYSDATETIME()
        WHERE CourtId = 'C1000001-0000-0000-0000-000000000001';
        PRINT N'[DL-01-WindowB] Đã ghi Courts C1 (không bị deadlock).';
    END TRY
    BEGIN CATCH
        IF ERROR_NUMBER() = 1205
            PRINT N'[DL-01-WindowB] >>> VICTIM: bị deadlock (1205). Transaction bị ROLLBACK - đúng bản chất deadlock.';
        ELSE
            PRINT N'[DL-01-WindowB] Lỗi khác: ' + CAST(ERROR_NUMBER() AS VARCHAR(10)) + N' ' + ERROR_MESSAGE();
    END CATCH;

    IF XACT_STATE() <> 0
    BEGIN
        COMMIT;
        PRINT N'[DL-01-WindowB] Transaction B commit thành công (deadlock không rơi vào B).';
    END
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