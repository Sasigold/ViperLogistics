\pset tuples_only on
\pset format unaligned

-- ===========================================================================
-- 51: שעה של עובד קבלן נספרת פעם אחת (0186).
--
-- הדיווח: "אם האצלתי לקבלן אתה מחשב פעמיים — פעם התשלום לקבלן, ופעם ההחתמה
-- של העובד של הקבלן בשעון". ‏0186 מנכה את ההחתמה **רק** כשהיא נופלת על
-- משימה שהואצלה לקבלן של אותו עובד, והוא משובץ עליה בכובע הקבלני.
--
-- החבילה מקימה לקוח, קבלן, אירוע, ארבע משימות וחמש דמויות משלה ואינה
-- נשענת על אף חבילה קודמת. האירוע יושב ב-current_date + 760, מעבר לכל טווח
-- אחר, כדי שכל סכום גלובלי שנמדד כאן יהיה של השורות שלה בלבד. היא רצה
-- אחרונה כי היא משאירה אחריה משימות, שיבוצים ומשמרות שאינם מנוקים.
--
-- **התאריכים מעוגנים ליום שני**, מאותו טעם של 13: `attendance.overtime`
-- מגדיר `rest_day.dow = [6]`, ומשמרת שהייתה נופלת בשבת מתומחרת ב-150%.
--
-- ארבע משימות, ולכל אחת השאלה שהיא בודקת:
--
--   TA  הואצלה, 1200 ₪  │ עובד שלנו (200) + עובד הקבלן (240)
--                        │ → 240 מנוכים, 200 נשארים.        ← הבאג עצמו
--   TB  לא הואצלה        │ אותו עובד קבלן, על משימה של אף אחד אחר (240)
--                        │ → אין מה לנכות.                  ← שמירה
--   TC  הואצלה,  800 ₪   │ דו-כובע (0075) שמשובץ כסגל *שלנו* (280)
--                        │ → אין מה לנכות.                  ← שמירה
--   TD  הואצלה,  500 ₪   │ עובד קבלן בלי תעריף אצלנו
--                        │ → שכר 0, ו**בלי** אזהרת "משמרת ללא תעריף".
--
-- אריתמטיקה: ארבע משמרות של ארבע שעות (מתחת למדרגת השעות הנוספות, ולכן
-- שכר ישר), תעריפים 50 / 60 / 70, ונטל מעביד 30% (0068).
--
-- הזריעה רצה בלי JWT (auth.uid() = null), ולכן הטריגרים מדלגים.
-- ===========================================================================

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000051a1', 'c51-reader@vl.test'),
  ('00000000-0000-0000-0000-0000000051b1', 'c51-ours@vl.test'),
  ('00000000-0000-0000-0000-0000000051b2', 'c51-cw1@vl.test'),
  ('00000000-0000-0000-0000-0000000051b3', 'c51-cw2@vl.test'),
  ('00000000-0000-0000-0000-0000000051b4', 'c51-dual@vl.test');

insert into customers (id, name) values
  ('10000000-0000-0000-0000-000000000051', 'לקוח 51');

-- בלי `price_per_worker` ובלי `default_task_price`: ‏`app.recompute_contractor_price`
-- (0091) יוצאת מיד כשאין תעריף-לעובד, ולכן שיבוץ עובד קבלן אינו דורס את
-- המחירים שנזרעים כאן.
insert into contractors (id, name) values
  ('11000000-0000-0000-0000-000000000051', 'קבלן 51');

insert into contractor_workers (id, contractor_id, full_name) values
  ('12000000-0000-0000-0000-00000000051a', '11000000-0000-0000-0000-000000000051', 'סגל 51 א'),
  ('12000000-0000-0000-0000-00000000051b', '11000000-0000-0000-0000-000000000051', 'סגל 51 ב'),
  ('12000000-0000-0000-0000-00000000051c', '11000000-0000-0000-0000-000000000051', 'סגל 51 ג');

insert into profiles (id, user_id, user_kind, is_admin, full_name,
                      contractor_id, contractor_worker_id) values
  ('20000000-0000-0000-0000-0000000051a1', '00000000-0000-0000-0000-0000000051a1',
   'staff', false, 'קורא רווחיות 51', null, null),
  -- עובד שלנו לכל דבר
  ('20000000-0000-0000-0000-0000000051b1', '00000000-0000-0000-0000-0000000051b1',
   'staff', false, 'עובד וייפר 51', null, null),
  -- שני עובדי הקבלן, עם חשבון ועם שורת רוסטר (0150)
  ('20000000-0000-0000-0000-0000000051b2', '00000000-0000-0000-0000-0000000051b2',
   'contractor_user', false, 'סגל 51 א', '11000000-0000-0000-0000-000000000051',
   '12000000-0000-0000-0000-00000000051a'),
  ('20000000-0000-0000-0000-0000000051b3', '00000000-0000-0000-0000-0000000051b3',
   'contractor_user', false, 'סגל 51 ב', '11000000-0000-0000-0000-000000000051',
   '12000000-0000-0000-0000-00000000051b'),
  -- הדו-כובע של 0075: איש צוות שלנו, שמקושר לאותו קבלן
  ('20000000-0000-0000-0000-0000000051b4', '00000000-0000-0000-0000-0000000051b4',
   'staff', false, 'דו-כובע 51', '11000000-0000-0000-0000-000000000051',
   '12000000-0000-0000-0000-00000000051c');

-- ‏b3 בכוונה בלי תעריף: הוא הדמות של "עובד קבלן שאין לו תעריף אצלנו"
insert into worker_pay_settings (profile_id, hourly_rate) values
  ('20000000-0000-0000-0000-0000000051b1', 50),
  ('20000000-0000-0000-0000-0000000051b2', 60),
  ('20000000-0000-0000-0000-0000000051b4', 70);

insert into user_permission_grants (profile_id, permission_key, allowed) values
  ('20000000-0000-0000-0000-0000000051a1', 'reports.view',              true),
  ('20000000-0000-0000-0000-0000000051a1', 'dashboard.margin',          true),
  ('20000000-0000-0000-0000-0000000051a1', 'dashboard.payroll',         true),
  ('20000000-0000-0000-0000-0000000051a1', 'dashboard.contractor_cost', true),
  ('20000000-0000-0000-0000-0000000051a1', 'pricing.revenue',           true),
  ('20000000-0000-0000-0000-0000000051a1', 'dashboard.all_workers',     true),
  ('20000000-0000-0000-0000-0000000051a1', 'customers.view',            true),
  ('20000000-0000-0000-0000-0000000051a1', 'contractors.view',          true),
  ('20000000-0000-0000-0000-0000000051a1', 'contractors.view_pricing',  true);

create temp table t51 as
select date_trunc('week', current_date + 760)::date      as d0,
       date_trunc('week', current_date + 760)::date + 1  as d1,
       date_trunc('week', current_date + 760)::date - 3  as dfrom,
       date_trunc('week', current_date + 760)::date + 10 as dto;
grant select on t51 to authenticated;

insert into events (id, customer_id, event_number, event_date, status_id)
select '30000000-0000-0000-0000-000000000051', '10000000-0000-0000-0000-000000000051',
       'EV-51', d0,
       (select id from statuses where entity = 'event' and code = 'planned'
                                  and deleted_at is null)
from t51;

-- ‏0009 יוצר משימות הקמה/פירוק אוטומטיות; הן אינן חלק מהאריתמטיקה כאן.
delete from tasks where event_id = '30000000-0000-0000-0000-000000000051';

insert into tasks (id, event_id, customer_id, task_type_id, task_date, status_id,
                   title, hours_count, worker_count)
select v.id, '30000000-0000-0000-0000-000000000051',
       '10000000-0000-0000-0000-000000000051',
       (select id from task_types where code = 'setup' limit 1),
       (select d0 from t51),
       (select id from statuses where entity = 'task' and code = 'assigned'
                                  and deleted_at is null),
       v.title, 4::numeric, 2
from (values
  ('31000000-0000-0000-0000-000000510001'::uuid, 'TA הואצלה + עובד שלנו'),
  ('31000000-0000-0000-0000-000000510002'::uuid, 'TB לא הואצלה'),
  ('31000000-0000-0000-0000-000000510003'::uuid, 'TC הואצלה + דו-כובע'),
  ('31000000-0000-0000-0000-000000510004'::uuid, 'TD הואצלה + עובד בלי תעריף')
) v(id, title);

-- ‏0096: ההאצלה היא שורה ב-task_contractor_terms, ו-`tasks.contractor_id`
-- הוא שיקוף שהטריגר מתחזק. הזריעה כותבת את האמת, לא את השיקוף.
insert into task_contractor_terms (task_id, contractor_id, price) values
  ('31000000-0000-0000-0000-000000510001', '11000000-0000-0000-0000-000000000051', 1200),
  ('31000000-0000-0000-0000-000000510003', '11000000-0000-0000-0000-000000000051',  800),
  ('31000000-0000-0000-0000-000000510004', '11000000-0000-0000-0000-000000000051',  500);

-- מי משובץ בכובע הקבלני. ‏TC מקבל את סגל א׳ — הקבלן אכן שלח מישהו — והדו-כובע
-- יושב עליה ב-`task_assignments`, כלומר בכובע שלנו.
insert into task_contractor_workers (task_id, contractor_worker_id) values
  ('31000000-0000-0000-0000-000000510001', '12000000-0000-0000-0000-00000000051a'),
  ('31000000-0000-0000-0000-000000510003', '12000000-0000-0000-0000-00000000051a'),
  ('31000000-0000-0000-0000-000000510004', '12000000-0000-0000-0000-00000000051b');

insert into task_assignments (task_id, profile_id, role) values
  ('31000000-0000-0000-0000-000000510001', '20000000-0000-0000-0000-0000000051b1', 'worker'),
  ('31000000-0000-0000-0000-000000510003', '20000000-0000-0000-0000-0000000051b4', 'worker');

insert into task_pricing (task_id, price, is_manual) values
  ('31000000-0000-0000-0000-000000510001', 3000, true),
  ('31000000-0000-0000-0000-000000510002', 1000, true),
  ('31000000-0000-0000-0000-000000510003', 2000, true),
  ('31000000-0000-0000-0000-000000510004',  900, true);

-- חמש משמרות של ארבע שעות, בימי חול
insert into attendance_entries (id, profile_id, work_date, seq, task_ids,
                                clock_in_at, clock_out_at, source)
select v.id, v.profile, v.d, 1, v.tasks,
       v.d + time '08:00', v.d + time '12:00', 'manual'
from (values
  -- TA: שלנו (200) ושל הקבלן (240)
  ('70000000-0000-0000-0000-000000510001'::uuid,
   '20000000-0000-0000-0000-0000000051b1'::uuid, (select d0 from t51),
   array['31000000-0000-0000-0000-000000510001']::uuid[]),
  ('70000000-0000-0000-0000-000000510002'::uuid,
   '20000000-0000-0000-0000-0000000051b2'::uuid, (select d0 from t51),
   array['31000000-0000-0000-0000-000000510001']::uuid[]),
  -- TB: אותו עובד קבלן, על משימה שלא הואצלה לאיש
  ('70000000-0000-0000-0000-000000510003'::uuid,
   '20000000-0000-0000-0000-0000000051b2'::uuid, (select d1 from t51),
   array['31000000-0000-0000-0000-000000510002']::uuid[]),
  -- TC: הדו-כובע, בכובע שלנו
  ('70000000-0000-0000-0000-000000510004'::uuid,
   '20000000-0000-0000-0000-0000000051b4'::uuid, (select d0 from t51),
   array['31000000-0000-0000-0000-000000510003']::uuid[]),
  -- TD: עובד קבלן בלי תעריף
  ('70000000-0000-0000-0000-000000510005'::uuid,
   '20000000-0000-0000-0000-0000000051b3'::uuid, (select d0 from t51),
   array['31000000-0000-0000-0000-000000510004']::uuid[])
) v(id, profile, d, tasks);

create or replace function t51row(p_task text) returns jsonb language sql stable as $$
  select r from jsonb_array_elements(
    (task_pnl((select dfrom from t51), (select dto from t51), null, null, 500)) -> 'rows') r
   where r ->> 'task_id' = p_task
$$;
grant execute on function t51row(text) to authenticated;

create or replace function t51all() returns jsonb language sql stable as $$
  select task_pnl((select dfrom from t51), (select dto from t51), null, null, 500)
$$;
grant execute on function t51all() to authenticated;

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000051a1', false);

\echo '--- TA: הבאג עצמו — העובד של הקבלן אינו נספר פעמיים ---'

select t_eq('עלות הקבלן היא מה שסוכם איתו',
  (t51row('31000000-0000-0000-0000-000000510001') ->> 'contractor_cost')::numeric,
  1200::numeric);
-- ‏240 + 200 = 440 היה המספר לפני 0186
select t_eq('והשכר הוא של העובד שלנו בלבד',
  (t51row('31000000-0000-0000-0000-000000510001') ->> 'payroll')::numeric, 200::numeric);
select t_eq('ומה שנוכה מדווח במפורש',
  (t51row('31000000-0000-0000-0000-000000510001') ->> 'payroll_contractor_covered')::numeric,
  240::numeric);
select t_eq('נטל המעביד יושב על השכר שלנו בלבד',
  (t51row('31000000-0000-0000-0000-000000510001') ->> 'payroll_with_employer')::numeric,
  260::numeric);
select t_eq('העלות הכוללת = קבלן + שכר עם נטל',
  (t51row('31000000-0000-0000-0000-000000510001') ->> 'cost_total')::numeric, 1460::numeric);
select t_eq('והרווח = 3000 − 1460',
  (t51row('31000000-0000-0000-0000-000000510001') ->> 'gross')::numeric, 1540::numeric);

-- מה ש*לא* השתנה: העובד של הקבלן אכן עבד, והשורה ממשיכה לומר את זה
select t_eq('שתי המשמרות עדיין נספרות כמשמרות',
  (t51row('31000000-0000-0000-0000-000000510001') ->> 'shifts')::int, 2);
select t_eq('ושני העובדים עדיין נספרים כעובדים בפועל',
  (t51row('31000000-0000-0000-0000-000000510001') ->> 'actual_workers')::int, 2);
select t_eq('וכל שמונה השעות שהוחתמו',
  (t51row('31000000-0000-0000-0000-000000510001') ->> 'actual_hours')::numeric, 8::numeric);

\echo '--- TB: אותו עובד, משימה שלא הואצלה — אין מה לנכות ---'

select t_eq('אין עלות קבלן',
  (t51row('31000000-0000-0000-0000-000000510002') ->> 'contractor_cost')::numeric, 0::numeric);
select t_eq('והשכר שלו נספר במלואו',
  (t51row('31000000-0000-0000-0000-000000510002') ->> 'payroll')::numeric, 240::numeric);
select t_eq('ולא נוכה דבר',
  (t51row('31000000-0000-0000-0000-000000510002') ->> 'payroll_contractor_covered')::numeric,
  0::numeric);

\echo '--- TC: דו-כובע (0075) שעבד בכובע שלנו — אין מה לנכות ---'

-- זו הטענה שמגינה על ההכרעה "איזה כובע", ולא "מי הוא": אותו אדם מקושר
-- לאותו קבלן שהמשימה הואצלה אליו, ובכל זאת השכר שלו הוא שלנו.
select t_eq('הוא אכן מקושר לקבלן שהמשימה הואצלה אליו',
  (select count(*)::int from profiles p
    where p.id = '20000000-0000-0000-0000-0000000051b4'
      and p.contractor_id = '11000000-0000-0000-0000-000000000051'), 1);
select t_eq('ובכל זאת השכר שלו נספר במלואו',
  (t51row('31000000-0000-0000-0000-000000510003') ->> 'payroll')::numeric, 280::numeric);
select t_eq('ולא נוכה דבר',
  (t51row('31000000-0000-0000-0000-000000510003') ->> 'payroll_contractor_covered')::numeric,
  0::numeric);
select t_eq('עלות הקבלן נשארת כמובן',
  (t51row('31000000-0000-0000-0000-000000510003') ->> 'contractor_cost')::numeric, 800::numeric);
select t_eq('והרווח = 2000 − 800 − 364',
  (t51row('31000000-0000-0000-0000-000000510003') ->> 'gross')::numeric, 836::numeric);

\echo '--- TD: עובד קבלן בלי תעריף — ובלי אזהרה שאינה שלנו ---'

select t_eq('השכר 0, כמו קודם',
  (t51row('31000000-0000-0000-0000-000000510004') ->> 'payroll')::numeric, 0::numeric);
select t_eq('והמשמרת נספרת כמשמרת',
  (t51row('31000000-0000-0000-0000-000000510004') ->> 'shifts')::int, 1);
-- לפני 0186 השורה הזו הייתה מכריזה "משמרת אחת אינה נספרת" ושולחת את המשרד
-- לחפש תעריף לעובד שאינו שלו. היא נספרת — במחיר הקבלן.
select t_eq('אבל היא אינה "משמרת ללא תעריף"',
  (t51row('31000000-0000-0000-0000-000000510004') ->> 'unrated_shifts')::int, 0);
select t_eq('והרווח = 900 − 500',
  (t51row('31000000-0000-0000-0000-000000510004') ->> 'gross')::numeric, 400::numeric);

\echo '--- הסיכום והמונים ---'

select t_eq('ארבע משימות בטווח',
  (t51all() #>> '{summary,tasks}')::int, 4);
select t_eq('סך ההכנסות',
  (t51all() #>> '{summary,revenue}')::numeric, 6900::numeric);
select t_eq('סך עלות הקבלנים',
  (t51all() #>> '{summary,contractor}')::numeric, 2500::numeric);
select t_eq('סך השכר — נטו',
  (t51all() #>> '{summary,payroll}')::numeric, 720::numeric);
select t_eq('ומה שנוכה, בסכום',
  (t51all() #>> '{summary,payroll_contractor_covered}')::numeric, 240::numeric);
select t_eq('סך הרווח',
  (t51all() #>> '{summary,gross}')::numeric, 3464::numeric);
select t_eq('וסכום הרווח של השורות שווה לו',
  (select round(sum((r ->> 'gross')::numeric), 2)
     from jsonb_array_elements(t51all() -> 'rows') r), 3464::numeric);
select t_eq('ה-meta אומר כמה נוכה',
  (t51all() #>> '{meta,contractor_covered}')::numeric, 240::numeric);
select t_eq('ובכמה משימות',
  (t51all() #>> '{meta,contractor_covered_tasks}')::int, 1);
select t_eq('ואין בטווח אף משמרת ללא תעריף שהיא שלנו',
  (t51all() #>> '{meta,unrated_shifts}')::int, 0);

\echo '--- השעון עצמו אינו זז ---'

-- ‏0186 מנכה ברווח, ולא בשכר. דוח הנוכחות והדשבורד של השכר ממשיכים לדווח
-- את מה שההחתמות מייצרות — אחרת אי אפשר היה ליישב אותם זה מול זה.
select t_eq('סך השכר שהשעון הפיק לא השתנה',
  (app.payroll_summary((select dfrom from t51), (select dto from t51)) ->> 'total')::numeric,
  960::numeric);
select t_eq('וגם המונה של משמרת ללא תעריף נשאר שם',
  (app.payroll_summary((select dfrom from t51), (select dto from t51)) ->> 'unrated_shifts')::int,
  1);
select t_eq('ההקצאה: משויך + לא משויך = סך השכר',
  ((app.payroll_task_alloc((select dfrom from t51), (select dto from t51)) ->> 'allocated')::numeric
   + (app.payroll_task_alloc((select dfrom from t51), (select dto from t51)) ->> 'unallocated')::numeric),
  960::numeric);
select t_eq('וההקצאה נושאת את מה שהקבלן כיסה לצדה',
  (app.payroll_task_alloc((select dfrom from t51), (select dto from t51))
     ->> 'contractor_covered')::numeric, 240::numeric);

\echo '--- הסכומים הגלובליים מסכימים עם השורות ---'

select t_eq('margin_summary: הכנסה',
  (app.margin_summary((select dfrom from t51), (select dto from t51)) ->> 'revenue')::numeric,
  6900::numeric);
select t_eq('margin_summary: עלות קבלנים',
  (app.margin_summary((select dfrom from t51), (select dto from t51)) ->> 'contractor')::numeric,
  2500::numeric);
select t_eq('margin_summary: שכר נטו',
  (app.margin_summary((select dfrom from t51), (select dto from t51)) ->> 'payroll')::numeric,
  720::numeric);
select t_eq('margin_summary: והברוטו לצדו',
  (app.margin_summary((select dfrom from t51), (select dto from t51)) ->> 'payroll_gross')::numeric,
  960::numeric);
select t_eq('margin_summary: וההפרש נקוב בשמו',
  (app.margin_summary((select dfrom from t51), (select dto from t51))
     ->> 'contractor_covered')::numeric, 240::numeric);
-- ‏05_dashboard כבר טוען שהחיסור הזה מתקיים; כאן הוא נטען על המספרים שלנו
select t_eq('margin_summary: רווח = הכנסה − קבלן − שכר',
  (app.margin_summary((select dfrom from t51), (select dto from t51)) ->> 'gross')::numeric,
  3680::numeric);

select t_eq('margin_by_customer: השכר של הלקוח הוא הנטו',
  (select (e ->> 'payroll')::numeric
     from jsonb_array_elements(
       app.margin_by_customer((select dfrom from t51), (select dto from t51), 50) -> 'rows') e
    where e ->> 'name' = 'לקוח 51'), 720::numeric);
select t_eq('margin_by_customer: והרווח שלו',
  (select round((e ->> 'revenue')::numeric - (e ->> 'contractor')::numeric
                - (e ->> 'payroll')::numeric, 2)
     from jsonb_array_elements(
       app.margin_by_customer((select dfrom from t51), (select dto from t51), 50) -> 'rows') e
    where e ->> 'name' = 'לקוח 51'), 3680::numeric);

select t_eq('margin_trend: סך השכר בדליים שווה לנטו',
  (select round(sum((e ->> 'payroll')::numeric), 2)
     from jsonb_array_elements(
       app.margin_trend((select dfrom from t51), (select dto from t51), 'day')) e),
  720::numeric);
select t_eq('margin_trend: ואף דלי אינו יוצא שלילי',
  (select bool_and((e ->> 'payroll')::numeric >= 0)
     from jsonb_array_elements(
       app.margin_trend((select dfrom from t51), (select dto from t51), 'day')) e), true);

reset role;
select set_config('request.jwt.claim.sub', '', false);
