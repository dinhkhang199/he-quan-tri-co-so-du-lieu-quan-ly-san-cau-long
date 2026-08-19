import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { PageHeader } from '../../components/PageHeader';
import { Card } from '../../components/Card';
import { Button } from '../../components/Button';
import { StatusBadge } from '../../components/StatusBadge';
import { EmptyState } from '../../components/EmptyState';
import { LoadingSkeleton } from '../../components/LoadingSkeleton';
import { BpIcon } from '../../components/BpIcon';
import { ApiError, getManagerBookingsRequest, managerActionRequest } from '../../api/client';
import { useAuth } from '../../auth/AuthContext';
import { BOOKING_STATUS } from '../../../shared/contract';
import type { BookingStatus } from '../../../shared/contract';
import type { ManagerBooking, ManagerBookingAction } from '../../../shared/types';

/**
 * Manager / Court Manager booking management (Phase 2.6) — locked
 * qu_n_l_booking_badmintonpro_production_final_polish.
 *
 * The list is fetched from dbo.vw_AllBookings on the authenticated SQL session;
 * scope is applied IN SQL by SESSION_CONTEXT (MANAGER → all rows; COURT_MANAGER
 * → only OwnerId rows), so the browser only ever receives authorized rows. The
 * chips (Tất cả/PENDING/...) are DISPLAY-ONLY filters over those rows.
 *
 * The Duyệt/Từ chối (PENDING) and Hoàn thành/Hủy (BOOKED) affordances are UX
 * ONLY: the role, ownership, state and overlap checks are decided by
 * sp_ApproveBooking / sp_RejectBooking / sp_CancelBooking /
 * sp_CompleteBooking under lock. A race between render and click is always
 * possible, so after every successful mutation the list is refetched from the
 * DB — no local status patching. Duplicate submits are blocked while a mutation
 * is running.
 *
 * The "Chế độ demo CSDL" drawer is a STATIC, read-only educational panel whose
 * text refers to the real Phase 1 evidence files (database/10–14,
 * tests/concurrency). It never opens a SQL connection and never executes SQL.
 */

type FilterStatus = 'ALL' | BookingStatus;

type ActionMeta = {
  label: string;
  confirmTitle: string;
  confirmLabel: string;
  successTitle: string;
  successMessage: string;
  danger: boolean;
  icon: string;
};

const ACTION_META: Record<ManagerBookingAction, ActionMeta> = {
  approve: {
    label: 'Duyệt',
    confirmTitle: 'Duyệt booking?',
    confirmLabel: 'Xác nhận duyệt',
    successTitle: 'Đã duyệt booking',
    successMessage: 'Booking đã chuyển sang trạng thái BOOKED.',
    danger: false,
    icon: 'check',
  },
  reject: {
    label: 'Từ chối',
    confirmTitle: 'Từ chối booking?',
    confirmLabel: 'Xác nhận từ chối',
    successTitle: 'Đã từ chối booking',
    successMessage: 'Booking đã chuyển sang trạng thái REJECTED.',
    danger: true,
    icon: 'close',
  },
  cancel: {
    label: 'Hủy',
    confirmTitle: 'Hủy booking?',
    confirmLabel: 'Xác nhận hủy',
    successTitle: 'Đã hủy booking',
    successMessage: 'Booking đã chuyển sang trạng thái CANCELLED.',
    danger: true,
    icon: 'cancel',
  },
  complete: {
    label: 'Hoàn thành',
    confirmTitle: 'Hoàn thành booking?',
    confirmLabel: 'Xác nhận hoàn thành',
    successTitle: 'Đã hoàn thành booking',
    successMessage: 'Booking đã chuyển sang trạng thái COMPLETED.',
    danger: false,
    icon: 'task_alt',
  },
};

const ACTIONS_BY_STATUS: Record<BookingStatus, ManagerBookingAction[]> = {
  PENDING: ['approve', 'reject'],
  BOOKED: ['complete', 'cancel'],
  COMPLETED: [],
  CANCELLED: [],
  REJECTED: [],
};

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

/* -------------------------------------------------------------------------- */
/* CSDL Demo drawer (static, read-only educational panel)                     */
/* -------------------------------------------------------------------------- */

type DemoTab = 'approve' | 'deadlock' | 'phantom';

const DEMO_TABS: { id: DemoTab; label: string }[] = [
  { id: 'approve', label: 'Approve cạnh tranh' },
  { id: 'deadlock', label: 'Deadlock' },
  { id: 'phantom', label: 'Phantom Read' },
];

function DemoDrawer({ open, onClose }: { open: boolean; onClose: () => void }) {
  const [tab, setTab] = useState<DemoTab>('approve');

  if (!open) return null;

  return (
    <div className="bp-demo" role="dialog" aria-modal="true" aria-label="CSDL Demo Terminal">
      <div className="bp-demo__backdrop" onClick={onClose} role="presentation" />
      <aside className="bp-demo__panel">
        <header className="bp-demo__head">
          <div className="bp-demo__title">
            <BpIcon name="database" size={20} aria-hidden="true" />
            <h3>CSDL Demo Terminal</h3>
          </div>
          <button className="bp-demo__close" type="button" aria-label="Đóng chế độ demo CSDL" onClick={onClose}>
            <BpIcon name="close" size={20} aria-hidden="true" />
          </button>
        </header>

        <div className="bp-demo__tabs" role="tablist" aria-label="Các kịch bản demo CSDL">
          {DEMO_TABS.map((t) => (
            <button
              key={t.id}
              type="button"
              role="tab"
              aria-selected={tab === t.id}
              className={['bp-demo__tab', tab === t.id ? 'bp-demo__tab--active' : ''].filter(Boolean).join(' ')}
              onClick={() => setTab(t.id)}
            >
              {t.label}
            </button>
          ))}
        </div>

        <div className="bp-demo__terminal" role="tabpanel">
          {tab === 'approve' ? (
            <>
              <p className="bp-demo__comment">
                -- Kịch bản minh họa (DB Demo): hai session cùng duyệt 2 booking PENDING
              </p>
              <p className="bp-demo__comment">
                -- chồng thời gian trên cùng một sân. Chứng cứ thật: database/11-12 (CC-01).
              </p>

              <div className="bp-demo__session-a">&gt; Session A</div>
              <div className="bp-demo__block">
                BEGIN TRAN; SELECT * FROM Bookings WITH (UPDLOCK) WHERE BookingId = '&lt;Booking A&gt;';
                <div className="bp-demo__comment">-- Booking A: cùng sân, khung giờ đầu — PENDING</div>
              </div>

              <div className="bp-demo__session-b">&gt; Session B</div>
              <div className="bp-demo__block">
                BEGIN TRAN; SELECT * FROM Bookings WITH (UPDLOCK) WHERE BookingId = '&lt;Booking B&gt;';
                <div className="bp-demo__comment">-- Booking B: cùng sân, khung giờ chồng — PENDING</div>
                <div className="bp-demo__warn">-- Blocked! Chờ Session A nhả khóa trên tài nguyên sân...</div>
              </div>

              <div className="bp-demo__session-a">&gt; Session A</div>
              <div className="bp-demo__block">
                UPDATE Bookings SET Status = 'BOOKED'; COMMIT TRAN;
                <div className="bp-demo__ok">-- Thành công: Booking A đã chuyển sang BOOKED.</div>
              </div>

              <div className="bp-demo__session-b">&gt; Session B — tiếp tục</div>
              <div className="bp-demo__block">
                <div className="bp-demo__comment">-- Kiểm tra lại chồng thời gian (sp_ApproveBooking / trigger)...</div>
                <div className="bp-demo__err">-- Xung đột: sân đã có BOOKED trong khung giờ này.</div>
                <div className="bp-demo__err">-- Vi phạm nghiệp vụ -&gt; ROLLBACK</div>
                ROLLBACK TRAN;
              </div>

              <p className="bp-demo__note">
                Trong ứng dụng thật, lỗi chồng thời gian trả về HTTP 409 — modal giữ nguyên và yêu cầu chọn lại.
              </p>
            </>
          ) : null}

          {tab === 'deadlock' ? (
            <>
              <p className="bp-demo__comment">
                -- Kịch bản minh họa (DB Demo): deadlock — vòng chờ khóa giữa 2 giao dịch.
              </p>
              <p className="bp-demo__comment">
                -- Chứng cứ thật: database/13-14 (SQL Server Error 1205, deadlock victim).
              </p>

              <div className="bp-demo__step">1. Session A giữ Lock trên Booking_1, chờ Lock trên Booking_2.</div>
              <div className="bp-demo__step">2. Session B giữ Lock trên Booking_2, chờ Lock trên Booking_1.</div>

              <div className="bp-demo__cycle">
                <span className="bp-demo__node bp-demo__node--a">A</span>
                <span className="bp-demo__arrow">
                  <BpIcon name="sync_alt" size={22} aria-hidden="true" />
                </span>
                <span className="bp-demo__node bp-demo__node--b">B</span>
              </div>

              <div className="bp-demo__msg">
                <div className="bp-demo__msg-title">
                  <BpIcon name="error" size={18} aria-hidden="true" />
                  Msg 1205, Deadlock victim
                </div>
                <p className="bp-demo__msg-body">
                  Transaction (Process ID ...) was deadlocked on lock resources with another process and has been
                  chosen as the deadlock victim. Rerun the transaction.
                </p>
              </div>

              <p className="bp-demo__note">
                Trong ứng dụng thật, Error 1205 được ánh xạ sang HTTP 409 và người dùng thử lại thủ công — không tự
                động chạy lại lệnh.
              </p>
            </>
          ) : null}

          {tab === 'phantom' ? (
            <>
              <p className="bp-demo__comment">
                -- Kịch bản minh họa (DB Demo): Phantom Read ở hai mức cô lập.
              </p>
              <p className="bp-demo__comment">
                -- Chứng cứ thật: database/10 (PH-01, PH-02) và tests/concurrency/phantom_session_*.
              </p>

              <div className="bp-demo__sub">READ COMMITTED (mặc định)</div>
              <div className="bp-demo__block">
                <span className="bp-demo__session-a">A:</span> SELECT COUNT(*) FROM Bookings WHERE date = '...'
                <span className="bp-demo__ok"> -&gt; 2 rows</span>
                <br />
                <span className="bp-demo__session-b">B:</span> INSERT INTO Bookings ... ; COMMIT;
                <br />
                <span className="bp-demo__session-a">A:</span> SELECT COUNT(*) FROM Bookings WHERE date = '...'
                <span className="bp-demo__err"> -&gt; 3 rows (Phantom!)</span>
              </div>

              <div className="bp-demo__sub">SERIALIZABLE</div>
              <div className="bp-demo__block">
                <span className="bp-demo__session-a">A:</span> SELECT COUNT(*) FROM Bookings WHERE date = '...'
                <span className="bp-demo__ok"> -&gt; 2 rows</span>
                <br />
                <span className="bp-demo__session-b">B:</span> INSERT INTO Bookings ...
                <span className="bp-demo__warn"> -- Blocked! (Range lock của Session A)</span>
                <br />
                <span className="bp-demo__session-a">A:</span> COMMIT;
                <br />
                <span className="bp-demo__session-b">B:</span> -- Tiếp tục và hoàn tất.
              </div>
            </>
          ) : null}
        </div>

        <footer className="bp-demo__foot">
          <BpIcon name="info" size={16} aria-hidden="true" />
          <span>Kịch bản minh họa (DB Demo) — nội dung tĩnh, không thực thi SQL trong ứng dụng.</span>
        </footer>
      </aside>
    </div>
  );
}

/* -------------------------------------------------------------------------- */
/* Page                                                                       */
/* -------------------------------------------------------------------------- */

export function ManagerBookingsPage() {
  const navigate = useNavigate();
  const { logout } = useAuth();

  type LoadState = 'loading' | 'ready' | 'error';
  const [loadState, setLoadState] = useState<LoadState>('loading');
  const [bookings, setBookings] = useState<ManagerBooking[]>([]);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [refreshing, setRefreshing] = useState(false);

  const [filterStatus, setFilterStatus] = useState<FilterStatus>('ALL');
  const [demoOpen, setDemoOpen] = useState(false);

  const [target, setTarget] = useState<{ booking: ManagerBooking; action: ManagerBookingAction } | null>(null);
  const [mutating, setMutating] = useState<ManagerBookingAction | null>(null);
  const [mutationError, setMutationError] = useState<string | null>(null);

  const [toast, setToast] = useState<{ title: string; message: string } | null>(null);
  const toastTimer = useRef<number | null>(null);

  const clearToast = useCallback(() => {
    if (toastTimer.current !== null) {
      window.clearTimeout(toastTimer.current);
      toastTimer.current = null;
    }
    setToast(null);
  }, []);

  const showToast = useCallback((title: string, message: string) => {
    setToast({ title, message });
    toastTimer.current = window.setTimeout(() => setToast(null), 3000);
  }, []);

  useEffect(() => clearToast, [clearToast]);

  /**
   * Refetch the manager list from dbo.vw_AllBookings. A background refetch keeps
   * the stale authoritative list visible while the DB is re-read after a
   * mutation; a full reload resets to the loading skeleton.
   */
  const loadManagerBookings = useCallback(
    async (opts?: { background?: boolean }) => {
      if (!opts?.background) setLoadState('loading');
      setRefreshing(true);
      setLoadError(null);
      try {
        const res = await getManagerBookingsRequest();
        setBookings(res.bookings);
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
    void loadManagerBookings();
  }, [loadManagerBookings]);

  const filtered = useMemo(() => {
    return bookings.filter((b) => filterStatus === 'ALL' || b.Status === filterStatus);
  }, [bookings, filterStatus]);

  function openConfirm(booking: ManagerBooking, action: ManagerBookingAction): void {
    setMutationError(null);
    setTarget({ booking, action });
  }

  async function handleMutationConfirm(): Promise<void> {
    if (!target || mutating) return;
    setMutating(target.action);
    setMutationError(null);
    const meta = ACTION_META[target.action];
    try {
      await managerActionRequest(target.action, target.booking.BookingId);
      setTarget(null);
      showToast(meta.successTitle, meta.successMessage);
      // Mandatory post-mutation reconciliation: re-read from the database.
      await loadManagerBookings({ background: true });
    } catch (err) {
      if (err instanceof ApiError && err.status === 401) {
        await logout();
        navigate('/login', { replace: true });
        return;
      }
      // 403/404/409 (ownership / gone / conflict) → stay in the modal so the
      // user can see the exact message and decide; DB state is the truth.
      setMutationError(err instanceof Error ? err.message : 'Có lỗi từ hệ thống. Vui lòng thử lại.');
    } finally {
      setMutating(null);
    }
  }

  const chips = (
    <div className="bp-mgr__chips" role="group" aria-label="Lọc theo trạng thái">
      <button
        type="button"
        className={['bp-mgr__chip', filterStatus === 'ALL' ? 'bp-mgr__chip--active' : ''].filter(Boolean).join(' ')}
        onClick={() => setFilterStatus('ALL')}
      >
        Tất cả
      </button>
      {BOOKING_STATUS.map((s) => (
        <button
          key={s}
          type="button"
          className={['bp-mgr__chip', filterStatus === s ? 'bp-mgr__chip--active' : ''].filter(Boolean).join(' ')}
          onClick={() => setFilterStatus(s)}
        >
          {s}
        </button>
      ))}
    </div>
  );

  return (
    <div className="bp-mgr">
      <PageHeader
        title="Quản lý booking"
        subtitle="Duyệt và theo dõi các lượt đặt sân trong hệ thống."
        actions={
          <button className="bp-mgr__demo-btn" type="button" onClick={() => setDemoOpen(true)}>
            <BpIcon name="terminal" size={20} aria-hidden="true" />
            Chế độ demo CSDL
          </button>
        }
      />

      {loadState === 'loading' ? (
        <Card className="bp-history__card">
          <LoadingSkeleton variant="table" rows={6} />
        </Card>
      ) : loadState === 'error' ? (
        <Card className="bp-history__card">
          <EmptyState
            icon="cloud_off"
            title="Không tải được danh sách booking"
            description={loadError}
            action={
              <Button variant="primary" icon="refresh" onClick={() => void loadManagerBookings()}>
                Thử lại
              </Button>
            }
          />
        </Card>
      ) : (
        <>
          {chips}

          {loadError ? (
            <div className="bp-history__notice" role="alert">
              <BpIcon name="warning" size={18} aria-hidden="true" />
              <span>{loadError}</span>
            </div>
          ) : null}

          <Card className="bp-history__card" flush>
            <div className="bp-history__scroll">
              <table className="bp-history__table bp-mgr__table">
                <thead>
                  <tr>
                    <th>Mã booking</th>
                    <th>Khách hàng</th>
                    <th>Sân</th>
                    <th>Thời gian</th>
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
                          title={bookings.length === 0 ? 'Chưa có booking' : 'Không có kết quả phù hợp'}
                          description={
                            bookings.length === 0
                              ? 'Khi khách hàng đặt sân, các lượt đặt sẽ xuất hiện ở đây.'
                              : 'Thử thay đổi bộ lọc trạng thái.'
                          }
                        />
                      </td>
                    </tr>
                  ) : (
                    filtered.map((b) => {
                      const actions = ACTIONS_BY_STATUS[b.Status];
                      return (
                        <tr key={b.BookingId} className={actions.length === 0 ? 'bp-history__row--inert' : ''}>
                          <td className="bp-history__cell--id">
                            <span className="bp-mono bp-history__code">{b.BookingId}</span>
                          </td>
                          <td className="bp-mgr__customer">
                            <div className="bp-mgr__customer-name">{b.CustomerUsername}</div>
                            <div className="bp-mgr__customer-phone">{b.CustomerPhone}</div>
                          </td>
                          <td className="bp-mgr__court">{b.CourtName}</td>
                          <td className="bp-mgr__time">
                            <div className="bp-mgr__time-date">{displayDate(b.StartTime)}</div>
                            <div className="bp-mgr__time-range">
                              {displayTime(b.StartTime)} – {displayTime(b.EndTime)}
                            </div>
                          </td>
                          <td className="bp-history__cost">{formatVnd(Number(b.TotalCost ?? 0))}</td>
                          <td>
                            <StatusBadge status={b.Status} />
                          </td>
                          <td className="bp-mgr__actions">
                            {actions.length === 0 ? (
                              <span className="bp-mgr__noop" aria-hidden="true">
                                —
                              </span>
                            ) : (
                              <div className="bp-mgr__action-group">
                                {actions.map((a) => {
                                  const meta = ACTION_META[a];
                                  return (
                                    <button
                                      key={a}
                                      type="button"
                                      className={[
                                        'bp-mgr__action',
                                        meta.danger ? 'bp-mgr__action--danger' : 'bp-mgr__action--primary',
                                      ].join(' ')}
                                      disabled={mutating !== null}
                                      onClick={() => openConfirm(b, a)}
                                    >
                                      {meta.label}
                                    </button>
                                  );
                                })}
                              </div>
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
              {refreshing ? (
                <span className="bp-mgr__refreshing">
                  <BpIcon name="progress_activity" size={16} aria-hidden="true" />
                  Đang đồng bộ từ cơ sở dữ liệu...
                </span>
              ) : null}
            </div>
          </Card>
        </>
      )}

      {/* -------- Mutation confirm modal (locked Stitch behavior) -------- */}
      {target ? (
        <div className="bp-modal" role="dialog" aria-modal="true" aria-labelledby="bp-mgr-modal-title">
          <div
            className="bp-modal__backdrop"
            onClick={() => {
              if (!mutating) setTarget(null);
            }}
          />
          <div className="bp-modal__panel">
            <div className="bp-modal__body">
              <div
                className={[
                  'bp-modal__icon',
                  ACTION_META[target.action].danger ? 'bp-modal__icon--danger' : 'bp-modal__icon--info',
                ].join(' ')}
              >
                <BpIcon name={ACTION_META[target.action].icon} filled size={26} aria-hidden="true" />
              </div>
              <div className="bp-modal__content">
                <h3 id="bp-mgr-modal-title">{ACTION_META[target.action].confirmTitle}</h3>
                <p className="bp-modal__text">
                  Bạn có chắc chắn muốn {ACTION_META[target.action].label.toLowerCase()} booking{' '}
                  <span className="bp-mono bp-modal__booking-id">{target.booking.BookingId}</span> không?
                </p>
                <p className="bp-modal__court-line">
                  {target.booking.CourtName} · {target.booking.CustomerUsername} · {displayDate(target.booking.StartTime)}{' '}
                  {displayTime(target.booking.StartTime)}–{displayTime(target.booking.EndTime)}
                </p>
                <p className="bp-modal__warn">Trạng thái sau khi duyệt/về cuối sẽ do dữ liệu trong hệ thống quyết định.</p>
                {mutationError ? (
                  <div className="bp-history__alert" role="alert">
                    <BpIcon name="error" size={18} aria-hidden="true" />
                    <span>{mutationError}</span>
                  </div>
                ) : null}
              </div>
            </div>
            <div className="bp-modal__actions">
              <Button variant="outline" onClick={() => setTarget(null)} disabled={mutating !== null}>
                Đóng
              </Button>
              <Button
                variant={ACTION_META[target.action].danger ? 'danger' : 'primary'}
                icon={ACTION_META[target.action].icon}
                loading={mutating !== null}
                keepLabel={mutating !== null}
                disabled={mutating !== null}
                onClick={() => void handleMutationConfirm()}
              >
                {ACTION_META[target.action].confirmLabel}
              </Button>
            </div>
          </div>
        </div>
      ) : null}

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

      {/* -------- Read-only CSDL demo drawer -------- */}
      <DemoDrawer open={demoOpen} onClose={() => setDemoOpen(false)} />
    </div>
  );
}