\pset tuples_only on
\pset format unaligned

-- ===========================================================================
-- ‏61: המשימות יוצאות עם האירוע (0209).
--
-- החבילה מקימה לקוח ושלושה אירועים משלה ב-`current_date + 1010`, מעבר לכל
-- טווח אחר, ומשתמשת בבעל המערכת ובמנהל אצל הלקוח מ-01. לכל אירוע שתי
-- המשימות האוטומטיות של 0009 (הקמה ופירוק).
--
--   א — נמחק ומשוחזר בידי בעל המערכת; לפני כן נמחקה לו משימה שלישית, לבד.
--   ב — מסומן כמחוק כשהטריגר כבוי: רק `app.live_tasks` עומדת בדרך.
--   ג — של "אקמי הפקות", נמחק בידי המנהל אצל הלקוח.
-- ===========================================================================

insert into customers (id, name) values
  ('10000000-0000-0000-0000-0000000061a0', 'לקוח 61');

-- המנהל אצל הלקוח רשאי למחוק אירוע של הלקוח שלו
insert into user_permission_grants (profile_id, permission_key, allowed) values
  ('20000000-0000-0000-0000-0000000000c1', 'events.delete', true)
on conflict do nothing;

create temp table t61 as
select current_date + 1010 as d;
grant select on t61 to authenticated;

insert into events (id, customer_id, end_client_name, event_number, event_date, status_id)
select v.id, v.customer, v.name, v.num, (select d from t61),
       (select id from statuses where entity = 'event' and code = 'planned' and deleted_at is null)
from (values
  ('30000000-0000-0000-0000-0000000061e1'::uuid, '10000000-0000-0000-0000-0000000061a0'::uuid, 'אירוע א 61', 'EV-61-A'),
  ('30000000-0000-0000-0000-0000000061e2'::uuid, '10000000-0000-0000-0000-0000000061a0'::uuid, 'אירוע ב 61', 'EV-61-B'),
  ('30000000-0000-0000-0000-0000000061e3'::uuid, '10000000-0000-0000-0000-000000000001'::uuid, 'אירוע ג 61', 'EV-61-C')
) v(id, customer, name, num);

-- משימה שלישית לאירוע א, שנמחקה לבד אתמול
insert into tasks (id, event_id, customer_id, task_type_id, task_date, status_id, deleted_at)
values ('40000000-0000-0000-0000-0000000061f1', '30000000-0000-0000-0000-0000000061e1',
        '10000000-0000-0000-0000-0000000061a0',
        (select id from task_types where code = 'setup' limit 1), (select d from t61),
        (select status_id from tasks where event_id = '30000000-0000-0000-0000-0000000061e1' limit 1),
        now() - interval '1 day');


\echo '--- 1. המצב ההתחלתי ---'

select t_eq('לכל אירוע שתי משימות חיות',
  (select count(*) from app.live_tasks
    where event_id in ('30000000-0000-0000-0000-0000000061e1',
                       '30000000-0000-0000-0000-0000000061e2',
                       '30000000-0000-0000-0000-0000000061e3')), 6::bigint);


\echo '--- 2. מחיקת אירוע מוחקת את המשימות שלו ---'

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false);

select t_expect_ok('בעל המערכת מוחק את אירוע א',
  $$select soft_delete('events', '30000000-0000-0000-0000-0000000061e1')$$);

reset role;

select t_eq('שתי המשימות של אירוע א מחוקות',
  (select count(*) from tasks
    where event_id = '30000000-0000-0000-0000-0000000061e1' and deleted_at is null), 0::bigint);
select t_eq('הן נמחקו בחותמת של האירוע',
  (select count(*) from tasks t join events e on e.id = t.event_id
    where e.id = '30000000-0000-0000-0000-0000000061e1' and t.deleted_at = e.deleted_at), 2::bigint);
select t_eq('הדשבורד אינו סופר את משימות אירוע א',
  (select count(*) from app.live_tasks where event_id = '30000000-0000-0000-0000-0000000061e1'), 0::bigint);

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false);

select t_eq('"משימות לפי לקוח" סופר ללקוח 61 רק את שתי המשימות של אירוע ב',
  (select (x ->> 'cnt')::int
     from jsonb_array_elements(dashboard_stats((select d from t61) - 1, (select d from t61) + 1)
                               -> 'by_customer') x
    where x ->> 'id' = '10000000-0000-0000-0000-0000000061a0'), 2);


\echo '--- 3. משימה של אירוע מחוק אינה משוחזרת לבד ---'

select t_expect_fail('שחזור משימה בודדת של אירוע מחוק נחסם',
  $$select soft_delete('tasks', (select id from tasks
                                  where event_id = '30000000-0000-0000-0000-0000000061e1'
                                    and id <> '40000000-0000-0000-0000-0000000061f1' limit 1), true)$$);


\echo '--- 4. שחזור האירוע מחזיר את מה שנמחק איתו ---'

select t_expect_ok('בעל המערכת משחזר את אירוע א',
  $$select soft_delete('events', '30000000-0000-0000-0000-0000000061e1', true)$$);

reset role;

select t_eq('שתי המשימות האוטומטיות חזרו',
  (select count(*) from tasks
    where event_id = '30000000-0000-0000-0000-0000000061e1' and deleted_at is null), 2::bigint);
select t_eq('המשימה שנמחקה לבד לפני כן נשארת מחוקה',
  (select deleted_at is not null from tasks where id = '40000000-0000-0000-0000-0000000061f1'), true);


\echo '--- 5. app.live_tasks לבדה: אירוע שסומן מחוק בלי הטריגר ---'

alter table events disable trigger events_z_tasks_follow_delete;
update events set deleted_at = now() where id = '30000000-0000-0000-0000-0000000061e2';
alter table events enable trigger events_z_tasks_follow_delete;

select t_eq('המשימות עצמן לא נמחקו (הטריגר היה כבוי)',
  (select count(*) from tasks
    where event_id = '30000000-0000-0000-0000-0000000061e2' and deleted_at is null), 2::bigint);
select t_eq('אבל app.live_tasks אינה מחזירה אותן',
  (select count(*) from app.live_tasks where event_id = '30000000-0000-0000-0000-0000000061e2'), 0::bigint);
select t_eq('ו-app.task_revenue דרכה אינה סופרת אותן',
  (select count(*) from app.task_revenue r join app.live_tasks t on t.id = r.task_id
    where t.event_id = '30000000-0000-0000-0000-0000000061e2'), 0::bigint);


\echo '--- 6. לקוח שמוחק אירוע שלו ---'

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000c1', false);

select t_expect_ok('המנהל אצל הלקוח מוחק את אירוע ג — המחיקה אינה נתקלת בהרשאות השדה של המשימה',
  $$select soft_delete('events', '30000000-0000-0000-0000-0000000061e3')$$);

reset role;

select t_eq('המשימות של אירוע ג נמחקו איתו',
  (select count(*) from tasks
    where event_id = '30000000-0000-0000-0000-0000000061e3' and deleted_at is null), 0::bigint);
select t_eq('כתיבת המערכת כבויה שוב בסוף',
  app.in_system_write(), false);
