-- 0192: שורת ההובלה הולכת להובלות, ושורת הסידור מתפצלת לשתיים
--
-- ‏0187 גזר את מחיר ההקמה והפירוק משורת **"הובלה"**, ו-0190 הוסיף את פיצול
-- הריהוט. שתיהן היו הכרעות על `line_type`, ושתיהן היו שגויות בשני מובנים:
--
-- ‏1. **ההובלה אינה מחיר של משימה — היא סעיף הכנסה.** ‏"הובלה" הוא מה
--    שהלקוח משלם על הנסיעה, ואצלנו יש לזה קטגוריה משלה ("הובלות"). מה
--    שכן מתחלק בין ההקמה לפירוק הוא **"סידור ואיסוף"** — העבודה עצמה,
--    שחציה בהקמה וחציה בפירוק.
--
-- ‏2. **`line_type` אינו השם.** בקטלוג של שיא עיצובים יושבות תחת `truck`
--    גם "הובלה כיוון אחד (רק הקמה)" ו"תוספת", ותחת `worker` גם "פיקוח",
--    "מפקח הקמה ופירוק בלבד" ו"הקמה ופירוק אהילים". הסכימה הקודמת **סכמה
--    את כולן**: הזמנה עם שורת פיקוח קיבלה עובד אחד יותר מהאמת, והזמנה עם
--    "תוספת" קיבלה משאית מיותרת. הכמויות והמחירים נלקחים מעכשיו משורה
--    ששמה הוא אחד מהשמות שהוגדרו לחיבור, ותו לא.
--
-- ‏3. **המחיר לא היה המחיר.** ‏`line_total` כבר מגלם את הנחת השורה — נבדק
--    מול הנתונים שלהם, ‏`line_total = quantity × unit_price × (1 − הנחה)` —
--    אבל **הנחת ההזמנה** יושבת על ההזמנה כולה ולא נכנסה לשום מקום. היא
--    נבדקה על שש ההזמנות שיש בהן אחת: היא חלה על שורות הריהוט **בלבד**,
--    ולא על ההובלה ועל הסידור, ושיעורה בפועל זהה ל-`order_discount_percent`
--    עד ארבע ספרות אחרי הנקודה. מעכשיו ההכנסה נכתבת אחריה.
--
-- **השמות יושבים על החיבור ולא בקוד.** הקטלוג של ViperFlow אינו שלנו, ושם
-- מוצר משתנה שם בלי לשאול אותנו — ומחרוזת עברית קבועה בתוך פונקציה היא כסף
-- שמפסיק לזרום בשקט ביום שמישהו יערוך שורה. לכן זו הגדרה במסך, עם ברירות
-- המחדל שנכונות היום, ואפשר להוסיף לה שם בלי מיגרציה.

-- ===== 1. אילו שורות הן הובלה, ואילו הן הצוות =============================

alter table viperflow_connections
  add column trucking_line_names text[] not null default array['הובלה'],
  add column crew_line_names     text[] not null default array['סידור ואיסוף'];

comment on column viperflow_connections.trucking_line_names is
  'שמות שורות ההזמנה (line_type = truck) שנספרות ככמות משאיות ונכתבות '
  'לקטגוריית ההכנסה "הובלות". שם שאינו ברשימה מתעלמים ממנו (0192).';
comment on column viperflow_connections.crew_line_names is
  'שמות שורות ההזמנה (line_type = worker) שנספרות ככמות עובדים, וסכומן '
  'מתחלק בין ההקמה לפירוק. פיקוח והשגחה אינם ברשימה (0192).';

-- ===== 2. מקור מחיר המשימה: הצוות, או כלום ================================
--
-- ‏"הובלה" ו"הובלה + סידור" אינן אפשרויות עוד — 0192 הכריע מה כל שורה
-- עושה. מה שנשאר הוא מתג: לסנכרן מחיר משימה, או לא.
alter table viperflow_connections
  drop constraint if exists viperflow_connections_logistics_price_source_check;

update viperflow_connections
   set logistics_price_source = 'crew'
 where logistics_price_source in ('truck', 'logistics');

alter table viperflow_connections
  alter column logistics_price_source set default 'crew',
  add constraint viperflow_connections_logistics_price_source_check
    check (logistics_price_source in ('none', 'crew'));

comment on column viperflow_connections.logistics_price_source is
  'crew = מחיר ההקמה והפירוק נגזר משורות הצוות, מחצית לכל משימה; '
  'none = מחיר המשימה אינו מסונכרן כלל (0187, 0192).';

-- ===== 3. מה כל קטגוריית הכנסה מקבלת מ-ViperFlow ===========================
--
-- ‏0190 שאל "איזה מצב פריט", ועכשיו יש שאלה שלישית שאינה מצב פריט כלל:
-- ההובלה. העמודה מקבלת שם שמתאר את מה שהיא באמת אומרת.
alter table income_categories
  add column viperflow_income_source text
    check (viperflow_income_source in ('furniture_old', 'furniture_new', 'trucking'));

comment on column income_categories.viperflow_income_source is
  'מה הקטגוריה מקבלת מסנכרון ViperFlow: furniture_old / furniture_new לפי '
  'מצב הפריט בקטלוג, trucking = סכום שורות ההובלה. null = אינה מקבלת (0192).';

update income_categories
   set viperflow_income_source = case viperflow_item_state
                                   when 'old' then 'furniture_old'
                                   when 'new' then 'furniture_new'
                                 end
 where viperflow_item_state is not null;

update income_categories set viperflow_income_source = 'trucking'
 where name = 'הובלות' and deleted_at is null
   and viperflow_income_source is null;

drop index if exists income_categories_viperflow_state_uq;
alter table income_categories drop column viperflow_item_state;

create unique index income_categories_viperflow_source_uq
  on income_categories (viperflow_income_source)
  where viperflow_income_source is not null and deleted_at is null;

-- ===== 4. כמות וסכום, לפי סוג השורה **ושמה** ==============================
--
-- תאומות של 0177 §1 ו-0187 §2, בתוספת הכלל של 0192: השם חייב להיות ברשימה.
-- ‏`nullif(...,0)` נשמר מהן — "לא הוזמן" אינו "הוזמנו אפס", והשני היה מוחק
-- את מה שהרכז קבע.
create or replace function app.viperflow_named_quantity(
  p_items jsonb, p_type text, p_names text[])
returns numeric language sql stable set search_path = public as $$
  select nullif(sum(coalesce((i ->> 'quantity')::numeric, 0)), 0)
  from jsonb_array_elements(
         case when jsonb_typeof(p_items) = 'array' then p_items else '[]'::jsonb end) i
  where i ->> 'line_type' = p_type
    and coalesce((i ->> 'is_component')::boolean, false) = false
    and btrim(coalesce(i ->> 'name', '')) = any(coalesce(p_names, '{}'::text[]));
$$;

comment on function app.viperflow_named_quantity(jsonb, text, text[]) is
  'הכמות שהוזמנה בשורות מסוג מסוים ששמן ברשימה. null כשאין (0192).';

create or replace function app.viperflow_named_amount(
  p_items jsonb, p_type text, p_names text[])
returns numeric language sql stable set search_path = public as $$
  select nullif(sum(coalesce((i ->> 'line_total')::numeric, 0)), 0)
  from jsonb_array_elements(
         case when jsonb_typeof(p_items) = 'array' then p_items else '[]'::jsonb end) i
  where i ->> 'line_type' = p_type
    and coalesce((i ->> 'is_component')::boolean, false) = false
    and btrim(coalesce(i ->> 'name', '')) = any(coalesce(p_names, '{}'::text[]));
$$;

comment on function app.viperflow_named_amount(jsonb, text, text[]) is
  'סכום `line_total` של שורות מסוג מסוים ששמן ברשימה. null כשאין (0192).';

-- ===== 5. ההכנסה נכתבת לפי המקור, לא לפי מצב הפריט ========================
--
-- שם הפרמטר משתנה (`p_state` → `p_source`), ופוסטגרס אינו מרשה לשנות שם של
-- פרמטר ב-`create or replace`. ה-revoke שאובד עם ה-drop מוחזר ב-§9.
drop function if exists app.viperflow_apply_income(uuid, uuid, text, numeric);

create or replace function app.viperflow_apply_income(
  p_event    uuid,
  p_customer uuid,
  p_source   text,
  p_amount   numeric)
returns boolean language plpgsql security definer set search_path = public as $$
declare
  v_cat uuid;
  v_pct numeric;
  v_sys boolean := app.in_system_write();
begin
  if p_event is null or p_amount is null then return false; end if;

  select id into v_cat from income_categories
   where viperflow_income_source = p_source and is_active and deleted_at is null
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
  'כותב סכום מ-ViperFlow לקטגוריית ההכנסה שמסומנת לאותו מקור (0190, 0192).';

-- ===== 6. ההפרש: שמות חדשים לשני סעיפי הכסף ===============================
create or replace function app.viperflow_changes(p_before jsonb, p_after jsonb)
returns text[] language plpgsql stable set search_path = public as $$
declare
  v_out    text[] := '{}';
  v_keys   text[] := array['event_date', 'delivery', 'return', 'location', 'customer_name',
                           'notes', 'status', 'trucks', 'workers',
                           'crew_price', 'trucking', 'furniture_old', 'furniture_new'];
  v_labels text[] := array['תאריך האירוע', 'ההקמה', 'הפירוק', 'האולם', 'הלקוח הסופי',
                           'הערת ההזמנה', 'סטטוס ההזמנה', 'כמות משאיות', 'כמות עובדים',
                           'מחיר הקמה ופירוק', 'הובלות', 'ריהוט ישן', 'ריהוט חדש'];
  v_money  text[] := array['crew_price', 'trucking', 'furniture_old', 'furniture_new'];
  v_old_d  text;
  v_new_d  text;
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

  -- ההנחה אינה שקלים ואינה שדה רגיל, והיא משנה כל סכום ריהוט שמתחתיה.
  -- אפס נכתב לצילום כאפס ולא כ-null, ולכן צד ריק כאן פירושו צילום שנוצר
  -- לפני 0192 — ועליו לא מדווחים, כמו בכל שדה אחר.
  v_old_d := nullif(p_before ->> 'discount', '');
  v_new_d := nullif(p_after  ->> 'discount', '');
  if v_old_d is not null and v_new_d is not null and v_old_d <> v_new_d then
    v_out := v_out || ('הנחת ההזמנה: ' || to_char(v_new_d::numeric, 'FM990D99')
                       || '% (היה ' || to_char(v_old_d::numeric, 'FM990D99') || '%)');
  end if;

  for i in 1 .. array_length(v_keys, 1) loop
    v_old := nullif(p_before ->> v_keys[i], '');
    v_new := nullif(p_after  ->> v_keys[i], '');
    -- צד ריק הוא "לא ידוע", ולא ידוע אינו שינוי (0190 §4).
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
  'מה השתנה בין שני צילומי הזמנה, כשורות לאדם — ליומן ולהתראה (0190, 0192).';

-- ===== 7. המתרגם =========================================================
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

-- ===== 8. המסך: השמות נקראים ונכתבים ======================================
--
-- החתימה משתנה, ולכן הישנה נמחקת — אותו נימוק של 0187 §6: פרמטר שנוסף עם
-- ברירת מחדל יוצר שתי פונקציות שאפשר לקרוא לשתיהן באותם ארגומנטים.
drop function if exists viperflow_set_connection(uuid, text, boolean, text, uuid, text);

create or replace function viperflow_set_connection(
  p_customer_id     uuid,
  p_label           text,
  p_is_active       boolean default true,
  p_notes           text default null,
  p_connection_id   uuid default null,
  -- null = אל תיגע. המסך שולח ערך רק כשהוא באמת משנה אותו, וכך מתג "פעיל"
  -- אינו יכול לאפס בטעות את מקור המחיר או את רשימות השמות.
  p_logistics_price text default null,
  p_trucking_names  text[] default null,
  p_crew_names      text[] default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_id       uuid;
  v_trucking text[];
  v_crew     text[];
begin
  perform app.require('integrations.manage', 'אין לך הרשאה לנהל חיבורים');

  if not exists (select 1 from customers c where c.id = p_customer_id and c.deleted_at is null) then
    raise exception 'לקוח לא נמצא';
  end if;
  if coalesce(btrim(p_label), '') = '' then
    raise exception 'חובה לתת שם לחיבור';
  end if;
  if p_logistics_price is not null
     and p_logistics_price not in ('none', 'crew') then
    raise exception 'מקור מחיר לא חוקי';
  end if;

  -- ריק ורווחים יורדים, וכפילות אינה משנה דבר אך מבלבלת במסך.
  v_trucking := (select array_agg(distinct btrim(n))
                   from unnest(coalesce(p_trucking_names, '{}'::text[])) n
                  where btrim(n) <> '');
  v_crew     := (select array_agg(distinct btrim(n))
                   from unnest(coalesce(p_crew_names, '{}'::text[])) n
                  where btrim(n) <> '');

  -- רשימה שנשלחה וכולה ריקה היא טעות הקלדה, לא "בטל את כולן": רשימה ריקה
  -- משתיקה כמות ומחיר בלי שאיש ישים לב.
  if p_trucking_names is not null and coalesce(cardinality(v_trucking), 0) = 0 then
    raise exception 'חובה שם אחד לפחות לשורות ההובלה';
  end if;
  if p_crew_names is not null and coalesce(cardinality(v_crew), 0) = 0 then
    raise exception 'חובה שם אחד לפחות לשורות הצוות';
  end if;

  if p_connection_id is null then
    -- `api_base_url` אינה ברשימה: היא נשארת על ברירת המחדל שלה (0176 §4.1).
    insert into viperflow_connections (customer_id, label, is_active, notes,
                                       logistics_price_source,
                                       trucking_line_names, crew_line_names)
    values (p_customer_id, btrim(p_label), coalesce(p_is_active, true),
            nullif(btrim(p_notes), ''), coalesce(p_logistics_price, 'crew'),
            coalesce(v_trucking, array['הובלה']),
            coalesce(v_crew, array['סידור ואיסוף']))
    returning id into v_id;
  else
    update viperflow_connections set
      customer_id            = p_customer_id,
      label                  = btrim(p_label),
      is_active              = coalesce(p_is_active, is_active),
      notes                  = nullif(btrim(p_notes), ''),
      logistics_price_source = coalesce(p_logistics_price, logistics_price_source),
      trucking_line_names    = coalesce(v_trucking, trucking_line_names),
      crew_line_names        = coalesce(v_crew, crew_line_names)
    where id = p_connection_id and deleted_at is null
    returning id into v_id;
    if v_id is null then raise exception 'חיבור לא נמצא'; end if;
  end if;

  return v_id;
end $$;

revoke execute on function viperflow_set_connection(uuid, text, boolean, text, uuid, text, text[], text[])
  from anon, public;
grant  execute on function viperflow_set_connection(uuid, text, boolean, text, uuid, text, text[], text[])
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
      -- ‏0187: האם מחיר ההקמה והפירוק מסונכרן. ‏0192: מאילו שורות.
      'logistics_price_source', c.logistics_price_source,
      'trucking_line_names',    to_jsonb(c.trucking_line_names),
      'crew_line_names',        to_jsonb(c.crew_line_names),
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

-- ===== 9. מה שהוחלף יורד ==================================================
--
-- שתי העוזרות של 0177/0187 ספרו לפי `line_type` בלבד, וזה בדיוק מה ש-0192
-- הפסיק לעשות. השארה שלהן בסכימה היא הזמנה לקרוא לשגויה מביניהן.
drop function if exists app.viperflow_line_quantity(jsonb, text);
drop function if exists app.viperflow_line_amount(jsonb, text[]);

revoke execute on function app.viperflow_named_quantity(jsonb, text, text[])
  from anon, authenticated, public;
revoke execute on function app.viperflow_named_amount(jsonb, text, text[])
  from anon, authenticated, public;
revoke execute on function app.viperflow_apply_income(uuid, uuid, text, numeric)
  from anon, authenticated, public;
revoke execute on function app.viperflow_changes(jsonb, jsonb)
  from anon, authenticated, public;
