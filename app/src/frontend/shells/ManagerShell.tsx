import { useState } from 'react';
import { NavLink, Outlet } from 'react-router-dom';
import type { UserRole } from '../../shared/contract';
import { ContentShell } from './ContentShell';
import { BrandLogo } from '../components/BrandLogo';
import { BpIcon } from '../components/BpIcon';
import { SearchInput } from '../components/Input';

interface ManagerNavItem {
  to: string;
  label: string;
  icon: string;
}

const MANAGER_NAV: ManagerNavItem[] = [
  { to: '/manager/dashboard', label: 'Bảng điều khiển', icon: 'dashboard' },
  { to: '/manager/bookings', label: 'Quản lý booking', icon: 'calendar_month' },
  { to: '/manager/courts', label: 'Quản lý sân', icon: 'sports_badminton' },
  { to: '/manager/notifications', label: 'Thông báo', icon: 'notifications' },
];

const SCOPE_LABELS: Record<string, string> = {
  MANAGER: 'Toàn hệ thống',
  COURT_MANAGER: 'Sân của tôi',
};

interface ManagerShellProps {
  /** Presentational only. Backend (SESSION_CONTEXT) remains the security authority. */
  role: Extract<UserRole, 'MANAGER' | 'COURT_MANAGER'>;
}

/**
 * Locked Manager / Court Manager shell: fixed left sidebar + top navbar.
 * Authorization is NOT enforced here — DB Stored Procedures are the authority.
 */
export function ManagerShell({ role }: ManagerShellProps) {
  const [mobileOpen, setMobileOpen] = useState(false);
  const scope = SCOPE_LABELS[role];

  return (
    <div className="bp-manager">
      {/* Sidebar (desktop) */}
      <aside className="bp-manager__side">
        <div className="bp-manager__brand">
          <BrandLogo size="md" />
          <span className="bp-manager__role">[{role}]</span>
        </div>
        <nav className="bp-manager__nav" aria-label="Điều hướng quản lý">
          {MANAGER_NAV.map((item) => (
            <NavLink
              key={item.to}
              to={item.to}
              className={({ isActive }) =>
                ['bp-manager__link', isActive ? 'bp-manager__link--active' : ''].filter(Boolean).join(' ')
              }
            >
              <BpIcon name={item.icon} filled size={20} aria-hidden="true" />
              <span>{item.label}</span>
            </NavLink>
          ))}
        </nav>
        <div className="bp-manager__footer">
          <NavLink to="/login" className="bp-manager__logout">
            <BpIcon name="logout" size={20} aria-hidden="true" />
            <span>Đăng xuất</span>
          </NavLink>
        </div>
      </aside>

      {/* Mobile overlay sidebar */}
      {mobileOpen ? (
        <div className="bp-manager__overlay" onClick={() => setMobileOpen(false)} role="presentation" />
      ) : null}
      <aside className={['bp-manager__side', 'bp-manager__side--mobile', mobileOpen ? 'bp-manager__side--open' : ''].filter(Boolean).join(' ')}>
        <div className="bp-manager__brand">
          <BrandLogo size="md" />
          <span className="bp-manager__role">[{role}]</span>
        </div>
        <nav className="bp-manager__nav" aria-label="Điều hướng quản lý">
          {MANAGER_NAV.map((item) => (
            <NavLink
              key={item.to}
              to={item.to}
              onClick={() => setMobileOpen(false)}
              className={({ isActive }) =>
                ['bp-manager__link', isActive ? 'bp-manager__link--active' : ''].filter(Boolean).join(' ')
              }
            >
              <BpIcon name={item.icon} filled size={20} aria-hidden="true" />
              <span>{item.label}</span>
            </NavLink>
          ))}
        </nav>
        <div className="bp-manager__footer">
          <NavLink to="/login" className="bp-manager__logout">
            <BpIcon name="logout" size={20} aria-hidden="true" />
            <span>Đăng xuất</span>
          </NavLink>
        </div>
      </aside>

      <div className="bp-manager__main">
        <header className="bp-manager__topbar">
          <div className="bp-manager__topbar-left">
            <button className="bp-manager__menu-btn" onClick={() => setMobileOpen((v) => !v)} aria-label="Mở menu">
              <BpIcon name="menu" size={26} aria-hidden="true" />
            </button>
            <div className="bp-manager__scope">
              <BpIcon name="account_tree" size={18} aria-hidden="true" />
              <span>Phạm vi: {scope}</span>
            </div>
          </div>
          <div className="bp-manager__topbar-right">
            <SearchInput placeholder="Tìm kiếm trong hệ thống..." aria-label="Tìm kiếm hệ thống" className="bp-manager__search" />
          </div>
        </header>
        <main className="bp-manager__content">
          <ContentShell>
            <Outlet />
          </ContentShell>
        </main>
      </div>
    </div>
  );
}