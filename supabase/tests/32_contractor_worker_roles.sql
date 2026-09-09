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

-- ===========================================================================
-- ‏0154: המשאית של נהג הקבלן
--
-- שלוש טענות: מי רשאי לקבוע אותה, שהיא של נהג בלבד, ושהיא מוגבלת לרשימת
-- המשאיות של הלקוח כמו בכל בורר משאיות אחר במערכת (0116).
--
-- המשימה כאן היא זו של סעיף 0128 שלמעלה — עובד A כבר משובץ עליה כעובד רגיל,
-- ולכן כל בדיקה מתחת היא על **עדכון** של אותה שורה, בדיוק הנתיב שבו ה-upsert
-- כותב את מה שנשלח.
-- ===========================================================================

\echo '--- 0154: משאית לנהג של הקבלן ---'

insert into trucks (id, name) values
  ('7c000000-0000-0000-0000-0000003200f1', 'משאית 32 א'),
  ('7c000000-0000-0000-0000-0000003200f2', 'משאית 32 ב');

-- מנהל הקבלן משבץ את הסגל שלו, ואינו מחזיק את מפתח המשאיות של המשרד.
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000032a4', false);
select t_expect_fail('מנהל הקבלן אינו קובע באיזו משאית נוסעים', $$
  select contractor_assign_worker('61000000-0000-0000-0000-000000032003',
      'ca000000-0000-0000-0000-0000003200a1', null, true, null, 'driver',
      '7c000000-0000-0000-0000-0000003200f1')$$);
reset role;
select set_config('request.jwt.claim.sub', '', false);

-- המשרד (כאן: מנהל המערכת) כן.
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000032a1', false);
select t_expect_ok('המשרד משבץ את נהג הקבלן למשאית', $$
  select contractor_assign_worker('61000000-0000-0000-0000-000000032003',
      'ca000000-0000-0000-0000-0000003200a1', null, true, null, 'driver',
      '7c000000-0000-0000-0000-0000003200f1')$$);

-- משאית היא של נהג. תפקיד אחר עם משאית נדחה במפורש ולא נבלע בשקט.
select t_expect_fail('ראש צוות אינו מקבל משאית', $$
  select contractor_assign_worker('61000000-0000-0000-0000-000000032003',
      'cb000000-0000-0000-0000-0000003200b1', null, true, null, 'team_lead',
      '7c000000-0000-0000-0000-0000003200f2')$$);
reset role;
select set_config('request.jwt.claim.sub', '', false);

select t_eq('והמשאית נרשמה על שורת השיבוץ',
  (select truck_id from task_contractor_workers
    where task_id = '61000000-0000-0000-0000-000000032003'
      and contractor_worker_id = 'ca000000-0000-0000-0000-0000003200a1'),
  '7c000000-0000-0000-0000-0000003200f1'::uuid);

-- ‏0111 כבר קובעת שנקודת ההתחלה של הקבלן נזרקת; מה שנבדק כאן הוא שהמשאית
-- **שורדת** קריאה שלו — הוא שולח את מצב השורה כולו, ואין לו מה לשנות בה.
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000032a4', false);
select t_expect_ok('והקבלן ממשיך לעדכן את השורה בלי לגעת במשאית', $$
  select contractor_assign_worker('61000000-0000-0000-0000-000000032003',
      'ca000000-0000-0000-0000-0000003200a1', null, true, 'warehouse', 'driver',
      '7c000000-0000-0000-0000-0000003200f1')$$);
reset role;
select set_config('request.jwt.claim.sub', '', false);

select t_eq('והיא נשארה עליו',
  (select truck_id from task_contractor_workers
    where task_id = '61000000-0000-0000-0000-000000032003'
      and contractor_worker_id = 'ca000000-0000-0000-0000-0000003200a1'),
  '7c000000-0000-0000-0000-0000003200f1'::uuid);

-- רשימת המשאיות של הלקוח (0116): משאית שאינה בה נדחית, וזו שבה עוברת.
insert into customer_trucks (customer_id, truck_id) values
  ('10000000-0000-0000-0000-00000000032a', '7c000000-0000-0000-0000-0000003200f1');

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000032a1', false);
select t_expect_fail('משאית שאינה ברשימת הלקוח נדחית', $$
  select contractor_assign_worker('61000000-0000-0000-0000-000000032003',
      'ca000000-0000-0000-0000-0000003200a1', null, true, null, 'driver',
      '7c000000-0000-0000-0000-0000003200f2')$$);

-- והורדת התפקיד מורידה איתה את המשאית, כי הקורא שולח את השורה כולה.
select t_expect_ok('חזרה לעובד רגיל מסירה את המשאית', $$
  select contractor_assign_worker('61000000-0000-0000-0000-000000032003',
      'ca000000-0000-0000-0000-0000003200a1', null, true, null, null, null)$$);
reset role;
select set_config('request.jwt.claim.sub', '', false);

select t_eq('ולא נשארה משאית על מי שאינו נוהג',
  (select truck_id from task_contractor_workers
    where task_id = '61000000-0000-0000-0000-000000032003'
      and contractor_worker_id = 'ca000000-0000-0000-0000-0000003200a1') is null, true);

-- ===========================================================================
-- ‏0162: ראש הצוות של הקבלן יכול להיות גם הנהג
--
-- ארבע טענות: הסימון שמור לראש צוות, הוא דורש שהעובד מוגדר נהג, הוא פותח
-- לראש הצוות את המשאית — והלו״ז מדווח עליו בשורת ראש הצוות.
--
-- משימת הפירוק היא הזירה: עובד A (ראש צוות + נהג) כבר משובץ עליה כראש צוות
-- מסעיף 0127 שלמעלה, ואין עליה ראש צוות פנימי.
-- ===========================================================================

\echo '--- 0162: ראש צוות של קבלן שגם נוהג ---'

-- משימה רביעית, מואצלת לאותו קבלן ובלי ראש צוות פנימי — כאן נבדק עובד B,
-- שמוגדר ראש צוות אך אינו מוגדר נהג.
insert into tasks (id, event_id, customer_id, task_type_id, task_date, worker_count, status_id)
select '61000000-0000-0000-0000-000000032004', '30000000-0000-0000-0000-00000000032a',
       '10000000-0000-0000-0000-00000000032a', tt.id, current_date + 480, 4,
       (select id from statuses where entity = 'task' and code = 'draft' and deleted_at is null)
  from task_types tt where tt.name = 'סידור' limit 1;
insert into task_contractor_terms (task_id, contractor_id, price, work_site)
values ('61000000-0000-0000-0000-000000032004', 'c0000000-0000-0000-0000-00000000032a', 0, 'field');

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000032a4', false);

-- הסימון הוא של ראש הצוות. מי שמשובץ נהג כבר נוהג, ועובד רגיל אינו נוהג.
select t_expect_fail('"גם נהג" על עובד רגיל נדחה', $$
  select contractor_assign_worker(
      (select t.id from tasks t where t.event_id = '30000000-0000-0000-0000-00000000032a'
         and t.task_type_id = (select id from task_types where code='teardown' limit 1)
         and t.deleted_at is null limit 1),
      'ca000000-0000-0000-0000-0000003200a1', null, true, null, null, null, true)$$);

-- עובד B מוגדר ראש צוות בלבד — הסימון נדחה, והשיבוץ בלעדיו עובר.
select t_expect_fail('ראש צוות שאינו מוגדר נהג אינו מסומן נוהג', $$
  select contractor_assign_worker('61000000-0000-0000-0000-000000032004',
      'cb000000-0000-0000-0000-0000003200b1', null, true, null, 'team_lead', null, true)$$);
select t_expect_ok('והוא משובץ ראש צוות בלי הסימון', $$
  select contractor_assign_worker('61000000-0000-0000-0000-000000032004',
      'cb000000-0000-0000-0000-0000003200b1', null, true, null, 'team_lead', null, false)$$);

-- עובד A מוגדר ראש צוות **וגם** נהג — הסימון מתקבל.
select t_expect_ok('ראש צוות שמוגדר נהג מסומן "גם נהג"', $$
  select contractor_assign_worker(
      (select t.id from tasks t where t.event_id = '30000000-0000-0000-0000-00000000032a'
         and t.task_type_id = (select id from task_types where code='teardown' limit 1)
         and t.deleted_at is null limit 1),
      'ca000000-0000-0000-0000-0000003200a1', null, true, null, 'team_lead', null, true)$$);
reset role;
select set_config('request.jwt.claim.sub', '', false);

select t_eq('והסימון נרשם על שורת השיבוץ',
  (select tcw.drives from task_contractor_workers tcw
     join tasks t on t.id = tcw.task_id
    where t.event_id = '30000000-0000-0000-0000-00000000032a'
      and t.task_type_id = (select id from task_types where code='teardown' limit 1)
      and tcw.contractor_worker_id = 'ca000000-0000-0000-0000-0000003200a1'), true);

-- והמשאית נפתחת לו, בדיוק כמו לנהג. המשרד קובע אותה (0154), והרשימה של
-- הלקוח כבר מוגבלת למשאית א׳ מהסעיף שמעל.
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000032a1', false);
select t_expect_ok('ראש הצוות שנוהג מקבל משאית', $$
  select contractor_assign_worker(
      (select t.id from tasks t where t.event_id = '30000000-0000-0000-0000-00000000032a'
         and t.task_type_id = (select id from task_types where code='teardown' limit 1)
         and t.deleted_at is null limit 1),
      'ca000000-0000-0000-0000-0000003200a1', null, true, null, 'team_lead',
      '7c000000-0000-0000-0000-0000003200f1', true)$$);
-- וכשהסימון יורד, יורדת איתו המשאית — הקורא שולח את השורה כולה.
select t_expect_fail('וראש צוות שאינו מסומן נוהג אינו מקבל משאית', $$
  select contractor_assign_worker(
      (select t.id from tasks t where t.event_id = '30000000-0000-0000-0000-00000000032a'
         and t.task_type_id = (select id from task_types where code='teardown' limit 1)
         and t.deleted_at is null limit 1),
      'ca000000-0000-0000-0000-0000003200a1', null, true, null, 'team_lead',
      '7c000000-0000-0000-0000-0000003200f1', false)$$);
reset role;
select set_config('request.jwt.claim.sub', '', false);

\echo '--- 0162: השורה בלו״ז אומרת מה ראש הצוות הוא ---'
select t_eq('הלו״ז מדווח שראש הצוות של הקבלן נוהג',
  (select w.team_lead_drives from work_board_view w
     join tasks t on t.id = w.id
    where t.event_id = '30000000-0000-0000-0000-00000000032a'
      and t.task_type_id = (select id from task_types where code='teardown' limit 1)), true);
select t_eq('ובאיזו משאית',
  (select w.team_lead_truck_name from work_board_view w
     join tasks t on t.id = w.id
    where t.event_id = '30000000-0000-0000-0000-00000000032a'
      and t.task_type_id = (select id from task_types where code='teardown' limit 1)), 'משאית 32 א');
select t_eq('ומאיפה הוא מתחיל',
  (select w.team_lead_work_site from work_board_view w
     join tasks t on t.id = w.id
    where t.event_id = '30000000-0000-0000-0000-00000000032a'
      and t.task_type_id = (select id from task_types where code='teardown' limit 1)), 'field');
select t_eq('וראש צוות שאינו נוהג מדווח ככזה',
  (select team_lead_drives from work_board_view
    where id = '61000000-0000-0000-0000-000000032004'), false);

-- ראש צוות פנימי שנוהג: שורת שיבוץ שנייה בתפקיד driver (0155), ומשם הלו״ז
-- גוזר את אותן שלוש התשובות. המשימה היא זו של סעיף 0128, שעליה כבר יושב
-- ראש צוות פנימי.
insert into task_assignments (task_id, profile_id, role, work_site, truck_id) values
  ('61000000-0000-0000-0000-000000032003', '20000000-0000-0000-0000-0000000032a5', 'driver',
   'warehouse', '7c000000-0000-0000-0000-0000003200f2');
update task_assignments set work_site = 'warehouse'
 where task_id = '61000000-0000-0000-0000-000000032003'
   and profile_id = '20000000-0000-0000-0000-0000000032a5' and role = 'team_lead';

select t_eq('וגם ראש הצוות הפנימי שנוהג מדווח ככזה',
  (select team_lead_drives from work_board_view
    where id = '61000000-0000-0000-0000-000000032003'), true);
select t_eq('עם המשאית שלו',
  (select team_lead_truck_name from work_board_view
    where id = '61000000-0000-0000-0000-000000032003'), 'משאית 32 ב');
select t_eq('ונקודת ההתחלה שלו היא של שורת הראשות',
  (select team_lead_work_site from work_board_view
    where id = '61000000-0000-0000-0000-000000032003'), 'warehouse');
