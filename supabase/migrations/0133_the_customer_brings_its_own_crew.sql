-- 0133: לקוח שמבצע בעצמו — רשומת סגל משלו
--
-- ‏0120 נתן למשימה את השאלה "מי מבצע: וייפר או ארקו", אבל ארקו היא **לקוח**
-- במערכת ואין לה אף עובד. הדיווח: **"במשימה שסומנה שארקו מבצעים, שארקו יוכלו
-- דרך הלוז עבודה להוסיף ולערוך עובדים, ראשי צוותי, משאיות, ונהגים."**
--
-- **רשומת סגל של הלקוח, ולא מימוש שלו כקבלן.** קבלן הוא ישות כספית: הוא נושא
-- תעריפים, האצלות, קנסות, תשלומים ופורטל. לארקו אין דבר מכל זה — מחיר המשימה
-- שלה הוא 0 (0120) והיא אינה מקבלת מוייפר שקל. שלוש טבלאות במקביל מדויק
-- לרשומת הקבלן עולות פחות מלגרור את כל המשמעות הכספית לאן שהיא אינה שייכת.
--
-- **הדגל הוא השער, לא התפקיד.** שני המפתחות החדשים נכנסים לתפקיד
-- `customer_manager`, שהוא של כל לקוח — ולכן כל מדיניות וכל בדיקה כאן שואלת
-- גם את `customers.performed_by_enabled`. לקוח שאינו מבצע בעצמו אינו מקבל
-- רשומת סגל גם אם המפתח בידו, ואינו רואה את המסך.
--
-- **ומה שאינו כאן, במפורש:** נוכחות, שכר ותמחור. סגל הלקוח אינו מוחתם בשעון
-- ואינו נכנס ל-`app.attendance_calc` — הוא עובד של הלקוח, לא של וייפר, ואין
-- לוייפר מה לשלם לו ולא מה למדוד. אין לו גם חשבון התחברות: הוא שם ברשימה,
-- כמו עובד קבלן בלי אפליקציה.

-- ===== 1. הסכמה =========================================================

create table customer_workers (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references customers(id),
  full_name text not null,
  phone text,
  id_number text,
  is_active boolean not null default true,
  deleted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index customer_workers_customer_idx on customer_workers (customer_id) where deleted_at is null;
create trigger customer_workers_updated before update on customer_workers
  for each row execute function app.set_updated_at();

comment on table customer_workers is
  'סגל העובדים של לקוח שמבצע בעצמו (0133). מקביל ל-contractor_workers, בלי '
  'שום משמעות כספית: אין תעריף, אין נוכחות ואין חשבון התחברות.';

-- התפקיד הוא הגדרה, בדיוק כמו ב-0121: אי אפשר לשבץ עובד כראש צוות או כנהג
-- אם לא הוגדר ככזה.
create table customer_worker_roles (
  customer_worker_id uuid not null references customer_workers(id) on delete cascade,
  role staff_role not null,
  primary key (customer_worker_id, role)
);

-- והשיבוץ בפועל. ‏`truck_id` כאן ולא על המשימה: המשאית של *הנהג* היא של
-- הנהג, בדיוק כמו `task_assignments.truck_id` בצוות הפנימי.
create table task_customer_workers (
  task_id uuid not null references tasks(id) on delete cascade,
  customer_worker_id uuid not null references customer_workers(id),
  work_site text not null default 'field' check (work_site in ('field', 'warehouse')),
  role staff_role,
  truck_id uuid references trucks(id),
  created_at timestamptz not null default now(),
  primary key (task_id, customer_worker_id)
);
create index task_customer_workers_worker_idx on task_customer_workers (customer_worker_id);
create unique index task_customer_workers_one_lead
  on task_customer_workers (task_id) where role = 'team_lead';

-- ===== 2. המפתחות =======================================================

select app.register_permission('customers.manage_own_staff', 'customers',
  'ניהול סגל העובדים שלי',
  'הוספה ועריכה של העובדים, ראשי הצוות והנהגים של הלקוח שמבצע בעצמו',
  'action', false, false,
  array['staff', 'customer_user']::user_kind[], null, 190);

select app.register_permission('customers.assign_own_staff', 'customers',
  'שיבוץ סגל העובדים שלי',
  'שיבוץ אותו סגל למשימות שסומנו "בוצע ע״י" הלקוח',
  'action', false, false,
  array['staff', 'customer_user']::user_kind[], null, 191);

-- שני המפתחות לתפקיד מנהל הלקוח. השער בפועל הוא הדגל פר-לקוח, ולכן ההענקה
-- הרחבה כאן אינה פותחת דבר ללקוח שאינו מבצע בעצמו.
insert into role_permissions (role_id, permission_key, allowed)
select r.id, k, true
from permission_roles r,
     unnest(array['customers.manage_own_staff', 'customers.assign_own_staff']) k
where r.key = 'customer_manager'
on conflict (role_id, permission_key) do update set allowed = true;

-- ===== 3. מי הלקוח שאני מנהל את הסגל שלו ================================
--
-- שאלה אחת שחוזרת בכל פוליסה וב-RPC, ולכן היא נכתבת פעם אחת: הלקוח של הקורא,
-- אבל רק אם הוא לקוח שמבצע בעצמו. `security definer` כי `customers` עצמה
-- מוגנת ב-RLS, ופוליסה שקוראת אותה הייתה נכנסת למעגל.
create or replace function app.own_staff_customer_id() returns uuid
language sql stable security definer set search_path = public as $$
  select c.id from customers c
   where c.id = app.customer_id()
     and c.performed_by_enabled
     and c.deleted_at is null
$$;

comment on function app.own_staff_customer_id() is
  'הלקוח שהקורא מנהל את סגלו (0133): הלקוח שלו, ורק אם הוא מסומן כמבצע בעצמו.';

revoke execute on function app.own_staff_customer_id() from anon, public;
grant execute on function app.own_staff_customer_id() to authenticated;

-- ===== 4. RLS ===========================================================

alter table customer_workers enable row level security;
alter table customer_worker_roles enable row level security;
alter table task_customer_workers enable row level security;

-- הקריאה: המשרד על כל הלקוחות (הלו״ז שלו מציג משימות של כמה לקוחות),
-- והלקוח על שלו.
create policy cuw_select on customer_workers for select to authenticated using (
  (select app.is_admin())
  or ((select app.user_kind()) = 'staff' and (select app.has('customers.view')))
  or customer_id = (select app.own_staff_customer_id()));

create policy cuw_staff_write on customer_workers for all to authenticated
  using ((select app.is_admin()) or (select app.has('customers.edit')))
  with check ((select app.is_admin()) or (select app.has('customers.edit')));

create policy cuw_own_write on customer_workers for all to authenticated
  using (customer_id = (select app.own_staff_customer_id())
         and (select app.has('customers.manage_own_staff')))
  with check (customer_id = (select app.own_staff_customer_id())
              and (select app.has('customers.manage_own_staff')));

-- התפקידים יורשים בדיוק את ההרשאה של שורת העובד.
create policy cuwr_select on customer_worker_roles for select to authenticated using (
  exists (select 1 from customer_workers w where w.id = customer_worker_id));

create policy cuwr_staff_write on customer_worker_roles for all to authenticated
  using ((select app.is_admin()) or (select app.has('customers.edit')))
  with check ((select app.is_admin()) or (select app.has('customers.edit')));

create policy cuwr_own_write on customer_worker_roles for all to authenticated
  using (exists (select 1 from customer_workers w
                  where w.id = customer_worker_id
                    and w.customer_id = (select app.own_staff_customer_id()))
         and (select app.has('customers.manage_own_staff')))
  with check (exists (select 1 from customer_workers w
                       where w.id = customer_worker_id
                         and w.customer_id = (select app.own_staff_customer_id()))
              and (select app.has('customers.manage_own_staff')));

-- השיבוץ נקרא בידי כל מי שהמשימה נפתחת לו — ה-exists על `tasks` הוא שמחיל
-- את כל היקפי הראייה, בדיוק כמו במפרט (0102). הכתיבה עוברת ב-RPC בלבד
-- (`security definer`), ולכן אין כאן זרוע ללקוח: שער אחד, ולא שניים שיסתרו.
create policy tcuw_select on task_customer_workers for select to authenticated using (
  exists (select 1 from tasks t where t.id = task_id));

create policy tcuw_staff_write on task_customer_workers for all to authenticated
  using ((select app.is_admin()) or (select app.has('tasks.assign.worker')))
  with check ((select app.is_admin()) or (select app.has('tasks.assign.worker')));

-- ===== 5. שיבוץ הסגל למשימה =============================================
--
-- תאום של `contractor_assign_worker` (0121/0128), עם אותו סדר בדיקות ואותה
-- כתיבת upsert. ההבדל היחיד שנוגע למשמעות: **המשימה חייבת להיות מסומנת
-- כמבוצעת בידי הלקוח.** זה מה שהופך את הסגל הזה לרלוונטי לה מלכתחילה.
create or replace function customer_assign_worker(
  p_task_id uuid,
  p_worker_id uuid,
  p_on boolean default true,
  p_work_site text default null,
  p_role staff_role default null,
  p_truck_id uuid default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_task    tasks%rowtype;
  v_ctr     uuid;
  v_site    text := coalesce(p_work_site, 'field');
  v_enabled boolean;
begin
  select * into v_task from tasks where id = p_task_id and deleted_at is null;
  if v_task.id is null then
    raise exception 'המשימה לא נמצאה' using errcode = '42501';
  end if;

  select coalesce(performed_by_enabled, false) into v_enabled
    from customers where id = v_task.customer_id;

  if not coalesce(v_enabled, false) then
    raise exception 'האפשרות "בוצע ע"י" אינה מופעלת ללקוח זה';
  end if;
  if v_task.performed_by = 'viper' then
    raise exception 'הסגל של הלקוח משובץ רק למשימה שסומנה שהוא מבצע אותה';
  end if;

  -- מי רשאי: מנהל מערכת, איש משרד שמשבץ, או הלקוח על המשימות שלו עצמו.
  if not (app.is_admin()
          or (app.user_kind() = 'staff' and app.has('tasks.assign.worker'))
          or (app.user_kind() = 'customer_user'
              and v_task.customer_id = app.customer_id()
              and app.has('customers.assign_own_staff'))) then
    raise exception 'אין לך הרשאה לשבץ את סגל הלקוח' using errcode = '42501';
  end if;

  -- העובד חייב להיות של אותו לקוח.
  select customer_id into v_ctr from customer_workers
   where id = p_worker_id and deleted_at is null and is_active;
  if v_ctr is null then
    raise exception 'העובד לא נמצא' using errcode = '42501';
  end if;
  if v_ctr is distinct from v_task.customer_id then
    raise exception 'העובד אינו שייך ללקוח של המשימה' using errcode = '42501';
  end if;

  if not p_on then
    delete from task_customer_workers
     where task_id = p_task_id and customer_worker_id = p_worker_id;
    return p_worker_id;
  end if;

  -- התפקיד הוא הגדרה ואז שיבוץ (0121). null = עובד רגיל.
  if p_role in ('team_lead', 'driver')
     and not exists (select 1 from customer_worker_roles
                      where customer_worker_id = p_worker_id and role = p_role) then
    raise exception 'העובד אינו מוגדר בתפקיד המבוקש' using errcode = '42501';
  end if;

  -- ראש צוות אחד למשימה, על שלושת המאגרים (0128).
  if p_role = 'team_lead' then
    if exists (select 1 from task_assignments a
                where a.task_id = p_task_id and a.role = 'team_lead')
       or exists (select 1 from task_contractor_workers tcw
                   where tcw.task_id = p_task_id and tcw.role = 'team_lead')
       or exists (select 1 from task_customer_workers x
                   where x.task_id = p_task_id and x.role = 'team_lead'
                     and x.customer_worker_id is distinct from p_worker_id) then
      raise exception 'למשימה כבר מוגדר ראש צוות' using errcode = '42501';
    end if;
  end if;

  if v_site not in ('field', 'warehouse') then
    raise exception 'אתר עבודה לא חוקי: %', v_site using errcode = '22023';
  end if;

  -- המשאית של הנהג מוגבלת לרשימת המשאיות של הלקוח, כשיש כזו (0116). רשימה
  -- ריקה = כל הקטלוג, בדיוק כמו בתא המשאיות של הלו״ז.
  if p_truck_id is not null then
    if not exists (select 1 from trucks t where t.id = p_truck_id and t.deleted_at is null) then
      raise exception 'המשאית לא נמצאה' using errcode = '42501';
    end if;
    if exists (select 1 from customer_trucks where customer_id = v_task.customer_id)
       and not exists (select 1 from customer_trucks
                        where customer_id = v_task.customer_id and truck_id = p_truck_id) then
      raise exception 'המשאית אינה ברשימת המשאיות של הלקוח' using errcode = '42501';
    end if;
  end if;

  insert into task_customer_workers (task_id, customer_worker_id, work_site, role, truck_id)
  values (p_task_id, p_worker_id, v_site, p_role, p_truck_id)
  on conflict (task_id, customer_worker_id) do update
    set work_site = excluded.work_site,
        role      = excluded.role,
        truck_id  = excluded.truck_id;

  return p_worker_id;
end $$;

comment on function customer_assign_worker(uuid, uuid, boolean, text, staff_role, uuid) is
  'שיבוץ עובד מסגל הלקוח למשימה שסומנה שהוא מבצע אותה (0133).';

revoke execute on function
  public.customer_assign_worker(uuid, uuid, boolean, text, staff_role, uuid) from anon, public;
grant execute on function
  public.customer_assign_worker(uuid, uuid, boolean, text, staff_role, uuid) to authenticated;

-- ===== 6. הסגל הניתן לשיבוץ =============================================
create or replace function customer_assignable_workers(p_customer_id uuid default null)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_cus uuid := coalesce(p_customer_id, app.own_staff_customer_id());
begin
  if v_cus is null then return '[]'::jsonb; end if;

  -- לקוח קורא רק על עצמו; איש משרד צריך את המפתח.
  if v_cus is distinct from app.own_staff_customer_id()
     and not app.is_admin() and not app.has('customers.view') then
    return '[]'::jsonb;
  end if;

  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'worker_id', w.id,
             'full_name', w.full_name,
             'phone',     w.phone,
             'roles',     coalesce((select jsonb_agg(r.role order by r.role)
                                      from customer_worker_roles r
                                     where r.customer_worker_id = w.id), '[]'::jsonb))
           order by w.full_name)
      from customer_workers w
     where w.customer_id = v_cus and w.deleted_at is null and w.is_active
  ), '[]'::jsonb);
end $$;

revoke execute on function public.customer_assignable_workers(uuid) from anon, public;
grant execute on function public.customer_assignable_workers(uuid) to authenticated;

-- ===== 7. יומן ביקורת ===================================================
create trigger customer_workers_audit after insert or update or delete
  on customer_workers for each row execute function app.audit();
create trigger customer_worker_roles_audit after insert or update or delete
  on customer_worker_roles for each row execute function app.audit();

-- ===== 8. הדגל מגיע ללקוח עם ההרשאות =====================================
--
-- ‏`performed_by_enabled` היה עד כה נקרא רק דרך שורת האירוע
-- (`EventDetailPage`), ולכן שום מסך אחר לא ידע אם הלקוח מבצע בעצמו — לא
-- התפריט, ולא טופס יצירת האירוע. הוא נוסע עכשיו עם `get_my_permissions`,
-- שהוא ממילא מה שכל מסך מקבל בעלייה. הגוף זהה ל-0109 פרט לשדה אחד.
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
                              'performed_by_enabled', c.performed_by_enabled)
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
