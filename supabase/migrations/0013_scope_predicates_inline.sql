-- 0013: inline the scope predicates
--
-- 0012 expressed each scope dimension through app.in_id_scope() /
-- app.in_date_scope(). Two problems with that, both fixed by writing the
-- comparison out longhand:
--
--   * A SQL function without a pinned search_path trips Supabase's security
--     linter. Pinning it would silence the warning but stop the planner from
--     inlining the function — SQL functions carrying a SET clause are never
--     inlined — which is the worse outcome for a predicate evaluated on every
--     row of the work board.
--   * Written inline, the comparison is plain `= any(...)` on a scalar the
--     planner already computed once as an InitPlan. No function call per row
--     at all, and nothing left for the linter to flag.
--
-- Semantics are unchanged: a NULL scope array means "unrestricted on this
-- dimension", and a row whose value is NULL is excluded once that dimension is
-- restricted (`null = any(...)` is NULL, which fails the policy).

-- events
drop policy events_select on events;
create policy events_select on events for select to authenticated using (
  (select app.is_admin())
  or (deleted_at is null
    and ((select app.scope_ids('events', 'customers')) is null
         or customer_id = any((select app.scope_ids('events', 'customers'))::uuid[]))
    and ((select app.scope_ids('events', 'statuses')) is null
         or status_id = any((select app.scope_ids('events', 'statuses'))::uuid[]))
    and ((select app.scope_date_from('events')) is null
         or event_date >= (select app.scope_date_from('events')))
    and ((select app.scope_date_to('events')) is null
         or event_date <= (select app.scope_date_to('events')))
    and (not (select app.scope_own('events'))
         or created_by = (select app.profile_id())
         or exists (select 1 from tasks t
                    where t.event_id = events.id and t.deleted_at is null
                      and exists (select 1 from task_assignments a
                                  where a.task_id = t.id and a.profile_id = (select app.profile_id()))))
    and (
      ((select app.user_kind()) = 'staff' and (select app.has('events.view')))
      or ((select app.user_kind()) = 'customer_user' and customer_id = (select app.customer_id()))
      or ((select app.user_kind()) = 'contractor_user' and exists (
            select 1 from tasks t where t.event_id = events.id
              and t.contractor_id = (select app.contractor_id()) and t.deleted_at is null))
    )));

-- tasks
drop policy tasks_select on tasks;
create policy tasks_select on tasks for select to authenticated using (
  (select app.is_admin())
  or (deleted_at is null
    and ((select app.scope_ids('tasks', 'customers')) is null
         or customer_id = any((select app.scope_ids('tasks', 'customers'))::uuid[]))
    and ((select app.scope_ids('tasks', 'contractors')) is null
         or contractor_id = any((select app.scope_ids('tasks', 'contractors'))::uuid[]))
    and ((select app.scope_ids('tasks', 'task_types')) is null
         or task_type_id = any((select app.scope_ids('tasks', 'task_types'))::uuid[]))
    and ((select app.scope_ids('tasks', 'statuses')) is null
         or status_id = any((select app.scope_ids('tasks', 'statuses'))::uuid[]))
    and ((select app.scope_ids('tasks', 'execution_methods')) is null
         or execution_method_id = any((select app.scope_ids('tasks', 'execution_methods'))::uuid[]))
    and ((select app.scope_ids('tasks', 'trucks')) is null
         or truck_id = any((select app.scope_ids('tasks', 'trucks'))::uuid[]))
    and ((select app.scope_date_from('tasks')) is null
         or task_date >= (select app.scope_date_from('tasks')))
    and ((select app.scope_date_to('tasks')) is null
         or task_date <= (select app.scope_date_to('tasks')))
    and (not (select app.scope_own('tasks'))
         or created_by = (select app.profile_id())
         or exists (select 1 from task_assignments a
                    where a.task_id = tasks.id and a.profile_id = (select app.profile_id())))
    and (
      ((select app.user_kind()) = 'staff' and (select app.has('tasks.view')))
      or ((select app.user_kind()) = 'customer_user' and customer_id = (select app.customer_id()))
      or ((select app.user_kind()) = 'contractor_user' and contractor_id = (select app.contractor_id()))
      or exists (select 1 from task_assignments a
                 where a.task_id = tasks.id and a.profile_id = (select app.profile_id()))
    )));

-- customers
drop policy customers_select on customers;
create policy customers_select on customers for select to authenticated using (
  (select app.is_admin())
  or (deleted_at is null
    and ((select app.scope_ids('customers', 'customers')) is null
         or id = any((select app.scope_ids('customers', 'customers'))::uuid[]))
    and (
      ((select app.user_kind()) = 'staff' and (select app.has('customers.view')))
      or id = (select app.customer_id())
      or ((select app.user_kind()) = 'contractor_user' and exists (
            select 1 from tasks t where t.customer_id = customers.id
              and t.contractor_id = (select app.contractor_id()) and t.deleted_at is null))
    )));

-- contractors
drop policy contractors_select on contractors;
create policy contractors_select on contractors for select to authenticated using (
  (select app.is_admin())
  or (deleted_at is null
    and ((select app.scope_ids('contractors', 'contractors')) is null
         or id = any((select app.scope_ids('contractors', 'contractors'))::uuid[]))
    and (
      ((select app.user_kind()) = 'staff' and (select app.has('contractors.view')))
      or id = (select app.contractor_id())
    )));

drop function app.in_id_scope(uuid[], uuid);
drop function app.in_date_scope(date, date, date);
