-- 0118: "הובלה בלבד" הוא משתנה של המחשבון
--
-- שורת "ראש צוות" במחשבון מותנית ב-`requires_team_lead` בלבד (0017), ולכן
-- היא נגבית גם על משימה שכל תוכנה הוא להסיע ציוד מנקודה לנקודה — ובהובלה
-- בלבד אין צוות בשטח שראש צוות ינהל. הלקוח שמשלם עליה משלם על תפקיד שלא
-- אויש.
--
-- **מנגנון, לא חריג.** המנוע כבר יודע לתנות כל שורת מחיר: ‏`app.price_cond`
-- (0017) תומך ב-`is_true`, ‏`is_false`, ‏`eq`, ‏`ne`, ‏`in` ו-`not_in`, ולכן
-- הכול חסר כאן הוא המשתנה עצמו. מה שמוסיפים הוא שורה אחת ב-`pricing_vars`
-- ואפשרות אחת בעורך התנאים; הכלל של לקוח מסוים נשאר **נתון**, כמו כל שאר
-- ההבדלים בין לקוחות במערכת (‏`customer_pricing_rules`, ‏`pricing_zones`,
-- ‏`customer_form_fields`).
--
-- **הדגל ולא השם.** ‏`execution_methods.is_transport_only` כבר קיים מ-0092
-- ומזין את מנוע מחירי הקבלנים (`app.recompute_contractor_price`), ומכאן
-- אותה עמודה מזינה גם את מנוע מחירי הלקוחות: עמודה אחת, שני מנועים, בלי
-- דגל שני שיכול להיפרד ממנה. השוואה לשם "הובלה בלבד" הייתה נשברת ברגע
-- שמישהו עורך אותו במסך ההגדרות — אותו נימוק בדיוק של `statuses.code`.
--
-- **הגוף מ-0020 ולא מ-0017.** ‏0020 היא הגרסה החיה, והיא זו שהחליפה את חישוב
-- זמן הנסיעה הכפול בקריאה ל-`app.task_travel_hours`. העתקה מ-0017 הייתה
-- מחזירה את הכפילות ההיא בשקט.
--
-- **וזה no-op לכל משימה שאינה הובלה בלבד.** ‏`app.price_calc` (0060) מחזירה
-- ‏`total/subtotal/hours/per_worker/workers/hour_lines/lines` ואינה מהדהדת את
-- ‏`vars`, ואף כלל מוזרע אינו מתייחס למשתנה החדש; המספרים המקובעים בבדיקת
-- התמחור אינם זזים.

create or replace function app.pricing_vars(p_task_id uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  t        tasks;
  e        events;
  z        pricing_zones;
  v_code   text;
  v_method text;
  v_transport boolean;
  v_travel numeric;
begin
  select * into t from tasks where id = p_task_id;
  if t.id is null then return '{}'::jsonb; end if;

  select * into e from events where id = t.event_id;
  select code into v_code   from task_types       where id = t.task_type_id;
  select name, coalesce(is_transport_only, false) into v_method, v_transport
    from execution_methods where id = t.execution_method_id;
  -- ‏coalesce שני, מחוץ ל-select: כשאין אופן ביצוע ה-select אינו מוצא
  -- שורה כלל והמשתנה נשאר null, ו-jsonb_strip_nulls היה מוריד את
  -- המפתח. ‏false מפורש הוא מה שמאפשר לראות אותו בתצוגה המקדימה של
  -- הבונה — שם בודקים כלל חדש לפני שסומכים עליו.
  v_transport := coalesce(v_transport, false);

  -- זמן נסיעה: דריסה על המשימה גוברת, אחרת האזור שמיקום האירוע נופל בתוכו.
  -- אותה הכרעה בדיוק משמשת את גזירת המשמרת, ולכן היא נקראת ולא משוכפלת.
  v_travel := app.task_travel_hours(p_task_id);
  if e.location_lat is not null and e.location_lng is not null then
    z := app.zone_for_point(t.customer_id, e.location_lat, e.location_lng);
  end if;

  return jsonb_strip_nulls(jsonb_build_object(
    'task_type_code',      v_code,
    'worker_count',        t.worker_count,
    'hours_count',         t.hours_count,
    'worker_hours',        coalesce(t.hours_count, 0) * coalesce(t.worker_count, 0),
    'task_date',           t.task_date,
    'dow',                 extract(dow from t.task_date),
    'is_weekend',          extract(dow from t.task_date) in (5, 6),
    'start_hour',          extract(hour from t.onsite_start_time),
    'has_truck',           t.truck_id is not null,
    'execution_method_id', t.execution_method_id,
    'execution_method',    v_method,
    'is_transport_only',   v_transport,
    'travel_hours',        v_travel,
    'requires_team_lead',  t.requires_team_lead,
    'zone_name',           z.name,
    'zone_surcharge',      z.surcharge,
    'volume_m',            e.volume_m,
    'truck_count',         e.truck_count,
    'no_parking',          e.no_parking,
    'porterage',           e.porterage,
    'supplier_pickup',     e.supplier_pickup,
    'event_date',          e.event_date,
    'customer_id',         t.customer_id));
end $$;

comment on function app.pricing_vars(uuid) is
  'משתני המחשבון למשימה. is_transport_only (0118) מגיע מהדגל של אופן '
  'הביצוע — אותה עמודה שמנוע מחירי הקבלנים קורא מאז 0092.';
