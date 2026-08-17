\pset tuples_only on
\pset format unaligned

-- ===========================================================================
-- 11: הרשאות ברירת המחדל פר סוג משתמש (0066).
--
-- החבילה מקימה לקוח, קבלן, אנשי צוות, אירוע ומשימות משל עצמה ואינה נשענת על
-- אף חבילה קודמת. היא בודקת שני דברים: את מטריצת app.has לכל פרסונה, ואת
-- ההתנהגות בפועל מול ה-RLS והטריגרים (עריכה, פרסום, שיבוץ, ראיית מי משובץ,
-- והצמצום של עובד הקבלן למשימות שלו בלבד).
--
-- הזריעה רצה בלי JWT (auth.uid() = null), ולכן טריגר הפרסום וטריגר השדות
-- מדלגים — אפשר להזריע משימה "משובצת" ישירות בלי שהם יחסמו.
-- ===========================================================================

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000011a1', 'cust-mgr@vl.test'),
  ('00000000-0000-0000-0000-0000000011a2', 'cust-emp@vl.test'),
  ('00000000-0000-0000-0000-0000000011a3', 'contr-mgr@vl.test'),
  ('00000000-0000-0000-0000-0000000011a4', 'contr-emp@vl.test'),
  ('00000000-0000-0000-0000-0000000011a5', 'staff-status@vl.test'),
  ('00000000-0000-0000-0000-0000000011a6', 'staff-driver@vl.test'),
  ('00000000-0000-0000-0000-0000000011a7', 'staff-lead@vl.test'),
  ('00000000-0000-0000-0000-0000000011a8', 'staff-worker@vl.test');

insert into customers (id, name) values
  ('10000000-0000-0000-0000-000000000011', 'לקוח ההרשאות');

insert into contractors (id, name, default_task_price) values
  ('11000000-0000-0000-0000-000000000011', 'קבלן ההרשאות', 500);

-- שורת סגל אצל הקבלן, שאליה קשור עובד הקבלן ושעליה נרשם ב-task_contractor_workers
insert into contractor_workers (id, contractor_id, full_name) values
  ('12000000-0000-0000-0000-000000000011', '11000000-0000-0000-0000-000000000011', 'עובד הקבלן');

insert into profiles (id, user_id, user_kind, is_admin, full_name, customer_id, contractor_id, contractor_worker_id) values
  ('20000000-0000-0000-0000-0000000011a1', '00000000-0000-0000-0000-0000000011a1',
   'customer_user', false, 'מנהל לקוח', '10000000-0000-0000-0000-000000000011', null, null),
  ('20000000-0000-0000-0000-0000000011a2', '00000000-0000-0000-0000-0000000011a2',
   'customer_user', false, 'עובד לקוח', '10000000-0000-0000-0000-000000000011', null, null),
  ('20000000-0000-0000-0000-0000000011a3', '00000000-0000-0000-0000-0000000011a3',
   'contractor_user', false, 'מנהל קבלן', null, '11000000-0000-0000-0000-000000000011', null),
  ('20000000-0000-0000-0000-0000000011a4', '00000000-0000-0000-0000-0000000011a4',
   'contractor_user', false, 'עובד קבלן', null, '11000000-0000-0000-0000-000000000011',
   '12000000-0000-0000-0000-000000000011'),
  ('20000000-0000-0000-0000-0000000011a5', '00000000-0000-0000-0000-0000000011a5',
   'staff', false, 'איש סטטוס', null, null, null),
  ('20000000-0000-0000-0000-0000000011a6', '00000000-0000-0000-0000-0000000011a6',
   'staff', false, 'נהג', null, null, null),
  ('20000000-0000-0000-0000-0000000011a7', '00000000-0000-0000-0000-0000000011a7',
   'staff', false, 'ראש צוות', null, null, null),
  ('20000000-0000-0000-0000-0000000011a8', '00000000-0000-0000-0000-0000000011a8',
   'staff', false, 'עובד שטח', null, null, null);

-- תפקידי ההרשאה
insert into profile_roles (profile_id, role_id)
select p.pid, r.id from (values
  ('20000000-0000-0000-0000-0000000011a1'::uuid, 'customer_manager'),
  ('20000000-0000-0000-0000-0000000011a2'::uuid, 'customer_viewer'),
  ('20000000-0000-0000-0000-0000000011a3'::uuid, 'contractor_manager'),
  ('20000000-0000-0000-0000-0000000011a4'::uuid, 'contractor_worker'),
  ('20000000-0000-0000-0000-0000000011a6'::uuid, 'driver'),
  ('20000000-0000-0000-0000-0000000011a7'::uuid, 'team_lead')
) as p(pid, rkey)
join permission_roles r on r.key = p.rkey;

-- איש הסטטוס: מענק אישי על tasks.change_status, כדי לבדוק שהפרסום נגזר ממנו
-- דרך implied_by בלי שום שורה מפורשת על tasks.publish.
insert into user_permission_grants (profile_id, permission_key, allowed) values
  ('20000000-0000-0000-0000-0000000011a5', 'tasks.change_status', true);

-- אירוע ומשימות. שולפים task_type אמיתי מהקטלוג המוזרע.
insert into events (id, customer_id, event_date, location_lat, location_lng) values
  ('30000000-0000-0000-0000-000000000011', '10000000-0000-0000-0000-000000000011',
   current_date + 3, 32.0853, 34.7818);

-- T1 — משימת הלקוח (סטטוס מתוכנן), עם עובד שטח משובץ כדי לבדוק ראיית שמות
insert into tasks (id, event_id, customer_id, task_type_id, task_date, status_id, worker_count)
select '31000000-0000-0000-0000-000000110001', '30000000-0000-0000-0000-000000000011',
       '10000000-0000-0000-0000-000000000011',
       (select id from task_types where code = 'setup' limit 1),
       current_date + 3,
       (select id from statuses where entity = 'task' and code = 'planned' and deleted_at is null), 2;

insert into task_assignments (task_id, profile_id, role, work_site) values
  ('31000000-0000-0000-0000-000000110001', '20000000-0000-0000-0000-0000000011a8', 'worker', 'field');

-- T2 — משימה שהואצלה לקבלן, פורסמה, ועובד הקבלן רשום עליה
insert into tasks (id, event_id, customer_id, task_type_id, task_date, status_id, contractor_id)
select '31000000-0000-0000-0000-000000110002', '30000000-0000-0000-0000-000000000011',
       '10000000-0000-0000-0000-000000000011',
       (select id from task_types where code = 'setup' limit 1),
       current_date + 3,
       (select id from statuses where entity = 'task' and code = 'assigned' and deleted_at is null),
       '11000000-0000-0000-0000-000000000011';

insert into task_contractor_workers (task_id, contractor_worker_id) values
  ('31000000-0000-0000-0000-000000110002', '12000000-0000-0000-0000-000000000011');

-- T3 — משימה של אותו קבלן, פורסמה, אך עובד הקבלן *אינו* רשום עליה
insert into tasks (id, event_id, customer_id, task_type_id, task_date, status_id, contractor_id)
select '31000000-0000-0000-0000-000000110003', '30000000-0000-0000-0000-000000000011',
       '10000000-0000-0000-0000-000000000011',
       (select id from task_types where code = 'setup' limit 1),
       current_date + 3,
       (select id from statuses where entity = 'task' and code = 'assigned' and deleted_at is null),
       '11000000-0000-0000-0000-000000000011';

-- ===========================================================================
\echo '--- מנהל לקוח: עורך אבל לא משבץ, לא מתמחר, לא מפרסם ---'
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000011a1', false);

select t_eq('מנהל לקוח: events.create',        app.has('events.create'), true);
select t_eq('מנהל לקוח: events.edit',          app.has('events.edit'), true);
select t_eq('מנהל לקוח: tasks.edit',           app.has('tasks.edit'), true);
select t_eq('מנהל לקוח: tasks.change_truck',   app.has('tasks.change_truck'), true);
select t_eq('מנהל לקוח: board.view_staffing',  app.has('board.view_staffing'), true);
select t_eq('מנהל לקוח: pricing.view',         app.has('pricing.view'), true);
select t_eq('מנהל לקוח: אין pricing.edit',     app.has('pricing.edit'), false);
select t_eq('מנהל לקוח: אין tasks.publish',    app.has('tasks.publish'), false);
select t_eq('מנהל לקוח: אין tasks.assign.worker', app.has('tasks.assign.worker'), false);
select t_eq('מנהל לקוח: אין tasks.delegate',   app.has('tasks.delegate'), false);
select t_eq('מנהל לקוח: dashboard.view',       app.has('dashboard.view'), true);

select t_expect_ok('מנהל לקוח עורך הערות במשימה', $$
  update tasks set notes = 'הערה מהמנהל' where id = '31000000-0000-0000-0000-000000110001'$$);

select t_expect_ok('מנהל לקוח משנה סטטוס למתוכנן/טיוטה (לא פרסום)', $$
  update tasks set status_id = (select id from statuses
    where entity = 'task' and code = 'draft' and deleted_at is null)
   where id = '31000000-0000-0000-0000-000000110001'$$);

select t_expect_fail('מנהל לקוח נחסם מפרסום (סטטוס "משובץ")', $$
  update tasks set status_id = (select id from statuses
    where entity = 'task' and code = 'assigned' and deleted_at is null)
   where id = '31000000-0000-0000-0000-000000110001'$$);

select t_expect_fail('מנהל לקוח נחסם משיבוץ עובד', $$
  insert into task_assignments (task_id, profile_id, role, work_site)
  values ('31000000-0000-0000-0000-000000110001',
          '20000000-0000-0000-0000-0000000011a7', 'worker', 'field')$$);

select t_eq('מנהל לקוח רואה מי משובץ (שם בלו״ז)',
  (select jsonb_array_length(workers) from work_board_view
    where id = '31000000-0000-0000-0000-000000110001'), 1);

-- ‏0076: שני צידי אותו מטבע. השם של המשובץ גלוי בלוח (הבדיקה שלמעלה), אבל
-- שורת הפרופיל שלו אינה נקראת — איש הצוות אינו "עובד של הלקוח", לא במסך
-- העובדים, לא בחיפוש הגלובלי ולא בבקשת REST ישירה אל profiles.
select t_eq('מנהל לקוח: שורת הפרופיל של המשובץ אינה נקראת',
  (select count(*)::int from profiles where id = '20000000-0000-0000-0000-0000000011a8'), 0);

select t_eq('מנהל לקוח: רואה את משתמשי החברה שלו בלבד',
  (select count(*)::int from profiles), 2);

select t_eq('מנהל לקוח: החיפוש הגלובלי אינו מחזיר את איש הצוות',
  (select count(*)::int from jsonb_array_elements(global_search('עובד שטח', 8)) x
    where x->>'kind' = 'profile'), 0);

select t_eq('מנהל לקוח: אין users.view (מסך העובדים אינו מסך של לקוח)',
  app.has('users.view'), false);

reset role;
select set_config('request.jwt.claim.sub', '', false);
-- מחזירים את T1 למתוכנן לצורך המשך הבדיקות
update tasks set status_id = (select id from statuses
  where entity = 'task' and code = 'planned' and deleted_at is null)
 where id = '31000000-0000-0000-0000-000000110001';

-- ===========================================================================
\echo '--- עובד לקוח: צפייה בלבד, בלי כספים ---'
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000011a2', false);

select t_eq('עובד לקוח: events.view',        app.has('events.view'), true);
select t_eq('עובד לקוח: אין events.edit',    app.has('events.edit'), false);
select t_eq('עובד לקוח: אין events.create',  app.has('events.create'), false);
select t_eq('עובד לקוח: אין tasks.edit',     app.has('tasks.edit'), false);
select t_eq('עובד לקוח: אין pricing.view',   app.has('pricing.view'), false);
select t_eq('עובד לקוח: board.view_staffing',app.has('board.view_staffing'), true);

select t_rows('עובד לקוח נחסם מעריכת משימה', $$
  update tasks set notes = 'לא אמור לעבור' where id = '31000000-0000-0000-0000-000000110001'$$, 0);

reset role;
select set_config('request.jwt.claim.sub', '', false);

-- ===========================================================================
\echo '--- צוות (נהג / ראש צוות): צפייה בלבד, בלי דשבורד ובלי מחירים ---'
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000011a6', false);
select t_eq('נהג: אין tasks.edit',          app.has('tasks.edit'), false);
select t_eq('נהג: אין tasks.change_status', app.has('tasks.change_status'), false);
select t_eq('נהג: אין tasks.publish',       app.has('tasks.publish'), false);
select t_eq('נהג: אין dashboard.view',      app.has('dashboard.view'), false);
select t_eq('נהג: אין pricing.view',        app.has('pricing.view'), false);
select t_eq('נהג: calendar.view',           app.has('calendar.view'), true);
reset role;
select set_config('request.jwt.claim.sub', '', false);

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000011a7', false);
select t_eq('ראש צוות: אין tasks.edit',          app.has('tasks.edit'), false);
select t_eq('ראש צוות: אין tasks.change_status', app.has('tasks.change_status'), false);
select t_eq('ראש צוות: אין tasks.publish',       app.has('tasks.publish'), false);
select t_eq('ראש צוות: אין dashboard.view',      app.has('dashboard.view'), false);
select t_eq('ראש צוות: אין pricing.view',        app.has('pricing.view'), false);
reset role;
select set_config('request.jwt.claim.sub', '', false);

-- ===========================================================================
\echo '--- implied_by: מי שמחזיק tasks.change_status מקבל tasks.publish ---'
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000011a5', false);
select t_eq('איש הסטטוס מחזיק change_status', app.has('tasks.change_status'), true);
select t_eq('ולכן גם tasks.publish (בירושה)', app.has('tasks.publish'), true);
reset role;
select set_config('request.jwt.claim.sub', '', false);

-- ===========================================================================
\echo '--- מנהל קבלן רואה את כל משימות הקבלן; עובד קבלן רק את שלו ---'
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000011a3', false);
select t_eq('מנהל קבלן: portal.view', app.has('portal.view'), true);
select t_eq('מנהל קבלן רואה את T2',
  (select count(*)::int from tasks where id = '31000000-0000-0000-0000-000000110002'), 1);
select t_eq('מנהל קבלן רואה גם את T3',
  (select count(*)::int from tasks where id = '31000000-0000-0000-0000-000000110003'), 1);
reset role;
select set_config('request.jwt.claim.sub', '', false);

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000011a4', false);
select t_eq('עובד קבלן: אין portal.view', app.has('portal.view'), false);
select t_eq('עובד קבלן: board.view',      app.has('board.view'), true);
select t_eq('עובד קבלן רואה את המשימה שהוא רשום עליה (T2)',
  (select count(*)::int from tasks where id = '31000000-0000-0000-0000-000000110002'), 1);
select t_eq('עובד קבלן אינו רואה משימת קבלן שאינו רשום עליה (T3)',
  (select count(*)::int from tasks where id = '31000000-0000-0000-0000-000000110003'), 0);
select t_eq('וגם בלו״ז — רק שלו',
  (select count(*)::int from work_board_view
    where id in ('31000000-0000-0000-0000-000000110002','31000000-0000-0000-0000-000000110003')), 1);
reset role;
select set_config('request.jwt.claim.sub', '', false);

-- ===========================================================================
-- 0067: תפקיד חוצה-סוג לא מזליג, ומסכי הצוות סגורים
-- ===========================================================================
-- a9 — איש staff שהוצמד לו (בטעות) גם התפקיד customer_manager. הזריעה רצה
-- בלי JWT, ולכן שומר ההצמדה מדלג; הבדיקה היא ש-app.has מתעלם ממנו בכל מקרה.
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000011a9', 'staff-crosskind@vl.test');
insert into profiles (id, user_id, user_kind, is_admin, full_name) values
  ('20000000-0000-0000-0000-0000000011a9', '00000000-0000-0000-0000-0000000011a9',
   'staff', false, 'איש צוות עם תפקיד לקוח');
insert into profile_roles (profile_id, role_id)
select '20000000-0000-0000-0000-0000000011a9', id from permission_roles where key in ('worker','customer_manager');

-- אירוע ומשימה משובצת נפרדים, כדי לבדוק שהצוות רואה את הקשר האירוע שלו
insert into events (id, customer_id, event_date, location_lat, location_lng) values
  ('30000000-0000-0000-0000-000000000019', '10000000-0000-0000-0000-000000000011',
   current_date + 5, 32.09, 34.78);
insert into tasks (id, event_id, customer_id, task_type_id, task_date, status_id, worker_count)
select '31000000-0000-0000-0000-000000110009', '30000000-0000-0000-0000-000000000019',
       '10000000-0000-0000-0000-000000000011',
       (select id from task_types where code = 'setup' limit 1),
       current_date + 5,
       (select id from statuses where entity = 'task' and code = 'assigned' and deleted_at is null), 1;
insert into task_assignments (task_id, profile_id, role, work_site) values
  ('31000000-0000-0000-0000-000000110009', '20000000-0000-0000-0000-0000000011a9', 'worker', 'field');

\echo '--- תפקיד חוצה-סוג (customer_manager על staff) אינו מזליג ---'
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000011a9', false);
select t_eq('צוות: אין dashboard.view (למרות תפקיד לקוח)', app.has('dashboard.view'), false);
select t_eq('צוות: אין pricing.view (הכנסות)',            app.has('pricing.view'), false);
select t_eq('צוות: אין pricing.revenue',                 app.has('pricing.revenue'), false);
select t_eq('צוות: אין customers.view',                  app.has('customers.view'), false);
select t_eq('צוות: אין users.view (עובדים)',             app.has('users.view'), false);
select t_eq('צוות: אין reports.view (דוחות)',            app.has('reports.view'), false);
select t_eq('צוות: אין events.view (עמוד אירועים)',      app.has('events.view'), false);

\echo '--- אבל מסכי הצוות פתוחים ---'
select t_eq('צוות: calendar.view',            app.has('calendar.view'), true);
select t_eq('צוות: board.view',               app.has('board.view'), true);
select t_eq('צוות: attendance.view_schedule', app.has('attendance.view_schedule'), true);
select t_eq('צוות: attendance.view_own',      app.has('attendance.view_own'), true);

\echo '--- והצוות רואה את הקשר האירוע שהוא משובץ אליו, בלי events.view ---'
select t_eq('צוות רואה את האירוע שהוא משובץ אליו',
  (select count(*)::int from events where id = '30000000-0000-0000-0000-000000000019'), 1);
select t_eq('אך לא אירוע שאינו משובץ אליו',
  (select count(*)::int from events where id = '30000000-0000-0000-0000-000000000011'), 0);
select t_eq('והלו״ז נושא את הקשר האירוע (מספר/לקוח קצה)',
  (select count(*)::int from work_board_view where id = '31000000-0000-0000-0000-000000110009'), 1);
reset role;
select set_config('request.jwt.claim.sub', '', false);
