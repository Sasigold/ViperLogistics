-- 0188: משימה שאינה אמורה להופיע בלו״ז
--
-- הלו״ז הוא תמונת העבודה של היום, ולא כל משימה שקיימת במערכת היא עבודה
-- שמישהו צריך לראות בו: משימה שנפתחה כדי להחזיק מחיר, כפילות שנוצרה
-- מהאינטגרציה ואי אפשר למחוק כי היא נושאת היסטוריה, סידור פנימי שאינו נוסע
-- לשום מקום. עד היום היו שתי דרכים בלבד — למחוק (וללכת עם ההיסטוריה) או
-- לחיות עם עמודה שמלכלכת את היום.
--
-- שלוש הכרעות:
--
-- 1. **דגל על המשימה, ולא סטטוס נוסף.** סטטוס מתאר איפה העבודה עומדת ונקרא
--    בדוחות, בשכר ובמחיר; "אל תציג לי את זה בלו״ז" אינו מצב של עבודה אלא
--    העדפת תצוגה של המשרד. סטטוס חדש היה מחלחל לכל מקום שסופר סטטוסים.
--
-- 2. **הלו״ז בלבד.** המשימה ממשיכה להופיע בדף האירוע, בלוח השנה, בדוחות,
--    בנוכחות ובכל מקום אחר — כולל אצל מי ששובץ אליה. זו לא הסתרה של עבודה
--    מהעובד שמבצע אותה, וטענה כזו הייתה הופכת את הדגל למסוכן. הוא מסנן
--    מסך אחד.
--
-- 3. **מפתח משלו, ולא `tasks.edit`.** מי שמזיז שעה אינו בהכרח מי שמחליט מה
--    ייעלם מהתמונה שכל המשרד עובד לפיה. ‏`board.hide_task` אינו ניתן כברירת
--    מחדל לאיש, ומנהל המערכת מחזיק אותו ממילא — זו הבקשה: "למנהל מערכת
--    אופציה לסמן".
--
-- הפילטר עצמו הוא קוד לקוח: הלוח שולח `hidden_on_board = false` כברירת
-- מחדל, ובורר "מוסתרות" מחליף אותו. אין כאן פוליסה חדשה — משימה מוסתרת היא
-- משימה רגילה לכל דבר, שמסך אחד מסנן החוצה.

-- ===== 1. הדגל ============================================================

alter table tasks
  add column hidden_on_board boolean not null default false;

comment on column tasks.hidden_on_board is
  'המשימה לא תופיע בלו״ז העבודה (מסך /board) אלא בפילטר "מוסתרות". אינה '
  'משפיעה על שום מסך אחר, על השיבוץ או על הדוחות (0188).';

-- אינדקס חלקי: המסנן הרגיל הוא `= false`, והשורות המוסתרות הן מיעוט קטן —
-- לכן האינדקס יושב עליהן ולא על העמודה כולה.
create index tasks_hidden_on_board_idx on tasks (hidden_on_board)
  where hidden_on_board;

-- ===== 2. המפתח ===========================================================
--
-- סדר הפרמטרים של `register_permission` הוא
-- (…, category, default_allowed, dangerous, applies_to, requires, sort).
select app.register_permission('board.hide_task', 'board',
  'הסתרת משימה מהלו״ז',
  'סימון משימה כך שלא תופיע בלו״ז העבודה, וצפייה במשימות המוסתרות',
  'action', false, false,
  array['staff']::user_kind[],
  'board.view', 45);

-- השדה במרשם — וזה מה שאוכף את המפתח בשרת: ‏`app.enforce_field_perms`
-- (0012) עוצרת כל כתיבה לעמודה בלי `board.hide_task`, ולכן המתג במסך אינו
-- ההגנה אלא התצוגה שלה.
select app.register_field('task', 'hidden_on_board', 'מוסתר מהלו״ז', 'board',
  'tasks', 'hidden_on_board', false, true, false, 'board.hide_task', 75);
select app.rebuild_secure_view('tasks');

-- ===== 3. הלוח יודע מי מוסתר ==============================================
--
-- ה-view חוזר כאן במלואו מ-0162, עם עמודה אחת בסופו.

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
  coalesce(lead_drv.truck_name, lead_c.truck_name, lead_o.truck_name) as team_lead_truck_name,
  -- ‏0188: משימה שסומנה "לא בלו״ז". העמודה בסוף, כי
  -- ‏`create or replace view` אינו מרשה להכניס עמודה באמצע.
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
