-- 0162: ראש הצוות הוא אדם אחד בשורה — ולפעמים הוא גם הנהג
--
-- שלושה דיווחים מהשטח, וכולם על אותה שורה בלו״ז:
--
-- 1. **"אם ראש הצוות הוא גם נהג — שלא יופיע פעמיים."** ‏0155 מימשה את
--    "ראש הצוות נוהג" כשורת שיבוץ שנייה בתפקיד `driver`, וזו עדיין ההכרעה
--    הנכונה (הוא מקבל את המשאית, את הבדיקות ואת המשמרת בלי מסלול שני) — אבל
--    השורה השנייה גם הכניסה אותו לתא "צוות", לצד שמו בתא "ראש צוות". התיקון
--    הוא בתצוגה, והוא צריך שהשורה תדע לומר על ראש הצוות מה שהיא אומרת על כל
--    שאר המשובצים: מאיפה הוא מתחיל, אם הוא נוהג, ובאיזו משאית.
--
-- 2. **"שגם לראש הצוות יהיה אייקון כשהוא מגיע למחסן."** ‏`work_site` יושב על
--    שורת השיבוץ מ-0019, וכל משובץ בתא "צוות" נושא את הסימון שלו — ראש הצוות
--    היה היחיד שהתא שלו לא ידע מאיפה הוא יוצא, כי `work_board_view` החזירה
--    ממנו שם ומזהה בלבד.
--
-- 3. **"שאפשר יהיה להגדיר גם על ראש צוות של קבלן שהוא נהג."** לצוות הפנימי
--    זה קיים מ-0155 כשורה שנייה; לעובד הקבלן אין שורה שנייה — ‏
--    `task_contractor_workers` מפתחה על (משימה, עובד) — ולכן זו עמודה על
--    השורה הקיימת ולא רשומה נוספת. אותו אדם, אותה שורה, אותה ספירה.
--
-- ההכרעות:
--
-- * ‏`drives` הוא של ראש הצוות בלבד. עובד שמשובץ `driver` כבר נוהג, וסימון
--   שני עליו היה שם שני מקורות אמת לאותה שאלה. אילוץ על הטבלה, ולא רק
--   בדיקה ב-RPC — מי שכותב ישירות אינו פטור ממנו.
-- * המשאית ממשיכה להיות של מי שנוהג: מ-0154 היא נדחתה לכל תפקיד שאינו
--   `driver`, ומעכשיו גם ראש צוות **שמסומן נוהג** רשאי לה. תפקיד אחר עם
--   משאית עדיין נדחה במפורש.
-- * שלוש העמודות החדשות ב-view נגזרות ולא נשמרות: הן קוראות את אותן שורות
--   שהרשימות קוראות, ולכן אין מצב שבו התא אומר דבר אחד והרשימה אחר.
--
-- ה-view חוזר כאן במלואו מ-0147 — ‏`create or replace view` אינו מרשה
-- להכניס עמודה באמצע, ולכן שלוש החדשות נתלות בסוף.

-- ===== 1. ראש צוות של קבלן שגם נוהג =======================================

alter table task_contractor_workers
  add column drives boolean not null default false;

comment on column task_contractor_workers.drives is
  'ראש הצוות של הקבלן הוא גם הנהג במשימה הזו (0162). שמור לתפקיד team_lead: '
  'עובד המשובץ driver כבר נוהג.';

alter table task_contractor_workers
  add constraint task_contractor_workers_drives_is_the_lead
  check (not drives or role = 'team_lead');

-- ===== 2. השיבוץ ==========================================================
--
-- זהה ל-0154 פרט לסימון: פרמטר, שתי בדיקות, הרחבה של כלל המשאית ועמודה
-- ב-upsert. החתימה גדלה בפרמטר והישנה נמחקת (0024 §8).
drop function if exists contractor_assign_worker(uuid, uuid, uuid, boolean, text, staff_role, uuid);

create or replace function contractor_assign_worker(
  p_task_id uuid,
  p_worker_id uuid default null,
  p_profile_id uuid default null,
  p_on boolean default true,
  p_work_site text default null,
  p_role staff_role default null,
  p_truck_id uuid default null,
  p_drives boolean default false)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_ctr    uuid;
  v_mine   uuid := app.contractor_id();
  v_worker uuid := p_worker_id;
  v_prof   profiles%rowtype;
  v_site   text := p_work_site;
  v_cust   uuid;
  -- ‏0162: מי שנוהג במשימה הזו — הנהג עצמו, או ראש הצוות שסומן.
  v_drives boolean := coalesce(p_drives, false);
  v_wheel  boolean;
begin
  if not (app.has('portal.assign_workers') or app.has('contractors.assign_workers')) then
    raise exception 'אין לך הרשאה לשבץ עובדי קבלן' using errcode = '42501';
  end if;

  -- פתרון העובד והקבלן שלו.
  if v_worker is null then
    if p_profile_id is null then
      raise exception 'חובה לנקוב בעובד או בחשבון' using errcode = '22023';
    end if;
    select * into v_prof from profiles where id = p_profile_id and deleted_at is null;
    if v_prof.id is null then
      raise exception 'העובד לא נמצא' using errcode = '42501';
    end if;
    v_ctr := v_prof.contractor_id;
    v_worker := v_prof.contractor_worker_id;
    if v_worker is null then
      if v_ctr is null then
        raise exception 'לחשבון אין קבלן משויך' using errcode = '42501';
      end if;
      insert into contractor_workers (contractor_id, full_name, phone)
      values (v_ctr, v_prof.full_name, v_prof.phone)
      returning id into v_worker;
      update profiles set contractor_worker_id = v_worker where id = v_prof.id;
    end if;
  else
    select contractor_id into v_ctr from contractor_workers
     where id = v_worker and deleted_at is null;
  end if;
  if v_ctr is null then
    raise exception 'לא נמצא קבלן לעובד' using errcode = '42501';
  end if;

  -- המשימה חייבת להיות מואצלת לקבלן של העובד.
  if not exists (select 1 from task_contractor_terms
                  where task_id = p_task_id and contractor_id = v_ctr) then
    raise exception 'המשימה אינה מואצלת לקבלן של העובד' using errcode = '42501';
  end if;

  -- קבלן משבץ רק את עובדיו; איש משרד צריך את המפתח המשרדי לקבלן אחר.
  if v_ctr is distinct from v_mine then
    perform app.require('contractors.assign_workers');
  end if;

  -- ‏0121: שיבוץ לתפקיד דורש שהעובד מוגדר בו. null = עובד רגיל.
  if p_role in ('team_lead', 'driver')
     and not exists (select 1 from contractor_worker_roles
                      where contractor_worker_id = v_worker and role = p_role) then
    raise exception 'העובד אינו מוגדר בתפקיד המבוקש' using errcode = '42501';
  end if;

  -- ‏0162: הסימון "גם נוהג" הוא של ראש הצוות, ודורש שהוא מוגדר נהג — בדיוק
  -- כמו שיבוץ לתפקיד נהג. מי שמשובץ `driver` כבר נוהג ואין מה לסמן עליו.
  if v_drives then
    if p_role is distinct from 'team_lead' then
      raise exception 'הסימון "גם נהג" שמור לראש הצוות' using errcode = '22023';
    end if;
    if not exists (select 1 from contractor_worker_roles
                    where contractor_worker_id = v_worker and role = 'driver') then
      raise exception 'העובד אינו מוגדר נהג' using errcode = '42501';
    end if;
  end if;
  -- מי שאוחז בהגה על המשימה הזו — וזה מי שרשאי למשאית.
  v_wheel := p_role = 'driver' or (p_role = 'team_lead' and v_drives);

  -- ‏0128: ראש צוות אחד למשימה — פנימי או של קבלן, ולא אחד מכל סוג.
  if p_on and p_role = 'team_lead' then
    if exists (select 1 from task_assignments a
                where a.task_id = p_task_id and a.role = 'team_lead') then
      raise exception 'למשימה כבר מוגדר ראש צוות' using errcode = '42501';
    end if;
    if exists (select 1 from task_contractor_workers tcw
                where tcw.task_id = p_task_id and tcw.role = 'team_lead'
                  and tcw.contractor_worker_id is distinct from v_worker) then
      raise exception 'למשימה כבר מוגדר ראש צוות' using errcode = '42501';
    end if;
  end if;

  -- ‏0154: המשאית.
  --
  -- ‏`tasks.assign.truck` נדרש רק כשהיא **משתנה**, ולא כשהיא נשלחת: הקורא
  -- שולח את מצב השורה כולו בכל קריאה (אחרת ה-upsert מוחק את מה שלא נשלח),
  -- ומנהל קבלן שמזיז את אתר העבודה של נהג אינו אמור להיחסם על משאית שהמשרד
  -- קבע ושהוא רק מחזיר כפי שהיא. המשאית היא נכס של המשרד, ולכן שינוי שלה
  -- הוא של מי שמחזיק את המפתח שכבר שומר עליה ב-`task_assignments` (0012).
  if p_on and p_truck_id is distinct from
       (select truck_id from task_contractor_workers
         where task_id = p_task_id and contractor_worker_id = v_worker) then
    perform app.require('tasks.assign.truck');
  end if;

  -- המשאית היא של מי שנוהג. תפקיד אחר עם משאית נדחה במפורש — שיבוץ ש"שכח"
  -- להוריד אותה בשינוי תפקיד הוא באג של הקורא, ובליעה שקטה שלה הייתה
  -- משאירה משאית תפוסה על מי שאינו נוהג בה.
  if p_on and p_truck_id is not null then
    if not v_wheel then
      raise exception 'משאית משויכת לנהג בלבד' using errcode = '22023';
    end if;
    if not exists (select 1 from trucks t where t.id = p_truck_id and t.deleted_at is null) then
      raise exception 'המשאית לא נמצאה' using errcode = '42501';
    end if;
    -- אותה הגבלה של 0116: רשימת המשאיות של הלקוח, וריקה = כל הקטלוג.
    select customer_id into v_cust from tasks where id = p_task_id;
    if exists (select 1 from customer_trucks where customer_id = v_cust)
       and not exists (select 1 from customer_trucks
                        where customer_id = v_cust and truck_id = p_truck_id) then
      raise exception 'המשאית אינה ברשימת המשאיות של הלקוח' using errcode = '42501';
    end if;
  end if;

  -- ‏0111: נקודת ההתחלה היא של המשרד. בלי המפתח המשרדי מה שנשלח מהקורא נזרק.
  if not app.has('contractors.assign_workers') then
    v_site := null;
  end if;
  if v_site is null then
    select coalesce(work_site, 'field') into v_site
      from task_contractor_terms where task_id = p_task_id and contractor_id = v_ctr;
    v_site := coalesce(v_site, 'field');
  end if;
  if v_site not in ('field', 'warehouse') then
    raise exception 'אתר עבודה לא חוקי: %', v_site using errcode = '22023';
  end if;

  if p_on then
    insert into task_contractor_workers (task_id, contractor_worker_id, work_site, role, truck_id, drives)
    values (p_task_id, v_worker, v_site, p_role,
            case when v_wheel then p_truck_id end,
            v_drives)
    on conflict (task_id, contractor_worker_id) do update
      set work_site = excluded.work_site,
          role      = excluded.role,
          truck_id  = excluded.truck_id,
          drives    = excluded.drives;
  else
    delete from task_contractor_workers
     where task_id = p_task_id and contractor_worker_id = v_worker;
  end if;

  return v_worker;
end $$;

comment on function contractor_assign_worker(uuid, uuid, uuid, boolean, text, staff_role, uuid, boolean) is
  'שיבוץ עובד קבלן למשימה, עם תפקיד (0121), ראש צוות אחד למשימה (0128) '
  'ומשאית לנהג (0154). מ-0162 ראש הצוות של הקבלן יכול להיות מסומן גם כנהג, '
  'ואז המשאית פתוחה גם לו.';

revoke execute on function
  public.contractor_assign_worker(uuid, uuid, uuid, boolean, text, staff_role, uuid, boolean)
  from anon, public;
grant execute on function
  public.contractor_assign_worker(uuid, uuid, uuid, boolean, text, staff_role, uuid, boolean)
  to authenticated;

-- ===== 3. השורה אומרת מה ראש הצוות הוא ====================================
--
-- הגוף זהה ל-0147 פרט לארבעה מקומות: ה-lateral של ראש הצוות בכל אחד משלושת
-- המקורות נושא מעכשיו גם אתר עבודה ומשאית, נוסף lateral לשורת הנהיגה של ראש
-- צוות פנימי, ‏`contractor_worker_list` נושא את `drives`, ובסוף שלוש
-- העמודות החדשות.

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
  -- ‏0128: עמודה חדשה נוספת בסוף — `create or replace view` אינו מרשה
  -- להכניס עמודה באמצע.
  case when lead_a.profile_id is not null then 'staff'
       when lead_c.id is not null then 'contractor'
       when lead_o.id is not null then 'customer' end as team_lead_kind,
  -- ‏0134: סגל הלקוח על המשימה, במתכונת `contractor_worker_list`.
  oworkers.list as customer_worker_list,
  -- ‏0140: האם ללקוח של השורה יש סגל משלו. עד כה התא נפתח לפי
  -- `performed_by = 'arko'`, וזה כבר אינו התנאי.
  (select app.customer_self_performing(t.customer_id)) as customer_self_performing,
  -- ‏0147: איסוף מספקים מהאירוע, ומי הספקים.
  case when (select app.can_view_field('event', 'supplier_pickup'))
       then coalesce(e.supplier_pickup, false) end as supplier_pickup,
  case when (select app.can_view_field('event', 'supplier_pickup'))
       then sup.list end as supplier_names,
  -- ‏0162: ראש הצוות, כמו כל משובץ אחר — מאיפה הוא מתחיל, אם הוא נוהג,
  -- ובאיזו משאית. הסדר הוא סדר ההכרעה של `team_lead_name`: פנימי גובר.
  coalesce(lead_a.work_site, lead_c.work_site, lead_o.work_site) as team_lead_work_site,
  case when lead_a.profile_id is not null then lead_drv.id is not null
       when lead_c.id is not null then lead_c.drives
       -- לסגל הלקוח אין (עדיין) סימון כזה: הוא משובץ בתפקיד אחד.
       when lead_o.id is not null then false end as team_lead_drives,
  coalesce(lead_drv.truck_name, lead_c.truck_name, lead_o.truck_name) as team_lead_truck_name
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
-- ‏0162: שורת הנהיגה של ראש הצוות הפנימי — היא שאומרת שהוא נוהג, והיא
-- שנושאת את המשאית. ריקה כשאין ראש צוות פנימי, ואז אין מה להצטרף אליו.
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
  join contractor_workers cw on cw.id = tcw.contractor_worker_id
  left join trucks tr6 on tr6.id = tcw.truck_id
  where tcw.task_id = t.id and tcw.role = 'team_lead' limit 1
) lead_c on true
left join lateral (
  select cuw.id, cuw.full_name, tcuw.work_site, tr7.name as truck_name
  from task_customer_workers tcuw
  join customer_workers cuw on cuw.id = tcuw.customer_worker_id
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
                                      -- ‏0162: ראש צוות של קבלן שגם נוהג.
                                      'drives', tcw.drives)
                   order by cw.full_name) as list
  from task_contractor_workers tcw join contractor_workers cw on cw.id = tcw.contractor_worker_id
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
  join customer_workers cuw on cuw.id = tcuw.customer_worker_id
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
