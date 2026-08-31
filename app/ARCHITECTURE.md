# Phase 2.0 — Architecture Decision Record

Branch: `phase2-app`. Phase 2.0–2.12 complete.
Scope: full application implementing all locked screens against the Phase 1 database contract.

## A. Audit summary

- Repository `BadmintonCourtManagement` contains a complete, hardened Phase 1:
  - `database/00..15` canonical SQL Server build (5 tables, 4 views, 2 functions,
    14 stored procedures, 6 triggers).
  - `tests/concurrency/` transaction/isolation/TOCTOU demos.
  - `evidence/final_*` + `PHASE1_TEST_REPORT.md` (09 = 47/47/0; CC/DL/PH/RC passed).
  - Locked UI export under `design/stitch_badminton_court_management_system/`
    (Login, Court search, Booking detail, History, Manager Dashboard,
    Booking management, Court management, Notifications) + `courtmaster_pro/DESIGN.md`
    visual tokens (BadmintonPro, teal `#00796F` family, Hanken Grotesk + JetBrains Mono,
    16–18px rounded cards, ambient shadows).
- Phase 1 confirmed on the local instance `.\SQLEXPRESS`; security model is
  **Option A**: `DENY EXECUTE ON sys.sp_set_session_context TO bcm_app` at master
  scope, `sp_Login` (WITH EXECUTE AS OWNER) is the ONLY way `bcm_app` can obtain a
  valid `SESSION_CONTEXT('UserId', 'Role')`.
- Local toolchain detected:
  - Node.js `v24.14.1`, npm `11.11.0` — present.
  - .NET SDK `10.0.302` — present.
  - Python — not installed.
  - git `2.53.0` — present.
- The course/contract locks **SQL Server + T-SQL**; it does **not** mandate a client
  framework. The stack choice below is therefore driven by repo reality + demo needs.

## B. Architecture chosen — TypeScript + Express + React, on Node.js

| Concern | Choice | Why |
|---|---|---|
| Frontend | **React 18 + TypeScript + Vite** | Component reuse across the 8 locked screens; single-language type discipline shared with the server; Vite dev server is trivial to run for the course demo. |
| Backend | **Express 4 (TypeScript, run via `tsx`)** | Minimal, auditable routing; each Stored Procedure maps to a thin route handler. |
| SQL Server driver | **`mssql` (tedious)** | Mature driver; native connection pooling; first-class `mssql.Connection` for a lifetime-held connection (needed for SESSION_CONTEXT). |
| Routing | Express routes (`/api/...`) + React Router shells | Matches locked UI; server stays the only DB caller. |
| Config/secrets | `.env` via `process.env`, committed template `.env.example` with placeholders | Connection string/secret stays out of git. |
| App-session model | `express-session` (HTTP cookie) -> server-side `SessionDb` map | One app session owns one dedicated SQL connection (see below). |
| Build/lint/run | `tsc --noEmit` typecheck, ESLint flat config, `tsx` dev, `vite build` | Fast iteration; no heavy toolchain. |

### Why not ASP.NET Core
- The contract locks only SQL Server/T-SQL. Node + React matches the exported HTML/JS
  UI naturally (same language, no .NET model round-trip), and Node is already installed
  while Python is not. .NET would be a valid alternative but adds ceremony with no
  contract benefit for this demo.

## C. SQL SESSION_CONTEXT strategy (critical)

### The constraint
`bcm_app` is DENYed `EXECUTE` on `sys.sp_set_session_context`. Therefore the
application can never create a valid session context itself; it can only obtain one
by executing `sp_Login`, and the context lives **on that one SQL connection until it
returns to the pool / is closed**. `sp_GetMyBookings`, `sp_GetNotifications`,
`sp_BookCourt`, etc. all read `SESSION_CONTEXT('UserId')` and throw (51054/51060/…)
when it is empty or when a caller-supplied `@UserId` does not match the context.

### Strategies compared
1. **Re-login on every request against a shared pool** — `sp_Login` would run on
   whichever pooled connection is checked out. Works but: (a) re-hash + `LastLogin`
   write per request, (b) loses the "one validated identity per connection" property,
   (c) risk of two interleaved requests on the same connection swapping contexts.
   Rejected.
2. **Direct `sp_set_session_context` re-establishment per request** — impossible:
   `bcm_app` is explicitly DENYed that procedure (the Phase 1 P0 fix). Rejected.
3. **Session-scoped dedicated SQL connection (chosen)** — each authenticated app
   session acquires **one** `mssql.Connection` and holds it for the session lifetime.
   `sp_Login` runs exactly once on it, establishing `SESSION_CONTEXT`; every
   subsequent protected procedure call for that user runs on the **same** connection,
   so the context is always present and never mixed with another user. On logout /
   session expiry the connection is closed (context disappears). A periodic sweeper
   enforces the same absolute `sessionTtlMs` as the non-rolling cookie plus a shorter
   idle timeout, including when the browser disappears without calling logout.
   Guest/public calls
   (`sp_GetAvailableCourts`, health) use the ordinary shared pool — no context needed.

### Implementation (bootstrap plumbing, no auth yet)
- `src/server/db/sessionDb.ts` — `createSession` + `withExistingConnection`:
  - holds a `Map<string, SessionConnection>` (connection + serialized work chain);
  - creates the dedicated single-connection pool only after a successful login flow;
  - **serializes** work per session so two requests never interleave SESSION_CONTEXT
    on the same connection;
  - records `createdAt`/`lastUsedAt` and evicts entries at absolute or idle expiry;
  - exposes idempotent `startReaper()` / `stopReaper()` for the server lifecycle;
  - `closeSession(sessionId)` closes the connection and evicts the entry;
  - `activeCount()` for health/diagnostics.
- `src/server/db/pool.ts` — shared `mssql.ConnectionPool` for public/guest SPs.
- Authentication runs `sp_Login` on that dedicated connection before the session is usable.

## D. How Stored Procedures will be called
- Task **only** through the 14 contract procedures / 4 views (no direct DML from app).
- Server constructs `sql.Request` on the session connection, binds named params
  matching the SP signature, `execute('dbo.sp_...')`, returns rowsets as typed DTOs.
- A thin `spError.ts` maps known SQL error numbers (including IMP-15 50120..50126 and 1205 deadlock)
  to stable Vietnamese messages for the UI while logging the technical detail.

## E. Why the design does not trust browser UserId/Role
- Authorization truth is `SESSION_CONTEXT` + SP-side checks (role, ownership, state).
- The backend never accepts `UserId`/`Role` from the browser as authority; it only uses
  them after `sp_Login`-established session context on the same connection.
- UI role-based routing/shell is presentational only; a user cannot act beyond their
  `SESSION_CONTEXT` role because the DB re-validates everything.

## F. Non-goals (explicit)
- No payment/membership/ratings/CRM/maintenance/settings/registration modules.
- No generic ADMIN app role.
- `database/`, `tests/`, `evidence/` are untouched. No new DB objects invented.

## G. Application layout
```
app/
  ARCHITECTURE.md
  package.json
  tsconfig.server.json   tsconfig.client.json
  vite.config.ts
  index.html
  .env.example
  .gitignore
  src/
    shared/   contract.ts + types.ts + spError.ts
    server/   index.ts, app.ts, config.ts, time.ts
               db/ connection.ts, index.ts, pool.ts, sessionDb.ts
               middleware/ errorHandler.ts, session.ts
               routes/ auth.ts, bookings.ts, courts.ts, health.ts,
                        manager.ts, managerCourts.ts, managerDashboard.ts, notifications.ts
               dev/ sessionContextProbe.ts
    frontend/ main.tsx, App.tsx, vite-env.d.ts
               api/ client.ts
               auth/ AuthContext.tsx, guards.tsx
               components/ BrandLogo.tsx, BpIcon.tsx, Button.tsx, Card.tsx,
                           CourtCard.tsx, EmptyState.tsx, IconButton.tsx, Input.tsx,
                           LoadingSkeleton.tsx, NotificationList.tsx, NotificationsView.tsx,
                           PageHeader.tsx, RoutePlaceholder.tsx, StatusBadge.tsx
               pages/ LoginPage.tsx, CourtsPage.tsx, BookingDetailPage.tsx,
                       MyBookingsPage.tsx, NotificationsPage.tsx
                       manager/ ManagerBookingsPage.tsx, ManagerCourtsPage.tsx,
                                ManagerDashboardPage.tsx, ManagerNotificationsPage.tsx
               shells/ ContentShell.tsx, CustomerShell.tsx, GuestShell.tsx, ManagerShell.tsx
               styles/ tokens.css, base.css, components.css, shells.css, ...
```

Phase 2.0 was the bootstrap skeleton. Phases 2.1–2.12 built the full application on this foundation.
