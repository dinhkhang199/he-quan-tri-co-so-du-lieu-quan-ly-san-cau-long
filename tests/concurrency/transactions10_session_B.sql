/* ============================================================
   Automated Session B for database/10_tests_transactions.sql.

   PH-01 inserts during A's READ COMMITTED wait so A must observe
   a phantom. PH-02 attempts a conflicting insert while A holds a
   SERIALIZABLE range lock and asserts that the attempt was blocked.
   ============================================================ */

USE BadmintonCourtManagement;
GO
SET NOCOUNT ON;
SET XACT_ABORT OFF;
SET LOCK_TIMEOUT 30000;
GO

DECLARE @CourtId UNIQUEIDENTIFIER = 'C1000001-0000-0000-0000-000000000006';
DECLARE @UserId UNIQUEIDENTIFIER = 'A1000001-0000-0000-0000-000000000004';
DECLARE @BookingId UNIQUEIDENTIFIER = 'B0000B00-0000-0000-0000-000000000001';
DECLARE @Date DATE = DATEADD(DAY, 1, CAST(GETDATE() AS DATE));
DECLARE @StartTime DATETIME2(0) = DATETIMEFROMPARTS(YEAR(@Date), MONTH(@Date), DAY(@Date), 6, 0, 0, 0);
DECLARE @EndTime DATETIME2(0) = DATETIMEFROMPARTS(YEAR(@Date), MONTH(@Date), DAY(@Date), 7, 0, 0, 0);

DELETE n
FROM dbo.Notifications n
JOIN dbo.Bookings b ON b.BookingId = n.BookingId
WHERE b.BookingId = @BookingId;
DELETE al
FROM dbo.ActivityLogs al
JOIN dbo.Bookings b ON b.BookingId = al.BookingId
WHERE b.BookingId = @BookingId;
DELETE FROM dbo.Bookings WHERE BookingId = @BookingId;

-- Session A is already inside PH-01 because the runner starts B three seconds later.
INSERT INTO dbo.Bookings (BookingId, UserId, CourtId, StartTime, EndTime, Status, TotalCost)
VALUES (@BookingId, @UserId, @CourtId, @StartTime, @EndTime, N'PENDING', 100000);
PRINT N'[10-B/PH-01] Inserted the phantom row and committed it.';

-- A finishes its 20-second PH-01 wait at about t+20. Start the second
-- attempt around t+22, while A is in the 10-second SERIALIZABLE window.
WAITFOR DELAY '00:00:18';

DECLARE @BlockedAt DATETIME2(3) = SYSDATETIME();
DECLARE @ElapsedMs INT;
BEGIN TRY
    INSERT INTO dbo.Bookings (UserId, CourtId, StartTime, EndTime, Status, TotalCost)
    VALUES (@UserId, @CourtId, @StartTime, @EndTime, N'PENDING', 100000);
END TRY
BEGIN CATCH
    -- After A releases its range lock, the overlap trigger is expected to
    -- reject this row because the PH-01 sentinel remains committed.
    PRINT N'[10-B/PH-02] Post-block result: ' + ERROR_MESSAGE();
END CATCH;

SET @ElapsedMs = DATEDIFF(MILLISECOND, @BlockedAt, SYSDATETIME());
PRINT N'[10-B/PH-02] INSERT attempt elapsed ms: ' + CAST(@ElapsedMs AS NVARCHAR(20));
IF @ElapsedMs < 5000
    THROW 52030, N'[10-B/PH-02] FAIL: INSERT was not blocked by the SERIALIZABLE range lock for at least five seconds.', 1;
PRINT N'[10-B/PH-02] PASS: competing INSERT was blocked until Session A released its SERIALIZABLE range lock.';

DELETE n
FROM dbo.Notifications n
JOIN dbo.Bookings b ON b.BookingId = n.BookingId
WHERE b.BookingId = @BookingId;
DELETE al
FROM dbo.ActivityLogs al
JOIN dbo.Bookings b ON b.BookingId = al.BookingId
WHERE b.BookingId = @BookingId;
DELETE FROM dbo.Bookings WHERE BookingId = @BookingId;
PRINT N'[10-B] Cleanup complete.';
GO
