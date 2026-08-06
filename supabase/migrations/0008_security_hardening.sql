-- 0008: advisor fixes — pin search_path on trigger functions, revoke RPC access from anon
alter function app.set_updated_at() set search_path = public;
alter function app.sync_task_customer() set search_path = public;
alter function app.check_contractor_worker_limit() set search_path = public;

do $$
declare fn text;
begin
  foreach fn in array array[
    'create_event(jsonb)', 'update_event(uuid, jsonb)', 'duplicate_event(uuid, date)',
    'bulk_update_tasks(uuid[], jsonb)', 'bulk_import_events(jsonb)',
    'get_my_permissions()', 'mark_notifications_read(uuid[])',
    'soft_delete(text, uuid, boolean)', 'global_search(text, int)',
    'dashboard_stats(date, date)', 'contractor_dashboard(date, date)']
  loop
    execute format('revoke execute on function public.%s from anon, public', fn);
  end loop;
end $$;
