\pset tuples_only on
\pset format unaligned

-- ===========================================================================
-- 30: תיעוד חופשי — למשרד וללקוח; לשטח רק רשומות מערכת (0122).
--
-- ראש צוות שטח וקבלן חולקים את אותו שער בדיוק: אין להם `events.edit`, ולכן
-- אין להם `events.activity_note_view`, ולכן הם רואים רק `kind <> 'note'`.
-- החלון הוא current_date + 460.
-- ===========================================================================

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000030a1', 'c30-admin@vl.test'),
  ('00000000-0000-0000-0000-0000000030a2', 'c30-office@vl.test'),
  ('00000000-0000-0000-0000-0000000030a3', 'c30-lead@vl.test'),
  ('00000000-0000-0000-0000-0000000030a5', 'c30-cust@vl.test');

insert into customers (id, name) values
  ('10000000-0000-0000-0000-00000000030a', 'לקוח 30');

insert into profiles (id, user_id, user_kind, is_admin, full_name) values
  ('20000000-0000-0000-0000-0000000030a1', '00000000-0000-0000-0000-0000000030a1', 'staff', true,  'מנהל 30'),
  ('20000000-0000-0000-0000-0000000030a2', '00000000-0000-0000-0000-0000000030a2', 'staff', false, 'רכז 30'),
  ('20000000-0000-0000-0000-0000000030a3', '00000000-0000-0000-0000-0000000030a3', 'staff', false, 'ראש צוות שטח 30');
insert into profiles (id, user_id, user_kind, is_admin, full_name, customer_id) values
  ('20000000-0000-0000-0000-0000000030a5', '00000000-0000-0000-0000-0000000030a5', 'customer_user', false, 'לקוח 30',
   '10000000-0000-0000-0000-00000000030a');
insert into staff_roles (profile_id, role) values
  ('20000000-0000-0000-0000-0000000030a3', 'team_lead');

-- הרכז מקבל events.edit במפורש (ומכאן activity_note_view בהיסק).
insert into user_permission_grants (profile_id, permission_key, allowed) values
  ('20000000-0000-0000-0000-0000000030a2', 'events.view', true),
  ('20000000-0000-0000-0000-0000000030a2', 'events.edit', true);

insert into events (id, customer_id, event_number, event_date, end_client_name, status_id)
values ('30000000-0000-0000-0000-00000000030a', '10000000-0000-0000-0000-00000000030a',
        'EV-30', current_date + 460, 'לקוח קצה 30',
        (select id from statuses where entity = 'event' and code = 'planned' and deleted_at is null));

-- ראש הצוות משובץ על משימת ההקמה, והמשימה מפורסמת (assigned) — רק אז
-- `is_event_team_lead` אמת עבורו (0082: ראש צוות "נספר" על משימה שפורסמה).
update tasks set status_id = (select id from statuses where entity='task' and code='assigned' and deleted_at is null)
  where event_id = '30000000-0000-0000-0000-00000000030a'
    and task_type_id = (select id from task_types where code = 'setup' limit 1)
    and deleted_at is null;
insert into task_assignments (task_id, profile_id, role)
select t.id, '20000000-0000-0000-0000-0000000030a3', 'team_lead'
  from tasks t where t.event_id = '30000000-0000-0000-0000-00000000030a'
   and t.task_type_id = (select id from task_types where code = 'setup' limit 1)
   and t.deleted_at is null limit 1;

-- שורת מלל חופשי אחת (מעבר לרשומת ה-created האוטומטית שהיא רשומת מערכת).
insert into event_activity (event_id, kind, actor_profile_id, actor_name, note)
values ('30000000-0000-0000-0000-00000000030a', 'note',
        '20000000-0000-0000-0000-0000000030a2', 'רכז 30', 'שיחה עם הלקוח על השעות');

\echo '--- רכז המשרד רואה הכול ---'
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000030a2', false);
select t_eq('הרכז רואה את המלל החופשי',
  (select count(*)::int from event_activity
    where event_id = '30000000-0000-0000-0000-00000000030a' and kind = 'note'), 1);
select t_eq('והרכז רואה רשומות מערכת',
  (select count(*)::int from event_activity
    where event_id = '30000000-0000-0000-0000-00000000030a' and kind <> 'note') >= 1, true);
reset role;
select set_config('request.jwt.claim.sub', '', false);

\echo '--- ראש צוות השטח רואה רק רשומות מערכת ---'
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000030a3', false);
select t_eq('ראש הצוות מזוהה ככזה',
  app.is_event_team_lead('30000000-0000-0000-0000-00000000030a'), true);
select t_eq('אינו רואה מלל חופשי',
  (select count(*)::int from event_activity
    where event_id = '30000000-0000-0000-0000-00000000030a' and kind = 'note'), 0);
select t_eq('אבל כן רשומות מערכת',
  (select count(*)::int from event_activity
    where event_id = '30000000-0000-0000-0000-00000000030a' and kind <> 'note') >= 1, true);
reset role;
select set_config('request.jwt.claim.sub', '', false);

\echo '--- הלקוח רואה מלל חופשי ---'
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000030a5', false);
select t_eq('הלקוח רואה את המלל החופשי',
  (select count(*)::int from event_activity
    where event_id = '30000000-0000-0000-0000-00000000030a' and kind = 'note'), 1);
reset role;
select set_config('request.jwt.claim.sub', '', false);

\echo '--- והמפתח קיים במרשם ---'
select t_eq('events.activity_note_view רשום ונגזר מ-events.edit',
  (select implied_by from permission_registry where key = 'events.activity_note_view'),
  'events.edit');
