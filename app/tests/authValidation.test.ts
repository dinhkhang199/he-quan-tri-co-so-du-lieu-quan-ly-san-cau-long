import test from 'node:test';
import assert from 'node:assert/strict';
import {
  emailError,
  normalizeEmail,
  normalizePhone,
  normalizeUsername,
  passwordError,
  phoneError,
  resetCodeError,
  usernameError,
} from '../src/server/authValidation.js';

test('authValidation normalizers trim and clean input', () => {
  assert.equal(normalizeUsername('  customer_99  '), 'customer_99');
  assert.equal(normalizePhone('090-123.456 7'), '0901234567');
  assert.equal(normalizeEmail('  Customer.One@Example.COM  '), 'customer.one@example.com');
});

test('usernameError enforces allowed length and character set', () => {
  assert.equal(usernameError('ab'), 'Tên đăng nhập phải dài 3–50 ký tự và chỉ gồm chữ, số, dấu chấm, gạch dưới hoặc gạch ngang.');
  assert.equal(usernameError('valid_user.01'), null);
  assert.equal(usernameError('user with spaces'), 'Tên đăng nhập phải dài 3–50 ký tự và chỉ gồm chữ, số, dấu chấm, gạch dưới hoặc gạch ngang.');
});

test('phoneError enforces 9 to 15 digits', () => {
  assert.equal(phoneError('091234567'), null);
  assert.equal(phoneError('12345678'), 'Số điện thoại phải gồm 9–15 chữ số.');
  assert.equal(phoneError('0912345678901234'), 'Số điện thoại phải gồm 9–15 chữ số.');
  assert.equal(phoneError('090123456a'), 'Số điện thoại phải gồm 9–15 chữ số.');
});

test('emailError enforces safe email shape and required presence', () => {
  assert.equal(emailError('user@example.com'), null);
  assert.equal(emailError(''), 'Email là bắt buộc.');
  assert.equal(emailError(undefined), 'Email là bắt buộc.');
  assert.equal(emailError('plainaddress'), 'Email không đúng định dạng.');
  assert.equal(emailError('user@domain'), 'Email không đúng định dạng.');
  assert.equal(emailError('a@b.c'), 'Email không đúng định dạng.');
});

test('passwordError enforces length and letter+digit mixture', () => {
  assert.equal(passwordError('short1'), 'Mật khẩu phải dài từ 8 đến 72 ký tự.');
  assert.equal(passwordError('alllettersnohere'), 'Mật khẩu phải có ít nhất một chữ và một số.');
  assert.equal(passwordError('1234567890'), 'Mật khẩu phải có ít nhất một chữ và một số.');
  assert.equal(passwordError('validPass123'), null);
});

test('resetCodeError enforces exact 6 digits', () => {
  assert.equal(resetCodeError('123456'), null);
  assert.equal(resetCodeError('12345'), 'Mã khôi phục phải gồm đúng 6 chữ số.');
  assert.equal(resetCodeError('1234567'), 'Mã khôi phục phải gồm đúng 6 chữ số.');
  assert.equal(resetCodeError('12345a'), 'Mã khôi phục phải gồm đúng 6 chữ số.');
});
