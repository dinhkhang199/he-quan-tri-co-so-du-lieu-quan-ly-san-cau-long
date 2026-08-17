/* ============================================================
   BadmintonCourtManagement
   Script : 06_procedures.sql
   Mục đích: 14 Stored Procedures theo contract v2.0 (section 6.3, 7)
   Nguyên tắc: mọi SP nghiệp vụ có validation quyền + state + input
               + transaction (SET XACT_ABORT ON + BEGIN TRAN/COMMIT/ROLLBACK + THROW)
               + WITH EXECUTE AS OWNER để app user (bị DENY DML trực tiếp)
                 chỉ có thể đổi dữ liệu qua SP.
   ============================================================ */

USE BadmintonCourtManagement;
GO

-- ============================================================
-- 1. sp_Login: xác thực, chặn inactive, cập nhật LastLogin
-- ============================================================
IF OBJECT_ID(N'dbo.sp_Login', N'P') IS NOT NULL DROP PROCEDURE dbo.sp_Login;
GO
CREATE PROCEDURE dbo.sp_Login
    @Username NVARCHAR(50),
    @Password NVARCHAR(200)
WITH EXECUTE AS OWNER
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Hash    VARBINARY(64) = CONVERT(VARBINARY(64), HASHBYTES('SHA2_256', N'bcms|' + @Password));
    DECLARE @UserId  UNIQUEIDENTIFIER;
    DECLARE @Role    NVARCHAR(20);
    DECLARE @IsActive BIT;

    SELECT @UserId = UserId, @Role = Role, @IsActive = IsActive
    FROM dbo.Users
    WHERE Username = @Username AND PasswordHash = @Hash;

    IF @UserId IS NULL
        THROW 50001, N'Đăng nhập thất bại: sai tên đăng nhập hoặc mật khẩu.', 1;

    IF @IsActive = 0
        THROW 50002, N'Đăng nhập thất bại: tài khoản đã bị vô hiệu hóa (inactive).', 1;

    UPDATE dbo.Users SET LastLogin = SYSDATETIME() WHERE UserId = @UserId;

    SELECT UserId, Username, Role, IsActive, LastLogin
    FROM dbo.Users
    WHERE UserId = @UserId;
END
GO

-- ============================================================
-- 2. sp_BookCourt: validate + transaction + lock + tạo đúng 1 PENDING
-- ============================================================
IF OBJECT_ID(N'dbo.sp_BookCourt', N'P') IS NOT NULL DROP PROCEDURE dbo.sp_BookCourt;
GO
CREATE PROCEDURE dbo.sp_BookCourt
    @UserId    UNIQUEIDENTIFIER,
    @CourtId   UNIQUEIDENTIFIER,
    @StartTime DATETIME2(0),
    @EndTime   DATETIME2(0),
    @BookingId UNIQUEIDENTIFIER = NULL OUTPUT,
    @TotalCost DECIMAL(12,0) = NULL OUTPUT
WITH EXECUTE AS OWNER
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Role NVARCHAR(20);
    SELECT @Role = Role FROM dbo.Users WHERE UserId = @UserId AND IsActive = 1;
    IF @Role IS NULL
        THROW 50010, N'Người dùng không tồn tại hoặc đang inactive.', 1;
    IF @Role <> N'CUSTOMER'
        THROW 50011, N'Chỉ CUSTOMER mới được tạo booking.', 1;

    DECLARE @PricePerHour DECIMAL(12,0), @PricePerThreeHours DECIMAL(12,0), @CourtIsActive BIT;
    SELECT @PricePerHour = PricePerHour, @PricePerThreeHours = PricePerThreeHours, @CourtIsActive = IsActive
    FROM dbo.Courts WHERE CourtId = @CourtId;

    IF @CourtIsActive IS NULL
        THROW 50012, N'Sân không tồn tại.', 1;
    IF @CourtIsActive = 0
        THROW 50013, N'Sân đang ngừng hoạt động (inactive), không thể đặt.', 1;

    -- ---- Validate thời gian ----
    IF @StartTime IS NULL OR @EndTime IS NULL
        THROW 50014, N'Bạn phải nhập đầy đủ thời gian bắt đầu và kết thúc.', 1;
    IF @StartTime >= @EndTime
        THROW 50015, N'Thời gian kết thúc phải lớn hơn thời gian bắt đầu.', 1;
    IF @StartTime <= SYSDATETIME()
        THROW 50016, N'Không cho phép đặt sân trong quá khứ.', 1;

    DECLARE @Minutes INT = DATEDIFF(MINUTE, @StartTime, @EndTime);
    IF @Minutes < 60
        THROW 50017, N'Thời lượng tối thiểu là 1 giờ.', 1;
    IF @Minutes > 180
        THROW 50018, N'Thời lượng tối đa là 3 giờ.', 1;

    -- Độ phân giải 30 phút: phút phải là 00 hoặc 30, giây/ms = 0
    IF DATEPART(MINUTE, @StartTime) % 30 <> 0 OR DATEPART(MINUTE, @EndTime) % 30 <> 0
        OR DATEPART(SECOND, @StartTime) <> 0 OR DATEPART(SECOND, @EndTime) <> 0
        OR DATEPART(MILLISECOND, @StartTime) <> 0 OR DATEPART(MILLISECOND, @EndTime) <> 0
        THROW 50019, N'Thời gian phải theo bước 30 phút (00 hoặc 30, không có giây/mili-giây).', 1;

    -- Trong khung hoạt động 06:00-22:00 mỗi ngày
    IF CONVERT(TIME(0), @StartTime) < CONVERT(TIME(0), '06:00') OR CONVERT(TIME(0), @EndTime) > CONVERT(TIME(0), '22:00')
        THROW 50020, N'Booking phải nằm trong khung hoạt động 06:00–22:00.', 1;

    IF @BookingId IS NULL
        SET @BookingId = NEWID();

    BEGIN TRY
        BEGIN TRAN;
            -- Khóa hàng Court để serialize theo từng sân (ngăn 2 booking chạy cùng lúc)
            SELECT CourtId FROM dbo.Courts WITH (UPDLOCK, ROWLOCK, HOLDLOCK) WHERE CourtId = @CourtId;

            -- Overlap chỉ tính với BOOKED (nhiều PENDING trên cùng khung là hợp lệ)
            IF EXISTS
            (
                SELECT 1 FROM dbo.Bookings
                WHERE CourtId = @CourtId
                  AND Status  = N'BOOKED'
                  AND StartTime < @EndTime
                  AND EndTime   > @StartTime
            )
                THROW 50021, N'Sân đã được đặt (BOOKED) trong khung giờ này.', 1;

            SET @TotalCost = dbo.fn_CalculateBookingCost(@CourtId, @StartTime, @EndTime);

            INSERT INTO dbo.Bookings (BookingId, UserId, CourtId, StartTime, EndTime, Status, TotalCost)
            VALUES (@BookingId, @UserId, @CourtId, @StartTime, @EndTime, N'PENDING', @TotalCost);
        COMMIT;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK;
        THROW;
    END CATCH;
END
GO

-- ============================================================
-- 3. sp_ApproveBooking: PENDING->BOOKED, re-check overlap trong tran có khóa
-- ============================================================
IF OBJECT_ID(N'dbo.sp_ApproveBooking', N'P') IS NOT NULL DROP PROCEDURE dbo.sp_ApproveBooking;
GO
CREATE PROCEDURE dbo.sp_ApproveBooking
    @SessionUserId UNIQUEIDENTIFIER,
    @BookingId     UNIQUEIDENTIFIER
WITH EXECUTE AS OWNER
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Role NVARCHAR(20);
    SELECT @Role = Role FROM dbo.Users WHERE UserId = @SessionUserId AND IsActive = 1;
    IF @Role IS NULL
        THROW 50030, N'Người dùng không tồn tại hoặc đang inactive.', 1;
    IF @Role NOT IN (N'MANAGER', N'COURT_MANAGER')
        THROW 50031, N'Không đủ quyền duyệt booking.', 1;

    DECLARE @CourtId UNIQUEIDENTIFIER, @CourtOwner UNIQUEIDENTIFIER;
    DECLARE @Status NVARCHAR(20), @StartT DATETIME2(0), @EndT DATETIME2(0);

    SELECT @CourtId = b.CourtId, @Status = b.Status, @StartT = b.StartTime, @EndT = b.EndTime,
           @CourtOwner = c.OwnerId
    FROM dbo.Bookings b
    INNER JOIN dbo.Courts c ON c.CourtId = b.CourtId
    WHERE b.BookingId = @BookingId;

    IF @CourtId IS NULL
        THROW 50032, N'Booking không tồn tại.', 1;

    IF @Role = N'COURT_MANAGER' AND @CourtOwner <> @SessionUserId
        THROW 50033, N'Court Manager chỉ được duyệt booking thuộc sân của mình.', 1;

    BEGIN TRY
        BEGIN TRAN;
            -- Khóa sân là điểm tuần tự hóa approve (CC-01: 2 session approve -> chỉ 1 BOOKED)
            SELECT CourtId FROM dbo.Courts WITH (UPDLOCK, ROWLOCK, HOLDLOCK) WHERE CourtId = @CourtId;

            -- Đọc lại booking dưới khóa để tránh lost update
            SELECT @Status = Status, @StartT = StartTime, @EndT = EndTime
            FROM dbo.Bookings WITH (UPDLOCK)
            WHERE BookingId = @BookingId;

            IF @Status <> N'PENDING'
                THROW 50034, N'Chỉ duyệt được booking ở trạng thái PENDING.', 1;

            -- Re-check overlap với BOOKED khác (loại trừ chính booking này)
            IF EXISTS
            (
                SELECT 1 FROM dbo.Bookings
                WHERE CourtId = @CourtId
                  AND Status  = N'BOOKED'
                  AND StartTime < @EndT
                  AND EndTime   > @StartT
                  AND BookingId <> @BookingId
            )
                THROW 50035, N'Không thể approve: booking overlap với một BOOKED khác trên cùng sân.', 1;

            UPDATE dbo.Bookings SET Status = N'BOOKED', UpdatedAt = SYSDATETIME() WHERE BookingId = @BookingId;
            IF @@ROWCOUNT <> 1
                THROW 50034, N'Chỉ duyệt được booking ở trạng thái PENDING.', 1;
        COMMIT;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK;
        THROW;
    END CATCH;
END
GO

-- ============================================================
-- 4. sp_RejectBooking: PENDING->REJECTED theo quyền
-- ============================================================
IF OBJECT_ID(N'dbo.sp_RejectBooking', N'P') IS NOT NULL DROP PROCEDURE dbo.sp_RejectBooking;
GO
CREATE PROCEDURE dbo.sp_RejectBooking
    @SessionUserId UNIQUEIDENTIFIER,
    @BookingId     UNIQUEIDENTIFIER
WITH EXECUTE AS OWNER
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Role NVARCHAR(20);
    SELECT @Role = Role FROM dbo.Users WHERE UserId = @SessionUserId AND IsActive = 1;
    IF @Role NOT IN (N'MANAGER', N'COURT_MANAGER')
        THROW 50040, N'Không đủ quyền từ chối booking.', 1;

    DECLARE @CourtId UNIQUEIDENTIFIER, @CourtOwner UNIQUEIDENTIFIER, @Status NVARCHAR(20);
    SELECT @CourtId = b.CourtId, @Status = b.Status, @CourtOwner = c.OwnerId
    FROM dbo.Bookings b INNER JOIN dbo.Courts c ON c.CourtId = b.CourtId
    WHERE b.BookingId = @BookingId;

    IF @CourtId IS NULL THROW 50041, N'Booking không tồn tại.', 1;
    IF @Role = N'COURT_MANAGER' AND @CourtOwner <> @SessionUserId
        THROW 50042, N'Court Manager chỉ thao tác booking thuộc sân của mình.', 1;
    IF @Status <> N'PENDING'
        THROW 50043, N'Chỉ từ chối được booking ở trạng thái PENDING.', 1;

    BEGIN TRY
        BEGIN TRAN;
            SELECT CourtId FROM dbo.Courts WITH (UPDLOCK, ROWLOCK, HOLDLOCK) WHERE CourtId = @CourtId;

            UPDATE dbo.Bookings SET Status = N'REJECTED', UpdatedAt = SYSDATETIME() WHERE BookingId = @BookingId;
            IF @@ROWCOUNT <> 1 THROW 50043, N'Chỉ từ chối được booking ở trạng thái PENDING.', 1;
        COMMIT;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK;
        THROW;
    END CATCH;
END
GO

-- ============================================================
-- 5. sp_CancelBooking: hủy theo quyền + state + luật 3 giờ (contract 3.5)
-- ============================================================
IF OBJECT_ID(N'dbo.sp_CancelBooking', N'P') IS NOT NULL DROP PROCEDURE dbo.sp_CancelBooking;
GO
CREATE PROCEDURE dbo.sp_CancelBooking
    @SessionUserId UNIQUEIDENTIFIER,
    @BookingId     UNIQUEIDENTIFIER
WITH EXECUTE AS OWNER
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Role NVARCHAR(20);
    SELECT @Role = Role FROM dbo.Users WHERE UserId = @SessionUserId AND IsActive = 1;
    IF @Role IS NULL THROW 50050, N'Người dùng không tồn tại hoặc đang inactive.', 1;

    DECLARE @BookingUserId UNIQUEIDENTIFIER, @CourtOwner UNIQUEIDENTIFIER;
    DECLARE @Status NVARCHAR(20), @StartT DATETIME2(0);

    SELECT @BookingUserId = b.UserId, @Status = b.Status, @StartT = b.StartTime, @CourtOwner = c.OwnerId
    FROM dbo.Bookings b INNER JOIN dbo.Courts c ON c.CourtId = b.CourtId
    WHERE b.BookingId = @BookingId;

    IF @BookingUserId IS NULL THROW 50051, N'Booking không tồn tại.', 1;
    IF @Status IN (N'COMPLETED', N'REJECTED')
        THROW 50052, N'Không thể hủy booking đã COMPLETED hoặc REJECTED.', 1;
    IF @Status = N'CANCELLED'
        THROW 50053, N'Booking này đã bị hủy trước đó.', 1;

    IF @Role = N'CUSTOMER'
    BEGIN
        IF @BookingUserId <> @SessionUserId
            THROW 50054, N'Customer chỉ được hủy booking của chính mình.', 1;
        IF @Status = N'BOOKED' AND @StartT < DATEADD(HOUR, 3, SYSDATETIME())
            THROW 50055, N'BOOKED chỉ được Customer tự hủy khi còn tối thiểu 3 giờ trước giờ bắt đầu.', 1;
    END
    ELSE IF @Role = N'COURT_MANAGER'
    BEGIN
        IF @CourtOwner <> @SessionUserId
            THROW 50056, N'Court Manager chỉ hủy booking thuộc sân của mình.', 1;
    END
    ELSE IF @Role <> N'MANAGER'
        THROW 50057, N'Không đủ quyền hủy booking.', 1;

    BEGIN TRY
        BEGIN TRAN;
            UPDATE dbo.Bookings SET Status = N'CANCELLED', UpdatedAt = SYSDATETIME() WHERE BookingId = @BookingId;
            IF @@ROWCOUNT <> 1 THROW 50058, N'Hủy booking thất bại.', 1;
        COMMIT;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK;
        THROW;
    END CATCH;
END
GO

-- ============================================================
-- 6. sp_CompleteBooking: BOOKED->COMPLETED theo quyền
-- ============================================================
IF OBJECT_ID(N'dbo.sp_CompleteBooking', N'P') IS NOT NULL DROP PROCEDURE dbo.sp_CompleteBooking;
GO
CREATE PROCEDURE dbo.sp_CompleteBooking
    @SessionUserId UNIQUEIDENTIFIER,
    @BookingId     UNIQUEIDENTIFIER
WITH EXECUTE AS OWNER
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Role NVARCHAR(20);
    SELECT @Role = Role FROM dbo.Users WHERE UserId = @SessionUserId AND IsActive = 1;
    IF @Role NOT IN (N'MANAGER', N'COURT_MANAGER')
        THROW 50060, N'Không đủ quyền hoàn thành booking.', 1;

    DECLARE @CourtId UNIQUEIDENTIFIER, @CourtOwner UNIQUEIDENTIFIER, @Status NVARCHAR(20);
    SELECT @CourtId = b.CourtId, @Status = b.Status, @CourtOwner = c.OwnerId
    FROM dbo.Bookings b INNER JOIN dbo.Courts c ON c.CourtId = b.CourtId
    WHERE b.BookingId = @BookingId;

    IF @CourtId IS NULL THROW 50061, N'Booking không tồn tại.', 1;
    IF @Status <> N'BOOKED'
        THROW 50062, N'Chỉ hoàn thành được booking ở trạng thái BOOKED.', 1;
    IF @Role = N'COURT_MANAGER' AND @CourtOwner <> @SessionUserId
        THROW 50063, N'Court Manager chỉ thao tác booking thuộc sân của mình.', 1;

    BEGIN TRY
        BEGIN TRAN;
            UPDATE dbo.Bookings SET Status = N'COMPLETED', UpdatedAt = SYSDATETIME() WHERE BookingId = @BookingId;
            IF @@ROWCOUNT <> 1 THROW 50064, N'Hoàn thành booking thất bại.', 1;
        COMMIT;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK;
        THROW;
    END CATCH;
END
GO

-- ============================================================
-- 7. sp_CreateCourt: tạo sân hợp lệ
-- ============================================================
IF OBJECT_ID(N'dbo.sp_CreateCourt', N'P') IS NOT NULL DROP PROCEDURE dbo.sp_CreateCourt;
GO
CREATE PROCEDURE dbo.sp_CreateCourt
    @SessionUserId       UNIQUEIDENTIFIER,
    @CourtName           NVARCHAR(100),
    @Address             NVARCHAR(255),
    @SurfaceType         NVARCHAR(20),
    @SizeType            NVARCHAR(20),
    @PricePerHour        DECIMAL(12,0),
    @PricePerThreeHours  DECIMAL(12,0),
    @ImageUrl            NVARCHAR(500) = NULL,
    @OwnerId             UNIQUEIDENTIFIER = NULL,
    @CourtId             UNIQUEIDENTIFIER = NULL OUTPUT
WITH EXECUTE AS OWNER
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Role NVARCHAR(20);
    SELECT @Role = Role FROM dbo.Users WHERE UserId = @SessionUserId AND IsActive = 1;
    IF @Role NOT IN (N'MANAGER', N'COURT_MANAGER')
        THROW 50070, N'Không đủ quyền tạo sân.', 1;

    IF @OwnerId IS NULL
        SET @OwnerId = @SessionUserId;

    -- Court Manager chỉ tạo sân cho chính mình
    IF @Role = N'COURT_MANAGER' AND @OwnerId <> @SessionUserId
        THROW 50071, N'Court Manager chỉ được tạo sân thuộc quyền mình.', 1;

    IF @PricePerHour <= 0 OR @PricePerThreeHours <= 0
        THROW 50072, N'Giá sân phải lớn hơn 0.', 1;

    IF @CourtId IS NULL SET @CourtId = NEWID();

    INSERT INTO dbo.Courts (CourtId, CourtName, Address, SurfaceType, SizeType, PricePerHour, PricePerThreeHours, ImageUrl, OwnerId)
    VALUES (@CourtId, @CourtName, @Address, @SurfaceType, @SizeType, @PricePerHour, @PricePerThreeHours, @ImageUrl, @OwnerId);

    SELECT @CourtId AS CourtId;
END
GO

-- ============================================================
-- 8. sp_UpdateCourt: sửa sân theo quyền + ownership
-- ============================================================
IF OBJECT_ID(N'dbo.sp_UpdateCourt', N'P') IS NOT NULL DROP PROCEDURE dbo.sp_UpdateCourt;
GO
CREATE PROCEDURE dbo.sp_UpdateCourt
    @SessionUserId       UNIQUEIDENTIFIER,
    @CourtId             UNIQUEIDENTIFIER,
    @CourtName           NVARCHAR(100),
    @Address             NVARCHAR(255),
    @SurfaceType         NVARCHAR(20),
    @SizeType            NVARCHAR(20),
    @PricePerHour        DECIMAL(12,0),
    @PricePerThreeHours  DECIMAL(12,0),
    @ImageUrl            NVARCHAR(500) = NULL
WITH EXECUTE AS OWNER
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Role NVARCHAR(20);
    SELECT @Role = Role FROM dbo.Users WHERE UserId = @SessionUserId AND IsActive = 1;
    IF @Role NOT IN (N'MANAGER', N'COURT_MANAGER')
        THROW 50080, N'Không đủ quyền sửa sân.', 1;

    DECLARE @OwnerId UNIQUEIDENTIFIER;
    SELECT @OwnerId = OwnerId FROM dbo.Courts WHERE CourtId = @CourtId;
    IF @OwnerId IS NULL THROW 50081, N'Sân không tồn tại.', 1;
    IF @Role = N'COURT_MANAGER' AND @OwnerId <> @SessionUserId
        THROW 50082, N'Court Manager chỉ được sửa sân thuộc quyền mình.', 1;

    IF @PricePerHour <= 0 OR @PricePerThreeHours <= 0
        THROW 50083, N'Giá sân phải lớn hơn 0.', 1;

    UPDATE dbo.Courts
    SET CourtName = @CourtName, Address = @Address, SurfaceType = @SurfaceType,
        SizeType = @SizeType, PricePerHour = @PricePerHour, PricePerThreeHours = @PricePerThreeHours,
        ImageUrl = @ImageUrl, UpdatedAt = SYSDATETIME()
    WHERE CourtId = @CourtId;
END
GO

-- ============================================================
-- 9. sp_DeactivateCourt: soft-delete IsActive=0 (không hard-delete sân có lịch sử)
-- ============================================================
IF OBJECT_ID(N'dbo.sp_DeactivateCourt', N'P') IS NOT NULL DROP PROCEDURE dbo.sp_DeactivateCourt;
GO
CREATE PROCEDURE dbo.sp_DeactivateCourt
    @SessionUserId UNIQUEIDENTIFIER,
    @CourtId       UNIQUEIDENTIFIER
WITH EXECUTE AS OWNER
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Role NVARCHAR(20);
    SELECT @Role = Role FROM dbo.Users WHERE UserId = @SessionUserId AND IsActive = 1;
    IF @Role NOT IN (N'MANAGER', N'COURT_MANAGER')
        THROW 50090, N'Không đủ quyền ngừng hoạt động sân.', 1;

    DECLARE @OwnerId UNIQUEIDENTIFIER;
    SELECT @OwnerId = OwnerId FROM dbo.Courts WHERE CourtId = @CourtId;
    IF @OwnerId IS NULL THROW 50091, N'Sân không tồn tại.', 1;
    IF @Role = N'COURT_MANAGER' AND @OwnerId <> @SessionUserId
        THROW 50092, N'Court Manager chỉ thao tác sân thuộc quyền mình.', 1;

    UPDATE dbo.Courts SET IsActive = 0, UpdatedAt = SYSDATETIME() WHERE CourtId = @CourtId;
END
GO

-- ============================================================
-- 10. sp_GetAvailableCourts: tìm sân phù hợp theo khoảng thời gian
-- ============================================================
IF OBJECT_ID(N'dbo.sp_GetAvailableCourts', N'P') IS NOT NULL DROP PROCEDURE dbo.sp_GetAvailableCourts;
GO
CREATE PROCEDURE dbo.sp_GetAvailableCourts
    @StartTime DATETIME2(0),
    @EndTime   DATETIME2(0),
    @CourtId   UNIQUEIDENTIFIER = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SELECT
        c.CourtId,
        c.CourtName,
        c.Address,
        c.SurfaceType,
        c.SizeType,
        c.PricePerHour,
        c.PricePerThreeHours,
        dbo.fn_IsCourtAvailable(c.CourtId, @StartTime, @EndTime) AS IsAvailable
    FROM dbo.Courts c
    WHERE c.IsActive = 1
      AND (@CourtId IS NULL OR c.CourtId = @CourtId)
      AND dbo.fn_IsCourtAvailable(c.CourtId, @StartTime, @EndTime) = 1
    ORDER BY c.CourtName;
END
GO

-- ============================================================
-- 11. sp_GetMyBookings: lịch sử booking của Customer hiện tại
-- ============================================================
IF OBJECT_ID(N'dbo.sp_GetMyBookings', N'P') IS NOT NULL DROP PROCEDURE dbo.sp_GetMyBookings;
GO
CREATE PROCEDURE dbo.sp_GetMyBookings
    @UserId UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SELECT BookingId, CourtId, CourtName, CourtAddress, StartTime, EndTime, Status, TotalCost, CreatedAt
    FROM dbo.vw_BookingHistory
    WHERE UserId = @UserId
    ORDER BY StartTime DESC;
END
GO

-- ============================================================
-- 12. sp_GetNotifications: lấy notification theo User
-- ============================================================
IF OBJECT_ID(N'dbo.sp_GetNotifications', N'P') IS NOT NULL DROP PROCEDURE dbo.sp_GetNotifications;
GO
CREATE PROCEDURE dbo.sp_GetNotifications
    @UserId     UNIQUEIDENTIFIER,
    @UnreadOnly BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SELECT NotificationId, UserId, BookingId, Message, IsRead, CreatedAt
    FROM dbo.Notifications
    WHERE UserId = @UserId
      AND (@UnreadOnly = 0 OR IsRead = 0)
    ORDER BY CreatedAt DESC;
END
GO

-- ============================================================
-- 13. sp_MarkNotificationRead: đánh dấu notification đã đọc
-- ============================================================
IF OBJECT_ID(N'dbo.sp_MarkNotificationRead', N'P') IS NOT NULL DROP PROCEDURE dbo.sp_MarkNotificationRead;
GO
CREATE PROCEDURE dbo.sp_MarkNotificationRead
    @SessionUserId  UNIQUEIDENTIFIER,
    @NotificationId UNIQUEIDENTIFIER
WITH EXECUTE AS OWNER
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    UPDATE dbo.Notifications
    SET IsRead = 1
    WHERE NotificationId = @NotificationId AND UserId = @SessionUserId;

    IF @@ROWCOUNT = 0
        THROW 50100, N'Không tìm thấy notification của người dùng này.', 1;
END
GO

-- ============================================================
-- 14. sp_GetDashboard: số liệu dashboard/thống kê (theo quyền)
--     Trả về 3 result-set: overview, doanh thu 7 ngày, top sân
-- ============================================================
IF OBJECT_ID(N'dbo.sp_GetDashboard', N'P') IS NOT NULL DROP PROCEDURE dbo.sp_GetDashboard;
GO
CREATE PROCEDURE dbo.sp_GetDashboard
    @SessionUserId UNIQUEIDENTIFIER
WITH EXECUTE AS OWNER
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Role NVARCHAR(20);
    SELECT @Role = Role FROM dbo.Users WHERE UserId = @SessionUserId AND IsActive = 1;
    IF @Role NOT IN (N'MANAGER', N'COURT_MANAGER')
        THROW 50110, N'Chỉ MANAGER/COURT_MANAGER được xem dashboard.', 1;

    -- ---- Overview ----
    IF @Role = N'MANAGER'
    BEGIN
        SELECT
            (SELECT COUNT(*) FROM dbo.Bookings WHERE Status = N'PENDING') AS PendingCount,
            (SELECT COUNT(*) FROM dbo.Bookings WHERE Status = N'BOOKED')  AS BookedCount,
            (SELECT ISNULL(SUM(TotalCost),0) FROM dbo.Bookings WHERE Status IN (N'BOOKED', N'COMPLETED')) AS TheoreticalRevenue,
            (SELECT COUNT(*) FROM dbo.Users WHERE IsActive = 1) AS ActiveUsers;

        SELECT CAST(StartTime AS DATE) AS Date, SUM(TotalCost) AS DailyRevenue
        FROM dbo.Bookings
        WHERE Status IN (N'BOOKED', N'COMPLETED')
          AND StartTime >= DATEADD(DAY, -6, CAST(SYSDATETIME() AS DATE))
        GROUP BY CAST(StartTime AS DATE)
        ORDER BY Date;

        SELECT TOP 5 c.CourtName, COUNT(*) AS BookingCount, ISNULL(SUM(b.TotalCost),0) AS Revenue
        FROM dbo.Bookings b INNER JOIN dbo.Courts c ON c.CourtId = b.CourtId
        WHERE b.Status IN (N'BOOKED', N'COMPLETED')
        GROUP BY c.CourtId, c.CourtName
        ORDER BY Revenue DESC;
    END
    ELSE -- COURT_MANAGER: chỉ thống kê sân mình
    BEGIN
        SELECT
            (SELECT COUNT(*) FROM dbo.Bookings b INNER JOIN dbo.Courts c ON c.CourtId = b.CourtId WHERE c.OwnerId = @SessionUserId AND b.Status = N'PENDING') AS PendingCount,
            (SELECT COUNT(*) FROM dbo.Bookings b INNER JOIN dbo.Courts c ON c.CourtId = b.CourtId WHERE c.OwnerId = @SessionUserId AND b.Status = N'BOOKED')  AS BookedCount,
            (SELECT ISNULL(SUM(b.TotalCost),0) FROM dbo.Bookings b INNER JOIN dbo.Courts c ON c.CourtId = b.CourtId WHERE c.OwnerId = @SessionUserId AND b.Status IN (N'BOOKED', N'COMPLETED')) AS TheoreticalRevenue,
            (SELECT COUNT(*) FROM dbo.Users WHERE IsActive = 1) AS ActiveUsers;

        SELECT CAST(b.StartTime AS DATE) AS Date, SUM(b.TotalCost) AS DailyRevenue
        FROM dbo.Bookings b INNER JOIN dbo.Courts c ON c.CourtId = b.CourtId
        WHERE c.OwnerId = @SessionUserId AND b.Status IN (N'BOOKED', N'COMPLETED')
          AND b.StartTime >= DATEADD(DAY, -6, CAST(SYSDATETIME() AS DATE))
        GROUP BY CAST(b.StartTime AS DATE)
        ORDER BY Date;

        SELECT TOP 5 c.CourtName, COUNT(*) AS BookingCount, ISNULL(SUM(b.TotalCost),0) AS Revenue
        FROM dbo.Bookings b INNER JOIN dbo.Courts c ON c.CourtId = b.CourtId
        WHERE c.OwnerId = @SessionUserId AND b.Status IN (N'BOOKED', N'COMPLETED')
        GROUP BY c.CourtId, c.CourtName
        ORDER BY Revenue DESC;
    END
END
GO

PRINT N'[OK] 14 Stored Procedures đã được tạo.';