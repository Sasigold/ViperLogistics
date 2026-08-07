-- 0034: לוח משמרות של הצוות, ופירוק משמרת למשימות שמרכיבות אותה
--
-- עד כאן היה למשמרות מסך אחד: /my/schedule, שמראה לעובד את שלו. שני הדברים
-- שחסרו למנהל יושבים כאן.
--
-- 1. לוח של כולם. employee_shifts מקבל פרופיל אחד, ולכן לוח של שישים עובדים
--    היה שישים קריאות. במקום זה, מנוע הגזירה עצמו מוכלל למערך של פרופילים.
--
-- 2. פירוק המשמרת. planned_shift_row כבר נושא task_ids, אבל אין דרך לתרגם
--    אותם לשמות ולשעות בלי הרשאת קריאה על tasks — שלעובד מן השורה אין.
--
-- ובנוסף, דבר שלישי שהוא תנאי לשניהם: profiles_select (0005) נותן לעובד צוות
-- לקרוא רק שורות user_kind='staff'. עובד קבלן שקיבל התחברות פשוט אינו שם,
-- ולכן לוח ש"מראה את כולם" שנבנה מקריאה ישירה ל-profiles הוא לוח שקרי.
-- app.shift_roster היא הרשימה האמיתית.

-- ===== 1. מנוע הגזירה, מוכלל למערך של פרופילים =============================
--
-- למה מערך ולא לולאה סביב app.planned_shifts: app.task_travel_hours (0020)
-- שולפת את המשימה, את האירוע ואת אזור התמחור — לכל משימה. הגזירה קוראת לה
-- לכל שורה ב-base, כלומר לכל צמד (עובד, משימה). בלולאה, משימה עם שישה
-- עובדים משלמת שש פעמים על אותה תשובה בדיוק. ה-CTE‏ travel שלמטה מחשב אותה
-- פעם אחת למשימה, וזה ההבדל היחיד שהוא לא טכני-גרידא בין שתי הגרסאות.
--
-- השם נפרד, ולא עומס-יתר על app.planned_shifts: חבילת הבדיקות קוראת לה עם
-- ליטרלים לא-מוטפסים ('2000...'), ושתי חתימות שנבדלות רק ב-uuid מול uuid[]
-- היו הופכות כל קריאה כזאת ל-ambiguous function.

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
    -- עובד צוות
    select a.profile_id as pid, a.task_id as tid,
           bool_or(a.work_site = 'warehouse') as is_wh
      from task_assignments a
     where a.profile_id = any(p_profile_ids)
     group by a.profile_id, a.task_id
    union all
    -- עובד קבלן, דרך הקישור בין ההתחברות לשורת הסגל
    select pr.id, w.task_id, bool_or(w.work_site = 'warehouse')
      from task_contractor_workers w
      join profiles pr on pr.contractor_worker_id = w.contractor_worker_id
     where pr.id = any(p_profile_ids)
     group by pr.id, w.task_id
  ),
  -- אותו אדם יכול להיות משובץ לאותה משימה בשני תפקידים (עובד וגם ראש
  -- צוות). מחסן גובר, כי מי שיוצא מהמחסן מתחיל שם בכל מקרה.
  dedup as (
    select m.pid, m.tid, bool_or(m.is_wh) as is_wh
      from mine m group by m.pid, m.tid
  ),
  -- זמן הנסיעה נשאל פעם אחת למשימה, ולא פעם לכל אדם שמשובץ אליה.
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
      -- נקודת ההתחלה: המחסן למי שיוצא ממנו, האתר לכל השאר.
      case when d.is_wh then wh.lat else e.location_lat end as b_start_lat,
      case when d.is_wh then wh.lng else e.location_lng end as b_start_lng,
      -- נקודת הסיום היא תמיד האתר: שם נגמרת העבודה, גם למי שיצא מהמחסן.
      e.location_lat as b_end_lat,
      e.location_lng as b_end_lng,
      case when d.is_wh then wh.id end   as b_wh_id,
      case when d.is_wh then wh.name end as b_wh_name
    from dedup d
    join tasks t on t.id = d.tid
    join travel tv on tv.tid = d.tid
    left join events e on e.id = t.event_id
    left join customers c on c.id = t.customer_id
    -- המחסן של הלקוח, אלא אם המשימה דרסה אותו במפורש
    left join warehouses wh
           on wh.id = coalesce(t.warehouse_id, c.warehouse_id)
          and wh.deleted_at is null
    join task_types tt on tt.id = t.task_type_id
    where t.deleted_at is null
      and t.task_date between p_from and p_to
      -- משימה בלי אף שעה אינה יכולה להרכיב משמרת
      and coalesce(t.onsite_start_time, t.warehouse_start_time) is not null
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
    -- הפער נמדד עד סיום העבודה בשטח, בלי הנסיעה חזרה. אילו נמדד כולל
    -- נסיעה, עריכה של אזור גיאופנס הייתה מפצלת מחדש שבוע שכבר שולם.
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
      -- הנסיעה חזרה מתווספת רק למשימה האחרונה במשמרת: בין שתי משימות
      -- שקרובות זו לזו אף אחד לא נוסע הביתה ובחזרה.
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

-- הגרסה של פרופיל יחיד הופכת לעטיפה, כדי שיישאר מנוע גזירה אחד. כל מי
-- שקורא לה — השעון, app.shift_at, my_shifts, employee_shifts והבדיקות —
-- ממשיך לעבוד מול אותה חתימה ואותה התנהגות.
create or replace function app.planned_shifts(p_profile_id uuid, p_from date, p_to date)
returns setof app.planned_shift_row
language plpgsql stable security definer set search_path = public as $$
begin
  return query
    select s.* from app.planned_shifts_many(array[p_profile_id], p_from, p_to) s;
end $$;

-- הזרוע של הקבלן בגזירה מצטרפת דרך contractor_worker_id, ועד כה בלי אינדקס.
create index if not exists task_contractor_workers_worker_idx
  on task_contractor_workers (contractor_worker_id);

-- ===== 2. הרוסטר: מי בכלל מופיע בלוח =======================================
--
-- שתי החלטות שיושבות כאן ולא במסך:
--
-- א. מי כשיר להחזיק משמרת. עובד צוות, או עובד קבלן שקיבל התחברות וקושרה לו
--    שורת סגל — כי רק דרך אלה הגזירה מוצאת משימות. איש קשר אצל לקוח לעולם
--    אינו משובץ, ושורה ריקה על שמו בלוח היא רעש.
--
-- ב. עובד שהושבת. הוא נשמט מהרשימה, *אלא אם* יש לו שיבוץ בטווח המוצג —
--    כי משמרת מתוכננת של מי שהושבת באמצע השבוע היא בדיוק מה שמנהל צריך
--    לראות, לא מה שצריך להיעלם לו. הבדיקה היא על השיבוץ ולא על תוצאת
--    הגזירה: היא זולה בהרבה, והיא מספיקה כדי לענות "יש לו משהו בטווח".

create or replace function app.shift_roster(p_from date, p_to date)
returns table (
  profile_id      uuid,
  full_name       text,
  contractor_id   uuid,
  contractor_name text,
  is_contractor   boolean,
  is_active       boolean)
language plpgsql stable security definer set search_path = public as $$
declare
  v_me     uuid    := app.profile_id();
  v_kind   text    := app.user_kind();
  v_ctr    uuid    := app.contractor_id();
  v_all    boolean;
  v_portal boolean;
begin
  if v_me is null then return; end if;

  v_all    := app.is_admin() or (v_kind = 'staff' and app.has('attendance.view_all'));
  v_portal := v_kind = 'contractor_user' and app.has('portal.attendance');

  return query
  select p.id, p.full_name, p.contractor_id, c.name,
         (p.contractor_worker_id is not null), p.is_active
    from profiles p
    left join contractors c on c.id = p.contractor_id and c.deleted_at is null
   where p.deleted_at is null
     and (p.user_kind = 'staff' or p.contractor_worker_id is not null)
     and (p.is_active or exists (
           select 1 from task_assignments a
             join tasks t on t.id = a.task_id and t.deleted_at is null
            where a.profile_id = p.id and t.task_date between p_from and p_to
           union all
           select 1 from task_contractor_workers w
             join tasks t on t.id = w.task_id and t.deleted_at is null
            where w.contractor_worker_id = p.contractor_worker_id
              and t.task_date between p_from and p_to))
     and (v_all
          or (v_portal and p.contractor_id is not null and p.contractor_id = v_ctr)
          or (p.id = v_me and app.has('attendance.view_schedule')))
   -- הסדר נקבע בשרת כדי שסדר השורות בטבלה וסדר האפשרויות במסנן לא יוכלו
   -- לסתור זה את זה: עובדי החברה, ואחריהם כל קבלן כגוש.
   order by (p.contractor_id is not null), c.name nulls first, p.full_name;
end $$;

create or replace function shift_roster(p_from date, p_to date)
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if app.profile_id() is null then
    raise exception 'משתמש לא מזוהה' using errcode = '42501';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'id',              r.profile_id,
             'full_name',       r.full_name,
             'contractor_id',   r.contractor_id,
             'contractor_name', r.contractor_name,
             'is_contractor',   r.is_contractor,
             'is_active',       r.is_active))
      from app.shift_roster(p_from, p_to) r), '[]'::jsonb);
end $$;

-- ===== 3. המשמרות של כל הצוות ==============================================
--
-- ההרשאה מוכרעת ברשימה ולא בכל שורה: הרוסטר כבר יודע במי מותר לצפות, ולכן
-- p_profile_ids הוא *חיתוך* איתו ואף פעם לא הרחבה שלו.
--
-- בקשה למי שאסור מצטמצמת בשקט במקום לזרוק — בשונה מ-employee_shifts, שכן
-- זורק. ההבדל מכוון: employee_shifts היא שאלה על אדם מסוים, וסירוב הוא
-- התשובה הנכונה לה; זו שאילתת רשימה, ושם הכלל הוא של attendance_report
-- (0020) — הרשימה מצטמצמת למה שמותר.

create or replace function team_shifts(
  p_from date, p_to date, p_profile_ids uuid[] default null)
returns setof jsonb language plpgsql stable security definer set search_path = public as $$
declare v_ids uuid[];
begin
  if p_to < p_from then
    raise exception 'טווח תאריכים הפוך' using errcode = '22023';
  end if;
  -- לוח משמרות הוא שבוע או שלושה ימים. בקשה לשנה שלמה על כל הצוות אינה
  -- לוח אלא ייצוא, ויש לו מסך משלו.
  if p_to - p_from > 62 then
    raise exception 'טווח גדול מדי ללוח המשמרות (עד 62 ימים)' using errcode = '22023';
  end if;

  select coalesce(array_agg(r.profile_id), '{}'::uuid[]) into v_ids
    from app.shift_roster(p_from, p_to) r
   where p_profile_ids is null or r.profile_id = any(p_profile_ids);

  if cardinality(v_ids) = 0 then return; end if;

  return query
    select to_jsonb(s) from app.planned_shifts_many(v_ids, p_from, p_to) s;
end $$;

-- ===== 4. פירוק המשמרת למשימות =============================================
--
-- המשמרת מזוהה לפי (profile_id, task_ids) ולא לפי (profile_id, work_date,
-- seq). seq הוא row_number() מעל קיבוץ נגזר שגבולותיו תלויים בטווח שהפיק
-- אותו: גזירה מחדש על טווח אחר יכולה לאחד את המשמרת עם קודמתה, ואז אותו
-- seq מצביע על משמרת אחרת — והמסך היה מתאר בשקט משהו שהמשתמש לא לחץ עליו.
-- הלקוח כבר מחזיק את task_ids בשורה שצייר, ולכן העברתם מדויקת בהגדרה.
--
-- מה שהעברת מזהים פותחת — קריאה על משימות שרירותיות דרך פונקציה מורשת —
-- נסגר בסוף: כל מזהה חייב להיות שיבוץ קיים של האדם הזה, אחרת הפונקציה
-- זורקת. זו בדיקת חברות מדויקת, ולא גזירה חוזרת.

create or replace function shift_task_breakdown(p_profile_id uuid, p_task_ids uuid[])
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_ids      uuid[];
  v_staffing boolean;
  v_name     text;
  v_tasks    jsonb;
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
      ((t.task_date + case
          when d.is_wh and t.warehouse_start_time is not null then t.warehouse_start_time
          else coalesce(t.onsite_start_time, t.warehouse_start_time) end)
        at time zone 'Asia/Jerusalem') as start_at,
      ((t.task_date + coalesce(t.onsite_start_time, t.warehouse_start_time))
        at time zone 'Asia/Jerusalem') as onsite_at,
      ((t.task_date + coalesce(t.onsite_start_time, t.warehouse_start_time))
        at time zone 'Asia/Jerusalem')
        + make_interval(mins => round(coalesce(t.hours_count, 0) * 60)::int) as end_at,
      (select count(*) from task_assignments x where x.task_id = t.id)
        + (select count(*) from task_contractor_workers x where x.task_id = t.id)
        as assigned_count,
      case when v_staffing then (
        select jsonb_agg(q.n order by q.n) from (
          select p2.full_name as n
            from task_assignments a2 join profiles p2 on p2.id = a2.profile_id
           where a2.task_id = t.id
          union all
          select cw.full_name
            from task_contractor_workers w2
            join contractor_workers cw on cw.id = w2.contractor_worker_id
           where w2.task_id = t.id) q) end as team
    from d
    join tasks t on t.id = d.tid and t.deleted_at is null
    join task_types tt on tt.id = t.task_type_id
    left join events e on e.id = t.event_id
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
           'location_text',         n.location_text,
           'location_lat',          n.location_lat,
           'location_lng',          n.location_lng,
           'work_site',             case when n.is_wh then 'warehouse' else 'field' end,
           'warehouse_id',          n.wh_id,
           'warehouse_name',        n.wh_name,
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

  return jsonb_build_object(
    'profile_id', p_profile_id,
    'full_name',  v_name,
    'tasks',      v_tasks,
    'totals', jsonb_build_object(
      'tasks', jsonb_array_length(v_tasks),
      'work_hours', (select round(coalesce(sum((r ->> 'hours_count')::numeric), 0), 2)
                       from jsonb_array_elements(v_tasks) r),
      -- הנסיעה של המשימה *האחרונה*, ולא סכום ולא מקסימום: הגזירה מוסיפה
      -- למשמרת רק את הנסיעה חזרה מהמשימה שנגמרת אחרונה
      -- (0023: array_agg(b_travel order by b_end desc, b_task desc)), ולכן
      -- כל חישוב אחר כאן היה מציג במגירה מספר שאינו זה שנספר בשעות.
      'travel_hours', coalesce((select (r ->> 'travel_hours')::numeric
                                  from jsonb_array_elements(v_tasks) r
                                 order by (r ->> 'end_at')::timestamptz desc,
                                          (r ->> 'task_id') desc
                                 limit 1), 0),
      'idle_minutes', (select coalesce(sum((r ->> 'gap_minutes')::int), 0)
                         from jsonb_array_elements(v_tasks) r)),
    -- מחושב מרשימת המשימות ולא מהשורה שממנה נפתחה המגירה, כדי שהמסך לא
    -- יצטרך לסמוך על נתון שהגיע אליו מהלקוח.
    'shift', jsonb_build_object(
      'start', (select min((r ->> 'start_at')::timestamptz) from jsonb_array_elements(v_tasks) r),
      'end',   (select max((r ->> 'end_at')::timestamptz)   from jsonb_array_elements(v_tasks) r),
      'work_site',      v_tasks -> 0 ->> 'work_site',
      'warehouse_name', v_tasks -> 0 ->> 'warehouse_name'));
end $$;

-- ===== 5. anon מחוץ למשטח החדש =============================================

do $$
declare fn text;
begin
  foreach fn in array array[
    'shift_roster(date, date)',
    'team_shifts(date, date, uuid[])',
    'shift_task_breakdown(uuid, uuid[])']
  loop
    execute format('revoke execute on function public.%s from anon, public', fn);
  end loop;
end $$;
