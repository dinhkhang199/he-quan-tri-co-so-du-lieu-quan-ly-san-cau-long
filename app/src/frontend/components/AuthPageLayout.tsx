import type { ReactNode } from 'react';
import { BpIcon } from './BpIcon';
import { BrandLogo } from './BrandLogo';
import { FestivalDecor } from './FestivalDecor';

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
      <div className="bp-login__hero" aria-hidden="true">
        <FestivalDecor variant="hero" />
        <div className="bp-login__court-lines" />
        <div className="bp-login__floating-chips">
          <span className="bp-login__chip bp-login__chip--pos-1 bp-login__chip--float-1">
            <BpIcon name="verified_user" size={18} /> An tâm vui hội
          </span>
          <span className="bp-login__chip bp-login__chip--pos-2 bp-login__chip--float-2">
            <BpIcon name="sports_tennis" size={18} /> Giao cầu dưới trăng
          </span>
          <span className="bp-login__chip bp-login__chip--pos-3 bp-login__chip--float-3">
            <BpIcon name="schedule" size={18} /> 06:00 — 22:00
          </span>
        </div>
        <div className="bp-login__hero-bottom">
          <div className="bp-login__glass-panel">
            <p className="bp-login__eyebrow">TRUNG THU ĐOÀN VIÊN · 2026</p>
            <h1 className="bp-login__hero-title">Hẹn sân dưới ánh trăng.</h1>
            <p className="bp-login__hero-sub">Tạo tài khoản, rủ bạn bè và lưu trọn từng cuộc hẹn mùa trăng.</p>
          </div>
        </div>
      </div>

      <div className="bp-login__hero-mobile" aria-hidden="true">
        <h1>Đêm hội trăng rằm</h1>
      </div>

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
