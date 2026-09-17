-- 0178: לעובד של הלקוח יש חשבון — והוא רואה את מה שעובד רואה, של הלקוח שלו בלבד
--
-- הדיווח: **"שיהיה אפשר להוסיף עובדים עבור לקוח ארקו, ושהם יראו את מה
-- שהעובדים הכלליים רואים — אבל רק של הלקוח ארקו."**
--
-- ‏0133 נתנה ללקוח שמבצע בעצמו **רשומת סגל**, ואמרה עליה במפורש: "אין לו גם
-- חשבון התחברות: הוא שם ברשימה, כמו עובד קבלן בלי אפליקציה". זו הייתה הכרעה
-- נכונה לשאלה שנשאלה אז — מי מופיע על המשימה — והשאלה עכשיו אחרת: מה
-- **העובד עצמו** רואה כשהוא פותח את האפליקציה. הרשומה נשארת מה שהיא; מה
-- שנוסף לה הוא הדלת.
--
-- **והדלת כבר קיימת, אצל הקבלן.** עובד קבלן מחזיק חשבון `contractor_user`
-- שמצביע על שורת הסגל שלו (`profiles.contractor_worker_id`, ‏0019), תפקיד צר
-- (`contractor_worker`, ‏0019/0148) שסוגר לו את פורטל הכספים, וזרוע בפוליסות
-- הראייה שנשענת על `app.on_task_as_contractor_worker`. הקובץ הזה הוא אותו
-- מהלך בדיוק, במאגר השני: `profiles.customer_worker_id`, תפקיד `customer_worker`,
-- ו-`app.on_task_as_customer_worker`. אין כאן מנגנון חדש — יש מאגר שלישי
-- שנכנס למנגנון שכבר עומד.
--
-- **"רק של הלקוח ארקו" נענה פעמיים, ושתיהן קיימות כבר:** החשבון הוא
-- `customer_user` של אותו לקוח, ולכן זרוע הלקוח ב-`tasks_select` כבר תוחמת
-- אותו ללקוח שלו; והתפקיד נושא היקף `own` על משימות ואירועים, ולכן הוא רואה
-- מתוכן את מה ששובץ אליו — בדיוק כמו תפקיד "עובד" של הצוות (0011). מנהל
-- מערכת יכול להרחיב אדם מסוים דרך ההיקפים, כמו אצל כל עובד אחר.
--
-- **ומה שאין כאן, במפורש: שעון ושכר.** ההכרעה של 0133 בעינה — סגל הלקוח
-- אינו מוחתם בשעון של וייפר ואינו נכנס ל-`app.attendance_calc`; הוא עובד של
-- הלקוח, ואין לוייפר מה למדוד ומה לשלם לו. התפקיד מקבל את `attendance.view_schedule`
-- לבדו: "מתי אני עובד ואיפה", שהוא לוח המשמרות — ולא את `attendance.clock`
-- ולא את `attendance.view_own`. משמרת נגזרת מהמשימה (0020), ולכן היא נכונה
-- לו בדיוק כפי שהיא נכונה לעובד הקבלן.

-- ===== 1. החשבון מצביע על שורת הסגל ======================================
--
-- ‏`unique` בלי תנאי, כמו `contractor_worker_id` ב-0019: שורת סגל אחת נושאת
-- חשבון אחד לכל היותר, וגם חשבון שנמחק רכות ממשיך להחזיק בה — כדי ששחזור
-- יחזיר אדם אחד ולא יתנגש בשני.
alter table profiles
  add column customer_worker_id uuid unique references customer_workers(id);

comment on column profiles.customer_worker_id is
  'שורת הסגל של הלקוח שהחשבון הזה הוא (0178) — המקבילה של contractor_worker_id.';

-- ‏`customer_worker_id` הוא של עובד אצל לקוח, ולכן הוא נשען על אותו תנאי
-- שכבר קיים ל-`customer_id` (‏profiles_customer_kind, ‏0001).
alter table profiles add constraint profiles_customer_worker_kind
  check (customer_worker_id is null or user_kind = 'customer_user');

create index profiles_customer_worker_idx on profiles (customer_worker_id)
  where deleted_at is null;

-- שורת הסגל של הקורא. אח ל-`app.contractor_id()`/`app.customer_id()`,
-- ‏`security definer` מאותה סיבה: `profiles` מוגנת ב-RLS, ופוליסה שקוראת
-- אותה הייתה נכנסת למעגל.
create or replace function app.customer_worker_id() returns uuid
language sql stable security definer set search_path = public as $$
  select p.customer_worker_id from profiles p
   where p.user_id = auth.uid() and p.is_active and p.deleted_at is null
$$;

comment on function app.customer_worker_id() is
  'שורת הסגל שהחשבון המחובר הוא (0178). null לכל מי שאינו עובד בסגל לקוח.';

revoke execute on function app.customer_worker_id() from anon;
grant execute on function app.customer_worker_id() to authenticated;

-- הקישור תקף רק כשהשורה היא של הלקוח של החשבון — אותו כלל של 0149 אצל
-- הקבלן, ומאותה סיבה: חשבון שעבר ללקוח אחר אינו ממשיך להצביע על סגל שאינו
-- שלו עוד. איפוס ולא שגיאה, כי זו שורה שמתקנת את עצמה ולא בקשה שנדחית.
create or replace function app.sync_customer_worker_link()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.customer_worker_id is not null
     and (new.customer_id is null
          or (select w.customer_id from customer_workers w
               where w.id = new.customer_worker_id) is distinct from new.customer_id) then
    new.customer_worker_id := null;
  end if;
  return new;
end $$;

create trigger profiles_customer_worker_link
  before insert or update of customer_id, customer_worker_id on profiles
  for each row execute function app.sync_customer_worker_link();

-- ===== 2. התפקיד: מה שעובד רואה, ולא יותר ================================
--
-- הרשימה היא זו של תפקיד "עובד" של הצוות (0011 §worker, ‏0079 §2א) בתרגום
-- לקהל הלקוחות: לוח, לוח שנה, המשימה, דלת דף האירוע — ובלי אף כלי תכנון.
-- מה ש**אינו** ברשימה נאמר בסגירת המודולים: `p_close_modules` מקבל את כל
-- המודולים הפעילים, ולכן כל מפתח שאינו מוזכר כאן נכתב כדחייה מפורשת בעומק
-- התפקיד — גוברת על ברירות המחדל של `customer_user` (‏0011/0066), שנועדו
-- למנהל הלקוח ולא לעובד שלו. כך `pricing.view`,‏ `dashboard.view`,‏
-- `events.create` ו-`board.view_staffing` נשארים מחוץ לתמונה בלי רשימת
-- דחיות ידנית שתתיישן.
insert into permission_roles (key, name_he, description_he, user_kind, is_system, sort_order)
values ('customer_worker', 'עובד אצל הלקוח',
        'רואה את המשימות ששובץ אליהן ואת המשמרות שלו — אצל הלקוח שלו בלבד',
        'customer_user', true, 115)
on conflict (key) do update set
  name_he = excluded.name_he,
  description_he = excluded.description_he,
  sort_order = excluded.sort_order;

-- ‏`app.has` מתעלם מ-applies_to, וזה רק כדי שהמפתח יופיע במטריצה כשמגדירים
-- תפקיד לקוח — אותה שורה בדיוק של 0131 על `board.inline_edit`.
update permission_registry
   set applies_to = array['staff', 'customer_user', 'contractor_user']::user_kind[]
 where key = 'attendance.view_schedule';

select app.set_role_permissions('customer_worker',
  array['board.view', 'calendar.view', 'events.view', 'tasks.view',
        'attendance.view_schedule', 'notifications.view', 'notifications.preferences',
        'search.global'],
  (select array_agg(distinct module) from permission_registry where is_active));

-- ההיקף, בדיוק כמו ל-'worker' ו-'driver' ב-0011: מה שהוא רואה מתוך הלקוח
-- שלו הוא מה ששובץ אליו.
insert into permission_scopes (role_id, resource, scope_type)
select r.id, res.resource, 'own'::permission_scope_type
from permission_roles r
cross join (values ('tasks'), ('events')) as res(resource)
where r.key = 'customer_worker'
  and not exists (select 1 from permission_scopes s
                   where s.role_id = r.id and s.resource = res.resource
                     and s.scope_type = 'own');

-- ===== 3. "המשימות שלי" של עובד הסגל =====================================
--
-- שתי הפונקציות הן תאום מדויק של `app.on_task_as_contractor_worker` ושל
-- `app.on_event_as_contractor_worker` (0066), כולל הנימוק ל-`security definer`:
-- ‏`tcuw_select` מפנה אל `tasks`, ותת-שאילתה על `task_customer_workers` בתוך
-- `tasks_select` הייתה רקורסיה הדדית ש-Postgres חוסם.
--
-- ההבדל היחיד הוא באירוע: אצל הקבלן נדרש שהמשימה תהיה **משובצת**, כי הוא
-- רואה רק לוח שפורסם. כאן המשימה היא של הלקוח שהחשבון שייך לו ממילא, וזרוע
-- הלקוח בפוליסה כבר פתחה לו את האירוע — הצמצום ל'משובץ' היה מסתיר ממנו
-- דווקא את מה ששובץ אליו בטיוטה.
create or replace function app.on_task_as_customer_worker(p_task_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from task_customer_workers w
    join profiles pr on pr.customer_worker_id = w.customer_worker_id
    where w.task_id = p_task_id and pr.id = app.profile_id())
$$;

comment on function app.on_task_as_customer_worker(uuid) is
  'האם הקורא משובץ למשימה הזו כעובד בסגל של הלקוח (0178).';

create or replace function app.on_event_as_customer_worker(p_event_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from tasks t
    join task_customer_workers w on w.task_id = t.id
    join profiles pr on pr.customer_worker_id = w.customer_worker_id
    where t.event_id = p_event_id and t.deleted_at is null
      and pr.id = app.profile_id())
$$;

comment on function app.on_event_as_customer_worker(uuid) is
  'האם לקורא יש באירוע הזה משימה ששובץ אליה כעובד בסגל של הלקוח (0178).';

revoke execute on function app.on_task_as_customer_worker(uuid) from anon;
revoke execute on function app.on_event_as_customer_worker(uuid) from anon;
grant execute on function app.on_task_as_customer_worker(uuid) to authenticated;
grant execute on function app.on_event_as_customer_worker(uuid) to authenticated;

-- שתי הפוליסות מועתקות מ-0139 מילה במילה, והשינוי היחיד הוא זרוע אחת
-- שנוספת ל-`scope_own` שבכל אחת.

drop policy tasks_select on tasks;
create policy tasks_select on tasks for select to authenticated using (
  ((select app.is_admin()) and performed_by <> 'arko')
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
         or exists (select 1 from task_assignments a
                    where a.task_id = tasks.id and a.profile_id = (select app.profile_id()))
         or (select app.assignment_on_my_contractor(tasks.id))
         -- ‏0178: והזרוע השלישית — עובד בסגל הלקוח ששובץ למשימה.
         or (select app.on_task_as_customer_worker(tasks.id))
         or ((select app.user_kind()) <> 'staff'
             and created_by = (select app.profile_id())))
    and ((select app.user_kind()) <> 'staff'
         or (select app.can_plan_tasks())
         or (created_by = (select app.profile_id())
             and not (select app.scope_own('tasks')))
         or ((select app.has('portal.view'))
             and (select app.assignment_on_my_contractor(tasks.id)))
         or status_id = (select s.id from statuses s
                          where s.entity = 'task' and s.code = 'assigned'
                            and s.deleted_at is null limit 1))
    and (
      ((select app.user_kind()) = 'staff' and (select app.has('tasks.view'))
          and performed_by <> 'arko')
      or ((select app.user_kind()) = 'customer_user' and customer_id = (select app.customer_id()))
      or ((select app.contractor_id()) is not null
          and performed_by <> 'arko'
          and (select app.assignment_on_my_contractor(tasks.id))
          and ((select app.has('portal.view'))
               or (status_id = (select s.id from statuses s
                                 where s.entity = 'task' and s.code = 'assigned'
                                   and s.deleted_at is null limit 1)
                   and (select app.on_task_as_contractor_worker(tasks.id)))))
      or (exists (select 1 from task_assignments a
                   where a.task_id = tasks.id and a.profile_id = (select app.profile_id()))
          and performed_by <> 'arko')
    )));

drop policy events_select on events;
create policy events_select on events for select to authenticated using (
  ((select app.is_admin()) and not (select app.event_all_tasks_arko(events.id)))
  or (deleted_at is null
    and ((select app.scope_ids('events', 'customers')) is null
         or customer_id = any((select app.scope_ids('events', 'customers'))::uuid[]))
    and ((select app.scope_ids('events', 'statuses')) is null
         or status_id = any((select app.scope_ids('events', 'statuses'))::uuid[]))
    and ((select app.scope_date_from('events')) is null
         or event_date >= (select app.scope_date_from('events')))
    and ((select app.scope_date_to('events')) is null
         or event_date <= (select app.scope_date_to('events')))
    and (not (select app.scope_own('events'))
         or (select app.on_event_as_staff(events.id))
         or (select app.event_on_my_contractor(events.id))
         -- ‏0178: האירוע שיש בו משימה שהעובד שובץ אליה.
         or (select app.on_event_as_customer_worker(events.id))
         or ((select app.user_kind()) <> 'staff'
             and created_by = (select app.profile_id())))
    and (
      ((select app.user_kind()) = 'staff' and ((select app.has('events.view'))
         or (select app.on_event_as_staff(events.id))
         or ((select app.has('portal.view'))
             and (select app.event_on_my_contractor(events.id))))
         and not (select app.event_all_tasks_arko(events.id)))
      or ((select app.user_kind()) = 'customer_user' and customer_id = (select app.customer_id()))
      or ((select app.contractor_id()) is not null and (
            ((select app.has('portal.view'))
             and (select app.event_on_my_contractor(events.id)))
            or (select app.on_event_as_contractor_worker(events.id))))
    )));

-- ===== 4. והמשמרות שלו ==================================================
--
-- ‏`app.planned_shifts_many` (0166) גוזרת את המשמרת משני מאגרי שיבוץ —
-- הצוות הפנימי וסגל הקבלן. השלישי נכנס לצדם באותה מתכונת, ולכן עובד
-- הלקוח רואה ב-`/my/schedule` בדיוק את מה שעובד הקבלן רואה: מתי הוא
-- מתחיל, איפה, וכמה זמן. הגוף זהה ל-0166 פרט לזרוע אחת.

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
    union all
    -- ‏0178: הזרוע השלישית — סגל הלקוח שמבצע בעצמו (0133).
    -- אותה גזירה בדיוק כמו של עובד הקבלן, ומאותה סיבה: השיבוץ
    -- יושב בטבלה משלו והחשבון מצביע על שורת הסגל.
    select pr.id, w.task_id, bool_or(w.work_site = 'warehouse')
      from task_customer_workers w
      join profiles pr on pr.customer_worker_id = w.customer_worker_id
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
      case when d.is_wh then wh.name end as b_wh_name,
      -- ‏0166: המחסן כנקודה, ולא רק כשם. עד כאן הוא נשלף רק דרך
      -- ‏`b_start_lat`, ולכן משמרת שחוזרת אליו בלי לצאת ממנו לא ידעה איפה הוא.
      case when d.is_wh then wh.lat end as b_wh_lat,
      case when d.is_wh then wh.lng end as b_wh_lng
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
      -- אל תוכו.
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
      -- ‏0166: הקצה השני נשאל מהמשימה האחרונה, באותו מיון שכבר בורר את
      -- הנסיעה שלה. ‏`b_wh_*` הם null כשהיא אינה משימת מחסן, וזה בדיוק
      -- המקרה שבו המשמרת נגמרת בשטח.
      (array_agg(g.b_site     order by g.b_end desc, g.b_task desc))[1] as s_end_site,
      (array_agg(g.b_wh_id    order by g.b_end desc, g.b_task desc))[1] as s_end_wh_id,
      (array_agg(g.b_wh_name  order by g.b_end desc, g.b_task desc))[1] as s_end_wh_name,
      (array_agg(g.b_wh_lat   order by g.b_end desc, g.b_task desc))[1] as s_end_wh_lat,
      (array_agg(g.b_wh_lng   order by g.b_end desc, g.b_task desc))[1] as s_end_wh_lng,
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
    -- ‏`work_site` הוא שאלה על ההתחלה, וכזה הוא נשאר: המחסן שיוצאים ממנו,
    -- או השטח שמגיעים אליו. הסיום נשאל בעמודה משלו.
    s.s_site,
    s.s_ids,
    s.s_first,
    s.s_last,
    s.s_first_lat, s.s_first_lng,
    -- ‏0166: מקום הסיום — המחסן שחוזרים אליו, או השטח שמסיימים בו.
    case when s.s_end_site = 'warehouse' then s.s_end_wh_lat else s.s_last_lat end,
    case when s.s_end_site = 'warehouse' then s.s_end_wh_lng else s.s_last_lng end,
    v.travel,
    case when s.s_count > 1 then s.s_label || ' +' || (s.s_count - 1)::text else s.s_label end,
    s.s_cust,
    s.s_color,
    s.s_wh_id,
    s.s_wh_name,
    s.s_end_site,
    s.s_end_wh_id,
    s.s_end_wh_name,
    -- השטח של המשימה האחרונה נשמר בשמו: הוא הנקודה השנייה שהיציאה מקבלת.
    s.s_last_lat,
    s.s_last_lng
  from shifts s
  -- ‏0166: הנסיעה חזרה שייכת למי ש**מסיים** במחסן, ולא למי שיצא ממנו.
  -- היא, בהגדרה, החזרה מהמשימה האחרונה אל המחסן — ולכן המשימה האחרונה היא
  -- שנשאלת. ההכרעה נגזרת פעם אחת כאן ומוזנת לשלושת הצרכנים שלה: שעת
  -- הסיום, השעות המתוכננות והעמודה עצמה.
  cross join lateral (
    select case when s.s_end_site = 'warehouse' then s.s_travel else 0 end as travel
  ) v
  -- ‏0163: המשמרת נתלית על היום שבו היא התחילה, וזה גם הטווח שנשאל.
  where (s.s_start at time zone 'Asia/Jerusalem')::date between p_from and p_to
  order by s.s_pid, s.s_start;
end $$;

comment on function app.planned_shifts_many(uuid[], date, date) is
  'גזירת המשמרות. ההתחלה לפי המשימה הראשונה, הסיום והמיקום שבו לפי האחרונה (0166). '
  'שלושה מאגרי שיבוץ מזינים אותה: הצוות הפנימי, סגל הקבלן וסגל הלקוח (0178).';


-- ===== 5. הלקוח פותח את החשבון בעצמו =====================================
--
-- הסגל הוא של הלקוח, ולכן גם החשבון: מנהל ארקו מוסיף עובד לרשימה ופותח לו
-- כניסה באותו מסך. מה שהוא **אינו** מקבל הוא המפתחות הרחבים של מודול
-- המשתמשים — ‏`users.create` פותח את היכולת להקים אצל הלקוח גם מנהלים, וזו
-- שאלה אחרת לגמרי. במקומם RPC אחד וצר, שנשען על אותו מפתח שכבר מכריע את
-- המסך הזה (`customers.manage_own_staff`) ועל אותו שער פר-לקוח
-- (`app.own_staff_customer_id`, ‏0133): שורת פרופיל אחת, קשורה לשורת סגל
-- אחת, עם תפקיד אחד — ולא מילימטר מעבר.
--
-- **שלוש כתיבות שחייבות לקרות יחד**, בדיוק כמו במודל של עובד הקבלן
-- (`ClockAccountModal`): שורת `profiles` (בלעדיה `app.has` מחזיר false לכל
-- מפתח), הקישור לשורת הסגל, והתפקיד הצר — שבלעדיו החשבון יורש מברירות
-- המחדל של `customer_user` את לוח השנה ואת אנשי הקשר של האירוע.
-- ‏`security definer` ו-`system_write`, כי הטריגרים על `profiles` ועל
-- `profile_roles` שואלים מה **לקורא** מותר, וכאן ההרשאה כבר נבדקה למעלה.
--
-- חשבון ההתחברות עצמו (‏auth.users) נפתח אחר כך ב-`admin-users`, שהוא
-- היחיד שיכול לגעת בו — וסעיף 5ב הוא מה שמרשה לו.
create or replace function customer_staff_account(p_worker_id uuid, p_on boolean default true)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_worker  customer_workers;
  v_profile profiles;
  v_own     uuid := app.own_staff_customer_id();
  v_role    uuid;
  v_id      uuid;
begin
  select * into v_worker from customer_workers where id = p_worker_id;
  if v_worker.id is null then
    raise exception 'העובד לא נמצא' using errcode = '42501';
  end if;

  -- ‏`v_own` הוא null לכל מי שאינו מנהל אצל לקוח שמבצע בעצמו, והוא
  -- נבדק במפורש: השוואה מול null מחזירה null, ו-`if not null` אינו נכנס
  -- לענף — כלומר השער היה נפתח דווקא למי שאין לו לקוח כזה.
  if not (app.is_admin()
          or (app.user_kind() = 'staff' and app.has('users.create'))
          or (app.has('customers.manage_own_staff')
              and v_own is not null and v_worker.customer_id = v_own)) then
    raise exception 'אין לך הרשאה לפתוח חשבון לעובד הזה' using errcode = '42501';
  end if;

  select * into v_profile from profiles where customer_worker_id = p_worker_id;

  if not p_on then
    if v_profile.id is null then return null; end if;
    perform app.system_write(true);
    update profiles set is_active = false, deleted_at = now()
     where id = v_profile.id and deleted_at is null;
    perform app.system_write(false);
    return v_profile.id;
  end if;

  if v_worker.deleted_at is not null or not v_worker.is_active then
    raise exception 'לא ניתן לפתוח חשבון לעובד שאינו פעיל' using errcode = '42501';
  end if;

  perform app.system_write(true);

  if v_profile.id is not null then
    -- חשבון שכבר היה וכובה חוזר לשורה שלו, עם ההיסטוריה שבה. שורה שנייה
    -- לצדה הייתה נחסמת ב-unique ממילא, וזה בדיוק מה שהוא אומר.
    update profiles
       set is_active = true, deleted_at = null,
           full_name = coalesce(nullif(full_name, ''), v_worker.full_name)
     where id = v_profile.id;
    v_id := v_profile.id;
  else
    insert into profiles (user_kind, customer_id, customer_worker_id, full_name, phone)
    values ('customer_user', v_worker.customer_id, v_worker.id,
            v_worker.full_name, v_worker.phone)
    returning id into v_id;
  end if;

  select id into v_role from permission_roles where key = 'customer_worker';
  if v_role is not null then
    insert into profile_roles (profile_id, role_id) values (v_id, v_role)
    on conflict do nothing;
  end if;

  perform app.system_write(false);
  return v_id;
end $$;

comment on function customer_staff_account(uuid, boolean) is
  'פתיחה (וכיבוי) של חשבון לעובד בסגל של לקוח שמבצע בעצמו (0178). שורת '
  'פרופיל, קישור לשורת הסגל ותפקיד "עובד אצל הלקוח" — שלושתם יחד.';

revoke execute on function public.customer_staff_account(uuid, boolean) from anon, public;
grant execute on function public.customer_staff_account(uuid, boolean) to authenticated;

-- 5ב. ומה ש-`admin-users` שואלת לפני שהיא נוגעת ב-`auth.users`.
--
-- הפונקציה הזו היא הרשאה **צרה מאוד**: לא "לפתוח חשבונות" אלא "לפתוח חשבון
-- לשורה בסגל שלי". היא נקראת בזהות הקורא בדיוק כמו `can_manage_profile`
-- (0014), ומאותה סיבה: הפונקציה בקצה אינה מרכיבה מחדש את שרשרת ההרשאות
-- ב-TypeScript, היא שואלת את המסד.
create or replace function can_manage_own_staff_login(p_target uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select app.is_admin()
      or (app.has('customers.manage_own_staff')
          and exists (select 1 from profiles p
                      join customer_workers w on w.id = p.customer_worker_id
                       where p.id = p_target
                         and p.user_kind = 'customer_user'
                         and not p.is_admin
                         and w.customer_id = app.own_staff_customer_id()))
$$;

comment on function can_manage_own_staff_login(uuid) is
  'האם הקורא רשאי לפתוח/לאפס/להסיר את חשבון ההתחברות של העובד הזה מהסגל שלו (0178).';

revoke execute on function public.can_manage_own_staff_login(uuid) from anon, public;
grant execute on function public.can_manage_own_staff_login(uuid) to authenticated;

-- 5ג. עובד שיורד מהסגל — החשבון שלו יורד איתו.
--
-- אחרת נשאר חשבון חי שרואה משימות של לקוח שכבר אינו מעסיק אותו. הכיוון
-- ההפוך אינו אוטומטי במכוון: החזרת עובד לרשימה אינה החזרת הכניסה שלו,
-- וזו לחיצה מפורשת במסך.
create or replace function app.customer_worker_account_follows()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_prev boolean;
begin
  if (new.deleted_at is not null and old.deleted_at is null)
     or (not new.is_active and old.is_active) then
    v_prev := app.in_system_write();
    perform app.system_write(true);
    update profiles
       set is_active = false,
           deleted_at = case when new.deleted_at is not null then now() else deleted_at end
     where customer_worker_id = new.id and deleted_at is null;
    perform app.system_write(v_prev);
  end if;
  return new;
end $$;

comment on function app.customer_worker_account_follows() is
  'עובד שהוסר מסגל הלקוח או כובה — חשבון ההתחברות שלו מכובה איתו (0178).';

create trigger customer_workers_account_follows
  after update of deleted_at, is_active on customer_workers
  for each row execute function app.customer_worker_account_follows();

-- ===== 6. הרשימה אומרת למי כבר יש חשבון ==================================
-- הגוף זהה ל-0133, בתוספת שדה אחד — אותו `has_login` שרשימת הקבלן כבר
-- נושאת מ-0148, ומאותה סיבה: המסך צריך לדעת אם להציע "פתיחת חשבון" או
-- להציג חשבון שקיים.
create or replace function customer_assignable_workers(p_customer_id uuid default null)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_cus uuid := coalesce(p_customer_id, app.own_staff_customer_id());
begin
  if v_cus is null then return '[]'::jsonb; end if;

  -- לקוח קורא רק על עצמו; איש משרד צריך את המפתח.
  if v_cus is distinct from app.own_staff_customer_id()
     and not app.is_admin() and not app.has('customers.view') then
    return '[]'::jsonb;
  end if;

  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'worker_id', w.id,
             'full_name', w.full_name,
             'phone',     w.phone,
             'has_login', p.id is not null,
             'profile_id', p.id,
             'roles',     coalesce((select jsonb_agg(r.role order by r.role)
                                      from customer_worker_roles r
                                     where r.customer_worker_id = w.id), '[]'::jsonb))
           order by w.full_name)
      from customer_workers w
      left join profiles p
             on p.customer_worker_id = w.id and p.deleted_at is null
     where w.customer_id = v_cus and w.deleted_at is null and w.is_active
  ), '[]'::jsonb);
end $$;

comment on function customer_assignable_workers(uuid) is
  'סגל הלקוח כפי שהוא ניתן לשיבוץ (0133), ומ-0178 גם מי מהם מחזיק חשבון.';

revoke execute on function public.customer_assignable_workers(uuid) from anon, public;
grant execute on function public.customer_assignable_workers(uuid) to authenticated;

-- ===== 7. וההרשאות נושאות את שורת הסגל ===================================
-- הגוף זהה ל-0133 פרט לשדה אחד באובייקט הפרופיל.
create or replace function get_my_permissions()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_profile profiles;
  v_caps jsonb; v_legacy jsonb; v_fields jsonb;
  v_roles jsonb; v_app_roles jsonb; v_customer jsonb; v_scopes jsonb; v_form jsonb;
  v_kinds jsonb; v_board jsonb;
begin
  select * into v_profile from profiles
    where user_id = auth.uid() and is_active and deleted_at is null;
  if v_profile.id is null then return null; end if;

  select coalesce(jsonb_object_agg(r.key, app.has(r.key)), '{}') into v_caps
    from permission_registry r where r.is_active;

  select coalesce(jsonb_object_agg(resource, actions), '{}') into v_legacy from (
    select split_part(r.key, '.', 1) as resource,
           jsonb_object_agg(substr(r.key, strpos(r.key, '.') + 1), app.has(r.key)) as actions
    from permission_registry r
    where r.is_active
      and substr(r.key, strpos(r.key, '.') + 1) in ('view', 'create', 'edit', 'delete')
    group by 1) x;

  select coalesce(jsonb_agg(jsonb_build_object(
      'entity', fr.entity, 'field_key', fr.field_key,
      'can_view', app.can_view_field(fr.entity, fr.field_key),
      'can_edit', app.can_edit_field(fr.entity, fr.field_key))), '[]') into v_fields
    from field_registry fr;

  select coalesce(jsonb_agg(role), '[]') into v_roles
    from staff_roles where profile_id = v_profile.id;

  select coalesce(jsonb_agg(jsonb_build_object(
      'id', r.id, 'key', r.key, 'name_he', r.name_he)), '[]') into v_app_roles
    from profile_roles pr join permission_roles r on r.id = pr.role_id
    where pr.profile_id = v_profile.id and r.is_active and r.deleted_at is null;

  select coalesce(jsonb_agg(jsonb_build_object(
      'resource', s.resource, 'scope_type', s.scope_type,
      'values', s.scope_values, 'days_back', s.days_back,
      'days_forward', s.days_forward)), '[]') into v_scopes
    from (select distinct resource from permission_scopes) res
    cross join lateral app.scope_rows(res.resource) s;

  if v_profile.customer_id is not null then
    select jsonb_build_object('id', c.id, 'name', c.name, 'color', c.color,
                              'can_create_events', c.can_create_events,
                              -- ‏0133: המסך צריך לדעת אם הלקוח הזה מבצע בעצמו,
                              -- כדי להציג לו את "הסגל שלי" ואת בורר "בוצע ע״י".
                              'performed_by_enabled', c.performed_by_enabled)
      into v_customer from customers c where c.id = v_profile.customer_id;
  end if;

  select coalesce(jsonb_agg(jsonb_build_object('field_key', field_key, 'state', state)), '[]')
    into v_form from app.form_config(v_profile.customer_id, v_profile.id);

  -- ‏0109: ריק לאיש צוות, ולכן הלוח שלו נשלט במפתחות כפי שהיה תמיד.
  select coalesce(jsonb_agg(jsonb_build_object('field_key', field_key, 'state', state)), '[]')
    into v_board from app.board_config(v_profile.customer_id);

  -- הלקוח והקבלן של הקורא מועברים כפי שהם: אצל עובד צוות הענף ב-
  -- may_create_profile אינו מסתכל עליהם, ואצל לקוח או קבלן זו בדיוק ההשוואה
  -- שהפונקציה עושה מול app.customer_id()/app.contractor_id().
  select coalesce(jsonb_agg(kind), '[]'::jsonb) into v_kinds from (
    select 'staff' as kind
      where app.may_create_profile('staff', null, null, false)
    union all
    select 'customer_user'
      where app.may_create_profile('customer_user', v_profile.customer_id, null, false)
    union all
    select 'contractor_user'
      where app.may_create_profile('contractor_user', null, v_profile.contractor_id, false)
  ) q;

  return jsonb_build_object(
    'profile', jsonb_build_object(
      'id', v_profile.id, 'full_name', v_profile.full_name,
      'user_kind', v_profile.user_kind, 'is_admin', v_profile.is_admin,
      'customer_id', v_profile.customer_id, 'contractor_id', v_profile.contractor_id,
      -- ‏0178: החשבון שהוא עובד בסגל הלקוח נושא את שורת הסגל שלו,
      -- והמסך שואל אותה כדי לדעת שהוא עובד ולא מנהל.
      'customer_worker_id', v_profile.customer_worker_id,
      'phone', v_profile.phone, 'email', v_profile.email),
    'roles', v_roles,
    'app_roles', v_app_roles,
    'customer', v_customer,
    'permissions', v_legacy,
    'capabilities', v_caps,
    'creatable_user_kinds', v_kinds,
    'field_permissions', v_fields,
    'scopes', coalesce(v_scopes, '[]'::jsonb),
    'form_config', v_form,
    'board_config', v_board);
end $$;
