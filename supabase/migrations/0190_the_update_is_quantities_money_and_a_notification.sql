-- 0190: בעדכון מסתנכרנות כמויות ומחירים, וכל השאר מגיע כהתראה
--
-- ‏0187 ו-0189 הזיזו שני שדות מ"ViperFlow הבעלים" ל"שלנו" — שעת ההגעה למחסן
-- והמיקום — וכל אחד מהם היה תיקון של אותה תקלה: **עדכון של ההזמנה דרס עבודה
-- שאדם עשה.** הקובץ הזה מפסיק לתקן שדה-שדה ואומר את הכלל:
--
--   **בלידה** ההזמנה קובעת הכול, כי אין דבר אחר.
--   **בעדכון** היא קובעת שלושה דברים בלבד: **כמות משאיות, כמות עובדים
--   ומחירים.** אלה מספרים שהלקוח הסופי סוכם עליהם, ואין אצלנו מי שיקבע
--   אותם אחרת.
--
--   כל השאר — תאריך, שעות, אולם, שם הלקוח, הערה, מפרט — **אינו נכתב**,
--   ו**נאמר**: ההזמנה השתנתה, וההתראה מפרטת מה. הרכז מחליט אם להזיז.
--
-- ארבע הכרעות שנגזרות מזה:
--
-- ‏1. **מה שנוצר חסר — נוצר.** משימת פירוק שלא הייתה (הזמנה בלי תאריך החזרה)
--    ונולדה בהזמנה מאוחר יותר, נוצרת עם התאריך והשעה שלה. "לא לדרוס" אינו
--    "לא למלא": משימה שאינה קיימת אין בה עבודה של אדם למחוק.
--
-- ‏2. **מחיר הריהוט מתפצל לפי מצב הפריט בקטלוג.** ‏שיא עיצובים מפרידה
--    "ריהוט ישן" מ"ריהוט חדש" — שתי קטגוריות הכנסה עם אחוזי חלוקה שונים
--    (70% ו-20%) — והפרדה הזו הוקלדה עד היום ביד, אירוע-אירוע. מעכשיו היא
--    נגזרת מהקטלוג: **מה שאינו מוגדר "ציוד חדש" הוא ישן**, וזה בדיוק
--    ה-coalesce שבקוד. הדגל עצמו אינו במעטפת ההזמנה — פונקציית הקצה שואלת
--    עליו את הקטלוג ומסמנת כל שורה לפני שהיא מגישה למתרגם.
--
-- ‏3. **ההשוואה היא מול ההזמנה הקודמת, לא מולנו.** ברגע שהפסקנו לכתוב
--    תאריכים, האירוע *אמור* להיות שונה מההזמנה — הרכז הזיז אותו. השוואה
--    מול האירוע הייתה מייצרת את אותה התראה בכל סנכרון, לנצח. לכן
--    ‏`viperflow_links.order_snapshot`: צילום של מה שההזמנה אמרה בפעם
--    הקודמת, וההתראה היא ההפרש בין שני הצילומים.
--
-- ‏4. **"לא ידוע" אינו שינוי.** צד ריק בהשוואה מדלג. כשהקטלוג לא נקרא
--    (מפתח בלי `products:read`), מחירי הריהוט אינם ידועים — ואז הם אינם
--    נכתבים, אינם מתאפסים, ואינם מדווחים כשינוי.

-- ===== 1. הצילום על הקישור ================================================

alter table viperflow_links
  add column order_snapshot jsonb;

comment on column viperflow_links.order_snapshot is
  'מה שההזמנה אמרה בסנכרון האחרון — הבסיס להשוואה של ההתראה (0190). '
  'null בקישור שנוצר לפני 0190, והסנכרון הבא ממלא אותו בלי לדווח.';

-- ===== 2. איזו קטגוריית הכנסה היא "חדש" ואיזו "ישן" =======================
--
-- עמודה ולא השוואת שם: הקטגוריות ניתנות לשינוי שם במסך ההגדרות, ושם הוא
-- תווית לאדם — לא מפתח. המיגרציה מזריעה את השתיים הקיימות לפי שמן, ומכאן
-- הקוד קורא את העמודה בלבד.
alter table income_categories
  add column viperflow_item_state text
    check (viperflow_item_state in ('new', 'old'));

comment on column income_categories.viperflow_item_state is
  'לאיזה מצב פריט בקטלוג של ViperFlow הקטגוריה הזו מקבלת את הסכום: '
  'new = ציוד חדש, old = כל השאר. null = אינה מקבלת סכום מהאינטגרציה (0190).';

create unique index income_categories_viperflow_state_uq
  on income_categories (viperflow_item_state)
  where viperflow_item_state is not null and deleted_at is null;

update income_categories set viperflow_item_state = 'old'
 where name = 'ריהוט ישן' and deleted_at is null;
update income_categories set viperflow_item_state = 'new'
 where name = 'ריהוט חדש' and deleted_at is null;

-- ===== 3. סכום הריהוט לפי מצב הפריט =======================================
--
-- ‏`coalesce(is_new, false)` הוא הכלל כלשונו: מה שאינו מוגדר כציוד חדש הוא
-- ישן. ‏0 מוחזר כ-0 ולא כ-null — בשונה מ-`viperflow_line_amount` — כי כאן
-- "לא הוזמן ריהוט חדש" הוא עובדה שצריכה להיכתב, ולא היעדר ידיעה.
create or replace function app.viperflow_furniture_amount(p_items jsonb, p_new boolean)
returns numeric language sql stable set search_path = public as $$
  select coalesce(sum(coalesce((i ->> 'line_total')::numeric, 0)), 0)
  from jsonb_array_elements(
         case when jsonb_typeof(p_items) = 'array' then p_items else '[]'::jsonb end) i
  where i ->> 'line_type' = 'product'
    and coalesce((i ->> 'is_component')::boolean, false) = false
    and coalesce((i ->> 'is_new')::boolean, false) = p_new;
$$;

comment on function app.viperflow_furniture_amount(jsonb, boolean) is
  'סכום `line_total` של שורות הריהוט לפי מצב הפריט. מה שאינו new הוא old (0190).';

-- ===== 4. כתיבת ההכנסה על האירוע ==========================================
--
-- אותו כלל של `app.apply_event_income` (0068): הקטגוריה נכתבת רק אם היא
-- **מופעלת ללקוח**, ו-`viper_share_pct` הוא צילום של האחוז ברגע הכתיבה.
-- קטגוריה שאינה מופעלת אינה שגיאה כאן אלא שתיקה: האינטגרציה אינה המקום
-- שבו מחליטים מה מופעל למי.
create or replace function app.viperflow_apply_income(
  p_event    uuid,
  p_customer uuid,
  p_state    text,
  p_amount   numeric)
returns boolean language plpgsql security definer set search_path = public as $$
declare
  v_cat uuid;
  v_pct numeric;
  v_sys boolean := app.in_system_write();
begin
  if p_event is null or p_amount is null then return false; end if;

  select id into v_cat from income_categories
   where viperflow_item_state = p_state and is_active and deleted_at is null
   order by sort_order, id limit 1;
  if v_cat is null then return false; end if;

  select s.viper_share_pct into v_pct from customer_income_splits s
   where s.customer_id = p_customer and s.category_id = v_cat;
  if v_pct is null then return false; end if;

  perform app.system_write(true);
  insert into event_income (event_id, category_id, amount, viper_share_pct)
  values (p_event, v_cat, p_amount, v_pct)
  on conflict (event_id, category_id) do update
    set amount          = excluded.amount,
        viper_share_pct = excluded.viper_share_pct;
  if not v_sys then perform app.system_write(false); end if;
  return true;
end $$;

comment on function app.viperflow_apply_income(uuid, uuid, text, numeric) is
  'כותב סכום ריהוט מ-ViperFlow לקטגוריית ההכנסה שמסומנת לאותו מצב פריט (0190).';

-- ===== 5. טביעת האצבע של המפרט ============================================
--
-- ‏"השתנה מפרט" נמדד על מה שנשמר, לא על המעטפה: אותה רשימה שמגיעה בסדר אחר
-- או עם מזהי שורה חדשים (ViperFlow כותב אותם מחדש בכל שמירה, 0176 §4.4)
-- אינה שינוי. מה שנחשב: שם, כמות, עודף, בחירות והערה — כלומר מה שקוראים
-- במחסן.
create or replace function app.viperflow_items_fingerprint(p_event uuid)
returns text language sql stable security definer set search_path = public as $$
  select md5(coalesce(string_agg(
    i.name || '|' || i.quantity::text || '|' || i.spare_quantity::text || '|' ||
    coalesce(i.options::text, '') || '|' || coalesce(i.notes, ''),
    E'\n' order by i.name, i.quantity, i.id), ''))
  from viperflow_order_items i
  where i.event_id = p_event and i.line_type = 'product' and not i.is_component;
$$;

-- ===== 6. ההפרש בין שני צילומים ===========================================
--
-- הפלט הוא שורות לאדם, לא מבנה למכונה: הוא נכנס גם ליומן הפעילות וגם לגוף
-- ההתראה. הצורה `שדה: עכשיו (היה קודם)` ולא חץ — חץ בין שני מספרים בתוך
-- טקסט עברי נקרא לשני הכיוונים, ו"היה" אינו משתמע לשתי פנים.
-- סטטוס ההזמנה הוא קוד באנגלית אצלם, וההתראה נקראת בעברית אצלנו.
create or replace function app.viperflow_status_label(p_status text)
returns text language sql immutable as $$
  select case p_status
    when 'draft'     then 'טיוטה'
    when 'confirmed' then 'מאושרת'
    when 'picked'    then 'נאספה'
    when 'delivered' then 'נמסרה'
    when 'returned'  then 'הוחזרה'
    when 'cancelled' then 'בוטלה'
    else coalesce(p_status, '') end;
$$;

create or replace function app.viperflow_changes(p_before jsonb, p_after jsonb)
returns text[] language plpgsql stable set search_path = public as $$
declare
  v_out    text[] := '{}';
  v_keys   text[] := array['event_date', 'delivery', 'return', 'location', 'customer_name',
                           'notes', 'status', 'trucks', 'workers',
                           'logistics', 'furniture_old', 'furniture_new'];
  v_labels text[] := array['תאריך האירוע', 'ההקמה', 'הפירוק', 'האולם', 'הלקוח הסופי',
                           'הערת ההזמנה', 'סטטוס ההזמנה', 'כמות משאיות', 'כמות עובדים',
                           'מחיר הלוגיסטיקה', 'ריהוט ישן', 'ריהוט חדש'];
  v_money  text[] := array['logistics', 'furniture_old', 'furniture_new'];
  i        int;
  v_old    text;
  v_new    text;
begin
  if p_before is null or p_after is null then return '{}'; end if;

  -- המפרט אומר "השתנה" ולא "מה": מאה שורות אינן נכנסות לגוף התראה, ומי
  -- שרוצה לראות לוחץ "מפרט".
  if nullif(p_before ->> 'items', '') is not null
     and nullif(p_after ->> 'items', '') is not null
     and p_before ->> 'items' is distinct from p_after ->> 'items' then
    v_out := v_out || 'השתנה מפרט'::text;
  end if;

  for i in 1 .. array_length(v_keys, 1) loop
    v_old := nullif(p_before ->> v_keys[i], '');
    v_new := nullif(p_after  ->> v_keys[i], '');
    -- צד ריק הוא "לא ידוע", ולא ידוע אינו שינוי (§4 בראש הקובץ).
    continue when v_old is null or v_new is null or v_old = v_new;

    if v_keys[i] = any(v_money) then
      v_out := v_out || (v_labels[i] || ': ' || to_char(v_new::numeric, 'FM999G999G990D00')
                         || ' ₪ (היה ' || to_char(v_old::numeric, 'FM999G999G990D00') || ' ₪)');
    elsif v_keys[i] = 'status' then
      v_out := v_out || ('סטטוס ההזמנה: ' || app.viperflow_status_label(v_new)
                         || ' (היה ' || app.viperflow_status_label(v_old) || ')');
    elsif v_keys[i] = 'notes' then
      -- ההערה היא פרוזה, ושתי פסקאות בגוף התראה אינן נקראות.
      v_out := v_out || 'הערת ההזמנה השתנתה'::text;
    else
      v_out := v_out || (v_labels[i] || ': ' || left(v_new, 100)
                         || ' (היה ' || left(v_old, 100) || ')');
    end if;
  end loop;

  return v_out;
end $$;

comment on function app.viperflow_changes(jsonb, jsonb) is
  'מה השתנה בין שני צילומי הזמנה, כשורות לאדם — ליומן ולהתראה (0190).';

-- ===== 7. ההתראה ==========================================================

select app.register_notification_type('viperflow_order_changed',
  'ההזמנה השתנתה ב-ViperFlow',
  'שינוי בהזמנה של לקוח שמחובר ל-ViperFlow: מפרט, תאריך, שעות, כמויות או מחירים. '
  'מה שאינו כמות או מחיר אינו מוחל מעצמו — ההתראה היא שאומרת עליו',
  'אירועים', array['admin'], 'event', 'forced', 'opt_out', 'opt_in', 49);

-- כל מנהלי המערכת. אין כאן `app.profile_id()` לסנן — הסנכרון אינו אדם.
create or replace function app.viperflow_notify_change(
  p_event    uuid,
  p_customer uuid,
  p_number   text,
  p_changes  text[])
returns void language plpgsql security definer set search_path = public as $$
declare
  r      record;
  v_body text;
begin
  if p_event is null or coalesce(cardinality(p_changes), 0) = 0 then return; end if;
  if not app.notification_in_scope('viperflow_order_changed', 'customer', p_customer) then
    return;
  end if;

  v_body := coalesce((select name from customers where id = p_customer), 'ViperFlow')
         || coalesce(' · הזמנה ' || p_number, '')
         || ' — ' || array_to_string(p_changes, ' · ');

  for r in select id from profiles
    where is_admin and is_active and deleted_at is null
  loop
    perform app.notify(r.id, 'viperflow_order_changed', 'ההזמנה השתנתה ב-ViperFlow',
      left(v_body, 500), 'event', p_event);
  end loop;
end $$;

-- ===== 8. המשימה: הכול בלידה, כמות עובדים בעדכון ==========================
--
-- ‏`p_created` הוא "האירוע נולד עכשיו", ולכן המשימות שהטריגר של 0003 יצר
-- ריקות וממתינות למילוי. משימה שנוצרת *כאן* (פירוק שהופיע בהזמנה מאוחר
-- יותר) מתמלאת גם היא במלואה — אין בה עבודה של אדם לדרוס.
drop function if exists app.viperflow_apply_task(uuid, text, date, time, int);

create or replace function app.viperflow_apply_task(
  p_event   uuid,
  p_code    text,
  p_date    date,
  p_onsite  time,
  p_workers int,
  p_created boolean)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_type    task_types;
  v_event   events;
  v_task_id uuid;
  v_born    boolean := false;
  v_sys     boolean := app.in_system_write();
begin
  select * into v_type from task_types
   where code = p_code and is_active and deleted_at is null;
  -- סוג משימה שכובה במסך ההגדרות אינו נוצר מחדש מהאינטגרציה.
  if v_type.id is null then return null; end if;

  select * into v_event from events where id = p_event;
  if v_event.id is null then raise exception 'אירוע לא נמצא'; end if;

  select t.id into v_task_id from tasks t
   where t.event_id = p_event and t.task_type_id = v_type.id and t.deleted_at is null
   order by t.created_at, t.id
   limit 1;

  -- משימה קיימת מוחזרת תמיד, גם כשאין מה לכתוב בה: המחיר צריך את המזהה.
  -- משימה שאינה קיימת נוצרת רק כשיש ממה — לא פותחים משימה ריקה.
  if v_task_id is null then
    if p_date is null and p_onsite is null and p_workers is null then
      return null;
    end if;
    -- הדגל מורם לפני *כל* כתיבה ולא פעם אחת בראש (0012 §90).
    perform app.system_write(true);
    insert into tasks (event_id, customer_id, task_type_id, task_date, status_id,
                       worker_count, created_by)
    values (p_event, v_event.customer_id, v_type.id,
            coalesce(p_date, v_event.event_date),
            (select id from statuses where entity = 'task' and is_default and deleted_at is null limit 1),
            0, null)
    returning id into v_task_id;
    v_born := true;
  end if;

  perform app.system_write(true);
  if coalesce(p_created, false) or v_born then
    update tasks set
      task_date         = coalesce(p_date, task_date),
      onsite_start_time = coalesce(p_onsite, onsite_start_time),
      worker_count      = coalesce(p_workers, worker_count)
    where id = v_task_id;
  else
    -- ‏0190: בעדכון נכתבת כמות העובדים בלבד. התאריך והשעה נשארים מה שהמשרד
    -- קבע, ושינוי שלהם בהזמנה מגיע כהתראה.
    update tasks set
      worker_count = coalesce(p_workers, worker_count)
    where id = v_task_id;
  end if;

  if not v_sys then perform app.system_write(false); end if;
  return v_task_id;
end $$;

-- ===== 9. המתרגם =========================================================
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
  v_catalog     boolean;
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
  v_event_date := nullif(p_order #>> '{event,date}', '')::date;
  v_location   := nullif(btrim(p_order #>> '{event,location}'), '');
  v_trucks     := app.viperflow_line_quantity(p_order -> 'items', 'truck');
  v_workers    := app.viperflow_line_quantity(p_order -> 'items', 'worker');
  v_delivery   := app.viperflow_local(p_order ->> 'delivery_date');
  v_return     := app.viperflow_local(p_order ->> 'return_date');
  v_note       := nullif(btrim(p_order ->> 'notes'), '');

  if v_event_date is null then
    raise exception 'הזמנה % בלי תאריך אירוע', coalesce(v_number, v_order_id::text);
  end if;

  -- ‏`catalog_enriched` מורם בפונקציית הקצה אחרי שהיא שאלה את הקטלוג על כל
  -- מוצר. בלעדיו אין לנו דעה על חדש/ישן, ומחירי הריהוט אינם נכתבים כלל.
  v_catalog := coalesce((p_order ->> 'catalog_enriched')::boolean, false);
  if v_catalog then
    v_old_amount := app.viperflow_furniture_amount(p_order -> 'items', false);
    v_new_amount := app.viperflow_furniture_amount(p_order -> 'items', true);
  end if;

  v_logistics := case v_conn.logistics_price_source
                   when 'truck'     then app.viperflow_line_amount(p_order -> 'items', array['truck'])
                   when 'logistics' then app.viperflow_line_amount(p_order -> 'items', array['truck', 'worker'])
                 end;

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
  --
  -- לא ירד ב-0190: "אושר" ו"בוטל" אינם שדה שהרכז ממלא אלא מחזור החיים של
  -- ההזמנה, והם היחידים שמזיזים אירוע בלי שאיש יקליד.
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

  -- ── המחירים (0187, 0190) ────────────────────────────────────────────────
  if v_logistics is not null and v_logistics > 0
     and (v_setup is not null or v_teardown is not null) then
    v_half := round(v_logistics / 2, 2);
    perform app.viperflow_apply_price(v_setup, v_half, 'הקמה — מחצית מהלוגיסטיקה בהזמנה',
      'הזמנה ' || coalesce(v_number, v_order_id::text) || ' · ' || to_char(v_logistics, 'FM999G999G990D00') || ' ₪');
    perform app.viperflow_apply_price(v_teardown, v_half, 'פירוק — מחצית מהלוגיסטיקה בהזמנה',
      'הזמנה ' || coalesce(v_number, v_order_id::text) || ' · ' || to_char(v_logistics, 'FM999G999G990D00') || ' ₪');
    if v_created then
      v_parts := v_parts || ('מחיר מההזמנה ' || to_char(v_logistics, 'FM999G999G990D00')
        || ' ₪ — ' || to_char(v_half, 'FM999G999G990D00') || ' ₪ לכל משימה');
    end if;
  end if;

  if v_catalog then
    if app.viperflow_apply_income(v_event_id, v_conn.customer_id, 'old', v_old_amount)
       and v_created then
      v_parts := v_parts || ('ריהוט ישן ' || to_char(v_old_amount, 'FM999G999G990D00') || ' ₪');
    end if;
    if app.viperflow_apply_income(v_event_id, v_conn.customer_id, 'new', v_new_amount)
       and v_created then
      v_parts := v_parts || ('ריהוט חדש ' || to_char(v_new_amount, 'FM999G999G990D00') || ' ₪');
    end if;
  end if;

  -- ── הריהוט ─────────────────────────────────────────────────────────────
  v_items := app.viperflow_apply_items(v_event_id, p_connection, p_order -> 'items');
  if v_items > 0 and v_created then
    v_parts := v_parts || (v_items || ' שורות בהזמנה');
  end if;

  -- ── מה השתנה מאז הסנכרון הקודם (§3 בראש הקובץ) ──────────────────────────
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
    'logistics',     v_logistics,
    'furniture_old', v_old_amount,
    'furniture_new', v_new_amount,
    'items',         app.viperflow_items_fingerprint(v_event_id)));

  if not v_created then
    v_changes := app.viperflow_changes(v_link.order_snapshot, v_snapshot);
    if cardinality(v_changes) > 0 then
      v_parts := v_parts || v_changes;
    end if;
  end if;

  update viperflow_links set order_snapshot = v_snapshot where event_id = v_event_id;

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

-- ===== 10. והחדשות סגורות כמו הוותיקות ====================================
revoke execute on function app.viperflow_furniture_amount(jsonb, boolean)
  from anon, authenticated, public;
revoke execute on function app.viperflow_apply_income(uuid, uuid, text, numeric)
  from anon, authenticated, public;
revoke execute on function app.viperflow_items_fingerprint(uuid)
  from anon, authenticated, public;
revoke execute on function app.viperflow_status_label(text)
  from anon, authenticated, public;
revoke execute on function app.viperflow_changes(jsonb, jsonb)
  from anon, authenticated, public;
revoke execute on function app.viperflow_notify_change(uuid, uuid, text, text[])
  from anon, authenticated, public;
revoke execute on function app.viperflow_apply_task(uuid, text, date, time, int, boolean)
  from anon, authenticated, public;
