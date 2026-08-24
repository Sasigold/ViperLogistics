\pset tuples_only on
\pset format unaligned

-- ===========================================================================
-- 24: שלוש ברירות מחדל שהמשרד מחזיק (0110).
--
--   * **אופן ביצוע ברירת מחדל פר לקוח** — משימה חדשה נולדת איתו, מכל דלת;
--     סוג משימה שאינו מתיר אותו אינו מקבל אותו; ובחירה מפורשת גוברת.
--   * **מחיר מטופס האירוע** — הלקוח אינו כותב אותו גם דרך `update_event`,
--     שהיא `security definer` ולכן פוסחת על `tp_write`; והסתרת השדה ללקוח
--     מסוים חוסמת אותו גם בשביל הצוות.
--   * **נקודת ההתחלה של עובדי הקבלן** — הקבלן מקבל את מה שנקבע בהאצלה גם
--     כשהוא נוקב במפורש באחר; המשרד עם המפתח כן דורס.
--
-- החבילה מקימה לקוח, קבלן, אירוע ודמויות משלה. האירועים יושבים ב-
-- ‏current_date + 400, מעבר לכל טווח אחר.
-- ===========================================================================

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000024a1', 'c24-cust@vl.test'),
  ('00000000-0000-0000-0000-0000000024a2', 'c24-staff@vl.test'),
  ('00000000-0000-0000-0000-0000000024a3', 'c24-ctr@vl.test'),
  ('00000000-0000-0000-0000-0000000024a4', 'c24-admin@vl.test');

insert into customers (id, name, can_create_events) values
  ('10000000-0000-0000-0000-00000000024a', 'לקוח 24', true);

insert into contractors (id, name, default_task_price) values
  ('11000000-0000-0000-0000-00000000024a', 'קבלן 24', 500);

insert into contractor_workers (id, contractor_id, full_name) values
  ('12000000-0000-0000-0000-000000024001', '11000000-0000-0000-0000-00000000024a', 'עובד קבלן 24');

insert into profiles (id, user_id, user_kind, is_admin, full_name, customer_id, contractor_id) values
  ('20000000-0000-0000-0000-0000000024a1', '00000000-0000-0000-0000-0000000024a1',
   'customer_user', false, 'מנהל לקוח 24', '10000000-0000-0000-0000-00000000024a', null),
  ('20000000-0000-0000-0000-0000000024a2', '00000000-0000-0000-0000-0000000024a2',
   'staff', false, 'רכז 24', null, null),
  ('20000000-0000-0000-0000-0000000024a3', '00000000-0000-0000-0000-0000000024a3',
   'contractor_user', false, 'מנהל קבלן 24', null, '11000000-0000-0000-0000-00000000024a'),
  ('20000000-0000-0000-0000-0000000024a4', '00000000-0000-0000-0000-0000000024a4',
   'staff', true, 'מנהל מערכת 24', null, null);

insert into profile_roles (profile_id, role_id)
select p.pid, r.id from (values
  ('20000000-0000-0000-0000-0000000024a1'::uuid, 'customer_manager'),
  ('20000000-0000-0000-0000-0000000024a2'::uuid, 'dispatcher'),
  ('20000000-0000-0000-0000-0000000024a3'::uuid, 'contractor_manager')
) as p(pid, rkey) join permission_roles r on r.key = p.rkey;

-- הרכז מתמחר: זה מה שהופך את הבדיקה למשמעותית — הוא מצליח, והלקוח לא.
insert into user_permission_grants (profile_id, permission_key, allowed) values
  ('20000000-0000-0000-0000-0000000024a2', 'pricing.edit', true),
  ('20000000-0000-0000-0000-0000000024a2', 'pricing.view', true)
on conflict (profile_id, permission_key) do update set allowed = true;

-- שני אופני ביצוע ללקוח: אחד מותר גם להקמה וגם לפירוק ומסומן כברירת המחדל,
-- והשני מותר להקמה בלבד.
insert into execution_methods (id, name, is_active) values
  ('13000000-0000-0000-0000-000000024001', 'אופן 24 — ברירת מחדל', true),
  ('13000000-0000-0000-0000-000000024002', 'אופן 24 — הקמה בלבד', true);

insert into task_type_execution_methods (task_type_id, execution_method_id)
select t.id, m.mid from task_types t
  cross join (values ('13000000-0000-0000-0000-000000024001'::uuid)) as m(mid)
 where t.code in ('setup', 'teardown')
on conflict do nothing;

insert into task_type_execution_methods (task_type_id, execution_method_id)
select t.id, '13000000-0000-0000-0000-000000024002' from task_types t where t.code = 'setup'
on conflict do nothing;

insert into customer_execution_methods (customer_id, execution_method_id, is_default) values
  ('10000000-0000-0000-0000-00000000024a', '13000000-0000-0000-0000-000000024001', true),
  ('10000000-0000-0000-0000-00000000024a', '13000000-0000-0000-0000-000000024002', false)
on conflict (customer_id, execution_method_id) do update set is_default = excluded.is_default;

-- ===== 1. אופן ביצוע ברירת מחדל ==========================================

\echo '--- אופן ביצוע ברירת מחדל ---'

select t_eq('ברירת מחדל אחת לכל היותר לכל לקוח', (
  select count(*)::int from customer_execution_methods
   where customer_id = '10000000-0000-0000-0000-00000000024a' and is_default), 1);

select t_expect_fail('ושנייה נדחית באינדקס', $$
  update customer_execution_methods set is_default = true
   where customer_id = '10000000-0000-0000-0000-00000000024a'
     and execution_method_id = '13000000-0000-0000-0000-000000024002'$$);

insert into events (id, customer_id, event_number, event_date, status_id)
values ('30000000-0000-0000-0000-00000000024a', '10000000-0000-0000-0000-00000000024a', 'EV-24',
        current_date + 400,
        (select id from statuses where entity = 'event' and code = 'planned' and deleted_at is null));

-- משימה שנולדת בלי אופן ביצוע מקבלת את ברירת המחדל של הלקוח
insert into tasks (id, event_id, customer_id, task_type_id, task_date, worker_count, status_id)
select '61000000-0000-0000-0000-000000024001', '30000000-0000-0000-0000-00000000024a',
       '10000000-0000-0000-0000-00000000024a', t.id, current_date + 400, 2,
       (select id from statuses where entity = 'task' and code = 'draft' and deleted_at is null)
  from task_types t where t.code = 'setup';

select t_eq('משימה חדשה נולדת עם ברירת המחדל של הלקוח',
  (select execution_method_id from tasks where id = '61000000-0000-0000-0000-000000024001'),
  '13000000-0000-0000-0000-000000024001'::uuid);

-- בחירה מפורשת גוברת עליה
insert into tasks (id, event_id, customer_id, task_type_id, task_date, worker_count, status_id,
                   execution_method_id)
select '61000000-0000-0000-0000-000000024002', '30000000-0000-0000-0000-00000000024a',
       '10000000-0000-0000-0000-00000000024a', t.id, current_date + 400, 2,
       (select id from statuses where entity = 'task' and code = 'draft' and deleted_at is null),
       '13000000-0000-0000-0000-000000024002'
  from task_types t where t.code = 'setup';

select t_eq('ובחירה מפורשת גוברת עליה',
  (select execution_method_id from tasks where id = '61000000-0000-0000-0000-000000024002'),
  '13000000-0000-0000-0000-000000024002'::uuid);

-- לקוח אחר, בלי ברירת מחדל — נשאר ריק ולא יורש מאיש
insert into tasks (id, event_id, customer_id, task_type_id, task_date, worker_count, status_id)
select '61000000-0000-0000-0000-000000024003', null,
       '10000000-0000-0000-0000-000000000001', t.id, current_date + 400, 2,
       (select id from statuses where entity = 'task' and code = 'draft' and deleted_at is null)
  from task_types t where t.code = 'setup';

select t_eq('ולקוח בלי ברירת מחדל נשאר ריק',
  (select execution_method_id from tasks where id = '61000000-0000-0000-0000-000000024003'), null::uuid);

-- ===== 2. מחיר מטופס האירוע ==============================================

\echo '--- מחיר מטופס האירוע ---'

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000024a2', false);

-- הקריאה חייבת להיות בהוראה נפרדת מהכתיבה: ל-plpgsql יש snapshot לכל הוראה,
-- ותת-שאילתה באותו SELECT קוראת את המצב שלפני ה-RPC (אותו נימוק של
-- ‏`t_created_event` ב-01).
do $$ begin perform update_event('30000000-0000-0000-0000-00000000024a',
  '{"setup_price":"777"}'::jsonb); end $$;

select t_eq('רכז עם המפתח מתמחר מטופס האירוע',
  (select tp.price from task_pricing tp
     join tasks t on t.id = tp.task_id
    where t.event_id = '30000000-0000-0000-0000-00000000024a'
      and t.task_type_id = (select id from task_types where code = 'setup')),
  777::numeric);

reset role;
select set_config('request.jwt.claim.sub', '', false);

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000024a1', false);

-- הלקוח שולח את אותו מפתח בדיוק, ו-update_event היא security definer —
-- ‏`tp_write` לא הייתה נשאלת כאן כלל, ולכן הבדיקה היא על התנאי שב-RPC.
do $$ begin perform update_event('30000000-0000-0000-0000-00000000024a',
  '{"setup_price":"1"}'::jsonb); end $$;

select t_eq('הלקוח שולח את אותו שדה — והמחיר לא זז',
  (select tp.price from task_pricing tp
     join tasks t on t.id = tp.task_id
    where t.event_id = '30000000-0000-0000-0000-00000000024a'
      and t.task_type_id = (select id from task_types where code = 'setup')),
  777::numeric);

reset role;
select set_config('request.jwt.claim.sub', '', false);

-- מנהל המערכת מסתיר את שדה המחיר ללקוח הזה — וזו החסימה, גם בשביל הצוות
insert into customer_form_fields (customer_id, field_key, state) values
  ('10000000-0000-0000-0000-00000000024a', 'setup_price', 'hidden')
on conflict (customer_id, field_key) do update set state = 'hidden';

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000024a2', false);

do $$ begin perform update_event('30000000-0000-0000-0000-00000000024a',
  '{"setup_price":"9999"}'::jsonb); end $$;

select t_eq('ואחרי שהשדה הוסתר ללקוח — גם הרכז אינו כותב',
  (select tp.price from task_pricing tp
     join tasks t on t.id = tp.task_id
    where t.event_id = '30000000-0000-0000-0000-00000000024a'
      and t.task_type_id = (select id from task_types where code = 'setup')),
  777::numeric);

reset role;
select set_config('request.jwt.claim.sub', '', false);

-- ===== 3. נקודת ההתחלה של עובדי הקבלן ====================================

\echo '--- נקודת ההתחלה של הקבלן ---'

insert into task_contractor_terms (task_id, contractor_id, price, work_site) values
  ('61000000-0000-0000-0000-000000024001', '11000000-0000-0000-0000-00000000024a', 500, 'field')
on conflict (task_id, contractor_id) do update set work_site = 'field';

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000024a3', false);

select t_expect_ok('הקבלן משבץ את עובדו', $$
  select contractor_assign_worker('61000000-0000-0000-0000-000000024001',
    '12000000-0000-0000-0000-000000024001', null, true, 'warehouse')$$);

reset role;
select set_config('request.jwt.claim.sub', '', false);

select t_eq('והוא יצא מהשטח, כפי שנקבע בהאצלה — ולא מהמחסן שביקש',
  (select work_site from task_contractor_workers
    where task_id = '61000000-0000-0000-0000-000000024001'
      and contractor_worker_id = '12000000-0000-0000-0000-000000024001'), 'field');

-- המשרד משנה את שורת ההאצלה, והעובד זז איתה
update task_contractor_terms set work_site = 'warehouse'
 where task_id = '61000000-0000-0000-0000-000000024001'
   and contractor_id = '11000000-0000-0000-0000-00000000024a';

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000024a3', false);
select t_expect_ok('הקבלן משבץ שוב', $$
  select contractor_assign_worker('61000000-0000-0000-0000-000000024001',
    '12000000-0000-0000-0000-000000024001', null, true, 'field')$$);
reset role;
select set_config('request.jwt.claim.sub', '', false);

select t_eq('ועכשיו הוא יוצא מהמחסן — שוב לפי ההאצלה ולא לפי מה שנשלח',
  (select work_site from task_contractor_workers
    where task_id = '61000000-0000-0000-0000-000000024001'
      and contractor_worker_id = '12000000-0000-0000-0000-000000024001'), 'warehouse');

-- ולמשרד הדריסה הנקודתית נשארת
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000024a4', false);
select t_expect_ok('מנהל המערכת דורס נקודתית', $$
  select contractor_assign_worker('61000000-0000-0000-0000-000000024001',
    '12000000-0000-0000-0000-000000024001', null, true, 'field')$$);
reset role;
select set_config('request.jwt.claim.sub', '', false);

select t_eq('והדריסה שלו נתפסה',
  (select work_site from task_contractor_workers
    where task_id = '61000000-0000-0000-0000-000000024001'
      and contractor_worker_id = '12000000-0000-0000-0000-000000024001'), 'field');
