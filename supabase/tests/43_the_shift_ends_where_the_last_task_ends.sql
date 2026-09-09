\pset tuples_only on
\pset format unaligned

-- ===========================================================================
-- ‏43: המשמרת נגמרת במקום שבו המשימה האחרונה נגמרת (0166).
--
-- החבילה מקימה מחסן, לקוח, אירוע, חמישה עובדים וחמש משימות משלה ב-
-- ‏`current_date + 600`, מעבר לכל טווח שחבילה אחרת נוגעת בו. היא משאירה
-- אחריה משימות, שיבוצים ורשומת נוכחות שאינם מנוקים.
--
-- שלוש קבוצות, וכל אחת היא צד אחד של אותו כלל:
--
--   * ‏**שני הקצוות.** שלושה עובדים על אותן שתי משימות בדיוק, ונבדלים רק
--     בשאלה מאיפה כל אחד מתחיל ולאן הוא נגמר. אותן שעות משימה, שלוש שעות
--     סיום שונות — וזה מה שאומר שהסיום נגזר מהקצה שלו ולא מההתחלה.
--   * ‏**החפיפה.** שלוש משימות שנופלות זו על זו, ובהן אחת שנבלעת כולה
--     בתוך קודמתה. סך העבודה הוא איחוד החלונות, ולא סכומם.
--   * ‏**המיקום.** מה שנדגם ברגע ההחתמה מגיע עד הדוח, ולצידו האתר שבו
--     המשמרת נגמרה.
-- ===========================================================================

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000043a1', 'ends-at-warehouse@vl.test'),
  ('00000000-0000-0000-0000-0000000043a2', 'ends-in-field@vl.test'),
  ('00000000-0000-0000-0000-0000000043a3', 'starts-in-field@vl.test'),
  ('00000000-0000-0000-0000-0000000043a4', 'overlapping@vl.test');

-- המחסן והאירוע רחוקים זה מזה בכוונה: כל קואורדינטה בבדיקה מזוהה חד-משמעית.
insert into warehouses (id, name, lat, lng) values
  ('40000000-0000-0000-0000-000000000043', 'מחסן 43', 32.1000, 34.8000);

insert into customers (id, name, warehouse_id) values
  ('10000000-0000-0000-0000-000000000043', 'לקוח 43',
   '40000000-0000-0000-0000-000000000043');

insert into profiles (id, user_id, user_kind, is_admin, full_name) values
  ('20000000-0000-0000-0000-0000000043a1', '00000000-0000-0000-0000-0000000043a1',
   'staff', false, 'מסיים במחסן 43'),
  ('20000000-0000-0000-0000-0000000043a2', '00000000-0000-0000-0000-0000000043a2',
   'staff', false, 'מסיים בשטח 43'),
  ('20000000-0000-0000-0000-0000000043a3', '00000000-0000-0000-0000-0000000043a3',
   'staff', false, 'מתחיל בשטח 43'),
  ('20000000-0000-0000-0000-0000000043a4', '00000000-0000-0000-0000-0000000043a4',
   'staff', false, 'חופף 43');

insert into user_permission_grants (profile_id, permission_key, allowed)
select p, k, true from unnest(array[
  '20000000-0000-0000-0000-0000000043a1'::uuid,
  '20000000-0000-0000-0000-0000000043a2'::uuid,
  '20000000-0000-0000-0000-0000000043a3'::uuid,
  '20000000-0000-0000-0000-0000000043a4'::uuid]) p,
  unnest(array['attendance.view_schedule', 'attendance.view_own']) k;

insert into events (id, customer_id, event_number, event_date,
                    location_text, location_lat, location_lng) values
  ('30000000-0000-0000-0000-000000000043', '10000000-0000-0000-0000-000000000043',
   'EV-43', current_date + 600, 'רעננה', 32.2000, 34.9000);

insert into tasks (id, event_id, customer_id, task_type_id, task_date,
                   warehouse_start_time, onsite_start_time, hours_count,
                   travel_hours, status_id, worker_count)
select v.id, '30000000-0000-0000-0000-000000000043',
       '10000000-0000-0000-0000-000000000043',
       (select id from task_types where code = 'setup' limit 1),
       current_date + 600, v.wh, v.onsite, v.hrs, v.travel,
       (select id from statuses where entity = 'task' and code = 'assigned' and deleted_at is null),
       3
from (values
  -- שתי המשימות של "שני הקצוות". הפער ביניהן שעה — פחות מ-120 דקות —
  -- ולכן הן משמרת אחת. זמני הנסיעה שונים, כדי ש"האחרונה" ו"הראשונה"
  -- ייתנו תשובות שונות.
  ('62000000-0000-0000-0000-000000043001'::uuid, '07:00'::time, '08:00'::time, 2.0::numeric, 0.50::numeric),
  ('62000000-0000-0000-0000-000000043002'::uuid, null::time,    '11:00'::time, 2.0::numeric, 0.75::numeric),
  -- שלוש המשימות של החפיפה: 08–12, 10–14, ו-10:30–11:30 שנבלעת בשתיהן.
  ('62000000-0000-0000-0000-000000043003'::uuid, null::time,    '08:00'::time, 4.0::numeric, 0::numeric),
  ('62000000-0000-0000-0000-000000043004'::uuid, null::time,    '10:00'::time, 4.0::numeric, 0::numeric),
  ('62000000-0000-0000-0000-000000043005'::uuid, null::time,    '10:30'::time, 1.0::numeric, 0::numeric)
) as v(id, wh, onsite, hrs, travel);

-- שלושה עובדים, אותן שתי משימות, ורק נקודות ההתחלה והסיום נבדלות.
insert into task_assignments (task_id, profile_id, role, work_site) values
  ('62000000-0000-0000-0000-000000043001', '20000000-0000-0000-0000-0000000043a1', 'worker', 'warehouse'),
  ('62000000-0000-0000-0000-000000043002', '20000000-0000-0000-0000-0000000043a1', 'worker', 'warehouse'),
  ('62000000-0000-0000-0000-000000043001', '20000000-0000-0000-0000-0000000043a2', 'worker', 'warehouse'),
  ('62000000-0000-0000-0000-000000043002', '20000000-0000-0000-0000-0000000043a2', 'worker', 'field'),
  ('62000000-0000-0000-0000-000000043001', '20000000-0000-0000-0000-0000000043a3', 'worker', 'field'),
  ('62000000-0000-0000-0000-000000043002', '20000000-0000-0000-0000-0000000043a3', 'worker', 'warehouse'),
  ('62000000-0000-0000-0000-000000043003', '20000000-0000-0000-0000-0000000043a4', 'worker', 'field'),
  ('62000000-0000-0000-0000-000000043004', '20000000-0000-0000-0000-0000000043a4', 'worker', 'field'),
  ('62000000-0000-0000-0000-000000043005', '20000000-0000-0000-0000-0000000043a4', 'worker', 'field');


\echo '--- הסיום נגזר מהמשימה האחרונה ---'

-- מחסן ⇒ מחסן: 11:00 ועוד שעתיים, ועוד 0.75 של הנסיעה חזרה
select t_eq('מי שמסיים במחסן מקבל את הנסיעה חזרה של המשימה האחרונה',
  (select to_char(shift_end at time zone 'Asia/Jerusalem', 'HH24:MI')
     from app.planned_shifts('20000000-0000-0000-0000-0000000043a1',
                             current_date + 600, current_date + 600)),
  '13:45');

select t_eq('והנסיעה היא של האחרונה (0.75) ולא של הראשונה (0.5)',
  (select travel_hours from app.planned_shifts('20000000-0000-0000-0000-0000000043a1',
                                               current_date + 600, current_date + 600)),
  0.75::numeric);

-- מחסן ⇒ שטח: אותן שתי משימות בדיוק, ואין נסיעה חזרה כלל
select t_eq('מי שמסיים בשטח מסיים בשעת השטח, בלי נסיעה',
  (select to_char(shift_end at time zone 'Asia/Jerusalem', 'HH24:MI')
     from app.planned_shifts('20000000-0000-0000-0000-0000000043a2',
                             current_date + 600, current_date + 600)),
  '13:00');

select t_eq('ולכן גם אין לו זמן נסיעה',
  (select travel_hours from app.planned_shifts('20000000-0000-0000-0000-0000000043a2',
                                               current_date + 600, current_date + 600)),
  0::numeric);

-- שטח ⇒ מחסן: המקרה ההפוך, זה שעד 0166 *לא* קיבל את הנסיעה שהוא כן נוסע
select t_eq('מי שמתחיל בשטח ומסיים במחסן כן מקבל את הנסיעה',
  (select to_char(shift_end at time zone 'Asia/Jerusalem', 'HH24:MI')
     from app.planned_shifts('20000000-0000-0000-0000-0000000043a3',
                             current_date + 600, current_date + 600)),
  '13:45');

select t_eq('והתחלתו היא שעת השטח ולא שעת המחסן',
  (select to_char(shift_start at time zone 'Asia/Jerusalem', 'HH24:MI')
     from app.planned_shifts('20000000-0000-0000-0000-0000000043a3',
                             current_date + 600, current_date + 600)),
  '08:00');

-- 08:00 עד 13:45 = 5.75, מול 6.75 של מי שיצא מהמחסן ב-07:00
select t_eq('ואורך המשמרת נמדד בין שני הקצוות שלו',
  (select planned_hours from app.planned_shifts('20000000-0000-0000-0000-0000000043a3',
                                                current_date + 600, current_date + 600)),
  5.75::numeric);


\echo '--- וכך גם המיקום בשני הקצוות ---'

select t_eq('ההתחלה של מי שיצא מהמחסן היא המחסן',
  (select start_lat from app.planned_shifts('20000000-0000-0000-0000-0000000043a1',
                                            current_date + 600, current_date + 600)),
  32.1000::double precision);

select t_eq('וההתחלה של מי שהגיע לשטח היא מיקום האירוע',
  (select start_lat from app.planned_shifts('20000000-0000-0000-0000-0000000043a3',
                                            current_date + 600, current_date + 600)),
  32.2000::double precision);

select t_eq('הסיום של מי שחוזר למחסן הוא המחסן',
  (select end_lat from app.planned_shifts('20000000-0000-0000-0000-0000000043a1',
                                          current_date + 600, current_date + 600)),
  32.1000::double precision);

select t_eq('והסיום של מי שנשאר בשטח הוא מיקום האירוע',
  (select end_lat from app.planned_shifts('20000000-0000-0000-0000-0000000043a2',
                                          current_date + 600, current_date + 600)),
  32.2000::double precision);

-- הנקודה השנייה שההחתמה מקבלת: השטח שממנו יוצאים חזרה למחסן
select t_eq('והשטח נשמר בשמו, כנקודת היציאה השנייה',
  (select onsite_end_lat from app.planned_shifts('20000000-0000-0000-0000-0000000043a1',
                                                 current_date + 600, current_date + 600)),
  32.2000::double precision);

select t_eq('האתר שבו המשמרת נגמרת נאמר במפורש',
  (select end_site from app.planned_shifts('20000000-0000-0000-0000-0000000043a1',
                                           current_date + 600, current_date + 600)),
  'warehouse');

select t_eq('ולצידו שם המחסן שחוזרים אליו',
  (select end_warehouse_name from app.planned_shifts('20000000-0000-0000-0000-0000000043a1',
                                                     current_date + 600, current_date + 600)),
  'מחסן 43');

select t_eq('מי שמסיים בשטח אינו נושא מחסן סיום',
  (select end_warehouse_name from app.planned_shifts('20000000-0000-0000-0000-0000000043a2',
                                                     current_date + 600, current_date + 600)),
  null::text);

-- ‏`work_site` נשאר שאלה על ההתחלה בלבד, ולכן שני העובדים ההפוכים אינם זהים
select t_eq('work_site ממשיך לתאר את ההתחלה',
  (select work_site from app.planned_shifts('20000000-0000-0000-0000-0000000043a3',
                                            current_date + 600, current_date + 600)),
  'field');

select t_eq('ואת אותו קצה בדיוק גוזרת גם app.shift_end_place',
  app.shift_end_place('20000000-0000-0000-0000-0000000043a1',
    array['62000000-0000-0000-0000-000000043001',
          '62000000-0000-0000-0000-000000043002']::uuid[]) ->> 'warehouse_name',
  'מחסן 43');

select t_eq('ולמי שנשאר בשטח היא אומרת שטח',
  app.shift_end_place('20000000-0000-0000-0000-0000000043a2',
    array['62000000-0000-0000-0000-000000043001',
          '62000000-0000-0000-0000-000000043002']::uuid[]) ->> 'work_site',
  'field');


\echo '--- הפירוק במגירה אומר את אותה שעה ---'

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000043a1', false);

select t_eq('המגירה מסיימת בשעה שהגזירה מסיימת בה',
  to_char((shift_task_breakdown('20000000-0000-0000-0000-0000000043a1',
    array['62000000-0000-0000-0000-000000043001',
          '62000000-0000-0000-0000-000000043002']::uuid[]) -> 'shift' ->> 'end')::timestamptz
    at time zone 'Asia/Jerusalem', 'HH24:MI'),
  '13:45');

select t_eq('והנסיעה שבה היא של המשימה האחרונה',
  (shift_task_breakdown('20000000-0000-0000-0000-0000000043a1',
    array['62000000-0000-0000-0000-000000043001',
          '62000000-0000-0000-0000-000000043002']::uuid[]) -> 'totals' ->> 'travel_hours')::numeric,
  0.75::numeric);

select t_eq('ושני הקצוות נאמרים בה בנפרד',
  (shift_task_breakdown('20000000-0000-0000-0000-0000000043a1',
    array['62000000-0000-0000-0000-000000043001',
          '62000000-0000-0000-0000-000000043002']::uuid[]) -> 'shift' ->> 'end_work_site'),
  'warehouse');

reset role;
select set_config('request.jwt.claim.sub', '', false);

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000043a2', false);

select t_eq('ולמי שמסיים בשטח המגירה אומרת שטח, בלי נסיעה',
  (shift_task_breakdown('20000000-0000-0000-0000-0000000043a2',
    array['62000000-0000-0000-0000-000000043001',
          '62000000-0000-0000-0000-000000043002']::uuid[]) -> 'totals' ->> 'travel_hours')::numeric,
  0::numeric);

reset role;
select set_config('request.jwt.claim.sub', '', false);


\echo '--- משימות חופפות נספרות פעם אחת ---'

-- 08:00–12:00, 10:00–14:00, ו-10:30–11:30 — סכומן 9 שעות, ואיחודן 6
select t_eq('סך המשמרת הוא החלון, ולא סכום המשימות',
  (select planned_hours from app.planned_shifts('20000000-0000-0000-0000-0000000043a4',
                                                current_date + 600, current_date + 600)),
  6.00::numeric);

select t_eq('ושלוש המשימות הן משמרת אחת',
  (select count(*) from app.planned_shifts('20000000-0000-0000-0000-0000000043a4',
                                           current_date + 600, current_date + 600))::int, 1);

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000043a4', false);

select t_eq('שעות העבודה בפירוק הן איחוד החלונות',
  (shift_task_breakdown('20000000-0000-0000-0000-0000000043a4',
    array['62000000-0000-0000-0000-000000043003',
          '62000000-0000-0000-0000-000000043004',
          '62000000-0000-0000-0000-000000043005']::uuid[]) -> 'totals' ->> 'work_hours')::numeric,
  6.00::numeric);

select t_eq('וההפרש מהסכום נאמר במפורש כחפיפה',
  (shift_task_breakdown('20000000-0000-0000-0000-0000000043a4',
    array['62000000-0000-0000-0000-000000043003',
          '62000000-0000-0000-0000-000000043004',
          '62000000-0000-0000-0000-000000043005']::uuid[]) -> 'totals' ->> 'overlap_hours')::numeric,
  3.00::numeric);

select t_eq('הראשונה אינה חופפת לאיש',
  (shift_task_breakdown('20000000-0000-0000-0000-0000000043a4',
    array['62000000-0000-0000-0000-000000043003',
          '62000000-0000-0000-0000-000000043004',
          '62000000-0000-0000-0000-000000043005']::uuid[]) -> 'tasks' -> 0 ->> 'overlap_minutes')::int,
  0);

select t_eq('השנייה חופפת לה שעתיים',
  (shift_task_breakdown('20000000-0000-0000-0000-0000000043a4',
    array['62000000-0000-0000-0000-000000043003',
          '62000000-0000-0000-0000-000000043004',
          '62000000-0000-0000-0000-000000043005']::uuid[]) -> 'tasks' -> 1 ->> 'overlap_minutes')::int,
  120);

-- זו הבדיקה של "המקסימום ולא הקודמת": 10:30–11:30 נבלעת בתוך 10:00–14:00
-- *וגם* בתוך 08:00–12:00, ו-lag לבדו היה מודד אותה מול הקודמת בלבד.
select t_eq('והשלישית, שנבלעת כולה, חופפת בכל אורכה',
  (shift_task_breakdown('20000000-0000-0000-0000-0000000043a4',
    array['62000000-0000-0000-0000-000000043003',
          '62000000-0000-0000-0000-000000043004',
          '62000000-0000-0000-0000-000000043005']::uuid[]) -> 'tasks' -> 2 ->> 'overlap_minutes')::int,
  60);

select t_eq('ואין בה המתנה, כי אין רגע שבו לא עובדים',
  (shift_task_breakdown('20000000-0000-0000-0000-0000000043a4',
    array['62000000-0000-0000-0000-000000043003',
          '62000000-0000-0000-0000-000000043004',
          '62000000-0000-0000-0000-000000043005']::uuid[]) -> 'totals' ->> 'idle_minutes')::int,
  0);

reset role;
select set_config('request.jwt.claim.sub', '', false);


\echo '--- המיקום שנדגם בהחתמה מגיע עד הדוח ---'

insert into attendance_entries (
  id, profile_id, work_date, seq, shift_start, shift_end, planned_hours,
  work_site, task_ids, clock_in_at, clock_in_lat, clock_in_lng,
  clock_out_at, clock_out_lat, clock_out_lng, status)
values (
  '70000000-0000-0000-0000-000000000043', '20000000-0000-0000-0000-0000000043a1',
  current_date + 600, 1,
  ((current_date + 600) + time '07:00') at time zone 'Asia/Jerusalem',
  ((current_date + 600) + time '13:45') at time zone 'Asia/Jerusalem',
  6.75, 'warehouse',
  array['62000000-0000-0000-0000-000000043001',
        '62000000-0000-0000-0000-000000043002']::uuid[],
  ((current_date + 600) + time '07:02') at time zone 'Asia/Jerusalem', 32.1001, 34.8002,
  ((current_date + 600) + time '13:50') at time zone 'Asia/Jerusalem', 32.1003, 34.8004,
  'approved');

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000043a1', false);

select t_eq('הקואורדינטה של הכניסה מגיעה לשורה',
  (select (r ->> 'in_lat')::double precision
     from jsonb_array_elements(attendance_report(current_date + 600, current_date + 600) -> 'rows') r
    where r ->> 'id' = '70000000-0000-0000-0000-000000000043'),
  32.1001::double precision);

select t_eq('וגם זו של היציאה',
  (select (r ->> 'out_lng')::double precision
     from jsonb_array_elements(attendance_report(current_date + 600, current_date + 600) -> 'rows') r
    where r ->> 'id' = '70000000-0000-0000-0000-000000000043'),
  34.8004::double precision);

select t_eq('והשורה אומרת גם איפה המשמרת נגמרה',
  (select r ->> 'end_work_place'
     from jsonb_array_elements(attendance_report(current_date + 600, current_date + 600) -> 'rows') r
    where r ->> 'id' = '70000000-0000-0000-0000-000000000043'),
  'מחסן 43');

select t_eq('ומאיזה אתר',
  (select r ->> 'end_work_site'
     from jsonb_array_elements(attendance_report(current_date + 600, current_date + 600) -> 'rows') r
    where r ->> 'id' = '70000000-0000-0000-0000-000000000043'),
  'warehouse');

reset role;
select set_config('request.jwt.claim.sub', '', false);
