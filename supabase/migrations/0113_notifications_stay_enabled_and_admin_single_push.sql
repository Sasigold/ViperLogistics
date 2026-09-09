-- 0113: keep push notifications enabled and prevent duplicate admin push deliveries
--
-- Some earlier migrations register notification types with opt_in defaults.
-- This migration makes the current operational choice explicit: push is enabled
-- for every notification type, nothing is globally muted, and admin accounts keep
-- a single active push subscription so one notification cannot fan out twice.

update notification_types
set default_mode_push = 'opt_out'
where default_mode_push is distinct from 'forced';

update app_settings
set value = jsonb_set(
              jsonb_set(coalesce(value, '{}'::jsonb), '{enabled}', 'true'::jsonb, true),
              '{muted_types}', '[]'::jsonb, true
            )
where key = 'notifications.push';

update notification_policies
set mode = 'opt_out'
where channel = 'push' and mode is distinct from 'forced';

update notification_policy_overrides
set mode = 'opt_out'
where channel = 'push' and mode is distinct from 'forced';

create or replace function app.keep_single_admin_push_subscription()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if exists (
    select 1
    from profiles p
    where p.id = new.profile_id
      and p.is_admin
      and p.deleted_at is null
      and p.is_active
  ) then
    delete from push_subscriptions ps
    where ps.profile_id = new.profile_id
      and ps.id <> new.id;
  end if;
  return new;
end;
$$;

drop trigger if exists push_subscriptions_single_admin on push_subscriptions;
create trigger push_subscriptions_single_admin
after insert or update of endpoint, p256dh, auth, last_seen_at on push_subscriptions
for each row execute function app.keep_single_admin_push_subscription();

with ranked as (
  select ps.id,
         row_number() over (
           partition by ps.profile_id
           order by ps.last_seen_at desc nulls last, ps.created_at desc, ps.id desc
         ) as rn
  from push_subscriptions ps
  join profiles p on p.id = ps.profile_id
  where p.is_admin
    and p.deleted_at is null
    and p.is_active
)
delete from push_subscriptions ps
using ranked r
where ps.id = r.id
  and r.rn > 1;
