\pset tuples_only on
\pset format unaligned

-- ===========================================================================
-- 54: העובד רואה את השכר שלו בדוח הנוכחות (0198).
--
-- החבילה מקימה שלוש דמויות משלה, והמשמרות שלהן יושבות ב-`current_date + 860`
-- — מעבר לכל טווח אחר. היא רצה אחרונה כי היא משאירה אחריה רשומות נוכחות
-- שאינן מנוקות.
--
-- הטענה: ‏`can_see_pay` אמת גם למי שכל הדוח הוא שלו ומחזיק
-- ‏`attendance.view_own_pay` — ולא רק למי שרואה את הכסף של כולם. דוח שיש בו
-- שורות של אחרים נשאר בלי כסף למי שאינו מחזיק `view_pay`.
-- ===========================================================================

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000054a1', 'c54-worker@vl.test'),
  ('00000000-0000-0000-0000-0000000054a2', 'c54-nopay@vl.test'),
  ('00000000-0000-0000-0000-0000000054a3', 'c54-manager@vl.test');

insert into profiles (id, user_id, user_kind, is_admin, full_name) values
  ('20000000-0000-0000-0000-0000000054a1', '00000000-0000-0000-0000-0000000054a1',
   'staff', false, 'עובד 54'),
  ('20000000-0000-0000-0000-0000000054a2', '00000000-0000-0000-0000-0000000054a2',
   'staff', false, 'עובד בלי שכר 54'),
  ('20000000-0000-0000-0000-0000000054a3', '00000000-0000-0000-0000-0000000054a3',
   'staff', false, 'מנהל 54');

insert into worker_pay_settings (profile_id, hourly_rate) values
  ('20000000-0000-0000-0000-0000000054a1', 50),
  ('20000000-0000-0000-0000-0000000054a2', 50),
  ('20000000-0000-0000-0000-0000000054a3', 60);

insert into user_permission_grants (profile_id, permission_key, allowed) values
  ('20000000-0000-0000-0000-0000000054a1', 'attendance.view_own',     true),
  ('20000000-0000-0000-0000-0000000054a1', 'attendance.view_own_pay', true),
  ('20000000-0000-0000-0000-0000000054a2', 'attendance.view_own',     true),
  ('20000000-0000-0000-0000-0000000054a2', 'attendance.view_own_pay', false),
  ('20000000-0000-0000-0000-0000000054a3', 'attendance.view_all',     true),
  ('20000000-0000-0000-0000-0000000054a3', 'attendance.view_own_pay', true),
  ('20000000-0000-0000-0000-0000000054a3', 'attendance.view_pay',     false);

-- משמרת מאושרת של שמונה שעות לכל אחד, ביום שני — בלי יום מנוחה ובלי נוספות.
insert into attendance_entries (id, profile_id, work_date, seq, clock_in_at, clock_out_at,
                                source, status)
select v.id::uuid, v.pid::uuid, d, 1,
       (d + time '08:00') at time zone 'Asia/Jerusalem',
       (d + time '16:00') at time zone 'Asia/Jerusalem', 'manual', 'approved'
  from (select (current_date + 860 - extract(isodow from current_date + 860)::int + 1) as d) w,
       (values ('50000000-0000-0000-0000-0000000054a1', '20000000-0000-0000-0000-0000000054a1'),
               ('50000000-0000-0000-0000-0000000054a2', '20000000-0000-0000-0000-0000000054a2'),
               ('50000000-0000-0000-0000-0000000054a3', '20000000-0000-0000-0000-0000000054a3')) v(id, pid);


\echo '--- 1. העובד רואה את השכר שלו ---'

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000054a1', false);

select t_eq('הדוח של העובד אומר שהוא רואה סכומים',
  (attendance_report(current_date + 850, current_date + 870) ->> 'can_see_pay')::boolean, true);
select t_eq('והשורה שלו נושאת את השכר',
  (select (r #>> '{pay,total}')::numeric
     from jsonb_array_elements(attendance_report(current_date + 850, current_date + 870) -> 'rows') r),
  400::numeric);
select t_eq('וגם הסיכום',
  (attendance_report(current_date + 850, current_date + 870) #>> '{totals,total}')::numeric, 400::numeric);
select t_eq('חודש ריק הוא עדיין הדוח שלו',
  (attendance_report(current_date + 900, current_date + 910) ->> 'can_see_pay')::boolean, true);


\echo '--- 2. מי שנשלל ממנו view_own_pay אינו רואה ---'

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000054a2', false);

select t_eq('בלי view_own_pay אין סכומים',
  (attendance_report(current_date + 850, current_date + 870) ->> 'can_see_pay')::boolean, false);
select t_eq('והשכר מושמט מהשורה',
  (select (r -> 'pay') ? 'total'
     from jsonb_array_elements(attendance_report(current_date + 850, current_date + 870) -> 'rows') r),
  false);


\echo '--- 3. מנהל בלי view_pay: כסף רק כשהדוח כולו שלו ---'

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000054a3', false);

select t_eq('הדוח של כולם נשאר בלי סכומים',
  (attendance_report(current_date + 850, current_date + 870) ->> 'can_see_pay')::boolean, false);
select t_eq('גם כשהוא מסנן לעובד אחר',
  (attendance_report(current_date + 850, current_date + 870,
     array['20000000-0000-0000-0000-0000000054a1']::uuid[]) ->> 'can_see_pay')::boolean, false);
select t_eq('אבל כשהוא מסנן לעצמו הוא רואה את השכר שלו',
  (attendance_report(current_date + 850, current_date + 870,
     array['20000000-0000-0000-0000-0000000054a3']::uuid[]) ->> 'can_see_pay')::boolean, true);
select t_eq('והסכום שלו הוא שלו',
  (attendance_report(current_date + 850, current_date + 870,
     array['20000000-0000-0000-0000-0000000054a3']::uuid[]) #>> '{totals,total}')::numeric, 480::numeric);
select t_eq('ודוח ריק של מי שרואה אחרים אינו "הדוח שלו"',
  (attendance_report(current_date + 900, current_date + 910) ->> 'can_see_pay')::boolean, false);

reset role;
select set_config('request.jwt.claim.sub', '', false);
