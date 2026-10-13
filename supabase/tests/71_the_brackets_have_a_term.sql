\pset tuples_only on
\pset format unaligned

-- ===========================================================================
-- ‏71: למדרגות יש תקופה (0223).
--
--   71a0 מנהל מערכת
--   71b1 מנהל תלושים (payslips.manage בלבד)
--   71c1 רואה עלות מעביד (payslips.employer_cost בלבד)
-- ===========================================================================

revoke execute on function payslip_store_reading(uuid, int, jsonb, text) from anon, authenticated, public;
revoke execute on function app.payslip_amounts_put(uuid, jsonb, text) from anon, authenticated, public;
revoke execute on function app.payslip_ni_recompute() from anon, authenticated, public;
revoke execute on function app.payslip_ni_brackets_for(date) from anon, authenticated, public;

insert into auth.users (id, email)
select ('00000000-0000-0000-0000-0000000071' || s)::uuid, 'p71-' || s || '@vl.test'
  from unnest(array['a0','b1','c1']) s;

insert into profiles (id, user_id, user_kind, is_admin, full_name) values
  ('20000000-0000-0000-0000-0000000071a0', '00000000-0000-0000-0000-0000000071a0', 'staff', true,  'מנהל 71'),
  ('20000000-0000-0000-0000-0000000071b1', '00000000-0000-0000-0000-0000000071b1', 'staff', false, 'מנהלת תלושים 71'),
  ('20000000-0000-0000-0000-0000000071c1', '00000000-0000-0000-0000-0000000071c1', 'staff', false, 'רואה חשבון 71');

insert into user_permission_grants (profile_id, permission_key, allowed) values
  ('20000000-0000-0000-0000-0000000071b1', 'payslips.manage', true),
  ('20000000-0000-0000-0000-0000000071c1', 'payslips.employer_cost', true);

create or replace function t71_as(p text) returns void language sql as $$
  select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000071' || p, false);
$$;
grant execute on function t71_as(text) to authenticated;

-- ביטוח לאומי מעסיק של התלוש
create or replace function t71_ni(p_slip uuid) returns text language sql stable as $$
  select coalesce((select employer_national_insurance::text from payslip_amounts where payslip_id = p_slip), '-')
$$;
grant execute on function t71_ni(uuid) to authenticated;

set role authenticated;

-- שני תלושים, מרץ ואוגוסט 2033, חייב מ.ה. 10,000 בכל אחד
select t71_as('b1');
select payslip_batch_create('תלושים 71.pdf', 2, '2033-03-01') as batch \gset
select id as slip_mar from payslips where batch_id = :'batch' and page_from = 1 \gset
select id as slip_aug from payslips where batch_id = :'batch' and page_from = 2 \gset
select t_expect_ok('התלוש השני — אוגוסט', format($$select payslip_set_period('%s', '2033-08-01')$$, :'slip_aug'));

select t71_as('c1');
select t_expect_ok('סכומי מרץ', format($$select payslip_amounts_save('%s', '{"gross_pay":10000,"taxable_income":10000}')$$, :'slip_mar'));
select t_expect_ok('סכומי אוגוסט', format($$select payslip_amounts_save('%s', '{"gross_pay":10000,"taxable_income":10000}')$$, :'slip_aug'));
select t_eq('בלי אף תקופה — אין ביטוח לאומי', t71_ni(:'slip_mar') || '|' || t71_ni(:'slip_aug'), '-|-');

-- ===== 1. מי קובע ==========================================================

\echo '--- 1. מי קובע ---'
select t71_as('b1');
select t_expect_fail('העזר הפנימי אינו פתוח למשתמש מחובר (0224)',
  $$select app.payslip_ni_brackets_for('2033-03-01')$$);
select t_expect_fail('מנהלת תלושים בלי עלות מעביד אינה קובעת',
  $$select payslip_ni_set_save(null, '2033-01-01', null, '[{"up_to":null,"rate":1}]')$$);

select t71_as('c1');
select t_expect_fail('בלי חודש תחולה', $$select payslip_ni_set_save(null, null, null, '[{"up_to":null,"rate":1}]')$$);
select t_expect_fail('תפוגה לפני תחולה',
  $$select payslip_ni_set_save(null, '2033-06-01', '2033-01-01', '[{"up_to":null,"rate":1}]')$$);
select t_expect_fail('בלי מדרגות', $$select payslip_ni_set_save(null, '2033-01-01', null, '[]')$$);

-- ===== 2. כל תלוש לפי החודש שלו ============================================

\echo '--- 2. לפי החודש ---'
select payslip_ni_set_save(null, '2033-01-15', '2033-06-30', '[{"up_to":null,"rate":1}]') as set_h1 \gset
select t_eq('התקופה נחתכת לחודשים',
  (select valid_from || '|' || valid_to from payslip_ni_bracket_sets where id = :'set_h1'), '2033-01-01|2033-06-01');
select t_eq('מרץ — 1%, ואוגוסט מחוץ לתקופה', t71_ni(:'slip_mar') || '|' || t71_ni(:'slip_aug'), '100.00|-');

select t_expect_fail('תקופה חופפת נדחית',
  $$select payslip_ni_set_save(null, '2033-06-01', null, '[{"up_to":null,"rate":2}]')$$);
select payslip_ni_set_save(null, '2033-07-01', null, '[{"up_to":null,"rate":2}]') as set_h2 \gset
select t_eq('אוגוסט — 2% מהתקופה החדשה, ומרץ לא זז', t71_ni(:'slip_mar') || '|' || t71_ni(:'slip_aug'), '100.00|200.00');

select t_expect_ok('שינוי המדרגות של התקופה השנייה',
  format($$select payslip_ni_set_save('%s', '2033-07-01', null, '[{"up_to":null,"rate":3}]')$$, :'set_h2'));
select t_eq('רק אוגוסט זז', t71_ni(:'slip_mar') || '|' || t71_ni(:'slip_aug'), '100.00|300.00');

-- ===== 3. תלוש שעבר חודש ===================================================

\echo '--- 3. שינוי חודש ---'
select t71_as('b1');
select t_expect_ok('מרץ עובר לספטמבר', format($$select payslip_set_period('%s', '2033-09-01')$$, :'slip_mar'));
select t71_as('c1');
select t_eq('ומחושב לפי ספטמבר', t71_ni(:'slip_mar'), '300.00');
select t71_as('b1');
select t_expect_ok('וחוזר למרץ', format($$select payslip_set_period('%s', '2033-03-01')$$, :'slip_mar'));

-- ===== 4. הסרה =============================================================

\echo '--- 4. הסרה ---'
select t71_as('b1');
select t_expect_fail('מנהלת תלושים אינה מסירה', format($$select payslip_ni_set_remove('%s')$$, :'set_h2'));
select t71_as('c1');
select t_expect_ok('הסרת התקופה השנייה', format($$select payslip_ni_set_remove('%s')$$, :'set_h2'));
select t_eq('אוגוסט בלי מדרגות, מרץ לא זז', t71_ni(:'slip_mar') || '|' || t71_ni(:'slip_aug'), '100.00|-');
select t_eq('והתקופה אינה נראית עוד',
  (select count(*)::int from payslip_ni_bracket_sets where id = :'set_h2'), 0);
select t_expect_ok('אחרי הסרה — אפשר לפתוח שוב את אותה תקופה',
  $$select payslip_ni_set_save(null, '2033-07-01', null, '[{"up_to":null,"rate":2}]')$$);

-- ‏payslip_ni_brackets_save (תאימות, 0219): סט אחד בלי תאריכים במקום כולם
select t_expect_ok('שמירה בלי תאריכים', $$select payslip_ni_brackets_save('[{"up_to":null,"rate":5}]')$$);
select t_eq('סט אחד, לכל הזמנים',
  (select count(*)::int || '|' || min(valid_from) || '|' || coalesce(max(valid_to)::text, '-') from payslip_ni_bracket_sets),
  '1|2000-01-01|-');
select t_eq('ושני התלושים לפיו', t71_ni(:'slip_mar') || '|' || t71_ni(:'slip_aug'), '500.00|500.00');
select t_expect_ok('ניקוי', $$select payslip_ni_brackets_save('[]')$$);

reset role;
