-- 0143: הדשבורד של הלקוח סופר את החודשים שלו
--
-- ללקוח יש היום כרטיס אחד שמדבר עליו — "הוצאה על אירועים" (0074) — והוא עונה
-- על הטווח שנבחר ותו לא. שתי שאלות שנשאלו נשארו בלי מסך:
--
--   • כמה אירועים היו לי החודש, וכמה אני חייב לוייפר.
--   • כמה אירועים, מה הסכום הכולל, וכמה עמלה מגיעה לי.
--
-- שתיהן אותה שאלה עם קונפיגורציה אחרת, ולכן הן סקשן אחד ולא שניים.
--
-- ‏**הדגל, לא השם.** ‏0120 קבעה את המוסכמה כשהיא חיברה את "בוצע ע״י" לארקו:
-- הלוגיקה בודקת עמודה על הלקוח, וההצמדה ללקוח מסוים היא עדכון נתונים
-- חד-פעמי. כאן זה חוזר מילה במילה — `commission_pct` הוא מה שנשאל בכל מקום,
-- ולקוח עמלה נוסף בעתיד לא ידרוש שורת קוד.


-- ===== 1. שתי העמודות ======================================================
--
-- ‏`commission_pct is null` פירושו "אין עמלה", ולא "אפס אחוז". ההבדל אינו
-- סמנטי: אפס היה מציג ללקוח כרטיס עמלה שכתוב בו 0 ₪ בכל חודש, ו-null מסיר
-- את הכרטיס ואת העמודה לגמרי. הסקשן מחזיר null באותה משמעות בדיוק, וזה אותו
-- חוזה שכל ווידג׳ט בדשבורד כבר מקיים.
--
-- הסף הוא עמודה ולא קבוע: "מעל 2,000" הוא תנאי מסחרי של לקוח אחד, ולקוח
-- שיסכם על 5,000 ישנה שורה במסד ולא מיגרציה.

alter table customers
  add column if not exists commission_pct numeric(5,2)
    check (commission_pct >= 0 and commission_pct <= 100),
  add column if not exists commission_min_event numeric(12,2) not null default 0
    check (commission_min_event >= 0);

comment on column customers.commission_pct is
  'אחוז העמלה שמגיע ללקוח על אירוע שחצה את הסף. null = אין עמלה, והכרטיס אינו מוצג לו כלל (0143).';
comment on column customers.commission_min_event is
  'הסכום שאירוע צריך לעבור (ממש מעל) כדי לזכות בעמלה. 0 = כל אירוע (0143).';

-- נתון, לא קוד — כמו 0120. אין לקוח כזה (אשכול בדיקות) ⇒ אפס שורות.
update customers set commission_pct = 10, commission_min_event = 2000
 where name ilike '%קיסר%' and deleted_at is null;


-- ===== 2. המפתח ============================================================
--
-- בלי `implied_by`, מאותו נימוק ש-0074 §3 מנסח על `finance.customer_spend`:
-- מפתח שמשמעותו תלויה במי שואל צריך להינתן ולא להיגזר. "האירועים שלי" בידי
-- איש משרד היה מציג את כל החברה תחת כותרת שאומרת "שלי".
--
-- ומוענק ל-`customer_manager` בלבד. ‏`customer_viewer` הוא צפייה בלי כסף —
-- ‏0074 §2 שוללת ממנו את כל המפתחות הכספיים, ו-`supabase/tests/15` טוענת
-- זאת במפורש. עמלה לצופה הייתה סותרת את השורה הזאת.

select app.register_permission('finance.customer_monthly', 'finance',
       'צפייה בסיכום החודשי של האירועים שלי',
       p_description => 'כמות אירועים, סכום ועמלה — חודש בחודשו, מהצד של הלקוח',
       p_category => 'access',
       p_applies_to => array['customer_user']::user_kind[]);

insert into role_permissions (role_id, permission_key, allowed)
select r.id, 'finance.customer_monthly', true
  from permission_roles r where r.key = 'customer_manager'
on conflict (role_id, permission_key) do update set allowed = true;


-- ===== 3. הסקשן ============================================================
--
-- הגוף מועתק מ-0114 כלשונו, עם שני `declare` וענף אחד. זו המוסכמה של הקובץ
-- הזה — ‏0041 → 0069 → 0074 → 0090 → 0091 → 0114 עשו בדיוק את זה — ולכן מי
-- שיוסיף סקשן בעתיד ימשיך מכאן.
--
-- `security invoker` כמו קודמיו, ולכן RLS הוא שתוחם את השורות ללקוח הקורא;
-- הפונקציה אינה מסננת לפי `customer_id` בעצמה.

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
  /* ‏0143. לא `v_pct`: הוא כבר תפוס בידי ענפי עלות המעביד, ושימוש חוזר
     בו כאן היה דורסן זה את זה בבקשה שמזמינה את שניהם. */
  v_com_pct numeric;
  v_com_min numeric;
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
  -- 51 ולא 50: `customer.monthly` (0143) הצטרף לרשימה.
  if coalesce(array_length(p_sections, 1), 0) > 51 then
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
          left join app.live_events e on e.id = ei.event_id and e.deleted_at is null
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
            join app.live_events e on e.id = ei.event_id and e.deleted_at is null
                 and e.event_date between p_from and p_to
            join customers c on c.id = e.customer_id
            join income_categories ic on ic.id = ei.category_id
           group by ic.name, c.name, ic.color
          union all
          select 'צוות ' || c.name, c.color, sum(tp.price)
            from app.task_revenue tp
            join app.live_tasks t on t.id = tp.task_id and t.deleted_at is null
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

    -- ── הכנסות ללקוח: חלקו של הלקוח, לפי ה-snapshot שנשמר על כל אירוע ─────
    elsif v_key = 'finance.client_share' and app.has('finance.income_view') then
      select jsonb_build_object(
        'total', round(coalesce(sum(ei.amount * (100 - ei.viper_share_pct) / 100), 0), 2),
        'rows', case when app.has('customers.view') then
          (select coalesce(jsonb_agg(row_to_json(y)), '[]') from (
             select c.name, c.color,
                    round(sum(ei2.amount * (100 - ei2.viper_share_pct) / 100), 2) as total
               from event_income ei2
               join app.live_events e2 on e2.id = ei2.event_id and e2.deleted_at is null
                    and e2.event_date between p_from and p_to
               join customers c on c.id = e2.customer_id
              group by c.name, c.color
             having sum(ei2.amount * (100 - ei2.viper_share_pct) / 100) <> 0
              order by 3 desc limit v_limit) y)
          else null end)
        into v_val
        from event_income ei
        join app.live_events e on e.id = ei.event_id and e.deleted_at is null
       where e.event_date between p_from and p_to;

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
                   -- ‏0091: עובדי הקבלן נספרים כמאיישים, כמו אנשי המשרד. בלי זה
                   -- משימה שהקבלן איישָׁ נותרה "חסרה" (task_contractor_workers).
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

    elsif v_key = 'hr.headcount' and app.has('dashboard.all_workers') then
      select jsonb_build_object(
        'active', count(*) filter (where p.is_active),
        'staff',  count(*) filter (where p.is_active and p.user_kind = 'staff'))
        into v_val
        from profiles p where p.deleted_at is null;

    /* ההוצאה של הלקוח: אותו `task_pricing.price` שהוצג לו קודם כ"הכנסות".
       `by_event` ולא `by_customer` — ללקוח יש לקוח אחד, הוא עצמו, ומה שהוא
       רוצה לדעת הוא על איזה אירוע הלך הכסף. `end_client_name` הוא איך הוא
       מזהה אירוע; מספר האירוע הוא הנפילה כשאין. */
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
    /* ‏0143: מה שהלקוח שואל על עצמו — כמה אירועים, כמה כסף, וכמה עמלה.

       ארבע הכרעות, וכל אחת מהן נראית כמו באג למי שיקרא בלי ההסבר:

       • **הסכום נבנה מ-`app.task_revenue` בלבד, ולא מ-`event_income`.**
         ל-`event_income` אין ענף `customer_user` באף פוליסה (0068 §6),
         והפונקציה הזאת היא `security invoker` — כלומר הטבלה הייתה חוזרת
         **ריקה בשקט**, והלקוח היה מקבל מספר אחר מזה שהמשרד רואה על אותו
         אירוע, בלי שגיאה ובלי שורה ביומן. זה גם המספר שהוא כבר רואה
         ב"הוצאה על אירועים" (0074), ולכן שני הכרטיסים אינם סותרים זה את זה.

       • **סכום האירוע נמדד על כל משימותיו, ולא על אלה שנפלו בטווח.** אירוע
         שנחתך בקצה הטווח היה יורד מתחת לסף העמלה מסיבה טכנית, ומאבד ללקוח
         כסף בגלל בורר תאריכים.

       • **הענף מותנה גם ב-`app.customer_id()`.** ‏`app.has` מחזיר `true`
         לאדמין בהגדרה, ובלי התנאי הזה הכרטיס "האירועים שלי" היה מציג לו את
         כל החברה. (זו התולעת שקיימת ב-`spend.summary` מ-0074, ואין להעתיק
         אותה הלאה.)

       • **הסף חמור.** "גבוה מ-2,000" פירושו ש-2,000 בדיוק אינם מזכים, ולכן
         `total <= v_com_min` ⇒ 0. והעיגול הוא **פר אירוע** ואז סכימה, כדי
         שהמספר החודשי יהיה סך מה שכל אירוע באמת מזכה בו.

       `months` הוא חלון של שנים־עשר חודשים המסתיים בחודש של `p_to`, ובאיחוד
       עם הטווח שנבחר. הוא אינו נחתך ב-`p_from` במכוון: הלקוח נעול על החודש
       הנוכחי (0144), וטבלה חודשית שהטווח חותך אותה הייתה מציגה שורה אחת.
       יש לזה תקדים — `fleet.status` ו-`fleet.documents_expiring` אינן קוראות
       את הטווח מאותו סוג נימוק. הכרטיסים כן קוראים אותו, ולכן הם עונים על
       "החודש" והטבלה על "חודש בחודשו".

       ‏`date_trunc('month', …)` ולא `v_bucket`: הדרישה היא לחודש. */
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
                    else round(ev.total * v_com_pct / 100, 2) end as commission
          from ev
      )
      select jsonb_build_object(
        'events',     (select count(*) from ec where event_date between p_from and p_to),
        'total',      (select round(coalesce(sum(total), 0), 2)
                         from ec where event_date between p_from and p_to),
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
              from ec group by month) m))
        into v_val;

    /* צי הרכב (0089). שני הסקשנים אינם קוראים את p_from/p_to במכוון: תוקף
       מסמך הוא שאלה על היום ועל מה שאחריו, ולא על הטווח שנבחר בראש הדשבורד.
       הווידג׳טים מוצהרים בהתאם, ראו fleetWidgets.tsx. */
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



-- ‏create or replace משמר את ה-ACL הקיים (ה-revoke/grant של 0044, 0070, 0087)
-- — אין מה לחזור עליו כאן.
