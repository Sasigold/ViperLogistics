-- 0083: הלו״ז מראה רק מה שפורסם, והמשמרת נקראת כמו יום עבודה
--
-- שלושה דיווחים, כולם על מה שעובד השטח קורא במסך:
--
--   * בלו״ז הוא עדיין רואה משימות שאינן "משובץ". ‏0081 הוציא את `created_by`
--     מזרוע ה-scope_own והשאיר אותה בשער הפרסום — ולכן חשבון של עובד שיצר
--     משימה אי-פעם ממשיך לראות אותה כטיוטה. בשטח זה נראה כשלוש טיוטות שאיש
--     אינו משובץ אליהן, על הלו״ז של עובד.
--   * בפרטי המשמרת שעת המחסן והנסיעה נבלעו בתוך זמן המשימה: המשימה הוצגה
--     כ-06:00–10:00 בעוד שהיא בת שלוש שעות, כי ההתחלה שלה נלקחה מהמחסן.
--     שלושת המרכיבים הם שלושה דברים שונים ביום של העובד, ולכן הם נספרים
--     בנפרד ומוצגים בנפרד.
--   * וראש הצוות צריך מתוך המשימה שני דברים שהעובד אינו צריך: את איש הקשר
--     של הלקוח, ואת מי מהצוות מגיע למחסן ומי לשטח.

-- ===== 1. שער הפרסום: מה שלא פורסם אינו על הלוח, גם למי שיצר אותו =========
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
    -- ‏0081: לעובד שטח "שלי" הוא השיבוץ; היצירה נשארת זרוע רק למי שאינו staff
    and (not (select app.scope_own('tasks'))
         or exists (select 1 from task_assignments a
                    where a.task_id = tasks.id and a.profile_id = (select app.profile_id()))
         or ((select app.user_kind()) <> 'staff'
             and created_by = (select app.profile_id())))
    -- ‏0083: ‏0081 הוציא את היצירה מזרוע ה-scope_own והשאיר אותה כאן, בשער
    -- הפרסום — ולכן עובד שטח שחשבונו יצר משימה המשיך לראות אותה כטיוטה.
    -- זה מה שנצפה בשטח: שלוש טיוטות שאיש אינו משובץ אליהן, על הלו״ז שלו.
    --
    -- אבל היצירה אינה חסרת משמעות לכולם: מי שמזין אירוע בלי להחזיק
    -- tasks.edit — מנהלת כספים, למשל — יוצר בכך משימות שנולדות כטיוטה,
    -- ובלי הזרוע הזו הן היו נעלמות ממנו ברגע היצירה. מה שמפריד בין השניים
    -- הוא ההיקף: `own` פירושו "כל זיקתי למשימות היא השיבוץ" (0081), וזה
    -- בדיוק הקהל שאצלו היצירה אינה אמורה לפתוח דבר.
    and ((select app.user_kind()) <> 'staff'
         or (select app.can_plan_tasks())
         or (created_by = (select app.profile_id())
             and not (select app.scope_own('tasks')))
         or status_id = (select s.id from statuses s
                          where s.entity = 'task' and s.code = 'assigned'
                            and s.deleted_at is null limit 1))
    and (
      ((select app.user_kind()) = 'staff' and (select app.has('tasks.view')))
      or ((select app.user_kind()) = 'customer_user' and customer_id = (select app.customer_id()))
      or ((select app.user_kind()) = 'contractor_user'
          and contractor_id = (select app.contractor_id())
          and ((select app.has('portal.view'))
               or (status_id = (select s.id from statuses s
                                 where s.entity = 'task' and s.code = 'assigned'
                                   and s.deleted_at is null limit 1)
                   and (select app.on_task_as_contractor_worker(tasks.id)))))
      or exists (select 1 from task_assignments a
                 where a.task_id = tasks.id and a.profile_id = (select app.profile_id()))
    )));

-- ===== 2. המשמרת נקראת כמו יום עבודה =======================================
--
-- שלושה מרכיבים, שלוש שורות. עד כאן `start_at` של משימה היה שעת המחסן כשמי
-- שקורא יוצא ממנו, ולכן הכרטיס הציג "06:00–10:00" למשימה בת שלוש שעות:
-- הנסיעה למחסן נבלעה בתוך המשימה, ומי שקרא לא יכול היה לדעת מתי הוא באמת
-- מתחיל לעבוד. עכשיו:
--
--   * `warehouse_start_at` — היציאה מהמחסן, שדה משלה ו-null למי שמגיע לשטח.
--   * `start_at` — תחילת העבודה בשטח, כלומר המשימה עצמה.
--   * והנסיעה חזרה כבר יושבת ב-`totals.travel_hours` מאז 0079.
--
-- `shift.start` נשארת מה שהיא הייתה — המוקדם מבין השניים — כי זו השעה
-- ש-`app.planned_shifts_many` קובעת, ושתי התשובות חייבות להסכים.
--
-- ובנוסף שני דברים לראש הצוות של האירוע (0082): איש הקשר, ונקודת ההתחלה של
-- כל אחד מהצוות. שניהם נגזרים כאן ולא במסך, כי הפונקציה היא security definer
-- והמסך אינו יכול לשאול את הטבלאות בעצמו.
create or replace function shift_task_breakdown(p_profile_id uuid, p_task_ids uuid[])
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_ids      uuid[];
  v_staffing boolean;
  v_name     text;
  v_tasks    jsonb;
  v_travel   numeric;
begin
  -- ההרשאה זהה מילה במילה לזו של employee_shifts (0020): אותם נתונים,
  -- אותה סמכות. כל סטייה כאן הייתה דלת צדדית לאותו מידע.
  if p_profile_id = app.profile_id() then
    perform app.require('attendance.view_schedule');
  elsif app.user_kind() = 'contractor_user' then
    if not (app.has('portal.attendance') and app.is_my_contractor_staff(p_profile_id)) then
      raise exception 'אין לך הרשאה לצפות במשמרות של עובד זה' using errcode = '42501';
    end if;
  else
    perform app.require('attendance.view_all');
  end if;

  select array_agg(distinct u) into v_ids
    from unnest(coalesce(p_task_ids, '{}'::uuid[])) u;

  select p.full_name into v_name from profiles p where p.id = p_profile_id;

  if v_ids is null then
    return jsonb_build_object(
      'profile_id', p_profile_id, 'full_name', v_name,
      'tasks', '[]'::jsonb,
      'totals', jsonb_build_object('tasks', 0, 'work_hours', 0,
                                   'travel_hours', 0, 'idle_minutes', 0),
      'shift', jsonb_build_object('start', null, 'end', null,
                                  'work_site', null, 'warehouse_name', null));
  end if;

  -- מי עוד משובץ למשימה הוא מידע על אנשים אחרים, ולכן הוא רוכב על המפתח
  -- שכבר שולט בו בלוח העבודה, ולא על עצם הצפייה במשמרת.
  v_staffing := app.is_admin() or app.has('board.view_staffing');

  with mine as (
    select a.task_id as tid,
           bool_or(a.work_site = 'warehouse') as is_wh,
           (array_agg(a.role::text order by case a.role
              when 'team_lead' then 0 when 'driver' then 1 else 2 end))[1] as my_role,
           (array_agg(a.truck_id) filter (where a.truck_id is not null))[1] as my_truck
      from task_assignments a
     where a.profile_id = p_profile_id and a.task_id = any(v_ids)
     group by a.task_id
    union all
    select w.task_id, bool_or(w.work_site = 'warehouse'), null::text, null::uuid
      from task_contractor_workers w
      join profiles pr on pr.contractor_worker_id = w.contractor_worker_id
     where pr.id = p_profile_id and w.task_id = any(v_ids)
     group by w.task_id
  ),
  d as (
    -- אין ל-uuid אגרגט max, ולכן המשאית נבחרת דרך array_agg כמו בגזירה עצמה.
    select m.tid, bool_or(m.is_wh) as is_wh,
           min(m.my_role) as my_role,
           (array_agg(m.my_truck) filter (where m.my_truck is not null))[1] as my_truck
      from mine m group by m.tid
  ),
  enriched as (
    select
      t.id as task_id,
      d.is_wh, d.my_role,
      coalesce(nullif(t.title, ''), tt.name) as title,
      tt.name as type_name, tt.code as type_code,
      t.customer_id, c.name as cust_name, c.color as cust_color,
      t.event_id, e.event_number, e.end_client_name,
      coalesce(nullif(t.location_text, ''), e.location_text) as location_text,
      e.location_lat, e.location_lng,
      t.hours_count, t.worker_count, t.notes,
      st.name as status_name, st.color as status_color,
      coalesce(tr.name, nullif(t.truck_free_text, '')) as truck_name,
      em.name as method_name,
      wh.id as wh_id, wh.name as wh_name,
      coalesce(app.task_travel_hours(t.id), 0) as travel,
      -- ‏0083: היציאה מהמחסן היא שדה משלה, ולא ההתחלה של המשימה. null למי
      -- שמגיע לשטח, ו-null גם כשאין למשימה שעת מחסן — אז אין ממה לצאת.
      case when d.is_wh and t.warehouse_start_time is not null
           then ((t.task_date + t.warehouse_start_time) at time zone 'Asia/Jerusalem')
      end as wh_start_at,
      ((t.task_date + coalesce(t.onsite_start_time, t.warehouse_start_time))
        at time zone 'Asia/Jerusalem') as start_at,
      ((t.task_date + coalesce(t.onsite_start_time, t.warehouse_start_time))
        at time zone 'Asia/Jerusalem') as onsite_at,
      ((t.task_date + coalesce(t.onsite_start_time, t.warehouse_start_time))
        at time zone 'Asia/Jerusalem')
        + make_interval(mins => round(coalesce(t.hours_count, 0) * 60)::int) as end_at,
      -- איש הקשר של הלקוח, למי שהמשרד נתן לו את השדה או למי שהוא ראש הצוות
      -- של האירוע (0082). שאילתה אחת לשניהם, כי זו אותה שורה.
      case when app.can_view_field('event', 'contact_phone')
                or app.is_event_team_lead(t.event_id)
           then ec.contact_name end as contact_name,
      case when app.can_view_field('event', 'contact_phone')
                or app.is_event_team_lead(t.event_id)
           then ec.contact_phone end as contact_phone,
      (select count(*) from task_assignments x where x.task_id = t.id)
        + (select count(*) from task_contractor_workers x where x.task_id = t.id)
        as assigned_count,
      -- ‏0083: השם לבדו אינו מספיק לראש צוות — הוא צריך לדעת מי מגיע למחסן
      -- ומי לשטח, וזו בדיוק ההבחנה שקובעת מתי כל אחד מתחיל.
      case when v_staffing then (
        select jsonb_agg(q.o order by q.o ->> 'name') from (
          select jsonb_build_object('name', p2.full_name, 'work_site', a2.work_site) as o
            from task_assignments a2 join profiles p2 on p2.id = a2.profile_id
           where a2.task_id = t.id
          union all
          select jsonb_build_object('name', cw.full_name, 'work_site', w2.work_site)
            from task_contractor_workers w2
            join contractor_workers cw on cw.id = w2.contractor_worker_id
           where w2.task_id = t.id) q) end as team
    from d
    join tasks t on t.id = d.tid and t.deleted_at is null
    join task_types tt on tt.id = t.task_type_id
    left join events e on e.id = t.event_id
    left join event_contacts ec on ec.event_id = t.event_id
    left join customers c on c.id = t.customer_id
    left join statuses st on st.id = t.status_id
    left join trucks tr on tr.id = coalesce(d.my_truck, t.truck_id)
    left join execution_methods em on em.id = t.execution_method_id
    left join warehouses wh on wh.id = coalesce(t.warehouse_id, c.warehouse_id)
                           and wh.deleted_at is null
  ),
  numbered as (
    select x.*,
           row_number() over (order by x.start_at, x.task_id) as ord,
           lag(x.end_at) over (order by x.start_at, x.task_id) as prev_end
      from enriched x
  )
  select jsonb_agg(jsonb_build_object(
           'task_id',               n.task_id,
           'ord',                   n.ord,
           'title',                 n.title,
           'task_type_name',        n.type_name,
           'task_type_code',        n.type_code,
           'customer_id',           n.customer_id,
           'customer_name',         n.cust_name,
           'customer_color',        n.cust_color,
           'event_id',              n.event_id,
           'event_number',          n.event_number,
           'end_client_name',       n.end_client_name,
           'contact_name',          n.contact_name,
           'contact_phone',         n.contact_phone,
           'location_text',         n.location_text,
           'location_lat',          n.location_lat,
           'location_lng',          n.location_lng,
           'work_site',             case when n.is_wh then 'warehouse' else 'field' end,
           'warehouse_id',          n.wh_id,
           'warehouse_name',        n.wh_name,
           'warehouse_start_at',    n.wh_start_at,
           'start_at',              n.start_at,
           'onsite_start_at',       n.onsite_at,
           'end_at',                n.end_at,
           'hours_count',           n.hours_count,
           'travel_hours',          n.travel,
           -- הפער נמדד מסיום הקודמת. null במשימה הראשונה, כי "המתנה" לפני
           -- תחילת המשמרת אינה המתנה אלא סתם בוקר.
           'gap_minutes',           case when n.prev_end is null then null
                                    else greatest(0, round(extract(epoch
                                           from (n.start_at - n.prev_end)) / 60))::int end,
           'status_name',           n.status_name,
           'status_color',          n.status_color,
           'truck_name',            n.truck_name,
           'execution_method_name', n.method_name,
           'my_role',               n.my_role,
           'worker_count',          n.worker_count,
           'assigned_count',        n.assigned_count,
           'team',                  n.team,
           'notes',                 n.notes)
         order by n.ord)
    into v_tasks
    from numbered n;

  -- השער. מזהה שאינו שיבוץ של האדם הזה פשוט לא חזר מה-join שלמעלה, ולכן
  -- אי-התאמה במניין היא בדיוק "ביקשת משהו שאינו שלך".
  if coalesce(jsonb_array_length(v_tasks), 0) <> cardinality(v_ids) then
    raise exception 'אחת המשימות אינה שייכת למשמרת של עובד זה' using errcode = '42501';
  end if;

  -- הנסיעה של המשימה האחרונה, ורק למי שיצא מהמחסן (0079/0082).
  v_travel := case when v_tasks -> 0 ->> 'work_site' = 'warehouse'
                   then coalesce((select (r ->> 'travel_hours')::numeric
                                    from jsonb_array_elements(v_tasks) r
                                   order by (r ->> 'end_at')::timestamptz desc,
                                            (r ->> 'task_id') desc
                                   limit 1), 0)
                   else 0 end;

  return jsonb_build_object(
    'profile_id', p_profile_id,
    'full_name',  v_name,
    'tasks',      v_tasks,
    'totals', jsonb_build_object(
      'tasks', jsonb_array_length(v_tasks),
      -- שעות המשימות בלבד. הנסיעה והמתנה יושבות לצידן ואינן מתערבבות בהן,
      -- וזה מה שמאפשר לקרוא את היום: כך וכך עבודה, כך וכך דרך, כך וכך המתנה.
      'work_hours', (select round(coalesce(sum((r ->> 'hours_count')::numeric), 0), 2)
                       from jsonb_array_elements(v_tasks) r),
      'travel_hours', v_travel,
      'idle_minutes', (select coalesce(sum((r ->> 'gap_minutes')::int), 0)
                         from jsonb_array_elements(v_tasks) r)),
    -- מחושב מרשימת המשימות ולא מהשורה שממנה נפתחה המגירה. ההתחלה היא
    -- המוקדם מבין היציאה מהמחסן ותחילת העבודה — אותה שעה בדיוק שהגזירה
    -- קובעת — והסיום כולל את הנסיעה חזרה.
    'shift', jsonb_build_object(
      'start', (select min(least((r ->> 'warehouse_start_at')::timestamptz,
                                 (r ->> 'start_at')::timestamptz))
                  from jsonb_array_elements(v_tasks) r),
      'end',   (select max((r ->> 'end_at')::timestamptz) from jsonb_array_elements(v_tasks) r)
                 + make_interval(mins => round(v_travel * 60)::int),
      'work_site',      v_tasks -> 0 ->> 'work_site',
      'warehouse_name', v_tasks -> 0 ->> 'warehouse_name'));
end $$;
