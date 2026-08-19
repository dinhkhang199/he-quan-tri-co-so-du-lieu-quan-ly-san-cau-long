import { useCallback, useMemo, useState } from 'react';
import type { FormEvent } from 'react';
import { PageHeader } from '../components/PageHeader';
import { Card } from '../components/Card';
import { EmptyState } from '../components/EmptyState';
import { LoadingSkeleton } from '../components/LoadingSkeleton';
import { Button } from '../components/Button';
import { BpIcon } from '../components/BpIcon';
import { CourtCard } from '../components/CourtCard';
import { searchCourtsRequest } from '../api/client';
import { useAuth } from '../auth/AuthContext';
import type { AvailableCourt } from '../../shared/types';

/**
 * Guest/CUSTOMER court search (Phase 2.3).
 *
 * Public, guest-safe. Times are LOCAL WALL-CLOCK values ("YYYY-MM-DDTHH:MM:00",
 * no timezone) which the server passes verbatim to dbo.sp_GetAvailableCourts.
 * Availability is decided by the DB procedure; the client only sorts the
 * returned records. Booking buttons: GUEST -> /login, CUSTOMER -> /booking/:id
 * with the selected window preserved in query parameters (for Phase 2.4).
 */

const FORM_FIELD_MINUTE_UNITS = 30;

function fmtHHMM(totalMinutes: number): string {
  const h = Math.floor(totalMinutes / 60);
  const m = totalMinutes % 60;
  return `${String(h).padStart(2, '0')}:${String(m).padStart(2, '0')}`;
}

function timeToMinutes(value: string): number {
  const [h, m] = value.split(':').map(Number);
  return h * 60 + m;
}

/** All 30-minute slots within 06:00-22:00. */
const TIME_OPTIONS: string[] = (() => {
  const slots: string[] = [];
  for (let m = 6 * 60; m <= 22 * 60; m += FORM_FIELD_MINUTE_UNITS) {
    slots.push(fmtHHMM(m));
  }
  return slots;
})();

/** Start slots that can still fit a 1-hour window (last valid start is 21:00). */
const START_OPTIONS = TIME_OPTIONS.filter((t) => timeToMinutes(t) <= 21 * 60);

function toLocalDateInput(value: Date): string {
  const y = value.getFullYear();
  const mo = String(value.getMonth() + 1).padStart(2, '0');
  const d = String(value.getDate()).padStart(2, '0');
  return `${y}-${mo}-${d}`;
}

/**
 * Deterministic default search window: never in the past, always 06:00-22:00,
 * 30-minute aligned, 1-3h. Prefers the Stitch-like 18:00-20:00 evening slot;
 * falls back to the next valid slot today, and to tomorrow 06:00-07:00 on
 * late nights when today has no valid 1-hour window left.
 */
function defaultSearchWindow(now: Date): { date: string; startTime: string; endTime: string } {
  const today = toLocalDateInput(now);
  if (new Date(`${today}T18:00:00`) > now) {
    return { date: today, startTime: '18:00', endTime: '20:00' };
  }
  const minutes = now.getHours() * 60 + now.getMinutes();
  const boundary = Math.ceil((minutes + 1) / FORM_FIELD_MINUTE_UNITS) * FORM_FIELD_MINUTE_UNITS;
  if (boundary + 60 <= 22 * 60) {
    return { date: today, startTime: fmtHHMM(boundary), endTime: fmtHHMM(boundary + 60) };
  }
  const tomorrow = new Date(now.getFullYear(), now.getMonth(), now.getDate() + 1);
  return { date: toLocalDateInput(tomorrow), startTime: '06:00', endTime: '07:00' };
}

/** "YYYY-MM-DDTHH:MM:00" -> minutes offset from 00:00. */
function fullToMinutes(full: string): number {
  return timeToMinutes(full.slice(11, 16));
}

/** Client-side mirror of the server validation (the server is the real gate). */
function validateClient(startFull: string, endFull: string): string | null {
  const startM = fullToMinutes(startFull);
  const endM = fullToMinutes(endFull);
  if (startM >= endM) return 'Giờ kết thúc phải sau giờ bắt đầu.';
  const duration = endM - startM;
  if (duration < 60) return 'Thời lượng tối thiểu là 1 giờ.';
  if (duration > 180) return 'Thời lượng tối đa là 3 giờ.';
  if (startM < 6 * 60 || endM > 22 * 60) return 'Thời gian phải nằm trong khung hoạt động 06:00–22:00.';
  if (new Date(startFull) <= new Date()) return 'Khung giờ đã chọn đã trôi qua. Vui lòng chọn thời gian trong tương lai.';
  return null;
}

type Phase = 'idle' | 'loading' | 'done' | 'error';
type SortOrder = 'price-asc' | 'price-desc' | 'name';

const SORT_OPTIONS: { value: SortOrder; label: string }[] = [
  { value: 'price-asc', label: 'Giá thấp đến cao' },
  { value: 'price-desc', label: 'Giá cao đến thấp' },
  { value: 'name', label: 'Tên sân A–Z' },
];

export function CourtsPage() {
  const { status, user } = useAuth();
  const isCustomer = status === 'authenticated' && user?.role === 'CUSTOMER';

  const initial = useMemo(() => defaultSearchWindow(new Date()), []);
  const today = useMemo(() => toLocalDateInput(new Date()), []);

  const [date, setDate] = useState(initial.date);
  const [startTime, setStartTime] = useState(initial.startTime);
  const [endTime, setEndTime] = useState(initial.endTime);

  const [phase, setPhase] = useState<Phase>('idle');
  const [formError, setFormError] = useState<string | null>(null);
  const [serverError, setServerError] = useState<string | null>(null);
  const [results, setResults] = useState<AvailableCourt[] | null>(null);
  const [resultWindow, setResultWindow] = useState<{ startTime: string; endTime: string } | null>(null);
  const [sortOrder, setSortOrder] = useState<SortOrder>('price-asc');

  // End options constrained to [start+1h, start+3h] within 22:00 so the UI can
  // only produce valid 1-3h windows.
  const startMin = timeToMinutes(startTime);
  const endOptions = useMemo(() => {
    const from = startMin + 60;
    const to = startMin + 180;
    return TIME_OPTIONS.filter((t) => {
      const m = timeToMinutes(t);
      return m >= from && m <= to && m <= 22 * 60;
    });
  }, [startMin]);

  function handleStartChange(value: string): void {
    setStartTime(value);
    const sm = timeToMinutes(value);
    if (timeToMinutes(endTime) <= sm) {
      setEndTime(fmtHHMM(Math.min(sm + 60, 22 * 60)));
    }
  }

  const runSearch = useCallback(async (startFull: string, endFull: string) => {
    setPhase('loading');
    setResults(null);
    setResultWindow(null);
    setServerError(null);
    try {
      const data = await searchCourtsRequest({ startTime: startFull, endTime: endFull });
      setResults(data.courts);
      setResultWindow({ startTime: startFull, endTime: endFull });
      setPhase('done');
    } catch (err) {
      setServerError(err instanceof Error ? err.message : 'Có lỗi từ hệ thống. Vui lòng thử lại.');
      setPhase('error');
    }
  }, []);

  function handleSubmit(event: FormEvent<HTMLFormElement>): void {
    event.preventDefault();
    if (phase === 'loading') return;
    const startFull = `${date}T${startTime}:00`;
    const endFull = `${date}T${endTime}:00`;
    const clientError = validateClient(startFull, endFull);
    if (clientError) {
      setFormError(clientError);
      setResults(null);
      setResultWindow(null);
      setPhase('idle');
      return;
    }
    setFormError(null);
    void runSearch(startFull, endFull);
  }

  const sortedResults = useMemo(() => {
    if (!results) return [];
    const arr = [...results];
    if (sortOrder === 'price-asc') arr.sort((a, b) => a.PricePerHour - b.PricePerHour);
    else if (sortOrder === 'price-desc') arr.sort((a, b) => b.PricePerHour - a.PricePerHour);
    else arr.sort((a, b) => a.CourtName.localeCompare(b.CourtName, 'vi'));
    return arr;
  }, [results, sortOrder]);

  const loading = phase === 'loading';

  return (
    <div className="bp-courts">
      <PageHeader title="Tìm sân cầu lông" subtitle="Khám phá và tìm sân cầu lông còn trống tại khu vực của bạn." />

      <div className="bp-courts__grid">
        {/* Filter panel */}
        <aside className="bp-courts__aside">
          <div className="bp-courts__filter">
            <h2 className="bp-courts__filter-title">
              <BpIcon name="tune" size={20} aria-hidden="true" />
              Bộ lọc tìm kiếm
            </h2>
            <form onSubmit={handleSubmit} noValidate>
              <div className="bp-courts__field">
                <label className="bp-courts__label" htmlFor="cs-date">
                  Ngày đặt sân
                </label>
                <div className="bp-courts__control">
                  <span className="bp-courts__control-icon">
                    <BpIcon name="calendar_today" size={18} aria-hidden="true" />
                  </span>
                  <input
                    id="cs-date"
                    type="date"
                    className="bp-courts__input"
                    value={date}
                    min={today}
                    onChange={(e) => setDate(e.target.value)}
                    disabled={loading}
                  />
                </div>
              </div>

              <div className="bp-courts__two">
                <div className="bp-courts__field">
                  <label className="bp-courts__label" htmlFor="cs-start">
                    Từ giờ
                  </label>
                  <div className="bp-courts__control">
                    <span className="bp-courts__control-icon">
                      <BpIcon name="schedule" size={18} aria-hidden="true" />
                    </span>
                    <select
                      id="cs-start"
                      className="bp-courts__input"
                      value={startTime}
                      onChange={(e) => handleStartChange(e.target.value)}
                      disabled={loading}
                    >
                      {START_OPTIONS.map((t) => (
                        <option key={t} value={t}>
                          {t}
                        </option>
                      ))}
                    </select>
                    <span className="bp-courts__control-chev">
                      <BpIcon name="expand_more" size={18} aria-hidden="true" />
                    </span>
                  </div>
                </div>
                <div className="bp-courts__field">
                  <label className="bp-courts__label" htmlFor="cs-end">
                    Đến giờ
                  </label>
                  <div className="bp-courts__control">
                    <span className="bp-courts__control-icon">
                      <BpIcon name="schedule" size={18} aria-hidden="true" />
                    </span>
                    <select
                      id="cs-end"
                      className="bp-courts__input"
                      value={endTime}
                      onChange={(e) => setEndTime(e.target.value)}
                      disabled={loading}
                    >
                      {endOptions.map((t) => (
                        <option key={t} value={t}>
                          {t}
                        </option>
                      ))}
                    </select>
                    <span className="bp-courts__control-chev">
                      <BpIcon name="expand_more" size={18} aria-hidden="true" />
                    </span>
                  </div>
                </div>
              </div>

              {formError ? (
                <div className="bp-courts__form-error" role="alert">
                  <BpIcon name="error" size={18} aria-hidden="true" />
                  <span>{formError}</span>
                </div>
              ) : null}

              <Button
                type="submit"
                variant="primary"
                size="lg"
                fullWidth
                icon="search"
                loading={loading}
                disabled={loading}
                className="bp-courts__submit"
              >
                Tìm sân trống
              </Button>
            </form>
          </div>
        </aside>

        {/* Results */}
        <section className="bp-courts__results" aria-live="polite">
          {phase === 'done' && results ? (
            <div className="bp-courts__meta">
              <p className="bp-courts__found">Tìm thấy {results.length} sân trống</p>
              <div className="bp-courts__sort">
                <label className="bp-courts__sort-label" htmlFor="cs-sort">
                  Sắp xếp:
                </label>
                <select
                  id="cs-sort"
                  className="bp-courts__sort-select"
                  value={sortOrder}
                  onChange={(e) => setSortOrder(e.target.value as SortOrder)}
                >
                  {SORT_OPTIONS.map((o) => (
                    <option key={o.value} value={o.value}>
                      {o.label}
                    </option>
                  ))}
                </select>
              </div>
            </div>
          ) : null}

          {phase === 'loading' ? (
            <div className="bp-courts__loading">
              <LoadingSkeleton variant="card" rows={3} />
            </div>
          ) : null}

          {phase === 'error' ? (
            <Card>
              <EmptyState
                icon="cloud_off"
                title="Không thể tải danh sách sân"
                description={serverError ?? 'Hệ thống đang gặp sự cố. Vui lòng thử lại sau.'}
                action={
                  <Button variant="primary" icon="refresh" onClick={() => void runSearch(`${date}T${startTime}:00`, `${date}T${endTime}:00`)}>
                    Thử lại
                  </Button>
                }
              />
            </Card>
          ) : null}

          {phase === 'done' && results && results.length > 0 && resultWindow ? (
            <div className="bp-courts__list">
              {sortedResults.map((court) => (
                <CourtCard
                  key={court.CourtId}
                  court={court}
                  startTime={resultWindow.startTime}
                  endTime={resultWindow.endTime}
                  isCustomer={isCustomer}
                />
              ))}
            </div>
          ) : null}

          {phase === 'done' && results && results.length === 0 ? (
            <Card>
              <EmptyState
                icon="event_busy"
                title="Không có sân trống trong khung giờ này"
                description="Hãy thử đổi ngày hoặc khung giờ khác để xem thêm sân còn trống."
              />
            </Card>
          ) : null}

          {phase === 'idle' ? (
            <Card>
              <EmptyState
                icon="search"
                title="Tìm sân cầu lông trống"
                description="Chọn ngày và giờ, sau đó bấm “Tìm sân trống” để xem danh sách sân còn trống theo dữ liệu thực từ hệ thống."
              />
            </Card>
          ) : null}
        </section>
      </div>
    </div>
  );
}