\pset tuples_only on
\pset format unaligned

-- ===========================================================================
-- ‏85: ההובלה נערכת ביד והסנכרון ממשיך לרוץ (0242).
--
-- החבילה מקימה לקוח, חיבור, ארבע דמויות והזמנה משלה. האירוע יושב ב-
-- `current_date + 1120`, מעבר לכל טווח אחר. היא משאירה אחריה אירוע, משימות,
-- הכנסות, משלוחים והתראות שאינם מנוקים.
--
--   85a1 תפעול      — `integrations.manage`, הכנסות (צפייה ועריכה), תשלומים.
--   85a2 רכז כספים  — עורך הכנסות, אינו עוצר סנכרון.
--   85a3 צופה       — רואה תשלומים והכנסות, אינו עורך.
--   85a4 מנהל מערכת — מקבל את ההתראות.
--
--   * ‏**הדגל** — ‏`manual_override` דלוק על ההובלות בלבד.
--   * ‏**העריכה** — נפתחת להובלות כשהסנכרון רץ, ונשארת חסומה לריהוט.
--   * ‏**הנעילה** — סכום שזז ננעל, סכום שחוזר על עצמו אינו נועל, והסנכרון
--     הבא מעדכן רק את `synced_amount` לצדו — ומתריע כרגיל שההזמנה זזה.
--   * ‏**עצירה וחידוש** — עריכה בזמן עצירה ננעלת, וההחלה מחדש אינה דורסת.
--   * ‏**חזרה** — ‏`event_income_release` ושדה ריק מחזירים לסכום של ViperFlow,
--     ומשם הסנכרון שולט שוב.
-- ===========================================================================

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000085a1', 'hl85-ops@vl.test'),
  ('00000000-0000-0000-0000-0000000085a2', 'hl85-coord@vl.test'),
  ('00000000-0000-0000-0000-0000000085a3', 'hl85-viewer@vl.test'),
  ('00000000-0000-0000-0000-0000000085a4', 'hl85-admin@vl.test');

insert into customers (id, name, event_payments_enabled) values
  ('10000000-0000-0000-0000-000000000085', 'שיא עיצובים 85', true);

insert into profiles (id, user_id, user_kind, is_admin, full_name) values
  ('20000000-0000-0000-0000-0000000085a1', '00000000-0000-0000-0000-0000000085a1', 'staff', false, 'תפעול 85'),
  ('20000000-0000-0000-0000-0000000085a2', '00000000-0000-0000-0000-0000000085a2', 'staff', false, 'רכז כספים 85'),
  ('20000000-0000-0000-0000-0000000085a3', '00000000-0000-0000-0000-0000000085a3', 'staff', false, 'צופה 85'),
  ('20000000-0000-0000-0000-0000000085a4', '00000000-0000-0000-0000-0000000085a4', 'staff', true,  'מנהל 85');

insert into user_permission_grants (profile_id, permission_key, allowed) values
  ('20000000-0000-0000-0000-0000000085a1', 'integrations.view', true),
  ('20000000-0000-0000-0000-0000000085a1', 'integrations.manage', true),
  ('20000000-0000-0000-0000-0000000085a1', 'events.view', true),
  ('20000000-0000-0000-0000-0000000085a1', 'customers.view', true),
  ('20000000-0000-0000-0000-0000000085a1', 'finance.income_view', true),
  ('20000000-0000-0000-0000-0000000085a1', 'finance.income_edit', true),
  ('20000000-0000-0000-0000-0000000085a1', 'finance.event_payments_view', true),
  ('20000000-0000-0000-0000-0000000085a2', 'events.view', true),
  ('20000000-0000-0000-0000-0000000085a2', 'finance.income_view', true),
  ('20000000-0000-0000-0000-0000000085a2', 'finance.income_edit', true),
  ('20000000-0000-0000-0000-0000000085a2', 'finance.event_payments_view', true),
  ('20000000-0000-0000-0000-0000000085a2', 'integrations.view', false),
  ('20000000-0000-0000-0000-0000000085a2', 'integrations.manage', false),
  ('20000000-0000-0000-0000-0000000085a3', 'events.view', true),
  ('20000000-0000-0000-0000-0000000085a3', 'finance.income_view', true),
  ('20000000-0000-0000-0000-0000000085a3', 'finance.event_payments_view', true),
  ('20000000-0000-0000-0000-0000000085a3', 'finance.income_edit', false);

-- רק הישן וההובלות דלוקים ללקוח: החבילה הזו היא על ההובלה, וקטגוריה בלי
-- שורת חלוקה אינה מקבלת שורה על האירוע (0190 §2) — כך הפירוט נשאר קריא.
insert into customer_income_splits (customer_id, category_id, viper_share_pct)
select '10000000-0000-0000-0000-000000000085', id,
       case viperflow_income_source when 'furniture_old' then 70 else 100 end
  from income_categories
 where viperflow_income_source in ('furniture_old', 'trucking') and deleted_at is null;


\echo '--- 1. הדגל יושב על ההובלות, ורק עליהן ---'

select t_eq('ההובלות מסומנות לעריכה ידנית',
  (select count(*)::int || ':' || bool_and(manual_override)
     from income_categories where viperflow_income_source = 'trucking' and deleted_at is null),
  '1:true');

select t_eq('וסעיפי הריהוט נשארו נעולים',
  (select bool_or(manual_override) from income_categories
    where viperflow_income_source in ('furniture_old', 'furniture_new',
                                      'furniture_chairs', 'furniture_custom')
      and deleted_at is null),
  false);


-- ===== המעטפה: שולחן ישן 1000, ושתי משאיות שהמחיר שלהן פרמטר ===============

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000085a1', false);
select t_expect_ok('החיבור נפתח',
  $$select viperflow_set_connection('10000000-0000-0000-0000-000000000085',
      'שיא עיצובים 85 — ViperFlow', true)$$);
reset role;
select set_config('request.jwt.claim.sub', '', false);

create temporary table vf85 as
  select id as connection_id from viperflow_connections
   where customer_id = '10000000-0000-0000-0000-000000000085';
grant select on vf85 to authenticated;

create or replace function t85_envelope(p_evt text, p_updated text, p_truck numeric, p_table numeric)
returns jsonb language sql stable as $$
  select jsonb_build_object(
    'id', 'evt_' || md5(p_evt),
    'type', 'order.updated',
    'created_at', p_updated,
    'api_version', 'v1',
    'livemode', true,
    'origin', jsonb_build_object('source', 'app'),
    'data', jsonb_build_object(
      'id', '99999999-8585-4444-4444-000000000085',
      'object', 'order',
      'order_number', 'ORD-85-0001',
      'status', 'confirmed',
      'customer_name', 'משפחת הובלה',
      'event', jsonb_build_object('date', to_char(current_date + 1120, 'YYYY-MM-DD'),
                                  'location', 'אולם ההובלות'),
      'delivery_date', to_char(current_date + 1119, 'YYYY-MM-DD') || 'T05:00:00.000Z',
      'return_date',   to_char(current_date + 1121, 'YYYY-MM-DD') || 'T07:00:00.000Z',
      'notes', null,
      'catalog_enriched', true,
      'categories_enriched', true,
      'totals', jsonb_build_object('order_discount_percent', 0),
      'items', jsonb_build_array(
        jsonb_build_object(
          'id', '11111111-8585-4444-4444-000000000001', 'parent_item_id', null,
          'line_type', 'product', 'is_component', false, 'name', 'שולחן 85',
          'product_id', '22222222-8585-4444-4444-000000000001',
          'quantity', 1, 'spare_quantity', 0, 'is_custom', false, 'sort_order', 1,
          'is_new', false, 'line_total', p_table, 'options', '[]'::jsonb,
          'category_names', to_jsonb(array['שולחנות'])),
        jsonb_build_object(
          'id', '11111111-8585-4444-4444-000000000009', 'parent_item_id', null,
          'line_type', 'truck', 'is_component', false, 'name', 'הובלה',
          'quantity', 2, 'spare_quantity', 0, 'is_custom', false, 'sort_order', 9,
          'line_total', p_truck, 'options', '[]'::jsonb)),
      'created_at', p_updated,
      'updated_at', p_updated),
    'previous', null);
$$;

create or replace function t85_ingest(p_evt text, p_hour int, p_truck numeric, p_table numeric default 1000)
returns text language sql as $$
  select viperflow_ingest(
    t85_envelope(p_evt, to_char(current_date, 'YYYY-MM-DD') || 'T' || lpad(p_hour::text, 2, '0') || ':00:00.000Z',
                 p_truck, p_table),
    jsonb_build_object('connection_id', (select connection_id from vf85))) ->> 'status';
$$;

-- כל הכנסות האירוע: מקור=סכום/סכום שהגיע/ידני, ממוין.
create or replace function t85_income()
returns text language sql stable as $$
  select string_agg(ic.viperflow_income_source || '=' || ei.amount
                      || '/' || coalesce(ei.synced_amount::text, '-')
                      || '/' || ei.is_manual,
                    ',' order by ic.viperflow_income_source)
    from event_income ei join income_categories ic on ic.id = ei.category_id
   where ei.event_id = (select event_id from viperflow_links
                         where order_id = '99999999-8585-4444-4444-000000000085');
$$;

create or replace function t85_cat(p_source text)
returns uuid language sql stable as $$
  select id from income_categories where viperflow_income_source = p_source and deleted_at is null;
$$;
grant execute on function t85_cat(text) to authenticated;

-- שורת ההובלות בכרטיס התשלומים: סכום/נעול בתצוגה/ידני/הסכום שהגיע.
create or replace function t85_line()
returns text language sql stable as $$
  select (l ->> 'amount') || '/' || (l ->> 'synced') || '/' || (l ->> 'is_manual')
         || '/' || coalesce(l ->> 'synced_amount', '-')
    from jsonb_array_elements(event_payment_summary(
           (select event_id from viperflow_links
             where order_id = '99999999-8585-4444-4444-000000000085')) -> 'lines') l
   where l ->> 'category_id' = t85_cat('trucking')::text;
$$;
grant execute on function t85_line() to authenticated;


\echo '--- 2. הלידה: ההובלה מגיעה מההזמנה, ופתוחה לעריכה ---'

select t_eq('המעטפה הראשונה הוחלה', t85_ingest('85-birth', 8, 2000), 'processed');

create temporary table ev85 as
  select event_id from viperflow_links where order_id = '99999999-8585-4444-4444-000000000085';
grant select on ev85 to authenticated;

select t_eq('ישן 1000 והובלה 2000 — ושניהם מסומנים כמה שהגיע',
  t85_income(),
  'furniture_old=1000.00/1000.00/false,trucking=2000.00/2000.00/false');

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000085a2', false);
select t_eq('בחלון העריכה: ההובלות פתוחות, הריהוט לא',
  (select string_agg((c ->> 'editable'), ',' order by c ->> 'source')
     from jsonb_array_elements(event_payment_summary((select event_id from ev85)) -> 'income_categories') c
    where c ->> 'source' in ('furniture_old', 'trucking')),
  'false,true');
select t_eq('והשורה עדיין "מגיעה מ-ViperFlow"', t85_line(), '2000.00/true/false/2000.00');
reset role;
select set_config('request.jwt.claim.sub', '', false);


\echo '--- 3. אותו סכום אינו נעילה, סכום שזז כן ---'

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000085a2', false);
select t_expect_ok('שמירה שחוזרת על הסכום הקיים עוברת',
  format($$select event_income_save(%L, jsonb_build_object(%L, '2000.00'))$$,
         (select event_id from ev85), t85_cat('trucking')));
reset role;
select set_config('request.jwt.claim.sub', '', false);

select t_eq('ולא נעלה דבר',
  t85_income(),
  'furniture_old=1000.00/1000.00/false,trucking=2000.00/2000.00/false');

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000085a3', false);
select t_expect_fail('צופה בלי מפתח ההזנה אינו עורך',
  format($$select event_income_save(%L, jsonb_build_object(%L, '2500'))$$,
         (select event_id from ev85), t85_cat('trucking')));

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000085a2', false);
select t_expect_fail('והריהוט נשאר חסום גם לעורך ההכנסות',
  format($$select event_income_save(%L, jsonb_build_object(%L, '1500'))$$,
         (select event_id from ev85), t85_cat('furniture_old')));
select t_expect_ok('רכז הכספים מתקן את ההובלה ל-2500',
  format($$select event_income_save(%L, jsonb_build_object(%L, '2500'))$$,
         (select event_id from ev85), t85_cat('trucking')));
select t_eq('ומהשורה ירדה הנעילה בתצוגה', t85_line(), '2500.00/false/true/2000.00');
select t_expect_fail('סכום שלילי עדיין נדחה',
  format($$select event_income_save(%L, jsonb_build_object(%L, '-5'))$$,
         (select event_id from ev85), t85_cat('trucking')));
reset role;
select set_config('request.jwt.claim.sub', '', false);

select t_eq('הסכום הידני נשמר, ולצדו מה שההזמנה אומרת',
  t85_income(),
  'furniture_old=1000.00/1000.00/false,trucking=2500.00/2000.00/true');

select t_eq('ונרשם מי קבע ומתי',
  (select (manual_set_by = '20000000-0000-0000-0000-0000000085a2')
          || ':' || (manual_set_at is not null)
     from event_income
    where event_id = (select event_id from ev85) and category_id = t85_cat('trucking')),
  'true:true');


\echo '--- 4. הסנכרון הבא אינו דורס — ומתריע כרגיל ---'

select t_eq('עדכון: הובלה 3000, שולחן 1200', t85_ingest('85-more', 9, 3000, 1200), 'processed');

select t_eq('הריהוט התעדכן, ההובלה נשארה ידנית, ומה שהגיע נרשם לצדה',
  t85_income(),
  'furniture_old=1200.00/1200.00/false,trucking=2500.00/3000.00/true');

select t_eq('וההתראה אומרת שההובלות בהזמנה זזו',
  (select count(*)::int from notifications
    where recipient_id = '20000000-0000-0000-0000-0000000085a4'
      and entity_id = (select event_id from ev85)
      and type = 'viperflow_order_changed'
      and body like '%הובלות%'),
  1);

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000085a2', false);
select t_eq('ובכרטיס מגיע הסכום הידני, לא זה של ההזמנה',
  (select (l ->> 'amount')::numeric
     from jsonb_array_elements(event_payment_summary((select event_id from ev85)) -> 'lines') l
    where l ->> 'category_id' = t85_cat('trucking')::text),
  2500.00::numeric);
reset role;
select set_config('request.jwt.claim.sub', '', false);


\echo '--- 5. עצירה, עריכה וחידוש: ההחלה מחדש אינה דורסת ---'

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000085a1', false);
select t_eq('תפעול עוצר את הסנכרון',
  (select (viperflow_set_event_lock((select event_id from ev85), true) ->> 'locked')::boolean),
  true);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000085a2', false);
select t_expect_ok('ובזמן העצירה ההובלה נערכת ל-2800',
  format($$select event_income_save(%L, jsonb_build_object(%L, '2800'))$$,
         (select event_id from ev85), t85_cat('trucking')));

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000085a1', false);
select t_eq('ותפעול מחדש את הסנכרון, עם החלה מחדש',
  (select (r ->> 'reapplied')::boolean
     from viperflow_set_event_lock((select event_id from ev85), false) r),
  true);
reset role;
select set_config('request.jwt.claim.sub', '', false);

select t_eq('הריהוט חזר למה שההזמנה אומרת, וההובלה הידנית שרדה',
  t85_income(),
  'furniture_old=1200.00/1200.00/false,trucking=2800.00/3000.00/true');


\echo '--- 6. חזרה לסכום של ViperFlow ---'

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000085a3', false);
select t_expect_fail('צופה אינו משחרר',
  format($$select event_income_release(%L, %L)$$, (select event_id from ev85), t85_cat('trucking')));

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000085a2', false);
select t_expect_fail('ואין מה לשחרר בקטגוריה שאינה ידנית',
  format($$select event_income_release(%L, %L)$$, (select event_id from ev85), t85_cat('furniture_old')));
select t_expect_ok('רכז הכספים מחזיר את ההובלה לסכום של ההזמנה',
  format($$select event_income_release(%L, %L)$$, (select event_id from ev85), t85_cat('trucking')));
reset role;
select set_config('request.jwt.claim.sub', '', false);

select t_eq('והיא שוב של הסנכרון',
  t85_income(),
  'furniture_old=1200.00/1200.00/false,trucking=3000.00/3000.00/false');

select t_eq('ונרשמה שורת יומן',
  (select count(*)::int from event_activity
    where event_id = (select event_id from ev85)
      and note like 'הסכום של "%" חזר לסכום מ-ViperFlow'),
  1);

select t_eq('עדכון: הובלה 3300', t85_ingest('85-after-release', 10, 3300, 1200), 'processed');
select t_eq('ומשם הסנכרון שולט שוב',
  t85_income(),
  'furniture_old=1200.00/1200.00/false,trucking=3300.00/3300.00/false');


\echo '--- 7. שדה ריק בחלון העריכה מחזיר, ואינו מוחק ---'

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000085a2', false);
select t_expect_ok('נעילה חדשה: 4000',
  format($$select event_income_save(%L, jsonb_build_object(%L, '4000'))$$,
         (select event_id from ev85), t85_cat('trucking')));
select t_expect_ok('ושדה ריק מחזיר',
  format($$select event_income_save(%L, jsonb_build_object(%L, ''))$$,
         (select event_id from ev85), t85_cat('trucking')));
reset role;
select set_config('request.jwt.claim.sub', '', false);

select t_eq('השורה לא נמחקה — היא חזרה ל-3300',
  t85_income(),
  'furniture_old=1200.00/1200.00/false,trucking=3300.00/3300.00/false');


drop function t85_envelope(text, text, numeric, numeric);
drop function t85_ingest(text, int, numeric, numeric);
drop function t85_income();
drop function t85_line();
drop function t85_cat(text);
