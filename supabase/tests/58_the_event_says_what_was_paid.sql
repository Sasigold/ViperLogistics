\pset tuples_only on
\pset format unaligned

-- ===========================================================================
-- ‏58: האירוע אומר כמה מגיע עליו, כמה שולם וכמה נשאר (0203).
--
-- החבילה מקימה שני לקוחות (אחד שהמודול פתוח לו ואחד שלא), ארבעה אירועים
-- וחמש דמויות משלה ב-`current_date + 900`, מעבר לכל טווח אחר. היא משאירה
-- אחריה אירועים, משימות ותקבולים שאינם מנוקים.
--
-- האירוע הראשי (E1): הקמה 1,500 + פירוק 1,500 + תוספת 200 = לוגיסטיקה 3,200;
-- הובלות 2,500 (100%), ריהוט ישן 1,000 (70% → 700), ריהוט חדש 2,000 (20% →
-- 400). סך הכול מגיע: 6,800.
-- ===========================================================================

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000058a1', 'p58-finance@vl.test'),
  ('00000000-0000-0000-0000-0000000058a2', 'p58-viewer@vl.test'),
  ('00000000-0000-0000-0000-0000000058a3', 'p58-coord@vl.test'),
  ('00000000-0000-0000-0000-0000000058a4', 'p58-denied@vl.test'),
  ('00000000-0000-0000-0000-0000000058c1', 'p58-customer@vl.test');

insert into customers (id, name, event_payments_enabled) values
  ('10000000-0000-0000-0000-000000000058', 'לקוח תשלומים 58', true),
  ('10000000-0000-0000-0000-00000000058b', 'לקוח בלי תשלומים 58', false);
-- ובלי לציין את הדגל — כדי לראות מה ברירת המחדל
insert into customers (id, name) values
  ('10000000-0000-0000-0000-00000000058d', 'לקוח רגיל 58');

insert into profiles (id, user_id, user_kind, is_admin, full_name, customer_id) values
  -- מנהל כספים: תקבולים — צפייה וניהול, ומהם נגזרים תשלומי האירועים
  ('20000000-0000-0000-0000-0000000058a1', '00000000-0000-0000-0000-0000000058a1',
   'staff', false, 'מנהל כספים 58', null),
  -- צופה בתקבולים בלבד
  ('20000000-0000-0000-0000-0000000058a2', '00000000-0000-0000-0000-0000000058a2',
   'staff', false, 'צופה 58', null),
  -- רכז: רואה אירועים, ואין לו כסף
  ('20000000-0000-0000-0000-0000000058a3', '00000000-0000-0000-0000-0000000058a3',
   'staff', false, 'רכז 58', null),
  -- רואה תקבולים, ונסגר לו תשלומי אירועים במפורש
  ('20000000-0000-0000-0000-0000000058a4', '00000000-0000-0000-0000-0000000058a4',
   'staff', false, 'חסום 58', null),
  -- משתמש של הלקוח — גם עם המפתח ביד, אינו רואה את ההכנסה של וייפר
  ('20000000-0000-0000-0000-0000000058c1', '00000000-0000-0000-0000-0000000058c1',
   'customer_user', false, 'לקוח 58', '10000000-0000-0000-0000-000000000058');

insert into user_permission_grants (profile_id, permission_key, allowed) values
  ('20000000-0000-0000-0000-0000000058a1', 'finance.receipts_view', true),
  ('20000000-0000-0000-0000-0000000058a1', 'finance.receipts_manage', true),
  ('20000000-0000-0000-0000-0000000058a2', 'finance.receipts_view', true),
  ('20000000-0000-0000-0000-0000000058a2', 'finance.receipts_manage', false),
  ('20000000-0000-0000-0000-0000000058a3', 'events.view', true),
  ('20000000-0000-0000-0000-0000000058a3', 'finance.receipts_view', false),
  ('20000000-0000-0000-0000-0000000058a3', 'dashboard.financial', false),
  ('20000000-0000-0000-0000-0000000058a4', 'finance.receipts_view', true),
  ('20000000-0000-0000-0000-0000000058a4', 'finance.event_payments_view', false),
  ('20000000-0000-0000-0000-0000000058c1', 'finance.event_payments_view', true),
  ('20000000-0000-0000-0000-0000000058c1', 'finance.event_payments_manage', true);

create temp table t58 as
select current_date + 900 as d;
grant select on t58 to authenticated;

insert into events (id, customer_id, end_client_name, event_number, event_date, status_id)
select v.id, v.customer, v.name, v.num, (select d from t58) + v.off,
       (select id from statuses where entity = 'event' and code = 'planned' and deleted_at is null)
from (values
  ('30000000-0000-0000-0000-0000000058e1'::uuid, '10000000-0000-0000-0000-000000000058'::uuid, 'משפחת כהן 58', 'EV-58-1', 0),
  ('30000000-0000-0000-0000-0000000058e2'::uuid, '10000000-0000-0000-0000-000000000058'::uuid, 'משפחת לוי 58',  'EV-58-2', 1),
  ('30000000-0000-0000-0000-0000000058e3'::uuid, '10000000-0000-0000-0000-00000000058b'::uuid, 'משפחת אחרת 58', 'EV-58-3', 1),
  ('30000000-0000-0000-0000-0000000058e4'::uuid, '10000000-0000-0000-0000-000000000058'::uuid, 'עוד לא תומחר 58', 'EV-58-4', 2)
) v(id, customer, name, num, off);

-- המשימות האוטומטיות של 0009 נמחקות; המשימות של החבילה נזרעות עם מחיר.
delete from tasks where event_id in ('30000000-0000-0000-0000-0000000058e1',
                                     '30000000-0000-0000-0000-0000000058e2',
                                     '30000000-0000-0000-0000-0000000058e3',
                                     '30000000-0000-0000-0000-0000000058e4');

insert into tasks (id, event_id, customer_id, task_type_id, task_date, status_id, title, hours_count, worker_count)
select v.id, v.event, v.customer, (select id from task_types where code = v.code limit 1),
       (select d from t58), (select id from statuses where entity = 'task' and code = 'assigned' and deleted_at is null),
       v.title, 4, 2
from (values
  ('31000000-0000-0000-0000-0000000058a1'::uuid, '30000000-0000-0000-0000-0000000058e1'::uuid, '10000000-0000-0000-0000-000000000058'::uuid, 'setup',    'הקמה 58'),
  ('31000000-0000-0000-0000-0000000058a2'::uuid, '30000000-0000-0000-0000-0000000058e1'::uuid, '10000000-0000-0000-0000-000000000058'::uuid, 'teardown', 'פירוק 58'),
  ('31000000-0000-0000-0000-0000000058b1'::uuid, '30000000-0000-0000-0000-0000000058e2'::uuid, '10000000-0000-0000-0000-000000000058'::uuid, 'setup',    'הקמה 58 ב'),
  ('31000000-0000-0000-0000-0000000058c1'::uuid, '30000000-0000-0000-0000-0000000058e3'::uuid, '10000000-0000-0000-0000-00000000058b'::uuid, 'setup',    'הקמה 58 ג')
) v(id, event, customer, code, title);

insert into task_pricing (task_id, price, is_manual) values
  ('31000000-0000-0000-0000-0000000058a1', 1500, true),
  ('31000000-0000-0000-0000-0000000058a2', 1500, true),
  ('31000000-0000-0000-0000-0000000058b1', 1000, true),
  ('31000000-0000-0000-0000-0000000058c1',  800, true);

insert into task_price_addons (task_id, amount, note) values
  ('31000000-0000-0000-0000-0000000058a1', 200, 'המתנה בשער');

insert into event_income (event_id, category_id, amount, viper_share_pct)
select '30000000-0000-0000-0000-0000000058e1', id,
       case name when 'ריהוט ישן' then 1000 when 'ריהוט חדש' then 2000 else 2500 end,
       case name when 'ריהוט ישן' then 70 when 'ריהוט חדש' then 20 else 100 end
  from income_categories where name in ('ריהוט ישן', 'ריהוט חדש', 'הובלות');


\echo '--- 1. מי רואה ---'

select t_eq('הדגל כבוי כברירת מחדל ללקוח חדש',
  (select event_payments_enabled from customers where id = '10000000-0000-0000-0000-00000000058d'),
  false);

select t_eq('anon אינו רשאי לרשום תשלום',
  has_function_privilege('anon', 'event_payment_add(uuid, numeric, text, text, date)', 'execute'), false);
select t_eq('ואינו רשאי לקרוא את הפירוט',
  has_function_privilege('anon', 'event_payment_summary(uuid)', 'execute'), false);

set role authenticated;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000058a3', false);
select t_expect_fail('רכז בלי מפתח כספי אינו רואה כמה מגיע',
  $$select event_payment_summary('30000000-0000-0000-0000-0000000058e1')$$);
select t_eq('ובדשבורד הכרטיס אינו קיים בשבילו',
  (select event_payments_dashboard((select d from t58) - 5, (select d from t58) + 5)) is null, true);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000058a4', false);
select t_expect_fail('דחייה מפורשת גוברת על הנגזרת מהתקבולים',
  $$select event_payment_summary('30000000-0000-0000-0000-0000000058e1')$$);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000058c1', false);
select t_expect_fail('משתמש לקוח אינו רואה את הפירוט — גם עם המפתח ביד',
  $$select event_payment_summary('30000000-0000-0000-0000-0000000058e1')$$);
select t_expect_fail('ואינו רושם תשלום',
  $$select event_payment_add('30000000-0000-0000-0000-0000000058e1', 100, 'cash')$$);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000058a2', false);
select t_expect_ok('צופה בתקבולים רואה את הפירוט (נגזר)',
  $$select event_payment_summary('30000000-0000-0000-0000-0000000058e1')$$);
select t_eq('ואינו מורשה לנהל',
  (select (event_payment_summary('30000000-0000-0000-0000-0000000058e1') ->> 'can_manage')::boolean), false);
select t_expect_fail('ואינו רושם תשלום',
  $$select event_payment_add('30000000-0000-0000-0000-0000000058e1', 100, 'cash')$$);


\echo '--- 2. כמה מגיע ---'

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000058a1', false);

create temp table s58 as
  select event_payment_summary('30000000-0000-0000-0000-0000000058e1') as j;

select t_eq('סך הכול מגיע: לוגיסטיקה + הובלות + עמלות',
  (select (j ->> 'due')::numeric from s58), 6800.00);
select t_eq('הלוגיסטיקה כוללת את התוספת',
  (select (j -> 'lines' -> 0 ->> 'amount')::numeric from s58), 3200.00);
select t_eq('הסדר: לוגיסטיקה, הובלות, ואחריהן העמלות',
  (select string_agg(l ->> 'label', ',' order by o) from s58,
          jsonb_array_elements(j -> 'lines') with ordinality as x(l, o)),
  'לוגיסטיקה,הובלות,ריהוט ישן,ריהוט חדש');
select t_eq('עמלה על ריהוט ישן היא 70% מהסכום',
  (select (l ->> 'amount')::numeric || '/' || (l ->> 'gross')::numeric || '/' || (l ->> 'pct')::numeric
     from s58, jsonb_array_elements(j -> 'lines') l where l ->> 'label' = 'ריהוט ישן'),
  '700.00/1000.00/70.00');
select t_eq('עוד לא שולם דבר',
  (select (j ->> 'paid')::numeric || '/' || (j ->> 'balance')::numeric from s58), '0.00/6800.00');

select t_eq('ללקוח שהמודול סגור לו — enabled=false',
  (select (event_payment_summary('30000000-0000-0000-0000-0000000058e3') ->> 'enabled')::boolean), false);


\echo '--- 3. אוסף תשלום ---'

select t_expect_ok('2,000 במזומן, בלי תאריך',
  $$select event_payment_add('30000000-0000-0000-0000-0000000058e1', 2000, 'cash')$$);
select t_expect_ok('1,000 באחר, עם הערה ותאריך',
  $$select event_payment_add('30000000-0000-0000-0000-0000000058e1', 1000, 'other', '  העברה 123  ',
                             (select d from t58))$$);

select t_eq('שולם 3,000, נשארו 3,800',
  (select (s ->> 'paid')::numeric || '/' || (s ->> 'balance')::numeric
     from (select event_payment_summary('30000000-0000-0000-0000-0000000058e1') as s) x),
  '3000.00/3800.00');
select t_eq('תשלום בלי תאריך נרשם על היום בישראל',
  (select received_at from receipts
    where event_id = '30000000-0000-0000-0000-0000000058e1' and method = 'cash'),
  (now() at time zone 'Asia/Jerusalem')::date);
select t_eq('ההערה נשמרת בלי רווחים מיותרים, והתשלום על הלקוח של האירוע',
  (select note || '/' || (customer_id = '10000000-0000-0000-0000-000000000058')::text from receipts
    where event_id = '30000000-0000-0000-0000-0000000058e1' and method = 'other'),
  'העברה 123/true');
select t_eq('ההיסטוריה: החדש ראשון, ומי רשם',
  (select string_agg((p ->> 'amount') || ':' || (p ->> 'method') || ':' || (p ->> 'created_by_name'), ','
                     order by o)
     from jsonb_array_elements(event_payment_summary('30000000-0000-0000-0000-0000000058e1') -> 'payments')
          with ordinality x(p, o)),
  '1000.00:other:מנהל כספים 58,2000.00:cash:מנהל כספים 58');

select t_expect_fail('סכום אפס נדחה',
  $$select event_payment_add('30000000-0000-0000-0000-0000000058e1', 0, 'cash')$$);
select t_expect_fail('סכום שלילי נדחה',
  $$select event_payment_add('30000000-0000-0000-0000-0000000058e1', -50, 'cash')$$);
select t_expect_fail('שלוש ספרות אחרי הנקודה נדחות',
  $$select event_payment_add('30000000-0000-0000-0000-0000000058e1', 10.555, 'cash')$$);
select t_expect_fail('אמצעי שאינו מזומן או אחר נדחה',
  $$select event_payment_add('30000000-0000-0000-0000-0000000058e1', 10, 'card')$$);
select t_expect_fail('לקוח שהמודול סגור לו — אין רישום',
  $$select event_payment_add('30000000-0000-0000-0000-0000000058e3', 10, 'cash')$$);


\echo '--- 4. מחיקה ---'

select t_expect_ok('מנהל הכספים מוחק את התשלום של 1,000',
  $$select event_payment_remove((select id from receipts
      where event_id = '30000000-0000-0000-0000-0000000058e1' and method = 'other'))$$);
select t_eq('התשלום ירד מהרשימה, והיתרה חזרה ל-4,800',
  (select (select count(*) from receipts where event_id = '30000000-0000-0000-0000-0000000058e1')
          || '/' || (event_payment_summary('30000000-0000-0000-0000-0000000058e1') ->> 'balance')),
  '1/4800.00');
select t_expect_fail('מחיקה שנייה של אותו תשלום נכשלת',
  $$select event_payment_remove((select id from receipts
      where event_id = '30000000-0000-0000-0000-0000000058e1' and method = 'other'))$$);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000058a2', false);
select t_expect_fail('הצופה אינו מוחק',
  $$select event_payment_remove((select id from receipts
      where event_id = '30000000-0000-0000-0000-0000000058e1' and method = 'cash'))$$);

reset role;
select set_config('request.jwt.claim.sub', '', false);


\echo '--- 5. התקבול נשאר נאמן לאירוע ---'

select t_eq('המחיקה רכה — השורה עדיין קיימת, מסומנת כמחוקה',
  (select count(*)::int from receipts
    where event_id = '30000000-0000-0000-0000-0000000058e1' and deleted_at is not null),
  1);

select t_expect_fail('אי אפשר להעביר תשלום של אירוע ללקוח אחר',
  $$update receipts set customer_id = '10000000-0000-0000-0000-00000000058b'
     where event_id = '30000000-0000-0000-0000-0000000058e1' and deleted_at is null$$);
select t_expect_fail('ותשלום על אירוע אינו שלילי',
  $$insert into receipts (customer_id, event_id, amount)
    values ('10000000-0000-0000-0000-000000000058', '30000000-0000-0000-0000-0000000058e1', -10)$$);
select t_expect_ok('תקבול על החשבון — שלילי מותר, כמו קודם',
  $$insert into receipts (customer_id, amount, received_at, note)
    values ('10000000-0000-0000-0000-00000000058b', -10, current_date + 2000, 'זיכוי 58')$$);


\echo '--- 6. אירוע שבוטל: אינו חייב, ומה ששולם נשאר ---'

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000058a1', false);
select t_expect_ok('תשלום של 300 על האירוע השני',
  $$select event_payment_add('30000000-0000-0000-0000-0000000058e2', 300, 'cash')$$);
reset role;
select set_config('request.jwt.claim.sub', '', false);

update events set status_id = (select id from statuses where entity = 'event' and code = 'cancelled' and deleted_at is null)
 where id = '30000000-0000-0000-0000-0000000058e2';

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000058a1', false);

select t_eq('האירוע שבוטל: מגיע 0, שולם 300, יתרת זכות',
  (select cancelled || '/' || due || '/' || paid || '/' || balance
     from event_payments_list((select d from t58) - 5, (select d from t58) + 5)
    where event_id = '30000000-0000-0000-0000-0000000058e2'),
  'true/0.00/300.00/-300.00');


\echo '--- 7. מסך התשלומים ---'

select t_eq('שלושה אירועים בטווח — בלי האירוע של הלקוח שהמודול סגור לו',
  (select string_agg(event_number, ',' order by event_date, event_number)
     from event_payments_list((select d from t58) - 5, (select d from t58) + 5)),
  'EV-58-1,EV-58-2,EV-58-4');
select t_eq('E1: מגיע 6,800, שולם 2,000, יתרה 4,800, תשלום אחד',
  (select due || '/' || paid || '/' || balance || '/' || payments_count
     from event_payments_list((select d from t58) - 5, (select d from t58) + 5)
    where event_id = '30000000-0000-0000-0000-0000000058e1'),
  '6800.00/2000.00/4800.00/1');
select t_expect_fail('טווח של יותר משנה נדחה',
  $$select * from event_payments_list(current_date, current_date + 500)$$);


\echo '--- 8. הדשבורד ---'

select t_eq('מגיע 6,800 · שולם 2,300 · לא שולם 4,800 (יתרת הזכות אינה מקזזת)',
  (select (j ->> 'due') || '/' || (j ->> 'paid') || '/' || (j ->> 'unpaid')
     from (select event_payments_dashboard((select d from t58) - 5, (select d from t58) + 5) as j) x),
  '6800.00/2300.00/4800.00');
select t_eq('שני אירועים נספרים, אחד פתוח, אף אחד לא שולם במלואו',
  (select (j ->> 'events') || '/' || (j ->> 'open_events') || '/' || (j ->> 'paid_events')
     from (select event_payments_dashboard((select d from t58) - 5, (select d from t58) + 5) as j) x),
  '2/1/0');
select t_eq('החודש של האירוע הראשי מופיע בפילוח החודשי עם היתרה שלו',
  (select (m ->> 'unpaid')::numeric
     from jsonb_array_elements(event_payments_dashboard((select d from t58) - 5, (select d from t58) + 5) -> 'months') m
    where (m ->> 'month')::date = date_trunc('month', (select d from t58))::date),
  4800.00::numeric);
select t_eq('הכותרת נבנית משם הלקוח שבנתונים — ורק ממי שהדגל דלוק אצלו',
  (select (j -> 'customers') @> '["לקוח תשלומים 58"]'::jsonb
          and not (j -> 'customers') @> '["לקוח בלי תשלומים 58"]'::jsonb
     from (select event_payments_dashboard((select d from t58) - 5, (select d from t58) + 5) as j) x),
  true);

select t_expect_ok('התשלום של היתרה כולה',
  $$select event_payment_add('30000000-0000-0000-0000-0000000058e1', 4800, 'cash')$$);
select t_eq('ועכשיו: לא שולם 0, אירוע אחד שולם במלואו',
  (select (j ->> 'unpaid') || '/' || (j ->> 'paid_events')
     from (select event_payments_dashboard((select d from t58) - 5, (select d from t58) + 5) as j) x),
  '0.00/1');

reset role;
select set_config('request.jwt.claim.sub', '', false);
