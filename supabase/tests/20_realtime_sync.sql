\pset tuples_only on
\pset format unaligned

-- ===========================================================================
-- 20: סנכרון און-ליין לקהל הרלוונטי בלבד (0101).
--
-- שני צדדים לאותה הבטחה: שינוי במשימה שולח אות לכל מי שהיא נוגעת לו — ולא
-- לאף אחד אחר; ופוליסת הערוצים מסרבת למי שמנסה להאזין לערוץ שאינו שלו.
-- ‏realtime.send של הבדיקות (00_bootstrap) כותב לטבלה במקום לרשת, ולכן אפשר
-- לספור בדיוק אילו ערוצים שמעו על כל שינוי.
--
-- החבילה מקימה לקוח, קבלן, אירוע, חמישה פרופילים ומשימות משלה ואינה נשענת על
-- אף חבילה קודמת. האירוע יושב ב-current_date + 340, מעבר לכל טווח של חבילה
-- אחרת. היא מרוקנת את realtime.messages בין תרחישים — אף חבילה אחרת אינה
-- קוראת את הטבלה הזו.
-- ===========================================================================

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000020a1', 'sync-worker1@vl.test'),
  ('00000000-0000-0000-0000-0000000020a2', 'sync-worker2@vl.test'),
  ('00000000-0000-0000-0000-0000000020a3', 'sync-dispatcher@vl.test'),
  ('00000000-0000-0000-0000-0000000020a4', 'sync-customer@vl.test'),
  ('00000000-0000-0000-0000-0000000020a5', 'sync-admin@vl.test'),
  ('00000000-0000-0000-0000-0000000020a6', 'sync-scoped@vl.test');

insert into customers (id, name, color, contact_phone) values
  ('10000000-0000-0000-0000-000000000020', 'לקוח הסנכרון', '#204060', '050-0000020');

insert into contractors (id, name) values
  ('11000000-0000-0000-0000-000000000020', 'קבלן הסנכרון');

insert into profiles (id, user_id, user_kind, is_admin, full_name, customer_id) values
  ('20000000-0000-0000-0000-0000000020a1', '00000000-0000-0000-0000-0000000020a1',
   'staff', false, 'עובד סנכרון א', null),
  ('20000000-0000-0000-0000-0000000020a2', '00000000-0000-0000-0000-0000000020a2',
   'staff', false, 'עובד סנכרון ב', null),
  ('20000000-0000-0000-0000-0000000020a3', '00000000-0000-0000-0000-0000000020a3',
   'staff', false, 'סדרן הסנכרון', null),
  ('20000000-0000-0000-0000-0000000020a4', '00000000-0000-0000-0000-0000000020a4',
   'customer_user', false, 'משתמש לקוח הסנכרון', '10000000-0000-0000-0000-000000000020'),
  ('20000000-0000-0000-0000-0000000020a5', '00000000-0000-0000-0000-0000000020a5',
   'staff', true, 'אדמין הסנכרון', null),
  ('20000000-0000-0000-0000-0000000020a6', '00000000-0000-0000-0000-0000000020a6',
   'staff', false, 'סגל בהיקף לקוח', null);

-- העובדים נושאים 'own' על tasks דרך תפקיד worker; הסדרן — dispatcher, בלי היקף.
insert into profile_roles (profile_id, role_id)
select p, id from permission_roles r,
  unnest(array['20000000-0000-0000-0000-0000000020a1'::uuid,
               '20000000-0000-0000-0000-0000000020a2'::uuid]) p
where r.key = 'worker';
insert into profile_roles (profile_id, role_id)
select '20000000-0000-0000-0000-0000000020a3', id from permission_roles where key = 'dispatcher';

-- הסגל המוגבל: היקף אישי הנקוב בלקוח הסנכרון, בלי 'own' — רואה את הלקוח, לא הכול.
insert into user_permission_grants (profile_id, permission_key, allowed) values
  ('20000000-0000-0000-0000-0000000020a6', 'tasks.view', true);
insert into permission_scopes (profile_id, resource, scope_type, scope_values) values
  ('20000000-0000-0000-0000-0000000020a6', 'tasks', 'customers',
   array['10000000-0000-0000-0000-000000000020'::uuid]);

insert into events (id, customer_id, end_client_name, event_date, location_text) values
  ('30000000-0000-0000-0000-000000000020', '10000000-0000-0000-0000-000000000020',
   'אירוע הסנכרון', current_date + 340, 'תל אביב');

-- משימה משובצת: לקוח, קבלן (דרך terms — המודל של 0096), ועובד א עליה.
insert into tasks (id, event_id, customer_id, task_type_id, task_date,
                   onsite_start_time, hours_count, status_id, worker_count)
select '61000000-0000-0000-0000-000000020001', '30000000-0000-0000-0000-000000000020',
       '10000000-0000-0000-0000-000000000020',
       (select id from task_types where code = 'setup' limit 1),
       current_date + 340, '08:00', 3.0,
       (select id from statuses where entity = 'task' and code = 'assigned' and deleted_at is null),
       1;

insert into task_contractor_terms (task_id, contractor_id, price) values
  ('61000000-0000-0000-0000-000000020001', '11000000-0000-0000-0000-000000000020', 0);

insert into task_assignments (task_id, profile_id, role, work_site) values
  ('61000000-0000-0000-0000-000000020001', '20000000-0000-0000-0000-0000000020a1', 'worker', 'field');

-- ===== 1. שינוי במשימה מגיע לקהל שלה — ולא לעובד שאינו משובץ ================

truncate realtime.messages;

update tasks set notes = 'שינוי לבדיקת הקהל'
 where id = '61000000-0000-0000-0000-000000020001';

\echo '--- הקהל של עדכון משימה ---'
select t_eq('הסדרנים שומעים',
  exists(select 1 from realtime.messages where topic = 'sync:staff'), true);
select t_eq('הלקוח שומע',
  exists(select 1 from realtime.messages
    where topic = 'sync:customer:10000000-0000-0000-0000-000000000020'), true);
select t_eq('הקבלן שומע',
  exists(select 1 from realtime.messages
    where topic = 'sync:contractor:11000000-0000-0000-0000-000000000020'), true);
select t_eq('העובד המשובץ שומע',
  exists(select 1 from realtime.messages
    where topic = 'sync:profile:20000000-0000-0000-0000-0000000020a1'), true);
select t_eq('והעובד שאינו משובץ — לא',
  exists(select 1 from realtime.messages
    where topic = 'sync:profile:20000000-0000-0000-0000-0000000020a2'), false);
select t_eq('האות נושא את מזהה המשימה',
  (select payload -> 'ids' ? '61000000-0000-0000-0000-000000020001'
     from realtime.messages where topic = 'sync:staff' limit 1), true);
select t_eq('ואת מזהה האירוע, בשביל מסך האירוע הפתוח',
  (select payload -> 'event_ids' ? '30000000-0000-0000-0000-000000000020'
     from realtime.messages where topic = 'sync:staff' limit 1), true);

-- ===== 2. שיבוץ והסרה מדליקים את הערוץ האישי ================================

truncate realtime.messages;

insert into task_assignments (task_id, profile_id, role, work_site) values
  ('61000000-0000-0000-0000-000000020001', '20000000-0000-0000-0000-0000000020a2', 'worker', 'field');

\echo '--- שיבוץ: העובד לומד שהמשימה נהייתה שלו ---'
select t_eq('האות מגיע לערוץ האישי של המשובץ החדש',
  exists(select 1 from realtime.messages
    where topic = 'sync:profile:20000000-0000-0000-0000-0000000020a2'
      and payload ->> 'kind' = 'assignment'), true);

truncate realtime.messages;

delete from task_assignments
 where task_id = '61000000-0000-0000-0000-000000020001'
   and profile_id = '20000000-0000-0000-0000-0000000020a2';

select t_eq('וגם ההסרה מגיעה אליו — כדי שהמשימה תיעלם אצלו',
  exists(select 1 from realtime.messages
    where topic = 'sync:profile:20000000-0000-0000-0000-0000000020a2'
      and payload ->> 'kind' = 'assignment'), true);

-- וההקבלה הקבלנית: ביטול האצלה מגיע לערוץ הקבלן גם אחרי ששורת ה-terms איננה.
truncate realtime.messages;

delete from task_contractor_terms
 where task_id = '61000000-0000-0000-0000-000000020001'
   and contractor_id = '11000000-0000-0000-0000-000000000020';

select t_eq('ביטול האצלה מגיע לערוץ הקבלן',
  exists(select 1 from realtime.messages
    where topic = 'sync:contractor:11000000-0000-0000-0000-000000000020'
      and payload ->> 'kind' = 'assignment'), true);

truncate realtime.messages;

insert into task_contractor_terms (task_id, contractor_id, price) values
  ('61000000-0000-0000-0000-000000020001', '11000000-0000-0000-0000-000000000020', 0);

select t_eq('והאצלה מחדש מגיעה אליו גם היא',
  exists(select 1 from realtime.messages
    where topic = 'sync:contractor:11000000-0000-0000-0000-000000000020'
      and payload ->> 'kind' = 'assignment'), true);

-- ===== 3. משפט אחד — הודעה אחת לערוץ =======================================

truncate realtime.messages;

insert into tasks (id, event_id, customer_id, task_type_id, task_date,
                   onsite_start_time, hours_count, status_id, worker_count)
select v.id, '30000000-0000-0000-0000-000000000020',
       '10000000-0000-0000-0000-000000000020',
       (select id from task_types where code = 'setup' limit 1),
       current_date + 340, '09:00', 2.0,
       (select id from statuses where entity = 'task' and code = 'assigned' and deleted_at is null),
       1
from (values ('61000000-0000-0000-0000-000000020002'::uuid),
             ('61000000-0000-0000-0000-000000020003'::uuid),
             ('61000000-0000-0000-0000-000000020004'::uuid)) as v(id);

\echo '--- ייבוא מרובה שורות אינו מציף ---'
select t_eq('שלוש משימות במשפט אחד — הודעה אחת לסדרנים',
  (select count(*)::int from realtime.messages where topic = 'sync:staff'), 1);
select t_eq('ושלושת המזהים בתוכה',
  (select jsonb_array_length(payload -> 'ids')
     from realtime.messages where topic = 'sync:staff'), 3);

-- ===== 4. שינוי באירוע ======================================================

truncate realtime.messages;

update events set notes = 'שינוי אירוע לבדיקת הקהל'
 where id = '30000000-0000-0000-0000-000000000020';

\echo '--- הקהל של עדכון אירוע ---'
select t_eq('הסדרנים שומעים על האירוע',
  exists(select 1 from realtime.messages
    where topic = 'sync:staff' and payload ->> 'entity' = 'event'), true);
select t_eq('הלקוח שומע על האירוע שלו',
  exists(select 1 from realtime.messages
    where topic = 'sync:customer:10000000-0000-0000-0000-000000000020'
      and payload ->> 'entity' = 'event'), true);
select t_eq('והעובד המשובץ למשימת האירוע שומע גם הוא',
  exists(select 1 from realtime.messages
    where topic = 'sync:profile:20000000-0000-0000-0000-0000000020a1'
      and payload ->> 'entity' = 'event'), true);
select t_eq('אבל לא העובד שאינו משובץ',
  exists(select 1 from realtime.messages
    where topic = 'sync:profile:20000000-0000-0000-0000-0000000020a2'
      and payload ->> 'entity' = 'event'), false);

-- ===== 5. פוליסת הערוצים: מי רשאי להאזין למה ================================

-- מילוי מחדש, כדי שלצד המורשה יהיה מה לראות.
truncate realtime.messages;
update tasks set notes = 'שינוי לבדיקת הפוליסה'
 where id = '61000000-0000-0000-0000-000000020001';

\echo '--- העובד: הערוץ האישי שלו בלבד ---'
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000020a1', false);

do $$ begin perform set_config('realtime.topic', 'sync:profile:20000000-0000-0000-0000-0000000020a1', false); end $$;
select t_eq('הערוץ האישי שלו נפתח',
  exists(select 1 from realtime.messages), true);

do $$ begin perform set_config('realtime.topic', 'sync:profile:20000000-0000-0000-0000-0000000020a2', false); end $$;
select t_eq('הערוץ האישי של חברו — סגור',
  exists(select 1 from realtime.messages), false);

do $$ begin perform set_config('realtime.topic', 'sync:staff', false); end $$;
select t_eq('וערוץ הסדרנים — סגור: יש לו היקף own',
  exists(select 1 from realtime.messages), false);

do $$ begin perform set_config('realtime.topic', 'sync:customer:10000000-0000-0000-0000-000000000020', false); end $$;
select t_eq('וגם ערוץ הלקוח — סגור',
  exists(select 1 from realtime.messages), false);

reset role;
select set_config('request.jwt.claim.sub', '', false);

\echo '--- משתמש הלקוח: הערוץ של הלקוח שלו בלבד ---'
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000020a4', false);

do $$ begin perform set_config('realtime.topic', 'sync:customer:10000000-0000-0000-0000-000000000020', false); end $$;
select t_eq('ערוץ הלקוח שלו נפתח',
  exists(select 1 from realtime.messages), true);

do $$ begin perform set_config('realtime.topic', 'sync:staff', false); end $$;
select t_eq('וערוץ הסדרנים סגור בפניו',
  exists(select 1 from realtime.messages), false);

reset role;
select set_config('request.jwt.claim.sub', '', false);

\echo '--- סגל בהיקף לקוח: הלקוח כן, הכול לא ---'
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000020a6', false);

do $$ begin perform set_config('realtime.topic', 'sync:customer:10000000-0000-0000-0000-000000000020', false); end $$;
select t_eq('ערוץ הלקוח שבהיקפו נפתח',
  exists(select 1 from realtime.messages), true);

do $$ begin perform set_config('realtime.topic', 'sync:staff', false); end $$;
select t_eq('אבל ערוץ הסדרנים סגור: ההיקף שלו נקוב',
  exists(select 1 from realtime.messages), false);

reset role;
select set_config('request.jwt.claim.sub', '', false);

\echo '--- הסדרן והאדמין: ערוץ הסדרנים פתוח ---'
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000020a3', false);
do $$ begin perform set_config('realtime.topic', 'sync:staff', false); end $$;
select t_eq('הסדרן מאזין לערוץ הסדרנים',
  exists(select 1 from realtime.messages), true);
reset role;
select set_config('request.jwt.claim.sub', '', false);

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000020a5', false);
do $$ begin perform set_config('realtime.topic', 'sync:staff', false); end $$;
select t_eq('וגם האדמין',
  exists(select 1 from realtime.messages), true);
reset role;
select set_config('request.jwt.claim.sub', '', false);

do $$ begin perform set_config('realtime.topic', '', false); end $$;
