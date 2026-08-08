-- 0037: אירוע שבוטל יורד מהלו״ז
--
-- הבדיקה נשענת על `statuses.code = 'cancelled'` שנקבע ב-0036, ולא על השם
-- (ניתן לעריכה בהגדרות) ולא על `is_terminal` (נכון גם ל"הושלם", והתכלית כאן
-- היא בדיוק ההבדל ביניהם: אירוע שהושלם הוא היסטוריה שראוי לראות, אירוע
-- שבוטל הוא עבודה שלא תתבצע). אותה זהות שלוח השנה כבר מסתיר לפיה, כדי
-- ששני המסכים לא יחלקו על מה נחשב מבוטל.
--
-- העמודה נוספת ל-work_board_view ולא נאכפת בפוליסה: המשימות עצמן לא נמחקו,
-- ועמוד האירוע ויומן הפעילות ממשיכים להציג אותן. הלוח הוא שמסנן.

-- אותה רשימת עמודות של 0035, בתוספת עמודה אחת בסוף
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
  coalesce(es.code = 'cancelled', false) as event_is_cancelled
from tasks t
left join events e     on e.id = t.event_id
left join customers c  on c.id = t.customer_id
join task_types tt     on tt.id = t.task_type_id
left join execution_methods em on em.id = t.execution_method_id
left join trucks tr    on tr.id = t.truck_id
join statuses s        on s.id = t.status_id
left join contractors ct on ct.id = t.contractor_id
left join statuses es  on es.id = e.status_id
left join task_pricing tp on tp.task_id = t.id
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
-- הרשימה נשלפת בסדר של המערך ולא לפי שם: האיבר הראשון הוא המשאית הראשית,
-- וזו הבחנה שהמסך מציג
left join lateral (
  select jsonb_agg(jsonb_build_object('id', tr3.id, 'name', tr3.name) order by u.ord) as list
  from unnest(t.truck_ids) with ordinality as u(truck_id, ord)
  join trucks tr3 on tr3.id = u.truck_id
) tlist on true;

-- ניקוי: גרסה מוקדמת של השינוי הזה הוסיפה דגל משלה. `code` קדם לה ומכסה
-- אותה, ושתי אמיתות לאותה שאלה הן אחת יותר מדי.
alter table statuses drop column if exists is_cancelled;
