-- 0070: רווחיות פר-משימה — "כמה חייבתי ללקוח, וכמה זה עלה לי בפועל"
--
-- המערכת מודדת היטב שני צדדים ולא מחברת ביניהם ברמת המשימה: ההכנסה יושבת
-- ב-`task_pricing` ומחושבת **מהתכנון** (`worker_count` × `hours_count`),
-- והעלות נמדדת **מהבפועל** — השעות שהוחתמו. הרווח היחיד שהמערכת מציגה הוא
-- פר-לקוח (0059). הקובץ הזה מוריד אותו לרזולוציה של משימה.
--
-- ההקצאה עצמה כבר קיימת: `app.payroll_task_alloc` (0041) מפזרת את שכר המשמרת
-- בין המשימות שבה, משוקלל לפי `hours_count`, ומסכמת ל-`by_customer` לפני
-- ההחזרה. §1 מחלץ את החישוב לעוזר טיפוסי ומשאיר את הקוראים הקיימים בפלט זהה;
-- §2 כותב את הקורא מחדש מעליו. **אין כאן חישוב שכר שני** — זו אותה תזה של
-- 0039 ו-0044: מימוש שני מתיישן.
--
-- שלוש הכרעות שראוי לנמק, כי כל אחת מהן נראית כמו השמטה:
--
-- * **אין מפתח הרשאה חדש ואין `register_module`.** הנתון הוא אותו נתון של
--   `margin.*` בגרנולריות אחרת, ומפתח חדש היה דלת צדדית אליו. מה שכן נוסף
--   לצרור הוא `dashboard.all_workers` — ראו §4.
--
-- * **אין "מחיר לפי בפועל".** אפשר היה להריץ מחדש את `app.price_calc` עם
--   השעות שהוחתמו, אבל המספר הזה מעולם לא הוצג ללקוח ולא חויב, ובטבלה לצד
--   עלות אמיתית הוא נקרא ככסף. הוא גם היה ריק בדיוק במשימות המעניינות:
--   `app.recalc_task_price` (0017) מחזירה מחיר רק ללקוח ב-`pricing_mode='auto'`
--   עם מחשבון פעיל ובלי `is_manual`. במקומו כל שורה נושאת **מתוכנן מול בפועל
--   בשעות ובראשים** — עובדה, לא תרחיש נגדי.
--
-- * **`event_income` אינו נכנס לכאן.** 0069 הגדירה "הכנסה" כתמחור משימות ועוד
--   הכנסת קטגוריה **ברמת לקוח וחברה**; הכנסת קטגוריה תלויה באירוע ואין לה
--   שיוך פר-משימה. מי שיוסיף אותה כאן "כדי ליישר" יספור פעמיים.

-- ===== 1. חילוץ ההקצאה לעוזר טיפוסי ========================================
--
-- טיפוס מורכב ולא `returns table`, מאותו נימוק של `app.attendance_pay_row`
-- (0039:29): `returns table` היה יוצר פרמטרי OUT בשמות `task_id`, `amount`,
-- `customer_id` — שמות שקיימים גם כעמודות — וכל הפניה אליהם בגוף הייתה
-- דו-משמעית.
--
-- `bucket` הוא מה שמחליף את שלושת התנאים המפוזרים של 0041:
--   'task'    — המשימה קיימת. נושאת `customer_id` ו-`task_deleted`.
--   'missing' — ‏`task_ids` נקב במזהה שאין לו שורה ב-`tasks`. שומרים את
--               המזהה הגולמי כדי שהשורה לא תתחזה למשמרת בלי משימות.
--   'none'    — משמרת בלי `task_ids` כלל. שורה סינתטית אחת, ולא קריאה שנייה
--               ל-`app.attendance_pay_rows`: הפונקציה רצה בכל טעינת דשבורד,
--               וסריקה שנייה של definer עתיר window-functions היא נסיגה.
--
-- שינוי אחד ויחיד מול 0041, והוא מה שכל הקובץ עומד עליו: המסנן
-- `where (r.pay ->> 'total') is not null` יורד מ-`rows` והופך ל-`sum(...)`
-- שמדלג על null ממילא. הוא בטוח כי הוא **פר-משמרת**, וגם שני המשקלים
-- פר-משמרת הם (`hours_total` מחולק לפי `id`, ו-`denom` הוא
-- `cardinality(task_ids)`) — הורדת משמרת בלי תעריף לפני הפיזור או אחריו
-- נותנת אותו כסף בדיוק. מה שהוא קונה הוא `unrated_shifts` **פר-משימה**,
-- מונה שהיום קיים רק גלובלית (0041:50). בלעדיו משימה שכל המשובצים בה בלי
-- תעריף מציגה שכר 0 ורווח 100% — שקר בטוח בעצמו על המספר שבדיוק מסתכלים בו.

drop type if exists app.payroll_task_amount cascade;
create type app.payroll_task_amount as (
  task_id        uuid,
  customer_id    uuid,
  task_deleted   boolean,
  bucket         text,
  amount         numeric,
  shifts         int,
  unrated_shifts int,
  actual_hours   numeric,
  workers        int
);

create or replace function app.payroll_task_amounts(p_from date, p_to date)
returns setof app.payroll_task_amount
language plpgsql stable security definer set search_path = public as $$
begin
  return query
  with src as (
    select r.id, r.profile_id,
           (r.pay ->> 'total')::numeric as total,
           (r.pay ->> 'hourly_rate') is null as unrated,
           coalesce(r.actual_hours, 0) as worked,
           r.task_ids
      from app.attendance_pay_rows(p_from, p_to, null, null, false, array['approved'], 'all') r
  ),
  -- כל המשימות שהמשמרת נוקבת בהן, כולל כאלה שנמחקו: הן חלק מהמכנה
  spread as (
    select w.id, w.profile_id, w.total, w.unrated, w.worked,
           u.task_id as ref_id,
           t.id as task_id, t.customer_id, t.deleted_at,
           coalesce(t.hours_count, 0) as hours,
           cardinality(w.task_ids) as denom
      from src w
      cross join lateral unnest(w.task_ids) as u(task_id)
      left join tasks t on t.id = u.task_id
     where cardinality(w.task_ids) > 0
  ),
  weighted as (
    select s.*, sum(s.hours) over (partition by s.id) as hours_total
      from spread s
  ),
  -- הביטויים נשמרים מילה במילה מ-0041:129-132. `total * (hours/hours_total)`
  -- ו-`total/denom` אינם זהים לחלוטין ל-`total * (1/denom)` בנומריקה, ושורת
  -- `round(...,2)` במעלה הזרם יכולה להיתלות בהפרש הזה.
  alloc as (
    select w.id, w.profile_id, w.unrated, w.ref_id, w.task_id,
           w.customer_id, w.deleted_at,
           case when w.hours_total > 0 then w.total  * (w.hours / w.hours_total)
                else w.total  / w.denom end as amount,
           case when w.hours_total > 0 then w.worked * (w.hours / w.hours_total)
                else w.worked / w.denom end as alloc_hours
      from weighted w
  )
  select coalesce(a.task_id, a.ref_id),
         a.customer_id,
         a.deleted_at is not null,
         case when a.task_id is not null then 'task' else 'missing' end,
         sum(a.amount),
         count(*)::int,
         count(*) filter (where a.unrated)::int,
         round(sum(a.alloc_hours), 2),
         count(distinct a.profile_id)::int
    from alloc a
   group by 1, 2, 3, 4

  union all

  -- משמרת בלי משימות אינה מתפזרת בשקט בין לקוחות. `task_ids` הוא
  -- `not null default '{}'` (0019:105), ולכן `cardinality(...) = 0` מכסה הכול.
  select null::uuid, null::uuid, false, 'none',
         sum(w.total),
         count(*)::int,
         count(*) filter (where w.unrated)::int,
         round(sum(w.worked), 2),
         count(distinct w.profile_id)::int
    from src w
   where cardinality(w.task_ids) = 0
  having count(*) > 0;
end $$;

-- מחזירה את שכר כל משימה בחברה בלי לשאול דבר — כמו `app.attendance_pay_rows`
-- (0039:153), היא נשללת לגמרי והשער יושב אצל הקורא.
revoke execute on function app.payroll_task_amounts(date, date)
  from anon, authenticated, public;

-- ===== 2. הקורא הקיים, מעל העוזר ===========================================
--
-- אותה חתימה, אותו `app.require`, אותם שלושה מפתחות בפלט, אותו עיגול. ארבעה
-- קוראים תלויים בפלט הזה (0041:350, 0044:118, 0044:394, 0069:98) וכולם קוראים
-- רק `by_customer` / `allocated` / `unallocated`.
--
-- שני פרטים נושאי משקל:
--
-- * `amount is not null` יושב **רק ב-`by_customer`**. היום לקוח שכל משמרותיו
--   בלי תעריף אינו מייצר שורות `alloc` כלל ונעדר מהמערך; בלי התנאי הזה הוא
--   היה שורד עם `payroll: null`, ו-0044:394 (ממד `payroll.customer` במנוע
--   הדוחות) היה פולט `value` ריק. `allocated`/`unallocated` אינם זקוקים לו —
--   ‏`sum()` מדלג על null ושניהם עטופים ב-`round(coalesce(...,0), 2)`.
--
-- * משימה שנמחקה רכות **צורכת את חלקה** והשארית הולכת ל-`unallocated`
--   (0041:101). הקטנת המכנה הייתה מנפחת את העלות של הלקוחות ששרדו.

create or replace function app.payroll_task_alloc(p_from date, p_to date)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v jsonb;
begin
  perform app.require('dashboard.payroll');

  with a as (select * from app.payroll_task_amounts(p_from, p_to))
  select jsonb_build_object(
    'by_customer', (select coalesce(jsonb_agg(row_to_json(x)), '[]') from (
        select c.name, c.color, round(sum(a.amount), 2) as payroll
          from a join customers c on c.id = a.customer_id
         where a.bucket = 'task' and not a.task_deleted and a.amount is not null
         group by c.name, c.color order by 3 desc) x),
    -- שלושה מקורות לאותו דלי, וכולם גלויים: משמרת בלי משימות, משימה שנמחקה,
    -- ומשימה עצמאית בלי לקוח
    'unallocated', round(coalesce((select sum(a.amount) from a
                                    where a.bucket <> 'task' or a.task_deleted
                                       or a.customer_id is null), 0), 2),
    'allocated',   round(coalesce((select sum(a.amount) from a
                                    where a.bucket = 'task' and not a.task_deleted
                                      and a.customer_id is not null), 0), 2))
    into v;

  return v;
end $$;

-- ===== 3. שורות הרווחיות ===================================================
--
-- **`security definer`, וזו ההכרעה היקרה ביותר בקובץ.** ‏`task_contractor_terms`
-- נקראת רק בידי מי שמחזיק `contractors.view_pricing` (0012:238). שאילתת invoker
-- בידי קורא שמחזיק את כל צרור הרווח אבל לא את המפתח הזה הייתה מחזירה **אפס
-- שורות** מהטבלה — עלות קבלן 0, ורווח מנופח בדיוק בגובה כל הקבלנות, בלי שום
-- סימן שמשהו חסר. `app.margin_summary` ו-`app.margin_by_customer` נמנעות מזה
-- בדיוק באותה דרך. מה שהופך את ה-definer לשקול ל-invoker כאן הוא
-- ש-`app.margin_require()` כבר סירבה לכל היקף נתונים מצומצם על `tasks`.
--
-- שני שערים נוספים מעבר לצרור:
--
-- * `dashboard.all_workers`. שכר פר-משימה על משימה שמשובץ אליה עובד אחד **הוא**
--   השכר של אותו עובד לאותו יום. זה בדיוק הקו ש-`app.payroll_by_worker`
--   (0041:62) כבר מותחת בין "הסכום הכולל" ל"כמה מרוויח כל אחד". המפתח נגזר
--   מ-`dashboard.view` עם `default_allowed=false`, וכבר מוחזק בידי `ops_manager`
--   ו-`dispatcher` — ולכן ביום המיגרציה איש אינו מאבד מספר ואיש אינו מקבל חדש.
--
-- * `staff` או אדמין בלבד. `applies_to` ברישום הוא תיעוד ולא אכיפה (0017:113),
--   ולכן `customer_user` שקיבל `dashboard.margin` מאדמין היה עובר את
--   `has_all` — ופונקציית definer הייתה מגישה לו את שכר כל החברה.

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
      -- מפתח שמשמיט שדה, לא מפתח שחוסם את הדוח: שורה כאן היא משימה ולא לקוח,
      -- ובלי השם היא עדיין נושאת כותרת, סוג ומספר אירוע.
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
    left join task_contractor_terms tct on tct.task_id = t.id
    left join alloc                 a   on a.task_id  = t.id
    where t.deleted_at is null
      and t.task_date between p_from and p_to
      and (p_task_id     is null or t.id          = p_task_id)
      and (p_customer_id is null or t.customer_id = p_customer_id)
  ),
  -- החיסור, האחוז ועלות המעביד — כאן ולא בדפדפן (0059:6).
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
    -- הרווח הגרוע ביותר ראשון: זו התשובה לשאלה ששאלו.
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
    -- הסיכום רץ על כל הטווח ולא על העמוד: `limit` הוא תקרת תצוגה, לא מסנן.
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

-- ===== 4. הדלת של המסך =====================================================
--
-- מבנה זהה ל-`customer_profitability` (0059:17): `reports.view` זורק, וכל השאר
-- מחזיר `{rows: null, denied}` **ולא שגיאה** — הדף קיים, הנתון אינו בשבילך.
-- אלה בדיוק התנאים ש-§3 זורק עליהם, נבדקים ברכות לפני שהעוזר נקרא.

create or replace function public.task_pnl(
  p_from        date,
  p_to          date,
  p_task_id     uuid default null,
  p_customer_id uuid default null,
  p_limit       int  default 200)
returns jsonb language plpgsql stable security invoker set search_path = public as $$
declare
  v      jsonb;
  v_alloc jsonb;
  v_rows jsonb;
  v_total int;
begin
  if not app.has('reports.view') then
    raise exception 'אין הרשאה לדוחות' using errcode = '42501';
  end if;

  -- אותם ארבעה גבולות של dashboard_sections, של המנוע ושל 0059
  if p_from is null or p_to is null then
    raise exception 'חסר טווח תאריכים' using errcode = '22023'; end if;
  if p_to < p_from then
    raise exception 'טווח תאריכים הפוך' using errcode = '22023'; end if;
  if p_to - p_from > 400 then
    raise exception 'טווח גדול מדי לדשבורד' using errcode = '22023'; end if;

  if not app.has_all(array['dashboard.margin','dashboard.payroll',
                           'dashboard.contractor_cost','pricing.revenue',
                           'dashboard.all_workers'])
     or exists (select 1 from app.scope_rows('tasks') where scope_type <> 'all')
     or not (app.is_admin() or app.user_kind() = 'staff') then
    return jsonb_build_object('rows', null, 'meta', jsonb_build_object('denied', true));
  end if;

  v       := app.task_pnl_rows(p_from, p_to, p_task_id, p_customer_id, p_limit);
  v_alloc := app.payroll_task_alloc(p_from, p_to);
  v_rows  := v -> 'rows';

  -- truncated אמיתי ולא ניחוש, ותחת invoker כמו 0059:68 — הספירה רואה את מה
  -- שהקורא רואה, וההיקף כבר אומת מלא למעלה.
  select count(*) into v_total
    from tasks t
   where t.deleted_at is null
     and t.task_date between p_from and p_to
     and (p_task_id     is null or t.id          = p_task_id)
     and (p_customer_id is null or t.customer_id = p_customer_id);

  return jsonb_build_object(
    'rows',    v_rows,
    'summary', v -> 'summary',
    'meta', jsonb_build_object(
      'revenue_basis',       'quoted_plan',
      'cost_basis',          'actual_clocked',
      'estimated',           true,
      'excludes_overhead',   true,
      'employer_pct',        (v -> 'summary' -> 'employer_pct'),
      'allocated',           (v_alloc -> 'allocated'),
      'unallocated',         (v_alloc -> 'unallocated'),
      'unrated_shifts',      (v -> 'counters' -> 'unrated_shifts'),
      'tasks_no_attendance', (v -> 'counters' -> 'tasks_no_attendance'),
      'unpriced_tasks',      (v -> 'counters' -> 'unpriced_tasks'),
      'truncated',           v_total > jsonb_array_length(coalesce(v_rows, '[]'::jsonb)),
      'scope_note',
        'המחיר ללקוח מחושב מהתכנון שהוזמן; עלות השכר נמדדת מהשעות שהוחתמו בפועל. '
        'שכר משמרת מתחלק בין משימותיה לפי שעות המשימה, ולכן השיוך משוער. '
        'משמרת שנמשכה אחרי חצות נרשמת ביום העבודה שלה ועשויה ליפול מחוץ לטווח. '
        'שכר שאינו משויך למשימה מופיע כ״לא משויך״ ואינו נספר באף שורה.'));
end $$;

-- ===== 5. הרשאות הרצה ======================================================
--
-- פונקציה חדשה **אינה בטוחה כברירת מחדל**: CREATE FUNCTION מעניק execute
-- ל-PUBLIC, וביטול מ-public מוחק גם את ההענקה המרומזת ש-authenticated נשען
-- עליה — ולכן ההענקה המפורשת חוזרת. אותה רשימה מפורשת של 0008/0012/0044/0058.

revoke execute on function public.task_pnl(date, date, uuid, uuid, int) from anon, public;
grant  execute on function public.task_pnl(date, date, uuid, uuid, int) to authenticated;

-- אין צורך באינדקס חדש, וזו הצהרה ולא השמטה: `task_pricing` ו-
-- `task_contractor_terms` ממופתחות על `task_id`, `tasks_date_live_idx` (0041:573)
-- מכסה את סריקת התאריכים, `attendance_date_status_idx` מכסה את סריקת
-- המשמרות, וההקצאה מונעת מתאריך ולא ממשימה — ולכן אינדקס GIN על
-- `attendance_entries.task_ids` לא היה נבחר לעולם.
