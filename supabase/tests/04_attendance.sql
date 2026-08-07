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

-- מכאן והלאה הבדיקות מריצות החתמות אמיתיות מול now(), ולכן הן תלויות בשעה
-- שבה החבילה רצה. הזריעה הקבועה (07:00 / 11:30 / 18:00) סיפקה משמרת שכבר
-- התחילה רק אם החבילה הורצה בבוקר: מ-13:30 ואילך המשמרת הבאה היא זו של 18:00,
-- ו-allow_early_clock_in=false הפך כל החתמה כאן ל"לא ניתן להתחיל לפני 18:00".
-- לכן המשימה הראשונה מעוגנת לשעה שעברה, ושתי האחרות מוזזות מהיום — כך
-- שלשעון יש בדיוק משמרת אחת להיצמד אליה, בכל שעה שבה החבילה תרוץ.
-- גזירת המשמרות (סעיף 2) כבר רצה על הזריעה הקבועה ואינה מושפעת.
do $$
declare
  now_il timestamp := now() at time zone 'Asia/Jerusalem';
  wh_start time;
begin
  -- שעה אחורה, אלא אם החבילה רצה ממש אחרי חצות — אז 00:00, שהוא עדיין בעבר
  wh_start := case when now_il::time < '01:00' then '00:00'::time
                   else (now_il - interval '1 hour')::time end;
  update tasks
     set task_date = now_il::date,
         warehouse_start_time = wh_start,
         onsite_start_time = wh_start + interval '1 hour'
   where id = '60000000-0000-0000-0000-00000000a001';
  update tasks set task_date = now_il::date + 10
   where id in ('60000000-0000-0000-0000-00000000a002',
                '60000000-0000-0000-0000-00000000a003');
end $$;

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

-- הציפייה נגזרת מהמשימה עצמה ולא מקובעת, כי שעת ההתחלה מעוגנת ל-now()
select t_eq('והיא נצמדה למשמרת של היום',
  (select to_char(shift_start at time zone 'Asia/Jerusalem', 'HH24:MI')
     from attendance_entries where profile_id = '20000000-0000-0000-0000-0000000000f3'),
  (select to_char(warehouse_start_time, 'HH24:MI')
     from tasks where id = '60000000-0000-0000-0000-00000000a001'));

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

-- מסלול הראיות. clock_in_at היה מוגן ב-field_registry, אבל הקואורדינטות,
-- המרחק והדגלים לא היו רשומים שם כלל — ולכן PATCH ישיר ל-PostgREST על
-- השורה של העובד עצמו יכול היה להפוך החתמה מחוץ לרדיוס להחתמה תקינה.
-- זה מה שהופך את "נדרש מיקום" לאכיפה: לא די בכך שה-RPC בודק, אם אפשר
-- לשכתב את התוצאה אחריו.
-- הביטוי מבטיח שינוי אמיתי בכל מצב: השוואה ל-'{}' הייתה עוברת בשקט כשהרשומה
-- ממילא בלי דגלים, ואז הבדיקה מאשרת את עצמה במקום את ההגנה.
select t_expect_fail('עובד אינו יכול לגעת בדגלים של הרשומה שלו', $$
  update attendance_entries set flags = flags || 'forged'::text
   where profile_id = '20000000-0000-0000-0000-0000000000f3'$$);

select t_expect_fail('ואינו יכול לשכתב את המרחק שנמדד', $$
  update attendance_entries set clock_in_distance_m = 0
   where profile_id = '20000000-0000-0000-0000-0000000000f3'$$);

select t_expect_fail('ואינו יכול לזייף את הקואורדינטות', $$
  update attendance_entries set clock_in_lat = 32.0853, clock_in_lng = 34.7818
   where profile_id = '20000000-0000-0000-0000-0000000000f3'$$);

select t_expect_fail('ואינו יכול לשנות את מקור הרשומה', $$
  update attendance_entries set source = 'manual'
   where profile_id = '20000000-0000-0000-0000-0000000000f3'$$);

select t_expect_fail('ואינו יכול להעביר את המשמרת ליום אחר', $$
  update attendance_entries set work_date = current_date - 1
   where profile_id = '20000000-0000-0000-0000-0000000000f3'$$);

select t_expect_fail('ואינו יכול לנתק את הרשומה מהמשימה שאליה נצמדה', $$
  update attendance_entries set task_ids = '{}'
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
-- המחסן יושב על הלקוח, ומשם נגזר לכל המשימות שלו
update customers set warehouse_id = '70000000-0000-0000-0000-000000000001'
 where id = '10000000-0000-0000-0000-000000000001';
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

select t_eq('המשמרת נושאת את שם המחסן של הלקוח',
  (select warehouse_name from app.planned_shifts('20000000-0000-0000-0000-0000000000f3',
     current_date, current_date) order by shift_start limit 1),
  'מחסן תל אביב');

-- הלקוח עובר למחסן ירושלים. העובד עומד בדיוק בכתובת האירוע בתל אביב, וזה
-- נדחה — כי הוא אמור לצאת מהמחסן של הלקוח שהמשימה שלו.
update customers set warehouse_id = '70000000-0000-0000-0000-000000000002'
 where id = '10000000-0000-0000-0000-000000000001';

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000f3', false);
select t_expect_fail('מי שמתחיל במחסן נמדד מול המחסן של הלקוח, לא מול האירוע',
  $$select t_clock_in(32.0853, 34.7818, 10)$$);
select t_expect_ok('ומתקבל כשהוא באמת ליד המחסן של הלקוח',
  $$select t_clock_in(31.7683, 35.2137, 10)$$);
reset role;
select set_config('request.jwt.claim.sub', '', false);
delete from attendance_entries where profile_id = '20000000-0000-0000-0000-0000000000f3';

-- דריסה על משימה בודדת גוברת על המחסן של הלקוח. זו הדרך היחידה שמשימה
-- עצמאית, שאין לה לקוח, תוכל לנקוב במחסן.
update tasks set warehouse_id = '70000000-0000-0000-0000-000000000001'
 where id = '60000000-0000-0000-0000-00000000a001';

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000f3', false);
select t_expect_ok('דריסת מחסן על המשימה גוברת על המחסן של הלקוח',
  $$select t_clock_in(32.0862, 34.7818, 15)$$);
reset role;
select set_config('request.jwt.claim.sub', '', false);

select t_eq('והמשמרת מציגה את המחסן שנדרס',
  (select warehouse_name from app.planned_shifts('20000000-0000-0000-0000-0000000000f3',
     current_date, current_date) order by shift_start limit 1),
  'מחסן תל אביב');

update tasks set warehouse_id = null where id = '60000000-0000-0000-0000-00000000a001';
update customers set warehouse_id = '70000000-0000-0000-0000-000000000001'
 where id = '10000000-0000-0000-0000-000000000001';
delete from attendance_entries where profile_id = '20000000-0000-0000-0000-0000000000f3';

-- ללקוח אין מחסן: אין מול מה למדוד, ולכן מתקבל ומסומן — ולא נופלים
-- למחסן הקרוב ביותר, שהיה מתיר החתמה מהמחסן של לקוח אחר.
update customers set warehouse_id = null
 where id = '10000000-0000-0000-0000-000000000001';

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000f3', false);
select t_expect_ok('לקוח בלי מחסן אינו חוסם את העובד',
  $$select t_clock_in(29.5581, 34.9482, 10)$$);
reset role;
select set_config('request.jwt.claim.sub', '', false);

select t_eq('אבל ההחתמה מסומנת כלא מאומתת',
  (select 'no_site_coords' = any(flags) from attendance_entries
    where profile_id = '20000000-0000-0000-0000-0000000000f3'), true);

update customers set warehouse_id = '70000000-0000-0000-0000-000000000001'
 where id = '10000000-0000-0000-0000-000000000001';
delete from attendance_entries where profile_id = '20000000-0000-0000-0000-0000000000f3';

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

-- מסנן "עובד" בדוח שבפורטל נשען על contractor_staff_list, כי profiles_select
-- לא נותן לקבלן לקרוא ישירות שורות פרופיל של מישהו אחר — אפילו לא של הסגל שלו.
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000b1', false);
select t_eq('הקבלן מקבל את כל הסגל שלו, כולל את עצמו',
  (select count(*) from jsonb_array_elements(contractor_staff_list()) r)::int, 2);

select t_eq('ולא עובד צוות של החברה',
  (select count(*) from jsonb_array_elements(contractor_staff_list()) r
    where r ->> 'id' = '20000000-0000-0000-0000-0000000000f3')::int, 0);
reset role;
select set_config('request.jwt.claim.sub', '', false);

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000f3', false);
select t_expect_fail('עובד צוות בלי portal.attendance אינו יכול לקרוא לרשימת סגל קבלן', $$
  select contractor_staff_list()$$);
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

-- ================= 6. דיווח עצמי ואישור =================
-- ההבטחה כאן היא אחת: שעות שדווחו ידנית אינן שעות עד שמישהו אמר כן. שאר
-- הבדיקות סובבות סביבה — מי יכול לומר כן, ומה חוסם דיווח לפני שהוא בכלל
-- מגיע להכרעה.

\echo '--- דיווח עצמי: הגשה ---'

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000f3', false);

select t_expect_ok('עובד מדווח משמרת שלא הוחתמה', $$
  select attendance_submit_entry(now() - interval '2 days',
                                 now() - interval '2 days' + interval '6 hours', 'נגמרה הסוללה')$$);

select t_expect_fail('דיווח בלי שעת סיום נדחה', $$
  select attendance_submit_entry(now() - interval '4 days', null, null)$$);

select t_expect_fail('דיווח על משמרת שטרם הסתיימה נדחה', $$
  select attendance_submit_entry(now() + interval '1 hour', now() + interval '5 hours', null)$$);

select t_expect_fail('דיווח מעבר לחלון האחורה נדחה', $$
  select attendance_submit_entry(now() - interval '40 days',
                                 now() - interval '40 days' + interval '5 hours', null)$$);

select t_expect_fail('דיווח שחופף לשעות שכבר נרשמו נדחה', $$
  select attendance_submit_entry(now() - interval '2 days' + interval '2 hours',
                                 now() - interval '2 days' + interval '8 hours', null)$$);

reset role;
select set_config('request.jwt.claim.sub', '', false);

select t_eq('הדיווח נשמר כממתין לאישור',
  (select status from attendance_entries
    where profile_id = '20000000-0000-0000-0000-0000000000f3'
      and 'self_reported' = any(flags)), 'pending');

select t_eq('ומסומן כדיווח עצמי ולא כהחתמת שעון',
  (select source from attendance_entries
    where profile_id = '20000000-0000-0000-0000-0000000000f3'
      and 'self_reported' = any(flags)), 'manual');

-- app.profiles_with הוא הצד ההפוך של app.has: לא "האם אני רשאי" אלא "מי
-- רשאי". f4 קיבל attendance.edit_entry, ו-approve_entry נגזר ממנו.
select t_eq('הדיווח יצר התראה למי שרשאי לאשר',
  (select count(*) from notifications
    where type = 'attendance_submitted'
      and recipient_id = '20000000-0000-0000-0000-0000000000f4')::int, 1);

\echo '--- דיווח עצמי: לא נספר עד שאושר ---'

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000f3', false);

select t_eq('6 השעות שדווחו נספרות בנפרד כממתינות',
  (attendance_report(current_date - 7, current_date + 1) -> 'totals' ->> 'pending_hours')::numeric,
  6.00::numeric);

-- ההבטחה עצמה: הסיכום שווה בדיוק לסכום השורות המאושרות, ולא לכולן.
select t_eq('וסך השעות בדוח סופר מאושרות בלבד',
  (attendance_report(current_date - 7, current_date + 1) -> 'totals' ->> 'actual_hours')::numeric,
  (select round(coalesce(sum((r ->> 'actual_hours')::numeric), 0), 2)
     from jsonb_array_elements(attendance_report(current_date - 7, current_date + 1) -> 'rows') r
    where r ->> 'status' = 'approved'));

select t_eq('והשכר לתשלום אינו כולל אותן',
  (attendance_report(current_date - 7, current_date + 1) -> 'totals' ->> 'total')::numeric,
  (select round(coalesce(sum((r #>> '{pay,total}')::numeric), 0), 2)
     from jsonb_array_elements(attendance_report(current_date - 7, current_date + 1) -> 'rows') r
    where r ->> 'status' = 'approved'));

-- בלי זה כל השאר הוא קישוט: הטבלה חשופה דרך PostgREST, והעובד רשאי לעדכן
-- את השורה שלו. field_registry הוא מה שעוצר אותו בעמודה אחת.
select t_expect_fail('עובד אינו יכול לאשר את הדיווח של עצמו', $$
  update attendance_entries set status = 'approved'
   where profile_id = '20000000-0000-0000-0000-0000000000f3' and status = 'pending'$$);

select t_expect_fail('ואינו יכול לזייף מי אישר ומתי', $$
  update attendance_entries set reviewed_at = now()
   where profile_id = '20000000-0000-0000-0000-0000000000f3' and status = 'pending'$$);

select t_expect_fail('ואינו יכול להריץ את ההכרעה בעצמו', $$
  select attendance_review_entry(
    (select id from attendance_entries
      where profile_id = '20000000-0000-0000-0000-0000000000f3' and status = 'pending'), true, null)$$);

reset role;
select set_config('request.jwt.claim.sub', '', false);

\echo '--- דיווח עצמי: ההכרעה ---'

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000f4', false);

select t_expect_fail('דחייה בלי נימוק נחסמת', $$
  select attendance_review_entry(
    (select id from attendance_entries
      where profile_id = '20000000-0000-0000-0000-0000000000f3' and status = 'pending'), false, null)$$);

-- f4 לא קיבל את attendance.approve_entry במפורש; הוא מגיע אליו מ-edit_entry
select t_expect_ok('מי שרשאי לתקן שעות רשאי גם לאשר', $$
  select attendance_review_entry(
    (select id from attendance_entries
      where profile_id = '20000000-0000-0000-0000-0000000000f3' and status = 'pending'),
    true, 'אושר')$$);

reset role;
select set_config('request.jwt.claim.sub', '', false);

select t_eq('הדיווח אושר',
  (select status from attendance_entries
    where profile_id = '20000000-0000-0000-0000-0000000000f3'
      and 'self_reported' = any(flags)), 'approved');

select t_eq('ונרשם מי אישר אותו',
  (select reviewed_by from attendance_entries
    where profile_id = '20000000-0000-0000-0000-0000000000f3'
      and 'self_reported' = any(flags)), '20000000-0000-0000-0000-0000000000f4'::uuid);

select t_eq('העובד קיבל התראה על האישור',
  (select count(*) from notifications
    where type = 'attendance_approved'
      and recipient_id = '20000000-0000-0000-0000-0000000000f3')::int, 1);

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000f3', false);

select t_eq('ומאותו רגע השעות נספרות',
  (attendance_report(current_date - 7, current_date + 1) -> 'totals' ->> 'pending_hours')::numeric,
  0.00::numeric);

select t_eq('והן בתוך סך השעות של הדוח',
  (select count(*) from jsonb_array_elements(
     attendance_report(current_date - 7, current_date + 1) -> 'rows') r
   where r ->> 'status' = 'approved' and (r -> 'flags') @> '["self_reported"]'::jsonb)::int, 1);

reset role;
select set_config('request.jwt.claim.sub', '', false);

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000f4', false);
select t_expect_fail('אי אפשר להכריע פעמיים באותו דיווח', $$
  select attendance_review_entry(
    (select id from attendance_entries
      where profile_id = '20000000-0000-0000-0000-0000000000f3'
        and 'self_reported' = any(flags)), false, 'שוב')$$);
reset role;
select set_config('request.jwt.claim.sub', '', false);

\echo '--- דיווח עצמי: משיכה ודחייה ---'

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000f3', false);

select t_expect_ok('דיווח נוסף, על יום אחר', $$
  select attendance_submit_entry(now() - interval '5 days',
                                 now() - interval '5 days' + interval '4 hours', 'שכחתי')$$);

-- כל עוד הדיווח ממתין הוא שייך לעובד; אחרי שהוכרע הוא רשומת נוכחות ככל אחרת
select t_expect_ok('עובד מושך דיווח שממתין לאישור', $$
  select attendance_delete_entry((select id from attendance_entries
    where profile_id = '20000000-0000-0000-0000-0000000000f3'
      and status = 'pending' and deleted_at is null), false)$$);

select t_expect_fail('אבל אינו יכול למחוק רשומה מאושרת', $$
  select attendance_delete_entry((select id from attendance_entries
    where profile_id = '20000000-0000-0000-0000-0000000000f3'
      and 'self_reported' = any(flags) and status = 'approved'), false)$$);

select t_expect_ok('דיווח שלישי, כדי לבדוק דחייה', $$
  select attendance_submit_entry(now() - interval '6 days',
                                 now() - interval '6 days' + interval '3 hours', null)$$);

reset role;
select set_config('request.jwt.claim.sub', '', false);

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000f4', false);
select t_expect_ok('מנהל דוחה עם נימוק', $$
  select attendance_review_entry(
    (select id from attendance_entries
      where profile_id = '20000000-0000-0000-0000-0000000000f3'
        and status = 'pending' and deleted_at is null),
    false, 'לא היית משובץ באותו יום')$$);
reset role;
select set_config('request.jwt.claim.sub', '', false);

select t_eq('הנימוק נשמר על הרשומה',
  (select manager_note from attendance_entries
    where profile_id = '20000000-0000-0000-0000-0000000000f3' and status = 'rejected'),
  'לא היית משובץ באותו יום');

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000f3', false);
select t_eq('ושעות שנדחו אינן נספרות אף פעם',
  (select count(*) from jsonb_array_elements(
     attendance_report(current_date - 10, current_date + 1) -> 'rows') r
   where r ->> 'status' = 'rejected')::int, 1);

select t_eq('גם לא בסיכום',
  (attendance_report(current_date - 10, current_date + 1) -> 'totals' ->> 'actual_hours')::numeric,
  (select round(coalesce(sum((r ->> 'actual_hours')::numeric), 0), 2)
     from jsonb_array_elements(attendance_report(current_date - 10, current_date + 1) -> 'rows') r
    where r ->> 'status' = 'approved'));

-- רשומה שנדחתה אינה חוסמת דיווח מתוקן על אותן שעות
select t_expect_ok('אפשר לדווח שוב על שעות שנדחו', $$
  select attendance_submit_entry(now() - interval '6 days',
                                 now() - interval '6 days' + interval '3 hours', 'דיווח מתוקן')$$);
reset role;
select set_config('request.jwt.claim.sub', '', false);

\echo '--- anon ---'
set role anon;
select t_expect_fail('anon אינו יכול לדווח משמרת',
  $$select attendance_submit_entry(now() - interval '1 day', now(), null)$$);
select t_expect_fail('anon אינו יכול להחתים שעון',
  $$select attendance_clock_in(null, null, null, null)$$);
select t_expect_fail('anon אינו יכול לשלוף דוח',
  $$select attendance_report(null, null)$$);
reset role;
select set_config('request.jwt.claim.sub', '', false);

-- ================= 6. כפל-שיבוץ =================

\echo '--- כפל-שיבוץ ---'

-- שלוש משימות באותו יום לאותו עובד:
--   A  10:00–12:00   B  11:00–13:00 (חופפת ל-A)   C  13:30–14:30 (צמודה, לא חופפת)
-- C היא המקרה שאסור לדווח עליו: הפער מ-B הוא 30 דקות, ולכן היא מתמזגת עם
-- B למשמרת אחת ב-planned_shifts — אבל משמרת אחת אינה חפיפה.
insert into tasks (id, event_id, task_type_id, task_date, onsite_start_time, hours_count,
                   travel_hours, status_id, worker_count)
select v.id, '30000000-0000-0000-0000-00000000a001',
       (select id from task_types where code = 'setup'),
       current_date + 20, v.onsite, v.hrs, 0,
       (select id from statuses where entity = 'task' and is_default), 1
from (values
  ('60000000-0000-0000-0000-00000000c001'::uuid, '10:00'::time, 2.0::numeric),
  ('60000000-0000-0000-0000-00000000c002'::uuid, '11:00'::time, 2.0::numeric),
  ('60000000-0000-0000-0000-00000000c003'::uuid, '13:30'::time, 1.0::numeric)
) as v(id, onsite, hrs);

insert into task_assignments (task_id, profile_id, role, work_site) values
  ('60000000-0000-0000-0000-00000000c001', '20000000-0000-0000-0000-0000000000f3', 'worker', 'field'),
  ('60000000-0000-0000-0000-00000000c003', '20000000-0000-0000-0000-0000000000f3', 'worker', 'field');

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false);

select t_eq('משימה צמודה שאינה חופפת אינה התנגשות',
  jsonb_array_length(assignment_conflicts('60000000-0000-0000-0000-00000000c003')), 0);

-- עכשיו משבצים אותו גם ל-B, שחופפת ל-A
select t_eq('שיבוץ לשתי משימות חופפות מדווח כהתנגשות',
  jsonb_array_length(assignment_conflicts('60000000-0000-0000-0000-00000000c002',
    array['20000000-0000-0000-0000-0000000000f3'::uuid])), 1);

select t_eq('וההתנגשות מצביעה על המשימה הנכונה',
  (assignment_conflicts('60000000-0000-0000-0000-00000000c002',
     array['20000000-0000-0000-0000-0000000000f3'::uuid]) -> 0 ->> 'task_id'),
  '60000000-0000-0000-0000-00000000c001');

select t_eq('ומזהה את סוג הנושא',
  (assignment_conflicts('60000000-0000-0000-0000-00000000c002',
     array['20000000-0000-0000-0000-0000000000f3'::uuid]) -> 0 ->> 'kind'), 'worker');

-- p_extra_profiles הוא השאלה "מה יקרה אם", ולכן בלעדיו אין עדיין התנגשות
select t_eq('בלי המועמד אין על מה לדווח',
  jsonb_array_length(assignment_conflicts('60000000-0000-0000-0000-00000000c002')), 0);

reset role;
select set_config('request.jwt.claim.sub', '', false);

-- אותה משאית בשתי משימות חופפות. אין משאיות בזריעה, ולכן אחת נוצרת כאן —
-- בלי זה truck_id היה נשאר null והבדיקה הייתה עוברת בלי לבדוק כלום.
insert into trucks (id, name) values
  ('80000000-0000-0000-0000-000000000001', 'משאית לבדיקת התנגשות');
update tasks set truck_id = '80000000-0000-0000-0000-000000000001'
 where id in ('60000000-0000-0000-0000-00000000c001', '60000000-0000-0000-0000-00000000c002');

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false);

select t_eq('משאית אחת בשתי משימות חופפות מדווחת',
  (select count(*) from jsonb_array_elements(
     assignment_conflicts('60000000-0000-0000-0000-00000000c002')) r
    where r ->> 'kind' = 'truck')::int, 1);

-- משימה בלי שעות אינה יכולה להתנגש: אין לה חלון
update tasks set onsite_start_time = null, warehouse_start_time = null
 where id = '60000000-0000-0000-0000-00000000c001';

select t_eq('משימה בלי שעה אינה מתנגשת בכלום',
  jsonb_array_length(assignment_conflicts('60000000-0000-0000-0000-00000000c002',
    array['20000000-0000-0000-0000-0000000000f3'::uuid])), 0);

reset role;
select set_config('request.jwt.claim.sub', '', false);

-- ================= 7. משלוח התראות =================

\echo '--- משלוח התראות ---'

-- הערוץ כבוי בברירת מחדל: שדרוג לא אמור להתחיל לשלוח מיילים מעצמו.
select t_eq('ערוץ המייל כבוי עד שמדליקים אותו', app.email_enabled(), false);

select t_eq('וכשהוא כבוי לא נוצרת שורת משלוח',
  (select count(*) from notification_deliveries)::int, 0);

update app_settings
   set value = jsonb_set(value, '{enabled}', 'true'::jsonb)
 where key = 'notifications.email';

update profiles set email = 'clock@vl.test'
 where id = '20000000-0000-0000-0000-0000000000f3';

select t_eq('אחרי ההדלקה הערוץ פתוח', app.email_enabled(), true);

select t_expect_ok('התראה חדשה מייצרת שורת משלוח', $$
  select app.notify('20000000-0000-0000-0000-0000000000f3', 'task_assigned',
    'שובצת למשימה', 'בדיקה', null, null)$$);

select t_eq('נוצרה שורה אחת, ממתינה',
  (select count(*) from notification_deliveries
    where recipient_id = '20000000-0000-0000-0000-0000000000f3' and status = 'pending')::int, 1);

select t_eq('והיא נושאת את כתובת הנמען',
  (select address from notification_deliveries
    where recipient_id = '20000000-0000-0000-0000-0000000000f3' limit 1), 'clock@vl.test');

-- ההתראה עצמה נכתבת בכל מקרה: המסך אינו תלוי בדואר
select t_eq('וההתראה עצמה נכתבה כרגיל',
  (select count(*) from notifications
    where recipient_id = '20000000-0000-0000-0000-0000000000f3'
      and type = 'task_assigned' and body = 'בדיקה')::int, 1);

-- העדפה פר-סוג גוברת על הכללית
insert into notification_preferences (profile_id, channel, type, enabled) values
  ('20000000-0000-0000-0000-0000000000f3', 'email', 'task_assigned', false);

select t_eq('סוג שהמשתמש כיבה אינו נשלח',
  app.should_email('20000000-0000-0000-0000-0000000000f3', 'task_assigned'), false);

select t_eq('אבל סוג אחר ממשיך להישלח',
  app.should_email('20000000-0000-0000-0000-0000000000f3', 'task_changed'), true);

insert into notification_preferences (profile_id, channel, type, enabled) values
  ('20000000-0000-0000-0000-0000000000f3', 'email', null, false);

select t_eq('כיבוי כללי חוסם סוג שלא הוגדר לו כלום',
  app.should_email('20000000-0000-0000-0000-0000000000f3', 'task_changed'), false);

update notification_preferences set enabled = true
 where profile_id = '20000000-0000-0000-0000-0000000000f3' and channel = 'email' and type = 'task_assigned';

select t_eq('והעדפה לסוג גוברת על הכללי גם לכיוון ההפוך',
  app.should_email('20000000-0000-0000-0000-0000000000f3', 'task_assigned'), true);

-- השתקה גלובלית של סוג גוברת על העדפת המשתמש
update app_settings
   set value = jsonb_set(value, '{muted_types}', '["task_assigned"]'::jsonb)
 where key = 'notifications.email';

select t_eq('סוג מושתק גלובלית אינו נשלח גם למי שביקש אותו',
  app.should_email('20000000-0000-0000-0000-0000000000f3', 'task_assigned'), false);

update app_settings
   set value = jsonb_set(value, '{muted_types}', '[]'::jsonb)
 where key = 'notifications.email';

-- מי שאין לו כתובת אינו מייצר שורת משלוח תלויה
update profiles set email = null where id = '20000000-0000-0000-0000-0000000000f4';
select t_expect_ok('התראה למי שאין לו כתובת', $$
  select app.notify('20000000-0000-0000-0000-0000000000f4', 'task_changed', 'שינוי', 'בדיקה', null, null)$$);
select t_eq('אינה מייצרת שורת משלוח',
  (select count(*) from notification_deliveries
    where recipient_id = '20000000-0000-0000-0000-0000000000f4')::int, 0);

-- ה-outbox אינו קריא לעובד מן השורה
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000f3', false);
select t_eq('עובד אינו רואה את יומן המשלוח',
  (select count(*) from notification_deliveries)::int, 0);
select t_eq('אבל כן רואה את ההעדפות של עצמו',
  (select count(*) > 0 from notification_preferences
    where profile_id = '20000000-0000-0000-0000-0000000000f3'), true);
reset role;
select set_config('request.jwt.claim.sub', '', false);

-- וכיבוי הערוץ מחזיר את המערכת למצב שבו כלום לא יוצא
update app_settings set value = jsonb_set(value, '{enabled}', 'false'::jsonb)
 where key = 'notifications.email';
select t_eq('כיבוי הערוץ עוצר משלוחים חדשים',
  app.should_email('20000000-0000-0000-0000-0000000000f3', 'task_assigned'), false);
