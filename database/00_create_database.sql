/* ============================================================
   BadmintonCourtManagement - Hệ quản trị cơ sở dữ liệu (SQL Server)
   Script : 00_create_database.sql
   Mục đích: Tạo database BadmintonCourtManagement từ rỗng (DB-01)
   Lưu ý  : Contract v2.0 - chỉ chạy T-SQL trên MS SQL Server
   ============================================================ */

IF DB_ID(N'BadmintonCourtManagement') IS NOT NULL
BEGIN
    -- Tạo lại sạch từ đầu theo test matrix DB-01 (chạy lại được).
    ALTER DATABASE BadmintonCourtManagement SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE BadmintonCourtManagement;
END
GO

CREATE DATABASE BadmintonCourtManagement;
GO

-- Thiết lập chế độ RECOVERY FULL để backup/restore demo có ý nghĩa (xem 15_backup_restore_demo.sql)
ALTER DATABASE BadmintonCourtManagement SET RECOVERY FULL;
GO

ALTER DATABASE BadmintonCourtManagement SET COMPATIBILITY_LEVEL = 150; -- SQL Server 2019 trở lên
GO

USE BadmintonCourtManagement;
GO

PRINT N'[OK] Database BadmintonCourtManagement đã được tạo.';
GO