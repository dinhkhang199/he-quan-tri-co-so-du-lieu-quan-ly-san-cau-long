import { useState } from 'react';
import type { FormEvent } from 'react';
import { NavLink } from 'react-router-dom';
import { registerRequest } from '../api/client';
import { AuthPageLayout } from '../components/AuthPageLayout';
import { BpIcon } from '../components/BpIcon';
import { Button } from '../components/Button';
import { Input } from '../components/Input';

export function RegisterPage() {
  const [username, setUsername] = useState('');
  const [phoneNumber, setPhoneNumber] = useState('');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [confirmPassword, setConfirmPassword] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [success, setSuccess] = useState(false);
  const [submitting, setSubmitting] = useState(false);

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (submitting) return;
    if (!email || email.trim().length === 0) {
      setError('Vui lòng nhập địa chỉ email.');
      return;
    }
    if (password !== confirmPassword) {
      setError('Mật khẩu xác nhận không khớp.');
      return;
    }
    setSubmitting(true);
    setError(null);
    try {
      await registerRequest({ username, phoneNumber, email, password, confirmPassword });
      setSuccess(true);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Đăng ký thất bại. Vui lòng thử lại.');
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <AuthPageLayout title="Tạo tài khoản" subtitle="Đăng ký tài khoản khách hàng mới">
      {success ? (
        <div className="bp-auth-result" role="status">
          <span className="bp-auth-result__icon">
            <BpIcon name="check_circle" size={34} />
          </span>
          <h3>Đăng ký thành công</h3>
          <p>Tài khoản của bạn đã sẵn sàng. Hãy đăng nhập để bắt đầu đặt sân.</p>
          <NavLink to="/login">
            <Button variant="primary" fullWidth>
              Đến trang đăng nhập
            </Button>
          </NavLink>
        </div>
      ) : (
        <form className="bp-login__form" onSubmit={handleSubmit} aria-busy={submitting}>
          <Input
            label="Tên đăng nhập"
            icon="person"
            name="username"
            autoComplete="username"
            value={username}
            onChange={(e) => setUsername(e.target.value)}
            placeholder="vd: nguyenvana"
            disabled={submitting}
            fullWidth
            autoFocus
          />
          <Input
            label="Số điện thoại"
            icon="phone"
            name="phoneNumber"
            inputMode="numeric"
            autoComplete="tel"
            value={phoneNumber}
            onChange={(e) => setPhoneNumber(e.target.value)}
            placeholder="09xxxxxxxx"
            disabled={submitting}
            fullWidth
          />
          <Input
            label="Email"
            icon="mail"
            type="email"
            name="email"
            autoComplete="email"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            placeholder="ban@example.com"
            disabled={submitting}
            fullWidth
          />
          <Input
            label="Mật khẩu"
            icon="lock"
            type="password"
            name="password"
            autoComplete="new-password"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            hint="8–72 ký tự, có ít nhất một chữ và một số."
            disabled={submitting}
            fullWidth
          />
          <Input
            label="Xác nhận mật khẩu"
            icon="lock_reset"
            type="password"
            name="confirmPassword"
            autoComplete="new-password"
            value={confirmPassword}
            onChange={(e) => setConfirmPassword(e.target.value)}
            disabled={submitting}
            fullWidth
          />
          <div className={['bp-login__error', error ? 'bp-login__error--show' : ''].filter(Boolean).join(' ')} role="alert">
            {error ? (
              <>
                <BpIcon name="error" size={20} />
                <span>{error}</span>
              </>
            ) : null}
          </div>
          <Button type="submit" variant="primary" size="lg" fullWidth loading={submitting} disabled={submitting}>
            Tạo tài khoản <BpIcon name="person_add" size={20} />
          </Button>
          <p className="bp-auth-back">
            Đã có tài khoản? <NavLink to="/login">Đăng nhập</NavLink>
          </p>
        </form>
      )}
    </AuthPageLayout>
  );
}
