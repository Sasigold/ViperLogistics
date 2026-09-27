\pset tuples_only on
\pset format unaligned

-- ===========================================================================
-- ‏56: הצוות במשימה הוא אנשים — פעם אחת כל אחד, וכולם (0201).
--
-- החבילה מקימה לקוח, קבלן, אירוע, שני אנשי צוות, שני עובדי קבלן, עובד לקוח
-- ומשימה אחת משלה ב-`current_date + 870`, מעבר לכל טווח אחר. היא משאירה
-- אחריה משימה ושיבוצים שאינם מנוקים.
--
-- על המשימה: "איציק 56" משובץ גם כעובד וגם כנהג, "שותף 56" כעובד, ראש צוות
-- ועובד מהקבלן, ועובד אחד של הלקוח. חמישה אנשים, שש שורות שיבוץ.
--
--   * ‏**המשמרת** (`shift_task_breakdown`) — איציק מופיע בצוות פעם אחת,
--     "משובצים" הם חמישה, ועובדי הקבלן והלקוח בפנים ומסומנים.
--   * ‏**הלו״ז** (`work_board_view`) — עובד שטח, בלי `contractors.view` ובלי
--     `customers.view`, רואה את שמות עובדי הקבלן והלקוח ואת ראש הצוות של הקבלן.
--   * ‏**ולא יותר** — הטבלאות עצמן, עם הטלפון ות״ז, נשארות סגורות לו, ומה
--     שהלקוח לא ראה עד היום (את עובדי הקבלן) הוא לא רואה גם עכשיו.
-- ===========================================================================

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000056a1', 'c56-itzik@vl.test'),
  ('00000000-0000-0000-0000-0000000056a2', 'c56-partner@vl.test'),
  ('00000000-0000-0000-0000-0000000056a3', 'c56-customer@vl.test');

insert into customers (id, name) values
  ('10000000-0000-0000-0000-00000000056a', 'לקוח 56');

insert into contractors (id, name) values
  ('40000000-0000-0000-0000-00000000056a', 'קבלן 56');

insert into contractor_workers (id, contractor_id, full_name, phone, id_number) values
  ('50000000-0000-0000-0000-0000000056a1', '40000000-0000-0000-0000-00000000056a',
   'ראש צוות קבלן 56', '050-5600001', '056000001'),
  ('50000000-0000-0000-0000-0000000056a2', '40000000-0000-0000-0000-00000000056a',
   'עובד קבלן 56', '050-5600002', '056000002');

insert into customer_workers (id, customer_id, full_name) values
  ('cf000000-0000-0000-0000-0000005600a1', '10000000-0000-0000-0000-00000000056a', 'עובד לקוח 56');

insert into profiles (id, user_id, user_kind, is_admin, full_name) values
  ('20000000-0000-0000-0000-0000000056a1', '00000000-0000-0000-0000-0000000056a1', 'staff', false, 'איציק 56'),
  ('20000000-0000-0000-0000-0000000056a2', '00000000-0000-0000-0000-0000000056a2', 'staff', false, 'שותף 56');

insert into profiles (id, user_id, user_kind, is_admin, full_name, customer_id) values
  ('20000000-0000-0000-0000-0000000056a3', '00000000-0000-0000-0000-0000000056a3',
   'customer_user', false, 'הלקוח 56', '10000000-0000-0000-0000-00000000056a');

-- שניהם בתפקיד "עובד" — העובד הכללי של 0079, בלי מודול הקבלנים ובלי הלקוחות.
insert into profile_roles (profile_id, role_id)
select p, r.id
  from unnest(array['20000000-0000-0000-0000-0000000056a1'::uuid,
                    '20000000-0000-0000-0000-0000000056a2'::uuid]) p,
       permission_roles r
 where r.key = 'worker';

insert into events (id, customer_id, event_number, event_date, status_id)
values ('30000000-0000-0000-0000-00000000056a', '10000000-0000-0000-0000-00000000056a',
        'EV-56', current_date + 870,
        (select id from statuses where entity = 'event' and code = 'pending' and deleted_at is null));

insert into tasks (id, event_id, customer_id, task_type_id, task_date,
                   warehouse_start_time, onsite_start_time, hours_count,
                   status_id, worker_count)
values ('62000000-0000-0000-0000-000000056001', '30000000-0000-0000-0000-00000000056a',
        '10000000-0000-0000-0000-00000000056a',
        (select id from task_types where code = 'setup' limit 1),
        current_date + 870, '11:00', '12:00', 1.0,
        (select id from statuses where entity = 'task' and code = 'assigned' and deleted_at is null),
        5);

-- איציק: עובד מהמחסן, וגם הנהג — שתי שורות, אדם אחד.
insert into task_assignments (task_id, profile_id, role, work_site) values
  ('62000000-0000-0000-0000-000000056001', '20000000-0000-0000-0000-0000000056a1', 'worker', 'warehouse'),
  ('62000000-0000-0000-0000-000000056001', '20000000-0000-0000-0000-0000000056a1', 'driver', 'field'),
  ('62000000-0000-0000-0000-000000056001', '20000000-0000-0000-0000-0000000056a2', 'worker', 'field');

insert into task_contractor_terms (task_id, contractor_id, price)
values ('62000000-0000-0000-0000-000000056001', '40000000-0000-0000-0000-00000000056a', 800);

insert into task_contractor_workers (task_id, contractor_worker_id, role, work_site) values
  ('62000000-0000-0000-0000-000000056001', '50000000-0000-0000-0000-0000000056a1', 'team_lead', 'field'),
  ('62000000-0000-0000-0000-000000056001', '50000000-0000-0000-0000-0000000056a2', 'worker', 'field');

insert into task_customer_workers (task_id, customer_worker_id, work_site)
values ('62000000-0000-0000-0000-000000056001', 'cf000000-0000-0000-0000-0000005600a1', 'field');

-- ===== 1. המשמרת: אדם אחד, פעם אחת ========================================

\echo '--- המשמרת של איציק: הצוות הוא אנשים ---'
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000056a1', false);

create temp table s56 as
select shift_task_breakdown('20000000-0000-0000-0000-0000000056a1',
                            array['62000000-0000-0000-0000-000000056001'::uuid]) -> 'tasks' -> 0 as t;

select t_eq('העובד מחזיק את board.view_staffing, ולכן רואה צוות',
  app.has('board.view_staffing'), true);

select t_eq('איציק מופיע בצוות פעם אחת, אף שהוא עובד וגם נהג',
  (select count(*)::int from s56, jsonb_array_elements(t -> 'team') m
    where m ->> 'name' = 'איציק 56'), 1);

select t_eq('ומתחיל במחסן — אחת השורות שלו יוצאת משם',
  (select m ->> 'work_site' from s56, jsonb_array_elements(t -> 'team') m
    where m ->> 'name' = 'איציק 56'), 'warehouse');

select t_eq('משובצים: חמישה אנשים, ולא שש שורות',
  (select (t ->> 'assigned_count')::int from s56), 5);

select t_eq('והצוות מונה את אותם חמישה',
  (select jsonb_array_length(t -> 'team') from s56), 5);

select t_eq('שני עובדי הקבלן בצוות, ומסומנים כקבלן',
  (select count(*)::int from s56, jsonb_array_elements(t -> 'team') m
    where m ->> 'kind' = 'contractor'
      and m ->> 'name' in ('ראש צוות קבלן 56', 'עובד קבלן 56')), 2);

select t_eq('ועובד הלקוח בצוות, ומסומן כלקוח',
  (select count(*)::int from s56, jsonb_array_elements(t -> 'team') m
    where m ->> 'kind' = 'customer' and m ->> 'name' = 'עובד לקוח 56'), 1);

select t_eq('לכל אדם מפתח משלו',
  (select count(distinct m ->> 'key')::int from s56, jsonb_array_elements(t -> 'team') m), 5);

select t_eq('התפקידים של איציק נשארים שניים — נהג ועובד',
  (select t -> 'my_role' from s56), '["driver", "worker"]'::jsonb);

drop table s56;

reset role;
select set_config('request.jwt.claim.sub', '', false);

-- ===== 2. הלו״ז: עובד השטח רואה את עובדי הקבלן ============================

\echo '--- הלו״ז של שותף 56: הקבלן והלקוח בצוות ---'
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000056a2', false);

select t_eq('העובד אינו מחזיק את מודול הקבלנים', app.has('contractors.view'), false);
select t_eq('ולא את מודול הלקוחות',             app.has('customers.view'), false);

select t_eq('הוא רואה את שני עובדי הקבלן בשמם',
  (select string_agg(w ->> 'name', ',' order by w ->> 'name')
     from work_board_view v, jsonb_array_elements(v.contractor_worker_list) w
    where v.id = '62000000-0000-0000-0000-000000056001'),
  'עובד קבלן 56,ראש צוות קבלן 56');

select t_eq('ואת ראש הצוות של הקבלן בתא של ראש הצוות',
  (select team_lead_name || '/' || team_lead_kind from work_board_view
    where id = '62000000-0000-0000-0000-000000056001'),
  'ראש צוות קבלן 56/contractor');

select t_eq('ואת עובד הלקוח',
  (select string_agg(w ->> 'name', ',')
     from work_board_view v, jsonb_array_elements(v.customer_worker_list) w
    where v.id = '62000000-0000-0000-0000-000000056001'),
  'עובד לקוח 56');

-- הזהות ולא השורה: הטלפון ות״ז של עובד הקבלן נשארים מאחורי המודול.
select t_eq('טבלת עובדי הקבלן עצמה נשארת סגורה לו',
  (select count(*)::int from contractor_workers
    where contractor_id = '40000000-0000-0000-0000-00000000056a'), 0);
select t_eq('וכך גם טבלת עובדי הלקוח',
  (select count(*)::int from customer_workers
    where customer_id = '10000000-0000-0000-0000-00000000056a'), 0);

reset role;
select set_config('request.jwt.claim.sub', '', false);

-- ===== 3. מה שהלקוח לא ראה, הוא לא רואה גם עכשיו ==========================

\echo '--- הלקוח: הסגל שלו כן, עובדי הקבלן לא ---'
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000056a3', false);

select t_eq('הלקוח רואה את המשימה בלו״ז',
  (select count(*)::int from work_board_view where id = '62000000-0000-0000-0000-000000056001'), 1);

select t_eq('אך לא את עובדי הקבלן',
  (select contractor_worker_list from work_board_view
    where id = '62000000-0000-0000-0000-000000056001'), null::jsonb);

select t_eq('ולא את ראש הצוות של הקבלן',
  (select team_lead_name from work_board_view
    where id = '62000000-0000-0000-0000-000000056001'), null::text);

reset role;
select set_config('request.jwt.claim.sub', '', false);
