-- 0202: אירוע יכול להפסיק להקשיב ל-ViperFlow
--
-- הבקשה, במילים של הבעלים: "כפתור בתוך אירוע שעוצר את הסנכרון. כל עוד הוא
-- מסומן לא משתנה כלום — לא סכומים, לא שעות, לא כמויות ולא מפרט."
--
-- עד היום כל הזמנה מקושרת (0177) הייתה מוחלת על האירוע שלה בכל משלוח: 0190
-- צמצם את העדכון לכמויות ולכסף, אבל לא היה שום מצב שבו האירוע אומר "מה שסוכם
-- כאן הוא הסופי". זה בדיוק המקרה של אירוע שנסגר מול הלקוח — המחיר נקבע, המפרט
-- הודפס למחסן — ושינוי מאוחר ב-ViperFlow אינו אמור לזוז מתחתיו.
--
-- ארבע הכרעות:
--
--   1. **הנעילה יושבת על הקישור, לא על האירוע.** ‏`viperflow_links` הוא מה
--      שמחבר אירוע להזמנה, ו"אל תסנכרן" היא תכונה של החיבור הזה. לאירוע שלא
--      הגיע מ-ViperFlow אין מה לנעול, ולכן גם אין לו עמודה.
--
--   2. **הבדיקה יושבת בנקודה אחת: `app.viperflow_apply_order`.** כל הדרכים
--      מגיעות אליה — ה-Webhook, "סנכרון עכשיו", משיכה כפויה (`force`) והרצה
--      מחדש של משלוח — דרך `viperflow_ingest`. היא נבדקת מיד אחרי קריאת
--      הקישור, *לפני* שומר החותמת ולפני ענף הביטול: גם `force` אינו עוקף
--      אותה, וגם ביטול ההזמנה אינו מבטל אירוע נעול. המשלוח נשמר כרגיל
--      (המעטפה כולה, 0176 §3) ונרשם "לא רלוונטי" עם הסיבה — שום דבר לא אבד,
--      הוא רק לא הוחל.
--
--   3. **המפרט ננעל יחד איתו.** רשימת הריהוט נכתבת רק מתוך אותה פונקציה
--      (`app.viperflow_apply_items`), ולכן היא קופאת מעצמה. מה שנשאר הוא
--      המסך: כפתור "מפרט" מושך את הרשימה חיה מה-API (0187), וזה בדיוק מה
--      שאסור כאן — מי שנעל רוצה לראות את מה שנעל. העמודה נחשפת ב-view, והמסך
--      מציג את הרשימה השמורה בלי לשאול את ViperFlow.
--
--   4. **שחרור הנעילה משלים את מה שהוחמץ.** הסנכרון היזום מתקדם לפי סמן
--      (`synced_through`) ואינו חוזר אחורה, ולכן הזמנה שהשתנתה בזמן הנעילה
--      ולא תשתנה שוב הייתה נשארת לא מסונכרנת לנצח. השחרור מריץ מחדש את
--      המשלוח האחרון של ההזמנה שנדחה בגלל הנעילה (`viperflow_replay`, 0177
--      §6) — כלומר האירוע חוזר למצב שההזמנה נמצאת בו עכשיו, בדיוק כאילו
--      לא ננעל. אם לא הגיע דבר בזמן הנעילה, אין מה להשלים.
--
-- מי נועל: מי שמחזיק `integrations.manage` — אותו מפתח שמנהל את החיבור
-- ומריץ משלוחים מחדש. נעילה היא הכרעה על מה ש-ViperFlow רשאי לכתוב, לא עריכה
-- של האירוע.

-- ===== 1. הנעילה על הקישור ================================================

alter table viperflow_links
  add column sync_locked_at timestamptz,
  add column sync_locked_by uuid references profiles(id) on delete set null;

comment on column viperflow_links.sync_locked_at is
  'מתי נעצר הסנכרון לאירוע הזה. כל עוד מלא — שום משלוח אינו מוחל (0202).';
comment on column viperflow_links.sync_locked_by is
  'מי עצר את הסנכרון (0202).';

-- ===== 2. שתי שורות יומן ===================================================
-- מי עצר ומתי — בלי זה, אירוע שלא זז אחרי שינוי בהזמנה נראה כתקלה.

alter type event_activity_kind add value if not exists 'sync_locked';
alter type event_activity_kind add value if not exists 'sync_unlocked';

-- ===== 3. המתרגם בודק את הנעילה ראשון ====================================
-- גוף זהה ל-0194 מילה במילה, בתוספת הבדיקה שמיד אחרי קריאת הקישור.
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
  v_crew        numeric;
  v_trucking    numeric;
  v_half        numeric;
  v_catalog     boolean;
  v_discount    numeric;
  v_old_amount  numeric;
  v_new_amount  numeric;
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

  -- ‏0202: אירוע שנעול לסנכרון אינו שומע דבר — לא כסף, לא כמויות, לא שעות,
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
  -- ולכן היא מוכפלת בשני הסכומים כאן ואינה נוגעת ב-`v_trucking` וב-`v_crew`.
  -- השאר מגיע כבר נקי: `line_total` של ViperFlow מגלם את הנחת השורה.
  -- ערך מחוץ ל-0‏–100 הוא נתון פגום, ומוטב להתעלם ממנו מלהכפיל בו כסף.
  v_discount := coalesce((p_order #>> '{totals,order_discount_percent}')::numeric, 0);
  if v_discount < 0 or v_discount > 100 then v_discount := 0; end if;

  if v_catalog then
    v_old_amount := round(
      app.viperflow_furniture_amount(p_order -> 'items', false) * (1 - v_discount / 100), 2);
    v_new_amount := round(
      app.viperflow_furniture_amount(p_order -> 'items', true) * (1 - v_discount / 100), 2);
  end if;

  -- ‏0192: הצוות מתחלק בין שתי המשימות, וההובלה הולכת להכנסות. שתיהן
  -- נמדדות על אותן שורות ששמן הוגדר, ולא על כל `line_type`.
  v_crew := case when v_conn.logistics_price_source = 'crew'
                 then app.viperflow_named_amount(p_order -> 'items', 'worker', v_conn.crew_line_names)
            end;
  v_trucking := app.viperflow_named_amount(p_order -> 'items', 'truck', v_conn.trucking_line_names);

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
            v_trucks::int,
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
    -- ── עדכון: כמות משאיות, וזהו (0190) ─────────────────────────────────────
    --
    -- ‏`event_number` הוא היוצא היחיד, והוא אינו סנכרון אלא השלמה: הוא נכתב
    -- רק כשהוא ריק אצלנו ופנוי אצל הלקוח, ולכן אין בו מה לדרוס.
    v_event_id := v_link.event_id;

    update events set
      truck_count  = coalesce(v_trucks::int, truck_count),
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

  -- ── שתי המשימות ────────────────────────────────────────────────────────
  v_setup := app.viperflow_apply_task(
    v_event_id, 'setup', v_delivery::date, v_delivery::time, v_workers::int, v_created);
  v_teardown := app.viperflow_apply_task(
    v_event_id, 'teardown', v_return::date, v_return::time, v_workers::int, v_created);

  if v_created then
    if v_delivery is not null then
      v_parts := v_parts || ('הקמה ' || to_char(v_delivery, 'DD/MM/YYYY HH24:MI'));
    end if;
    if v_return is not null then
      v_parts := v_parts || ('פירוק ' || to_char(v_return, 'DD/MM/YYYY HH24:MI'));
    end if;
  end if;

  -- ── מחיר המשימה: שורות הצוות, מחצית לכל אחת (0187, 0192) ────────────────
  if v_crew is not null and v_crew > 0
     and (v_setup is not null or v_teardown is not null) then
    v_half := round(v_crew / 2, 2);
    perform app.viperflow_apply_price(v_setup, v_half, 'הקמה — מחצית מסידור ואיסוף בהזמנה',
      'הזמנה ' || coalesce(v_number, v_order_id::text) || ' · ' || to_char(v_crew, 'FM999G999G990D00') || ' ₪');
    perform app.viperflow_apply_price(v_teardown, v_half, 'פירוק — מחצית מסידור ואיסוף בהזמנה',
      'הזמנה ' || coalesce(v_number, v_order_id::text) || ' · ' || to_char(v_crew, 'FM999G999G990D00') || ' ₪');
    if v_created then
      v_parts := v_parts || ('סידור ואיסוף ' || to_char(v_crew, 'FM999G999G990D00')
        || ' ₪ — ' || to_char(v_half, 'FM999G999G990D00') || ' ₪ לכל משימה');
    end if;
  end if;

  -- ── ההכנסות: ההובלה, והריהוט לפי הקטלוג (0190, 0192) ────────────────────
  if app.viperflow_apply_income(v_event_id, v_conn.customer_id, 'trucking', v_trucking)
     and v_created then
    v_parts := v_parts || ('הובלות ' || to_char(v_trucking, 'FM999G999G990D00') || ' ₪');
  end if;

  if v_catalog then
    if app.viperflow_apply_income(v_event_id, v_conn.customer_id, 'furniture_old', v_old_amount)
       and v_created then
      v_parts := v_parts || ('ריהוט ישן ' || to_char(v_old_amount, 'FM999G999G990D00') || ' ₪');
    end if;
    if app.viperflow_apply_income(v_event_id, v_conn.customer_id, 'furniture_new', v_new_amount)
       and v_created then
      v_parts := v_parts || ('ריהוט חדש ' || to_char(v_new_amount, 'FM999G999G990D00') || ' ₪');
    end if;
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
    'trucks',        v_trucks,
    'workers',       v_workers,
    'crew_price',    v_crew,
    'trucking',      v_trucking,
    'discount',      v_discount,
    'furniture_old', v_old_amount,
    'furniture_new', v_new_amount,
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

  return jsonb_build_object(
    'status',   'processed',
    'event_id', v_event_id,
    'created',  v_created,
    'changes',  to_jsonb(v_changes),
    'items',    v_items);
end $$;

-- ===== 4. הכפתור ==========================================================
--
-- ‏`p_locked` ולא "החלף": שתי לשוניות פתוחות על אותו אירוע אינן יכולות להפוך
-- זו את ההכרעה של זו. אותה נעילת-ייעוץ של המתרגם (0177 §4), כדי שמשלוח
-- שמוחל ברגע הלחיצה יסתיים לפני הנעילה או יתחיל אחריה — לא באמצע.
--
-- מחזיר את המצב החדש, ובשחרור — גם את תוצאת ההשלמה (§4 בראש הקובץ).

create or replace function viperflow_set_event_lock(p_event_id uuid, p_locked boolean)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_link     viperflow_links;
  v_actor    uuid := app.profile_id();
  v_name     text;
  v_delivery uuid;
  v_result   jsonb;
begin
  perform app.require('integrations.manage', 'אין לך הרשאה לעצור או לחדש סנכרון של אירוע');

  select * into v_link from viperflow_links where event_id = p_event_id;
  if v_link.event_id is null then
    raise exception 'האירוע לא הגיע מ-ViperFlow — אין סנכרון לעצור';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(v_link.connection_id::text || ':' || v_link.order_id::text, 0));
  select * into v_link from viperflow_links where event_id = p_event_id;

  -- כבר במצב המבוקש: אין שורת יומן ואין השלמה.
  if (v_link.sync_locked_at is not null) = coalesce(p_locked, false) then
    return jsonb_build_object('locked', v_link.sync_locked_at is not null,
                              'locked_at', v_link.sync_locked_at);
  end if;

  select full_name into v_name from profiles where id = v_actor;

  if p_locked then
    update viperflow_links set sync_locked_at = now(), sync_locked_by = v_actor
     where event_id = p_event_id;

    insert into event_activity (event_id, kind, actor_profile_id, actor_name, note)
    values (p_event_id, 'sync_locked'::event_activity_kind, v_actor, v_name,
            'הסנכרון מ-ViperFlow נעצר — סכומים, שעות, כמויות ומפרט לא ישתנו מההזמנה');

    return jsonb_build_object('locked', true, 'locked_at', now());
  end if;

  -- ── שחרור ────────────────────────────────────────────────────────────────
  -- המשלוח האחרון שנדחה בגלל הנעילה. האחרון לפי החותמת של ההזמנה, לא לפי
  -- סדר ההגעה: ‏ViperFlow אינו מבטיח סדר, ושומר החותמת של המתרגם יעשה את
  -- השאר.
  select d.id into v_delivery
    from viperflow_deliveries d
   where d.connection_id = v_link.connection_id
     and d.entity_id = v_link.order_id::text
     and d.status = 'ignored'
     and d.reason = 'הסנכרון לאירוע הזה נעצר — ההזמנה נשמרה ולא הוחלה'
     and d.received_at >= v_link.sync_locked_at
   order by d.payload #>> '{data,updated_at}' desc nulls last, d.received_at desc
   limit 1;

  update viperflow_links set sync_locked_at = null, sync_locked_by = null
   where event_id = p_event_id;

  insert into event_activity (event_id, kind, actor_profile_id, actor_name, note)
  values (p_event_id, 'sync_unlocked'::event_activity_kind, v_actor, v_name,
          case when v_delivery is null
               then 'הסנכרון מ-ViperFlow חודש — לא הגיעו שינויים בזמן העצירה'
               else 'הסנכרון מ-ViperFlow חודש — השינויים שהגיעו בזמן העצירה מוחלים עכשיו' end);

  if v_delivery is not null then
    v_result := viperflow_replay(v_delivery);
  end if;

  return jsonb_build_object('locked', false, 'locked_at', null,
                            'caught_up', v_delivery is not null,
                            'result', v_result);
end $$;

revoke execute on function viperflow_set_event_lock(uuid, boolean) from anon, public;
grant  execute on function viperflow_set_event_lock(uuid, boolean) to authenticated;

-- ===== 5. וה-view אומר שהאירוע נעול ======================================
-- העמודה החדשה בסוף, כדי ש-`create or replace view` יקבל את השינוי. גוף זהה
-- ל-0194 — העמודה נקראת ישירות, בלי פונקציה (0194 §3).

create or replace view viperflow_event_link with (security_invoker = true) as
select l.event_id,
       l.connection_id,
       l.order_id,
       l.order_number,
       l.order_status,
       l.last_synced_at,
       c.label as connection_label,
       (select count(*) from viperflow_order_items i
         where i.event_id = l.event_id and i.line_type = 'product'
           and not i.is_component) as furniture_lines,
       l.truck_quantity,
       l.worker_quantity,
       l.sync_locked_at
from viperflow_links l
left join viperflow_connections c on c.id = l.connection_id;

grant select on viperflow_event_link to authenticated;
revoke all on viperflow_event_link from anon;
