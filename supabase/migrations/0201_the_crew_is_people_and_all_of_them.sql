-- 0201: הצוות במשימה הוא אנשים — פעם אחת כל אחד, וכולם
--
-- שני דיווחים מאותו מסך, "עם: …" בכרטיס המשימה שבמשמרת:
--
--   * "עובד שמשובץ גם כעובד וגם כנהג מופיע פעמיים". ‏`team` ו-`assigned_count`
--     של `shift_task_breakdown` נספרו מתוך *שורות* `task_assignments`, ושורה
--     היא תפקיד ולא אדם: אותו אדם כעובד וכנהג הוא שתי שורות, והכרטיס כתב
--     "עם: איציק, איציק" ו"2 משובצים" על משימה שעומד בה אדם אחד. זה בדיוק
--     הכלל ש-`crew.ts` כבר אוכף בלו״ז — "אדם אחד, שורה אחת" — והוא עובר
--     כאן אל השרת.
--
--   * "שיבצתי קבלן למשימה, והעובדים לא רואים את העובדים של הקבלן". השם של
--     עובד קבלן יושב ב-`contractor_workers`, ו-`cw_select` (0028) פותחת את
--     השורה לאיש צוות רק עם `contractors.view` — מפתח של מודול שלם, כולל
--     טלפון, ת״ז ותמחור. ‏`work_board_view` הוא security_invoker, ולכן אצל
--     עובד שטח `contractor_worker_list` חזר ריק, וראש צוות של קבלן נעלם
--     מהתא שלו. אותו דבר בדיוק קרה לסגל של לקוח שמבצע בעצמו
--     (`customer_workers`, ‏`cuw_select` דורשת `customers.view`), ולכן הוא
--     מתוקן כאן יחד איתו. ‏`shift_task_breakdown` (security definer) כבר
--     החזירה את עובדי הקבלן, אך לא את סגל הלקוח.
--
-- ההכרעה בשאלה השנייה היא זו של `app.customer_identities` (0079): **הזהות**
-- של מי שעומד על המשימה — שם, ולא יותר — נגלית למי שכבר רואה את המשימה.
-- הפוליסות על שתי הטבלאות לא נפתחות, כי הן פותחות *שורה*, כלומר גם phone
-- ו-id_number, לכל מי שמשובץ לידו. ה-view יושב בסכמת `app`, שאינה חשופה
-- ב-PostgREST, ומשמש רק מתוך views שהשורות בהם כבר מסוננות.

-- ===== 1. זהות של עובד קבלן ושל עובד לקוח ==================================
--
-- הסינון כאן אינו מחליף את זה של המשימה אלא קובע מי בכלל מקבל שמות:
-- המשרד והעובדים (staff) — שהלו״ז שלהם מציג משימות של כל הקבלנים והלקוחות —
-- וכל קבלן ולקוח את שלו, כפי שהיה. מה שקבלן או לקוח לא ראו עד היום, הם לא
-- רואים גם עכשיו.
--
-- ‏`current_user` הוא התפקיד של מי שקורא (view אינו מחליף אותו), והסינון חל רק
-- על `authenticated` ו-`anon` — אותם תפקידים ש-RLS חל עליהם. קריאה בצד השרת
-- (service_role, או פונקציית security definer שקוראת את הלו״ז) ראתה את השמות
-- עד היום כי עקפה את RLS, והיא ממשיכה לראות אותם.
--
-- אין כאן `deleted_at is null`: השורה מגיעה לכאן רק דרך שיבוץ קיים למשימה,
-- ומי שעדיין רשום על משימה עומד עליה — גם אם כרטיס העובד שלו הוסר מהמאגר.
create or replace view app.contractor_worker_identities as
  select cw.id, cw.contractor_id, cw.full_name
    from contractor_workers cw
   where current_user not in ('authenticated', 'anon')
      or (select app.is_admin())
      or (select app.user_kind()) = 'staff'
      or cw.contractor_id = (select app.contractor_id());

comment on view app.contractor_worker_identities is
  'זהות עובד הקבלן בלבד — שם וקבלן. עוקפת את RLS על contractor_workers במכוון '
  '(בלי טלפון ות״ז), ולכן משמשת אך ורק בתוך views שהשורות בהם כבר מסוננות '
  '(work_board_view). אינה חשופה ב-API (0201).';

grant select on app.contractor_worker_identities to authenticated;

create or replace view app.customer_worker_identities as
  select cuw.id, cuw.customer_id, cuw.full_name
    from customer_workers cuw
   where current_user not in ('authenticated', 'anon')
      or (select app.is_admin())
      or (select app.user_kind()) = 'staff'
      or cuw.customer_id = (select app.own_staff_customer_id());

comment on view app.customer_worker_identities is
  'זהות עובד הלקוח בלבד — שם ולקוח. עוקפת את RLS על customer_workers במכוון, '
  'ולכן משמשת אך ורק בתוך views שהשורות בהם כבר מסוננות (work_board_view). '
  'אינה חשופה ב-API (0201).';

grant select on app.customer_worker_identities to authenticated;

-- ===== 2. הלו״ז קורא שמות דרך הזהות =======================================
--
-- ה-view חוזר כאן במלואו מ-0188. ההבדל היחיד: ארבעת ה-joins אל
-- `contractor_workers` ואל `customer_workers` (ראש הצוות של כל אחד, והרשימות)
-- עוברים לזהויות שלמעלה.

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
  coalesce(lead_p.full_name, lead_c.full_name, lead_o.full_name) as team_lead_name,
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
  s.code as status_code,
  case when (select app.has('contractors.view_pricing'))
       then case when (select app.contractor_id()) is not null then ctmine.price
                 else ctall.total_price end end as contractor_price,
  case when (select app.has('contractors.view_pricing')) then ctmine.price_per_worker end as contractor_price_per_worker,
  ctmine.work_site as contractor_work_site,
  ctmine.contractor_worker_count as contractor_worker_count,
  ctall.list as contractor_list,
  t.performed_by,
  case when lead_a.profile_id is not null then 'staff'
       when lead_c.id is not null then 'contractor'
       when lead_o.id is not null then 'customer' end as team_lead_kind,
  oworkers.list as customer_worker_list,
  (select app.customer_self_performing(t.customer_id)) as customer_self_performing,
  case when (select app.can_view_field('event', 'supplier_pickup'))
       then coalesce(e.supplier_pickup, false) end as supplier_pickup,
  case when (select app.can_view_field('event', 'supplier_pickup'))
       then sup.list end as supplier_names,
  coalesce(lead_a.work_site, lead_c.work_site, lead_o.work_site) as team_lead_work_site,
  case when lead_a.profile_id is not null then lead_drv.id is not null
       when lead_c.id is not null then lead_c.drives
       when lead_o.id is not null then false end as team_lead_drives,
  coalesce(lead_drv.truck_name, lead_c.truck_name, lead_o.truck_name) as team_lead_truck_name,
  t.hidden_on_board
from tasks t
left join events e     on e.id = t.event_id
left join app.customer_identities c on c.id = t.customer_id
join task_types tt     on tt.id = t.task_type_id
left join execution_methods em on em.id = t.execution_method_id
left join trucks tr    on tr.id = t.truck_id
join statuses s        on s.id = t.status_id
left join contractors ct on ct.id = t.contractor_id
left join statuses es  on es.id = e.status_id
left join task_pricing tp on tp.task_id = t.id
left join lateral (
  select
    jsonb_agg(jsonb_build_object(
      'contractor_id', tct.contractor_id,
      'name', ctx.name,
      'price', case when (select app.has('contractors.view_pricing')) then tct.price end,
      'price_per_worker', case when (select app.has('contractors.view_pricing')) then tct.price_per_worker end,
      'work_site', tct.work_site,
      'worker_count', tct.contractor_worker_count)
      order by tct.created_at, tct.contractor_id) as list,
    sum(tct.price) as total_price
  from task_contractor_terms tct
  join contractors ctx on ctx.id = tct.contractor_id
  where tct.task_id = t.id
) ctall on true
left join lateral (
  select tct.* from task_contractor_terms tct
  where tct.task_id = t.id
    and tct.contractor_id = coalesce((select app.contractor_id()), t.contractor_id)
  limit 1
) ctmine on true
left join lateral (
  select a.profile_id, a.work_site from task_assignments a
  where a.task_id = t.id and a.role = 'team_lead' limit 1
) lead_a on true
left join profiles lead_p on lead_p.id = lead_a.profile_id
left join lateral (
  select a.id, tr5.name as truck_name
  from task_assignments a
  left join trucks tr5 on tr5.id = a.truck_id
  where a.task_id = t.id and a.role = 'driver' and a.profile_id = lead_a.profile_id
  limit 1
) lead_drv on true
left join lateral (
  select cw.id, cw.full_name, tcw.work_site, tcw.drives, tr6.name as truck_name
  from task_contractor_workers tcw
  join app.contractor_worker_identities cw on cw.id = tcw.contractor_worker_id
  left join trucks tr6 on tr6.id = tcw.truck_id
  where tcw.task_id = t.id and tcw.role = 'team_lead' limit 1
) lead_c on true
left join lateral (
  select cuw.id, cuw.full_name, tcuw.work_site, tr7.name as truck_name
  from task_customer_workers tcuw
  join app.customer_worker_identities cuw on cuw.id = tcuw.customer_worker_id
  left join trucks tr7 on tr7.id = tcuw.truck_id
  where tcuw.task_id = t.id and tcuw.role = 'team_lead' limit 1
) lead_o on true
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
                                      'contractor_id', cw.contractor_id,
                                      'work_site', tcw.work_site,
                                      'role', tcw.role,
                                      'drives', tcw.drives)
                   order by cw.full_name) as list
  from task_contractor_workers tcw
  join app.contractor_worker_identities cw on cw.id = tcw.contractor_worker_id
  where tcw.task_id = t.id
) cworkers on true
left join lateral (
  select jsonb_agg(jsonb_build_object('id', cuw.id, 'name', cuw.full_name,
                                      'work_site', tcuw.work_site,
                                      'role', tcuw.role,
                                      'truck_id', tcuw.truck_id,
                                      'truck_name', tr4.name)
                   order by cuw.full_name) as list
  from task_customer_workers tcuw
  join app.customer_worker_identities cuw on cuw.id = tcuw.customer_worker_id
  left join trucks tr4 on tr4.id = tcuw.truck_id
  where tcuw.task_id = t.id
) oworkers on true
left join lateral (
  select jsonb_agg(jsonb_build_object('id', tr3.id, 'name', tr3.name) order by u.ord) as list
  from unnest(t.truck_ids) with ordinality as u(truck_id, ord)
  join trucks tr3 on tr3.id = u.truck_id
) tlist on true
left join lateral (
  select array_agg(sp.name order by sp.name) as list
  from event_suppliers esup
  join suppliers sp on sp.id = esup.supplier_id
  where esup.event_id = e.id and sp.deleted_at is null
) sup on true
where t.deleted_at is null and e.deleted_at is null;

-- ===== 3. המשמרת: אדם אחד, פעם אחת — וסגל הלקוח בכללם =====================
--
-- הגוף זהה ל-0166, ושלושה דברים משתנים ב-`enriched`:
--
-- 1. ‏**`team` הוא רשימת אנשים.** שורות הסגל מקובצות לפי `profile_id`; מי
--    שאחת השורות שלו מתחילה במחסן — מתחיל במחסן, כמו ב-`mine` שלמעלה. לכל
--    אדם נוסף `kind` (staff / contractor / customer), כדי שהמסך יוכל לומר
--    מי מגיע מהקבלן, ו-`key` יציב לרינדור — שם אינו מזהה.
-- 2. ‏**סגל הלקוח נכנס לצוות.** ‏`task_customer_workers` (0133) הוא חלק מאותו
--    צוות בשטח, והלו״ז כבר מציג אותו (`crew.ts`).
-- 3. ‏**`assigned_count` סופר אנשים** — מאותן שלוש קבוצות, ובאותו כלל.
--
-- מה שנשאר: הצוות עדיין מוחזר רק למי שמחזיק `board.view_staffing`.

create or replace function shift_task_breakdown(p_profile_id uuid, p_task_ids uuid[])
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_ids      uuid[];
  v_staffing boolean;
  v_name     text;
  v_tasks    jsonb;
  v_last     jsonb;
  v_travel   numeric;
  v_work     numeric;
  v_sum      numeric;
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
                                   'travel_hours', 0, 'idle_minutes', 0,
                                   'overlap_hours', 0),
      'shift', jsonb_build_object('start', null, 'end', null,
                                  'work_site', null, 'warehouse_name', null,
                                  'end_work_site', null, 'end_warehouse_name', null));
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
      -- ‏0201: אנשים, ולא שורות. ראש צוות שנוהג ועובד ששובץ גם כנהג — אחד.
      (select count(distinct x.profile_id) from task_assignments x where x.task_id = t.id)
        + (select count(*) from task_contractor_workers x where x.task_id = t.id)
        + (select count(*) from task_customer_workers x where x.task_id = t.id)
        as assigned_count,
      case when v_staffing then (
        select jsonb_agg(q.o order by q.o ->> 'name', q.o ->> 'key') from (
          select jsonb_build_object(
                   'key',       's:' || a2.profile_id,
                   'kind',      'staff',
                   'name',      min(p2.full_name),
                   'work_site', case when bool_or(a2.work_site = 'warehouse')
                                     then 'warehouse' else 'field' end) as o
            from task_assignments a2 join profiles p2 on p2.id = a2.profile_id
           where a2.task_id = t.id
           group by a2.profile_id
          union all
          select jsonb_build_object('key', 'c:' || cw.id, 'kind', 'contractor',
                                    'name', cw.full_name, 'work_site', w2.work_site)
            from task_contractor_workers w2
            join contractor_workers cw on cw.id = w2.contractor_worker_id
           where w2.task_id = t.id
          union all
          select jsonb_build_object('key', 'o:' || cuw.id, 'kind', 'customer',
                                    'name', cuw.full_name, 'work_site', w3.work_site)
            from task_customer_workers w3
            join customer_workers cuw on cuw.id = w3.customer_worker_id
           where w3.task_id = t.id) q) end as team
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
           -- ‏0166: המאוחר מבין הסיומים שקדמו, ולא הסיום של הקודמת. משימה
           -- שנבלעת בתוך אחת ארוכה ממנה אינה "אחריה".
           max(x.end_at) over (order by x.start_at, x.task_id
                               rows between unbounded preceding and 1 preceding) as prev_end
      from enriched x
  ),
  -- החלונות מאוחדים לאיים: איי הזמן שבהם באמת עובדים. אי חדש נפתח כשמשימה
  -- מתחילה אחרי שכל מה שלפניה כבר נגמר, וכל השאר מתמזג לתוך מה שפתוח.
  islands as (
    select n.*,
           sum(case when n.prev_end is null or n.start_at > n.prev_end then 1 else 0 end)
             over (order by n.ord rows between unbounded preceding and current row) as grp
      from numbered n
  ),
  merged as (
    select i.grp, min(i.start_at) as s, max(i.end_at) as e
      from islands i group by i.grp
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
           'overlap_minutes',       case when n.prev_end is null then 0
                                    else greatest(0, round(extract(epoch
                                           from (least(n.end_at, n.prev_end) - n.start_at))
                                           / 60))::int end,
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
         order by n.ord),
         (select round((coalesce(sum(extract(epoch from (m.e - m.s))), 0) / 3600.0)::numeric, 2)
            from merged m)
    into v_tasks, v_work
    from islands n;

  if coalesce(jsonb_array_length(v_tasks), 0) <> cardinality(v_ids) then
    raise exception 'אחת המשימות אינה שייכת למשמרת של עובד זה' using errcode = '42501';
  end if;

  select r into v_last
    from jsonb_array_elements(v_tasks) r
   order by (r ->> 'end_at')::timestamptz desc, (r ->> 'task_id') desc
   limit 1;

  v_travel := case when v_last ->> 'work_site' = 'warehouse'
                   then coalesce((v_last ->> 'travel_hours')::numeric, 0)
                   else 0 end;

  select round(coalesce(sum((r ->> 'hours_count')::numeric), 0), 2) into v_sum
    from jsonb_array_elements(v_tasks) r;

  return jsonb_build_object(
    'profile_id', p_profile_id,
    'full_name',  v_name,
    'tasks',      v_tasks,
    'totals', jsonb_build_object(
      'tasks', jsonb_array_length(v_tasks),
      'work_hours', v_work,
      'overlap_hours', greatest(0, round(v_sum - v_work, 2)),
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
      'warehouse_name', v_tasks -> 0 ->> 'warehouse_name',
      'end_work_site',      v_last ->> 'work_site',
      'end_warehouse_name', case when v_last ->> 'work_site' = 'warehouse'
                                 then v_last ->> 'warehouse_name' end));
end $$;

comment on function shift_task_breakdown(uuid, uuid[]) is
  'פירוק המשמרת למשימות. הסיום לפי האחרונה, והחפיפה נספרת פעם אחת (0166). '
  'הצוות הוא אנשים — כל אחד פעם אחת, כולל עובדי הקבלן וסגל הלקוח (0201).';
