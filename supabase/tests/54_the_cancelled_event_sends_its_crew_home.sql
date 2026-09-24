\pset tuples_only on
\pset format unaligned

-- ===========================================================================
-- 54: אירוע שבוטל או נמחק משחרר את מי שהיה משובץ אליו (0200).
--
-- החלון הוא current_date + 820, מעבר לכל טווח קודם — פרט לאירוע אחד שיושב
-- במכוון לפני היום, כי כל הבדיקה שלו היא שמשימה שעברה אינה משתחררת.
-- ===========================================================================

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000054a1', 'c54-admin@vl.test'),
  ('00000000-0000-0000-0000-0000000054a2', 'c54-worker@vl.test'),
  ('00000000-0000-0000-0000-0000000054a3', 'c54-driver@vl.test'),
  ('00000000-0000-0000-0000-0000000054a4', 'c54-kmanager@vl.test'),
  ('00000000-0000-0000-0000-0000000054a5', 'c54-kworker@vl.test'),
  ('00000000-0000-0000-0000-0000000054a6', 'c54-crew@vl.test'),
  ('00000000-0000-0000-0000-0000000054a7', 'c54-customer@vl.test');

insert into customers (id, name, performed_by_enabled) values
  ('10000000-0000-0000-0000-00000000054a', 'לקוח 54', true);

insert into contractors (id, name) values
  ('40000000-0000-0000-0000-00000000054a', 'קבלן 54');

insert into contractor_workers (id, contractor_id, full_name, user_id) values
  ('50000000-0000-0000-0000-00000000054a', '40000000-0000-0000-0000-00000000054a',
   'עובד הקבלן 54', '00000000-0000-0000-0000-0000000054a5');

insert into customer_workers (id, customer_id, full_name) values
  ('cf000000-0000-0000-0000-0000005400a1', '10000000-0000-0000-0000-00000000054a', 'עובד הלקוח 54');

insert into profiles (id, user_id, user_kind, is_admin, full_name) values
  ('20000000-0000-0000-0000-0000000054a1', '00000000-0000-0000-0000-0000000054a1', 'staff', true,  'מנהל 54'),
  ('20000000-0000-0000-0000-0000000054a2', '00000000-0000-0000-0000-0000000054a2', 'staff', false, 'עובד 54'),
  ('20000000-0000-0000-0000-0000000054a3', '00000000-0000-0000-0000-0000000054a3', 'staff', false, 'נהג 54');
insert into profiles (id, user_id, user_kind, is_admin, full_name, contractor_id) values
  ('20000000-0000-0000-0000-0000000054a4', '00000000-0000-0000-0000-0000000054a4',
   'contractor_user', false, 'מנהל הקבלן 54', '40000000-0000-0000-0000-00000000054a');
insert into profiles (id, user_id, user_kind, is_admin, full_name, contractor_id, contractor_worker_id) values
  ('20000000-0000-0000-0000-0000000054a5', '00000000-0000-0000-0000-0000000054a5',
   'contractor_user', false, 'עובד הקבלן 54', '40000000-0000-0000-0000-00000000054a',
   '50000000-0000-0000-0000-00000000054a');
insert into profiles (id, user_id, user_kind, is_admin, full_name, customer_id, customer_worker_id) values
  ('20000000-0000-0000-0000-0000000054a6', '00000000-0000-0000-0000-0000000054a6',
   'customer_user', false, 'עובד הלקוח 54', '10000000-0000-0000-0000-00000000054a',
   'cf000000-0000-0000-0000-0000005400a1');
insert into profiles (id, user_id, user_kind, is_admin, full_name, customer_id) values
  ('20000000-0000-0000-0000-0000000054a7', '00000000-0000-0000-0000-0000000054a7',
   'customer_user', false, 'הלקוח 54', '10000000-0000-0000-0000-00000000054a');

-- התפקידים הצרים: העובד והנהג רואים רק את מה ששובצו אליו, מנהל הקבלן מחזיק
-- את portal.view, ועובד הקבלן לא — כדי שלא ייספר כמנהל (0110).
insert into profile_roles (profile_id, role_id)
select p.pid, r.id from (values
  ('20000000-0000-0000-0000-0000000054a2'::uuid, 'worker'),
  ('20000000-0000-0000-0000-0000000054a3'::uuid, 'driver'),
  ('20000000-0000-0000-0000-0000000054a4'::uuid, 'contractor_manager'),
  ('20000000-0000-0000-0000-0000000054a5'::uuid, 'contractor_worker'),
  ('20000000-0000-0000-0000-0000000054a6'::uuid, 'customer_worker')
) as p(pid, key) join permission_roles r on r.key = p.key;
insert into user_permission_grants (profile_id, permission_key, allowed) values
  ('20000000-0000-0000-0000-0000000054a7', 'events.edit', true),
  ('20000000-0000-0000-0000-0000000054a7', 'events.change_status', true);

-- שישה אירועים. לכל אחד ההקמה והפירוק של create_default_tasks (0009).
insert into events (id, customer_id, event_number, event_date, end_client_name, status_id)
select v.id, '10000000-0000-0000-0000-00000000054a', v.num, v.d, 'קצה ' || v.num,
       (select id from statuses where entity = 'event' and code = 'pending' and deleted_at is null)
from (values
  ('30000000-0000-0000-0000-0000000054e1'::uuid, 'EV-54-1', current_date + 820),  -- מבוטל בידי המשרד
  ('30000000-0000-0000-0000-0000000054e2'::uuid, 'EV-54-2', current_date + 821),  -- נמחק
  ('30000000-0000-0000-0000-0000000054e3'::uuid, 'EV-54-3', current_date + 822),  -- מבוטל בידי הלקוח
  ('30000000-0000-0000-0000-0000000054e4'::uuid, 'EV-54-4', current_date - 2),    -- עבר, ועם משמרת פתוחה
  ('30000000-0000-0000-0000-0000000054e5'::uuid, 'EV-54-5', current_date + 824),  -- האצלה ששולמה
  ('30000000-0000-0000-0000-0000000054e6'::uuid, 'EV-54-6', current_date + 825)   -- חי, להסרה רגילה
) as v(id, num, d);

create temp table t54 (k text primary key, id uuid);
insert into t54
select 'e' || right(e.event_number, 1) || '_' || tt.code, t.id
  from tasks t
  join events e on e.id = t.event_id
  join task_types tt on tt.id = t.task_type_id
 where e.event_number like 'EV-54-%';
grant select on t54 to authenticated;

-- ההקמה של כל אירוע משובצת; הפירוק נשאר טיוטה. תאריך המשימה הוא תאריך
-- האירוע, כדי שמשימות אירוע 4 יישבו באמת לפני היום.
update tasks t
   set status_id = (select id from statuses where entity = 'task' and code = 'assigned' and deleted_at is null),
       task_date = e.event_date, onsite_start_time = '08:00', hours_count = 4
  from events e
 where e.id = t.event_id and e.event_number like 'EV-54-%'
   and t.task_type_id = (select id from task_types where code = 'setup' limit 1);
update tasks t set task_date = e.event_date
  from events e
 where e.id = t.event_id and e.event_number like 'EV-54-%'
   and t.task_type_id = (select id from task_types where code = 'teardown' limit 1);

-- באירוע 4 הפירוק עתידי ומשובץ, ויש עליו משמרת בשעון.
update tasks
   set status_id = (select id from statuses where entity = 'task' and code = 'assigned' and deleted_at is null),
       task_date = current_date + 823
 where id = (select id from t54 where k = 'e4_teardown');

-- הצוות. באירוע 1 — כל סוגי השיבוץ, וגם שיבוץ על הטיוטה.
insert into task_assignments (task_id, profile_id, role, work_site)
select (select id from t54 where k = v.k), v.p, v.r::assignment_role, 'field'
from (values
  ('e1_setup',    '20000000-0000-0000-0000-0000000054a2'::uuid, 'worker'),
  ('e1_setup',    '20000000-0000-0000-0000-0000000054a3'::uuid, 'driver'),
  ('e1_teardown', '20000000-0000-0000-0000-0000000054a2'::uuid, 'worker'),
  ('e2_setup',    '20000000-0000-0000-0000-0000000054a2'::uuid, 'worker'),
  ('e3_setup',    '20000000-0000-0000-0000-0000000054a3'::uuid, 'worker'),
  ('e4_setup',    '20000000-0000-0000-0000-0000000054a2'::uuid, 'worker'),
  ('e4_teardown', '20000000-0000-0000-0000-0000000054a3'::uuid, 'worker'),
  ('e5_setup',    '20000000-0000-0000-0000-0000000054a2'::uuid, 'worker'),
  ('e6_setup',    '20000000-0000-0000-0000-0000000054a3'::uuid, 'worker')
) as v(k, p, r);

insert into task_contractor_terms (task_id, contractor_id, price)
values ((select id from t54 where k = 'e1_setup'), '40000000-0000-0000-0000-00000000054a', 500),
       ((select id from t54 where k = 'e5_setup'), '40000000-0000-0000-0000-00000000054a', 700);
update task_contractor_terms set paid_at = now(), paid_amount = 700
 where task_id = (select id from t54 where k = 'e5_setup');

insert into task_contractor_workers (task_id, contractor_worker_id)
values ((select id from t54 where k = 'e1_setup'), '50000000-0000-0000-0000-00000000054a');

insert into task_customer_workers (task_id, customer_worker_id)
values ((select id from t54 where k = 'e1_setup'), 'cf000000-0000-0000-0000-0000005400a1');

insert into attendance_entries (profile_id, work_date, task_ids, clock_in_at)
values ('20000000-0000-0000-0000-0000000054a3', current_date + 823,
        array[(select id from t54 where k = 'e4_teardown')], now());

-- מכאן נספרות רק ההתראות שהביטול עצמו מוציא.
delete from notifications where recipient_id in (
  select id from profiles where full_name like '%54');

-- ===== 1. המשרד מבטל ======================================================

\echo '--- 1. המשרד מבטל אירוע ---'
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000054a1', false);
select t_expect_ok('המנהל מבטל את אירוע 1', $$
  select update_event('30000000-0000-0000-0000-0000000054e1',
    jsonb_build_object('status_id',
      (select id from statuses where entity = 'event' and code = 'cancelled' and deleted_at is null)))$$);
reset role;
select set_config('request.jwt.claim.sub', '', false);

select t_eq('הסגל ירד מההקמה המשובצת',
  (select count(*)::int from task_assignments where task_id = (select id from t54 where k = 'e1_setup')), 0);
select t_eq('עובד הקבלן ירד ממנה',
  (select count(*)::int from task_contractor_workers where task_id = (select id from t54 where k = 'e1_setup')), 0);
select t_eq('סגל הלקוח ירד ממנה',
  (select count(*)::int from task_customer_workers where task_id = (select id from t54 where k = 'e1_setup')), 0);
select t_eq('וההאצלה לקבלן ירדה',
  (select count(*)::int from task_contractor_terms where task_id = (select id from t54 where k = 'e1_setup')), 0);
select t_eq('הפירוק בטיוטה נשאר עם הצוות שתוכנן לו',
  (select count(*)::int from task_assignments where task_id = (select id from t54 where k = 'e1_teardown')), 1);
select t_eq('המשימה עצמה לא נמחקה ולא זזה מהסטטוס שלה',
  (select s.code from tasks t join statuses s on s.id = t.status_id
    where t.id = (select id from t54 where k = 'e1_setup') and t.deleted_at is null), 'assigned');

select t_eq('העובד שמע: "האירוע בוטל — השיבוץ שלך בוטל"',
  (select string_agg(title, ' | ') from notifications
    where recipient_id = '20000000-0000-0000-0000-0000000054a2'
      and entity_id = (select id from t54 where k = 'e1_setup')),
  'האירוע בוטל — השיבוץ שלך בוטל');
select t_eq('וגם הנהג, פעם אחת',
  (select count(*)::int from notifications
    where recipient_id = '20000000-0000-0000-0000-0000000054a3' and type = 'assignment_removed'
      and title = 'האירוע בוטל — השיבוץ שלך בוטל'
      and entity_id = (select id from t54 where k = 'e1_setup')), 1);
select t_eq('עובד הקבלן שמע',
  (select count(*)::int from notifications
    where recipient_id = '20000000-0000-0000-0000-0000000054a5' and type = 'assignment_removed'
      and title = 'האירוע בוטל — השיבוץ שלך בוטל'), 1);
select t_eq('עובד הלקוח שמע',
  (select count(*)::int from notifications
    where recipient_id = '20000000-0000-0000-0000-0000000054a6' and type = 'assignment_removed'
      and title = 'האירוע בוטל — השיבוץ שלך בוטל'), 1);
select t_eq('מנהל הקבלן שמע שהמשימה הוסרה ממנו',
  (select count(*)::int from notifications
    where recipient_id = '20000000-0000-0000-0000-0000000054a4' and type = 'task_unpublished'
      and title = 'האירוע בוטל — המשימה הוסרה מהקבלן שלך'), 1);
select t_eq('על הטיוטה לא יצאה התראה — העובד לא ידע עליה',
  (select count(*)::int from notifications
    where entity_id = (select id from t54 where k = 'e1_teardown')), 0);
select t_eq('ומי שביטל לא שמע על זה',
  (select count(*)::int from notifications
    where recipient_id = '20000000-0000-0000-0000-0000000054a1'
      and entity_id = (select id from t54 where k = 'e1_setup')), 0);

\echo '--- ומעכשיו הם לא רואים את המשימה ---'
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000054a2', false);
select t_eq('העובד אינו רואה את ההקמה',
  (select count(*)::int from tasks where id = (select id from t54 where k = 'e1_setup')), 0);
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000054a5', false);
select t_eq('עובד הקבלן אינו רואה אותה',
  (select count(*)::int from tasks where id = (select id from t54 where k = 'e1_setup')), 0);
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000054a4', false);
select t_eq('מנהל הקבלן אינו רואה אותה',
  (select count(*)::int from tasks where id = (select id from t54 where k = 'e1_setup')), 0);
reset role;
select set_config('request.jwt.claim.sub', '', false);

select t_eq('ואין להם משמרת ביום ההקמה',
  (select count(*)::int
     from unnest(array['20000000-0000-0000-0000-0000000054a2'::uuid,
                       '20000000-0000-0000-0000-0000000054a3'::uuid,
                       '20000000-0000-0000-0000-0000000054a5'::uuid,
                       '20000000-0000-0000-0000-0000000054a6'::uuid]) p,
          app.planned_shifts(p, current_date + 820, current_date + 820)), 0);

\echo '--- מחיקה של אירוע שכבר בוטל אינה מדברת שוב ---'
select t_expect_ok('אירוע 1 נמחק', $$
  update events set deleted_at = now() where id = '30000000-0000-0000-0000-0000000054e1'$$);
select t_eq('אין התראה שנייה לעובד',
  (select count(*)::int from notifications
    where recipient_id = '20000000-0000-0000-0000-0000000054a2' and type = 'assignment_removed'), 1);

-- ===== 2. מחיקה ============================================================

\echo '--- 2. מחיקת אירוע ---'
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000054a1', false);
select t_expect_ok('המנהל מוחק את אירוע 2', $$
  select soft_delete('events', '30000000-0000-0000-0000-0000000054e2')$$);
reset role;
select set_config('request.jwt.claim.sub', '', false);

select t_eq('הסגל ירד מההקמה של האירוע שנמחק',
  (select count(*)::int from task_assignments where task_id = (select id from t54 where k = 'e2_setup')), 0);
select t_eq('והעובד שמע',
  (select count(*)::int from notifications
    where recipient_id = '20000000-0000-0000-0000-0000000054a2'
      and entity_id = (select id from t54 where k = 'e2_setup')
      and title = 'האירוע בוטל — השיבוץ שלך בוטל'), 1);

-- ===== 3. הלקוח מבטל ======================================================

\echo '--- 3. הלקוח מבטל את האירוע שלו ---'
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000054a7', false);
select t_expect_ok('הלקוח מבטל את אירוע 3', $$
  select update_event('30000000-0000-0000-0000-0000000054e3',
    jsonb_build_object('status_id',
      (select id from statuses where entity = 'event' and code = 'cancelled' and deleted_at is null)))$$);
reset role;
select set_config('request.jwt.claim.sub', '', false);

select t_eq('גם ביטול של לקוח מוריד את הסגל — אף שאין לו גישה לשיבוצים',
  (select count(*)::int from task_assignments where task_id = (select id from t54 where k = 'e3_setup')), 0);
select t_eq('והנהג שמע',
  (select count(*)::int from notifications
    where recipient_id = '20000000-0000-0000-0000-0000000054a3'
      and entity_id = (select id from t54 where k = 'e3_setup')
      and title = 'האירוע בוטל — השיבוץ שלך בוטל'), 1);

-- ===== 4. מה שנשאר ========================================================

\echo '--- 4. משימה שעברה, ומשימה שנפתחה עליה משמרת ---'
update events set status_id = (select id from statuses where entity = 'event' and code = 'cancelled' and deleted_at is null)
 where id = '30000000-0000-0000-0000-0000000054e4';

select t_eq('משימה שעברה נשארת עם הצוות שלה',
  (select count(*)::int from task_assignments where task_id = (select id from t54 where k = 'e4_setup')), 1);
select t_eq('ומשימה שכבר החתימו עליה נשארת',
  (select count(*)::int from task_assignments where task_id = (select id from t54 where k = 'e4_teardown')), 1);
select t_eq('ואף אחד לא שמע עליהן',
  (select count(*)::int from notifications
    where entity_id in (select id from t54 where k like 'e4_%')), 0);

\echo '--- האצלה ששולמה ---'
update events set status_id = (select id from statuses where entity = 'event' and code = 'cancelled' and deleted_at is null)
 where id = '30000000-0000-0000-0000-0000000054e5';

select t_eq('הסגל ירד',
  (select count(*)::int from task_assignments where task_id = (select id from t54 where k = 'e5_setup')), 0);
select t_eq('וההאצלה ששולמה נשארת כרישום כספי',
  (select count(*)::int from task_contractor_terms
    where task_id = (select id from t54 where k = 'e5_setup') and paid_at is not null), 1);

-- ===== 5. הנוסח הרגיל לא נפגע =============================================

\echo '--- 5. הסרה רגילה אחרי ביטול באותה טרנזקציה ---'
begin;
update events set status_id = (select id from statuses where entity = 'event' and code = 'approved' and deleted_at is null)
 where id = '30000000-0000-0000-0000-0000000054e3';
update events set status_id = (select id from statuses where entity = 'event' and code = 'cancelled' and deleted_at is null)
 where id = '30000000-0000-0000-0000-0000000054e3';
delete from task_assignments where task_id = (select id from t54 where k = 'e6_setup');
commit;

select t_eq('הסרה שאינה מביטול נשארת "השיבוץ שלך בוטל"',
  (select string_agg(title, ' | ') from notifications
    where recipient_id = '20000000-0000-0000-0000-0000000054a3'
      and entity_id = (select id from t54 where k = 'e6_setup')),
  'השיבוץ שלך בוטל');

-- ‏0200 שולל את EXECUTE על app.release_event_crew מכל תפקיד, ו**אי אפשר לאשר
-- את זה כאן**: ‏`01_seed.sql:9` מעניק execute על כל הפונקציות ל-authenticated
-- אחרי המיגרציות (ראו 49 §12). מה שנבדק למעלה הוא שכל שלוש הדלתות — ביטול של
-- המשרד, מחיקה, וביטול של הלקוח — מגיעות לשחרור דרך הטריגר בלבד.
