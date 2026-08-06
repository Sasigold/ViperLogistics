-- 0001: extensions, enums, identity tables
create extension if not exists pg_trgm;

create schema if not exists app;

create type user_kind as enum ('staff', 'customer_user', 'contractor_user');
create type staff_role as enum ('worker', 'driver', 'team_lead');
create type assignment_role as enum ('worker', 'driver', 'team_lead');
create type field_state as enum ('visible', 'hidden', 'required');
create type audit_action as enum ('INSERT', 'UPDATE', 'DELETE');
create type permission_action as enum ('view', 'create', 'edit', 'delete');

create or replace function app.set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end $$;

create table customers (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  color text not null default '#3b82f6',
  can_create_events boolean not null default false,
  contact_name text,
  contact_phone text,
  contact_email text,
  notes text,
  is_active boolean not null default true,
  deleted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index customers_name_uq on customers (name) where deleted_at is null;
create trigger customers_updated before update on customers
  for each row execute function app.set_updated_at();

create table contractors (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  contact_name text,
  phone text,
  email text,
  notes text,
  default_task_price numeric(12,2),
  is_active boolean not null default true,
  deleted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create trigger contractors_updated before update on contractors
  for each row execute function app.set_updated_at();

create table profiles (
  id uuid primary key default gen_random_uuid(),
  user_id uuid unique references auth.users(id) on delete set null,
  user_kind user_kind not null default 'staff',
  is_admin boolean not null default false,
  full_name text not null,
  phone text,
  email text,
  customer_id uuid references customers(id),
  contractor_id uuid references contractors(id),
  notes text,
  is_active boolean not null default true,
  deleted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint profiles_customer_kind check (user_kind <> 'customer_user' or customer_id is not null),
  constraint profiles_contractor_kind check (user_kind <> 'contractor_user' or contractor_id is not null)
);
create index profiles_customer_idx on profiles (customer_id) where deleted_at is null;
create index profiles_contractor_idx on profiles (contractor_id) where deleted_at is null;
create index profiles_user_idx on profiles (user_id);
create index profiles_name_trgm on profiles using gin (full_name gin_trgm_ops);
create index profiles_phone_trgm on profiles using gin (phone gin_trgm_ops);
create trigger profiles_updated before update on profiles
  for each row execute function app.set_updated_at();

create table staff_roles (
  profile_id uuid not null references profiles(id) on delete cascade,
  role staff_role not null,
  primary key (profile_id, role)
);

create table contractor_workers (
  id uuid primary key default gen_random_uuid(),
  contractor_id uuid not null references contractors(id),
  full_name text not null,
  phone text,
  id_number text,
  user_id uuid references auth.users(id),
  is_active boolean not null default true,
  deleted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index contractor_workers_contractor_idx on contractor_workers (contractor_id) where deleted_at is null;
create trigger contractor_workers_updated before update on contractor_workers
  for each row execute function app.set_updated_at();
