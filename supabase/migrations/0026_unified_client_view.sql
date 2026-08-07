-- 0026: הלקוח חוזר למערכת אחת.
--
-- עד כאן משתמש לקוח קיבל עץ מסכים משלו (`/client/*`), ולכן ההבדל בינו לבין עובד
-- היה `user_kind` ולא הרשאה. אחרי המיגרציה הזו הוא נכנס לאותם מסכים כמו כולם,
-- וכל הבדל נובע ממפתח במרשם או מ-RLS. שלושה חלקים:
--
--   1. פתיחת `applies_to` למפתחות שהמסכים המשותפים דורשים. פתיחה היא *היתר
--      להעניק*, לא הענקה: `default_allowed` נשאר false ואין ברירות מחדל חדשות
--      לסוג המשתמש, ולכן אף לקוח קיים לא מקבל יכולת חדשה ביום השדרוג.
--   2. `dashboard_stats` הופכת לדשבורד היחיד — כל סקשן שהקורא אינו זכאי לו חוזר
--      null במקום להיחתך בקוד הדפדפן, בדיוק כמו `financial` ו-`revenue` היום.
--      `customer_dashboard` מתבטלת.
--   3. `get_my_permissions` מחזירה אילו סוגי משתמש הקורא רשאי ליצור, כדי
--      שטופס המשתמש המשותף לא יצטרך לשאול `user_kind` בדפדפן.

-- ===== 1. applies_to =========================================================

-- users.*: 0014 כבר בנתה את כל הפוליסות והטריגרים למקרה שבו לקוח מנהל את
-- המשתמשים של החברה שלו — `app.can_manage_profile`, `app.may_create_profile`,
-- `profiles_insert/update` ו-`guard_permission_grant`. מה שחסר היה שורה במרשם:
-- בלעדיה `useGroupedRegistry` הסתירה את המפתחות ממטריצת ההרשאות, ובלעדיה
-- `guard_permission_grant` סירב להענקה. זהו תיקון של חוסר-עקביות, לא הרחבה.
--
-- שלושה נשארים סגורים במכוון: set_admin (אף פעם לא נגזר ולא מואצל),
-- delete (מחיקת אדם היא החלטה של בעל המערכת) ו-manage_staff_roles
-- (עובד/נהג/ראש צוות — מושגים של הצוות, לא של הלקוח).
update permission_registry
   set applies_to = array['staff', 'customer_user']::user_kind[]
 where key in ('users.view', 'users.create', 'users.edit', 'users.view_contact',
               'users.manage_permissions', 'users.manage_scopes',
               'users.create_login', 'users.reset_password');

-- לוח העבודה: צפייה ובחירת עמודות. `work_board_view` היא security_invoker
-- ולכן השורות מסוננות ממילא, והעמודות שנשענות על join שה-RLS מרוקן (צוות,
-- ראש צוות, קבלן) נעלמות בצד הלקוח לפי המפתח שלהן. העריכה נשארת סגורה:
-- inline_edit ו-bulk_edit נגזרים מ-tasks.edit, ש-tasks_update לא מתיר ללקוח.
update permission_registry
   set applies_to = array['staff', 'customer_user']::user_kind[]
 where key in ('board.view', 'board.columns');

-- גרירת אירוע בלוח השנה. אפשרי רק מפני שהכתיבה עברה ל-update_event באותו
-- שינוי: כתיבה ישירה ל-events חסומה ללקוח מאז 0014, וה-RPC הוא המקום היחיד
-- שאוכף את קונפיגורציית הטופס פר-לקוח.
update permission_registry
   set applies_to = array['staff', 'customer_user']::user_kind[]
 where key = 'calendar.drag';

-- נוכחות: רק המפתחות האישיים. `ae_select` מתיר "הרשומות שלי" ללא תלות בסוג
-- המשתמש, ולכן איש קשר אצל לקוח שמחתים שעון עובד כמו כל אחד אחר.
--
-- attendance.view_all *לא* נפתח. לא מפני שהוא מסוכן — `ae_select` ו-
-- `attendance_report` (0024:382) שניהם מתנים את הענף הזה ב-user_kind = 'staff'
-- ולכן הענקה ללקוח לא הייתה מחזירה אף שורה — אלא בדיוק מפני שכך: מפתח שנראה
-- כאילו הוענק ואינו עושה דבר גרוע ממפתח שלא הוצע. פתיחת דוח הנוכחות ללקוח
-- מחייבת קודם ענף customer_user בשני המקומות, שמצמצם לעובדים ששובצו למשימות
-- של אותו לקוח.
--
-- ראוי לדעת: `board.view` נגזר מ-`tasks.view` ו-`calendar.drag` מ-
-- `events.change_date`, ושני התפקידים הקיימים ללקוח (customer_manager,
-- customer_viewer) מעניקים את המקורות. `app.has` אינו מסתכל על applies_to,
-- ולכן שני המסכים האלה נפתחים ללקוחות קיימים ברגע שההפניה ל-/client יורדת —
-- לא בגלל השורות כאן. זה מה שביקש בעל המוצר, וזו הסיבה שגרירת האירוע חייבת
-- לעבור ל-update_event באותו שינוי: אחרת הידית חיה והשמירה נכשלת.
update permission_registry
   set applies_to = array['staff', 'customer_user', 'contractor_user']::user_kind[]
 where key in ('attendance.view_own', 'attendance.view_schedule',
               'attendance.clock', 'attendance.view_own_pay');

-- עמודות הצוות בלוח העבודה. הן מגיעות מרוקנות ללקוח ממילא — ה-lateral joins
-- קוראים profiles, ו-profiles_select לא מחזירה לו עובדים — אבל "ריק" נראה כמו
-- לוח שבור ולא כמו עמודה שאינה שלו, ולכן צריך מפתח כדי להשמיט אותן.
--
-- מפתח חדש ולא tasks.assign.worker/contractors.view: התפקידים worker ו-driver
-- (0011:400-407) אינם מחזיקים אף אחד מהם ובכל זאת רואים את הצוות היום, ולכן
-- שימוש במפתחות הקיימים היה נסיגה לצוות. implied_by ריק בכוונה, וברירת המחדל
-- לסוג המשתמש היא מה ששומר על כולם — בדיוק המנגנון של 0011:297-308.
select app.register_permission('board.view_staffing', 'board', 'עמודות צוות, ראש צוות וקבלן',
  'מי משובץ למשימה ולאיזה קבלן היא הואצלה', 'field', false, false,
  array['staff']::user_kind[], null, 15);

insert into kind_permission_defaults (user_kind, permission_key, allowed) values
  ('staff', 'board.view_staffing', true),
  ('contractor_user', 'board.view_staffing', true)
on conflict (user_kind, permission_key) do nothing;

-- ===== 1ב. תפקיד הוא צרור הרשאות, ולכן הוא צריך את אותם שערים =============

-- `app.guard_permission_grant` (0014) שומר על user_permission_grants: אי אפשר
-- להעניק מפתח שאינך מחזיק, ולקוח מוגבל למפתחות שה-applies_to שלהם כולל אותו.
-- `profile_roles_write` לעומת זאת בדקה רק "יש לך users.manage_permissions" ו-
-- "זה משתמש שאתה מנהל" — ולא מה יש *בתוך* התפקיד. לכן צירוף תפקיד היה נתיב
-- עוקף: מי שמחזיק את המפתח יכול היה לצרף לתת-משתמש שלו את ops_manager.
--
-- הפער קיים כבר היום; פתיחת users.manage_permissions ללקוח במיגרציה הזו הופכת
-- אותו מתצורה שאפשר להגיע אליה בטעות לתצורה נתמכת, ולכן הוא נסגר כאן.
create or replace function app.guard_profile_role()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_row profile_roles; v_target_kind user_kind;
begin
  if auth.uid() is null or app.in_system_write() or app.is_admin() then
    return coalesce(new, old);
  end if;
  v_row := coalesce(new, old);

  if not app.can_manage_profile(v_row.profile_id) then
    raise exception 'אין לך הרשאה לנהל משתמש זה' using errcode = '42501';
  end if;
  if tg_op = 'DELETE' then return old; end if;

  -- תפקיד שנקשר לסוג משתמש אינו חל על סוג אחר
  select user_kind into v_target_kind from profiles where id = new.profile_id;
  if exists (select 1 from permission_roles r
              where r.id = new.role_id
                and r.user_kind is not null and r.user_kind <> v_target_kind) then
    raise exception 'התפקיד אינו מתאים לסוג המשתמש' using errcode = '42501';
  end if;

  -- אותו כלל של הענקה בודדת, מורם לרמת הצרור
  if exists (select 1 from role_permissions rp
              where rp.role_id = new.role_id and rp.allowed
                and not app.has(rp.permission_key)) then
    raise exception 'התפקיד כולל הרשאות שאין לך' using errcode = '42501';
  end if;

  if app.user_kind() = 'customer_user' and exists (
       select 1 from role_permissions rp
         join permission_registry r on r.key = rp.permission_key
        where rp.role_id = new.role_id and rp.allowed
          and not ('customer_user' = any (r.applies_to))) then
    raise exception 'התפקיד אינו זמין למשתמשי לקוח' using errcode = '42501';
  end if;
  return new;
end $$;

drop trigger if exists profile_roles_guard on profile_roles;
create trigger profile_roles_guard
  before insert or update or delete on profile_roles
  for each row execute function app.guard_profile_role();

-- ===== 2. הדשבורד היחיד =====================================================

-- גרף הקבלנים היה הסקשן היחיד בדשבורד בלי מפתח משלו, ולכן לא הייתה דרך להסתיר
-- אותו ממי שאינו רואה קבלנים. נגזר מ-contractors.view כדי שמי שכבר רואה אותם
-- ימשיך לראות את הגרף בלי הגדרה נוספת.
select app.register_permission('dashboard.contractors', 'dashboard', 'התפלגות קבלנים',
  'גרף המשימות לפי קבלן בדשבורד', 'field', false, false,
  array['staff']::user_kind[], 'contractors.view', 35);

-- SECURITY INVOKER: כל הספירות עוברות דרך פוליסות ה-SELECT, ולכן לקוח מקבל את
-- המספרים שלו מאותה שאילתה בלי שהיא תנקוב בלקוח כלשהו.
--
-- ההבדל מהגרסה הקודמת הוא שסקשן שאין לקורא מפתח עליו חוזר null ולא 0 או [].
-- ההבחנה חשובה: 0 אומר "אין", null אומר "לא בשבילך", והמסך מצייר את הראשון
-- ומשמיט את השני. `next_events` ושלוש הספירות שהצטרפו הגיעו מ-customer_dashboard
-- והן שימושיות לכולם, ולכן הן לא מותנות במפתח.
create or replace function dashboard_stats(p_from date, p_to date)
returns jsonb language sql stable security invoker set search_path = public as $$
  select jsonb_build_object(
    'events_count', (select count(*) from events
       where deleted_at is null and event_date between p_from and p_to),
    'events_upcoming', (select count(*) from events e
       left join statuses s on s.id = e.status_id
       where e.deleted_at is null and e.event_date >= current_date
         and not coalesce(s.is_terminal, false)),
    'events_done', (select count(*) from events e
       join statuses s on s.id = e.status_id
       where e.deleted_at is null and s.is_terminal
         and e.event_date between p_from and p_to),
    'tasks_count', (select count(*) from tasks
       where deleted_at is null and task_date between p_from and p_to),
    'tasks_open', (select count(*) from tasks t join statuses s on s.id = t.status_id
       where t.deleted_at is null and not s.is_terminal
         and t.task_date between p_from and p_to),
    'tasks_today', (select count(*) from tasks
       where deleted_at is null and task_date = current_date),
    'tasks_week', (select count(*) from tasks
       where deleted_at is null
         and task_date between date_trunc('week', current_date)::date
         and (date_trunc('week', current_date) + interval '6 days')::date),
    'tasks_overdue', (select count(*) from tasks t join statuses s on s.id = t.status_id
       where t.deleted_at is null and t.task_date < current_date and not s.is_terminal),
    -- מונה את סגל הצוות, ולכן שייך למי שרשאי לראות סטטיסטיקות של כל העובדים
    'available_workers', case when app.has('dashboard.all_workers') then
      (select count(*) from profiles p
         where p.deleted_at is null and p.is_active and p.user_kind = 'staff'
           and not exists (select 1 from task_assignments a join tasks t on t.id = a.task_id
                           where a.profile_id = p.id and t.task_date = current_date
                             and t.deleted_at is null))
      else null end,
    -- ללקוח יש לקוח אחד: הגרף היה עמודה בודדת ששמה את שם החברה שלו על המסך
    'by_customer', case when app.has('customers.view') then
      (select coalesce(jsonb_agg(row_to_json(x)), '[]') from (
         select c.name, c.color, count(*) as cnt from tasks t join customers c on c.id = t.customer_id
         where t.deleted_at is null and t.task_date between p_from and p_to
         group by c.name, c.color order by cnt desc limit 12) x)
      else null end,
    'by_contractor', case when app.has('dashboard.contractors') then
      (select coalesce(jsonb_agg(row_to_json(x)), '[]') from (
         select ct.name, count(*) as cnt from tasks t join contractors ct on ct.id = t.contractor_id
         where t.deleted_at is null and t.task_date between p_from and p_to
         group by ct.name order by cnt desc limit 12) x)
      else null end,
    'by_worker', case when app.has('dashboard.all_workers') then
      (select coalesce(jsonb_agg(row_to_json(x)), '[]') from (
         select p.full_name as name, count(*) as cnt
         from task_assignments a
         join tasks t on t.id = a.task_id and t.deleted_at is null
           and t.task_date between p_from and p_to
         join profiles p on p.id = a.profile_id
         group by p.full_name order by cnt desc limit 12) x)
      else null end,
    'financial', case when app.has('dashboard.financial') then
      (select jsonb_build_object(
         'expected', coalesce(sum(tct.price), 0),
         'paid', coalesce(sum(tct.paid_amount) filter (where tct.paid_at is not null), 0))
       from task_contractor_terms tct
       join tasks t on t.id = tct.task_id and t.deleted_at is null
        and t.task_date between p_from and p_to)
      else null end,
    'revenue', case when app.has('pricing.revenue') then
      (select jsonb_build_object(
         'total', coalesce(sum(tp.price), 0),
         'priced_tasks', count(*) filter (where tp.price is not null),
         'by_customer', case when app.has('customers.view') then
           (select coalesce(jsonb_agg(row_to_json(y)), '[]') from (
              select c.name, c.color, coalesce(sum(tp2.price), 0) as total
              from task_pricing tp2
              join tasks t2 on t2.id = tp2.task_id and t2.deleted_at is null
               and t2.task_date between p_from and p_to
              join customers c on c.id = t2.customer_id
              group by c.name, c.color order by 3 desc limit 12) y)
           else null end)
       from task_pricing tp
       join tasks t on t.id = tp.task_id and t.deleted_at is null
        and t.task_date between p_from and p_to)
      else null end,
    'by_status', (select coalesce(jsonb_agg(row_to_json(x)), '[]') from (
       select s.name, s.color, count(*) as cnt from tasks t join statuses s on s.id = t.status_id
       where t.deleted_at is null and t.task_date between p_from and p_to
       group by s.name, s.color order by cnt desc) x),
    'next_events', (select coalesce(jsonb_agg(row_to_json(x)), '[]') from (
       select e.id, e.event_date, e.end_client_name, e.event_number, e.location_text
       from events e
       where e.deleted_at is null and e.event_date >= current_date
       order by e.event_date limit 5) x))
$$;

drop function if exists customer_dashboard(date, date);

-- ===== 3. אילו סוגי משתמש מותר לי ליצור =====================================

-- טופס המשתמש המשותף צריך לדעת אם להציג בורר סוג משתמש בכלל. השאלה כבר נענית
-- ב-`app.may_create_profile`, שהיא גם מה ש-profiles_insert בודקת — ולכן הטופס
-- שואל אותה ולא את user_kind של הקורא, ואינו יכול להציע אפשרות שתידחה בכתיבה.
create or replace function get_my_permissions()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_profile profiles;
  v_caps jsonb; v_legacy jsonb; v_fields jsonb;
  v_roles jsonb; v_app_roles jsonb; v_customer jsonb; v_scopes jsonb; v_form jsonb;
  v_kinds jsonb;
begin
  select * into v_profile from profiles
    where user_id = auth.uid() and is_active and deleted_at is null;
  if v_profile.id is null then return null; end if;

  select coalesce(jsonb_object_agg(r.key, app.has(r.key)), '{}') into v_caps
    from permission_registry r where r.is_active;

  select coalesce(jsonb_object_agg(resource, actions), '{}') into v_legacy from (
    select split_part(r.key, '.', 1) as resource,
           jsonb_object_agg(substr(r.key, strpos(r.key, '.') + 1), app.has(r.key)) as actions
    from permission_registry r
    where r.is_active
      and substr(r.key, strpos(r.key, '.') + 1) in ('view', 'create', 'edit', 'delete')
    group by 1) x;

  select coalesce(jsonb_agg(jsonb_build_object(
      'entity', fr.entity, 'field_key', fr.field_key,
      'can_view', app.can_view_field(fr.entity, fr.field_key),
      'can_edit', app.can_edit_field(fr.entity, fr.field_key))), '[]') into v_fields
    from field_registry fr;

  select coalesce(jsonb_agg(role), '[]') into v_roles
    from staff_roles where profile_id = v_profile.id;

  select coalesce(jsonb_agg(jsonb_build_object(
      'id', r.id, 'key', r.key, 'name_he', r.name_he)), '[]') into v_app_roles
    from profile_roles pr join permission_roles r on r.id = pr.role_id
    where pr.profile_id = v_profile.id and r.is_active and r.deleted_at is null;

  select coalesce(jsonb_agg(jsonb_build_object(
      'resource', s.resource, 'scope_type', s.scope_type,
      'values', s.scope_values, 'days_back', s.days_back,
      'days_forward', s.days_forward)), '[]') into v_scopes
    from (select distinct resource from permission_scopes) res
    cross join lateral app.scope_rows(res.resource) s;

  if v_profile.customer_id is not null then
    select jsonb_build_object('id', c.id, 'name', c.name, 'color', c.color,
                              'can_create_events', c.can_create_events)
      into v_customer from customers c where c.id = v_profile.customer_id;
  end if;

  select coalesce(jsonb_agg(jsonb_build_object('field_key', field_key, 'state', state)), '[]')
    into v_form from app.form_config(v_profile.customer_id, v_profile.id);

  -- הלקוח והקבלן של הקורא מועברים כפי שהם: אצל עובד צוות הענף ב-
  -- may_create_profile אינו מסתכל עליהם, ואצל לקוח או קבלן זו בדיוק ההשוואה
  -- שהפונקציה עושה מול app.customer_id()/app.contractor_id().
  select coalesce(jsonb_agg(kind), '[]'::jsonb) into v_kinds from (
    select 'staff' as kind
      where app.may_create_profile('staff', null, null, false)
    union all
    select 'customer_user'
      where app.may_create_profile('customer_user', v_profile.customer_id, null, false)
    union all
    select 'contractor_user'
      where app.may_create_profile('contractor_user', null, v_profile.contractor_id, false)
  ) q;

  return jsonb_build_object(
    'profile', jsonb_build_object(
      'id', v_profile.id, 'full_name', v_profile.full_name,
      'user_kind', v_profile.user_kind, 'is_admin', v_profile.is_admin,
      'customer_id', v_profile.customer_id, 'contractor_id', v_profile.contractor_id,
      'phone', v_profile.phone, 'email', v_profile.email),
    'roles', v_roles,
    'app_roles', v_app_roles,
    'customer', v_customer,
    'permissions', v_legacy,
    'capabilities', v_caps,
    'creatable_user_kinds', v_kinds,
    'field_permissions', v_fields,
    'scopes', coalesce(v_scopes, '[]'::jsonb),
    'form_config', v_form);
end $$;
