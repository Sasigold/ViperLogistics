-- 0103: הקבלן בשטח — יומן, איש קשר, ומנהל שהוא גם עובד
--
-- חמישה דיווחים מאותו קהל, וכולם נגזרים משתי שאלות: מה קבלן רשאי לעשות
-- באירוע שהוא עובד בו, ומה קורה לאדם אחד שנושא שני כובעים.
--
--   1. **הקבלן אינו יכול לכתוב ביומן הפעילות.** ‏`events.activity_note` נגזר
--      מ-`events.edit`, שאין לו — ו-`events.activity_log` נגזר מ-`events.view`,
--      ש-0072 סגר למנהל הקבלן. כלומר גם לקרוא הוא לא יכול.
--   2. **עובד הקבלן רואה את איש הקשר של הלקוח.** ‏`event.contact_name/phone`
--      נרשמו `default_can_view = true` (0011), ולקהל ה-staff נכתבה דחייה
--      בברירת המחדל (0004) — אבל לא לקהל הקבלן. מגירת המשמרת
--      (`shift_task_breakdown`) שואלת `can_view_field` ומציגה שם וטלפון, ולכן
--      כל עובד קבלן עם התחברות ראה אותם.
--   3. **מי שהוא גם מנהל קבלן וגם עובד אינו מופיע בדוח.** ‏`app.shift_roster`
--      (0085) מכניס חשבון קבלן רק דרך שורת הסגל שלו (`contractor_worker_id`),
--      ולמנהל אין כזו.
--   4. **מנהל הקבלן אינו יכול להגדיר דבר לעובדיו.** ‏`wps_write` (0019) דורשת
--      מפתח משרדי — `attendance.manage_pay` או `attendance.manage_clock` —
--      ואין לה זרוע לקבלן.
--   5. **והוא אינו יכול לשבץ את עצמו.** ‏`contractor_assignable_workers`
--      (0075) משמיטה במפורש חשבונות שנושאים תפקיד מנהל: "הם אינם סגל".
--
-- הכלל שמאחד את 3 ו-5, ושהוא גם מה שהתבקש במפורש: **מנהל קבלן גובר על עובד
-- קבלן.** אדם שנושא את שני הכובעים הוא מנהל *ובנוסף* עובד — הוא אינו מאבד
-- דבר מהכובע הראשון, והוא כן מקבל את מה שהשני נותן. שכבת ההרשאות כבר עובדת
-- כך (`bool_or` על שורות התפקידים), והמקומות שסתרו אותה הם השניים שלמעלה.

-- ===== 1. הקבלן כותב ביומן הפעילות ========================================
--
-- ‏`applies_to` נפתח לקהל הקבלן כדי שהמפתח יופיע במטריצה כשמגדירים תפקיד
-- קבלן; `app.has` אינו מסתכל עליו (0026), ולכן הפתיחה לבדה אינה מעניקה דבר.
select app.register_permission(
  'events.activity_note', 'events', 'הוספת תיעוד חופשי ליומן',
  'רישום ידני ביומן הפעילות של האירוע', 'action', false, false,
  array['staff', 'customer_user', 'contractor_user']::user_kind[], 'events.edit', 180);

-- ‏`events.view` חוזר למנהל הקבלן. ‏0072 סגר אותו בנימוק שכתוב שם במפורש:
-- "מה שנשאר ממנו הוא רק הדלת ל-`/events`, מסך משרדי שאינו שלו". ‏0082 פיצל
-- מאז את הרשימה למפתח משלה (`events.list`), ולכן הנימוק חדל להתקיים — ומה
-- שנשאר הוא דף האירוע עצמו, שהוא בדיוק המקום שבו היומן והמפרט יושבים.
--
-- הזרוע שלו ב-`events_select` אינה משתנה: היא נשענת על `portal.view` ועל
-- שורת ה-terms (0098), ו-`events.view` נבדק שם רק בזרוע ה-staff. כלומר הוא
-- ממשיך לראות בדיוק את אותם אירועים — אלה שיש בהם משימה שהואצלה לו — ומה
-- שנפתח הוא הדלת אליהם.
insert into role_permissions (role_id, permission_key, allowed)
select r.id, k, true
from permission_roles r, unnest(array['events.view', 'events.activity_log', 'events.activity_note']) k
where r.key = 'contractor_manager'
on conflict (role_id, permission_key) do update set allowed = true;

-- ...ושני המפתחות שנגזרים מ-`events.view` ואינם שלו נסגרים במפורש, אחרת הם
-- נדלקים לו עכשיו בהיסק: הקטלוג ב-`/events` (0082) והייצוא לאקסל, שמסומן
-- מסוכן ומוציא את כל מה שבשורה.
insert into role_permissions (role_id, permission_key, allowed)
select r.id, k, false
from permission_roles r, unnest(array['events.list', 'events.export']) k
where r.key = 'contractor_manager'
on conflict (role_id, permission_key) do update set allowed = false;

-- העובד שגם מביא סגל (0075) מקבל את אותם שני מפתחות על הכובע הקבלני שלו.
-- שורות הדחייה הגורפות של 0079/0080 על מודול האירועים יושבות על תפקיד השטח
-- שלו, ושכבת התפקידים היא `bool_or` — ולכן ההענקה כאן גוברת עליהן. זה בדיוק
-- הכלל של הקובץ: הכובע המנהל אינו נגרע על ידי כובע העובד.
insert into role_permissions (role_id, permission_key, allowed)
select r.id, k, true
from permission_roles r, unnest(array['events.activity_log', 'events.activity_note']) k
where r.key = 'staff_contractor'
on conflict (role_id, permission_key) do update set allowed = true;

-- ===== 2. איש הקשר של הלקוח אינו של עובד הקבלן ============================
--
-- ההכרעה נכתבת בשתי שכבות, ובכוונה: דחייה לקהל הקבלן כולו, והיתר חוזר לתפקיד
-- המנהל. ‏`app.can_view_field` קורא פרופיל → תפקיד → קהל → מרשם, ולכן שורת
-- התפקיד גוברת על שורת הקהל — וכך "מנהל גובר על עובד" נאמר גם כאן, ולא רק
-- בסעיף 3.
--
-- למה קהל ולא תפקיד: חשבון עובד שנוצר דרך `contractor_assign_worker` (0091)
-- נולד בלי תפקיד כלל, ודחייה שיושבת על התפקיד `contractor_worker` הייתה
-- מדלגת עליו — כלומר בדיוק על העובד שהדיווח מדבר עליו.
--
-- מחיקה לפני ההכנסה במקום `on conflict`: האינדקסים הייחודיים כאן חלקיים
-- (0010), והכתיבה הזאת רצה פעם אחת ואינה צריכה להיות אלגנטית — רק חוזרת.
delete from field_permissions
 where entity = 'event' and field_key in ('contact_name', 'contact_phone')
   and ((user_kind = 'contractor_user' and profile_id is null and role_id is null)
        or role_id in (select id from permission_roles where key = 'contractor_manager'));

insert into field_permissions (user_kind, entity, field_key, can_view, can_edit)
values ('contractor_user', 'event', 'contact_name',  false, false),
       ('contractor_user', 'event', 'contact_phone', false, false);

-- מנהל הקבלן מתאם מול איש הקשר בשטח, ולכן הוא מקבל אותו בחזרה — לצפייה
-- בלבד. עריכה נשארת מאחורי `events.manage_contacts`, שאין לו.
insert into field_permissions (role_id, entity, field_key, can_view, can_edit)
select r.id, 'event', k, true, false
from permission_roles r, unnest(array['contact_name', 'contact_phone']) k
where r.key = 'contractor_manager';

-- ===== 3. מנהל קבלן שהוא גם עובד ==========================================
--
-- ‏0075 השמיטה חשבונות מנהל מרשימת השיבוץ בנימוק "הם אינם סגל, לא מחתימים
-- שעון ולא נגזרת להם משמרת". זה נכון לקבלן שרק מנהל, ושגוי בדיוק במקרה
-- שהדיווח מדבר עליו: קבלן קטן הוא לרוב גם העובד הראשון של עצמו. מי שאינו
-- עובד פשוט לא ישובץ — הרשימה מציעה, היא אינה קובעת — ומי שכן, מקבל מרגע
-- השיבוץ הראשון שורת סגל משלו (`contractor_assign_worker` יוצר אותה וקושר
-- אליה את הפרופיל), וממנה נגזרות המשמרת, השעון ושורת הדוח.
--
-- שאר הגוף זהה ל-0075 §4.
create or replace function contractor_assignable_workers(p_contractor_id uuid default null)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_ctr uuid := app.contractor_id();
begin
  /* מי שמקושר לקבלן מקבל את הסגל של אותו קבלן, ומתעלם מהארגומנט (0075). */
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

      -- חשבונות תחת אותו קבלן שאין להם שורת רוסטר. מ-0103 גם המנהל בכללם:
      -- הוא מוצע לשיבוץ ככל אחד אחר, ומי שרק מנהל פשוט לא נבחר.
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
    ) t(x, full_name)
  ), '[]'::jsonb);
end $$;

revoke execute on function public.contractor_assignable_workers(uuid) from anon, public;

-- והרוסטר של לוח המשמרות מקבל את אותו טיפול מהצד השני: מי שכבר החתים שעון
-- בטווח המוצג הוא עובד, גם אם עוד אין לו שורת סגל. בלי הזרוע הזאת מנהל שגם
-- עבד נעדר מהלוח ומרשימת העובדים של הדוח — נוכחות שנרשמה בלי אדם שאפשר
-- לסנן לפיו. שאר הגוף זהה ל-0085 §2.
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
     -- עובד קבלן נכנס דרך שורת הסגל שלו, או דרך נוכחות שכבר נרשמה לו בטווח
     -- (0103); עובד חברה דרך תפקיד הצוות שלו, או דרך שיבוץ בפועל בטווח.
     -- איש קשר אצל לקוח אינו נכנס בשום דרך, כמו קודם.
     and (p.contractor_worker_id is not null
          or (p.contractor_id is not null and exists (
                select 1 from attendance_entries ae
                 where ae.profile_id = p.id and ae.deleted_at is null
                   and ae.work_date between p_from and p_to))
          or (p.user_kind = 'staff'
              and (app.is_staff_member(p.id) or exists (
                    select 1 from task_assignments a
                      join tasks t on t.id = a.task_id and t.deleted_at is null
                     where a.profile_id = p.id and t.task_date between p_from and p_to))))
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
   order by (p.contractor_id is not null), c.name nulls first, p.full_name;
end $$;

-- ===== 4. הגדרות שכר ושעון לעובדי הקבלן ===================================
--
-- מפתח ייעודי ולא `attendance.manage_pay` המשרדי, בדיוק מהנימוק של 0091 §6
-- על `portal.approve_attendance`: המפתח המשרדי מתיר לכתוב את ההגדרות של *כל*
-- אדם במערכת, והזרוע כאן מוגבלת בפוליסה לסגל של הקבלן שכותב.
select app.register_permission('portal.worker_settings', 'portal',
  'הגדרות שכר ושעון לעובדי הקבלן',
  'מנהל קבלן קובע תעריף, שעות נוספות והגדרות שעון לעובדים של הקבלן שלו',
  'action', false, true,
  array['staff', 'contractor_user']::user_kind[], null, 47);

insert into role_permissions (role_id, permission_key, allowed)
select r.id, 'portal.worker_settings', true
from permission_roles r where r.key in ('contractor_manager', 'staff_contractor')
on conflict (role_id, permission_key) do update set allowed = true;

-- הקריאה: הזרוע הקיימת של הקבלן דורשת `portal.attendance_pay`, שהוא מפתח
-- כספי — ומי שקובע הגדרת שעון אינו בהכרח מי שרואה שכר. המפתח החדש מצטרף לצדו
-- ואינו מחליף אותו.
drop policy if exists wps_select on worker_pay_settings;
create policy wps_select on worker_pay_settings for select to authenticated using (
  (select app.is_admin())
  or profile_id = (select app.profile_id())
  or ((select app.user_kind()) = 'staff'
      and ((select app.has('attendance.view_pay')) or (select app.has('attendance.manage_clock'))))
  or (((select app.has('portal.attendance_pay')) or (select app.has('portal.worker_settings')))
      and app.is_my_contractor_staff(profile_id)));

-- והכתיבה: הזרועות המשרדיות כפי שהיו (0019), ולצדן מנהל הקבלן — על הסגל שלו
-- בלבד. ‏`is_my_contractor_staff` היא security definer ושואלת על `profiles`,
-- ולכן היא עונה נכון גם כשהפוליסה עצמה מסתירה את השורה מהקורא.
drop policy if exists wps_write on worker_pay_settings;
create policy wps_write on worker_pay_settings for all to authenticated
  using ((select app.is_admin())
         or (select app.has('attendance.manage_pay'))
         or (select app.has('attendance.manage_clock'))
         or ((select app.has('portal.worker_settings')) and app.is_my_contractor_staff(profile_id)))
  with check ((select app.is_admin())
         or (select app.has('attendance.manage_pay'))
         or (select app.has('attendance.manage_clock'))
         or ((select app.has('portal.worker_settings')) and app.is_my_contractor_staff(profile_id)));

-- הכתיבה עצמה עוברת ב-RPC, ולא ישירות בטבלה כמו במשרד. הסיבה אינה הרשאת
-- השורה — סעיף הפוליסה שלמעלה כבר פותח אותה — אלא הטריגר הגנרי על העמודות
-- (`app.enforce_field_perms`, 0012): הוא קורא מ-`field_registry` ש-
-- `hourly_rate` דורש `attendance.manage_pay`, ומפתח משרדי הוא בדיוק מה
-- שלמנהל הקבלן אין ואסור שיהיה. הרחבת הטריגר הייתה מחייבת אותו להכיר את
-- הזרוע הזאת פר-טבלה; פונקציה אחת שמכריזה על ההיקף שלה, מדליקה
-- `app.system_write` ומכבה אותו מיד, היא הדפוס שהרפו כבר משתמש בו לכל כתיבה
-- שנשענת על שער גס יותר.
--
-- ‏`jsonb_populate_record` על השורה הקיימת הוא מה שהופך את זה לעדכון חלקי:
-- מפתח שלא נשלח שומר על ערכו, ומפתח שאינו עמודה נזרק. ‏`profile_id` נדרס
-- מהארגומנט אחריו, כדי שגוף ה-JSON לא יוכל להפנות את הכתיבה לאדם אחר.
create or replace function portal_set_worker_settings(p_profile_id uuid, p_settings jsonb)
returns void language plpgsql security definer set search_path = public as $$
declare v_row worker_pay_settings;
begin
  if p_profile_id is null then
    raise exception 'חסר מזהה עובד' using errcode = '22023';
  end if;
  if not (app.is_admin()
          or (app.has('portal.worker_settings') and app.is_my_contractor_staff(p_profile_id))) then
    raise exception 'אין לך הרשאה להגדיר את העובד הזה' using errcode = '42501';
  end if;

  select * into v_row from worker_pay_settings where profile_id = p_profile_id;
  if v_row.profile_id is null then
    v_row.overtime_enabled := true;
    v_row.travel_paid      := true;
  end if;

  v_row := jsonb_populate_record(v_row, p_settings - 'profile_id' - 'created_at' - 'updated_at');
  v_row.profile_id := p_profile_id;

  perform app.system_write(true);
  insert into worker_pay_settings (
    profile_id, hourly_rate, overtime_enabled, min_hours_per_shift, travel_paid,
    team_lead_bonus, shift_bonus, late_topup_forfeit_minutes,
    clock_enabled, requires_location, location_radius_m,
    allow_early_clock_in, early_grace_minutes, allow_clock_without_shift, notes)
  values (
    v_row.profile_id, v_row.hourly_rate, v_row.overtime_enabled, v_row.min_hours_per_shift,
    v_row.travel_paid, v_row.team_lead_bonus, v_row.shift_bonus, v_row.late_topup_forfeit_minutes,
    v_row.clock_enabled, v_row.requires_location, v_row.location_radius_m,
    v_row.allow_early_clock_in, v_row.early_grace_minutes, v_row.allow_clock_without_shift, v_row.notes)
  on conflict (profile_id) do update set
    hourly_rate               = excluded.hourly_rate,
    overtime_enabled          = excluded.overtime_enabled,
    min_hours_per_shift       = excluded.min_hours_per_shift,
    travel_paid               = excluded.travel_paid,
    team_lead_bonus           = excluded.team_lead_bonus,
    shift_bonus               = excluded.shift_bonus,
    late_topup_forfeit_minutes = excluded.late_topup_forfeit_minutes,
    clock_enabled             = excluded.clock_enabled,
    requires_location         = excluded.requires_location,
    location_radius_m         = excluded.location_radius_m,
    allow_early_clock_in      = excluded.allow_early_clock_in,
    early_grace_minutes       = excluded.early_grace_minutes,
    allow_clock_without_shift = excluded.allow_clock_without_shift,
    notes                     = excluded.notes;
  perform app.system_write(false);
end $$;

-- ‏revoke לפני grant, כמו בכל RPC כאן: ההרשאה מגיעה ל-PUBLIC בברירת המחדל של
-- פוסטגרס, ו-anon יורש ממנה (0048). ההענקה המפורשת ל-authenticated אינה
-- מיותרת — היא מה שהופך את הפונקציה לקריאה דרך PostgREST גם על אשכול שאין בו
-- את ברירות המחדל של Supabase (0044, 0087 עושות בדיוק את זה).
revoke execute on function public.portal_set_worker_settings(uuid, jsonb) from anon, public;
grant execute on function public.portal_set_worker_settings(uuid, jsonb) to authenticated;

comment on function public.portal_set_worker_settings(uuid, jsonb) is
  'מנהל קבלן קובע הגדרות שכר ושעון לעובד מהסגל שלו (0103). המשרד כותב ישירות '
  'בטבלה, תחת הטריגר הגנרי על העמודות; זו הדרך היחידה שאינה דורשת מפתח משרדי.';

comment on function app.shift_roster(date, date) is
  'מי כשיר להחזיק משמרת בטווח: עובד חברה עם תפקיד צוות או שיבוץ, ועובד קבלן '
  'עם שורת סגל או נוכחות שנרשמה (0103) — כדי שמנהל קבלן שגם עובד לא ייעדר מהלוח.';
