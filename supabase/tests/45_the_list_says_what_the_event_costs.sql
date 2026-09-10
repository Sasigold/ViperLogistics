\pset tuples_only on
\pset format unaligned

-- ===========================================================================
-- 45: המחיר של האירוע ברשימה — `event_task_totals` (0169).
--
--   * **הסכום הוא של המשימות ושל התוספות שלהן**, בדיוק כמו כרטיס "סך תמחור"
--     בדף האירוע. שני מסכים שאומרים מספרים שונים על אותו אירוע הם באג, ולכן
--     הבדיקה משווה את הפונקציה לחישוב שהכרטיס עושה ולא רק למספר קבוע.
--   * **אירוע בלי תמחור מחזיר `null` ולא `0`.** אפס הוא מחיר; חוסר תמחור
--     אינו. הרשימה מציירת מקף על השני, וסכום על הראשון.
--   * **‏`pricing.view` הוא השער, והפונקציה אינה עוקפת אותו.** היא
--     ‏`security invoker` ואין בה פרדיקט משלה: ‏`work_board_view` ממסך את
--     ‏`customer_price` ו-`tpa_select` את התוספות. הלקוח מחזיק את המפתח
--     מ-0074 — זה הצד שלו בכסף, "כמה הוצאתי" — ולכן הוא כן מקבל סכום, אבל
--     של האירועים שלו בלבד; הקבלן, שאינו צד לזה (0017 §5), אינו מקבל דבר.
--
-- החבילה מקימה שני לקוחות, קבלן, שלושה אירועים, משימות וחמישה פרופילים משלה
-- ואינה נשענת על אף חבילה קודמת. האירועים יושבים ב-current_date + 620.
-- ===========================================================================

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000045a1', 'c45-staff@vl.test'),
  ('00000000-0000-0000-0000-0000000045a2', 'c45-cust@vl.test'),
  ('00000000-0000-0000-0000-0000000045a3', 'c45-ctr@vl.test'),
  ('00000000-0000-0000-0000-0000000045a4', 'c45-admin@vl.test'),
  ('00000000-0000-0000-0000-0000000045a5', 'c45-cust2@vl.test');

insert into customers (id, name) values
  ('10000000-0000-0000-0000-00000000045a', 'לקוח 45'),
  ('10000000-0000-0000-0000-00000000045b', 'לקוח 45 אחר');

insert into contractors (id, name) values
  ('11000000-0000-0000-0000-00000000045a', 'קבלן 45');

insert into profiles (id, user_id, user_kind, is_admin, full_name, customer_id, contractor_id) values
  ('20000000-0000-0000-0000-0000000045a1', '00000000-0000-0000-0000-0000000045a1',
   'staff', false, 'רכז 45', null, null),
  ('20000000-0000-0000-0000-0000000045a2', '00000000-0000-0000-0000-0000000045a2',
   'customer_user', false, 'מנהל לקוח 45', '10000000-0000-0000-0000-00000000045a', null),
  ('20000000-0000-0000-0000-0000000045a3', '00000000-0000-0000-0000-0000000045a3',
   'contractor_user', false, 'מנהל קבלן 45', null, '11000000-0000-0000-0000-00000000045a'),
  ('20000000-0000-0000-0000-0000000045a4', '00000000-0000-0000-0000-0000000045a4',
   'staff', true, 'מנהל מערכת 45', null, null),
  ('20000000-0000-0000-0000-0000000045a5', '00000000-0000-0000-0000-0000000045a5',
   'customer_user', false, 'מנהל לקוח 45 אחר', '10000000-0000-0000-0000-00000000045b', null);

insert into profile_roles (profile_id, role_id)
select p.pid, r.id from (values
  ('20000000-0000-0000-0000-0000000045a1'::uuid, 'dispatcher'),
  ('20000000-0000-0000-0000-0000000045a2'::uuid, 'customer_manager'),
  ('20000000-0000-0000-0000-0000000045a3'::uuid, 'contractor_manager'),
  ('20000000-0000-0000-0000-0000000045a5'::uuid, 'customer_manager')
) as p(pid, rkey) join permission_roles r on r.key = p.rkey;

insert into user_permission_grants (profile_id, permission_key, allowed) values
  ('20000000-0000-0000-0000-0000000045a1', 'pricing.view', true),
  ('20000000-0000-0000-0000-0000000045a1', 'pricing.edit', true);

-- שלושה אירועים: מתומחר, לא מתומחר, ואחד של לקוח אחר.
insert into events (id, customer_id, event_number, event_date, end_client_name, status_id)
select x.id, x.cust, x.num, current_date + 620, x.label,
       (select id from statuses where entity = 'event' and code = 'planned' and deleted_at is null)
from (values
  ('30000000-0000-0000-0000-00000000045a'::uuid, '10000000-0000-0000-0000-00000000045a'::uuid, 'EV-45A', 'לקוח קצה 45 א'),
  ('30000000-0000-0000-0000-00000000045b'::uuid, '10000000-0000-0000-0000-00000000045a'::uuid, 'EV-45B', 'לקוח קצה 45 ב'),
  ('30000000-0000-0000-0000-00000000045c'::uuid, '10000000-0000-0000-0000-00000000045b'::uuid, 'EV-45C', 'לקוח קצה 45 ג')
) as x(id, cust, num, label);

-- ‏`events_default_tasks` פותח הקמה ופירוק לכל אירוע חדש. החבילה סופרת משימות,
-- ולכן היא מנקה אותן ומזריעה בעצמה בדיוק את מה שהיא בודקת.
delete from tasks where event_id in (
  '30000000-0000-0000-0000-00000000045a',
  '30000000-0000-0000-0000-00000000045b',
  '30000000-0000-0000-0000-00000000045c');

-- שלוש משימות באירוע הראשון: שתיים מתומחרות ואחת לא, כדי ש-`priced_tasks`
-- ו-`task_count` יאמרו שני דברים שונים.
insert into tasks (id, event_id, customer_id, task_type_id, task_date,
                   onsite_start_time, hours_count, worker_count, status_id)
select x.id, x.event, x.cust,
       (select id from task_types where code = x.code limit 1), current_date + 620,
       '09:00', 4, 2,
       (select id from statuses where entity = 'task' and code = 'draft' and deleted_at is null)
from (values
  ('61000000-0000-0000-0000-000000045001'::uuid, '30000000-0000-0000-0000-00000000045a'::uuid,
   '10000000-0000-0000-0000-00000000045a'::uuid, 'setup'),
  ('61000000-0000-0000-0000-000000045002'::uuid, '30000000-0000-0000-0000-00000000045a'::uuid,
   '10000000-0000-0000-0000-00000000045a'::uuid, 'teardown'),
  ('61000000-0000-0000-0000-000000045003'::uuid, '30000000-0000-0000-0000-00000000045a'::uuid,
   '10000000-0000-0000-0000-00000000045a'::uuid, 'setup'),
  ('61000000-0000-0000-0000-000000045004'::uuid, '30000000-0000-0000-0000-00000000045b'::uuid,
   '10000000-0000-0000-0000-00000000045a'::uuid, 'setup'),
  ('61000000-0000-0000-0000-000000045005'::uuid, '30000000-0000-0000-0000-00000000045c'::uuid,
   '10000000-0000-0000-0000-00000000045b'::uuid, 'setup')
) as x(id, event, cust, code);

-- ‏`tasks_price` מחשב מחיר לבד; ההשתלטות המפורשת היא מה שמקבע את המספרים.
insert into task_pricing (task_id, price, is_manual) values
  ('61000000-0000-0000-0000-000000045001', 1000, true),
  ('61000000-0000-0000-0000-000000045002',  400, true),
  ('61000000-0000-0000-0000-000000045005',  777, true)
on conflict (task_id) do update set price = excluded.price, is_manual = true;

delete from task_pricing where task_id in
  ('61000000-0000-0000-0000-000000045003', '61000000-0000-0000-0000-000000045004');

-- תוספת אחת על משימה מתומחרת, ואחת "יתומה" על המשימה בלי מחיר: שתיהן כסף
-- שהאירוע גובה, וסך האירוע חייב להכיל את שתיהן.
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000045a1', false);
insert into task_price_addons (task_id, amount, note) values
  ('61000000-0000-0000-0000-000000045001', 250, 'המתנה בשער, שעתיים'),
  ('61000000-0000-0000-0000-000000045003',  80, 'משאית שנייה');
reset role;
select set_config('request.jwt.claim.sub', '', false);

-- ===== 1. המשרד: הסכום, והמונים ============================================

\echo '--- מחיר האירוע: המשרד ---'

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000045a1', false);

select t_eq('סך האירוע הוא המשימות ועוד התוספות',
  (select price_total from event_task_totals(array['30000000-0000-0000-0000-00000000045a'::uuid])),
  1730::numeric);

select t_eq('המונה סופר את המשימות שיש להן מחיר',
  (select priced_tasks from event_task_totals(array['30000000-0000-0000-0000-00000000045a'::uuid])),
  2);

select t_eq('ולצדו כמה משימות יש באירוע בכלל',
  (select task_count from event_task_totals(array['30000000-0000-0000-0000-00000000045a'::uuid])),
  3);

select t_eq('אירוע בלי תמחור ובלי תוספות מחזיר null ולא אפס',
  (select price_total from event_task_totals(array['30000000-0000-0000-0000-00000000045b'::uuid])),
  null::numeric);

select t_eq('אבל הוא עדיין שורה — ולא אירוע שנעלם מהרשימה',
  (select task_count from event_task_totals(array['30000000-0000-0000-0000-00000000045b'::uuid])),
  1);

select t_eq('שני מזהים, שתי שורות — אחת לכל אירוע',
  (select count(*)::int from event_task_totals(array[
     '30000000-0000-0000-0000-00000000045a'::uuid,
     '30000000-0000-0000-0000-00000000045b'::uuid])),
  2);

-- הבטחה שהרשימה ודף האירוע אומרים אותו מספר: הכרטיס שם מסכם `customer_price`
-- ומוסיף `event_price_addons`, וזה בדיוק מה שנבדק כאן מול הפונקציה החדשה.
select t_eq('והמספר מסכים עם מה שכרטיס התמחור בדף האירוע מחשב',
  (select price_total from event_task_totals(array['30000000-0000-0000-0000-00000000045a'::uuid])),
  (select coalesce(sum(v.customer_price), 0) from work_board_view v
    where v.event_id = '30000000-0000-0000-0000-00000000045a')
  + (select coalesce(sum(amount), 0)
       from event_price_addons('30000000-0000-0000-0000-00000000045a')));

reset role;
select set_config('request.jwt.claim.sub', '', false);

-- ===== 2. מחיקה רכה של משימה יורדת מהסכום ==================================
--
-- ‏`work_board_view` מסננת משימה מחוקה, וזה מה שמונע מהסכום להיות "כמעט נכון"
-- אחרי מחיקה — הכשל הרגיל של סכום נגזר ששמור על השורה.

update tasks set deleted_at = now() where id = '61000000-0000-0000-0000-000000045002';

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000045a1', false);

select t_eq('אחרי מחיקה רכה הסכום הוא מה שנשאר',
  (select price_total from event_task_totals(array['30000000-0000-0000-0000-00000000045a'::uuid])),
  1330::numeric);

select t_eq('והמשימה המחוקה אינה נספרת עוד',
  (select task_count from event_task_totals(array['30000000-0000-0000-0000-00000000045a'::uuid])),
  2);

reset role;
select set_config('request.jwt.claim.sub', '', false);

-- ===== 3. מנהל המערכת רואה את הכול =========================================

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000045a4', false);

select t_eq('מנהל המערכת מקבל את אותו סכום',
  (select price_total from event_task_totals(array['30000000-0000-0000-0000-00000000045a'::uuid])),
  1330::numeric);

reset role;
select set_config('request.jwt.claim.sub', '', false);

-- ===== 4. הלקוח: האירועים שלו, ורק הם ======================================
--
-- ‏0074 השאיר בידו את `pricing.view` — זה הצד שלו באותו מספר, "כמה שילמתי" —
-- וסגר את `pricing.revenue` ואת `finance.income_view`. הפונקציה אינה מרחיבה
-- ואינה מצמצמת את זה; ‏RLS על `tasks` היא שמכריעה אילו אירועים היא רואה.

\echo '--- מחיר האירוע: הלקוח ---'

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000045a2', false);

select t_eq('ללקוח יש pricing.view — זה הצד שלו בכסף', app.has('pricing.view'), true);
select t_eq('ואין לו pricing.revenue', app.has('pricing.revenue'), false);

select t_eq('הוא מקבל את הסכום של האירוע שלו',
  (select price_total from event_task_totals(array['30000000-0000-0000-0000-00000000045a'::uuid])),
  1330::numeric);

select t_eq('ועל אירוע של לקוח אחר אין לו שורה בכלל',
  (select count(*)::int from event_task_totals(array['30000000-0000-0000-0000-00000000045c'::uuid])),
  0);

select t_eq('גם כששני המזהים נשלחים יחד, חוזר רק שלו',
  (select count(*)::int from event_task_totals(array[
     '30000000-0000-0000-0000-00000000045a'::uuid,
     '30000000-0000-0000-0000-00000000045c'::uuid])),
  1);

reset role;
select set_config('request.jwt.claim.sub', '', false);

-- ===== 5. הקבלן אינו צד לזה ================================================

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000045a3', false);

select t_eq('מנהל הקבלן אינו מקבל את מחיר הלקוח',
  (select price_total from event_task_totals(array['30000000-0000-0000-0000-00000000045a'::uuid])),
  null::numeric);

reset role;
select set_config('request.jwt.claim.sub', '', false);

-- ===== 6. אנונימי אינו קורא לפונקציה =======================================

set role anon;
select t_expect_fail('anon אינו רשאי להריץ את event_task_totals', $$
  select * from event_task_totals(array['30000000-0000-0000-0000-00000000045a'::uuid])$$);
reset role;
