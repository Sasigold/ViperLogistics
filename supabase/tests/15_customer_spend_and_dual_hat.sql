\pset tuples_only on
\pset format unaligned

-- ===========================================================================
-- 15: הלקוח, הכובע הכפול, וקוד השגיאה של השעון (0073–0075).
--
-- שלוש טענות שאף אחת מהן לא הייתה נכשלת בסוויטה הקודמת, מפני שאף בדיקה לא
-- שאלה אותן:
--
--   * שללקוח **אין** את מפתחות ההכנסות, הדוחות והנוכחות. ‏11 בדקה שיש לו
--     `dashboard.view` ו-`pricing.view`, ולא מה נגזר מהם — וזה בדיוק מה
--     שדלף. בדיקת היעדר היא לא סימטרית לבדיקת קיום: מפתח נגזר מופיע בלי
--     שאיש הוסיף אותו.
--   * שעובד צוות שמקושר לקבלן מקבל את הצד הקבלני. זו כל הנקודה של 0075.
--   * שסירוב עסקי בשעון אינו נושא `42501`. הבדיקה היא על **הקוד**, כי
--     ההודעה עוברת ממילא — ומה שנשבר היה המיפוי לפיו.
--
-- החבילה מקימה לקוח, קבלן, אירוע ומשימה משל עצמה ואינה נשענת על קודמותיה.
-- הזריעה רצה בלי JWT (auth.uid() = null) ולכן הטריגרים מדלגים.
-- ===========================================================================

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000015a1', 'c15-cust-mgr@vl.test'),
  ('00000000-0000-0000-0000-0000000015a2', 'c15-cust-viewer@vl.test'),
  ('00000000-0000-0000-0000-0000000015a3', 'c15-dual@vl.test'),
  ('00000000-0000-0000-0000-0000000015a4', 'c15-staff@vl.test');

insert into customers (id, name) values
  ('10000000-0000-0000-0000-000000000015', 'לקוח 15');

insert into contractors (id, name, default_task_price) values
  ('11000000-0000-0000-0000-00000000015a', 'קבלן 15', 400);

insert into contractor_workers (id, contractor_id, full_name) values
  ('12000000-0000-0000-0000-00000000015a', '11000000-0000-0000-0000-00000000015a', 'סגל של הכובע הכפול');

insert into profiles (id, user_id, user_kind, full_name, customer_id, contractor_id) values
  ('20000000-0000-0000-0000-0000000015a1', '00000000-0000-0000-0000-0000000015a1',
   'customer_user', 'מנהל אצל הלקוח 15', '10000000-0000-0000-0000-000000000015', null),
  ('20000000-0000-0000-0000-0000000015a2', '00000000-0000-0000-0000-0000000015a2',
   'customer_user', 'צופה אצל הלקוח 15', '10000000-0000-0000-0000-000000000015', null),
  -- **הכובע הכפול**: עובד צוות לכל דבר, שמקושר לקבלן
  ('20000000-0000-0000-0000-0000000015a3', '00000000-0000-0000-0000-0000000015a3',
   'staff', 'עובד שגם קבלן', null, '11000000-0000-0000-0000-00000000015a'),
  -- איש צוות רגיל, לביקורת: אותם תפקידים בלי הקישור לקבלן
  ('20000000-0000-0000-0000-0000000015a4', '00000000-0000-0000-0000-0000000015a4',
   'staff', 'עובד רגיל', null, null);

insert into profile_roles (profile_id, role_id)
select p.pid, r.id from (values
  ('20000000-0000-0000-0000-0000000015a1'::uuid, 'customer_manager'),
  ('20000000-0000-0000-0000-0000000015a2'::uuid, 'customer_viewer'),
  ('20000000-0000-0000-0000-0000000015a3'::uuid, 'worker'),
  ('20000000-0000-0000-0000-0000000015a3'::uuid, 'staff_contractor'),
  ('20000000-0000-0000-0000-0000000015a4'::uuid, 'worker')
) as p(pid, rkey) join permission_roles r on r.key = p.rkey;

-- אירוע ומשימה מתומחרת של הלקוח, כדי שיהיה מה לספור בהוצאה
insert into events (id, customer_id, event_number, event_date, end_client_name, status_id)
select '30000000-0000-0000-0000-000000000015', '10000000-0000-0000-0000-000000000015',
       915, current_date, 'החתונה של 15',
       (select id from statuses where entity = 'event' and deleted_at is null
         order by sort_order limit 1);

insert into tasks (id, event_id, customer_id, task_type_id, task_date, onsite_start_time,
                   hours_count, worker_count, status_id)
select '60000000-0000-0000-0000-00000000015a', '30000000-0000-0000-0000-000000000015',
       '10000000-0000-0000-0000-000000000015',
       (select id from task_types where code = 'setup' limit 1), current_date, '09:00', 4, 2,
       (select id from statuses where entity = 'task' and code = 'assigned' and deleted_at is null);

-- ההאצלה עוברת בשורת ה-terms (0096), והשיקוף ב-`tasks.contractor_id` נגזר ממנה.
insert into task_contractor_terms (task_id, contractor_id, price)
values ('60000000-0000-0000-0000-00000000015a', '11000000-0000-0000-0000-00000000015a', 0);

insert into task_pricing (task_id, price, is_manual)
values ('60000000-0000-0000-0000-00000000015a', 1250, true);

set role authenticated;

-- ===== §1: ללקוח אין כספים שאינם שלו ======================================

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000015a1', false);

select t_eq('מנהל לקוח: יש dashboard.view', app.has('dashboard.view'), true);
select t_eq('מנהל לקוח: יש pricing.view — בלעדיו אין לו את התמחור של עצמו',
  app.has('pricing.view'), true);

-- אלה נגזרו ולא הוענקו. זו הבדיקה שלא הייתה.
select t_eq('מנהל לקוח: אין pricing.revenue', app.has('pricing.revenue'), false);
select t_eq('מנהל לקוח: אין finance.income_view', app.has('finance.income_view'), false);
select t_eq('מנהל לקוח: אין finance.receipts_view', app.has('finance.receipts_view'), false);
select t_eq('מנהל לקוח: אין reports.view', app.has('reports.view'), false);

-- ===== §2: וללקוח אין נוכחות ==============================================

select t_eq('מנהל לקוח: אין שעון נוכחות', app.has('attendance.clock'), false);
select t_eq('מנהל לקוח: אין דוח נוכחות אישי', app.has('attendance.view_own'), false);
select t_eq('מנהל לקוח: אין לוח משמרות', app.has('attendance.view_schedule'), false);
select t_eq('מנהל לקוח: אין דיווח משמרת ידני', app.has('attendance.submit_entry'), false);
select t_eq('מנהל לקוח: אין נוכחות של אחרים', app.has('attendance.view_all'), false);
select t_expect_fail('ומסך דוח הנוכחות מסרב לו', $$select attendance_report()$$);

-- ===== §3: מה שכן — כמה הוא הוציא =========================================

select t_eq('מנהל לקוח: יש finance.customer_spend', app.has('finance.customer_spend'), true);

select t_eq('ההוצאה היא סך התמחור של המשימות שלו',
  ((dashboard_sections(array['spend.summary'], current_date - 1, current_date + 1)
      -> 'spend.summary' ->> 'total')::numeric), 1250.00::numeric);

select t_eq('והיא יודעת על איזה אירוע היא נרשמה',
  (dashboard_sections(array['spend.summary'], current_date - 1, current_date + 1)
     -> 'spend.summary' -> 'by_event' -> 0 ->> 'label'), 'החתונה של 15');

-- הצופה אצל הלקוח אינו רואה כסף בכלל
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000015a2', false);
select t_eq('צופה אצל הלקוח: אין reports.view', app.has('reports.view'), false);
select t_eq('צופה אצל הלקוח: אין finance.customer_spend', app.has('finance.customer_spend'), false);
select t_eq('ולכן הסקשן חוזר null ולא אפס',
  (dashboard_sections(array['spend.summary'], current_date - 1, current_date + 1)
     -> 'spend.summary'), 'null'::jsonb);

-- ואיש צוות אינו מקבל את הכרטיס הזה בכלל: הוא לא נגזר משום מפתח שיש לו
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000015a4', false);
select t_eq('איש צוות: אין finance.customer_spend', app.has('finance.customer_spend'), false);

-- ===== §4: הכובע הכפול ====================================================

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000015a3', false);

select t_eq('הכובע הכפול הוא עובד צוות', app.user_kind(), 'staff');
select t_eq('ומקושר לקבלן', app.contractor_id(), '11000000-0000-0000-0000-00000000015a'::uuid);

-- התפקיד עם user_kind ריק עובר את המסנן של my_role_ids
select t_eq('התפקיד "קבלן — בנוסף לתפקיד" בתוקף אצלו',
  (select true from unnest(app.my_role_ids()) rid
     join permission_roles r on r.id = rid where r.key = 'staff_contractor'), true);
select t_eq('וגם התפקיד שלו כעובד',
  (select true from unnest(app.my_role_ids()) rid
     join permission_roles r on r.id = rid where r.key = 'worker'), true);

select t_eq('הצד הקבלני: דף הכספים', app.has('portal.view'), true);
select t_eq('הצד הקבלני: הסגל שלו', app.has('portal.manage_workers'), true);
select t_eq('הצד הקבלני: שיבוץ הסגל', app.has('portal.assign_workers'), true);
select t_eq('הצד הקבלני: נוכחות הסגל', app.has('portal.attendance'), true);

-- והצד השעתי לא נלקח ממנו. שכבת התפקידים היא bool_or, ולכן תפקיד שמוסיף
-- אינו יכול לגרוע ממה שתפקיד אחר כבר נתן.
select t_eq('הצד השעתי: שעון נוכחות', app.has('attendance.clock'), true);
select t_eq('הצד השעתי: לוח המשמרות שלו', app.has('attendance.view_schedule'), true);

select t_eq('הוא רואה את הסגל של הקבלן שלו',
  (contractor_assignable_workers() -> 0 ->> 'full_name'), 'סגל של הכובע הכפול');

select t_expect_ok('ומשבץ אותו למשימה שהואצלה לקבלן שלו',
  $$select contractor_assign_worker('60000000-0000-0000-0000-00000000015a',
      '12000000-0000-0000-0000-00000000015a', null, true, 'field')$$);

select t_eq('והשיבוץ נרשם',
  (select count(*) from task_contractor_workers
    where task_id = '60000000-0000-0000-0000-00000000015a')::int, 1);

select t_eq('ודוח הנוכחות נפתח לו על הסגל שלו',
  (attendance_report(current_date - 7, current_date + 1) -> 'rows') is not null, true);

-- איש הצוות עם אותו תפקיד "עובד" אך בלי הקישור לקבלן אינו מקבל דבר מזה.
-- זו הבדיקה שמוכיחה שההכרעה עברה לעמודה ולא נשארה על סוג המשתמש.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000015a4', false);
select t_eq('עובד רגיל: אין portal.view', app.has('portal.view'), false);
select t_eq('עובד רגיל: אין portal.manage_workers', app.has('portal.manage_workers'), false);
select t_eq('עובד רגיל: הרשימה של הקבלן ריקה',
  contractor_assignable_workers(), '[]'::jsonb);

-- ===== §5: מנהל קבלן אינו מחזיק את המפתחות המשרדיים ========================

reset role;
select t_eq('contractor_manager אינו מחזיק contractors.assign_workers',
  (select rp.allowed from role_permissions rp join permission_roles r on r.id = rp.role_id
    where r.key = 'contractor_manager' and rp.permission_key = 'contractors.assign_workers'), false);
select t_eq('ולא contractors.manage_workers',
  (select rp.allowed from role_permissions rp join permission_roles r on r.id = rp.role_id
    where r.key = 'contractor_manager' and rp.permission_key = 'contractors.manage_workers'), false);

-- ===== §6: קוד השגיאה של השעון ============================================
--
-- הטענה היא על ה-SQLSTATE ולא על הטקסט: הטקסט עבר ממילא, ומה שהחליף אותו
-- ב"אין לך הרשאה" היה המיפוי לפי הקוד.

create or replace function t_sqlstate(p_label text, p_sql text, p_expected text)
returns text language plpgsql as $$
begin
  execute p_sql;
  return 'FAIL  ✗ ' || p_label || ' — statement succeeded';
exception when others then
  if sqlstate = p_expected then return 'pass  ✓ ' || p_label; end if;
  return 'FAIL  ✗ ' || p_label || ' — got ' || sqlstate || ', expected ' || p_expected
       || ' (' || sqlerrm || ')';
end $$;
grant execute on function t_sqlstate(text,text,text) to authenticated;

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000015a4', false);

-- לעובד הזה אין משמרת משובצת כרגע. זה סירוב עסקי, לא סירוב הרשאה.
select t_sqlstate('כניסה בלי משמרת נכשלת כ-P0001 ולא כ-42501',
  $$select attendance_clock_in()$$, 'P0001');
select t_sqlstate('ויציאה בלי משמרת פתוחה כמוה',
  $$select attendance_clock_out()$$, 'P0001');

-- ומי שבאמת אין לו את המפתח מקבל 42501, כפי שצריך
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000015a1', false);
select t_sqlstate('ולמי שאין לו attendance.clock — 42501',
  $$select attendance_clock_in()$$, '42501');

reset role;
select set_config('request.jwt.claim.sub', '', false);
