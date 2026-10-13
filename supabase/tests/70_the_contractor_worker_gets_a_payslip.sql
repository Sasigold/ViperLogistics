\pset tuples_only on
\pset format unaligned

-- ===========================================================================
-- ‏70: גם עובד של קבלן מקבל תלוש, ותלוש יכול להישאר "ללא שיוך" (0220).
--
--   70a0 מנהל מערכת
--   70b1 מנהל תלושים (payslips.manage בלבד)
--   70c1 עובד קבלן "גדי קבלני 70"  (contractor_user, קבלן 70)
--   70c2 עובד אחר של אותו קבלן   (contractor_user, קבלן 70)
--   70e1 משתמש לקוח
-- ===========================================================================

revoke execute on function payslip_store_reading(uuid, int, jsonb, text) from anon, authenticated, public;
revoke execute on function app.notify_payslip_available(uuid) from anon, authenticated, public;
revoke execute on function app.payslip_amounts_put(uuid, jsonb, text) from anon, authenticated, public;

insert into auth.users (id, email)
select ('00000000-0000-0000-0000-0000000070' || s)::uuid, 'p70-' || s || '@vl.test'
  from unnest(array['a0','b1','c1','c2','e1']) s;

insert into contractors (id, name) values ('10000000-0000-0000-0000-0000000070c0', 'קבלן 70');
insert into customers (id, name) values ('10000000-0000-0000-0000-0000000070e0', 'לקוח 70');

insert into profiles (id, user_id, user_kind, is_admin, full_name, contractor_id, customer_id) values
  ('20000000-0000-0000-0000-0000000070a0', '00000000-0000-0000-0000-0000000070a0', 'staff', true,  'מנהל 70', null, null),
  ('20000000-0000-0000-0000-0000000070b1', '00000000-0000-0000-0000-0000000070b1', 'staff', false, 'מנהלת תלושים 70', null, null),
  ('20000000-0000-0000-0000-0000000070c1', '00000000-0000-0000-0000-0000000070c1', 'contractor_user', false, 'גדי קבלני 70',
   '10000000-0000-0000-0000-0000000070c0', null),
  ('20000000-0000-0000-0000-0000000070c2', '00000000-0000-0000-0000-0000000070c2', 'contractor_user', false, 'אחר קבלני 70',
   '10000000-0000-0000-0000-0000000070c0', null),
  ('20000000-0000-0000-0000-0000000070e1', '00000000-0000-0000-0000-0000000070e1', 'customer_user', false, 'לקוח 70',
   null, '10000000-0000-0000-0000-0000000070e0');

insert into user_permission_grants (profile_id, permission_key, allowed) values
  ('20000000-0000-0000-0000-0000000070b1', 'payslips.manage', true);

create or replace function t70_as(p text) returns void language sql as $$
  select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000070' || p, false);
$$;
grant execute on function t70_as(text) to authenticated;

create or replace function t70_files(p_batch uuid) returns text language sql stable as $$
  select coalesce(string_agg(split_part(name, '/', 2), ',' order by name), '-')
    from storage.objects where bucket_id = 'payslips' and name like p_batch::text || '/%'
$$;
grant execute on function t70_files(uuid) to authenticated;

-- ===== 1. עובד קבלן ========================================================

\echo '--- 1. עובד קבלן ---'
set role authenticated;

select t70_as('c1');
select t_eq('עובד קבלן: רואה את התלושים שלו (applies_to כולל contractor_user)',
  app.can_view_own_payslips(), true);
select t70_as('e1');
select t_eq('משתמש לקוח: עדיין לא', app.can_view_own_payslips(), false);

select t70_as('c1');
select t_expect_fail('עובד קבלן אינו פותח את רשימת השיוך', $$select payslip_assignees()$$);

select t70_as('b1');
select t_eq('רשימת השיוך: עובד הקבלן עם שם הקבלן',
  (select e ->> 'contractor_name' from jsonb_array_elements(payslip_assignees()) e
    where e ->> 'id' = '20000000-0000-0000-0000-0000000070c1'), 'קבלן 70');
select t_eq('ומשתמש לקוח אינו בה',
  (select count(*)::int from jsonb_array_elements(payslip_assignees()) e
    where e ->> 'id' = '20000000-0000-0000-0000-0000000070e1'), 0);

select payslip_batch_create('תלושים 70.pdf', 3, '2032-07-01') as batch \gset
select t_expect_ok('העמודים עולים',
  format($$insert into storage.objects (bucket_id, name) values ('payslips', '%1$s/1.pdf'), ('payslips', '%1$s/2.pdf'), ('payslips', '%1$s/3.pdf')$$, :'batch'));
select id as slip1 from payslips where batch_id = :'batch' and page_from = 1 \gset
select id as slip2 from payslips where batch_id = :'batch' and page_from = 2 \gset
select id as slip3 from payslips where batch_id = :'batch' and page_from = 3 \gset

select t_expect_fail('אין שיוך למשתמש לקוח',
  format($$select payslip_assign('%s', '20000000-0000-0000-0000-0000000070e1')$$, :'slip1'));
select t_expect_ok('שיוך לעובד הקבלן',
  format($$select payslip_assign('%s', '20000000-0000-0000-0000-0000000070c1')$$, :'slip1'));
select t_eq('המסך אומר מי הקבלן',
  (select r ->> 'contractor_name' from jsonb_array_elements(payslips_board(:'batch') -> 'slips') r
    where r ->> 'id' = :'slip1'), 'קבלן 70');

select t70_as('c1');
select t_eq('עובד הקבלן רואה את התלוש שלו',
  (select count(*)::int from payslips where id = :'slip1'), 1);
select t_eq('ופותח את העמוד שלו — ורק אותו', t70_files(:'batch'), '1.pdf');
select t_eq('וקיבל התראה שמובילה לתלושים שלו',
  (select count(*)::int || '|' || max(link) from notifications
    where recipient_id = '20000000-0000-0000-0000-0000000070c1' and type = 'payslip_available'),
  '1|/my/payslips');

select t70_as('c2');
select t_eq('עובד אחר של אותו קבלן אינו רואה אותו', (select count(*)::int from payslips where batch_id = :'batch'), 0);
select t_eq('ולא את העמוד', t70_files(:'batch'), '-');

-- ===== 2. "ללא שיוך" =======================================================

\echo '--- 2. ללא שיוך ---'
select t70_as('c1');
select t_expect_fail('עובד אינו מסמן', format($$select payslip_skip('%s')$$, :'slip2'));

select t70_as('b1');
select t_expect_fail('תלוש משויך אינו מסומן "ללא שיוך"', format($$select payslip_skip('%s')$$, :'slip1'));
select t_expect_ok('סימון "ללא שיוך"', format($$select payslip_skip('%s')$$, :'slip2'));
select t_eq('יורד מהממתינים — נשאר רק עמוד 3',
  (select string_agg(r ->> 'page_from', ',') from jsonb_array_elements(payslips_board(:'batch', null, true) -> 'slips') r),
  '3');
select t_eq('והשורה אומרת שסומן',
  (select r ->> 'skipped' from jsonb_array_elements(payslips_board(:'batch') -> 'slips') r
    where r ->> 'id' = :'slip2'), 'true');
select t_eq('סקירת הקבצים: אחד שויך, אחד ללא שיוך, משלושה',
  (select (b ->> 'assigned') || '/' || (b ->> 'skipped') || '/' || (b ->> 'slips')
     from jsonb_array_elements(payslip_batches_overview()) b where b ->> 'id' = :'batch'), '1/1/3');

select t70_as('a0');
-- ‏0222: "ללא שיוך" אינו נספר; 0223: גם לא תלוש של עובד קבלן — נשאר 0
select t_eq('סיכומי החודש אינם סופרים "ללא שיוך" ולא עובד קבלן',
  (payslips_board(:'batch') -> 'totals' ->> 'count')::int, 0);
select t_eq('השורה של עובד הקבלן מסומנת',
  (select r ->> 'contractor_worker' from jsonb_array_elements(payslips_board(:'batch') -> 'slips') r
    where r ->> 'id' = :'slip1'), 'true');

select t70_as('b1');
select t_expect_ok('החזרה לממתינים', format($$select payslip_skip('%s', false)$$, :'slip2'));
select t_eq('חזר לממתינים',
  (select count(*)::int from jsonb_array_elements(payslips_board(:'batch', null, true) -> 'slips') r
    where r ->> 'id' = :'slip2'), 1);
select t_expect_ok('ושוב "ללא שיוך"', format($$select payslip_skip('%s')$$, :'slip2'));
select t_expect_ok('שיוך מאוחר לתלוש שסומן',
  format($$select payslip_assign('%s', '20000000-0000-0000-0000-0000000070b1')$$, :'slip2'));
select t_eq('השיוך מנקה את הסימון',
  (select r ->> 'skipped' from jsonb_array_elements(payslips_board(:'batch') -> 'slips') r
    where r ->> 'id' = :'slip2'), 'false');

-- ===== 3. מה שהסקירה מצאה (0221) ==========================================

\echo '--- 3. 0221 ---'
reset role;
-- עובד קבלן שהכניסה שלו לא נפתחה
insert into profiles (id, user_id, user_kind, is_admin, full_name, contractor_id) values
  ('20000000-0000-0000-0000-0000000070c3', null, 'contractor_user', false, 'בלי כניסה 70',
   '10000000-0000-0000-0000-0000000070c0');
update payslips set detected_kind = 'other' where id = :'slip3';
set role authenticated;

select t70_as('b1');
select t_expect_fail('אין שיוך לעובד קבלן בלי כניסה',
  format($$select payslip_assign('%s', '20000000-0000-0000-0000-0000000070c3')$$, :'slip3'));
select t_eq('והוא אינו ברשימת השיוך',
  (select count(*)::int from jsonb_array_elements(payslip_assignees()) e
    where e ->> 'id' = '20000000-0000-0000-0000-0000000070c3'), 0);
select t_expect_fail('עמוד "לא תלוש" אינו מסומן "ללא שיוך"', format($$select payslip_skip('%s')$$, :'slip3'));

select payslip_batch_create('תלושים 70ב.pdf', 1, '2032-08-01') as batch2 \gset
reset role;
set role service_role;
select payslip_store_reading(:'batch2', 1, '{"kind":"payslip","employee_name":"מישהו 70","amounts":{"gross_pay":5000}}'::jsonb, 'test');
reset role;
set role authenticated;
select t70_as('b1');
select t_expect_ok('קיבוץ', format($$select payslip_apply_reading('%s')$$, :'batch2'));
select id as slip4 from payslips where batch_id = :'batch2' \gset
select t_expect_ok('"ללא שיוך"', format($$select payslip_skip('%s')$$, :'slip4'));
select t_expect_fail('קיבוץ מחדש נחסם כשיש "ללא שיוך"', format($$select payslip_apply_reading('%s')$$, :'batch2'));
select t_eq('והסימון נשאר',
  (select r ->> 'skipped' from jsonb_array_elements(payslips_board(:'batch2') -> 'slips') r), 'true');
select t_eq('קריאת הסכומים מחדש עדיין עובדת',
  payslip_refresh_amounts(:'batch2')::text, '{"manual": 0, "updated": 1}');

reset role;
