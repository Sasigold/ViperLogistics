\pset tuples_only on
\pset format unaligned

-- ===========================================================================
-- ‏67: לוח השנה עונה בזמן (0217).
--
-- ‏`app.on_event_as_staff` נכתבה מחדש כך שהשאלה "רשאי לתכנן" נשאלת רק כשיש
-- שיבוץ לטיוטה. הבדיקות כאן מוודאות שהתשובה לא השתנתה, ושעובד עם ההיקף
-- "רק מה שמשויך אליי" רואה בלוח השנה (טבלת events דרך RLS) רק את האירועים
-- ששובץ אליהם במשימה שפורסמה.
--
--   67a1 עובד (תפקיד "עובד": ‏events.view + היקף own)
--   67a2 עובד שהוענק לו אישית tasks.edit (רשאי לתכנן) — עדיין עם היקף own
--
-- אירועים: e1 — משימה שפורסמה, שניהם משובצים · e2 — רק טיוטה, שניהם משובצים ·
-- e3 — משימה שפורסמה, אף אחד מהם אינו משובץ.
-- ===========================================================================

insert into auth.users (id, email)
select ('00000000-0000-0000-0000-0000000067' || s)::uuid, 'p67-' || s || '@vl.test'
  from unnest(array['a1','a2']) s;

insert into customers (id, name) values
  ('10000000-0000-0000-0000-0000000067a0', 'לקוח 67');

insert into profiles (id, user_id, user_kind, is_admin, full_name) values
  ('20000000-0000-0000-0000-0000000067a1', '00000000-0000-0000-0000-0000000067a1', 'staff', false, 'עובד 67'),
  ('20000000-0000-0000-0000-0000000067a2', '00000000-0000-0000-0000-0000000067a2', 'staff', false, 'עובד מתכנן 67');

insert into profile_roles (profile_id, role_id)
select p, (select id from permission_roles where key = 'worker' and deleted_at is null limit 1)
  from unnest(array['20000000-0000-0000-0000-0000000067a1',
                    '20000000-0000-0000-0000-0000000067a2']::uuid[]) p;

insert into user_permission_grants (profile_id, permission_key, allowed) values
  ('20000000-0000-0000-0000-0000000067a2', 'tasks.edit', true);

insert into events (id, customer_id, end_client_name, event_number, event_date) values
  ('30000000-0000-0000-0000-0000000067e1', '10000000-0000-0000-0000-0000000067a0', 'אירוע 1 67', 'EV-67-1', current_date + 1140),
  ('30000000-0000-0000-0000-0000000067e2', '10000000-0000-0000-0000-0000000067a0', 'אירוע 2 67', 'EV-67-2', current_date + 1141),
  ('30000000-0000-0000-0000-0000000067e3', '10000000-0000-0000-0000-0000000067a0', 'אירוע 3 67', 'EV-67-3', current_date + 1142);

insert into tasks (id, event_id, customer_id, task_type_id, task_date, onsite_start_time, hours_count, status_id, worker_count)
select v.id::uuid, v.ev::uuid, '10000000-0000-0000-0000-0000000067a0',
       (select id from task_types where code = 'setup' limit 1),
       current_date + v.d, '10:00', 2,
       (select id from statuses where entity = 'task' and code = v.st and deleted_at is null),
       2
  from (values
    ('62000000-0000-0000-0000-0000000067f1', '30000000-0000-0000-0000-0000000067e1', 1140, 'assigned'),
    ('62000000-0000-0000-0000-0000000067f2', '30000000-0000-0000-0000-0000000067e2', 1141, 'draft'),
    ('62000000-0000-0000-0000-0000000067f3', '30000000-0000-0000-0000-0000000067e3', 1142, 'assigned')
  ) v(id, ev, d, st);

insert into task_assignments (task_id, profile_id, role, work_site) values
  ('62000000-0000-0000-0000-0000000067f1', '20000000-0000-0000-0000-0000000067a1', 'worker', 'field'),
  ('62000000-0000-0000-0000-0000000067f2', '20000000-0000-0000-0000-0000000067a1', 'worker', 'field'),
  ('62000000-0000-0000-0000-0000000067f1', '20000000-0000-0000-0000-0000000067a2', 'worker', 'field'),
  ('62000000-0000-0000-0000-0000000067f2', '20000000-0000-0000-0000-0000000067a2', 'worker', 'field');

create or replace function t67_as(p text) returns void language sql as $$
  select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000067' || p, false);
$$;
grant execute on function t67_as(text) to authenticated;

-- מה שלוח השנה מקבל: אירועי 67 בטווח, כפי ש-RLS מחזירה אותם לקורא
create or replace function t67_calendar() returns text language sql stable as $$
  select coalesce(string_agg(event_number, ',' order by event_number), '-')
    from events
   where event_number like 'EV-67-%'
     and event_date between current_date + 1140 and current_date + 1142
     and deleted_at is null
$$;
grant execute on function t67_calendar() to authenticated;

-- ===== 1. עובד: רק מה ששובץ אליו ופורסם ===================================

\echo '--- 1. עובד: רק מה ששובץ אליו ופורסם ---'
set role authenticated;

select t67_as('a1');
select t_eq('עובד: ההיקף שלו הוא "רק מה שמשויך אליי"', app.scope_own('events'), true);
select t_eq('משובץ למשימה שפורסמה — האירוע שלו',
  app.on_event_as_staff('30000000-0000-0000-0000-0000000067e1'), true);
select t_eq('משובץ רק לטיוטה — עוד לא',
  app.on_event_as_staff('30000000-0000-0000-0000-0000000067e2'), false);
select t_eq('לא משובץ — לא',
  app.on_event_as_staff('30000000-0000-0000-0000-0000000067e3'), false);
select t_eq('לוח השנה של העובד: רק האירוע ששובץ אליו', t67_calendar(), 'EV-67-1');

-- ===== 2. רשאי לתכנן: גם הטיוטה שהוא משובץ אליה, ולא יותר ================

\echo '--- 2. רשאי לתכנן: גם הטיוטה שהוא משובץ אליה ---'
select t67_as('a2');
select t_eq('רשאי לתכנן', app.can_plan_tasks(), true);
select t_eq('משובץ לטיוטה — רואה אותה (0063 §4)',
  app.on_event_as_staff('30000000-0000-0000-0000-0000000067e2'), true);
select t_eq('לא משובץ — עדיין לא, גם כשהוא רשאי לתכנן',
  app.on_event_as_staff('30000000-0000-0000-0000-0000000067e3'), false);
select t_eq('לוח השנה שלו: שני האירועים שהוא משובץ אליהם, לא השלישי',
  t67_calendar(), 'EV-67-1,EV-67-2');

reset role;
