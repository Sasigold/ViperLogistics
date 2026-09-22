-- 0189: המיקום נקבע בלידה, ומכאן הוא של הרכז
--
-- ‏0177 קבעה ש-ViperFlow הוא הבעלים של האולם, ו-0187 כבר הזיזה גבול אחד
-- מהסוג הזה (שעת ההגעה למחסן). זה השני, ומאותה סיבה בדיוק: **מה שכתוב
-- בהזמנה אינו מה שהנהג צריך.**
--
-- ‏"אולם הדקל" בהזמנה הופך אצלנו ל"אולם הדקל, החושלים 12 ראשון לציון —
-- הכניסה מאחור, שער משאיות" — כתובת שהרכז השלים, לעתים אחרי טלפון לאולם,
-- ושממנה נגזר גם הפין, גם אזור הנסיעה וגם המיקום שמועתק למשימות (0158).
-- כל עדכון של ההזמנה — שינוי שעה, הערה, פריט — החזיר אותה לטקסט הגולמי,
-- ומחק את העבודה הזו בשקט.
--
-- מעכשיו: **בלידה** המיקום נלקח מההזמנה, כי שם הוא הדבר היחיד שיש. **בעדכון**
-- הוא אינו נכתב כלל — בדיוק כמו `notes` מאז 0177 §1 — ומה שההזמנה אומרת
-- נרשם ביומן הפעילות. אם באמת החליפו אולם, זה יופיע ביומן ומישהו יכריע;
-- מיקום שנמחק בשקט הוא משאית שנוסעת לכתובת הלא נכונה.
--
-- שאר הגוף זהה ל-0187 §5.

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
  v_logistics   numeric;
  v_half        numeric;
begin
  -- ‏`is_active` ולא רק `deleted_at`: כיבוי החיבור במסך אמור לעצור את
  -- הקליטה, וגם כשהכתובת שנקודת הקצה מצביעה עליה נושאת את המזהה שלו בנתיב.
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

    return jsonb_build_object('status', 'processed', 'event_id', v_link.event_id,
                              'cancelled', true);
  end if;

  -- ── השדות שההזמנה קובעת ─────────────────────────────────────────────────
  v_event_date := nullif(p_order #>> '{event,date}', '')::date;
  v_location   := nullif(btrim(p_order #>> '{event,location}'), '');
  v_trucks     := app.viperflow_line_quantity(p_order -> 'items', 'truck');
  v_workers    := app.viperflow_line_quantity(p_order -> 'items', 'worker');
  v_delivery   := app.viperflow_local(p_order ->> 'delivery_date');
  v_return     := app.viperflow_local(p_order ->> 'return_date');

  if v_event_date is null then
    raise exception 'הזמנה % בלי תאריך אירוע', coalesce(v_number, v_order_id::text);
  end if;

  perform app.system_write(true);

  if v_link.event_id is null then
    -- ── לידה ────────────────────────────────────────────────────────────────
    --
    -- **אלא אם ההזמנה הזו כבר מתה** — ‏`order.created` שהתעכב יכול להגיע
    -- אחרי ה-`order.deleted` של אותה הזמנה (0177 §4).
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
            nullif(btrim(p_order ->> 'notes'), ''),
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
    -- ── עדכון ───────────────────────────────────────────────────────────────
    v_event_id := v_link.event_id;

    update events set
      end_client_name = coalesce(nullif(btrim(p_order ->> 'customer_name'), ''), end_client_name),
      event_date      = v_event_date,
      truck_count     = coalesce(v_trucks::int, truck_count),
      event_number    = case
        when event_number is null and v_number is not null and not exists (
               select 1 from events e2
                where e2.customer_id = events.customer_id
                  and e2.event_number = v_number and e2.deleted_at is null)
        then v_number else event_number end
     where id = v_event_id;

    -- הערה חדשה נאמרת ואינה נכתבת על מה שרכז כתב (0177 §1).
    v_note := nullif(btrim(p_order ->> 'notes'), '');
    if v_note is not null
       and v_note is distinct from (select e.notes from events e where e.id = v_event_id) then
      v_parts := v_parts || ('הערת ההזמנה ב-ViperFlow: ' || left(v_note, 300));
    end if;

    -- ‏0189: והמיקום, מעכשיו, באותו כלל בדיוק. ‏`location_text` אינו בעדכון
    -- למעלה; מה שההזמנה אומרת נאמר כאן, ומי שקורא את היומן יראה שהאולם
    -- ב-ViperFlow שונה ממה שכתוב אצלנו — ויחליט בעצמו.
    if v_location is not null
       and v_location is distinct from (select e.location_text from events e where e.id = v_event_id) then
      v_parts := v_parts || ('המיקום ב-ViperFlow: ' || left(v_location, 200));
    end if;

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
  --
  -- ‏0187 §1: ‏`buffer_hours.before` אינו נקרא עוד. שעת ההגעה למחסן נקבעת
  -- אצלנו, והיא אינה נגזרת של חיץ שנרשם בהזמנה.
  if v_delivery is not null then
    v_setup := app.viperflow_apply_task(
      v_event_id, 'setup', v_delivery::date, v_delivery::time, v_workers::int);
    v_parts := v_parts || ('הקמה ' || to_char(v_delivery, 'DD/MM/YYYY HH24:MI'));
  end if;

  if v_return is not null then
    v_teardown := app.viperflow_apply_task(
      v_event_id, 'teardown', v_return::date, v_return::time, v_workers::int);
    v_parts := v_parts || ('פירוק ' || to_char(v_return, 'DD/MM/YYYY HH24:MI'));
  end if;

  -- ── המחיר (0187 §2) ─────────────────────────────────────────────────────
  --
  -- מחצית לכל משימה, גם כשאחת מהן עדיין אינה קיימת: הזמנה בלי תאריך החזרה
  -- תקבל את הפירוק — ואת המחצית שלו — כשהתאריך יתמלא. הדרך השנייה, "הכול
  -- להקמה כשאין פירוק", הייתה מייצרת חיוב שצריך לתקן אחר כך ביד.
  v_logistics := case v_conn.logistics_price_source
                   when 'truck'     then app.viperflow_line_amount(p_order -> 'items', array['truck'])
                   when 'logistics' then app.viperflow_line_amount(p_order -> 'items', array['truck', 'worker'])
                 end;

  if v_logistics is not null and v_logistics > 0 and (v_setup is not null or v_teardown is not null) then
    v_half := round(v_logistics / 2, 2);
    perform app.viperflow_apply_price(v_setup, v_half, 'הקמה — מחצית מהלוגיסטיקה בהזמנה',
      'הזמנה ' || coalesce(v_number, v_order_id::text) || ' · ' || to_char(v_logistics, 'FM999G999G990D00') || ' ₪');
    perform app.viperflow_apply_price(v_teardown, v_half, 'פירוק — מחצית מהלוגיסטיקה בהזמנה',
      'הזמנה ' || coalesce(v_number, v_order_id::text) || ' · ' || to_char(v_logistics, 'FM999G999G990D00') || ' ₪');
    v_parts := v_parts || ('מחיר מההזמנה ' || to_char(v_logistics, 'FM999G999G990D00')
      || ' ₪ — ' || to_char(v_half, 'FM999G999G990D00') || ' ₪ לכל משימה');
  end if;

  -- ── הריהוט ─────────────────────────────────────────────────────────────
  v_items := app.viperflow_apply_items(v_event_id, p_connection, p_order -> 'items');
  if v_items > 0 then
    v_parts := v_parts || (v_items || ' שורות בהזמנה');
  end if;

  if not v_sys then perform app.system_write(false); end if;

  insert into event_activity (event_id, kind, actor_name, note)
  values (v_event_id, 'synced', 'ViperFlow',
          'סונכרן מ-ViperFlow · ' || array_to_string(
            case when cardinality(v_parts) = 0 then array['ללא שינוי'] else v_parts end, ' · '));

  return jsonb_build_object(
    'status',   'processed',
    'event_id', v_event_id,
    'created',  v_created,
    'items',    v_items);
end $$;
