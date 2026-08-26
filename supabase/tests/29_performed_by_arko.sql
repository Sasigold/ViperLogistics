\pset tuples_only on
\pset format unaligned

-- ===========================================================================
-- 29: "בוצע ע"י" — משימת ארקו מוסתרת מוייפר ומחירה 0 (0120).
--
-- החלון הוא current_date + 450, מעבר ל-440 של 28.
-- ===========================================================================

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000029a1', 'c29-admin@vl.test'),
  ('00000000-0000-0000-0000-0000000029a2', 'c29-office@vl.test'),
  ('00000000-0000-0000-0000-0000000029a3', 'c29-cust@vl.test');

-- לקוח שהאפשרות מופעלת אצלו (כמו ארקו), במצב תמחור אוטומטי
insert into customers (id, name, pricing_mode, performed_by_enabled) values
  ('10000000-0000-0000-0000-00000000029a', 'ארקו 29', 'auto', true);

insert into profiles (id, user_id, user_kind, is_admin, full_name) values
  ('20000000-0000-0000-0000-0000000029a1', '00000000-0000-0000-0000-0000000029a1',
   'staff', true, 'מנהל 29'),
  ('20000000-0000-0000-0000-0000000029a2', '00000000-0000-0000-0000-0000000029a2',
   'staff', false, 'רכז משרד 29');
insert into profiles (id, user_id, user_kind, is_admin, full_name, customer_id) values
  ('20000000-0000-0000-0000-0000000029a3', '00000000-0000-0000-0000-0000000029a3',
   'customer_user', false, 'משתמש ארקו 29', '10000000-0000-0000-0000-00000000029a');

-- הרכז רואה משימות טיוטה רק אם הוא יכול לתכנן (tasks.edit → can_plan_tasks).
insert into user_permission_grants (profile_id, permission_key, allowed) values
  ('20000000-0000-0000-0000-0000000029a2', 'tasks.view', true),
  ('20000000-0000-0000-0000-0000000029a2', 'tasks.edit', true),
  ('20000000-0000-0000-0000-0000000029a2', 'events.view', true);

-- מחשבון מינימלי: 100 ₪ לשעה לעובד. 2×3×100 = 600.
insert into customer_pricing_rules (customer_id, task_type_id, config, is_active)
values ('10000000-0000-0000-0000-00000000029a',
        (select id from task_types where code = 'setup' limit 1),
        '{"model":"worker_hours","hour_rate":100,
          "hours":[{"id":"base","kind":"input","input":"hours_count","multiplier":1}],
          "workers":{"input":"worker_count"}}'::jsonb, true);

insert into events (id, customer_id, event_number, event_date, end_client_name, status_id)
values ('30000000-0000-0000-0000-00000000029a', '10000000-0000-0000-0000-00000000029a',
        'EV-29', current_date + 450, 'לקוח קצה 29',
        (select id from statuses where entity = 'event' and code = 'planned' and deleted_at is null));

-- מורידים את משימות ברירת המחדל שהטריגר יצר, ומזריעים שתי משימות משלנו.
update tasks set deleted_at = now() where event_id = '30000000-0000-0000-0000-00000000029a';

insert into tasks (id, event_id, customer_id, task_type_id, task_date,
                   onsite_start_time, hours_count, worker_count, status_id)
values
  ('61000000-0000-0000-0000-000000029001', '30000000-0000-0000-0000-00000000029a',
   '10000000-0000-0000-0000-00000000029a',
   (select id from task_types where code = 'setup' limit 1), current_date + 450,
   '09:00', 3, 2,
   (select id from statuses where entity = 'task' and code = 'draft' and deleted_at is null)),
  ('61000000-0000-0000-0000-000000029002', '30000000-0000-0000-0000-00000000029a',
   '10000000-0000-0000-0000-00000000029a',
   (select id from task_types where code = 'teardown' limit 1), current_date + 450,
   '18:00', 3, 2,
   (select id from statuses where entity = 'task' and code = 'draft' and deleted_at is null));

\echo '--- ברירת מחדל וייפר, מחיר רגיל ---'

select t_eq('משימה חדשה נולדת viper',
  (select performed_by from tasks where id = '61000000-0000-0000-0000-000000029001'), 'viper');
select t_eq('ומחירה מחושב כרגיל',
  (select price from task_pricing where task_id = '61000000-0000-0000-0000-000000029001'), 600::numeric);

\echo '--- הפיכת המשימה לארקו: מחיר 0 ---'
update tasks set performed_by = 'arko' where id = '61000000-0000-0000-0000-000000029001';

select t_eq('משימת ארקו — המחיר 0',
  (select price from task_pricing where task_id = '61000000-0000-0000-0000-000000029001'), 0::numeric);
select t_eq('והסיבה נרשמת בפירוט',
  (select breakdown ->> 'reason' from task_pricing where task_id = '61000000-0000-0000-0000-000000029001'),
  'performed_by_arko');

\echo '--- הסתרה מרכז המשרד (staff לא-admin) ---'
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000029a2', false);

select t_eq('הרכז אינו רואה את משימת ארקו',
  (select count(*)::int from tasks where id = '61000000-0000-0000-0000-000000029001'), 0);
select t_eq('אבל כן את משימת וייפר',
  (select count(*)::int from tasks where id = '61000000-0000-0000-0000-000000029002'), 1);
select t_eq('והאירוע גלוי כל עוד יש בו משימת וייפר',
  (select count(*)::int from events where id = '30000000-0000-0000-0000-00000000029a'), 1);

reset role;
select set_config('request.jwt.claim.sub', '', false);

\echo '--- כשכל המשימות ארקו — האירוע נעלם מוייפר ---'
update tasks set performed_by = 'arko' where id = '61000000-0000-0000-0000-000000029002';

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000029a2', false);
select t_eq('הרכז אינו רואה אירוע שכולו ארקו',
  (select count(*)::int from events where id = '30000000-0000-0000-0000-00000000029a'), 0);

reset role;
select set_config('request.jwt.claim.sub', '', false);

\echo '--- לקוח ארקו רואה הכול ---'
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000029a3', false);
select t_eq('הלקוח רואה את שתי משימותיו',
  (select count(*)::int from tasks where event_id = '30000000-0000-0000-0000-00000000029a'
     and deleted_at is null), 2);
select t_eq('והלקוח רואה את האירוע',
  (select count(*)::int from events where id = '30000000-0000-0000-0000-00000000029a'), 1);

reset role;
select set_config('request.jwt.claim.sub', '', false);

\echo '--- חזרה לוייפר מחזירה מחיר ---'
update tasks set performed_by = 'viper' where id = '61000000-0000-0000-0000-000000029001';
select t_eq('משימה שחזרה לוייפר מתומחרת שוב',
  (select price from task_pricing where task_id = '61000000-0000-0000-0000-000000029001'), 600::numeric);

\echo '--- הרשאת ה-RPC ---'
-- admin רשאי
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000029a1', false);
select t_expect_ok('admin קובע ביצוע ע"י',
  $$select set_task_performed_by('61000000-0000-0000-0000-000000029001', 'arko')$$);
reset role;
select set_config('request.jwt.claim.sub', '', false);

-- לקוח ארקו רשאי על המשימה שלו
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000029a3', false);
select t_expect_ok('לקוח ארקו קובע על משימתו',
  $$select set_task_performed_by('61000000-0000-0000-0000-000000029002', 'viper')$$);
select t_expect_fail('אך ערך לא חוקי נדחה',
  $$select set_task_performed_by('61000000-0000-0000-0000-000000029002', 'someone')$$);
reset role;
select set_config('request.jwt.claim.sub', '', false);
