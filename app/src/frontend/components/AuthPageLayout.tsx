import type { ReactNode } from 'react';
import { BpIcon } from './BpIcon';
import { BrandLogo } from './BrandLogo';

export function AuthPageLayout({
  title,
  subtitle,
  children,
}: {
  title: string;
  subtitle: string;
  children: ReactNode;
}) {
  return (
    <div className="bp-login bp-login--auth-flow">
      {/* Left visual area (desktop, >= 768px) */}
      <div className="bp-login__hero" aria-hidden="true">
        <div className="bp-login__court-lines" />
        <div className="bp-login__floating-chips">
          <span className="bp-login__chip bp-login__chip--pos-1 bp-login__chip--float-1">
            <BpIcon name="sports_badminton" size={18} /> Đặt sân nhanh chóng
          </span>
          <span className="bp-login__chip bp-login__chip--pos-2 bp-login__chip--float-2">
            <BpIcon name="schedule" size={18} /> 06:00 — 22:00
          </span>
          <span className="bp-login__chip bp-login__chip--pos-3 bp-login__chip--float-3">
            <BpIcon name="verified_user" size={18} /> Minh bạch chi phí
          </span>
        </div>
        <div className="bp-login__hero-bottom">
          <div className="bp-login__glass-panel">
            <p className="bp-login__eyebrow">BADMINTON PRO · QUẢN LÝ SÂN CẦU LÔNG</p>
            <h1 className="bp-login__hero-title">Trải nghiệm đặt sân tiện lợi & chuyên nghiệp.</h1>
            <p className="bp-login__hero-sub">Tạo tài khoản để đặt sân, theo dõi lịch hẹn và nhận thông báo tức thì.</p>
          </div>
        </div>
      </div>

      {/* Mobile hero banner (< 768px) */}
      <div className="bp-login__hero-mobile" aria-hidden="true">
        <h1>BadmintonPro</h1>
      </div>

      {/* Right form panel */}
      <div className="bp-login__panel">
        <div className="bp-login__card bp-login__card--auth-flow">
          <div className="bp-login__head">
            <div className="bp-login__logo">
              <BrandLogo showName={false} size="md" />
            </div>
            <h2 className="bp-login__title">{title}</h2>
            <p className="bp-login__subtitle">{subtitle}</p>
          </div>
          {children}
        </div>
      </div>
    </div>
  );
}
