# Demo runbook — BadmintonCourtManagement

Chỉ đánh dấu PASS sau khi quan sát output thật. Dùng database sạch theo thứ tự `00` → `08`; mở hai cửa sổ SSMS kết nối cùng database cho demo tương tranh.

## 1. Luồng ứng dụng

1. Guest mở **Tìm sân**, lọc thời gian và xác nhận không thể đặt khi chưa login.
2. Thử login sai, user inactive, rồi login đúng bằng CUSTOMER.
3. CUSTOMER đặt sân; kiểm tra kết quả `PENDING`, lịch sử và notification lấy lại từ DB.
4. Hủy `PENDING`; với `BOOKED`, kiểm tra hint mốc 3 giờ và để `sp_CancelBooking` quyết định cuối.
5. Login COURT_MANAGER; xác nhận chỉ thấy/thao tác sân thuộc `OwnerId` của actor.
6. Login MANAGER; approve/reject PENDING, complete/cancel BOOKED; sau mỗi mutation kiểm tra danh sách được refetch.
7. Mở dashboard; đối chiếu PENDING, BOOKED, active users và **doanh thu lý thuyết** với `sp_GetDashboard`.

## 2. Bốn anomaly bắt buộc

Với mỗi case: chạy Session A trước; khi A in hướng dẫn/đang `WAITFOR`, chạy Session B. Chạy cả phần UNSAFE rồi phần FIXED trong chính cặp script; đọc assertion/output và để script cleanup dữ liệu.

| Case | Session A / Session B | UNSAFE mong đợi | FIXED |
|---|---|---|---|
| Lost Update | `tests/concurrency/lost_update_session_A.sql` / `_B.sql` | một update bị ghi đè | `UPDLOCK`, `HOLDLOCK` tuần tự hóa read–write |
| Dirty Read | `tests/concurrency/dirty_read_session_A.sql` / `_B.sql` | B đọc giá trị chưa commit rồi A rollback | `READ COMMITTED` chỉ đọc dữ liệu commit |
| Non-repeatable Read | `tests/concurrency/nonrepeatable_session_A.sql` / `_B.sql` | hai lần đọc cùng hàng khác nhau | `REPEATABLE READ`, B block đến A commit |
| Phantom Read | `tests/concurrency/phantom_session_A.sql` / `_B.sql` | predicate ở `READ COMMITTED` đổi số hàng | `SERIALIZABLE`, B insert block bởi range lock |

Nếu bỏ lỡ cửa sổ `WAITFOR`, để script cleanup xong và chạy lại từ A; không suy diễn PASS.

## 3. Bonus

- Concurrent approve: chạy `database/11_tests_concurrency_session_A.sql`, rồi `database/12_tests_concurrency_session_B.sql` trong thời gian chờ. Hai PENDING overlap cùng Court/time phải cho `BookedCount <= 1`; production khóa **Court → Booking**.
- Deadlock: chạy `database/13_deadlock_demo_session_A.sql`, rồi `database/14_deadlock_demo_session_B.sql`. UNSAFE tạo vòng A giữ Court/chờ Booking, B giữ Booking/chờ Court; một session nhận 1205. FIXED dùng thứ tự **Court → Booking** ở cả hai session.
- Backup/restore: chạy `database/15_backup_restore_demo.sql` chỉ với tài khoản/quyền và đường dẫn backup phù hợp máy demo; xác nhận restore bằng truy vấn trong script.

## UI-01 → UI-07

- UI-01 login đúng/sai/inactive; UI-02 Guest xem sân nhưng không booking.
- UI-03 CUSTOMER booking tạo PENDING và xuất hiện history; UI-04 manager mutation phản ánh DB.
- UI-05 COURT_MANAGER không thao tác sân owner khác; UI-06 lỗi concurrency/1205 không treo và có retry/reload.
- UI-07 statistics khớp các result set của `sp_GetDashboard`.

Ghi ngày chạy, môi trường, PASS/FAIL và output/screenshot vào evidence; mục chưa chạy phải ghi `NOT RUN`.
