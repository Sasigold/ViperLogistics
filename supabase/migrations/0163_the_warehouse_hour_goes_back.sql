-- 0163: שעת ההגעה למחסן הולכת אחורה, לעולם לא קדימה
--
-- הדיווח: "יש לי משימה שמתחילה ב-01:00 בתאריך 11.9. אני רושם שעת הגעה למחסן
-- 23:00, והמערכת עושה 23:00 של 11.9 — למרות שזה צריך להיות 10.9."
--
-- הוא צודק, וזו אינה שאלה של העדפה. ‏`warehouse_start_time` היא שעה ולא
-- רגע — עמודת `time` על שורת המשימה — והרגע נבנה ממנה בשלושה מקומות, בכולם
-- באותה דרך: ‏`task_date + warehouse_start_time`. הדרך הזו מניחה בשקט שהיציאה
-- מהמחסן והעבודה בשטח נופלות באותו יום קלנדרי, וההנחה נכונה לכל משמרת יום
-- (07:00 במחסן, 08:00 בשטח) ושקרית בדיוק במשמרת שחוצה חצות: המחסן ב-23:00
-- והשטח ב-01:00 אינם 23:00 *אחרי* 01:00, אלא שעתיים לפניו.
--
-- הכלל, ואין לו יוצא מן הכלל: **מהמחסן יוצאים לפני שמגיעים לשטח.** ולכן שעת
-- מחסן שגדולה משעת השטח היא של הערב שלפני, ולא של הערב שאחרי. אין כאן סף
-- ואין חלון של "עד כמה שעות אחורה" — הסף היחיד היה מוסיף שאלה שאיש אינו יודע
-- לענות עליה ("ומה אם המחסן ב-15:00 והשטח ב-16:00 של מחר?"), בעוד שהכלל
-- כפי שנאמר הוא חד: אחורה, תמיד.
--
-- שלוש ההכרעות:
--
-- 1. **פונקציה אחת ולא שלושה תיקונים.** ‏`app.warehouse_start_at` היא היחידה
--    שיודעת את הכלל, ושלושת הצרכנים קוראים לה. שלוש העתקות של אותו `case`
--    היו נפרדות ביום שבו הכלל ישתנה.
-- 2. **הנסיגה היא ביום הקלנדרי ולא בשעות.** ‏`task_date - 1` ואז המרה לאזור
--    הזמן, ולא `- interval '24 hours'` אחריה: בלילה שבו השעון זז, 23:00 של
--    אתמול הוא 23:00 של אתמול, ולא 22:00 או 00:00.
-- 3. **מי שהמשמרת שלו נסוגה נתלה על היום שבו היא התחילה.** זה מה
--    ש-`app.planned_shifts_many` עושה מאז 0020 ("משמרת שמתחילה ב-22:00
--    ונגמרת ב-02:00 שייכת ליום שבו התחילה"), ולכן משמרת כזו עוברת לתא של
--    10.9 בלוח. כדי שהיא לא תיפול בין הכיסאות — מחוץ לטווח המשימות של הלוח
--    האחד ומחוץ לטווח הימים של הלוח האחר — הגזירה שואבת גם את המשימה של
--    היום שאחרי החלון כשהיא נסוגה אל תוכו, ומסננת בסוף לפי היום שהתקבל.
--
-- מה לא משתנה: שעת השטח, שעת הסיום, ‏`hours_count` והתמחור. משמרת שהמחסן שלה
-- אינו מאוחר משעת השטח — כלומר כל משמרת יום — מקבלת בדיוק את מה שקיבלה עד
-- כה, וגם משימה בלי שעת שטח בכלל: שם `coalesce` כבר בחר את שעת המחסן, ואין
-- מול מה לסגת.

-- ===== 1. הכלל עצמו =======================================================
--
-- ‏null נכנס ו-null יוצא: משימה בלי שעת מחסן אינה יוצאת ממנו. שעת שטח חסרה
-- אינה נסיגה אלא היעדר השוואה — היא ה"שטח" בעצמה (`coalesce` בכל הקוראים),
-- והשוואה של שעה לעצמה לעולם אינה גדולה.
--
-- ‏`stable` ולא `immutable`: ההמרה לאזור זמן נשענת על מסד אזורי הזמן, וזה
-- נתון שהתקנה יכולה לעדכן. די ב-stable כדי שהמתכנן ישבץ את הפונקציה בתוך
-- השאילתות שקוראות לה, וכולן stable בעצמן.
create or replace function app.warehouse_start_at(
  p_task_date date, p_warehouse time, p_onsite time)
returns timestamptz language sql stable set search_path = public as $$
  select case when p_warehouse is null then null else
    (((case when p_onsite is not null and p_warehouse > p_onsite
            then p_task_date - 1 else p_task_date end) + p_warehouse)
      at time zone 'Asia/Jerusalem') end
$$;

-- ===== 2. חלון המשימה — ההתנגשויות =======================================
--
-- ההגדרה זהה ל-0029 פרט לענף הפתיחה.
create or replace function app.task_window(p_task_id uuid, p_from_warehouse boolean)
returns tstzrange language sql stable set search_path = public as $$
  select tstzrange(
    -- ‏0163: יציאה מהמחסן שגדולה משעת השטח היא של הערב שלפני, ולכן החלון
    -- נפתח שם. בלי זה התנגשות של לילה שלם לא נראתה כלל.
    case when p_from_warehouse and t.warehouse_start_time is not null
         then app.warehouse_start_at(t.task_date, t.warehouse_start_time,
                                     t.onsite_start_time)
         else ((t.task_date + coalesce(t.onsite_start_time, t.warehouse_start_time))
                 at time zone 'Asia/Jerusalem') end,
    ((t.task_date + coalesce(t.onsite_start_time, t.warehouse_start_time))
      at time zone 'Asia/Jerusalem')
      + make_interval(mins => round(coalesce(t.hours_count, 0) * 60)::int),
    '[)')
  from tasks t
  where t.id = p_task_id
    and coalesce(t.onsite_start_time, t.warehouse_start_time) is not null
$$;

-- ===== 3. גזירת המשמרות ===================================================
--
-- ההגדרה זהה ל-0079 פרט ל-`b_start`, לתנאי הטווח ולמסנן היום בסוף.
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
      -- ‏0163: ההגעה למחסן קודמת לעבודה בשטח, ולכן שעה שגדולה ממנה היא של
      -- הערב שלפני. שאר הענפים לא זזו.
      case when d.is_wh and t.warehouse_start_time is not null
           then app.warehouse_start_at(t.task_date, t.warehouse_start_time,
                                       t.onsite_start_time)
           else ((t.task_date + coalesce(t.onsite_start_time, t.warehouse_start_time))
                   at time zone 'Asia/Jerusalem') end as b_start,
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
      -- ‏0163: ועוד משימה של היום שאחרי החלון, כשההגעה למחסן שלה נסוגה
      -- אל תוכו. בלעדיה משמרת כזו הייתה נעלמת משני הלוחות גם יחד: כאן היא
      -- מחוץ לטווח המשימות, ובלוח הבא היא כבר מחוץ לטווח הימים.
      and (t.task_date between p_from and p_to
           or (t.task_date = p_to + 1 and d.is_wh
               and t.warehouse_start_time is not null
               and t.onsite_start_time is not null
               and t.warehouse_start_time > t.onsite_start_time))
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
    s.s_core_end + make_interval(mins => round(v.travel * 60)::int),
    round((extract(epoch from
      (s.s_core_end + make_interval(mins => round(v.travel * 60)::int) - s.s_start)
      ) / 3600.0)::numeric, 2),
    s.s_site,
    s.s_ids,
    s.s_first,
    s.s_last,
    s.s_first_lat, s.s_first_lng,
    s.s_last_lat,  s.s_last_lng,
    v.travel,
    case when s.s_count > 1 then s.s_label || ' +' || (s.s_count - 1)::text else s.s_label end,
    s.s_cust,
    s.s_color,
    s.s_wh_id,
    s.s_wh_name
  from shifts s
  -- הנסיעה חזרה שייכת למי שיצא מהמחסן. מי שהגיע ישירות לשטח מסיים בשטח,
  -- ולכן ההכרעה נגזרת פעם אחת כאן ומוזנת לשלושת הצרכנים שלה — שעת הסיום,
  -- השעות המתוכננות והעמודה עצמה — במקום להיכתב שלוש פעמים.
  cross join lateral (
    select case when s.s_site = 'warehouse' then s.s_travel else 0 end as travel
  ) v
  -- ‏0163: המשמרת נתלית על היום שבו היא התחילה, וזה גם הטווח שנשאל. משמרת
  -- שנסוגה אל היום שלפני החלון שייכת ללוח הקודם ולא לזה — ומשימה שנשאבה
  -- מיום אחרי החלון כבר קיבלה כאן את היום הנכון. `seq` אינו נפגע: המסנן
  -- מסלק מחיצות שלמות של work_date ואינו נוגע בספירה שבתוך הנותרות.
  where (s.s_start at time zone 'Asia/Jerusalem')::date between p_from and p_to
  order by s.s_pid, s.s_start;
end $$;


-- ===== 4. פירוק המשמרת ====================================================
--
-- ההגדרה זהה ל-0094 פרט ל-`wh_start_at`. ‏`shift.start` כבר נלקח כ-`least`
-- שלו ושל תחילת העבודה בשטח, ולכן הנסיגה נכנסת אליו בלי נגיעה נוספת.
create or replace function shift_task_breakdown(p_profile_id uuid, p_task_ids uuid[])
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_ids      uuid[];
  v_staffing boolean;
  v_name     text;
  v_tasks    jsonb;
  v_travel   numeric;
begin
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

  v_staffing := app.is_admin() or app.has('board.view_staffing');

  with mine as (
    select a.task_id as tid,
           bool_or(a.work_site = 'warehouse') as is_wh,
           (array_agg(a.truck_id) filter (where a.truck_id is not null))[1] as my_truck
      from task_assignments a
     where a.profile_id = p_profile_id and a.task_id = any(v_ids)
     group by a.task_id
    union all
    select w.task_id, bool_or(w.work_site = 'warehouse'), null::uuid
      from task_contractor_workers w
      join profiles pr on pr.contractor_worker_id = w.contractor_worker_id
     where pr.id = p_profile_id and w.task_id = any(v_ids)
     group by w.task_id
  ),
  d as (
    select m.tid, bool_or(m.is_wh) as is_wh,
           (array_agg(m.my_truck) filter (where m.my_truck is not null))[1] as my_truck
      from mine m group by m.tid
  ),
  enriched as (
    select
      t.id as task_id,
      d.is_wh,
      -- ‏0094: כל התפקידים של האדם במשימה, מסודרים ראש צוות > נהג > עובד.
      (select array_agg(s.r order by s.pr) from (
         select distinct a.role::text as r,
                case a.role when 'team_lead' then 0 when 'driver' then 1 else 2 end as pr
           from task_assignments a
          where a.task_id = t.id and a.profile_id = p_profile_id) s) as my_roles,
      coalesce(nullif(t.title, ''), tt.name) as title,
      tt.name as type_name, tt.code as type_code,
      t.customer_id, c.name as cust_name, c.color as cust_color,
      t.event_id, e.event_number, e.end_client_name,
      coalesce(nullif(t.location_text, ''), e.location_text) as location_text,
      e.location_lat, e.location_lng,
      t.hours_count, t.worker_count, t.notes,
      st.name as status_name, st.color as status_color,
      coalesce(tr.name, nullif(t.truck_free_text, '')) as truck_name,
      tlist.list as truck_list,
      em.name as method_name,
      wh.id as wh_id, wh.name as wh_name,
      coalesce(app.task_travel_hours(t.id), 0) as travel,
      -- ‏0163: היציאה מהמחסן שקודמת לעבודה בשטח היא של הערב שלפני.
      case when d.is_wh and t.warehouse_start_time is not null
           then app.warehouse_start_at(t.task_date, t.warehouse_start_time,
                                       t.onsite_start_time)
      end as wh_start_at,
      ((t.task_date + coalesce(t.onsite_start_time, t.warehouse_start_time))
        at time zone 'Asia/Jerusalem') as start_at,
      ((t.task_date + coalesce(t.onsite_start_time, t.warehouse_start_time))
        at time zone 'Asia/Jerusalem') as onsite_at,
      ((t.task_date + coalesce(t.onsite_start_time, t.warehouse_start_time))
        at time zone 'Asia/Jerusalem')
        + make_interval(mins => round(coalesce(t.hours_count, 0) * 60)::int) as end_at,
      case when app.can_view_field('event', 'contact_phone')
                or app.is_event_team_lead(t.event_id)
           then ec.contact_name end as contact_name,
      case when app.can_view_field('event', 'contact_phone')
                or app.is_event_team_lead(t.event_id)
           then ec.contact_phone end as contact_phone,
      (select count(*) from task_assignments x where x.task_id = t.id)
        + (select count(*) from task_contractor_workers x where x.task_id = t.id)
        as assigned_count,
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
    left join lateral (
      select jsonb_agg(jsonb_build_object('id', tr3.id, 'name', tr3.name) order by u.ord) as list
        from unnest(t.truck_ids) with ordinality as u(truck_id, ord)
        join trucks tr3 on tr3.id = u.truck_id
    ) tlist on true
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
           'gap_minutes',           case when n.prev_end is null then null
                                    else greatest(0, round(extract(epoch
                                           from (n.start_at - n.prev_end)) / 60))::int end,
           'status_name',           n.status_name,
           'status_color',          n.status_color,
           'truck_name',            n.truck_name,
           'truck_list',            n.truck_list,
           'execution_method_name', n.method_name,
           'my_role',               n.my_roles,
           'worker_count',          n.worker_count,
           'assigned_count',        n.assigned_count,
           'team',                  n.team,
           'notes',                 n.notes)
         order by n.ord)
    into v_tasks
    from numbered n;

  if coalesce(jsonb_array_length(v_tasks), 0) <> cardinality(v_ids) then
    raise exception 'אחת המשימות אינה שייכת למשמרת של עובד זה' using errcode = '42501';
  end if;

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
      'work_hours', (select round(coalesce(sum((r ->> 'hours_count')::numeric), 0), 2)
                       from jsonb_array_elements(v_tasks) r),
      'travel_hours', v_travel,
      'idle_minutes', (select coalesce(sum((r ->> 'gap_minutes')::int), 0)
                         from jsonb_array_elements(v_tasks) r)),
    'shift', jsonb_build_object(
      'start', (select min(least((r ->> 'warehouse_start_at')::timestamptz,
                                 (r ->> 'start_at')::timestamptz))
                  from jsonb_array_elements(v_tasks) r),
      'end',   (select max((r ->> 'end_at')::timestamptz) from jsonb_array_elements(v_tasks) r)
                 + make_interval(mins => round(v_travel * 60)::int),
      'work_site',      v_tasks -> 0 ->> 'work_site',
      'warehouse_name', v_tasks -> 0 ->> 'warehouse_name'));
end $$;
