-- 0002: configurable lookup tables + form config + seeds
create table task_types (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  code text unique,
  is_system boolean not null default false,
  auto_create_on_event boolean not null default false,
  sort_order int not null default 0,
  is_active boolean not null default true,
  deleted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create trigger task_types_updated before update on task_types
  for each row execute function app.set_updated_at();

create table execution_methods (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  sort_order int not null default 0,
  is_active boolean not null default true,
  deleted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create trigger execution_methods_updated before update on execution_methods
  for each row execute function app.set_updated_at();

create table task_type_execution_methods (
  task_type_id uuid not null references task_types(id) on delete cascade,
  execution_method_id uuid not null references execution_methods(id) on delete cascade,
  primary key (task_type_id, execution_method_id)
);

create table customer_execution_methods (
  customer_id uuid not null references customers(id) on delete cascade,
  execution_method_id uuid not null references execution_methods(id) on delete cascade,
  primary key (customer_id, execution_method_id)
);

create table statuses (
  id uuid primary key default gen_random_uuid(),
  entity text not null check (entity in ('task','event')),
  name text not null,
  color text not null default '#64748b',
  sort_order int not null default 0,
  is_default boolean not null default false,
  is_terminal boolean not null default false,
  is_active boolean not null default true,
  deleted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index statuses_one_default on statuses (entity) where is_default and deleted_at is null;
create trigger statuses_updated before update on statuses
  for each row execute function app.set_updated_at();

create table trucks (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  plate_number text,
  notes text,
  is_active boolean not null default true,
  deleted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create trigger trucks_updated before update on trucks
  for each row execute function app.set_updated_at();

create table suppliers (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references customers(id),
  name text not null,
  phone text,
  address text,
  notes text,
  is_active boolean not null default true,
  deleted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index suppliers_customer_idx on suppliers (customer_id) where deleted_at is null;
create trigger suppliers_updated before update on suppliers
  for each row execute function app.set_updated_at();

create table form_fields (
  field_key text primary key,
  label_he text not null,
  sort_order int not null default 0
);

create table customer_form_fields (
  customer_id uuid not null references customers(id) on delete cascade,
  field_key text not null references form_fields(field_key),
  state field_state not null default 'visible',
  primary key (customer_id, field_key)
);

create table app_settings (
  key text primary key,
  value jsonb not null,
  updated_at timestamptz not null default now()
);

-- ===== seeds =====
insert into form_fields (field_key, label_he, sort_order) values
  ('end_client_name', 'שם לקוח האירוע', 1),
  ('event_number',    'מספר אירוע', 2),
  ('location',        'מיקום', 3),
  ('event_date',      'תאריך אירוע', 4),
  ('location_notes',  'הערות למיקום', 5),
  ('volume_m',        'נפח במטר', 6),
  ('truck_count',     'כמות משאיות', 7),
  ('contact_name',    'איש קשר', 8),
  ('contact_phone',   'טלפון איש קשר', 9),
  ('notes',           'הערות', 10),
  ('addons',          'תוספות', 11);

insert into task_types (name, code, is_system, auto_create_on_event, sort_order) values
  ('הקמה',  'setup',    true, true, 1),
  ('פירוק', 'teardown', true, true, 2);
insert into task_types (name, sort_order) values
  ('סידור', 3), ('הובלה נוספת', 4), ('איסוף', 5), ('ביקורת', 6), ('ניקיון', 7);

insert into execution_methods (name, sort_order) values
  ('סידור', 1), ('הרכבה בלבד', 2), ('הובלה בלבד', 3), ('פיקוח', 4),
  ('צוות לשטח', 5), ('איסוף עצמי', 6), ('איסוף', 7), ('פירוק בלבד', 8),
  ('החזרה עצמית', 9);

-- setup methods
insert into task_type_execution_methods (task_type_id, execution_method_id)
select t.id, m.id from task_types t, execution_methods m
where t.code = 'setup' and m.name in ('סידור','הרכבה בלבד','הובלה בלבד','פיקוח','צוות לשטח','איסוף עצמי');
-- teardown methods
insert into task_type_execution_methods (task_type_id, execution_method_id)
select t.id, m.id from task_types t, execution_methods m
where t.code = 'teardown' and m.name in ('איסוף','פירוק בלבד','הובלה בלבד','פיקוח','צוות לשטח','החזרה עצמית');
-- generic task types: all methods allowed
insert into task_type_execution_methods (task_type_id, execution_method_id)
select t.id, m.id from task_types t, execution_methods m where t.code is null;

insert into statuses (entity, name, color, sort_order, is_default, is_terminal) values
  ('task', 'טיוטה',    '#94a3b8', 1, false, false),
  ('task', 'מתוכנן',   '#3b82f6', 2, true,  false),
  ('task', 'משובץ',    '#8b5cf6', 3, false, false),
  ('task', 'בביצוע',   '#f59e0b', 4, false, false),
  ('task', 'הושלם',    '#22c55e', 5, false, true),
  ('task', 'בוטל',     '#ef4444', 6, false, true),
  ('event', 'מתוכנן',  '#3b82f6', 1, true,  false),
  ('event', 'מאושר',   '#8b5cf6', 2, false, false),
  ('event', 'הושלם',   '#22c55e', 3, false, true),
  ('event', 'בוטל',    '#ef4444', 4, false, true);

-- new customer: enable all execution methods + default form fields
create or replace function app.seed_customer_defaults()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into customer_execution_methods (customer_id, execution_method_id)
  select new.id, m.id from execution_methods m where m.deleted_at is null
  on conflict do nothing;
  insert into customer_form_fields (customer_id, field_key, state)
  select new.id, f.field_key, 'visible'::field_state from form_fields f
  on conflict do nothing;
  return new;
end $$;
create trigger customers_seed_defaults after insert on customers
  for each row execute function app.seed_customer_defaults();
