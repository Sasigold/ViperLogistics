\pset tuples_only on
\pset format unaligned

-- ===========================================================================
-- ‏69: הבעלים קובע איך מחושבת עלות המעביד (0219).
--
--   69a0 מנהל מערכת
--   69b1 מנהל תלושים (payslips.manage בלבד)
--   69c1 רואה עלות מעביד (payslips.employer_cost בלבד)
--   69d1 עובד "יוסי מדרגות 69"
--   69d2 עובדת "רותי מדרגות 69"
-- ===========================================================================

-- ‏01_seed.sql מעניק ל-authenticated את כל הפונקציות אחרי המיגרציות; השלילות
-- של 0218/0219 נאמרות כאן שוב.
revoke execute on function payslip_store_reading(uuid, int, jsonb, text) from anon, authenticated, public;
revoke execute on function app.payslip_amounts_put(uuid, jsonb, text) from anon, authenticated, public;
revoke execute on function app.payslip_amounts_compute() from anon, authenticated, public;

insert into auth.users (id, email)
select ('00000000-0000-0000-0000-0000000069' || s)::uuid, 'p69-' || s || '@vl.test'
  from unnest(array['a0','b1','c1','d1','d2']) s;

insert into profiles (id, user_id, user_kind, is_admin, full_name) values
  ('20000000-0000-0000-0000-0000000069a0', '00000000-0000-0000-0000-0000000069a0', 'staff', true,  'מנהל 69'),
  ('20000000-0000-0000-0000-0000000069b1', '00000000-0000-0000-0000-0000000069b1', 'staff', false, 'מנהלת תלושים 69'),
  ('20000000-0000-0000-0000-0000000069c1', '00000000-0000-0000-0000-0000000069c1', 'staff', false, 'רואה חשבון 69'),
  ('20000000-0000-0000-0000-0000000069d1', '00000000-0000-0000-0000-0000000069d1', 'staff', false, 'יוסי מדרגות 69'),
  ('20000000-0000-0000-0000-0000000069d2', '00000000-0000-0000-0000-0000000069d2', 'staff', false, 'רותי מדרגות 69');

insert into user_permission_grants (profile_id, permission_key, allowed) values
  ('20000000-0000-0000-0000-0000000069b1', 'payslips.manage', true),
  ('20000000-0000-0000-0000-0000000069c1', 'payslips.employer_cost', true);

create or replace function t69_as(p text) returns void language sql as $$
  select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000069' || p, false);
$$;
grant execute on function t69_as(text) to authenticated;

-- ===== 1. החשבון ===========================================================

\echo '--- 1. מדרגות שוליות ---'
select t_eq('10,000 במדרגות 7,000/1% ו-15,000/5%: ‏70 + 150',
  app.payslip_employer_ni(10000, '[{"up_to":7000,"rate":1},{"up_to":15000,"rate":5}]'), 220.00::numeric);
select t_eq('מעל התקרה האחרונה — אין חיוב',
  app.payslip_employer_ni(20000, '[{"up_to":7000,"rate":1},{"up_to":15000,"rate":5}]'), 470.00::numeric);
select t_eq('בתוך המדרגה הראשונה',
  app.payslip_employer_ni(5000, '[{"up_to":7000,"rate":1},{"up_to":15000,"rate":5}]'), 50.00::numeric);
select t_eq('מדרגה אחרונה בלי תקרה חלה על כל השאר',
  app.payslip_employer_ni(20000, '[{"up_to":7000,"rate":1},{"up_to":null,"rate":5}]'), 720.00::numeric);
select t_eq('בלי חייב מ.ה. — אין חישוב',
  app.payslip_employer_ni(null, '[{"up_to":null,"rate":5}]'), null::numeric);
select t_eq('בלי מדרגות — אין חישוב', app.payslip_employer_ni(10000, '[]'), null::numeric);
select t_eq('עיגול לאגורות', app.payslip_employer_ni(333.33, '[{"up_to":null,"rate":4.51}]'), 15.03::numeric);

-- ===== 2. מי קובע ==========================================================

\echo '--- 2. מי קובע את המדרגות ---'
set role authenticated;

select t69_as('b1');
select t_expect_fail('מנהלת תלושים בלי עלות מעביד אינה קובעת מדרגות',
  $$select payslip_ni_brackets_save('[{"up_to":null,"rate":1}]')$$);
select t_eq('ואינה רואה אותן', (select count(*)::int from payslip_settings), 0);

select t69_as('d1');
select t_expect_fail('עובד אינו קובע מדרגות', $$select payslip_ni_brackets_save('[]')$$);
select t_eq('ואינו רואה אותן', (select count(*)::int from payslip_settings), 0);
select t_rows('ואינו כותב לטבלה ישירות',
  $$update payslip_settings set value = '[]'$$, 0);

select t69_as('c1');
select t_expect_fail('מדרגה שאינה עולה נדחית',
  $$select payslip_ni_brackets_save('[{"up_to":7000,"rate":1},{"up_to":5000,"rate":5}]')$$);
select t_expect_fail('בלי תקרה באמצע נדחה',
  $$select payslip_ni_brackets_save('[{"up_to":null,"rate":1},{"up_to":5000,"rate":5}]')$$);
select t_expect_fail('אחוז מעל 100 נדחה',
  $$select payslip_ni_brackets_save('[{"up_to":null,"rate":101}]')$$);
select t_expect_fail('אחוז שאינו מספר נדחה',
  $$select payslip_ni_brackets_save('[{"up_to":null,"rate":"abc"}]')$$);
select t_expect_fail('לא רשימה — נדחה', $$select payslip_ni_brackets_save('{"rate":1}')$$);
select t_expect_ok('רואה העלות קובע מדרגות (מחרוזות של מספרים מתקבלות)',
  $$select payslip_ni_brackets_save('[{"up_to":"7000","rate":"1"},{"up_to":15000,"rate":5}]')$$);
select t_eq('נשמרות מנורמלות',
  (select value::text from payslip_settings where key = 'employer_ni_brackets'),
  '[{"rate": 1, "up_to": 7000}, {"rate": 5, "up_to": 15000}]');

-- ===== 3. קריאה מחדש של קובץ ששויך ========================================

\echo '--- 3. קריאת הסכומים מחדש ---'
select t69_as('b1');
select payslip_batch_create('תלושים 69.pdf', 2, '2032-03-01') as batch \gset

reset role;
set role service_role;
-- הקריאה הראשונה, לפני 0219: בלי חייב מ.ה.
select payslip_store_reading(:'batch', 1, '{
  "kind":"payslip","employee_name":"יוסי מדרגות 69","employee_no":"691","period":"2032-03-01",
  "amounts":{"gross_pay":10000,"net_pay":8000,"employer_pension":650,"employer_severance":833.33}}'::jsonb, 'test');
select payslip_store_reading(:'batch', 2, '{
  "kind":"payslip","employee_name":"רותי מדרגות 69","employee_no":"692","period":"2032-03-01",
  "amounts":{"gross_pay":8000,"net_pay":6800}}'::jsonb, 'test');
reset role;
set role authenticated;

select t69_as('b1');
select t_expect_ok('קיבוץ', format($$select payslip_apply_reading('%s')$$, :'batch'));
select id as slip1 from payslips where batch_id = :'batch' and page_from = 1 \gset
select id as slip2 from payslips where batch_id = :'batch' and page_from = 2 \gset
select t_expect_ok('שיוך יוסי',
  format($$select payslip_assign('%s', '20000000-0000-0000-0000-0000000069d1')$$, :'slip1'));

select t69_as('c1');
select t_eq('בלי חייב מ.ה. — אין ביטוח לאומי מעסיק, והעלות בלעדיו',
  (select coalesce(employer_national_insurance::text, '-') || '|' || employer_cost::text
     from payslip_amounts where payslip_id = :'slip1'), '-|11483.33');
select t_expect_ok('רותי מוקלדת ביד',
  format($$select payslip_amounts_save('%s', '{"gross_pay":8100,"net_pay":6800,"taxable_income":8100}')$$, :'slip2'));
-- ‏8,100 + 7,000 × 1% + 1,100 × 5%
select t_eq('ידני: הביטוח הלאומי מחושב גם כאן', (select employer_cost from payslip_amounts where payslip_id = :'slip2'),
  8225.00::numeric);

reset role;
set role service_role;
-- הקריאה מחדש, עם הרכיבים של 0219 (וזקיפה שנזרקת)
select payslip_store_reading(:'batch', 1, '{
  "kind":"payslip","employee_name":"יוסי מדרגות 69","employee_no":"691","period":"2032-03-01",
  "amounts":{"gross_pay":10000,"net_pay":8000,"employer_pension":650,"employer_severance":833.33,
             "taxable_income":10000,"employee_health_tax":310,"imputed_income":500}}'::jsonb, 'test');
select payslip_store_reading(:'batch', 2, '{
  "kind":"payslip","employee_name":"רותי מדרגות 69","employee_no":"692","period":"2032-03-01",
  "amounts":{"gross_pay":9999,"taxable_income":9999}}'::jsonb, 'test');
reset role;
set role authenticated;

select t69_as('b1');
select t_expect_fail('קיבוץ מחדש עדיין נחסם אחרי שיוך',
  format($$select payslip_apply_reading('%s')$$, :'batch'));
select t69_as('c1');
select t_expect_fail('רואה עלות בלי ניהול אינו קורא מחדש',
  format($$select payslip_refresh_amounts('%s')$$, :'batch'));
select t69_as('d1');
select t_expect_fail('עובד אינו קורא מחדש', format($$select payslip_refresh_amounts('%s')$$, :'batch'));

select t69_as('b1');
select t_eq('הסכומים מתעדכנים בלי לגעת בשיוך; הידני נשאר',
  payslip_refresh_amounts(:'batch')::text, '{"manual": 1, "updated": 1}');
select t_eq('השיוך והטווחים במקומם',
  (select string_agg(page_from || '-' || page_to || ':' || coalesce(profile_id::text, '-'), ',' order by page_from)
     from payslips where batch_id = :'batch'),
  '1-1:20000000-0000-0000-0000-0000000069d1,2-2:-');

select t69_as('c1');
-- ‏10,000 + 650 + 833.33 + (70 + 150)
select t_eq('יוסי: ביטוח לאומי מעסיק מחייב מ.ה., והעלות = ברוטו + תשלומי המעסיק',
  (select employer_national_insurance::text || '|' || employer_cost::text
     from payslip_amounts where payslip_id = :'slip1'), '220.00|11703.33');
select t_eq('דמי בריאות נשמרים, וזקיפה אינה נשמרת',
  (select employee_health_tax::text || '|' || coalesce(imputed_income::text, '-')
     from payslip_amounts where payslip_id = :'slip1'), '310.00|-');
select t_eq('רותי: הידני לא נדרס',
  (select gross_pay::text || '|' || source from payslip_amounts where payslip_id = :'slip2'), '8100.00|manual');

-- ===== 4. שינוי מדרגות מחשב מחדש ==========================================

\echo '--- 4. שינוי מדרגות ---'
select t_eq('שמירה מחזירה כמה תלושים חושבו מחדש',
  payslip_ni_brackets_save('[{"up_to":null,"rate":2}]') >= 2, true);
select t_eq('יוסי: 2% מ-10,000',
  (select employer_national_insurance from payslip_amounts where payslip_id = :'slip1'), 200.00::numeric);
select t_eq('רותי: 2% מ-8,100',
  (select employer_national_insurance from payslip_amounts where payslip_id = :'slip2'), 162.00::numeric);
select t_expect_ok('ניקוי המדרגות', $$select payslip_ni_brackets_save('[]')$$);
select t_eq('בלי מדרגות — אין ביטוח לאומי מעסיק',
  (select count(*)::int from payslip_amounts
    where payslip_id in (:'slip1', :'slip2') and employer_national_insurance is not null), 0);

select t69_as('d1');
select t_eq('העובד עדיין אינו רואה סכומים', (select count(*)::int from payslip_amounts), 0);

reset role;
