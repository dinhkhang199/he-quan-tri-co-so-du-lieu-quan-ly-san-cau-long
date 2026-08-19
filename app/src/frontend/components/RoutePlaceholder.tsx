import type { ReactNode } from 'react';
import { PageHeader } from './PageHeader';
import { EmptyState } from './EmptyState';
import { StatusBadge } from './StatusBadge';
import type { BookingStatus } from '../../shared/contract';

interface RoutePlaceholderProps {
  title: string;
  subtitle: string;
  icon?: string;
  /** Optional action row for the page header. */
  actions?: ReactNode;
  /** Optional demo row showing the five contract statuses. */
  showStatuses?: boolean;
}

/**
 * Phase 2.1 route skeleton: renders the shell content area with a page header
 * and an honest "not implemented yet" empty state. No business data.
 */
export function RoutePlaceholder({ title, subtitle, icon = 'construction', actions, showStatuses = false }: RoutePlaceholderProps) {
  return (
    <div className="bp-route">
      <PageHeader title={title} subtitle={subtitle} actions={actions} />
      <div className="bp-route__body">
        <EmptyState
          icon={icon}
          title="Màn hình đang được triển khai"
          description="Tính năng này sẽ được kết nối với Stored Procedure ở giai đoạn tiếp theo (Phase 2.2+)."
        />
      </div>
      {showStatuses ? (
        <div className="bp-route__status-demo">
          {(['PENDING', 'BOOKED', 'COMPLETED', 'CANCELLED', 'REJECTED'] as BookingStatus[]).map((s) => (
            <StatusBadge key={s} status={s} />
          ))}
        </div>
      ) : null}
    </div>
  );
}