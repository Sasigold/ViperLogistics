\pset tuples_only on
\pset format unaligned

-- ===========================================================================
-- ‏68: התלוש מוצא את בעליו (0218).
--
-- קובץ של ארבעה עמודים: תלוש של שני עמודים (שמעון, מספר עובד 17), תלוש של
-- עמוד אחד (דנה, בלי מספר, עם מספור עמודים של הקובץ כולו) ועמוד שאינו תלוש.
--
--   68a0 מנהל מערכת
--   68b1 מנהל תלושים (payslips.manage בלבד)
--   68c1 רואה עלות מעביד (payslips.employer_cost בלבד)
--   68d1 עובד "שמעון אברהמי 68"
--   68d2 עובדת "דנה לויתן 68"
--   68e1 משתמש לקוח
-- ===========================================================================

-- ‏01_seed.sql מעניק ל-authenticated את כל הפונקציות *אחרי* המיגרציות (ראו
-- 0194), ולכן השלילות של 0218 נאמרות כאן שוב — אותן שורות בדיוק.
revoke execute on function payslip_store_reading(uuid, int, jsonb, text) from anon, authenticated, public;
revoke execute on function app.notify_payslip_available(uuid) from anon, authenticated, public;

insert into auth.users (id, email)
select ('00000000-0000-0000-0000-0000000068' || s)::uuid, 'p68-' || s || '@vl.test'
  from unnest(array['a0','b1','c1','d1','d2','e1']) s;

insert into customers (id, name) values
  ('10000000-0000-0000-0000-0000000068e0', 'לקוח 68');

insert into profiles (id, user_id, user_kind, is_admin, full_name, customer_id) values
  ('20000000-0000-0000-0000-0000000068a0', '00000000-0000-0000-0000-0000000068a0', 'staff', true,  'מנהל 68', null),
  ('20000000-0000-0000-0000-0000000068b1', '00000000-0000-0000-0000-0000000068b1', 'staff', false, 'מנהלת תלושים 68', null),
  ('20000000-0000-0000-0000-0000000068c1', '00000000-0000-0000-0000-0000000068c1', 'staff', false, 'רואה חשבון 68', null),
  ('20000000-0000-0000-0000-0000000068d1', '00000000-0000-0000-0000-0000000068d1', 'staff', false, 'שמעון אברהמי 68', null),
  ('20000000-0000-0000-0000-0000000068d2', '00000000-0000-0000-0000-0000000068d2', 'staff', false, 'דנה לויתן 68', null),
  ('20000000-0000-0000-0000-0000000068e1', '00000000-0000-0000-0000-0000000068e1', 'customer_user', false, 'לקוח 68',
   '10000000-0000-0000-0000-0000000068e0');

insert into profile_roles (profile_id, role_id)
select p, (select id from permission_roles where key = 'worker' and deleted_at is null limit 1)
  from unnest(array['20000000-0000-0000-0000-0000000068d1',
                    '20000000-0000-0000-0000-0000000068d2']::uuid[]) p;

insert into user_permission_grants (profile_id, permission_key, allowed) values
  ('20000000-0000-0000-0000-0000000068b1', 'payslips.manage', true),
  ('20000000-0000-0000-0000-0000000068c1', 'payslips.employer_cost', true);

create or replace function t68_as(p text) returns void language sql as $$
  select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000068' || p, false);
$$;
grant execute on function t68_as(text) to authenticated;

-- התלושים שהקורא רואה בקובץ, כ-'עמוד-עמוד' לפי הסדר
create or replace function t68_slips(p_batch uuid) returns text language sql stable as $$
  select coalesce(string_agg(page_from || '-' || page_to, ',' order by page_from), '-')
    from payslips where batch_id = p_batch
$$;
grant execute on function t68_slips(uuid) to authenticated;

-- כמה עמודים מהקובץ הקורא יכול לפתוח ב-Storage
create or replace function t68_files(p_batch uuid) returns text language sql stable as $$
  select coalesce(string_agg(split_part(name, '/', 2), ',' order by name), '-')
    from storage.objects where bucket_id = 'payslips' and name like p_batch::text || '/%'
$$;
grant execute on function t68_files(uuid) to authenticated;

-- ===== 1. ההרשאות ==========================================================

\echo '--- 1. ההרשאות ---'
set role authenticated;

select t68_as('d1');
select t_eq('עובד: רואה את התלושים שלו (ברירת מחדל)', app.can_view_own_payslips(), true);
select t_eq('עובד: אינו מנהל תלושים', app.can_manage_payslips(), false);
select t_eq('עובד: אינו רואה עלות מעביד', app.can_view_payslip_costs(), false);

select t68_as('b1');
select t_eq('מנהלת תלושים: מנהלת', app.can_manage_payslips(), true);
select t_eq('מנהלת תלושים: בלי עלות מעביד', app.can_view_payslip_costs(), false);

select t68_as('c1');
select t_eq('רואה עלות: רואה', app.can_view_payslip_costs(), true);
select t_eq('רואה עלות: אינו מנהל', app.can_manage_payslips(), false);

select t68_as('e1');
select t_eq('משתמש לקוח: אין לו תלושים (applies_to = staff)', app.can_view_own_payslips(), false);

select t68_as('a0');
select t_eq('מנהל מערכת: הכול', app.can_manage_payslips() and app.can_view_payslip_costs(), true);

-- ===== 2. העלאה ============================================================

\echo '--- 2. העלאה ---'
select t68_as('d1');
select t_expect_fail('עובד אינו מעלה קובץ תלושים',
  $$select payslip_batch_create('x.pdf', 2, '2031-05-01')$$);

select t68_as('b1');
select t_expect_fail('קובץ ריק נדחה', $$select payslip_batch_create('x.pdf', 0, '2031-05-01')$$);
select t_expect_fail('מעל 200 עמודים נדחה', $$select payslip_batch_create('x.pdf', 201, '2031-05-01')$$);

select payslip_batch_create('תלושים 05-2031.pdf', 4, '2031-05-17') as batch1 \gset

select t_eq('כל עמוד נפתח כתלוש', t68_slips(:'batch1'), '1-1,2-2,3-3,4-4');
select t_eq('החודש נחתך לראשון בחודש',
  (select string_agg(distinct period::text, ',') from payslips where batch_id = :'batch1'), '2031-05-01');

select t_expect_ok('מנהלת התלושים מעלה את עמוד 1',
  format($$insert into storage.objects (bucket_id, name) values ('payslips', '%s/1.pdf')$$, :'batch1'));
select t_expect_ok('ואת עמודים 2-4',
  format($$insert into storage.objects (bucket_id, name) values ('payslips', '%1$s/2.pdf'), ('payslips', '%1$s/3.pdf'), ('payslips', '%1$s/4.pdf')$$, :'batch1'));
select t_expect_fail('עמוד שהקובץ אינו מכיר נדחה',
  format($$insert into storage.objects (bucket_id, name) values ('payslips', '%s/5.pdf')$$, :'batch1'));
select t_expect_fail('נתיב שאינו <קובץ>/<עמוד>.pdf נדחה',
  format($$insert into storage.objects (bucket_id, name) values ('payslips', '%s/x/1.pdf')$$, :'batch1'));

select t68_as('d1');
select t_expect_fail('עובד אינו מעלה עמוד',
  format($$insert into storage.objects (bucket_id, name) values ('payslips', '%s/4.pdf')$$, :'batch1'));
select t_eq('עובד: לא רואה את הקובץ', (select count(*)::int from payslip_batches where id = :'batch1'), 0);
select t_eq('עובד: לא רואה תלושים שלא שויכו אליו', t68_slips(:'batch1'), '-');
select t_eq('עובד: לא פותח את העמודים', t68_files(:'batch1'), '-');

-- ===== 3. הקריאה ===========================================================

\echo '--- 3. הקריאה ---'
select t68_as('b1');
select t_expect_fail('מנהלת תלושים אינה כותבת קריאה בעצמה (service_role בלבד)',
  format($$select payslip_store_reading('%s', 1, '{"kind":"payslip"}')$$, :'batch1'));
select t_expect_fail('אין קיבוץ לפני שנקרא דבר',
  format($$select payslip_apply_reading('%s')$$, :'batch1'));

reset role;
set role service_role;
select payslip_store_reading(:'batch1', 1, '{
  "kind":"payslip","employee_name":"אברהמי שמעון 68","employee_no":"17","period":"2031-05-01",
  "page_index":1,"page_total":2,"amounts":{"gross_pay":9000}}'::jsonb, 'test');
select payslip_store_reading(:'batch1', 2, '{
  "kind":"payslip","employee_name":null,"employee_no":"17","period":"2031-05-01",
  "page_index":2,"page_total":2,"amounts":{"gross_pay":12000,"net_pay":9000,"imputed_income":1000,
  "income_tax":1200,"employee_national_insurance":800,"employee_pension":720,
  "employer_pension":780,"employer_severance":750,"taxable_income":11000,
  "printed_employer_cost":13800}}'::jsonb, 'test');
-- מספור של הקובץ כולו ("עמוד 3"): עובדת אחרת, ולכן אינו המשך
select payslip_store_reading(:'batch1', 3, '{
  "kind":"payslip","employee_name":"דנה לויתן 68","employee_no":null,"period":"2031-05-01",
  "page_index":3,"page_total":4,"amounts":{"gross_pay":6000,"net_pay":5100}}'::jsonb, 'test');
select payslip_store_reading(:'batch1', 4, '{"kind":"other"}'::jsonb, 'test');
select t_expect_fail('עמוד מעבר לקובץ נדחה',
  format($$select payslip_store_reading('%s', 9, '{"kind":"other"}')$$, :'batch1'));
reset role;
set role authenticated;

select t68_as('b1');
select t_eq('הקיבוץ: תלוש של שני עמודים, תלוש של אחד, ועמוד שאינו תלוש',
  payslip_apply_reading(:'batch1')::text, '{"other": 1, "pages": 4, "slips": 2, "read_pages": 4}');
select t_eq('הטווחים', t68_slips(:'batch1'), '1-2,3-3,4-4');
select t_eq('הזהות מהעמוד הראשון',
  (select detected_name || '|' || detected_employee_no || '|' || link_key
     from payslips where batch_id = :'batch1' and page_from = 1), 'אברהמי שמעון 68|17|e:17');
select t_eq('בלי מספר עובד — מפתח לפי השם, בלי תלות בסדר המילים',
  (select link_key from payslips where batch_id = :'batch1' and page_from = 3),
  'n:' || app.payslip_name_key('לויתן דנה 68'));
select t_eq('עמוד שאינו תלוש מסומן ככזה, בלי מפתח',
  (select detected_kind || '|' || coalesce(link_key, '-') from payslips where batch_id = :'batch1' and page_from = 4),
  'other|-');
select t_eq('מנהלת תלושים בלי עלות מעביד אינה רואה סכומים',
  (select count(*)::int from payslip_amounts a join payslips s on s.id = a.payslip_id where s.batch_id = :'batch1'), 0);

select id as slip1 from payslips where batch_id = :'batch1' and page_from = 1 \gset
select id as slip3 from payslips where batch_id = :'batch1' and page_from = 3 \gset
select id as slip4 from payslips where batch_id = :'batch1' and page_from = 4 \gset

-- ===== 4. עלות המעביד ======================================================

\echo '--- 4. עלות המעביד ---'
select t68_as('c1');
-- מדרגות ביטוח לאומי מעסיק (0219): עד 7,000 — 1%, מעליהן 5%
select t_eq('שמירת המדרגות מחשבת מחדש את התלושים שכבר נקראו',
  payslip_ni_brackets_save('[{"up_to":7000,"rate":1},{"up_to":null,"rate":5}]') >= 2, true);
select t_eq('הסכומים של תלוש רב-עמודי: הערך האחרון לכל רכיב',
  (select gross_pay::text || '|' || net_pay::text from payslip_amounts where payslip_id = :'slip1'), '12000.00|9000.00');
-- ‏12,000 + 780 קופ"ג + 750 פיצויים + ביטוח לאומי על חייב מ.ה. 11,000:
-- ‏7,000 × 1% + 4,000 × 5% = 270. הזקיפות שנקראו (1,000) אינן מופחתות (0219).
select t_eq('ביטוח לאומי מעסיק מחושב מחייב מ.ה. לפי המדרגות',
  (select employer_national_insurance from payslip_amounts where payslip_id = :'slip1'), 270.00::numeric);
select t_eq('עלות מעביד = ברוטו + תשלומי המעסיק',
  (select employer_cost from payslip_amounts where payslip_id = :'slip1'), 13800.00::numeric);
select t_eq('ההפרשות לבדן', (select employer_contributions from payslip_amounts where payslip_id = :'slip1'), 1800.00::numeric);
select t_eq('הניכויים = ברוטו − נטו (אינם עלות מעביד)',
  (select deductions from payslip_amounts where payslip_id = :'slip1'), 3000.00::numeric);
select t_eq('ומתיישבת עם "עלות מעביד" שהתלוש מדפיס',
  (select employer_cost = printed_employer_cost from payslip_amounts where payslip_id = :'slip1'), true);
select t_eq('מקור הסכומים: הקריאה', (select source from payslip_amounts where payslip_id = :'slip1'), 'reading');
select t_eq('עמוד שאינו תלוש — בלי סכומים',
  (select count(*)::int from payslip_amounts where payslip_id = :'slip4'), 0);
select t_expect_fail('רואה עלות אינו משייך', format($$select payslip_assign('%s', '20000000-0000-0000-0000-0000000068d1')$$, :'slip1'));

select t_expect_ok('רואה עלות מתקן סכומים ביד',
  format($$select payslip_amounts_save('%s', '{"gross_pay":"6000","net_pay":5100,"employer_pension":390,"employer_severance":375,"taxable_income":6000}')$$, :'slip3'));
-- ‏6,000 + 390 + 375 + 6,000 × 1%
select t_eq('ועלות המעביד מתעדכנת', (select employer_cost from payslip_amounts where payslip_id = :'slip3'), 6825.00::numeric);
select t_eq('המקור: ידני', (select source from payslip_amounts where payslip_id = :'slip3'), 'manual');
select t_expect_ok('הפרשה בלי ברוטו נשמרת',
  format($$select payslip_amounts_save('%s', '{"employer_pension":100,"net_pay":"abc"}')$$, :'slip4'));
select t_eq('אבל בלי ברוטו אין עלות מעביד, ומה שאינו מספר אינו נשמר',
  (select (employer_cost is null)::text || '|' || coalesce(net_pay::text, '-') || '|' || employer_contributions::text
     from payslip_amounts where payslip_id = :'slip4'), 'true|-|100.00');

select t68_as('b1');
select t_expect_fail('מנהלת תלושים בלי עלות מעביד אינה עורכת סכומים',
  format($$select payslip_amounts_save('%s', '{"gross_pay":1}')$$, :'slip3'));

-- ===== 5. מה המסך מציע =====================================================

\echo '--- 5. ההצעה ---'
select t_eq('"אברהמי שמעון" בתלוש מציע את "שמעון אברהמי" במערכת',
  (select r ->> 'suggested_profile_id' from jsonb_array_elements(payslips_board(:'batch1') -> 'slips') r
    where r ->> 'id' = :'slip1'), '20000000-0000-0000-0000-0000000068d1');
select t_eq('ודנה — את דנה',
  (select r ->> 'suggested_profile_id' from jsonb_array_elements(payslips_board(:'batch1') -> 'slips') r
    where r ->> 'id' = :'slip3'), '20000000-0000-0000-0000-0000000068d2');
select t_eq('עמוד שאינו תלוש אינו מציע איש',
  (select r ->> 'suggested_profile_id' from jsonb_array_elements(payslips_board(:'batch1') -> 'slips') r
    where r ->> 'id' = :'slip4'), null);
select t_eq('בלי עלות מעביד — המסך אינו מחזיר סכומים',
  (select count(*)::int from jsonb_array_elements(payslips_board(:'batch1') -> 'slips') r
    where r -> 'amounts' <> 'null'::jsonb), 0);
select t_eq('ולא סיכומים', (payslips_board(:'batch1') -> 'totals') = 'null'::jsonb, true);

select t68_as('d1');
select t_expect_fail('עובד אינו פותח את מסך התלושים', $$select payslips_board()$$);

-- ===== 6. שיוך =============================================================

\echo '--- 6. שיוך ---'
select t68_as('b1');
select t_expect_fail('אין שיוך למשתמש לקוח',
  format($$select payslip_assign('%s', '20000000-0000-0000-0000-0000000068e1')$$, :'slip1'));
select t_expect_ok('שיוך התלוש של שמעון',
  format($$select payslip_assign('%s', '20000000-0000-0000-0000-0000000068d1')$$, :'slip1'));
select t_expect_fail('מרגע ששויך תלוש — אין קיבוץ מחדש',
  format($$select payslip_apply_reading('%s')$$, :'batch1'));

select t68_as('d1');
select t_eq('שמעון רואה את התלוש שלו', t68_slips(:'batch1'), '1-2');
select t_eq('ופותח את שני העמודים שלו — ורק אותם', t68_files(:'batch1'), '1.pdf,2.pdf');
select t_eq('אבל לא את הסכומים', (select count(*)::int from payslip_amounts), 0);
select t_eq('ולא את הקובץ', (select count(*)::int from payslip_batches), 0);
select t_rows('ואינו משנה את התלוש בעצמו',
  format($$update payslips set profile_id = null where id = '%s'$$, :'slip1'), 0);
select t_expect_fail('ואינו משייך', format($$select payslip_assign('%s', '20000000-0000-0000-0000-0000000068d1')$$, :'slip3'));
select t_eq('קיבל התראה שמובילה לתלושים שלו',
  (select count(*)::int || '|' || max(link) from notifications
    where recipient_id = '20000000-0000-0000-0000-0000000068d1' and type = 'payslip_available'),
  '1|/my/payslips');
select t_eq('ובה החודש', (select body from notifications
    where recipient_id = '20000000-0000-0000-0000-0000000068d1' and type = 'payslip_available'),
  'תלוש השכר למאי 2031 זמין לצפייה ולהורדה');

select t68_as('d2');
select t_eq('דנה אינה רואה את התלוש של שמעון', t68_slips(:'batch1'), '-');
select t_eq('ולא את העמודים שלו', t68_files(:'batch1'), '-');

-- ===== 7. איחוד ופיצול =====================================================

\echo '--- 7. איחוד ופיצול ---'
select t68_as('b1');
select t_expect_fail('תלוש של עמוד אחד אינו מתפצל', format($$select payslip_split('%s')$$, :'slip3'));
select t_expect_ok('פיצול התלוש של שמעון', format($$select payslip_split('%s')$$, :'slip1'));
select t_eq('שני תלושים במקום אחד', t68_slips(:'batch1'), '1-1,2-2,3-3,4-4');
select t_eq('העמוד שנפתח — לא משויך, ועם מה שנקרא ממנו',
  (select coalesce(profile_id::text, '-') || '|' || detected_employee_no from payslips
    where batch_id = :'batch1' and page_from = 2), '-|17');

select t68_as('d1');
select t_eq('שמעון פותח עכשיו רק את העמוד הראשון', t68_files(:'batch1'), '1.pdf');

select t68_as('b1');
select id as slip2 from payslips where batch_id = :'batch1' and page_from = 2 \gset
select t_eq('צירוף העמוד בחזרה לתלוש שלפניו',
  payslip_merge_previous(:'slip2')::text, :'slip1');
select t_eq('הטווח חזר', t68_slips(:'batch1'), '1-2,3-3,4-4');
select t_expect_ok('שיוך התלוש של דנה',
  format($$select payslip_assign('%s', '20000000-0000-0000-0000-0000000068d2')$$, :'slip3'));
select t_expect_fail('אין צירוף של תלוש ששויך לעובד אחר',
  format($$select payslip_merge_previous('%s')$$, :'slip3'));
select t_expect_fail('אין צירוף לתלוש הראשון בקובץ',
  format($$select payslip_merge_previous('%s')$$, :'slip1'));

select t68_as('c1');
select t_eq('הסכומים נשארו עם התלוש', (select employer_cost from payslip_amounts where payslip_id = :'slip1'), 13800.00::numeric);
select t_eq('סיכומי החודש — על תלושים ששויכו',
  (payslips_board(null, '2031-05-01') -> 'totals' ->> 'employer_cost')::numeric, 20625.00::numeric);
select t_eq('ומספרם', (payslips_board(null, '2031-05-01') -> 'totals' ->> 'count')::int, 2);

-- ===== 8. "רק מה שמותר" ====================================================

\echo '--- 8. דחייה אישית של view_own ---'
-- הטריגר על המענקים שואל מי מעניק — מנהל המערכת
select t68_as('a0');
reset role;
insert into user_permission_grants (profile_id, permission_key, allowed) values
  ('20000000-0000-0000-0000-0000000068d2', 'payslips.view_own', false);
set role authenticated;
select t68_as('d2');
select t_eq('דחייה מפורשת: דנה אינה רואה את התלוש שלה', t68_slips(:'batch1'), '-');
select t_eq('ולא את העמוד', t68_files(:'batch1'), '-');
select t68_as('a0');
reset role;
delete from user_permission_grants
 where profile_id = '20000000-0000-0000-0000-0000000068d2' and permission_key = 'payslips.view_own';
set role authenticated;
select t68_as('d2');
select t_eq('בלי הדחייה — רואה', t68_files(:'batch1'), '3.pdf');

select t68_as('e1');
select t_eq('משתמש לקוח אינו רואה תלושים', (select count(*)::int from payslips), 0);
select t_expect_fail('ואינו פותח את המסך', $$select payslips_board()$$);

-- ===== 9. החודש הבא: הצימוד נזכר ===========================================

\echo '--- 9. החודש הבא ---'
select t68_as('b1');
select payslip_batch_create('תלושים 06-2031.pdf', 1, '2031-06-01') as batch2 \gset
reset role;
set role service_role;
-- שם אחר באותו מספר עובד: ההצעה באה מהצימוד, לא מהשם
select payslip_store_reading(:'batch2', 1, '{
  "kind":"payslip","employee_name":"שמעון א.","employee_no":"17","period":"2031-06-01",
  "amounts":{"gross_pay":12500}}'::jsonb, 'test');
reset role;
set role authenticated;
select t68_as('b1');
select t_expect_ok('קיבוץ הקובץ השני', format($$select payslip_apply_reading('%s')$$, :'batch2'));
select t_eq('מספר העובד 17 מציע את שמעון',
  (select r ->> 'suggested_profile_id' from jsonb_array_elements(payslips_board(:'batch2') -> 'slips') r),
  '20000000-0000-0000-0000-0000000068d1');
select t_eq('ממתינים לשיוך — רק התלוש החדש ועמוד ה"אחר"',
  (select count(*)::int from jsonb_array_elements(payslips_board(null, null, true) -> 'slips') r
    where r ->> 'batch_id' in (:'batch1', :'batch2')), 2);

select t_eq('סקירת הקבצים: שני קבצים, ובראשון שני תלושים משויכים מתוך שלושה',
  (select string_agg((b ->> 'assigned') || '/' || (b ->> 'slips'), ',' order by b ->> 'created_at')
     from jsonb_array_elements(payslip_batches_overview()) b
    where b ->> 'id' in (:'batch1', :'batch2')), '2/3,0/1');

-- ===== 10. הסרה ============================================================

\echo '--- 10. הסרה ---'
select t_expect_ok('הסרת עמוד שאינו תלוש', format($$select payslip_remove('%s')$$, :'slip4'));
select t_eq('ירד מהקובץ', t68_slips(:'batch1'), '1-2,3-3');

select t_expect_ok('הסרת הקובץ כולו', format($$select payslip_batch_remove('%s')$$, :'batch1'));
select t_eq('המנהלת אינה רואה אותו עוד', t68_slips(:'batch1'), '-');
select t_rows('אבל מוחקת את העמודים שלו מ-Storage',
  format($$delete from storage.objects where bucket_id = 'payslips' and name like '%s/%%'$$, :'batch1'), 4);
select t_eq('ולא נשאר מהם דבר', t68_files(:'batch1'), '-');

select t68_as('c1');
select t_eq('רואה העלות אינו פותח עמודים של קובץ שהוסר',
  (select app.may_touch_payslip_file(:'batch1' || '/1.pdf', false)), false);
select t_eq('ואינו כותב לדלי בכלל',
  (select app.may_touch_payslip_file(:'batch2' || '/1.pdf', true)), false);

select t68_as('d1');
select t_eq('שמעון אינו רואה עוד את התלוש מהקובץ שהוסר', t68_slips(:'batch1'), '-');

reset role;
