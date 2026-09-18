\pset tuples_only on
\pset format unaligned

-- ===========================================================================
-- 50: לעובד של הלקוח יש חשבון (0178), והמשימה שהוא מבצע היא של הלקוח
--     לשנות (0179).
--
-- החלון הוא current_date + 710, מעבר לכל טווח קודם.
-- ===========================================================================

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000050a1', 'c50-admin@vl.test'),
  ('00000000-0000-0000-0000-0000000050a2', 'c50-arko@vl.test'),
  ('00000000-0000-0000-0000-0000000050a3', 'c50-worker@vl.test'),
  ('00000000-0000-0000-0000-0000000050a4', 'c50-other@vl.test'),
  ('00000000-0000-0000-0000-0000000050a5', 'c50-staff@vl.test');

insert into customers (id, name, performed_by_enabled) values
  ('10000000-0000-0000-0000-00000000050a', 'ארקו 50', true),
  ('10000000-0000-0000-0000-00000000050b', 'לקוח רגיל 50', false);

insert into profiles (id, user_id, user_kind, is_admin, full_name) values
  ('20000000-0000-0000-0000-0000000050a1', '00000000-0000-0000-0000-0000000050a1',
   'staff', true, 'מנהל 50'),
  ('20000000-0000-0000-0000-0000000050a5', '00000000-0000-0000-0000-0000000050a5',
   'staff', false, 'רכז 50');
insert into profiles (id, user_id, user_kind, is_admin, full_name, customer_id) values
  ('20000000-0000-0000-0000-0000000050a2', '00000000-0000-0000-0000-0000000050a2',
   'customer_user', false, 'מנהל אצל ארקו 50', '10000000-0000-0000-0000-00000000050a'),
  ('20000000-0000-0000-0000-0000000050a4', '00000000-0000-0000-0000-0000000050a4',
   'customer_user', false, 'מנהל אצל לקוח רגיל 50', '10000000-0000-0000-0000-00000000050b');

insert into profile_roles (profile_id, role_id)
select p, id from permission_roles r,
  unnest(array['20000000-0000-0000-0000-0000000050a2'::uuid,
               '20000000-0000-0000-0000-0000000050a4'::uuid]) p
where r.key = 'customer_manager';
insert into profile_roles (profile_id, role_id)
select '20000000-0000-0000-0000-0000000050a5', id from permission_roles where key = 'dispatcher';

insert into events (id, customer_id, event_number, event_date, end_client_name, status_id)
values ('30000000-0000-0000-0000-00000000050a', '10000000-0000-0000-0000-00000000050a',
        'EV-50', current_date + 710, 'קצה 50',
        (select id from statuses where entity = 'event' and code = 'pending' and deleted_at is null));

-- ההקמה עוברת לארקו, הפירוק נשאר על וייפר — שתי המשימות של אותו אירוע,
-- וכל בדיקה כאן היא על ההבדל ביניהן.
update tasks set performed_by = 'arko'
 where event_id = '30000000-0000-0000-0000-00000000050a'
   and task_type_id = (select id from task_types where code = 'setup' limit 1);

-- שעות, כדי שתהיה משמרת לגזור (0020).
update tasks set onsite_start_time = '08:00', hours_count = 4
 where event_id = '30000000-0000-0000-0000-00000000050a';

insert into customer_workers (id, customer_id, full_name, phone) values
  ('cf000000-0000-0000-0000-0000005000a1', '10000000-0000-0000-0000-00000000050a', 'עובד ארקו 50', '050-5000050');

-- ===== 1. מי פותח חשבון לעובד ============================================

\echo '--- החשבון נפתח בידי מנהל הלקוח ---'
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000050a2', false);
select t_expect_ok('מנהל ארקו פותח חשבון לעובד שלו', $$
  select customer_staff_account('cf000000-0000-0000-0000-0000005000a1')$$);
reset role;
select set_config('request.jwt.claim.sub', '', false);

select t_eq('נולדה שורת פרופיל, של הלקוח, מסוג לקוח',
  (select user_kind::text || '/' || customer_id::text from profiles
    where customer_worker_id = 'cf000000-0000-0000-0000-0000005000a1'),
  'customer_user/10000000-0000-0000-0000-00000000050a');

select t_eq('ועליה התפקיד הצר "עובד אצל הלקוח"',
  (select r.key from profiles p
     join profile_roles pr on pr.profile_id = p.id
     join permission_roles r on r.id = pr.role_id
    where p.customer_worker_id = 'cf000000-0000-0000-0000-0000005000a1'), 'customer_worker');

select t_eq('ואין לה חשבון התחברות עד ש-admin-users ייתן לה אחד',
  (select user_id from profiles
    where customer_worker_id = 'cf000000-0000-0000-0000-0000005000a1'), null::uuid);

\echo '--- ולא בידי לקוח אחר ---'
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000050a4', false);
select t_expect_fail('מנהל אצל לקוח אחר נדחה', $$
  select customer_staff_account('cf000000-0000-0000-0000-0000005000a1')$$);
select t_eq('וגם השאלה על חשבון ההתחברות נענית לו בשלילה',
  can_manage_own_staff_login(
    (select id from profiles where customer_worker_id = 'cf000000-0000-0000-0000-0000005000a1')),
  false);
reset role;
select set_config('request.jwt.claim.sub', '', false);

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000050a2', false);
select t_eq('ולמנהל ארקו — בחיוב',
  can_manage_own_staff_login(
    (select id from profiles where customer_worker_id = 'cf000000-0000-0000-0000-0000005000a1')),
  true);
select t_eq('והרשימה אומרת שלעובד יש חשבון',
  (select (x ->> 'has_login')::boolean
     from jsonb_array_elements(customer_assignable_workers()) x
    where x ->> 'worker_id' = 'cf000000-0000-0000-0000-0000005000a1'), true);
reset role;
select set_config('request.jwt.claim.sub', '', false);

-- החיבור ל-auth.users הוא של ה-service role (admin-users), וכאן הוא נעשה
-- ישירות — בדיוק כפי שכל חבילה אחרת מזריעה פרופיל עם user_id.
update profiles set user_id = '00000000-0000-0000-0000-0000000050a3'
 where customer_worker_id = 'cf000000-0000-0000-0000-0000005000a1';

-- ===== 2. מה שיש לו, ומה שאין לו =========================================

\echo '--- העובד מחזיק את מה שעובד מחזיק, ולא יותר ---'
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000050a3', false);
select t_eq('לו״ז עבודה',           app.has('board.view'), true);
select t_eq('המשימה',               app.has('tasks.view'), true);
select t_eq('דלת דף האירוע',        app.has('events.view'), true);
select t_eq('לוח המשמרות שלו',      app.has('attendance.view_schedule'), true);
select t_eq('אבל לא שעון נוכחות',   app.has('attendance.clock'), false);
select t_eq('ולא רשימת האירועים',   app.has('events.list'), false);
select t_eq('ולא יצירת אירוע',      app.has('events.create'), false);
select t_eq('ולא עריכת משימה',      app.has('tasks.edit'), false);
select t_eq('ולא מחירים',           app.has('pricing.view'), false);
select t_eq('ולא דשבורד',           app.has('dashboard.view'), false);
select t_eq('ולא ניהול הסגל',       app.has('customers.manage_own_staff'), false);
select t_eq('ולא שיבוץ הסגל',       app.has('customers.assign_own_staff'), false);
reset role;
select set_config('request.jwt.claim.sub', '', false);

\echo '--- ובלי שיבוץ הוא אינו רואה דבר ---'
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000050a3', false);
select t_eq('משימות הלקוח שלו אינן שלו עד שישובץ',
  (select count(*)::int from tasks where customer_id = '10000000-0000-0000-0000-00000000050a'), 0);
select t_eq('וגם האירוע לא',
  (select count(*)::int from events where id = '30000000-0000-0000-0000-00000000050a'), 0);
reset role;
select set_config('request.jwt.claim.sub', '', false);

-- ===== 3. השיבוץ פותח לו את המשימה, ואותה בלבד ===========================

\echo '--- מנהל ארקו משבץ אותו למשימה שארקו מבצעת ---'
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000050a2', false);
select t_expect_ok('השיבוץ נכתב', $$
  select customer_assign_worker(
    (select t.id from tasks t where t.event_id = '30000000-0000-0000-0000-00000000050a'
       and t.task_type_id = (select id from task_types where code='setup' limit 1)
       and t.deleted_at is null limit 1),
    'cf000000-0000-0000-0000-0000005000a1', true, null, null)$$);
reset role;
select set_config('request.jwt.claim.sub', '', false);

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000050a3', false);
select t_eq('ומעכשיו הוא רואה משימה אחת — זו ששובץ אליה',
  (select count(*)::int from tasks where customer_id = '10000000-0000-0000-0000-00000000050a'), 1);
select t_eq('והיא זו שארקו מבצעת',
  (select performed_by from tasks
    where customer_id = '10000000-0000-0000-0000-00000000050a' limit 1), 'arko');
select t_eq('משימת הפירוק של וייפר אינה שלו',
  (select count(*)::int from tasks t
    where t.event_id = '30000000-0000-0000-0000-00000000050a'
      and t.task_type_id = (select id from task_types where code='teardown' limit 1)), 0);
select t_eq('האירוע נפתח לו, כי יש בו משימה שלו',
  (select count(*)::int from events where id = '30000000-0000-0000-0000-00000000050a'), 1);
select t_eq('והלו״ז מחזיר לו את השורה',
  (select count(*)::int from work_board_view
    where customer_id = '10000000-0000-0000-0000-00000000050a'), 1);
select t_eq('בלי שהוא רואה שם שום משימה של לקוח אחר',
  (select count(*)::int from work_board_view
    where customer_id <> '10000000-0000-0000-0000-00000000050a'), 0);
reset role;
select set_config('request.jwt.claim.sub', '', false);

-- ===== 4. "לשנות כל דבר במשימות שלו" (0179) ==============================

\echo '--- הלקוח עורך שדה שלא נפתח לו — במשימה שהוא מבצע ---'
-- ‏`hours_count` נשאר 'visible' בקונפיגורציה (0109), ורק 'truck'/'status'
-- נפתחו ללקוח שמבצע בעצמו (0138). זה בדיוק ההבדל שהקובץ החדש מייצר.
select t_eq('ואכן — "משך" אינו פתוח לעריכה בקונפיגורציה',
  (select state::text from customer_board_fields
    where customer_id = '10000000-0000-0000-0000-00000000050a' and field_key = 'hours_count'),
  'visible');

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000050a2', false);
select t_expect_ok('במשימה שארקו מבצעת — המשך נערך', $$
  update tasks set hours_count = 5
   where event_id = '30000000-0000-0000-0000-00000000050a'
     and performed_by = 'arko'$$);
select t_expect_fail('ובמשימה של וייפר — נדחה, בדיוק כמו היום', $$
  update tasks set hours_count = 5
   where event_id = '30000000-0000-0000-0000-00000000050a'
     and performed_by = 'viper'$$);
select t_expect_ok('ומה שהמשרד כן פתח לו שם נשאר פתוח (0138)', $$
  update tasks set truck_free_text = 'משאית 50'
   where event_id = '30000000-0000-0000-0000-00000000050a'
     and performed_by = 'viper'$$);
reset role;
select set_config('request.jwt.claim.sub', '', false);

select t_eq('המשך אכן נכתב במשימת ארקו',
  (select hours_count from tasks
    where event_id = '30000000-0000-0000-0000-00000000050a' and performed_by = 'arko'), 5::numeric);
select t_eq('ולא במשימת וייפר',
  (select hours_count from tasks
    where event_id = '30000000-0000-0000-0000-00000000050a' and performed_by = 'viper'), 4::numeric);

\echo '--- והפרסום: את שלו הוא מפרסם, את של וייפר לא ---'
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000050a2', false);
select t_eq('המפתח עצמו אינו בידו',  app.has('tasks.publish'), false);
select t_expect_ok('ובכל זאת — משימת ארקו עולה ל"משובץ"', $$
  update tasks set status_id =
    (select id from statuses where entity='task' and code='assigned' and deleted_at is null)
   where event_id = '30000000-0000-0000-0000-00000000050a'
     and performed_by = 'arko'$$);
select t_expect_fail('ומשימת וייפר — לא', $$
  update tasks set status_id =
    (select id from statuses where entity='task' and code='assigned' and deleted_at is null)
   where event_id = '30000000-0000-0000-0000-00000000050a'
     and performed_by = 'viper'$$);
reset role;
select set_config('request.jwt.claim.sub', '', false);

select t_eq('משימת ארקו משובצת',
  (select s.code from tasks t join statuses s on s.id = t.status_id
    where t.event_id = '30000000-0000-0000-0000-00000000050a' and t.performed_by = 'arko'), 'assigned');

-- ===== 5. והמשמרת מגיעה אליו (0178 §4) ===================================

\echo '--- המשמרת נגזרת מהמשימה, גם כשהשיבוץ הוא בסגל הלקוח ---'
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000050a3', false);
select t_eq('משמרת אחת בשבוע של האירוע',
  (select count(*)::int from my_shifts(current_date + 709, current_date + 711)), 1);
select t_eq('ובתאריך של המשימה',
  (select (s ->> 'work_date')::date from my_shifts(current_date + 709, current_date + 711) s),
  (current_date + 710)::date);
reset role;
select set_config('request.jwt.claim.sub', '', false);

-- ===== 6. הצוות של וייפר אינו רואה דבר מכל זה ============================

\echo '--- רכז השיבוצים: המשימה של ארקו אינה שלו, וגם לא העובד שלה ---'
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000050a5', false);
select t_eq('משימת ארקו מוסתרת ממנו (0120/0135)',
  (select count(*)::int from tasks t
    where t.event_id = '30000000-0000-0000-0000-00000000050a' and t.performed_by = 'arko'), 0);
select t_eq('והוא אינו פותח חשבון לסגל של לקוח', (select app.has('customers.manage_own_staff')), false);
reset role;
select set_config('request.jwt.claim.sub', '', false);

-- ===== 7. עובד שיורד מהסגל — החשבון יורד איתו ============================

\echo '--- הסרת העובד מכבה את החשבון שלו ---'
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000050a2', false);
select t_expect_ok('מנהל ארקו מסיר את העובד מהסגל', $$
  update customer_workers set deleted_at = now()
   where id = 'cf000000-0000-0000-0000-0000005000a1'$$);
reset role;
select set_config('request.jwt.claim.sub', '', false);

select t_eq('והחשבון כבוי',
  (select is_active from profiles
    where customer_worker_id = 'cf000000-0000-0000-0000-0000005000a1'), false);
select t_eq('ונמחק רכות',
  (select deleted_at is not null from profiles
    where customer_worker_id = 'cf000000-0000-0000-0000-0000005000a1'), true);

\echo '--- ומכאן הוא אינו נכנס יותר ---'
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000050a3', false);
select t_eq('ההרשאות שלו ריקות', (select get_my_permissions()), null::jsonb);
reset role;
select set_config('request.jwt.claim.sub', '', false);
