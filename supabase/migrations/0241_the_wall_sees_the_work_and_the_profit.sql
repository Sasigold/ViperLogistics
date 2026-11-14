-- 0241: מסך הקיר רואה את העבודה ואת הרווח
--
-- בקשת הבעלים (מסך הקיר של ViperGroup, נובמבר 2026): "בראש המסך ציר זמן יומי
-- עם המשימות לביצוע מויפר לוגיסטיקס — משימות המחסן (ליקוט והחזרה) ומשימות
-- השטח, עם הסטטוס ועם העובדים. מתחת: המשימות שלי (משימות ניהול), רווחים בדיוק
-- כמו בדשבורד — הכנסות, קבלנים, שכר עם ה-30% ומה נשאר למטה — וסטטוס נוכחות:
-- מי במשמרת, מי היה אמור להתחיל ולא התחיל, מי התחיל באיחור ומי סיים לאחרונה."
--
-- הפיד (0202/0203) כבר נושא את משימות השטח, את "במשמרת עכשיו" ואת מי שלא
-- החתים. הקובץ הזה מוסיף לו ארבעה דברים, כולם תוספות (`v` נשאר 1 — מסך הקיר
-- קורא בזוד לא-קשיח, וכל שדה חדש אופציונלי אצלו):
--
--   1. **`finance.profit`** — הווידג'ט "רווח" של הדשבורד (`finance.profit_summary`,
--      0213) מתחילת החודש עד היום. כדי שיהיה חישוב אחד ולא שניים (ROADMAP:
--      "שתי הגדרות רווח"), גוף הסקשן עובר מילה במילה ל-`app.profit_summary_core`
--      (בלי שער, נשללת מכולם), ועטיפה `app.profit_summary` שואלת את
--      `app.margin_require()` — אותם ארבעה מפתחות ואותו "היקף מלא" שהדשבורד
--      בודק לפני הסקשן (`v_margin and not v_scoped`). הדשבורד קורא לעטיפה, מסך
--      הקיר לליבה. השינוי היחיד בגוף: `app.margin_summary` → `app.margin_summary_core`
--      (העטיפה של 0202 קוראת לאותה ליבה אחרי אותו שער, כך שהמספר זהה).
--   2. **`warehouse_tasks`** — לו״ז המחסן (0196/0226), הכנה והחזרה, עם שלושת
--      הסימונים (אישור סופי, אירוע מוכן, נבדק). ‏`app.warehouse_rows` מתפצלת
--      לליבה בלי השער של המשתמש (`app.warehouse_rows_core` — הדגל
--      `warehouse_schedule_enabled` נשאר בה) ולעטיפה עם השער, כמו 0202 §1: הכלל
--      של התאריכים נכתב פעם אחת. ללו״ז המחסן אין שיבוץ עובדים — אין שמות.
--   3. **`missions`** — משימות ניהול (0227): פתוחות, באיחור, להיום, בוצעו השבוע
--      (ומתוכן בזמן), 20 הפתוחות הקרובות עם התקדמות השלבים, ו-8 שבוצעו בשבוע
--      האחרון. "באיחור" ו"להיום" — אותן הגדרות של סיכום הבוקר (0232).
--   4. **`attendance.late_started`, `attendance.ended_recently`** — מי שהחתים
--      כניסה ראשונה היום 5 דקות ומעלה אחרי תחילת המשמרת המתוכננת (המדידה של
--      0084), ומי שהחתים יציאה בארבע השעות האחרונות ואינו במשמרת פתוחה.
--
-- אין בפיד טלפון, אין שכר פר-אדם, ואין מזהה פנימי מלבד המזהה של השורה עצמה
-- (הבעלים של משימת ניהול — שם בלבד).

-- ===== 1. הרווח: ליבה אחת, עטיפה עם השער, והדשבורד קורא לעטיפה ============

create or replace function app.profit_summary_core(p_from date, p_to date)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v     jsonb;
  v_m   jsonb;
  v_pct numeric;
  v_rev numeric;
begin
  v_m := app.margin_summary_core(p_from, p_to);
  v_pct := coalesce((select (value ->> 'pct')::numeric
                       from app_settings where key = 'finance.employer_cost'), 0);

  -- סך הכנסות לפי פילוח הכנסות
  with 
  trans_sia as (
    select coalesce(sum(ei.amount), 0) as total
      from event_income ei
      join app.live_events e on e.id = ei.event_id and e.deleted_at is null
           and e.event_date between p_from and p_to
      join customers c on c.id = e.customer_id
      join income_categories ic on ic.id = ei.category_id
     where c.name = 'שיא עיצובים' and ic.name = 'הובלות'
  ),
  event_tasks as (
    select e.id as event_id, e.customer_id, c.name as customer_name,
           coalesce(c.commission_pct, 0) as commission_pct,
           coalesce(c.commission_min_event, 0) as commission_min_event,
           coalesce(sum(tp.price), 0) as task_sum
      from app.live_events e
      join customers c on c.id = e.customer_id
      left join app.live_tasks t on t.event_id = e.id and t.deleted_at is null
      left join app.task_revenue tp on tp.task_id = t.id
     where e.deleted_at is null
       and e.event_date between p_from and p_to
     group by e.id, e.customer_id, c.name, c.commission_pct, c.commission_min_event
    union all
    select null as event_id, t.customer_id, c.name as customer_name,
           0 as commission_pct, 0 as commission_min_event,
           sum(tp.price) as task_sum
      from app.live_tasks t
      join app.task_revenue tp on tp.task_id = t.id
      join customers c on c.id = t.customer_id
     where t.event_id is null and t.deleted_at is null
       and t.task_date between p_from and p_to
     group by t.customer_id, c.name
  ),
  cust_logistics as (
    select coalesce(sum(
             case 
               when (et.commission_pct > 0 or et.customer_name = 'קיסר') and et.task_sum > coalesce(et.commission_min_event, 2000) then
                 et.task_sum - round(et.task_sum * (case when et.commission_pct > 0 then et.commission_pct else 10 end) / 100, 2)
               else
                 et.task_sum
             end
           ), 0) as total
      from event_tasks et
  ),
  furn_new as (
    select coalesce(sum(ei.amount * 0.20), 0) as total
      from event_income ei
      join app.live_events e on e.id = ei.event_id and e.deleted_at is null
           and e.event_date between p_from and p_to
      join income_categories ic on ic.id = ei.category_id
     where ic.name = 'ריהוט חדש'
  ),
  furn_old as (
    select coalesce(sum(ei.amount * 0.70), 0) as total
      from event_income ei
      join app.live_events e on e.id = ei.event_id and e.deleted_at is null
           and e.event_date between p_from and p_to
      join income_categories ic on ic.id = ei.category_id
     where ic.name = 'ריהוט ישן'
  ),
  -- ‏0212: הכיסאות — העמלה שנקבעה ביד, כולה של וייפר (ועד שנקבעה, האחוז)
  furn_manual as (
    select coalesce(sum(app.income_viper_share(ei.amount, ei.viper_share_pct, ei.commission_amount)), 0) as total
      from event_income ei
      join app.live_events e on e.id = ei.event_id and e.deleted_at is null
           and e.event_date between p_from and p_to
      join income_categories ic on ic.id = ei.category_id
     where ic.manual_commission
  )
  select round((select total from trans_sia) + (select total from cust_logistics) + (select total from furn_new) + (select total from furn_old) + (select total from furn_manual), 2)
    into v_rev;

  v := jsonb_build_object(
    'revenue',      v_rev,
    'payroll',      v_m -> 'payroll',
    'employer_pct', v_pct,
    'payroll_with_employer',
      round(coalesce((v_m ->> 'payroll')::numeric, 0) * (1 + v_pct / 100), 2),
    'contractor',   v_m -> 'contractor',
    'profit',
      round(coalesce(v_rev, 0)
            - coalesce((v_m ->> 'payroll')::numeric, 0) * (1 + v_pct / 100)
            - coalesce((v_m ->> 'contractor')::numeric, 0), 2),
    'pct', case when coalesce(v_rev, 0) > 0
                then round((coalesce(v_rev, 0)
                            - coalesce((v_m ->> 'payroll')::numeric, 0) * (1 + v_pct / 100)
                            - coalesce((v_m ->> 'contractor')::numeric, 0))
                           / v_rev * 100, 1) end,
    'unrated_shifts', v_m -> 'unrated_shifts',
    'excludes_overhead', true);

  return v;
end $$;

comment on function app.profit_summary_core(date, date) is
  'הסקשן "רווח" של הדשבורד (finance.profit_summary, 0213) בלי שער (0241): הכנסות לפי '
  'הפילוח, פחות שכר × (1 + עלות מעביד %) ופחות קבלנים. נשללת מכולם: השער אצל הקורא — '
  'app.profit_summary למשתמש, ומסך הקיר מאחורי סוד ב-Vault.';

create or replace function app.profit_summary(p_from date, p_to date)
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  perform app.margin_require();
  return app.profit_summary_core(p_from, p_to);
end $$;

revoke execute on function app.profit_summary_core(date, date) from public, anon, authenticated, service_role;
revoke execute on function app.profit_summary(date, date) from anon, public;
grant  execute on function app.profit_summary(date, date) to authenticated;

-- הדשבורד: הגוף של 0213 מילה במילה, והסקשן "רווח" קורא לעטיפה.
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
  v_com_pct numeric;
  v_com_min numeric;
  v_rev    numeric;
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
  if coalesce(array_length(p_sections, 1), 0) > 60 then
    raise exception 'יותר מדי סקשנים בבקשה אחת' using errcode = '22023';
  end if;

  foreach v_key in array coalesce(p_sections, '{}'::text[]) loop
    v_val := null;

    if v_key = 'revenue.trend' and app.has('pricing.revenue') then
      select coalesce(jsonb_agg(row_to_json(x) order by x.bucket), '[]') into v_val from (
        select u.bucket, round(sum(u.total), 2) as total from (
          select date_trunc(v_bucket, t.task_date)::date as bucket, sum(tp.price) as total
            from app.task_revenue tp
            join app.live_tasks t on t.id = tp.task_id and t.deleted_at is null
           where t.task_date between p_from and p_to
           group by 1
          union all
          select date_trunc(v_bucket, e.event_date)::date, sum(ei.amount)
            from event_income ei
            join app.live_events e on e.id = ei.event_id and e.deleted_at is null
           where e.event_date between p_from and p_to
           group by 1) u
         group by u.bucket) x;

    elsif v_key = 'revenue.forecast' and app.has('pricing.revenue') then
      select jsonb_build_object(
        'total', round(coalesce(sum(tp.price), 0)
                       + coalesce((select sum(ei.amount)
                                     from event_income ei
                                     join app.live_events e on e.id = ei.event_id and e.deleted_at is null
                                    where e.event_date > current_date), 0), 2),
        'tasks', count(*),
        'by_month', (select coalesce(jsonb_agg(row_to_json(y) order by y.bucket), '[]') from (
            select u.bucket, round(sum(u.total), 2) as total from (
              select date_trunc('month', t2.task_date)::date as bucket, sum(tp2.price) as total
                from app.task_revenue tp2
                join app.live_tasks t2 on t2.id = tp2.task_id and t2.deleted_at is null
               where t2.task_date > current_date
                group by 1
              union all
              select date_trunc('month', e2.event_date)::date, sum(ei2.amount)
                from event_income ei2
                join app.live_events e2 on e2.id = ei2.event_id and e2.deleted_at is null
               where e2.event_date > current_date
                group by 1) u
             group by u.bucket) y))
        into v_val
        from app.task_revenue tp
        join app.live_tasks t on t.id = tp.task_id and t.deleted_at is null
       where t.task_date > current_date;

    elsif v_key = 'pricing.quality' and app.has('pricing.view') then
      select jsonb_build_object(
        'total',    count(*),
        'unpriced', count(*) filter (where tp.task_id is null or tp.price = 0),
        'manual',   count(*) filter (where tp.is_manual),
        'auto',     count(*) filter (where tp.task_id is not null and not tp.is_manual and tp.price > 0),
        'unpriced_list', (select coalesce(jsonb_agg(row_to_json(y)), '[]') from (
            select t2.id, t2.task_date, coalesce(c2.name, t2.title, tt2.name) as label
              from app.live_tasks t2
              left join task_pricing tp2 on tp2.task_id = t2.id
              left join customers c2 on c2.id = t2.customer_id
              left join task_types tt2 on tt2.id = t2.task_type_id
             where t2.deleted_at is null and t2.task_date between p_from and p_to
               and (tp2.task_id is null or tp2.price = 0)
             order by t2.task_date desc limit 8) y))
        into v_val
        from app.live_tasks t
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
        join app.live_tasks t on t.id = tct.task_id and t.deleted_at is null
       where t.task_date between p_from and p_to;

    elsif v_key = 'cost.by_contractor' and app.has('dashboard.contractor_cost') and app.has('contractors.view') then
      select coalesce(jsonb_agg(row_to_json(x)), '[]') into v_val from (
        select ct.name,
               round(sum(tct.price), 2) as expected,
               round(sum(coalesce(tct.paid_amount, tct.price)) filter (where tct.paid_at is not null), 2) as paid
          from task_contractor_terms tct
          join app.live_tasks t on t.id = tct.task_id and t.deleted_at is null
          join contractors ct on ct.id = tct.contractor_id
         where t.task_date between p_from and p_to
         group by ct.name order by 2 desc limit v_limit) x;

    elsif v_key = 'cost.contractor_unpaid' and app.has('dashboard.contractor_cost')
          and app.has('contractors.view_pricing') then
      select coalesce(jsonb_agg(row_to_json(x)), '[]') into v_val from (
        select t.id as task_id, t.task_date, ct.name as contractor, tct.price
          from task_contractor_terms tct
          join app.live_tasks t on t.id = tct.task_id and t.deleted_at is null
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

    -- ── סיכום רווח: סך הכנסות מהאירועים לפי הפילוח פחות הוצאות (שכר×מעביד + קבלנים) ─────
    elsif v_key = 'finance.profit_summary' and v_margin and not v_scoped then
      -- ‏0241: אותו חישוב בדיוק, מפונקציה אחת — הדשבורד ומסך הקיר קוראים לה
      v_val := app.profit_summary(p_from, p_to);

    -- ── הכנסות לפי קטגוריה ────────────────────────────────────────────────
    elsif v_key = 'income.by_category' and app.has('finance.income_view') then
      with cat as (
        select ic.id, ic.name, ic.family, ic.color, ic.sort_order, ic.manual_commission,
               round(coalesce(sum(ei.amount) filter (where e.id is not null), 0), 2) as total,
               -- ‏0212: החלק של וייפר — העמלה שנקבעה ביד, ועד שנקבעה האחוז
               round(coalesce(sum(app.income_viper_share(ei.amount, ei.viper_share_pct, ei.commission_amount))
                                filter (where e.id is not null), 0), 2) as viper_share
          from income_categories ic
          left join event_income ei on ei.category_id = ic.id
          left join app.live_events e on e.id = ei.event_id and e.deleted_at is null
               and e.event_date between p_from and p_to
         group by ic.id, ic.name, ic.family, ic.color, ic.sort_order, ic.manual_commission
        having (ic.deleted_at is null and ic.is_active)
            or coalesce(sum(ei.amount) filter (where e.id is not null), 0) <> 0)
      select jsonb_build_object(
        'rows', coalesce((select jsonb_agg(row_to_json(c) order by c.sort_order) from cat c), '[]'::jsonb),
        'furniture_total', round(coalesce((select sum(total) from cat where family = 'furniture'), 0), 2),
        'logistics_total', round(coalesce((select sum(total) from cat where family = 'logistics'), 0), 2),
        'total', round(coalesce((select sum(total) from cat), 0), 2),
        'manual_commission_total',
          round(coalesce((select sum(viper_share) from cat where manual_commission), 0), 2))
        into v_val;

    -- ── פילוח הכנסות: הובלות שיא עיצובים, לוגיסטיקה לפי לקוח, ריהוט חדש (20%), ריהוט ישן (70%) ──
    elsif v_key = 'income.mix' and app.has('finance.income_view') and app.has('customers.view') then
      with 
      -- 1. הובלות של שיא עיצובים (100% להכנסות)
      trans_sia as (
        select 'הובלות שיא עיצובים' as label, ic.color as color, round(sum(ei.amount), 2) as total
          from event_income ei
          join app.live_events e on e.id = ei.event_id and e.deleted_at is null
               and e.event_date between p_from and p_to
          join customers c on c.id = e.customer_id
          join income_categories ic on ic.id = ei.category_id
         where c.name = 'שיא עיצובים' and ic.name = 'הובלות'
         group by ic.color
      ),
      -- 2. הכנסה לוגיסטיקה לפי לקוח (סך משימות האירועים; עבור קיסר פחות 10% מעל 2000 ש"ח לאירוע)
      event_tasks as (
        select e.id as event_id, e.customer_id, c.name as customer_name, c.color as customer_color,
               coalesce(c.commission_pct, 0) as commission_pct,
               coalesce(c.commission_min_event, 0) as commission_min_event,
               coalesce(sum(tp.price), 0) as task_sum
          from app.live_events e
          join customers c on c.id = e.customer_id
          left join app.live_tasks t on t.event_id = e.id and t.deleted_at is null
          left join app.task_revenue tp on tp.task_id = t.id
         where e.deleted_at is null
           and e.event_date between p_from and p_to
         group by e.id, e.customer_id, c.name, c.color, c.commission_pct, c.commission_min_event
        union all
        select null as event_id, t.customer_id, c.name as customer_name, c.color as customer_color,
               0 as commission_pct, 0 as commission_min_event,
               sum(tp.price) as task_sum
          from app.live_tasks t
          join app.task_revenue tp on tp.task_id = t.id
          join customers c on c.id = t.customer_id
         where t.event_id is null and t.deleted_at is null
           and t.task_date between p_from and p_to
         group by t.customer_id, c.name, c.color
      ),
      cust_logistics as (
        select 'לוגיסטיקה ' || et.customer_name as label,
               et.customer_color as color,
               round(sum(
                 case 
                   when (et.commission_pct > 0 or et.customer_name = 'קיסר') and et.task_sum > coalesce(et.commission_min_event, 2000) then
                     et.task_sum - round(et.task_sum * (case when et.commission_pct > 0 then et.commission_pct else 10 end) / 100, 2)
                   else
                     et.task_sum
                 end
               ), 2) as total
          from event_tasks et
         group by et.customer_name, et.customer_color
        having sum(et.task_sum) > 0
      ),
      -- 3. ריהוט חדש (20% להכנסות)
      furn_new as (
        select 'ריהוט חדש' as label, ic.color as color, round(sum(ei.amount * 0.20), 2) as total
          from event_income ei
          join app.live_events e on e.id = ei.event_id and e.deleted_at is null
               and e.event_date between p_from and p_to
          join income_categories ic on ic.id = ei.category_id
         where ic.name = 'ריהוט חדש'
         group by ic.color
      ),
      -- 4. ריהוט ישן (70% להכנסות)
      furn_old as (
        select 'ריהוט ישן' as label, ic.color as color, round(sum(ei.amount * 0.70), 2) as total
          from event_income ei
          join app.live_events e on e.id = ei.event_id and e.deleted_at is null
               and e.event_date between p_from and p_to
          join income_categories ic on ic.id = ei.category_id
         where ic.name = 'ריהוט ישן'
         group by ic.color
      ),
      -- 5. ‏0212: עמלה שנקבעה ביד (כיסאות) — 100% להכנסות (ועד שנקבעה, האחוז)
      furn_manual as (
        select 'עמלת ' || ic.name as label, ic.color as color,
               round(sum(app.income_viper_share(ei.amount, ei.viper_share_pct, ei.commission_amount)), 2) as total
          from event_income ei
          join app.live_events e on e.id = ei.event_id and e.deleted_at is null
               and e.event_date between p_from and p_to
          join income_categories ic on ic.id = ei.category_id
         where ic.manual_commission
         group by ic.name, ic.color
      ),
      all_mix as (
        select label, color, total from trans_sia
        union all
        select label, color, total from cust_logistics
        union all
        select label, color, total from furn_new
        union all
        select label, color, total from furn_old
        union all
        select label, color, total from furn_manual
      )
      select coalesce(jsonb_agg(row_to_json(x)), '[]') into v_val from (
        select label, color, total
          from all_mix
         where total > 0
         order by total desc limit v_limit
      ) x;

    -- ── תשלום לוויפר: מה שהלקוחות חייבים, מה ששולם, והיתרה ───────────────
    elsif v_key = 'finance.receivables' and app.has('finance.receipts_view')
          and app.has('finance.income_view') then
      with rev as (
        select u.cid, sum(u.amount) as owed from (
          select e.customer_id as cid, ei.amount
            from event_income ei
            join app.live_events e on e.id = ei.event_id and e.deleted_at is null
           where e.event_date between p_from and p_to
          union all
          select t.customer_id, tp.price
            from app.task_revenue tp
            join app.live_tasks t on t.id = tp.task_id and t.deleted_at is null
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

    -- ── הכנסות לשיא עיצובים: 80% מריהוט חדש ו-30% מריהוט ישן עם פילוח ────
    elsif v_key = 'finance.client_share' and app.has('finance.income_view') then
      select jsonb_build_object(
        'total', round(coalesce(sum(case 
                    when ic.name = 'ריהוט חדש' then ei.amount * 0.80
                    when ic.name = 'ריהוט ישן' then ei.amount * 0.30
                    else ei.amount - app.income_viper_share(ei.amount, ei.viper_share_pct, ei.commission_amount)
                  end), 0), 2),
        'furniture_new_share', round(coalesce(sum(case when ic.name = 'ריהוט חדש' then ei.amount * 0.80 else 0 end), 0), 2),
        'furniture_old_share', round(coalesce(sum(case when ic.name = 'ריהוט ישן' then ei.amount * 0.30 else 0 end), 0), 2),
        'furniture_new_raw', round(coalesce(sum(case when ic.name = 'ריהוט חדש' then ei.amount else 0 end), 0), 2),
        'furniture_old_raw', round(coalesce(sum(case when ic.name = 'ריהוט ישן' then ei.amount else 0 end), 0), 2),
        -- ‏0212: הכיסאות — הסכום, העמלה שנקבעה ביד, ומה שנשאר ללקוח
        'chairs_raw', round(coalesce(sum(case when ic.manual_commission then ei.amount else 0 end), 0), 2),
        'chairs_commission', round(coalesce(sum(case when ic.manual_commission
                                                      then app.income_viper_share(ei.amount, ei.viper_share_pct, ei.commission_amount)
                                                      else 0 end), 0), 2),
        'chairs_share', round(coalesce(sum(case when ic.manual_commission
                                                 then ei.amount - app.income_viper_share(ei.amount, ei.viper_share_pct, ei.commission_amount)
                                                 else 0 end), 0), 2),
        -- ‏0213: אותו פירוט לכל קטגוריה ידנית בנפרד — כיסאות, פריטים חופשיים
        'manual_rows', (select coalesce(jsonb_agg(jsonb_build_object(
                           'name', m.name, 'raw', m.raw, 'commission', m.commission,
                           'share', m.raw - m.commission) order by m.sort_order), '[]'::jsonb)
                          from (select ic3.name, ic3.sort_order,
                                       round(sum(ei3.amount), 2) as raw,
                                       round(sum(app.income_viper_share(ei3.amount, ei3.viper_share_pct,
                                                                        ei3.commission_amount)), 2) as commission
                                  from event_income ei3
                                  join app.live_events e3 on e3.id = ei3.event_id and e3.deleted_at is null
                                       and e3.event_date between p_from and p_to
                                  join customers c3 on c3.id = e3.customer_id
                                  join income_categories ic3 on ic3.id = ei3.category_id
                                 where c3.name = 'שיא עיצובים' and ic3.manual_commission
                                 group by ic3.name, ic3.sort_order) m),
        'rows', case when app.has('customers.view') then
          (select coalesce(jsonb_agg(row_to_json(y)), '[]') from (
             select c.name, c.color,
                    round(sum(case 
                      when c.name = 'שיא עיצובים' and ic2.name = 'ריהוט חדש' then ei2.amount * 0.80
                      when c.name = 'שיא עיצובים' and ic2.name = 'ריהוט ישן' then ei2.amount * 0.30
                      else ei2.amount - app.income_viper_share(ei2.amount, ei2.viper_share_pct, ei2.commission_amount)
                    end), 2) as total
               from event_income ei2
               join app.live_events e2 on e2.id = ei2.event_id and e2.deleted_at is null
                    and e2.event_date between p_from and p_to
               join customers c on c.id = e2.customer_id
               join income_categories ic2 on ic2.id = ei2.category_id
              group by c.name, c.color
             having sum(case 
                      when c.name = 'שיא עיצובים' and ic2.name = 'ריהוט חדש' then ei2.amount * 0.80
                      when c.name = 'שיא עיצובים' and ic2.name = 'ריהוט ישן' then ei2.amount * 0.30
                      else ei2.amount - app.income_viper_share(ei2.amount, ei2.viper_share_pct, ei2.commission_amount)
                    end) <> 0
              order by 3 desc limit v_limit) y)
          else null end)
        into v_val
        from event_income ei
        join app.live_events e on e.id = ei.event_id and e.deleted_at is null
             and e.event_date between p_from and p_to
        join customers c on c.id = e.customer_id
        join income_categories ic on ic.id = ei.category_id
       where c.name = 'שיא עיצובים';

    -- ── עמלה לקיסר: 10% מאירועים של קיסר שסך כל המשימות של האירוע מעל 2000 ש"ח ──
    elsif v_key = 'finance.keisar_commission' and app.has('finance.income_view') then
      with ev as (
        select e.id,
               coalesce(sum(tp.price), 0) as task_sum
          from app.live_events e
          join customers c on c.id = e.customer_id
          left join app.live_tasks t on t.event_id = e.id and t.deleted_at is null
          left join app.task_revenue tp on tp.task_id = t.id
         where c.name = 'קיסר' and e.deleted_at is null
           and e.event_date between p_from and p_to
         group by e.id
      ),
      qualifying as (
        select ev.task_sum, round(ev.task_sum * 0.10, 2) as commission
          from ev
         where ev.task_sum > 2000
      )
      select jsonb_build_object(
        'total', round(coalesce(sum(commission), 0), 2),
        'events_count', count(*),
        'tasks_total', round(coalesce(sum(task_sum), 0), 2)
      ) into v_val from qualifying;

    elsif v_key = 'tasks.by_type' then
      select coalesce(jsonb_agg(row_to_json(x)), '[]') into v_val from (
        select tt.name, count(*) as cnt
          from app.live_tasks t join task_types tt on tt.id = t.task_type_id
         where t.deleted_at is null and t.task_date between p_from and p_to
         group by tt.name order by 2 desc limit v_limit) x;

    elsif v_key = 'tasks.by_method' then
      select coalesce(jsonb_agg(row_to_json(x)), '[]') into v_val from (
        select em.name, count(*) as cnt
          from app.live_tasks t join execution_methods em on em.id = t.execution_method_id
         where t.deleted_at is null and t.task_date between p_from and p_to
         group by em.name order by 2 desc limit v_limit) x;

    elsif v_key = 'tasks.trend' then
      select coalesce(jsonb_agg(row_to_json(x) order by x.bucket), '[]') into v_val from (
        select bucket, sum(tasks) as tasks, sum(events) as events from (
          select date_trunc(v_bucket, t.task_date)::date as bucket, count(*) as tasks, 0 as events
            from app.live_tasks t where t.deleted_at is null and t.task_date between p_from and p_to
           group by 1
          union all
          select date_trunc(v_bucket, e.event_date)::date, 0, count(*)
            from app.live_events e where e.deleted_at is null and e.event_date between p_from and p_to
           group by 1) u
         group by bucket) x;

    elsif v_key = 'tasks.understaffed'
          and (app.has('dashboard.all_workers') or app.has('tasks.assign.worker')) then
      select jsonb_build_object(
        'count', count(*),
        'rows', (select coalesce(jsonb_agg(row_to_json(y)), '[]') from (
            select t2.id, t2.task_date, coalesce(c2.name, t2.title) as label,
                   t2.worker_count as needed,
                   ((select count(*) from task_assignments a2
                      where a2.task_id = t2.id and a2.role = 'worker')
                    + (select count(*) from task_contractor_workers cw2
                        where cw2.task_id = t2.id)) as assigned
              from app.live_tasks t2
              left join customers c2 on c2.id = t2.customer_id
              join statuses s2 on s2.id = t2.status_id
             where t2.deleted_at is null and t2.task_date between p_from and p_to
               and not s2.is_terminal and t2.worker_count > 0
               and ((select count(*) from task_assignments a3
                      where a3.task_id = t2.id and a3.role = 'worker')
                    + (select count(*) from task_contractor_workers cw3
                        where cw3.task_id = t2.id)) < t2.worker_count
             order by t2.task_date limit 8) y))
        into v_val
        from app.live_tasks t
        join statuses s on s.id = t.status_id
       where t.deleted_at is null and t.task_date between p_from and p_to
         and not s.is_terminal and t.worker_count > 0
         and ((select count(*) from task_assignments a
                where a.task_id = t.id and a.role = 'worker')
              + (select count(*) from task_contractor_workers cw
                  where cw.task_id = t.id)) < t.worker_count;

    elsif v_key = 'tasks.no_truck' then
      select jsonb_build_object('count', count(*)) into v_val
        from app.live_tasks t join statuses s on s.id = t.status_id
       where t.deleted_at is null and t.task_date between p_from and p_to
         and not s.is_terminal
         and coalesce(cardinality(t.truck_ids), 0) = 0 and t.truck_free_text is null;

    elsif v_key = 'fleet.utilization' then
      select coalesce(jsonb_agg(row_to_json(x)), '[]') into v_val from (
        select tr.name,
               count(distinct t.task_date) as days,
               count(*) as tasks
          from app.live_tasks t
          cross join lateral unnest(t.truck_ids) as u(truck_id)
          join trucks tr on tr.id = u.truck_id
         where t.deleted_at is null and t.task_date between p_from and p_to
         group by tr.name order by 2 desc limit v_limit) x;

    elsif v_key = 'events.by_customer' and app.has('customers.view') then
      select coalesce(jsonb_agg(row_to_json(x)), '[]') into v_val from (
        select c.name, c.color, count(*) as cnt
          from app.live_events e join customers c on c.id = e.customer_id
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
              from app.live_events e2 join customers c2 on c2.id = e2.customer_id
             where e2.deleted_at is null and e2.event_date between p_from and p_to
             group by c2.name, c2.color order by 3 desc limit v_limit) y))
        into v_val
        from app.live_events e
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
                                             join app.live_events e3 on e3.id = ei.event_id
                                              and e3.deleted_at is null
                                              and e3.event_date between p_from and p_to
                                            where e3.customer_id = c.id), 0), 2) end as revenue,
               max(e.event_date) as last_event
          from customers c
          left join app.live_events e on e.customer_id = c.id and e.deleted_at is null
               and e.event_date between p_from and p_to
          left join app.live_tasks t on t.customer_id = c.id and t.deleted_at is null
               and t.task_date between p_from and p_to
          left join lateral (
            select tp.price from app.task_revenue tp where tp.task_id = t.id) distinct_price on true
         where c.deleted_at is null
         group by c.id, c.name, c.color
        having count(distinct e.id) > 0 or count(distinct t.id) > 0
         limit v_limit) x;

    elsif v_key = 'customers.inactive' and app.has('customers.view') then
      select coalesce(jsonb_agg(row_to_json(x)), '[]') into v_val from (
        select c.name, c.color,
               (select max(e2.event_date) from app.live_events e2
                 where e2.customer_id = c.id and e2.deleted_at is null) as last_event
          from customers c
         where c.deleted_at is null and c.is_active
           and not exists (select 1 from app.live_events e where e.customer_id = c.id
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

    elsif v_key = 'attendance.active_and_recent' and (app.has('attendance.view_all') or exists (select 1 from profiles where user_id = auth.uid() and is_admin)) then
      select jsonb_build_object(
        'active_count', count(*) filter (where e.clock_out_at is null),
        'total_count', count(*),
        'shifts', coalesce(jsonb_agg(jsonb_build_object(
          'id', e.id,
          'profile_id', e.profile_id,
          'worker_name', p.full_name,
          'phone', p.phone,
          'work_site', e.work_site,
          'task_or_event', (
            select coalesce(ev.end_client_name, t.title, ev.location_text)
            from tasks t left join events ev on ev.id = t.event_id
            where t.id = e.task_ids[1] limit 1
          ),
          'clock_in_at', e.clock_in_at,
          'clock_out_at', e.clock_out_at,
          'is_active', (e.clock_out_at is null),
          'status', e.status,
          'actual_hours', e.actual_hours,
          'duration_minutes', case
            when e.clock_out_at is not null then round(extract(epoch from (e.clock_out_at - e.clock_in_at)) / 60)
            else round(extract(epoch from (now() - e.clock_in_at)) / 60)
          end
        ) order by
          (e.clock_out_at is null) desc,
          e.clock_in_at desc
        ), '[]'::jsonb)
      ) into v_val
      from (
        select * from attendance_entries
        where deleted_at is null
          and (clock_out_at is null or clock_out_at >= now() - interval '24 hours' or clock_in_at >= now() - interval '24 hours')
        order by (clock_out_at is null) desc, clock_in_at desc
        limit 50
      ) e
      join profiles p on p.id = e.profile_id;

    elsif v_key = 'hr.headcount' and app.has('dashboard.all_workers') then
      select jsonb_build_object(
        'active', count(*) filter (where p.is_active),
        'staff',  count(*) filter (where p.is_active and p.user_kind = 'staff'))
        into v_val
        from profiles p where p.deleted_at is null;

    elsif v_key = 'spend.summary' and app.has('finance.customer_spend') then
      select jsonb_build_object(
        'total', round(coalesce(sum(tp.price), 0), 2),
        'tasks', count(*),
        'by_event', (select coalesce(jsonb_agg(row_to_json(y) order by y.total desc), '[]') from (
            select e2.id, e2.event_date,
                   coalesce(nullif(e2.end_client_name, ''), 'אירוע ' || e2.event_number) as label,
                   round(sum(tp2.price), 2) as total
              from app.task_revenue tp2
              join app.live_tasks t2 on t2.id = tp2.task_id and t2.deleted_at is null
              join app.live_events e2 on e2.id = t2.event_id and e2.deleted_at is null
             where t2.task_date between p_from and p_to and tp2.price > 0
             group by e2.id, e2.event_date, e2.end_client_name, e2.event_number
             order by 4 desc limit v_limit) y),
        'by_bucket', (select coalesce(jsonb_agg(row_to_json(z) order by z.bucket), '[]') from (
            select date_trunc(v_bucket, t3.task_date)::date as bucket,
                   round(sum(tp3.price), 2) as total
              from app.task_revenue tp3
              join app.live_tasks t3 on t3.id = tp3.task_id and t3.deleted_at is null
             where t3.task_date between p_from and p_to
             group by 1) z))
        into v_val
        from app.task_revenue tp
        join app.live_tasks t on t.id = tp.task_id and t.deleted_at is null
       where t.task_date between p_from and p_to;

    elsif v_key = 'customer.monthly' and app.has('finance.customer_monthly')
          and app.customer_id() is not null then
      select c.commission_pct, coalesce(c.commission_min_event, 0)
        into v_com_pct, v_com_min
        from customers c where c.id = app.customer_id();

      with ev as (
        select e.id, e.event_date,
               date_trunc('month', e.event_date)::date as month,
               coalesce((select sum(tr.price)
                           from app.live_tasks t
                           join app.task_revenue tr on tr.task_id = t.id
                          where t.event_id = e.id and t.deleted_at is null), 0) as total
          from app.live_events e
         where e.deleted_at is null
           and e.event_date between
                 least(p_from, (date_trunc('month', p_to) - interval '11 months')::date) and p_to
      ), ec as (
        select ev.*,
               case when v_com_pct is null or ev.total <= v_com_min then 0
                    else round(ev.total * v_com_pct / 100, 2) end as commission,
               (v_com_pct is null or ev.total > 0) as billed
          from ev
      )
      select jsonb_build_object(
        'events',     (select count(*) from ec where billed and event_date between p_from and p_to),
        'total',      (select round(coalesce(sum(total), 0), 2)
                         from ec where billed and event_date between p_from and p_to),
        'commission', case when v_com_pct is null then null
                           else (select round(coalesce(sum(commission), 0), 2)
                                   from ec where event_date between p_from and p_to) end,
        'commission_pct', v_com_pct,
        'commission_min', v_com_min,
        'months', (select coalesce(jsonb_agg(row_to_json(m) order by m.month), '[]') from (
            select month,
                   count(*)             as events,
                   round(sum(total), 2) as total,
                   case when v_com_pct is null then null
                        else round(sum(commission), 2) end as commission
              from ec where billed group by month) m))
        into v_val;

    elsif v_key = 'fleet.status' and app.has('fleet.view') then
      select jsonb_build_object(
        'total',     count(*),
        'active',    count(*) filter (where status = 'active'),
        'in_garage', count(*) filter (where status = 'in_garage'),
        'inactive',  count(*) filter (where status = 'inactive'))
        into v_val
        from vehicles where deleted_at is null and status <> 'sold';

    elsif v_key = 'fleet.documents_expiring'
          and app.has('fleet.view') and app.has('fleet.docs_view') then
      select coalesce(jsonb_agg(row_to_json(x) order by x.expires_at), '[]') into v_val from (
        select v.id as vehicle_id, v.name, v.plate_number,
               s.kind_name, s.expires_at, s.days_left, s.status
          from vehicle_document_status s
          join vehicles v on v.id = s.vehicle_id
         where s.deleted_at is null and v.deleted_at is null and v.status <> 'sold'
           and s.status in ('expired', 'expiring')
         order by s.expires_at limit v_limit) x;

    end if;

    v_out := v_out || jsonb_build_object(v_key, v_val);
  end loop;

  return v_out;
end $$;

-- ===== 2. לו״ז המחסן: ליבה בלי שער המשתמש, ועטיפה עם השער ==================

create or replace function app.warehouse_rows_core(p_from date, p_to date, p_event_id uuid)
returns table (
  event_id        uuid,
  kind            warehouse_task_kind,
  customer_id     uuid,
  customer_name   text,
  customer_color  text,
  event_number    text,
  end_client_name text,
  event_date      date,
  task_date       date,
  date_is_manual  boolean,
  start_time      time,
  duration_hours  numeric,
  notes           text,
  final_approved  boolean,
  event_ready     boolean,
  checked         boolean,
  updated_at      timestamptz)
language sql stable security definer set search_path = public as $$
  with ev as (
    select e.id, e.customer_id, e.event_number, e.end_client_name, e.event_date,
           c.name as customer_name, c.color as customer_color
      from events e
      join customers c on c.id = e.customer_id
     where e.deleted_at is null
       and e.status_id is distinct from (select app.cancelled_event_status_id())
       and (case when p_event_id is null
                 then e.event_date between p_from - 31 and p_to + 31
                 else e.id = p_event_id end)
       -- ‏0241: הדגל בלבד; מי שקורא — השער שלו אצלו (app.warehouse_rows / מסך הקיר)
       and c.warehouse_schedule_enabled and c.deleted_at is null
  ),
  wr as (
    select ev.id as event_id, k.kind, ev.customer_id, ev.customer_name, ev.customer_color,
           ev.event_number, ev.end_client_name, ev.event_date,
           coalesce(w.task_date,
                    case k.kind when 'prep' then d.prep_date else d.return_date end) as task_date,
           w.task_date is not null as date_is_manual,
           w.start_time, coalesce(w.duration_hours, 0) as duration_hours, w.notes,
           coalesce(w.final_approved, false) as final_approved,
           coalesce(w.event_ready, false) as event_ready,
           coalesce(w.checked, false) as checked,
           w.updated_at
      from ev
      cross join lateral app.warehouse_anchor_dates(ev.id, ev.event_date) d
      cross join (values ('prep'::warehouse_task_kind), ('return'::warehouse_task_kind)) k(kind)
      left join warehouse_tasks w on w.event_id = ev.id and w.kind = k.kind
  )
  select * from wr
   where p_event_id is not null or task_date between p_from and p_to
$$;

comment on function app.warehouse_rows_core(date, date, uuid) is
  'שורות לו״ז המחסן (0226) בלי שער המשתמש — רק הדגל warehouse_schedule_enabled (0241). '
  'נשללת מכולם: app.warehouse_rows עוטפת אותה עם app.warehouse_customer_visible, '
  'ומסך הקיר קורא לה מאחורי הסוד.';

create or replace function app.warehouse_rows(p_from date, p_to date, p_event_id uuid)
returns table (
  event_id        uuid,
  kind            warehouse_task_kind,
  customer_id     uuid,
  customer_name   text,
  customer_color  text,
  event_number    text,
  end_client_name text,
  event_date      date,
  task_date       date,
  date_is_manual  boolean,
  start_time      time,
  duration_hours  numeric,
  notes           text,
  final_approved  boolean,
  event_ready     boolean,
  checked         boolean,
  updated_at      timestamptz)
language sql stable security definer set search_path = public as $$
  select r.* from app.warehouse_rows_core(p_from, p_to, p_event_id) r
   where app.warehouse_customer_visible(r.customer_id)
$$;

revoke execute on function app.warehouse_rows_core(date, date, uuid) from public, anon, authenticated, service_role;

-- ===== 3. התמונה של מסך הקיר ===============================================
--
-- הגוף של 0203 מילה במילה, ועוד ארבעת החלקים שלמעלה לפני ה-`return`.

create or replace function app.wall_snapshot_at(p_now timestamptz, p_days int default 3)
returns jsonb
language plpgsql stable security definer
set search_path = public
-- חותמות הזמן ב-JSON יוצאות באזור הזמן של הסשן. UTC קבוע הופך אותן
-- ל-"…+00:00" בכל קריאה, בלי קשר למי שקרא.
set timezone to 'UTC'
as $$
declare
  v_now        timestamptz := coalesce(p_now, now());
  v_today      date;
  v_days       int := greatest(1, least(coalesce(p_days, 3), 14));
  v_week       date;
  v_month      date;
  v_month_end  date;
  v_horizon    timestamptz;
  v_auto       interval;
  v_tasks      jsonb;
  v_kpis       jsonb;
  v_under      jsonb;
  v_unpub      jsonb;
  v_shifts     jsonb;
  v_att        jsonb;
  v_late       jsonb;
  v_fleet      jsonb;
  v_margin     jsonb;
  v_forecast   numeric;
  v_wh         jsonb;
  v_missions   jsonb;
  v_late_in    jsonb;
  v_ended      jsonb;
  v_profit     jsonb;
begin
  v_today     := (v_now at time zone 'Asia/Jerusalem')::date;
  -- השבוע מתחיל ביום ראשון (dow = 0)
  v_week      := v_today - extract(dow from v_today)::int;
  v_month     := make_date(extract(year from v_today)::int, extract(month from v_today)::int, 1);
  v_month_end := (v_month + interval '1 month')::date - 1;
  v_horizon   := v_now + interval '48 hours';
  -- אותו סף ואותה ברירת מחדל שהשעון סוגר בהם החתמה שנשכחה (0168)
  v_auto      := make_interval(hours => coalesce(
                   (app.attendance_config('attendance.clock') ->> 'auto_close_after_hours')::int, 16));

  -- ‏4.1 המשימות: הרשימה, המונים, ושתי רשימות ההתראה. טווח אחד שמכסה את
  -- שלושתם — הרשימה עד today+days, המונים שבעה ימים, וההתראות 48 שעות.
  with r as materialized (
    select x.*,
           -- ב-48 השעות הקרובות: מתחילה לפני האופק, ועוד לא נגמרה. משימה
           -- בלי שעה נשארת עד סוף היום שלה.
           (x.task_date <= v_today + 2
            and coalesce(x.start_at, x.task_date::timestamp at time zone 'Asia/Jerusalem') < v_horizon
            and case when x.end_at is not null then x.end_at > v_now
                     else x.task_date >= v_today end) as in_48h
      from app.wall_task_rows(v_today, v_today + greatest(v_days, 6)) x
  )
  select
    coalesce((select jsonb_agg(jsonb_build_object(
                'id',               r.id,
                'date',             r.task_date,
                'type_code',        r.type_code,
                'type_name',        r.type_name,
                'status_code',      r.status_code,
                'status_name',      r.status_name,
                'status_color',     r.status_color,
                'published',        r.published,
                'warehouse_at',     r.warehouse_at,
                'start_at',         r.start_at,
                'end_at',           r.end_at,
                'customer_name',    r.customer_name,
                'customer_color',   r.customer_color,
                'end_client_name',  r.end_client_name,
                'event_number',     r.event_number,
                'title',            r.title,
                'location',         r.location,
                'needed',           r.needed,
                'assigned',         r.assigned,
                'delegated',        r.delegated,
                'contractor_names', to_jsonb(r.contractor_names),
                'team_lead_name',   r.team_lead_name,
                -- ‏0203: שמות הצוות, ראש הצוות ראשון — שמות בלבד
                'crew_names',       to_jsonb(app.wall_task_crew(r.id)),
                'trucks',           to_jsonb(r.trucks))
                order by r.task_date, r.start_at nulls last, r.warehouse_at nulls last,
                         r.label, r.id)
                from r
               where r.task_date <= v_today + v_days and not r.hidden), '[]'::jsonb),
    (select jsonb_build_object(
       'tasks_today',      count(*) filter (where r.task_date = v_today),
       'setups_today',     count(*) filter (where r.task_date = v_today and r.type_code = 'setup'),
       'teardowns_today',  count(*) filter (where r.task_date = v_today and r.type_code = 'teardown'),
       'tasks_next_7d',    count(*) filter (where r.task_date <= v_today + 6),
       'understaffed_48h', count(*) filter (where r.in_48h and not r.status_terminal
                                              and r.needed > r.assigned),
       'unpublished_48h',  count(*) filter (where r.in_48h and not r.status_terminal
                                              and not r.published))
       from r),
    coalesce((select jsonb_agg(jsonb_build_object(
                'task_id', u.id, 'date', u.task_date, 'label', u.label,
                'needed', u.needed, 'assigned', u.assigned)
                order by u.start_at nulls last, u.task_date, u.label, u.id)
                from (select * from r
                       where r.in_48h and not r.status_terminal and r.needed > r.assigned
                       order by r.start_at nulls last, r.task_date, r.label, r.id
                       limit 10) u), '[]'::jsonb),
    coalesce((select jsonb_agg(jsonb_build_object(
                'task_id', u.id, 'date', u.task_date, 'label', u.label)
                order by u.start_at nulls last, u.task_date, u.label, u.id)
                from (select * from r
                       where r.in_48h and not r.status_terminal and not r.published
                       order by r.start_at nulls last, r.task_date, r.label, r.id
                       limit 10) u), '[]'::jsonb)
    into v_tasks, v_kpis, v_under, v_unpub;

  -- ‏4.2 במשמרת עכשיו: החתמה פתוחה שצעירה מסף הסגירה האוטומטית, ושלא נדחתה.
  -- התווית היא של המשימה הראשונה של ההחתמה — ‏task_ids ממוינות כמו המשמרת
  -- (0034).
  select coalesce(jsonb_agg(jsonb_build_object(
           'profile_id',   e.profile_id,
           'name',         p.full_name,
           'clock_in_at',  e.clock_in_at,
           'work_site',    e.work_site,
           'hours_so_far', round(extract(epoch from (v_now - e.clock_in_at)) / 3600.0, 2),
           'task_label',   (select concat_ws(' · ', c.name,
                                     coalesce(nullif(btrim(t.title), ''),
                                              nullif(btrim(ev.end_client_name), ''), tt.name))
                              from tasks t
                              join task_types tt on tt.id = t.task_type_id
                              left join events ev on ev.id = t.event_id
                              left join app.customer_identities c on c.id = t.customer_id
                             where t.id = e.task_ids[1]))
           order by e.clock_in_at, p.full_name), '[]'::jsonb)
    into v_shifts
    from attendance_entries e
    join profiles p on p.id = e.profile_id
   where e.clock_out_at is null
     and e.deleted_at is null
     and e.status <> 'rejected'
     and e.clock_in_at <= v_now
     and e.clock_in_at > v_now - v_auto;

  -- ‏4.3 שעות: מאושרות שנסגרו, ועוד השעות החיות של הפתוחות (באותה הגדרה של
  -- 4.2). החתמה שנדחתה אינה עבודה, ולכן גם אינה "עובד היום".
  with ent as (
    select e.profile_id, e.work_date,
           (e.clock_out_at is null and e.clock_in_at <= v_now
            and e.clock_in_at > v_now - v_auto) as is_open,
           case when e.clock_out_at is null then
                  case when e.clock_in_at <= v_now and e.clock_in_at > v_now - v_auto
                       then extract(epoch from (v_now - e.clock_in_at)) / 3600.0 else 0 end
                when e.status = 'approved' then coalesce(e.actual_hours, 0)
                else 0 end as hrs
      from attendance_entries e
     where e.deleted_at is null
       and e.status <> 'rejected'
       and e.work_date between v_week and v_today
  ),
  today_by as (
    select ent.profile_id, sum(ent.hrs) as hrs, bool_or(ent.is_open) as is_open
      from ent where ent.work_date = v_today
     group by ent.profile_id
  )
  select jsonb_build_object(
           'hours_today',   round(coalesce((select sum(hrs) from ent where work_date = v_today), 0), 2),
           'hours_week',    round(coalesce((select sum(hrs) from ent), 0), 2),
           'workers_today', (select count(*) from today_by),
           'by_worker_today', coalesce((
              select jsonb_agg(jsonb_build_object(
                       'profile_id', b.profile_id,
                       'name',       p.full_name,
                       'hours',      round(b.hrs, 2),
                       'open',       b.is_open)
                       order by b.hrs desc, p.full_name)
                from today_by b join profiles p on p.id = b.profile_id), '[]'::jsonb))
    into v_att;

  -- ‏4.4 מאחרים: ROADMAP §3.4. המועמדים הם מי שמשובץ למשימה **משובצת** היום
  -- או מחר — מחר, כי יציאה מהמחסן יכולה לסגת אל הערב של היום (0163).
  -- ‏`app.planned_shifts_many` גוזרת את המשמרת משלושת המאגרים (0178), ומשם
  -- נשארות רק אלה שהתחילו היום לפני יותר מ-15 דקות, בלי אף החתמה היום.
  with live as (
    select x.id from app.wall_task_rows(v_today, v_today + 1) x where x.published
  ),
  cand as (
    select a.profile_id as pid
      from task_assignments a join live l on l.id = a.task_id
    union
    select pr.id
      from task_contractor_workers w
      join live l on l.id = w.task_id
      join profiles pr on pr.contractor_worker_id = w.contractor_worker_id
    union
    select pr.id
      from task_customer_workers w
      join live l on l.id = w.task_id
      join profiles pr on pr.customer_worker_id = w.customer_worker_id
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'profile_id',    s.profile_id,
           'name',          p.full_name,
           'planned_start', s.shift_start,
           'minutes_late',  floor(extract(epoch from (v_now - s.shift_start)) / 60)::int,
           'task_label',    concat_ws(' · ', c.name, s.label))
           order by s.shift_start, p.full_name), '[]'::jsonb)
    into v_late
    from app.planned_shifts_many(array(select pid from cand), v_today, v_today) s
    join profiles p on p.id = s.profile_id
    left join app.customer_identities c on c.id = s.customer_id
   where p.deleted_at is null
     and p.is_active
     and s.shift_start < v_now - interval '15 minutes'
     and not exists (select 1 from attendance_entries e
                      where e.profile_id = s.profile_id
                        and e.work_date = v_today
                        and e.deleted_at is null)
     and coalesce((app.clock_rules(s.profile_id) ->> 'clock_enabled')::boolean, true);

  v_att := v_att || jsonb_build_object('late', v_late);

  -- ‏4.5 מסמכי רכב: הסינון של 0174, התוקף מול התאריך בישראל. הנוסחה זו של
  -- ‏vehicle_document_status (0089): פג לפני היום, "עומד לפוג" עד ימי ההתראה
  -- של הסוג. בלי תקרה: הצי קטן, והקיר מדפדף רשימה ארוכה בעצמו.
  select coalesce(jsonb_agg(jsonb_build_object(
           'vehicle_name', d.vehicle_name,
           'plate_number', d.plate_number,
           'kind_name',    d.kind_name,
           'expires_at',   d.expires_at,
           'days_left',    d.days_left,
           'status',       d.status)
           order by d.expires_at, d.vehicle_name, d.kind_name), '[]'::jsonb)
    into v_fleet
    from (select v.name as vehicle_name, v.plate_number, k.name as kind_name,
                 doc.expires_at, (doc.expires_at - v_today) as days_left,
                 case when doc.expires_at < v_today then 'expired' else 'expiring' end as status
            from vehicle_documents doc
            join vehicle_document_kinds k on k.id = doc.kind_id
            join vehicles v on v.id = doc.vehicle_id
           where doc.deleted_at is null and v.deleted_at is null and v.status <> 'sold'
             and doc.expires_at is not null
             and (doc.expires_at < v_today or doc.expires_at <= v_today + k.alert_days)) d;

  -- ‏4.6 כסף: כלל 6. מהחודש עד היום — הליבה של הרווח הגולמי; משאר החודש —
  -- אותו ביטוי הכנסה בדיוק, על מחר עד סוף החודש.
  v_margin := app.margin_summary_core(v_month, v_today);

  select coalesce((select sum(tp.price)
                     from app.task_revenue tp
                     join app.live_tasks t on t.id = tp.task_id and t.deleted_at is null
                    where t.task_date between v_today + 1 and v_month_end), 0)
       + coalesce((select sum(ei.amount)
                     from event_income ei
                     join app.live_events e on e.id = ei.event_id and e.deleted_at is null
                    where e.event_date between v_today + 1 and v_month_end), 0)
    into v_forecast;

  -- ── 0241: לו״ז המחסן — הכנה והחזרה, אותן שורות של app.warehouse_rows ────────
  -- הליבה בלי השער של המשתמש: מסך הקיר אינו משתמש, והדלת שלו היא הסוד.
  select coalesce(jsonb_agg(jsonb_build_object(
           'event_id',        w.event_id,
           'kind',            w.kind,
           'date',            w.task_date,
           'start_at',        case when w.start_time is not null
                                   then (w.task_date + w.start_time) at time zone 'Asia/Jerusalem' end,
           'end_at',          case when w.start_time is not null and w.duration_hours > 0
                                   then ((w.task_date + w.start_time) at time zone 'Asia/Jerusalem')
                                        + make_interval(mins => round(w.duration_hours * 60)::int) end,
           'customer_name',   w.customer_name,
           'customer_color',  w.customer_color,
           'event_number',    w.event_number,
           'end_client_name', w.end_client_name,
           'event_date',      w.event_date,
           'final_approved',  w.final_approved,
           'event_ready',     w.event_ready,
           'checked',         w.checked)
           order by w.task_date, w.start_time nulls last, w.kind, w.event_number), '[]'::jsonb)
    into v_wh
    from app.warehouse_rows_core(v_today, v_today + v_days, null) w;

  -- ── 0241: משימות ניהול (0227) — מונים באותן הגדרות של סיכום הבוקר (0232) ──
  select jsonb_build_object(
           'open',      count(*) filter (where m.status = 'open'),
           'overdue',   count(*) filter (where m.status = 'open' and m.due_at < v_now),
           'due_today', count(*) filter (where m.status = 'open' and m.due_at >= v_now
                                           and m.due_at < app.mission_day_end(v_today)),
           'done_week', count(*) filter (where m.status = 'done'
                                           and m.done_at >= v_week::timestamp at time zone 'Asia/Jerusalem'
                                           and m.done_at <= v_now),
           'done_week_on_time', count(*) filter (where m.status = 'done'
                                           and m.done_at >= v_week::timestamp at time zone 'Asia/Jerusalem'
                                           and m.done_at <= v_now and m.done_at <= m.due_at),
           'items', coalesce((
              select jsonb_agg(jsonb_build_object(
                       'id', x.id, 'title', x.title, 'owner_name', o.full_name,
                       'due_at', x.due_at, 'priority', x.priority, 'recurrence', x.recurrence,
                       'postpone_count', x.postpone_count,
                       'steps_total', (select count(*) from admin_mission_steps s
                                        where s.mission_id = x.id and s.deleted_at is null),
                       'steps_done',  (select count(*) from admin_mission_steps s
                                        where s.mission_id = x.id and s.deleted_at is null
                                          and s.done_at is not null))
                       order by x.due_at, x.priority, x.title)
                from (select * from admin_missions
                       where deleted_at is null and status = 'open'
                       order by due_at, priority, title limit 20) x
                join profiles o on o.id = x.owner_id), '[]'::jsonb),
           'recent_done', coalesce((
              select jsonb_agg(jsonb_build_object(
                       'id', x.id, 'title', x.title, 'owner_name', o.full_name,
                       'due_at', x.due_at, 'done_at', x.done_at)
                       order by x.done_at desc)
                from (select * from admin_missions
                       where deleted_at is null and status = 'done'
                         and done_at > v_now - interval '7 days' and done_at <= v_now
                       order by done_at desc limit 8) x
                join profiles o on o.id = x.owner_id), '[]'::jsonb))
    into v_missions
    from admin_missions m
   where m.deleted_at is null;

  -- ── 0241: התחילו באיחור — ההחתמה הראשונה היום מול תחילת המשמרת המתוכננת ──
  -- אותה מדידה של 0084 (`clock_in_at - shift_start` בדקות), עם סף של 5 דקות
  -- כדי שהמסך לא יתמלא בדקה-שתיים. משמרת מתוכננת אחת לאדם — הראשונה ביום.
  with first_in as (
    select e.profile_id, min(e.clock_in_at) as clock_in_at
      from attendance_entries e
     where e.work_date = v_today
       and e.deleted_at is null
       and e.status <> 'rejected'
       and e.clock_in_at <= v_now
     group by e.profile_id
  ),
  planned as (
    select distinct on (s.profile_id)
           s.profile_id, s.shift_start, concat_ws(' · ', c.name, s.label) as label
      from app.planned_shifts_many(array(select profile_id from first_in), v_today, v_today) s
      left join app.customer_identities c on c.id = s.customer_id
     order by s.profile_id, s.shift_start
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'profile_id',    f.profile_id,
           'name',          p.full_name,
           'planned_start', pl.shift_start,
           'clock_in_at',   f.clock_in_at,
           'minutes_late',  x.mins,
           'task_label',    pl.label)
           order by x.mins desc, p.full_name), '[]'::jsonb)
    into v_late_in
    from first_in f
    join planned pl on pl.profile_id = f.profile_id
    join profiles p on p.id = f.profile_id
    cross join lateral (select round(extract(epoch from (f.clock_in_at - pl.shift_start)) / 60)::int as mins) x
   where x.mins >= 5;

  -- ── 0241: סיימו לאחרונה — יציאה בארבע השעות האחרונות, מי שלא חזר למשמרת ──
  select coalesce(jsonb_agg(jsonb_build_object(
           'profile_id',   z.profile_id,
           'name',         z.full_name,
           'clock_in_at',  z.clock_in_at,
           'clock_out_at', z.clock_out_at,
           'hours',        round(extract(epoch from (z.clock_out_at - z.clock_in_at)) / 3600.0, 2),
           'work_site',    z.work_site)
           order by z.clock_out_at desc, z.full_name), '[]'::jsonb)
    into v_ended
    from (select distinct on (e.profile_id)
                 e.profile_id, p.full_name, e.clock_in_at, e.clock_out_at, e.work_site
            from attendance_entries e
            join profiles p on p.id = e.profile_id
           where e.deleted_at is null
             and e.status <> 'rejected'
             and e.clock_out_at is not null
             and e.clock_out_at <= v_now
             and e.clock_out_at > v_now - interval '4 hours'
             and not exists (select 1 from attendance_entries o
                              where o.profile_id = e.profile_id
                                and o.deleted_at is null
                                and o.status <> 'rejected'
                                and o.clock_out_at is null
                                and o.clock_in_at <= v_now
                                and o.clock_in_at > v_now - v_auto)
           order by e.profile_id, e.clock_out_at desc
           limit 10) z;

  -- ── 0241: הרווח של הדשבורד, מתחילת החודש עד היום ─────────────────────────
  v_profit := app.profit_summary_core(v_month, v_today);

  return jsonb_build_object(
    'v',            1,
    'source',       'viperlogistics',
    'generated_at', v_now,
    'today',        v_today,
    'days',         v_days,
    'tasks',        v_tasks,
    'shifts_now',   v_shifts,
    'attendance',   v_att || jsonb_build_object('late_started', v_late_in, 'ended_recently', v_ended),
    'warehouse_tasks', v_wh,
    'missions',     v_missions,
    'kpis',         v_kpis || jsonb_build_object('workers_on_shift', jsonb_array_length(v_shifts)),
    'alerts', jsonb_build_object(
      'understaffed',        v_under,
      'unpublished',         v_unpub,
      'fleet_documents',     v_fleet,
      'attendance_pending',  (select count(*) from attendance_entries
                               where status = 'pending' and deleted_at is null),
      'correction_requests', (select count(*) from attendance_entries
                               where req_at is not null and deleted_at is null),
      -- ‏arco_outbound אינה מחזיקה מתי נכשלה, רק מתי נכנסה לתור (0184/0195)
      'integration_failures', jsonb_build_object(
        'viperflow', (select count(*) from viperflow_deliveries
                       where status = 'failed'
                         and received_at > v_now - interval '24 hours' and received_at <= v_now),
        'arco_in',   (select count(*) from arco_deliveries
                       where status = 'failed'
                         and received_at > v_now - interval '24 hours' and received_at <= v_now),
        'arco_out',  (select count(*) from arco_outbound
                       where status = 'failed'
                         and created_at > v_now - interval '24 hours' and created_at <= v_now))),
    'finance', jsonb_build_object(
      'month_start',            v_month,
      'month_end',              v_month_end,
      'revenue_mtd',            (v_margin ->> 'revenue')::numeric,
      'contractor_mtd',         (v_margin ->> 'contractor')::numeric,
      'payroll_mtd',            (v_margin ->> 'payroll')::numeric,
      'gross_mtd',              (v_margin ->> 'gross')::numeric,
      -- אחוזים (0..100), כפי ש-margin_summary מחזירה; null כשאין הכנסה
      'gross_pct',              (v_margin ->> 'pct')::numeric,
      'forecast_rest_of_month', round(v_forecast, 2),
      'unrated_shifts',         coalesce((v_margin ->> 'unrated_shifts')::int, 0),
      -- ‏0241: "רווח" של הדשבורד (finance.profit_summary) מתחילת החודש עד היום — אותה פונקציה
      'profit', jsonb_build_object(
        'revenue',               (v_profit ->> 'revenue')::numeric,
        'contractor',            (v_profit ->> 'contractor')::numeric,
        'payroll',               (v_profit ->> 'payroll')::numeric,
        'employer_pct',          (v_profit ->> 'employer_pct')::numeric,
        'payroll_with_employer', (v_profit ->> 'payroll_with_employer')::numeric,
        'profit',                (v_profit ->> 'profit')::numeric,
        'pct',                   (v_profit ->> 'pct')::numeric)));
end $$;

comment on function app.wall_snapshot_at(timestamptz, int) is
  'התמונה של מסך הקיר ל"עכשיו" נתון (0202/0203): משימות שטח עם הצוות, לו״ז המחסן, '
  'משימות ניהול, במשמרת עכשיו, שעות, לא החתימו / התחילו באיחור / סיימו לאחרונה, '
  'מונים, התראות, כספי החודש ורווח הדשבורד (0241). נשללת מכולם — הדלת היחידה היא '
  'public.wall_snapshot מאחורי הסוד.';

revoke all on function app.wall_snapshot_at(timestamptz, int) from public, anon, authenticated, service_role;
