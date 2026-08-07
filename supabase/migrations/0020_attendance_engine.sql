-- 0020: מנוע הנוכחות — גזירת משמרות, חישוב שכר ו-RPCs
--
-- 0019 הוא סכמה ו-RLS שרצים פעם אחת; כאן יושבים רק גופי פונקציות, שמיגרציה
-- עתידית יכולה להצהיר מחדש במלואם בלי לגעת בטבלה.
--
-- שתי נקודות שכדאי לקרוא לפני שמשנים כאן משהו:
--
-- * גזירת המשמרת יושבת ב-SQL ולא בדפדפן כי ארבעה צרכנים חייבים לקבל את
--   אותה תשובה: לוח המשמרות, שער "מותר לך להתחיל?" בשעון (שהוא הגנה ולכן
--   חייב להיות בשרת), עמודת מתוכנן-מול-בפועל בדוח, והתצלום שנשמר ברשומה.
--   מימוש שני ב-TypeScript היה הופך את הראשון מביניהם לעותק שמתיישן.
--
-- * השכר מחושב בקריאה ולא נשמר. אין טבלת שכר, אין is_manual ואין חישוב
--   מחדש: הרשומה מחזיקה שעות, ההגדרות מחזיקות תעריף, והמכפלה נעשית ברגע
--   שמישהו מסתכל. מי שאין לו attendance.view_pay מקבל מאותה שאילתה את
--   השעות בלי הסכומים.

-- ===== 1. קונפיגורציה ======================================================

create or replace function app.attendance_config(p_key text)
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce((select value from app_settings where key = p_key), '{}'::jsonb)
$$;

-- כללי השעון שחלים על עובד מסוים: ברירות המחדל הגלובליות, ומעליהן העמודות
-- שהוגדרו לו במפורש. jsonb_strip_nulls הוא מה שגורם ל-NULL בעמודה להיקרא
-- "לך לפי הגלובלי" ולא "כבוי".
create or replace function app.clock_rules(p_profile_id uuid)
returns jsonb language sql stable security definer set search_path = public as $$
  select app.attendance_config('attendance.clock') || coalesce(
    (select jsonb_strip_nulls(jsonb_build_object(
       'clock_enabled',             s.clock_enabled,
       'requires_location',         s.requires_location,
       'location_radius_m',         s.location_radius_m,
       'allow_early_clock_in',      s.allow_early_clock_in,
       'early_grace_minutes',       s.early_grace_minutes,
       'allow_clock_without_shift', s.allow_clock_without_shift))
     from worker_pay_settings s where s.profile_id = p_profile_id),
    '{}'::jsonb)
$$;

-- ===== 2. זמן נסיעה — מקור אחד ============================================
-- ההכרעה הזו כבר הייתה קיימת בתוך app.pricing_vars. חילוץ שלה לפונקציה
-- ושכתוב הקורא המקורי הוא מה שמונע מהתמחור ומהמשמרות להיפרד בעתיד.
-- NULL פירושו "לא ידוע" ולא "אפס", כדי שקבוע במחשבון התמחור ימשיך לתפוס.

create or replace function app.task_travel_hours(p_task_id uuid)
returns numeric language plpgsql stable security definer set search_path = public as $$
declare t tasks; e events; z pricing_zones;
begin
  select * into t from tasks where id = p_task_id;
  if t.id is null then return null; end if;
  if t.travel_hours is not null then return t.travel_hours; end if;
  select * into e from events where id = t.event_id;
  if e.location_lat is null or e.location_lng is null then return null; end if;
  z := app.zone_for_point(t.customer_id, e.location_lat, e.location_lng);
  return z.travel_hours;
end $$;

create or replace function app.pricing_vars(p_task_id uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  t        tasks;
  e        events;
  z        pricing_zones;
  v_code   text;
  v_method text;
  v_travel numeric;
begin
  select * into t from tasks where id = p_task_id;
  if t.id is null then return '{}'::jsonb; end if;

  select * into e from events where id = t.event_id;
  select code into v_code   from task_types       where id = t.task_type_id;
  select name into v_method from execution_methods where id = t.execution_method_id;

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

-- ===== 3. גזירת המשמרות ====================================================
-- שעות המשימה נשמרות כ-time, וההמרה שלהן ל-timestamptz נעשית מול אזור הזמן
-- של ישראל ולא מול אזור הזמן של השרת.
--
-- שימו לב שהחישוב אינו נוגע ב-tasks.onsite_end_time. זו עמודת time
-- generated, ו-time + interval ב-Postgres גולש מודולו 24 שעות: משימה
-- שמתחילה ב-22:00 ונמשכת 4 שעות מקבלת שם 02:00, ואז הסיום מוקדם מההתחלה
-- והמשמרת יוצאת שלילית. חיבור על גבי timestamptz אינו גולש.

create or replace function app.planned_shifts(p_profile_id uuid, p_from date, p_to date)
returns setof app.planned_shift_row
language plpgsql stable security definer set search_path = public as $$
declare v_gap interval;
begin
  v_gap := make_interval(mins => coalesce(
    (app.attendance_config('attendance.clock') ->> 'merge_gap_minutes')::int, 120));

  return query
  with mine as (
    -- עובד צוות
    select a.task_id as tid, bool_or(a.work_site = 'warehouse') as is_wh
      from task_assignments a
     where a.profile_id = p_profile_id
     group by a.task_id
    union all
    -- עובד קבלן, דרך הקישור בין ההתחברות לשורת הסגל
    select w.task_id, bool_or(w.work_site = 'warehouse')
      from task_contractor_workers w
      join profiles pr on pr.contractor_worker_id = w.contractor_worker_id
     where pr.id = p_profile_id
     group by w.task_id
  ),
  -- אותו אדם יכול להיות משובץ לאותה משימה בשני תפקידים (עובד וגם ראש
  -- צוות). מחסן גובר, כי מי שיוצא מהמחסן מתחיל שם בכל מקרה.
  dedup as (select m.tid, bool_or(m.is_wh) as is_wh from mine m group by m.tid),
  base as (
    select
      t.id as b_task,
      t.customer_id as b_cust,
      c.color as b_color,
      coalesce(nullif(t.title, ''), tt.name) as b_label,
      case when d.is_wh then 'warehouse' else 'field' end as b_site,
      ((t.task_date + case
          when d.is_wh and t.warehouse_start_time is not null then t.warehouse_start_time
          else coalesce(t.onsite_start_time, t.warehouse_start_time) end)
        at time zone 'Asia/Jerusalem') as b_start,
      ((t.task_date + coalesce(t.onsite_start_time, t.warehouse_start_time))
        at time zone 'Asia/Jerusalem')
        + make_interval(mins => round(coalesce(t.hours_count, 0) * 60)::int) as b_end,
      coalesce(app.task_travel_hours(t.id), 0) as b_travel,
      e.location_lat as b_lat,
      e.location_lng as b_lng
    from dedup d
    join tasks t on t.id = d.tid
    left join events e on e.id = t.event_id
    left join customers c on c.id = t.customer_id
    join task_types tt on tt.id = t.task_type_id
    where t.deleted_at is null
      and t.task_date between p_from and p_to
      -- משימה בלי אף שעה אינה יכולה להרכיב משמרת
      and coalesce(t.onsite_start_time, t.warehouse_start_time) is not null
  ),
  ordered as (
    select b.*,
           max(b.b_end) over (
             order by b.b_start, b.b_task
             rows between unbounded preceding and 1 preceding) as b_prev_end
    from base b
  ),
  flagged as (
    -- הפער נמדד עד סיום העבודה בשטח, בלי הנסיעה חזרה. אילו נמדד כולל
    -- נסיעה, עריכה של אזור גיאופנס הייתה מפצלת מחדש שבוע שכבר שולם.
    select o.*, case when o.b_prev_end is null or o.b_start - o.b_prev_end > v_gap
                     then 1 else 0 end as b_new
    from ordered o
  ),
  grouped as (
    select f.*, sum(f.b_new) over (
             order by f.b_start, f.b_task
             rows between unbounded preceding and current row) as b_grp
    from flagged f
  ),
  shifts as (
    select
      min(g.b_start) as s_start,
      max(g.b_end)   as s_core_end,
      -- הנסיעה חזרה מתווספת רק למשימה האחרונה במשמרת: בין שתי משימות
      -- שקרובות זו לזו אף אחד לא נוסע הביתה ובחזרה.
      (array_agg(g.b_travel order by g.b_end desc, g.b_task desc))[1] as s_travel,
      (array_agg(g.b_task   order by g.b_end desc, g.b_task desc))[1] as s_last,
      (array_agg(g.b_lat    order by g.b_end desc, g.b_task desc))[1] as s_last_lat,
      (array_agg(g.b_lng    order by g.b_end desc, g.b_task desc))[1] as s_last_lng,
      (array_agg(g.b_task   order by g.b_start, g.b_task))[1] as s_first,
      (array_agg(g.b_site   order by g.b_start, g.b_task))[1] as s_site,
      (array_agg(g.b_lat    order by g.b_start, g.b_task))[1] as s_first_lat,
      (array_agg(g.b_lng    order by g.b_start, g.b_task))[1] as s_first_lng,
      (array_agg(g.b_label  order by g.b_start, g.b_task))[1] as s_label,
      (array_agg(g.b_cust   order by g.b_start, g.b_task))[1] as s_cust,
      (array_agg(g.b_color  order by g.b_start, g.b_task))[1] as s_color,
      array_agg(g.b_task order by g.b_start, g.b_task) as s_ids,
      count(*) as s_count
    from grouped g
    group by g.b_grp
  )
  select
    p_profile_id,
    (s.s_start at time zone 'Asia/Jerusalem')::date,
    (row_number() over (
       partition by (s.s_start at time zone 'Asia/Jerusalem')::date
       order by s.s_start))::int,
    s.s_start,
    s.s_core_end + make_interval(mins => round(s.s_travel * 60)::int),
    round((extract(epoch from
      (s.s_core_end + make_interval(mins => round(s.s_travel * 60)::int) - s.s_start)
      ) / 3600.0)::numeric, 2),
    s.s_site,
    s.s_ids,
    s.s_first,
    s.s_last,
    s.s_first_lat, s.s_first_lng,
    s.s_last_lat,  s.s_last_lng,
    s.s_travel,
    case when s.s_count > 1 then s.s_label || ' +' || (s.s_count - 1)::text else s.s_label end,
    s.s_cust,
    s.s_color
  from shifts s
  order by s.s_start;
end $$;

-- המשמרת הרלוונטית לרגע נתון: זו שהחלון שלה מכיל אותו, ואם אין —
-- הקרובה ביותר. זו בדיוק הדרישה "מהמשמרת של אותו זמן, או הכי קרובה לה".
create or replace function app.shift_at(p_profile_id uuid, p_at timestamptz, p_grace interval)
returns app.planned_shift_row
language plpgsql stable security definer set search_path = public as $$
declare
  v_row  app.planned_shift_row;
  v_from date := (p_at at time zone 'Asia/Jerusalem')::date - 1;
  v_to   date := (p_at at time zone 'Asia/Jerusalem')::date + 1;
begin
  select s.* into v_row
    from app.planned_shifts(p_profile_id, v_from, v_to) s
   where p_at between s.shift_start - p_grace and s.shift_end + p_grace
   order by s.shift_start
   limit 1;
  if v_row.shift_start is not null then return v_row; end if;

  select s.* into v_row
    from app.planned_shifts(p_profile_id, v_from, v_to) s
   order by abs(extract(epoch from (s.shift_start - p_at)))
   limit 1;
  return v_row;
end $$;

-- ===== 4. מנוע השכר ========================================================
-- פונקציה טהורה, בדיוק כמו app.price_calc: אותו קוד שמחשב את הדוח מריץ גם
-- את התצוגה המקדימה במסך ההגדרות, ולכן אין דרך שהם ייתנו תשובות שונות.
--
-- vars:  hours · min_hours · overtime_enabled · hourly_rate · dow · week_hours_before
-- מחזיר: paid_hours · base_hours · overtime_hours · topup_hours · total · lines[]
--
-- סכום השורות שווה תמיד לסך הכול — תוספת נרשמת כשורה ולא כמכפלה על הסך.

create or replace function app.attendance_calc(p_config jsonb, p_vars jsonb)
returns jsonb language plpgsql immutable set search_path = public as $$
declare
  v_hours     numeric := coalesce((p_vars ->> 'hours')::numeric, 0);
  v_min       numeric := nullif(p_vars ->> 'min_hours', '')::numeric;
  v_ot        boolean := coalesce((p_vars ->> 'overtime_enabled')::boolean, true);
  v_rate      numeric := nullif(p_vars ->> 'hourly_rate', '')::numeric;
  v_dow       int     := coalesce((p_vars ->> 'dow')::int, -1);
  v_week_before numeric := coalesce((p_vars ->> 'week_hours_before')::numeric, 0);

  v_round_min  int  := coalesce((p_config #>> '{rounding,minutes}')::int, 0);
  v_round_mode text := coalesce(p_config #>> '{rounding,mode}', 'nearest');
  v_topup_ot   boolean := coalesce((p_config #>> '{top_up,counts_toward_overtime}')::boolean, false);

  v_table     jsonb;
  v_is_rest   boolean := false;
  v_base_h    numeric;
  v_base_rate numeric;
  v_tier      jsonb;
  v_tier_rate numeric;
  v_topup     numeric := 0;
  v_walk      numeric;
  v_take      numeric;
  v_remaining numeric;
  v_lines     jsonb := '[]'::jsonb;
  v_rate_hours numeric := 0;
  v_base_sum  numeric := 0;
  v_ot_sum    numeric := 0;
  v_idx       int;
  v_weekly    jsonb;
  v_wk_rate   numeric;
  v_wk_over   numeric;
begin
  -- עיגול
  if v_round_min > 0 then
    v_hours := case v_round_mode
      when 'up'   then ceil (v_hours * 60 / v_round_min) * v_round_min / 60.0
      when 'down' then floor(v_hours * 60 / v_round_min) * v_round_min / 60.0
      else             round(v_hours * 60 / v_round_min) * v_round_min / 60.0
    end;
  end if;
  v_hours := round(v_hours, 2);

  -- השלמה לשעות. מחושבת לפני מדרגות השעות הנוספות ומוחזקת מחוץ להן:
  -- אחרת "מובטחות 10 שעות, עבד 0" היה מייצר שעתיים פיקטיביות ב-150%.
  if v_min is not null and v_min > v_hours then
    v_topup := round(v_min - v_hours, 2);
  end if;

  v_walk := v_hours + case when v_topup_ot then v_topup else 0 end;

  if not v_ot then
    if v_walk > 0 then
      v_lines := v_lines || jsonb_build_object(
        'key', 'base', 'label', 'שעות רגילות', 'hours', v_walk, 'rate', 1.0,
        'amount', case when v_rate is not null then round(v_walk * v_rate, 2) end);
    end if;
    v_base_sum := v_walk;
    v_rate_hours := v_walk;
  else
    v_is_rest := coalesce(p_config #> '{rest_day,dow}', '[]'::jsonb) @> to_jsonb(v_dow);
    v_table   := case when v_is_rest then p_config -> 'rest_day' else p_config -> 'daily' end;
    v_base_h  := coalesce((v_table ->> 'base_hours')::numeric, 8);
    v_base_rate := coalesce((v_table ->> 'base_rate')::numeric, 1.0);

    v_remaining := v_walk;
    v_take := least(v_remaining, v_base_h);
    if v_take > 0 then
      v_lines := v_lines || jsonb_build_object(
        'key', 'base',
        'label', case when v_is_rest then 'שעות ביום מנוחה' else 'שעות רגילות' end,
        'hours', round(v_take, 2), 'rate', v_base_rate,
        'amount', case when v_rate is not null then round(v_take * v_base_rate * v_rate, 2) end);
      v_base_sum := round(v_take, 2);
      v_rate_hours := v_rate_hours + v_take * v_base_rate;
      v_remaining := v_remaining - v_take;
    end if;

    v_idx := 0;
    for v_tier in select * from jsonb_array_elements(coalesce(v_table -> 'tiers', '[]'::jsonb)) loop
      exit when v_remaining <= 0;
      v_idx := v_idx + 1;
      v_tier_rate := coalesce((v_tier ->> 'rate')::numeric, 1);
      v_take := case when v_tier ->> 'hours' is null
                     then v_remaining
                     else least(v_remaining, (v_tier ->> 'hours')::numeric) end;
      if v_take > 0 then
        v_lines := v_lines || jsonb_build_object(
          'key', 'ot' || v_idx,
          'label', 'שעות נוספות ' || round(v_tier_rate * 100)::text || '%',
          'hours', round(v_take, 2), 'rate', v_tier_rate,
          'amount', case when v_rate is not null then round(v_take * v_tier_rate * v_rate, 2) end);
        v_ot_sum := v_ot_sum + round(v_take, 2);
        v_rate_hours := v_rate_hours + v_take * v_tier_rate;
        v_remaining := v_remaining - v_take;
      end if;
    end loop;

    -- מדרגה אחרונה סגורה שלא כיסתה הכול: השארית נצברת בתעריף האחרון
    -- במקום להיעלם בשקט.
    if v_remaining > 0 then
      v_tier_rate := coalesce(v_tier_rate, v_base_rate);
      v_lines := v_lines || jsonb_build_object(
        'key', 'ot_rest', 'label', 'שעות נוספות ' || round(v_tier_rate * 100)::text || '%',
        'hours', round(v_remaining, 2), 'rate', v_tier_rate,
        'amount', case when v_rate is not null then round(v_remaining * v_tier_rate * v_rate, 2) end);
      v_ot_sum := v_ot_sum + round(v_remaining, 2);
      v_rate_hours := v_rate_hours + v_remaining * v_tier_rate;
    end if;

    -- תקרה שבועית: תוספת על מה שכבר חושב, כשורה נפרדת, ולכן היא לא
    -- מתנגשת עם המדרגה היומית שאותן שעות כבר קיבלו.
    v_weekly := coalesce(p_config -> 'weekly', '{}'::jsonb);
    if coalesce((v_weekly ->> 'enabled')::boolean, false) then
      v_wk_rate := coalesce((v_weekly ->> 'rate')::numeric, 1);
      v_wk_over := least(v_walk,
        greatest(0, v_week_before + v_walk - coalesce((v_weekly ->> 'base_hours')::numeric, 42)));
      if v_wk_over > 0 and v_wk_rate > 1 then
        v_lines := v_lines || jsonb_build_object(
          'key', 'weekly', 'label', 'תוספת שבועית',
          'hours', round(v_wk_over, 2), 'rate', round(v_wk_rate - 1, 2),
          'amount', case when v_rate is not null
                    then round(v_wk_over * (v_wk_rate - 1) * v_rate, 2) end);
        v_rate_hours := v_rate_hours + v_wk_over * (v_wk_rate - 1);
      end if;
    end if;
  end if;

  if v_topup > 0 and not v_topup_ot then
    v_lines := v_lines || jsonb_build_object(
      'key', 'top_up', 'label', 'השלמה לשעות', 'hours', v_topup, 'rate', 1.0,
      'amount', case when v_rate is not null then round(v_topup * v_rate, 2) end);
    v_rate_hours := v_rate_hours + v_topup;
  end if;

  return jsonb_build_object(
    'version',        1,
    'paid_hours',     round(v_hours + v_topup, 2),
    'worked_hours',   v_hours,
    'base_hours',     v_base_sum,
    'overtime_hours', v_ot_sum,
    'topup_hours',    v_topup,
    'is_rest_day',    v_is_rest,
    'hourly_rate',    v_rate,
    'rate_hours',     round(v_rate_hours, 2),
    'total',          case when v_rate is not null then round(v_rate_hours * v_rate, 2) end,
    'lines',          v_lines);
end $$;

-- ===== 5. הדוח ============================================================
-- security definer, כי הוא קורא את התעריף מ-worker_pay_settings שהקורא לרוב
-- אינו רשאי לקרוא. לכן הראייה נאכפת כאן במפורש, באותן שלוש זרועות של
-- הפוליסה: שלי · כולם עם המפתח · הסגל של הקבלן שלי.

create or replace function attendance_report(
  p_from date default null,
  p_to   date default null,
  p_profile_ids uuid[] default null,
  p_contractor_id uuid default null,
  p_only_flagged boolean default false)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_me         uuid    := app.profile_id();
  v_kind       text    := app.user_kind();
  v_admin      boolean := app.is_admin();
  v_all        boolean;
  v_portal     boolean;
  v_contractor uuid    := app.contractor_id();
  v_money_all  boolean;
  v_money_own  boolean;
  v_config     jsonb   := app.attendance_config('attendance.overtime');
  v_from       date    := coalesce(p_from, current_date - 30);
  v_to         date    := coalesce(p_to, current_date);
  v_rows       jsonb;
begin
  if v_me is null then
    return jsonb_build_object('rows', '[]'::jsonb, 'totals', '{}'::jsonb, 'can_see_pay', false);
  end if;
  v_all    := v_admin or (v_kind = 'staff' and app.has('attendance.view_all'));
  v_portal := v_kind = 'contractor_user' and app.has('portal.attendance');
  if not (v_all or v_portal or app.has('attendance.view_own')) then
    raise exception 'אין לך הרשאה לצפות בדוח נוכחות' using errcode = '42501';
  end if;
  v_money_all := v_admin
              or (v_kind = 'staff' and app.has('attendance.view_pay'))
              or (v_kind = 'contractor_user' and app.has('portal.attendance_pay'));
  v_money_own := app.has('attendance.view_own_pay');

  with visible as (
    select e.*, p.full_name, p.contractor_id as p_contractor,
           (e.profile_id = v_me) as is_mine
    from attendance_entries e
    join profiles p on p.id = e.profile_id
    where e.deleted_at is null
      and e.work_date between v_from and v_to
      and (
        e.profile_id = v_me
        or v_all
        or (v_portal and p.contractor_id is not null and p.contractor_id = v_contractor))
      and (p_profile_ids is null or e.profile_id = any(p_profile_ids))
      and (p_contractor_id is null or p.contractor_id = p_contractor_id)
      and (not p_only_flagged or coalesce(array_length(e.flags, 1), 0) > 0)
  ),
  -- הצבר השבועי נחוץ לתקרה השבועית, ולכן הוא מחושב לפני הרכבת כל שורה.
  weekly as (
    select v.*,
           coalesce(sum(v.actual_hours) over (
             partition by v.profile_id, date_trunc('week', v.work_date)
             order by v.clock_in_at
             rows between unbounded preceding and 1 preceding), 0) as week_before
    from visible v
  ),
  computed as (
    select w.*,
           app.attendance_calc(v_config, jsonb_build_object(
             'hours',             coalesce(w.actual_hours, 0),
             'min_hours',         s.min_hours_per_shift,
             'overtime_enabled',  coalesce(s.overtime_enabled, true),
             'hourly_rate',       s.hourly_rate,
             'dow',               extract(dow from w.work_date)::int,
             'week_hours_before', w.week_before)) as pay
    from weekly w
    left join worker_pay_settings s on s.profile_id = w.profile_id
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',             c.id,
    'profile_id',     c.profile_id,
    'full_name',      c.full_name,
    'contractor_id',  c.p_contractor,
    'work_date',      c.work_date,
    'seq',            c.seq,
    'shift_start',    c.shift_start,
    'shift_end',      c.shift_end,
    'planned_hours',  c.planned_hours,
    'work_site',      c.work_site,
    'task_ids',       to_jsonb(c.task_ids),
    'clock_in_at',    c.clock_in_at,
    'clock_out_at',   c.clock_out_at,
    'actual_hours',   c.actual_hours,
    'in_distance_m',  c.clock_in_distance_m,
    'out_distance_m', c.clock_out_distance_m,
    'raw_clock_in_at',  c.raw_clock_in_at,
    'raw_clock_out_at', c.raw_clock_out_at,
    'source',         c.source,
    'flags',          to_jsonb(c.flags),
    'employee_note',  c.employee_note,
    'manager_note',   c.manager_note,
    'edited_at',      c.edited_at,
    -- הכסף מוסתר ברמת השורה ולא ברמת השאילתה: אותה קריאה משרתת את המנהל
    -- שרואה סכומים ואת רכז המשמרות שרואה רק שעות.
    'pay', case when v_money_all or (c.is_mine and v_money_own)
                then c.pay
                else c.pay - array['hourly_rate', 'total', 'lines'] end)
    order by c.work_date desc, c.clock_in_at desc), '[]'::jsonb)
  into v_rows
  from computed c;

  return jsonb_build_object(
    'rows', v_rows,
    'can_see_pay', v_money_all,
    'totals', jsonb_build_object(
      'entries',        jsonb_array_length(v_rows),
      'actual_hours',   (select round(coalesce(sum((r ->> 'actual_hours')::numeric), 0), 2)
                         from jsonb_array_elements(v_rows) r),
      'paid_hours',     (select round(coalesce(sum((r #>> '{pay,paid_hours}')::numeric), 0), 2)
                         from jsonb_array_elements(v_rows) r),
      'overtime_hours', (select round(coalesce(sum((r #>> '{pay,overtime_hours}')::numeric), 0), 2)
                         from jsonb_array_elements(v_rows) r),
      'total',          case when v_money_all then
                        (select round(coalesce(sum((r #>> '{pay,total}')::numeric), 0), 2)
                         from jsonb_array_elements(v_rows) r) end));
end $$;

-- תצוגה מקדימה חיה למסך ההגדרות, על אותו מנוע שמחשב את הדוח.
create or replace function preview_attendance_pay(p_config jsonb, p_vars jsonb)
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  perform app.require('attendance.settings');
  return app.attendance_calc(
    coalesce(nullif(p_config, '{}'::jsonb), app.attendance_config('attendance.overtime')),
    p_vars);
end $$;

-- ===== 6. לוח המשמרות ======================================================

create or replace function my_shifts(p_from date, p_to date)
returns setof jsonb language plpgsql stable security definer set search_path = public as $$
begin
  perform app.require('attendance.view_schedule');
  return query select to_jsonb(s) from app.planned_shifts(app.profile_id(), p_from, p_to) s;
end $$;

create or replace function employee_shifts(p_profile_id uuid, p_from date, p_to date)
returns setof jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if p_profile_id = app.profile_id() then
    perform app.require('attendance.view_schedule');
  elsif app.user_kind() = 'contractor_user' then
    if not (app.has('portal.attendance') and app.is_my_contractor_staff(p_profile_id)) then
      raise exception 'אין לך הרשאה לצפות במשמרות של עובד זה' using errcode = '42501';
    end if;
  else
    perform app.require('attendance.view_all');
  end if;
  return query select to_jsonb(s) from app.planned_shifts(p_profile_id, p_from, p_to) s;
end $$;

-- ===== 7. השעון ============================================================
-- כאן יושבת החסימה. אין לעובד פוליסת INSERT על attendance_entries, ולכן זה
-- הנתיב היחיד שלו לכתוב — והוא עובר דרך כל הבדיקות שלמטה לפני שהוא כותב.

-- בדיקת המיקום, במקום אחד, כדי ששתי ההחתמות יאכפו בדיוק את אותו כלל.
-- מחזירה את המרחק במטרים, או NULL כשאין מה למדוד; זורקת כשהעובד מחוץ לרדיוס.
create or replace function app.check_clock_location(
  p_rules jsonb, p_lat double precision, p_lng double precision,
  p_accuracy numeric, p_site_lat double precision, p_site_lng double precision,
  out o_distance_m numeric, out o_flags text[])
language plpgsql stable set search_path = public as $$
declare
  v_required boolean := coalesce((p_rules ->> 'requires_location')::boolean, false);
  v_radius   numeric := coalesce((p_rules ->> 'location_radius_m')::numeric, 300);
  v_max_acc  numeric := coalesce((p_rules ->> 'max_accuracy_m')::numeric, 500);
begin
  o_flags := '{}';
  o_distance_m := null;

  if v_required and (p_lat is null or p_lng is null) then
    raise exception 'חובה לאשר שיתוף מיקום כדי להחתים שעון' using errcode = '42501';
  end if;

  if p_lat is null or p_lng is null then return; end if;

  -- לאתר אין קואורדינטות — זה פער נתונים במשרד ולא של העובד, ולכן
  -- ההחתמה מתקבלת ומסומנת במקום להיחסם.
  if p_site_lat is null or p_site_lng is null then
    if v_required then o_flags := o_flags || 'no_site_coords'::text; end if;
    return;
  end if;

  o_distance_m := round((app.haversine_km(p_lat, p_lng, p_site_lat, p_site_lng) * 1000)::numeric, 1);

  if v_required then
    -- דיוק ה-GPS מנוכה לפני ההשוואה: חוסמים רק כשהעובד *מוכח* מחוץ
    -- לרדיוס, ולא כשקריאה גסה מציבה אותו שם.
    if o_distance_m - coalesce(p_accuracy, 0) > v_radius then
      raise exception 'המיקום שלך מרוחק % מ׳ מהאתר (מותר עד % מ׳)',
        round(o_distance_m), round(v_radius) using errcode = '42501';
    end if;
    if coalesce(p_accuracy, 0) > v_max_acc then
      o_flags := o_flags || 'low_accuracy'::text;
    end if;
  end if;
end $$;

create or replace function attendance_clock_in(
  p_lat double precision default null,
  p_lng double precision default null,
  p_accuracy numeric default null,
  p_note text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_me    uuid := app.profile_id();
  v_rules jsonb;
  v_shift app.planned_shift_row;
  v_open  attendance_entries;
  v_grace interval;
  v_auto  int;
  v_site_lat double precision;
  v_site_lng double precision;
  v_dist  numeric;
  v_loc_flags text[];
  v_flags text[] := '{}';
  v_wh    jsonb;
  v_id    uuid;
  v_date  date;
  v_seq   int;
  v_prev  boolean;
begin
  perform app.require('attendance.clock');
  if v_me is null then raise exception 'משתמש לא מזוהה' using errcode = '42501'; end if;

  v_rules := app.clock_rules(v_me);
  if not coalesce((v_rules ->> 'clock_enabled')::boolean, true) then
    raise exception 'שעון הנוכחות מושבת עבורך' using errcode = '42501';
  end if;

  -- משמרת פתוחה שנשכחה נסגרת אוטומטית אחרי הסף, כדי שלא תחסום לנצח.
  v_auto := coalesce((v_rules ->> 'auto_close_after_hours')::int, 16);
  select * into v_open from attendance_entries
   where profile_id = v_me and clock_out_at is null and deleted_at is null;
  if v_open.id is not null then
    if now() - v_open.clock_in_at > make_interval(hours => v_auto) then
      v_prev := app.in_system_write();
      perform app.system_write(true);
      update attendance_entries
         set clock_out_at = clock_in_at + make_interval(hours => v_auto),
             flags = flags || 'auto_closed'::text
       where id = v_open.id;
      perform app.system_write(v_prev);
    else
      raise exception 'כבר נרשמה כניסה למשמרת פתוחה' using errcode = '42501';
    end if;
  end if;

  v_grace := make_interval(mins => coalesce((v_rules ->> 'early_grace_minutes')::int, 15));
  v_shift := app.shift_at(v_me, now(), v_grace);

  if v_shift.shift_start is null then
    if not coalesce((v_rules ->> 'allow_clock_without_shift')::boolean, false) then
      raise exception 'אין לך משמרת משובצת כרגע' using errcode = '42501';
    end if;
    v_flags := v_flags || 'no_shift'::text;
  elsif now() < v_shift.shift_start - v_grace
        and not coalesce((v_rules ->> 'allow_early_clock_in')::boolean, false) then
    -- התחלה מוקדמת: חסימה, אלא אם הותרה במפורש לעובד הזה.
    raise exception 'לא ניתן להתחיל משמרת לפני השעה %',
      to_char(v_shift.shift_start at time zone 'Asia/Jerusalem', 'HH24:MI')
      using errcode = '42501';
  end if;

  -- נקודת הייחוס: מי שיוצא מהמחסן נמדד מול המחסן, ומי שמגיע לאתר מול האתר.
  if v_shift.work_site = 'warehouse' then
    v_wh := app.attendance_config('attendance.clock') -> 'warehouse';
    v_site_lat := nullif(v_wh ->> 'lat', '')::double precision;
    v_site_lng := nullif(v_wh ->> 'lng', '')::double precision;
  else
    v_site_lat := v_shift.start_lat;
    v_site_lng := v_shift.start_lng;
  end if;

  select o_distance_m, o_flags into v_dist, v_loc_flags
    from app.check_clock_location(v_rules, p_lat, p_lng, p_accuracy, v_site_lat, v_site_lng);
  v_flags := v_flags || coalesce(v_loc_flags, '{}');

  v_date := coalesce((v_shift.shift_start at time zone 'Asia/Jerusalem')::date,
                     (now() at time zone 'Asia/Jerusalem')::date);
  select coalesce(max(seq), 0) + 1 into v_seq from attendance_entries
   where profile_id = v_me and work_date = v_date and deleted_at is null;

  insert into attendance_entries (
    profile_id, work_date, seq, shift_start, shift_end, planned_hours, work_site, task_ids,
    clock_in_at, raw_clock_in_at, clock_in_lat, clock_in_lng, clock_in_accuracy_m,
    clock_in_distance_m, flags, employee_note, created_by)
  values (
    v_me, v_date, v_seq, v_shift.shift_start, v_shift.shift_end, v_shift.planned_hours,
    v_shift.work_site, coalesce(v_shift.task_ids, '{}'),
    now(), now(), p_lat, p_lng, p_accuracy, v_dist, v_flags, nullif(p_note, ''), v_me)
  returning id into v_id;

  return jsonb_build_object('ok', true, 'entry_id', v_id, 'distance_m', v_dist,
                            'flags', to_jsonb(v_flags), 'shift', to_jsonb(v_shift));
end $$;

create or replace function attendance_clock_out(
  p_lat double precision default null,
  p_lng double precision default null,
  p_accuracy numeric default null,
  p_note text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_me    uuid := app.profile_id();
  v_rules jsonb;
  v_entry attendance_entries;
  v_shift app.planned_shift_row;
  v_site_lat double precision;
  v_site_lng double precision;
  v_dist  numeric;
  v_loc_flags text[];
  v_wh    jsonb;
  v_prev  boolean;
begin
  perform app.require('attendance.clock');
  if v_me is null then raise exception 'משתמש לא מזוהה' using errcode = '42501'; end if;
  v_rules := app.clock_rules(v_me);

  select * into v_entry from attendance_entries
   where profile_id = v_me and clock_out_at is null and deleted_at is null;
  if v_entry.id is null then
    raise exception 'לא נמצאה משמרת פתוחה להחתמת יציאה' using errcode = '42501';
  end if;

  -- היציאה נמדדת מול המשמרת של אותו זמן, או הקרובה לה. לרוב זו אותה משמרת
  -- של הכניסה; היא נשלפת מחדש כי עובד יכול לסיים במקום אחר.
  v_shift := app.shift_at(v_me, now(), make_interval(hours => 2));
  v_site_lat := v_shift.end_lat;
  v_site_lng := v_shift.end_lng;
  if v_site_lat is null and v_shift.work_site = 'warehouse' then
    v_wh := app.attendance_config('attendance.clock') -> 'warehouse';
    v_site_lat := nullif(v_wh ->> 'lat', '')::double precision;
    v_site_lng := nullif(v_wh ->> 'lng', '')::double precision;
  end if;

  select o_distance_m, o_flags into v_dist, v_loc_flags
    from app.check_clock_location(v_rules, p_lat, p_lng, p_accuracy, v_site_lat, v_site_lng);

  -- clock_in_at/clock_out_at רשומות ב-field_registry עם מפתח עריכה
  -- attendance.edit_entry, והטריגר הגנרי אינו מוותר גם ל-security definer.
  -- העטיפה כאן היא מה שמאפשר לשעון עצמו לסגור משמרת בלי לתת לעובד את
  -- מפתח התיקון. שמירה ושחזור ולא כיבוי עיוור — כמו ב-app.recalc_task_price.
  v_prev := app.in_system_write();
  perform app.system_write(true);
  update attendance_entries
     set clock_out_at = now(),
         raw_clock_out_at = now(),
         clock_out_lat = p_lat,
         clock_out_lng = p_lng,
         clock_out_accuracy_m = p_accuracy,
         clock_out_distance_m = v_dist,
         flags = flags || coalesce(v_loc_flags, '{}'),
         employee_note = coalesce(nullif(p_note, ''), employee_note)
   where id = v_entry.id;
  perform app.system_write(v_prev);

  return jsonb_build_object('ok', true, 'entry_id', v_entry.id, 'distance_m', v_dist);
end $$;

-- מה שדף השעון צריך כדי לצייר את עצמו: הרשומה הפתוחה, המשמרת של עכשיו,
-- והכללים שחלים על המשתמש (כדי לדעת אם לבקש מיקום לפני שמציגים כפתור).
create or replace function attendance_my_status()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_me    uuid := app.profile_id();
  v_open  attendance_entries;
  v_shift app.planned_shift_row;
  v_rules jsonb;
begin
  if v_me is null then return '{}'::jsonb; end if;
  perform app.require('attendance.view_own');
  v_rules := app.clock_rules(v_me);
  select * into v_open from attendance_entries
   where profile_id = v_me and clock_out_at is null and deleted_at is null;
  v_shift := app.shift_at(v_me, now(),
    make_interval(mins => coalesce((v_rules ->> 'early_grace_minutes')::int, 15)));
  return jsonb_build_object(
    'open_entry', case when v_open.id is not null then to_jsonb(v_open) end,
    'shift',      case when v_shift.shift_start is not null then to_jsonb(v_shift) end,
    'rules',      v_rules,
    'today',      (select coalesce(jsonb_agg(to_jsonb(e) order by e.clock_in_at), '[]'::jsonb)
                   from attendance_entries e
                   where e.profile_id = v_me and e.deleted_at is null
                     and e.work_date = (now() at time zone 'Asia/Jerusalem')::date));
end $$;

-- ===== 8. הנתיב הידני ======================================================
-- פתח המילוט. בדיקות המיקום וההתחלה המוקדמת אינן בגוף הפונקציות האלה — לא
-- מדולגות בתנאי — ולכן אין דגל שעובד יכול להעביר כדי להגיע לפטור.

create or replace function attendance_record_entry(
  p_profile_id uuid, p_clock_in timestamptz, p_clock_out timestamptz default null,
  p_note text default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_date date; v_seq int; v_id uuid;
begin
  perform app.require('attendance.manual_entry');
  if p_clock_out is not null and p_clock_out <= p_clock_in then
    raise exception 'שעת היציאה חייבת להיות אחרי שעת הכניסה';
  end if;
  v_date := (p_clock_in at time zone 'Asia/Jerusalem')::date;
  select coalesce(max(seq), 0) + 1 into v_seq from attendance_entries
   where profile_id = p_profile_id and work_date = v_date and deleted_at is null;
  insert into attendance_entries (
    profile_id, work_date, seq, clock_in_at, clock_out_at,
    source, flags, manager_note, created_by, edited_by, edited_at)
  values (
    p_profile_id, v_date, v_seq, p_clock_in, p_clock_out,
    'manual', array['manual'], nullif(p_note, ''), app.profile_id(), app.profile_id(), now())
  returning id into v_id;
  return v_id;
end $$;

create or replace function attendance_save_entry(
  p_id uuid, p_clock_in timestamptz, p_clock_out timestamptz default null,
  p_manager_note text default null)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform app.require('attendance.edit_entry');
  if p_clock_out is not null and p_clock_out <= p_clock_in then
    raise exception 'שעת היציאה חייבת להיות אחרי שעת הכניסה';
  end if;
  update attendance_entries
     set raw_clock_in_at  = coalesce(raw_clock_in_at, clock_in_at),
         raw_clock_out_at = coalesce(raw_clock_out_at, clock_out_at),
         clock_in_at  = p_clock_in,
         clock_out_at = p_clock_out,
         manager_note = coalesce(nullif(p_manager_note, ''), manager_note),
         flags = case when 'edited' = any(flags) then flags else flags || 'edited'::text end,
         edited_by = app.profile_id(),
         edited_at = now()
   where id = p_id and deleted_at is null;
end $$;

-- ===== 9. anon מחוץ למשטח החדש =============================================

do $$
declare fn text;
begin
  foreach fn in array array[
    'attendance_report(date, date, uuid[], uuid, boolean)',
    'preview_attendance_pay(jsonb, jsonb)',
    'my_shifts(date, date)',
    'employee_shifts(uuid, date, date)',
    'attendance_clock_in(double precision, double precision, numeric, text)',
    'attendance_clock_out(double precision, double precision, numeric, text)',
    'attendance_my_status()',
    'attendance_record_entry(uuid, timestamptz, timestamptz, text)',
    'attendance_save_entry(uuid, timestamptz, timestamptz, text)']
  loop
    execute format('revoke execute on function public.%s from anon, public', fn);
  end loop;
end $$;
