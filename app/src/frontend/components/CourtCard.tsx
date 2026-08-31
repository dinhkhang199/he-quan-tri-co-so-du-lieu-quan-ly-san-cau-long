import { NavLink } from 'react-router-dom';
import type { AvailableCourt } from '../../shared/types';
import { BpIcon } from './BpIcon';

function formatVnd(value: number): string {
  return `${new Intl.NumberFormat('vi-VN').format(value)}đ`;
}

function surfaceLabel(value: string): string {
  if (value === 'VIP') return 'Sân VIP';
  if (value === 'STANDARD') return 'Sân tiêu chuẩn';
  return value;
}

function sizeLabel(value: string): string {
  if (value === 'DOUBLE') return 'Sân đôi';
  if (value === 'SINGLE') return 'Sân đơn';
  return value;
}

interface CourtCardProps {
  court: AvailableCourt;
  /** Local wall-clock window the search returned this court for. */
  startTime: string;
  endTime: string;
  /** True only for an authenticated CUSTOMER (can proceed to booking). */
  isCustomer: boolean;
}

function calculateWindowHours(startTime: string, endTime: string): number {
  const [sh, sm] = startTime.slice(11, 16).split(':').map(Number);
  const [eh, em] = endTime.slice(11, 16).split(':').map(Number);
  const diff = (eh * 60 + em) - (sh * 60 + sm);
  return diff > 0 ? diff / 60 : 1;
}

function formatHoursLabel(hours: number): string {
  if (hours === 1) return '1 giờ';
  if (hours === 2) return '2 giờ';
  if (hours === 3) return '3 giờ';
  const h = Math.floor(hours);
  const m = Math.round((hours - h) * 60);
  return m > 0 ? `${h}h${m}` : `${h} giờ`;
}

function estimateWindowCost(court: AvailableCourt, hours: number): number {
  if (hours === 3) return court.PricePerThreeHours;
  return court.PricePerHour * hours;
}

/**
 * Court result card (locked t_m_s_n_c_u_l_ng_guest_badmintonpro_final).
 * Fills entirely from real dbo.sp_GetAvailableCourts columns.
 */
export function CourtCard({ court, startTime, endTime, isCustomer }: CourtCardProps) {
  const bookingHref = `/booking/${court.CourtId}?startTime=${encodeURIComponent(startTime)}&endTime=${encodeURIComponent(endTime)}`;
  const hours = calculateWindowHours(startTime, endTime);
  const totalCost = estimateWindowCost(court, hours);

  return (
    <article className="bp-court-card">
      <div className="bp-court-card__media">
        <div className="bp-court-card__media-fallback" aria-hidden="true">
          <img
            className="bp-pixel-court-image"
            src="/assets/badminton-court-mid-autumn-pixel.png"
            alt=""
            loading="lazy"
            decoding="async"
          />
        </div>
        <div className="bp-court-card__available">
          <span className="bp-court-card__dot" aria-hidden="true" />
          Còn trống
        </div>
      </div>

      <div className="bp-court-card__body">
        <div className="bp-court-card__main-info">
          <div className="bp-court-card__head">
            <h3 className="bp-court-card__name">{court.CourtName}</h3>
            <div className="bp-court-card__price">
              <strong>{formatVnd(court.PricePerHour)}</strong>
              <span> / giờ</span>
            </div>
          </div>
          <p className="bp-court-card__address">
            <BpIcon name="location_on" size={18} aria-hidden="true" />
            <span>{court.Address}</span>
          </p>
          <div className="bp-court-card__chips">
            <span className="bp-court-card__chip">
              <BpIcon name="layers" size={14} aria-hidden="true" />
              {surfaceLabel(court.SurfaceType)}
            </span>
            <span className="bp-court-card__chip">
              <BpIcon name="grid_view" size={14} aria-hidden="true" />
              {sizeLabel(court.SizeType)}
            </span>
          </div>
        </div>

        <div className="bp-court-card__foot">
          <div className="bp-court-card__total">
            <span className="bp-court-card__total-label">Tổng:</span>
            <strong className="bp-court-card__total-amount">{formatVnd(totalCost)}</strong>
            <span className="bp-court-card__total-duration">({formatHoursLabel(hours)})</span>
          </div>

          {isCustomer ? (
            <NavLink to={bookingHref} className="bp-btn bp-btn--primary bp-court-card__cta">
              <BpIcon name="event_available" size={18} aria-hidden="true" />
              <span>Đặt sân</span>
            </NavLink>
          ) : (
            <NavLink to="/login" className="bp-court-card__cta bp-court-card__cta--login">
              <BpIcon name="lock" size={18} aria-hidden="true" />
              <span>Đăng nhập để đặt</span>
            </NavLink>
          )}
        </div>
      </div>
    </article>
  );
}
