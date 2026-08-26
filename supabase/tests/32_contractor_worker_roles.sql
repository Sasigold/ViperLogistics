\pset tuples_only on
\pset format unaligned

-- ===========================================================================
-- 32: עובד קבלן כראש צוות/נהג, והקבלן משבץ לפי התפקיד (0121).
--
-- החלון הוא current_date + 480.
-- ===========================================================================

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000032a1', 'c32-admin@vl.test'),
  ('00000000-0000-0000-0000-0000000032a4', 'c32-ctrmgr@vl.test');

insert into customers (id, name) values
  ('10000000-0000-0000-0000-00000000032a', 'לקוח 32');
insert into contractors (id, name) values
  ('c0000000-0000-0000-0000-00000000032a', 'קבלן 32');

insert into profiles (id, user_id, user_kind, is_admin, full_name, contractor_id) values
  ('20000000-0000-0000-0000-0000000032a1', '00000000-0000-0000-0000-0000000032a1', 'staff', true, 'מנהל 32', null),
  ('20000000-0000-0000-0000-0000000032a4', '00000000-0000-0000-0000-0000000032a4', 'contractor_user', false, 'מנהל קבלן 32',
   'c0000000-0000-0000-0000-00000000032a');

-- שלושה עובדי קבלן: A ראש צוות+נהג, B ראש צוות, C ללא תפקיד
insert into contractor_workers (id, contractor_id, full_name) values
  ('ca000000-0000-0000-0000-0000003200a1', 'c0000000-0000-0000-0000-00000000032a', 'עובד A 32'),
  ('cb000000-0000-0000-0000-0000003200b1', 'c0000000-0000-0000-0000-00000000032a', 'עובד B 32'),
  ('cc000000-0000-0000-0000-0000003200c1', 'c0000000-0000-0000-0000-00000000032a', 'עובד C 32');
-- מנהל הקבלן רואה את המשימות שהואצלו לו (portal.view) ומשבץ את סגלו.
insert into user_permission_grants (profile_id, permission_key, allowed) values
  ('20000000-0000-0000-0000-0000000032a4', 'portal.view', true),
  ('20000000-0000-0000-0000-0000000032a4', 'portal.assign_workers', true);

insert into contractor_worker_roles (contractor_worker_id, role) values
  ('ca000000-0000-0000-0000-0000003200a1', 'team_lead'),
  ('ca000000-0000-0000-0000-0000003200a1', 'driver'),
  ('cb000000-0000-0000-0000-0000003200b1', 'team_lead');

insert into events (id, customer_id, event_number, event_date, end_client_name, status_id)
values ('30000000-0000-0000-0000-00000000032a', '10000000-0000-0000-0000-00000000032a',
        'EV-32', current_date + 480, 'קצה 32',
        (select id from statuses where entity = 'event' and code = 'planned' and deleted_at is null));

-- מאצילים את משימת ההקמה לקבלן.
insert into task_contractor_terms (task_id, contractor_id, price, work_site)
select t.id, 'c0000000-0000-0000-0000-00000000032a', 0, 'field'
  from tasks t where t.event_id = '30000000-0000-0000-0000-00000000032a'
   and t.task_type_id = (select id from task_types where code = 'setup' limit 1)
   and t.deleted_at is null limit 1;

\echo '--- שיבוץ לפי תפקיד ---'
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000032a4', false);

-- עובד C אינו מוגדר ראש צוות — נדחה
select t_expect_fail('עובד ללא תפקיד אינו משובץ כראש צוות',
  $$select contractor_assign_worker(
      (select t.id from tasks t where t.event_id = '30000000-0000-0000-0000-00000000032a'
         and t.task_type_id = (select id from task_types where code='setup' limit 1)
         and t.deleted_at is null limit 1),
      'cc000000-0000-0000-0000-0000003200c1', null, true, null, 'team_lead')$$);

-- עובד A מוגדר ראש צוות — מתקבל
select t_expect_ok('עובד מוגדר משובץ כראש צוות',
  $$select contractor_assign_worker(
      (select t.id from tasks t where t.event_id = '30000000-0000-0000-0000-00000000032a'
         and t.task_type_id = (select id from task_types where code='setup' limit 1)
         and t.deleted_at is null limit 1),
      'ca000000-0000-0000-0000-0000003200a1', null, true, null, 'team_lead')$$);

-- עובד B מוגדר ראש צוות אך כבר יש ראש צוות אחד לקבלן על המשימה — נדחה
select t_expect_fail('ראש צוות שני לקבלן על אותה משימה נדחה',
  $$select contractor_assign_worker(
      (select t.id from tasks t where t.event_id = '30000000-0000-0000-0000-00000000032a'
         and t.task_type_id = (select id from task_types where code='setup' limit 1)
         and t.deleted_at is null limit 1),
      'cb000000-0000-0000-0000-0000003200b1', null, true, null, 'team_lead')$$);

-- עובד C כעובד רגיל (בלי תפקיד) — מתקבל
select t_expect_ok('עובד רגיל (בלי תפקיד) משובץ',
  $$select contractor_assign_worker(
      (select t.id from tasks t where t.event_id = '30000000-0000-0000-0000-00000000032a'
         and t.task_type_id = (select id from task_types where code='setup' limit 1)
         and t.deleted_at is null limit 1),
      'cc000000-0000-0000-0000-0000003200c1', null, true, null, null)$$);

reset role;
select set_config('request.jwt.claim.sub', '', false);

\echo '--- מצב סופי ---'
select t_eq('עובד A רשום כראש צוות על המשימה',
  (select role::text from task_contractor_workers
     where contractor_worker_id = 'ca000000-0000-0000-0000-0000003200a1'), 'team_lead');
select t_eq('עובד C רשום בלי תפקיד',
  (select role from task_contractor_workers
     where contractor_worker_id = 'cc000000-0000-0000-0000-0000003200c1'), null);

\echo '--- הסגל הניתן לשיבוץ נושא את התפקידים ---'
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000032a4', false);
select t_eq('עובד A מוצע עם תפקיד ראש צוות',
  (select (x -> 'roles') @> '"team_lead"'::jsonb
     from jsonb_array_elements(contractor_assignable_workers()) x
    where x ->> 'worker_id' = 'ca000000-0000-0000-0000-0000003200a1'), true);
select t_eq('ועובד C בלי תפקידים',
  (select (x -> 'roles')
     from jsonb_array_elements(contractor_assignable_workers()) x
    where x ->> 'worker_id' = 'cc000000-0000-0000-0000-0000003200c1'), '[]'::jsonb);
reset role;
select set_config('request.jwt.claim.sub', '', false);
