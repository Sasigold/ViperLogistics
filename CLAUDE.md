# CLAUDE.md — ViperLogistics project map

Read this first. It tells you where things live so you do not have to read the whole repo.
`README.md` (2.8k lines, Hebrew) is the design log: it holds the *why* behind business rules,
cited by migration number. Use the index in §9 to jump to a section instead of reading it all.

Verify before relying on line numbers or "latest migration" claims — they drift. Re-grep.

## 1. What this is

Multi-tenant, Hebrew RTL (+ dark mode) web app for an event-equipment / staffing company:
events → setup/teardown tasks → crew assignment, contractors, customers, attendance & pay,
pricing, profitability, dashboards, notifications. Source comments and error messages are mostly Hebrew.

Stack: Vite 8 + React 19 + TypeScript, Tailwind v4, react-router 8, TanStack Query 5 (+Virtual),
zustand, FullCalendar 6, Recharts, ExcelJS, pdf-lib, Leaflet, PWA (custom `injectManifest` service worker).
Backend: Supabase — Postgres 17 with full RLS, Auth, Edge Functions (Deno), Realtime.

Commands: `npm run dev` · `lint` (oxlint) · `typecheck` (`tsc -b`) · `test:unit` (vitest, node env, pure logic only) ·
`test:db` (`supabase/tests/run.sh`, scratch Postgres in /var/tmp, needs root/sudo + PG16+) · `test` (both) · `build`.
CI (`.github/workflows/ci.yml`): lint, typecheck, unit, build; plus a `database` job running run.sh.

Repo layout: `src/` frontend · `supabase/migrations` (0001..0203) · `supabase/functions` · `supabase/tests` · `docs/` · `public/`.
There is no `supabase/config.toml`; `verify_jwt` per function and all secrets/GUCs live in the Supabase dashboard/CLI.
Production migrations are applied out-of-band (Supabase MCP `apply_migration`/`list_migrations` or dashboard) — run `list_migrations` first.

## 2. Golden rules (do not break)

1. **The server is the authority.** UI `has()` only hides things. Enforcement = RLS + triggers + `app.require()` in RPCs.
   Never compute money/profit in the browser; exports are pure builders over server numbers.
2. **One shell for all user kinds.** Customers/contractors use the same routes/components; differences come from
   permission keys or RLS, never from `user_kind` checks. Flags (`performed_by_enabled`, `commission_pct`,
   `warehouse_schedule_enabled`) decide behaviour — never customer names in code.
3. **Every route declares `handle: { perm | anyPerm | open, audience? }`** or `RouteGate` denies it.
4. **Every new RPC** ends with `revoke execute ... from anon, public; grant execute ... to authenticated`.
   A `security invoker` function needs EXECUTE on every `app.*` helper it calls, else 42501 hits everyone incl. admins
   (recurred: 0087→0164, 0193→0194). 42501 is reserved for `app.require`/RLS — business rules must not use it.
5. **RLS policies wrap helper calls in `(select app.fn())`** (InitPlan). Use definer helpers to avoid recursion
   (`app.assignment_on_my_contractor`, `app.event_visible` must stay invoker). Definer functions bypass RLS, so write the gate inside them.
6. **Money sums use only** `app.live_events`, `app.live_tasks`, `app.task_revenue` (cancelled events/deleted tasks excluded).
   Never add per-query cancelled predicates; do not `where` a left-join branch. Don't fold add-ons into `task_pricing.price`.
   Manual price = `is_manual` flag. Never floor contractor price at 0 (penalty > price is a debt). Contractor-covered hours count once (0186).
   Arco-performed tasks price 0 even over manual price. `tasks.contractor_id` is a read-only mirror — write via
   `contractor_delegate`/`contractor_undelegate`; truth is `task_contractor_terms`.
7. **Customer never sees our revenue or writes price**; sees spend (`finance.customer_spend`). Contractor doesn't see add-ons or choose start point.
   Cross-party names go only through identity views (`app.customer_identities`, worker identity views). Never widen `customers_select`.
8. **Permission traps:** `app.has` ignores `applies_to`; `register_permission` does not update `default_allowed` on conflict;
   `implied_by` can silently open access (write an explicit deny row); `users.set_admin` is not implied by anything.
   Keep hand-mirrored catalogs in sync: `src/lib/permissionKeys.ts` (`PERM`), `src/features/dashboard/sections.ts`
   (an unknown key is silently skipped).
9. **Never put secrets in `app_settings`** (readable by all authenticated). Use edge secrets or `alter database postgres set app.*`.
10. **Soft delete via definer RPC** (`soft_delete`, `remove_*`), not direct `UPDATE deleted_at`. `hard_delete` is admin-only, requires prior soft delete.
    Use separate write policies, not `for all`.
11. **Notifications**: all emissions through `app.notify()`; register types with `app.register_notification_type` (a test fails otherwise). Email/push off by default.
12. **Auth**: `signOut` scope stays `'local'`; don't reload permissions on `TOKEN_REFRESHED`; `auth.users` deleted only by `admin-users`.
13. **Edge deploy flags**: `viperflow-webhook`, `arco-intake`, `arco-dispatch`, `wall-feed` need `--no-verify-jwt`; `viperflow-sync`/`viperflow-spec`/`admin-users` keep JWT on.
    **Do NOT deploy `notify-dispatch` from the repo blindly** — prod differs (uses `npm:web-push`); deploying repo version replaces it (ROADMAP tech-debt).
14. **ViperFlow update never writes dates/hours** (even with `force`); only truck count, worker count, prices. `_shared/viperflow.ts` must stay free of Deno imports (vitest tests it).
15. Edit the **latest** definition of any SQL function: `grep -l "function app.<name>" supabase/migrations/*.sql | tail -1`, copy the whole body into a NEW migration (never edit old migrations).

## 3. Making changes — recipes

**New migration**: `supabase/migrations/0203_<slug>.sql` (next number; note duplicate 0113/0175 exist). Header: `-- 0203: title`, Hebrew narrative
(what/why, cite earlier migrations), then `-- ===== N. section =====` blocks, `create or replace function ... security definer set search_path = public`,
revoke/grant. Views respecting RLS: `security_invoker`. Redefine whole functions/views (`work_board_view` has been redefined 21× — copy latest, 0201).
Then add/extend a test suite and make sure `test:db` passes.

**New permission**: migration calling `app.register_permission(key, module, label, desc, category, default_allowed, dangerous, applies_to[], implied_by, sort)`
(+ `app.register_module`, `app.set_role_permissions` / `kind_permission_defaults`; example: 0196 §3) → add to `src/lib/permissionKeys.ts` → gate route/nav/UI.
New field permission: `register_field` + `app.enforce_field_perms` trigger + `rebuild_secure_view`.

**New page + menu item**: (1) permission key as above; (2) `src/features/<x>/<X>Page.tsx` default export;
(3) `router.tsx`: `const XPage = lazyPage(() => import(...))`, route under `AppLayout` with `handle:{perm}`, wrapped `page(<XPage/>)`;
(4) `nav.ts`: `NavItem` in right section (+ icon from `components/ui/icons.ts`, + `ROUTE_LABELS`); (5) `PageHeader`, `usePageTitle` for detail pages; (6) `nav.test.ts` if non-trivial.

**New shared query/mutation**: feature-local → `features/<x>/<x>Queries.ts`; shared reference data → `src/lib/queries.ts`. Query keys `[entity, variant, ...args]`;
invalidate by prefix. For live-update lists use a key starting with `workboard|dashboard|attendance|portal|events|calendar|tasks` (see `features/sync/useRealtimeSync.ts`).

**New dashboard widget**: component in `dashboard/widgets/*` → register in `dashboard/registry.tsx` → section key in `dashboard/sections.ts` + SQL section in `dashboard_sections` (latest 0174; redefined in full).
KPI card: `widgets/kpi.tsx` factory. Custom user widgets: `dashboard/builder/` (`widgetSpec.ts`).

**New SQL test**: `supabase/tests/59_<slug>.sql`, copy header from `56_*`/`58_*`; own UUID prefixes; dates far out (`current_date + N`, N > 870 — but 58 owns `current_date + 900..906` and 57 owns a July week four calendar years out, so stay clear of both); assert as `set role authenticated` + `set_config('request.jwt.claim.sub',...)`;
helpers `t_eq/t_rows/t_expect_fail/t_expect_ok`; reset role; **append a block to `run.sh`** (run order is hard-coded).

**Settings tab**: `features/settings/SettingsPage.tsx` `TABS` array (each has `perm`). **Notification type**: emitters 0110+, gating `app.notification_enabled` (0086), insert `app.notify` (0054), sender `functions/notify-dispatch`.

After a change: `npm run lint && npm run typecheck && npm run test:unit` (and `test:db` if SQL touched, when Postgres is available). If a migration is added, note it in README/docs (README "מבנה" lists the range — bump it).

## 4. Frontend map (`src/`)

**Boot** `main.tsx`: QueryClient (staleTime 30s, retry 1), global `reportError` for query/mutation errors (`lib/reportError.ts`, `setErrorSink` for Sentry), `useAuth.boot()` → `dismissSplash` (`app/splash.ts`; the animated logo splash is inline SVG+CSS in `index.html`, skipped in iframes/`/embed/`), tree `ErrorBoundary > QueryClientProvider > ToastProvider > RouterProvider`.
**`sw.ts`**: Workbox precache + NavigationRoute (denylist `/functions/ /rest/ /auth/ /storage/ /employee-guide/`), NetworkFirst for Supabase GET, push handlers. No background sync by design (clock uses server `now()`). `vite.config.ts` explains injectManifest traps.

**`app/`**: `router.tsx` (routes, lazyPage, `handle` gates; `/client/*` legacy redirects keep until ≥2027) · `nav.ts` (`NAV_SECTIONS`, audience predicates `forEmployees/forContractors/forSelfPerformingCustomers/forWarehouseSchedule`, `hiddenBy`, `ROUTE_LABELS`) · `AppLayout.tsx` (sidebar, bottom nav, Ctrl+K palette, mounts push + realtime sync) · `HomeRoute.tsx` (`/` → Dashboard / CustomerDashboard / first reachable nav) · `breadcrumbs.tsx`.

**Auth/perm state**: `state/auth.ts` (`useAuth`: session, `me` from RPC `get_my_permissions`, `has/hasAny/can`, `canViewField/canEditField`, `formFieldState`, `boardFieldState`, `performsTask`, `canCreateEvent`) · `features/auth/guards.tsx` (`RequireAuth`, `RouteGate`, `RequirePermission`, `Can`, `useCan`) · `lib/effectivePermission.ts` (pure mirror of `app.has`) · `lib/permissions.ts` (registry/roles/grants hooks) · `features/permissions/*` (matrix, roles, scopes, field perms UI).

**`lib/`**: `supabase.ts` (client, `invokeFunction`) · `authFetch.ts` (401 refresh-retry) · `queries.ts` (871 lines shared hooks) · `errors.ts` (`errorMessage`/`actionError` → Hebrew; never show raw `e.message`) · `dates.ts` (`fmt*`, `fmtMoney`, warehouse-start helpers mirroring `app.warehouse_start_at`; note `fmtMoney` also exists in `components/ui/format.ts`) · `hebrewHolidays.ts` · `address.ts` · `bidiText.ts` (PDF RTL) · `colors.ts` · `deepLink.ts` · `push.ts` · `lazyPage.ts` (always use, reloads once on chunk error) · hooks `useMediaQuery/useOnline/useDragScroll/useSwipeNav` · `zoomGuard.ts`.
Timestamps are stamped server-side; avoid client-side "now" for business logic. Timezone `Asia/Jerusalem` appears only in LoadHeatmap and sectionWidgets.

**UI kit** `components/ui` (import from index): primitives (Button, Badge, Avatar…), inputs (Field, Input, Select, MultiSelect, Autocomplete…), overlay (Modal, Drawer, Popover, `useToast`, `useConfirm`, `usePrompt`), Card (`PageHeader`, `StatCard`, `FilterBar`), `DataTable`, Tabs, feedback (`EmptyState`, `ErrorState`, Skeleton), `format.ts`, `icons.ts`.
**Theme** `index.css`: `--vl-*` tokens, `[data-theme=dark]`, Tailwind `@theme inline`, type-scale utilities. RTL: use logical utilities (`ms-/me-/start-/end-`).
**Types**: all DB/RPC row shapes in `types/domain.ts` (2185 lines) — add new ones there.

## 5. Feature modules (`src/features/<x>`) — where to go

| Module | Routes / entry | Change X → go to |
|---|---|---|
| attendance | `/shifts` `/attendance` `/my/schedule` `/my/attendance` | data hooks `attendanceQueries.ts`; board window/filters `shiftBoard.ts`; Excel `exportAttendance.ts`; overtime UI `OvertimeSettingsTab`; clock UI `TimeClockPage`, geo `useGeolocation/LocationPicker`; pay math is SQL (`app.attendance_calc`) |
| calendar | `/calendar` | everything in `CalendarPage.tsx` (1134 lines; FullCalendar, `update_event`, `saved_filters`) |
| contractors | `/contractors(/:id)`, `/my/staff` | terms/payments UI `ContractorDetailPage`; own staff `MyStaffPage`; worker-assign hooks in `lib/queries.ts` |
| customers | `/customers(/:id)`, `/my/crew` | pricing editor `PricingTab` + `pricingSchema.ts` (mirrors `app.price_calc`); income split `IncomeSplitTab`; board/form fields in `CustomerDetailPage`; crew visibility → `tasks/crewVisibility.ts` |
| dashboard | `/` | see §3 widget recipe; `layout.ts` sizes, `drill.ts` click-through, `dashboardRange.ts`, `exportDashboard.ts`, `useDashboardData/Layout` |
| events | `/events(/:id)` | `EventDetailPage` (1412), `EventFormModal` (1194) + `eventForm.ts` (pure); quote `quote.ts`/`quotePdf.ts`/`quoteQueries.ts`; specs `specs.ts` (mirrors 0077 MIME/size); furniture `furniture*.ts`; signature `signatureQueries.ts`; Excel import/export → `importExport/eventsWorkbook.ts` |
| pricing | (no route) | zones `travelZones.ts`; "price without travel" `travelGap.ts`; add-ons `addonQueries.ts`; formula is SQL |
| portal | `/portal` | `PortalPage`, totals `portalTasks.ts`, export `exportPortalTasks.ts` |
| reports | `/reports` `/reports/profitability` `/reports/task-pnl` `/reports/load` | builder `reportState.ts`/`reportTemplates.ts`/`useReportRuns.ts`; heatmap `LoadHeatmapPage` + `loadScale.ts`; P&L `taskPnl.ts`, `profitability.ts` (server computes numbers) |
| tasks | (drawer, no route) | `TaskDrawer.tsx` (1209), `taskPanels.tsx` (1554: pricing/crew/terms/assignments); crew = one person once across 3 pools `crew.ts`; per-customer visibility `crewVisibility.ts` |
| users | `/users` | `UsersPage`, `userType.ts` (admin = staff + `is_admin`); account creation via `admin-users` function |
| vehicles | `/vehicles(/:id)` | `vehicleQueries.ts`, labels/upload rules `vehicles.ts`, tabs Documents/Drivers/FuelCard |
| warehouse | `/warehouse` | `WarehouseSchedulePage`, `warehouseSchedule.ts` (RPCs `warehouse_schedule`, `warehouse_task_save`) |
| workboard | `/board` | `WorkBoardPage.tsx` (2156, biggest); grouping/colors `grouping.ts`; status transitions `statusOptions.ts`; columns `boardFields.tsx`; data = view `work_board_view` queried directly |
| notifications | bell, `/my/notifications`, settings tab | `notificationQueries.ts`, `pushQueries.ts` |
| search | Ctrl+K | `CommandPalette.tsx` → RPC `global_search` |
| settings | `/settings` | `SettingsPage.tsx` `TABS`, `companyQueries.ts` (bucket `company-assets`) |
| integrations | `/integrations` | ViperFlow/Arco status, replay, sync |
| finance | `/receipts` | `ReceiptsPage.tsx` |
| embed | `/embed/event` | iframe of `EventFormModal`, postMessage `viper:event-saved/closed` |
| sync | (hook) | `useRealtimeSync.ts` — broadcast → debounced `invalidateQueries`, never patches cache |

Pattern: pure logic in `*.ts` with sibling `*.test.ts` (vitest is node-only, no component tests); React in `*.tsx`.

## 6. Backend map (`supabase/`)

**Migrations** (~100 tables). Ranges: 0001-0009 foundation (identity, lookups, events/tasks, permissions v1/audit, RLS, RPCs, realtime) · 0010-0015 permission system v2 ·
0016-0018 activity log + pricing · attendance ≈ 0019-0025/0034/0060/0065/0152/0166 · 0030-0031/0046-0054/0086/0110/0167 notifications ·
0038-0045/0058-0059/0174 dashboard/reports · 0068-0070/0074/0087/0164/0186 income/receipts/P&L · contractors 0072/0075/0091-0108/0155 ·
0077-0078/0102/0107 specs & signature · 0089-0090 vehicles · 0101 scoped realtime · 0109-0147 customer board, Arco-performed, recycle bin, customer crew ·
0159-0169 login/delete/hour-fix/clock · 0170-0175/0181 quote, load heatmap · 0176-0177/0187-0195 ViperFlow · 0182-0186/0199 Arco · 0178-0180/0196-0201 customer worker accounts, warehouse schedule, worker pay view, cancelled releases crew, crew-is-people · 0202-0203 wall feed (ViperGroup; 0203 = `crew_names`).

Core tables: identity (`profiles`, `staff_roles`, `profile_roles`, `customers`, `contractors`, `contractor_workers`, `customer_workers`) · work (`events`, `tasks`, `task_assignments` (one row per role),
`task_contractor_terms`, `task_contractor_workers`, `task_customer_workers`, `task_pricing`, `task_price_addons`, `event_activity/specs/signatures/quotes/income/suppliers/contacts`, `warehouse_tasks`, `warehouses`, `trucks`, `vehicles*`) ·
config (`task_types`, `statuses`, `execution_methods`, `form_fields`, `customer_form_fields`, `board_fields`, `pricing_zones`, `customer_pricing_rules`, `app_settings`) ·
money (`income_categories`, `customer_income_splits`, `receipts`, `worker_pay_settings`, `attendance_entries`, `attendance_entry_bonus`) · permissions (`permission_registry`, `permission_roles`, `role_permissions`, `kind_permission_defaults`, `user_permission_grants`, `permission_scopes`, `field_registry`, `field_permissions`) ·
notifications (`notifications`, `notification_types/policies/deliveries`, `push_subscriptions`) · dashboards (`dashboard_layouts`, `dashboard_widgets`, `report_sources/fields/measures`, `saved_filters`) · `audit_log` · integrations (`viperflow_*`, `arco_*`, `legacy_firestore_docs`).

**Permission resolution `app.has(key)`** (0010, never redefined; first match wins): admin → `user_permission_grants` → `role_permissions` → `kind_permission_defaults` → `default_allowed` → `implied_by` chain (≤8) → deny.
Row scoping `app.scope_rows/ids/own/date_*` (0085); column write guard `app.enforce_field_perms()` trigger; column read via `*_secure` views/masking; actions via `app.require`. Client bootstrap RPC `get_my_permissions` (latest 0196 — append there for new client-visible flags).
User kinds: `staff | customer_user | contractor_user`; admin = staff + `is_admin`. Roles attach only if kind matches; "manager beats worker" for contractors (0103/0104).

**Latest definition of critical functions** (verify with grep): `app.my_role_ids` 0104 · `app.scope_rows` 0085 · `app.event_visible` 0082 · `app.notify` 0054 · `app.notification_enabled` 0086 · emitters 0110 · `app.planned_shifts` 0034 / `_many` 0178 ·
`app.attendance_calc` 0152 · `attendance_pay_rows`/`clock_needs_location` 0166 · `app.price_calc` 0060 · `recompute_contractor_price` 0155 · `task_pnl_rows`/`payroll_task_amounts` 0186 · `margin_summary`/`payroll_summary` (thin gated wrappers) + `_core` (bodies, revoked from all) 0202 ·
`dashboard_sections` 0174 · `app.report_run` 0058 · `app.load_capacity` 0175 / `load_slots` 0181 · `log_event_activity` 0170 · `release_event_crew` 0200 · `enforce_task_publish` 0179 ·
`viperflow_apply_order` 0194 · `arco_outbound_enqueue` 0184 · `app.audit` 0196 · `work_board_view` 0201 · `shift_task_breakdown` 0201 · `app.wall_snapshot_at` 0203 · `app.wall_task_crew` 0203 · `app.wall_task_rows`/`app.wall_feed_check`/`public.wall_snapshot` 0202.

**Edge functions** (`supabase/functions/`, Deno; shared pure code in `_shared/viperflow.ts`, `_shared/arco.ts`, unit-tested):
`admin-users` (create/set password/active/delete/purge login; JWT on) · `geocode-proxy` (Google Places → Photon/Nominatim; auth in code, accepts service key) ·
`notify-dispatch` (drains deliveries: Resend email + Web Push; `x-dispatch-secret`) · `fleet-expiry-sweep` (`x-sweep-secret`) ·
`viperflow-webhook` (HMAC, no-verify-jwt) · `viperflow-sync` (user JWT w/ `integrations.manage` or `x-sync-secret`) · `viperflow-spec` (live furniture list, redacts money) ·
`arco-intake` (`/event`, `/spec`; `x-arco-secret`; business failures return 200 + failed row) · `arco-dispatch` (drains `arco_outbound`) ·
`wall-feed` (read-only feed for the ViperGroup wall; `x-wall-secret` checked in SQL against Vault; no-verify-jwt).
Secrets: `SUPABASE_*`, `GOOGLE_MAPS_API_KEY`, `RESEND_API_KEY`, `VAPID_KEYS/VAPID_SUBJECT`, `FLEET_SWEEP_SECRET`, `VIPERFLOW_WEBHOOK_SECRET(_PREVIOUS)`, `VIPERFLOW_API_KEY` (needs `orders:read` + `products:read`), `VIPERFLOW_SYNC_SECRET`, `ARCO_INTAKE_SECRET`, `ARCO_DISPATCH_SECRET`, `ARCO_EVENT_WEBHOOK_URL`, `ARCO_WEBHOOK_TOKEN`; DB GUCs `app.notify_dispatch_url/secret`, `app.arco_dispatch_url/secret`.

**Tests** `supabase/tests`: `run.sh` builds scratch cluster, applies ALL migrations (`ON_ERROR_STOP`), seeds, runs suites 02..58 in hard-coded order. Suites map ≈ feature names (02 escalation/RLS, 03 pricing, 04 attendance, 05 dashboard, 07 notifications, 08 import, 13 task P&L, 29 performed-by-arko, 40 delete user, 44 clock in shift, 48 heatmap, 49 ViperFlow, 51 Arco, 52 contractor hour once, 56 crew, 57 wall feed, 58 wall crew names). Regression tests for permissions must run as a normal role (superuser bypasses grants). `01_seed.sql` re-grants EXECUTE on every `public`/`app` function to `authenticated`, undoing migration revokes — assert what a migration revoked against `t_pre_seed.function_acl` (snapshot taken by `run.sh` before the seed; see 57). `00_bootstrap.sql` stubs `vault` (no grants to any API role).

## 7. Integrations & ops (see `docs/`)

- **ViperFlow** (`docs/VIPERFLOW.md`): order → event + setup/teardown + income. Birth sets everything; update writes only quantities/prices, notifies the rest (compared vs `viperflow_links.order_snapshot`). Line names are a configurable list in `/integrations`. Endpoint disabled after 10 failed deliveries → sync recovers. Pending: `products:read` on API key, price backfill (force pull).
- **Arco via Make** (`docs/ARCO.md`): `arco-intake` inbound, `pg_net` outbound to `app.arco_webhook_targets`; Arco = customer with `performed_by_enabled` (its tasks price 0, hidden from Viper). Replay: `arco_replay`, `arco_outbound_retry()`.
- **Wall feed** (0202, ViperGroup `docs/FEEDS.md` §1): `wall-feed` → `public.wall_snapshot(p_secret, p_days)` (service_role only) → `app.wall_snapshot_at(now(), days)`. Vault holds only the **sha256 hex** of each secret, never the secret and never `app_settings`. **Several secrets work at once**: `app.wall_feed_check` reads every Vault row whose name `starts_with` `wall_feed_secret` (not LIKE — `_` is a wildcard) and accepts a secret whose sha256 equals ANY of them; `wall_feed_secret` = the Vercel deployment, `wall_feed_secret_minipc` = the Mini PC, other names (`other_secret`, `old_wall_feed_secret`) never count. Create one with `select vault.create_secret(encode(sha256(convert_to('<secret>','UTF8')),'hex'),'wall_feed_secret_minipc','sha256 of the Mini PC wall secret');` (or name `wall_feed_secret` for Vercel), rotate one with `vault.update_secret((select id from vault.secrets where name='wall_feed_secret_minipc'), encode(sha256(convert_to('<new>','UTF8')),'hex'))` — the others keep working; revoke one by deleting its row. A row whose value is not 64 hex chars is ignored. Secret < 32 chars or wrong → 28P01 (401); no valid hash row at all → 55000 (503). Feed money comes from `app.margin_summary_core` (rule 6); no phones, no per-person pay. **0203** adds one additive field to every `tasks[]` item: `crew_names` — names (text array) of the task's crew as PEOPLE, the same definition as `assigned` (distinct profiles from `task_assignments` + contractor workers + customer workers, via the identity views — rule 7), team lead first (same pick as `team_lead_name`: staff, else contractor worker, else customer worker), then alphabetical (tiebreak by id), capped at 40, blank names skipped (so `cardinality(crew_names)` = `assigned` unless a crew member has a blank name or the crew exceeds 40), `[]` when empty; names only (no phone/id/pay/uuid). Built by `app.wall_task_crew(task_id)` (revoked from everyone, like the other `wall_*` helpers) called from `app.wall_snapshot_at`; `app.wall_task_rows` and the `wall-feed` edge function are unchanged (no redeploy).
- **Manual/one-time ops**: schedule `notify-dispatch` retry, daily `fleet-expiry-sweep`, daily ViperFlow sync, hourly `arco-dispatch`; enable email/push in `app_settings`; deploy `admin-users` (purge) and `geocode-proxy` (Arco pins); `ops.capacity` numbers; iOS push needs 16.4+ installed app.
- `docs/ROADMAP.md` = planning + tech-debt list (two profit definitions, hand-mirrored catalogs, `app.has` can't answer for another profile, receipts soft-delete, dead tables). `docs/EMPLOYEE_GUIDE.md` = end-user guide (static page `public/employee-guide`).

## 8. Domain glossary

עובד worker (hourly, clocks in; shift derived from assignments) · נהג driver (assignment role, truck) · ראש צוות team lead (one per task across internal/contractor/customer pools; per-event, not a key) ·
קבלן contractor (rates, delegations, penalties, portal; own staff; manager vs worker roles) · לקוח customer (tenant entity + `customer_user` logins; also "end client" for quotes) ·
מחסן warehouse (table, per-customer + role that sees only `/warehouse`) · ארקו Arco · וייפר Viper (us) · הקמה/פירוק setup/teardown (auto-created tasks) · אופן ביצוע execution method (valid = active ∩ task type ∩ customer) ·
משובץ = published (unpublished tasks invisible to assignees) · מפרט spec (versioned customer doc / furniture list) · מפת עומסים load heatmap (concurrency, not sum) · הצעת מחיר quote PDF (pdf-lib, WhatsApp share).
Pricing: `task_pricing.price` via `app.price_calc` (workers×hours + zone travel + add-ons; only `pricing_mode='auto'`); contractor price = base + add-ons + penalties; worker pay computed on read; shift bonus separate from hours.

## 9. README.md index (jump with `sed -n 'A,Bp'`)

1-38 stack + screens table · 40-104 Excel import · 105-174 event spec · 175-312 ViperFlow · 313-358 furniture list · 359-381 Arco · 382-503 quote (WhatsApp/PDF) · 504-570 vehicles · 571-613 event location/zones ·
614-668 duplicate removed, activity log · 669-912 schedule/board cell, panels, customer board fields · 913-1048 Arco-performed & customer crew · 1049-1102 one team lead · **1103-1465 attendance & shifts** · 1466-1536 task P&L ·
1537-1594 load heatmap · 1595-1640 what counts as money · 1641-1684 cancelled releases crew, crew=people · 1685-1753 list totals, customer spend/commission · 1754-1895 dashboard · 1896-1987 contractor finances, return-position memory ·
**1988-2436 security & permissions** · 2437-2513 login, user delete · 2514-2564 local run & tests · 2565-2585 layout · 2586-2794 notifications (ladder, push VAPID, ops) · 2795-2862 wall feed (Vault hashes, several secrets, deploy; 2841-2862 `crew_names`, 0203) · 2863-2885 ops notes (admin-users, Google Places).
