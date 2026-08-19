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

/**
 * Court result card (locked t_m_s_n_c_u_l_ng_guest_badmintonpro_final).
 * Fills entirely from real dbo.sp_GetAvailableCourts columns. ImageUrl is not
 * returned by that procedure (and seed ImageUrl is NULL), so the media slot
 * uses a local teal fallback — never a fabricated remote court image.
 */
export function CourtCard({ court, startTime, endTime, isCustomer }: CourtCardProps) {
  const bookingHref = `/booking/${court.CourtId}?startTime=${encodeURIComponent(startTime)}&endTime=${encodeURIComponent(endTime)}`;

  return (
    <article className="bp-court-card">
      <div className="bp-court-card__media">
        <div className="bp-court-card__media-fallback" aria-hidden="true">
          <BpIcon name="sports_badminton" size={56} />
          <span>BadmintonPro</span>
        </div>
        <div className="bp-court-card__available">
          <span className="bp-court-card__dot" aria-hidden="true" />
          Còn trống
        </div>
      </div>

      <div className="bp-court-card__body">
        <div>
          <div className="bp-court-card__head">
            <h3 className="bp-court-card__name">{court.CourtName}</h3>
            <div className="bp-court-card__price">
              <strong>{formatVnd(court.PricePerHour)}</strong>
              <span> / giờ</span>
            </div>
          </div>
          <p className="bp-court-card__address">
            <BpIcon name="location_on" size={18} aria-hidden="true" />
            {court.Address}
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
            <span className="bp-court-card__chip">
              <BpIcon name="sell" size={14} aria-hidden="true" />
              {formatVnd(court.PricePerThreeHours)}
              <span className="bp-court-card__chip-sub"> / 3 giờ</span>
            </span>
          </div>
        </div>

        <div className="bp-court-card__foot">
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