\pset tuples_only on
\pset format unaligned

-- ===========================================================================
-- 41: שעת ההגעה למחסן הולכת אחורה ולא קדימה (0163).
--
-- החבילה מקימה מחסן, לקוח, אירוע, עובד ושתי משימות משלה ב-`current_date + 580`,
-- מעבר לכל טווח שחבילה אחרת נוגעת בו. היא משאירה אחריה משימות ושיבוצים שאינם
-- מנוקים.
--
-- שתי המשימות הן שני הצדדים של אותו כלל, ולא שתי וריאציות עליו:
--
--   * ‏**הלילה** — 23:00 במחסן, 01:00 בשטח. זו המשימה מהדיווח, וההגעה למחסן
--     שלה היא של הערב שלפני.
--   * ‏**היום** — 07:00 במחסן, 08:00 בשטח. שום דבר בה לא זז, וזו בדיוק
--     הנקודה: הכלל אינו מזיז משמרת שאינה חוצה חצות.
-- ===========================================================================

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000041a1', 'night-warehouse@vl.test');

insert into warehouses (id, name, lat, lng) values
  ('40000000-0000-0000-0000-000000000041', 'מחסן הלילה', 32.05, 34.77);

insert into customers (id, name, warehouse_id) values
  ('10000000-0000-0000-0000-000000000041', 'לקוח 41',
   '40000000-0000-0000-0000-000000000041');

insert into profiles (id, user_id, user_kind, is_admin, full_name) values
  ('20000000-0000-0000-0000-0000000041a1', '00000000-0000-0000-0000-0000000041a1',
   'staff', false, 'עובד לילה 41');

insert into user_permission_grants (profile_id, permission_key, allowed) values
  ('20000000-0000-0000-0000-0000000041a1', 'attendance.view_schedule', true);

insert into events (id, customer_id, event_number, event_date,
                    location_text, location_lat, location_lng) values
  ('30000000-0000-0000-0000-000000000041', '10000000-0000-0000-0000-000000000041',
   'EV-41', current_date + 580, 'תל אביב', 32.0853, 34.7818);

insert into tasks (id, event_id, customer_id, task_type_id, task_date,
                   warehouse_start_time, onsite_start_time, hours_count,
                   travel_hours, status_id, worker_count)
select v.id, '30000000-0000-0000-0000-000000000041',
       '10000000-0000-0000-0000-000000000041',
       (select id from task_types where code = 'setup' limit 1),
       v.d, v.wh, v.onsite, v.hrs, v.travel,
       (select id from statuses where entity = 'task' and code = 'assigned' and deleted_at is null),
       1
from (values
  -- הלילה: 23:00 במחסן, 01:00 בשטח, ארבע שעות ועוד חצי שעת נסיעה חזרה
  ('61000000-0000-0000-0000-000000041001'::uuid, (current_date + 580)::date,
   '23:00'::time, '01:00'::time, 4.0::numeric, 0.5::numeric),
  -- היום: 07:00 במחסן, 08:00 בשטח
  ('61000000-0000-0000-0000-000000041002'::uuid, (current_date + 583)::date,
   '07:00'::time, '08:00'::time, 3.0::numeric, 0.5::numeric)
) as v(id, d, wh, onsite, hrs, travel);

insert into task_assignments (task_id, profile_id, role, work_site) values
  ('61000000-0000-0000-0000-000000041001', '20000000-0000-0000-0000-0000000041a1', 'worker', 'warehouse'),
  ('61000000-0000-0000-0000-000000041002', '20000000-0000-0000-0000-0000000041a1', 'worker', 'warehouse');


\echo '--- הכלל עצמו ---'

-- הדוגמה מהדיווח, מילה במילה: משימה של 11.9 שמתחילה ב-01:00, ומחסן ב-23:00
select t_eq('23:00 מול שטח ב-01:00 הוא הערב שלפני',
  app.warehouse_start_at(date '2026-09-11', time '23:00', time '01:00'),
  timestamp '2026-09-10 23:00' at time zone 'Asia/Jerusalem');

select t_eq('07:00 מול שטח ב-08:00 נשאר באותו יום',
  app.warehouse_start_at(date '2026-09-11', time '07:00', time '08:00'),
  timestamp '2026-09-11 07:00' at time zone 'Asia/Jerusalem');

select t_eq('שעה זהה אינה נסיגה',
  app.warehouse_start_at(date '2026-09-11', time '08:00', time '08:00'),
  timestamp '2026-09-11 08:00' at time zone 'Asia/Jerusalem');

-- בלי שעת שטח, שעת המחסן היא בעצמה תחילת המשימה — אין מול מה לסגת
select t_eq('בלי שעת שטח אין נסיגה',
  app.warehouse_start_at(date '2026-09-11', time '23:00', null),
  timestamp '2026-09-11 23:00' at time zone 'Asia/Jerusalem');

select t_eq('בלי שעת מחסן אין רגע', app.warehouse_start_at(date '2026-09-11', null, time '01:00'),
  null::timestamptz);

-- הנסיגה היא יום קלנדרי ולא 24 שעות: בלילה שבו השעון חוזר (25/10/2026,
-- 02:00 → 01:00) 23:00 של אתמול נשאר 23:00 של אתמול.
select t_eq('הנסיגה שורדת את מעבר השעון',
  to_char(app.warehouse_start_at(date '2026-10-25', time '23:00', time '01:00')
            at time zone 'Asia/Jerusalem', 'DD/MM HH24:MI'),
  '24/10 23:00');


\echo '--- חלון המשימה, שממנו נגזרות ההתנגשויות ---'

select t_eq('החלון של מי שיוצא מהמחסן נפתח בערב שלפני',
  to_char(lower(app.task_window('61000000-0000-0000-0000-000000041001', true))
            at time zone 'Asia/Jerusalem', 'YYYY-MM-DD HH24:MI'),
  to_char(current_date + 579, 'YYYY-MM-DD') || ' 23:00');

select t_eq('ושל מי שמגיע לשטח — בשעת השטח, כפי שהיה',
  to_char(lower(app.task_window('61000000-0000-0000-0000-000000041001', false))
            at time zone 'Asia/Jerusalem', 'YYYY-MM-DD HH24:MI'),
  to_char(current_date + 580, 'YYYY-MM-DD') || ' 01:00');

select t_eq('הסיום לא זז: 01:00 ועוד ארבע שעות',
  to_char(upper(app.task_window('61000000-0000-0000-0000-000000041001', true))
            at time zone 'Asia/Jerusalem', 'YYYY-MM-DD HH24:MI'),
  to_char(current_date + 580, 'YYYY-MM-DD') || ' 05:00');


\echo '--- גזירת המשמרת ---'

select t_eq('המשמרת מתחילה ב-23:00 של הערב שלפני',
  (select to_char(shift_start at time zone 'Asia/Jerusalem', 'YYYY-MM-DD HH24:MI')
     from app.planned_shifts('20000000-0000-0000-0000-0000000041a1',
                             current_date + 579, current_date + 579)),
  to_char(current_date + 579, 'YYYY-MM-DD') || ' 23:00');

select t_eq('והיא נתלית על היום שבו התחילה',
  (select work_date from app.planned_shifts('20000000-0000-0000-0000-0000000041a1',
                                            current_date + 579, current_date + 579)),
  (current_date + 579)::date);

-- 23:00 עד 05:00 (01:00 ועוד ארבע) ועוד חצי שעת נסיעה חזרה = 6.5
select t_eq('ואורכה נמדד מהמחסן ועד החזרה אליו',
  (select planned_hours from app.planned_shifts('20000000-0000-0000-0000-0000000041a1',
                                                current_date + 579, current_date + 579)),
  6.50::numeric);

-- המשימה של היום שאחרי החלון נשאבת פנימה, ולכן הלוח שמציג את 579 רואה אותה
select t_eq('לוח שמסתיים ביום שלפני המשימה עדיין מראה אותה',
  (select count(*) from app.planned_shifts('20000000-0000-0000-0000-0000000041a1',
                                           current_date + 577, current_date + 579))::int, 1);

-- ...ובדיוק פעם אחת: הלוח של היום שאחריו כבר אינו התא שלה
select t_eq('והלוח של יום המשימה עצמו כבר אינו מראה אותה',
  (select count(*) from app.planned_shifts('20000000-0000-0000-0000-0000000041a1',
                                           current_date + 580, current_date + 582))::int, 0);

\echo '--- ומשמרת יום אינה זזה ---'

select t_eq('משמרת יום מתחילה בשעת המחסן של אותו יום',
  (select to_char(shift_start at time zone 'Asia/Jerusalem', 'YYYY-MM-DD HH24:MI')
     from app.planned_shifts('20000000-0000-0000-0000-0000000041a1',
                             current_date + 583, current_date + 583)),
  to_char(current_date + 583, 'YYYY-MM-DD') || ' 07:00');

select t_eq('והיא נתלית על היום של המשימה',
  (select work_date from app.planned_shifts('20000000-0000-0000-0000-0000000041a1',
                                            current_date + 583, current_date + 583)),
  (current_date + 583)::date);


\echo '--- פירוק המשמרת אומר את אותה שעה ---'

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000041a1', false);

select t_eq('ההגעה למחסן היא של הערב שלפני',
  to_char((shift_task_breakdown('20000000-0000-0000-0000-0000000041a1',
    array['61000000-0000-0000-0000-000000041001']::uuid[])
    -> 'tasks' -> 0 ->> 'warehouse_start_at')::timestamptz
      at time zone 'Asia/Jerusalem', 'YYYY-MM-DD HH24:MI'),
  to_char(current_date + 579, 'YYYY-MM-DD') || ' 23:00');

select t_eq('תחילת העבודה בשטח נשארה 01:00 של יום המשימה',
  to_char((shift_task_breakdown('20000000-0000-0000-0000-0000000041a1',
    array['61000000-0000-0000-0000-000000041001']::uuid[])
    -> 'tasks' -> 0 ->> 'start_at')::timestamptz
      at time zone 'Asia/Jerusalem', 'YYYY-MM-DD HH24:MI'),
  to_char(current_date + 580, 'YYYY-MM-DD') || ' 01:00');

select t_eq('ותחילת המשמרת היא המוקדמת מבין השתיים',
  to_char((shift_task_breakdown('20000000-0000-0000-0000-0000000041a1',
    array['61000000-0000-0000-0000-000000041001']::uuid[])
    -> 'shift' ->> 'start')::timestamptz
      at time zone 'Asia/Jerusalem', 'YYYY-MM-DD HH24:MI'),
  to_char(current_date + 579, 'YYYY-MM-DD') || ' 23:00');

reset role;
select set_config('request.jwt.claim.sub', '', false);
