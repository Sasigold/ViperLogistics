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
