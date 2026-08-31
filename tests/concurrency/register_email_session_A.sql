/* ============================================================
   BadmintonCourtManagement — Concurrency Test Suite
   Script : register_email_session_A.sql (Window A)
   Kịch bản : CC-EMAIL-01 — Đăng ký tài khoản song song cùng Email
   ============================================================ */

USE BadmintonCourtManagement;
GO
SET NOCOUNT ON;
SET XACT_ABORT OFF;
GO

-- 1. Chuẩn bị bảng cờ đồng bộ
IF OBJECT_ID('dbo._CCTestSync', 'U') IS NULL
    CREATE TABLE dbo._CCTestSync (Flag NVARCHAR(60) PRIMARY KEY, SetAt DATETIME2 NOT NULL DEFAULT SYSDATETIME());
GO

-- Dọn dẹp dữ liệu kịch bản cũ
DELETE FROM dbo._CCTestSync WHERE Flag LIKE 'CC_EMAIL_%';
DELETE FROM dbo.ActivityLogs WHERE UserId IN (SELECT UserId FROM dbo.Users WHERE Username LIKE 'concur_race_%');
DELETE FROM dbo.Users WHERE Username LIKE 'concur_race_%' OR Email = 'concur_race@badmintonpro.local';
GO

PRINT N'>>> Window A: Sẵn sàng thử nghiệm đăng ký song song cùng Email (CC-EMAIL-01)...';
INSERT INTO dbo._CCTestSync (Flag) VALUES ('CC_EMAIL_A_READY');
GO

-- Chờ Window B báo sẵn sàng (tối đa 15 giây)
DECLARE @w INT = 0;
WHILE NOT EXISTS (SELECT 1 FROM dbo._CCTestSync WHERE Flag = 'CC_EMAIL_B_READY') AND @w < 30
BEGIN
    WAITFOR DELAY '00:00:00.500';
    SET @w = @w + 1;
END;

IF NOT EXISTS (SELECT 1 FROM dbo._CCTestSync WHERE Flag = 'CC_EMAIL_B_READY')
BEGIN
    PRINT N'[FAIL] Timeout: Window B không phản hồi!';
    RETURN;
END;

PRINT N'>>> Window A: Bắt đầu gọi sp_Register (User A)...';

DECLARE @Email NVARCHAR(254) = N'concur_race@badmintonpro.local';
DECLARE @ErrA INT = 0;
DECLARE @MsgA NVARCHAR(400) = N'';

BEGIN TRY
    EXEC dbo.sp_Register
        @Username = N'concur_race_user_A',
        @Password = N'PassA_Strong123',
        @PhoneNumber = N'0977000011',
        @Email = @Email;
    PRINT N'>>> Window A: sp_Register THÀNH CÔNG.';
END TRY
BEGIN CATCH
    SET @ErrA = ERROR_NUMBER();
    SET @MsgA = ERROR_MESSAGE();
    PRINT N'>>> Window A: sp_Register BỊ CHẶN. Mã lỗi: ' + CAST(@ErrA AS NVARCHAR(10)) + N' - ' + @MsgA;
END CATCH;

INSERT INTO dbo._CCTestSync (Flag) VALUES ('CC_EMAIL_A_DONE');
GO

-- Chờ Window B hoàn tất
DECLARE @w2 INT = 0;
WHILE NOT EXISTS (SELECT 1 FROM dbo._CCTestSync WHERE Flag = 'CC_EMAIL_B_DONE') AND @w2 < 30
BEGIN
    WAITFOR DELAY '00:00:00.500';
    SET @w2 = @w2 + 1;
END;

-- Kiểm tra kết quả tổng thể
DECLARE @Email NVARCHAR(254) = N'concur_race@badmintonpro.local';
DECLARE @FinalCount INT = (SELECT COUNT(*) FROM dbo.Users WHERE Email = @Email);

PRINT N'------------------------------------------------------------';
PRINT N'>>> KẾT QUẢ ĐỒNG THỜI CC-EMAIL-01 (Window A):';
PRINT N'    Tổng số user mang email "' + @Email + N'": ' + CAST(@FinalCount AS NVARCHAR(10));
IF @FinalCount = 1
    PRINT N'>>> [CC-EMAIL-01 PASS]: Đăng ký đồng thời được serialize an toàn bằng sp_getapplock (Đúng 1 user được tạo).';
ELSE
    PRINT N'>>> [CC-EMAIL-01 FAIL]: Xuất hiện duplicate hoặc không tạo được user!';
PRINT N'------------------------------------------------------------';
GO
