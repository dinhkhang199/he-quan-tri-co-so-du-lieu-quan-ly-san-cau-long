/* ============================================================
   BadmintonCourtManagement
   Script : 07_triggers.sql
   Mục đích: 6 Triggers theo contract v2.0 (section 6.4)
   Nguyên tắc: set-based, xử lý multi-row (TR-03)
   ============================================================ */

USE BadmintonCourtManagement;
GO

-- ------------------------------------------------------------
-- 1. trg_Bookings_AuditInsert : AFTER INSERT -> ghi audit cho từng dòng inserted
-- ------------------------------------------------------------
IF OBJECT_ID(N'dbo.trg_Bookings_AuditInsert', N'TR') IS NOT NULL
    DROP TRIGGER dbo.trg_Bookings_AuditInsert;
GO
CREATE TRIGGER dbo.trg_Bookings_AuditInsert
ON dbo.Bookings
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO dbo.ActivityLogs (UserId, BookingId, Action, OldStatus, NewStatus)
    SELECT i.UserId, i.BookingId, N'CREATE', NULL, i.Status
    FROM inserted i;
END
GO

-- ------------------------------------------------------------
-- 2. trg_Bookings_AuditStatus : AFTER UPDATE -> ghi old/new khi status đổi
-- ------------------------------------------------------------
IF OBJECT_ID(N'dbo.trg_Bookings_AuditStatus', N'TR') IS NOT NULL
    DROP TRIGGER dbo.trg_Bookings_AuditStatus;
GO
CREATE TRIGGER dbo.trg_Bookings_AuditStatus
ON dbo.Bookings
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO dbo.ActivityLogs (UserId, BookingId, Action, OldStatus, NewStatus)
    SELECT COALESCE(TRY_CONVERT(UNIQUEIDENTIFIER, SESSION_CONTEXT(N'UserId')), i.UserId), i.BookingId,
           CASE
               WHEN d.Status = N'PENDING'  AND i.Status = N'BOOKED'    THEN N'APPROVE'
               WHEN d.Status = N'PENDING'  AND i.Status = N'REJECTED'  THEN N'REJECT'
               WHEN i.Status = N'CANCELLED'                            THEN N'CANCEL'
               WHEN d.Status = N'BOOKED'   AND i.Status = N'COMPLETED' THEN N'COMPLETE'
               ELSE N'STATUS_CHANGE'
           END,
           d.Status, i.Status
    FROM inserted i
    INNER JOIN deleted d ON d.BookingId = i.BookingId
    WHERE d.Status <> i.Status;
END
GO

-- ------------------------------------------------------------
-- 3. trg_Bookings_NotifyInsert : AFTER INSERT -> thông báo booking mới cho chủ sân
-- ------------------------------------------------------------
IF OBJECT_ID(N'dbo.trg_Bookings_NotifyInsert', N'TR') IS NOT NULL
    DROP TRIGGER dbo.trg_Bookings_NotifyInsert;
GO
CREATE TRIGGER dbo.trg_Bookings_NotifyInsert
ON dbo.Bookings
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO dbo.Notifications (UserId, BookingId, Message)
    SELECT c.OwnerId, i.BookingId,
           N'Booking mới chờ duyệt #' + LOWER(CONVERT(NVARCHAR(36), i.BookingId)) +
           N' - sân ' + c.CourtName + N' (' + CONVERT(NVARCHAR(20), i.StartTime, 120) + N' → ' + CONVERT(NVARCHAR(20), i.EndTime, 120) + N')'
    FROM inserted i
    INNER JOIN dbo.Courts c ON c.CourtId = i.CourtId;
END
GO

-- ------------------------------------------------------------
-- 4. trg_Bookings_NotifyStatus : AFTER UPDATE -> thông báo cho Customer khi status đổi
-- ------------------------------------------------------------
IF OBJECT_ID(N'dbo.trg_Bookings_NotifyStatus', N'TR') IS NOT NULL
    DROP TRIGGER dbo.trg_Bookings_NotifyStatus;
GO
CREATE TRIGGER dbo.trg_Bookings_NotifyStatus
ON dbo.Bookings
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO dbo.Notifications (UserId, BookingId, Message)
    SELECT i.UserId, i.BookingId,
           N'Booking của bạn đổi trạng thái: ' + i.Status +
           N' (sân ' + c.CourtName + N', ' + CONVERT(NVARCHAR(20), i.StartTime, 120) + N' → ' + CONVERT(NVARCHAR(20), i.EndTime, 120) + N')'
    FROM inserted i
    INNER JOIN deleted d ON d.BookingId = i.BookingId
    INNER JOIN dbo.Courts c ON c.CourtId = i.CourtId
    WHERE d.Status <> i.Status;
END
GO

-- ------------------------------------------------------------
-- 5. trg_Bookings_ValidateState : AFTER UPDATE -> safety net state transition (contract 3.4)
--    Cho phép: PENDING->BOOKED/REJECTED/CANCELLED ; BOOKED->CANCELLED/COMPLETED
-- ------------------------------------------------------------
IF OBJECT_ID(N'dbo.trg_Bookings_ValidateState', N'TR') IS NOT NULL
    DROP TRIGGER dbo.trg_Bookings_ValidateState;
GO
CREATE TRIGGER dbo.trg_Bookings_ValidateState
ON dbo.Bookings
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    IF EXISTS
    (
        SELECT 1
        FROM inserted i
        INNER JOIN deleted d ON d.BookingId = i.BookingId
        WHERE d.Status <> i.Status
          AND NOT
          (
              (d.Status = N'PENDING' AND i.Status IN (N'BOOKED', N'REJECTED', N'CANCELLED'))
              OR (d.Status = N'BOOKED'  AND i.Status IN (N'COMPLETED', N'CANCELLED'))
          )
    )
        THROW 51000, N'Chuyển trạng thái booking không hợp lệ (bị trigger chặn).', 1;
END
GO

-- ------------------------------------------------------------
-- 6. trg_Bookings_PreventBookedOverlap : AFTER INSERT, UPDATE
--    Safety net chặn hai BOOKED overlap cùng Court; xử lý multi-row.
--    LƯU Ý: check đúng contract 3.3 - [Start, End), chỉ chạm biên là KHÔNG overlap.
-- ------------------------------------------------------------
IF OBJECT_ID(N'dbo.trg_Bookings_PreventBookedOverlap', N'TR') IS NOT NULL
    DROP TRIGGER dbo.trg_Bookings_PreventBookedOverlap;
GO
CREATE TRIGGER dbo.trg_Bookings_PreventBookedOverlap
ON dbo.Bookings
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    -- i.Status = BOOKED và tồn tại booking BOOKED khác cùng Court có giao nhau thực sự
    IF EXISTS
    (
        SELECT 1
        FROM inserted i
        INNER JOIN dbo.Bookings b
                ON b.CourtId = i.CourtId
               AND b.Status  = N'BOOKED'
               AND b.BookingId <> i.BookingId
               AND i.StartTime < b.EndTime   -- overlap thực sự: (i.Start < b.End) AND (b.Start < i.End)
               AND b.StartTime < i.EndTime
        WHERE i.Status = N'BOOKED'
    )
        THROW 51001, N'Không cho phép hai booking BOOKED overlap trên cùng sân (bị trigger chặn).', 1;
END
GO

PRINT N'[OK] 6 Triggers đã được tạo.';
