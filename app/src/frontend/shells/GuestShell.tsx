import { NavLink, Outlet } from 'react-router-dom';
import { ContentShell } from './ContentShell';
import { BrandLogo } from '../components/BrandLogo';
import { Button } from '../components/Button';

/**
 * Guest shell: public court-search visual language (locked
 * t_m_s_n_c_u_l_ng_guest_badmintonpro_final). No privileged role here.
 */
export function GuestShell() {
  return (
    <div className="bp-guest">
      <div className="bp-guest__pattern" aria-hidden="true" />
      <header className="bp-guest__topbar">
        <div className="bp-guest__topbar-inner">
          <div className="bp-guest__left">
            <NavLink to="/courts" aria-label="BadmintonPro">
              <BrandLogo size="md" />
            </NavLink>
            <nav className="bp-guest__nav" aria-label="Tìm sân">
              <NavLink
                to="/courts"
                className={({ isActive }) =>
                  ['bp-guest__link', isActive ? 'bp-guest__link--active' : ''].filter(Boolean).join(' ')
                }
              >
                Tìm sân
              </NavLink>
            </nav>
          </div>
          <div className="bp-guest__right">
            <NavLink to="/login">
              <Button variant="primary" size="md" icon="login">
                Đăng nhập
              </Button>
            </NavLink>
          </div>
        </div>
      </header>
      <main className="bp-guest__main">
        <ContentShell>
          <Outlet />
        </ContentShell>
      </main>
    </div>
  );
}