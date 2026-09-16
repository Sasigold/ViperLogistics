-- 0175: מפת עומסים — הגדרת קיבולת מדויקת ובחירת בסיס חישוב (צוות פנימי / קבלנים)
--
-- הרחבה של 0173:
-- 1. app.load_capacity מקבלת p_scope ו-p_contractor_id:
--    - 'internal': סופרת אך ורק עובדי צוות פנימיים פעילים (או את המספר הידני שנקבע ב-ops.capacity).
--    - 'contractor': קיבולת הקבלן הנבחר (לפי עובדי הקבלן הפעילים שלו במאגר או הגדרה ידנית).
--    - 'all': הקיבולת הכללית של המערכת.
-- 2. app.load_tasks ו-app.load_slots מסננות משימות בהתאם ל-scope ולקבלן שנבחר.
-- 3. load_heatmap ו-load_day מקבלות p_scope ו-p_contractor_id ומחזירות נתוני עומס מדויקים.

-- הסרת הגרסאות הקודמות למניעת עמימות חתימות
drop function if exists load_heatmap(date, date);
drop function if exists load_day(date);
drop function if exists app.load_slots(date, date);
drop function if exists app.load_tasks(date, date);
drop function if exists app.load_capacity();

-- ===== 1. חישוב קיבולת לפי Scope וקבלן =====================================

create or replace function app.load_capacity(
  p_scope text default 'all',
  p_contractor_id uuid default null
)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_cfg jsonb;
  v_workers numeric;
  v_trucks numeric;
  v_leads numeric;
  v_workers_source text := 'derived';
  v_trucks_source text := 'derived';
  v_leads_source text := 'derived';
  v_c_cfg jsonb;
begin
  select coalesce((select value from app_settings where key = 'ops.capacity'), '{}'::jsonb) into v_cfg;

  if p_scope = 'contractor' and p_contractor_id is not null then
    -- קבלן ספציפי: נבדוק אם הוגדרה לו תקרה ספציפית ב-ops.capacity -> contractors -> <id>
    v_c_cfg := v_cfg -> 'contractors' -> p_contractor_id::text;

    if v_c_cfg ->> 'workers' is not null and (v_c_cfg ->> 'workers')::numeric >= 0 then
      v_workers := (v_c_cfg ->> 'workers')::numeric;
      v_workers_source := 'configured';
    else
      select count(*) into v_workers
      from contractor_workers w
      where w.contractor_id = p_contractor_id
        and w.deleted_at is null and w.is_active;
    end if;

    if v_c_cfg ->> 'trucks' is not null and (v_c_cfg ->> 'trucks')::numeric >= 0 then
      v_trucks := (v_c_cfg ->> 'trucks')::numeric;
      v_trucks_source := 'configured';
    else
      v_trucks := 0; -- לקבלן אין תקרת משאיות ברירת מחדל אלא אם הוגדר
    end if;

    if v_c_cfg ->> 'team_leads' is not null and (v_c_cfg ->> 'team_leads')::numeric >= 0 then
      v_leads := (v_c_cfg ->> 'team_leads')::numeric;
      v_leads_source := 'configured';
    else
      select count(*) into v_leads
      from contractor_workers w
      join contractor_worker_roles r on r.contractor_worker_id = w.id
      where w.contractor_id = p_contractor_id
        and w.deleted_at is null and w.is_active
        and r.role = 'team_lead';
    end if;

  elsif p_scope = 'internal' then
    -- צוות פנימי בלבד: סופר אך ורק עובדי צוות פעילים, ללא עובדי קבלנים
    if v_cfg ->> 'workers' is not null and (v_cfg ->> 'workers')::numeric >= 0 then
      v_workers := (v_cfg ->> 'workers')::numeric;
      v_workers_source := 'configured';
    else
      select count(*) into v_workers
      from profiles p
      where p.deleted_at is null and p.is_active
        and exists (select 1 from staff_roles r where r.profile_id = p.id);
    end if;

    if v_cfg ->> 'trucks' is not null and (v_cfg ->> 'trucks')::numeric >= 0 then
      v_trucks := (v_cfg ->> 'trucks')::numeric;
      v_trucks_source := 'configured';
    else
      select count(*) into v_trucks
      from trucks t
      where t.deleted_at is null and t.is_active;
    end if;

    if v_cfg ->> 'team_leads' is not null and (v_cfg ->> 'team_leads')::numeric >= 0 then
      v_leads := (v_cfg ->> 'team_leads')::numeric;
      v_leads_source := 'configured';
    else
      select count(*) into v_leads
      from profiles p
      where p.deleted_at is null and p.is_active
        and exists (select 1 from staff_roles r where r.profile_id = p.id and r.role = 'team_lead');
    end if;

  else
    -- כללי (כולל הכל)
    if v_cfg ->> 'workers' is not null and (v_cfg ->> 'workers')::numeric >= 0 then
      v_workers := (v_cfg ->> 'workers')::numeric;
      v_workers_source := 'configured';
    else
      select
        (select count(*) from profiles p
          where p.deleted_at is null and p.is_active
            and exists (select 1 from staff_roles r where r.profile_id = p.id))
        + (select count(*) from contractor_workers w
            join contractors c on c.id = w.contractor_id
           where w.deleted_at is null and w.is_active
             and c.deleted_at is null and c.is_active) into v_workers;
    end if;

    if v_cfg ->> 'trucks' is not null and (v_cfg ->> 'trucks')::numeric >= 0 then
      v_trucks := (v_cfg ->> 'trucks')::numeric;
      v_trucks_source := 'configured';
    else
      select count(*) into v_trucks
      from trucks t
      where t.deleted_at is null and t.is_active;
    end if;

    if v_cfg ->> 'team_leads' is not null and (v_cfg ->> 'team_leads')::numeric >= 0 then
      v_leads := (v_cfg ->> 'team_leads')::numeric;
      v_leads_source := 'configured';
    else
      select
        (select count(*) from profiles p
          where p.deleted_at is null and p.is_active
            and exists (select 1 from staff_roles r
                         where r.profile_id = p.id and r.role = 'team_lead'))
        + (select count(*) from contractor_workers w
            join contractors c on c.id = w.contractor_id
           where w.deleted_at is null and w.is_active
             and c.deleted_at is null and c.is_active
             and exists (select 1 from contractor_worker_roles r
                          where r.contractor_worker_id = w.id and r.role = 'team_lead'))
        into v_leads;
    end if;
  end if;

  return jsonb_build_object(
    'workers', coalesce(v_workers, 0),
    'trucks', coalesce(v_trucks, 0),
    'team_leads', coalesce(v_leads, 0),
    'source', jsonb_build_object(
      'workers', v_workers_source,
      'trucks', v_trucks_source,
      'team_leads', v_leads_source
    ),
    'scope', coalesce(p_scope, 'all'),
    'contractor_id', p_contractor_id
  );
end $$;

grant execute on function app.load_capacity(text, uuid) to authenticated;

-- ===== 2. המשימות שעל הציר מסוננות לפי Scope ================================

create or replace function app.load_tasks(
  p_from date, 
  p_to date,
  p_scope text default 'all',
  p_contractor_id uuid default null
)
returns table (
  task_id       uuid,
  task_date     date,
  win           tstzrange,
  worker_need   int,
  staffed       int,
  needs_lead    boolean,
  truck_ids     uuid[],
  customer_id   uuid,
  site          text,
  warehouse     uuid,
  delegated     boolean,
  contractor_id uuid
)
language sql stable security invoker set search_path = public as $$
  select
    t.id,
    t.task_date,
    tstzrange(
      case when t.warehouse_start_time is not null
           then app.warehouse_start_at(t.task_date, t.warehouse_start_time,
                                       t.onsite_start_time)
           else ((t.task_date + t.onsite_start_time) at time zone 'Asia/Jerusalem') end,
      ((t.task_date + coalesce(t.onsite_start_time, t.warehouse_start_time))
        at time zone 'Asia/Jerusalem')
        + make_interval(mins => round(coalesce(t.hours_count, 0) * 60)::int),
      '[)'),
    t.worker_count,
    (select count(distinct a.profile_id) from task_assignments a where a.task_id = t.id)
    + (select count(*) from task_contractor_workers w where w.task_id = t.id)
    + (select count(*) from task_customer_workers o where o.task_id = t.id),
    coalesce(t.requires_team_lead, false),
    t.truck_ids,
    t.customer_id,
    nullif(btrim(coalesce(t.location_text, e.location_text, '')), ''),
    coalesce(t.warehouse_id, c.warehouse_id),
    t.contractor_id is not null,
    t.contractor_id
  from tasks t
  left join events e     on e.id = t.event_id
  left join statuses es  on es.id = e.status_id
  left join customers c  on c.id = t.customer_id
  where t.deleted_at is null
    and coalesce(es.code, '') <> 'cancelled'
    and (t.task_date between p_from - 1 and p_to
         or (t.task_date = p_to + 1
             and t.warehouse_start_time is not null
             and t.onsite_start_time is not null
             and t.warehouse_start_time > t.onsite_start_time))
    and coalesce(t.onsite_start_time, t.warehouse_start_time) is not null
    and coalesce(t.hours_count, 0) > 0
    and (
      case 
        when p_scope = 'internal' then t.contractor_id is null
        when p_scope = 'contractor' then 
          case 
            when p_contractor_id is not null then t.contractor_id = p_contractor_id
            else t.contractor_id is not null
          end
        else true
      end
    )
$$;

grant execute on function app.load_tasks(date, date, text, uuid) to authenticated;

-- ===== 3. משבצות השעה =======================================================

create or replace function app.load_slots(
  p_from date, 
  p_to date,
  p_scope text default 'all',
  p_contractor_id uuid default null
)
returns table (
  slot_day   date,
  slot_hour  int,
  tasks      int,
  workers    int,
  staffed    int,
  trucks     int,
  leads      int,
  customers  int,
  sites      int,
  warehouses int,
  delegated  int
)
language sql stable security invoker set search_path = public as $$
  with lt as (select * from app.load_tasks(p_from, p_to, p_scope, p_contractor_id)),
  slots as (
    select (p_from + n) as slot_day, h as slot_hour,
           tstzrange((((p_from + n)::timestamp + make_interval(hours => h))
                       at time zone 'Asia/Jerusalem'),
                     (((p_from + n)::timestamp + make_interval(hours => h + 1))
                       at time zone 'Asia/Jerusalem'),
                     '[)') as win
      from generate_series(0, p_to - p_from) n
      cross join generate_series(0, 23) h
  )
  select
    s.slot_day,
    s.slot_hour,
    count(l.task_id)::int,
    coalesce(sum(l.worker_need), 0)::int,
    coalesce(sum(l.staffed), 0)::int,
    (select count(distinct u.tid)
       from lt l2, lateral unnest(l2.truck_ids) u(tid)
      where l2.win && s.win)::int,
    coalesce(sum(case when l.needs_lead then 1 else 0 end), 0)::int,
    count(distinct l.customer_id)::int,
    count(distinct l.site)::int,
    count(distinct l.warehouse)::int,
    coalesce(sum(case when l.delegated then 1 else 0 end), 0)::int
  from slots s
  left join lt l on l.win && s.win
  group by s.slot_day, s.slot_hour, s.win
$$;

grant execute on function app.load_slots(date, date, text, uuid) to authenticated;

-- ===== 4. המפה החודשית =====================================================

create or replace function load_heatmap(
  p_from date, 
  p_to date,
  p_scope text default 'all',
  p_contractor_id uuid default null
)
returns jsonb language plpgsql stable security invoker set search_path = public as $$
declare
  v_cap  jsonb;
  v_days jsonb;
begin
  if not app.has('reports.load') then
    raise exception 'אין הרשאה למפת העומסים' using errcode = '42501';
  end if;

  if p_from is null or p_to is null then
    raise exception 'חסר טווח תאריכים' using errcode = '22023'; end if;
  if p_to < p_from then
    raise exception 'טווח תאריכים הפוך' using errcode = '22023'; end if;
  if p_to - p_from > 400 then
    raise exception 'טווח גדול מדי' using errcode = '22023'; end if;

  if app.load_denied() then
    return jsonb_build_object('days', null, 'meta', jsonb_build_object('denied', true));
  end if;

  v_cap := app.load_capacity(p_scope, p_contractor_id);

  with s as (select * from app.load_slots(p_from, p_to, p_scope, p_contractor_id)),
  peaks as (
    select
      s.slot_day,
      max(s.tasks)      as peak_tasks,
      max(s.workers)    as peak_workers,
      max(s.trucks)     as peak_trucks,
      max(s.leads)      as peak_leads,
      max(s.sites)      as peak_sites,
      max(s.warehouses) as peak_warehouses,
      count(*) filter (where s.tasks > 0) as busy_hours
    from s group by s.slot_day
  ),
  peak_hour as (
    select distinct on (s.slot_day) s.slot_day, s.slot_hour
      from s
     where s.tasks > 0
     order by s.slot_day,
              greatest(
                case when (v_cap ->> 'workers')::numeric    > 0
                     then s.workers::numeric / (v_cap ->> 'workers')::numeric    else 0 end,
                case when (v_cap ->> 'trucks')::numeric     > 0
                     then s.trucks::numeric  / (v_cap ->> 'trucks')::numeric     else 0 end,
                case when (v_cap ->> 'team_leads')::numeric > 0
                     then s.leads::numeric   / (v_cap ->> 'team_leads')::numeric else 0 end) desc,
              s.workers desc, s.slot_hour
  ),
  totals as (
    select
      l.task_date as slot_day,
      count(*)::int                                   as tasks,
      coalesce(sum(l.worker_need), 0)::int            as worker_need,
      coalesce(sum(l.staffed), 0)::int                as staffed,
      coalesce(sum(greatest(l.worker_need - l.staffed, 0)), 0)::int as gap,
      coalesce(sum(extract(epoch from (upper(l.win) - lower(l.win))) / 3600.0
                   * l.worker_need), 0)::numeric      as worker_hours,
      count(*) filter (where l.delegated)::int        as delegated,
      count(distinct l.customer_id)::int              as customers,
      count(distinct l.site)::int                     as sites
    from app.load_tasks(p_from, p_to, p_scope, p_contractor_id) l
    group by l.task_date
  ),
  untimed as (
    select t.task_date, count(*)::int as untimed_tasks
      from tasks t
      left join events e    on e.id = t.event_id
      left join statuses es on es.id = e.status_id
     where t.deleted_at is null
       and coalesce(es.code, '') <> 'cancelled'
       and t.task_date between p_from and p_to
       and (coalesce(t.onsite_start_time, t.warehouse_start_time) is null
            or coalesce(t.hours_count, 0) = 0)
       and (
         case 
           when p_scope = 'internal' then t.contractor_id is null
           when p_scope = 'contractor' then 
             case 
               when p_contractor_id is not null then t.contractor_id = p_contractor_id
               else t.contractor_id is not null
             end
           else true
         end
       )
     group by t.task_date
  )
  select jsonb_agg(jsonb_build_object(
           'day',             (p_from + n),
           'tasks',           coalesce(tt.tasks, 0),
           'untimed',         coalesce(u.untimed_tasks, 0),
           'worker_need',     coalesce(tt.worker_need, 0),
           'staffed',         coalesce(tt.staffed, 0),
           'gap',             coalesce(tt.gap, 0),
           'worker_hours',    round(coalesce(tt.worker_hours, 0), 2),
           'delegated',       coalesce(tt.delegated, 0),
           'customers',       coalesce(tt.customers, 0),
           'sites',           coalesce(tt.sites, 0),
           'peak_hour',       ph.slot_hour,
           'peak_tasks',      coalesce(pk.peak_tasks, 0),
           'peak_workers',    coalesce(pk.peak_workers, 0),
           'peak_trucks',     coalesce(pk.peak_trucks, 0),
           'peak_leads',      coalesce(pk.peak_leads, 0),
           'peak_sites',      coalesce(pk.peak_sites, 0),
           'peak_warehouses', coalesce(pk.peak_warehouses, 0),
           'busy_hours',      coalesce(pk.busy_hours, 0))
         order by n)
    into v_days
    from generate_series(0, p_to - p_from) g(n)
    left join peaks     pk on pk.slot_day  = (p_from + n)
    left join peak_hour ph on ph.slot_day  = (p_from + n)
    left join totals    tt on tt.slot_day  = (p_from + n)
    left join untimed   u  on u.task_date  = (p_from + n);

  return jsonb_build_object(
    'days', coalesce(v_days, '[]'::jsonb),
    'meta', jsonb_build_object(
      'from', p_from, 
      'to', p_to, 
      'capacity', v_cap, 
      'scope', p_scope,
      'contractor_id', p_contractor_id,
      'denied', false));
end $$;

revoke execute on function load_heatmap(date, date, text, uuid) from anon, public;
grant  execute on function load_heatmap(date, date, text, uuid) to authenticated;

-- ===== 5. הפילוח השעתי של יום ==============================================

create or replace function load_day(
  p_date date,
  p_scope text default 'all',
  p_contractor_id uuid default null
)
returns jsonb language plpgsql stable security invoker set search_path = public as $$
declare
  v_cap   jsonb;
  v_hours jsonb;
  v_tasks jsonb;
begin
  if not app.has('reports.load') then
    raise exception 'אין הרשאה למפת העומסים' using errcode = '42501';
  end if;
  if p_date is null then
    raise exception 'חסר תאריך' using errcode = '22023'; end if;

  if app.load_denied() then
    return jsonb_build_object('hours', null, 'tasks', null,
                              'meta', jsonb_build_object('denied', true));
  end if;

  v_cap := app.load_capacity(p_scope, p_contractor_id);

  select jsonb_agg(jsonb_build_object(
           'hour',       s.slot_hour,
           'tasks',      s.tasks,
           'workers',    s.workers,
           'staffed',    s.staffed,
           'gap',        greatest(s.workers - s.staffed, 0),
           'trucks',     s.trucks,
           'leads',      s.leads,
           'customers',  s.customers,
           'sites',      s.sites,
           'warehouses', s.warehouses,
           'delegated',  s.delegated)
         order by s.slot_hour)
    into v_hours
    from app.load_slots(p_date, p_date, p_scope, p_contractor_id) s;

  select jsonb_agg(jsonb_build_object(
           'task_id',     v.id,
           'task_date',   v.task_date,
           'label',       coalesce(nullif(v.title, ''), v.end_client_name,
                                   v.customer_name, v.task_type_name),
           'task_type',   v.task_type_name,
           'customer',    v.customer_name,
           'color',       v.customer_color,
           'start',       lower(l.win),
           'end',         upper(l.win),
           'worker_need', l.worker_need,
           'staffed',     l.staffed,
           'needs_lead',  l.needs_lead,
           'trucks',      coalesce(cardinality(l.truck_ids), 0),
           'truck_names', v.truck_list,
           'site',        l.site,
           'delegated',   l.delegated,
           'contractor_id', l.contractor_id,
           'status_name', v.status_name,
           'status_color', v.status_color)
         order by lower(l.win), v.id)
    into v_tasks
    from app.load_tasks(p_date, p_date, p_scope, p_contractor_id) l
    join work_board_view v on v.id = l.task_id
   where l.win && tstzrange((p_date::timestamp       at time zone 'Asia/Jerusalem'),
                            ((p_date + 1)::timestamp at time zone 'Asia/Jerusalem'), '[)');

  return jsonb_build_object(
    'hours', coalesce(v_hours, '[]'::jsonb),
    'tasks', coalesce(v_tasks, '[]'::jsonb),
    'meta',  jsonb_build_object(
      'date', p_date, 
      'capacity', v_cap, 
      'scope', p_scope,
      'contractor_id', p_contractor_id,
      'denied', false));
end $$;

revoke execute on function load_day(date, text, uuid) from anon, public;
grant  execute on function load_day(date, text, uuid) to authenticated;
