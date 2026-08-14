\pset tuples_only on
\pset format unaligned

-- ===========================================================================
-- 12: הכנסות לפי קטגוריה, חלוקת הכנסות ותקבולים (0068/0069).
--
-- החבילה מקימה לקוח, אירוע ואנשים משלה ואינה נשענת על אף חבילה קודמת — 02
-- הופכת את f2 לאדמין ו-06/09 מזיזות מפתחות על f1/f3. האירוע יושב רחוק בעתיד
-- (current_date + 210) כדי שטווח הבדיקות [+200, +220] לא יתפוס משימות
-- שחבילות אחרות הזריעו סביב היום.
-- ===========================================================================

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000012a1', 'finance@vl.test'),
  ('00000000-0000-0000-0000-0000000012a2', 'noincome@vl.test'),
  ('00000000-0000-0000-0000-0000000012a3', 'blank12@vl.test');

insert into customers (id, name) values
  ('10000000-0000-0000-0000-000000000012', 'לקוח חלוקת הכנסות');

insert into profiles (id, user_id, user_kind, is_admin, full_name) values
  -- מנהלת כספים: כל מפתחות ה-finance + מה שהסקשנים דורשים
  ('20000000-0000-0000-0000-0000000012a1', '00000000-0000-0000-0000-0000000012a1',
   'staff', false, 'מנהלת כספים'),
  -- מזין אירועים בלי finance.income_edit: המפתח נשמט בשקט
  ('20000000-0000-0000-0000-0000000012a2', '00000000-0000-0000-0000-0000000012a2',
   'staff', false, 'מזין בלי הרשאת הכנסות'),
  -- עובד בלי שום מפתח: RLS מחזירה לו כלום
  ('20000000-0000-0000-0000-0000000012a3', '00000000-0000-0000-0000-0000000012a3',
   'staff', false, 'עובד ללא מפתחות');

insert into user_permission_grants (profile_id, permission_key, allowed) values
  ('20000000-0000-0000-0000-0000000012a1', 'events.create', true),
  ('20000000-0000-0000-0000-0000000012a1', 'events.edit', true),
  ('20000000-0000-0000-0000-0000000012a1', 'customers.view', true),
  ('20000000-0000-0000-0000-0000000012a1', 'pricing.view', true),
  ('20000000-0000-0000-0000-0000000012a1', 'pricing.revenue', true),
  ('20000000-0000-0000-0000-0000000012a1', 'finance.income_view', true),
  ('20000000-0000-0000-0000-0000000012a1', 'finance.income_edit', true),
  ('20000000-0000-0000-0000-0000000012a1', 'finance.manage_splits', true),
  ('20000000-0000-0000-0000-0000000012a1', 'finance.receipts_view', true),
  ('20000000-0000-0000-0000-0000000012a1', 'finance.receipts_manage', true),
  ('20000000-0000-0000-0000-0000000012a2', 'events.create', true),
  ('20000000-0000-0000-0000-0000000012a2', 'events.edit', true),
  ('20000000-0000-0000-0000-0000000012a2', 'customers.view', true);

-- מזהי הקטגוריות שנזרעו ב-0068, בטבלה זמנית כדי שהבדיקות יקראו בשמות
create temp table t12cat as
select id, name, family from income_categories;
grant select on t12cat to authenticated;

\echo '--- הקטלוג נזרע ב-0068 ---'

select t_eq('ארבע קטגוריות נזרעו',
  (select count(*)::int from income_categories where deleted_at is null), 4);
select t_eq('שתיים ממשפחת ריהוט',
  (select count(*)::int from income_categories where family = 'furniture'), 2);
select t_eq('אחוז עלות המעביד נזרע',
  (select (value ->> 'pct')::numeric from app_settings where key = 'finance.employer_cost'), 30::numeric);

-- חלוקה ללקוח: ריהוט ישן 70/30, ריהוט חדש 20/80. לוגיסטיקה בכוונה לא מופעלת.
insert into customer_income_splits (customer_id, category_id, viper_share_pct)
select '10000000-0000-0000-0000-000000000012', id,
       case name when 'ריהוט ישן' then 70 else 20 end
  from income_categories where name in ('ריהוט ישן', 'ריהוט חדש');

\echo '--- RLS: מי שאין לו מפתח לא רואה ולא כותב ---'

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000012a3', false);

select t_eq('בלי מפתח: קטלוג הקטגוריות ריק',
  (select count(*)::int from income_categories), 0);
select t_eq('בלי מפתח: חלוקות הלקוח ריקות',
  (select count(*)::int from customer_income_splits), 0);
select t_eq('בלי מפתח: תקבולים ריקים',
  (select count(*)::int from receipts), 0);
select t_expect_fail('בלי מפתח: הוספת תקבול נחסמת',
  $$insert into receipts (customer_id, amount)
    values ('10000000-0000-0000-0000-000000000012', 100)$$);
select t_expect_fail('בלי finance.manage_splits: כתיבת חלוקה נחסמת',
  $$insert into customer_income_splits (customer_id, category_id)
    select '10000000-0000-0000-0000-000000000012', id from t12cat where name = 'לוגיסטיקה'$$);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000012a1', false);

select t_eq('מנהלת הכספים רואה את הקטלוג',
  (select count(*)::int from income_categories), 4);
select t_eq('ורואה את חלוקות הלקוח',
  (select count(*)::int from customer_income_splits
    where customer_id = '10000000-0000-0000-0000-000000000012'), 2);

\echo '--- create_event עם הכנסות: כתיבה + snapshot ---'

-- ריהוט ישן 1000 (70/30), ריהוט חדש 500 (20/80)
create temp table t12ev as
select (t_created_event(jsonb_build_object(
  'customer_id', '10000000-0000-0000-0000-000000000012',
  'event_date', (current_date + 210)::text,
  'event_income', (select jsonb_object_agg(id::text,
      case name when 'ריהוט ישן' then '1000' else '500' end)
    from t12cat where name in ('ריהוט ישן', 'ריהוט חדש'))))).id as id;
grant select on t12ev to authenticated;

select t_eq('שתי שורות הכנסה נכתבו',
  (select count(*)::int from event_income where event_id = (select id from t12ev)), 2);
select t_eq('הסכום נשמר',
  (select amount from event_income
    where event_id = (select id from t12ev)
      and category_id = (select id from t12cat where name = 'ריהוט ישן')), 1000::numeric(12,2));
select t_eq('האחוז הוצמד מחלוקת הלקוח (snapshot)',
  (select viper_share_pct from event_income
    where event_id = (select id from t12ev)
      and category_id = (select id from t12cat where name = 'ריהוט ישן')), 70::numeric(5,2));

select t_expect_fail('קטגוריה שאינה מופעלת ללקוח נדחית',
  $$select create_event(jsonb_build_object(
      'customer_id', '10000000-0000-0000-0000-000000000012',
      'event_date', (current_date + 211)::text,
      'event_income', (select jsonb_object_agg(id::text, '250')
        from t12cat where name = 'לוגיסטיקה')))$$);

select t_expect_fail('ערך שאינו מספר נדחה בעברית',
  $$select create_event(jsonb_build_object(
      'customer_id', '10000000-0000-0000-0000-000000000012',
      'event_date', (current_date + 211)::text,
      'event_income', (select jsonb_object_agg(id::text, 'abc')
        from t12cat where name = 'ריהוט ישן')))$$);

\echo '--- בלי finance.income_edit: המפתח נשמט בשקט והאירוע נשמר ---'

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000012a2', false);

create temp table t12ev2 as
select (t_created_event(jsonb_build_object(
  'customer_id', '10000000-0000-0000-0000-000000000012',
  'event_date', (current_date + 212)::text,
  'event_income', (select jsonb_object_agg(id::text, '999')
    from t12cat where name = 'ריהוט ישן')))).id as id;
grant select on t12ev2 to authenticated;

select t_eq('האירוע עצמו נוצר',
  (select count(*)::int from events where id = (select id from t12ev2)), 1);

reset role;
select t_eq('אך לא נכתבה אף שורת הכנסה',
  (select count(*)::int from event_income where event_id = (select id from t12ev2)), 0);

\echo '--- update_event: סמנטיקת patch ו-snapshot שאינו משתנה למפרע ---'

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000012a1', false);

-- עדכון בלי המפתח — הסכומים נשארים
select t_expect_ok('עדכון בלי event_income אינו נוגע בסכומים',
  $$select update_event((select id from t12ev), jsonb_build_object('notes', 'עודכן'))$$);
select t_eq('שתי השורות עדיין קיימות',
  (select count(*)::int from event_income where event_id = (select id from t12ev)), 2);

-- שינוי החלוקה אחרי ההזנה: 70 → 60. האירוע הקיים שומר 70.
update customer_income_splits set viper_share_pct = 60
 where customer_id = '10000000-0000-0000-0000-000000000012'
   and category_id = (select id from t12cat where name = 'ריהוט ישן');

select t_eq('שינוי אחוז אינו משנה אירוע קיים (snapshot)',
  (select viper_share_pct from event_income
    where event_id = (select id from t12ev)
      and category_id = (select id from t12cat where name = 'ריהוט ישן')), 70::numeric(5,2));

-- עריכה מפורשת של הסכום כן מרעננת את האחוז לפי החלוקה הנוכחית
select t_expect_ok('עריכת סכום מרעננת את האחוז',
  $$select update_event((select id from t12ev), jsonb_build_object(
      'event_income', (select jsonb_object_agg(id::text, '1000')
        from t12cat where name = 'ריהוט ישן')))$$);
select t_eq('האחוז החדש הוצמד',
  (select viper_share_pct from event_income
    where event_id = (select id from t12ev)
      and category_id = (select id from t12cat where name = 'ריהוט ישן')), 60::numeric(5,2));

-- ומחזירים ל-70 כדי שחישובי ההמשך יישארו פשוטים
reset role;
update customer_income_splits set viper_share_pct = 70
 where customer_id = '10000000-0000-0000-0000-000000000012'
   and category_id = (select id from t12cat where name = 'ריהוט ישן');
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000012a1', false);
select t_expect_ok('עריכת הסכום מיישרת את האחוז חזרה',
  $$select update_event((select id from t12ev), jsonb_build_object(
      'event_income', (select jsonb_object_agg(id::text, '1000')
        from t12cat where name = 'ריהוט ישן')))$$);

-- ערך ריק מוחק את השורה
select t_expect_ok('ערך ריק מוחק שורת הכנסה',
  $$select update_event((select id from t12ev), jsonb_build_object(
      'event_income', (select jsonb_object_agg(id::text, '')
        from t12cat where name = 'ריהוט חדש')))$$);
select t_eq('נשארה שורה אחת',
  (select count(*)::int from event_income where event_id = (select id from t12ev)), 1);

-- ומחזירים אותה לחישובי הסקשנים
select t_expect_ok('החזרת ריהוט חדש 500',
  $$select update_event((select id from t12ev), jsonb_build_object(
      'event_income', (select jsonb_object_agg(id::text, '500')
        from t12cat where name = 'ריהוט חדש')))$$);

\echo '--- תמחור משימה + תקבול, ואז הסקשנים ---'

reset role;
-- משימת ההקמה שנוצרה אוטומטית מקבלת מחיר 1000 — רכיב ה"צוות" של ההכנסות
insert into task_pricing (task_id, price)
select t.id, 1000 from tasks t
  join task_types tt on tt.id = t.task_type_id
 where t.event_id = (select id from t12ev) and tt.code = 'setup';

insert into receipts (customer_id, amount, received_at) values
  ('10000000-0000-0000-0000-000000000012', 800, current_date + 215);

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000012a1', false);

create temp table t12sec as
select dashboard_sections(
  array['income.by_category', 'income.mix', 'finance.receivables',
        'finance.client_share', 'cost.payroll', 'cost.payroll_employer',
        'revenue.trend'],
  current_date + 200, current_date + 220, '{}') as v;
grant select on t12sec to authenticated;

-- ריהוט ישן 1000 + ריהוט חדש 500 = 1500, כולו ריהוט
select t_eq('income.by_category: סך הריהוט',
  (select (v -> 'income.by_category' ->> 'furniture_total')::numeric from t12sec), 1500::numeric);
select t_eq('income.by_category: אין לוגיסטיקה',
  (select (v -> 'income.by_category' ->> 'logistics_total')::numeric from t12sec), 0::numeric);

-- חלק הלקוח: 1000×30% + 500×80% = 700
select t_eq('finance.client_share: לפי ה-snapshot',
  (select (v -> 'finance.client_share' ->> 'total')::numeric from t12sec), 700::numeric);

-- החוב: 1500 הכנסות קטגוריה + 1000 תמחור משימה; שולם 800
select t_eq('finance.receivables: החוב כולל את שני המקורות',
  (select (v -> 'finance.receivables' ->> 'owed')::numeric from t12sec), 2500::numeric);
select t_eq('finance.receivables: שולם = התקבול',
  (select (v -> 'finance.receivables' ->> 'paid')::numeric from t12sec), 800::numeric);
select t_eq('finance.receivables: לא שולם = ההפרש',
  (select (v -> 'finance.receivables' ->> 'unpaid')::numeric from t12sec), 1700::numeric);

-- revenue.trend סוכם עכשיו את שני המקורות
select t_eq('revenue.trend כולל הכנסות קטגוריה',
  (select (select sum((e ->> 'total')::numeric)
             from jsonb_array_elements(v -> 'revenue.trend') e) from t12sec), 2500::numeric);

-- העוגה: שלוש פרוסות — שתי קטגוריות ו"צוות"
select t_eq('income.mix: שלוש פרוסות',
  (select jsonb_array_length(v -> 'income.mix') from t12sec), 3);
select t_eq('income.mix: פרוסת הצוות נושאת את תמחור המשימות',
  (select (e ->> 'total')::numeric from t12sec,
     jsonb_array_elements(v -> 'income.mix') e
    where e ->> 'label' = 'צוות לקוח חלוקת הכנסות'), 1000::numeric);

-- עלות מעביד: dashboard.payroll אינו אצל המשתמשת — הסקשן חוזר null
select t_eq('cost.payroll_employer בלי dashboard.payroll: null',
  (select v -> 'cost.payroll_employer' from t12sec), 'null'::jsonb);

-- ובלי מפתחות בכלל — הכול null
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000012a3', false);
select t_eq('בלי מפתח: income.by_category חוזר null',
  (dashboard_sections(array['income.by_category'], current_date + 200, current_date + 220, '{}')
     -> 'income.by_category'), 'null'::jsonb);
select t_eq('בלי מפתח: finance.receivables חוזר null',
  (dashboard_sections(array['finance.receivables'], current_date + 200, current_date + 220, '{}')
     -> 'finance.receivables'), 'null'::jsonb);

\echo '--- עלות מעביד: בסיס × (1 + אחוז) ---'

reset role;
select set_config('request.jwt.claim.sub', '', false);
insert into user_permission_grants (profile_id, permission_key, allowed) values
  ('20000000-0000-0000-0000-0000000012a1', 'dashboard.payroll', true);

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000012a1', false);

-- על כל טווח שהוא: total = round(base × 1.3, 2), עם האחוז שנזרע (30)
create temp table t12pay as
select dashboard_sections(array['cost.payroll', 'cost.payroll_employer'],
  current_date - 30, current_date + 30, '{}') as v;
grant select on t12pay to authenticated;

select t_eq('עלות מעביד = שכר × 1.3',
  (select (v -> 'cost.payroll_employer' ->> 'total')::numeric from t12pay),
  (select round(coalesce((v -> 'cost.payroll' ->> 'total')::numeric, 0) * 1.3, 2) from t12pay));
select t_eq('והאחוז מדווח בתשובה',
  (select (v -> 'cost.payroll_employer' ->> 'pct')::numeric from t12pay), 30::numeric);

reset role;
