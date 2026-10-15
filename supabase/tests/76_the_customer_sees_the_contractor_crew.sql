\pset tuples_only on
\pset format unaligned

-- ===========================================================================
-- ‏76: הלקוח רואה בלו״ז גם את עובדי הקבלן (0234).
--
-- לקוח, קבלן עם ראש צוות ועובד, משימה אחת של הלקוח, ושלושה משתמשי לקוח:
-- מנהל עם `board.view_staffing`, צופה בלי המפתח, ומנהל של לקוח אחר עם המפתח.
-- התאריך ב-current_date + 1260, מעבר לכל טווח אחר; הסוויטה משאירה אחריה את
-- הנתונים שלה.
-- ===========================================================================

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000076a1', 'c76-manager@vl.test'),
  ('00000000-0000-0000-0000-0000000076a2', 'c76-viewer@vl.test'),
  ('00000000-0000-0000-0000-0000000076a3', 'c76-other@vl.test');

insert into customers (id, name) values
  ('10000000-0000-0000-0000-00000000076a', 'לקוח 76'),
  ('10000000-0000-0000-0000-00000000076b', 'לקוח אחר 76');

insert into contractors (id, name) values
  ('40000000-0000-0000-0000-00000000076a', 'קבלן 76');

insert into contractor_workers (id, contractor_id, full_name, phone, id_number) values
  ('50000000-0000-0000-0000-0000000076a1', '40000000-0000-0000-0000-00000000076a',
   'ראש צוות קבלן 76', '050-7600001', '076000001'),
  ('50000000-0000-0000-0000-0000000076a2', '40000000-0000-0000-0000-00000000076a',
   'עובד קבלן 76', '050-7600002', '076000002');

insert into profiles (id, user_id, user_kind, is_admin, full_name, customer_id) values
  ('20000000-0000-0000-0000-0000000076a1', '00000000-0000-0000-0000-0000000076a1',
   'customer_user', false, 'מנהל לקוח 76', '10000000-0000-0000-0000-00000000076a'),
  ('20000000-0000-0000-0000-0000000076a2', '00000000-0000-0000-0000-0000000076a2',
   'customer_user', false, 'צופה לקוח 76', '10000000-0000-0000-0000-00000000076a'),
  ('20000000-0000-0000-0000-0000000076a3', '00000000-0000-0000-0000-0000000076a3',
   'customer_user', false, 'מנהל לקוח אחר 76', '10000000-0000-0000-0000-00000000076b');

insert into user_permission_grants (profile_id, permission_key, allowed) values
  ('20000000-0000-0000-0000-0000000076a1', 'board.view_staffing', true),
  ('20000000-0000-0000-0000-0000000076a2', 'board.view_staffing', false),
  ('20000000-0000-0000-0000-0000000076a3', 'board.view_staffing', true);

insert into events (id, customer_id, event_number, event_date, status_id)
values ('30000000-0000-0000-0000-00000000076a', '10000000-0000-0000-0000-00000000076a',
        'EV-76', current_date + 1260,
        (select id from statuses where entity = 'event' and code = 'pending' and deleted_at is null));

insert into tasks (id, event_id, customer_id, task_type_id, task_date,
                   warehouse_start_time, onsite_start_time, hours_count,
                   status_id, worker_count)
values ('62000000-0000-0000-0000-000000076001', '30000000-0000-0000-0000-00000000076a',
        '10000000-0000-0000-0000-00000000076a',
        (select id from task_types where code = 'setup' limit 1),
        current_date + 1260, '11:00', '12:00', 1.0,
        (select id from statuses where entity = 'task' and code = 'assigned' and deleted_at is null),
        2);

insert into task_contractor_terms (task_id, contractor_id, price)
values ('62000000-0000-0000-0000-000000076001', '40000000-0000-0000-0000-00000000076a', 500);

insert into task_contractor_workers (task_id, contractor_worker_id, role, work_site) values
  ('62000000-0000-0000-0000-000000076001', '50000000-0000-0000-0000-0000000076a1', 'team_lead', 'field'),
  ('62000000-0000-0000-0000-000000076001', '50000000-0000-0000-0000-0000000076a2', 'worker', 'field');

-- ===== 1. מנהל הלקוח עם המפתח רואה את עובדי הקבלן ==========================

\echo '--- מנהל הלקוח: עובדי הקבלן בלו״ז ---'
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000076a1', false);

select t_eq('המנהל מחזיק את המפתח', app.has('board.view_staffing'), true);

select t_eq('הוא רואה את שני עובדי הקבלן בשמם',
  (select string_agg(w ->> 'name', ',' order by w ->> 'name')
     from work_board_view v, jsonb_array_elements(v.contractor_worker_list) w
    where v.id = '62000000-0000-0000-0000-000000076001'),
  'עובד קבלן 76,ראש צוות קבלן 76');

select t_eq('ואת ראש הצוות של הקבלן בתא של ראש הצוות',
  (select team_lead_name || '/' || team_lead_kind from work_board_view
    where id = '62000000-0000-0000-0000-000000076001'),
  'ראש צוות קבלן 76/contractor');

select t_eq('טבלת עובדי הקבלן עצמה (טלפון, ת״ז) נשארת סגורה לו',
  (select count(*)::int from contractor_workers
    where contractor_id = '40000000-0000-0000-0000-00000000076a'), 0);

reset role;
select set_config('request.jwt.claim.sub', '', false);

-- ===== 2. בלי המפתח — לא ==================================================

\echo '--- צופה בלי המפתח: לא ---'
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000076a2', false);

select t_eq('הצופה רואה את המשימה',
  (select count(*)::int from work_board_view where id = '62000000-0000-0000-0000-000000076001'), 1);
select t_eq('אך לא את עובדי הקבלן',
  (select contractor_worker_list from work_board_view
    where id = '62000000-0000-0000-0000-000000076001'), null::jsonb);
select t_eq('ולא שורות שיבוץ של הקבלן',
  (select count(*)::int from task_contractor_workers
    where task_id = '62000000-0000-0000-0000-000000076001'), 0);

reset role;
select set_config('request.jwt.claim.sub', '', false);

-- ===== 3. לקוח אחר — לא ===================================================

\echo '--- לקוח אחר עם המפתח: לא ---'
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000076a3', false);

select t_eq('שורות השיבוץ של משימה של לקוח אחר סגורות',
  (select count(*)::int from task_contractor_workers
    where task_id = '62000000-0000-0000-0000-000000076001'), 0);

reset role;
select set_config('request.jwt.claim.sub', '', false);
