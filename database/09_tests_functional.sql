/* ============================================================
   BadmintonCourtManagement
   Script : 09_tests_functional.sql
   Mục đích: Chạy test matrix phiên đơn (DB-*, FN-*, SP-*, TR-*, TX-01, INV-01)
             + negative security tests (SESSION_CONTEXT bắt buộc - Option A).
             Kết quả ghi vào #Results rồi in summary cuối script.
   LƯU Ý : Chạy sau khi đã chạy 00→08. Có thể chạy lại.
   Option A: mọi SP nghiệp vụ phải gọi sp_Login trước (SESSION_CONTEXT).
   Trong test, trước mỗi SP call đều có sp_Login cho đúng actor.
   ============================================================ */

USE BadmintonCourtManagement;
GO

SET NOCOUNT ON;
SET XACT_ABORT OFF;  -- riêng cho test harness
GO

IF OBJECT_ID('tempdb..#Results') IS NOT NULL DROP TABLE #Results;
GO
CREATE TABLE #Results
(
    id   VARCHAR(20)   NOT NULL,
    name NVARCHAR(200) NOT NULL,
    [pass] BIT         NOT NULL,
    note NVARCHAR(500) NULL
);
GO

-- ============================================================
-- RESET dữ liệu test từ lần chạy trước (giúp script chạy lại được)
-- ============================================================
DELETE n
FROM dbo.Notifications n
JOIN dbo.Bookings b ON b.BookingId = n.BookingId
WHERE b.BookingId NOT LIKE 'B0000000-0000-0000-0000-%'
  AND b.BookingId NOT LIKE 'B1000001-0000-0000-0000-%';
GO
DELETE al
FROM dbo.ActivityLogs al
JOIN dbo.Bookings b ON b.BookingId = al.BookingId
WHERE b.BookingId NOT LIKE 'B0000000-0000-0000-0000-%'
  AND b.BookingId NOT LIKE 'B1000001-0000-0000-0000-%';
GO
DELETE FROM dbo.Bookings
WHERE BookingId NOT LIKE 'B0000000-0000-0000-0000-%'
  AND BookingId NOT LIKE 'B1000001-0000-0000-0000-%';
GO

-- ============================================================
-- MAIN TEST BATCH
-- ============================================================
DECLARE @d1 DATE = DATEADD(DAY,1,CAST(GETDATE() AS DATE));
DECLARE @d2 DATE = DATEADD(DAY,2,CAST(GETDATE() AS DATE));

-- Các mốc giờ (D1, D2) dùng chung
DECLARE @D1_0600 datetime2(0) = DATETIMEFROMPARTS(YEAR(@d1),MONTH(@d1),DAY(@d1),6,0,0,0);
DECLARE @D1_0630 datetime2(0) = DATETIMEFROMPARTS(YEAR(@d1),MONTH(@d1),DAY(@d1),6,30,0,0);
DECLARE @D1_0700 datetime2(0) = DATETIMEFROMPARTS(YEAR(@d1),MONTH(@d1),DAY(@d1),7,0,0,0);
DECLARE @D1_0730 datetime2(0) = DATETIMEFROMPARTS(YEAR(@d1),MONTH(@d1),DAY(@d1),7,30,0,0);
DECLARE @D1_0800 datetime2(0) = DATETIMEFROMPARTS(YEAR(@d1),MONTH(@d1),DAY(@d1),8,0,0,0);
DECLARE @D1_0830 datetime2(0) = DATETIMEFROMPARTS(YEAR(@d1),MONTH(@d1),DAY(@d1),8,30,0,0);
DECLARE @D1_0900 datetime2(0) = DATETIMEFROMPARTS(YEAR(@d1),MONTH(@d1),DAY(@d1),9,0,0,0);
DECLARE @D1_0930 datetime2(0) = DATETIMEFROMPARTS(YEAR(@d1),MONTH(@d1),DAY(@d1),9,30,0,0);
DECLARE @D1_1000 datetime2(0) = DATETIMEFROMPARTS(YEAR(@d1),MONTH(@d1),DAY(@d1),10,0,0,0);
DECLARE @D1_1100 datetime2(0) = DATETIMEFROMPARTS(YEAR(@d1),MONTH(@d1),DAY(@d1),11,0,0,0);

-- GUID seed
DECLARE @mgr   UNIQUEIDENTIFIER = 'A1000001-0000-0000-0000-000000000001';
DECLARE @cm1   UNIQUEIDENTIFIER = 'A1000001-0000-0000-0000-000000000002';
DECLARE @cm2   UNIQUEIDENTIFIER = 'A1000001-0000-0000-0000-000000000003';
DECLARE @cus1  UNIQUEIDENTIFIER = 'A1000001-0000-0000-0000-000000000004';
DECLARE @cus2  UNIQUEIDENTIFIER = 'A1000001-0000-0000-0000-000000000005';
DECLARE @cus3  UNIQUEIDENTIFIER = 'A1000001-0000-0000-0000-000000000006';

DECLARE @c1 UNIQUEIDENTIFIER = 'C1000001-0000-0000-0000-000000000001';
DECLARE @c2 UNIQUEIDENTIFIER = 'C1000001-0000-0000-0000-000000000002';
DECLARE @c3 UNIQUEIDENTIFIER = 'C1000001-0000-0000-0000-000000000003';
DECLARE @c4 UNIQUEIDENTIFIER = 'C1000001-0000-0000-0000-000000000004';
DECLARE @c5 UNIQUEIDENTIFIER = 'C1000001-0000-0000-0000-000000000005';
DECLARE @c6 UNIQUEIDENTIFIER = 'C1000001-0000-0000-0000-000000000006';

-- ------------------------------------------------------------
-- DB-01: Database tạo từ rỗng
-- ------------------------------------------------------------
IF DB_ID(N'BadmintonCourtManagement') IS NOT NULL
    INSERT #Results VALUES('DB-01', N'Create DB từ rỗng (5 bảng lõi)', 1, N'DB tồn tại');
ELSE
    INSERT #Results VALUES('DB-01', N'Create DB từ rỗng (5 bảng lõi)', 0, N'DB không tồn tại');

IF (SELECT COUNT(*) FROM sys.tables WHERE is_ms_shipped = 0) = 5
    INSERT #Results VALUES('DB-01b', N'Đủ 5 bảng lõi', 1, N'Users/Courts/Bookings/ActivityLogs/Notifications');
ELSE
    INSERT #Results VALUES('DB-01b', N'Đủ 5 bảng lõi', 0, N'Thiếu bảng');

-- ------------------------------------------------------------
-- DB-02: Duplicate username / phone -> UNIQUE
-- ------------------------------------------------------------
BEGIN TRY
    INSERT INTO dbo.Users (Username, PasswordHash, PhoneNumber, Role)
    VALUES (N'manager', CONVERT(VARBINARY(64), HASHBYTES('SHA2_256', N'bcms|t')), N'0999999999', N'CUSTOMER');
    INSERT #Results VALUES('DB-02', N'Duplicate username/phone bị UNIQUE chặn', 0, N'Insert thành công, không bị chặn');
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 2627
        INSERT #Results VALUES('DB-02', N'Duplicate username/phone bị UNIQUE chặn', 1, N'Lỗi 2627 UNIQUE constraint');
    ELSE
        INSERT #Results VALUES('DB-02', N'Duplicate username/phone bị UNIQUE chặn', 0, N'Mã lỗi: ' + CAST(ERROR_NUMBER() AS VARCHAR(10)));
END CATCH;

BEGIN TRY
    INSERT INTO dbo.Users (Username, PasswordHash, PhoneNumber, Role)
    VALUES (N'dup_phone_user', CONVERT(VARBINARY(64), HASHBYTES('SHA2_256', N'bcms|t')), N'0901000001', N'CUSTOMER');
    INSERT #Results VALUES('DB-02p', N'Duplicate phone bị UNIQUE chặn', 0, N'Insert thành công');
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 2627
        INSERT #Results VALUES('DB-02p', N'Duplicate phone bị UNIQUE chặn', 1, N'Lỗi 2627 UNIQUE constraint');
    ELSE
        INSERT #Results VALUES('DB-02p', N'Duplicate phone bị UNIQUE chặn', 0, N'Mã lỗi: ' + CAST(ERROR_NUMBER() AS VARCHAR(10)));
END CATCH;

-- ------------------------------------------------------------
-- DB-03: Giá <= 0 -> CHECK
-- ------------------------------------------------------------
BEGIN TRY
    INSERT INTO dbo.Courts (CourtName, Address, SurfaceType, SizeType, PricePerHour, PricePerThreeHours, OwnerId)
    VALUES (N'Sân lỗi giá', N'x', N'STANDARD', N'SINGLE', 0, 270000, @cm1);
    INSERT #Results VALUES('DB-03', N'Giá <= 0 bị CHECK chặn', 0, N'Insert thành công');
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 547
        INSERT #Results VALUES('DB-03', N'Giá <= 0 bị CHECK chặn', 1, N'Lỗi 547 CHECK constraint');
    ELSE
        INSERT #Results VALUES('DB-03', N'Giá <= 0 bị CHECK chặn', 0, N'Mã lỗi: ' + CAST(ERROR_NUMBER() AS VARCHAR(10)));
END CATCH;

-- ------------------------------------------------------------
-- DB-04: Start >= End -> CHECK
-- ------------------------------------------------------------
BEGIN TRY
    INSERT INTO dbo.Bookings (UserId, CourtId, StartTime, EndTime, Status, TotalCost)
    VALUES (@cus1, @c1, @D1_0800, @D1_0700, N'PENDING', 100000);
    INSERT #Results VALUES('DB-04', N'Start >= End bị CHECK chặn', 0, N'Insert thành công');
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 547
        INSERT #Results VALUES('DB-04', N'Start >= End bị CHECK chặn', 1, N'Lỗi 547 CHECK constraint');
    ELSE
        INSERT #Results VALUES('DB-04', N'Start >= End bị CHECK chặn', 0, N'Mã lỗi: ' + CAST(ERROR_NUMBER() AS VARCHAR(10)));
END CATCH;

-- ------------------------------------------------------------
-- DB-05: Status / Role invalid -> CHECK
-- ------------------------------------------------------------
BEGIN TRY
    INSERT INTO dbo.Bookings (UserId, CourtId, StartTime, EndTime, Status, TotalCost)
    VALUES (@cus1, @c1, @D1_0700, @D1_0800, N'INVALID', 100000);
    INSERT #Results VALUES('DB-05', N'Status invalid bị CHECK chặn', 0, N'Insert thành công');
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 547
        INSERT #Results VALUES('DB-05', N'Status invalid bị CHECK chặn', 1, N'Lỗi 547 CHECK constraint');
    ELSE
        INSERT #Results VALUES('DB-05', N'Status invalid bị CHECK chặn', 0, N'Mã lỗi: ' + CAST(ERROR_NUMBER() AS VARCHAR(10)));
END CATCH;

BEGIN TRY
    INSERT INTO dbo.Users (Username, PasswordHash, PhoneNumber, Role)
    VALUES (N'badrole_user', CONVERT(VARBINARY(64), HASHBYTES('SHA2_256', N'bcms|t')), N'0988000001', N'ROOT');
    INSERT #Results VALUES('DB-05r', N'Role invalid bị CHECK chặn', 0, N'Insert thành công');
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 547
        INSERT #Results VALUES('DB-05r', N'Role invalid bị CHECK chặn', 1, N'Lỗi 547 CHECK constraint');
    ELSE
        INSERT #Results VALUES('DB-05r', N'Role invalid bị CHECK chặn', 0, N'Mã lỗi: ' + CAST(ERROR_NUMBER() AS VARCHAR(10)));
END CATCH;

-- ------------------------------------------------------------
-- FN-01..FN-03: fn_CalculateBookingCost
-- ------------------------------------------------------------
DECLARE @cost DECIMAL(12,0);
SET @cost = dbo.fn_CalculateBookingCost(@c1, @D1_0600, @D1_0700);
IF @cost = 100000
    INSERT #Results VALUES('FN-01', N'Cost < 3h = giờ lẻ x PricePerHour', 1, N'1h = 100.000');
ELSE
    INSERT #Results VALUES('FN-01', N'Cost < 3h = giờ lẻ x PricePerHour', 0, N'Kết quả: ' + CAST(@cost AS VARCHAR(20)));

SET @cost = dbo.fn_CalculateBookingCost(@c1, @D1_0600, @D1_0900);
IF @cost = 270000
    INSERT #Results VALUES('FN-02', N'Cost đúng 3h = PricePerThreeHours', 1, N'3h = 270.000');
ELSE
    INSERT #Results VALUES('FN-02', N'Cost đúng 3h = PricePerThreeHours', 0, N'Kết quả: ' + CAST(@cost AS VARCHAR(20)));

SET @cost = dbo.fn_CalculateBookingCost(@c1, @D1_0600, @D1_0930);   -- 3,5h
IF @cost = 320000
    INSERT #Results VALUES('FN-03', N'Cost > 3h = block 3h + giờ lẻ', 1, N'3,5h = 270.000 + 50.000 = 320.000');
ELSE
    INSERT #Results VALUES('FN-03', N'Cost > 3h = block 3h + giờ lẻ', 0, N'Kết quả: ' + CAST(@cost AS VARCHAR(20)));

-- ================= SP-01: Book hợp lệ (actor = cus2) =================
DECLARE @pendingId1 UNIQUEIDENTIFIER = NEWID();
DECLARE @tc DECIMAL(12,0);
DECLARE @ok BIT = 0;
BEGIN TRY
    EXEC dbo.sp_Login @Username=N'customer2', @Password=N'cus2pass';
    EXEC dbo.sp_BookCourt @UserId=@cus2, @CourtId=@c1, @StartTime=@D1_0600, @EndTime=@D1_0700,
         @BookingId=@pendingId1 OUTPUT, @TotalCost=@tc OUTPUT;
    IF EXISTS (SELECT 1 FROM dbo.Bookings WHERE BookingId=@pendingId1 AND Status=N'PENDING' AND TotalCost=100000)
       AND EXISTS (SELECT 1 FROM dbo.ActivityLogs WHERE BookingId=@pendingId1)
       AND EXISTS (SELECT 1 FROM dbo.Notifications WHERE BookingId=@pendingId1)
        SET @ok = 1;
END TRY
BEGIN CATCH
    SET @ok = 0;
    INSERT #Results VALUES('SP-01', N'Book hợp lệ', 0, N'Lỗi: ' + ERROR_MESSAGE());
END CATCH;
IF @ok = 1
    INSERT #Results VALUES('SP-01', N'Book hợp lệ → 1 PENDING + audit + notification', 1, N'TotalCost=100.000');
ELSE IF NOT EXISTS (SELECT 1 FROM #Results WHERE id='SP-01')
    INSERT #Results VALUES('SP-01', N'Book hợp lệ → 1 PENDING + audit + notification', 0, N'Thiếu PENDING/audit/notification');

-- ================= SP-02: Book overlap với BOOKED =================
-- Tạo + approve 1 booking BOOKED trên court1 khung 07-08 (actor: cus1 book, mgr approve)
DECLARE @xId UNIQUEIDENTIFIER = NEWID();
BEGIN TRY
    EXEC dbo.sp_Login @Username=N'customer1', @Password=N'cus1pass';
    EXEC dbo.sp_BookCourt @UserId=@cus1, @CourtId=@c1, @StartTime=@D1_0700, @EndTime=@D1_0800, @BookingId=@xId OUTPUT, @TotalCost=@tc OUTPUT;
    EXEC dbo.sp_Login @Username=N'manager', @Password=N'manager123';
    EXEC dbo.sp_ApproveBooking @SessionUserId=@mgr, @BookingId=@xId;
END TRY
BEGIN CATCH
    INSERT #Results VALUES('SP-02', N'Book overlap với BOOKED', 0, N'Setup approve thất bại: ' + ERROR_MESSAGE());
END CATCH;

BEGIN TRY
    DECLARE @overlapId UNIQUEIDENTIFIER = NEWID();
    EXEC dbo.sp_Login @Username=N'customer2', @Password=N'cus2pass';
    EXEC dbo.sp_BookCourt @UserId=@cus2, @CourtId=@c1, @StartTime=@D1_0730, @EndTime=@D1_0830, @BookingId=@overlapId OUTPUT, @TotalCost=@tc OUTPUT;
    INSERT #Results VALUES('SP-02', N'Book overlap với BOOKED', 0, N'Không bị từ chối (đã tạo booking mới!)');
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50021
        INSERT #Results VALUES('SP-02', N'Book overlap với BOOKED', 1, N'Bị từ chối 50021, transaction rollback');
    ELSE
        INSERT #Results VALUES('SP-02', N'Book overlap với BOOKED', 0, N'Mã lỗi: ' + CAST(ERROR_NUMBER() AS VARCHAR(10)));
END CATCH;

-- ================= FN-04 (dựa trên @xId BOOKED 07-08 court1) =================
IF dbo.fn_IsCourtAvailable(@c1, @D1_0800, @D1_0900) = 1
    INSERT #Results VALUES('FN-04', N'Boundary: End A = Start B → available', 1, N'07-08 & 08-09 không overlap');
ELSE
    INSERT #Results VALUES('FN-04', N'Boundary: End A = Start B → available', 0, N'fn trả 0 (sai contract)');
IF dbo.fn_IsCourtAvailable(@c1, @D1_0630, @D1_0730) = 0
    INSERT #Results VALUES('FN-04b', N'Overlap thật → không available', 1, N'06:30-07:30 overlap 07-08');
ELSE
    INSERT #Results VALUES('FN-04b', N'Overlap thật → không available', 0, N'fn trả 1 (sai contract)');

-- ================= SP-03: Approve hợp lệ (cus2 book, mgr approve) =================
DECLARE @s3Id UNIQUEIDENTIFIER = NEWID();
BEGIN TRY
    EXEC dbo.sp_Login @Username=N'customer2', @Password=N'cus2pass';
    EXEC dbo.sp_BookCourt @UserId=@cus2, @CourtId=@c1, @StartTime=@D1_0800, @EndTime=@D1_0900, @BookingId=@s3Id OUTPUT, @TotalCost=@tc OUTPUT;
    EXEC dbo.sp_Login @Username=N'manager', @Password=N'manager123';
    EXEC dbo.sp_ApproveBooking @SessionUserId=@mgr, @BookingId=@s3Id;
    IF EXISTS (SELECT 1 FROM dbo.Bookings WHERE BookingId=@s3Id AND Status=N'BOOKED')
      AND EXISTS (SELECT 1 FROM dbo.ActivityLogs WHERE BookingId=@s3Id AND Action=N'APPROVE')
        INSERT #Results VALUES('SP-03', N'Approve hợp lệ PENDING→BOOKED', 1, N'BOOKED + audit APPROVE');
    ELSE
        INSERT #Results VALUES('SP-03', N'Approve hợp lệ PENDING→BOOKED', 0, N'Trạng thái/audit không đúng');
END TRY
BEGIN CATCH
    INSERT #Results VALUES('SP-03', N'Approve hợp lệ PENDING→BOOKED', 0, N'Lỗi: ' + ERROR_MESSAGE());
END CATCH;

-- ================= SP-04: Approve overlap (2 PENDING cùng khung) =================
DECLARE @pA UNIQUEIDENTIFIER = NEWID();
DECLARE @pB UNIQUEIDENTIFIER = NEWID();
BEGIN TRY
    EXEC dbo.sp_Login @Username=N'customer1', @Password=N'cus1pass';
    EXEC dbo.sp_BookCourt @UserId=@cus1, @CourtId=@c1, @StartTime=@D1_0900, @EndTime=@D1_1000, @BookingId=@pA OUTPUT, @TotalCost=@tc OUTPUT;
    EXEC dbo.sp_Login @Username=N'customer2', @Password=N'cus2pass';
    EXEC dbo.sp_BookCourt @UserId=@cus2, @CourtId=@c1, @StartTime=@D1_0900, @EndTime=@D1_1000, @BookingId=@pB OUTPUT, @TotalCost=@tc OUTPUT;
    EXEC dbo.sp_Login @Username=N'manager', @Password=N'manager123';
    EXEC dbo.sp_ApproveBooking @SessionUserId=@mgr, @BookingId=@pA;      -- ưu tiên pA
    BEGIN TRY
        EXEC dbo.sp_ApproveBooking @SessionUserId=@mgr, @BookingId=@pB;  -- phải bị từ chối
        INSERT #Results VALUES('SP-04', N'Approve overlap → rollback, không tạo BOOKED overlap', 0, N'pB approve thành công (sai!)');
    END TRY
    BEGIN CATCH
        IF ERROR_NUMBER() = 50035
        BEGIN
            IF (SELECT Status FROM dbo.Bookings WHERE BookingId=@pB) = N'PENDING'
               AND NOT EXISTS (SELECT 1 FROM dbo.Bookings WHERE CourtId=@c1 AND Status=N'BOOKED' AND StartTime=@D1_0900 AND BookingId<>@pA)
                INSERT #Results VALUES('SP-04', N'Approve overlap → rollback, không tạo BOOKED overlap', 1, N'pB giữ PENDING, chỉ 1 BOOKED');
            ELSE
                INSERT #Results VALUES('SP-04', N'Approve overlap → rollback, không tạo BOOKED overlap', 0, N'Trạng thái pB sai');
        END
        ELSE
            INSERT #Results VALUES('SP-04', N'Approve overlap → rollback, không tạo BOOKED overlap', 0, N'Mã lỗi: ' + CAST(ERROR_NUMBER() AS VARCHAR(10)));
    END CATCH;
END TRY
BEGIN CATCH
    INSERT #Results VALUES('SP-04', N'Approve overlap → rollback, không tạo BOOKED overlap', 0, N'Setup fail: ' + ERROR_MESSAGE());
END CATCH;

-- ================= SP-05: Reject PENDING (cm1 reject) =================
DECLARE @s5Id UNIQUEIDENTIFIER = NEWID();
BEGIN TRY
    EXEC dbo.sp_Login @Username=N'customer2', @Password=N'cus2pass';
    EXEC dbo.sp_BookCourt @UserId=@cus2, @CourtId=@c2, @StartTime=@D1_0600, @EndTime=@D1_0700, @BookingId=@s5Id OUTPUT, @TotalCost=@tc OUTPUT;
    EXEC dbo.sp_Login @Username=N'courtmanager1', @Password=N'cm1pass';
    EXEC dbo.sp_RejectBooking @SessionUserId=@cm1, @BookingId=@s5Id;
    IF (SELECT Status FROM dbo.Bookings WHERE BookingId=@s5Id) = N'REJECTED'
        INSERT #Results VALUES('SP-05', N'Reject PENDING→REJECTED', 1, N'Rejected bởi Court Manager');
    ELSE
        INSERT #Results VALUES('SP-05', N'Reject PENDING→REJECTED', 0, N'Trạng thái sai');
END TRY
BEGIN CATCH
    INSERT #Results VALUES('SP-05', N'Reject PENDING→REJECTED', 0, N'Lỗi: ' + ERROR_MESSAGE());
END CATCH;

-- Reject lần 2 (không còn PENDING) phải thất bại
BEGIN TRY
    EXEC dbo.sp_Login @Username=N'manager', @Password=N'manager123';
    EXEC dbo.sp_RejectBooking @SessionUserId=@mgr, @BookingId=@s5Id;
    INSERT #Results VALUES('SP-05b', N'Reject không-PENDING bị từ chối', 0, N'Reject thành công (sai)');
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50043
        INSERT #Results VALUES('SP-05b', N'Reject không-PENDING bị từ chối', 1, N'Lỗi 50043');
    ELSE
        INSERT #Results VALUES('SP-05b', N'Reject không-PENDING bị từ chối', 0, N'Mã lỗi: ' + CAST(ERROR_NUMBER() AS VARCHAR(10)));
END CATCH;

-- ================= SP-06: Cancel PENDING (customer của chính mình) =================
DECLARE @s6Id UNIQUEIDENTIFIER = NEWID();
BEGIN TRY
    EXEC dbo.sp_Login @Username=N'customer3', @Password=N'cus3pass';
    EXEC dbo.sp_BookCourt @UserId=@cus3, @CourtId=@c3, @StartTime=@D1_0600, @EndTime=@D1_0700, @BookingId=@s6Id OUTPUT, @TotalCost=@tc OUTPUT;
    EXEC dbo.sp_CancelBooking @SessionUserId=@cus3, @BookingId=@s6Id;
    IF (SELECT Status FROM dbo.Bookings WHERE BookingId=@s6Id) = N'CANCELLED'
        INSERT #Results VALUES('SP-06', N'Cancel PENDING→CANCELLED', 1, N'Customer tự hủy PENDING');
    ELSE
        INSERT #Results VALUES('SP-06', N'Cancel PENDING→CANCELLED', 0, N'Trạng thái sai');
END TRY
BEGIN CATCH
    INSERT #Results VALUES('SP-06', N'Cancel PENDING→CANCELLED', 0, N'Lỗi: ' + ERROR_MESSAGE());
END CATCH;

-- Cancel booking KHÔNG phải của mình -> bị chặn
BEGIN TRY
    DECLARE @otherPend UNIQUEIDENTIFIER = NEWID();
    EXEC dbo.sp_Login @Username=N'customer1', @Password=N'cus1pass';
    EXEC dbo.sp_BookCourt @UserId=@cus1, @CourtId=@c3, @StartTime=@D1_0900, @EndTime=@D1_1000, @BookingId=@otherPend OUTPUT, @TotalCost=@tc OUTPUT;
    EXEC dbo.sp_Login @Username=N'customer3', @Password=N'cus3pass';
    EXEC dbo.sp_CancelBooking @SessionUserId=@cus3, @BookingId=@otherPend;
    INSERT #Results VALUES('SP-06b', N'Customer hủy booking của người khác bị chặn', 0, N'Không bị chặn (sai)');
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50054
        INSERT #Results VALUES('SP-06b', N'Customer hủy booking của người khác bị chặn', 1, N'Lỗi 50054 ownership');
    ELSE
        INSERT #Results VALUES('SP-06b', N'Customer hủy booking của người khác bị chặn', 0, N'Mã lỗi: ' + CAST(ERROR_NUMBER() AS VARCHAR(10)));
END CATCH;

-- ================= SP-07: Cancel BOOKED < 3h (customer) bị từ chối, vẫn BOOKED =================
DECLARE @nearId UNIQUEIDENTIFIER = NEWID();
DECLARE @nearStart datetime2(0) = DATEADD(MINUTE, 90, SYSDATETIME());
DECLARE @nearEnd datetime2(0) = DATEADD(MINUTE, 180, SYSDATETIME());
BEGIN TRY
    INSERT INTO dbo.Bookings (BookingId, UserId, CourtId, StartTime, EndTime, Status, TotalCost)
    VALUES (@nearId, @cus1, @c6, @nearStart, @nearEnd, N'BOOKED', 100000);
    BEGIN TRY
        EXEC dbo.sp_Login @Username=N'customer1', @Password=N'cus1pass';
        EXEC dbo.sp_CancelBooking @SessionUserId=@cus1, @BookingId=@nearId;
        INSERT #Results VALUES('SP-07', N'Cancel BOOKED < 3h bị từ chối, vẫn BOOKED', 0, N'Cancel thành công (sai)');
    END TRY
    BEGIN CATCH
        IF ERROR_NUMBER() = 50055
        BEGIN
            IF (SELECT Status FROM dbo.Bookings WHERE BookingId=@nearId) = N'BOOKED'
                INSERT #Results VALUES('SP-07', N'Cancel BOOKED < 3h bị từ chối, vẫn BOOKED', 1, N'Lỗi 50055; vẫn BOOKED');
            ELSE
                INSERT #Results VALUES('SP-07', N'Cancel BOOKED < 3h bị từ chối, vẫn BOOKED', 0, N'Trạng thái đổi sai');
        END
        ELSE
            INSERT #Results VALUES('SP-07', N'Cancel BOOKED < 3h bị từ chối, vẫn BOOKED', 0, N'Mã lỗi: ' + CAST(ERROR_NUMBER() AS VARCHAR(10)));
    END CATCH;
END TRY
BEGIN CATCH
    INSERT #Results VALUES('SP-07', N'Cancel BOOKED < 3h bị từ chối, vẫn BOOKED', 0, N'Setup fail: ' + ERROR_MESSAGE());
END CATCH;

-- ================= SP-08: Sai quyền (customer approve) =================
DECLARE @s8Id UNIQUEIDENTIFIER = NEWID();
BEGIN TRY
    EXEC dbo.sp_Login @Username=N'customer1', @Password=N'cus1pass';
    EXEC dbo.sp_BookCourt @UserId=@cus1, @CourtId=@c4, @StartTime=@D1_0600, @EndTime=@D1_0700, @BookingId=@s8Id OUTPUT, @TotalCost=@tc OUTPUT;
    BEGIN TRY
        EXEC dbo.sp_ApproveBooking @SessionUserId=@cus1, @BookingId=@s8Id;
        INSERT #Results VALUES('SP-08', N'Sai quyền: customer approve bị từ chối', 0, N'Approve thành công (sai)');
    END TRY
    BEGIN CATCH
        IF ERROR_NUMBER() = 50031
            INSERT #Results VALUES('SP-08', N'Sai quyền: customer approve bị từ chối', 1, N'Lỗi 50031');
        ELSE
            INSERT #Results VALUES('SP-08', N'Sai quyền: customer approve bị từ chối', 0, N'Mã lỗi: ' + CAST(ERROR_NUMBER() AS VARCHAR(10)));
    END CATCH;
END TRY
BEGIN CATCH
    INSERT #Results VALUES('SP-08', N'Sai quyền: customer approve bị từ chối', 0, N'Setup fail: ' + ERROR_MESSAGE());
END CATCH;

-- ================= SP-09: Complete sai state (PENDING) =================
DECLARE @s9Id UNIQUEIDENTIFIER = NEWID();
BEGIN TRY
    EXEC dbo.sp_Login @Username=N'customer2', @Password=N'cus2pass';
    EXEC dbo.sp_BookCourt @UserId=@cus2, @CourtId=@c4, @StartTime=@D1_0700, @EndTime=@D1_0800, @BookingId=@s9Id OUTPUT, @TotalCost=@tc OUTPUT;
    BEGIN TRY
        EXEC dbo.sp_Login @Username=N'courtmanager2', @Password=N'cm2pass';
        EXEC dbo.sp_CompleteBooking @SessionUserId=@cm2, @BookingId=@s9Id;
        INSERT #Results VALUES('SP-09', N'Complete sai state bị từ chối', 0, N'Complete thành công (sai)');
    END TRY
    BEGIN CATCH
        IF ERROR_NUMBER() = 50062
            INSERT #Results VALUES('SP-09', N'Complete sai state bị từ chối', 1, N'Lỗi 50062 (chỉ BOOKED→COMPLETED)');
        ELSE
            INSERT #Results VALUES('SP-09', N'Complete sai state bị từ chối', 0, N'Mã lỗi: ' + CAST(ERROR_NUMBER() AS VARCHAR(10)));
    END CATCH;
END TRY
BEGIN CATCH
    INSERT #Results VALUES('SP-09', N'Complete sai state bị từ chối', 0, N'Setup fail: ' + ERROR_MESSAGE());
END CATCH;

-- ================= TR-01: Direct state transition sai (trigger chặn) =================
DECLARE @tr1Id UNIQUEIDENTIFIER = NEWID();
BEGIN TRY
    EXEC dbo.sp_Login @Username=N'customer1', @Password=N'cus1pass';
    EXEC dbo.sp_BookCourt @UserId=@cus1, @CourtId=@c5, @StartTime=@D1_0600, @EndTime=@D1_0700, @BookingId=@tr1Id OUTPUT, @TotalCost=@tc OUTPUT;
    BEGIN TRY
        UPDATE dbo.Bookings SET Status = N'COMPLETED' WHERE BookingId = @tr1Id;
        INSERT #Results VALUES('TR-01', N'Direct state transition sai bị trigger chặn', 0, N'Update thành công (sai)');
    END TRY
    BEGIN CATCH
        IF ERROR_NUMBER() = 51000
        BEGIN
            IF (SELECT Status FROM dbo.Bookings WHERE BookingId=@tr1Id) = N'PENDING'
                INSERT #Results VALUES('TR-01', N'Direct state transition sai bị trigger chặn', 1, N'Đổi trạng thái bị chặn, vẫn PENDING');
            ELSE
                INSERT #Results VALUES('TR-01', N'Direct state transition sai bị trigger chặn', 0, N'Trạng thái đổi sai');
        END
        ELSE
            INSERT #Results VALUES('TR-01', N'Direct state transition sai bị trigger chặn', 0, N'Mã lỗi: ' + CAST(ERROR_NUMBER() AS VARCHAR(10)));
    END CATCH;
END TRY
BEGIN CATCH
    INSERT #Results VALUES('TR-01', N'Direct state transition sai bị trigger chặn', 0, N'Setup fail: ' + ERROR_MESSAGE());
END CATCH;

-- ================= TR-02: Direct BOOKED overlap (trigger chặn) =================
DECLARE @tr2Id UNIQUEIDENTIFIER = NEWID();
BEGIN TRY
    INSERT INTO dbo.Bookings (BookingId, UserId, CourtId, StartTime, EndTime, Status, TotalCost)
    VALUES (@tr2Id, @cus2, @c1, @D1_0730, @D1_0830, N'BOOKED', 100000);
    INSERT #Results VALUES('TR-02', N'Direct BOOKED overlap bị trigger chặn', 0, N'Insert thành công (sai)');
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 51001
        INSERT #Results VALUES('TR-02', N'Direct BOOKED overlap bị trigger chặn', 1, N'Lỗi 51001 từ safety-net trigger');
    ELSE
        INSERT #Results VALUES('TR-02', N'Direct BOOKED overlap bị trigger chặn', 0, N'Mã lỗi: ' + CAST(ERROR_NUMBER() AS VARCHAR(10)));
END CATCH;

-- ================= TR-03a: Multi-row insert không bỏ sót audit =================
DECLARE @m1 UNIQUEIDENTIFIER = NEWID();
DECLARE @m2 UNIQUEIDENTIFIER = NEWID();
BEGIN TRY
    INSERT INTO dbo.Bookings (BookingId, UserId, CourtId, StartTime, EndTime, Status, TotalCost)
    VALUES
        (@m1, @cus1, @c2, @D1_0700, @D1_0800, N'PENDING', 100000),
        (@m2, @cus2, @c2, @D1_0800, @D1_0900, N'PENDING', 100000);
    IF (SELECT COUNT(*) FROM dbo.ActivityLogs WHERE BookingId IN (@m1,@m2)) = 2
        INSERT #Results VALUES('TR-03a', N'Multi-row insert: audit đủ 2 dòng', 1, N'2 audit cho 2 booking');
    ELSE
        INSERT #Results VALUES('TR-03a', N'Multi-row insert: audit đủ 2 dòng', 0, N'Thiếu audit');
END TRY
BEGIN CATCH
    INSERT #Results VALUES('TR-03a', N'Multi-row insert: audit đủ 2 dòng', 0, N'Lỗi: ' + ERROR_MESSAGE());
END CATCH;

-- ================= TR-03b: Multi-row INSERT có 1 dòng overlap BOOKED -> trigger bắt cả 2 =================
DECLARE @m3 UNIQUEIDENTIFIER = NEWID();
BEGIN TRY
    INSERT INTO dbo.Bookings (BookingId, UserId, CourtId, StartTime, EndTime, Status, TotalCost)
    VALUES
        (@m3, @cus1, @c2, @D1_0900, @D1_1000, N'PENDING', 100000),
        (NEWID(), @cus2, @c1, @D1_0700, @D1_0900, N'BOOKED', 100000);
    INSERT #Results VALUES('TR-03b', N'Multi-row trigger bắt overlap (set-based)', 0, N'Không bị chặn (sai)');
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 51001
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM dbo.Bookings WHERE BookingId=@m3)
            INSERT #Results VALUES('TR-03b', N'Multi-row trigger bắt overlap (set-based)', 1, N'Lỗi 51001; toàn bộ statement bị chặn');
        ELSE
            INSERT #Results VALUES('TR-03b', N'Multi-row trigger bắt overlap (set-based)', 0, N'Statement vẫn ghi 1 phần (sai)');
    END
    ELSE
        INSERT #Results VALUES('TR-03b', N'Multi-row trigger bắt overlap (set-based)', 0, N'Mã lỗi: ' + CAST(ERROR_NUMBER() AS VARCHAR(10)));
END CATCH;

-- ================= TX-01: Lỗi giữa transaction -> không partial write =================
DECLARE @txId UNIQUEIDENTIFIER = NEWID();
BEGIN TRY
    BEGIN TRAN;
        INSERT INTO dbo.Bookings (BookingId, UserId, CourtId, StartTime, EndTime, Status, TotalCost)
        VALUES (@txId, @cus1, @c2, @D1_1000, @D1_1100, N'PENDING', 100000);
        SELECT 1/0;
    COMMIT;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK;
END CATCH;

IF NOT EXISTS (SELECT 1 FROM dbo.Bookings WHERE BookingId=@txId)
   AND NOT EXISTS (SELECT 1 FROM dbo.ActivityLogs WHERE BookingId=@txId)
    INSERT #Results VALUES('TX-01', N'Lỗi giữa transaction → không partial write', 1, N'ROLLBACK; không còn booking/audit');
ELSE
    INSERT #Results VALUES('TX-01', N'Lỗi giữa transaction → không partial write', 0, N'Còn dữ liệu sót (sai)');

-- ================= Invariant check: không tồn tại 2 BOOKED overlap =================
IF NOT EXISTS
(
    SELECT 1
    FROM dbo.Bookings a
    INNER JOIN dbo.Bookings b
        ON b.CourtId = a.CourtId AND b.BookingId <> a.BookingId
       AND b.Status = N'BOOKED'
       AND a.StartTime < b.EndTime AND b.StartTime < a.EndTime
    WHERE a.Status = N'BOOKED'
)
    INSERT #Results VALUES('INV-01', N'Invariant: không có 2 BOOKED overlap cùng sân', 1, N'OK');
ELSE
    INSERT #Results VALUES('INV-01', N'Invariant: không có 2 BOOKED overlap cùng sân', 0, N'Tồn tại overlap');

-- ================= SP-10: Cross-midnight booking bị từ chối (KNOWN-01 fix) =================
DECLARE @midId UNIQUEIDENTIFIER = NEWID();
DECLARE @midStart datetime2(0) = DATETIMEFROMPARTS(YEAR(@d1),MONTH(@d1),DAY(@d1),21,30,0,0);
DECLARE @midEnd datetime2(0) = DATEADD(MINUTE, 180, @midStart);
BEGIN TRY
    EXEC dbo.sp_Login @Username=N'customer1', @Password=N'cus1pass';
    EXEC dbo.sp_BookCourt @UserId=@cus1, @CourtId=@c3, @StartTime=@midStart, @EndTime=@midEnd,
         @BookingId=@midId OUTPUT, @TotalCost=@tc OUTPUT;
    INSERT #Results VALUES('SP-10', N'Cross-midnight (21:30→00:30) bị từ chối', 0, N'Không bị chặn (sai)');
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50023
        INSERT #Results VALUES('SP-10', N'Cross-midnight (21:30→00:30) bị từ chối', 1, N'Lỗi 50023: không được qua đêm');
    ELSE
        INSERT #Results VALUES('SP-10', N'Cross-midnight (21:30→00:30) bị từ chối', 0, N'Mã lỗi: ' + CAST(ERROR_NUMBER() AS VARCHAR(10)));
END CATCH;

-- ============================================================
-- NEGATIVE SECURITY TESTS (SESSION_CONTEXT bắt buộc - Option A)
-- ============================================================
-- SP-11: Chưa đăng nhập (SESSION_CONTEXT rỗng) + UserId customer tùy ý
--        → sp_BookCourt phải bị từ chối 50010, không ghi gì.
EXEC sp_set_session_context @key=N'UserId', @value=NULL;
EXEC sp_set_session_context @key=N'Role', @value=NULL;
DECLARE @ctxId UNIQUEIDENTIFIER = NEWID();
BEGIN TRY
    EXEC dbo.sp_BookCourt @UserId=@cus1, @CourtId=@c3, @StartTime=@D1_0600, @EndTime=@D1_0700,
         @BookingId=@ctxId OUTPUT, @TotalCost=@tc OUTPUT;
    INSERT #Results VALUES('SP-11', N'Không SESSION_CONTEXT + UserId customer tùy ý bị chặn', 0, N'Không bị chặn (sai)');
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50010
       AND NOT EXISTS (SELECT 1 FROM dbo.Bookings WHERE BookingId=@ctxId)
        INSERT #Results VALUES('SP-11', N'Không SESSION_CONTEXT + UserId customer tùy ý bị chặn', 1, N'Lỗi 50010; không ghi booking');
    ELSE
        INSERT #Results VALUES('SP-11', N'Không SESSION_CONTEXT + UserId customer tùy ý bị chặn', 0, N'Mã lỗi: ' + CAST(ERROR_NUMBER() AS VARCHAR(10)));
END CATCH;

-- SP-12: Chưa đăng nhập + UserId manager tùy ý
--        → sp_ApproveBooking phải bị từ chối 50030 (không có phiên),
--        không cần booking hợp lệ vì guard phiên chạy trước khi lookup.
BEGIN TRY
    EXEC dbo.sp_ApproveBooking @SessionUserId=@mgr, @BookingId='B1000001-0000-0000-0000-000000000004';
    INSERT #Results VALUES('SP-12', N'Không SESSION_CONTEXT + UserId manager tùy ý bị chặn', 0, N'Không bị chặn (sai)');
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50030
        INSERT #Results VALUES('SP-12', N'Không SESSION_CONTEXT + UserId manager tùy ý bị chặn', 1, N'Lỗi 50030 phiên chưa đăng nhập');
    ELSE
        INSERT #Results VALUES('SP-12', N'Không SESSION_CONTEXT + UserId manager tùy ý bị chặn', 0, N'Mã lỗi: ' + CAST(ERROR_NUMBER() AS VARCHAR(10)));
END CATCH;

-- SP-13: GetMyBookings chưa đăng nhập (không fallback) -> 51054
BEGIN TRY
    EXEC dbo.sp_GetMyBookings @UserId=@cus1;
    INSERT #Results VALUES('SP-13', N'GetMyBookings không phiên bị chặn (hết fallback)', 0, N'Không bị chặn (sai)');
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 51054
        INSERT #Results VALUES('SP-13', N'GetMyBookings không phiên bị chặn (hết fallback)', 1, N'Lỗi 51054');
    ELSE
        INSERT #Results VALUES('SP-13', N'GetMyBookings không phiên bị chặn (hết fallback)', 0, N'Mã lỗi: ' + CAST(ERROR_NUMBER() AS VARCHAR(10)));
END CATCH;

-- SP-14: GetNotifications chưa đăng nhập -> 51060
BEGIN TRY
    EXEC dbo.sp_GetNotifications @UserId=@cus1;
    INSERT #Results VALUES('SP-14', N'GetNotifications không phiên bị chặn', 0, N'Không bị chặn (sai)');
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 51060
        INSERT #Results VALUES('SP-14', N'GetNotifications không phiên bị chặn', 1, N'Lỗi 51060');
    ELSE
        INSERT #Results VALUES('SP-14', N'GetNotifications không phiên bị chặn', 0, N'Mã lỗi: ' + CAST(ERROR_NUMBER() AS VARCHAR(10)));
END CATCH;

-- ============================================================
-- Từ đây: đăng nhập đúng actor rồi thử impersonation (truyền UserId/khác)
-- ============================================================
-- SP-15: Session = customer1, truyền @UserId=@cus2 → sp_BookCourt 50010
EXEC dbo.sp_Login @Username=N'customer1', @Password=N'cus1pass';
DECLARE @imId UNIQUEIDENTIFIER = NEWID();
BEGIN TRY
    EXEC dbo.sp_BookCourt @UserId=@cus2, @CourtId=@c5, @StartTime=@D1_1000, @EndTime=@D1_1100,
         @BookingId=@imId OUTPUT, @TotalCost=@tc OUTPUT;
    INSERT #Results VALUES('SP-15', N'Book sai actor (SESSION_CONTEXT=cus1, UserId=cus2) bị chặn', 0, N'Không bị chặn (sai)');
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50010
       AND NOT EXISTS (SELECT 1 FROM dbo.Bookings WHERE BookingId=@imId)
        INSERT #Results VALUES('SP-15', N'Book sai actor (SESSION_CONTEXT=cus1, UserId=cus2) bị chặn', 1, N'Lỗi 50010; không ghi booking');
    ELSE
        INSERT #Results VALUES('SP-15', N'Book sai actor (SESSION_CONTEXT=cus1, UserId=cus2) bị chặn', 0, N'Mã lỗi: ' + CAST(ERROR_NUMBER() AS VARCHAR(10)));
END CATCH;

-- SP-16: Session = customer1, GetMyBookings @UserId=@cus2 → 51054
BEGIN TRY
    EXEC dbo.sp_GetMyBookings @UserId=@cus2;
    INSERT #Results VALUES('SP-16', N'GetMyBookings cross-user (cus1↔cus2) bị chặn', 0, N'Không bị chặn (sai)');
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 51054
        INSERT #Results VALUES('SP-16', N'GetMyBookings cross-user (cus1↔cus2) bị chặn', 1, N'Lỗi 51054: không khớp phiên đăng nhập');
    ELSE
        INSERT #Results VALUES('SP-16', N'GetMyBookings cross-user (cus1↔cus2) bị chặn', 0, N'Mã lỗi: ' + CAST(ERROR_NUMBER() AS VARCHAR(10)));
END CATCH;

-- SP-17: Session = customer1, GetNotifications @UserId=@cus2 → 51060
BEGIN TRY
    EXEC dbo.sp_GetNotifications @UserId=@cus2;
    INSERT #Results VALUES('SP-17', N'GetNotifications cross-user (cus1↔cus2) bị chặn', 0, N'Không bị chặn (sai)');
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 51060
        INSERT #Results VALUES('SP-17', N'GetNotifications cross-user (cus1↔cus2) bị chặn', 1, N'Lỗi 51060');
    ELSE
        INSERT #Results VALUES('SP-17', N'GetNotifications cross-user (cus1↔cus2) bị chặn', 0, N'Mã lỗi: ' + CAST(ERROR_NUMBER() AS VARCHAR(10)));
END CATCH;

-- SP-18: GetDashboard impersonation - session = courtmanager1, truyền @SessionUserId=@cm2 → 50110
EXEC dbo.sp_Login @Username=N'courtmanager1', @Password=N'cm1pass';
BEGIN TRY
    EXEC dbo.sp_GetDashboard @SessionUserId=@cm2;
    INSERT #Results VALUES('SP-18', N'GetDashboard impersonation (cm1↔cm2) bị chặn', 0, N'Không bị chặn (sai)');
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50110
        INSERT #Results VALUES('SP-18', N'GetDashboard impersonation (cm1↔cm2) bị chặn', 1, N'Lỗi 50110');
    ELSE
        INSERT #Results VALUES('SP-18', N'GetDashboard impersonation (cm1↔cm2) bị chặn', 0, N'Mã lỗi: ' + CAST(ERROR_NUMBER() AS VARCHAR(10)));
END CATCH;

-- SP-19: GetDashboard không phiên (session trống + UserId manager tùy ý) → 50110
EXEC sp_set_session_context @key=N'UserId', @value=NULL;
EXEC sp_set_session_context @key=N'Role', @value=NULL;
BEGIN TRY
    EXEC dbo.sp_GetDashboard @SessionUserId=@cm1;
    INSERT #Results VALUES('SP-19', N'GetDashboard không phiên + UserId tùy ý bị chặn', 0, N'Không bị chặn (sai)');
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50110
        INSERT #Results VALUES('SP-19', N'GetDashboard không phiên + UserId tùy ý bị chặn', 1, N'Lỗi 50110');
    ELSE
        INSERT #Results VALUES('SP-19', N'GetDashboard không phiên + UserId tùy ý bị chặn', 0, N'Mã lỗi: ' + CAST(ERROR_NUMBER() AS VARCHAR(10)));
END CATCH;

-- ============================================================
-- ============================================================
-- SP-20: Booking management impersonation - session=customer1, truyền @SessionUserId=@mgr
--        → sp_ApproveBooking phải bị chặn 50030 (không khớp phiên).
-- ============================================================
-- Tạo 1 booking PENDING bằng phiên đúng (customer1) để có target
DECLARE @mgmtId UNIQUEIDENTIFIER = NEWID();
EXEC dbo.sp_Login @Username=N'customer1', @Password=N'cus1pass';
EXEC dbo.sp_BookCourt @UserId=@cus1, @CourtId=@c3, @StartTime=@D1_0900, @EndTime=@D1_1000,
     @BookingId=@mgmtId OUTPUT, @TotalCost=@tc OUTPUT;
BEGIN TRY
    -- vẫn session=customer1 nhưng claim là manager
    EXEC dbo.sp_ApproveBooking @SessionUserId=@mgr, @BookingId=@mgmtId;
    INSERT #Results VALUES('SP-20', N'Approve impersonation (session=cus1, claim=mgr) bị chặn', 0, N'Không bị chặn (sai)');
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50030
        INSERT #Results VALUES('SP-20', N'Approve impersonation (session=cus1, claim=mgr) bị chặn', 1, N'Lỗi 50030');
    ELSE
        INSERT #Results VALUES('SP-20', N'Approve impersonation (session=cus1, claim=mgr) bị chặn', 0, N'Mã lỗi: ' + CAST(ERROR_NUMBER() AS VARCHAR(10)));
END CATCH;

-- SP-21: Session = customer1, truyền @SessionUserId=@cus2 → sp_CancelBooking 50050
BEGIN TRY
    EXEC dbo.sp_CancelBooking @SessionUserId=@cus2, @BookingId=@mgmtId;
    INSERT #Results VALUES('SP-21', N'Cancel impersonation (session=cus1, claim=cus2) bị chặn', 0, N'Không bị chặn (sai)');
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50050
        INSERT #Results VALUES('SP-21', N'Cancel impersonation (session=cus1, claim=cus2) bị chặn', 1, N'Lỗi 50050');
    ELSE
        INSERT #Results VALUES('SP-21', N'Cancel impersonation (session=cus1, claim=cus2) bị chặn', 0, N'Mã lỗi: ' + CAST(ERROR_NUMBER() AS VARCHAR(10)));
END CATCH;

-- ============================================================
-- SEC-01..05: chống giả mạo SESSION_CONTEXT (P0) — chạy dưới principal bcm_app
-- Fix (08_security.sql): DENY EXECUTE ON sys.sp_set_session_context TO bcm_app
-- ở master scope (login). bcm_app chỉ có context hợp lệ qua sp_Login.
-- ============================================================

-- ---- SEC-01/SEC-02: bcm_app tự gán UserId/Role → phải bị chặn CHÍNH XÁC mã 229
-- (EXECUTE permission denied trên sys.sp_set_session_context) - không chỉ "có lỗi".
-- Trạng thái: 0 = chưa rõ/lỗi khác, 1 = set THÀNH CÔNG (lỗ hổng), -1 = bị chặn 229.
EXECUTE AS USER = N'bcm_app';
DECLARE @sec1_state INT = 0, @sec1_msg NVARCHAR(300);
DECLARE @sec2_state INT = 0, @sec2_msg NVARCHAR(300);
BEGIN TRY
    EXEC sys.sp_set_session_context @key=N'UserId', @value=@mgr;
    SET @sec1_state = 1;
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 229
        SET @sec1_state = -1;
    SET @sec1_msg = ERROR_MESSAGE();
END CATCH;
BEGIN TRY
    EXEC sys.sp_set_session_context @key=N'Role', @value=N'MANAGER';
    SET @sec2_state = 1;
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 229
        SET @sec2_state = -1;
    SET @sec2_msg = ERROR_MESSAGE();
END CATCH;
REVERT;
IF @sec1_state = -1
    INSERT #Results VALUES('SEC-01', N'bcm_app tự gán SESSION_CONTEXT UserId bị chặn (giả mạo)', 1, N'EXECUTE permission denied (229) trên sp_set_session_context');
ELSE IF @sec1_state = 1
    INSERT #Results VALUES('SEC-01', N'bcm_app tự gán SESSION_CONTEXT UserId bị chặn (giả mạo)', 0, N'KHÔNG bị chặn - lỗ hổng còn hở');
ELSE
    INSERT #Results VALUES('SEC-01', N'bcm_app tự gán SESSION_CONTEXT UserId bị chặn (giả mạo)', 0, LEFT(ISNULL(@sec1_msg, N'Lỗi khác không phải 229'),250));
IF @sec2_state = -1
    INSERT #Results VALUES('SEC-02', N'bcm_app tự gán SESSION_CONTEXT Role bị chặn (giả mạo)', 1, N'EXECUTE permission denied (229) trên sp_set_session_context');
ELSE IF @sec2_state = 1
    INSERT #Results VALUES('SEC-02', N'bcm_app tự gán SESSION_CONTEXT Role bị chặn (giả mạo)', 0, N'KHÔNG bị chặn - lỗ hổng còn hở');
ELSE
    INSERT #Results VALUES('SEC-02', N'bcm_app tự gán SESSION_CONTEXT Role bị chặn (giả mạo)', 0, LEFT(ISNULL(@sec2_msg, N'Lỗi khác không phải 229'),250));

-- ---- SEC-03: sp_Login dưới bcm_app vẫn tạo context hợp lệ (chỉ có qua SP này) ----
EXECUTE AS USER = N'bcm_app';
DECLARE @sec3_ok BIT = 0, @sec3_note NVARCHAR(300);
BEGIN TRY
    EXEC dbo.sp_Login @Username=N'manager', @Password=N'manager123';
    IF CONVERT(UNIQUEIDENTIFIER, SESSION_CONTEXT(N'UserId')) = @mgr
       AND CONVERT(VARCHAR(20), SESSION_CONTEXT(N'Role')) = N'MANAGER'
        SET @sec3_ok = 1;
END TRY
BEGIN CATCH
    SET @sec3_note = ERROR_MESSAGE();
END CATCH;
REVERT;
IF @sec3_ok = 1
    INSERT #Results VALUES('SEC-03', N'sp_Login (bcm_app) tạo context MANAGER hợp lệ', 1, N'UserId+Role đúng, SESSION_CONTEXT ENFORCED');
ELSE
    INSERT #Results VALUES('SEC-03', N'sp_Login (bcm_app) tạo context MANAGER hợp lệ', 0, ISNULL(@sec3_note, N'Context không khớp'));

-- Xóa context (admin) để mô tả attacker chưa login trước khi approve
EXEC sys.sp_set_session_context @key=N'UserId', @value=NULL;
EXEC sys.sp_set_session_context @key=N'Role', @value=NULL;

-- ---- SEC-04: giả mạo manager rồi approve → phải bị chặn (229 nếu không set được context; 50030/50031 nếu approve chạy) ----
EXECUTE AS USER = N'bcm_app';
DECLARE @sec4_ok BIT = 0, @sec4_err INT = 0, @sec4_msg NVARCHAR(300);
BEGIN TRY
    EXEC sys.sp_set_session_context @key=N'UserId', @value=@mgr;  -- phải fail (không thể giả)
END TRY
BEGIN CATCH
    SET @sec4_err = ERROR_NUMBER();
    SET @sec4_msg = ERROR_MESSAGE();
END CATCH;
IF @sec4_err = 0  -- set thành công (bất thường) → thử approve
BEGIN
    BEGIN TRY
        EXEC dbo.sp_ApproveBooking @SessionUserId=@mgr, @BookingId=@mgmtId;
        SET @sec4_ok = 1;
    END TRY
    BEGIN CATCH
        SET @sec4_err = ERROR_NUMBER();
        SET @sec4_msg = ERROR_MESSAGE();
    END CATCH;
END;
REVERT;
IF @sec4_err = 229
    INSERT #Results VALUES('SEC-04', N'Approve w/o session (attacker giả manager) bị chặn', 1, N'Không set được context (229); approve không thể chạy với giả manager');
ELSE IF @sec4_err IN (50030, 50031)
    INSERT #Results VALUES('SEC-04', N'Approve w/o session (attacker giả manager) bị chặn', 1, N'Mã lỗi: ' + CAST(@sec4_err AS VARCHAR(10)));
ELSE IF @sec4_ok = 1
    INSERT #Results VALUES('SEC-04', N'Approve w/o session (attacker giả manager) bị chặn', 0, N'Approve không bị chặn');
ELSE
    INSERT #Results VALUES('SEC-04', N'Approve w/o session (attacker giả manager) bị chặn', 0, ISNULL(@sec4_msg, N'Lỗi không xác định'));

-- ---- SEC-05: Guest browse sân trống vẫn public qua sp_GetAvailableCourts ----
EXECUTE AS USER = N'bcm_app';
DECLARE @sec5_cnt INT = 0, @sec5_msg NVARCHAR(300);
DECLARE @freeD DATE = DATEADD(DAY, 20, CAST(GETDATE() AS DATE));
DECLARE @sec5_s DATETIME2(0), @sec5_e DATETIME2(0);
SET @sec5_s = CONVERT(DATETIME2(0), CONCAT(CONVERT(VARCHAR(10), @freeD, 23), ' 09:00:00'));
SET @sec5_e = CONVERT(DATETIME2(0), CONCAT(CONVERT(VARCHAR(10), @freeD, 23), ' 10:00:00'));
BEGIN TRY
    DECLARE @sec5 TABLE (CourtId UNIQUEIDENTIFIER, CourtName NVARCHAR(100), Address NVARCHAR(255),
                         SurfaceType NVARCHAR(20), SizeType NVARCHAR(20), PricePerHour DECIMAL(12,0),
                         PricePerThreeHours DECIMAL(12,0), IsAvailable BIT);
    INSERT INTO @sec5
    EXEC dbo.sp_GetAvailableCourts @StartTime=@sec5_s, @EndTime=@sec5_e;
    SELECT @sec5_cnt = COUNT(*) FROM @sec5;
END TRY
BEGIN CATCH
    SET @sec5_msg = ERROR_MESSAGE();
END CATCH;
REVERT;
IF @sec5_cnt > 0
    INSERT #Results VALUES('SEC-05', N'Guest browse sp_GetAvailableCourts public (no session)', 1, N'Số sân trống: ' + CAST(@sec5_cnt AS VARCHAR(10)));
ELSE
    INSERT #Results VALUES('SEC-05', N'Guest browse sp_GetAvailableCourts public (no session)', 0, ISNULL(@sec5_msg, N'0 sân trống (sai)'));

-- ============================================================
-- SUMMARY
-- ============================================================
SELECT
    COUNT(*)                                              AS Total,
    SUM(CASE WHEN [pass] = 1 THEN 1 ELSE 0 END)          AS Passed,
    SUM(CASE WHEN [pass] = 0 THEN 1 ELSE 0 END)          AS Failed
FROM #Results;

SELECT id, name, CASE WHEN [pass]=1 THEN N'PASS' ELSE N'FAIL' END AS Result, note
FROM #Results
ORDER BY id;

PRINT N'--- Kết thúc 09_tests_functional.sql. Xem bảng #Results ở trên (Total/Passed/Failed) ---';
PRINT N'--- Các test multi-session (CC/PH/DL) chạy riêng trong 10→14. ---';
GO