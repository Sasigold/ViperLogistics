-- 0025: employee picker for the contractor's own attendance report
--
-- attendance_report() already scopes rows to the caller's own contractor
-- when `portal.attendance` is held (see 0024) — a contractor manager only
-- ever sees their own roster's entries, no matter what p_profile_ids holds.
-- What was missing was a way for the portal screen to *build* that filter:
-- profiles_select (0005) only lets a contractor_user read their own row, so
-- the client had nothing to populate an "employee" picker from. This RPC is
-- that picker's data source, gated by the same key the report itself checks.

create or replace function contractor_staff_list()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_contractor uuid := app.contractor_id();
begin
  perform app.require('portal.attendance');
  if v_contractor is null then
    return '[]'::jsonb;
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', p.id, 'full_name', p.full_name) order by p.full_name)
    from profiles p
    where p.contractor_id = v_contractor
      and p.deleted_at is null
      and p.is_active
  ), '[]'::jsonb);
end $$;

revoke execute on function public.contractor_staff_list() from anon, public;
