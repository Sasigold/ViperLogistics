-- 0123: אירוע שנמחק יורד מהלו״ז, וסטטוס "בוטל" יורד עם המחיקה
--
-- שני באגים באותו אזור:
--
-- **א. אירוע שנמחק נשאר בלו״ז.** ‏0062 סינן משימה שנמחקה (`t.deleted_at`), אבל
-- ‏`soft_delete('events', …)` מסמן את האירוע בלבד ואינו מדרדר ל-tasks, ו-
-- ‏`work_board_view` לא בדק `e.deleted_at` כלל. התוצאה: משימות של אירוע מחוק
-- ממשיכות להופיע על הלוח. הפתרון: `and e.deleted_at is null` ב-view. ‏`e`
-- מגיע ב-left join, ולכן משימה עצמאית (בלי אירוע) נשארת — `e.deleted_at`
-- שלה NULL.
--
-- **ב. אירוע מבוטל שנמחק נשאר "מבוטל".** ‏soft_delete כותב `deleted_at` בלבד
-- ואינו נוגע בסטטוס. אירוע שבוטל ואז נמחק המשיך להצביע על "בוטל" — וכשמשחזרים
-- אותו מסל המיחזור הוא חוזר מבוטל. הכוונה: מחיקה מנקה את הביטול, וכשמשחזרים
-- האירוע חוזר כ"טרם אושר" (ברירת המחדל). טריגר `before update of deleted_at`.

-- ===== א+ב: הביטול יורד במחיקה ============================================
create or replace function app.event_delete_clears_cancelled()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_default uuid;
begin
  -- רק בכיוון המחיקה (NULL → ערך), וכשהסטטוס הוא "בוטל".
  if old.deleted_at is null and new.deleted_at is not null
     and exists (select 1 from statuses s where s.id = new.status_id and s.code = 'cancelled') then
    select id into v_default from statuses
      where entity = 'event' and is_default and deleted_at is null limit 1;
    if v_default is null then
      select id into v_default from statuses
        where entity = 'event' and code = 'pending' and deleted_at is null limit 1;
    end if;
    new.status_id := v_default;
  end if;
  return new;
end $$;

create trigger events_delete_clears_cancelled before update of deleted_at on events
  for each row execute function app.event_delete_clears_cancelled();

comment on function app.event_delete_clears_cancelled() is
  'מחיקת אירוע מבוטל מנקה את סטטוס "בוטל" לברירת המחדל (0123), כדי שאירוע '
  'מחוק לא ייספר כמבוטל וישוחזר מבוטל.';

-- ===== א: הלו״ז מסנן גם אירוע שנמחק =======================================
-- הגוף זהה ל-0121 (0099 + performed_by + תפקיד עובד הקבלן), והשינוי היחיד
-- הוא `and e.deleted_at is null` ב-where.
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
  case when (select app.has('contractors.view_pricing'))
       then case when (select app.contractor_id()) is not null then ctmine.price
                 else ctall.total_price end end as contractor_price,
  case when (select app.has('contractors.view_pricing')) then ctmine.price_per_worker end as contractor_price_per_worker,
  ctmine.work_site as contractor_work_site,
  ctmine.contractor_worker_count as contractor_worker_count,
  ctall.list as contractor_list,
  t.performed_by
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
left join lateral (
  select
    jsonb_agg(jsonb_build_object(
      'contractor_id', tct.contractor_id,
      'name', ctx.name,
      'price', case when (select app.has('contractors.view_pricing')) then tct.price end,
      'price_per_worker', case when (select app.has('contractors.view_pricing')) then tct.price_per_worker end,
      'work_site', tct.work_site,
      'worker_count', tct.contractor_worker_count)
      order by tct.created_at, tct.contractor_id) as list,
    sum(tct.price) as total_price
  from task_contractor_terms tct
  join contractors ctx on ctx.id = tct.contractor_id
  where tct.task_id = t.id
) ctall on true
left join lateral (
  select tct.* from task_contractor_terms tct
  where tct.task_id = t.id
    and tct.contractor_id = coalesce((select app.contractor_id()), t.contractor_id)
  limit 1
) ctmine on true
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
                                      'contractor_id', cw.contractor_id,
                                      'work_site', tcw.work_site,
                                      'role', tcw.role)
                   order by cw.full_name) as list
  from task_contractor_workers tcw join contractor_workers cw on cw.id = tcw.contractor_worker_id
  where tcw.task_id = t.id
) cworkers on true
left join lateral (
  select jsonb_agg(jsonb_build_object('id', tr3.id, 'name', tr3.name) order by u.ord) as list
  from unnest(t.truck_ids) with ordinality as u(truck_id, ord)
  join trucks tr3 on tr3.id = u.truck_id
) tlist on true
where t.deleted_at is null and e.deleted_at is null;
