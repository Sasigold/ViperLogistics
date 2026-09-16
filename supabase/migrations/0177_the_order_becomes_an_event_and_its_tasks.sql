-- 0177: ההזמנה הופכת לאירוע, ולשתי המשימות שלו
--
-- ‏0176 הניחה את הצינור; כאן יושב התרגום. הזמנה ב-ViperFlow ואירוע אצלנו
-- מתארים את אותו ערב, אבל הם עונים על שתי שאלות שונות — "מה הלקוח הזמין"
-- מול "מי נוסע ומתי" — ולכן התרגום אינו העתקה של שדות אלא הכרעה על **מי
-- הבעלים של כל שדה**:
--
--   ‏ViperFlow הוא הבעלים של: תאריך האירוע, האולם, שם הלקוח הסופי, מספר
--   ההזמנה, שעת האספקה, שעת ההחזרה, כמות המשאיות, כמות העובדים ורשימת
--   הריהוט. אלה עובדות שנקבעות מול הלקוח הסופי, ואצלנו אין מי שיקבע אותן.
--   הן **נדרסות** בכל סנכרון, וזו כל הנקודה: שעה שזזה שם צריכה לזוז כאן.
--
--   אנחנו הבעלים של: השיבוץ, הקבלן, התמחור, אופן הביצוע, המשאית, סטטוס
--   המשימה, ההערות של הרכז וכל השדות המותאמים של הלקוח. אלה **אינם נגעים**
--   לעולם — לא בסנכרון ראשון ולא במאה.
--
-- ארבע הכרעות שנגזרות מזה, וכל אחת מהן שווה שורה:
--
--   1. **הערה של רכז אינה נמחקת בגלל שההזמנה השתנתה.** שדה `notes` מתמלא
--      פעם אחת, בלידה. מכאן ואילך, הערה חדשה מ-ViperFlow נרשמת ביומן
--      הפעילות ולא נכתבת על מה שאדם כתב.
--
--   2. **הסטטוס זז קדימה, ולא אחורה.** ביטול ב-ViperFlow מבטל את האירוע —
--      תמיד. אישור מקדם אירוע ש**עדיין** על "טרם אושר", ואינו נוגע באירוע
--      שהמשרד כבר קידם בעצמו. אירוע שהמשרד סימן "מתקיים" לא יחזור ל"אישור
--      סופי" בגלל משלוח שהגיע באיחור.
--
--   3. **משלוח ישן אינו דורס חדש.** ‏ViperFlow מבטיח at-least-once ואינו
--      מבטיח סדר, ולכן `order_updated_at` נשמר, וכל מעטפה שנושאת חותמת
--      ישנה ממנו נדחית כ-'stale'. בלי זה, ניסיון חוזר שהתעכב שש שעות היה
--      מחזיר את התאריך שנקבע לפני שש שעות.
--
--   4. **המשימה שכבר פורסמה כן זזה.** הטריגר של 0003 יוצר הקמה ופירוק בלידת
--      האירוע, והסנכרון *ממלא* אותן — אותו דפוס בדיוק של `apply_import_tasks`
--      (0052). אם ההקמה כבר "משובצת" ועובדים רואים אותה, והלקוח הזיז את
--      האירוע ביום — היא זזה בכל זאת, והיומן אומר בדיוק מה זז. משימה שאינה
--      זזה בשקט היא משאית שמגיעה ליום הלא נכון.

-- ===== 1. מה-UTC של ViperFlow לשעון הקיר של ישראל ==========================
--
-- ‏ViperFlow שולח כל חותמת זמן כ-ISO ב-UTC עם אלפיות ו-Z. אצלנו `task_date`
-- הוא `date` ו-`onsite_start_time` הוא `time` — כלומר שעון קיר מקומי, כי זה
-- מה שכתוב על דף העבודה של הנהג. ההמרה חייבת לעבור דרך אזור הזמן ולא דרך
-- חיתוך מחרוזת: אספקה ב-2026-10-01T21:00:00Z היא 2 באוקטובר ב-00:00 בישראל,
-- ומי שיחתוך את המחרוזת יקבל את היום הלא נכון וגם את השעה הלא נכונה.
--
-- `immutable` היא לא: `timestamptz → timestamp` תלוי ב-tz של המסד? לא —
-- אזור הזמן כאן קבוע במפורש, וההמרה דטרמיניסטית. `stable` בכל זאת, כי
-- `::timestamptz` על מחרוזת קורא את TimeZone של הסשן כשאין היסט במחרוזת.
create or replace function app.viperflow_local(p_iso text)
returns timestamp language plpgsql stable set search_path = public as $$
begin
  if coalesce(btrim(p_iso), '') = '' then return null; end if;
  return (p_iso::timestamptz) at time zone 'Asia/Jerusalem';
exception when others then
  -- מעטפה פגומה אינה מפילה סנכרון שלם. השדה פשוט אינו ידוע.
  return null;
end $$;

/**
 * הכמות שהוזמנה מסוג שורה מסוים — 'truck' או 'worker'.
 *
 * רכיבים (`is_component`) אינם נספרים: הם חלק מהאב, וספירתם הייתה מכפילה.
 * ‏ViperFlow פותח כל הזמנה עם שורת עובדים ושורת משאית, ולעתים קרובות בכמות
 * אפס — ולכן אפס מוחזר כ-null: "לא הוזמנה משאית" אינו "הוזמנו אפס משאיות",
 * והשני היה מוחק את מה שהרכז קבע.
 */
create or replace function app.viperflow_line_quantity(p_items jsonb, p_type text)
returns numeric language sql stable set search_path = public as $$
  select nullif(sum(coalesce((i ->> 'quantity')::numeric, 0)), 0)
  from jsonb_array_elements(case when jsonb_typeof(p_items) = 'array' then p_items else '[]'::jsonb end) i
  where i ->> 'line_type' = p_type
    and coalesce((i ->> 'is_component')::boolean, false) = false;
$$;

-- ===== 2. רשימת הריהוט ====================================================
--
-- החלפה ולא מיזוג. מזהי השורות של ViperFlow אינם יציבים בין עריכות (הם
-- נכתבים מחדש בכל שמירה באשף שלהם), ולכן התאמה שורה-לשורה הייתה יוצרת
-- כפילויות בכל עריכה. מה שמגיע הוא הרשימה המלאה, ומה שנשמר הוא בדיוק היא.
--
-- **הכסף אינו נקרא כאן.** ‏`unit_price`, `discount_percent`, `line_total`
-- ו-`totals` קיימים במעטפה של ViperFlow, נמחקים בפונקציית הקצה לפני
-- שהמעטפה נשמרת, ואינם מופיעים באף שורה בגוף הזה. שתי שכבות, ובכוונה.
create or replace function app.viperflow_apply_items(
  p_event uuid, p_connection uuid, p_items jsonb)
returns int language plpgsql security definer set search_path = public as $$
declare v_count int := 0;
begin
  if jsonb_typeof(p_items) is distinct from 'array' then
    -- מעטפה בלי `items` (למשל `order.deleted`) אינה אומרת "אין ריהוט" אלא
    -- "לא סופר" — ולכן היא אינה מוחקת רשימה שכבר נקראה.
    return 0;
  end if;

  delete from viperflow_order_items where event_id = p_event;

  insert into viperflow_order_items (
    event_id, connection_id, external_item_id, parent_external_item_id,
    line_type, name, quantity, spare_quantity, is_component, component_type,
    is_custom, options, notes, position)
  select
    p_event,
    p_connection,
    case when i.value ->> 'id' ~* '^[0-9a-f-]{36}$' then (i.value ->> 'id')::uuid end,
    case when i.value ->> 'parent_item_id' ~* '^[0-9a-f-]{36}$'
         then (i.value ->> 'parent_item_id')::uuid end,
    coalesce(nullif(i.value ->> 'line_type', ''), 'product'),
    coalesce(nullif(btrim(i.value ->> 'name'), ''), 'פריט'),
    coalesce((i.value ->> 'quantity')::numeric, 0),
    coalesce((i.value ->> 'spare_quantity')::numeric, 0),
    coalesce((i.value ->> 'is_component')::boolean, false),
    nullif(i.value ->> 'component_type', ''),
    coalesce((i.value ->> 'is_custom')::boolean, false),
    -- רק מה שאדם קורא: שם הקבוצה והערך שנבחר. מזהי הקטלוג של ViperFlow
    -- אינם אומרים דבר למי שמחזיק את הרשימה במחסן.
    coalesce((
      select jsonb_agg(jsonb_build_object(
               'group', nullif(o ->> 'group_name', ''),
               'value', nullif(o ->> 'value', '')))
      from jsonb_array_elements(
             case when jsonb_typeof(i.value -> 'options') = 'array'
                  then i.value -> 'options' else '[]'::jsonb end) o
      where nullif(o ->> 'value', '') is not null), '[]'::jsonb),
    nullif(btrim(i.value ->> 'notes'), ''),
    -- הסדר שבו ViperFlow שלח: אב אחרי אב, והרכיבים של כל אב מיד אחריו.
    i.ordinality::int
  from jsonb_array_elements(p_items) with ordinality as i(value, ordinality);

  get diagnostics v_count = row_count;
  return v_count;
end $$;

-- ===== 3. המשימה שההזמנה קובעת את שעתה ====================================
--
-- ממלאת את המשימה שהטריגר של 0003 כבר יצר, ויוצרת אותה רק אם אינה קיימת —
-- אותה החלטה ואותו סדר של `apply_import_tasks` (0052) ושל
-- `apply_event_task_block` (0136). ההבדל היחיד: כאן `coalesce` אינו מספיק.
-- הייבוא *משלים* שדות ריקים; הסנכרון **דורס**, כי הוא הבעלים של השעה.
--
-- ‏`p_warehouse` ריק אינו מוחק שעת יציאה קיימת: הזמנה בלי חיץ (`buffer_hours`
-- ריק = ברירת המחדל של החשבון) אינה אומרת "צאו בשעת האירוע".
create or replace function app.viperflow_apply_task(
  p_event      uuid,
  p_code       text,
  p_date       date,
  p_onsite     time,
  p_warehouse  time,
  p_workers    int,
  -- ‏true כשההזמנה כן קבעה יציאה מהמחסן אבל היא אינה ניתנת לביטוי: חיץ
  -- שנסוג ליום הקודם. אז השדה **מתרוקן** ואינו נשאר על מה שסנכרון קודם
  -- כתב — שעה שגויה גרועה מהיעדר שעה, כי היא נראית כמו החלטה.
  p_clear_warehouse boolean default false)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_type    task_types;
  v_event   events;
  v_task_id uuid;
  v_sys     boolean := app.in_system_write();
begin
  if p_date is null and p_onsite is null and p_warehouse is null and p_workers is null
     and not coalesce(p_clear_warehouse, false) then
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
    task_date            = coalesce(p_date, task_date),
    onsite_start_time    = coalesce(p_onsite, onsite_start_time),
    warehouse_start_time = case
                             when p_warehouse is not null then p_warehouse
                             when coalesce(p_clear_warehouse, false) then null
                             else warehouse_start_time end,
    worker_count         = coalesce(p_workers, worker_count)
  where id = v_task_id;

  if not v_sys then perform app.system_write(false); end if;
  return v_task_id;
end $$;

-- ===== 4. ההזמנה עצמה =====================================================

/**
 * מתרגם הזמנה אחת לאירוע אחד, ומחזיר את מזהה האירוע.
 *
 * ‏`p_event_type` הוא סוג האירוע ב-ViperFlow ולא סוג האירוע אצלנו: הוא משמש
 * להבחנה אחת בלבד — `order.deleted` נושא תמונת מצב מינימלית ולא הזמנה מלאה,
 * ולכן הוא מבטל ואינו מתרגם.
 */
create or replace function app.viperflow_apply_order(
  p_connection uuid,
  p_order      jsonb,
  p_event_type text,
  -- ‏§3 של שומר הסדר מגן על המקרה השכיח — ניסיון חוזר שהתעכב — אבל
  -- ‏`updated_at` של ViperFlow הוא זמן *תחילת* הטרנזקציה, ולכן יש חלון צר
  -- שבו שינוי מאוחר נושא חותמת מוקדמת ונדחה לתמיד. ‏`p_force` הוא הדרך
  -- חזרה: היא פתוחה רק ל-`integrations.manage` ולסנכרון היזום, והיא אומרת
  -- "מה שבמעטפה הוא האמת, בלי קשר לחותמת".
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
  v_warehouse   timestamp;
  v_buffer      int;
  v_items       int := 0;
  v_note        text;
  v_parts       text[] := '{}';
  v_sys         boolean := app.in_system_write();
  v_current     text;
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

  -- נעילה פר-הזמנה, לפני קריאת הקישור.
  --
  -- ‏ViperFlow מוציא משלוחים בבריכה מקבילה של שמונה, והקיבוץ שלו ממזג רק
  -- מעטפות שטרם יצאו — כלומר שני משלוחים של *אותה* הזמנה יכולים להגיע בו
  -- זמנית. בלי הנעילה שניהם היו קוראים "אין קישור", שניהם היו יוצרים אירוע,
  -- והשני היה נופל על `unique (connection_id, order_id)` ונרשם כנכשל: אירוע
  -- אחד תקין, ועבודה ידנית שאיש לא ביקש. עם הנעילה השני פשוט מחכה, רואה את
  -- הקישור שהראשון כתב, והופך לעדכון — שזה בדיוק מה שהוא.
  --
  -- זולה, כי היא פר-הזמנה ומשתחררת בסוף הטרנזקציה. אותו מכשיר של 0077 §4 על
  -- מספור גרסאות המפרט.
  perform pg_advisory_xact_lock(
    hashtextextended(p_connection::text || ':' || v_order_id::text, 0));

  select * into v_link from viperflow_links
   where connection_id = p_connection and order_id = v_order_id;

  -- ‏§3 בראש הקובץ: משלוח שנושא חותמת ישנה ממה שכבר הוחל אינו מתקדם.
  -- שוויון כן מוחל: הוא ניסיון חוזר של אותו שינוי, וההחלה אידמפוטנטית.
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
    -- הסטטוס נקרא למשתנה ולא נכתב מתוך תת-שאילתה: מסד שבו "בוטל" נמחק ממסך
    -- ההגדרות היה מחזיר null, והתנאי `is distinct from null` היה מכניס אותו
    -- לעמודה. אירוע בלי סטטוס אינו ביטול — הוא אירוע שבור.
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
  v_buffer     := nullif(p_order #>> '{buffer_hours,before}', '')::int;

  if v_event_date is null then
    raise exception 'הזמנה % בלי תאריך אירוע', coalesce(v_number, v_order_id::text);
  end if;

  perform app.system_write(true);

  if v_link.event_id is null then
    -- ── לידה ────────────────────────────────────────────────────────────────
    --
    -- **אלא אם ההזמנה הזו כבר מתה.** ‏ViperFlow מבטיח at-least-once ואינו
    -- מבטיח סדר: ‏`order.created` שהתעכב יכול להגיע *אחרי* ה-`order.deleted`
    -- של אותה הזמנה, וכשאין קישור הביטול לא השאיר סימן — אז היינו יוצרים
    -- אירוע לערב שכבר בוטל, ומישהו היה צריך לגלות ולבטל אותו ביד. יומן
    -- המשלוחים הוא הסימן: הוא כבר נושא את המחיקה, והשאלה עולה כאן בלבד —
    -- בנתיב הלידה, ופעם אחת לכל הזמנה.
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

    -- מספר האירוע נלקח ממספר ההזמנה, אך ורק אם הוא פנוי אצל הלקוח הזה:
    -- ‏`events_customer_number_uq` ייחודי, ואירוע שרכז הקליד ידנית באותו מספר
    -- אינו נעלם בגלל שהגיעה הזמנה. במקרה כזה האירוע נולד בלי מספר, והיומן
    -- אומר למה.
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
      -- מספר האירוע נכתב רק אם הוא עדיין ריק אצלנו ופנוי אצל הלקוח.
      event_number    = case
        when event_number is null and v_number is not null and not exists (
               select 1 from events e2
                where e2.customer_id = events.customer_id
                  and e2.event_number = v_number and e2.deleted_at is null)
        then v_number else event_number end
     where id = v_event_id;

    -- ‏§1: הערה חדשה נאמרת ואינה נכתבת על מה שרכז כתב. ההשוואה היא מול
    -- ה-`notes` שאצלנו — כל עוד הם זהים איש לא שינה אותם משני הצדדים, ומרגע
    -- שהם נפרדו, הערה של ViperFlow היא ידיעה ליומן ולא כתיבה על השדה.
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

  -- ── הסטטוס: קדימה בלבד (§2) ─────────────────────────────────────────────
  select s.code into v_current from events e
    join statuses s on s.id = e.status_id where e.id = v_event_id;

  -- ‏`v_current` ריק הוא סטטוס שנוצר ידנית במסך ההגדרות (‏`code` null,
  -- 0036), והוא הכרעה של המשרד שהאינטגרציה אינה מבינה — ולכן אינה נוגעת בה.
  if v_status in ('confirmed', 'picked', 'delivered', 'returned')
     and v_current = 'pending' then
    select id into v_status_id from statuses
     where entity = 'event' and code = 'approved' and deleted_at is null limit 1;
    if v_status_id is not null then
      update events set status_id = v_status_id where id = v_event_id;
      -- הקאסט אינו קישוט: ‏`text[] || 'literal'` הוא עמום, ופוסטגרס בוחר
      -- לפרש את המחרוזת כמערך ונופל על "malformed array literal".
      v_parts := v_parts || 'ההזמנה אושרה — האירוע עבר ל״אישור סופי״'::text;
    end if;
  end if;

  -- ── שתי המשימות ────────────────────────────────────────────────────────
  --
  -- ‏`buffer_hours.before` של ViperFlow הוא הזמן שהציוד צריך להיות בדרך לפני
  -- האירוע, וזו בדיוק "יציאה מהמחסן" אצלנו. חיץ שחוצה חצות הוא היוצא מן
  -- הכלל: ‏`warehouse_start_time` הוא `time` על `task_date` ואינו יודע לומר
  -- "אתמול ב-23:00", ולכן במקרה כזה הוא אינו נכתב כלל — שעה שנראית כמו
  -- 23:00 של יום האירוע גרועה מהיעדר שעה. היומן אומר את המספר האמיתי,
  -- והרכז מפצל את המשימה בעצמו.
  if v_delivery is not null then
    v_warehouse := case when v_buffer is not null and v_buffer > 0
                        then v_delivery - make_interval(hours => v_buffer) end;

    perform app.viperflow_apply_task(
      v_event_id, 'setup',
      v_delivery::date,
      v_delivery::time,
      case when v_warehouse::date = v_delivery::date then v_warehouse::time end,
      v_workers::int,
      -- חיץ שכן נקבע אך נסוג ליום הקודם: השדה מתרוקן ואינו נשאר על מה
      -- שסנכרון קודם כתב.
      v_warehouse is not null and v_warehouse::date <> v_delivery::date);

    v_parts := v_parts || ('הקמה ' || to_char(v_delivery, 'DD/MM/YYYY HH24:MI')
      || case
           when v_warehouse is null then ''
           when v_warehouse::date = v_delivery::date
             then ' (יציאה מהמחסן ' || to_char(v_warehouse, 'HH24:MI') || ')'
           else ' (יציאה מהמחסן ' || to_char(v_warehouse, 'DD/MM HH24:MI') ||
                ' — יום קודם, לא נכתבה על המשימה)'
         end);
  end if;

  if v_return is not null then
    perform app.viperflow_apply_task(
      v_event_id, 'teardown', v_return::date, v_return::time, null, v_workers::int);
    v_parts := v_parts || ('פירוק ' || to_char(v_return, 'DD/MM/YYYY HH24:MI'));
  end if;

  -- ── הריהוט ─────────────────────────────────────────────────────────────
  v_items := app.viperflow_apply_items(v_event_id, p_connection, p_order -> 'items');
  if v_items > 0 then
    v_parts := v_parts || (v_items || ' שורות בהזמנה');
  end if;

  if not v_sys then perform app.system_write(false); end if;

  -- שורת יומן אחת לכל סנכרון. שינויי השדות עצמם נרשמים ממילא בטריגרים של
  -- 0016 ו-0112, וזו השורה שאומרת *למה* הם קרו.
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

-- ===== 5. הכניסה: מעטפה אחת ===============================================
--
-- זו הפונקציה היחידה שפונקציית הקצה קוראת. היא מקבלת את המעטפה **אחרי**
-- אימות החתימה ואחרי ניקוי הכסף, ועושה שלושה דברים בסדר הזה: רושמת את
-- המשלוח (וכך גם מכריעה על כפילות), מתרגמת, ומסמנת מה יצא.
--
-- **כישלון עסקי אינו שגיאה כלפי חוץ.** ‏ViperFlow מפרש כל 4xx שאינו
-- 408/425/429 כ"אל תנסה שוב לעולם", ומכבה נקודת קצה אחרי עשרה כישלונות
-- רצופים — כלומר מעטפה אחת שהמתרגם לא ידע לעכל הייתה יכולה לנתק את החיבור
-- כולו. לכן כל חריגה נתפסת כאן, נרשמת כ-'failed' עם הסיבה, והפונקציה מחזירה
-- תשובה תקינה. מה שנשאר הוא שורה אדומה במסך, וכפתור "הרץ מחדש".
create or replace function viperflow_ingest(p_envelope jsonb, p_meta jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_event_id   text := p_envelope ->> 'id';
  v_type       text := p_envelope ->> 'type';
  v_data       jsonb := p_envelope -> 'data';
  v_conn       uuid;
  v_active     int;
  v_row        uuid;
  v_result     jsonb;
  v_entity     text;
begin
  -- קורא עם JWT הוא אדם שלחץ "הרץ מחדש" (§6); בלי JWT זו פונקציית הקצה
  -- בזהות service role. אותה הבחנה של `fleet_expiry_sweep` (0089).
  if auth.uid() is not null then
    perform app.require('integrations.manage', 'אין לך הרשאה להזרים אירועי ViperFlow');
  end if;

  if coalesce(v_event_id, '') !~ '^evt_[0-9a-f]{32}$' or coalesce(v_type, '') = '' then
    raise exception 'מעטפה פגומה' using errcode = '22023';
  end if;

  -- מי כותב ביומן כשאיש לא לחץ (0176 §2). התווית מקומית לטרנזקציה, ולכן
  -- שינויי השדות שהטריגרים של 0016/0112 ירשמו בהמשך יישאו את השם הזה —
  -- ורק הם: כל שאר המערכת פשוט אינה מגדירה את ה-GUC הזה.
  perform set_config('app.actor_label', 'ViperFlow', true);

  -- החיבור: לפי מה שפונקציית הקצה זיהתה מהנתיב, ואם לא — החיבור הפעיל
  -- **היחיד**.
  --
  -- ‏`into` על שאילתה שמחזירה שתי שורות לוקח את הראשונה ולא מתלונן, וזה היה
  -- מפיל הזמנה של לקוח אחד על הלקוח השני. לכן הספירה: אחד נבחר, יותר מאחד
  -- נרשם ככישלון עם סיבה שאומרת בדיוק מה לעשות — להוסיף את מזהה החיבור
  -- לכתובת נקודת הקצה.
  v_conn := nullif(p_meta ->> 'connection_id', '')::uuid;
  if v_conn is null then
    select count(*), min(c.id) into v_active, v_conn
      from viperflow_connections c
     where c.is_active and c.deleted_at is null;
    if v_active <> 1 then v_conn := null; end if;
  end if;

  v_entity := v_data ->> 'id';

  insert into viperflow_deliveries (
    connection_id, event_id, delivery_id, event_type, attempt, origin,
    entity_id, occurred_at, payload)
  values (
    v_conn, v_event_id, nullif(p_meta ->> 'delivery_id', ''), v_type,
    nullif(p_meta ->> 'attempt', '')::int, nullif(p_meta ->> 'origin', ''),
    v_entity, nullif(p_envelope ->> 'created_at', '')::timestamptz, p_envelope)
  on conflict (event_id) do nothing
  returning id into v_row;

  -- ניסיון חוזר של אותו אירוע. ‏ViperFlow מבטיח at-least-once, והאינדקס
  -- הייחודי הוא כל מנגנון האי-כפילות.
  --
  -- ‏`force` מדלג גם על זה, ובכוונה: הוא הכלי של מי שאומר "המצב אצלנו שגוי,
  -- משוך שוב" — ותשובת "כבר ראינו את המעטפה הזו" היא בדיוק מה שהוא מנסה
  -- לעקוף. השורה הקיימת נכתבת מחדש ואינה מוכפלת.
  if v_row is null then
    if not coalesce((p_meta ->> 'force')::boolean, false) then
      return jsonb_build_object('status', 'duplicate', 'event_id', v_event_id);
    end if;
    select id into v_row from viperflow_deliveries where event_id = v_event_id;
  end if;

  begin
    if v_type = 'webhook.test' then
      v_result := jsonb_build_object('status', 'ignored', 'reason', 'אירוע בדיקה');
    elsif v_conn is null then
      v_result := jsonb_build_object('status', 'failed', 'reason',
        case when coalesce(v_active, 0) > 1
             then 'יש ' || v_active || ' חיבורים פעילים ולא נאמר לאיזה מהם — יש להוסיף את מזהה החיבור לכתובת נקודת הקצה'
             else 'אין חיבור ViperFlow פעיל' end);
    elsif v_type in ('order.created', 'order.updated', 'order.confirmed',
                     'order.status_changed', 'order.picked', 'order.delivered',
                     'order.returned', 'order.cancelled', 'order.deleted') then
      v_result := app.viperflow_apply_order(
        v_conn, v_data, v_type, coalesce((p_meta ->> 'force')::boolean, false));
    else
      -- ‏41 סוגי אירוע קיימים אצלם, ורובם אינם אומרים דבר על עבודה שלנו.
      -- הם נרשמים כדי שיהיה אפשר לראות מה נכנס, ולא מתורגמים.
      v_result := jsonb_build_object('status', 'ignored',
                                     'reason', 'סוג אירוע שאינו מתורגם');
    end if;
  exception when others then
    -- **לא כל כישלון הוא כישלון עסקי.** ‏deadlock מול רכז ששומר את אותו
    -- אירוע, נעילה שלא התפנתה, או statement_timeout על הזמנה כבדה — כולם
    -- ייעלמו בניסיון הבא, ולכן הם צריכים להיזרק החוצה: ה-RPC ייכשל,
    -- פונקציית הקצה תענה 503, ו-ViperFlow ינסה שוב לפי לוח הזמנים שלו.
    -- ‏`failed` שמור למה שלא ישתנה מעצמו — "הזמנה בלי תאריך אירוע" — ושם
    -- דווקא נכון להחזיר 200, כי ניסיון חוזר רק יבזבז את עשרת הכישלונות
    -- שאחריהם הם מכבים את נקודת הקצה.
    if sqlstate like '40%' or sqlstate like '53%' or sqlstate in ('55P03', '57014') then
      raise;
    end if;

    update viperflow_deliveries set
      status = 'failed', reason = left(sqlerrm, 500), processed_at = now()
     where id = v_row;
    return jsonb_build_object('status', 'failed', 'event_id', v_event_id,
                              'reason', sqlerrm);
  end;

  update viperflow_deliveries set
    status = case v_result ->> 'status'
               when 'processed' then 'processed'
               when 'stale'     then 'ignored'
               when 'failed'    then 'failed'
               else 'ignored' end,
    reason = coalesce(v_result ->> 'reason',
                      case when v_result ->> 'status' = 'stale'
                           then 'משלוח ישן — כבר הוחל עדכון חדש יותר' end),
    event_row_id = nullif(v_result ->> 'event_id', '')::uuid,
    processed_at = now()
   where id = v_row;

  return v_result || jsonb_build_object('delivery', v_row);
end $$;

revoke execute on function viperflow_ingest(jsonb, jsonb) from anon, public;
grant  execute on function viperflow_ingest(jsonb, jsonb) to service_role, authenticated;

-- ===== 6. הרצה מחדש =======================================================
--
-- המעטפה שמורה אצלנו (0176 §3), ולכן "הרץ מחדש" אינו מבקש דבר מ-ViperFlow
-- וגם אינו תלוי בכך שהיא עדיין קיימת שם — הם שומרים שלושים יום.
--
-- השורה הישנה נמחקת ונכתבת מחדש ולא מתעדכנת במקומה: `viperflow_ingest`
-- נשענת על ה-insert כדי להכריע כפילות, והיסטוריה שבה משלוח שנכשל ואז הצליח
-- מוצגת כשורה אחת שתמיד הצליחה היא היסטוריה משוכתבת. מה שנשמר הוא
-- `received_at` המקורי.
create or replace function viperflow_replay(p_delivery uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_row      viperflow_deliveries;
  v_meta     jsonb;
  v_result   jsonb;
begin
  perform app.require('integrations.manage', 'אין לך הרשאה להריץ מחדש משלוח');

  select * into v_row from viperflow_deliveries where id = p_delivery;
  if v_row.id is null then raise exception 'משלוח לא נמצא'; end if;

  v_meta := jsonb_build_object(
    'connection_id', v_row.connection_id,
    'delivery_id',   v_row.delivery_id,
    'attempt',       v_row.attempt,
    'origin',        v_row.origin);

  delete from viperflow_deliveries where id = p_delivery;
  v_result := viperflow_ingest(v_row.payload, v_meta);

  update viperflow_deliveries set received_at = v_row.received_at
   where event_id = v_row.event_id;

  return v_result;
end $$;

revoke execute on function viperflow_replay(uuid) from anon, public;
grant  execute on function viperflow_replay(uuid) to authenticated;

-- ===== 6א. והמתרגם עצמו סגור בפני כולם ====================================
--
-- ‏`schema app` פתוח ל-authenticated (0010:35), ושלוש הפונקציות שלמטה הן
-- ‏`security definer` שכותבות אירועים ומשימות מתחת ל-`app.system_write` —
-- כלומר מעקפות את השער ברמת העמודה. בלי ה-revoke, כל משתמש מאומת היה יכול
-- לקרוא להן ישירות ולכתוב אירוע בשם המערכת. אותה הקפדה בדיוק של 0052 §4 על
-- ‏`app.apply_import_tasks`: הדרך היחידה להגיע אליהן היא `viperflow_ingest`,
-- שאוכפת את `integrations.manage` על כל קורא שיש לו JWT.
--
-- שתי העזר הטהורות סגורות איתן, מאותו נימוק שכתוב שם על `resolve_task_type`:
-- מה שאין לו קורא חוקי מחוץ למודול אינו צריך להיות פתוח.

revoke execute on function app.viperflow_local(text)
  from anon, authenticated, public;
revoke execute on function app.viperflow_line_quantity(jsonb, text)
  from anon, authenticated, public;
revoke execute on function app.viperflow_apply_items(uuid, uuid, jsonb)
  from anon, authenticated, public;
revoke execute on function app.viperflow_apply_task(uuid, text, date, time, time, int, boolean)
  from anon, authenticated, public;
revoke execute on function app.viperflow_apply_order(uuid, jsonb, text, boolean)
  from anon, authenticated, public;

-- ===== 7. מה שהאירוע יודע לספר על עצמו ====================================
--
-- ‏`security invoker` במכוון: הפוליסות של 0176 §5 הן שמכריעות מי רואה, וה-
-- ‏view אינו אמור להוסיף להן ולא לגרוע מהן. הוא קיים כדי שהמסך יבקש שאילתה
-- אחת במקום שתיים.
--
-- ‏**`left join` על החיבור, ולא `join`.** שתי הטבלאות נקראות בשני מפתחות
-- שונים: הקישור שייך למי שהאירוע נפתח לו, והחיבור למי שמחזיק
-- `integrations.view`. ‏`join` רגיל היה מחיל את השני על הראשון — עובד שטח
-- היה מקבל שורה ריקה במקום מספר ההזמנה של האירוע שהוא נוסע אליו. עם
-- ‏`left join` הוא מקבל את העובדות שלו, ושם החיבור נשאר ריק אצל מי שאינו
-- אמור לדעת אותו.
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
           and not i.is_component) as furniture_lines
from viperflow_links l
left join viperflow_connections c on c.id = l.connection_id;

grant select on viperflow_event_link to authenticated;
revoke all on viperflow_event_link from anon;
