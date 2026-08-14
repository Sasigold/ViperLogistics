\pset tuples_only on
\pset format unaligned

-- ===========================================================================
-- 14: הקבלן ב-shell המשותף (0071).
--
-- החבילה מקימה שני קבלנים, לקוח, אירוע ומשימות משל עצמה ואינה נשענת על אף
-- חבילה קודמת. היא בודקת שלושה דברים:
--
--   * שהפיכת `default_allowed` של מפתחות הפורטל לא לקחה אותם מהקבלנים ולא
--     השאירה אותם אצל הצוות;
--   * שמנהל הקבלן מחזיק את מפתחות המסכים המשותפים ולא את מה שסביבם;
--   * ששיבוץ של חשבון שנרשם תחת הקבלן ואין לו שורת סגל יוצר את הגשר, ושהגשר
--     הזה הוא מה שמייצר לו משמרת — כלומר שהוא לא קוסמטי.
--
-- הזריעה רצה בלי JWT (auth.uid() = null), ולכן טריגר הפרסום וטריגר השדות
-- מדלגים ואפשר להזריע משימה "משובצת" ישירות.
-- ===========================================================================

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000014a1', 'c14-mgr@vl.test'),
  ('00000000-0000-0000-0000-0000000014a2', 'c14-roster@vl.test'),
  ('00000000-0000-0000-0000-0000000014a3', 'c14-office-hire@vl.test'),
  ('00000000-0000-0000-0000-0000000014a4', 'c14-other@vl.test'),
  ('00000000-0000-0000-0000-0000000014a5', 'c14-staff@vl.test');

insert into customers (id, name) values
  ('10000000-0000-0000-0000-000000000014', 'לקוח ה-shell');

insert into contractors (id, name, default_task_price) values
  ('11000000-0000-0000-0000-00000000014a', 'קבלן א', 500),
  ('11000000-0000-0000-0000-00000000014b', 'קבלן ב', 500);

-- שורת סגל ידנית אצל קבלן א, עם חשבון מקושר — הנתיב הישן
insert into contractor_workers (id, contractor_id, full_name) values
  ('12000000-0000-0000-0000-00000000014a', '11000000-0000-0000-0000-00000000014a', 'עובד מהרוסטר');

insert into profiles (id, user_id, user_kind, full_name, contractor_id, contractor_worker_id) values
  -- מנהל הקבלן
  ('20000000-0000-0000-0000-0000000014a1', '00000000-0000-0000-0000-0000000014a1',
   'contractor_user', 'מנהל קבלן א', '11000000-0000-0000-0000-00000000014a', null),
  -- עובד שיש לו שורת רוסטר וגשר
  ('20000000-0000-0000-0000-0000000014a2', '00000000-0000-0000-0000-0000000014a2',
   'contractor_user', 'עובד מהרוסטר', '11000000-0000-0000-0000-00000000014a',
   '12000000-0000-0000-0000-00000000014a'),
  -- **הפער**: חשבון שהמשרד יצר במסך העובדים — contractor_id בלי contractor_worker_id
  ('20000000-0000-0000-0000-0000000014a3', '00000000-0000-0000-0000-0000000014a3',
   'contractor_user', 'עובד שנרשם במשרד', '11000000-0000-0000-0000-00000000014a', null),
  -- עובד של קבלן אחר
  ('20000000-0000-0000-0000-0000000014a4', '00000000-0000-0000-0000-0000000014a4',
   'contractor_user', 'עובד של קבלן ב', '11000000-0000-0000-0000-00000000014b', null),
  -- איש צוות בלי שום מפתח קבלנים
  ('20000000-0000-0000-0000-0000000014a5', '00000000-0000-0000-0000-0000000014a5',
   'staff', 'איש צוות', null, null);

insert into profile_roles (profile_id, role_id)
select p.pid, r.id from (values
  ('20000000-0000-0000-0000-0000000014a1'::uuid, 'contractor_manager'),
  ('20000000-0000-0000-0000-0000000014a2'::uuid, 'contractor_worker'),
  ('20000000-0000-0000-0000-0000000014a3'::uuid, 'contractor_worker'),
  ('20000000-0000-0000-0000-0000000014a5'::uuid, 'worker')
) as p(pid, rkey)
join permission_roles r on r.key = p.rkey;

insert into events (id, customer_id, event_date, location_lat, location_lng) values
  ('30000000-0000-0000-0000-000000000014', '10000000-0000-0000-0000-000000000014',
   current_date + 5, 32.0853, 34.7818);

-- T1 — משימה של קבלן א, עם שעות כדי ש-planned_shifts יוכל לגזור ממנה משמרת
insert into tasks (id, event_id, customer_id, task_type_id, task_date, status_id,
                   contractor_id, worker_count, onsite_start_time, hours_count)
select '31000000-0000-0000-0000-000000140001', '30000000-0000-0000-0000-000000000014',
       '10000000-0000-0000-0000-000000000014',
       (select id from task_types where code = 'setup' limit 1),
       current_date + 5,
       (select id from statuses where entity = 'task' and code = 'assigned' and deleted_at is null),
       '11000000-0000-0000-0000-00000000014a', 3, '08:00', 6;

-- T2 — משימה של קבלן ב
insert into tasks (id, event_id, customer_id, task_type_id, task_date, status_id,
                   contractor_id, worker_count, onsite_start_time, hours_count)
select '31000000-0000-0000-0000-000000140002', '30000000-0000-0000-0000-000000000014',
       '10000000-0000-0000-0000-000000000014',
       (select id from task_types where code = 'setup' limit 1),
       current_date + 5,
       (select id from statuses where entity = 'task' and code = 'assigned' and deleted_at is null),
       '11000000-0000-0000-0000-00000000014b', 2, '08:00', 6;

-- ===========================================================================
\echo '--- §1: מפתחות הפורטל אינם עוד ברירת מחדל לכולם ---'
set role authenticated;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000014a5', false);
select t_eq('צוות: אין portal.view',            app.has('portal.view'), false);
select t_eq('צוות: אין portal.manage_workers',  app.has('portal.manage_workers'), false);
select t_eq('צוות: אין portal.assign_workers',  app.has('portal.assign_workers'), false);
select t_eq('צוות: אין portal.view_financials', app.has('portal.view_financials'), false);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000014a1', false);
select t_eq('מנהל קבלן: portal.view',            app.has('portal.view'), true);
select t_eq('מנהל קבלן: portal.manage_workers',  app.has('portal.manage_workers'), true);
select t_eq('מנהל קבלן: portal.assign_workers',  app.has('portal.assign_workers'), true);
select t_eq('מנהל קבלן: portal.view_financials', app.has('portal.view_financials'), true);
select t_eq('מנהל קבלן: portal.attendance',      app.has('portal.attendance'), true);

\echo '--- §2: מנהל הקבלן מחזיק את המסכים, ולא את מה שסביבם ---'
select t_eq('מנהל קבלן: calendar.view',       app.has('calendar.view'), true);
select t_eq('מנהל קבלן: board.view',          app.has('board.view'), true);
select t_eq('מנהל קבלן: board.view_staffing', app.has('board.view_staffing'), true);
select t_eq('מנהל קבלן: אין events.view (עמוד האירועים)', app.has('events.view'), false);
select t_eq('מנהל קבלן: אין dashboard.view',       app.has('dashboard.view'), false);
select t_eq('מנהל קבלן: אין customers.view',       app.has('customers.view'), false);
select t_eq('מנהל קבלן: אין users.view',           app.has('users.view'), false);
select t_eq('מנהל קבלן: אין contractors.view',     app.has('contractors.view'), false);
select t_eq('מנהל קבלן: אין pricing.view',         app.has('pricing.view'), false);
select t_eq('מנהל קבלן: אין attendance.view_all',  app.has('attendance.view_all'), false);
select t_eq('מנהל קבלן: אין board.inline_edit',    app.has('board.inline_edit'), false);
select t_eq('מנהל קבלן: אין tasks.edit',           app.has('tasks.edit'), false);
select t_eq('מנהל קבלן: אין tasks.publish',        app.has('tasks.publish'), false);
select t_eq('מנהל קבלן: אין calendar.drag',        app.has('calendar.drag'), false);

\echo '--- ולוח השנה שלו לא איבד הקשר כשנסגר events.view ---'
select t_eq('מנהל קבלן עדיין רואה את האירוע שיש בו משימה שלו',
  (select count(*)::int from events where id = '30000000-0000-0000-0000-000000000014'), 1);

\echo '--- הלוח אינו מדליף כסף ולא את הצוות של החברה ---'
select t_eq('מנהל קבלן: מחיר הלקוח מוסתר ב-work_board_view',
  (select customer_price from work_board_view where id = '31000000-0000-0000-0000-000000140001'), null);
select t_eq('מנהל קבלן: שם הקבלן מוסתר',
  (select contractor_name from work_board_view where id = '31000000-0000-0000-0000-000000140001'), null);
select t_eq('מנהל קבלן רואה רק את המשימה של הקבלן שלו',
  (select count(*)::int from work_board_view
    where id in ('31000000-0000-0000-0000-000000140001', '31000000-0000-0000-0000-000000140002')), 1);

\echo '--- §3: עובד הקבלן מיושר לרצפת העובד ---'
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000014a2', false);
select t_eq('עובד קבלן: calendar.view',            app.has('calendar.view'), true);
select t_eq('עובד קבלן: board.view',               app.has('board.view'), true);
select t_eq('עובד קבלן: tasks.view',               app.has('tasks.view'), true);
select t_eq('עובד קבלן: notifications.preferences', app.has('notifications.preferences'), true);
select t_eq('עובד קבלן: attendance.view_own',      app.has('attendance.view_own'), true);
select t_eq('עובד קבלן: attendance.view_schedule', app.has('attendance.view_schedule'), true);
select t_eq('עובד קבלן: attendance.clock',         app.has('attendance.clock'), true);
select t_eq('עובד קבלן: attendance.submit_entry',  app.has('attendance.submit_entry'), true);
select t_eq('עובד קבלן: אין portal.view',          app.has('portal.view'), false);
select t_eq('עובד קבלן: אין portal.attendance',    app.has('portal.attendance'), false);
select t_eq('עובד קבלן: אין attendance.view_all',  app.has('attendance.view_all'), false);
select t_eq('עובד קבלן: אין contractors.view',     app.has('contractors.view'), false);

\echo '--- §5: הרשימה המאוחדת של מי שניתן לשבץ ---'
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000014a1', false);

select t_eq('הרשימה מחזירה את שורת הרוסטר ואת החשבון שנרשם במשרד',
  (select count(*)::int from jsonb_array_elements(contractor_assignable_workers())), 2);
select t_eq('...והחשבון מהמשרד מגיע בלי worker_id',
  (select count(*)::int from jsonb_array_elements(contractor_assignable_workers()) e
    where e->>'full_name' = 'עובד שנרשם במשרד' and e->>'worker_id' is null), 1);
select t_eq('...ושורת הרוסטר מגיעה עם worker_id',
  (select e->>'worker_id' from jsonb_array_elements(contractor_assignable_workers()) e
    where e->>'full_name' = 'עובד מהרוסטר'), '12000000-0000-0000-0000-00000000014a');
select t_eq('מנהל הקבלן עצמו אינו ברשימה',
  (select count(*)::int from jsonb_array_elements(contractor_assignable_workers()) e
    where e->>'full_name' = 'מנהל קבלן א'), 0);
select t_eq('ואיש מקבלן אחר אינו ברשימה',
  (select count(*)::int from jsonb_array_elements(contractor_assignable_workers()) e
    where e->>'full_name' = 'עובד של קבלן ב'), 0);
-- הארגומנט אינו דרך לצאת מהקבלן שלך. מנהל קבלן מחזיק `contractors.manage_workers`
-- מאז 0011 — זה מה שמתיר לו לנהל את הסגל של עצמו — ולכן שער שנשען עליו היה
-- פותח לו את הסגל של כל קבלן אחר. ההפרדה היא לפי סוג המשתמש.
select t_eq('העברת קבלן אחר כארגומנט מוחזרת לקבלן של הקורא',
  (select count(*)::int from jsonb_array_elements(
     contractor_assignable_workers('11000000-0000-0000-0000-00000000014b')) e
    where e->>'full_name' = 'עובד של קבלן ב'), 0);
select t_eq('...והוא עדיין מקבל את שלו',
  (select count(*)::int from jsonb_array_elements(
     contractor_assignable_workers('11000000-0000-0000-0000-00000000014b'))), 2);

\echo '--- שיבוץ שורת רוסטר קיימת ---'
select t_expect_ok('מנהל קבלן משבץ עובד מהרוסטר', $$
  select contractor_assign_worker('31000000-0000-0000-0000-000000140001',
                                  '12000000-0000-0000-0000-00000000014a') $$);
select t_eq('...והשורה נוצרה',
  (select count(*)::int from task_contractor_workers
    where task_id = '31000000-0000-0000-0000-000000140001'
      and contractor_worker_id = '12000000-0000-0000-0000-00000000014a'), 1);

\echo '--- שיבוץ חשבון שאין לו שורת רוסטר: הגשר נוצר ---'
select t_expect_ok('מנהל קבלן משבץ עובד שנרשם במשרד', $$
  select contractor_assign_worker('31000000-0000-0000-0000-000000140001',
                                  null, '20000000-0000-0000-0000-0000000014a3') $$);
select t_eq('נוצרה שורת סגל לאותו עובד',
  (select count(*)::int from contractor_workers
    where contractor_id = '11000000-0000-0000-0000-00000000014a'
      and full_name = 'עובד שנרשם במשרד' and deleted_at is null), 1);
select t_eq('והוא משובץ למשימה',
  (select count(*)::int from task_contractor_workers t
     join contractor_workers w on w.id = t.contractor_worker_id
    where t.task_id = '31000000-0000-0000-0000-000000140001'
      and w.full_name = 'עובד שנרשם במשרד'), 1);

-- זו הבדיקה שמפרידה בין גשר אמיתי לקוסמטיקה: המשמרת הנגזרת מצטרפת דרך
-- profiles.contractor_worker_id, ובלעדיה העובד היה משובץ ובכל זאת בלי משמרת
-- ובלי יכולת להחתים.
select t_eq('ומכאן נגזרת לו משמרת',
  (select count(*)::int from app.planned_shifts_many(
     array['20000000-0000-0000-0000-0000000014a3'::uuid],
     current_date + 5, current_date + 5)), 1);

select t_expect_ok('שיבוץ חוזר של אותו עובד אינו יוצר שורת סגל שנייה', $$
  select contractor_assign_worker('31000000-0000-0000-0000-000000140001',
                                  null, '20000000-0000-0000-0000-0000000014a3') $$);
select t_eq('...ועדיין שורת סגל אחת',
  (select count(*)::int from contractor_workers
    where contractor_id = '11000000-0000-0000-0000-00000000014a'
      and full_name = 'עובד שנרשם במשרד' and deleted_at is null), 1);

\echo '--- הסרה משיבוץ אינה מפטרת ---'
select t_expect_ok('הסרת העובד מהמשימה', $$
  select contractor_assign_worker('31000000-0000-0000-0000-000000140001',
                                  '12000000-0000-0000-0000-00000000014a', null, false) $$);
select t_eq('השיבוץ ירד',
  (select count(*)::int from task_contractor_workers
    where task_id = '31000000-0000-0000-0000-000000140001'
      and contractor_worker_id = '12000000-0000-0000-0000-00000000014a'), 0);
select t_eq('אבל שורת הסגל נשארה',
  (select count(*)::int from contractor_workers
    where id = '12000000-0000-0000-0000-00000000014a' and deleted_at is null), 1);

\echo '--- מה שה-RPC מסרב לו ---'
select t_expect_fail('שיבוץ עובד של קבלן אחר למשימה של קבלן א', $$
  select contractor_assign_worker('31000000-0000-0000-0000-000000140001',
                                  null, '20000000-0000-0000-0000-0000000014a4') $$);
select t_expect_fail('שיבוץ במשימה שהואצלה לקבלן אחר', $$
  select contractor_assign_worker('31000000-0000-0000-0000-000000140002',
                                  '12000000-0000-0000-0000-00000000014a') $$);
select t_expect_fail('שיבוץ בלי לנקוב לא בעובד ולא בחשבון', $$
  select contractor_assign_worker('31000000-0000-0000-0000-000000140001') $$);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000014a2', false);
select t_expect_fail('עובד קבלן אינו משבץ', $$
  select contractor_assign_worker('31000000-0000-0000-0000-000000140001',
                                  '12000000-0000-0000-0000-00000000014a') $$);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000014a5', false);
select t_expect_fail('איש צוות בלי contractors.assign_workers אינו משבץ', $$
  select contractor_assign_worker('31000000-0000-0000-0000-000000140001',
                                  '12000000-0000-0000-0000-00000000014a') $$);

\echo '--- מה שנקרא מחוץ ל-RLS: הגשר ושורת התפקיד ---'
reset role;

-- ‏`profiles_select` (0066) מחזיר ל-`contractor_user` את שורתו בלבד, ולכן את
-- הגשר אי אפשר לאמת מתוך ההתחזות — הוא נקרא כאן, אחרי reset role.
select t_eq('profiles.contractor_worker_id מצביע על שורת הסגל שנוצרה',
  (select p.contractor_worker_id = w.id
     from profiles p join contractor_workers w
       on w.contractor_id = '11000000-0000-0000-0000-00000000014a'
      and w.full_name = 'עובד שנרשם במשרד'
    where p.id = '20000000-0000-0000-0000-0000000014a3'), true);

-- שורת התפקיד עצמה ולא רק התוצאה: עד 0071 `board.view` נגזר מ-`tasks.view`,
-- ומי שהיה מצמצם את `tasks.view` היה לוקח למנהל הקבלן את הלוח בלי לדעת.
select t_eq('board.view מוענק ל-contractor_manager במפורש ולא בירושה',
  (select allowed from role_permissions rp
     join permission_roles r on r.id = rp.role_id
    where r.key = 'contractor_manager' and rp.permission_key = 'board.view'), true);
select t_eq('ו-calendar.view כמוהו',
  (select allowed from role_permissions rp
     join permission_roles r on r.id = rp.role_id
    where r.key = 'contractor_manager' and rp.permission_key = 'calendar.view'), true);

\echo '--- §4: קישור ההתראה אינו מפצל עוד לפי סוג משתמש ---'
select t_eq('משימה מובילה ללוח גם לקבלן',
  app.notification_link('20000000-0000-0000-0000-0000000014a1', 'task_assigned', 'task',
                        '31000000-0000-0000-0000-000000140001')
    like '/board?task=%', true);
select t_eq('ולצוות אותו יעד',
  app.notification_link('20000000-0000-0000-0000-0000000014a5', 'task_assigned', 'task',
                        '31000000-0000-0000-0000-000000140001')
    like '/board?task=%', true);

select set_config('request.jwt.claim.sub', '', false);
