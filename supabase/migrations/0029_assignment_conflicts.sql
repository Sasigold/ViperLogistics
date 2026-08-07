-- 0029: כפל-שיבוץ
--
-- עד עכשיו אפשר היה לשבץ את אותו עובד, נהג, ראש צוות, עובד קבלן או משאית
-- לשתי משימות שרצות באותה שעה, ושום דבר במערכת לא אמר מילה. בדיקת החפיפה
-- היחידה שהייתה קיימת היא app.attendance_overlap (0024), והיא עוסקת רק
-- בדיווח נוכחות עצמי — כלומר בכסף שכבר שולם, לא בשיבוץ שנוצר.
--
-- ההכרעה יושבת ב-SQL ולא בדפדפן מאותה סיבה שחישוב המשמרת יושב שם: מי
-- שמשבץ מלוח העבודה, מהיומן או מהמגירה חייב לקבל את אותה תשובה, ומימוש
-- שני היה נפרד מהראשון תוך שבוע.

-- ===== חלון העבודה של משימה ========================================
--
-- אותה נוסחה שמרכיבה משמרת ב-app.planned_shifts: מי שיוצא מהמחסן מתחיל
-- ב-warehouse_start_time, כל השאר ב-onsite_start_time, והסיום הוא תחילת
-- העבודה בשטח ועוד hours_count.
--
-- הנסיעה חזרה אינה נכללת, בדיוק כפי ש-planned_shifts אינו כולל אותה במדידת
-- הפער: היא נגזרת מאזור הגיאופנס, ועריכה של אזור הייתה מייצרת ומבטלת
-- התנגשויות על שיבוצים ישנים שאיש לא נגע בהם.
create or replace function app.task_window(p_task_id uuid, p_from_warehouse boolean)
returns tstzrange language sql stable set search_path = public as $$
  select tstzrange(
    ((t.task_date + case
        when p_from_warehouse and t.warehouse_start_time is not null then t.warehouse_start_time
        else coalesce(t.onsite_start_time, t.warehouse_start_time) end)
      at time zone 'Asia/Jerusalem'),
    ((t.task_date + coalesce(t.onsite_start_time, t.warehouse_start_time))
      at time zone 'Asia/Jerusalem')
      + make_interval(mins => round(coalesce(t.hours_count, 0) * 60)::int),
    '[)')
  from tasks t
  where t.id = p_task_id
    and coalesce(t.onsite_start_time, t.warehouse_start_time) is not null
$$;

-- ===== ההתנגשויות של משימה =========================================
--
-- הפונקציה היא SECURITY INVOKER במכוון, בניגוד לרוב ה-RPCs כאן. משמעות
-- הדבר שהיא מדווחת רק על התנגשות עם משימה שהקורא רשאי לראות ממילא.
-- החלופה — DEFINER שרואה הכול — הייתה מדליפה קיום ושעות של משימות מחוץ
-- להיקף הנתונים של הקורא, וזה בדיוק מה ש-permission_scopes קיים כדי למנוע.
-- למי שהיקף המשימות שלו אינו מוגבל, וזה המצב של כל מי שמשבץ, התשובה מלאה.
--
-- p_extra_profiles מאפשר לשאול "מה יקרה אם אשבץ גם את X" לפני השמירה, ולא
-- רק אחריה.
create or replace function assignment_conflicts(
  p_task_id uuid,
  p_extra_profiles uuid[] default '{}')
returns jsonb language sql stable set search_path = public as $$
  with target as (
    select t.id, t.truck_id,
           app.task_window(t.id, true)  as win_wh,
           app.task_window(t.id, false) as win_field
    from tasks t
    where t.id = p_task_id and t.deleted_at is null
  ),
  -- מי שנבדק: המשובצים בפועל, מי שנשקל להוספה, עובדי הקבלן, והמשאית
  subjects as (
    select 'worker'::text as kind, a.profile_id as subject_id, a.role::text as role,
           bool_or(a.work_site = 'warehouse') as from_wh
      from task_assignments a
     where a.task_id = p_task_id
     group by a.profile_id, a.role
    union all
    select 'worker', x.pid, null, false
      from unnest(coalesce(p_extra_profiles, '{}')) as x(pid)
     where not exists (select 1 from task_assignments a
                        where a.task_id = p_task_id and a.profile_id = x.pid)
    union all
    select 'contractor_worker', w.contractor_worker_id, null,
           bool_or(w.work_site = 'warehouse')
      from task_contractor_workers w
     where w.task_id = p_task_id
     group by w.contractor_worker_id
  ),
  -- החלון של המשימה הנבדקת, לפי נקודת ההתחלה של אותו משובץ
  subject_win as (
    select s.*, case when s.from_wh then tg.win_wh else tg.win_field end as win
    from subjects s cross join target tg
  ),
  -- אותו אדם על משימה אחרת, בכל אחד משני נתיבי השיבוץ
  elsewhere as (
    select sw.kind, sw.subject_id, sw.role, o.task_id as other_id,
           case when bool_or(o.from_wh) then app.task_window(o.task_id, true)
                else app.task_window(o.task_id, false) end as other_win,
           sw.win
    from subject_win sw
    join lateral (
      select a.task_id, (a.work_site = 'warehouse') as from_wh
        from task_assignments a
       where sw.kind = 'worker' and a.profile_id = sw.subject_id and a.task_id <> p_task_id
      union all
      select w.task_id, (w.work_site = 'warehouse')
        from task_contractor_workers w
       where sw.kind = 'contractor_worker'
         and w.contractor_worker_id = sw.subject_id and w.task_id <> p_task_id
    ) o on true
    group by sw.kind, sw.subject_id, sw.role, o.task_id, sw.win
  ),
  -- משאית: תכונה של המשימה עצמה ושל השיבוץ, ושתיהן נספרות
  trucks_used as (
    select distinct tr.truck_id
    from (
      select tg.truck_id from target tg where tg.truck_id is not null
      union
      select a.truck_id from task_assignments a
       where a.task_id = p_task_id and a.truck_id is not null
    ) tr
  ),
  truck_elsewhere as (
    select 'truck'::text as kind, tu.truck_id as subject_id, null::text as role,
           o.task_id as other_id, app.task_window(o.task_id, true) as other_win,
           (select tg.win_wh from target tg) as win
    from trucks_used tu
    join lateral (
      select t2.id as task_id from tasks t2
       where t2.truck_id = tu.truck_id and t2.id <> p_task_id and t2.deleted_at is null
      union
      select a2.task_id from task_assignments a2
       where a2.truck_id = tu.truck_id and a2.task_id <> p_task_id
    ) o on true
  ),
  hits as (
    select * from elsewhere
    union all
    select kind, subject_id, role, other_id, other_win, win from truck_elsewhere
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'kind',          h.kind,
    'subject_id',    h.subject_id,
    'subject_name',  case h.kind
                       when 'worker' then (select p.full_name from profiles p where p.id = h.subject_id)
                       when 'contractor_worker' then (select cw.full_name from contractor_workers cw where cw.id = h.subject_id)
                       else (select tr.name from trucks tr where tr.id = h.subject_id) end,
    'role',          h.role,
    'task_id',       h.other_id,
    'task_label',    (select coalesce(nullif(t2.title, ''), tt.name)
                        from tasks t2 join task_types tt on tt.id = t2.task_type_id
                       where t2.id = h.other_id),
    'customer_name', (select c.name from tasks t2 join customers c on c.id = t2.customer_id
                       where t2.id = h.other_id),
    'task_date',     (select t2.task_date from tasks t2 where t2.id = h.other_id),
    'starts_at',     lower(h.other_win),
    'ends_at',       upper(h.other_win))
    order by lower(h.other_win)), '[]'::jsonb)
  from hits h
  -- החפיפה עצמה. שתי משימות בפער של 90 דקות מתמזגות למשמרת אחת ב-
  -- planned_shifts אבל אינן חופפות, ולכן הן אינן התנגשות — וזה ההבדל
  -- שהבדיקה בחבילה שומרת עליו.
  where h.win && h.other_win
    and not isempty(h.win) and not isempty(h.other_win)
$$;

revoke execute on function public.assignment_conflicts(uuid, uuid[]) from anon, public;

comment on function public.assignment_conflicts(uuid, uuid[]) is
  'התנגשויות שיבוץ של משימה: מי מהמשובצים עליה משובץ גם למשימה חופפת. '
  'SECURITY INVOKER — מדווח רק על משימות שהקורא רשאי לראות.';
