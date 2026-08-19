import { NavLink, Outlet, useNavigate } from 'react-router-dom';
import { ContentShell } from './ContentShell';
import { BrandLogo } from '../components/BrandLogo';
import { Button } from '../components/Button';
import { BpIcon } from '../components/BpIcon';
import { useAuth } from '../auth/AuthContext';
import { roleHome } from '../auth/guards';

/**
 * Guest shell: public court-search visual language (locked
 * t_m_s_n_c_u_l_ng_guest_badmintonpro_final). No privileged role here.
 * Auth-aware only for Phase 2.2: an authenticated visitor sees their role home
 * and a real logout instead of a stale "Đăng nhập" CTA.
 */
export function GuestShell() {
  const { status, user, logout } = useAuth();
  const navigate = useNavigate();

  const handleLogout = async () => {
    await logout();
    navigate('/login', { replace: true });
  };

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
            {status === 'authenticated' && user ? (
              <>
                <NavLink to={roleHome(user.role)} className="bp-icon-btn" aria-label="Tài khoản" title="Tài khoản">
                  <BpIcon name="account_circle" size={22} aria-hidden="true" />
                </NavLink>
                <button className="bp-icon-btn" type="button" aria-label="Đăng xuất" title="Đăng xuất" onClick={handleLogout}>
                  <BpIcon name="logout" size={22} aria-hidden="true" />
                </button>
              </>
            ) : (
              <NavLink to="/login">
                <Button variant="primary" size="md" icon="login">
                  Đăng nhập
                </Button>
              </NavLink>
            )}
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