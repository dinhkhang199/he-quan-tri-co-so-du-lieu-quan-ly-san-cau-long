/**
 * Typed DTOs mirroring the result tuples returned by the Phase 1 stored procedures
 * and views (06_procedures.sql / 05_views.sql). Shared between the data-access
 * layer and (later) UI. No business logic lives here.
 */

import type { BookingStatus, SizeType, SurfaceType, UserRole } from './contract.js';

/** sp_Login result row (single user). */
export interface LoginResult {
  UserId: string;
  Username: string;
  Role: UserRole;
  IsActive: boolean;
  LastLogin: Date | null;
}

/**
 * Safe authenticated user exposed by the auth API and stored in the Express
 * session. `lastLogin` is the ISO-8601 wire format (the raw SQL value is a
 * datetime2, which serializes to a string across HTTP/session storage).
 */
export interface AuthUser {
  userId: string;
  username: string;
  role: UserRole;
  isActive: boolean;
  lastLogin: string | null;
}

/** sp_GetAvailableCourts row (exact columns returned by the procedure). */
export interface AvailableCourt {
  CourtId: string;
  CourtName: string;
  Address: string;
  SurfaceType: SurfaceType;
  SizeType: SizeType;
  PricePerHour: number;
  PricePerThreeHours: number;
  IsAvailable: boolean;
}

/**
 * GET /api/courts/available response.
 * Times are local wall-clock strings ("YYYY-MM-DDTHH:MM:SS", no timezone),
 * the exact values passed to dbo.sp_GetAvailableCourts as DATETIME2(0).
 */
export interface CourtSearchResponse {
  courts: AvailableCourt[];
  count: number;
  window: {
    startTime: string;
    endTime: string;
    courtId: string | null;
  };
}

/** sp_GetMyBookings row. */
export interface MyBooking {
  BookingId: string;
  CourtId: string;
  CourtName: string;
  CourtAddress: string;
  StartTime: Date;
  EndTime: Date;
  Status: BookingStatus;
  TotalCost: number;
  CreatedAt: Date;
}

/** sp_GetNotifications row. */
export interface Notification {
  NotificationId: string;
  UserId: string;
  BookingId: string | null;
  Message: string;
  IsRead: boolean;
  CreatedAt: Date;
}

/** sp_GetDashboard first result-set (overview). */
export interface DashboardOverview {
  PendingCount: number;
  BookedCount: number;
  TheoreticalRevenue: number;
  ActiveUsers: number;
}

/** sp_GetDashboard second result-set (daily theoretical revenue). */
export interface DashboardDailyRevenue {
  Date: Date;
  DailyRevenue: number;
}

/** sp_GetDashboard third result-set (top courts). */
export interface DashboardTopCourt {
  CourtName: string;
  BookingCount: number;
  Revenue: number;
}

/** sp_BookCourt output parameters. */
export interface BookCourtOutput {
  BookingId: string;
  TotalCost: number;
}

/**
 * Booking echoed back to the client after a successful creation.
 * Times are local wall-clock strings ("YYYY-MM-DDTHH:MM:SS", no timezone),
 * the exact values sent to dbo.sp_BookCourt as DATETIME2(0). TotalCost is the
 * value computed by SQL (fn_CalculateBookingCost inside the procedure).
 */
export interface BookingResult {
  BookingId: string;
  CourtId: string;
  StartTime: string;
  EndTime: string;
  Status: BookingStatus;
  TotalCost: number;
}

/** POST /api/bookings response. */
export interface BookingCreateResponse {
  booking: BookingResult;
}

/**
 * GET /api/bookings/estimate response (pre-confirm "Chi phí dự kiến",
 * authenticated CUSTOMER flow). The cost is computed by the DB
 * (dbo.fn_CalculateBookingCost); the app holds no cost formula. `totalCost` is
 * null when the court does not exist.
 */
export interface CostEstimateResponse {
  totalCost: number | null;
  courtId: string;
  startTime: string;
  endTime: string;
}

/** sp_CreateCourt output parameter. */
export interface CreateCourtOutput {
  CourtId: string;
}