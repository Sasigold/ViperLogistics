\pset tuples_only on
\pset format unaligned

-- ===========================================================================
-- 17: מה שעובד השטח רואה (0079).
--
-- שלושה נושאים באותה חבילה, כי כולם מתארים את אותו אדם: המפתחות של הכלים
-- שמעל הלוח, זהות הלקוח שנגלית למי שרואה את המשימה, והנסיעה חזרה ששייכת רק
-- למי שיצא מהמחסן.
--
-- החבילה מקימה לקוח, מחסן, אירוע, שני פרופילים ושתי משימות משלה ואינה נשענת
-- על אף חבילה קודמת. האירוע יושב ב-current_date + 320 כדי שלא ייתפס בטווחים
-- של חבילות הדשבורד, הדוחות והמפרטים.
-- ===========================================================================

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000017a1', 'field-worker@vl.test'),
  ('00000000-0000-0000-0000-0000000017a2', 'field-dispatcher@vl.test');

insert into warehouses (id, name, lat, lng) values
  ('40000000-0000-0000-0000-000000000017', 'מחסן עובד השטח', 32.05, 34.77);

insert into customers (id, name, color, contact_phone, warehouse_id) values
  ('10000000-0000-0000-0000-000000000017', 'לקוח עובד השטח', '#123456', '050-0000017',
   '40000000-0000-0000-0000-000000000017');

insert into profiles (id, user_id, user_kind, is_admin, full_name) values
  ('20000000-0000-0000-0000-0000000017a1', '00000000-0000-0000-0000-0000000017a1',
   'staff', false, 'עובד כללי'),
  ('20000000-0000-0000-0000-0000000017a2', '00000000-0000-0000-0000-0000000017a2',
   'staff', false, 'רכז שיבוצים');

insert into profile_roles (profile_id, role_id)
select '20000000-0000-0000-0000-0000000017a1', id from permission_roles where key = 'worker';
insert into profile_roles (profile_id, role_id)
select '20000000-0000-0000-0000-0000000017a2', id from permission_roles where key = 'dispatcher';

insert into events (id, customer_id, end_client_name, event_date,
                    location_text, location_lat, location_lng) values
  ('30000000-0000-0000-0000-000000000017', '10000000-0000-0000-0000-000000000017',
   'לקוח הקצה של עובד השטח', current_date + 320, 'תל אביב', 32.0853, 34.7818);

-- שתי משמרות בשני ימים, כדי שהמיזוג לא יאחד אותן:
--   A — יוצא מהמחסן ב-06:00, בשטח 07:00, שלוש שעות, חצי שעה נסיעה
--   B — מגיע לשטח ב-08:00, שעתיים, שלושת רבעי שעה נסיעה
insert into tasks (id, event_id, customer_id, task_type_id, task_date,
                   warehouse_start_time, onsite_start_time, hours_count,
                   travel_hours, status_id, worker_count)
select v.id, '30000000-0000-0000-0000-000000000017',
       '10000000-0000-0000-0000-000000000017',
       (select id from task_types where code = 'setup' limit 1),
       v.d, v.wh, v.onsite, v.hrs, v.travel,
       (select id from statuses where entity = 'task' and code = 'assigned' and deleted_at is null),
       1
from (values
  ('61000000-0000-0000-0000-000000017001'::uuid, (current_date + 320)::date,
   '06:00'::time, '07:00'::time, 3.0::numeric, 0.5::numeric),
  ('61000000-0000-0000-0000-000000017002'::uuid, (current_date + 321)::date,
   null::time,    '08:00'::time, 2.0::numeric, 0.75::numeric)
) as v(id, d, wh, onsite, hrs, travel);

insert into task_assignments (task_id, profile_id, role, work_site) values
  ('61000000-0000-0000-0000-000000017001', '20000000-0000-0000-0000-0000000017a1', 'worker', 'warehouse'),
  ('61000000-0000-0000-0000-000000017002', '20000000-0000-0000-0000-0000000017a1', 'worker', 'field');

-- ===== 1. הכלים שמעל הלוח הם מפתח, ולא ברירת מחדל של המסך ==================

\echo '--- העובד: אירוע כן, כלי תכנון לא ---'
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000017a1', false);

select t_eq('העובד פותח את דף האירוע',        app.has('events.view'), true);
select t_eq('בלי סינון בלוח שנה',              app.has('calendar.filter'), false);
select t_eq('בלי שמירת סינון',                 app.has('calendar.save_filters'), false);
select t_eq('בלי סינון בלו״ז',                 app.has('board.filter'), false);
select t_eq('בלי פתיחת כרטיס משימה',           app.has('board.open_task'), false);
select t_eq('ובלי בורר התצוגה והשדות',         app.has('board.columns'), false);
-- מה שכן: המסכים עצמם, ומה שהעובד עושה בהם
select t_eq('אבל הלו״ז עצמו פתוח',             app.has('board.view'), true);
select t_eq('וגם לוח השנה',                    app.has('calendar.view'), true);

reset role;
select set_config('request.jwt.claim.sub', '', false);

\echo '--- הרכז ממשיך להחזיק את שלושתם, בלי שהוענקו לו ---'
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000017a2', false);

-- implied_by של מפתח הגישה: מי שכבר פותח את המסך מקבל את הכלים שבו בלי
-- שורת הענקה, וזו כל הסיבה שהמפתחות החדשים אינם שוברים תפקיד קיים.
select t_eq('הרכז מסנן בלוח שנה',              app.has('calendar.filter'), true);
select t_eq('הרכז מסנן בלו״ז',                 app.has('board.filter'), true);
select t_eq('והרכז פותח כרטיס משימה',          app.has('board.open_task'), true);

reset role;
select set_config('request.jwt.claim.sub', '', false);

-- ===== 2. זהות הלקוח נגלית למי שרואה את המשימה =============================

\echo '--- שם הלקוח במערכת, בלי לפתוח את מודול הלקוחות ---'
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000017a1', false);

select t_eq('העובד קורא את שם הלקוח מהלו״ז',
  (select customer_name from work_board_view where id = '61000000-0000-0000-0000-000000017001'),
  'לקוח עובד השטח');

select t_eq('וגם את הצבע שלו',
  (select customer_color from work_board_view where id = '61000000-0000-0000-0000-000000017001'),
  '#123456');

select t_eq('לצד שם לקוח האירוע, שכבר היה שם',
  (select end_client_name from work_board_view where id = '61000000-0000-0000-0000-000000017001'),
  'לקוח הקצה של עובד השטח');

-- הזהות ולא השורה: הטבלה עצמה נשארת סגורה, ואיתה פרטי הקשר והתמחור.
select t_eq('אך טבלת הלקוחות עצמה נשארת סגורה לו',
  (select count(*)::int from customers where id = '10000000-0000-0000-0000-000000000017'), 0);
select t_eq('ואין לו customers.view', app.has('customers.view'), false);

select t_eq('משימה שאינה שלו אינה מחזירה לו שם לקוח — היא אינה מחזירה שורה',
  (select count(*)::int from work_board_view
    where customer_id = '10000000-0000-0000-0000-000000000017'), 2);

reset role;
select set_config('request.jwt.claim.sub', '', false);

-- ===== 3. הנסיעה חזרה שייכת למי שיצא מהמחסן ================================

\echo '--- הנסיעה חזרה, והסיום שמסכים עם עצמו ---'
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000017a1', false);

-- 07:00 + 3 שעות = 10:00, ועוד חצי שעה חזרה למחסן
select t_eq('היוצא מהמחסן מסיים אחרי הנסיעה חזרה',
  (select to_char(shift_end at time zone 'Asia/Jerusalem', 'HH24:MI')
     from app.planned_shifts('20000000-0000-0000-0000-0000000017a1',
       current_date + 320, current_date + 320)), '10:30');

select t_eq('והמשמרת מתחילה בשעת המחסן',
  (select to_char(shift_start at time zone 'Asia/Jerusalem', 'HH24:MI')
     from app.planned_shifts('20000000-0000-0000-0000-0000000017a1',
       current_date + 320, current_date + 320)), '06:00');

-- 08:00 + 2 שעות = 10:00, ולא 10:45: אין לאן לחזור
select t_eq('המגיע לשטח מסיים בשטח',
  (select to_char(shift_end at time zone 'Asia/Jerusalem', 'HH24:MI')
     from app.planned_shifts('20000000-0000-0000-0000-0000000017a1',
       current_date + 321, current_date + 321)), '10:00');

select t_eq('והנסיעה שלו אינה נספרת',
  (select travel_hours from app.planned_shifts('20000000-0000-0000-0000-0000000017a1',
     current_date + 321, current_date + 321)), 0::numeric);

select t_eq('אף שהמשימה עצמה נושאת זמן נסיעה',
  (select app.task_travel_hours('61000000-0000-0000-0000-000000017002')), 0.75::numeric);

select t_eq('ולכן המשמרת שלו היא שעתיים בדיוק',
  (select planned_hours from app.planned_shifts('20000000-0000-0000-0000-0000000017a1',
     current_date + 321, current_date + 321)), 2.00::numeric);

-- הפירוק והגזירה הם אותו מספר. זה הדיווח שפתח את 0079 §5.
select t_eq('פירוק המשמרת נגמר באותה שעה שהגזירה קבעה — במחסן',
  (shift_task_breakdown('20000000-0000-0000-0000-0000000017a1',
     array['61000000-0000-0000-0000-000000017001']::uuid[]) -> 'shift' ->> 'end')::timestamptz,
  (select shift_end from app.planned_shifts('20000000-0000-0000-0000-0000000017a1',
     current_date + 320, current_date + 320)));

select t_eq('וגם בשטח',
  (shift_task_breakdown('20000000-0000-0000-0000-0000000017a1',
     array['61000000-0000-0000-0000-000000017002']::uuid[]) -> 'shift' ->> 'end')::timestamptz,
  (select shift_end from app.planned_shifts('20000000-0000-0000-0000-0000000017a1',
     current_date + 321, current_date + 321)));

select t_eq('והנסיעה במגירה זהה לזו שבגזירה',
  (shift_task_breakdown('20000000-0000-0000-0000-0000000017a1',
     array['61000000-0000-0000-0000-000000017002']::uuid[]) -> 'totals' ->> 'travel_hours')::numeric,
  0::numeric);

select t_eq('ובמשמרת שיצאה מהמחסן היא חצי שעה',
  (shift_task_breakdown('20000000-0000-0000-0000-0000000017a1',
     array['61000000-0000-0000-0000-000000017001']::uuid[]) -> 'totals' ->> 'travel_hours')::numeric,
  0.5::numeric);

-- הפירוק נושא את שם הלקוח מאז 0034 (security definer), והוא זהה למה
-- שהלו״ז מראה עכשיו — שני נתיבים, תשובה אחת.
select t_eq('ושם הלקוח בפירוק זהה לזה שבלו״ז',
  (shift_task_breakdown('20000000-0000-0000-0000-0000000017a1',
     array['61000000-0000-0000-0000-000000017001']::uuid[]) -> 'tasks' -> 0 ->> 'customer_name'),
  (select customer_name from work_board_view where id = '61000000-0000-0000-0000-000000017001'));

reset role;
select set_config('request.jwt.claim.sub', '', false);

-- ===========================================================================
-- 0082: הגבולות של הצוות, והתפקיד של ראש הצוות באירוע
-- ===========================================================================

-- עוד שני אנשים באותו קהל: ראש צוות *באירוע* (תפקיד השיבוץ, לא תפקיד
-- ההרשאה — שניהם מחזיקים את אותו "עובד"), ועובד שמשובץ לשטח בלבד.
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000017a3', 'field-lead@vl.test'),
  ('00000000-0000-0000-0000-0000000017a4', 'field-onsite@vl.test');

insert into profiles (id, user_id, user_kind, is_admin, full_name) values
  ('20000000-0000-0000-0000-0000000017a3', '00000000-0000-0000-0000-0000000017a3',
   'staff', false, 'ראש צוות באירוע'),
  ('20000000-0000-0000-0000-0000000017a4', '00000000-0000-0000-0000-0000000017a4',
   'staff', false, 'עובד שמגיע לשטח');

insert into profile_roles (profile_id, role_id)
select p, id from permission_roles r,
  unnest(array['20000000-0000-0000-0000-0000000017a3'::uuid,
               '20000000-0000-0000-0000-0000000017a4'::uuid]) p
where r.key = 'worker';

insert into task_assignments (task_id, profile_id, role, work_site) values
  ('61000000-0000-0000-0000-000000017001', '20000000-0000-0000-0000-0000000017a3', 'team_lead', 'warehouse'),
  ('61000000-0000-0000-0000-000000017002', '20000000-0000-0000-0000-0000000017a4', 'worker', 'field');

insert into event_contacts (event_id, contact_name, contact_phone) values
  ('30000000-0000-0000-0000-000000000017', 'איש הקשר של הלקוח', '050-1700017');

-- אירוע שני, שהמשימה בו היא **טיוטה**: העובד משובץ אליה, וזה בדיוק המצב
-- שבו הוא ראה אותו בלוח השנה עד 0082.
insert into events (id, customer_id, end_client_name, event_date,
                    location_text, location_lat, location_lng) values
  ('30000000-0000-0000-0000-000000017018', '10000000-0000-0000-0000-000000000017',
   'אירוע שעוד לא פורסם', current_date + 322, 'תל אביב', 32.0853, 34.7818);

insert into tasks (id, event_id, customer_id, task_type_id, task_date,
                   onsite_start_time, hours_count, status_id, worker_count)
select '61000000-0000-0000-0000-000000017003', '30000000-0000-0000-0000-000000017018',
       '10000000-0000-0000-0000-000000000017',
       (select id from task_types where code = 'setup' limit 1),
       current_date + 322, '09:00', 2.0,
       (select id from statuses where entity = 'task' and code = 'draft' and deleted_at is null),
       1;

insert into task_assignments (task_id, profile_id, role, work_site) values
  ('61000000-0000-0000-0000-000000017003', '20000000-0000-0000-0000-0000000017a1', 'worker', 'field');

-- ===== 4. רק מה שפורסם — גם באירוע ולא רק במשימה ==========================

\echo '--- טיוטה אינה מזמינה את האירוע ללוח השנה ---'
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000017a1', false);

select t_eq('העובד אינו רואה את המשימה שבטיוטה',
  (select count(*)::int from tasks where id = '61000000-0000-0000-0000-000000017003'), 0);

select t_eq('וגם לא את האירוע שלה — זה מה ש-0082 סוגר',
  (select count(*)::int from events where id = '30000000-0000-0000-0000-000000017018'), 0);

select t_eq('אבל את האירוע שמשימותיו פורסמו הוא כן רואה',
  (select count(*)::int from events where id = '30000000-0000-0000-0000-000000000017'), 1);

select t_eq('ואת שתי המשימות שלו בו',
  (select count(*)::int from work_board_view
    where event_id = '30000000-0000-0000-0000-000000000017'), 2);

\echo '--- דף רשימת האירועים נסגר, דף האירוע נשאר ---'
select t_eq('אין לעובד events.list', app.has('events.list'), false);
select t_eq('אך events.view נשאר',   app.has('events.view'), true);

\echo '--- והדלת שנפתחה ב-0079 נסגרה: event_visible אינה "כל אירוע" ---'
select t_eq('האירוע שהוא משובץ אליו גלוי לו',
  app.event_visible('30000000-0000-0000-0000-000000000017'), true);
select t_eq('והאירוע שאינו שלו — לא',
  app.event_visible('30000000-0000-0000-0000-000000017018'), false);

reset role;
select set_config('request.jwt.claim.sub', '', false);

-- ===== 5. ראש הצוות של האירוע =============================================

\echo '--- עובד מן השורה: בלי יומן ובלי איש קשר ---'
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000017a1', false);

select t_eq('העובד אינו רואה את יומן האירוע',
  (select count(*)::int from event_activity
    where event_id = '30000000-0000-0000-0000-000000000017'), 0);

select t_eq('ואינו רואה את איש הקשר',
  (select count(*)::int from event_contacts
    where event_id = '30000000-0000-0000-0000-000000000017'), 0);

select t_rows('ואינו יכול לתעד', $$
  insert into event_activity (event_id, kind, actor_profile_id, note)
  values ('30000000-0000-0000-0000-000000000017', 'note',
          '20000000-0000-0000-0000-0000000017a1', 'לא אמור להיכתב')$$, 0);

reset role;
select set_config('request.jwt.claim.sub', '', false);

\echo '--- ראש הצוות של האירוע: יומן, תיעוד ואיש קשר ---'
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000017a3', false);

select t_eq('הוא מזוהה כראש צוות באירוע',
  app.is_event_team_lead('30000000-0000-0000-0000-000000000017'), true);

select t_expect_ok('והוא מתעד', $$
  insert into event_activity (event_id, kind, actor_profile_id, note)
  values ('30000000-0000-0000-0000-000000000017', 'note',
          '20000000-0000-0000-0000-0000000017a3', 'הצוות יצא מהמחסן בזמן')$$);

select t_eq('ורואה את מה שכתב',
  (select count(*)::int from event_activity
    where event_id = '30000000-0000-0000-0000-000000000017' and kind = 'note'), 1);

select t_eq('ורואה את שם איש הקשר',
  (select contact_name from event_contacts
    where event_id = '30000000-0000-0000-0000-000000000017'), 'איש הקשר של הלקוח');

select t_eq('ואת הטלפון',
  (select contact_phone from event_contacts
    where event_id = '30000000-0000-0000-0000-000000000017'), '050-1700017');

select t_eq('אבל הוא אינו ראש צוות באירוע שאינו שלו',
  app.is_event_team_lead('30000000-0000-0000-0000-000000017018'), false);

-- המסך מכריע את אותה שאלה מ-`team_lead_id` שבלו״ז, בלי שאילתה נוספת, ולכן
-- העמודה הזו חייבת להגיע אליו מלאה — ‏`ta_select` היא שמתירה אותה.
select t_eq('והלו״ז מחזיר לו את עצמו כראש הצוות של המשימה',
  (select team_lead_id from work_board_view where id = '61000000-0000-0000-0000-000000017001'),
  '20000000-0000-0000-0000-0000000017a3');

reset role;
select set_config('request.jwt.claim.sub', '', false);

-- ===== 6. יציאה מהמחסן ====================================================
--
-- המחסן (32.05, 34.77) והאתר (32.0853, 34.7818) מרוחקים כ-4 ק״מ זה מזה,
-- כלומר הרבה מעבר לרדיוס. זה מה שהופך את הבדיקה לחד-משמעית.
--
-- המשמרות של החבילה יושבות ב-current_date+320, ו-`app.shift_at` מחפשת יום
-- אחד לכל צד מ-`now()` — ולכן לשעון נדרש אירוע של **היום**, אחרת אין מול מה
-- למדוד והבדיקה עוברת בלי שנגעה בכלום.

insert into events (id, customer_id, end_client_name, event_date,
                    location_text, location_lat, location_lng) values
  ('30000000-0000-0000-0000-000000017019', '10000000-0000-0000-0000-000000000017',
   'אירוע השעון', current_date, 'תל אביב', 32.0853, 34.7818);

insert into tasks (id, event_id, customer_id, task_type_id, task_date,
                   warehouse_start_time, onsite_start_time, hours_count,
                   travel_hours, status_id, worker_count)
select v.id, '30000000-0000-0000-0000-000000017019',
       '10000000-0000-0000-0000-000000000017',
       (select id from task_types where code = 'setup' limit 1),
       current_date, v.wh, v.onsite, v.hrs, 0.5,
       (select id from statuses where entity = 'task' and code = 'assigned' and deleted_at is null),
       1
from (values
  ('61000000-0000-0000-0000-000000017004'::uuid, '06:00'::time, '07:00'::time, 3.0::numeric),
  ('61000000-0000-0000-0000-000000017005'::uuid, null::time,    '08:00'::time, 2.0::numeric)
) as v(id, wh, onsite, hrs);

insert into task_assignments (task_id, profile_id, role, work_site) values
  ('61000000-0000-0000-0000-000000017004', '20000000-0000-0000-0000-0000000017a1', 'worker', 'warehouse'),
  ('61000000-0000-0000-0000-000000017005', '20000000-0000-0000-0000-0000000017a4', 'worker', 'field');

insert into worker_pay_settings (profile_id, hourly_rate, requires_location, location_radius_m)
values ('20000000-0000-0000-0000-0000000017a1', 50, true, 300),
       ('20000000-0000-0000-0000-0000000017a4', 50, true, 300)
on conflict (profile_id) do update
   set requires_location = true, location_radius_m = 300;

insert into attendance_entries (profile_id, work_date, clock_in_at) values
  ('20000000-0000-0000-0000-0000000017a1', current_date, now() - interval '4 hours'),
  ('20000000-0000-0000-0000-0000000017a4', current_date, now() - interval '4 hours');

-- שתי המשמרות אכן נגזרו להיום, אחרת כל מה שמתחת בודק "אין מול מה למדוד"
select t_eq('למי שיוצא מהמחסן יש משמרת היום, והיא מתחילה במחסן',
  (select work_site from app.planned_shifts('20000000-0000-0000-0000-0000000017a1',
     current_date, current_date)), 'warehouse');
select t_eq('ולמי שמגיע לשטח — משמרת שמתחילה בשטח',
  (select work_site from app.planned_shifts('20000000-0000-0000-0000-0000000017a4',
     current_date, current_date)), 'field');

\echo '--- מי שיצא מהמחסן מחתים יציאה במחסן ---'
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000017a1', false);

-- זה הדיווח עצמו: עד 0082 היציאה נמדדה מול האתר בלבד, והעובד שעמד במחסן
-- שאליו חזר נחסם.
select t_expect_ok('יציאה מנקודת המחסן מתקבלת', $$
  select attendance_clock_out(32.05, 34.77, 10)$$);

reset role;
select set_config('request.jwt.claim.sub', '', false);

\echo '--- ומי שמגיע לשטח עדיין נמדד מול השטח בלבד ---'
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000017a4', false);

select t_expect_fail('יציאה מהמחסן נדחית למי שכלל לא יצא ממנו', $$
  select attendance_clock_out(32.05, 34.77, 10)$$);

select t_expect_ok('ומהאתר היא מתקבלת', $$
  select attendance_clock_out(32.0853, 34.7818, 10)$$);

reset role;
select set_config('request.jwt.claim.sub', '', false);

-- ===========================================================================
-- 0083: מה שלא פורסם אינו על הלוח, והמשמרת נקראת כמו יום עבודה
-- ===========================================================================

-- הדיווח עצמו: טיוטה ש*חשבון העובד* יצר, ושאיש אינו משובץ אליה.
insert into tasks (id, event_id, customer_id, task_type_id, task_date,
                   onsite_start_time, hours_count, status_id, worker_count, created_by)
select '61000000-0000-0000-0000-000000017006', '30000000-0000-0000-0000-000000017018',
       '10000000-0000-0000-0000-000000000017',
       (select id from task_types where code = 'setup' limit 1),
       current_date + 322, '09:00', 2.0,
       (select id from statuses where entity = 'task' and code = 'draft' and deleted_at is null),
       1, '20000000-0000-0000-0000-0000000017a1';

\echo '--- טיוטה שהעובד יצר אינה על הלו״ז שלו ---'
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000017a1', false);

select t_eq('העובד אינו רואה טיוטה שחשבונו יצר',
  (select count(*)::int from tasks where id = '61000000-0000-0000-0000-000000017006'), 0);

select t_eq('וגם לא בלו״ז עצמו',
  (select count(*)::int from work_board_view where id = '61000000-0000-0000-0000-000000017006'), 0);

reset role;
select set_config('request.jwt.claim.sub', '', false);

-- הצד השני של אותה הכרעה: מי שמזין אירוע בלי tasks.edit ואין לו היקף 'own'
-- ממשיך לראות את הטיוטות שנולדו מהיצירה שלו.
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000017a5', 'field-office@vl.test');
insert into profiles (id, user_id, user_kind, is_admin, full_name) values
  ('20000000-0000-0000-0000-0000000017a5', '00000000-0000-0000-0000-0000000017a5',
   'staff', false, 'מזין אירועים בלי עריכת משימות');
insert into user_permission_grants (profile_id, permission_key, allowed) values
  ('20000000-0000-0000-0000-0000000017a5', 'events.view', true),
  ('20000000-0000-0000-0000-0000000017a5', 'tasks.view', true);

update tasks set created_by = '20000000-0000-0000-0000-0000000017a5'
 where id = '61000000-0000-0000-0000-000000017006';

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000017a5', false);
select t_eq('מי שאין לו היקף own כן רואה את הטיוטה שיצר',
  (select count(*)::int from tasks where id = '61000000-0000-0000-0000-000000017006'), 1);
reset role;
select set_config('request.jwt.claim.sub', '', false);

update tasks set created_by = '20000000-0000-0000-0000-0000000017a1'
 where id = '61000000-0000-0000-0000-000000017006';

-- ===== המשמרת: שלושה מרכיבים, שלוש שורות ==================================

\echo '--- שעת המחסן אינה נבלעת בזמן המשימה ---'
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000017a1', false);

-- משימה 017001: יציאה מהמחסן 06:00, עבודה בשטח 07:00, שלוש שעות.
select t_eq('היציאה מהמחסן היא שדה משלה',
  (select to_char((shift_task_breakdown('20000000-0000-0000-0000-0000000017a1',
     array['61000000-0000-0000-0000-000000017001']::uuid[])
     -> 'tasks' -> 0 ->> 'warehouse_start_at')::timestamptz
     at time zone 'Asia/Jerusalem', 'HH24:MI')), '06:00');

select t_eq('והמשימה מתחילה כשהעבודה מתחילה, לא כשיוצאים',
  (select to_char((shift_task_breakdown('20000000-0000-0000-0000-0000000017a1',
     array['61000000-0000-0000-0000-000000017001']::uuid[])
     -> 'tasks' -> 0 ->> 'start_at')::timestamptz
     at time zone 'Asia/Jerusalem', 'HH24:MI')), '07:00');

select t_eq('שעות העבודה הן של המשימה בלבד — בלי מחסן ובלי נסיעה',
  (shift_task_breakdown('20000000-0000-0000-0000-0000000017a1',
     array['61000000-0000-0000-0000-000000017001']::uuid[])
     -> 'totals' ->> 'work_hours')::numeric, 3.00::numeric);

-- והמשמרת בכללותה עדיין מתחילה במחסן, כמו שהגזירה קובעת
select t_eq('אך תחילת המשמרת נשארת שעת המחסן',
  (shift_task_breakdown('20000000-0000-0000-0000-0000000017a1',
     array['61000000-0000-0000-0000-000000017001']::uuid[]) -> 'shift' ->> 'start')::timestamptz,
  (select shift_start from app.planned_shifts('20000000-0000-0000-0000-0000000017a1',
     current_date + 320, current_date + 320)));

-- מי שמגיע לשטח אין לו יציאה מהמחסן כלל
select t_eq('למי שמגיע לשטח אין שעת מחסן',
  (shift_task_breakdown('20000000-0000-0000-0000-0000000017a1',
     array['61000000-0000-0000-0000-000000017002']::uuid[])
     -> 'tasks' -> 0 ->> 'warehouse_start_at'), null::text);

reset role;
select set_config('request.jwt.claim.sub', '', false);

\echo '--- איש קשר ונקודת התחלה של הצוות: לראש הצוות בלבד ---'
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000017a3', false);

select t_eq('ראש הצוות רואה את איש הקשר מתוך המשימה',
  (shift_task_breakdown('20000000-0000-0000-0000-0000000017a3',
     array['61000000-0000-0000-0000-000000017001']::uuid[])
     -> 'tasks' -> 0 ->> 'contact_name'), 'איש הקשר של הלקוח');

select t_eq('ואת הטלפון',
  (shift_task_breakdown('20000000-0000-0000-0000-0000000017a3',
     array['61000000-0000-0000-0000-000000017001']::uuid[])
     -> 'tasks' -> 0 ->> 'contact_phone'), '050-1700017');

reset role;
select set_config('request.jwt.claim.sub', '', false);

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000017a1', false);
select t_eq('ועובד מן השורה אינו רואה אותו',
  (shift_task_breakdown('20000000-0000-0000-0000-0000000017a1',
     array['61000000-0000-0000-0000-000000017001']::uuid[])
     -> 'tasks' -> 0 ->> 'contact_name'), null::text);
reset role;
select set_config('request.jwt.claim.sub', '', false);

-- ===========================================================================
-- 0084: איחור, השלמה, תוספות ומיקום במילים
-- ===========================================================================

\echo '--- ההשלמה מתקצרת באיחור ---'

-- הדוגמה מהדרישה: מובטחות 6 שעות, המשמרת ב-10:00, הגיע ב-10:15, סיים ב-12:00.
-- עבד 1:45; התקרה יורדת ל-5:45; ולכן ההשלמה היא 4:00 והתשלום 5:45.
select t_eq('התקרה יורדת בדיוק בגובה האיחור',
  (app.attendance_calc(app.attendance_config('attendance.overtime'),
    '{"hours":1.75,"min_hours":6,"hourly_rate":50,"dow":1,"late_minutes":15}'::jsonb)
    ->> 'topup_target')::numeric, 5.75::numeric);

select t_eq('ולכן ההשלמה היא 4:00',
  (app.attendance_calc(app.attendance_config('attendance.overtime'),
    '{"hours":1.75,"min_hours":6,"hourly_rate":50,"dow":1,"late_minutes":15}'::jsonb)
    ->> 'topup_hours')::numeric, 4.00::numeric);

select t_eq('והמשולם הוא 5:45',
  (app.attendance_calc(app.attendance_config('attendance.overtime'),
    '{"hours":1.75,"min_hours":6,"hourly_rate":50,"dow":1,"late_minutes":15}'::jsonb)
    ->> 'paid_hours')::numeric, 5.75::numeric);

select t_eq('בלי איחור התקרה נשארת מלאה',
  (app.attendance_calc(app.attendance_config('attendance.overtime'),
    '{"hours":1.75,"min_hours":6,"hourly_rate":50,"dow":1,"late_minutes":0}'::jsonb)
    ->> 'paid_hours')::numeric, 6.00::numeric);

-- איחור גדול מהמובטח אינו יכול להוריד את התשלום מתחת למה שנעבד
select t_eq('איחור ענק אינו גוזל שעות שנעבדו',
  (app.attendance_calc(app.attendance_config('attendance.overtime'),
    '{"hours":1.75,"min_hours":6,"hourly_rate":50,"dow":1,"late_minutes":600}'::jsonb)
    ->> 'paid_hours')::numeric, 1.75::numeric);

\echo '--- ומעל הסף היא נשמטת כליל ---'
select t_eq('איחור מעל הסף מבטל את ההשלמה',
  (app.attendance_calc(app.attendance_config('attendance.overtime'),
    '{"hours":1.75,"min_hours":6,"hourly_rate":50,"dow":1,
      "late_minutes":31,"late_forfeit_minutes":30}'::jsonb)
    ->> 'topup_hours')::numeric, 0::numeric);

select t_eq('והשורה מסומנת ככזו שנשמטה',
  (app.attendance_calc(app.attendance_config('attendance.overtime'),
    '{"hours":1.75,"min_hours":6,"hourly_rate":50,"dow":1,
      "late_minutes":31,"late_forfeit_minutes":30}'::jsonb)
    ->> 'topup_forfeited')::boolean, true);

select t_eq('בדיוק על הסף היא עדיין ניתנת',
  (app.attendance_calc(app.attendance_config('attendance.overtime'),
    '{"hours":1.75,"min_hours":6,"hourly_rate":50,"dow":1,
      "late_minutes":30,"late_forfeit_minutes":30}'::jsonb)
    ->> 'topup_hours')::numeric, 3.75::numeric);

\echo '--- התוספות הן כסף ולא שעות ---'
select t_eq('תוספת ראש צוות ותוספת קבועה נכנסות לסך',
  (app.attendance_calc(app.attendance_config('attendance.overtime'),
    '{"hours":8,"hourly_rate":50,"dow":1,"lead_bonus":120,"shift_bonus":30}'::jsonb)
    ->> 'total')::numeric, 550::numeric);

select t_eq('ואינן מזיזות את השעות',
  (app.attendance_calc(app.attendance_config('attendance.overtime'),
    '{"hours":8,"hourly_rate":50,"dow":1,"lead_bonus":120,"shift_bonus":30}'::jsonb)
    ->> 'paid_hours')::numeric, 8::numeric);

select t_eq('`bonus` הוא סך מה שאינו שעות',
  (app.attendance_calc(app.attendance_config('attendance.overtime'),
    '{"hours":8,"hourly_rate":50,"dow":1,"bonus":100,"lead_bonus":120,"shift_bonus":30}'::jsonb)
    ->> 'bonus')::numeric, 250::numeric);

select t_eq('ושלושתם שורות נפרדות בפירוט',
  (select count(*)::int from jsonb_array_elements(
     app.attendance_calc(app.attendance_config('attendance.overtime'),
       '{"hours":8,"hourly_rate":50,"dow":1,"bonus":100,"lead_bonus":120,"shift_bonus":30}'::jsonb)
       -> 'lines') l
    where l ->> 'key' in ('bonus', 'lead_bonus', 'shift_bonus')), 3);

select t_eq('סכום השורות שווה לסך גם עם התוספות',
  (select round(sum((l ->> 'amount')::numeric), 2)
     from jsonb_array_elements(app.attendance_calc(app.attendance_config('attendance.overtime'),
       '{"hours":11,"min_hours":12,"hourly_rate":50,"dow":1,"late_minutes":20,
         "bonus":100,"lead_bonus":120,"shift_bonus":30}'::jsonb) -> 'lines') l),
  (app.attendance_calc(app.attendance_config('attendance.overtime'),
    '{"hours":11,"min_hours":12,"hourly_rate":50,"dow":1,"late_minutes":20,
      "bonus":100,"lead_bonus":120,"shift_bonus":30}'::jsonb) ->> 'total')::numeric);

\echo '--- ודיווח ידני נושא מיקום במילים ---'
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000017a3', false);

select t_expect_fail('דיווח בלי מיקום כניסה נדחה', $$
  select attendance_submit_entry(now() - interval '3 days',
                                 now() - interval '3 days' + interval '4 hours',
                                 null, '', 'אתר')$$);

select t_expect_ok('ועם שני המיקומים הוא מתקבל', $$
  select attendance_submit_entry(now() - interval '3 days',
                                 now() - interval '3 days' + interval '4 hours',
                                 null, 'מחסן ראשון לציון', 'היכל התרבות')$$);

reset role;
select set_config('request.jwt.claim.sub', '', false);

select t_eq('המיקום נשמר על הרשומה',
  (select clock_in_place from attendance_entries
    where profile_id = '20000000-0000-0000-0000-0000000017a3' and source = 'manual'
    order by created_at desc limit 1), 'מחסן ראשון לציון');

select t_eq('וגם מיקום היציאה',
  (select clock_out_place from attendance_entries
    where profile_id = '20000000-0000-0000-0000-0000000017a3' and source = 'manual'
    order by created_at desc limit 1), 'היכל התרבות');
