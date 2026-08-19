import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { PageHeader } from '../../components/PageHeader';
import { Button } from '../../components/Button';
import { Input } from '../../components/Input';
import { EmptyState } from '../../components/EmptyState';
import { LoadingSkeleton } from '../../components/LoadingSkeleton';
import { BpIcon } from '../../components/BpIcon';
import {
  ApiError,
  createCourtRequest,
  deactivateCourtRequest,
  getManagerCourtsRequest,
  updateCourtRequest,
} from '../../api/client';
import { useAuth } from '../../auth/AuthContext';
import { SIZE_TYPES, SURFACE_TYPES } from '../../../shared/contract';
import type { ManagerCourt, ManagerCourtInput } from '../../../shared/types';

/**
 * Manager / Court Manager court management (Phase 2.7) — locked
 * qu_n_l_s_n_badmintonpro_admin_production_final_polish.
 *
 * The list is fetched from dbo.Courts on the authenticated SQL session; scope
 * is applied IN SQL by SESSION_CONTEXT (MANAGER → all courts including
 * inactive; COURT_MANAGER → only OwnerId rows), so the browser only ever
 * receives authorized rows. The chips (Tất cả/Đang hoạt động/Ngừng hoạt động)
 * are DISPLAY-ONLY filters over those rows.
 *
 * Create/update/deactivate run through dbo.sp_CreateCourt / sp_UpdateCourt /
 * sp_DeactivateCourt on the same session. The browser sends ONLY editable
 * court fields; ownership is derived by the Stored Procedures from session
 * context (sp_CreateCourt defaults @OwnerId to the session user and forces
 * COURT_MANAGER to self). A race between render and click is always possible,
 * so after every successful mutation the list is refetched from the DB — no
 * local status patching. Duplicate submits are blocked while a mutation runs.
 *
 * Soft deactivation (IsActive = 0) keeps booking history; there is no
 * reactivation in this phase ("Kích hoạt" removed as per contract limits).
 */

type CourtFilter = 'ALL' | 'ACTIVE' | 'INACTIVE';

type FormMode = { kind: 'create' } | { kind: 'edit'; court: ManagerCourt };

interface CourtFormState {
  courtName: string;
  address: string;
  surfaceType: string;
  sizeType: string;
  pricePerHour: string;
  pricePerThreeHours: string;
  imageUrl: string;
}

const SURFACE_OPTIONS: { value: string; label: string }[] = SURFACE_TYPES.map((t) => ({
  value: t,
  label: t === 'VIP' ? 'Sân VIP' : 'Sân tiêu chuẩn',
}));

const SIZE_OPTIONS: { value: string; label: string }[] = SIZE_TYPES.map((t) => ({
  value: t,
  label: t === 'DOUBLE' ? 'Sân đôi' : 'Sân đơn',
}));

const EMPTY_FORM: CourtFormState = {
  courtName: '',
  address: '',
  surfaceType: 'STANDARD',
  sizeType: 'SINGLE',
  pricePerHour: '',
  pricePerThreeHours: '',
  imageUrl: '',
};

function formatVnd(value: number): string {
  return `${new Intl.NumberFormat('vi-VN').format(value)}đ`;
}

function surfaceLabel(value: string): string {
  return value === 'VIP' ? 'Sân VIP' : value === 'STANDARD' ? 'Sân tiêu chuẩn' : value;
}

function sizeLabel(value: string): string {
  return value === 'DOUBLE' ? 'Sân đôi' : value === 'SINGLE' ? 'Sân đơn' : value;
}

function formToInput(form: CourtFormState): ManagerCourtInput {
  return {
    courtName: form.courtName.trim(),
    address: form.address.trim(),
    surfaceType: form.surfaceType,
    sizeType: form.sizeType,
    pricePerHour: Number(form.pricePerHour),
    pricePerThreeHours: Number(form.pricePerThreeHours),
    imageUrl: form.imageUrl.trim().length === 0 ? null : form.imageUrl.trim(),
  };
}

/** UX-level form check only; dbo.sp_CreateCourt/sp_UpdateCourt stay authoritative. */
function validateForm(form: CourtFormState): string | null {
  if (form.courtName.trim().length === 0) return 'Vui lòng nhập tên sân.';
  if (form.address.trim().length === 0) return 'Vui lòng nhập địa chỉ.';
  const hour = Number(form.pricePerHour);
  const three = Number(form.pricePerThreeHours);
  if (!Number.isFinite(hour) || hour <= 0) return 'Giá 1 giờ phải là số lớn hơn 0.';
  if (!Number.isFinite(three) || three <= 0) return 'Giá 3 giờ phải là số lớn hơn 0.';
  return null;
}

/** Locked Stitch court card. Only real dbo.Courts columns are rendered. */
function CourtCard({
  court,
  busy,
  onEdit,
  onDeactivate,
}: {
  court: ManagerCourt;
  busy: boolean;
  onEdit: (court: ManagerCourt) => void;
  onDeactivate: (court: ManagerCourt) => void;
}) {
  const active = Boolean(court.IsActive);
  return (
    <article
      className={['bp-court', active ? '' : 'bp-court--inactive'].filter(Boolean).join(' ')}
      aria-label={`Sân ${court.CourtName}`}
    >
      <div className="bp-court__media">
        {court.ImageUrl ? (
          <img className={['bp-court__img', active ? '' : 'bp-court__img--dim'].filter(Boolean).join(' ')} src={court.ImageUrl} alt={court.CourtName} />
        ) : (
          <div className="bp-court__media-fallback" aria-hidden="true">
            <BpIcon name="sports_badminton" size={56} />
            <span>BadmintonPro</span>
          </div>
        )}
        <div className={active ? 'bp-court__status bp-court__status--active' : 'bp-court__status bp-court__status--inactive'}>
          <span className="bp-court__dot" aria-hidden="true" />
          {active ? 'Đang hoạt động' : 'Ngừng hoạt động'}
        </div>
      </div>

      <div className="bp-court__body">
        <h3 className="bp-court__name">{court.CourtName}</h3>
        <div className="bp-court__address">
          <BpIcon name="location_on" size={18} aria-hidden="true" />
          <p>{court.Address}</p>
        </div>
        <div className="bp-court__chips">
          <span className="bp-court__chip">{surfaceLabel(court.SurfaceType)}</span>
          <span className="bp-court__chip">{sizeLabel(court.SizeType)}</span>
        </div>

        <div className="bp-court__prices">
          <div>
            <p className="bp-court__price-label">Giá / 1 Giờ</p>
            <p className="bp-court__price-value">{formatVnd(Number(court.PricePerHour ?? 0))}</p>
          </div>
          <div>
            <p className="bp-court__price-label">Giá / 3 Giờ</p>
            <p className="bp-court__price-value">{formatVnd(Number(court.PricePerThreeHours ?? 0))}</p>
          </div>
        </div>

        <div className="bp-court__actions">
          <button type="button" className="bp-court__action bp-court__action--edit" onClick={() => onEdit(court)} disabled={busy}>
            <BpIcon name="edit" size={16} aria-hidden="true" />
            Chỉnh sửa
          </button>
          {active ? (
            <button type="button" className="bp-court__action bp-court__action--deactivate" onClick={() => onDeactivate(court)} disabled={busy}>
              <BpIcon name="block" size={16} aria-hidden="true" />
              Ngừng HĐ
            </button>
          ) : null}
        </div>
      </div>
    </article>
  );
}

interface CourtFormSelectProps {
  label: string;
  name: string;
  value: string;
  options: { value: string; label: string }[];
  disabled: boolean;
  onChange: (value: string) => void;
}

/** Stitch-style field select (same .bp-field chrome as the Inputs). */
function CourtFormSelect({ label, name, value, options, disabled, onChange }: CourtFormSelectProps) {
  return (
    <div className="bp-field bp-field--full">
      <label className="bp-field__label" htmlFor={`court-form-${name}`}>
        {label}
      </label>
      <div className="bp-field__control">
        <select
          id={`court-form-${name}`}
          name={name}
          className="bp-field__input bp-court-form__select"
          value={value}
          disabled={disabled}
          onChange={(e) => onChange(e.target.value)}
        >
          {options.map((o) => (
            <option key={o.value} value={o.value}>
              {o.label}
            </option>
          ))}
        </select>
        <span className="bp-court-form__chev" aria-hidden="true">
          <BpIcon name="expand_more" size={20} />
        </span>
      </div>
    </div>
  );
}

export function ManagerCourtsPage() {
  const navigate = useNavigate();
  const { logout } = useAuth();

  type LoadState = 'loading' | 'ready' | 'error';
  const [loadState, setLoadState] = useState<LoadState>('loading');
  const [courts, setCourts] = useState<ManagerCourt[]>([]);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [refreshing, setRefreshing] = useState(false);

  const [filter, setFilter] = useState<CourtFilter>('ALL');

  const [formMode, setFormMode] = useState<FormMode | null>(null);
  const [form, setForm] = useState<CourtFormState>(EMPTY_FORM);
  const [saving, setSaving] = useState(false);
  const [formError, setFormError] = useState<string | null>(null);

  const [deactivateTarget, setDeactivateTarget] = useState<ManagerCourt | null>(null);
  const [deactivating, setDeactivating] = useState(false);
  const [deactivateError, setDeactivateError] = useState<string | null>(null);

  const [toast, setToast] = useState<{ title: string; message: string } | null>(null);
  const toastTimer = useRef<number | null>(null);
  const busy = saving || deactivating;

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
   * Refetch the manager court list from dbo.Courts. A background refetch keeps
   * the stale authorized list visible while the DB is re-read after a mutation.
   */
  const loadManagerCourts = useCallback(
    async (opts?: { background?: boolean }) => {
      if (!opts?.background) setLoadState('loading');
      setRefreshing(true);
      setLoadError(null);
      try {
        const res = await getManagerCourtsRequest();
        setCourts(res.courts);
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
    void loadManagerCourts();
  }, [loadManagerCourts]);

  const filtered = useMemo(() => {
    return courts.filter((c) => {
      if (filter === 'ACTIVE') return Boolean(c.IsActive);
      if (filter === 'INACTIVE') return !c.IsActive;
      return true;
    });
  }, [courts, filter]);

  function openCreate(): void {
    setFormError(null);
    setForm(EMPTY_FORM);
    setFormMode({ kind: 'create' });
  }

  function openEdit(court: ManagerCourt): void {
    setFormError(null);
    setForm({
      courtName: court.CourtName,
      address: court.Address,
      surfaceType: court.SurfaceType,
      sizeType: court.SizeType,
      pricePerHour: String(court.PricePerHour ?? ''),
      pricePerThreeHours: String(court.PricePerThreeHours ?? ''),
      imageUrl: court.ImageUrl ?? '',
    });
    setFormMode({ kind: 'edit', court });
  }

  function closeForm(): void {
    if (saving) return;
    setFormMode(null);
    setFormError(null);
  }

  async function handleFormSubmit(): Promise<void> {
    if (!formMode || saving) return;
    const error = validateForm(form);
    if (error) {
      setFormError(error);
      return;
    }
    setSaving(true);
    setFormError(null);
    try {
      const input = formToInput(form);
      if (formMode.kind === 'create') {
        await createCourtRequest(input);
        setFormMode(null);
        showToast('Đã thêm sân', 'Sân mới đã được tạo trong hệ thống.');
      } else {
        await updateCourtRequest(formMode.court.CourtId, input);
        setFormMode(null);
        showToast('Đã cập nhật sân', 'Thông tin sân đã được lưu.');
      }
      // Mandatory post-mutation reconciliation: re-read from the database.
      await loadManagerCourts({ background: true });
    } catch (err) {
      if (err instanceof ApiError && err.status === 401) {
        setFormMode(null);
        await logout();
        navigate('/login', { replace: true });
        return;
      }
      // 403/404/409 (ownership / gone / conflict) → stay in the modal so the
      // user can read the exact message; DB state is the truth.
      setFormError(err instanceof Error ? err.message : 'Có lỗi từ hệ thống. Vui lòng thử lại.');
    } finally {
      setSaving(false);
    }
  }

  async function handleDeactivateConfirm(): Promise<void> {
    if (!deactivateTarget || deactivating) return;
    setDeactivating(true);
    setDeactivateError(null);
    try {
      await deactivateCourtRequest(deactivateTarget.CourtId);
      setDeactivateTarget(null);
      showToast('Đã ngừng hoạt động', 'Sân đã chuyển sang trạng thái "Ngừng hoạt động".');
      // Mandatory post-mutation reconciliation: re-read from the database.
      await loadManagerCourts({ background: true });
    } catch (err) {
      if (err instanceof ApiError && err.status === 401) {
        setDeactivateTarget(null);
        await logout();
        navigate('/login', { replace: true });
        return;
      }
      setDeactivateError(err instanceof Error ? err.message : 'Có lỗi từ hệ thống. Vui lòng thử lại.');
    } finally {
      setDeactivating(false);
    }
  }

  const filterChips = (
    <div className="bp-courts__seg" role="group" aria-label="Lọc theo trạng thái sân">
      {(
        [
          { id: 'ALL', label: 'Tất cả' },
          { id: 'ACTIVE', label: 'Đang hoạt động' },
          { id: 'INACTIVE', label: 'Ngừng hoạt động' },
        ] as const
      ).map((c) => (
        <button
          key={c.id}
          type="button"
          className={['bp-courts__seg-btn', filter === c.id ? 'bp-courts__seg-btn--active' : ''].filter(Boolean).join(' ')}
          onClick={() => setFilter(c.id)}
        >
          {c.label}
        </button>
      ))}
    </div>
  );

  return (
    <div className="bp-courts-mgr">
      <PageHeader
        title="Quản lý sân"
        subtitle="Theo dõi và quản lý thông tin các sân trong hệ thống."
        actions={
          <div className="bp-courts__header-actions">
            {filterChips}
            <Button variant="primary" icon="add" onClick={openCreate} disabled={busy}>
              Thêm sân mới
            </Button>
          </div>
        }
      />

      {loadState === 'loading' ? (
        <div className="bp-courts__grid" aria-hidden="true">
          {Array.from({ length: 4 }, (_, i) => (
            <div className="bp-courts__skeleton" key={i}>
              <LoadingSkeleton variant="card" />
            </div>
          ))}
        </div>
      ) : loadState === 'error' ? (
        <div className="bp-courts__card">
          <EmptyState
            icon="cloud_off"
            title="Không tải được danh sách sân"
            description={loadError}
            action={
              <Button variant="primary" icon="refresh" onClick={() => void loadManagerCourts()}>
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

          {filtered.length === 0 ? (
            <div className="bp-courts__card">
              <EmptyState
                icon="sports_badminton"
                title={courts.length === 0 ? 'Chưa có sân' : 'Không có kết quả phù hợp'}
                description={
                  courts.length === 0
                    ? 'Khi sân được tạo, chúng sẽ xuất hiện ở đây. Chọn "Thêm sân mới" để tạo sân đầu tiên.'
                    : 'Thử thay đổi bộ lọc trạng thái.'
                }
              />
            </div>
          ) : (
            <div className="bp-courts__grid">
              {filtered.map((court) => (
                <CourtCard
                  key={court.CourtId}
                  court={court}
                  busy={busy}
                  onEdit={openEdit}
                  onDeactivate={setDeactivateTarget}
                />
              ))}
            </div>
          )}

          <div className="bp-courts__footer">
            <span>
              Hiển thị {filtered.length} trong {courts.length} sân
            </span>
            {refreshing ? (
              <span className="bp-mgr__refreshing">
                <BpIcon name="progress_activity" size={16} aria-hidden="true" />
                Đang đồng bộ từ cơ sở dữ liệu...
              </span>
            ) : null}
          </div>
        </>
      )}

      {/* -------- Add / Edit court modal (locked Stitch form) -------- */}
      {formMode ? (
        <div className="bp-modal" role="dialog" aria-modal="true" aria-labelledby="bp-court-form-title">
          <div className="bp-modal__backdrop" onClick={closeForm} role="presentation" />
          <div className="bp-modal__panel bp-court-form">
            <header className="bp-court-form__head">
              <h2 id="bp-court-form-title">{formMode.kind === 'create' ? 'Thêm sân mới' : 'Chỉnh sửa sân'}</h2>
              <button className="bp-court-form__close" type="button" aria-label="Đóng" onClick={closeForm} disabled={saving}>
                <BpIcon name="close" size={20} aria-hidden="true" />
              </button>
            </header>

            <div className="bp-court-form__body">
              <div className="bp-court-form__grid">
                <Input
                  label="Tên sân *"
                  value={form.courtName}
                  placeholder="VD: Sân A1"
                  maxLength={100}
                  fullWidth
                  disabled={saving}
                  onChange={(e) => setForm((prev) => ({ ...prev, courtName: e.target.value }))}
                />
                <CourtFormSelect
                  label="Loại mặt sân"
                  name="surfaceType"
                  value={form.surfaceType}
                  options={SURFACE_OPTIONS}
                  disabled={saving}
                  onChange={(value) => setForm((prev) => ({ ...prev, surfaceType: value }))}
                />
              </div>

              <Input
                label="Địa chỉ / Vị trí *"
                value={form.address}
                placeholder="VD: Tầng 2, Khu thể thao phức hợp"
                maxLength={255}
                fullWidth
                disabled={saving}
                onChange={(e) => setForm((prev) => ({ ...prev, address: e.target.value }))}
              />

              <div className="bp-court-form__grid">
                <CourtFormSelect
                  label="Kích thước"
                  name="sizeType"
                  value={form.sizeType}
                  options={SIZE_OPTIONS}
                  disabled={saving}
                  onChange={(value) => setForm((prev) => ({ ...prev, sizeType: value }))}
                />
                <Input
                  label="Ảnh sân (URL)"
                  value={form.imageUrl}
                  placeholder="https://..."
                  maxLength={500}
                  fullWidth
                  disabled={saving}
                  onChange={(e) => setForm((prev) => ({ ...prev, imageUrl: e.target.value }))}
                />
              </div>

              <div className="bp-court-form__grid">
                <Input
                  label="Giá 1 giờ (VNĐ) *"
                  type="number"
                  value={form.pricePerHour}
                  placeholder="100000"
                  min={1}
                  fullWidth
                  disabled={saving}
                  onChange={(e) => setForm((prev) => ({ ...prev, pricePerHour: e.target.value }))}
                />
                <Input
                  label="Giá 3 giờ (VNĐ) *"
                  type="number"
                  value={form.pricePerThreeHours}
                  placeholder="270000"
                  min={1}
                  fullWidth
                  disabled={saving}
                  onChange={(e) => setForm((prev) => ({ ...prev, pricePerThreeHours: e.target.value }))}
                />
              </div>

              {formError ? (
                <div className="bp-history__alert" role="alert">
                  <BpIcon name="error" size={18} aria-hidden="true" />
                  <span>{formError}</span>
                </div>
              ) : null}
            </div>

            <footer className="bp-court-form__foot">
              <Button variant="outline" onClick={closeForm} disabled={saving}>
                Hủy bỏ
              </Button>
              <Button
                variant="primary"
                icon="check"
                loading={saving}
                keepLabel={saving}
                disabled={saving}
                onClick={() => void handleFormSubmit()}
              >
                {formMode.kind === 'create' ? 'Thêm sân' : 'Lưu thay đổi'}
              </Button>
            </footer>
          </div>
        </div>
      ) : null}

      {/* -------- Soft deactivation confirm modal (locked Stitch behavior) -------- */}
      {deactivateTarget ? (
        <div className="bp-modal" role="dialog" aria-modal="true" aria-labelledby="bp-court-deactivate-title">
          <div
            className="bp-modal__backdrop"
            onClick={() => {
              if (!deactivating) setDeactivateTarget(null);
            }}
            role="presentation"
          />
          <div className="bp-modal__panel bp-court-deactivate">
            <div className="bp-court-deactivate__icon">
              <BpIcon name="info" size={32} aria-hidden="true" />
            </div>
            <h2 id="bp-court-deactivate-title">Ngừng hoạt động sân?</h2>
            <p className="bp-court-deactivate__text">
              Sân sẽ chuyển sang trạng thái &quot;Ngừng hoạt động&quot;. Lịch sử đặt sân vẫn được giữ nguyên, nhưng khách
              hàng sẽ không thể đặt lịch mới tại sân này.
            </p>
            {deactivateError ? (
              <div className="bp-history__alert" role="alert">
                <BpIcon name="error" size={18} aria-hidden="true" />
                <span>{deactivateError}</span>
              </div>
            ) : null}
            <div className="bp-court-deactivate__actions">
              <Button
                variant="danger"
                icon="block"
                loading={deactivating}
                keepLabel={deactivating}
                disabled={deactivating}
                onClick={() => void handleDeactivateConfirm()}
              >
                Xác nhận ngừng hoạt động
              </Button>
              <Button variant="outline" onClick={() => setDeactivateTarget(null)} disabled={deactivating}>
                Hủy bỏ
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
    </div>
  );
}