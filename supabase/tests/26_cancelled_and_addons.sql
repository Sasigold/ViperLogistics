\pset tuples_only on
\pset format unaligned

-- ===========================================================================
-- 26: מה נספר בכסף — ומה לא (0114).
--
--   * **אירוע שבוטל אינו הכנסה ואינו ספירה.** מאז 0037 הוא יורד מהלו״ז
--     ומלוח השנה; כאן נבדק שהוא יורד גם מכל סכום ומכל מונה. היוצא מן הכלל
--     היחיד הוא `events.funnel`, שכל עניינו ההתפלגות לפי סטטוס — והוא נבדק
--     במפורש כדי שאיש לא "יתקן" אותו בעתיד.
--   * **תוספת המחיר כן נספרת.** ‏0113 הוציאה אותה מ-`task_pricing.price`
--     בכוונה, וכתוצאה מכך היא נעלמה מכל סיכום. עכשיו היא בפנים — כולל תוספת
--     על משימה שטרם תומחרה, וכולל סימן שלילי.
--   * **והשתיים נפגשות:** תוספת על משימה של אירוע מבוטל אינה מחזירה אותו
--     לחשבון.
--
-- החבילה מקימה לקוח, שלושה אירועים ומשימות משלה ואינה נשענת על אף חבילה
-- קודמת. החלון הוא current_date + 420, מעבר ל-410 של 25 ולכל טווח אחר, ולכן
-- כל מספר כאן הוא של השורות האלה בלבד.
-- ===========================================================================

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000026a1', 'c26-admin@vl.test'),
  ('00000000-0000-0000-0000-0000000026a2', 'c26-disp@vl.test');

insert into customers (id, name) values
  ('10000000-0000-0000-0000-00000000026a', 'לקוח 26');

insert into profiles (id, user_id, user_kind, is_admin, full_name, customer_id) values
  ('20000000-0000-0000-0000-0000000026a1', '00000000-0000-0000-0000-0000000026a1',
   'staff', true,  'מנהל מערכת 26', null),
  ('20000000-0000-0000-0000-0000000026a2', '00000000-0000-0000-0000-0000000026a2',
   'staff', false, 'רכז 26', null);

insert into profile_roles (profile_id, role_id)
select '20000000-0000-0000-0000-0000000026a2'::uuid, r.id
  from permission_roles r where r.key = 'dispatcher';

-- הרכז צריך לראות כסף כדי שהבדיקה שלו תבדוק משהו
insert into user_permission_grants (profile_id, permission_key, allowed) values
  ('20000000-0000-0000-0000-0000000026a2', 'pricing.view',    true),
  ('20000000-0000-0000-0000-0000000026a2', 'pricing.revenue', true);

-- שלושה אירועים באותו יום: חי, מבוטל, וחי-בלי-תמחור
insert into events (id, customer_id, event_number, event_date, end_client_name, status_id)
select x.id, '10000000-0000-0000-0000-00000000026a', x.num, current_date + 420,
       'לקוח קצה 26',
       (select id from statuses where entity = 'event' and code = x.code and deleted_at is null)
from (values
  ('30000000-0000-0000-0000-00000000026a'::uuid, 'EV-26-LIVE',   'planned'),
  ('30000000-0000-0000-0000-00000000026b'::uuid, 'EV-26-CANCEL', 'cancelled'),
  ('30000000-0000-0000-0000-00000000026c'::uuid, 'EV-26-BARE',   'planned')
) as x(id, num, code);

-- הטריגר של 0003 כבר ברא הקמה ופירוק לכל אירוע. מוחקים אותן רכות ומקימים
-- משימות מפורשות, כדי שהמונים כאן יהיו של מה שהבדיקה כתבה ולא של ברירת מחדל.
update tasks set deleted_at = now()
 where event_id in ('30000000-0000-0000-0000-00000000026a',
                    '30000000-0000-0000-0000-00000000026b',
                    '30000000-0000-0000-0000-00000000026c');

insert into tasks (id, event_id, customer_id, task_type_id, task_date,
                   onsite_start_time, hours_count, worker_count, status_id)
select x.id, x.eid, '10000000-0000-0000-0000-00000000026a',
       (select id from task_types where code = 'setup' limit 1), current_date + 420,
       '09:00', 4, 2,
       (select id from statuses where entity = 'task' and code = 'draft' and deleted_at is null)
from (values
  ('61000000-0000-0000-0000-000000026001'::uuid, '30000000-0000-0000-0000-00000000026a'::uuid),
  ('61000000-0000-0000-0000-000000026002'::uuid, '30000000-0000-0000-0000-00000000026b'::uuid),
  ('61000000-0000-0000-0000-000000026003'::uuid, '30000000-0000-0000-0000-00000000026c'::uuid)
) as x(id, eid);

-- מחיר ידני, כדי שמנוע התמחור לא יכתוב עליו
insert into task_pricing (task_id, price, is_manual) values
  ('61000000-0000-0000-0000-000000026001', 1000, true),
  ('61000000-0000-0000-0000-000000026002',  700, true);
-- ...ו-...003 נשארת בלי מחיר בכוונה: היא נושאת תוספת יתומה בסעיף 3

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000026a1', false);

-- ===== 1. מבוטל אינו נספר =================================================

\echo '--- מבוטל יורד מהכסף ומהמונים ---'

select t_eq('הכנסות: רק האירוע החי נספר, לא המבוטל',
  ((dashboard_stats(current_date + 420, current_date + 420)) -> 'revenue' ->> 'total')::numeric,
  1000::numeric);

select t_eq('מונה האירועים מדלג על המבוטל',
  ((dashboard_stats(current_date + 420, current_date + 420)) ->> 'events_count')::int, 2);

select t_eq('ומונה המשימות גם הוא',
  ((dashboard_stats(current_date + 420, current_date + 420)) ->> 'tasks_count')::int, 2);

select t_eq('רווחיות לקוחות אינה רואה את המבוטל',
  (select round(sum((e ->> 'revenue')::numeric), 2)
     from jsonb_array_elements(
       (customer_profitability(current_date + 420, current_date + 420, 50)) -> 'rows') e
    where e ->> 'name' = 'לקוח 26'),
  1000::numeric);

select t_eq('רווחיות לפי משימה אינה רואה את המשימה של המבוטל',
  (select count(*) from jsonb_array_elements(
     (task_pnl(current_date + 420, current_date + 420, null, null, 200)) -> 'rows') e
    where e ->> 'event_number' = 'EV-26-CANCEL'), 0::bigint);

select t_eq('ומנוע הדוחות מסכים איתם',
  (select sum((e ->> 'value')::numeric) from jsonb_array_elements(
     (reports_run('{"variant":"query","source":"tasks","measure":"revenue","agg":"sum"}',
                  current_date + 420, current_date + 420)) -> 'rows') e),
  1000::numeric);

-- ...ובכל זאת, המשפך הוא היוצא מן הכלל, וזו הנקודה שלו
select t_eq('אבל משפך האירועים כן סופר אותו — זה כל עניינו',
  (select sum((e ->> 'cnt')::int)::int from jsonb_array_elements(
     (dashboard_sections(array['events.funnel'], current_date + 420, current_date + 420, '{}'))
       -> 'events.funnel') e
    where e ->> 'name' = (select name from statuses
                           where entity = 'event' and code = 'cancelled' and deleted_at is null)),
  1);

-- ===== 2. התוספת נספרת ====================================================

\echo '--- תוספת המחיר נכנסת לסכומים ---'

insert into task_price_addons (task_id, amount, note)
values ('61000000-0000-0000-0000-000000026001', 450, 'המתנה בשער');

select t_eq('תוספת 450 נכנסת לסך ההכנסות',
  ((dashboard_stats(current_date + 420, current_date + 420)) -> 'revenue' ->> 'total')::numeric,
  1450::numeric);

insert into task_price_addons (task_id, amount, note)
values ('61000000-0000-0000-0000-000000026001', -50, 'זיכוי על איחור שלנו');

select t_eq('וסכום שלילי מפחית',
  ((dashboard_stats(current_date + 420, current_date + 420)) -> 'revenue' ->> 'total')::numeric,
  1400::numeric);

-- ===== 3. תוספת על משימה שטרם תומחרה ======================================

insert into task_price_addons (task_id, amount, note)
values ('61000000-0000-0000-0000-000000026003', 200, 'סבלות שלא תוכננה');

select t_eq('תוספת על משימה בלי מחיר אינה נעלמת',
  ((dashboard_stats(current_date + 420, current_date + 420)) -> 'revenue' ->> 'total')::numeric,
  1600::numeric);

-- ...אבל היא אינה הופכת את המשימה ל"מתומחרת": זו שאלה על המחשבון
select t_eq('ובכל זאת המשימה נשארת חסרת תמחור באיכות התמחור',
  ((dashboard_sections(array['pricing.quality'], current_date + 420, current_date + 420, '{}')
      -> 'pricing.quality') ->> 'unpriced')::int, 1);

-- ===== 4. הסרה, והמפגש בין השניים =========================================

update task_price_addons set deleted_at = now()
 where task_id = '61000000-0000-0000-0000-000000026001' and amount = 450;

select t_eq('תוספת שהוסרה יורדת מהחשבון',
  ((dashboard_stats(current_date + 420, current_date + 420)) -> 'revenue' ->> 'total')::numeric,
  1150::numeric);

insert into task_price_addons (task_id, amount, note)
values ('61000000-0000-0000-0000-000000026002', 999, 'תוספת על אירוע שבוטל');

select t_eq('ותוספת על משימה של אירוע מבוטל אינה מחזירה אותו לחשבון',
  ((dashboard_stats(current_date + 420, current_date + 420)) -> 'revenue' ->> 'total')::numeric,
  1150::numeric);

-- ===== 5. וגם לקורא שאינו אדמין ===========================================
--
-- ה-views הם security_invoker, ולכן RLS ממשיכה לחול. אילו נכתבו בלי הדגל,
-- הבדיקה הזו הייתה עוברת בדיוק כמו של האדמין ואיש לא היה מבחין.

\echo '--- אותו חשבון לרכז, דרך RLS ---'

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000026a2', false);

select t_eq('רכז עם מפתחות התמחור מקבל את אותו מספר',
  ((dashboard_stats(current_date + 420, current_date + 420)) -> 'revenue' ->> 'total')::numeric,
  1150::numeric);

reset role;
