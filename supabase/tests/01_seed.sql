-- Seed run as postgres. The guard triggers deliberately no-op when auth.uid()
-- is null, which is what lets seeding and the service-role edge function work —
-- so this also exercises that escape hatch.

-- Supabase grants these to authenticated via default privileges; replicate it.
grant usage on schema public, app to anon, authenticated, service_role;
grant all on all tables in schema public to authenticated;
grant all on all sequences in schema public to authenticated;
grant execute on all functions in schema public, app to authenticated;

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000a1', 'owner@vl.test'),
  ('00000000-0000-0000-0000-0000000000c1', 'client-admin@acme.test'),
  ('00000000-0000-0000-0000-0000000000c2', 'client-sub@acme.test'),
  ('00000000-0000-0000-0000-0000000000f1', 'staff@vl.test'),
  ('00000000-0000-0000-0000-0000000000f2', 'staff2@vl.test');

insert into customers (id, name, can_create_events) values
  ('10000000-0000-0000-0000-000000000001', 'אקמי הפקות', true),
  ('10000000-0000-0000-0000-000000000002', 'לקוח אחר', true);

insert into profiles (id, user_id, user_kind, is_admin, full_name, customer_id) values
  ('20000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000000a1',
   'staff', true, 'בעל המערכת', null),
  ('20000000-0000-0000-0000-0000000000f1', '00000000-0000-0000-0000-0000000000f1',
   'staff', false, 'איש צוות', null),
  ('20000000-0000-0000-0000-0000000000f2', '00000000-0000-0000-0000-0000000000f2',
   'staff', false, 'איש צוות ב', null),
  ('20000000-0000-0000-0000-0000000000c1', '00000000-0000-0000-0000-0000000000c1',
   'customer_user', false, 'מנהל אצל הלקוח', '10000000-0000-0000-0000-000000000001'),
  ('20000000-0000-0000-0000-0000000000c2', '00000000-0000-0000-0000-0000000000c2',
   'customer_user', false, 'תת-משתמש', '10000000-0000-0000-0000-000000000001');

insert into staff_roles (profile_id, role) values
  ('20000000-0000-0000-0000-0000000000f1', 'driver');

-- The client admin: may manage their own people. Since 0066 the events.* edit
-- rights come from the customer_manager role rather than kind defaults (which
-- now open only view), so the role is attached below; only the users.* keys and
-- the deliberately-withheld ones are set as personal grants here.
insert into user_permission_grants (profile_id, permission_key, allowed) values
  ('20000000-0000-0000-0000-0000000000c1', 'users.view',               true),
  ('20000000-0000-0000-0000-0000000000c1', 'users.create',             true),
  ('20000000-0000-0000-0000-0000000000c1', 'users.edit',               true),
  ('20000000-0000-0000-0000-0000000000c1', 'users.delete',             true),
  ('20000000-0000-0000-0000-0000000000c1', 'users.create_login',       true),
  ('20000000-0000-0000-0000-0000000000c1', 'users.manage_permissions', true),
  -- 0026 made the personal attendance keys grantable to a client. Held here so
  -- the "can hand on what you hold" branch is reachable — without it the guard
  -- would refuse for the other reason and prove nothing about applies_to.
  ('20000000-0000-0000-0000-0000000000c1', 'attendance.clock',         true);

-- 0066: מנהל אצל הלקוח הוא כעת תפקיד (customer_manager), ולא ברירת מחדל של
-- ה-kind. c1 הוא בדיוק הדמות הזו, ולכן הוא מקבל את התפקיד — כמו ה-backfill
-- שהמיגרציה מריצה על משתמשי לקוח קיימים.
insert into profile_roles (profile_id, role_id)
select '20000000-0000-0000-0000-0000000000c1', id from permission_roles where key = 'customer_manager';

-- A client-facing role that carries a key no client admin holds. The
-- profile_roles guard has three separate reasons to refuse a role, and without
-- this fixture the "carries a key you do not hold" one would never be reached:
-- every seeded client role is a subset of what the client admin already has.
insert into permission_roles (id, key, name_he, user_kind, is_system) values
  ('40000000-0000-0000-0000-000000000091', 'test_client_pricer', 'תפקיד בדיקה', 'customer_user', false);
insert into role_permissions (role_id, permission_key, allowed) values
  ('40000000-0000-0000-0000-000000000091', 'events.view', true),
  ('40000000-0000-0000-0000-000000000091', 'pricing.edit', true);

-- an event belonging to the *other* customer, for cross-tenant probes
insert into events (id, customer_id, event_date) values
  ('30000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000002', current_date + 3);

-- per-company form config: volume_m hidden for אקמי
update customer_form_fields set state = 'hidden'
  where customer_id = '10000000-0000-0000-0000-000000000001' and field_key = 'volume_m';

-- per-user override: event_number required for the client admin only
insert into user_form_fields (profile_id, field_key, state) values
  ('20000000-0000-0000-0000-0000000000c1', 'event_number', 'required');

-- ===== assertion helpers (SECURITY INVOKER: run as whoever calls them) =====
create or replace function t_expect_fail(p_label text, p_sql text)
returns text language plpgsql as $$
begin
  execute p_sql;
  return 'FAIL  ✗ ' || p_label || ' — statement succeeded but should have been blocked';
exception when others then
  return 'pass  ✓ ' || p_label;
end $$;

create or replace function t_expect_ok(p_label text, p_sql text)
returns text language plpgsql as $$
begin
  execute p_sql;
  return 'pass  ✓ ' || p_label;
exception when others then
  return 'FAIL  ✗ ' || p_label || ' — ' || sqlerrm;
end $$;

create or replace function t_eq(p_label text, p_actual anyelement, p_expected anyelement)
returns text language plpgsql as $$
begin
  if p_actual is not distinct from p_expected then
    return 'pass  ✓ ' || p_label;
  end if;
  return 'FAIL  ✗ ' || p_label || ' — got ' || coalesce(p_actual::text,'null')
       || ', expected ' || coalesce(p_expected::text,'null');
end $$;

-- RLS makes a forbidden UPDATE affect zero rows rather than raise, so this
-- distinguishes "silently did nothing" from "was blocked".
create or replace function t_rows(p_label text, p_sql text, p_expected int)
returns text language plpgsql as $$
declare n int;
begin
  execute p_sql;
  get diagnostics n = row_count;
  if n = p_expected then return 'pass  ✓ ' || p_label; end if;
  return 'FAIL  ✗ ' || p_label || ' — affected ' || n || ' rows, expected ' || p_expected;
exception when others then
  return 'pass  ✓ ' || p_label || ' (raised)';
end $$;

-- create_event inserts a row the *calling statement's* snapshot cannot see, so
-- the read has to happen in a later statement. plpgsql gives each statement its
-- own snapshot; a scalar subquery in the same SELECT does not.
create or replace function t_created_event(p_payload jsonb)
returns events language plpgsql as $$
declare v_id uuid; v_row events;
begin
  v_id := create_event(p_payload);
  select * into v_row from events where id = v_id;
  return v_row;
end $$;

create or replace function t_updated_event(p_id uuid, p_payload jsonb)
returns events language plpgsql as $$
declare v_row events;
begin
  perform update_event(p_id, p_payload);
  select * into v_row from events where id = p_id;
  return v_row;
end $$;

grant execute on function t_expect_fail(text,text), t_expect_ok(text,text),
  t_rows(text,text,int), t_created_event(jsonb), t_updated_event(uuid,jsonb) to authenticated;
grant execute on function t_eq(text,anyelement,anyelement) to authenticated;
