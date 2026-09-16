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
create or replace function t49_envelope(p_event_id text, p_updated text, p_type text,
                                        p_status text, p_delivery text, p_return text,
                                        p_items jsonb)
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
      'items', p_items,
      'created_at', p_updated,
      'updated_at', p_updated),
    'previous', null);
$$;

create or replace function t49_items(p_chairs int)
returns jsonb language sql immutable as $$
  select jsonb_build_array(
    jsonb_build_object(
      'id', '11111111-4444-4444-4444-000000000001', 'parent_item_id', null,
      'line_type', 'product', 'is_component', false, 'component_type', null,
      'name', 'שולחן עגול 1.8', 'quantity', 10, 'spare_quantity', 2,
      'is_custom', false, 'notes', null, 'sort_order', 0,
      -- הכסף נשלח, ואינו אמור להגיע לשום מקום. פונקציית הקצה מנקה אותו,
      -- והמתרגם אינו קורא אותו — כאן הוא נשאר במכוון כדי לבדוק את השני.
      'unit_price', 120, 'line_total', 1200, 'discount_percent', 0,
      'options', jsonb_build_array(jsonb_build_object(
        'group_id', null, 'group_name', 'מפה', 'child_id', null, 'value', 'מפה לבנה'))),
    jsonb_build_object(
      'id', '11111111-4444-4444-4444-000000000002',
      'parent_item_id', '11111111-4444-4444-4444-000000000001',
      'line_type', 'product', 'is_component', true, 'component_type', 'choice_group',
      'name', 'מפה לבנה', 'quantity', 10, 'spare_quantity', 0,
      'is_custom', false, 'notes', null, 'sort_order', 1, 'options', '[]'::jsonb),
    jsonb_build_object(
      'id', '11111111-4444-4444-4444-000000000003', 'parent_item_id', null,
      'line_type', 'product', 'is_component', false, 'component_type', null,
      'name', 'כיסא נפוליאון', 'quantity', p_chairs, 'spare_quantity', 0,
      'is_custom', false, 'notes', null, 'sort_order', 2, 'options', '[]'::jsonb),
    jsonb_build_object(
      'id', '11111111-4444-4444-4444-000000000004', 'parent_item_id', null,
      'line_type', 'worker', 'is_component', false, 'name', 'סידור ואיסוף',
      'quantity', 4, 'spare_quantity', 0, 'is_custom', false, 'sort_order', 3,
      'options', '[]'::jsonb),
    jsonb_build_object(
      'id', '11111111-4444-4444-4444-000000000005', 'parent_item_id', null,
      'line_type', 'truck', 'is_component', false, 'name', 'הובלה',
      'quantity', 2, 'spare_quantity', 0, 'is_custom', false, 'sort_order', 4,
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
select t_eq('היציאה מהמחסן היא שלוש שעות החיץ',
  (select t.warehouse_start_time from tasks t join task_types tt on tt.id = t.task_type_id
    where t.event_id = (select event_id from ev49) and tt.code = 'setup'),
  '05:00'::time);
select t_eq('כמות העובדים נגזרה משורת "סידור ואיסוף"',
  (select t.worker_count from tasks t join task_types tt on tt.id = t.task_type_id
    where t.event_id = (select event_id from ev49) and tt.code = 'setup'),
  4);
select t_eq('הפירוק ביום ההחזרה ובשעה שלו',
  (select t.task_date::text || ' ' || t.onsite_start_time::text
     from tasks t join task_types tt on tt.id = t.task_type_id
    where t.event_id = (select event_id from ev49) and tt.code = 'teardown'),
  '2026-10-03 10:00:00');

-- הטריגר של 0003 יוצר הקמה ופירוק בלידה, והסנכרון ממלא אותן. שתיים, לא ארבע.
select t_eq('שתי משימות בלבד — הסנכרון ממלא ואינו מכפיל',
  (select count(*)::int from tasks where event_id = (select event_id from ev49)), 2);


\echo '--- 4. רשימת הריהוט, ובלי מחירים ---'

select t_eq('חמש שורות נכתבו — הריהוט והלוגיסטיקה',
  (select count(*)::int from viperflow_order_items where event_id = (select event_id from ev49)), 5);
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


\echo '--- 6. עדכון מזיז את השעות, גם כשהמשימה כבר פורסמה ---'

-- ההקמה מסומנת "משובצת" — כלומר עובדים כבר רואים אותה. היא זזה בכל זאת:
-- משימה שאינה זזה בשקט היא משאית שמגיעה ליום הלא נכון (0177 §4).
update tasks set status_id = (select id from statuses
                               where entity = 'task' and code = 'assigned' and deleted_at is null)
 where event_id = (select event_id from ev49)
   and task_type_id = (select id from task_types where code = 'setup');

-- ‏21:00Z ביום 1/10 הן חצות של 2/10 בישראל, והחיץ מוציא מהמחסן ביום הקודם —
-- ולכן שעת היציאה אינה נכתבת, ונשארת מה שהייתה.
select t_eq('העדכון הוחל',
  (select viperflow_ingest(
     t49_envelope('evt_' || repeat('b', 32), '2026-09-16T09:00:00.000Z',
                  'order.updated', 'confirmed',
                  '2026-10-01T21:00:00.000Z', '2026-10-03T07:00:00.000Z',
                  t49_items(120)),
     jsonb_build_object('connection_id', (select connection_id from vf49))) ->> 'status'),
  'processed');

select t_eq('ההקמה זזה ליום שאחריו',
  (select t.task_date from tasks t join task_types tt on tt.id = t.task_type_id
    where t.event_id = (select event_id from ev49) and tt.code = 'setup'),
  '2026-10-02'::date);
select t_eq('ולשעה המקומית שלו',
  (select t.onsite_start_time from tasks t join task_types tt on tt.id = t.task_type_id
    where t.event_id = (select event_id from ev49) and tt.code = 'setup'),
  '00:00'::time);
-- אספקה ב-00:00 וחיץ של שלוש שעות: היציאה מהמחסן היא 21:00 של הערב שלפני,
-- והיא נכתבת כמו שהיא — 0163 הוא שמרכיב ממנה את הרגע הנכון.
select t_eq('שעת היציאה היא 21:00, גם כשהיא נסוגה לערב שלפני',
  (select t.warehouse_start_time from tasks t join task_types tt on tt.id = t.task_type_id
    where t.event_id = (select event_id from ev49) and tt.code = 'setup'),
  '21:00'::time);
select t_eq('ו-0163 מרכיב ממנה את הערב שלפני ולא את זה שאחרי',
  (select app.warehouse_start_at(t.task_date, t.warehouse_start_time, t.onsite_start_time)
     from tasks t join task_types tt on tt.id = t.task_type_id
    where t.event_id = (select event_id from ev49) and tt.code = 'setup'),
  ('2026-10-01 21:00'::timestamp at time zone 'Asia/Jerusalem'));
select t_eq('אישור ההזמנה קידם את האירוע',
  (select s.code from events e join statuses s on s.id = e.status_id
    where e.id = (select event_id from ev49)), 'approved');
select t_eq('הריהוט הוחלף ולא נערם',
  (select count(*)::int from viperflow_order_items where event_id = (select event_id from ev49)), 5);
select t_eq('והכמות המעודכנת היא שנשמרה',
  (select quantity from viperflow_order_items
    where event_id = (select event_id from ev49) and name = 'כיסא נפוליאון'), 120::numeric);


\echo '--- 7. משלוח ישן אינו דורס חדש ---'

select t_eq('מעטפה עם חותמת ישנה נדחית כ-stale',
  (select viperflow_ingest(
     t49_envelope('evt_' || repeat('c', 32), '2026-09-16T08:30:00.000Z',
                  'order.updated', 'confirmed',
                  '2026-10-05T05:00:00.000Z', '2026-10-07T07:00:00.000Z',
                  t49_items(1)),
     jsonb_build_object('connection_id', (select connection_id from vf49))) ->> 'status'),
  'stale');
select t_eq('וההקמה נשארה איפה שהעדכון החדש השאיר אותה',
  (select t.task_date from tasks t join task_types tt on tt.id = t.task_type_id
    where t.event_id = (select event_id from ev49) and tt.code = 'setup'),
  '2026-10-02'::date);
select t_eq('הכמות לא חזרה אחורה',
  (select quantity from viperflow_order_items
    where event_id = (select event_id from ev49) and name = 'כיסא נפוליאון'), 120::numeric);
select t_eq('והמשלוח נרשם כלא-רלוונטי ולא כנכשל',
  (select status from viperflow_deliveries where event_id = 'evt_' || repeat('c', 32)), 'ignored');


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
select t_eq('וההקמה זזה למה שהמעטפה אומרת',
  (select t.task_date from tasks t join task_types tt on tt.id = t.task_type_id
    where t.event_id = (select event_id from ev49) and tt.code = 'setup'),
  '2026-10-05'::date);
select t_eq('והריהוט הוחלף',
  (select quantity from viperflow_order_items
    where event_id = (select event_id from ev49) and name = 'כיסא נפוליאון'), 7::numeric);
select t_eq('ושורת המשלוח נכתבה מחדש ולא הוכפלה',
  (select count(*)::int from viperflow_deliveries where event_id = 'evt_' || repeat('c', 32)), 1);

-- ומחזירים את המצב למה שהיה, כדי ש-§11 תבטל את האירוע האמיתי.
select viperflow_ingest(
  t49_envelope('evt_' || repeat('7', 32), '2026-09-16T09:30:00.000Z',
               'order.updated', 'confirmed',
               '2026-10-01T21:00:00.000Z', '2026-10-03T07:00:00.000Z',
               t49_items(120)),
  jsonb_build_object('connection_id', (select connection_id from vf49)));


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
  (select count(*)::int from viperflow_order_items where event_id = (select event_id from ev49)), 5);
select t_eq('ואת מספר ההזמנה דרך ה-view',
  (select order_number from viperflow_event_link where event_id = (select event_id from ev49)),
  'ORD-49-0001');
select t_eq('וה-view סופר לו את שורות הריהוט',
  (select furniture_lines from viperflow_event_link where event_id = (select event_id from ev49)), 2::bigint);
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

drop function t49_envelope(text, text, text, text, text, text, jsonb);
drop function t49_items(int);
