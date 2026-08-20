-- 0095: כפתור אי-התייצבות למנהל, וכמות העובדים של הקבלן בלו״ז
--
--   * `contractor_mark_no_show` — סימון/ביטול אי-התייצבות של עובד קבלן, למנהל
--     המערכת או למי שמנהל קבלנים (contractors.assign_workers). הכתיבה עוברת
--     ב-RPC כי אין לטבלה פוליסת UPDATE לעובד, והטריגר tcw_noshow_sync מחשב
--     מחדש את מחיר הקבלן.
--   * work_board_view מחזיר גם את `contractor_worker_count` — כמה עובדים הקבלן
--     צריך להביא — כדי שהלו״ז יציג לו שורה נפרדת מכמות המשימה.

create or replace function contractor_mark_no_show(
  p_task_id uuid, p_worker_id uuid, p_on boolean default true)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not (app.is_admin() or app.has('contractors.assign_workers')) then
    raise exception 'אין לך הרשאה לסמן אי-התייצבות' using errcode = '42501';
  end if;
  perform app.system_write(true);
  update task_contractor_workers set no_show = p_on
   where task_id = p_task_id and contractor_worker_id = p_worker_id;
  perform app.system_write(false);
end $$;

revoke execute on function public.contractor_mark_no_show(uuid, uuid, boolean) from anon, public;

comment on function public.contractor_mark_no_show(uuid, uuid, boolean) is
  'סימון/ביטול אי-התייצבות של עובד קבלן במשימה (0095). מפעיל את קנס אי-ההתייצבות.';

-- work_board_view + contractor_worker_count (עמודה בקצה, כי create or replace view
-- מוסיף עמודות רק בסוף). שאר ההגדרה זהה ל-0091.
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
  cworkers.list as contractor_worker_list,
  case when (select app.has('pricing.view')) then tp.price end as customer_price,
  case when (select app.has('pricing.view')) then tp.is_manual end as price_is_manual,
  case when (select app.has('pricing.view')) then tp.breakdown end as price_breakdown,
  t.travel_hours,
  t.requires_team_lead,
  case when (select app.can_view_field('task', 'truck_ids')) then t.truck_ids end as truck_ids,
  case when (select app.can_view_field('task', 'truck_ids')) then tlist.list end as truck_list,
  coalesce(es.code = 'cancelled', false) as event_is_cancelled,
  s.code as status_code,
  case when (select app.has('contractors.view_pricing')) then tct.price end as contractor_price,
  case when (select app.has('contractors.view_pricing')) then tct.price_per_worker end as contractor_price_per_worker,
  tct.work_site as contractor_work_site,
  tct.contractor_worker_count as contractor_worker_count
from tasks t
left join events e     on e.id = t.event_id
left join app.customer_identities c on c.id = t.customer_id
join task_types tt     on tt.id = t.task_type_id
left join execution_methods em on em.id = t.execution_method_id
left join trucks tr    on tr.id = t.truck_id
join statuses s        on s.id = t.status_id
left join contractors ct on ct.id = t.contractor_id
left join statuses es  on es.id = e.status_id
left join task_pricing tp on tp.task_id = t.id
left join task_contractor_terms tct on tct.task_id = t.id
left join lateral (
  select a.profile_id from task_assignments a
  where a.task_id = t.id and a.role = 'team_lead' limit 1
) lead_a on true
left join profiles lead_p on lead_p.id = lead_a.profile_id
left join lateral (
  select jsonb_agg(jsonb_build_object('profile_id', a.profile_id, 'name', p.full_name,
                                      'work_site', a.work_site)
                   order by p.full_name) as list
  from task_assignments a join profiles p on p.id = a.profile_id
  where a.task_id = t.id and a.role = 'worker'
) workers on true
left join lateral (
  select jsonb_agg(jsonb_build_object('profile_id', a.profile_id, 'name', p.full_name,
                                      'truck_id', a.truck_id, 'truck_name', tr2.name,
                                      'work_site', a.work_site)
                   order by p.full_name) as list
  from task_assignments a
  join profiles p on p.id = a.profile_id
  left join trucks tr2 on tr2.id = a.truck_id
  where a.task_id = t.id and a.role = 'driver'
) drivers on true
left join lateral (
  select jsonb_agg(jsonb_build_object('id', cw.id, 'name', cw.full_name,
                                      'work_site', tcw.work_site)
                   order by cw.full_name) as list
  from task_contractor_workers tcw join contractor_workers cw on cw.id = tcw.contractor_worker_id
  where tcw.task_id = t.id
) cworkers on true
left join lateral (
  select jsonb_agg(jsonb_build_object('id', tr3.id, 'name', tr3.name) order by u.ord) as list
  from unnest(t.truck_ids) with ordinality as u(truck_id, ord)
  join trucks tr3 on tr3.id = u.truck_id
) tlist on true
where t.deleted_at is null;
