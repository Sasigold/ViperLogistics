-- 0039: מנוע השכר מקבל נקודת כניסה אחת
--
-- הדשבורד עומד להציג עלות שכר, וזו הזדמנות לטעות אחת גדולה: לכתוב אגרגציה
-- שנייה שמכפילה את החישוב של `attendance_report`. ה-README מסביר למה זה
-- אסור — "מימוש שני היה הופך את הראשון לעותק שמתיישן" — והמקום שבו זה היה
-- נשבר הוא הצבר השבועי: `week_before` הוא חלון מסודר לפי `clock_in_at` שסוכם
-- שעות מאושרות בלבד, ולכן חישוב מחדש על קבוצת שורות **צרה יותר** משנה בשקט
-- כל מדרגת שעות נוספות שמתחתיו.
--
-- לכן שלוש ה-CTE-ים — visible / weekly / computed — עוברות כפי שהן לפונקציה
-- אחת, ו-`attendance_report` נשארת בדיוק מה שהיא הייתה: השער, מיסוך הכסף
-- והסיכומים. **אין כאן שינוי התנהגות.** הבדיקה לכך היא ש-04_attendance.sql
-- ממשיכה לעבור בלי שנגעו בה.
--
-- שני דברים שמכוונים במפורש ואינם תקלה:
--   • `p_status` מסנן בתוך `visible`, כלומר גם הצבר השבועי נבנה מהקבוצה
--     המסוננת. זו ההתנהגות של היום, והיא נשמרת מילה במילה. סינון ל-approved
--     בלבד אינו משנה כלום (ההצבר ממילא סופר רק אותן); סינון ל-pending היה
--     משנה. תיקון — אם בכלל — הוא שינוי נפרד עם נימוק משלו, לא כאן.
--   • הפונקציה היא `security definer` כי היא קוראת `worker_pay_settings`
--     שהקורא לרוב אינו רשאי לקרוא, ולכן היא **נשללת מ-authenticated**.
--     מיסוך הכסף לא זז לתוכה: הוא נשאר ב-`attendance_report`, שם הוא היום.

-- ===== 1. שורת השכר כטיפוס ==================================================
-- טיפוס מורכב ולא `returns table`, מאותה סיבה ש-`app.planned_shift_row` הוא
-- טיפוס (0019:157): `returns table` היה יוצר פרמטרי OUT בשמות `id`, `status`,
-- `flags` — שמות שקיימים גם כעמודות — וכל הפניה אליהם בגוף הייתה דו-משמעית.

drop type if exists app.attendance_pay_row cascade;
create type app.attendance_pay_row as (
  id                   uuid,
  profile_id           uuid,
  full_name            text,
  contractor_id        uuid,
  work_date            date,
  seq                  int,
  shift_start          timestamptz,
  shift_end            timestamptz,
  planned_hours        numeric,
  work_site            text,
  task_ids             uuid[],
  clock_in_at          timestamptz,
  clock_out_at         timestamptz,
  actual_hours         numeric,
  clock_in_distance_m  numeric,
  clock_out_distance_m numeric,
  raw_clock_in_at      timestamptz,
  raw_clock_out_at     timestamptz,
  source               text,
  status               text,
  reviewed_at          timestamptz,
  flags                text[],
  employee_note        text,
  manager_note         text,
  edited_at            timestamptz,
  is_mine              boolean,
  overtime_enabled     boolean,
  bonus_amount         numeric,
  bonus_note           text,
  pay                  jsonb
);

-- ===== 2. המנוע ============================================================
-- p_scope:
--   'auto' — בדיוק כלל הנראוּת ש-attendance_report מפעילה היום: שורה שלי, או
--            attendance.view_all, או מנהל קבלן עם portal.attendance על הסגל שלו.
--   'all'  — בלי סינון נראוּת כלל. מיועד לקורא definer שכבר עשה app.require
--            על מפתח משלו (כמו app.payroll_summary), ולא נגיש מבחוץ.

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
  v_portal := v_kind = 'contractor_user' and app.has('portal.attendance');

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
             'bonus',             w.bonus_amount)) as pay
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
         c.is_mine, c.overtime_enabled, c.bonus_amount, c.bonus_note, c.pay
  from computed c;
end $$;

-- הפונקציה רואה כל שורת שכר במערכת כשקוראים לה עם 'all'. היא כלי פנימי
-- לקוראי definer, ולא משטח שנגיש דרך PostgREST.
revoke execute on function app.attendance_pay_rows(date, date, uuid[], uuid, boolean, text[], text)
  from anon, authenticated, public;

-- ===== 3. הדוח, מעל המנוע ==================================================
-- זהה לגרסת 0033 בכל פרט שנראה מבחוץ: אותה חתימה, אותו שער הרשאות, אותו
-- מיסוך כסף פר-שורה, אותם סיכומים. מה שהשתנה הוא שהשורות מגיעות מבחוץ.

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
  v_portal := v_kind = 'contractor_user' and app.has('portal.attendance');
  if not (v_all or v_portal or app.has('attendance.view_own')) then
    raise exception 'אין לך הרשאה לצפות בדוח נוכחות' using errcode = '42501';
  end if;
  v_money_all := v_admin
              or (v_kind = 'staff' and app.has('attendance.view_pay'))
              or (v_kind = 'contractor_user' and app.has('portal.attendance_pay'));
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
