-- 0079: מה שעובד השטח רואה
--
-- חמישה דיווחים מאותו קהל אחד — העובד ה"כללי", זה שמחזיק רק את המשימות
-- ששובץ אליהן — וכולם נגזרים מאותה שאלה: מה מותר לו לראות, ומה אין לו מה
-- לעשות איתו.
--
--   * הוא לא יכול לפתוח אירוע. `events.view` נחסם לתפקיד "עובד" ב-0011
--     כשמודול האירועים נסגר לו כולו, אף ש-`events_select` כבר מגבילה אותו
--     להיקף 'own' — כלומר לאירוע שיש בו משימה שהוא רשום עליה. המפתח הוא
--     שחסם, לא ההיקף.
--   * הוא לא רואה את שם הלקוח *במערכת*, רק את שם לקוח האירוע. הסיבה אינה
--     מסך אלא RLS: `work_board_view` הוא security_invoker, ו-`customers_select`
--     דורשת `customers.view` — מפתח שפותח מודול שלם, כולל פרטי קשר ותמחור.
--   * הכלים שמעל הלוח — סינון, חיפוש, בורר תצוגה, פתיחת כרטיס משימה לעריכה —
--     הם של מי שמתכנן, לא של מי שמבצע. לא היה להם מפתח משלהם, ולכן לא היה
--     אפשר לכבות אותם בלי לכבות את המסך.
--   * המשמרת שלו נגמרה בשתי שעות שונות בשני מסכים: הגזירה מוסיפה נסיעה
--     חזרה, `shift_task_breakdown` — שממנו נבנית מגירת הפירוק — לא.
--   * ומי שמגיע ישירות לשטח קיבל בכל זאת נסיעה חזרה למחסן שממנו לא יצא.
--
-- הקובץ עונה לחמישתם. שלושת הראשונים הם מפתחות ותפקיד; שני האחרונים הם
-- אריתמטיקה, ולכן הם מתוקנים במנוע ולא במסך.

-- ===== 1. שלושה מפתחות לכלים שמעל הלוח ====================================
--
-- כולם `implied_by` של מפתח הגישה של המודול, ולכן מי שכבר פותח את המסך
-- ממשיך לקבל אותם בלי שינוי — התוספת אינה מורידה דבר לאיש. מה שהיא מוסיפה
-- היא היכולת לכבות: שורת דחייה בעומק התפקיד (שכבה 3 ב-app.has) גוברת על
-- ההיסק בעומק 6.
--
-- `board.columns` ("שינוי עמודות ותצוגה") כבר קיים מ-0011 ומתאר בדיוק את
-- תפריטי "תצוגה" ו"שדות", ולכן אין כאן מפתח רביעי — המסך פשוט מתחיל לשאול
-- אותו.

select app.register_permission('calendar.filter', 'calendar',
  'סינון וחיפוש בלוח שנה',
  'שורת הסינון, החיפוש והצ׳יפים שמעל הלוח. בלעדיה הלוח מוצג כפי שהוא',
  'action', false, false,
  array['staff', 'customer_user']::user_kind[],
  'calendar.view', 15);

select app.register_permission('board.filter', 'board',
  'סינון וחיפוש בלו״ז עבודה',
  'שורת הסינון והחיפוש שמעל הלו״ז. בלעדיה הלוח מוצג כפי שהוא',
  'action', false, false,
  array['staff', 'customer_user']::user_kind[],
  'board.view', 15);

select app.register_permission('board.open_task', 'board',
  'פתיחת כרטיס משימה מהלוח',
  'לחיצה על משימה פותחת את כרטיס המשימה. בלי המפתח היא מובילה לדף האירוע',
  'action', false, false,
  array['staff', 'customer_user']::user_kind[],
  'board.view', 25);

-- ===== 2. תפקיד "עובד": אירוע כן, כלי תכנון לא ============================
--
-- 2א. האירוע נפתח. `close_modules` ב-0011 כתב שורת דחייה לכל מפתח במודול
-- events, וזו שעל events.view היא היחידה שהופכת. השאר נכתבות מחדש כדחייה
-- מפורשת — כולל מפתחות שנרשמו *אחרי* 0011 (יומן הפעילות, המפרט), שאחרת היו
-- נדלקים לו עכשיו בהיסק מ-events.view שזה עתה הענקנו. "לראות את האירוע"
-- אינו "לראות את המסמך שהלקוח שלח ואת מי שינה בו מה".
insert into role_permissions (role_id, permission_key, allowed)
select r.id, pr.key, pr.key = 'events.view'
from permission_roles r
cross join permission_registry pr
where r.key = 'worker' and pr.module = 'events' and pr.is_active
on conflict (role_id, permission_key) do update set allowed = excluded.allowed;

-- 2ב. הכלים שמעל הלוח נסגרים לו. ‏board.columns כבר סגור מ-0011 (המודול
-- board נסגר לו כולו), ולכן כאן רק השלושה החדשים ועוד השניים של לוח השנה
-- שאין להם מה לתת למי שאינו מסנן.
insert into role_permissions (role_id, permission_key, allowed)
select r.id, k, false
from permission_roles r,
     unnest(array['calendar.filter', 'board.filter', 'board.open_task',
                  'calendar.save_filters']) k
where r.key = 'worker'
on conflict (role_id, permission_key) do update set allowed = false;

-- ‏"עובד" ולא "צוות": נהג וראש צוות ממשיכים להחזיק את שלושת המפתחות, וכך
-- גם כל תפקיד שהוגדר במערכת. המפתחות קיימים לכולם במטריצה, ולכן תפקיד
-- שאמור להתנהג כמו עובד שטח נקבע במסך ההרשאות ולא במיגרציה נוספת.

-- ===== 3. מי שרואה את המשימה רואה של מי היא ===============================
--
-- שם הלקוח *במערכת* הוא הזהות שלפיה המשרד מדבר על העבודה, והוא הוסתר מעובד
-- השטח בלי החלטה — פשוט מפני שהוא מגיע מטבלה שהמפתח לפתיחתה הוא
-- `customers.view`, שהוא מפתח מודול: פרטי קשר, תמחור, שדות טופס.
--
-- ההכרעה כאן היא הצרה שלו: **הזהות** של הלקוח (שם וצבע) נגלית למי שכבר
-- רואה את המשימה, ותו לא. ‏`shift_task_breakdown` (0034) כבר עושה בדיוק את
-- זה — היא security definer ומחזירה `customer_name` לעובד שמסתכל במשמרת
-- שלו — ולכן הכלל אינו חדש, הוא רק חדל להיות מקומי.
--
-- המימוש הוא view בסכמת `app` ולא הרחבה של `customers_select`: הרחבת
-- הפוליסה הייתה פותחת את *השורה*, כלומר גם contact_phone ו-notes, לכל מי
-- שמשובץ למשימה. הסכמה הזו אינה חשופה ב-PostgREST, ולכן ה-view אינו משטח
-- קריאה חדש אלא רק מה שהוא: העמודות שכבר מוצגות, בלי הזכות לקרוא את השאר.
--
-- ההיקפים אינם נעקפים. `permission_scopes` על משאב 'tasks' כבר סינן את
-- השורה עצמה לפי לקוח, ומה שנשאר אחריו הוא משימה שמותר לקורא לראות; ההיקף
-- על משאב 'customers' מגדיר מי נכנס לרשימת הלקוחות, ולא של מי המשימה שכבר
-- על המסך.
create or replace view app.customer_identities as
  select id, name, color from customers where deleted_at is null;

comment on view app.customer_identities is
  'זהות הלקוח בלבד — שם וצבע. בעלת הזכויות של ה-view עוקפת את RLS על '
  'customers במכוון, ולכן היא משמשת אך ורק בתוך views שהשורות בהם כבר '
  'מסוננות (work_board_view). אינה חשופה ב-API.';

grant select on app.customer_identities to authenticated;

-- ‏work_board_view נכתב מחדש כדי להחליף join אחד. שאר ההגדרה זהה ל-0062.
create or replace view work_board_view
with (security_invoker = true) as
select
  t.id,
  t.event_id,
  t.customer_id,
  c.name  as customer_name,
  c.color as customer_color,
  e.end_client_name,
  e.event_number,
  case when (select app.can_view_field('task', 'location_text'))
    then coalesce(t.location_text, e.location_text) end as location_text,
  e.volume_m,
  e.truck_count as event_truck_count,
  t.task_type_id,
  tt.name as task_type_name,
  tt.code as task_type_code,
  t.title,
  t.task_date,
  t.warehouse_start_time,
  t.onsite_start_time,
  t.onsite_end_time,
  t.hours_count,
  t.worker_count,
  t.execution_method_id,
  em.name as execution_method_name,
  t.truck_id,
  case when (select app.can_view_field('task', 'truck_id')) then tr.name end as truck_name,
  case when (select app.can_view_field('task', 'truck_free_text')) then t.truck_free_text end as truck_free_text,
  case when (select app.can_view_field('task', 'notes')) then t.notes end as notes,
  t.status_id,
  s.name  as status_name,
  s.color as status_color,
  s.is_terminal as status_is_terminal,
  t.contractor_id,
  case when (select app.has('contractors.view')) then ct.name end as contractor_name,
  t.created_at,
  t.updated_at,
  lead_p.full_name as team_lead_name,
  lead_a.profile_id as team_lead_id,
  workers.list  as workers,
  drivers.list  as drivers,
  cworkers.list as contractor_worker_list,
  case when (select app.has('pricing.view')) then tp.price end as customer_price,
  case when (select app.has('pricing.view')) then tp.is_manual end as price_is_manual,
  case when (select app.has('pricing.view')) then tp.breakdown end as price_breakdown,
  t.travel_hours,
  t.requires_team_lead,
  case when (select app.can_view_field('task', 'truck_ids')) then t.truck_ids end as truck_ids,
  case when (select app.can_view_field('task', 'truck_ids')) then tlist.list end as truck_list,
  coalesce(es.code = 'cancelled', false) as event_is_cancelled,
  s.code as status_code
from tasks t
left join events e     on e.id = t.event_id
-- ‏0079: זהות בלבד, ובלי RLS — ראו את ההערה על ה-view. השורה עצמה כבר
-- מסוננת ב-tasks_select, ולכן "של מי המשימה" אינו מידע נוסף.
left join app.customer_identities c on c.id = t.customer_id
join task_types tt     on tt.id = t.task_type_id
left join execution_methods em on em.id = t.execution_method_id
left join trucks tr    on tr.id = t.truck_id
join statuses s        on s.id = t.status_id
left join contractors ct on ct.id = t.contractor_id
left join statuses es  on es.id = e.status_id
left join task_pricing tp on tp.task_id = t.id
left join lateral (
  select a.profile_id from task_assignments a
  where a.task_id = t.id and a.role = 'team_lead' limit 1
) lead_a on true
left join profiles lead_p on lead_p.id = lead_a.profile_id
left join lateral (
  select jsonb_agg(jsonb_build_object('profile_id', a.profile_id, 'name', p.full_name,
                                      'work_site', a.work_site)
                   order by p.full_name) as list
  from task_assignments a join profiles p on p.id = a.profile_id
  where a.task_id = t.id and a.role = 'worker'
) workers on true
left join lateral (
  select jsonb_agg(jsonb_build_object('profile_id', a.profile_id, 'name', p.full_name,
                                      'truck_id', a.truck_id, 'truck_name', tr2.name,
                                      'work_site', a.work_site)
                   order by p.full_name) as list
  from task_assignments a
  join profiles p on p.id = a.profile_id
  left join trucks tr2 on tr2.id = a.truck_id
  where a.task_id = t.id and a.role = 'driver'
) drivers on true
left join lateral (
  select jsonb_agg(jsonb_build_object('id', cw.id, 'name', cw.full_name,
                                      'work_site', tcw.work_site)
                   order by cw.full_name) as list
  from task_contractor_workers tcw join contractor_workers cw on cw.id = tcw.contractor_worker_id
  where tcw.task_id = t.id
) cworkers on true
left join lateral (
  select jsonb_agg(jsonb_build_object('id', tr3.id, 'name', tr3.name) order by u.ord) as list
  from unnest(t.truck_ids) with ordinality as u(truck_id, ord)
  join trucks tr3 on tr3.id = u.truck_id
) tlist on true
where t.deleted_at is null;

-- ===== 4. הנסיעה חזרה היא של מי שיצא מהמחסן ===============================
--
-- ‏`app.planned_shifts_many` הוסיפה את זמן הנסיעה לסיום *כל* משמרת, בלי
-- לשאול מהיכן היא התחילה. הנסיעה הזו היא, בהגדרה, החזרה מהמשימה האחרונה אל
-- המחסן (0071: "המשמרת מוסיפה אותו פעם אחת, החזרה למחסן מהמשימה האחרונה"),
-- ולמי שהגיע ישירות לשטח אין למה לחזור — הוא סיים כשהעבודה נגמרה.
--
-- זו אינה החמרה אלא תיקון: עד כאן היא נספרה לו כשעת עבודה בכל מקום שקורא
-- את הגזירה — הלוח, השעון והדוח — ולכן היא גם שולמה.
--
-- ‏`work_site` נקבע פר-משובץ (`task_assignments.work_site`), ולכן שני אנשים
-- באותה משימה יכולים לקבל שתי תשובות שונות, וזה בדיוק הנכון: אחד לקח משאית
-- מהמחסן והשני הגיע במכוניתו.
--
-- ההגדרה זהה ל-0063 פרט ל-`cross join lateral` שבסופה ולשלושת השימושים בו.
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
  order by s.s_pid, s.s_start;
end $$;

-- ===== 5. פירוק המשמרת נגמר באותה שעה שהמשמרת נגמרת =======================
--
-- הדיווח: "בלוח המשמרות הסיום כולל את הנסיעה חזרה, ובפרטי המשמרת לא". שניהם
-- נכונים — ‏`shift_task_breakdown` החזירה `max(end_at)`, כלומר את סיום
-- העבודה בשטח, בעוד ש-`app.planned_shifts_many` מוסיפה את הנסיעה. אותה
-- משמרת, שני מספרים, ושום דרך לדעת מי מהם השעה שבה נוסעים הביתה.
--
-- התיקון הוא כאן ולא במסך: המגירה כבר בנויה במכוון כך שהיא מחשבת מהמשימות
-- ולא סומכת על השורה שנשלחה אליה, ולכן החישוב חייב להיות אותו חישוב.
--
-- ההגדרה זהה ל-0034 פרט ל-`v_travel` ולשני השימושים בו.
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

  -- הנסיעה של המשימה *האחרונה*, ולא סכום ולא מקסימום: הגזירה מוסיפה
  -- למשמרת רק את הנסיעה חזרה מהמשימה שנגמרת אחרונה
  -- (0023: array_agg(b_travel order by b_end desc, b_task desc)), ולכן כל
  -- חישוב אחר כאן היה מציג במגירה מספר שאינו זה שנספר בשעות.
  --
  -- ‏0079: ורק למי שיצא מהמחסן — אותה הכרעה בדיוק שיושבת ב-
  -- app.planned_shifts_many, ומאותו נימוק: מי שהגיע ישירות לשטח מסיים בשטח.
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
    -- מחושב מרשימת המשימות ולא מהשורה שממנה נפתחה המגירה, כדי שהמסך לא
    -- יצטרך לסמוך על נתון שהגיע אליו מהלקוח.
    --
    -- ‏0079: הסיום כולל את הנסיעה חזרה, כמו בגזירה עצמה. עד כאן הוא היה
    -- `max(end_at)` — סיום העבודה בשטח — ולכן אותה משמרת נגמרה בשעה אחת
    -- בלוח ובשעה אחרת במגירה שנפתחה מתוכו.
    'shift', jsonb_build_object(
      'start', (select min((r ->> 'start_at')::timestamptz) from jsonb_array_elements(v_tasks) r),
      'end',   (select max((r ->> 'end_at')::timestamptz) from jsonb_array_elements(v_tasks) r)
                 + make_interval(mins => round(v_travel * 60)::int),
      'work_site',      v_tasks -> 0 ->> 'work_site',
      'warehouse_name', v_tasks -> 0 ->> 'warehouse_name'));
end $$;
