\pset tuples_only on
\pset format unaligned

-- ===========================================================================
-- ‏78: הובלות ולוגיסטיקה אינן מסונכרנות מ-ViperFlow (0237).
--
-- החבילה מקימה לקוח, חיבור, מנהל מערכת (מקבל ההתראות), רכז עם מפתח הזנת
-- הכנסות, והזמנה משלה ב-2031-08-15. היא משאירה אחריה את מה שיצרה.
--
--   * ‏**בלידה** — אין כמות משאיות, אין כמות עובדים, אין מחיר משימה ואין
--     "הובלות". הריהוט נכתב כרגיל, והספירה נשמרת על הקישור בלבד.
--   * ‏**מה שהמשרד קבע נשאר** — עדכון, ועדכון כפוי, אינם נוגעים בכמויות,
--     במחיר הידני ובשורת "הובלות" שהוזנו ביד.
--   * ‏**ואינו נאמר** — שינוי של הלוגיסטיקה בלבד אינו מוציא התראה, ושינוי
--     מפרט מוציא התראה בלי שורות לוגיסטיקה.
--   * ‏**"הובלות" נפתחת לעריכה** באירוע שהסנכרון שלו רץ; הריהוט נשאר נעול.
-- ===========================================================================

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000078a1', 'vf78-admin@vl.test'),
  ('00000000-0000-0000-0000-0000000078a2', 'vf78-coord@vl.test');

insert into customers (id, name) values
  ('10000000-0000-0000-0000-000000000078', 'לקוח ריהוט 78');

insert into profiles (id, user_id, user_kind, is_admin, full_name) values
  ('20000000-0000-0000-0000-0000000078a1', '00000000-0000-0000-0000-0000000078a1',
   'staff', true, 'מנהל 78'),
  ('20000000-0000-0000-0000-0000000078a2', '00000000-0000-0000-0000-0000000078a2',
   'staff', false, 'רכז 78');

insert into user_permission_grants (profile_id, permission_key, allowed) values
  ('20000000-0000-0000-0000-0000000078a2', 'events.view', true),
  ('20000000-0000-0000-0000-0000000078a2', 'finance.income_edit', true);

insert into customer_income_splits (customer_id, category_id, viper_share_pct)
select '10000000-0000-0000-0000-000000000078', id,
       case name when 'ריהוט ישן' then 70 when 'ריהוט חדש' then 20 else 100 end
  from income_categories where name in ('ריהוט ישן', 'ריהוט חדש', 'הובלות');

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000078a1', false);
select t_expect_ok('החיבור נפתח',
  $$select viperflow_set_connection('10000000-0000-0000-0000-000000000078',
      'לקוח ריהוט 78 — ViperFlow', true)$$);
reset role;
select set_config('request.jwt.claim.sub', '', false);

create temporary table vf78 as
  select id as connection_id from viperflow_connections
   where customer_id = '10000000-0000-0000-0000-000000000078';
grant select on vf78 to authenticated;

create or replace function t78_envelope(p_evt text, p_updated text, p_type text,
                                        p_chairs int, p_trucks int, p_workers int)
returns jsonb language sql immutable as $$
  select jsonb_build_object(
    'id', 'evt_' || md5(p_evt),
    'type', p_type,
    'created_at', p_updated,
    'api_version', 'v1',
    'livemode', true,
    'origin', jsonb_build_object('source', 'app'),
    'data', jsonb_build_object(
      'id', '99999999-7878-4444-4444-000000000078',
      'object', 'order',
      'order_number', 'ORD-78-0001',
      'status', 'draft',
      'customer_name', 'משפחת אדלר',
      'event', jsonb_build_object('date', '2031-08-15', 'location', 'אולם התמר'),
      'delivery_date', '2031-08-14T05:00:00.000Z',
      'return_date', '2031-08-16T07:00:00.000Z',
      'notes', null,
      'catalog_enriched', true,
      'totals', jsonb_build_object('order_discount_percent', 0),
      'items', jsonb_build_array(
        jsonb_build_object(
          'id', '11111111-7878-4444-4444-000000000001', 'parent_item_id', null,
          'line_type', 'product', 'is_component', false, 'name', 'שולחן 78',
          'quantity', 10, 'spare_quantity', 0, 'is_custom', false, 'sort_order', 0,
          'line_total', 1000, 'options', '[]'::jsonb),
        jsonb_build_object(
          'id', '11111111-7878-4444-4444-000000000002', 'parent_item_id', null,
          'line_type', 'product', 'is_component', false, 'name', 'כיסא 78',
          'quantity', p_chairs, 'spare_quantity', 0, 'is_custom', false, 'sort_order', 1,
          'is_new', true, 'line_total', p_chairs * 10, 'options', '[]'::jsonb),
        jsonb_build_object(
          'id', '11111111-7878-4444-4444-000000000003', 'parent_item_id', null,
          'line_type', 'worker', 'is_component', false, 'name', 'סידור ואיסוף',
          'quantity', p_workers, 'spare_quantity', 0, 'is_custom', false, 'sort_order', 2,
          'line_total', p_workers * 500, 'options', '[]'::jsonb),
        jsonb_build_object(
          'id', '11111111-7878-4444-4444-000000000004', 'parent_item_id', null,
          'line_type', 'truck', 'is_component', false, 'name', 'הובלה',
          'quantity', p_trucks, 'spare_quantity', 0, 'is_custom', false, 'sort_order', 3,
          'line_total', p_trucks * 1000, 'options', '[]'::jsonb)),
      'created_at', p_updated,
      'updated_at', p_updated),
    'previous', null);
$$;

create or replace function t78_notes()
returns int language sql stable as $$
  select count(*)::int from notifications
   where recipient_id = '20000000-0000-0000-0000-0000000078a1'
     and type = 'viperflow_order_changed';
$$;


\echo '--- 1. הקטגוריה והחיבור ---'

select t_eq('"הובלות" אינה מקושרת עוד ל-ViperFlow',
  (select viperflow_income_source from income_categories
    where name = 'הובלות' and deleted_at is null), null::text);
select t_eq('ואף קטגוריה אינה מקבלת "trucking"',
  (select count(*)::int from income_categories where viperflow_income_source = 'trucking'), 0);


\echo '--- 2. לידה: בלי כמויות, בלי מחיר ובלי הובלות ---'

select t_eq('ההזמנה נולדה',
  (select viperflow_ingest(t78_envelope('78-birth', '2031-01-01T08:00:00.000Z',
                                        'order.created', 100, 2, 4),
     jsonb_build_object('connection_id', (select connection_id from vf78))) ->> 'status'),
  'processed');

create temporary table ev78 as
  select event_id from viperflow_links
   where order_id = '99999999-7878-4444-4444-000000000078';

select t_eq('אין כמות משאיות על האירוע',
  (select truck_count from events where id = (select event_id from ev78)), null::int);
select t_eq('שתי משימות נוצרו, ובשתיהן 0 עובדים',
  (select string_agg(t.worker_count::text, ',' order by tt.code)
     from tasks t join task_types tt on tt.id = t.task_type_id
    where t.event_id = (select event_id from ev78) and t.deleted_at is null),
  '0,0');
select t_eq('והתאריך והשעה כן נכתבו בלידה',
  (select t.task_date::text || ' ' || t.onsite_start_time::text
     from tasks t join task_types tt on tt.id = t.task_type_id
    where t.event_id = (select event_id from ev78) and tt.code = 'setup'),
  '2031-08-14 08:00:00');
select t_eq('אין מחיר משימה מההזמנה',
  (select count(*)::int from task_pricing tp join tasks t on t.id = tp.task_id
    where t.event_id = (select event_id from ev78) and tp.is_manual), 0);
select t_eq('אין שורת "הובלות"',
  (select count(*)::int from event_income ei
     join income_categories ic on ic.id = ei.category_id
    where ei.event_id = (select event_id from ev78) and ic.name = 'הובלות'), 0);
select t_eq('והריהוט נכתב כרגיל: ישן 1000, חדש 1000',
  (select string_agg(ic.name || '=' || ei.amount, ',' order by ic.name)
     from event_income ei join income_categories ic on ic.id = ei.category_id
    where ei.event_id = (select event_id from ev78)),
  'ריהוט חדש=1000.00,ריהוט ישן=1000.00');
select t_eq('הספירה נשמרת על הקישור בלבד — 2 משאיות, 4 עובדים',
  (select truck_quantity || '/' || worker_quantity from viperflow_links
    where event_id = (select event_id from ev78)), '2/4');
select t_eq('והצילום אינו נושא את הלוגיסטיקה',
  (select order_snapshot ?| array['trucks', 'workers', 'crew_price', 'trucking']
     from viperflow_links where event_id = (select event_id from ev78)), false);
select t_eq('והיומן אינו מזכיר הובלות או סידור',
  (select count(*)::int from event_activity
    where event_id = (select event_id from ev78) and kind = 'synced'
      and (note like '%הובלות%' or note like '%סידור ואיסוף%')), 0);


\echo '--- 3. המשרד קובע, וההזמנה אינה דורסת ---'

update events set truck_count = 5 where id = (select event_id from ev78);
update tasks set worker_count = 3 where event_id = (select event_id from ev78);
insert into task_pricing (task_id, price, is_manual)
select t.id, 1234, true from tasks t join task_types tt on tt.id = t.task_type_id
 where t.event_id = (select event_id from ev78) and tt.code = 'setup'
on conflict (task_id) do update set price = excluded.price, is_manual = true;
insert into event_income (event_id, category_id, amount, viper_share_pct)
select (select event_id from ev78), id, 900, 100 from income_categories
 where name = 'הובלות' and deleted_at is null;

create or replace function t78_office()
returns text language sql stable as $$
  select concat_ws(' | ',
    'trucks=' || (select truck_count from events where id = (select event_id from ev78)),
    'workers=' || (select string_agg(worker_count::text, ',' order by id) from tasks
                    where event_id = (select event_id from ev78) and deleted_at is null),
    'prices=' || (select string_agg(tp.price::text, ',') from task_pricing tp
                    join tasks t on t.id = tp.task_id where t.event_id = (select event_id from ev78)),
    'trucking=' || (select ei.amount from event_income ei
                      join income_categories ic on ic.id = ei.category_id
                     where ei.event_id = (select event_id from ev78) and ic.name = 'הובלות'));
$$;
grant select on ev78 to authenticated;

select t_eq('המצב שהמשרד קבע',
  t78_office(), 'trucks=5 | workers=3,3 | prices=1234.00 | trucking=900.00');

select t_eq('עדכון: מפרט, משאיות ועובדים זזו',
  (select viperflow_ingest(t78_envelope('78-update', '2031-01-02T08:00:00.000Z',
                                        'order.updated', 150, 3, 6),
     jsonb_build_object('connection_id', (select connection_id from vf78))) ->> 'status'),
  'processed');
select t_eq('ומה שהמשרד קבע לא זז',
  t78_office(), 'trucks=5 | workers=3,3 | prices=1234.00 | trucking=900.00');
select t_eq('אבל הריהוט החדש התעדכן: 150 כיסאות',
  (select ei.amount from event_income ei join income_categories ic on ic.id = ei.category_id
    where ei.event_id = (select event_id from ev78) and ic.name = 'ריהוט חדש'), 1500::numeric);
select t_eq('והקישור סופר את ההזמנה החדשה',
  (select truck_quantity || '/' || worker_quantity from viperflow_links
    where event_id = (select event_id from ev78)), '3/6');

select t_eq('יצאה התראה אחת — על המפרט',
  t78_notes(), 1);
select t_eq('והיא אומרת "השתנה מפרט" ואת הריהוט החדש',
  (select body like '%השתנה מפרט%' and body like '%ריהוט חדש: 1,500.00 ₪ (היה 1,000.00 ₪)%'
     from notifications
    where recipient_id = '20000000-0000-0000-0000-0000000078a1'
      and type = 'viperflow_order_changed'), true);
select t_eq('ובלי שורה אחת של לוגיסטיקה',
  (select body not like '%משאיות%' and body not like '%עובדים%'
      and body not like '%הקמה ופירוק%' and body not like '%הובלות%'
     from notifications
    where recipient_id = '20000000-0000-0000-0000-0000000078a1'
      and type = 'viperflow_order_changed'), true);


\echo '--- 4. שינוי של הלוגיסטיקה בלבד אינו שינוי ---'

select t_eq('עדכון שבו רק המשאיות והעובדים זזו',
  (select viperflow_ingest(t78_envelope('78-logistics', '2031-01-03T08:00:00.000Z',
                                        'order.updated', 150, 4, 8),
     jsonb_build_object('connection_id', (select connection_id from vf78))) ->> 'status'),
  'processed');
select t_eq('אינו מוציא התראה',
  t78_notes(), 1);
select t_eq('ואינו נוגע במשרד',
  t78_office(), 'trucks=5 | workers=3,3 | prices=1234.00 | trucking=900.00');

select t_eq('וגם force אינו מחזיר אותן',
  (select viperflow_ingest(t78_envelope('78-logistics', '2031-01-03T08:00:00.000Z',
                                        'order.updated', 150, 4, 8),
     jsonb_build_object('connection_id', (select connection_id from vf78),
                        'force', true)) ->> 'status'),
  'processed');
select t_eq('המשרד עדיין שלם',
  t78_office(), 'trucks=5 | workers=3,3 | prices=1234.00 | trucking=900.00');


\echo '--- 5. "הובלות" נערכת ביד גם כשהסנכרון רץ ---'

select t_eq('הסנכרון לאירוע רץ (לא נעול)',
  (select sync_locked_at is null from viperflow_links where event_id = (select event_id from ev78)),
  true);

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000078a2', false);
select t_expect_ok('הרכז משנה את "הובלות" ל-1100',
  $$select event_income_save((select event_id from ev78),
      jsonb_build_object((select id from income_categories
                           where name = 'הובלות' and deleted_at is null)::text, 1100))$$);
select t_expect_fail('אבל הריהוט החדש עדיין מגיע מ-ViperFlow',
  $$select event_income_save((select event_id from ev78),
      jsonb_build_object((select id from income_categories
                           where name = 'ריהוט חדש' and deleted_at is null)::text, 1))$$);
reset role;
select set_config('request.jwt.claim.sub', '', false);

select t_eq('הסכום שהרכז הזין נשמר',
  (select ei.amount from event_income ei join income_categories ic on ic.id = ei.category_id
    where ei.event_id = (select event_id from ev78) and ic.name = 'הובלות'), 1100::numeric);

drop function t78_office();
drop function t78_notes();
drop function t78_envelope(text, text, text, int, int, int);
