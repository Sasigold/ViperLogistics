\pset tuples_only on
\pset format unaligned

-- ===========================================================================
-- ‏65: מה שמגדירים הוא מה שרואים (0214).
--
-- החבילה מקימה שני לקוחות, שני קבלנים, שלושה אירועים וארבע משימות משלה
-- ב-`current_date + 1130`, מעבר לכל טווח אחר, ושלוש־עשרה דמויות — אחת לכל
-- סוג משתמש ותפקיד שמשתתף בהחלטה. כל בדיקה רצה **בזהות** הדמות
-- (`set role authenticated`), כי בזהות superuser הרשאות ו-RLS אינן נשאלות.
--
--   לקוח א (ארקו 65) — אירועים א1, א2. לקוח ב — אירוע ב1.
--   משימה א1 (הקמה, מפורסמת)  — הואצלה לקבלן 1; שובצו בה: עובד השטח, עובד
--                                קבלן 1, עובד הלקוח.
--   משימה א1-טיוטה (פירוק)     — עובד השטח שובץ בה; טרם פורסמה.
--   משימה א2 (הקמה, מפורסמת)  — הואצלה לקבלן 2.
--   משימה ב1 (הקמה, מפורסמת)  — של לקוח ב, לא הואצלה.
--
--   65a1 משרד (רכז שיבוצים + מחירים + תמחור קבלנים + צפייה בעובדים)
--   65a2 עובד שטח (תפקיד "עובד": רק מה שמשויך אליו) + צפייה במחירים
--   65a3 עובד שהוא גם קבלן 1 (עובד + "קבלן — בנוסף לתפקיד")
--   65a4 עובד שקיבל "הגדרות שעון פר-עובד" — כמו התפקיד "עובד" במסד החי
--   65a5 משאבי אנוש (שכר)        65a6 מנהל מערכת
--   65b1 מנהל אצל לקוח א         65b2 צופה אצל לקוח א
--   65b3 עובד בסגל לקוח א (תפקיד "עובד אצל הלקוח" — own)
--   65b4 מנהל אצל לקוח ב         65b5 משתמש לקוח א שנחסמה לו צפייה באירועים ובמשימות
--   65c1 מנהל קבלן 1             65c2 עובד קבלן 1
--   65c3 מנהל קבלן 2             65c4 משתמש קבלן 2 בלי תפקיד (רק ברירות המחדל)
-- ===========================================================================

insert into auth.users (id, email)
select ('00000000-0000-0000-0000-0000000065' || s)::uuid, 'p65-' || s || '@vl.test'
  from unnest(array['a1','a2','a3','a4','a5','a6','b1','b2','b3','b4','b5','c1','c2','c3','c4']) s;

insert into customers (id, name, performed_by_enabled, quote_enabled) values
  ('10000000-0000-0000-0000-0000000065a0', 'ארקו 65', true, true),
  ('10000000-0000-0000-0000-0000000065b0', 'לקוח ב 65', false, true);

insert into contractors (id, name) values
  ('40000000-0000-0000-0000-0000000065c1', 'קבלן 1 65'),
  ('40000000-0000-0000-0000-0000000065c2', 'קבלן 2 65');

insert into contractor_workers (id, contractor_id, full_name, phone) values
  ('50000000-0000-0000-0000-0000000065d1', '40000000-0000-0000-0000-0000000065c1', 'עובד קבלן 1 65', '050-6500001'),
  ('50000000-0000-0000-0000-0000000065d2', '40000000-0000-0000-0000-0000000065c1', 'עובד נוסף קבלן 1 65', '050-6500002'),
  ('50000000-0000-0000-0000-0000000065d3', '40000000-0000-0000-0000-0000000065c2', 'עובד קבלן 2 65', '050-6500003');

insert into customer_workers (id, customer_id, full_name) values
  ('cf000000-0000-0000-0000-0000006500a1', '10000000-0000-0000-0000-0000000065a0', 'עובד ארקו 65');

insert into profiles (id, user_id, user_kind, is_admin, full_name, customer_id, contractor_id) values
  ('20000000-0000-0000-0000-0000000065a1', '00000000-0000-0000-0000-0000000065a1', 'staff', false, 'משרד 65', null, null),
  ('20000000-0000-0000-0000-0000000065a2', '00000000-0000-0000-0000-0000000065a2', 'staff', false, 'עובד שטח 65', null, null),
  ('20000000-0000-0000-0000-0000000065a3', '00000000-0000-0000-0000-0000000065a3', 'staff', false, 'עובד-קבלן 65', null, '40000000-0000-0000-0000-0000000065c1'),
  ('20000000-0000-0000-0000-0000000065a4', '00000000-0000-0000-0000-0000000065a4', 'staff', false, 'עובד עם שעון 65', null, null),
  ('20000000-0000-0000-0000-0000000065a5', '00000000-0000-0000-0000-0000000065a5', 'staff', false, 'משאבי אנוש 65', null, null),
  ('20000000-0000-0000-0000-0000000065a6', '00000000-0000-0000-0000-0000000065a6', 'staff', true,  'מנהל 65', null, null),
  ('20000000-0000-0000-0000-0000000065b1', '00000000-0000-0000-0000-0000000065b1', 'customer_user', false, 'מנהל ארקו 65', '10000000-0000-0000-0000-0000000065a0', null),
  ('20000000-0000-0000-0000-0000000065b2', '00000000-0000-0000-0000-0000000065b2', 'customer_user', false, 'צופה ארקו 65', '10000000-0000-0000-0000-0000000065a0', null),
  ('20000000-0000-0000-0000-0000000065b3', '00000000-0000-0000-0000-0000000065b3', 'customer_user', false, 'עובד ארקו 65', '10000000-0000-0000-0000-0000000065a0', null),
  ('20000000-0000-0000-0000-0000000065b4', '00000000-0000-0000-0000-0000000065b4', 'customer_user', false, 'מנהל לקוח ב 65', '10000000-0000-0000-0000-0000000065b0', null),
  ('20000000-0000-0000-0000-0000000065b5', '00000000-0000-0000-0000-0000000065b5', 'customer_user', false, 'חסום ארקו 65', '10000000-0000-0000-0000-0000000065a0', null),
  ('20000000-0000-0000-0000-0000000065c1', '00000000-0000-0000-0000-0000000065c1', 'contractor_user', false, 'מנהל קבלן 1 65', null, '40000000-0000-0000-0000-0000000065c1'),
  ('20000000-0000-0000-0000-0000000065c2', '00000000-0000-0000-0000-0000000065c2', 'contractor_user', false, 'עובד קבלן 1 65', null, '40000000-0000-0000-0000-0000000065c1'),
  ('20000000-0000-0000-0000-0000000065c3', '00000000-0000-0000-0000-0000000065c3', 'contractor_user', false, 'מנהל קבלן 2 65', null, '40000000-0000-0000-0000-0000000065c2'),
  ('20000000-0000-0000-0000-0000000065c4', '00000000-0000-0000-0000-0000000065c4', 'contractor_user', false, 'קבלן 2 בלי תפקיד 65', null, '40000000-0000-0000-0000-0000000065c2');

update profiles set customer_worker_id = 'cf000000-0000-0000-0000-0000006500a1'
 where id = '20000000-0000-0000-0000-0000000065b3';
update profiles set contractor_worker_id = '50000000-0000-0000-0000-0000000065d1'
 where id = '20000000-0000-0000-0000-0000000065c2';

insert into profile_roles (profile_id, role_id)
select v.p::uuid, r.id
  from (values
    ('20000000-0000-0000-0000-0000000065a1', 'dispatcher'),
    ('20000000-0000-0000-0000-0000000065a2', 'worker'),
    ('20000000-0000-0000-0000-0000000065a3', 'worker'),
    ('20000000-0000-0000-0000-0000000065a3', 'staff_contractor'),
    ('20000000-0000-0000-0000-0000000065a4', 'worker'),
    ('20000000-0000-0000-0000-0000000065a5', 'hr'),
    ('20000000-0000-0000-0000-0000000065b1', 'customer_manager'),
    ('20000000-0000-0000-0000-0000000065b2', 'customer_viewer'),
    ('20000000-0000-0000-0000-0000000065b3', 'customer_worker'),
    ('20000000-0000-0000-0000-0000000065b4', 'customer_manager'),
    ('20000000-0000-0000-0000-0000000065b5', 'customer_viewer'),
    ('20000000-0000-0000-0000-0000000065c1', 'contractor_manager'),
    ('20000000-0000-0000-0000-0000000065c2', 'contractor_worker'),
    ('20000000-0000-0000-0000-0000000065c3', 'contractor_manager')) v(p, k)
  join permission_roles r on r.key = v.k;

insert into user_permission_grants (profile_id, permission_key, allowed) values
  ('20000000-0000-0000-0000-0000000065a1', 'pricing.view', true),
  ('20000000-0000-0000-0000-0000000065a1', 'contractors.view_pricing', true),
  ('20000000-0000-0000-0000-0000000065a2', 'pricing.view', true),
  ('20000000-0000-0000-0000-0000000065a4', 'attendance.manage_clock', true),
  ('20000000-0000-0000-0000-0000000065b1', 'users.view', true),
  ('20000000-0000-0000-0000-0000000065b5', 'events.view', false),
  ('20000000-0000-0000-0000-0000000065b5', 'tasks.view', false),
  -- זה מה שמנהל מערכת מעניק כשהוא רוצה שמנהל אצל לקוח ייצא אירועים — והמפתח
  -- חל על צוות בלבד. ההענקה נכתבת ישירות (כמו מיגרציה), לא דרך המסך.
  ('20000000-0000-0000-0000-0000000065b2', 'events.export', true)
on conflict (profile_id, permission_key) do update set allowed = excluded.allowed;

-- האירועים נפתחים בלי המשימות האוטומטיות של 0009, כדי שכל משימה כאן תהיה
-- בדיוק זו שהחבילה בנתה.
alter table events disable trigger events_default_tasks;
insert into events (id, customer_id, end_client_name, event_number, event_date)
values
  ('30000000-0000-0000-0000-0000000065e1', '10000000-0000-0000-0000-0000000065a0', 'אירוע א1 65', 'EV-65-A1', current_date + 1130),
  ('30000000-0000-0000-0000-0000000065e2', '10000000-0000-0000-0000-0000000065a0', 'אירוע א2 65', 'EV-65-A2', current_date + 1131),
  ('30000000-0000-0000-0000-0000000065e3', '10000000-0000-0000-0000-0000000065b0', 'אירוע ב1 65', 'EV-65-B1', current_date + 1132);
alter table events enable trigger events_default_tasks;

insert into tasks (id, event_id, customer_id, task_type_id, task_date, onsite_start_time, hours_count, status_id, worker_count)
select v.id::uuid, v.ev::uuid, v.cust::uuid,
       (select id from task_types where code = v.tt limit 1),
       current_date + v.d, '10:00', 2,
       (select id from statuses where entity = 'task' and code = v.st and deleted_at is null),
       3
  from (values
    ('62000000-0000-0000-0000-0000000065f1', '30000000-0000-0000-0000-0000000065e1', '10000000-0000-0000-0000-0000000065a0', 'setup',    1130, 'assigned'),
    ('62000000-0000-0000-0000-0000000065f4', '30000000-0000-0000-0000-0000000065e1', '10000000-0000-0000-0000-0000000065a0', 'teardown', 1130, 'draft'),
    ('62000000-0000-0000-0000-0000000065f2', '30000000-0000-0000-0000-0000000065e2', '10000000-0000-0000-0000-0000000065a0', 'setup',    1131, 'assigned'),
    ('62000000-0000-0000-0000-0000000065f3', '30000000-0000-0000-0000-0000000065e3', '10000000-0000-0000-0000-0000000065b0', 'setup',    1132, 'assigned')
  ) v(id, ev, cust, tt, d, st);

insert into task_pricing (task_id, price, is_manual)
select id, 1000, true from tasks where id::text like '62000000-0000-0000-0000-0000000065f%'
on conflict (task_id) do update set price = excluded.price, is_manual = true;

insert into task_contractor_terms (task_id, contractor_id, price) values
  ('62000000-0000-0000-0000-0000000065f1', '40000000-0000-0000-0000-0000000065c1', 500),
  ('62000000-0000-0000-0000-0000000065f2', '40000000-0000-0000-0000-0000000065c2', 700);

insert into task_assignments (task_id, profile_id, role, work_site) values
  ('62000000-0000-0000-0000-0000000065f1', '20000000-0000-0000-0000-0000000065a2', 'worker', 'field'),
  ('62000000-0000-0000-0000-0000000065f4', '20000000-0000-0000-0000-0000000065a2', 'worker', 'field');

insert into task_contractor_workers (task_id, contractor_worker_id, work_site) values
  ('62000000-0000-0000-0000-0000000065f1', '50000000-0000-0000-0000-0000000065d1', 'field'),
  ('62000000-0000-0000-0000-0000000065f2', '50000000-0000-0000-0000-0000000065d3', 'field');

insert into task_customer_workers (task_id, customer_worker_id, work_site) values
  ('62000000-0000-0000-0000-0000000065f1', 'cf000000-0000-0000-0000-0000006500a1', 'field');

insert into worker_pay_settings (profile_id, hourly_rate, shift_bonus, team_lead_bonus) values
  ('20000000-0000-0000-0000-0000000065a2', 50, 10, 20),
  ('20000000-0000-0000-0000-0000000065a4', 60, 0, 0)
on conflict (profile_id) do update set hourly_rate = excluded.hourly_rate,
  shift_bonus = excluded.shift_bonus, team_lead_bonus = excluded.team_lead_bonus;

-- מה שכל אחד רואה, בשורה אחת: האירועים והמשימות של החבילה בלבד
create or replace function t65_seen(p_what text) returns text
language sql stable as $$
  select coalesce(string_agg(x, ',' order by x), '-') from (
    select e.event_number as x from events e
     where p_what = 'events' and e.event_number like 'EV-65-%'
    union all
    select right(t.id::text, 2) from tasks t
     where p_what = 'tasks' and t.id::text like '62000000-0000-0000-0000-0000000065f%'
    union all
    select right(tp.task_id::text, 2) from task_pricing tp
     where p_what = 'prices' and tp.task_id::text like '62000000-0000-0000-0000-0000000065f%'
    union all
    select (select c.name from contractors c where c.id = tct.contractor_id)
      from task_contractor_terms tct
     where p_what = 'terms' and tct.task_id::text like '62000000-0000-0000-0000-0000000065f%'
  ) s
$$;
grant execute on function t65_seen(text) to authenticated;

create or replace function t65_as(p text) returns void language sql as $$
  select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000065' || p, false);
$$;
grant execute on function t65_as(text) to authenticated;

-- ===== 1. מפתח שאינו חל על סוג המשתמש אינו מוענק =========================

\echo '--- 1. applies_to: מה שהמטריצה אינה מציגה, גם אינו מוענק ---'
set role authenticated;

select t65_as('b1');
select t_eq('מנהל אצל לקוח עורך אירועים', app.has('events.edit'), true);
select t_eq('ולכן ירש "הפקה ושליחה של הצעת מחיר" — עד 0214. עכשיו לא: המפתח של צוות',
  app.has('events.quote_send'), false);
select t_eq('ולא "הסתרת משימה מהלו״ז"', app.has('board.hide_task'), false);
select t_expect_fail('והצעת מחיר בשם וייפר אינה נכנסת ממנו גם ישירות לטבלה',
  $$insert into event_quotes (event_id, version, document_number, storage_path, file_name,
                              subtotal, vat_pct, vat_amount, total)
    values ('30000000-0000-0000-0000-0000000065e1', 99, 'FORGED-65', 'x/y.pdf', 'y.pdf', 1, 18, 0, 1)$$);

select t65_as('b2');
select t_eq('הענקה אישית של מפתח צוות ללקוח אינה פותחת אותו (ייצוא אירועים)',
  app.has('events.export'), false);

select t65_as('c2');
select t_eq('עובד קבלן רואה את הלו״ז — המפתח חל עכשיו על קבלן', app.has('board.view'), true);
select t_eq('ואת לוח השנה', app.has('calendar.view'), true);
select t_eq('ואת עמודות הצוות', app.has('board.view_staffing'), true);
select t_eq('אבל לא את ניהול הסגל של המשרד', app.has('contractors.manage_workers'), false);

select t65_as('c4');
select t_eq('גם משתמש קבלן בלי תפקיד — ברירת המחדל של הקהל אינה פותחת מפתח משרד',
  app.has('contractors.manage_workers'), false);

select t65_as('a3');
select t_eq('עובד שהוא גם קבלן מחזיק את הפורטל — המפתח חל עכשיו גם על צוות',
  app.has('portal.view'), true);

select t65_as('a2');
select t_eq('עובד שטח פותח את הלו״ז, ובכל זאת אינו מסתיר משימות (0188: "אינו ניתן כברירת מחדל לאיש")',
  app.has('board.hide_task'), false);

reset role;
select t_eq('הבבואה לכל המשתמשים (נמענים של התראות) אומרת אותו דבר',
  (select count(*)::int from app.profiles_with('events.quote_send') p
    where p = '20000000-0000-0000-0000-0000000065b1'), 0);
select t_eq('ומחזירה את עובד-הקבלן לפורטל',
  (select count(*)::int from app.profiles_with('portal.view') p
    where p = '20000000-0000-0000-0000-0000000065a3'), 1);

-- ===== 2. הגבלת נתונים מצמצמת, ואינה פותחת ===============================

\echo '--- 2. היקפים: הגבלה אישית אינה מבטלת את ה-own של התפקיד ---'
set role authenticated;

select t65_as('b3');
select t_eq('עובד בסגל הלקוח רואה רק את האירוע ששובץ אליו', t65_seen('events'), 'EV-65-A1');
select t_eq('ורק את המשימה ששובץ אליה', t65_seen('tasks'), 'f1');

reset role;
-- חלון תאריכים אישי — הדבר שעד 0214 ביטל את "רק מה שמשויך אליי"
insert into permission_scopes (profile_id, resource, scope_type, days_back, days_forward)
values ('20000000-0000-0000-0000-0000000065b3', 'events', 'date_window', 10, 2000);
set role authenticated;
select t65_as('b3');
select t_eq('חלון תאריכים אישי נוסף — ועדיין רק מה ששובץ אליו (עד 0214: כל האירועים של הלקוח)',
  t65_seen('events'), 'EV-65-A1');

reset role;
-- ‏"ללא הגבלה" אישית — זה מה שנכתב לאוראל במסד החי
insert into permission_scopes (profile_id, resource, scope_type)
values ('20000000-0000-0000-0000-0000000065b3', 'events', 'all');
set role authenticated;
select t65_as('b3');
select t_eq('"ללא הגבלה" אישית מבטלת במפורש את ה-own — ורואים את כל האירועים של הלקוח',
  t65_seen('events'), 'EV-65-A1,EV-65-A2');
select t_eq('ואף פעם לא של לקוח אחר', position('EV-65-B1' in t65_seen('events')), 0);
select t_eq('ו-get_my_permissions מחזיר את ההיקף כפי שהוא חל',
  (select string_agg(s ->> 'scope_type', ',' order by s ->> 'scope_type')
     from jsonb_array_elements(get_my_permissions() -> 'scopes') s
    where s ->> 'resource' = 'events'), 'all');

reset role;
delete from permission_scopes where profile_id = '20000000-0000-0000-0000-0000000065b3';

-- הגבלת "לקוחות" שנוספה ועוד לא נבחר בה לקוח
insert into permission_scopes (profile_id, resource, scope_type, scope_values)
values ('20000000-0000-0000-0000-0000000065a1', 'tasks', 'customers', '{}');
set role authenticated;
select t65_as('a1');
select t_eq('רשימת לקוחות ריקה סוגרת (עד 0214: פתחה את כל הלקוחות)', t65_seen('tasks'), '-');
reset role;
update permission_scopes set scope_values = array['10000000-0000-0000-0000-0000000065b0'::uuid]
 where profile_id = '20000000-0000-0000-0000-0000000065a1' and resource = 'tasks';
set role authenticated;
select t65_as('a1');
select t_eq('ומשנבחר לקוח — רק המשימות שלו', t65_seen('tasks'), 'f3');
reset role;
delete from permission_scopes where profile_id = '20000000-0000-0000-0000-0000000065a1';

-- ===== 3. "צפייה באירועים/משימות" נאכפת על לקוח ועל קבלן ================

\echo '--- 3. לקוח וקבלן: רק של עצמם, ורק מה שהמפתח מתיר ---'
set role authenticated;

select t65_as('b2');
select t_eq('צופה אצל לקוח א: שני האירועים של א', t65_seen('events'), 'EV-65-A1,EV-65-A2');
select t_eq('והמשימות של א, כולל הטיוטה (הלקוח מתכנן את שלו)', t65_seen('tasks'), 'f1,f2,f4');

select t65_as('b4');
select t_eq('מנהל אצל לקוח ב: רק האירוע של ב', t65_seen('events'), 'EV-65-B1');
select t_eq('ורק המשימה של ב', t65_seen('tasks'), 'f3');

select t65_as('b5');
select t_eq('משתמש לקוח שנחסמה לו "צפייה באירועים" — אינו רואה אף אירוע (עד 0214: את כולם)',
  t65_seen('events'), '-');
select t_eq('ולא משימות', t65_seen('tasks'), '-');
select t_eq('גם אם לוח השנה עצמו פתוח לו', app.has('calendar.view'), true);

select t65_as('c1');
select t_eq('מנהל קבלן 1: רק האירוע שיש בו משימה שהואצלה לו', t65_seen('events'), 'EV-65-A1');
select t_eq('ורק המשימה הזו', t65_seen('tasks'), 'f1');

select t65_as('c3');
select t_eq('מנהל קבלן 2: רק שלו', t65_seen('events'), 'EV-65-A2');

select t65_as('c2');
select t_eq('עובד קבלן 1: האירוע של המשימה ששובץ אליה', t65_seen('events'), 'EV-65-A1');
select t_eq('והמשימה', t65_seen('tasks'), 'f1');

reset role;
-- שורת שיבוץ של עובד קבלן 1 על משימה של קבלן 2 — מה שהתנאי הטאוטולוגי איפשר
insert into task_contractor_workers (task_id, contractor_worker_id, work_site)
values ('62000000-0000-0000-0000-0000000065f2', '50000000-0000-0000-0000-0000000065d1', 'field');
set role authenticated;
select t65_as('c2');
select t_eq('שיבוץ שאינו של הקבלן שלו אינו פותח את האירוע של קבלן אחר',
  t65_seen('events'), 'EV-65-A1');
reset role;
delete from task_contractor_workers
 where task_id = '62000000-0000-0000-0000-0000000065f2'
   and contractor_worker_id = '50000000-0000-0000-0000-0000000065d1';

set role authenticated;
select t65_as('a2');
select t_eq('עובד שטח: רק המשימה המפורסמת ששובץ אליה', t65_seen('tasks'), 'f1');
select t_eq('ורק האירוע שלה', t65_seen('events'), 'EV-65-A1');

-- ===== 4. התמחור והסגל של קבלן הם שלו =====================================

\echo '--- 4. קבלנים: התמחור, הסגל והשיבוץ ---'

select t65_as('a3');
select t_eq('עובד שהוא גם קבלן 1 רואה רק את התמחור של קבלן 1 (עד 0214: של כל הקבלנים)',
  t65_seen('terms'), 'קבלן 1 65');

select t65_as('a1');
select t_eq('המשרד, עם מפתח הצפייה בתמחור, רואה את שניהם', t65_seen('terms'), 'קבלן 1 65,קבלן 2 65');

select t65_as('c1');
select t_eq('מנהל קבלן 1 — את שלו', t65_seen('terms'), 'קבלן 1 65');

select t_expect_fail('מנהל קבלן 1 אינו משבץ את העובד שלו למשימה של קבלן 2',
  $$insert into task_contractor_workers (task_id, contractor_worker_id, work_site)
    values ('62000000-0000-0000-0000-0000000065f2', '50000000-0000-0000-0000-0000000065d2', 'field')$$);
select t_expect_fail('וגם לא למשימה של לקוח ב שלא הואצלה לאיש',
  $$insert into task_contractor_workers (task_id, contractor_worker_id, work_site)
    values ('62000000-0000-0000-0000-0000000065f3', '50000000-0000-0000-0000-0000000065d2', 'field')$$);
select t_expect_ok('אבל למשימה שהואצלה לו — כן',
  $$insert into task_contractor_workers (task_id, contractor_worker_id, work_site)
    values ('62000000-0000-0000-0000-0000000065f1', '50000000-0000-0000-0000-0000000065d2', 'field')$$);
select t_rows('ומחיקה בלי סינון מוחקת רק את השיבוצים של קבלן 1 (עד 0214: של כולם)',
  $$delete from task_contractor_workers$$, 2);

reset role;
select t_eq('השיבוץ של קבלן 2 נשאר במקומו',
  (select count(*)::int from task_contractor_workers
    where task_id = '62000000-0000-0000-0000-0000000065f2'
      and contractor_worker_id = '50000000-0000-0000-0000-0000000065d3'), 1);
-- מחזירים את השיבוץ של עובד קבלן 1 למשימה שלו
insert into task_contractor_workers (task_id, contractor_worker_id, work_site)
values ('62000000-0000-0000-0000-0000000065f1', '50000000-0000-0000-0000-0000000065d1', 'field')
on conflict do nothing;

set role authenticated;
select t65_as('c4');
select t_eq('משתמש קבלן 2 רואה רק את הסגל של קבלן 2 (עד 0214: של כל הקבלנים)',
  (select count(*)::int from contractor_workers
    where contractor_id = '40000000-0000-0000-0000-0000000065c1'), 0);
select t_rows('ואינו משנה עובד של קבלן 1',
  $$update contractor_workers set full_name = 'נחטף' where id = '50000000-0000-0000-0000-0000000065d2'$$, 0);
select t_expect_fail('ואינו מוסיף עובד לסגל של קבלן 1',
  $$insert into contractor_workers (contractor_id, full_name)
    values ('40000000-0000-0000-0000-0000000065c1', 'רוח רפאים')$$);
select t_expect_fail('ואינו מוחק עובד של קבלן 1 דרך soft_delete',
  $$select soft_delete('contractor_workers', '50000000-0000-0000-0000-0000000065d2')$$);

select t65_as('c2');
select t_expect_fail('עובד קבלן אינו כותב תפקידים לעובדי הסגל',
  $$insert into contractor_worker_roles (contractor_worker_id, role)
    values ('50000000-0000-0000-0000-0000000065d2', 'driver')$$);

-- ===== 5. מחיר משימה — רק על משימה שהקורא רואה ===========================

\echo '--- 5. מחירים ---'

select t65_as('a2');
select t_eq('עובד שטח עם "צפייה במחיר" רואה מחיר רק של מה ששובץ אליו (עד 0214: של כל המשימות)',
  t65_seen('prices'), 'f1');

select t65_as('a1');
select t_eq('המשרד, בלי הגבלה, רואה את כל המחירים', t65_seen('prices'), 'f1,f2,f3,f4');

select t65_as('b1');
select t_eq('מנהל אצל לקוח א רואה את המחירים של א בלבד', t65_seen('prices'), 'f1,f2,f4');

select t65_as('b2');
select t_eq('צופה בלי "צפייה במחיר" אינו רואה מחיר', t65_seen('prices'), '-');

-- ===== 6. השכר של עובד הוא של המשרד ========================================

\echo '--- 6. הגדרות שכר ושעון ---'

select t65_as('a4');
select t_eq('"הגדרות שעון פר-עובד" כבר אינו פותח את שורת השכר של אחר',
  (select count(*)::int from worker_pay_settings where profile_id <> app.profile_id()), 0);
select t_rows('ואינו משנה לאחר בונוס למשמרת (עד 0214: כן)',
  $$update worker_pay_settings set shift_bonus = 999 where profile_id = '20000000-0000-0000-0000-0000000065a2'$$, 0);
select t_rows('וגם לא לעצמו',
  $$update worker_pay_settings set shift_bonus = 999 where profile_id = '20000000-0000-0000-0000-0000000065a4'$$, 0);
select t_expect_fail('ואינו פותח שורת שכר חדשה עם תעריף',
  $$insert into worker_pay_settings (profile_id, hourly_rate) values ('20000000-0000-0000-0000-0000000065a1', 250)$$);
select t_eq('דרך הפונקציה הוא מקבל את השעון בלי הכסף',
  (select (s ? 'hourly_rate')::text || ':' || (s ? 'shift_bonus')::text || ':' || (s ? 'requires_location')::text
     from (select worker_settings_for('20000000-0000-0000-0000-0000000065a2') s) x), 'false:false:true');
select t_expect_ok('וקובע את השעון',
  $$select worker_settings_save('20000000-0000-0000-0000-0000000065a2', '{"requires_location": true}')$$);
select t_expect_ok('גם כשהכרטיס שולח את כל הטופס — כסף שלא השתנה אינו חוסם',
  $$select worker_settings_save('20000000-0000-0000-0000-0000000065a2',
      '{"requires_location": true, "hourly_rate": 50, "shift_bonus": 10, "overtime_enabled": true}')$$);
select t_expect_fail('אבל לא בונוס',
  $$select worker_settings_save('20000000-0000-0000-0000-0000000065a2', '{"shift_bonus": 99}')$$);
select t_expect_fail('ולא תעריף',
  $$select worker_settings_save('20000000-0000-0000-0000-0000000065a2', '{"hourly_rate": 99}')$$);
select t_expect_fail('ולא עמודה שאינה קיימת',
  $$select worker_settings_save('20000000-0000-0000-0000-0000000065a2', '{"is_admin": true}')$$);

select t65_as('a5');
select t_eq('משאבי אנוש רואים את השכר', (select hourly_rate from worker_pay_settings
  where profile_id = '20000000-0000-0000-0000-0000000065a2'), 50::numeric(10,2));
select t_expect_ok('וקובעים תעריף דרך הפונקציה',
  $$select worker_settings_save('20000000-0000-0000-0000-0000000065a2', '{"hourly_rate": 55}')$$);
select t_eq('והתעריף נשמר, והשעון שנקבע קודם לא נדרס',
  (select hourly_rate::text || ':' || requires_location::text from worker_pay_settings
    where profile_id = '20000000-0000-0000-0000-0000000065a2'), '55.00:true');

select t65_as('a2');
select t_eq('העובד עצמו קורא את השורה שלו', (select count(*)::int from worker_pay_settings
  where profile_id = app.profile_id()), 1);

select t65_as('b1');
select t_expect_fail('משתמש לקוח אינו קורא הגדרות של עובד שלנו',
  $$select worker_settings_for('20000000-0000-0000-0000-0000000065a2')$$);

-- ===== 7. מטא-דאטה של הרשאות — רק בתוך הארגון ============================

\echo '--- 7. מי מחזיק מה ---'

select t65_as('b1');
select t_eq('מנהל לקוח עם "צפייה בעובדים" רואה את התפקידים של אנשי הלקוח שלו',
  (select count(*)::int from profile_roles where profile_id = '20000000-0000-0000-0000-0000000065b2'), 1);
select t_eq('אבל לא של לקוח אחר (עד 0214: של כולם)',
  (select count(*)::int from profile_roles where profile_id = '20000000-0000-0000-0000-0000000065b4'), 0);
select t_eq('ולא של הצוות שלנו',
  (select count(*)::int from profile_roles where profile_id = '20000000-0000-0000-0000-0000000065a2'), 0);
select t_eq('ולא את ההרשאות האישיות שלהם',
  (select count(*)::int from user_permission_grants where profile_id = '20000000-0000-0000-0000-0000000065a2'), 0);

-- ===== 8. סכומי ההזמנה מ-ViperFlow ========================================

\echo '--- 8. ViperFlow ---'
reset role;
insert into viperflow_connections (id, customer_id, label)
values ('70000000-0000-0000-0000-0000000065c0', '10000000-0000-0000-0000-0000000065a0', 'ViperFlow 65');
insert into viperflow_links (event_id, connection_id, order_id, order_number, order_snapshot)
values ('30000000-0000-0000-0000-0000000065e1', '70000000-0000-0000-0000-0000000065c0',
        '99999999-6565-4444-4444-000000000065', 'ORD-65', '{"trucking": 1500, "discount": 10}');
set role authenticated;
select t65_as('a2');
select t_eq('עובד שטח רואה שהאירוע מסונכרן', (select count(*)::int from viperflow_event_link
  where event_id = '30000000-0000-0000-0000-0000000065e1'), 1);
select t_expect_fail('אבל לא את סכומי ההזמנה',
  $$select order_snapshot from viperflow_links where event_id = '30000000-0000-0000-0000-0000000065e1'$$);

-- ===== 9. פונקציות שעקפו את RLS ===========================================

\echo '--- 9. פונקציות ---'

select t65_as('b1');
select t_expect_fail('לקוח אינו שואל על אזורי תמחור (של אף לקוח)',
  $$select zone_for_location('10000000-0000-0000-0000-0000000065b0', 32.08, 34.78)$$);
select t65_as('a1');
select t_expect_ok('המשרד, עם "צפייה במחיר", כן',
  $$select zone_for_location('10000000-0000-0000-0000-0000000065b0', 32.08, 34.78)$$);

select t65_as('a2');
select t_eq('פירוט המשמרת אינו מגלה טיוטה ששובץ אליה (עד 0214: שם לקוח, מיקום וצוות)',
  (select jsonb_array_length(shift_task_breakdown(app.profile_id(),
     array['62000000-0000-0000-0000-0000000065f4'::uuid]) -> 'tasks')), 0);
select t_eq('ומשימה מפורסמת — כן',
  (select jsonb_array_length(shift_task_breakdown(app.profile_id(),
     array['62000000-0000-0000-0000-0000000065f1'::uuid]) -> 'tasks')), 1);

reset role;
set role authenticated;
select t65_as('a6');
select t_expect_ok('מנהל מערכת מאשר את אירוע א2',
  $$select set_event_approved('30000000-0000-0000-0000-0000000065e2', true)$$);
select t_expect_ok('ואת אירוע א1',
  $$select set_event_approved('30000000-0000-0000-0000-0000000065e1', true)$$);
reset role;
select t_eq('מנהל אצל הלקוח מקבל את שתי ההתראות',
  (select count(*)::int from notifications
    where recipient_id = '20000000-0000-0000-0000-0000000065b1' and type = 'event_approved'), 2);
select t_eq('עובד הסגל מקבל רק על האירוע ששובץ אליו (עד 0214: גם על א2, שאינו רואה)',
  (select string_agg(entity_id::text, ',') from notifications
    where recipient_id = '20000000-0000-0000-0000-0000000065b3' and type = 'event_approved'),
  '30000000-0000-0000-0000-0000000065e1');
select t_eq('ומי שנחסמה לו צפייה באירועים אינו מקבל אף אחת',
  (select count(*)::int from notifications
    where recipient_id = '20000000-0000-0000-0000-0000000065b5' and type = 'event_approved'), 0);

insert into customer_board_fields (customer_id, field_key, state)
values ('10000000-0000-0000-0000-0000000065b0', 'notes', 'hidden')
on conflict (customer_id, field_key) do update set state = excluded.state;
set role authenticated;
select t65_as('b1');
select t_eq('משתמש לקוח אינו קורא את תצורת הלוח של לקוח אחר',
  (select count(*)::int from customer_board_fields
    where customer_id = '10000000-0000-0000-0000-0000000065b0'), 0);
select t65_as('c1');
select t_eq('וגם קבלן לא', (select count(*)::int from customer_board_fields), 0);
select t65_as('a1');
select t_eq('הצוות קורא אותה', (select count(*)::int from customer_board_fields
  where customer_id = '10000000-0000-0000-0000-0000000065b0' and field_key = 'notes'
    and state = 'hidden'), 1);


-- ===== 10. שני הפערים שהסקירה של 0214 מצאה (0216) =========================

\echo '--- 10. 0216: מטא-דאטה בין עמיתים, והתראה מול היקף חלקי ---'

-- (א) צופה אצל לקוח, בלי "צפייה בעובדים", אינו קורא את ההרשאות של עמיתיו.
select t65_as('b2');
select t_eq('צופה אצל לקוח אינו רואה את התפקידים של עמיתיו (עד 0216: כן)',
  (select count(*)::int from profile_roles where profile_id = '20000000-0000-0000-0000-0000000065b1'), 0);
select t_eq('ולא את ההרשאות האישיות שלהם',
  (select count(*)::int from user_permission_grants where profile_id = '20000000-0000-0000-0000-0000000065b5'), 0);
select t65_as('b1');
select t_eq('ומנהל עם "צפייה בעובדים" — עדיין כן',
  (select count(*)::int from user_permission_grants where profile_id = '20000000-0000-0000-0000-0000000065b5'), 2);

-- (ב) חלון תאריכים אישי לצופה: אירוע א4, שמחוץ לחלון, אושר — והוא אינו
-- מקבל עליו התראה, בדיוק כמו שאינו רואה אותו.
reset role;
insert into permission_scopes (profile_id, resource, scope_type, days_back, days_forward)
values ('20000000-0000-0000-0000-0000000065b2', 'events', 'date_window', 30, 30);
alter table events disable trigger events_default_tasks;
insert into events (id, customer_id, end_client_name, event_number, event_date)
values ('30000000-0000-0000-0000-0000000065e4', '10000000-0000-0000-0000-0000000065a0',
        'אירוע א4 65', 'EV-65-A4', current_date + 1133);
alter table events enable trigger events_default_tasks;
set role authenticated;

select t65_as('b2');
select t_eq('הצופה אינו רואה את א4 — מחוץ לחלון התאריכים שלו',
  (select count(*)::int from events where id = '30000000-0000-0000-0000-0000000065e4'), 0);
select t65_as('b5');
select t_eq('וצופה אחר אצל אותו לקוח אינו קורא את ההיקף שלו',
  (select count(*)::int from permission_scopes where profile_id = '20000000-0000-0000-0000-0000000065b2'), 0);
select t65_as('a6');
select t_expect_ok('מנהל מערכת מאשר את א4',
  $$select set_event_approved('30000000-0000-0000-0000-0000000065e4', true)$$);
reset role;
select t_eq('הצופה אינו מקבל התראה על אירוע מחוץ להיקף שלו (עד 0216: קיבל שם ותאריך)',
  (select count(*)::int from notifications where recipient_id = '20000000-0000-0000-0000-0000000065b2'
     and type = 'event_approved' and entity_id = '30000000-0000-0000-0000-0000000065e4'), 0);
select t_eq('ומנהל אצל הלקוח, שאינו מוגבל, מקבל',
  (select count(*)::int from notifications where recipient_id = '20000000-0000-0000-0000-0000000065b1'
     and type = 'event_approved' and entity_id = '30000000-0000-0000-0000-0000000065e4'), 1);
select t_eq('ועובד הסגל, שלא שובץ אליו, אינו מקבל',
  (select count(*)::int from notifications where recipient_id = '20000000-0000-0000-0000-0000000065b3'
     and type = 'event_approved' and entity_id = '30000000-0000-0000-0000-0000000065e4'), 0);

reset role;
select set_config('request.jwt.claim.sub', '', false);
