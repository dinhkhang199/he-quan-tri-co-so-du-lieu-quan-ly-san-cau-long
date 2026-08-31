import { strict as assert } from 'node:assert';
import test from 'node:test';
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

test('AV-01 chuẩn hóa username và số điện thoại', () => {
  assert.equal(normalizeUsername('  user.name  '), 'user.name');
  assert.equal(normalizePhone('0912 345-678'), '0912345678');
  assert.equal(normalizePhone('0912.345.678'), '0912345678');
  assert.equal(normalizeEmail('  User.Name@Example.COM '), 'user.name@example.com');
});

test('AV-07 email hợp lệ và được giới hạn độ dài', () => {
  for (const value of ['user@example.com', 'a.b+c@sub.example.vn']) {
    assert.equal(emailError(value), null, value);
  }
  for (const value of ['user', 'user@localhost', 'user name@example.com', `${'a'.repeat(250)}@x.com`]) {
    assert.ok(emailError(value), value);
  }
});

test('AV-02 username hợp lệ', () => {
  for (const value of ['abc', 'user_01', 'user.name', 'user-name']) {
    assert.equal(usernameError(value), null, value);
  }
});

test('AV-03 username quá ngắn, có khoảng trắng hoặc ký tự lạ bị chặn', () => {
  for (const value of ['ab', 'user name', 'người_dùng', 'user@name']) {
    assert.ok(usernameError(value), value);
  }
});

test('AV-04 số điện thoại phải có 9–15 chữ số', () => {
  assert.equal(phoneError('0912345678'), null);
  for (const value of ['12345678', '1234567890123456', '09123abc45']) {
    assert.ok(phoneError(value), value);
  }
});

test('AV-05 mật khẩu phải dài 8–72 ký tự và có chữ lẫn số', () => {
  assert.equal(passwordError('MatKhau1'), null);
  assert.ok(passwordError('Short1'));
  assert.ok(passwordError('onlyletters'));
  assert.ok(passwordError('12345678'));
  assert.ok(passwordError(`A1${'x'.repeat(71)}`));
});

test('AV-06 mã khôi phục phải đúng 6 chữ số', () => {
  assert.equal(resetCodeError('000001'), null);
  for (const value of ['12345', '1234567', '123a56', ' 123456']) {
    assert.ok(resetCodeError(value), value);
  }
});
