import type { Notification } from '../../shared/types';
import { BpIcon } from './BpIcon';
import { EmptyState } from './EmptyState';

interface NotificationListProps {
  /** Rows to display (already filtered by the page). */
  notifications: Notification[];
  /** Total fetched rows (footer text). */
  totalCount: number;
  /** Unread rows among the fetched set (footer text). */
  unreadCount: number;
  /** In-flight notification id: that row is disabled and shows a spinner. */
  markingId: string | null;
  /** Any in-flight mark-read blocks every mark-read action. */
  disabled: boolean;
  onRead: (notification: Notification) => void;
}

/** Raw wall-clock ISO digits; safe whether the value arrived as Date or string. */
function wallClockString(value: Date | string): string {
  return typeof value === 'string' ? value : value.toISOString();
}

/**
 * The DB stores local wall-clock DATETIME2 verbatim, so the ISO string's digits
 * ARE the local time. Build a real Date from those digits (local-constructed)
 * instead of letting `new Date(iso)` re-interpret them as UTC (which would shift
 * the relative time). Comparison against `Date.now()` is then exact.
 */
function wallClockToLocalDate(value: Date | string): Date {
  const digits = wallClockString(value).slice(0, 19).replace('T', ' ');
  const [datePart, timePart] = digits.split(' ');
  const [y, m, d] = datePart.split('-').map(Number);
  const [hh, mm, ss] = timePart.split(':').map(Number);
  return new Date(y, m - 1, d, hh, mm, ss);
}

/** Locked Stitch relative-time labels, computed from the real CreatedAt. */
export function formatRelativeTime(value: Date | string): string {
  const date = wallClockToLocalDate(value);
  const diffSeconds = Math.floor((Date.now() - date.getTime()) / 1000);
  if (diffSeconds < 60) return 'Vừa xong';
  if (diffSeconds < 3600) return `${Math.floor(diffSeconds / 60)} phút trước`;
  if (diffSeconds < 86400) return `${Math.floor(diffSeconds / 3600)} giờ trước`;
  const diffDays = Math.floor(diffSeconds / 86400);
  if (diffDays === 1) return 'Hôm qua';
  if (diffDays < 7) return `${diffDays} ngày trước`;
  const [y, m, d] = wallClockString(value).slice(0, 10).split('-');
  return `${d}/${m}/${y}`;
}

/**
 * Shared notification list (locked th_ng_b_o_..._logic_cleaned) — represents a
 * flat list of real dbo.Notifications rows. Unread rows get the teal tint +
 * left accent bar + bold message; read rows are muted. The whole row is the
 * mark-read affordance (row click), matching the locked prototype. Only real
 * fields are shown: Message, IsRead, CreatedAt (relative) and BookingId (mono)
 * when the DB actually returned one. No invented categories/priorities/icons.
 */
export function NotificationList({
  notifications,
  totalCount,
  unreadCount,
  markingId,
  disabled,
  onRead,
}: NotificationListProps) {
  if (notifications.length === 0) {
    return (
      <div className="bp-notif__list">
        <EmptyState
          icon="notifications_paused"
          title="Chưa có thông báo"
          description="Hiện tại hệ thống chưa có cập nhật mới nào liên quan đến các booking của bạn."
        />
      </div>
    );
  }

  return (
    <div className="bp-notif__list">
      {notifications.map((notification) => {
        const isUnread = !notification.IsRead;
        const isMarking = markingId === notification.NotificationId;
        const locked = disabled || isMarking;
        return (
          <button
            key={notification.NotificationId}
            type="button"
            className={[
              'bp-notif__item',
              isUnread ? 'bp-notif__item--unread' : 'bp-notif__item--read',
            ].filter(Boolean).join(' ')}
            disabled={locked}
            aria-label={isUnread ? `Đánh dấu thông báo là đã đọc: ${notification.Message}` : undefined}
            onClick={() => onRead(notification)}
          >
            {isUnread ? <span className="bp-notif__bar" aria-hidden="true" /> : null}

            <span
              className={[
                'bp-notif__icon',
                isUnread ? 'bp-notif__icon--unread' : 'bp-notif__icon--read',
              ].filter(Boolean).join(' ')}
            >
              {isMarking ? (
                <BpIcon name="progress_activity" size={22} className="bp-spinner" aria-hidden="true" />
              ) : (
                <BpIcon name="notifications" filled={isUnread} size={22} aria-hidden="true" />
              )}
            </span>

            <span className="bp-notif__body">
              <span className="bp-notif__row">
                <span className={['bp-notif__message', isUnread ? 'bp-notif__message--unread' : ''].filter(Boolean).join(' ')}>
                  {notification.Message}
                </span>
                <span className={['bp-notif__time', isUnread ? 'bp-notif__time--unread' : ''].filter(Boolean).join(' ')}>
                  {formatRelativeTime(notification.CreatedAt)}
                </span>
              </span>
              {notification.BookingId ? (
                <span className={['bp-notif__meta', isUnread ? 'bp-notif__meta--unread' : ''].filter(Boolean).join(' ')}>
                  <BpIcon name="receipt_long" size={14} aria-hidden="true" />
                  <span className="bp-mono">{notification.BookingId}</span>
                </span>
              ) : null}
            </span>
          </button>
        );
      })}

      <div className="bp-notif__footer">
        <span>
          Hiển thị {notifications.length} trong {totalCount} thông báo
        </span>
        <span className={unreadCount > 0 ? 'bp-notif__unread-count' : 'bp-notif__unread-count--none'}>
          {unreadCount} chưa đọc
        </span>
      </div>
    </div>
  );
}