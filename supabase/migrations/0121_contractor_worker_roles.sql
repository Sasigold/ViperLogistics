-- 0121: עובד קבלן יכול להיות ראש צוות ו/או נהג, והקבלן משבץ לפי התפקיד
--
-- עד כה סגל הקבלן היה שטוח: `task_contractor_workers` הוא (משימה, עובד) בלבד,
-- וכל עובד הוא "עובד". מעכשיו לעובד הקבלן יש תפקידים — ראש צוות ו/או נהג —
-- בדיוק כמו לאיש צוות פנימי (`staff_roles`), והקבלן משבץ עובד לתפקיד המתאים.
--
-- **התפקיד הוא הגדרה + שיבוץ.** `contractor_worker_roles` היא ההגדרה (מי
-- מוגדר מה), ו-`task_contractor_workers.role` הוא השיבוץ בפועל למשימה. אי
-- אפשר לשבץ עובד כראש צוות/נהג אם אינו מוגדר ככזה.

-- ===== 1. הגדרת התפקידים של עובד הקבלן ====================================
create table contractor_worker_roles (
  contractor_worker_id uuid not null references contractor_workers(id) on delete cascade,
  role staff_role not null,
  primary key (contractor_worker_id, role)
);
alter table contractor_worker_roles enable row level security;

-- אותה סמנטיקה של contractor_workers (0005): המשרד עם contractors.view/edit,
-- והקבלן על הסגל שלו.
create policy cwr_select on contractor_worker_roles for select to authenticated using (
  (select app.is_admin())
  or exists (select 1 from contractor_workers w
              where w.id = contractor_worker_id and w.deleted_at is null
                and (((select app.user_kind()) = 'staff' and app.has_permission('contractors','view'))
                     or w.contractor_id = (select app.contractor_id()))));
create policy cwr_staff_write on contractor_worker_roles for all to authenticated
  using ((select app.is_admin()) or app.has_permission('contractors','edit'))
  with check ((select app.is_admin()) or app.has_permission('contractors','edit'));
create policy cwr_own_write on contractor_worker_roles for all to authenticated
  using (exists (select 1 from contractor_workers w
                  where w.id = contractor_worker_id and w.contractor_id = (select app.contractor_id())))
  with check (exists (select 1 from contractor_workers w
                       where w.id = contractor_worker_id and w.contractor_id = (select app.contractor_id())));

-- ===== 2. שיבוץ לפי תפקיד =================================================
-- null = עובד רגיל (התנהגות קודמת). ראש צוות אחד לכל היותר בקרב סגל הקבלן על
-- משימה — מקביל ל-task_assignments_one_lead של הצוות הפנימי.
alter table task_contractor_workers add column role staff_role;
create unique index task_contractor_workers_one_lead
  on task_contractor_workers (task_id) where role = 'team_lead';

-- ה-RPC מקבל תפקיד, ומוודא שהעובד מוגדר בו. חתימה חדשה (6 ארגומנטים) —
-- מפילים את הקודמת כדי שלא יישארו שתי גרסאות.
drop function if exists contractor_assign_worker(uuid, uuid, uuid, boolean, text);
create or replace function contractor_assign_worker(
  p_task_id uuid,
  p_worker_id uuid default null,
  p_profile_id uuid default null,
  p_on boolean default true,
  p_work_site text default null,
  p_role staff_role default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_ctr    uuid;
  v_mine   uuid := app.contractor_id();
  v_worker uuid := p_worker_id;
  v_prof   profiles%rowtype;
  v_site   text := p_work_site;
begin
  if not (app.has('portal.assign_workers') or app.has('contractors.assign_workers')) then
    raise exception 'אין לך הרשאה לשבץ עובדי קבלן' using errcode = '42501';
  end if;

  -- פתרון העובד והקבלן שלו.
  if v_worker is null then
    if p_profile_id is null then
      raise exception 'חובה לנקוב בעובד או בחשבון' using errcode = '22023';
    end if;
    select * into v_prof from profiles where id = p_profile_id and deleted_at is null;
    if v_prof.id is null then
      raise exception 'העובד לא נמצא' using errcode = '42501';
    end if;
    v_ctr := v_prof.contractor_id;
    v_worker := v_prof.contractor_worker_id;
    if v_worker is null then
      if v_ctr is null then
        raise exception 'לחשבון אין קבלן משויך' using errcode = '42501';
      end if;
      insert into contractor_workers (contractor_id, full_name, phone)
      values (v_ctr, v_prof.full_name, v_prof.phone)
      returning id into v_worker;
      update profiles set contractor_worker_id = v_worker where id = v_prof.id;
    end if;
  else
    select contractor_id into v_ctr from contractor_workers
     where id = v_worker and deleted_at is null;
  end if;
  if v_ctr is null then
    raise exception 'לא נמצא קבלן לעובד' using errcode = '42501';
  end if;

  -- המשימה חייבת להיות מואצלת לקבלן של העובד.
  if not exists (select 1 from task_contractor_terms
                  where task_id = p_task_id and contractor_id = v_ctr) then
    raise exception 'המשימה אינה מואצלת לקבלן של העובד' using errcode = '42501';
  end if;

  -- קבלן משבץ רק את עובדיו; איש משרד צריך את המפתח המשרדי לקבלן אחר.
  if v_ctr is distinct from v_mine then
    perform app.require('contractors.assign_workers');
  end if;

  -- ‏0121: שיבוץ לתפקיד דורש שהעובד מוגדר בו. null = עובד רגיל.
  if p_role in ('team_lead', 'driver')
     and not exists (select 1 from contractor_worker_roles
                      where contractor_worker_id = v_worker and role = p_role) then
    raise exception 'העובד אינו מוגדר בתפקיד המבוקש' using errcode = '42501';
  end if;

  -- ‏0111: נקודת ההתחלה היא של המשרד. בלי המפתח המשרדי מה שנשלח מהקורא נזרק.
  if not app.has('contractors.assign_workers') then
    v_site := null;
  end if;
  if v_site is null then
    select coalesce(work_site, 'field') into v_site
      from task_contractor_terms where task_id = p_task_id and contractor_id = v_ctr;
    v_site := coalesce(v_site, 'field');
  end if;
  if v_site not in ('field', 'warehouse') then
    raise exception 'אתר עבודה לא חוקי: %', v_site using errcode = '22023';
  end if;

  if p_on then
    insert into task_contractor_workers (task_id, contractor_worker_id, work_site, role)
    values (p_task_id, v_worker, v_site, p_role)
    on conflict (task_id, contractor_worker_id) do update
      set work_site = excluded.work_site, role = excluded.role;
  else
    delete from task_contractor_workers
     where task_id = p_task_id and contractor_worker_id = v_worker;
  end if;

  return v_worker;
end $$;

revoke execute on function
  public.contractor_assign_worker(uuid, uuid, uuid, boolean, text, staff_role) from anon, public;
grant execute on function
  public.contractor_assign_worker(uuid, uuid, uuid, boolean, text, staff_role) to authenticated;

-- ===== 3. הסגל הניתן לשיבוץ מחזיר גם את התפקידים ==========================
create or replace function contractor_assignable_workers(p_contractor_id uuid default null)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_ctr uuid := app.contractor_id();
begin
  if v_ctr is null then
    v_ctr := p_contractor_id;
    if v_ctr is not null and not app.is_admin() then
      perform app.require('contractors.manage_workers');
    end if;
  end if;
  if v_ctr is null then return '[]'::jsonb; end if;

  return coalesce((
    select jsonb_agg(x order by x->>'full_name')
    from (
      select jsonb_build_object(
               'worker_id',  w.id,
               'profile_id', p.id,
               'full_name',  w.full_name,
               'phone',      w.phone,
               'has_login',  p.id is not null,
               'roles',      coalesce((select jsonb_agg(r.role order by r.role)
                                         from contractor_worker_roles r
                                        where r.contractor_worker_id = w.id), '[]'::jsonb)) as x,
             w.full_name
        from contractor_workers w
        left join profiles p
               on p.contractor_worker_id = w.id and p.deleted_at is null
       where w.contractor_id = v_ctr and w.deleted_at is null and w.is_active

      union all

      -- חשבונות תחת אותו קבלן שאין להם שורת רוסטר. אין להם שורת עובד ⇒ אין
      -- להם תפקידים להגדיר עדיין.
      select jsonb_build_object(
               'worker_id',  null,
               'profile_id', p.id,
               'full_name',  p.full_name,
               'phone',      p.phone,
               'has_login',  true,
               'roles',      '[]'::jsonb),
             p.full_name
        from profiles p
       where p.contractor_id = v_ctr
         and p.user_kind = 'contractor_user'
         and p.contractor_worker_id is null
         and p.deleted_at is null and p.is_active
    ) t(x, full_name)
  ), '[]'::jsonb);
end $$;

revoke execute on function public.contractor_assignable_workers(uuid) from anon, public;

-- ===== 4. work_board_view — תפקיד עובד הקבלן בתא =========================
-- הגוף זהה ל-0120 (0099 + performed_by), ועוד `role` ברשימת עובדי הקבלן.
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
                                      'work_site', tcw.work_site,
                                      'role', tcw.role)
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
