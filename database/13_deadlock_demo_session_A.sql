/* ============================================================
   BadmintonCourtManagement
   Script : 13_deadlock_demo_session_A.sql   (SSMS Window A)
   Nội dung:
     DL-01: tái hiện DEADLOCK (khóa chéo Courts <> Bookings) -> victim error 1205
     DL-02: fix bằng lock ordering nhất quán (Court -> Booking) -> hết deadlock
   CÁCH CHẠY:
     1. Mở 2 cửa sổ SSMS.
     2. Chạy 13 ở cửa sổ A và 14 ở cửa sổ B GẦN NHƯ CÙNG LÚC (không quá 2 giây).
     3. Xem 1 cửa sổ nhận lỗi 1205 (deadlock victim) - đó là DL-01.
     4. Tái lập DL-02: comment phần DL-01 ở cả 2 file, bỏ comment phần DL-02, chạy lại.
   ============================================================ */

USE BadmintonCourtManagement;
GO
SET NOCOUNT ON;
SET XACT_ABORT OFF;
GO

-- ============================================================
-- DL-01 (buggy): A khóa Courts C1 -> chờ -> khóa Bookings b1
-- B khóa Bookings b1 -> chờ -> khóa Courts C1   (xem 14)
-- -> chu kỳ chờ khóa = deadlock
-- ============================================================
PRINT N'[DL-01-WindowA] Bắt đầu: A muốn khóa theo thứ tự Courts(C1) -> Bookings(b1).';
BEGIN TRAN;
    UPDATE dbo.Courts SET UpdatedAt = SYSDATETIME()
    WHERE CourtId = 'C1000001-0000-0000-0000-000000000001';
    PRINT N'[DL-01-WindowA] Đã khóa Courts C1. Chờ 3 giây để B khóa Bookings b1...';
    WAITFOR DELAY '00:00:03';

    -- Bước này A phải chờ khóa Bookings b1 (đang do B giữ)
    BEGIN TRY
        UPDATE dbo.Bookings SET UpdatedAt = SYSDATETIME()
        WHERE BookingId = 'B1000001-0000-0000-0000-000000000001';
        PRINT N'[DL-01-WindowA] Đã ghi Bookings b1 (không bị deadlock).';
    END TRY
    BEGIN CATCH
        IF ERROR_NUMBER() = 1205
            PRINT N'[DL-01-WindowA] >>> VICTIM: bị deadlock (1205). Transaction bị ROLLBACK - đúng bản chất deadlock.';
        ELSE
            PRINT N'[DL-01-WindowA] Lỗi khác: ' + CAST(ERROR_NUMBER() AS VARCHAR(10)) + N' ' + ERROR_MESSAGE();
    END CATCH;

    IF XACT_STATE() <> 0
    BEGIN
        COMMIT;
        PRINT N'[DL-01-WindowA] Transaction A commit thành công (deadlock không rơi vào A).';
    END
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