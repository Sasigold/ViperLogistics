-- 0004: permissions, field permissions, audit log, notifications, saved filters, app.* helpers
create table permission_defaults (
  id uuid primary key default gen_random_uuid(),
  user_kind user_kind not null,
  resource text not null,
  action permission_action not null,
  allowed boolean not null default false,
  unique (user_kind, resource, action)
);

create table user_permissions (
  profile_id uuid not null references profiles(id) on delete cascade,
  resource text not null,
  action permission_action not null,
  allowed boolean not null,
  primary key (profile_id, resource, action)
);

create table field_permissions (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid references profiles(id) on delete cascade,
  user_kind user_kind,
  entity text not null,
  field_key text not null,
  can_view boolean not null default true,
  can_edit boolean not null default false,
  constraint field_perm_target check (profile_id is not null or user_kind is not null)
);
create unique index field_perm_user_uq on field_permissions (profile_id, entity, field_key)
  where profile_id is not null;
create unique index field_perm_kind_uq on field_permissions (user_kind, entity, field_key)
  where profile_id is null;

create table saved_filters (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references profiles(id) on delete cascade,
  screen text not null,
  name text not null,
  filters jsonb not null default '{}',
  is_default boolean not null default false,
  created_at timestamptz not null default now()
);
create index saved_filters_owner_idx on saved_filters (profile_id, screen);

create table notifications (
  id uuid primary key default gen_random_uuid(),
  recipient_id uuid not null references profiles(id) on delete cascade,
  type text not null,
  title text not null,
  body text,
  entity_type text,
  entity_id uuid,
  read_at timestamptz,
  created_at timestamptz not null default now()
);
create index notifications_recipient_idx on notifications (recipient_id, created_at desc);
create index notifications_unread_idx on notifications (recipient_id) where read_at is null;

create table audit_log (
  id bigint generated always as identity primary key,
  actor_user_id uuid,
  action audit_action not null,
  table_name text not null,
  row_id uuid not null,
  old_data jsonb,
  new_data jsonb,
  changed_cols text[],
  created_at timestamptz not null default now()
);
create index audit_row_idx on audit_log (table_name, row_id, created_at desc);
create index audit_time_brin on audit_log using brin (created_at);

-- ===== identity helper functions =====
-- SECURITY DEFINER + STABLE: bypass profiles RLS (no recursion), evaluated once
-- per query as an InitPlan when wrapped in (select ...) inside policies.
-- Reading profiles directly (instead of JWT claims) means permission/kind
-- changes apply immediately without a token refresh, and no auth-hook
-- configuration is required.
create or replace function app.is_admin() returns boolean
language sql stable security definer set search_path = public as
$$ select coalesce((select is_admin from profiles
     where user_id = auth.uid() and is_active and deleted_at is null), false) $$;

create or replace function app.user_kind() returns text
language sql stable security definer set search_path = public as
$$ select user_kind::text from profiles
     where user_id = auth.uid() and is_active and deleted_at is null $$;

create or replace function app.profile_id() returns uuid
language sql stable security definer set search_path = public as
$$ select id from profiles
     where user_id = auth.uid() and is_active and deleted_at is null $$;

create or replace function app.customer_id() returns uuid
language sql stable security definer set search_path = public as
$$ select customer_id from profiles
     where user_id = auth.uid() and is_active and deleted_at is null $$;

create or replace function app.contractor_id() returns uuid
language sql stable security definer set search_path = public as
$$ select contractor_id from profiles
     where user_id = auth.uid() and is_active and deleted_at is null $$;

-- ===== permission resolution =====
create or replace function app.has_permission(p_resource text, p_action permission_action)
returns boolean language sql stable security definer set search_path = public as $$
  select case
    when app.is_admin() then true
    else coalesce(
      (select allowed from user_permissions
        where profile_id = app.profile_id() and resource = p_resource and action = p_action),
      (select allowed from permission_defaults
        where user_kind = app.user_kind()::user_kind and resource = p_resource and action = p_action),
      false)
  end
$$;

create or replace function app.can_view_field(p_entity text, p_field text)
returns boolean language sql stable security definer set search_path = public as $$
  select case
    when app.is_admin() then true
    else coalesce(
      (select can_view from field_permissions
        where profile_id = app.profile_id() and entity = p_entity and field_key = p_field),
      (select can_view from field_permissions
        where profile_id is null and user_kind = app.user_kind()::user_kind
          and entity = p_entity and field_key = p_field),
      true)
  end
$$;

-- ===== notifications helper =====
create or replace function app.notify(
  p_recipient uuid, p_type text, p_title text, p_body text,
  p_entity_type text default null, p_entity_id uuid default null)
returns void language plpgsql security definer set search_path = public as $$
begin
  if p_recipient is null then return; end if;
  insert into notifications (recipient_id, type, title, body, entity_type, entity_id)
  values (p_recipient, p_type, p_title, p_body, p_entity_type, p_entity_id);
end $$;

-- ===== generic audit trigger =====
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
    -- composite-key junction tables: synthesize a stable row id from task/event id
    v_row_id := coalesce(
      (coalesce(v_new, v_old) ->> 'task_id')::uuid,
      (coalesce(v_new, v_old) ->> 'event_id')::uuid,
      (coalesce(v_new, v_old) ->> 'profile_id')::uuid,
      (coalesce(v_new, v_old) ->> 'customer_id')::uuid);
  end if;
  insert into audit_log (actor_user_id, action, table_name, row_id, old_data, new_data, changed_cols)
  values (auth.uid(), tg_op::audit_action, tg_table_name, v_row_id, v_old, v_new, v_changed);
  return coalesce(new, old);
end $$;

do $$
declare t text;
begin
  foreach t in array array[
    'customers','contractors','profiles','contractor_workers','events','event_contacts',
    'event_suppliers','tasks','task_assignments','task_contractor_workers','task_contractor_terms',
    'suppliers','trucks','task_types','execution_methods','statuses',
    'customer_form_fields','user_permissions','field_permissions','permission_defaults']
  loop
    execute format(
      'create trigger %I_audit after insert or update or delete on %I
         for each row execute function app.audit()', t, t);
  end loop;
end $$;

-- ===== notification triggers =====
create or replace function app.notify_assignment()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_task tasks; v_label text;
begin
  select * into v_task from tasks where id = new.task_id;
  v_label := coalesce(v_task.title, (select tt.name from task_types tt where tt.id = v_task.task_type_id), 'משימה');
  perform app.notify(new.profile_id, 'task_assigned', 'שובצת למשימה',
    v_label || ' בתאריך ' || to_char(v_task.task_date, 'DD/MM/YYYY'), 'task', new.task_id);
  return new;
end $$;
create trigger task_assignments_notify after insert on task_assignments
  for each row execute function app.notify_assignment();

create or replace function app.notify_contractor_delegation()
returns trigger language plpgsql security definer set search_path = public as $$
declare r record; v_label text;
begin
  if new.contractor_id is not null and
     (tg_op = 'INSERT' or old.contractor_id is distinct from new.contractor_id) then
    v_label := coalesce(new.title, (select tt.name from task_types tt where tt.id = new.task_type_id), 'משימה');
    for r in select id from profiles
      where contractor_id = new.contractor_id and user_kind = 'contractor_user'
        and is_active and deleted_at is null
    loop
      perform app.notify(r.id, 'contractor_task', 'משימה חדשה הוקצתה לך',
        v_label || ' בתאריך ' || to_char(new.task_date, 'DD/MM/YYYY'), 'task', new.id);
    end loop;
  end if;
  return new;
end $$;
create trigger tasks_notify_contractor after insert or update of contractor_id on tasks
  for each row execute function app.notify_contractor_delegation();

create or replace function app.notify_task_time_change()
returns trigger language plpgsql security definer set search_path = public as $$
declare r record; v_label text;
begin
  if old.task_date is distinct from new.task_date
     or old.onsite_start_time is distinct from new.onsite_start_time then
    v_label := coalesce(new.title, (select tt.name from task_types tt where tt.id = new.task_type_id), 'משימה');
    for r in select distinct profile_id from task_assignments where task_id = new.id loop
      perform app.notify(r.profile_id, 'task_changed', 'שינוי בזמני משימה',
        v_label || ' עודכנה ל-' || to_char(new.task_date, 'DD/MM/YYYY') ||
        coalesce(' ' || to_char(new.onsite_start_time, 'HH24:MI'), ''), 'task', new.id);
    end loop;
    for r in select p.id from profiles p
      where new.contractor_id is not null and p.contractor_id = new.contractor_id
        and p.user_kind = 'contractor_user' and p.is_active and p.deleted_at is null
    loop
      perform app.notify(r.id, 'task_changed', 'שינוי בזמני משימה',
        v_label || ' עודכנה ל-' || to_char(new.task_date, 'DD/MM/YYYY'), 'task', new.id);
    end loop;
  end if;
  return new;
end $$;
create trigger tasks_notify_time_change after update of task_date, onsite_start_time on tasks
  for each row execute function app.notify_task_time_change();

create or replace function app.notify_admins_event_created()
returns trigger language plpgsql security definer set search_path = public as $$
declare r record; v_creator profiles;
begin
  select * into v_creator from profiles where id = new.created_by;
  if v_creator.user_kind = 'customer_user' then
    for r in select id from profiles where is_admin and is_active and deleted_at is null loop
      perform app.notify(r.id, 'event_created', 'אירוע חדש נוצר על ידי לקוח',
        (select name from customers where id = new.customer_id) ||
        ' — ' || to_char(new.event_date, 'DD/MM/YYYY'), 'event', new.id);
    end loop;
  end if;
  return new;
end $$;
create trigger events_notify_admins after insert on events
  for each row execute function app.notify_admins_event_created();

-- ===== permission defaults seed =====
insert into permission_defaults (user_kind, resource, action, allowed) values
  -- staff
  ('staff', 'events', 'view', true), ('staff', 'events', 'create', false),
  ('staff', 'events', 'edit', false), ('staff', 'events', 'delete', false),
  ('staff', 'tasks', 'view', true), ('staff', 'tasks', 'create', false),
  ('staff', 'tasks', 'edit', false), ('staff', 'tasks', 'delete', false),
  ('staff', 'customers', 'view', true), ('staff', 'customers', 'create', false),
  ('staff', 'customers', 'edit', false), ('staff', 'customers', 'delete', false),
  ('staff', 'users', 'view', false), ('staff', 'users', 'create', false),
  ('staff', 'users', 'edit', false), ('staff', 'users', 'delete', false),
  ('staff', 'contractors', 'view', false), ('staff', 'contractors', 'create', false),
  ('staff', 'contractors', 'edit', false), ('staff', 'contractors', 'delete', false),
  ('staff', 'settings', 'view', false), ('staff', 'settings', 'edit', false),
  ('staff', 'dashboard', 'view', true),
  -- customer users
  ('customer_user', 'events', 'view', true), ('customer_user', 'events', 'create', true),
  ('customer_user', 'events', 'edit', true), ('customer_user', 'events', 'delete', false),
  ('customer_user', 'tasks', 'view', true), ('customer_user', 'tasks', 'create', false),
  ('customer_user', 'tasks', 'edit', false), ('customer_user', 'tasks', 'delete', false),
  ('customer_user', 'dashboard', 'view', false),
  -- contractor users
  ('contractor_user', 'tasks', 'view', true), ('contractor_user', 'dashboard', 'view', false)
on conflict do nothing;

-- default field visibility: plain staff don't see event contact details
insert into field_permissions (user_kind, entity, field_key, can_view, can_edit) values
  ('staff', 'event', 'contact_phone', false, false)
on conflict do nothing;
