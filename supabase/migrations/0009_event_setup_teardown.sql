-- 0009: הקמה/פירוק sections on the event form
-- The two auto-created tasks (task_types.code 'setup'/'teardown') are now editable
-- straight from the event form. Their fields are configurable per customer like any
-- other event field, so the keys below double as form_fields keys and payload keys.

insert into form_fields (field_key, label_he, sort_order) values
  ('setup_date',                'הקמה — תאריך',        12),
  ('setup_time',                'הקמה — שעה בשטח',     13),
  ('setup_worker_count',        'הקמה — כמות עובדים',  14),
  ('setup_hours_count',         'הקמה — כמות שעות',    15),
  ('setup_execution_method',    'הקמה — אופן ביצוע',   16),
  ('teardown_date',             'פירוק — תאריך',       17),
  ('teardown_time',             'פירוק — שעה בשטח',    18),
  ('teardown_worker_count',     'פירוק — כמות עובדים', 19),
  ('teardown_hours_count',      'פירוק — כמות שעות',   20),
  ('teardown_execution_method', 'פירוק — אופן ביצוע',  21)
on conflict (field_key) do nothing;

-- app.seed_customer_defaults() only fires for new customers — backfill the existing ones
insert into customer_form_fields (customer_id, field_key, state)
select c.id, f.field_key, 'visible'::field_state
from customers c cross join form_fields f
where f.sort_order >= 12
on conflict do nothing;

-- ===== apply one section of the event form onto its auto-created task =====
-- Patch semantics: a key absent from the payload never clears the column, so a
-- dispatcher's warehouse time, truck, status, contractor and assignments survive
-- an event edit. Only the five columns the form owns are touched.
create or replace function app.apply_event_task_block(p_event_id uuid, p_code text, payload jsonb)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_type    task_types;
  v_event   events;
  v_task_id uuid;
  v_method  uuid;
  k_date    text := p_code || '_date';
  k_time    text := p_code || '_time';
  k_workers text := p_code || '_worker_count';
  k_hours   text := p_code || '_hours_count';
  k_method  text := p_code || '_execution_method';
begin
  if payload is null or not (payload ?| array[k_date, k_time, k_workers, k_hours, k_method]) then
    return;
  end if;

  select * into v_type from task_types
    where code = p_code and is_active and deleted_at is null;
  if v_type.id is null then return; end if;  -- type disabled in settings — nothing to fill

  select * into v_event from events where id = p_event_id;
  if v_event.id is null then raise exception 'אירוע לא נמצא'; end if;

  -- אופן ביצוע חייב להיות בחיתוך: פעיל ∩ מותר לסוג המשימה ∩ מותר ללקוח
  if payload ? k_method then
    v_method := (nullif(payload ->> k_method, ''))::uuid;
    if v_method is not null and not exists (
         select 1 from execution_methods m
         join task_type_execution_methods ttm
           on ttm.execution_method_id = m.id and ttm.task_type_id = v_type.id
         join customer_execution_methods cem
           on cem.execution_method_id = m.id and cem.customer_id = v_event.customer_id
         where m.id = v_method and m.is_active and m.deleted_at is null)
    then
      raise exception 'אופן הביצוע שנבחר אינו זמין עבור % אצל לקוח זה', v_type.name;
    end if;
  end if;

  select t.id into v_task_id from tasks t
   where t.event_id = p_event_id and t.task_type_id = v_type.id and t.deleted_at is null
   order by t.created_at, t.id limit 1;

  -- המשימה נמחקה או שלא נוצרה אוטומטית — יוצרים אותה מחדש
  if v_task_id is null then
    insert into tasks (event_id, customer_id, task_type_id, task_date, status_id, worker_count, created_by)
    values (p_event_id, v_event.customer_id, v_type.id,
            coalesce((nullif(payload ->> k_date, ''))::date, v_event.event_date),
            (select id from statuses where entity = 'task' and is_default and deleted_at is null limit 1),
            0, app.profile_id())
    returning id into v_task_id;
  end if;

  update tasks set
    task_date           = case when payload ? k_date
                            then coalesce((nullif(payload ->> k_date, ''))::date, task_date)
                            else task_date end,
    onsite_start_time   = case when payload ? k_time
                            then (nullif(payload ->> k_time, ''))::time else onsite_start_time end,
    hours_count         = case when payload ? k_hours
                            then (nullif(payload ->> k_hours, ''))::numeric else hours_count end,
    worker_count        = case when payload ? k_workers
                            then coalesce((nullif(payload ->> k_workers, ''))::int, 0) else worker_count end,
    execution_method_id = case when payload ? k_method
                            then (nullif(payload ->> k_method, ''))::uuid else execution_method_id end
  where id = v_task_id;
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

  -- the events_default_tasks trigger already created the two auto tasks
  perform app.apply_event_task_block(v_event_id, 'setup', payload);
  perform app.apply_event_task_block(v_event_id, 'teardown', payload);

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

  perform app.apply_event_task_block(p_event_id, 'setup', payload);
  perform app.apply_event_task_block(p_event_id, 'teardown', payload);
end $$;

-- ===== duplicate event (now carries the הקמה/פירוק timing too) =====
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

  -- the auto tasks already exist (trigger) but carry no timing — copy it from the source.
  -- status stays at the default and the contractor is deliberately not copied: delegation
  -- must be decided again, and copying it would silently create pricing rows.
  update tasks nt set
    task_date            = src.task_date + v_shift,
    onsite_start_time    = src.onsite_start_time,
    warehouse_start_time = src.warehouse_start_time,
    hours_count          = src.hours_count,
    worker_count         = src.worker_count,
    execution_method_id  = src.execution_method_id,
    truck_id             = src.truck_id,
    truck_free_text      = src.truck_free_text,
    notes                = src.notes
  from (
    select distinct on (t.task_type_id) t.*
    from tasks t join task_types tt on tt.id = t.task_type_id
    where t.event_id = p_event_id and t.deleted_at is null and tt.auto_create_on_event
    order by t.task_type_id, t.created_at
  ) src
  where nt.event_id = v_new_id and nt.deleted_at is null and nt.task_type_id = src.task_type_id;

  return v_new_id;
end $$;

-- ===== align the per-customer config policies with the UI =====
-- CustomerDetailPage enables the "שדות טופס" and "אופני ביצוע" tabs for customers:edit,
-- but these policies only accepted settings:edit — the toggles failed at the DB.
do $$
declare t text;
begin
  foreach t in array array['customer_execution_methods','customer_form_fields'] loop
    execute format('drop policy %I_write on %I', t, t);
    execute format(
      'create policy %I_write on %I for all to authenticated
         using ((select app.is_admin()) or app.has_permission(''settings'',''edit'')
                or app.has_permission(''customers'',''edit''))
         with check ((select app.is_admin()) or app.has_permission(''settings'',''edit'')
                or app.has_permission(''customers'',''edit''))', t, t);
  end loop;
end $$;
