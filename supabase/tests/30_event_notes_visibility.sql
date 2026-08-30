\pset tuples_only on
\pset format unaligned

-- ===========================================================================
-- 30: תיעוד האירוע — השטח והקבלנים רואים הערות, ורק אותן (0129).
--
-- ‏0122 שאלה מי רשאי לקרוא מלל חופשי, ו-0129 הפכה את השאלה: ההערה נכתבת אל
-- מי שנוסע לאירוע, ורשומות המערכת — ההיסטוריה של מי שינה מה — הן שדורשות
-- מפתח (`events.activity_system_view`). החבילה בודקת את שני צדי ההיפוך על
-- ארבעה קהלים: משרד, ראש צוות שטח, עובד קבלן ולקוח.
-- החלון הוא current_date + 460.
-- ===========================================================================

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000030a1', 'c30-admin@vl.test'),
  ('00000000-0000-0000-0000-0000000030a2', 'c30-office@vl.test'),
  ('00000000-0000-0000-0000-0000000030a3', 'c30-lead@vl.test'),
  ('00000000-0000-0000-0000-0000000030a4', 'c30-ctr@vl.test'),
  ('00000000-0000-0000-0000-0000000030a5', 'c30-cust@vl.test');

insert into customers (id, name) values
  ('10000000-0000-0000-0000-00000000030a', 'לקוח 30');
insert into contractors (id, name) values
  ('c0000000-0000-0000-0000-00000000030a', 'קבלן 30');

insert into profiles (id, user_id, user_kind, is_admin, full_name) values
  ('20000000-0000-0000-0000-0000000030a1', '00000000-0000-0000-0000-0000000030a1', 'staff', true,  'מנהל 30'),
  ('20000000-0000-0000-0000-0000000030a2', '00000000-0000-0000-0000-0000000030a2', 'staff', false, 'רכז 30'),
  ('20000000-0000-0000-0000-0000000030a3', '00000000-0000-0000-0000-0000000030a3', 'staff', false, 'ראש צוות שטח 30');
insert into profiles (id, user_id, user_kind, is_admin, full_name, contractor_id) values
  ('20000000-0000-0000-0000-0000000030a4', '00000000-0000-0000-0000-0000000030a4', 'contractor_user', false,
   'עובד קבלן 30', 'c0000000-0000-0000-0000-00000000030a');
insert into profiles (id, user_id, user_kind, is_admin, full_name, customer_id) values
  ('20000000-0000-0000-0000-0000000030a5', '00000000-0000-0000-0000-0000000030a5', 'customer_user', false, 'לקוח 30',
   '10000000-0000-0000-0000-00000000030a');

insert into staff_roles (profile_id, role) values
  ('20000000-0000-0000-0000-0000000030a3', 'team_lead');

-- ‏ההרשאות נגזרות מתפקיד ההרשאות ולא מ-`staff_roles`, ולכן ראש צוות השטח
-- נושא את תפקיד "ראש צוות" — הוא זה שנושא את שורת הדחייה של 0129.
insert into profile_roles (profile_id, role_id)
select '20000000-0000-0000-0000-0000000030a3', id from permission_roles where key = 'team_lead';

-- הרכז מקבל events.edit במפורש (ומכאן activity_system_view בהיסק).
insert into user_permission_grants (profile_id, permission_key, allowed) values
  ('20000000-0000-0000-0000-0000000030a2', 'events.view', true),
  ('20000000-0000-0000-0000-0000000030a2', 'events.edit', true);

insert into events (id, customer_id, event_number, event_date, end_client_name, status_id)
values ('30000000-0000-0000-0000-00000000030a', '10000000-0000-0000-0000-00000000030a',
        'EV-30', current_date + 460, 'לקוח קצה 30',
        (select id from statuses where entity = 'event' and code = 'pending' and deleted_at is null));

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

-- עובד הקבלן מגיע לאירוע כפי שהוא מגיע אליו במציאות: המשימה הואצלה לקבלן
-- שלו, יש לו שורת סגל, והוא משובץ על המשימה שפורסמה.
insert into task_contractor_terms (task_id, contractor_id, price)
select t.id, 'c0000000-0000-0000-0000-00000000030a', 0
  from tasks t where t.event_id = '30000000-0000-0000-0000-00000000030a'
   and t.task_type_id = (select id from task_types where code = 'setup' limit 1)
   and t.deleted_at is null limit 1;

insert into contractor_workers (id, contractor_id, full_name) values
  ('c1000000-0000-0000-0000-00000000030a', 'c0000000-0000-0000-0000-00000000030a', 'עובד קבלן 30');
update profiles set contractor_worker_id = 'c1000000-0000-0000-0000-00000000030a'
 where id = '20000000-0000-0000-0000-0000000030a4';

insert into task_contractor_workers (task_id, contractor_worker_id)
select t.id, 'c1000000-0000-0000-0000-00000000030a'
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

\echo '--- ראש צוות השטח רואה הערות בלבד ---'
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000030a3', false);
select t_eq('ראש הצוות מזוהה ככזה',
  app.is_event_team_lead('30000000-0000-0000-0000-00000000030a'), true);
select t_eq('רואה את המלל החופשי (0129)',
  (select count(*)::int from event_activity
    where event_id = '30000000-0000-0000-0000-00000000030a' and kind = 'note'), 1);
select t_eq('ואינו רואה רשומות מערכת',
  (select count(*)::int from event_activity
    where event_id = '30000000-0000-0000-0000-00000000030a' and kind <> 'note'), 0);
select t_expect_ok('והוא מתעד בעצמו', $$
  insert into event_activity (event_id, kind, actor_profile_id, note)
  values ('30000000-0000-0000-0000-00000000030a', 'note',
          '20000000-0000-0000-0000-0000000030a3', 'הכניסה מאחורי הבניין')$$);
reset role;
select set_config('request.jwt.claim.sub', '', false);

\echo '--- עובד הקבלן: אותו כלל בדיוק ---'
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000030a4', false);
select t_eq('עובד הקבלן קורא את היומן',      app.has('events.activity_log'), true);
select t_eq('ומתעד',                          app.has('events.activity_note'), true);
select t_eq('אך לא רשומות מערכת',            app.has('events.activity_system_view'), false);
select t_eq('ובפועל רואה שתי הערות',
  (select count(*)::int from event_activity
    where event_id = '30000000-0000-0000-0000-00000000030a' and kind = 'note'), 2);
select t_eq('ואפס רשומות מערכת',
  (select count(*)::int from event_activity
    where event_id = '30000000-0000-0000-0000-00000000030a' and kind <> 'note'), 0);
reset role;
select set_config('request.jwt.claim.sub', '', false);

\echo '--- הלקוח ממשיך לראות הכול ---'
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000030a5', false);
select t_eq('הלקוח רואה את המלל החופשי',
  (select count(*)::int from event_activity
    where event_id = '30000000-0000-0000-0000-00000000030a' and kind = 'note'), 2);
select t_eq('והלקוח רואה רשומות מערכת',
  (select count(*)::int from event_activity
    where event_id = '30000000-0000-0000-0000-00000000030a' and kind <> 'note') >= 1, true);
reset role;
select set_config('request.jwt.claim.sub', '', false);

\echo '--- והמפתחות במרשם ---'
select t_eq('events.activity_system_view רשום ונגזר מ-events.edit',
  (select implied_by from permission_registry where key = 'events.activity_system_view'),
  'events.edit');
select t_eq('והשער הישן ירד מהמרשם הפעיל',
  (select is_active from permission_registry where key = 'events.activity_note_view'), false);
