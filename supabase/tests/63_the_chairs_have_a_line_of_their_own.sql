\pset tuples_only on
\pset format unaligned

-- ===========================================================================
-- ‏63: הכיסאות בשורה משלהם, עמלה ידנית, ועריכה כשהסנכרון עצור (0212).
--
-- החבילה מקימה לקוח, חיבור, ארבע דמויות והזמנה משלה. האירוע יושב ב-
-- `current_date + 1070`, מעבר לכל טווח אחר. היא משאירה אחריה אירוע, משימות,
-- הכנסות, משלוחים והתראות שאינם מנוקים.
--
--   63a1 תפעול     — `integrations.manage`, הכנסות (צפייה ועריכה), תשלומים, לקוחות.
--   63a2 רכז כספים — עורך הכנסות, אינו עוצר סנכרון.
--   63a3 צופה      — רואה תשלומים והכנסות, אינו עורך.
--   63a4 מנהל מערכת — מקבל את ההתראות.
--
--   * ‏**הפיצול** — שורה בקטגוריית הכיסאות (או תחתיה, בכל רישיות) יוצאת
--     מהישן ומהחדש; ההנחה חלה עליה; סך הריהוט לא זז.
--   * ‏**העמלה** — רק עורך הכנסות קובע, רק בקטגוריה ידנית, לא מעל הסכום;
--     היא החלק של וייפר במגיע ובדשבורד.
--   * ‏**המפרט השתנה לאחר קביעת העמלה** — סימון, שורת יומן והתראה; קביעה
--     חוזרת מאשרת.
--   * ‏**עריכה ידנית** — נחסמת כשהסנכרון רץ, נפתחת כשהוא עצור, ונדרסת בחידוש.
--   * ‏**מעטפה ישנה** — בלי עץ הקטגוריות הכול ישן/חדש, והכיסאות אפס.
-- ===========================================================================

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000063a1', 'ch63-ops@vl.test'),
  ('00000000-0000-0000-0000-0000000063a2', 'ch63-coord@vl.test'),
  ('00000000-0000-0000-0000-0000000063a3', 'ch63-viewer@vl.test'),
  ('00000000-0000-0000-0000-0000000063a4', 'ch63-admin@vl.test');

insert into customers (id, name, event_payments_enabled) values
  ('10000000-0000-0000-0000-000000000063', 'לקוח כיסאות 63', true);

insert into profiles (id, user_id, user_kind, is_admin, full_name) values
  ('20000000-0000-0000-0000-0000000063a1', '00000000-0000-0000-0000-0000000063a1', 'staff', false, 'תפעול 63'),
  ('20000000-0000-0000-0000-0000000063a2', '00000000-0000-0000-0000-0000000063a2', 'staff', false, 'רכז כספים 63'),
  ('20000000-0000-0000-0000-0000000063a3', '00000000-0000-0000-0000-0000000063a3', 'staff', false, 'צופה 63'),
  ('20000000-0000-0000-0000-0000000063a4', '00000000-0000-0000-0000-0000000063a4', 'staff', true,  'מנהל 63');

insert into user_permission_grants (profile_id, permission_key, allowed) values
  ('20000000-0000-0000-0000-0000000063a1', 'integrations.view', true),
  ('20000000-0000-0000-0000-0000000063a1', 'integrations.manage', true),
  ('20000000-0000-0000-0000-0000000063a1', 'events.view', true),
  ('20000000-0000-0000-0000-0000000063a1', 'customers.view', true),
  ('20000000-0000-0000-0000-0000000063a1', 'finance.income_view', true),
  ('20000000-0000-0000-0000-0000000063a1', 'finance.income_edit', true),
  ('20000000-0000-0000-0000-0000000063a1', 'finance.event_payments_view', true),
  ('20000000-0000-0000-0000-0000000063a2', 'events.view', true),
  ('20000000-0000-0000-0000-0000000063a2', 'finance.income_view', true),
  ('20000000-0000-0000-0000-0000000063a2', 'finance.income_edit', true),
  ('20000000-0000-0000-0000-0000000063a2', 'finance.event_payments_view', true),
  ('20000000-0000-0000-0000-0000000063a2', 'integrations.view', false),
  ('20000000-0000-0000-0000-0000000063a2', 'integrations.manage', false),
  ('20000000-0000-0000-0000-0000000063a3', 'events.view', true),
  ('20000000-0000-0000-0000-0000000063a3', 'finance.income_view', true),
  ('20000000-0000-0000-0000-0000000063a3', 'finance.event_payments_view', true),
  ('20000000-0000-0000-0000-0000000063a3', 'finance.income_edit', false);

-- הכיסאות דלוקים ב-0%, כמו שהמיגרציה הדליקה אצל הלקוחות הקיימים.
insert into customer_income_splits (customer_id, category_id, viper_share_pct)
select '10000000-0000-0000-0000-000000000063', id,
       case viperflow_income_source when 'furniture_old' then 70 when 'furniture_new' then 20
                                    when 'furniture_chairs' then 0 else 100 end
  from income_categories
 where viperflow_income_source in ('furniture_old', 'furniture_new', 'furniture_chairs', 'trucking')
   and deleted_at is null;

select t_eq('קטגוריית הכיסאות קיימת, ידנית, במשפחת הריהוט',
  (select count(*)::int || ':' || bool_and(manual_commission) || ':' || min(family)
     from income_categories where viperflow_income_source = 'furniture_chairs' and deleted_at is null),
  '1:true:furniture');

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000063a1', false);
select t_expect_ok('החיבור נפתח',
  $$select viperflow_set_connection('10000000-0000-0000-0000-000000000063',
      'לקוח כיסאות 63 — ViperFlow', true)$$);
select t_eq('ברירת המחדל של קטגוריות הכיסאות היא kiss-ot',
  (select x -> 'chairs_category_names' from jsonb_array_elements(viperflow_connection_status()) x
    where x ->> 'customer_id' = '10000000-0000-0000-0000-000000000063'),
  '["kiss-ot"]'::jsonb);
reset role;
select set_config('request.jwt.claim.sub', '', false);

create temporary table vf63 as
  select id as connection_id from viperflow_connections
   where customer_id = '10000000-0000-0000-0000-000000000063';
grant select on vf63 to authenticated;

-- שורת ריהוט במעטפה: מחיר, האם חדש, ושמות הקטגוריה (הקרוב ראשון).
create or replace function t63_line(p_n int, p_name text, p_total numeric, p_new boolean, p_cats text[])
returns jsonb language sql immutable as $$
  select jsonb_build_object(
    'id', '11111111-6363-4444-4444-00000000000' || p_n, 'parent_item_id', null,
    'line_type', 'product', 'is_component', false, 'name', p_name,
    'quantity', 10, 'spare_quantity', 0, 'is_custom', false, 'sort_order', p_n,
    'is_new', p_new, 'line_total', p_total, 'options', '[]'::jsonb)
  || case when p_cats is null then '{}'::jsonb
          else jsonb_build_object('category_names', to_jsonb(p_cats)) end;
$$;

-- המעטפה: שולחן ישן, כיסא חדש ב-kiss-ot, כיסא ישן בתת-קטגוריה (ברישיות אחרת),
-- שתי משאיות והנחה של 10%. ‏`p_cats = false` היא מעטפה מלפני 0212.
create or replace function t63_envelope(p_evt text, p_updated text, p_chair_new numeric,
                                        p_cats boolean default true)
returns jsonb language sql stable as $$
  select jsonb_build_object(
    'id', 'evt_' || md5(p_evt),
    'type', 'order.updated',
    'created_at', p_updated,
    'api_version', 'v1',
    'livemode', true,
    'origin', jsonb_build_object('source', 'app'),
    'data', jsonb_build_object(
      'id', '99999999-6363-4444-4444-000000000063',
      'object', 'order',
      'order_number', 'ORD-63-0001',
      'status', 'confirmed',
      'customer_name', 'משפחת כהן',
      'event', jsonb_build_object('date', to_char(current_date + 1070, 'YYYY-MM-DD'),
                                  'location', 'אולם הכיסאות'),
      'delivery_date', to_char(current_date + 1069, 'YYYY-MM-DD') || 'T05:00:00.000Z',
      'return_date',   to_char(current_date + 1071, 'YYYY-MM-DD') || 'T07:00:00.000Z',
      'notes', null,
      'catalog_enriched', true,
      'totals', jsonb_build_object('order_discount_percent', 10),
      'items', jsonb_build_array(
        t63_line(1, 'שולחן 63', 1000, false, case when p_cats then array['שולחנות'] end),
        t63_line(2, 'כיסא חדש 63', p_chair_new, true, case when p_cats then array['kiss-ot'] end),
        t63_line(3, 'כיסא בר 63', 300, false, case when p_cats then array['כיסאות בר', ' KISS-OT '] end),
        jsonb_build_object(
          'id', '11111111-6363-4444-4444-000000000009', 'parent_item_id', null,
          'line_type', 'truck', 'is_component', false, 'name', 'הובלה',
          'quantity', 2, 'spare_quantity', 0, 'is_custom', false, 'sort_order', 9,
          'line_total', 2000, 'options', '[]'::jsonb)),
      'created_at', p_updated,
      'updated_at', p_updated)
    || case when p_cats then jsonb_build_object('categories_enriched', true) else '{}'::jsonb end,
    'previous', null);
$$;

-- כל הכנסות האירוע בשורה אחת: מקור=סכום, ממוין.
create or replace function t63_income()
returns text language sql stable as $$
  select string_agg(ic.viperflow_income_source || '=' || ei.amount, ',' order by ic.viperflow_income_source)
    from event_income ei join income_categories ic on ic.id = ei.category_id
   where ei.event_id = (select event_id from viperflow_links
                         where order_id = '99999999-6363-4444-4444-000000000063');
$$;

create or replace function t63_cat(p_source text)
returns uuid language sql stable as $$
  select id from income_categories where viperflow_income_source = p_source and deleted_at is null;
$$;
grant execute on function t63_cat(text) to authenticated;


\echo '--- 1. הכיסאות יוצאים מהישן ומהחדש ---'

select t_eq('המעטפה הראשונה הוחלה',
  (select viperflow_ingest(
     t63_envelope('63-birth', to_char(current_date, 'YYYY-MM-DD') || 'T08:00:00.000Z', 500),
     jsonb_build_object('connection_id', (select connection_id from vf63))) ->> 'status'),
  'processed');

create temporary table ev63 as
  select event_id from viperflow_links where order_id = '99999999-6363-4444-4444-000000000063';
grant select on ev63 to authenticated;

-- ישן: שולחן 1000 → 900 · חדש: אין (הכיסא החדש הוא כיסא) · כיסאות: (500 + 300) × 0.9 = 720
select t_eq('ישן 900, חדש 0, כיסאות 720, הובלה 2000',
  t63_income(),
  'furniture_chairs=720.00,furniture_new=0.00,furniture_old=900.00,trucking=2000.00');

select t_eq('סך הריהוט לא זז: 1620 = (1000 + 500 + 300) × 0.9',
  (select sum(ei.amount) from event_income ei join income_categories ic on ic.id = ei.category_id
    where ei.event_id = (select event_id from ev63) and ic.family = 'furniture'),
  1620.00::numeric);

select t_eq('והצילום יודע על הכיסאות',
  (select order_snapshot ->> 'furniture_chairs' from viperflow_links where event_id = (select event_id from ev63)),
  '720.00');


\echo '--- 2. בלי עמלה — הכיסאות אינם של וייפר ---'

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000063a3', false);

create temporary table due63 as
  select (event_payment_summary((select event_id from ev63)) ->> 'due')::numeric as due;

select t_eq('שורת הכיסאות: ידנית, בלי אחוז, הסכום 720 והחלק של וייפר 0',
  (select (l ->> 'manual_commission') || ':' || coalesce(l ->> 'pct', 'null') || ':'
          || (l ->> 'gross') || ':' || (l ->> 'amount')
     from jsonb_array_elements(event_payment_summary((select event_id from ev63)) -> 'lines') l
    where l ->> 'category_id' = t63_cat('furniture_chairs')::text),
  'true:null:720.00:0.00');

select t_eq('והסכום מסונכרן מ-ViperFlow',
  (select (l ->> 'synced')::boolean
     from jsonb_array_elements(event_payment_summary((select event_id from ev63)) -> 'lines') l
    where l ->> 'category_id' = t63_cat('furniture_chairs')::text),
  true);

select t_eq('צופה אינו עורך הכנסות — ואינו מקבל את רשימת הקטגוריות',
  (select (s ->> 'can_edit_income')::boolean || ':' || coalesce(s ->> 'income_categories', 'null')
     from event_payment_summary((select event_id from ev63)) s),
  'false:null');


\echo '--- 3. קביעת העמלה ---'

select t_expect_fail('צופה אינו קובע עמלה',
  $$select event_income_set_commission((select event_id from ev63), t63_cat('furniture_chairs'), 100)$$);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000063a2', false);
select t_expect_fail('עמלה גבוהה מסכום הכיסאות נדחית',
  $$select event_income_set_commission((select event_id from ev63), t63_cat('furniture_chairs'), 721)$$);
select t_expect_fail('עמלה שלילית נדחית',
  $$select event_income_set_commission((select event_id from ev63), t63_cat('furniture_chairs'), -1)$$);
select t_expect_fail('בריהוט ישן העמלה היא האחוז, ואינה נקבעת ביד',
  $$select event_income_set_commission((select event_id from ev63), t63_cat('furniture_old'), 10)$$);
select t_eq('רכז הכספים קובע 100 ₪ — על בסיס 720',
  (select (r ->> 'commission') || ':' || (r ->> 'basis')
     from event_income_set_commission((select event_id from ev63), t63_cat('furniture_chairs'), 100) r),
  '100.00:720.00');

select t_eq('המגיע עלה ב-100 בדיוק — העמלה כולה של וייפר',
  (select (event_payment_summary((select event_id from ev63)) ->> 'due')::numeric - (select due from due63)),
  100::numeric);

select t_eq('שורת הכיסאות: החלק של וייפר 100, והעמלה אינה ישנה',
  (select (l ->> 'amount') || ':' || (l ->> 'commission_stale')
     from jsonb_array_elements(event_payment_summary((select event_id from ev63)) -> 'lines') l
    where l ->> 'category_id' = t63_cat('furniture_chairs')::text),
  '100.00:false');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000063a1', false);
select t_eq('בדשבורד: העמלה בפילוח לפי קטגוריה',
  (select (dashboard_sections(array['income.by_category'], current_date + 1070, current_date + 1070)
            #>> '{income.by_category,manual_commission_total}')::numeric),
  100::numeric);
select t_eq('ופרוסה "עמלת כיסאות" בפילוח ההכנסות, מאה אחוז',
  (select (x ->> 'total')::numeric
     from jsonb_array_elements(dashboard_sections(array['income.mix'], current_date + 1070, current_date + 1070)
                               -> 'income.mix') x
    where x ->> 'label' = 'עמלת כיסאות'),
  100::numeric);
reset role;
select set_config('request.jwt.claim.sub', '', false);

select t_eq('נרשמה שורת יומן — בלי סכום',
  (select count(*)::int from event_activity
    where event_id = (select event_id from ev63) and note = 'העמלה על כיסאות נקבעה ביד'),
  1);


\echo '--- 4. כשהסנכרון רץ — הסכומים של ViperFlow אינם נערכים ביד ---'

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000063a2', false);
select t_expect_fail('שינוי סכום הכיסאות נדחה',
  format($$select event_income_save(%L, jsonb_build_object(%L, '999'))$$,
         (select event_id from ev63), t63_cat('furniture_chairs')));
select t_expect_ok('אותו סכום עובר בשקט — טופס ששולח הכול אינו נופל',
  format($$select event_income_save(%L, jsonb_build_object(%L, '720.00', %L, '900'))$$,
         (select event_id from ev63), t63_cat('furniture_chairs'), t63_cat('furniture_old')));
reset role;
select set_config('request.jwt.claim.sub', '', false);

select t_eq('והסכומים לא זזו',
  t63_income(),
  'furniture_chairs=720.00,furniture_new=0.00,furniture_old=900.00,trucking=2000.00');


\echo '--- 5. המפרט משתנה אחרי קביעת העמלה ---'

create temporary table notes63 as
  select (select count(*) from notifications
           where type = 'income_commission_stale' and entity_id = (select event_id from ev63)) as stale,
         (select count(*) from notifications
           where type = 'viperflow_order_changed' and entity_id = (select event_id from ev63)) as changed;

-- הכיסא החדש עולה מ-500 ל-1000: ‏(1000 + 300) × 0.9 = 1170
select t_eq('העדכון הוחל',
  (select viperflow_ingest(
     t63_envelope('63-more-chairs', to_char(current_date, 'YYYY-MM-DD') || 'T09:00:00.000Z', 1000),
     jsonb_build_object('connection_id', (select connection_id from vf63))) ->> 'status'),
  'processed');

select t_eq('כיסאות 1170 — הישן לא זז',
  t63_income(),
  'furniture_chairs=1170.00,furniture_new=0.00,furniture_old=900.00,trucking=2000.00');

select t_eq('העמלה עצמה לא זזה, והבסיס עדיין 720',
  (select commission_amount || ':' || commission_basis from event_income
    where event_id = (select event_id from ev63) and category_id = t63_cat('furniture_chairs')),
  '100.00:720.00');

select t_eq('יצאה התראה "המפרט השתנה לאחר קביעת העמלה" למנהל המערכת',
  (select count(*)::int from notifications
    where type = 'income_commission_stale' and entity_id = (select event_id from ev63)
      and recipient_id = '20000000-0000-0000-0000-0000000063a4'),
  1);

select t_eq('והתראת "ההזמנה השתנתה" מפרטת את הכיסאות',
  (select bool_or(body like '%כיסאות: 1,170.00 ₪ (היה 720.00 ₪)%') from notifications
    where type = 'viperflow_order_changed' and entity_id = (select event_id from ev63)),
  true);

select t_eq('וביומן: המפרט השתנה לאחר קביעת העמלה',
  (select count(*)::int from event_activity
    where event_id = (select event_id from ev63) and kind = 'synced'
      and note like '%כיסאות: המפרט השתנה לאחר קביעת העמלה%'),
  1);

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000063a3', false);
select t_eq('הכרטיס מסמן שהעמלה ישנה',
  (select (l ->> 'commission_stale')::boolean
     from jsonb_array_elements(event_payment_summary((select event_id from ev63)) -> 'lines') l
    where l ->> 'category_id' = t63_cat('furniture_chairs')::text),
  true);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000063a2', false);
select t_eq('קביעה חוזרת באותו סכום מאשרת את הבסיס החדש',
  (select r ->> 'basis'
     from event_income_set_commission((select event_id from ev63), t63_cat('furniture_chairs'), 100) r),
  '1170.00');
select t_eq('והסימון יורד',
  (select (l ->> 'commission_stale')::boolean
     from jsonb_array_elements(event_payment_summary((select event_id from ev63)) -> 'lines') l
    where l ->> 'category_id' = t63_cat('furniture_chairs')::text),
  false);
reset role;
select set_config('request.jwt.claim.sub', '', false);

select t_eq('אותו משלוח שוב (כפילות) אינו מתריע שוב',
  (select viperflow_ingest(
     t63_envelope('63-more-chairs', to_char(current_date, 'YYYY-MM-DD') || 'T09:00:00.000Z', 1000),
     jsonb_build_object('connection_id', (select connection_id from vf63))) ->> 'status'),
  'duplicate');
select t_eq('עדיין התראה אחת',
  (select count(*)::int from notifications
    where type = 'income_commission_stale' and entity_id = (select event_id from ev63)
      and recipient_id = '20000000-0000-0000-0000-0000000063a4'),
  1);


\echo '--- 6. עצירת סנכרון פותחת את הסכומים ---'

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000063a1', false);
select t_eq('תפעול עוצר את הסנכרון',
  (select (viperflow_set_event_lock((select event_id from ev63), true) ->> 'locked')::boolean),
  true);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000063a2', false);
select t_eq('ובכרטיס — הקטגוריות פתוחות לעריכה',
  (select bool_and((c ->> 'editable')::boolean)
     from jsonb_array_elements(event_payment_summary((select event_id from ev63)) -> 'income_categories') c),
  true);
select t_expect_ok('רכז הכספים עורך: כיסאות 2000, ישן 5000',
  format($$select event_income_save(%L, jsonb_build_object(%L, '2000', %L, '5000'))$$,
         (select event_id from ev63), t63_cat('furniture_chairs'), t63_cat('furniture_old')));
select t_eq('הסכום החדש בכרטיס, והעמלה מסומנת כישנה מולו',
  (select (l ->> 'gross') || ':' || (l ->> 'commission_stale')
     from jsonb_array_elements(event_payment_summary((select event_id from ev63)) -> 'lines') l
    where l ->> 'category_id' = t63_cat('furniture_chairs')::text),
  '2000.00:true');
select t_expect_fail('גם בעריכה ידנית — אין סכום שלילי',
  format($$select event_income_save(%L, jsonb_build_object(%L, '-5'))$$,
         (select event_id from ev63), t63_cat('furniture_chairs')));
reset role;
select set_config('request.jwt.claim.sub', '', false);

select t_eq('העריכה נשמרה',
  t63_income(),
  'furniture_chairs=2000.00,furniture_new=0.00,furniture_old=5000.00,trucking=2000.00');

select t_eq('עריכה ידנית אינה שולחת התראה על העמלה',
  (select count(*)::int from notifications
    where type = 'income_commission_stale' and entity_id = (select event_id from ev63)
      and recipient_id = '20000000-0000-0000-0000-0000000063a4'),
  1);


\echo '--- 7. חידוש סנכרון דורס את הידני ---'

delete from notes63;
insert into notes63
  select (select count(*) from notifications
           where type = 'income_commission_stale' and entity_id = (select event_id from ev63)),
         (select count(*) from notifications
           where type = 'viperflow_order_changed' and entity_id = (select event_id from ev63));

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000063a1', false);
select t_eq('חידוש בלי שהגיע דבר: אין השלמה, יש החלה מחדש',
  (select (r ->> 'caught_up') || ':' || (r ->> 'reapplied')
     from viperflow_set_event_lock((select event_id from ev63), false) r),
  'false:true');
reset role;
select set_config('request.jwt.claim.sub', '', false);

select t_eq('הסכומים חזרו למה שההזמנה אומרת',
  t63_income(),
  'furniture_chairs=1170.00,furniture_new=0.00,furniture_old=900.00,trucking=2000.00');

select t_eq('העמלה נשארה, והיא שוב על הבסיס',
  (select commission_amount || ':' || (commission_basis = amount) from event_income
    where event_id = (select event_id from ev63) and category_id = t63_cat('furniture_chairs')),
  '100.00:true');

select t_eq('ההחלה מחדש אינה "שינוי בהזמנה" ואינה מתריעה על העמלה',
  (select (select count(*) from notifications
            where type = 'income_commission_stale' and entity_id = (select event_id from ev63))
          - stale
          + (select count(*) from notifications
              where type = 'viperflow_order_changed' and entity_id = (select event_id from ev63))
          - changed
     from notes63)::int,
  0);

select t_eq('ויומן החידוש אומר שהנתונים הוחלו מחדש',
  (select count(*)::int from event_activity
    where event_id = (select event_id from ev63) and kind = 'sync_unlocked'
      and note like '%הוחלו מחדש%'),
  1);

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000063a2', false);
select t_expect_fail('והסכומים שוב סגורים לעריכה',
  format($$select event_income_save(%L, jsonb_build_object(%L, '5000'))$$,
         (select event_id from ev63), t63_cat('furniture_old')));
reset role;
select set_config('request.jwt.claim.sub', '', false);


\echo '--- 8. מעטפה מלפני 0212 — הכול ישן וחדש, והכיסאות אפס ---'

select t_eq('מעטפה בלי עץ הקטגוריות הוחלה',
  (select viperflow_ingest(
     t63_envelope('63-legacy', to_char(current_date, 'YYYY-MM-DD') || 'T10:00:00.000Z', 1000, false),
     jsonb_build_object('connection_id', (select connection_id from vf63))) ->> 'status'),
  'processed');

-- ישן: (1000 + 300) × 0.9 = 1170 · חדש: 1000 × 0.9 = 900 · כיסאות 0 — סך הריהוט 2070 כמו קודם
select t_eq('אותו כסף לא נספר פעמיים',
  t63_income(),
  'furniture_chairs=0.00,furniture_new=900.00,furniture_old=1170.00,trucking=2000.00');

select t_eq('והאפס של מעטפה ישנה אינו "המפרט השתנה" — אין התראה נוספת',
  (select count(*)::int from notifications
    where type = 'income_commission_stale' and entity_id = (select event_id from ev63)
      and recipient_id = '20000000-0000-0000-0000-0000000063a4'),
  1);


\echo '--- 9. רשימת הכיסאות של החיבור ---'

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000063a1', false);
select t_expect_ok('הרשימה נערכת, ושם ריק יורד',
  $$select viperflow_set_connection('10000000-0000-0000-0000-000000000063',
      'לקוח כיסאות 63 — ViperFlow', true, null,
      (select connection_id from vf63), null, null, null, array['כיסאות', ' ', 'kiss-ot'])$$);
select t_eq('ונקראת חזרה',
  (select x -> 'chairs_category_names' from jsonb_array_elements(viperflow_connection_status()) x
    where x ->> 'customer_id' = '10000000-0000-0000-0000-000000000063'),
  '["kiss-ot", "כיסאות"]'::jsonb);
select t_expect_ok('ושמירה בלי הרשימה אינה נוגעת בה',
  $$select viperflow_set_connection('10000000-0000-0000-0000-000000000063',
      'לקוח כיסאות 63 — ViperFlow', true, null, (select connection_id from vf63))$$);
select t_eq('עדיין שתיים',
  (select jsonb_array_length(x -> 'chairs_category_names') from jsonb_array_elements(viperflow_connection_status()) x
    where x ->> 'customer_id' = '10000000-0000-0000-0000-000000000063'),
  2);
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000063a2', false);
select t_expect_fail('מי שאינו מנהל אינטגרציות אינו עורך את הרשימה',
  $$select viperflow_set_connection('10000000-0000-0000-0000-000000000063',
      'לקוח כיסאות 63 — ViperFlow', true, null,
      (select connection_id from vf63), null, null, null, array['x'])$$);
reset role;
select set_config('request.jwt.claim.sub', '', false);
