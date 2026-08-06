-- 0012: enforcement — where the catalog stops being a list and starts saying no
--
-- Four mechanisms, in order of how much they cover:
--
--   1. app.enforce_field_perms()  — one BEFORE UPDATE trigger, driven entirely
--      by field_registry, that rejects a change to any column the user may not
--      write. It sits on the *table*, so it covers every write path at once:
--      the work board's direct update, bulk_update_tasks, the calendar's raw
--      event_date update, and anything written after this file.
--   2. Row scopes woven into the SELECT policies — "which data may they see".
--   3. Granular policies for the junction tables (assignment by role, money).
--   4. app.require() inside the RPCs for verbs that aren't a column write.
--
-- Read masking is generated from field_registry too (app.rebuild_secure_view),
-- so a field registered tomorrow is masked by regenerating the view rather than
-- by hand-editing SQL.

-- ===== system writes =====
-- Some triggers and RPCs write on the user's behalf after already checking a
-- coarser permission: delegating a task rewrites its terms row, saving an event
-- rewrites its הקמה/פירוק tasks. Those writes must not be re-judged column by
-- column against the *user's* field rights, or "may edit the event" would
-- require "may reschedule tasks". The flag is transaction-local and is turned
-- off again immediately after the nested write, so the window is exactly the
-- statement that needs it.
create or replace function app.system_write(p_on boolean)
returns void language plpgsql set search_path = public as $$
begin
  perform set_config('app.system_write', case when p_on then 'on' else 'off' end, true);
end $$;

create or replace function app.in_system_write() returns boolean
language sql stable set search_path = public as $$
  select coalesce(current_setting('app.system_write', true), 'off') = 'on'
$$;

-- ===== the column-level gate =====
-- Reads its rules from field_registry keyed on TG_TABLE_NAME, so attaching it
-- to a new table takes a CREATE TRIGGER and no arguments — the registry already
-- knows which columns of that table are governed and by what.
create or replace function app.enforce_field_perms()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_old jsonb := to_jsonb(old);
  v_new jsonb := to_jsonb(new);
  r record;
begin
  -- service role (no JWT) runs migrations and back-office jobs
  if auth.uid() is null then return new; end if;
  if app.in_system_write() then return new; end if;
  if app.is_admin() then return new; end if;

  for r in
    select entity, field_key, label_he, column_name, edit_permission_key
    from field_registry
    where table_name = tg_table_name and column_name is not null
  loop
    if v_old -> r.column_name is not distinct from v_new -> r.column_name then
      continue;
    end if;
    if r.edit_permission_key is not null then
      if not app.has(r.edit_permission_key) then
        raise exception 'אין לך הרשאה לשנות את השדה "%"', r.label_he using errcode = '42501';
      end if;
    elsif not app.can_edit_field(r.entity, r.field_key) then
      raise exception 'אין לך הרשאה לשנות את השדה "%"', r.label_he using errcode = '42501';
    end if;
  end loop;
  return new;
end $$;

-- UPDATE only. Creation is gated by the module's `create` permission; making
-- INSERT column-aware as well would break the triggers that auto-create the
-- הקמה/פירוק tasks whenever a customer saves an event.
do $$
declare t text;
begin
  foreach t in array array[
    'events', 'event_contacts', 'tasks', 'customers', 'contractors',
    'profiles', 'task_contractor_terms']
  loop
    execute format(
      'create trigger %I_field_perms before update on %I
         for each row execute function app.enforce_field_perms()', t, t);
  end loop;
end $$;

-- Delegating a task rewrites task_contractor_terms; that is authorised by
-- tasks.delegate, not by contractors.edit_pricing.
create or replace function app.sync_contractor_terms()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  perform app.system_write(true);
  if new.contractor_id is not null and
     (tg_op = 'INSERT' or old.contractor_id is distinct from new.contractor_id) then
    insert into task_contractor_terms (task_id, contractor_id, price)
    values (new.id, new.contractor_id,
            coalesce((select default_task_price from contractors where id = new.contractor_id), 0))
    on conflict (task_id) do update
      set contractor_id = excluded.contractor_id, price = excluded.price,
          paid_at = null, paid_amount = null;
    if tg_op = 'UPDATE' and old.contractor_id is not null then
      delete from task_contractor_workers where task_id = new.id;
    end if;
  elsif new.contractor_id is null and tg_op = 'UPDATE' and old.contractor_id is not null then
    delete from task_contractor_terms where task_id = new.id;
    delete from task_contractor_workers where task_id = new.id;
  end if;
  perform app.system_write(false);
  return new;
end $$;

-- ===== row scopes in the SELECT policies =====

-- events
drop policy events_select on events;
create policy events_select on events for select to authenticated using (
  (select app.is_admin())
  or (deleted_at is null
    and app.in_id_scope((select app.scope_ids('events', 'customers')), customer_id)
    and app.in_id_scope((select app.scope_ids('events', 'statuses')), status_id)
    and app.in_date_scope((select app.scope_date_from('events')),
                          (select app.scope_date_to('events')), event_date)
    and (not (select app.scope_own('events'))
         or created_by = (select app.profile_id())
         or exists (select 1 from tasks t
                    where t.event_id = events.id and t.deleted_at is null
                      and exists (select 1 from task_assignments a
                                  where a.task_id = t.id and a.profile_id = (select app.profile_id()))))
    and (
      ((select app.user_kind()) = 'staff' and (select app.has('events.view')))
      or ((select app.user_kind()) = 'customer_user' and customer_id = (select app.customer_id()))
      or ((select app.user_kind()) = 'contractor_user' and exists (
            select 1 from tasks t where t.event_id = events.id
              and t.contractor_id = (select app.contractor_id()) and t.deleted_at is null))
    )));

-- tasks
drop policy tasks_select on tasks;
create policy tasks_select on tasks for select to authenticated using (
  (select app.is_admin())
  or (deleted_at is null
    and app.in_id_scope((select app.scope_ids('tasks', 'customers')), customer_id)
    and app.in_id_scope((select app.scope_ids('tasks', 'contractors')), contractor_id)
    and app.in_id_scope((select app.scope_ids('tasks', 'task_types')), task_type_id)
    and app.in_id_scope((select app.scope_ids('tasks', 'statuses')), status_id)
    and app.in_id_scope((select app.scope_ids('tasks', 'execution_methods')), execution_method_id)
    and app.in_id_scope((select app.scope_ids('tasks', 'trucks')), truck_id)
    and app.in_date_scope((select app.scope_date_from('tasks')),
                          (select app.scope_date_to('tasks')), task_date)
    and (not (select app.scope_own('tasks'))
         or created_by = (select app.profile_id())
         or exists (select 1 from task_assignments a
                    where a.task_id = tasks.id and a.profile_id = (select app.profile_id())))
    and (
      ((select app.user_kind()) = 'staff' and (select app.has('tasks.view')))
      or ((select app.user_kind()) = 'customer_user' and customer_id = (select app.customer_id()))
      or ((select app.user_kind()) = 'contractor_user' and contractor_id = (select app.contractor_id()))
      or exists (select 1 from task_assignments a
                 where a.task_id = tasks.id and a.profile_id = (select app.profile_id()))
    )));

-- customers
drop policy customers_select on customers;
create policy customers_select on customers for select to authenticated using (
  (select app.is_admin())
  or (deleted_at is null
    and app.in_id_scope((select app.scope_ids('customers', 'customers')), id)
    and (
      ((select app.user_kind()) = 'staff' and (select app.has('customers.view')))
      or id = (select app.customer_id())
      or ((select app.user_kind()) = 'contractor_user' and exists (
            select 1 from tasks t where t.customer_id = customers.id
              and t.contractor_id = (select app.contractor_id()) and t.deleted_at is null))
    )));

-- contractors
drop policy contractors_select on contractors;
create policy contractors_select on contractors for select to authenticated using (
  (select app.is_admin())
  or (deleted_at is null
    and app.in_id_scope((select app.scope_ids('contractors', 'contractors')), id)
    and (
      ((select app.user_kind()) = 'staff' and (select app.has('contractors.view')))
      or id = (select app.contractor_id())
    )));

-- ===== assignment: one capability per role =====
create or replace function app.assignment_allowed(p_role assignment_role, p_profile uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select app.is_admin()
    or (p_profile = app.profile_id() and app.has('tasks.assign.self'))
    or case p_role
         when 'worker'    then app.has('tasks.assign.worker')
         when 'driver'    then app.has('tasks.assign.driver')
         when 'team_lead' then app.has('tasks.assign.team_lead')
         else false
       end
$$;

drop policy ta_write on task_assignments;
create policy ta_insert on task_assignments for insert to authenticated with check (
  app.assignment_allowed(role, profile_id)
  and (truck_id is null or (select app.has('tasks.assign.truck'))));
create policy ta_update on task_assignments for update to authenticated
  using (app.assignment_allowed(role, profile_id))
  with check (app.assignment_allowed(role, profile_id)
    and (truck_id is null or (select app.has('tasks.assign.truck'))));
create policy ta_delete on task_assignments for delete to authenticated
  using (app.assignment_allowed(role, profile_id));

-- ===== contractor worker assignment =====
drop policy tcw_staff_write on task_contractor_workers;
create policy tcw_staff_write on task_contractor_workers for all to authenticated
  using ((select app.is_admin()) or (select app.has('contractors.assign_workers')))
  with check ((select app.is_admin()) or (select app.has('contractors.assign_workers')));

drop policy tcw_contractor_insert on task_contractor_workers;
create policy tcw_contractor_insert on task_contractor_workers for insert to authenticated
  with check (
    (select app.has('portal.assign_workers'))
    and exists (select 1 from tasks t where t.id = task_id
                and t.contractor_id = (select app.contractor_id()) and t.deleted_at is null)
    and exists (select 1 from contractor_workers cw
                where cw.id = contractor_worker_id
                  and cw.contractor_id = (select app.contractor_id())
                  and cw.deleted_at is null));

drop policy tcw_contractor_delete on task_contractor_workers;
create policy tcw_contractor_delete on task_contractor_workers for delete to authenticated
  using (
    (select app.has('portal.assign_workers'))
    and exists (select 1 from tasks t where t.id = task_id
                and t.contractor_id = (select app.contractor_id()) and t.deleted_at is null));

-- ===== money =====
drop policy tct_select on task_contractor_terms;
create policy tct_select on task_contractor_terms for select to authenticated using (
  (select app.is_admin())
  or ((select app.user_kind()) = 'staff' and (select app.has('contractors.view_pricing')))
  or (contractor_id = (select app.contractor_id()) and (select app.has('contractors.view_pricing'))));

drop policy tct_write on task_contractor_terms;
create policy tct_write on task_contractor_terms for all to authenticated
  using ((select app.is_admin())
    or (select app.has('contractors.edit_pricing')) or (select app.has('contractors.mark_paid')))
  with check ((select app.is_admin())
    or (select app.has('contractors.edit_pricing')) or (select app.has('contractors.mark_paid')));

-- ===== contractor staff =====
drop policy cw_staff_write on contractor_workers;
create policy cw_staff_write on contractor_workers for all to authenticated
  using ((select app.is_admin()) or (select app.has('contractors.manage_workers')))
  with check ((select app.is_admin()) or (select app.has('contractors.manage_workers')));

drop policy cw_own_insert on contractor_workers;
create policy cw_own_insert on contractor_workers for insert to authenticated
  with check (contractor_id = (select app.contractor_id())
              and (select app.has('portal.manage_workers')));

drop policy cw_own_update on contractor_workers;
create policy cw_own_update on contractor_workers for update to authenticated
  using (contractor_id = (select app.contractor_id()) and deleted_at is null
         and (select app.has('portal.manage_workers')))
  with check (contractor_id = (select app.contractor_id()));

-- ===== audit log =====
drop policy audit_admin on audit_log;
create policy audit_read on audit_log for select to authenticated
  using ((select app.is_admin()) or (select app.has('settings.audit_log')));

-- old_data/new_data are whole-row snapshots, which would otherwise hand back
-- every column a field permission was meant to withhold. Strip the keys the
-- reader may not see before the row leaves the database.
create or replace function app.redact_audit(p_table text, p_data jsonb)
returns jsonb language sql stable security definer set search_path = public as $$
  select case when p_data is null then null else
    p_data - coalesce(
      array(select fr.column_name from field_registry fr
            where fr.table_name = p_table and fr.column_name is not null
              and not app.can_view_field(fr.entity, fr.field_key)),
      '{}'::text[])
  end
$$;

create or replace view audit_log_secure with (security_invoker = true) as
select id, actor_user_id, action, table_name, row_id,
       app.redact_audit(table_name, old_data) as old_data,
       app.redact_audit(table_name, new_data) as new_data,
       changed_cols, created_at
from audit_log;
grant select on audit_log_secure to authenticated;

-- ===== generated read masking =====
-- Builds <table>_secure from the live column list, wrapping every column that
-- field_registry governs in a visibility check. The check is an uncorrelated
-- scalar subquery, so the planner runs it once per query rather than per row.
create or replace function app.rebuild_secure_view(p_table text)
returns void language plpgsql security definer set search_path = public as $$
declare v_cols text;
begin
  select string_agg(
    case when fr.field_key is null then format('t.%I', c.column_name)
         else format('case when (select app.can_view_field(%L, %L)) then t.%I end as %I',
                     fr.entity, fr.field_key, c.column_name, c.column_name)
    end, ', ' order by c.ordinal_position)
  into v_cols
  from information_schema.columns c
  left join field_registry fr
    on fr.table_name = p_table and fr.column_name = c.column_name
  where c.table_schema = 'public' and c.table_name = p_table;

  if v_cols is null then
    raise exception 'טבלה לא נמצאה: %', p_table;
  end if;

  execute format(
    'create or replace view %I with (security_invoker = true) as select %s from %I t',
    p_table || '_secure', v_cols, p_table);
  execute format('grant select on %I to authenticated', p_table || '_secure');
end $$;

select app.rebuild_secure_view('events');
select app.rebuild_secure_view('event_contacts');
select app.rebuild_secure_view('tasks');
select app.rebuild_secure_view('customers');
select app.rebuild_secure_view('contractors');
select app.rebuild_secure_view('profiles');
select app.rebuild_secure_view('task_contractor_terms');

-- The work board view is the single read path behind the board, the event
-- page, the contractor portal and the dashboard — masking it once covers all
-- four. Same column list and types as 0005, so CREATE OR REPLACE is valid.
create or replace view work_board_view
with (security_invoker = true) as
select
  t.id,
  t.event_id,
  t.customer_id,
  c.name  as customer_name,
  c.color as customer_color,
  e.end_client_name,
  e.event_number,
  case when (select app.can_view_field('task', 'location_text'))
    then coalesce(t.location_text, e.location_text) end as location_text,
  e.volume_m,
  e.truck_count as event_truck_count,
  t.task_type_id,
  tt.name as task_type_name,
  tt.code as task_type_code,
  t.title,
  t.task_date,
  t.warehouse_start_time,
  t.onsite_start_time,
  t.onsite_end_time,
  t.hours_count,
  t.worker_count,
  t.execution_method_id,
  em.name as execution_method_name,
  t.truck_id,
  case when (select app.can_view_field('task', 'truck_id')) then tr.name end as truck_name,
  case when (select app.can_view_field('task', 'truck_free_text')) then t.truck_free_text end as truck_free_text,
  case when (select app.can_view_field('task', 'notes')) then t.notes end as notes,
  t.status_id,
  s.name  as status_name,
  s.color as status_color,
  s.is_terminal as status_is_terminal,
  t.contractor_id,
  case when (select app.has('contractors.view')) then ct.name end as contractor_name,
  t.created_at,
  t.updated_at,
  lead_p.full_name as team_lead_name,
  lead_a.profile_id as team_lead_id,
  workers.list  as workers,
  drivers.list  as drivers,
  cworkers.list as contractor_worker_list
from tasks t
left join events e     on e.id = t.event_id
left join customers c  on c.id = t.customer_id
join task_types tt     on tt.id = t.task_type_id
left join execution_methods em on em.id = t.execution_method_id
left join trucks tr    on tr.id = t.truck_id
join statuses s        on s.id = t.status_id
left join contractors ct on ct.id = t.contractor_id
left join lateral (
  select a.profile_id from task_assignments a
  where a.task_id = t.id and a.role = 'team_lead' limit 1
) lead_a on true
left join profiles lead_p on lead_p.id = lead_a.profile_id
left join lateral (
  select jsonb_agg(jsonb_build_object('profile_id', a.profile_id, 'name', p.full_name)
                   order by p.full_name) as list
  from task_assignments a join profiles p on p.id = a.profile_id
  where a.task_id = t.id and a.role = 'worker'
) workers on true
left join lateral (
  select jsonb_agg(jsonb_build_object('profile_id', a.profile_id, 'name', p.full_name,
                                      'truck_id', a.truck_id, 'truck_name', tr2.name)
                   order by p.full_name) as list
  from task_assignments a
  join profiles p on p.id = a.profile_id
  left join trucks tr2 on tr2.id = a.truck_id
  where a.task_id = t.id and a.role = 'driver'
) drivers on true
left join lateral (
  select jsonb_agg(jsonb_build_object('id', cw.id, 'name', cw.full_name)
                   order by cw.full_name) as list
  from task_contractor_workers tcw join contractor_workers cw on cw.id = tcw.contractor_worker_id
  where tcw.task_id = t.id
) cworkers on true
where t.deleted_at is null;

-- ===== RPC hardening =====

-- The הקמה/פירוק section of the event form writes tasks. It is authorised as
-- part of editing the event, so it must not also demand task field rights.
create or replace function app.apply_event_section(
  p_event_id uuid, p_code text, payload jsonb)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_event events;
  v_type task_types;
  v_task_id uuid;
  v_method uuid;
  k_date text := p_code || '_date';
  k_time text := p_code || '_time';
  k_hours text := p_code || '_hours_count';
  k_workers text := p_code || '_worker_count';
  k_method text := p_code || '_execution_method';
begin
  if not (payload ?| array[k_date, k_time, k_hours, k_workers, k_method]) then
    return;
  end if;
  perform app.require('events.manage_setup');

  select * into v_event from events where id = p_event_id;
  select * into v_type from task_types where code = p_code and deleted_at is null;
  if v_type.id is null then return; end if;

  v_method := (nullif(payload ->> k_method, ''))::uuid;
  if v_method is not null then
    if not exists (
      select 1 from execution_methods m
       join task_type_execution_methods ttm
         on ttm.execution_method_id = m.id and ttm.task_type_id = v_type.id
       join customer_execution_methods cem
         on cem.execution_method_id = m.id and cem.customer_id = v_event.customer_id
       where m.id = v_method and m.is_active and m.deleted_at is null)
    then
      raise exception 'אופן הביצוע שנבחר אינו זמין עבור % אצל לקוח זה', v_type.name;
    end if;
  end if;

  select t.id into v_task_id from tasks t
   where t.event_id = p_event_id and t.task_type_id = v_type.id and t.deleted_at is null
   order by t.created_at, t.id limit 1;

  perform app.system_write(true);
  if v_task_id is null then
    insert into tasks (event_id, customer_id, task_type_id, task_date, status_id, worker_count, created_by)
    values (p_event_id, v_event.customer_id, v_type.id,
            coalesce((nullif(payload ->> k_date, ''))::date, v_event.event_date),
            (select id from statuses where entity = 'task' and is_default and deleted_at is null limit 1),
            0, app.profile_id())
    returning id into v_task_id;
  end if;

  update tasks set
    task_date           = case when payload ? k_date
                            then coalesce((nullif(payload ->> k_date, ''))::date, task_date)
                            else task_date end,
    onsite_start_time   = case when payload ? k_time
                            then (nullif(payload ->> k_time, ''))::time else onsite_start_time end,
    hours_count         = case when payload ? k_hours
                            then (nullif(payload ->> k_hours, ''))::numeric else hours_count end,
    worker_count        = case when payload ? k_workers
                            then coalesce((nullif(payload ->> k_workers, ''))::int, 0) else worker_count end,
    execution_method_id = case when payload ? k_method
                            then (nullif(payload ->> k_method, ''))::uuid else execution_method_id end
  where id = v_task_id;
  perform app.system_write(false);
end $$;

-- Bulk edit accepts more columns than the UI offers, so the verb is gated here
-- and each column is judged by the field trigger on its way through.
create or replace function bulk_update_tasks(p_task_ids uuid[], p_patch jsonb)
returns int language plpgsql security definer set search_path = public as $$
declare v_count int;
begin
  perform app.require('tasks.bulk_edit', 'אין לך הרשאה לעריכה מרובה של משימות');
  update tasks set
    task_date            = case when p_patch ? 'task_date' then (p_patch ->> 'task_date')::date else task_date end,
    onsite_start_time    = case when p_patch ? 'onsite_start_time' then (nullif(p_patch ->> 'onsite_start_time',''))::time else onsite_start_time end,
    warehouse_start_time = case when p_patch ? 'warehouse_start_time' then (nullif(p_patch ->> 'warehouse_start_time',''))::time else warehouse_start_time end,
    hours_count          = case when p_patch ? 'hours_count' then (nullif(p_patch ->> 'hours_count',''))::numeric else hours_count end,
    worker_count         = case when p_patch ? 'worker_count' then coalesce((nullif(p_patch ->> 'worker_count',''))::int, 0) else worker_count end,
    execution_method_id  = case when p_patch ? 'execution_method_id' then (nullif(p_patch ->> 'execution_method_id',''))::uuid else execution_method_id end,
    truck_id             = case when p_patch ? 'truck_id' then (nullif(p_patch ->> 'truck_id',''))::uuid else truck_id end,
    truck_free_text      = case when p_patch ? 'truck_free_text' then nullif(p_patch ->> 'truck_free_text','') else truck_free_text end,
    status_id            = case when p_patch ? 'status_id' then (p_patch ->> 'status_id')::uuid else status_id end,
    contractor_id        = case when p_patch ? 'contractor_id' then (nullif(p_patch ->> 'contractor_id',''))::uuid else contractor_id end,
    notes                = case when p_patch ? 'notes' then nullif(p_patch ->> 'notes','') else notes end
  where id = any(p_task_ids) and deleted_at is null;
  get diagnostics v_count = row_count;
  return v_count;
end $$;

create or replace function bulk_import_events(p_rows jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  r jsonb; i int := 0; v_ok int := 0; v_errors jsonb := '[]';
begin
  perform app.require('events.import', 'אין לך הרשאה לייבא אירועים');
  for r in select * from jsonb_array_elements(p_rows) loop
    i := i + 1;
    begin
      perform create_event(r);
      v_ok := v_ok + 1;
    exception when others then
      v_errors := v_errors || jsonb_build_object('row', i, 'error', sqlerrm);
    end;
  end loop;
  return jsonb_build_object('imported', v_ok, 'errors', v_errors);
end $$;

-- Soft delete maps each table to the key that actually governs it, rather than
-- to a generic <resource>.delete that does not exist for the lookup tables.
create or replace function soft_delete(p_table text, p_id uuid, p_restore boolean default false)
returns void language plpgsql security definer set search_path = public as $$
declare v_key text;
begin
  v_key := case p_table
    when 'events'             then case when p_restore then 'events.restore'      else 'events.delete' end
    when 'tasks'              then case when p_restore then 'tasks.restore'       else 'tasks.delete' end
    when 'customers'          then case when p_restore then 'customers.restore'   else 'customers.delete' end
    when 'contractors'        then case when p_restore then 'contractors.restore' else 'contractors.delete' end
    when 'contractor_workers' then 'contractors.manage_workers'
    when 'profiles'           then case when p_restore then 'users.restore'       else 'users.delete' end
    when 'suppliers'          then 'customers.manage_suppliers'
    when 'trucks'             then 'settings.trucks'
    when 'task_types'         then 'settings.task_types'
    when 'execution_methods'  then 'settings.execution_methods'
    when 'statuses'           then 'settings.statuses'
    else null end;
  if v_key is null then raise exception 'טבלה לא נתמכת'; end if;
  perform app.require(v_key, 'אין לך הרשאה למחוק פריט זה');

  if p_table = 'task_types' and not p_restore
     and exists (select 1 from task_types where id = p_id and is_system) then
    raise exception 'לא ניתן למחוק סוג משימה מערכתי';
  end if;

  perform app.system_write(true);
  execute format('update %I set deleted_at = case when $2 then null else now() end where id = $1', p_table)
    using p_id, p_restore;
  perform app.system_write(false);
end $$;

create or replace function duplicate_event(p_event_id uuid, p_new_date date default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_old events; v_new_id uuid; v_shift int;
begin
  perform app.require('events.duplicate', 'אין לך הרשאה לשכפל אירועים');
  select * into v_old from events where id = p_event_id and deleted_at is null;
  if v_old.id is null then raise exception 'אירוע לא נמצא'; end if;
  v_shift := coalesce(p_new_date, v_old.event_date) - v_old.event_date;

  perform app.system_write(true);
  insert into events (customer_id, end_client_name, event_number, event_date,
    location_text, location_provider, location_place_id, location_lat, location_lng,
    location_notes, volume_m, truck_count, notes, status_id,
    no_parking, porterage, supplier_pickup, created_by)
  values (v_old.customer_id, v_old.end_client_name, null,
    v_old.event_date + v_shift,
    v_old.location_text, v_old.location_provider, v_old.location_place_id,
    v_old.location_lat, v_old.location_lng, v_old.location_notes,
    v_old.volume_m, v_old.truck_count, v_old.notes,
    (select id from statuses where entity='event' and is_default and deleted_at is null limit 1),
    v_old.no_parking, v_old.porterage, v_old.supplier_pickup, app.profile_id())
  returning id into v_new_id;

  if app.has('events.view_contacts') then
    insert into event_contacts (event_id, contact_name, contact_phone)
    select v_new_id, contact_name, contact_phone from event_contacts where event_id = p_event_id
    on conflict do nothing;
  end if;

  insert into event_suppliers (event_id, supplier_id)
  select v_new_id, supplier_id from event_suppliers where event_id = p_event_id
  on conflict do nothing;

  insert into tasks (event_id, customer_id, task_type_id, title, task_date,
    onsite_start_time, warehouse_start_time, hours_count, worker_count,
    execution_method_id, truck_id, truck_free_text, notes, status_id, location_text, created_by)
  select v_new_id, t.customer_id, t.task_type_id, t.title, t.task_date + v_shift,
    t.onsite_start_time, t.warehouse_start_time, t.hours_count, t.worker_count,
    t.execution_method_id, t.truck_id, t.truck_free_text, t.notes,
    (select id from statuses where entity='task' and is_default and deleted_at is null limit 1),
    t.location_text, app.profile_id()
  from tasks t
  join task_types tt on tt.id = t.task_type_id
  where t.event_id = p_event_id and t.deleted_at is null and not tt.auto_create_on_event;

  update tasks nt set
    onsite_start_time = ot.onsite_start_time,
    warehouse_start_time = ot.warehouse_start_time,
    hours_count = ot.hours_count,
    worker_count = ot.worker_count,
    execution_method_id = ot.execution_method_id
  from tasks ot
  join task_types tt on tt.id = ot.task_type_id and tt.auto_create_on_event
  where nt.event_id = v_new_id and ot.event_id = p_event_id
    and nt.task_type_id = ot.task_type_id and ot.deleted_at is null and nt.deleted_at is null;
  perform app.system_write(false);

  return v_new_id;
end $$;

-- The dashboard leaked two things regardless of permission: money and the
-- full roster's workload. Both are now conditional.
create or replace function dashboard_stats(p_from date, p_to date)
returns jsonb language sql stable security invoker set search_path = public as $$
  select jsonb_build_object(
    'events_count', (select count(*) from events
       where deleted_at is null and event_date between p_from and p_to),
    'tasks_count', (select count(*) from tasks
       where deleted_at is null and task_date between p_from and p_to),
    'tasks_today', (select count(*) from tasks
       where deleted_at is null and task_date = current_date),
    'tasks_week', (select count(*) from tasks
       where deleted_at is null
         and task_date between date_trunc('week', current_date)::date
         and (date_trunc('week', current_date) + interval '6 days')::date),
    'tasks_overdue', (select count(*) from tasks t join statuses s on s.id = t.status_id
       where t.deleted_at is null and t.task_date < current_date and not s.is_terminal),
    'available_workers', (select count(*) from profiles p
       where p.deleted_at is null and p.is_active and p.user_kind = 'staff'
         and not exists (select 1 from task_assignments a join tasks t on t.id = a.task_id
                         where a.profile_id = p.id and t.task_date = current_date and t.deleted_at is null)),
    'by_customer', (select coalesce(jsonb_agg(row_to_json(x)), '[]') from (
       select c.name, c.color, count(*) as cnt from tasks t join customers c on c.id = t.customer_id
       where t.deleted_at is null and t.task_date between p_from and p_to
       group by c.name, c.color order by cnt desc limit 12) x),
    'by_contractor', (select coalesce(jsonb_agg(row_to_json(x)), '[]') from (
       select ct.name, count(*) as cnt from tasks t join contractors ct on ct.id = t.contractor_id
       where t.deleted_at is null and t.task_date between p_from and p_to
       group by ct.name order by cnt desc limit 12) x),
    'by_worker', case when app.has('dashboard.all_workers') then
      (select coalesce(jsonb_agg(row_to_json(x)), '[]') from (
         select p.full_name as name, count(*) as cnt
         from task_assignments a
         join tasks t on t.id = a.task_id and t.deleted_at is null
           and t.task_date between p_from and p_to
         join profiles p on p.id = a.profile_id
         group by p.full_name order by cnt desc limit 12) x)
      else '[]'::jsonb end,
    'financial', case when app.has('dashboard.financial') then
      (select jsonb_build_object(
         'expected', coalesce(sum(tct.price), 0),
         'paid', coalesce(sum(tct.paid_amount) filter (where tct.paid_at is not null), 0))
       from task_contractor_terms tct
       join tasks t on t.id = tct.task_id and t.deleted_at is null
        and t.task_date between p_from and p_to)
      else null end,
    'by_status', (select coalesce(jsonb_agg(row_to_json(x)), '[]') from (
       select s.name, s.color, count(*) as cnt from tasks t join statuses s on s.id = t.status_id
       where t.deleted_at is null and t.task_date between p_from and p_to
       group by s.name, s.color order by cnt desc) x))
$$;

create or replace function contractor_dashboard(p_from date default null, p_to date default null)
returns jsonb language sql stable security invoker set search_path = public as $$
  with my_tasks as (
    select t.*, tct.price, tct.paid_at, tct.paid_amount, s.is_terminal
    from tasks t
    join statuses s on s.id = t.status_id
    left join task_contractor_terms tct on tct.task_id = t.id
    where t.deleted_at is null
      and t.contractor_id = app.contractor_id()
      and (p_from is null or t.task_date >= p_from)
      and (p_to is null or t.task_date <= p_to)
  )
  select jsonb_build_object(
    'tasks_count', (select count(*) from my_tasks),
    'expected_total', case when app.has('portal.view_financials')
      then (select coalesce(sum(price), 0) from my_tasks) else null end,
    'paid_total', case when app.has('portal.view_financials')
      then (select coalesce(sum(coalesce(paid_amount, price)), 0) from my_tasks where paid_at is not null) else null end,
    'unpaid_total', case when app.has('portal.view_financials')
      then (select coalesce(sum(price), 0) from my_tasks where paid_at is null) else null end,
    'completed_count', (select count(*) from my_tasks where is_terminal),
    'upcoming_count', (select count(*) from my_tasks where task_date >= current_date and not is_terminal))
$$;

-- ===== login bootstrap =====
-- Resolves every registry key and every registered field through the same
-- functions RLS uses, so the client can never believe something the server
-- would refuse. `permissions` keeps the old nested shape so existing
-- can(resource, action) call sites keep working.
create or replace function get_my_permissions()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_profile profiles;
  v_caps jsonb; v_legacy jsonb; v_fields jsonb;
  v_roles jsonb; v_app_roles jsonb; v_customer jsonb; v_scopes jsonb;
begin
  select * into v_profile from profiles
    where user_id = auth.uid() and is_active and deleted_at is null;
  if v_profile.id is null then return null; end if;

  select coalesce(jsonb_object_agg(r.key, app.has(r.key)), '{}') into v_caps
    from permission_registry r where r.is_active;

  select coalesce(jsonb_object_agg(resource, actions), '{}') into v_legacy from (
    select split_part(r.key, '.', 1) as resource,
           jsonb_object_agg(substr(r.key, strpos(r.key, '.') + 1), app.has(r.key)) as actions
    from permission_registry r
    where r.is_active
      and substr(r.key, strpos(r.key, '.') + 1) in ('view', 'create', 'edit', 'delete')
    group by 1) x;

  select coalesce(jsonb_agg(jsonb_build_object(
      'entity', fr.entity, 'field_key', fr.field_key,
      'can_view', app.can_view_field(fr.entity, fr.field_key),
      'can_edit', app.can_edit_field(fr.entity, fr.field_key))), '[]') into v_fields
    from field_registry fr;

  select coalesce(jsonb_agg(role), '[]') into v_roles
    from staff_roles where profile_id = v_profile.id;

  select coalesce(jsonb_agg(jsonb_build_object(
      'id', r.id, 'key', r.key, 'name_he', r.name_he)), '[]') into v_app_roles
    from profile_roles pr join permission_roles r on r.id = pr.role_id
    where pr.profile_id = v_profile.id and r.is_active and r.deleted_at is null;

  select coalesce(jsonb_agg(jsonb_build_object(
      'resource', s.resource, 'scope_type', s.scope_type,
      'values', s.scope_values, 'days_back', s.days_back,
      'days_forward', s.days_forward)), '[]') into v_scopes
    from (select distinct resource from permission_scopes) res
    cross join lateral app.scope_rows(res.resource) s;

  if v_profile.customer_id is not null then
    select jsonb_build_object('id', c.id, 'name', c.name, 'color', c.color,
                              'can_create_events', c.can_create_events)
      into v_customer from customers c where c.id = v_profile.customer_id;
  end if;

  return jsonb_build_object(
    'profile', jsonb_build_object(
      'id', v_profile.id, 'full_name', v_profile.full_name,
      'user_kind', v_profile.user_kind, 'is_admin', v_profile.is_admin,
      'customer_id', v_profile.customer_id, 'contractor_id', v_profile.contractor_id,
      'phone', v_profile.phone, 'email', v_profile.email),
    'roles', v_roles,
    'app_roles', v_app_roles,
    'customer', v_customer,
    'permissions', v_legacy,
    'capabilities', v_caps,
    'field_permissions', v_fields,
    'scopes', coalesce(v_scopes, '[]'::jsonb));
end $$;

-- ===== keep anon out of the new surface =====
do $$
declare fn text;
begin
  foreach fn in array array[
    'get_my_permissions()', 'bulk_update_tasks(uuid[], jsonb)', 'bulk_import_events(jsonb)',
    'soft_delete(text, uuid, boolean)', 'duplicate_event(uuid, date)',
    'dashboard_stats(date, date)', 'contractor_dashboard(date, date)']
  loop
    execute format('revoke execute on function public.%s from anon, public', fn);
  end loop;
end $$;
revoke select on audit_log_secure from anon;
