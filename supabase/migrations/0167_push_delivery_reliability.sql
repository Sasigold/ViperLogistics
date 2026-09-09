-- 0167: Web Push survives future migrations and each delivery is claimed exactly once.
--
-- 0113_notifications_stay_enabled_and_admin_single_push tried to stop duplicate
-- notifications by deleting every other subscription of an admin. That is the
-- wrong level for deduplication: a subscription is a device/browser, so an admin
-- is allowed to have several of them. Worse, notify-dispatch updates last_seen_at
-- after a successful push, which caused that trigger to delete another active
-- device while a batch was still being delivered.
--
-- The correct guarantees are:
--   * every active notification type defaults to push-on unless explicitly forced;
--   * a notification has at most one push delivery per subscription;
--   * concurrent dispatch invocations atomically claim different rows before
--     touching Apple/FCM, so the same row cannot be sent twice;
--   * stale claims can be retried after five minutes.

-- ===== 1. Undo the single-device admin workaround ============================
drop trigger if exists push_subscriptions_single_admin on public.push_subscriptions;
drop function if exists app.keep_single_admin_push_subscription();

-- ===== 2. Keep push globally enabled =========================================
update public.notification_types
   set default_mode_push = 'opt_out'
 where default_mode_push is distinct from 'forced';

update public.notification_policies
   set mode = 'opt_out'
 where channel = 'push'
   and mode is distinct from 'forced';

update public.notification_policy_overrides
   set mode = 'opt_out'
 where channel = 'push'
   and mode is distinct from 'forced';

update public.app_settings
   set value = jsonb_set(
                 jsonb_set(coalesce(value, '{}'::jsonb), '{enabled}', 'true'::jsonb, true),
                 '{muted_types}', '[]'::jsonb, true
               ),
       updated_at = now()
 where key = 'notifications.push';

-- ===== 3. Claim queue rows before external delivery ==========================
alter table public.notification_deliveries
  add column if not exists claimed_at timestamptz;

alter table public.notification_deliveries
  drop constraint if exists notification_deliveries_status_check;

alter table public.notification_deliveries
  add constraint notification_deliveries_status_check
  check (status = any (array['pending'::text, 'processing'::text, 'sent'::text, 'failed'::text, 'skipped'::text]));

-- One push per notification per concrete browser/device. This prevents a future
-- emitter or backfill from creating duplicate queue rows for the same endpoint.
create unique index if not exists notification_deliveries_push_once_idx
  on public.notification_deliveries (notification_id, subscription_id)
  where channel = 'push' and subscription_id is not null;

create index if not exists notification_deliveries_processing_idx
  on public.notification_deliveries (claimed_at, created_at)
  where status = 'processing';

create or replace function public.claim_notification_deliveries(
  p_delivery_id uuid default null,
  p_limit integer default 50
)
returns table(id uuid)
language sql
security definer
set search_path = public
as $$
  with candidates as (
    select d.id
      from public.notification_deliveries d
     where d.attempts < 5
       and (
         d.status = 'pending'
         or (d.status = 'processing' and d.claimed_at < now() - interval '5 minutes')
       )
       and (p_delivery_id is null or d.id = p_delivery_id)
     order by d.created_at, d.id
     for update skip locked
     limit greatest(1, least(coalesce(p_limit, 50), 200))
  )
  update public.notification_deliveries d
     set status = 'processing',
         claimed_at = now(),
         attempts = d.attempts + 1,
         last_error = null
    from candidates c
   where d.id = c.id
  returning d.id;
$$;

revoke all on function public.claim_notification_deliveries(uuid, integer) from public;
revoke all on function public.claim_notification_deliveries(uuid, integer) from anon;
revoke all on function public.claim_notification_deliveries(uuid, integer) from authenticated;
grant execute on function public.claim_notification_deliveries(uuid, integer) to service_role;

comment on function public.claim_notification_deliveries(uuid, integer) is
  'Atomically claims pending notification deliveries using FOR UPDATE SKIP LOCKED. Service-role only.';
