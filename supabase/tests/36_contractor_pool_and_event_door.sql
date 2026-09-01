\pset tuples_only on
\pset format unaligned

-- ===========================================================================
-- 36: עובד שמשויך לקבלן נכנס לסגל שלו, ועובד קבלן נכנס לדף האירוע (0148).
--
-- שתי טענות חדשות ושתי טענות ביקורת:
--
--   * **איש צוות שנושא `contractor_id` מופיע במאגר השיבוץ של הקבלן שלו.**
--     עד 0148 זרוע החשבונות של `contractor_assignable_workers` סיננה על
--     `user_kind = 'contractor_user'`, ועובד צוות משויך לא הופיע לעולם.
--   * **תפקיד `contractor_worker` מחזיק `events.view`.** הדלת של `/events/:id`
--     — ‏RLS כבר פתחה לו את השורה (0066), והמסך נעצר על המפתח.
--   * ביקורת: עובד הקבלן ממשיך לראות רק משימות שפורסמו שהוא משובץ בהן,
--     ומנהל הקבלן ממשיך לראות את הכול — 0148 לא נגעה ב-RLS של tasks.
--
-- החבילה מקימה לקוח, קבלן, אירוע ושלוש דמויות משלה ב-current_date + 520,
-- מעבר לכל טווח אחר. הזריעה רצה בלי JWT (auth.uid() = null), והטריגרים מדלגים.
-- ===========================================================================

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000036a0', 'c36-admin@vl.test'),
  ('00000000-0000-0000-0000-0000000036a1', 'c36-manager@vl.test'),
  ('00000000-0000-0000-0000-0000000036a2', 'c36-worker@vl.test'),
  ('00000000-0000-0000-0000-0000000036a3', 'c36-staff@vl.test');

insert into customers (id, name) values
  ('10000000-0000-0000-0000-000000000036', 'לקוח 36');
insert into contractors (id, name) values
  ('11000000-0000-0000-0000-00000000036a', 'קבלן 36');

-- שורת סגל אחת ברוסטר — של עובד הקבלן שיש לו התחברות.
insert into contractor_workers (id, contractor_id, full_name) values
  ('12000000-0000-0000-0000-00000000036a', '11000000-0000-0000-0000-00000000036a', 'עובד קבלן 36');

insert into profiles (id, user_id, user_kind, is_admin, full_name) values
  ('20000000-0000-0000-0000-0000000036a0', '00000000-0000-0000-0000-0000000036a0',
   'staff', true, 'מנהל 36');

insert into profiles (id, user_id, user_kind, full_name, contractor_id, contractor_worker_id) values
  -- מנהל הקבלן
  ('20000000-0000-0000-0000-0000000036a1', '00000000-0000-0000-0000-0000000036a1',
   'contractor_user', 'מנהל קבלן 36', '11000000-0000-0000-0000-00000000036a', null),
  -- עובד הקבלן, מקושר לשורת הסגל שלו
  ('20000000-0000-0000-0000-0000000036a2', '00000000-0000-0000-0000-0000000036a2',
   'contractor_user', 'עובד קבלן 36', '11000000-0000-0000-0000-00000000036a',
   '12000000-0000-0000-0000-00000000036a'),
  -- **הנבדק המרכזי**: איש צוות מן השורה שהמשרד שייך לקבלן במסך העובדים
  ('20000000-0000-0000-0000-0000000036a3', '00000000-0000-0000-0000-0000000036a3',
   'staff', 'איש צוות משויך 36', '11000000-0000-0000-0000-00000000036a', null);

insert into profile_roles (profile_id, role_id)
select p.pid, r.id from (values
  ('20000000-0000-0000-0000-0000000036a1'::uuid, 'contractor_manager'),
  ('20000000-0000-0000-0000-0000000036a2'::uuid, 'contractor_worker'),
  ('20000000-0000-0000-0000-0000000036a3'::uuid, 'worker')
) as p(pid, rkey) join permission_roles r on r.key = p.rkey;

-- אירוע (ההקמה והפירוק נולדים איתו כטיוטות), ושתי המשימות מואצלות לקבלן.
insert into events (id, customer_id, event_number, event_date, end_client_name, status_id)
values ('30000000-0000-0000-0000-000000000036', '10000000-0000-0000-0000-000000000036',
        'EV-36', current_date + 520, 'קצה 36',
        (select id from statuses where entity = 'event' and code = 'planned' and deleted_at is null));

insert into task_contractor_terms (task_id, contractor_id, price, work_site)
select t.id, '11000000-0000-0000-0000-00000000036a', 0, 'field'
  from tasks t where t.event_id = '30000000-0000-0000-0000-000000000036' and t.deleted_at is null;

-- ההקמה מתפרסמת; הפירוק נשאר טיוטה. עובד הקבלן משובץ על ההקמה בלבד.
update tasks set status_id =
    (select id from statuses where entity = 'task' and code = 'assigned' and deleted_at is null)
 where event_id = '30000000-0000-0000-0000-000000000036'
   and task_type_id = (select id from task_types where code = 'setup' limit 1);

insert into task_contractor_workers (task_id, contractor_worker_id, work_site)
select t.id, '12000000-0000-0000-0000-00000000036a', 'field'
  from tasks t where t.event_id = '30000000-0000-0000-0000-000000000036'
   and t.task_type_id = (select id from task_types where code = 'setup' limit 1)
   and t.deleted_at is null limit 1;

\echo '--- איש צוות משויך נכנס למאגר השיבוץ של הקבלן (0148) ---'
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000036a1', false);

-- ‏0150: השיוך הוא הקבלה לסגל, ולכן יש לו שורת סגל כבר עכשיו — וזה מה
-- שפותח עליו את מתגי התפקיד ומעקב האיחורים במסך "העובדים שלי".
select t_eq('איש הצוות המשויך מופיע במאגר, עם שורת סגל',
  (select count(*)::int from jsonb_array_elements(contractor_assignable_workers()) x
    where x ->> 'profile_id' = '20000000-0000-0000-0000-0000000036a3'
      and x ->> 'worker_id' is not null), 1);

-- והמתגים באמת ניתנים להגדרה: התפקיד נכתב על שורת הסגל שנוצרה.
insert into contractor_worker_roles (contractor_worker_id, role)
select p.contractor_worker_id, 'driver' from profiles p
 where p.id = '20000000-0000-0000-0000-0000000036a3';

select t_eq('ואפשר להגדיר עליו תפקיד נהג',
  (select (x -> 'roles') @> '"driver"'::jsonb
     from jsonb_array_elements(contractor_assignable_workers()) x
    where x ->> 'profile_id' = '20000000-0000-0000-0000-0000000036a3'), true);

select t_expect_ok('ומנהל הקבלן משבץ אותו על ההקמה',
  $$select contractor_assign_worker(
      (select t.id from tasks t where t.event_id = '30000000-0000-0000-0000-000000000036'
         and t.task_type_id = (select id from task_types where code='setup' limit 1)
         and t.deleted_at is null limit 1),
      null, '20000000-0000-0000-0000-0000000036a3', true, null, null)$$);

reset role;
select set_config('request.jwt.claim.sub', '', false);

-- ואחרי השיבוץ עדיין שורה אחת: הגשר של 0121 מוצא את מה ש-0150 כבר יצר,
-- ואינו פותח שנייה לצדה.
select t_eq('ועדיין שורת סגל אחת אצל הקבלן',
  (select count(*)::int from contractor_workers w
     join profiles p on p.contractor_worker_id = w.id
    where p.id = '20000000-0000-0000-0000-0000000036a3'
      and w.contractor_id = '11000000-0000-0000-0000-00000000036a'
      and w.deleted_at is null), 1);

\echo '--- הדלת של דף האירוע נפתחת לעובד הקבלן (0148) ---'
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000036a2', false);

select t_eq('תפקיד עובד הקבלן מחזיק events.view', app.has('events.view'), true);
select t_eq('אך רשימת האירועים נשארת סגורה לו', app.has('events.list'), false);
select t_eq('והאירוע שהוא משובץ בו נפתח',
  (select count(*)::int from events where id = '30000000-0000-0000-0000-000000000036'), 1);

-- ביקורת 0148: ה-RLS לא זזה — הוא רואה רק את מה שפורסם והוא משובץ בו.
select t_eq('והוא רואה רק את המשימה שפורסמה',
  (select count(*)::int from tasks
    where event_id = '30000000-0000-0000-0000-000000000036'), 1);

reset role;
select set_config('request.jwt.claim.sub', '', false);

\echo '--- הספק שהקבלן אינו רשאי לקרוא (הקריסה של דף האירוע) ---'
-- דף האירוע שולף `event_suppliers(supplier_id, suppliers(name))`. שתי הפוליסות
-- אינן זהות: הקישור נגזר מהאירוע, והספק עצמו דורש מפתח משלו. הקבלן מקבל
-- שורת קישור עם ספק `null`, וקריאה עיוורת של `.name` הפילה לו את המסך.
-- אותה אסימטריה בדיוק כבר מוכרזת ב-0147 על הלו״ז (`supplier_names = null`).
insert into suppliers (id, customer_id, name) values
  ('5a000000-0000-0000-0000-000000000036', '10000000-0000-0000-0000-000000000036', 'ספק 36');
insert into event_suppliers (event_id, supplier_id) values
  ('30000000-0000-0000-0000-000000000036', '5a000000-0000-0000-0000-000000000036');

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000036a1', false);

select t_eq('מנהל הקבלן רואה את שורת הקישור לספק',
  (select count(*)::int from event_suppliers
    where event_id = '30000000-0000-0000-0000-000000000036'), 1);
select t_eq('אך לא את הספק עצמו — ולכן ההטמעה חוזרת null',
  (select count(*)::int from event_suppliers es
     join suppliers s on s.id = es.supplier_id
    where es.event_id = '30000000-0000-0000-0000-000000000036'), 0);

reset role;
select set_config('request.jwt.claim.sub', '', false);

\echo '--- מנהל הקבלן לא איבד דבר ---'
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000036a1', false);

-- הצמצום לסטטוס "משובץ" הוא של מסך הלו״ז (0148, בצד הלקוח); ה-RLS נשארה
-- פתוחה כדי שמסך הכספים ימשיך לספור גם את מה שטרם פורסם (ראו 22).
select t_eq('מנהל הקבלן ממשיך לראות את שתי המשימות',
  (select count(*)::int from tasks
    where event_id = '30000000-0000-0000-0000-000000000036'), 2);

reset role;
select set_config('request.jwt.claim.sub', '', false);

\echo '--- החלפת קבלן: השורה הישנה נשארת, וחדשה נפתחת (0149+0150) ---'
insert into contractors (id, name) values
  ('11000000-0000-0000-0000-00000000036b', 'קבלן 36ב');

-- שומרים את מזהה השורה הישנה, כדי לוודא שהקישור באמת עבר לשורה אחרת.
create temp table t36_before as
select contractor_worker_id as wid from profiles
 where id = '20000000-0000-0000-0000-0000000036a3';

update profiles set contractor_id = '11000000-0000-0000-0000-00000000036b'
 where id = '20000000-0000-0000-0000-0000000036a3';

select t_eq('הקישור לשורה הישנה נעזב לטובת שורה אצל הקבלן החדש',
  (select w.contractor_id from profiles p
     join contractor_workers w on w.id = p.contractor_worker_id
    where p.id = '20000000-0000-0000-0000-0000000036a3'),
  '11000000-0000-0000-0000-00000000036b'::uuid);

select t_eq('וזו אינה השורה הישנה',
  (select p.contractor_worker_id is distinct from b.wid
     from profiles p, t36_before b
    where p.id = '20000000-0000-0000-0000-0000000036a3'), true);

select t_eq('ושורת הסגל הישנה נשארה אצל הקבלן הישן, כהיסטוריה',
  (select count(*)::int from contractor_workers w
    where w.contractor_id = '11000000-0000-0000-0000-00000000036a'
      and w.full_name = 'איש צוות משויך 36' and w.deleted_at is null), 1);

-- וחזרה לקבלן הראשון מתחברת לשורה שנעזבה, ולא פותחת שלישית.
update profiles set contractor_id = '11000000-0000-0000-0000-00000000036a'
 where id = '20000000-0000-0000-0000-0000000036a3';

select t_eq('חזרה לקבלן הראשון מחזירה אותו לשורה שלו',
  (select p.contractor_worker_id = b.wid
     from profiles p, t36_before b
    where p.id = '20000000-0000-0000-0000-0000000036a3'), true);

select t_eq('ולא נפתחה שורה שלישית אצל הקבלן הראשון',
  (select count(*)::int from contractor_workers w
    where w.contractor_id = '11000000-0000-0000-0000-00000000036a'
      and w.full_name = 'איש צוות משויך 36' and w.deleted_at is null), 1);

drop table t36_before;
