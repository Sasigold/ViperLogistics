\pset tuples_only on
\pset format unaligned

-- ===========================================================================
-- 10: מחזור החיים של סטטוס משימה (0063), ושני הבאגים שנפתחו לצדו —
--     מחיקת אירוע (0061) ומחיקת משימה (0062).
--
-- החבילה מקימה לקוח, אירוע ועובד משלה ואינה נשענת על אף חבילה קודמת: 02
-- הופך את f2 לאדמין ו-06 מזיז מפתחות על f1, ובדיקה על "מה עובד רגיל רואה"
-- שרצה על דמות שמישהו אחר מלביש היא בדיקה שאינה אומרת דבר.
-- ===========================================================================

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000010a1', 'planner@vl.test'),
  ('00000000-0000-0000-0000-0000000010a2', 'fieldworker@vl.test');

insert into customers (id, name) values
  ('10000000-0000-0000-0000-000000000010', 'לקוח מחזור החיים');

insert into profiles (id, user_id, user_kind, is_admin, full_name) values
  ('20000000-0000-0000-0000-0000000010a1', '00000000-0000-0000-0000-0000000010a1',
   'staff', true,  'רכז'),
  -- עובד שטח: tasks.view מגיע לו מברירת המחדל של הקהל, וזו בדיוק הנקודה —
  -- מה שמונע ממנו לראות טיוטה אינו חוסר בהרשאת קריאה אלא הסטטוס עצמו.
  ('20000000-0000-0000-0000-0000000010a2', '00000000-0000-0000-0000-0000000010a2',
   'staff', false, 'עובד שטח');

insert into events (id, customer_id, event_date, location_lat, location_lng) values
  ('30000000-0000-0000-0000-0000000010e1', '10000000-0000-0000-0000-000000000010',
   current_date + 3, 32.0853, 34.7818);

\echo '--- הקטלוג: שלושה סטטוסים, וטיוטה היא ברירת המחדל ---'

select t_eq('נשארו בדיוק שלושה סטטוסי משימה',
  (select count(*)::int from statuses where entity = 'task' and deleted_at is null), 3);

select t_eq('ולשלושתם יש זהות יציבה',
  (select array_agg(code order by sort_order)::text from statuses
    where entity = 'task' and deleted_at is null), '{draft,planned,assigned}');

select t_eq('"בביצוע", "הושלם" ו"בוטל" ירדו',
  (select count(*)::int from statuses
    where entity = 'task' and deleted_at is null
      and name in ('בביצוע', 'הושלם', 'בוטל')), 0);

select t_eq('ולא נשארה אף משימה שמצביעה עליהם',
  (select count(*)::int from tasks t join statuses s on s.id = t.status_id
    where s.entity = 'task' and s.deleted_at is not null), 0);

select t_eq('ברירת המחדל היא טיוטה',
  (select code from statuses where entity = 'task' and is_default and deleted_at is null), 'draft');

-- app.create_default_tasks (0003) פתחה לאירוע הקמה ופירוק ברגע שנוצר, והיא
-- שולפת `where is_default` — כלומר המשימה שנבדקת כאן היא בדיוק מה שהמערכת
-- מייצרת לבדה, ולא מה שהבדיקה הזריעה לעצמה.
create temp table t10 as
select t.id from tasks t
  join task_types tt on tt.id = t.task_type_id
 where t.event_id = '30000000-0000-0000-0000-0000000010e1'
   and tt.code = 'setup' and t.deleted_at is null
 limit 1;
grant select on t10 to authenticated;

select t_eq('משימה שנוצרה עם האירוע נולדה כטיוטה',
  (select s.code from tasks t join statuses s on s.id = t.status_id
    where t.id in (select id from t10)), 'draft');

-- שעות, כדי שתהיה משמרת שאפשר לגזור
update tasks set onsite_start_time = '09:00', hours_count = 4, worker_count = 2
 where id in (select id from t10);

insert into task_assignments (task_id, profile_id, role, work_site)
select id, '20000000-0000-0000-0000-0000000010a2', 'worker', 'field' from t10;

\echo '--- טיוטה: העובד המשובץ לא רואה כלום ---'

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000010a2', false);

select t_eq('העובד אכן מחזיק tasks.view', app.has('tasks.view'), true);
select t_eq('ואינו מתכנן', app.can_plan_tasks(), false);

select t_eq('המשימה שהוא משובץ אליה אינה נראית לו',
  (select count(*)::int from tasks where id in (select id from t10)), 0);
select t_eq('וגם לא דרך לוח העבודה',
  (select count(*)::int from work_board_view where id in (select id from t10)), 0);
reset role;
select set_config('request.jwt.claim.sub', '', false);

select t_eq('ולא נגזרת ממנה משמרת',
  (select count(*)::int from app.planned_shifts(
     '20000000-0000-0000-0000-0000000010a2', current_date, current_date + 7)), 0);

\echo '--- מתוכנן: אותו דבר בדיוק ---'

update tasks set status_id = (select id from statuses
  where entity = 'task' and code = 'planned' and deleted_at is null)
 where id in (select id from t10);

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000010a2', false);
select t_eq('"מתוכנן" עדיין אינו מגיע לעובד',
  (select count(*)::int from tasks where id in (select id from t10)), 0);
reset role;
select set_config('request.jwt.claim.sub', '', false);

select t_eq('וגם לא כמשמרת',
  (select count(*)::int from app.planned_shifts(
     '20000000-0000-0000-0000-0000000010a2', current_date, current_date + 7)), 0);

\echo '--- משובץ: העובד רואה גם בלו״ז וגם בלוח המשמרות ---'

update tasks set status_id = (select id from statuses
  where entity = 'task' and code = 'assigned' and deleted_at is null)
 where id in (select id from t10);

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000010a2', false);
select t_eq('המשימה נפתחה לעובד',
  (select count(*)::int from tasks where id in (select id from t10)), 1);
select t_eq('והיא בלו״ז',
  (select count(*)::int from work_board_view where id in (select id from t10)), 1);
select t_eq('והלוח נושא את זהות הסטטוס',
  (select status_code from work_board_view where id in (select id from t10)), 'assigned');
select t_eq('my_shifts מחזיר לו את המשמרת',
  (select count(*)::int from my_shifts(current_date, current_date + 7)), 1);
reset role;
select set_config('request.jwt.claim.sub', '', false);

\echo '--- הרכז רואה טיוטות לאורך כל הדרך ---'

update tasks set status_id = (select id from statuses
  where entity = 'task' and code = 'draft' and deleted_at is null)
 where id in (select id from t10);

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000010a1', false);
select t_eq('לרכז הטיוטה גלויה',
  (select count(*)::int from work_board_view where id in (select id from t10)), 1);
reset role;
select set_config('request.jwt.claim.sub', '', false);

\echo '--- 0062: משימה שנמחקה יורדת מהלוח, גם למי שמחק ---'

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000010a1', false);
select t_expect_ok('הרכז מוחק את המשימה', $$
  select soft_delete('tasks', (select id from t10))$$);
select t_eq('והיא ירדה מהלוח מיד',
  (select count(*)::int from work_board_view where id in (select id from t10)), 0);
select t_eq('אבל השורה עצמה עדיין שם, לשחזור מסל המיחזור',
  (select count(*)::int from tasks where id in (select id from t10)), 1);
select t_expect_ok('ושחזור מחזיר אותה ללוח', $$
  select soft_delete('tasks', (select id from t10), true)$$);
select t_eq('אכן חזרה',
  (select count(*)::int from work_board_view where id in (select id from t10)), 1);
reset role;
select set_config('request.jwt.claim.sub', '', false);

\echo '--- 0061: מחיקת אירוע ושחזורו ---'
-- הבאג שחזר פעמיים: ה-CASE בין 'restored' ל-'deleted' ב-app.log_event_activity
-- נפתר ל-text, ומ-text ל-enum אין המרה בהשמה — ולכן *כל* UPDATE שנוגע
-- ב-events.deleted_at נפל. הבדיקה כאן היא מה שהיה תופס את שתיהן.

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000010a1', false);
select t_expect_ok('מחיקת אירוע עוברת', $$
  select soft_delete('events', '30000000-0000-0000-0000-0000000010e1')$$);
select t_expect_ok('ושחזורו עובר', $$
  select soft_delete('events', '30000000-0000-0000-0000-0000000010e1', true)$$);
reset role;
select set_config('request.jwt.claim.sub', '', false);

select t_eq('היומן רשם מחיקה ושחזור',
  (select count(*)::int from event_activity
    where event_id = '30000000-0000-0000-0000-0000000010e1'
      and kind in ('deleted', 'restored')), 2);

select t_eq('והאירוע חי בסוף',
  (select deleted_at is null from events
    where id = '30000000-0000-0000-0000-0000000010e1'), true);

\echo '--- 0065: תקרת הדיווח הידני ---'

select t_eq('אורך משמרת מרבי בדיווח עצמי הוא 24 שעות',
  (select (value -> 'self_entry' ->> 'max_hours')::int
     from app_settings where key = 'attendance.clock'), 24);
