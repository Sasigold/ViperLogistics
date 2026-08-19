-- 0084: מה שמרכיב את התלוש — איחור, תוספות, ומיקום שנרשם במילים
--
-- שש בקשות שכולן נוגעות באותו מקום: מה נספר לעובד על משמרת, ומי קובע את זה.
--
--   * ההשלמה לשעות התעלמה מאיחור. "מובטחות 6 שעות" שילמו 6 שעות גם למי
--     שהגיע ברבע השעה השנייה, ולכן היא תמרצה בדיוק את מה שהיא נועדה לכסות.
--   * ולצידה: איחור שאינו "כמה דקות" צריך לבטל אותה כליל, בסף שנקבע פר-עובד.
--   * שתי תוספות שלא היו: סכום לכל משימה שבה העובד רשום כראש צוות, וסכום
--     קבוע לכל משמרת.
--   * ודיווח ידני של משמרת שלא הוחתמה צריך לשאת מיקום כניסה ויציאה במילים —
--     אין שם GPS לאמת מולו, והמלל הוא מה שהמנהל מאשר לפיו.
--
-- שלוש ההחלטות שמתחת:
--
--   * הכסף שאינו שעות נשאר מחוץ למדרגות השעות הנוספות ומחוץ לתקרה השבועית,
--     כמו שהבונוס של 0033 כבר עשה. תוספת של 100 ש״ח אינה שווה יותר לעובד
--     שממילא עשה שעות נוספות באותו יום.
--   * ההשלמה נמדדת מתחילת המשמרת *המתוכננת*. בלי נקודת ייחוס כזו "איחור"
--     אינו מוגדר, ולכן מי שאין לו משמרת משובצת פשוט אינו מאחר.
--   * המיקום במילים הוא שדה ברישום השדות (`field_registry`) ולא עמודה
--     חופשית, וזו הדרך שבה המנהל מקבל אותו לעריכה בלי RPC נוסף.

-- ===== 1. שלוש הגדרות חדשות בכרטיס העובד ==================================

alter table worker_pay_settings
  add column team_lead_bonus numeric(10,2)
    check (team_lead_bonus is null or team_lead_bonus >= 0),
  add column shift_bonus numeric(10,2)
    check (shift_bonus is null or shift_bonus >= 0),
  add column late_topup_forfeit_minutes int
    check (late_topup_forfeit_minutes is null or late_topup_forfeit_minutes >= 0);

comment on column worker_pay_settings.team_lead_bonus is
  'תוספת בשקלים לכל משימה במשמרת שבה העובד רשום כראש צוות. NULL = אין.';
comment on column worker_pay_settings.shift_bonus is
  'תוספת קבועה בשקלים לכל משמרת של העובד. NULL = אין.';
comment on column worker_pay_settings.late_topup_forfeit_minutes is
  'איחור מעל כך דקות מבטל את ההשלמה לשעות כליל. NULL = ההשלמה רק מתקצרת '
  'באיחור ואינה נשמטת.';

-- ===== 2. מנוע השכר: האיחור מקצר את ההשלמה, והתוספות הן שורות ============
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
  v_min_target := v_min;
  if v_min_target is not null and v_late_min > 0 then
    if v_forfeit is not null and v_late_min > v_forfeit then
      v_min_target := null;
    else
      v_min_target := greatest(0, v_min_target - v_late_min / 60.0);
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
    'topup_forfeited', v_min is not null and v_min_target is null,
    'total',          case when v_rate is not null or v_money <> 0
                           then round(v_rate_hours * coalesce(v_rate, 0), 2) + v_money end,
    'lines',          v_lines);
end $$;

-- ===== 3. המנוע מקבל את הנתונים: איחור, ראשות צוות ותוספת קבועה ==========
--
-- הטיפוס גדל בשתי עמודות כדי שהמיקום במילים יגיע עד הדוח. `cascade` מפיל
-- את הפונקציות שנשענות עליו, ולכן שתיהן נכתבות מחדש כאן מיד אחריו.
alter type app.attendance_pay_row add attribute clock_in_place  text cascade;
alter type app.attendance_pay_row add attribute clock_out_place text cascade;

--
-- זהה ל-0075 פרט לארבעת השדות החדשים שנכנסים ל-`attendance_calc`. שלושתם
-- נשלפים ממקום שכבר יושב על השורה: `shift_start` נצמד להחתמה בזמן אמת,
-- ו-`task_ids` הן המשימות שהרכיבו אותה — ולכן "כמה פעמים הוא היה ראש צוות"
-- אינה שאלה על היום אלא על המשמרת הזו.
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

-- ===== 4. מיקום כניסה ויציאה במילים ========================================
--
-- דיווח ידני הוא בדיוק המקרה שבו אין קואורדינטות: השעון לא עבד, ולכן אין
-- מה לאמת מולו. מה שיש הוא מה שהעובד כותב, ומה שהמנהל מאשר לפיו — ולכן שני
-- השדות חובה בדיווח, וניתנים לעריכה בידי מי שמתקן את הרשומה.

alter table attendance_entries
  add column clock_in_place  text,
  add column clock_out_place text;

comment on column attendance_entries.clock_in_place is
  'מיקום הכניסה במילים. נרשם בדיווח ידני, שבו אין GPS לאמת מולו.';
comment on column attendance_entries.clock_out_place is
  'מיקום היציאה במילים. ראו clock_in_place.';

-- הרישום הוא מה שנותן למנהל לערוך אותם: הטריגר הגנרי `enforce_field_perms`
-- קורא את הטבלה הזו לפי שם הטבלה, ולכן שדה שאינו רשום בה אינו ניתן לעריכה
-- דרך אף נתיב.
select app.register_field('attendance', 'clock_in_place', 'מיקום כניסה', 'attendance',
  'attendance_entries', 'clock_in_place', false, true, true, 'attendance.edit_entry', 60);
select app.register_field('attendance', 'clock_out_place', 'מיקום יציאה', 'attendance',
  'attendance_entries', 'clock_out_place', false, true, true, 'attendance.edit_entry', 61);
select app.rebuild_secure_view('attendance_entries');

-- החתימה גדלה בשני פרמטרים, והישנה נמחקת ולא נשארת לצידה: שתיהן היו נקראות
-- באותם שלושה ארגומנטים, וזו בדיוק העמימות ש-0024 §8 הזהירה מפניה.
drop function if exists attendance_submit_entry(timestamptz, timestamptz, text);
create or replace function attendance_submit_entry(
  p_clock_in timestamptz,
  p_clock_out timestamptz,
  p_note text default null,
  p_in_place text default null,
  p_out_place text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_me    uuid := app.profile_id();
  v_rules jsonb;
  v_self  jsonb;
  v_max_h numeric;
  v_back  int;
  v_hours numeric;
  v_shift app.planned_shift_row;
  v_clash uuid;
  v_flags text[] := array['manual', 'self_reported'];
  v_date  date;
  v_seq   int;
  v_id    uuid;
  v_name  text;
  r       record;
begin
  perform app.require('attendance.submit_entry');
  if v_me is null then raise exception 'משתמש לא מזוהה' using errcode = '42501'; end if;

  v_rules := app.clock_rules(v_me);
  v_self  := coalesce(v_rules -> 'self_entry', '{}'::jsonb);
  if not coalesce((v_self ->> 'enabled')::boolean, true) then
    raise exception 'דיווח משמרת ידני אינו מופעל במערכת' using errcode = '42501';
  end if;

  if p_clock_in is null then
    raise exception 'חובה להזין שעת התחלה';
  end if;
  if p_clock_out is null then
    raise exception 'חובה להזין שעת סיום — דיווח ידני מתאר משמרת שהסתיימה';
  end if;
  if p_clock_out <= p_clock_in then
    raise exception 'שעת הסיום חייבת להיות אחרי שעת ההתחלה';
  end if;
  -- דקות ספורות של חסד, כדי שעובד שמדווח ברגע שירד מהמשאית לא ייחסם על
  -- הפרש שעונים בין הטלפון לשרת.
  if p_clock_out > now() + interval '5 minutes' then
    raise exception 'לא ניתן לדווח על משמרת שטרם הסתיימה';
  end if;

  v_hours := round((extract(epoch from (p_clock_out - p_clock_in)) / 3600.0)::numeric, 2);
  v_max_h := coalesce((v_self ->> 'max_hours')::numeric, 16);
  if v_hours > v_max_h then
    raise exception 'משמרת מדווחת אינה יכולה לעלות על % שעות', round(v_max_h);
  end if;

  v_back := coalesce((v_self ->> 'max_backdate_days')::int, 14);
  if p_clock_in < now() - make_interval(days => v_back) then
    raise exception 'ניתן לדווח רק על % הימים האחרונים. לתאריך מוקדם יותר יש לפנות למנהל', v_back;
  end if;

  v_clash := app.attendance_overlap(v_me, p_clock_in, p_clock_out);
  if v_clash is not null then
    raise exception 'כבר קיימת רשומת נוכחות שחופפת לשעות האלה';
  end if;

  -- המשמרת המתוכננת נצמדת רק אם הדיווח באמת נופל בתוכה (בתוספת חלון של
  -- שעתיים לכל צד). app.shift_at הייתה מחזירה גם את "הקרובה ביותר", ודיווח
  -- על יום שלא היה בו שיבוץ היה נתלה במשמרת של יום אחר.
  v_date := (p_clock_in at time zone 'Asia/Jerusalem')::date;
  select s.* into v_shift
    from app.planned_shifts(v_me, v_date - 1, v_date + 1) s
   where p_clock_in between s.shift_start - interval '2 hours'
                        and s.shift_end   + interval '2 hours'
   order by abs(extract(epoch from (s.shift_start - p_clock_in)))
   limit 1;

  if v_shift.shift_start is null then
    v_flags := v_flags || 'no_shift'::text;
  else
    v_date := (v_shift.shift_start at time zone 'Asia/Jerusalem')::date;
  end if;

  -- ‏0084: דיווח ידני אינו נושא מיקום GPS, ולכן המלל הוא כל מה שיש למנהל
  -- לאשר לפיו. חובה, ולא "רצוי": שדה ריק הופך את האישור לחתימה על כלום.
  if coalesce(nullif(btrim(p_in_place), ''), '') = ''
     or coalesce(nullif(btrim(p_out_place), ''), '') = '' then
    raise exception 'יש לציין מיקום כניסה ומיקום יציאה';
  end if;

  select coalesce(max(seq), 0) + 1 into v_seq from attendance_entries
   where profile_id = v_me and work_date = v_date and deleted_at is null;

  insert into attendance_entries (
    profile_id, work_date, seq, shift_start, shift_end, planned_hours, work_site, task_ids,
    clock_in_at, clock_out_at, source, status, flags, employee_note, created_by,
    clock_in_place, clock_out_place)
  values (
    v_me, v_date, v_seq, v_shift.shift_start, v_shift.shift_end, v_shift.planned_hours,
    v_shift.work_site, coalesce(v_shift.task_ids, '{}'),
    p_clock_in, p_clock_out, 'manual', 'pending', v_flags, nullif(p_note, ''), v_me,
    nullif(btrim(p_in_place), ''), nullif(btrim(p_out_place), ''))
  returning id into v_id;

  select full_name into v_name from profiles where id = v_me;
  for r in select t.id from app.profiles_with('attendance.approve_entry') as t(id) loop
    perform app.notify(r.id, 'attendance_submitted', 'דיווח נוכחות ממתין לאישור',
      v_name || ' דיווח משמרת ב-' || to_char(v_date, 'DD/MM/YYYY') || ' (' ||
      to_char(p_clock_in at time zone 'Asia/Jerusalem', 'HH24:MI') || '–' ||
      to_char(p_clock_out at time zone 'Asia/Jerusalem', 'HH24:MI') || ')',
      'attendance_entry', v_id);
  end loop;

  return jsonb_build_object('ok', true, 'entry_id', v_id, 'status', 'pending',
                            'work_date', v_date, 'hours', v_hours,
                            'flags', to_jsonb(v_flags));
end $$;

revoke execute on function public.attendance_submit_entry(timestamptz, timestamptz, text, text, text)
  from anon, public;

-- ===== 5. המנהל מתקן הכול, ובכלל זה את המיקום ==============================
--
-- ‏`attendance_save_entry` תיקנה שעות והערה בלבד. ההשלמה, השעות הנוספות
-- והסכומים נגזרים מהשעות ומהגדרות העובד ולכן הם מתעדכנים מאליהם ברגע
-- שהשעות מתוקנות; מה שלא היה ניתן לתיקון הוא המיקום, וזה מה שנוסף כאן.
drop function if exists attendance_save_entry(uuid, timestamptz, timestamptz, text);

create or replace function attendance_save_entry(
  p_id uuid, p_clock_in timestamptz, p_clock_out timestamptz default null,
  p_manager_note text default null,
  p_in_place text default null, p_out_place text default null)
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
         -- ריק אינו "אל תיגע" אלא "מחק": המנהל שמנקה שדה מיקום מתכוון לכך.
         clock_in_place  = nullif(btrim(coalesce(p_in_place, clock_in_place)), ''),
         clock_out_place = nullif(btrim(coalesce(p_out_place, clock_out_place)), ''),
         flags = case when 'edited' = any(flags) then flags else flags || 'edited'::text end,
         edited_by = app.profile_id(),
         edited_at = now()
   where id = p_id and deleted_at is null;
end $$;

revoke execute on function public.attendance_save_entry(uuid, timestamptz, timestamptz, text, text, text)
  from anon, public;

-- ===== 6. הדוח מעביר את המיקום הלאה ========================================
--
-- זהה ל-0075 פרט לשתי השורות של המיקום. הוא נכתב מחדש ממילא, כי ה-`cascade`
-- שבסעיף 3 הפיל אותו יחד עם הטיפוס.
create or replace function attendance_report(
  p_from date default null,
  p_to   date default null,
  p_profile_ids uuid[] default null,
  p_contractor_id uuid default null,
  p_only_flagged boolean default false,
  p_status text[] default null)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_me         uuid    := app.profile_id();
  v_kind       text    := app.user_kind();
  v_admin      boolean := app.is_admin();
  v_all        boolean;
  v_portal     boolean;
  v_money_all  boolean;
  v_money_own  boolean;
  v_from       date    := coalesce(p_from, current_date - 30);
  v_to         date    := coalesce(p_to, current_date);
  v_rows       jsonb;
begin
  if v_me is null then
    return jsonb_build_object('rows', '[]'::jsonb, 'totals', '{}'::jsonb, 'can_see_pay', false);
  end if;
  v_all    := v_admin or (v_kind = 'staff' and app.has('attendance.view_all'));
  -- 0075: מי שמקושר לקבלן, ולא מי שנולד כקבלן
  v_portal := app.contractor_id() is not null and app.has('portal.attendance');
  if not (v_all or v_portal or app.has('attendance.view_own')) then
    raise exception 'אין לך הרשאה לצפות בדוח נוכחות' using errcode = '42501';
  end if;
  v_money_all := v_admin
              or (v_kind = 'staff' and app.has('attendance.view_pay'))
              or (app.contractor_id() is not null and app.has('portal.attendance_pay'));
  v_money_own := app.has('attendance.view_own_pay');

  -- pay מחושב גם לשורה שממתינה לאישור, כי המאשר צריך לדעת מה הוא מאשר.
  -- מה שממתין אינו נספר הוא הסיכומים שלמטה, ולא התצוגה של השורה עצמה.
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',             c.id,
    'profile_id',     c.profile_id,
    'full_name',      c.full_name,
    'contractor_id',  c.contractor_id,
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
    'status',         c.status,
    'reviewed_at',    c.reviewed_at,
    'flags',          to_jsonb(c.flags),
    'employee_note',  c.employee_note,
    'manager_note',   c.manager_note,
    -- ‏0084: המיקום במילים מגיע עד הדוח, כי שם המנהל מאשר את הדיווח הידני
    'clock_in_place',  c.clock_in_place,
    'clock_out_place', c.clock_out_place,
    'edited_at',      c.edited_at,
    -- לא כסף אלא כלל: אם השעות הנוספות חלות על העובד הזה בכלל. אין כאן מה
    -- להסתיר — הוא נגזר מאותה הגדרה שהעובד רואה בכרטיס שלו.
    'overtime_enabled', c.overtime_enabled,
    -- הנימוק הולך עם הסכום: מי שאינו רואה כמה, אינו רואה גם למה. הוא מגודר
    -- בתנאי הכסף ולא נמצא ליד manager_note שכולם רואים.
    'bonus_note',     case when v_money_all or (c.is_mine and v_money_own)
                           then c.bonus_note end,
    -- הכסף מוסתר ברמת השורה ולא ברמת השאילתה: אותה קריאה משרתת את המנהל
    -- שרואה סכומים ואת רכז המשמרות שרואה רק שעות. bonus מצטרף לרשימה כי
    -- הוא סכום בשקלים ולא נתון תפעולי.
    'pay', case when v_money_all or (c.is_mine and v_money_own)
                then c.pay
                else c.pay - array['hourly_rate', 'total', 'lines', 'bonus'] end)
    order by c.work_date desc, c.clock_in_at desc), '[]'::jsonb)
  into v_rows
  from app.attendance_pay_rows(
         v_from, v_to, p_profile_ids, p_contractor_id, p_only_flagged, p_status, 'auto') c;

  return jsonb_build_object(
    'rows', v_rows,
    'can_see_pay', v_money_all,
    'totals', jsonb_build_object(
      'entries',        jsonb_array_length(v_rows),
      'pending',        (select count(*) from jsonb_array_elements(v_rows) r
                          where r ->> 'status' = 'pending'),
      'pending_hours',  (select round(coalesce(sum((r ->> 'actual_hours')::numeric), 0), 2)
                          from jsonb_array_elements(v_rows) r
                         where r ->> 'status' = 'pending'),
      'actual_hours',   (select round(coalesce(sum((r ->> 'actual_hours')::numeric), 0), 2)
                          from jsonb_array_elements(v_rows) r
                         where r ->> 'status' = 'approved'),
      'paid_hours',     (select round(coalesce(sum((r #>> '{pay,paid_hours}')::numeric), 0), 2)
                          from jsonb_array_elements(v_rows) r
                         where r ->> 'status' = 'approved'),
      'overtime_hours', (select round(coalesce(sum((r #>> '{pay,overtime_hours}')::numeric), 0), 2)
                          from jsonb_array_elements(v_rows) r
                         where r ->> 'status' = 'approved'),
      -- סיכום משלו ולא רק בלוע ב-total: המסך והייצוא צריכים להראות כמה מהסכום
      -- אינו שעות, בלי לגזור אותו מהפרש. הוא *כלול* ב-total ואינו נוסף עליו.
      'bonus',          case when v_money_all or v_money_own then
                        (select round(coalesce(sum((r #>> '{pay,bonus}')::numeric), 0), 2)
                          from jsonb_array_elements(v_rows) r
                         where r ->> 'status' = 'approved') end,
      'total',          case when v_money_all or v_money_own then
                        (select round(coalesce(sum((r #>> '{pay,total}')::numeric), 0), 2)
                          from jsonb_array_elements(v_rows) r
                         where r ->> 'status' = 'approved') end));
end $$;

revoke execute on function public.attendance_report(date, date, uuid[], uuid, boolean, text[])
  from anon, public;
