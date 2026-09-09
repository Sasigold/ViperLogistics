\pset tuples_only on
\pset format unaligned

-- ===========================================================================
-- ‏44: הכניסה נפתחת רק כשיש משמרת עכשיו (0168).
--
-- החבילה מקימה לקוח, אירוע, קבלן, שלושה עובדי סגל ועובד קבלן אחד, וארבע
-- משימות — אחת לכל אדם, כדי שאפשר יהיה להזיז כל אחת מהן על ציר הזמן בלי
-- לגעת בשאר. כל בדיקה כאן היא החתמה אמיתית מול `now()`, ולכן המשימות
-- מעוגנות אליו ולא לשעה קבועה; האירוע יושב מחוץ לכל טווח אחר, וללא
-- קואורדינטות, כדי שהמיקום לא ייכנס לתמונה כלל (0159).
--
-- ארבע הטענות שהיא מחזיקה:
--
--   1. **משמרת שנגמרה אינה משמרת.** ‏`app.shift_at` מחזירה אותה כ"הקרובה
--      ביותר", ועד 0168 די היה בכך כדי לפתוח את השעון שעות אחריה — ואפילו
--      למחרת. עכשיו היא נחסמת, והשעון אומר למה.
--   2. **ובזמן המשמרת היא נפתחת.** אותו עובד, אותה משימה, שעה אחרת.
--   3. **שתי הדלתות נשארו במקומן.** ‏`allow_early_clock_in` מדבר על קדימה
--      בלבד — משמרת שנגמרה אינה נפתחת בו — ו-`allow_clock_without_shift`
--      מחתים בלי משמרת, ובלי לשאול ממנה שעות שאינן שלו.
--   4. **עובד קבלן נמדד באותה אמת מידה בדיוק**, אף שהשיבוץ שלו מגיע
--      מטבלה אחרת.
-- ===========================================================================

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000044a1', 'c44-worker@vl.test'),
  ('00000000-0000-0000-0000-0000000044a2', 'c44-no-shift@vl.test'),
  ('00000000-0000-0000-0000-0000000044a3', 'c44-early@vl.test'),
  ('00000000-0000-0000-0000-0000000044b2', 'c44-kworker@vl.test');

insert into customers (id, name) values
  ('10000000-0000-0000-0000-000000000044', 'לקוח 44');

insert into contractors (id, name) values
  ('40000000-0000-0000-0000-000000000044', 'קבלן 44');

insert into contractor_workers (id, contractor_id, full_name, user_id) values
  ('50000000-0000-0000-0000-000000000044', '40000000-0000-0000-0000-000000000044',
   'עובד הקבלן 44', '00000000-0000-0000-0000-0000000044b2');

insert into profiles (id, user_id, user_kind, is_admin, full_name,
                      contractor_id, contractor_worker_id) values
  ('20000000-0000-0000-0000-0000000044a1', '00000000-0000-0000-0000-0000000044a1',
   'staff', false, 'עובד 44', null, null),
  ('20000000-0000-0000-0000-0000000044a2', '00000000-0000-0000-0000-0000000044a2',
   'staff', false, 'מחתים בלי שיבוץ 44', null, null),
  ('20000000-0000-0000-0000-0000000044a3', '00000000-0000-0000-0000-0000000044a3',
   'staff', false, 'מתחיל מוקדם 44', null, null),
  ('20000000-0000-0000-0000-0000000044b2', '00000000-0000-0000-0000-0000000044b2',
   'contractor_user', false, 'עובד הקבלן 44',
   '40000000-0000-0000-0000-000000000044', '50000000-0000-0000-0000-000000000044');

insert into user_permission_grants (profile_id, permission_key, allowed)
select p, 'attendance.view_own', true from unnest(array[
  '20000000-0000-0000-0000-0000000044a1'::uuid,
  '20000000-0000-0000-0000-0000000044a2'::uuid,
  '20000000-0000-0000-0000-0000000044a3'::uuid,
  '20000000-0000-0000-0000-0000000044b2'::uuid]) p;

-- אירוע בלי קואורדינטות: הבדיקה כולה היא על הזמן, ולא על המקום.
insert into events (id, customer_id, event_number, event_date, location_text,
                    location_lat, location_lng) values
  ('30000000-0000-0000-0000-000000000044', '10000000-0000-0000-0000-000000000044',
   'EV-44', current_date + 610, 'אולם ללא נקודה', null, null);

insert into tasks (id, event_id, customer_id, task_type_id, task_date,
                   onsite_start_time, hours_count, travel_hours, status_id, worker_count)
select v.id, '30000000-0000-0000-0000-000000000044',
       '10000000-0000-0000-0000-000000000044',
       (select id from task_types where code = 'setup' limit 1),
       current_date + 610, '09:00', 4.0, 0,
       (select id from statuses where entity = 'task' and code = 'assigned'
          and deleted_at is null),
       1
from (values
  ('60000000-0000-0000-0000-0000000044a1'::uuid),
  ('60000000-0000-0000-0000-0000000044a2'::uuid),
  ('60000000-0000-0000-0000-0000000044a3'::uuid),
  ('60000000-0000-0000-0000-0000000044b2'::uuid)
) as v(id);

insert into task_assignments (task_id, profile_id, role, work_site) values
  ('60000000-0000-0000-0000-0000000044a1', '20000000-0000-0000-0000-0000000044a1',
   'worker', 'field'),
  ('60000000-0000-0000-0000-0000000044a2', '20000000-0000-0000-0000-0000000044a2',
   'worker', 'field'),
  ('60000000-0000-0000-0000-0000000044a3', '20000000-0000-0000-0000-0000000044a3',
   'worker', 'field');

-- עובד הקבלן מגיע דרך הטבלה שלו, ולא דרך task_assignments — וזו בדיוק
-- הנקודה של סעיף 4: הגזירה מאחדת את שני המסלולים, ולכן גם השער.
insert into task_contractor_workers (task_id, contractor_worker_id, work_site) values
  ('60000000-0000-0000-0000-0000000044b2', '50000000-0000-0000-0000-000000000044',
   'field');

insert into worker_pay_settings (profile_id, hourly_rate, allow_clock_without_shift,
                                 allow_early_clock_in) values
  ('20000000-0000-0000-0000-0000000044a1', 50, false, false),
  ('20000000-0000-0000-0000-0000000044a2', 50, true,  false),
  ('20000000-0000-0000-0000-0000000044a3', 50, false, true),
  ('20000000-0000-0000-0000-0000000044b2', 50, false, false);

-- מזיזה משימה על ציר הזמן, בשעון של ישראל. שעת ההתחלה נשמרת כ-`time`
-- והתאריך נגזר ממנה, ולכן הזזה שחוצה חצות אינה מייצרת משמרת שלילית.
create or replace function t44_place(p_task uuid, p_start timestamp, p_hours numeric)
returns void language plpgsql as $$
begin
  update tasks set task_date = p_start::date,
                   onsite_start_time = p_start::time,
                   hours_count = p_hours
   where id = p_task;
end $$;

-- סירוב עסקי הוא P0001; סירוב הרשאה הוא 42501. ההבחנה חשובה כאן: עובד
-- שאין לו משמרת אינו עובד שאין לו מפתח (0073).
create or replace function t44_sqlstate(p_label text, p_sql text, p_expected text)
returns text language plpgsql as $$
begin
  execute p_sql;
  return 'FAIL  ✗ ' || p_label || ' — statement succeeded';
exception when others then
  if sqlstate = p_expected then return 'pass  ✓ ' || p_label; end if;
  return 'FAIL  ✗ ' || p_label || ' — got ' || sqlstate || ', expected ' || p_expected;
end $$;
grant execute on function t44_sqlstate(text, text, text) to authenticated;


\echo '--- 1. משמרת שנגמרה אינה פותחת את השעון ---'

-- התחילה לפני חמש שעות ונגמרה לפני שלוש. ‏`shift_at` עדיין מחזירה אותה —
-- היא הקרובה ביותר — וזה בדיוק מה שפתח את השעון עד 0168.
select t44_place('60000000-0000-0000-0000-0000000044a1',
                 (now() at time zone 'Asia/Jerusalem') - interval '5 hours', 2.0);

select t_eq('המשמרת שנגמרה עדיין נמצאת כ"הקרובה ביותר"',
  (select shift_start is not null from app.shift_at('20000000-0000-0000-0000-0000000044a1',
     now(), interval '15 minutes')), true);

select t_eq('אבל אין משמרת שהרגע הזה בתוכה',
  (select shift_start is not null from app.shift_covering('20000000-0000-0000-0000-0000000044a1',
     now(), interval '15 minutes')), false);

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000044a1', false);

select t_eq('ולכן השעון אומר למסך שאי אפשר להחתים כניסה',
  (attendance_my_status() ->> 'can_clock_in')::boolean, false);

select t_eq('והנימוק הוא שהמשמרת נגמרה',
  (attendance_my_status() #>> '{clock_in_block,reason}'), 'shift_ended');

select t_eq('וההודעה מפנה לדיווח לאישור מנהל',
  (attendance_my_status() #>> '{clock_in_block,message}') like '%לדווח משמרת לאישור מנהל', true);

select t44_sqlstate('והחתמה בפועל נדחית כסירוב עסקי',
  $$select attendance_clock_in(null, null, null, null)$$, 'P0001');

reset role;
select set_config('request.jwt.claim.sub', '', false);

select t_eq('ולא נוצרה רשומה',
  (select count(*) from attendance_entries
    where profile_id = '20000000-0000-0000-0000-0000000044a1')::int, 0);

-- ואותו דבר בדיוק כשהמשמרת היא של אתמול: היא בטווח שהגזירה סורקת, ולכן
-- ‏`shift_at` מוצאת אותה, ועד 0168 היא פתחה את השעון של היום.
select t44_place('60000000-0000-0000-0000-0000000044a1',
                 (now() at time zone 'Asia/Jerusalem') - interval '24 hours', 4.0);

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000044a1', false);
select t_expect_fail('משמרת של אתמול אינה פותחת את השעון היום',
  $$select attendance_clock_in(null, null, null, null)$$);
reset role;
select set_config('request.jwt.claim.sub', '', false);

select t_eq('וגם כאן אין רשומה',
  (select count(*) from attendance_entries
    where profile_id = '20000000-0000-0000-0000-0000000044a1')::int, 0);

-- הגדר הישן עומד: מוקדם מדי נחסם כפי שנחסם מאז 0020.
select t44_place('60000000-0000-0000-0000-0000000044a1',
                 (now() at time zone 'Asia/Jerusalem') + interval '6 hours', 4.0);

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000044a1', false);
select t_eq('ומשמרת שטרם התחילה נחסמת בנימוק שלה',
  (attendance_my_status() #>> '{clock_in_block,reason}'), 'too_early');
select t_expect_fail('וההחתמה עצמה נדחית',
  $$select attendance_clock_in(null, null, null, null)$$);
reset role;
select set_config('request.jwt.claim.sub', '', false);

-- ובלי שום משמרת בטווח — הנימוק השלישי.
update tasks set task_date = current_date + 610
 where id = '60000000-0000-0000-0000-0000000044a1';

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000044a1', false);
select t_eq('ובלי משמרת בכלל הנימוק הוא שאין שיבוץ',
  (attendance_my_status() #>> '{clock_in_block,reason}'), 'no_shift');
reset role;
select set_config('request.jwt.claim.sub', '', false);


\echo '--- 2. ובזמן המשמרת היא נפתחת ---'

select t44_place('60000000-0000-0000-0000-0000000044a1',
                 (now() at time zone 'Asia/Jerusalem') - interval '1 hour', 6.0);

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000044a1', false);

select t_eq('השעון פתוח',
  (attendance_my_status() ->> 'can_clock_in')::boolean, true);

select t_eq('ואין נימוק חסימה',
  (attendance_my_status() -> 'clock_in_block'), 'null'::jsonb);

select t_expect_ok('וההחתמה נכנסת',
  $$select attendance_clock_in(null, null, null, null)$$);

reset role;
select set_config('request.jwt.claim.sub', '', false);

select t_eq('והיא נצמדה למשמרת שהיא בתוכה',
  (select to_char(e.shift_start at time zone 'Asia/Jerusalem', 'HH24:MI')
     from attendance_entries e
    where e.profile_id = '20000000-0000-0000-0000-0000000044a1'),
  (select to_char(t.onsite_start_time, 'HH24:MI')
     from tasks t where t.id = '60000000-0000-0000-0000-0000000044a1'));

select t_eq('ואינה מסומנת כהחתמה בלי שיבוץ',
  (select 'no_shift' = any(flags) from attendance_entries
    where profile_id = '20000000-0000-0000-0000-0000000044a1'), false);

delete from attendance_entries where profile_id = '20000000-0000-0000-0000-0000000044a1';


\echo '--- 3. שתי הדלתות שנשארו פתוחות ---'

-- ‏`allow_early_clock_in` מדבר על קדימה בלבד. משמרת שנגמרה אינה משמרת
-- שמתחילים בה מוקדם, ועד 0168 ההיתר הזה (וגם היעדרו) לא נשאל עליה כלל.
select t44_place('60000000-0000-0000-0000-0000000044a3',
                 (now() at time zone 'Asia/Jerusalem') - interval '5 hours', 2.0);

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000044a3', false);
select t_expect_fail('מי שהותר לו להתחיל מוקדם אינו מחתים על משמרת שנגמרה',
  $$select attendance_clock_in(null, null, null, null)$$);
reset role;
select set_config('request.jwt.claim.sub', '', false);

-- ואותו עובד, מול משמרת שעוד תבוא: זה מה שההיתר אומר.
select t44_place('60000000-0000-0000-0000-0000000044a3',
                 (now() at time zone 'Asia/Jerusalem') + interval '6 hours', 4.0);

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000044a3', false);
select t_expect_ok('אבל כן מחתים לפני משמרת שעוד תבוא',
  $$select attendance_clock_in(null, null, null, null)$$);
reset role;
select set_config('request.jwt.claim.sub', '', false);

select t_eq('וההחתמה נצמדה למשמרת הבאה, לא לזו שנגמרה',
  (select to_char(e.shift_start at time zone 'Asia/Jerusalem', 'HH24:MI')
     from attendance_entries e
    where e.profile_id = '20000000-0000-0000-0000-0000000044a3'),
  (select to_char(t.onsite_start_time, 'HH24:MI')
     from tasks t where t.id = '60000000-0000-0000-0000-0000000044a3'));

delete from attendance_entries where profile_id = '20000000-0000-0000-0000-0000000044a3';

-- ‏`allow_clock_without_shift` הוא הפטור המפורש, והוא נשאר פטור מלא.
select t44_place('60000000-0000-0000-0000-0000000044a2',
                 (now() at time zone 'Asia/Jerusalem') - interval '5 hours', 2.0);

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000044a2', false);

select t_eq('למי שהותר לו להחתים בלי שיבוץ השעון פתוח',
  (attendance_my_status() ->> 'can_clock_in')::boolean, true);

select t_expect_ok('וההחתמה נכנסת',
  $$select attendance_clock_in(null, null, null, null)$$);

reset role;
select set_config('request.jwt.claim.sub', '', false);

select t_eq('היא מסומנת כהחתמה בלי שיבוץ',
  (select 'no_shift' = any(flags) from attendance_entries
    where profile_id = '20000000-0000-0000-0000-0000000044a2'), true);

select t_eq('ואינה שואלת שעות ממשמרת שאינה שלה',
  (select shift_start from attendance_entries
    where profile_id = '20000000-0000-0000-0000-0000000044a2'), null::timestamptz);

select t_eq('ויום העבודה שלה הוא היום, ולא של המשמרת שנגמרה',
  (select work_date from attendance_entries
    where profile_id = '20000000-0000-0000-0000-0000000044a2'),
  (now() at time zone 'Asia/Jerusalem')::date);

delete from attendance_entries where profile_id = '20000000-0000-0000-0000-0000000044a2';


\echo '--- 4. עובד קבלן נמדד באותה אמת מידה ---'

select t44_place('60000000-0000-0000-0000-0000000044b2',
                 (now() at time zone 'Asia/Jerusalem') - interval '5 hours', 2.0);

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000044b2', false);

select t_eq('גם לו השעון סגור אחרי שהמשמרת נגמרה',
  (attendance_my_status() ->> 'can_clock_in')::boolean, false);

select t44_sqlstate('וההחתמה שלו נדחית כסירוב עסקי',
  $$select attendance_clock_in(null, null, null, null)$$, 'P0001');

reset role;
select set_config('request.jwt.claim.sub', '', false);

select t_eq('ולא נוצרה לו רשומה',
  (select count(*) from attendance_entries
    where profile_id = '20000000-0000-0000-0000-0000000044b2')::int, 0);

select t44_place('60000000-0000-0000-0000-0000000044b2',
                 (now() at time zone 'Asia/Jerusalem') - interval '1 hour', 6.0);

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000044b2', false);
select t_expect_ok('ובזמן המשמרת הוא מחתים, דרך שיבוץ הקבלן',
  $$select attendance_clock_in(null, null, null, null)$$);
reset role;
select set_config('request.jwt.claim.sub', '', false);

select t_eq('וההחתמה שלו נצמדה למשמרת',
  (select shift_start is not null from attendance_entries
    where profile_id = '20000000-0000-0000-0000-0000000044b2'), true);

delete from attendance_entries where profile_id = '20000000-0000-0000-0000-0000000044b2';
