import { useState } from 'react';
import type { FormEvent } from 'react';
import { NavLink, useNavigate } from 'react-router-dom';
import { BrandLogo } from '../components/BrandLogo';
import { BpIcon } from '../components/BpIcon';
import { Button } from '../components/Button';
import { Input } from '../components/Input';
import { roleHome } from '../auth/guards';
import { useAuth } from '../auth/AuthContext';

/**
 * Login screen (locked Stitch login_premium_polished_v2_badmintonpro).
 * No registration / forgot-password / remember-me. Errors come from the safe
 * server messages mapped from sp_Login (50001 bad credentials, 50002 inactive).
 */
export function LoginPage() {
  const { login } = useAuth();
  const navigate = useNavigate();
  const [username, setUsername] = useState('');
  const [password, setPassword] = useState('');
  const [showPassword, setShowPassword] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (submitting) return;
    const trimmedUser = username.trim();
    if (!trimmedUser || !password) {
      setError('Vui lòng nhập tên đăng nhập và mật khẩu.');
      return;
    }
    setSubmitting(true);
    setError(null);
    try {
      const user = await login(trimmedUser, password);
      navigate(roleHome(user.role), { replace: true });
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Đăng nhập thất bại. Vui lòng thử lại.');
      setSubmitting(false);
    }
  }

  return (
    <div className="bp-login">
      {/* Left visual area (desktop, >= 768px) */}
      <div className="bp-login__hero" aria-hidden="true">
        <div className="bp-login__hero-brand">
          <BrandLogo showName={false} size="lg" />
        </div>
        <div className="bp-login__hero-bottom">
          <div className="bp-login__chips">
            <span className="bp-login__chip bp-login__chip--float-1">
              <BpIcon name="calendar_month" size={18} />
              Quản lý lịch sân
            </span>
            <span className="bp-login__chip bp-login__chip--float-2">
              <BpIcon name="flash_on" size={18} />
              Đặt sân nhanh chóng
            </span>
            <span className="bp-login__chip bp-login__chip--float-3">
              <BpIcon name="schedule" size={18} />
              06:00 — 22:00
            </span>
          </div>
          <div className="bp-login__hero-copy">
            <h1 className="bp-login__hero-title">
              Quản lý sân thông minh.
              <br />
              Vận hành dễ dàng.
            </h1>
            <p className="bp-login__hero-sub">Theo dõi lịch sân, booking và hoạt động trên một hệ thống duy nhất.</p>
          </div>
        </div>
      </div>

      {/* Mobile hero banner (< 768px) */}
      <div className="bp-login__hero-mobile" aria-hidden="true">
        <h1>Quản lý sân thông minh.</h1>
      </div>

      {/* Right login panel */}
      <div className="bp-login__panel">
        <div className="bp-login__card">
          <div className="bp-login__head">
            <div className="bp-login__logo">
              <BrandLogo showName={false} size="md" />
            </div>
            <h2 className="bp-login__title">BadmintonPro</h2>
            <p className="bp-login__subtitle">Hệ thống quản lý sân cầu lông</p>
          </div>

          <form className="bp-login__form" onSubmit={handleSubmit} aria-busy={submitting}>
            <Input
              label="Tên đăng nhập"
              icon="person"
              type="text"
              name="username"
              autoComplete="username"
              placeholder="Nhập tên đăng nhập"
              value={username}
              onChange={(e) => setUsername(e.target.value)}
              disabled={submitting}
              fullWidth
              autoFocus
            />

            <div className="bp-field bp-field--full">
              <label className="bp-field__label" htmlFor="bp-login-password">
                Mật khẩu
              </label>
              <div className="bp-field__control">
                <span className="bp-field__icon">
                  <BpIcon name="lock" size={20} aria-hidden="true" />
                </span>
                <input
                  id="bp-login-password"
                  className="bp-field__input bp-field__input--with-action"
                  type={showPassword ? 'text' : 'password'}
                  name="password"
                  autoComplete="current-password"
                  placeholder="••••••••"
                  value={password}
                  onChange={(e) => setPassword(e.target.value)}
                  disabled={submitting}
                />
                <button
                  type="button"
                  className="bp-field__action"
                  onClick={() => setShowPassword((v) => !v)}
                  aria-label={showPassword ? 'Ẩn mật khẩu' : 'Hiện mật khẩu'}
                  aria-pressed={showPassword}
                >
                  <BpIcon name={showPassword ? 'visibility_off' : 'visibility'} size={20} aria-hidden="true" />
                </button>
              </div>
            </div>

            <div className={['bp-login__error', error ? 'bp-login__error--show' : ''].filter(Boolean).join(' ')} role="alert">
              {error ? (
                <>
                  <BpIcon name="error" size={20} />
                  <span>{error}</span>
                </>
              ) : null}
            </div>

            <Button
              type="submit"
              variant="primary"
              size="lg"
              fullWidth
              loading={submitting}
              disabled={submitting}
              className="bp-login__submit"
            >
              Đăng nhập <BpIcon name="arrow_forward" size={20} aria-hidden="true" />
            </Button>
          </form>

          <div className="bp-login__guest-wrap">
            <NavLink to="/courts" className="bp-login__guest">
              <span>Tiếp tục với tư cách khách</span>
              <BpIcon name="arrow_forward" size={18} aria-hidden="true" />
            </NavLink>
          </div>
        </div>
      </div>
    </div>
  );
}