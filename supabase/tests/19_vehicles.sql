\pset tuples_only on
\pset format unaligned

-- ===========================================================================
-- 19: צי הרכב — RLS, סנכרון הרישוי, נהגים, כרטיס דלק, והתראות הפקיעה
--     (0089 + 0090).
--
-- החבילה מקימה משאית, שני רכבים וחמישה פרופילים משלה ואינה נשענת על אף חבילה
-- קודמת. היא רצה אחרונה כי היא משאירה אחריה רכבים, מסמכים והתראות שאינם
-- מנוקים, ומפני שהיא סופרת פוליסות על storage.objects. תאריכי הפקיעה נגזרים
-- מ-current_date בכוונה — כל הבדיקה כאן היא על היחס ליום הנוכחי.
-- ===========================================================================

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000019a1', 'fleet-manager@vl.test'),
  ('00000000-0000-0000-0000-0000000019a2', 'fleet-viewer@vl.test'),
  ('00000000-0000-0000-0000-0000000019a3', 'nofleet@vl.test'),
  ('00000000-0000-0000-0000-0000000019a4', 'fleet-admin@vl.test'),
  ('00000000-0000-0000-0000-0000000019a5', 'fleet-driver@vl.test');

insert into profiles (id, user_id, user_kind, is_admin, full_name) values
  -- מנהל צי: כל המפתחות, כולל כרטיס הדלק
  ('20000000-0000-0000-0000-0000000019a1', '00000000-0000-0000-0000-0000000019a1',
   'staff', false, 'מנהל צי'),
  -- צופה: רואה רכבים ומסמכים, ולא את כרטיס הדלק
  ('20000000-0000-0000-0000-0000000019a2', '00000000-0000-0000-0000-0000000019a2',
   'staff', false, 'צופה צי'),
  -- בלי שום מפתח צי: RLS מחזירה לו כלום
  ('20000000-0000-0000-0000-0000000019a3', '00000000-0000-0000-0000-0000000019a3',
   'staff', false, 'עובד ללא צי'),
  ('20000000-0000-0000-0000-0000000019a4', '00000000-0000-0000-0000-0000000019a4',
   'staff', true, 'אדמין צי'),
  ('20000000-0000-0000-0000-0000000019a5', '00000000-0000-0000-0000-0000000019a5',
   'staff', false, 'דני הנהג');

insert into staff_roles (profile_id, role) values
  ('20000000-0000-0000-0000-0000000019a5', 'driver');

insert into user_permission_grants (profile_id, permission_key, allowed) values
  ('20000000-0000-0000-0000-0000000019a1', 'fleet.view', true),
  ('20000000-0000-0000-0000-0000000019a1', 'fleet.create', true),
  ('20000000-0000-0000-0000-0000000019a1', 'fleet.edit', true),
  ('20000000-0000-0000-0000-0000000019a1', 'fleet.delete', true),
  ('20000000-0000-0000-0000-0000000019a1', 'fleet.docs_view', true),
  ('20000000-0000-0000-0000-0000000019a1', 'fleet.docs_manage', true),
  ('20000000-0000-0000-0000-0000000019a1', 'fleet.drivers_manage', true),
  ('20000000-0000-0000-0000-0000000019a1', 'fleet.view_fuel_card', true),
  ('20000000-0000-0000-0000-0000000019a1', 'fleet.manage_fuel_card', true),
  ('20000000-0000-0000-0000-0000000019a1', 'fleet.settings', true),
  ('20000000-0000-0000-0000-0000000019a2', 'fleet.view', true),
  ('20000000-0000-0000-0000-0000000019a2', 'fleet.docs_view', true),
  ('20000000-0000-0000-0000-0000000019a2', 'fleet.docs_manage', false),
  ('20000000-0000-0000-0000-0000000019a2', 'fleet.view_fuel_card', false),
  ('20000000-0000-0000-0000-0000000019a2', 'fleet.settings', false),
  ('20000000-0000-0000-0000-0000000019a3', 'fleet.view', false),
  ('20000000-0000-0000-0000-0000000019a3', 'fleet.docs_view', false);

insert into trucks (id, name, plate_number) values
  ('50000000-0000-0000-0000-000000000019', 'משאית הצי', null);

\echo ''
\echo '=== צי הרכב: מסמכים, תוקף, נהגים וכרטיס דלק ==='

-- ===== 0. המודול והמפתחות ==================================================

\echo '--- הקטלוג ---'

select t_eq('מודול fleet נרשם',
  (select count(*)::int from permission_modules where key = 'fleet'), 1);

select t_eq('עשרת המפתחות נרשמו',
  (select count(*)::int from permission_registry where module = 'fleet' and is_active), 10);

/* זו ההחלטה של 0089 §1, והבדיקה קיימת כדי שלא תבוטל בשקט: `fleet.view` הוא
   מפתח שורש. אילו היה יורש מ-`settings.trucks`, כל רכז שמתקן שם של משאית היה
   מקבל את מחירי הרכישה והליסינג של הצי. */
select t_eq('fleet.view אינו יורש משום מפתח',
  (select implied_by from permission_registry where key = 'fleet.view'), null);

select t_eq('הצי אינו מסך של לקוח או קבלן',
  (select count(*)::int from permission_registry
    where module = 'fleet' and not (applies_to = array['staff']::user_kind[])), 0);

-- ===== 1. הרכב, והרישוי שמסונכרן למשאית ====================================

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000019a1', false);

insert into vehicles (id, plate_number, name, category, truck_id) values
  ('40000000-0000-0000-0000-000000000019', '12-345-67', 'המשאית הגדולה', 'truck',
   '50000000-0000-0000-0000-000000000019');
insert into vehicles (id, plate_number, name, category) values
  ('40000000-0000-0000-0000-00000000001a', '76-543-21', 'המסחרי', 'van');

\echo '--- הרכב מול המשאית ---'

select t_eq('הרכב נוצר',
  (select name from vehicles where id = '40000000-0000-0000-0000-000000000019'), 'המשאית הגדולה');

/* 0089 §3: הרכב הוא מקור האמת, והטריגר דוחף ממנו את הרישוי אל המשאית. */
select t_eq('מספר הרישוי נדחף אל המשאית המקושרת',
  (select plate_number from trucks where id = '50000000-0000-0000-0000-000000000019'), '12-345-67');

update vehicles set plate_number = '12-345-99' where id = '40000000-0000-0000-0000-000000000019';
select t_eq('ושינוי ברכב מתגלגל אליה',
  (select plate_number from trucks where id = '50000000-0000-0000-0000-000000000019'), '12-345-99');

select t_expect_fail('שתי רכבות לאותה משאית נדחות', $$
  update vehicles set truck_id = '50000000-0000-0000-0000-000000000019'
   where id = '40000000-0000-0000-0000-00000000001a'$$);

select t_expect_fail('אותו מספר רישוי פעמיים נדחה', $$
  insert into vehicles (plate_number, name) values ('12-345-99', 'כפילה')$$);

-- ===== 2. RLS ==============================================================

\echo '--- מי רואה את הצי ---'

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000019a2', false);
select t_eq('צופה רואה את שני הרכבים',
  (select count(*)::int from vehicles
    where id in ('40000000-0000-0000-0000-000000000019', '40000000-0000-0000-0000-00000000001a')), 2);
select t_rows('אך אינו עורך אותם',
  $$update vehicles set notes = 'לא אמור לעבור' where id = '40000000-0000-0000-0000-000000000019'$$, 0);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000019a3', false);
select t_eq('מי שאין לו fleet.view אינו רואה רכב',
  (select count(*)::int from vehicles), 0);
select t_expect_fail('ואינו יוצר רכב', $$
  insert into vehicles (plate_number, name) values ('11-111-11', 'מבריח')$$);

-- ===== 3. מסמכים ותוקף =====================================================

\echo '--- מסמכים ---'

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000019a1', false);

insert into vehicle_documents (id, vehicle_id, kind_id, expires_at, document_number)
select '60000000-0000-0000-0000-000000000019', '40000000-0000-0000-0000-000000000019',
       k.id, current_date + 20, 'T-1'
  from vehicle_document_kinds k where k.key = 'annual_test';

insert into vehicle_documents (id, vehicle_id, kind_id, expires_at)
select '60000000-0000-0000-0000-00000000001a', '40000000-0000-0000-0000-000000000019',
       k.id, current_date - 3
  from vehicle_document_kinds k where k.key = 'insurance_mandatory';

insert into vehicle_documents (id, vehicle_id, kind_id, expires_at)
select '60000000-0000-0000-0000-00000000001b', '40000000-0000-0000-0000-000000000019',
       k.id, current_date + 200
  from vehicle_document_kinds k where k.key = 'vehicle_license';

/* השרת הוא שמחשב את התוקף, ולא הלקוח — ה-view הוא מה שהמסך, הדשבורד והסוויפ
   קוראים, ולכן שלושתם אינם יכולים לחלוק על עצמם. */
select t_eq('טסט בעוד 20 יום, וסף ההתראה 30 — פג בקרוב',
  (select status from vehicle_document_status where id = '60000000-0000-0000-0000-000000000019'), 'expiring');
select t_eq('ביטוח חובה שעבר — פג',
  (select status from vehicle_document_status where id = '60000000-0000-0000-0000-00000000001a'), 'expired');
select t_eq('רישיון בעוד 200 יום — בתוקף',
  (select status from vehicle_document_status where id = '60000000-0000-0000-0000-00000000001b'), 'valid');
select t_eq('ונותרו הימים הנכונים',
  (select days_left from vehicle_document_status where id = '60000000-0000-0000-0000-000000000019'), 20);

select t_expect_fail('תאריך פקיעה לפני ההוצאה נדחה', $$
  update vehicle_documents set issued_at = current_date + 30
   where id = '60000000-0000-0000-0000-000000000019'$$);

select t_eq('שם המעלה נחתם מהשרת',
  (select creator_name from vehicle_documents where id = '60000000-0000-0000-0000-000000000019'), 'מנהל צי');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000019a2', false);
select t_expect_fail('צופה אינו מוסיף מסמך', $$
  insert into vehicle_documents (vehicle_id, kind_id)
  select '40000000-0000-0000-0000-000000000019', id from vehicle_document_kinds limit 1$$);
select t_expect_fail('ואינו מסיר מסמך',
  $$select remove_vehicle_document('60000000-0000-0000-0000-000000000019')$$);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000019a1', false);
select t_expect_ok('מנהל הצי מסיר מסמך',
  $$select remove_vehicle_document('60000000-0000-0000-0000-00000000001b')$$);
select t_eq('והוא יורד מהמסך שלו',
  (select count(*)::int from vehicle_document_status
    where id = '60000000-0000-0000-0000-00000000001b' and deleted_at is null), 0);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000019a4', false);
select t_eq('רק אדמין רואה מסמך שהוסר',
  (select count(*)::int from vehicle_documents where id = '60000000-0000-0000-0000-00000000001b'), 1);
select t_expect_ok('והוא זה שיכול לשחזר אותו',
  $$select remove_vehicle_document('60000000-0000-0000-0000-00000000001b', true)$$);

-- ===== 4. נהגים ============================================================

\echo '--- הצמדת נהג ---'

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000019a1', false);

select t_expect_ok('הצמדת נהג ראשון', $$
  select assign_vehicle_driver('40000000-0000-0000-0000-000000000019',
    '20000000-0000-0000-0000-0000000019a5', current_date - 30)$$);

/* העמודה מדונרמלת מהטריגר בלבד — זה מה שמאפשר לרשימה לקרוא נהג בשאילתה אחת. */
select t_eq('current_driver_id נגזר לרכב',
  (select current_driver_id from vehicles where id = '40000000-0000-0000-0000-000000000019'),
  '20000000-0000-0000-0000-0000000019a5'::uuid);
select t_eq('וגם השם, כדי שהרשימה לא תצטרך join',
  (select current_driver_name from vehicles where id = '40000000-0000-0000-0000-000000000019'), 'דני הנהג');

/* 0089 §5: הכתיבה הישירה נחסמת, אחרת העמודה הנגזרת הופכת למקור אמת שני. */
update vehicles set current_driver_id = '20000000-0000-0000-0000-0000000019a1'
 where id = '40000000-0000-0000-0000-000000000019';
select t_eq('כתיבה ישירה על הנהג אינה תופסת',
  (select current_driver_id from vehicles where id = '40000000-0000-0000-0000-000000000019'),
  '20000000-0000-0000-0000-0000000019a5'::uuid);

select t_expect_ok('החלפת נהג', $$
  select assign_vehicle_driver('40000000-0000-0000-0000-000000000019',
    '20000000-0000-0000-0000-0000000019a1', current_date)$$);

select t_eq('ההצמדה הקודמת נסגרה אתמול',
  (select to_date from vehicle_driver_assignments
    where vehicle_id = '40000000-0000-0000-0000-000000000019'
      and profile_id = '20000000-0000-0000-0000-0000000019a5'), current_date - 1);
select t_eq('ויש בדיוק הצמדה פתוחה אחת',
  (select count(*)::int from vehicle_driver_assignments
    where vehicle_id = '40000000-0000-0000-0000-000000000019' and to_date is null), 1);
select t_eq('הנהג הנוכחי הוא החדש',
  (select current_driver_name from vehicles where id = '40000000-0000-0000-0000-000000000019'), 'מנהל צי');
select t_eq('וההיסטוריה זוכרת מי נהג לפניו',
  (select driver_name from vehicle_driver_assignments
    where vehicle_id = '40000000-0000-0000-0000-000000000019' and to_date is not null), 'דני הנהג');

/* אותו נהג פעמיים אינו פותח הצמדה שנייה — אחרת ההיסטוריה מתמלאת ברעש. */
select t_expect_ok('הצמדה חוזרת של אותו נהג אינה מייצרת שורה', $$
  select assign_vehicle_driver('40000000-0000-0000-0000-000000000019',
    '20000000-0000-0000-0000-0000000019a1', current_date)$$);
select t_eq('ומספר ההצמדות לא השתנה',
  (select count(*)::int from vehicle_driver_assignments
    where vehicle_id = '40000000-0000-0000-0000-000000000019'), 2);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000019a2', false);
select t_expect_fail('צופה אינו מצמיד נהג', $$
  select assign_vehicle_driver('40000000-0000-0000-0000-00000000001a',
    '20000000-0000-0000-0000-0000000019a5')$$);
/* אין פוליסת כתיבה על הטבלה כלל — ה-RPCs הם הדלת היחידה. */
select t_rows('ואף אחד אינו כותב בטבלה ישירות', $$
  update vehicle_driver_assignments set note = 'עקיפה'
   where vehicle_id = '40000000-0000-0000-0000-000000000019'$$, 0);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000019a1', false);
select t_expect_ok('סיום הצמדה',
  $$select end_vehicle_driver('40000000-0000-0000-0000-000000000019')$$);
select t_eq('והרכב נשאר בלי נהג קבוע',
  (select current_driver_id from vehicles where id = '40000000-0000-0000-0000-000000000019'), null);

-- ===== 5. כרטיס הדלק — הסעיף שכל ההפרדה קיימת בשבילו =======================

\echo '--- כרטיס הדלק ---'

insert into vehicle_fuel_cards (vehicle_id, provider, card_number, pin_code)
values ('40000000-0000-0000-0000-000000000019', 'פז', '7788990011', '4321');

select t_eq('מנהל הצי רואה את הכרטיס',
  (select pin_code from vehicle_fuel_cards
    where vehicle_id = '40000000-0000-0000-0000-000000000019'), '4321');

/* זו הנקודה: `fleet.view` לבדו אינו פותח את הכרטיס. הפרדה שנשענת רק על
   הסתרה בלקוח הייתה מחזירה את ה-PIN ב-PostgREST לכל מי שרואה רכב. */
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000019a2', false);
select t_eq('צופה עם fleet.view אינו מקבל אף שורת כרטיס',
  (select count(*)::int from vehicle_fuel_cards), 0);
select t_expect_fail('ואינו כותב כרטיס', $$
  insert into vehicle_fuel_cards (vehicle_id, provider, pin_code)
  values ('40000000-0000-0000-0000-00000000001a', 'דלק', '1111')$$);

/* והדלת האחורית: `app.audit()` הגנרית הייתה כותבת את ה-PIN ל-audit_log,
   שנקרא במפתח אחר לגמרי. 0089 §6 מחליף אותה בטריגר שמסתיר את שני השדות. */
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000019a1', false);
update vehicle_fuel_cards set pin_code = '9876'
 where vehicle_id = '40000000-0000-0000-0000-000000000019';

/* היומן עצמו מגודר ב-settings.audit_log, ולכן הקריאה כאן היא של האדמין —
   וזו גם הזהות שהחשיפה הייתה נפתחת אליה אילו הטריגר הגנרי היה במקומו. */
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000019a4', false);

select t_eq('הביקורת רשמה את השינוי',
  (select count(*)::int from audit_log where table_name = 'vehicle_fuel_cards'), 2);
select t_eq('ורשמה איזה שדה השתנה',
  (select changed_cols @> array['pin_code'] from audit_log
    where table_name = 'vehicle_fuel_cards' and action = 'UPDATE'), true);
select t_eq('אך הקוד עצמו אינו יושב ביומן',
  (select count(*)::int from audit_log
    where table_name = 'vehicle_fuel_cards'
      and (coalesce(old_data, '{}')::text like '%4321%'
           or coalesce(new_data, '{}')::text like '%9876%'
           or coalesce(new_data, '{}')::text like '%7788990011%')), 0);
select t_eq('ובמקומו מסכה',
  (select new_data ->> 'pin_code' from audit_log
    where table_name = 'vehicle_fuel_cards' and action = 'UPDATE'), '***');

/* מחיקה רכה חייבת להיעלם גם ממי שמחזיק fleet.manage_fuel_card, ולא רק ממי
   שאין לו fleet.view_fuel_card. `vfc_write` היה בעבר `for all`, ו-Postgres
   מאחד פוליסות פרמיסיביות באותו פועל ב-OR — כלומר ה-USING של הכתיבה (שאינו
   בודק deleted_at) היה פותח select גם על שורה מחוקה למי שמחזיק את מפתח
   הכתיבה. הפיצול ל-vfc_insert/vfc_update (0089 §7) הוא מה שסוגר את זה,
   ואותה בדיקה בדיוק תפסה את התקלה המקבילה ב-vehicle_document_kinds.

   המחיקה עצמה מבוצעת כאן כאדמין, ולא כמנהל הצי — לא לצורך הבדיקה, אלא כי
   Postgres בודק UPDATE נגד ה-USING של פוליסת ה-select גם על השורה *החדשה*,
   לא רק נגד ה-with check של פוליסת הכתיבה. מנהל הצי שהופך את deleted_at
   ל-not null היה נופל על vfc_select (deleted_at is null) באמצע ה-UPDATE שלו
   עצמו — בדיוק המכשול ש-0077/0089 פותרים במסמכים ובנהגים על ידי הפניית
   המחיקה ל-RPC ‏security definer, שרץ בזהות הבעלים ואינו כפוף ל-RLS בכלל.
   כרטיס הדלק אינו נמחק דרך המסך (אין כפתור כזה), ולכן אין לו RPC משלו — מה
   שנבדק כאן הוא רק שמסך שכן יראה שורה מחוקה (למשל דרך ה-Dashboard) לא דולף
   אותה למי שמחזיק רק את מפתח הכתיבה. */
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000019a4', false);
update vehicle_fuel_cards set deleted_at = now()
 where vehicle_id = '40000000-0000-0000-0000-000000000019';

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000019a1', false);
select t_eq('מנהל הצי אינו רואה כרטיס שהוסר, גם שהוא מחזיק manage_fuel_card',
  (select count(*)::int from vehicle_fuel_cards), 0);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000019a4', false);
select t_eq('אדמין כן רואה אותו',
  (select count(*)::int from vehicle_fuel_cards
    where vehicle_id = '40000000-0000-0000-0000-000000000019'), 1);
update vehicle_fuel_cards set deleted_at = null
 where vehicle_id = '40000000-0000-0000-0000-000000000019';

-- ===== 6. הסוויפ ===========================================================

\echo '--- התראות פקיעה ---'

reset role;
select set_config('request.jwt.claim.sub', '', false);

select t_eq('שני סוגי ההתראה בקטלוג',
  (select count(*)::int from notification_types where key like 'vehicle_document%'), 2);
select t_eq('ושניהם מגודרים ב-fleet.view',
  (select count(*)::int from notification_types
    where key like 'vehicle_document%' and required_permission = 'fleet.view'), 2);

/* שני מסמכים חיים בטווח: הטסט בעוד 20 יום, והביטוח שפג לפני 3.
   הביטוח עומד בשלושת הספים בבת אחת (30, 7, 0) — והסוויפ שולח עליו התראה
   אחת ולא שלוש, ורושם את השניים הנותרים כדי שלא יישלחו מחר. */
select t_eq('הסוויפ מטפל בשני המסמכים',
  (fleet_expiry_sweep_result -> 'documents')::int, 2)
  from (select fleet_expiry_sweep() as fleet_expiry_sweep_result) x;

select t_eq('ושני הספים הנוספים של הביטוח נבלעו ולא נשלחו',
  (select count(*)::int from vehicle_document_alerts
    where document_id = '60000000-0000-0000-0000-00000000001a'), 3);

/* האידמפוטנטיות היא כל העניין: התזמון רץ כל יום, והאדם לוחץ "בדוק עכשיו"
   באמצע. שליחה כפולה על אותו מסמך היא בדיוק מה שגורם לאנשים לכבות התראות. */
select t_eq('הרצה שנייה באותו יום אינה שולחת דבר',
  (fleet_expiry_sweep() ->> 'documents')::int, 0);

select t_eq('מנהל הצי קיבל התראה אחת על הביטוח שפג',
  (select count(*)::int from notifications
    where type = 'vehicle_document_expired'
      and recipient_id = '20000000-0000-0000-0000-0000000019a1'
      and entity_id = '40000000-0000-0000-0000-000000000019'), 1);
select t_eq('והתראה אחת על הטסט שעומד לפוג',
  (select count(*)::int from notifications
    where type = 'vehicle_document_expiring'
      and recipient_id = '20000000-0000-0000-0000-0000000019a1'), 1);
select t_eq('ומי שאין לו fleet.view אינו מקבל דבר',
  (select count(*)::int from notifications
    where type like 'vehicle_document%'
      and recipient_id = '20000000-0000-0000-0000-0000000019a3'), 0);
select t_eq('והקישור מוביל לכרטיס הרכב',
  (select distinct link from notifications where type = 'vehicle_document_expired'),
  '/vehicles/40000000-0000-0000-0000-000000000019');

/* חידוש מסמך מזיז את expires_at, וזה חלק מהמפתח הראשי של יומן ההתראות —
   ולכן ההתראה נדרכת מחדש מעצמה, בלי איפוס ידני שאפשר לשכוח. */
update vehicle_documents set expires_at = current_date + 25
 where id = '60000000-0000-0000-0000-00000000001a';
select t_eq('חידוש המסמך דורך את ההתראה מחדש',
  (fleet_expiry_sweep() ->> 'documents')::int, 1);

/* רכב שנמכר אינו מייצר רעש. */
update vehicles set status = 'sold' where id = '40000000-0000-0000-0000-000000000019';
update vehicle_documents set expires_at = current_date + 1
 where id = '60000000-0000-0000-0000-000000000019';
select t_eq('מסמכים של רכב שנמכר מדולגים',
  (fleet_expiry_sweep() ->> 'documents')::int, 0);
update vehicles set status = 'active' where id = '40000000-0000-0000-0000-000000000019';

-- ===== 7. הסיכום והסקשן ====================================================

\echo '--- הסיכום, הדשבורד והדלי ---'

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000019a1', false);

select t_eq('הסיכום סופר את הרכבים שלא נמכרו',
  (fleet_expiry_summary() ->> 'vehicles')::int, 2);
select t_eq('ואת המסמכים שפגו',
  (fleet_expiry_summary() ->> 'expired')::int, 0);

select t_eq('סקשן הצי מחזיר את מצב הרכבים',
  ((dashboard_sections(array['fleet.status'], current_date, current_date + 30)
     -> 'fleet.status') ->> 'total')::int, 2);
select t_eq('וסקשן המסמכים מחזיר רשימה',
  jsonb_typeof(dashboard_sections(array['fleet.documents_expiring'], current_date, current_date + 30)
    -> 'fleet.documents_expiring'), 'array');

/* 0041: null אומר "לא בשבילך", ולא אפס. הווידג׳ט נעלם במקום לצייר ריק. */
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000019a3', false);
select t_eq('בלי fleet.view הסקשן חוזר null',
  (dashboard_sections(array['fleet.status'], current_date, current_date + 30)
    -> 'fleet.status') = 'null'::jsonb, true);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000019a1', false);
select t_expect_ok('התקרה עלתה ל-50 סקשנים', $$
  select dashboard_sections((select array_agg('k' || g) from generate_series(1,50) g),
    current_date - 5, current_date, '{}')$$);

-- ===== 8. הדלי ופוליסות ה-Storage ==========================================

select t_eq('הדלי קיים והוא פרטי',
  (select public from storage.buckets where id = 'vehicle-docs'), false);
select t_eq('ארבע פוליסות על האובייקטים',
  (select count(*)::int from pg_policies
    where schemaname = 'storage' and tablename = 'objects'
      and policyname like 'vehicle_docs_objects_%'), 4);

/* הנתיב הוא החוזה: מה שאינו '<uuid>/...' אינו שלנו ואינו נפתח. */
select t_eq('נתיב שאינו uuid נדחה',
  app.may_touch_vehicle_doc('not-a-uuid/scan.pdf', false), false);
select t_eq('ונתיב של רכב קיים נפתח למי שיש לו מפתח',
  app.may_touch_vehicle_doc('40000000-0000-0000-0000-000000000019/a.pdf', false), true);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000019a2', false);
select t_eq('צופה קורא את הקובץ',
  app.may_touch_vehicle_doc('40000000-0000-0000-0000-000000000019/a.pdf', false), true);
select t_eq('ואינו כותב אליו',
  app.may_touch_vehicle_doc('40000000-0000-0000-0000-000000000019/a.pdf', true), false);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000019a3', false);
select t_eq('ומי שאין לו מפתח אינו רואה דבר',
  app.may_touch_vehicle_doc('40000000-0000-0000-0000-000000000019/a.pdf', false), false);

-- ===== 9. סל המיחזור =======================================================

\echo '--- מחיקה ושחזור ---'

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000019a2', false);
select t_expect_fail('צופה אינו מוחק רכב',
  $$select soft_delete('vehicles', '40000000-0000-0000-0000-00000000001a')$$);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000019a1', false);
select t_expect_ok('מנהל הצי מוחק רכב',
  $$select soft_delete('vehicles', '40000000-0000-0000-0000-00000000001a')$$);
select t_eq('והוא יורד מהרשימה',
  (select count(*)::int from vehicles where id = '40000000-0000-0000-0000-00000000001a'), 0);
select t_expect_ok('ואותו מפתח מחזיר אותו',
  $$select soft_delete('vehicles', '40000000-0000-0000-0000-00000000001a', true)$$);
select t_eq('הרכב חזר',
  (select count(*)::int from vehicles where id = '40000000-0000-0000-0000-00000000001a'), 1);

/* הכפתור ב-VehicleDocKindsTab (הגדרות) קורא ל-soft_delete בדיוק על השם הזה,
   כמו trucks/task_types/statuses. בלי ענף בטבלת ה-case הוא היה נופל תמיד
   על 'טבלה לא נתמכת' — זו הבדיקה שתופסת את זה.

   שורה ייעודית עם id ידוע, ולא אחת מהזריעה: אחרי מחיקה רכה הפוליסה
   (vdk_select) מסתירה אותה ממי שאינו אדמין, ו-id שנשלף ב-SELECT היה חוזר
   null בדיוק ברגע שצריך אותו לשחזור. אותה סיבה שבגללה בדיקת הרכב למעלה
   משתמשת ב-uuid קבוע ולא ב-SELECT אחרי המחיקה. */
insert into vehicle_document_kinds (id, key, name) values
  ('70000000-0000-0000-0000-000000000019', 'test_kind_019', 'סוג לבדיקה');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000019a2', false);
select t_expect_fail('צופה בלי fleet.settings אינו מוחק סוג מסמך',
  $$select soft_delete('vehicle_document_kinds', '70000000-0000-0000-0000-000000000019')$$);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000019a1', false);
select t_expect_ok('מנהל הצי מוחק סוג מסמך',
  $$select soft_delete('vehicle_document_kinds', '70000000-0000-0000-0000-000000000019')$$);
select t_eq('והוא יורד מהקטלוג',
  (select count(*)::int from vehicle_document_kinds
    where id = '70000000-0000-0000-0000-000000000019'), 0);
select t_expect_ok('ואותו מפתח מחזיר אותו',
  $$select soft_delete('vehicle_document_kinds', '70000000-0000-0000-0000-000000000019', true)$$);
select t_eq('הסוג חזר',
  (select count(*)::int from vehicle_document_kinds
    where id = '70000000-0000-0000-0000-000000000019'), 1);

reset role;
select set_config('request.jwt.claim.sub', '', false);
