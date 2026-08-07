\pset tuples_only on
\pset format unaligned

-- ================= זריעה =================
-- שני עובדי צוות, קבלן עם עובד אחד שיש לו התחברות, ואירוע ממוקם בתל אביב.

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000f3', 'clock@vl.test'),
  ('00000000-0000-0000-0000-0000000000f4', 'manager@vl.test'),
  ('00000000-0000-0000-0000-0000000000b1', 'kablan@vl.test'),
  ('00000000-0000-0000-0000-0000000000b2', 'kworker@vl.test');

insert into contractors (id, name) values
  ('40000000-0000-0000-0000-000000000001', 'קבלן הנוכחות');

insert into contractor_workers (id, contractor_id, full_name, user_id) values
  ('50000000-0000-0000-0000-000000000001', '40000000-0000-0000-0000-000000000001',
   'עובד הקבלן', '00000000-0000-0000-0000-0000000000b2');

insert into profiles (id, user_id, user_kind, full_name, contractor_id, contractor_worker_id) values
  ('20000000-0000-0000-0000-0000000000f3', '00000000-0000-0000-0000-0000000000f3',
   'staff', 'עובד שעון', null, null),
  ('20000000-0000-0000-0000-0000000000f4', '00000000-0000-0000-0000-0000000000f4',
   'staff', 'מנהל נוכחות', null, null),
  ('20000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-0000000000b1',
   'contractor_user', 'מנהל הקבלן', '40000000-0000-0000-0000-000000000001', null),
  ('20000000-0000-0000-0000-0000000000b2', '00000000-0000-0000-0000-0000000000b2',
   'contractor_user', 'עובד הקבלן', '40000000-0000-0000-0000-000000000001',
   '50000000-0000-0000-0000-000000000001');

insert into user_permission_grants (profile_id, permission_key, allowed) values
  ('20000000-0000-0000-0000-0000000000f4', 'attendance.view_all',   true),
  ('20000000-0000-0000-0000-0000000000f4', 'attendance.edit_entry', true),
  ('20000000-0000-0000-0000-0000000000f4', 'attendance.manual_entry', true),
  -- מנהל המשמרות רואה שעות ובמפורש *לא* כסף
  ('20000000-0000-0000-0000-0000000000f4', 'attendance.view_pay',   false),
  ('20000000-0000-0000-0000-0000000000b1', 'portal.attendance',     true);

-- אירוע בתל אביב, ומשימות שמרכיבות את המשמרות
insert into events (id, customer_id, event_date, location_lat, location_lng) values
  ('30000000-0000-0000-0000-00000000a001', '10000000-0000-0000-0000-000000000001',
   current_date, 32.0853, 34.7818);

insert into tasks (id, event_id, task_type_id, task_date, warehouse_start_time,
                   onsite_start_time, hours_count, travel_hours, status_id, worker_count)
select v.id, '30000000-0000-0000-0000-00000000a001',
       (select id from task_types where code = 'setup'),
       current_date, v.wh, v.onsite, v.hrs, v.travel,
       (select id from statuses where entity = 'task' and is_default), 2
from (values
  -- שתי משימות בפער 90 דקות: 08:00–10:00 ואז 11:30–13:30 ⇒ משמרת אחת
  ('60000000-0000-0000-0000-00000000a001'::uuid, '07:00'::time, '08:00'::time, 2.0::numeric, 0.5::numeric),
  ('60000000-0000-0000-0000-00000000a002'::uuid, null::time,    '11:30'::time, 2.0::numeric, 0.5::numeric),
  -- משימה רחוקה באותו יום: מתחילה 18:00 ⇒ משמרת נפרדת
  ('60000000-0000-0000-0000-00000000a003'::uuid, null::time,    '18:00'::time, 1.0::numeric, 0.25::numeric)
) as v(id, wh, onsite, hrs, travel);

-- משימה חוצת חצות, למחר
insert into tasks (id, event_id, task_type_id, task_date, onsite_start_time, hours_count,
                   travel_hours, status_id, worker_count)
values ('60000000-0000-0000-0000-00000000a004', '30000000-0000-0000-0000-00000000a001',
        (select id from task_types where code = 'teardown'), current_date + 1,
        '22:00', 4.0, 0, (select id from statuses where entity = 'task' and is_default), 1);

-- העובד יוצא מהמחסן במשימה הראשונה, ובשטח בשאר
insert into task_assignments (task_id, profile_id, role, work_site) values
  ('60000000-0000-0000-0000-00000000a001', '20000000-0000-0000-0000-0000000000f3', 'worker', 'warehouse'),
  ('60000000-0000-0000-0000-00000000a002', '20000000-0000-0000-0000-0000000000f3', 'worker', 'field'),
  ('60000000-0000-0000-0000-00000000a003', '20000000-0000-0000-0000-0000000000f3', 'worker', 'field'),
  ('60000000-0000-0000-0000-00000000a004', '20000000-0000-0000-0000-0000000000f3', 'worker', 'field');

-- עובד הקבלן משובץ דרך הטבלה שלו, ולא דרך task_assignments
insert into task_contractor_workers (task_id, contractor_worker_id, work_site) values
  ('60000000-0000-0000-0000-00000000a001', '50000000-0000-0000-0000-000000000001', 'field');

insert into worker_pay_settings (profile_id, hourly_rate, overtime_enabled, min_hours_per_shift)
values ('20000000-0000-0000-0000-0000000000f3', 50, true, null);

-- ================= 1. מנוע השכר (אריתמטיקה טהורה) =================

\echo '--- מנוע השכר ---'

select t_eq('8 שעות בתעריף 50 = 400',
  (app.attendance_calc(app.attendance_config('attendance.overtime'),
    '{"hours":8,"hourly_rate":50,"dow":1}'::jsonb) ->> 'total')::numeric, 400::numeric);

-- 8×50 + 2×62.5 + 1×75 = 400 + 125 + 75 = 600
select t_eq('11 שעות = 600 (8 רגילות, 2 ב-125%, 1 ב-150%)',
  (app.attendance_calc(app.attendance_config('attendance.overtime'),
    '{"hours":11,"hourly_rate":50,"dow":1}'::jsonb) ->> 'total')::numeric, 600::numeric);

select t_eq('מתוכן 3 שעות נוספות',
  (app.attendance_calc(app.attendance_config('attendance.overtime'),
    '{"hours":11,"hourly_rate":50,"dow":1}'::jsonb) ->> 'overtime_hours')::numeric, 3::numeric);

select t_eq('עובד שאינו זכאי לשעות נוספות מקבל 11×50 = 550',
  (app.attendance_calc(app.attendance_config('attendance.overtime'),
    '{"hours":11,"hourly_rate":50,"dow":1,"overtime_enabled":false}'::jsonb) ->> 'total')::numeric,
  550::numeric);

-- הדוגמה מהדרישה: השלמה ל-6 שעות על משמרת של 5
\echo '--- השלמה לשעות ---'
select t_eq('משמרת 5 שעות עם השלמה ל-6 משולמת כ-6',
  (app.attendance_calc(app.attendance_config('attendance.overtime'),
    '{"hours":5,"min_hours":6,"hourly_rate":50,"dow":1}'::jsonb) ->> 'paid_hours')::numeric,
  6::numeric);

select t_eq('ובכסף: 6×50 = 300',
  (app.attendance_calc(app.attendance_config('attendance.overtime'),
    '{"hours":5,"min_hours":6,"hourly_rate":50,"dow":1}'::jsonb) ->> 'total')::numeric, 300::numeric);

select t_eq('שורת ההשלמה היא שעה אחת',
  (app.attendance_calc(app.attendance_config('attendance.overtime'),
    '{"hours":5,"min_hours":6,"hourly_rate":50,"dow":1}'::jsonb) ->> 'topup_hours')::numeric,
  1::numeric);

-- ההשלמה לא נכנסת למדרגות: אחרת "מובטחות 10, עבד 0" היה מייצר שעות נוספות
select t_eq('השלמה אינה מייצרת שעות נוספות פיקטיביות',
  (app.attendance_calc(app.attendance_config('attendance.overtime'),
    '{"hours":0.5,"min_hours":10,"hourly_rate":50,"dow":1}'::jsonb) ->> 'overtime_hours')::numeric,
  0::numeric);

select t_eq('מי שעבד יותר מהמינימום אינו מקבל השלמה',
  (app.attendance_calc(app.attendance_config('attendance.overtime'),
    '{"hours":7,"min_hours":6,"hourly_rate":50,"dow":1}'::jsonb) ->> 'topup_hours')::numeric,
  0::numeric);

\echo '--- יום מנוחה ועיגול ---'
-- שבת: 8 שעות ב-150% ⇒ 8×1.5×50 = 600
select t_eq('שבת: 8 שעות = 600',
  (app.attendance_calc(app.attendance_config('attendance.overtime'),
    '{"hours":8,"hourly_rate":50,"dow":6}'::jsonb) ->> 'total')::numeric, 600::numeric);

select t_eq('שבת מסומנת כיום מנוחה',
  (app.attendance_calc(app.attendance_config('attendance.overtime'),
    '{"hours":8,"hourly_rate":50,"dow":6}'::jsonb) ->> 'is_rest_day')::boolean, true);

select t_eq('סכום השורות שווה לסך הכול',
  (select round(sum((l ->> 'amount')::numeric), 2)
     from jsonb_array_elements(app.attendance_calc(app.attendance_config('attendance.overtime'),
       '{"hours":11,"min_hours":12,"hourly_rate":50,"dow":6}'::jsonb) -> 'lines') l),
  (app.attendance_calc(app.attendance_config('attendance.overtime'),
    '{"hours":11,"min_hours":12,"hourly_rate":50,"dow":6}'::jsonb) ->> 'total')::numeric);

-- עיגול ל-5 דקות: 7:58 ⇒ 8.00
select t_eq('עיגול ל-5 דקות מעגל 7.9667 ל-8',
  (app.attendance_calc(
     app.attendance_config('attendance.overtime') ||
       '{"rounding":{"minutes":5,"mode":"nearest"}}'::jsonb,
     '{"hours":7.9667,"hourly_rate":50,"dow":1}'::jsonb) ->> 'worked_hours')::numeric,
  8::numeric);

select t_eq('בלי תעריף מוחזרות שעות בלי סכום',
  (app.attendance_calc(app.attendance_config('attendance.overtime'),
    '{"hours":8,"dow":1}'::jsonb) ->> 'total'), null::text);

-- ================= 2. גזירת המשמרות =================

\echo '--- גזירת משמרות ---'

select t_eq('פער של 90 דקות מאחד למשמרת אחת, והמשימה של 18:00 נפרדת',
  (select count(*) from app.planned_shifts('20000000-0000-0000-0000-0000000000f3',
     current_date, current_date))::int, 2);

-- 07:00 במחסן היא ההתחלה, אף שהמשימה בשטח מתחילה 08:00
select t_eq('משמרת שמתחילה במחסן מתחילה בשעת המחסן',
  (select to_char(min(shift_start) at time zone 'Asia/Jerusalem', 'HH24:MI')
     from app.planned_shifts('20000000-0000-0000-0000-0000000000f3', current_date, current_date)),
  '07:00');

-- הסיום לפי המשימה האחרונה במשמרת: 11:30 + 2 שעות + 0.5 נסיעה = 14:00
select t_eq('הסיום נלקח מהמשימה האחרונה במשמרת ועוד זמן נסיעה',
  (select to_char(shift_end at time zone 'Asia/Jerusalem', 'HH24:MI')
     from app.planned_shifts('20000000-0000-0000-0000-0000000000f3', current_date, current_date)
     order by shift_start limit 1),
  '14:00');

select t_eq('המשמרת הראשונה מאגדת שתי משימות',
  (select array_length(task_ids, 1)
     from app.planned_shifts('20000000-0000-0000-0000-0000000000f3', current_date, current_date)
     order by shift_start limit 1), 2);

select t_eq('והיא מסומנת כמתחילה במחסן',
  (select work_site
     from app.planned_shifts('20000000-0000-0000-0000-0000000000f3', current_date, current_date)
     order by shift_start limit 1), 'warehouse');

-- 22:00 + 4 שעות: הסיום ב-02:00 *למחרת*, ולא שלילי כמו ב-onsite_end_time
select t_eq('משמרת חוצת חצות נמשכת 4 שעות ולא שלילית',
  (select planned_hours from app.planned_shifts('20000000-0000-0000-0000-0000000000f3',
     current_date + 1, current_date + 1)), 4.00::numeric);

select t_eq('וסיומה נופל ביום שאחרי',
  (select (shift_end at time zone 'Asia/Jerusalem')::date - (shift_start at time zone 'Asia/Jerusalem')::date
     from app.planned_shifts('20000000-0000-0000-0000-0000000000f3',
       current_date + 1, current_date + 1)), 1);

-- עובד הקבלן מגיע דרך task_contractor_workers, לא דרך task_assignments
select t_eq('עובד קבלן מקבל משמרת דרך שיבוץ הקבלן',
  (select count(*) from app.planned_shifts('20000000-0000-0000-0000-0000000000b2',
     current_date, current_date))::int, 1);

select t_eq('והוא בשטח, ולכן מתחיל ב-08:00 ולא ב-07:00',
  (select to_char(shift_start at time zone 'Asia/Jerusalem', 'HH24:MI')
     from app.planned_shifts('20000000-0000-0000-0000-0000000000b2', current_date, current_date)),
  '08:00');

-- זמן נסיעה מהאזור, כשאין דריסה על המשימה
update tasks set travel_hours = null where id = '60000000-0000-0000-0000-00000000a002';
insert into pricing_zones (name, shape, center_lat, center_lng, radius_km, travel_hours, priority)
values ('מרכז לבדיקת נוכחות', 'circle', 32.0853, 34.7818, 10, 1.0, 1);

select t_eq('בלי דריסה, זמן הנסיעה נשאב מאזור הגיאופנס',
  (select to_char(shift_end at time zone 'Asia/Jerusalem', 'HH24:MI')
     from app.planned_shifts('20000000-0000-0000-0000-0000000000f3', current_date, current_date)
     order by shift_start limit 1),
  '14:30');

update tasks set travel_hours = 0.5 where id = '60000000-0000-0000-0000-00000000a002';
update pricing_zones set deleted_at = now() where name = 'מרכז לבדיקת נוכחות';

-- ================= 3. השעון =================

\echo '--- השעון: חסימות ---'

-- המשמרת של מחר בלבד, כדי שהעובד יהיה "מוקדם מדי" ביחס אליה
create or replace function t_clock_in(p_lat double precision default null,
                                      p_lng double precision default null,
                                      p_acc numeric default null)
returns jsonb language sql as $$ select attendance_clock_in(p_lat, p_lng, p_acc, null) $$;
grant execute on function t_clock_in(double precision, double precision, numeric) to authenticated;

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000f3', false);

-- ברירת המחדל היא "מיקום לא נדרש", ולכן החתמה בלי מיקום עוברת
select t_expect_ok('החתמת כניסה עוברת כשמיקום אינו נדרש', $$select t_clock_in()$$);
select t_expect_fail('כניסה כפולה נחסמת', $$select t_clock_in()$$);
select t_expect_ok('החתמת יציאה סוגרת את המשמרת',
  $$select attendance_clock_out(null, null, null, null)$$);

select t_eq('נרשמה בדיוק רשומה אחת',
  (select count(*) from attendance_entries
    where profile_id = '20000000-0000-0000-0000-0000000000f3')::int, 1);

select t_eq('והיא נצמדה למשמרת של היום',
  (select to_char(shift_start at time zone 'Asia/Jerusalem', 'HH24:MI')
     from attendance_entries where profile_id = '20000000-0000-0000-0000-0000000000f3'),
  '07:00');

select t_expect_fail('אין החתמת יציאה בלי משמרת פתוחה',
  $$select attendance_clock_out(null, null, null, null)$$);

-- העובד אינו יכול לכתוב לטבלה ישירות. זו הנקודה שבה "חסימת מיקום" הופכת
-- מהצעה לאכיפה: אילו היה נתיב INSERT ישיר, כל בדיקה ב-RPC הייתה עקיפה.
select t_expect_fail('עובד אינו יכול להזין נוכחות ישירות לטבלה', $$
  insert into attendance_entries (profile_id, work_date, clock_in_at)
  values ('20000000-0000-0000-0000-0000000000f3', current_date, now())$$);

select t_rows('ואינו יכול לתקן לעצמו את שעת הכניסה', $$
  update attendance_entries set clock_in_at = now() - interval '5 hours'
   where profile_id = '20000000-0000-0000-0000-0000000000f3'$$, 0);

select t_expect_ok('אבל כן יכול להוסיף הערה משלו', $$
  update attendance_entries set employee_note = 'איחרתי בגלל פקק'
   where profile_id = '20000000-0000-0000-0000-0000000000f3'$$);

reset role;
select set_config('request.jwt.claim.sub', '', false);

-- מעכשיו: מיקום נדרש ברדיוס 300 מ׳, ואסור להתחיל לפני המשימה.
--
-- המשמרת הראשונה של העובד מתחילה במחסן, ולכן נקודת הייחוס שלה היא המחסן
-- ולא האירוע. בלי מחסן מוגדר כל בדיקת מרחק כאן הייתה מדלגת על עצמה
-- ומחזירה "מתקבל" — וזה בדיוק מה שהבדיקות האלה אמורות לתפוס.
--
-- שני מחסנים, כדי שהבחירה ביניהם תהיה שאלה אמיתית ולא ברירת מחדל.
insert into warehouses (id, name, lat, lng) values
  ('70000000-0000-0000-0000-000000000001', 'מחסן תל אביב', 32.0853, 34.7818),
  ('70000000-0000-0000-0000-000000000002', 'מחסן ירושלים', 31.7683, 35.2137);

update worker_pay_settings
   set requires_location = true, location_radius_m = 300, allow_early_clock_in = false
 where profile_id = '20000000-0000-0000-0000-0000000000f3';
-- המשימה נוקבת במחסן תל אביב במפורש
update tasks set warehouse_id = '70000000-0000-0000-0000-000000000001'
 where id = '60000000-0000-0000-0000-00000000a001';
delete from attendance_entries where profile_id = '20000000-0000-0000-0000-0000000000f3';

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000f3', false);

select t_expect_fail('בלי מיקום ההחתמה נדחית כשמיקום נדרש', $$select t_clock_in()$$);

-- ירושלים מול המחסן בתל אביב — כ-54 ק״מ
select t_expect_fail('מיקום רחוק מנקודת הייחוס נדחה',
  $$select t_clock_in(31.7683, 35.2137, 10)$$);

select t_eq('ולא נוצרה רשומה מאף אחת מהדחיות',
  (select count(*) from attendance_entries
    where profile_id = '20000000-0000-0000-0000-0000000000f3')::int, 0);

-- כ-100 מ׳ מהמחסן: בתוך הרדיוס
select t_expect_ok('מיקום סמוך לנקודת הייחוס מתקבל',
  $$select t_clock_in(32.0862, 34.7818, 15)$$);

select t_eq('והמרחק נשמר ברשומה',
  (select clock_in_distance_m < 300 from attendance_entries
    where profile_id = '20000000-0000-0000-0000-0000000000f3'), true);

reset role;
select set_config('request.jwt.claim.sub', '', false);
delete from attendance_entries where profile_id = '20000000-0000-0000-0000-0000000000f3';

-- המשימה עוברת למחסן ירושלים. העובד עומד בדיוק בכתובת האירוע בתל אביב,
-- וזה עדיין נדחה — כי הוא אמור לצאת מהמחסן שהמשימה נוקבת בו.
update tasks set warehouse_id = '70000000-0000-0000-0000-000000000002'
 where id = '60000000-0000-0000-0000-00000000a001';

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000f3', false);
select t_expect_fail('מי שמתחיל במחסן נמדד מול המחסן שהמשימה נוקבת בו',
  $$select t_clock_in(32.0853, 34.7818, 10)$$);
select t_expect_ok('ומתקבל כשהוא באמת ליד אותו מחסן',
  $$select t_clock_in(31.7683, 35.2137, 10)$$);
reset role;
select set_config('request.jwt.claim.sub', '', false);

select t_eq('המשמרת נושאת את שם המחסן שנקבע לה',
  (select warehouse_name from app.planned_shifts('20000000-0000-0000-0000-0000000000f3',
     current_date, current_date) order by shift_start limit 1),
  'מחסן ירושלים');

delete from attendance_entries where profile_id = '20000000-0000-0000-0000-0000000000f3';

-- משימה שלא נקבה במחסן: נמדדים מול הקרוב ביותר, ועדיין חייבים להיות בתוך
-- הרדיוס של מחסן אמיתי.
update tasks set warehouse_id = null where id = '60000000-0000-0000-0000-00000000a001';

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000f3', false);
select t_expect_ok('בלי מחסן על המשימה, המחסן הקרוב ביותר הוא נקודת הייחוס',
  $$select t_clock_in(32.0862, 34.7818, 15)$$);
reset role;
select set_config('request.jwt.claim.sub', '', false);
delete from attendance_entries where profile_id = '20000000-0000-0000-0000-0000000000f3';

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000f3', false);
select t_expect_fail('אבל עמידה רחוק מכל המחסנים עדיין נדחית',
  $$select t_clock_in(29.5581, 34.9482, 10)$$);
reset role;
select set_config('request.jwt.claim.sub', '', false);

-- רדיוס פר-מחסן גובר על הגלובלי
update warehouses set radius_m = 20000 where id = '70000000-0000-0000-0000-000000000001';
update worker_pay_settings set location_radius_m = null
 where profile_id = '20000000-0000-0000-0000-0000000000f3';

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000f3', false);
select t_expect_ok('רדיוס רחב שהוגדר על המחסן מתיר החתמה רחוקה יותר',
  $$select t_clock_in(32.1800, 34.8700, 20)$$);
reset role;
select set_config('request.jwt.claim.sub', '', false);

update warehouses set radius_m = null where id = '70000000-0000-0000-0000-000000000001';
update worker_pay_settings set location_radius_m = 300
 where profile_id = '20000000-0000-0000-0000-0000000000f3';
delete from attendance_entries where profile_id = '20000000-0000-0000-0000-0000000000f3';

-- לא לאירוע ולא לשום מחסן יש קואורדינטות: אי אפשר לאמת, ולכן מתקבל ומסומן
update events set location_lat = null, location_lng = null
 where id = '30000000-0000-0000-0000-00000000a001';
update warehouses set lat = null, lng = null;

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000f3', false);
select t_expect_ok('אתר בלי קואורדינטות אינו חוסם את העובד',
  $$select t_clock_in(31.7683, 35.2137, 10)$$);
reset role;
select set_config('request.jwt.claim.sub', '', false);

select t_eq('וההחתמה מסומנת כלא ניתנת לאימות',
  (select 'no_site_coords' = any(flags) from attendance_entries
    where profile_id = '20000000-0000-0000-0000-0000000000f3'), true);

update events set location_lat = 32.0853, location_lng = 34.7818
 where id = '30000000-0000-0000-0000-00000000a001';
update warehouses set lat = 32.0853, lng = 34.7818
 where id = '70000000-0000-0000-0000-000000000001';
update warehouses set lat = 31.7683, lng = 35.2137
 where id = '70000000-0000-0000-0000-000000000002';
delete from attendance_entries where profile_id = '20000000-0000-0000-0000-0000000000f3';

\echo '--- השעון: התחלה מוקדמת ---'
-- מזיזים את כל משימות היום למחר, כך שכל משמרת היא בעתיד הרחוק
update tasks set task_date = current_date + 5
 where id in ('60000000-0000-0000-0000-00000000a001', '60000000-0000-0000-0000-00000000a002',
              '60000000-0000-0000-0000-00000000a003');

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000f3', false);
select t_expect_fail('אין משמרת להיום ⇒ אין החתמה',
  $$select t_clock_in(32.0853, 34.7818, 10)$$);
reset role;
select set_config('request.jwt.claim.sub', '', false);

-- משמרת שמתחילה בעוד שעתיים: מוקדם מדי
update tasks set task_date = (now() at time zone 'Asia/Jerusalem')::date,
                 warehouse_start_time = (now() at time zone 'Asia/Jerusalem' + interval '2 hours')::time,
                 onsite_start_time = (now() at time zone 'Asia/Jerusalem' + interval '3 hours')::time
 where id = '60000000-0000-0000-0000-00000000a001';

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000f3', false);
select t_expect_fail('התחלה שעתיים לפני המשמרת נחסמת',
  $$select t_clock_in(32.0853, 34.7818, 10)$$);
reset role;
select set_config('request.jwt.claim.sub', '', false);

update worker_pay_settings set allow_early_clock_in = true
 where profile_id = '20000000-0000-0000-0000-0000000000f3';

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000f3', false);
select t_expect_ok('ומתאפשרת למי שהוגדר לו שמותר',
  $$select t_clock_in(32.0853, 34.7818, 10)$$);
reset role;
select set_config('request.jwt.claim.sub', '', false);

-- ================= 4. הנתיב הידני =================

\echo '--- הנתיב הידני ---'

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000f4', false);
-- המנהל נמצא בירושלים ורושם עבור העובד; פתח המילוט פטור מבדיקת המיקום
-- מעצם כך שהיא אינה בגוף הפונקציה, ולא בגלל דגל שמישהו מעביר.
select t_expect_ok('מנהל מזין נוכחות ידנית בלי בדיקת מיקום', $$
  select attendance_record_entry('20000000-0000-0000-0000-0000000000f3',
    now() - interval '3 days', now() - interval '3 days' + interval '9 hours', 'שכח להחתים')$$);
reset role;
select set_config('request.jwt.claim.sub', '', false);

select t_eq('הרשומה הידנית מסומנת ככזו',
  (select source from attendance_entries
    where profile_id = '20000000-0000-0000-0000-0000000000f3' and source = 'manual'), 'manual');

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000f3', false);
select t_expect_fail('עובד אינו יכול להזין נוכחות ידנית לעצמו', $$
  select attendance_record_entry('20000000-0000-0000-0000-0000000000f3',
    now() - interval '2 days', now() - interval '2 days' + interval '9 hours', null)$$);
reset role;
select set_config('request.jwt.claim.sub', '', false);

-- ================= 5. ראייה והרשאות בדוח =================

\echo '--- דוח נוכחות: מי רואה מה ---'

-- רשומה לעובד הקבלן, כדי שיהיה מה לראות בפורטל
insert into attendance_entries (profile_id, work_date, clock_in_at, clock_out_at, source)
values ('20000000-0000-0000-0000-0000000000b2', current_date,
        now() - interval '9 hours', now(), 'manual');

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000f3', false);
select t_eq('עובד רואה רק את הרשומות שלו',
  (select count(*) from jsonb_array_elements(
     attendance_report(current_date - 7, current_date + 1) -> 'rows') r
   where r ->> 'profile_id' <> '20000000-0000-0000-0000-0000000000f3')::int, 0);

select t_eq('ורואה את השכר שלו',
  (select bool_and((r #>> '{pay,total}') is not null)
     from jsonb_array_elements(attendance_report(current_date - 7, current_date + 1) -> 'rows') r
    where (r ->> 'clock_out_at') is not null), true);
reset role;
select set_config('request.jwt.claim.sub', '', false);

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000f4', false);
select t_eq('מנהל עם view_all רואה גם את עובד הקבלן',
  (select count(*) from jsonb_array_elements(
     attendance_report(current_date - 7, current_date + 1) -> 'rows') r
   where r ->> 'profile_id' = '20000000-0000-0000-0000-0000000000b2')::int, 1);

-- זו ההפרדה שבגללה view_all ו-view_pay אינם נגזרים זה מזה
select t_eq('אבל בלי view_pay הוא לא מקבל סכומים',
  (attendance_report(current_date - 7, current_date + 1) ->> 'can_see_pay')::boolean, false);

select t_eq('והסכום אכן מושמט מהשורות של אחרים',
  (select bool_and((r #>> '{pay,total}') is null)
     from jsonb_array_elements(attendance_report(current_date - 7, current_date + 1) -> 'rows') r
    where r ->> 'profile_id' <> '20000000-0000-0000-0000-0000000000f4'), true);

select t_expect_ok('ומנהל עם edit_entry מתקן שעות', $$
  select attendance_save_entry(
    (select id from attendance_entries where source = 'manual'
      and profile_id = '20000000-0000-0000-0000-0000000000f3' limit 1),
    now() - interval '3 days', now() - interval '3 days' + interval '8 hours', 'תוקן')$$);
reset role;
select set_config('request.jwt.claim.sub', '', false);

select t_eq('התיקון שמר את המדידה המקורית',
  (select raw_clock_out_at is not null from attendance_entries
    where source = 'manual' and profile_id = '20000000-0000-0000-0000-0000000000f3' limit 1), true);

select t_eq('וסימן את הרשומה כערוכה',
  (select 'edited' = any(flags) from attendance_entries
    where source = 'manual' and profile_id = '20000000-0000-0000-0000-0000000000f3' limit 1), true);

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000b1', false);
select t_eq('קבלן רואה את עובד הסגל שלו',
  (select count(*) from jsonb_array_elements(
     attendance_report(current_date - 7, current_date + 1) -> 'rows') r
   where r ->> 'profile_id' = '20000000-0000-0000-0000-0000000000b2')::int, 1);

select t_eq('ואינו רואה עובד צוות של החברה',
  (select count(*) from jsonb_array_elements(
     attendance_report(current_date - 7, current_date + 1) -> 'rows') r
   where r ->> 'profile_id' = '20000000-0000-0000-0000-0000000000f3')::int, 0);

select t_eq('גם בקריאה ישירה לטבלה הוא רואה רק את שלו',
  (select count(*) from attendance_entries
    where profile_id = '20000000-0000-0000-0000-0000000000f3')::int, 0);
reset role;
select set_config('request.jwt.claim.sub', '', false);

-- הקבלן אינו רשאי לצפות במשמרות של עובד צוות של החברה
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000b1', false);
select t_expect_fail('קבלן אינו יכול לשלוף משמרות של עובד שאינו שלו', $$
  select * from employee_shifts('20000000-0000-0000-0000-0000000000f3',
    current_date, current_date)$$);
select t_expect_ok('אבל כן של העובד שלו', $$
  select * from employee_shifts('20000000-0000-0000-0000-0000000000b2',
    current_date, current_date)$$);
reset role;
select set_config('request.jwt.claim.sub', '', false);

\echo '--- anon ---'
set role anon;
select t_expect_fail('anon אינו יכול להחתים שעון',
  $$select attendance_clock_in(null, null, null, null)$$);
select t_expect_fail('anon אינו יכול לשלוף דוח',
  $$select attendance_report(null, null)$$);
reset role;
select set_config('request.jwt.claim.sub', '', false);
