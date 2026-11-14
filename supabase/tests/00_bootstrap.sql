-- Minimal Supabase-shaped scaffolding so the repo's migrations can be applied
-- verbatim against a stock PostgreSQL 16.
-- roles are cluster-wide, so this has to survive a database re-create
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then
    create role anon nologin;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then
    create role authenticated nologin;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role') then
    create role service_role nologin bypassrls;
  end if;
end $$;

create schema if not exists auth;

create table auth.users (
  id uuid primary key default gen_random_uuid(),
  email text
);

-- Supabase resolves this from the request JWT; here it is a settable GUC so
-- tests can impersonate a user with set_config('request.jwt.claim.sub', ...).
create or replace function auth.uid() returns uuid
language sql stable as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
$$;

grant usage on schema auth to anon, authenticated, service_role;
grant select on auth.users to authenticated, service_role;

-- Storage, in the shape 0077 needs. Supabase ships a much larger schema; what
-- matters here is that `storage.buckets` and `storage.objects` exist with RLS
-- on, so the bucket row and the object policies are actually created and can be
-- asserted against instead of silently skipped.
create schema if not exists storage;

create table storage.buckets (
  id text primary key,
  name text not null,
  public boolean not null default false,
  file_size_limit bigint,
  allowed_mime_types text[],
  created_at timestamptz not null default now()
);

create table storage.objects (
  id uuid primary key default gen_random_uuid(),
  bucket_id text not null references storage.buckets(id),
  name text not null,
  owner uuid,
  metadata jsonb,
  created_at timestamptz not null default now(),
  unique (bucket_id, name)
);
alter table storage.objects enable row level security;

grant usage on schema storage to anon, authenticated, service_role;
grant select on storage.buckets to authenticated, service_role;
grant all on storage.objects to authenticated, service_role;

-- Realtime, in the shape 0101 needs. On hosted Supabase `realtime.send` fans a
-- broadcast message out over websockets; here it lands in a plain table, so the
-- suite can assert exactly which topics a change was sent to. `realtime.topic()`
-- is the topic a client asked to join — Supabase resolves it from the join
-- request; here it is a settable GUC, so the tests can exercise the
-- authorization policy with set_config('realtime.topic', ...).
create schema if not exists realtime;

create table realtime.messages (
  id bigint generated always as identity primary key,
  topic text not null,
  extension text not null default 'broadcast',
  event text,
  payload jsonb,
  private boolean not null default true,
  inserted_at timestamptz not null default now()
);
alter table realtime.messages enable row level security;

create or replace function realtime.send(payload jsonb, event text, topic text, private boolean default true)
returns void language sql as $$
  insert into realtime.messages (payload, event, topic, private)
  values (send.payload, send.event, send.topic, send.private)
$$;

create or replace function realtime.topic() returns text
language sql stable as $$
  select nullif(current_setting('realtime.topic', true), '')
$$;

grant usage on schema realtime to authenticated, service_role;
grant select on realtime.messages to authenticated, service_role;

-- Vault, in the shape 0202 needs. On hosted Supabase `supabase_vault` keeps
-- the secret encrypted and decrypts it in `vault.decrypted_secrets`; here the
-- "encryption" is the identity, because what is under test is who may read the
-- view and what the caller does with the value — not pgsodium. The two
-- functions keep the hosted signatures, so the ops note in CLAUDE.md
-- (`vault.create_secret(...)`, `vault.update_secret(...)`) runs here verbatim.
--
-- Nothing is granted on the schema: on Supabase neither anon, authenticated
-- nor service_role can read the decrypted view, and a `security definer`
-- function owned by postgres is the only door. Keeping it that way here is
-- what lets the suite show that the wall feed works through that door alone.
create schema if not exists vault;

create table vault.secrets (
  id          uuid primary key default gen_random_uuid(),
  name        text unique,
  description text not null default '',
  secret      text not null,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create view vault.decrypted_secrets as
  select s.id, s.name, s.description, s.secret,
         s.secret as decrypted_secret, s.created_at, s.updated_at
    from vault.secrets s;

create or replace function vault.create_secret(
  new_secret text, new_name text default null,
  new_description text default '', new_key_id uuid default null)
returns uuid language sql as $$
  insert into vault.secrets (secret, name, description)
  values (new_secret, new_name, coalesce(new_description, ''))
  returning id
$$;

create or replace function vault.update_secret(
  secret_id uuid, new_secret text default null, new_name text default null,
  new_description text default null, new_key_id uuid default null)
returns void language sql as $$
  update vault.secrets
     set secret      = coalesce(new_secret, secret),
         name        = coalesce(new_name, name),
         description = coalesce(new_description, description),
         updated_at  = now()
   where id = secret_id
$$;

revoke all on schema vault from public;
revoke all on all tables in schema vault from public;
revoke execute on all functions in schema vault from public;
