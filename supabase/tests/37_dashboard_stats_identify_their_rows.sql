\pset tuples_only on
\pset format unaligned

-- ===========================================================================
-- 37: האגרגטים של הדשבורד אומרים איזו שורה הם ספרו (0151).
--
-- החבילה מקימה לקוח, קבלן ו**שני עובדים בעלי אותו שם** ב-`current_date + 540`,
-- מעבר לכל טווח שחבילה אחרת נוגעת בו.
--
-- אותו שם אינו קוריוז אלא לב הבדיקה, והוא אפשרי: ל-`customers.name` יש
-- ‏`customers_name_uq`, אבל ל-`profiles.full_name`, ל-`contractors.name`
-- ול-`statuses.name` אין אילוץ ייחודיות כלל. עד 0151 קיבצו האגרגטים לפי שם,
-- ולכן שני עובדים ששמם זהה נספרו כשורה **אחת** שהמספר בה סכום של שניהם —
-- מספר סביר למראה שהוא פשוט לא נכון, ואי אפשר ללחוץ עליו ולהגיע לאיש.
--
-- מה שנבדק כאן ולא נבדק בשום מקום אחר:
--
--   * ששני עובדים בעלי אותו שם הם **שתי** שורות, ולכל אחת id הפרופיל שלה.
--   * ש-`by_customer`, ‏`by_status` ו-`by_contractor` נושאים id — כל אחד
--     מהם הוא היעד של לחיצה בצד הלקוח, ושם אינו כתובת.
--   * ש-`revenue.by_customer` נושא id, ושהסכום שלו לא זז מהשינוי. קיבוץ
--     לפי id במקום לפי שם משנה כמה שורות יש; אסור לו לשנות את הסכום.
--   * שהשדות הישנים לא נעלמו. לקוח שנשאר על גרסה קודמת קורא `name`,
--     ‏`color` ו-`cnt`, והמיגרציה מוסיפה מפתח ולא מחליפה אחד.
--
-- הזריעה רצה בלי JWT (auth.uid() = null) ולכן הטריגרים מדלגים; הקריאות
-- עצמן רצות כמנהל, כי `dashboard_stats` חותכת כל אגרגט לפי מפתח.
-- ===========================================================================

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000037a0', 'c37-admin@vl.test'),
  ('00000000-0000-0000-0000-0000000037a1', 'c37-worker-a@vl.test'),
  ('00000000-0000-0000-0000-0000000037a2', 'c37-worker-b@vl.test');

insert into customers (id, name) values
  ('10000000-0000-0000-0000-000000000371', 'לקוח 37');

insert into contractors (id, name) values
  ('11000000-0000-0000-0000-000000000371', 'קבלן 37');

insert into profiles (id, user_id, user_kind, is_admin, full_name) values
  ('20000000-0000-0000-0000-0000000037a0', '00000000-0000-0000-0000-0000000037a0',
   'staff', true, 'מנהל 37');

-- שני עובדים, שם אחד. אין `unique` על full_name, ולכן זה מצב חוקי לגמרי.
insert into profiles (id, user_id, user_kind, full_name) values
  ('20000000-0000-0000-0000-0000000037a1', '00000000-0000-0000-0000-0000000037a1',
   'staff', 'עובד כפול 37'),
  ('20000000-0000-0000-0000-0000000037a2', '00000000-0000-0000-0000-0000000037a2',
   'staff', 'עובד כפול 37');

insert into profile_roles (profile_id, role_id)
select p.pid, r.id from (values
  ('20000000-0000-0000-0000-0000000037a0'::uuid, 'admin'),
  ('20000000-0000-0000-0000-0000000037a1'::uuid, 'field_worker'),
  ('20000000-0000-0000-0000-0000000037a2'::uuid, 'field_worker')
) as p(pid, rkey) join permission_roles r on r.key = p.rkey;

insert into events (id, customer_id, event_date, end_client_name) values
  ('30000000-0000-0000-0000-000000000371', '10000000-0000-0000-0000-000000000371',
   current_date + 540, 'אירוע 37');

-- ‏`create_default_tasks` נולדת עם האירוע; המשימות כאן נכתבות ידנית כדי
-- שהספירה תהיה על מספר ידוע ולא על מה שהתבנית ייצרה.
delete from tasks where event_id = '30000000-0000-0000-0000-000000000371';

insert into tasks (id, event_id, customer_id, task_type_id, task_date, status_id)
select v.tid,
       '30000000-0000-0000-0000-000000000371',
       '10000000-0000-0000-0000-000000000371',
       (select id from task_types order by sort_order limit 1),
       current_date + 540,
       (select id from statuses where entity = 'task' order by sort_order limit 1)
  from (values
    ('40000000-0000-0000-0000-000000000371'::uuid),
    ('40000000-0000-0000-0000-000000000372'::uuid)
  ) as v(tid);

insert into task_pricing (task_id, price) values
  ('40000000-0000-0000-0000-000000000371', 100),
  ('40000000-0000-0000-0000-000000000372', 250);

insert into task_contractor_terms (task_id, contractor_id, price, work_site)
values ('40000000-0000-0000-0000-000000000371', '11000000-0000-0000-0000-000000000371', 40, 'field');

-- עובד אחד לכל משימה, ושניהם נקראים אותו דבר.
insert into task_assignments (task_id, profile_id, role, work_site) values
  ('40000000-0000-0000-0000-000000000371', '20000000-0000-0000-0000-0000000037a1', 'worker', 'field'),
  ('40000000-0000-0000-0000-000000000372', '20000000-0000-0000-0000-0000000037a2', 'worker', 'field');


\echo '--- שני עובדים בעלי אותו שם הם שתי שורות (0151) ---'

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000037a0', false);

-- שתי שורות ולא אחת. לפני 0151 זו הייתה שורה אחת עם cnt = 2.
select t_eq('by_worker מפריד שני עובדים ששמם זהה',
  (select count(*) from jsonb_array_elements(
     dashboard_stats(current_date + 540, current_date + 540) -> 'by_worker') e
    where e ->> 'name' = 'עובד כפול 37'),
  2::bigint);

select t_eq('ולכל אחת מהן id הפרופיל שלה',
  (select count(*) from jsonb_array_elements(
     dashboard_stats(current_date + 540, current_date + 540) -> 'by_worker') e
    where e ->> 'id' in ('20000000-0000-0000-0000-0000000037a1',
                         '20000000-0000-0000-0000-0000000037a2')),
  2::bigint);

select t_eq('וכל אחת סופרת את השיבוץ שלה בלבד',
  (select e ->> 'cnt' from jsonb_array_elements(
     dashboard_stats(current_date + 540, current_date + 540) -> 'by_worker') e
    where e ->> 'id' = '20000000-0000-0000-0000-0000000037a1'),
  '1');


\echo '--- כל יעד לחיצה נושא את ה-id שלו ---'

select t_eq('by_customer נושא id לקוח',
  (select e ->> 'id' from jsonb_array_elements(
     dashboard_stats(current_date + 540, current_date + 540) -> 'by_customer') e
    where e ->> 'name' = 'לקוח 37'),
  '10000000-0000-0000-0000-000000000371');

-- החוזה הישן: מפתח נוסף, לא מפתח שהוחלף.
select t_eq('והשדות שהיו לפני 0151 לא זזו',
  (select (e ? 'name') and (e ? 'color') and (e ? 'cnt') from jsonb_array_elements(
     dashboard_stats(current_date + 540, current_date + 540) -> 'by_customer') e
    where e ->> 'id' = '10000000-0000-0000-0000-000000000371'),
  true);

select t_eq('by_status נושא id סטטוס',
  (select bool_and(e ? 'id') from jsonb_array_elements(
     dashboard_stats(current_date + 540, current_date + 540) -> 'by_status') e),
  true);

select t_eq('by_contractor נושא id קבלן',
  (select e ->> 'id' from jsonb_array_elements(
     dashboard_stats(current_date + 540, current_date + 540) -> 'by_contractor') e
    where e ->> 'name' = 'קבלן 37'),
  '11000000-0000-0000-0000-000000000371');


\echo '--- הקיבוץ לפי id משנה כמה שורות, ולא כמה כסף ---'

select t_eq('revenue.by_customer נושא id',
  (select e ->> 'id' from jsonb_array_elements(
     dashboard_stats(current_date + 540, current_date + 540) #> '{revenue,by_customer}') e
    where e ->> 'name' = 'לקוח 37'),
  '10000000-0000-0000-0000-000000000371');

select t_eq('והסכום נשאר מה שהיה',
  (select (e ->> 'total')::numeric from jsonb_array_elements(
     dashboard_stats(current_date + 540, current_date + 540) #> '{revenue,by_customer}') e
    where e ->> 'name' = 'לקוח 37'),
  350::numeric);

select set_config('request.jwt.claim.sub', '', false);
