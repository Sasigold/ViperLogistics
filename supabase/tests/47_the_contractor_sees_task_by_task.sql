\pset tuples_only on
\pset format unaligned

-- ===========================================================================
-- 47: הקבלן רואה משימה־משימה, עם המחיר של כל אחת (0172).
--
-- שלוש שאלות: מה `contractor_tasks` מחזיר ולמי, מה קורה לקבלן שאין לו מפתח
-- כספי, והאם המונה של `contractor_dashboard` והרשימה סופרים אותו דבר.
--
-- החבילה מקימה לקוח, שני קבלנים, אירוע וארבע דמויות משלה ב-current_date + 640,
-- מעבר לכל טווח אחר. היא רצה אחרונה כי היא משאירה אחריה משימות ותמחור שאינם
-- מנוקים, ואחת ממשימותיה נמחקת רכות. הזריעה רצה בלי JWT, והטריגרים מדלגים.
-- ===========================================================================

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000047a0', 'c47-admin@vl.test'),
  ('00000000-0000-0000-0000-0000000047a1', 'c47-mgr@vl.test'),
  ('00000000-0000-0000-0000-0000000047a2', 'c47-nopricing@vl.test'),
  ('00000000-0000-0000-0000-0000000047a3', 'c47-nofin@vl.test'),
  ('00000000-0000-0000-0000-0000000047a4', 'c47-other@vl.test');

insert into customers (id, name) values
  ('10000000-0000-0000-0000-00000000047a', 'לקוח 47');
insert into contractors (id, name) values
  ('11000000-0000-0000-0000-00000000047a', 'קבלן 47 שלי'),
  ('11000000-0000-0000-0000-00000000047b', 'קבלן 47 אחר');

insert into profiles (id, user_id, user_kind, is_admin, full_name) values
  ('20000000-0000-0000-0000-0000000047a0', '00000000-0000-0000-0000-0000000047a0',
   'staff', true, 'מנהל 47');

insert into profiles (id, user_id, user_kind, full_name, contractor_id) values
  ('20000000-0000-0000-0000-0000000047a1', '00000000-0000-0000-0000-0000000047a1',
   'contractor_user', 'מנהל קבלן 47', '11000000-0000-0000-0000-00000000047a'),
  -- אותו קבלן בדיוק, בלי המפתח שפותח את שורת התמחור
  ('20000000-0000-0000-0000-0000000047a2', '00000000-0000-0000-0000-0000000047a2',
   'contractor_user', 'מנהל קבלן 47 בלי תמחור', '11000000-0000-0000-0000-00000000047a'),
  -- ואותו קבלן בלי המפתח הכספי של הפורטל
  ('20000000-0000-0000-0000-0000000047a3', '00000000-0000-0000-0000-0000000047a3',
   'contractor_user', 'מנהל קבלן 47 בלי כספים', '11000000-0000-0000-0000-00000000047a'),
  ('20000000-0000-0000-0000-0000000047a4', '00000000-0000-0000-0000-0000000047a4',
   'contractor_user', 'מנהל הקבלן האחר 47', '11000000-0000-0000-0000-00000000047b');

insert into profile_roles (profile_id, role_id)
select p.pid, r.id from (values
  ('20000000-0000-0000-0000-0000000047a1'::uuid, 'contractor_manager'),
  ('20000000-0000-0000-0000-0000000047a2'::uuid, 'contractor_manager'),
  ('20000000-0000-0000-0000-0000000047a3'::uuid, 'contractor_manager'),
  ('20000000-0000-0000-0000-0000000047a4'::uuid, 'contractor_manager')
) as p(pid, rkey) join permission_roles r on r.key = p.rkey;

-- החריגות האישיות: כל אחת מכבה מפתח אחד, ורק אותו.
insert into user_permission_grants (profile_id, permission_key, allowed) values
  ('20000000-0000-0000-0000-0000000047a2', 'contractors.view_pricing', false),
  ('20000000-0000-0000-0000-0000000047a3', 'portal.view_financials',   false);

-- האירוע נולד עם הקמה ופירוק (auto_create_on_event), שתיהן ביום האירוע.
insert into events (id, customer_id, event_number, event_date, end_client_name, location_text, status_id)
values ('30000000-0000-0000-0000-00000000047a', '10000000-0000-0000-0000-00000000047a',
        'EV-47', current_date + 640, 'אולם 47', 'הרצל 1, תל אביב',
        (select id from statuses where entity = 'event' and code = 'planned' and deleted_at is null));

-- ושלוש משימות מפורשות: אחת יום אחרי, אחת יום לפני, ואחת שתימחק רכות.
insert into tasks (id, event_id, customer_id, task_type_id, task_date, worker_count, location_text, status_id)
select x.id, '30000000-0000-0000-0000-00000000047a', '10000000-0000-0000-0000-00000000047a',
       (select id from task_types where name = 'סידור' limit 1), x.d, 2, x.loc,
       (select id from statuses where entity = 'task' and code = 'draft' and deleted_at is null)
from (values
  ('61000000-0000-0000-0000-000000047001'::uuid, (current_date + 641)::date, 'ביאליק 9, רמת גן'),
  ('61000000-0000-0000-0000-000000047002'::uuid, (current_date + 639)::date, null),
  ('61000000-0000-0000-0000-000000047003'::uuid, (current_date + 640)::date, null)
) as x(id, d, loc);

-- ההאצלה: שלוש משימות לקבלן שלי, אחת לאחר, ואחת שנמחקת.
insert into task_contractor_terms (task_id, contractor_id, price, work_site)
select t.id, '11000000-0000-0000-0000-00000000047a', 1000, 'field'
  from tasks t
 where t.event_id = '30000000-0000-0000-0000-00000000047a'
   and t.task_type_id = (select id from task_types where code = 'setup' limit 1);
insert into task_contractor_terms (task_id, contractor_id, price, work_site)
select t.id, '11000000-0000-0000-0000-00000000047a', 500, 'field'
  from tasks t
 where t.event_id = '30000000-0000-0000-0000-00000000047a'
   and t.task_type_id = (select id from task_types where code = 'teardown' limit 1);
insert into task_contractor_terms (task_id, contractor_id, price, work_site) values
  ('61000000-0000-0000-0000-000000047001', '11000000-0000-0000-0000-00000000047a', 250, 'field'),
  -- המשימה של הקבלן האחר, ובאותו אירוע: אם הרשימה סוננה לפי אירוע ולא לפי
  -- שורת ההאצלה, היא תופיע כאן.
  ('61000000-0000-0000-0000-000000047002', '11000000-0000-0000-0000-00000000047b', 700, 'field'),
  ('61000000-0000-0000-0000-000000047003', '11000000-0000-0000-0000-00000000047a', 999, 'field');

-- ההקמה שולמה, ובסכום אחר מהצפוי — זה ההפרש שהקבלן בא לחפש.
update task_contractor_terms
   set paid_at = now(), paid_amount = 900
 where contractor_id = '11000000-0000-0000-0000-00000000047a'
   and task_id in (select t.id from tasks t
                    where t.event_id = '30000000-0000-0000-0000-00000000047a'
                      and t.task_type_id = (select id from task_types where code = 'setup' limit 1));

-- ומשימה שנמחקה רכות אינה משימה שביצעתי.
update tasks set deleted_at = now() where id = '61000000-0000-0000-0000-000000047003';

\echo '--- 1. הקבלן מקבל את המשימות שלו, ורק אותן ---'
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000047a1', false);

select t_eq('שלוש משימות: שתיים של האירוע ואחת נוספת',
  (select count(*)::int from contractor_tasks(null, null)), 3);
select t_eq('המשימה של הקבלן האחר אינה ברשימה',
  (select count(*)::int from contractor_tasks(null, null)
    where task_id = '61000000-0000-0000-0000-000000047002'), 0);
select t_eq('ומשימה שנמחקה רכות אינה ברשימה',
  (select count(*)::int from contractor_tasks(null, null)
    where task_id = '61000000-0000-0000-0000-000000047003'), 0);
select t_eq('סך המחירים הוא של השורות שלו בלבד',
  (select sum(price) from contractor_tasks(null, null)), 1750::numeric);
select t_eq('היום האחרון ראשון',
  (select task_id from contractor_tasks(null, null) limit 1),
  '61000000-0000-0000-0000-000000047001'::uuid);

\echo '--- 2. מה שהשורה נושאת: מחיר, תשלום, אירוע ומיקום ---'
select t_eq('ההקמה נושאת את המחיר שלה',
  (select price from contractor_tasks(null, null)
    where task_type_name = 'הקמה'), 1000::numeric);
select t_eq('והסכום ששולם בפועל נפרד ממנו',
  (select paid_amount from contractor_tasks(null, null)
    where task_type_name = 'הקמה'), 900::numeric);
select t_eq('הפירוק ממתין לתשלום',
  (select paid_at is null from contractor_tasks(null, null)
    where task_type_name = 'פירוק'), true);
select t_eq('שם הלקוח מגיע לקבלן',
  (select distinct customer_name from contractor_tasks(null, null)), 'לקוח 47');
select t_eq('וגם הלקוח הסופי',
  (select distinct end_client_name from contractor_tasks(null, null)), 'אולם 47');
select t_eq('מיקום המשימה גובר על זה של האירוע',
  (select location_text from contractor_tasks(null, null)
    where task_id = '61000000-0000-0000-0000-000000047001'), 'ביאליק 9, רמת גן');
select t_eq('ובהיעדרו נלקח המיקום של האירוע',
  (select location_text from contractor_tasks(null, null)
    where task_type_name = 'הקמה'), 'הרצל 1, תל אביב');
select t_eq('תאריך האירוע נושא את השורה גם כשהמשימה ביום אחר',
  (select event_date from contractor_tasks(null, null)
    where task_id = '61000000-0000-0000-0000-000000047001'), (current_date + 640)::date);

\echo '--- 3. הטווח והתקרה ---'
select t_eq('טווח מסנן — יום אחד בלבד',
  (select count(*)::int from contractor_tasks((current_date + 641)::date, null)), 1);
select t_eq('וקצה שני סוגר את הרשימה',
  (select count(*)::int from contractor_tasks(null, (current_date + 639)::date)), 0);
select t_eq('התקרה חותכת, והחדשה נשארת',
  (select array_agg(task_id)::text from contractor_tasks(null, null, 1)),
  '{61000000-0000-0000-0000-000000047001}');

\echo '--- 4. המונה של הכרטיס והרשימה סופרים אותו דבר ---'
select t_eq('המונה שווה למספר השורות',
  (contractor_dashboard(null, null) ->> 'tasks_count')::int,
  (select count(*)::int from contractor_tasks(null, null)));
select t_eq('והסכום הצפוי שווה לסכום העמודה',
  (contractor_dashboard(null, null) ->> 'expected_total')::numeric,
  (select sum(price) from contractor_tasks(null, null)));
select t_eq('מה ששולם הוא הסכום שנרשם ולא המחיר',
  (contractor_dashboard(null, null) ->> 'paid_total')::numeric, 900::numeric);
select t_eq('והיתרה היא של מה שלא שולם',
  (contractor_dashboard(null, null) ->> 'unpaid_total')::numeric, 750::numeric);
reset role;
select set_config('request.jwt.claim.sub', '', false);

\echo '--- 5. קבלן בלי מפתח תמחור: השורות נשארות, המחיר יורד (0172) ---'
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000047a2', false);
select t_eq('המפתח אכן כבוי', app.has('contractors.view_pricing'), false);
select t_eq('ושורת התמחור באמת סגורה בפניו',
  (select count(*)::int from task_contractor_terms
    where contractor_id = '11000000-0000-0000-0000-00000000047a'), 0);
select t_eq('ובכל זאת הוא רואה את שלוש המשימות שביצע',
  (select count(*)::int from contractor_tasks(null, null)), 3);
select t_eq('בלי מחיר על אף אחת מהן',
  (select count(price)::int from contractor_tasks(null, null)), 0);
select t_eq('וגם המונה אינו אומר לו שלא עבד',
  (contractor_dashboard(null, null) ->> 'tasks_count')::int, 3);
reset role;
select set_config('request.jwt.claim.sub', '', false);

\echo '--- 6. קבלן בלי המפתח הכספי של הפורטל ---'
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000047a3', false);
select t_eq('שלוש המשימות שלו נשארות',
  (select count(*)::int from contractor_tasks(null, null)), 3);
select t_eq('אבל שדות הכסף ריקים',
  (select count(price)::int + count(paid_at)::int + count(paid_amount)::int
     from contractor_tasks(null, null)), 0);
select t_eq('והכרטיס אינו נוקב בסכום',
  (contractor_dashboard(null, null) -> 'expected_total') = 'null'::jsonb, true);
reset role;
select set_config('request.jwt.claim.sub', '', false);

\echo '--- 7. הקבלן האחר, והמשרד ---'
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000047a4', false);
select t_eq('הקבלן האחר רואה את שורתו האחת',
  (select count(*)::int from contractor_tasks(null, null)), 1);
select t_eq('ואת המחיר שלו, לא של השכן',
  (select sum(price) from contractor_tasks(null, null)), 700::numeric);
reset role;
select set_config('request.jwt.claim.sub', '', false);

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000047a0', false);
select t_eq('מנהל מערכת אינו קבלן, ולכן הרשימה שלו ריקה',
  (select count(*)::int from contractor_tasks(null, null)), 0);
reset role;
select set_config('request.jwt.claim.sub', '', false);

\echo '--- 8. ה-ACL של הפונקציה ---'
select t_eq('anon אינו רשאי להריץ',
  has_function_privilege('anon', 'public.contractor_tasks(date,date,int)', 'EXECUTE'), false);
select t_eq('ו-authenticated כן',
  has_function_privilege('authenticated', 'public.contractor_tasks(date,date,int)', 'EXECUTE'), true);
