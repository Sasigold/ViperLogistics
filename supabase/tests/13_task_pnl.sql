\pset tuples_only on
\pset format unaligned

-- ===========================================================================
-- 13: רווחיות פר-משימה (0070).
--
-- החבילה מקימה לקוח, קבלן, אירוע, משימות, עובדים ומשמרות משל עצמה ואינה
-- נשענת על אף חבילה קודמת — 02 הופכת את f2 לאדמין, ו-06/09 מזיזות מפתחות על
-- f1/f3. היא רצה אחרונה כי היא סופרת שורות בטווח שלה בלבד.
--
-- **התאריכים מעוגנים ליום שני בכוונה.** `attendance.overtime` מגדיר
-- `rest_day.dow = [6]`, ומשמרת שהייתה נופלת בשבת הייתה מתומחרת ב-150%
-- וכל המספרים כאן היו זזים. `date_trunc('week', ...)` מחזיר יום שני,
-- והמשמרות יושבות עליו ועל שלושת הימים שאחריו — כולם ימי חול.
--
-- אריתמטיקת הבדיקה, כדי שהמספרים למטה לא ייראו שרירותיים. ארבע משמרות של
-- ארבע שעות (מתחת ל-8 השעות של המדרגה הראשונה, ולכן שכר ישר):
--
--   E1  w1 (50 ₪)  200 ₪  →  T1(6ש׳) + T2(2ש׳)   →  150 / 50
--   E2  w2 (40 ₪)  160 ₪  →  T3(0ש׳) + T4(0ש׳)   →   80 / 80   (חלוקה שווה)
--   E3  w1 (50 ₪)  200 ₪  →  T5(3ש׳,מחוקה) + T6(1ש׳) → 150 / 50
--   E4  w1 (50 ₪)  200 ₪  →  בלי משימות כלל       →  לא משויך
--   E5  w3 (ללא תעריף)    →  T8                   →  total = null
--
--   סך השכר       760 = 200+160+200+200   (E5 אינה נספרת — אין לה תעריף)
--   משויך         410 = 150+50+80+80+50
--   לא משויך      350 = 150 (המשימה המחוקה) + 200 (E4)
-- ===========================================================================

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000013a1', 'pnl.full@vl.test'),
  ('00000000-0000-0000-0000-0000000013a2', 'pnl.noworkers@vl.test'),
  ('00000000-0000-0000-0000-0000000013a3', 'pnl.nocontractorprice@vl.test'),
  ('00000000-0000-0000-0000-0000000013a4', 'pnl.hoursonly@vl.test'),
  ('00000000-0000-0000-0000-0000000013a5', 'pnl.noreports@vl.test'),
  ('00000000-0000-0000-0000-0000000013a6', 'pnl.scoped@vl.test'),
  ('00000000-0000-0000-0000-0000000013a7', 'pnl.nocustomers@vl.test'),
  ('00000000-0000-0000-0000-0000000013b1', 'pnl.w1@vl.test'),
  ('00000000-0000-0000-0000-0000000013b2', 'pnl.w2@vl.test'),
  ('00000000-0000-0000-0000-0000000013b3', 'pnl.w3@vl.test'),
  ('00000000-0000-0000-0000-0000000013a8', 'pnl.admin@vl.test');

insert into customers (id, name) values
  ('10000000-0000-0000-0000-000000000013', 'לקוח רווחיות משימות');

insert into contractors (id, name) values
  ('11000000-0000-0000-0000-000000000013', 'קבלן רווחיות משימות');

insert into profiles (id, user_id, user_kind, is_admin, full_name) values
  ('20000000-0000-0000-0000-0000000013a1', '00000000-0000-0000-0000-0000000013a1',
   'staff', false, 'קורא רווחיות מלא'),
  ('20000000-0000-0000-0000-0000000013a2', '00000000-0000-0000-0000-0000000013a2',
   'staff', false, 'צרור בלי כל העובדים'),
  ('20000000-0000-0000-0000-0000000013a3', '00000000-0000-0000-0000-0000000013a3',
   'staff', false, 'צרור בלי תמחור קבלנים'),
  ('20000000-0000-0000-0000-0000000013a4', '00000000-0000-0000-0000-0000000013a4',
   'staff', false, 'רואה שעות בלי רווח'),
  ('20000000-0000-0000-0000-0000000013a5', '00000000-0000-0000-0000-0000000013a5',
   'staff', false, 'בלי מסך דוחות'),
  ('20000000-0000-0000-0000-0000000013a6', '00000000-0000-0000-0000-0000000013a6',
   'staff', false, 'צרור עם היקף מצומצם'),
  ('20000000-0000-0000-0000-0000000013a7', '00000000-0000-0000-0000-0000000013a7',
   'staff', false, 'צרור בלי לקוחות'),
  ('20000000-0000-0000-0000-0000000013b1', '00000000-0000-0000-0000-0000000013b1',
   'staff', false, 'עובד עם תעריף 50'),
  ('20000000-0000-0000-0000-0000000013b2', '00000000-0000-0000-0000-0000000013b2',
   'staff', false, 'עובד עם תעריף 40'),
  ('20000000-0000-0000-0000-0000000013b3', '00000000-0000-0000-0000-0000000013b3',
   'staff', false, 'עובד ללא תעריף'),
  -- מנהל מערכת. אין לו מענקים בכלל — `app.has` מחזיר לו true על כל מפתח.
  ('20000000-0000-0000-0000-0000000013a8', '00000000-0000-0000-0000-0000000013a8',
   'staff', true, 'מנהל מערכת עם היקף מיותם');

-- w3 בכוונה בלי שורת worker_pay_settings — זו הדמות של "משמרת ללא תעריף"
insert into worker_pay_settings (profile_id, hourly_rate) values
  ('20000000-0000-0000-0000-0000000013b1', 50),
  ('20000000-0000-0000-0000-0000000013b2', 40);

insert into user_permission_grants (profile_id, permission_key, allowed) values
  -- a1: הצרור המלא
  ('20000000-0000-0000-0000-0000000013a1', 'reports.view',              true),
  ('20000000-0000-0000-0000-0000000013a1', 'dashboard.margin',          true),
  ('20000000-0000-0000-0000-0000000013a1', 'dashboard.payroll',         true),
  ('20000000-0000-0000-0000-0000000013a1', 'dashboard.contractor_cost', true),
  ('20000000-0000-0000-0000-0000000013a1', 'pricing.revenue',           true),
  ('20000000-0000-0000-0000-0000000013a1', 'dashboard.all_workers',     true),
  ('20000000-0000-0000-0000-0000000013a1', 'customers.view',            true),
  ('20000000-0000-0000-0000-0000000013a1', 'contractors.view',          true),
  ('20000000-0000-0000-0000-0000000013a1', 'contractors.view_pricing',  true),
  -- a2: הכול חוץ מ-dashboard.all_workers
  ('20000000-0000-0000-0000-0000000013a2', 'reports.view',              true),
  ('20000000-0000-0000-0000-0000000013a2', 'dashboard.margin',          true),
  ('20000000-0000-0000-0000-0000000013a2', 'dashboard.payroll',         true),
  ('20000000-0000-0000-0000-0000000013a2', 'dashboard.contractor_cost', true),
  ('20000000-0000-0000-0000-0000000013a2', 'pricing.revenue',           true),
  ('20000000-0000-0000-0000-0000000013a2', 'dashboard.all_workers',     false),
  -- a3: הצרור המלא, אבל בלי המפתח שפותח את `task_contractor_terms`
  ('20000000-0000-0000-0000-0000000013a3', 'reports.view',              true),
  ('20000000-0000-0000-0000-0000000013a3', 'dashboard.margin',          true),
  ('20000000-0000-0000-0000-0000000013a3', 'dashboard.payroll',         true),
  ('20000000-0000-0000-0000-0000000013a3', 'dashboard.contractor_cost', true),
  ('20000000-0000-0000-0000-0000000013a3', 'pricing.revenue',           true),
  ('20000000-0000-0000-0000-0000000013a3', 'dashboard.all_workers',     true),
  ('20000000-0000-0000-0000-0000000013a3', 'customers.view',            true),
  ('20000000-0000-0000-0000-0000000013a3', 'contractors.view',          true),
  ('20000000-0000-0000-0000-0000000013a3', 'contractors.view_pricing',  false),
  -- a4: שעות בלי כסף
  ('20000000-0000-0000-0000-0000000013a4', 'reports.view',              true),
  ('20000000-0000-0000-0000-0000000013a4', 'attendance.view_all',       true),
  ('20000000-0000-0000-0000-0000000013a4', 'dashboard.margin',          false),
  -- a5: בלי הדלת עצמה
  ('20000000-0000-0000-0000-0000000013a5', 'reports.view',              false),
  ('20000000-0000-0000-0000-0000000013a5', 'dashboard.margin',          true),
  ('20000000-0000-0000-0000-0000000013a5', 'dashboard.payroll',         true),
  ('20000000-0000-0000-0000-0000000013a5', 'dashboard.contractor_cost', true),
  ('20000000-0000-0000-0000-0000000013a5', 'pricing.revenue',           true),
  ('20000000-0000-0000-0000-0000000013a5', 'dashboard.all_workers',     true),
  -- a6: הצרור המלא, אבל היקף נתונים מצומצם על משימות
  ('20000000-0000-0000-0000-0000000013a6', 'reports.view',              true),
  ('20000000-0000-0000-0000-0000000013a6', 'dashboard.margin',          true),
  ('20000000-0000-0000-0000-0000000013a6', 'dashboard.payroll',         true),
  ('20000000-0000-0000-0000-0000000013a6', 'dashboard.contractor_cost', true),
  ('20000000-0000-0000-0000-0000000013a6', 'pricing.revenue',           true),
  ('20000000-0000-0000-0000-0000000013a6', 'dashboard.all_workers',     true),
  ('20000000-0000-0000-0000-0000000013a6', 'customers.view',            true),
  -- a7: הצרור המלא, בלי המפתח ללקוחות. דמות נפרדת ולא כיבוי-והדלקה של a1
  -- באמצע החבילה: `app.guard_permission_grant` דורש `users.manage_permissions`
  -- מהזהות הפעילה, ולכן שינוי מענק תוך כדי ריצה הוא נתיב שבור.
  ('20000000-0000-0000-0000-0000000013a7', 'reports.view',              true),
  ('20000000-0000-0000-0000-0000000013a7', 'dashboard.margin',          true),
  ('20000000-0000-0000-0000-0000000013a7', 'dashboard.payroll',         true),
  ('20000000-0000-0000-0000-0000000013a7', 'dashboard.contractor_cost', true),
  ('20000000-0000-0000-0000-0000000013a7', 'pricing.revenue',           true),
  ('20000000-0000-0000-0000-0000000013a7', 'dashboard.all_workers',     true),
  ('20000000-0000-0000-0000-0000000013a7', 'contractors.view',          true),
  ('20000000-0000-0000-0000-0000000013a7', 'customers.view',            false);

insert into permission_scopes (profile_id, resource, scope_type, scope_values) values
  ('20000000-0000-0000-0000-0000000013a6', 'tasks', 'customers',
   array['10000000-0000-0000-0000-000000000013']::uuid[]),
  -- a8 הוא מנהל מערכת שיש עליו בדיוק אותה שורת היקף. עד 0085 היא הספיקה כדי
  -- לסגור בפניו את הדוח, אף שכל פוליסת RLS במערכת מדלגת עליה בשבילו.
  ('20000000-0000-0000-0000-0000000013a8', 'tasks', 'customers',
   array['10000000-0000-0000-0000-000000000013']::uuid[]);

-- התאריכים, מעוגנים ליום שני. dfrom/dto מקיפים את כל ארבעת הימים ואינם
-- נוגעים במה שחבילות אחרות זרעו סביב היום.
create temp table t13 as
select date_trunc('week', current_date + 240)::date        as d0,
       date_trunc('week', current_date + 240)::date + 1    as d1,
       date_trunc('week', current_date + 240)::date + 2    as d2,
       date_trunc('week', current_date + 240)::date - 3    as dfrom,
       date_trunc('week', current_date + 240)::date + 10   as dto;
grant select on t13 to authenticated;

insert into events (id, customer_id, event_date, location_lat, location_lng)
select '30000000-0000-0000-0000-000000000013',
       '10000000-0000-0000-0000-000000000013', d0, 32.0853, 34.7818 from t13;

-- 0009 יוצר אוטומטית משימות הקמה ופירוק לכל אירוע חדש. הן אינן חלק
-- מהאריתמטיקה כאן, והשארתן הייתה קושרת את הספירות שלמטה להגדרת
-- `task_types.auto_create_on_event` — שדה שמישהו ישנה בהגדרות יום אחד.
delete from tasks where event_id = '30000000-0000-0000-0000-000000000013';

-- שמונה משימות. T5 תימחק רכות בהמשך, אחרי שהמשמרת כבר נוקבת בה.
insert into tasks (id, event_id, customer_id, task_type_id, task_date, status_id,
                   title, hours_count, worker_count)
select v.id, '30000000-0000-0000-0000-000000000013',
       '10000000-0000-0000-0000-000000000013',
       (select id from task_types where code = 'setup' limit 1),
       (select d0 from t13),
       (select id from statuses where entity = 'task' and code = 'assigned'
                                  and deleted_at is null),
       v.title, v.hours, v.workers
from (values
  ('31000000-0000-0000-0000-000000130001'::uuid, 'T1 שש שעות',       6::numeric, 2, null),
  ('31000000-0000-0000-0000-000000130002'::uuid, 'T2 שעתיים',        2::numeric, 1, null),
  ('31000000-0000-0000-0000-000000130003'::uuid, 'T3 בלי שעות',      0::numeric, 1, null),
  ('31000000-0000-0000-0000-000000130004'::uuid, 'T4 בלי שעות',      0::numeric, 1, null),
  ('31000000-0000-0000-0000-000000130005'::uuid, 'T5 תימחק',         3::numeric, 1, null),
  ('31000000-0000-0000-0000-000000130006'::uuid, 'T6 שעה',           1::numeric, 1, null),
  ('31000000-0000-0000-0000-000000130007'::uuid, 'T7 קבלן בלי נוכחות', 4::numeric, 2,
   '11000000-0000-0000-0000-000000000013'),
  ('31000000-0000-0000-0000-000000130008'::uuid, 'T8 רק עובד ללא תעריף', 2::numeric, 1, null)
) v(id, title, hours, workers, contractor);

-- ‏0096: ההאצלה היא שורה ב-task_contractor_terms, ו-`tasks.contractor_id` הוא
-- שיקוף שהטריגר על ה-terms מתחזק. הזריעה כותבת את האמת, לא את השיקוף.
insert into task_contractor_terms (task_id, contractor_id, price)
values ('31000000-0000-0000-0000-000000130007', '11000000-0000-0000-0000-000000000013', 0);

insert into task_pricing (task_id, price, is_manual) values
  ('31000000-0000-0000-0000-000000130001', 1000, true),
  ('31000000-0000-0000-0000-000000130002',  400, true),
  ('31000000-0000-0000-0000-000000130003',  300, true),
  ('31000000-0000-0000-0000-000000130004',  300, true),
  ('31000000-0000-0000-0000-000000130005',  500, true),
  ('31000000-0000-0000-0000-000000130006',  200, true),
  ('31000000-0000-0000-0000-000000130007', 5000, true),
  ('31000000-0000-0000-0000-000000130008',  600, true);

-- המחיר על שורת התנאים שנזרעה למעלה.
update task_contractor_terms set price = 2000
 where task_id = '31000000-0000-0000-0000-000000130007';

-- ארבע משמרות של ארבע שעות, בימי חול
insert into attendance_entries (id, profile_id, work_date, seq, task_ids,
                                clock_in_at, clock_out_at, source)
select v.id, v.profile, v.d, 1, v.tasks,
       v.d + time '08:00', v.d + time '12:00', 'manual'
from (values
  ('70000000-0000-0000-0000-000000130001'::uuid,
   '20000000-0000-0000-0000-0000000013b1'::uuid, (select d0 from t13),
   array['31000000-0000-0000-0000-000000130001',
         '31000000-0000-0000-0000-000000130002']::uuid[]),
  ('70000000-0000-0000-0000-000000130002'::uuid,
   '20000000-0000-0000-0000-0000000013b2'::uuid, (select d1 from t13),
   array['31000000-0000-0000-0000-000000130003',
         '31000000-0000-0000-0000-000000130004']::uuid[]),
  ('70000000-0000-0000-0000-000000130003'::uuid,
   '20000000-0000-0000-0000-0000000013b1'::uuid, (select d1 from t13),
   array['31000000-0000-0000-0000-000000130005',
         '31000000-0000-0000-0000-000000130006']::uuid[]),
  ('70000000-0000-0000-0000-000000130004'::uuid,
   '20000000-0000-0000-0000-0000000013b1'::uuid, (select d2 from t13),
   '{}'::uuid[]),
  ('70000000-0000-0000-0000-000000130005'::uuid,
   '20000000-0000-0000-0000-0000000013b3'::uuid, (select d2 from t13),
   array['31000000-0000-0000-0000-000000130008']::uuid[])
) v(id, profile, d, tasks);

-- המחיקה הרכה באה **אחרי** ההחתמה, כמו במציאות: המשמרת כבר נקבה במשימה.
update tasks set deleted_at = now()
 where id = '31000000-0000-0000-0000-000000130005';

-- שורה מהתשובה לפי מזהה משימה, כדי שהטענות ייקראו כמו משפטים
create or replace function t13row(p_task text) returns jsonb language sql stable as $$
  select r from jsonb_array_elements(
    (task_pnl((select dfrom from t13), (select dto from t13), null, null, 500)) -> 'rows') r
   where r ->> 'task_id' = p_task
$$;
grant execute on function t13row(text) to authenticated;

create or replace function t13all() returns jsonb language sql stable as $$
  select task_pnl((select dfrom from t13), (select dto from t13), null, null, 500)
$$;
grant execute on function t13all() to authenticated;

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000013a1', false);

\echo '--- ההקצאה: פיצול משמרת בין משימותיה ---'

select t_eq('T1 מקבל 6/8 משכר המשמרת',
  (t13row('31000000-0000-0000-0000-000000130001') ->> 'payroll')::numeric, 150::numeric);
select t_eq('T2 מקבל 2/8 משכר המשמרת',
  (t13row('31000000-0000-0000-0000-000000130002') ->> 'payroll')::numeric, 50::numeric);
select t_eq('ושתי השורות יחד הן שכר המשמרת',
  (t13row('31000000-0000-0000-0000-000000130001') ->> 'payroll')::numeric
  + (t13row('31000000-0000-0000-0000-000000130002') ->> 'payroll')::numeric, 200::numeric);

select t_eq('T1 סופג גם את השעות לפי אותו משקל',
  (t13row('31000000-0000-0000-0000-000000130001') ->> 'actual_hours')::numeric, 3::numeric);
select t_eq('T2 את השארית',
  (t13row('31000000-0000-0000-0000-000000130002') ->> 'actual_hours')::numeric, 1::numeric);

\echo '--- שתי משימות בלי שעות: חלוקה שווה ---'

select t_eq('T3 מקבל מחצית',
  (t13row('31000000-0000-0000-0000-000000130003') ->> 'payroll')::numeric, 80::numeric);
select t_eq('T4 מקבל מחצית',
  (t13row('31000000-0000-0000-0000-000000130004') ->> 'payroll')::numeric, 80::numeric);

\echo '--- משימה מחוקה צורכת את חלקה ---'

select t_eq('המשימה המחוקה אינה מופיעה בשורות',
  t13row('31000000-0000-0000-0000-000000130005') is null, true);
-- זו הטענה שמגינה על ההחלטה של 0041: אילו המכנה היה מצטמצם, T6 היה מקבל 200
select t_eq('T6 מקבל רק את הרבע שלו, ולא את כל המשמרת',
  (t13row('31000000-0000-0000-0000-000000130006') ->> 'payroll')::numeric, 50::numeric);
select t_eq('והשארית של המחוקה יושבת ב״לא משויך״',
  (t13all() #>> '{meta,unallocated}')::numeric, 350::numeric);

\echo '--- משמרת בלי משימות אינה מתפזרת ---'

select t_eq('משויך = 410',
  (t13all() #>> '{meta,allocated}')::numeric, 410::numeric);
-- 410 + 350 = 760, וזה בדיוק סך השכר המאושר בטווח
select t_eq('משויך + לא משויך = סך השכר',
  (t13all() #>> '{meta,allocated}')::numeric + (t13all() #>> '{meta,unallocated}')::numeric,
  760::numeric);

\echo '--- משמרת ללא תעריף: לא רווח 100% ---'

select t_eq('T8 מדווח שכר 0',
  (t13row('31000000-0000-0000-0000-000000130008') ->> 'payroll')::numeric, 0::numeric);
-- בלי המונה הזה השורה הייתה אומרת "רווח 600, שוליים 100%" בביטחון מלא
select t_eq('אבל מצהיר שמשמרת אחת אינה נספרת',
  (t13row('31000000-0000-0000-0000-000000130008') ->> 'unrated_shifts')::int, 1);
select t_eq('והמשמרת כן נספרת כמשמרת',
  (t13row('31000000-0000-0000-0000-000000130008') ->> 'shifts')::int, 1);
select t_eq('והמונה עולה גם ל-meta',
  (t13all() #>> '{meta,unrated_shifts}')::int, 1);

\echo '--- משימה בלי נוכחות כלל ---'

select t_eq('T7 מסומן ככזה שאין עליו נוכחות',
  (t13row('31000000-0000-0000-0000-000000130007') ->> 'no_attendance')::boolean, true);
select t_eq('ומונה ה-meta סופר אותו',
  (t13all() #>> '{meta,tasks_no_attendance}')::int, 1);

\echo '--- עלות מעביד: אותה הגדרה של 0069 ---'

select t_eq('האחוז מדווח בתשובה',
  (t13all() #>> '{meta,employer_pct}')::numeric, 30::numeric);
select t_eq('T1: שכר 150 → 195 עם נטל המעביד',
  (t13row('31000000-0000-0000-0000-000000130001') ->> 'payroll_with_employer')::numeric,
  195::numeric);
select t_eq('T1: עלות כוללת = קבלן + שכר עם נטל',
  (t13row('31000000-0000-0000-0000-000000130001') ->> 'cost_total')::numeric, 195::numeric);
select t_eq('T1: רווח = 1000 − 195',
  (t13row('31000000-0000-0000-0000-000000130001') ->> 'gross')::numeric, 805::numeric);
select t_eq('T1: שיעור רווח',
  (t13row('31000000-0000-0000-0000-000000130001') ->> 'pct')::numeric, 80.5::numeric);

\echo '--- מתוכנן מול בפועל: עובדה, לא מחיר נגדי ---'

select t_eq('T1 תוכנן 2 עובדים × 6 שעות',
  (t13row('31000000-0000-0000-0000-000000130001') ->> 'planned_worker_hours')::numeric,
  12::numeric);
select t_eq('בפועל הוחתמו 3 שעות',
  (t13row('31000000-0000-0000-0000-000000130001') ->> 'actual_hours')::numeric, 3::numeric);
select t_eq('והפער מדווח',
  (t13row('31000000-0000-0000-0000-000000130001') ->> 'hours_delta')::numeric, -9::numeric);
select t_eq('עובד אחד הוחתם בפועל',
  (t13row('31000000-0000-0000-0000-000000130001') ->> 'actual_workers')::int, 1);
-- מה שלא קרה: ההכנסה לא זזה בעקבות הביצוע
select t_eq('ההכנסה נשארה המחיר שהוזמן',
  (t13row('31000000-0000-0000-0000-000000130001') ->> 'revenue')::numeric, 1000::numeric);
select t_eq('ו-meta מצהיר על שני הבסיסים',
  (t13all() #>> '{meta,revenue_basis}') || '/' || (t13all() #>> '{meta,cost_basis}'),
  'quoted_plan/actual_clocked');

\echo '--- הסיכום מתיישב עם השורות ---'

select t_eq('שבע משימות חיות בטווח',
  (t13all() #>> '{summary,tasks}')::int, 7);
select t_eq('סך ההכנסות',
  (t13all() #>> '{summary,revenue}')::numeric, 7800::numeric);
select t_eq('סך השכר המשויך שווה ל-allocated',
  (t13all() #>> '{summary,payroll}')::numeric,
  (t13all() #>> '{meta,allocated}')::numeric);
select t_eq('סך עלות הקבלנים',
  (t13all() #>> '{summary,contractor}')::numeric, 2000::numeric);
select t_eq('סך הרווח',
  (t13all() #>> '{summary,gross}')::numeric, 5267::numeric);
select t_eq('וסכום הרווח של השורות שווה לו',
  (select round(sum((r ->> 'gross')::numeric), 2)
     from jsonb_array_elements(t13all() -> 'rows') r), 5267::numeric);

\echo '--- הרשאות ---'

-- זו המלכודת היקרה: `task_contractor_terms` נקראת רק עם contractors.view_pricing,
-- ושאילתת invoker הייתה מחזירה 0 ומנפחת את הרווח בגובה כל הקבלנות.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000013a3', false);
select t_eq('בלי contractors.view_pricing הטבלה עצמה ריקה',
  (select count(*)::int from task_contractor_terms
    where task_id = '31000000-0000-0000-0000-000000130007'), 0);
select t_eq('ובכל זאת עלות הקבלן בדוח היא המספר האמיתי',
  (t13row('31000000-0000-0000-0000-000000130007') ->> 'contractor_cost')::numeric,
  2000::numeric);
select t_eq('ולכן הרווח אינו מנופח',
  (t13row('31000000-0000-0000-0000-000000130007') ->> 'gross')::numeric, 3000::numeric);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000013a2', false);
select t_eq('צרור מלא בלי dashboard.all_workers — נדחה ברכות',
  (t13all() -> 'rows') = 'null'::jsonb, true);
select t_eq('ומצהיר על כך',
  (t13all() #>> '{meta,denied}')::boolean, true);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000013a4', false);
select t_eq('רואה שעות בלי צרור הרווח — נדחה ברכות ולא בשגיאה',
  (t13all() -> 'rows') = 'null'::jsonb, true);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000013a6', false);
select t_eq('היקף נתונים מצומצם — נדחה',
  (t13all() -> 'rows') = 'null'::jsonb, true);

/*
 * ‏0085 §3: למנהל מערכת אין היקף נתונים.
 *
 * a8 נושא בדיוק את שורת ההיקף של a6, ובכל זאת רואה את הדוח במלואו — כי
 * ‏`app.scope_rows` שותקת בשבילו, בדיוק כפי ש-`app.has` מחזיר לו true. זו
 * הייתה הסיבה ל"למה כמנהל מערכת אין לי הרשאה לרווחיות לפי משימה": די היה
 * בתפקיד ישן שנושא היקף (worker/driver/team_lead נושאים 'own' על tasks מאז
 * 0011) כדי לסגור בפניו את כל שערי הכספים.
 */
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000013a8', false);
select t_eq('מנהל מערכת עם שורת היקף — רואה בכל זאת',
  (t13all() -> 'rows') = 'null'::jsonb, false);
select t_eq('ואותן שבע שורות שרואה הקורא המלא',
  jsonb_array_length(t13all() -> 'rows'), 7);
select t_eq('וגם `app.scope_rows` עצמה שותקת בשבילו',
  (select count(*)::int from app.scope_rows('tasks')), 0);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000013a5', false);
select t_expect_fail('בלי reports.view — דלת סגורה, לא null',
  $$select t13all()$$);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000013a1', false);
select t_expect_fail('טווח הפוך נדחה',
  $$select task_pnl(current_date + 10, current_date, null, null, 50)$$);
select t_expect_fail('טווח גדול מדי נדחה',
  $$select task_pnl(current_date - 500, current_date, null, null, 50)$$);

\echo '--- customers.view משמיט שדה ולא חוסם דוח ---'

select t_eq('עם המפתח, שם הלקוח מגיע',
  (t13row('31000000-0000-0000-0000-000000130001') ->> 'customer_name'),
  'לקוח רווחיות משימות');

-- בניגוד ל-0059, שהוא דוח **לפי לקוח** ולכן אינו קיים בלי המפתח, כאן השורה
-- היא משימה. המפתח משמיט שדה ואינו סוגר את הדלת.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000013a7', false);
select t_eq('בלי המפתח הדוח עדיין חוזר',
  jsonb_array_length(t13all() -> 'rows'), 7);
select t_eq('אבל בלי שם הלקוח',
  (t13row('31000000-0000-0000-0000-000000130001') ->> 'customer_name') is null, true);
select t_eq('והכותרת עדיין שם',
  (t13row('31000000-0000-0000-0000-000000130001') ->> 'title'), 'T1 שש שעות');
select t_eq('והמספרים זהים לאלה של הקורא המלא',
  (t13row('31000000-0000-0000-0000-000000130001') ->> 'gross')::numeric, 805::numeric);

\echo '--- ניטרליות: ההקצאה הישנה לא זזה ---'

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000013a1', false);
select t_eq('payroll_task_alloc: משויך + לא משויך = סך השכר',
  ((app.payroll_task_alloc((select dfrom from t13), (select dto from t13)) ->> 'allocated')::numeric
   + (app.payroll_task_alloc((select dfrom from t13), (select dto from t13)) ->> 'unallocated')::numeric),
  (app.payroll_summary((select dfrom from t13), (select dto from t13)) ->> 'total')::numeric);
select t_eq('by_customer נושא את המשויך כולו',
  (select round(sum((e ->> 'payroll')::numeric), 2)
     from jsonb_array_elements(
       app.payroll_task_alloc((select dfrom from t13), (select dto from t13)) -> 'by_customer') e),
  410::numeric);

reset role;
select set_config('request.jwt.claim.sub', '', false);
