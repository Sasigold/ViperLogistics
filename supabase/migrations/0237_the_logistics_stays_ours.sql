-- 0237: ההובלות והלוגיסטיקה אינן מסונכרנות מ-ViperFlow
--
-- הבקשה, במילים של הבעלים: "תעשה שבסנכרון בין viper flow למערכת אז הובלות
-- ולוגיסטיקה לא מסתנכרן." ובשאלת ההבהרה: הכול — כסף וכמויות; ומה שכבר נכתב
-- נשאר כמו שהוא.
--
-- עד היום שתי שורות הלוגיסטיקה של ההזמנה (0187, 0192) נכתבו אצלנו:
--
--   • ‏**"הובלה"** — כמות המשאיות של האירוע (`events.truck_count`), וסכומה
--     לסעיף ההכנסה **"הובלות"** (`viperflow_income_source = 'trucking'`);
--   • ‏**"סידור ואיסוף"** — כמות העובדים בהקמה ובפירוק (`tasks.worker_count`),
--     וסכומה מחולק בשניים כמחיר ידני של שתי המשימות (`task_pricing`).
--
-- מעכשיו אף אחד מהם אינו נכתב — לא בלידה ולא בעדכון, וגם `force` אינו מחזיר
-- אותם. הם של המשרד, כמו השיבוץ והשעות אחרי הלידה (0190):
--
--   1. **המתרגם** (`app.viperflow_apply_order`, גוף 0213) אינו כותב את כמות
--      המשאיות, את כמות העובדים, את מחיר ההקמה והפירוק ואת ההובלות. בלידה
--      נוצרים האירוע ושתי המשימות עם התאריך והשעה, בלי כמויות ובלי מחיר.
--   2. **ההתראה "ההזמנה השתנתה"** אינה מדווחת עליהם עוד: הם יצאו מהצילום
--      (`order_snapshot`), וצד חסר בהשוואה הוא "לא ידוע" ולא שינוי (0190 §4) —
--      ולכן גם הסנכרון הראשון אחרי המיגרציה, מול צילום ישן שעוד נושא אותם,
--      שקט.
--   3. **הקטגוריה "הובלות" אינה מקושרת עוד ל-ViperFlow**
--      (`viperflow_income_source = null`). הנעילה של 0212 ("הסכום מגיע
--      מ-ViperFlow") נשענת על העמודה הזו — בטופס האירוע, בכרטיס התשלומים
--      וב-`app.apply_event_income` — ולכן היא נפתחת לעריכה ידנית בכל אירוע,
--      בלי לגעת באף אחת מהן.
--   4. **מקור המחיר בחיבור** עובר ל-"none" ("אל תסנכרן מחיר"). המתרגם כבר
--      אינו קורא אותו; זה רק כדי שהשורה תגיד את מה שקורה. הבורר יורד מהמסך.
--
-- מה **שנשאר**:
--
--   • **כל מה שכבר נכתב** — כמויות, מחירי משימות (נשארים ידניים, `is_manual`)
--     ושורות "הובלות" באירועים קיימים. בלי מחיקה ובלי איפוס.
--   • **הספירה על הקישור** (`viperflow_links.truck_quantity/worker_quantity`,
--     0194) — היא הכיתוב "בהזמנה: 2 משאיות · 4 עובדים" שמתחת לרשימת הריהוט
--     (0193): מה שההזמנה אומרת, לעיני הרכז, ולא שדה שלנו. רשימות השמות של
--     החיבור קובעות אותה כמו קודם.
--   • הריהוט, הכיסאות, הפריטים החופשיים, הסטטוס, הביטול והמפרט — בלי שינוי.

-- ===== 1. "הובלות" אינה מקבלת עוד מ-ViperFlow ===============================

update income_categories set viperflow_income_source = null
 where viperflow_income_source = 'trucking';

comment on column income_categories.viperflow_income_source is
  'מאיזה סכום בהזמנת ViperFlow הקטגוריה מקבלת: furniture_old/furniture_new = ריהוט לפי הקטלוג, '
  'furniture_chairs = הכיסאות, furniture_custom = הפריטים החופשיים. '
  'trucking נשאר מותר אך אינו נכתב מאז 0237 — ההובלות של המשרד. '
  'null = אינה מקבלת (0192, 0212, 0213, 0237).';

-- ===== 2. מקור המחיר בחיבור: "אל תסנכרן" ===================================

update viperflow_connections set logistics_price_source = 'none'
 where logistics_price_source is distinct from 'none';

comment on column viperflow_connections.logistics_price_source is
  'אינו נקרא מאז 0237: מחיר ההקמה והפירוק אינו מסונכרן מההזמנה.';

-- ===== 3. המתרגם: בלי משאיות, עובדים, מחיר משימה והובלות ==================
-- גוף 0213, פחות ארבעת אלה. הכמויות עדיין נספרות — לקישור בלבד (0194).

create or replace function app.viperflow_apply_order(
  p_connection uuid,
  p_order      jsonb,
  p_event_type text,
  p_force      boolean default false)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_conn        viperflow_connections;
  v_link        viperflow_links;
  v_order_id    uuid;
  v_updated     timestamptz;
  v_event_id    uuid;
  v_created     boolean := false;
  v_status      text;
  v_status_id   uuid;
  v_event_date  date;
  v_location    text;
  v_number      text;
  v_trucks      numeric;
  v_workers     numeric;
  v_delivery    timestamp;
  v_return      timestamp;
  v_items       int := 0;
  v_note        text;
  v_parts       text[] := '{}';
  v_sys         boolean := app.in_system_write();
  v_current     text;
  v_setup       uuid;
  v_teardown    uuid;
  v_catalog     boolean;
  v_discount    numeric;
  v_old_amount  numeric;
  v_new_amount  numeric;
  v_cats        boolean;
  v_ch_on       boolean;
  v_split       boolean;
  v_chairs      numeric;
  v_free_on     boolean;
  v_free        numeric;
  v_bucket      jsonb;
  v_alerts      jsonb := '[]'::jsonb;
  v_alert       jsonb;
  v_snapshot    jsonb;
  v_changes     text[] := '{}';
begin
  select * into v_conn from viperflow_connections
   where id = p_connection and is_active and deleted_at is null;
  if v_conn.id is null then raise exception 'חיבור ViperFlow אינו פעיל'; end if;

  if coalesce(p_order ->> 'id', '') !~* '^[0-9a-f-]{36}$' then
    raise exception 'מעטפה בלי מזהה הזמנה';
  end if;
  v_order_id := (p_order ->> 'id')::uuid;
  v_updated  := nullif(p_order ->> 'updated_at', '')::timestamptz;
  v_status   := nullif(p_order ->> 'status', '');
  v_number   := nullif(btrim(p_order ->> 'order_number'), '');

  -- נעילה פר-הזמנה, לפני קריאת הקישור (0177 §4).
  perform pg_advisory_xact_lock(
    hashtextextended(p_connection::text || ':' || v_order_id::text, 0));

  select * into v_link from viperflow_links
   where connection_id = p_connection and order_id = v_order_id;

  -- ‏0204: אירוע שנעול לסנכרון אינו שומע דבר — לא כסף, לא כמויות, לא שעות,
  -- לא מפרט ולא ביטול. לפני שומר החותמת במכוון: גם `force` אינו עוקף את זה.
  -- הקישור עצמו אינו מתעדכן (גם לא `order_updated_at`), כדי ששחרור הנעילה
  -- יוכל להחיל את המשלוח האחרון כחדש ולא כ"ישן".
  if v_link.event_id is not null and v_link.sync_locked_at is not null then
    return jsonb_build_object('status', 'locked', 'event_id', v_link.event_id,
      'reason', 'הסנכרון לאירוע הזה נעצר — ההזמנה נשמרה ולא הוחלה');
  end if;

  -- משלוח שנושא חותמת ישנה ממה שכבר הוחל אינו מתקדם.
  if not coalesce(p_force, false)
     and v_link.event_id is not null
     and v_link.order_updated_at is not null
     and v_updated is not null
     and v_updated < v_link.order_updated_at then
    return jsonb_build_object('status', 'stale', 'event_id', v_link.event_id);
  end if;

  -- ── ביטול ומחיקה: אין מה לתרגם, יש מה לכבות ─────────────────────────────
  if p_event_type = 'order.deleted' or v_status = 'cancelled' then
    if v_link.event_id is null then
      return jsonb_build_object('status', 'ignored', 'reason', 'הזמנה שבוטלה ואינה מקושרת');
    end if;
    select id into v_status_id from statuses
     where entity = 'event' and code = 'cancelled' and deleted_at is null limit 1;

    if v_status_id is not null then
      perform app.system_write(true);
      update events set status_id = v_status_id
       where id = v_link.event_id and status_id is distinct from v_status_id;
      if not v_sys then perform app.system_write(false); end if;
    end if;

    update viperflow_links set
      order_status     = coalesce(v_status, 'deleted'),
      order_number     = coalesce(v_number, order_number),
      order_updated_at = coalesce(v_updated, order_updated_at),
      last_synced_at   = now()
     where event_id = v_link.event_id;

    insert into event_activity (event_id, kind, actor_name, note)
    values (v_link.event_id, 'synced', 'ViperFlow',
            (case when p_event_type = 'order.deleted'
                  then 'ההזמנה נמחקה ב-ViperFlow'
                  else 'ההזמנה בוטלה ב-ViperFlow' end)
            || (case when v_status_id is null
                     then ' — אין סטטוס "בוטל" בקטלוג, והאירוע נשאר כפי שהוא'
                     else ' — האירוע סומן כמבוטל' end));

    -- ביטול הוא שינוי, והוא הראשון שצריך לשמוע עליו.
    perform app.viperflow_notify_change(v_link.event_id, v_conn.customer_id, v_number,
      array[case when p_event_type = 'order.deleted'
                 then 'ההזמנה נמחקה ב-ViperFlow'
                 else 'ההזמנה בוטלה ב-ViperFlow' end]);

    return jsonb_build_object('status', 'processed', 'event_id', v_link.event_id,
                              'cancelled', true);
  end if;

  -- ── מה שההזמנה אומרת ────────────────────────────────────────────────────
  --
  -- ‏0192: הכמויות נספרות משורה ששמה הוגדר לחיבור בלבד. שורת פיקוח אינה
  -- עובד שעולה על המשאית, ושורת "תוספת" אינה משאית.
  -- ‏0237: הן נספרות עדיין, אבל רק לקישור (הכיתוב שמתחת לרשימת הריהוט,
  -- 0193–0194) — לאירוע ולמשימות הן אינן נכתבות עוד.
  v_event_date := nullif(p_order #>> '{event,date}', '')::date;
  v_location   := nullif(btrim(p_order #>> '{event,location}'), '');
  v_trucks     := app.viperflow_named_quantity(p_order -> 'items', 'truck', v_conn.trucking_line_names);
  v_workers    := app.viperflow_named_quantity(p_order -> 'items', 'worker', v_conn.crew_line_names);
  v_delivery   := app.viperflow_local(p_order ->> 'delivery_date');
  v_return     := app.viperflow_local(p_order ->> 'return_date');
  v_note       := nullif(btrim(p_order ->> 'notes'), '');

  if v_event_date is null then
    raise exception 'הזמנה % בלי תאריך אירוע', coalesce(v_number, v_order_id::text);
  end if;

  -- ‏`catalog_enriched` מורם בפונקציית הקצה אחרי שהיא שאלה את הקטלוג על כל
  -- מוצר. בלעדיו אין לנו דעה על חדש/ישן, ומחירי הריהוט אינם נכתבים כלל.
  -- ההובלה אינה תלויה בקטלוג: היא שורת הזמנה, וסכומה עובר תמיד.
  v_catalog := coalesce((p_order ->> 'catalog_enriched')::boolean, false);

  -- ‏0192: הנחת ההזמנה חלה על הריהוט בלבד — לא על ההובלה ולא על הסידור —
  -- ולכן היא מוכפלת בסכומי הריהוט כאן בלבד.
  -- השאר מגיע כבר נקי: `line_total` של ViperFlow מגלם את הנחת השורה.
  -- ערך מחוץ ל-0‏–100 הוא נתון פגום, ומוטב להתעלם ממנו מלהכפיל בו כסף.
  v_discount := coalesce((p_order #>> '{totals,order_discount_percent}')::numeric, 0);
  if v_discount < 0 or v_discount > 100 then v_discount := 0; end if;

  -- ‏0212: ‏`categories_enriched` מורם כשפונקציית הקצה קראה גם את עץ
  -- הקטגוריות, ואז כל שורת ריהוט נושאת את שמות הקטגוריה שלה ושל אבותיה. שורה
  -- שהקטגוריה שלה ברשימת הכיסאות של החיבור יוצאת מהישן ומהחדש ונספרת לבד.
  -- ההנחה חלה על הכיסאות כמו על כל שורת ריהוט.
  --
  -- הפיצול קורה רק כשיש לו לאן לנחות: עץ הקטגוריות ידוע, רשימת הכיסאות של
  -- החיבור אינה ריקה, וקטגוריית הכיסאות מופעלת ללקוח. בכל מקרה אחר — מעטפה
  -- ישנה, רשימה ריקה, לקוח בלי כיסאות — הכיסאות נשארים בישן ובחדש כמו לפני
  -- 0212, ושום כסף אינו נעלם בדרך.
  v_cats := v_catalog and coalesce((p_order ->> 'categories_enriched')::boolean, false);
  v_ch_on := exists (
    select 1 from customer_income_splits s
      join income_categories ic on ic.id = s.category_id
     where s.customer_id = v_conn.customer_id
       and ic.viperflow_income_source = 'furniture_chairs'
       and ic.is_active and ic.deleted_at is null);
  v_split := v_cats and v_ch_on and coalesce(cardinality(v_conn.chairs_category_names), 0) > 0;

  -- ‏0213: הפריטים החופשיים — שורה שהוקלדה ביד, בלי מוצר בקטלוג. היא מסומנת
  -- על השורה עצמה (`is_custom`), ולכן אינה תלויה בעץ הקטגוריות ולא ברשימה של
  -- החיבור; רק בכך שהקטגוריה מופעלת ללקוח. פריט חופשי אינו בקטלוג, ולכן
  -- תמיד "ישן" ואף פעם לא כיסא — הוא יוצא מהישן בלבד.
  v_free_on := exists (
    select 1 from customer_income_splits s
      join income_categories ic on ic.id = s.category_id
     where s.customer_id = v_conn.customer_id
       and ic.viperflow_income_source = 'furniture_custom'
       and ic.is_active and ic.deleted_at is null);

  if v_catalog then
    v_old_amount := round((app.viperflow_furniture_amount(p_order -> 'items', false,
      case when v_split then v_conn.chairs_category_names end)
      - case when v_free_on then app.viperflow_custom_amount(p_order -> 'items',
               case when v_split then v_conn.chairs_category_names end) else 0 end)
      * (1 - v_discount / 100), 2);
    v_new_amount := round(app.viperflow_furniture_amount(p_order -> 'items', true,
      case when v_split then v_conn.chairs_category_names end) * (1 - v_discount / 100), 2);
    v_chairs := case when v_split
      then round(app.viperflow_chairs_amount(p_order -> 'items', v_conn.chairs_category_names)
                 * (1 - v_discount / 100), 2) end;
    v_free := case when v_free_on
      then round(app.viperflow_custom_amount(p_order -> 'items',
                 case when v_split then v_conn.chairs_category_names end)
                 * (1 - v_discount / 100), 2) end;
  end if;

  perform app.system_write(true);

  if v_link.event_id is null then
    -- ── לידה ────────────────────────────────────────────────────────────────
    if exists (
      select 1 from viperflow_deliveries d
       where d.connection_id = p_connection
         and d.entity_id = v_order_id::text
         and d.event_type in ('order.deleted', 'order.cancelled')
         and d.status in ('processed', 'ignored'))
    then
      if not v_sys then perform app.system_write(false); end if;
      return jsonb_build_object('status', 'ignored',
        'reason', 'ההזמנה כבר נמחקה או בוטלה ב-ViperFlow — אירוע אינו נוצר בדיעבד');
    end if;

    insert into events (customer_id, end_client_name, event_number, event_date,
                        location_text, notes, truck_count, status_id, created_by)
    values (v_conn.customer_id,
            nullif(btrim(p_order ->> 'customer_name'), ''),
            case when v_number is not null and not exists (
                   select 1 from events e
                    where e.customer_id = v_conn.customer_id
                      and e.event_number = v_number and e.deleted_at is null)
                 then v_number end,
            v_event_date,
            v_location,
            v_note,
            null,
            (select id from statuses where entity = 'event' and is_default and deleted_at is null limit 1),
            null)
    returning id into v_event_id;
    v_created := true;

    insert into viperflow_links (event_id, connection_id, order_id, order_number,
                                 order_status, order_updated_at)
    values (v_event_id, p_connection, v_order_id, v_number, v_status, v_updated);

    v_parts := v_parts || ('נוצר מהזמנה ' || coalesce(v_number, v_order_id::text));
    if v_number is not null and not exists (
         select 1 from events e where e.id = v_event_id and e.event_number = v_number) then
      v_parts := v_parts || ('מספר האירוע ' || v_number || ' כבר תפוס — נשאר ריק');
    end if;
  else
    -- ── עדכון: כבר לא כמות משאיות (0237) ────────────────────────────────────
    --
    -- ‏`event_number` הוא היחיד, והוא אינו סנכרון אלא השלמה: הוא נכתב
    -- רק כשהוא ריק אצלנו ופנוי אצל הלקוח, ולכן אין בו מה לדרוס.
    v_event_id := v_link.event_id;

    update events set
      event_number = case
        when event_number is null and v_number is not null and not exists (
               select 1 from events e2
                where e2.customer_id = events.customer_id
                  and e2.event_number = v_number and e2.deleted_at is null)
        then v_number else event_number end
     where id = v_event_id;

    update viperflow_links set
      order_number     = coalesce(v_number, order_number),
      order_status     = coalesce(v_status, order_status),
      order_updated_at = coalesce(v_updated, order_updated_at),
      last_synced_at   = now()
     where event_id = v_event_id;
  end if;

  -- ── הסטטוס: קדימה בלבד (0177 §2) ────────────────────────────────────────
  select s.code into v_current from events e
    join statuses s on s.id = e.status_id where e.id = v_event_id;

  if v_status in ('confirmed', 'picked', 'delivered', 'returned')
     and v_current = 'pending' then
    select id into v_status_id from statuses
     where entity = 'event' and code = 'approved' and deleted_at is null limit 1;
    if v_status_id is not null then
      update events set status_id = v_status_id where id = v_event_id;
      v_parts := v_parts || 'ההזמנה אושרה — האירוע עבר ל״אישור סופי״'::text;
    end if;
  end if;

  -- ── שתי המשימות: תאריך ושעה בלידה, בלי כמות עובדים (0237) ───────────────
  v_setup := app.viperflow_apply_task(
    v_event_id, 'setup', v_delivery::date, v_delivery::time, null, v_created);
  v_teardown := app.viperflow_apply_task(
    v_event_id, 'teardown', v_return::date, v_return::time, null, v_created);

  if v_created then
    if v_delivery is not null then
      v_parts := v_parts || ('הקמה ' || to_char(v_delivery, 'DD/MM/YYYY HH24:MI'));
    end if;
    if v_return is not null then
      v_parts := v_parts || ('פירוק ' || to_char(v_return, 'DD/MM/YYYY HH24:MI'));
    end if;
  end if;

  -- ── ההכנסות: הריהוט לפי הקטלוג (0190). ההובלות אינן מסונכרנות (0237) ───
  if v_catalog then
    if app.viperflow_apply_income(v_event_id, v_conn.customer_id, 'furniture_old', v_old_amount)
       and v_created then
      v_parts := v_parts || ('ריהוט ישן ' || to_char(v_old_amount, 'FM999G999G990D00') || ' ₪');
    end if;
    if app.viperflow_apply_income(v_event_id, v_conn.customer_id, 'furniture_new', v_new_amount)
       and v_created then
      v_parts := v_parts || ('ריהוט חדש ' || to_char(v_new_amount, 'FM999G999G990D00') || ' ₪');
    end if;

    -- ‏0212/0213: הכיסאות והפריטים החופשיים — שתי קטגוריות שהעמלה עליהן
    -- נקבעת ביד. אותו כלל לשתיהן, בפונקציה אחת (0213 §3).
    v_bucket := app.viperflow_apply_manual_bucket(v_event_id, v_conn.customer_id,
      'furniture_chairs', v_split, v_chairs, v_created);
    if v_bucket ->> 'part' is not null then v_parts := v_parts || (v_bucket ->> 'part'); end if;
    if (v_bucket ->> 'alert')::boolean then v_alerts := v_alerts || jsonb_build_array(v_bucket); end if;

    v_bucket := app.viperflow_apply_manual_bucket(v_event_id, v_conn.customer_id,
      'furniture_custom', v_free_on, v_free, v_created);
    if v_bucket ->> 'part' is not null then v_parts := v_parts || (v_bucket ->> 'part'); end if;
    if (v_bucket ->> 'alert')::boolean then v_alerts := v_alerts || jsonb_build_array(v_bucket); end if;
  end if;

  -- ── הריהוט ─────────────────────────────────────────────────────────────
  v_items := app.viperflow_apply_items(v_event_id, p_connection, p_order -> 'items');
  if v_items > 0 and v_created then
    v_parts := v_parts || (v_items || ' שורות בהזמנה');
  end if;

  -- ── מה השתנה מאז הסנכרון הקודם (0190 §3) ────────────────────────────────
  v_snapshot := jsonb_strip_nulls(jsonb_build_object(
    'event_date',    to_char(v_event_date, 'DD/MM/YYYY'),
    'delivery',      to_char(v_delivery, 'DD/MM/YYYY HH24:MI'),
    'return',        to_char(v_return, 'DD/MM/YYYY HH24:MI'),
    'location',      v_location,
    'customer_name', nullif(btrim(p_order ->> 'customer_name'), ''),
    'notes',         v_note,
    'status',        v_status,
    'discount',      v_discount,
    'furniture_old', v_old_amount,
    'furniture_new', v_new_amount,
    'furniture_chairs', case when v_split then v_chairs end,
    'furniture_custom', case when v_free_on then v_free end,
    'items',         app.viperflow_items_fingerprint(v_event_id)));

  if not v_created then
    v_changes := app.viperflow_changes(v_link.order_snapshot, v_snapshot);
    if cardinality(v_changes) > 0 then
      v_parts := v_parts || v_changes;
    end if;
  end if;

  -- ‏0194: הכמויות נשמרות על הקישור ולא נספרות מחדש במסך. שתי סיבות:
  -- אלה בדיוק המספרים שהמתרגם עבד לפיהם, ו-view שקורא לפונקציה `security
  -- definer` הוא view שנשבר ביום שמישהו ישלול ממנה הרשאה.
  update viperflow_links set
    order_snapshot  = v_snapshot,
    truck_quantity  = v_trucks,
    worker_quantity = v_workers
   where event_id = v_event_id;

  if not v_sys then perform app.system_write(false); end if;

  insert into event_activity (event_id, kind, actor_name, note)
  values (v_event_id, 'synced', 'ViperFlow',
          'סונכרן מ-ViperFlow · ' || array_to_string(
            case when cardinality(v_parts) = 0 then array['ללא שינוי'] else v_parts end, ' · '));

  -- ההתראה יוצאת אחרי הכתיבה, ורק על עדכון: לידה אינה שינוי.
  perform app.viperflow_notify_change(v_event_id, v_conn.customer_id, v_number, v_changes);

  -- ‏0212: ועל העמלה — התראה משלה, כי מי שקבע אותה צריך לחזור אליה.
  for v_alert in select * from jsonb_array_elements(v_alerts) loop
    perform app.notify_commission_stale(v_event_id, v_conn.customer_id, v_number,
      v_alert ->> 'label', (v_alert ->> 'basis')::numeric,
      (v_alert ->> 'amount')::numeric, (v_alert ->> 'commission')::numeric);
  end loop;

  return jsonb_build_object(
    'status',   'processed',
    'event_id', v_event_id,
    'created',  v_created,
    'changes',  to_jsonb(v_changes),
    'items',    v_items);
end $$;

revoke execute on function app.viperflow_apply_order(uuid, jsonb, text, boolean) from anon, authenticated, public;

comment on function app.viperflow_apply_order(uuid, jsonb, text, boolean) is
  'מתרגם הזמנת ViperFlow לאירוע. מאז 0237 אינו כותב כמות משאיות, כמות עובדים, מחיר הקמה ופירוק והובלות.';
