/**
 * Shared contract constants mirroring the Phase 1 DB contract.
 * These are NOT business logic; they are the typed contract surface shared
 * between server and (later) UI. Values must stay in sync with 06_procedures.sql
 * / 07_triggers.sql / 05_views.sql without inventing new states or roles.
 */

export const BOOKING_STATUS = ['PENDING', 'BOOKED', 'COMPLETED', 'CANCELLED', 'REJECTED'] as const;
export type BookingStatus = (typeof BOOKING_STATUS)[number];

export const USER_ROLES = ['MANAGER', 'COURT_MANAGER', 'CUSTOMER'] as const;
/** GUEST is behavioral only; there is no privileged GUEST role in the DB. */
export type UserRole = (typeof USER_ROLES)[number];

export const SURFACE_TYPES = ['STANDARD', 'VIP'] as const;
export type SurfaceType = (typeof SURFACE_TYPES)[number];

export const SIZE_TYPES = ['SINGLE', 'DOUBLE'] as const;
export type SizeType = (typeof SIZE_TYPES)[number];

/** Operating hours are enforced by the DB; these constrain the UI pickers only. */
export const OPERATING_START = '06:00';
export const OPERATING_END = '22:00';
export const MIN_DURATION_MINUTES = 60;
export const MAX_DURATION_MINUTES = 180;
export const TIME_STEP_MINUTES = 30;

export const CONTRACT_STORED_PROCEDURES = [
  'sp_Login',
  'sp_BookCourt',
  'sp_ApproveBooking',
  'sp_RejectBooking',
  'sp_CancelBooking',
  'sp_CompleteBooking',
  'sp_CreateCourt',
  'sp_UpdateCourt',
  'sp_DeactivateCourt',
  'sp_GetAvailableCourts',
  'sp_GetMyBookings',
  'sp_GetNotifications',
  'sp_MarkNotificationRead',
  'sp_GetDashboard',
] as const;

export const CONTRACT_VIEWS = [
  'vw_AvailableCourts',
  'vw_BookingHistory',
  'vw_AdminDashboard',
  'vw_AllBookings',
] as const;