\pset tuples_only on
\pset format unaligned

-- ===========================================================================
-- 18: הצוות בשטח — האירוע נפתח, וההיקף הוא השיבוץ (0080, 0081).
--
-- שני תיקונים לאותו קהל, ולכן אותה חבילה:
--
--   * ‏0080: נהג וראש צוות פותחים את דף האירוע כמו העובד. עד כה הלחיצה על
--     אירוע בלוח השנה לא עשתה אצלם דבר, כי `events.view` היה חסום להם.
--   * ‏0081: ההיקף 'own' של איש staff הוא השיבוץ בלבד. הזרוע `created_by`
--     נתנה לעובד שיצר משימה — בייבוא, בבדיקה, או בגלגול קודם — לראות אותה
--     ואת כל אחיותיה באירוע לתמיד, כולל טיוטות שלא פורסמו.
--
-- החבילה מקימה לקוח, אירוע, שלושה אנשי צוות ושלוש משימות משלה ואינה נשענת
-- על אף חבילה קודמת. האירוע יושב ב-current_date + 330 כדי שלא ייתפס בטווח
-- של אף חבילה אחרת.
--
-- הזריעה רצה בלי JWT (auth.uid() = null), ולכן טריגר הפרסום מדלג ואפשר
-- להזריע משימה "משובצת" ישירות.
-- ===========================================================================

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000018a1', 'team-worker@vl.test'),
  ('00000000-0000-0000-0000-0000000018a2', 'team-driver@vl.test'),
  ('00000000-0000-0000-0000-0000000018a3', 'team-lead@vl.test'),
  ('00000000-0000-0000-0000-0000000018a4', 'team-cust@vl.test');

insert into customers (id, name, color) values
  ('10000000-0000-0000-0000-000000000018', 'לקוח הצוות', '#180018');

insert into profiles (id, user_id, user_kind, is_admin, full_name, customer_id) values
  ('20000000-0000-0000-0000-0000000018a1', '00000000-0000-0000-0000-0000000018a1',
   'staff', false, 'עובד שטח', null),
  ('20000000-0000-0000-0000-0000000018a2', '00000000-0000-0000-0000-0000000018a2',
   'staff', false, 'נהג הצוות', null),
  ('20000000-0000-0000-0000-0000000018a3', '00000000-0000-0000-0000-0000000018a3',
   'staff', false, 'ראש הצוות', null),
  ('20000000-0000-0000-0000-0000000018a4', '00000000-0000-0000-0000-0000000018a4',
   'customer_user', false, 'מנהל הלקוח', '10000000-0000-0000-0000-000000000018');

insert into profile_roles (profile_id, role_id)
select p.pid, r.id from (values
  ('20000000-0000-0000-0000-0000000018a1'::uuid, 'worker'),
  ('20000000-0000-0000-0000-0000000018a2'::uuid, 'driver'),
  ('20000000-0000-0000-0000-0000000018a3'::uuid, 'team_lead'),
  ('20000000-0000-0000-0000-0000000018a4'::uuid, 'customer_manager')
) as p(pid, rkey)
join permission_roles r on r.key = p.rkey;

insert into events (id, customer_id, end_client_name, event_date, location_text) values
  ('30000000-0000-0000-0000-000000000018', '10000000-0000-0000-0000-000000000018',
   'לקוח הקצה של הצוות', current_date + 330, 'חיפה');

-- שלוש משימות באותו אירוע:
--   A — משובצת, והעובד רשום עליה
--   B — משובצת, ואיש אינו רשום עליה. זו ה"אחות" שהעובד ראה עד 0081.
--   C — טיוטה ש*העובד עצמו* יצר. זו הזרוע שנסגרה: created_by.
insert into tasks (id, event_id, customer_id, task_type_id, task_date, status_id,
                   worker_count, created_by)
select v.id, '30000000-0000-0000-0000-000000000018',
       '10000000-0000-0000-0000-000000000018',
       (select id from task_types where code = 'setup' limit 1),
       current_date + 330,
       (select id from statuses where entity = 'task' and code = v.code and deleted_at is null),
       1, v.creator
from (values
  ('61000000-0000-0000-0000-000000018001'::uuid, 'assigned', null::uuid),
  ('61000000-0000-0000-0000-000000018002'::uuid, 'assigned', null::uuid),
  ('61000000-0000-0000-0000-000000018003'::uuid, 'draft',
   '20000000-0000-0000-0000-0000000018a1'::uuid)
) as v(id, code, creator);

insert into task_assignments (task_id, profile_id, role, work_site) values
  ('61000000-0000-0000-0000-000000018001', '20000000-0000-0000-0000-0000000018a1', 'worker', 'field'),
  ('61000000-0000-0000-0000-000000018001', '20000000-0000-0000-0000-0000000018a2', 'driver', 'field'),
  ('61000000-0000-0000-0000-000000018001', '20000000-0000-0000-0000-0000000018a3', 'team_lead', 'field');

-- כמה משימות יש באירוע *באמת*. לא שלוש: יצירת האירוע מריצה את בלוק ההקמה
-- והפירוק, ולכן לצד השלוש שהוזרעו כאן יושבות עוד שתיים שהטריגר יצר. המספר
-- נלכד כאן, לפני שנכנסים לתוך RLS, כדי שבדיקת "הלקוח רואה הכול" תמדוד מול
-- המצב בפועל ולא מול מספר שנכתב ביד.
create temp table t18_total as
select count(*)::int as n from tasks where event_id = '30000000-0000-0000-0000-000000000018';
grant select on t18_total to public;

-- ===== 1. שלושת התפקידים פותחים את האירוע (0080) ===========================

\echo '--- נהג וראש צוות פותחים את האירוע, כמו העובד ---'

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000018a2', false);
select t_eq('הנהג פותח את דף האירוע', app.has('events.view'), true);
-- ההכרעה של 0079 נשמרת: לראות את האירוע, לא לערוך אותו ולא לקרוא את יומנו
select t_eq('אך אינו עורך אותו',       app.has('events.edit'), false);
select t_eq('ואת היומן הוא כן קורא (0129)', app.has('events.activity_log'), true);
select t_eq('אך לא את רשומות המערכת שבו',   app.has('events.activity_system_view'), false);
-- ‏0102 הוציא את המפרט מהדחייה הגורפת: מי שנוסע לאירוע קורא את המסמך שלו
select t_eq('ואת המפרט הוא כן רואה',    app.has('events.specs_view'), true);
select t_eq('אך אינו מעלה אותו',        app.has('events.specs_manage'), false);
reset role;
select set_config('request.jwt.claim.sub', '', false);

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000018a3', false);
select t_eq('ראש הצוות פותח את דף האירוע', app.has('events.view'), true);
select t_eq('אף הוא אינו עורך',             app.has('events.edit'), false);
select t_eq('ואת היומן הוא כן קורא (0129)',   app.has('events.activity_log'), true);
select t_eq('אך לא את רשומות המערכת שבו',    app.has('events.activity_system_view'), false);
reset role;
select set_config('request.jwt.claim.sub', '', false);

-- ===== 2. ההיקף הוא השיבוץ, לא היצירה (0081) ===============================

\echo '--- העובד רואה את המשימה שלו, ולא את אחיותיה באירוע ---'

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000018a1', false);

select t_eq('העובד רואה משימה אחת בלבד באירוע',
  (select count(*)::int from tasks where event_id = '30000000-0000-0000-0000-000000000018'), 1);

select t_eq('והיא זו ששובץ אליה',
  (select id from tasks where event_id = '30000000-0000-0000-0000-000000000018'),
  '61000000-0000-0000-0000-000000018001'::uuid);

-- זו העיקר: המשימה שהעובד עצמו יצר אינה שלו לצפייה, כי איש לא שיבץ אותו
select t_eq('הטיוטה שהוא עצמו יצר אינה מוצגת לו',
  (select count(*)::int from tasks where id = '61000000-0000-0000-0000-000000018003'), 0);

select t_eq('וגם לא המשימה המשובצת שאינה שלו',
  (select count(*)::int from tasks where id = '61000000-0000-0000-0000-000000018002'), 0);

-- אותו צמצום בדיוק בלו״ז עצמו, שהוא ה-view שהמסך קורא
select t_eq('ולכן בלו״ז יש לו שורה אחת מהאירוע',
  (select count(*)::int from work_board_view
    where event_id = '30000000-0000-0000-0000-000000000018'), 1);

-- האירוע עצמו נשאר פתוח לו — הוא משובץ למשימה בתוכו
select t_eq('האירוע עצמו נשאר גלוי לו',
  (select count(*)::int from events where id = '30000000-0000-0000-0000-000000000018'), 1);

reset role;
select set_config('request.jwt.claim.sub', '', false);

\echo '--- וכך גם הנהג וראש הצוות ---'

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000018a2', false);
select t_eq('הנהג רואה רק את המשימה ששובץ אליה',
  (select count(*)::int from tasks where event_id = '30000000-0000-0000-0000-000000000018'), 1);
reset role;
select set_config('request.jwt.claim.sub', '', false);

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000018a3', false);
select t_eq('וראש הצוות אף הוא',
  (select count(*)::int from tasks where event_id = '30000000-0000-0000-0000-000000000018'), 1);
reset role;
select set_config('request.jwt.claim.sub', '', false);

-- ===== 3. עובד הלקוח שומר על זרוע היצירה ===================================
--
-- ‏0081 צמצם את 'own' לסוג staff בלבד. מנהל הלקוח יוצר אירועים ורואה אותם
-- מהרגע הראשון, גם לפני שיש בהם משימה ולפני ששובץ מישהו — ולכן הזרוע
-- created_by נשארת לו. הוא אינו נושא היקף 'own' כלל (הוא נתחם לפי
-- customer_id), וזו בדיוק הסיבה שהתיקון אינו נוגע בו.

\echo '--- מנהל הלקוח ממשיך לראות את מה שיצר ---'

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000018a4', false);

select t_eq('מנהל הלקוח רואה את כל משימות האירוע שלו',
  (select count(*)::int from tasks where event_id = '30000000-0000-0000-0000-000000000018'),
  (select n from t18_total));

-- הניגוד החד: אותה טיוטה בדיוק שהעובד שיצר אותה אינו רואה עוד
select t_eq('ובכללן הטיוטה שהעובד יצר',
  (select count(*)::int from tasks where id = '61000000-0000-0000-0000-000000018003'), 1);

select t_eq('ואת האירוע עצמו',
  (select count(*)::int from events where id = '30000000-0000-0000-0000-000000000018'), 1);

reset role;
select set_config('request.jwt.claim.sub', '', false);
