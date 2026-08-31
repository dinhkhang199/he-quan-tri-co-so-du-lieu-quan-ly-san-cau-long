import { useCallback, useEffect, useMemo, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { PageHeader } from '../../components/PageHeader';
import { Card } from '../../components/Card';
import { Button } from '../../components/Button';
import { EmptyState } from '../../components/EmptyState';
import { LoadingSkeleton } from '../../components/LoadingSkeleton';
import { BpIcon } from '../../components/BpIcon';
import { useAuth } from '../../auth/AuthContext';
import { ApiError, getManagerDashboardRequest } from '../../api/client';
import type { DashboardDailyRevenue, DashboardTopCourt, ManagerDashboardResponse } from '../../../shared/types';

/** Project VND formatting (existing convention: vi-VN + đ suffix). */
function formatVnd(value: number): string {
  return `${new Intl.NumberFormat('vi-VN').format(value)}đ`;
}

/** "DD/MM" label from the SQL DATE serialized as an ISO string (wall-clock digits). */
function dayLabel(value: Date | string): string {
  const iso = typeof value === 'string' ? value : value.toISOString();
  const [y, m, d] = iso.slice(0, 10).split('-');
  return y && m && d ? `${d}/${m}` : iso;
}

type KpiTone = 'pending' | 'booked' | 'users' | 'revenue';

interface KpiCardProps {
  label: string;
  value: string;
  icon: string;
  tone: KpiTone;
  footer: string;
}

/** Locked four KPI chips (t_ng_quan_h_th_ng_..._manager_production_final). */
function KpiCard({ label, value, icon, tone, footer }: KpiCardProps) {
  return (
    <div className={['bp-dash-kpi', `bp-dash-kpi--${tone}`].filter(Boolean).join(' ')}>
      <div className="bp-dash-kpi__row">
        <div className="bp-dash-kpi__text">
          <p className="bp-dash-kpi__label">{label}</p>
          <span className="bp-dash-kpi__value">{value}</span>
        </div>
        <div className="bp-dash-kpi__icon">
          <BpIcon name={icon} size={26} aria-hidden="true" />
        </div>
      </div>
      <div className="bp-dash-kpi__foot">{footer}</div>
      <div className="bp-dash-kpi__blob" aria-hidden="true" />
    </div>
  );
}

/** Lightweight CSS bar chart of the real daily revenue series (no chart lib). */
function RevenueChart({ daily }: { daily: DashboardDailyRevenue[] }) {
  const max = useMemo(() => Math.max(...daily.map((d) => d.DailyRevenue), 0), [daily]);

  if (daily.length === 0) {
    return (
      <div className="bp-dash__inline-empty">
        <EmptyState
          icon="insights"
          title="Chưa có dữ liệu doanh thu"
          description="Không có booking BOOKED/COMPLETED trong 7 ngày gần nhất."
        />
      </div>
    );
  }

  return (
    <div className="bp-dash-chart" role="img" aria-label="Biểu đồ doanh thu lý thuyết 7 ngày gần nhất">
      {daily.map((d) => {
        const ratio = max > 0 ? d.DailyRevenue / max : 0;
        const heightPct = ratio > 0 ? Math.max(4, ratio * 100) : 0;
        return (
          <div className="bp-dash-chart__col" key={String(d.Date)}>
            <div className="bp-dash-chart__track">
              <div
                className="bp-dash-chart__fill"
                style={{ height: `${heightPct}%` }}
                title={`${dayLabel(d.Date)}: ${formatVnd(d.DailyRevenue)}`}
                aria-label={`${dayLabel(d.Date)}: ${formatVnd(d.DailyRevenue)}`}
              />
            </div>
            <span className="bp-dash-chart__tip" aria-hidden="true">
              <strong>{dayLabel(d.Date)}</strong>
              {formatVnd(d.DailyRevenue)}
            </span>
            <span className="bp-dash-chart__day">{dayLabel(d.Date)}</span>
          </div>
        );
      })}
    </div>
  );
}

/** Top courts, ranked by the SP's actual ORDER BY (Revenue DESC). */
function TopCourtsPanel({ courts }: { courts: DashboardTopCourt[] }) {
  if (courts.length === 0) {
    return (
      <div className="bp-dash__inline-empty">
        <EmptyState
          icon="leaderboard"
          title="Chưa có dữ liệu xếp hạng"
          description="Không có booking BOOKED/COMPLETED để xếp hạng sân."
        />
      </div>
    );
  }

  return (
    <ol className="bp-dash-courts">
      {courts.map((court, i) => (
        <li className="bp-dash-courts__item" key={`${court.CourtName}-${i}`}>
          <span className="bp-dash-courts__rank" aria-hidden="true">
            {i + 1}
          </span>
          <div className="bp-dash-courts__info">
            <h4 className="bp-dash-courts__name">{court.CourtName}</h4>
            <p className="bp-dash-courts__meta">
              {new Intl.NumberFormat('vi-VN').format(court.BookingCount)} booking · {formatVnd(court.Revenue)}
            </p>
          </div>
          <span className="bp-dash-courts__icon" aria-hidden="true">
            <BpIcon name="stadium" size={20} />
          </span>
        </li>
      ))}
    </ol>
  );
}

/**
 * MANAGER / COURT_MANAGER dashboard (Phase 2.9) — locked
 * t_ng_quan_h_th_ng_badmintonpro_manager_production_final.
 *
 * All numbers come from dbo.sp_GetDashboard on the authenticated SQL session;
 * the scope (MANAGER system-wide / COURT_MANAGER owned courts) is applied INSIDE
 * SQL Server, so this page never recomputes or re-filters authoritative
 * aggregates. "Theoretical revenue" is booking value (BOOKED + COMPLETED), not
 * money received. There is NO growth/trend figure here — the Stored Procedure
 * does not compute one and the design samples must not be fabricated.
 */
export function ManagerDashboardPage() {
  const navigate = useNavigate();
  const { logout } = useAuth();

  type LoadState = 'loading' | 'ready' | 'error';
  const [loadState, setLoadState] = useState<LoadState>('loading');
  const [data, setData] = useState<ManagerDashboardResponse | null>(null);
  const [loadError, setLoadError] = useState<string | null>(null);

  const loadDashboard = useCallback(async () => {
    setLoadState('loading');
    setLoadError(null);
    try {
      const res = await getManagerDashboardRequest();
      setData(res);
      setLoadState('ready');
    } catch (err) {
      const message = err instanceof Error ? err.message : 'Có lỗi từ hệ thống. Vui lòng thử lại.';
      setLoadError(message);
      setLoadState('error');
      if (err instanceof ApiError && err.status === 401) {
        await logout();
        navigate('/login', { replace: true });
      }
    }
  }, [logout, navigate]);

  useEffect(() => {
    void loadDashboard();
  }, [loadDashboard]);

  // Truthful, non-interactive period note: the SP's daily result set is a fixed
  // 7-day window ending today; the Stitch "Hôm nay/7 ngày/30 ngày" control has
  // no SP support, so it is omitted rather than faked.
  const periodPill = (
    <div className="bp-dash__period" role="note">
      <BpIcon name="calendar_today" size={16} aria-hidden="true" />
      <span>7 ngày gần nhất</span>
    </div>
  );

  const { overview } = data ?? { overview: null };
  const countFmt = new Intl.NumberFormat('vi-VN');

  return (
    <div className="bp-dash">
      <PageHeader
        title="Tổng quan hệ thống"
        subtitle="Theo dõi tình hình booking, sân và các chỉ số vận hành chính."
        actions={periodPill}
      />

      {loadState === 'loading' ? (
        <div className="bp-dash__loading" aria-busy="true">
          <div className="bp-dash__kpis">
            {Array.from({ length: 4 }, (_, i) => (
              <LoadingSkeleton key={i} variant="card" />
            ))}
          </div>
          <div className="bp-dash__analytics">
            <LoadingSkeleton variant="card" className="bp-dash__analytics-chart" />
            <LoadingSkeleton variant="card" className="bp-dash__analytics-top" />
          </div>
        </div>
      ) : loadState === 'error' ? (
        <EmptyState
          icon="cloud_off"
          title="Không tải được dữ liệu tổng quan"
          description={loadError}
          action={
            <Button variant="primary" icon="refresh" onClick={() => void loadDashboard()}>
              Thử lại
            </Button>
          }
        />
      ) : data && overview ? (
        <div className="bp-dash__body">
          <div className="bp-dash__kpis">
            <KpiCard
              label="Chờ duyệt (PENDING)"
              value={countFmt.format(overview.PendingCount)}
              icon="pending_actions"
              tone="pending"
              footer="Booking đang chờ xử lý"
            />
            <KpiCard
              label="Đã xác nhận (BOOKED)"
              value={countFmt.format(overview.BookedCount)}
              icon="event_available"
              tone="booked"
              footer="Booking đã được xác nhận"
            />
            <KpiCard
              label="Người dùng hoạt động"
              value={countFmt.format(overview.ActiveUsers)}
              icon="group"
              tone="users"
              footer="Tài khoản đang hoạt động (IsActive = 1)"
            />
            <KpiCard
              label="Doanh thu lý thuyết"
              value={formatVnd(overview.TheoreticalRevenue)}
              icon="payments"
              tone="revenue"
              footer="Tổng giá trị booking BOOKED + COMPLETED"
            />
          </div>

          <div className="bp-dash__analytics">
            <Card heading="Doanh thu lý thuyết theo ngày" className="bp-dash__chart-card">
              <p className="bp-dash__card-sub">7 ngày gần nhất</p>
              <RevenueChart daily={data.daily} />
            </Card>
            <Card heading="Top sân" className="bp-dash__courts-card">
              <p className="bp-dash__card-sub">Xếp hạng theo doanh thu lý thuyết</p>
              <TopCourtsPanel courts={data.topCourts} />
            </Card>
          </div>
        </div>
      ) : null}
    </div>
  );
}
