---
name: CourtMaster Pro
colors:
  surface: '#f5faf8'
  surface-dim: '#d6dbd9'
  surface-bright: '#f5faf8'
  surface-container-lowest: '#ffffff'
  surface-container-low: '#f0f5f2'
  surface-container: '#eaefed'
  surface-container-high: '#e4e9e7'
  surface-container-highest: '#dee4e1'
  on-surface: '#171d1c'
  on-surface-variant: '#3d4947'
  inverse-surface: '#2c3130'
  inverse-on-surface: '#edf2f0'
  outline: '#6d7a77'
  outline-variant: '#bcc9c6'
  surface-tint: '#006a61'
  primary: '#00685f'
  on-primary: '#ffffff'
  primary-container: '#008378'
  on-primary-container: '#f4fffc'
  inverse-primary: '#6bd8cb'
  secondary: '#565e74'
  on-secondary: '#ffffff'
  secondary-container: '#dae2fd'
  on-secondary-container: '#5c647a'
  tertiary: '#595c5e'
  on-tertiary: '#ffffff'
  tertiary-container: '#727577'
  on-tertiary-container: '#fbfdff'
  error: '#ba1a1a'
  on-error: '#ffffff'
  error-container: '#ffdad6'
  on-error-container: '#93000a'
  primary-fixed: '#89f5e7'
  primary-fixed-dim: '#6bd8cb'
  on-primary-fixed: '#00201d'
  on-primary-fixed-variant: '#005049'
  secondary-fixed: '#dae2fd'
  secondary-fixed-dim: '#bec6e0'
  on-secondary-fixed: '#131b2e'
  on-secondary-fixed-variant: '#3f465c'
  tertiary-fixed: '#e0e3e5'
  tertiary-fixed-dim: '#c4c7c9'
  on-tertiary-fixed: '#191c1e'
  on-tertiary-fixed-variant: '#444749'
  background: '#f5faf8'
  on-background: '#171d1c'
  surface-variant: '#dee4e1'
typography:
  display-lg:
    fontFamily: Hanken Grotesk
    fontSize: 36px
    fontWeight: '700'
    lineHeight: 44px
  headline-md:
    fontFamily: Hanken Grotesk
    fontSize: 24px
    fontWeight: '600'
    lineHeight: 32px
  title-sm:
    fontFamily: Hanken Grotesk
    fontSize: 18px
    fontWeight: '600'
    lineHeight: 24px
  body-md:
    fontFamily: Hanken Grotesk
    fontSize: 16px
    fontWeight: '400'
    lineHeight: 24px
  label-sm:
    fontFamily: JetBrains Mono
    fontSize: 13px
    fontWeight: '500'
    lineHeight: 16px
    letterSpacing: 0.05em
  headline-lg-mobile:
    fontFamily: Hanken Grotesk
    fontSize: 28px
    fontWeight: '700'
    lineHeight: 36px
rounded:
  sm: 0.25rem
  DEFAULT: 0.5rem
  md: 0.75rem
  lg: 1rem
  xl: 1.5rem
  full: 9999px
spacing:
  base: 4px
  xs: 0.5rem
  sm: 1rem
  md: 1.5rem
  lg: 2rem
  xl: 3rem
  gutter: 1.5rem
  container-padding: 2rem
---

## Brand & Style

Hệ thống thiết kế tập trung vào sự hiệu quả, độ chính xác và tính chuyên nghiệp của một công cụ quản lý vận hành (SaaS). Phong cách chủ đạo là **Modern Corporate**, kết hợp giữa sự sạch sẽ của chủ nghĩa tối giản và tính cấu trúc của các bảng điều khiển dữ liệu hiện đại.

Mục tiêu là tạo ra một môi trường làm việc kỹ thuật số giúp người quản lý sân cầu lông giảm bớt áp lực tinh thần. Giao diện sử dụng các khoảng trắng rộng rãi, phân cấp thông tin rõ ràng và các yếu tố tương tác tinh tế để tạo cảm giác tin cậy và học thuật. Trải nghiệm người dùng tập trung vào tốc độ xử lý tác vụ và khả năng hiển thị dữ liệu lớn một cách trực quan.

## Colors

Bảng màu được lấy cảm hứng từ sắc xanh đặc trưng của thảm sân cầu lông tiêu chuẩn, kết hợp với các tông màu trung tính để tạo sự cân bằng chuyên nghiệp.

- **Primary (Teal):** Sử dụng cho các hành động chính (CTA), tiêu đề quan trọng và các trạng thái tích cực. Mang lại cảm giác tươi mới nhưng vẫn đủ nghiêm túc.
- **Secondary (Navy/Slate):** Dùng cho hệ thống điều hướng (navigation) và văn bản chính, tạo nền tảng vững chãi và chuyên nghiệp.
- **Neutral Background:** Sử dụng màu xám trắng cực nhẹ (`#F8FAFC`) để giảm mỏi mắt khi làm việc lâu trên dashboard.
- **Semantic Colors:** Hệ thống màu trạng thái được tách biệt rõ ràng để quản lý đặt sân:
  - **Pending:** Vàng hổ phách (Cần chú ý).
  - **Booked:** Xanh dương (Đã xác nhận).
  - **Rejected/Error:** Đỏ (Cảnh báo/Hủy bỏ).
  - **Completed:** Xanh lá (Hoàn tất).

## Typography

Sử dụng **Hanken Grotesk** làm phông chữ chủ đạo nhờ cấu trúc hình học hiện đại, độ dễ đọc cao trong các bảng dữ liệu phức tạp. 

Để tăng tính "học thuật" và kỹ thuật cho các dữ liệu số hoặc mã đặt chỗ (Booking ID), hệ thống sử dụng **JetBrains Mono** cho các nhãn (labels) và dữ liệu bảng. Sự kết hợp này giúp người dùng phân biệt nhanh chóng giữa nội dung văn bản mô tả và các tham số dữ liệu thô. Phân cấp chữ được thiết lập chặt chẽ thông qua trọng lượng (weight) thay vì chỉ dựa vào kích thước.

## Layout & Spacing

Hệ thống sử dụng **Fluid Grid** 12 cột cho khu vực nội dung chính với lề (margin) cố định 32px ở hai bên trên desktop. 

Quy tắc khoảng cách dựa trên hệ số 4px để đảm bảo sự đồng bộ tuyệt đối. Các thành phần trong Card sử dụng padding `1.5rem` (md) để tạo sự thông thoáng. Đối với các bảng dữ liệu (Data Grid), khoảng cách dòng được thu hẹp lại để tối ưu hóa lượng thông tin hiển thị trên một màn hình nhưng vẫn đảm bảo không gây rối mắt bằng cách sử dụng các đường kẻ phân cách mảnh.

## Elevation & Depth

Thiết kế sử dụng tư duy **Tonal Layering** kết hợp với **Ambient Shadows** để phân cấp.

- **Mặt nền (Level 0):** Màu `#F8FAFC`, không bóng.
- **Card nội dung (Level 1):** Nền trắng tuyệt đối, sử dụng bóng đổ cực mờ, tán rộng (Blur 15px, Opacity 4%, Y-offset 2px) để tạo cảm giác nổi nhẹ nhàng trên nền xám.
- **Modal & Popovers (Level 2):** Bóng đổ đậm hơn để tách biệt hẳn với nội dung bên dưới, kết hợp với một lớp phủ (overlay) màu Slate mờ 40%.
- **Trạng thái Concurrent/Deadlock:** Sử dụng lớp phủ kính mờ (Backdrop blur 8px) trên các vùng bị ảnh hưởng để chỉ thị trạng thái đang xử lý hoặc bị khóa do xung đột dữ liệu.

## Shapes

Hệ thống sử dụng bo góc mức độ **Rounded (0.5rem)** cho hầu hết các thành phần như Card, Input và Buttons. Đây là tỷ lệ vàng tạo ra sự hiện đại nhưng vẫn giữ được cấu trúc ngay ngắn, chuyên nghiệp.

Riêng các Badge trạng thái (Pending, Booked...) sử dụng bo góc dạng **Pill-shaped** để phân biệt rõ ràng với các nút bấm chức năng, giúp người dùng nhận diện nhanh đó là thông tin hiển thị chứ không phải phần tử tương tác chính.

## Components

### 1. Hệ thống Badge Trạng thái
- **Cấu trúc:** Nền màu nhạt (10% opacity của màu chủ đạo) + Chữ màu đậm + Icon chấm tròn (dot).
- **PENDING:** Nền hổ phách nhạt, chữ nâu đậm.
- **BOOKED:** Nền xanh dương nhạt, chữ xanh đậm.
- **REJECTED/CANCELLED:** Nền đỏ/xám nhạt, chữ đỏ/xám đậm.

### 2. Data Table (Danh sách đặt sân)
- Header bảng sử dụng nền xám rất nhạt, chữ in hoa, font JetBrains Mono cỡ nhỏ.
- Hàng trong bảng có hiệu ứng `hover:bg-slate-50` để dễ theo dõi dòng.
- Các ô dữ liệu số được căn phải để dễ so sánh.

### 3. Trạng thái Concurrency & Deadlock
- **Loading Skeleton:** Sử dụng các mảng xám chuyển động mượt (shimmer effect) thay thế cho nội dung chữ và hình ảnh.
- **Retry State:** Khi xảy ra deadlock, card nội dung sẽ mờ đi, hiển thị icon xoay nhẹ và nút "Thử lại" nổi bật ở trung tâm vùng bị ảnh hưởng.
- **Confirmation Modal:** Thiết kế tối giản, tập trung vào hai hành động tương phản: "Hủy bỏ" (Ghost button) và "Xác nhận" (Solid primary button).

### 4. Thông báo (Toasts)
- Nằm ở góc trên bên phải màn hình.
- Có thanh progress bar nhỏ ở dưới đáy toast để chỉ thị thời gian tự đóng.
- Sử dụng icon đặc trưng cho từng loại (Success: Check, Warning: Alert, Error: X-circle).