-- 0033: בונוס למשמרת
--
-- עד כאן השכר של משמרת היה מכפלה ותו לא: `app.attendance_calc` מכפילה את
-- השעות המשוקללות בתעריף השעתי, וזהו. כל מה שאינו נגזר מהשעון — פרמיה על
-- משמרת קשה, תמריץ על משמרת שאיש לא רצה לקחת, "תודה" של סוף חודש — לא היה
-- לו מקום, והדרך היחידה לשלם אותו הייתה להזין שעות פיקטיביות שמעוותות את
-- דוח השעות עצמו.
--
-- ארבע החלטות עומדות בבסיס הקובץ:
--
-- 1. **סכום ולא שעות.** שעה פיקטיבית נכנסת למדרגות השעות הנוספות ולתקרה
--    השבועית, כלומר בונוס של 100 ש״ח היה שווה יותר לעובד שממילא עשה שעות
--    נוספות באותו יום. הבונוס נרשם כשורה ב-`lines` ומצטרף לסך כפי שהוא —
--    בדיוק הכלל שכבר נוסח ב-0020 עבור התוספת השבועית: "תוספת נרשמת כשורה
--    ולא כמכפלה על הסך".
--
-- 2. **טבלת לוויין ולא עמודה על `attendance_entries`.** זה אותו נימוק מילה
--    במילה שכתוב ב-0019 §3 עבור `hourly_rate`, והוא חל כאן במלואו: RLS
--    ב-Postgres הוא ברמת שורה בלבד, `ae_select` מתירה לכל מי שמחזיק
--    `attendance.view_all` לקרוא כל שורת נוכחות, ו-Supabase מעניקה
--    `select` על טבלאות `public` ל-authenticated. עמודת `bonus` על הטבלה
--    הייתה נקראת ישירות דרך PostgREST בידי רכז משמרות שאינו רשאי לראות
--    שכר, ו-`attendance_entries_secure` לא הייתה עוזרת כי היא תצוגה נוספת
--    ולא החלפה של הטבלה. טבלה נפרדת נושאת פוליסה משלה, ובה התנאי הוא
--    הרשאת הכסף עצמה.
--
--    בונוס: `attendance_my_status` מחזיר `to_jsonb` של שורות נוכחות גולמיות
--    לשלושה שדות. עמודה על הטבלה הייתה נכנסת לשלושתם ומציגה את הסכום גם
--    לעובד שנשללה ממנו `attendance.view_own_pay`. טבלה נפרדת לא נוגעת בו.
--
-- 3. **מפתח הרשאה משלו.** `attendance.edit_entry` הוא מפתח תפעולי — הוא
--    ניתן לרכז משמרות שמתקן שעות ואינו רשאי לראות שכר בכלל. קביעת סכום כסף
--    אינה אותה יכולת. `attendance.manage_bonus` נגזר מ-`attendance.manage_pay`,
--    כי מי שממילא קובע תעריף שעתי אינו צריך מפתח נוסף.
--
-- 4. **הכתיבה עוברת ב-RPC בלבד**, כמו כל שאר המודול. לטבלה אין פוליסת
--    כתיבה כלל, ולכן אין נתיב PostgREST שעוקף את הבדיקות.

-- ===== 1. הטבלה ============================================================
-- `amount > 0` ולא `<> 0`: בונוס אפס הוא היעדר בונוס, ואז השורה נמחקת ולא
-- מתאפסת. סכום שלילי הוא ניכוי משכר — מושג נפרד עם דרישות משלו — ומי
-- שיזדקק לו יוסיף אותו כמפתח וכטבלה משלו, ולא יסתיר אותו מאחורי תווית
-- שכתוב עליה "בונוס".
--
-- `on delete cascade`: מחיקה קשה של רשומת נוכחות (attendance.delete מוחקת
-- רק רכה, אבל `ae_delete` קיימת) לא אמורה להשאיר בונוס יתום.
--
-- `id` נפרד ו-`entry_id` ייחודי, ולא `entry_id` כמפתח ראשי: `app.audit`
-- שולפת `row_id` מ-`new.id` ונופלת חזרה על task/event/profile/customer_id
-- בלבד, ו-`audit_log.row_id` הוא `not null` — טבלה בלי `id` הייתה מפילה כל
-- כתיבה על הפרת not null. ה-unique הוא מה ששומר על "בונוס אחד למשמרת" ועל
-- ה-`on conflict` ב-§5.

create table attendance_entry_bonus (
  id         uuid primary key default gen_random_uuid(),
  entry_id   uuid not null unique references attendance_entries(id) on delete cascade,
  amount     numeric(10,2) not null check (amount > 0),
  note       text,
  created_by uuid references profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table attendance_entry_bonus is
  'בונוס שקלי פר-משמרת. טבלה נפרדת ולא עמודה על attendance_entries, כי RLS '
  'שם אינו בודק הרשאת שכר — ראו את ההסבר בראש 0033.';
comment on column attendance_entry_bonus.amount is
  'הסכום בש״ח. נכנס לסך לתשלום של המשמרת כשורה נפרדת, ואינו משפיע על השעות, '
  'על מדרגות השעות הנוספות או על התקרה השבועית.';

create trigger attendance_entry_bonus_updated before update on attendance_entry_bonus
  for each row execute function app.set_updated_at();

create trigger attendance_entry_bonus_audit after insert or update or delete
  on attendance_entry_bonus for each row execute function app.audit();

-- ===== 2. RLS ==============================================================
-- שלוש זרועות הראייה הן בדיוק אלה של הכסף ב-attendance_report, ולא אלה של
-- הנוכחות: העובד את שלו אם יש לו attendance.view_own_pay, מנהל עם
-- attendance.view_pay את כולם, וקבלן את הסגל שלו עם portal.attendance_pay.
-- מי שרואה שעות בלי סכומים אינו עומד באף אחת מהן.
--
-- אין פוליסת כתיבה במכוון. §5 הוא הנתיב היחיד, והוא security definer שאוכף
-- את attendance.manage_bonus לפני שהוא כותב — אותה החלטה בדיוק שנוסחה
-- ב-0019 §2 עבור השעון.

alter table attendance_entry_bonus enable row level security;

create policy aeb_select on attendance_entry_bonus for select to authenticated using (
  (select app.is_admin())
  or exists (
    select 1 from attendance_entries e
     where e.id = entry_id
       and e.deleted_at is null
       and (
         (e.profile_id = (select app.profile_id())
          and (select app.has('attendance.view_own_pay')))
         or ((select app.user_kind()) = 'staff'
             and (select app.has('attendance.view_pay')))
         or ((select app.user_kind()) = 'contractor_user'
             and (select app.has('portal.attendance_pay'))
             and app.is_my_contractor_staff(e.profile_id)))));

-- ===== 3. ההרשאה ===========================================================
-- is_dangerous=true כמו attendance.manage_pay: המסך מסמן את המפתח, ובחירה
-- בו היא החלטה מודעת.
--
-- אין כאן שורת kind_permission_defaults ואין role_permissions: שרשרת
-- ה-implied_by עושה את העבודה. מי שמחזיק attendance.manage_pay מקבל אותו,
-- ו-contractor_worker חסום כי 0019 כתב לו דחייה מפורשת על המודול כולו
-- ב-p_close_modules — ודחייה מפורשת גוברת על השרשרת.

select app.register_permission('attendance.manage_bonus', 'attendance',
  'בונוס למשמרת', 'קביעת סכום בונוס על משמרת בודדת', 'action', false, true,
  array['staff']::user_kind[], 'attendance.manage_pay', 115);

-- grant_role_module מעניקה לפי המרשם *ברגע הקריאה*, ולכן היא נקראת שוב
-- ואינה נסמכת על 0021/0024 — אותו נימוק שכבר נוסח שם.
select app.grant_role_module('ops_manager', 'attendance');
select app.grant_role_module('hr', 'attendance');

-- שני השדות נרשמים במרשם לא בשביל ה-RLS — הפוליסה שלמעלה כבר סוגרת את
-- הטבלה כולה — אלא בשביל `app.redact_audit`: `audit_log_secure` מנקה מכל
-- תמונת לפני/אחרי כל עמודה שרשומה במרשם ושהקורא אינו רשאי לראות. בלי
-- השורות האלה הסכום היה גלוי ביומן הביקורת למי שיש לו `settings.audit_log`
-- גם בלי `attendance.view_pay`. אין כאן טריגר enforce_field_perms ואין
-- תצוגה מאובטחת, כי אין נתיב כתיבה או קריאה ישיר לטבלה מלכתחילה.
select app.register_field('attendance_bonus', 'amount', 'סכום הבונוס', 'attendance',
  'attendance_entry_bonus', 'amount', true, false, false, 'attendance.manage_bonus', 90);
select app.register_field('attendance_bonus', 'note', 'סיבת הבונוס', 'attendance',
  'attendance_entry_bonus', 'note', true, false, false, 'attendance.manage_bonus', 91);

-- ===== 4. מנוע השכר ========================================================
-- הצהרה מחדש במלואה, כפי ש-0020 תכנן: גופי הפונקציות יושבים שם לחוד
-- מהטבלה בדיוק כדי שמיגרציה כזו תוכל להחליף אותם בלי לגעת בסכמה.
--
-- שלושה שינויים מ-0020 §4, והשאר זהה:
--
-- * v_bonus נמסר כמשתנה ולא נקרא מהטבלה בתוך הפונקציה. היא נשארת טהורה,
--   ולכן התצוגה המקדימה במסך ההגדרות ממשיכה לרוץ על אותו קוד בדיוק.
--
-- * שורת הבונוס נוספת אחרונה, עם hours ו-rate שהם null מפורש ולא 1×הסכום:
--   היא אינה מכפלה, ומספר פיקטיבי בעמודת השעות היה מוצג במסך כ-"1:00 × 250".
--   ה-cast ל-numeric נדרש — null עירום ב-jsonb_build_object הוא מטיפוס
--   unknown ונופל.
--
-- * total: עד כה rate_hours × hourly_rate, ו-NULL כשאין תעריף. עכשיו הוא
--   מוגדר גם כשאין תעריף אבל יש בונוס, ואז הוא שווה לבונוס בדיוק. זו הצורה
--   היחידה ששומרת על ההבטחה "סכום השורות שווה לסך הכול", כי לשורות השעות
--   יש amount=null ו-sum מדלג עליהן. התנאי `or v_bonus <> 0` הוא מה ששומר
--   על ההבטחה השנייה: בלי תעריף ובלי בונוס עדיין מוחזר NULL ולא 0.
--
-- rate_hours במכוון אינו סופג את הבונוס: הוא שעות-שקולות, ולסכום שקלי קבוע
-- אין שעות שקולות.

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

  -- אחרון בפירוט, כי הוא הדבר היחיד שם שאינו נגזר משעות.
  if v_bonus <> 0 then
    v_lines := v_lines || jsonb_build_object(
      'key', 'bonus', 'label', 'בונוס למשמרת',
      'hours', null::numeric, 'rate', null::numeric,
      'amount', v_bonus);
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
    'bonus',          v_bonus,
    'total',          case when v_rate is not null or v_bonus <> 0
                           then round(v_rate_hours * coalesce(v_rate, 0), 2) + v_bonus end,
    'lines',          v_lines);
end $$;

-- ===== 5. נתיב הכתיבה ======================================================
-- RPC נפרד ולא ארגומנט על attendance_save_entry. שני נימוקים, וכל אחד מהם
-- עומד בפני עצמו:
--
-- * attendance_save_entry נשענת על attendance.edit_entry בלבד. ארגומנט בונוס
--   שם היה מחייב אחת משתיים — התעלמות שקטה מהערך כשלקורא אין manage_bonus,
--   או זריקה שתשבור כל קורא קיים. שקט על כסף אינו אופציה.
-- * 0024 §8 כבר תיעד את הצד השני: ארגומנט עם ברירת מחדל יוצר עומס-יתר,
--   והקריאה הקיימת בארבעה ארגומנטים הופכת לדו-משמעית.
--
-- security definer, ולכן הוא עוקף את היעדר פוליסת הכתיבה על הטבלה — שזו
-- בדיוק הנקודה: אין נתיב אחר.

create or replace function attendance_set_bonus(
  p_id uuid, p_bonus numeric, p_note text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_e   attendance_entries;
  v_amt numeric := round(coalesce(p_bonus, 0), 2);
begin
  perform app.require('attendance.manage_bonus');

  if v_amt < 0 then
    raise exception 'סכום הבונוס אינו יכול להיות שלילי';
  end if;
  -- תקרת שפיות. אין כאן כלל עסקי אלא הגנה מפני אפס מיותר בהקלדה, ולכן היא
  -- רחבה בכוונה ומנוסחת בעברית ולא כ-check על העמודה.
  if v_amt > 100000 then
    raise exception 'סכום הבונוס חורג מהטווח המותר (עד 100,000 ש״ח למשמרת)';
  end if;

  select * into v_e from attendance_entries where id = p_id and deleted_at is null;
  if v_e.id is null then
    raise exception 'רשומת הנוכחות לא נמצאה';
  end if;
  -- רשומה שנדחתה אינה משולמת כלל, ובונוס עליה היה סכום שלא ייספר לעולם.
  if v_e.status = 'rejected' then
    raise exception 'לא ניתן להוסיף בונוס לרשומה שנדחתה';
  end if;

  -- אפס הוא היעדר בונוס ולכן מחיקה, ולא שורה עם 0 שתיספר בכל הצטברות
  -- עתידית כאילו מישהו החליט עליה.
  if v_amt = 0 then
    delete from attendance_entry_bonus where entry_id = p_id;
    return jsonb_build_object('ok', true, 'entry_id', p_id, 'bonus', 0);
  end if;

  insert into attendance_entry_bonus (entry_id, amount, note, created_by)
  values (p_id, v_amt, nullif(btrim(p_note), ''), app.profile_id())
  on conflict (entry_id) do update
    set amount = excluded.amount,
        note   = excluded.note;

  return jsonb_build_object('ok', true, 'entry_id', p_id, 'bonus', v_amt);
end $$;

revoke execute on function public.attendance_set_bonus(uuid, numeric, text)
  from anon, public;

-- ===== 6. הדוח =============================================================
-- החתימה אינה משתנה, ולכן create or replace ולא drop — מה שתואר ב-0024 §8
-- נוגע להוספת ארגומנט בלבד. שאר הפונקציה זהה ל-0032.
--
-- ה-join לטבלת הבונוס נעשה כאן ולא נשען על ה-RLS שלה: הפונקציה היא security
-- definer ולכן היא רואה הכול, בדיוק כפי שהיא כבר קוראת את worker_pay_settings
-- שהקורא לרוב אינו רשאי לקרוא. ההסתרה נאכפת למטה, באותה שורה שמסתירה את
-- שאר הכסף.
--
-- הבונוס נכנס ל-pay.total, ולכן הוא נספר בסך החודשי בלי חיבור נוסף:
-- הסיכומים קוראים את total מתוך v_rows.

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
           (e.profile_id = v_me) as is_mine,
           coalesce(b.amount, 0) as bonus_amount,
           b.note as bonus_note
    from attendance_entries e
    join profiles p on p.id = e.profile_id
    left join attendance_entry_bonus b on b.entry_id = e.id
    where e.deleted_at is null
      and e.work_date between v_from and v_to
      and (
        e.profile_id = v_me
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
             'bonus',             w.bonus_amount)) as pay
    from weekly w
    left join worker_pay_settings s on s.profile_id = w.profile_id
  )
  -- pay מחושב גם לשורה שממתינה לאישור, כי המאשר צריך לדעת מה הוא מאשר.
  -- מה שממתין אינו נספר הוא הסיכומים שלמטה, ולא התצוגה של השורה עצמה.
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
    'status',         c.status,
    'reviewed_at',    c.reviewed_at,
    'flags',          to_jsonb(c.flags),
    'employee_note',  c.employee_note,
    'manager_note',   c.manager_note,
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
  from computed c;

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
