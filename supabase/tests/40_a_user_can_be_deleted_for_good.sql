\pset tuples_only on
\pset format unaligned

-- ===========================================================================
-- 40: מנהל מערכת מוחק משתמש לצמיתות (0160).
--
--     מה שנבדק כאן הוא הגבול: מה יורד עם החשבון (משמרות, שיבוצים, התראות),
--     מה נשאר בלי השם שלו (אירוע, משימה, קבלה, משמרת של מישהו אחר שהוא
--     ערך), ומי בכלל רשאי — לא הרכז, לא על עצמך, ולא על משתמש חי.
--
--     החלון הוא current_date + 570.
-- ===========================================================================

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000040a1', 'c40-admin@vl.test'),
  ('00000000-0000-0000-0000-0000000040a2', 'c40-office@vl.test'),
  ('00000000-0000-0000-0000-0000000040a3', 'c40-worker@vl.test');

insert into customers (id, name) values
  ('10000000-0000-0000-0000-00000000040a', 'לקוח 40');
insert into contractors (id, name) values
  ('11000000-0000-0000-0000-00000000040a', 'קבלן 40');

insert into profiles (id, user_id, user_kind, is_admin, full_name) values
  ('20000000-0000-0000-0000-0000000040a1', '00000000-0000-0000-0000-0000000040a1', 'staff', true,  'מנהל 40'),
  ('20000000-0000-0000-0000-0000000040a2', '00000000-0000-0000-0000-0000000040a2', 'staff', false, 'רכז 40'),
  ('20000000-0000-0000-0000-0000000040a3', '00000000-0000-0000-0000-0000000040a3', 'staff', false, 'עובד 40');

insert into staff_roles (profile_id, role) values
  ('20000000-0000-0000-0000-0000000040a3', 'worker');
-- ‏users.edit לצד users.delete: app.can_manage_profile דורשת את הראשון כדי
-- לענות "כן" על משתמש מסוים, וה-users.delete הוא רק "מותר לך למחוק משתמשים".
insert into user_permission_grants (profile_id, permission_key, allowed) values
  ('20000000-0000-0000-0000-0000000040a2', 'users.delete', true),
  ('20000000-0000-0000-0000-0000000040a2', 'users.edit', true),
  ('20000000-0000-0000-0000-0000000040a3', 'tasks.view', true);

-- שורת סגל אצל קבלן שמחזיקה את חשבון ההתחברות של העובד. ‏0149/0150: השורה
-- שייכת לקבלן ואינה נמחקת איתו — מה שמתאפס הוא ההצבעה ל-auth.
insert into contractor_workers (id, contractor_id, full_name, user_id) values
  ('12000000-0000-0000-0000-00000000040a', '11000000-0000-0000-0000-00000000040a',
   'עובד 40', '00000000-0000-0000-0000-0000000040a3');

-- אירוע שהעובד יצר ואישר. ‏approved_by נכתב כאן ב-INSERT במכוון:
-- ‏events_approval_guard (0115) חוסם *עדכון* שלו, וזו בדיוק הסיבה שהמחיקה
-- ב-0160 עוטפת את האיפוסים ב-app.system_write.
insert into events (id, customer_id, event_number, event_date, end_client_name, status_id,
                    created_by, approved_by, approved_at)
values ('30000000-0000-0000-0000-00000000040a', '10000000-0000-0000-0000-00000000040a',
        'EV-40A', current_date + 570, 'קצה 40',
        (select id from statuses where entity = 'event' and code = 'pending' and deleted_at is null),
        '20000000-0000-0000-0000-0000000040a3',
        '20000000-0000-0000-0000-0000000040a3', now());

insert into tasks (id, event_id, customer_id, task_type_id, task_date, worker_count, status_id, created_by)
select '61000000-0000-0000-0000-000000040001', '30000000-0000-0000-0000-00000000040a',
       '10000000-0000-0000-0000-00000000040a', tt.id, current_date + 570, 2,
       (select id from statuses where entity = 'task' and code = 'draft' and deleted_at is null),
       '20000000-0000-0000-0000-0000000040a3'
  from task_types tt where tt.code = 'setup' limit 1;

insert into receipts (id, customer_id, amount, received_at, created_by) values
  ('62000000-0000-0000-0000-000000040001', '10000000-0000-0000-0000-00000000040a',
   1000, current_date + 570, '20000000-0000-0000-0000-0000000040a3');

insert into task_assignments (task_id, profile_id, role) values
  ('61000000-0000-0000-0000-000000040001', '20000000-0000-0000-0000-0000000040a3', 'worker');

-- המשמרת שלו, עם מענק שתלוי בה
insert into attendance_entries (id, profile_id, work_date, seq, task_ids, clock_in_at, clock_out_at, source)
values ('70000000-0000-0000-0000-000000040001', '20000000-0000-0000-0000-0000000040a3',
        current_date + 570, 1, array['61000000-0000-0000-0000-000000040001'::uuid],
        (current_date + 570) + time '08:00', (current_date + 570) + time '12:00', 'manual');
insert into attendance_entry_bonus (entry_id, amount, created_by) values
  ('70000000-0000-0000-0000-000000040001', 50, '20000000-0000-0000-0000-0000000040a1');

-- המשמרת של הרכז, שהעובד ערך ואישר. השורה הזו היא של מישהו אחר, והיא נשארת.
insert into attendance_entries (id, profile_id, work_date, seq, task_ids, clock_in_at, clock_out_at,
                                source, created_by, edited_by, reviewed_by)
values ('70000000-0000-0000-0000-000000040002', '20000000-0000-0000-0000-0000000040a2',
        current_date + 570, 1, array['61000000-0000-0000-0000-000000040001'::uuid],
        (current_date + 570) + time '08:00', (current_date + 570) + time '12:00', 'manual',
        '20000000-0000-0000-0000-0000000040a3',
        '20000000-0000-0000-0000-0000000040a3',
        '20000000-0000-0000-0000-0000000040a3');

insert into notifications (recipient_id, type, title) values
  ('20000000-0000-0000-0000-0000000040a3', 'assignment', 'שובצת למשימה');

\echo '--- מי רשאי בכלל ---'
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000040a2', false);
select t_expect_fail('רכז אינו קורא ל-user_delete_impact',
  $$select user_delete_impact('20000000-0000-0000-0000-0000000040a3')$$);
select t_expect_fail('ורכז אינו מוחק משתמש לצמיתות',
  $$select hard_delete('profiles', '20000000-0000-0000-0000-0000000040a3')$$);
select t_expect_ok('אבל הוא כן מעביר אותו לסל (users.delete)',
  $$select soft_delete('profiles', '20000000-0000-0000-0000-0000000040a3')$$);
reset role;
select set_config('request.jwt.claim.sub', '', false);

select t_eq('המשתמש בסל',
  (select deleted_at is not null from profiles where id = '20000000-0000-0000-0000-0000000040a3'), true);

\echo '--- המנהל רואה מה המחיקה תעלה, לפני שהוא לוחץ ---'
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000040a1', false);
select t_eq('שתי משמרות? לא — רק שלו',
  (select (user_delete_impact('20000000-0000-0000-0000-0000000040a3') ->> 'shifts')::int), 1);
select t_eq('שיבוץ אחד',
  (select (user_delete_impact('20000000-0000-0000-0000-0000000040a3') ->> 'assignments')::int), 1);
select t_eq('אירוע אחד שיצר',
  (select (user_delete_impact('20000000-0000-0000-0000-0000000040a3') ->> 'events_created')::int), 1);
-- שלוש, ולא אחת: שתי משימות ברירת המחדל שנוצרו עם האירוע יורשות את
-- ‏created_by שלו (app.create_default_tasks), ובצדק — הוא שיצר את האירוע.
select t_eq('שלוש משימות שיצר — שלו ושתי ברירות המחדל של האירוע',
  (select (user_delete_impact('20000000-0000-0000-0000-0000000040a3') ->> 'tasks_created')::int), 3);
select t_eq('קבלה אחת שרשם',
  (select (user_delete_impact('20000000-0000-0000-0000-0000000040a3') ->> 'receipts')::int), 1);
select t_eq('ויש לו חשבון התחברות',
  (select (user_delete_impact('20000000-0000-0000-0000-0000000040a3') ->> 'has_login')::boolean), true);

\echo '--- ולא על עצמך, ולא על משתמש חי ---'
select t_expect_fail('מנהל אינו מוחק את עצמו לצמיתות',
  $$select hard_delete('profiles', '20000000-0000-0000-0000-0000000040a1')$$);
select t_expect_fail('ואינו מוחק לצמיתות משתמש שאינו בסל',
  $$select hard_delete('profiles', '20000000-0000-0000-0000-0000000040a2')$$);

\echo '--- המחיקה עצמה ---'
select t_expect_ok('מנהל מוחק לצמיתות משתמש מהסל',
  $$select hard_delete('profiles', '20000000-0000-0000-0000-0000000040a3')$$);
reset role;
select set_config('request.jwt.claim.sub', '', false);

select t_eq('המשתמש נעלם',
  (select count(*)::int from profiles where id = '20000000-0000-0000-0000-0000000040a3'), 0);
select t_eq('ותפקיד הצוות שלו ירד בקסקייד',
  (select count(*)::int from staff_roles where profile_id = '20000000-0000-0000-0000-0000000040a3'), 0);
select t_eq('וההרשאה האישית שלו',
  (select count(*)::int from user_permission_grants where profile_id = '20000000-0000-0000-0000-0000000040a3'), 0);

\echo '--- מה שהיה שלו ירד איתו ---'
select t_eq('המשמרת שלו נמחקה',
  (select count(*)::int from attendance_entries where id = '70000000-0000-0000-0000-000000040001'), 0);
select t_eq('והמענק שתלוי בה ירד בקסקייד',
  (select count(*)::int from attendance_entry_bonus
    where entry_id = '70000000-0000-0000-0000-000000040001'), 0);
select t_eq('השיבוץ שלו נמחק',
  (select count(*)::int from task_assignments
    where task_id = '61000000-0000-0000-0000-000000040001'), 0);
select t_eq('וההתראות שלו',
  (select count(*)::int from notifications where recipient_id = '20000000-0000-0000-0000-0000000040a3'), 0);

\echo '--- ומה שרק הצביע עליו נשאר, בלי השם ---'
select t_eq('האירוע נשאר',
  (select count(*)::int from events where id = '30000000-0000-0000-0000-00000000040a'), 1);
select t_eq('בלי שם היוצר',
  (select created_by from events where id = '30000000-0000-0000-0000-00000000040a'), null::uuid);
select t_eq('ובלי שם המאשר (הפרצה של events_approval_guard)',
  (select approved_by from events where id = '30000000-0000-0000-0000-00000000040a'), null::uuid);
select t_eq('והוא עדיין מאושר',
  (select approved_at is not null from events where id = '30000000-0000-0000-0000-00000000040a'), true);
select t_eq('המשימות נשארו, בלי שם היוצר',
  (select count(*)::int from tasks where event_id = '30000000-0000-0000-0000-00000000040a'
     and created_by is not null), 0);
select t_eq('ושלושתן עדיין שם',
  (select count(*)::int from tasks where event_id = '30000000-0000-0000-0000-00000000040a'), 3);
select t_eq('הקבלה נשארה, בלי שם הרושם',
  (select created_by from receipts where id = '62000000-0000-0000-0000-000000040001'), null::uuid);
select t_eq('המשמרת של הרכז נשארה',
  (select count(*)::int from attendance_entries where id = '70000000-0000-0000-0000-000000040002'), 1);
select t_eq('ומי שערך אותה כבר אינו רשום',
  (select coalesce(created_by, edited_by, reviewed_by) from attendance_entries
    where id = '70000000-0000-0000-0000-000000040002'), null::uuid);

\echo '--- שורת הסגל אצל הקבלן שורדת את מחיקת החשבון ---'
select t_eq('השורה נשארה אצל הקבלן',
  (select count(*)::int from contractor_workers where id = '12000000-0000-0000-0000-00000000040a'), 1);
select t_eq('וההצבעה לחשבון ההתחברות התאפסה',
  (select user_id from contractor_workers where id = '12000000-0000-0000-0000-00000000040a'), null::uuid);
