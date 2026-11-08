\pset tuples_only on
\pset format unaligned

-- ===========================================================================
-- ‏81: קוד הרכב, הביטוח ורישיון הנהג (0240) — עמודות הביטוח והקוד על הרכב,
-- ‏RLS על driver_licenses, השער של הדלי לנתיב 'drivers/<profile>/...',
-- ותאריכים בלתי סבירים (שנה בת 5 ספרות) נדחים במסמכים וברישיונות.
--
-- נתונים: פרופילים, רכב ורישיון משלה (קידומת ...0081..).
-- ===========================================================================

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000081a1', 'fleet81-manager@vl.test'),
  ('00000000-0000-0000-0000-0000000081a2', 'fleet81-viewer@vl.test'),
  ('00000000-0000-0000-0000-0000000081a3', 'fleet81-none@vl.test'),
  ('00000000-0000-0000-0000-0000000081a4', 'fleet81-driver@vl.test');

insert into profiles (id, user_id, user_kind, is_admin, full_name) values
  ('20000000-0000-0000-0000-0000000081a1', '00000000-0000-0000-0000-0000000081a1', 'staff', false, 'מנהל צי 81'),
  ('20000000-0000-0000-0000-0000000081a2', '00000000-0000-0000-0000-0000000081a2', 'staff', false, 'צופה צי 81'),
  ('20000000-0000-0000-0000-0000000081a3', '00000000-0000-0000-0000-0000000081a3', 'staff', false, 'בלי צי 81'),
  ('20000000-0000-0000-0000-0000000081a4', '00000000-0000-0000-0000-0000000081a4', 'staff', false, 'נהג 81');

insert into user_permission_grants (profile_id, permission_key, allowed) values
  ('20000000-0000-0000-0000-0000000081a1', 'fleet.view', true),
  ('20000000-0000-0000-0000-0000000081a1', 'fleet.edit', true),
  ('20000000-0000-0000-0000-0000000081a1', 'fleet.create', true),
  ('20000000-0000-0000-0000-0000000081a1', 'fleet.docs_view', true),
  ('20000000-0000-0000-0000-0000000081a1', 'fleet.docs_manage', true),
  ('20000000-0000-0000-0000-0000000081a1', 'fleet.drivers_manage', true),
  ('20000000-0000-0000-0000-0000000081a2', 'fleet.view', true),
  ('20000000-0000-0000-0000-0000000081a2', 'fleet.docs_view', true),
  ('20000000-0000-0000-0000-0000000081a2', 'fleet.edit', false),
  ('20000000-0000-0000-0000-0000000081a2', 'fleet.drivers_manage', false),
  ('20000000-0000-0000-0000-0000000081a3', 'fleet.view', false),
  ('20000000-0000-0000-0000-0000000081a3', 'fleet.docs_view', false);

\echo ''
\echo '=== 81: קוד הרכב, ביטוח ורישיון נהג ==='

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000081a1', false);

insert into vehicles (id, plate_number, name, category) values
  ('40000000-0000-0000-0000-000000000081', '81-081-81', 'איסוזו קצרה', 'truck');

\echo '--- קוד וביטוח ---'

select t_rows('מנהל צי שומר קוד ופרטי ביטוח',
  $$update vehicles set vehicle_code = '1234', insurance_company = 'הראל',
       insurance_coverage = 'comprehensive', insurance_min_driver_age = 24,
       insurance_min_license_years = 2
     where id = '40000000-0000-0000-0000-000000000081'$$, 1);

select t_expect_fail('סוג כיסוי לא מוכר נדחה', $$
  update vehicles set insurance_coverage = 'whatever' where id = '40000000-0000-0000-0000-000000000081'$$);
select t_expect_fail('גיל מינימלי לא סביר נדחה', $$
  update vehicles set insurance_min_driver_age = 5 where id = '40000000-0000-0000-0000-000000000081'$$);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000081a2', false);
select t_eq('צופה רואה את הקוד',
  (select vehicle_code from vehicles where id = '40000000-0000-0000-0000-000000000081'), '1234');
select t_rows('אך אינו משנה את הביטוח',
  $$update vehicles set insurance_min_driver_age = 18 where id = '40000000-0000-0000-0000-000000000081'$$, 0);

\echo '--- תאריכים סבירים ---'

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000081a1', false);

/* זו הקריסה שדווחה: שנה בת 5 ספרות נשמרה, והלקוח נפל עליה. */
select t_expect_fail('מסמך עם שנה 20255 נדחה', $$
  insert into vehicle_documents (vehicle_id, kind_id, expires_at)
  select '40000000-0000-0000-0000-000000000081', k.id, date '20255-01-01'
    from vehicle_document_kinds k where k.deleted_at is null limit 1$$);
select t_expect_ok('ומסמך עם תאריך רגיל עובר', $$
  insert into vehicle_documents (vehicle_id, kind_id, expires_at)
  select '40000000-0000-0000-0000-000000000081', k.id, current_date + 1200
    from vehicle_document_kinds k where k.deleted_at is null limit 1$$);

\echo '--- רישיון הנהג ---'

select t_expect_ok('מנהל צי שומר רישיון לנהג', $$
  insert into driver_licenses (id, profile_id, license_number, license_classes,
                               first_issued_at, expires_at, birth_date, storage_path)
  values ('70000000-0000-0000-0000-000000000081', '20000000-0000-0000-0000-0000000081a4',
          '1234567', 'B, C1', date '2015-03-01', current_date + 1500, date '1995-06-01',
          'drivers/20000000-0000-0000-0000-0000000081a4/x.jpg')$$);

select t_expect_fail('רישיון חי שני לאותו נהג נדחה', $$
  insert into driver_licenses (profile_id) values ('20000000-0000-0000-0000-0000000081a4')$$);
select t_expect_fail('תאריך לידה עם שנה בת 5 ספרות נדחה', $$
  update driver_licenses set birth_date = date '19955-06-01'
   where id = '70000000-0000-0000-0000-000000000081'$$);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000081a2', false);
select t_eq('צופה (fleet.docs_view) רואה את הרישיון',
  (select license_number from driver_licenses where id = '70000000-0000-0000-0000-000000000081'), '1234567');
select t_rows('אך אינו עורך אותו',
  $$update driver_licenses set note = 'x' where id = '70000000-0000-0000-0000-000000000081'$$, 0);
select t_expect_fail('ואינו יוצר רישיון', $$
  insert into driver_licenses (profile_id) values ('20000000-0000-0000-0000-0000000081a3')$$);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000081a3', false);
select t_eq('מי שאין לו מפתח צי אינו רואה רישיון',
  (select count(*)::int from driver_licenses where id = '70000000-0000-0000-0000-000000000081'), 0);

\echo '--- השער של הדלי ---'

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000081a1', false);
select t_eq('מנהל צי כותב קובץ רישיון',
  app.may_touch_vehicle_doc('drivers/20000000-0000-0000-0000-0000000081a4/a.jpg', true), true);
select t_eq('נתיב רישיון בלי מזהה תקין סגור',
  app.may_touch_vehicle_doc('drivers/not-a-uuid/a.jpg', false), false);
select t_eq('נתיב רישיון של פרופיל שאינו קיים סגור',
  app.may_touch_vehicle_doc('drivers/20000000-0000-0000-0000-0000000081ff/a.jpg', false), false);
select t_eq('ונתיב הרכב עדיין עובד כמו קודם',
  app.may_touch_vehicle_doc('40000000-0000-0000-0000-000000000081/a.pdf', true), true);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000081a2', false);
select t_eq('צופה קורא קובץ רישיון',
  app.may_touch_vehicle_doc('drivers/20000000-0000-0000-0000-0000000081a4/a.jpg', false), true);
select t_eq('אך אינו כותב אותו',
  app.may_touch_vehicle_doc('drivers/20000000-0000-0000-0000-0000000081a4/a.jpg', true), false);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000081a3', false);
select t_eq('בלי מפתח צי — אין קריאה',
  app.may_touch_vehicle_doc('drivers/20000000-0000-0000-0000-0000000081a4/a.jpg', false), false);

reset role;
