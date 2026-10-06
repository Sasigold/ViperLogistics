\pset tuples_only on
\pset format unaligned

-- ===========================================================================
-- ‏60: מסך תשלומי האירועים מסנן לפי לקוח (0208).
--
-- החבילה מקימה שלושה לקוחות (שניים שתשלומי אירועים דלוקים אצלם ואחד שלא),
-- אירוע לכל אחד ושתי דמויות משלה ב-`current_date + 980`, מעבר לכל טווח אחר.
-- היא משאירה אחריה אירועים, הכנסות ותקבולים שאינם מנוקים.
--
-- לקוח א: הובלות 1,000 (100%), שולם 400. לקוח ב: הובלות 3,000, לא שולם דבר.
-- ‏`customer_options` ו-`customers` כוללים גם לקוחות של חבילות קודמות (58
-- משאירה לקוח דלוק), ולכן הבדיקות עליהם הן "מכיל", לא "שווה".
-- ===========================================================================

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000060a1', 'p60-finance@vl.test'),
  ('00000000-0000-0000-0000-0000000060a2', 'p60-coord@vl.test');

insert into customers (id, name, event_payments_enabled) values
  ('10000000-0000-0000-0000-0000000060a0', 'לקוח א 60', true),
  ('10000000-0000-0000-0000-0000000060b0', 'לקוח ב 60', true),
  ('10000000-0000-0000-0000-0000000060c0', 'לקוח סגור 60', false);

insert into profiles (id, user_id, user_kind, is_admin, full_name, customer_id) values
  -- מנהל כספים: תקבולים — צפייה וניהול, ומהם נגזרים תשלומי האירועים
  ('20000000-0000-0000-0000-0000000060a1', '00000000-0000-0000-0000-0000000060a1',
   'staff', false, 'מנהל כספים 60', null),
  -- רכז בלי כסף
  ('20000000-0000-0000-0000-0000000060a2', '00000000-0000-0000-0000-0000000060a2',
   'staff', false, 'רכז 60', null);

insert into user_permission_grants (profile_id, permission_key, allowed) values
  ('20000000-0000-0000-0000-0000000060a1', 'finance.receipts_view', true),
  ('20000000-0000-0000-0000-0000000060a1', 'finance.receipts_manage', true),
  ('20000000-0000-0000-0000-0000000060a2', 'events.view', true),
  ('20000000-0000-0000-0000-0000000060a2', 'finance.receipts_view', false),
  ('20000000-0000-0000-0000-0000000060a2', 'dashboard.financial', false);

create temp table t60 as
select current_date + 980 as d;
grant select on t60 to authenticated;

insert into events (id, customer_id, end_client_name, event_number, event_date, status_id)
select v.id, v.customer, v.name, v.num, (select d from t60),
       (select id from statuses where entity = 'event' and code = 'planned' and deleted_at is null)
from (values
  ('30000000-0000-0000-0000-0000000060e1'::uuid, '10000000-0000-0000-0000-0000000060a0'::uuid, 'אירוע א 60', 'EV-60-A'),
  ('30000000-0000-0000-0000-0000000060e2'::uuid, '10000000-0000-0000-0000-0000000060b0'::uuid, 'אירוע ב 60', 'EV-60-B'),
  ('30000000-0000-0000-0000-0000000060e3'::uuid, '10000000-0000-0000-0000-0000000060c0'::uuid, 'אירוע סגור 60', 'EV-60-C')
) v(id, customer, name, num);

-- המשימות האוטומטיות של 0009 נמחקות: "מגיע" כאן הוא ההכנסות בלבד.
delete from tasks where event_id in ('30000000-0000-0000-0000-0000000060e1',
                                     '30000000-0000-0000-0000-0000000060e2',
                                     '30000000-0000-0000-0000-0000000060e3');

insert into event_income (event_id, category_id, amount, viper_share_pct)
select v.event, (select id from income_categories where name = 'הובלות' limit 1), v.amount, 100
from (values
  ('30000000-0000-0000-0000-0000000060e1'::uuid, 1000),
  ('30000000-0000-0000-0000-0000000060e2'::uuid, 3000),
  ('30000000-0000-0000-0000-0000000060e3'::uuid, 5000)
) v(event, amount);


\echo '--- 1. החתימה ---'

select t_eq('החתימה הישנה (date, date) אינה קיימת עוד — אין קריאה דו-משמעית',
  to_regprocedure('event_payments_dashboard(date, date)') is null, true);
select t_eq('anon אינו רשאי לקרוא את הסיכום',
  has_function_privilege('anon', 'event_payments_dashboard(date, date, uuid)', 'execute'), false);

set role authenticated;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000060a2', false);
select t_eq('רכז בלי מפתח כספי אינו רואה כלום — גם עם לקוח',
  event_payments_dashboard((select d from t60) - 3, (select d from t60) + 3,
                           '10000000-0000-0000-0000-0000000060a0') is null, true);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000060a1', false);
select t_expect_ok('תשלום של 400 על האירוע של לקוח א',
  $$select event_payment_add('30000000-0000-0000-0000-0000000060e1', 400, 'cash')$$);


\echo '--- 2. בלי לקוח — כמו שהיה ---'

select t_eq('שני הלקוחות יחד: מגיע 4,000 · שולם 400 · לא שולם 3,600 · שני אירועים',
  (select (j ->> 'due') || '/' || (j ->> 'paid') || '/' || (j ->> 'unpaid') || '/' || (j ->> 'events')
     from (select event_payments_dashboard((select d from t60) - 3, (select d from t60) + 3) as j) x),
  '4000.00/400.00/3600.00/2');
select t_eq('שני הלקוחות ברשימת השמות לכותרת',
  (select (j -> 'customers') @> '["לקוח א 60", "לקוח ב 60"]'::jsonb
     from (select event_payments_dashboard((select d from t60) - 3, (select d from t60) + 3) as j) x),
  true);


\echo '--- 3. לקוח אחד ---'

select t_eq('לקוח א: מגיע 1,000 · שולם 400 · לא שולם 600 · אירוע אחד פתוח',
  (select (j ->> 'due') || '/' || (j ->> 'paid') || '/' || (j ->> 'unpaid') || '/' || (j ->> 'open_events')
     from (select event_payments_dashboard((select d from t60) - 3, (select d from t60) + 3,
                                           '10000000-0000-0000-0000-0000000060a0') as j) x),
  '1000.00/400.00/600.00/1');
select t_eq('לקוח ב: מגיע 3,000 · שולם 0 · לא שולם 3,000',
  (select (j ->> 'due') || '/' || (j ->> 'paid') || '/' || (j ->> 'unpaid')
     from (select event_payments_dashboard((select d from t60) - 3, (select d from t60) + 3,
                                           '10000000-0000-0000-0000-0000000060b0') as j) x),
  '3000.00/0.00/3000.00');
select t_eq('הפילוח החודשי מסונן גם הוא',
  (select (m ->> 'due')::numeric
     from jsonb_array_elements(event_payments_dashboard((select d from t60) - 3, (select d from t60) + 3,
                                                        '10000000-0000-0000-0000-0000000060b0') -> 'months') m
    where (m ->> 'month')::date = date_trunc('month', (select d from t60))::date),
  3000.00::numeric);
select t_eq('רשימת השמות מצטמצמת ללקוח שנבחר',
  (select j -> 'customers'
     from (select event_payments_dashboard((select d from t60) - 3, (select d from t60) + 3,
                                           '10000000-0000-0000-0000-0000000060a0') as j) x),
  '["לקוח א 60"]'::jsonb);
select t_eq('לקוח שהמודול סגור לו — אין מה לספור',
  (select (j ->> 'due') || '/' || (j ->> 'events')
     from (select event_payments_dashboard((select d from t60) - 3, (select d from t60) + 3,
                                           '10000000-0000-0000-0000-0000000060c0') as j) x),
  '0.00/0');


\echo '--- 4. רשימת הלקוחות לפילטר ---'

select t_eq('שני הלקוחות הדלוקים מוצעים, עם מזהה וצבע',
  (select (j -> 'customer_options') @> jsonb_build_array(
            jsonb_build_object('id', '10000000-0000-0000-0000-0000000060a0', 'name', 'לקוח א 60'),
            jsonb_build_object('id', '10000000-0000-0000-0000-0000000060b0', 'name', 'לקוח ב 60'))
      and (select bool_and(o ? 'color') from jsonb_array_elements(j -> 'customer_options') o)
     from (select event_payments_dashboard((select d from t60) - 3, (select d from t60) + 3) as j) x),
  true);
select t_eq('הלקוח שהמודול סגור לו אינו מוצע',
  (select (j -> 'customer_options') @> jsonb_build_array(
            jsonb_build_object('id', '10000000-0000-0000-0000-0000000060c0'))
     from (select event_payments_dashboard((select d from t60) - 3, (select d from t60) + 3) as j) x),
  false);
select t_eq('והרשימה המלאה מוצעת גם כשלקוח נבחר — הפילטר לא מתכווץ לבחירה',
  (select (j -> 'customer_options') @> jsonb_build_array(
            jsonb_build_object('id', '10000000-0000-0000-0000-0000000060b0'))
     from (select event_payments_dashboard((select d from t60) - 3, (select d from t60) + 3,
                                           '10000000-0000-0000-0000-0000000060a0') as j) x),
  true);

reset role;
select set_config('request.jwt.claim.sub', '', false);
