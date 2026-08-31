/** Pure validation shared by public authentication routes and unit tests. */

const USERNAME_PATTERN = /^[A-Za-z0-9._-]{3,50}$/;
const PHONE_PATTERN = /^\d{9,15}$/;
const RESET_CODE_PATTERN = /^\d{6}$/;
const EMAIL_PATTERN = /^[^\s@]+@[^\s@]+\.[A-Za-z0-9-]{2,}$/;

export function normalizeUsername(value: string): string {
  return value.trim();
}

export function normalizePhone(value: string): string {
  return value.replace(/[\s.-]/g, '');
}

export function normalizeEmail(value: string): string {
  return value.trim().toLowerCase();
}

export function usernameError(value: string): string | null {
  return USERNAME_PATTERN.test(value)
    ? null
    : 'Tên đăng nhập phải dài 3–50 ký tự và chỉ gồm chữ, số, dấu chấm, gạch dưới hoặc gạch ngang.';
}

export function phoneError(value: string): string | null {
  return PHONE_PATTERN.test(value) ? null : 'Số điện thoại phải gồm 9–15 chữ số.';
}

export function emailError(value: string): string | null {
  return value.length >= 5 && value.length <= 254 && EMAIL_PATTERN.test(value)
    ? null
    : 'Email không hợp lệ.';
}

export function passwordError(value: string): string | null {
  if (value.length < 8 || value.length > 72) return 'Mật khẩu phải dài từ 8 đến 72 ký tự.';
  if (!/[A-Za-z]/.test(value) || !/\d/.test(value)) return 'Mật khẩu phải có ít nhất một chữ và một số.';
  return null;
}

export function resetCodeError(value: string): string | null {
  return RESET_CODE_PATTERN.test(value) ? null : 'Mã khôi phục phải gồm đúng 6 chữ số.';
}
