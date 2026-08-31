/* ============================================================
   BadmintonCourtManagement — Concurrency Test Suite
   Script : register_email_session_B.sql (Window B)
   Kịch bản : CC-EMAIL-01 — Đăng ký tài khoản song song cùng Email
   ============================================================ */

USE BadmintonCourtManagement;
GO
SET NOCOUNT ON;
SET XACT_ABORT OFF;
GO

PRINT N'>>> Window B: Bắt đầu tham gia kịch bản đăng ký song song (CC-EMAIL-01)...';

-- Chờ Window A tạo bảng cờ
DECLARE @w0 INT = 0;
WHILE OBJECT_ID('dbo._CCTestSync', 'U') IS NULL AND @w0 < 30
BEGIN
    WAITFOR DELAY '00:00:00.500';
    SET @w0 = @w0 + 1;
END;

IF OBJECT_ID('dbo._CCTestSync', 'U') IS NULL
BEGIN
    PRINT N'[FAIL] Timeout: Bảng _CCTestSync chưa được tạo bởi Window A!';
    RETURN;
END;

INSERT INTO dbo._CCTestSync (Flag) VALUES ('CC_EMAIL_B_READY');
GO

-- Chờ Window A bắt đầu
DECLARE @w INT = 0;
WHILE NOT EXISTS (SELECT 1 FROM dbo._CCTestSync WHERE Flag = 'CC_EMAIL_A_READY') AND @w < 30
BEGIN
    WAITFOR DELAY '00:00:00.500';
    SET @w = @w + 1;
END;

PRINT N'>>> Window B: Bắt đầu gọi sp_Register (User B)...';

DECLARE @Email NVARCHAR(254) = N'concur_race@badmintonpro.local';
DECLARE @ErrB INT = 0;
DECLARE @MsgB NVARCHAR(400) = N'';

BEGIN TRY
    EXEC dbo.sp_Register
        @Username = N'concur_race_user_B',
        @Password = N'PassB_Strong123',
        @PhoneNumber = N'0977000022',
        @Email = @Email;
    PRINT N'>>> Window B: sp_Register THÀNH CÔNG.';
END TRY
BEGIN CATCH
    SET @ErrB = ERROR_NUMBER();
    SET @MsgB = ERROR_MESSAGE();
    PRINT N'>>> Window B: sp_Register BỊ CHẶN. Mã lỗi: ' + CAST(@ErrB AS NVARCHAR(10)) + N' - ' + @MsgB;
END CATCH;

INSERT INTO dbo._CCTestSync (Flag) VALUES ('CC_EMAIL_B_DONE');
GO

-- Chờ Window A hoàn tất
DECLARE @w2 INT = 0;
WHILE NOT EXISTS (SELECT 1 FROM dbo._CCTestSync WHERE Flag = 'CC_EMAIL_A_DONE') AND @w2 < 30
BEGIN
    WAITFOR DELAY '00:00:00.500';
    SET @w2 = @w2 + 1;
END;

-- Kiểm tra kết quả tổng thể
DECLARE @Email NVARCHAR(254) = N'concur_race@badmintonpro.local';
DECLARE @FinalCount INT = (SELECT COUNT(*) FROM dbo.Users WHERE Email = @Email);

PRINT N'------------------------------------------------------------';
PRINT N'>>> KẾT QUẢ ĐỒNG THỜI CC-EMAIL-01 (Window B):';
PRINT N'    Tổng số user mang email "' + @Email + N'": ' + CAST(@FinalCount AS NVARCHAR(10));
IF @FinalCount = 1
    PRINT N'>>> [CC-EMAIL-01 PASS]: Đăng ký đồng thời được serialize an toàn bằng sp_getapplock.';
ELSE
    PRINT N'>>> [CC-EMAIL-01 FAIL]: Xuất hiện duplicate hoặc không tạo được user!';
PRINT N'------------------------------------------------------------';
GO
