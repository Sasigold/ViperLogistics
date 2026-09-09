\pset tuples_only on
\pset format unaligned

-- ===========================================================================
-- 42: העובד מבקש לתקן שעה, והמנהל מכריע (0165).
--
-- החבילה מקימה לקוח, אירוע, משימה, שני עובדים ומנהל מאשר משלה, ב-
-- `current_date + 590` — מעבר לכל טווח אחר. היא רצה אחרונה כי היא משאירה
-- אחריה רשומות נוכחות שאינן מנוקות, וכי היא מזיזה מענקים אישיים על הדמויות
-- שלה בלבד.
--
-- ארבע הטענות שהיא מחזיקה:
--
--   1. **המפתח נגזר.** מי שרשאי לדווח משמרת ידנית רשאי גם לבקש תיקון, בלי
--      שורה חדשה במסך ההרשאות.
--   2. **הבקשה אינה נוגעת בשעות.** היא יושבת לצד הרשומה; הסטטוס, השעות
--      והשכר נשארים כשהיו עד שמנהל מכריע — וזה מה שמבדיל אותה מ"להפוך את
--      הרשומה ל-pending", שדחייה בו מאבדת את היום כולו.
--   3. **אישור כותב, דחייה מוחקת.** אישור מעביר את השעות ושומר את המדידה
--      המקורית ב-`raw_*`; דחייה מוחקת את הבקשה ומשאירה את המשמרת על מכונה.
--   4. **משמרת פתוחה מקבלת סוף.** בקשה עם שעת יציאה בלבד סוגרת אותה
--      באישור, ו-`actual_hours` נגזר מאליו.
-- ===========================================================================

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000042a1', 'c42-worker@vl.test'),
  ('00000000-0000-0000-0000-0000000042a2', 'c42-other@vl.test'),
  ('00000000-0000-0000-0000-0000000042a3', 'c42-manager@vl.test');

insert into customers (id, name) values
  ('10000000-0000-0000-0000-000000000421', 'לקוח 42');

insert into profiles (id, user_id, user_kind, is_admin, full_name) values
  ('20000000-0000-0000-0000-0000000042a1', '00000000-0000-0000-0000-0000000042a1',
   'staff', false, 'עובד 42'),
  ('20000000-0000-0000-0000-0000000042a2', '00000000-0000-0000-0000-0000000042a2',
   'staff', false, 'עובד אחר 42'),
  ('20000000-0000-0000-0000-0000000042a3', '00000000-0000-0000-0000-0000000042a3',
   'staff', false, 'מנהל 42');

insert into worker_pay_settings (profile_id, hourly_rate) values
  ('20000000-0000-0000-0000-0000000042a1', 50),
  ('20000000-0000-0000-0000-0000000042a2', 50);

-- לעובד ניתן מפתח הדיווח הידני בלבד. ‏`attendance.request_correction` נגזר
-- ממנו (0165 §2), וזו הטענה הראשונה של החבילה.
insert into user_permission_grants (profile_id, permission_key, allowed) values
  ('20000000-0000-0000-0000-0000000042a1', 'attendance.view_own', true),
  ('20000000-0000-0000-0000-0000000042a1', 'attendance.submit_entry', true),
  ('20000000-0000-0000-0000-0000000042a2', 'attendance.view_own', true),
  ('20000000-0000-0000-0000-0000000042a2', 'attendance.submit_entry', true),
  ('20000000-0000-0000-0000-0000000042a3', 'attendance.view_all', true),
  ('20000000-0000-0000-0000-0000000042a3', 'attendance.approve_entry', true);

-- משמרת מאושרת שהוחתמה בשעון: 08:00–14:00 של אתמול, בשעון ישראל.
insert into attendance_entries (id, profile_id, work_date, seq, clock_in_at, clock_out_at,
                                raw_clock_in_at, raw_clock_out_at, source, status)
values ('50000000-0000-0000-0000-000000000421', '20000000-0000-0000-0000-0000000042a1',
        (now() at time zone 'Asia/Jerusalem')::date - 1, 1,
        now() - interval '30 hours', now() - interval '24 hours',
        now() - interval '30 hours', now() - interval '24 hours', 'clock', 'approved');


\echo '--- 1. המפתח נגזר מהדיווח הידני ---'

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000042a1', false);

select t_eq('לעובד יש את מפתח הדיווח הידני', app.has('attendance.submit_entry'), true);
select t_eq('ולכן גם את מפתח בקשת התיקון', app.has('attendance.request_correction'), true);
select t_eq('אבל לא את מפתח תיקון ההחתמות של מנהל', app.has('attendance.edit_entry'), false);
select t_eq('והשעון אומר לו שהוא רשאי לבקש',
  (attendance_my_status() ->> 'can_request_correction')::boolean, true);


\echo '--- 2. הבקשה אינה נוגעת בשעות ---'

select t_expect_ok('העובד מבקש להקדים את הכניסה בחצי שעה',
  $$select attendance_request_correction('50000000-0000-0000-0000-000000000421',
      now() - interval '30.5 hours', now() - interval '24 hours', 'יצאתי מהמחסן לפני שהחתמתי')$$);

reset role;
select set_config('request.jwt.claim.sub', '', false);

select t_eq('שעת הכניסה על הרשומה לא זזה',
  (select clock_in_at from attendance_entries where id = '50000000-0000-0000-0000-000000000421'),
  (select raw_clock_in_at from attendance_entries where id = '50000000-0000-0000-0000-000000000421'));

select t_eq('והסטטוס נשאר מאושר',
  (select status from attendance_entries where id = '50000000-0000-0000-0000-000000000421'), 'approved');

select t_eq('השעות בפועל לא זזו',
  (select actual_hours from attendance_entries where id = '50000000-0000-0000-0000-000000000421'), 6.00);

select t_eq('הבקשה עצמה נרשמה',
  (select req_by from attendance_entries where id = '50000000-0000-0000-0000-000000000421'),
  '20000000-0000-0000-0000-0000000042a1'::uuid);

select t_eq('ואיתה הנימוק שהעובד כתב',
  (select req_note from attendance_entries where id = '50000000-0000-0000-0000-000000000421'),
  'יצאתי מהמחסן לפני שהחתמתי');

select t_eq('המנהל קיבל התראה על הבקשה',
  (select count(*)::int from notifications
    where type = 'attendance_correction_requested'
      and recipient_id = '20000000-0000-0000-0000-0000000042a3'), 1);


\echo '--- 3. הבקשה היא של מי שהגיש אותה ---'

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000042a2', false);

select t_expect_fail('עובד אחר אינו יכול לבקש תיקון על משמרת שאינה שלו',
  $$select attendance_request_correction('50000000-0000-0000-0000-000000000421',
      now() - interval '31 hours', now() - interval '24 hours', 'לא שלי')$$);

select t_expect_fail('ואינו יכול לבטל את הבקשה של אחר',
  $$select attendance_cancel_correction('50000000-0000-0000-0000-000000000421')$$);

select t_expect_fail('וגם לא להכריע בה — אין לו מפתח אישור',
  $$select attendance_review_correction('50000000-0000-0000-0000-000000000421', true, null)$$);

reset role;
select set_config('request.jwt.claim.sub', '', false);

select t_eq('הבקשה שרדה את שלושת הניסיונות',
  (select req_at is not null from attendance_entries
    where id = '50000000-0000-0000-0000-000000000421'), true);


\echo '--- 4. המנהל רואה אותה בדוח ---'

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000042a3', false);

select t_eq('שורת הדוח נושאת את הבקשה',
  (select (r -> 'correction' ->> 'note')
     from jsonb_array_elements(
       attendance_report((now() at time zone 'Asia/Jerusalem')::date - 2,
                         (now() at time zone 'Asia/Jerusalem')::date) -> 'rows') r
    where r ->> 'id' = '50000000-0000-0000-0000-000000000421'),
  'יצאתי מהמחסן לפני שהחתמתי');

select t_expect_fail('דחייה בלי נימוק נחסמת',
  $$select attendance_review_correction('50000000-0000-0000-0000-000000000421', false, null)$$);

select t_expect_ok('ודחייה עם נימוק מתקבלת',
  $$select attendance_review_correction('50000000-0000-0000-0000-000000000421', false,
      'השעון מראה 08:00, ואין אישור על יציאה מוקדמת מהמחסן')$$);

reset role;
select set_config('request.jwt.claim.sub', '', false);

select t_eq('הבקשה נמחקה',
  (select req_at from attendance_entries where id = '50000000-0000-0000-0000-000000000421'),
  null::timestamptz);

select t_eq('והשעות נשארו כפי שהיו — הדחייה אינה מאבדת את היום',
  (select actual_hours from attendance_entries where id = '50000000-0000-0000-0000-000000000421'), 6.00);

select t_eq('הרשומה עדיין מאושרת',
  (select status from attendance_entries where id = '50000000-0000-0000-0000-000000000421'), 'approved');

select t_eq('והעובד קיבל את הנימוק',
  (select count(*)::int from notifications
    where type = 'attendance_rejected'
      and recipient_id = '20000000-0000-0000-0000-0000000042a1'), 1);


\echo '--- 5. אישור כותב את השעות ושומר את המדידה ---'

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000042a1', false);
select t_expect_ok('העובד מבקש שוב',
  $$select attendance_request_correction('50000000-0000-0000-0000-000000000421',
      now() - interval '30.5 hours', now() - interval '24 hours', 'הפעם עם אישור הרכז')$$);
reset role;

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000042a3', false);
select t_expect_ok('והמנהל מאשר',
  $$select attendance_review_correction('50000000-0000-0000-0000-000000000421', true, null)$$);
reset role;
select set_config('request.jwt.claim.sub', '', false);

select t_eq('השעות בפועל גדלו בחצי שעה',
  (select actual_hours from attendance_entries where id = '50000000-0000-0000-0000-000000000421'), 6.50);

select t_eq('והמדידה המקורית של השעון נשמרה',
  (select round(extract(epoch from (raw_clock_out_at - raw_clock_in_at)) / 3600.0, 2)
     from attendance_entries where id = '50000000-0000-0000-0000-000000000421'), 6.00);

select t_eq('הרשומה מסומנת כמתוקנת',
  (select 'edited' = any(flags) from attendance_entries
    where id = '50000000-0000-0000-0000-000000000421'), true);

select t_eq('ומי שתיקן הוא המנהל שאישר',
  (select edited_by from attendance_entries where id = '50000000-0000-0000-0000-000000000421'),
  '20000000-0000-0000-0000-0000000042a3'::uuid);

select t_eq('הבקשה נמחקה גם באישור',
  (select req_at from attendance_entries where id = '50000000-0000-0000-0000-000000000421'),
  null::timestamptz);


\echo '--- 6. משמרת פתוחה מקבלת שעת סיום ---'

insert into attendance_entries (id, profile_id, work_date, seq, clock_in_at, clock_out_at,
                                raw_clock_in_at, source, status)
values ('50000000-0000-0000-0000-000000000422', '20000000-0000-0000-0000-0000000042a2',
        (now() at time zone 'Asia/Jerusalem')::date - 1, 1,
        now() - interval '30 hours', null, now() - interval '30 hours', 'clock', 'approved');

select t_eq('היא נפתחה בלי שעות בפועל',
  (select actual_hours from attendance_entries where id = '50000000-0000-0000-0000-000000000422'),
  null::numeric);

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000042a2', false);
select t_expect_ok('העובד מבקש להשלים שעת סיום',
  $$select attendance_request_correction('50000000-0000-0000-0000-000000000422',
      now() - interval '30 hours', now() - interval '25 hours', 'שכחתי להחתים יציאה')$$);
reset role;

select t_eq('והמשמרת עדיין פתוחה — הבקשה לבדה אינה סוגרת',
  (select clock_out_at from attendance_entries where id = '50000000-0000-0000-0000-000000000422'),
  null::timestamptz);

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000042a3', false);
select t_expect_ok('המנהל מאשר',
  $$select attendance_review_correction('50000000-0000-0000-0000-000000000422', true, null)$$);
reset role;
select set_config('request.jwt.claim.sub', '', false);

select t_eq('המשמרת נסגרה על חמש שעות',
  (select actual_hours from attendance_entries where id = '50000000-0000-0000-0000-000000000422'), 5.00);

select t_eq('ואין לה מדידת יציאה מקורית — השעון מעולם לא מדד אותה',
  (select raw_clock_out_at from attendance_entries where id = '50000000-0000-0000-0000-000000000422'),
  null::timestamptz);


\echo '--- 7. הגבולות ---'

-- שתי עוזרות קריאה. הבדיקה "בקשה שאינה משנה דבר" חייבת לשלוח בדיוק את השעות
-- ששמורות על הרשומה, ו-`now()` בהצהרה חדשה כבר אינו אותו `now()` שנכתב בה.
create or replace function t42_ci(p_id uuid) returns timestamptz
language sql stable security definer set search_path = public as $$
  select clock_in_at from attendance_entries where id = p_id $$;
create or replace function t42_co(p_id uuid) returns timestamptz
language sql stable security definer set search_path = public as $$
  select clock_out_at from attendance_entries where id = p_id $$;

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000042a1', false);

select t_expect_fail('שעת יציאה לפני הכניסה נחסמת',
  $$select attendance_request_correction('50000000-0000-0000-0000-000000000421',
      now() - interval '24 hours', now() - interval '30 hours', 'הפוך')$$);

select t_expect_fail('שעה שטרם הגיעה נחסמת',
  $$select attendance_request_correction('50000000-0000-0000-0000-000000000421',
      now() - interval '30 hours', now() + interval '3 hours', 'עתידי')$$);

select t_expect_fail('בקשה שאינה משנה דבר נחסמת',
  $$select attendance_request_correction('50000000-0000-0000-0000-000000000421',
      t42_ci('50000000-0000-0000-0000-000000000421'),
      t42_co('50000000-0000-0000-0000-000000000421'), 'אותו דבר')$$);

select t_expect_fail('ובקשה על משמרת שאינה קיימת נחסמת',
  $$select attendance_request_correction('50000000-0000-0000-0000-0000000004ff',
      now() - interval '30 hours', now() - interval '24 hours', 'אין כזו')$$);

select t_expect_ok('בקשה תקינה נכתבת',
  $$select attendance_request_correction('50000000-0000-0000-0000-000000000421',
      now() - interval '31 hours', now() - interval '24 hours', 'עוד חצי שעה')$$);

select t_expect_ok('והעובד מושך אותה בחזרה',
  $$select attendance_cancel_correction('50000000-0000-0000-0000-000000000421')$$);

select t_expect_fail('משיכה שנייה נחסמת — אין מה למשוך',
  $$select attendance_cancel_correction('50000000-0000-0000-0000-000000000421')$$);

reset role;
select set_config('request.jwt.claim.sub', '', false);

select t_eq('השעות נשארו של האישור מסעיף 5',
  (select actual_hours from attendance_entries where id = '50000000-0000-0000-0000-000000000421'), 6.50);

-- ‏0165: משמרת ישנה מחלון הדיווח (14 יום כברירת מחדל) אינה ניתנת לבקשה.
insert into attendance_entries (id, profile_id, work_date, seq, clock_in_at, clock_out_at,
                                source, status)
values ('50000000-0000-0000-0000-000000000423', '20000000-0000-0000-0000-0000000042a1',
        (now() at time zone 'Asia/Jerusalem')::date - 40, 2,
        now() - interval '40 days', now() - interval '40 days' + interval '6 hours',
        'clock', 'approved');

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000042a1', false);
select t_expect_fail('משמרת מלפני ארבעים יום מחוץ לחלון',
  $$select attendance_request_correction('50000000-0000-0000-0000-000000000423',
      now() - interval '40 days' - interval '1 hour',
      now() - interval '40 days' + interval '6 hours', 'ישן מדי')$$);

select t_expect_fail('ובקשה שחופפת לרשומה אחרת שלי נחסמת',
  $$select attendance_request_correction('50000000-0000-0000-0000-000000000421',
      now() - interval '40 days',
      now() - interval '40 days' + interval '3 hours', 'חופף')$$);

reset role;
select set_config('request.jwt.claim.sub', '', false);
