\pset tuples_only on
\pset format unaligned

-- ===========================================================================
-- 22: מי משבץ, מי רואה, וכמה זה עולה כשהקנס גדול מהמחיר (0108).
--
-- שלוש טענות שאף בדיקה קודמת לא שאלה:
--
--   * **עובד קבלן אינו משבץ.** ‏14 בדקה את מנהל הקבלן, ו-11 את התפקידים —
--     ואף אחת מהן לא בדקה את החשבון שאין לו תפקיד כלל, שהוא בדיוק זה שנפל
--     חזרה לשכבת הקהל וקיבל שם `contractors.assign_workers`. ‏`contractor_assign_worker`
--     הוא `security definer`, ולכן הפוליסה על הטבלה לא עצרה אותו.
--   * **הדו-כובע רואה את המשימות של הקבלן שלו.** ‏15 בדקה שיש לו את
--     ה*מפתחות*; היא לא בדקה מה הוא רואה איתם. מה שדלף הוא ההפרש: מפתחות
--     מלאים ולוח ריק, ומשם גם מסך כספים שמחזיר אפסים.
--   * **קנס יכול לרדת מתחת לאפס.** ‏`greatest(0, …)` הפך חוב להנחה.
--
-- החבילה מקימה קבלן, לקוח, אירוע, משימות ושלוש דמויות משלה ואינה נשענת על אף
-- חבילה קודמת. האירוע יושב ב-current_date + 360, מעבר לכל טווח אחר, והיא רצה
-- אחרונה כי היא מזריעה שיבוצים ותמחור שאינם מנוקים.
--
-- הזריעה רצה בלי JWT (auth.uid() = null), ולכן הטריגרים מדלגים.
-- ===========================================================================

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000022a1', 'c22-worker@vl.test'),
  ('00000000-0000-0000-0000-0000000022a2', 'c22-manager@vl.test'),
  ('00000000-0000-0000-0000-0000000022a3', 'c22-dual@vl.test');

insert into customers (id, name) values
  ('10000000-0000-0000-0000-000000000022', 'לקוח 22');

-- ‏`default_task_price` בלבד אינו מפעיל את מנוע המחיר (0092 §v_active), ולכן
-- הקבלן נושא גם קנס — וזה גם מה שמאפשר לבדוק את הריצפה.
insert into contractors (id, name, default_task_price, no_show_penalty) values
  ('11000000-0000-0000-0000-00000000022a', 'קבלן 22', 300, 500);

insert into contractor_workers (id, contractor_id, full_name) values
  ('12000000-0000-0000-0000-00000000022a', '11000000-0000-0000-0000-00000000022a', 'סגל 22'),
  ('12000000-0000-0000-0000-00000000022b', '11000000-0000-0000-0000-00000000022a', 'סגל 22 ב');

insert into profiles (id, user_id, user_kind, full_name, contractor_id, contractor_worker_id) values
  -- **עובד הקבלן, בלי שום תפקיד** — הוא הנבדק המרכזי כאן
  ('20000000-0000-0000-0000-0000000022a1', '00000000-0000-0000-0000-0000000022a1',
   'contractor_user', 'עובד קבלן בלי תפקיד', '11000000-0000-0000-0000-00000000022a',
   '12000000-0000-0000-0000-00000000022a'),
  -- מנהל הקבלן, לביקורת: אסור שהתיקון ייקח ממנו דבר
  ('20000000-0000-0000-0000-0000000022a2', '00000000-0000-0000-0000-0000000022a2',
   'contractor_user', 'מנהל קבלן 22', '11000000-0000-0000-0000-00000000022a', null),
  -- הדו-כובע: איש צוות לכל דבר, שמקושר לאותו קבלן
  ('20000000-0000-0000-0000-0000000022a3', '00000000-0000-0000-0000-0000000022a3',
   'staff', 'עובד שגם קבלן 22', '11000000-0000-0000-0000-00000000022a', null);

insert into profile_roles (profile_id, role_id)
select p.pid, r.id from (values
  ('20000000-0000-0000-0000-0000000022a2'::uuid, 'contractor_manager'),
  -- ‏'worker' מביא איתו היקף 'own' על משימות — וזה בדיוק מה שחסם את הדו-כובע
  ('20000000-0000-0000-0000-0000000022a3'::uuid, 'worker'),
  ('20000000-0000-0000-0000-0000000022a3'::uuid, 'staff_contractor')
) as p(pid, rkey) join permission_roles r on r.key = p.rkey;

insert into events (id, customer_id, event_number, event_date, end_client_name, status_id)
select '30000000-0000-0000-0000-000000000022', '10000000-0000-0000-0000-000000000022',
       'EV-22', current_date + 360, 'לקוח קצה 22',
       (select id from statuses where entity = 'event' and code = 'planned' and deleted_at is null);

-- שתי משימות: אחת שפורסמה ואחת שלא. שתיהן מואצלות לאותו קבלן — הדו-כובע
-- אמור לראות את שתיהן, כי בכובע הקבלני הוא רואה ככל מנהל קבלן.
insert into tasks (id, event_id, customer_id, task_type_id, task_date,
                   onsite_start_time, hours_count, worker_count, status_id)
select x.id, '30000000-0000-0000-0000-000000000022', '10000000-0000-0000-0000-000000000022',
       (select id from task_types where code = 'setup' limit 1), current_date + 360,
       '09:00', 4, 2,
       (select id from statuses where entity = 'task' and code = x.code and deleted_at is null)
from (values
  ('61000000-0000-0000-0000-000000022001'::uuid, 'assigned'),
  ('61000000-0000-0000-0000-000000022002'::uuid, 'draft')
) as x(id, code);

insert into task_contractor_terms (task_id, contractor_id, price) values
  ('61000000-0000-0000-0000-000000022001', '11000000-0000-0000-0000-00000000022a', 300),
  ('61000000-0000-0000-0000-000000022002', '11000000-0000-0000-0000-00000000022a', 300);

set role authenticated;

-- ===== 1. עובד קבלן אינו משבץ ============================================

\echo '--- עובד קבלן בלי תפקיד ---'

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000022a1', false);

select t_eq('אין לו את מפתח הפורטל',   app.has('portal.assign_workers'), false);
-- זה המפתח שדלף: ה*משרדי*, שנתן לו לשבץ סגל של כל קבלן, לא רק של שלו
select t_eq('ואין לו את המפתח המשרדי', app.has('contractors.assign_workers'), false);

select t_expect_fail('ולכן ה-RPC דוחה אותו',
  $$select contractor_assign_worker('61000000-0000-0000-0000-000000022001',
      '12000000-0000-0000-0000-00000000022b', null, true, null)$$);

select t_eq('ולא נוצר שיבוץ',
  (select count(*)::int from task_contractor_workers
    where task_id = '61000000-0000-0000-0000-000000022001'), 0);

-- הלוח עצמו נשאר פתוח לו: מה שנסגר הוא הכתיבה, לא הקריאה
select t_eq('הלוח עצמו נשאר פתוח לו', app.has('board.view'), true);

reset role;
select set_config('request.jwt.claim.sub', '', false);

\echo '--- מנהל הקבלן לא איבד דבר ---'

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000022a2', false);

select t_eq('מנהל הקבלן משבץ דרך מפתח הפורטל', app.has('portal.assign_workers'), true);
-- והמשרדי נשאר סגור לו גם אחרי התיקון (0075 §2) — הוא משבץ את שלו בלבד
select t_eq('והמפתח המשרדי נשאר סגור לו',      app.has('contractors.assign_workers'), false);

select t_expect_ok('והוא משבץ את הסגל שלו',
  $$select contractor_assign_worker('61000000-0000-0000-0000-000000022001',
      '12000000-0000-0000-0000-00000000022a', null, true, null)$$);

reset role;
select set_config('request.jwt.claim.sub', '', false);

select t_eq('נרשם שיבוץ אחד',
  (select count(*)::int from task_contractor_workers
    where task_id = '61000000-0000-0000-0000-000000022001'), 1);

-- ===== 2. הדו-כובע רואה את מה שהואצל לקבלן שלו ============================

\echo '--- עובד שהוא גם קבלן ---'

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000022a3', false);

select t_eq('הוא staff, ומקושר לקבלן',
  (select app.user_kind() || '/' || (app.contractor_id() is not null)::text), 'staff/true');

-- זו הטענה: לפני 0108 שתי אלה החזירו 0, כי היקף ה-'own' של תפקיד השטח
-- הכיר רק בשיבוץ אישי ולא בהאצלה לקבלן שלו.
select t_eq('הוא רואה את שתי המשימות של הקבלן שלו',
  (select count(*)::int from tasks
    where event_id = '30000000-0000-0000-0000-000000000022'), 2);

select t_eq('וגם בלו״ז עצמו',
  (select count(*)::int from work_board_view
    where event_id = '30000000-0000-0000-0000-000000000022'), 2);

-- כולל זו שלא פורסמה: בכובע הקבלני הוא רואה ככל מנהל קבלן, ולא כעובד שטח
select t_eq('כולל זו שלא פורסמה',
  (select count(*)::int from tasks
    where id = '61000000-0000-0000-0000-000000022002'), 1);

select t_eq('והאירוע נפתח לו',
  (select count(*)::int from events
    where id = '30000000-0000-0000-0000-000000000022'), 1);

-- ומכאן מסך הכספים: `contractor_dashboard` הוא security invoker, ולכן הוא
-- החזיר אפסים בדיוק כל עוד `tasks` היה ריק עבורו.
select t_eq('ומסך הכספים סופר את שתיהן',
  ((contractor_dashboard(current_date + 359, current_date + 361)) ->> 'tasks_count')::int, 2);

select t_eq('ומסכם את הצפוי',
  ((contractor_dashboard(current_date + 359, current_date + 361)) ->> 'expected_total')::numeric, 600::numeric);

reset role;
select set_config('request.jwt.claim.sub', '', false);

-- ===== 3. הקנס יורד מתחת לאפס ============================================

\echo '--- קנס גדול מהמחיר ---'

-- עובד אחד משובץ (מנהל הקבלן שיבץ אותו למעלה), והוא לא התייצב. הבסיס 300,
-- הקנס 500 — כלומר חוב של 200, ולא "אפס".
update task_contractor_workers set no_show = true
 where task_id = '61000000-0000-0000-0000-000000022001'
   and contractor_worker_id = '12000000-0000-0000-0000-00000000022a';

select t_eq('המחיר יורד מתחת לאפס',
  (select price from task_contractor_terms
    where task_id = '61000000-0000-0000-0000-000000022001'
      and contractor_id = '11000000-0000-0000-0000-00000000022a'), -200::numeric);

-- הפירוט לא השתנה: המנהל ממשיך לראות ממה מורכב המספר
select t_eq('והפירוט ממשיך לומר ממה הוא מורכב',
  (select (price_parts ->> 'base') || '/' || (price_parts ->> 'penalty_total')
     from task_contractor_terms
    where task_id = '61000000-0000-0000-0000-000000022001'
      and contractor_id = '11000000-0000-0000-0000-00000000022a'), '300.00/500.00');

-- וההיפוך חוזר: הסרת הסימון מחזירה את המחיר המלא
update task_contractor_workers set no_show = false
 where task_id = '61000000-0000-0000-0000-000000022001'
   and contractor_worker_id = '12000000-0000-0000-0000-00000000022a';

select t_eq('והסרת הסימון מחזירה את המחיר',
  (select price from task_contractor_terms
    where task_id = '61000000-0000-0000-0000-000000022001'
      and contractor_id = '11000000-0000-0000-0000-00000000022a'), 300::numeric);
