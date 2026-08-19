import { RoutePlaceholder } from '../../components/RoutePlaceholder';

/** Route skeleton for /manager/bookings. Booking management ships in Phase 2.7. */
export function ManagerBookingsPage() {
  return <RoutePlaceholder title="Quản lý booking" subtitle="Duyệt, từ chối, hoàn thành và hủy booking." icon="calendar_month" showStatuses />;
}