-- 0027: מה שסקירת המערכת מצאה
--
-- חמישה תיקונים שאין ביניהם קשר מלבד זה שנמצאו באותה סקירה. שניים מהם
-- (portal.attendance, סיכום השכר) נתפסו על ידי חבילת הבדיקות עצמה ברגע
-- שהיא הפסיקה להיות תלויה בשעה שבה היא רצה.

-- ===== 1. רשומת הנוכחות: מה שהעובד רשאי לגעת בו =====================
--
-- ההערה ב-0019 מתארת את הכוונה במדויק: "היא מתירה את השורה, והטריגר מצמצם
-- אותה לעמודה אחת (employee_note)". זה לא מה שקרה בפועל.
--
-- ae_update מתירה לעובד לעדכן את השורה של עצמו, וההגנה ברמת העמודה היא
-- app.enforce_field_perms() — שקורא את field_registry לפי שם הטבלה. שם
-- רשומות שש עמודות בלבד: clock_in_at, clock_out_at, manager_note (0019)
-- ו-status, reviewed_by, reviewed_at (0024). כל השאר לא היה מוגן כלל:
-- clock_in_lat/lng/accuracy_m/distance_m ומקביליהן ב-clock_out, וכן flags,
-- source, raw_clock_in_at, raw_clock_out_at, work_date, seq, shift_start,
-- shift_end, planned_hours, work_site, task_ids, created_by, edited_by.
--
-- כלומר עובד יכול היה לשלוח PATCH ישיר ל-PostgREST על השורה של עצמו,
-- למחוק דגל low_accuracy או לשכתב את clock_in_distance_m ואת הקואורדינטות,
-- כך שהחתמה מחוץ לרדיוס תיראה בדיעבד כאילו נעשתה באתר — וגם על שורה
-- שכבר אושרה, כי אין בפוליסה שום בדיקת status. השכר עצמו לא היה חשוף
-- (actual_hours היא GENERATED מ-clock_in_at/clock_out_at, ושתיהן כן מגודרות),
-- אבל מסלול הראיות שכל מנגנון "נדרש מיקום" נבנה כדי לייצר — כן.
--
-- התיקון הוא רשימת היתר ולא רשימת איסור. רישום עשרים עמודות ב-field_registry
-- היה סוגר את החור של היום ומשאיר את הבא: עמודה שתתווסף לטבלה בעתיד תיוולד
-- שוב בלי הגנה. היתר מפורש הוא שלם מעצם הגדרתו, והוא גם מה שההערה כבר
-- הבטיחה. הטריגר הגנרי נשאר במקומו ומטפל במי שכן מחזיק attendance.edit_entry.

create or replace function app.attendance_owner_edit_guard()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_old jsonb := to_jsonb(old);
  v_new jsonb := to_jsonb(new);
  -- employee_note הוא מה שהעובד אמור לכתוב. updated_at נכתב בטריגר נפרד
  -- ולכן הוא ברשימה כדי שלא ייחשב כשינוי של המשתמש.
  --
  -- actual_hours היא GENERATED ALWAYS: בטריגר BEFORE היא טרם חושבה, ולכן
  -- ב-NEW היא null בזמן שב-OLD יש ערך — כל עדכון היה נראה כשינוי שלה.
  -- לזייף אותה ממילא אי אפשר, כי היא נגזרת מ-clock_in_at/clock_out_at ושתיהן
  -- חסומות כאן. הרשימה מפורשת ולא נשלפת מ-information_schema במכוון: עמודה
  -- מחושבת שתתווסף בעתיד תיחסם עד שמישהו יוסיף אותה לכאן, וזה הכיוון הבטוח.
  v_allowed constant text[] := array['employee_note', 'updated_at', 'actual_hours'];
  k text;
begin
  -- אותם שלושה פטורים של הטריגר הגנרי: מיגרציות ועבודות שרת בלי JWT,
  -- כתיבה מתוך RPC שכבר אכף את הכללים שלו, ואדמין.
  if auth.uid() is null then return new; end if;
  if app.in_system_write() then return new; end if;
  if app.is_admin() then return new; end if;
  -- מי שמחזיק את מפתח התיקון ממשיך לטריגר הגנרי, שמכריע לפי field_registry
  if app.has('attendance.edit_entry') then return new; end if;

  for k in select jsonb_object_keys(v_new) loop
    if k = any(v_allowed) then continue; end if;
    if v_old -> k is distinct from v_new -> k then
      raise exception 'אין לך הרשאה לשנות את השדה "%" ברשומת נוכחות', k
        using errcode = '42501';
    end if;
  end loop;
  return new;
end $$;

create trigger attendance_entries_owner_guard before update on attendance_entries
  for each row execute function app.attendance_owner_edit_guard();

-- משיכת דיווח שממתין לאישור היא הנתיב היחיד שבו עובד בלי attendance.edit_entry
-- משנה עמודה שאינה employee_note (deleted_at), והוא כבר אכף את הכלל שלו
-- בגוף ה-RPC. אותה עטיפה שמשמשת את attendance_clock_out ואת ההכרעה.
create or replace function attendance_delete_entry(p_id uuid, p_restore boolean default false)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_e attendance_entries;
  v_prev boolean;
begin
  select * into v_e from attendance_entries where id = p_id;
  if v_e.id is null then
    raise exception 'רשומת הנוכחות לא נמצאה';
  end if;
  if not (not p_restore and v_e.status = 'pending' and v_e.profile_id = app.profile_id()) then
    perform app.require('attendance.delete');
  end if;
  v_prev := app.in_system_write();
  perform app.system_write(true);
  update attendance_entries
     set deleted_at = case when p_restore then null else now() end
   where id = p_id;
  perform app.system_write(v_prev);
end $$;
revoke execute on function public.attendance_delete_entry(uuid, boolean) from anon, public;

-- ===== 2. portal.attendance היה מפתח שלא חסם איש ====================
--
-- הוא נרשם ב-0019 עם default_allowed=false, אבל גם עם
-- implied_by => 'portal.view' — ו-portal.view הוא default_allowed=true
-- (0011), כי הפורטל מגודר ב-shell ולא במפתח. שלב 6 של app.has הולך על
-- שרשרת ה-implied_by ומגיע ל-true, ולכן app.has('portal.attendance')
-- החזיר true לכל משתמש במערכת, ו-app.require עליו לא חסם דבר.
--
-- במקומות שבהם הוא נבדק לצד user_kind ('contractor_user') זה לא הזיק,
-- אבל contractor_staff_list נשען עליו לבדו. הוא לא דלף נתונים (הסגל נשלף
-- לפי app.contractor_id(), שהוא null לכל מי שאינו קבלן, ולכן התשובה הייתה
-- מערך ריק) — אבל השער היה פתוח, וזה מה שהבדיקה תפסה.
--
-- portal.attendance_pay כבר נרשם בלי implied_by. זה מיישר אותו לצידו:
-- הקבלנים מקבלים את המפתח מ-kind_permission_defaults (0019) ומהתפקידים
-- (0021), ולא בירושה ממפתח שכולם מחזיקים.
select app.register_permission('portal.attendance', 'portal', 'נוכחות עובדי הקבלן',
  'דוח הנוכחות של הסגל שלי בפורטל', 'access', false, false,
  array['contractor_user']::user_kind[], null, 45);

-- ===== 3. סיכום השכר בדוח של העובד עצמו =============================
--
-- השורות מסתירות כסף לפי v_money_all או (השורה שלי ו-v_money_own), אבל
-- totals.total נשען על v_money_all בלבד. התוצאה: עובד שרואה את דוח עצמו
-- קיבל סכום על כל שורה ושורת סיכום ריקה.
--
-- ההרחבה בטוחה כי הסכימה קוראת מ-v_rows אחרי שהכסף כבר הוסתר: לשורה
-- שאינה שלו אין pay.total, ו-sum מדלג על null. מי שרואה שעות בלי שכר
-- (רכז משמרות) עדיין מקבל null בשני התנאים, כמו קודם.
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
      'total',          case when v_money_all or v_money_own then
                        (select round(coalesce(sum((r #>> '{pay,total}')::numeric), 0), 2)
                          from jsonb_array_elements(v_rows) r
                         where r ->> 'status' = 'approved') end));
end $$;

-- ===== 4. אזורי תמחור שנמחקו היו עדיין קריאים =======================
--
-- pz_select הייתה פוליסת ה-SELECT היחידה בסכמה בלי deleted_at is null.
-- להשוואה, warehouses_select (0022) — טבלה כמעט זהה באופייה — כן כוללת
-- אותו. החישוב עצמו (app.zone_for_point) מסנן נכון, ולכן זו דליפת קריאה
-- ולא באג תמחור: אזור גיאופנס שנמחק המשיך להופיע לכל מי שמחזיק pricing.view.
drop policy if exists pz_select on pricing_zones;
create policy pz_select on pricing_zones for select to authenticated using (
  (select app.is_admin())
  or (deleted_at is null
      and (select app.user_kind()) = 'staff'
      and ((select app.has('pricing.manage_rules')) or (select app.has('pricing.view')))));

-- ===== 5. יומן הביקורת חזר להיות קריא ================================
--
-- 0016 החליף את מסך היומן הגולמי ב-event_activity לאירועים, ובדרך מחק את
-- הפוליסה audit_read ואת המפתח שלה בלי להעמיד חלופה. מאחר ש-RLS מופעל על
-- audit_log, טבלה עם אפס פוליסות SELECT אינה קריאה לאיש דרך ה-API — כולל
-- אדמין. היומן המשיך להיכתב מכל הטבלאות המבוקרות ואי אפשר היה לקרוא ממנו,
-- בזמן שה-README ממשיך להבטיח "Audit Log על כל שינוי".
--
-- כאן זה חוזר, אבל בלי implied_by: קריאה ביומן היא מתן אמון מפורש ולא משהו
-- שנגרר מ-settings.view. event_activity נשאר הדרך לראות אירוע; זה מה שעונה
-- על "מי מחק את הלקוח הזה", שאין לו היום שום תשובה במוצר.
select app.register_permission('settings.audit_log', 'settings', 'יומן ביקורת',
  'תמונות לפני/אחרי של כל שינוי במערכת', 'action', false, true,
  array['staff']::user_kind[], null, 80);

drop policy if exists audit_read on audit_log;
create policy audit_read on audit_log for select to authenticated using (
  (select app.is_admin()) or (select app.has('settings.audit_log')));
