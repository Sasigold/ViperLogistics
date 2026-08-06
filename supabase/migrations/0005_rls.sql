-- 0005: RLS policies + work_board_view
-- Visibility helper: replicates event visibility without RLS recursion
create or replace function app.event_visible(p_event_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select app.is_admin()
    or exists (
      select 1 from events e
      where e.id = p_event_id and e.deleted_at is null
        and (
          (app.user_kind() = 'staff' and app.has_permission('events', 'view'))
          or (app.user_kind() = 'customer_user' and e.customer_id = app.customer_id())
          or (app.user_kind() = 'contractor_user' and exists (
                select 1 from tasks t
                where t.event_id = e.id and t.contractor_id = app.contractor_id()
                  and t.deleted_at is null))
        ))
$$;

-- ===== enable RLS everywhere =====
do $$
declare t text;
begin
  foreach t in array array[
    'customers','contractors','profiles','staff_roles','contractor_workers',
    'task_types','execution_methods','task_type_execution_methods','customer_execution_methods',
    'statuses','trucks','suppliers','form_fields','customer_form_fields','app_settings',
    'events','event_contacts','event_suppliers','tasks','task_assignments',
    'task_contractor_workers','task_contractor_terms',
    'permission_defaults','user_permissions','field_permissions',
    'saved_filters','notifications','audit_log']
  loop
    execute format('alter table %I enable row level security', t);
  end loop;
end $$;

-- ===== customers =====
create policy customers_select on customers for select to authenticated using (
  (select app.is_admin())
  or (deleted_at is null and (
    ((select app.user_kind()) = 'staff' and app.has_permission('customers','view'))
    or id = (select app.customer_id())
    or ((select app.user_kind()) = 'contractor_user' and exists (
          select 1 from tasks t where t.customer_id = customers.id
            and t.contractor_id = (select app.contractor_id()) and t.deleted_at is null))
  )));
create policy customers_insert on customers for insert to authenticated
  with check ((select app.is_admin()) or app.has_permission('customers','create'));
create policy customers_update on customers for update to authenticated
  using ((select app.is_admin()) or (deleted_at is null and app.has_permission('customers','edit')));
create policy customers_delete on customers for delete to authenticated
  using ((select app.is_admin()));

-- ===== contractors =====
create policy contractors_select on contractors for select to authenticated using (
  (select app.is_admin())
  or (deleted_at is null and (
    ((select app.user_kind()) = 'staff' and app.has_permission('contractors','view'))
    or id = (select app.contractor_id())
  )));
create policy contractors_insert on contractors for insert to authenticated
  with check ((select app.is_admin()) or app.has_permission('contractors','create'));
create policy contractors_update on contractors for update to authenticated
  using ((select app.is_admin()) or (deleted_at is null and app.has_permission('contractors','edit')));
create policy contractors_delete on contractors for delete to authenticated
  using ((select app.is_admin()));

-- ===== profiles =====
create policy profiles_select on profiles for select to authenticated using (
  (select app.is_admin())
  or user_id = (select auth.uid())
  or (deleted_at is null and (
    ((select app.user_kind()) = 'staff' and user_kind = 'staff')
    or ((select app.user_kind()) = 'customer_user' and customer_id = (select app.customer_id()))
  )));
create policy profiles_insert on profiles for insert to authenticated
  with check ((select app.is_admin()) or app.has_permission('users','create'));
create policy profiles_update on profiles for update to authenticated
  using ((select app.is_admin()) or (deleted_at is null and app.has_permission('users','edit')));
create policy profiles_delete on profiles for delete to authenticated
  using ((select app.is_admin()));

-- ===== staff_roles =====
create policy staff_roles_select on staff_roles for select to authenticated using (true);
create policy staff_roles_write on staff_roles for all to authenticated
  using ((select app.is_admin()) or app.has_permission('users','edit'))
  with check ((select app.is_admin()) or app.has_permission('users','edit'));

-- ===== contractor_workers =====
create policy cw_select on contractor_workers for select to authenticated using (
  (select app.is_admin())
  or (deleted_at is null and (
    ((select app.user_kind()) = 'staff' and app.has_permission('contractors','view'))
    or contractor_id = (select app.contractor_id())
  )));
create policy cw_staff_write on contractor_workers for all to authenticated
  using ((select app.is_admin()) or app.has_permission('contractors','edit'))
  with check ((select app.is_admin()) or app.has_permission('contractors','edit'));
create policy cw_own_insert on contractor_workers for insert to authenticated
  with check (contractor_id = (select app.contractor_id()));
create policy cw_own_update on contractor_workers for update to authenticated
  using (contractor_id = (select app.contractor_id()) and deleted_at is null)
  with check (contractor_id = (select app.contractor_id()));

-- ===== lookup tables: readable by all, writable by settings editors =====
do $$
declare t text;
begin
  foreach t in array array[
    'task_types','execution_methods','task_type_execution_methods',
    'customer_execution_methods','statuses','trucks','form_fields',
    'customer_form_fields','app_settings']
  loop
    execute format(
      'create policy %I_read on %I for select to authenticated using (true)', t, t);
    execute format(
      'create policy %I_write on %I for all to authenticated
         using ((select app.is_admin()) or app.has_permission(''settings'',''edit''))
         with check ((select app.is_admin()) or app.has_permission(''settings'',''edit''))', t, t);
  end loop;
end $$;

-- ===== suppliers (per-customer) =====
create policy suppliers_select on suppliers for select to authenticated using (
  (select app.is_admin())
  or (deleted_at is null and (
    ((select app.user_kind()) = 'staff' and
       (app.has_permission('customers','view') or app.has_permission('events','view')))
    or customer_id = (select app.customer_id())
  )));
create policy suppliers_write on suppliers for all to authenticated
  using ((select app.is_admin()) or app.has_permission('settings','edit') or app.has_permission('customers','edit'))
  with check ((select app.is_admin()) or app.has_permission('settings','edit') or app.has_permission('customers','edit'));

-- ===== events =====
create policy events_select on events for select to authenticated using (
  (select app.is_admin())
  or (deleted_at is null and (
    ((select app.user_kind()) = 'staff' and app.has_permission('events','view'))
    or ((select app.user_kind()) = 'customer_user' and customer_id = (select app.customer_id()))
    or ((select app.user_kind()) = 'contractor_user' and exists (
          select 1 from tasks t where t.event_id = events.id
            and t.contractor_id = (select app.contractor_id()) and t.deleted_at is null))
  )));
create policy events_insert on events for insert to authenticated with check (
  (select app.is_admin())
  or ((select app.user_kind()) = 'staff' and app.has_permission('events','create'))
  or ((select app.user_kind()) = 'customer_user'
      and customer_id = (select app.customer_id())
      and app.has_permission('events','create')
      and exists (select 1 from customers c
                  where c.id = customer_id and c.can_create_events and c.deleted_at is null)));
create policy events_update on events for update to authenticated using (
  (select app.is_admin())
  or (deleted_at is null and (
    ((select app.user_kind()) = 'staff' and app.has_permission('events','edit'))
    or ((select app.user_kind()) = 'customer_user'
        and customer_id = (select app.customer_id())
        and app.has_permission('events','edit'))
  )));
create policy events_delete on events for delete to authenticated
  using ((select app.is_admin()));

-- ===== event_contacts (field-level security boundary) =====
create policy event_contacts_select on event_contacts for select to authenticated using (
  (select app.is_admin())
  or (app.can_view_field('event','contact_phone') and app.event_visible(event_id)));
create policy event_contacts_write on event_contacts for all to authenticated
  using ((select app.is_admin())
    or (app.event_visible(event_id) and
        (app.has_permission('events','edit') or app.has_permission('events','create'))))
  with check ((select app.is_admin())
    or (app.event_visible(event_id) and
        (app.has_permission('events','edit') or app.has_permission('events','create'))));

-- ===== event_suppliers =====
create policy event_suppliers_select on event_suppliers for select to authenticated
  using ((select app.is_admin()) or app.event_visible(event_id));
create policy event_suppliers_write on event_suppliers for all to authenticated
  using ((select app.is_admin())
    or (app.event_visible(event_id) and app.has_permission('events','edit')))
  with check ((select app.is_admin())
    or (app.event_visible(event_id) and app.has_permission('events','edit')));

-- ===== tasks =====
create policy tasks_select on tasks for select to authenticated using (
  (select app.is_admin())
  or (deleted_at is null and (
    ((select app.user_kind()) = 'staff' and app.has_permission('tasks','view'))
    or ((select app.user_kind()) = 'customer_user' and customer_id = (select app.customer_id()))
    or ((select app.user_kind()) = 'contractor_user' and contractor_id = (select app.contractor_id()))
    or exists (select 1 from task_assignments a
               where a.task_id = tasks.id and a.profile_id = (select app.profile_id()))
  )));
create policy tasks_insert on tasks for insert to authenticated with check (
  (select app.is_admin())
  or ((select app.user_kind()) = 'staff' and app.has_permission('tasks','create')));
create policy tasks_update on tasks for update to authenticated using (
  (select app.is_admin())
  or (deleted_at is null
      and (select app.user_kind()) = 'staff' and app.has_permission('tasks','edit')));
create policy tasks_delete on tasks for delete to authenticated
  using ((select app.is_admin()));

-- ===== task_assignments =====
create policy ta_select on task_assignments for select to authenticated using (
  (select app.is_admin())
  or ((select app.user_kind()) = 'staff' and app.has_permission('tasks','view'))
  or profile_id = (select app.profile_id()));
create policy ta_write on task_assignments for all to authenticated
  using ((select app.is_admin()) or app.has_permission('tasks','edit'))
  with check ((select app.is_admin()) or app.has_permission('tasks','edit'));

-- ===== task_contractor_workers (the contractor's only write surface) =====
create policy tcw_select on task_contractor_workers for select to authenticated using (
  (select app.is_admin())
  or ((select app.user_kind()) = 'staff'
      and (app.has_permission('tasks','view') or app.has_permission('contractors','view')))
  or exists (select 1 from tasks t where t.id = task_id
             and t.contractor_id = (select app.contractor_id()) and t.deleted_at is null));
create policy tcw_staff_write on task_contractor_workers for all to authenticated
  using ((select app.is_admin()) or app.has_permission('contractors','edit'))
  with check ((select app.is_admin()) or app.has_permission('contractors','edit'));
create policy tcw_contractor_insert on task_contractor_workers for insert to authenticated
  with check (
    exists (select 1 from tasks t where t.id = task_id
            and t.contractor_id = (select app.contractor_id()) and t.deleted_at is null)
    and exists (select 1 from contractor_workers cw
                where cw.id = contractor_worker_id
                  and cw.contractor_id = (select app.contractor_id())
                  and cw.deleted_at is null));
create policy tcw_contractor_delete on task_contractor_workers for delete to authenticated
  using (
    exists (select 1 from tasks t where t.id = task_id
            and t.contractor_id = (select app.contractor_id()) and t.deleted_at is null));

-- ===== task_contractor_terms (money — invisible to workers/customers) =====
create policy tct_select on task_contractor_terms for select to authenticated using (
  (select app.is_admin())
  or ((select app.user_kind()) = 'staff' and app.has_permission('contractors','view'))
  or contractor_id = (select app.contractor_id()));
create policy tct_write on task_contractor_terms for all to authenticated
  using ((select app.is_admin()) or app.has_permission('contractors','edit'))
  with check ((select app.is_admin()) or app.has_permission('contractors','edit'));

-- ===== permissions tables: admin only (clients read via get_my_permissions RPC) =====
create policy pd_admin on permission_defaults for all to authenticated
  using ((select app.is_admin())) with check ((select app.is_admin()));
create policy up_admin on user_permissions for all to authenticated
  using ((select app.is_admin()) or app.has_permission('users','edit'))
  with check ((select app.is_admin()) or app.has_permission('users','edit'));
create policy fp_admin on field_permissions for all to authenticated
  using ((select app.is_admin()) or app.has_permission('users','edit'))
  with check ((select app.is_admin()) or app.has_permission('users','edit'));

-- ===== saved_filters / notifications / audit_log =====
create policy sf_own on saved_filters for all to authenticated
  using (profile_id = (select app.profile_id()))
  with check (profile_id = (select app.profile_id()));
create policy notif_select on notifications for select to authenticated
  using (recipient_id = (select app.profile_id()));
create policy notif_update on notifications for update to authenticated
  using (recipient_id = (select app.profile_id()))
  with check (recipient_id = (select app.profile_id()));
create policy audit_admin on audit_log for select to authenticated
  using ((select app.is_admin()));

-- ===== work board view =====
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
  coalesce(t.location_text, e.location_text) as location_text,
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
  tr.name as truck_name,
  t.truck_free_text,
  t.notes,
  t.status_id,
  s.name  as status_name,
  s.color as status_color,
  s.is_terminal as status_is_terminal,
  t.contractor_id,
  ct.name as contractor_name,
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
