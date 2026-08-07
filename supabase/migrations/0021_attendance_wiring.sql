-- 0021: חיבור מודול הנוכחות למה שכבר קיים
--
-- שני דברים שלא שייכים ל-0019 (סכמה) ולא ל-0020 (מנוע): הענקת המפתחות
-- לתפקידי המערכת, והוספת שטח/מחסן לתצוגת לוח העבודה.

-- ===== 1. תפקידי המערכת ====================================================
-- app.set_role_permissions מוחקת את *כל* הרשאות התפקיד לפני שהיא כותבת
-- (0010), ותפקידים כמו worker ו-driver הוגדרו ב-0011 עם p_close_modules
-- שכותב דחיות מפורשות. הרצה חוזרת שלה כאן הייתה מוחקת אותן. לכן הוספה
-- נקודתית, ולא הגדרה מחדש.

-- מנהלי תפעול ומשאבי אנוש מקבלים את המודול כולו — כך הוא נשאר שלם גם
-- כשייווספו לו מפתחות בעתיד.
select app.grant_role_module('ops_manager', 'attendance');
select app.grant_role_module('hr', 'attendance');

-- כספים: הצד הכספי בלבד, בלי עריכת החתמות.
insert into role_permissions (role_id, permission_key, allowed)
select r.id, k, true
from permission_roles r,
     unnest(array['attendance.view_own', 'attendance.view_schedule', 'attendance.clock',
                  'attendance.view_own_pay', 'attendance.view_all', 'attendance.view_pay',
                  'attendance.manage_pay', 'attendance.settings', 'attendance.export']) k
where r.key = 'finance'
on conflict (role_id, permission_key) do update set allowed = true;

-- מבצעים: השעון והמשמרות שלהם בלבד.
insert into role_permissions (role_id, permission_key, allowed)
select r.id, k, true
from permission_roles r,
     unnest(array['attendance.view_own', 'attendance.view_schedule',
                  'attendance.clock', 'attendance.view_own_pay']) k
where r.key in ('worker', 'driver', 'team_lead')
on conflict (role_id, permission_key) do update set allowed = true;

-- צופה: שעות בלי כסף — בדיוק ההפרדה שבגללה שני המפתחות אינם נגזרים זה מזה.
insert into role_permissions (role_id, permission_key, allowed)
select r.id, k, true
from permission_roles r,
     unnest(array['attendance.view_own', 'attendance.view_schedule', 'attendance.view_all']) k
where r.key = 'viewer'
on conflict (role_id, permission_key) do update set allowed = true;

-- מנהל הקבלן: דוח הנוכחות של הסגל שלו, בלי הסכומים עד שיוחלט אחרת.
insert into role_permissions (role_id, permission_key, allowed)
select r.id, 'portal.attendance', true
from permission_roles r where r.key = 'contractor_manager'
on conflict (role_id, permission_key) do update set allowed = true;

-- ===== 2. שטח/מחסן בלוח העבודה =============================================
-- work_board_view הוא נתיב הקריאה היחיד של הלוח, של דף האירוע ושל הפורטל.
-- ההגדרה מועתקת מ-0017 עם תוספת אחת: work_site בתוך כל אובייקט משובץ, כדי
-- שהלוח יוכל להראות מי יוצא מהמחסן בלי שאילתה נוספת.

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
  t.requires_team_lead
from tasks t
left join events e     on e.id = t.event_id
left join customers c  on c.id = t.customer_id
join task_types tt     on tt.id = t.task_type_id
left join execution_methods em on em.id = t.execution_method_id
left join trucks tr    on tr.id = t.truck_id
join statuses s        on s.id = t.status_id
left join contractors ct on ct.id = t.contractor_id
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
where t.deleted_at is null;
