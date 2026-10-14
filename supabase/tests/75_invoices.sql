\pset tuples_only on
\pset format unaligned

-- ===========================================================================
-- ‏75: חשבוניות (0233) — מנהלי מערכת בלבד, יצירה ושמירה, קריאה שאינה דורסת
-- אישור, תיקייה לחודש וסיכום מע"מ, התאמת החברה, וחיבור Gmail שהטוקן שלו סגור.
--
-- החודשים רחוקים (2031) כדי לא לפגוש נתונים אחרים; הסוויטה מסירה אחריה את מה
-- שיצרה (soft delete).
-- ===========================================================================

-- הסיד של הבדיקות מחזיר הרשאת הרצה לכל פונקציה; מה ש-0233 סגר נסגר כאן שוב.
revoke execute on function app.invoice_company_for(text, text) from anon, authenticated, public;
revoke execute on function app.invoice_json(invoices) from anon, authenticated, public;
revoke execute on function app.invoice_gmail_kick() from anon, authenticated, public;
revoke execute on function invoice_store_reading(uuid, jsonb, text) from anon, authenticated, public;
revoke execute on function invoice_read_failed(uuid, text) from anon, authenticated, public;
revoke execute on function invoice_company_match(text, text) from anon, authenticated, public;
revoke execute on function invoice_gmail_import(uuid, uuid, jsonb, text, text, jsonb, text) from anon, authenticated, public;
revoke execute on function invoice_gmail_connect(uuid, text, text) from anon, authenticated, public;
revoke execute on function invoice_gmail_accounts_due(uuid) from anon, authenticated, public;
revoke execute on function invoice_gmail_seen(uuid, text[]) from anon, authenticated, public;
revoke execute on function invoice_gmail_mark(uuid, text, int, int, text) from anon, authenticated, public;
revoke execute on function invoice_gmail_run_done(uuid, timestamptz, text) from anon, authenticated, public;
-- (וגם הרשאות הטבלאות: הסיד פותח את כולן ל-authenticated)
revoke all on invoice_gmail_accounts, invoice_gmail_messages from anon, authenticated, public;
revoke insert, update, delete, truncate on invoice_companies, invoices, invoice_lines from authenticated;

create temp table i75 (k text primary key, id uuid);
grant all on i75 to authenticated;

-- ===== 1. מי נכנס ==========================================================

\echo '--- מי נכנס ---'
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000f1', false);
select t_eq('איש צוות אינו מחזיק את המפתח', app.has('invoices.manage'), false);
select t_expect_fail('ואינו פותח את התיקייה', $$ select invoices_board(date '2031-03-01') $$);
select t_expect_fail('ואינו יוצר חשבונית', $$
  select invoice_create('x.pdf', 'upload', repeat('a', 64)) $$);
select t_expect_fail('ואינו כותב לטבלה ישירות', $$
  insert into invoices (source, file_name, file_path, file_sha256, period)
  values ('upload', 'x', 'x', repeat('a', 64), date '2031-03-01') $$);
select t_expect_fail('ואינו רואה את חשבונות Gmail', $$ select invoice_gmail_status() $$);
select t_expect_fail('ואינו מחבר Gmail בעצמו', $$
  select invoice_gmail_connect('20000000-0000-0000-0000-0000000000f1', 'a@b.c', 'tok') $$);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false);
select t_eq('מנהל מערכת מחזיק את המפתח', app.has('invoices.manage'), true);
select t_expect_fail('גם מנהל אינו קורא את טבלת הטוקנים', $$ select * from invoice_gmail_accounts $$);
select t_expect_fail('ואינו כותב קריאה בעצמו', $$
  select invoice_store_reading(gen_random_uuid(), '{}'::jsonb, 'x') $$);
select t_expect_fail('והפונקציות הפנימיות סגורות', $$ select app.invoice_company_for('x', null) $$);

-- ===== 2. חברות ============================================================

\echo '--- חברות ---'
insert into i75 values ('viper', invoice_company_save(null, jsonb_build_object(
  'name', 'וייפר מיקור חוץ לעסקים', 'tax_id', '51-555123-4', 'aliases', jsonb_build_array('Viper Outsourcing'))));
select t_eq('ח.פ. נשמר בספרות בלבד',
  (select tax_id from invoice_companies where id = (select id from i75 where k = 'viper')), '515551234');
select t_expect_fail('ח.פ. קצר מדי נדחה', $$
  select invoice_company_save(null, jsonb_build_object('name', 'x', 'tax_id', '12')) $$);
reset role;
select t_eq('התאמה לפי ח.פ.', invoice_company_match('חברה אחרת', '515551234'),
  (select id from i75 where k = 'viper'));
select t_eq('התאמה לפי שם, גם בתוך שם ארוך',
  invoice_company_match('לכבוד: וייפר מיקור-חוץ לעסקים בע"מ', null), (select id from i75 where k = 'viper'));
select t_eq('התאמה לפי שם נוסף', invoice_company_match('VIPER OUTSOURCING LTD', null),
  (select id from i75 where k = 'viper'));
select t_eq('חברה זרה — אין התאמה', invoice_company_match('משה כהן', '123456789'), null::uuid);

-- ===== 3. העלאה וקריאה =====================================================

\echo '--- העלאה וקריאה ---'
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false);
insert into i75 select 'a', (invoice_create('fuel.pdf', 'upload', repeat('1', 64)) ->> 'id')::uuid;
select t_eq('אותו קובץ פעמיים — מצביע על הראשון',
  (invoice_create('again.pdf', 'camera', repeat('1', 64)) ->> 'duplicate_of')::uuid,
  (select id from i75 where k = 'a'));
select t_eq('השער של הקובץ פתוח למנהל, לחשבונית קיימת',
  app.may_touch_invoice_file((select id from i75 where k = 'a') || '.pdf'), true);
select t_eq('ולא לנתיב אחר', app.may_touch_invoice_file('../x.pdf'), false);
reset role;

select t_eq('קריאה ראשונה מוחלת', invoice_store_reading((select id from i75 where k = 'a'), jsonb_build_object(
  'doc_type', 'tax_invoice', 'vendor_name', 'פז  חברת נפט', 'vendor_tax_id', '520-000-000',
  'invoice_number', 'A-100', 'issue_date', '2031-03-14', 'currency', 'ILS',
  'amount_before_vat', 100, 'vat_amount', 18, 'total_amount', '118.00', 'category', 'fuel',
  'recipient_name', 'וייפר מיקור חוץ לעסקים', 'recipient_tax_id', null,
  'lines', jsonb_build_array(jsonb_build_object('description', 'סולר', 'quantity', 15, 'unit_price', 6.67, 'total', 100),
                             jsonb_build_object('description', '', 'total', 1))), 'm') ->> 'applied', 'true');
select t_eq('השדות נקראו, החודש לפי התאריך, והחברה זוהתה',
  (select vendor_name || '|' || vendor_tax_id || '|' || period || '|' || total_amount || '|'
          || (company_id = (select id from i75 where k = 'viper'))::text
     from invoices where id = (select id from i75 where k = 'a')),
  'פז חברת נפט|520000000|2031-03-01|118.00|true');
select t_eq('שורה בלי תיאור לא נשמרת',
  (select count(*)::int from invoice_lines where invoice_id = (select id from i75 where k = 'a') and deleted_at is null), 1);

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false);
select t_expect_ok('תיקון ביד ואישור', $$
  select invoice_save((select id from i75 where k = 'a'), jsonb_build_object(
    'total_amount', 117.99, 'category', 'vehicle',
    'lines', jsonb_build_array(jsonb_build_object('description', 'סולר', 'total', 99.99),
                               jsonb_build_object('description', 'שמן', 'total', 0)))) $$);
select t_expect_fail('סוג הוצאה לא מוכר נדחה', $$
  select invoice_save((select id from i75 where k = 'a'), '{"category": "x"}'::jsonb) $$);
reset role;
select t_eq('קריאה חוזרת אינה דורסת חשבונית שאושרה',
  invoice_store_reading((select id from i75 where k = 'a'),
    '{"total_amount": 5, "issue_date": "2031-01-01"}'::jsonb, 'm') ->> 'applied', 'false');
select t_eq('התיקון נשאר',
  (select total_amount || '|' || category || '|' || period from invoices where id = (select id from i75 where k = 'a')),
  '117.99|vehicle|2031-03-01');
select t_eq('השורות הוחלפו',
  (select string_agg(description, ',' order by line_no) from invoice_lines
    where invoice_id = (select id from i75 where k = 'a') and deleted_at is null), 'סולר,שמן');

-- חשבונית זיכוי, ומטבע זר
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false);
insert into i75 select 'b', (invoice_create('credit.pdf', 'upload', repeat('2', 64)) ->> 'id')::uuid;
insert into i75 select 'c', (invoice_create('aws.pdf', 'upload', repeat('3', 64)) ->> 'id')::uuid;
select t_expect_ok('זיכוי ביד', $$
  select invoice_save((select id from i75 where k = 'b'), jsonb_build_object('doc_type', 'credit',
    'issue_date', '2031-03-20', 'amount_before_vat', -50, 'vat_amount', -9, 'total_amount', -59)) $$);
select t_expect_ok('מטבע זר', $$
  select invoice_save((select id from i75 where k = 'c'), jsonb_build_object('currency', 'usd',
    'issue_date', '2031-03-02', 'total_amount', 40, 'category', 'software')) $$);
reset role;
select invoice_read_failed((select id from i75 where k = 'c'), 'x');
select t_eq('כישלון קריאה אינו נוגע בחשבונית שאושרה',
  (select read_status from invoices where id = (select id from i75 where k = 'c')), 'pending');

-- ===== 4. התיקייה והסיכום ==================================================

\echo '--- התיקייה ---'
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false);
select t_eq('הסיכום בשקלים: זיכוי מחוסר, מטבע זר בנפרד',
  (select (b -> 'totals' ->> 'count') || '|' || (b -> 'totals' ->> 'before_vat') || '|'
          || (b -> 'totals' ->> 'vat') || '|' || (b -> 'totals' ->> 'total') || '|' || (b -> 'totals' ->> 'foreign')
     from (select invoices_board(date '2031-03-17') b) s),
  '3|50.00|9.00|58.99|1');
select t_eq('התיקייה של מרץ 2031 ברשימת החודשים',
  (select count(*)::int from jsonb_array_elements(invoices_board(date '2031-03-01') -> 'months') m
    where m ->> 'period' = '2031-03-01' and (m ->> 'count')::int = 3), 1);
select t_eq('הקריאה הגולמית אינה יוצאת למסך',
  (select bool_or(i ? 'raw_reading') from jsonb_array_elements(invoices_board(date '2031-03-01') -> 'invoices') i), false);
select t_expect_ok('העברה לחודש אחר', $$
  select invoice_save((select id from i75 where k = 'b'), '{"period": "2031-04-01"}'::jsonb) $$);
select t_eq('הזיכוי עבר לאפריל',
  (invoices_board(date '2031-04-01') -> 'totals' ->> 'count'), '1');
select t_expect_ok('הסרה', $$ select invoice_remove((select id from i75 where k = 'c')) $$);
select t_eq('מה שהוסר אינו בתיקייה', (invoices_board(date '2031-03-01') -> 'totals' ->> 'count'), '1');
select t_eq('ואותו קובץ אפשר להעלות שוב',
  (invoice_create('aws.pdf', 'upload', repeat('3', 64)) ? 'id'), true);
reset role;

-- ===== 5. Gmail ============================================================

\echo '--- Gmail ---'
select t_expect_fail('רק מנהל מערכת מחבר', $$
  select invoice_gmail_connect('20000000-0000-0000-0000-0000000000f1', 'x@gmail.com', 'tok') $$);
insert into i75 values ('acc', invoice_gmail_connect('20000000-0000-0000-0000-000000000001', 'Owner@Gmail.com', 'secret-tok'));
select t_eq('חיבור חוזר של אותה כתובת מעדכן את אותו חשבון',
  invoice_gmail_connect('20000000-0000-0000-0000-000000000001', 'owner@gmail.com', 'tok-2'),
  (select id from i75 where k = 'acc'));
select t_eq('הסריקה רואה את החשבון ואת הטוקן',
  (select refresh_token from invoice_gmail_accounts_due(null)), 'tok-2');
select invoice_gmail_mark((select id from i75 where k = 'acc'), 'm1', 0, 1, 'no match');
select t_eq('הודעה שנבדקה מסומנת',
  invoice_gmail_seen((select id from i75 where k = 'acc'), array['m1', 'm2']), array['m1']);
insert into i75 select 'g', invoice_gmail_import(gen_random_uuid(), (select id from i75 where k = 'acc'),
  jsonb_build_object('id', 'm2', 'from', 'billing@pango.co.il', 'subject', 'חשבונית', 'date', '2031-03-05T08:00:00Z'),
  'pango.pdf', repeat('4', 64),
  jsonb_build_object('doc_type', 'tax_invoice_receipt', 'vendor_name', 'פנגו', 'issue_date', '2031-03-04',
    'total_amount', 23.6, 'vat_amount', 3.6, 'amount_before_vat', 20, 'recipient_tax_id', '515551234'), 'm');
select t_eq('חשבונית מ-Gmail נשמרה עם המקור והחברה',
  (select source || '|' || gmail_message_id || '|' || (company_id = (select id from i75 where k = 'viper'))::text
     from invoices where id = (select id from i75 where k = 'g')), 'gmail|m2|true');
select t_eq('אותו קובץ שוב מ-Gmail — לא נשמר', invoice_gmail_import(gen_random_uuid(), (select id from i75 where k = 'acc'),
  '{"id": "m3"}'::jsonb, 'pango.pdf', repeat('4', 64), '{}'::jsonb, 'm'), null::uuid);

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false);
select t_eq('המסך רואה את החשבון בלי הטוקן',
  (select (a ->> 'email') || '|' || (a ->> 'connected') || '|' || (a ? 'refresh_token')::text
     from jsonb_array_elements(invoice_gmail_status() -> 'accounts') a), 'owner@gmail.com|true|false');
select t_expect_ok('ניתוק', $$ select invoice_gmail_disconnect((select id from i75 where k = 'acc')) $$);
select t_eq('אחרי ניתוק — אין חשבונות', jsonb_array_length(invoice_gmail_status() -> 'accounts'), 0);
reset role;
select t_eq('והטוקן נמחק', (select refresh_token from invoice_gmail_accounts where id = (select id from i75 where k = 'acc')), null::text);
select t_rows('והסריקה כבר לא רואה אותו', $$ select * from invoice_gmail_accounts_due(null) $$, 0);

-- ===== ניקוי ===============================================================

update invoices set deleted_at = now() where period >= date '2031-01-01' and deleted_at is null;
update invoice_companies set deleted_at = now() where id = (select id from i75 where k = 'viper');
select set_config('request.jwt.claim.sub', '', false);
