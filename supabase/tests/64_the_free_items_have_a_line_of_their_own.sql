\pset tuples_only on
\pset format unaligned

-- ===========================================================================
-- ‏64: הפריטים החופשיים בשורה משלהם, כמו הכיסאות (0213).
--
-- החבילה מקימה לקוח, חיבור, שלוש דמויות והזמנה משלה. האירוע יושב ב-
-- `current_date + 1100`, מעבר לכל טווח אחר. היא משאירה אחריה אירוע, משימות,
-- הכנסות, משלוחים והתראות שאינם מנוקים.
--
-- הלקוח נקרא "שיא עיצובים" כי הכרטיס `finance.client_share` של הדשבורד הוא
-- שלו בשמו (0174), ו-`manual_rows` שבו הוא חלק מהמיגרציה.
--
--   64a1 תפעול      — `integrations.manage`, הכנסות (צפייה ועריכה), תשלומים, לקוחות.
--   64a2 רכז כספים  — עורך הכנסות, אינו עוצר סנכרון.
--   64a4 מנהל מערכת — מקבל את ההתראות.
--
--   * ‏**הפיצול** — שורת `is_custom` בלי מוצר יוצאת מהישן; ההנחה חלה עליה; סך
--     הריהוט לא זז; הכיסאות ממשיכים לצאת לבד.
--   * ‏**העמלה** — ידנית, בשקלים, כולה של וייפר, ובדשבורד גם לכל קטגוריה לבד.
--   * ‏**המפרט השתנה לאחר קביעת העמלה** — לכל קטגוריה ידנית התראה משלה.
--   * ‏**עצירה וחידוש** — אותו כלל של 0212.
--   * ‏**כיבוי ללקוח** — הפריטים חוזרים לישן, השורה יורדת עם העמלה, ואין
--     "ההזמנה השתנתה" על המעבר עצמו — לא בכיבוי ולא בהדלקה.
-- ===========================================================================

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000064a1', 'fr64-ops@vl.test'),
  ('00000000-0000-0000-0000-0000000064a2', 'fr64-coord@vl.test'),
  ('00000000-0000-0000-0000-0000000064a4', 'fr64-admin@vl.test');

insert into customers (id, name, event_payments_enabled) values
  ('10000000-0000-0000-0000-000000000064', 'שיא עיצובים', true);

insert into profiles (id, user_id, user_kind, is_admin, full_name) values
  ('20000000-0000-0000-0000-0000000064a1', '00000000-0000-0000-0000-0000000064a1', 'staff', false, 'תפעול 64'),
  ('20000000-0000-0000-0000-0000000064a2', '00000000-0000-0000-0000-0000000064a2', 'staff', false, 'רכז כספים 64'),
  ('20000000-0000-0000-0000-0000000064a4', '00000000-0000-0000-0000-0000000064a4', 'staff', true,  'מנהל 64');

insert into user_permission_grants (profile_id, permission_key, allowed) values
  ('20000000-0000-0000-0000-0000000064a1', 'integrations.view', true),
  ('20000000-0000-0000-0000-0000000064a1', 'integrations.manage', true),
  ('20000000-0000-0000-0000-0000000064a1', 'events.view', true),
  ('20000000-0000-0000-0000-0000000064a1', 'customers.view', true),
  ('20000000-0000-0000-0000-0000000064a1', 'finance.income_view', true),
  ('20000000-0000-0000-0000-0000000064a1', 'finance.income_edit', true),
  ('20000000-0000-0000-0000-0000000064a1', 'finance.event_payments_view', true),
  ('20000000-0000-0000-0000-0000000064a2', 'events.view', true),
  ('20000000-0000-0000-0000-0000000064a2', 'finance.income_view', true),
  ('20000000-0000-0000-0000-0000000064a2', 'finance.income_edit', true),
  ('20000000-0000-0000-0000-0000000064a2', 'finance.event_payments_view', true),
  ('20000000-0000-0000-0000-0000000064a2', 'integrations.view', false),
  ('20000000-0000-0000-0000-0000000064a2', 'integrations.manage', false);

-- הכיסאות והפריטים החופשיים דלוקים ב-0%, כמו שהמיגרציות הדליקו אצל הלקוחות הקיימים.
insert into customer_income_splits (customer_id, category_id, viper_share_pct)
select '10000000-0000-0000-0000-000000000064', id,
       case viperflow_income_source when 'furniture_old' then 70 when 'furniture_new' then 20
                                    when 'furniture_chairs' then 0 when 'furniture_custom' then 0
                                    else 100 end
  from income_categories
 where viperflow_income_source in ('furniture_old', 'furniture_new', 'furniture_chairs',
                                   'furniture_custom', 'trucking')
   and deleted_at is null;

select t_eq('קטגוריית הפריטים החופשיים קיימת, ידנית, במשפחת הריהוט',
  (select count(*)::int || ':' || bool_and(manual_commission) || ':' || min(family) || ':' || min(name)
     from income_categories where viperflow_income_source = 'furniture_custom' and deleted_at is null),
  '1:true:furniture:פריטים חופשיים');

select t_expect_fail('ומקור שאינו מוכר עדיין נדחה',
  $$update income_categories set viperflow_income_source = 'furniture_other'
     where viperflow_income_source = 'furniture_custom'$$);

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000064a1', false);
select t_expect_ok('החיבור נפתח',
  $$select viperflow_set_connection('10000000-0000-0000-0000-000000000064',
      'שיא עיצובים — ViperFlow', true)$$);
reset role;
select set_config('request.jwt.claim.sub', '', false);

create temporary table vf64 as
  select id as connection_id from viperflow_connections
   where customer_id = '10000000-0000-0000-0000-000000000064';
grant select on vf64 to authenticated;

-- שורת ריהוט במעטפה. פריט חופשי (`p_custom`) הוא בדיוק מה ש-ViperFlow שולח
-- ומה שפונקציית הקצה עושה ממנו: אין `product_id`, ולכן לא חדש ובלי שמות קטגוריה.
create or replace function t64_line(p_n int, p_name text, p_total numeric, p_new boolean,
                                    p_cats text[], p_custom boolean default false)
returns jsonb language sql immutable as $$
  select jsonb_build_object(
    'id', '11111111-6464-4444-4444-00000000000' || p_n, 'parent_item_id', null,
    'line_type', 'product', 'is_component', false, 'name', p_name,
    'product_id', case when p_custom then null else '22222222-6464-4444-4444-00000000000' || p_n end,
    'quantity', 1, 'spare_quantity', 0, 'is_custom', p_custom, 'sort_order', p_n,
    'is_new', p_new and not p_custom, 'line_total', p_total, 'options', '[]'::jsonb,
    'category_names', to_jsonb(case when p_custom then array[]::text[] else p_cats end));
$$;

-- המעטפה: שולחן ישן 1000, ספה חדשה 600, כיסא ב-kiss-ot, שני פריטים חופשיים
-- (במה, ושלט 100), רכיב חופשי (שאינו נספר לעולם), שתי משאיות והנחה של 10%.
create or replace function t64_envelope(p_evt text, p_updated text, p_stage numeric,
                                        p_chair numeric default 500)
returns jsonb language sql stable as $$
  select jsonb_build_object(
    'id', 'evt_' || md5(p_evt),
    'type', 'order.updated',
    'created_at', p_updated,
    'api_version', 'v1',
    'livemode', true,
    'origin', jsonb_build_object('source', 'app'),
    'data', jsonb_build_object(
      'id', '99999999-6464-4444-4444-000000000064',
      'object', 'order',
      'order_number', 'ORD-64-0001',
      'status', 'confirmed',
      'customer_name', 'משפחת לוי',
      'event', jsonb_build_object('date', to_char(current_date + 1100, 'YYYY-MM-DD'),
                                  'location', 'אולם הפריטים'),
      'delivery_date', to_char(current_date + 1099, 'YYYY-MM-DD') || 'T05:00:00.000Z',
      'return_date',   to_char(current_date + 1101, 'YYYY-MM-DD') || 'T07:00:00.000Z',
      'notes', null,
      'catalog_enriched', true,
      'categories_enriched', true,
      'totals', jsonb_build_object('order_discount_percent', 10),
      'items', jsonb_build_array(
        t64_line(1, 'שולחן 64', 1000, false, array['שולחנות']),
        t64_line(2, 'ספה 64', 600, true, array['ספות']),
        t64_line(3, 'כיסא 64', p_chair, false, array['kiss-ot']),
        t64_line(4, 'במה מיוחדת 64', p_stage, false, null, true),
        t64_line(5, 'שלט 64', 100, false, null, true),
        t64_line(6, 'רכיב חופשי 64', 999, false, null, true)
          || jsonb_build_object('is_component', true,
                                'parent_item_id', '11111111-6464-4444-4444-000000000004'),
        jsonb_build_object(
          'id', '11111111-6464-4444-4444-000000000009', 'parent_item_id', null,
          'line_type', 'truck', 'is_component', false, 'name', 'הובלה',
          'quantity', 2, 'spare_quantity', 0, 'is_custom', false, 'sort_order', 9,
          'line_total', 2000, 'options', '[]'::jsonb)),
      'created_at', p_updated,
      'updated_at', p_updated),
    'previous', null);
$$;

create or replace function t64_ingest(p_evt text, p_hour int, p_stage numeric, p_chair numeric default 500)
returns text language sql as $$
  select viperflow_ingest(
    t64_envelope(p_evt, to_char(current_date, 'YYYY-MM-DD') || 'T' || lpad(p_hour::text, 2, '0') || ':00:00.000Z',
                 p_stage, p_chair),
    jsonb_build_object('connection_id', (select connection_id from vf64))) ->> 'status';
$$;

-- כל הכנסות האירוע בשורה אחת: מקור=סכום, ממוין.
create or replace function t64_income()
returns text language sql stable as $$
  select string_agg(ic.viperflow_income_source || '=' || ei.amount, ',' order by ic.viperflow_income_source)
    from event_income ei join income_categories ic on ic.id = ei.category_id
   where ei.event_id = (select event_id from viperflow_links
                         where order_id = '99999999-6464-4444-4444-000000000064');
$$;

create or replace function t64_cat(p_source text)
returns uuid language sql stable as $$
  select id from income_categories where viperflow_income_source = p_source and deleted_at is null;
$$;
grant execute on function t64_cat(text) to authenticated;

create or replace function t64_count(p_type text)
returns int language sql stable as $$
  select count(*)::int from notifications
   where type = p_type and recipient_id = '20000000-0000-0000-0000-0000000064a4'
     and entity_id = (select event_id from viperflow_links
                       where order_id = '99999999-6464-4444-4444-000000000064');
$$;


\echo '--- 1. הפריטים החופשיים יוצאים מהישן ---'

select t_eq('המעטפה הראשונה הוחלה', t64_ingest('64-birth', 8, 400), 'processed');

create temporary table ev64 as
  select event_id from viperflow_links where order_id = '99999999-6464-4444-4444-000000000064';
grant select on ev64 to authenticated;

-- ישן: 1000 × 0.9 = 900 · חדש: 600 × 0.9 = 540 · כיסאות: 500 × 0.9 = 450
-- · חופשיים: (400 + 100) × 0.9 = 450 — הרכיב אינו נספר
select t_eq('ישן 900, חדש 540, כיסאות 450, חופשיים 450, הובלה 2000',
  t64_income(),
  'furniture_chairs=450.00,furniture_custom=450.00,furniture_new=540.00,furniture_old=900.00,trucking=2000.00');

select t_eq('סך הריהוט לא זז: 2340 = (1000 + 600 + 500 + 400 + 100) × 0.9',
  (select sum(ei.amount) from event_income ei join income_categories ic on ic.id = ei.category_id
    where ei.event_id = (select event_id from ev64) and ic.family = 'furniture'),
  2340.00::numeric);

select t_eq('הצילום יודע על הפריטים החופשיים',
  (select order_snapshot ->> 'furniture_custom' from viperflow_links where event_id = (select event_id from ev64)),
  '450.00');

select t_eq('ויומן הלידה מונה אותם בשורה משלהם',
  (select count(*)::int from event_activity
    where event_id = (select event_id from ev64) and kind = 'synced'
      and note like '%פריטים חופשיים 450.00 ₪%' and note like '%כיסאות 450.00 ₪%'),
  1);


\echo '--- 2. העמלה — ידנית, וכולה של וייפר ---'

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000064a2', false);

create temporary table due64 as
  select (event_payment_summary((select event_id from ev64)) ->> 'due')::numeric as due;

select t_eq('שורת הפריטים החופשיים: ידנית, בלי אחוז, 450 והחלק של וייפר 0',
  (select (l ->> 'manual_commission') || ':' || coalesce(l ->> 'pct', 'null') || ':'
          || (l ->> 'gross') || ':' || (l ->> 'amount')
     from jsonb_array_elements(event_payment_summary((select event_id from ev64)) -> 'lines') l
    where l ->> 'category_id' = t64_cat('furniture_custom')::text),
  'true:null:450.00:0.00');

select t_expect_fail('עמלה גבוהה מהסכום נדחית',
  $$select event_income_set_commission((select event_id from ev64), t64_cat('furniture_custom'), 451)$$);
select t_eq('רכז הכספים קובע 40 ₪ — על בסיס 450',
  (select (r ->> 'commission') || ':' || (r ->> 'basis')
     from event_income_set_commission((select event_id from ev64), t64_cat('furniture_custom'), 40) r),
  '40.00:450.00');

select t_eq('המגיע עלה ב-40 בדיוק',
  (select (event_payment_summary((select event_id from ev64)) ->> 'due')::numeric - (select due from due64)),
  40::numeric);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000064a1', false);
select t_eq('בדשבורד: העמלות הידניות',
  (select (dashboard_sections(array['income.by_category'], current_date + 1100, current_date + 1100)
            #>> '{income.by_category,manual_commission_total}')::numeric),
  40::numeric);
select t_eq('ופרוסה "עמלת פריטים חופשיים" בפילוח ההכנסות',
  (select (x ->> 'total')::numeric
     from jsonb_array_elements(dashboard_sections(array['income.mix'], current_date + 1100, current_date + 1100)
                               -> 'income.mix') x
    where x ->> 'label' = 'עמלת פריטים חופשיים'),
  40::numeric);
select t_eq('ובכרטיס של הלקוח — כל קטגוריה ידנית לבד',
  (dashboard_sections(array['finance.client_share'], current_date + 1100, current_date + 1100)
     #> '{finance.client_share,manual_rows}'),
  '[{"name": "כיסאות", "raw": 450, "commission": 0, "share": 450},
    {"name": "פריטים חופשיים", "raw": 450, "commission": 40, "share": 410}]'::jsonb);
select t_eq('והסך הישן של הכרטיס הוא שתיהן יחד',
  (select (v ->> 'chairs_raw')::numeric || ':' || (v ->> 'chairs_commission')::numeric
          || ':' || (v ->> 'chairs_share')::numeric
     from (select dashboard_sections(array['finance.client_share'], current_date + 1100, current_date + 1100)
                    -> 'finance.client_share' as v) x),
  '900.00:40.00:860.00');
reset role;
select set_config('request.jwt.claim.sub', '', false);


\echo '--- 3. המפרט של הפריטים החופשיים משתנה אחרי קביעת העמלה ---'

-- הבמה עולה מ-400 ל-900: ‏(900 + 100) × 0.9 = 900
select t_eq('העדכון הוחל', t64_ingest('64-bigger-stage', 9, 900), 'processed');

select t_eq('חופשיים 900 — הישן לא זז',
  t64_income(),
  'furniture_chairs=450.00,furniture_custom=900.00,furniture_new=540.00,furniture_old=900.00,trucking=2000.00');

select t_eq('העמלה עצמה לא זזה, והבסיס עדיין 450',
  (select commission_amount || ':' || commission_basis from event_income
    where event_id = (select event_id from ev64) and category_id = t64_cat('furniture_custom')),
  '40.00:450.00');

select t_eq('יצאה התראה "המפרט השתנה לאחר קביעת העמלה" — על הפריטים החופשיים',
  (select count(*)::int || ':' || bool_and(body like '%— פריטים חופשיים: 900.00 ₪ (העמלה 40.00 ₪ נקבעה על 450.00 ₪)%')
     from notifications
    where type = 'income_commission_stale' and recipient_id = '20000000-0000-0000-0000-0000000064a4'
      and entity_id = (select event_id from ev64)),
  '1:true');

select t_eq('"ההזמנה השתנתה" מפרטת את הפריטים החופשיים, ולא את הישן',
  (select bool_or(body like '%פריטים חופשיים: 900.00 ₪ (היה 450.00 ₪)%')
          || ':' || bool_or(body like '%ריהוט ישן%')
     from notifications
    where type = 'viperflow_order_changed' and entity_id = (select event_id from ev64)
      and recipient_id = '20000000-0000-0000-0000-0000000064a4'),
  'true:false');

select t_eq('וביומן: המפרט השתנה לאחר קביעת העמלה',
  (select count(*)::int from event_activity
    where event_id = (select event_id from ev64) and kind = 'synced'
      and note like '%פריטים חופשיים: המפרט השתנה לאחר קביעת העמלה%'),
  1);


\echo '--- 4. שתי הקטגוריות זזות יחד — התראה לכל אחת ---'

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000064a2', false);
select t_expect_ok('עמלה של 30 ₪ על הכיסאות',
  $$select event_income_set_commission((select event_id from ev64), t64_cat('furniture_chairs'), 30)$$);
select t_expect_ok('ואישור מחדש של 40 ₪ על הפריטים החופשיים (בסיס 900)',
  $$select event_income_set_commission((select event_id from ev64), t64_cat('furniture_custom'), 40)$$);
reset role;
select set_config('request.jwt.claim.sub', '', false);

-- כיסא 1000 → 900 · במה 400 → (400 + 100) × 0.9 = 450
select t_eq('העדכון הוחל', t64_ingest('64-both-move', 10, 400, 1000), 'processed');

select t_eq('כיסאות 900, חופשיים 450',
  t64_income(),
  'furniture_chairs=900.00,furniture_custom=450.00,furniture_new=540.00,furniture_old=900.00,trucking=2000.00');

select t_eq('שתי התראות חדשות — אחת לכל קטגוריה',
  (select count(*) filter (where body like '%— כיסאות: 900.00 ₪ (העמלה 30.00 ₪ נקבעה על 450.00 ₪)%')
          || ':' || count(*) filter (where body like '%— פריטים חופשיים: 450.00 ₪ (העמלה 40.00 ₪ נקבעה על 900.00 ₪)%')
          || ':' || count(*)
     from notifications
    where type = 'income_commission_stale' and recipient_id = '20000000-0000-0000-0000-0000000064a4'
      and entity_id = (select event_id from ev64)),
  '1:1:3');


\echo '--- 5. עצירה פותחת, חידוש דורס ---'

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000064a1', false);
select t_eq('תפעול עוצר את הסנכרון',
  (select (viperflow_set_event_lock((select event_id from ev64), true) ->> 'locked')::boolean),
  true);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000064a2', false);
select t_eq('הפריטים החופשיים פתוחים לעריכה',
  (select (c ->> 'editable')::boolean
     from jsonb_array_elements(event_payment_summary((select event_id from ev64)) -> 'income_categories') c
    where c ->> 'id' = t64_cat('furniture_custom')::text),
  true);
select t_expect_ok('רכז הכספים עורך: חופשיים 777',
  format($$select event_income_save(%L, jsonb_build_object(%L, '777'))$$,
         (select event_id from ev64), t64_cat('furniture_custom')));

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000064a1', false);
select t_eq('חידוש מחיל מחדש',
  (select r ->> 'reapplied' from viperflow_set_event_lock((select event_id from ev64), false) r),
  'true');
reset role;
select set_config('request.jwt.claim.sub', '', false);

select t_eq('והסכומים חזרו למה שההזמנה אומרת',
  t64_income(),
  'furniture_chairs=900.00,furniture_custom=450.00,furniture_new=540.00,furniture_old=900.00,trucking=2000.00');


\echo '--- 6. כיבוי ללקוח — חזרה לישן, בלי "ההזמנה השתנתה" ---'

create temporary table notes64 as
  select t64_count('viperflow_order_changed') as changed;

delete from customer_income_splits
 where customer_id = '10000000-0000-0000-0000-000000000064'
   and category_id = t64_cat('furniture_custom');

select t_eq('אותה הזמנה, משלוח חדש', t64_ingest('64-custom-off', 11, 400, 1000), 'processed');

-- ישן: (1000 + 400 + 100) × 0.9 = 1350
select t_eq('הפריטים החופשיים חזרו לישן, ושורתם ירדה',
  t64_income(),
  'furniture_chairs=900.00,furniture_new=540.00,furniture_old=1350.00,trucking=2000.00');

select t_eq('והיומן אומר שהעמלה הידנית עליהם בוטלה',
  (select count(*)::int from event_activity
    where event_id = (select event_id from ev64) and kind = 'synced'
      and note like '%פריטים חופשיים נספרים שוב בריהוט ישן/חדש — העמלה הידנית עליהם בוטלה%'),
  1);

select t_eq('המעבר עצמו אינו "ההזמנה השתנתה"',
  t64_count('viperflow_order_changed') - (select changed from notes64),
  0);


\echo '--- 7. הדלקה (כמו הסנכרון הראשון אחרי 0213) — בלי "ההזמנה השתנתה" ---'

insert into customer_income_splits (customer_id, category_id, viper_share_pct)
values ('10000000-0000-0000-0000-000000000064', t64_cat('furniture_custom'), 0);

select t_eq('אותה הזמנה, משלוח חדש', t64_ingest('64-custom-on', 12, 400, 1000), 'processed');

select t_eq('הפריטים החופשיים שוב בשורה משלהם',
  t64_income(),
  'furniture_chairs=900.00,furniture_custom=450.00,furniture_new=540.00,furniture_old=900.00,trucking=2000.00');

select t_eq('בלי עמלה — היא ירדה עם השורה',
  (select commission_amount is null from event_income
    where event_id = (select event_id from ev64) and category_id = t64_cat('furniture_custom')),
  true);

select t_eq('וגם המעבר הזה אינו "ההזמנה השתנתה"',
  t64_count('viperflow_order_changed') - (select changed from notes64),
  0);

select t_eq('אבל שינוי אמיתי בישן עדיין מדווח, גם כשהצד השני מקופל',
  (select app.viperflow_changes(
     jsonb_build_object('furniture_old', 1350.00),
     jsonb_build_object('furniture_old', 1000.00, 'furniture_custom', 450.00))),
  array['ריהוט ישן: 1,450.00 ₪ (היה 1,350.00 ₪)']);
