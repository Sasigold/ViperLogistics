-- 0114: אירוע שבוטל אינו כסף ואינו ספירה, ותוספת המחיר כן
--
-- שני תיקונים לאותה שאלה — "מה בדיוק מסתכם במסך הכספי" — ולכן מיגרציה אחת.
-- שניהם נוגעים באותם שישה גופי פונקציות, והגדרה מחדש כפולה של
-- `dashboard_sections` בן 550 השורות הייתה מכפילה את הסיכון בלי תמורה.
--
-- ===== א. מבוטלים =========================================================
--
-- מאז 0037 הלו״ז מסתיר אירוע שבוטל, ולוח השנה מסתיר אותו מאחורי מתג. אף
-- אגרגט לא ידע על כך דבר: `dashboard_stats`, `dashboard_sections`, מנוע
-- הדוחות, עוזרי הרווח ו-`task_pnl` כולם ספרו עבודה שלא תתבצע כהכנסה. שני
-- מסכים סמוכים החזיקו שתי תשובות שונות לשאלה "מה היה החודש", וזו בדיוק
-- ההתנגשות ש-0037 נימק את מניעתה ("כדי ששני המסכים לא יחלקו על מה נחשב
-- מבוטל") — רק שהיא נמנעה שם בין הלוח ללוח השנה, ולא מול הכסף.
--
-- ===== ב. תוספות המחיר ====================================================
--
-- ‏0113 הוציאה את `task_price_addons` מ-`task_pricing.price` **בכוונה**:
-- המחיר שם הוא תוצר המחשבון, וחישוב מחדש היה מוחק את התוספת או נועל את
-- המשימה על `is_manual` בגלל 80 ₪ של המתנה. ההכרעה נכונה ונשארת. מה שחסר
-- היה מקום אחד שאומר מה המחיר ה**אפקטיבי** — ובלעדיו "המתנה בשער — 450 ₪"
-- הופיעה בכרטיס האירוע (שמחבר אותה בקליינט) ונעלמה מכל סיכום כספי במערכת.
--
-- ===== איך, ולמה כך =======================================================
--
-- שלושה views ולא ארבעים פרדיקטים משוכפלים. תנאי שנכתב ארבעים פעם הוא
-- ארבעים הזדמנויות לשכוח אותו פעם אחת, והשכחה הזו אינה נופלת כשגיאה אלא
-- כמספר שנראה סביר. ‏`from tasks t` ⇐ `from app.live_tasks t` היא החלפה
-- שאפשר לקרוא ב-diff ולחפש ב-grep.
--
-- וזה גם מה שמנטרל את המלכודת האמיתית: בענפים שבהם האירוע או המשימה מגיעים
-- ב-`left join` (‏`customers.leaderboard`), פרדיקט ב-`where` היה הופך את
-- ה-join לפנימי ומוחק לקוח שאמור להיקרא אפס. סינון שיושב בתוך ה-view אינו
-- יכול לעשות את זה.
--
-- ‏`security_invoker = true` בשלושתם, כמו `work_board_view`: כל פוליסות
-- ה-RLS ממשיכות להכריע מי רואה מה, ואין כאן משטח קריאה חדש. בתוך פונקציית
-- ‏`security definer` (עוזרי הרווח, `task_pnl_rows`) ה"invoker" הוא ממילא
-- בעלת הפונקציה, ולכן שם ההתנהגות זהה לקודמתה.
--
-- ‏`app` ולא `public`: הסכמה אינה חשופה ב-PostgREST, ולכן ה-views אינם
-- מוסיפים נקודת קצה. אותו שיקול של `app.customer_identities` (0079).

-- ===== 1. מה נחשב מבוטל ===================================================
--
-- ‏`statuses.code` ולא השם: השם ניתן לעריכה במסך ההגדרות, וכלל שנשען על
-- המחרוזת "בוטל" נשבר ברגע שמישהו מקליד "מבוטל". ולא `is_terminal` — הוא
-- נכון גם ל"הושלם", וההבדל ביניהם הוא כל התכלית כאן: אירוע שהושלם הוא
-- היסטוריה שראוי לספור, אירוע שבוטל הוא עבודה שלא תתבצע. אותו נימוק בדיוק
-- של 0037, ואותה זהות.
--
-- מזהה ולא בוליאון פר-שורה: `(select app.cancelled_event_status_id())` נפתר
-- פעם אחת לשאילתה כ-InitPlan, כפי ש-0028 קבע לכל תת-שאילתה שאינה תלויה
-- בשורה. בוליאון שמקבל `event_id` היה קריאת פונקציה לכל שורה.
create or replace function app.cancelled_event_status_id() returns uuid
language sql stable set search_path = public as $$
  select id from statuses
   where entity = 'event' and code = 'cancelled' and deleted_at is null
   limit 1
$$;

comment on function app.cancelled_event_status_id() is
  'מזהה סטטוס האירוע "בוטל" (0114). נקרא כתת-שאילתה עטופה כדי להיפתר פעם '
  'אחת לשאילתה. null כשהסטטוס נמחק מההגדרות — ואז שום דבר אינו מסונן.';

-- ===== 2. שלושת ה-views ===================================================
--
-- ‏`is distinct from` ולא `<>`: אירוע שאין לו סטטוס כלל חייב להמשיך להיספר.
-- ‏`<>` מול null מחזיר null, כלומר "לא", והאירוע היה נעלם בשקט.
create or replace view app.live_events with (security_invoker = true) as
  select e.*
    from events e
   where e.deleted_at is null
     and e.status_id is distinct from (select app.cancelled_event_status_id());

comment on view app.live_events is
  'אירועים שלא נמחקו ולא בוטלו (0114) — הבסיס לכל ספירה וכל סכום. אינו '
  'חשוף ב-API. היוצא מן הכלל היחיד הוא events.funnel, שכל עניינו ההתפלגות '
  'לפי סטטוס ולכן קורא ישירות מ-events.';

-- ‏`not exists` רגיל ולא `is distinct from`: משימה בלי אירוע (`event_id`
-- ריק) היא משימה עצמאית אמיתית, והיא חייבת להישאר.
create or replace view app.live_tasks with (security_invoker = true) as
  select t.*
    from tasks t
   where t.deleted_at is null
     and not exists (select 1 from events e
                      where e.id = t.event_id
                        and e.status_id = (select app.cancelled_event_status_id()));

comment on view app.live_tasks is
  'משימות שלא נמחקו ושהאירוע שלהן לא בוטל (0114). משימה בלי אירוע נשארת.';

-- המחיר האפקטיבי: מה שהמחשבון חישב, ועוד מה שאדם הוסיף ידנית לצדו.
--
-- מפתח על `tasks` ולא על `task_pricing`, עם `where` שמשאיר רק שורות שיש
-- בהן משהו: משימה שיש לה תוספת אבל טרם תומחרה אינה נעלמת מהסכום. זה בדיוק
-- מה שדף האירוע כבר עושה בקליינט (`orphanAddons`), ומכאן השרת מסכים איתו.
--
-- ‏`deleted_at is null` על התוספת — ל-0113 יש מחיקה רכה, ותוספת שהוסרה
-- ירדה מהחשבון. סכום שלילי ("הנחה על איחור שלנו") מתחבר כמו שהוא.
--
-- ‏`base_price` ו-`addons_total` נשמרים בנפרד כדי שמי שצריך להבחין ביניהם
-- יוכל, ובראשם `pricing.quality` — ששואל על **המחשבון** ולכן ממשיך לקרוא
-- מ-`task_pricing` ישירות: תוספת ידנית אינה הופכת משימה ל"מתומחרת".
create or replace view app.task_revenue with (security_invoker = true) as
  select t.id                                        as task_id,
         coalesce(tp.price, 0) + coalesce(ad.total, 0) as price,
         tp.price                                    as base_price,
         coalesce(ad.total, 0)                       as addons_total,
         tp.is_manual,
         tp.breakdown,
         tp.calculated_at
    from tasks t
    left join task_pricing tp on tp.task_id = t.id
    left join lateral (
      select sum(a.amount) as total
        from task_price_addons a
       where a.task_id = t.id and a.deleted_at is null) ad on true
   where tp.task_id is not null or ad.total is not null;

comment on view app.task_revenue is
  'המחיר שהלקוח משלם על המשימה (0114): task_pricing.price ועוד תוספות '
  '0113 החיות. אותו שם עמודה (price) כמו במקור, ולכן זו החלפת שם טבלה '
  'בלבד בכל אתר סיכום. task_pricing עצמה נשארת התשובה לשאלות על המחשבון.';

grant select on app.live_events, app.live_tasks, app.task_revenue to authenticated;

-- ===== 3. מנוע הדוחות: המקור, לא התנאי ====================================
--
-- ‏0044 קבע ש"המלכודות יושבות ב-report_source_where ולא בקטלוג". הן ממשיכות
-- לשבת שם — אבל את הביטול והתוספת נכון יותר לתקן ב-**מקור** ולא בתנאי:
-- ‏`report_source_where` מחזירה טקסט SQL, וכל פרדיקט שנכתב בה נושא ציטוט
-- מוכפל וקושי לקרוא. החלפת שם הטבלה ב-`report_source_sql` עושה את אותו דבר
-- בלי מרכאה אחת, וחלה על שני הגופים של `app.report_run` (0044, 0058)
-- שקוראים לשתי הפונקציות האלה בשם.
--
-- ‏`t.deleted_at is null` ו-`e.deleted_at is null` נשארים ב-where אף שהם
-- מיותרים עכשיו: הם נכונים, הם זולים, והורדתם היא שינוי בלי סיבה.

create or replace function app.report_source_sql(p_key text) returns text
language sql immutable set search_path = public as $$
  select case p_key
    when 'tasks'      then 'app.live_tasks t'
    when 'events'     then 'app.live_events e'
    -- profiles נכנס כאן כי הפילוח "לפי עובד" זקוק לשם, וזה join פנימי מבחינה
    -- לוגית: לכל שורת נוכחות יש בעלים.
    when 'attendance' then 'attendance_entries a join profiles p on p.id = a.profile_id'
    -- 'payroll' אינו כאן במכוון: כל מדדיו הם impl='engine'. app.attendance_pay_rows
    -- מבוטלת מ-authenticated, ולכן פונקציית invoker אינה יכולה לקרוא לה גם אם
    -- ננסה — וזו בדיוק הסיבה שהשכר מנותב לעוזרי definer.
    else null end
$$;


-- מדד `revenue` בקטלוג הוא impl='sql' עם join_key='task_pricing',
-- col='price' ו-presence_col='task_id' (0043). ‏`col` נפלט דרך `%I` ולכן
-- אינו יכול להיות ביטוי — ולכן ההחלפה כאן, ב-join, היא מה שמכניס את
-- התוספות לכל דוח בלי לגעת בקטלוג ובלי מימוש שני שיתיישן (הכלל של 0039).

create or replace function app.report_join_sql(p_key text) returns text
language sql immutable set search_path = public as $$
  select case p_key
    when 'customers'        then ' left join customers c on c.id = t.customer_id and c.deleted_at is null'
    when 'task_status'      then ' left join statuses s on s.id = t.status_id'
    when 'task_types'       then ' left join task_types tt on tt.id = t.task_type_id'
    when 'exec_methods'     then ' left join execution_methods em on em.id = t.execution_method_id'
    -- LEFT lateral ולא CROSS: cross join על מערך ריק מוחק את המשימה מהתוצאה,
    -- ומשימה בלי משאית היא בדיוק מה ש"משימות לפי משאית" צריך להראות.
    when 'trucks'           then ' left join lateral unnest(t.truck_ids) as u(truck_id) on true'
                                 ' left join trucks tr on tr.id = u.truck_id'
    when 'task_contractor'  then ' left join contractors ct on ct.id = t.contractor_id and ct.deleted_at is null'
    when 'task_pricing'     then ' left join app.task_revenue tp on tp.task_id = t.id'
    when 'contractor_terms' then ' left join task_contractor_terms tct on tct.task_id = t.id'
    when 'ev_customers'     then ' left join customers ec on ec.id = e.customer_id and ec.deleted_at is null'
    when 'ev_status'        then ' left join statuses es on es.id = e.status_id'
    -- profiles כבר ב-FROM של attendance; הפילוח רק צריך את הכינוי.
    when 'people'           then ''
    else null end
$$;


-- ===== 4. הגופים שסוכמים ==================================================
--
-- כל אחד מהם מוגדר מחדש **במלואו**, מהגרסה החיה שלו — לא מזו שיצרה אותו:
-- ‏margin_summary מ-0069 (שהוסיפה event_income להכנסה), margin_trend
-- ו-margin_by_customer ו-task_pnl_rows מ-0100 (ריבוי הקבלנים),
-- dashboard_stats מ-0069 ו-dashboard_sections מ-0091. העתקה מ-0044 או
-- מ-0070 הייתה מחזירה את העבודות ההן אחורה בלי שגיאה, רק עם מספרים שגויים.
--
-- מה שנשאר כפי שהיה, ובכוונה:
--
--   • `events.funnel` — כל עניינו ההתפלגות לפי סטטוס אירוע. להסתיר ממנו את
--     "בוטל" אינו תיקון אלא שקר על הצנרת. הוא הצרכן היחיד שנשאר על `events`.
--   • `pricing.quality` — שואל על המחשבון (מה תומחר, מה ידני, מה לא נגע בו
--     אדם), ולכן ממשיך לקרוא `task_pricing` ולא `app.task_revenue`. הוא כן
--     עבר ל-`app.live_tasks`: משימה של אירוע מבוטל אינה "חסרת תמחור".
--   • `app.payroll_*` — השכר נגזר ממשמרות שהוחתמו, ושעה שעבדו עליה היא
--     עלות ששולמה גם אם האירוע בוטל אחריה. הורדתה הייתה מייפה את הרווח.
--     בפועל לאירוע מבוטל אין נוכחות מאושרת, ולכן המספר אינו זז.
--   • `customer_profitability` (0059) ו-`public.task_pnl` (0070) — מרכיבים
--     טהורים מעל העוזרים שכאן. תיקון העוזרים מתקן אותם, והגדרה מחדש שלהם
--     הייתה drift בלי תמורה.
--   • `work_board_view.customer_price` — ‏0113 בחרה במפורש שהתוספת תגיע
--     למסך כרשימה עם משפט ולא כמספר שנבלע. לסכם אותה לתוך תא בלוח היה
--     מבטל את ההכרעה ההיא, וזו שאלה נפרדת.


create or replace function app.margin_summary(p_from date, p_to date)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_rev numeric; v_con numeric; v_pay jsonb;
begin
  perform app.margin_require();
  v_pay := app.payroll_summary(p_from, p_to);

  select coalesce((select sum(tp.price)
                     from app.task_revenue tp
                     join app.live_tasks t on t.id = tp.task_id and t.deleted_at is null
                    where t.task_date between p_from and p_to), 0)
       + coalesce((select sum(ei.amount)
                     from event_income ei
                     join app.live_events e on e.id = ei.event_id and e.deleted_at is null
                    where e.event_date between p_from and p_to), 0)
    into v_rev;
  select coalesce(sum(tct.price), 0) into v_con
    from task_contractor_terms tct join app.live_tasks t on t.id = tct.task_id and t.deleted_at is null
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
                 sum(coalesce(tp.price, 0)) as revenue,
                 sum(coalesce((select sum(x.price) from task_contractor_terms x
                                where x.task_id = t.id), 0)) as contractor
            from app.live_tasks t
            left join app.task_revenue tp on tp.task_id = t.id
           where t.deleted_at is null and t.task_date between p_from and p_to
           group by 1
          union all
          select date_trunc(v_b, e.event_date)::date, sum(ei.amount), 0
            from event_income ei
            join app.live_events e on e.id = ei.event_id and e.deleted_at is null
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
              from app.live_tasks t
              left join app.task_revenue tp on tp.task_id = t.id
             where t.deleted_at is null and t.task_date between p_from and p_to
            union all
            select e.customer_id, ei.amount, 0
              from event_income ei
              join app.live_events e on e.id = ei.event_id and e.deleted_at is null
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
    from app.live_tasks t
    left join task_types            tt  on tt.id  = t.task_type_id
    left join statuses              st  on st.id  = t.status_id
    left join events                e   on e.id   = t.event_id
    left join customers             c   on c.id   = t.customer_id
    left join contractors           ct  on ct.id  = t.contractor_id
    left join app.task_revenue          tp  on tp.task_id = t.id
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


create or replace function dashboard_stats(p_from date, p_to date)
returns jsonb language sql stable security invoker set search_path = public as $$
  select jsonb_build_object(
    'events_count', (select count(*) from app.live_events
       where deleted_at is null and event_date between p_from and p_to),
    'events_upcoming', (select count(*) from app.live_events e
       left join statuses s on s.id = e.status_id
       where e.deleted_at is null and e.event_date >= current_date
         and not coalesce(s.is_terminal, false)),
    'events_done', (select count(*) from app.live_events e
       join statuses s on s.id = e.status_id
       where e.deleted_at is null and s.is_terminal
         and e.event_date between p_from and p_to),
    'tasks_count', (select count(*) from app.live_tasks
       where deleted_at is null and task_date between p_from and p_to),
    'tasks_open', (select count(*) from app.live_tasks t join statuses s on s.id = t.status_id
       where t.deleted_at is null and s.code is distinct from 'assigned'
         and t.task_date between p_from and p_to),
    'tasks_today', (select count(*) from app.live_tasks
       where deleted_at is null and task_date = current_date),
    'tasks_week', (select count(*) from app.live_tasks
       where deleted_at is null
         and task_date between date_trunc('week', current_date)::date
         and (date_trunc('week', current_date) + interval '6 days')::date),
    'tasks_overdue', (select count(*) from app.live_tasks t join statuses s on s.id = t.status_id
       where t.deleted_at is null and t.task_date < current_date
         and s.code is distinct from 'assigned'),
    'available_workers', case when app.has('dashboard.all_workers') then
      (select count(*) from profiles p
         where p.deleted_at is null and p.is_active and p.user_kind = 'staff'
           and not exists (select 1 from task_assignments a join app.live_tasks t on t.id = a.task_id
                           where a.profile_id = p.id and t.task_date = current_date
                             and t.deleted_at is null))
      else null end,
    'by_customer', case when app.has('customers.view') then
      (select coalesce(jsonb_agg(row_to_json(x)), '[]') from (
         select c.name, c.color, count(*) as cnt from app.live_tasks t join customers c on c.id = t.customer_id
         where t.deleted_at is null and t.task_date between p_from and p_to
         group by c.name, c.color order by cnt desc limit 12) x)
      else null end,
    'by_contractor', case when app.has('dashboard.contractors') then
      (select coalesce(jsonb_agg(row_to_json(x)), '[]') from (
         select ct.name, count(*) as cnt from app.live_tasks t join contractors ct on ct.id = t.contractor_id
         where t.deleted_at is null and t.task_date between p_from and p_to
         group by ct.name order by cnt desc limit 12) x)
      else null end,
    'by_worker', case when app.has('dashboard.all_workers') then
      (select coalesce(jsonb_agg(row_to_json(x)), '[]') from (
         select p.full_name as name, count(*) as cnt
         from task_assignments a
         join app.live_tasks t on t.id = a.task_id and t.deleted_at is null
           and t.task_date between p_from and p_to
         join profiles p on p.id = a.profile_id
         group by p.full_name order by cnt desc limit 12) x)
      else null end,
    'financial', case when app.has('dashboard.financial') then
      (select jsonb_build_object(
         'expected', coalesce(sum(tct.price), 0),
         'paid', coalesce(sum(tct.paid_amount) filter (where tct.paid_at is not null), 0))
       from task_contractor_terms tct
       join app.live_tasks t on t.id = tct.task_id and t.deleted_at is null
        and t.task_date between p_from and p_to)
      else null end,
    'revenue', case when app.has('pricing.revenue') then
      (select jsonb_build_object(
         'total', coalesce(sum(tp.price), 0)
                  + coalesce((select sum(ei.amount)
                                from event_income ei
                                join app.live_events e on e.id = ei.event_id and e.deleted_at is null
                               where e.event_date between p_from and p_to), 0),
         'priced_tasks', count(*) filter (where tp.price is not null),
         'by_customer', case when app.has('customers.view') then
           (select coalesce(jsonb_agg(row_to_json(y) order by y.total desc), '[]') from (
              select u.name, u.color, round(sum(u.total), 2) as total from (
                select c.name, c.color, coalesce(sum(tp2.price), 0) as total
                from app.task_revenue tp2
                join app.live_tasks t2 on t2.id = tp2.task_id and t2.deleted_at is null
                 and t2.task_date between p_from and p_to
                join customers c on c.id = t2.customer_id
                group by c.name, c.color
                union all
                select c.name, c.color, coalesce(sum(ei2.amount), 0)
                from event_income ei2
                join app.live_events e2 on e2.id = ei2.event_id and e2.deleted_at is null
                 and e2.event_date between p_from and p_to
                join customers c on c.id = e2.customer_id
                group by c.name, c.color) u
              group by u.name, u.color order by 3 desc limit 12) y)
           else null end)
       from app.task_revenue tp
       join app.live_tasks t on t.id = tp.task_id and t.deleted_at is null
        and t.task_date between p_from and p_to)
      else null end,
    'by_status', (select coalesce(jsonb_agg(row_to_json(x)), '[]') from (
       select s.name, s.color, count(*) as cnt from app.live_tasks t join statuses s on s.id = t.status_id
       where t.deleted_at is null and t.task_date between p_from and p_to
       group by s.name, s.color order by cnt desc) x),
    'next_events', (select coalesce(jsonb_agg(row_to_json(x)), '[]') from (
       select e.id, e.event_date, e.end_client_name, e.event_number, e.location_text
       from app.live_events e
       where e.deleted_at is null and e.event_date >= current_date
       order by e.event_date limit 5) x))
$$;


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
  -- 50 ולא 48: שני כרטיסי הצי של 0090 הצטרפו לרשימה שפריסה רחבה יכולה לבקש.
  if coalesce(array_length(p_sections, 1), 0) > 50 then
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


-- create or replace משמר את ה-ACL הקיים (ה-revoke/grant של 0044, 0070, 0087)
-- — אין מה לחזור עליו כאן.
