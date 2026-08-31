import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { NavLink, useNavigate } from 'react-router-dom';
import { PageHeader } from '../components/PageHeader';
import { Card } from '../components/Card';
import { Button } from '../components/Button';
import { StatusBadge } from '../components/StatusBadge';
import { EmptyState } from '../components/EmptyState';
import { LoadingSkeleton } from '../components/LoadingSkeleton';
import { BpIcon } from '../components/BpIcon';
import { ApiError, cancelBookingRequest, getMyBookingsRequest } from '../api/client';
import { useAuth } from '../auth/AuthContext';
import { BOOKING_STATUS } from '../../shared/contract';
import type { BookingStatus } from '../../shared/contract';
import type { MyBooking } from '../../shared/types';
import { hoursUntilVietnamWallClock } from '../../shared/time';

/**
 * Customer booking history + cancellation (Phase 2.5) — locked
 * l_ch_s_t_s_n_badmintonpro_final_polish.
 *
 * The list is fetched verbatim from dbo.sp_GetMyBookings (authenticated
 * customer only) and covers all five contract states. The Hủy affordance is
 * UX ONLY (PENDING always; BOOKED only when >= 3h remain before start):
 * dbo.sp_CancelBooking is the authority for ownership/state/deadline and a race
 * between render and click is always possible. After a successful cancel the
 * page refreshes history FROM THE DATABASE — no local status patching.
 *
 * StartTime/EndTime arrive as ISO strings carrying the local wall-clock digits
 * (the SQL DATETIME2 stored the wall clock verbatim). Display by string-slicing;
 * the 3h hint explicitly interprets those digits in Asia/Ho_Chi_Minh.
 */

type FilterStatus = 'ALL' | BookingStatus;

function formatVnd(value: number): string {
  return `${new Intl.NumberFormat('vi-VN').format(value)}đ`;
}

/** Raw wall-clock ISO digits; safe whether the value arrived as Date or string. */
function wallClockString(value: Date | string): string {
  return typeof value === 'string' ? value : value.toISOString();
}

function displayDate(iso: Date | string): string {
  const [y, m, d] = wallClockString(iso).slice(0, 10).split('-');
  return `${d}/${m}/${y}`;
}

function displayTime(iso: Date | string): string {
  return wallClockString(iso).slice(11, 16);
}

/** Whole hours from now until the start wall clock (instants → tz-safe). */
/** UX-only eligibility hint; sp_CancelBooking makes the final decision. */
function mayShowCancel(booking: MyBooking): boolean {
  if (booking.Status === 'PENDING') return true;
  if (booking.Status === 'BOOKED') return hoursUntilVietnamWallClock(booking.StartTime) >= 3;
  return false;
}

const FINAL_STATUSES: ReadonlySet<BookingStatus> = new Set(['COMPLETED', 'CANCELLED', 'REJECTED']);

export function MyBookingsPage() {
  const navigate = useNavigate();
  const { logout } = useAuth();

  type LoadState = 'loading' | 'ready' | 'error';
  const [loadState, setLoadState] = useState<LoadState>('loading');
  const [bookings, setBookings] = useState<MyBooking[]>([]);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [refreshing, setRefreshing] = useState(false);

  const [filterStatus, setFilterStatus] = useState<FilterStatus>('ALL');
  const [filterDate, setFilterDate] = useState('');

  const [cancelTarget, setCancelTarget] = useState<MyBooking | null>(null);
  const [cancelling, setCancelling] = useState(false);
  const [cancelError, setCancelError] = useState<string | null>(null);

  const [toast, setToast] = useState<{ title: string; message: string } | null>(null);
  const toastTimer = useRef<number | null>(null);

  const clearToast = useCallback(() => {
    if (toastTimer.current !== null) {
      window.clearTimeout(toastTimer.current);
      toastTimer.current = null;
    }
    setToast(null);
  }, []);

  const showCancelToast = useCallback(() => {
    setToast({ title: 'Đã hủy booking', message: 'Booking đã được chuyển sang trạng thái CANCELLED.' });
    toastTimer.current = window.setTimeout(() => setToast(null), 3000);
  }, []);

  useEffect(() => clearToast, [clearToast]);

  /** Fetch history from dbo.sp_GetMyBookings. Background keeps the visible list on error. */
  const loadHistory = useCallback(
    async (opts?: { background?: boolean }) => {
      if (!opts?.background) setLoadState('loading');
      setRefreshing(true);
      setLoadError(null);
      try {
        const res = await getMyBookingsRequest();
        setBookings(res.bookings);
        setLoadState('ready');
      } catch (err) {
        const message = err instanceof Error ? err.message : 'Có lỗi từ hệ thống. Vui lòng thử lại.';
        setLoadError(message);
        if (opts?.background) {
          // Keep the stale authoritative list visible; DB state is the truth.
        } else {
          setLoadState('error');
        }
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
    void loadHistory();
  }, [loadHistory]);

  const filtered = useMemo(() => {
    return bookings.filter((b) => {
      const statusOk = filterStatus === 'ALL' || b.Status === filterStatus;
      const dateOk = !filterDate || wallClockString(b.StartTime).slice(0, 10) === filterDate;
      return statusOk && dateOk;
    });
  }, [bookings, filterStatus, filterDate]);

  function openCancel(booking: MyBooking): void {
    setCancelError(null);
    setCancelTarget(booking);
  }

  async function handleCancelConfirm(): Promise<void> {
    if (!cancelTarget || cancelling) return;
    setCancelling(true);
    setCancelError(null);
    try {
      await cancelBookingRequest(cancelTarget.BookingId);
      setCancelTarget(null);
      showCancelToast();
      // Mandatory post-mutation reconciliation: re-read from the database.
      await loadHistory({ background: true });
    } catch (err) {
      if (err instanceof ApiError && err.status === 401) {
        await logout();
        navigate('/login', { replace: true });
        return;
      }
      setCancelError(err instanceof Error ? err.message : 'Có lỗi từ hệ thống. Vui lòng thử lại.');
    } finally {
      setCancelling(false);
    }
  }

  const filters = (
    <div className="bp-history__filters">
      <div className="bp-history__filter">
        <select
          className="bp-history__select"
          aria-label="Lọc theo trạng thái"
          value={filterStatus}
          onChange={(e) => setFilterStatus(e.target.value as FilterStatus)}
        >
          <option value="ALL">Tất cả trạng thái</option>
          {BOOKING_STATUS.map((s) => (
            <option key={s} value={s}>
              {s}
            </option>
          ))}
        </select>
        <span className="bp-history__filter-icon" aria-hidden="true">
          <BpIcon name="expand_more" size={18} />
        </span>
      </div>
      <input
        className="bp-history__date"
        type="date"
        aria-label="Lọc theo ngày"
        value={filterDate}
        onChange={(e) => setFilterDate(e.target.value)}
      />
      <button
        className="bp-history__filter-btn"
        type="button"
        onClick={() => void loadHistory({ background: true })}
        disabled={refreshing}
      >
        <BpIcon name="filter_list" size={20} aria-hidden="true" />
        Lọc
      </button>
    </div>
  );

  return (
    <div className="bp-history">
      <PageHeader
        title="Lịch sử đặt sân"
        subtitle="Quản lý và theo dõi các lượt đặt sân của bạn."
      />

      {loadState === 'loading' ? (
        <Card className="bp-history__card">
          <LoadingSkeleton variant="table" rows={5} />
        </Card>
      ) : loadState === 'error' ? (
        <Card className="bp-history__card">
          <EmptyState
            icon="cloud_off"
            title="Không tải được lịch sử đặt sân"
            description={loadError}
            action={
              <Button variant="primary" icon="refresh" onClick={() => void loadHistory()}>
                Thử lại
              </Button>
            }
          />
        </Card>
      ) : (
        <>
          {filters}

          {loadError ? (
            <div className="bp-history__notice" role="alert">
              <BpIcon name="warning" size={18} aria-hidden="true" />
              <span>{loadError}</span>
            </div>
          ) : null}

          <Card className="bp-history__card" flush>
            <div className="bp-history__scroll">
              <table className="bp-history__table">
                <thead>
                  <tr>
                    <th className="bp-history__th--id">Mã booking</th>
                    <th>Sân</th>
                    <th>Ngày</th>
                    <th>Khung giờ</th>
                    <th className="bp-history__th--right">Tổng tiền</th>
                    <th>Trạng thái</th>
                    <th className="bp-history__th--right">Thao tác</th>
                  </tr>
                </thead>
                <tbody>
                  {filtered.length === 0 ? (
                    <tr>
                      <td colSpan={7}>
                        <EmptyState
                          icon="event_busy"
                          title={bookings.length === 0 ? 'Chưa có lịch sử đặt sân' : 'Không có kết quả phù hợp'}
                          description={
                            bookings.length === 0
                              ? 'Khi bạn đặt sân, các lượt đặt sẽ xuất hiện ở đây.'
                              : 'Thử thay đổi bộ lọc trạng thái hoặc ngày.'
                          }
                          action={
                            bookings.length === 0 ? (
                              <NavLink to="/courts">
                                <Button variant="primary" icon="search">
                                  Tìm sân
                                </Button>
                              </NavLink>
                            ) : undefined
                          }
                        />
                      </td>
                    </tr>
                  ) : (
                    filtered.map((b) => {
                      const inert = FINAL_STATUSES.has(b.Status);
                      const cancellable = mayShowCancel(b);
                      return (
                        <tr key={b.BookingId} className={inert ? 'bp-history__row--inert' : ''}>
                          <td className="bp-history__cell--id">
                            <span className="bp-mono bp-history__code">{b.BookingId}</span>
                          </td>
                          <td className="bp-history__court">
                            <span className="bp-history__court-name">{b.CourtName}</span>
                          </td>
                          <td>{displayDate(b.StartTime)}</td>
                          <td>
                            {displayTime(b.StartTime)} – {displayTime(b.EndTime)}
                          </td>
                          <td className="bp-history__cost">{formatVnd(Number(b.TotalCost ?? 0))}</td>
                          <td>
                            <StatusBadge status={b.Status} />
                          </td>
                          <td className="bp-history__actions">
                            {cancellable ? (
                              <button
                                className="bp-history__cancel"
                                type="button"
                                onClick={() => openCancel(b)}
                                disabled={cancelling}
                              >
                                <BpIcon name="cancel" size={18} aria-hidden="true" />
                                Hủy
                              </button>
                            ) : (
                              <span className="bp-history__noop" aria-hidden="true">
                                —
                              </span>
                            )}
                          </td>
                        </tr>
                      );
                    })
                  )}
                </tbody>
              </table>
            </div>
            <div className="bp-history__footer">
              <span>
                Hiển thị {filtered.length} trong {bookings.length} kết quả
              </span>
            </div>
          </Card>
        </>
      )}

      {/* -------- Cancel confirmation modal (locked Stitch behavior) -------- */}
      {cancelTarget ? (
        <div className="bp-modal" role="dialog" aria-modal="true" aria-labelledby="bp-cancel-modal-title">
          <div
            className="bp-modal__backdrop"
            onClick={() => {
              if (!cancelling) setCancelTarget(null);
            }}
          />
          <div className="bp-modal__panel">
            <div className="bp-modal__body">
              <div className="bp-modal__icon">
                <BpIcon name="warning" filled size={26} aria-hidden="true" />
              </div>
              <div className="bp-modal__content">
                <h3 id="bp-cancel-modal-title">Hủy đặt sân?</h3>
                <p className="bp-modal__text">
                  Bạn có chắc chắn muốn hủy booking{' '}
                  <span className="bp-mono bp-modal__booking-id">{cancelTarget.BookingId}</span> không?
                </p>
                <p className="bp-modal__court-line">
                  {cancelTarget.CourtName} · {displayDate(cancelTarget.StartTime)} {displayTime(cancelTarget.StartTime)}–
                  {displayTime(cancelTarget.EndTime)}
                </p>
                <p className="bp-modal__warn">Hành động hủy là không thể hoàn tác.</p>
                {cancelError ? (
                  <div className="bp-history__alert" role="alert">
                    <BpIcon name="error" size={18} aria-hidden="true" />
                    <span>{cancelError}</span>
                  </div>
                ) : null}
              </div>
            </div>
            <div className="bp-modal__actions">
              <Button variant="outline" onClick={() => setCancelTarget(null)} disabled={cancelling}>
                Đóng
              </Button>
              <Button
                variant="danger"
                icon="cancel"
                loading={cancelling}
                keepLabel={cancelling}
                disabled={cancelling}
                onClick={() => void handleCancelConfirm()}
              >
                Xác nhận hủy
              </Button>
            </div>
          </div>
        </div>
      ) : null}

      {/* -------- Success toast (locked Stitch behavior) -------- */}
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
