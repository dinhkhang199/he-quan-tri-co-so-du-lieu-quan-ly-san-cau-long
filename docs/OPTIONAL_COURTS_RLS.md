# OPTIONAL — siết quyền đọc `dbo.Courts` bằng Row-Level Security

Không áp dụng mặc định. Contract §14 khóa đúng **5 table / 4 view / 2 function /
14 procedure / 6 trigger**. Bật RLS dưới đây sẽ thêm một inline table-valued
function và một security policy, nên RG-43/ST-01…ST-05 sẽ cố ý báo lệch `2 function`.

Hiện tại `bcm_app_role` vẫn có `SELECT` chỉ-đọc trên `dbo.Courts` để màn quản lý
liệt kê được cả sân active lẫn inactive. Application query tự lọc theo
`SESSION_CONTEXT`, nhưng người giữ chuỗi kết nối có thể tự gửi một câu SELECT
khác. DML vẫn bị DENY và mọi thay đổi vẫn phải qua stored procedure.

Chỉ bật sau khi giảng viên đồng ý nới số object trong §14.

## Bật

```sql
USE BadmintonCourtManagement;
GO

CREATE FUNCTION dbo.fn_CourtsRlsPredicate(@OwnerId UNIQUEIDENTIFIER)
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN
(
    SELECT 1 AS allowed
    WHERE
        USER_NAME() = N'dbo'
        OR CONVERT(NVARCHAR(20), SESSION_CONTEXT(N'Role')) = N'MANAGER'
        OR (
            CONVERT(NVARCHAR(20), SESSION_CONTEXT(N'Role')) = N'COURT_MANAGER'
            AND @OwnerId = TRY_CONVERT(UNIQUEIDENTIFIER, SESSION_CONTEXT(N'UserId'))
        )
);
GO

CREATE SECURITY POLICY dbo.CourtsRlsPolicy
ADD FILTER PREDICATE dbo.fn_CourtsRlsPredicate(OwnerId) ON dbo.Courts
WITH (STATE = ON, SCHEMABINDING = ON);
GO
```

`dbo` được miễn để các procedure `WITH EXECUTE AS OWNER`, seed, test và
backup/restore giữ nguyên hành vi. `bcm_app` không thể tự đặt SESSION_CONTEXT vì
`08_security.sql` DENY `sys.sp_set_session_context` ở database `master`.

## Tắt và trả về đúng object count của contract

```sql
USE BadmintonCourtManagement;
GO
ALTER SECURITY POLICY dbo.CourtsRlsPolicy WITH (STATE = OFF);
DROP SECURITY POLICY dbo.CourtsRlsPolicy;
DROP FUNCTION dbo.fn_CourtsRlsPredicate;
GO
```

Sau mỗi lần bật/tắt phải chạy lại functional, regression, concurrency và static
checks; không dùng tài liệu này thay cho bằng chứng thực thi.
