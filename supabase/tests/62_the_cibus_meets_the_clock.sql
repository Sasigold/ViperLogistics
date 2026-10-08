\pset tuples_only on
\pset format unaligned

-- ===========================================================================
-- ‏62: סיבוס מול השעון (0210).
--
-- החבילה מקימה ארבע דמויות משלה, והמשמרות והמשיכות שלהן יושבות ב-
-- `current_date + 1040`, מעבר לכל טווח אחר. היא רצה אחרונה כי היא משאירה
-- אחריה רשומות נוכחות ומשיכות שאינן מנוקות.
--
--   62a1 "דני כהן"   — בסיבוס "כהן" + "דני": ניחוש לפי שם, בסדר ההפוך.
--   62a2 "יוסי לוי"  — בסיבוס "יוסף לוי": אין ניחוש, צימוד ביד.
--   62a3 מנהל נוכחות בלי סיבוס — נחסם.
--   62a4 כספים (`attendance.view_pay`) — מקבל את הסיבוס בירושה, ומייבא.
-- ===========================================================================

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000062a1', 'c62-dani@vl.test'),
  ('00000000-0000-0000-0000-0000000062a2', 'c62-yossi@vl.test'),
  ('00000000-0000-0000-0000-0000000062a3', 'c62-manager@vl.test'),
  ('00000000-0000-0000-0000-0000000062a4', 'c62-finance@vl.test');

insert into profiles (id, user_id, user_kind, is_admin, full_name) values
  ('20000000-0000-0000-0000-0000000062a1', '00000000-0000-0000-0000-0000000062a1', 'staff', false, 'דני  כהן'),
  ('20000000-0000-0000-0000-0000000062a2', '00000000-0000-0000-0000-0000000062a2', 'staff', false, 'יוסי לוי'),
  ('20000000-0000-0000-0000-0000000062a3', '00000000-0000-0000-0000-0000000062a3', 'staff', false, 'מנהל 62'),
  ('20000000-0000-0000-0000-0000000062a4', '00000000-0000-0000-0000-0000000062a4', 'staff', false, 'כספים 62'),
  -- שני "משה זהבי": אין ניחוש כשהשם אינו יחיד
  ('20000000-0000-0000-0000-0000000062b1', null, 'staff', false, 'משה זהבי'),
  ('20000000-0000-0000-0000-0000000062b2', null, 'staff', false, 'משה זהבי');

-- ‏0211: משתמשת לקוח ששמה יחיד במערכת — ובכל זאת אינה עובדת, ולא תנוחש
insert into profiles (id, user_id, user_kind, is_admin, full_name, customer_id) values
  ('20000000-0000-0000-0000-0000000062c1', null, 'customer_user', false, 'רונית ברק',
   '10000000-0000-0000-0000-000000000001');

insert into user_permission_grants (profile_id, permission_key, allowed) values
  ('20000000-0000-0000-0000-0000000062a3', 'attendance.view_all', true),
  ('20000000-0000-0000-0000-0000000062a4', 'attendance.view_all', true),
  ('20000000-0000-0000-0000-0000000062a4', 'attendance.view_pay', true)
on conflict do nothing;

create temp table t62 as select current_date + 1040 as d;
grant select on t62 to authenticated;

-- דני: יום (מאושר), לילה שחוצה חצות (ממתין), ומשמרת שנדחתה. יוסי: יום.
insert into attendance_entries (id, profile_id, work_date, seq, clock_in_at, clock_out_at, source, status)
select v.id::uuid, v.pid::uuid, d + v.day_in, 1,
       (d + v.day_in + v.t_in) at time zone 'Asia/Jerusalem',
       (d + v.day_out + v.t_out) at time zone 'Asia/Jerusalem', 'manual', v.status
  from t62,
       (values
         ('50000000-0000-0000-0000-0000000062e1', '20000000-0000-0000-0000-0000000062a1',
          0, time '08:00', 0, time '16:00', 'approved'),
         ('50000000-0000-0000-0000-0000000062e2', '20000000-0000-0000-0000-0000000062a1',
          1, time '20:00', 2, time '02:00', 'pending'),
         ('50000000-0000-0000-0000-0000000062e3', '20000000-0000-0000-0000-0000000062a1',
          3, time '10:00', 3, time '12:00', 'rejected'),
         ('50000000-0000-0000-0000-0000000062e4', '20000000-0000-0000-0000-0000000062a2',
          0, time '08:00', 0, time '16:00', 'approved')
       ) v(id, pid, day_in, t_in, day_out, t_out, status);

-- הקובץ, כפי שהדפדפן שולח אותו: שעה מקומית בלי אזור זמן
create temp table t62_rows as
select jsonb_agg(jsonb_build_object(
         'txn_no', v.txn, 'occurred_local', to_char(d + v.day + v.t, 'YYYY-MM-DD"T"HH24:MI'),
         'user_no', v.user_no, 'first_name', v.first, 'last_name', v.last,
         'employee_name', v.first || ' ' || v.last,
         'merchant', v.merchant, 'deal_type', 'ישיבה', 'amount', v.amount,
         'company_part', v.amount, 'employee_part', 0)) as rows
  from t62,
       (values
         -- דני: בתוך המשמרת
         (62001, 0, time '12:00', 9001, 'דני', 'כהן', 'מסעדה א', 30.0),
         -- 45 דקות לפני הכניסה
         (62002, 0, time '07:15', 9001, 'דני', 'כהן', 'מאפייה', 20.5),
         -- שעה וחצי אחרי היציאה — אין נוכחות
         (62003, 0, time '17:30', 9001, 'דני', 'כהן', 'פיצה', 29.9),
         -- 40 דקות אחרי משמרת לילה שנגמרה ב-02:00 של יום +2
         (62004, 2, time '02:40', 9001, 'דני', 'כהן', 'תחנת דלק', 28.7),
         -- בתוך משמרת שנדחתה — אין נוכחות
         (62005, 3, time '11:00', 9001, 'דני', 'כהן', 'פלאפל', 25.0),
         -- יום בלי משמרת
         (62006, 5, time '12:00', 9001, 'דני', 'כהן', 'סושי', 30.0),
         -- יוסי, בשם אחר בסיבוס
         (62007, 0, time '12:00', 9002, 'יוסף', 'לוי', 'שווארמה', 30.0),
         -- "משה זהבי" — שני מועמדים
         (62008, 0, time '12:00', 9003, 'משה', 'זהבי', 'קפה', 15.0),
         -- "רונית ברק" — יש כזו, אבל היא משתמשת לקוח
         (62009, 0, time '12:00', 9004, 'רונית', 'ברק', 'מאפה', 10.0)
       ) v(txn, day, t, user_no, first, last, merchant, amount);
grant select on t62_rows to authenticated;

set role authenticated;


\echo '--- 1. הרשאות ---'

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000062a3', false);
select t_expect_fail('מנהל נוכחות בלי סיבוס אינו מייבא',
  'select cibus_import((select rows from t62_rows))');
select t_expect_fail('ואינו רואה את הדוח',
  'select cibus_report(current_date, current_date + 1)');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000062a1', false);
select t_expect_fail('עובד אינו מייבא',
  'select cibus_import((select rows from t62_rows))');

-- ‏01_seed מחזיר ל-authenticated הרשאות על כל הטבלאות, ולכן כאן זה RLS בלי
-- פוליסות שעוצר: אפס שורות. בפרודקשן ה-revoke של 0210 עוצר עוד קודם.
select t_eq('הטבלה עצמה סגורה',
  (select count(*) from cibus_transactions), 0::bigint);


\echo '--- 2. ייבוא ---'

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000062a4', false);

create temp table t62_imp as select cibus_import((select rows from t62_rows)) as r;

select t_eq('כספים מייבא: תשע משיכות חדשות',
  ((select r from t62_imp) ->> 'inserted')::int, 9);
select t_eq('יוסף לוי, משה זהבי ורונית ברק לא צומדו',
  (select string_agg(u ->> 'employee_name', ',' order by u ->> 'employee_name')
     from jsonb_array_elements((select r from t62_imp) -> 'unlinked') u),
  'יוסף לוי,משה זהבי,רונית ברק');

create temp table t62_imp2 as select cibus_import((select rows from t62_rows)) as r;
select t_eq('ייבוא חוזר מעדכן ולא מכפיל',
  ((select r from t62_imp2) ->> 'inserted')::int || '/' || ((select r from t62_imp2) ->> 'updated'), '0/9');

select t_expect_fail('שורה בלי סכום נדחית',
  $$select cibus_import('[{"txn_no": 62099, "occurred_local": "2026-01-01T10:00", "employee_name": "x"}]')$$);
select t_expect_fail('ושורה בלי תאריך תקין',
  $$select cibus_import('[{"txn_no": 62099, "occurred_local": "לא תאריך", "employee_name": "x", "amount": 5}]')$$);


\echo '--- 3. ההצלבה ---'

create temp table t62_rep as
select cibus_report((select d from t62) - 5, (select d from t62) + 10) as r;

create temp view t62_tx as
select (t ->> 'txn_no')::bigint as txn, t ->> 'entry_id' as entry_id, t ->> 'profile_id' as pid
  from jsonb_array_elements((select r from t62_rep) -> 'transactions') t;

select t_eq('בתוך המשמרת — שייכת לה',
  (select entry_id from t62_tx where txn = 62001), '50000000-0000-0000-0000-0000000062e1');
select t_eq('45 דקות לפני הכניסה — שייכת לה',
  (select entry_id from t62_tx where txn = 62002), '50000000-0000-0000-0000-0000000062e1');
select t_eq('שעה וחצי אחרי היציאה — בלי נוכחות',
  (select entry_id from t62_tx where txn = 62003), null::text);
select t_eq('40 דקות אחרי משמרת לילה (ממתינה) — שייכת לה',
  (select entry_id from t62_tx where txn = 62004), '50000000-0000-0000-0000-0000000062e2');
select t_eq('בתוך משמרת שנדחתה — בלי נוכחות',
  (select entry_id from t62_tx where txn = 62005), null::text);
select t_eq('יום בלי משמרת — בלי נוכחות',
  (select entry_id from t62_tx where txn = 62006), null::text);

select t_eq('דני: שלוש עם נוכחות, שלוש בלי',
  (select (e ->> 'matched_count') || '/' || (e ->> 'unmatched_count')
     from jsonb_array_elements((select r from t62_rep) -> 'employees') e
    where e ->> 'profile_id' = '20000000-0000-0000-0000-0000000062a1'), '3/3');
select t_eq('והסכום בלי נוכחות הוא 29.9 + 25 + 30',
  (select (e ->> 'unmatched_amount')::numeric
     from jsonb_array_elements((select r from t62_rep) -> 'employees') e
    where e ->> 'profile_id' = '20000000-0000-0000-0000-0000000062a1'), 84.9::numeric);
select t_eq('שלושה עובדי סיבוס לא צומדו',
  jsonb_array_length((select r from t62_rep) -> 'unlinked'), 3);
select t_eq('הסיכום הכללי: תשע משיכות',
  ((select r from t62_rep) #>> '{totals,count}')::int, 9);
select t_eq('בסך 219.1',
  ((select r from t62_rep) #>> '{totals,amount}')::numeric, 219.1::numeric);
-- ‏0211: מי שלא זוהה אינו "בלי נוכחות" — הוא נספר לבד
select t_eq('"בלי נוכחות" סופר רק את דני',
  ((select r from t62_rep) #>> '{totals,unmatched_count}')::int, 3);
select t_eq('ובסכום שלו בלבד',
  ((select r from t62_rep) #>> '{totals,unmatched_amount}')::numeric, 84.9::numeric);
select t_eq('ושלושת שלא זוהו נספרים בנפרד',
  ((select r from t62_rep) #>> '{totals,unlinked_count}')::int, 3);


\echo '--- 4. גבול החודש ---'

select t_eq('משיכת 02:40 נספרת בחודש של משמרת הלילה',
  (select count(*) from jsonb_array_elements(
     cibus_report((select d from t62) - 5, (select d from t62) + 1) -> 'transactions') t
    where (t ->> 'txn_no')::bigint = 62004), 1::bigint);
select t_eq('ולא בחודש של התאריך שלה',
  (select count(*) from jsonb_array_elements(
     cibus_report((select d from t62) + 2, (select d from t62) + 10) -> 'transactions') t
    where (t ->> 'txn_no')::bigint = 62004), 0::bigint);


\echo '--- 5. צימוד ידני ---'

select t_expect_ok('צימוד יוסף לוי ליוסי לוי',
  $$select cibus_link('u:9002', '20000000-0000-0000-0000-0000000062a2')$$);
select t_eq('ומיד המשיכה שלו נמצאת במשמרת שלו',
  (select t ->> 'entry_id' from jsonb_array_elements(
     cibus_report((select d from t62) - 5, (select d from t62) + 10) -> 'transactions') t
    where (t ->> 'txn_no')::bigint = 62007), '50000000-0000-0000-0000-0000000062e4');

create temp table t62_imp3 as select cibus_import((select rows from t62_rows)) as r;
select t_eq('הצימוד נזכר בייבוא הבא',
  (select count(*) from jsonb_array_elements((select r from t62_imp3) -> 'unlinked') u
    where u ->> 'link_key' = 'u:9002'), 0::bigint);

select t_expect_ok('ביטול צימוד',
  $$select cibus_link('u:9002', null)$$);
select t_eq('מחזיר את המשיכה ל"לא צומד"',
  (select t ->> 'profile_id' from jsonb_array_elements(
     cibus_report((select d from t62) - 5, (select d from t62) + 10) -> 'transactions') t
    where (t ->> 'txn_no')::bigint = 62007), null::text);

select t_expect_fail('אין צימוד למשתמש לקוח',
  $$select cibus_link('u:9004', '20000000-0000-0000-0000-0000000062c1')$$);

select t_expect_fail('צימוד של עובד סיבוס שאינו קיים',
  $$select cibus_link('u:123456789', '20000000-0000-0000-0000-0000000062a2')$$);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000062a3', false);
select t_expect_fail('מי שאין לו סיבוס אינו מצמד',
  $$select cibus_link('u:9002', '20000000-0000-0000-0000-0000000062a2')$$);

reset role;
select set_config('request.jwt.claim.sub', '', false);
