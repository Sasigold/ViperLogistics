-- ‏0186: שעה של עובד קבלן נספרת פעם אחת
--
-- הדיווח מהמשרד: "אם האצלתי לקבלן אתה מחשב פעמיים את העלויות — פעם אחת
-- התשלום לקבלן, ופעם אחת ההחתמה של העובד של הקבלן בשעון נוכחות."
--
-- והוא צודק. ‏`app.task_pnl_rows` (0070, ‏0100, ‏0114) בונה את העלות משני
-- מקורות שמעולם לא דיברו זה עם זה:
--
--   contractor_cost ← sum(task_contractor_terms.price)      — מה ששילמנו לקבלן
--   payroll         ← app.payroll_task_amounts              — מה שהשעון הפיק
--
-- והשעון אינו מבחין בין עובד שלנו לעובד של הקבלן: ‏`app.attendance_pay_rows`
-- ‏(0039 §4, ‏0166) מחזירה כל `attendance_entries` בטווח, וחשבון שמשויך לקבלן
-- הוא פרופיל ככל פרופיל — יש לו `worker_pay_settings`, הוא מחתים שעון, ויש לו
-- שורת שכר. כשהוא מחתים על משימה שהואצלה **לקבלן שלו**, אותה שעה נקנתה כבר
-- במחיר הקבלן, ולכן היא נספרת פעמיים.
--
-- האירוע שהמשרד הצביע עליו (‏37208, קיסר, "הקמה"): הכנסה 1,600, מחיר קבלן
-- ‏600, ובשעון שתי החתמות — עובד שלנו ועובד של אותו קבלן. השכר שיוחס למשימה
-- היה 830.90 ₪ במקום 416.50, והעלות ניפחה את עצמה ב-414.40 ₪ ועוד נטל מעביד
-- עליהם. על משימה של 1,600 ₪ זה הפרש של יותר מ-30% בשורת הרווח.
--
-- ===== מה מבדיל בין שני הכובעים ============================================
--
-- ‏**השאלה אינה מי הוא, אלא איזה כובע הוא חבש על המשימה הזו.** ‏0075 כבר קבע
-- את ההבחנה הזו בהרשאות ("מי שמקושר לקבלן", לא "מי שנולד כקבלן"), והנתונים
-- בשטח מאשרים שהיא נחוצה גם בכסף: באותו חודש יש עובד שמקושר לקבלן ומשובץ
-- למשימה של אותו קבלן **כעובד קבלן** (`task_contractor_workers`), ויש עובד
-- שמקושר לאותו קבלן ומשובץ למשימה **כסגל שלנו** (`task_assignments`) בזמן
-- שהצוות של הקבלן שלו עובד לצדו. הראשון כלול במחיר הקבלן; השני הוא שכר שלנו
-- לכל דבר. ‏`profiles.contractor_id` לבדו היה מוחק גם את השני.
--
-- לכן ההכרעה היא **פר (משמרת, משימה)** ולא פר משמרת ולא פר אדם:
--
--   שעה מכוסה ⇔  המשימה חיה (`app.live_tasks`)
--              ∧  יש עליה שורת `task_contractor_terms` לקבלן שלו
--              ∧  הוא משובץ עליה כעובד של אותו קבלן.
--
-- שלושת התנאים הם שמירה הדדית:
--
-- * **בלי שורת terms** אין מחיר קבלן על המשימה, ולכן אין כפילות לנכות —
--   ניכוי היה מוחק עלות אמיתית ומציג רווח שלא היה. ‏(`tcw_price_sync` מ-0091
--   כבר מבטיח ששיבוץ עובד קבלן יוצר את השורה, ולכן התנאי אינו עולה דבר.)
-- * **בלי שיבוץ כעובד קבלן** הוא עבד שם בכובע שלנו — זה בדיוק המקרה של
--   ‏0075, והשכר שלו הוא שלנו.
-- * **משימה שאינה חיה** — אירוע שבוטל או משימה שנמחקה רכות — אינה תורמת
--   ‏`contractor_cost` לאף סיכום (0114), ולכן אין ממה לנכות. ‏0114 הכריע
--   במפורש שהשכר **כן** נשאר שם ("שעה שעבדו עליה היא עלות ששולמה גם אם
--   האירוע בוטל אחריה"), וההכרעה ההיא נשמרת כאן כמו שהיא.
--
-- ===== איפה זה נחתך, ולמה שם =============================================
--
-- הפיצול של משמרת בין המשימות שלה יושב במקום אחד — ‏`app.payroll_task_amounts`
-- ‏(0070 §1) — ושם גם התשובה צריכה לשבת. אבל הסכומים הגלובליים
-- ‏(`app.margin_summary`, ‏`app.margin_trend`) אינם עוברים דרכו כלל: הם
-- מחברים `app.payroll_summary` ל-`sum(task_contractor_terms.price)`, וסובלים
-- מאותה כפילות בדיוק. מימוש שני של המשקלים היה מתיישן ביום שמישהו יגע
-- באחד מהם.
--
-- לכן §1 מחלץ את הפיצול עצמו לעוזר אחד — ‏`app.payroll_task_spread` — שמחזיר
-- שורה לכל (משמרת, משימה) ואת הדגל `covered` עליה, וכל השאר יושב מעליו:
-- ‏`app.payroll_task_amounts` מצטבר ממנו, והסכומים הגלובליים שואלים אותו
-- ישירות. זו אותה תזה של 0070 §1 עצמו, צעד אחד למעלה.
--
-- ===== מה נשאר ברוטו, ובכוונה ==============================================
--
-- ‏**השכר שהשעון הפיק אינו זז.** ‏`app.payroll_summary`, ‏`app.payroll_trend`,
-- ‏`app.payroll_by_worker` ו-`allocated`/`unallocated` של
-- ‏`app.payroll_task_alloc` ממשיכים לדווח את מה שההחתמות מייצרות, כולל של
-- עובדי קבלנים. שם השאלה היא "מה השעון אומר" — המשרד מאשר מולו שעות ומיישב
-- אותו מול דוח הנוכחות — ומספר שיזוז שם בשקט הוא מספר שאי אפשר יהיה ליישב.
-- מה שמשתנה הוא **הרווח**: שם השאלה היא "כמה זה עלה לי", ושם שעה שנקנתה
-- מהקבלן אינה שכר שלנו.
--
-- ההפרש עצמו אינו נעלם — הוא מדווח: `contractor_covered` בכל אחת מהתשובות,
-- כדי שמי שמחסר ברוטו מנטו ימצא את המספר ולא יחפש אותו.

-- ===== 1. העוזר: שורה לכל (משמרת, משימה), ועליה איזה כובע ==================
--
-- ‏`returns table` כאן ולא טיפוס מורכב: הנימוק של 0070 §1 (פרמטרי OUT
-- בשמות שהם גם עמודות) חל על הגוף שמפנה אליהם, וכאן הגוף כולו הוא CTE אחד
-- עם כינויים מפורשים (`w.`, ‏`s.`, ‏`t.`) ואין בו הפניה חשופה לאף שם.
--
-- ‏`security definer` מאותו טעם של `app.payroll_task_amounts`: הוא מחזיר את
-- שכר כל החברה בלי לשאול דבר, ולכן הוא **נשלל מכולם** והשער יושב אצל הקורא.
--
-- ‏**משמרת בלי משימות נשארת בפנים**, עם `ref_id` ו-`task_id` ריקים. היא זו
-- שנעשית דלי `'none'` במצטבר, וכך אין קריאה שנייה ל-`app.attendance_pay_rows`
-- — ההכרעה של 0070 §1, שנשמרת כאן מילה במילה.
create or replace function app.payroll_task_spread(p_from date, p_to date)
returns table (
  entry_id     uuid,
  profile_id   uuid,
  work_date    date,
  /* המזהה שהמשמרת נקבה בו, גם כשאין לו שורה ב-`tasks` */
  ref_id       uuid,
  task_id      uuid,
  task_date    date,
  customer_id  uuid,
  task_deleted boolean,
  unrated      boolean,
  /* מחיר קבלן כבר שילם על השעה הזו */
  covered      boolean,
  amount       numeric,
  alloc_hours  numeric)
language plpgsql stable security definer set search_path = public as $$
begin
  return query
  with src as (
    select r.id, r.profile_id, r.work_date,
           (r.pay ->> 'total')::numeric as total,
           (r.pay ->> 'hourly_rate') is null as unrated,
           coalesce(r.actual_hours, 0) as worked,
           r.task_ids,
           /* ‏0150: חשבון שמשויך לקבלן מקבל שורת סגל מיד, ו-0149 מוודא
              שהשורה שייכת לקבלן של החשבון. ‏`contractor_workers.user_id`
              נשאר null במתכוון (0150), ולכן `profiles.contractor_worker_id`
              הוא הקישור היחיד בין חשבון לרוסטר — וזה הקישור שהשיבוץ
              ב-`task_contractor_workers` מצביע עליו. */
           p.contractor_id,
           p.contractor_worker_id
      from app.attendance_pay_rows(p_from, p_to, null, null, false, array['approved'], 'all') r
      join profiles p on p.id = r.profile_id
  ),
  -- כל המשימות שהמשמרת נוקבת בהן, כולל כאלה שנמחקו: הן חלק מהמכנה.
  -- ‏`left join lateral ... on true` ולא `cross join` עם `cardinality > 0`:
  -- משמרת בלי משימות יוצאת כשורה אחת עם `ref_id` ריק, ונשארת בזרם.
  spread as (
    select w.id, w.profile_id, w.work_date, w.total, w.unrated, w.worked,
           u.task_id as ref_id,
           t.id as task_id, t.task_date, t.customer_id, t.deleted_at,
           coalesce(t.hours_count, 0) as hours,
           cardinality(w.task_ids) as denom,
           /* הכובע. שלושת התנאים מנומקים בראש הקובץ; שניים מהם הם `exists`
              על שורה שממילא קיימת (0091), והשלישי הוא השאלה האמיתית. */
           (t.id is not null
            and exists (select 1 from app.live_tasks lt where lt.id = t.id)
            and w.contractor_id is not null
            and exists (select 1 from task_contractor_terms tct
                         where tct.task_id = t.id
                           and tct.contractor_id = w.contractor_id)
            and exists (select 1 from task_contractor_workers tcw
                         where tcw.task_id = t.id
                           and tcw.contractor_worker_id = w.contractor_worker_id))
             as covered
      from src w
      left join lateral unnest(w.task_ids) as u(task_id) on true
      left join tasks t on t.id = u.task_id
  ),
  weighted as (
    select s.*, sum(s.hours) over (partition by s.id) as hours_total
      from spread s
  )
  -- הביטויים נשמרים מילה במילה מ-0070 §1 (ומשם מ-0041:129-132).
  -- `total * (hours/hours_total)` ו-`total/denom` אינם זהים לחלוטין
  -- ל-`total * (1/denom)` בנומריקה, ושורת `round(...,2)` במעלה הזרם יכולה
  -- להיתלות בהפרש הזה.
  select w.id, w.profile_id, w.work_date, w.ref_id, w.task_id, w.task_date,
         w.customer_id, w.deleted_at is not null, w.unrated, w.covered,
         case when w.ref_id is null    then w.total
              when w.hours_total > 0   then w.total  * (w.hours / w.hours_total)
              else w.total  / w.denom end,
         case when w.ref_id is null    then w.worked
              when w.hours_total > 0   then w.worked * (w.hours / w.hours_total)
              else w.worked / w.denom end
    from weighted w;
end $$;

revoke execute on function app.payroll_task_spread(date, date)
  from anon, authenticated, public;

comment on function app.payroll_task_spread(date, date) is
  'שורה לכל (משמרת, משימה) עם חלקה בשכר ובשעות, ועליה `covered` — האם מחיר '
  'קבלן כבר שילם על השעה הזו (0186). משמרת בלי משימות נשארת עם ref_id ריק. '
  'נשללת מכולם: היא מחזירה את שכר כל החברה, והשער יושב אצל הקורא.';

-- ===== 2. המצטבר, מעל העוזר ===============================================
--
-- אותן ארבע דליים ואותם מספרים; מה שנוסף הוא `contractor_covered`, ומה
-- שהשתנה בשקט הוא `unrated_shifts`: משמרת של עובד קבלן שאין לו תעריף אצלנו
-- אינה "משמרת שאינה נספרת" — היא משמרת שנספרה במחיר הקבלן. אזהרה עליה
-- הייתה שולחת את המשרד לחפש תעריף לעובד שאינו שלו.
--
-- ‏`amount` נשאר **ברוטו**, וזו ההכרעה שמחזיקה את `allocated`/`unallocated`:
-- הם נמדדים מול סך השכר של השעון (06_report_builder), ומספר נטו שם היה
-- שובר את השוויון בלי שאיש יבקש זאת.

alter type app.payroll_task_amount add attribute contractor_covered numeric cascade;

create or replace function app.payroll_task_amounts(p_from date, p_to date)
returns setof app.payroll_task_amount
language plpgsql stable security definer set search_path = public as $$
begin
  return query
  with sp as (select * from app.payroll_task_spread(p_from, p_to))
  select coalesce(s.task_id, s.ref_id),
         s.customer_id,
         s.task_deleted,
         /* 'task' — יש שורה ב-`tasks`. ‏'missing' — המשמרת נקבה במזהה שאין
            לו שורה. ‏'none' — משמרת בלי `task_ids` כלל (0019:105 מבטיח
            `not null default '{}'`, ולכן אין מצב רביעי). */
         case when s.task_id is not null then 'task'
              when s.ref_id  is not null then 'missing'
              else 'none' end,
         sum(s.amount),
         count(*)::int,
         count(*) filter (where s.unrated and not s.covered)::int,
         round(sum(s.alloc_hours), 2),
         count(distinct s.profile_id)::int,
         round(coalesce(sum(s.amount) filter (where s.covered), 0), 2)
    from sp s
   group by 1, 2, 3, 4;
end $$;

comment on function app.payroll_task_amounts(date, date) is
  'שכר המשמרות המאושרות, מפוזר למשימות (0070), מעל app.payroll_task_spread '
  '(0186). amount הוא ברוטו, ו-contractor_covered הוא החלק שמחיר קבלן כבר '
  'שילם עליו. נשללת מכולם — השער יושב אצל הקורא.';

-- ===== 3. ההקצאה ללקוחות ==================================================
--
-- פלט זהה ל-0070 §2 ועוד שני שדות: `contractor_covered` על כל שורת לקוח,
-- ו-`contractor_covered` כסכום. ארבעת הקוראים הקיימים (0041:350, ‏0044:118,
-- ‏0044:394, ‏0069:98) קוראים `by_customer`/`allocated`/`unallocated` ואינם
-- רואים שינוי; ‏`app.margin_by_customer` (§5) הוא היחיד שמחסר.

create or replace function app.payroll_task_alloc(p_from date, p_to date)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v jsonb;
begin
  perform app.require('dashboard.payroll');

  with a as (select * from app.payroll_task_amounts(p_from, p_to))
  select jsonb_build_object(
    'by_customer', (select coalesce(jsonb_agg(row_to_json(x)), '[]') from (
        select c.name, c.color, round(sum(a.amount), 2) as payroll,
               round(coalesce(sum(a.contractor_covered), 0), 2) as contractor_covered
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
                                      and a.customer_id is not null), 0), 2),
    -- הסכום שכבר שולם דרך הקבלן, מתוך `allocated`. מדווח ואינו מנוכה כאן.
    'contractor_covered',
                   round(coalesce((select sum(a.contractor_covered) from a
                                    where a.bucket = 'task' and not a.task_deleted
                                      and a.customer_id is not null), 0), 2))
    into v;

  return v;
end $$;

-- ===== 4. רווחיות פר-משימה: העלות מפסיקה לספור פעמיים ======================
--
-- ההגדרה זהה ל-0114 §4 פרט לשלוש שורות: `payroll` הוא `amount` פחות
-- ‏`contractor_covered`, השורה נושאת את ההפרש בשדה משלו, והסיכום והמונים
-- נושאים אותו גם הם. כל השאר — כולל `actual_hours` ו-`actual_workers` —
-- נשאר כפי שהוא: עובד הקבלן **אכן עבד** את השעות האלה, והמסך שמראה "מתוכנן
-- מול בפועל" מתאר עבודה, לא כסף.

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
      -- ‏0186: השכר שלנו הוא מה שהשעון הפיק **פחות** מה שמחיר הקבלן כבר
      -- שילם עליו. ‏`greatest(...,0)` אינו נחוץ — `contractor_covered` הוא
      -- תת-סכום של `amount` מאותה שורה — ואינו נכתב, כדי ששגיאה עתידית
      -- בהגדרה תיראה כמספר שלילי ולא תתחבא מאחורי רצפה.
      coalesce(a.amount, 0) - coalesce(a.contractor_covered, 0) as payroll,
      coalesce(a.contractor_covered, 0)                 as payroll_contractor_covered,
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
    left join app.task_revenue      tp  on tp.task_id = t.id
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
               'payroll_contractor_covered', round(r.payroll_contractor_covered, 2),
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
               'payroll_contractor_covered',
                                       round(coalesce(sum(f.payroll_contractor_covered), 0), 2),
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
               'unpriced_tasks',      count(*) filter (where f.unpriced),
               -- כמה משימות בטווח הן כאלה שניכינו בהן שעה ששולמה דרך קבלן.
               -- המסך אומר את זה במשפט אחד, כדי שהירידה בעלות לא תיראה
               -- כמספר שהשתנה בלי סיבה.
               'contractor_covered_tasks',
                                      count(*) filter (where f.payroll_contractor_covered > 0),
               'contractor_covered',  round(coalesce(sum(f.payroll_contractor_covered), 0), 2))
              from fin f))
    into v_out;

  return v_out;
end $$;

-- ===== 5. הסכומים הגלובליים ================================================
--
-- שלושתם מחברים היום `app.payroll_*` (ברוטו) ל-`sum(task_contractor_terms
-- .price)` ולכן סופרים פעמיים את אותה שעה. כולם מוגדרים מחדש **מהגרסה החיה
-- שלהם** (0114 §4) ולא מזו שיצרה אותם — העתקה מ-0044 או מ-0100 הייתה
-- מחזירה את הביטול והתוספות אחורה בלי שגיאה, רק עם מספרים שגויים. זו
-- האזהרה של 0114:185, והיא חלה גם כאן.
--
-- ‏`s.task_date between p_from and p_to` בשלושתם: הניכוי חייב להיות בדיוק
-- על מה שנוסף. צד הקבלן נמדד לפי **תאריך המשימה**, וצד השכר לפי **יום
-- ההחתמה**; משמרת שיומה בטווח ומשימתה מחוצה לו לא הוסיפה מחיר קבלן לסכום
-- הזה, ולכן אין ממה לנכות אותה.

create or replace function app.margin_summary(p_from date, p_to date)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_rev numeric; v_con numeric; v_cov numeric; v_pay jsonb; v_net numeric;
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

  -- ‏0186: השעות שמחיר הקבלן שמעליו כבר שילם עליהן. ‏`covered` כבר דורש
  -- משימה חיה ושורת terms, ולכן כאן נשאר רק חלון התאריכים.
  select coalesce(sum(s.amount), 0) into v_cov
    from app.payroll_task_spread(p_from, p_to) s
   where s.covered and s.task_date between p_from and p_to;

  v_net := round(coalesce((v_pay ->> 'total')::numeric, 0) - v_cov, 2);

  return jsonb_build_object(
    'revenue',    round(v_rev, 2),
    'contractor', round(v_con, 2),
    -- נטו: מה שהשעון הפיק, פחות מה שכבר שולם דרך הקבלן
    'payroll',    v_net,
    -- ושני המספרים שמהם הוא נבנה, כדי שההפרש יהיה ניתן ליישוב מול דוח הנוכחות
    'payroll_gross',      (v_pay -> 'total'),
    'contractor_covered', round(v_cov, 2),
    'gross',      round(v_rev - v_con - v_net, 2),
    'pct',        case when v_rev > 0
                       then round((v_rev - v_con - v_net) / v_rev * 100, 1) end,
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
        -- ‏0186: הניכוי יושב על ציר **יום ההחתמה**, כמו השכר שממנו הוא
        -- מנוכה, ולא על ציר תאריך המשימה. אחרת דלי שבו הקבלן תומחר בשבוע
        -- אחד והעובד שלו הוחתם בשבוע אחר היה יוצא עם שכר שלילי.
        select pt.bucket, pt.total - coalesce(cv.covered, 0) as total
          from (select (e ->> 'bucket')::date as bucket, (e ->> 'total')::numeric as total
                  from jsonb_array_elements(app.payroll_trend(p_from, p_to, v_b)) e) pt
          left join (
            select date_trunc(v_b, s.work_date)::date as bucket,
                   sum(s.amount) as covered
              from app.payroll_task_spread(p_from, p_to) s
             where s.covered and s.task_date between p_from and p_to
             group by 1) cv on cv.bucket = pt.bucket) p
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
               -- ‏0186: ההקצאה מחזירה ברוטו ואת החלק שהקבלן כיסה לצדו;
               -- הרווח מחסר, והדשבורד של השכר ממשיך להציג את הברוטו.
               round(coalesce((select (a ->> 'payroll')::numeric
                                      - coalesce((a ->> 'contractor_covered')::numeric, 0)
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
    'contractor_covered', (v_alloc -> 'contractor_covered'),
    'estimated', true)
    into v;
  return v;
end $$;

-- ===== 6. הדלת של המסך: מה שנוכה נאמר במפורש ===============================
--
-- ‏0114 §4 בחר **לא** להגדיר מחדש את `public.task_pnl`, כי הוא מרכיב טהור
-- מעל העוזרים ותיקון העוזרים מתקן אותו. זה נכון גם כאן לכל המספרים — ואינו
-- נכון לדבר אחד: `meta` נבנה כאן, מפתח אחר מפתח, ומפתח חדש אינו עולה אליו
-- מלמטה. בלעדיו העלות הייתה יורדת בשקט, ומי שמשווה לחודש שעבר היה מוצא
-- מספר אחר בלי שום משפט שמסביר אותו. ההגדרה זהה ל-0070 §4 פרט לשני
-- המפתחות ולמשפט שנוסף ל-`scope_note`.

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
      -- ‏0186: כמה כסף ובכמה משימות ניכינו שעות ששולמו דרך הקבלן
      'contractor_covered',       (v -> 'counters' -> 'contractor_covered'),
      'contractor_covered_tasks', (v -> 'counters' -> 'contractor_covered_tasks'),
      'truncated',           v_total > jsonb_array_length(coalesce(v_rows, '[]'::jsonb)),
      'scope_note',
        'המחיר ללקוח מחושב מהתכנון שהוזמן; עלות השכר נמדדת מהשעות שהוחתמו בפועל. '
        'שכר משמרת מתחלק בין משימותיה לפי שעות המשימה, ולכן השיוך משוער. '
        'משמרת שנמשכה אחרי חצות נרשמת ביום העבודה שלה ועשויה ליפול מחוץ לטווח. '
        'שכר שאינו משויך למשימה מופיע כ״לא משויך״ ואינו נספר באף שורה. '
        'שעה של עובד קבלן על משימה שהואצלה לקבלן שלו נספרת במחיר הקבלן בלבד, '
        'ואינה נספרת שוב כשכר.'));
end $$;
