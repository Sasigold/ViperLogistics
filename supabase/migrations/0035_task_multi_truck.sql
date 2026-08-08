-- 0035: יותר ממשאית אחת למשימה
--
-- למשימה הייתה עד היום משאית אחת (tasks.truck_id), ובפועל אירוע גדול יוצא
-- בשתיים או שלוש. הפתרון כאן הוא עמודת מערך חדשה — truck_ids — ולא טבלת
-- קישור, משתי סיבות:
--
--   1. נתיב הכתיבה של לוח העבודה הוא UPDATE ישיר על tasks עם בדיקת
--      updated_at. טבלת קישור הייתה מחייבת RPC נפרד, ואיתו RLS משלה, ומסלול
--      עריכה שני שאינו עובר ב-enforce_field_perms.
--   2. truck_id נשאר, ומסונכרן תמיד למשאית הראשונה ברשימה. כל מה שנשען עליו
--      היום — תמחור (0017), מנוע הנוכחות (0020), scope_predicates (0013),
--      לוח המשמרות (0034) — ממשיך לעבוד בלי לדעת דבר על השינוי.
--
-- העמודה נכנסת ל-field_registry עם אותו מפתח עריכה של truck_id, ולכן היא
-- מוגנת על ידי אותו טריגר ברמת העמודה שכבר שומר על השדה הישן.

alter table tasks add column if not exists truck_ids uuid[] not null default '{}'::uuid[];

-- המשאית הקיימת היא האיבר הראשון ברשימה החדשה
update tasks
   set truck_ids = array[truck_id]
 where truck_id is not null
   and cardinality(truck_ids) = 0;

-- הבדיקה "מי משובץ למשאית הזו" (assignment_conflicts) עוברת עכשיו על מערך
create index if not exists tasks_truck_ids_idx on tasks using gin (truck_ids);

insert into field_registry (
  entity, field_key, label_he, module, table_name, column_name,
  is_sensitive, default_can_view, default_can_edit, edit_permission_key, sort_order)
values ('task', 'truck_ids', 'משאיות', 'tasks', 'tasks', 'truck_ids',
        false, true, true, 'tasks.change_truck', 95)
on conflict (entity, field_key) do update
  set label_he            = excluded.label_he,
      column_name         = excluded.column_name,
      edit_permission_key = excluded.edit_permission_key,
      sort_order          = excluded.sort_order;

-- ===== סנכרון שני הכיוונים =================================================
-- הרשימה היא המקור כשהיא זו שהשתנתה, וה-truck_id הבודד הוא המקור כשהוא זה
-- שהשתנה — כך שגם מסך שעדיין כותב truck_id בלבד (שורת המשימה בטופס האירוע,
-- ה-RPC של שכפול משימה) לא מוחק בשקט את המשאיות הנוספות: החלפת הראשית
-- מחליפה את האיבר הראשון ומשאירה את השאר במקומם.
--
-- הטריגר נקרא tasks_truck_sync ולכן הוא רץ אחרי tasks_field_perms (סדר
-- אלפביתי): קודם נשפטת השינוי שהמשתמש עשה בפועל, ורק אחר כך נגזרת ממנו
-- העמודה השנייה. כך גזירה אוטומטית לא יכולה לעקוף בדיקת הרשאה.
create or replace function app.sync_task_trucks()
returns trigger language plpgsql set search_path = public as $$
declare v_ids uuid[];
begin
  new.truck_ids := coalesce(new.truck_ids, '{}'::uuid[]);

  if tg_op = 'INSERT' then
    if cardinality(new.truck_ids) = 0 then
      new.truck_ids := case when new.truck_id is null then '{}'::uuid[] else array[new.truck_id] end;
    end if;
  elsif new.truck_ids is distinct from coalesce(old.truck_ids, '{}'::uuid[]) then
    null;  -- הרשימה השתנתה: truck_id ייגזר ממנה למטה
  elsif new.truck_id is distinct from old.truck_id then
    if new.truck_id is null then
      new.truck_ids := case when old.truck_id is null then new.truck_ids
                            else array_remove(new.truck_ids, old.truck_id) end;
    else
      new.truck_ids := array[new.truck_id] || array_remove(
        case when old.truck_id is null then new.truck_ids
             else array_remove(new.truck_ids, old.truck_id) end,
        new.truck_id);
    end if;
  end if;

  -- ניקוי: בלי כפילויות ובלי null, בשמירה על הסדר — האיבר הראשון הוא הראשי
  select coalesce(array_agg(u.id order by u.ord), '{}'::uuid[]) into v_ids
    from (select id, min(ord) as ord
            from unnest(new.truck_ids) with ordinality as t(id, ord)
           where id is not null
           group by id) u;
  new.truck_ids := v_ids;
  new.truck_id  := new.truck_ids[1];
  return new;
end $$;

drop trigger if exists tasks_truck_sync on tasks;
create trigger tasks_truck_sync
  before insert or update on tasks
  for each row execute function app.sync_task_trucks();

-- `UPDATE OF truck_id` נבחן לפי העמודות שנכתבו במשפט, לא לפי מה שהשתנה בפועל.
-- עדכון שנוגע רק ב-truck_ids לא היה מפעיל את חישוב המחיר אף שהמשאית הראשית
-- השתנתה בעקבותיו, ולכן העמודה החדשה מצטרפת לרשימה.
drop trigger if exists tasks_price on tasks;
create trigger tasks_price
  after insert or update of task_type_id, worker_count, hours_count, task_date,
    onsite_start_time, execution_method_id, truck_id, truck_ids, customer_id,
    event_id, travel_hours, requires_team_lead
  on tasks for each row execute function app.tasks_recalc_price();

-- ===== מסכות הקריאה ========================================================

select app.rebuild_secure_view('tasks');

-- אותה רשימת עמודות של 0021 בדיוק, בתוספת שתי עמודות בסוף — וזה מה
-- ש-CREATE OR REPLACE VIEW מתיר.
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
  case when (select app.can_view_field('task', 'truck_ids')) then tlist.list end as truck_list
from tasks t
left join events e     on e.id = t.event_id
left join customers c  on c.id = t.customer_id
join task_types tt     on tt.id = t.task_type_id
left join execution_methods em on em.id = t.execution_method_id
left join trucks tr    on tr.id = t.truck_id
join statuses s        on s.id = t.status_id
left join contractors ct on ct.id = t.contractor_id
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
-- הרשימה נשלפת בסדר של המערך ולא לפי שם: האיבר הראשון הוא המשאית הראשית,
-- וזו הבחנה שהמסך מציג
left join lateral (
  select jsonb_agg(jsonb_build_object('id', tr3.id, 'name', tr3.name) order by u.ord) as list
  from unnest(t.truck_ids) with ordinality as u(truck_id, ord)
  join trucks tr3 on tr3.id = u.truck_id
) tlist on true;

-- ===== התנגשויות משאית על כל הרשימה ========================================
-- 0029 בדקה t.truck_id בלבד. משאית שנייה שנקבעה לשתי משימות חופפות הייתה
-- עוברת בשקט, וזו בדיוק ההתנגשות שהפונקציה קיימת בשבילה.
create or replace function assignment_conflicts(
  p_task_id uuid,
  p_extra_profiles uuid[] default '{}')
returns jsonb language sql stable set search_path = public as $$
  with target as (
    select t.id, t.truck_ids,
           app.task_window(t.id, true)  as win_wh,
           app.task_window(t.id, false) as win_field
    from tasks t
    where t.id = p_task_id and t.deleted_at is null
  ),
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
  subject_win as (
    select s.*, case when s.from_wh then tg.win_wh else tg.win_field end as win
    from subjects s cross join target tg
  ),
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
  trucks_used as (
    select distinct tr.truck_id
    from (
      select u.truck_id from target tg, unnest(tg.truck_ids) as u(truck_id)
      union
      select a.truck_id from task_assignments a
       where a.task_id = p_task_id and a.truck_id is not null
    ) tr
    where tr.truck_id is not null
  ),
  truck_elsewhere as (
    select 'truck'::text as kind, tu.truck_id as subject_id, null::text as role,
           o.task_id as other_id, app.task_window(o.task_id, true) as other_win,
           (select tg.win_wh from target tg) as win
    from trucks_used tu
    join lateral (
      select t2.id as task_id from tasks t2
       where tu.truck_id = any (t2.truck_ids) and t2.id <> p_task_id and t2.deleted_at is null
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
  where h.win && h.other_win
    and not isempty(h.win) and not isempty(h.other_win)
$$;

revoke execute on function public.assignment_conflicts(uuid, uuid[]) from anon, public;

comment on column tasks.truck_ids is
  'כל המשאיות של המשימה, לפי סדר. האיבר הראשון מסונכרן אל truck_id.';
