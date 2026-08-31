import nodemailer from 'nodemailer';
import type { AppConfig } from '../config.js';

export interface PasswordResetMailResult {
  configured: boolean;
  sent: boolean;
}

/** Send one password-reset code when SMTP is configured. Local classroom runs
 * intentionally fall back to the development code returned by the API. */
export async function sendPasswordResetMail(
  cfg: AppConfig,
  recipient: string,
  resetCode: string,
): Promise<PasswordResetMailResult> {
  if (!cfg.smtpHost || !cfg.mailFrom) return { configured: false, sent: false };

  const transporter = nodemailer.createTransport({
    host: cfg.smtpHost,
    port: cfg.smtpPort,
    secure: cfg.smtpSecure,
    auth: cfg.smtpUser && cfg.smtpPassword
      ? { user: cfg.smtpUser, pass: cfg.smtpPassword }
      : undefined,
  });

  await transporter.sendMail({
    from: cfg.mailFrom,
    to: recipient,
    subject: 'Mã khôi phục mật khẩu BadmintonPro',
    html: `<p>Mã khôi phục mật khẩu BadmintonPro của bạn là:</p><p style="font-size:28px;font-weight:700;letter-spacing:6px">${resetCode}</p><p>Mã có hiệu lực trong 10 phút và tối đa 5 lần nhập sai.</p>`,
  });

  return { configured: true, sent: true };
}
