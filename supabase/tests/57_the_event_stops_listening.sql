\pset tuples_only on
\pset format unaligned

-- ===========================================================================
-- ‏57: אירוע יכול להפסיק להקשיב ל-ViperFlow (0204).
--
-- החבילה מקימה לקוח, חיבור, שלוש דמויות והזמנה משלה, ואינה נשענת על 49
-- (שמשאירה את ההזמנה שלה מבוטלת). האירוע יושב ב-2031-05-15, מעבר לכל טווח
-- אחר. היא משאירה אחריה אירוע, משימות, שורות ריהוט ומשלוחים שאינם מנוקים.
--
--   * ‏**נעילה** — רק מי שמחזיק `integrations.manage`, והיא נראית ב-view.
--   * ‏**כלום לא זז** — עדכון, משיכה כפויה וביטול: לא משאיות, לא עובדים, לא
--     שעות, לא מחיר, לא הכנסות, לא ריהוט, לא סטטוס ולא הצילום. המשלוח נשמר
--     ונרשם "לא רלוונטי" עם הסיבה.
--   * ‏**שחרור משלים** — המשלוח האחרון שנדחה מוחל, והסנכרון חוזר לעבוד.
-- ===========================================================================

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000057a1', 'vf57-ops@vl.test'),
  ('00000000-0000-0000-0000-0000000057a2', 'vf57-coord@vl.test');

insert into customers (id, name) values
  ('10000000-0000-0000-0000-000000000057', 'לקוח ריהוט 57');

insert into profiles (id, user_id, user_kind, is_admin, full_name) values
  -- מנהל אינטגרציות: הוא שעוצר ומחדש
  ('20000000-0000-0000-0000-0000000057a1', '00000000-0000-0000-0000-0000000057a1',
   'staff', false, 'מנהל אינטגרציות 57'),
  -- רכז: עורך אירועים, ואינו רשאי לעצור סנכרון
  ('20000000-0000-0000-0000-0000000057a2', '00000000-0000-0000-0000-0000000057a2',
   'staff', false, 'רכז 57');

insert into user_permission_grants (profile_id, permission_key, allowed) values
  ('20000000-0000-0000-0000-0000000057a1', 'integrations.view', true),
  ('20000000-0000-0000-0000-0000000057a1', 'integrations.manage', true),
  ('20000000-0000-0000-0000-0000000057a1', 'events.view', true),
  ('20000000-0000-0000-0000-0000000057a2', 'events.view', true),
  ('20000000-0000-0000-0000-0000000057a2', 'events.edit', true),
  ('20000000-0000-0000-0000-0000000057a2', 'integrations.view', false),
  ('20000000-0000-0000-0000-0000000057a2', 'integrations.manage', false);

insert into customer_income_splits (customer_id, category_id, viper_share_pct)
select '10000000-0000-0000-0000-000000000057', id,
       case name when 'ריהוט ישן' then 70 when 'ריהוט חדש' then 20 else 100 end
  from income_categories where name in ('ריהוט ישן', 'ריהוט חדש', 'הובלות');

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000057a1', false);
select t_expect_ok('החיבור נפתח',
  $$select viperflow_set_connection('10000000-0000-0000-0000-000000000057',
      'לקוח ריהוט 57 — ViperFlow', true)$$);
reset role;
select set_config('request.jwt.claim.sub', '', false);

create temporary table vf57 as
  select id as connection_id from viperflow_connections
   where customer_id = '10000000-0000-0000-0000-000000000057';
grant select on vf57 to authenticated;

-- מעטפה של ההזמנה של החבילה הזו. ‏`p_evt` עובר דרך md5 כדי שכל משלוח יקבל
-- מזהה ייחודי בפורמט של ViperFlow בלי להתנגש במזהים של 49.
create or replace function t57_envelope(p_evt text, p_updated text, p_type text, p_status text,
                                        p_chairs int, p_trucks int, p_workers int,
                                        p_delivery text default '2031-05-14T05:00:00.000Z')
returns jsonb language sql immutable as $$
  select jsonb_build_object(
    'id', 'evt_' || md5(p_evt),
    'type', p_type,
    'created_at', p_updated,
    'api_version', 'v1',
    'livemode', true,
    'origin', jsonb_build_object('source', 'app'),
    'data', jsonb_build_object(
      'id', '99999999-5757-4444-4444-000000000057',
      'object', 'order',
      'order_number', 'ORD-57-0001',
      'status', p_status,
      'customer_name', 'משפחת לוי',
      'event', jsonb_build_object('date', '2031-05-15', 'location', 'אולם הגפן'),
      'delivery_date', p_delivery,
      'return_date', '2031-05-16T07:00:00.000Z',
      'notes', null,
      'catalog_enriched', true,
      'totals', jsonb_build_object('order_discount_percent', 0),
      'items', jsonb_build_array(
        jsonb_build_object(
          'id', '11111111-5757-4444-4444-000000000001', 'parent_item_id', null,
          'line_type', 'product', 'is_component', false, 'name', 'שולחן 57',
          'quantity', 10, 'spare_quantity', 0, 'is_custom', false, 'sort_order', 0,
          'line_total', 1000, 'options', '[]'::jsonb),
        jsonb_build_object(
          'id', '11111111-5757-4444-4444-000000000002', 'parent_item_id', null,
          'line_type', 'product', 'is_component', false, 'name', 'כיסא 57',
          'quantity', p_chairs, 'spare_quantity', 0, 'is_custom', false, 'sort_order', 1,
          'is_new', true, 'line_total', p_chairs * 10, 'options', '[]'::jsonb),
        jsonb_build_object(
          'id', '11111111-5757-4444-4444-000000000003', 'parent_item_id', null,
          'line_type', 'worker', 'is_component', false, 'name', 'סידור ואיסוף',
          'quantity', p_workers, 'spare_quantity', 0, 'is_custom', false, 'sort_order', 2,
          'line_total', p_workers * 500, 'options', '[]'::jsonb),
        jsonb_build_object(
          'id', '11111111-5757-4444-4444-000000000004', 'parent_item_id', null,
          'line_type', 'truck', 'is_component', false, 'name', 'הובלה',
          'quantity', p_trucks, 'spare_quantity', 0, 'is_custom', false, 'sort_order', 3,
          'line_total', p_trucks * 1000, 'options', '[]'::jsonb)),
      'created_at', p_updated,
      'updated_at', p_updated),
    'previous', null);
$$;

-- כל מה שהסנכרון עשוי לגעת בו, בשורה אחת. אם משהו זז — המחרוזת משתנה.
create or replace function t57_state()
returns text language sql stable as $$
  select concat_ws(' | ',
    'trucks=' || e.truck_count,
    'status=' || s.code,
    'setup=' || (select string_agg(t.task_date || ' ' || coalesce(t.onsite_start_time::text, '') || ' w' || t.worker_count, ',' order by tt.code)
                   from tasks t join task_types tt on tt.id = t.task_type_id
                  where t.event_id = e.id and t.deleted_at is null),
    'prices=' || (select string_agg(tp.price::text, ',' order by tp.price)
                    from task_pricing tp join tasks t on t.id = tp.task_id
                   where t.event_id = e.id),
    'income=' || (select string_agg(ic.viperflow_income_source || ':' || ei.amount, ',' order by ic.viperflow_income_source)
                    from event_income ei join income_categories ic on ic.id = ei.category_id
                   where ei.event_id = e.id),
    'items=' || (select string_agg(i.name || ':' || i.quantity, ',' order by i.position)
                   from viperflow_order_items i where i.event_id = e.id),
    'link=' || (select l.order_status || '/' || l.order_updated_at || '/' || md5(l.order_snapshot::text)
                  from viperflow_links l where l.event_id = e.id))
  from events e join statuses s on s.id = e.status_id
  where e.id = (select event_id from viperflow_links
                 where order_id = '99999999-5757-4444-4444-000000000057');
$$;


\echo '--- 1. ההזמנה נולדת ---'

select t_eq('המעטפה הראשונה הוחלה',
  (select viperflow_ingest(
     t57_envelope('57-birth', '2031-01-01T08:00:00.000Z', 'order.created', 'draft', 100, 2, 4),
     jsonb_build_object('connection_id', (select connection_id from vf57))) ->> 'status'),
  'processed');

create temporary table ev57 as
  select event_id from viperflow_links where order_id = '99999999-5757-4444-4444-000000000057';
grant select on ev57 to authenticated;

select t_eq('נוצר אירוע אחד', (select count(*)::int from ev57), 1);
select t_eq('שתי משאיות', (select truck_count from events where id = (select event_id from ev57)), 2);

create temporary table before57 as select t57_state() as state;


\echo '--- 2. מי עוצר ---'

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000057a2', false);
select t_expect_fail('רכז אינו עוצר סנכרון',
  $$select viperflow_set_event_lock((select event_id from ev57), true)$$);
select t_eq('ורואה שהאירוע אינו נעול',
  (select sync_locked_at is null from viperflow_event_link where event_id = (select event_id from ev57)),
  true);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000057a1', false);
select t_eq('מנהל האינטגרציות עוצר',
  (select (viperflow_set_event_lock((select event_id from ev57), true) ->> 'locked')::boolean),
  true);
select t_eq('עצירה שנייה אינה כותבת שורת יומן נוספת',
  (select (viperflow_set_event_lock((select event_id from ev57), true) ->> 'locked')::boolean),
  true);
select t_expect_fail('אירוע שלא הגיע מ-ViperFlow אינו ננעל',
  $$select viperflow_set_event_lock(gen_random_uuid(), true)$$);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000057a2', false);
select t_eq('הרכז רואה ב-view שהאירוע נעול',
  (select sync_locked_at is not null from viperflow_event_link where event_id = (select event_id from ev57)),
  true);
reset role;
select set_config('request.jwt.claim.sub', '', false);

select t_eq('נרשמה שורת יומן אחת של עצירה, בשם מי שעצר',
  (select count(*)::int || ':' || min(actor_name) from event_activity
    where event_id = (select event_id from ev57) and kind = 'sync_locked'),
  '1:מנהל אינטגרציות 57');


\echo '--- 3. כל עוד הוא נעול — כלום לא זז ---'

-- ביטול, ואחריו עדכון שמשנה הכול: כמויות, מחירים, ריהוט והשעה.
select t_eq('ביטול נדחה כנעול',
  (select viperflow_ingest(
     t57_envelope('57-cancel', '2031-01-02T08:00:00.000Z', 'order.cancelled', 'cancelled', 100, 2, 4),
     jsonb_build_object('connection_id', (select connection_id from vf57))) ->> 'status'),
  'locked');

select t_eq('עדכון נדחה כנעול',
  (select viperflow_ingest(
     t57_envelope('57-update', '2031-01-03T08:00:00.000Z', 'order.updated', 'confirmed', 150, 3, 6,
                  '2031-05-14T09:30:00.000Z'),
     jsonb_build_object('connection_id', (select connection_id from vf57))) ->> 'status'),
  'locked');

select t_eq('גם משיכה כפויה נדחית',
  (select viperflow_ingest(
     t57_envelope('57-update', '2031-01-03T08:00:00.000Z', 'order.updated', 'confirmed', 150, 3, 6,
                  '2031-05-14T09:30:00.000Z'),
     jsonb_build_object('connection_id', (select connection_id from vf57), 'force', true)) ->> 'status'),
  'locked');

select t_eq('המשלוחים נשמרו כ"לא רלוונטי" עם הסיבה',
  (select string_agg(distinct status || ':' || reason, ',') from viperflow_deliveries
    where event_id in ('evt_' || md5('57-cancel'), 'evt_' || md5('57-update'))),
  'ignored:הסנכרון לאירוע הזה נעצר — ההזמנה נשמרה ולא הוחלה');

select t_eq('שום דבר באירוע לא השתנה — משאיות, סטטוס, שעות, עובדים, מחירים, הכנסות, ריהוט וקישור',
  t57_state(), (select state from before57));

select t_eq('ולא נרשמה שורת סנכרון ביומן מאז הלידה',
  (select count(*)::int from event_activity
    where event_id = (select event_id from ev57) and kind = 'synced'),
  1);

select t_eq('ולא יצאה התראה על שינוי בהזמנה',
  (select count(*)::int from notifications
    where type = 'viperflow_order_changed'
      and entity_id = (select event_id from ev57)),
  0);


\echo '--- 4. שחרור — והשינויים שהוחמצו מוחלים ---'

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000057a2', false);
select t_expect_fail('רכז אינו מחדש סנכרון',
  $$select viperflow_set_event_lock((select event_id from ev57), false)$$);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000057a1', false);
select t_eq('מנהל האינטגרציות מחדש, וההשלמה רצה',
  (select (viperflow_set_event_lock((select event_id from ev57), false) ->> 'caught_up')::boolean),
  true);
reset role;
select set_config('request.jwt.claim.sub', '', false);

select t_eq('הקישור אינו נעול עוד',
  (select sync_locked_at is null from viperflow_links where event_id = (select event_id from ev57)),
  true);

-- המשלוח האחרון לפי חותמת ההזמנה הוא העדכון (03/01), לא הביטול (02/01).
select t_eq('העדכון האחרון הוחל: שלוש משאיות',
  (select truck_count from events where id = (select event_id from ev57)), 3);
select t_eq('ושישה עובדים בשתי המשימות',
  (select string_agg(distinct worker_count::text, ',') from tasks
    where event_id = (select event_id from ev57) and deleted_at is null),
  '6');
select t_eq('ו-150 כיסאות במפרט',
  (select quantity from viperflow_order_items
    where event_id = (select event_id from ev57) and name = 'כיסא 57'),
  150.00::numeric(12,2));
select t_eq('והאירוע לא בוטל — הביטול קדם לעדכון',
  (select s.code from events e join statuses s on s.id = e.status_id
    where e.id = (select event_id from ev57)) <> 'cancelled',
  true);
select t_eq('המשלוח שהוחל רשום כמעובד',
  (select status from viperflow_deliveries where event_id = 'evt_' || md5('57-update')),
  'processed');
select t_eq('נרשמה שורת יומן של חידוש',
  (select count(*)::int from event_activity
    where event_id = (select event_id from ev57) and kind = 'sync_unlocked'),
  1);

select t_eq('ומשלוח חדש מוחל כרגיל',
  (select viperflow_ingest(
     t57_envelope('57-after', '2031-01-04T08:00:00.000Z', 'order.updated', 'confirmed', 160, 4, 6,
                  '2031-05-14T09:30:00.000Z'),
     jsonb_build_object('connection_id', (select connection_id from vf57))) ->> 'status'),
  'processed');
select t_eq('ארבע משאיות',
  (select truck_count from events where id = (select event_id from ev57)), 4);


\echo '--- 5. שחרור בלי שהגיע דבר — אין מה להשלים ---'

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000057a1', false);
select t_eq('עצירה',
  (select (viperflow_set_event_lock((select event_id from ev57), true) ->> 'locked')::boolean), true);
select t_eq('וחידוש מיד — בלי השלמה',
  (select (viperflow_set_event_lock((select event_id from ev57), false) ->> 'caught_up')::boolean), false);
reset role;
select set_config('request.jwt.claim.sub', '', false);

select t_eq('ארבע משאיות עדיין',
  (select truck_count from events where id = (select event_id from ev57)), 4);


\echo '--- 6. משלוח שנכנס רגע לפני הנעילה — והשחרור עדיין משלים אותו (0206) ---'

-- המצב שהבדיקה מדמה: טרנזקציית ה-Webhook התחילה (ולכן `received_at` שלה
-- נקבע) לפני שהנעילה נשמרה, חיכתה על נעילת-הייעוץ, ונדחתה כ"נעולה" רק אחרי
-- שהנעילה נשמרה. ‏0204 בחר לפי `received_at >= sync_locked_at` ודילג עליה.

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000057a1', false);
select t_eq('עצירה',
  (select (viperflow_set_event_lock((select event_id from ev57), true) ->> 'locked')::boolean), true);
reset role;
select set_config('request.jwt.claim.sub', '', false);

select t_eq('עדכון שנדחה כנעול',
  (select viperflow_ingest(
     t57_envelope('57-race', '2031-01-05T08:00:00.000Z', 'order.updated', 'confirmed', 170, 5, 6,
                  '2031-05-14T09:30:00.000Z'),
     jsonb_build_object('connection_id', (select connection_id from vf57))) ->> 'status'),
  'locked');

update viperflow_deliveries
   set received_at = (select sync_locked_at from viperflow_links
                       where event_id = (select event_id from ev57)) - interval '1 second'
 where event_id = 'evt_' || md5('57-race');

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000057a1', false);
select t_eq('השחרור מוצא אותו למרות זמן ההגעה המוקדם',
  (select (viperflow_set_event_lock((select event_id from ev57), false) ->> 'caught_up')::boolean), true);
reset role;
select set_config('request.jwt.claim.sub', '', false);

select t_eq('והעדכון הוחל: חמש משאיות',
  (select truck_count from events where id = (select event_id from ev57)), 5);

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000057a1', false);
select t_eq('ומחזור נעילה נוסף בלי משלוחים חדשים אינו מחיל שוב משלוח ישן',
  (select (viperflow_set_event_lock((select event_id from ev57), true) ->> 'locked')::boolean
          and not (viperflow_set_event_lock((select event_id from ev57), false) ->> 'caught_up')::boolean),
  true);
reset role;
select set_config('request.jwt.claim.sub', '', false);
