-- 0075: אדם אחד, שני כובעים — עובד שעתי שגם מביא עובדים
--
-- יש עובדים שהם גם קבלנים: הם עובדים אצלנו לפי שעות, ובמקביל מביאים סגל
-- משלהם. עד כאן המערכת הכריחה לבחור, ולא מפני שמשהו בסכימה אסר את השילוב —
-- ‏`profiles_contractor_kind` (0001) הוא גרירה חד-כיוונית, לא בלעדיות, ופרופיל
-- ‏`staff` תמיד היה רשאי לשאת `contractor_id` — אלא מפני ששלושה מקומות שאלו
-- **מי הוא** במקום **למי הוא שייך**:
--
--   v_portal := v_kind = 'contractor_user' and app.has('portal.attendance')
--
-- השאלה הנכונה היא `app.contractor_id() is not null`. הפונקציה הזאת קוראת את
-- העמודה בלי לבדוק סוג משתמש מאז 0004, ולכן היא כבר עונה נכון לשני הכובעים —
-- מה שחסר היה להשתמש בה. אין כאן פונקציה חדשה ואין שינוי סכימה: מי שמקושר
-- לקבלן מקבל את יכולות הקבלן, וסוג המשתמש חוזר לתאר איפה החשבון נולד.
--
-- הצד השעתי כבר עבד: `staff_roles`, `worker_pay_settings`, `task_assignments`
-- ו-`attendance_entries` כולם על `profile_id` ואדישים לסוג. הצד הקבלני הוא
-- שנפתח כאן.
--
-- **התפקיד נושא `user_kind = null` בכוונה.** ‏`app.my_role_ids()` (0067) מסנן
-- תפקידים שאינם תואמים לסוג המשתמש, ותפקיד בלי סוג עובר את המסנן לכל אחד —
-- ולכן אין צורך לגעת בפונקציה הזאת, שהיא הדבר היחיד שמגן על המערכת מהצמדות
-- תפקיד שגויות. ושכבת התפקידים היא `bool_or`: התפקיד יכול רק להוסיף למה
-- שהעובד כבר מחזיק, ולא לגרוע ממנו.

-- ===== 1. התפקיד ===========================================================

insert into permission_roles (key, name_he, description_he, user_kind, is_system, sort_order)
values ('staff_contractor', 'קבלן — בנוסף לתפקיד',
        'לעובד שגם מביא סגל משלו: הסגל, השיבוץ, הנוכחות והכספים של הקבלן שהוא מקושר אליו',
        null, true, 130)
on conflict (key) do update set
  name_he = excluded.name_he,
  description_he = excluded.description_he,
  user_kind = excluded.user_kind,
  sort_order = excluded.sort_order;

insert into role_permissions (role_id, permission_key, allowed)
select r.id, k, true
  from permission_roles r
 cross join unnest(array[
   'portal.view',            -- דף הכספים שלו כקבלן
   'portal.view_financials',
   'portal.manage_workers',  -- "העובדים שלי"
   'portal.assign_workers',  -- לשבץ אותם למשימות שהואצלו אליו
   'portal.attendance',      -- הנוכחות של הסגל שלו
   'contractors.view_pricing'
 ]) as k
 where r.key = 'staff_contractor'
on conflict (role_id, permission_key) do update set allowed = true;

-- ===== 2. מה שמנהל קבלן לא אמור להחזיק =====================================
--
-- ‏`contractors.assign_workers` ו-`contractors.manage_workers` הם המפתחות
-- ה*משרדיים* — "כל קבלן" — ומנהל הקבלן מחזיק אותם מאז 0011, שם הם נועדו
-- לתאר את הסגל של עצמו. ‏`contractor_assignable_workers` (0072) כבר סירבה
-- לסמוך על `manage_workers` בדיוק מהסיבה הזאת, ותיעדה למה; מה שלא נעשה הוא
-- להחיל את אותה מסקנה על `contractor_assign_worker`, שבו הענף "היקף זר"
-- מסתפק ב-`contractors.assign_workers` — כלומר מנהל קבלן שמכיר מזהה של עובד
-- אצל קבלן אחר יכול היה לשבץ אותו על משימה של אותו קבלן. ה-RPC הוא
-- `security definer` ולכן `tasks_select` לא עצר אותו.
--
-- הכיוון הנכון הוא להוריד את המפתחות המשרדיים ולא לסבך את הענף: `portal.*`
-- כבר נותן למנהל הקבלן את הסגל של עצמו ואת השיבוץ בו, וזה כל מה שהוא צריך.

insert into role_permissions (role_id, permission_key, allowed)
select r.id, k, false
  from permission_roles r
 cross join unnest(array['contractors.assign_workers', 'contractors.manage_workers']) as k
 where r.key in ('contractor_manager', 'contractor_worker')
on conflict (role_id, permission_key) do update set allowed = false;

-- ===== 3. הצמדות תפקיד שאינן תואמות לסוג המשתמש ============================
--
-- ‏0067 §4 ניקתה את אלה פעם אחת, אבל המסך המשיך להציע אותן: רשימת התפקידים
-- בטופס המשתמש לא סוננה לפי הסוג, ו-`app.my_role_ids()` בולע בשקט תפקיד שאינו
-- תואם. התוצאה היא משתמש שבמסך הניהול מסומנים לו תפקידים, ובפועל אין לו אף
-- אחד — ומי שהגדיר אותו בטוח שכן. הניקוי חוזר כאן, והמסך מסנן מעכשיו.

delete from profile_roles pr
 using permission_roles r, profiles p
 where r.id = pr.role_id and p.id = pr.profile_id
   and r.user_kind is not null
   and r.user_kind <> p.user_kind;

-- ===== 4. מי שמקושר לקבלן, ולא מי שנולד כקבלן ===============================
--
-- ארבע נקודות ההכרעה. הגופים מועתקים מהגרסאות האחרונות שלהם
-- (`contractor_assignable_workers` מ-0072, `app.shift_roster` מ-0034,
-- `app.attendance_pay_rows` ו-`attendance_report` מ-0039) עם השורה האחת הזאת
-- מוחלפת. `contractor_assign_worker` ו-`contractor_staff_list` כבר שואלים את
-- `app.contractor_id()` ישירות ואינם משתנים.

create or replace function contractor_assignable_workers(p_contractor_id uuid default null)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_ctr uuid := app.contractor_id();
begin
  /* מי שמקושר לקבלן מקבל את הסגל של אותו קבלן, ומתעלם מהארגומנט. הבדיקה
     **אינה** יכולה להיות `app.require('contractors.manage_workers')` על היקף
     זר: מנהל הקבלן החזיק את המפתח הזה מאז 0011, ולכן הוא היה פותח לו את הסגל
     של כל קבלן אחר (§2 למעלה מוריד לו אותו, אבל ההיגיון כאן לא יכול להישען
     על כך). ההפרדה היא בין "יש לי קבלן משלי" ל"אני מנהל אותם מהמשרד" — וזו
     שאלה על העמודה, לא על סוג המשתמש: העובד שגם מביא סגל הוא `staff`. */
  if v_ctr is null then
    v_ctr := p_contractor_id;
    if v_ctr is not null and not app.is_admin() then
      perform app.require('contractors.manage_workers');
    end if;
  end if;
  if v_ctr is null then return '[]'::jsonb; end if;

  return coalesce((
    select jsonb_agg(x order by x->>'full_name')
    from (
      select jsonb_build_object(
               'worker_id',  w.id,
               'profile_id', p.id,
               'full_name',  w.full_name,
               'phone',      w.phone,
               'has_login',  p.id is not null) as x,
             w.full_name
        from contractor_workers w
        left join profiles p
               on p.contractor_worker_id = w.id and p.deleted_at is null
       where w.contractor_id = v_ctr and w.deleted_at is null and w.is_active

      union all

      -- חשבונות תחת אותו קבלן שאין להם שורת רוסטר. מנהלי הקבלן מושמטים:
      -- הם אינם סגל, לא מחתימים שעון ולא נגזרת להם משמרת. וכך גם העובד
      -- שהוא עצמו הקבלן — הוא מנהל את הסגל, לא חלק ממנו.
      select jsonb_build_object(
               'worker_id',  null,
               'profile_id', p.id,
               'full_name',  p.full_name,
               'phone',      p.phone,
               'has_login',  true),
             p.full_name
        from profiles p
       where p.contractor_id = v_ctr
         and p.user_kind = 'contractor_user'
         and p.contractor_worker_id is null
         and p.deleted_at is null and p.is_active
         and not exists (
               select 1 from profile_roles pr
                 join permission_roles r on r.id = pr.role_id
                where pr.profile_id = p.id
                  and r.key in ('contractor_manager', 'staff_contractor'))
    ) t(x, full_name)
  ), '[]'::jsonb);
end $$;

revoke execute on function public.contractor_assignable_workers(uuid) from anon, public;

create or replace function app.shift_roster(p_from date, p_to date)
returns table (
  profile_id      uuid,
  full_name       text,
  contractor_id   uuid,
  contractor_name text,
  is_contractor   boolean,
  is_active       boolean)
language plpgsql stable security definer set search_path = public as $$
declare
  v_me     uuid    := app.profile_id();
  v_kind   text    := app.user_kind();
  v_ctr    uuid    := app.contractor_id();
  v_all    boolean;
  v_portal boolean;
begin
  if v_me is null then return; end if;

  v_all    := app.is_admin() or (v_kind = 'staff' and app.has('attendance.view_all'));
  v_portal := v_ctr is not null and app.has('portal.attendance');

  return query
  select p.id, p.full_name, p.contractor_id, c.name,
         (p.contractor_worker_id is not null), p.is_active
    from profiles p
    left join contractors c on c.id = p.contractor_id and c.deleted_at is null
   where p.deleted_at is null
     and (p.user_kind = 'staff' or p.contractor_worker_id is not null)
     and (p.is_active or exists (
           select 1 from task_assignments a
             join tasks t on t.id = a.task_id and t.deleted_at is null
            where a.profile_id = p.id and t.task_date between p_from and p_to
           union all
           select 1 from task_contractor_workers w
             join tasks t on t.id = w.task_id and t.deleted_at is null
            where w.contractor_worker_id = p.contractor_worker_id
              and t.task_date between p_from and p_to))
     and (v_all
          or (v_portal and p.contractor_id is not null and p.contractor_id = v_ctr)
          or (p.id = v_me and app.has('attendance.view_schedule')))
   -- הסדר נקבע בשרת כדי שסדר השורות בטבלה וסדר האפשרויות במסנן לא יוכלו
   -- לסתור זה את זה: עובדי החברה, ואחריהם כל קבלן כגוש.
   order by (p.contractor_id is not null), c.name nulls first, p.full_name;
end $$;

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
