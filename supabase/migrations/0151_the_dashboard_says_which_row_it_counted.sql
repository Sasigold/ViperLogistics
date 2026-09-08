-- 0151: הדשבורד אומר איזו שורה הוא ספר
--
-- כל אגרגט ב-`dashboard_stats` קיבץ לפי **שם**: `group by c.name, c.color`,
-- ‏`group by s.name, s.color`, וכן הלאה. זה נראה תמים כל עוד הגרף רק מצויר,
-- ומרגע שלוחצים עליו הוא הופך לבעיה — שם אינו כתובת. הלחיצה על "לקוח א׳"
-- צריכה לפתוח את הרשימה של לקוח א׳, ובלי id הלקוח אין לצד הלקוח דרך לומר
-- באיזה לקוח מדובר אלא לחפש את השם בטבלה ולקוות.
--
-- ‏**ושם גם אינו מפתח — בשלושה מתוך הארבעה.** ל-`customers.name` יש
-- ‏`customers_name_uq`, ולכן שם לקוח אכן מזהה לקוח. ל-`profiles.full_name`,
-- ל-`contractors.name` ול-`statuses.name` אין אילוץ ייחודיות כלל: שני עובדים
-- ששמם זהה — וזה קורה — נספרו עד כאן כשורה **אחת** שהמספר בה סכום של
-- שניהם. מספר סביר למראה שהוא פשוט לא נכון, ואף אחד לא יכול היה לגלות זאת
-- מהמסך. הקיבוץ לפי id מפריד אותם, וזו לא תופעת לוואי של השינוי אלא הסיבה
-- השנייה לעשותו.
--
-- ‏**מה לא נוגעים בו כאן ולמה.** ‏`dashboard_sections` מקבצת גם היא לפי שם
-- ב-`events.by_customer` וב-`events.funnel`, ונשארת כך: היא פונקציית
-- ‏plpgsql באורך מאות שורות שכל מיגרציה שנגעה בה העתיקה במלואה (0114, 0143,
-- ‏0145), והעתקה שלמה בשביל שני `group by` היא סיכון גדול מהתועלת. הצד
-- הקליינטי של אותם שני כרטיסים ממשיך לתרגם שם ל-id דרך רשימת הלקוחות
-- (`useCustomerDrill`), וזו בדיוק העקיפה שהמיגרציה הזאת מייתרת כאן.
--
-- ‏**החוזה עם הלקוח לא נשבר.** ‏`jsonb_agg(row_to_json(x))` מוסיף מפתח
-- ולא מסיר אחד: לקוח ישן שקורא `name`, `color` ו-`cnt` ממשיך לעבוד מול
-- שרת חדש, ולקוח חדש שקורא `id` מקבל `undefined` מול שרת ישן — ולכן
-- הירידה לפרטים בצד הלקוח נבנתה כ"אם יש id" ולא כהנחה.
--
-- הפונקציה מועתקת מ-0114 בשלמותה, באותה תבנית `pg_get_functiondef`
-- שהיא עצמה השאירה, ובאותיות גדולות מאותה סיבה — כדי שהחיפוש הבא ימצא
-- את הגרסה האחרונה ולא את זו שלפניה.


CREATE OR REPLACE FUNCTION public.dashboard_stats(p_from date, p_to date)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
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
         select c.id, c.name, c.color, count(*) as cnt from app.live_tasks t join customers c on c.id = t.customer_id
         where t.deleted_at is null and t.task_date between p_from and p_to
         group by c.id, c.name, c.color order by cnt desc limit 12) x)
      else null end,
    'by_contractor', case when app.has('dashboard.contractors') then
      (select coalesce(jsonb_agg(row_to_json(x)), '[]') from (
         -- 0105: דרך שורות ה-terms ולא דרך העמודה המשוקפת — משימה שהואצלה
         -- לשני קבלנים נספרת אצל שניהם, וזו בדיוק השאלה שהאריח שואל.
         select ct.id, ct.name, count(*) as cnt
           from task_contractor_terms tct
           join app.live_tasks t on t.id = tct.task_id
           join contractors ct on ct.id = tct.contractor_id
         where t.deleted_at is null and t.task_date between p_from and p_to
         group by ct.id, ct.name order by cnt desc limit 12) x)
      else null end,
    'by_worker', case when app.has('dashboard.all_workers') then
      (select coalesce(jsonb_agg(row_to_json(x)), '[]') from (
         select p.id, p.full_name as name, count(*) as cnt
         from task_assignments a
         join app.live_tasks t on t.id = a.task_id and t.deleted_at is null
           and t.task_date between p_from and p_to
         join profiles p on p.id = a.profile_id
         group by p.id, p.full_name order by cnt desc limit 12) x)
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
              select u.id, u.name, u.color, round(sum(u.total), 2) as total from (
                select c.id, c.name, c.color, coalesce(sum(tp2.price), 0) as total
                from app.task_revenue tp2
                join app.live_tasks t2 on t2.id = tp2.task_id and t2.deleted_at is null
                 and t2.task_date between p_from and p_to
                join customers c on c.id = t2.customer_id
                group by c.id, c.name, c.color
                union all
                select c.id, c.name, c.color, coalesce(sum(ei2.amount), 0)
                from event_income ei2
                join app.live_events e2 on e2.id = ei2.event_id and e2.deleted_at is null
                 and e2.event_date between p_from and p_to
                join customers c on c.id = e2.customer_id
                group by c.id, c.name, c.color) u
              group by u.id, u.name, u.color order by 4 desc limit 12) y)
           else null end)
       from app.task_revenue tp
       join app.live_tasks t on t.id = tp.task_id and t.deleted_at is null
        and t.task_date between p_from and p_to)
      else null end,
    'by_status', (select coalesce(jsonb_agg(row_to_json(x)), '[]') from (
       select s.id, s.name, s.color, count(*) as cnt from app.live_tasks t join statuses s on s.id = t.status_id
       where t.deleted_at is null and t.task_date between p_from and p_to
       group by s.id, s.name, s.color order by cnt desc) x),
    'next_events', (select coalesce(jsonb_agg(row_to_json(x)), '[]') from (
       select e.id, e.event_date, e.end_client_name, e.event_number, e.location_text
       from app.live_events e
       where e.deleted_at is null and e.event_date >= current_date
       order by e.event_date limit 5) x))
$function$;