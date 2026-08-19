-- 0085: מנהל מערכת אינו עובד, ואינו מוגבל בהיקף נתונים
--
-- שלושה דיווחים, ומאחוריהם אותה שאלה: מה בדיוק *הוא* מנהל מערכת.
--
--   • "מנהל מערכת שיהיה סוג משתמש ושלא אצטרך לרשום כצוות."
--   • "שלא יהיה למנהל מערכת שעון נוכחות ומשמרות, אלא אם הוא מוגדר גם כעובד."
--   • "למה כמנהל מערכת אין לי הרשאה לצפייה ברווחיות לפי משימה."
--
-- במסד מנהל מערכת הוא שורת `staff` עם `is_admin`, וזה נשאר כך: `user_kind`
-- מכריע עשרות פוליסות RLS, את `permission_roles.user_kind` ואת
-- `kind_permission_defaults`, וערך אנום רביעי היה נוגע בכולן כדי לתאר מישהו
-- שממילא עוקף את כולן. ההפרדה נעשית בשני מקומות שבהם היא באמת חסרה: הרוסטר
-- (כאן) והמסך שפותח אותו (`userType.ts`, `forEmployees` ב-nav.ts).
--
-- ‏`app.notification_audience` (0046) כבר עושה בדיוק את ההבחנה הזו — "אדמין
-- גובר על סוג המשתמש" — וזו הרחבה שלה לשני המקומות הנותרים.

-- ===== 1. מי נחשב עובד ====================================================
--
-- תפקיד צוות (`staff_roles`) הוא מה שהופך פרופיל לעובד: בלעדיו אי אפשר לשבץ
-- אותו בכלל — בוררי העובד/נהג/ראש-צוות שבמסך המשימה מסננים לפיו — ולכן שורה
-- שלו בלוח המשמרות היא לנצח ריקה.
create or replace function app.is_staff_member(p_profile uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from staff_roles s where s.profile_id = p_profile)
$$;

-- ===== 2. הרוסטר של לוח המשמרות ===========================================
--
-- ‏"מי כשיר להחזיק משמרת" (0034 §2א) היה "כל פרופיל צוות, או עובד קבלן עם
-- התחברות". הראשון רחב מדי: הוא כולל את מנהל המערכת — שנפתח כשורת צוות —
-- ואת אנשי המשרד, ושניהם קיבלו שורה קבועה בלוח שאין ואי אפשר שיהיו בה
-- משמרות. בלוח של חברה קטנה זה חצי מהשורות.
--
-- התנאי החדש הוא תפקיד הצוות, עם נפילה לאחור לשיבוץ בפועל: מי ששובץ בטווח
-- המוצג נשאר בלוח גם אם התפקיד הוסר לו אחר כך, בדיוק מאותו נימוק שבגללו
-- עובד שהושבת נשאר כשיש לו שיבוץ — משמרת שקיימת חייבת להיראות.
--
-- ההגדרה זהה ל-0075 פרט לתנאי אחד.
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
     -- עובד קבלן נכנס דרך שורת הסגל שלו, ועובד חברה דרך תפקיד הצוות שלו
     and (p.contractor_worker_id is not null or app.is_staff_member(p.id) or exists (
           select 1 from task_assignments a
             join tasks t on t.id = a.task_id and t.deleted_at is null
            where a.profile_id = p.id and t.task_date between p_from and p_to))
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

-- ===== 3. למנהל מערכת אין היקף נתונים =====================================
--
-- הדיווח: מנהל מערכת פותח את "רווחיות לפי משימה" ומקבל "הנתון אינו זמין
-- בהרשאות שלך". לא בגלל מפתח — `app.has` מחזיר לאדמין true בשורה הראשונה —
-- אלא בגלל התנאי השני שבשער: `exists (select 1 from app.scope_rows('tasks')
-- where scope_type <> 'all')`. די בכך שהוצמד לו אי־פעם תפקיד שנושא היקף
-- נתונים — ו-`worker` / `driver` / `team_lead` נושאים 'own' על tasks מאז
-- ‏0011 — כדי שהוא ייחשב "קורא בהיקף מצומצם" לנצח.
--
-- זה חוסר עקביות ולא החלטה: כל פוליסת RLS במערכת נפתחת ב-`app.is_admin() or`
-- ולכן מדלגת על ההיקף בפועל, ו-`app.has` עוקף את שכבת ההרשאות במפורש. רק
-- שאלת ההיקף המשיכה להיענות מהטבלה. התיקון הוא בנקודה האחת שכולם קוראים
-- דרכה, ולכן הוא חל על כל שערי הכספים יחד — דוחות (0058), רווחיות לקוחות
-- (0059), רווחיות משימות (0070), מנוע הדוחות (0044) ומקטעי הדשבורד
-- (0041/0069/0074) — במקום להתקן בשבעה מקומות ולהישכח בשמיני.
--
-- ההגדרה זהה ל-0010 פרט לענף הראשון.
create or replace function app.scope_rows(p_resource text)
returns setof permission_scopes
language sql stable security definer set search_path = public as $$
  select * from permission_scopes
    where not app.is_admin()
      and resource = p_resource and profile_id = app.profile_id()
  union all
  select * from permission_scopes
    where not app.is_admin()
      and resource = p_resource and role_id = any(app.my_role_ids())
      and not exists (select 1 from permission_scopes s2
                      where s2.resource = p_resource and s2.profile_id = app.profile_id())
$$;
