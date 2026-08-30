\pset tuples_only on
\pset format unaligned

-- ===========================================================================
-- 27: המשאיות של הלקוח, והסטטוס שהוא רשאי להזיז (0116, 0117).
--
--   * **רשימת משאיות פר-לקוח.** ריק = כל הקטלוג; רשימה = רק היא. האכיפה
--     בטריגר ולא במסך, ועל `customer_user` בלבד — המשרד ממשיך לשבץ הכול.
--   * **שני השערים מתחברים בסדר הנכון:** ‏0109 שואל קודם "האם השדה בכלל
--     פתוח לך", ורק אחריו 0116 שואל "והאם המשאית שלך".
--   * **פרסום הוא מתג.** הלקוח מזיז בין "טיוטה" ל"מתוכנן" לשני הכיוונים,
--     ואינו נוגע ב"משובץ" — לא כדי להיכנס אליו ולא כדי לצאת ממנו.
--
-- החבילה מקימה לקוח, אירוע, משימות ושלוש דמויות משלה. האירוע ב-
-- current_date + 430, מעבר ל-420 של 26.
-- ===========================================================================

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000027a1', 'c27-cust@vl.test'),
  ('00000000-0000-0000-0000-0000000027a2', 'c27-admin@vl.test'),
  ('00000000-0000-0000-0000-0000000027a3', 'c27-disp@vl.test');

insert into customers (id, name) values
  ('10000000-0000-0000-0000-00000000027a', 'לקוח 27');

insert into profiles (id, user_id, user_kind, is_admin, full_name, customer_id) values
  ('20000000-0000-0000-0000-0000000027a1', '00000000-0000-0000-0000-0000000027a1',
   'customer_user', false, 'מנהל אצל לקוח 27', '10000000-0000-0000-0000-00000000027a'),
  ('20000000-0000-0000-0000-0000000027a2', '00000000-0000-0000-0000-0000000027a2',
   'staff', true,  'מנהל מערכת 27', null),
  ('20000000-0000-0000-0000-0000000027a3', '00000000-0000-0000-0000-0000000027a3',
   'staff', false, 'רכז 27', null);

insert into profile_roles (profile_id, role_id)
select p.pid, r.id from (values
  ('20000000-0000-0000-0000-0000000027a1'::uuid, 'customer_manager'),
  ('20000000-0000-0000-0000-0000000027a3'::uuid, 'dispatcher')
) as p(pid, rkey) join permission_roles r on r.key = p.rkey;

insert into trucks (id, name, plate_number) values
  ('70000000-0000-0000-0000-000000027001', 'משאית 27 של הלקוח', '27-001-27'),
  ('70000000-0000-0000-0000-000000027002', 'משאית 27 נוספת שלו', '27-002-27'),
  ('70000000-0000-0000-0000-000000027003', 'משאית 27 של מישהו אחר', '27-003-27');

insert into events (id, customer_id, event_number, event_date, end_client_name, status_id)
values ('30000000-0000-0000-0000-00000000027a', '10000000-0000-0000-0000-00000000027a',
        'EV-27', current_date + 430, 'לקוח קצה 27',
        (select id from statuses where entity = 'event' and code = 'planned' and deleted_at is null));

insert into tasks (id, event_id, customer_id, task_type_id, task_date,
                   onsite_start_time, hours_count, worker_count, status_id)
select x.id, '30000000-0000-0000-0000-00000000027a', '10000000-0000-0000-0000-00000000027a',
       (select id from task_types where code = 'setup' limit 1), current_date + 430,
       '09:00', 4, 2,
       (select id from statuses where entity = 'task' and code = 'draft' and deleted_at is null)
from (values
  ('61000000-0000-0000-0000-000000027001'::uuid),
  ('61000000-0000-0000-0000-000000027002'::uuid)
) as x(id);

-- ===== 1. השדה נעול עד שהמשרד פותח אותו ==================================
--
-- ברירת המחדל של 0109 היא "רואה, אינו עורך", ולכן זו נקודת ההתחלה — וגם
-- ההוכחה ששני השערים עומדים בסדר הנכון: 0109 עונה ראשון.

\echo '--- משאיות הלקוח ---'

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000027a1', false);
select t_expect_fail('שדה המשאיות נעול ללקוח כברירת מחדל', $$
  update tasks set truck_ids = array['70000000-0000-0000-0000-000000027001'::uuid]
   where id = '61000000-0000-0000-0000-000000027001'$$);
reset role;
select set_config('request.jwt.claim.sub', '', false);

-- המשרד פותח לו את השדה, ואת הסטטוס לקראת סעיף 3
insert into customer_board_fields (customer_id, field_key, state) values
  ('10000000-0000-0000-0000-00000000027a', 'truck',  'editable'),
  ('10000000-0000-0000-0000-00000000027a', 'status', 'editable')
on conflict (customer_id, field_key) do update set state = excluded.state;

-- ===== 2. ריק = אין הגבלה, ורשימה = רק היא ===============================

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000027a1', false);
select t_expect_ok('בלי רשימה — הלקוח בוחר כל משאית בקטלוג', $$
  update tasks set truck_ids = array['70000000-0000-0000-0000-000000027003'::uuid]
   where id = '61000000-0000-0000-0000-000000027001'$$);
reset role;
select set_config('request.jwt.claim.sub', '', false);

insert into customer_trucks (customer_id, truck_id) values
  ('10000000-0000-0000-0000-00000000027a', '70000000-0000-0000-0000-000000027001'),
  ('10000000-0000-0000-0000-00000000027a', '70000000-0000-0000-0000-000000027002');

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000027a1', false);
select t_expect_ok('משאית מהרשימה עוברת', $$
  update tasks set truck_ids = array['70000000-0000-0000-0000-000000027001'::uuid]
   where id = '61000000-0000-0000-0000-000000027001'$$);

select t_expect_ok('ושתיים מהרשימה גם הן', $$
  update tasks set truck_ids = array['70000000-0000-0000-0000-000000027001'::uuid,
                                     '70000000-0000-0000-0000-000000027002'::uuid]
   where id = '61000000-0000-0000-0000-000000027001'$$);

select t_expect_fail('משאית שאינה ברשימה נדחית', $$
  update tasks set truck_ids = array['70000000-0000-0000-0000-000000027003'::uuid]
   where id = '61000000-0000-0000-0000-000000027001'$$);

-- גם כשהיא מתחבאת בין שתיים כשרות
select t_expect_fail('וגם כשהיא מעורבבת בין שתיים כשרות', $$
  update tasks set truck_ids = array['70000000-0000-0000-0000-000000027001'::uuid,
                                     '70000000-0000-0000-0000-000000027003'::uuid]
   where id = '61000000-0000-0000-0000-000000027001'$$);

-- הנתיב של truck_id הבודד: app.sync_task_trucks גוזר ממנו את המערך, ולכן
-- הבדיקה חייבת לרוץ *אחריו* — זו כל הסיבה לשם tasks_z_customer_trucks
select t_expect_fail('וגם דרך truck_id הבודד, שהמערך נגזר ממנו', $$
  update tasks set truck_id = '70000000-0000-0000-0000-000000027003'
   where id = '61000000-0000-0000-0000-000000027002'$$);

select t_expect_ok('וריקון המשאיות תמיד מותר', $$
  update tasks set truck_ids = '{}'::uuid[]
   where id = '61000000-0000-0000-0000-000000027001'$$);
reset role;
select set_config('request.jwt.claim.sub', '', false);

-- ...והמשרד אינו מוגבל: אצלו הבורר מסונן, לא נעול
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000027a3', false);
select t_expect_ok('הרכז משבץ משאית שאינה ברשימת הלקוח', $$
  update tasks set truck_ids = array['70000000-0000-0000-0000-000000027003'::uuid]
   where id = '61000000-0000-0000-0000-000000027001'$$);
reset role;
select set_config('request.jwt.claim.sub', '', false);

-- הלקוח רואה את הרשימה שלו, ורק אותה
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000027a1', false);
select t_eq('הלקוח קורא את הרשימה שלו',
  (select count(*)::int from customer_trucks), 2);
reset role;
select set_config('request.jwt.claim.sub', '', false);

-- ===== 3. הסטטוס: טיוטה ↔ מתוכנן, ולא משובץ ==============================

\echo '--- הסטטוס שהלקוח רשאי להזיז ---'

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000027a1', false);

select t_expect_ok('הלקוח מעביר טיוטה למתוכנן', $$
  update tasks set status_id = (select id from statuses
                                 where entity = 'task' and code = 'planned' and deleted_at is null)
   where id = '61000000-0000-0000-0000-000000027001'$$);

select t_expect_ok('ובחזרה לטיוטה', $$
  update tasks set status_id = (select id from statuses
                                 where entity = 'task' and code = 'draft' and deleted_at is null)
   where id = '61000000-0000-0000-0000-000000027001'$$);

select t_expect_fail('אבל לא למשובץ', $$
  update tasks set status_id = (select id from statuses
                                 where entity = 'task' and code = 'assigned' and deleted_at is null)
   where id = '61000000-0000-0000-0000-000000027001'$$);
reset role;
select set_config('request.jwt.claim.sub', '', false);

-- מנהל המערכת מפרסם, והלקוח מנסה להוריד — הכיוון שנפתח ב-0117
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000027a2', false);
select t_expect_ok('מנהל המערכת מפרסם', $$
  update tasks set status_id = (select id from statuses
                                 where entity = 'task' and code = 'assigned' and deleted_at is null)
   where id = '61000000-0000-0000-0000-000000027001'$$);
reset role;
select set_config('request.jwt.claim.sub', '', false);

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000027a1', false);
select t_expect_fail('והלקוח אינו מוריד משימה מפרסום', $$
  update tasks set status_id = (select id from statuses
                                 where entity = 'task' and code = 'planned' and deleted_at is null)
   where id = '61000000-0000-0000-0000-000000027001'$$);
reset role;
select set_config('request.jwt.claim.sub', '', false);

select t_eq('והמשימה נשארה משובצת',
  (select s.code from tasks t join statuses s on s.id = t.status_id
    where t.id = '61000000-0000-0000-0000-000000027001'), 'assigned');

-- ...ומי שכן מחזיק את המפתח כן מוריד. השער הוא על המפתח, לא על סוג המשתמש.
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000027a3', false);
select t_expect_ok('רכז שמחזיק tasks.publish כן מוריד מפרסום', $$
  update tasks set status_id = (select id from statuses
                                 where entity = 'task' and code = 'planned' and deleted_at is null)
   where id = '61000000-0000-0000-0000-000000027001'$$);
reset role;
select set_config('request.jwt.claim.sub', '', false);

-- ===== 4. ומה שהמסך שואל, ולא רק השרת (0131) =============================
--
-- השרת הרשה את המעבר עוד קודם — שכבת הרשאות השדה ענתה כן — אבל תא הסטטוס
-- בלו״ז נשען על שני מפתחות שלא היו בידי `customer_manager`, ולכן הוא נצבע
-- לקריאה בלבד והלקוח לא הצליח להזיז דבר. ‏0131 העניק אותם לתפקיד.
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000027a1', false);
select t_eq('מנהל אצל הלקוח מחזיק tasks.change_status', app.has('tasks.change_status'), true);
select t_eq('ומחזיק board.inline_edit',                 app.has('board.inline_edit'),   true);
select t_eq('ואינו מחזיק tasks.publish',                app.has('tasks.publish'),       false);
reset role;
select set_config('request.jwt.claim.sub', '', false);
