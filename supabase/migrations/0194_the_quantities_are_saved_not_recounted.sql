-- 0194: הכמויות נשמרות בסנכרון, וה-view אינו קורא לאף פונקציה
--
-- ‏0193 הוסיף ל-`viperflow_event_link` שתי עמודות שחושבו בפונקציה `security
-- definer`, ושלל ממנה הרשאת הרצה מ-`authenticated` — כמו מכל עוזרת אחרת
-- ב-`app`. אבל ה-view הזה הוא **`security_invoker`**: הוא רץ בהרשאות של מי
-- שקורא לו, ולכן כל `select` ממנו התחיל לענות "permission denied for
-- function". המסך לא קיבל את הקישור, ומפרטים הפסיקו להיפתח בפרודקשן.
--
-- **חבילת הבדיקות לא יכלה לתפוס את זה**, וזה מתועד בתוך בדיקה 49 עצמה:
-- ‏`01_seed.sql` מריץ `grant execute on all functions in schema public, app
-- to authenticated` *אחרי* המיגרציות, ולכן מבטל שם כל `revoke`. מה שנראה
-- ירוק בבדיקות היה שבור בייצור. ‏§3 למטה סוגר את הפער הזה מלמעלה.
--
-- התיקון אינו להחזיר את ההרשאה אלא להסיר את השאלה: הכמויות הן מה שהמתרגם
-- כבר חישב, ולכן הן נשמרות על הקישור בזמן הסנכרון וה-view רק קורא עמודה.
-- אין פונקציה, אין הרשאה לשכוח, ואין מקום שני שסופר אחרת.

-- ===== 1. הכמויות יושבות על הקישור =======================================

alter table viperflow_links
  add column truck_quantity  numeric,
  add column worker_quantity numeric;

comment on column viperflow_links.truck_quantity is
  'כמות המשאיות כפי שהמתרגם ספר אותה בסנכרון האחרון (0194).';
comment on column viperflow_links.worker_quantity is
  'כמות העובדים כפי שהמתרגם ספר אותה בסנכרון האחרון (0194).';

-- מילוי חד-פעמי לקישורים שכבר קיימים, מאותן שורות ובאותו כלל של 0192.
update viperflow_links l set
  truck_quantity = (
    select nullif(sum(i.quantity), 0) from viperflow_order_items i
     where i.event_id = l.event_id and i.line_type = 'truck' and not i.is_component
       and btrim(i.name) = any(c.trucking_line_names)),
  worker_quantity = (
    select nullif(sum(i.quantity), 0) from viperflow_order_items i
     where i.event_id = l.event_id and i.line_type = 'worker' and not i.is_component
       and btrim(i.name) = any(c.crew_line_names))
from viperflow_connections c
where c.id = l.connection_id;

-- ===== 2. המתרגם כותב אותן =================================================
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

-- ===== 3. וה-view קורא עמודה, לא פונקציה ==================================
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
       l.worker_quantity
from viperflow_links l
left join viperflow_connections c on c.id = l.connection_id;

grant select on viperflow_event_link to authenticated;
revoke all on viperflow_event_link from anon;

drop function if exists app.viperflow_stored_quantity(uuid, text);
