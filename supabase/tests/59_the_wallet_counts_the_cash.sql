\pset tuples_only on
\pset format unaligned

-- ===========================================================================
-- ‏59: חיוב ידני על אירוע, וארנק המזומנים (0206).
--
-- החבילה מקימה לקוח, שני אירועים וארבע דמויות משלה ב-`current_date + 950`,
-- מעבר לכל טווח אחר. הארנק הוא סכום על כל התקבולים במזומן במסד — גם של
-- חבילות קודמות (58) — ולכן הבדיקות על היתרה הן על ההפרש, לא על מספר מוחלט.
-- היא משאירה אחריה אירועים, תקבולים ושורות ארנק שאינם מנוקים.
-- ===========================================================================

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000059a1', 'p59-finance@vl.test'),
  ('00000000-0000-0000-0000-0000000059a2', 'p59-owner@vl.test'),
  ('00000000-0000-0000-0000-0000000059a3', 'p59-viewer@vl.test'),
  ('00000000-0000-0000-0000-0000000059c1', 'p59-customer@vl.test');

insert into customers (id, name, event_payments_enabled) values
  ('10000000-0000-0000-0000-000000000059', 'לקוח ארנק 59', true);

insert into profiles (id, user_id, user_kind, is_admin, full_name, customer_id) values
  -- מנהל כספים: אוסף תשלומים, ואינו רואה את הארנק
  ('20000000-0000-0000-0000-0000000059a1', '00000000-0000-0000-0000-0000000059a1',
   'staff', false, 'מנהל כספים 59', null),
  -- הבעלים: מנהל מערכת
  ('20000000-0000-0000-0000-0000000059a2', '00000000-0000-0000-0000-0000000059a2',
   'staff', true, 'בעלים 59', null),
  -- רואה את הארנק בלבד
  ('20000000-0000-0000-0000-0000000059a3', '00000000-0000-0000-0000-0000000059a3',
   'staff', false, 'צופה ארנק 59', null),
  -- משתמש לקוח — גם עם המפתחות ביד, אינו רואה
  ('20000000-0000-0000-0000-0000000059c1', '00000000-0000-0000-0000-0000000059c1',
   'customer_user', false, 'לקוח 59', '10000000-0000-0000-0000-000000000059');

insert into user_permission_grants (profile_id, permission_key, allowed) values
  ('20000000-0000-0000-0000-0000000059a1', 'finance.receipts_view', true),
  ('20000000-0000-0000-0000-0000000059a1', 'finance.receipts_manage', true),
  ('20000000-0000-0000-0000-0000000059a3', 'finance.cash_wallet_view', true),
  ('20000000-0000-0000-0000-0000000059c1', 'finance.cash_wallet_view', true),
  ('20000000-0000-0000-0000-0000000059c1', 'finance.cash_wallet_manage', true),
  ('20000000-0000-0000-0000-0000000059c1', 'finance.event_payments_manage', true);

create temp table t59 as
select current_date + 950 as d;
grant select on t59 to authenticated;

insert into events (id, customer_id, end_client_name, event_number, event_date, status_id)
select v.id, '10000000-0000-0000-0000-000000000059', v.name, v.num, (select d from t59) + v.off,
       (select id from statuses where entity = 'event' and code = 'planned' and deleted_at is null)
from (values
  ('30000000-0000-0000-0000-0000000059e1'::uuid, 'משפחת כהן 59', 'EV-59-1', 0),
  ('30000000-0000-0000-0000-0000000059e2'::uuid, 'משפחת לוי 59', 'EV-59-2', 1)
) v(id, name, num, off);

delete from tasks where event_id in ('30000000-0000-0000-0000-0000000059e1',
                                     '30000000-0000-0000-0000-0000000059e2');

insert into tasks (id, event_id, customer_id, task_type_id, task_date, status_id, title, hours_count, worker_count)
select '31000000-0000-0000-0000-0000000059a1', '30000000-0000-0000-0000-0000000059e1',
       '10000000-0000-0000-0000-000000000059', (select id from task_types where code = 'setup' limit 1),
       (select d from t59), (select id from statuses where entity = 'task' and code = 'assigned' and deleted_at is null),
       'הקמה 59', 4, 2;

insert into task_pricing (task_id, price, is_manual) values
  ('31000000-0000-0000-0000-0000000059a1', 2000, true);


\echo '--- 1. מי רשאי ---'

select t_eq('anon אינו רשאי להוסיף חיוב',
  has_function_privilege('anon', 'event_charge_add(uuid, text, numeric, text)', 'execute'), false);
select t_eq('ואינו רשאי לקרוא את הארנק',
  has_function_privilege('anon', 'cash_wallet(date, date)', 'execute'), false);
select t_eq('RLS דלוק על שתי הטבלאות, בלי אף פוליסה',
  (select bool_and(c.relrowsecurity) and not exists (
            select 1 from pg_policies p where p.tablename in ('cash_wallet_entries', 'event_charges'))
     from pg_class c where c.relname in ('cash_wallet_entries', 'event_charges')),
  true);

set role authenticated;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000059a1', false);
select t_expect_fail('מנהל הכספים אינו רואה את הארנק — אין implied_by',
  $$select cash_wallet(current_date, current_date)$$);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000059c1', false);
select t_expect_fail('משתמש לקוח אינו רואה את הארנק — גם עם המפתח ביד',
  $$select cash_wallet(current_date, current_date)$$);
select t_expect_fail('ואינו מוסיף חיוב',
  $$select event_charge_add('30000000-0000-0000-0000-0000000059e1', 'עלות ייצור', 1000)$$);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000059a3', false);
select t_expect_ok('צופה הארנק רואה אותו',
  $$select cash_wallet(current_date, current_date)$$);
select t_eq('ואינו מורשה לנהל',
  (select (cash_wallet(current_date, current_date) ->> 'can_manage')::boolean), false);
select t_expect_fail('ואינו מוסיף הוצאה',
  $$select cash_wallet_entry_add('expense', 10, 'בדיקה')$$);


\echo '--- 2. חיוב ידני על אירוע ---'

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000059a1', false);

select t_expect_ok('עלות ייצור 1,000 על האירוע',
  $$select event_charge_add('30000000-0000-0000-0000-0000000059e1', '  עלות ייצור  ', 1000, 'שלט כניסה')$$);
select t_eq('מגיע: 2,000 לוגיסטיקה + 1,000 חיוב = 3,000',
  (select (event_payment_summary('30000000-0000-0000-0000-0000000059e1') ->> 'due')::numeric), 3000.00);
select t_eq('החיוב הוא שורה בפירוט, אחרונה, עם מזהה והערה',
  (select (l ->> 'label') || '/' || (l ->> 'amount') || '/' || (l ->> 'note') || '/' || ((l ->> 'charge_id') is not null)::text
     from jsonb_array_elements(event_payment_summary('30000000-0000-0000-0000-0000000059e1') -> 'lines')
          with ordinality x(l, o)
    order by o desc limit 1),
  'עלות ייצור/1000.00/שלט כניסה/true');
select t_eq('מסך התשלומים סופר את החיוב',
  (select due || '/' || balance from event_payments_list((select d from t59) - 1, (select d from t59) + 1)
    where event_id = '30000000-0000-0000-0000-0000000059e1'),
  '3000.00/3000.00');
select t_eq('והדשבורד',
  (select (event_payments_dashboard((select d from t59) - 1, (select d from t59) + 1) ->> 'due')::numeric),
  3000.00);
select t_expect_ok('הובלה מיוחדת 450.50 על אירוע בלי משימות',
  $$select event_charge_add('30000000-0000-0000-0000-0000000059e2', 'הובלה מיוחדת', 450.50)$$);
select t_eq('החיוב לבדו הוא כל מה שמגיע',
  (select (event_payment_summary('30000000-0000-0000-0000-0000000059e2') ->> 'due')::numeric), 450.50);

select t_expect_fail('חיוב בלי תיאור נדחה',
  $$select event_charge_add('30000000-0000-0000-0000-0000000059e1', '  ', 10)$$);
select t_expect_fail('חיוב של אפס נדחה',
  $$select event_charge_add('30000000-0000-0000-0000-0000000059e1', 'משהו', 0)$$);
select t_expect_fail('שלוש ספרות אחרי הנקודה נדחות',
  $$select event_charge_add('30000000-0000-0000-0000-0000000059e1', 'משהו', 1.005)$$);

-- החיפוש של המזהה כ-postgres: לתפקיד authenticated הטבלה ריקה (RLS בלי פוליסה)
reset role;
create temp table ch59 as
  select id from event_charges where event_id = '30000000-0000-0000-0000-0000000059e2';
grant select on ch59 to authenticated;
set role authenticated;

select t_eq('קריאה ישירה של הטבלה אינה מחזירה דבר',
  (select count(*)::int from event_charges), 0);
select t_expect_ok('מחיקת החיוב של האירוע השני',
  $$select event_charge_remove((select id from ch59))$$);
select t_eq('והאירוע חזר לאפס',
  (select (event_payment_summary('30000000-0000-0000-0000-0000000059e2') ->> 'due')::numeric), 0.00);
select t_expect_fail('מחיקה שנייה נכשלת',
  $$select event_charge_remove((select id from ch59))$$);


\echo '--- 3. ארנק המזומנים ---'

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000059a2', false);
create temp table w59 as
  select (cash_wallet(current_date, current_date) ->> 'balance')::numeric as before;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000059a1', false);
select t_expect_ok('1,200 במזומן על האירוע',
  $$select event_payment_add('30000000-0000-0000-0000-0000000059e1', 1200, 'cash', null, (select d from t59))$$);
select t_expect_ok('800 באחר — אינו נכנס לארנק',
  $$select event_payment_add('30000000-0000-0000-0000-0000000059e1', 800, 'other', null, (select d from t59))$$);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000059a2', false);
select t_expect_ok('הבעלים: יתרת פתיחה 5,000',
  $$select cash_wallet_entry_add('income', 5000, 'יתרת פתיחה', null, (select d from t59) - 1)$$);
select t_expect_ok('הבעלים: קניתי אוטו, 10,000',
  $$select cash_wallet_entry_add('expense', 10000, 'קניתי אוטו', 'יד שנייה', (select d from t59) + 1)$$);

select t_eq('היתרה: +1,200 +5,000 −10,000 = −3,800 מול מה שהיה',
  (select (cash_wallet(current_date, current_date) ->> 'balance')::numeric - (select before from w59)),
  -3800.00);

create temp table c59 as
  select cash_wallet((select d from t59) - 1, (select d from t59) + 1) as j;

select t_eq('בטווח: נכנס 1,200, הכנסה 5,000, הוצאות 10,000',
  (select (j ->> 'cash_in') || '/' || (j ->> 'income') || '/' || (j ->> 'expenses') from c59),
  '1200.00/5000.00/10000.00');
select t_eq('פתיחה + תנועות = סגירה = היתרה (אין תנועות אחרי הטווח)',
  (select ((j ->> 'opening')::numeric + 1200 + 5000 - 10000 = (j ->> 'closing')::numeric)
          and (j ->> 'closing') = (j ->> 'balance') from c59),
  true);
select t_eq('התנועות: החדשה ראשונה, עם הסימן שלה',
  (select string_agg((e ->> 'source') || ':' || (e ->> 'amount'), ',' order by o)
     from c59, jsonb_array_elements(j -> 'entries') with ordinality x(e, o)),
  'expense:-10000.00,payment:1200.00,income:5000.00');
select t_eq('היתרה הרצה של השורה האחרונה היא הסגירה',
  (select (j -> 'entries' -> 0 ->> 'running') = (j ->> 'closing') from c59), true);
select t_eq('שורת המזומן יודעת מאיזה אירוע ולקוח',
  (select (e ->> 'event_name') || '/' || (e ->> 'customer_name')
     from c59, jsonb_array_elements(j -> 'entries') e where e ->> 'source' = 'payment'),
  'משפחת כהן 59/לקוח ארנק 59');

select t_expect_fail('סוג שאינו הוצאה או הכנסה נדחה',
  $$select cash_wallet_entry_add('loan', 10, 'הלוואה')$$);
select t_expect_fail('בלי תיאור נדחה',
  $$select cash_wallet_entry_add('expense', 10, '')$$);
select t_expect_fail('טווח הפוך נדחה',
  $$select cash_wallet(current_date, current_date - 1)$$);


\echo '--- 4. מחיקות יוצאות מהארנק ---'

select t_eq('ההוצאה היא שורה בארנק — המזהה ממנו',
  (select count(*)::int from c59, jsonb_array_elements(j -> 'entries') e where e ->> 'label' = 'קניתי אוטו'), 1);
select t_expect_ok('מחיקת ההוצאה',
  $$select cash_wallet_entry_remove((select (e ->> 'id')::uuid
      from c59, jsonb_array_elements(j -> 'entries') e where e ->> 'label' = 'קניתי אוטו'))$$);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000059a1', false);
select t_expect_ok('מחיקת התשלום במזומן בכרטיס האירוע',
  $$select event_payment_remove((select id from receipts
      where event_id = '30000000-0000-0000-0000-0000000059e1' and method = 'cash'))$$);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000059a2', false);
select t_eq('נשארה רק יתרת הפתיחה: +5,000',
  (select (cash_wallet(current_date, current_date) ->> 'balance')::numeric - (select before from w59)),
  5000.00);


\echo '--- 5. אירוע שבוטל אינו חייב — גם לא חיוב ידני ---'

reset role;
select set_config('request.jwt.claim.sub', '', false);
update events set status_id = (select id from statuses where entity = 'event' and code = 'cancelled' and deleted_at is null)
 where id = '30000000-0000-0000-0000-0000000059e1';

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000059a1', false);
select t_eq('מגיע 0, ושולם 800 נשאר',
  (select (s ->> 'due') || '/' || (s ->> 'paid')
     from (select event_payment_summary('30000000-0000-0000-0000-0000000059e1') as s) x),
  '0.00/800.00');
select t_expect_fail('ואין חיוב חדש על אירוע שבוטל',
  $$select event_charge_add('30000000-0000-0000-0000-0000000059e1', 'משהו', 10)$$);

reset role;
select set_config('request.jwt.claim.sub', '', false);
