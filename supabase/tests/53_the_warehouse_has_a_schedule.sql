\pset tuples_only on
\pset format unaligned

-- ===========================================================================
-- 53: לו״ז מחסן (0196) — הכנה והחזרה לכל אירוע, ויוזר "מחסן" שרואה רק אותו.
--
-- החלון הוא current_date + 810, מעבר לכל טווח קודם.
-- ===========================================================================

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000053a1', 'c53-admin@vl.test'),
  ('00000000-0000-0000-0000-0000000053a2', 'c53-arco-manager@vl.test'),
  ('00000000-0000-0000-0000-0000000053a3', 'c53-arco-warehouse@vl.test'),
  ('00000000-0000-0000-0000-0000000053a4', 'c53-other-manager@vl.test'),
  ('00000000-0000-0000-0000-0000000053a5', 'c53-viewer@vl.test');

insert into customers (id, name, warehouse_schedule_enabled) values
  ('10000000-0000-0000-0000-00000000053a', 'ארקו 53', true),
  ('10000000-0000-0000-0000-00000000053b', 'לקוח רגיל 53', false);

insert into profiles (id, user_id, user_kind, is_admin, full_name) values
  ('20000000-0000-0000-0000-0000000053a1', '00000000-0000-0000-0000-0000000053a1',
   'staff', true, 'מנהל 53');
insert into profiles (id, user_id, user_kind, is_admin, full_name, customer_id) values
  ('20000000-0000-0000-0000-0000000053a2', '00000000-0000-0000-0000-0000000053a2',
   'customer_user', false, 'מנהל אצל ארקו 53', '10000000-0000-0000-0000-00000000053a'),
  ('20000000-0000-0000-0000-0000000053a3', '00000000-0000-0000-0000-0000000053a3',
   'customer_user', false, 'מחסן ארקו 53', '10000000-0000-0000-0000-00000000053a'),
  ('20000000-0000-0000-0000-0000000053a4', '00000000-0000-0000-0000-0000000053a4',
   'customer_user', false, 'מנהל אצל לקוח רגיל 53', '10000000-0000-0000-0000-00000000053b'),
  ('20000000-0000-0000-0000-0000000053a5', '00000000-0000-0000-0000-0000000053a5',
   'customer_user', false, 'צופה אצל ארקו 53', '10000000-0000-0000-0000-00000000053a');

insert into profile_roles (profile_id, role_id)
select p, id from permission_roles r,
  unnest(array['20000000-0000-0000-0000-0000000053a2'::uuid,
               '20000000-0000-0000-0000-0000000053a4'::uuid]) p
where r.key = 'customer_manager';
insert into profile_roles (profile_id, role_id)
select '20000000-0000-0000-0000-0000000053a3', id from permission_roles where key = 'customer_warehouse';
insert into profile_roles (profile_id, role_id)
select '20000000-0000-0000-0000-0000000053a5', id from permission_roles where key = 'customer_viewer';

insert into events (id, customer_id, event_number, event_date, end_client_name, status_id) values
  ('30000000-0000-0000-0000-00000000053a', '10000000-0000-0000-0000-00000000053a',
   '53001', current_date + 810, 'קצה 53',
   (select id from statuses where entity = 'event' and code = 'pending' and deleted_at is null)),
  ('30000000-0000-0000-0000-00000000053b', '10000000-0000-0000-0000-00000000053b',
   '53002', current_date + 810, 'קצה אחר 53',
   (select id from statuses where entity = 'event' and code = 'pending' and deleted_at is null));

-- ההקמה יום לפני האירוע והפירוק יום אחריו — ההכנה וההחזרה נגזרות מהם.
update tasks set task_date = current_date + 809
 where event_id = '30000000-0000-0000-0000-00000000053a'
   and task_type_id = (select id from task_types where code = 'setup' limit 1);
update tasks set task_date = current_date + 811
 where event_id = '30000000-0000-0000-0000-00000000053a'
   and task_type_id = (select id from task_types where code = 'teardown' limit 1);

-- ===== 1. מי מחזיק מה =====================================================

\echo '--- המחסן רואה מחסן, ורק מחסן ---'
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000053a3', false);
select t_eq('לו״ז מחסן',            app.has('warehouse.view'), true);
select t_eq('ועריכתו',              app.has('warehouse.edit'), true);
select t_eq('ולא לו״ז עבודה',       app.has('board.view'), false);
select t_eq('ולא לוח שנה',          app.has('calendar.view'), false);
select t_eq('ולא אירועים',          app.has('events.view'), false);
select t_eq('ולא דשבורד',           app.has('dashboard.view'), false);
select t_eq('ולא משימות',           app.has('tasks.view'), false);
select t_eq('ואינו רואה את האירוע עצמו',
  (select count(*)::int from events where id = '30000000-0000-0000-0000-00000000053a'), 0);
reset role;
select set_config('request.jwt.claim.sub', '', false);

\echo '--- מנהל הלקוח רואה ועורך, הצופה רואה ---'
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000053a2', false);
select t_eq('מנהל ארקו — צפייה', app.has('warehouse.view'), true);
select t_eq('מנהל ארקו — עריכה', app.has('warehouse.edit'), true);
select t_eq('ומחזיק עדיין את האירועים שלו', app.has('events.view'), true);
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000053a5', false);
select t_eq('צופה ארקו — צפייה', app.has('warehouse.view'), true);
select t_eq('צופה ארקו — בלי עריכה', app.has('warehouse.edit'), false);
reset role;
select set_config('request.jwt.claim.sub', '', false);

-- ===== 2. הלו״ז ===========================================================

\echo '--- שתי עמודות לכל אירוע, בתאריכים הנגזרים ---'
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000053a3', false);
select t_eq('הכנה והחזרה של האירוע של ארקו',
  (select string_agg(kind::text || '@' || (task_date - current_date)::text, ',' order by kind)
     from warehouse_schedule(current_date + 800, current_date + 820)),
  'prep@809,return@811');
select t_eq('עם מספר התעודה ושם הלקוח',
  (select event_number || '/' || end_client_name
     from warehouse_schedule(current_date + 800, current_date + 820) where kind = 'prep'),
  '53001/קצה 53');
select t_eq('והאירוע של הלקוח האחר אינו שם',
  (select count(*)::int from warehouse_schedule(current_date + 800, current_date + 820)
    where event_id = '30000000-0000-0000-0000-00000000053b'), 0);
reset role;
select set_config('request.jwt.claim.sub', '', false);

\echo '--- לקוח שהמודול סגור לו אינו רואה דבר ---'
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000053a4', false);
select t_eq('מנהל אצל לקוח רגיל — לו״ז ריק',
  (select count(*)::int from warehouse_schedule(current_date + 800, current_date + 820)), 0);
select t_expect_fail('ואינו כותב לאירוע של ארקו', $$
  select warehouse_task_save('30000000-0000-0000-0000-00000000053a', 'prep', '{"notes":"x"}')$$);
select t_expect_fail('ולא לאירוע של עצמו', $$
  select warehouse_task_save('30000000-0000-0000-0000-00000000053b', 'prep', '{"notes":"x"}')$$);
reset role;
select set_config('request.jwt.claim.sub', '', false);

\echo '--- אדמין רואה את ארקו ---'
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000053a1', false);
select t_eq('שתי העמודות של ארקו',
  (select count(*)::int from warehouse_schedule(current_date + 800, current_date + 820)
    where event_id = '30000000-0000-0000-0000-00000000053a'), 2);
reset role;
select set_config('request.jwt.claim.sub', '', false);

-- ===== 3. הכתיבה ==========================================================

\echo '--- המחסן מעדכן ---'
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000053a3', false);
select t_expect_ok('שעה, זמן והערה', $$
  select warehouse_task_save('30000000-0000-0000-0000-00000000053a', 'prep',
    '{"start_time":"05:55","duration_hours":"2.5","notes":"  להביא כיסאות  "}')$$);
select t_expect_ok('ושלושת הסימונים', $$
  select warehouse_task_save('30000000-0000-0000-0000-00000000053a', 'prep',
    '{"final_approved":true,"event_ready":true,"checked":true}')$$);
select t_expect_ok('ויום משלו להחזרה', $$
  select warehouse_task_save('30000000-0000-0000-0000-00000000053a', 'return',
    jsonb_build_object('task_date', (current_date + 812)::text))$$);
select t_expect_fail('שדה שאינו קיים נדחה', $$
  select warehouse_task_save('30000000-0000-0000-0000-00000000053a', 'prep', '{"price":1}')$$);
select t_eq('העדכון נקרא בלו״ז',
  (select to_char(start_time, 'HH24:MI') || '|' || duration_hours::text || '|' || notes || '|'
          || final_approved::text || event_ready::text || checked::text
     from warehouse_schedule(current_date + 800, current_date + 820) where kind = 'prep'),
  '05:55|2.50|להביא כיסאות|truetruetrue');
select t_eq('וההחזרה זזה ליום שנקבע',
  (select (task_date - current_date)::text || '/' || date_is_manual::text
     from warehouse_schedule(current_date + 800, current_date + 820) where kind = 'return'),
  '812/true');
select t_eq('ורואה את השורות בטבלה עצמה',
  (select count(*)::int from warehouse_tasks where event_id = '30000000-0000-0000-0000-00000000053a'), 2);
select t_rows('אבל אינו כותב לטבלה ישירות',
  $$update warehouse_tasks set notes = 'y' where event_id = '30000000-0000-0000-0000-00000000053a'$$, 0);
reset role;
select set_config('request.jwt.claim.sub', '', false);

\echo '--- החזרה לתאריך הנגזר ---'
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000053a2', false);
select t_expect_ok('מנהל ארקו מנקה את היום', $$
  select warehouse_task_save('30000000-0000-0000-0000-00000000053a', 'return', '{"task_date":null}')$$);
select t_eq('וההחזרה חוזרת ליום הפירוק',
  (select (task_date - current_date)::text || '/' || date_is_manual::text
     from warehouse_schedule(current_date + 800, current_date + 820) where kind = 'return'),
  '811/false');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000053a5', false);
select t_expect_fail('צופה אינו כותב', $$
  select warehouse_task_save('30000000-0000-0000-0000-00000000053a', 'prep', '{"notes":"x"}')$$);
reset role;
select set_config('request.jwt.claim.sub', '', false);

\echo '--- get_my_permissions מספר למסך שהמודול פתוח ---'
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000053a3', false);
select t_eq('הדגל על הלקוח',
  (get_my_permissions() -> 'customer' ->> 'warehouse_schedule_enabled')::boolean, true);
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000053a4', false);
select t_eq('וכבוי אצל הלקוח האחר',
  (get_my_permissions() -> 'customer' ->> 'warehouse_schedule_enabled')::boolean, false);
reset role;
select set_config('request.jwt.claim.sub', '', false);
