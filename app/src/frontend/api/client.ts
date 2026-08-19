import type {
  AuthUser,
  BookingCreateResponse,
  CancelBookingResponse,
  CostEstimateResponse,
  CourtSearchResponse,
  MyBookingsResponse,
} from '../../shared/types';

/** Server never authenticates on the module itself; it checks the web session cookie. */
const DEFAULT_HEADERS: Record<string, string> = { 'Content-Type': 'application/json' };

interface ApiErrorBody {
  error?: { code?: number | null; message?: string };
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
    const err = (body as ApiErrorBody | null)?.error;
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