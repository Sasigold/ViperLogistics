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
  ('00000000-0000-0000-0000-0000000014a6', 'c14-dual@vl.test'),
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
   'staff', 'איש צוות', null, null),
  -- **שני כובעים**: מנהל של קבלן ב שגם עובד אצלו (0104). הוא יושב אצל ב
  -- בכוונה, כדי שלא ישנה את מניין הסגל של קבלן א שנספר בסעיף 5.
  ('20000000-0000-0000-0000-0000000014a6', '00000000-0000-0000-0000-0000000014a6',
   'contractor_user', 'מנהל שגם עובד', '11000000-0000-0000-0000-00000000014b', null);

insert into profile_roles (profile_id, role_id)
select p.pid, r.id from (values
  ('20000000-0000-0000-0000-0000000014a1'::uuid, 'contractor_manager'),
  ('20000000-0000-0000-0000-0000000014a2'::uuid, 'contractor_worker'),
  ('20000000-0000-0000-0000-0000000014a3'::uuid, 'contractor_worker'),
  ('20000000-0000-0000-0000-0000000014a5'::uuid, 'worker'),
  ('20000000-0000-0000-0000-0000000014a6'::uuid, 'contractor_manager'),
  ('20000000-0000-0000-0000-0000000014a6'::uuid, 'contractor_worker')
) as p(pid, rkey)
join permission_roles r on r.key = p.rkey;

insert into events (id, customer_id, event_date, location_lat, location_lng) values
  ('30000000-0000-0000-0000-000000000014', '10000000-0000-0000-0000-000000000014',
   current_date + 5, 32.0853, 34.7818);

-- T1 — משימה של קבלן א, עם שעות כדי ש-planned_shifts יוכל לגזור ממנה משמרת.
-- ההאצלה נזרעת כשורת terms (0096) ולא כעמודה: `tasks.contractor_id` הוא שיקוף
-- שהטריגר על ה-terms מתחזק, וזריעה שלו לבדו אינה מאצילה דבר.
insert into tasks (id, event_id, customer_id, task_type_id, task_date, status_id,
                   worker_count, onsite_start_time, hours_count)
select '31000000-0000-0000-0000-000000140001', '30000000-0000-0000-0000-000000000014',
       '10000000-0000-0000-0000-000000000014',
       (select id from task_types where code = 'setup' limit 1),
       current_date + 5,
       (select id from statuses where entity = 'task' and code = 'assigned' and deleted_at is null),
       3, '08:00', 6;

insert into task_contractor_terms (task_id, contractor_id, price)
values ('31000000-0000-0000-0000-000000140001', '11000000-0000-0000-0000-00000000014a', 500);

-- T2 — משימה של קבלן ב
insert into tasks (id, event_id, customer_id, task_type_id, task_date, status_id,
                   worker_count, onsite_start_time, hours_count)
select '31000000-0000-0000-0000-000000140002', '30000000-0000-0000-0000-000000000014',
       '10000000-0000-0000-0000-000000000014',
       (select id from task_types where code = 'setup' limit 1),
       current_date + 5,
       (select id from statuses where entity = 'task' and code = 'assigned' and deleted_at is null),
       2, '08:00', 6;

insert into task_contractor_terms (task_id, contractor_id, price)
values ('31000000-0000-0000-0000-000000140002', '11000000-0000-0000-0000-00000000014b', 500);

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
-- ‏0072 סגר לו את events.view כדי לחסום את הקטלוג ב-/events; ‏0082 הוציא את
-- הקטלוג למפתח משלו, ו-0103 מחזיר לו את דף האירוע עצמו — שם יושבים היומן
-- והמפרט. הקטלוג והייצוא, ששניהם נגזרים ממנו, נשארים סגורים במפורש.
select t_eq('מנהל קבלן: events.view (דף האירוע, 0103)', app.has('events.view'), true);
select t_eq('מנהל קבלן: אין events.list (הקטלוג)',  app.has('events.list'), false);
select t_eq('מנהל קבלן: אין events.export',        app.has('events.export'), false);
select t_eq('מנהל קבלן: יומן האירוע נפתח',          app.has('events.activity_log'), true);
select t_eq('מנהל קבלן: והוא כותב בו',              app.has('events.activity_note'), true);
-- ‏0106: הגדרות השכר והשעון של הסגל חזרו למשרד. מה שנשאר לקבלן במסך "העובדים
-- שלי" הוא לראות את הרשימה ולהוסיף עובד.
select t_eq('מנהל קבלן: אין הגדרות שכר ושעון לסגל', app.has('portal.worker_settings'), false);
select t_eq('מנהל קבלן: אין attendance.manage_pay המשרדי', app.has('attendance.manage_pay'), false);
-- וכלי התכנון שמעל הלו״ז אינם שלו (0106), כמו אצל עובד השטח מאז 0079
select t_eq('מנהל קבלן: אין בורר תצוגה בלו״ז',    app.has('board.columns'), false);
select t_eq('מנהל קבלן: ואין שורת סינון',          app.has('board.filter'), false);
select t_eq('מנהל קבלן: אבל הלוח עצמו נשאר',       app.has('board.view'), true);
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
-- ‏0103: הדחייה על איש הקשר יושבת על קהל הקבלן, וההיתר חוזר על תפקיד המנהל —
-- ‏`can_view_field` קורא תפקיד לפני קהל, ולכן המנהל גובר על העובד.
select t_eq('מנהל קבלן: רואה את איש הקשר של הלקוח',
  app.can_view_field('event', 'contact_phone'), true);

\echo '--- והמפתח אינו מרחיב את מה שהוא רואה: הזרוע שלו נשענת על portal.view ---'
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
-- ‏0103: איש הקשר של הלקוח אינו שלו — לא במגירת המשמרת ולא בשום מקום אחר
select t_eq('עובד קבלן: אינו רואה את שם איש הקשר',
  app.can_view_field('event', 'contact_name'), false);
select t_eq('עובד קבלן: ולא את הטלפון',
  app.can_view_field('event', 'contact_phone'), false);
-- ‏0129: הקהל כולו מתעד ורואה הערות; מה שנשאר סגור הוא רשומות המערכת.
select t_eq('עובד קבלן: כותב ביומן האירוע (0129)', app.has('events.activity_note'), true);
select t_eq('עובד קבלן: אך לא רשומות מערכת',       app.has('events.activity_system_view'), false);
select t_eq('עובד קבלן: ואינו קובע הגדרות לאיש',   app.has('portal.worker_settings'), false);
select t_eq('עובד קבלן: אין בורר תצוגה בלו״ז',     app.has('board.columns'), false);
select t_eq('עובד קבלן: ואין שורת סינון',           app.has('board.filter'), false);

\echo '--- §5: הרשימה המאוחדת של מי שניתן לשבץ ---'
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000014a1', false);

-- שלושה מ-0103: שורת הרוסטר, החשבון שנרשם במשרד, והמנהל עצמו — קבלן קטן הוא
-- לרוב גם העובד הראשון של עצמו, ומי שרק מנהל פשוט לא נבחר מהרשימה.
select t_eq('הרשימה מחזירה את שורת הרוסטר, את החשבון מהמשרד ואת המנהל',
  (select count(*)::int from jsonb_array_elements(contractor_assignable_workers())), 3);
select t_eq('...והחשבון מהמשרד מגיע בלי worker_id',
  (select count(*)::int from jsonb_array_elements(contractor_assignable_workers()) e
    where e->>'full_name' = 'עובד שנרשם במשרד' and e->>'worker_id' is null), 1);
select t_eq('...ושורת הרוסטר מגיעה עם worker_id',
  (select e->>'worker_id' from jsonb_array_elements(contractor_assignable_workers()) e
    where e->>'full_name' = 'עובד מהרוסטר'), '12000000-0000-0000-0000-00000000014a');
select t_eq('מנהל הקבלן עצמו ברשימה, ויכול לשבץ את עצמו (0103)',
  (select count(*)::int from jsonb_array_elements(contractor_assignable_workers()) e
    where e->>'full_name' = 'מנהל קבלן א'), 1);
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
     contractor_assignable_workers('11000000-0000-0000-0000-00000000014b'))), 3);

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

\echo '--- §6: הגדרות שכר ושעון אינן של הקבלן (0106) ---'
-- ‏0103 פתח לו אותן, ו-0106 מחזיר אותן למשרד: הקבלן רואה את הסגל ומוסיף
-- עובד, ותו לא. ה-RPC והזרוע בפוליסה נשארו — שניהם נשענים על המפתח, ולכן מי
-- שאינו מחזיק אותו נדחה בשניהם, ואפשר להעניק אותו במסך ההרשאות בלי מיגרציה.
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000014a1', false);

select t_expect_fail('מנהל קבלן אינו קובע תעריף לעובד מהסגל שלו', $$
  select portal_set_worker_settings('20000000-0000-0000-0000-0000000014a3',
                                    '{"hourly_rate": 55}'::jsonb) $$);
select t_eq('ולא נכתבה שורת הגדרות',
  (select count(*)::int from worker_pay_settings
    where profile_id = '20000000-0000-0000-0000-0000000014a3'), 0);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000014a2', false);
select t_expect_fail('וגם עובד קבלן אינו קובע לעצמו', $$
  select portal_set_worker_settings('20000000-0000-0000-0000-0000000014a2',
                                    '{"hourly_rate": 99}'::jsonb) $$);
reset role;
-- ‏`app.guard_permission_grant` (0014) מדלגת רק כשאין JWT כלל, ולכן הטענה
-- שנשארה מההתחזות הקודמת הייתה חוסמת את ההענקה שלמטה.
select set_config('request.jwt.claim.sub', '', false);

-- והמפתח, כשמעניקים אותו במפורש, עדיין פותח את שני הצדדים — הכתיבה והקריאה.
insert into user_permission_grants (profile_id, permission_key, allowed)
values ('20000000-0000-0000-0000-0000000014a1', 'portal.worker_settings', true)
on conflict (profile_id, permission_key) do update set allowed = true;

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000014a1', false);
select t_expect_ok('מענק אישי מחזיר את היכולת', $$
  select portal_set_worker_settings('20000000-0000-0000-0000-0000000014a3',
                                    '{"hourly_rate": 55, "overtime_enabled": false}'::jsonb) $$);
select t_eq('...והתעריף נשמר',
  (select hourly_rate::text from worker_pay_settings
    where profile_id = '20000000-0000-0000-0000-0000000014a3'), '55.00');
-- עדכון חלקי: מפתח שלא נשלח שומר על ערכו
select t_expect_ok('שמירה שנייה נוגעת רק במה שנשלח', $$
  select portal_set_worker_settings('20000000-0000-0000-0000-0000000014a3',
                                    '{"min_hours_per_shift": 4}'::jsonb) $$);
select t_eq('התעריף לא נמחק',
  (select hourly_rate::text from worker_pay_settings
    where profile_id = '20000000-0000-0000-0000-0000000014a3'), '55.00');
select t_expect_fail('ועדיין אינו קובע דבר לעובד של קבלן אחר', $$
  select portal_set_worker_settings('20000000-0000-0000-0000-0000000014a4',
                                    '{"hourly_rate": 55}'::jsonb) $$);
reset role;
select set_config('request.jwt.claim.sub', '', false);

delete from user_permission_grants
 where profile_id = '20000000-0000-0000-0000-0000000014a1'
   and permission_key = 'portal.worker_settings';

\echo '--- §7: מנהל קבלן שהוא גם עובד (0104) ---'
-- שני התפקידים על אותו אדם. תפקיד העובד סוגר במפורש את מודול הפורטל, ומנהל
-- הקבלן קיבל את `portal.attendance` מברירת המחדל של הקהל — שכבה שמדברת *אחרי*
-- התפקידים. התוצאה עד 0104: דחיית העובד ניצחה, והמנהל איבד את דוח העובדים.
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000014a6', false);

select t_eq('התפקיד האפקטיבי הוא המנהל בלבד',
  (select string_agg(r.key, ',') from permission_roles r where r.id = any(app.my_role_ids())),
  'contractor_manager');
select t_eq('ולכן דוח העובדים נשאר פתוח לו', app.has('portal.attendance'), true);
select t_eq('וגם שאר הפורטל',                app.has('portal.view'), true);
select t_eq('ואישור נוכחות של הסגל',          app.has('portal.approve_attendance'), true);
-- ומה שהעובד נותן לא נלקח: הוא עדיין מחתים שעון, מדווח ידנית ורואה את שכרו
select t_eq('הוא עדיין מחתים שעון',           app.has('attendance.clock'), true);
select t_eq('מדווח נוכחות ידנית',             app.has('attendance.submit_entry'), true);
select t_eq('ורואה את השכר של עצמו',          app.has('attendance.view_own_pay'), true);
-- והכובע המנהל גובר גם בשכבת השדות (0103)
select t_eq('ואיש הקשר גלוי לו כמנהל',        app.can_view_field('event', 'contact_phone'), true);
reset role;

\echo '--- §4: קישור ההתראה אינו מפצל עוד לפי סוג משתמש ---'
select t_eq('משימה מובילה ללוח גם לקבלן',
  app.notification_link('20000000-0000-0000-0000-0000000014a1', 'task_assigned', 'task',
                        '31000000-0000-0000-0000-000000140001')
    like '/board?task=%', true);
select t_eq('ולצוות אותו יעד',
  app.notification_link('20000000-0000-0000-0000-0000000014a5', 'task_assigned', 'task',
                        '31000000-0000-0000-0000-000000140001')
    like '/board?task=%', true);

-- 0110: התראות הכניסה/יציאה מובילות לדוח הנוכחות — המסך של מי שמקבל אותן,
-- מנהל ומנהל קבלן כאחד (שניהם על /attendance, בהיקפים שונים).
select t_eq('התראת כניסה מובילה לדוח הנוכחות',
  app.notification_link('20000000-0000-0000-0000-0000000014a1', 'attendance_clock_in',
                        'attendance_entry', gen_random_uuid())
    like '/attendance?entry=%', true);

select set_config('request.jwt.claim.sub', '', false);
