-- 0213: הפריטים החופשיים בשורה משלהם, כמו הכיסאות
--
-- הבקשה, במילים של הבעלים: "אני רוצה שגם פריטים חופשיים יהיו בנפרד כמו
-- שעשינו עם kiss-ot."
--
-- "פריט חופשי" ב-ViperFlow הוא שורת ריהוט שהוקלדה ביד בהזמנה, בלי מוצר
-- בקטלוג: ‏`line_type = 'product'`, ‏`is_custom = true`, ‏`product_id` ריק. עד
-- היום הוא נספר בריהוט ישן — כי מה שאינו מסומן "חדש" בקטלוג הוא ישן (0190) —
-- ולכן קיבל את האחוז של הישן. מעכשיו הוא בדיוק כמו הכיסאות של 0212:
--
--   1. **קטגוריית הכנסה רביעית לריהוט, ‏`furniture_custom`.** שורת פריט חופשי
--      יוצאת מהישן ונספרת לבד; סך הריהוט (ישן + חדש + כיסאות + חופשיים) שווה
--      למה שהיה לפני כן, ולכן שום מספר "ברוטו" אינו זז. ההנחה של ההזמנה חלה
--      עליה כמו על כל שורת ריהוט.
--
--   2. **הזיהוי הוא על השורה, לא בהגדרה של החיבור.** הכיסאות צריכים רשימת שמות
--      ועץ קטגוריות (0212 §2), כי הקטלוג של ViperFlow אינו שלנו. פריט חופשי
--      מסומן ב-`is_custom` על השורה עצמה, והמעטפה נושאת אותו כבר היום (פונקציית
--      הקצה מעבירה כל שדה שאינו כסף) — אין שינוי בפונקציות הקצה ואין רשימה
--      לערוך. מה שנדרש הוא רק שהקטגוריה מופעלת ללקוח.
--
--   3. **פריט חופשי אינו בקטלוג, ולכן אינו חדש ואינו כיסא.** פונקציית הקצה
--      מסמנת `is_new` ו-`category_names` לפי המוצר, ולשורה בלי מוצר אין אף אחד
--      מהם. הסכום של הפריטים החופשיים יוצא לכן מהישן בלבד — והפונקציה שסופרת
--      אותו מסננת בכל זאת חדש וכיסאות, כדי שההפרש יהיה מדויק בהגדרה ולא בהנחה.
--
--   4. **העמלה נקבעת ביד, בשקלים, וכולה של וייפר** — אותו כלל של הכיסאות
--      (‏`manual_commission`, ‏`app.income_viper_share`). הקטגוריה נדלקת ב-0%
--      אצל כל לקוח שהריהוט הישן או החדש דלוק אצלו: "אין עמלה עד שקבעת".
--      ⚠ לכן, מהסנכרון הבא של כל אירוע, הפריטים החופשיים שלו עוברים מהאחוז של
--      הישן ל-0% עד שתיקבע עליהם עמלה — ה"מגיע" של וייפר יורד בהתאם.
--
--   5. **"המפרט השתנה לאחר קביעת העמלה" — אותה התראה, אותו בסיס.** סנכרון
--      שמזיז את הסכום מבסיס העמלה מוציא `income_commission_stale` ושורה ביומן.
--      הכלל של שתי הקטגוריות כתוב עכשיו פעם אחת, ב-
--      ‏`app.viperflow_apply_manual_bucket` (§3), והמתרגם קורא לו פעמיים.
--
--   6. **עצירת סנכרון פותחת, חידוש דורס** — בלי שינוי: ‏0212 §5–6 כלליים לכל
--      קטגוריה שמקבלת סכום מ-ViperFlow, והפריטים החופשיים הם עוד אחת.
--
-- כמו בכיסאות: הפיצול קורה רק כשיש לו לאן לנחות (הקטגוריה מופעלת ללקוח
-- והמעטפה הועשרה מהקטלוג). אחרת הפריטים החופשיים נשארים בישן, ושורת פריטים
-- חופשיים שנשארה על האירוע יורדת עם העמלה שעליה — אחרת אותו כסף נספר פעמיים.

-- ===== 1. קטגוריית ההכנסה "פריטים חופשיים" ===============================

alter table income_categories
  drop constraint if exists income_categories_viperflow_income_source_check;
alter table income_categories
  add constraint income_categories_viperflow_income_source_check
  check (viperflow_income_source in ('furniture_old', 'furniture_new', 'furniture_chairs',
                                     'furniture_custom', 'trucking'));

comment on column income_categories.viperflow_income_source is
  'מה הקטגוריה מקבלת מסנכרון ViperFlow: furniture_old / furniture_new לפי '
  'מצב הפריט בקטלוג, furniture_chairs = מוצרי קטגוריית הכיסאות של החיבור, '
  'furniture_custom = פריטים חופשיים (שורה בלי מוצר בקטלוג), '
  'trucking = סכום שורות ההובלה. null = אינה מקבלת (0192, 0212, 0213).';

insert into income_categories (name, family, color, sort_order, viperflow_income_source, manual_commission)
select 'פריטים חופשיים', 'furniture', '#06b6d4', 27, 'furniture_custom', true
 where not exists (select 1 from income_categories
                    where viperflow_income_source = 'furniture_custom' and deleted_at is null);

-- דלוק ב-0% אצל כל מי שריהוט ישן או חדש דלוק אצלו (0212 §2, אותו נימוק).
insert into customer_income_splits (customer_id, category_id, viper_share_pct)
select distinct s.customer_id, fr.id, 0
  from customer_income_splits s
  join income_categories fu on fu.id = s.category_id
                           and fu.viperflow_income_source in ('furniture_old', 'furniture_new')
                           and fu.deleted_at is null
 cross join (select id from income_categories
              where viperflow_income_source = 'furniture_custom' and deleted_at is null) fr
on conflict (customer_id, category_id) do nothing;

-- ההתראה של 0212 אינה עוד "כיסאות" בלבד.
select app.register_notification_type('income_commission_stale',
  'המפרט השתנה לאחר קביעת העמלה',
  'סכום של קטגוריה שהעמלה עליה נקבעת ביד (כיסאות, פריטים חופשיים) השתנה בסנכרון '
  'מ-ViperFlow אחרי שהעמלה נקבעה — צריך לתמחר אותה מחדש',
  'אירועים', array['admin'], 'event', 'forced', 'opt_out', 'opt_in', 50);

-- ===== 2. מהו פריט חופשי, וכמה הוא שווה ===================================

create or replace function app.viperflow_is_custom(p_item jsonb)
returns boolean language sql immutable set search_path = public as $$
  select p_item ->> 'line_type' = 'product'
     and coalesce((p_item ->> 'is_component')::boolean, false) = false
     and coalesce((p_item ->> 'is_custom')::boolean, false)
     and nullif(btrim(coalesce(p_item ->> 'product_id', '')), '') is null
$$;

comment on function app.viperflow_is_custom(jsonb) is
  'שורת ההזמנה היא "פריט חופשי": ריהוט שהוקלד ביד, בלי מוצר בקטלוג (0213).';

-- ‏`p_chairs` — רשימת הכיסאות כשהפיצול שלהם פעיל, כמו ב-`viperflow_furniture_amount`.
-- פריט חופשי אינו חדש ואינו כיסא (§3 בראש הקובץ); הסינון כאן מבטיח שהסכום
-- הוא תת-קבוצה של "הישן" גם אם יום אחד המעטפה תאמר אחרת.
create or replace function app.viperflow_custom_amount(p_items jsonb, p_chairs text[])
returns numeric language sql stable set search_path = public as $$
  select coalesce(sum(coalesce((i ->> 'line_total')::numeric, 0)), 0)
  from jsonb_array_elements(
         case when jsonb_typeof(p_items) = 'array' then p_items else '[]'::jsonb end) i
  where app.viperflow_is_custom(i)
    and coalesce((i ->> 'is_new')::boolean, false) = false
    and not app.viperflow_is_chairs(i, p_chairs);
$$;

comment on function app.viperflow_custom_amount(jsonb, text[]) is
  'סכום `line_total` של הפריטים החופשיים בהזמנה — חלק מהריהוט הישן, בלי כיסאות (0213).';

revoke execute on function app.viperflow_is_custom(jsonb) from anon, authenticated, public;
revoke execute on function app.viperflow_custom_amount(jsonb, text[]) from anon, authenticated, public;

-- ===== 3. קטגוריה שהעמלה עליה ידנית: אותו כלל, פעם אחת =====================
--
-- זה גוף "הכיסאות" של 0212 §7, כפונקציה של מקור הכסף:
--
--   * יש פיצול (‏`p_split`): הסכום נכתב. סכום שזז בסנכרון הזה וגם שונה ממה
--     שהעמלה נקבעה עליו הוא "המפרט השתנה לאחר קביעת העמלה"; סכום שחזר אל
--     הבסיס אינו מתריע — העמלה שוב נכונה.
--   * אין פיצול: הכסף נספר הפעם בריהוט ישן/חדש, ושורה שנשארה על האירוע
--     (מסנכרון קודם, או מעריכה ידנית בזמן עצירה) היא אותו כסף פעם שנייה —
--     היא יורדת, ואיתה העמלה שנקבעה עליה.
--
-- מחזירה `part` — שורה ליומן, או null — ו-`alert` עם מה שההתראה צריכה. את
-- ההתראה עצמה שולח המתרגם, אחרי היומן (0190: "ההתראה יוצאת אחרי הכתיבה").

create or replace function app.viperflow_apply_manual_bucket(
  p_event    uuid,
  p_customer uuid,
  p_source   text,
  p_split    boolean,
  p_amount   numeric,
  p_created  boolean)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_cat    uuid;
  v_label  text;
  v_before numeric;
  v_comm   numeric;
  v_basis  numeric;
  v_gone   boolean;
  v_part   text;
  v_alert  boolean := false;
  v_sys    boolean := app.in_system_write();
begin
  if p_event is null then return jsonb_build_object('alert', false); end if;

  -- אותה קטגוריה ש-`viperflow_apply_income` כותב אליה.
  select id, name into v_cat, v_label from income_categories
   where viperflow_income_source = p_source and is_active and deleted_at is null
   order by sort_order, id limit 1;
  v_label := coalesce(v_label, case p_source when 'furniture_chairs' then 'כיסאות'
                                             when 'furniture_custom' then 'פריטים חופשיים'
                                             else p_source end);

  if coalesce(p_split, false) then
    select ei.amount, ei.commission_amount, ei.commission_basis
      into v_before, v_comm, v_basis
      from event_income ei
     where ei.event_id = p_event and ei.category_id = v_cat;

    if app.viperflow_apply_income(p_event, p_customer, p_source, p_amount) then
      if p_created and p_amount <> 0 then
        v_part := v_label || ' ' || to_char(p_amount, 'FM999G999G990D00') || ' ₪';
      end if;
      if v_comm is not null
         and v_before is distinct from p_amount
         and v_basis is distinct from p_amount then
        v_alert := true;
        v_part := v_label || ': המפרט השתנה לאחר קביעת העמלה — יש לתמחר אותה מחדש';
      end if;
    end if;
  else
    perform app.system_write(true);
    with gone as (
      delete from event_income ei
       using income_categories ic
       where ic.id = ei.category_id
         and ei.event_id = p_event
         and ic.viperflow_income_source = p_source
      returning ei.commission_amount, ic.name)
    select count(*) > 0, max(commission_amount), coalesce(max(name), v_label)
      into v_gone, v_comm, v_label
      from gone;
    if not v_sys then perform app.system_write(false); end if;

    if v_gone then
      v_part := v_label || ' נספרים שוב בריהוט ישן/חדש'
        || case when v_comm is not null then ' — העמלה הידנית עליהם בוטלה' else '' end;
    end if;
  end if;

  return jsonb_build_object(
    'part',       v_part,
    'alert',      v_alert,
    'label',      v_label,
    'basis',      v_basis,
    'amount',     p_amount,
    'commission', v_comm);
end $$;

comment on function app.viperflow_apply_manual_bucket(uuid, uuid, text, boolean, numeric, boolean) is
  'כותב (או מוריד) שורת הכנסה של קטגוריה שהעמלה עליה ידנית — כיסאות, פריטים חופשיים — '
  'ואומר אם הסכום זז מבסיס העמלה (0212, 0213).';

revoke execute on function app.viperflow_apply_manual_bucket(uuid, uuid, text, boolean, numeric, boolean)
  from anon, authenticated, public;

-- ===== 4. ההפרש: הפריטים החופשיים הם סעיף כסף ==============================
-- גוף 0212, ועוד מפתח אחד.

create or replace function app.viperflow_changes(p_before jsonb, p_after jsonb)
returns text[] language plpgsql stable set search_path = public as $$
declare
  v_out    text[] := '{}';
  v_keys   text[] := array['event_date', 'delivery', 'return', 'location', 'customer_name',
                           'notes', 'status', 'trucks', 'workers',
                           'crew_price', 'trucking', 'furniture_old', 'furniture_new',
                           'furniture_chairs', 'furniture_custom'];
  v_labels text[] := array['תאריך האירוע', 'ההקמה', 'הפירוק', 'האולם', 'הלקוח הסופי',
                           'הערת ההזמנה', 'סטטוס ההזמנה', 'כמות משאיות', 'כמות עובדים',
                           'מחיר הקמה ופירוק', 'הובלות', 'ריהוט ישן', 'ריהוט חדש',
                           'כיסאות', 'פריטים חופשיים'];
  v_money  text[] := array['crew_price', 'trucking', 'furniture_old', 'furniture_new',
                           'furniture_chairs', 'furniture_custom'];
  v_old_d  text;
  v_new_d  text;
  i        int;
  v_old    text;
  v_new    text;
begin
  if p_before is null or p_after is null then return '{}'; end if;

  -- ‏0213: צילום מלפני הפיצול (או מאחרי שכובה ללקוח) סופר את הפריטים
  -- החופשיים בתוך הישן. זה סיווג אחר של אותו כסף, לא שינוי בהזמנה: הצד
  -- שמפריד אותם מקופל חזרה לישן לצורך ההשוואה, ולכן המעבר עצמו אינו מוציא
  -- "ההזמנה השתנתה" על כל אירוע שיש בו פריט חופשי.
  if p_before ? 'furniture_custom' and not p_after ? 'furniture_custom' then
    p_before := (p_before - 'furniture_custom')
      || case when p_before ? 'furniture_old'
              then jsonb_build_object('furniture_old',
                     (p_before ->> 'furniture_old')::numeric + (p_before ->> 'furniture_custom')::numeric)
              else '{}'::jsonb end;
  elsif p_after ? 'furniture_custom' and not p_before ? 'furniture_custom' then
    p_after := (p_after - 'furniture_custom')
      || case when p_after ? 'furniture_old'
              then jsonb_build_object('furniture_old',
                     (p_after ->> 'furniture_old')::numeric + (p_after ->> 'furniture_custom')::numeric)
              else '{}'::jsonb end;
  end if;

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
  'מה השתנה בין שני צילומי הזמנה, כשורות לאדם — ליומן ולהתראה (0190, 0192, 0212, 0213).';

revoke execute on function app.viperflow_changes(jsonb, jsonb)
  from anon, authenticated, public;

-- ===== 5. המתרגם: הפריטים החופשיים בנפרד ===================================
-- גוף 0212, ועוד: הסכום של הפריטים החופשיים יוצא מהישן, והכיסאות והחופשיים
-- עוברים שניהם דרך §3. רשימת ההתראות על העמלה במקום דגל אחד.

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
    'trucks',        v_trucks,
    'workers',       v_workers,
    'crew_price',    v_crew,
    'trucking',      v_trucking,
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

-- ===== 6. הדשבורד: חלק הלקוח לכל קטגוריה ידנית בנפרד ======================
-- גוף 0212, ועוד `manual_rows` ב-`finance.client_share`: אותם שלושה מספרים
-- של הכיסאות (‏`chairs_*` — שם היסטורי, והם סך כל הקטגוריות הידניות), לכל
-- קטגוריה ידנית לבד. השאר — ‏`by_category`, ‏`manual_commission_total`, הרווח
-- והתמהיל — כבר כלליים לכל קטגוריה שמסומנת `manual_commission`.

create or replace function dashboard_sections(
  p_sections text[], p_from date, p_to date, p_opts jsonb default '{}'::jsonb)
returns jsonb language plpgsql stable security invoker set search_path = public as $$
declare
  v_key    text;
  v_out    jsonb := '{}'::jsonb;
  v_bucket text := case when p_opts ->> 'bucket' in ('day','week','month')
                        then p_opts ->> 'bucket' else 'week' end;
  v_limit  int  := greatest(1, least(coalesce((p_opts ->> 'limit')::int, 12), 50));
  v_val    jsonb;
  v_m      jsonb;
  v_pct    numeric;
  v_margin boolean := app.has_all(array['dashboard.margin','dashboard.payroll',
                                        'dashboard.contractor_cost','pricing.revenue']);
  v_scoped boolean := exists (select 1 from app.scope_rows('tasks') where scope_type <> 'all');
  v_com_pct numeric;
  v_com_min numeric;
  v_rev    numeric;
begin
  if p_from is null or p_to is null then
    raise exception 'חסר טווח תאריכים' using errcode = '22023';
  end if;
  if p_to < p_from then
    raise exception 'טווח תאריכים הפוך' using errcode = '22023';
  end if;
  if p_to - p_from > 400 then
    raise exception 'טווח גדול מדי לדשבורד' using errcode = '22023';
  end if;
  if coalesce(array_length(p_sections, 1), 0) > 60 then
    raise exception 'יותר מדי סקשנים בבקשה אחת' using errcode = '22023';
  end if;

  foreach v_key in array coalesce(p_sections, '{}'::text[]) loop
    v_val := null;

    if v_key = 'revenue.trend' and app.has('pricing.revenue') then
      select coalesce(jsonb_agg(row_to_json(x) order by x.bucket), '[]') into v_val from (
        select u.bucket, round(sum(u.total), 2) as total from (
          select date_trunc(v_bucket, t.task_date)::date as bucket, sum(tp.price) as total
            from app.task_revenue tp
            join app.live_tasks t on t.id = tp.task_id and t.deleted_at is null
           where t.task_date between p_from and p_to
           group by 1
          union all
          select date_trunc(v_bucket, e.event_date)::date, sum(ei.amount)
            from event_income ei
            join app.live_events e on e.id = ei.event_id and e.deleted_at is null
           where e.event_date between p_from and p_to
           group by 1) u
         group by u.bucket) x;

    elsif v_key = 'revenue.forecast' and app.has('pricing.revenue') then
      select jsonb_build_object(
        'total', round(coalesce(sum(tp.price), 0)
                       + coalesce((select sum(ei.amount)
                                     from event_income ei
                                     join app.live_events e on e.id = ei.event_id and e.deleted_at is null
                                    where e.event_date > current_date), 0), 2),
        'tasks', count(*),
        'by_month', (select coalesce(jsonb_agg(row_to_json(y) order by y.bucket), '[]') from (
            select u.bucket, round(sum(u.total), 2) as total from (
              select date_trunc('month', t2.task_date)::date as bucket, sum(tp2.price) as total
                from app.task_revenue tp2
                join app.live_tasks t2 on t2.id = tp2.task_id and t2.deleted_at is null
               where t2.task_date > current_date
                group by 1
              union all
              select date_trunc('month', e2.event_date)::date, sum(ei2.amount)
                from event_income ei2
                join app.live_events e2 on e2.id = ei2.event_id and e2.deleted_at is null
               where e2.event_date > current_date
                group by 1) u
             group by u.bucket) y))
        into v_val
        from app.task_revenue tp
        join app.live_tasks t on t.id = tp.task_id and t.deleted_at is null
       where t.task_date > current_date;

    elsif v_key = 'pricing.quality' and app.has('pricing.view') then
      select jsonb_build_object(
        'total',    count(*),
        'unpriced', count(*) filter (where tp.task_id is null or tp.price = 0),
        'manual',   count(*) filter (where tp.is_manual),
        'auto',     count(*) filter (where tp.task_id is not null and not tp.is_manual and tp.price > 0),
        'unpriced_list', (select coalesce(jsonb_agg(row_to_json(y)), '[]') from (
            select t2.id, t2.task_date, coalesce(c2.name, t2.title, tt2.name) as label
              from app.live_tasks t2
              left join task_pricing tp2 on tp2.task_id = t2.id
              left join customers c2 on c2.id = t2.customer_id
              left join task_types tt2 on tt2.id = t2.task_type_id
             where t2.deleted_at is null and t2.task_date between p_from and p_to
               and (tp2.task_id is null or tp2.price = 0)
             order by t2.task_date desc limit 8) y))
        into v_val
        from app.live_tasks t
        left join task_pricing tp on tp.task_id = t.id
       where t.deleted_at is null and t.task_date between p_from and p_to;

    elsif v_key = 'cost.contractor' and app.has('dashboard.contractor_cost') then
      select jsonb_build_object(
        'expected',   round(coalesce(sum(tct.price), 0), 2),
        'paid',       round(coalesce(sum(coalesce(tct.paid_amount, tct.price))
                              filter (where tct.paid_at is not null), 0), 2),
        'unpaid',     round(coalesce(sum(tct.price) filter (where tct.paid_at is null), 0), 2),
        'unpaid_rows', count(*) filter (where tct.paid_at is null),
        'zero_rows',   count(*) filter (where tct.price = 0),
        'rows',        count(*),
        'aging', jsonb_build_object(
          'd0_30',  round(coalesce(sum(tct.price) filter (
                      where tct.paid_at is null and t.task_date > current_date - 30), 0), 2),
          'd31_60', round(coalesce(sum(tct.price) filter (
                      where tct.paid_at is null and t.task_date between current_date - 60 and current_date - 30), 0), 2),
          'd60',    round(coalesce(sum(tct.price) filter (
                      where tct.paid_at is null and t.task_date < current_date - 60), 0), 2)))
        into v_val
        from task_contractor_terms tct
        join app.live_tasks t on t.id = tct.task_id and t.deleted_at is null
       where t.task_date between p_from and p_to;

    elsif v_key = 'cost.by_contractor' and app.has('dashboard.contractor_cost') and app.has('contractors.view') then
      select coalesce(jsonb_agg(row_to_json(x)), '[]') into v_val from (
        select ct.name,
               round(sum(tct.price), 2) as expected,
               round(sum(coalesce(tct.paid_amount, tct.price)) filter (where tct.paid_at is not null), 2) as paid
          from task_contractor_terms tct
          join app.live_tasks t on t.id = tct.task_id and t.deleted_at is null
          join contractors ct on ct.id = tct.contractor_id
         where t.task_date between p_from and p_to
         group by ct.name order by 2 desc limit v_limit) x;

    elsif v_key = 'cost.contractor_unpaid' and app.has('dashboard.contractor_cost')
          and app.has('contractors.view_pricing') then
      select coalesce(jsonb_agg(row_to_json(x)), '[]') into v_val from (
        select t.id as task_id, t.task_date, ct.name as contractor, tct.price
          from task_contractor_terms tct
          join app.live_tasks t on t.id = tct.task_id and t.deleted_at is null
          join contractors ct on ct.id = tct.contractor_id
         where tct.paid_at is null and tct.price > 0 and t.task_date between p_from and p_to
         order by t.task_date limit v_limit) x;

    elsif v_key = 'cost.payroll' and app.has('dashboard.payroll') then
      v_val := app.payroll_summary(p_from, p_to);

    elsif v_key = 'cost.payroll_by_worker' and app.has('dashboard.payroll')
          and app.has('dashboard.all_workers') then
      v_val := app.payroll_by_worker(p_from, p_to, v_limit);

    elsif v_key = 'cost.payroll_trend' and app.has('dashboard.payroll') then
      v_val := app.payroll_trend(p_from, p_to, v_bucket);

    -- ── עלות מעביד: שכר מאושר כפול האחוז הגלובלי ─────────────────────────
    elsif v_key = 'cost.payroll_employer' and app.has('dashboard.payroll') then
      v_m := app.payroll_summary(p_from, p_to);
      v_pct := coalesce((select (value ->> 'pct')::numeric
                           from app_settings where key = 'finance.employer_cost'), 0);
      v_val := jsonb_build_object(
        'base',  v_m -> 'total',
        'pct',   v_pct,
        'total', round(coalesce((v_m ->> 'total')::numeric, 0) * (1 + v_pct / 100), 2),
        'unrated_shifts', v_m -> 'unrated_shifts');

    -- ── רווח גולמי: מימוש אחד, שני קוראים ─────────────────────────────────
    elsif v_key = 'margin.summary' and v_margin and not v_scoped then
      v_val := app.margin_summary(p_from, p_to);

    elsif v_key = 'margin.trend' and v_margin and not v_scoped then
      v_val := app.margin_trend(p_from, p_to, v_bucket);

    elsif v_key = 'margin.by_customer' and v_margin and not v_scoped and app.has('customers.view') then
      v_val := app.margin_by_customer(p_from, p_to, v_limit);

    -- ── סיכום רווח: סך הכנסות מהאירועים לפי הפילוח פחות הוצאות (שכר×מעביד + קבלנים) ─────
    elsif v_key = 'finance.profit_summary' and v_margin and not v_scoped then
      v_m := app.margin_summary(p_from, p_to);
      v_pct := coalesce((select (value ->> 'pct')::numeric
                           from app_settings where key = 'finance.employer_cost'), 0);

      -- סך הכנסות לפי פילוח הכנסות
      with 
      trans_sia as (
        select coalesce(sum(ei.amount), 0) as total
          from event_income ei
          join app.live_events e on e.id = ei.event_id and e.deleted_at is null
               and e.event_date between p_from and p_to
          join customers c on c.id = e.customer_id
          join income_categories ic on ic.id = ei.category_id
         where c.name = 'שיא עיצובים' and ic.name = 'הובלות'
      ),
      event_tasks as (
        select e.id as event_id, e.customer_id, c.name as customer_name,
               coalesce(c.commission_pct, 0) as commission_pct,
               coalesce(c.commission_min_event, 0) as commission_min_event,
               coalesce(sum(tp.price), 0) as task_sum
          from app.live_events e
          join customers c on c.id = e.customer_id
          left join app.live_tasks t on t.event_id = e.id and t.deleted_at is null
          left join app.task_revenue tp on tp.task_id = t.id
         where e.deleted_at is null
           and e.event_date between p_from and p_to
         group by e.id, e.customer_id, c.name, c.commission_pct, c.commission_min_event
        union all
        select null as event_id, t.customer_id, c.name as customer_name,
               0 as commission_pct, 0 as commission_min_event,
               sum(tp.price) as task_sum
          from app.live_tasks t
          join app.task_revenue tp on tp.task_id = t.id
          join customers c on c.id = t.customer_id
         where t.event_id is null and t.deleted_at is null
           and t.task_date between p_from and p_to
         group by t.customer_id, c.name
      ),
      cust_logistics as (
        select coalesce(sum(
                 case 
                   when (et.commission_pct > 0 or et.customer_name = 'קיסר') and et.task_sum > coalesce(et.commission_min_event, 2000) then
                     et.task_sum - round(et.task_sum * (case when et.commission_pct > 0 then et.commission_pct else 10 end) / 100, 2)
                   else
                     et.task_sum
                 end
               ), 0) as total
          from event_tasks et
      ),
      furn_new as (
        select coalesce(sum(ei.amount * 0.20), 0) as total
          from event_income ei
          join app.live_events e on e.id = ei.event_id and e.deleted_at is null
               and e.event_date between p_from and p_to
          join income_categories ic on ic.id = ei.category_id
         where ic.name = 'ריהוט חדש'
      ),
      furn_old as (
        select coalesce(sum(ei.amount * 0.70), 0) as total
          from event_income ei
          join app.live_events e on e.id = ei.event_id and e.deleted_at is null
               and e.event_date between p_from and p_to
          join income_categories ic on ic.id = ei.category_id
         where ic.name = 'ריהוט ישן'
      ),
      -- ‏0212: הכיסאות — העמלה שנקבעה ביד, כולה של וייפר (ועד שנקבעה, האחוז)
      furn_manual as (
        select coalesce(sum(app.income_viper_share(ei.amount, ei.viper_share_pct, ei.commission_amount)), 0) as total
          from event_income ei
          join app.live_events e on e.id = ei.event_id and e.deleted_at is null
               and e.event_date between p_from and p_to
          join income_categories ic on ic.id = ei.category_id
         where ic.manual_commission
      )
      select round((select total from trans_sia) + (select total from cust_logistics) + (select total from furn_new) + (select total from furn_old) + (select total from furn_manual), 2)
        into v_rev;

      v_val := jsonb_build_object(
        'revenue',      v_rev,
        'payroll',      v_m -> 'payroll',
        'employer_pct', v_pct,
        'payroll_with_employer',
          round(coalesce((v_m ->> 'payroll')::numeric, 0) * (1 + v_pct / 100), 2),
        'contractor',   v_m -> 'contractor',
        'profit',
          round(coalesce(v_rev, 0)
                - coalesce((v_m ->> 'payroll')::numeric, 0) * (1 + v_pct / 100)
                - coalesce((v_m ->> 'contractor')::numeric, 0), 2),
        'pct', case when coalesce(v_rev, 0) > 0
                    then round((coalesce(v_rev, 0)
                                - coalesce((v_m ->> 'payroll')::numeric, 0) * (1 + v_pct / 100)
                                - coalesce((v_m ->> 'contractor')::numeric, 0))
                               / v_rev * 100, 1) end,
        'unrated_shifts', v_m -> 'unrated_shifts',
        'excludes_overhead', true);

    -- ── הכנסות לפי קטגוריה ────────────────────────────────────────────────
    elsif v_key = 'income.by_category' and app.has('finance.income_view') then
      with cat as (
        select ic.id, ic.name, ic.family, ic.color, ic.sort_order, ic.manual_commission,
               round(coalesce(sum(ei.amount) filter (where e.id is not null), 0), 2) as total,
               -- ‏0212: החלק של וייפר — העמלה שנקבעה ביד, ועד שנקבעה האחוז
               round(coalesce(sum(app.income_viper_share(ei.amount, ei.viper_share_pct, ei.commission_amount))
                                filter (where e.id is not null), 0), 2) as viper_share
          from income_categories ic
          left join event_income ei on ei.category_id = ic.id
          left join app.live_events e on e.id = ei.event_id and e.deleted_at is null
               and e.event_date between p_from and p_to
         group by ic.id, ic.name, ic.family, ic.color, ic.sort_order, ic.manual_commission
        having (ic.deleted_at is null and ic.is_active)
            or coalesce(sum(ei.amount) filter (where e.id is not null), 0) <> 0)
      select jsonb_build_object(
        'rows', coalesce((select jsonb_agg(row_to_json(c) order by c.sort_order) from cat c), '[]'::jsonb),
        'furniture_total', round(coalesce((select sum(total) from cat where family = 'furniture'), 0), 2),
        'logistics_total', round(coalesce((select sum(total) from cat where family = 'logistics'), 0), 2),
        'total', round(coalesce((select sum(total) from cat), 0), 2),
        'manual_commission_total',
          round(coalesce((select sum(viper_share) from cat where manual_commission), 0), 2))
        into v_val;

    -- ── פילוח הכנסות: הובלות שיא עיצובים, לוגיסטיקה לפי לקוח, ריהוט חדש (20%), ריהוט ישן (70%) ──
    elsif v_key = 'income.mix' and app.has('finance.income_view') and app.has('customers.view') then
      with 
      -- 1. הובלות של שיא עיצובים (100% להכנסות)
      trans_sia as (
        select 'הובלות שיא עיצובים' as label, ic.color as color, round(sum(ei.amount), 2) as total
          from event_income ei
          join app.live_events e on e.id = ei.event_id and e.deleted_at is null
               and e.event_date between p_from and p_to
          join customers c on c.id = e.customer_id
          join income_categories ic on ic.id = ei.category_id
         where c.name = 'שיא עיצובים' and ic.name = 'הובלות'
         group by ic.color
      ),
      -- 2. הכנסה לוגיסטיקה לפי לקוח (סך משימות האירועים; עבור קיסר פחות 10% מעל 2000 ש"ח לאירוע)
      event_tasks as (
        select e.id as event_id, e.customer_id, c.name as customer_name, c.color as customer_color,
               coalesce(c.commission_pct, 0) as commission_pct,
               coalesce(c.commission_min_event, 0) as commission_min_event,
               coalesce(sum(tp.price), 0) as task_sum
          from app.live_events e
          join customers c on c.id = e.customer_id
          left join app.live_tasks t on t.event_id = e.id and t.deleted_at is null
          left join app.task_revenue tp on tp.task_id = t.id
         where e.deleted_at is null
           and e.event_date between p_from and p_to
         group by e.id, e.customer_id, c.name, c.color, c.commission_pct, c.commission_min_event
        union all
        select null as event_id, t.customer_id, c.name as customer_name, c.color as customer_color,
               0 as commission_pct, 0 as commission_min_event,
               sum(tp.price) as task_sum
          from app.live_tasks t
          join app.task_revenue tp on tp.task_id = t.id
          join customers c on c.id = t.customer_id
         where t.event_id is null and t.deleted_at is null
           and t.task_date between p_from and p_to
         group by t.customer_id, c.name, c.color
      ),
      cust_logistics as (
        select 'לוגיסטיקה ' || et.customer_name as label,
               et.customer_color as color,
               round(sum(
                 case 
                   when (et.commission_pct > 0 or et.customer_name = 'קיסר') and et.task_sum > coalesce(et.commission_min_event, 2000) then
                     et.task_sum - round(et.task_sum * (case when et.commission_pct > 0 then et.commission_pct else 10 end) / 100, 2)
                   else
                     et.task_sum
                 end
               ), 2) as total
          from event_tasks et
         group by et.customer_name, et.customer_color
        having sum(et.task_sum) > 0
      ),
      -- 3. ריהוט חדש (20% להכנסות)
      furn_new as (
        select 'ריהוט חדש' as label, ic.color as color, round(sum(ei.amount * 0.20), 2) as total
          from event_income ei
          join app.live_events e on e.id = ei.event_id and e.deleted_at is null
               and e.event_date between p_from and p_to
          join income_categories ic on ic.id = ei.category_id
         where ic.name = 'ריהוט חדש'
         group by ic.color
      ),
      -- 4. ריהוט ישן (70% להכנסות)
      furn_old as (
        select 'ריהוט ישן' as label, ic.color as color, round(sum(ei.amount * 0.70), 2) as total
          from event_income ei
          join app.live_events e on e.id = ei.event_id and e.deleted_at is null
               and e.event_date between p_from and p_to
          join income_categories ic on ic.id = ei.category_id
         where ic.name = 'ריהוט ישן'
         group by ic.color
      ),
      -- 5. ‏0212: עמלה שנקבעה ביד (כיסאות) — 100% להכנסות (ועד שנקבעה, האחוז)
      furn_manual as (
        select 'עמלת ' || ic.name as label, ic.color as color,
               round(sum(app.income_viper_share(ei.amount, ei.viper_share_pct, ei.commission_amount)), 2) as total
          from event_income ei
          join app.live_events e on e.id = ei.event_id and e.deleted_at is null
               and e.event_date between p_from and p_to
          join income_categories ic on ic.id = ei.category_id
         where ic.manual_commission
         group by ic.name, ic.color
      ),
      all_mix as (
        select label, color, total from trans_sia
        union all
        select label, color, total from cust_logistics
        union all
        select label, color, total from furn_new
        union all
        select label, color, total from furn_old
        union all
        select label, color, total from furn_manual
      )
      select coalesce(jsonb_agg(row_to_json(x)), '[]') into v_val from (
        select label, color, total
          from all_mix
         where total > 0
         order by total desc limit v_limit
      ) x;

    -- ── תשלום לוויפר: מה שהלקוחות חייבים, מה ששולם, והיתרה ───────────────
    elsif v_key = 'finance.receivables' and app.has('finance.receipts_view')
          and app.has('finance.income_view') then
      with rev as (
        select u.cid, sum(u.amount) as owed from (
          select e.customer_id as cid, ei.amount
            from event_income ei
            join app.live_events e on e.id = ei.event_id and e.deleted_at is null
           where e.event_date between p_from and p_to
          union all
          select t.customer_id, tp.price
            from app.task_revenue tp
            join app.live_tasks t on t.id = tp.task_id and t.deleted_at is null
           where t.task_date between p_from and p_to) u
         group by u.cid),
      rec as (
        select r.customer_id as cid, sum(r.amount) as paid, count(*) as cnt
          from receipts r
         where r.deleted_at is null and r.received_at between p_from and p_to
         group by r.customer_id)
      select jsonb_build_object(
        'owed',   round(coalesce((select sum(owed) from rev), 0), 2),
        'paid',   round(coalesce((select sum(paid) from rec), 0), 2),
        'unpaid', round(coalesce((select sum(owed) from rev), 0)
                        - coalesce((select sum(paid) from rec), 0), 2),
        'receipts_count', coalesce((select sum(cnt) from rec), 0),
        'by_customer', case when app.has('customers.view') then
          (select coalesce(jsonb_agg(row_to_json(y)), '[]') from (
             select c.name, c.color,
                    round(coalesce(v.owed, 0), 2) as owed,
                    round(coalesce(p.paid, 0), 2) as paid,
                    round(coalesce(v.owed, 0) - coalesce(p.paid, 0), 2) as unpaid
               from customers c
               left join rev v on v.cid = c.id
               left join rec p on p.cid = c.id
              where c.deleted_at is null and (v.cid is not null or p.cid is not null)
              order by 3 desc limit v_limit) y)
          else null end)
        into v_val;

    -- ── הכנסות לשיא עיצובים: 80% מריהוט חדש ו-30% מריהוט ישן עם פילוח ────
    elsif v_key = 'finance.client_share' and app.has('finance.income_view') then
      select jsonb_build_object(
        'total', round(coalesce(sum(case 
                    when ic.name = 'ריהוט חדש' then ei.amount * 0.80
                    when ic.name = 'ריהוט ישן' then ei.amount * 0.30
                    else ei.amount - app.income_viper_share(ei.amount, ei.viper_share_pct, ei.commission_amount)
                  end), 0), 2),
        'furniture_new_share', round(coalesce(sum(case when ic.name = 'ריהוט חדש' then ei.amount * 0.80 else 0 end), 0), 2),
        'furniture_old_share', round(coalesce(sum(case when ic.name = 'ריהוט ישן' then ei.amount * 0.30 else 0 end), 0), 2),
        'furniture_new_raw', round(coalesce(sum(case when ic.name = 'ריהוט חדש' then ei.amount else 0 end), 0), 2),
        'furniture_old_raw', round(coalesce(sum(case when ic.name = 'ריהוט ישן' then ei.amount else 0 end), 0), 2),
        -- ‏0212: הכיסאות — הסכום, העמלה שנקבעה ביד, ומה שנשאר ללקוח
        'chairs_raw', round(coalesce(sum(case when ic.manual_commission then ei.amount else 0 end), 0), 2),
        'chairs_commission', round(coalesce(sum(case when ic.manual_commission
                                                      then app.income_viper_share(ei.amount, ei.viper_share_pct, ei.commission_amount)
                                                      else 0 end), 0), 2),
        'chairs_share', round(coalesce(sum(case when ic.manual_commission
                                                 then ei.amount - app.income_viper_share(ei.amount, ei.viper_share_pct, ei.commission_amount)
                                                 else 0 end), 0), 2),
        -- ‏0213: אותו פירוט לכל קטגוריה ידנית בנפרד — כיסאות, פריטים חופשיים
        'manual_rows', (select coalesce(jsonb_agg(jsonb_build_object(
                           'name', m.name, 'raw', m.raw, 'commission', m.commission,
                           'share', m.raw - m.commission) order by m.sort_order), '[]'::jsonb)
                          from (select ic3.name, ic3.sort_order,
                                       round(sum(ei3.amount), 2) as raw,
                                       round(sum(app.income_viper_share(ei3.amount, ei3.viper_share_pct,
                                                                        ei3.commission_amount)), 2) as commission
                                  from event_income ei3
                                  join app.live_events e3 on e3.id = ei3.event_id and e3.deleted_at is null
                                       and e3.event_date between p_from and p_to
                                  join customers c3 on c3.id = e3.customer_id
                                  join income_categories ic3 on ic3.id = ei3.category_id
                                 where c3.name = 'שיא עיצובים' and ic3.manual_commission
                                 group by ic3.name, ic3.sort_order) m),
        'rows', case when app.has('customers.view') then
          (select coalesce(jsonb_agg(row_to_json(y)), '[]') from (
             select c.name, c.color,
                    round(sum(case 
                      when c.name = 'שיא עיצובים' and ic2.name = 'ריהוט חדש' then ei2.amount * 0.80
                      when c.name = 'שיא עיצובים' and ic2.name = 'ריהוט ישן' then ei2.amount * 0.30
                      else ei2.amount - app.income_viper_share(ei2.amount, ei2.viper_share_pct, ei2.commission_amount)
                    end), 2) as total
               from event_income ei2
               join app.live_events e2 on e2.id = ei2.event_id and e2.deleted_at is null
                    and e2.event_date between p_from and p_to
               join customers c on c.id = e2.customer_id
               join income_categories ic2 on ic2.id = ei2.category_id
              group by c.name, c.color
             having sum(case 
                      when c.name = 'שיא עיצובים' and ic2.name = 'ריהוט חדש' then ei2.amount * 0.80
                      when c.name = 'שיא עיצובים' and ic2.name = 'ריהוט ישן' then ei2.amount * 0.30
                      else ei2.amount - app.income_viper_share(ei2.amount, ei2.viper_share_pct, ei2.commission_amount)
                    end) <> 0
              order by 3 desc limit v_limit) y)
          else null end)
        into v_val
        from event_income ei
        join app.live_events e on e.id = ei.event_id and e.deleted_at is null
             and e.event_date between p_from and p_to
        join customers c on c.id = e.customer_id
        join income_categories ic on ic.id = ei.category_id
       where c.name = 'שיא עיצובים';

    -- ── עמלה לקיסר: 10% מאירועים של קיסר שסך כל המשימות של האירוע מעל 2000 ש"ח ──
    elsif v_key = 'finance.keisar_commission' and app.has('finance.income_view') then
      with ev as (
        select e.id,
               coalesce(sum(tp.price), 0) as task_sum
          from app.live_events e
          join customers c on c.id = e.customer_id
          left join app.live_tasks t on t.event_id = e.id and t.deleted_at is null
          left join app.task_revenue tp on tp.task_id = t.id
         where c.name = 'קיסר' and e.deleted_at is null
           and e.event_date between p_from and p_to
         group by e.id
      ),
      qualifying as (
        select ev.task_sum, round(ev.task_sum * 0.10, 2) as commission
          from ev
         where ev.task_sum > 2000
      )
      select jsonb_build_object(
        'total', round(coalesce(sum(commission), 0), 2),
        'events_count', count(*),
        'tasks_total', round(coalesce(sum(task_sum), 0), 2)
      ) into v_val from qualifying;

    elsif v_key = 'tasks.by_type' then
      select coalesce(jsonb_agg(row_to_json(x)), '[]') into v_val from (
        select tt.name, count(*) as cnt
          from app.live_tasks t join task_types tt on tt.id = t.task_type_id
         where t.deleted_at is null and t.task_date between p_from and p_to
         group by tt.name order by 2 desc limit v_limit) x;

    elsif v_key = 'tasks.by_method' then
      select coalesce(jsonb_agg(row_to_json(x)), '[]') into v_val from (
        select em.name, count(*) as cnt
          from app.live_tasks t join execution_methods em on em.id = t.execution_method_id
         where t.deleted_at is null and t.task_date between p_from and p_to
         group by em.name order by 2 desc limit v_limit) x;

    elsif v_key = 'tasks.trend' then
      select coalesce(jsonb_agg(row_to_json(x) order by x.bucket), '[]') into v_val from (
        select bucket, sum(tasks) as tasks, sum(events) as events from (
          select date_trunc(v_bucket, t.task_date)::date as bucket, count(*) as tasks, 0 as events
            from app.live_tasks t where t.deleted_at is null and t.task_date between p_from and p_to
           group by 1
          union all
          select date_trunc(v_bucket, e.event_date)::date, 0, count(*)
            from app.live_events e where e.deleted_at is null and e.event_date between p_from and p_to
           group by 1) u
         group by bucket) x;

    elsif v_key = 'tasks.understaffed'
          and (app.has('dashboard.all_workers') or app.has('tasks.assign.worker')) then
      select jsonb_build_object(
        'count', count(*),
        'rows', (select coalesce(jsonb_agg(row_to_json(y)), '[]') from (
            select t2.id, t2.task_date, coalesce(c2.name, t2.title) as label,
                   t2.worker_count as needed,
                   ((select count(*) from task_assignments a2
                      where a2.task_id = t2.id and a2.role = 'worker')
                    + (select count(*) from task_contractor_workers cw2
                        where cw2.task_id = t2.id)) as assigned
              from app.live_tasks t2
              left join customers c2 on c2.id = t2.customer_id
              join statuses s2 on s2.id = t2.status_id
             where t2.deleted_at is null and t2.task_date between p_from and p_to
               and not s2.is_terminal and t2.worker_count > 0
               and ((select count(*) from task_assignments a3
                      where a3.task_id = t2.id and a3.role = 'worker')
                    + (select count(*) from task_contractor_workers cw3
                        where cw3.task_id = t2.id)) < t2.worker_count
             order by t2.task_date limit 8) y))
        into v_val
        from app.live_tasks t
        join statuses s on s.id = t.status_id
       where t.deleted_at is null and t.task_date between p_from and p_to
         and not s.is_terminal and t.worker_count > 0
         and ((select count(*) from task_assignments a
                where a.task_id = t.id and a.role = 'worker')
              + (select count(*) from task_contractor_workers cw
                  where cw.task_id = t.id)) < t.worker_count;

    elsif v_key = 'tasks.no_truck' then
      select jsonb_build_object('count', count(*)) into v_val
        from app.live_tasks t join statuses s on s.id = t.status_id
       where t.deleted_at is null and t.task_date between p_from and p_to
         and not s.is_terminal
         and coalesce(cardinality(t.truck_ids), 0) = 0 and t.truck_free_text is null;

    elsif v_key = 'fleet.utilization' then
      select coalesce(jsonb_agg(row_to_json(x)), '[]') into v_val from (
        select tr.name,
               count(distinct t.task_date) as days,
               count(*) as tasks
          from app.live_tasks t
          cross join lateral unnest(t.truck_ids) as u(truck_id)
          join trucks tr on tr.id = u.truck_id
         where t.deleted_at is null and t.task_date between p_from and p_to
         group by tr.name order by 2 desc limit v_limit) x;

    elsif v_key = 'events.by_customer' and app.has('customers.view') then
      select coalesce(jsonb_agg(row_to_json(x)), '[]') into v_val from (
        select c.name, c.color, count(*) as cnt
          from app.live_events e join customers c on c.id = e.customer_id
         where e.deleted_at is null and e.event_date between p_from and p_to
         group by c.name, c.color order by 3 desc limit v_limit) x;

    elsif v_key = 'events.funnel' then
      select coalesce(jsonb_agg(row_to_json(x)), '[]') into v_val from (
        select s.name, s.color, count(*) as cnt
          from events e join statuses s on s.id = e.status_id
         where e.deleted_at is null and e.event_date between p_from and p_to
         group by s.name, s.color, s.sort_order order by s.sort_order) x;

    elsif v_key = 'events.volume' and app.has('customers.view') then
      select jsonb_build_object(
        'volume_m', round(coalesce(sum(e.volume_m), 0), 2),
        'trucks',   coalesce(sum(e.truck_count), 0),
        'events',   count(*),
        'by_customer', (select coalesce(jsonb_agg(row_to_json(y)), '[]') from (
            select c2.name, c2.color,
                   round(coalesce(sum(e2.volume_m), 0), 2) as volume_m,
                   coalesce(sum(e2.truck_count), 0) as trucks
              from app.live_events e2 join customers c2 on c2.id = e2.customer_id
             where e2.deleted_at is null and e2.event_date between p_from and p_to
             group by c2.name, c2.color order by 3 desc limit v_limit) y))
        into v_val
        from app.live_events e
        where e.deleted_at is null and e.event_date between p_from and p_to;

    elsif v_key = 'customers.leaderboard' and app.has('customers.view') then
      select coalesce(jsonb_agg(row_to_json(x) order by x.events desc), '[]') into v_val from (
        select c.name, c.color,
               count(distinct e.id) as events,
               count(distinct t.id) as tasks,
               case when app.has('pricing.revenue')
                    then round(coalesce(sum(distinct_price.price), 0)
                               + coalesce((select sum(ei.amount)
                                             from event_income ei
                                             join app.live_events e3 on e3.id = ei.event_id
                                              and e3.deleted_at is null
                                              and e3.event_date between p_from and p_to
                                            where e3.customer_id = c.id), 0), 2) end as revenue,
               max(e.event_date) as last_event
          from customers c
          left join app.live_events e on e.customer_id = c.id and e.deleted_at is null
               and e.event_date between p_from and p_to
          left join app.live_tasks t on t.customer_id = c.id and t.deleted_at is null
               and t.task_date between p_from and p_to
          left join lateral (
            select tp.price from app.task_revenue tp where tp.task_id = t.id) distinct_price on true
         where c.deleted_at is null
         group by c.id, c.name, c.color
        having count(distinct e.id) > 0 or count(distinct t.id) > 0
         limit v_limit) x;

    elsif v_key = 'customers.inactive' and app.has('customers.view') then
      select coalesce(jsonb_agg(row_to_json(x)), '[]') into v_val from (
        select c.name, c.color,
               (select max(e2.event_date) from app.live_events e2
                 where e2.customer_id = c.id and e2.deleted_at is null) as last_event
          from customers c
         where c.deleted_at is null and c.is_active
           and not exists (select 1 from app.live_events e where e.customer_id = c.id
                             and e.deleted_at is null and e.event_date between p_from and p_to)
         order by 3 desc nulls last limit v_limit) x;

    elsif v_key = 'attendance.hours' and app.has('attendance.view_all') then
      select jsonb_build_object(
        'actual_hours', round(coalesce(sum(e.actual_hours), 0), 2),
        'shifts',       count(*),
        'workers',      count(distinct e.profile_id))
        into v_val
        from attendance_entries e
       where e.deleted_at is null and e.status = 'approved'
         and e.work_date between p_from and p_to;

    elsif v_key = 'attendance.hours_by_worker' and app.has('attendance.view_all') then
      select coalesce(jsonb_agg(row_to_json(x)), '[]') into v_val from (
        select p.full_name as name, round(sum(e.actual_hours), 2) as hours
          from attendance_entries e join profiles p on p.id = e.profile_id
         where e.deleted_at is null and e.status = 'approved'
           and e.work_date between p_from and p_to
         group by p.full_name order by 2 desc nulls last limit v_limit) x;

    elsif v_key = 'attendance.pending' and app.has('attendance.approve_entry') then
      select jsonb_build_object(
        'count', count(*),
        'hours', round(coalesce(sum(e.actual_hours), 0), 2),
        'rows', (select coalesce(jsonb_agg(row_to_json(y)), '[]') from (
            select e2.id, e2.work_date, p2.full_name, e2.actual_hours
              from attendance_entries e2 join profiles p2 on p2.id = e2.profile_id
             where e2.deleted_at is null and e2.status = 'pending'
             order by e2.work_date limit 8) y))
        into v_val
        from attendance_entries e
       where e.deleted_at is null and e.status = 'pending';

    elsif v_key = 'attendance.flags' and app.has('attendance.view_all') then
      select coalesce(jsonb_agg(row_to_json(x)), '[]') into v_val from (
        select f as flag, count(*) as cnt
          from attendance_entries e, unnest(e.flags) as f
         where e.deleted_at is null and e.work_date between p_from and p_to
         group by f order by 2 desc) x;

    elsif v_key = 'attendance.active_and_recent' and (app.has('attendance.view_all') or exists (select 1 from profiles where user_id = auth.uid() and is_admin)) then
      select jsonb_build_object(
        'active_count', count(*) filter (where e.clock_out_at is null),
        'total_count', count(*),
        'shifts', coalesce(jsonb_agg(jsonb_build_object(
          'id', e.id,
          'profile_id', e.profile_id,
          'worker_name', p.full_name,
          'phone', p.phone,
          'work_site', e.work_site,
          'task_or_event', (
            select coalesce(ev.end_client_name, t.title, ev.location_text)
            from tasks t left join events ev on ev.id = t.event_id
            where t.id = e.task_ids[1] limit 1
          ),
          'clock_in_at', e.clock_in_at,
          'clock_out_at', e.clock_out_at,
          'is_active', (e.clock_out_at is null),
          'status', e.status,
          'actual_hours', e.actual_hours,
          'duration_minutes', case
            when e.clock_out_at is not null then round(extract(epoch from (e.clock_out_at - e.clock_in_at)) / 60)
            else round(extract(epoch from (now() - e.clock_in_at)) / 60)
          end
        ) order by
          (e.clock_out_at is null) desc,
          e.clock_in_at desc
        ), '[]'::jsonb)
      ) into v_val
      from (
        select * from attendance_entries
        where deleted_at is null
          and (clock_out_at is null or clock_out_at >= now() - interval '24 hours' or clock_in_at >= now() - interval '24 hours')
        order by (clock_out_at is null) desc, clock_in_at desc
        limit 50
      ) e
      join profiles p on p.id = e.profile_id;

    elsif v_key = 'hr.headcount' and app.has('dashboard.all_workers') then
      select jsonb_build_object(
        'active', count(*) filter (where p.is_active),
        'staff',  count(*) filter (where p.is_active and p.user_kind = 'staff'))
        into v_val
        from profiles p where p.deleted_at is null;

    elsif v_key = 'spend.summary' and app.has('finance.customer_spend') then
      select jsonb_build_object(
        'total', round(coalesce(sum(tp.price), 0), 2),
        'tasks', count(*),
        'by_event', (select coalesce(jsonb_agg(row_to_json(y) order by y.total desc), '[]') from (
            select e2.id, e2.event_date,
                   coalesce(nullif(e2.end_client_name, ''), 'אירוע ' || e2.event_number) as label,
                   round(sum(tp2.price), 2) as total
              from app.task_revenue tp2
              join app.live_tasks t2 on t2.id = tp2.task_id and t2.deleted_at is null
              join app.live_events e2 on e2.id = t2.event_id and e2.deleted_at is null
             where t2.task_date between p_from and p_to and tp2.price > 0
             group by e2.id, e2.event_date, e2.end_client_name, e2.event_number
             order by 4 desc limit v_limit) y),
        'by_bucket', (select coalesce(jsonb_agg(row_to_json(z) order by z.bucket), '[]') from (
            select date_trunc(v_bucket, t3.task_date)::date as bucket,
                   round(sum(tp3.price), 2) as total
              from app.task_revenue tp3
              join app.live_tasks t3 on t3.id = tp3.task_id and t3.deleted_at is null
             where t3.task_date between p_from and p_to
             group by 1) z))
        into v_val
        from app.task_revenue tp
        join app.live_tasks t on t.id = tp.task_id and t.deleted_at is null
       where t.task_date between p_from and p_to;

    elsif v_key = 'customer.monthly' and app.has('finance.customer_monthly')
          and app.customer_id() is not null then
      select c.commission_pct, coalesce(c.commission_min_event, 0)
        into v_com_pct, v_com_min
        from customers c where c.id = app.customer_id();

      with ev as (
        select e.id, e.event_date,
               date_trunc('month', e.event_date)::date as month,
               coalesce((select sum(tr.price)
                           from app.live_tasks t
                           join app.task_revenue tr on tr.task_id = t.id
                          where t.event_id = e.id and t.deleted_at is null), 0) as total
          from app.live_events e
         where e.deleted_at is null
           and e.event_date between
                 least(p_from, (date_trunc('month', p_to) - interval '11 months')::date) and p_to
      ), ec as (
        select ev.*,
               case when v_com_pct is null or ev.total <= v_com_min then 0
                    else round(ev.total * v_com_pct / 100, 2) end as commission,
               (v_com_pct is null or ev.total > 0) as billed
          from ev
      )
      select jsonb_build_object(
        'events',     (select count(*) from ec where billed and event_date between p_from and p_to),
        'total',      (select round(coalesce(sum(total), 0), 2)
                         from ec where billed and event_date between p_from and p_to),
        'commission', case when v_com_pct is null then null
                           else (select round(coalesce(sum(commission), 0), 2)
                                   from ec where event_date between p_from and p_to) end,
        'commission_pct', v_com_pct,
        'commission_min', v_com_min,
        'months', (select coalesce(jsonb_agg(row_to_json(m) order by m.month), '[]') from (
            select month,
                   count(*)             as events,
                   round(sum(total), 2) as total,
                   case when v_com_pct is null then null
                        else round(sum(commission), 2) end as commission
              from ec where billed group by month) m))
        into v_val;

    elsif v_key = 'fleet.status' and app.has('fleet.view') then
      select jsonb_build_object(
        'total',     count(*),
        'active',    count(*) filter (where status = 'active'),
        'in_garage', count(*) filter (where status = 'in_garage'),
        'inactive',  count(*) filter (where status = 'inactive'))
        into v_val
        from vehicles where deleted_at is null and status <> 'sold';

    elsif v_key = 'fleet.documents_expiring'
          and app.has('fleet.view') and app.has('fleet.docs_view') then
      select coalesce(jsonb_agg(row_to_json(x) order by x.expires_at), '[]') into v_val from (
        select v.id as vehicle_id, v.name, v.plate_number,
               s.kind_name, s.expires_at, s.days_left, s.status
          from vehicle_document_status s
          join vehicles v on v.id = s.vehicle_id
         where s.deleted_at is null and v.deleted_at is null and v.status <> 'sold'
           and s.status in ('expired', 'expiring')
         order by s.expires_at limit v_limit) x;

    end if;

    v_out := v_out || jsonb_build_object(v_key, v_val);
  end loop;

  return v_out;
end $$;

revoke execute on function dashboard_sections(text[], date, date, jsonb) from anon, public;
grant  execute on function dashboard_sections(text[], date, date, jsonb) to authenticated;
