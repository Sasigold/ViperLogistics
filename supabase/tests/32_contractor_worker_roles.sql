\pset tuples_only on
\pset format unaligned

-- ===========================================================================
-- 32: עובד קבלן כראש צוות/נהג, והקבלן משבץ לפי התפקיד (0121),
--     המכסה סופרת שורה פעם אחת (0127), וראש הצוות אחד למשימה (0128).
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

\echo '--- 0127: מכסת עובד אחד, ושינוי תפקיד על אותו עובד ---'
-- משימת הפירוק מואצלת לאותו קבלן עם מכסה של עובד אחד. זה בדיוק המקרה של
-- הדיווח: הקבלן מביא עובד יחיד, ואז מסמן אותו ראש צוות.
insert into task_contractor_terms (task_id, contractor_id, price, work_site, contractor_worker_count)
select t.id, 'c0000000-0000-0000-0000-00000000032a', 0, 'field', 1
  from tasks t where t.event_id = '30000000-0000-0000-0000-00000000032a'
   and t.task_type_id = (select id from task_types where code = 'teardown' limit 1)
   and t.deleted_at is null limit 1;

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000032a4', false);

select t_expect_ok('העובד היחיד משובץ', $$
  select contractor_assign_worker(
      (select t.id from tasks t where t.event_id = '30000000-0000-0000-0000-00000000032a'
         and t.task_type_id = (select id from task_types where code='teardown' limit 1)
         and t.deleted_at is null limit 1),
      'ca000000-0000-0000-0000-0000003200a1', null, true, null, null)$$);

-- לפני 0127 השורה הזו נפלה על "חריגה מכמות העובדים שהקבלן אמור להביא (1)":
-- ‏on conflict do update מפעיל טריגר before insert, והספירה כללה את השורה
-- שעמדה להתעדכן.
select t_expect_ok('ואותו עובד מסומן ראש צוות בלי חריגה (0127)', $$
  select contractor_assign_worker(
      (select t.id from tasks t where t.event_id = '30000000-0000-0000-0000-00000000032a'
         and t.task_type_id = (select id from task_types where code='teardown' limit 1)
         and t.deleted_at is null limit 1),
      'ca000000-0000-0000-0000-0000003200a1', null, true, null, 'team_lead')$$);

-- והמכסה עצמה עדיין נאכפת: עובד *נוסף* על אותה משימה נדחה.
select t_expect_fail('אך עובד נוסף מעל המכסה עדיין נדחה', $$
  select contractor_assign_worker(
      (select t.id from tasks t where t.event_id = '30000000-0000-0000-0000-00000000032a'
         and t.task_type_id = (select id from task_types where code='teardown' limit 1)
         and t.deleted_at is null limit 1),
      'cc000000-0000-0000-0000-0000003200c1', null, true, null, null)$$);

reset role;
select set_config('request.jwt.claim.sub', '', false);

select t_eq('העובד היחיד רשום כראש צוות על הפירוק',
  (select tcw.role::text from task_contractor_workers tcw
     join tasks t on t.id = tcw.task_id
    where t.event_id = '30000000-0000-0000-0000-00000000032a'
      and t.task_type_id = (select id from task_types where code='teardown' limit 1)
      and tcw.contractor_worker_id = 'ca000000-0000-0000-0000-0000003200a1'), 'team_lead');

\echo '--- 0128: ראש צוות פנימי חוסם ראש צוות של קבלן ---'
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000032a5', 'c32-lead@vl.test');
insert into profiles (id, user_id, user_kind, is_admin, full_name) values
  ('20000000-0000-0000-0000-0000000032a5', '00000000-0000-0000-0000-0000000032a5', 'staff', false, 'ראש צוות פנימי 32');

-- משימה שלישית, מואצלת לקבלן, ועליה כבר יושב ראש צוות פנימי.
insert into tasks (id, event_id, customer_id, task_type_id, task_date, worker_count, status_id)
select '61000000-0000-0000-0000-000000032003', '30000000-0000-0000-0000-00000000032a',
       '10000000-0000-0000-0000-00000000032a', tt.id, current_date + 480, 4,
       (select id from statuses where entity = 'task' and code = 'draft' and deleted_at is null)
  from task_types tt where tt.name = 'סידור' limit 1;

insert into task_contractor_terms (task_id, contractor_id, price, work_site)
values ('61000000-0000-0000-0000-000000032003', 'c0000000-0000-0000-0000-00000000032a', 0, 'field');

insert into task_assignments (task_id, profile_id, role) values
  ('61000000-0000-0000-0000-000000032003', '20000000-0000-0000-0000-0000000032a5', 'team_lead');

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000032a4', false);
select t_expect_fail('הקבלן אינו מגדיר ראש צוות כשיש כבר אחד פנימי (0128)', $$
  select contractor_assign_worker('61000000-0000-0000-0000-000000032003',
      'ca000000-0000-0000-0000-0000003200a1', null, true, null, 'team_lead')$$);
select t_expect_ok('אך כעובד רגיל הוא כן משובץ', $$
  select contractor_assign_worker('61000000-0000-0000-0000-000000032003',
      'ca000000-0000-0000-0000-0000003200a1', null, true, null, null)$$);
reset role;
select set_config('request.jwt.claim.sub', '', false);

\echo '--- 0128: הלו״ז מציג את ראש הצוות של הקבלן בשורה שלו ---'
select t_eq('ראש הצוות של הקבלן הוא זה שבשורת ראש הצוות',
  (select team_lead_name from work_board_view w
     join tasks t on t.id = w.id
    where t.event_id = '30000000-0000-0000-0000-00000000032a'
      and t.task_type_id = (select id from task_types where code='teardown' limit 1)),
  'עובד A 32');
select t_eq('והמקור מסומן ככזה של קבלן',
  (select team_lead_kind from work_board_view w
     join tasks t on t.id = w.id
    where t.event_id = '30000000-0000-0000-0000-00000000032a'
      and t.task_type_id = (select id from task_types where code='teardown' limit 1)),
  'contractor');
select t_eq('ושיבוץ פנימי גובר עליו',
  (select team_lead_kind from work_board_view
    where id = '61000000-0000-0000-0000-000000032003'), 'staff');

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
