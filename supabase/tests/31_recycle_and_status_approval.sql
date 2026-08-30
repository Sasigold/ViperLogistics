\pset tuples_only on
\pset format unaligned

-- ===========================================================================
-- 31: אירוע שנמחק יורד מהלו״ז (0123), ביטול יורד במחיקה (0123), מחיקה
--     לצמיתות (0124) שיודעת לנקות ולהסביר (0137), ושינוי סטטוס אינו מפיל
--     אישור (0125).
--
-- החלון הוא current_date + 470.
-- ===========================================================================

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000031a1', 'c31-admin@vl.test'),
  ('00000000-0000-0000-0000-0000000031a2', 'c31-office@vl.test'),
  ('00000000-0000-0000-0000-0000000031a5', 'c31-cust@vl.test');

insert into customers (id, name) values
  ('10000000-0000-0000-0000-00000000031a', 'לקוח 31');

insert into profiles (id, user_id, user_kind, is_admin, full_name) values
  ('20000000-0000-0000-0000-0000000031a1', '00000000-0000-0000-0000-0000000031a1', 'staff', true,  'מנהל 31'),
  ('20000000-0000-0000-0000-0000000031a2', '00000000-0000-0000-0000-0000000031a2', 'staff', false, 'רכז 31');
insert into profiles (id, user_id, user_kind, is_admin, full_name, customer_id) values
  ('20000000-0000-0000-0000-0000000031a5', '00000000-0000-0000-0000-0000000031a5', 'customer_user', false, 'לקוח 31',
   '10000000-0000-0000-0000-00000000031a');
insert into user_permission_grants (profile_id, permission_key, allowed) values
  ('20000000-0000-0000-0000-0000000031a5', 'events.edit', true);

-- אירוע א׳ — למחיקה ולסטטוס מבוטל
insert into events (id, customer_id, event_number, event_date, end_client_name, status_id)
values ('30000000-0000-0000-0000-00000000031a', '10000000-0000-0000-0000-00000000031a',
        'EV-31A', current_date + 470, 'קצה 31A',
        (select id from statuses where entity = 'event' and code = 'pending' and deleted_at is null));

\echo '--- אירוע חי מופיע בלו״ז ---'
select t_eq('לאירוע החי יש משימות בלו״ז',
  (select count(*)::int from work_board_view
    where event_id = '30000000-0000-0000-0000-00000000031a') >= 1, true);

\echo '--- ביטול יורד במחיקה, והלו״ז נקי ---'
update events set status_id = (select id from statuses where entity='event' and code='cancelled' and deleted_at is null)
 where id = '30000000-0000-0000-0000-00000000031a';
update events set deleted_at = now() where id = '30000000-0000-0000-0000-00000000031a';

select t_eq('הסטטוס אינו עוד "בוטל"',
  (select s.code from events e join statuses s on s.id = e.status_id
     where e.id = '30000000-0000-0000-0000-00000000031a') <> 'cancelled', true);
select t_eq('וחזר לברירת המחדל pending',
  (select s.code from events e join statuses s on s.id = e.status_id
     where e.id = '30000000-0000-0000-0000-00000000031a'), 'pending');
select t_eq('ואירוע שנמחק אינו בלו״ז',
  (select count(*)::int from work_board_view
    where event_id = '30000000-0000-0000-0000-00000000031a'), 0);

\echo '--- מחיקה לצמיתות: admin בלבד, ורק מהסל ---'
-- אירוע ב׳ חי — מחיקה לצמיתות שלו אמורה להיכשל
insert into events (id, customer_id, event_number, event_date, end_client_name, status_id)
values ('30000000-0000-0000-0000-00000000031b', '10000000-0000-0000-0000-00000000031a',
        'EV-31B', current_date + 471, 'קצה 31B',
        (select id from statuses where entity = 'event' and code = 'pending' and deleted_at is null));

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000031a2', false);
select t_expect_fail('רכז (לא-admin) אינו מוחק לצמיתות',
  $$select hard_delete('events', '30000000-0000-0000-0000-00000000031a')$$);
reset role;
select set_config('request.jwt.claim.sub', '', false);

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000031a1', false);
select t_expect_fail('אי אפשר למחוק לצמיתות אירוע חי',
  $$select hard_delete('events', '30000000-0000-0000-0000-00000000031b')$$);
select t_expect_ok('admin מוחק לצמיתות אירוע מהסל',
  $$select hard_delete('events', '30000000-0000-0000-0000-00000000031a')$$);
reset role;
select set_config('request.jwt.claim.sub', '', false);

select t_eq('האירוע נמחק לצמיתות',
  (select count(*)::int from events where id = '30000000-0000-0000-0000-00000000031a'), 0);

\echo '--- שינוי סטטוס אינו מפיל אישור, עריכת מפרט כן ---'
-- admin מאשר את אירוע ב׳
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000031a1', false);
select set_event_approved('30000000-0000-0000-0000-00000000031b', true);
reset role;
select set_config('request.jwt.claim.sub', '', false);

select t_eq('האירוע מאושר',
  (select approved_at is not null from events where id = '30000000-0000-0000-0000-00000000031b'), true);

-- הלקוח משנה רק סטטוס
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000031a5', false);
select update_event('30000000-0000-0000-0000-00000000031b',
  jsonb_build_object('status_id',
    (select id from statuses where entity='event' and code='active' and deleted_at is null)::text));
reset role;
select set_config('request.jwt.claim.sub', '', false);

select t_eq('שינוי סטטוס לא הפיל את האישור',
  (select approved_at is not null from events where id = '30000000-0000-0000-0000-00000000031b'), true);

-- הלקוח משנה שדה מפרט (הערות) — האישור יורד
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000031a5', false);
select update_event('30000000-0000-0000-0000-00000000031b',
  jsonb_build_object('notes', 'הלקוח שינה משהו מהותי'));
reset role;
select set_config('request.jwt.claim.sub', '', false);

select t_eq('אבל עריכת מפרט כן הפילה אותו',
  (select approved_at is null from events where id = '30000000-0000-0000-0000-00000000031b'), true);

-- ===== 0137: המחיקה לצמיתות מנקה מה שאפשר, וחוסמת בשם ===================
--
-- ‏0124 פתחה רשימה לבנה של שלוש-עשרה טבלאות וטיפלה בילד היחיד של `events`.
-- כאן נבדק מה קורה בשאר: משאית משובצת נמחקת אחרי שהיא מתפנה מהתכנון, ולקוח
-- עם אירועים אינו נמחק — עם הודעה שאומרת מה חוסם.

\echo '--- משאית שנמחקה מתפנה מהתכנון ---'
insert into trucks (id, name, plate_number) values
  ('70000000-0000-0000-0000-000000031001', 'משאית 31', '31-001-31');

insert into events (id, customer_id, event_number, event_date, end_client_name, status_id)
values ('30000000-0000-0000-0000-00000000031c', '10000000-0000-0000-0000-00000000031a',
        'EV-31C', current_date + 472, 'קצה 31C',
        (select id from statuses where entity = 'event' and code = 'pending' and deleted_at is null));

insert into tasks (id, event_id, customer_id, task_type_id, task_date, worker_count, status_id,
                   truck_id, truck_ids)
select '61000000-0000-0000-0000-000000031001', '30000000-0000-0000-0000-00000000031c',
       '10000000-0000-0000-0000-00000000031a', tt.id, current_date + 472, 2,
       (select id from statuses where entity = 'task' and code = 'draft' and deleted_at is null),
       '70000000-0000-0000-0000-000000031001',
       array['70000000-0000-0000-0000-000000031001'::uuid]
  from task_types tt where tt.code = 'setup' limit 1;

insert into task_assignments (task_id, profile_id, role, truck_id) values
  ('61000000-0000-0000-0000-000000031001', '20000000-0000-0000-0000-0000000031a2', 'driver',
   '70000000-0000-0000-0000-000000031001');

update trucks set deleted_at = now() where id = '70000000-0000-0000-0000-000000031001';

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000031a1', false);
select t_expect_ok('admin מוחק משאית לצמיתות (0137)',
  $$select hard_delete('trucks', '70000000-0000-0000-0000-000000031001')$$);
reset role;
select set_config('request.jwt.claim.sub', '', false);

select t_eq('המשאית נעלמה',
  (select count(*)::int from trucks where id = '70000000-0000-0000-0000-000000031001'), 0);
select t_eq('והמשימה נשארה, בלי משאית',
  (select truck_id from tasks where id = '61000000-0000-0000-0000-000000031001'), null::uuid);
select t_eq('וגם ממערך המשאיות',
  (select coalesce(array_length(truck_ids, 1), 0) from tasks
    where id = '61000000-0000-0000-0000-000000031001'), 0);
select t_eq('והשיבוץ של הנהג נשאר, בלי משאית',
  (select truck_id from task_assignments
    where task_id = '61000000-0000-0000-0000-000000031001'), null::uuid);

\echo '--- לקוח עם אירועים אינו נמחק, וההודעה אומרת למה ---'
update customers set deleted_at = now() where id = '10000000-0000-0000-0000-00000000031a';

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000031a1', false);
select t_expect_fail('לקוח עם אירועים נחסם',
  $$select hard_delete('customers', '10000000-0000-0000-0000-00000000031a')$$);
reset role;
select set_config('request.jwt.claim.sub', '', false);

select t_eq('והלקוח עדיין קיים',
  (select count(*)::int from customers where id = '10000000-0000-0000-0000-00000000031a'), 1);
update customers set deleted_at = null where id = '10000000-0000-0000-0000-00000000031a';

\echo '--- אירוע עם לוויינים נמחק לצמיתות עד הסוף ---'
insert into event_activity (event_id, kind, actor_profile_id, actor_name, note)
values ('30000000-0000-0000-0000-00000000031c', 'note',
        '20000000-0000-0000-0000-0000000031a1', 'מנהל 31', 'הערה שתלך עם האירוע');
insert into event_suppliers (event_id, supplier_id)
select '30000000-0000-0000-0000-00000000031c', s.id
  from (insert into suppliers (customer_id, name)
        values ('10000000-0000-0000-0000-00000000031a', 'ספק 31') returning id) s;

update events set deleted_at = now() where id = '30000000-0000-0000-0000-00000000031c';

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000031a1', false);
select t_expect_ok('admin מוחק לצמיתות אירוע עם משימות, יומן וספקים',
  $$select hard_delete('events', '30000000-0000-0000-0000-00000000031c')$$);
reset role;
select set_config('request.jwt.claim.sub', '', false);

select t_eq('האירוע נעלם',
  (select count(*)::int from events where id = '30000000-0000-0000-0000-00000000031c'), 0);
select t_eq('והמשימה שלו איתו',
  (select count(*)::int from tasks where id = '61000000-0000-0000-0000-000000031001'), 0);
select t_eq('וגם שורות היומן',
  (select count(*)::int from event_activity
    where event_id = '30000000-0000-0000-0000-00000000031c'), 0);
