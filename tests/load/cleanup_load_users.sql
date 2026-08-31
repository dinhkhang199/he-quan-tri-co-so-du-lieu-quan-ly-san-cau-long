/* ============================================================
   BadmintonCourtManagement — LOAD TEST: dọn dẹp sau khi đo tải
   File   : tests/load/cleanup_load_users.sql
   Chạy   : sqlcmd -S ".\SQLEXPRESS" -E -f 65001 -i tests\load\cleanup_load_users.sql
   Tác dụng: xoá toàn bộ booking/notification/audit/user do load test sinh ra,
            đỆ DỮ LIỆU SEED CHUẨN (7 users / 6 courts / 15 bookings) trở lại đúng.
   ============================================================ */

USE BadmintonCourtManagement;
GO

SET NOCOUNT ON;
GO

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
GO

SELECT
    (SELECT COUNT(*) FROM dbo.Users)         AS Users,
    (SELECT COUNT(*) FROM dbo.Courts)        AS Courts,
    (SELECT COUNT(*) FROM dbo.Bookings)      AS Bookings,
    (SELECT COUNT(*) FROM dbo.ActivityLogs)  AS ActivityLogs,
    (SELECT COUNT(*) FROM dbo.Notifications) AS Notifications;
PRINT N'[LOAD] Cleanup xong. Kỳ vọng: Users=7, Courts=6, Bookings=15, ActivityLogs=3, Notifications=2.';
GO
