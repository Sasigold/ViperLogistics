-- 0212: הכיסאות בשורה משלהם, העמלה עליהם נקבעת ביד, ועצירת סנכרון פותחת את הסכומים לעריכה
--
-- הבקשה, במילים של הבעלים: "יש ב-ViperFlow קטגוריה שנקראת kiss-ot. אני רוצה
-- שכל מה שמשויך אליה יוצג בנפרד — ריהוט חדש, ריהוט ישן, וגם כיסאות. על
-- הכיסאות שלא ייתן לי עמלה, רק יציג את הסכום, ואני ארשום ביד כמה עמלה. אם
-- מחר המפרט של הכיסאות משתנה — שתקפוץ התראה שהמפרט השתנה לאחר קביעת העמלה.
-- וכשעוצרים את הסנכרון לאירוע, הסיכום — ריהוט חדש, ישן, כיסאות — נפתח
-- לעריכה ידנית. אם מחדשים סנכרון, הידני נדרס. ובדשבורד, העמלה שהכנסתי על
-- הכיסאות נספרת כולה לוייפר."
--
-- שש הכרעות:
--
--   1. **הכיסאות הם קטגוריית הכנסה שלישית, לא עמודה על הריהוט.** ‏0190 פיצל
--      את סכום הריהוט לפי הקטלוג לשתי קטגוריות הכנסה (‏`furniture_old`,
--      ‏`furniture_new`), וזה בדיוק מה שהבעלים מבקש להוסיף לו צד שלישי:
--      ‏`furniture_chairs`. שורת ריהוט שהקטגוריה שלה ב-ViperFlow ברשימת
--      הכיסאות של החיבור **יוצאת מהישן ומהחדש** ונספרת לבד — אותו כסף אינו
--      נספר פעמיים. סך הריהוט (ישן + חדש + כיסאות) שווה בדיוק למה שהיה לפני
--      0212, ולכן כל מספר "ברוטו" (הכנסות, רווחיות, מגמה) אינו זז.
--
--   2. **שם הקטגוריה הוא הגדרה של החיבור, לא קוד.** אותו נימוק של 0192 על
--      שמות השורות: הקטלוג של ViperFlow אינו שלנו. ‏`chairs_category_names`
--      נערך ב-`/integrations`, ברירת המחדל `kiss-ot`. ההשוואה אינה תלויה
--      ברישיות ובכל הענף: מוצר בתת-קטגוריה של "kiss-ot" הוא כיסא
--      (פונקציית הקצה מסמנת כל שורה בשם הקטגוריה שלה ובשמות כל אבותיה).
--
--   3. **העמלה על הכיסאות היא סכום בשקלים שנקבע ביד** (‏`event_income.
--      commission_amount`), ולא אחוז. היא נכנסת **כולה** לחלק של וייפר — במגיע
--      של תשלומי האירוע, בפילוח ההכנסות ובסיכום הרווח של הדשבורד — וחלק
--      הלקוח הוא הסכום פחות העמלה. כל עוד לא נקבעה, החלק של וייפר הוא האחוז
--      שבחלוקת הלקוח, והמיגרציה מדליקה את הכיסאות ב-0% אצל כל לקוח שהריהוט
--      החדש דלוק אצלו — כלומר "אין עמלה עד שקבעת". הכלל עצמו (סכום ידני גובר
--      על אחוז) כללי, ב-`app.income_viper_share`, והמסך מציע אותו רק בקטגוריה
--      שמסומנת `manual_commission`.
--
--   4. **"המפרט השתנה לאחר קביעת העמלה" הוא הפרש מהבסיס.** קביעת עמלה שומרת
--      גם את הסכום שהיא נקבעה עליו (‏`commission_basis`). כל עוד הסכום שונה
--      ממנו — הכרטיס מסמן שצריך לתמחר מחדש. כשסנכרון מזיז את סכום הכיסאות
--      והוא שונה מהבסיס, יוצאת גם התראה (‏`income_commission_stale`) ונכתבת
--      שורה ביומן האירוע. קביעה חוזרת של העמלה (גם באותו סכום) מאשרת את הבסיס
--      החדש.
--
--   5. **כשהסנכרון רץ, ViperFlow הוא הבעלים של הסכומים שלו.** עד היום טופס
--      האירוע אפשר לערוך את סכומי הריהוט וההובלה גם באירוע מסונכרן — והסנכרון
--      הבא מחק את העריכה בשקט. מעכשיו קטגוריה שמקבלת סכום מ-ViperFlow, באירוע
--      שמקושר להזמנה והסנכרון שלו רץ, אינה נערכת ביד (השרת דוחה, הטופס נועל
--      את השדה). **עצירת הסנכרון (0204) פותחת אותה**, והסכומים נערכים גם
--      מכרטיס התשלומים (‏`event_income_save`).
--
--   6. **חידוש סנכרון דורס את הידני.** ‏0204/0206 השלימו בשחרור רק משלוח
--      שנדחה בזמן העצירה. כשלא הגיע דבר — האירוע נשאר עם מה שנערך ביד, וזה
--      בדיוק ההפך מהבקשה. מעכשיו השחרור מחיל מחדש את המשלוח האחרון שכבר
--      הוחל, ואז כל מה שנערך ביד בזמן העצירה חוזר למה שההזמנה אומרת. הצילום
--      של 0190 אינו משתנה, ולכן אין התראת "ההזמנה השתנתה" על שינוי שהיה רק
--      אצלנו. העמלה עצמה אינה נדרסת — היא שלנו ולא של ViperFlow — ואם הסכום
--      זז ממנה, סעיף 4 אומר זאת.
--
-- הכסף אינו נכנס ליומן האירוע (ראש צוות קורא אותו, 0082): שורות היומן של
-- העריכה ושל העמלה אומרות מה נעשה, לא כמה.

-- ===== 1. איזו קטגוריה ב-ViperFlow היא "כיסאות" ===========================

alter table viperflow_connections
  add column chairs_category_names text[] not null default array['kiss-ot'];

comment on column viperflow_connections.chairs_category_names is
  'שמות הקטגוריות בקטלוג של ViperFlow שהמוצרים שלהן (וכל תת-קטגוריה שלהן) '
  'נספרים ככיסאות — יוצאים מריהוט ישן/חדש ונכתבים לקטגוריית ההכנסה furniture_chairs. '
  'ריק = אין פיצול כיסאות (0212).';

-- ===== 2. קטגוריית ההכנסה "כיסאות" =========================================

alter table income_categories
  drop constraint if exists income_categories_viperflow_income_source_check;
alter table income_categories
  add constraint income_categories_viperflow_income_source_check
  check (viperflow_income_source in ('furniture_old', 'furniture_new', 'furniture_chairs', 'trucking'));

comment on column income_categories.viperflow_income_source is
  'מה הקטגוריה מקבלת מסנכרון ViperFlow: furniture_old / furniture_new לפי '
  'מצב הפריט בקטלוג, furniture_chairs = מוצרי קטגוריית הכיסאות של החיבור, '
  'trucking = סכום שורות ההובלה. null = אינה מקבלת (0192, 0212).';

alter table income_categories
  add column manual_commission boolean not null default false;

comment on column income_categories.manual_commission is
  'העמלה בקטגוריה הזו נקבעת ביד, בשקלים, על כל אירוע (event_income.commission_amount) — '
  'והיא כולה של וייפר. בלעדיה החלק של וייפר הוא האחוז שבחלוקת הלקוח (0212).';

insert into income_categories (name, family, color, sort_order, viperflow_income_source, manual_commission)
select 'כיסאות', 'furniture', '#ec4899', 25, 'furniture_chairs', true
 where not exists (select 1 from income_categories
                    where viperflow_income_source = 'furniture_chairs' and deleted_at is null);

-- דלוק ב-0% אצל כל מי שהריהוט החדש דלוק אצלו: "אין עמלה עד שקבעת".
insert into customer_income_splits (customer_id, category_id, viper_share_pct)
select s.customer_id, ch.id, 0
  from customer_income_splits s
  join income_categories nw on nw.id = s.category_id
                           and nw.viperflow_income_source = 'furniture_new'
                           and nw.deleted_at is null
 cross join (select id from income_categories
              where viperflow_income_source = 'furniture_chairs' and deleted_at is null) ch
on conflict (customer_id, category_id) do nothing;

-- ===== 3. העמלה הידנית על שורת ההכנסה =====================================

alter table event_income
  add column commission_amount numeric(12,2) check (commission_amount >= 0),
  add column commission_basis  numeric(12,2),
  add column commission_set_at timestamptz,
  add column commission_set_by uuid references profiles(id) on delete set null;

comment on column event_income.commission_amount is
  'עמלה בשקלים שנקבעה ביד. כשמלאה — זה החלק של וייפר, במקום amount × viper_share_pct (0212).';
comment on column event_income.commission_basis is
  'הסכום (amount) ברגע שהעמלה נקבעה. סכום ששונה ממנו = "המפרט השתנה לאחר קביעת העמלה" (0212).';

-- החלק של וייפר בשורת הכנסה: עמלה שנקבעה ביד, ואם אין — האחוז.
create or replace function app.income_viper_share(p_amount numeric, p_pct numeric, p_commission numeric)
returns numeric language sql immutable set search_path = public as $$
  select coalesce(p_commission, round(coalesce(p_amount, 0) * coalesce(p_pct, 0) / 100, 2))
$$;

comment on function app.income_viper_share(numeric, numeric, numeric) is
  'החלק של וייפר בשורת event_income: commission_amount כשנקבעה, אחרת amount × viper_share_pct (0212).';

-- ‏`dashboard_sections` היא security invoker וקוראת לה (CLAUDE.md §2.4).
revoke execute on function app.income_viper_share(numeric, numeric, numeric) from anon, public;
grant  execute on function app.income_viper_share(numeric, numeric, numeric) to authenticated;

-- ===== 4. סכום הריהוט, בלי הכיסאות — וסכום הכיסאות ========================
--
-- שורה היא "כיסא" כשאחד משמות הקטגוריה שפונקציית הקצה הצמידה לה (הקטגוריה
-- ואבותיה) ברשימה של החיבור. בלי רישיות ובלי רווחים בקצוות: "Kiss-ot " של
-- מי שהקליד ברשימה הוא אותה קטגוריה.

create or replace function app.viperflow_is_chairs(p_item jsonb, p_names text[])
returns boolean language sql immutable set search_path = public as $$
  select coalesce(cardinality(p_names), 0) > 0
     and jsonb_typeof(p_item -> 'category_names') = 'array'
     and exists (
       select 1
         from jsonb_array_elements_text(p_item -> 'category_names') n
        where lower(btrim(n)) in (select lower(btrim(x)) from unnest(p_names) x))
$$;

create or replace function app.viperflow_furniture_amount(p_items jsonb, p_new boolean, p_chairs text[])
returns numeric language sql stable set search_path = public as $$
  select coalesce(sum(coalesce((i ->> 'line_total')::numeric, 0)), 0)
  from jsonb_array_elements(
         case when jsonb_typeof(p_items) = 'array' then p_items else '[]'::jsonb end) i
  where i ->> 'line_type' = 'product'
    and coalesce((i ->> 'is_component')::boolean, false) = false
    and not app.viperflow_is_chairs(i, p_chairs)
    and coalesce((i ->> 'is_new')::boolean, false) = p_new;
$$;

comment on function app.viperflow_furniture_amount(jsonb, boolean, text[]) is
  'סכום `line_total` של שורות הריהוט לפי מצב הפריט, בלי שורות הכיסאות. '
  'מה שאינו new הוא old (0190, 0212).';

create or replace function app.viperflow_chairs_amount(p_items jsonb, p_chairs text[])
returns numeric language sql stable set search_path = public as $$
  select coalesce(sum(coalesce((i ->> 'line_total')::numeric, 0)), 0)
  from jsonb_array_elements(
         case when jsonb_typeof(p_items) = 'array' then p_items else '[]'::jsonb end) i
  where i ->> 'line_type' = 'product'
    and coalesce((i ->> 'is_component')::boolean, false) = false
    and app.viperflow_is_chairs(i, p_chairs);
$$;

comment on function app.viperflow_chairs_amount(jsonb, text[]) is
  'סכום `line_total` של שורות הריהוט שהקטגוריה שלהן ברשימת הכיסאות של החיבור (0212).';

-- ===== 5. ההתראה: המפרט השתנה לאחר קביעת העמלה ============================

select app.register_notification_type('income_commission_stale',
  'המפרט השתנה לאחר קביעת העמלה',
  'סכום של קטגוריה שהעמלה עליה נקבעת ביד (כיסאות) השתנה בסנכרון מ-ViperFlow אחרי '
  'שהעמלה נקבעה — צריך לתמחר אותה מחדש',
  'אירועים', array['admin'], 'event', 'forced', 'opt_out', 'opt_in', 50);

-- כל מנהלי המערכת — אותם נמענים של "ההזמנה השתנתה" (0190).
create or replace function app.notify_commission_stale(
  p_event      uuid,
  p_customer   uuid,
  p_number     text,
  p_label      text,
  p_basis      numeric,
  p_amount     numeric,
  p_commission numeric)
returns void language plpgsql security definer set search_path = public as $$
declare
  r      record;
  v_body text;
begin
  if p_event is null then return; end if;
  if not app.notification_in_scope('income_commission_stale', 'customer', p_customer) then
    return;
  end if;

  v_body := coalesce((select name from customers where id = p_customer), 'אירוע')
         || coalesce(' · הזמנה ' || p_number, '')
         || ' — ' || coalesce(p_label, 'הסכום') || ': '
         || to_char(coalesce(p_amount, 0), 'FM999G999G990D00') || ' ₪ (העמלה '
         || to_char(coalesce(p_commission, 0), 'FM999G999G990D00') || ' ₪ נקבעה על '
         || to_char(coalesce(p_basis, 0), 'FM999G999G990D00') || ' ₪). יש לתמחר מחדש את העמלה.';

  for r in select id from profiles
    where is_admin and is_active and deleted_at is null
  loop
    perform app.notify(r.id, 'income_commission_stale', 'המפרט השתנה לאחר קביעת העמלה',
      left(v_body, 500), 'event', p_event);
  end loop;
end $$;

revoke execute on function app.notify_commission_stale(uuid, uuid, text, text, numeric, numeric, numeric)
  from anon, authenticated, public;

-- ===== 6. ההפרש: הכיסאות הם סעיף כסף ======================================
-- גוף 0192, ועוד מפתח אחד.

create or replace function app.viperflow_changes(p_before jsonb, p_after jsonb)
returns text[] language plpgsql stable set search_path = public as $$
declare
  v_out    text[] := '{}';
  v_keys   text[] := array['event_date', 'delivery', 'return', 'location', 'customer_name',
                           'notes', 'status', 'trucks', 'workers',
                           'crew_price', 'trucking', 'furniture_old', 'furniture_new',
                           'furniture_chairs'];
  v_labels text[] := array['תאריך האירוע', 'ההקמה', 'הפירוק', 'האולם', 'הלקוח הסופי',
                           'הערת ההזמנה', 'סטטוס ההזמנה', 'כמות משאיות', 'כמות עובדים',
                           'מחיר הקמה ופירוק', 'הובלות', 'ריהוט ישן', 'ריהוט חדש',
                           'כיסאות'];
  v_money  text[] := array['crew_price', 'trucking', 'furniture_old', 'furniture_new',
                           'furniture_chairs'];
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
  'מה השתנה בין שני צילומי הזמנה, כשורות לאדם — ליומן ולהתראה (0190, 0192, 0212).';

revoke execute on function app.viperflow_changes(jsonb, jsonb)
  from anon, authenticated, public;

-- ===== 7. המתרגם: הכיסאות בנפרד, וההתראה על העמלה =========================
-- גוף 0204 (שלא השתנה ב-0206), ועוד: הסכום בלי הכיסאות, שורת הכיסאות,
-- הבדיקה מול בסיס העמלה, והמפתח בצילום.

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
  v_chairs      numeric;
  v_ch_before   numeric;
  v_ch_comm     numeric;
  v_ch_basis    numeric;
  v_ch_label    text;
  v_ch_alert    boolean := false;
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
  -- מעטפה ישנה, בלי עץ הקטגוריות, סופרת הכול לישן ולחדש כמו לפני 0212 —
  -- ולכן הכיסאות שלה אפס, כדי שאותו כסף לא ייספר פעמיים. ההנחה חלה על
  -- הכיסאות כמו על כל שורת ריהוט.
  v_cats := v_catalog and coalesce((p_order ->> 'categories_enriched')::boolean, false);

  if v_catalog then
    v_old_amount := round(app.viperflow_furniture_amount(p_order -> 'items', false,
      case when v_cats then v_conn.chairs_category_names end) * (1 - v_discount / 100), 2);
    v_new_amount := round(app.viperflow_furniture_amount(p_order -> 'items', true,
      case when v_cats then v_conn.chairs_category_names end) * (1 - v_discount / 100), 2);
    v_chairs := case when v_cats
      then round(app.viperflow_chairs_amount(p_order -> 'items', v_conn.chairs_category_names)
                 * (1 - v_discount / 100), 2)
      else 0 end;
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

    -- ‏0212: הכיסאות, והעמלה שנקבעה עליהם ביד. סכום שזז בסנכרון הזה וגם שונה
    -- ממה שהעמלה נקבעה עליו הוא בדיוק "המפרט השתנה לאחר קביעת העמלה". סכום
    -- שחזר אל הבסיס אינו מתריע — העמלה שוב נכונה.
    select ei.amount, ei.commission_amount, ei.commission_basis, ic.name
      into v_ch_before, v_ch_comm, v_ch_basis, v_ch_label
      from event_income ei
      join income_categories ic on ic.id = ei.category_id
     where ei.event_id = v_event_id
       and ic.viperflow_income_source = 'furniture_chairs'
       and ic.is_active and ic.deleted_at is null;
    if app.viperflow_apply_income(v_event_id, v_conn.customer_id, 'furniture_chairs', v_chairs) then
      if v_created and v_chairs <> 0 then
        v_parts := v_parts || ('כיסאות ' || to_char(v_chairs, 'FM999G999G990D00') || ' ₪');
      end if;
      -- מעטפה בלי עץ הקטגוריות אינה יודעת דבר על הכיסאות: האפס שלה אינו
      -- "המפרט השתנה".
      if v_cats and v_ch_comm is not null
         and v_ch_before is distinct from v_chairs
         and v_ch_basis is distinct from v_chairs then
        v_ch_alert := true;
        v_parts := v_parts || (coalesce(v_ch_label, 'כיסאות')
          || ': המפרט השתנה לאחר קביעת העמלה — יש לתמחר אותה מחדש');
      end if;
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
    'furniture_chairs', case when v_cats then v_chairs end,
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
  if v_ch_alert then
    perform app.notify_commission_stale(v_event_id, v_conn.customer_id, v_number,
      coalesce(v_ch_label, 'כיסאות'), v_ch_basis, v_chairs, v_ch_comm);
  end if;

  return jsonb_build_object(
    'status',   'processed',
    'event_id', v_event_id,
    'created',  v_created,
    'changes',  to_jsonb(v_changes),
    'items',    v_items);
end $$;

revoke execute on function app.viperflow_is_chairs(jsonb, text[]) from anon, authenticated, public;
revoke execute on function app.viperflow_furniture_amount(jsonb, boolean, text[]) from anon, authenticated, public;
revoke execute on function app.viperflow_chairs_amount(jsonb, text[]) from anon, authenticated, public;
revoke execute on function app.viperflow_apply_order(uuid, jsonb, text, boolean) from anon, authenticated, public;

-- הגרסה הדו-פרמטרית סופרת את הכיסאות פעמיים, ואין לה עוד קורא (0192 §9).
drop function if exists app.viperflow_furniture_amount(jsonb, boolean);

-- ===== 8. חידוש סנכרון דורס את הידני =======================================
-- גוף 0206, ועוד: כשלא נדחה דבר בזמן העצירה — המשלוח האחרון שהוחל מוחל שוב.

create or replace function viperflow_set_event_lock(p_event_id uuid, p_locked boolean)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_link     viperflow_links;
  v_actor    uuid := app.profile_id();
  v_name     text;
  v_delivery uuid;
  v_result   jsonb;
  v_reapply  boolean := false;
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
            'הסנכרון מ-ViperFlow נעצר — סכומים, שעות, כמויות ומפרט לא ישתנו מההזמנה, '
            || 'וסכומי ההכנסות פתוחים לעריכה ידנית');

    return jsonb_build_object('locked', true, 'locked_at', now());
  end if;

  -- ── שחרור ────────────────────────────────────────────────────────────────
  -- ‏0206: המשלוח הנעול שהחותמת שלו חדשה ממה שכבר הוחל — בלי תנאי על זמן
  -- ההגעה (ראו §2 בראש הקובץ). החותמת נקראת רק כשהיא נראית כתאריך, כדי
  -- שמעטפה פגומה לא תפיל את השחרור כולו.
  select x.id into v_delivery
    from (select d.id, d.received_at,
                 case when (d.payload #>> '{data,updated_at}') ~ '^\d{4}-\d{2}-\d{2}'
                      then (d.payload #>> '{data,updated_at}')::timestamptz end as stamp
            from viperflow_deliveries d
           where d.connection_id = v_link.connection_id
             and d.entity_id = v_link.order_id::text
             and d.status = 'ignored'
             and d.reason = 'הסנכרון לאירוע הזה נעצר — ההזמנה נשמרה ולא הוחלה') x
   where x.stamp is not null
     and (v_link.order_updated_at is null or x.stamp > v_link.order_updated_at)
   order by x.stamp desc, x.received_at desc
   limit 1;

  -- ‏0212: לא נדחה דבר בזמן העצירה — ובכל זאת חידוש מחזיר את האירוע למה
  -- שההזמנה אומרת, כי מה שנערך ביד בזמן העצירה אמור להידרס. לכן המשלוח
  -- האחרון שכבר הוחל (יצירה או עדכון) מוחל שוב. הצילום זהה, ולכן אין התראת
  -- "ההזמנה השתנתה". משלוח שנושא חותמת ישנה מביטול שהוחל אחריו נעצר בשומר
  -- החותמת של המתרגם ואינו מחזיר דבר.
  if v_delivery is null then
    select x.id into v_delivery
      from (select d.id, d.received_at,
                   case when (d.payload #>> '{data,updated_at}') ~ '^\d{4}-\d{2}-\d{2}'
                        then (d.payload #>> '{data,updated_at}')::timestamptz end as stamp
              from viperflow_deliveries d
             where d.connection_id = v_link.connection_id
               and d.entity_id = v_link.order_id::text
               and d.status = 'processed'
               and d.event_type in ('order.created', 'order.updated')) x
     order by x.stamp desc nulls last, x.received_at desc
     limit 1;
    v_reapply := v_delivery is not null;
  end if;

  update viperflow_links set sync_locked_at = null, sync_locked_by = null
   where event_id = p_event_id;

  insert into event_activity (event_id, kind, actor_profile_id, actor_name, note)
  values (p_event_id, 'sync_unlocked'::event_activity_kind, v_actor, v_name,
          case when v_delivery is null
               then 'הסנכרון מ-ViperFlow חודש — לא הגיעו שינויים בזמן העצירה'
               when v_reapply
               then 'הסנכרון מ-ViperFlow חודש — לא הגיעו שינויים בזמן העצירה, והנתונים '
                    || 'מההזמנה הוחלו מחדש במקום מה שנערך ביד'
               else 'הסנכרון מ-ViperFlow חודש — השינויים שהגיעו בזמן העצירה מוחלים עכשיו' end);

  if v_delivery is not null then
    v_result := viperflow_replay(v_delivery);
  end if;

  return jsonb_build_object('locked', false, 'locked_at', null,
                            'caught_up', v_delivery is not null and not v_reapply,
                            'reapplied', v_reapply,
                            'result', v_result);
end $$;

revoke execute on function viperflow_set_event_lock(uuid, boolean) from anon, public;
grant  execute on function viperflow_set_event_lock(uuid, boolean) to authenticated;

-- ===== 9. עריכה ידנית: רק כשהסנכרון אינו רץ ================================
--
-- גוף 0068, ועוד שער אחד: באירוע שמקושר להזמנה והסנכרון שלו רץ, קטגוריה
-- שמקבלת סכום מ-ViperFlow אינה משתנה ביד. ערך זהה למה שכבר שמור עובר בשקט —
-- טופס האירוע שולח את כל הקטגוריות בכל שמירה, ושמירה של שדה אחר לא תיפול
-- בגלל סכום שאיש לא נגע בו. השגיאה אינה 42501: זה כלל עסקי, לא הרשאה.

create or replace function app.apply_event_income(p_event_id uuid, p_customer uuid, payload jsonb)
returns void language plpgsql security definer set search_path = public as $$
declare
  r        record;
  v_cat    uuid;
  v_amount numeric;
  v_pct    numeric;
  v_name   text;
  v_source text;
  v_synced boolean;
  v_found  boolean;
  v_now    numeric;
begin
  if not (payload ? 'event_income') then return; end if;
  if not app.has('finance.income_edit') then return; end if;

  -- ‏0212: null = האירוע אינו מקושר ל-ViperFlow.
  select l.sync_locked_at is null into v_synced
    from viperflow_links l where l.event_id = p_event_id;

  for r in select key, nullif(btrim(coalesce(value, '')), '') as raw
             from jsonb_each_text(coalesce(payload -> 'event_income', '{}'::jsonb))
  loop
    begin
      v_cat := r.key::uuid;
    exception when others then
      raise exception 'קטגוריית הכנסה לא מוכרת: %', r.key;
    end;
    v_name := null;
    v_source := null;
    select name, viperflow_income_source into v_name, v_source
      from income_categories where id = v_cat;

    v_amount := null;
    if r.raw is not null then
      begin
        v_amount := r.raw::numeric;
      exception when others then
        raise exception 'ערך לא תקין בשדה "%": %', coalesce(v_name, r.key), r.raw;
      end;
      if v_amount < 0 then
        raise exception 'סכום שלילי אינו חוקי בשדה "%"', coalesce(v_name, r.key);
      end if;
    end if;

    -- ‏0212: הסכום של ViperFlow, באירוע שהסנכרון שלו רץ.
    if coalesce(v_synced, false) and v_source is not null then
      select true, ei.amount into v_found, v_now
        from event_income ei where ei.event_id = p_event_id and ei.category_id = v_cat;
      if (v_amount is null and coalesce(v_found, false))
         or (v_amount is not null and v_now is distinct from v_amount) then
        raise exception 'הסכום של "%" מגיע מ-ViperFlow — כדי לערוך אותו ביד יש לעצור את הסנכרון לאירוע',
          coalesce(v_name, r.key);
      end if;
      v_found := null;
      v_now := null;
      continue;
    end if;

    if v_amount is null then
      delete from event_income
       where event_id = p_event_id and category_id = v_cat;
      continue;
    end if;

    -- ה-snapshot: האחוז הנוכחי של הלקוח, ברגע הכתיבה. קטגוריה בלי שורת חלוקה
    -- אינה מופעלת ללקוח הזה — והזנה אליה היא טעות שצריך לשמוע עליה.
    v_pct := null;
    select s.viper_share_pct into v_pct
      from customer_income_splits s
      join income_categories ic on ic.id = s.category_id
     where s.customer_id = p_customer and s.category_id = v_cat
       and ic.deleted_at is null;
    if v_pct is null then
      raise exception 'הקטגוריה "%" אינה מופעלת ללקוח של האירוע',
        coalesce(v_name, r.key);
    end if;

    insert into event_income (event_id, category_id, amount, viper_share_pct)
    values (p_event_id, v_cat, v_amount, v_pct)
    on conflict (event_id, category_id) do update set
      amount = excluded.amount,
      viper_share_pct = excluded.viper_share_pct;
  end loop;
end $$;

revoke execute on function app.apply_event_income(uuid, uuid, jsonb) from anon, authenticated, public;

-- ===== 10. עריכת הסכומים מכרטיס התשלומים ===================================
--
-- אותו מסלול בדיוק של טופס האירוע (‏`app.apply_event_income`), ולכן אותם
-- כללים: סכום אי-שלילי, קטגוריה מופעלת ללקוח, ושער הסנכרון של סעיף 9. המפתח
-- הוא `finance.income_edit` — אותו מפתח שמזין הכנסות בטופס.

create or replace function app.can_edit_event_income()
returns boolean language sql stable security definer set search_path = public as $$
  select app.is_admin()
      or (app.user_kind() = 'staff' and app.has('finance.income_edit'))
$$;

revoke execute on function app.can_edit_event_income() from anon, public;
grant  execute on function app.can_edit_event_income() to authenticated;

create or replace function event_income_save(p_event_id uuid, p_amounts jsonb)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_event events;
  v_actor uuid := app.profile_id();
begin
  if not app.can_edit_event_income() then
    raise exception 'אין לך הרשאה לערוך הכנסות' using errcode = '42501';
  end if;

  select * into v_event from events where id = p_event_id and deleted_at is null;
  if v_event.id is null then raise exception 'אירוע לא נמצא'; end if;
  if jsonb_typeof(coalesce(p_amounts, '{}'::jsonb)) <> 'object' then
    raise exception 'מבנה סכומים לא תקין';
  end if;

  perform app.apply_event_income(p_event_id, v_event.customer_id,
    jsonb_build_object('event_income', coalesce(p_amounts, '{}'::jsonb)));

  insert into event_activity (event_id, kind, actor_profile_id, actor_name, note)
  values (p_event_id, 'note', v_actor, (select full_name from profiles where id = v_actor),
          'סכומי ההכנסות של האירוע נערכו ביד');
end $$;

revoke execute on function event_income_save(uuid, jsonb) from anon, public;
grant  execute on function event_income_save(uuid, jsonb) to authenticated;

-- ===== 11. קביעת העמלה =====================================================
--
-- ‏null מוחק את העמלה (והחלק של וייפר חוזר לאחוז). כל קביעה — גם באותו סכום —
-- מצלמת את הסכום הנוכחי כבסיס, וכך "אישור" אחרי שינוי במפרט הוא קביעה
-- חוזרת. עמלה גבוהה מהסכום שעליו היא נקבעת היא טעות הקלדה, לא עסקה.

create or replace function event_income_set_commission(
  p_event_id    uuid,
  p_category_id uuid,
  p_amount      numeric)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_row   event_income;
  v_cat   income_categories;
  v_actor uuid := app.profile_id();
begin
  if not app.can_edit_event_income() then
    raise exception 'אין לך הרשאה לקבוע עמלה' using errcode = '42501';
  end if;

  if not exists (select 1 from events where id = p_event_id and deleted_at is null) then
    raise exception 'אירוע לא נמצא';
  end if;

  select * into v_cat from income_categories where id = p_category_id;
  if v_cat.id is null then raise exception 'קטגוריית הכנסה לא נמצאה'; end if;
  if not v_cat.manual_commission then
    raise exception 'העמלה בקטגוריה "%" נגזרת מהאחוז של הלקוח, ואינה נקבעת ביד', v_cat.name;
  end if;

  select * into v_row from event_income
   where event_id = p_event_id and category_id = p_category_id
   for update;
  if v_row.event_id is null then
    raise exception 'אין לאירוע סכום בקטגוריה "%" — אין על מה לקבוע עמלה', v_cat.name;
  end if;

  if p_amount is not null then
    if p_amount < 0 then raise exception 'עמלה שלילית אינה חוקית'; end if;
    if round(p_amount, 2) <> p_amount then
      raise exception 'העמלה — עד שתי ספרות אחרי הנקודה';
    end if;
    if p_amount > v_row.amount then
      raise exception 'העמלה גבוהה מסכום ה%', v_cat.name;
    end if;
  end if;

  update event_income set
    commission_amount = p_amount,
    commission_basis  = case when p_amount is null then null else amount end,
    commission_set_at = case when p_amount is null then null else now() end,
    commission_set_by = case when p_amount is null then null else v_actor end
   where event_id = p_event_id and category_id = p_category_id
  returning * into v_row;

  insert into event_activity (event_id, kind, actor_profile_id, actor_name, note)
  values (p_event_id, 'note', v_actor, (select full_name from profiles where id = v_actor),
          case when p_amount is null
               then 'העמלה על ' || v_cat.name || ' נמחקה'
               else 'העמלה על ' || v_cat.name || ' נקבעה ביד' end);

  return jsonb_build_object(
    'commission', v_row.commission_amount,
    'basis',      v_row.commission_basis,
    'amount',     v_row.amount);
end $$;

revoke execute on function event_income_set_commission(uuid, uuid, numeric) from anon, public;
grant  execute on function event_income_set_commission(uuid, uuid, numeric) to authenticated;

-- ===== 12. "מגיע" סופר את העמלה הידנית =====================================
-- ההגדרה של 0207 מילה במילה, והחלק של וייפר עובר דרך `app.income_viper_share`.

create or replace view app.event_payment_dues with (security_invoker = true) as
select e.id            as event_id,
       e.customer_id,
       e.event_date,
       e.end_client_name,
       e.event_number,
       not exists (select 1 from app.live_events le where le.id = e.id) as cancelled,
       coalesce(lg.total, 0)                             as logistics,
       coalesce(inc.share, 0)                            as income_share,
       coalesce(lg.total, 0) + coalesce(inc.share, 0) + coalesce(ch.total, 0) as due,
       coalesce(pd.paid, 0)                              as paid,
       coalesce(lg.total, 0) + coalesce(inc.share, 0) + coalesce(ch.total, 0)
         - coalesce(pd.paid, 0)                          as balance,
       coalesce(pd.cnt, 0)                               as payments_count,
       pd.last_at                                        as last_paid_at,
       coalesce(ch.total, 0)                             as charges
  from events e
  join customers c on c.id = e.customer_id and c.event_payments_enabled
  left join lateral (
    select sum(tr.price) as total
      from app.live_tasks t
      join app.task_revenue tr on tr.task_id = t.id
     where t.event_id = e.id) lg on true
  left join lateral (
    select sum(app.income_viper_share(ei.amount, ei.viper_share_pct, ei.commission_amount)) as share
      from event_income ei
      join app.live_events le on le.id = ei.event_id
     where ei.event_id = e.id) inc on true
  left join lateral (
    select sum(ec.amount) as total
      from event_charges ec
      join app.live_events le on le.id = ec.event_id
     where ec.event_id = e.id and ec.deleted_at is null) ch on true
  left join lateral (
    select sum(r.amount) as paid, count(*) as cnt, max(r.received_at) as last_at
      from receipts r
     where r.event_id = e.id and r.deleted_at is null) pd on true
 where e.deleted_at is null;

comment on view app.event_payment_dues is
  'לכל אירוע של לקוח שתשלומי אירועים פתוחים לו: כמה מגיע לוייפר (משימות + חלק '
  'וייפר מההכנסות — עמלה ידנית או אחוז + חיובים ידניים), כמה שולם וכמה נשאר '
  '(0205, 0207, 0212). נקרא רק מתוך פונקציות definer.';

revoke all on app.event_payment_dues from anon, authenticated, public;

-- ===== 13. הפירוט של האירוע: העמלה, הבסיס, ומה פתוח לעריכה =================
--
-- ההגדרה של 0207, ועוד:
--   * בשורת הכנסה: `category_id`, ‏`manual_commission`, ‏`commission`,
--     ‏`commission_basis`, ‏`commission_set_at`, ‏`commission_stale` ו-`synced`
--     (הסכום מגיע מ-ViperFlow והסנכרון רץ). שורה ידנית נשלחת עם `pct` ריק —
--     אין בה אחוז — ונכללת גם כשהסכום אפס אם נקבעה עליה עמלה.
--   * ברמת האירוע: `viperflow` (מקושר? נעול?), ‏`can_edit_income`, וכשמותר —
--     `income_categories`: הקטגוריות שמופעלות ללקוח עם הסכום הנוכחי, לחלון
--     העריכה. ‏`editable` לכל אחת לפי השער של סעיף 9.

create or replace function event_payment_summary(p_event_id uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_event   events;
  v_enabled boolean;
  v_row     app.event_payment_dues;
  v_lines   jsonb;
  v_pays    jsonb;
  v_link    viperflow_links;
  v_synced  boolean;
  v_can     boolean := app.can_edit_event_income();
  v_cats    jsonb;
begin
  if not app.can_view_event_payments() then
    raise exception 'אין לך הרשאה לצפות בתשלומי אירועים' using errcode = '42501';
  end if;

  select * into v_event from events where id = p_event_id and deleted_at is null;
  if v_event.id is null then raise exception 'אירוע לא נמצא'; end if;

  select event_payments_enabled into v_enabled from customers where id = v_event.customer_id;
  if not coalesce(v_enabled, false) then
    return jsonb_build_object('enabled', false);
  end if;

  select * into v_row from app.event_payment_dues where event_id = p_event_id;

  select * into v_link from viperflow_links where event_id = p_event_id;
  v_synced := v_link.event_id is not null and v_link.sync_locked_at is null;

  select coalesce(jsonb_agg(x.line order by x.sort, x.at), '[]'::jsonb) into v_lines from (
    select 0 as sort, null::timestamptz as at, jsonb_build_object(
             'key', 'logistics', 'label', 'לוגיסטיקה',
             'amount', round(v_row.logistics, 2), 'gross', null, 'pct', null) as line
     where v_row.logistics <> 0
    union all
    select (case when ei.commission_amount is null and not ic.manual_commission
                      and ei.viper_share_pct >= 100 then 1000 else 2000 end) + ic.sort_order, null,
           jsonb_build_object(
             'key', ic.id, 'label', ic.name, 'category_id', ic.id,
             'amount', app.income_viper_share(ei.amount, ei.viper_share_pct, ei.commission_amount),
             'gross', ei.amount,
             'pct', case when ic.manual_commission or ei.commission_amount is not null
                         then null else ei.viper_share_pct end,
             'manual_commission', ic.manual_commission,
             'commission', ei.commission_amount,
             'commission_basis', ei.commission_basis,
             'commission_set_at', ei.commission_set_at,
             'commission_stale', ei.commission_amount is not null
                                 and ei.commission_basis is distinct from ei.amount,
             'synced', v_synced and ic.viperflow_income_source is not null)
      from event_income ei
      join app.live_events le on le.id = ei.event_id
      join income_categories ic on ic.id = ei.category_id
     where ei.event_id = p_event_id
       and (ei.amount <> 0 or ei.commission_amount is not null)
    union all
    select 3000, ec.created_at,
           jsonb_build_object(
             'key', ec.id, 'label', ec.label, 'amount', ec.amount,
             'gross', null, 'pct', null, 'charge_id', ec.id, 'note', ec.note)
      from event_charges ec
      join app.live_events le on le.id = ec.event_id
     where ec.event_id = p_event_id and ec.deleted_at is null) x;

  select coalesce(jsonb_agg(jsonb_build_object(
           'id', r.id, 'amount', r.amount, 'received_at', r.received_at,
           'method', r.method, 'note', r.note, 'created_at', r.created_at,
           'created_by_name', p.full_name)
           order by r.received_at desc, r.created_at desc), '[]'::jsonb)
    into v_pays
    from receipts r
    left join profiles p on p.id = r.created_by
   where r.event_id = p_event_id and r.deleted_at is null;

  if v_can then
    select coalesce(jsonb_agg(jsonb_build_object(
             'id', ic.id, 'name', ic.name, 'family', ic.family,
             'amount', ei.amount,
             'manual_commission', ic.manual_commission,
             'source', ic.viperflow_income_source,
             'editable', not (v_synced and ic.viperflow_income_source is not null))
             order by ic.sort_order, ic.name), '[]'::jsonb)
      into v_cats
      from customer_income_splits s
      join income_categories ic on ic.id = s.category_id
                               and ic.is_active and ic.deleted_at is null
      left join event_income ei on ei.event_id = p_event_id and ei.category_id = ic.id
     where s.customer_id = v_event.customer_id;
  end if;

  return jsonb_build_object(
    'enabled',   true,
    'cancelled', v_row.cancelled,
    'lines',     v_lines,
    'due',       round(v_row.due, 2),
    'paid',      round(v_row.paid, 2),
    'balance',   round(v_row.balance, 2),
    'payments',  v_pays,
    'can_manage', app.can_manage_event_payments(),
    'can_edit_income', v_can,
    'viperflow', case when v_link.event_id is not null
                      then jsonb_build_object('locked', v_link.sync_locked_at is not null) end,
    'income_categories', v_cats);
end $$;

revoke execute on function event_payment_summary(uuid) from anon, public;
grant  execute on function event_payment_summary(uuid) to authenticated;

-- ===== 14. רשימת שמות הכיסאות במסך החיבור ==================================
-- החתימה משתנה, ולכן הישנה נמחקת (0192 §8). רשימה ריקה כאן מותרת — בניגוד
-- לשורות ההובלה והצוות — ופירושה "אין פיצול כיסאות".

drop function if exists viperflow_set_connection(uuid, text, boolean, text, uuid, text, text[], text[]);

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
  p_crew_names      text[] default null,
  -- ‏0212: קטגוריות הכיסאות בקטלוג של ViperFlow. ריק = אין פיצול כיסאות.
  p_chairs_names    text[] default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_id       uuid;
  v_trucking text[];
  v_crew     text[];
  v_chairs   text[];
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
  v_chairs   := (select coalesce(array_agg(distinct btrim(n)), '{}'::text[])
                   from unnest(coalesce(p_chairs_names, '{}'::text[])) n
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
                                       trucking_line_names, crew_line_names,
                                       chairs_category_names)
    values (p_customer_id, btrim(p_label), coalesce(p_is_active, true),
            nullif(btrim(p_notes), ''), coalesce(p_logistics_price, 'crew'),
            coalesce(v_trucking, array['הובלה']),
            coalesce(v_crew, array['סידור ואיסוף']),
            case when p_chairs_names is null then array['kiss-ot'] else v_chairs end)
    returning id into v_id;
  else
    update viperflow_connections set
      customer_id            = p_customer_id,
      label                  = btrim(p_label),
      is_active              = coalesce(p_is_active, is_active),
      notes                  = nullif(btrim(p_notes), ''),
      logistics_price_source = coalesce(p_logistics_price, logistics_price_source),
      trucking_line_names    = coalesce(v_trucking, trucking_line_names),
      crew_line_names        = coalesce(v_crew, crew_line_names),
      chairs_category_names  = case when p_chairs_names is null
                                    then chairs_category_names else v_chairs end
    where id = p_connection_id and deleted_at is null
    returning id into v_id;
    if v_id is null then raise exception 'חיבור לא נמצא'; end if;
  end if;

  return v_id;
end $$;

revoke execute on function viperflow_set_connection(uuid, text, boolean, text, uuid, text, text[], text[], text[])
  from anon, public;
grant  execute on function viperflow_set_connection(uuid, text, boolean, text, uuid, text, text[], text[], text[])
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
      -- ‏0212: אילו קטגוריות בקטלוג הן כיסאות.
      'chairs_category_names',  to_jsonb(c.chairs_category_names),
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

-- ===== 15. הדשבורד: העמלה הידנית כולה של וייפר =============================
--
-- גוף 0174, וארבעה סקשנים משתנים:
--   * ‏`income.by_category` — לכל קטגוריה גם `commission` (סך העמלה הידנית)
--     ו-`manual_commission`, ובראש `manual_commission_total`.
--   * ‏`income.mix` — פרוסה "עמלת כיסאות": סך העמלה הידנית, מאה אחוז.
--   * ‏`finance.profit_summary` — אותה עמלה נכנסת להכנסות של הרווח.
--   * ‏`finance.client_share` — חלק הלקוח בקטגוריה עם עמלה ידנית הוא הסכום פחות
--     העמלה (ולא האחוז), ועוד `chairs_raw`, ‏`chairs_commission`, ‏`chairs_share`.

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
      -- ‏0212: עמלה שנקבעה ביד (כיסאות) — כולה של וייפר
      furn_manual as (
        select coalesce(sum(ei.commission_amount), 0) as total
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
               -- ‏0212: העמלה שנקבעה ביד בקטגוריה — כולה של וייפר
               round(coalesce(sum(ei.commission_amount) filter (where e.id is not null), 0), 2) as commission
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
          round(coalesce((select sum(commission) from cat where manual_commission), 0), 2))
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
      -- 5. ‏0212: עמלה שנקבעה ביד (כיסאות) — 100% להכנסות
      furn_manual as (
        select 'עמלת ' || ic.name as label, ic.color as color,
               round(sum(coalesce(ei.commission_amount, 0)), 2) as total
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
                                                      then coalesce(ei.commission_amount, 0) else 0 end), 0), 2),
        'chairs_share', round(coalesce(sum(case when ic.manual_commission
                                                 then ei.amount - coalesce(ei.commission_amount, 0) else 0 end), 0), 2),
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
