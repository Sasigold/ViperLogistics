-- 0140: סגל הלקוח משרת גם את משימות וייפר, והחזרה מנקה אותו
--
-- שני חצאים של אותה הכרעה, שהתקבלה יחד עם 0139:
--
-- **‏(17) מנהל המערכת משבץ את עובדי הלקוח.** ‏0133 דרשה שהמשימה תהיה מסומנת
-- "בוצע ע"י" הלקוח — כלומר סגל הלקוח שירת אך ורק את המשימות שוייפר אינה
-- מבצעת. אחרי 0139 מנהל המערכת אינו רואה את המשימות האלה כלל, ולכן התנאי
-- הזה הפך את הסגל לבלתי-שביץ בידו לחלוטין. התנאי יורד: מה שנשאר הוא
-- `customers.performed_by_enabled` על הלקוח של המשימה, ומי רשאי לשבץ נשאר
-- כפי שהיה. **הראייה היא שמפרידה** — המשרד משבץ על משימות הוייפר של אותו
-- לקוח, שאותן הוא רואה, וארקו על שלה.
--
-- **‏(16) והמעבר בחזרה לוייפר מסיר את שמות העובדים.**
-- ‏`app.tasks_clear_crew_on_arko` (0135) טיפלה רק בכיוון אחד. הסגל שעל
-- המשימה בזמן שארקו ביצעה אותה הוא הסגל *שלה*, ומשימה שחזרה לוייפר אינה
-- שלה עוד — הצוות שלה נשאר על המסך כאילו הוא עדיין מגיע. הענף השני מנקה
-- אותו, והמשרד משבץ מחדש את מי שצריך.

-- ===== 1. האם ללקוח יש סגל משלו ==========================================
-- שאלה של שורה ולא של קורא, ולכן היא נפרדת מ-`app.own_staff_customer_id()`.
-- ‏`security definer` כי `customers` מוגנת ב-RLS ו-`work_board_view` הוא
-- `security_invoker` — בלי זה איש שטח היה מקבל NULL והתא היה נסגר לו בשקט.
create or replace function app.customer_self_performing(p_customer_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select c.performed_by_enabled from customers c
                    where c.id = p_customer_id and c.deleted_at is null), false)
$$;

comment on function app.customer_self_performing(uuid) is
  'האם הלקוח מסומן כמבצע בעצמו (0120) — כלומר יש לו סגל משלו (0133/0140).';

revoke execute on function app.customer_self_performing(uuid) from anon;
grant execute on function app.customer_self_performing(uuid) to authenticated;

-- ===== 2. השיבוץ אינו מוגבל עוד למשימת ארקו ==============================
-- הגוף זהה ל-0133 מילה במילה, פחות שער אחד.
create or replace function customer_assign_worker(
  p_task_id uuid,
  p_worker_id uuid,
  p_on boolean default true,
  p_work_site text default null,
  p_role staff_role default null,
  p_truck_id uuid default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_task    tasks%rowtype;
  v_ctr     uuid;
  v_site    text := coalesce(p_work_site, 'field');
  v_enabled boolean;
begin
  select * into v_task from tasks where id = p_task_id and deleted_at is null;
  if v_task.id is null then
    raise exception 'המשימה לא נמצאה' using errcode = '42501';
  end if;

  select coalesce(performed_by_enabled, false) into v_enabled
    from customers where id = v_task.customer_id;

  if not coalesce(v_enabled, false) then
    raise exception 'האפשרות "בוצע ע"י" אינה מופעלת ללקוח זה';
  end if;

  -- מי רשאי: מנהל מערכת, איש משרד שמשבץ, או הלקוח על המשימות שלו עצמו.
  if not (app.is_admin()
          or (app.user_kind() = 'staff' and app.has('tasks.assign.worker'))
          or (app.user_kind() = 'customer_user'
              and v_task.customer_id = app.customer_id()
              and app.has('customers.assign_own_staff'))) then
    raise exception 'אין לך הרשאה לשבץ את סגל הלקוח' using errcode = '42501';
  end if;

  -- העובד חייב להיות של אותו לקוח.
  select customer_id into v_ctr from customer_workers
   where id = p_worker_id and deleted_at is null and is_active;
  if v_ctr is null then
    raise exception 'העובד לא נמצא' using errcode = '42501';
  end if;
  if v_ctr is distinct from v_task.customer_id then
    raise exception 'העובד אינו שייך ללקוח של המשימה' using errcode = '42501';
  end if;

  if not p_on then
    delete from task_customer_workers
     where task_id = p_task_id and customer_worker_id = p_worker_id;
    return p_worker_id;
  end if;

  -- התפקיד הוא הגדרה ואז שיבוץ (0121). null = עובד רגיל.
  if p_role in ('team_lead', 'driver')
     and not exists (select 1 from customer_worker_roles
                      where customer_worker_id = p_worker_id and role = p_role) then
    raise exception 'העובד אינו מוגדר בתפקיד המבוקש' using errcode = '42501';
  end if;

  -- ראש צוות אחד למשימה, על שלושת המאגרים (0128).
  if p_role = 'team_lead' then
    if exists (select 1 from task_assignments a
                where a.task_id = p_task_id and a.role = 'team_lead')
       or exists (select 1 from task_contractor_workers tcw
                   where tcw.task_id = p_task_id and tcw.role = 'team_lead')
       or exists (select 1 from task_customer_workers x
                   where x.task_id = p_task_id and x.role = 'team_lead'
                     and x.customer_worker_id is distinct from p_worker_id) then
      raise exception 'למשימה כבר מוגדר ראש צוות' using errcode = '42501';
    end if;
  end if;

  if v_site not in ('field', 'warehouse') then
    raise exception 'אתר עבודה לא חוקי: %', v_site using errcode = '22023';
  end if;

  -- המשאית של הנהג מוגבלת לרשימת המשאיות של הלקוח, כשיש כזו (0116). רשימה
  -- ריקה = כל הקטלוג, בדיוק כמו בתא המשאיות של הלו״ז.
  if p_truck_id is not null then
    if not exists (select 1 from trucks t where t.id = p_truck_id and t.deleted_at is null) then
      raise exception 'המשאית לא נמצאה' using errcode = '42501';
    end if;
    if exists (select 1 from customer_trucks where customer_id = v_task.customer_id)
       and not exists (select 1 from customer_trucks
                        where customer_id = v_task.customer_id and truck_id = p_truck_id) then
      raise exception 'המשאית אינה ברשימת המשאיות של הלקוח' using errcode = '42501';
    end if;
  end if;

  insert into task_customer_workers (task_id, customer_worker_id, work_site, role, truck_id)
  values (p_task_id, p_worker_id, v_site, p_role, p_truck_id)
  on conflict (task_id, customer_worker_id) do update
    set work_site = excluded.work_site,
        role      = excluded.role,
        truck_id  = excluded.truck_id;

  return p_worker_id;
end $$;

comment on function customer_assign_worker(uuid, uuid, boolean, text, staff_role, uuid) is
  'שיבוץ עובד מסגל הלקוח למשימה של אותו לקוח (0133). מ-0140 גם למשימה '
  'שוייפר מבצעת — הראייה היא שמפרידה בין מי שמשבץ על מה.';

-- ===== 3. החזרה לוייפר מנקה את סגל הלקוח =================================
-- הגוף זהה ל-0135, בתוספת הענף השני. הוא נבדק ראשון כי הוא הזול משניהם.
create or replace function app.tasks_clear_crew_on_arko()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  -- ‏0140: חזרה לוייפר — הסגל של הלקוח יורד מהמשימה שכבר אינה שלו.
  if new.performed_by = 'viper' and old.performed_by = 'arko' then
    delete from task_customer_workers where task_id = new.id;
    return new;
  end if;

  if new.performed_by <> 'arko' or old.performed_by = 'arko' then
    return new;
  end if;

  if exists (select 1 from task_contractor_terms
              where task_id = new.id and paid_at is not null) then
    raise exception 'לא ניתן להעביר לארקו משימה שההאצלה שלה כבר שולמה';
  end if;

  delete from task_assignments        where task_id = new.id;
  delete from task_contractor_workers where task_id = new.id;
  delete from task_contractor_terms   where task_id = new.id;

  return new;
end $$;

comment on function app.tasks_clear_crew_on_arko() is
  'מעבר בין זרועות הביצוע מפנה את המשימה ממי שכבר אינו שלה (0135/0140): '
  'לארקו — שיבוצים פנימיים, סגל קבלן וההאצלה; ובחזרה לוייפר — סגל הלקוח. '
  'האצלה ששולמה חוסמת את המעבר לארקו.';

-- הטריגר עצמו לא השתנה ואינו נוצר מחדש.

-- ===== 4. הלוח יודע למי יש סגל ===========================================
-- עמודה חדשה בסוף, כרגיל.
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
  coalesce(lead_p.full_name, lead_c.full_name, lead_o.full_name) as team_lead_name,
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
       when lead_c.id is not null then 'contractor'
       when lead_o.id is not null then 'customer' end as team_lead_kind,
  -- ‏0134: סגל הלקוח על המשימה, במתכונת `contractor_worker_list`.
  oworkers.list as customer_worker_list,
  -- ‏0140: האם ללקוח של השורה יש סגל משלו. עד כה התא נפתח לפי
  -- `performed_by = 'arko'`, וזה כבר אינו התנאי.
  (select app.customer_self_performing(t.customer_id)) as customer_self_performing
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
  select cuw.id, cuw.full_name
  from task_customer_workers tcuw
  join customer_workers cuw on cuw.id = tcuw.customer_worker_id
  where tcuw.task_id = t.id and tcuw.role = 'team_lead' limit 1
) lead_o on true
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
  select jsonb_agg(jsonb_build_object('id', cuw.id, 'name', cuw.full_name,
                                      'work_site', tcuw.work_site,
                                      'role', tcuw.role,
                                      'truck_id', tcuw.truck_id,
                                      'truck_name', tr4.name)
                   order by cuw.full_name) as list
  from task_customer_workers tcuw
  join customer_workers cuw on cuw.id = tcuw.customer_worker_id
  left join trucks tr4 on tr4.id = tcuw.truck_id
  where tcuw.task_id = t.id
) oworkers on true
left join lateral (
  select jsonb_agg(jsonb_build_object('id', tr3.id, 'name', tr3.name) order by u.ord) as list
  from unnest(t.truck_ids) with ordinality as u(truck_id, ord)
  join trucks tr3 on tr3.id = u.truck_id
) tlist on true
where t.deleted_at is null and e.deleted_at is null;
