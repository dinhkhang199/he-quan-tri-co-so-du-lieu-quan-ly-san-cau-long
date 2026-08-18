# Phase 2 Context — BadmintonCourtManagement

## Project status
Phase 1 (database + technical evidence) is complete on the repository `main` branch. The repository currently centers on:
- `database/` — canonical SQL Server build and tests
- `tests/` — additional transaction/concurrency demonstrations
- `evidence/` — recorded evidence
- `README.md`

Phase 2 adds the application under `app/` while preserving Phase 1 behavior.

The implementation contract states that the product must include a program/source application in addition to the SQL work. The UI contract requires Login, court listing/search, booking, customer history, notifications, booking management, court management and dashboard.

## Core data model
Five core tables only:
- `Users`
- `Courts`
- `Bookings`
- `ActivityLogs`
- `Notifications`

Important court fields:
- `CourtId` UNIQUEIDENTIFIER
- `CourtName`
- `Address`
- `SurfaceType`
- `SizeType`
- `PricePerHour`
- `PricePerThreeHours`
- `ImageUrl`
- `OwnerId`
- `IsActive`
- `CreatedAt`
- `UpdatedAt`

Important notification fields:
- `NotificationId`
- `UserId`
- `BookingId` nullable
- `Message`
- `IsRead`
- `CreatedAt`

Do not model presentation-only titles/icons as DB columns unless the contract changes.

## Authentication and authorization
Seed/demo roles:
- `MANAGER`
- `COURT_MANAGER`
- `CUSTOMER`

`sp_Login` validates the password hash, blocks inactive accounts, updates `LastLogin`, and initializes SQL `SESSION_CONTEXT` for actor identity/role.

The app must not use a browser-provided UserId/Role as an authorization source. The backend/data-access layer must make the DB's session-based security work correctly.

### Required role behavior
Guest:
- can browse/search active courts and prices
- cannot create booking

Customer:
- login
- search active courts
- create booking (`PENDING`)
- view own booking history/cost
- cancel own eligible booking
- view notifications and mark them read

Court Manager:
- manage only owned courts
- approve/reject/cancel/complete bookings for owned courts
- view dashboard/statistics for owned scope
- view notifications relevant to actor

Manager:
- system-wide booking/court operations
- system-wide dashboard
- notifications

## Booking invariants
Availability shown in UI is advisory. The final booking/approval decision must happen in SQL under the Stored Procedure transaction/lock strategy.

Time:
- 06:00–22:00
- 30-minute boundaries
- duration 1–3h
- no past booking

Overlap:
`existing.StartTime < requested.EndTime AND existing.EndTime > requested.StartTime`
with half-open intervals `[StartTime, EndTime)`.

State machine:
- PENDING -> BOOKED -> COMPLETED
- PENDING -> REJECTED
- PENDING -> CANCELLED
- BOOKED -> CANCELLED

Concurrency invariant:
At most one overlapping booking for the same court/time can end in `BOOKED`.
`sp_ApproveBooking` must re-check overlap inside its transaction with locking.

## App mutation pattern
Use this pattern for every mutation:
1. validate basic UX input client-side
2. disable duplicate submission
3. call backend/data layer
4. backend executes the correct Stored Procedure
5. DB decides authorization/business validity
6. on success, refresh/reconcile from DB
7. on failure, keep prior authoritative state and show a user-friendly error

Never optimistic-update irreversible business state before DB success.

## SQL error handling
The app should translate common errors into understandable Vietnamese messages, while retaining technical detail for logs/dev mode.
Examples:
- invalid credentials / inactive user
- unauthorized role/ownership
- invalid booking time/duration
- overlap/availability conflict
- invalid state transition
- cancellation deadline
- deadlock victim 1205: offer retry, do not hang

Do not hide all SQL errors behind a generic "Có lỗi" if a stable business message can be mapped safely.

## Notifications
Use:
- `sp_GetNotifications`
- `sp_MarkNotificationRead`

Rules:
- use the real `NotificationId` GUID for mark-read
- friendly booking code such as `#BK-2026-021` is presentation only
- `IsRead` comes from DB
- relative time comes from actual `CreatedAt`
- unread indicators derive from unread data
- no invented payment/refund/maintenance notification types

## Dashboard
Required metrics:
- PENDING count
- BOOKED count
- active users
- theoretical booking revenue
- daily theoretical revenue
- top courts

Do not label theoretical revenue as collected/paid revenue.

## Court management
Use:
- `sp_CreateCourt`
- `sp_UpdateCourt`
- `sp_DeactivateCourt`

Manager sees system-wide scope.
Court Manager is limited to owned courts.
Deactivate is soft delete. Preserve booking history.

## App technology
The course/contract fixes SQL Server + T-SQL but does not lock a specific client programming framework.
Therefore Phase 2.0 must inspect the local development environment and propose a minimal, maintainable stack before implementation.

The chosen stack must support:
- SQL Server Stored Procedure calls
- deliberate SQL connection/session handling required by `SESSION_CONTEXT`
- role-based routes/layout
- the locked web UI design
- easy local demo for the course presentation

Do not pick a stack solely because an agent prefers it.

## Non-goals
No feature expansion beyond the locked contract. A smaller correct system is preferred over a larger invented one.
