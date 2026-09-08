\pset tuples_only on
\pset format unaligned

-- ===========================================================================
-- 39: מקום בלי קואורדינטות אינו דורש מיקום (0159).
--
-- החבילה מקימה לקוח **בלי מחסן**, אירוע שהמיקום שלו הוקלד ידנית ואין לו
-- קואורדינטות, משימה אחת ועובד אחד, ב-`current_date + 560` — ואת המשימה
-- עצמה היא מעגנת סביב `now()`, כי כל בדיקה כאן היא החתמה אמיתית מול השעון.
--
-- שלוש הטענות שהיא מחזיקה, ובסדר הזה:
--
--   1. **בלי נקודת ייחוס אין דרישה.** ההחתמה עוברת בלי קריאת GPS כלל,
--      ומסומנת `no_site_coords` — המנהל יודע שהיא לא אומתה.
--   2. **עם נקודת ייחוס הדרישה עומדת.** אותו עובד, אותה הגדרה, אירוע עם
--      קואורדינטות: החתמה בלי מיקום נדחית, ורחוקה נדחית גם היא. הפטור אינו
--      דלת אחורית למי שפשוט אינו מוכן לשתף מיקום.
--   3. **השעות לא זזו.** גם כשהמיקום אינו מאמת דבר, כניסה לפני תחילת
--      המשמרת עדיין נחסמת. זה מה ש"מכל מקום, אבל לפי שעות המשמרת" אומר.
-- ===========================================================================

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000039a1', 'c39-worker@vl.test');

insert into customers (id, name) values
  ('10000000-0000-0000-0000-000000000391', 'לקוח 39');

insert into profiles (id, user_id, user_kind, is_admin, full_name) values
  ('20000000-0000-0000-0000-0000000039a1', '00000000-0000-0000-0000-0000000039a1',
   'staff', false, 'עובד 39');

-- מיקום שהוקלד ידנית: יש מלל, אין נקודה. בדיוק מה ש-0157 מאפשר לשמור.
insert into events (id, customer_id, event_number, event_date, location_text,
                    location_lat, location_lng, status_id)
values ('30000000-0000-0000-0000-000000000391', '10000000-0000-0000-0000-000000000391',
        'EV-39', current_date + 560, 'מתחם האירועים בכניסה לקיבוץ, ליד השער הצפוני',
        null, null,
        (select id from statuses where entity = 'event' and code = 'pending' and deleted_at is null));

insert into tasks (id, event_id, customer_id, task_type_id, task_date, onsite_start_time,
                   hours_count, travel_hours, worker_count, status_id)
values ('40000000-0000-0000-0000-000000000391', '30000000-0000-0000-0000-000000000391',
        '10000000-0000-0000-0000-000000000391',
        (select id from task_types where code = 'setup'),
        current_date + 560, '09:00', 6.0, 0, 1,
        (select id from statuses where entity = 'task' and code = 'assigned'));

insert into task_assignments (task_id, profile_id, role, work_site) values
  ('40000000-0000-0000-0000-000000000391', '20000000-0000-0000-0000-0000000039a1', 'worker', 'field');

-- "נדרש מיקום" דלוק, וכניסה מוקדמת אסורה — שתי ההגדרות שהבדיקה כולה עומדת
-- עליהן. בלי הראשונה אין מה לפטור, ובלי השנייה אין מה לשמור.
insert into worker_pay_settings (profile_id, hourly_rate, requires_location,
                                 location_radius_m, allow_early_clock_in)
values ('20000000-0000-0000-0000-0000000039a1', 50, true, 300, false);

-- המשימה מעוגנת לשעה שעברה, כמו בחבילה 04: השעון נמדד מול `now()`, ומשמרת
-- שנזרעה בשעה קבועה הייתה "עוד לא התחילה" בחצי מהיממה.
do $$
declare
  now_il timestamp := now() at time zone 'Asia/Jerusalem';
  start_t time;
begin
  start_t := case when now_il::time < '01:00' then '00:00'::time
                  else (now_il - interval '1 hour')::time end;
  update tasks set task_date = now_il::date, onsite_start_time = start_t
   where id = '40000000-0000-0000-0000-000000000391';
end $$;

select t_eq('לעובד 39 יש בדיוק משמרת אחת, והיא בשטח',
  (select work_site from app.planned_shifts('20000000-0000-0000-0000-0000000039a1',
     (now() at time zone 'Asia/Jerusalem')::date, (now() at time zone 'Asia/Jerusalem')::date)),
  'field');

select t_eq('ואין לה נקודת ייחוס להתחלה',
  (select start_lat from app.planned_shifts('20000000-0000-0000-0000-0000000039a1',
     (now() at time zone 'Asia/Jerusalem')::date, (now() at time zone 'Asia/Jerusalem')::date)),
  null::double precision);


\echo '--- 1. בלי קואורדינטות: החתמה מכל מקום, בלי לבקש GPS ---'

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000039a1', false);

select t_eq('השעון אומר למסך שאינו זקוק למיקום',
  (attendance_my_status() ->> 'location_required')::boolean, false);

select t_eq('וההגדרה עצמה בכל זאת דורשת מיקום',
  (attendance_my_status() #>> '{rules,requires_location}')::boolean, true);

select t_expect_ok('כניסה בלי קריאת מיקום מתקבלת',
  $$select attendance_clock_in(null, null, null, null)$$);

reset role;
select set_config('request.jwt.claim.sub', '', false);

select t_eq('ונרשמה רשומה אחת',
  (select count(*) from attendance_entries
    where profile_id = '20000000-0000-0000-0000-0000000039a1')::int, 1);

select t_eq('היא מסומנת כלא מאומתת',
  (select 'no_site_coords' = any(flags) from attendance_entries
    where profile_id = '20000000-0000-0000-0000-0000000039a1'), true);

select t_eq('ואין עליה מרחק — לא היה מול מה למדוד',
  (select clock_in_distance_m from attendance_entries
    where profile_id = '20000000-0000-0000-0000-0000000039a1'), null::numeric);

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000039a1', false);
select t_expect_ok('וגם היציאה אינה דורשת מיקום',
  $$select attendance_clock_out(null, null, null, null)$$);
reset role;
select set_config('request.jwt.claim.sub', '', false);

delete from attendance_entries where profile_id = '20000000-0000-0000-0000-0000000039a1';


\echo '--- 2. עם קואורדינטות: הדרישה עומדת כפי שהייתה ---'

update events set location_lat = 32.0853, location_lng = 34.7818
 where id = '30000000-0000-0000-0000-000000000391';

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000039a1', false);

select t_eq('עכשיו השעון מבקש מיקום',
  (attendance_my_status() ->> 'location_required')::boolean, true);

select t_expect_fail('כניסה בלי קריאה נדחית',
  $$select attendance_clock_in(null, null, null, null)$$);

-- ירושלים מול תל אביב — כ-54 ק״מ
select t_expect_fail('וכניסה מרחוק נדחית',
  $$select attendance_clock_in(31.7683, 35.2137, 10, null)$$);

-- כ-100 מ׳ מהאתר
select t_expect_ok('כניסה מהאתר עצמו מתקבלת',
  $$select attendance_clock_in(32.0862, 34.7818, 15, null)$$);

reset role;
select set_config('request.jwt.claim.sub', '', false);

select t_eq('ועליה נשמר המרחק',
  (select clock_in_distance_m < 300 from attendance_entries
    where profile_id = '20000000-0000-0000-0000-0000000039a1'), true);

select t_eq('והיא אינה מסומנת כלא מאומתת',
  (select 'no_site_coords' = any(flags) from attendance_entries
    where profile_id = '20000000-0000-0000-0000-0000000039a1'), false);

delete from attendance_entries where profile_id = '20000000-0000-0000-0000-0000000039a1';


\echo '--- 3. הפטור הוא על המקום, לא על השעות ---'

-- אותו אירוע בלי נקודה, והמשמרת מוזזת קדימה: אין מה לאמת במיקום, ולכן
-- השעות הן כל מה שנשאר — והן עדיין חוסמות.
update events set location_lat = null, location_lng = null
 where id = '30000000-0000-0000-0000-000000000391';

do $$
declare later_il timestamp := (now() at time zone 'Asia/Jerusalem') + interval '6 hours';
begin
  update tasks set task_date = later_il::date, onsite_start_time = later_il::time
   where id = '40000000-0000-0000-0000-000000000391';
end $$;

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000039a1', false);

select t_expect_fail('כניסה לפני תחילת המשמרת נחסמת גם בלי קואורדינטות',
  $$select attendance_clock_in(null, null, null, null)$$);

reset role;
select set_config('request.jwt.claim.sub', '', false);

select t_eq('ולא נוצרה רשומה',
  (select count(*) from attendance_entries
    where profile_id = '20000000-0000-0000-0000-0000000039a1')::int, 0);
