/* ============================================================
   BadmintonCourtManagement
   Script : tests/regression/imp_regression.sql
   Mục đích: test TẮT CẢ các cải tiến FIX-NULLROLE / IMP-01 / IMP-05 /
             IMP-09 trên SQL Server THẬT — từng khả năng, kể cả các ca
             đúng (negative control) để chắc rằng ràng buộc mới KHÔNG
             chặn dữ liệu hợp lệ.
   Chạy sau khi đã chạy 00→08. Chạy lại được nhiều lần.
   Mọi test thay đổi dữ liệu đều nằm trong BEGIN TRAN ... ROLLBACK
   nên KHÔNG làm bẩn DB.

   sqlcmd -S ".\SQLEXPRESS" -E -f 65001 -i tests\regression\imp_regression.sql
   ============================================================ */

USE BadmintonCourtManagement;
GO

SET NOCOUNT ON;
SET XACT_ABORT OFF;   -- harness: cần bắt lỗi rồi tiếp tục
GO

IF OBJECT_ID('tempdb..#R') IS NOT NULL DROP TABLE #R;
GO
CREATE TABLE #R
(
    id     VARCHAR(20)   NOT NULL,
    name   NVARCHAR(200) NOT NULL,
    [pass] BIT           NOT NULL,
    note   NVARCHAR(500) NULL
);
GO

-- ============================================================
-- BIẾN CHUNG
-- ============================================================
DECLARE @ghost    UNIQUEIDENTIFIER = 'FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF';  -- user không tồn tại
DECLARE @inactive UNIQUEIDENTIFIER = 'A1000001-0000-0000-0000-000000000007';  -- inactive_user
DECLARE @cus1     UNIQUEIDENTIFIER = 'A1000001-0000-0000-0000-000000000004';
DECLARE @cus2     UNIQUEIDENTIFIER = 'A1000001-0000-0000-0000-000000000005';
DECLARE @cm1      UNIQUEIDENTIFIER = 'A1000001-0000-0000-0000-000000000002';
DECLARE @court1   UNIQUEIDENTIFIER = 'C1000001-0000-0000-0000-000000000001';
DECLARE @court2   UNIQUEIDENTIFIER = 'C1000001-0000-0000-0000-000000000002';
DECLARE @dummy    UNIQUEIDENTIFIER = '00000000-0000-0000-0000-000000000001';

DECLARE @d DATE = DATEADD(DAY, 7, CAST(GETDATE() AS DATE));   -- xa seed để không chạm dữ liệu mẫu
DECLARE @y INT = YEAR(@d), @m INT = MONTH(@d), @dd INT = DAY(@d);
DECLARE @t0500 DATETIME2(0) = DATETIME2FROMPARTS(@y, @m, @dd,  5,  0, 0, 0, 0);
DECLARE @t0600 DATETIME2(0) = DATETIME2FROMPARTS(@y, @m, @dd,  6,  0, 0, 0, 0);
DECLARE @t0630 DATETIME2(0) = DATETIME2FROMPARTS(@y, @m, @dd,  6, 30, 0, 0, 0);
DECLARE @t0800 DATETIME2(0) = DATETIME2FROMPARTS(@y, @m, @dd,  8,  0, 0, 0, 0);
DECLARE @t0815 DATETIME2(0) = DATETIME2FROMPARTS(@y, @m, @dd,  8, 15, 0, 0, 0);
DECLARE @t0830 DATETIME2(0) = DATETIME2FROMPARTS(@y, @m, @dd,  8, 30, 0, 0, 0);
DECLARE @t0830s DATETIME2(0) = DATETIME2FROMPARTS(@y, @m, @dd, 8, 30, 30, 0, 0);
DECLARE @t0900 DATETIME2(0) = DATETIME2FROMPARTS(@y, @m, @dd,  9,  0, 0, 0, 0);
DECLARE @t0930 DATETIME2(0) = DATETIME2FROMPARTS(@y, @m, @dd,  9, 30, 0, 0, 0);
DECLARE @t1000 DATETIME2(0) = DATETIME2FROMPARTS(@y, @m, @dd, 10,  0, 0, 0, 0);
DECLARE @t1030 DATETIME2(0) = DATETIME2FROMPARTS(@y, @m, @dd, 10, 30, 0, 0, 0);
DECLARE @t1100 DATETIME2(0) = DATETIME2FROMPARTS(@y, @m, @dd, 11,  0, 0, 0, 0);
DECLARE @t1200 DATETIME2(0) = DATETIME2FROMPARTS(@y, @m, @dd, 12,  0, 0, 0, 0);
DECLARE @t2100 DATETIME2(0) = DATETIME2FROMPARTS(@y, @m, @dd, 21,  0, 0, 0, 0);
DECLARE @t2300 DATETIME2(0) = DATETIME2FROMPARTS(@y, @m, @dd, 23,  0, 0, 0, 0);
DECLARE @tNext0030 DATETIME2(0) = DATEADD(MINUTE, 90, @t2300);   -- 00:30 ngày sau
DECLARE @bid UNIQUEIDENTIFIER;

PRINT N'--- Nhóm A: FIX-NULLROLE (user không tồn tại / đã vô hiệu hóa) ---';

-- RG-01 sp_BookCourt
BEGIN TRY
    EXEC dbo.sp_BookCourt @UserId = @ghost, @CourtId = @court1, @StartTime = @t0800, @EndTime = @t0900;
    INSERT #R VALUES ('RG-01', N'sp_BookCourt chặn user không tồn tại', 0, N'KHÔNG throw — lọt quyền');
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK;
    INSERT #R VALUES ('RG-01', N'sp_BookCourt chặn user không tồn tại',
        CASE WHEN ERROR_NUMBER() = 50010 THEN 1 ELSE 0 END, CONCAT(N'err=', ERROR_NUMBER()));
END CATCH

-- RG-02 sp_ApproveBooking
BEGIN TRY
    EXEC dbo.sp_ApproveBooking @SessionUserId = @ghost, @BookingId = @dummy;
    INSERT #R VALUES ('RG-02', N'sp_ApproveBooking chặn user không tồn tại', 0, N'KHÔNG throw — lọt quyền');
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK;
    INSERT #R VALUES ('RG-02', N'sp_ApproveBooking chặn user không tồn tại',
        CASE WHEN ERROR_NUMBER() = 50030 THEN 1 ELSE 0 END, CONCAT(N'err=', ERROR_NUMBER()));
END CATCH

-- RG-03 sp_RejectBooking
BEGIN TRY
    EXEC dbo.sp_RejectBooking @SessionUserId = @ghost, @BookingId = @dummy;
    INSERT #R VALUES ('RG-03', N'sp_RejectBooking chặn user không tồn tại', 0, N'KHÔNG throw — lọt quyền');
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK;
    INSERT #R VALUES ('RG-03', N'sp_RejectBooking chặn user không tồn tại',
        CASE WHEN ERROR_NUMBER() = 50040 THEN 1 ELSE 0 END, CONCAT(N'err=', ERROR_NUMBER()));
END CATCH

-- RG-04 sp_CancelBooking
BEGIN TRY
    EXEC dbo.sp_CancelBooking @SessionUserId = @ghost, @BookingId = @dummy;
    INSERT #R VALUES ('RG-04', N'sp_CancelBooking chặn user không tồn tại', 0, N'KHÔNG throw — lọt quyền');
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK;
    INSERT #R VALUES ('RG-04', N'sp_CancelBooking chặn user không tồn tại',
        CASE WHEN ERROR_NUMBER() = 50050 THEN 1 ELSE 0 END, CONCAT(N'err=', ERROR_NUMBER()));
END CATCH

-- RG-05 sp_CompleteBooking
BEGIN TRY
    EXEC dbo.sp_CompleteBooking @SessionUserId = @ghost, @BookingId = @dummy;
    INSERT #R VALUES ('RG-05', N'sp_CompleteBooking chặn user không tồn tại', 0, N'KHÔNG throw — lọt quyền');
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK;
    INSERT #R VALUES ('RG-05', N'sp_CompleteBooking chặn user không tồn tại',
        CASE WHEN ERROR_NUMBER() = 50060 THEN 1 ELSE 0 END, CONCAT(N'err=', ERROR_NUMBER()));
END CATCH

-- RG-06 sp_CreateCourt
BEGIN TRY
    EXEC dbo.sp_CreateCourt @SessionUserId = @ghost, @CourtName = N'Sân test', @Address = N'Địa chỉ test',
         @SurfaceType = N'STANDARD', @SizeType = N'SINGLE', @PricePerHour = 100000, @PricePerThreeHours = 270000;
    INSERT #R VALUES ('RG-06', N'sp_CreateCourt chặn user không tồn tại', 0, N'KHÔNG throw — TẠO ĐƯỢC SÂN!');
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK;
    INSERT #R VALUES ('RG-06', N'sp_CreateCourt chặn user không tồn tại',
        CASE WHEN ERROR_NUMBER() = 50070 THEN 1 ELSE 0 END, CONCAT(N'err=', ERROR_NUMBER()));
END CATCH

-- RG-07 sp_UpdateCourt
BEGIN TRY
    EXEC dbo.sp_UpdateCourt @SessionUserId = @ghost, @CourtId = @court1, @CourtName = N'Sân hack',
         @Address = N'X', @SurfaceType = N'VIP', @SizeType = N'DOUBLE', @PricePerHour = 1, @PricePerThreeHours = 1;
    INSERT #R VALUES ('RG-07', N'sp_UpdateCourt chặn user không tồn tại', 0, N'KHÔNG throw — SỬA ĐƯỢC GIÁ!');
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK;
    INSERT #R VALUES ('RG-07', N'sp_UpdateCourt chặn user không tồn tại',
        CASE WHEN ERROR_NUMBER() = 50080 THEN 1 ELSE 0 END, CONCAT(N'err=', ERROR_NUMBER()));
END CATCH

-- RG-08 sp_DeactivateCourt
BEGIN TRY
    EXEC dbo.sp_DeactivateCourt @SessionUserId = @ghost, @CourtId = @court1;
    INSERT #R VALUES ('RG-08', N'sp_DeactivateCourt chặn user không tồn tại', 0, N'KHÔNG throw — TẮT ĐƯỢC SÂN!');
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK;
    INSERT #R VALUES ('RG-08', N'sp_DeactivateCourt chặn user không tồn tại',
        CASE WHEN ERROR_NUMBER() = 50090 THEN 1 ELSE 0 END, CONCAT(N'err=', ERROR_NUMBER()));
END CATCH

-- RG-09 sp_GetDashboard
BEGIN TRY
    EXEC dbo.sp_GetDashboard @SessionUserId = @ghost;
    INSERT #R VALUES ('RG-09', N'sp_GetDashboard chặn user không tồn tại', 0, N'KHÔNG throw — XEM ĐƯỢC DOANH THU!');
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK;
    INSERT #R VALUES ('RG-09', N'sp_GetDashboard chặn user không tồn tại',
        CASE WHEN ERROR_NUMBER() = 50110 THEN 1 ELSE 0 END, CONCAT(N'err=', ERROR_NUMBER()));
END CATCH

-- RG-10..RG-12: user TỒN TẠI nhưng IsActive = 0
BEGIN TRY
    EXEC dbo.sp_RejectBooking @SessionUserId = @inactive, @BookingId = @dummy;
    INSERT #R VALUES ('RG-10', N'sp_RejectBooking chặn user đã vô hiệu hóa', 0, N'KHÔNG throw');
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK;
    INSERT #R VALUES ('RG-10', N'sp_RejectBooking chặn user đã vô hiệu hóa',
        CASE WHEN ERROR_NUMBER() = 50040 THEN 1 ELSE 0 END, CONCAT(N'err=', ERROR_NUMBER()));
END CATCH

BEGIN TRY
    EXEC dbo.sp_CreateCourt @SessionUserId = @inactive, @CourtName = N'Sân test 2', @Address = N'Địa chỉ test',
         @SurfaceType = N'STANDARD', @SizeType = N'SINGLE', @PricePerHour = 100000, @PricePerThreeHours = 270000;
    INSERT #R VALUES ('RG-11', N'sp_CreateCourt chặn user đã vô hiệu hóa', 0, N'KHÔNG throw');
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK;
    INSERT #R VALUES ('RG-11', N'sp_CreateCourt chặn user đã vô hiệu hóa',
        CASE WHEN ERROR_NUMBER() = 50070 THEN 1 ELSE 0 END, CONCAT(N'err=', ERROR_NUMBER()));
END CATCH

BEGIN TRY
    EXEC dbo.sp_GetDashboard @SessionUserId = @inactive;
    INSERT #R VALUES ('RG-12', N'sp_GetDashboard chặn user đã vô hiệu hóa', 0, N'KHÔNG throw');
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK;
    INSERT #R VALUES ('RG-12', N'sp_GetDashboard chặn user đã vô hiệu hóa',
        CASE WHEN ERROR_NUMBER() = 50110 THEN 1 ELSE 0 END, CONCAT(N'err=', ERROR_NUMBER()));
END CATCH

PRINT N'--- Nhóm B: IMP-01 CHECK constraint (INSERT trực tiếp, kể cả khi không qua SP) ---';

-- RG-13 30 phút (dưới 1 giờ)
BEGIN TRY
    BEGIN TRAN;
        INSERT dbo.Bookings (BookingId, UserId, CourtId, StartTime, EndTime, Status, TotalCost)
        VALUES (NEWID(), @cus1, @court1, @t0800, @t0830, N'PENDING', 50000);
    ROLLBACK;
    INSERT #R VALUES ('RG-13', N'CHECK chặn booking 30 phút', 0, N'KHÔNG bị chặn');
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK;
    INSERT #R VALUES ('RG-13', N'CHECK chặn booking 30 phút',
        CASE WHEN ERROR_NUMBER() = 547 THEN 1 ELSE 0 END, CONCAT(N'err=', ERROR_NUMBER()));
END CATCH

-- RG-14 4 giờ (vượt 3 giờ)
BEGIN TRY
    BEGIN TRAN;
        INSERT dbo.Bookings (BookingId, UserId, CourtId, StartTime, EndTime, Status, TotalCost)
        VALUES (NEWID(), @cus1, @court1, @t0800, @t1200, N'PENDING', 400000);
    ROLLBACK;
    INSERT #R VALUES ('RG-14', N'CHECK chặn booking 4 giờ', 0, N'KHÔNG bị chặn');
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK;
    INSERT #R VALUES ('RG-14', N'CHECK chặn booking 4 giờ',
        CASE WHEN ERROR_NUMBER() = 547 THEN 1 ELSE 0 END, CONCAT(N'err=', ERROR_NUMBER()));
END CATCH

-- RG-15 lệch mốc 30 phút (08:15)
BEGIN TRY
    BEGIN TRAN;
        INSERT dbo.Bookings (BookingId, UserId, CourtId, StartTime, EndTime, Status, TotalCost)
        VALUES (NEWID(), @cus1, @court1, @t0815, DATEADD(MINUTE, 60, @t0815), N'PENDING', 100000);
    ROLLBACK;
    INSERT #R VALUES ('RG-15', N'CHECK chặn giờ bắt đầu 08:15', 0, N'KHÔNG bị chặn');
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK;
    INSERT #R VALUES ('RG-15', N'CHECK chặn giờ bắt đầu 08:15',
        CASE WHEN ERROR_NUMBER() = 547 THEN 1 ELSE 0 END, CONCAT(N'err=', ERROR_NUMBER()));
END CATCH

-- RG-16 có giây lẻ (08:30:30)
BEGIN TRY
    BEGIN TRAN;
        INSERT dbo.Bookings (BookingId, UserId, CourtId, StartTime, EndTime, Status, TotalCost)
        VALUES (NEWID(), @cus1, @court1, @t0830s, DATEADD(MINUTE, 60, @t0830s), N'PENDING', 100000);
    ROLLBACK;
    INSERT #R VALUES ('RG-16', N'CHECK chặn giây lẻ 08:30:30', 0, N'KHÔNG bị chặn');
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK;
    INSERT #R VALUES ('RG-16', N'CHECK chặn giây lẻ 08:30:30',
        CASE WHEN ERROR_NUMBER() = 547 THEN 1 ELSE 0 END, CONCAT(N'err=', ERROR_NUMBER()));
END CATCH

-- RG-17 trước giờ mở cửa (05:00 → 06:30)
BEGIN TRY
    BEGIN TRAN;
        INSERT dbo.Bookings (BookingId, UserId, CourtId, StartTime, EndTime, Status, TotalCost)
        VALUES (NEWID(), @cus1, @court1, @t0500, @t0630, N'PENDING', 150000);
    ROLLBACK;
    INSERT #R VALUES ('RG-17', N'CHECK chặn bắt đầu 05:00 (ngoài giờ)', 0, N'KHÔNG bị chặn');
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK;
    INSERT #R VALUES ('RG-17', N'CHECK chặn bắt đầu 05:00 (ngoài giờ)',
        CASE WHEN ERROR_NUMBER() = 547 THEN 1 ELSE 0 END, CONCAT(N'err=', ERROR_NUMBER()));
END CATCH

-- RG-18 sau giờ đóng cửa (21:00 → 23:00)
BEGIN TRY
    BEGIN TRAN;
        INSERT dbo.Bookings (BookingId, UserId, CourtId, StartTime, EndTime, Status, TotalCost)
        VALUES (NEWID(), @cus1, @court1, @t2100, @t2300, N'PENDING', 200000);
    ROLLBACK;
    INSERT #R VALUES ('RG-18', N'CHECK chặn kết thúc 23:00 (ngoài giờ)', 0, N'KHÔNG bị chặn');
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK;
    INSERT #R VALUES ('RG-18', N'CHECK chặn kết thúc 23:00 (ngoài giờ)',
        CASE WHEN ERROR_NUMBER() = 547 THEN 1 ELSE 0 END, CONCAT(N'err=', ERROR_NUMBER()));
END CATCH

-- RG-19 vắt qua nửa đêm (23:00 → 00:30 ngày sau)
BEGIN TRY
    BEGIN TRAN;
        INSERT dbo.Bookings (BookingId, UserId, CourtId, StartTime, EndTime, Status, TotalCost)
        VALUES (NEWID(), @cus1, @court1, @t2300, @tNext0030, N'PENDING', 150000);
    ROLLBACK;
    INSERT #R VALUES ('RG-19', N'CHECK chặn booking qua nửa đêm', 0, N'KHÔNG bị chặn');
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK;
    INSERT #R VALUES ('RG-19', N'CHECK chặn booking qua nửa đêm',
        CASE WHEN ERROR_NUMBER() = 547 THEN 1 ELSE 0 END, CONCAT(N'err=', ERROR_NUMBER()));
END CATCH

-- RG-20 chi phí âm
BEGIN TRY
    BEGIN TRAN;
        INSERT dbo.Bookings (BookingId, UserId, CourtId, StartTime, EndTime, Status, TotalCost)
        VALUES (NEWID(), @cus1, @court1, @t0800, @t0900, N'PENDING', -1);
    ROLLBACK;
    INSERT #R VALUES ('RG-20', N'CHECK chặn TotalCost âm', 0, N'KHÔNG bị chặn');
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK;
    INSERT #R VALUES ('RG-20', N'CHECK chặn TotalCost âm',
        CASE WHEN ERROR_NUMBER() = 547 THEN 1 ELSE 0 END, CONCAT(N'err=', ERROR_NUMBER()));
END CATCH

-- RG-21 username quá ngắn
BEGIN TRY
    BEGIN TRAN;
        INSERT dbo.Users (UserId, Username, PasswordHash, PhoneNumber, Role)
        VALUES (NEWID(), N'ab', CONVERT(VARBINARY(64), HASHBYTES('SHA2_256', N'bcms|test')), N'0999888777', N'CUSTOMER');
    ROLLBACK;
    INSERT #R VALUES ('RG-21', N'CHECK chặn username < 3 ký tự', 0, N'KHÔNG bị chặn');
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK;
    INSERT #R VALUES ('RG-21', N'CHECK chặn username < 3 ký tự',
        CASE WHEN ERROR_NUMBER() = 547 THEN 1 ELSE 0 END, CONCAT(N'err=', ERROR_NUMBER()));
END CATCH

-- RG-22 số điện thoại có chữ
BEGIN TRY
    BEGIN TRAN;
        INSERT dbo.Users (UserId, Username, PasswordHash, PhoneNumber, Role)
        VALUES (NEWID(), N'test_user_x', CONVERT(VARBINARY(64), HASHBYTES('SHA2_256', N'bcms|test')), N'090abc1234', N'CUSTOMER');
    ROLLBACK;
    INSERT #R VALUES ('RG-22', N'CHECK chặn số điện thoại có chữ', 0, N'KHÔNG bị chặn');
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK;
    INSERT #R VALUES ('RG-22', N'CHECK chặn số điện thoại có chữ',
        CASE WHEN ERROR_NUMBER() = 547 THEN 1 ELSE 0 END, CONCAT(N'err=', ERROR_NUMBER()));
END CATCH

-- RG-23 tên sân toàn khoảng trắng
BEGIN TRY
    BEGIN TRAN;
        INSERT dbo.Courts (CourtId, CourtName, Address, SurfaceType, SizeType, PricePerHour, PricePerThreeHours, OwnerId)
        VALUES (NEWID(), N'   ', N'Địa chỉ hợp lệ', N'STANDARD', N'SINGLE', 100000, 270000, @cm1);
    ROLLBACK;
    INSERT #R VALUES ('RG-23', N'CHECK chặn tên sân rỗng', 0, N'KHÔNG bị chặn');
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK;
    INSERT #R VALUES ('RG-23', N'CHECK chặn tên sân rỗng',
        CASE WHEN ERROR_NUMBER() = 547 THEN 1 ELSE 0 END, CONCAT(N'err=', ERROR_NUMBER()));
END CATCH

-- RG-24 địa chỉ sân rỗng
BEGIN TRY
    BEGIN TRAN;
        INSERT dbo.Courts (CourtId, CourtName, Address, SurfaceType, SizeType, PricePerHour, PricePerThreeHours, OwnerId)
        VALUES (NEWID(), N'Sân hợp lệ', N'', N'STANDARD', N'SINGLE', 100000, 270000, @cm1);
    ROLLBACK;
    INSERT #R VALUES ('RG-24', N'CHECK chặn địa chỉ sân rỗng', 0, N'KHÔNG bị chặn');
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK;
    INSERT #R VALUES ('RG-24', N'CHECK chặn địa chỉ sân rỗng',
        CASE WHEN ERROR_NUMBER() = 547 THEN 1 ELSE 0 END, CONCAT(N'err=', ERROR_NUMBER()));
END CATCH

-- RG-25 thông báo rỗng
BEGIN TRY
    BEGIN TRAN;
        INSERT dbo.Notifications (NotificationId, UserId, BookingId, Message)
        VALUES (NEWID(), @cus1, NULL, N'   ');
    ROLLBACK;
    INSERT #R VALUES ('RG-25', N'CHECK chặn nội dung thông báo rỗng', 0, N'KHÔNG bị chặn');
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK;
    INSERT #R VALUES ('RG-25', N'CHECK chặn nội dung thông báo rỗng',
        CASE WHEN ERROR_NUMBER() = 547 THEN 1 ELSE 0 END, CONCAT(N'err=', ERROR_NUMBER()));
END CATCH

-- RG-26 ĐỐI CHỨNG: dữ liệu hợp lệ vẫn vào được (CHECK không chặn oan)
BEGIN TRY
    BEGIN TRAN;
        INSERT dbo.Bookings (BookingId, UserId, CourtId, StartTime, EndTime, Status, TotalCost)
        VALUES (NEWID(), @cus1, @court1, @t0800, @t0930, N'PENDING', 150000);
    ROLLBACK;
    INSERT #R VALUES ('RG-26', N'ĐỐI CHỨNG: booking 90 phút hợp lệ vẫn INSERT được', 1, NULL);
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK;
    INSERT #R VALUES ('RG-26', N'ĐỐI CHỨNG: booking 90 phút hợp lệ vẫn INSERT được', 0,
        CONCAT(N'BỊ CHẶN OAN, err=', ERROR_NUMBER(), N': ', ERROR_MESSAGE()));
END CATCH

PRINT N'--- Nhóm C: IMP-09 unique filtered index (chống spam PENDING) ---';

-- RG-27 cùng user + cùng sân + cùng giờ → phải bị chặn (2601)
BEGIN TRY
    BEGIN TRAN;
        INSERT dbo.Bookings (BookingId, UserId, CourtId, StartTime, EndTime, Status, TotalCost)
        VALUES (NEWID(), @cus1, @court1, @t1000, @t1100, N'PENDING', 100000);
        INSERT dbo.Bookings (BookingId, UserId, CourtId, StartTime, EndTime, Status, TotalCost)
        VALUES (NEWID(), @cus1, @court1, @t1000, @t1100, N'PENDING', 100000);
    ROLLBACK;
    INSERT #R VALUES ('RG-27', N'Chặn cùng người spam 2 PENDING trùng khung giờ', 0, N'KHÔNG bị chặn — index thiếu?');
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK;
    INSERT #R VALUES ('RG-27', N'Chặn cùng người spam 2 PENDING trùng khung giờ',
        CASE WHEN ERROR_NUMBER() IN (2601, 2627) THEN 1 ELSE 0 END, CONCAT(N'err=', ERROR_NUMBER()));
END CATCH

-- RG-28 ĐỐI CHỨNG QUAN TRỌNG: hai người KHÁC NHAU vẫn PENDING cùng khung giờ (CC-01 không vỡ)
BEGIN TRY
    BEGIN TRAN;
        INSERT dbo.Bookings (BookingId, UserId, CourtId, StartTime, EndTime, Status, TotalCost)
        VALUES (NEWID(), @cus1, @court1, @t1000, @t1100, N'PENDING', 100000);
        INSERT dbo.Bookings (BookingId, UserId, CourtId, StartTime, EndTime, Status, TotalCost)
        VALUES (NEWID(), @cus2, @court1, @t1000, @t1100, N'PENDING', 100000);
    ROLLBACK;
    INSERT #R VALUES ('RG-28', N'ĐỐI CHỨNG: 2 khách khác nhau vẫn PENDING cùng giờ', 1, NULL);
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK;
    INSERT #R VALUES ('RG-28', N'ĐỐI CHỨNG: 2 khách khác nhau vẫn PENDING cùng giờ', 0,
        CONCAT(N'VỠ CC-01! err=', ERROR_NUMBER()));
END CATCH

-- RG-29 cùng user, một BOOKED + một PENDING cùng giờ → index KHÔNG chặn (chỉ lọc PENDING)
BEGIN TRY
    BEGIN TRAN;
        INSERT dbo.Bookings (BookingId, UserId, CourtId, StartTime, EndTime, Status, TotalCost)
        VALUES (NEWID(), @cus1, @court2, @t1000, @t1100, N'BOOKED', 100000);
        INSERT dbo.Bookings (BookingId, UserId, CourtId, StartTime, EndTime, Status, TotalCost)
        VALUES (NEWID(), @cus1, @court2, @t1000, @t1100, N'PENDING', 100000);
    ROLLBACK;
    INSERT #R VALUES ('RG-29', N'Index chỉ lọc PENDING (BOOKED + PENDING cùng giờ vẫn được)', 1, NULL);
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK;
    INSERT #R VALUES ('RG-29', N'Index chỉ lọc PENDING (BOOKED + PENDING cùng giờ vẫn được)', 0,
        CONCAT(N'err=', ERROR_NUMBER(), N' (51001 = trigger overlap, không phải index)'));
END CATCH

-- RG-30 cùng user, cùng sân, KHÁC giờ → được
BEGIN TRY
    BEGIN TRAN;
        INSERT dbo.Bookings (BookingId, UserId, CourtId, StartTime, EndTime, Status, TotalCost)
        VALUES (NEWID(), @cus1, @court1, @t1000, @t1100, N'PENDING', 100000);
        INSERT dbo.Bookings (BookingId, UserId, CourtId, StartTime, EndTime, Status, TotalCost)
        VALUES (NEWID(), @cus1, @court1, @t1100, @t1200, N'PENDING', 100000);
    ROLLBACK;
    INSERT #R VALUES ('RG-30', N'Cùng người đặt 2 khung giờ khác nhau vẫn được', 1, NULL);
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK;
    INSERT #R VALUES ('RG-30', N'Cùng người đặt 2 khung giờ khác nhau vẫn được', 0, CONCAT(N'err=', ERROR_NUMBER()));
END CATCH

-- RG-31 cùng user, cùng giờ, KHÁC sân → được
BEGIN TRY
    BEGIN TRAN;
        INSERT dbo.Bookings (BookingId, UserId, CourtId, StartTime, EndTime, Status, TotalCost)
        VALUES (NEWID(), @cus1, @court1, @t1000, @t1100, N'PENDING', 100000);
        INSERT dbo.Bookings (BookingId, UserId, CourtId, StartTime, EndTime, Status, TotalCost)
        VALUES (NEWID(), @cus1, @court2, @t1000, @t1100, N'PENDING', 100000);
    ROLLBACK;
    INSERT #R VALUES ('RG-31', N'Cùng người đặt 2 sân khác nhau cùng giờ vẫn được', 1, NULL);
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK;
    INSERT #R VALUES ('RG-31', N'Cùng người đặt 2 sân khác nhau cùng giờ vẫn được', 0, CONCAT(N'err=', ERROR_NUMBER()));
END CATCH

-- RG-32 bị TỪ CHỐI rồi đặt lại đúng khung giờ đó → phải được
BEGIN TRY
    BEGIN TRAN;
        SET @bid = NEWID();
        INSERT dbo.Bookings (BookingId, UserId, CourtId, StartTime, EndTime, Status, TotalCost)
        VALUES (@bid, @cus1, @court1, @t1000, @t1100, N'PENDING', 100000);
        UPDATE dbo.Bookings SET Status = N'REJECTED', UpdatedAt = SYSDATETIME() WHERE BookingId = @bid;
        INSERT dbo.Bookings (BookingId, UserId, CourtId, StartTime, EndTime, Status, TotalCost)
        VALUES (NEWID(), @cus1, @court1, @t1000, @t1100, N'PENDING', 100000);
    ROLLBACK;
    INSERT #R VALUES ('RG-32', N'Bị từ chối rồi đặt lại cùng khung giờ vẫn được', 1, NULL);
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK;
    INSERT #R VALUES ('RG-32', N'Bị từ chối rồi đặt lại cùng khung giờ vẫn được', 0,
        CONCAT(N'err=', ERROR_NUMBER(), N' — index chặn oan!'));
END CATCH

-- RG-33 metadata của index
INSERT #R
SELECT 'RG-33', N'UQ_Bookings_OnePendingPerUserSlot tồn tại, unique, có filter',
       CASE WHEN EXISTS (SELECT 1 FROM sys.indexes
                         WHERE name = N'UQ_Bookings_OnePendingPerUserSlot'
                           AND object_id = OBJECT_ID(N'dbo.Bookings')
                           AND is_unique = 1 AND has_filter = 1)
            THEN 1 ELSE 0 END,
       (SELECT MAX(filter_definition) FROM sys.indexes
        WHERE name = N'UQ_Bookings_OnePendingPerUserSlot' AND object_id = OBJECT_ID(N'dbo.Bookings'));

PRINT N'--- Nhóm D: IMP-05 công thức tính tiền ---';

DECLARE @P1 DECIMAL(12,0), @P3 DECIMAL(12,0);
SELECT @P1 = PricePerHour, @P3 = PricePerThreeHours FROM dbo.Courts WHERE CourtId = @court1;

INSERT #R SELECT 'RG-34', N'60 phút = giá 1 giờ',
    CASE WHEN dbo.fn_CalculateBookingCost(@court1, @t0800, @t0900) = @P1 THEN 1 ELSE 0 END,
    CONCAT(N'ra=', dbo.fn_CalculateBookingCost(@court1, @t0800, @t0900), N' / mong đợi=', @P1);

INSERT #R SELECT 'RG-35', N'90 phút = 1,5 × giá giờ',
    CASE WHEN dbo.fn_CalculateBookingCost(@court1, @t0800, @t0930) = ROUND(@P1 * 1.5, 0) THEN 1 ELSE 0 END,
    CONCAT(N'ra=', dbo.fn_CalculateBookingCost(@court1, @t0800, @t0930), N' / mong đợi=', ROUND(@P1 * 1.5, 0));

INSERT #R SELECT 'RG-36', N'120 phút = 2 × giá giờ',
    CASE WHEN dbo.fn_CalculateBookingCost(@court1, @t0800, @t1000) = @P1 * 2 THEN 1 ELSE 0 END,
    CONCAT(N'ra=', dbo.fn_CalculateBookingCost(@court1, @t0800, @t1000), N' / mong đợi=', @P1 * 2);

INSERT #R SELECT 'RG-37', N'150 phút = 2,5 × giá giờ',
    CASE WHEN dbo.fn_CalculateBookingCost(@court1, @t0800, @t1030) = ROUND(@P1 * 2.5, 0) THEN 1 ELSE 0 END,
    CONCAT(N'ra=', dbo.fn_CalculateBookingCost(@court1, @t0800, @t1030), N' / mong đợi=', ROUND(@P1 * 2.5, 0));

INSERT #R SELECT 'RG-38', N'180 phút = đúng giá combo 3 giờ',
    CASE WHEN dbo.fn_CalculateBookingCost(@court1, @t0800, @t1100) = @P3 THEN 1 ELSE 0 END,
    CONCAT(N'ra=', dbo.fn_CalculateBookingCost(@court1, @t0800, @t1100), N' / mong đợi=', @P3);

-- RG-39 nghịch lý giá: nếu P3 < 2,5×P1 thì đặt 2,5 giờ đắt hơn đặt 3 giờ
INSERT #R
SELECT 'RG-39', N'Không sân nào có nghịch lý giá (2,5 giờ đắt hơn 3 giờ)',
       CASE WHEN NOT EXISTS (SELECT 1 FROM dbo.Courts WHERE IsActive = 1 AND PricePerThreeHours < PricePerHour * 2.5)
            THEN 1 ELSE 0 END,
       (SELECT COUNT(*) FROM dbo.Courts WHERE IsActive = 1 AND PricePerThreeHours < PricePerHour * 2.5);

-- RG-40 chi phí không âm, không lẻ
INSERT #R SELECT 'RG-40', N'Chi phí >= 0 và là số nguyên đồng',
    CASE WHEN dbo.fn_CalculateBookingCost(@court1, @t0800, @t0930) >= 0
          AND dbo.fn_CalculateBookingCost(@court1, @t0800, @t0930) =
              FLOOR(dbo.fn_CalculateBookingCost(@court1, @t0800, @t0930)) THEN 1 ELSE 0 END, NULL;

PRINT N'--- Nhóm E: bất biến của contract và cấu hình khoá ---';

-- RG-41 IMP-04: sp_GetAvailableCourts không còn gọi lại fn_IsCourtAvailable cho cột IsAvailable
INSERT #R SELECT 'RG-41', N'IMP-04: sp_GetAvailableCourts trả CAST(1 AS BIT) AS IsAvailable',
    CASE WHEN OBJECT_DEFINITION(OBJECT_ID(N'dbo.sp_GetAvailableCourts')) LIKE N'%CAST(1 AS BIT) AS IsAvailable%'
         THEN 1 ELSE 0 END, NULL;

-- RG-42 KHÔNG được đặt SET LOCK_TIMEOUT trong bất kỳ SP nào (sẽ phá demo tranh khoá)
INSERT #R
SELECT 'RG-42', N'Không SP nào chứa SET LOCK_TIMEOUT (chỉ đặt ở tầng app)',
       CASE WHEN NOT EXISTS (SELECT 1 FROM sys.sql_modules WHERE definition LIKE N'%SET LOCK_TIMEOUT%')
            THEN 1 ELSE 0 END,
       (SELECT COUNT(*) FROM sys.sql_modules WHERE definition LIKE N'%SET LOCK_TIMEOUT%');

-- RG-43 số lượng đối tượng theo contract: 5 / 4 / 2 / 14 / 6
INSERT #R
SELECT 'RG-43', N'Đủ 5 bảng / 4 view / 2 function / 14 procedure / 6 trigger',
       CASE WHEN (SELECT COUNT(*) FROM sys.tables WHERE schema_id = SCHEMA_ID('dbo')) = 5
             AND (SELECT COUNT(*) FROM sys.views WHERE schema_id = SCHEMA_ID('dbo')) = 4
             AND (SELECT COUNT(*) FROM sys.objects WHERE type IN ('FN','IF','TF') AND schema_id = SCHEMA_ID('dbo')) = 2
             AND (SELECT COUNT(*) FROM sys.procedures WHERE schema_id = SCHEMA_ID('dbo')) = 14
             AND (SELECT COUNT(*) FROM sys.triggers WHERE parent_class = 1) = 6
            THEN 1 ELSE 0 END,
       CONCAT((SELECT COUNT(*) FROM sys.tables WHERE schema_id = SCHEMA_ID('dbo')), N'/',
              (SELECT COUNT(*) FROM sys.views WHERE schema_id = SCHEMA_ID('dbo')), N'/',
              (SELECT COUNT(*) FROM sys.objects WHERE type IN ('FN','IF','TF') AND schema_id = SCHEMA_ID('dbo')), N'/',
              (SELECT COUNT(*) FROM sys.procedures WHERE schema_id = SCHEMA_ID('dbo')), N'/',
              (SELECT COUNT(*) FROM sys.triggers WHERE parent_class = 1));

-- RG-44 dữ liệu seed không vi phạm IMP-09 (nếu vi phạm thì 03_indexes.sql đã không tạo được index)
INSERT #R
SELECT 'RG-44', N'Dữ liệu hiện tại không có 2 PENDING trùng (UserId, CourtId, StartTime)',
       CASE WHEN NOT EXISTS (
            SELECT 1 FROM dbo.Bookings WHERE Status = N'PENDING'
            GROUP BY UserId, CourtId, StartTime HAVING COUNT(*) > 1)
            THEN 1 ELSE 0 END, NULL;

PRINT N'--- Nhóm F: IMP-15 validation public SP + ownership view ---';

-- RG-45..RG-51: từng guard của sp_GetAvailableCourts phải có mã riêng, đúng thứ tự.
BEGIN TRY
    EXEC dbo.sp_GetAvailableCourts @StartTime = NULL, @EndTime = @t0900;
    INSERT #R VALUES ('RG-45', N'AvailableCourts chặn thời gian NULL', 0, N'Không throw');
END TRY
BEGIN CATCH
    INSERT #R VALUES ('RG-45', N'AvailableCourts chặn thời gian NULL',
        CASE WHEN ERROR_NUMBER() = 50120 THEN 1 ELSE 0 END, CONCAT(N'err=', ERROR_NUMBER()));
END CATCH;

BEGIN TRY
    EXEC dbo.sp_GetAvailableCourts @StartTime = @t0900, @EndTime = @t0900;
    INSERT #R VALUES ('RG-46', N'AvailableCourts chặn StartTime >= EndTime', 0, N'Không throw');
END TRY
BEGIN CATCH
    INSERT #R VALUES ('RG-46', N'AvailableCourts chặn StartTime >= EndTime',
        CASE WHEN ERROR_NUMBER() = 50121 THEN 1 ELSE 0 END, CONCAT(N'err=', ERROR_NUMBER()));
END CATCH;

BEGIN TRY
    EXEC dbo.sp_GetAvailableCourts @StartTime = @t0815, @EndTime = @t0930;
    INSERT #R VALUES ('RG-47', N'AvailableCourts chặn lệch bước 30 phút', 0, N'Không throw');
END TRY
BEGIN CATCH
    INSERT #R VALUES ('RG-47', N'AvailableCourts chặn lệch bước 30 phút',
        CASE WHEN ERROR_NUMBER() = 50122 THEN 1 ELSE 0 END, CONCAT(N'err=', ERROR_NUMBER()));
END CATCH;

BEGIN TRY
    EXEC dbo.sp_GetAvailableCourts @StartTime = @t2300, @EndTime = @tNext0030;
    INSERT #R VALUES ('RG-48', N'AvailableCourts chặn khung giờ qua ngày', 0, N'Không throw');
END TRY
BEGIN CATCH
    INSERT #R VALUES ('RG-48', N'AvailableCourts chặn khung giờ qua ngày',
        CASE WHEN ERROR_NUMBER() = 50123 THEN 1 ELSE 0 END, CONCAT(N'err=', ERROR_NUMBER()));
END CATCH;

BEGIN TRY
    EXEC dbo.sp_GetAvailableCourts @StartTime = @t0900, @EndTime = @t0930;
    INSERT #R VALUES ('RG-49', N'AvailableCourts chặn thời lượng ngoài 60-180 phút', 0, N'Không throw');
END TRY
BEGIN CATCH
    INSERT #R VALUES ('RG-49', N'AvailableCourts chặn thời lượng ngoài 60-180 phút',
        CASE WHEN ERROR_NUMBER() = 50124 THEN 1 ELSE 0 END, CONCAT(N'err=', ERROR_NUMBER()));
END CATCH;

BEGIN TRY
    EXEC dbo.sp_GetAvailableCourts @StartTime = @t0500, @EndTime = @t0600;
    INSERT #R VALUES ('RG-50', N'AvailableCourts chặn ngoài 06:00-22:00', 0, N'Không throw');
END TRY
BEGIN CATCH
    INSERT #R VALUES ('RG-50', N'AvailableCourts chặn ngoài 06:00-22:00',
        CASE WHEN ERROR_NUMBER() = 50125 THEN 1 ELSE 0 END, CONCAT(N'err=', ERROR_NUMBER()));
END CATCH;

DECLARE @pastStart DATETIME2(0) = DATEADD(DAY, -10, @t0900);
DECLARE @pastEnd   DATETIME2(0) = DATEADD(DAY, -10, @t1000);
BEGIN TRY
    EXEC dbo.sp_GetAvailableCourts @StartTime = @pastStart, @EndTime = @pastEnd;
    INSERT #R VALUES ('RG-51', N'AvailableCourts chặn thời gian quá khứ', 0, N'Không throw');
END TRY
BEGIN CATCH
    INSERT #R VALUES ('RG-51', N'AvailableCourts chặn thời gian quá khứ',
        CASE WHEN ERROR_NUMBER() = 50126 THEN 1 ELSE 0 END, CONCAT(N'err=', ERROR_NUMBER()));
END CATCH;

DECLARE @available TABLE
(
    CourtId UNIQUEIDENTIFIER,
    CourtName NVARCHAR(100),
    Address NVARCHAR(255),
    SurfaceType NVARCHAR(20),
    SizeType NVARCHAR(20),
    PricePerHour DECIMAL(12,0),
    PricePerThreeHours DECIMAL(12,0),
    IsAvailable BIT
);

BEGIN TRY
    INSERT @available
    EXEC dbo.sp_GetAvailableCourts @StartTime = @t0900, @EndTime = @t1030;
    INSERT #R VALUES ('RG-52', N'AvailableCourts happy path 09:00-10:30 vẫn trả danh sách',
        CASE WHEN EXISTS (SELECT 1 FROM @available) THEN 1 ELSE 0 END,
        CONCAT(N'rows=', (SELECT COUNT(*) FROM @available)));
END TRY
BEGIN CATCH
    INSERT #R VALUES ('RG-52', N'AvailableCourts happy path 09:00-10:30 vẫn trả danh sách',
        0, CONCAT(N'err=', ERROR_NUMBER(), N': ', ERROR_MESSAGE()));
END CATCH;

DELETE FROM @available;
BEGIN TRY
    INSERT @available
    EXEC dbo.sp_GetAvailableCourts @StartTime = @t0900, @EndTime = @t1030, @CourtId = @ghost;
    INSERT #R VALUES ('RG-53', N'AvailableCourts courtId không tồn tại trả danh sách rỗng',
        CASE WHEN NOT EXISTS (SELECT 1 FROM @available) THEN 1 ELSE 0 END,
        CONCAT(N'rows=', (SELECT COUNT(*) FROM @available)));
END TRY
BEGIN CATCH
    INSERT #R VALUES ('RG-53', N'AvailableCourts courtId không tồn tại trả danh sách rỗng',
        0, CONCAT(N'err=', ERROR_NUMBER(), N': ', ERROR_MESSAGE()));
END CATCH;

-- Xóa context trước khi giả lập caller giữ chuỗi kết nối bcm_app.
EXEC sys.sp_set_session_context @key = N'UserId', @value = NULL;
EXEC sys.sp_set_session_context @key = N'Role', @value = NULL;

DECLARE @rg54Count INT = -1, @rg54Error INT = NULL;
BEGIN TRY
    EXECUTE AS USER = N'bcm_app';
    SELECT @rg54Count = COUNT(*) FROM dbo.vw_AllBookings;
    REVERT;
END TRY
BEGIN CATCH
    SET @rg54Error = ERROR_NUMBER();
    IF USER_NAME() = N'bcm_app' REVERT;
END CATCH;
INSERT #R VALUES ('RG-54', N'bcm_app không context đọc vw_AllBookings nhận 0 dòng',
    CASE WHEN @rg54Error IS NULL AND @rg54Count = 0 THEN 1 ELSE 0 END,
    CONCAT(N'rows=', @rg54Count, N'; err=', COALESCE(CONVERT(NVARCHAR(20), @rg54Error), N'none')));

DECLARE @rg55Base INT = (SELECT COUNT(*) FROM dbo.Bookings);
DECLARE @rg55View INT = (SELECT COUNT(*) FROM dbo.vw_AllBookings);
INSERT #R VALUES ('RG-55', N'Sysadmin vẫn đọc đủ vw_AllBookings cho test/backup',
    CASE WHEN IS_SRVROLEMEMBER(N'sysadmin') = 1 AND @rg55View = @rg55Base THEN 1 ELSE 0 END,
    CONCAT(N'view=', @rg55View, N'; base=', @rg55Base,
           N'; sysadmin=', COALESCE(CONVERT(NVARCHAR(10), IS_SRVROLEMEMBER(N'sysadmin')), N'NULL')));
GO

-- ============================================================
-- TỔNG KẾT
-- ============================================================
PRINT N'';
PRINT N'================ KẾT QUẢ imp_regression ================';
SELECT id, name, CASE WHEN [pass] = 1 THEN 'PASS' ELSE 'FAIL' END AS result, note
FROM #R ORDER BY id;

DECLARE @total INT = (SELECT COUNT(*) FROM #R);
DECLARE @failed INT = (SELECT COUNT(*) FROM #R WHERE [pass] = 0);
PRINT CONCAT(N'TỔNG: ', @total, N' | PASS: ', @total - @failed, N' | FAIL: ', @failed);
IF @failed > 0
BEGIN
    PRINT N'CÓ TEST FAIL — xem cột note ở trên.';
    RAISERROR(N'imp_regression: có test FAIL.', 16, 1);
END
ELSE
    PRINT N'TẤT CẢ PASS.';
GO
