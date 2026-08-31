/**
 * SQL error number -> stable Vietnamese message map.
 * Numbers come from 06_procedures.sql THROW statements and SQL Server system errors.
 * Technical detail is preserved separately for logs/dev mode.
 */

import type { RequestError } from 'mssql';

export interface MappedError {
  code: number | null;
  /** Stable, user-facing message. Null when no stable mapping exists. */
  message: string | null;
  /** Vietnamese generic fallback message. */
  fallback: string;
  technical: string;
}

/** Map SQL error numbers to stable Vietnamese messages per the Phase 2 context. */
const SQL_ERROR_MAP: Record<number, string> = {
  50001: 'Đăng nhập thất bại: sai tên đăng nhập hoặc mật khẩu.',
  50002: 'Đăng nhập thất bại: tài khoản đã bị vô hiệu hóa (inactive).',
  50010: 'Người dùng không tồn tại, đang inactive, chưa đăng nhập hoặc UserId không khớp phiên đăng nhập.',
  50011: 'Chỉ CUSTOMER mới được tạo booking.',
  50012: 'Sân không tồn tại.',
  50013: 'Sân đang ngừng hoạt động (inactive), không thể đặt.',
  50014: 'Bạn phải nhập đầy đủ thời gian bắt đầu và kết thúc.',
  50015: 'Thời gian kết thúc phải lớn hơn thời gian bắt đầu.',
  50016: 'Không cho phép đặt sân trong quá khứ.',
  50017: 'Thời lượng tối thiểu là 1 giờ.',
  50018: 'Thời lượng tối đa là 3 giờ.',
  50019: 'Thời gian phải theo bước 30 phút (00 hoặc 30, không có giây/mili-giây).',
  50020: 'Booking phải nằm trong khung hoạt động 06:00–22:00.',
  50021: 'Sân đã được đặt (BOOKED) trong khung giờ này.',
  50023: 'Booking phải nằm trong cùng một ngày (không được qua đêm).',
  50030: 'Người dùng không tồn tại, đang inactive, chưa đăng nhập hoặc UserId không khớp phiên đăng nhập.',
  50031: 'Không đủ quyền duyệt booking.',
  50032: 'Booking không tồn tại.',
  50033: 'Court Manager chỉ được duyệt booking thuộc sân của mình.',
  50034: 'Chỉ duyệt được booking ở trạng thái PENDING.',
  50035: 'Không thể approve: booking overlap với một BOOKED khác trên cùng sân.',
  50040: 'Không đủ quyền từ chối booking.',
  50041: 'Booking không tồn tại.',
  50042: 'Court Manager chỉ thao tác booking thuộc sân của mình.',
  50043: 'Chỉ từ chối được booking ở trạng thái PENDING.',
  50050: 'Người dùng không tồn tại, đang inactive, chưa đăng nhập hoặc UserId không khớp phiên đăng nhập.',
  50051: 'Booking không tồn tại.',
  50052: 'Không thể hủy booking đã COMPLETED hoặc REJECTED.',
  50053: 'Booking này đã bị hủy trước đó.',
  50054: 'Customer chỉ được hủy booking của chính mình.',
  50055: 'BOOKED chỉ được Customer tự hủy khi còn tối thiểu 3 giờ trước giờ bắt đầu.',
  50056: 'Court Manager chỉ hủy booking thuộc sân của mình.',
  50057: 'Không đủ quyền hủy booking.',
  50058: 'Hủy booking thất bại: trạng thái đã thay đổi đồng thời.',
  50060: 'Người dùng không tồn tại, đang inactive, chưa đăng nhập hoặc UserId không khớp phiên đăng nhập.',
  50061: 'Booking không tồn tại.',
  50062: 'Chỉ hoàn thành được booking ở trạng thái BOOKED.',
  50063: 'Court Manager chỉ thao tác booking thuộc sân của mình.',
  50064: 'Hoàn thành booking thất bại: trạng thái đã thay đổi đồng thời.',
  50070: 'Người dùng không tồn tại, đang inactive, chưa đăng nhập hoặc UserId không khớp phiên đăng nhập.',
  50071: 'Court Manager chỉ được tạo sân thuộc quyền mình.',
  50072: 'Giá sân phải lớn hơn 0.',
  50080: 'Người dùng không tồn tại, đang inactive, chưa đăng nhập hoặc UserId không khớp phiên đăng nhập.',
  50081: 'Sân không tồn tại.',
  50082: 'Court Manager chỉ được sửa sân thuộc quyền mình.',
  50083: 'Giá sân phải lớn hơn 0.',
  50090: 'Người dùng không tồn tại, đang inactive, chưa đăng nhập hoặc UserId không khớp phiên đăng nhập.',
  50091: 'Sân không tồn tại.',
  50092: 'Court Manager chỉ thao tác sân thuộc quyền mình.',
  50100: 'Không tìm thấy notification của người dùng này.',
  50110: 'Phiên đăng nhập chưa được thiết lập; chỉ MANAGER/COURT_MANAGER được xem dashboard.',
  50120: 'Bạn phải nhập đầy đủ thời gian bắt đầu và kết thúc.',
  50121: 'Thời gian kết thúc phải lớn hơn thời gian bắt đầu.',
  50122: 'Thời gian phải theo bước 30 phút (00 hoặc 30, không có giây/mili-giây).',
  50123: 'Khoảng tìm kiếm phải nằm trong cùng một ngày (không được qua đêm).',
  50124: 'Thời lượng tìm sân phải từ 1 đến 3 giờ.',
  50125: 'Khoảng tìm kiếm phải nằm trong khung hoạt động 06:00–22:00.',
  50126: 'Không cho phép tìm sân trong quá khứ.',
  50200: 'Thông tin đăng ký không hợp lệ.',
  50201: 'Tên đăng nhập đã được sử dụng.',
  50202: 'Số điện thoại đã được sử dụng.',
  50203: 'Mật khẩu phải dài 8–72 ký tự và có cả chữ lẫn số.',
  50204: 'Email đã được sử dụng.',
  50210: 'Không tìm thấy tài khoản khớp thông tin khôi phục.',
  50211: 'Mã khôi phục đã hết hạn hoặc không còn hiệu lực.',
  50212: 'Mã khôi phục không đúng hoặc không hợp lệ.',
  50213: 'Yêu cầu xác thực không hợp lệ.',
  51000: 'Chuyển trạng thái booking không hợp lệ.',
  51001: 'Sân đã có booking được xác nhận (BOOKED) trong khung giờ này.',
  51054: 'Chưa đăng nhập: phải gọi sp_Login trước (SESSION_CONTEXT rỗng) hoặc UserId không khớp.',
  51060: 'Chưa đăng nhập: phải gọi sp_Login trước (SESSION_CONTEXT rỗng) hoặc UserId không khớp.',
  51061: 'Phiên đăng nhập chưa được thiết lập hoặc UserId không khớp.',
  1205: 'Xung đột deadlock (1205). Vui lòng thử lại sau.',
  // IMP-10: SET LOCK_TIMEOUT ở tầng app (SessionDb) làm SQL tự huỷ giao dịch
  // chờ khoá quá lâu thay vì treo vô hạn. Giao dịch đã rollback → thử lại an toàn.
  1222: 'Hệ thống đang quá tải (chờ khoá quá lâu). Vui lòng thử lại sau vài giây.',
  // IMP-09: vi phạm UQ_Bookings_OnePendingPerUserSlot (unique filtered index).
  2601: 'Bạn đã có một yêu cầu đặt sân đang chờ duyệt cho đúng sân và khung giờ này.',
};

/** Peek the TECHNICAL error number out of an unknown mssql error. */
function errNumber(err: unknown): number | null {
  // IMP-12 (lỗi do test SE-07 phát hiện): err có thể là null / undefined / chuỗi
  // (một `throw` không phải Error, hoặc promise reject với undefined). Khi đó
  // đọc thuộc tính `.number` sẽ ném TypeError NGAY TRONG error handler, biến một
  // lỗi nhỏ thành 500 không thông báo. Chặn ngay tại đây.
  if (err === null || (typeof err !== 'object' && typeof err !== 'function')) return null;
  const e = err as Partial<RequestError>;
  if (typeof e.number === 'number') return e.number;
  if (typeof e.code === 'number') return e.code;
  return null;
}

/** Translate any thrown value (mssql RequestError or otherwise) to a mapped error. */
export function mapSqlError(err: unknown): MappedError {
  const code = errNumber(err);
  const technical = err instanceof Error ? `${err.name}: ${err.message}` : String(err);
  if (code !== null && code in SQL_ERROR_MAP) {
    return { code, message: SQL_ERROR_MAP[code]!, fallback: 'Có lỗi từ hệ thống. Vui lòng thử lại.', technical };
  }
  return { code, message: null, fallback: 'Có lỗi từ hệ thống. Vui lòng thử lại.', technical };
}
