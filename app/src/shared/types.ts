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

/**
 * GET /api/notifications response (authenticated CUSTOMER / MANAGER /
 * COURT_MANAGER). Rows come verbatim from dbo.sp_GetNotifications on the
 * authenticated session; the actor is derived from SESSION_CONTEXT by the SP,
 * never from the browser. CreatedAt serializes as an ISO string carrying the
 * local wall-clock digits — string-slice for display, do not re-interpret.
 */
export interface NotificationsResponse {
  notifications: Notification[];
  count: number;
}

/**
 * POST /api/notifications/:notificationId/read success response. The read ran
 * through dbo.sp_MarkNotificationRead, which enforces ownership by UPDATEing
 * only rows WHERE UserId = SESSION_CONTEXT actor. The UX then refetches
 * GET /api/notifications — this is only the success signal.
 */
export interface MarkNotificationReadResponse {
  notificationId: string;
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

/**
 * GET /api/bookings/mine response (authenticated CUSTOMER history).
 * Rows come verbatim from dbo.sp_GetMyBookings; only the actor's own bookings
 * are returned. StartTime/EndTime/CreatedAt serialize as ISO strings whose wall
 * clock digits match the local court time (the SQL DATETIME2 is stored as the
 * local wall clock; string-slice it for display — do not re-interpret via Date).
 */
export interface MyBookingsResponse {
  bookings: MyBooking[];
  count: number;
}

/**
 * POST /api/bookings/:bookingId/cancel success response. The cancel ran through
 * dbo.sp_CancelBooking; the UX then refreshes history from dbo.sp_GetMyBookings
 * so the UI never fabricates the resulting state.
 */
export interface CancelBookingResponse {
  bookingId: string;
  status: 'CANCELLED';
}

/**
 * vw_AllBookings row as returned by the authenticated manager booking-list
 * endpoint (05_views.sql). Exact view columns; StatusLabel is the view's CASE
 * label. StartTime/EndTime/CreatedAt serialize as ISO strings carrying the
 * local wall-clock digits — string-slice for display, do not re-interpret.
 */
export interface ManagerBooking {
  BookingId: string;
  UserId: string;
  CustomerUsername: string;
  CustomerPhone: string;
  CourtId: string;
  CourtName: string;
  SurfaceType: string;
  SizeType: string;
  OwnerId: string;
  PricePerHour: number;
  StartTime: Date;
  EndTime: Date;
  Status: BookingStatus;
  StatusLabel: string;
  TotalCost: number;
  CreatedAt: Date;
  UpdatedAt: Date;
}

/**
 * GET /api/manager/bookings response. Rows come verbatim from
 * dbo.vw_AllBookings on the authenticated session connection, scoped in SQL by
 * SESSION_CONTEXT (MANAGER sees all; COURT_MANAGER sees only OwnerId rows).
 */
export interface ManagerBookingsResponse {
  bookings: ManagerBooking[];
  count: number;
}

/**
 * POST /api/manager/bookings/:bookingId/{approve|reject|cancel|complete}
 * success response. The mutation ran through the matching contract SP; the UX
 * then refetches the manager list from the DB so it never fabricates the
 * resulting state.
 */
export interface ManagerMutationResponse {
  bookingId: string;
  status: 'BOOKED' | 'REJECTED' | 'CANCELLED' | 'COMPLETED';
}

/** Manager booking mutations backed by the four contract Stored Procedures. */
export type ManagerBookingAction = 'approve' | 'reject' | 'cancel' | 'complete';

/**
 * dbo.Courts row as returned by the authenticated manager court-list endpoint
 * (01_tables_constraints.sql). Exact table columns; COURT_MANAGER rows are
 * scoped to OwnerId = SESSION_CONTEXT('UserId') BEFORE they leave SQL Server.
 * CreatedAt/UpdatedAt serialize as ISO strings carrying the local wall-clock
 * digits — string-slice for display, do not re-interpret.
 */
export interface ManagerCourt {
  CourtId: string;
  CourtName: string;
  Address: string;
  SurfaceType: string;
  SizeType: string;
  PricePerHour: number;
  PricePerThreeHours: number;
  ImageUrl: string | null;
  OwnerId: string;
  IsActive: boolean;
  CreatedAt: Date;
  UpdatedAt: Date;
}

/**
 * GET /api/manager/courts response. Rows come verbatim from dbo.Courts on the
 * authenticated session connection, scoped IN SQL by SESSION_CONTEXT
 * (MANAGER sees all including inactive; COURT_MANAGER sees only OwnerId rows).
 */
export interface ManagerCourtsResponse {
  courts: ManagerCourt[];
  count: number;
}

/**
 * Editable court fields accepted from the browser for create/update. OwnerId is
 * deliberately NOT here — the Stored Procedures derive ownership from the
 * authenticated session (sp_CreateCourt defaults @OwnerId to the session user;
 * COURT_MANAGER is forced to self). Prices are in VND (DB CHECK: > 0).
 */
export interface ManagerCourtInput {
  courtName: string;
  address: string;
  surfaceType: string;
  sizeType: string;
  pricePerHour: number;
  pricePerThreeHours: number;
  imageUrl: string | null;
}

/**
 * POST /api/manager/courts success response (sp_CreateCourt output param).
 * The UX then refetches GET /api/manager/courts from the DB.
 */
export interface ManagerCourtCreateResponse {
  courtId: string;
}

/**
 * PUT/DELETE-style court mutation success responses (sp_UpdateCourt /
 * sp_DeactivateCourt). The UX then refetches GET /api/manager/courts — these
 * are only success signals.
 */
export interface ManagerCourtMutationResponse {
  courtId: string;
}