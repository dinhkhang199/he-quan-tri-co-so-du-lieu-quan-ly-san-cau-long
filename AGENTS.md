# AGENTS.md — BadmintonCourtManagement Phase 2

This file is the mandatory entry point for any coding agent (OpenCode, Antigravity, Codex, etc.).

## 1. Read-before-work order
Before making any change, read in this order:
1. `AGENTS.md`
2. `docs/PHASE2_CONTEXT.md`
3. `docs/UI_SCREEN_MAP.md`
4. `docs/IMPLEMENTATION_PLAN.md`
5. repository `README.md`
6. the relevant SQL files in `database/`, especially `06_procedures.sql`, `07_triggers.sql`, `08_security.sql`
7. the relevant locked Stitch `code.html` + `screen.png`

Do not rely on previous agent memory. The repository is the memory.

## 2. Source-of-truth priority
When sources conflict, use this priority:
1. `QuanLySanCauLong_IMPLEMENTATION_CONTRACT_v2.0`
2. current Phase 1 SQL implementation in `database/`
3. these Phase 2 context files
4. locked Stitch UI exports
5. agent assumptions/suggestions

Never change a business rule merely to make application code easier.

## 3. Hard safety rules
- Microsoft SQL Server + T-SQL only.
- Phase 1 database is already hardened and tested. Do **not** casually modify `database/`, `tests/`, or `evidence/`.
- If an app requirement appears impossible with the existing DB contract, stop and report the mismatch before editing SQL.
- Database is the final source of truth for booking validity, authorization, state, overlap and ownership.
- Do not implement direct INSERT/UPDATE/DELETE against core tables from the app. Use the contract Stored Procedures.
- Preserve `SESSION_CONTEXT('UserId')` and `SESSION_CONTEXT('Role')` semantics established by `sp_Login`.
- Do not trust role, UserId, OwnerId, price, status or availability sent by the browser as authorization/business truth.
- Never hard-code UI logic to bypass Stored Procedure validation.
- Disable duplicate submissions while a mutation is running.
- Catch SQL errors and present understandable UI messages; app must not hang/crash.
- After every successful mutation, reconcile/refresh from the DB.
- Connection strings/secrets belong in local config/environment variables and must not be committed.

## 4. Locked project scope
Roles:
- `CUSTOMER`
- `MANAGER`
- `COURT_MANAGER`
- Guest behavior exists but `GUEST` is not a privileged authenticated role.

Do not invent generic `ADMIN` authorization.

Out of scope unless a future contract explicitly adds it:
- payment gateway / payment status / refunds / invoices
- membership / loyalty
- ratings / reviews
- equipment / food / services
- CRM / customer-management module
- maintenance workflow
- multi-branch / GPS / maps
- registration / forgot-password
- arbitrary settings/configuration modules

## 5. Locked booking rules
- Operating hours: 06:00–22:00.
- Time resolution: 30 minutes.
- Minimum duration: 1 hour.
- Maximum duration: 3 hours per booking.
- No past bookings.
- `StartTime < EndTime`.
- Overlap interval is `[StartTime, EndTime)`.
- Only `BOOKED` overlap is forbidden; final correctness belongs to DB transaction/locking.

States exactly:
- `PENDING`
- `BOOKED`
- `COMPLETED`
- `CANCELLED`
- `REJECTED`

Allowed transitions:
- `PENDING -> BOOKED -> COMPLETED`
- `PENDING -> REJECTED`
- `PENDING -> CANCELLED`
- `BOOKED -> CANCELLED`

No resurrection from final states.

Customer cancellation:
- own `PENDING`: allowed
- own `BOOKED`: allowed only when at least 3 hours remain before `StartTime`
- `COMPLETED` / `REJECTED`: not cancellable

Manager/Court Manager cancellation follows Stored Procedure authorization/state rules; do not apply the Customer 3-hour rule blindly to them.

## 6. Court ownership
- `MANAGER`: system-wide scope.
- `COURT_MANAGER`: only courts where `OwnerId` belongs to the current actor, plus bookings/statistics for those courts.
- Ownership must be enforced by Stored Procedures, not only by UI filtering.
- Court deactivation is soft delete: `IsActive = 0`.
- Do not promise a reactivation workflow unless the DB contract is updated.

## 7. Pricing baseline
Prototype/seed baseline:
- `PricePerHour = 100000` VND/hour
- `PricePerThreeHours = 270000` VND/3 hours
- no surcharge
- no discount
- revenue shown by dashboard is **theoretical booking revenue**, not money actually paid

Use DB-returned prices/costs in the real app. Do not make UI totals authoritative.

## 8. Phase 1 object contract
Views (4):
- `vw_AvailableCourts`
- `vw_BookingHistory`
- `vw_AdminDashboard`
- `vw_AllBookings`

Functions (2):
- `fn_CalculateBookingCost`
- `fn_IsCourtAvailable`

Stored Procedures (14):
- `sp_Login`
- `sp_BookCourt`
- `sp_ApproveBooking`
- `sp_RejectBooking`
- `sp_CancelBooking`
- `sp_CompleteBooking`
- `sp_CreateCourt`
- `sp_UpdateCourt`
- `sp_DeactivateCourt`
- `sp_GetAvailableCourts`
- `sp_GetMyBookings`
- `sp_GetNotifications`
- `sp_MarkNotificationRead`
- `sp_GetDashboard`

Triggers (6):
- `trg_Bookings_AuditInsert`
- `trg_Bookings_AuditStatus`
- `trg_Bookings_NotifyInsert`
- `trg_Bookings_NotifyStatus`
- `trg_Bookings_ValidateState`
- `trg_Bookings_PreventBookedOverlap`

Do not add production DB objects simply because an agent prefers another API shape.

## 9. SQL session requirement — critical
The current DB implementation uses Option A session security:
- `sp_Login` sets `SESSION_CONTEXT('UserId')` and `SESSION_CONTEXT('Role')`.
- Business procedures require the authenticated SQL session context.
- `sp_GetMyBookings` and `sp_GetNotifications` use the current actor and reject impersonation.
- Guest court search is the public exception through `sp_GetAvailableCourts` / `vw_AvailableCourts`.

Therefore the application data-access design must explicitly preserve or correctly re-establish the authenticated SQL session context. Do not implement a connection pattern that logs in on one pooled SQL connection and then executes protected SPs on unrelated connections without session context.

Before implementing authentication, document exactly how connection/session ownership will work.

## 10. UI policy
The Stitch screens listed in `docs/UI_SCREEN_MAP.md` are visually locked.
- Reuse their layout, spacing, typography, colors and badminton branding.
- Convert prototype HTML into maintainable components.
- Remove mock JavaScript, fake delays, fake DB calls and generated fake records.
- Do not redesign already-approved screens unless a real implementation constraint requires it.
- Prefer `sports_badminton` for badminton branding.
- Hanken Grotesk for UI; JetBrains Mono for technical IDs/log traces.

## 11. Technical demo policy
Concurrency/deadlock/phantom evidence already exists in Phase 1 SQL/test assets.
The Manager Booking screen may expose a demo-oriented presentation, but:
- Approve race = two different overlapping PENDING bookings, same court/time, concurrent approve.
- Deadlock is a real lock wait cycle and SQL Server victim error 1205, separate from overlap conflict.
- Phantom Read is a separate isolation-level demonstration.
- UI technical traces should reflect real evidence conceptually; do not invent SQL schema/columns.

## 12. Change discipline
For each implementation phase:
1. inspect relevant SQL contract first
2. implement the smallest coherent slice
3. run lint/build/tests
4. manually verify the target flow
5. show `git status`, `git diff --stat`, relevant diff, test output
6. commit only after review

Do not implement all screens in one unreviewed mega-change.
