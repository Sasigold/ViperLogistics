\pset tuples_only on
\pset format unaligned

-- ===========================================================================
-- ‏58: הקיר נותן שם לכל צוות — `crew_names` בכל משימה בפיד (0203).
--
-- החבילה מקימה שני לקוחות (ואחד מהם של ארקו), קבלן, שלושה אירועים, ארבע-עשרה
-- משימות, ארבעה עובדי קבלן, ארבעה עובדי לקוח ושישים ואחד אנשי צוות משלה
-- ב-`current_date + 900`, מעבר לכל טווח אחר. 57 יושבת ביולי ארבע שנים קדימה,
-- ושאר החבילות עד +870. "עכשיו" ננעץ ל-10:00 של אותו יום בישראל, ו-
-- `app.wall_snapshot_at` נקראת איתו — השעון אינו משחק (חוץ מבדיקת הדלת, §5).
-- ההחתמות אינן חלק מהתרחיש.
--
-- היום D, המשימות (שמות האנשים מסודרים כך שראש הצוות אינו הראשון באלף-בית —
-- אחרת "ראש הצוות ראשון" ו-"לפי האלף-בית" לא היו נבדלים):
--   K1  שלושת המאגרים; ראש הצוות הוא עובד הקבלן. אורי הוא עובד וגם נהג.
--   K2  ראש צוות פנימי (תמר, אחרונה באלף-בית), ועוד עובד קבלן ועובד לקוח.
--   K3  ראש צוות של הלקוח (חגי), ועוד אורי ועובד לקוח.
--   K4  אין איש — `[]`, לא null.
--   K5  מואצלת לקבלן: שני עובדי קבלן, בלי ראש צוות.
--   K6  עובדי לקוח בלבד, בלי ראש צוות.
--   K7  ראשי צוות בשלושת המאגרים — הפנימי הוא שנבחר, כמו ב-`team_lead_name`.
--   K8  שחר הוא ראש צוות, עובד וגם נהג (שלוש שורות, אדם אחד), ושני אנשים שונים
--       בשם אחד: שניהם בצוות.
--   K9  מוסתרת מהלו״ז   — לא ברשימה, והשמות שלה לא בפיד.
--   K10 נמחקה            — לא ברשימה.
--   K11 באירוע שבוטל     — לא ברשימה.
--   K12 של ארקו          — לא ברשימה.
--   K13 ב-D+2: 45 אנשים, האחרון הוא ראש הצוות — התקרה של 40.
--   K14 ב-D+3: אנשים בלי שם (ריק, רווחים, טאב) — מדלגים עליהם.
-- היא משאירה אחריה את כל זה.
-- ===========================================================================

-- היום: +900. חצות ו-DST אינם חלק מהבדיקה הזו, וההמרות הן דרך אזור ישראל.
create or replace function t58_day() returns date language sql stable as $$
  select current_date + 900
$$;

-- שעה בישראל ביום D + p_offset
create or replace function t58_at(p_offset int, p_time time) returns timestamptz
language sql stable as $$
  select ((t58_day() + p_offset) + p_time) at time zone 'Asia/Jerusalem'
$$;

-- מה ש-SQLSTATE אמר — 'ok' כשלא נזרק דבר. רץ בזהות הקורא.
create or replace function t58_state(p_sql text) returns text language plpgsql as $$
begin
  execute p_sql;
  return 'ok';
exception when others then
  return sqlstate;
end $$;

insert into customers (id, name, color) values
  ('10000000-0000-0000-0000-00000000058a', 'לקוח 58', '#0e7490');
insert into customers (id, name, performed_by_enabled) values
  ('10000000-0000-0000-0000-00000000058b', 'ארקו 58', true);

insert into contractors (id, name) values
  ('40000000-0000-0000-0000-00000000058a', 'קבלן 58');

-- הטלפון והת״ז כאן כדי שהבדיקה תוכל לוודא שהם לא יוצאים
insert into contractor_workers (id, contractor_id, full_name, phone, id_number) values
  ('50000000-0000-0000-0000-0000000058a1', '40000000-0000-0000-0000-00000000058a', 'הילה 58',  '050-5800011', '58-ID-0011'),
  ('50000000-0000-0000-0000-0000000058a2', '40000000-0000-0000-0000-00000000058a', 'ורד 58',   '050-5800012', '58-ID-0012'),
  ('50000000-0000-0000-0000-0000000058a3', '40000000-0000-0000-0000-00000000058a', 'זיו 58',   '050-5800013', '58-ID-0013'),
  ('50000000-0000-0000-0000-0000000058a4', '40000000-0000-0000-0000-00000000058a', E'\t',      '050-5800014', '58-ID-0014');

insert into customer_workers (id, customer_id, full_name, phone, id_number) values
  ('cf000000-0000-0000-0000-0000005800a1', '10000000-0000-0000-0000-00000000058a', 'חגי 58', '050-5800021', '58-ID-0021'),
  ('cf000000-0000-0000-0000-0000005800a2', '10000000-0000-0000-0000-00000000058a', 'טל 58',  '050-5800022', '58-ID-0022'),
  ('cf000000-0000-0000-0000-0000005800a3', '10000000-0000-0000-0000-00000000058a', 'יעל 58', '050-5800023', '58-ID-0023'),
  ('cf000000-0000-0000-0000-0000005800a4', '10000000-0000-0000-0000-00000000058a', '  ',     '050-5800024', '58-ID-0024');

insert into profiles (id, user_kind, is_admin, full_name, phone) values
  ('20000000-0000-0000-0000-0000000058a1', 'staff', false, 'אורי 58',  '050-5800001'),
  ('20000000-0000-0000-0000-0000000058a2', 'staff', false, 'בועז 58',  null),
  ('20000000-0000-0000-0000-0000000058a3', 'staff', false, 'גלית 58',  null),
  ('20000000-0000-0000-0000-0000000058a4', 'staff', false, 'דנה 58',   null),
  ('20000000-0000-0000-0000-0000000058a5', 'staff', false, 'תמר 58',   null),
  ('20000000-0000-0000-0000-0000000058a6', 'staff', false, 'פנינה 58', null),
  ('20000000-0000-0000-0000-0000000058a7', 'staff', false, 'כפיל 58',  null),
  ('20000000-0000-0000-0000-0000000058a8', 'staff', false, 'כפיל 58',  null),
  ('20000000-0000-0000-0000-0000000058a9', 'staff', false, 'שחר 58',   null),
  -- צוות של המשימות שאינן ברשימה, בשמות שאין להם מקום אחר
  ('20000000-0000-0000-0000-0000000058c1', 'staff', false, 'צוות מוסתר 58', null),
  ('20000000-0000-0000-0000-0000000058c2', 'staff', false, 'צוות נמחק 58',  null),
  ('20000000-0000-0000-0000-0000000058c3', 'staff', false, 'צוות מבוטל 58', null),
  ('20000000-0000-0000-0000-0000000058c4', 'staff', false, 'צוות ארקו 58',  null),
  -- K14: אחד עם שם, ושניים בלי (רווחים, ומחרוזת ריקה)
  ('20000000-0000-0000-0000-0000000058b1', 'staff', false, 'רונית 58', null),
  ('20000000-0000-0000-0000-0000000058b2', 'staff', false, '   ',      null),
  ('20000000-0000-0000-0000-0000000058b3', 'staff', false, '',         null);

-- K13: ארבעים וחמישה, 'מקס 58 01' .. 'מקס 58 45' — מספר באורך קבוע, כדי שהסדר
-- יהיה אותו סדר בכל collation
insert into profiles (id, user_kind, is_admin, full_name)
select ('20000000-0000-0000-0000-' || lpad('58' || lpad(i::text, 2, '0'), 12, '0'))::uuid,
       'staff', false, 'מקס 58 ' || lpad(i::text, 2, '0')
  from generate_series(1, 45) i;

-- שכר לאורי: המספר הזה אסור שיופיע במשימות
insert into worker_pay_settings (profile_id, hourly_rate) values
  ('20000000-0000-0000-0000-0000000058a1', 123.45);

insert into events (id, customer_id, event_number, end_client_name, location_text, event_date, status_id)
select v.id::uuid, v.cust::uuid, v.num, v.client, v.loc, t58_day(),
       (select id from statuses where entity = 'event' and code = 'pending' and deleted_at is null)
  from (values
    ('30000000-0000-0000-0000-00000000058a', '10000000-0000-0000-0000-00000000058a', 'EV-58',   'חתונה 58', 'גני 58'),
    ('30000000-0000-0000-0000-00000000058b', '10000000-0000-0000-0000-00000000058a', 'EV-58-X', 'בוטל 58',  'אולם 58'),
    ('30000000-0000-0000-0000-00000000058c', '10000000-0000-0000-0000-00000000058b', 'EV-58-A', 'ארקו 58',  'אולם ארקו 58')) v(id, cust, num, client, loc);

-- ההקמה והפירוק שנולדים עם כל אירוע (0003) אינם חלק מהתרחיש
update tasks set deleted_at = now()
 where event_id in ('30000000-0000-0000-0000-00000000058a', '30000000-0000-0000-0000-00000000058b',
                    '30000000-0000-0000-0000-00000000058c');

insert into tasks (id, event_id, customer_id, task_type_id, task_date, title,
                   warehouse_start_time, onsite_start_time, hours_count, status_id,
                   worker_count, hidden_on_board, performed_by)
select v.id::uuid, v.ev::uuid, v.cust::uuid,
       (select id from task_types where code = v.type limit 1),
       t58_day() + v.off, v.title, null, v.onsite::time, 2.0,
       (select id from statuses where entity = 'task' and code = 'assigned' and deleted_at is null),
       v.need, v.hidden, v.perf
  from (values
    ('62000000-0000-0000-0000-000000058001', '30000000-0000-0000-0000-00000000058a', '10000000-0000-0000-0000-00000000058a',
     'setup',    0, 'שלושה מאגרים 58',   '09:00',  5, false, 'viper'),
    ('62000000-0000-0000-0000-000000058002', '30000000-0000-0000-0000-00000000058a', '10000000-0000-0000-0000-00000000058a',
     'teardown', 0, 'ראש צוות פנימי 58', '09:30',  5, false, 'viper'),
    ('62000000-0000-0000-0000-000000058003', '30000000-0000-0000-0000-00000000058a', '10000000-0000-0000-0000-00000000058a',
     'setup',    0, 'ראש צוות לקוח 58',  '10:00',  3, false, 'viper'),
    ('62000000-0000-0000-0000-000000058004', '30000000-0000-0000-0000-00000000058a', '10000000-0000-0000-0000-00000000058a',
     'teardown', 0, 'בלי צוות 58',       '11:00',  2, false, 'viper'),
    ('62000000-0000-0000-0000-000000058005', '30000000-0000-0000-0000-00000000058a', '10000000-0000-0000-0000-00000000058a',
     'setup',    0, 'מואצלת 58',         '11:30',  2, false, 'viper'),
    ('62000000-0000-0000-0000-000000058006', '30000000-0000-0000-0000-00000000058a', '10000000-0000-0000-0000-00000000058a',
     'teardown', 0, 'עובדי לקוח 58',     '12:00',  3, false, 'viper'),
    ('62000000-0000-0000-0000-000000058007', '30000000-0000-0000-0000-00000000058a', '10000000-0000-0000-0000-00000000058a',
     'setup',    0, 'שלושה ראשי צוות 58', '12:30', 4, false, 'viper'),
    ('62000000-0000-0000-0000-000000058008', '30000000-0000-0000-0000-00000000058a', '10000000-0000-0000-0000-00000000058a',
     'teardown', 0, 'אדם פעם אחת 58',    '13:00',  3, false, 'viper'),
    -- מוסתרת: 15:00, כדי שאיש מצוותה לא ייראה "מאחר" ב-10:00
    ('62000000-0000-0000-0000-000000058009', '30000000-0000-0000-0000-00000000058a', '10000000-0000-0000-0000-00000000058a',
     'setup',    0, 'מוסתרת 58',         '15:00',  2, true,  'viper'),
    ('62000000-0000-0000-0000-000000058010', '30000000-0000-0000-0000-00000000058a', '10000000-0000-0000-0000-00000000058a',
     'setup',    0, 'נמחקה 58',          '14:00',  2, false, 'viper'),
    ('62000000-0000-0000-0000-000000058011', '30000000-0000-0000-0000-00000000058b', '10000000-0000-0000-0000-00000000058a',
     'setup',    0, 'אירוע שבוטל 58',    '14:30',  2, false, 'viper'),
    ('62000000-0000-0000-0000-000000058012', '30000000-0000-0000-0000-00000000058c', '10000000-0000-0000-0000-00000000058b',
     'setup',    0, 'של ארקו 58',        '16:00',  2, false, 'arko'),
    ('62000000-0000-0000-0000-000000058013', '30000000-0000-0000-0000-00000000058a', '10000000-0000-0000-0000-00000000058a',
     'setup',    2, 'תקרה 58',           '08:00', 45, false, 'viper'),
    ('62000000-0000-0000-0000-000000058014', '30000000-0000-0000-0000-00000000058a', '10000000-0000-0000-0000-00000000058a',
     'setup',    3, 'בלי שם 58',         '08:00',  6, false, 'viper')
  ) v(id, ev, cust, type, off, title, onsite, need, hidden, perf);

-- הצוות של K11 נכנס אחרי שהאירוע בוטל: ביטול משחרר צוות (0200), ואנחנו רוצים
-- משימה שבאירוע מבוטל ובכל זאת יש בה שמות.
update events set status_id = (select id from statuses where entity = 'event' and code = 'cancelled'
                                                          and deleted_at is null)
 where id = '30000000-0000-0000-0000-00000000058b';

-- K1: אורי עובד מהמחסן וגם הנהג — שתי שורות, אדם אחד
insert into task_assignments (task_id, profile_id, role, work_site) values
  ('62000000-0000-0000-0000-000000058001', '20000000-0000-0000-0000-0000000058a1', 'worker',    'warehouse'),
  ('62000000-0000-0000-0000-000000058001', '20000000-0000-0000-0000-0000000058a1', 'driver',    'field'),
  ('62000000-0000-0000-0000-000000058001', '20000000-0000-0000-0000-0000000058a2', 'worker',    'field'),
  -- K2
  ('62000000-0000-0000-0000-000000058002', '20000000-0000-0000-0000-0000000058a5', 'team_lead', 'field'),
  ('62000000-0000-0000-0000-000000058002', '20000000-0000-0000-0000-0000000058a3', 'worker',    'field'),
  ('62000000-0000-0000-0000-000000058002', '20000000-0000-0000-0000-0000000058a4', 'worker',    'field'),
  -- K3
  ('62000000-0000-0000-0000-000000058003', '20000000-0000-0000-0000-0000000058a1', 'worker',    'field'),
  -- K7
  ('62000000-0000-0000-0000-000000058007', '20000000-0000-0000-0000-0000000058a6', 'team_lead', 'field'),
  ('62000000-0000-0000-0000-000000058007', '20000000-0000-0000-0000-0000000058a2', 'worker',    'field'),
  -- K8: שחר ראש צוות, עובד וגם נהג; ושני "כפיל" שהם שני אנשים
  ('62000000-0000-0000-0000-000000058008', '20000000-0000-0000-0000-0000000058a9', 'team_lead', 'field'),
  ('62000000-0000-0000-0000-000000058008', '20000000-0000-0000-0000-0000000058a9', 'worker',    'field'),
  ('62000000-0000-0000-0000-000000058008', '20000000-0000-0000-0000-0000000058a9', 'driver',    'field'),
  ('62000000-0000-0000-0000-000000058008', '20000000-0000-0000-0000-0000000058a7', 'worker',    'field'),
  ('62000000-0000-0000-0000-000000058008', '20000000-0000-0000-0000-0000000058a8', 'worker',    'field'),
  -- K14
  ('62000000-0000-0000-0000-000000058014', '20000000-0000-0000-0000-0000000058b1', 'worker',    'field'),
  ('62000000-0000-0000-0000-000000058014', '20000000-0000-0000-0000-0000000058b2', 'team_lead', 'field'),
  ('62000000-0000-0000-0000-000000058014', '20000000-0000-0000-0000-0000000058b3', 'worker',    'field');

-- K13: 45 אנשים, והאחרון הוא ראש הצוות
insert into task_assignments (task_id, profile_id, role, work_site)
select '62000000-0000-0000-0000-000000058013',
       ('20000000-0000-0000-0000-' || lpad('58' || lpad(i::text, 2, '0'), 12, '0'))::uuid,
       case when i = 45 then 'team_lead' else 'worker' end::assignment_role, 'field'
  from generate_series(1, 45) i;

insert into task_contractor_terms (task_id, contractor_id, price) values
  ('62000000-0000-0000-0000-000000058001', '40000000-0000-0000-0000-00000000058a', 500),
  ('62000000-0000-0000-0000-000000058005', '40000000-0000-0000-0000-00000000058a', 300);

insert into task_contractor_workers (task_id, contractor_worker_id, role, work_site) values
  ('62000000-0000-0000-0000-000000058001', '50000000-0000-0000-0000-0000000058a1', 'team_lead', 'field'),
  ('62000000-0000-0000-0000-000000058001', '50000000-0000-0000-0000-0000000058a2', null,        'field'),
  ('62000000-0000-0000-0000-000000058002', '50000000-0000-0000-0000-0000000058a3', null,        'field'),
  ('62000000-0000-0000-0000-000000058005', '50000000-0000-0000-0000-0000000058a2', null,        'field'),
  ('62000000-0000-0000-0000-000000058005', '50000000-0000-0000-0000-0000000058a3', null,        'field'),
  ('62000000-0000-0000-0000-000000058007', '50000000-0000-0000-0000-0000000058a1', 'team_lead', 'field'),
  ('62000000-0000-0000-0000-000000058014', '50000000-0000-0000-0000-0000000058a3', null,        'field'),
  ('62000000-0000-0000-0000-000000058014', '50000000-0000-0000-0000-0000000058a4', null,        'field');

insert into task_customer_workers (task_id, customer_worker_id, role, work_site) values
  ('62000000-0000-0000-0000-000000058001', 'cf000000-0000-0000-0000-0000005800a2', null,        'field'),
  ('62000000-0000-0000-0000-000000058002', 'cf000000-0000-0000-0000-0000005800a3', null,        'field'),
  ('62000000-0000-0000-0000-000000058003', 'cf000000-0000-0000-0000-0000005800a1', 'team_lead', 'field'),
  ('62000000-0000-0000-0000-000000058003', 'cf000000-0000-0000-0000-0000005800a2', null,        'field'),
  ('62000000-0000-0000-0000-000000058006', 'cf000000-0000-0000-0000-0000005800a3', null,        'field'),
  ('62000000-0000-0000-0000-000000058006', 'cf000000-0000-0000-0000-0000005800a2', null,        'field'),
  ('62000000-0000-0000-0000-000000058006', 'cf000000-0000-0000-0000-0000005800a1', null,        'field'),
  ('62000000-0000-0000-0000-000000058007', 'cf000000-0000-0000-0000-0000005800a1', 'team_lead', 'field'),
  ('62000000-0000-0000-0000-000000058014', 'cf000000-0000-0000-0000-0000005800a4', null,        'field');

-- המשימות שאינן ברשימה: מוסתרת, נמחקה, באירוע שבוטל, של ארקו — לכל אחת צוות
insert into task_assignments (task_id, profile_id, role, work_site) values
  ('62000000-0000-0000-0000-000000058009', '20000000-0000-0000-0000-0000000058c1', 'worker', 'field'),
  ('62000000-0000-0000-0000-000000058010', '20000000-0000-0000-0000-0000000058c2', 'worker', 'field'),
  ('62000000-0000-0000-0000-000000058011', '20000000-0000-0000-0000-0000000058c3', 'worker', 'field'),
  ('62000000-0000-0000-0000-000000058012', '20000000-0000-0000-0000-0000000058c4', 'worker', 'field');
insert into task_contractor_workers (task_id, contractor_worker_id, role, work_site) values
  ('62000000-0000-0000-0000-000000058009', '50000000-0000-0000-0000-0000000058a2', null, 'field');

update tasks set deleted_at = now() where id = '62000000-0000-0000-0000-000000058010';

-- ===== 0. ההרשאות כפי שהמיגרציה השאירה אותן (לפני הזריעה) ====================

\echo '--- ההרשאות: העוזר נשלל מכולם, והדלת נשארת ל-service_role ---'

select t_eq('העוזר app.wall_task_crew נמצא בתמונה, פעם אחת',
  (select count(*)::int from t_pre_seed.function_acl
    where schema = 'app' and name = 'wall_task_crew' and args = 'p_task_id uuid'), 1);

select t_eq('anon, authenticated ו-service_role אינם מריצים אותו',
  (select count(*)::int from t_pre_seed.function_acl
    where schema = 'app' and name = 'wall_task_crew'
      and (anon or authenticated or service_role)), 0);

select t_eq('וגם את app.wall_snapshot_at, אחרי שנאמרה שוב',
  (select count(*)::int from t_pre_seed.function_acl
    where schema = 'app' and name = 'wall_snapshot_at'
      and (anon or authenticated or service_role)), 0);

select t_eq('הדלת public.wall_snapshot נשארת ל-service_role, ורק לו',
  (select concat_ws('/', service_role::text, anon::text, authenticated::text) from t_pre_seed.function_acl
    where schema = 'public' and name = 'wall_snapshot'), 'true/false/false');

select t_eq('ו-service_role אינו מריץ אף פונקציית wall אחרת — אף אחת מהן',
  (select string_agg(schema || '.' || name, ',' order by schema, name) from t_pre_seed.function_acl
    where name like 'wall\_%' and service_role), 'public.wall_snapshot');

select t_eq('וההרשאה החיה זהה: service_role אינו מריץ את העוזר',
  has_function_privilege('service_role', 'app.wall_task_crew(uuid)', 'execute'), false);

\echo '--- אותו דבר בזמן ריצה: anon ו-service_role נדחים ---'
set role anon;
select t_eq('anon אינו מריץ את העוזר',
  t58_state($$select app.wall_task_crew('62000000-0000-0000-0000-000000058001')$$), '42501');
reset role;
set role service_role;
select t_eq('service_role אינו מריץ את העוזר',
  t58_state($$select app.wall_task_crew('62000000-0000-0000-0000-000000058001')$$), '42501');
select t_eq('ואינו עוקף את הדלת אל התמונה',
  t58_state($$select app.wall_snapshot_at(now(), 3)$$), '42501');
reset role;

-- ===== 1. תנאי הפתיחה: שהמשימות שאינן ברשימה אכן נושאות צוות =================

\echo '--- תנאי פתיחה ---'
select t_eq('לכל ארבע המשימות שאינן ברשימה יש שיבוץ אמיתי',
  (select count(distinct task_id)::int from (
     select task_id from task_assignments
      where task_id in ('62000000-0000-0000-0000-000000058009', '62000000-0000-0000-0000-000000058010',
                        '62000000-0000-0000-0000-000000058011', '62000000-0000-0000-0000-000000058012')) x), 4);

select t_eq('K11 באירוע שבוטל, והצוות שבו שורד את הביטול',
  (select s.code || '/' || (select count(*) from task_assignments a where a.task_id = t.id)
     from tasks t join events e on e.id = t.event_id join statuses s on s.id = e.status_id
    where t.id = '62000000-0000-0000-0000-000000058011'), 'cancelled/1');

select t_eq('K9 מוסתרת, K10 נמחקה, K12 של ארקו',
  (select string_agg(right(id::text, 3) || ':' || (deleted_at is not null)::text || '/' || hidden_on_board::text
                     || '/' || performed_by::text, ',' order by id)
     from tasks where id in ('62000000-0000-0000-0000-000000058009', '62000000-0000-0000-0000-000000058010',
                             '62000000-0000-0000-0000-000000058012')),
  '009:false/true/viper,010:true/false/viper,012:false/false/arko');

-- ===== 2. התמונה של D, ב-10:00 =================================================

\echo '--- המשימות, ב-10:00 של D, ברשימה של יום אחד ---'
create temp table s58 as select app.wall_snapshot_at(t58_at(0, '10:00'), 1) as j;

select t_eq('היום הוא D, והרשימה של יום אחד',
  (select (j ->> 'today')::date = t58_day() and (j ->> 'days')::int = 1 from s58), true);

create temp table k58 as
select right(t ->> 'id', 3) as k, t
  from s58, jsonb_array_elements(j -> 'tasks') t
 where t ->> 'id' like '62000000-0000-0000-0000-000000058%';

select t_eq('ברשימה שמונה משימות: K1..K8 — לא המוסתרת, לא שנמחקה, לא של האירוע המבוטל, לא של ארקו',
  (select string_agg(k, ',' order by k) from k58), '001,002,003,004,005,006,007,008');

\echo '--- שמות הצוות מכל שלושת המאגרים ---'
select t_eq('K1: ראש הצוות של הקבלן ראשון, ואחריו כולם לפי האלף-בית (פנימי, פנימי, קבלן, לקוח)',
  (select t -> 'crew_names' from k58 where k = '001'),
  '["הילה 58", "אורי 58", "בועז 58", "ורד 58", "טל 58"]'::jsonb);
select t_eq('K1: חמישה אנשים — אורי עובד וגם נהג, והוא פעם אחת',
  (select (t ->> 'assigned') || '/' || jsonb_array_length(t -> 'crew_names') from k58 where k = '001'), '5/5');
select t_eq('K1: שם הראש הוא team_lead_name',
  (select t ->> 'team_lead_name' from k58 where k = '001'), 'הילה 58');

select t_eq('K2: ראש צוות פנימי ראשון, אף שהוא אחרון באלף-בית',
  (select t -> 'crew_names' from k58 where k = '002'),
  '["תמר 58", "גלית 58", "דנה 58", "זיו 58", "יעל 58"]'::jsonb);

select t_eq('K3: ראש צוות של הלקוח ראשון, אף שאורי קודם לו באלף-בית',
  (select t -> 'crew_names' from k58 where k = '003'),
  '["חגי 58", "אורי 58", "טל 58"]'::jsonb);

select t_eq('K4: משימה בלי צוות — מערך ריק, לא null',
  (select t -> 'crew_names' from k58 where k = '004'), '[]'::jsonb);
select t_eq('K4: והוא מערך ולא null של JSON',
  (select jsonb_typeof(t -> 'crew_names') from k58 where k = '004'), 'array');
select t_eq('K4: צריך 2, משובצים 0',
  (select (t ->> 'needed') || '/' || (t ->> 'assigned') from k58 where k = '004'), '2/0');

select t_eq('K5: מואצלת — שני עובדי הקבלן, לפי האלף-בית, בלי ראש צוות',
  (select t -> 'crew_names' from k58 where k = '005'), '["ורד 58", "זיו 58"]'::jsonb);
select t_eq('K5: והיא מואצלת לקבלן בשמו',
  (select (t ->> 'delegated') || '/' || (t -> 'contractor_names')::text from k58 where k = '005'),
  'true/["קבלן 58"]');
select t_eq('K2: אינה מואצלת — עובד קבלן בלי terms הוא עדיין בצוות',
  (select t ->> 'delegated' from k58 where k = '002'), 'false');

select t_eq('K6: עובדי לקוח בלבד, לפי האלף-בית',
  (select t -> 'crew_names' from k58 where k = '006'), '["חגי 58", "טל 58", "יעל 58"]'::jsonb);

select t_eq('K7: ראשי צוות בשלושת המאגרים — הפנימי נבחר, וה-team_lead_name זהה',
  (select (t -> 'crew_names' ->> 0) || '/' || (t ->> 'team_lead_name') from k58 where k = '007'),
  'פנינה 58/פנינה 58');
select t_eq('K7: ושני האחרים ממוינים עם כולם',
  (select t -> 'crew_names' from k58 where k = '007'),
  '["פנינה 58", "בועז 58", "הילה 58", "חגי 58"]'::jsonb);

select t_eq('K8: שחר ראש צוות, עובד וגם נהג — שלוש שורות, פעם אחת, וראשון',
  (select t -> 'crew_names' ->> 0 from k58 where k = '008'), 'שחר 58');
select t_eq('K8: ושני אנשים שונים בשם אחד — שניהם בצוות',
  (select t -> 'crew_names' from k58 where k = '008'), '["שחר 58", "כפיל 58", "כפיל 58"]'::jsonb);
select t_eq('K8: שלושה אנשים, לא חמש שורות',
  (select (t ->> 'assigned') || '/' || jsonb_array_length(t -> 'crew_names') from k58 where k = '008'), '3/3');

\echo '--- כל משימה בתמונה ---'
select t_eq('בכל המשימות שבתמונה יש crew_names, והוא מערך',
  (select count(*)::int from s58, jsonb_array_elements(j -> 'tasks') t
    where jsonb_typeof(t -> 'crew_names') is distinct from 'array'), 0);

select t_eq('וה-cardinality שלו שווה ל-assigned בכל משימה בתמונה — לא רק שלי',
  (select count(*)::int from s58, jsonb_array_elements(j -> 'tasks') t
    where jsonb_array_length(t -> 'crew_names') <> (t ->> 'assigned')::int), 0);

select t_eq('והבדיקה הזו אינה ריקה: ברשימה לפחות השמונה שלי',
  (select count(*)::int >= 8 from s58, jsonb_array_elements(j -> 'tasks') t), true);

select t_eq('בכל משימה שיש לה ראש צוות, הוא האיבר הראשון — team_lead_name זהה לו',
  (select count(*)::int from s58, jsonb_array_elements(j -> 'tasks') t
    where t ->> 'team_lead_name' is not null
      and t ->> 'team_lead_name' is distinct from t -> 'crew_names' ->> 0), 0);

select t_eq('כל האיברים הם מחרוזות לא ריקות',
  (select count(*)::int from s58, jsonb_array_elements(j -> 'tasks') t,
          jsonb_array_elements(t -> 'crew_names') e
    where jsonb_typeof(e) <> 'string' or (e #>> '{}') !~ '\S'), 0);

\echo '--- מה שלא ברשימה, גם שמותיו לא ---'
select t_eq('המוסתרת, שנמחקה, שבאירוע שבוטל ושל ארקו — אינן ברשימה',
  (select count(*)::int from s58, jsonb_array_elements(j -> 'tasks') t
    where t ->> 'id' in ('62000000-0000-0000-0000-000000058009', '62000000-0000-0000-0000-000000058010',
                         '62000000-0000-0000-0000-000000058011', '62000000-0000-0000-0000-000000058012')), 0);

select t_eq('ושום שם מהצוות שלהן אינו בפיד כולו',
  (select j::text like '%צוות מוסתר 58%' or j::text like '%צוות נמחק 58%'
          or j::text like '%צוות מבוטל 58%' or j::text like '%צוות ארקו 58%' from s58), false);

select t_eq('המוסתרת עדיין נספרת במונים — היא עבודה שתתבצע (0202)',
  (select (j -> 'kpis' ->> 'tasks_today')::int from s58), 9);

\echo '--- שמות בלבד ---'
select t_eq('מפתחות המשימה: אלה של 0202 ועוד crew_names — לא יותר',
  (select array_agg(k order by k collate "C") from (select distinct jsonb_object_keys(t) as k from k58 where k58.k = '001') x),
  (select array_agg(k order by k collate "C") from unnest(array[
     'id', 'date', 'type_code', 'type_name', 'status_code', 'status_name', 'status_color', 'published',
     'warehouse_at', 'start_at', 'end_at', 'customer_name', 'customer_color', 'end_client_name',
     'event_number', 'title', 'location', 'needed', 'assigned', 'delegated', 'contractor_names',
     'team_lead_name', 'trucks', 'crew_names']) k));

select t_eq('אין בכל המשימות טלפון, ת״ז, שכר או מזהה של אדם',
  (select (j -> 'tasks')::text like '%050-580%'
       or (j -> 'tasks')::text like '%58-ID-%'
       or (j -> 'tasks')::text like '%123.45%'
       or (j -> 'tasks')::text like '%20000000-0000-0000-0000-0000000058%'
       or (j -> 'tasks')::text like '%50000000-0000-0000-0000-0000000058%'
       or (j -> 'tasks')::text like '%cf000000-0000-0000-0000-0000005800%' from s58), false);

select t_eq('והבדיקה הזו אינה ריקה: הטלפון והשכר של אורי אכן שמורים',
  (select p.phone || '/' || w.hourly_rate::text from profiles p join worker_pay_settings w on w.profile_id = p.id
    where p.id = '20000000-0000-0000-0000-0000000058a1'), '050-5800001/123.45');

\echo '--- ושאר הפיד לא זז ---'
select t_eq('המפתחות של הפיד כולו',
  (select array_agg(k order by k collate "C") from (select jsonb_object_keys(j) k from s58) x),
  (select array_agg(k order by k collate "C") from unnest(array[
     'v', 'source', 'generated_at', 'today', 'days', 'tasks', 'shifts_now', 'attendance', 'kpis',
     'alerts', 'finance']) k));
select t_eq('והמונים',
  (select array_agg(k order by k collate "C") from (select jsonb_object_keys(j -> 'kpis') k from s58) x),
  (select array_agg(k order by k collate "C") from unnest(array[
     'tasks_today', 'setups_today', 'teardowns_today', 'tasks_next_7d', 'understaffed_48h',
     'unpublished_48h', 'workers_on_shift']) k));
select t_eq('וההתראות',
  (select array_agg(k order by k collate "C") from (select jsonb_object_keys(j -> 'alerts') k from s58) x),
  (select array_agg(k order by k collate "C") from unnest(array[
     'understaffed', 'unpublished', 'fleet_documents', 'attendance_pending', 'correction_requests',
     'integration_failures']) k));
select t_eq('הכספים',
  (select array_agg(k order by k collate "C") from (select jsonb_object_keys(j -> 'finance') k from s58) x),
  (select array_agg(k order by k collate "C") from unnest(array[
     'month_start', 'month_end', 'revenue_mtd', 'contractor_mtd', 'payroll_mtd', 'gross_mtd',
     'gross_pct', 'forecast_rest_of_month', 'unrated_shifts']) k));
select t_eq('היום: תשע משימות (K1..K9), חמש הקמות וארבעה פירוקים',
  (select (j -> 'kpis' ->> 'tasks_today') || '/' || (j -> 'kpis' ->> 'setups_today')
          || '/' || (j -> 'kpis' ->> 'teardowns_today') from s58), '9/5/4');
select t_eq('שבעה ימים: אחד-עשר, כולל K13 ו-K14 שמחוץ לרשימה של היום אחד',
  (select (j -> 'kpis' ->> 'tasks_next_7d')::int from s58), 11);
select t_eq('חותמות הזמן יוצאות ב-UTC עם היסט',
  (select j ->> 'generated_at' from s58) like '%+00:00', true);

-- ===== 3. התקרה, ושמות ריקים — שלושה ימים =====================================

\echo '--- שלושה ימים: התקרה והשמות הריקים ---'
create temp table s58f as select app.wall_snapshot_at(t58_at(0, '10:00'), 3) as j;

create temp table kf58 as
select right(t ->> 'id', 3) as k, t
  from s58f, jsonb_array_elements(j -> 'tasks') t
 where t ->> 'id' like '62000000-0000-0000-0000-000000058%';

select t_eq('בשלושה ימים נכנסות גם K13 ו-K14',
  (select string_agg(k, ',' order by k) from kf58), '001,002,003,004,005,006,007,008,013,014');

select t_eq('K13: 45 אנשים, ו-assigned אומר את המספר האמיתי',
  (select (t ->> 'needed') || '/' || (t ->> 'assigned') from kf58 where k = '013'), '45/45');
select t_eq('K13: אבל crew_names נחתך ל-40',
  (select jsonb_array_length(t -> 'crew_names') from kf58 where k = '013'), 40);
select t_eq('K13: ראש הצוות — האחרון באלף-בית — נשאר ראשון',
  (select t -> 'crew_names' ->> 0 from kf58 where k = '013'), 'מקס 58 45');
select t_eq('K13: ואחריו מתחיל האלף-בית ונחתך בסוף: 01 עד 39',
  (select (t -> 'crew_names' ->> 1) || '..' || (t -> 'crew_names' ->> 39) from kf58 where k = '013'),
  'מקס 58 01..מקס 58 39');
select t_eq('K13: ומי שנחתך הוא 40 עד 44, לא ראש הצוות',
  (select count(*)::int from kf58, jsonb_array_elements_text(t -> 'crew_names') e
    where k = '013' and e in ('מקס 58 40', 'מקס 58 41', 'מקס 58 42', 'מקס 58 43', 'מקס 58 44')), 0);
select t_eq('K13: וכל ארבעים השמות שונים',
  (select count(distinct e)::int from kf58, jsonb_array_elements_text(t -> 'crew_names') e where k = '013'), 40);

select t_eq('בכל משימה בתמונה crew_names הוא min(assigned, 40) — חוץ מ-K14 שבה שמות ריקים',
  (select count(*)::int from s58f, jsonb_array_elements(j -> 'tasks') t
    where t ->> 'id' <> '62000000-0000-0000-0000-000000058014'
      and jsonb_array_length(t -> 'crew_names') <> least((t ->> 'assigned')::int, 40)), 0);

\echo '--- שמות ריקים ---'
select t_eq('K14: שישה אנשים משובצים, ארבעה מהם בלי שם — ב-crew_names נשארים שניים',
  (select (t ->> 'assigned') || '/' || jsonb_array_length(t -> 'crew_names') from kf58 where k = '014'), '6/2');
select t_eq('K14: מדלגים על ריק, רווחים וטאב — ראש הצוות הריק לא מופיע, ונשארים עם השם',
  (select t -> 'crew_names' from kf58 where k = '014'), '["זיו 58", "רונית 58"]'::jsonb);
select t_eq('בכל התמונה אין שם ריק: לא ריק, לא רווחים ולא טאב',
  (select count(*)::int from s58f, jsonb_array_elements(j -> 'tasks') t,
          jsonb_array_elements_text(t -> 'crew_names') e
    where e !~ '\S'), 0);
select t_eq('וההפרש בין assigned ל-cardinality בכל התמונה הוא בדיוק מספר האנשים בלי שם (4)',
  (select coalesce(sum((t ->> 'assigned')::int - jsonb_array_length(t -> 'crew_names')), 0)::int
     from s58f, jsonb_array_elements(j -> 'tasks') t
    where t ->> 'id' like '62000000-0000-0000-0000-000000058%'
      and t ->> 'id' <> '62000000-0000-0000-0000-000000058013'), 4);

-- ===== 4. העוזר עצמו =========================================================

\echo '--- העוזר: אינו מסנן משימות, ואינו מחזיר null ---'
select t_eq('משימה מוסתרת: העוזר נותן את השמות — הסינון הוא של הרשימה',
  app.wall_task_crew('62000000-0000-0000-0000-000000058009'), array['ורד 58', 'צוות מוסתר 58']);
select t_eq('משימה שאינה קיימת — מערך ריק',
  app.wall_task_crew('62000000-0000-0000-0000-000000058999'), '{}'::text[]);
select t_eq('ו-null — מערך ריק',
  app.wall_task_crew(null), '{}'::text[]);
select t_eq('ו-cardinality של K13 הוא 40 גם ישירות',
  cardinality(app.wall_task_crew('62000000-0000-0000-0000-000000058013')), 40);

-- ===== 5. הדלת, בשעון האמיתי =================================================
--
-- ‏`public.wall_snapshot` נקראת עם `now()` ולא עם שעון נעוץ, ולכן משימה של
-- היום-של-ישראל נוצרת כאן בתוך טרנזקציה אחת, נבדקת דרך הדלת כ-service_role,
-- ומתבטלת — כך שדבר אינו נשאר אחריה, לא משימה ולא סוד ב-Vault.

\echo '--- הדלת כ-service_role, בשעון האמיתי ---'
begin;

select vault.create_secret(encode(sha256(convert_to('door-58-' || repeat('d', 40), 'UTF8')), 'hex'),
                           'wall_feed_secret_58door', 'sha256 of the 58 test secret');

insert into tasks (id, customer_id, task_type_id, task_date, title, onsite_start_time, hours_count,
                   status_id, worker_count, performed_by)
values ('62000000-0000-0000-0000-000000058f01', '10000000-0000-0000-0000-00000000058a',
        (select id from task_types where code = 'setup' limit 1),
        (now() at time zone 'Asia/Jerusalem')::date, 'דלת 58', '12:00', 2.0,
        (select id from statuses where entity = 'task' and code = 'assigned' and deleted_at is null),
        3, 'viper');
insert into task_assignments (task_id, profile_id, role, work_site) values
  ('62000000-0000-0000-0000-000000058f01', '20000000-0000-0000-0000-0000000058a1', 'worker', 'field');
insert into task_contractor_workers (task_id, contractor_worker_id, role, work_site) values
  ('62000000-0000-0000-0000-000000058f01', '50000000-0000-0000-0000-0000000058a1', 'team_lead', 'field');
insert into task_customer_workers (task_id, customer_worker_id, role, work_site) values
  ('62000000-0000-0000-0000-000000058f01', 'cf000000-0000-0000-0000-0000005800a2', null, 'field');

set role service_role;
select t_eq('הדלת עובדת ל-service_role, והמשימה של היום נושאת את שמות הצוות — ראש הקבלן ראשון',
  (select t -> 'crew_names'
     from jsonb_array_elements(public.wall_snapshot('door-58-' || repeat('d', 40), 3) -> 'tasks') t
    where t ->> 'id' = '62000000-0000-0000-0000-000000058f01'),
  '["הילה 58", "אורי 58", "טל 58"]'::jsonb);
select t_eq('וכל משימה שהדלת מחזירה נושאת crew_names',
  (select count(*)::int
     from jsonb_array_elements(public.wall_snapshot('door-58-' || repeat('d', 40), 3) -> 'tasks') t
    where jsonb_typeof(t -> 'crew_names') is distinct from 'array'), 0);
reset role;

rollback;

select t_eq('והטרנזקציה לא השאירה אחריה משימה ולא סוד',
  (select count(*)::int from tasks where id = '62000000-0000-0000-0000-000000058f01')
  + (select count(*)::int from vault.secrets where name = 'wall_feed_secret_58door'), 0);
