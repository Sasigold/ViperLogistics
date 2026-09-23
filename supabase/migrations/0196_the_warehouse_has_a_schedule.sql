-- 0196: לו״ז מחסן — הכנה והחזרה לכל אירוע, ויוזר "מחסן" שרואה רק אותו
--
-- הדיווח: **"מודול חדש עבור לקוח ארקו שנקרא לו״ז מחסן. הוא נראה כמו לו״ז
-- העבודה: לכל אירוע יש משימת הכנה ומשימת החזרה. פתוח רק ללקוח ארקו. ויוזר
-- מחסן שרואה רק את לו״ז המחסן — כהרשאה, כך שמנהל הלקוח רואה אותו גם."**
--
-- **למה טבלה משלה ולא שתי משימות נוספות ב-`tasks`.** משימה ב-`tasks` היא
-- יחידה של עבודת שטח: היא מתומחרת (0017), נספרת במפת העומסים (0173), גוזרת
-- משמרות (0020), יוצאת לארקו בכל שינוי (0184/0195) ונרשמת ביומן האירוע.
-- הכנה במחסן אינה אף אחד מאלה — אין לה מחיר, אין עליה צוות משובץ, והיא אינה
-- שינוי באירוע שארקו צריכה לשמוע עליו. שתי שורות `tasks` נוספות היו נכנסות
-- לכל אחד מהצינורות האלה ודורשות החרגה בכל אחד מהם.
--
-- **השורה נולדת בעריכה הראשונה, לא בלידת האירוע.** הלו״ז בונה שתי עמודות
-- לכל אירוע של לקוח שהמודול פתוח לו, גם כשעוד אין שורה — ואז כל ערך הוא
-- ברירת המחדל שלו. כך אין טריגר על `events`, אין מילוי היסטורי, ואירוע שנולד
-- לפני המיגרציה מופיע בדיוק כמו אירוע שנולד אחריה.
--
-- **התאריך נגזר עד שמישהו קובע אותו.** ההכנה יושבת ביום ההקמה, וההחזרה ביום
-- הפירוק (ובהיעדרם — ביום האירוע). הזזת ההקמה מזיזה את ההכנה איתה, אלא אם
-- המחסן קבע לה יום משלו — ואז `task_date` מלא, והוא גובר.
--
-- **"פתוח רק לארקו" הוא דגל ולא שם.** כמו החיבור לארקו (0182), שום דבר כאן
-- אינו משווה לשם 'ארקו': הדגל `customers.warehouse_schedule_enabled` הוא
-- השער, והמיגרציה מדליקה אותו ללקוח ששמו מכיל "ארקו".
--
-- **המחסן הוא הרשאה ולא סוג משתמש.** שני מפתחות חדשים, `warehouse.view`
-- ו-`warehouse.edit`, ותפקיד חדש `customer_warehouse` ("מחסן") שמחזיק אותם
-- ורק אותם. מנהל אצל הלקוח מקבל את אותם שני מפתחות, ולכן רואה ועורך את אותו
-- לו״ז בדיוק; צופה אצל הלקוח רואה בלבד.

-- ===== 1. הדגל על הלקוח ==================================================

alter table customers
  add column warehouse_schedule_enabled boolean not null default false;

comment on column customers.warehouse_schedule_enabled is
  'האם מודול "לו״ז מחסן" פתוח ללקוח הזה (0196).';

update customers set warehouse_schedule_enabled = true
 where name like '%ארקו%' and deleted_at is null;

-- ===== 2. הטבלה ===========================================================

create type warehouse_task_kind as enum ('prep', 'return');

create table warehouse_tasks (
  id              uuid primary key default gen_random_uuid(),
  event_id        uuid not null references events(id) on delete cascade,
  -- מועתק מהאירוע בלידה, כדי שהפוליסה לא תצטרך join. אירוע אינו עובר לקוח
  -- בפועל (events.change_customer סגור ללקוח), ו-`warehouse_task_save` מיישר
  -- אותו מחדש בכל כתיבה בכל מקרה.
  customer_id     uuid not null references customers(id),
  kind            warehouse_task_kind not null,
  -- null = נגזר (יום ההקמה/הפירוק, ואז יום האירוע). מלא = המחסן קבע.
  task_date       date,
  start_time      time,
  duration_hours  numeric(5,2) check (duration_hours is null or duration_hours between 0 and 72),
  notes           text,
  final_approved  boolean not null default false,
  event_ready     boolean not null default false,
  checked         boolean not null default false,
  updated_by      uuid references profiles(id),
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  unique (event_id, kind)
);

comment on table warehouse_tasks is
  'לו״ז מחסן (0196): הכנה והחזרה לכל אירוע. שורה נולדת בעריכה הראשונה.';

create index warehouse_tasks_customer_idx on warehouse_tasks (customer_id);

create trigger warehouse_tasks_updated before update on warehouse_tasks
  for each row execute function app.set_updated_at();
create trigger warehouse_tasks_audit after insert or update or delete
  on warehouse_tasks for each row execute function app.audit();

-- ===== 3. ההרשאות ========================================================

select app.register_module('warehouse', 'לו״ז מחסן',
  'הכנה והחזרה של הציוד במחסן לכל אירוע', 'Warehouse', 35);

select app.register_permission('warehouse.view', 'warehouse',
  'צפייה בלו״ז המחסן',
  'משימות ההכנה וההחזרה של כל אירוע, אצל לקוח שהמודול פתוח לו',
  'access', false, false, array['staff', 'customer_user']::user_kind[], null, 10);

select app.register_permission('warehouse.edit', 'warehouse',
  'עדכון לו״ז המחסן',
  'שעה, זמן, הערות, אישור סופי, אירוע מוכן ובדיקה',
  'action', false, false, array['staff', 'customer_user']::user_kind[], 'warehouse.view', 20);

-- תפקיד "מחסן": שני המפתחות, ההתראות — וכל השאר נסגר במפורש. בדיוק כמו
-- `customer_worker` (0178): `p_close_modules` על כל המודולים הפעילים כותב
-- דחייה לכל מפתח שלא נמנה, וכך ברירות המחדל של `customer_user` (הדשבורד,
-- האירועים, לוח השנה) אינן זולגות אל מי שאמור לראות מחסן ורק מחסן.
insert into permission_roles (key, name_he, description_he, user_kind, is_system, sort_order)
values ('customer_warehouse', 'מחסן',
        'רואה ומעדכן את לו״ז המחסן של הלקוח שלו — ורק אותו',
        'customer_user', true, 116)
on conflict (key) do update set
  name_he = excluded.name_he,
  description_he = excluded.description_he,
  sort_order = excluded.sort_order;

select app.set_role_permissions('customer_warehouse',
  array['warehouse.view', 'warehouse.edit', 'notifications.view', 'notifications.preferences'],
  (select array_agg(distinct module) from permission_registry where is_active));

-- מנהל אצל הלקוח רואה את מה שהמחסן רואה ועורך אותו; צופה — רואה.
-- ובצד המשרד: מי שמנהל את התפעול או משבץ אותו.
insert into role_permissions (role_id, permission_key, allowed)
select r.id, k, true
from permission_roles r, unnest(array['warehouse.view', 'warehouse.edit']) k
where r.key in ('customer_manager', 'ops_manager', 'dispatcher')
on conflict (role_id, permission_key) do update set allowed = true;

-- ‏`warehouse.edit` נגזר מ-`warehouse.view` (implied_by), ולכן צופה שקיבל
-- את הצפייה היה יורש גם את העריכה. דחייה מפורשת בתפקיד גוברת על הירושה.
insert into role_permissions (role_id, permission_key, allowed)
select r.id, k.key, k.allowed
from permission_roles r,
     (values ('warehouse.view', true), ('warehouse.edit', false)) k(key, allowed)
where r.key in ('customer_viewer', 'viewer')
on conflict (role_id, permission_key) do update set allowed = excluded.allowed;

-- ההיקף, בדיוק כמו ל-`customer_worker` (0178): זרוע הלקוח בפוליסות של
-- `events` ו-`tasks` פותחת כל שורה של הלקוח, והיוזר "מחסן" אינו אמור לראות
-- אף אחת מהן — רק את מה ש-`warehouse_schedule` מחזירה לו. ‏`own` מצמצם
-- אותו למה ששובץ אליו, כלומר לכלום.
insert into permission_scopes (role_id, resource, scope_type)
select r.id, res.resource, 'own'::permission_scope_type
from permission_roles r
cross join (values ('tasks'), ('events')) as res(resource)
where r.key = 'customer_warehouse'
  and not exists (select 1 from permission_scopes s
                   where s.role_id = r.id and s.resource = res.resource
                     and s.scope_type = 'own');

-- ===== 4. מי רואה איזה לקוח ==============================================
--
-- פונקציה אחת שעונה לשלוש הכניסות — הפוליסה, הקריאה והכתיבה — כדי שלא
-- יהיו שלוש גרסאות של אותה שאלה. אדמין ואיש צוות עם המפתח: כל לקוח שהמודול
-- פתוח לו. משתמש לקוח: הלקוח שלו, אם המודול פתוח לו. קבלן: אף אחד.
create or replace function app.warehouse_customer_visible(p_customer_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from customers c
     where c.id = p_customer_id
       and c.warehouse_schedule_enabled
       and c.deleted_at is null)
    and app.has('warehouse.view')
    and (app.is_admin()
         or app.user_kind() = 'staff'
         or (app.user_kind() = 'customer_user' and p_customer_id = app.customer_id()))
$$;

revoke execute on function app.warehouse_customer_visible(uuid) from anon;
grant execute on function app.warehouse_customer_visible(uuid) to authenticated;

alter table warehouse_tasks enable row level security;

-- קריאה בלבד. כל כתיבה עוברת ב-`warehouse_task_save`, שבודקת את
-- `warehouse.edit` ומיישרת את `customer_id` מול האירוע.
create policy warehouse_tasks_select on warehouse_tasks for select to authenticated
  using ((select app.warehouse_customer_visible(customer_id)));

grant select on warehouse_tasks to authenticated;

-- ===== 5. הלו״ז ==========================================================
--
-- שתי שורות לכל אירוע בטווח — `prep` ו-`return` — בין שיש להן שורה בטבלה
-- ובין שאין. התאריך האפקטיבי הוא מה שהטווח נמדד מולו, ולכן חלון האירועים
-- רחב ממנו בחודש לכל צד: הכנה שנקבעה שבוע לפני אירוע עדיין נמצאת.
create or replace function warehouse_schedule(p_from date, p_to date)
returns table (
  event_id        uuid,
  kind            warehouse_task_kind,
  customer_id     uuid,
  customer_name   text,
  customer_color  text,
  event_number    text,
  end_client_name text,
  event_date      date,
  task_date       date,
  date_is_manual  boolean,
  start_time      time,
  duration_hours  numeric,
  notes           text,
  final_approved  boolean,
  event_ready     boolean,
  checked         boolean,
  updated_at      timestamptz)
language sql stable security definer set search_path = public as $$
  with ev as (
    select e.id, e.customer_id, e.event_number, e.end_client_name, e.event_date,
           c.name as customer_name, c.color as customer_color
      from events e
      join customers c on c.id = e.customer_id
     where e.deleted_at is null
       and e.status_id is distinct from (select app.cancelled_event_status_id())
       and e.event_date between p_from - 31 and p_to + 31
       and app.warehouse_customer_visible(e.customer_id)
  ),
  anchors as (
    select ev.*,
           (select min(t.task_date) from tasks t join task_types tt on tt.id = t.task_type_id
             where t.event_id = ev.id and t.deleted_at is null and tt.code = 'setup') as setup_date,
           (select max(t.task_date) from tasks t join task_types tt on tt.id = t.task_type_id
             where t.event_id = ev.id and t.deleted_at is null and tt.code = 'teardown') as teardown_date
      from ev
  ),
  wr as (
    select a.id as event_id, k.kind, a.customer_id, a.customer_name, a.customer_color,
           a.event_number, a.end_client_name, a.event_date,
           coalesce(w.task_date,
                    case k.kind when 'prep' then a.setup_date else a.teardown_date end,
                    a.event_date) as task_date,
           w.task_date is not null as date_is_manual,
           w.start_time, coalesce(w.duration_hours, 0) as duration_hours, w.notes,
           coalesce(w.final_approved, false) as final_approved,
           coalesce(w.event_ready, false) as event_ready,
           coalesce(w.checked, false) as checked,
           w.updated_at
      from anchors a
      cross join (values ('prep'::warehouse_task_kind), ('return'::warehouse_task_kind)) k(kind)
      left join warehouse_tasks w on w.event_id = a.id and w.kind = k.kind
  )
  select * from wr
   where task_date between p_from and p_to
   order by task_date, start_time nulls last, kind, event_number
$$;

comment on function warehouse_schedule(date, date) is
  'לו״ז המחסן בטווח (0196): הכנה והחזרה לכל אירוע של לקוח שהמודול פתוח לו.';

revoke execute on function warehouse_schedule(date, date) from anon, public;
grant execute on function warehouse_schedule(date, date) to authenticated;

-- ===== 6. הכתיבה =========================================================
--
-- ‏`p_patch` נושא רק את מה שהשתנה. מפתח שאינו מוכר נדחה ולא מתעלמים ממנו —
-- תא שכתב לשדה שאינו קיים צריך לשמוע על זה, ולא לראות "נשמר".
create or replace function warehouse_task_save(
  p_event_id uuid, p_kind warehouse_task_kind, p_patch jsonb)
returns warehouse_tasks language plpgsql security definer set search_path = public as $$
declare
  v_customer uuid;
  v_row warehouse_tasks;
  v_bad text;
begin
  if not app.has('warehouse.edit') then
    raise exception 'אין לך הרשאה לעדכן את לו״ז המחסן' using errcode = '42501';
  end if;

  select e.customer_id into v_customer
    from events e
   where e.id = p_event_id and e.deleted_at is null;
  if v_customer is null or not app.warehouse_customer_visible(v_customer) then
    raise exception 'האירוע לא נמצא' using errcode = 'P0002';
  end if;

  select k into v_bad from jsonb_object_keys(coalesce(p_patch, '{}'::jsonb)) k
   where k not in ('task_date', 'start_time', 'duration_hours', 'notes',
                   'final_approved', 'event_ready', 'checked')
   limit 1;
  if v_bad is not null then
    raise exception 'שדה לא מוכר בלו״ז המחסן: %', v_bad using errcode = '22023';
  end if;

  insert into warehouse_tasks (event_id, customer_id, kind)
  values (p_event_id, v_customer, p_kind)
  on conflict (event_id, kind) do nothing;

  update warehouse_tasks w set
    customer_id    = v_customer,
    task_date      = case when p_patch ? 'task_date'
                          then nullif(p_patch->>'task_date', '')::date else w.task_date end,
    start_time     = case when p_patch ? 'start_time'
                          then nullif(p_patch->>'start_time', '')::time else w.start_time end,
    duration_hours = case when p_patch ? 'duration_hours'
                          then nullif(p_patch->>'duration_hours', '')::numeric else w.duration_hours end,
    notes          = case when p_patch ? 'notes'
                          then nullif(btrim(p_patch->>'notes'), '') else w.notes end,
    final_approved = case when p_patch ? 'final_approved'
                          then coalesce((p_patch->>'final_approved')::boolean, false) else w.final_approved end,
    event_ready    = case when p_patch ? 'event_ready'
                          then coalesce((p_patch->>'event_ready')::boolean, false) else w.event_ready end,
    checked        = case when p_patch ? 'checked'
                          then coalesce((p_patch->>'checked')::boolean, false) else w.checked end,
    updated_by     = app.profile_id()
  where w.event_id = p_event_id and w.kind = p_kind
  returning * into v_row;

  return v_row;
end $$;

comment on function warehouse_task_save(uuid, warehouse_task_kind, jsonb) is
  'עדכון משימת הכנה/החזרה בלו״ז המחסן (0196). יוצר את השורה אם אינה קיימת.';

revoke execute on function warehouse_task_save(uuid, warehouse_task_kind, jsonb) from anon, public;
grant execute on function warehouse_task_save(uuid, warehouse_task_kind, jsonb) to authenticated;

-- ===== 7. המסך צריך לדעת שהמודול פתוח ללקוח שלו ==========================
--
-- ‏`get_my_permissions` מועתקת מ-0178 מילה במילה, והשינוי היחיד הוא שדה
-- אחד באובייקט הלקוח — כמו `performed_by_enabled` ב-0133: התפריט מציג
-- "לו״ז מחסן" למשתמש לקוח רק כשהדגל דלוק אצל הלקוח שלו.
create or replace function get_my_permissions()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_profile profiles;
  v_caps jsonb; v_legacy jsonb; v_fields jsonb;
  v_roles jsonb; v_app_roles jsonb; v_customer jsonb; v_scopes jsonb; v_form jsonb;
  v_kinds jsonb; v_board jsonb;
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
                              'can_create_events', c.can_create_events,
                              -- ‏0133: המסך צריך לדעת אם הלקוח הזה מבצע בעצמו,
                              -- כדי להציג לו את "הסגל שלי" ואת בורר "בוצע ע״י".
                              'performed_by_enabled', c.performed_by_enabled,
                              -- ‏0196: ואם לו״ז המחסן פתוח לו.
                              'warehouse_schedule_enabled', c.warehouse_schedule_enabled)
      into v_customer from customers c where c.id = v_profile.customer_id;
  end if;

  select coalesce(jsonb_agg(jsonb_build_object('field_key', field_key, 'state', state)), '[]')
    into v_form from app.form_config(v_profile.customer_id, v_profile.id);

  -- ‏0109: ריק לאיש צוות, ולכן הלוח שלו נשלט במפתחות כפי שהיה תמיד.
  select coalesce(jsonb_agg(jsonb_build_object('field_key', field_key, 'state', state)), '[]')
    into v_board from app.board_config(v_profile.customer_id);

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
      -- ‏0178: החשבון שהוא עובד בסגל הלקוח נושא את שורת הסגל שלו,
      -- והמסך שואל אותה כדי לדעת שהוא עובד ולא מנהל.
      'customer_worker_id', v_profile.customer_worker_id,
      'phone', v_profile.phone, 'email', v_profile.email),
    'roles', v_roles,
    'app_roles', v_app_roles,
    'customer', v_customer,
    'permissions', v_legacy,
    'capabilities', v_caps,
    'creatable_user_kinds', v_kinds,
    'field_permissions', v_fields,
    'scopes', coalesce(v_scopes, '[]'::jsonb),
    'form_config', v_form,
    'board_config', v_board);
end $$;
