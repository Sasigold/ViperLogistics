-- 0076: הלקוח רואה את שמות המשובצים, אבל הם אינם "העובדים שלו"
--
-- הדיווח: משתמש לקוח (אביב, אצל "ארקו") רואה במסך "עובדים ומשתמשים" את
-- "מנהל מערכת" ואת "לקוח בדיקה" — שני פרופילי `staff` שאינם שייכים לחברה שלו.
-- אותם שמות חוזרים גם בחיפוש הגלובלי, שם הכתובית היא הטלפון.
--
-- למה: 0066 (סעיף 5ב) הוסיף ל-profiles_select זרוע שלישית ללקוח —
-- ‏`board.view_staffing` + `app.staff_on_my_customer(id)` — כדי שעמודות הצוות
-- בלוח יפסיקו לחזור ריקות. ‏`work_board_view` הוא security_invoker, ולכן ה-join
-- שלו אל `profiles` כפוף ל-RLS של הקורא, ובלי הזרוע אין שם שם. הזרוע עשתה
-- בדיוק את מה שנדרש ממנה — ובנוסף פתחה את *שורת הפרופיל עצמה* לכל קורא ישיר
-- של `profiles`: מסך העובדים (`select('*')`, כלומר גם טלפון, אימייל והערות)
-- ו-`global_search` (security invoker) בכללם. ‏0066 עצמו סימן את זה כשארית
-- וכתב מה הצעד הבא — "view ייעודי security-definer לשמות במקום זרועות
-- ה-RLS". זה הצעד הזה.
--
-- ההפרדה: *שם בהקשר שיבוץ* ו*שורת פרופיל* מפסיקים להיות אותו דבר.
--   • `app.staffing_names` — view עם שתי עמודות (id, full_name) שאינו
--     security_invoker, ולכן אינו עובר דרך profiles_select. הוא נושא את היקף
--     הראייה של השמות, כולל זרוע השיבוץ.
--   • `work_board_view` — שלושת ה-join-ים של השמות (ראש צוות, עובדים, נהגים)
--     עוברים אל ה-view החדש. שאר ה-view לא נוגע, וגם לא סוג ה-join: inner
--     נשאר inner, ולכן מי שאינו רשאי לשם עדיין מקבל רשימה ריקה ולא שורות
--     עם name=null.
--   • `profiles_select` — זרוע השיבוץ יורדת, והפוליסה חוזרת בדיוק לזו של
--     0005: אדמין, השורה של עצמי, צוות רואה צוות, ולקוח רואה את החברה שלו.
--
-- מה זה משנה בפועל: הלוח, דף האירוע והפורטל ממשיכים להראות ללקוח מי משובץ
-- לעבודות שלו — אותם שמות, אותה הרשאה (`board.view_staffing`), אותו תנאי
-- (`app.staff_on_my_customer`). מסך העובדים והחיפוש הגלובלי חוזרים להראות לו
-- את החברה שלו בלבד, וטלפון/אימייל/הערות של אנשי הצוות אינם נקראים יותר —
-- לא במסך ולא בבקשת REST ישירה.
--
-- ‏`ta_select` לא נוגעת: זרוע הלקוח שם (0066) היא שמאשרת את *שורת השיבוץ*,
-- וכל הגעה אל השם עוברת דרכה. כלומר מי שמגיע אל `app.staffing_names` דרך
-- ה-view כבר עבר את הבדיקה "האם ההשמה הזו על משימה של הלקוח שלי".

-- ===== 1. השמות =============================================================
--
-- ‏security_invoker אינו מופעל כאן במתכוון: ה-view הוא הנתיב שעוקף את
-- profiles_select, וזו כל תכליתו. מכיוון שכך, ה-`where` שלו הוא השער היחיד,
-- והוא מעתיק את היקף הראייה שהיה ב-profiles_select של 0066 מילה במילה —
-- כדי שהשמות בלוח לא ישתנו לאף אחד מהקוראים. שתי עמודות ולא יותר: שארית
-- הטלפון/אימייל שהערת 0066 מתריעה עליה אינה קיימת כאן מהמבנה, ולא מכוח
-- הרשאה שאפשר להדליק.
--
-- ה-view יושב ב-`app` ולא ב-public: הסכימה הזו אינה חשופה ל-PostgREST, ולכן
-- אין אליו בקשת REST ישירה בכלל. `authenticated` מקבל usage על `app` ב-0010.
create or replace view app.staffing_names as
select p.id, p.full_name
from profiles p
where (select app.is_admin())
   or p.user_id = (select auth.uid())
   or (p.deleted_at is null and (
        ((select app.user_kind()) = 'staff' and p.user_kind = 'staff')
        or ((select app.user_kind()) = 'customer_user' and p.customer_id = (select app.customer_id()))
        or ((select app.user_kind()) = 'customer_user'
            and (select app.has('board.view_staffing'))
            and (select app.staff_on_my_customer(p.id)))));

grant select on app.staffing_names to authenticated;
revoke all on app.staffing_names from anon;

-- ===== 2. הלוח קורא את השמות משם ============================================
--
-- מועתק מ-0062 מילה במילה, פרט לשלושת ה-join-ים של השמות: `profiles` →
-- `app.staffing_names`. רשימת העמודות והסדר שלהן זהים, כנדרש ב-create or
-- replace view.
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
  -- הזהות היציבה של הסטטוס (0063). המסכים מציגים את `status_name`, אבל
  -- מי שצריך להחליט לפי הסטטוס — "האם המשמרת הזו פורסמה לעובד" — שואל את
  -- הקוד, מאותו נימוק שנכתב ב-0036 על אירועים.
  s.code as status_code
from tasks t
left join events e     on e.id = t.event_id
left join customers c  on c.id = t.customer_id
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
left join app.staffing_names lead_p on lead_p.id = lead_a.profile_id
left join lateral (
  select jsonb_agg(jsonb_build_object('profile_id', a.profile_id, 'name', p.full_name,
                                      'work_site', a.work_site)
                   order by p.full_name) as list
  from task_assignments a join app.staffing_names p on p.id = a.profile_id
  where a.task_id = t.id and a.role = 'worker'
) workers on true
left join lateral (
  select jsonb_agg(jsonb_build_object('profile_id', a.profile_id, 'name', p.full_name,
                                      'truck_id', a.truck_id, 'truck_name', tr2.name,
                                      'work_site', a.work_site)
                   order by p.full_name) as list
  from task_assignments a
  join app.staffing_names p on p.id = a.profile_id
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

-- ===== 3. שורת הפרופיל נסגרת חזרה ===========================================
--
-- זהה לפוליסה של 0005: זרוע השיבוץ שהוסיף 0066 יורדת, ואיתה מסך העובדים
-- והחיפוש הגלובלי חוזרים להראות ללקוח את החברה שלו בלבד. שאר הזרועות ללא
-- שינוי — ‏`staff` רואה `staff`, וכל אחד רואה את שורתו גם אם היא מחוקה.
drop policy profiles_select on profiles;
create policy profiles_select on profiles for select to authenticated using (
  (select app.is_admin())
  or user_id = (select auth.uid())
  or (deleted_at is null and (
    ((select app.user_kind()) = 'staff' and user_kind = 'staff')
    or ((select app.user_kind()) = 'customer_user' and customer_id = (select app.customer_id())))));
