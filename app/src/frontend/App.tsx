import { Routes, Route, Navigate, NavLink } from 'react-router-dom';
import type { UserRole } from '../shared/contract';
import { Card } from './components/Card';
import { EmptyState } from './components/EmptyState';
import { Button } from './components/Button';
import { LoginPage } from './pages/LoginPage';
import { RegisterPage } from './pages/RegisterPage';
import { ForgotPasswordPage } from './pages/ForgotPasswordPage';
import { CourtsPage } from './pages/CourtsPage';
import { BookingDetailPage } from './pages/BookingDetailPage';
import { MyBookingsPage } from './pages/MyBookingsPage';
import { NotificationsPage } from './pages/NotificationsPage';
import { ManagerDashboardPage } from './pages/manager/ManagerDashboardPage';
import { ManagerBookingsPage } from './pages/manager/ManagerBookingsPage';
import { ManagerCourtsPage } from './pages/manager/ManagerCourtsPage';
import { ManagerNotificationsPage } from './pages/manager/ManagerNotificationsPage';
import { GuestShell } from './shells/GuestShell';
import { CustomerShell } from './shells/CustomerShell';
import { ManagerShell } from './shells/ManagerShell';
import { GuestOnly, RequireAuth } from './auth/guards';
import { useAuth } from './auth/AuthContext';

type ManagerRole = Extract<UserRole, 'MANAGER' | 'COURT_MANAGER'>;

/**
 * Public /courts keeps the guest visual language; an authenticated CUSTOMER
 * gets the customer shell so their navigation (history/notifications) stays
 * available. Backend remains the security authority.
 */
function CourtsShell() {
  const { status, user } = useAuth();
  if (status === 'authenticated' && user?.role === 'CUSTOMER') return <CustomerShell />;
  return <GuestShell />;
}

export function App() {
  const { user } = useAuth();
  const managerRole: ManagerRole = user?.role === 'COURT_MANAGER' ? 'COURT_MANAGER' : 'MANAGER';

  return (
    <Routes>
      {/* "/" has no product screen; redirect to the approved public route. */}
      <Route path="/" element={<Navigate to="/courts" replace />} />

      {/* Public */}
      <Route path="/login" element={<GuestOnly><LoginPage /></GuestOnly>} />
      <Route path="/register" element={<GuestOnly><RegisterPage /></GuestOnly>} />
      <Route path="/forgot-password" element={<GuestOnly><ForgotPasswordPage /></GuestOnly>} />
      <Route path="/courts" element={<CourtsShell />}>
        <Route index element={<CourtsPage />} />
      </Route>

      {/* Customer (RequireAuth UX guard; DB remains authoritative) */}
      <Route path="/booking/:courtId" element={<RequireAuth roles={['CUSTOMER']}><CustomerShell /></RequireAuth>}>
        <Route index element={<BookingDetailPage />} />
      </Route>
      <Route path="/my-bookings" element={<RequireAuth roles={['CUSTOMER']}><CustomerShell /></RequireAuth>}>
        <Route index element={<MyBookingsPage />} />
      </Route>
      <Route path="/notifications" element={<RequireAuth roles={['CUSTOMER']}><CustomerShell /></RequireAuth>}>
        <Route index element={<NotificationsPage />} />
      </Route>

      {/* Manager / Court Manager (same routes; authenticated role drives presentation) */}
      <Route
        path="/manager"
        element={
          <RequireAuth roles={['MANAGER', 'COURT_MANAGER']}>
            <ManagerShell role={managerRole} />
          </RequireAuth>
        }
      >
        <Route index element={<Navigate to="/manager/dashboard" replace />} />
        <Route path="dashboard" element={<ManagerDashboardPage />} />
        <Route path="bookings" element={<ManagerBookingsPage />} />
        <Route path="courts" element={<ManagerCourtsPage />} />
        <Route path="notifications" element={<ManagerNotificationsPage />} />
      </Route>

      {/* Fallback */}
      <Route
        path="*"
        element={
          <div className="bp-route" style={{ maxWidth: '32rem', margin: '4rem auto', padding: '0 1rem' }}>
            <Card>
              <EmptyState
                icon="search_off"
                title="Không tìm thấy trang"
                description="Đường dẫn bạn yêu cầu không tồn tại hoặc đã bị thay đổi."
                action={
                  <NavLink to="/courts">
                    <Button variant="primary" icon="arrow_forward">
                      Về trang tìm sân
                    </Button>
                  </NavLink>
                }
              />
            </Card>
          </div>
        }
      />
    </Routes>
  );
}
