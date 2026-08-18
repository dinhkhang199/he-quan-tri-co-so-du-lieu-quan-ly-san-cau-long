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
-- Login là server principal → phải tạo ở scope master (dù file chạy sau khi DB đã có).
IF SUSER_ID(N'bcm_app') IS NULL
    CREATE LOGIN bcm_app WITH PASSWORD = N'Bcm@Passw0rd', CHECK_POLICY = OFF, CHECK_EXPIRATION = OFF;
GO

-- ============================================================
-- SEC: chống giả mạo SESSION_CONTEXT (P0)
-- bcm_app KHÔNG được tự gọi sys.sp_set_session_context để giả mạo actor
-- (bỏ qua sp_Login). Permission trên system stored procedure chỉ được cấp
-- ở DATABASE MASTER (Msg 4629) → phải chuyển sang master để DENY.
-- sp_Login (WITH EXECUTE AS OWNER → thân thủ tục chạy dưới owner dbo/sysadmin)
-- vẫn gọi được sp_set_session_context nội bộ; bcm_app chỉ có thể có context
-- hợp lệ thông qua sp_Login với mật khẩu/username đúng (trust model section Q).
-- ============================================================
USE master;
GO
-- Grantee của DENY trên sys.sp_set_session_context là user trong database master
-- (permission được lưu ở master.sys.database_permissions) → cần user master cho login.
IF DATABASE_PRINCIPAL_ID(N'bcm_app') IS NULL
    CREATE USER bcm_app FOR LOGIN bcm_app;
GO
IF NOT EXISTS (
    SELECT 1 FROM sys.database_permissions p
    WHERE p.class_desc IN (N'OBJECT_OR_COLUMN', N'OBJECT')
      AND p.major_id = OBJECT_ID(N'sys.sp_set_session_context')
      AND p.grantee_principal_id = DATABASE_PRINCIPAL_ID(N'bcm_app')
      AND p.permission_name = N'EXECUTE'
      AND p.state_desc = N'DENY'
)
    DENY EXECUTE ON sys.sp_set_session_context TO bcm_app;
GO
PRINT N'[OK] Security (master): DENY EXECUTE sys.sp_set_session_context TO bcm_app.';
GO
USE BadmintonCourtManagement;
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
-- KNOWN-05 FIX: Loại bỏ GRANT SELECT trực tiếp trên Users (chứa PasswordHash nhạy cảm).
-- App chỉ truy cập dữ liệu thông qua SP (WITH EXECUTE AS OWNER) hoặc Views.
-- Views đã lọc/ghấu dữ liệu nhạy cảm (PasswordHash không xuất hiện ở bất kỳ view nào).
GRANT EXECUTE ON SCHEMA::dbo TO bcm_app_role;
GRANT SELECT ON  OBJECT::dbo.vw_AvailableCourts  TO bcm_app_role;
-- vw_BookingHistory, vw_AdminDashboard, vw_AllBookings chứa dữ liệu toàn bộ
-- booking/notification → app chỉ truy cập qua SP (sp_GetMyBookings, sp_GetDashboard...).
-- GRANT SELECT trên Views còn lại được cấp qua EXECUTE AS OWNER của SP.

-- Column-level DENY: ngay cả khi có quyền SELECT bảng, PasswordHash vẫn bị chặn
DENY SELECT ON dbo.Users(PasswordHash) TO bcm_app_role;
-- ActivityLogs chứa audit nhạy cảm → không cho phép SELECT trực tiếp
DENY SELECT ON OBJECT::dbo.ActivityLogs TO bcm_app_role;

-- Courts: SELECT cho phép để app đọc thông tin sân công khai (view vw_AvailableCourts cũng đã đủ)
-- Các bảng còn lại (Users, Bookings, Notifications) chỉ truy cập qua SP với WITH EXECUTE AS OWNER
GO

-- ---- Cấm app INSERT/UPDATE/DELETE trực tiếp lên bảng lõi ----
-- (SP dùng WITH EXECUTE AS OWNER nên vẫn chạy được nghiệp vụ theo contract)
DENY INSERT, UPDATE, DELETE ON OBJECT::dbo.Users         TO bcm_app_role;
DENY INSERT, UPDATE, DELETE ON OBJECT::dbo.Courts        TO bcm_app_role;
DENY INSERT, UPDATE, DELETE ON OBJECT::dbo.Bookings      TO bcm_app_role;
DENY INSERT, UPDATE, DELETE ON OBJECT::dbo.ActivityLogs  TO bcm_app_role;
DENY INSERT, UPDATE, DELETE ON OBJECT::dbo.Notifications TO bcm_app_role;
GO

PRINT N'[OK] Security: bcm_app không thể tự set SESSION_CONTEXT (DENY sys.sp_set_session_context, master scope).';
PRINT N'[OK] Security: bcm_app chỉ thao tác qua Stored Procedure; DENY DML trực tiếp lên bảng lõi.';
GO