# Locked Stitch UI Screen Map

Source export: `stitch_badminton_court_management_system.zip`

Use each `screen.png` as the visual reference and `code.html` as a styling/layout source. Prototype JS is not production logic.

| App screen | Locked Stitch folder | Role/scope | DB integration |
|---|---|---|---|
| Login | `login_premium_polished_v2_badmintonpro/` | Guest -> authenticated role | `sp_Login` |
| Court search/list | `t_m_s_n_c_u_l_ng_guest_badmintonpro_final/` | Guest + Customer | `sp_GetAvailableCourts` |
| Booking detail/create | `chi_ti_t_t_s_n_badmintonpro_final_polish/` | Customer | `sp_BookCourt` |
| Customer booking history | `l_ch_s_t_s_n_badmintonpro_final_polish/` | Customer | `sp_GetMyBookings`, `sp_CancelBooking` |
| Manager Dashboard | `t_ng_quan_h_th_ng_badmintonpro_manager_production_final/` | Manager; reuse with owned scope for Court Manager | `sp_GetDashboard` |
| Booking management + DB demo | `qu_n_l_booking_badmintonpro_production_final_polish/` | Manager/Court Manager | approve/reject/cancel/complete SPs; technical demo uses Phase 1 evidence |
| Court management | `qu_n_l_s_n_badmintonpro_admin_production_final_polish/` | Manager/Court Manager | create/update/deactivate SPs |
| Notifications | `th_ng_b_o_badmintonpro_production_final_logic_cleaned/` | Manager; reuse list for Customer/Court Manager with correct shell/scope | `sp_GetNotifications`, `sp_MarkNotificationRead` |
| Design guide | `courtmaster_pro/DESIGN.md` | shared | visual tokens only |

## Shared visual rules
- Product name: `BadmintonPro`
- Premium teal / white / cool-gray direction
- Primary direction around `#00796F` / contract-approved Stitch teal palette
- Hanken Grotesk for UI
- JetBrains Mono for IDs/technical traces
- rounded cards around 16–18px
- subtle ambient shadows
- `sports_badminton` branding
- no tennis/baseball branding in final app

## Customer shell
Reuse locked customer visual language. Expected top-level destinations:
- Tìm sân
- Lịch sử đặt sân
- Thông báo
- account/logout affordance

Do not invent registration/profile/settings modules just to fill navigation.

## Manager shell
Locked sidebar:
- Bảng điều khiển
- Quản lý booking
- Quản lý sân
- Thông báo
- Đăng xuất

Role label: `[MANAGER]`
Scope: `Phạm vi: Toàn hệ thống`

## Court Manager shell
Reuse the Manager component set; do not duplicate an entire visual system.
Change role/scope presentation:
- `[COURT_MANAGER]`
- `Phạm vi: Sân của tôi`

Real security still belongs to Stored Procedures/OwnerId checks.

## Screen-specific implementation notes
### Login
Remove mock loading/error timers. Real login must distinguish bad credentials and inactive account without crashing.

### Court search
Guest may search without authentication. Court cards must show DB prices and only active/available results returned by DB search logic.

### Booking detail
New booking is `PENDING`, never immediately `BOOKED`.
Validate 30-minute boundaries and 1–3h in UX, but still call `sp_BookCourt` for final decision.

### History
All five states must render. Cancellation controls depend on state/eligibility returned or determined consistently with DB rules. Refresh after cancellation.

### Dashboard
No fake growth percentages required. Revenue copy must say theoretical revenue where appropriate.

### Booking management
PENDING actions: approve/reject.
BOOKED actions: complete/cancel.
Final states: no state-changing action.
Technical DB demo is optional/supporting UI and must not become a second fake booking engine.

### Court management
Show owner context for Manager where useful.
No "Activate" action unless DB contract gains a corresponding workflow.

### Notifications
Remove prototype `setTimeout`, random GUID generation, fake sample appends and simulated SP logging from production behavior.
Use actual DB records and actual `NotificationId`.
