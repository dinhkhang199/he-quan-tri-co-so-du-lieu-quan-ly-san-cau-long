/* ============================================================
   BadmintonCourtManagement
   Script : 03_indexes.sql
   Mục đích: Index phục vụ overlap check, truy vấn lịch sử, dashboard
   ============================================================ */

USE BadmintonCourtManagement;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- Email có thể NULL cho dữ liệu regression cũ, nhưng mọi email đã nhập phải duy nhất.
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'UQ_Users_Email_NotNull' AND object_id = OBJECT_ID(N'dbo.Users'))
    CREATE UNIQUE INDEX UQ_Users_Email_NotNull ON dbo.Users(Email) WHERE Email IS NOT NULL;
GO

-- Overlap check & booking theo thời gian cùng Court (quan trọng nhất cho sp_BookCourt / sp_ApproveBooking)
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_Bookings_Court_Status_Time' AND object_id = OBJECT_ID(N'dbo.Bookings'))
    CREATE INDEX IX_Bookings_Court_Status_Time ON dbo.Bookings (CourtId, Status, StartTime, EndTime);
GO

-- Lịch sử booking của khách hàng
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_Bookings_UserId' AND object_id = OBJECT_ID(N'dbo.Bookings'))
    CREATE INDEX IX_Bookings_UserId ON dbo.Bookings (UserId);
GO

-- Dashboard / thống kê theo trạng thái
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_Bookings_Status' AND object_id = OBJECT_ID(N'dbo.Bookings'))
    CREATE INDEX IX_Bookings_Status ON dbo.Bookings (Status, TotalCost);
GO

-- Thông báo đọc/chưa đọc theo người nhận
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_Notifications_User_IsRead' AND object_id = OBJECT_ID(N'dbo.Notifications'))
    CREATE INDEX IX_Notifications_User_IsRead ON dbo.Notifications (UserId, IsRead);
GO

-- Audit truy vấn theo user / booking
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_ActivityLogs_UserId' AND object_id = OBJECT_ID(N'dbo.ActivityLogs'))
    CREATE INDEX IX_ActivityLogs_UserId ON dbo.ActivityLogs (UserId);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_ActivityLogs_BookingId' AND object_id = OBJECT_ID(N'dbo.ActivityLogs'))
    CREATE INDEX IX_ActivityLogs_BookingId ON dbo.ActivityLogs (BookingId);
GO

-- Sân theo owner & trạng thái active
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_Courts_OwnerId' AND object_id = OBJECT_ID(N'dbo.Courts'))
    CREATE INDEX IX_Courts_OwnerId ON dbo.Courts (OwnerId);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_Courts_IsActive' AND object_id = OBJECT_ID(N'dbo.Courts'))
    CREATE INDEX IX_Courts_IsActive ON dbo.Courts (IsActive);
GO

/* ============================================================
   IMP-03: Index tuning (bổ sung) — không thêm bảng/view/SP nào,
   chỉ tối ưu đường truy vấn nóng.
   Filtered index cần QUOTED_IDENTIFIER ON khi tạo.
   ============================================================ */
SET QUOTED_IDENTIFIER ON;
GO

-- (a) Overlap check chỉ quan tâm Status = 'BOOKED' => filtered index nhỏ hơn,
--     seek trực tiếp (CourtId, StartTime, EndTime) không phải lọc Status.
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_Bookings_Booked_Court_Time' AND object_id = OBJECT_ID(N'dbo.Bookings'))
    CREATE INDEX IX_Bookings_Booked_Court_Time ON dbo.Bookings (CourtId, StartTime, EndTime)
        WHERE Status = N'BOOKED';
GO

-- (b) Hàng đợi duyệt của manager: chỉ các booking PENDING.
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_Bookings_Pending_Court_Time' AND object_id = OBJECT_ID(N'dbo.Bookings'))
    CREATE INDEX IX_Bookings_Pending_Court_Time ON dbo.Bookings (CourtId, StartTime, EndTime)
        INCLUDE (UserId, TotalCost)
        WHERE Status = N'PENDING';
GO

-- (c) sp_GetMyBookings: WHERE UserId = @Actor ORDER BY StartTime DESC
--     -> covering index, bỏ được Key Lookup + Sort.
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_Bookings_User_Start' AND object_id = OBJECT_ID(N'dbo.Bookings'))
    CREATE INDEX IX_Bookings_User_Start ON dbo.Bookings (UserId, StartTime DESC)
        INCLUDE (CourtId, EndTime, Status, TotalCost);
GO

-- (d) sp_GetDashboard: doanh thu / thống kê theo khoảng StartTime.
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_Bookings_Start_Status' AND object_id = OBJECT_ID(N'dbo.Bookings'))
    CREATE INDEX IX_Bookings_Start_Status ON dbo.Bookings (StartTime)
        INCLUDE (Status, TotalCost, CourtId);
GO

-- (e) Badge "thông báo chưa đọc": phần lớn hàng là IsRead = 1 => filtered index.
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_Notifications_Unread' AND object_id = OBJECT_ID(N'dbo.Notifications'))
    CREATE INDEX IX_Notifications_Unread ON dbo.Notifications (UserId, CreatedAt DESC)
        INCLUDE (BookingId, Message)
        WHERE IsRead = 0;
GO

-- ------------------------------------------------------------
-- IMP-09 (chống spam PENDING — contract 5.2 cho phép UNIQUE/INDEX)
-- Vấn đề: contract cho phép nhiều PENDING chồng khung giờ (chỉ BOOKED mới
-- độc quyền). Hệ quả: MỘT khách có thể tạo vô hạn PENDING trùng nhau trên
-- cùng sân/khung giờ (spam + làm ngủ hộp thông báo của chủ sân).
-- Cách chặn: unique filtered index trên (UserId, CourtId, StartTime) cho
-- riêng trạng thái PENDING. Hai khách KHÁC NHAU vẫn được PENDING cùng khung
-- giờ (giữ nguyên seed b4/b9 và demo CC-01 approve cạnh tranh).
-- Vi phạm sẽ sinh lỗi SQL 2601, được app dịch thành thông báo tiếng Việt.
-- ------------------------------------------------------------
SET QUOTED_IDENTIFIER ON;

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'UQ_Bookings_OnePendingPerUserSlot' AND object_id = OBJECT_ID(N'dbo.Bookings'))
    CREATE UNIQUE INDEX UQ_Bookings_OnePendingPerUserSlot
        ON dbo.Bookings (UserId, CourtId, StartTime)
        WHERE Status = N'PENDING';
GO

PRINT N'[OK] Indexes đã được tạo.';
