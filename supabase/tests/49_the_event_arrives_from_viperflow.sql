\pset tuples_only on
\pset format unaligned

-- ===========================================================================
-- 49: האירוע מגיע מ-ViperFlow — תרגום, אי-כפילות, סדר, ביטול ו-RLS (0176‏–0177).
--
-- החבילה מקימה לקוח, חיבור, ארבעה פרופילים ואירוע משלה ואינה נשענת על אף
-- חבילה קודמת. האירוע יושב ב-2026-10-02 — תאריך קבוע ולא `current_date + N`,
-- במכוון: כל הבדיקה כאן היא על המרת אזור זמן, ותאריך שזז עם היום שבו הבדיקה
-- רצה אינו יכול לאשר שהיא נכונה. היא רצה אחרונה כי היא משאירה אחריה אירוע,
-- משימות, שורות ריהוט ומשלוחים שאינם מנוקים.
-- ===========================================================================

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000049a1', 'vf-admin@vl.test'),
  ('00000000-0000-0000-0000-0000000049a2', 'vf-ops@vl.test'),
  ('00000000-0000-0000-0000-0000000049a3', 'vf-coord@vl.test'),
  ('00000000-0000-0000-0000-0000000049a4', 'vf-worker@vl.test');

insert into customers (id, name) values
  ('10000000-0000-0000-0000-000000000049', 'שיא ריהוט 49');

insert into profiles (id, user_id, user_kind, is_admin, full_name) values
  -- מנהל מערכת: פותח את החיבור
  ('20000000-0000-0000-0000-0000000049a1', '00000000-0000-0000-0000-0000000049a1',
   'staff', true, 'אדמין 49'),
  -- מנהל אינטגרציות: integrations.view + manage
  ('20000000-0000-0000-0000-0000000049a2', '00000000-0000-0000-0000-0000000049a2',
   'staff', false, 'מנהל אינטגרציות 49'),
  -- רכז: רואה אירועים, ואינו רואה את מסך החיבורים
  ('20000000-0000-0000-0000-0000000049a3', '00000000-0000-0000-0000-0000000049a3',
   'staff', false, 'רכז 49'),
  -- עובד שטח: כל מה שיש לו הוא האירוע שהוא רואה, והמפרט שנגזר ממנו (0102)
  ('20000000-0000-0000-0000-0000000049a4', '00000000-0000-0000-0000-0000000049a4',
   'staff', false, 'עובד 49');

insert into user_permission_grants (profile_id, permission_key, allowed) values
  ('20000000-0000-0000-0000-0000000049a2', 'integrations.view', true),
  ('20000000-0000-0000-0000-0000000049a2', 'integrations.manage', true),
  ('20000000-0000-0000-0000-0000000049a3', 'events.view', true),
  ('20000000-0000-0000-0000-0000000049a3', 'integrations.view', false),
  ('20000000-0000-0000-0000-0000000049a4', 'events.view', true),
  ('20000000-0000-0000-0000-0000000049a4', 'events.specs_view', true),
  ('20000000-0000-0000-0000-0000000049a4', 'integrations.view', false);

-- ‏0190: שתי קטגוריות הריהוט מופעלות ללקוח, ובאחוזים שונים. קיום השורה הוא
-- מה שמדליק את הקטגוריה (0068 §3), ובלעדיה האינטגרציה שותקת ואינה כותבת.
insert into customer_income_splits (customer_id, category_id, viper_share_pct)
select '10000000-0000-0000-0000-000000000049', id,
       case name when 'ריהוט ישן' then 70 when 'ריהוט חדש' then 20 else 100 end
  from income_categories where name in ('ריהוט ישן', 'ריהוט חדש', 'הובלות');


\echo '--- 1. החיבור נפתח, ורק בידי מי שמחזיק את המפתח ---'

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000049a3', false);
select t_expect_fail('רכז אינו פותח חיבור',
  $$select viperflow_set_connection('10000000-0000-0000-0000-000000000049', 'ניסיון', true)$$);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000049a2', false);
select t_expect_ok('מנהל אינטגרציות פותח חיבור',
  $$select viperflow_set_connection('10000000-0000-0000-0000-000000000049',
      'שיא ריהוט 49 — ViperFlow', true)$$);
reset role;
select set_config('request.jwt.claim.sub', '', false);

-- המזהה נקרא פעם אחת ונשמר בטבלה זמנית, כדי שכל המעטפות למטה יצביעו עליו.
create temporary table vf49 as
  select id as connection_id from viperflow_connections
   where customer_id = '10000000-0000-0000-0000-000000000049';
-- ‏§12 קורא את הטבלאות האלה אחרי `set role authenticated`, והן שייכות
-- ל-postgres. בלי ההענקה כל בדיקת RLS שם נופלת על "permission denied".
grant select on vf49 to authenticated;

select t_eq('נפתח חיבור אחד', (select count(*)::int from vf49), 1);


\echo '--- 2. הזמנה חדשה נעשית אירוע, ושתי המשימות שלו ---'

-- ‏delivery ב-05:00Z ביום 1/10 היא 08:00 בישראל (IDT, ‏UTC+3), וחיץ של שלוש
-- שעות מוציא מהמחסן ב-05:00 באותו יום עצמו. ‏return ב-07:00Z ביום 3/10 היא
-- 10:00 מקומי.
-- ‏p_discount היא הנחת ההזמנה (0192). ViperFlow שולח אותה בתוך `totals`,
-- ופונקציית הקצה מצמצמת את `totals` אליה בלבד — וכך היא מגיעה לכאן.
create or replace function t49_envelope(p_event_id text, p_updated text, p_type text,
                                        p_status text, p_delivery text, p_return text,
                                        p_items jsonb, p_discount numeric default 0)
returns jsonb language sql immutable as $$
  select jsonb_build_object(
    'id', p_event_id,
    'type', p_type,
    'created_at', p_updated,
    'api_version', 'v1',
    'livemode', true,
    'origin', jsonb_build_object('source', 'app'),
    'data', jsonb_build_object(
      'id', '99999999-4444-4444-4444-000000000049',
      'object', 'order',
      'order_number', 'ORD-49-0001',
      'status', p_status,
      'customer_name', 'משפחת כהן',
      'event', jsonb_build_object('date', '2026-10-02', 'location', 'אולם הדקל, ראשון לציון'),
      'delivery_date', p_delivery,
      'return_date', p_return,
      'buffer_hours', jsonb_build_object('before', 3, 'after', 3),
      'notes', 'הכניסה מאחור',
      -- ‏0190: פונקציית הקצה שאלה את הקטלוג על כל מוצר וסימנה כל שורה. הדגל
      -- הוא "שאלנו", ובלעדיו המתרגם אינו כותב מחירי ריהוט כלל.
      'catalog_enriched', true,
      'totals', jsonb_build_object('order_discount_percent', p_discount),
      'items', p_items,
      'created_at', p_updated,
      'updated_at', p_updated),
    'previous', null);
$$;

-- ‏p_trucks ו-p_workers משתנים כדי ש-§6 תוכל להראות שהכמויות כן חוצות את
-- הגבול בעדכון, בעוד השעות אינן. ‏`line_total` של שתי שורות הלוגיסטיקה נגזר
-- מהכמות, כמו אצלם.
create or replace function t49_items(p_chairs int,
                                     p_trucks int default 2,
                                     p_workers int default 4)
returns jsonb language sql immutable as $$
  select jsonb_build_array(
    -- השולחן **אינו נושא `is_new`**, וזה בכוונה: "מה שאינו מוגדר כציוד חדש
    -- הוא ישן" הוא הכלל, ולא ברירת מחדל שמישהו כותב במפורש (0190 §3).
    jsonb_build_object(
      'id', '11111111-4444-4444-4444-000000000001', 'parent_item_id', null,
      'line_type', 'product', 'is_component', false, 'component_type', null,
      'name', 'שולחן עגול 1.8', 'quantity', 10, 'spare_quantity', 2,
      'is_custom', false, 'notes', null, 'sort_order', 0,
      -- הכסף נשלח, ואינו אמור להגיע לשום מקום *על המשימה*. פונקציית הקצה
      -- משאירה `line_total` בלבד (0190), וממנו נגזרת ההכנסה — לא מחיר.
      'unit_price', 120, 'line_total', 1200, 'discount_percent', 0,
      'options', jsonb_build_array(jsonb_build_object(
        'group_id', null, 'group_name', 'מפה', 'child_id', null, 'value', 'מפה לבנה'))),
    jsonb_build_object(
      'id', '11111111-4444-4444-4444-000000000002',
      'parent_item_id', '11111111-4444-4444-4444-000000000001',
      'line_type', 'product', 'is_component', true, 'component_type', 'choice_group',
      'name', 'מפה לבנה', 'quantity', 10, 'spare_quantity', 0,
      'is_custom', false, 'notes', null, 'sort_order', 1, 'options', '[]'::jsonb),
    -- והכיסאות כן: הקטלוג אמר "ציוד חדש", והסכום שלהם הולך לקטגוריה השנייה.
    jsonb_build_object(
      'id', '11111111-4444-4444-4444-000000000003', 'parent_item_id', null,
      'line_type', 'product', 'is_component', false, 'component_type', null,
      'name', 'כיסא נפוליאון', 'quantity', p_chairs, 'spare_quantity', 0,
      'is_custom', false, 'notes', null, 'sort_order', 2, 'is_new', true,
      'unit_price', 31, 'line_total', p_chairs * 31, 'options', '[]'::jsonb),
    -- שתי שורות הלוגיסטיקה נושאות סכום, וזה הסכום היחיד שהופך ל**מחיר
    -- משימה** (0187): הקמה ופירוק. כסף של ריהוט הולך להכנסות, לא למשימה.
    jsonb_build_object(
      'id', '11111111-4444-4444-4444-000000000004', 'parent_item_id', null,
      'line_type', 'worker', 'is_component', false, 'name', 'סידור ואיסוף',
      'quantity', p_workers, 'spare_quantity', 0, 'is_custom', false, 'sort_order', 3,
      'unit_price', 500, 'line_total', p_workers * 500,
      'options', '[]'::jsonb),
    jsonb_build_object(
      'id', '11111111-4444-4444-4444-000000000005', 'parent_item_id', null,
      'line_type', 'truck', 'is_component', false, 'name', 'הובלה',
      'quantity', p_trucks, 'spare_quantity', 0, 'is_custom', false, 'sort_order', 4,
      'unit_price', 1250, 'line_total', p_trucks * 1250,
      'options', '[]'::jsonb),
    -- ‏0192: שתי שורות שה-`line_type` שלהן נכון ושמן אינו ברשימה. עד 0192
    -- הן נספרו — עובד שלא עולה על המשאית ומשאית שאינה משאית — וזה בדיוק
    -- מה שהסכימה החדשה מפסיקה. הסכומים שלהן גדולים במכוון: אם הן ידלפו
    -- למחיר או לכמות, שום קביעה למטה לא תסתדר.
    jsonb_build_object(
      'id', '11111111-4444-4444-4444-000000000006', 'parent_item_id', null,
      'line_type', 'worker', 'is_component', false, 'name', 'פיקוח הקמה ופירוק',
      'quantity', 9, 'spare_quantity', 0, 'is_custom', false, 'sort_order', 5,
      'unit_price', 777, 'line_total', 6993,
      'options', '[]'::jsonb),
    jsonb_build_object(
      'id', '11111111-4444-4444-4444-000000000007', 'parent_item_id', null,
      'line_type', 'truck', 'is_component', false, 'name', 'תוספת',
      'quantity', 8, 'spare_quantity', 0, 'is_custom', false, 'sort_order', 6,
      'unit_price', 640, 'line_total', 5120,
      'options', '[]'::jsonb));
$$;

select t_eq('המעטפה הראשונה הוחלה',
  (select viperflow_ingest(
     t49_envelope('evt_' || repeat('a', 32), '2026-09-16T08:00:00.000Z',
                  'order.created', 'draft',
                  '2026-10-01T05:00:00.000Z', '2026-10-03T07:00:00.000Z',
                  t49_items(100)),
     jsonb_build_object('connection_id', (select connection_id from vf49))) ->> 'status'),
  'processed');

create temporary table ev49 as
  select event_id from viperflow_links
   where order_id = '99999999-4444-4444-4444-000000000049';
grant select on ev49 to authenticated;

select t_eq('נוצר אירוע אחד', (select count(*)::int from ev49), 1);

select t_eq('שם לקוח הקצה הוא הלקוח של ההזמנה',
  (select end_client_name from events where id = (select event_id from ev49)), 'משפחת כהן');
select t_eq('מספר האירוע הוא מספר ההזמנה',
  (select event_number from events where id = (select event_id from ev49)), 'ORD-49-0001');
select t_eq('תאריך האירוע הוא תאריך ההזמנה',
  (select event_date from events where id = (select event_id from ev49)), '2026-10-02'::date);
select t_eq('המיקום עבר',
  (select location_text from events where id = (select event_id from ev49)),
  'אולם הדקל, ראשון לציון');
select t_eq('כמות המשאיות נגזרה משורת ההובלה',
  (select truck_count from events where id = (select event_id from ev49)), 2);
select t_eq('האירוע נפתח על סטטוס ברירת המחדל',
  (select s.code from events e join statuses s on s.id = e.status_id
    where e.id = (select event_id from ev49)), 'pending');
select t_eq('והאירוע יושב על הלקוח של החיבור',
  (select customer_id from events where id = (select event_id from ev49)),
  '10000000-0000-0000-0000-000000000049'::uuid);


\echo '--- 3. אזור הזמן: UTC נכנס, שעון ישראל יוצא ---'

select t_eq('ההקמה ביום האספקה המקומי',
  (select t.task_date from tasks t join task_types tt on tt.id = t.task_type_id
    where t.event_id = (select event_id from ev49) and tt.code = 'setup'),
  '2026-10-01'::date);
select t_eq('ובשעה המקומית — 05:00Z הן 08:00 בישראל',
  (select t.onsite_start_time from tasks t join task_types tt on tt.id = t.task_type_id
    where t.event_id = (select event_id from ev49) and tt.code = 'setup'),
  '08:00'::time);
-- ‏0187 §1: החיץ של ההזמנה אינו שעת ההגעה למחסן שלנו, והוא אינו נכתב.
select t_eq('שעת ההגעה למחסן אינה מגיעה מ-ViperFlow',
  (select t.warehouse_start_time from tasks t join task_types tt on tt.id = t.task_type_id
    where t.event_id = (select event_id from ev49) and tt.code = 'setup'),
  null::time);
-- ‏0192: ארבעה, לא שלושה-עשר. שורת "פיקוח הקמה ופירוק" נושאת כמות 9 ואותו
-- ‏`line_type`, ושמה אינו ברשימת הצוות — ולכן היא אינה עובד.
select t_eq('כמות העובדים נגזרה משורת "סידור ואיסוף" בלבד',
  (select t.worker_count from tasks t join task_types tt on tt.id = t.task_type_id
    where t.event_id = (select event_id from ev49) and tt.code = 'setup'),
  4);
-- ושתיים, לא עשר: "תוספת" היא `truck` ששמה אינו ברשימת ההובלה.
select t_eq('וכמות המשאיות משורת "הובלה" בלבד',
  (select truck_count from events where id = (select event_id from ev49)), 2);
select t_eq('הפירוק ביום ההחזרה ובשעה שלו',
  (select t.task_date::text || ' ' || t.onsite_start_time::text
     from tasks t join task_types tt on tt.id = t.task_type_id
    where t.event_id = (select event_id from ev49) and tt.code = 'teardown'),
  '2026-10-03 10:00:00');

-- ‏0192: **שורת "סידור ואיסוף"** היא שמתחלקת בין שתי המשימות — היא העבודה,
-- וחציה בהקמה וחציה בפירוק. ‏4 × 500 = 2,000, ולכן 1,000 לכל אחת. ההובלה
-- אינה כאן כלל: היא סעיף הכנסה, ונבדקת ב-§3א.
select t_eq('מחיר ההקמה הוא מחצית מסידור ואיסוף',
  (select tp.price from tasks t join task_types tt on tt.id = t.task_type_id
     join task_pricing tp on tp.task_id = t.id
    where t.event_id = (select event_id from ev49) and tt.code = 'setup'),
  1000::numeric);
select t_eq('והפירוק מקבל את המחצית השנייה',
  (select tp.price from tasks t join task_types tt on tt.id = t.task_type_id
     join task_pricing tp on tp.task_id = t.id
    where t.event_id = (select event_id from ev49) and tt.code = 'teardown'),
  1000::numeric);
-- ידני, ולכן `app.recalc_task_price` אינה דורסת אותו בשינוי השעה הבא.
select t_eq('והוא נעול מפני מנוע התמחור',
  (select bool_and(tp.is_manual) from tasks t join task_pricing tp on tp.task_id = t.id
    where t.event_id = (select event_id from ev49)), true);
-- ההבטחה שלא נשברה: שום סכום אחר מהמעטפה אינו הופך למחיר — לא ההובלה
-- (2,500), לא הפיקוח (6,993) ולא "תוספת" (5,120).
select t_eq('ושום מחיר אחר לא נכתב על משימות האירוע',
  (select count(*)::int from task_pricing tp
     join tasks t on t.id = tp.task_id
    where t.event_id = (select event_id from ev49)
      and tp.price <> 1000), 0);

-- הטריגר של 0003 יוצר הקמה ופירוק בלידה, והסנכרון ממלא אותן. שתיים, לא ארבע.
select t_eq('שתי משימות בלבד — הסנכרון ממלא ואינו מכפיל',
  (select count(*)::int from tasks where event_id = (select event_id from ev49)), 2);


\echo '--- 3א. כסף הריהוט נחתך לפי הקטלוג: ישן וחדש (0190) ---'

-- השולחן (1,200) אינו נושא `is_new` ולכן הוא ישן; הכיסאות (100 × 31 = 3,100)
-- נושאים אותו ולכן הם חדשים. המפה היא רכיב, והיא אינה נספרת פעמיים.
select t_eq('ריהוט ישן קיבל את מה שאינו מוגדר חדש',
  (select ei.amount from event_income ei
     join income_categories ic on ic.id = ei.category_id
    where ei.event_id = (select event_id from ev49) and ic.viperflow_income_source = 'furniture_old'),
  1200::numeric);
select t_eq('וריהוט חדש את מה שכן',
  (select ei.amount from event_income ei
     join income_categories ic on ic.id = ei.category_id
    where ei.event_id = (select event_id from ev49) and ic.viperflow_income_source = 'furniture_new'),
  3100::numeric);
-- האחוז הוא צילום מחלוקת הלקוח ברגע הכתיבה, כמו בכל כתיבת הכנסה (0068 §4).
select t_eq('ואחוז ויפר צולם מחלוקת הלקוח',
  (select ei.viper_share_pct from event_income ei
     join income_categories ic on ic.id = ei.category_id
    where ei.event_id = (select event_id from ev49) and ic.viperflow_income_source = 'furniture_old'),
  70::numeric);
-- ‏0192: ההובלה היא סעיף הכנסה, לא מחיר משימה. ‏2 × 1,250 = 2,500, ובלי
-- "תוספת" (5,120) שגם היא `truck` — ובלי הנחה, שאינה חלה על הובלה.
select t_eq('וההובלה נכתבה לסעיף "הובלות"',
  (select ei.amount from event_income ei
     join income_categories ic on ic.id = ei.category_id
    where ei.event_id = (select event_id from ev49) and ic.viperflow_income_source = 'trucking'),
  2500::numeric);
select t_eq('שלוש שורות הכנסה, ולא אחת לכל שורת ריהוט',
  (select count(*)::int from event_income where event_id = (select event_id from ev49)), 3);
select t_eq('והיומן אומר את שלושת הסכומים',
  (select count(*)::int from event_activity
    where event_id = (select event_id from ev49) and kind = 'synced'
      and note like '%ריהוט ישן 1,200.00 ₪%' and note like '%ריהוט חדש 3,100.00 ₪%'
      and note like '%הובלות 2,500.00 ₪%'), 1);

-- ומעטפה שהקצה לא הספיק להעשיר אינה מנחשת: בלי הדגל אין דעה, ולכן אין
-- כתיבה — לא אפס, ולא מה שהיה קודם.
select t_eq('הזמנה אחרת בלי דגל הקטלוג אינה כותבת הכנסה',
  (select viperflow_ingest(
     jsonb_build_object('id', 'evt_' || repeat('6', 32), 'type', 'order.created',
       'created_at', '2026-09-16T08:10:00.000Z', 'api_version', 'v1', 'livemode', true,
       'origin', jsonb_build_object('source', 'app'),
       'data', jsonb_build_object(
         'id', '99999999-4444-4444-4444-000000000349', 'object', 'order',
         'order_number', 'ORD-49-0009', 'status', 'draft', 'customer_name', 'בלי קטלוג',
         'event', jsonb_build_object('date', '2026-12-01', 'location', 'אולם'),
         'delivery_date', '2026-11-30T05:00:00.000Z',
         'return_date', '2026-12-02T07:00:00.000Z',
         'items', t49_items(5),
         'updated_at', '2026-09-16T08:10:00.000Z'),
       'previous', null),
     jsonb_build_object('connection_id', (select connection_id from vf49))) ->> 'status'),
  'processed');
select t_eq('ואין לה שורת הכנסת ריהוט',
  (select count(*)::int from event_income ei
     join income_categories ic on ic.id = ei.category_id
    where ic.viperflow_income_source in ('furniture_old', 'furniture_new')
      and ei.event_id = (select l.event_id from viperflow_links l
                          where l.order_id = '99999999-4444-4444-4444-000000000349')), 0);
-- אבל ההובלה כן: היא שורת הזמנה ולא שאלה על הקטלוג, ולכן `products:read`
-- אינו תנאי לה. ‏2 × 1,250 גם כאן.
select t_eq('וההובלה כן נכתבת — היא אינה תלויה בקטלוג',
  (select ei.amount from event_income ei
     join income_categories ic on ic.id = ei.category_id
    where ic.viperflow_income_source = 'trucking'
      and ei.event_id = (select l.event_id from viperflow_links l
                          where l.order_id = '99999999-4444-4444-4444-000000000349')),
  2500::numeric);


\echo '--- 4. רשימת הריהוט, ובלי מחירים ---'

select t_eq('שבע שורות נכתבו — הריהוט, הלוגיסטיקה ושתי השורות שאינן נספרות',
  (select count(*)::int from viperflow_order_items where event_id = (select event_id from ev49)), 7);
select t_eq('שתיים מהן ריהוט שאינו רכיב',
  (select count(*)::int from viperflow_order_items
    where event_id = (select event_id from ev49)
      and line_type = 'product' and not is_component), 2);
select t_eq('הרכיב יודע מי האב שלו',
  (select parent_external_item_id from viperflow_order_items
    where event_id = (select event_id from ev49) and name = 'מפה לבנה'),
  '11111111-4444-4444-4444-000000000001'::uuid);
select t_eq('הבחירה נשמרה בשמות בלבד',
  (select options from viperflow_order_items
    where event_id = (select event_id from ev49) and name = 'שולחן עגול 1.8'),
  '[{"group": "מפה", "value": "מפה לבנה"}]'::jsonb);
select t_eq('והספייר נשמר בנפרד מהכמות',
  (select spare_quantity from viperflow_order_items
    where event_id = (select event_id from ev49) and name = 'שולחן עגול 1.8'),
  2::numeric);

-- ההבטחה של 0176 §2 אינה הערה אלא מבנה: אין לאן לכתוב מחיר.
select t_eq('אין בטבלת הריהוט שום עמודה שיכולה להחזיק כסף',
  (select count(*)::int from information_schema.columns
    where table_schema = 'public' and table_name = 'viperflow_order_items'
      and (column_name ~* 'price|total|amount|discount|vat|currency|cost')), 0);


\echo '--- 5. אותה מעטפה פעמיים אינה שני אירועים ---'

select t_eq('משלוח חוזר נענה duplicate',
  (select viperflow_ingest(
     t49_envelope('evt_' || repeat('a', 32), '2026-09-16T08:00:00.000Z',
                  'order.created', 'draft',
                  '2026-10-01T05:00:00.000Z', '2026-10-03T07:00:00.000Z',
                  t49_items(100)),
     jsonb_build_object('connection_id', (select connection_id from vf49))) ->> 'status'),
  'duplicate');
select t_eq('ועדיין אירוע אחד',
  (select count(*)::int from viperflow_links
    where order_id = '99999999-4444-4444-4444-000000000049'), 1);
select t_eq('ושורת משלוח אחת',
  (select count(*)::int from viperflow_deliveries where event_id = 'evt_' || repeat('a', 32)), 1);


\echo '--- 6. עדכון: כמויות ומחירים נכתבים, השאר נאמר בהתראה (0190) ---'

-- ההקמה מסומנת "משובצת" — כלומר עובדים כבר רואים אותה. עד 0190 היא זזה
-- בכל זאת, וזו הייתה התקלה: משימה שזזה בשקט מתחת לרגליים של מי שכבר שובץ
-- אליה אינה סנכרון אלא נזק. מה שההזמנה אומרת על השעה נאמר, ואינו נכתב.
update tasks set status_id = (select id from statuses
                               where entity = 'task' and code = 'assigned' and deleted_at is null)
 where event_id = (select event_id from ev49)
   and task_type_id = (select id from task_types where code = 'setup');

-- והרכז קבע שעת הגעה למחסן (0187 §1)...
update tasks set warehouse_start_time = '05:30'
 where event_id = (select event_id from ev49)
   and task_type_id = (select id from task_types where code = 'setup');

-- ...ואת הכתובת המלאה של האולם, שההזמנה אינה יודעת עליה דבר (0189).
update events set location_text = 'אולם הדקל, החושלים 12 ראשון לציון — שער משאיות'
 where id = (select event_id from ev49);

-- ‏21:00Z ביום 1/10 הן חצות של 2/10 בישראל — שינוי שעה שעד 0190 היה נכתב.
-- שלוש משאיות ושישה עובדים הם מה שכן חוצה את הגבול, יחד עם המחיר שנגזר מהם.
select t_eq('העדכון הוחל',
  (select viperflow_ingest(
     t49_envelope('evt_' || repeat('b', 32), '2026-09-16T09:00:00.000Z',
                  'order.updated', 'confirmed',
                  '2026-10-01T21:00:00.000Z', '2026-10-03T07:00:00.000Z',
                  t49_items(120, 3, 6)),
     jsonb_build_object('connection_id', (select connection_id from vf49))) ->> 'status'),
  'processed');

-- ── שלושת הדברים שכן נכתבים ─────────────────────────────────────────────
select t_eq('כמות המשאיות התעדכנה',
  (select truck_count from events where id = (select event_id from ev49)), 3);
select t_eq('כמות העובדים בהקמה התעדכנה',
  (select t.worker_count from tasks t join task_types tt on tt.id = t.task_type_id
    where t.event_id = (select event_id from ev49) and tt.code = 'setup'), 6);
select t_eq('וגם בפירוק',
  (select t.worker_count from tasks t join task_types tt on tt.id = t.task_type_id
    where t.event_id = (select event_id from ev49) and tt.code = 'teardown'), 6);
-- ‏6 × 500 = 3,000, ומחצית לכל משימה. הפיקוח (6,993) עדיין בחוץ.
select t_eq('והמחיר נגזר מחדש משורת הצוות',
  (select array_agg(distinct tp.price) from tasks t join task_pricing tp on tp.task_id = t.id
    where t.event_id = (select event_id from ev49)),
  array[1500]::numeric[]);
-- ‏3 × 1,250 = 3,750, ובלי "תוספת".
select t_eq('וההובלות התעדכנו לפי שורת ההובלה',
  (select ei.amount from event_income ei
     join income_categories ic on ic.id = ei.category_id
    where ei.event_id = (select event_id from ev49) and ic.viperflow_income_source = 'trucking'),
  3750::numeric);
select t_eq('והכנסות הריהוט התעדכנו עם הכמות החדשה',
  (select ei.amount from event_income ei
     join income_categories ic on ic.id = ei.category_id
    where ei.event_id = (select event_id from ev49) and ic.viperflow_income_source = 'furniture_new'),
  3720::numeric);

-- ── וכל השאר נשאר של מי שקבע אותו ────────────────────────────────────────
select t_eq('ההקמה לא זזה מהיום שהמשרד קבע',
  (select t.task_date from tasks t join task_types tt on tt.id = t.task_type_id
    where t.event_id = (select event_id from ev49) and tt.code = 'setup'),
  '2026-10-01'::date);
select t_eq('ולא מהשעה שלו',
  (select t.onsite_start_time from tasks t join task_types tt on tt.id = t.task_type_id
    where t.event_id = (select event_id from ev49) and tt.code = 'setup'),
  '08:00'::time);
select t_eq('ושעת ההגעה למחסן שהרכז קבע נשארה כפי שהיא',
  (select t.warehouse_start_time from tasks t join task_types tt on tt.id = t.task_type_id
    where t.event_id = (select event_id from ev49) and tt.code = 'setup'),
  '05:30'::time);
select t_eq('והפירוק אף הוא לא זז',
  (select t.task_date::text || ' ' || t.onsite_start_time::text
     from tasks t join task_types tt on tt.id = t.task_type_id
    where t.event_id = (select event_id from ev49) and tt.code = 'teardown'),
  '2026-10-03 10:00:00');
select t_eq('והמיקום שהרכז השלים לא נדרס',
  (select location_text from events where id = (select event_id from ev49)),
  'אולם הדקל, החושלים 12 ראשון לציון — שער משאיות');
select t_eq('אישור ההזמנה קידם את האירוע',
  (select s.code from events e join statuses s on s.id = e.status_id
    where e.id = (select event_id from ev49)), 'approved');
select t_eq('הריהוט הוחלף ולא נערם',
  (select count(*)::int from viperflow_order_items where event_id = (select event_id from ev49)), 7);
select t_eq('והכמות המעודכנת היא שנשמרה',
  (select quantity from viperflow_order_items
    where event_id = (select event_id from ev49) and name = 'כיסא נפוליאון'), 120::numeric);


\echo '--- 6א. ומה שלא נכתב — נאמר ---'

-- ההשוואה היא בין שני צילומי הזמנה ולא בין ההזמנה לאירוע (0190 §3): אחרת
-- כל סנכרון היה מדווח מחדש על אותו פער שהרכז יצר בכוונה.
select t_eq('יצאה התראה אחת למנהל המערכת',
  (select count(*)::int from notifications
    where recipient_id = '20000000-0000-0000-0000-0000000049a1'
      and type = 'viperflow_order_changed'), 1);
select t_eq('והיא תלויה באירוע עצמו',
  (select entity_id from notifications
    where recipient_id = '20000000-0000-0000-0000-0000000049a1'
      and type = 'viperflow_order_changed'),
  (select event_id from ev49));

create temporary table n49 as
  select body from notifications
   where recipient_id = '20000000-0000-0000-0000-0000000049a1'
     and type = 'viperflow_order_changed';

-- מפרט שהשתנה נאמר במילה אחת: מאה שורות אינן נכנסות לגוף התראה.
select t_eq('המפרט נאמר כ"השתנה מפרט" ולא כרשימה',
  (select body like '%השתנה מפרט%' and body not like '%כיסא נפוליאון%' from n49), true);
select t_eq('והשעה שזזה מפורטת — מה שהיה ומה שעכשיו',
  (select body like '%ההקמה: 02/10/2026 00:00 (היה 01/10/2026 08:00)%' from n49), true);
select t_eq('וכמות המשאיות',
  (select body like '%כמות משאיות: 3 (היה 2)%' from n49), true);
select t_eq('וכמות העובדים',
  (select body like '%כמות עובדים: 6 (היה 4)%' from n49), true);
select t_eq('ומחיר ההקמה והפירוק בשקלים',
  (select body like '%מחיר הקמה ופירוק: 3,000.00 ₪ (היה 2,000.00 ₪)%' from n49), true);
select t_eq('וההובלות בנפרד ממנו',
  (select body like '%הובלות: 3,750.00 ₪ (היה 2,500.00 ₪)%' from n49), true);
select t_eq('והסטטוס בעברית, ולא בקוד שלהם',
  (select body like '%סטטוס ההזמנה: מאושרת (היה טיוטה)%' from n49), true);
select t_eq('והכנסת הריהוט החדש',
  (select body like '%ריהוט חדש: 3,720.00 ₪ (היה 3,100.00 ₪)%' from n49), true);
-- מה שלא השתנה אינו מופיע: האולם, שם הלקוח, תאריך האירוע והריהוט הישן.
select t_eq('ומה שלא השתנה אינו בהתראה',
  (select body not like '%האולם%' and body not like '%הלקוח הסופי%'
      and body not like '%תאריך האירוע%' and body not like '%ריהוט ישן%'
      and body not like '%הנחת ההזמנה%' from n49), true);
select t_eq('והשם של מי שהשתנה אצלו נמצא בגוף',
  (select body like 'שיא ריהוט 49 · הזמנה ORD-49-0001 —%' from n49), true);
-- אותן שורות בדיוק נכנסות גם ליומן האירוע, ולא רק להתראה.
select t_eq('ואותן שורות נכתבו ביומן',
  (select count(*)::int from event_activity
    where event_id = (select event_id from ev49) and kind = 'synced'
      and note like '%השתנה מפרט%' and note like '%כמות משאיות: 3 (היה 2)%'), 1);

drop table n49;


\echo '--- 7. משלוח ישן אינו דורס חדש ---'

select t_eq('מעטפה עם חותמת ישנה נדחית כ-stale',
  (select viperflow_ingest(
     t49_envelope('evt_' || repeat('c', 32), '2026-09-16T08:30:00.000Z',
                  'order.updated', 'confirmed',
                  '2026-10-05T05:00:00.000Z', '2026-10-07T07:00:00.000Z',
                  t49_items(1)),
     jsonb_build_object('connection_id', (select connection_id from vf49))) ->> 'status'),
  'stale');
-- הכמות היא העד: מאז 0190 התאריך אינו זז בעדכון בכלל, ולכן תאריך שלא זז
-- כבר אינו מעיד על כלום. מה שמעיד הוא הריהוט, שכן נכתב בכל החלה.
select t_eq('הכמות לא חזרה אחורה',
  (select quantity from viperflow_order_items
    where event_id = (select event_id from ev49) and name = 'כיסא נפוליאון'), 120::numeric);
select t_eq('וכמות המשאיות לא חזרה אחורה',
  (select truck_count from events where id = (select event_id from ev49)), 3);
select t_eq('והמשלוח נרשם כלא-רלוונטי ולא כנכשל',
  (select status from viperflow_deliveries where event_id = 'evt_' || repeat('c', 32)), 'ignored');
-- מעטפה שנעצרה בשומר לא הגיעה עד ההשוואה, ולכן גם לא עד ההתראה.
select t_eq('ומעטפה שנדחתה אינה מקפיצה התראה',
  (select count(*)::int from notifications
    where recipient_id = '20000000-0000-0000-0000-0000000049a1'
      and type = 'viperflow_order_changed'), 1);


\echo '--- 7א. ו-force עובר גם את השומר וגם את האי-כפילות ---'

-- אותו evt_ בדיוק כמו ב-§7, ואותה חותמת ישנה. בלי force הוא כבר נענה
-- 'stale'; עם force הוא מוחל, כי זה הכלי של מי שאומר "המצב אצלנו שגוי".
select t_eq('אותה מעטפה עם force מוחלת',
  (select viperflow_ingest(
     t49_envelope('evt_' || repeat('c', 32), '2026-09-16T08:30:00.000Z',
                  'order.updated', 'confirmed',
                  '2026-10-05T05:00:00.000Z', '2026-10-07T07:00:00.000Z',
                  t49_items(7)),
     jsonb_build_object('connection_id', (select connection_id from vf49),
                        'force', true)) ->> 'status'),
  'processed');
select t_eq('והריהוט הוחלף',
  (select quantity from viperflow_order_items
    where event_id = (select event_id from ev49) and name = 'כיסא נפוליאון'), 7::numeric);
select t_eq('וכמות המשאיות חזרה לשתיים',
  (select truck_count from events where id = (select event_id from ev49)), 2);
select t_eq('והמחיר חזר למחצית של 2,000',
  (select array_agg(distinct tp.price) from tasks t join task_pricing tp on tp.task_id = t.id
    where t.event_id = (select event_id from ev49)),
  array[1000]::numeric[]);
-- ‏force עוקף את השומר ואת האי-כפילות, ואינו עוקף את הבעלות: הוא אומר
-- "המצב אצלנו שגוי", והמצב שיכול להיות שגוי הוא מה שאנחנו כותבים. השעה
-- אינה כזו מאז 0190 — היא של המשרד, ו-force אינו מנהל.
select t_eq('ו-force אינו מזיז את ההקמה — היא כבר לא שלהם',
  (select t.task_date from tasks t join task_types tt on tt.id = t.task_type_id
    where t.event_id = (select event_id from ev49) and tt.code = 'setup'),
  '2026-10-01'::date);
select t_eq('אבל הוא כן מקפיץ התראה, כי ההזמנה אכן השתנתה',
  (select count(*)::int from notifications
    where recipient_id = '20000000-0000-0000-0000-0000000049a1'
      and type = 'viperflow_order_changed'), 2);
select t_eq('ושורת המשלוח נכתבה מחדש ולא הוכפלה',
  (select count(*)::int from viperflow_deliveries where event_id = 'evt_' || repeat('c', 32)), 1);

-- ומחזירים את המצב למה שהיה, כדי ש-§11 תבטל את האירוע האמיתי.
select t_eq('והמצב הוחזר לקראת §8',
  (select viperflow_ingest(
     t49_envelope('evt_' || repeat('7', 32), '2026-09-16T09:30:00.000Z',
                  'order.updated', 'confirmed',
                  '2026-10-01T21:00:00.000Z', '2026-10-03T07:00:00.000Z',
                  t49_items(120)),
     jsonb_build_object('connection_id', (select connection_id from vf49))) ->> 'status'),
  'processed');


\echo '--- 8. היומן אומר מי הזיז, גם כשאיש לא לחץ ---'

select t_eq('נכתבה שורת סנכרון לכל החלה',
  (select count(*)::int from event_activity
    where event_id = (select event_id from ev49) and kind = 'synced'), 4);
select t_eq('והכותב הוא ViperFlow',
  (select distinct actor_name from event_activity
    where event_id = (select event_id from ev49) and kind = 'synced'), 'ViperFlow');
select t_eq('גם שינוי השדה האוטומטי נושא את השם',
  (select actor_name from event_activity
    where event_id = (select event_id from ev49) and kind = 'changed'
      and field_key = 'status_id' limit 1), 'ViperFlow');


\echo '--- 9. סוג אירוע שאינו מתורגם נרשם ואינו מתורגם ---'

select t_eq('אירוע בדיקה נבלע',
  (select viperflow_ingest(
     jsonb_build_object('id', 'evt_' || repeat('d', 32), 'type', 'webhook.test',
                        'created_at', '2026-09-16T10:00:00.000Z', 'api_version', 'v1',
                        'livemode', true, 'origin', jsonb_build_object('source', 'system'),
                        'data', jsonb_build_object('message', 'ViperFlow webhook test'),
                        'previous', null),
     jsonb_build_object('connection_id', (select connection_id from vf49))) ->> 'status'),
  'ignored');

select t_eq('לקוח שנוצר אצלם אינו עניינו של הלו״ז',
  (select viperflow_ingest(
     jsonb_build_object('id', 'evt_' || repeat('e', 32), 'type', 'customer.created',
                        'created_at', '2026-09-16T10:05:00.000Z', 'api_version', 'v1',
                        'livemode', true, 'origin', jsonb_build_object('source', 'app'),
                        'data', jsonb_build_object('id', gen_random_uuid(), 'object', 'customer'),
                        'previous', null),
     jsonb_build_object('connection_id', (select connection_id from vf49))) ->> 'status'),
  'ignored');

select t_expect_fail('מעטפה בלי מזהה תקין נדחית',
  $$select viperflow_ingest('{"id":"evt_bad","type":"order.updated"}'::jsonb)$$);


\echo '--- 10. מעטפה שנפלה נרשמת, ואפשר להריץ אותה מחדש ---'

-- הזמנה בלי תאריך אירוע היא בדיוק המקרה שהמתרגם אינו יודע לעכל.
select t_eq('מעטפה פגומה עסקית מסתיימת ב-failed ולא בחריגה',
  (select viperflow_ingest(
     jsonb_build_object('id', 'evt_' || repeat('f', 32), 'type', 'order.updated',
       'created_at', '2026-09-16T11:00:00.000Z', 'api_version', 'v1', 'livemode', true,
       'origin', jsonb_build_object('source', 'app'),
       'data', jsonb_build_object(
         'id', '99999999-4444-4444-4444-000000000149', 'object', 'order',
         'order_number', 'ORD-49-0002', 'status', 'draft',
         'event', jsonb_build_object('date', null, 'location', null),
         'updated_at', '2026-09-16T11:00:00.000Z'),
       'previous', null),
     jsonb_build_object('connection_id', (select connection_id from vf49))) ->> 'status'),
  'failed');

select t_eq('והשורה ממתינה עם סיבה',
  (select status from viperflow_deliveries where event_id = 'evt_' || repeat('f', 32)), 'failed');

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000049a3', false);
select t_expect_fail('רכז אינו מריץ מחדש',
  $$select viperflow_replay((select id from viperflow_deliveries
                              where event_id = 'evt_' || repeat('f', 32)))$$);
reset role;
select set_config('request.jwt.claim.sub', '', false);


\echo '--- 11. ביטול ב-ViperFlow מבטל את האירוע ---'

select t_eq('הביטול הוחל',
  (select viperflow_ingest(
     t49_envelope('evt_' || repeat('1', 32), '2026-09-16T12:00:00.000Z',
                  'order.cancelled', 'cancelled',
                  '2026-10-01T21:00:00.000Z', '2026-10-03T07:00:00.000Z',
                  t49_items(120)),
     jsonb_build_object('connection_id', (select connection_id from vf49))) ->> 'status'),
  'processed');
select t_eq('והאירוע מבוטל',
  (select s.code from events e join statuses s on s.id = e.status_id
    where e.id = (select event_id from ev49)), 'cancelled');


\echo '--- 11א. מחיקה שהגיעה לפני הלידה אינה מייצרת אירוע רפאים ---'

-- הזמנה אחרת, שלא נראתה כאן מעולם: קודם נמחקת, ואז ה-`order.created` שלה
-- מגיע באיחור. סדר כזה אפשרי — at-least-once בלי הבטחת סדר.
select t_eq('מחיקה של הזמנה שאינה מקושרת נרשמת ואינה עושה דבר',
  (select viperflow_ingest(
     jsonb_build_object('id', 'evt_' || repeat('2', 32), 'type', 'order.deleted',
       'created_at', '2026-09-16T13:00:00.000Z', 'api_version', 'v1', 'livemode', true,
       'origin', jsonb_build_object('source', 'app'),
       'data', jsonb_build_object(
         'id', '99999999-4444-4444-4444-000000000249', 'object', 'order',
         'order_number', 'ORD-49-0003', 'status', 'draft', 'deleted', true,
         'updated_at', '2026-09-16T13:00:00.000Z'),
       'previous', null),
     jsonb_build_object('connection_id', (select connection_id from vf49))) ->> 'status'),
  'ignored');

select t_eq('והלידה שהגיעה אחריה אינה יוצרת אירוע',
  (select viperflow_ingest(
     jsonb_build_object('id', 'evt_' || repeat('3', 32), 'type', 'order.created',
       'created_at', '2026-09-16T12:00:00.000Z', 'api_version', 'v1', 'livemode', true,
       'origin', jsonb_build_object('source', 'app'),
       'data', jsonb_build_object(
         'id', '99999999-4444-4444-4444-000000000249', 'object', 'order',
         'order_number', 'ORD-49-0003', 'status', 'draft', 'customer_name', 'רפאים',
         'event', jsonb_build_object('date', '2026-11-11', 'location', 'אולם'),
         'delivery_date', '2026-11-10T05:00:00.000Z',
         'return_date', '2026-11-12T07:00:00.000Z',
         'items', '[]'::jsonb,
         'updated_at', '2026-09-16T12:00:00.000Z'),
       'previous', null),
     jsonb_build_object('connection_id', (select connection_id from vf49))) ->> 'status'),
  'ignored');

select t_eq('לא נולד קישור להזמנה המתה',
  (select count(*)::int from viperflow_links
    where order_id = '99999999-4444-4444-4444-000000000249'), 0);
select t_eq('ולא נולד אירוע בשם הלקוח שלה',
  (select count(*)::int from events where end_client_name = 'רפאים'), 0);


\echo '--- 12. מי רואה מה ---'

set role authenticated;

-- מנהל האינטגרציות: החיבור והמשלוחים
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000049a2', false);
select t_eq('מנהל אינטגרציות רואה את החיבור',
  (select count(*)::int from viperflow_connections), 1);
select t_eq('ורואה משלוחים',
  (select count(*)::int > 0 from viperflow_deliveries), true);

-- הרכז: אירועים כן, מסך החיבורים לא
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000049a3', false);
select t_eq('רכז אינו רואה את החיבור',
  (select count(*)::int from viperflow_connections), 0);
select t_eq('ואינו רואה את המשלוחים',
  (select count(*)::int from viperflow_deliveries), 0);
select t_eq('אבל כן רואה שהאירוע הגיע מ-ViperFlow',
  (select count(*)::int from viperflow_links where event_id = (select event_id from ev49)), 1);

-- עובד השטח: הריהוט הוא המפרט, ולכן הוא שלו (0102 → 0176)
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000049a4', false);
select t_eq('עובד שרואה את האירוע רואה את רשימת הריהוט שלו',
  (select count(*)::int from viperflow_order_items where event_id = (select event_id from ev49)), 7);
select t_eq('ואת מספר ההזמנה דרך ה-view',
  (select order_number from viperflow_event_link where event_id = (select event_id from ev49)),
  'ORD-49-0001');
select t_eq('וה-view סופר לו את שורות הריהוט',
  (select furniture_lines from viperflow_event_link where event_id = (select event_id from ev49)), 2::bigint);
-- ‏0193: אותה ספירה של המתרגם, גם לעובד שאינו רואה את מסך החיבורים.
-- לפי `line_type` בלבד זה היה 10 משאיות ו-13 עובדים — "תוספת" (8) ושורת
-- הפיקוח (9) נמצאות בהזמנה, ואינן ברשימת השמות.
select t_eq('ואת הכמויות לפי רשימת השמות, ולא לפי line_type',
  (select truck_quantity::int::text || '/' || worker_quantity::int::text
     from viperflow_event_link where event_id = (select event_id from ev49)), '2/4');
select t_eq('אך אינו רואה את מסך החיבורים',
  (select count(*)::int from viperflow_connections), 0);

-- ומי שאין לו את מפתח המפרט אינו רואה ריהוט, גם כשהאירוע פתוח לו
reset role;
select set_config('request.jwt.claim.sub', '', false);
insert into user_permission_grants (profile_id, permission_key, allowed) values
  ('20000000-0000-0000-0000-0000000049a3', 'events.specs_view', false)
on conflict (profile_id, permission_key) do update set allowed = false;

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000049a3', false);
select t_eq('שלילת מפתח המפרט סוגרת גם את הריהוט',
  (select count(*)::int from viperflow_order_items where event_id = (select event_id from ev49)), 0);

-- והכתיבה סגורה לכולם: אין פוליסת insert על אף אחת מארבע הטבלאות
select t_expect_fail('מנהל אינטגרציות אינו כותב שורת ריהוט בעצמו',
  $$insert into viperflow_order_items (event_id, connection_id, line_type, name, position)
    values ((select event_id from ev49), (select connection_id from vf49), 'product', 'זיוף', 99)$$);

-- הדלת האחורית — קריאה ישירה ל-`app.viperflow_apply_*` — סגורה ב-revoke
-- ב-0177 §6א, ו**אי אפשר לאשר את זה כאן**: ‏`01_seed.sql:9` מריץ
-- `grant execute on all functions in schema public, app to authenticated`
-- כדי לחקות את ברירת המחדל של Supabase, והוא רץ *אחרי* המיגרציות — ולכן הוא
-- מבטל בחבילת הבדיקות כל revoke מ-authenticated, כולל אלה של 0044, 0052
-- ו-0068. מה שכן נבדק כאן הוא הדלת הקדמית, ששם השער אינו הרשאת EXECUTE אלא
-- המפתח שבתוך הפונקציה.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000049a3', false);
select t_expect_fail('רכז אינו מזרים מעטפות',
  $$select viperflow_ingest('{"id":"evt_00000000000000000000000000000099","type":"webhook.test"}'::jsonb)$$);

reset role;
select set_config('request.jwt.claim.sub', '', false);

\echo '--- 13. ההנחה, שינוי מפרט בלבד, והמתג שמכבה מחיר ---'

-- ‏0192: הנחת ההזמנה חלה על הריהוט בלבד. ‏25% על 1,200 ועל 3,720 (120
-- כיסאות) — וההובלה והצוות אינם זזים, כי ההנחה אינה נוגעת בהם.
select t_eq('הוחל עם הנחת הזמנה',
  (select viperflow_ingest(
     t49_envelope('evt_' || repeat('4', 32), '2026-09-16T14:00:00.000Z',
                  'order.updated', 'confirmed',
                  '2026-10-01T21:00:00.000Z', '2026-10-03T07:00:00.000Z',
                  t49_items(120), 25),
     jsonb_build_object('connection_id', (select connection_id from vf49))) ->> 'status'),
  'processed');

select t_eq('ריהוט ישן נכתב אחרי ההנחה',
  (select ei.amount from event_income ei
     join income_categories ic on ic.id = ei.category_id
    where ei.event_id = (select event_id from ev49) and ic.viperflow_income_source = 'furniture_old'),
  900::numeric);
select t_eq('וריהוט חדש אחריה',
  (select ei.amount from event_income ei
     join income_categories ic on ic.id = ei.category_id
    where ei.event_id = (select event_id from ev49) and ic.viperflow_income_source = 'furniture_new'),
  2790::numeric);
-- ‏2 × 1,250 = 2,500 במלואם: הנחת ההזמנה אינה חלה על ההובלה, וכך זה אצלם.
select t_eq('וההובלות נשארו מלאות — ההנחה אינה נוגעת בהן',
  (select ei.amount from event_income ei
     join income_categories ic on ic.id = ei.category_id
    where ei.event_id = (select event_id from ev49) and ic.viperflow_income_source = 'trucking'),
  2500::numeric);
-- ‏4 × 500 = 2,000, מחצית לכל משימה — גם הוא בלי הנחה.
select t_eq('וגם מחיר המשימה לא הונח',
  (select array_agg(distinct tp.price) from tasks t join task_pricing tp on tp.task_id = t.id
    where t.event_id = (select event_id from ev49)),
  array[1000]::numeric[]);
select t_eq('וההתראה אומרת שההנחה השתנתה',
  (select count(*)::int from notifications
    where recipient_id = '20000000-0000-0000-0000-0000000049a1'
      and type = 'viperflow_order_changed'
      and body like '%הנחת ההזמנה: 25% (היה 0%)%'), 1);


\echo '--- 13א. שינוי במפרט בלבד מעדכן את הכסף ---'

-- ‏ViperFlow מעלה `orders.updated_at` בכל שינוי בשורות ההזמנה ופולט
-- `order.updated` (‏`integrations.touch_and_emit`), ולכן שינוי מפרט מגיע
-- כמו כל עדכון אחר. מה שנבדק כאן: הכסף באמת נגזר מחדש, ולא רק ברגע הלידה.
-- אותם תאריכים, אותה הנחה, אותה לוגיסטיקה — רק הכמות בכיסאות זזה.
select t_eq('הוחל שינוי מפרט בלבד',
  (select viperflow_ingest(
     t49_envelope('evt_' || repeat('8', 32), '2026-09-16T14:30:00.000Z',
                  'order.updated', 'confirmed',
                  '2026-10-01T21:00:00.000Z', '2026-10-03T07:00:00.000Z',
                  t49_items(200), 25),
     jsonb_build_object('connection_id', (select connection_id from vf49))) ->> 'status'),
  'processed');

-- ‏200 × 31 = 6,200, פחות 25% = 4,650.
select t_eq('הכנסת הריהוט החדש נגזרה מחדש מהמפרט',
  (select ei.amount from event_income ei
     join income_categories ic on ic.id = ei.category_id
    where ei.event_id = (select event_id from ev49) and ic.viperflow_income_source = 'furniture_new'),
  4650::numeric);
select t_eq('והישן לא זז — השולחן לא השתנה',
  (select ei.amount from event_income ei
     join income_categories ic on ic.id = ei.category_id
    where ei.event_id = (select event_id from ev49) and ic.viperflow_income_source = 'furniture_old'),
  900::numeric);
select t_eq('וההתראה אומרת גם "השתנה מפרט" וגם את הסכום',
  (select count(*)::int from notifications
    where recipient_id = '20000000-0000-0000-0000-0000000049a1'
      and type = 'viperflow_order_changed'
      and body like '%השתנה מפרט%'
      and body like '%ריהוט חדש: 4,650.00 ₪ (היה 2,790.00 ₪)%'), 1);


\echo '--- 13ב. והמתג שמכבה את מחיר המשימה ---'

update viperflow_connections set logistics_price_source = 'none'
 where id = (select connection_id from vf49);

select t_eq('הוחל עם סנכרון מחיר כבוי',
  (select viperflow_ingest(
     t49_envelope('evt_' || repeat('5', 32), '2026-09-16T15:00:00.000Z',
                  'order.updated', 'confirmed',
                  '2026-10-01T21:00:00.000Z', '2026-10-03T07:00:00.000Z',
                  t49_items(120), 25),
     jsonb_build_object('connection_id', (select connection_id from vf49))) ->> 'status'),
  'processed');
-- כיבוי אינו מחיקה: מחיר שכבר נכתב הוא מספר שהמשרד עובד לפיו, ושינוי של
-- הגדרה אינו מוחק אותו. הוא פשוט מפסיק להתעדכן.
select t_eq('המחיר שכבר נכתב נשאר, ואינו מתאפס',
  (select array_agg(distinct tp.price) from tasks t join task_pricing tp on tp.task_id = t.id
    where t.event_id = (select event_id from ev49)),
  array[1000]::numeric[]);
-- ההכנסות אינן תלויות במתג הזה — הוא על מחיר המשימה בלבד.
select t_eq('וההובלות ממשיכות להתעדכן',
  (select ei.amount from event_income ei
     join income_categories ic on ic.id = ei.category_id
    where ei.event_id = (select event_id from ev49) and ic.viperflow_income_source = 'trucking'),
  2500::numeric);

update viperflow_connections set logistics_price_source = 'crew'
 where id = (select connection_id from vf49);


\echo '--- 13ג. שם שאינו ברשימה אינו נספר, וריק אינו מתקבל ---'

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000049a2', false);
select t_expect_fail('רשימת שמות ריקה נדחית — היא משתיקה כסף בשקט',
  $$select viperflow_set_connection('10000000-0000-0000-0000-000000000049',
      'שיא ריהוט 49 — ViperFlow', true, null,
      (select connection_id from vf49), null, array['  ']::text[])$$);
select t_expect_ok('ושם נוסף לרשימה מתקבל',
  $$select viperflow_set_connection('10000000-0000-0000-0000-000000000049',
      'שיא ריהוט 49 — ViperFlow', true, null,
      (select connection_id from vf49), null, array['הובלה', 'תוספת'])$$);
reset role;
select set_config('request.jwt.claim.sub', '', false);

-- ומעכשיו "תוספת" כן נספרת: ‏2 + 8 = 10 משאיות, ו-2,500 + 5,120 = 7,620.
select t_eq('הוחל אחרי שהשם נוסף',
  (select viperflow_ingest(
     t49_envelope('evt_' || repeat('9', 32), '2026-09-16T16:00:00.000Z',
                  'order.updated', 'confirmed',
                  '2026-10-01T21:00:00.000Z', '2026-10-03T07:00:00.000Z',
                  t49_items(120), 25),
     jsonb_build_object('connection_id', (select connection_id from vf49))) ->> 'status'),
  'processed');
select t_eq('הרשימה היא שקובעת, ולא הקוד',
  (select truck_count from events where id = (select event_id from ev49)), 10);
select t_eq('וגם הסכום',
  (select ei.amount from event_income ei
     join income_categories ic on ic.id = ei.category_id
    where ei.event_id = (select event_id from ev49) and ic.viperflow_income_source = 'trucking'),
  7620::numeric);


drop function t49_envelope(text, text, text, text, text, text, jsonb, numeric);
drop function t49_items(int, int, int);
