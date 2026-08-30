-- 0128: ראש הצוות יושב בשורת ראש הצוות, וגם כשהוא של הקבלן — ואין שני
--
-- שני דיווחים על אותו אזור:
--
-- **א. "כשקבלן משבץ ראש צוות העובד יופיע בשורה של ראש צוות".** ‏0121 נתן
-- לעובד הקבלן תפקיד, והלו״ז אף מחזיר אותו (`contractor_worker_list[].role`),
-- אבל תא "ראש צוות" קורא רק את `task_assignments`. התוצאה: ראש הצוות של
-- הקבלן נבלע ברשימת "צוות" עם כל השאר, והשורה שנועדה לו נשארת ריקה.
--
-- **ב. "כשמשובץ כבר ראש צוות אז הקבלן לא יוכל להגדיר ראש צוות".** האינדקס
-- `task_contractor_workers_one_lead` (0121) אמנם חוסם ראש שני *בקרב סגל
-- הקבלן*, אבל בהודעת `duplicate key` גולמית — ולא ידע דבר על ראש צוות פנימי
-- שכבר יושב על המשימה. **המשימה נושאת ראש צוות אחד**, לא אחד לכל מאגר, וזה
-- מה שנאמר בדיווח.
--
-- שימו לב שהנתיב הפנימי נשאר כפי שהוא: המשרד *מחליף* ראש צוות (הקליינט
-- מפנה את המושב לפני שהוא ממלא אותו), והוא זה שמנהל את השיבוץ. מה שנחסם הוא
-- הקבלן, שאינו אמור לדרוס הכרעה של המשרד.

-- ===== א. הלו״ז: נסיגה לראש צוות של הקבלן =================================
-- הגוף זהה ל-0123 מילה במילה, בתוספת ה-lateral ‏`lead_c`, ה-coalesce על
-- `team_lead_name` והעמודה החדשה `team_lead_kind` ('staff' / 'contractor').
-- שיבוץ פנימי גובר כששניהם קיימים — הוא ההכרעה של המשרד.
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
  coalesce(lead_p.full_name, lead_c.full_name) as team_lead_name,
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
  t.performed_by,
  -- ‏0128: עמודה חדשה נוספת בסוף — `create or replace view` אינו מרשה
  -- להכניס עמודה באמצע.
  case when lead_a.profile_id is not null then 'staff'
       when lead_c.id is not null then 'contractor' end as team_lead_kind
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
  select cw.id, cw.full_name
  from task_contractor_workers tcw
  join contractor_workers cw on cw.id = tcw.contractor_worker_id
  where tcw.task_id = t.id and tcw.role = 'team_lead' limit 1
) lead_c on true
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
where t.deleted_at is null and e.deleted_at is null;

-- ===== ב. ראש צוות אחד למשימה, ולא אחד לכל מאגר ===========================
-- הגוף זהה ל-0121, בתוספת הבדיקה המפורשת לפני הכתיבה. היא באה *אחרי* בדיקת
-- ההגדרה (`contractor_worker_roles`) כדי שההודעה הראשונה שאדם רואה תהיה על
-- מה שהוא שלט בו.
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

  -- ‏0128: ראש צוות אחד למשימה — פנימי או של קבלן, ולא אחד מכל סוג.
  if p_on and p_role = 'team_lead' then
    if exists (select 1 from task_assignments a
                where a.task_id = p_task_id and a.role = 'team_lead') then
      raise exception 'למשימה כבר מוגדר ראש צוות' using errcode = '42501';
    end if;
    if exists (select 1 from task_contractor_workers tcw
                where tcw.task_id = p_task_id and tcw.role = 'team_lead'
                  and tcw.contractor_worker_id is distinct from v_worker) then
      raise exception 'למשימה כבר מוגדר ראש צוות' using errcode = '42501';
    end if;
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

comment on function contractor_assign_worker(uuid, uuid, uuid, boolean, text, staff_role) is
  'שיבוץ עובד קבלן למשימה, עם תפקיד (0121). מ-0128 ראש צוות הוא אחד למשימה — '
  'ראש צוות פנימי חוסם אף הוא, וההודעה מפורשת ולא duplicate key.';
