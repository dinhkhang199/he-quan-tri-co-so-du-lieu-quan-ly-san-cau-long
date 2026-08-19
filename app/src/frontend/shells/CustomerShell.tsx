import { NavLink, Outlet } from 'react-router-dom';
import { ContentShell } from './ContentShell';
import { BrandLogo } from '../components/BrandLogo';
import { BpIcon } from '../components/BpIcon';

interface CustomerNavItem {
  to: string;
  label: string;
  icon: string;
}

const CUSTOMER_NAV: CustomerNavItem[] = [
  { to: '/courts', label: 'Tìm sân', icon: 'search' },
  { to: '/my-bookings', label: 'Lịch sử đặt sân', icon: 'history' },
];

/** Locked customer shell: slim top navbar over a centered content column. */
export function CustomerShell() {
  return (
    <div className="bp-customer">
      <header className="bp-customer__topbar">
        <div className="bp-customer__topbar-inner">
          <div className="bp-customer__left">
            <NavLink to="/courts" aria-label="BadmintonPro">
              <BrandLogo size="md" />
            </NavLink>
            <nav className="bp-customer__nav" aria-label="Điều hướng khách hàng">
              {CUSTOMER_NAV.map((item) => (
                <NavLink
                  key={item.to}
                  to={item.to}
                  className={({ isActive }) =>
                    ['bp-customer__link', isActive ? 'bp-customer__link--active' : ''].filter(Boolean).join(' ')
                  }
                >
                  {item.label}
                </NavLink>
              ))}
            </nav>
          </div>
          <div className="bp-customer__right">
            <NavLink to="/notifications" className="bp-icon-btn" aria-label="Thông báo">
              <BpIcon name="notifications" size={22} aria-hidden="true" />
            </NavLink>
            <button className="bp-icon-btn" aria-label="Tài khoản">
              <BpIcon name="account_circle" size={22} aria-hidden="true" />
            </button>
          </div>
        </div>
      </header>
      <main className="bp-customer__main">
        <ContentShell>
          <Outlet />
        </ContentShell>
      </main>
    </div>
  );
}