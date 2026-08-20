-- 0096e: דוחות הכסף לא סופרים פעמיים כשלמשימה כמה קבלנים
--
-- כל `tasks left join task_contractor_terms` שמחזיר שורה למשימה התפצל והכפיל
-- הכנסה/שכר. כאן הצירוף מוחלף בתת-שאילתת סכום (עלות קבלן = סכום כל שורותיו),
-- כך שהמשימה נשארת שורה אחת. `margin_summary` כבר סכם נכון (terms→tasks).

-- ===== פורטל הקבלן: רק המשימות שלו, ורק המחיר שלו =========================
create or replace function contractor_dashboard(p_from date default null, p_to date default null)
returns jsonb language sql stable security invoker set search_path = public as $$
  with my_tasks as (
    select t.*, tct.price, tct.paid_at, tct.paid_amount, s.is_terminal
    from tasks t
    join statuses s on s.id = t.status_id
    join task_contractor_terms tct on tct.task_id = t.id and tct.contractor_id = app.contractor_id()
    where t.deleted_at is null
      and (p_from is null or t.task_date >= p_from)
      and (p_to is null or t.task_date <= p_to)
  )
  select jsonb_build_object(
    'tasks_count', (select count(*) from my_tasks),
    'expected_total', case when app.has('portal.view_financials')
      then (select coalesce(sum(price), 0) from my_tasks) else null end,
    'paid_total', case when app.has('portal.view_financials')
      then (select coalesce(sum(coalesce(paid_amount, price)), 0) from my_tasks where paid_at is not null) else null end,
    'unpaid_total', case when app.has('portal.view_financials')
      then (select coalesce(sum(price), 0) from my_tasks where paid_at is null) else null end,
    'completed_count', (select count(*) from my_tasks where is_terminal),
    'upcoming_count', (select count(*) from my_tasks where task_date >= current_date and not is_terminal))
$$;

-- ===== רווחיות פר-משימה: עלות הקבלן = סכום כל הקבלנים =====================
create or replace function app.task_pnl_rows(
  p_from        date,
  p_to          date,
  p_task_id     uuid default null,
  p_customer_id uuid default null,
  p_limit       int  default 200)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_pct  numeric;
  v_lim  int := greatest(1, least(coalesce(p_limit, 200), 500));
  v_out  jsonb;
begin
  perform app.margin_require();

  if not app.has('dashboard.all_workers') then
    raise exception 'רווחיות פר-משימה חושפת שכר ברמת עובד' using errcode = '42501';
  end if;
  if not (app.is_admin() or app.user_kind() = 'staff') then
    raise exception 'רווחיות פר-משימה זמינה לצוות בלבד' using errcode = '42501';
  end if;

  v_pct := coalesce((select (value ->> 'pct')::numeric
                       from app_settings where key = 'finance.employer_cost'), 0);

  with alloc as (
    select * from app.payroll_task_amounts(p_from, p_to) where bucket = 'task'
  ),
  base as (
    select
      t.id                                              as task_id,
      t.task_date,
      coalesce(nullif(t.title, ''), tt.name)            as title,
      tt.name                                           as task_type_name,
      tt.code                                           as task_type_code,
      st.name                                           as status_name,
      st.color                                          as status_color,
      t.event_id, e.event_number, e.end_client_name,
      t.customer_id,
      case when app.has('customers.view')   then c.name  end as customer_name,
      case when app.has('customers.view')   then c.color end as customer_color,
      case when app.has('contractors.view') then ct.name end as contractor_name,
      coalesce(tp.price, 0)                             as revenue,
      coalesce(tp.is_manual, false)                     as price_is_manual,
      (tp.task_id is null)                              as unpriced,
      coalesce(tct.price, 0)                            as contractor_cost,
      coalesce(a.amount, 0)                             as payroll,
      coalesce(a.shifts, 0)                             as shifts,
      coalesce(a.unrated_shifts, 0)                     as unrated_shifts,
      coalesce(a.actual_hours, 0)                       as actual_hours,
      coalesce(a.workers, 0)                            as actual_workers,
      (a.task_id is null)                               as no_attendance,
      t.worker_count                                    as planned_workers,
      t.hours_count                                     as planned_hours,
      coalesce(t.worker_count, 0) * coalesce(t.hours_count, 0) as planned_worker_hours
    from tasks t
    left join task_types            tt  on tt.id  = t.task_type_id
    left join statuses              st  on st.id  = t.status_id
    left join events                e   on e.id   = t.event_id
    left join customers             c   on c.id   = t.customer_id
    left join contractors           ct  on ct.id  = t.contractor_id
    left join task_pricing          tp  on tp.task_id = t.id
    -- ‏0096: סכום כל הקבלנים במשימה, שורה אחת — במקום צירוף שמתפצל.
    left join lateral (select sum(price) as price
                         from task_contractor_terms where task_id = t.id) tct on true
    left join alloc                 a   on a.task_id  = t.id
    where t.deleted_at is null
      and t.task_date between p_from and p_to
      and (p_task_id     is null or t.id          = p_task_id)
      and (p_customer_id is null or t.customer_id = p_customer_id)
  ),
  fin as (
    select b.*,
           round(b.payroll * (1 + v_pct / 100), 2) as payroll_with_employer,
           round(b.contractor_cost + b.payroll * (1 + v_pct / 100), 2) as cost_total,
           round(b.revenue - (b.contractor_cost + b.payroll * (1 + v_pct / 100)), 2) as gross,
           case when b.revenue > 0
                then round((b.revenue - (b.contractor_cost + b.payroll * (1 + v_pct / 100)))
                           / b.revenue * 100, 1) end as pct,
           round(b.actual_hours - b.planned_worker_hours, 2) as hours_delta
      from base b
  )
  select jsonb_build_object(
    'rows', (select coalesce(jsonb_agg(jsonb_build_object(
               'task_id',              r.task_id,
               'task_date',            r.task_date,
               'title',                r.title,
               'task_type_name',       r.task_type_name,
               'task_type_code',       r.task_type_code,
               'status_name',          r.status_name,
               'status_color',         r.status_color,
               'event_id',             r.event_id,
               'event_number',         r.event_number,
               'end_client_name',      r.end_client_name,
               'customer_id',          r.customer_id,
               'customer_name',        r.customer_name,
               'customer_color',       r.customer_color,
               'contractor_name',      r.contractor_name,
               'revenue',              r.revenue,
               'price_is_manual',      r.price_is_manual,
               'unpriced',             r.unpriced,
               'contractor_cost',      r.contractor_cost,
               'payroll',              round(r.payroll, 2),
               'payroll_with_employer', r.payroll_with_employer,
               'cost_total',           r.cost_total,
               'gross',                r.gross,
               'pct',                  r.pct,
               'planned_workers',      r.planned_workers,
               'planned_hours',        r.planned_hours,
               'planned_worker_hours', r.planned_worker_hours,
               'actual_workers',       r.actual_workers,
               'actual_hours',         r.actual_hours,
               'hours_delta',          r.hours_delta,
               'shifts',               r.shifts,
               'unrated_shifts',       r.unrated_shifts,
               'no_attendance',        r.no_attendance)
               order by r.gross asc, r.revenue desc), '[]')
              from (select * from fin
                     order by gross asc, revenue desc
                     limit v_lim) r),
    'summary', (select jsonb_build_object(
               'tasks',                count(*),
               'revenue',              round(coalesce(sum(f.revenue), 0), 2),
               'contractor',           round(coalesce(sum(f.contractor_cost), 0), 2),
               'payroll',              round(coalesce(sum(f.payroll), 0), 2),
               'payroll_with_employer', round(coalesce(sum(f.payroll_with_employer), 0), 2),
               'employer_pct',         v_pct,
               'cost_total',           round(coalesce(sum(f.cost_total), 0), 2),
               'gross',                round(coalesce(sum(f.gross), 0), 2),
               'pct', case when coalesce(sum(f.revenue), 0) > 0
                           then round(coalesce(sum(f.gross), 0)
                                      / sum(f.revenue) * 100, 1) end,
               'planned_worker_hours', round(coalesce(sum(f.planned_worker_hours), 0), 2),
               'actual_hours',         round(coalesce(sum(f.actual_hours), 0), 2))
              from fin f),
    'counters', (select jsonb_build_object(
               'tasks',               count(*),
               'unrated_shifts',      coalesce(sum(f.unrated_shifts), 0),
               'tasks_no_attendance', count(*) filter (where f.no_attendance),
               'unpriced_tasks',      count(*) filter (where f.unpriced))
              from fin f))
    into v_out;

  return v_out;
end $$;

revoke execute on function app.task_pnl_rows(date, date, uuid, uuid, int)
  from anon, authenticated, public;

-- ===== מגמת רווח: עלות הקבלן בתת-שאילתה, בלי פיצול =======================
create or replace function app.margin_trend(p_from date, p_to date, p_bucket text default 'week')
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v jsonb; v_b text := case when p_bucket in ('day','week','month','quarter')
                                  then p_bucket else 'week' end;
begin
  perform app.margin_require();
  select coalesce(jsonb_agg(row_to_json(x) order by x.bucket), '[]') into v from (
    select coalesce(b.bucket, p.bucket) as bucket,
           round(coalesce(b.revenue, 0), 2)    as revenue,
           round(coalesce(b.contractor, 0), 2) as contractor,
           round(coalesce(p.total, 0), 2)      as payroll,
           round(coalesce(b.revenue, 0) - coalesce(b.contractor, 0) - coalesce(p.total, 0), 2) as gross
      from (
        select bucket, sum(revenue) as revenue, sum(contractor) as contractor from (
          select date_trunc(v_b, t.task_date)::date as bucket,
                 sum(coalesce(tp.price, 0)) as revenue,
                 sum(coalesce((select sum(x.price) from task_contractor_terms x
                                where x.task_id = t.id), 0)) as contractor
            from tasks t
            left join task_pricing tp on tp.task_id = t.id
           where t.deleted_at is null and t.task_date between p_from and p_to
           group by 1
          union all
          select date_trunc(v_b, e.event_date)::date, sum(ei.amount), 0
            from event_income ei
            join events e on e.id = ei.event_id and e.deleted_at is null
           where e.event_date between p_from and p_to
           group by 1) u
         group by bucket) b
      full join (
        select (e ->> 'bucket')::date as bucket, (e ->> 'total')::numeric as total
          from jsonb_array_elements(app.payroll_trend(p_from, p_to, v_b)) e) p
        on p.bucket = b.bucket) x;
  return v;
end $$;

-- ===== רווח לפי לקוח: עלות הקבלן בתת-שאילתה, בלי פיצול ====================
create or replace function app.margin_by_customer(p_from date, p_to date, p_limit int default 12)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v jsonb; v_alloc jsonb;
begin
  perform app.margin_require();
  if not app.has('customers.view') then
    raise exception 'אין הרשאה ללקוחות' using errcode = '42501';
  end if;
  v_alloc := app.payroll_task_alloc(p_from, p_to);

  select jsonb_build_object(
    'rows', (select coalesce(jsonb_agg(row_to_json(x) order by x.revenue desc), '[]') from (
        select c.name, c.color,
               round(sum(u.revenue), 2)    as revenue,
               round(sum(u.contractor), 2) as contractor,
               round(coalesce((select (a ->> 'payroll')::numeric
                                 from jsonb_array_elements(v_alloc -> 'by_customer') a
                                where a ->> 'name' = c.name), 0), 2) as payroll
          from (
            select t.customer_id as cid,
                   coalesce(tp.price, 0) as revenue,
                   coalesce((select sum(x.price) from task_contractor_terms x
                              where x.task_id = t.id), 0) as contractor
              from tasks t
              left join task_pricing tp on tp.task_id = t.id
             where t.deleted_at is null and t.task_date between p_from and p_to
            union all
            select e.customer_id, ei.amount, 0
              from event_income ei
              join events e on e.id = ei.event_id and e.deleted_at is null
             where e.event_date between p_from and p_to) u
          join customers c on c.id = u.cid
         group by c.name, c.color
         limit greatest(1, least(coalesce(p_limit, 12), 50))) x),
    'unallocated', (v_alloc -> 'unallocated'),
    'allocated',   (v_alloc -> 'allocated'),
    'estimated', true)
    into v;
  return v;
end $$;
