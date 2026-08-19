import type { ReactNode } from 'react';
import { Navigate } from 'react-router-dom';
import type { UserRole } from '../../shared/contract';
import { BpIcon } from '../components/BpIcon';
import { useAuth } from './AuthContext';

/** Role-based landing page after login (and where role-mismatched users are sent). */
export function roleHome(role: UserRole): string {
  return role === 'CUSTOMER' ? '/courts' : '/manager/dashboard';
}

/** Full-page loading while the initial /api/auth/me check is in flight. */
function FullPageLoading() {
  return (
    <div className="bp-gate" role="status">
      <BpIcon name="progress_activity" size={28} className="bp-spinner" />
      <span>Đang kiểm tra phiên đăng nhập...</span>
    </div>
  );
}

/**
 * UX-only guard: renders children only for an authenticated user whose role is
 * allowed. Backend Stored Procedures remain the security authority.
 */
export function RequireAuth({ roles, children }: { roles: UserRole[]; children: ReactNode }) {
  const { status, user } = useAuth();
  if (status === 'loading') return <FullPageLoading />;
  if (status === 'guest' || !user) return <Navigate to="/login" replace />;
  if (!roles.includes(user.role)) return <Navigate to={roleHome(user.role)} replace />;
  return <>{children}</>;
}

/** Guard for /login: an already-authenticated user is sent to their role home. */
export function GuestOnly({ children }: { children: ReactNode }) {
  const { status, user } = useAuth();
  if (status === 'loading') return <FullPageLoading />;
  if (status === 'authenticated' && user) return <Navigate to={roleHome(user.role)} replace />;
  return <>{children}</>;
}