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

-- Login cho ứng dụng — mật khẩu phải được cung cấp qua SQLCMD variable:
--   sqlcmd ... -v BCM_APP_PASSWORD="<YOUR_LOCAL_PASSWORD>"
-- Login là server principal → phải tạo ở scope master (dù file chạy sau khi DB đã có).
-- Nếu $(BCM_APP_PASSWORD) chưa được thay thế (chạy ngoài SQLCMD mode), script sẽ fail rõ ràng.
IF SUSER_ID(N'bcm_app') IS NULL
BEGIN
    DECLARE @rawAppPassword NVARCHAR(4000) = CAST('$(BCM_APP_PASSWORD)' AS NVARCHAR(4000));
    IF @rawAppPassword = N'$' + N'(BCM_APP_PASSWORD)'
        THROW 50100, N'BCM_APP_PASSWORD SQLCMD variable is not set. Run with: -v BCM_APP_PASSWORD="<password>"', 1;
    DECLARE @loginSql NVARCHAR(4000) = N'CREATE LOGIN bcm_app WITH PASSWORD = N''' + REPLACE(@rawAppPassword, N'''', N'''''') + N''', CHECK_POLICY = OFF, CHECK_EXPIRATION = OFF;';
    EXEC sp_executesql @loginSql;
END
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

-- ---- App chỉ được EXECUTE SP/Function + SELECT đúng các nguồn được cấp ----
-- KNOWN-05 FIX: Loại bỏ GRANT SELECT trực tiếp trên Users (chứa PasswordHash nhạy cảm).
-- App truy cập dữ liệu thông qua SP (WITH EXECUTE AS OWNER) hoặc các nguồn SELECT
-- được cấp rõ ràng ở dưới (filtered views + bảng Courts chỉ-đọc cho quản lý sân).
GRANT EXECUTE ON SCHEMA::dbo TO bcm_app_role;
-- vw_AvailableCourts: public/guest active-court availability path.
GRANT SELECT ON OBJECT::dbo.vw_AvailableCourts TO bcm_app_role;
-- vw_AllBookings: authenticated manager booking-list path. Row-level scope
-- (MANAGER all / COURT_MANAGER owned courts) is applied by the application SQL
-- using SESSION_CONTEXT on the authenticated connection — never client-side.
GRANT SELECT ON OBJECT::dbo.vw_AllBookings TO bcm_app_role;
-- dbo.Courts: authenticated court-management READ path (Phase 2.7). The
-- management screen must list BOTH active and inactive courts for the locked
-- Tất cả / Đang hoạt động / Ngừng hoạt động filters, which vw_AvailableCourts
-- (IsActive = 1) cannot provide, so a narrow base-table SELECT is approved.
-- COURT_MANAGER scope (OwnerId = SESSION_CONTEXT('UserId')) is applied by the
-- application SQL on the authenticated connection. This is READ ONLY:
-- mutations still go exclusively through sp_CreateCourt / sp_UpdateCourt /
-- sp_DeactivateCourt (INSERT/UPDATE/DELETE on Courts stays DENYed below).
GRANT SELECT ON OBJECT::dbo.Courts TO bcm_app_role;
-- vw_BookingHistory, vw_AdminDashboard chứa dữ liệu toàn bộ booking → app chỉ
-- truy cập qua SP (sp_GetMyBookings, sp_GetDashboard...) với EXECUTE AS OWNER.
-- Ngoài ra: Column-level DENY bên dưới chặn PasswordHash kể cả khi có SELECT bảng;
-- scope theo chủ sân của vw_AllBookings luôn do application enforce bằng
-- SESSION_CONTEXT trên connection đã đăng nhập, không dựa vào lọc ở client.

-- Column-level DENY: ngay cả khi có quyền SELECT bảng, PasswordHash vẫn bị chặn
DENY SELECT ON dbo.Users(PasswordHash) TO bcm_app_role;
-- ActivityLogs chứa audit nhạy cảm → không cho phép SELECT trực tiếp
DENY SELECT ON OBJECT::dbo.ActivityLogs TO bcm_app_role;

-- Không cấp SELECT thêm cho các bảng lõi còn lại: Users (chứa PasswordHash và
-- dữ liệu cá nhân), Bookings, Notifications — chúng chỉ truy cập qua SP với
-- WITH EXECUTE AS OWNER. dbo.Courts được cấp SELECT chỉ-đọc (riêng cho quản lý
-- sân); không cấp INSERT/UPDATE/DELETE ở bất kỳ bảng lõi nào (mọi thay đổi đi
-- qua Stored Procedure với WITH EXECUTE AS OWNER).
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
