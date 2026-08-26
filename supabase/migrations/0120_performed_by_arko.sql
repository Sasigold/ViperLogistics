-- 0120: "בוצע ע"י" — ארקו מבצעת בעצמה, וייפר לא רואה ולא גובה
--
-- אצל ארקו יש משימות שהיא מבצעת בכוחות עצמה. לכל משימה נוסף השדה `performed_by`
-- (‏`viper` ברירת מחדל / `arko`). כשמשימה = `arko`:
--   * **מוסתרת לגמרי מוייפר** — צוות המשרד והשטח אינם רואים אותה בלו״ז, בלוח
--     השנה, בדף האירוע ובכל אגרגט; אירוע שכל משימותיו `arko` נעלם כולו. רק
--     לקוח ארקו (וה-admin) רואה.
--   * **המחיר 0** — אין מה שוייפר גובה על עבודה שלא ביצעה.
--
-- **הבורר מופיע רק אצל ארקו** — דגל פר-לקוח `customers.performed_by_enabled`,
-- שנדלק לארקו בזריעה כאן (כמו 0119). אין קידוד שם-לקוח בלוגיקה: הלוגיקה בודקת
-- את הדגל, וההצמדה לארקו היא נתון חד-פעמי.
--
-- **הכתיבה עוברת RPC** (`set_task_performed_by`), כמו `set_event_approved`:
-- ללקוח אין `UPDATE` ישיר על משימה מחוץ לשער הלו״ז, וזו הכרעה פר-משימה ולא
-- שדה-לו״ז. ה-RPC אוכף בעצמו מי רשאי, ועוטף את הכתיבה ב-`system_write` כדי
-- לעבור את שערי השדות והלו״ז.

-- ===== 1. סכמה ============================================================

alter table tasks add column performed_by text not null default 'viper'
  check (performed_by in ('viper', 'arko'));

alter table customers add column performed_by_enabled boolean not null default false;

-- הדלקת הדגל לארקו — נתון, לא קוד. אין לקוח כזה (אשכול בדיקות) ⇒ אפס שורות.
update customers set performed_by_enabled = true
 where name ilike '%ארקו%' and deleted_at is null;

-- השדה במרשם: כתיבת צוות נאכפת גנרית (`tasks.edit`); לא רגיש, נראה לכל מי
-- שרואה את המשימה.
select app.register_field('task', 'performed_by', 'בוצע ע"י', 'tasks',
  'tasks', 'performed_by', false, true, true, 'tasks.edit', 70);
select app.rebuild_secure_view('tasks');

-- ===== 2. תמחור 0 למשימת ארקו ============================================
-- קיצור דרך בראש `recalc_task_price`, לפני נעילת הידני ולפני בדיקת המצב:
-- משימת ארקו היא 0 תמיד. הכתיבה עטופה ב-system_write ולכן אינה נועלת.
create or replace function app.recalc_task_price(p_task_id uuid, p_force boolean default false)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  t          tasks;
  v_existing task_pricing;
  v_mode     text;
  v_config   jsonb;
  v_result   jsonb;
  v_prev     boolean;
begin
  select * into t from tasks where id = p_task_id;
  if t.id is null or t.deleted_at is not null then return null; end if;

  -- ‏0120: משימה שמבצעת ארקו אינה נגבית — 0 בלי קשר למחשבון או לנעילה.
  if t.performed_by = 'arko' then
    v_prev := app.in_system_write();
    perform app.system_write(true);
    insert into task_pricing (task_id, price, is_manual, breakdown, calculated_at)
    values (p_task_id, 0, false,
            jsonb_build_object('total', 0, 'reason', 'performed_by_arko'), now())
    on conflict (task_id) do update
      set price = 0, is_manual = false,
          breakdown = excluded.breakdown, calculated_at = excluded.calculated_at;
    perform app.system_write(v_prev);
    return jsonb_build_object('total', 0);
  end if;

  select * into v_existing from task_pricing where task_id = p_task_id;
  if v_existing.task_id is not null and v_existing.is_manual and not p_force then
    return null;
  end if;

  select pricing_mode into v_mode from customers where id = t.customer_id;
  if coalesce(v_mode, 'manual') <> 'auto' then return null; end if;

  select config into v_config from customer_pricing_rules
   where customer_id = t.customer_id and task_type_id = t.task_type_id and is_active;
  if v_config is null then return null; end if;

  v_result := app.price_calc(v_config, app.pricing_vars(p_task_id));

  v_prev := app.in_system_write();
  perform app.system_write(true);
  insert into task_pricing (task_id, price, is_manual, breakdown, calculated_at)
  values (p_task_id, (v_result ->> 'total')::numeric, false, v_result, now())
  on conflict (task_id) do update
    set price         = excluded.price,
        is_manual     = false,
        breakdown     = excluded.breakdown,
        calculated_at = excluded.calculated_at;
  perform app.system_write(v_prev);

  return v_result;
end $$;

-- מוסיפים את `performed_by` לרשימת עמודות טריגר החישוב: היפוך ערך מחשב מחדש.
drop trigger tasks_price on tasks;
create trigger tasks_price after insert or update of
    task_type_id, worker_count, hours_count, task_date, onsite_start_time,
    execution_method_id, truck_id, customer_id, event_id, travel_hours,
    requires_team_lead, performed_by
  on tasks for each row execute function app.tasks_recalc_price();

-- ===== 3. RPC לכתיבה מגודרת ==============================================
create or replace function set_task_performed_by(p_task_id uuid, p_value text)
returns void language plpgsql security definer set search_path = public as $$
declare
  t         tasks;
  v_enabled boolean;
begin
  if p_value not in ('viper', 'arko') then
    raise exception 'ערך לא חוקי לביצוע ע"י';
  end if;

  select * into t from tasks where id = p_task_id and deleted_at is null;
  if t.id is null then raise exception 'משימה לא נמצאה'; end if;

  select performed_by_enabled into v_enabled from customers where id = t.customer_id;

  if not (app.is_admin()
          or (app.user_kind() = 'staff' and app.has('tasks.edit'))
          or (app.user_kind() = 'customer_user'
              and t.customer_id = app.customer_id()
              and coalesce(v_enabled, false))) then
    raise exception 'אין לך הרשאה לקבוע מי מבצע את המשימה' using errcode = '42501';
  end if;

  -- דגל כבוי אצל הלקוח פירושו שהאפשרות אינה קיימת לו כלל.
  if app.user_kind() = 'staff' and not app.is_admin() and not coalesce(v_enabled, false) then
    raise exception 'האפשרות "בוצע ע"י" אינה מופעלת ללקוח זה';
  end if;

  perform app.system_write(true);
  update tasks set performed_by = p_value where id = p_task_id;
  perform app.system_write(false);
end $$;

revoke all on function set_task_performed_by(uuid, text) from public;
grant execute on function set_task_performed_by(uuid, text) to authenticated;

-- ===== 4. RLS — הסתרה מוייפר =============================================
-- האם כל משימותיו החיות של האירוע הן ארקו (ולכן האירוע מוסתר מוייפר). ‏≥1
-- משימה ואף אחת אינה viper. אירוע ללא משימות נשאר גלוי.
create or replace function app.event_all_tasks_arko(p_event_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from tasks t
                  where t.event_id = p_event_id and t.deleted_at is null)
     and not exists (select 1 from tasks t
                      where t.event_id = p_event_id and t.deleted_at is null
                        and coalesce(t.performed_by, 'viper') <> 'arko')
$$;

comment on function app.event_all_tasks_arko(uuid) is
  'האם כל משימות האירוע החיות בוצעו ע"י ארקו (0120) — ואז האירוע מוסתר מוייפר.';

-- ‏tasks_select: זרוע ה-staff אינה רואה משימת ארקו. שאר הזרועות (לקוח, קבלן,
-- משובץ) ללא שינוי, ו-admin עוקף בראש הפוליסה. הגוף זהה ל-0108.
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
         or (select app.assignment_on_my_contractor(tasks.id))
         or ((select app.user_kind()) <> 'staff'
             and created_by = (select app.profile_id())))
    and ((select app.user_kind()) <> 'staff'
         or (select app.can_plan_tasks())
         or (created_by = (select app.profile_id())
             and not (select app.scope_own('tasks')))
         or ((select app.has('portal.view'))
             and (select app.assignment_on_my_contractor(tasks.id)))
         or status_id = (select s.id from statuses s
                          where s.entity = 'task' and s.code = 'assigned'
                            and s.deleted_at is null limit 1))
    and (
      ((select app.user_kind()) = 'staff' and (select app.has('tasks.view'))
          and performed_by <> 'arko')
      or ((select app.user_kind()) = 'customer_user' and customer_id = (select app.customer_id()))
      or ((select app.contractor_id()) is not null
          and (select app.assignment_on_my_contractor(tasks.id))
          and ((select app.has('portal.view'))
               or (status_id = (select s.id from statuses s
                                 where s.entity = 'task' and s.code = 'assigned'
                                   and s.deleted_at is null limit 1)
                   and (select app.on_task_as_contractor_worker(tasks.id)))))
      or exists (select 1 from task_assignments a
                 where a.task_id = tasks.id and a.profile_id = (select app.profile_id()))
    )));

-- ‏events_select: זרוע ה-staff אינה רואה אירוע שכולו ארקו. הגוף זהה ל-0108.
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
         or (select app.event_on_my_contractor(events.id))
         or ((select app.user_kind()) <> 'staff'
             and created_by = (select app.profile_id())))
    and (
      ((select app.user_kind()) = 'staff' and ((select app.has('events.view'))
         or (select app.on_event_as_staff(events.id))
         or ((select app.has('portal.view'))
             and (select app.event_on_my_contractor(events.id))))
         and not (select app.event_all_tasks_arko(events.id)))
      or ((select app.user_kind()) = 'customer_user' and customer_id = (select app.customer_id()))
      or ((select app.contractor_id()) is not null and (
            ((select app.has('portal.view'))
             and (select app.event_on_my_contractor(events.id)))
            or (select app.on_event_as_contractor_worker(events.id))))
    )));

-- ===== 5. work_board_view — חושף את performed_by =========================
-- (‏security_invoker, ולכן משימות ארקו ממילא נושרות לצוות דרך tasks_select.)
-- הגוף זהה ל-0099; העמודה החדשה נוספת **בסוף** (create-or-replace מוסיף בסוף בלבד).
create or replace view work_board_view
with (security_invoker = true) as
select
  t.id,
  t.event_id,
  t.customer_id,
  c.name  as customer_name,
  c.color as customer_color,
  e.end_client_name,
  e.event_number,
  case when (select app.can_view_field('task', 'location_text'))
    then coalesce(t.location_text, e.location_text) end as location_text,
  e.volume_m,
  e.truck_count as event_truck_count,
  t.task_type_id,
  tt.name as task_type_name,
  tt.code as task_type_code,
  t.title,
  t.task_date,
  t.warehouse_start_time,
  t.onsite_start_time,
  t.onsite_end_time,
  t.hours_count,
  t.worker_count,
  t.execution_method_id,
  em.name as execution_method_name,
  t.truck_id,
  case when (select app.can_view_field('task', 'truck_id')) then tr.name end as truck_name,
  case when (select app.can_view_field('task', 'truck_free_text')) then t.truck_free_text end as truck_free_text,
  case when (select app.can_view_field('task', 'notes')) then t.notes end as notes,
  t.status_id,
  s.name  as status_name,
  s.color as status_color,
  s.is_terminal as status_is_terminal,
  t.contractor_id,
  case when (select app.has('contractors.view')) then ct.name end as contractor_name,
  t.created_at,
  t.updated_at,
  lead_p.full_name as team_lead_name,
  lead_a.profile_id as team_lead_id,
  workers.list  as workers,
  drivers.list  as drivers,
  cworkers.list as contractor_worker_list,
  case when (select app.has('pricing.view')) then tp.price end as customer_price,
  case when (select app.has('pricing.view')) then tp.is_manual end as price_is_manual,
  case when (select app.has('pricing.view')) then tp.breakdown end as price_breakdown,
  t.travel_hours,
  t.requires_team_lead,
  case when (select app.can_view_field('task', 'truck_ids')) then t.truck_ids end as truck_ids,
  case when (select app.can_view_field('task', 'truck_ids')) then tlist.list end as truck_list,
  coalesce(es.code = 'cancelled', false) as event_is_cancelled,
  s.code as status_code,
  case when (select app.has('contractors.view_pricing'))
       then case when (select app.contractor_id()) is not null then ctmine.price
                 else ctall.total_price end end as contractor_price,
  case when (select app.has('contractors.view_pricing')) then ctmine.price_per_worker end as contractor_price_per_worker,
  ctmine.work_site as contractor_work_site,
  ctmine.contractor_worker_count as contractor_worker_count,
  ctall.list as contractor_list,
  t.performed_by
from tasks t
left join events e     on e.id = t.event_id
left join app.customer_identities c on c.id = t.customer_id
join task_types tt     on tt.id = t.task_type_id
left join execution_methods em on em.id = t.execution_method_id
left join trucks tr    on tr.id = t.truck_id
join statuses s        on s.id = t.status_id
left join contractors ct on ct.id = t.contractor_id
left join statuses es  on es.id = e.status_id
left join task_pricing tp on tp.task_id = t.id
left join lateral (
  select
    jsonb_agg(jsonb_build_object(
      'contractor_id', tct.contractor_id,
      'name', ctx.name,
      'price', case when (select app.has('contractors.view_pricing')) then tct.price end,
      'price_per_worker', case when (select app.has('contractors.view_pricing')) then tct.price_per_worker end,
      'work_site', tct.work_site,
      'worker_count', tct.contractor_worker_count)
      order by tct.created_at, tct.contractor_id) as list,
    sum(tct.price) as total_price
  from task_contractor_terms tct
  join contractors ctx on ctx.id = tct.contractor_id
  where tct.task_id = t.id
) ctall on true
left join lateral (
  select tct.* from task_contractor_terms tct
  where tct.task_id = t.id
    and tct.contractor_id = coalesce((select app.contractor_id()), t.contractor_id)
  limit 1
) ctmine on true
left join lateral (
  select a.profile_id from task_assignments a
  where a.task_id = t.id and a.role = 'team_lead' limit 1
) lead_a on true
left join profiles lead_p on lead_p.id = lead_a.profile_id
left join lateral (
  select jsonb_agg(jsonb_build_object('profile_id', a.profile_id, 'name', p.full_name,
                                      'work_site', a.work_site)
                   order by p.full_name) as list
  from task_assignments a join profiles p on p.id = a.profile_id
  where a.task_id = t.id and a.role = 'worker'
) workers on true
left join lateral (
  select jsonb_agg(jsonb_build_object('profile_id', a.profile_id, 'name', p.full_name,
                                      'truck_id', a.truck_id, 'truck_name', tr2.name,
                                      'work_site', a.work_site)
                   order by p.full_name) as list
  from task_assignments a
  join profiles p on p.id = a.profile_id
  left join trucks tr2 on tr2.id = a.truck_id
  where a.task_id = t.id and a.role = 'driver'
) drivers on true
left join lateral (
  select jsonb_agg(jsonb_build_object('id', cw.id, 'name', cw.full_name,
                                      'contractor_id', cw.contractor_id,
                                      'work_site', tcw.work_site)
                   order by cw.full_name) as list
  from task_contractor_workers tcw join contractor_workers cw on cw.id = tcw.contractor_worker_id
  where tcw.task_id = t.id
) cworkers on true
left join lateral (
  select jsonb_agg(jsonb_build_object('id', tr3.id, 'name', tr3.name) order by u.ord) as list
  from unnest(t.truck_ids) with ordinality as u(truck_id, ord)
  join trucks tr3 on tr3.id = u.truck_id
) tlist on true
where t.deleted_at is null;
