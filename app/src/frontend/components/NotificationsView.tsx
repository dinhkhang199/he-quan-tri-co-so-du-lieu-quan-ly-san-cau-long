import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { PageHeader } from './PageHeader';
import { Button } from './Button';
import { EmptyState } from './EmptyState';
import { LoadingSkeleton } from './LoadingSkeleton';
import { BpIcon } from './BpIcon';
import { NotificationList } from './NotificationList';
import { ApiError, getNotificationsRequest, markNotificationReadRequest } from '../api/client';
import { useAuth } from '../auth/AuthContext';
import type { Notification } from '../../shared/types';

type NotificationFilter = 'ALL' | 'UNREAD';

/**
 * Shared authenticated notifications view (Phase 2.6) — locked
 * th_ng_b_o_badmintonpro_production_final_logic_cleaned.
 *
 * Used under BOTH shells: the customer route (/notifications, CustomerShell)
 * and the manager route (/manager/notifications, ManagerShell). The Stored
 * Procedure (dbo.sp_GetNotifications) returns ONLY the authenticated actor's
 * rows (driven by SESSION_CONTEXT), so the shell never changes what a role can
 * see — a MANAGER gets exactly their own notifications, never another user's.
 *
 * The "Tất cả / Chưa đọc" segmented control is a DISPLAY-ONLY filter over the
 * already-authorized rows; unread counts are derived from the returned IsRead
 * values. Clicking an unread row calls dbo.sp_MarkNotificationRead (row click,
 * as locked); a ref guard makes a rapid double-click produce exactly ONE
 * mutation. After success the list is refetched from the DB — no local
 * IsRead patching.
 */

export function NotificationsView() {
  const navigate = useNavigate();
  const { logout } = useAuth();

  type LoadState = 'loading' | 'ready' | 'error';
  const [loadState, setLoadState] = useState<LoadState>('loading');
  const [notifications, setNotifications] = useState<Notification[]>([]);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [refreshing, setRefreshing] = useState(false);

  const [filter, setFilter] = useState<NotificationFilter>('ALL');

  const [markingId, setMarkingId] = useState<string | null>(null);
  const [actionError, setActionError] = useState<string | null>(null);
  /** Hard guard: exactly one mark-read mutation until it completes. */
  const inFlightRef = useRef<string | null>(null);

  const [toast, setToast] = useState<{ title: string; message: string } | null>(null);
  const toastTimer = useRef<number | null>(null);

  // Re-render every minute so relative timestamps ("N phút trước") stay fresh.
  const [, setTick] = useState(0);

  const clearToast = useCallback(() => {
    if (toastTimer.current !== null) {
      window.clearTimeout(toastTimer.current);
      toastTimer.current = null;
    }
    setToast(null);
  }, []);

  useEffect(() => clearToast, [clearToast]);

  useEffect(() => {
    const timer = window.setInterval(() => setTick((t) => t + 1), 60_000);
    return () => window.clearInterval(timer);
  }, []);

  /**
   * Refetch the actor's notifications from dbo.sp_GetNotifications. A
   * background refetch keeps the stale authoritative list visible while the DB
   * is re-read after a mutation; a full reload resets to the loading skeleton.
   */
  const loadNotifications = useCallback(
    async (opts?: { background?: boolean }) => {
      if (!opts?.background) setLoadState('loading');
      setRefreshing(true);
      setLoadError(null);
      try {
        const res = await getNotificationsRequest();
        setNotifications(res.notifications);
        setLoadState('ready');
      } catch (err) {
        const message = err instanceof Error ? err.message : 'Có lỗi từ hệ thống. Vui lòng thử lại.';
        setLoadError(message);
        if (!opts?.background) setLoadState('error');
        if (err instanceof ApiError && err.status === 401) {
          await logout();
          navigate('/login', { replace: true });
          return;
        }
      } finally {
        setRefreshing(false);
      }
    },
    [logout, navigate],
  );

  useEffect(() => {
    void loadNotifications();
  }, [loadNotifications]);

  const filtered = useMemo(() => {
    return notifications.filter((n) => filter === 'ALL' || !n.IsRead);
  }, [notifications, filter]);

  const unreadCount = useMemo(() => notifications.reduce((acc, n) => acc + (n.IsRead ? 0 : 1), 0), [notifications]);

  /**
   * Row click -> mark notification read through dbo.sp_MarkNotificationRead.
   * Already-read rows no-op, matching the locked row-click behavior. The ref
   * guarantees exactly one request per row even under two rapid clicks, and the
   * SP enforces ownership (a foreign/unknown id is rejected and left intact).
   */
  async function handleRead(notification: Notification): Promise<void> {
    if (notification.IsRead) return;
    if (inFlightRef.current !== null) return;
    inFlightRef.current = notification.NotificationId;
    setMarkingId(notification.NotificationId);
    setActionError(null);
    try {
      await markNotificationReadRequest(notification.NotificationId);
      showReadToast();
      // Mandatory post-mutation reconciliation: re-read from the database.
      await loadNotifications({ background: true });
    } catch (err) {
      if (err instanceof ApiError && err.status === 401) {
        inFlightRef.current = null;
        setMarkingId(null);
        await logout();
        navigate('/login', { replace: true });
        return;
      }
      // 404 (not found/not owner) / 409 / 500 → keep DB truth, show the safe
      // server message; the actor remains authenticated.
      setActionError(err instanceof Error ? err.message : 'Có lỗi từ hệ thống. Vui lòng thử lại.');
    } finally {
      inFlightRef.current = null;
      setMarkingId(null);
    }
  }

  function showReadToast(): void {
    setToast({ title: 'Đã đọc thông báo', message: 'Thông báo đã được đánh dấu là đã đọc.' });
    toastTimer.current = window.setTimeout(() => setToast(null), 3000);
  }

  const filterChips = (
    <div className="bp-notif__seg" role="group" aria-label="Lọc theo trạng thái đọc">
      {(
        [
          { id: 'ALL', label: 'Tất cả' },
          { id: 'UNREAD', label: 'Chưa đọc' },
        ] as const
      ).map((c) => (
        <button
          key={c.id}
          type="button"
          className={['bp-notif__seg-btn', filter === c.id ? 'bp-notif__seg-btn--active' : ''].filter(Boolean).join(' ')}
          onClick={() => setFilter(c.id)}
        >
          {c.label}
        </button>
      ))}
    </div>
  );

  return (
    <div className="bp-notif">
      <PageHeader
        title="Thông báo"
        subtitle="Theo dõi các cập nhật liên quan đến booking trong hệ thống."
        actions={filterChips}
      />

      {loadState === 'loading' ? (
        <div className="bp-notif__list">
          <LoadingSkeleton variant="list" rows={6} />
        </div>
      ) : loadState === 'error' ? (
        <div className="bp-notif__list">
          <EmptyState
            icon="cloud_off"
            title="Không tải được danh sách thông báo"
            description={loadError}
            action={
              <Button variant="primary" icon="refresh" onClick={() => void loadNotifications()}>
                Thử lại
              </Button>
            }
          />
        </div>
      ) : (
        <>
          {loadError ? (
            <div className="bp-history__notice" role="alert">
              <BpIcon name="warning" size={18} aria-hidden="true" />
              <span>{loadError}</span>
            </div>
          ) : null}
          {actionError ? (
            <div className="bp-history__alert" role="alert">
              <BpIcon name="error" size={18} aria-hidden="true" />
              <span>{actionError}</span>
            </div>
          ) : null}

          <NotificationList
            notifications={filtered}
            totalCount={notifications.length}
            unreadCount={unreadCount}
            markingId={markingId}
            disabled={inFlightRef.current !== null}
            onRead={(n) => void handleRead(n)}
          />

          <div className="bp-notif__status">
            {refreshing ? (
              <span className="bp-mgr__refreshing">
                <BpIcon name="progress_activity" size={16} aria-hidden="true" />
                Đang đồng bộ từ cơ sở dữ liệu...
              </span>
            ) : (
              <span />
            )}
          </div>
        </>
      )}

      {/* -------- Success toast -------- */}
      {toast ? (
        <div className="bp-toast" role="status">
          <span className="bp-toast__icon">
            <BpIcon name="check_circle" filled size={22} aria-hidden="true" />
          </span>
          <div className="bp-toast__text">
            <h4>{toast.title}</h4>
            <p>{toast.message}</p>
          </div>
          <button className="bp-toast__close" type="button" aria-label="Đóng thông báo" onClick={clearToast}>
            <BpIcon name="close" size={20} aria-hidden="true" />
          </button>
          <div className="bp-toast__bar" aria-hidden="true" />
        </div>
      ) : null}
    </div>
  );
}