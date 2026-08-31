USE BadmintonCourtManagement;
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;

/* Run after 00→08 and seed. Uses a transaction so all test mutations roll back. */
BEGIN TRAN;
BEGIN TRY
    DECLARE @manager UNIQUEIDENTIFIER = 'A1000001-0000-0000-0000-000000000001';
    DECLARE @customer UNIQUEIDENTIFIER = 'A1000001-0000-0000-0000-000000000005';
    DECLARE @booking UNIQUEIDENTIFIER = 'B1000001-0000-0000-0000-000000000004';

    EXEC dbo.sp_Login @Username=N'manager', @Password=N'manager123';
    EXEC dbo.sp_ApproveBooking @SessionUserId=@manager, @BookingId=@booking;
    IF NOT EXISTS (SELECT 1 FROM dbo.ActivityLogs WHERE BookingId=@booking AND Action=N'APPROVE' AND UserId=@manager)
        THROW 52001, N'FAIL: manager approve audit actor không phải manager.', 1;

    DECLARE @customerBooking UNIQUEIDENTIFIER = 'B0000000-0000-0000-0000-A00100000001';
    DECLARE @multiBooking UNIQUEIDENTIFIER = 'B0000000-0000-0000-0000-A00100000002';
    DECLARE @start DATETIME2(0) = DATEADD(DAY, 10, CAST(CAST(SYSDATETIME() AS DATE) AS DATETIME2));
    SET @start = DATEADD(HOUR, 10, @start);
    INSERT dbo.Bookings(BookingId,UserId,CourtId,StartTime,EndTime,Status,TotalCost)
    VALUES (@customerBooking,@customer,'C1000001-0000-0000-0000-000000000001',@start,DATEADD(HOUR,1,@start),N'PENDING',100000),
           (@multiBooking,'A1000001-0000-0000-0000-000000000006','C1000001-0000-0000-0000-000000000002',@start,DATEADD(HOUR,1,@start),N'PENDING',100000);

    EXEC dbo.sp_Login @Username=N'customer1', @Password=N'customer123';
    EXEC dbo.sp_CancelBooking @SessionUserId=@customer, @BookingId=@customerBooking;
    IF NOT EXISTS (SELECT 1 FROM dbo.ActivityLogs WHERE BookingId=@customerBooking AND Action=N'CANCEL' AND UserId=@customer)
        THROW 52002, N'FAIL: customer cancel audit actor không phải customer.', 1;

    /* Set-based fallback: no SESSION_CONTEXT must use each booking owner and remain FK-safe. */
    EXEC sys.sp_set_session_context @key=N'UserId', @value=NULL;
    UPDATE dbo.Bookings SET Status=N'CANCELLED'
    WHERE BookingId IN (@booking, @multiBooking) AND Status IN (N'PENDING',N'BOOKED');
    IF (SELECT COUNT(*) FROM dbo.ActivityLogs l JOIN dbo.Bookings b ON b.BookingId=l.BookingId
        WHERE l.BookingId IN (@booking,@multiBooking) AND l.Action=N'CANCEL' AND l.UserId=b.UserId) <> 2
        THROW 52003, N'FAIL: multi-row fallback không ghi đúng actor từng booking.', 1;

    PRINT N'PASS: manager approve, customer cancel và multi-row fallback đều ghi đúng audit actor.';
    ROLLBACK;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK;
    THROW;
END CATCH;
GO
