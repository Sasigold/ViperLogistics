\pset tuples_only on
\pset format unaligned

-- ===========================================================================
-- 29: "בוצע ע"י" — משימת ארקו מוסתרת מוייפר ומחירה 0 (0120), הפרצות
--     נסגרות והשיבוצים יורדים (0135), והמעבר מדבר (0136).
--
-- החלון הוא current_date + 450, מעבר ל-440 של 28.
-- ===========================================================================

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000029a1', 'c29-admin@vl.test'),
  ('00000000-0000-0000-0000-0000000029a2', 'c29-office@vl.test'),
  ('00000000-0000-0000-0000-0000000029a3', 'c29-cust@vl.test');

-- לקוח שהאפשרות מופעלת אצלו (כמו ארקו), במצב תמחור אוטומטי
insert into customers (id, name, pricing_mode, performed_by_enabled) values
  ('10000000-0000-0000-0000-00000000029a', 'ארקו 29', 'auto', true);

insert into profiles (id, user_id, user_kind, is_admin, full_name) values
  ('20000000-0000-0000-0000-0000000029a1', '00000000-0000-0000-0000-0000000029a1',
   'staff', true, 'מנהל 29'),
  ('20000000-0000-0000-0000-0000000029a2', '00000000-0000-0000-0000-0000000029a2',
   'staff', false, 'רכז משרד 29');
insert into profiles (id, user_id, user_kind, is_admin, full_name, customer_id) values
  ('20000000-0000-0000-0000-0000000029a3', '00000000-0000-0000-0000-0000000029a3',
   'customer_user', false, 'משתמש ארקו 29', '10000000-0000-0000-0000-00000000029a');

-- הרכז רואה משימות טיוטה רק אם הוא יכול לתכנן (tasks.edit → can_plan_tasks).
insert into user_permission_grants (profile_id, permission_key, allowed) values
  ('20000000-0000-0000-0000-0000000029a2', 'tasks.view', true),
  ('20000000-0000-0000-0000-0000000029a2', 'tasks.edit', true),
  ('20000000-0000-0000-0000-0000000029a2', 'events.view', true);

-- מחשבון מינימלי: 100 ₪ לשעה לעובד. 2×3×100 = 600.
insert into customer_pricing_rules (customer_id, task_type_id, config, is_active)
values ('10000000-0000-0000-0000-00000000029a',
        (select id from task_types where code = 'setup' limit 1),
        '{"model":"worker_hours","hour_rate":100,
          "hours":[{"id":"base","kind":"input","input":"hours_count","multiplier":1}],
          "workers":{"input":"worker_count"}}'::jsonb, true);

insert into events (id, customer_id, event_number, event_date, end_client_name, status_id)
values ('30000000-0000-0000-0000-00000000029a', '10000000-0000-0000-0000-00000000029a',
        'EV-29', current_date + 450, 'לקוח קצה 29',
        (select id from statuses where entity = 'event' and code = 'planned' and deleted_at is null));

-- מורידים את משימות ברירת המחדל שהטריגר יצר, ומזריעים שתי משימות משלנו.
update tasks set deleted_at = now() where event_id = '30000000-0000-0000-0000-00000000029a';

insert into tasks (id, event_id, customer_id, task_type_id, task_date,
                   onsite_start_time, hours_count, worker_count, status_id)
values
  ('61000000-0000-0000-0000-000000029001', '30000000-0000-0000-0000-00000000029a',
   '10000000-0000-0000-0000-00000000029a',
   (select id from task_types where code = 'setup' limit 1), current_date + 450,
   '09:00', 3, 2,
   (select id from statuses where entity = 'task' and code = 'draft' and deleted_at is null)),
  ('61000000-0000-0000-0000-000000029002', '30000000-0000-0000-0000-00000000029a',
   '10000000-0000-0000-0000-00000000029a',
   (select id from task_types where code = 'teardown' limit 1), current_date + 450,
   '18:00', 3, 2,
   (select id from statuses where entity = 'task' and code = 'draft' and deleted_at is null));

\echo '--- ברירת מחדל וייפר, מחיר רגיל ---'

select t_eq('משימה חדשה נולדת viper',
  (select performed_by from tasks where id = '61000000-0000-0000-0000-000000029001'), 'viper');
select t_eq('ומחירה מחושב כרגיל',
  (select price from task_pricing where task_id = '61000000-0000-0000-0000-000000029001'), 600::numeric);

\echo '--- הפיכת המשימה לארקו: מחיר 0 ---'
update tasks set performed_by = 'arko' where id = '61000000-0000-0000-0000-000000029001';

select t_eq('משימת ארקו — המחיר 0',
  (select price from task_pricing where task_id = '61000000-0000-0000-0000-000000029001'), 0::numeric);
select t_eq('והסיבה נרשמת בפירוט',
  (select breakdown ->> 'reason' from task_pricing where task_id = '61000000-0000-0000-0000-000000029001'),
  'performed_by_arko');

\echo '--- הסתרה מרכז המשרד (staff לא-admin) ---'
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000029a2', false);

select t_eq('הרכז אינו רואה את משימת ארקו',
  (select count(*)::int from tasks where id = '61000000-0000-0000-0000-000000029001'), 0);
select t_eq('אבל כן את משימת וייפר',
  (select count(*)::int from tasks where id = '61000000-0000-0000-0000-000000029002'), 1);
select t_eq('והאירוע גלוי כל עוד יש בו משימת וייפר',
  (select count(*)::int from events where id = '30000000-0000-0000-0000-00000000029a'), 1);

reset role;
select set_config('request.jwt.claim.sub', '', false);

\echo '--- כשכל המשימות ארקו — האירוע נעלם מוייפר ---'
update tasks set performed_by = 'arko' where id = '61000000-0000-0000-0000-000000029002';

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000029a2', false);
select t_eq('הרכז אינו רואה אירוע שכולו ארקו',
  (select count(*)::int from events where id = '30000000-0000-0000-0000-00000000029a'), 0);

reset role;
select set_config('request.jwt.claim.sub', '', false);

\echo '--- לקוח ארקו רואה הכול ---'
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000029a3', false);
select t_eq('הלקוח רואה את שתי משימותיו',
  (select count(*)::int from tasks where event_id = '30000000-0000-0000-0000-00000000029a'
     and deleted_at is null), 2);
select t_eq('והלקוח רואה את האירוע',
  (select count(*)::int from events where id = '30000000-0000-0000-0000-00000000029a'), 1);

reset role;
select set_config('request.jwt.claim.sub', '', false);

\echo '--- חזרה לוייפר מחזירה מחיר ---'
update tasks set performed_by = 'viper' where id = '61000000-0000-0000-0000-000000029001';
select t_eq('משימה שחזרה לוייפר מתומחרת שוב',
  (select price from task_pricing where task_id = '61000000-0000-0000-0000-000000029001'), 600::numeric);

\echo '--- הרשאת ה-RPC ---'
-- admin רשאי
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000029a1', false);
select t_expect_ok('admin קובע ביצוע ע"י',
  $$select set_task_performed_by('61000000-0000-0000-0000-000000029001', 'arko')$$);
reset role;
select set_config('request.jwt.claim.sub', '', false);

-- לקוח ארקו רשאי על המשימה שלו
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000029a3', false);
select t_expect_ok('לקוח ארקו קובע על משימתו',
  $$select set_task_performed_by('61000000-0000-0000-0000-000000029002', 'viper')$$);
select t_expect_fail('אך ערך לא חוקי נדחה',
  $$select set_task_performed_by('61000000-0000-0000-0000-000000029002', 'someone')$$);
reset role;
select set_config('request.jwt.claim.sub', '', false);

-- ===== 0135: הפרצות נסגרות והמשימה מתפנה ================================
--
-- שתי הזרועות שלא שאלו על `performed_by` הן בדיוק אלה של מי שכבר עבד על
-- המשימה, ולכן זה גם המקום שבו הבאג לא נראה: הרכז ששובץ המשיך לראות.

\echo '--- רכז ששובץ למשימה מאבד אותה במעבר, והשיבוץ יורד ---'
update tasks set performed_by = 'viper' where event_id = '30000000-0000-0000-0000-00000000029a';

insert into task_assignments (task_id, profile_id, role) values
  ('61000000-0000-0000-0000-000000029001', '20000000-0000-0000-0000-0000000029a2', 'worker');

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000029a2', false);
select t_eq('לפני המעבר הרכז רואה את המשימה ששובץ אליה',
  (select count(*)::int from tasks where id = '61000000-0000-0000-0000-000000029001'), 1);
reset role;
select set_config('request.jwt.claim.sub', '', false);

update tasks set performed_by = 'arko' where id = '61000000-0000-0000-0000-000000029001';

select t_eq('השיבוץ הפנימי נמחק במעבר (0135)',
  (select count(*)::int from task_assignments
    where task_id = '61000000-0000-0000-0000-000000029001'), 0);

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000029a2', false);
select t_eq('ואחרי המעבר אינו רואה אותה',
  (select count(*)::int from tasks where id = '61000000-0000-0000-0000-000000029001'), 0);
reset role;
select set_config('request.jwt.claim.sub', '', false);

\echo '--- והקבלן אינו רואה משימת ארקו ---'
insert into contractors (id, name) values
  ('c0000000-0000-0000-0000-00000000029a', 'קבלן 29');
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000029a4', 'c29-ctr@vl.test');
insert into profiles (id, user_id, user_kind, is_admin, full_name, contractor_id) values
  ('20000000-0000-0000-0000-0000000029a4', '00000000-0000-0000-0000-0000000029a4',
   'contractor_user', false, 'מנהל קבלן 29', 'c0000000-0000-0000-0000-00000000029a');
insert into user_permission_grants (profile_id, permission_key, allowed) values
  ('20000000-0000-0000-0000-0000000029a4', 'portal.view', true);

update tasks set performed_by = 'viper' where id = '61000000-0000-0000-0000-000000029002';
-- ‏0096: ההאצלה היא מקור האמת, ו-`tasks.contractor_id` משתקף ממנה בטריגר.
insert into task_contractor_terms (task_id, contractor_id, price)
values ('61000000-0000-0000-0000-000000029002', 'c0000000-0000-0000-0000-00000000029a', 0);

select t_eq('והשיקוף על המשימה נכתב מההאצלה',
  (select contractor_id from tasks where id = '61000000-0000-0000-0000-000000029002'),
  'c0000000-0000-0000-0000-00000000029a'::uuid);

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000029a4', false);
select t_eq('הקבלן רואה את המשימה שהואצלה לו',
  (select count(*)::int from tasks where id = '61000000-0000-0000-0000-000000029002'), 1);
reset role;
select set_config('request.jwt.claim.sub', '', false);

update tasks set performed_by = 'arko' where id = '61000000-0000-0000-0000-000000029002';

select t_eq('וההאצלה עצמה ירדה במעבר',
  (select count(*)::int from task_contractor_terms
    where task_id = '61000000-0000-0000-0000-000000029002'), 0);

-- והשיקוף יורד איתה מעצמו (0096), בלי ש-0135 תכתוב לעמודה — כתיבה ישירה
-- אליה היא בדיוק מה ש-0105 אסר.
select t_eq('והשיקוף של הקבלן ירד איתה',
  (select contractor_id from tasks where id = '61000000-0000-0000-0000-000000029002'), null::uuid);

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000029a4', false);
select t_eq('והקבלן אינו רואה עוד את משימת ארקו',
  (select count(*)::int from tasks where id = '61000000-0000-0000-0000-000000029002'), 0);
reset role;
select set_config('request.jwt.claim.sub', '', false);

\echo '--- האצלה ששולמה חוסמת את המעבר ---'
update tasks set performed_by = 'viper' where id = '61000000-0000-0000-0000-000000029002';
insert into task_contractor_terms (task_id, contractor_id, price, paid_at)
values ('61000000-0000-0000-0000-000000029002', 'c0000000-0000-0000-0000-00000000029a', 100, now())
on conflict (task_id, contractor_id) do update set paid_at = now(), price = 100;

select t_expect_fail('משימה עם האצלה ששולמה אינה עוברת לארקו', $$
  update tasks set performed_by = 'arko' where id = '61000000-0000-0000-0000-000000029002'$$);

select t_eq('והיא נשארה על וייפר',
  (select performed_by from tasks where id = '61000000-0000-0000-0000-000000029002'), 'viper');

-- ===== 0136: המעבר מדבר, ונרשם ביומן ====================================

\echo '--- התראה למנהלי המערכת ושורת יומן ---'
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000029a2', false);
select set_task_performed_by('61000000-0000-0000-0000-000000029001', 'viper');
reset role;
select set_config('request.jwt.claim.sub', '', false);

select t_eq('מנהל המערכת קיבל התראה על המעבר',
  (select count(*)::int from notifications
    where type = 'task_performed_by_changed'
      and entity_id = '61000000-0000-0000-0000-000000029001'
      and recipient_id = '20000000-0000-0000-0000-0000000029a1') >= 1, true);

-- הכיוון כתוב בכותרת, לשני הצדדים. ‏`notifications.id` הוא uuid ולא סדרה,
-- ולכן הבדיקה היא על קיום ולא על "האחרונה".
select t_eq('והכיוון כתוב בכותרת — לארקו',
  (select count(*)::int from notifications
    where type = 'task_performed_by_changed'
      and entity_id = '61000000-0000-0000-0000-000000029001'
      and title = 'המשימה עברה: וייפר ← ארקו') >= 1, true);
select t_eq('וממנה חזרה',
  (select count(*)::int from notifications
    where type = 'task_performed_by_changed'
      and entity_id = '61000000-0000-0000-0000-000000029001'
      and title = 'המשימה עברה: ארקו ← וייפר') >= 1, true);

select t_eq('והיומן רשם את השינוי בעברית',
  (select new_value from event_activity
    where event_id = '30000000-0000-0000-0000-00000000029a'
      and field_key = 'task_performed_by'
    order by id desc limit 1), 'וייפר');

-- ===== 0136: הבחירה כבר בטופס האירוע =====================================

\echo '--- setup_performed_by בהוספת האירוע ---'
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000029a1', false);
select create_event(jsonb_build_object(
  'customer_id', '10000000-0000-0000-0000-00000000029a',
  'event_number', 'EV-29B',
  'event_date', (current_date + 450)::text,
  'setup_performed_by', 'arko',
  'teardown_performed_by', 'viper')) as new_event \gset
reset role;
select set_config('request.jwt.claim.sub', '', false);

select t_eq('משימת ההקמה נולדה על ארקו',
  (select t.performed_by from tasks t join task_types tt on tt.id = t.task_type_id
    where t.event_id = :'new_event' and tt.code = 'setup' and t.deleted_at is null), 'arko');
select t_eq('ומשימת הפירוק על וייפר',
  (select t.performed_by from tasks t join task_types tt on tt.id = t.task_type_id
    where t.event_id = :'new_event' and tt.code = 'teardown' and t.deleted_at is null), 'viper');

select t_expect_fail('וערך לא חוקי בטופס נדחה', $$
  select app.apply_event_task_block(
    (select id from events where event_number = 'EV-29B' limit 1),
    'setup', '{"setup_performed_by":"someone"}'::jsonb)$$);
