/* ============================================================
   BadmintonCourtManagement
   Script : 08_security.sql
   Mục đích: An toàn/bảo mật (contract section 4, 10)
   - Role Database 'bcm_app_role'
   - User 'bcm_app' dùng cho ứng dụng
   - App chỉ thao tác qua Stored Procedure (WITH EXECUTE AS OWNER)
   - DENY INSERT/UPDATE/DELETE trực tiếp lên 5 bảng lõi
   ============================================================ */

USE BadmintonCourtManagement;
GO

-- Login cho ứng dụng (demo - đổi mật khẩu trước khi deploy thật; connection string trong config)
IF SUSER_ID(N'bcm_app') IS NULL
    CREATE LOGIN bcm_app WITH PASSWORD = N'Bcm@Passw0rd', CHECK_POLICY = OFF, CHECK_EXPIRATION = OFF;
GO

-- User + role trong database
IF DATABASE_PRINCIPAL_ID(N'bcm_app') IS NULL
    CREATE USER bcm_app FOR LOGIN bcm_app;
GO

IF DATABASE_PRINCIPAL_ID(N'bcm_app_role') IS NULL
    CREATE ROLE bcm_app_role;
GO

ALTER ROLE bcm_app_role ADD MEMBER bcm_app;
GO

-- ---- App chỉ được EXECUTE SP/Function + SELECT 4 Views + SELECT bảng lõi (chỉ đọc) ----
GRANT EXECUTE ON SCHEMA::dbo TO bcm_app_role;
GRANT SELECT ON  OBJECT::dbo.vw_AvailableCourts  TO bcm_app_role;
GRANT SELECT ON  OBJECT::dbo.vw_BookingHistory   TO bcm_app_role;
GRANT SELECT ON  OBJECT::dbo.vw_AdminDashboard   TO bcm_app_role;
GRANT SELECT ON  OBJECT::dbo.vw_AllBookings      TO bcm_app_role;
-- SELECT cho phép để function/proc (execute-as-caller) có thể đọc.
GRANT SELECT ON  OBJECT::dbo.Users         TO bcm_app_role;
GRANT SELECT ON  OBJECT::dbo.Courts        TO bcm_app_role;
GRANT SELECT ON  OBJECT::dbo.Bookings      TO bcm_app_role;
GRANT SELECT ON  OBJECT::dbo.ActivityLogs  TO bcm_app_role;
GRANT SELECT ON  OBJECT::dbo.Notifications TO bcm_app_role;
GO

-- ---- Cấm app INSERT/UPDATE/DELETE trực tiếp lên bảng lõi ----
-- (SP dùng WITH EXECUTE AS OWNER nên vẫn chạy được nghiệp vụ theo contract)
DENY INSERT, UPDATE, DELETE ON OBJECT::dbo.Users         TO bcm_app_role;
DENY INSERT, UPDATE, DELETE ON OBJECT::dbo.Courts        TO bcm_app_role;
DENY INSERT, UPDATE, DELETE ON OBJECT::dbo.Bookings      TO bcm_app_role;
DENY INSERT, UPDATE, DELETE ON OBJECT::dbo.ActivityLogs  TO bcm_app_role;
DENY INSERT, UPDATE, DELETE ON OBJECT::dbo.Notifications TO bcm_app_role;
GO

PRINT N'[OK] Security: bcm_app chỉ thao tác qua Stored Procedure; DENY DML trực tiếp lên bảng lõi.';
GO