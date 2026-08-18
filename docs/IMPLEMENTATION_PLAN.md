# Phase 2 Implementation Plan

Work sequentially. Do not jump to all screens at once.

## Phase 2.0 — Architecture & bootstrap
Goal: create a safe application skeleton under `app/` without implementing business features.

Tasks:
- read all context files and repo README
- inspect current SQL Server procedures/security/session behavior
- inspect locked Stitch export
- detect local toolchain/runtime constraints
- propose the smallest suitable application stack
- explicitly explain how SQL `SESSION_CONTEXT` will be preserved/re-established across requests
- create `app/` skeleton only after architecture is agreed
- add local configuration template (`.env.example` or framework equivalent) without secrets
- add lint/build/run scripts and a minimal health/start page
- do not edit Phase 1 SQL

Exit criteria:
- app starts locally
- architecture note exists
- no business feature is falsely claimed complete
- no secrets committed
- `database/`, `tests/`, `evidence/` unchanged

## Phase 2.1 — Design system + shared shells
- convert Stitch visual tokens into application styles
- shared logo/brand
- Customer shell
- Manager/Court Manager shell
- reusable status badge, button, loading, empty/error states
- route skeletons only

Exit criteria: visual shell matches Stitch, no mock DB business behavior.

## Phase 2.2 — Authentication
- implement `sp_Login`
- handle valid / invalid / inactive
- establish secure app session
- preserve SQL session-context requirements
- role-based route guards/navigation
- logout disposes/clears authenticated context correctly

Exit criteria: seeded MANAGER, COURT_MANAGER, CUSTOMER can login to correct shell; inactive/invalid cannot.

## Phase 2.3 — Guest/Customer court search
- public `sp_GetAvailableCourts`
- date/time filters
- 06:00–22:00, 30-min UX, 1–3h
- guest CTA asks login before booking
- customer can continue to booking detail

Exit criteria: results come from DB, not hard-coded cards.

## Phase 2.4 — Customer booking creation
- booking detail screen
- call `sp_BookCourt`
- disable double click
- show PENDING success
- handle invalid time/overlap/DB errors
- refresh/reconcile from DB

Exit criteria: one successful request creates exactly one PENDING booking and trigger side effects occur through DB.

## Phase 2.5 — Customer history + cancellation
- `sp_GetMyBookings`
- all five statuses
- `sp_CancelBooking`
- Customer PENDING cancellation
- Customer BOOKED cancellation only >=3h before start
- refresh after mutation

Exit criteria: ownership/state/deadline enforcement works from DB.

## Phase 2.6 — Notifications
- shared notification list component
- `sp_GetNotifications`
- `sp_MarkNotificationRead`
- DB-driven unread indicators and timestamps
- Customer/Manager/Court Manager reuse with correct shell

Exit criteria: mark-read uses real NotificationId and persists after refresh.

## Phase 2.7 — Manager/Court Manager booking management
- list admin bookings using contract-compatible DB source
- PENDING: approve/reject
- BOOKED: complete/cancel
- final states: no mutation controls
- Court Manager scope by DB ownership
- catch deadlock victim 1205 and expose retry guidance

Exit criteria: permissions/state transitions cannot be bypassed from UI.

## Phase 2.8 — Court management
- create/update/deactivate
- Manager all courts
- Court Manager owned courts only
- soft delete only
- no reactivation feature

Exit criteria: ownership is enforced by DB and history remains intact.

## Phase 2.9 — Dashboard
- `sp_GetDashboard`
- pending/booked counts
- active users
- theoretical revenue
- daily revenue
- top courts
- role-appropriate scope

Exit criteria: no prototype KPI/chart values remain hard-coded.

## Phase 2.10 — Technical demo integration
- present existing concurrency/deadlock/phantom evidence in Manager Booking demo UI if required
- do not replace Phase 1 SQL evidence with browser simulation
- deadlock 1205 retry UX should be real where applicable

## Phase 2.11 — Hardening & end-to-end QA
Minimum E2E flows:
1. Guest search -> login -> book -> PENDING
2. Manager approves -> BOOKED
3. Customer history refresh -> BOOKED
4. Customer receives/views status notification
5. Reject path
6. Cancel PENDING path
7. Cancel BOOKED eligible/ineligible path
8. Complete path
9. Court Manager ownership denial path
10. inactive court/user path
11. duplicate submit path
12. overlap conflict path
13. DB error/deadlock retry path

Also verify responsive layout against Stitch screenshots.

## Phase 2.12 — Documentation/demo packaging
Only after source is stable:
- update README application run instructions
- capture application evidence
- prepare demo script
- then update report/slide so they describe the actual source, not an imagined system

## Git discipline
Suggested commits:
- `feat(app): bootstrap phase 2 application`
- `feat(app): add shared design system and layouts`
- `feat(app): implement session-backed authentication`
- `feat(app): implement court availability search`
- `feat(app): implement customer booking flow`
- `feat(app): implement booking history and cancellation`
- `feat(app): implement notifications`
- `feat(app): implement booking management`
- `feat(app): implement court management`
- `feat(app): implement dashboard`
- `test(app): harden end-to-end database flows`

Before each commit, review the diff and test output.
