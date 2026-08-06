-- 0014: scoping the 'users' module so a client can be trusted with it.
--
-- 0010–0012 built the key model and the column-level gate, and between them
-- they already answer "may you touch this *kind* of thing" and "may you change
-- this *column*". What is still missing is "is this particular row yours" —
-- and that is the whole question once a customer_user may hold users.create or
-- users.manage_permissions.
--
-- Concretely, four gaps remain after 0012:
--   1. app.enforce_field_perms is BEFORE UPDATE only, so profiles.is_admin is
--      protected on update and wide open on insert.
--   2. profiles.user_id is not in field_registry, so nothing stops a client
--      from pointing an existing profile at their own auth user.
--   3. profiles_insert/profiles_update carry no customer scoping at all — a
--      client with users.edit reaches every tenant's people.
--   4. user_grants_write is `app.has('users.manage_permissions')` with no
--      subject test, so that key is self-escalation to anything.
--
-- Conventions below follow app.enforce_field_perms: skip when there is no JWT
-- (migrations, service role), skip inside app.system_write, skip for admins.

-- ===== object-level helpers =================================================

-- May the actor administer this *existing* profile? Deliberately silent about
-- which action — each caller pairs it with the key it needs. Self is always
-- excluded: every escalation path starts with editing yourself.
create or replace function app.can_manage_profile(p_target uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select case
    when app.is_admin() then true
    when p_target is null or p_target = app.profile_id() then false
    when app.user_kind() = 'staff' then app.has('users.edit')
    when app.user_kind() = 'customer_user' then exists (
      select 1 from profiles t
       where t.id = p_target
         and t.user_kind = 'customer_user'
         and t.customer_id is not null
         and t.customer_id = app.customer_id()
         and not t.is_admin
         and t.deleted_at is null)
    else false
  end
$$;

-- The same question for a row that does not exist yet, so it takes the shape
-- rather than the id. A client may only ever mint customer_user profiles of
-- their own customer, and only users.set_admin mints an admin.
create or replace function app.may_create_profile(
  p_kind user_kind, p_customer uuid, p_contractor uuid, p_is_admin boolean)
returns boolean language sql stable security definer set search_path = public as $$
  select case
    when app.is_admin() then true
    when not app.has('users.create') then false
    when coalesce(p_is_admin, false) and not app.has('users.set_admin') then false
    when app.user_kind() = 'staff' then true
    when app.user_kind() = 'customer_user' then
         p_kind = 'customer_user'
     and p_customer is not null and p_customer = app.customer_id()
     and p_contractor is null
    else false
  end
$$;

-- Exposed so the admin-users edge function authorizes against the same
-- predicate as RLS rather than re-deriving it in TypeScript and drifting.
create or replace function can_manage_profile(p_target uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select app.can_manage_profile(p_target)
$$;
revoke execute on function public.can_manage_profile(uuid) from anon, public;

-- ===== gaps the column gate cannot cover ====================================

create or replace function app.guard_profile_write()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null or app.in_system_write() or app.is_admin() then return new; end if;

  if tg_op = 'INSERT' then
    -- enforce_field_perms diffs old against new, so an INSERT reaches no rule
    -- at all. These two are the ones that matter on the way in.
    if new.is_admin and not app.has('users.set_admin') then
      raise exception 'רק בעל הרשאת ״הגדרת מנהל מערכת״ יכול ליצור מנהל מערכת'
        using errcode = '42501';
    end if;
    -- linking a login is the service role's job (see the admin-users function);
    -- allowing it here would let a client attach their own auth user to any row
    if new.user_id is not null then
      raise exception 'לא ניתן לקשר חשבון התחברות ישירות' using errcode = '42501';
    end if;
  elsif new.user_id is distinct from old.user_id then
    raise exception 'לא ניתן לשנות את חשבון ההתחברות' using errcode = '42501';
  end if;
  return new;
end $$;
create trigger profiles_guard before insert or update on profiles
  for each row execute function app.guard_profile_write();

-- Granting is the one write where "may you do this at all" is not enough: the
-- answer also depends on what the *granter* holds.
create or replace function app.guard_permission_grant()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_row user_permission_grants; v_applies user_kind[];
begin
  if auth.uid() is null or app.in_system_write() or app.is_admin() then
    return coalesce(new, old);
  end if;
  v_row := coalesce(new, old);

  if not app.can_manage_profile(v_row.profile_id) then
    raise exception 'אין לך הרשאה לנהל משתמש זה' using errcode = '42501';
  end if;
  if tg_op = 'DELETE' then return old; end if;

  -- you cannot hand out what you do not hold; taking away is always safe
  if new.allowed and not app.has(new.permission_key) then
    raise exception 'לא ניתן להעניק הרשאה שאין לך: %', new.permission_key using errcode = '42501';
  end if;

  -- and a client deals only in keys the catalog marks as client-facing, so the
  -- rule follows the registry instead of a list that would drift from it.
  -- Only granting is restricted: writing an explicit deny takes nothing away
  -- from anyone and is how the UI records "blocked" for an inherited key.
  if new.allowed and app.user_kind() = 'customer_user' then
    select applies_to into v_applies from permission_registry where key = new.permission_key;
    if v_applies is null or not ('customer_user' = any (v_applies)) then
      raise exception 'הרשאה זו אינה זמינה למשתמשי לקוח: %', new.permission_key using errcode = '42501';
    end if;
  end if;
  return new;
end $$;
create trigger user_permission_grants_guard
  before insert or update or delete on user_permission_grants
  for each row execute function app.guard_permission_grant();

-- ===== subject tests on the permission tables ===============================
-- Each of these was "do you hold the managing key", with no question of whose
-- row it is.

drop policy user_grants_write on user_permission_grants;
create policy user_grants_write on user_permission_grants for all to authenticated
  using ((select app.is_admin())
    or (app.has('users.manage_permissions') and app.can_manage_profile(profile_id)))
  with check ((select app.is_admin())
    or (app.has('users.manage_permissions') and app.can_manage_profile(profile_id)));

drop policy profile_roles_write on profile_roles;
create policy profile_roles_write on profile_roles for all to authenticated
  using ((select app.is_admin())
    or (app.has('users.manage_permissions') and app.can_manage_profile(profile_id)))
  with check ((select app.is_admin())
    or (app.has('users.manage_permissions') and app.can_manage_profile(profile_id)));

drop policy permission_scopes_write on permission_scopes;
create policy permission_scopes_write on permission_scopes for all to authenticated
  using ((select app.is_admin())
    or (app.has('users.manage_scopes') and profile_id is not null
        and app.can_manage_profile(profile_id)))
  with check ((select app.is_admin())
    or (app.has('users.manage_scopes') and profile_id is not null
        and app.can_manage_profile(profile_id)));

-- field_permissions rows with a null profile_id are kind- or role-wide
-- defaults: owner territory, not something a client edits for their own people.
drop policy fp_write on field_permissions;
create policy fp_write on field_permissions for all to authenticated
  using ((select app.is_admin())
    or (app.has('users.manage_permissions') and profile_id is not null
        and app.can_manage_profile(profile_id)))
  with check ((select app.is_admin())
    or (app.has('users.manage_permissions') and profile_id is not null
        and app.can_manage_profile(profile_id)));

-- staff_roles was readable by everyone signed in, so any client or contractor
-- could enumerate the staff roster and its profile ids; and its write gate had
-- no subject test, so users.edit was enough to hand out a driver role.
drop policy staff_roles_select on staff_roles;
create policy staff_roles_select on staff_roles for select to authenticated
  using ((select app.is_admin()) or (select app.user_kind()) = 'staff');
drop policy staff_roles_write on staff_roles;
create policy staff_roles_write on staff_roles for all to authenticated
  using ((select app.is_admin())
    or ((select app.user_kind()) = 'staff' and app.has('users.manage_staff_roles')))
  with check ((select app.is_admin())
    or ((select app.user_kind()) = 'staff' and app.has('users.manage_staff_roles')));

-- ===== profiles =============================================================

drop policy profiles_insert on profiles;
create policy profiles_insert on profiles for insert to authenticated with check (
  (select app.is_admin())
  or app.may_create_profile(user_kind, customer_id, contractor_id, is_admin));

drop policy profiles_update on profiles;
create policy profiles_update on profiles for update to authenticated
  using (
    (select app.is_admin())
    or (deleted_at is null and (
      ((select app.user_kind()) = 'staff' and app.has('users.edit'))
      or ((select app.user_kind()) = 'customer_user'
          and app.has('users.edit')
          and user_kind = 'customer_user'
          and customer_id = (select app.customer_id())
          and not is_admin
          and id <> (select app.profile_id()))
    )))
  -- there was no WITH CHECK at all, so a permitted row could be edited into
  -- one the same actor could never have selected
  with check (
    (select app.is_admin())
    or ((select app.user_kind()) = 'staff' and app.has('users.edit'))
    or ((select app.user_kind()) = 'customer_user'
        and app.has('users.edit')
        and user_kind = 'customer_user'
        and customer_id = (select app.customer_id())
        and contractor_id is null
        and not is_admin
        and id <> (select app.profile_id())));

-- ===== force clients through the event RPCs =================================
-- create_event/update_event are the only place the per-customer form config is
-- enforced — required fields, and which fields exist for this client at all.
-- events_field_perms (0012) column-gates a direct UPDATE, but an INSERT reaches
-- no rule, and neither covers "מספר אירוע is required for this customer". While
-- a client can POST straight to /rest/v1/events, that configuration is advisory.
--
-- The RPCs are SECURITY DEFINER and no table uses FORCE ROW LEVEL SECURITY, so
-- they keep working once the customer_user branch is gone from here.
drop policy events_insert on events;
create policy events_insert on events for insert to authenticated with check (
  (select app.is_admin())
  or ((select app.user_kind()) = 'staff' and app.has('events.create')));

drop policy events_update on events;
create policy events_update on events for update to authenticated using (
  (select app.is_admin())
  or (deleted_at is null and (select app.user_kind()) = 'staff' and app.has('events.edit')));

-- ===== soft_delete: SECURITY DEFINER, so RLS never sees it ==================
-- 0012 gave it the right *key* per table but no object test, so users.delete
-- still reaches every profile in every tenant — including the owner's.
create or replace function soft_delete(p_table text, p_id uuid, p_restore boolean default false)
returns void language plpgsql security definer set search_path = public as $$
declare v_key text;
begin
  v_key := case p_table
    when 'events'             then case when p_restore then 'events.restore'      else 'events.delete' end
    when 'tasks'              then case when p_restore then 'tasks.restore'       else 'tasks.delete' end
    when 'customers'          then case when p_restore then 'customers.restore'   else 'customers.delete' end
    when 'contractors'        then case when p_restore then 'contractors.restore' else 'contractors.delete' end
    when 'contractor_workers' then 'contractors.manage_workers'
    when 'profiles'           then case when p_restore then 'users.restore'       else 'users.delete' end
    when 'suppliers'          then 'customers.manage_suppliers'
    when 'trucks'             then 'settings.trucks'
    when 'task_types'         then 'settings.task_types'
    when 'execution_methods'  then 'settings.execution_methods'
    when 'statuses'           then 'settings.statuses'
    else null end;
  if v_key is null then raise exception 'טבלה לא נתמכת'; end if;
  perform app.require(v_key, 'אין לך הרשאה למחוק פריט זה');

  -- the key says "may delete this kind of thing"; this says "this one"
  if not app.is_admin() then
    if p_table = 'profiles' and not app.can_manage_profile(p_id) then
      raise exception 'אין לך הרשאה למחוק משתמש זה' using errcode = '42501';
    end if;
    if app.user_kind() = 'customer_user' then
      if p_table = 'events' then
        if not exists (select 1 from events
                       where id = p_id and customer_id = app.customer_id()) then
          raise exception 'אין לך הרשאה למחוק פריט זה' using errcode = '42501';
        end if;
      elsif p_table <> 'profiles' then
        raise exception 'אין לך הרשאה למחוק פריט זה' using errcode = '42501';
      end if;
    end if;
  end if;

  if p_table = 'task_types' and not p_restore
     and exists (select 1 from task_types where id = p_id and is_system) then
    raise exception 'לא ניתן למחוק סוג משימה מערכתי';
  end if;

  perform app.system_write(true);
  execute format('update %I set deleted_at = case when $2 then null else now() end where id = $1', p_table)
    using p_id, p_restore;
  perform app.system_write(false);
end $$;
