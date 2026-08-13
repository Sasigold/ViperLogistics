-- 0063: מחזור החיים של סטטוס משימה
--
-- למשימה היו שישה סטטוסים. שלושה מהם — "בביצוע", "הושלם", "בוטל" — לא נשאו
-- שום משמעות שהמערכת פעלה לפיה: מי שסימן "הושלם" קיבל בדיוק את מה שקיבל מי
-- שלא סימן כלום. הם יורדים, ונשארים שלושה שכן מכריעים משהו:
--
--   טיוטה  (draft)    — המשימה בבנייה. העובד אינו רואה אותה בשום מקום.
--   מתוכנן (planned)  — התכנון סגור אבל טרם פורסם. גם כאן העובד אינו רואה.
--   משובץ  (assigned) — פורסם. מכאן העובד רואה: בלו״ז, בלוח המשמרות שלו,
--                        ומכאן הוא גם מקבל התראות (0064).
--
-- שתי החלטות שיושבות כאן:
--
-- 1. `code`, ולא השם. את השם אפשר לערוך ממסך ההגדרות, וכלל ראייה שנשען על
--    המחרוזת "משובץ" נשבר ברגע שמישהו מקליד "שובץ". זו בדיוק ההנמקה של 0036
--    על סטטוסי אירוע, ואותה עמודה משרתת כאן.
--
-- 2. הסתרה בשרת, ולא במסך. משמרת שלא מוצגת אבל כן חוזרת מה-API היא משמרת
--    שדולפת דרך כל לקוח אחר, ולכן שני נתיבי הקריאה של העובד — הפוליסה על
--    tasks ומנוע גזירת המשמרות — נסגרים כאן ולא ב-TSX.

-- ===== 1. שלושת הסטטוסים שנשארים ==========================================
-- נכתבים מחדש ולא נמחקים-ונוצרים: tasks.status_id מצביע עליהם.

update statuses set code = 'draft',    color = '#94a3b8', sort_order = 1, is_terminal = false
  where entity = 'task' and code is null and name = 'טיוטה';
update statuses set code = 'planned',  color = '#3b82f6', sort_order = 2, is_terminal = false
  where entity = 'task' and code is null and name = 'מתוכנן';
update statuses set code = 'assigned', color = '#8b5cf6', sort_order = 3, is_terminal = false
  where entity = 'task' and code is null and name = 'משובץ';

-- מסד שעבר עריכה ידנית עלול לא להחזיק את אחד מהשמות. השלמה, בלי לגעת
-- בברירת המחדל — `statuses_one_default` מתיר אחת בלבד לישות.
insert into statuses (entity, name, color, sort_order, is_default, is_terminal, code)
select 'task', v.name, v.color, v.sort_order, false, false, v.code
from (values
  ('טיוטה',  '#94a3b8', 1, 'draft'),
  ('מתוכנן', '#3b82f6', 2, 'planned'),
  ('משובץ',  '#8b5cf6', 3, 'assigned')
) as v(name, color, sort_order, code)
where not exists (
  select 1 from statuses s
   where s.entity = 'task' and s.code = v.code and s.deleted_at is null);

-- ===== 2. שלושת הסטטוסים שיורדים ==========================================
--
-- קודם מעבירים את המשימות, ורק אחר כך מוחקים. "בביצוע" ו"הושלם" מתארים
-- עבודה שכבר פורסמה לעובד, ולכן היעד שלהן הוא "משובץ" — אחרת משמרת שכבר
-- נעבדה הייתה נעלמת מהלוח של מי שעבד בה. "בוטל" מתאר עבודה שלא תתבצע,
-- והיעד שלה הוא "מתוכנן": מחוץ לעיני העובד, כמו שהיא.

update tasks t set status_id = (
    select s.id from statuses s
     where s.entity = 'task' and s.code = 'assigned' and s.deleted_at is null limit 1)
  where t.status_id in (
    select s.id from statuses s where s.entity = 'task' and s.name in ('בביצוע', 'הושלם'));

update tasks t set status_id = (
    select s.id from statuses s
     where s.entity = 'task' and s.code = 'planned' and s.deleted_at is null limit 1)
  where t.status_id in (
    select s.id from statuses s where s.entity = 'task' and s.name = 'בוטל');

-- מחיקה רכה ולא קשה: audit_log ודוחות שמורים מצביעים על המזהים האלה, וסל
-- המיחזור הוא ממילא הדרך שבה כל שאר הקטלוגים במערכת נסגרים.
update statuses
   set deleted_at = coalesce(deleted_at, now()), is_active = false, is_default = false
 where entity = 'task' and code is null
   and name in ('בביצוע', 'הושלם', 'בוטל');

-- ===== 3. ברירת המחדל היא טיוטה ===========================================
--
-- כל נתיבי היצירה — create_event, add_event_task, duplicate_task, הייבוא
-- ומסך המשימות — שולפים `where is_default`, ולכן ההיפוך הזה הוא כל מה
-- שנדרש כדי שמשימה חדשה תיוולד כטיוטה.
--
-- שתי הוראות ולא אחת: `statuses_one_default` הוא אינדקס ייחודי חלקי שנבדק
-- מיד, ו-UPDATE אחד שמזיז את הדגל בין שתי שורות היה מתנגש בעצמו.

update statuses set is_default = false
 where entity = 'task' and is_default and coalesce(code, '') <> 'draft';

update statuses set is_default = true
 where entity = 'task' and code = 'draft' and deleted_at is null
   and not exists (select 1 from statuses
                    where entity = 'task' and is_default and deleted_at is null);

-- ===== 4. מי רואה משימה שטרם פורסמה =======================================
--
-- "עובד" ו"רכז" הם אותו user_kind, ולכן ההבחנה אינה יכולה להיות עליו. מה
-- שמבחין ביניהם הוא היכולת לתכנן: מי שרשאי ליצור או לערוך משימה, או לפתוח
-- את לוח העבודה, חייב לראות טיוטות — הוא זה שכותב אותן. מי שכל זיקתו
-- למשימה היא שהוא משובץ אליה רואה רק את מה שפורסם.
--
-- הפונקציה נפרדת ולא מוטמעת בפוליסה משתי סיבות: היא נקראת פעם אחת לשאילתה
-- כ-InitPlan (0028), ויש רק מקום אחד לתקן בו אם ההגדרה תשתנה.
--
-- `board.view` *אינו* ברשימה, ולא במקרה: הוא implied_by של tasks.view (0011),
-- ו-tasks.view דלוק בברירת המחדל של קהל ה-staff — כלומר כל עובד שטח מחזיק
-- אותו בירושה. שער שנשען עליו היה פתוח לכולם. tasks.create ו-tasks.edit הם
-- מפתחות עצמאיים שנולדים כבויים, וזו ההבחנה האמיתית בין מי שכותב את המשימה
-- לבין מי שמופיע אליה.
create or replace function app.can_plan_tasks() returns boolean
language sql stable security definer set search_path = public as $$
  select app.is_admin()
      or app.has('tasks.create')
      or app.has('tasks.edit')
$$;

-- אותה פוליסה של 0013, בתוספת התנאי היחיד שלמעלה. שאר הזרועות — טווחי
-- ההרשאה, הלקוח והקבלן — זהות מילה במילה.
drop policy tasks_select on tasks;
create policy tasks_select on tasks for select to authenticated using (
  (select app.is_admin())
  or (deleted_at is null
    and ((select app.scope_ids('tasks', 'customers')) is null
         or customer_id = any((select app.scope_ids('tasks', 'customers'))::uuid[]))
    and ((select app.scope_ids('tasks', 'contractors')) is null
         or contractor_id = any((select app.scope_ids('tasks', 'contractors'))::uuid[]))
    and ((select app.scope_ids('tasks', 'task_types')) is null
         or task_type_id = any((select app.scope_ids('tasks', 'task_types'))::uuid[]))
    and ((select app.scope_ids('tasks', 'statuses')) is null
         or status_id = any((select app.scope_ids('tasks', 'statuses'))::uuid[]))
    and ((select app.scope_ids('tasks', 'execution_methods')) is null
         or execution_method_id = any((select app.scope_ids('tasks', 'execution_methods'))::uuid[]))
    and ((select app.scope_ids('tasks', 'trucks')) is null
         or truck_id = any((select app.scope_ids('tasks', 'trucks'))::uuid[]))
    and ((select app.scope_date_from('tasks')) is null
         or task_date >= (select app.scope_date_from('tasks')))
    and ((select app.scope_date_to('tasks')) is null
         or task_date <= (select app.scope_date_to('tasks')))
    and (not (select app.scope_own('tasks'))
         or created_by = (select app.profile_id())
         or exists (select 1 from task_assignments a
                    where a.task_id = tasks.id and a.profile_id = (select app.profile_id())))
    -- ⟵ החדש: טיוטה ומתוכנן אינם מגיעים לעובד שרק משובץ. ההשוואה היא מול
    -- תת-שאילתה עטופה ולא מול join, כדי שהיא תיפתר פעם אחת לשאילתה כ-InitPlan
    -- ולא פעם לכל שורה — אותה סיבה שבגללה כל שאר הזרועות כאן עטופות (0028).
    and ((select app.user_kind()) <> 'staff'
         or (select app.can_plan_tasks())
         or created_by = (select app.profile_id())
         or status_id = (select s.id from statuses s
                          where s.entity = 'task' and s.code = 'assigned'
                            and s.deleted_at is null limit 1))
    and (
      ((select app.user_kind()) = 'staff' and (select app.has('tasks.view')))
      or ((select app.user_kind()) = 'customer_user' and customer_id = (select app.customer_id()))
      or ((select app.user_kind()) = 'contractor_user' and contractor_id = (select app.contractor_id()))
      or exists (select 1 from task_assignments a
                 where a.task_id = tasks.id and a.profile_id = (select app.profile_id()))
    )));

-- ===== 5. משמרת נגזרת רק ממשימה שפורסמה ===================================
--
-- app.planned_shifts_many היא security definer, ולכן הפוליסה שלמעלה אינה
-- חלה עליה כלל — וזה הנתיב שמזין את /my/schedule, את לוח המשמרות של הצוות,
-- את השעון ואת הדיווח הידני. בלי התנאי כאן, "העובד לא רואה כלום" היה נכון
-- בלוח ושקרי בכל מקום שבו הוא באמת מסתכל.
--
-- הסינון אינו מותנה בקורא: משמרת אינה "מה שמותר לי לראות" אלא "מה שנקבע
-- שיקרה", ומשימה שלא פורסמה טרם נקבעה. גם המנהל, שרואה את המשימה בלוח
-- העבודה, אינו רואה עבורה משמרת עד שהיא משובצת.
--
-- זהה ל-0034 מלבד שתי השורות ב-`base`: ה-join אל statuses והתנאי עליו.
create or replace function app.planned_shifts_many(
  p_profile_ids uuid[], p_from date, p_to date)
returns setof app.planned_shift_row
language plpgsql stable security definer set search_path = public as $$
declare v_gap interval;
begin
  v_gap := make_interval(mins => coalesce(
    (app.attendance_config('attendance.clock') ->> 'merge_gap_minutes')::int, 120));

  return query
  with mine as (
    select a.profile_id as pid, a.task_id as tid,
           bool_or(a.work_site = 'warehouse') as is_wh
      from task_assignments a
     where a.profile_id = any(p_profile_ids)
     group by a.profile_id, a.task_id
    union all
    select pr.id, w.task_id, bool_or(w.work_site = 'warehouse')
      from task_contractor_workers w
      join profiles pr on pr.contractor_worker_id = w.contractor_worker_id
     where pr.id = any(p_profile_ids)
     group by pr.id, w.task_id
  ),
  dedup as (
    select m.pid, m.tid, bool_or(m.is_wh) as is_wh
      from mine m group by m.pid, m.tid
  ),
  travel as (
    select u.tid, coalesce(app.task_travel_hours(u.tid), 0) as hrs
      from (select distinct d.tid from dedup d) u
  ),
  base as (
    select
      d.pid as b_pid,
      t.id as b_task,
      t.customer_id as b_cust,
      c.color as b_color,
      coalesce(nullif(t.title, ''), tt.name) as b_label,
      case when d.is_wh then 'warehouse' else 'field' end as b_site,
      ((t.task_date + case
          when d.is_wh and t.warehouse_start_time is not null then t.warehouse_start_time
          else coalesce(t.onsite_start_time, t.warehouse_start_time) end)
        at time zone 'Asia/Jerusalem') as b_start,
      ((t.task_date + coalesce(t.onsite_start_time, t.warehouse_start_time))
        at time zone 'Asia/Jerusalem')
        + make_interval(mins => round(coalesce(t.hours_count, 0) * 60)::int) as b_end,
      tv.hrs as b_travel,
      case when d.is_wh then wh.lat else e.location_lat end as b_start_lat,
      case when d.is_wh then wh.lng else e.location_lng end as b_start_lng,
      e.location_lat as b_end_lat,
      e.location_lng as b_end_lng,
      case when d.is_wh then wh.id end   as b_wh_id,
      case when d.is_wh then wh.name end as b_wh_name
    from dedup d
    join tasks t on t.id = d.tid
    join travel tv on tv.tid = d.tid
    left join events e on e.id = t.event_id
    left join customers c on c.id = t.customer_id
    left join warehouses wh
           on wh.id = coalesce(t.warehouse_id, c.warehouse_id)
          and wh.deleted_at is null
    join task_types tt on tt.id = t.task_type_id
    join statuses st on st.id = t.status_id
    where t.deleted_at is null
      and t.task_date between p_from and p_to
      and coalesce(t.onsite_start_time, t.warehouse_start_time) is not null
      -- משימה שטרם פורסמה אינה משמרת
      and st.code = 'assigned'
  ),
  ordered as (
    select b.*,
           max(b.b_end) over (
             partition by b.b_pid
             order by b.b_start, b.b_task
             rows between unbounded preceding and 1 preceding) as b_prev_end
    from base b
  ),
  flagged as (
    select o.*, case when o.b_prev_end is null or o.b_start - o.b_prev_end > v_gap
                     then 1 else 0 end as b_new
    from ordered o
  ),
  grouped as (
    select f.*, sum(f.b_new) over (
             partition by f.b_pid
             order by f.b_start, f.b_task
             rows between unbounded preceding and current row) as b_grp
    from flagged f
  ),
  shifts as (
    select
      g.b_pid        as s_pid,
      min(g.b_start) as s_start,
      max(g.b_end)   as s_core_end,
      (array_agg(g.b_travel   order by g.b_end desc, g.b_task desc))[1] as s_travel,
      (array_agg(g.b_task     order by g.b_end desc, g.b_task desc))[1] as s_last,
      (array_agg(g.b_end_lat  order by g.b_end desc, g.b_task desc))[1] as s_last_lat,
      (array_agg(g.b_end_lng  order by g.b_end desc, g.b_task desc))[1] as s_last_lng,
      (array_agg(g.b_task     order by g.b_start, g.b_task))[1] as s_first,
      (array_agg(g.b_site     order by g.b_start, g.b_task))[1] as s_site,
      (array_agg(g.b_start_lat order by g.b_start, g.b_task))[1] as s_first_lat,
      (array_agg(g.b_start_lng order by g.b_start, g.b_task))[1] as s_first_lng,
      (array_agg(g.b_label    order by g.b_start, g.b_task))[1] as s_label,
      (array_agg(g.b_cust     order by g.b_start, g.b_task))[1] as s_cust,
      (array_agg(g.b_color    order by g.b_start, g.b_task))[1] as s_color,
      (array_agg(g.b_wh_id    order by g.b_start, g.b_task))[1] as s_wh_id,
      (array_agg(g.b_wh_name  order by g.b_start, g.b_task))[1] as s_wh_name,
      array_agg(g.b_task order by g.b_start, g.b_task) as s_ids,
      count(*) as s_count
    from grouped g
    group by g.b_pid, g.b_grp
  )
  select
    s.s_pid,
    (s.s_start at time zone 'Asia/Jerusalem')::date,
    (row_number() over (
       partition by s.s_pid, (s.s_start at time zone 'Asia/Jerusalem')::date
       order by s.s_start))::int,
    s.s_start,
    s.s_core_end + make_interval(mins => round(s.s_travel * 60)::int),
    round((extract(epoch from
      (s.s_core_end + make_interval(mins => round(s.s_travel * 60)::int) - s.s_start)
      ) / 3600.0)::numeric, 2),
    s.s_site,
    s.s_ids,
    s.s_first,
    s.s_last,
    s.s_first_lat, s.s_first_lng,
    s.s_last_lat,  s.s_last_lng,
    s.s_travel,
    case when s.s_count > 1 then s.s_label || ' +' || (s.s_count - 1)::text else s.s_label end,
    s.s_cust,
    s.s_color,
    s.s_wh_id,
    s.s_wh_name
  from shifts s
  order by s.s_pid, s.s_start;
end $$;

-- הצירוף שהתנאי החדש שואל עליו — משימה חיה בטווח תאריכים, לפי סטטוס.
create index if not exists tasks_status_date_idx
  on tasks (status_id, task_date) where deleted_at is null;

-- ===== 6. "פתוח" ו"באיחור" בדשבורד ========================================
--
-- שני המדדים נמדדו לפי `not s.is_terminal`, כלומר "לא הושלם ולא בוטל".
-- אחרי שסעיף 2 הוריד את שני הסטטוסים האלה אין למשימה סטטוס סוגר בכלל,
-- והמדד היה מחזיר את *כל* ההיסטוריה כמשימות פתוחות ובאיחור.
--
-- ההבחנה שנשארה משמעותית היא הפרסום: משימה שטרם הגיעה לעובד היא עבודה
-- שעדיין מחכה למישהו, ומשימה כזו שתאריכה כבר עבר היא בדיוק "פוספסה".
-- אותה הגדרה בדיוק יושבת בלוח העבודה (grouping.ts) ובווידג'ט הרשימה.
--
-- שאר הגוף זהה ל-0026 מילה במילה; סטטוס אירוע ממשיך להיקרא לפי is_terminal
-- כי שם "הושלם" ו"בוטל" עדיין קיימים.
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
    -- מונה את סגל הצוות, ולכן שייך למי שרשאי לראות סטטיסטיקות של כל העובדים
    'available_workers', case when app.has('dashboard.all_workers') then
      (select count(*) from profiles p
         where p.deleted_at is null and p.is_active and p.user_kind = 'staff'
           and not exists (select 1 from task_assignments a join tasks t on t.id = a.task_id
                           where a.profile_id = p.id and t.task_date = current_date
                             and t.deleted_at is null))
      else null end,
    -- ללקוח יש לקוח אחד: הגרף היה עמודה בודדת ששמה את שם החברה שלו על המסך
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
         'total', coalesce(sum(tp.price), 0),
         'priced_tasks', count(*) filter (where tp.price is not null),
         'by_customer', case when app.has('customers.view') then
           (select coalesce(jsonb_agg(row_to_json(y)), '[]') from (
              select c.name, c.color, coalesce(sum(tp2.price), 0) as total
              from task_pricing tp2
              join tasks t2 on t2.id = tp2.task_id and t2.deleted_at is null
               and t2.task_date between p_from and p_to
              join customers c on c.id = t2.customer_id
              group by c.name, c.color order by 3 desc limit 12) y)
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
