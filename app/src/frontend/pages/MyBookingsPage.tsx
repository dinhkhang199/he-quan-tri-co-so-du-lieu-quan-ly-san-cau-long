import { RoutePlaceholder } from '../components/RoutePlaceholder';

/** Route skeleton for /my-bookings. History + cancellation ship in Phase 2.5. */
export function MyBookingsPage() {
  return (
    <RoutePlaceholder
      title="Lịch sử đặt sân"
      subtitle="Quản lý và theo dõi các lượt đặt sân của bạn."
      icon="history"
      showStatuses
    />
  );
}