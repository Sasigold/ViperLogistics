-- 0072: הקבלן נכנס ל-shell המשותף
--
-- ‏(הקובץ נכתב כ-0071 ומוספר מחדש: `0071_travel_zones_for_shifts` תפס את
-- אותה קידומת וכבר הורץ בפרודקשן, בעוד הקובץ הזה לא. הגוף לא השתנה.)
--
-- ‏0066 §6 כבר כתבה את `tasks_select` ו-`events_select` עם זרוע קבלן שמבחינה
-- בין המנהל (`portal.view` — כל משימות הקבלן) לעובד (רק משימות שפורסמו והוא
-- רשום עליהן), ו-§7ד כבר העניקה ל-`contractor_worker` את `board.view` ואת
-- `calendar.view`. שתיהן קוד מת: `RequireAuth` בדפדפן מפנה כל `contractor_user`
-- מכל נתיב שאינו `/portal` או `/my/*`, לפני ש-`RouteGate` בכלל רץ.
--
-- הקובץ הזה מסיר את הסיבה שבגללה ההפניה ההיא הייתה נחוצה, ומשלים את מה שחסר
-- כדי שהקבלן יהיה משתמש רגיל של אותם מסכים — בדיוק כפי שנעשה ללקוחות כשפורקה
-- מהם המעטפת `/client`.
--
-- שלוש הכרעות שראוי לנמק:
--
-- * **`default_allowed` של מפתחות הפורטל מתהפך.** בלי זה אי אפשר לגדר בהם
--   נתיב, כי כל איש staff פותר אותם `true` (§1).
--
-- * **הדחיות למנהל הקבלן מפורשות ולא נשענות על ה-RLS.** ה-RLS וטריגר השדות
--   כבר מסרבים לכתיבה, אבל הלוח היה מצייר תאים שנראים ניתנים לעריכה ומגלים
--   את הסירוב רק בשמירה (§2).
--
-- * **שיבוץ של עובד רשום יוצר את שורת הרוסטר החסרה.** זה לא נוחות: המשמרת
--   הנגזרת והשעון שניהם מצטרפים דרך `profiles.contractor_worker_id`, ובלי
--   הגשר השיבוץ היה חצי-אמיתי (§5).

-- ===== 1. סגירת ברירת המחדל של מפתחות הפורטל ==============================
--
-- ‏0011 רשם את ארבעת מפתחות הפורטל עם `default_allowed = true`. שכבה 5 של
-- `app.has` נופלת לשם אחרי שכבת ה-kind, ולכן **כל איש staff פותר אותם true** —
-- וזו הסיבה שעד היום הם לא יכלו לגדר נתיב או רשומת תפריט, ושהחסימה נעשתה
-- בהפניה ידנית לפי `user_kind` בדפדפן.
--
-- הקבלנים אינם מאבדים דבר: `kind_permission_defaults` מדליק את ארבעתם ל-
-- `contractor_user` (0011), והתפקיד `contractor_manager` מדליק אותם שוב.
-- ‏`portal.attendance` כבר נרשם `false` ב-0027 ואינו נוגע כאן.
--
-- ‏`update` ישיר ולא `app.register_permission`: ה-`on conflict do update` שלה
-- מעדכן הכול חוץ מ-`default_allowed` (0010), בכוונה — כדי שרישום חוזר לא
-- ישנה מדיניות. כאן המדיניות היא בדיוק מה שמשתנה.
update permission_registry set default_allowed = false
 where key in ('portal.view', 'portal.assign_workers',
               'portal.view_financials', 'portal.manage_workers');

-- ===== 2. מנהל הקבלן — מפתחות המסכים המשותפים =============================
--
-- **הוא כבר מחזיק את רובם, ובמקרה.** `board.view` נגזר מ-`tasks.view`
-- ו-`calendar.view` מ-`events.view` (0011:53,58), ושניהם ברשימת התפקיד
-- (0011:443); `board.columns` נגזר מ-`board.view`; ו-`board.view_staffing`
-- דלוק ל-`contractor_user` בברירת המחדל של הקהל (0026). כל אלה נפתרו `true`
-- כל הזמן הזה, והדבר היחיד שחסם היה ההפניה בדפדפן.
--
-- ההענקה המפורשת כאן אינה מרחיבה דבר — היא הופכת ירושה מקרית להכרעה. בלעדיה,
-- מי שיצמצם מחר את `tasks.view` של מנהל הקבלן היה לוקח ממנו את הלוח בלי לדעת.
--
-- בתבנית האינקרמנטלית של 0066 §7 ולא דרך `app.set_role_permissions`: היא
-- מוחקת את *כל* שורות התפקיד, כולל `portal.attendance` שנוסף ב-0021.
insert into role_permissions (role_id, permission_key, allowed)
select r.id, k, true
from permission_roles r,
     unnest(array['calendar.view', 'board.view', 'board.view_staffing', 'board.columns',
                  'notifications.preferences',
                  'attendance.view_schedule', 'attendance.view_own', 'attendance.clock']) k
where r.key = 'contractor_manager'
on conflict (role_id, permission_key) do update set allowed = true;

-- ‏`events.view` נסגר, ואיתו מסך האירועים. הוא היה ברשימה של 0011 כדי ש-
-- `calendar.view` ייגזר ממנו; מרגע ש-`calendar.view` מוענק ישירות, מה שנשאר
-- ממנו הוא רק הדלת ל-`/events` — מסך משרדי עם לקוחות, ספקים ותוספות, שאינו
-- שלו. לוח השנה והלוח אינם מאבדים הקשר: זרוע הקבלן ב-`events_select`
-- (0066 §6, 0067 §3) נשענת על `portal.view` ולא על `events.view`. אותה הבחנה
-- בדיוק שנעשתה לצוות ב-0067 §2.
insert into role_permissions (role_id, permission_key, allowed)
select r.id, 'events.view', false
from permission_roles r where r.key = 'contractor_manager'
on conflict (role_id, permission_key) do update set allowed = false;

-- ...ומה שנשאר סגור. `contractors.view` אינו ברשימה בכוונה — מנהל הקבלן אינו
-- נכנס למסך הקבלנים, והסגל שלו מקבל דף משלו מאחורי `portal.manage_workers`.
insert into role_permissions (role_id, permission_key, allowed)
select r.id, k, false
from permission_roles r,
     unnest(array['dashboard.view', 'customers.view', 'users.view', 'reports.view',
                  'settings.view', 'pricing.view', 'pricing.revenue',
                  'attendance.view_all', 'attendance.edit_entry',
                  'calendar.drag', 'board.inline_edit', 'board.bulk_edit',
                  'tasks.create', 'tasks.edit', 'tasks.publish', 'tasks.change_status',
                  'tasks.reschedule', 'tasks.change_location', 'tasks.change_truck',
                  'tasks.change_worker_count', 'tasks.change_execution_method',
                  'tasks.delegate', 'tasks.assign.worker', 'tasks.assign.driver',
                  'tasks.assign.team_lead', 'tasks.assign.truck']) k
where r.key = 'contractor_manager'
on conflict (role_id, permission_key) do update set allowed = false;

-- ===== 3. עובד קבלן — יישור לרצפת העובד ====================================
--
-- ‏0067 §2 קבעה את הרצפה של worker/driver/team_lead. `contractor_worker` קיבל
-- את `board.view` ו-`calendar.view` ב-0066 §7ד; מה שנשאר הוא ההפרש. ההענקה
-- מפורשת ולא נשענת על כך ש-`attendance.submit_entry` נרשם רק ב-0024 ולכן
-- `close_modules` של 0019 לא הספיק לדחות אותו.
--
-- המודולים `portal` ו-`contractors` נשארים סגורים לו: בלעדיהם הוא היה יורש
-- מברירות המחדל של `contractor_user` את פורטל הקבלן על כל הכספים שבו.
insert into role_permissions (role_id, permission_key, allowed)
select r.id, k, true
from permission_roles r,
     unnest(array['tasks.view', 'notifications.preferences',
                  'attendance.submit_entry', 'attendance.view_own_pay']) k
where r.key = 'contractor_worker'
on conflict (role_id, permission_key) do update set allowed = true;

-- ===== 4. קישור ההתראה ====================================================
--
-- ‏0054 פיצל משימה לפי `user_kind` והחזיר לקבלן `/portal?task=`, בנימוק
-- שכתוב שם: "המסכים נפרדים ממילא — לקבלן יש /portal ולצוות יש /board".
-- מרגע ש-`board.view` בידי שני תפקידי הקבלן, הפיצול מתאר מצב שאינו קיים.
-- הגוף זהה ל-0054 פרט למחיקת הזרוע ושל ה-`select` שהזין אותה.
create or replace function app.notification_link(
  p_recipient uuid, p_type text, p_entity_type text, p_entity_id uuid)
returns text language plpgsql stable security definer set search_path = public as $$
declare v_date date;
begin
  if p_entity_id is null then return '/'; end if;

  if p_entity_type = 'event' then
    return '/events/' || p_entity_id;
  end if;

  if p_entity_type = 'task' then
    select task_date into v_date from tasks where id = p_entity_id;
    return '/board?task=' || p_entity_id
           || coalesce('&date=' || to_char(v_date, 'YYYY-MM-DD'), '');
  end if;

  if p_entity_type = 'attendance_entry' then
    if p_type = 'attendance_submitted' then
      select work_date into v_date from attendance_entries where id = p_entity_id;
      return '/attendance?entry=' || p_entity_id
             || coalesce('&date=' || to_char(v_date, 'YYYY-MM-DD'), '');
    end if;
    return '/my/attendance?entry=' || p_entity_id;
  end if;

  return '/';
end $$;

-- ===== 5. עובדים רשומים כברי-שיבוץ ========================================
--
-- לקבלן שתי רשימות עובדים, והן מחוברות רק דרך `profiles.contractor_worker_id`:
-- ‏`contractor_workers` היא הרוסטר הידני, ו-`profiles` עם `contractor_id` הם
-- החשבונות. `ClockAccountModal` מייצר תמיד את הגשר, אבל חשבון שהמשרד יצר
-- במסך העובדים — `contractor_id` בלי `contractor_worker_id` — אינו יושב
-- ברוסטר, ולכן מעולם לא הופיע בבורר השיבוץ.
--
-- ‏`security definer` מאותו נימוק שהוליד את `contractor_staff_list` (0025):
-- ‏`profiles_select` אינו מרשה ל-`contractor_user` לקרוא שורות של אחרים.

create or replace function contractor_assignable_workers(p_contractor_id uuid default null)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_ctr uuid;
begin
  /* קורא מסוג `contractor_user` מתעלם מהארגומנט לחלוטין ומקבל את שלו, כמו
     ב-`contractor_staff_list` (0025). הבדיקה **אינה** יכולה להיות
     `app.require('contractors.manage_workers')` על היקף זר: מנהל הקבלן מחזיק
     את המפתח הזה מאז 0011 — הוא מה שמתיר לו לנהל את הסגל של עצמו — ולכן הוא
     היה פותח לו את הסגל של כל קבלן אחר. ההפרדה היא לפי סוג המשתמש, שהוא גם
     מה שמפריד בין "הסגל שלי" ל"הסגל שלהם". */
  if app.user_kind() = 'contractor_user' then
    v_ctr := app.contractor_id();
  else
    v_ctr := coalesce(p_contractor_id, app.contractor_id());
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
      -- הם אינם סגל, לא מחתימים שעון ולא נגזרת להם משמרת.
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
                where pr.profile_id = p.id and r.key = 'contractor_manager')
    ) t(x, full_name)
  ), '[]'::jsonb);
end $$;

revoke execute on function public.contractor_assignable_workers(uuid) from anon, public;

comment on function public.contractor_assignable_workers(uuid) is
  'מי מהקבלן ניתן לשיבוץ: הרוסטר הידני ועוד חשבונות שנרשמו תחתיו בלי שורת רוסטר.';

-- ‏`contractor_assign_worker` מחליף את הכתיבה הישירה ל-`task_contractor_workers`
-- מהדפדפן. שתי סיבות: הטבלה מפתחת על `contractor_worker_id` בלבד, ולכן שיבוץ
-- של חשבון בלי שורת רוסטר מחייב ליצור אותה קודם; ושתי הכתיבות חייבות להיות
-- באותה טרנזקציה, אחרת שיבוץ שנכשל היה משאיר שורת רוסטר יתומה.
--
-- **יצירת הגשר אינה קוסמטיקה.** `app.planned_shifts_many` (0034) מצרפת
-- `profiles pr on pr.contractor_worker_id = w.contractor_worker_id`, ומנוע
-- הנוכחות כותב על `attendance_entries.profile_id`. בלי הגשר העובד המשובץ לא
-- היה מקבל משמרת נגזרת ולא היה יכול להחתים — כלומר השיבוץ היה חצי-אמיתי.
--
-- ‏`security definer` כאן **עוקף** את `tcw_contractor_insert` (0012), כי בעל
-- הטבלה פטור מ-RLS. לכן שלושת התנאים של אותה פוליסה נבדקים בגוף במפורש —
-- המפתח, שהמשימה שייכת לקבלן, ושהעובד שייך לאותו קבלן — ולא בהסתמכות עליה.
-- הפוליסה נשארת במקומה עבור כל נתיב כתיבה אחר.
create or replace function contractor_assign_worker(
  p_task_id uuid,
  p_worker_id uuid default null,
  p_profile_id uuid default null,
  p_on boolean default true,
  p_work_site text default 'field')
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_task_ctr uuid;
  v_mine     uuid := app.contractor_id();
  v_worker   uuid := p_worker_id;
  v_prof     profiles%rowtype;
begin
  if not (app.has('portal.assign_workers') or app.has('contractors.assign_workers')) then
    raise exception 'אין לך הרשאה לשבץ עובדי קבלן' using errcode = '42501';
  end if;
  if p_work_site not in ('field', 'warehouse') then
    raise exception 'אתר עבודה לא חוקי: %', p_work_site using errcode = '22023';
  end if;

  select contractor_id into v_task_ctr
    from tasks where id = p_task_id and deleted_at is null;
  if v_task_ctr is null then
    raise exception 'המשימה לא נמצאה או שאינה מואצלת לקבלן' using errcode = '42501';
  end if;
  -- קבלן משבץ רק במשימות שלו; איש משרד צריך את המפתח המשרדי לכל קבלן.
  if v_task_ctr is distinct from v_mine then
    perform app.require('contractors.assign_workers');
  end if;

  -- פתרון הגשר: חשבון שנרשם תחת הקבלן ואין לו שורת רוסטר מקבל אחת עכשיו.
  -- ‏`user_id` נשאר ריק בשורה החדשה, כמו ב-`ClockAccountModal`: הגשר הקנוני
  -- הוא `profiles.contractor_worker_id` (0019), ומילוי `contractor_workers.user_id`
  -- היה מתנגש ב-`contractor_workers_user_uq` מול שורה קיימת של אותו משתמש.
  if v_worker is null then
    if p_profile_id is null then
      raise exception 'חובה לנקוב בעובד או בחשבון' using errcode = '22023';
    end if;
    select * into v_prof from profiles
     where id = p_profile_id and deleted_at is null;
    if v_prof.id is null or v_prof.contractor_id is distinct from v_task_ctr then
      raise exception 'העובד אינו רשום תחת הקבלן של המשימה' using errcode = '42501';
    end if;
    v_worker := v_prof.contractor_worker_id;
    if v_worker is null then
      insert into contractor_workers (contractor_id, full_name, phone)
      values (v_task_ctr, v_prof.full_name, v_prof.phone)
      returning id into v_worker;
      update profiles set contractor_worker_id = v_worker where id = v_prof.id;
    end if;
  end if;

  -- התנאי השלישי של `tcw_contractor_insert`, שנבדק כאן כי ה-definer עוקף אותה:
  -- העובד חייב להיות של הקבלן שהמשימה הואצלה אליו.
  if not exists (select 1 from contractor_workers cw
                  where cw.id = v_worker and cw.contractor_id = v_task_ctr
                    and cw.deleted_at is null) then
    raise exception 'העובד אינו בסגל של הקבלן שהמשימה הואצלה אליו' using errcode = '42501';
  end if;

  if p_on then
    insert into task_contractor_workers (task_id, contractor_worker_id, work_site)
    values (p_task_id, v_worker, p_work_site)
    on conflict (task_id, contractor_worker_id) do update set work_site = excluded.work_site;
  else
    delete from task_contractor_workers
     where task_id = p_task_id and contractor_worker_id = v_worker;
  end if;

  return v_worker;
end $$;

revoke execute on function
  public.contractor_assign_worker(uuid, uuid, uuid, boolean, text) from anon, public;

comment on function public.contractor_assign_worker(uuid, uuid, uuid, boolean, text) is
  'שיבוץ/הסרה של עובד קבלן במשימה, כולל יצירת שורת הרוסטר לחשבון שנרשם בלעדיה.';
