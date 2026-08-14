-- 0069: הכנסות הקטגוריה נכנסות לדשבורד — סקשנים חדשים והרחבת הקיימים
--
-- 0068 הוסיפה את הנתונים; הקובץ הזה מלמד את שכבת הקריאה. שתי החלטות:
--
--   1. **"הכנסות" פירושו מעכשיו תמחור משימות + הכנסות קטגוריה, בכל מקום.**
--      כך ביקש הבעלים במפורש: מספר אחד של סך הכל, כמו במערכת הישנה. לכן כל
--      ענף שסכם task_pricing — revenue.trend, revenue.forecast,
--      customers.leaderboard, שלוש פונקציות ה-margin ו-dashboard_stats —
--      נכתב מחדש כאן עם איחוד של שני המקורות. ההכנסה מקטגוריה מיוחסת
--      ל-events.event_date, כפי שתמחור משימה מיוחס ל-tasks.task_date.
--   2. **הסקשנים החדשים יושבים באותו dispatcher** ולא ב-RPC נפרד — ווידג'ט
--      חדש הוא עוד מפתח בבקשה הקיימת, לא בקשה נוספת.
--
-- הרשאות: event_income נקרא כאן תחת RLS של הקורא (הפונקציה security invoker),
-- והמפתח finance.income_view נגזר מ-pricing.revenue — מי שראה הכנסות אתמול
-- רואה את אותו כרטיס גם היום, רק שלם יותר. מי שנשלל ממנו income_view במפורש
-- יראה את רכיב המשימות בלבד, כי ה-RLS מסננת את השורות עוד לפני הסכימה.

-- ===== 1. רווח גולמי — שלושת העוזרים לומדים על הכנסות קטגוריה ==============
-- גוף 0044 עם שינוי אחד: revenue = תמחור משימות + event_income. העלויות אינן
-- משתנות. security definer כמו קודם — app.margin_require() מגדר בפנים.

create or replace function app.margin_summary(p_from date, p_to date)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_rev numeric; v_con numeric; v_pay jsonb;
begin
  perform app.margin_require();
  v_pay := app.payroll_summary(p_from, p_to);

  select coalesce((select sum(tp.price)
                     from task_pricing tp
                     join tasks t on t.id = tp.task_id and t.deleted_at is null
                    where t.task_date between p_from and p_to), 0)
       + coalesce((select sum(ei.amount)
                     from event_income ei
                     join events e on e.id = ei.event_id and e.deleted_at is null
                    where e.event_date between p_from and p_to), 0)
    into v_rev;
  select coalesce(sum(tct.price), 0) into v_con
    from task_contractor_terms tct join tasks t on t.id = tct.task_id and t.deleted_at is null
   where t.task_date between p_from and p_to;

  return jsonb_build_object(
    'revenue',    round(v_rev, 2),
    'contractor', round(v_con, 2),
    'payroll',    (v_pay -> 'total'),
    'gross',      round(v_rev - v_con - coalesce((v_pay ->> 'total')::numeric, 0), 2),
    'pct',        case when v_rev > 0
                       then round((v_rev - v_con - coalesce((v_pay ->> 'total')::numeric, 0))
                                  / v_rev * 100, 1) end,
    'unrated_shifts', (v_pay -> 'unrated_shifts'),
    'excludes_overhead', true);
end $$;

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
                 sum(tp.price) as revenue, sum(tct.price) as contractor
            from tasks t
            left join task_pricing tp on tp.task_id = t.id
            left join task_contractor_terms tct on tct.task_id = t.id
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

create or replace function app.margin_by_customer(p_from date, p_to date, p_limit int default 12)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v jsonb; v_alloc jsonb;
begin
  perform app.margin_require();
  if not app.has('customers.view') then
    raise exception 'אין הרשאה ללקוחות' using errcode = '42501';
  end if;
  v_alloc := app.payroll_task_alloc(p_from, p_to);

  -- איחוד לפי לקוח ולא from tasks: לקוח שיש לו רק הכנסות קטגוריה בטווח (ואף
  -- משימה) עדיין שייך לטבלה.
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
                   coalesce(tp.price, 0) as revenue, coalesce(tct.price, 0) as contractor
              from tasks t
              left join task_pricing tp on tp.task_id = t.id
              left join task_contractor_terms tct on tct.task_id = t.id
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

-- create or replace משמר את ה-ACL הקיים (revoke/grant מ-0044) — אין מה לחזור עליו.

-- ===== 2. dashboard_stats — ההכנסה שהמסך הראשי מציג ========================
-- גוף 0063 מילה במילה, למעט revenue: total ו-by_customer סוכמים גם event_income.

create or replace function dashboard_stats(p_from date, p_to date)
returns jsonb language sql stable security invoker set search_path = public as $$
  select jsonb_build_object(
    'events_count', (select count(*) from events
       where deleted_at is null and event_date between p_from and p_to),
    'events_upcoming', (select count(*) from events e
       left join statuses s on s.id = e.status_id
       where e.deleted_at is null and e.event_date >= current_date
         and not coalesce(s.is_terminal, false)),
    'events_done', (select count(*) from events e
       join statuses s on s.id = e.status_id
       where e.deleted_at is null and s.is_terminal
         and e.event_date between p_from and p_to),
    'tasks_count', (select count(*) from tasks
       where deleted_at is null and task_date between p_from and p_to),
    'tasks_open', (select count(*) from tasks t join statuses s on s.id = t.status_id
       where t.deleted_at is null and s.code is distinct from 'assigned'
         and t.task_date between p_from and p_to),
    'tasks_today', (select count(*) from tasks
       where deleted_at is null and task_date = current_date),
    'tasks_week', (select count(*) from tasks
       where deleted_at is null
         and task_date between date_trunc('week', current_date)::date
         and (date_trunc('week', current_date) + interval '6 days')::date),
    'tasks_overdue', (select count(*) from tasks t join statuses s on s.id = t.status_id
       where t.deleted_at is null and t.task_date < current_date
         and s.code is distinct from 'assigned'),
    'available_workers', case when app.has('dashboard.all_workers') then
      (select count(*) from profiles p
         where p.deleted_at is null and p.is_active and p.user_kind = 'staff'
           and not exists (select 1 from task_assignments a join tasks t on t.id = a.task_id
                           where a.profile_id = p.id and t.task_date = current_date
                             and t.deleted_at is null))
      else null end,
    'by_customer', case when app.has('customers.view') then
      (select coalesce(jsonb_agg(row_to_json(x)), '[]') from (
         select c.name, c.color, count(*) as cnt from tasks t join customers c on c.id = t.customer_id
         where t.deleted_at is null and t.task_date between p_from and p_to
         group by c.name, c.color order by cnt desc limit 12) x)
      else null end,
    'by_contractor', case when app.has('dashboard.contractors') then
      (select coalesce(jsonb_agg(row_to_json(x)), '[]') from (
         select ct.name, count(*) as cnt from tasks t join contractors ct on ct.id = t.contractor_id
         where t.deleted_at is null and t.task_date between p_from and p_to
         group by ct.name order by cnt desc limit 12) x)
      else null end,
    'by_worker', case when app.has('dashboard.all_workers') then
      (select coalesce(jsonb_agg(row_to_json(x)), '[]') from (
         select p.full_name as name, count(*) as cnt
         from task_assignments a
         join tasks t on t.id = a.task_id and t.deleted_at is null
           and t.task_date between p_from and p_to
         join profiles p on p.id = a.profile_id
         group by p.full_name order by cnt desc limit 12) x)
      else null end,
    'financial', case when app.has('dashboard.financial') then
      (select jsonb_build_object(
         'expected', coalesce(sum(tct.price), 0),
         'paid', coalesce(sum(tct.paid_amount) filter (where tct.paid_at is not null), 0))
       from task_contractor_terms tct
       join tasks t on t.id = tct.task_id and t.deleted_at is null
        and t.task_date between p_from and p_to)
      else null end,
    'revenue', case when app.has('pricing.revenue') then
      (select jsonb_build_object(
         'total', coalesce(sum(tp.price), 0)
                  + coalesce((select sum(ei.amount)
                                from event_income ei
                                join events e on e.id = ei.event_id and e.deleted_at is null
                               where e.event_date between p_from and p_to), 0),
         'priced_tasks', count(*) filter (where tp.price is not null),
         'by_customer', case when app.has('customers.view') then
           (select coalesce(jsonb_agg(row_to_json(y) order by y.total desc), '[]') from (
              select u.name, u.color, round(sum(u.total), 2) as total from (
                select c.name, c.color, coalesce(sum(tp2.price), 0) as total
                from task_pricing tp2
                join tasks t2 on t2.id = tp2.task_id and t2.deleted_at is null
                 and t2.task_date between p_from and p_to
                join customers c on c.id = t2.customer_id
                group by c.name, c.color
                union all
                select c.name, c.color, coalesce(sum(ei2.amount), 0)
                from event_income ei2
                join events e2 on e2.id = ei2.event_id and e2.deleted_at is null
                 and e2.event_date between p_from and p_to
                join customers c on c.id = e2.customer_id
                group by c.name, c.color) u
              group by u.name, u.color order by 3 desc limit 12) y)
           else null end)
       from task_pricing tp
       join tasks t on t.id = tp.task_id and t.deleted_at is null
        and t.task_date between p_from and p_to)
      else null end,
    'by_status', (select coalesce(jsonb_agg(row_to_json(x)), '[]') from (
       select s.name, s.color, count(*) as cnt from tasks t join statuses s on s.id = t.status_id
       where t.deleted_at is null and t.task_date between p_from and p_to
       group by s.name, s.color order by cnt desc) x),
    'next_events', (select coalesce(jsonb_agg(row_to_json(x)), '[]') from (
       select e.id, e.event_date, e.end_client_name, e.event_number, e.location_text
       from events e
       where e.deleted_at is null and e.event_date >= current_date
       order by e.event_date limit 5) x))
$$;

-- ===== 3. dashboard_sections — גוף 0044 + ההרחבות + שישה סקשנים חדשים ======

create or replace function dashboard_sections(
  p_sections text[], p_from date, p_to date, p_opts jsonb default '{}'::jsonb)
returns jsonb language plpgsql stable security invoker set search_path = public as $$
declare
  v_key    text;
  v_out    jsonb := '{}'::jsonb;
  v_bucket text := case when p_opts ->> 'bucket' in ('day','week','month')
                        then p_opts ->> 'bucket' else 'week' end;
  v_limit  int  := greatest(1, least(coalesce((p_opts ->> 'limit')::int, 12), 50));
  v_val    jsonb;
  v_m      jsonb;
  v_pct    numeric;
  v_margin boolean := app.has_all(array['dashboard.margin','dashboard.payroll',
                                        'dashboard.contractor_cost','pricing.revenue']);
  v_scoped boolean := exists (select 1 from app.scope_rows('tasks') where scope_type <> 'all');
begin
  if p_from is null or p_to is null then
    raise exception 'חסר טווח תאריכים' using errcode = '22023';
  end if;
  if p_to < p_from then
    raise exception 'טווח תאריכים הפוך' using errcode = '22023';
  end if;
  if p_to - p_from > 400 then
    raise exception 'טווח גדול מדי לדשבורד' using errcode = '22023';
  end if;
  -- 48 ולא 40: ששת מפתחות ההכנסה החדשים הצטרפו לפריסת ברירת המחדל.
  if coalesce(array_length(p_sections, 1), 0) > 48 then
    raise exception 'יותר מדי סקשנים בבקשה אחת' using errcode = '22023';
  end if;

  foreach v_key in array coalesce(p_sections, '{}'::text[]) loop
    v_val := null;

    if v_key = 'revenue.trend' and app.has('pricing.revenue') then
      select coalesce(jsonb_agg(row_to_json(x) order by x.bucket), '[]') into v_val from (
        select u.bucket, round(sum(u.total), 2) as total from (
          select date_trunc(v_bucket, t.task_date)::date as bucket, sum(tp.price) as total
            from task_pricing tp
            join tasks t on t.id = tp.task_id and t.deleted_at is null
           where t.task_date between p_from and p_to
           group by 1
          union all
          select date_trunc(v_bucket, e.event_date)::date, sum(ei.amount)
            from event_income ei
            join events e on e.id = ei.event_id and e.deleted_at is null
           where e.event_date between p_from and p_to
           group by 1) u
         group by u.bucket) x;

    elsif v_key = 'revenue.forecast' and app.has('pricing.revenue') then
      select jsonb_build_object(
        'total', round(coalesce(sum(tp.price), 0)
                       + coalesce((select sum(ei.amount)
                                     from event_income ei
                                     join events e on e.id = ei.event_id and e.deleted_at is null
                                    where e.event_date > current_date), 0), 2),
        'tasks', count(*),
        'by_month', (select coalesce(jsonb_agg(row_to_json(y) order by y.bucket), '[]') from (
            select u.bucket, round(sum(u.total), 2) as total from (
              select date_trunc('month', t2.task_date)::date as bucket, sum(tp2.price) as total
                from task_pricing tp2
                join tasks t2 on t2.id = tp2.task_id and t2.deleted_at is null
               where t2.task_date > current_date
               group by 1
              union all
              select date_trunc('month', e2.event_date)::date, sum(ei2.amount)
                from event_income ei2
                join events e2 on e2.id = ei2.event_id and e2.deleted_at is null
               where e2.event_date > current_date
               group by 1) u
             group by u.bucket) y))
        into v_val
        from task_pricing tp
        join tasks t on t.id = tp.task_id and t.deleted_at is null
       where t.task_date > current_date;

    elsif v_key = 'pricing.quality' and app.has('pricing.view') then
      select jsonb_build_object(
        'total',    count(*),
        'unpriced', count(*) filter (where tp.task_id is null or tp.price = 0),
        'manual',   count(*) filter (where tp.is_manual),
        'auto',     count(*) filter (where tp.task_id is not null and not tp.is_manual and tp.price > 0),
        'unpriced_list', (select coalesce(jsonb_agg(row_to_json(y)), '[]') from (
            select t2.id, t2.task_date, coalesce(c2.name, t2.title, tt2.name) as label
              from tasks t2
              left join task_pricing tp2 on tp2.task_id = t2.id
              left join customers c2 on c2.id = t2.customer_id
              left join task_types tt2 on tt2.id = t2.task_type_id
             where t2.deleted_at is null and t2.task_date between p_from and p_to
               and (tp2.task_id is null or tp2.price = 0)
             order by t2.task_date desc limit 8) y))
        into v_val
        from tasks t
        left join task_pricing tp on tp.task_id = t.id
       where t.deleted_at is null and t.task_date between p_from and p_to;

    elsif v_key = 'cost.contractor' and app.has('dashboard.contractor_cost') then
      select jsonb_build_object(
        'expected',   round(coalesce(sum(tct.price), 0), 2),
        'paid',       round(coalesce(sum(coalesce(tct.paid_amount, tct.price))
                              filter (where tct.paid_at is not null), 0), 2),
        'unpaid',     round(coalesce(sum(tct.price) filter (where tct.paid_at is null), 0), 2),
        'unpaid_rows', count(*) filter (where tct.paid_at is null),
        'zero_rows',   count(*) filter (where tct.price = 0),
        'rows',        count(*),
        'aging', jsonb_build_object(
          'd0_30',  round(coalesce(sum(tct.price) filter (
                      where tct.paid_at is null and t.task_date > current_date - 30), 0), 2),
          'd31_60', round(coalesce(sum(tct.price) filter (
                      where tct.paid_at is null and t.task_date between current_date - 60 and current_date - 30), 0), 2),
          'd60',    round(coalesce(sum(tct.price) filter (
                      where tct.paid_at is null and t.task_date < current_date - 60), 0), 2)))
        into v_val
        from task_contractor_terms tct
        join tasks t on t.id = tct.task_id and t.deleted_at is null
       where t.task_date between p_from and p_to;

    elsif v_key = 'cost.by_contractor' and app.has('dashboard.contractor_cost') and app.has('contractors.view') then
      select coalesce(jsonb_agg(row_to_json(x)), '[]') into v_val from (
        select ct.name,
               round(sum(tct.price), 2) as expected,
               round(sum(coalesce(tct.paid_amount, tct.price)) filter (where tct.paid_at is not null), 2) as paid
          from task_contractor_terms tct
          join tasks t on t.id = tct.task_id and t.deleted_at is null
          join contractors ct on ct.id = tct.contractor_id
         where t.task_date between p_from and p_to
         group by ct.name order by 2 desc limit v_limit) x;

    elsif v_key = 'cost.contractor_unpaid' and app.has('dashboard.contractor_cost')
          and app.has('contractors.view_pricing') then
      select coalesce(jsonb_agg(row_to_json(x)), '[]') into v_val from (
        select t.id as task_id, t.task_date, ct.name as contractor, tct.price
          from task_contractor_terms tct
          join tasks t on t.id = tct.task_id and t.deleted_at is null
          join contractors ct on ct.id = tct.contractor_id
         where tct.paid_at is null and tct.price > 0 and t.task_date between p_from and p_to
         order by t.task_date limit v_limit) x;

    elsif v_key = 'cost.payroll' and app.has('dashboard.payroll') then
      v_val := app.payroll_summary(p_from, p_to);

    elsif v_key = 'cost.payroll_by_worker' and app.has('dashboard.payroll')
          and app.has('dashboard.all_workers') then
      v_val := app.payroll_by_worker(p_from, p_to, v_limit);

    elsif v_key = 'cost.payroll_trend' and app.has('dashboard.payroll') then
      v_val := app.payroll_trend(p_from, p_to, v_bucket);

    -- ── עלות מעביד: שכר מאושר כפול האחוז הגלובלי ─────────────────────────
    elsif v_key = 'cost.payroll_employer' and app.has('dashboard.payroll') then
      v_m := app.payroll_summary(p_from, p_to);
      v_pct := coalesce((select (value ->> 'pct')::numeric
                           from app_settings where key = 'finance.employer_cost'), 0);
      v_val := jsonb_build_object(
        'base',  v_m -> 'total',
        'pct',   v_pct,
        'total', round(coalesce((v_m ->> 'total')::numeric, 0) * (1 + v_pct / 100), 2),
        'unrated_shifts', v_m -> 'unrated_shifts');

    -- ── רווח גולמי: מימוש אחד, שני קוראים ─────────────────────────────────
    elsif v_key = 'margin.summary' and v_margin and not v_scoped then
      v_val := app.margin_summary(p_from, p_to);

    elsif v_key = 'margin.trend' and v_margin and not v_scoped then
      v_val := app.margin_trend(p_from, p_to, v_bucket);

    elsif v_key = 'margin.by_customer' and v_margin and not v_scoped and app.has('customers.view') then
      v_val := app.margin_by_customer(p_from, p_to, v_limit);

    -- ── סיכום רווח במתכונת המערכת הישנה: הכנסות − שכר×מעביד − קבלנים ─────
    -- אותו שער כמו margin.*: רווח הוא חיסור, ומי שרואה אותו רואה את הרכיבים.
    elsif v_key = 'finance.profit_summary' and v_margin and not v_scoped then
      v_m := app.margin_summary(p_from, p_to);
      v_pct := coalesce((select (value ->> 'pct')::numeric
                           from app_settings where key = 'finance.employer_cost'), 0);
      v_val := jsonb_build_object(
        'revenue',      v_m -> 'revenue',
        'payroll',      v_m -> 'payroll',
        'employer_pct', v_pct,
        'payroll_with_employer',
          round(coalesce((v_m ->> 'payroll')::numeric, 0) * (1 + v_pct / 100), 2),
        'contractor',   v_m -> 'contractor',
        'profit',
          round(coalesce((v_m ->> 'revenue')::numeric, 0)
                - coalesce((v_m ->> 'payroll')::numeric, 0) * (1 + v_pct / 100)
                - coalesce((v_m ->> 'contractor')::numeric, 0), 2),
        'pct', case when coalesce((v_m ->> 'revenue')::numeric, 0) > 0
                    then round((coalesce((v_m ->> 'revenue')::numeric, 0)
                                - coalesce((v_m ->> 'payroll')::numeric, 0) * (1 + v_pct / 100)
                                - coalesce((v_m ->> 'contractor')::numeric, 0))
                               / (v_m ->> 'revenue')::numeric * 100, 1) end,
        'unrated_shifts', v_m -> 'unrated_shifts',
        'excludes_overhead', true);

    -- ── הכנסות לפי קטגוריה ────────────────────────────────────────────────
    -- קטגוריה כבויה/מחוקה עם סכומים בטווח עדיין נספרת — ההיסטוריה אינה
    -- נעלמת כשמכבים קטגוריה.
    elsif v_key = 'income.by_category' and app.has('finance.income_view') then
      with cat as (
        select ic.id, ic.name, ic.family, ic.color, ic.sort_order,
               round(coalesce(sum(ei.amount) filter (where e.id is not null), 0), 2) as total
          from income_categories ic
          left join event_income ei on ei.category_id = ic.id
          left join events e on e.id = ei.event_id and e.deleted_at is null
               and e.event_date between p_from and p_to
         group by ic.id, ic.name, ic.family, ic.color, ic.sort_order
        having (ic.deleted_at is null and ic.is_active)
            or coalesce(sum(ei.amount) filter (where e.id is not null), 0) <> 0)
      select jsonb_build_object(
        'rows', coalesce((select jsonb_agg(row_to_json(c) order by c.sort_order) from cat c), '[]'::jsonb),
        'furniture_total', round(coalesce((select sum(total) from cat where family = 'furniture'), 0), 2),
        'logistics_total', round(coalesce((select sum(total) from cat where family = 'logistics'), 0), 2),
        'total', round(coalesce((select sum(total) from cat), 0), 2))
        into v_val;

    -- ── פילוח הכנסות: קטגוריה × לקוח, ותמחור המשימות כ"צוות" ─────────────
    elsif v_key = 'income.mix' and app.has('finance.income_view') and app.has('customers.view') then
      select coalesce(jsonb_agg(row_to_json(x)), '[]') into v_val from (
        select u.label, u.color, round(sum(u.total), 2) as total from (
          select ic.name || ' ' || c.name as label, ic.color as color, sum(ei.amount) as total
            from event_income ei
            join events e on e.id = ei.event_id and e.deleted_at is null
                 and e.event_date between p_from and p_to
            join customers c on c.id = e.customer_id
            join income_categories ic on ic.id = ei.category_id
           group by ic.name, c.name, ic.color
          union all
          select 'צוות ' || c.name, c.color, sum(tp.price)
            from task_pricing tp
            join tasks t on t.id = tp.task_id and t.deleted_at is null
                 and t.task_date between p_from and p_to
            join customers c on c.id = t.customer_id
           group by c.name, c.color) u
         group by u.label, u.color
        having sum(u.total) <> 0
         order by 3 desc limit v_limit) x;

    -- ── תשלום לוויפר: מה שהלקוחות חייבים, מה ששולם, והיתרה ───────────────
    -- owed = כל ההכנסות בטווח (ויפר גובה הכול ומעביר ללקוח את חלקו אחר כך);
    -- paid = תקבולים שנרשמו בטווח. שני השערים יחד: יתרה שנגזרת מחוב חלקי
    -- היא מספר שגוי, לא מספר חסר — התקדים של margin.
    elsif v_key = 'finance.receivables' and app.has('finance.receipts_view')
          and app.has('finance.income_view') then
      with rev as (
        select u.cid, sum(u.amount) as owed from (
          select e.customer_id as cid, ei.amount
            from event_income ei
            join events e on e.id = ei.event_id and e.deleted_at is null
           where e.event_date between p_from and p_to
          union all
          select t.customer_id, tp.price
            from task_pricing tp
            join tasks t on t.id = tp.task_id and t.deleted_at is null
           where t.task_date between p_from and p_to) u
         group by u.cid),
      rec as (
        select r.customer_id as cid, sum(r.amount) as paid, count(*) as cnt
          from receipts r
         where r.deleted_at is null and r.received_at between p_from and p_to
         group by r.customer_id)
      select jsonb_build_object(
        'owed',   round(coalesce((select sum(owed) from rev), 0), 2),
        'paid',   round(coalesce((select sum(paid) from rec), 0), 2),
        'unpaid', round(coalesce((select sum(owed) from rev), 0)
                        - coalesce((select sum(paid) from rec), 0), 2),
        'receipts_count', coalesce((select sum(cnt) from rec), 0),
        'by_customer', case when app.has('customers.view') then
          (select coalesce(jsonb_agg(row_to_json(y)), '[]') from (
             select c.name, c.color,
                    round(coalesce(v.owed, 0), 2) as owed,
                    round(coalesce(p.paid, 0), 2) as paid,
                    round(coalesce(v.owed, 0) - coalesce(p.paid, 0), 2) as unpaid
               from customers c
               left join rev v on v.cid = c.id
               left join rec p on p.cid = c.id
              where c.deleted_at is null and (v.cid is not null or p.cid is not null)
              order by 3 desc limit v_limit) y)
          else null end)
        into v_val;

    -- ── הכנסות ללקוח: חלקו של הלקוח, לפי ה-snapshot שנשמר על כל אירוע ─────
    elsif v_key = 'finance.client_share' and app.has('finance.income_view') then
      select jsonb_build_object(
        'total', round(coalesce(sum(ei.amount * (100 - ei.viper_share_pct) / 100), 0), 2),
        'rows', case when app.has('customers.view') then
          (select coalesce(jsonb_agg(row_to_json(y)), '[]') from (
             select c.name, c.color,
                    round(sum(ei2.amount * (100 - ei2.viper_share_pct) / 100), 2) as total
               from event_income ei2
               join events e2 on e2.id = ei2.event_id and e2.deleted_at is null
                    and e2.event_date between p_from and p_to
               join customers c on c.id = e2.customer_id
              group by c.name, c.color
             having sum(ei2.amount * (100 - ei2.viper_share_pct) / 100) <> 0
              order by 3 desc limit v_limit) y)
          else null end)
        into v_val
        from event_income ei
        join events e on e.id = ei.event_id and e.deleted_at is null
       where e.event_date between p_from and p_to;

    elsif v_key = 'tasks.by_type' then
      select coalesce(jsonb_agg(row_to_json(x)), '[]') into v_val from (
        select tt.name, count(*) as cnt
          from tasks t join task_types tt on tt.id = t.task_type_id
         where t.deleted_at is null and t.task_date between p_from and p_to
         group by tt.name order by 2 desc limit v_limit) x;

    elsif v_key = 'tasks.by_method' then
      select coalesce(jsonb_agg(row_to_json(x)), '[]') into v_val from (
        select em.name, count(*) as cnt
          from tasks t join execution_methods em on em.id = t.execution_method_id
         where t.deleted_at is null and t.task_date between p_from and p_to
         group by em.name order by 2 desc limit v_limit) x;

    elsif v_key = 'tasks.trend' then
      select coalesce(jsonb_agg(row_to_json(x) order by x.bucket), '[]') into v_val from (
        select bucket, sum(tasks) as tasks, sum(events) as events from (
          select date_trunc(v_bucket, t.task_date)::date as bucket, count(*) as tasks, 0 as events
            from tasks t where t.deleted_at is null and t.task_date between p_from and p_to
           group by 1
          union all
          select date_trunc(v_bucket, e.event_date)::date, 0, count(*)
            from events e where e.deleted_at is null and e.event_date between p_from and p_to
           group by 1) u
         group by bucket) x;

    elsif v_key = 'tasks.understaffed'
          and (app.has('dashboard.all_workers') or app.has('tasks.assign.worker')) then
      select jsonb_build_object(
        'count', count(*),
        'rows', (select coalesce(jsonb_agg(row_to_json(y)), '[]') from (
            select t2.id, t2.task_date, coalesce(c2.name, t2.title) as label,
                   t2.worker_count as needed,
                   (select count(*) from task_assignments a2
                     where a2.task_id = t2.id and a2.role = 'worker') as assigned
              from tasks t2
              left join customers c2 on c2.id = t2.customer_id
              join statuses s2 on s2.id = t2.status_id
             where t2.deleted_at is null and t2.task_date between p_from and p_to
               and not s2.is_terminal and t2.worker_count > 0
               and (select count(*) from task_assignments a3
                     where a3.task_id = t2.id and a3.role = 'worker') < t2.worker_count
             order by t2.task_date limit 8) y))
        into v_val
        from tasks t
        join statuses s on s.id = t.status_id
       where t.deleted_at is null and t.task_date between p_from and p_to
         and not s.is_terminal and t.worker_count > 0
         and (select count(*) from task_assignments a
               where a.task_id = t.id and a.role = 'worker') < t.worker_count;

    elsif v_key = 'tasks.no_truck' then
      select jsonb_build_object('count', count(*)) into v_val
        from tasks t join statuses s on s.id = t.status_id
       where t.deleted_at is null and t.task_date between p_from and p_to
         and not s.is_terminal
         and coalesce(cardinality(t.truck_ids), 0) = 0 and t.truck_free_text is null;

    elsif v_key = 'fleet.utilization' then
      select coalesce(jsonb_agg(row_to_json(x)), '[]') into v_val from (
        select tr.name,
               count(distinct t.task_date) as days,
               count(*) as tasks
          from tasks t
          cross join lateral unnest(t.truck_ids) as u(truck_id)
          join trucks tr on tr.id = u.truck_id
         where t.deleted_at is null and t.task_date between p_from and p_to
         group by tr.name order by 2 desc limit v_limit) x;

    elsif v_key = 'events.by_customer' and app.has('customers.view') then
      select coalesce(jsonb_agg(row_to_json(x)), '[]') into v_val from (
        select c.name, c.color, count(*) as cnt
          from events e join customers c on c.id = e.customer_id
         where e.deleted_at is null and e.event_date between p_from and p_to
         group by c.name, c.color order by 3 desc limit v_limit) x;

    elsif v_key = 'events.funnel' then
      select coalesce(jsonb_agg(row_to_json(x)), '[]') into v_val from (
        select s.name, s.color, count(*) as cnt
          from events e join statuses s on s.id = e.status_id
         where e.deleted_at is null and e.event_date between p_from and p_to
         group by s.name, s.color, s.sort_order order by s.sort_order) x;

    elsif v_key = 'events.volume' and app.has('customers.view') then
      select jsonb_build_object(
        'volume_m', round(coalesce(sum(e.volume_m), 0), 2),
        'trucks',   coalesce(sum(e.truck_count), 0),
        'events',   count(*),
        'by_customer', (select coalesce(jsonb_agg(row_to_json(y)), '[]') from (
            select c2.name, c2.color,
                   round(coalesce(sum(e2.volume_m), 0), 2) as volume_m,
                   coalesce(sum(e2.truck_count), 0) as trucks
              from events e2 join customers c2 on c2.id = e2.customer_id
             where e2.deleted_at is null and e2.event_date between p_from and p_to
             group by c2.name, c2.color order by 3 desc limit v_limit) y))
        into v_val
        from events e
       where e.deleted_at is null and e.event_date between p_from and p_to;

    elsif v_key = 'customers.leaderboard' and app.has('customers.view') then
      select coalesce(jsonb_agg(row_to_json(x) order by x.events desc), '[]') into v_val from (
        select c.name, c.color,
               count(distinct e.id) as events,
               count(distinct t.id) as tasks,
               case when app.has('pricing.revenue')
                    then round(coalesce(sum(distinct_price.price), 0)
                               + coalesce((select sum(ei.amount)
                                             from event_income ei
                                             join events e3 on e3.id = ei.event_id
                                              and e3.deleted_at is null
                                              and e3.event_date between p_from and p_to
                                            where e3.customer_id = c.id), 0), 2) end as revenue,
               max(e.event_date) as last_event
          from customers c
          left join events e on e.customer_id = c.id and e.deleted_at is null
               and e.event_date between p_from and p_to
          left join tasks t on t.customer_id = c.id and t.deleted_at is null
               and t.task_date between p_from and p_to
          left join lateral (
            select tp.price from task_pricing tp where tp.task_id = t.id) distinct_price on true
         where c.deleted_at is null
         group by c.id, c.name, c.color
        having count(distinct e.id) > 0 or count(distinct t.id) > 0
         limit v_limit) x;

    elsif v_key = 'customers.inactive' and app.has('customers.view') then
      select coalesce(jsonb_agg(row_to_json(x)), '[]') into v_val from (
        select c.name, c.color,
               (select max(e2.event_date) from events e2
                 where e2.customer_id = c.id and e2.deleted_at is null) as last_event
          from customers c
         where c.deleted_at is null and c.is_active
           and not exists (select 1 from events e where e.customer_id = c.id
                             and e.deleted_at is null and e.event_date between p_from and p_to)
         order by 3 desc nulls last limit v_limit) x;

    elsif v_key = 'attendance.hours' and app.has('attendance.view_all') then
      select jsonb_build_object(
        'actual_hours', round(coalesce(sum(e.actual_hours), 0), 2),
        'shifts',       count(*),
        'workers',      count(distinct e.profile_id))
        into v_val
        from attendance_entries e
       where e.deleted_at is null and e.status = 'approved'
         and e.work_date between p_from and p_to;

    elsif v_key = 'attendance.hours_by_worker' and app.has('attendance.view_all') then
      select coalesce(jsonb_agg(row_to_json(x)), '[]') into v_val from (
        select p.full_name as name, round(sum(e.actual_hours), 2) as hours
          from attendance_entries e join profiles p on p.id = e.profile_id
         where e.deleted_at is null and e.status = 'approved'
           and e.work_date between p_from and p_to
         group by p.full_name order by 2 desc nulls last limit v_limit) x;

    elsif v_key = 'attendance.pending' and app.has('attendance.approve_entry') then
      select jsonb_build_object(
        'count', count(*),
        'hours', round(coalesce(sum(e.actual_hours), 0), 2),
        'rows', (select coalesce(jsonb_agg(row_to_json(y)), '[]') from (
            select e2.id, e2.work_date, p2.full_name, e2.actual_hours
              from attendance_entries e2 join profiles p2 on p2.id = e2.profile_id
             where e2.deleted_at is null and e2.status = 'pending'
             order by e2.work_date limit 8) y))
        into v_val
        from attendance_entries e
       where e.deleted_at is null and e.status = 'pending';

    elsif v_key = 'attendance.flags' and app.has('attendance.view_all') then
      select coalesce(jsonb_agg(row_to_json(x)), '[]') into v_val from (
        select f as flag, count(*) as cnt
          from attendance_entries e, unnest(e.flags) as f
         where e.deleted_at is null and e.work_date between p_from and p_to
         group by f order by 2 desc) x;

    elsif v_key = 'hr.headcount' and app.has('dashboard.all_workers') then
      select jsonb_build_object(
        'active', count(*) filter (where p.is_active),
        'staff',  count(*) filter (where p.is_active and p.user_kind = 'staff'))
        into v_val
        from profiles p where p.deleted_at is null;

    end if;

    v_out := v_out || jsonb_build_object(v_key, v_val);
  end loop;

  return v_out;
end $$;

revoke execute on function public.dashboard_sections(text[], date, date, jsonb) from anon, public;

-- ===== 4. אינדקס ===========================================================
-- כל הסקשנים שלמעלה מסננים אירועים לפי טווח; event_income עצמו קטן, אבל
-- הצירוף event_income→events נשען על האינדקס הקיים events (event_date).
-- הכיוון ההפוך — "כל השורות של אירוע" — הוא ה-PK. אין אינדקס חדש נדרש.
