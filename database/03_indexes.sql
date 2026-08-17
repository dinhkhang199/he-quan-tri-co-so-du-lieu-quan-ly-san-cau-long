/* ============================================================
   BadmintonCourtManagement
   Script : 03_indexes.sql
   Mục đích: Index phục vụ overlap check, truy vấn lịch sử, dashboard
   ============================================================ */

USE BadmintonCourtManagement;
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

PRINT N'[OK] Indexes đã được tạo.';