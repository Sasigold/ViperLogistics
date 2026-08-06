-- 0010: permissions core — a self-describing, key-based permission model
--
-- The 0004 model was (resource, action) with `action` a four-value enum. That
-- enum is the ceiling: "may reassign workers on a task but may not move it"
-- is not a CRUD verb, and adding one costs an ALTER TYPE on a shipped database.
--
-- This migration replaces it with a *registry* of dotted permission keys
-- ('tasks.assign.worker'). A key is a row, not an enum member, so a future
-- module registers its permissions with an INSERT — the resolver, the RLS
-- helpers and the admin UI all pick it up with no code change. Everything
-- resolves through one function, app.has(key), so there is exactly one place
-- where "is this allowed" is decided.
--
-- Layers, most specific first:
--   1. is_admin                     — unconditional yes
--   2. user_permission_grants       — per-person allow/deny
--   3. role_permissions             — named bundles the person belongs to
--   4. kind_permission_defaults     — per user_kind baseline
--   5. permission_registry.default_allowed
--   6. the key this one is `implied_by`, resolved the same way
--   7. deny
--
-- Step 6 is what keeps the model from breaking every time it gets finer.
-- 'tasks.reschedule' is implied_by 'tasks.edit', so someone who was granted
-- "edit tasks" before that key existed keeps being able to move a task — until
-- an admin says otherwise, at which point the narrower key takes over. Splitting
-- a coarse permission into finer ones is therefore a non-breaking change.
--
-- Unknown key ⇒ deny. New capabilities are closed until granted, which is the
-- safe direction for something added after this file was written.

-- Policy expressions are evaluated as the querying role, so `authenticated`
-- must be able to reach the helpers in `app`. Supabase grants this implicitly
-- for new schemas; stating it here means the model does not depend on that.
grant usage on schema app to authenticated, service_role;

-- ===== enums =====
create type permission_scope_type as enum (
  'all',                -- explicitly unrestricted (used to override a role scope)
  'own',                -- only rows the user is assigned to or created
  'customers',          -- only these customers
  'contractors',        -- only these contractors
  'task_types',         -- only these task types
  'statuses',           -- only these statuses
  'execution_methods',
  'trucks',
  'date_window'         -- only a rolling window around today
);

-- ===== catalog: modules =====
-- Modules exist so the admin screen can group hundreds of keys into sections
-- without a hard-coded list in the client.
create table permission_modules (
  key text primary key,
  label_he text not null,
  description_he text,
  icon text,
  sort_order int not null default 100
);

-- ===== catalog: permissions =====
create table permission_registry (
  key text primary key,
  module text not null references permission_modules(key) on update cascade,
  -- resource/action are derived from the key and kept as columns so RLS and
  -- the legacy app.has_permission(resource, action) shim can filter on them.
  resource text not null,
  action text not null,
  label_he text not null,
  description_he text,
  -- 'access'  — may open the module at all
  -- 'crud'    — view/create/edit/delete
  -- 'field'   — controls one field or a small group of fields
  -- 'action'  — a verb that is not CRUD (duplicate, export, delegate…)
  -- 'admin'   — governs the permission system itself
  category text not null default 'action'
    check (category in ('access', 'crud', 'field', 'action', 'admin')),
  -- surfaced with a warning in the UI: money, credentials, permissions
  is_dangerous boolean not null default false,
  -- which kinds of user this key is meaningful for (UI filtering only)
  applies_to user_kind[] not null default array['staff', 'customer_user', 'contractor_user']::user_kind[],
  -- Coarser key this one falls back to when nobody has ruled on it directly.
  -- Set on every key that carves a slice out of an existing permission.
  implied_by text references permission_registry(key) on delete set null,
  default_allowed boolean not null default false,
  sort_order int not null default 100,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);
create index permission_registry_module_idx on permission_registry (module, sort_order);

-- ===== catalog: fields =====
-- Field-level control. `table_name`/`column_name` wire a logical field to a
-- physical column so one generic trigger can enforce edit rights on every
-- table without a bespoke trigger per entity.
create table field_registry (
  entity text not null,
  field_key text not null,
  label_he text not null,
  module text not null references permission_modules(key) on update cascade,
  table_name text,
  column_name text,
  is_sensitive boolean not null default false,
  default_can_view boolean not null default true,
  default_can_edit boolean not null default true,
  -- When set, editing this column requires this capability instead of the
  -- generic per-field edit right. This is what makes a permission like
  -- "may change a task's status but nothing else" expressible.
  edit_permission_key text references permission_registry(key) on delete set null,
  sort_order int not null default 100,
  primary key (entity, field_key)
);
create index field_registry_table_idx on field_registry (table_name);

-- ===== roles =====
create table permission_roles (
  id uuid primary key default gen_random_uuid(),
  key text not null unique,
  name_he text not null,
  description_he text,
  -- null = assignable to any kind of user
  user_kind user_kind,
  is_system boolean not null default false,
  sort_order int not null default 100,
  is_active boolean not null default true,
  deleted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create trigger permission_roles_updated before update on permission_roles
  for each row execute function app.set_updated_at();

create table role_permissions (
  role_id uuid not null references permission_roles(id) on delete cascade,
  permission_key text not null references permission_registry(key) on delete cascade,
  allowed boolean not null default true,
  primary key (role_id, permission_key)
);

create table profile_roles (
  profile_id uuid not null references profiles(id) on delete cascade,
  role_id uuid not null references permission_roles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (profile_id, role_id)
);
create index profile_roles_role_idx on profile_roles (role_id);

-- ===== per-user grants and per-kind defaults =====
create table user_permission_grants (
  profile_id uuid not null references profiles(id) on delete cascade,
  permission_key text not null references permission_registry(key) on delete cascade,
  allowed boolean not null,
  created_at timestamptz not null default now(),
  primary key (profile_id, permission_key)
);

create table kind_permission_defaults (
  user_kind user_kind not null,
  permission_key text not null references permission_registry(key) on delete cascade,
  allowed boolean not null,
  primary key (user_kind, permission_key)
);

-- ===== data scopes =====
-- "Which rows may this person see" — orthogonal to "which verbs may they use".
-- Rows attach to a profile or to a role; profile rows, when present for a
-- resource, replace the role rows for that resource entirely (so an
-- individual can be widened or narrowed without editing the shared role).
create table permission_scopes (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid references profiles(id) on delete cascade,
  role_id uuid references permission_roles(id) on delete cascade,
  resource text not null,
  scope_type permission_scope_type not null,
  scope_values uuid[] not null default '{}',
  days_back int,
  days_forward int,
  created_at timestamptz not null default now(),
  constraint scope_target check (num_nonnulls(profile_id, role_id) = 1),
  constraint scope_window check (
    scope_type <> 'date_window' or days_back is not null or days_forward is not null)
);
create index permission_scopes_profile_idx on permission_scopes (profile_id, resource);
create index permission_scopes_role_idx on permission_scopes (role_id, resource);

-- ===== field_permissions gains role support =====
alter table field_permissions add column role_id uuid references permission_roles(id) on delete cascade;
alter table field_permissions drop constraint field_perm_target;
alter table field_permissions add constraint field_perm_target
  check (num_nonnulls(profile_id, user_kind, role_id) = 1);
drop index field_perm_kind_uq;
create unique index field_perm_kind_uq on field_permissions (user_kind, entity, field_key)
  where profile_id is null and role_id is null;
create unique index field_perm_role_uq on field_permissions (role_id, entity, field_key)
  where role_id is not null;

-- ===== resolution =====

-- Roles the current user belongs to. Wrapped in (select …) at call sites so
-- Postgres evaluates it once per query as an InitPlan rather than per row.
create or replace function app.my_role_ids() returns uuid[]
language sql stable security definer set search_path = public as $$
  select coalesce(array_agg(pr.role_id), '{}'::uuid[])
  from profile_roles pr
  join permission_roles r on r.id = pr.role_id
  where pr.profile_id = app.profile_id() and r.is_active and r.deleted_at is null
$$;

-- The one place a permission decision is made.
--
-- `chain` walks the key up its implied_by ancestry; `resolved` asks each layer
-- about each key in the chain. Every arm returns NULL when that layer has no
-- opinion, so the first non-NULL answer nearest the requested key wins.
--
-- bool_or over zero role rows is NULL (no opinion); over rows that are all
-- false it is false — an explicit role denial, which correctly outranks the
-- kind default. default_allowed only speaks when true, so a registry row
-- reading false still defers to the parent key rather than ending the walk.
--
-- The depth cap is a safety net: a catalog edit that made implied_by circular
-- would otherwise spin here, inside a policy, on every query.
create or replace function app.has(p_key text) returns boolean
language sql stable security definer set search_path = public as $$
  with recursive chain(key, depth) as (
    select p_key, 0
    union all
    select r.implied_by, c.depth + 1
    from chain c
    join permission_registry r on r.key = c.key
    where r.implied_by is not null and c.depth < 8
  ),
  resolved as (
    select c.depth, coalesce(
      (select g.allowed from user_permission_grants g
        where g.profile_id = app.profile_id() and g.permission_key = c.key),
      (select bool_or(rp.allowed) from role_permissions rp
        where rp.role_id = any(app.my_role_ids()) and rp.permission_key = c.key),
      (select k.allowed from kind_permission_defaults k
        where k.user_kind = app.user_kind()::user_kind and k.permission_key = c.key),
      (select true from permission_registry r
        where r.key = c.key and r.is_active and r.default_allowed)
    ) as decided
    from chain c
  )
  select case
    when app.is_admin() then true
    when app.profile_id() is null then false
    else coalesce(
      (select decided from resolved where decided is not null order by depth limit 1),
      false)
  end
$$;

-- Every key in one call — for get_my_permissions and for screens that need a
-- handful of checks without a round trip each.
create or replace function app.has_all(p_keys text[]) returns boolean
language sql stable security definer set search_path = public as $$
  select bool_and(app.has(k)) from unnest(p_keys) k
$$;

create or replace function app.has_any(p_keys text[]) returns boolean
language sql stable security definer set search_path = public as $$
  select bool_or(app.has(k)) from unnest(p_keys) k
$$;

-- Legacy shim. Every policy written in 0005 calls this; replacing the body
-- (rather than the signature) keeps those policies valid while routing them
-- through the new resolver.
create or replace function app.has_permission(p_resource text, p_action permission_action)
returns boolean language sql stable security definer set search_path = public as $$
  select app.has(p_resource || '.' || p_action::text)
$$;

-- Raise a Hebrew, user-facing error unless the capability is held. RPCs call
-- this instead of hand-rolling an `if not … then raise` each time.
create or replace function app.require(p_key text, p_message text default null)
returns void language plpgsql stable security definer set search_path = public as $$
begin
  if not app.has(p_key) then
    raise exception '%', coalesce(
      p_message,
      'אין לך הרשאה לבצע פעולה זו (' ||
        coalesce((select label_he from permission_registry where key = p_key), p_key) || ')')
      using errcode = '42501';
  end if;
end $$;

-- ===== field-level resolution =====
create or replace function app.can_view_field(p_entity text, p_field text)
returns boolean language sql stable security definer set search_path = public as $$
  select case
    when app.is_admin() then true
    when app.profile_id() is null then false
    else coalesce(
      (select f.can_view from field_permissions f
        where f.profile_id = app.profile_id() and f.entity = p_entity and f.field_key = p_field),
      (select bool_or(f.can_view) from field_permissions f
        where f.role_id = any(app.my_role_ids()) and f.entity = p_entity and f.field_key = p_field),
      (select f.can_view from field_permissions f
        where f.profile_id is null and f.role_id is null
          and f.user_kind = app.user_kind()::user_kind
          and f.entity = p_entity and f.field_key = p_field),
      (select fr.default_can_view from field_registry fr
        where fr.entity = p_entity and fr.field_key = p_field),
      true)
  end
$$;

-- Editing implies viewing: a field you cannot read is never writable, so a
-- hidden field can't be blind-overwritten through a crafted request.
create or replace function app.can_edit_field(p_entity text, p_field text)
returns boolean language sql stable security definer set search_path = public as $$
  select case
    when app.is_admin() then true
    when app.profile_id() is null then false
    when not app.can_view_field(p_entity, p_field) then false
    else coalesce(
      (select f.can_edit from field_permissions f
        where f.profile_id = app.profile_id() and f.entity = p_entity and f.field_key = p_field),
      (select bool_or(f.can_edit) from field_permissions f
        where f.role_id = any(app.my_role_ids()) and f.entity = p_entity and f.field_key = p_field),
      (select f.can_edit from field_permissions f
        where f.profile_id is null and f.role_id is null
          and f.user_kind = app.user_kind()::user_kind
          and f.entity = p_entity and f.field_key = p_field),
      (select fr.default_can_edit from field_registry fr
        where fr.entity = p_entity and fr.field_key = p_field),
      true)
  end
$$;

-- ===== scope resolution =====

-- Effective scope rows for a resource: the person's own rows if they have any,
-- otherwise the union of their roles' rows. Mixing the two would make a
-- narrowing override impossible — a role saying "customers A,B" plus a user
-- row saying "customer A" would union back to A,B.
create or replace function app.scope_rows(p_resource text)
returns setof permission_scopes
language sql stable security definer set search_path = public as $$
  select * from permission_scopes
    where resource = p_resource and profile_id = app.profile_id()
  union all
  select * from permission_scopes
    where resource = p_resource and role_id = any(app.my_role_ids())
      and not exists (select 1 from permission_scopes s2
                      where s2.resource = p_resource and s2.profile_id = app.profile_id())
$$;

-- NULL means "unrestricted on this dimension", which is what an absent scope
-- and an explicit 'all' scope both produce.
create or replace function app.scope_ids(p_resource text, p_type permission_scope_type)
returns uuid[] language sql stable security definer set search_path = public as $$
  select nullif(
    array(select distinct u from app.scope_rows(p_resource) s, unnest(s.scope_values) u
          where s.scope_type = p_type),
    '{}'::uuid[])
$$;

create or replace function app.scope_own(p_resource text)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from app.scope_rows(p_resource) where scope_type = 'own')
$$;

-- Widest window wins when several rows apply, so adding a role can only ever
-- broaden what someone sees, never silently narrow it.
create or replace function app.scope_date_from(p_resource text)
returns date language sql stable security definer set search_path = public as $$
  select (current_date - max(days_back))::date from app.scope_rows(p_resource)
   where scope_type = 'date_window' and days_back is not null
$$;

create or replace function app.scope_date_to(p_resource text)
returns date language sql stable security definer set search_path = public as $$
  select (current_date + max(days_forward))::date from app.scope_rows(p_resource)
   where scope_type = 'date_window' and days_forward is not null
$$;

-- Immutable so the planner inlines it: policies read as one short predicate
-- per dimension while the scope array itself is an InitPlan computed once.
create or replace function app.in_id_scope(p_scope uuid[], p_value uuid)
returns boolean language sql immutable as $$
  select p_scope is null or (p_value is not null and p_value = any(p_scope))
$$;

create or replace function app.in_date_scope(p_from date, p_to date, p_value date)
returns boolean language sql immutable as $$
  select (p_from is null or (p_value is not null and p_value >= p_from))
     and (p_to   is null or (p_value is not null and p_value <= p_to))
$$;

-- ===== registration helpers (the extension point for future modules) =====
create or replace function app.register_module(
  p_key text, p_label text, p_description text default null,
  p_icon text default null, p_sort int default 100)
returns void language sql security definer set search_path = public as $$
  insert into permission_modules (key, label_he, description_he, icon, sort_order)
  values (p_key, p_label, p_description, p_icon, p_sort)
  on conflict (key) do update set
    label_he = excluded.label_he,
    description_he = coalesce(excluded.description_he, permission_modules.description_he),
    icon = coalesce(excluded.icon, permission_modules.icon),
    sort_order = excluded.sort_order
$$;

-- Resource and action are split off the key: 'tasks.assign.worker' is resource
-- 'tasks', action 'assign.worker'. A one-segment key gets action 'access'.
create or replace function app.register_permission(
  p_key text, p_module text, p_label text,
  p_description text default null,
  p_category text default 'action',
  p_default_allowed boolean default false,
  p_dangerous boolean default false,
  p_applies_to user_kind[] default array['staff', 'customer_user', 'contractor_user']::user_kind[],
  p_implied_by text default null,
  p_sort int default 100)
returns void language sql security definer set search_path = public as $$
  insert into permission_registry (
    key, module, resource, action, label_he, description_he,
    category, default_allowed, is_dangerous, applies_to, implied_by, sort_order)
  values (
    p_key, p_module,
    split_part(p_key, '.', 1),
    case when strpos(p_key, '.') = 0 then 'access'
         else substr(p_key, strpos(p_key, '.') + 1) end,
    p_label, p_description, p_category, p_default_allowed, p_dangerous, p_applies_to, p_implied_by, p_sort)
  on conflict (key) do update set
    module = excluded.module,
    label_he = excluded.label_he,
    description_he = coalesce(excluded.description_he, permission_registry.description_he),
    category = excluded.category,
    is_dangerous = excluded.is_dangerous,
    applies_to = excluded.applies_to,
    implied_by = excluded.implied_by,
    sort_order = excluded.sort_order,
    is_active = true
$$;

create or replace function app.register_field(
  p_entity text, p_field text, p_label text, p_module text,
  p_table text default null, p_column text default null,
  p_sensitive boolean default false,
  p_default_view boolean default true,
  p_default_edit boolean default true,
  p_edit_permission_key text default null,
  p_sort int default 100)
returns void language sql security definer set search_path = public as $$
  insert into field_registry (
    entity, field_key, label_he, module, table_name, column_name,
    is_sensitive, default_can_view, default_can_edit, edit_permission_key, sort_order)
  values (
    p_entity, p_field, p_label, p_module, p_table, coalesce(p_column, p_field),
    p_sensitive, p_default_view, p_default_edit, p_edit_permission_key, p_sort)
  on conflict (entity, field_key) do update set
    label_he = excluded.label_he,
    module = excluded.module,
    table_name = excluded.table_name,
    column_name = excluded.column_name,
    is_sensitive = excluded.is_sensitive,
    default_can_view = excluded.default_can_view,
    default_can_edit = excluded.default_can_edit,
    edit_permission_key = excluded.edit_permission_key,
    sort_order = excluded.sort_order
$$;

-- Replaces a role's whole grant set.
--
-- `p_close_modules` is what makes a narrow role stay narrow. Without it, a role
-- granted 'tasks.edit' also inherits every key that names tasks.edit as its
-- implied_by — which is right for a legacy grant but wrong for a role that was
-- deliberately written to allow only part of a module. Closing a module writes
-- an explicit deny for every key in it the role was not given, and an explicit
-- deny outranks the implied_by fallback.
create or replace function app.set_role_permissions(
  p_role_key text, p_keys text[], p_close_modules text[] default '{}')
returns void language plpgsql security definer set search_path = public as $$
declare v_role uuid;
begin
  select id into v_role from permission_roles where key = p_role_key;
  if v_role is null then raise exception 'תפקיד לא נמצא: %', p_role_key; end if;
  delete from role_permissions where role_id = v_role;

  insert into role_permissions (role_id, permission_key, allowed)
  select v_role, k, true from unnest(p_keys) k
  where exists (select 1 from permission_registry r where r.key = k)
  on conflict do nothing;

  insert into role_permissions (role_id, permission_key, allowed)
  select v_role, r.key, false
  from permission_registry r
  where r.module = any(p_close_modules) and r.is_active and not (r.key = any(p_keys))
  on conflict do nothing;
end $$;

-- Grant a role every key in a module — how a role stays complete as the
-- module grows, without anyone remembering to revisit the seed.
create or replace function app.grant_role_module(p_role_key text, p_module text)
returns void language plpgsql security definer set search_path = public as $$
declare v_role uuid;
begin
  select id into v_role from permission_roles where key = p_role_key;
  if v_role is null then raise exception 'תפקיד לא נמצא: %', p_role_key; end if;
  insert into role_permissions (role_id, permission_key, allowed)
  select v_role, r.key, true from permission_registry r where r.module = p_module and r.is_active
  on conflict (role_id, permission_key) do update set allowed = true;
end $$;

-- ===== audit: the permission tables are themselves audited =====
-- app.audit() derives row_id from an `id` column; these junction tables have
-- composite keys, so teach it the two new synthetic sources and let it skip
-- (rather than fail) anything it still cannot key.
create or replace function app.audit()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_old jsonb; v_new jsonb; v_changed text[]; v_row_id uuid;
begin
  if tg_op = 'INSERT' then
    v_new := to_jsonb(new); v_row_id := (v_new ->> 'id')::uuid;
  elsif tg_op = 'UPDATE' then
    v_old := to_jsonb(old); v_new := to_jsonb(new); v_row_id := (v_new ->> 'id')::uuid;
    select coalesce(array_agg(key), '{}') into v_changed
    from jsonb_each(v_new) as n(key, value)
    where v_old -> key is distinct from value;
    if v_changed = '{}' then return new; end if;
  else
    v_old := to_jsonb(old); v_row_id := (v_old ->> 'id')::uuid;
  end if;
  if v_row_id is null then
    v_row_id := coalesce(
      (coalesce(v_new, v_old) ->> 'task_id')::uuid,
      (coalesce(v_new, v_old) ->> 'event_id')::uuid,
      (coalesce(v_new, v_old) ->> 'profile_id')::uuid,
      (coalesce(v_new, v_old) ->> 'customer_id')::uuid,
      (coalesce(v_new, v_old) ->> 'role_id')::uuid);
  end if;
  if v_row_id is null then return coalesce(new, old); end if;
  insert into audit_log (actor_user_id, action, table_name, row_id, old_data, new_data, changed_cols)
  values (auth.uid(), tg_op::audit_action, tg_table_name, v_row_id, v_old, v_new, v_changed);
  return coalesce(new, old);
end $$;

do $$
declare t text;
begin
  foreach t in array array[
    'permission_roles', 'role_permissions', 'profile_roles',
    'user_permission_grants', 'kind_permission_defaults', 'permission_scopes']
  loop
    execute format(
      'create trigger %I_audit after insert or update or delete on %I
         for each row execute function app.audit()', t, t);
  end loop;
end $$;

-- ===== RLS on the permission model itself =====
do $$
declare t text;
begin
  foreach t in array array[
    'permission_modules', 'permission_registry', 'field_registry',
    'permission_roles', 'role_permissions', 'profile_roles',
    'user_permission_grants', 'kind_permission_defaults', 'permission_scopes']
  loop
    execute format('alter table %I enable row level security', t);
  end loop;
end $$;

-- The catalog is readable by everyone signed in: the client needs labels to
-- render its own screens, and knowing a permission exists grants nothing.
create policy permission_modules_read on permission_modules for select to authenticated using (true);
create policy permission_registry_read on permission_registry for select to authenticated using (true);
create policy field_registry_read on field_registry for select to authenticated using (true);
create policy permission_roles_read on permission_roles for select to authenticated using (true);

create policy permission_modules_write on permission_modules for all to authenticated
  using ((select app.is_admin())) with check ((select app.is_admin()));
create policy permission_registry_write on permission_registry for all to authenticated
  using ((select app.is_admin())) with check ((select app.is_admin()));
create policy field_registry_write on field_registry for all to authenticated
  using ((select app.is_admin())) with check ((select app.is_admin()));

create policy permission_roles_write on permission_roles for all to authenticated
  using ((select app.is_admin()) or app.has('settings.permissions'))
  with check ((select app.is_admin()) or app.has('settings.permissions'));

create policy role_permissions_read on role_permissions for select to authenticated
  using ((select app.is_admin()) or app.has('users.view') or app.has('settings.permissions'));
create policy role_permissions_write on role_permissions for all to authenticated
  using ((select app.is_admin()) or app.has('settings.permissions'))
  with check ((select app.is_admin()) or app.has('settings.permissions'));

-- Everyone may see which roles they themselves hold.
create policy profile_roles_read on profile_roles for select to authenticated
  using ((select app.is_admin()) or profile_id = (select app.profile_id()) or app.has('users.view'));
create policy profile_roles_write on profile_roles for all to authenticated
  using ((select app.is_admin()) or app.has('users.manage_permissions'))
  with check ((select app.is_admin()) or app.has('users.manage_permissions'));

create policy user_grants_read on user_permission_grants for select to authenticated
  using ((select app.is_admin()) or profile_id = (select app.profile_id()) or app.has('users.view'));
create policy user_grants_write on user_permission_grants for all to authenticated
  using ((select app.is_admin()) or app.has('users.manage_permissions'))
  with check ((select app.is_admin()) or app.has('users.manage_permissions'));

create policy kind_defaults_read on kind_permission_defaults for select to authenticated using (true);
create policy kind_defaults_write on kind_permission_defaults for all to authenticated
  using ((select app.is_admin()) or app.has('settings.permissions'))
  with check ((select app.is_admin()) or app.has('settings.permissions'));

create policy permission_scopes_read on permission_scopes for select to authenticated
  using ((select app.is_admin()) or profile_id = (select app.profile_id()) or app.has('users.view'));
create policy permission_scopes_write on permission_scopes for all to authenticated
  using ((select app.is_admin()) or app.has('users.manage_scopes'))
  with check ((select app.is_admin()) or app.has('users.manage_scopes'));

-- field_permissions predates this file; widen its write gate to the new key.
drop policy fp_admin on field_permissions;
create policy fp_read on field_permissions for select to authenticated
  using ((select app.is_admin()) or profile_id = (select app.profile_id()) or app.has('users.view'));
create policy fp_write on field_permissions for all to authenticated
  using ((select app.is_admin()) or app.has('users.manage_permissions'))
  with check ((select app.is_admin()) or app.has('users.manage_permissions'));
