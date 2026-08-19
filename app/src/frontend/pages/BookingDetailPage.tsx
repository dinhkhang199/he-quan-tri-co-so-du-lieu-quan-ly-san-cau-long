import { useCallback, useEffect, useMemo, useState } from 'react';
import { useNavigate, useParams, useSearchParams, NavLink } from 'react-router-dom';
import { Card } from '../components/Card';
import { Button } from '../components/Button';
import { StatusBadge } from '../components/StatusBadge';
import { EmptyState } from '../components/EmptyState';
import { LoadingSkeleton } from '../components/LoadingSkeleton';
import { BpIcon } from '../components/BpIcon';
import { bookCourtRequest, costEstimateRequest, searchCourtsRequest } from '../api/client';
import type { AvailableCourt, BookingResult } from '../../shared/types';

/**
 * Customer booking detail (Phase 2.4) — locked chi_ti_t_t_s_n_badmintonpro_final_polish.
 *
 * Flow:
 * 1. Parse /booking/:courtId?startTime=...&endTime=... (local wall-clock, set by
 *    the Phase 2.3 CTA).
 * 2. Re-check availability via the PUBLIC dbo.sp_GetAvailableCourts (shared pool,
 *    never touches the authenticated SQL session) and show the court's real DB data.
 * 3. Confirm sends ONE POST /api/bookings; dbo.sp_BookCourt is the final authority
 *    (availability, price, overlap). Result echoes the DB-returned PENDING row.
 *
 * No client-side cost is computed or shown before submit — the cost comes from
 * dbo.sp_BookCourt output only. Times are local wall-clock values.
 */

const GUID_RE = /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/;
const FULL_RE = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})$/;
const STEP_MINUTES = 30;

function fmtHHMM(totalMinutes: number): string {
  const h = Math.floor(totalMinutes / 60);
  const m = totalMinutes % 60;
  return `${String(h).padStart(2, '0')}:${String(m).padStart(2, '0')}`;
}

function timeToMinutes(value: string): number {
  const [h, m] = value.split(':').map(Number);
  return h * 60 + m;
}

function toLocalDateInput(value: Date): string {
  const y = value.getFullYear();
  const mo = String(value.getMonth() + 1).padStart(2, '0');
  const d = String(value.getDate()).padStart(2, '0');
  return `${y}-${mo}-${d}`;
}

/** All 30-minute slots within 06:00-22:00. */
const TIME_OPTIONS: string[] = (() => {
  const slots: string[] = [];
  for (let m = 6 * 60; m <= 22 * 60; m += STEP_MINUTES) {
    slots.push(fmtHHMM(m));
  }
  return slots;
})();

/** Start slots that can still fit a 1-hour window (last valid start is 21:00). */
const START_OPTIONS = TIME_OPTIONS.filter((t) => timeToMinutes(t) <= 21 * 60);

function formatVnd(value: number): string {
  return `${new Intl.NumberFormat('vi-VN').format(value)}đ`;
}

function formatDuration(minutes: number): string {
  const h = Math.floor(minutes / 60);
  const m = minutes % 60;
  if (m === 0) return `${h} giờ`;
  return `${h} giờ ${m} phút`;
}

function surfaceLabel(value: string): string {
  if (value === 'VIP') return 'Sân VIP';
  if (value === 'STANDARD') return 'Sân tiêu chuẩn';
  return value;
}

type Availability = 'checking' | 'available' | 'unavailable';

export function BookingDetailPage() {
  const { courtId } = useParams<{ courtId: string }>();
  const [searchParams] = useSearchParams();
  const navigate = useNavigate();

  const [parseError, setParseError] = useState<string | null>(null);
  const [initialized, setInitialized] = useState(false);

  const [date, setDate] = useState('');
  const [startTime, setStartTime] = useState('');
  const [endTime, setEndTime] = useState('');

  const [court, setCourt] = useState<AvailableCourt | null>(null);
  const [availability, setAvailability] = useState<Availability>('checking');
  const [loadError, setLoadError] = useState<string | null>(null);

  const [estimate, setEstimate] = useState<number | null>(null);
  const [estimateUnavailable, setEstimateUnavailable] = useState(false);

  const [submitting, setSubmitting] = useState(false);
  const [submitError, setSubmitError] = useState<string | null>(null);
  const [created, setCreated] = useState<BookingResult | null>(null);

  /* ----- Parse the URL once ----------------------------------------- */
  useEffect(() => {
    const rawStart = searchParams.get('startTime');
    const rawEnd = searchParams.get('endTime');

    if (!courtId || !GUID_RE.test(courtId)) {
      setParseError('Mã sân (courtId) không hợp lệ.');
      return;
    }
    const s = rawStart ? FULL_RE.exec(rawStart) : null;
    const e = rawEnd ? FULL_RE.exec(rawEnd) : null;
    if (!s || !e || s[3] !== e[3] || s[2] !== e[2] || s[1] !== e[1]) {
      setParseError('Khung giờ đặt sân không hợp lệ.');
      return;
    }
    setDate(`${s[1]}-${s[2]}-${s[3]}`);
    setStartTime(`${s[4]}:${s[5]}`);
    setEndTime(`${e[4]}:${e[5]}`);
    setInitialized(true);
  }, [courtId, searchParams]);

  /* ----- Availability + court data + DB-side estimate ---------------- */
  const runLoad = useCallback(async () => {
    if (!courtId) return;
    const fullStart = `${date}T${startTime}:00`;
    const fullEnd = `${date}T${endTime}:00`;
    setAvailability('checking');
    setLoadError(null);
    try {
      // Availability (search) + pre-confirm cost (est) run in parallel. The
      // estimate comes from dbo.fn_CalculateBookingCost on the server; a failure
      // or a null result only hides the "Chi phí dự kiến" row, it never blocks
      // booking (the real cost is returned by sp_BookCourt after submit).
      const [searchData, estimateRes] = await Promise.all([
        searchCourtsRequest({ startTime: fullStart, endTime: fullEnd }),
        costEstimateRequest({ courtId, startTime: fullStart, endTime: fullEnd }).catch(() => null),
      ]);
      const found = searchData.courts.find((c) => c.CourtId.toLowerCase() === courtId.toLowerCase()) ?? null;
      if (found) setCourt(found);
      setAvailability(found ? 'available' : 'unavailable');
      if (estimateRes && estimateRes.totalCost != null) {
        setEstimate(estimateRes.totalCost);
        setEstimateUnavailable(false);
      } else {
        setEstimate(null);
        setEstimateUnavailable(true);
      }
    } catch (err) {
      setLoadError(err instanceof Error ? err.message : 'Có lỗi từ hệ thống. Vui lòng thử lại.');
      setAvailability('unavailable');
      setEstimate(null);
      setEstimateUnavailable(true);
    }
  }, [courtId, date, startTime, endTime]);

  useEffect(() => {
    if (initialized) {
      void runLoad();
    }
  }, [initialized, runLoad]);

  /* ----- Client-side window validation (server remains the gate) ----- */
  const windowError = useMemo<string | null>(() => {
    if (!date || !startTime || !endTime) return 'Vui lòng chọn ngày, giờ bắt đầu và giờ kết thúc.';
    const sm = timeToMinutes(startTime);
    const em = timeToMinutes(endTime);
    if (sm >= em) return 'Giờ kết thúc phải sau giờ bắt đầu.';
    const duration = em - sm;
    if (duration < 60) return 'Thời lượng tối thiểu là 1 giờ.';
    if (duration > 180) return 'Thời lượng tối đa là 3 giờ.';
    if (sm < 6 * 60 || em > 22 * 60) return 'Thời gian đặt phải nằm trong khung hoạt động 06:00–22:00.';
    const full = `${date}T${startTime}:00`;
    if (new Date(full).getTime() <= new Date().getTime()) {
      return 'Khung giờ đã chọn đã trôi qua. Vui lòng chọn thời gian trong tương lai.';
    }
    return null;
  }, [date, startTime, endTime]);

  const durationMinutes = useMemo(() => {
    if (!startTime || !endTime) return null;
    return timeToMinutes(endTime) - timeToMinutes(startTime);
  }, [startTime, endTime]);

  const today = useMemo(() => toLocalDateInput(new Date()), []);

  // End options constrained to [start+1h, start+3h] within 22:00.
  const endOptions = useMemo(() => {
    const from = timeToMinutes(startTime) + 60;
    const to = timeToMinutes(startTime) + 180;
    return TIME_OPTIONS.filter((t) => {
      const m = timeToMinutes(t);
      return m >= from && m <= to && m <= 22 * 60;
    });
  }, [startTime]);

  function handleStartChange(value: string): void {
    setStartTime(value);
    const sm = timeToMinutes(value);
    if (timeToMinutes(endTime) <= sm) {
      setEndTime(fmtHHMM(Math.min(sm + 60, 22 * 60)));
    }
  }

  const canConfirm = availability === 'available' && windowError === null && loadError === null && !submitting && !created;

  async function handleSubmit(): Promise<void> {
    if (!canConfirm || !courtId) return;
    setSubmitting(true);
    setSubmitError(null);
    try {
      const res = await bookCourtRequest({
        courtId,
        startTime: `${date}T${startTime}:00`,
        endTime: `${date}T${endTime}:00`,
      });
      setCreated(res.booking);
    } catch (err) {
      setSubmitError(err instanceof Error ? err.message : 'Có lỗi từ hệ thống. Vui lòng thử lại.');
    } finally {
      setSubmitting(false);
    }
  }

  /* ----- Render ------------------------------------------------------ */
  if (parseError) {
    return (
      <Card>
        <EmptyState
          icon="link_off"
          title="Đường dẫn đặt sân không hợp lệ"
          description={parseError}
          action={
            <NavLink to="/courts">
              <Button variant="primary" icon="arrow_back">
                Về trang tìm sân
              </Button>
            </NavLink>
          }
        />
      </Card>
    );
  }

  const availabilityLabel =
    availability === 'available' ? (
      <span className="bp-booking__available">
        <span className="bp-booking__dot" aria-hidden="true" />
        Còn trống
      </span>
    ) : availability === 'unavailable' ? (
      <span className="bp-booking__available bp-booking__available--busy">
        <span className="bp-booking__dot" aria-hidden="true" />
        Đã được đặt
      </span>
    ) : null;

  return (
    <div className="bp-booking">
      <div className="bp-booking__grid">
        {/* -------- Left: court summary + rules -------- */}
        <aside className="bp-booking__aside">
          {availability === 'checking' && !court ? (
            <div className="bp-booking__card">
              <LoadingSkeleton variant="card" rows={4} />
            </div>
          ) : (
            <Card className="bp-booking__card">
              <div className="bp-booking__media">
                <div className="bp-booking__media-fallback" aria-hidden="true">
                  <BpIcon name="sports_badminton" size={52} />
                  <span>BadmintonPro</span>
                </div>
                {availabilityLabel}
              </div>
              <div className="bp-booking__card-body">
                <h2 className="bp-booking__name">{court?.CourtName ?? 'Sân không xác định'}</h2>
                <p className="bp-booking__address">
                  <BpIcon name="location_on" size={18} aria-hidden="true" />
                  {court?.Address ?? 'Không có thông tin địa chỉ.'}
                </p>
                <div className="bp-booking__rows">
                  <div className="bp-booking__row">
                    <span className="bp-booking__row-label">Loại sân</span>
                    <span className="bp-booking__row-value">{court ? surfaceLabel(court.SurfaceType) : '—'}</span>
                  </div>
                  <div className="bp-booking__row">
                    <span className="bp-booking__row-label">Giá theo giờ</span>
                    <span className="bp-booking__row-value bp-booking__price">
                      {court ? formatVnd(court.PricePerHour) : '—'}
                    </span>
                  </div>
                  <div className="bp-booking__row">
                    <span className="bp-booking__row-label">3 giờ</span>
                    <span className="bp-booking__row-value bp-booking__price">
                      {court ? formatVnd(court.PricePerThreeHours) : '—'}
                    </span>
                  </div>
                </div>
              </div>
            </Card>
          )}

          <Card className="bp-booking__card">
            <h3 className="bp-booking__rules-title">
              <BpIcon name="gavel" size={20} aria-hidden="true" />
              Quy tắc đặt sân
            </h3>
            <ul className="bp-booking__rules">
              <li className="bp-booking__rule">
                <BpIcon name="schedule" size={20} aria-hidden="true" />
                <div>
                  <p className="bp-booking__rule-title">Giờ hoạt động</p>
                  <p className="bp-booking__rule-desc">06:00 – 22:00 hàng ngày</p>
                </div>
              </li>
              <li className="bp-booking__rule">
                <BpIcon name="timer" size={20} aria-hidden="true" />
                <div>
                  <p className="bp-booking__rule-title">Thời lượng</p>
                  <p className="bp-booking__rule-desc">Tối thiểu 1 giờ, tối đa 3 giờ; chọn theo bước 30 phút.</p>
                </div>
              </li>
              <li className="bp-booking__rule">
                <BpIcon name="event_busy" size={20} aria-hidden="true" />
                <div>
                  <p className="bp-booking__rule-title">Hủy sân</p>
                  <p className="bp-booking__rule-desc">
                    Booking PENDING có thể hủy. Booking BOOKED chỉ được khách tự hủy khi còn ít nhất 3 giờ trước giờ bắt đầu.
                  </p>
                </div>
              </li>
            </ul>
          </Card>
        </aside>

        {/* -------- Right: form / result -------- */}
        <section className="bp-booking__main">
          {created ? (
            <Card className="bp-booking__card">
              <div className="bp-booking__success">
                <div className="bp-booking__success-icon">
                  <BpIcon name="check_circle" size={44} aria-hidden="true" />
                </div>
                <h2 className="bp-booking__success-title">Đã gửi yêu cầu đặt sân</h2>
                <p className="bp-booking__success-text">Yêu cầu đặt sân của bạn đang chờ quản lý duyệt.</p>

                <div className="bp-booking__success-status">
                  <StatusBadge status="PENDING" />
                </div>

                <dl className="bp-booking__success-rows">
                  <div className="bp-booking__row">
                    <dt className="bp-booking__row-label">Mã đặt sân</dt>
                    <dd className="bp-booking__row-value bp-mono bp-booking__code">{created.BookingId}</dd>
                  </div>
                  <div className="bp-booking__row">
                    <dt className="bp-booking__row-label">Sân</dt>
                    <dd className="bp-booking__row-value">{court?.CourtName ?? '—'}</dd>
                  </div>
                  <div className="bp-booking__row">
                    <dt className="bp-booking__row-label">Khung giờ</dt>
                    <dd className="bp-booking__row-value">
                      {created.StartTime.slice(11, 16)} – {created.EndTime.slice(11, 16)} ({created.StartTime.slice(0, 10)})
                    </dd>
                  </div>
                  <div className="bp-booking__row">
                    <dt className="bp-booking__row-label">Chi phí</dt>
                    <dd className="bp-booking__row-value bp-booking__price">{formatVnd(created.TotalCost)}</dd>
                  </div>
                </dl>

                <div className="bp-booking__actions">
                  <NavLink to="/my-bookings">
                    <Button variant="primary" icon="history">
                      Xem lịch sử đặt sân
                    </Button>
                  </NavLink>
                  <NavLink to="/courts">
                    <Button variant="outline" icon="search">
                      Về tìm sân
                    </Button>
                  </NavLink>
                </div>
              </div>
            </Card>
          ) : (
            <Card className="bp-booking__card">
              <h2 className="bp-booking__form-title">Chi tiết đặt sân</h2>

              <form
                className="bp-booking__form"
                onSubmit={(e) => {
                  e.preventDefault();
                  void handleSubmit();
                }}
                noValidate
              >
                <div className="bp-booking__field">
                  <label className="bp-booking__label" htmlFor="bk-date">
                    Ngày đặt
                  </label>
                  <div className="bp-booking__control">
                    <span className="bp-booking__control-icon">
                      <BpIcon name="calendar_month" size={18} aria-hidden="true" />
                    </span>
                    <input
                      id="bk-date"
                      type="date"
                      className="bp-booking__input"
                      value={date}
                      min={today}
                      onChange={(e) => setDate(e.target.value)}
                      disabled={submitting}
                    />
                  </div>
                </div>

                <div className="bp-booking__two">
                  <div className="bp-booking__field">
                    <label className="bp-booking__label" htmlFor="bk-start">
                      Giờ bắt đầu
                    </label>
                    <div className="bp-booking__control">
                      <span className="bp-booking__control-icon">
                        <BpIcon name="schedule" size={18} aria-hidden="true" />
                      </span>
                      <select
                        id="bk-start"
                        className="bp-booking__input"
                        value={startTime}
                        onChange={(e) => handleStartChange(e.target.value)}
                        disabled={submitting}
                      >
                        {START_OPTIONS.map((t) => (
                          <option key={t} value={t}>
                            {t}
                          </option>
                        ))}
                      </select>
                      <span className="bp-booking__control-chev">
                        <BpIcon name="expand_more" size={18} aria-hidden="true" />
                      </span>
                    </div>
                  </div>
                  <div className="bp-booking__field">
                    <label className="bp-booking__label" htmlFor="bk-end">
                      Giờ kết thúc
                    </label>
                    <div className="bp-booking__control">
                      <span className="bp-booking__control-icon">
                        <BpIcon name="schedule" size={18} aria-hidden="true" />
                      </span>
                      <select
                        id="bk-end"
                        className="bp-booking__input"
                        value={endTime}
                        onChange={(e) => setEndTime(e.target.value)}
                        disabled={submitting}
                      >
                        {endOptions.map((t) => (
                          <option key={t} value={t}>
                            {t}
                          </option>
                        ))}
                      </select>
                      <span className="bp-booking__control-chev">
                        <BpIcon name="expand_more" size={18} aria-hidden="true" />
                      </span>
                    </div>
                  </div>
                </div>

                <div className="bp-booking__summary">
                  <div className="bp-booking__summary-item">
                    <span className="bp-booking__summary-label">Thời lượng</span>
                    <span className="bp-booking__summary-value">
                      {durationMinutes != null && durationMinutes > 0 ? formatDuration(durationMinutes) : '—'}
                    </span>
                  </div>
                  <div className="bp-booking__summary-item bp-booking__summary-item--end">
                    <span className="bp-booking__summary-label">Chi phí dự kiến</span>
                    <span className="bp-booking__summary-value bp-booking__price">
                      {estimateUnavailable || estimate == null ? '—' : formatVnd(estimate)}
                    </span>
                  </div>
                </div>

                {availability === 'unavailable' && !loadError ? (
                  <div className="bp-booking__alert" role="alert">
                    <BpIcon name="event_busy" size={18} aria-hidden="true" />
                    <span>Sân không còn trống trong khung giờ này. Vui lòng chọn khung giờ khác.</span>
                  </div>
                ) : null}

                {windowError ? (
                  <div className="bp-booking__alert" role="alert">
                    <BpIcon name="error" size={18} aria-hidden="true" />
                    <span>{windowError}</span>
                  </div>
                ) : null}

                {loadError ? (
                  <div className="bp-booking__alert" role="alert">
                    <BpIcon name="cloud_off" size={18} aria-hidden="true" />
                    <span>{loadError}</span>
                  </div>
                ) : null}

                {submitError ? (
                  <div className="bp-booking__alert" role="alert">
                    <BpIcon name="error" size={18} aria-hidden="true" />
                    <span>{submitError}</span>
                  </div>
                ) : null}

                <div className="bp-booking__actions">
                  <Button type="button" variant="outline" icon="arrow_back" onClick={() => navigate('/courts')} disabled={submitting}>
                    Quay lại
                  </Button>
                  <Button
                    type="submit"
                    variant="primary"
                    icon="check_circle"
                    loading={submitting}
                    disabled={!canConfirm}
                    keepLabel={submitting}
                  >
                    Xác nhận đặt sân
                  </Button>
                </div>
              </form>
            </Card>
          )}
        </section>
      </div>
    </div>
  );
}
