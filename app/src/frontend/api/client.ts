import type {
  AuthUser,
  BookingCreateResponse,
  CancelBookingResponse,
  CostEstimateResponse,
  CourtSearchResponse,
  ManagerBookingAction,
  ManagerBookingsResponse,
  ManagerCourtCreateResponse,
  ManagerCourtInput,
  ManagerCourtMutationResponse,
  ManagerCourtsResponse,
  ManagerDashboardResponse,
  ManagerMutationResponse,
  MarkNotificationReadResponse,
  MyBookingsResponse,
  NotificationsResponse,
} from '../../shared/types';

/** Server never authenticates on the module itself; it checks the web session cookie. */
const DEFAULT_HEADERS: Record<string, string> = { 'Content-Type': 'application/json' };

interface ApiErrorBody {
  error?: { code?: number | null; message?: string };
  code?: number | null;
  message?: string;
}

/** Typed fetch error with the safe server message (no SQL internals/credentials). */
export class ApiError extends Error {
  status: number;
  code: number | null;

  constructor(status: number, code: number | null, message: string) {
    super(message);
    this.name = 'ApiError';
    this.status = status;
    this.code = code;
  }
}

async function request<T>(path: string, options: RequestInit = {}): Promise<T> {
  const res = await fetch(path, { credentials: 'same-origin', headers: DEFAULT_HEADERS, ...options });
  if (res.status === 204) return undefined as T;
  let body: unknown = null;
  try {
    body = await res.json();
  } catch {
    body = null;
  }
  if (!res.ok) {
    const b = body as ApiErrorBody | null;
    const err = b?.error ?? b;
    throw new ApiError(res.status, err?.code ?? null, err?.message ?? 'Có lỗi từ hệ thống. Vui lòng thử lại.');
  }
  return body as T;
}

export function loginRequest(username: string, password: string): Promise<{ user: AuthUser }> {
  return request<{ user: AuthUser }>('/api/auth/login', {
    method: 'POST',
    body: JSON.stringify({ username, password }),
  });
}

/** Returns the authenticated user or throws ApiError(401) when the session is gone. */
export function meRequest(): Promise<{ user: AuthUser }> {
  return request<{ user: AuthUser }>('/api/auth/me');
}

/** Best-effort: the local auth state is cleared whether or not the server call succeeds. */
export async function logoutRequest(): Promise<void> {
  try {
    await request<void>('/api/auth/logout', { method: 'POST' });
  } catch {
    // Idempotent by design; nothing to do here.
  }
}

/**
 * Public court availability search (guest-safe, no session required).
 * Times are local wall-clock strings "YYYY-MM-DDTHH:MM:00" (no timezone).
 */
export function searchCourtsRequest(params: {
  startTime: string;
  endTime: string;
  courtId?: string;
}): Promise<CourtSearchResponse> {
  const qs = new URLSearchParams({ startTime: params.startTime, endTime: params.endTime });
  if (params.courtId) qs.set('courtId', params.courtId);
  return request<CourtSearchResponse>(`/api/courts/available?${qs.toString()}`);
}

/**
 * Create a CUSTOMER booking by calling dbo.sp_BookCourt on the authenticated
 * SQL session connection. The server decides authorization; the request carries
 * only { courtId, startTime, endTime }. Times are local wall-clock strings
 * ("YYYY-MM-DDTHH:MM:00", no timezone).
 */
export function bookCourtRequest(params: {
  courtId: string;
  startTime: string;
  endTime: string;
}): Promise<BookingCreateResponse> {
  return request<BookingCreateResponse>('/api/bookings', {
    method: 'POST',
    body: JSON.stringify(params),
  });
}

/**
 * Pre-confirm "Chi phí dự kiến" for the booking detail screen. Authenticated
 * CUSTOMER flow: the cost is computed by dbo.fn_CalculateBookingCost on the
 * authenticated SQL session connection — no cost formula lives in the frontend.
 * `totalCost` is null when the court does not exist.
 */
export function costEstimateRequest(params: {
  courtId: string;
  startTime: string;
  endTime: string;
}): Promise<CostEstimateResponse> {
  const qs = new URLSearchParams({ courtId: params.courtId, startTime: params.startTime, endTime: params.endTime });
  return request<CostEstimateResponse>(`/api/bookings/estimate?${qs.toString()}`);
}

/**
 * Authenticated CUSTOMER booking history. Rows come from dbo.sp_GetMyBookings on
 * the authenticated SQL session; the server derives the actor from the session,
 * never from the client. Times serialize as ISO strings whose wall-clock digits
 * match the local court time (slice them for display — do not re-interpret).
 */
export function getMyBookingsRequest(): Promise<MyBookingsResponse> {
  return request<MyBookingsResponse>('/api/bookings/mine');
}

/**
 * Cancel one of the authenticated customer's own bookings through
 * dbo.sp_CancelBooking. The request carries only the booking id; the server and
 * the stored procedure decide ownership/state/deadline. The UI must refresh
 * history from the DB afterwards — this response is only the success signal.
 */
export function cancelBookingRequest(bookingId: string): Promise<CancelBookingResponse> {
  return request<CancelBookingResponse>(`/api/bookings/${encodeURIComponent(bookingId)}/cancel`, { method: 'POST' });
}

/**
 * Authenticated MANAGER/COURT_MANAGER booking list (Phase 2.6). Rows come from
 * dbo.vw_AllBookings on the authenticated SQL session; scope is applied IN SQL
 * by SESSION_CONTEXT (MANAGER sees all rows, COURT_MANAGER only OwnerId rows),
 * so the browser never sees another actor's bookings.
 */
export function getManagerBookingsRequest(): Promise<ManagerBookingsResponse> {
  return request<ManagerBookingsResponse>('/api/manager/bookings');
}

/**
 * Run one manager booking mutation (approve/reject/cancel/complete) through the
 * matching contract Stored Procedure. The request carries ONLY the booking id;
 * the server, SESSION_CONTEXT and SP decide role/ownership/state. The UI must
 * refetch the manager list from the DB afterwards — this response is only the
 * success signal.
 */
export function managerActionRequest(
  action: ManagerBookingAction,
  bookingId: string,
): Promise<ManagerMutationResponse> {
  return request<ManagerMutationResponse>(`/api/manager/bookings/${encodeURIComponent(bookingId)}/${action}`, {
    method: 'POST',
  });
}

/**
 * Authenticated MANAGER/COURT_MANAGER court list (Phase 2.7). Rows come from
 * dbo.Courts on the authenticated SQL session; scope is applied IN SQL by
 * SESSION_CONTEXT (MANAGER sees all courts including inactive, COURT_MANAGER
 * only OwnerId rows), so the browser never sees another actor's courts.
 */
export function getManagerCourtsRequest(): Promise<ManagerCourtsResponse> {
  return request<ManagerCourtsResponse>('/api/manager/courts');
}

/**
 * Create a court through dbo.sp_CreateCourt. The request carries ONLY editable
 * court fields — ownership derives from the authenticated SQL session inside
 * the Stored Procedure. The UI must refetch the court list from the DB
 * afterwards; this response is only the success signal.
 */
export function createCourtRequest(input: ManagerCourtInput): Promise<ManagerCourtCreateResponse> {
  return request<ManagerCourtCreateResponse>('/api/manager/courts', {
    method: 'POST',
    body: JSON.stringify(input),
  });
}

/**
 * Update a court through dbo.sp_UpdateCourt. The Stored Procedure re-validates
 * role, SESSION_CONTEXT and (for COURT_MANAGER) ownership under lock. The UI
 * must refetch the court list from the DB afterwards.
 */
export function updateCourtRequest(courtId: string, input: ManagerCourtInput): Promise<ManagerCourtMutationResponse> {
  return request<ManagerCourtMutationResponse>(`/api/manager/courts/${encodeURIComponent(courtId)}`, {
    method: 'PUT',
    body: JSON.stringify(input),
  });
}

/**
 * Soft-deactivate a court through dbo.sp_DeactivateCourt (IsActive = 0). There
 * is no reactivation in this phase. The UI must refetch the court list from the
 * DB afterwards — the deactivated court returns with IsActive = false.
 */
export function deactivateCourtRequest(courtId: string): Promise<ManagerCourtMutationResponse> {
  return request<ManagerCourtMutationResponse>(
    `/api/manager/courts/${encodeURIComponent(courtId)}/deactivate`,
    { method: 'POST' },
  );
}

/**
 * Authenticated notification list (CUSTOMER / MANAGER / COURT_MANAGER). Rows
 * come from dbo.sp_GetNotifications on the authenticated SQL session; the SP
 * derives the actor from SESSION_CONTEXT, so the browser only ever receives
 * the authenticated user's own notifications. CreatedAt carries local
 * wall-clock digits — display by string-slicing, do not re-interpret via Date.
 */
export function getNotificationsRequest(): Promise<NotificationsResponse> {
  return request<NotificationsResponse>('/api/notifications');
}

/**
 * Mark one notification read through dbo.sp_MarkNotificationRead. The request
 * carries ONLY the notification id; ownership is enforced by the Stored
 * Procedure against SESSION_CONTEXT (a foreign/unknown id matches nothing and
 * is rejected). The UI must refetch GET /api/notifications afterwards — this
 * response is only the success signal.
 */
export function markNotificationReadRequest(notificationId: string): Promise<MarkNotificationReadResponse> {
  return request<MarkNotificationReadResponse>(
    `/api/notifications/${encodeURIComponent(notificationId)}/read`,
    { method: 'POST' },
  );
}

/**
 * Authenticated MANAGER/COURT_MANAGER dashboard (Phase 2.9). Rows come from
 * dbo.sp_GetDashboard on the authenticated SQL session; scope is applied INSIDE
 * SQL Server (MANAGER system-wide, COURT_MANAGER only OwnerId courts), so the
 * browser only ever receives the actor's correctly scoped aggregates.
 */
export function getManagerDashboardRequest(): Promise<ManagerDashboardResponse> {
  return request<ManagerDashboardResponse>('/api/manager/dashboard');
}