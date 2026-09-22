-- 0187: שורת ההובלה נושאת את המחיר שלה, ושעת המחסן חוזרת להיות שלנו
--
-- שלוש בקשות של שיא עיצובים, וכולן על אותו גבול: **מה ViperFlow הבעלים שלו
-- ומה שלנו.** ‏0177 שרטטה אותו פעם אחת, וכאן הוא זז בשתי נקודות.
--
-- ‏1. **שעת ההגעה למחסן אינה של ViperFlow.** ‏`buffer_hours.before` של
--    ההזמנה תורגם עד כה ל-`warehouse_start_time` של ההקמה, מתוך הנחה ששתי
--    המערכות מתארות את אותו חיץ. הן לא: אצלם זה "כמה שעות לפני האירוע
--    הציוד צריך לצאת", ואצלנו זו השעה שבה **הצוות מגיע למחסן** — שעה
--    שנקבעת מהמרחק, מהעומס באותו בוקר ומכמה משאיות עומסים, ושהרכז קובע
--    ידנית. סנכרון דרס אותה בכל עדכון של ההזמנה, גם כשאיש לא נגע בחיץ.
--    מעכשיו היא אינה נכתבת מהאינטגרציה כלל.
--
--    **מה שכבר נכתב נשאר.** שעה שהרכז ראה ועבד לפיה אינה דבר שמיגרציה
--    מוחקת בלילה; מכאן ואילך היא פשוט לא תזוז מעצמה.
--
-- ‏2. **שורת "הובלה" נושאת מחיר, והוא מחיר ההקמה והפירוק.** ‏0176 §2 קבעה
--    ש"אין מחירים, בשום שלב" — והכוונה הייתה לרשימת הריהוט: מחיר פר-פריט
--    שהלקוח הסופי משלם אינו עניינו של מי שמעמיס משאית. שורות הלוגיסטיקה הן
--    שאלה אחרת: הן מה ש**אנחנו** עושים, ומה שנגבה עליו. ‏שיא עיצובים מתמחרת
--    את ההובלה בהזמנה אחת, אצלנו היא שתי משימות — הקמה ופירוק — ולכן
--    הסכום מתחלק לשניים, מחצית לכל אחת.
--
--    ‏`viperflow_order_items` **נשארת בלי עמודת מחיר**, וזו לא פשרה אלא
--    בדיוק אותו נימוק של 0176 §2: הכסף אינו יושב בטבלת הריהוט לרגע. הוא
--    נקרא מהמעטפה, מתחלק, ונכתב ל-`task_pricing` — ולשום מקום אחר.
--
--    ‏`is_manual` ולא מחיר מחושב: המספר בא מבחוץ ואינו נגזר משום מחשבון
--    שלנו, ו-`app.recalc_task_price` (0120) מדלגת על שורה ידנית. בלי הדגל,
--    הטריגר שרץ על כל שינוי תאריך או שעה היה מוחק אותו בשקט.
--
--    **והוא נדרס בכל סנכרון**, כמו התאריך והשעה: מי שמשנה מחיר בהזמנה מצפה
--    שהוא ישתנה, ולא שמישהו יזכור לעדכן ידנית. מספר שהוקלד אצלנו שורד עד
--    העדכון הבא של אותה הזמנה.
--
-- ‏3. **מהי "הלוגיסטיקה" — הכרעה של המשרד, לא של הקוד.** ההזמנה נושאת שתי
--    שורות כאלה: "הובלה" (`truck`) ו"סידור ואיסוף" (`worker`). ברירת המחדל
--    היא ההובלה בלבד, והמסך מאפשר לצרף גם את הסידור או לכבות את הסנכרון
--    לגמרי. עמודה על החיבור ולא קבוע בקוד: זו שאלה של כסף, והתשובה עליה
--    צריכה להיות גלויה במסך ולא קבורה במיגרציה.

-- ===== 1. מקור המחיר, על החיבור ===========================================

alter table viperflow_connections
  add column logistics_price_source text not null default 'truck'
    check (logistics_price_source in ('none', 'truck', 'logistics'));

comment on column viperflow_connections.logistics_price_source is
  'מאיזו שורה בהזמנה נגזר מחיר ההקמה והפירוק: truck = "הובלה" בלבד '
  '(ברירת המחדל), logistics = הובלה + סידור ואיסוף, none = אין סנכרון מחיר. '
  'הסכום מתחלק בשניים, מחצית לכל משימה (0187).';

-- ===== 2. הסכום שהוזמן מסוג שורה ==========================================
--
-- תאומה של `app.viperflow_line_quantity` (0177 §1), ובאותם שני כללים:
-- רכיבים אינם נספרים (הם חלק מהאב), ואפס מוחזר כ-null — "לא תומחרה הובלה"
-- אינו "הובלה בחינם", והשני היה מאפס מחיר שהמשרד קבע.
--
-- ‏`line_total` ולא `unit_price × quantity`: הראשון הוא מה ש-ViperFlow חישב
-- בפועל, כולל הנחת שורה. אנחנו לא מחשבים מחדש מה שכבר חושב.
create or replace function app.viperflow_line_amount(p_items jsonb, p_types text[])
returns numeric language sql stable set search_path = public as $$
  select nullif(sum(coalesce((i ->> 'line_total')::numeric, 0)), 0)
  from jsonb_array_elements(
         case when jsonb_typeof(p_items) = 'array' then p_items else '[]'::jsonb end) i
  where i ->> 'line_type' = any(p_types)
    and coalesce((i ->> 'is_component')::boolean, false) = false;
$$;

comment on function app.viperflow_line_amount(jsonb, text[]) is
  'סכום `line_total` של שורות ההזמנה מהסוגים שנמסרו, בלי רכיבים. null כשאין (0187).';

-- ===== 3. כתיבת המחיר על המשימה ===========================================
--
-- פונקציה משלה ולא שתי פסקאות זהות בתוך המתרגם: שתי המשימות מקבלות את אותו
-- טיפול, והפירוט שנשמר חייב להיות זהה בשתיהן.
--
-- ‏`breakdown` מלא ולא `{total: …}`: המסך מרנדר כל פירוט שאינו null
-- (`TaskDrawer` → `Breakdown`), וצורה חלקית הייתה מפילה אותו. שורה אחת,
-- שאומרת מאיפה המספר בא — כי "מחיר ידני" בלי מקור הוא בדיוק מה שגורם
-- למישהו לשנות אותו בטעות בעוד חודש.
create or replace function app.viperflow_apply_price(
  p_task   uuid,
  p_amount numeric,
  p_label  text,
  p_detail text)
returns void language plpgsql security definer set search_path = public as $$
declare v_sys boolean := app.in_system_write();
begin
  if p_task is null or p_amount is null then return; end if;

  perform app.system_write(true);
  insert into task_pricing (task_id, price, is_manual, breakdown, calculated_at)
  values (p_task, p_amount, true,
          jsonb_build_object(
            'version', 1, 'model', 'line_items', 'source', 'viperflow',
            'total', p_amount, 'subtotal', p_amount,
            'hours', 0, 'per_worker', 0, 'base_workers', 0, 'workers', 0,
            'hour_lines', '[]'::jsonb,
            'lines', jsonb_build_array(jsonb_build_object(
              'id', 'viperflow_logistics', 'label', p_label,
              'detail', p_detail, 'amount', p_amount))),
          now())
  on conflict (task_id) do update
    set price         = excluded.price,
        is_manual     = true,
        breakdown     = excluded.breakdown,
        calculated_at = excluded.calculated_at;

  if not v_sys then perform app.system_write(false); end if;
end $$;

comment on function app.viperflow_apply_price(uuid, numeric, text, text) is
  'כותב מחיר שהגיע מ-ViperFlow על משימה, כמחיר ידני שהמנוע אינו דורס (0187).';

-- ===== 4. המשימה, בלי שעת המחסן ===========================================
--
-- ‏`p_warehouse` יורדת מהחתימה ולא מקבלת null בקריאה: פרמטר שכל הקוראים
-- מעבירים בו null הוא פרמטר שמישהו ימלא בטעות בעוד שנה. החתימה משתנה, ולכן
-- הישנה נמחקת קודם.
drop function if exists app.viperflow_apply_task(uuid, text, date, time, time, int);

create or replace function app.viperflow_apply_task(
  p_event      uuid,
  p_code       text,
  p_date       date,
  p_onsite     time,
  p_workers    int)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_type    task_types;
  v_event   events;
  v_task_id uuid;
  v_sys     boolean := app.in_system_write();
begin
  if p_date is null and p_onsite is null and p_workers is null then
    return null;
  end if;

  select * into v_type from task_types
   where code = p_code and is_active and deleted_at is null;
  -- סוג משימה שכובה במסך ההגדרות אינו נוצר מחדש מהאינטגרציה. ההגדרות הן של
  -- המשרד, וסנכרון אינו מקום להחזיר מהן דברים.
  if v_type.id is null then return null; end if;

  select * into v_event from events where id = p_event;
  if v_event.id is null then raise exception 'אירוע לא נמצא'; end if;

  select t.id into v_task_id from tasks t
   where t.event_id = p_event and t.task_type_id = v_type.id and t.deleted_at is null
   order by t.created_at, t.id
   limit 1;

  -- הדגל מורם לפני *כל* כתיבה ולא פעם אחת בראש: ‏`app.sync_contractor_terms`
  -- הוא טריגר AFTER INSERT על tasks שמכבה אותו בסופו (0012 §90), ולכן
  -- ה-UPDATE שאחרי ה-INSERT היה נשפט מול הרשאות השדה של מי שלחץ "הרץ מחדש".
  perform app.system_write(true);

  if v_task_id is null then
    insert into tasks (event_id, customer_id, task_type_id, task_date, status_id,
                       worker_count, created_by)
    values (p_event, v_event.customer_id, v_type.id,
            coalesce(p_date, v_event.event_date),
            (select id from statuses where entity = 'task' and is_default and deleted_at is null limit 1),
            0, null)
    returning id into v_task_id;
  end if;

  perform app.system_write(true);
  update tasks set
    task_date         = coalesce(p_date, task_date),
    onsite_start_time = coalesce(p_onsite, onsite_start_time),
    worker_count      = coalesce(p_workers, worker_count)
  where id = v_task_id;

  if not v_sys then perform app.system_write(false); end if;
  return v_task_id;
end $$;

-- ===== 5. המתרגם ==========================================================
--
-- הגוף זהה ל-0177 §4 פרט לשלושה מקומות: החיץ אינו נקרא ואינו נכתב (§1),
-- מזהי שתי המשימות נשמרים במקום להיזרק, ואחריהן יושבת פסקת המחיר (§2).
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
      location_text   = coalesce(v_location, location_text),
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

-- ===== 6. המסך: מקור המחיר נקרא ונכתב =====================================
--
-- החתימה משתנה, ולכן הישנה נמחקת: פרמטר שנוסף עם ברירת מחדל יוצר שתי
-- פונקציות עם אותו שם שאפשר לקרוא לשתיהן באותם ארגומנטים, ופוסטגרס עונה על
-- כך "function is not unique".
drop function if exists viperflow_set_connection(uuid, text, boolean, text, uuid);

create or replace function viperflow_set_connection(
  p_customer_id     uuid,
  p_label           text,
  p_is_active       boolean default true,
  p_notes           text default null,
  p_connection_id   uuid default null,
  -- null = אל תיגע. המסך שולח ערך רק כשהוא באמת משנה אותו, וכך מתג "פעיל"
  -- אינו יכול לאפס בטעות את מקור המחיר.
  p_logistics_price text default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  perform app.require('integrations.manage', 'אין לך הרשאה לנהל חיבורים');

  if not exists (select 1 from customers c where c.id = p_customer_id and c.deleted_at is null) then
    raise exception 'לקוח לא נמצא';
  end if;
  if coalesce(btrim(p_label), '') = '' then
    raise exception 'חובה לתת שם לחיבור';
  end if;
  if p_logistics_price is not null
     and p_logistics_price not in ('none', 'truck', 'logistics') then
    raise exception 'מקור מחיר לא חוקי';
  end if;

  if p_connection_id is null then
    -- `api_base_url` אינה ברשימה: היא נשארת על ברירת המחדל שלה (0176 §4.1).
    insert into viperflow_connections (customer_id, label, is_active, notes,
                                       logistics_price_source)
    values (p_customer_id, btrim(p_label), coalesce(p_is_active, true),
            nullif(btrim(p_notes), ''), coalesce(p_logistics_price, 'truck'))
    returning id into v_id;
  else
    update viperflow_connections set
      customer_id            = p_customer_id,
      label                  = btrim(p_label),
      is_active              = coalesce(p_is_active, is_active),
      notes                  = nullif(btrim(p_notes), ''),
      logistics_price_source = coalesce(p_logistics_price, logistics_price_source)
    where id = p_connection_id and deleted_at is null
    returning id into v_id;
    if v_id is null then raise exception 'חיבור לא נמצא'; end if;
  end if;

  return v_id;
end $$;

revoke execute on function viperflow_set_connection(uuid, text, boolean, text, uuid, text)
  from anon, public;
grant  execute on function viperflow_set_connection(uuid, text, boolean, text, uuid, text)
  to authenticated;

create or replace function viperflow_connection_status()
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  perform app.require('integrations.view');

  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id',            c.id,
      'label',         c.label,
      'customer_id',   c.customer_id,
      'customer_name', cu.name,
      'api_base_url',   c.api_base_url,
      'is_active',      c.is_active,
      'synced_through', c.synced_through,
      'notes',          c.notes,
      -- ‏0187: מאיזו שורה נגזר מחיר ההקמה והפירוק.
      'logistics_price_source', c.logistics_price_source,
      'linked_events', (select count(*) from viperflow_links l where l.connection_id = c.id),
      'last_event_at', (select max(d.received_at) from viperflow_deliveries d
                         where d.connection_id = c.id),
      'received_24h',  (select count(*) from viperflow_deliveries d
                         where d.connection_id = c.id
                           and d.received_at > now() - interval '24 hours'),
      'failed_open',   (select count(*) from viperflow_deliveries d
                         where d.connection_id = c.id and d.status = 'failed')
    ) order by c.label)
    from viperflow_connections c
    join customers cu on cu.id = c.customer_id
    where c.deleted_at is null
  ), '[]'::jsonb);
end $$;

revoke execute on function viperflow_connection_status() from anon, public;
grant  execute on function viperflow_connection_status() to authenticated;

-- ===== 7. והחדשות סגורות כמו הוותיקות =====================================
--
-- ‏0177 §6א חסם את המתרגם בפני כל משתמש מאומת, וזה נכון גם לשלוש הפונקציות
-- שהקובץ הזה מוסיף או מחליף. ‏`app.viperflow_apply_task` בפרט: החתימה
-- שלה השתנתה, ולכן ה-revoke הישן ירד עם הפונקציה הישנה — ובלי השורה כאן
-- היא הייתה חוזרת פתוחה. ‏`app.viperflow_apply_price` היא `security definer`
-- שכותבת מחיר מתחת ל-`app.system_write`, כלומר עוקפת את שער `pricing.edit`;
-- הדרך היחידה אליה היא המתרגם. ‏`app.viperflow_apply_order` לא נמחקה אלא
-- הוחלפה, וה-ACL שלה שרד איתה.
--
-- (‏`create or replace` שומר על ה-ACL; ‏`drop` מוחק אותו. זה כל ההבדל בין
-- השורות שכאן לבין אלה שאינן.)
revoke execute on function app.viperflow_line_amount(jsonb, text[])
  from anon, authenticated, public;
revoke execute on function app.viperflow_apply_price(uuid, numeric, text, text)
  from anon, authenticated, public;
revoke execute on function app.viperflow_apply_task(uuid, text, date, time, int)
  from anon, authenticated, public;
