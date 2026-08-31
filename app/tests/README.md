# Test tầng app (không cần SQL Server)

Sáu bộ test dưới đây dùng `node:test` + `tsx` (devDependency), không mở kết nối
DB. Chạy `npm ci` một lần trước khi chạy test.

```bash
cd app
node --import tsx --test tests/authValidation.test.ts
node --import tsx --test tests/retry.test.ts
node --import tsx --test tests/rateLimit.test.ts
node --import tsx --test tests/sessionExpiry.test.ts
node --import tsx --test tests/time.test.ts
node --import tsx --test tests/spError.test.ts
```

Hoặc chạy tất cả:

```bash
cd app
for f in tests/*.test.ts; do node --import tsx --test "$f"; done
```

| File | Số test | Phủ |
|---|---|---|
| `authValidation.test.ts` | 6 | Đăng ký/quên mật khẩu — chuẩn hóa và validation username, điện thoại, mật khẩu, mã 6 số |
| `retry.test.ts` | 11 | IMP-10 — tự thử lại 1205/1222, không thử lại lỗi nghiệp vụ, backoff + jitter, trần 3 lần |
| `rateLimit.test.ts` | 9 | IMP-11 — chặn 429, `Retry-After`, đếm theo IP, hết cửa sổ, `limit = 0` tắt |
| `sessionExpiry.test.ts` | 12 | IMP-13 — TTL tuyệt đối, idle timeout, touch monotonic, quét 2000 phiên bỏ rơi và giữ phiên đang dùng |
| `time.test.ts` | 30 | Luật khung giờ 06:00–22:00, bước 30 phút, 1–3 giờ, cùng ngày, quá khứ, dữ liệu rác, GUID |
| `spError.test.ts` | 9 | Bản đồ lỗi SQL → tiếng Việt, hai mã mới 1222/2601, lỗi không phải `Error` |

## Những gì test này KHÔNG kiểm tra được

Mọi hành vi cần SQL Server thật (khoá `UPDLOCK`, deadlock, `LOCK_TIMEOUT`,
unique filtered index, CHECK constraint, trần worker) nằm ở:

- `tests/regression/imp_regression.sql` — test từng cải tiến trên DB thật
- `tests/static/check_static.py` — kiểm tra tĩnh, không cần DB
- `tests/concurrency/`, `tests/load/` — demo tranh chấp và tải 2000 người
- `docs/TEST_MATRIX.md` — bảng liệt kê từng khả năng và nơi nó được kiểm tra
