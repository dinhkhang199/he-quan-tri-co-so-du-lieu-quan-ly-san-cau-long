/* ============================================================
   BadmintonCourtManagement
   Script : 04_functions.sql
   Mục đích: Các Function theo contract v2.0 (FN-01..FN-04)
   - fn_CalculateBookingCost : tính chi phí theo thời lượng + giá Court
   - fn_IsCourtAvailable     : kiểm tra BOOKED overlap (chỉ để kiểm tra/hiển thị)
   ============================================================ */

USE BadmintonCourtManagement;
GO

-- ------------------------------------------------------------
-- 1. fn_CalculateBookingCost
--    Cost = floor(DurationMinutes/180)*PricePerThreeHours + (DurationMinutes%180)*PricePerHour/60
--    Ví dụ 3,5h = 270.000 + 50.000 = 320.000 (3h = 270k, 30ph lẻ = 50k)
-- ------------------------------------------------------------
IF OBJECT_ID(N'dbo.fn_CalculateBookingCost', N'FN') IS NOT NULL
    DROP FUNCTION dbo.fn_CalculateBookingCost;
GO

CREATE FUNCTION dbo.fn_CalculateBookingCost
(
    @CourtId   UNIQUEIDENTIFIER,
    @StartTime DATETIME2(0),
    @EndTime   DATETIME2(0)
)
RETURNS DECIMAL(12,0)
AS
BEGIN
    DECLARE @PricePerHour       DECIMAL(12,0);
    DECLARE @PricePerThreeHours DECIMAL(12,0);

    SELECT @PricePerHour = PricePerHour, @PricePerThreeHours = PricePerThreeHours
    FROM dbo.Courts
    WHERE CourtId = @CourtId;

    IF @PricePerHour IS NULL
        RETURN NULL; -- sân không tồn tại (caller phải tự validate trước khi gọi)

    DECLARE @Minutes INT = DATEDIFF(MINUTE, @StartTime, @EndTime);

    RETURN (@Minutes / 180) * @PricePerThreeHours + ((@Minutes % 180) * @PricePerHour) / 60;
END
GO

-- ------------------------------------------------------------
-- 2. fn_IsCourtAvailable
--    Trả 1 nếu KHÔNG có BOOKED overlap trong [Start, End)
--    LƯU Ý (contract 6.2): chỉ phục vụ kiểm tra/hiển thị, KHÔNG thay thế
--    transaction + lock trong sp_BookCourt / sp_ApproveBooking.
-- ------------------------------------------------------------
IF OBJECT_ID(N'dbo.fn_IsCourtAvailable', N'FN') IS NOT NULL
    DROP FUNCTION dbo.fn_IsCourtAvailable;
GO

CREATE FUNCTION dbo.fn_IsCourtAvailable
(
    @CourtId   UNIQUEIDENTIFIER,
    @StartTime DATETIME2(0),
    @EndTime   DATETIME2(0)
)
RETURNS BIT
AS
BEGIN
    IF EXISTS
    (
        SELECT 1
        FROM dbo.Bookings
        WHERE CourtId = @CourtId
          AND Status  = N'BOOKED'
          AND StartTime < @EndTime
          AND EndTime   > @StartTime
    )
        RETURN 0;

    RETURN 1;
END
GO

PRINT N'[OK] 2 Functions đã được tạo.';