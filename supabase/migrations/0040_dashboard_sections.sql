-- 0040: dashboard_sections — הנתונים של הקטלוג
--
-- הדשבורד עומד להחזיק עשרות ווידג׳טים, ולא כולם מוצגים בבת אחת. RPC שמחשב את
-- הכול לכולם היה משלם על ווידג׳טים שאיש לא בחר, ושאילתה פר-ווידג׳ט הייתה
-- ארבעים הלוך-חזור בטעינה. לכן הלקוח שולח את רשימת הסקשנים שהווידג׳טים
-- הגלויים שלו צריכים, והפונקציה מחשבת בדיוק אותם.
--
-- `dashboard_stats` **אינה משתנה**. היא מכסה את הווידג׳טים הקיימים, היא נקובה
-- בשמה בשתי מערכי ההקשחה (0008, 0012), והיא נקראת פעמיים בכל טעינה — פעם
-- לטווח ופעם לתקופה הקודמת. הרחבתה בפרמטר הייתה יוצרת עומס-יתר על חתימה חיה,
-- וזו בדיוק הסיבה ש-0033 בחרה ב-RPC נפרד ל-`attendance_set_bonus`.
--
-- שלוש מוסכמות שנשמרות בכל ענף:
--   • `security invoker` — ה-RLS מצמצמת כל ספירה, ולכן לקוח מקבל את המספרים
--     שלו מאותה שאילתה בלי שהיא תנקוב בלקוח כלשהו. החריג היחיד הוא שכר, שחייב
--     לקרוא `worker_pay_settings`, והוא מואצל לעוזר definer שדורש מפתח בעצמו.
--   • `0` אומר "אין", `null` אומר "לא בשבילך". סקשן שאין לקורא מפתח עליו חוזר
--     null, והמסך משמיט את הווידג׳ט במקום לצייר אפס.
--   • מפתח סקשן שאינו מוכר **מדולג ולא זורק**, כדי ששרת ישן מול לקוח חדש
--     יתדרדר לפחות כרטיסים ולא לשגיאה.

-- ===== 1. שכר ==============================================================
-- הסיכום נשען על `app.attendance_pay_rows` מ-0038 ולא מחשב כלום בעצמו: הצבר
-- השבועי תלוי-סדר, ומימוש שני היה מתפצל מהדוח בשקט.

create or replace function app.payroll_summary(p_from date, p_to date)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v jsonb;
begin
  perform app.require('dashboard.payroll');

  with approved as (
    select * from app.attendance_pay_rows(p_from, p_to, null, null, false, array['approved'], 'all')
  ),
  pending as (
    select * from app.attendance_pay_rows(p_from, p_to, null, null, false, array['pending'], 'all')
  )
  select jsonb_build_object(
    'total',          round(coalesce(sum((a.pay ->> 'total')::numeric), 0), 2),
    'bonus',          round(coalesce(sum((a.pay ->> 'bonus')::numeric), 0), 2),
    'paid_hours',     round(coalesce(sum((a.pay ->> 'paid_hours')::numeric), 0), 2),
    'base_hours',     round(coalesce(sum((a.pay ->> 'base_hours')::numeric), 0), 2),
    'overtime_hours', round(coalesce(sum((a.pay ->> 'overtime_hours')::numeric), 0), 2),
    'actual_hours',   round(coalesce(sum(a.actual_hours), 0), 2),
    'shifts',         count(*),
    'workers',        count(distinct a.profile_id),
    -- app.attendance_calc מחזירה total = null כשאין תעריף ואין בונוס, ולכן
    -- משמרת כזו נעלמת מ-sum() בשקט ועלות השכר מדווחת נמוך מדי. המונה הזה הוא
    -- מה שמאפשר לווידג׳ט לומר "X משמרות אינן נספרות" במקום לשקר בביטחון.
    'unrated_shifts', count(*) filter (where a.pay ->> 'hourly_rate' is null),
    'pending_shifts', (select count(*) from pending),
    'pending_hours',  (select round(coalesce(sum(actual_hours), 0), 2) from pending),
    -- הצהרה על מה נספר, שהמסך מציג כהערת מקור
    'scope',          'approved_only')
  into v from approved a;

  return v;
end $$;

-- פירוק פר-עובד. מפתח נפרד: מנהל יכול לקבל את הסכום הכולל בלי לראות כמה
-- מרוויח כל אחד, וזו ההפרדה שהופכת את זה לאפשרי.
create or replace function app.payroll_by_worker(p_from date, p_to date, p_limit int default 12)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v jsonb;
begin
  perform app.require('dashboard.payroll');
  perform app.require('dashboard.all_workers');

  select coalesce(jsonb_agg(row_to_json(x)), '[]') into v from (
    select r.full_name as name,
           round(sum((r.pay ->> 'total')::numeric), 2) as total,
           round(sum(r.actual_hours), 2) as hours
      from app.attendance_pay_rows(p_from, p_to, null, null, false, array['approved'], 'all') r
     group by r.profile_id, r.full_name
     having sum((r.pay ->> 'total')::numeric) is not null
     order by 2 desc nulls last
     limit greatest(1, least(coalesce(p_limit, 12), 50))) x;
  return v;
end $$;

create or replace function app.payroll_trend(p_from date, p_to date, p_bucket text default 'week')
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v jsonb; v_b text := case when p_bucket in ('day','week','month') then p_bucket else 'week' end;
begin
  perform app.require('dashboard.payroll');
  select coalesce(jsonb_agg(row_to_json(x) order by x.bucket), '[]') into v from (
    select date_trunc(v_b, r.work_date)::date as bucket,
           round(sum((r.pay ->> 'total')::numeric), 2) as total,
           round(sum(r.actual_hours), 2) as hours
      from app.attendance_pay_rows(p_from, p_to, null, null, false, array['approved'], 'all') r
     group by 1) x;
  return v;
end $$;

-- ===== 2. הקצאת שכר למשימות ================================================
-- הכנסה תלויה במשימה, שכר תלוי במשמרת, והגשר היחיד הוא
-- `attendance_entries.task_ids`. ההקצאה היא **הערכה**, והיא מוצהרת ככזו:
--   • משמרת בלי task_ids אינה ניתנת להקצאה ונופלת לדלי `unallocated`. היא
--     לעולם לא מתפזרת בשקט בין לקוחות — משמרות מחסן ודיווחים ידניים חיים שם.
--   • החלוקה היא לפי `hours_count` של המשימה, ובהיעדר שעות — שווה בשווה.
--   • משימה שנמחקה רכות עדיין צורכת את חלקה, והשארית הולכת ל-unallocated.
--     הקטנת המכנה הייתה מנפחת את העלות של הלקוחות ששרדו.
create or replace function app.payroll_task_alloc(p_from date, p_to date)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v jsonb;
begin
  perform app.require('dashboard.payroll');

  with rows as (
    select r.id, (r.pay ->> 'total')::numeric as total, r.task_ids
      from app.attendance_pay_rows(p_from, p_to, null, null, false, array['approved'], 'all') r
     where (r.pay ->> 'total') is not null
  ),
  -- כל המשימות שהמשמרת נוקבת בהן, כולל כאלה שנמחקו: הן חלק מהמכנה
  spread as (
    select w.id, w.total, t.id as task_id, t.customer_id, t.deleted_at,
           coalesce(t.hours_count, 0) as hours,
           cardinality(w.task_ids) as denom
      from rows w
      cross join lateral unnest(w.task_ids) as u(task_id)
      left join tasks t on t.id = u.task_id
     where cardinality(w.task_ids) > 0
  ),
  weighted as (
    select s.*,
           sum(s.hours) over (partition by s.id) as hours_total
      from spread s
  ),
  alloc as (
    select w.customer_id, w.deleted_at, w.task_id,
           case when w.hours_total > 0 then w.total * (w.hours / w.hours_total)
                else w.total / w.denom end as amount
      from weighted w
  )
  select jsonb_build_object(
    'by_customer', (select coalesce(jsonb_agg(row_to_json(x)), '[]') from (
        select c.name, c.color, round(sum(a.amount), 2) as payroll
          from alloc a join customers c on c.id = a.customer_id
         where a.deleted_at is null and a.customer_id is not null
         group by c.name, c.color order by 3 desc) x),
    -- שלושה מקורות לאותו דלי, וכולם גלויים: משמרת בלי משימות, משימה שנמחקה,
    -- ומשימה עצמאית בלי לקוח
    'unallocated', round(
        coalesce((select sum(a.amount) from alloc a
                   where a.deleted_at is not null or a.customer_id is null or a.task_id is null), 0)
      + coalesce((select sum(w.total) from rows w where cardinality(w.task_ids) = 0), 0), 2),
    'allocated', round(coalesce((select sum(a.amount) from alloc a
                                  where a.deleted_at is null and a.customer_id is not null), 0), 2))
  into v;

  return v;
end $$;

-- ===== 3. הדיספצ׳ר =========================================================

create or replace function dashboard_sections(
  p_sections text[],
  p_from     date,
  p_to       date,
  p_opts     jsonb default '{}'::jsonb)
returns jsonb language plpgsql stable security invoker set search_path = public as $$
declare
  v_key    text;
  v_out    jsonb := '{}'::jsonb;
  v_bucket text := case when p_opts ->> 'bucket' in ('day','week','month')
                        then p_opts ->> 'bucket' else 'week' end;
  v_limit  int  := greatest(1, least(coalesce((p_opts ->> 'limit')::int, 12), 50));
  v_val    jsonb;
  -- רווח דורש את ארבעת המפתחות יחד: הוא חיסור, ומי שרואה אותו יכול לגזור
  -- ממנו את הרכיבים. אין טעם להעמיד פנים שאפשר להראות רווח בלי להראות עלות.
  v_margin boolean := app.has_all(array['dashboard.margin','dashboard.payroll',
                                        'dashboard.contractor_cost','pricing.revenue']);
  -- ...ובתנאי שהקורא רואה את כל המשימות. עלות השכר היא של כל החברה ואינה
  -- ניתנת לצמצום לפי היקף נתונים, ולכן מי שרואה חלק מהמשימות היה מקבל
  -- "ההכנסות שלי פחות השכר של כולם". מספר שחסר עדיף על מספר שגוי.
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
  if coalesce(array_length(p_sections, 1), 0) > 40 then
    raise exception 'יותר מדי סקשנים בבקשה אחת' using errcode = '22023';
  end if;

  foreach v_key in array coalesce(p_sections, '{}'::text[]) loop
    v_val := null;

    -- ── כספים: הכנסות ──────────────────────────────────────────────────────
    if v_key = 'revenue.trend' and app.has('pricing.revenue') then
      select coalesce(jsonb_agg(row_to_json(x) order by x.bucket), '[]') into v_val from (
        select date_trunc(v_bucket, t.task_date)::date as bucket,
               round(sum(tp.price), 2) as total
          from task_pricing tp
          join tasks t on t.id = tp.task_id and t.deleted_at is null
         where t.task_date between p_from and p_to
         group by 1) x;

    elsif v_key = 'revenue.forecast' and app.has('pricing.revenue') then
      select jsonb_build_object(
        'total', round(coalesce(sum(tp.price), 0), 2),
        'tasks', count(*),
        'by_month', (select coalesce(jsonb_agg(row_to_json(y) order by y.bucket), '[]') from (
            select date_trunc('month', t2.task_date)::date as bucket,
                   round(sum(tp2.price), 2) as total
              from task_pricing tp2
              join tasks t2 on t2.id = tp2.task_id and t2.deleted_at is null
             where t2.task_date > current_date
             group by 1) y))
        into v_val
        from task_pricing tp
        join tasks t on t.id = tp.task_id and t.deleted_at is null
       where t.task_date > current_date;

    -- ── כספים: איכות התמחור ────────────────────────────────────────────────
    -- הדליפה השקטה של המערכת: משימה בלי שורת תמחור אינה מופיעה בשום סכום,
    -- ולכן "הכנסות בטווח" נראה סביר בדיוק כשהוא חסר.
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

    -- ── כספים: קבלנים ──────────────────────────────────────────────────────
    elsif v_key = 'cost.contractor' and app.has('dashboard.contractor_cost') then
      select jsonb_build_object(
        'expected',   round(coalesce(sum(tct.price), 0), 2),
        'paid',       round(coalesce(sum(coalesce(tct.paid_amount, tct.price))
                              filter (where tct.paid_at is not null), 0), 2),
        'unpaid',     round(coalesce(sum(tct.price) filter (where tct.paid_at is null), 0), 2),
        -- `price` הוא not null default 0, ולכן סכום לבדו אינו מבחין בין
        -- "לא סוכם מחיר" ל-"סוכם אפס". הספירה היא מה שמאפשר להבדיל.
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

    -- ── כספים: שכר ─────────────────────────────────────────────────────────
    elsif v_key = 'cost.payroll' and app.has('dashboard.payroll') then
      v_val := app.payroll_summary(p_from, p_to);

    elsif v_key = 'cost.payroll_by_worker' and app.has('dashboard.payroll')
          and app.has('dashboard.all_workers') then
      v_val := app.payroll_by_worker(p_from, p_to, v_limit);

    elsif v_key = 'cost.payroll_trend' and app.has('dashboard.payroll') then
      v_val := app.payroll_trend(p_from, p_to, v_bucket);

    -- ── כספים: רווח גולמי ──────────────────────────────────────────────────
    -- ההכנסות ועלות הקבלנים נקראות כאן, בהקשר invoker, ולכן ה-RLS חלה עליהן.
    -- רק השכר מגיע מעוזר definer, כי הוא חייב לקרוא worker_pay_settings.
    elsif v_key = 'margin.summary' and v_margin and not v_scoped then
      declare
        v_rev  numeric;
        v_con  numeric;
        v_pay  jsonb := app.payroll_summary(p_from, p_to);
      begin
        select coalesce(sum(tp.price), 0) into v_rev
          from task_pricing tp join tasks t on t.id = tp.task_id and t.deleted_at is null
         where t.task_date between p_from and p_to;
        select coalesce(sum(tct.price), 0) into v_con
          from task_contractor_terms tct join tasks t on t.id = tct.task_id and t.deleted_at is null
         where t.task_date between p_from and p_to;

        v_val := jsonb_build_object(
          'revenue',   round(v_rev, 2),
          'contractor', round(v_con, 2),
          'payroll',   (v_pay -> 'total'),
          'gross',     round(v_rev - v_con - coalesce((v_pay ->> 'total')::numeric, 0), 2),
          'pct',       case when v_rev > 0
                            then round((v_rev - v_con - coalesce((v_pay ->> 'total')::numeric, 0))
                                       / v_rev * 100, 1) end,
          -- מה שהמסך חייב לומר יחד עם המספר
          'unrated_shifts', (v_pay -> 'unrated_shifts'),
          'excludes_overhead', true);
      end;

    elsif v_key = 'margin.trend' and v_margin and not v_scoped then
      select coalesce(jsonb_agg(row_to_json(x) order by x.bucket), '[]') into v_val from (
        select b.bucket,
               round(coalesce(b.revenue, 0), 2)    as revenue,
               round(coalesce(b.contractor, 0), 2) as contractor,
               round(coalesce(p.total, 0), 2)      as payroll,
               round(coalesce(b.revenue, 0) - coalesce(b.contractor, 0) - coalesce(p.total, 0), 2) as gross
          from (
            select date_trunc(v_bucket, t.task_date)::date as bucket,
                   sum(tp.price) as revenue,
                   sum(tct.price) as contractor
              from tasks t
              left join task_pricing tp on tp.task_id = t.id
              left join task_contractor_terms tct on tct.task_id = t.id
             where t.deleted_at is null and t.task_date between p_from and p_to
             group by 1) b
          full join (
            select (e ->> 'bucket')::date as bucket, (e ->> 'total')::numeric as total
              from jsonb_array_elements(app.payroll_trend(p_from, p_to, v_bucket)) e) p
            on p.bucket = b.bucket) x;

    elsif v_key = 'margin.by_customer' and v_margin and not v_scoped and app.has('customers.view') then
      declare v_alloc jsonb := app.payroll_task_alloc(p_from, p_to);
      begin
        select jsonb_build_object(
          'rows', (select coalesce(jsonb_agg(row_to_json(x) order by x.revenue desc), '[]') from (
              select c.name, c.color,
                     round(coalesce(sum(tp.price), 0), 2)  as revenue,
                     round(coalesce(sum(tct.price), 0), 2) as contractor,
                     round(coalesce((select (a ->> 'payroll')::numeric
                                       from jsonb_array_elements(v_alloc -> 'by_customer') a
                                      where a ->> 'name' = c.name), 0), 2) as payroll
                from tasks t
                join customers c on c.id = t.customer_id
                left join task_pricing tp on tp.task_id = t.id
                left join task_contractor_terms tct on tct.task_id = t.id
               where t.deleted_at is null and t.task_date between p_from and p_to
               group by c.name, c.color) x),
          'unallocated', (v_alloc -> 'unallocated'),
          'allocated',   (v_alloc -> 'allocated'),
          -- ההקצאה היא הערכה; המסך מסרב להציג אחוזים כשהחלק הלא-משויך גדול מדי
          'estimated', true)
          into v_val;
      end;

    -- ── תפעול ──────────────────────────────────────────────────────────────
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

    -- משימה שנדרשים לה עובדים ואין לה מספיק. `worker_count > 0` מוציא משימות
    -- שלא נדרש להן צוות בכלל, אחרת כל משימת פיקוח הייתה מדווחת כתת-איוש.
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

    -- truck_ids ולא truck_id: 0035 הפכה משימה לרב-משאיתית, והעמודה הישנה
    -- מחזיקה רק את הראשונה מהן.
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

    -- ── לקוחות ─────────────────────────────────────────────────────────────
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
                    then round(coalesce(sum(distinct_price.price), 0), 2) end as revenue,
               max(e.event_date) as last_event
          from customers c
          left join events e on e.customer_id = c.id and e.deleted_at is null
               and e.event_date between p_from and p_to
          left join tasks t on t.customer_id = c.id and t.deleted_at is null
               and t.task_date between p_from and p_to
          left join lateral (
            select tp.price from task_pricing tp where tp.task_id = t.id) distinct_price on true
         where c.deleted_at is null
         group by c.name, c.color
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

    -- ── כוח אדם ────────────────────────────────────────────────────────────
    -- שעות בלבד, בלי כסף: זו בדיוק ההפרדה שמאפשרת לרכז משמרות לראות עומס בלי
    -- לראות שכר, ואותה הפרדה כבר קיימת ב-attendance_report.
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

    -- מפתח שאינו מוכר, או מוכר ואין עליו מפתח הרשאה — שניהם מגיעים לכאן עם
    -- v_val = null, ושניהם נכתבים כ-null. המסך משמיט את שניהם באותה דרך.
    v_out := v_out || jsonb_build_object(v_key, v_val);
  end loop;

  return v_out;
end $$;

-- RPC חדש אינו בטוח כברירת מחדל: 0008 ו-0012 מבטלים execute מ-anon ומ-public
-- לפי רשימת חתימות מפורשת, וזו מצטרפת אליה.
revoke execute on function public.dashboard_sections(text[], date, date, jsonb) from anon, public;

-- ===== 4. אינדקסים =========================================================
-- הסקשנים החדשים סורקים לפי תאריך ולפי סטטוס תשלום. שלושת אלה הם מה שחסר.
create index if not exists tasks_date_live_idx on tasks (task_date) where deleted_at is null;
create index if not exists events_date_live_idx on events (event_date) where deleted_at is null;
create index if not exists tct_unpaid_idx on task_contractor_terms (paid_at) where paid_at is null;
create index if not exists attendance_date_status_idx
  on attendance_entries (work_date, status) where deleted_at is null;
