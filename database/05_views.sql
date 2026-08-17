/* ============================================================
   BadmintonCourtManagement
   Script : 05_views.sql
   Mục đích: 4 Views theo contract v2.0 (section 6.1)
   ============================================================ */

USE BadmintonCourtManagement;
GO

-- ------------------------------------------------------------
-- 1. vw_AvailableCourts
--    Danh sách sân active + giá/trạng thái.
--    Availability theo khung giờ cụ thể phải qua sp_GetAvailableCourts.
-- ------------------------------------------------------------
IF OBJECT_ID(N'dbo.vw_AvailableCourts', N'V') IS NOT NULL
    DROP VIEW dbo.vw_AvailableCourts;
GO

CREATE VIEW dbo.vw_AvailableCourts
AS
SELECT
    c.CourtId,
    c.CourtName,
    c.Address,
    c.SurfaceType,
    c.SizeType,
    c.PricePerHour,
    c.PricePerThreeHours,
    c.ImageUrl,
    c.IsActive,
    c.OwnerId,
    u.Username AS OwnerUsername
FROM dbo.Courts c
INNER JOIN dbo.Users u ON u.UserId = c.OwnerId
WHERE c.IsActive = 1;
GO

-- ------------------------------------------------------------
-- 2. vw_BookingHistory
--    Lịch sử booking + chi phí + thông tin sân/khách.
-- ------------------------------------------------------------
IF OBJECT_ID(N'dbo.vw_BookingHistory', N'V') IS NOT NULL
    DROP VIEW dbo.vw_BookingHistory;
GO

CREATE VIEW dbo.vw_BookingHistory
AS
SELECT
    b.BookingId,
    b.UserId,
    u.Username        AS CustomerUsername,
    b.CourtId,
    c.CourtName,
    c.Address         AS CourtAddress,
    b.StartTime,
    b.EndTime,
    b.Status,
    b.TotalCost,
    b.CreatedAt,
    b.UpdatedAt
FROM dbo.Bookings b
INNER JOIN dbo.Users  u ON u.UserId = b.UserId
INNER JOIN dbo.Courts c ON c.CourtId = b.CourtId;
GO

-- ------------------------------------------------------------
-- 3. vw_AdminDashboard
--    Pending, Booked, doanh thu lý thuyết, active users.
--    Doanh thu lý thuyết = tổng TotalCost của BOOKED + COMPLETED.
-- ------------------------------------------------------------
IF OBJECT_ID(N'dbo.vw_AdminDashboard', N'V') IS NOT NULL
    DROP VIEW dbo.vw_AdminDashboard;
GO

CREATE VIEW dbo.vw_AdminDashboard
AS
SELECT
    (SELECT COUNT(*) FROM dbo.Bookings WHERE Status = N'PENDING')                          AS PendingCount,
    (SELECT COUNT(*) FROM dbo.Bookings WHERE Status = N'BOOKED')                           AS BookedCount,
    (SELECT ISNULL(SUM(TotalCost), 0) FROM dbo.Bookings WHERE Status IN (N'BOOKED', N'COMPLETED')) AS TheoreticalRevenue,
    (SELECT COUNT(*) FROM dbo.Users WHERE IsActive = 1)                                     AS ActiveUsers;
GO

-- ------------------------------------------------------------
-- 4. vw_AllBookings
--    Chi tiết booking phục vụ quản trị (kèm audit nhãn trạng thái CASE).
-- ------------------------------------------------------------
IF OBJECT_ID(N'dbo.vw_AllBookings', N'V') IS NOT NULL
    DROP VIEW dbo.vw_AllBookings;
GO

CREATE VIEW dbo.vw_AllBookings
AS
SELECT
    b.BookingId,
    b.UserId,
    u.Username              AS CustomerUsername,
    u.PhoneNumber           AS CustomerPhone,
    b.CourtId,
    c.CourtName,
    c.SurfaceType,
    c.SizeType,
    c.OwnerId,
    c.PricePerHour,
    b.StartTime,
    b.EndTime,
    b.Status,
    CASE b.Status
        WHEN N'PENDING'   THEN N'Đang chờ duyệt'
        WHEN N'BOOKED'    THEN N'Đã xác nhận'
        WHEN N'COMPLETED' THEN N'Đã hoàn thành'
        WHEN N'REJECTED'  THEN N'Đã từ chối'
        WHEN N'CANCELLED' THEN N'Đã hủy'
        ELSE b.Status
    END AS StatusLabel,
    b.TotalCost,
    b.CreatedAt,
    b.UpdatedAt
FROM dbo.Bookings b
INNER JOIN dbo.Users  u ON u.UserId = b.UserId
INNER JOIN dbo.Courts c ON c.CourtId = b.CourtId;
GO

PRINT N'[OK] 4 Views đã được tạo.';