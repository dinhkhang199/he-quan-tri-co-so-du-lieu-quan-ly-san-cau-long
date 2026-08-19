import type { AuthUser } from '../../shared/types';

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