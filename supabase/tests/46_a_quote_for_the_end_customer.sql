\pset tuples_only on
\pset format unaligned

-- ===========================================================================
-- 46: הצעת מחיר ללקוח הקצה (0170).
--
-- שלוש שאלות: מי רשאי להפיק ולראות, מה קורה למסמך אחרי שהוא הופק, ומתי
-- בדיוק נרשמת השורה ביומן. החבילה מקימה לקוח, אירוע, ארבעה קהלים —
-- משרד, עובד שטח, עובד קבלן ולקוח — ומפיקה שתי גרסאות של אותה הצעה.
-- החלון הוא current_date + 630.
-- ===========================================================================

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000046a1', 'c46-office@vl.test'),
  ('00000000-0000-0000-0000-0000000046a2', 'c46-worker@vl.test'),
  ('00000000-0000-0000-0000-0000000046a3', 'c46-ctr@vl.test'),
  ('00000000-0000-0000-0000-0000000046a4', 'c46-cust@vl.test'),
  ('00000000-0000-0000-0000-0000000046a5', 'c46-admin@vl.test');

insert into customers (id, name) values
  ('10000000-0000-0000-0000-00000000046a', 'לקוח 46');
insert into contractors (id, name) values
  ('c0000000-0000-0000-0000-00000000046a', 'קבלן 46');

insert into profiles (id, user_id, user_kind, is_admin, full_name) values
  ('20000000-0000-0000-0000-0000000046a1', '00000000-0000-0000-0000-0000000046a1', 'staff', false, 'רכז 46'),
  ('20000000-0000-0000-0000-0000000046a2', '00000000-0000-0000-0000-0000000046a2', 'staff', false, 'עובד שטח 46'),
  ('20000000-0000-0000-0000-0000000046a5', '00000000-0000-0000-0000-0000000046a5', 'staff', true,  'מנהל 46');
insert into profiles (id, user_id, user_kind, is_admin, full_name, contractor_id) values
  ('20000000-0000-0000-0000-0000000046a3', '00000000-0000-0000-0000-0000000046a3', 'contractor_user', false,
   'עובד קבלן 46', 'c0000000-0000-0000-0000-00000000046a');
insert into profiles (id, user_id, user_kind, is_admin, full_name, customer_id) values
  ('20000000-0000-0000-0000-0000000046a4', '00000000-0000-0000-0000-0000000046a4', 'customer_user', false, 'לקוח 46',
   '10000000-0000-0000-0000-00000000046a');

-- הרכז מקבל events.edit, וממנו נגזרים שני מפתחות ההצעה בהיסק. זו כל
-- הנקודה של `implied_by`: מי שעורך אירוע מפיק לו הצעה בלי שורה נוספת.
insert into user_permission_grants (profile_id, permission_key, allowed) values
  ('20000000-0000-0000-0000-0000000046a1', 'events.view', true),
  ('20000000-0000-0000-0000-0000000046a1', 'events.edit', true),
  ('20000000-0000-0000-0000-0000000046a1', 'events.create', true),
  ('20000000-0000-0000-0000-0000000046a1', 'pricing.view', true);

-- עובד השטח נושא את תפקיד "עובד" — הוא זה שנושא את שורות הדחייה של 0170.
insert into profile_roles (profile_id, role_id)
select '20000000-0000-0000-0000-0000000046a2', id from permission_roles where key = 'worker';

insert into events (id, customer_id, event_number, event_date, end_client_name, location_text, status_id)
values ('30000000-0000-0000-0000-00000000046a', '10000000-0000-0000-0000-00000000046a',
        'EV-46', current_date + 630, 'אולם הדס', 'רחוב הברזל 3, תל אביב',
        (select id from statuses where entity = 'event' and code = 'pending' and deleted_at is null));

insert into event_contacts (event_id, contact_name, contact_phone)
values ('30000000-0000-0000-0000-00000000046a', 'רונן', '050-1234567');

\echo '--- 1. הדגל פר-לקוח: כבוי אלא אם הודלק ---'
select t_eq('לקוח חדש נולד בלי הצעת מחיר',
  (select quote_enabled from customers where id = '10000000-0000-0000-0000-00000000046a'), false);
update customers set quote_enabled = true where id = '10000000-0000-0000-0000-00000000046a';
select t_eq('וההדלקה היא שורה במסד ולא שורת קוד',
  (select quote_enabled from customers where id = '10000000-0000-0000-0000-00000000046a'), true);
select t_eq('פרטי החברה נזרעו עם ח.פ',
  (select value ->> 'tax_id' from app_settings where key = 'company.details'), '516766748');
select t_eq('ואחוז המע״מ יושב לצדם',
  (select (value ->> 'vat_pct')::numeric from app_settings where key = 'company.details'), 18::numeric);

\echo '--- 2. תנאי תשלום הם שדה של הלקוח, לא של המערכת (0171) ---'
-- ‏0170 הוסיפה שדה מערכת בשם הזה, ו-0171 הסירה אותו: לכל לקוח יש שדה
-- מותאם משלו, והמסמך קורא ממנו. שלוש הבדיקות כאן הן שהנסיגה שלמה.
select t_eq('אין עמודה `payment_terms` על אירוע',
  (select count(*)::int from information_schema.columns
    where table_schema = 'public' and table_name = 'events' and column_name = 'payment_terms'), 0);
select t_eq('וגם לא בתצוגה המאובטחת',
  (select count(*)::int from information_schema.columns
    where table_schema = 'public' and table_name = 'events_secure' and column_name = 'payment_terms'), 0);
select t_eq('ואין שדה מערכת כזה בקטלוג הטפסים',
  (select count(*)::int from form_fields where field_key = 'payment_terms'), 0);
select t_eq('ולא במרשם השדות',
  (select count(*)::int from field_registry where entity = 'event' and field_key = 'payment_terms'), 0);

-- והצילום על ההצעה נשאר: הוא מה שהודפס, ואינו מצביע לשום מקום.
select t_eq('העמודה על ההצעה כן נשארה',
  (select count(*)::int from information_schema.columns
    where table_schema = 'public' and table_name = 'event_quotes' and column_name = 'payment_terms'), 1);

-- שדה מותאם של לקוח, בדיוק כמו זה שקיסר מחזיקה בייצור.
insert into form_fields (field_key, label_he, customer_id, field_type, options, sort_order)
values ('custom_terms046a', 'תנאי תשלום', '10000000-0000-0000-0000-00000000046a',
        'select', '["תאריך הארוע","שוטף + 30"]'::jsonb, 1000);

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000046a1', false);
select t_eq('הערך נשמר בשדה המותאם של הלקוח',
  (select custom_fields ->> 'custom_terms046a'
     from t_updated_event('30000000-0000-0000-0000-00000000046a',
       '{"custom_terms046a":"שוטף + 30"}'::jsonb)), 'שוטף + 30');
reset role;
select set_config('request.jwt.claim.sub', '', false);

select t_eq('והיומן רשם אותו בשם שהלקוח נתן לשדה',
  (select count(*)::int from event_activity
    where event_id = '30000000-0000-0000-0000-00000000046a'
      and kind = 'changed' and field_key = 'custom_terms046a'
      and field_label = 'תנאי תשלום' and new_value = 'שוטף + 30'), 1);

\echo '--- 3. הרשאות: מי מפיק ומי אפילו לא רואה ---'
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000046a1', false);
select t_eq('הרכז רואה הצעות מחיר',  app.has('events.quote_view'), true);
select t_eq('והרכז מפיק ושולח',      app.has('events.quote_send'), true);
select t_eq('והשער על הדלי נפתח לו', app.may_touch_event_quote(
  '30000000-0000-0000-0000-00000000046a/aa.pdf', true), true);
select t_eq('נתיב שאינו מזהה אירוע אינו נפתח לאיש', app.may_touch_event_quote('junk.pdf', false), false);
select t_eq('ואירוע שאינו קיים אינו פותח כלום', app.may_touch_event_quote(
  '30000000-0000-0000-0000-0000000ffff/aa.pdf', false), false);
reset role;
select set_config('request.jwt.claim.sub', '', false);

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000046a2', false);
select t_eq('עובד השטח אינו רואה הצעות',  app.has('events.quote_view'), false);
select t_eq('ואינו מפיק',                  app.has('events.quote_send'), false);
select t_eq('והדלי סגור בפניו',            app.may_touch_event_quote(
  '30000000-0000-0000-0000-00000000046a/aa.pdf', false), false);
reset role;
select set_config('request.jwt.claim.sub', '', false);

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000046a3', false);
select t_eq('עובד הקבלן אינו צד להצעה', app.has('events.quote_view'), false);
select t_eq('והדלי סגור גם בפניו',       app.may_touch_event_quote(
  '30000000-0000-0000-0000-00000000046a/aa.pdf', false), false);
reset role;
select set_config('request.jwt.claim.sub', '', false);

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000046a4', false);
select t_eq('הלקוח אינו מפיק בשם וייפר', app.has('events.quote_send'), false);
reset role;
select set_config('request.jwt.claim.sub', '', false);

\echo '--- 4. הלוגו: קריאה לכולם, כתיבה למי שמנהל הגדרות ---'
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000046a2', false);
select t_eq('עובד השטח קורא את הלוגו',    app.may_touch_company_asset(false), true);
select t_eq('ואינו מחליף אותו',            app.may_touch_company_asset(true),  false);
reset role;
select set_config('request.jwt.claim.sub', '', false);

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000046a5', false);
select t_eq('מנהל המערכת מחליף את הלוגו', app.may_touch_company_asset(true), true);
reset role;
select set_config('request.jwt.claim.sub', '', false);

\echo '--- 5. הפקה: המספור בשרת, מספר המסמך קבוע ---'
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000046a1', false);
select t_expect_ok('הרכז מפיק הצעה', $$
  insert into event_quotes (event_id, document_number, storage_path, file_name,
    lines, subtotal, vat_pct, vat_amount, total, payment_terms)
  values ('30000000-0000-0000-0000-00000000046a', 'EV-46',
          '30000000-0000-0000-0000-00000000046a/q1.pdf', 'הצעת מחיר EV-46.pdf',
          '[{"kind":"task","label":"הקמה","when_text":"01/01/2027 08:00","amount":1000}]'::jsonb,
          1000, 18, 180, 1180, 'שוטף + 30')$$);
select t_expect_ok('ומפיק גרסה שנייה של אותו מסמך', $$
  insert into event_quotes (event_id, document_number, storage_path, file_name,
    lines, subtotal, vat_pct, vat_amount, total)
  values ('30000000-0000-0000-0000-00000000046a', 'EV-46',
          '30000000-0000-0000-0000-00000000046a/q2.pdf', 'הצעת מחיר EV-46.pdf',
          '[]'::jsonb, 2000, 18, 360, 2360)$$);
reset role;
select set_config('request.jwt.claim.sub', '', false);

select t_eq('המספור נקבע בשרת ורץ 1,2',
  (select array_agg(version order by version)::text from event_quotes
    where event_id = '30000000-0000-0000-0000-00000000046a'), '{1,2}');
select t_eq('ומספר המסמך זהה בשתיהן',
  (select count(distinct document_number)::int from event_quotes
    where event_id = '30000000-0000-0000-0000-00000000046a'), 1);
select t_eq('והמפיק נחתם מהשרת',
  (select distinct issuer_name from event_quotes
    where event_id = '30000000-0000-0000-0000-00000000046a'), 'רכז 46');

\echo '--- 6. היומן מדווח על שליחה, לא על הפקה ---'
select t_eq('הפקה בלבד אינה שורה ביומן',
  (select count(*)::int from event_activity
    where event_id = '30000000-0000-0000-0000-00000000046a' and kind = 'quote_sent'), 0);

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000046a1', false);
select t_rows('סימון שנשלחה נכנס', $$
  update event_quotes set sent_at = now()
   where event_id = '30000000-0000-0000-0000-00000000046a' and version = 1$$, 1);
reset role;
select set_config('request.jwt.claim.sub', '', false);

select t_eq('ואז נכתבת שורה אחת ביומן',
  (select count(*)::int from event_activity
    where event_id = '30000000-0000-0000-0000-00000000046a' and kind = 'quote_sent'), 1);
select t_eq('ובה מספר המסמך והסכום',
  (select note from event_activity
    where event_id = '30000000-0000-0000-0000-00000000046a' and kind = 'quote_sent'),
  'נשלחה הצעת מחיר מס׳ EV-46 · סה״כ 1,180.00 ₪');

\echo '--- 7. מסמך שיצא אינו משתנה ---'
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000046a1', false);
select t_expect_fail('אי אפשר לשנות את הסכום של הצעה שהופקה', $$
  update event_quotes set total = 1
   where event_id = '30000000-0000-0000-0000-00000000046a' and version = 2$$);
select t_expect_fail('אי אפשר להחליף את הקובץ מתחת למספר', $$
  update event_quotes set storage_path = 'x/y.pdf'
   where event_id = '30000000-0000-0000-0000-00000000046a' and version = 2$$);
select t_expect_fail('ואי אפשר לשלוח פעמיים את אותה גרסה', $$
  update event_quotes set sent_at = now() + interval '1 hour'
   where event_id = '30000000-0000-0000-0000-00000000046a' and version = 1$$);
reset role;
select set_config('request.jwt.claim.sub', '', false);

select t_eq('ולכן עדיין שורת יומן אחת',
  (select count(*)::int from event_activity
    where event_id = '30000000-0000-0000-0000-00000000046a' and kind = 'quote_sent'), 1);

\echo '--- 8. הקריאה: מי מוצא את השורות ---'
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000046a1', false);
select t_eq('הרכז רואה את שתי ההצעות',
  (select count(*)::int from event_quotes
    where event_id = '30000000-0000-0000-0000-00000000046a'), 2);
reset role;
select set_config('request.jwt.claim.sub', '', false);

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000046a2', false);
select t_eq('עובד השטח מקבל רשימה ריקה',
  (select count(*)::int from event_quotes
    where event_id = '30000000-0000-0000-0000-00000000046a'), 0);
select t_rows('ואינו מפיק בעצמו', $$
  insert into event_quotes (event_id, document_number, storage_path, file_name,
    subtotal, vat_pct, vat_amount, total)
  values ('30000000-0000-0000-0000-00000000046a', 'EV-46', 'x/z.pdf', 'z.pdf', 1, 18, 0, 1)$$, 0);
reset role;
select set_config('request.jwt.claim.sub', '', false);

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000046a4', false);
select t_eq('והלקוח שבמערכת אינו רואה את מה שנשלח ללקוח שלו',
  (select count(*)::int from event_quotes
    where event_id = '30000000-0000-0000-0000-00000000046a'), 0);
reset role;
select set_config('request.jwt.claim.sub', '', false);
