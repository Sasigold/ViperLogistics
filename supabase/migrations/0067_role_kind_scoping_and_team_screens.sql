-- 0067: תפקידים מסוננים לפי סוג המשתמש, ומסכי הצוות נסגרים כמו שצריך
--
-- שני באגים שהתגלו אחרי 0066, שנתנו לאיש צוות (staff worker) לראות דשבורד עם
-- הכנסות, ועמודי לקוחות/עובדים/דוחות/אירועים — בניגוד למדיניות:
--
-- 1. דליפה חוצת-סוגים. app.my_role_ids() החזירה את *כל* התפקידים של הפרופיל
--    בלי קשר ל-user_kind שלהם, ו-app.has עושה עליהם bool_or. פרופיל staff
--    שהוצמד לו תפקיד customer_manager — תפקיד של customer_user — קיבל את כל
--    ההרשאות שלו: dashboard.view, pricing.view (הכנסות!), users.view ועוד.
--    השומר app.guard_profile_role כבר מונע הצמדה כזו, אבל הוא מדלג על אדמין
--    (return כש-is_admin) — וכך אדמין שהצמיד את התפקיד ממסך ההרשאות יצר את
--    הנתון השגוי. הסינון ב-my_role_ids הופך כל תפקיד חוצה-סוג — לא משנה איך
--    נוצר — לחסר-משמעות, גם בהרשאות וגם בהיקפי הנתונים.
--
-- 2. תפקידי הצוות (worker/driver/team_lead) לא סגרו את מסכי המשרד. הרצפה של
--    קהל ה-staff (kind_permission_defaults) פתוחה בכוונה לאנשי משרד — היא
--    נותנת customers.view, dashboard.view, events.view — וכל התפקידים
--    המשרדיים (dispatcher, ops_manager, finance, scheduler, viewer) מעניקים
--    אותם לעצמם גם במפורש. לכן אפשר לסגור אותם לתפקידי הצוות בדחייה מפורשת
--    בלי לגעת באנשי המשרד. מוסיפים דחיות, ומיישרים את שלושת התפקידים לרשימת
--    המסכים של "צוות": לוח שנה, לו״ז עבודה, המשמרות והנוכחות שלי, התראות.
--
-- הצוות עדיין רואה את *הקשר* האירוע שלו בלו״ז ובלוח (מספר אירוע, שם לקוח
-- הקצה) — אבל לא את עמוד האירועים. ההפרדה הזו נעשית בסעיף 4: events.view
-- שולט בעמוד ובניווט, וזרוע שיבוץ חדשה ב-events_select נותנת את הקשר הנתונים.

-- ===== 1. תפקידים מסוננים לפי סוג המשתמש ===================================
--
-- כל התפקידים במערכת נושאים user_kind (staff / customer_user / contractor_user);
-- אין תפקיד גלובלי. פרופיל אמור להחזיק רק תפקידים של הסוג שלו. הסינון כאן
-- הופך כל הצמדה חוצת-סוג לחסרת-משמעות — גם בהרשאות (app.has) וגם בהיקפי
-- הנתונים (app.scope_rows/scope_ids), ששניהם נשענים על my_role_ids.
create or replace function app.my_role_ids() returns uuid[]
language sql stable security definer set search_path = public as $$
  select coalesce(array_agg(pr.role_id), '{}'::uuid[])
  from profile_roles pr
  join permission_roles r on r.id = pr.role_id
  where pr.profile_id = app.profile_id()
    and r.is_active and r.deleted_at is null
    and (r.user_kind is null or r.user_kind = app.user_kind()::user_kind)
$$;

-- ===== 2. סגירת מסכי המשרד לתפקידי הצוות ===================================
--
-- worker / driver / team_lead = "צוות". דחייה מפורשת גוברת על הרצפה של קהל
-- ה-staff, ולכן זה סוגר בלי לגעת באנשי המשרד (שמעניקים לעצמם את המפתחות).
-- כל אלה כספים/חברה-רחב/ניהול — שום דבר מהם אינו במסכי הצוות שבמפרט.
insert into role_permissions (role_id, permission_key, allowed)
select r.id, k, false
from permission_roles r,
     unnest(array[
       'dashboard.view', 'dashboard.build_widget', 'dashboard.export',
       'dashboard.all_workers', 'dashboard.financial',
       'customers.view', 'contractors.view', 'users.view', 'reports.view',
       'settings.view', 'pricing.view', 'pricing.revenue',
       'events.view', 'attendance.view_all'
     ]) k
where r.key in ('worker', 'driver', 'team_lead')
on conflict (role_id, permission_key) do update set allowed = false;

-- ...והמסכים שכן שייכים לצוות. worker נולד ב-0011 בלי calendar.view (שורת
-- דחייה מפורשת); driver ו-team_lead כבר מקבלים אותו. מיישרים את שלושתם.
insert into role_permissions (role_id, permission_key, allowed)
select r.id, k, true
from permission_roles r,
     unnest(array['calendar.view', 'board.view', 'tasks.view',
                  'notifications.view', 'notifications.preferences',
                  'attendance.view_schedule', 'attendance.view_own', 'attendance.clock']) k
where r.key in ('worker', 'driver', 'team_lead')
on conflict (role_id, permission_key) do update set allowed = true;

-- ===== 3. הקשר האירוע לצוות, בלי עמוד האירועים =============================
--
-- events.view שולט גם בעמוד /events (הניווט וה-RouteGate) וגם בזרוע ה-staff
-- של events_select. סגרנו אותו לצוות בסעיף 2 — מה שמסתיר את העמוד — אבל בלי
-- זה הלו״ז והלוח היו מאבדים את הקשר האירוע (מספר אירוע, שם לקוח הקצה), שהם
-- דרך work_board_view שמצרף events תחת RLS של הקורא. הזרוע החדשה מחזירה את
-- ההקשר: איש staff רואה אירוע אם הוא משובץ למשימה בתוכו — גם בלי events.view.
--
-- זהה ל-events_select של 0066 פרט לזרוע ה-staff. תת-השאילתה על tasks/‏
-- task_assignments זהה במבנה לזרוע scope_own שכבר יושבת בפוליסה הזו מאז 0013,
-- ולכן אין כאן חשש רקורסיה: לא tasks_select ולא ta_select מפנים אל events.
drop policy events_select on events;
create policy events_select on events for select to authenticated using (
  (select app.is_admin())
  or (deleted_at is null
    and ((select app.scope_ids('events', 'customers')) is null
         or customer_id = any((select app.scope_ids('events', 'customers'))::uuid[]))
    and ((select app.scope_ids('events', 'statuses')) is null
         or status_id = any((select app.scope_ids('events', 'statuses'))::uuid[]))
    and ((select app.scope_date_from('events')) is null
         or event_date >= (select app.scope_date_from('events')))
    and ((select app.scope_date_to('events')) is null
         or event_date <= (select app.scope_date_to('events')))
    and (not (select app.scope_own('events'))
         or created_by = (select app.profile_id())
         or exists (select 1 from tasks t
                    where t.event_id = events.id and t.deleted_at is null
                      and exists (select 1 from task_assignments a
                                  where a.task_id = t.id and a.profile_id = (select app.profile_id()))))
    and (
      ((select app.user_kind()) = 'staff' and ((select app.has('events.view'))
         or exists (select 1 from tasks t
                    join task_assignments a on a.task_id = t.id
                    where t.event_id = events.id and t.deleted_at is null
                      and a.profile_id = (select app.profile_id()))))
      or ((select app.user_kind()) = 'customer_user' and customer_id = (select app.customer_id()))
      or ((select app.user_kind()) = 'contractor_user' and (
            ((select app.has('portal.view')) and exists (
               select 1 from tasks t where t.event_id = events.id
                 and t.contractor_id = (select app.contractor_id()) and t.deleted_at is null))
            or (select app.on_event_as_contractor_worker(events.id))))
    )));

-- ===== 4. ניקוי נתונים: הסרת התפקידים חוצי-הסוג שהוצמדו בטעות ==============
--
-- פרופילי staff שהוצמד להם תפקיד של customer_user או contractor_user. הסינון
-- בסעיף 1 כבר מנטרל אותם, אבל השורות עצמן שגויות ומטעות במסך ההרשאות.
delete from profile_roles pr
using permission_roles r, profiles p
where pr.role_id = r.id and pr.profile_id = p.id
  and r.user_kind is not null and r.user_kind is distinct from p.user_kind;
