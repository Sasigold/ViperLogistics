-- 0006: RPC functions
-- ===== login bootstrap: resolved permissions + profile in one round trip =====
create or replace function get_my_permissions()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_profile profiles;
  v_perms jsonb;
  v_fields jsonb;
  v_roles jsonb;
  v_customer jsonb;
begin
  select * into v_profile from profiles
    where user_id = auth.uid() and is_active and deleted_at is null;
  if v_profile.id is null then return null; end if;

  select coalesce(jsonb_object_agg(resource, actions), '{}') into v_perms
  from (
    select resource, jsonb_object_agg(action, allowed) as actions
    from (
      select distinct on (resource, action) resource, action, allowed
      from (
        select resource, action, allowed, 1 as prio
          from user_permissions where profile_id = v_profile.id
        union all
        select resource, action, allowed, 2
          from permission_defaults where user_kind = v_profile.user_kind
      ) x
      order by resource, action, prio
    ) y
    group by resource
  ) z;

  select coalesce(jsonb_agg(jsonb_build_object(
      'entity', entity, 'field_key', field_key,
      'can_view', can_view, 'can_edit', can_edit)), '[]') into v_fields
  from (
    select distinct on (entity, field_key) entity, field_key, can_view, can_edit
    from (
      select entity, field_key, can_view, can_edit, 1 as prio
        from field_permissions where profile_id = v_profile.id
      union all
      select entity, field_key, can_view, can_edit, 2
        from field_permissions where profile_id is null and user_kind = v_profile.user_kind
    ) x
    order by entity, field_key, prio
  ) y;

  select coalesce(jsonb_agg(role), '[]') into v_roles
    from staff_roles where profile_id = v_profile.id;

  if v_profile.customer_id is not null then
    select jsonb_build_object('id', c.id, 'name', c.name, 'color', c.color,
                              'can_create_events', c.can_create_events)
      into v_customer from customers c where c.id = v_profile.customer_id;
  end if;

  return jsonb_build_object(
    'profile', jsonb_build_object(
      'id', v_profile.id, 'full_name', v_profile.full_name,
      'user_kind', v_profile.user_kind, 'is_admin', v_profile.is_admin,
      'customer_id', v_profile.customer_id, 'contractor_id', v_profile.contractor_id,
      'phone', v_profile.phone, 'email', v_profile.email),
    'roles', v_roles,
    'customer', v_customer,
    'permissions', v_perms,
    'field_permissions', v_fields);
end $$;

-- ===== event creation with per-customer required-field validation =====
create or replace function create_event(payload jsonb)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_customer_id uuid;
  v_event_id uuid;
  v_missing text[];
  v_status uuid;
  r record;
begin
  if (select app.user_kind()) = 'customer_user' then
    v_customer_id := app.customer_id();
    if not app.has_permission('events','create')
       or not exists (select 1 from customers c where c.id = v_customer_id
                      and c.can_create_events and c.deleted_at is null) then
      raise exception 'אין לך הרשאה ליצור אירועים';
    end if;
  elsif app.is_admin() or app.has_permission('events','create') then
    v_customer_id := (payload ->> 'customer_id')::uuid;
    if v_customer_id is null then raise exception 'חובה לבחור לקוח'; end if;
  else
    raise exception 'אין לך הרשאה ליצור אירועים';
  end if;

  -- required-field validation from customer form config
  select coalesce(array_agg(f.label_he), '{}') into v_missing
  from customer_form_fields cff
  join form_fields f on f.field_key = cff.field_key
  where cff.customer_id = v_customer_id and cff.state = 'required'
    and cff.field_key not in ('addons')
    and (
      case cff.field_key
        when 'location' then nullif(payload ->> 'location_text', '')
        else nullif(payload ->> cff.field_key, '')
      end) is null;
  if array_length(v_missing, 1) > 0 then
    raise exception 'שדות חובה חסרים: %', array_to_string(v_missing, ', ');
  end if;

  if payload ->> 'event_date' is null then
    raise exception 'שדות חובה חסרים: תאריך אירוע';
  end if;

  v_status := coalesce((payload ->> 'status_id')::uuid,
    (select id from statuses where entity = 'event' and is_default and deleted_at is null limit 1));

  insert into events (customer_id, end_client_name, event_number, event_date,
    location_text, location_provider, location_place_id, location_lat, location_lng,
    location_notes, volume_m, truck_count, notes, status_id,
    no_parking, porterage, supplier_pickup, created_by)
  values (v_customer_id,
    nullif(payload ->> 'end_client_name',''),
    nullif(payload ->> 'event_number',''),
    (payload ->> 'event_date')::date,
    nullif(payload ->> 'location_text',''),
    nullif(payload ->> 'location_provider',''),
    nullif(payload ->> 'location_place_id',''),
    (payload ->> 'location_lat')::double precision,
    (payload ->> 'location_lng')::double precision,
    nullif(payload ->> 'location_notes',''),
    (nullif(payload ->> 'volume_m',''))::numeric,
    (nullif(payload ->> 'truck_count',''))::int,
    nullif(payload ->> 'notes',''),
    v_status,
    coalesce((payload ->> 'no_parking')::boolean, false),
    coalesce((payload ->> 'porterage')::boolean, false),
    coalesce((payload ->> 'supplier_pickup')::boolean, false),
    app.profile_id())
  returning id into v_event_id;

  if nullif(payload ->> 'contact_name','') is not null
     or nullif(payload ->> 'contact_phone','') is not null then
    insert into event_contacts (event_id, contact_name, contact_phone)
    values (v_event_id, nullif(payload ->> 'contact_name',''), nullif(payload ->> 'contact_phone',''));
  end if;

  if payload ? 'supplier_ids' then
    for r in select value::uuid as sid from jsonb_array_elements_text(payload -> 'supplier_ids') loop
      insert into event_suppliers (event_id, supplier_id) values (v_event_id, r.sid)
      on conflict do nothing;
    end loop;
  end if;

  return v_event_id;
end $$;

-- ===== update event (same validation path) =====
create or replace function update_event(p_event_id uuid, payload jsonb)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_customer_id uuid;
  v_missing text[];
begin
  select customer_id into v_customer_id from events
    where id = p_event_id and deleted_at is null;
  if v_customer_id is null then raise exception 'אירוע לא נמצא'; end if;

  if not (app.is_admin()
          or ((select app.user_kind()) = 'staff' and app.has_permission('events','edit'))
          or ((select app.user_kind()) = 'customer_user'
              and v_customer_id = app.customer_id()
              and app.has_permission('events','edit'))) then
    raise exception 'אין לך הרשאה לערוך אירוע זה';
  end if;

  select coalesce(array_agg(f.label_he), '{}') into v_missing
  from customer_form_fields cff
  join form_fields f on f.field_key = cff.field_key
  where cff.customer_id = v_customer_id and cff.state = 'required'
    and cff.field_key not in ('addons')
    and payload ? (case cff.field_key when 'location' then 'location_text' else cff.field_key end)
    and (case cff.field_key
           when 'location' then nullif(payload ->> 'location_text', '')
           else nullif(payload ->> cff.field_key, '')
         end) is null;
  if array_length(v_missing, 1) > 0 then
    raise exception 'שדות חובה חסרים: %', array_to_string(v_missing, ', ');
  end if;

  update events set
    end_client_name = case when payload ? 'end_client_name' then nullif(payload ->> 'end_client_name','') else end_client_name end,
    event_number    = case when payload ? 'event_number' then nullif(payload ->> 'event_number','') else event_number end,
    event_date      = case when payload ? 'event_date' then (payload ->> 'event_date')::date else event_date end,
    location_text   = case when payload ? 'location_text' then nullif(payload ->> 'location_text','') else location_text end,
    location_provider = case when payload ? 'location_provider' then nullif(payload ->> 'location_provider','') else location_provider end,
    location_place_id = case when payload ? 'location_place_id' then nullif(payload ->> 'location_place_id','') else location_place_id end,
    location_lat    = case when payload ? 'location_lat' then (payload ->> 'location_lat')::double precision else location_lat end,
    location_lng    = case when payload ? 'location_lng' then (payload ->> 'location_lng')::double precision else location_lng end,
    location_notes  = case when payload ? 'location_notes' then nullif(payload ->> 'location_notes','') else location_notes end,
    volume_m        = case when payload ? 'volume_m' then (nullif(payload ->> 'volume_m',''))::numeric else volume_m end,
    truck_count     = case when payload ? 'truck_count' then (nullif(payload ->> 'truck_count',''))::int else truck_count end,
    notes           = case when payload ? 'notes' then nullif(payload ->> 'notes','') else notes end,
    status_id       = case when payload ? 'status_id' then (payload ->> 'status_id')::uuid else status_id end,
    no_parking      = case when payload ? 'no_parking' then (payload ->> 'no_parking')::boolean else no_parking end,
    porterage       = case when payload ? 'porterage' then (payload ->> 'porterage')::boolean else porterage end,
    supplier_pickup = case when payload ? 'supplier_pickup' then (payload ->> 'supplier_pickup')::boolean else supplier_pickup end
  where id = p_event_id;

  if payload ? 'contact_name' or payload ? 'contact_phone' then
    insert into event_contacts (event_id, contact_name, contact_phone)
    values (p_event_id, nullif(payload ->> 'contact_name',''), nullif(payload ->> 'contact_phone',''))
    on conflict (event_id) do update set
      contact_name  = case when payload ? 'contact_name' then nullif(payload ->> 'contact_name','') else event_contacts.contact_name end,
      contact_phone = case when payload ? 'contact_phone' then nullif(payload ->> 'contact_phone','') else event_contacts.contact_phone end;
  end if;

  if payload ? 'supplier_ids' then
    delete from event_suppliers where event_id = p_event_id;
    insert into event_suppliers (event_id, supplier_id)
    select p_event_id, value::uuid from jsonb_array_elements_text(payload -> 'supplier_ids')
    on conflict do nothing;
  end if;
end $$;

-- ===== duplicate event (copies extra tasks; default tasks come from trigger) =====
create or replace function duplicate_event(p_event_id uuid, p_new_date date default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_old events;
  v_new_id uuid;
  v_shift int;
begin
  if not (app.is_admin() or app.has_permission('events','create')) then
    raise exception 'אין לך הרשאה לשכפל אירועים';
  end if;
  select * into v_old from events where id = p_event_id and deleted_at is null;
  if v_old.id is null then raise exception 'אירוע לא נמצא'; end if;
  v_shift := coalesce(p_new_date, v_old.event_date) - v_old.event_date;

  insert into events (customer_id, end_client_name, event_number, event_date,
    location_text, location_provider, location_place_id, location_lat, location_lng,
    location_notes, volume_m, truck_count, notes, status_id,
    no_parking, porterage, supplier_pickup, created_by)
  values (v_old.customer_id, v_old.end_client_name, null,
    v_old.event_date + v_shift,
    v_old.location_text, v_old.location_provider, v_old.location_place_id,
    v_old.location_lat, v_old.location_lng, v_old.location_notes,
    v_old.volume_m, v_old.truck_count, v_old.notes,
    (select id from statuses where entity='event' and is_default and deleted_at is null limit 1),
    v_old.no_parking, v_old.porterage, v_old.supplier_pickup, app.profile_id())
  returning id into v_new_id;

  insert into event_contacts (event_id, contact_name, contact_phone)
  select v_new_id, contact_name, contact_phone from event_contacts where event_id = p_event_id
  on conflict do nothing;

  insert into event_suppliers (event_id, supplier_id)
  select v_new_id, supplier_id from event_suppliers where event_id = p_event_id
  on conflict do nothing;

  -- copy the non-auto tasks (auto ones were created by the trigger)
  insert into tasks (event_id, customer_id, task_type_id, title, task_date,
    onsite_start_time, warehouse_start_time, hours_count, worker_count,
    execution_method_id, truck_id, truck_free_text, notes, status_id, location_text, created_by)
  select v_new_id, t.customer_id, t.task_type_id, t.title, t.task_date + v_shift,
    t.onsite_start_time, t.warehouse_start_time, t.hours_count, t.worker_count,
    t.execution_method_id, t.truck_id, t.truck_free_text, t.notes,
    (select id from statuses where entity='task' and is_default and deleted_at is null limit 1),
    t.location_text, app.profile_id()
  from tasks t
  join task_types tt on tt.id = t.task_type_id
  where t.event_id = p_event_id and t.deleted_at is null and not tt.auto_create_on_event;

  return v_new_id;
end $$;

-- ===== bulk edit =====
create or replace function bulk_update_tasks(p_task_ids uuid[], p_patch jsonb)
returns int language plpgsql security definer set search_path = public as $$
declare v_count int;
begin
  if not (app.is_admin() or app.has_permission('tasks','edit')) then
    raise exception 'אין לך הרשאה לערוך משימות';
  end if;
  update tasks set
    task_date            = case when p_patch ? 'task_date' then (p_patch ->> 'task_date')::date else task_date end,
    onsite_start_time    = case when p_patch ? 'onsite_start_time' then (nullif(p_patch ->> 'onsite_start_time',''))::time else onsite_start_time end,
    warehouse_start_time = case when p_patch ? 'warehouse_start_time' then (nullif(p_patch ->> 'warehouse_start_time',''))::time else warehouse_start_time end,
    hours_count          = case when p_patch ? 'hours_count' then (nullif(p_patch ->> 'hours_count',''))::numeric else hours_count end,
    worker_count         = case when p_patch ? 'worker_count' then coalesce((nullif(p_patch ->> 'worker_count',''))::int, 0) else worker_count end,
    execution_method_id  = case when p_patch ? 'execution_method_id' then (nullif(p_patch ->> 'execution_method_id',''))::uuid else execution_method_id end,
    truck_id             = case when p_patch ? 'truck_id' then (nullif(p_patch ->> 'truck_id',''))::uuid else truck_id end,
    truck_free_text      = case when p_patch ? 'truck_free_text' then nullif(p_patch ->> 'truck_free_text','') else truck_free_text end,
    status_id            = case when p_patch ? 'status_id' then (p_patch ->> 'status_id')::uuid else status_id end,
    contractor_id        = case when p_patch ? 'contractor_id' then (nullif(p_patch ->> 'contractor_id',''))::uuid else contractor_id end,
    notes                = case when p_patch ? 'notes' then nullif(p_patch ->> 'notes','') else notes end
  where id = any(p_task_ids) and deleted_at is null;
  get diagnostics v_count = row_count;
  return v_count;
end $$;

-- ===== Excel import =====
create or replace function bulk_import_events(p_rows jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  r jsonb;
  i int := 0;
  v_ok int := 0;
  v_errors jsonb := '[]';
begin
  if not (app.is_admin() or app.has_permission('events','create')) then
    raise exception 'אין לך הרשאה לייבא אירועים';
  end if;
  for r in select * from jsonb_array_elements(p_rows) loop
    i := i + 1;
    begin
      perform create_event(r);
      v_ok := v_ok + 1;
    exception when others then
      v_errors := v_errors || jsonb_build_object('row', i, 'error', sqlerrm);
    end;
  end loop;
  return jsonb_build_object('imported', v_ok, 'errors', v_errors);
end $$;

-- ===== global search (SECURITY INVOKER — RLS scopes results per user) =====
create or replace function global_search(p_q text, p_limit int default 20)
returns jsonb language sql stable security invoker set search_path = public as $$
  select coalesce(jsonb_agg(row_to_json(x)), '[]') from (
    (select 'event' as kind, e.id, coalesce(e.end_client_name, 'אירוע') as title,
        c.name || coalesce(' · ' || e.event_number, '') || ' · ' || to_char(e.event_date, 'DD/MM/YYYY') as subtitle,
        e.event_date::text as extra
     from events e join customers c on c.id = e.customer_id
     where e.deleted_at is null and (
        e.search_tsv @@ plainto_tsquery('simple', p_q)
        or e.end_client_name ilike '%' || p_q || '%'
        or e.event_number ilike '%' || p_q || '%'
        or e.location_text ilike '%' || p_q || '%'
        or exists (select 1 from event_contacts ec where ec.event_id = e.id
                   and (ec.contact_phone ilike '%' || p_q || '%'
                        or ec.contact_name ilike '%' || p_q || '%')))
     order by e.event_date desc limit p_limit)
    union all
    (select 'customer', c.id, c.name, coalesce(c.contact_name, ''), null::text
     from customers c
     where c.deleted_at is null
       and (c.name ilike '%' || p_q || '%' or c.contact_phone ilike '%' || p_q || '%')
     limit p_limit)
    union all
    (select 'profile', p.id, p.full_name, coalesce(p.phone, ''), p.user_kind::text
     from profiles p
     where p.deleted_at is null
       and (p.full_name ilike '%' || p_q || '%' or p.phone ilike '%' || p_q || '%')
     limit p_limit)
    union all
    (select 'task', t.id,
        coalesce(t.title, tt.name), coalesce(c.name || ' · ', '') || to_char(t.task_date, 'DD/MM/YYYY'),
        t.task_date::text
     from tasks t
     join task_types tt on tt.id = t.task_type_id
     left join customers c on c.id = t.customer_id
     where t.deleted_at is null
       and (t.title ilike '%' || p_q || '%' or t.location_text ilike '%' || p_q || '%')
     order by t.task_date desc limit p_limit)
  ) x
$$;

-- ===== notifications =====
create or replace function mark_notifications_read(p_ids uuid[] default null)
returns void language sql security definer set search_path = public as $$
  update notifications set read_at = now()
  where recipient_id = app.profile_id() and read_at is null
    and (p_ids is null or id = any(p_ids))
$$;

-- ===== dashboards (SECURITY INVOKER — RLS scopes) =====
create or replace function dashboard_stats(p_from date, p_to date)
returns jsonb language sql stable security invoker set search_path = public as $$
  select jsonb_build_object(
    'events_count', (select count(*) from events
       where deleted_at is null and event_date between p_from and p_to),
    'tasks_count', (select count(*) from tasks
       where deleted_at is null and task_date between p_from and p_to),
    'tasks_today', (select count(*) from tasks
       where deleted_at is null and task_date = current_date),
    'tasks_week', (select count(*) from tasks
       where deleted_at is null
         and task_date between date_trunc('week', current_date)::date
         and (date_trunc('week', current_date) + interval '6 days')::date),
    'tasks_overdue', (select count(*) from tasks t join statuses s on s.id = t.status_id
       where t.deleted_at is null and t.task_date < current_date and not s.is_terminal),
    'available_workers', (select count(*) from profiles p
       where p.deleted_at is null and p.is_active and p.user_kind = 'staff'
         and not exists (select 1 from task_assignments a join tasks t on t.id = a.task_id
                         where a.profile_id = p.id and t.task_date = current_date and t.deleted_at is null)),
    'by_customer', (select coalesce(jsonb_agg(row_to_json(x)), '[]') from (
       select c.name, c.color, count(*) as cnt from tasks t join customers c on c.id = t.customer_id
       where t.deleted_at is null and t.task_date between p_from and p_to
       group by c.name, c.color order by cnt desc limit 12) x),
    'by_contractor', (select coalesce(jsonb_agg(row_to_json(x)), '[]') from (
       select ct.name, count(*) as cnt from tasks t join contractors ct on ct.id = t.contractor_id
       where t.deleted_at is null and t.task_date between p_from and p_to
       group by ct.name order by cnt desc limit 12) x),
    'by_worker', (select coalesce(jsonb_agg(row_to_json(x)), '[]') from (
       select p.full_name as name, count(*) as cnt
       from task_assignments a
       join tasks t on t.id = a.task_id and t.deleted_at is null
         and t.task_date between p_from and p_to
       join profiles p on p.id = a.profile_id
       group by p.full_name order by cnt desc limit 12) x),
    'by_status', (select coalesce(jsonb_agg(row_to_json(x)), '[]') from (
       select s.name, s.color, count(*) as cnt from tasks t join statuses s on s.id = t.status_id
       where t.deleted_at is null and t.task_date between p_from and p_to
       group by s.name, s.color order by cnt desc) x))
$$;

create or replace function contractor_dashboard(p_from date default null, p_to date default null)
returns jsonb language sql stable security invoker set search_path = public as $$
  with my_tasks as (
    select t.*, tct.price, tct.paid_at, tct.paid_amount,
           s.is_terminal
    from tasks t
    join statuses s on s.id = t.status_id
    left join task_contractor_terms tct on tct.task_id = t.id
    where t.deleted_at is null
      and t.contractor_id = app.contractor_id()
      and (p_from is null or t.task_date >= p_from)
      and (p_to is null or t.task_date <= p_to)
  )
  select jsonb_build_object(
    'tasks_count', (select count(*) from my_tasks),
    'expected_total', (select coalesce(sum(price), 0) from my_tasks),
    'paid_total', (select coalesce(sum(coalesce(paid_amount, price)), 0) from my_tasks where paid_at is not null),
    'unpaid_total', (select coalesce(sum(price), 0) from my_tasks where paid_at is null),
    'completed_count', (select count(*) from my_tasks where is_terminal),
    'upcoming_count', (select count(*) from my_tasks where task_date >= current_date and not is_terminal))
$$;

-- soft delete / restore helper
create or replace function soft_delete(p_table text, p_id uuid, p_restore boolean default false)
returns void language plpgsql security definer set search_path = public as $$
declare v_resource text;
begin
  v_resource := case p_table
    when 'events' then 'events'
    when 'tasks' then 'tasks'
    when 'customers' then 'customers'
    when 'contractors' then 'contractors'
    when 'contractor_workers' then 'contractors'
    when 'profiles' then 'users'
    when 'suppliers' then 'settings'
    when 'trucks' then 'settings'
    when 'task_types' then 'settings'
    when 'execution_methods' then 'settings'
    when 'statuses' then 'settings'
    else null end;
  if v_resource is null then raise exception 'טבלה לא נתמכת'; end if;
  if not (app.is_admin() or app.has_permission(v_resource,
      case when p_restore then 'edit' else 'delete' end::permission_action)) then
    raise exception 'אין לך הרשאה למחוק פריט זה';
  end if;
  if p_table in ('task_types','statuses') and not p_restore then
    -- system rows are protected
    if p_table = 'task_types' and exists (select 1 from task_types where id = p_id and is_system) then
      raise exception 'לא ניתן למחוק סוג משימה מערכתי';
    end if;
  end if;
  execute format('update %I set deleted_at = case when $2 then null else now() end where id = $1', p_table)
    using p_id, p_restore;
end $$;
