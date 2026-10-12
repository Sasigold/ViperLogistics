\pset tuples_only on
\pset format unaligned

-- ===========================================================================
-- ‏66: הבעלים בוחר אילו דפים כל אחד רואה (0215).
--
-- שכבת "דפים" נפרדת מההרשאות: היא אומרת מה מוצג בתפריט, ושלוש רמות קובעות
-- אותה — מנהלי מערכת כקבוצה, תפקיד, ומשתמש. כל בדיקה רצה בזהות הדמות.
--
--   66a1 מנהל מערכת            66a2 מנהל מערכת נוסף
--   66a3 עובד (תפקיד "עובד")    66a4 עובד וראש צוות
--   66a5 משרד שעורך תפקידים ומשתמשים (settings.permissions + users.*)
--   66b1 מנהל אצל לקוח 66 שעורך הרשאות לאנשי הלקוח שלו
--   66b2 צופה אצל לקוח 66       66b3 צופה אצל לקוח אחר
--   66c1 מנהל קבלן
-- ===========================================================================

insert into auth.users (id, email)
select ('00000000-0000-0000-0000-0000000066' || s)::uuid, 'p66-' || s || '@vl.test'
  from unnest(array['a1','a2','a3','a4','a5','b1','b2','b3','c1']) s;

insert into customers (id, name) values
  ('10000000-0000-0000-0000-0000000066a0', 'לקוח 66'),
  ('10000000-0000-0000-0000-0000000066b0', 'לקוח אחר 66');

insert into contractors (id, name) values
  ('40000000-0000-0000-0000-0000000066c1', 'קבלן 66');

insert into profiles (id, user_id, user_kind, is_admin, full_name, customer_id, contractor_id) values
  ('20000000-0000-0000-0000-0000000066a1', '00000000-0000-0000-0000-0000000066a1', 'staff', true,  'מנהל 66', null, null),
  ('20000000-0000-0000-0000-0000000066a2', '00000000-0000-0000-0000-0000000066a2', 'staff', true,  'מנהל נוסף 66', null, null),
  ('20000000-0000-0000-0000-0000000066a3', '00000000-0000-0000-0000-0000000066a3', 'staff', false, 'עובד 66', null, null),
  ('20000000-0000-0000-0000-0000000066a4', '00000000-0000-0000-0000-0000000066a4', 'staff', false, 'ראש צוות 66', null, null),
  ('20000000-0000-0000-0000-0000000066a5', '00000000-0000-0000-0000-0000000066a5', 'staff', false, 'משרד 66', null, null),
  ('20000000-0000-0000-0000-0000000066b1', '00000000-0000-0000-0000-0000000066b1', 'customer_user', false, 'מנהל לקוח 66', '10000000-0000-0000-0000-0000000066a0', null),
  ('20000000-0000-0000-0000-0000000066b2', '00000000-0000-0000-0000-0000000066b2', 'customer_user', false, 'צופה לקוח 66', '10000000-0000-0000-0000-0000000066a0', null),
  ('20000000-0000-0000-0000-0000000066b3', '00000000-0000-0000-0000-0000000066b3', 'customer_user', false, 'צופה לקוח אחר 66', '10000000-0000-0000-0000-0000000066b0', null),
  ('20000000-0000-0000-0000-0000000066c1', '00000000-0000-0000-0000-0000000066c1', 'contractor_user', false, 'מנהל קבלן 66', null, '40000000-0000-0000-0000-0000000066c1');

insert into profile_roles (profile_id, role_id)
select v.p::uuid, r.id
  from (values
    ('20000000-0000-0000-0000-0000000066a3', 'worker'),
    ('20000000-0000-0000-0000-0000000066a4', 'worker'),
    ('20000000-0000-0000-0000-0000000066a4', 'team_lead'),
    ('20000000-0000-0000-0000-0000000066a5', 'dispatcher'),
    ('20000000-0000-0000-0000-0000000066b1', 'customer_manager'),
    ('20000000-0000-0000-0000-0000000066b2', 'customer_viewer'),
    ('20000000-0000-0000-0000-0000000066b3', 'customer_viewer'),
    ('20000000-0000-0000-0000-0000000066c1', 'contractor_manager')) v(p, k)
  join permission_roles r on r.key = v.k;

insert into user_permission_grants (profile_id, permission_key, allowed) values
  ('20000000-0000-0000-0000-0000000066a5', 'settings.permissions', true),
  ('20000000-0000-0000-0000-0000000066a5', 'users.manage_permissions', true),
  ('20000000-0000-0000-0000-0000000066a5', 'users.edit', true),
  ('20000000-0000-0000-0000-0000000066b1', 'users.manage_permissions', true),
  ('20000000-0000-0000-0000-0000000066b1', 'users.view', true)
on conflict (profile_id, permission_key) do update set allowed = excluded.allowed;

create or replace function t66_as(p text) returns void language sql as $$
  select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000066' || p, false);
$$;
grant execute on function t66_as(text) to authenticated;

-- מה ש-get_my_permissions מחזירה לקורא, בשורה אחת
create or replace function t66_hidden() returns text language sql stable as $$
  select coalesce(string_agg(x, ',' order by x), '-')
    from jsonb_array_elements_text(get_my_permissions() -> 'hidden_pages') x
$$;
grant execute on function t66_hidden() to authenticated;

create or replace function t66_role(p_key text) returns uuid language sql stable as $$
  select id from permission_roles where key = p_key and deleted_at is null limit 1
$$;
grant execute on function t66_role(text) to authenticated;

-- ===== 1. בלי הגדרה — שום דף אינו מוסתר =================================

\echo '--- 1. בלי הגדרה — שום דף אינו מוסתר ---'
set role authenticated;

select t66_as('a1');
select t_eq('מנהל מערכת: אין דף מוסתר', t66_hidden(), '-');
select t66_as('a3');
select t_eq('עובד: אין דף מוסתר', t66_hidden(), '-');
select t66_as('b2');
select t_eq('משתמש לקוח: השדה מגיע, ושום דף אינו מוסתר',
  jsonb_typeof(get_my_permissions() -> 'hidden_pages'), 'array');
select t66_as('c1');
select t_eq('קבלן: אותו דבר', t66_hidden(), '-');

-- ===== 2. מנהלי מערכת כקבוצה ==============================================

\echo '--- 2. מנהלי מערכת כקבוצה ---'
select t66_as('a1');
select t_expect_ok('מנהל מערכת מסתיר ממנהלי המערכת את "משמרות"',
  $$select page_visibility_set('my_schedule', false, p_admins => true)$$);
select t_expect_ok('ואת "כספים ותשלומים" של הקבלן',
  $$select page_visibility_set('portal', false, p_admins => true)$$);
select t_eq('ושניהם נעלמים לו', t66_hidden(), 'my_schedule,portal');
select t_expect_ok('קביעה חוזרת אינה נכשלת',
  $$select page_visibility_set('portal', false, p_admins => true)$$);
select t66_as('a2');
select t_eq('ולכל מנהל מערכת אחר', t66_hidden(), 'my_schedule,portal');
select t66_as('a3');
select t_eq('ולא לעובד — הוא אינו בקבוצה', t66_hidden(), '-');

select t66_as('a1');
select t_expect_fail('את ההגדרות אי אפשר להסתיר ממנהלי המערכת — משם מחזירים דפים',
  $$select page_visibility_set('settings', false, p_admins => true)$$);
select t_expect_fail('וגם לא ממנהל מערכת בודד',
  $$select page_visibility_set('settings', false, p_profile_id => '20000000-0000-0000-0000-0000000066a2')$$);
reset role;
insert into page_visibility (page_key, visible) values ('settings', false);
set role authenticated;
select t66_as('a2');
select t_eq('וגם שורה שנכתבה ישירות במסד אינה מסתירה אותן', t66_hidden(), 'my_schedule,portal');
reset role;
delete from page_visibility where page_key = 'settings' and role_id is null and profile_id is null;
select t_eq('הקבוצה מחזיקה שורה אחת לכל דף', (select count(*)::int from page_visibility
  where role_id is null and profile_id is null and page_key = 'portal'), 1);
set role authenticated;

-- ===== 3. שורה אישית גוברת על הקבוצה ======================================

\echo '--- 3. שורה אישית גוברת ---'
select t66_as('a1');
select t_expect_ok('מנהל מערכת מחזיר למנהל אחר את "משמרות" אישית',
  $$select page_visibility_set('my_schedule', true, p_profile_id => '20000000-0000-0000-0000-0000000066a2')$$);
select t66_as('a2');
select t_eq('ההגדרה האישית גוברת על הקבוצה', t66_hidden(), 'portal');
select t66_as('a1');
select t_eq('ושאר המנהלים כפי שהיו', t66_hidden(), 'my_schedule,portal');

-- ===== 4. תפקידים ==========================================================

\echo '--- 4. תפקידים ---'
select t_expect_ok('מסתירים את לוח השנה מתפקיד "עובד"',
  $$select page_visibility_set('calendar', false, p_role_id => t66_role('worker'))$$);
select t66_as('a3');
select t_eq('עובד — מוסתר', t66_hidden(), 'calendar');
select t66_as('a4');
select t_eq('עובד וראש צוות — מוסתר: לתפקיד ראש הצוות אין הגדרה', t66_hidden(), 'calendar');
select t66_as('a1');
select t_expect_ok('"מוצג" מפורש בתפקיד "ראש צוות"',
  $$select page_visibility_set('calendar', true, p_role_id => t66_role('team_lead'))$$);
select t66_as('a4');
select t_eq('"מוצג" מפורש בתפקיד אחד גובר על "מוסתר" בתפקיד אחר', t66_hidden(), '-');
select t66_as('a3');
select t_eq('ומי שאינו ראש צוות — עדיין מוסתר', t66_hidden(), 'calendar');

-- מנהל מערכת שמחזיק גם תפקיד: התפקיד אינו מחזיר לו דף שהוסתר מהמנהלים,
-- אלא אם הוא מציג אותו במפורש. (התפקידים מוצמדים בזהות מנהל מערכת:
-- הטריגר של profile_roles שואל את מי שמחובר אם הוא רשאי לנהל את האדם.)
select t66_as('a1');
reset role;
insert into profile_roles (profile_id, role_id)
values ('20000000-0000-0000-0000-0000000066a1', t66_role('worker'));
set role authenticated;
select t66_as('a1');
select t_eq('מנהל שהוא גם עובד — "משמרות" נשאר מוסתר', t66_hidden(), 'calendar,my_schedule,portal');
select t_expect_ok('"מוצג" מפורש למשמרות בתפקיד "עובד"',
  $$select page_visibility_set('my_schedule', true, p_role_id => t66_role('worker'))$$);
select t_eq('ועכשיו המנהל שהוא גם עובד רואה אותו', t66_hidden(), 'calendar,portal');
select t66_as('a2');
select t_eq('ומנהל שאינו עובד — כפי שהיה (האישי שלו מציג)', t66_hidden(), 'portal');
select t66_as('a1');
select t_expect_ok('ומחזירים את התפקיד לירושה',
  $$select page_visibility_set('my_schedule', null, p_role_id => t66_role('worker'))$$);
reset role;
delete from profile_roles
 where profile_id = '20000000-0000-0000-0000-0000000066a1' and role_id = t66_role('worker');
set role authenticated;

-- תפקיד של סוג משתמש אחר אינו חל (0067), ולכן גם הדפים שלו לא.
reset role;
insert into profile_roles (profile_id, role_id)
values ('20000000-0000-0000-0000-0000000066a3', t66_role('customer_warehouse'));
set role authenticated;
select t66_as('a1');
select t_expect_ok('מסתירים דוחות מתפקיד של לקוח',
  $$select page_visibility_set('reports', false, p_role_id => t66_role('customer_warehouse'))$$);
select t66_as('a3');
select t_eq('ועובד שהתפקיד הזה הוצמד לו בטעות אינו מושפע', t66_hidden(), 'calendar');
select t66_as('a1');
reset role;
delete from profile_roles
 where profile_id = '20000000-0000-0000-0000-0000000066a3' and role_id = t66_role('customer_warehouse');
set role authenticated;

-- ===== 5. משתמש בודד, וירושה ==============================================

\echo '--- 5. משתמש בודד, וירושה ---'
select t66_as('a1');
select t_expect_ok('הצגה אישית של לוח השנה לעובד',
  $$select page_visibility_set('calendar', true, p_profile_id => '20000000-0000-0000-0000-0000000066a3')$$);
select t66_as('a3');
select t_eq('האישי גובר על התפקיד', t66_hidden(), '-');
select t66_as('a1');
select t_expect_ok('הסתרה אישית של הלו״ז לראש הצוות',
  $$select page_visibility_set('board', false, p_profile_id => '20000000-0000-0000-0000-0000000066a4')$$);
select t66_as('a4');
select t_eq('הסתרה אישית', t66_hidden(), 'board');
select t66_as('a1');
select t_expect_ok('"ירושה" מוחקת את השורה האישית',
  $$select page_visibility_set('calendar', null, p_profile_id => '20000000-0000-0000-0000-0000000066a3')$$);
select t66_as('a3');
select t_eq('ועם הירושה חוזרת ההכרעה של התפקיד', t66_hidden(), 'calendar');
reset role;
select t_eq('ואין שורה אישית שנשארה', (select count(*)::int from page_visibility
  where profile_id = '20000000-0000-0000-0000-0000000066a3'), 0);
select t_eq('ולתפקיד שורה אחת לדף', (select count(*)::int from page_visibility
  where role_id = t66_role('worker') and page_key = 'calendar'), 1);
set role authenticated;

-- ===== 6. מי רשאי לקבוע =====================================================

\echo '--- 6. מי רשאי לקבוע ---'
select t66_as('a3');
select t_expect_fail('עובד אינו קובע דפים לתפקיד',
  $$select page_visibility_set('events', false, p_role_id => t66_role('worker'))$$);
select t_expect_fail('ולא למנהלי המערכת',
  $$select page_visibility_set('events', false, p_admins => true)$$);
select t_expect_fail('ולא לעצמו',
  $$select page_visibility_set('events', false, p_profile_id => '20000000-0000-0000-0000-0000000066a3')$$);
select t_expect_fail('ולא ישירות בטבלה',
  $$insert into page_visibility (page_key, profile_id, visible)
    values ('events', '20000000-0000-0000-0000-0000000066a3', true)$$);

select t66_as('a5');
select t_expect_ok('מי שעורך תפקידים קובע דפים לתפקיד',
  $$select page_visibility_set('events', false, p_role_id => t66_role('driver'))$$);
select t_expect_fail('אבל לא למנהלי המערכת',
  $$select page_visibility_set('events', false, p_admins => true)$$);
select t_expect_fail('ולא למנהל מערכת בודד',
  $$select page_visibility_set('events', false, p_profile_id => '20000000-0000-0000-0000-0000000066a1')$$);
select t_expect_ok('ולעובד שהוא רשאי לנהל — כן',
  $$select page_visibility_set('events', false, p_profile_id => '20000000-0000-0000-0000-0000000066a3')$$);
select t_rows('וגם הוא אינו משנה את הטבלה ישירות',
  $$update page_visibility set visible = true where profile_id = '20000000-0000-0000-0000-0000000066a3'$$, 0);
select t_rows('ואינו מוחק ממנה ישירות',
  $$delete from page_visibility where profile_id = '20000000-0000-0000-0000-0000000066a3'$$, 0);
select t66_as('a3');
select t_eq('והעובד רואה את מה שנקבע לו', t66_hidden(), 'calendar,events');

select t66_as('b1');
select t_expect_ok('מנהל אצל לקוח קובע דפים לאנשי הלקוח שלו',
  $$select page_visibility_set('calendar', false, p_profile_id => '20000000-0000-0000-0000-0000000066b2')$$);
select t_expect_fail('ולא לאנשי לקוח אחר',
  $$select page_visibility_set('calendar', false, p_profile_id => '20000000-0000-0000-0000-0000000066b3')$$);
select t_expect_fail('ולא לאנשי הצוות',
  $$select page_visibility_set('calendar', false, p_profile_id => '20000000-0000-0000-0000-0000000066a3')$$);
select t_expect_fail('ולא לתפקיד',
  $$select page_visibility_set('calendar', false, p_role_id => t66_role('customer_viewer'))$$);
select t_expect_fail('ולא למנהלי המערכת',
  $$select page_visibility_set('calendar', false, p_admins => true)$$);
select t66_as('b2');
select t_eq('הצופה רואה את מה שנקבע לו', t66_hidden(), 'calendar');
select t66_as('b3');
select t_eq('והצופה אצל הלקוח האחר — לא', t66_hidden(), '-');

-- ===== 7. קלט שגוי ==========================================================

\echo '--- 7. קלט שגוי ---'
select t66_as('a1');
select t_expect_fail('מזהה דף לא תקין',
  $$select page_visibility_set('Bad Key', false, p_admins => true)$$);
select t_expect_fail('שני יעדים בבת אחת',
  $$select page_visibility_set('events', false, p_admins => true, p_role_id => t66_role('worker'))$$);
select t_expect_fail('בלי יעד',
  $$select page_visibility_set('events', false)$$);
select t_expect_fail('תפקיד שאינו קיים',
  $$select page_visibility_set('events', false, p_role_id => '99999999-9999-9999-9999-999999999966')$$);
select t_expect_fail('משתמש שאינו קיים',
  $$select page_visibility_set('events', false, p_profile_id => '99999999-9999-9999-9999-999999999966')$$);

-- ===== 8. מי קורא ===========================================================

\echo '--- 8. מי קורא את ההגדרות ---'
select t66_as('b1');
select t_eq('מנהל הלקוח קורא את השורות של אנשי הלקוח שלו', (select count(*)::int from page_visibility
  where profile_id = '20000000-0000-0000-0000-0000000066b2'), 1);
select t_eq('ולא את של אנשי הצוות', (select count(*)::int from page_visibility
  where profile_id in ('20000000-0000-0000-0000-0000000066a3', '20000000-0000-0000-0000-0000000066a4')), 0);
select t_eq('ולא את של מנהלי המערכת', (select count(*)::int from page_visibility
  where role_id is null and profile_id is null), 0);
select t66_as('b3');
select t_eq('צופה אצל לקוח אחר אינו קורא את השורות של הלקוח', (select count(*)::int from page_visibility
  where profile_id = '20000000-0000-0000-0000-0000000066b2'), 0);
select t66_as('a3');
select t_eq('עובד קורא את השורה האישית שלו', (select count(*)::int from page_visibility
  where profile_id = '20000000-0000-0000-0000-0000000066a3'), 1);
select t_eq('ולא את של עמיתו', (select count(*)::int from page_visibility
  where profile_id = '20000000-0000-0000-0000-0000000066a4'), 0);
select t_eq('ואת שורות התפקיד שלו', (select count(*)::int from page_visibility
  where role_id = t66_role('worker')), 1);
select t_eq('ולא של תפקיד שאינו שלו', (select count(*)::int from page_visibility
  where role_id = t66_role('driver')), 0);
select t66_as('a5');
select t_eq('מי שעורך תפקידים ומשתמשים קורא את הכול', (select count(*)::int > 3 from page_visibility
  where page_key in ('my_schedule', 'portal', 'calendar', 'events', 'board')), true);

reset role;
select t_eq('כל שינוי נרשם ביומן', (select count(*)::int > 0 from audit_log
  where table_name = 'page_visibility'), true);
select set_config('request.jwt.claim.sub', '', false);
