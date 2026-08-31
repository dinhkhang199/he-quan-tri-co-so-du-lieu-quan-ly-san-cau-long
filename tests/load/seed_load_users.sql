/* ============================================================
   BadmintonCourtManagement — LOAD TEST: nạp N user thử tải
   File   : tests/load/seed_load_users.sql
   Mục đích: tạo N account CUSTOMER (mặc định 2000) để mô phỏng
            "2000 người đăng nhập + bấm đặt sân cùng lúc".
   Chạy   : sqlcmd -S ".\SQLEXPRESS" -E -f 65001 -i tests\load\seed_load_users.sql
            (phải chạy bằng quyền sysadmin — bcm_app bị DENY DML trực tiếp)
   Lưu ý  : KHÔNG thuộc bộ script contract database/00..15; đây là công cụ
            đo tải, không tham gia build/test chính thức.
   ============================================================ */

USE BadmintonCourtManagement;
GO

SET NOCOUNT ON;
GO

DECLARE @Count INT = 2000;              -- số user thử tải
DECLARE @Password NVARCHAR(200) = N'load123';

-- Chạy lại được: xoá dấu vết lần trước (theo thứ tự FK)
DELETE n FROM dbo.Notifications n
INNER JOIN dbo.Bookings b ON b.BookingId = n.BookingId
INNER JOIN dbo.Users u ON u.UserId = b.UserId
WHERE u.Username LIKE N'loadtest%';

DELETE a FROM dbo.ActivityLogs a
INNER JOIN dbo.Bookings b ON b.BookingId = a.BookingId
INNER JOIN dbo.Users u ON u.UserId = b.UserId
WHERE u.Username LIKE N'loadtest%';

DELETE n FROM dbo.Notifications n
INNER JOIN dbo.Users u ON u.UserId = n.UserId
WHERE u.Username LIKE N'loadtest%';

DELETE a FROM dbo.ActivityLogs a
INNER JOIN dbo.Users u ON u.UserId = a.UserId
WHERE u.Username LIKE N'loadtest%';

DELETE b FROM dbo.Bookings b
INNER JOIN dbo.Users u ON u.UserId = b.UserId
WHERE u.Username LIKE N'loadtest%';

DELETE FROM dbo.Users WHERE Username LIKE N'loadtest%';

-- Nạp mới: UserId xác định (F0000001-...) để dễ truy vết/cleanup
;WITH Nums AS
(
    SELECT TOP (@Count) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n
    FROM sys.all_objects a CROSS JOIN sys.all_objects b
)
INSERT INTO dbo.Users (UserId, Username, PasswordHash, PhoneNumber, Role, IsActive)
SELECT
    CONVERT(UNIQUEIDENTIFIER, N'F0000001-0000-0000-0000-' + RIGHT(N'000000000000' + CAST(n AS NVARCHAR(12)), 12)),
    N'loadtest' + RIGHT(N'000000' + CAST(n AS NVARCHAR(6)), 6),
    CONVERT(VARBINARY(64), HASHBYTES('SHA2_256', N'bcms|' + @Password)),
    N'079' + RIGHT(N'0000000' + CAST(n AS NVARCHAR(7)), 7),
    N'CUSTOMER',
    1
FROM Nums;

PRINT N'[LOAD] Đã tạo ' + CAST(@@ROWCOUNT AS NVARCHAR(10)) + N' user loadtestNNNNNN (password: load123).';
GO

SELECT COUNT(*) AS LoadTestUsers FROM dbo.Users WHERE Username LIKE N'loadtest%';
GO
