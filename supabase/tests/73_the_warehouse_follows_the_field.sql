\pset tuples_only on
\pset format unaligned

-- ===========================================================================
-- ‏73: לו״ז המחסן נגזר מהשטח (0226) — הכנה 3 ימים לפני ההקמה, החזרה לפי
-- שעת הסיום בשטח (עד 10:00 באותו יום, אחרת למחרת), עריכה בשטח מנקה יום
-- ידני, ובדף האירוע — `warehouse_event_tasks`.
--
-- החלון הוא current_date + 1200.
-- ===========================================================================

-- הסיד של הבדיקות מחזיר הרשאת הרצה לכל פונקציה; מה ש-0226 סגר נסגר כאן שוב.
revoke execute on function app.warehouse_rows(date, date, uuid) from anon, authenticated, public;
revoke execute on function app.warehouse_anchor_dates(uuid, date) from anon, authenticated, public;
revoke execute on function app.warehouse_follow_field() from anon, authenticated, public;

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000073a2', 'c73-arco-manager@vl.test'),
  ('00000000-0000-0000-0000-0000000073a4', 'c73-other-manager@vl.test'),
  ('00000000-0000-0000-0000-0000000073a5', 'c73-viewer@vl.test');

insert into customers (id, name, warehouse_schedule_enabled) values
  ('10000000-0000-0000-0000-00000000073a', 'ארקו 73', true),
  ('10000000-0000-0000-0000-00000000073b', 'לקוח רגיל 73', false);

insert into profiles (id, user_id, user_kind, is_admin, full_name, customer_id) values
  ('20000000-0000-0000-0000-0000000073a2', '00000000-0000-0000-0000-0000000073a2',
   'customer_user', false, 'מנהל אצל ארקו 73', '10000000-0000-0000-0000-00000000073a'),
  ('20000000-0000-0000-0000-0000000073a4', '00000000-0000-0000-0000-0000000073a4',
   'customer_user', false, 'מנהל אצל לקוח רגיל 73', '10000000-0000-0000-0000-00000000073b'),
  ('20000000-0000-0000-0000-0000000073a5', '00000000-0000-0000-0000-0000000073a5',
   'customer_user', false, 'צופה אצל ארקו 73', '10000000-0000-0000-0000-00000000073a');

insert into profile_roles (profile_id, role_id)
select p, id from permission_roles r,
  unnest(array['20000000-0000-0000-0000-0000000073a2'::uuid,
               '20000000-0000-0000-0000-0000000073a4'::uuid]) p
where r.key = 'customer_manager';
insert into profile_roles (profile_id, role_id)
select '20000000-0000-0000-0000-0000000073a5', id from permission_roles where key = 'customer_viewer';

insert into events (id, customer_id, event_number, event_date, end_client_name, status_id) values
  ('30000000-0000-0000-0000-00000000073a', '10000000-0000-0000-0000-00000000073a',
   '73001', current_date + 1200, 'קצה 73',
   (select id from statuses where entity = 'event' and code = 'pending' and deleted_at is null)),
  ('30000000-0000-0000-0000-00000000073b', '10000000-0000-0000-0000-00000000073b',
   '73002', current_date + 1200, 'קצה אחר 73',
   (select id from statuses where entity = 'event' and code = 'pending' and deleted_at is null));

-- ההקמה יום לפני האירוע, הפירוק יום אחריו, 06:00 לארבע שעות — מסתיים ב-10:00.
update tasks set task_date = current_date + 1199
 where event_id = '30000000-0000-0000-0000-00000000073a'
   and task_type_id = (select id from task_types where code = 'setup' limit 1);
update tasks set task_date = current_date + 1201, onsite_start_time = '06:00', hours_count = 4
 where event_id = '30000000-0000-0000-0000-00000000073a'
   and task_type_id = (select id from task_types where code = 'teardown' limit 1);

create or replace function pg_temp.wh73() returns text language sql as $$
  select string_agg(kind::text || '@' || (task_date - current_date)::text
                    || case when date_is_manual then '!' else '' end, ',' order by kind)
    from warehouse_schedule(current_date + 1180, current_date + 1220)
   where event_id = '30000000-0000-0000-0000-00000000073a'
$$;

-- ===== 1. הכלל ============================================================

\echo '--- הכנה 3 ימים לפני ההקמה, החזרה לפי שעת הסיום ---'
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000073a2', false);
select t_eq('סיום ב-10:00 בדיוק — החזרה ביום הפירוק', pg_temp.wh73(), 'prep@1196,return@1201');
reset role;
select set_config('request.jwt.claim.sub', '', false);

update tasks set hours_count = 4.5
 where event_id = '30000000-0000-0000-0000-00000000073a'
   and task_type_id = (select id from task_types where code = 'teardown' limit 1);
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000073a2', false);
select t_eq('סיום ב-10:30 — למחרת', pg_temp.wh73(), 'prep@1196,return@1202');
reset role;
select set_config('request.jwt.claim.sub', '', false);

update tasks set onsite_start_time = '22:00', hours_count = 5
 where event_id = '30000000-0000-0000-0000-00000000073a'
   and task_type_id = (select id from task_types where code = 'teardown' limit 1);
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000073a2', false);
select t_eq('פירוק שחוצה חצות ומסתיים ב-03:00 — ביום הסיום', pg_temp.wh73(), 'prep@1196,return@1202');
reset role;
select set_config('request.jwt.claim.sub', '', false);

update tasks set onsite_start_time = null
 where event_id = '30000000-0000-0000-0000-00000000073a'
   and task_type_id = (select id from task_types where code = 'teardown' limit 1);
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000073a2', false);
select t_eq('פירוק בלי שעה — למחרת', pg_temp.wh73(), 'prep@1196,return@1202');
reset role;
select set_config('request.jwt.claim.sub', '', false);

update tasks set onsite_start_time = '07:00', hours_count = 2
 where event_id = '30000000-0000-0000-0000-00000000073a'
   and task_type_id = (select id from task_types where code = 'teardown' limit 1);

-- ===== 2. עריכה בשטח מנקה יום ידני ========================================

\echo '--- יום ידני מתנקה כשההקמה או הפירוק זזים ---'
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000073a2', false);
select t_expect_ok('המחסן קובע יום להכנה', $$
  select warehouse_task_save('30000000-0000-0000-0000-00000000073a', 'prep',
    jsonb_build_object('task_date', (current_date + 1190)::text, 'notes', 'נשאר'))$$);
select t_expect_ok('ולהחזרה', $$
  select warehouse_task_save('30000000-0000-0000-0000-00000000073a', 'return',
    jsonb_build_object('task_date', (current_date + 1210)::text))$$);
select t_eq('הימים הידניים בתוקף', pg_temp.wh73(), 'prep@1190!,return@1210!');
reset role;
select set_config('request.jwt.claim.sub', '', false);

update tasks set task_date = current_date + 1198
 where event_id = '30000000-0000-0000-0000-00000000073a'
   and task_type_id = (select id from task_types where code = 'setup' limit 1);
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000073a2', false);
select t_eq('ההקמה זזה — ההכנה חוזרת לנגזר, ההחזרה נשארת', pg_temp.wh73(), 'prep@1195,return@1210!');
select t_eq('וההערה לא נמחקה',
  (select notes from warehouse_schedule(current_date + 1180, current_date + 1220)
    where event_id = '30000000-0000-0000-0000-00000000073a' and kind = 'prep'), 'נשאר');
reset role;
select set_config('request.jwt.claim.sub', '', false);

update tasks set notes = 'רק הערה'
 where event_id = '30000000-0000-0000-0000-00000000073a'
   and task_type_id = (select id from task_types where code = 'teardown' limit 1);
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000073a2', false);
select t_eq('שינוי שאינו יום או שעה אינו נוגע', pg_temp.wh73(), 'prep@1195,return@1210!');
reset role;
select set_config('request.jwt.claim.sub', '', false);

update tasks set hours_count = 5
 where event_id = '30000000-0000-0000-0000-00000000073a'
   and task_type_id = (select id from task_types where code = 'teardown' limit 1);
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000073a2', false);
select t_eq('שעות הפירוק השתנו — ההחזרה חוזרת לנגזר (07:00+5 = 12:00 → למחרת)',
  pg_temp.wh73(), 'prep@1195,return@1202');
reset role;
select set_config('request.jwt.claim.sub', '', false);

-- ===== 3. בדף האירוע ======================================================

\echo '--- warehouse_event_tasks ---'
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000073a2', false);
select t_eq('מנהל ארקו רואה את שתי המשימות של האירוע',
  (select string_agg(kind::text || '@' || (task_date - current_date)::text, ',' order by kind)
     from warehouse_event_tasks('30000000-0000-0000-0000-00000000073a')), 'prep@1195,return@1202');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000073a5', false);
select t_eq('וגם הצופה אצל ארקו',
  (select count(*)::int from warehouse_event_tasks('30000000-0000-0000-0000-00000000073a')), 2);
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000073a4', false);
select t_eq('לקוח אחר אינו רואה את של ארקו',
  (select count(*)::int from warehouse_event_tasks('30000000-0000-0000-0000-00000000073a')), 0);
select t_eq('ולא לאירוע של עצמו — המודול סגור לו',
  (select count(*)::int from warehouse_event_tasks('30000000-0000-0000-0000-00000000073b')), 0);
select t_expect_fail('והפונקציה הפנימית סגורה', $$
  select * from app.warehouse_rows(null, null, '30000000-0000-0000-0000-00000000073a')$$);
reset role;
select set_config('request.jwt.claim.sub', '', false);
