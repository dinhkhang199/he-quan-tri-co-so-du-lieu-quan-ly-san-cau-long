# tests/concurrency — Demo 4 lỗi cô lập giao dịch (isolation anomalies)

Các demo này dùng **2 database session thực** (2 tiến trình `sqlcmd` / 2 cửa sổ
SSMS), đồng bộ bằng **bảng cờ** (`_LUTestSync`, `_DRTestSync`, `_NRTestSync`,
`_PhTestSync`) — mỗi session báo cờ ngoài transaction để session kia thấy ngay,
không cần canh giờ thủ công. Mỗi file chạy **cả 2 phase** `UNSAFE` rồi `FIXED`
trong cùng một lần chạy.

## Yêu cầu
- Đã chạy `database/00..08` (DB `BadmintonCourtManagement` sẵn sàng).
- 2 kết nối DB song song (`sqlcmd` hoặc SSMS).

## Danh sách demo

| Demo | File Session A | File Session B | Hành vi UNSAFE | Fix |
|------|----------------|----------------|----------------|-----|
| **LOST UPDATE** | `lost_update_session_A.sql` | `lost_update_session_B.sql` | Cả A/B đọc `PricePerHour=100.000`; B ghi `120.000`, A ghi đè `150.000` dựa giá cũ → mất +20.000 | Đọc bằng `UPDLOCK` → nối tiếp, final `170.000` |
| **DIRTY READ** | `dirty_read_session_A.sql` | `dirty_read_session_B.sql` | A `UPDATE` chưa commit; B ở `READ UNCOMMITTED` đọc được giá dirty `200.000`, sau rollback biến mất | `READ COMMITTED` → B bị block, chỉ đọc giá đã commit |
| **NON-REPEATABLE READ** | `nonrepeatable_session_A.sql` | `nonrepeatable_session_B.sql` | A đọc `100.000`, B update+commit `120.000`, A đọc lại thấy khác | `REPEATABLE READ` → S-lock giữ đến hết tran, B bị block |
| **PHANTOM READ** | `phantom_session_A.sql` | `phantom_session_B.sql` | A đếm booking theo predicate (Court+Date), B INSERT thêm row khớp predicate → số tăng | `SERIALIZABLE` → range lock giữ predicate, B bị block |
| **TOCTOU** | `toctou_booking_vs_deactivate_session_A.sql` | `toctou_booking_vs_deactivate_session_B.sql` | B giữ UPDLOCK sân C1 rồi deactivate+commit ngay trong lúc A đang `sp_BookCourt` → nếu SP không đọc lại IsActive dưới khóa sẽ tạo PENDING trên sân inactive | `sp_BookCourt` re-read Court dưới khóa (UPDLOCK+ROWLOCK+HOLDLOCK) → THROW 50013, không tạo PENDING |

## Chạy bằng sqlcmd (2 session tự động)

> Mỗi demo gồm 2 file `_session_A` và `_session_B`. **Session A phải chạy trước**,
> session B khởi động sau khoảng 3 giây (cả hai kết nối cùng "Base DB" đã build).

```
# Session A (chạy trước — tạo bảng cờ + chạy phase UNSAFE và FIXED)
sqlcmd -S .\SQLEXPRESS -E -f 65001 -i tests\concurrency\lost_update_session_A.sql -o ..\evidence\lostupdate_A.txt
# Session B (khởi động ~3s sau A — chờ cờ của A rồi hành động theo từng phase)
Start-Sleep 3; sqlcmd -S .\SQLEXPRESS -E -f 65001 -i tests\concurrency\lost_update_session_B.sql -o ..\evidence\lostupdate_B.txt
```

Thay `lost_update` → `dirty_read` / `nonrepeatable` / `phantom` / `toctou_booking_vs_deactivate`
tương ứng.
Session A tạo mới bảng cờ ở đầu (luôn sạch); Session B chỉ tạo nếu chưa có và
**không bao giờ xóa** bảng cờ để không làm mất cờ của A.

> TOCTOU demo yêu cầu C1 đang ACTIVE trước khi chạy và **không thuộc** canonical
> build 00→15: nó nằm ngoài thứ tự build để không làm thay đổi object set sản xuất.

## Chú thích kết quả mong đợi (mỗi file in ra cả 2 phase)
- Lost Update: UNSAFE final `150.000` ("LOST UPDATE xảy ra"); FIXED final
  `170.000` ("ASSERTION PASS") — nối tiếp, không mất phép cập nhật.
- Dirty Read: UNSAFE B đọc `200000` dù A rollback ("DIRTY READ"); FIXED B đọc
  giá ĐÃ COMMIT `100000`, không thấy lệnh chưa commit ("bị ngăn").
- Non-repeatable: UNSAFE A thấy `100000` → `120000` ("NON-REPEATABLE READ");
  FIXED 2 lần đọc đều `100000` ("bị ngăn").
- Phantom: UNSAFE COUNT tăng dù đã commit; FIXED `f1 = f2` ("PHANTOM bị ngăn").

## Cleanup
Mỗi script A tự reset dữ liệu giá sân C5 về `100.000` và xóa booking sentinel
`B0000A00-...` theo thứ tự FK (Notifications → ActivityLogs → Bookings). Bảng cờ
`_*TestSync` sẽ được dọn trong đợt residue-cleanup cuối phase 1.
Không cần thao tác thủ công sau demo.