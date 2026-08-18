/* ============================================================
   BadmintonCourtManagement
   Script : 02_seed.sql
   Mục đích: Seed dữ liệu demo cố định, chạy lại được (contract section 11)
   - Users   : 7 (1 MANAGER, 2 COURT_MANAGER, 4 CUSTOMER, trong đó 1 inactive)
   - Courts  : 6 (2 owners, 1 inactive)
   - Bookings: 15 (đủ PENDING/BOOKED/CANCELLED/COMPLETED/REJECTED + boundary/overlap-PENDING)
   - ActivityLogs / Notifications: vài dòng demo; dòng runtime đi qua Trigger (07)
   Lưu ý: Password chỉ lưu hash SHA2_256('bcms|' + plain) - cùng công thức với sp_Login.
   ============================================================ */

USE BadmintonCourtManagement;
GO

-- ---- Chạy lại được: xóa sạch theo thứ tự FK ----
DELETE FROM dbo.ActivityLogs;
DELETE FROM dbo.Notifications;
DELETE FROM dbo.Bookings;
DELETE FROM dbo.Courts;
DELETE FROM dbo.Users;
GO

PRINT N'[OK] Seed: bắt đầu nạp dữ liệu demo...';
GO

-- ------------------------------------------------------------
-- USERS
-- ------------------------------------------------------------
INSERT INTO dbo.Users (UserId, Username, PasswordHash, PhoneNumber, Role, IsActive, LastLogin)
SELECT * FROM (VALUES
    ('A1000001-0000-0000-0000-000000000001', N'manager',       CONVERT(VARBINARY(64), HASHBYTES('SHA2_256', N'bcms|manager123')), N'0901000001', N'MANAGER',        1, NULL),
    ('A1000001-0000-0000-0000-000000000002', N'courtmanager1', CONVERT(VARBINARY(64), HASHBYTES('SHA2_256', N'bcms|cm1pass')),    N'0901000002', N'COURT_MANAGER',  1, NULL),
    ('A1000001-0000-0000-0000-000000000003', N'courtmanager2', CONVERT(VARBINARY(64), HASHBYTES('SHA2_256', N'bcms|cm2pass')),    N'0901000003', N'COURT_MANAGER',  1, NULL),
    ('A1000001-0000-0000-0000-000000000004', N'customer1',     CONVERT(VARBINARY(64), HASHBYTES('SHA2_256', N'bcms|cus1pass')),   N'0901000004', N'CUSTOMER',       1, NULL),
    ('A1000001-0000-0000-0000-000000000005', N'customer2',     CONVERT(VARBINARY(64), HASHBYTES('SHA2_256', N'bcms|cus2pass')),   N'0901000005', N'CUSTOMER',       1, NULL),
    ('A1000001-0000-0000-0000-000000000006', N'customer3',     CONVERT(VARBINARY(64), HASHBYTES('SHA2_256', N'bcms|cus3pass')),   N'0901000006', N'CUSTOMER',       1, NULL),
    ('A1000001-0000-0000-0000-000000000007', N'inactive_user', CONVERT(VARBINARY(64), HASHBYTES('SHA2_256', N'bcms|inactive1')),  N'0901000007', N'CUSTOMER',       0, NULL)
) AS S(UserId, Username, PasswordHash, PhoneNumber, Role, IsActive, LastLogin);
GO

-- ------------------------------------------------------------
-- COURTS (6 sân: 3 cho CM1, 3 cho CM2 - sân 6 inactive)
-- ------------------------------------------------------------
INSERT INTO dbo.Courts (CourtId, CourtName, Address, SurfaceType, SizeType, PricePerHour, PricePerThreeHours, ImageUrl, OwnerId, IsActive)
SELECT * FROM (VALUES
    ('C1000001-0000-0000-0000-000000000001', N'Sân 01', N'12 Nguyễn Hữu Thọ, Q7, TP.HCM',    N'STANDARD', N'SINGLE', 100000, 270000, NULL, 'A1000001-0000-0000-0000-000000000002', 1),
    ('C1000001-0000-0000-0000-000000000002', N'Sân 02', N'12 Nguyễn Hữu Thọ, Q7, TP.HCM',    N'STANDARD', N'DOUBLE', 100000, 270000, NULL, 'A1000001-0000-0000-0000-000000000002', 1),
    ('C1000001-0000-0000-0000-000000000003', N'Sân 03', N'12 Nguyễn Hữu Thọ, Q7, TP.HCM',    N'VIP',      N'SINGLE', 100000, 270000, NULL, 'A1000001-0000-0000-0000-000000000002', 1),
    ('C1000001-0000-0000-0000-000000000004', N'Sân 04', N'5 Trần Não, TP.Thủ Đức, TP.HCM',   N'STANDARD', N'SINGLE', 100000, 270000, NULL, 'A1000001-0000-0000-0000-000000000003', 1),
    ('C1000001-0000-0000-0000-000000000005', N'Sân 05', N'5 Trần Não, TP.Thủ Đức, TP.HCM',   N'VIP',      N'DOUBLE', 100000, 270000, NULL, 'A1000001-0000-0000-0000-000000000003', 1),
    ('C1000001-0000-0000-0000-000000000006', N'Sân 06', N'5 Trần Não, TP.Thủ Đức, TP.HCM',   N'STANDARD', N'SINGLE', 100000, 270000, NULL, 'A1000001-0000-0000-0000-000000000003', 0)
) AS S(CourtId, CourtName, Address, SurfaceType, SizeType, PricePerHour, PricePerThreeHours, ImageUrl, OwnerId, IsActive);
GO

-- ------------------------------------------------------------
-- BOOKINGS (15 - ngày tính tương đối GETDATE() để luôn hợp lệ khi seed)
-- b4 & b9: 2 PENDING overlap cùng sân/khung → dùng demo CC-01 approve cạnh tranh
-- KNOWN-04 FIX: Tắt trigger trong lúc INSERT bookings để tránh trigger sinh
-- audit/notification trùng với dòng demo explicit → deterministic rerun.
-- ------------------------------------------------------------
DECLARE @T DATE = CAST(GETDATE() AS DATE);
DECLARE @D1 DATE = DATEADD(DAY, 1, @T);   -- mai
DECLARE @D2 DATE = DATEADD(DAY, 2, @T);   -- ngày kia

DECLARE @T0600 datetime2(0) = DATETIMEFROMPARTS(YEAR(@T), MONTH(@T), DAY(@T), 6, 0, 0, 0);
DECLARE @T0700 datetime2(0) = DATETIMEFROMPARTS(YEAR(@T), MONTH(@T), DAY(@T), 7, 0, 0, 0);
DECLARE @T0800 datetime2(0) = DATETIMEFROMPARTS(YEAR(@T), MONTH(@T), DAY(@T), 8, 0, 0, 0);
DECLARE @T0900 datetime2(0) = DATETIMEFROMPARTS(YEAR(@T), MONTH(@T), DAY(@T), 9, 0, 0, 0);
DECLARE @T1000 datetime2(0) = DATETIMEFROMPARTS(YEAR(@T), MONTH(@T), DAY(@T), 10, 0, 0, 0);
DECLARE @T1200 datetime2(0) = DATETIMEFROMPARTS(YEAR(@T), MONTH(@T), DAY(@T), 12, 0, 0, 0);
DECLARE @T1400 datetime2(0) = DATETIMEFROMPARTS(YEAR(@T), MONTH(@T), DAY(@T), 14, 0, 0, 0);
DECLARE @T1800 datetime2(0) = DATETIMEFROMPARTS(YEAR(@T), MONTH(@T), DAY(@T), 18, 0, 0, 0);
DECLARE @T1900 datetime2(0) = DATETIMEFROMPARTS(YEAR(@T), MONTH(@T), DAY(@T), 19, 0, 0, 0);
DECLARE @T2000 datetime2(0) = DATETIMEFROMPARTS(YEAR(@T), MONTH(@T), DAY(@T), 20, 0, 0, 0);
DECLARE @T2200 datetime2(0) = DATETIMEFROMPARTS(YEAR(@T), MONTH(@T), DAY(@T), 22, 0, 0, 0);

DECLARE @D1_0600 datetime2(0) = DATETIMEFROMPARTS(YEAR(@D1), MONTH(@D1), DAY(@D1), 6, 0, 0, 0);
DECLARE @D1_0900 datetime2(0) = DATETIMEFROMPARTS(YEAR(@D1), MONTH(@D1), DAY(@D1), 9, 0, 0, 0);
DECLARE @D1_0700 datetime2(0) = DATETIMEFROMPARTS(YEAR(@D1), MONTH(@D1), DAY(@D1), 7, 0, 0, 0);
DECLARE @D1_0800 datetime2(0) = DATETIMEFROMPARTS(YEAR(@D1), MONTH(@D1), DAY(@D1), 8, 0, 0, 0);
DECLARE @D1_1000 datetime2(0) = DATETIMEFROMPARTS(YEAR(@D1), MONTH(@D1), DAY(@D1), 10, 0, 0, 0);
DECLARE @D1_1300 datetime2(0) = DATETIMEFROMPARTS(YEAR(@D1), MONTH(@D1), DAY(@D1), 13, 0, 0, 0);

DECLARE @D2_0700 datetime2(0) = DATETIMEFROMPARTS(YEAR(@D2), MONTH(@D2), DAY(@D2), 7, 0, 0, 0);
DECLARE @D2_0800 datetime2(0) = DATETIMEFROMPARTS(YEAR(@D2), MONTH(@D2), DAY(@D2), 8, 0, 0, 0);
DECLARE @D2_0830 datetime2(0) = DATETIMEFROMPARTS(YEAR(@D2), MONTH(@D2), DAY(@D2), 8, 30, 0, 0);

-- BOOKINGS INSERT - deterministic, KHÔNG vô hiệu hóa toàn bộ trigger.
-- Chỉ tạm tắt 2 trigger INSERT sinh side-effect (audit + notification) để không
-- trùng với các dòng demo explicit; CÓ ĐIỀU KIỆN (nếu trigger đã tồn tại - script
-- 07 chạy ở bước 7) và BẢO ĐẢM bật lại kể cả khi INSERT gặp lỗi (TRY/CATCH).
-- Trigger an toàn state (ValidateState) và overlap (PreventBookedOverlap) vẫn
-- HOẠT ĐỘNG khi chúng tồn tại.
DECLARE @SeedErr INT = 0;

IF OBJECT_ID(N'dbo.trg_Bookings_AuditInsert', N'TR') IS NOT NULL
    ALTER TABLE dbo.Bookings DISABLE TRIGGER trg_Bookings_AuditInsert;
IF OBJECT_ID(N'dbo.trg_Bookings_NotifyInsert', N'TR') IS NOT NULL
    ALTER TABLE dbo.Bookings DISABLE TRIGGER trg_Bookings_NotifyInsert;

BEGIN TRY
    INSERT INTO dbo.Bookings (BookingId, UserId, CourtId, StartTime, EndTime, Status, TotalCost)
    SELECT * FROM (VALUES
        -- Sân 1
        ('B1000001-0000-0000-0000-000000000001', 'A1000001-0000-0000-0000-000000000004', 'C1000001-0000-0000-0000-000000000001', @T0700,  @T0800,  N'BOOKED',    100000),
        ('B1000001-0000-0000-0000-000000000002', 'A1000001-0000-0000-0000-000000000005', 'C1000001-0000-0000-0000-000000000001', @T0800,  @T0900,  N'BOOKED',    100000),
        ('B1000001-0000-0000-0000-000000000003', 'A1000001-0000-0000-0000-000000000004', 'C1000001-0000-0000-0000-000000000001', @T0600,  @T0700,  N'COMPLETED', 100000),
        ('B1000001-0000-0000-0000-000000000004', 'A1000001-0000-0000-0000-000000000006', 'C1000001-0000-0000-0000-000000000001', @D1_0600, @D1_0900, N'PENDING',   270000),
        ('B1000001-0000-0000-0000-000000000009', 'A1000001-0000-0000-0000-000000000005', 'C1000001-0000-0000-0000-000000000001', @D1_0600, @D1_0900, N'PENDING',   270000),
        ('B1000001-0000-0000-0000-000000000010', 'A1000001-0000-0000-0000-000000000006', 'C1000001-0000-0000-0000-000000000001', @T0900,  @T1000,  N'CANCELLED', 100000),
        -- Sân 2
        ('B1000001-0000-0000-0000-000000000005', 'A1000001-0000-0000-0000-000000000005', 'C1000001-0000-0000-0000-000000000002', @T1800,  @T1900,  N'BOOKED',    100000),
        ('B1000001-0000-0000-0000-000000000006', 'A1000001-0000-0000-0000-000000000006', 'C1000001-0000-0000-0000-000000000002', @T1900,  @T2000,  N'PENDING',   100000),
        -- Sân 3
        ('B1000001-0000-0000-0000-000000000007', 'A1000001-0000-0000-0000-000000000004', 'C1000001-0000-0000-0000-000000000003', @D1_0700, @D1_0800, N'BOOKED',   100000),
        ('B1000001-0000-0000-0000-000000000008', 'A1000001-0000-0000-0000-000000000005', 'C1000001-0000-0000-0000-000000000003', @T2000,  @T2200,  N'COMPLETED', 200000),
        -- Sân 4
        ('B1000001-0000-0000-0000-000000000011', 'A1000001-0000-0000-0000-000000000004', 'C1000001-0000-0000-0000-000000000004', @D1_1000, @D1_1300, N'REJECTED',  270000),
        ('B1000001-0000-0000-0000-000000000013', 'A1000001-0000-0000-0000-000000000006', 'C1000001-0000-0000-0000-000000000004', @D2_0700, @D2_0800, N'BOOKED',    100000),
        ('B1000001-0000-0000-0000-000000000015', 'A1000001-0000-0000-0000-000000000005', 'C1000001-0000-0000-0000-000000000004', @T1900,  @T2000,  N'BOOKED',    100000),
        -- Sân 5
        ('B1000001-0000-0000-0000-000000000012', 'A1000001-0000-0000-0000-000000000005', 'C1000001-0000-0000-0000-000000000005', @D2_0700, @D2_0830, N'BOOKED',   150000),
        ('B1000001-0000-0000-0000-000000000014', 'A1000001-0000-0000-0000-000000000004', 'C1000001-0000-0000-0000-000000000005', @T1200,  @T1400,  N'COMPLETED', 200000)
    ) AS S(BookingId, UserId, CourtId, StartTime, EndTime, Status, TotalCost);
END TRY
BEGIN CATCH
    SET @SeedErr = ERROR_NUMBER();
    PRINT N'[LỖI seed Bookings] ' + ERROR_MESSAGE();
END CATCH;

-- Luôn bật lại trigger (kể cả khi có lỗi) - đảm bảo không phá contract sản xuất
IF OBJECT_ID(N'dbo.trg_Bookings_AuditInsert', N'TR') IS NOT NULL
    ALTER TABLE dbo.Bookings ENABLE TRIGGER trg_Bookings_AuditInsert;
IF OBJECT_ID(N'dbo.trg_Bookings_NotifyInsert', N'TR') IS NOT NULL
    ALTER TABLE dbo.Bookings ENABLE TRIGGER trg_Bookings_NotifyInsert;

IF @SeedErr <> 0
    THROW 52010, N'Seed Bookings thất bại (đã bật lại trigger). Xem lỗi ở trên.', 1;
GO

-- ------------------------------------------------------------
-- ActivityLogs + Notifications (dòng demo; dòng runtime đi qua trigger)
-- ------------------------------------------------------------
INSERT INTO dbo.ActivityLogs (LogId, UserId, BookingId, Action, OldStatus, NewStatus)
SELECT * FROM (VALUES
    ('D1000001-0000-0000-0000-000000000001', 'A1000001-0000-0000-0000-000000000004', 'B1000001-0000-0000-0000-000000000001', N'CREATE',  NULL,        N'PENDING'),
    ('D1000001-0000-0000-0000-000000000002', 'A1000001-0000-0000-0000-000000000002', 'B1000001-0000-0000-0000-000000000001', N'APPROVE', N'PENDING',  N'BOOKED'),
    ('D1000001-0000-0000-0000-000000000003', 'A1000001-0000-0000-0000-000000000003', 'B1000001-0000-0000-0000-000000000015', N'APPROVE', N'PENDING',  N'BOOKED')
) AS S(LogId, UserId, BookingId, Action, OldStatus, NewStatus);

INSERT INTO dbo.Notifications (NotificationId, UserId, BookingId, Message, IsRead)
SELECT * FROM (VALUES
    ('E1000001-0000-0000-0000-000000000001', 'A1000001-0000-0000-0000-000000000002', 'B1000001-0000-0000-0000-000000000001', N'Booking của bạn đã được duyệt (BOOKED): Sân 01.', 1),
    ('E1000001-0000-0000-0000-000000000002', 'A1000001-0000-0000-0000-000000000003', 'B1000001-0000-0000-0000-000000000015', N'Booking của bạn đã được duyệt (BOOKED): Sân 04.', 0)
) AS S(NotificationId, UserId, BookingId, Message, IsRead);
GO

PRINT N'[OK] Seed hoàn tất.';
SELECT
    (SELECT COUNT(*) FROM dbo.Users)       AS Users,
    (SELECT COUNT(*) FROM dbo.Courts)      AS Courts,
    (SELECT COUNT(*) FROM dbo.Bookings)    AS Bookings,
    (SELECT COUNT(*) FROM dbo.ActivityLogs) AS ActivityLogs,
    (SELECT COUNT(*) FROM dbo.Notifications) AS Notifications;
GO