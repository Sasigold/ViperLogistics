# CLAUDE.md

Guidance for AI assistants working in this repository.

`README.md` is the authority on **what the system does** — the attendance engine, the
permission model, pricing, notifications, task P&L. It is thorough; read the relevant
section before changing behaviour in that area. This file covers what the README does
not: commands, layout, and the conventions that fail **silently** when broken.

---

## Commands

```bash
cp .env.example .env.local   # then fill in VITE_SUPABASE_ANON_KEY
npm install
npm run dev

npm run lint        # oxlint
npm run typecheck   # tsc -b  (three referenced projects)
npm run build       # tsc -b && vite build
npm run test:unit   # vitest
npm run test:db     # ./supabase/tests/run.sh
npm test            # both suites
```

`test:db` needs a local PostgreSQL (16+; CI uses 17, matching production). It creates a
throwaway cluster under `/var/tmp/vlpg`, applies every migration in order, then runs the
SQL suites. **It never touches a Supabase project.**

CI (`.github/workflows/ci.yml`) runs lint → typecheck → test:unit → build in one job and
the whole SQL suite in another, on every PR. Both must pass.

---

## Stack and layout

Vite · React 19 · TypeScript 6 · Tailwind v4 · TanStack Query · Zustand · React Router 8,
against Supabase (Postgres 17, full RLS, Auth, Edge Functions, Realtime). There is **no
custom backend** — the browser talks to PostgREST and RPCs directly.

```
src/app/                 shell: AppLayout, router, nav, breadcrumbs, HomeRoute
src/features/<domain>/   one directory per feature; pages, components, hooks, pure logic
src/components/ui/       the UI kit — single export point at index.ts
src/lib/                 supabase client, shared queries, permissions, dates, errors
src/types/domain.ts      all shared domain types (~1100 lines)
src/state/auth.ts        the zustand auth store: session, me, has(), theme
src/sw.ts                hand-written service worker (push + precache)
supabase/migrations/     0001..0071 — schema, RLS, RPCs, permissions, engines
supabase/functions/      admin-users, geocode-proxy, notify-dispatch (Deno)
supabase/tests/          run.sh + suites 00..14
```

Feature modules keep pure logic in plain `.ts` files next to the components
(`shiftBoard.ts`, `profitability.ts`, `travelZones.ts`) — that separation is what makes
the code testable under the node-only vitest setup. Data hooks live either in
`src/lib/queries.ts` (cross-cutting lookups) or a feature-local `*Queries.ts`.

**The database is the authority.** `has()` in the client hides controls; it protects
nothing. Enforcement is RLS policies, the `app.enforce_field_perms()` column trigger, and
`app.require(key)` inside RPCs. Never treat a client-side check as a security boundary,
and never add one as a substitute for the server-side rule.

---

## Conventions that fail silently

These are the ones worth memorising — each has no symptom at the point of the mistake.

### Every route declares its permission

```tsx
{ path: '/billing', handle: { perm: PERM.BILLING_VIEW }, element: page(<BillingPage />) }
```

`RouteGate` (`src/features/auth/guards.tsx`) **refuses** a route whose `handle` declares
nothing — that is deliberate, so "who may open this?" cannot be deferred. Use `anyPerm:
[...]` when two audiences reach one screen through different keys (see `/shifts`), and
`open: true` only for routes that decide for themselves (`/`, `/reset-password`).

Nobody is routed by `user_kind`. Clients and contractors use the same shell, routes and
components as staff; every difference comes from a registry key or from RLS.

### Permission keys live in the database first

A new key is a migration (`app.register_permission`), then mirrored into `PERM` in
`src/lib/permissionKeys.ts`, which is regenerated rather than hand-edited:

```sql
select key from permission_registry order by module, sort_order, key;
```

Nothing breaks if the mirror lags — `has()` takes any string — but call sites lose
autocompletion and typo protection.

### Dashboard section keys must be listed twice

A widget names section keys that `dashboard_sections` computes. An **unknown key is
skipped, not raised** (that is what lets an old server serve a new client), so a typo
means the widget never appears, for anyone, with nothing in any log. Add the key to
`SECTIONS` in `src/features/dashboard/sections.ts`; `registry.test.ts` asserts every
widget's sections against that list and turns the silent failure into a failing test.

### Import UI from the kit's entry point

```ts
import { Button, Card, DataTable } from '../../components/ui'
import { Truck, ICON, STROKE } from '../../components/ui/icons'
```

Never import `lucide-react` directly — `icons.ts` is the single icon vocabulary, and a
second icon set cannot creep in through a file that does not exist.

### Errors go through `errorMessage()`

`(e as Error).message` from Supabase is raw Postgres: English constraint names and table
names inside a Hebrew UI. Use `errorMessage(e)` or `actionError('שמירת האירוע', e)` from
`src/lib/errors.ts`. Mapping is by error **code**, not text, because text changes between
Postgres versions. A Hebrew message raised deliberately inside an RPC passes through
untouched — that is the server explaining *why* it refused.

### Lazy-load screens with `lazyPage`

`src/lib/lazyPage.ts`, not bare `React.lazy`. After a deploy the previous build's chunks
404 while an open tab is still running that build; `lazyPage` recovers with a single
guarded reload instead of an error screen.

### Sensitive columns need registry wiring

Adding a column that not everyone may read or edit takes four things, not one:

```sql
select app.register_field('invoice', 'total', 'סכום', 'billing', 'invoices', 'total',
       p_sensitive => true, p_edit_permission_key => 'billing.issue_invoice');
create trigger invoices_field_perms before update on invoices
  for each row execute function app.enforce_field_perms();
select app.rebuild_secure_view('invoices');
```

The trigger sits on the **table**, not the RPC, so it covers every write path. Remember
that any table reachable through PostgREST is readable by whoever RLS allows — a money
column on a widely-readable table is exposed regardless of what the UI draws. That is why
`hourly_rate` lives in `worker_pay_settings` and shift bonuses in a separate table.

---

## Migrations

Files are `NNNN_name.sql`, applied in glob order. **Never edit a migration that has been
applied** — add a new one.

> The number `0071` is currently used by two files (`0071_contractor_in_the_shell.sql`
> and `0071_travel_zones_for_shifts.sql`). The next migration is **0072**.

House style, which you should match:

- A header comment naming the problem and why it exists, not a summary of the SQL.
- Numbered `-- ===== 1. ... =====` sections.
- An explicit list of "decisions worth justifying" — especially the omissions, since an
  absent thing has no code to explain itself. `0070` and `0071` are good models.

**Derived values are computed on read, never stored.** The shift comes from
`app.planned_shifts`, pay from `app.attendance_calc`, price from `task_pricing` — so they
cannot go stale against the tasks they derive from, and the board, the time clock and the
report cannot disagree. When you need an existing calculation in a new shape, **extract
and wrap it** rather than reimplementing: `0070` §1 pulled `app.payroll_task_amounts` out
of `app.payroll_task_alloc` and left the old caller a thin wrapper with identical output.
A second implementation of the same calculation is the failure mode this codebase most
consistently designs against.

---

## Tests

### SQL suites (`supabase/tests/`)

Suites `00`–`14` are **order-dependent**, and `run.sh` documents per suite why it sits
where it does — one seeds rows others count, another moves permissions on `f1`, another
disguises `f3`. Read those comments before inserting a suite. A new suite should seed its
own fixtures, avoid depending on earlier ones, and run last if it leaves rows behind.

Assertion helpers are defined in `01_seed.sql`:

| Helper | Use |
|---|---|
| `t_expect_ok(label, sql)` | the statement should succeed |
| `t_expect_fail(label, sql)` | the statement should be blocked |
| `t_eq(label, actual, expected)` | value comparison |
| `t_rows(label, sql, n)` | affected-row count — RLS makes a forbidden UPDATE affect **zero rows rather than raise**, and this is what distinguishes "silently did nothing" from "was blocked" |

Switch identity with `select set_config('request.jwt.claim.sub', '<uuid>', false);` and
back to anon with `''`. Seeding runs with no JWT on purpose, which skips the publication
and field-permission triggers so fixtures can be inserted in states a user could not
create. `run.sh` counts `pass`/`FAIL` lines and exits non-zero on any failure.

### Unit tests (vitest)

`environment: 'node'` with **no jsdom**, deliberately: what is tested is pure logic —
permission resolution, shift derivation, date handling, error mapping, exports — not
rendering. Tests are colocated (`foo.ts` → `foo.test.ts`) and only `src/**/*.test.ts` is
collected.

Two shims exist because modules touch browser globals at import time: `vitest.setup.ts`
supplies an in-memory `localStorage` (the auth store reads the saved theme while zustand
builds it), and `vitest.config.ts` injects placeholder Supabase env vars because
`lib/supabase.ts` constructs its client on import. Neither is a hook to hang new
behaviour on.

---

## Language and style

- **The product is Hebrew and RTL.** All user-facing text — labels, toasts, empty states,
  `aria-label`, error strings — is Hebrew. Match the surrounding tone.
- **Commit messages are Hebrew**, describing the user-visible change rather than the
  files touched: `רווחיות פר-משימה: כמה חויב מול כמה עלה בפועל`.
- **Comments explain why, and usually name the failure they prevent.** Both Hebrew and
  English appear and both are fine. This is the codebase's strongest convention and the
  easiest to under-serve: when a decision looks arbitrary or looks like an omission,
  write down what the alternative would have broken.
- TypeScript is strict, with `noUnusedLocals`, `noUnusedParameters` and
  `verbatimModuleSyntax` — use `import type` for type-only imports.
- Four tsconfigs. `src/sw.ts` is excluded from `tsconfig.app.json` and compiled by
  `tsconfig.worker.json` instead, because the `DOM` and `WebWorker` libs redeclare `self`,
  `caches` and `fetch` and cannot share a program.
- oxlint enforces `react/rules-of-hooks` as an error.

---

## Gotchas

- **`app_settings` is readable by every authenticated user** through PostgREST. Never put
  a secret there. The VAPID *public* key lives there; the private key is a function
  secret, and dispatch URL/secret are database settings.
- **Email and Web Push are off by default**, in two independent places for push (the
  settings key and an `opt_in` catalog default). An upgrade must not start sending mail
  by itself. See README → התראות.
- **`src/sw.ts` is hand-written** (`injectManifest`, not `generateSW`) because Workbox
  cannot generate a `push` handler. Keep it dumb — what to send and where it links is
  decided server-side in `notify-dispatch`, because workers reach devices slowly.
- **Geolocation needs a secure context.** Production and `localhost` qualify; a dev server
  reached over a LAN IP cannot request location, so the time clock's location rules cannot
  be exercised there.
- **Nominatim is rate-limited to one request/second** and the proxy self-throttles.
  Exceeding it blocks the whole application's IP. Heavy use should move to Google Places
  through the adapter in `src/lib/address.ts`.
- New user logins are created through the `admin-users` Edge Function (service role,
  server-side only), never from the browser.

---

## Where to look

| Question | File |
|---|---|
| How does the permission decision work? | README → אבטחה והרשאות; `app.has()` in migrations 0010–0013 |
| What keys exist? | `src/lib/permissionKeys.ts`, `permission_registry` |
| How is a shift derived? | README → נוכחות ומשמרות; `app.planned_shifts` |
| What is planned but not built? | `docs/ROADMAP.md` |
| How do I add a screen? | `src/app/router.tsx` + `src/app/nav.ts`, both keyed by `PERM` |
| How do I add a widget? | `src/features/dashboard/registry.tsx` + `sections.ts` |
