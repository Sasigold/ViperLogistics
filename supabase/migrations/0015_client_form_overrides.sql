-- 0015: per-user overrides of the event form, plus the client portal's dashboard.
--
-- There are two separate ideas about "fields" in this database and they are not
-- the same thing:
--
--   field_registry + field_permissions (0010–0012) govern access to *data*.
--     Column-shaped: location_text, no_parking, contact_phone. Enforced by RLS
--     and by app.enforce_field_perms.
--
--   form_fields + customer_form_fields (0002) govern the *shape of the form*.
--     Form-shaped: 'location' is five columns, 'addons' is three, and
--     'setup_time' is a column on a different table entirely. Enforced in
--     create_event/update_event.
--
-- They cannot be merged: field_registry has no key for a form-only grouping,
-- and field_permissions is two booleans and so cannot express "required". This
-- migration adds the missing third layer to the second idea — the same config,
-- narrowed for one user.

create table user_form_fields (
  profile_id uuid not null references profiles(id) on delete cascade,
  field_key  text not null references form_fields(field_key),
  state      field_state not null,
  primary key (profile_id, field_key)
);
alter table user_form_fields enable row level security;

create policy uff_select on user_form_fields for select to authenticated using (
  (select app.is_admin())
  or profile_id = (select app.profile_id())
  or app.can_manage_profile(profile_id));
create policy uff_write on user_form_fields for all to authenticated
  using ((select app.is_admin())
    or (app.has('users.manage_permissions') and app.can_manage_profile(profile_id)))
  with check ((select app.is_admin())
    or (app.has('users.manage_permissions') and app.can_manage_profile(profile_id)));

create trigger user_form_fields_audit after insert or update or delete on user_form_fields
  for each row execute function app.audit();

-- ===== the merged config ====================================================
-- Intersection, not override: hidden from either layer hides, required from
-- either layer requires. That is what guarantees a client admin can only narrow
-- what the owner configured for the company, never widen it. The cost is that
-- showing a field to exactly one person means enabling it company-wide and
-- hiding it for the others — one-directional, and predictable.
--
-- Deliberately NOT security definer: called from inside the SECURITY DEFINER
-- event RPCs it inherits their rights, but called directly over PostgREST it
-- runs as the caller, so user_form_fields RLS keeps one client out of another's
-- configuration.
create or replace function app.form_config(p_customer uuid, p_profile uuid)
returns table (field_key text, state field_state)
language sql stable set search_path = public as $$
  select f.field_key,
         case
           when c.state = 'hidden'   or u.state = 'hidden'   then 'hidden'
           when c.state = 'required' or u.state = 'required' then 'required'
           else 'visible'
         end::field_state
  from form_fields f
  left join customer_form_fields c
         on c.customer_id = p_customer and c.field_key = f.field_key
  left join user_form_fields u
         on u.profile_id = p_profile and u.field_key = f.field_key
$$;

/* One form key can own several payload keys. */
create or replace function app.event_payload_keys(p_field_key text)
returns text[] language sql immutable set search_path = public as $$
  select case p_field_key
    when 'location' then array['location_text','location_provider','location_place_id',
                               'location_lat','location_lng']
    when 'addons'   then array['no_parking','porterage','supplier_pickup','supplier_ids']
    else array[p_field_key]
  end
$$;

-- Drop what the caller is not allowed to supply. On create a stripped key falls
-- back to the column default; on update an absent key is a no-op thanks to the
-- existing `case when payload ? 'x'` patch semantics, so a hidden field keeps
-- whatever staff last set. Stripping rather than rejecting: a stale draft in
-- localStorage, written before a field was hidden, would otherwise throw an
-- error the user cannot act on.
create or replace function app.strip_hidden_event_keys(p_profile uuid, payload jsonb)
returns jsonb language plpgsql stable set search_path = public as $$
declare r record; v_out jsonb := payload; v_customer uuid;
begin
  select customer_id into v_customer from profiles where id = p_profile;
  for r in select field_key from app.form_config(v_customer, p_profile) where state = 'hidden' loop
    v_out := v_out - app.event_payload_keys(r.field_key);
  end loop;
  if not app.has('events.view_contacts') then
    v_out := v_out - array['contact_name','contact_phone'];
  end if;
  return v_out;
end $$;

-- Required-field validation, shared by create and update. p_patch limits it to
-- keys the payload actually carries, which is what makes a partial update legal.
create or replace function app.validate_event_payload(
  p_customer uuid, p_profile uuid, payload jsonb, p_patch boolean)
returns void language plpgsql stable set search_path = public as $$
declare v_missing text[];
begin
  select coalesce(array_agg(f.label_he), '{}') into v_missing
  from app.form_config(p_customer, p_profile) cfg
  join form_fields f on f.field_key = cfg.field_key
  where cfg.state = 'required'
    and cfg.field_key <> 'addons'
    and (not p_patch
         or payload ? (case cfg.field_key when 'location' then 'location_text'
                                          else cfg.field_key end))
    and (case cfg.field_key
           when 'location' then nullif(payload ->> 'location_text', '')
           else nullif(payload ->> cfg.field_key, '')
         end) is null;
  if array_length(v_missing, 1) > 0 then
    raise exception 'שדות חובה חסרים: %', array_to_string(v_missing, ', ');
  end if;
end $$;

-- ===== create/update event ==================================================
-- Same bodies as 0009, with three changes: the config is resolved per user
-- rather than per customer, the payload is filtered before it is trusted, and
-- the nested הקמה/פירוק write runs inside app.system_write.
--
-- That last one matters now that 0012 attached a column gate to tasks: saving
-- an event rewrites its two auto tasks, and without the flag those writes are
-- judged against the *user's* task field rights, so "may edit the event" would
-- silently require "may reschedule tasks". This is the case the flag was
-- introduced for.
create or replace function create_event(payload jsonb)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_customer_id uuid;
  v_profile_id uuid;
  v_event_id uuid;
  v_status uuid;
  r record;
begin
  v_profile_id := app.profile_id();

  if (select app.user_kind()) = 'customer_user' then
    v_customer_id := app.customer_id();
    if not app.has('events.create')
       or not exists (select 1 from customers c where c.id = v_customer_id
                      and c.can_create_events and c.deleted_at is null) then
      raise exception 'אין לך הרשאה ליצור אירועים' using errcode = '42501';
    end if;
    payload := app.strip_hidden_event_keys(v_profile_id, payload);
  elsif app.is_admin() or app.has('events.create') then
    v_customer_id := (payload ->> 'customer_id')::uuid;
    if v_customer_id is null then raise exception 'חובה לבחור לקוח'; end if;
    -- staff pick the customer from a dropdown and carry no personal form
    -- config, so their validation stays purely per-customer
    v_profile_id := null;
  else
    raise exception 'אין לך הרשאה ליצור אירועים' using errcode = '42501';
  end if;

  perform app.validate_event_payload(v_customer_id, v_profile_id, payload, false);

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
  perform app.system_write(true);
  perform app.apply_event_task_block(v_event_id, 'setup', payload);
  perform app.apply_event_task_block(v_event_id, 'teardown', payload);
  perform app.system_write(false);

  return v_event_id;
end $$;

create or replace function update_event(p_event_id uuid, payload jsonb)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_customer_id uuid;
  v_profile_id uuid;
begin
  select customer_id into v_customer_id from events
    where id = p_event_id and deleted_at is null;
  if v_customer_id is null then raise exception 'אירוע לא נמצא'; end if;

  if not (app.is_admin()
          or ((select app.user_kind()) = 'staff' and app.has('events.edit'))
          or ((select app.user_kind()) = 'customer_user'
              and v_customer_id = app.customer_id()
              and app.has('events.edit'))) then
    raise exception 'אין לך הרשאה לערוך אירוע זה' using errcode = '42501';
  end if;

  if (select app.user_kind()) = 'customer_user' then
    v_profile_id := app.profile_id();
    payload := app.strip_hidden_event_keys(v_profile_id, payload);
  end if;

  perform app.validate_event_payload(v_customer_id, v_profile_id, payload, true);

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

  perform app.system_write(true);
  perform app.apply_event_task_block(p_event_id, 'setup', payload);
  perform app.apply_event_task_block(p_event_id, 'teardown', payload);
  perform app.system_write(false);
end $$;

-- ===== login bootstrap now carries the merged form config ===================
-- Same body as 0012 plus 'form_config'. Saves the portal a round trip, and
-- keeps the merged result correct even though customer_form_fields is
-- world-readable while user_form_fields is not.
create or replace function get_my_permissions()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_profile profiles;
  v_caps jsonb; v_legacy jsonb; v_fields jsonb;
  v_roles jsonb; v_app_roles jsonb; v_customer jsonb; v_scopes jsonb; v_form jsonb;
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
    'field_permissions', v_fields,
    'scopes', coalesce(v_scopes, '[]'::jsonb),
    'form_config', v_form);
end $$;

-- ===== client portal dashboard ==============================================
-- SECURITY INVOKER, like contractor_dashboard: events_select already restricts
-- the rows by scope, so the numbers are scoped without restating the rule.
-- dashboard_stats is deliberately not reused — available_workers, by_worker and
-- by_contractor are meaningless or unwelcome on a client's screen.
create or replace function customer_dashboard(p_from date default null, p_to date default null)
returns jsonb language sql stable security invoker set search_path = public as $$
  with my_events as (
    select e.*, s.is_terminal
    from events e
    left join statuses s on s.id = e.status_id
    where e.deleted_at is null
      and (p_from is null or e.event_date >= p_from)
      and (p_to   is null or e.event_date <= p_to)
  ),
  my_tasks as (
    select t.*, s.is_terminal, s.name as status_name, s.color as status_color
    from tasks t
    join statuses s on s.id = t.status_id
    where t.deleted_at is null
      and (p_from is null or t.task_date >= p_from)
      and (p_to   is null or t.task_date <= p_to)
  )
  select jsonb_build_object(
    'events_count',    (select count(*) from my_events),
    'events_upcoming', (select count(*) from my_events
                         where event_date >= current_date and not coalesce(is_terminal, false)),
    'events_done',     (select count(*) from my_events where coalesce(is_terminal, false)),
    'tasks_count',     (select count(*) from my_tasks),
    'tasks_open',      (select count(*) from my_tasks where not is_terminal),
    'by_status',       (select coalesce(jsonb_agg(jsonb_build_object(
                                 'name', status_name, 'color', status_color, 'cnt', cnt)), '[]')
                          from (select status_name, status_color, count(*) as cnt
                                  from my_tasks group by status_name, status_color
                                 order by count(*) desc) q),
    'next_events',     (select coalesce(jsonb_agg(jsonb_build_object(
                                 'id', id, 'event_date', event_date,
                                 'end_client_name', end_client_name,
                                 'event_number', event_number,
                                 'location_text', location_text)), '[]')
                          from (select * from my_events
                                 where event_date >= current_date
                                 order by event_date limit 5) q))
$$;

revoke execute on function public.customer_dashboard(date, date) from anon, public;

-- The company-wide form config is staff territory: 0009 widened its write gate
-- to customers:edit for the CustomerDetailPage tabs, which would let a client
-- rewrite their own form config if ever granted that key.
drop policy customer_form_fields_write on customer_form_fields;
create policy customer_form_fields_write on customer_form_fields for all to authenticated
  using ((select app.is_admin())
    or ((select app.user_kind()) = 'staff' and app.has('customers.manage_form_fields')))
  with check ((select app.is_admin())
    or ((select app.user_kind()) = 'staff' and app.has('customers.manage_form_fields')));
