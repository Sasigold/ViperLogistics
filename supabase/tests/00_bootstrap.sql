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
