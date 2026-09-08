-- 0152: ההשלמה שמבוטלת על משמרת אחת
--
-- "מובטחות 6 שעות" היא הגדרה של *עובד* — `worker_pay_settings.min_hours_per_shift`
-- — והיא חלה על כל משמרת שלו. מה שלא היה אפשרי עד כאן הוא לומר "לא במשמרת
-- הזו": העובד ביקש לרדת מוקדם ואושר לו, הוזמן מראש לשעתיים ושני הצדדים ידעו
-- זאת, או שהמשמרת נגמרה בהסכמה לפני הזמן. הדרך היחידה הייתה לרוקן את ההגדרה
-- בכרטיס העובד לפני שמסתכלים בדוח ולהחזיר אותה אחרי — כלומר לזייף אותה לכל
-- שאר החודש, ולסמוך על מי שמזין שיזכור להחזיר.
--
-- ארבע החלטות עומדות מתחת:
--
-- 1. **דגל על המשמרת, ולא תקרה שנייה לצידה.** "השלמה ל-4 במקום ל-6" הוא כלל
--    עסקי שאיש לא ביקש, והוא היה דורש תשובה לשאלה מה קורה כשהוא גבוה מההגדרה
--    של העובד. הבקשה היא בינארית — במשמרת הזו אין השלמה — וכך גם השדה.
--
-- 2. **עמודה על `attendance_entries` ולא טבלת לוויין.** הנימוק של 0033 §2
--    עבור הבונוס אינו חל כאן: הוא הוציא *סכום* מהטבלה, כי `ae_select` מתירה
--    לכל מי שמחזיק `attendance.view_all` לקרוא כל שורה, ורכז משמרות אינו
--    רשאי לראות כסף. הדגל הזה אינו סכום — הוא נמצא באותה שכבה שבה כבר יושבים
--    `topup_hours` ו-`topup_target`, שהדוח מחזיר לכל מי שרואה שעות. אין כאן
--    מה להסתיר, ולכן אין סיבה לטבלה.
--
-- 3. **`attendance.manage_pay` ולא מפתח חדש.** זה בדיוק המפתח שההגדרה
--    ההפוכה יושבת עליו: `min_hours_per_shift` רשום ב-`field_registry` תחתיו
--    מאז 0019, ותיאורו הוא "תעריף לשעה, שעות נוספות והשלמה לשעות". מי שרשאי
--    לקבוע שיש השלמה רשאי לומר שהפעם אין. `attendance.edit_entry` — המפתח
--    התפעולי של מי שמתקן שעות — במפורש אינו זה, ולכן הכתיבה אינה פרמטר על
--    `attendance_save_entry` אלא RPC משלה, כמו הבונוס ב-0033 §5.
--
-- 4. **ביטול ידני ואיחור שאכל את ההשלמה הם שני דברים שונים בפלט.**
--    `topup_forfeited` נשאר מה שהוא היה מאז 0084 — "האיחור עבר את הסף" —
--    ולצידו `topup_waived` אומר "מישהו החליט". מסך שמראה לעובד למה לא קיבל
--    השלמה חייב להבחין ביניהם.

-- ===== 1. הדגל על המשמרת ==================================================
-- `not null default false`: אין מצב שלישי. false אינו "לא הוחלט" אלא "לך לפי
-- ההגדרה של העובד", וזו התשובה הנכונה לכל שורה שקיימת היום.

alter table attendance_entries
  add column topup_waived boolean not null default false;

comment on column attendance_entries.topup_waived is
  'ביטול ההשלמה לשעות במשמרת הזו בלבד. false = לך לפי min_hours_per_shift של '
  'העובד. נקבע ב-attendance_set_topup_waiver תחת attendance.manage_pay.';

-- הרישום הוא מה שסוגר את הנתיב הישיר. העובד עצמו כבר עצור:
-- `app.attendance_owner_edit_guard` (0027) מתירה למי שאין לו
-- `attendance.edit_entry` לגעת ב-`employee_note` בלבד. מי שהרישום הזה עוצר
-- הוא רכז המשמרות — הוא *כן* מחזיק `edit_entry`, ולכן `ae_update` והשומר של
-- 0027 מעבירים אותו, ובלי שורה כאן הוא היה מבטל השלמות דרך PostgREST בעמודה
-- שאיש לא הכריז עליה. `attendance_entries_field_perms` (0019) קוראת את
-- המרשם לפי שם הטבלה ועוצרת אותו על המפתח.
--
-- `default_can_edit=false` כמו כל שאר עמודות הנוכחות: המפתח הוא שמכריע, ולא
-- ברירת מחדל של מטריצת השדות.
select app.register_field('attendance', 'topup_waived', 'ביטול השלמה לשעות', 'attendance',
  'attendance_entries', 'topup_waived', false, true, false, 'attendance.manage_pay', 88);
select app.rebuild_secure_view('attendance_entries');

-- ===== 2. מנוע השכר =======================================================
--
-- זהה ל-0084 §2 פרט ל-`topup_waived`: משתנה נוסף, ענף אחד לפניו, ושני שדות
-- בפלט. הגוף נכתב במלואו כפי ש-0020 תכנן — הפונקציות יושבות לחוד מהסכמה
-- בדיוק כדי שמיגרציה כזו תחליף אותן בלי לגעת בה.
create or replace function app.attendance_calc(p_config jsonb, p_vars jsonb)
returns jsonb language plpgsql immutable set search_path = public as $$
declare
  v_hours     numeric := coalesce((p_vars ->> 'hours')::numeric, 0);
  v_min       numeric := nullif(p_vars ->> 'min_hours', '')::numeric;
  v_ot        boolean := coalesce((p_vars ->> 'overtime_enabled')::boolean, true);
  v_rate      numeric := nullif(p_vars ->> 'hourly_rate', '')::numeric;
  v_dow       int     := coalesce((p_vars ->> 'dow')::int, -1);
  v_week_before numeric := coalesce((p_vars ->> 'week_hours_before')::numeric, 0);
  v_bonus     numeric := round(coalesce(nullif(p_vars ->> 'bonus', '')::numeric, 0), 2);
  -- ‏0084: כסף שאינו שעות, משלושה מקורות שונים
  v_lead_bonus  numeric := round(coalesce(nullif(p_vars ->> 'lead_bonus', '')::numeric, 0), 2);
  v_shift_bonus numeric := round(coalesce(nullif(p_vars ->> 'shift_bonus', '')::numeric, 0), 2);
  v_money       numeric;
  -- ‏0084: האיחור, והסף שמעליו הוא מבטל את ההשלמה כליל
  v_late_min    numeric := greatest(0, coalesce(nullif(p_vars ->> 'late_minutes', '')::numeric, 0));
  v_forfeit     numeric := nullif(p_vars ->> 'late_forfeit_minutes', '')::numeric;
  -- ‏0152: החלטה ידנית על המשמרת הזו, שגוברת על ההגדרה של העובד
  v_waived      boolean := coalesce((p_vars ->> 'topup_waived')::boolean, false);
  v_min_target  numeric;

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
  --
  -- ‏0084: ההשלמה נמדדת מתחילת המשמרת המתוכננת, ולכן איחור מקטין אותה.
  -- מובטחות 6 שעות, המשמרת ב-10:00, העובד הגיע ב-10:15 — התקרה היא 5:45,
  -- כלומר האיחור עולה לו בדיוק את עצמו, פעם אחת. מעל סף שנקבע פר-עובד
  -- (`late_forfeit_minutes`) ההשלמה נשמטת כליל: זו החלטה של המשרד על
  -- איחור שאינו "כמה דקות", והיא מוגדרת בכרטיס העובד ולא בקוד.
  --
  -- ‏0152: ביטול ידני על המשמרת הזו קודם לשניהם ואינו מתחשב בהם. אין טעם
  -- לחשב איחור מתוך תקרה שכבר הוסרה, ו"בוטלה" אינו "נשמטה באיחור".
  if v_waived then
    v_min_target := null;
  else
    v_min_target := v_min;
    if v_min_target is not null and v_late_min > 0 then
      if v_forfeit is not null and v_late_min > v_forfeit then
        v_min_target := null;
      else
        v_min_target := greatest(0, v_min_target - v_late_min / 60.0);
      end if;
    end if;
  end if;

  if v_min_target is not null and v_min_target > v_hours then
    v_topup := round(v_min_target - v_hours, 2);
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

  -- אחרונים בפירוט, כי הם הדברים היחידים שם שאינם נגזרים משעות. שלוש שורות
  -- ולא אחת: הן נקבעות בשלושה מקומות שונים — בונוס פר-משמרת שמנהל מזין
  -- ידנית, תוספת ראש צוות פר-משימה, ותוספת קבועה למשמרת — ומי שקורא את
  -- התלוש צריך לדעת מאיפה כל שקל הגיע.
  if v_bonus <> 0 then
    v_lines := v_lines || jsonb_build_object(
      'key', 'bonus', 'label', 'בונוס למשמרת',
      'hours', null::numeric, 'rate', null::numeric,
      'amount', v_bonus);
  end if;
  if v_lead_bonus <> 0 then
    v_lines := v_lines || jsonb_build_object(
      'key', 'lead_bonus', 'label', 'תוספת ראש צוות',
      'hours', null::numeric, 'rate', null::numeric,
      'amount', v_lead_bonus);
  end if;
  if v_shift_bonus <> 0 then
    v_lines := v_lines || jsonb_build_object(
      'key', 'shift_bonus', 'label', 'תוספת קבועה למשמרת',
      'hours', null::numeric, 'rate', null::numeric,
      'amount', v_shift_bonus);
  end if;
  v_money := round(v_bonus + v_lead_bonus + v_shift_bonus, 2);

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
    -- `bonus` נשאר מה שהוא היה מאז 0033 — "כמה מהסכום אינו שעות" — ולכן הוא
    -- הסך של שלושת המקורות. הפירוט שלידו הוא מה שהתווסף.
    'bonus',          v_money,
    'bonus_manual',   v_bonus,
    'bonus_lead',     v_lead_bonus,
    'bonus_shift',    v_shift_bonus,
    -- מה שהמסך צריך כדי להסביר את ההשלמה ולא רק להציג אותה
    'late_minutes',   round(v_late_min),
    'topup_target',   v_min_target,
    -- ‏0152: "נשמטה באיחור" נשאר מה שהוא היה, ולכן ביטול ידני אינו נספר בו.
    -- לצידו `topup_waived` אומר שמישהו החליט, ו-`topup_min_hours` הוא מה
    -- שהיה מובטח לולא ההחלטה — בלעדיו המסך יודע שאין השלמה ולא כמה בוטל.
    'topup_forfeited', v_min is not null and not v_waived and v_min_target is null,
    'topup_waived',    v_waived,
    'topup_min_hours', v_min,
    'total',          case when v_rate is not null or v_money <> 0
                           then round(v_rate_hours * coalesce(v_rate, 0), 2) + v_money end,
    'lines',          v_lines);
end $$;

-- ===== 3. הדוח מעביר את הדגל למנוע ========================================
--
-- זהה ל-0084 §3 פרט לשורה אחת. החתימה אינה משתנה והטיפוס אינו גדל, ולכן
-- `create or replace` ובלי `cascade` — `attendance_report` שמעליה נשארת כפי
-- שהיא, כי `pay` הוא jsonb ושני השדות החדשים נוסעים בתוכו.
create or replace function app.attendance_pay_rows(
  p_from date,
  p_to   date,
  p_profile_ids   uuid[]  default null,
  p_contractor_id uuid    default null,
  p_only_flagged  boolean default false,
  p_status        text[]  default null,
  p_scope         text    default 'auto')
returns setof app.attendance_pay_row
language plpgsql stable security definer set search_path = public as $$
declare
  v_me         uuid    := app.profile_id();
  v_kind       text    := app.user_kind();
  v_admin      boolean := app.is_admin();
  v_all        boolean;
  v_portal     boolean;
  v_contractor uuid    := app.contractor_id();
  v_config     jsonb   := app.attendance_config('attendance.overtime');
  v_any        boolean := p_scope = 'all';
begin
  v_all    := v_admin or (v_kind = 'staff' and app.has('attendance.view_all'));
  -- 0075: מי שמקושר לקבלן, ולא מי שנולד כקבלן
  v_portal := v_contractor is not null and app.has('portal.attendance');

  return query
  with visible as (
    select e.*, p.full_name, p.contractor_id as p_contractor,
           (e.profile_id = v_me) as is_mine,
           coalesce(b.amount, 0) as bonus_amount,
           b.note as bonus_note
    from attendance_entries e
    join profiles p on p.id = e.profile_id
    left join attendance_entry_bonus b on b.entry_id = e.id
    where e.deleted_at is null
      and e.work_date between p_from and p_to
      and (
        v_any
        or e.profile_id = v_me
        or v_all
        or (v_portal and p.contractor_id is not null and p.contractor_id = v_contractor))
      and (p_profile_ids is null or e.profile_id = any(p_profile_ids))
      and (p_contractor_id is null or p.contractor_id = p_contractor_id)
      and (p_status is null or e.status = any(p_status))
      and (not p_only_flagged or coalesce(array_length(e.flags, 1), 0) > 0)
  ),
  -- הצבר השבועי סופר שעות מאושרות בלבד. דיווח שממתין לאישור אינו אמור
  -- לדחוף את המשמרת הבאה אל מעבר לתקרה השבועית לפני שהוכרע.
  weekly as (
    select v.*,
           coalesce(sum(case when v.status = 'approved' then v.actual_hours else 0 end) over (
             partition by v.profile_id, date_trunc('week', v.work_date)
             order by v.clock_in_at
             rows between unbounded preceding and 1 preceding), 0) as week_before
    from visible v
  ),
  computed as (
    select w.*,
           coalesce(s.overtime_enabled, true) as overtime_enabled,
           app.attendance_calc(v_config, jsonb_build_object(
             'hours',             coalesce(w.actual_hours, 0),
             'min_hours',         s.min_hours_per_shift,
             -- ‏0152: ההחלטה יושבת על המשמרת, ולכן היא נוסעת עם השורה ולא
             -- עם הגדרות העובד — בדיוק כמו הבונוס שמעליה.
             'topup_waived',      w.topup_waived,
             'overtime_enabled',  coalesce(s.overtime_enabled, true),
             'hourly_rate',       s.hourly_rate,
             'dow',               extract(dow from w.work_date)::int,
             'week_hours_before', w.week_before,
             -- הבונוס יושב על המשמרת ולא על הגדרות העובד: הוא פר-משמרת.
             'bonus',             w.bonus_amount,
             -- ‏0084: האיחור נמדד מול המשמרת המתוכננת שנצמדה להחתמה. בלי
             -- משמרת אין ממה לאחר, ולכן 0 ולא null — "לא איחר".
             'late_minutes',      case when w.shift_start is null then 0
                                       else greatest(0, round(extract(epoch
                                              from (w.clock_in_at - w.shift_start)) / 60)) end,
             'late_forfeit_minutes', s.late_topup_forfeit_minutes,
             -- תוספת ראש צוות היא פר-משימה, ולכן היא נספרת על המשימות של
             -- המשמרת עצמה ולא על המשמרת כיחידה.
             'lead_bonus',        round(coalesce(s.team_lead_bonus, 0) * (
                                    select count(*) from unnest(w.task_ids) tid
                                     where exists (select 1 from task_assignments a
                                                    where a.task_id = tid
                                                      and a.profile_id = w.profile_id
                                                      and a.role = 'team_lead')), 2),
             'shift_bonus',       coalesce(s.shift_bonus, 0))) as pay
    from weekly w
    left join worker_pay_settings s on s.profile_id = w.profile_id
  )
  select c.id, c.profile_id, c.full_name, c.p_contractor,
         c.work_date, c.seq, c.shift_start, c.shift_end,
         c.planned_hours, c.work_site, c.task_ids,
         c.clock_in_at, c.clock_out_at, c.actual_hours,
         c.clock_in_distance_m, c.clock_out_distance_m,
         c.raw_clock_in_at, c.raw_clock_out_at,
         c.source, c.status, c.reviewed_at, c.flags,
         c.employee_note, c.manager_note, c.edited_at,
         c.is_mine, c.overtime_enabled, c.bonus_amount, c.bonus_note, c.pay,
         c.clock_in_place, c.clock_out_place
  from computed c;
end $$;

-- ===== 4. הכתיבה =========================================================
--
-- RPC ולא פרמטר על `attendance_save_entry`, מאותו נימוק מילה במילה שכתוב
-- ב-0033 §5 עבור הבונוס: השמירה שם נשענת על `attendance.edit_entry`, ורכז
-- משמרות שמתקן שעה אינו מי שמחליט על השלמה. ארגומנט שם היה מחייב אחת משתיים
-- — התעלמות שקטה מהערך כשלקורא אין את המפתח, או זריקה שתשבור כל קורא קיים.
--
-- אין כאן בדיקת סטטוס. בונוס על רשומה שנדחתה הוא סכום שלא ישולם לעולם ולכן
-- הוא נחסם; ביטול השלמה הוא הכיוון ההפוך — הוא רק מוריד — ורשומה שנדחתה
-- ממילא אינה נספרת. חסימה כאן הייתה מונעת מהמנהל להכין את ההחלטה על דיווח
-- שעדיין ממתין, וזה בדיוק הרגע שבו הוא מכריע.
--
-- security definer, ולכן ה-RLS של `ae_update` — שמתירה רק ל-`edit_entry`
-- ולעובד עצמו — אינה עומדת בדרכו של חשב שכר שאין לו אף אחת מהן.
--
-- ו-`app.system_write` סביב הכתיבה מאותה סיבה בדיוק, כפי ש-0091 עשתה
-- באישור הדיווח: `app.attendance_owner_edit_guard` (0027) מתירה למי שאינו
-- מחזיק `attendance.edit_entry` לגעת ב-`employee_note` בלבד, וחשב השכר הוא
-- בדיוק מי שאינו מחזיק אותו. ההיתר צר ומוצהר — הכלל כבר נאכף בשורה הראשונה
-- של הפונקציה — והמצב הקודם מוחזר ולא נדרס, כדי שקריאה מתוך RPC אחר לא
-- תיסגר כאן באמצע.
create or replace function attendance_set_topup_waiver(
  p_id uuid, p_waived boolean)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_e     attendance_entries;
  v_flag  boolean := coalesce(p_waived, false);
  v_prev  boolean;
begin
  perform app.require('attendance.manage_pay');

  select * into v_e from attendance_entries where id = p_id and deleted_at is null;
  if v_e.id is null then
    raise exception 'רשומת הנוכחות לא נמצאה';
  end if;

  v_prev := app.in_system_write();
  perform app.system_write(true);
  update attendance_entries
     set topup_waived = v_flag
   where id = p_id and topup_waived is distinct from v_flag;
  perform app.system_write(v_prev);

  return jsonb_build_object('ok', true, 'entry_id', p_id, 'topup_waived', v_flag);
end $$;

revoke execute on function public.attendance_set_topup_waiver(uuid, boolean)
  from anon, public;
