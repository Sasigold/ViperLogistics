\pset tuples_only on
\pset format unaligned

-- ===========================================================================
-- 33: סגל העובדים של לקוח שמבצע בעצמו (0133), הלו״ז שמכיר אותו (0134),
--     והשדות שנפתחים לו בו (0138).
--
-- החלון הוא current_date + 490, מעבר ל-480 של 32.
-- ===========================================================================

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000033a1', 'c33-admin@vl.test'),
  ('00000000-0000-0000-0000-0000000033a2', 'c33-arko@vl.test'),
  ('00000000-0000-0000-0000-0000000033a3', 'c33-other@vl.test');

-- לקוח שמבצע בעצמו, ולקוח רגיל לצדו — כדי שהדגל יהיה מה שמכריע ולא התפקיד.
insert into customers (id, name, performed_by_enabled) values
  ('10000000-0000-0000-0000-00000000033a', 'ארקו 33', true),
  ('10000000-0000-0000-0000-00000000033b', 'לקוח רגיל 33', false);

insert into profiles (id, user_id, user_kind, is_admin, full_name) values
  ('20000000-0000-0000-0000-0000000033a1', '00000000-0000-0000-0000-0000000033a1', 'staff', true, 'מנהל 33');
insert into profiles (id, user_id, user_kind, is_admin, full_name, customer_id) values
  ('20000000-0000-0000-0000-0000000033a2', '00000000-0000-0000-0000-0000000033a2',
   'customer_user', false, 'מנהל אצל ארקו 33', '10000000-0000-0000-0000-00000000033a'),
  ('20000000-0000-0000-0000-0000000033a3', '00000000-0000-0000-0000-0000000033a3',
   'customer_user', false, 'מנהל אצל לקוח רגיל 33', '10000000-0000-0000-0000-00000000033b');

insert into profile_roles (profile_id, role_id)
select p, id from permission_roles r,
  unnest(array['20000000-0000-0000-0000-0000000033a2'::uuid,
               '20000000-0000-0000-0000-0000000033a3'::uuid]) p
where r.key = 'customer_manager';

insert into events (id, customer_id, event_number, event_date, end_client_name, status_id)
values ('30000000-0000-0000-0000-00000000033a', '10000000-0000-0000-0000-00000000033a',
        'EV-33', current_date + 490, 'קצה 33',
        (select id from statuses where entity = 'event' and code = 'pending' and deleted_at is null));

-- משימת ההקמה עוברת לארקו; הפירוק נשאר על וייפר.
update tasks set performed_by = 'arko'
 where event_id = '30000000-0000-0000-0000-00000000033a'
   and task_type_id = (select id from task_types where code = 'setup' limit 1);

-- ===== 1. המפתחות והדגל ==================================================

\echo '--- הדגל הוא השער, לא התפקיד ---'
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000033a2', false);
select t_eq('מנהל אצל ארקו מחזיק את המפתחות', app.has('customers.manage_own_staff'), true);
select t_eq('ומזוהה כמנהל סגל של הלקוח שלו',
  app.own_staff_customer_id(), '10000000-0000-0000-0000-00000000033a'::uuid);
reset role;
select set_config('request.jwt.claim.sub', '', false);

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000033a3', false);
select t_eq('מנהל אצל לקוח רגיל מחזיק את אותו מפתח', app.has('customers.manage_own_staff'), true);
select t_eq('אבל אינו מנהל סגל של איש — הדגל כבוי',
  app.own_staff_customer_id(), null::uuid);
reset role;
select set_config('request.jwt.claim.sub', '', false);

-- ===== 2. רשומת הסגל =====================================================

\echo '--- הלקוח מקים את הסגל שלו ---'
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000033a2', false);

select t_expect_ok('מוסיף עובד', $$
  insert into customer_workers (id, customer_id, full_name)
  values ('cf000000-0000-0000-0000-0000003300a1', '10000000-0000-0000-0000-00000000033a', 'עובד A 33')$$);
select t_expect_ok('ועוד אחד', $$
  insert into customer_workers (id, customer_id, full_name)
  values ('cf000000-0000-0000-0000-0000003300b1', '10000000-0000-0000-0000-00000000033a', 'עובד B 33')$$);

select t_expect_fail('אך לא לחשבון של לקוח אחר', $$
  insert into customer_workers (customer_id, full_name)
  values ('10000000-0000-0000-0000-00000000033b', 'עובד גנוב 33')$$);

select t_expect_ok('ומגדיר לעובד A תפקיד ראש צוות', $$
  insert into customer_worker_roles (customer_worker_id, role)
  values ('cf000000-0000-0000-0000-0000003300a1', 'team_lead')$$);
select t_expect_ok('ולעובד A גם נהג', $$
  insert into customer_worker_roles (customer_worker_id, role)
  values ('cf000000-0000-0000-0000-0000003300a1', 'driver')$$);
reset role;
select set_config('request.jwt.claim.sub', '', false);

\echo '--- לקוח אחר אינו רואה את הסגל הזה ---'
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000033a3', false);
select t_eq('הסגל של ארקו אינו נראה ללקוח אחר',
  (select count(*)::int from customer_workers
    where customer_id = '10000000-0000-0000-0000-00000000033a'), 0);
reset role;
select set_config('request.jwt.claim.sub', '', false);

-- ===== 3. השיבוץ =========================================================

\echo '--- שיבוץ למשימה שסומנה שהלקוח מבצע ---'
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000033a2', false);

select t_expect_fail('עובד B אינו ראש צוות ולכן אינו משובץ ככזה', $$
  select customer_assign_worker(
    (select t.id from tasks t where t.event_id = '30000000-0000-0000-0000-00000000033a'
       and t.task_type_id = (select id from task_types where code='setup' limit 1)
       and t.deleted_at is null limit 1),
    'cf000000-0000-0000-0000-0000003300b1', true, null, 'team_lead')$$);

select t_expect_ok('עובד A משובץ כראש צוות', $$
  select customer_assign_worker(
    (select t.id from tasks t where t.event_id = '30000000-0000-0000-0000-00000000033a'
       and t.task_type_id = (select id from task_types where code='setup' limit 1)
       and t.deleted_at is null limit 1),
    'cf000000-0000-0000-0000-0000003300a1', true, null, 'team_lead')$$);

select t_expect_ok('ועובד B כעובד רגיל', $$
  select customer_assign_worker(
    (select t.id from tasks t where t.event_id = '30000000-0000-0000-0000-00000000033a'
       and t.task_type_id = (select id from task_types where code='setup' limit 1)
       and t.deleted_at is null limit 1),
    'cf000000-0000-0000-0000-0000003300b1', true, null, null)$$);

-- אותו כלל של 0128: ראש צוות אחד למשימה
select t_expect_fail('ואין ראש צוות שני', $$
  select customer_assign_worker(
    (select t.id from tasks t where t.event_id = '30000000-0000-0000-0000-00000000033a'
       and t.task_type_id = (select id from task_types where code='setup' limit 1)
       and t.deleted_at is null limit 1),
    'cf000000-0000-0000-0000-0000003300b1', true, null, 'team_lead')$$);

-- והמשימה של וייפר אינה שלו לשבץ בה
select t_expect_fail('ומשימה שנשארה על וייפר אינה פתוחה לסגל שלו', $$
  select customer_assign_worker(
    (select t.id from tasks t where t.event_id = '30000000-0000-0000-0000-00000000033a'
       and t.task_type_id = (select id from task_types where code='teardown' limit 1)
       and t.deleted_at is null limit 1),
    'cf000000-0000-0000-0000-0000003300a1', true, null, null)$$);

reset role;
select set_config('request.jwt.claim.sub', '', false);

\echo '--- לקוח אחר אינו משבץ לתוך המשימה של ארקו ---'
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000033a3', false);
select t_expect_fail('לקוח זר נדחה', $$
  select customer_assign_worker(
    (select t.id from tasks t where t.event_id = '30000000-0000-0000-0000-00000000033a'
       and t.task_type_id = (select id from task_types where code='setup' limit 1)
       and t.deleted_at is null limit 1),
    'cf000000-0000-0000-0000-0000003300a1', true, null, null)$$);
reset role;
select set_config('request.jwt.claim.sub', '', false);

-- ===== 4. הלו״ז (0134) ===================================================

\echo '--- ראש הצוות של הלקוח יושב בשורה של ראש הצוות ---'
select t_eq('ראש הצוות הוא עובד A',
  (select w.team_lead_name from work_board_view w
     join tasks t on t.id = w.id
    where t.event_id = '30000000-0000-0000-0000-00000000033a'
      and t.task_type_id = (select id from task_types where code='setup' limit 1)), 'עובד A 33');

select t_eq('והמקור הוא סגל הלקוח',
  (select w.team_lead_kind from work_board_view w
     join tasks t on t.id = w.id
    where t.event_id = '30000000-0000-0000-0000-00000000033a'
      and t.task_type_id = (select id from task_types where code='setup' limit 1)), 'customer');

select t_eq('ושני העובדים ברשימת הסגל של הלקוח',
  (select jsonb_array_length(w.customer_worker_list) from work_board_view w
     join tasks t on t.id = w.id
    where t.event_id = '30000000-0000-0000-0000-00000000033a'
      and t.task_type_id = (select id from task_types where code='setup' limit 1)), 2);

\echo '--- הסרה, ורשימת הסגל הניתן לשיבוץ ---'
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000033a2', false);
select t_eq('עובד A מוצע עם תפקיד ראש צוות',
  (select (x -> 'roles') @> '"team_lead"'::jsonb
     from jsonb_array_elements(customer_assignable_workers()) x
    where x ->> 'worker_id' = 'cf000000-0000-0000-0000-0000003300a1'), true);
select t_eq('ועובד B בלי תפקידים',
  (select (x -> 'roles')
     from jsonb_array_elements(customer_assignable_workers()) x
    where x ->> 'worker_id' = 'cf000000-0000-0000-0000-0000003300b1'), '[]'::jsonb);

select t_expect_ok('והלקוח מסיר עובד מהמשימה', $$
  select customer_assign_worker(
    (select t.id from tasks t where t.event_id = '30000000-0000-0000-0000-00000000033a'
       and t.task_type_id = (select id from task_types where code='setup' limit 1)
       and t.deleted_at is null limit 1),
    'cf000000-0000-0000-0000-0000003300b1', false)$$);
reset role;
select set_config('request.jwt.claim.sub', '', false);

select t_eq('ונשאר אחד',
  (select count(*)::int from task_customer_workers tcuw
     join tasks t on t.id = tcuw.task_id
    where t.event_id = '30000000-0000-0000-0000-00000000033a'), 1);

\echo '--- ולקוח שאינו מבצע בעצמו אינו מקבל רשימה ---'
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000033a3', false);
select t_eq('רשימת הסגל שלו ריקה', customer_assignable_workers(), '[]'::jsonb);
reset role;
select set_config('request.jwt.claim.sub', '', false);

-- ===== 5. שדות הלוח של מי שמבצע בעצמו (0138) ============================

\echo '--- המשאיות והסטטוס פתוחים לו, ורק לו ---'
select t_eq('שדה המשאיות פתוח לעריכה ללקוח שמבצע בעצמו',
  (select state::text from customer_board_fields
    where customer_id = '10000000-0000-0000-0000-00000000033a' and field_key = 'truck'), 'editable');
select t_eq('וגם שדה הסטטוס',
  (select state::text from customer_board_fields
    where customer_id = '10000000-0000-0000-0000-00000000033a' and field_key = 'status'), 'editable');
select t_eq('ואצל לקוח רגיל הם נשארים כפי שהמשרד קבע',
  (select state::text from customer_board_fields
    where customer_id = '10000000-0000-0000-0000-00000000033b' and field_key = 'truck'), 'visible');

-- ובפועל: הלקוח מזיז טיוטה↔מתוכנן על המשימה שלו (0131 + 0138)
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000033a2', false);
select t_expect_ok('והוא מזיז את המשימה שלו למתוכנן', $$
  update tasks set status_id = (select id from statuses
                                 where entity = 'task' and code = 'planned' and deleted_at is null)
   where event_id = '30000000-0000-0000-0000-00000000033a'
     and task_type_id = (select id from task_types where code = 'setup' limit 1)$$);
reset role;
select set_config('request.jwt.claim.sub', '', false);

-- והדגל הוא שפותח: לקוח שנדלק אחרי הלידה מקבל אותם בטריגר
update customers set performed_by_enabled = true where id = '10000000-0000-0000-0000-00000000033b';
select t_eq('לקוח שהדגל שלו נדלק מאוחר מקבל אותם בטריגר',
  (select state::text from customer_board_fields
    where customer_id = '10000000-0000-0000-0000-00000000033b' and field_key = 'truck'), 'editable');
update customers set performed_by_enabled = false where id = '10000000-0000-0000-0000-00000000033b';
