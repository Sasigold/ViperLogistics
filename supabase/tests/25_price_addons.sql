\pset tuples_only on
\pset format unaligned

-- ===========================================================================
-- 25: תוספת מחיר למשימה, עם ההערה שהלקוח קורא (0113).
--
--   * **המשרד מוסיף.** מי שמחזיק `pricing.edit` רושם סכום והערה, וזה הכול.
--   * **הלקוח קורא ואינו כותב.** הוא רואה את התוספות של האירוע שלו — כי זו
--     כל מטרתן — ואינו מוסיף, אינו עורך ואינו מסיר. אצלו הבדיקה נעשית עם
--     המפתח *ביד*: הפוליסה שואלת גם על הצד ולא רק על המפתח, ובלי זה מנהל
--     מערכת שהעניק לו `pricing.edit` בטעות היה פותח לו לתמחר את עצמו.
--   * **הקבלן אינו רואה כלל.** מה שהלקוח משלם אינו עניינו, בדיוק כמו
--     ‏`task_pricing` (0017 §5).
--   * **ההסרה היא רכה, עוברת ב-RPC, ונרשמת ביומן** — יחד עם ההוספה.
--
-- החבילה מקימה לקוח, קבלן, אירוע, משימות וארבע דמויות משלה ואינה נשענת על אף
-- חבילה קודמת. האירוע יושב ב-current_date + 410, מעבר לכל טווח אחר.
-- ===========================================================================

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000025a1', 'c25-staff@vl.test'),
  ('00000000-0000-0000-0000-0000000025a2', 'c25-cust@vl.test'),
  ('00000000-0000-0000-0000-0000000025a3', 'c25-ctr@vl.test'),
  ('00000000-0000-0000-0000-0000000025a4', 'c25-admin@vl.test');

insert into customers (id, name) values
  ('10000000-0000-0000-0000-00000000025a', 'לקוח 25');

insert into contractors (id, name) values
  ('11000000-0000-0000-0000-00000000025a', 'קבלן 25');

insert into profiles (id, user_id, user_kind, is_admin, full_name, customer_id, contractor_id) values
  ('20000000-0000-0000-0000-0000000025a1', '00000000-0000-0000-0000-0000000025a1',
   'staff', false, 'רכז 25', null, null),
  ('20000000-0000-0000-0000-0000000025a2', '00000000-0000-0000-0000-0000000025a2',
   'customer_user', false, 'מנהל לקוח 25', '10000000-0000-0000-0000-00000000025a', null),
  ('20000000-0000-0000-0000-0000000025a3', '00000000-0000-0000-0000-0000000025a3',
   'contractor_user', false, 'מנהל קבלן 25', null, '11000000-0000-0000-0000-00000000025a'),
  ('20000000-0000-0000-0000-0000000025a4', '00000000-0000-0000-0000-0000000025a4',
   'staff', true, 'מנהל מערכת 25', null, null);

insert into profile_roles (profile_id, role_id)
select p.pid, r.id from (values
  ('20000000-0000-0000-0000-0000000025a1'::uuid, 'dispatcher'),
  ('20000000-0000-0000-0000-0000000025a2'::uuid, 'customer_manager'),
  ('20000000-0000-0000-0000-0000000025a3'::uuid, 'contractor_manager')
) as p(pid, rkey) join permission_roles r on r.key = p.rkey;

-- הרכז מתמחר; הלקוח *גם* מקבל את המפתח, וזו הנקודה של סעיף 3.
insert into user_permission_grants (profile_id, permission_key, allowed) values
  ('20000000-0000-0000-0000-0000000025a1', 'pricing.view', true),
  ('20000000-0000-0000-0000-0000000025a1', 'pricing.edit', true),
  ('20000000-0000-0000-0000-0000000025a2', 'pricing.view', true),
  ('20000000-0000-0000-0000-0000000025a2', 'pricing.edit', true);

insert into events (id, customer_id, event_number, event_date, end_client_name, status_id)
values ('30000000-0000-0000-0000-00000000025a', '10000000-0000-0000-0000-00000000025a',
        'EV-25', current_date + 410, 'לקוח קצה 25',
        (select id from statuses where entity = 'event' and code = 'planned' and deleted_at is null));

-- שתי משימות: אחת מתומחרת, ואחת שאין לה מחיר — כדי שתוספת "יתומה" תיבדק גם היא.
insert into tasks (id, event_id, customer_id, task_type_id, task_date,
                   onsite_start_time, hours_count, worker_count, status_id)
select x.id, '30000000-0000-0000-0000-00000000025a', '10000000-0000-0000-0000-00000000025a',
       (select id from task_types where code = x.code limit 1), current_date + 410,
       '09:00', 4, 2,
       (select id from statuses where entity = 'task' and code = 'draft' and deleted_at is null)
from (values
  ('61000000-0000-0000-0000-000000025001'::uuid, 'setup'),
  ('61000000-0000-0000-0000-000000025002'::uuid, 'teardown')
) as x(id, code);

insert into task_pricing (task_id, price, is_manual)
values ('61000000-0000-0000-0000-000000025001', 1000, true);

-- ===== 1. המשרד מוסיף ======================================================

\echo '--- תוספת מחיר: המשרד ---'

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000025a1', false);

select t_expect_ok('רכז עם pricing.edit מוסיף תוספת', $$
  insert into task_price_addons (task_id, amount, note)
  values ('61000000-0000-0000-0000-000000025001', 250, 'המתנה בשער, שעתיים')$$);

select t_expect_ok('וגם הנחה — אותה ישות בסימן הפוך', $$
  insert into task_price_addons (task_id, amount, note)
  values ('61000000-0000-0000-0000-000000025001', -100, 'זיכוי על איחור שלנו')$$);

-- אפס אינו תוספת אלא הערה, והערה מקומה ביומן
select t_expect_fail('סכום אפס נדחה', $$
  insert into task_price_addons (task_id, amount, note)
  values ('61000000-0000-0000-0000-000000025001', 0, 'כלום')$$);

-- וכך גם תוספת בלי משפט: היא בדיוק המספר חסר ההסבר שהיא באה להחליף
select t_expect_fail('והערה ריקה נדחית', $$
  insert into task_price_addons (task_id, amount, note)
  values ('61000000-0000-0000-0000-000000025001', 50, '   ')$$);

-- תוספת על משימה שאין לה עדיין מחיר — היא עומדת בפני עצמה
select t_expect_ok('ותוספת על משימה בלי מחיר', $$
  insert into task_price_addons (task_id, amount, note)
  values ('61000000-0000-0000-0000-000000025002', 80, 'משאית שנייה')$$);

reset role;
select set_config('request.jwt.claim.sub', '', false);

select t_eq('מי הוסיף נכפה מהשרת ולא מהקליינט',
  (select count(*)::int from task_price_addons
    where task_id = '61000000-0000-0000-0000-000000025001'
      and created_by = '20000000-0000-0000-0000-0000000025a1'), 2);

select t_eq('ושם המוסיף נשמר לצד המזהה',
  (select distinct creator_name from task_price_addons
    where task_id = '61000000-0000-0000-0000-000000025001'), 'רכז 25');

-- ===== 2. היומן של האירוע ==================================================

select t_eq('כל תוספת נרשמה ביומן האירוע',
  (select count(*)::int from event_activity
    where event_id = '30000000-0000-0000-0000-00000000025a'
      and kind = 'price_addon_added'), 3);

select t_eq('והשורה נושאת את הסכום ואת המשפט',
  (select count(*)::int from event_activity
    where event_id = '30000000-0000-0000-0000-00000000025a'
      and kind = 'price_addon_added'
      and note like '%250.00 ₪%המתנה בשער%'), 1);

-- ===== 3. הלקוח: קורא, ולא כותב ============================================

\echo '--- תוספת מחיר: הלקוח ---'

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000025a2', false);

select t_eq('הלקוח רואה את התוספות של האירוע שלו',
  (select count(*)::int from task_price_addons), 3);

select t_eq('והפונקציה מחזירה לו אותן עם שם המשימה',
  (select count(*)::int from event_price_addons('30000000-0000-0000-0000-00000000025a')), 3);

select t_eq('וסך התוספות הוא מה שנוסף לחשבון שלו',
  (select sum(amount) from event_price_addons('30000000-0000-0000-0000-00000000025a')),
  230::numeric);

-- המפתח בידו — ההענקה למעלה היא מפורשת — והכתיבה עדיין חסומה. זו בדיוק
-- הזרוע `user_kind = 'staff'` ב-`tpa_write`.
select t_eq('המפתח בידו', app.has('pricing.edit'), true);

select t_expect_fail('ובכל זאת אינו מוסיף תוספת', $$
  insert into task_price_addons (task_id, amount, note)
  values ('61000000-0000-0000-0000-000000025001', 999, 'ננסה בכל זאת')$$);

select t_rows('ואינו עורך תוספת קיימת', $$
  update task_price_addons set amount = 1 where amount = 250$$, 0);

select t_expect_fail('ואינו מסיר אחת', $$
  select remove_task_price_addon(
    (select id from task_price_addons where amount = 250))$$);

reset role;
select set_config('request.jwt.claim.sub', '', false);

-- ===== 4. הקבלן אינו צד לזה ================================================

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000025a3', false);

select t_eq('מנהל הקבלן אינו רואה תוספות מחיר כלל',
  (select count(*)::int from task_price_addons), 0);

reset role;
select set_config('request.jwt.claim.sub', '', false);

-- ===== 5. ההסרה ============================================================

\echo '--- תוספת מחיר: הסרה ---'

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000025a1', false);

select t_expect_ok('הרכז מסיר את ההנחה', $$
  select remove_task_price_addon(
    (select id from task_price_addons where amount = -100))$$);

select t_eq('והיא ירדה מהחשבון של האירוע',
  (select sum(amount) from event_price_addons('30000000-0000-0000-0000-00000000025a')),
  330::numeric);

select t_eq('ומהרשימה שהוא עצמו רואה',
  (select count(*)::int from task_price_addons), 2);

reset role;
select set_config('request.jwt.claim.sub', '', false);

-- מחיקה רכה: השורה עדיין שם, ומנהל מערכת רואה אותה
select t_eq('אבל השורה לא נמחקה — היא הוסרה',
  (select count(*)::int from task_price_addons where deleted_at is not null), 1);

select t_eq('וההסרה נרשמה ביומן',
  (select count(*)::int from event_activity
    where event_id = '30000000-0000-0000-0000-00000000025a'
      and kind = 'price_addon_removed'), 1);

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000025a4', false);

select t_eq('מנהל המערכת רואה גם את מה שהוסר',
  (select count(*)::int from task_price_addons), 3);

select t_expect_ok('והוא זה שיכול להחזיר אותה', $$
  select remove_task_price_addon(
    (select id from task_price_addons where deleted_at is not null), true)$$);

reset role;
select set_config('request.jwt.claim.sub', '', false);

select t_eq('והשחזור קיבל שורת יומן משלו',
  (select count(*)::int from event_activity
    where event_id = '30000000-0000-0000-0000-00000000025a'
      and kind = 'price_addon_added'), 4);

-- ===== 6. הגרסה אינה משתנה מתחת ל-RPC ======================================
-- ‏`remove_task_price_addon` הוא security definer, ולכן הוא זה שאוכף את
-- המפתח בעצמו — ולא הפוליסה, שאינה נשאלת בתוכו כלל.

select t_eq('ואינו קריא ל-anon',
  has_function_privilege('anon', 'remove_task_price_addon(uuid,boolean)', 'execute'), false);

select t_eq('וגם לא event_price_addons',
  has_function_privilege('anon', 'event_price_addons(uuid)', 'execute'), false);
