\pset tuples_only on
\pset format unaligned

-- ===========================================================================
-- ‏74: משימות ניהול (0227–0230) — משימות של מנהלי המערכת: רק מנהלים, נקודות,
-- דחיות, רמת האיום, משימה חוזרת, וסיכום הבוקר שיוצא פעם אחת ביום.
--
-- הזמנים יחסיים ל-now(); המשימות של הסוויטה נמחקות בסופה.
-- ===========================================================================

-- הסיד של הבדיקות מחזיר הרשאת הרצה לכל פונקציה; מה ש-0227 סגר נסגר כאן שוב.
revoke execute on function app.mission_defcon(uuid) from anon, authenticated, public;
revoke execute on function app.mission_daily(uuid, int) from anon, authenticated, public;
revoke execute on function app.mission_streak(uuid) from anon, authenticated, public;
revoke execute on function app.missions_digest(date) from anon, authenticated, public;
revoke execute on function missions_sweep() from anon, authenticated, public;

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000074a1', 'c74-admin-b@vl.test');
insert into profiles (id, user_id, user_kind, is_admin, full_name) values
  ('20000000-0000-0000-0000-0000000074a1', '00000000-0000-0000-0000-0000000074a1',
   'staff', true, 'מנהל ב 74');

-- ===== 1. הנקודות ==========================================================

\echo '--- נקודות ---'
select t_eq('P1 בזמן — 100',
  app.mission_points(1::smallint, now(), now() - interval '1 hour', 0), 100);
select t_eq('P1 מוקדם ביום — 150',
  app.mission_points(1::smallint, now(), now() - interval '25 hours', 0), 150);
select t_eq('P2 בזמן עם שתי דחיות — 40',
  app.mission_points(2::smallint, now(), now() - interval '1 hour', 2), 40);
select t_eq('P1 באיחור של 36 שעות — רבע',
  app.mission_points(1::smallint, now() - interval '36 hours', now(), 0), 25);
select t_eq('באיחור של 4 ימים — 0, ולא פחות',
  app.mission_points(1::smallint, now() - interval '4 days', now(), 3), 0);

-- ===== 2. רק מנהלי מערכת ===================================================

\echo '--- מי נכנס ---'
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000f1', false);
select t_expect_fail('איש צוות אינו פותח את הלוח', $$ select missions_board(null) $$);
select t_expect_fail('ואינו יוצר משימה', $$
  select mission_save(null, jsonb_build_object('title', 'x', 'due_at', now() + interval '1 day')) $$);
select t_expect_fail('ואינו מריץ את הסריקה', $$ select missions_sweep() $$);
select t_eq('ואינו מחזיק את המפתח', app.has('command.view'), false);
select t_expect_fail('ואינו כותב לטבלה ישירות', $$
  insert into admin_missions (title, owner_id, due_at)
  values ('x', '20000000-0000-0000-0000-0000000000f1', now()) $$);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false);
select t_eq('מנהל מערכת מחזיק את המפתח', app.has('command.view'), true);
select t_expect_fail('אי אפשר לשייך למי שאינו מנהל', $$
  select mission_save(null, jsonb_build_object('title', 'x', 'due_at', now() + interval '1 day',
    'owner_id', '20000000-0000-0000-0000-0000000000f1')) $$);
select t_expect_fail('והפונקציות הפנימיות סגורות', $$ select app.mission_defcon(null) $$);
reset role;
select set_config('request.jwt.claim.sub', '', false);

-- ===== 3. יצירה, שיוך, דחייה ===============================================

\echo '--- יצירה ושיוך ---'
create temp table m74 (k text primary key, id uuid);
grant all on m74 to authenticated;

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false);
insert into m74 values ('cams', mission_save(null, jsonb_build_object(
  'title', 'התקנת מצלמות במחסן', 'due_at', now() + interval '3 days', 'priority', 1,
  'owner_id', '20000000-0000-0000-0000-0000000074a1',
  'steps', jsonb_build_array(jsonb_build_object('title', 'להזמין מצלמות'),
                             jsonb_build_object('title', 'להתקין')))));
reset role;
select set_config('request.jwt.claim.sub', '', false);

select t_eq('המנהל השני קיבל התראה על השיוך',
  (select count(*)::int from notifications
    where recipient_id = '20000000-0000-0000-0000-0000000074a1' and type = 'mission_assigned'), 1);
select t_eq('והקישור פותח את המשימה',
  (select link from notifications
    where recipient_id = '20000000-0000-0000-0000-0000000074a1' and type = 'mission_assigned'),
  '/command?m=' || (select id from m74 where k = 'cams'));
select t_eq('שני צעדים', (select count(*)::int from admin_mission_steps
  where mission_id = (select id from m74 where k = 'cams') and deleted_at is null), 2);

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000074a1', false);
select t_expect_ok('נודניק של יום', $$ select mission_snooze((select id from m74 where k = 'cams'), 1440) $$);
select t_eq('הלוח של "שלי" רואה אותה',
  (select jsonb_array_length(missions_board('20000000-0000-0000-0000-0000000074a1') -> 'missions')), 1);
select t_eq('ונספרה דחייה אחת',
  (select (missions_board('20000000-0000-0000-0000-0000000074a1') -> 'missions' -> 0 ->> 'postpone_count')::int), 1);
select t_expect_ok('עריכה שמקדימה את היעד ומורידה צעד', $$
  select mission_save((select id from m74 where k = 'cams'), jsonb_build_object(
    'title', 'התקנת מצלמות במחסן', 'due_at', now() + interval '2 days', 'priority', 1,
    'owner_id', '20000000-0000-0000-0000-0000000074a1',
    'steps', jsonb_build_array(jsonb_build_object(
      'id', (select id from admin_mission_steps where mission_id = (select id from m74 where k = 'cams')
              and title = 'להזמין מצלמות'), 'title', 'להזמין מצלמות', 'done', true)))) $$);
select t_eq('הקדמה אינה דחייה',
  (select postpone_count from admin_missions where id = (select id from m74 where k = 'cams')), 1);
select t_eq('נשאר צעד אחד, מסומן',
  (select string_agg(title || ':' || (done_at is not null)::text, ',') from admin_mission_steps
    where mission_id = (select id from m74 where k = 'cams')), 'להזמין מצלמות:true');
reset role;
select set_config('request.jwt.claim.sub', '', false);

-- ===== 4. רמת האיום ========================================================

\echo '--- DEFCON ---'
select t_eq('יעד בעוד יומיים — שליטה מלאה',
  app.mission_defcon('20000000-0000-0000-0000-0000000074a1'), 5);

insert into admin_missions (id, title, owner_id, due_at, created_at) values
  ('74000000-0000-0000-0000-000000000001', 'באיחור קטן', '20000000-0000-0000-0000-0000000074a1',
   now() - interval '2 hours', now() - interval '3 days');
select t_eq('משימה אחת באיחור — 3', app.mission_defcon('20000000-0000-0000-0000-0000000074a1'), 3);

insert into admin_missions (id, title, owner_id, due_at, created_at) values
  ('74000000-0000-0000-0000-000000000002', 'באיחור ישן', '20000000-0000-0000-0000-0000000074a1',
   now() - interval '8 days', now() - interval '10 days');
select t_eq('איחור של יותר משבוע — 1', app.mission_defcon('20000000-0000-0000-0000-0000000074a1'), 1);
select t_eq('ושל המנהל הראשון — לא נוגע',
  app.mission_defcon('20000000-0000-0000-0000-000000000001'), 5);

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000074a1', false);
select t_eq('הלוח סופר שתיים באיחור',
  (missions_board('20000000-0000-0000-0000-0000000074a1') ->> 'overdue')::int, 2);
select t_eq('והחוב הוא לפחות 8 ימים ושעתיים',
  (missions_board('20000000-0000-0000-0000-0000000074a1') ->> 'debt_seconds')::bigint >= 8 * 86400 + 7200, true);
select t_eq('הרצף נשבר היום', (missions_stats('20000000-0000-0000-0000-0000000074a1', 30) ->> 'streak')::int, 0);
reset role;
select set_config('request.jwt.claim.sub', '', false);

-- ===== 5. סיכום הבוקר, פעם ביום (0229) ====================================

\echo '--- סיכום הבוקר ---'
insert into admin_missions (id, title, owner_id, due_at, created_at) values
  ('74000000-0000-0000-0000-000000000003', 'עוד היום', '20000000-0000-0000-0000-0000000074a1',
   least(now() + interval '30 minutes', app.mission_day_end(app.mission_today()) - interval '1 second'),
   now() - interval '2 days');
select t_eq('סיכום אחד — רק למנהל שיש לו מה לסגור',
  app.missions_digest(app.mission_today()), 1);
select t_eq('הכותרת סופרת באיחור ולהיום',
  (select title from notifications
    where recipient_id = '20000000-0000-0000-0000-0000000074a1' and type = 'mission_daily_digest'),
  '🚨 2 באיחור · 1 להיום');
select t_eq('והוא פותח את משימות הניהול',
  (select link from notifications
    where recipient_id = '20000000-0000-0000-0000-0000000074a1' and type = 'mission_daily_digest'),
  '/command');
select t_eq('הרצה שנייה באותו יום אינה שולחת', app.missions_digest(app.mission_today()), 0);
select missions_sweep() is not null;
select t_eq('וגם התזמון אינו שולח שוב',
  (select count(*)::int from notifications
    where recipient_id = '20000000-0000-0000-0000-0000000074a1' and type = 'mission_daily_digest'), 1);
select t_eq('אין יותר התראה לכל משימה',
  (select count(*)::int from notifications
    where recipient_id = '20000000-0000-0000-0000-0000000074a1'
      and type in ('mission_overdue', 'mission_due_soon')), 0);
select t_eq('ושני הסוגים האלה פרשו',
  (select count(*)::int from notification_types
    where key in ('mission_overdue', 'mission_due_soon') and not is_active), 2);

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false);
select t_expect_fail('גם מנהל מערכת אינו מריץ את הסריקה מהדפדפן', $$ select missions_sweep() $$);
select t_expect_fail('ולא את הסיכום', $$ select app.missions_digest(current_date) $$);
reset role;
select set_config('request.jwt.claim.sub', '', false);

-- ===== 6. סיום וחזרה ===============================================

\echo '--- סיום ---'
update admin_missions set recurrence = 'weekly' where id = '74000000-0000-0000-0000-000000000002';

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false);
insert into m74 values ('done', null);
select t_eq('סיום מוקדם של P1 שנדחה פעם — 150 פחות 10',
  (mission_complete((select id from m74 where k = 'cams')) ->> 'points')::int, 140);
select t_eq('המשימה בוצעה בידי המנהל הראשון, הנקודות למנהל השני',
  (missions_stats('20000000-0000-0000-0000-0000000074a1', 7) ->> 'xp_total')::int, 140);
select t_eq('ובלי הישגים בסטטיסטיקה (0229)',
  missions_stats('20000000-0000-0000-0000-0000000074a1', 7) ? 'achievements', false);
select t_expect_fail('אי אפשר לסיים פעמיים', $$ select mission_complete((select id from m74 where k = 'cams')) $$);

update m74 set id = (mission_complete('74000000-0000-0000-0000-000000000002') ->> 'next_id')::uuid where k = 'done';
select t_eq('משימה חוזרת באיחור — 0 נקודות',
  (select points from admin_missions where id = '74000000-0000-0000-0000-000000000002'), 0);
select t_eq('והמופע הבא נולד בעתיד, שבוע אחרי שבוע',
  (select due_at > now() and due_at <= now() + interval '7 days'
          and extract(epoch from due_at - (now() - interval '8 days'))::bigint % (7 * 86400) < 2
     from admin_missions where id = (select id from m74 where k = 'done')), true);

select t_expect_ok('ביטול סיום', $$ select mission_reopen((select id from m74 where k = 'cams')) $$);
select t_eq('והנקודות חזרו לאפס',
  (missions_stats('20000000-0000-0000-0000-0000000074a1', 7) ->> 'xp_total')::int, 0);
select t_expect_ok('הסרה', $$ select mission_remove('74000000-0000-0000-0000-000000000001') $$);
select t_rows('ומשימה שהוסרה אינה נראית',
  $$ select 1 from admin_missions where id = '74000000-0000-0000-0000-000000000001' $$, 0);
reset role;
select set_config('request.jwt.claim.sub', '', false);

select t_eq('הסרה רכה — השורה עדיין במסד',
  (select deleted_at is not null from admin_missions where id = '74000000-0000-0000-0000-000000000001'), true);

-- ===== 7. 0228: מופע חוזר אחד, ומשימה שבוצעה קפואה =======================

\echo '--- 0228 ---'
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false);
select t_expect_ok('ביטול הסיום של המשימה החוזרת', $$ select mission_reopen('74000000-0000-0000-0000-000000000002') $$);
select t_eq('סגירה שנייה אינה מולידה מופע נוסף',
  (mission_complete('74000000-0000-0000-0000-000000000002') ->> 'next_id'), null);
select t_eq('יש בדיוק מופע חי אחד אחריה',
  (select count(*)::int from admin_missions
    where previous_id = '74000000-0000-0000-0000-000000000002' and deleted_at is null), 1);

select t_expect_ok('סגירה, ואז עריכה שמנסה להעביר ולהזיז', $$
  select mission_complete((select id from m74 where k = 'cams')) $$);
select t_expect_ok('העריכה עצמה עוברת', $$
  select mission_save((select id from m74 where k = 'cams'), jsonb_build_object(
    'title', 'מצלמות — הותקנו', 'due_at', now() + interval '30 days', 'priority', 4,
    'owner_id', '20000000-0000-0000-0000-000000000001')) $$);
select t_eq('השם השתנה; הבעלים, היעד והעדיפות — לא',
  (select title || '|' || (owner_id = '20000000-0000-0000-0000-0000000074a1')::text || '|'
          || (due_at < now() + interval '3 days')::text || '|' || priority
     from admin_missions where id = (select id from m74 where k = 'cams')),
  'מצלמות — הותקנו|true|true|1');
reset role;
select set_config('request.jwt.claim.sub', '', false);

-- ===== ניקוי ===============================================================

delete from notifications where recipient_id = '20000000-0000-0000-0000-0000000074a1';
delete from admin_missions where owner_id = '20000000-0000-0000-0000-0000000074a1';
update profiles set is_active = false where id = '20000000-0000-0000-0000-0000000074a1';
