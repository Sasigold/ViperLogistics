\pset tuples_only on
\pset format unaligned

-- ===========================================================================
-- 23: מה שהלקוח רואה, מה שהוא עורך, ומה שאושר לביצוע (0109).
--
--   * **הלקוח אינו כותב את המחיר שהוא משלם.** ‏11 בדקה שאין לו `pricing.edit`;
--     היא לא בדקה מה קורה אם מישהו כן יעניק לו אותו. הפוליסה מפסיקה לשאול
--     רק על המפתח, ולכן זו הבדיקה: מפתח ביד, וכתיבה חסומה.
--   * **שדות הלו״ז נקבעים פר-לקוח.** מוסתר/נראה/ניתן-לעריכה, והאכיפה היא
--     בטריגר ולא במסך. ‏11 בודקת את הכיוון הבסיסי (סגור עד שנפתח); כאן
--     נבדקים שני הלקוחות זה מול זה — אותו תפקיד בדיוק, קונפיגורציה אחרת.
--   * **אישור לביצוע.** מנהל מערכת בלבד, דרך ה-RPC בלבד, והלקוח קורא.
--
-- החבילה מקימה שני לקוחות, אירוע, משימות ושלוש דמויות משלה ואינה נשענת על אף
-- חבילה קודמת. האירוע יושב ב-current_date + 370, מעבר לכל טווח אחר.
-- ===========================================================================

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000023a1', 'c23-mgr-a@vl.test'),
  ('00000000-0000-0000-0000-0000000023a2', 'c23-mgr-b@vl.test'),
  ('00000000-0000-0000-0000-0000000023a3', 'c23-admin@vl.test'),
  ('00000000-0000-0000-0000-0000000023a4', 'c23-staff@vl.test');

insert into customers (id, name) values
  ('10000000-0000-0000-0000-00000000023a', 'לקוח 23 א'),
  ('10000000-0000-0000-0000-00000000023b', 'לקוח 23 ב');

insert into profiles (id, user_id, user_kind, is_admin, full_name, customer_id) values
  ('20000000-0000-0000-0000-0000000023a1', '00000000-0000-0000-0000-0000000023a1',
   'customer_user', false, 'מנהל אצל לקוח א', '10000000-0000-0000-0000-00000000023a'),
  ('20000000-0000-0000-0000-0000000023a2', '00000000-0000-0000-0000-0000000023a2',
   'customer_user', false, 'מנהל אצל לקוח ב', '10000000-0000-0000-0000-00000000023b'),
  ('20000000-0000-0000-0000-0000000023a3', '00000000-0000-0000-0000-0000000023a3',
   'staff', true,  'מנהל מערכת 23', null),
  ('20000000-0000-0000-0000-0000000023a4', '00000000-0000-0000-0000-0000000023a4',
   'staff', false, 'רכז 23', null);

insert into profile_roles (profile_id, role_id)
select p.pid, r.id from (values
  ('20000000-0000-0000-0000-0000000023a1'::uuid, 'customer_manager'),
  ('20000000-0000-0000-0000-0000000023a2'::uuid, 'customer_manager'),
  ('20000000-0000-0000-0000-0000000023a4'::uuid, 'dispatcher')
) as p(pid, rkey) join permission_roles r on r.key = p.rkey;

-- אירוע ומשימה לכל לקוח
insert into events (id, customer_id, event_number, event_date, end_client_name, status_id)
select x.id, x.cid, x.num, current_date + 370, 'לקוח קצה 23',
       (select id from statuses where entity = 'event' and code = 'planned' and deleted_at is null)
from (values
  ('30000000-0000-0000-0000-00000000023a'::uuid, '10000000-0000-0000-0000-00000000023a'::uuid, 'EV-23A'),
  ('30000000-0000-0000-0000-00000000023b'::uuid, '10000000-0000-0000-0000-00000000023b'::uuid, 'EV-23B')
) as x(id, cid, num);

insert into tasks (id, event_id, customer_id, task_type_id, task_date,
                   onsite_start_time, hours_count, worker_count, status_id)
select x.id, x.eid, x.cid,
       (select id from task_types where code = 'setup' limit 1), current_date + 370,
       '09:00', 4, 2,
       (select id from statuses where entity = 'task' and code = 'draft' and deleted_at is null)
from (values
  ('61000000-0000-0000-0000-000000023001'::uuid, '30000000-0000-0000-0000-00000000023a'::uuid,
   '10000000-0000-0000-0000-00000000023a'::uuid),
  ('61000000-0000-0000-0000-000000023002'::uuid, '30000000-0000-0000-0000-00000000023b'::uuid,
   '10000000-0000-0000-0000-00000000023b'::uuid)
) as x(id, eid, cid);

insert into task_pricing (task_id, price, is_manual) values
  ('61000000-0000-0000-0000-000000023001', 1000, true);

-- לקוח א׳ מקבל את "הערות" לעריכה; לקוח ב׳ מקבל "הערות" מוסתר. אותו תפקיד,
-- שתי תשובות — וזו כל הנקודה.
insert into customer_board_fields (customer_id, field_key, state) values
  ('10000000-0000-0000-0000-00000000023a', 'notes',        'editable'),
  ('10000000-0000-0000-0000-00000000023a', 'hours_count',  'visible'),
  ('10000000-0000-0000-0000-00000000023b', 'notes',        'hidden')
on conflict (customer_id, field_key) do update set state = excluded.state;

-- ההענקה האישית: המפתח ביד, וזה בדיוק מה שהפוליסה מפסיקה לסמוך עליו
insert into user_permission_grants (profile_id, permission_key, allowed) values
  ('20000000-0000-0000-0000-0000000023a1', 'pricing.edit', true)
on conflict (profile_id, permission_key) do update set allowed = true;

set role authenticated;

-- ===== 1. הלקוח אינו כותב את המחיר =======================================

\echo '--- מחיר המשימה ---'

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000023a1', false);

select t_eq('למנהל הלקוח הוענק pricing.edit אישית', app.has('pricing.edit'), true);
select t_eq('והוא עדיין קורא את המחיר שלו',
  (select price from task_pricing where task_id = '61000000-0000-0000-0000-000000023001'), 1000::numeric);

-- הפוליסה שואלת גם מי הכותב, ולכן המפתח לבדו אינו פותח את הכתיבה
select t_rows('אך אינו כותב אותו', $$
  update task_pricing set price = 1 where task_id = '61000000-0000-0000-0000-000000023001'$$, 0);
select t_expect_fail('וגם לא כותב שורה חדשה', $$
  insert into task_pricing (task_id, price) values ('61000000-0000-0000-0000-000000023002', 5)$$);

select t_eq('והמחיר לא זז',
  (select price from task_pricing where task_id = '61000000-0000-0000-0000-000000023001'), 1000::numeric);

reset role;
select set_config('request.jwt.claim.sub', '', false);

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000023a4', false);
select t_expect_ok('רכז עם המפתח כן כותב', $$
  update task_pricing set price = 1200 where task_id = '61000000-0000-0000-0000-000000023001'$$);
reset role;
select set_config('request.jwt.claim.sub', '', false);

-- ===== 2. שדות הלו״ז פר-לקוח =============================================

\echo '--- שדות הלו״ז ---'

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000023a1', false);

select t_eq('לקוח א׳: "הערות" פתוח לעריכה',
  (select state::text from app.board_config('10000000-0000-0000-0000-00000000023a')
    where field_key = 'notes'), 'editable');

select t_expect_ok('ולכן הוא עורך אותן', $$
  update tasks set notes = 'הערה של לקוח א' where id = '61000000-0000-0000-0000-000000023001'$$);

-- אותו תפקיד בדיוק, שדה אחר: "משך" נשאר נראה-בלבד
select t_expect_fail('ואינו עורך את "משך", שנשאר נראה בלבד', $$
  update tasks set hours_count = 9 where id = '61000000-0000-0000-0000-000000023001'$$);

-- הקונפיגורציה עצמה אינה שלו
select t_rows('והוא אינו משנה את הקונפיגורציה של עצמו', $$
  update customer_board_fields set state = 'editable'
   where customer_id = '10000000-0000-0000-0000-00000000023a' and field_key = 'hours_count'$$, 0);

reset role;
select set_config('request.jwt.claim.sub', '', false);

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000023a2', false);

select t_eq('לקוח ב׳: אותו שדה מוסתר לגמרי',
  (select state::text from app.board_config('10000000-0000-0000-0000-00000000023b')
    where field_key = 'notes'), 'hidden');

select t_expect_fail('ולכן הוא אינו עורך אותו', $$
  update tasks set notes = 'הערה של לקוח ב' where id = '61000000-0000-0000-0000-000000023002'$$);

reset role;
select set_config('request.jwt.claim.sub', '', false);

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000023a4', false);
select t_rows('רכז אינו כותב את הקונפיגורציה — היא של מנהל המערכת', $$
  update customer_board_fields set state = 'editable'
   where customer_id = '10000000-0000-0000-0000-00000000023a' and field_key = 'hours_count'$$, 0);
select t_eq('ואיש צוות אינו נשלט בה כלל', (select count(*)::int from app.board_config(null)), 0);
reset role;
select set_config('request.jwt.claim.sub', '', false);

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000023a3', false);
select t_expect_ok('מנהל המערכת כותב אותה', $$
  update customer_board_fields set state = 'editable'
   where customer_id = '10000000-0000-0000-0000-00000000023a' and field_key = 'hours_count'$$);
reset role;
select set_config('request.jwt.claim.sub', '', false);

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000023a1', false);
select t_expect_ok('ומאותו רגע הלקוח עורך את "משך"', $$
  update tasks set hours_count = 9 where id = '61000000-0000-0000-0000-000000023001'$$);
reset role;
select set_config('request.jwt.claim.sub', '', false);

-- ===== 3. אישור לביצוע ===================================================

\echo '--- מאושר לביצוע ---'

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000023a4', false);
select t_expect_fail('רכז אינו מאשר',
  $$select set_event_approved('30000000-0000-0000-0000-00000000023a', true)$$);
reset role;
select set_config('request.jwt.claim.sub', '', false);

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000023a1', false);
select t_expect_fail('ומנהל הלקוח אינו מאשר לעצמו',
  $$select set_event_approved('30000000-0000-0000-0000-00000000023a', true)$$);
-- ‏RLS עוצרת אותו עוד לפני הטריגר: לאירוע שלו אין לו פוליסת UPDATE כלל
select t_rows('ו-RLS עוצרת אותו לפני שהטריגר בכלל נשאל', $$
  update events set approved_at = now() where id = '30000000-0000-0000-0000-00000000023a'$$, 0);
reset role;
select set_config('request.jwt.claim.sub', '', false);

-- והטריגר הוא מה שעוצר את מי ש-RLS כן מעבירה: רכז עם `events.edit` מלא.
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000023a4', false);
select t_expect_ok('רכז עורך את האירוע ככל שדה אחר', $$
  update events set notes = 'הערה של רכז' where id = '30000000-0000-0000-0000-00000000023a'$$);
select t_expect_fail('אך העמודה עצמה חסומה לכתיבה ישירה — גם לו', $$
  update events set approved_at = now() where id = '30000000-0000-0000-0000-00000000023a'$$);
reset role;
select set_config('request.jwt.claim.sub', '', false);

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000023a3', false);
select t_expect_ok('מנהל המערכת מאשר',
  $$select set_event_approved('30000000-0000-0000-0000-00000000023a', true)$$);
reset role;
select set_config('request.jwt.claim.sub', '', false);

select t_eq('והאישור נרשם עם מי שאישר',
  (select approved_by from events where id = '30000000-0000-0000-0000-00000000023a'),
  '20000000-0000-0000-0000-0000000023a3'::uuid);

select t_eq('והיומן מדווח עליו במילה ולא בחותמת זמן',
  (select new_value from event_activity
    where event_id = '30000000-0000-0000-0000-00000000023a' and field_key = 'approved_at'
    order by id desc limit 1), 'מאושר');

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000023a1', false);
select t_eq('והלקוח רואה שהאירוע שלו אושר',
  (select approved_at is not null from events where id = '30000000-0000-0000-0000-00000000023a'), true);
select t_eq('ושל לקוח אחר אינו קיים עבורו',
  (select count(*)::int from events where id = '30000000-0000-0000-0000-00000000023b'), 0);
reset role;
select set_config('request.jwt.claim.sub', '', false);

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000023a3', false);
select t_expect_ok('וההפעלה מתהפכת',
  $$select set_event_approved('30000000-0000-0000-0000-00000000023a', false)$$);
reset role;
select set_config('request.jwt.claim.sub', '', false);

select t_eq('והשדות התרוקנו',
  (select approved_at is null and approved_by is null
     from events where id = '30000000-0000-0000-0000-00000000023a'), true);

-- ===== 4. ‏0115: עריכה של הלקוח מבטלת את האישור ===========================
--
-- הדמויות והאירוע של סעיף 3 ממשיכים. ‏a1 הוא מנהל הלקוח, a3 מנהל המערכת,
-- ו-a4 רכז עם `events.edit` — כלומר "המשרד".

\echo '--- והאישור יורד כשהלקוח משנה ---'

-- מאשרים מחדש: סעיף 3 הסתיים בביטול אישור
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000023a3', false);
select t_expect_ok('מנהל המערכת מאשר שוב',
  $$select set_event_approved('30000000-0000-0000-0000-00000000023a', true)$$);
reset role;
select set_config('request.jwt.claim.sub', '', false);

-- ── המשרד עורך: האישור שורד ──────────────────────────────────────────────
-- אילו כל שמירה של מנהל הייתה מורידה את האישור, האישור היה צעד שאי אפשר
-- להשלים: מסמנים, מתקנים פסיק, והסימון נעלם.
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000023a4', false);
select t_expect_ok('המשרד עורך את האירוע', $$
  select update_event('30000000-0000-0000-0000-00000000023a',
                      '{"notes":"הערה שהמשרד כתב אחרי האישור"}'::jsonb)$$);
reset role;
select set_config('request.jwt.claim.sub', '', false);

select t_eq('והאישור שורד — המשרד הוא מי שאישר',
  (select approved_at is not null from events where id = '30000000-0000-0000-0000-00000000023a'),
  true);

-- ── הלקוח שומר בלי לשנות דבר: האישור שורד ────────────────────────────────
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000023a1', false);
select t_expect_ok('הלקוח שומר את אותו ערך בדיוק', $$
  select update_event('30000000-0000-0000-0000-00000000023a',
                      '{"end_client_name":"לקוח קצה 23"}'::jsonb)$$);
reset role;
select set_config('request.jwt.claim.sub', '', false);

select t_eq('שמירה שלא שינתה דבר אינה מבטלת',
  (select approved_at is not null from events where id = '30000000-0000-0000-0000-00000000023a'),
  true);

-- ── הלקוח משנה באמת: האישור יורד ─────────────────────────────────────────
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000023a1', false);
select t_expect_ok('הלקוח משנה שם לקוח קצה', $$
  select update_event('30000000-0000-0000-0000-00000000023a',
                      '{"end_client_name":"שם אחר לגמרי"}'::jsonb)$$);
reset role;
select set_config('request.jwt.claim.sub', '', false);

select t_eq('והאישור ירד',
  (select approved_at is null and approved_by is null
     from events where id = '30000000-0000-0000-0000-00000000023a'), true);

select t_eq('והיומן מספר גם על הירידה, לא רק על העלייה',
  (select new_value is null from event_activity
    where event_id = '30000000-0000-0000-0000-00000000023a' and field_key = 'approved_at'
    order by id desc limit 1), true);

-- ── והלו״ז, שאינו עובר ב-update_event ────────────────────────────────────
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000023a3', false);
select t_expect_ok('מנהל המערכת מאשר בשלישית',
  $$select set_event_approved('30000000-0000-0000-0000-00000000023a', true)$$);
reset role;
select set_config('request.jwt.claim.sub', '', false);

-- שדה "משך" נפתח ללקוח הזה בסעיף 2, ולכן הכתיבה עוברת את 0109
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000023a1', false);
select t_expect_ok('הלקוח משנה משך מתא בלו״ז', $$
  update tasks set hours_count = 11 where id = '61000000-0000-0000-0000-000000023001'$$);
reset role;
select set_config('request.jwt.claim.sub', '', false);

select t_eq('וגם זה מבטל — זה בדיוק מה שהאישור אישר',
  (select approved_at is null from events where id = '30000000-0000-0000-0000-00000000023a'),
  true);

-- ── אבל סטטוס המשימה הוא תכנון, ולא מפרט ─────────────────────────────────
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000023a3', false);
select t_expect_ok('מנהל המערכת מאשר ברביעית',
  $$select set_event_approved('30000000-0000-0000-0000-00000000023a', true)$$);
reset role;
select set_config('request.jwt.claim.sub', '', false);

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000023a3', false);
select t_expect_ok('ומעביר את המשימה ל"מתוכנן"', $$
  update tasks set status_id = (select id from statuses
                                 where entity = 'task' and code = 'planned' and deleted_at is null)
   where id = '61000000-0000-0000-0000-000000023001'$$);
reset role;
select set_config('request.jwt.claim.sub', '', false);

select t_eq('שינוי סטטוס אינו מבטל את האישור',
  (select approved_at is not null from events where id = '30000000-0000-0000-0000-00000000023a'),
  true);
