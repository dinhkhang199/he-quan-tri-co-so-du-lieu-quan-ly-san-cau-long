import type { BookingStatus } from '../../shared/contract';

interface StatusBadgeProps {
  status: BookingStatus;
  className?: string;
}

const STATUS_CLASS: Record<BookingStatus, string> = {
  PENDING: 'bp-badge--pending',
  BOOKED: 'bp-badge--booked',
  COMPLETED: 'bp-badge--completed',
  CANCELLED: 'bp-badge--cancelled',
  REJECTED: 'bp-badge--rejected',
};

/**
 * Pill status badge with a leading dot, matching the locked Stitch history
 * and booking-management badges. Supports ONLY the five contract states.
 */
export function StatusBadge({ status, className }: StatusBadgeProps) {
  return (
    <span className={['bp-badge', STATUS_CLASS[status], className ?? ''].filter(Boolean).join(' ')}>
      <span className="bp-badge__dot" aria-hidden="true" />
      {status}
    </span>
  );
}