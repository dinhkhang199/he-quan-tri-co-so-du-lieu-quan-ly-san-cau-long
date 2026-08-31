/* ============================================================
   Script: build_product_test_db.sql
   Tạo và khởi tạo database cô lập BadmintonCourtManagement_ProductTest
   ============================================================ */

USE master;
GO

IF DB_ID(N'BadmintonCourtManagement_ProductTest') IS NOT NULL
BEGIN
    ALTER DATABASE BadmintonCourtManagement_ProductTest SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE BadmintonCourtManagement_ProductTest;
END;
GO

CREATE DATABASE BadmintonCourtManagement_ProductTest;
GO
ALTER DATABASE BadmintonCourtManagement_ProductTest SET RECOVERY FULL;
GO
ALTER DATABASE BadmintonCourtManagement_ProductTest SET COMPATIBILITY_LEVEL = 150;
GO

PRINT N'[OK] Database BadmintonCourtManagement_ProductTest đã tạo thành công.';
GO
