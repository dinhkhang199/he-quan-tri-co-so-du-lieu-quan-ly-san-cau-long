import { useState } from 'react';
import type { FormEvent } from 'react';
import { NavLink } from 'react-router-dom';
import { forgotPasswordRequest, resetPasswordRequest } from '../api/client';
import { AuthPageLayout } from '../components/AuthPageLayout';
import { BpIcon } from '../components/BpIcon';
import { Button } from '../components/Button';
import { Input } from '../components/Input';

type Step = 'identify' | 'reset' | 'done';

export function ForgotPasswordPage() {
  const [step, setStep] = useState<Step>('identify');
  const [username, setUsername] = useState('');
  const [email, setEmail] = useState('');
  const [resetCode, setResetCode] = useState('');
  const [password, setPassword] = useState('');
  const [confirmPassword, setConfirmPassword] = useState('');
  const [developmentCode, setDevelopmentCode] = useState<string | null>(null);
  const [emailSent, setEmailSent] = useState(false);
  const [emailMasked, setEmailMasked] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);

  async function requestCode(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (submitting) return;
    setSubmitting(true);
    setError(null);
    try {
      const result = await forgotPasswordRequest({ username, email });
      // Production keeps account-enumeration protection (matched is omitted).
      // On the local course demo, however, the backend can safely tell this UI
      // that no reset code was created. Do not advance to an impossible step.
      if (result.matched === false) {
        setError('Tên đăng nhập hoặc email không khớp. Vui lòng kiểm tra lại.');
        return;
      }
      setDevelopmentCode(result.developmentCode ?? null);
      setEmailSent(result.emailSent === true);
      setEmailMasked(result.emailMasked ?? null);
      if (result.developmentCode) setResetCode(result.developmentCode);
      setStep('reset');
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Không thể tạo mã khôi phục.');
    } finally {
      setSubmitting(false);
    }
  }

  async function resetPassword(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (submitting) return;
    if (password !== confirmPassword) {
      setError('Mật khẩu xác nhận không khớp.');
      return;
    }
    setSubmitting(true);
    setError(null);
    try {
      await resetPasswordRequest({ username, email, resetCode, password, confirmPassword });
      setStep('done');
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Không thể đổi mật khẩu.');
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <AuthPageLayout title="Quên mật khẩu" subtitle="Nhận mã khôi phục qua email đã đăng ký">
      {step === 'identify' ? (
        <form className="bp-login__form" onSubmit={requestCode} aria-busy={submitting}>
          <Input label="Tên đăng nhập" icon="person" value={username} onChange={(e) => setUsername(e.target.value)}
            autoComplete="username" disabled={submitting} fullWidth autoFocus />
          <Input label="Email đã đăng ký" icon="mail" type="email" value={email} onChange={(e) => setEmail(e.target.value)}
            autoComplete="email" placeholder="ban@example.com" disabled={submitting} fullWidth />
          <AuthError message={error} />
          <Button type="submit" variant="primary" size="lg" fullWidth loading={submitting} disabled={submitting}>
            Gửi mã qua email <BpIcon name="send" size={20} />
          </Button>
          <p className="bp-auth-back"><NavLink to="/login">Quay lại đăng nhập</NavLink></p>
        </form>
      ) : null}

      {step === 'reset' ? (
        <form className="bp-login__form" onSubmit={resetPassword} aria-busy={submitting}>
          <div className="bp-auth-notice" role="status">
            <BpIcon name="mark_email_read" size={22} />
            <span>{emailSent ? `Đã gửi mã tới ${emailMasked ?? 'email của bạn'}.` : 'Mã có hiệu lực trong 10 phút và tối đa 5 lần nhập sai.'}</span>
          </div>
          {developmentCode ? (
            <div className="bp-auth-dev-code">
              <span>{emailSent ? 'Mã dùng thử trên máy local' : 'Local chưa cấu hình SMTP — dùng mã này'}</span><strong>{developmentCode}</strong>
            </div>
          ) : null}
          <Input label="Mã khôi phục" icon="pin" value={resetCode} onChange={(e) => setResetCode(e.target.value)}
            inputMode="numeric" autoComplete="one-time-code" maxLength={6} disabled={submitting} fullWidth autoFocus />
          <Input label="Mật khẩu mới" icon="lock" type="password" value={password} onChange={(e) => setPassword(e.target.value)}
            autoComplete="new-password" hint="8–72 ký tự, có ít nhất một chữ và một số." disabled={submitting} fullWidth />
          <Input label="Xác nhận mật khẩu mới" icon="lock_reset" type="password" value={confirmPassword}
            onChange={(e) => setConfirmPassword(e.target.value)} autoComplete="new-password" disabled={submitting} fullWidth />
          <AuthError message={error} />
          <Button type="submit" variant="primary" size="lg" fullWidth loading={submitting} disabled={submitting}>
            Đặt lại mật khẩu <BpIcon name="password" size={20} />
          </Button>
          <button type="button" className="bp-auth-link-button" onClick={() => { setStep('identify'); setError(null); setDevelopmentCode(null); }}>
            Gửi lại mã khác
          </button>
        </form>
      ) : null}

      {step === 'done' ? (
        <div className="bp-auth-result" role="status">
          <span className="bp-auth-result__icon"><BpIcon name="check_circle" size={34} /></span>
          <h3>Đổi mật khẩu thành công</h3>
          <p>Mã khôi phục đã bị vô hiệu hóa. Bạn có thể đăng nhập bằng mật khẩu mới.</p>
          <NavLink to="/login"><Button variant="primary" fullWidth>Đăng nhập ngay</Button></NavLink>
        </div>
      ) : null}
    </AuthPageLayout>
  );
}

function AuthError({ message }: { message: string | null }) {
  return (
    <div className={['bp-login__error', message ? 'bp-login__error--show' : ''].filter(Boolean).join(' ')} role="alert">
      {message ? <><BpIcon name="error" size={20} /><span>{message}</span></> : null}
    </div>
  );
}
