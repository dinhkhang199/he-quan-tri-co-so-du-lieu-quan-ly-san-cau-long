import { Routes, Route, Navigate } from 'react-router-dom';
import { LoginPage } from './pages/LoginPage';
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

/**
 * Phase 2.1 routing skeleton. Only locked screens, route placeholders only.
 * Guest has no privileged shell; the ManagerShell role prop is presentational
 * (backend stays the security authority). COURT_MANAGER reuses the SAME
 * /manager/* routes as MANAGER — no separate route namespace.
 */
export function App() {
  return (
    <Routes>
      {/* "/" has no product screen; redirect to the approved public route. */}
      <Route path="/" element={<Navigate to="/courts" replace />} />

      {/* Public */}
      <Route path="/login" element={<LoginPage />} />
      <Route path="/courts" element={<GuestShell />}>
        <Route index element={<CourtsPage />} />
      </Route>

      {/* Customer */}
      <Route path="/booking/:courtId" element={<CustomerShell />}>
        <Route index element={<BookingDetailPage />} />
      </Route>
      <Route path="/my-bookings" element={<CustomerShell />}>
        <Route index element={<MyBookingsPage />} />
      </Route>
      <Route path="/notifications" element={<CustomerShell />}>
        <Route index element={<NotificationsPage />} />
      </Route>

      {/* Manager / Court Manager (same routes; role is presentational) */}
      <Route path="/manager" element={<ManagerShell role="MANAGER" />}>
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
          <div style={{ padding: '3rem', textAlign: 'center' }}>
            <a href="/courts">Không tìm thấy trang. Về trang tìm sân.</a>
          </div>
        }
      />
    </Routes>
  );
}