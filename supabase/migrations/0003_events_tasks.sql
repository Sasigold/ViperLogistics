-- 0003: events, tasks, assignments, contractor tables, triggers
create table events (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references customers(id),
  end_client_name text,
  event_number text,
  event_date date not null,
  location_text text,
  location_provider text,
  location_place_id text,
  location_lat double precision,
  location_lng double precision,
  location_notes text,
  volume_m numeric(10,2),
  truck_count int,
  notes text,
  status_id uuid references statuses(id),
  no_parking boolean not null default false,
  porterage boolean not null default false,
  supplier_pickup boolean not null default false,
  created_by uuid references profiles(id),
  search_tsv tsvector generated always as (
    to_tsvector('simple',
      coalesce(end_client_name,'') || ' ' ||
      coalesce(event_number,'') || ' ' ||
      coalesce(location_text,''))) stored,
  deleted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index events_customer_number_uq on events (customer_id, event_number)
  where event_number is not null and deleted_at is null;
create index events_customer_date_idx on events (customer_id, event_date) where deleted_at is null;
create index events_date_idx on events (event_date) where deleted_at is null;
create index events_search_gin on events using gin (search_tsv);
create index events_client_trgm on events using gin (end_client_name gin_trgm_ops);
create trigger events_updated before update on events
  for each row execute function app.set_updated_at();

create table event_contacts (
  event_id uuid primary key references events(id) on delete cascade,
  contact_name text,
  contact_phone text
);
create index event_contacts_phone_trgm on event_contacts using gin (contact_phone gin_trgm_ops);

create table event_suppliers (
  event_id uuid not null references events(id) on delete cascade,
  supplier_id uuid not null references suppliers(id),
  primary key (event_id, supplier_id)
);

create table tasks (
  id uuid primary key default gen_random_uuid(),
  event_id uuid references events(id),
  customer_id uuid references customers(id),
  task_type_id uuid not null references task_types(id),
  title text,
  task_date date not null,
  onsite_start_time time,
  warehouse_start_time time,
  hours_count numeric(5,2),
  onsite_end_time time generated always as (
    case when onsite_start_time is not null and hours_count is not null
      then (onsite_start_time + make_interval(mins => round(hours_count * 60)::int))::time
    end) stored,
  worker_count int not null default 0,
  execution_method_id uuid references execution_methods(id),
  truck_id uuid references trucks(id),
  truck_free_text text,
  notes text,
  status_id uuid not null references statuses(id),
  contractor_id uuid references contractors(id),
  location_text text,
  created_by uuid references profiles(id),
  deleted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index tasks_date_idx on tasks (task_date) where deleted_at is null;
create index tasks_customer_date_idx on tasks (customer_id, task_date) where deleted_at is null;
create index tasks_contractor_date_idx on tasks (contractor_id, task_date)
  where contractor_id is not null and deleted_at is null;
create index tasks_event_idx on tasks (event_id);
create index tasks_status_idx on tasks (status_id) where deleted_at is null;
create index tasks_type_date_idx on tasks (task_type_id, task_date) where deleted_at is null;
create trigger tasks_updated before update on tasks
  for each row execute function app.set_updated_at();

create table task_assignments (
  id uuid primary key default gen_random_uuid(),
  task_id uuid not null references tasks(id) on delete cascade,
  profile_id uuid not null references profiles(id),
  role assignment_role not null,
  truck_id uuid references trucks(id),
  created_at timestamptz not null default now(),
  unique (task_id, profile_id, role)
);
create index task_assignments_task_idx on task_assignments (task_id);
create index task_assignments_profile_idx on task_assignments (profile_id);
create unique index task_assignments_one_lead on task_assignments (task_id) where role = 'team_lead';

create table task_contractor_workers (
  task_id uuid not null references tasks(id) on delete cascade,
  contractor_worker_id uuid not null references contractor_workers(id),
  primary key (task_id, contractor_worker_id)
);

create table task_contractor_terms (
  task_id uuid primary key references tasks(id) on delete cascade,
  contractor_id uuid not null references contractors(id),
  price numeric(12,2) not null default 0,
  paid_at timestamptz,
  paid_amount numeric(12,2),
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index tct_contractor_idx on task_contractor_terms (contractor_id, paid_at);
create trigger tct_updated before update on task_contractor_terms
  for each row execute function app.set_updated_at();

-- keep tasks.customer_id in sync with parent event
create or replace function app.sync_task_customer()
returns trigger language plpgsql as $$
begin
  if new.event_id is not null then
    select e.customer_id into new.customer_id from events e where e.id = new.event_id;
  end if;
  return new;
end $$;
create trigger tasks_sync_customer before insert or update of event_id on tasks
  for each row execute function app.sync_task_customer();

-- default tasks (הקמה/פירוק) on event creation
create or replace function app.create_default_tasks()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_status uuid;
begin
  select id into v_status from statuses
    where entity = 'task' and is_default and deleted_at is null limit 1;
  insert into tasks (event_id, customer_id, task_type_id, task_date, status_id, worker_count, created_by)
  select new.id, new.customer_id, t.id, new.event_date, v_status, 0, new.created_by
  from task_types t
  where t.auto_create_on_event and t.deleted_at is null and t.is_active
  order by t.sort_order;
  return new;
end $$;
create trigger events_default_tasks after insert on events
  for each row execute function app.create_default_tasks();

-- contractor may not exceed worker_count on a task
create or replace function app.check_contractor_worker_limit()
returns trigger language plpgsql as $$
declare
  v_limit int;
  v_current int;
begin
  select worker_count into v_limit from tasks where id = new.task_id;
  select count(*) into v_current from task_contractor_workers where task_id = new.task_id;
  if v_limit is not null and v_limit > 0 and v_current >= v_limit then
    raise exception 'חריגה מכמות העובדים שהוגדרה למשימה (%)', v_limit;
  end if;
  return new;
end $$;
create trigger tcw_limit before insert on task_contractor_workers
  for each row execute function app.check_contractor_worker_limit();

-- delegating a task to a contractor creates the terms row with default price
create or replace function app.sync_contractor_terms()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.contractor_id is not null and
     (tg_op = 'INSERT' or old.contractor_id is distinct from new.contractor_id) then
    insert into task_contractor_terms (task_id, contractor_id, price)
    values (new.id, new.contractor_id,
            coalesce((select default_task_price from contractors where id = new.contractor_id), 0))
    on conflict (task_id) do update
      set contractor_id = excluded.contractor_id, price = excluded.price, paid_at = null, paid_amount = null;
    -- previous contractor's chosen workers are no longer relevant
    if tg_op = 'UPDATE' and old.contractor_id is not null then
      delete from task_contractor_workers where task_id = new.id;
    end if;
  elsif new.contractor_id is null and tg_op = 'UPDATE' and old.contractor_id is not null then
    delete from task_contractor_terms where task_id = new.id;
    delete from task_contractor_workers where task_id = new.id;
  end if;
  return new;
end $$;
create trigger tasks_contractor_terms after insert or update of contractor_id on tasks
  for each row execute function app.sync_contractor_terms();
