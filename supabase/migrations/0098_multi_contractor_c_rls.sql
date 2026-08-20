-- 0096c: RLS מבוסס-terms במקום tasks.contractor_id
--
-- כשלמשימה כמה קבלנים, "האם המשימה שלי" נקבע לפי קיום שורת terms שלי — ולא
-- לפי הקבלן היחיד ב-tasks.contractor_id (שהוא עכשיו רק הראשי). כל זרוע קבלן
-- בפוליסות הראייה/כתיבה עוברת לבדיקת exists על task_contractor_terms.

-- ===== tasks_select (הגוף מ-0083, זרוע הקבלן שונתה) ======================
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
         or exists (select 1 from task_assignments a
                    where a.task_id = tasks.id and a.profile_id = (select app.profile_id()))
         or ((select app.user_kind()) <> 'staff'
             and created_by = (select app.profile_id())))
    and ((select app.user_kind()) <> 'staff'
         or (select app.can_plan_tasks())
         or (created_by = (select app.profile_id())
             and not (select app.scope_own('tasks')))
         or status_id = (select s.id from statuses s
                          where s.entity = 'task' and s.code = 'assigned'
                            and s.deleted_at is null limit 1))
    and (
      ((select app.user_kind()) = 'staff' and (select app.has('tasks.view')))
      or ((select app.user_kind()) = 'customer_user' and customer_id = (select app.customer_id()))
      or ((select app.user_kind()) = 'contractor_user'
          and exists (select 1 from task_contractor_terms tct
                       where tct.task_id = tasks.id
                         and tct.contractor_id = (select app.contractor_id()))
          and ((select app.has('portal.view'))
               or (status_id = (select s.id from statuses s
                                 where s.entity = 'task' and s.code = 'assigned'
                                   and s.deleted_at is null limit 1)
                   and (select app.on_task_as_contractor_worker(tasks.id)))))
      or exists (select 1 from task_assignments a
                 where a.task_id = tasks.id and a.profile_id = (select app.profile_id()))
    )));

-- ===== events_select (הגוף מ-0082, זרוע הקבלן שונתה) =====================
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
         or (select app.on_event_as_staff(events.id))
         or ((select app.user_kind()) <> 'staff'
             and created_by = (select app.profile_id())))
    and (
      ((select app.user_kind()) = 'staff' and ((select app.has('events.view'))
         or (select app.on_event_as_staff(events.id))))
      or ((select app.user_kind()) = 'customer_user' and customer_id = (select app.customer_id()))
      or ((select app.user_kind()) = 'contractor_user' and (
            ((select app.has('portal.view')) and exists (
               select 1 from tasks t
                 join task_contractor_terms tct on tct.task_id = t.id
                where t.event_id = events.id
                  and tct.contractor_id = (select app.contractor_id()) and t.deleted_at is null))
            or (select app.on_event_as_contractor_worker(events.id))))
    )));

-- ===== task_contractor_workers: זרועות הקבלן מבוססות-terms ===============
drop policy tcw_select on task_contractor_workers;
create policy tcw_select on task_contractor_workers for select to authenticated using (
  (select app.is_admin())
  or ((select app.user_kind()) = 'staff'
      and ((select app.has_permission('tasks','view'))
           or (select app.has_permission('contractors','view'))))
  or exists (select 1 from task_contractor_terms tct
             where tct.task_id = task_id and tct.contractor_id = (select app.contractor_id())));

drop policy tcw_contractor_insert on task_contractor_workers;
create policy tcw_contractor_insert on task_contractor_workers for insert to authenticated
  with check (
    (select app.has('portal.assign_workers'))
    and exists (select 1 from task_contractor_terms tct
                where tct.task_id = task_id and tct.contractor_id = (select app.contractor_id()))
    and exists (select 1 from contractor_workers cw
                where cw.id = contractor_worker_id
                  and cw.contractor_id = (select app.contractor_id())
                  and cw.deleted_at is null));

drop policy tcw_contractor_delete on task_contractor_workers;
create policy tcw_contractor_delete on task_contractor_workers for delete to authenticated
  using (
    (select app.has('portal.assign_workers'))
    and exists (select 1 from task_contractor_terms tct
                where tct.task_id = task_id and tct.contractor_id = (select app.contractor_id())));

-- ===== עוזרי הראייה לתא הצוות (0091) — מבוססי terms ======================
create or replace function app.assignment_on_my_contractor(p_task_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select app.contractor_id() is not null
     and exists (select 1 from task_contractor_terms tct
                  where tct.task_id = p_task_id and tct.contractor_id = app.contractor_id())
$$;

create or replace function app.staff_on_my_contractor(p_profile_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select app.contractor_id() is not null
     and exists (select 1 from task_assignments a
                 join task_contractor_terms tct on tct.task_id = a.task_id
                  where a.profile_id = p_profile_id and tct.contractor_id = app.contractor_id())
$$;
