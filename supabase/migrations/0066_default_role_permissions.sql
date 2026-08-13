-- 0066: הרשאות ברירת המחדל פר סוג משתמש
--
-- המערכת כבר יודעת לפתור הרשאה פר מפתח (app.has, 0010), פר תפקיד
-- (permission_roles) ופר משתמש (user_permission_grants). מה שחסר היה
-- שברירות המחדל של התפקידים יתארו את המדיניות שהוגדרה:
--
--   מנהל לקוח   — מעלה ועורך אירועים; רואה מחירים בלי לערוך; רואה מי משובץ
--                 בלי לשבץ; עורך משימות חוץ מצוות, מחירים ופרסום ("משובץ").
--   עובד לקוח   — כמו המנהל אבל צפייה בלבד, וללא שום נתון כספי.
--   צוות         — worker / driver / team_lead: צפייה בלבד במה שהם חלק ממנו,
--                 בלי דשבורד ובלי מחירים.
--   עובד קבלן    — כמו צוות: רואה בלוח ובלו״ז רק את המשימות ששובץ אליהן.
--   מנהל קבלן    — כבר תואם (portal.*, contractors.view_pricing); ללא שינוי.
--
-- כל אלה נשארים ברירת מחדל בלבד: user_permission_grants ממשיך לגבור עליהם
-- פר משתמש, וזו כל הנקודה של השכבה הזו ב-app.has.
--
-- שתי הבחנות שחוזרות לאורך הקובץ:
--   * שינוי סטטוס משימה ל"משובץ" הוא *פרסום* — מרגע זה העובד רואה את המשימה
--     ומקבל התראות (0063/0064). לכן הוא מפתח נפרד, tasks.publish, ולא עוד
--     ערך של tasks.change_status.
--   * דחייה מפורשת (role/kind) גוברת על allow שיורש דרך implied_by, כי
--     app.has מכריע בעומק הרדוד ביותר תחילה. זו הסיבה ש-tasks.publish בטוח
--     כ-implied_by של tasks.change_status: מי שמחזיק את ההורה ממשיך לפרסם,
--     ומי שחסום עליו במפורש — לא.

-- ===== 1. מפתח חדש: פרסום משימה ============================================
--
-- implied_by = tasks.change_status: כל מי שכבר רשאי לשנות סטטוס (ops_manager,
-- dispatcher, וכל grant אישי) ממשיך לפרסם בלי שינוי. tasks.change_status
-- *אינו* default_allowed, ולכן ההיסק הזה אינו דולף לקהלים שלא אמורים אותו
-- (זו בדיוק ההבחנה של 0042: implied_by דולף רק כשההורה דלוק בברירת המחדל).
select app.register_permission('tasks.publish', 'tasks',
  'פרסום משימה (סטטוס "משובץ")',
  'העברת משימה לסטטוס "משובץ" — מרגע זה העובד רואה אותה ומקבל התראות',
  'action', false, false,
  array['staff', 'customer_user']::user_kind[],
  'tasks.change_status', 85);

-- ===== 2. נראות במטריצת ההרשאות (applies_to בלבד) =========================
--
-- app.has מתעלם מ-applies_to; הוא משמש רק לסינון מסך ההרשאות של האדמין. כדי
-- שאפשר יהיה לנהל ולדרוס את מפתחות עריכת המשימה ואת עמודות הצוות עבור משתמשי
-- לקוח, הם צריכים לכלול customer_user ברשימה. זהה בכוונתו ל-0026 §1.
update permission_registry
   set applies_to = array['staff', 'customer_user']::user_kind[]
 where key in ('tasks.edit', 'tasks.reschedule', 'tasks.change_status', 'tasks.change_type',
               'tasks.change_worker_count', 'tasks.change_execution_method',
               'tasks.change_location', 'tasks.change_truck', 'tasks.edit_notes',
               'board.view', 'board.columns', 'board.view_staffing');

-- ===== 3. תיקוני ברירת מחדל פר סוג משתמש ==================================
--
-- ברירות המחדל של customer_user הגיעו מ-0004 עם events.create ו-events.edit
-- דלוקים ברמת ה-kind. המשמעות: *כל* משתמש לקוח, כולל "צופה", ירש עריכת
-- אירועים. מהיום זכות העריכה מגיעה מהתפקיד (customer_manager), ולכן שכבת
-- ה-kind נסגרת — וכך "עובד לקוח" (customer_viewer, בלי close_modules) נופל
-- לצפייה בלבד. customer_manager לא מושפע: שורת התפקיד שלו גוברת על ה-kind
-- באותו עומק (role לפני kind ב-coalesce של app.has).
--
-- board.view_staffing נדלק לשני תפקידי הלקוח — "מי משובץ" גלוי, היכולת לשבץ
-- לא (זו נשמרת ב-app.assignment_allowed, סעיף 5).
--
-- tasks.publish נסגר ללקוח ולקבלן ברמת ה-kind: שורת kind מדברת בעומק 0, לפני
-- שהשרשרת מגיעה ל-tasks.change_status, ונשארת ניתנת לשינוי פר משתמש.
insert into kind_permission_defaults (user_kind, permission_key, allowed) values
  ('customer_user',   'events.create',       false),
  ('customer_user',   'events.edit',         false),
  ('customer_user',   'board.view_staffing', true),
  ('customer_user',   'tasks.publish',       false),
  ('contractor_user', 'tasks.publish',       false)
on conflict (user_kind, permission_key) do update set allowed = excluded.allowed;

-- כשפותחים ללקוח את הדשבורד (מנהל לקוח מקבל dashboard.view בסעיף 7) נגררים
-- איתו, דרך implied_by ודרך default_allowed, סקשנים שהם של החברה ולא של
-- הלקוח: סטטיסטיקות כל הצוות (dashboard.all_workers, implied_by dashboard.view),
-- הסכומים הכספיים (dashboard.financial, default_allowed), והייצוא. נחסמים
-- ברמת ה-kind — עומק 0, לפני שהשרשרת מגיעה ל-dashboard.view — ונשארים ניתנים
-- לשינוי פר משתמש. (dashboard.contractors נגזר מ-contractors.view שאין ללקוח,
-- ולכן ממילא כבוי.)
insert into kind_permission_defaults (user_kind, permission_key, allowed) values
  ('customer_user', 'dashboard.all_workers', false),
  ('customer_user', 'dashboard.financial',   false),
  ('customer_user', 'dashboard.export',      false)
on conflict (user_kind, permission_key) do update set allowed = excluded.allowed;

-- ===== 4. אכיפת הפרסום בשרת ================================================
--
-- כתיבת סטטוס משימה עוברת תמיד דרך טבלת tasks — TaskDrawer, עריכת התא בלוח,
-- וה-RPC bulk_update_tasks — ולכן טריגר על הטבלה מכסה את כל הנתיבים. אותם
-- תנאי דילוג של app.enforce_field_perms (0012): שירות בלי JWT, כתיבת מערכת,
-- ואדמין. הבדיקה על INSERT חשובה לא פחות מ-UPDATE: יוצר בלי הרשאת פרסום
-- אסור שיוליד משימה שכבר "משובצת".
create or replace function app.enforce_task_publish()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_assigned uuid;
begin
  if auth.uid() is null then return new; end if;
  if app.in_system_write() then return new; end if;
  if app.is_admin() then return new; end if;

  select id into v_assigned from statuses
   where entity = 'task' and code = 'assigned' and deleted_at is null limit 1;

  if new.status_id = v_assigned
     and (tg_op = 'INSERT' or old.status_id is distinct from new.status_id) then
    perform app.require('tasks.publish', 'אין לך הרשאה לפרסם משימה (סטטוס "משובץ")');
  end if;
  return new;
end $$;

create trigger tasks_publish_guard before insert or update on tasks
  for each row execute function app.enforce_task_publish();

-- ===== 5. RLS: עריכת משימות ללקוח, וראיית מי משובץ =========================
--
-- 5א. עריכת משימות בידי מנהל הלקוח. הפוליסה של 0005 הייתה staff בלבד; מוסיפים
-- זרוע customer_user מוגבלת ללקוח שלו. שליטת העמודות נשארת בטריגר השדות
-- (enforce_field_perms — צוות ומחירים אינם עמודות של tasks ממילא, ומחיר
-- הלקוח יושב ב-task_pricing עם tp_write), ושליטת הפרסום בטריגר של סעיף 4.
-- ה-WITH CHECK שומר שהמשימה לא תיטלטל ללקוח אחר.
drop policy tasks_update on tasks;
create policy tasks_update on tasks for update to authenticated
using (
  (select app.is_admin())
  or (deleted_at is null and (
    ((select app.user_kind()) = 'staff' and (select app.has('tasks.edit')))
    or ((select app.user_kind()) = 'customer_user'
        and customer_id = (select app.customer_id())
        and (select app.has('tasks.edit')))))
)
with check (
  (select app.is_admin())
  or (deleted_at is null and (
    ((select app.user_kind()) = 'staff' and (select app.has('tasks.edit')))
    or ((select app.user_kind()) = 'customer_user'
        and customer_id = (select app.customer_id())
        and (select app.has('tasks.edit')))))
);

-- 5ב. השמות של המשובצים. work_board_view הוא security_invoker, ולכן ה-join
-- שלו אל task_assignments ואל profiles כפוף ל-RLS של הקורא. ללקוח, ta_select
-- (0028) מחזיר רק את ההשמות של *עצמו* ו-profiles_select (0005) רק את פרופילי
-- החברה שלו — ולכן עמודות הצוות בלוח חזרו ריקות. שתי הזרועות כאן, שתיהן
-- מותנות ב-board.view_staffing, פותחות בדיוק את הקריאה הזאת: מי משובץ למשימות
-- של הלקוח, ואת שמו של אותו אדם. אין כאן זכות שיבוץ — היא ב-app.assignment_allowed.
--
-- הבדיקות "האם ההשמה הזו על משימה של הלקוח שלי" ו"האם הפרופיל הזה משובץ
-- למשימה של הלקוח שלי" עטופות ב-security definer, ולא בתת-שאילתה בפוליסה:
-- ta_select מפנה כאן אל tasks, ו-tasks_select מפנה אל task_assignments, וצמד
-- כזה של פוליסות שמפנות זו אל טבלת זו הוא רקורסיה הדדית ש-Postgres חוסם —
-- גם כשה-user_kind מונע אותה בזמן ריצה, ההרחבה עצמה מעגלית. הפונקציה עוקפת
-- RLS ומוגבלת ממילא ללקוח הקורא.
--
-- הערה על שארית: RLS הוא ברמת שורה ולא ברמת עמודה. משנפתחה שורת פרופיל הצוות
-- ללקוח, בקשת REST ישירה אל profiles יכולה לקרוא גם את עמודת הטלפון/אימייל
-- שלה (המסך עצמו קורא רק דרך work_board_view, שחושף full_name בלבד;
-- ו-profiles_secure ממילא ממסך טלפון/אימייל דרך users.view_contact). מדובר
-- באנשי הצוות המשובצים לאירועי הלקוח בלבד. אם החשיפה הזו אינה מקובלת, הצעד
-- הבא הוא view ייעודי security-definer לשמות במקום זרועות ה-RLS.
create or replace function app.assignment_on_my_customer(p_task_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from tasks t
                  where t.id = p_task_id and t.deleted_at is null
                    and t.customer_id = app.customer_id())
$$;

create or replace function app.staff_on_my_customer(p_profile_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from task_assignments a
                 join tasks t on t.id = a.task_id and t.deleted_at is null
                  where a.profile_id = p_profile_id
                    and t.customer_id = app.customer_id())
$$;

drop policy ta_select on task_assignments;
create policy ta_select on task_assignments for select to authenticated using (
  (select app.is_admin())
  or ((select app.user_kind()) = 'staff' and (select app.has_permission('tasks', 'view')))
  or profile_id = (select app.profile_id())
  or ((select app.user_kind()) = 'customer_user'
      and (select app.has('board.view_staffing'))
      and (select app.assignment_on_my_customer(task_id))));

drop policy profiles_select on profiles;
create policy profiles_select on profiles for select to authenticated using (
  (select app.is_admin())
  or user_id = (select auth.uid())
  or (deleted_at is null and (
    ((select app.user_kind()) = 'staff' and user_kind = 'staff')
    or ((select app.user_kind()) = 'customer_user' and customer_id = (select app.customer_id()))
    or ((select app.user_kind()) = 'customer_user'
        and (select app.has('board.view_staffing'))
        and (select app.staff_on_my_customer(profiles.id))))));

-- ===== 6. עובד קבלן רואה רק את המשימות שלו =================================
--
-- זרוע הקבלן בפוליסות הראייה נתנה עד היום לכל contractor_user את *כל* משימות
-- הקבלן. זה נכון למנהל הקבלן (portal.view), אבל עובד הקבלן אמור לראות — כמו
-- צוות — רק משימות שפורסמו ושהוא רשום עליהן ב-task_contractor_workers. ההבחנה
-- היא על ההרשאה portal.view (שיש למנהל ואין לעובד), לא על צורת הנתונים.
--
-- שתי הבדיקות "האם אני רשום על המשימה/האירוע הזה כעובד קבלן" עטופות בפונקציות
-- security definer, ולא בתת-שאילתה בתוך הפוליסה, מסיבה מחייבת: tcw_select
-- (0028) מפנה בעצמו אל tasks, ותת-שאילתה על task_contractor_workers בתוך
-- tasks_select הייתה יוצרת רקורסיה הדדית של פוליסות (tasks → tcw → tasks)
-- ש-Postgres חוסם בשגיאה. הפונקציה עוקפת RLS ומוגבלת ממילא לפרופיל הקורא,
-- בדיוק כמו app.is_my_contractor_staff (0019) ו-app.planned_shifts (0063).
create or replace function app.on_task_as_contractor_worker(p_task_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from task_contractor_workers w
    join profiles pr on pr.contractor_worker_id = w.contractor_worker_id
    where w.task_id = p_task_id and pr.id = app.profile_id())
$$;

create or replace function app.on_event_as_contractor_worker(p_event_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from tasks t
    join task_contractor_workers w on w.task_id = t.id
    join profiles pr on pr.contractor_worker_id = w.contractor_worker_id
    where t.event_id = p_event_id and t.deleted_at is null
      and pr.id = app.profile_id()
      and t.status_id = (select s.id from statuses s
                          where s.entity = 'task' and s.code = 'assigned'
                            and s.deleted_at is null limit 1))
$$;

-- הפוליסה משוכפלת מ-0063 מילה במילה, פרט לזרוע ה-contractor_user שבסוף.
drop policy tasks_select on tasks;
create policy tasks_select on tasks for select to authenticated using (
  (select app.is_admin())
  or (deleted_at is null
    and ((select app.scope_ids('tasks', 'customers')) is null
         or customer_id = any((select app.scope_ids('tasks', 'customers'))::uuid[]))
    and ((select app.scope_ids('tasks', 'contractors')) is null
         or contractor_id = any((select app.scope_ids('tasks', 'contractors'))::uuid[]))
    and ((select app.scope_ids('tasks', 'task_types')) is null
         or task_type_id = any((select app.scope_ids('tasks', 'task_types'))::uuid[]))
    and ((select app.scope_ids('tasks', 'statuses')) is null
         or status_id = any((select app.scope_ids('tasks', 'statuses'))::uuid[]))
    and ((select app.scope_ids('tasks', 'execution_methods')) is null
         or execution_method_id = any((select app.scope_ids('tasks', 'execution_methods'))::uuid[]))
    and ((select app.scope_ids('tasks', 'trucks')) is null
         or truck_id = any((select app.scope_ids('tasks', 'trucks'))::uuid[]))
    and ((select app.scope_date_from('tasks')) is null
         or task_date >= (select app.scope_date_from('tasks')))
    and ((select app.scope_date_to('tasks')) is null
         or task_date <= (select app.scope_date_to('tasks')))
    and (not (select app.scope_own('tasks'))
         or created_by = (select app.profile_id())
         or exists (select 1 from task_assignments a
                    where a.task_id = tasks.id and a.profile_id = (select app.profile_id())))
    and ((select app.user_kind()) <> 'staff'
         or (select app.can_plan_tasks())
         or created_by = (select app.profile_id())
         or status_id = (select s.id from statuses s
                          where s.entity = 'task' and s.code = 'assigned'
                            and s.deleted_at is null limit 1))
    and (
      ((select app.user_kind()) = 'staff' and (select app.has('tasks.view')))
      or ((select app.user_kind()) = 'customer_user' and customer_id = (select app.customer_id()))
      or ((select app.user_kind()) = 'contractor_user'
          and contractor_id = (select app.contractor_id())
          and ((select app.has('portal.view'))
               or (status_id = (select s.id from statuses s
                                 where s.entity = 'task' and s.code = 'assigned'
                                   and s.deleted_at is null limit 1)
                   and (select app.on_task_as_contractor_worker(tasks.id)))))
      or exists (select 1 from task_assignments a
                 where a.task_id = tasks.id and a.profile_id = (select app.profile_id()))
    )));

-- אותה הבחנה על אירועים: המנהל רואה כל אירוע שיש בו משימה של הקבלן; העובד רק
-- אירוע שיש בו משימה שפורסמה והוא רשום עליה. משוכפל מ-0013 פרט לזרוע האחרונה.
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
      ((select app.user_kind()) = 'staff' and (select app.has('events.view')))
      or ((select app.user_kind()) = 'customer_user' and customer_id = (select app.customer_id()))
      or ((select app.user_kind()) = 'contractor_user' and (
            ((select app.has('portal.view')) and exists (
               select 1 from tasks t where t.event_id = events.id
                 and t.contractor_id = (select app.contractor_id()) and t.deleted_at is null))
            or (select app.on_event_as_contractor_worker(events.id))))
    )));

-- ===== 7. כוונון התפקידים ==================================================
--
-- הכול בתבנית אינקרמנטלית (insert ... on conflict do update), ולא דרך
-- app.set_role_permissions — היא מוחקת את *כל* שורות התפקיד, כולל ההרשאות
-- שנוספו אחרי 0011 (attendance מ-0021/0024). כאן רק ההפרש נכתב.

-- 7א. מנהל לקוח — הרשאות עריכת המשימה (מלבד צוות, מחירים ופרסום), ראיית מחיר
-- לקריאה, דשבורד ולוח. 0011 סגר את מודול tasks עם דחיות מפורשות; ה-upsert
-- הופך את הרלוונטיות ל-allow.
insert into role_permissions (role_id, permission_key, allowed)
select r.id, k, true
from permission_roles r,
     unnest(array[
       'dashboard.view',
       'board.view', 'board.columns', 'board.view_staffing',
       'tasks.edit', 'tasks.reschedule', 'tasks.change_status', 'tasks.change_type',
       'tasks.change_worker_count', 'tasks.change_execution_method',
       'tasks.change_location', 'tasks.change_truck', 'tasks.edit_notes',
       'pricing.view'
     ]) k
where r.key = 'customer_manager'
on conflict (role_id, permission_key) do update set allowed = true;

-- ...ובמפורש: פרסום ("משובץ") ועריכת מחיר נשארים חסומים למנהל הלקוח. ה-kind
-- כבר חוסם את tasks.publish, וזו חגורה נוספת ברמת התפקיד.
insert into role_permissions (role_id, permission_key, allowed)
select r.id, k, false
from permission_roles r, unnest(array['tasks.publish', 'pricing.edit']) k
where r.key = 'customer_manager'
on conflict (role_id, permission_key) do update set allowed = false;

-- 7ב. עובד לקוח — צפייה בלבד. מוסיפים דשבורד ולוח; שום מפתח עריכה, ושום מפתח
-- כספי (pricing.view לא מוענק → נופל ל-false בברירת המחדל של הרישום).
insert into role_permissions (role_id, permission_key, allowed)
select r.id, k, true
from permission_roles r, unnest(array['dashboard.view', 'board.view', 'board.view_staffing']) k
where r.key = 'customer_viewer'
on conflict (role_id, permission_key) do update set allowed = true;

-- 7ג. צוות — worker / driver / team_lead: צפייה בלבד, בלי דשבורד. staff מקבל
-- dashboard.view בברירת המחדל של ה-kind (0004), ולכן צריך דחייה מפורשת.
insert into role_permissions (role_id, permission_key, allowed)
select r.id, 'dashboard.view', false
from permission_roles r where r.key in ('worker', 'driver', 'team_lead')
on conflict (role_id, permission_key) do update set allowed = false;

-- driver ו-team_lead קיבלו ב-0011 עריכת משימות ושינוי סטטוס. לפי המדיניות
-- הם צפייה בלבד — הופכים את שני המפתחות (וגם tasks.edit_notes ל-team_lead)
-- לדחיות, וממילא tasks.publish נחסם דרכם. worker כבר צופה.
insert into role_permissions (role_id, permission_key, allowed)
select r.id, k, false
from permission_roles r, unnest(array['tasks.edit', 'tasks.change_status', 'tasks.publish']) k
where r.key in ('driver', 'team_lead')
on conflict (role_id, permission_key) do update set allowed = false;

insert into role_permissions (role_id, permission_key, allowed)
select r.id, k, false
from permission_roles r, unnest(array['tasks.edit_notes', 'events.view']) k
where r.key = 'team_lead'
on conflict (role_id, permission_key) do update set allowed = false;

-- team_lead ראה עד היום את *כל* המשימות (tasks.view בלי היקף). כדי שיראה רק
-- את מה שהוא חלק ממנו — כמו worker ו-driver — מוסיפים לו היקף 'own' על
-- משימות ואירועים. שמור מ-הכפלה בהרצה חוזרת.
insert into permission_scopes (role_id, resource, scope_type)
select r.id, res.resource, 'own'::permission_scope_type
from permission_roles r
cross join (values ('tasks'), ('events')) as res(resource)
where r.key = 'team_lead'
  and not exists (
    select 1 from permission_scopes s
    where s.role_id = r.id and s.resource = res.resource and s.scope_type = 'own');

-- 7ד. עובד קבלן — כמו צוות, רואה את הלוח ואת לוח השנה (סעיף 6 מגביל אותם
-- למשימות שפורסמו ושהוא רשום עליהן). המודולים board ו-calendar לא נסגרו
-- לתפקיד ב-0019, ולכן ה-upsert מספיק.
insert into role_permissions (role_id, permission_key, allowed)
select r.id, k, true
from permission_roles r, unnest(array['board.view', 'calendar.view']) k
where r.key = 'contractor_worker'
on conflict (role_id, permission_key) do update set allowed = true;

-- ===== 8. שיוך תפקיד למשתמשי לקוח קיימים ===================================
--
-- אחרי שסגרנו את events.create/edit ברמת ה-kind (סעיף 3), משתמש לקוח קיים
-- בלי תפקיד היה נופל לצפייה בלבד ומאבד את היכולת שהייתה לו ליצור ולערוך
-- אירועים. משייכים לכל משתמש כזה את "מנהל לקוח" כברירת מחדל; אפשר להוריד
-- ידנית פר משתמש במסך המשתמשים.
insert into profile_roles (profile_id, role_id)
select p.id, (select id from permission_roles where key = 'customer_manager')
from profiles p
where p.user_kind = 'customer_user'
  and not exists (select 1 from profile_roles pr where pr.profile_id = p.id)
on conflict do nothing;
