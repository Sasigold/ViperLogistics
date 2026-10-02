\pset tuples_only on
\pset format unaligned

-- ===========================================================================
-- ‏57: מסך הקיר רואה את כל היום (0202).
--
-- החבילה מקימה לקוח, לקוח שארקו מבצעת אצלו, קבלן, שלושה אירועים, שבע דמויות
-- ושני רכבים משלה, ביום רביעי של אמצע יולי ארבע שנים קדימה — מעבר לכל טווח
-- אחר (+870), ובשעון קיץ: 21:30 UTC הוא כבר 00:30 של מחר בישראל. "עכשיו"
-- ננעץ ל-10:00 של אותו יום, ו-`app.wall_snapshot_at` נקראת איתו.
--
-- היום D, המשימות (D = רביעי, השבוע מתחיל ב-D-3):
--   T1  הקמה 08:00/09:00–13:00, משובצת, צריך 5: עובד א׳ (עובד + נהג — אדם
--       אחד), עובד ב׳, ראש צוות ועובד מהקבלן, עובד לקוח. משאית ונגרר.
--   T2  פירוק 18:00, מתוכנן, צריך 3, אין איש, ‏**מוסתרת מהלו״ז**.
--   T3  הקמה של ארקו (performed_by = 'arko').       — לא נספרת בכלל
--   T4  נמחקה.                                       — לא נספרת בכלל
--   T5  באירוע שבוטל.                                — לא נספרת בכלל
--   T6  הקמה ב-D+1 07:00, משובצת.
--   T7  סידור 08:30, משובצת, צריך 2: "מאחר 57" ו"בלי שעון 57".
--   T8  סידור 10:00, משובצת, צריך 2: ראש צוות אחד.
--   T9  הקמה ב-D+5, טיוטה, מחיר ידני 800 — לתחזית החודש.
--
-- ההחתמות: עובד א׳ פתוחה מ-08:00 (שעתיים עד עכשיו); עובד ב׳ סגורה 07:00–09:30
-- ומאושרת, ועוד 8 שעות ב-D-1; "שכח לצאת 57" פתוחה מ-D-1 06:00 — 28 שעות,
-- מעבר לסף של 16; "ממתין 57" סגורה וממתינה היום, ובקשת תיקון על D-2.
-- היא משאירה אחריה את כל זה, ואת הסוד ב-Vault.
-- ===========================================================================

-- היום: רביעי הראשון מ-15 ביולי, ארבע שנים קדימה. ביולי ישראל תמיד ב-UTC+3.
create or replace function t57_day() returns date language sql stable as $$
  select d + ((10 - extract(dow from d)::int) % 7)
    from (select make_date(extract(year from current_date)::int + 4, 7, 15) as d) x
$$;

-- שעה בישראל ביום D + p_offset
create or replace function t57_at(p_offset int, p_time time) returns timestamptz
language sql stable as $$
  select ((t57_day() + p_offset) + p_time) at time zone 'Asia/Jerusalem'
$$;

-- מה ש-SQLSTATE אמר — 'ok' כשלא נזרק דבר. רץ בזהות הקורא.
create or replace function t57_state(p_sql text) returns text language plpgsql as $$
begin
  execute p_sql;
  return 'ok';
exception when others then
  return sqlstate;
end $$;

-- ה-sha256 (hex) של סוד — מה שהוראות התפעול שמות ב-Vault
create or replace function t57_hash(p_secret text) returns text language sql immutable as $$
  select encode(sha256(convert_to(p_secret, 'UTF8')), 'hex')
$$;

-- מה שהדלת אומרת למי שמציג את הסוד — 'ok', או ה-SQLSTATE. רץ בזהות הקורא.
create or replace function t57_door(p_secret text) returns text language plpgsql as $$
begin
  return t57_state(format('select public.wall_snapshot(%L, 1)', p_secret));
end $$;

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000057b1', 'w57-worker@vl.test');

insert into customers (id, name, color) values
  ('10000000-0000-0000-0000-00000000057a', 'לקוח 57', '#0e7490');
insert into customers (id, name, performed_by_enabled) values
  ('10000000-0000-0000-0000-00000000057b', 'ארקו 57', true);

insert into contractors (id, name) values
  ('40000000-0000-0000-0000-00000000057a', 'קבלן 57');

insert into contractor_workers (id, contractor_id, full_name, phone) values
  ('50000000-0000-0000-0000-0000000057a1', '40000000-0000-0000-0000-00000000057a',
   'ראש צוות קבלן 57', '050-5700001'),
  ('50000000-0000-0000-0000-0000000057a2', '40000000-0000-0000-0000-00000000057a',
   'עובד קבלן 57', '050-5700002');

insert into customer_workers (id, customer_id, full_name) values
  ('cf000000-0000-0000-0000-0000005700a1', '10000000-0000-0000-0000-00000000057a', 'עובד לקוח 57');

insert into profiles (id, user_kind, is_admin, full_name, phone) values
  ('20000000-0000-0000-0000-0000000057a1', 'staff', false, 'עובד 57 א', '050-5711111'),
  ('20000000-0000-0000-0000-0000000057a2', 'staff', false, 'עובד 57 ב', null),
  ('20000000-0000-0000-0000-0000000057a3', 'staff', false, 'מאחר 57', null),
  ('20000000-0000-0000-0000-0000000057a4', 'staff', false, 'ראש צוות 57', null),
  ('20000000-0000-0000-0000-0000000057a5', 'staff', false, 'שכח לצאת 57', null),
  ('20000000-0000-0000-0000-0000000057a6', 'staff', false, 'ממתין 57', null),
  ('20000000-0000-0000-0000-0000000057a7', 'staff', false, 'בלי שעון 57', null);

-- עובד בתפקיד "עובד" (0079) עם כניסה — מי שאינו מחזיק את מפתחות הרווח
insert into profiles (id, user_id, user_kind, is_admin, full_name) values
  ('20000000-0000-0000-0000-0000000057b1', '00000000-0000-0000-0000-0000000057b1',
   'staff', false, 'עובד שטח 57');
insert into profile_roles (profile_id, role_id)
select '20000000-0000-0000-0000-0000000057b1', r.id from permission_roles r where r.key = 'worker';

-- השעון כבוי לו — הוא אינו מחתים, ולכן אינו "מאחר"
insert into worker_pay_settings (profile_id, clock_enabled) values
  ('20000000-0000-0000-0000-0000000057a7', false);

insert into trucks (id, name) values
  ('a5700000-0000-0000-0000-000000000001', 'משאית 57');

insert into events (id, customer_id, event_number, end_client_name, location_text, event_date, status_id)
select v.id::uuid, v.cust::uuid, v.num, v.client, v.loc, t57_day(),
       (select id from statuses where entity = 'event' and code = 'pending' and deleted_at is null)
  from (values
    ('30000000-0000-0000-0000-00000000057a', '10000000-0000-0000-0000-00000000057a', 'EV-57',   'חתונה 57', 'גני 57'),
    ('30000000-0000-0000-0000-00000000057b', '10000000-0000-0000-0000-00000000057a', 'EV-57-X', 'בוטל 57',  'אולם 57'),
    ('30000000-0000-0000-0000-00000000057c', '10000000-0000-0000-0000-00000000057b', 'EV-57-A', 'ארקו 57',  'אולם ארקו 57')) v(id, cust, num, client, loc);

-- ההקמה והפירוק שנולדים עם כל אירוע (0003) אינם חלק מהתרחיש
update tasks set deleted_at = now()
 where event_id in ('30000000-0000-0000-0000-00000000057a', '30000000-0000-0000-0000-00000000057b',
                    '30000000-0000-0000-0000-00000000057c');

insert into tasks (id, event_id, customer_id, task_type_id, task_date, title,
                   warehouse_start_time, onsite_start_time, hours_count, status_id,
                   worker_count, truck_ids, truck_free_text, hidden_on_board, performed_by)
select v.id::uuid, v.ev::uuid, v.cust::uuid,
       (select id from task_types where (v.type = 'סידור' and name = 'סידור')
                                     or (v.type <> 'סידור' and code = v.type) limit 1),
       t57_day() + v.off, v.title, v.wh::time, v.onsite::time, v.hours,
       (select id from statuses where entity = 'task' and code = v.status and deleted_at is null),
       v.need, v.trucks::uuid[], v.free, v.hidden, v.perf
  from (values
    ('62000000-0000-0000-0000-000000057001', '30000000-0000-0000-0000-00000000057a', '10000000-0000-0000-0000-00000000057a',
     'setup',    0, null::text,      '08:00', '09:00', 4.0, 'assigned', 5, '{a5700000-0000-0000-0000-000000000001}', 'נגרר 57', false, 'viper'),
    ('62000000-0000-0000-0000-000000057002', '30000000-0000-0000-0000-00000000057a', '10000000-0000-0000-0000-00000000057a',
     'teardown', 0, null,            null,    '18:00', 2.0, 'planned',  3, '{}', null, true, 'viper'),
    ('62000000-0000-0000-0000-000000057003', '30000000-0000-0000-0000-00000000057c', '10000000-0000-0000-0000-00000000057b',
     'setup',    0, null,            null,    '09:00', 3.0, 'draft',    3, '{}', null, false, 'arko'),
    ('62000000-0000-0000-0000-000000057004', '30000000-0000-0000-0000-00000000057a', '10000000-0000-0000-0000-00000000057a',
     'סידור',    0, 'נמחקה 57',      null,    '11:00', 2.0, 'planned',  2, '{}', null, false, 'viper'),
    ('62000000-0000-0000-0000-000000057005', '30000000-0000-0000-0000-00000000057b', '10000000-0000-0000-0000-00000000057a',
     'setup',    0, null,            null,    '12:00', 2.0, 'planned',  2, '{}', null, false, 'viper'),
    ('62000000-0000-0000-0000-000000057006', '30000000-0000-0000-0000-00000000057a', '10000000-0000-0000-0000-00000000057a',
     'setup',    1, null,            null,    '07:00', 3.0, 'assigned', 0, '{}', null, false, 'viper'),
    ('62000000-0000-0000-0000-000000057007', '30000000-0000-0000-0000-00000000057a', '10000000-0000-0000-0000-00000000057a',
     'סידור',    0, 'סידור במה 57',  null,    '08:30', 2.0, 'assigned', 2, '{}', null, false, 'viper'),
    ('62000000-0000-0000-0000-000000057008', '30000000-0000-0000-0000-00000000057a', '10000000-0000-0000-0000-00000000057a',
     'סידור',    0, 'ציוד במה 57',   null,    '10:00', 2.0, 'assigned', 2, '{}', null, false, 'viper'),
    ('62000000-0000-0000-0000-000000057009', '30000000-0000-0000-0000-00000000057a', '10000000-0000-0000-0000-00000000057a',
     'setup',    5, null,            null,    '09:00', 2.0, 'draft',    0, '{}', null, false, 'viper')
  ) v(id, ev, cust, type, off, title, wh, onsite, hours, status, need, trucks, free, hidden, perf);

update tasks set deleted_at = now() where id = '62000000-0000-0000-0000-000000057004';

-- עובד א׳: עובד מהמחסן וגם הנהג — שתי שורות, אדם אחד.
insert into task_assignments (task_id, profile_id, role, work_site) values
  ('62000000-0000-0000-0000-000000057001', '20000000-0000-0000-0000-0000000057a1', 'worker',    'warehouse'),
  ('62000000-0000-0000-0000-000000057001', '20000000-0000-0000-0000-0000000057a1', 'driver',    'field'),
  ('62000000-0000-0000-0000-000000057001', '20000000-0000-0000-0000-0000000057a2', 'worker',    'field'),
  ('62000000-0000-0000-0000-000000057007', '20000000-0000-0000-0000-0000000057a3', 'worker',    'field'),
  ('62000000-0000-0000-0000-000000057007', '20000000-0000-0000-0000-0000000057a7', 'worker',    'field'),
  ('62000000-0000-0000-0000-000000057008', '20000000-0000-0000-0000-0000000057a4', 'team_lead', 'field');

insert into task_contractor_terms (task_id, contractor_id, price)
values ('62000000-0000-0000-0000-000000057001', '40000000-0000-0000-0000-00000000057a', 800);

insert into task_contractor_workers (task_id, contractor_worker_id, role, work_site) values
  ('62000000-0000-0000-0000-000000057001', '50000000-0000-0000-0000-0000000057a1', 'team_lead', 'field'),
  ('62000000-0000-0000-0000-000000057001', '50000000-0000-0000-0000-0000000057a2', 'worker',    'field');

insert into task_customer_workers (task_id, customer_worker_id, work_site)
values ('62000000-0000-0000-0000-000000057001', 'cf000000-0000-0000-0000-0000005700a1', 'field');

-- מחירים ידניים: מה שחי נספר, ומה שנמחק או שאירועו בוטל — לא.
insert into task_pricing (task_id, price, is_manual) values
  ('62000000-0000-0000-0000-000000057001', 1200, true),
  ('62000000-0000-0000-0000-000000057004', 7000, true),
  ('62000000-0000-0000-0000-000000057005', 5000, true),
  ('62000000-0000-0000-0000-000000057009',  800, true)
on conflict (task_id) do update set price = excluded.price, is_manual = true;

-- והאירוע השני מבוטל (0036/0114)
update events set status_id = (select id from statuses where entity = 'event' and code = 'cancelled'
                                                          and deleted_at is null)
 where id = '30000000-0000-0000-0000-00000000057b';

insert into attendance_entries (id, profile_id, work_date, seq, clock_in_at, clock_out_at,
                                source, status, work_site, task_ids,
                                req_at, req_clock_in_at, req_by)
values
  ('70000000-0000-0000-0000-0000000057e1', '20000000-0000-0000-0000-0000000057a1', t57_day(), 1,
   t57_at(0, '08:00'), null, 'clock', 'approved', 'warehouse',
   '{62000000-0000-0000-0000-000000057001}', null, null, null),
  ('70000000-0000-0000-0000-0000000057e2', '20000000-0000-0000-0000-0000000057a2', t57_day(), 1,
   t57_at(0, '07:00'), t57_at(0, '09:30'), 'manual', 'approved', 'field',
   '{62000000-0000-0000-0000-000000057001}', null, null, null),
  ('70000000-0000-0000-0000-0000000057e3', '20000000-0000-0000-0000-0000000057a2', t57_day() - 1, 1,
   t57_at(-1, '08:00'), t57_at(-1, '16:00'), 'manual', 'approved', 'field', '{}', null, null, null),
  ('70000000-0000-0000-0000-0000000057e4', '20000000-0000-0000-0000-0000000057a5', t57_day() - 1, 1,
   t57_at(-1, '06:00'), null, 'clock', 'approved', 'field', '{}', null, null, null),
  ('70000000-0000-0000-0000-0000000057e5', '20000000-0000-0000-0000-0000000057a6', t57_day(), 1,
   t57_at(0, '06:00'), t57_at(0, '08:00'), 'manual', 'pending', 'field', '{}', null, null, null),
  ('70000000-0000-0000-0000-0000000057e6', '20000000-0000-0000-0000-0000000057a6', t57_day() - 2, 1,
   t57_at(-2, '08:00'), t57_at(-2, '10:00'), 'manual', 'approved', 'field', '{}',
   t57_at(-1, '12:00'), t57_at(-2, '07:30'), '20000000-0000-0000-0000-0000000057a6');

insert into vehicles (id, plate_number, name, category) values
  ('40000000-0000-0000-0000-0000000057e1', '57-570-57', 'רכב 57', 'van'),
  ('40000000-0000-0000-0000-0000000057e2', '57-570-58', 'רכב שנמכר 57', 'van');
update vehicles set status = 'sold' where id = '40000000-0000-0000-0000-0000000057e2';

insert into vehicle_documents (id, vehicle_id, kind_id, expires_at)
select v.id::uuid, v.veh::uuid, k.id, t57_day() + v.off
  from (values
    ('60000000-0000-0000-0000-0000000057d1', '40000000-0000-0000-0000-0000000057e1', 'insurance_mandatory', -2),
    ('60000000-0000-0000-0000-0000000057d2', '40000000-0000-0000-0000-0000000057e1', 'annual_test',          10),
    ('60000000-0000-0000-0000-0000000057d3', '40000000-0000-0000-0000-0000000057e1', 'vehicle_license',     100),
    ('60000000-0000-0000-0000-0000000057d4', '40000000-0000-0000-0000-0000000057e2', 'insurance_mandatory', -2)
  ) v(id, veh, kind, off)
  join vehicle_document_kinds k on k.key = v.kind;

-- משלוחי אינטגרציה: נכשל בתוך 24 השעות, נכשל לפניהן, ועבר
insert into viperflow_deliveries (event_id, event_type, status, received_at) values
  ('evt_' || md5('wall-57-a'), 'order.updated', 'failed',    t57_at(0, '09:00')),
  ('evt_' || md5('wall-57-b'), 'order.updated', 'failed',    t57_at(-1, '04:00')),
  ('evt_' || md5('wall-57-c'), 'order.updated', 'processed', t57_at(0, '09:00'));

insert into arco_deliveries (kind, payload, status, received_at) values
  ('event', '{}', 'failed', t57_at(0, '08:00')),
  ('event', '{}', 'failed', t57_at(0, '11:00'));

insert into arco_outbound (event_id, tx_id, status, created_at) values
  ('30000000-0000-0000-0000-00000000057a', 'wall-57', 'failed', t57_at(0, '07:00'));

-- ===== 1. הדלת: מי מגיע אליה, ומה היא אומרת למי שאין לו סוד =================

\echo '--- ההרשאות כפי שהמיגרציה השאירה אותן (לפני הזריעה) ---'

select t_eq('anon ו-authenticated אינם מריצים אף אחת מהפונקציות החדשות',
  (select count(*)::int from t_pre_seed.function_acl
    where (schema, name) in (('public', 'wall_snapshot'), ('app', 'wall_snapshot_at'),
                             ('app', 'wall_feed_check'), ('app', 'wall_task_rows'),
                             ('app', 'margin_summary_core'), ('app', 'payroll_summary_core'))
      and (anon or authenticated)), 0);

select t_eq('ושש הפונקציות האלה אכן נמצאו בתמונה',
  (select count(*)::int from t_pre_seed.function_acl
    where (schema, name) in (('public', 'wall_snapshot'), ('app', 'wall_snapshot_at'),
                             ('app', 'wall_feed_check'), ('app', 'wall_task_rows'),
                             ('app', 'margin_summary_core'), ('app', 'payroll_summary_core'))), 6);

select t_eq('service_role מריץ את הדלת',
  (select service_role from t_pre_seed.function_acl
    where schema = 'public' and name = 'wall_snapshot' and args = 'p_secret text, p_days integer'), true);

select t_eq('ורק אותה — לא את הלוגיקה ולא את הליבות',
  (select count(*)::int from t_pre_seed.function_acl
    where (schema, name) in (('app', 'wall_snapshot_at'), ('app', 'wall_feed_check'),
                             ('app', 'wall_task_rows'), ('app', 'margin_summary_core'),
                             ('app', 'payroll_summary_core'))
      and service_role), 0);

select t_eq('העטיפה של הרווח שומרת את ההענקה ל-authenticated (0044)',
  (select authenticated from t_pre_seed.function_acl
    where schema = 'app' and name = 'margin_summary'), true);

\echo '--- anon ---'
set role anon;
select t_eq('anon אינו מריץ את הדלת', t57_state($$select public.wall_snapshot('x', 3)$$), '42501');
reset role;

\echo '--- service_role, בלי סוד ב-Vault ---'
set role service_role;
select t_eq('אין hash ב-Vault — 55000 (503), לא 42501',
  t57_state($$select public.wall_snapshot(repeat('s', 48), 3)$$), '55000');
select t_eq('service_role אינו קורא את Vault בעצמו',
  t57_state($$select count(*) from vault.decrypted_secrets$$), '42501');
select t_eq('ואינו עוקף את הדלת אל הלוגיקה',
  t57_state($$select app.wall_snapshot_at(now(), 3)$$), '42501');
reset role;

set role authenticated;
select t_eq('authenticated אינו קורא את Vault',
  t57_state($$select count(*) from vault.decrypted_secrets$$), '42501');
reset role;

-- הסוד נקבע כמו בהוראות התפעול: ה-hash בלבד
do $$ begin
  perform vault.create_secret(encode(sha256(convert_to('wall-57-' || repeat('k', 40), 'UTF8')), 'hex'),
                              'wall_feed_secret', 'sha256 of the ViperGroup wall secret');
end $$;

\echo '--- service_role, עם סוד ---'
set role service_role;
select t_eq('סוד שגוי — 28P01 (401)',
  t57_state($$select public.wall_snapshot('wall-57-' || repeat('x', 40), 3)$$), '28P01');
select t_eq('סוד ריק — 28P01',
  t57_state($$select public.wall_snapshot(null, 3)$$), '28P01');
select t_eq('הסוד הנכון עובר',
  t57_state($$select public.wall_snapshot('wall-57-' || repeat('k', 40), 3)$$), 'ok');
select t_eq('והתמונה היא של היום בישראל, עם ברירת המחדל של 3 ימים',
  (select (j ->> 'today')::date = (now() at time zone 'Asia/Jerusalem')::date
          and (j ->> 'days')::int = 3 and (j ->> 'v')::int = 1
          and j ->> 'source' = 'viperlogistics'
     from (select public.wall_snapshot('wall-57-' || repeat('k', 40)) as j) x), true);
reset role;

-- סוד קצר נדחה גם כשה-hash שלו הוא בדיוק מה שב-Vault
do $$ begin
  perform vault.update_secret((select id from vault.secrets where name = 'wall_feed_secret'),
                              encode(sha256(convert_to('short-57', 'UTF8')), 'hex'));
end $$;
set role service_role;
select t_eq('סוד קצר מ-32 נדחה גם כשה-hash תואם',
  t57_state($$select public.wall_snapshot('short-57', 3)$$), '28P01');
reset role;

-- מי שהדביק את הסוד עצמו במקום ה-hash רואה "לא מוגדר", לא "סוד שגוי"
do $$ begin
  perform vault.update_secret((select id from vault.secrets where name = 'wall_feed_secret'),
                              'wall-57-' || repeat('k', 40));
end $$;
set role service_role;
select t_eq('ערך שאינו hash ב-Vault — 55000',
  t57_state($$select public.wall_snapshot('wall-57-' || repeat('k', 40), 3)$$), '55000');
reset role;

do $$ begin
  perform vault.update_secret((select id from vault.secrets where name = 'wall_feed_secret'),
                              encode(sha256(convert_to('wall-57-' || repeat('k', 40), 'UTF8')), 'hex'));
end $$;

set role service_role;
select t_eq('ימים מחוץ לטווח נחתכים: 0 → 1, 99 → 14',
  (select (public.wall_snapshot('wall-57-' || repeat('k', 40), 0) ->> 'days') || '/'
       || (public.wall_snapshot('wall-57-' || repeat('k', 40), 99) ->> 'days')), '1/14');
reset role;

-- ===== 1ב. כמה סודות: כל שורה ב-Vault ששמה מתחיל ב-wall_feed_secret ===========
--
-- ‏`wall_feed_secret` הוא של Vercel (והוא כבר ב-Vault, עם wall-57-kkk…),
-- ‏`wall_feed_secret_minipc` הוא של ה-Mini PC. ההחלפה והביטול של אחד אינם נוגעים
-- באחר. הבדיקות רצות כ-service_role דרך הדלת; הכתיבה ל-Vault — כבעלים.

\echo '--- כמה סודות: Vercel ו-Mini PC ---'
do $$ begin
  perform vault.create_secret(t57_hash('mini-57-' || repeat('m', 40)),
                              'wall_feed_secret_minipc', 'sha256 of the Mini PC wall secret');
end $$;

set role service_role;
select t_eq('הסוד של Vercel עובר',
  t57_door('wall-57-' || repeat('k', 40)), 'ok');
select t_eq('והסוד של ה-Mini PC עובר גם הוא',
  t57_door('mini-57-' || repeat('m', 40)), 'ok');
select t_eq('סוד שאינו באף שורה — 28P01',
  t57_door('nope-57-' || repeat('n', 40)), '28P01');
select t_eq('סוד שמתחיל כמו אחד מהם אבל שונה — 28P01',
  t57_door('mini-57-' || repeat('m', 39)), '28P01');
select t_eq('סוד ריק — 28P01, גם עם שתי שורות', t57_door(null), '28P01');
select t_eq('ומחרוזת ריקה — 28P01', t57_door(''), '28P01');
reset role;

-- סוד קצר נדחה גם כשה-hash של שורה אחרת (לא רק הראשונה) תואם אותו
do $$ begin
  perform vault.update_secret((select id from vault.secrets where name = 'wall_feed_secret_minipc'),
                              t57_hash('short-57'));
end $$;
set role service_role;
select t_eq('סוד קצר מ-32 נדחה גם כשה-hash של שורת ה-Mini PC תואם',
  t57_door('short-57'), '28P01');
select t_eq('ושורת Vercel ממשיכה לעבוד',
  t57_door('wall-57-' || repeat('k', 40)), 'ok');
reset role;

\echo '--- החלפת סוד באחת השורות אינה נוגעת באחרת ---'
-- ה-Mini PC מקבל סוד חדש כמו בהוראות התפעול; Vercel לא זז
do $$ begin
  perform vault.update_secret((select id from vault.secrets where name = 'wall_feed_secret_minipc'),
                              t57_hash('mini2-57-' || repeat('m', 40)));
end $$;
set role service_role;
select t_eq('הסוד החדש של ה-Mini PC עובר',
  t57_door('mini2-57-' || repeat('m', 40)), 'ok');
select t_eq('הישן של ה-Mini PC נדחה',
  t57_door('mini-57-' || repeat('m', 40)), '28P01');
select t_eq('ו-Vercel ממשיך לעבוד',
  t57_door('wall-57-' || repeat('k', 40)), 'ok');
reset role;

-- ועכשיו להפך: Vercel מוחלף, וה-Mini PC לא זז
do $$ begin
  perform vault.update_secret((select id from vault.secrets where name = 'wall_feed_secret'),
                              t57_hash('wall2-57-' || repeat('k', 40)));
end $$;
set role service_role;
select t_eq('הסוד החדש של Vercel עובר',
  t57_door('wall2-57-' || repeat('k', 40)), 'ok');
select t_eq('הישן של Vercel נדחה',
  t57_door('wall-57-' || repeat('k', 40)), '28P01');
select t_eq('וה-Mini PC (בסוד החדש שלו) ממשיך לעבוד',
  t57_door('mini2-57-' || repeat('m', 40)), 'ok');
reset role;

\echo '--- סוד אחר ב-Vault אינו נספר ---'
-- שמות שאינם מתחילים ב-wall_feed_secret, אבל ה-hash של כל אחד הוא של הסוד שיוצג.
-- ‏`wallXfeedXsecret` תופס את ה-LIKE הלא-מוברח (הקו התחתון הוא תו-כללי).
do $$ begin
  perform vault.create_secret(t57_hash('other-57-' || repeat('o', 40)), 'other_secret', 'unrelated');
  perform vault.create_secret(t57_hash('old-57-' || repeat('d', 40)), 'old_wall_feed_secret',
                              'the prefix is in the middle of the name');
  perform vault.create_secret(t57_hash('wild-57-' || repeat('w', 40)), 'wallXfeedXsecret',
                              'underscore is a LIKE wildcard');
  perform vault.create_secret(t57_hash('wall-57-' || repeat('u', 40)), 'WALL_FEED_SECRET_UPPER',
                              'a different name, not a prefix match');
end $$;
set role service_role;
select t_eq('other_secret שה-hash שלו הוא של הסוד המוצג — 28P01',
  t57_door('other-57-' || repeat('o', 40)), '28P01');
select t_eq('שם שהקידומת בו באמצע — 28P01',
  t57_door('old-57-' || repeat('d', 40)), '28P01');
select t_eq('שם שנתפס רק אם הקו התחתון הוא תו-כללי — 28P01',
  t57_door('wild-57-' || repeat('w', 40)), '28P01');
select t_eq('ושם באותיות גדולות אינו הקידומת — 28P01',
  t57_door('wall-57-' || repeat('u', 40)), '28P01');
select t_eq('והשורות האמיתיות ממשיכות לעבוד',
  t57_door('wall2-57-' || repeat('k', 40)) || '/' || t57_door('mini2-57-' || repeat('m', 40)), 'ok/ok');
reset role;
delete from vault.secrets
 where name in ('other_secret', 'old_wall_feed_secret', 'wallXfeedXsecret', 'WALL_FEED_SECRET_UPPER');

\echo '--- שורה שאינה hash מתעלמים ממנה ---'
-- ה-Mini PC הדביק את הסוד עצמו במקום ה-hash, ועוד שתי שורות פגומות:
-- 63 תווי hex, ו-64 תווים שאינם hex. שורה שלישית תקינה אבל באותיות גדולות
-- ועם רווחים מסביב (btrim) — לא נפגמת.
do $$ begin
  perform vault.update_secret((select id from vault.secrets where name = 'wall_feed_secret_minipc'),
                              'mini2-57-' || repeat('m', 40));
  perform vault.create_secret(repeat('a', 63), 'wall_feed_secret_short', 'one hex char short');
  perform vault.create_secret(repeat('g', 64), 'wall_feed_secret_nothex', 'right length, not hex');
  perform vault.create_secret(' ' || upper(t57_hash('upper-57-' || repeat('h', 40))) || ' ',
                              'wall_feed_secret_upper', 'valid after lower(btrim)');
end $$;
set role service_role;
select t_eq('השורה התקינה של Vercel עובדת לצד הפגומות',
  t57_door('wall2-57-' || repeat('k', 40)), 'ok');
select t_eq('הסוד שהודבק כמות שהוא אינו מתקבל — 28P01, לא 55000',
  t57_door('mini2-57-' || repeat('m', 40)), '28P01');
select t_eq('hex באותיות גדולות ועם רווחים מסביב — תקין',
  t57_door('upper-57-' || repeat('h', 40)), 'ok');
reset role;
delete from vault.secrets
 where name in ('wall_feed_secret_short', 'wall_feed_secret_nothex', 'wall_feed_secret_upper');

\echo '--- אין אף שורה תקינה — 55000 ---'
-- שורת ה-Mini PC עדיין פגומה (הסוד הודבק במקום ה-hash). מוחקים את Vercel, ואז
-- נשארת רק היא — ו-other_secret, שערכו hash תקין אבל שמו אינו wall_feed_secret*.
do $$ begin
  delete from vault.secrets where name = 'wall_feed_secret';
  perform vault.create_secret(t57_hash('wall2-57-' || repeat('k', 40)), 'other_secret', 'unrelated');
end $$;
set role service_role;
select t_eq('רק שורה פגומה אחת ו-other_secret — 55000 גם לסוד שהיה נכון',
  t57_door('wall2-57-' || repeat('k', 40)), '55000');
select t_eq('ו-55000 גם לסוד ריק: הגדרה לפני סוד',
  t57_door(null), '55000');
reset role;

delete from vault.secrets where name = 'wall_feed_secret_minipc';
set role service_role;
select t_eq('אין אף שורה wall_feed_secret* — 55000',
  t57_door('wall2-57-' || repeat('k', 40)), '55000');
reset role;

-- חוזרים לשורה אחת, ומי שחזר לעבוד הוא הסוד של Vercel
do $$ begin
  delete from vault.secrets where name = 'other_secret';
  perform vault.create_secret(t57_hash('wall-57-' || repeat('k', 40)),
                              'wall_feed_secret', 'sha256 of the ViperGroup wall secret');
end $$;
set role service_role;
select t_eq('שורה תקינה אחת חזרה — והסוד המקורי של Vercel עובר שוב',
  t57_door('wall-57-' || repeat('k', 40)), 'ok');
reset role;
select t_eq('וב-Vault לא נשאר דבר מלבדה',
  (select string_agg(name, ',' order by name) from vault.secrets), 'wall_feed_secret');

-- ===== 2. המשימות של היום ===================================================

\echo '--- המשימות, ב-10:00 של D ---'
create temp table s57 as select app.wall_snapshot_at(t57_at(0, '10:00'), 3) as j;

select t_eq('היום הוא D, ו"נוצר ב" הוא העכשיו שננעץ',
  (select (j ->> 'today')::date = t57_day()
          and (j ->> 'generated_at')::timestamptz = t57_at(0, '10:00') from s57), true);

select t_eq('חותמות הזמן יוצאות ב-UTC עם היסט',
  (select j ->> 'generated_at' from s57) like '%+00:00', true);

select t_eq('הרשימה: סידור 08:30, הקמה 09:00, סידור 10:00, ומחר 07:00 — לפי זמן',
  (select string_agg(right(t ->> 'id', 3), ',' order by o)
     from s57, jsonb_array_elements(j -> 'tasks') with ordinality as x(t, o)
    where t ->> 'id' like '62000000-0000-0000-0000-000000057%'), '007,001,008,006');

select t_eq('המוסתרת מהלו״ז, של ארקו, שנמחקה ושבאירוע שבוטל — אינן ברשימה',
  (select count(*)::int from s57, jsonb_array_elements(j -> 'tasks') t
    where t ->> 'id' in ('62000000-0000-0000-0000-000000057002', '62000000-0000-0000-0000-000000057003',
                         '62000000-0000-0000-0000-000000057004', '62000000-0000-0000-0000-000000057005')), 0);

select t_eq('D+5 מחוץ לשלושת הימים',
  (select count(*)::int from s57, jsonb_array_elements(j -> 'tasks') t
    where t ->> 'id' = '62000000-0000-0000-0000-000000057009'), 0);

create temp table t57_1 as
select t from s57, jsonb_array_elements(j -> 'tasks') t
 where t ->> 'id' = '62000000-0000-0000-0000-000000057001';

select t_eq('הצוות הוא אנשים: 5, אף שיש 6 שורות שיבוץ (עובד א׳ גם נהג)',
  (select (t ->> 'assigned')::int || '/' || (t ->> 'needed') from t57_1), '5/5');
select t_eq('ראש הצוות של הקבלן',
  (select t ->> 'team_lead_name' from t57_1), 'ראש צוות קבלן 57');
select t_eq('מואצלת, לקבלן בשמו',
  (select (t ->> 'delegated') || '/' || (t -> 'contractor_names')::text from t57_1),
  'true/["קבלן 57"]');
select t_eq('המשאיות: מהרשימה, ואז הטקסט החופשי',
  (select t -> 'trucks' from t57_1), '["משאית 57", "נגרר 57"]'::jsonb);
select t_eq('יציאה מהמחסן 08:00, בשטח 09:00, סיום 13:00 — בישראל',
  (select (t ->> 'warehouse_at')::timestamptz = t57_at(0, '08:00')
          and (t ->> 'start_at')::timestamptz = t57_at(0, '09:00')
          and (t ->> 'end_at')::timestamptz = t57_at(0, '13:00') from t57_1), true);
select t_eq('הקמה, משובצת ולכן פורסמה',
  (select concat_ws('/', t ->> 'type_code', t ->> 'type_name', t ->> 'status_code', t ->> 'published')
     from t57_1), 'setup/הקמה/assigned/true');
select t_eq('הלקוח, הצבע, האירוע והמיקום',
  (select concat_ws('/', t ->> 'customer_name', t ->> 'customer_color', t ->> 'event_number',
                    t ->> 'end_client_name', t ->> 'location') from t57_1),
  'לקוח 57/#0e7490/EV-57/חתונה 57/גני 57');
select t_eq('אין בשורה טלפון', (select t::text not like '%050-57%' from t57_1), true);

select t_eq('סידור: אין לסוג קוד, וראש צוות פנימי',
  (select coalesce(t ->> 'type_code', '∅') || '/' || (t ->> 'team_lead_name')
     from s57, jsonb_array_elements(j -> 'tasks') t
    where t ->> 'id' = '62000000-0000-0000-0000-000000057008'), '∅/ראש צוות 57');

-- ===== 3. המונים וההתראות ====================================================

\echo '--- מונים ---'
select t_eq('היום: ארבע משימות — המוסתרת בפנים, ארקו/נמחקה/בוטלה בחוץ',
  (select (j -> 'kpis' ->> 'tasks_today')::int from s57), 4);
select t_eq('הקמה אחת ופירוק אחד',
  (select (j -> 'kpis' ->> 'setups_today') || '/' || (j -> 'kpis' ->> 'teardowns_today') from s57), '1/1');
select t_eq('שבעה ימים: שש',
  (select (j -> 'kpis' ->> 'tasks_next_7d')::int from s57), 6);
select t_eq('חסר צוות ב-48 שעות: שתיים, והמוסתרת אחת מהן',
  (select (j -> 'kpis' ->> 'understaffed_48h')::int from s57), 2);
select t_eq('לא פורסמה ב-48 שעות: המוסתרת',
  (select (j -> 'kpis' ->> 'unpublished_48h')::int from s57), 1);
select t_eq('במשמרת עכשיו: אחד',
  (select (j -> 'kpis' ->> 'workers_on_shift')::int from s57), 1);

\echo '--- התראות ---'
select t_eq('חסר צוות: סידור 10:00 (1/2), ואז הפירוק המוסתר 18:00 (0/3)',
  (select string_agg(right(u ->> 'task_id', 3) || ':' || (u ->> 'assigned') || '/' || (u ->> 'needed'),
                     ',' order by o)
     from s57, jsonb_array_elements(j -> 'alerts' -> 'understaffed') with ordinality as x(u, o)),
  '008:1/2,002:0/3');
select t_eq('לא פורסמה: הפירוק, עם תווית שאומרת של מי',
  (select string_agg(right(u ->> 'task_id', 3) || ':' || (u ->> 'label'), ',')
     from s57, jsonb_array_elements(j -> 'alerts' -> 'unpublished') u),
  '002:לקוח 57 · חתונה 57');

select t_eq('מסמכי רכב: שפג לפני יומיים, ושיפוג בעוד עשרה — לא התקף, ולא של הרכב שנמכר',
  (select string_agg((d ->> 'kind_name') || ':' || (d ->> 'status') || ':' || (d ->> 'days_left'),
                     ',' order by d ->> 'expires_at')
     from s57, jsonb_array_elements(j -> 'alerts' -> 'fleet_documents') d
    where d ->> 'vehicle_name' like '%57'),
  'ביטוח חובה:expired:-2,טסט שנתי:expiring:10');

select t_eq('ממתינות לאישור — כל החברה, בלי מחוקות',
  (select (j -> 'alerts' ->> 'attendance_pending')::int from s57),
  (select count(*)::int from attendance_entries where status = 'pending' and deleted_at is null));
select t_eq('ובקשות תיקון — כולל זו של "ממתין 57"',
  (select (j -> 'alerts' ->> 'correction_requests')::int from s57),
  (select count(*)::int from attendance_entries where req_at is not null and deleted_at is null));
select t_eq('והמונה הזה אינו ריק', (select (j -> 'alerts' ->> 'correction_requests')::int >= 1 from s57), true);

select t_eq('כשלי אינטגרציה ב-24 שעות: אחד מכל סוג — לא הישן, לא שעבר, לא שבעתיד',
  (select j -> 'alerts' -> 'integration_failures' from s57),
  '{"viperflow": 1, "arco_in": 1, "arco_out": 1}'::jsonb);

-- ===== 4. במשמרת, שעות, ומי מאחר ============================================

\echo '--- במשמרת עכשיו ---'
select t_eq('עובד א׳ במשמרת מ-08:00, מהמחסן, שעתיים עד עכשיו, על החתונה',
  (select concat_ws('/', s ->> 'name', s ->> 'work_site', (s ->> 'hours_so_far')::numeric,
                    s ->> 'task_label', ((s ->> 'clock_in_at')::timestamptz = t57_at(0, '08:00'))::text)
     from s57, jsonb_array_elements(j -> 'shifts_now') s),
  'עובד 57 א/warehouse/2.00/לקוח 57 · חתונה 57/true');
select t_eq('"שכח לצאת" — פתוחה כבר 28 שעות, מעבר לסף של 16 — אינו במשמרת',
  (select count(*)::int from s57, jsonb_array_elements(j -> 'shifts_now') s
    where s ->> 'name' = 'שכח לצאת 57'), 0);

\echo '--- שעות ---'
select t_eq('היום: 2 חיות + 2.5 מאושרות; הממתינה אינה נספרת',
  (select (j -> 'attendance' ->> 'hours_today')::numeric from s57), 4.5);
select t_eq('השבוע (מיום ראשון): ועוד 8 ב-D-1 ו-2 ב-D-2; הפתוחה שנשכחה — אפס',
  (select (j -> 'attendance' ->> 'hours_week')::numeric from s57), 14.5);
select t_eq('שלושה עבדו היום, גם מי שממתין',
  (select (j -> 'attendance' ->> 'workers_today')::int from s57), 3);
select t_eq('פר-עובד היום: לפי שעות, והפתוח מסומן',
  (select string_agg((b ->> 'name') || ':' || ((b ->> 'hours')::numeric)::text || ':' || (b ->> 'open'),
                     ',' order by o)
     from s57, jsonb_array_elements(j -> 'attendance' -> 'by_worker_today') with ordinality as x(b, o)),
  'עובד 57 ב:2.50:false,עובד 57 א:2.00:true,ממתין 57:0.00:false');

\echo '--- מאחרים (ROADMAP §3.4) ---'
select t_eq('"מאחר 57": התחיל 08:30, 90 דקות, על הסידור — ולא אף אחד אחר',
  (select string_agg(concat_ws('/', l ->> 'name', l ->> 'minutes_late', l ->> 'task_label',
                               ((l ->> 'planned_start')::timestamptz = t57_at(0, '08:30'))::text), ',')
     from s57, jsonb_array_elements(j -> 'attendance' -> 'late') l),
  'מאחר 57/90/לקוח 57 · סידור במה 57/true');

select t_eq('ב-08:40 הוא עוד לא מאחר — עשר דקות בתוך החסד',
  (select jsonb_array_length(app.wall_snapshot_at(t57_at(0, '08:40'), 3) -> 'attendance' -> 'late')), 0);

-- ===== 5. חצות של ישראל ======================================================

\echo '--- חצות ---'
select t_eq('20:59 UTC הוא עדיין D בישראל',
  (app.wall_snapshot_at((t57_day() + time '20:59') at time zone 'UTC', 1) ->> 'today')::date, t57_day());

create temp table s57n as
select app.wall_snapshot_at((t57_day() + time '21:30') at time zone 'UTC', 1) as j;

select t_eq('21:30 UTC בקיץ הוא כבר D+1 בישראל',
  (select (j ->> 'today')::date from s57n), t57_day() + 1);
select t_eq('והמשימות שלו הן של D+1 בלבד',
  (select string_agg(right(t ->> 'id', 3), ',')
     from s57n, jsonb_array_elements(j -> 'tasks') t
    where t ->> 'id' like '62000000-0000-0000-0000-000000057%'), '006');
select t_eq('והמונה של "היום" סופר את D+1',
  (select (j -> 'kpis' ->> 'tasks_today')::int from s57n), 1);

-- ===== 6. כסף: כלל 6 ========================================================

\echo '--- כספים ---'
create temp table m57 as
select make_date(extract(year from t57_day())::int, 7, 1) as m_from,
       app.margin_summary_core(make_date(extract(year from t57_day())::int, 7, 1), t57_day()) as core;

select t_eq('החודש: יולי',
  (select (j -> 'finance' ->> 'month_start') || '/' || (j -> 'finance' ->> 'month_end') from s57),
  (select m_from::text || '/' || (m_from + interval '1 month' - interval '1 day')::date::text from m57));

select t_eq('הכנסה, קבלן, שכר, גולמי, אחוז ומשמרות בלי תעריף — בדיוק margin_summary_core',
  (select jsonb_build_object(
            'revenue', (j -> 'finance' ->> 'revenue_mtd')::numeric,
            'contractor', (j -> 'finance' ->> 'contractor_mtd')::numeric,
            'payroll', (j -> 'finance' ->> 'payroll_mtd')::numeric,
            'gross', (j -> 'finance' ->> 'gross_mtd')::numeric,
            'pct', (j -> 'finance' ->> 'gross_pct')::numeric,
            'unrated', (j -> 'finance' ->> 'unrated_shifts')::int) from s57),
  (select jsonb_build_object(
            'revenue', (core ->> 'revenue')::numeric,
            'contractor', (core ->> 'contractor')::numeric,
            'payroll', (core ->> 'payroll')::numeric,
            'gross', (core ->> 'gross')::numeric,
            'pct', (core ->> 'pct')::numeric,
            'unrated', (core ->> 'unrated_shifts')::int) from m57));

select t_eq('ההכנסה היא של המשימות החיות — לא של שנמחקה (7,000) ולא של שבוטלה (5,000)',
  (select (j -> 'finance' ->> 'revenue_mtd')::numeric from s57),
  (select sum(price) from app.task_revenue
    where task_id in ('62000000-0000-0000-0000-000000057001', '62000000-0000-0000-0000-000000057002',
                      '62000000-0000-0000-0000-000000057003', '62000000-0000-0000-0000-000000057007',
                      '62000000-0000-0000-0000-000000057008')));

select t_eq('ומחיר הקבלן של ההקמה',
  (select (j -> 'finance' ->> 'contractor_mtd')::numeric from s57),
  (select price from task_contractor_terms where task_id = '62000000-0000-0000-0000-000000057001'));

select t_eq('תחזית שאר החודש: D+1 ו-D+5',
  (select (j -> 'finance' ->> 'forecast_rest_of_month')::numeric from s57),
  (select sum(price) from app.task_revenue
    where task_id in ('62000000-0000-0000-0000-000000057006', '62000000-0000-0000-0000-000000057009')));

select t_eq('ובה ה-800 הידניים',
  (select (j -> 'finance' ->> 'forecast_rest_of_month')::numeric >= 800 from s57), true);

select t_eq('אחוז הוא אחוז (0..100) או null',
  (select (j -> 'finance' ->> 'gross_pct') is null
          or abs((j -> 'finance' ->> 'gross_pct')::numeric) <= 100 from s57), true);

-- ===== 7. העטיפות שומרות על השער ============================================

\echo '--- margin_summary / payroll_summary ---'
select (select core::text from m57) as core57,
       app.payroll_summary_core((select m_from from m57), t57_day())::text as pay57,
       (select m_from from m57)::text as from57,
       t57_day()::text as to57
\gset

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000057b1', false);
select t_eq('עובד השטח אינו מחזיק את מפתח השכר', app.has('dashboard.payroll'), false);
select t_eq('margin_summary עדיין זורקת לו 42501',
  t57_state(format('select app.margin_summary(%L, %L)', :'from57', :'to57')), '42501');
select t_eq('וכך payroll_summary',
  t57_state(format('select app.payroll_summary(%L, %L)', :'from57', :'to57')), '42501');
reset role;
select set_config('request.jwt.claim.sub', '', false);

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false);
select t_eq('בעל המערכת מקבל מ-margin_summary בדיוק את הליבה',
  app.margin_summary(:'from57'::date, :'to57'::date), :'core57'::jsonb);
select t_eq('ומ-payroll_summary בדיוק את הליבה',
  app.payroll_summary(:'from57'::date, :'to57'::date), :'pay57'::jsonb);
reset role;
select set_config('request.jwt.claim.sub', '', false);
