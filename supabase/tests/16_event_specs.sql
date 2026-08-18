\pset tuples_only on
\pset format unaligned

-- ===========================================================================
-- 16: מפרט האירוע — גרסאות, אי-שינוי, RLS ופוליסות ה-Storage (0077).
--
-- החבילה מקימה לקוח, אירוע ושלושה פרופילים משלה ואינה נשענת על אף חבילה קודמת —
-- 02 הופכת את f2 לאדמין, ו-06/09 מזיזות מפתחות על f1/f3. האירוע יושב ב-
-- current_date + 300 כדי שלא ייתפס בטווחים של חבילות הדשבורד והדוחות.
-- ===========================================================================

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000016a1', 'specs-manager@vl.test'),
  ('00000000-0000-0000-0000-0000000016a2', 'specs-viewer@vl.test'),
  ('00000000-0000-0000-0000-0000000016a3', 'nospecs@vl.test'),
  ('00000000-0000-0000-0000-0000000016a4', 'specs-admin@vl.test');

insert into customers (id, name) values
  ('10000000-0000-0000-0000-000000000016', 'לקוח מפרטים');

insert into profiles (id, user_id, user_kind, is_admin, full_name) values
  -- מעלה מפרטים: specs_view + specs_manage
  ('20000000-0000-0000-0000-0000000016a1', '00000000-0000-0000-0000-0000000016a1',
   'staff', false, 'רכזת מפרטים'),
  -- צופה בלבד: specs_view ותו לא
  ('20000000-0000-0000-0000-0000000016a2', '00000000-0000-0000-0000-0000000016a2',
   'staff', false, 'צופה מפרטים'),
  -- בלי שום מפתח מפרטים: RLS מחזירה לו כלום
  ('20000000-0000-0000-0000-0000000016a3', '00000000-0000-0000-0000-0000000016a3',
   'staff', false, 'עובד ללא מפרטים'),
  -- אדמין: רק הוא רואה גרסאות שהוסרו, ולכן רק הוא יכול לשחזר אחת
  ('20000000-0000-0000-0000-0000000016a4', '00000000-0000-0000-0000-0000000016a4',
   'staff', true, 'אדמין מפרטים');

insert into user_permission_grants (profile_id, permission_key, allowed) values
  ('20000000-0000-0000-0000-0000000016a1', 'events.view', true),
  ('20000000-0000-0000-0000-0000000016a1', 'events.specs_view', true),
  ('20000000-0000-0000-0000-0000000016a1', 'events.specs_manage', true),
  ('20000000-0000-0000-0000-0000000016a2', 'events.view', true),
  ('20000000-0000-0000-0000-0000000016a2', 'events.specs_view', true),
  ('20000000-0000-0000-0000-0000000016a2', 'events.specs_manage', false),
  ('20000000-0000-0000-0000-0000000016a3', 'events.view', true),
  ('20000000-0000-0000-0000-0000000016a3', 'events.specs_view', false),
  ('20000000-0000-0000-0000-0000000016a3', 'events.specs_manage', false);

insert into events (id, customer_id, end_client_name, event_date, location_text) values
  ('30000000-0000-0000-0000-000000000016',
   '10000000-0000-0000-0000-000000000016', 'אירוע מפרטים',
   current_date + 300, 'תל אביב');

-- ===== 1. מספור הגרסאות ====================================================

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000016a1', false);

insert into event_specs (event_id, source, storage_path, file_name, mime_type, size_bytes)
values ('30000000-0000-0000-0000-000000000016', 'file',
        '30000000-0000-0000-0000-000000000016/aaaaaaaa-0000-0000-0000-000000000001.pdf',
        'מפרט ראשוני.pdf', 'application/pdf', 120000);

-- version נשלח מהקליינט במכוון, והטריגר מתעלם ממנו
insert into event_specs (event_id, version, source, storage_path, file_name, mime_type)
values ('30000000-0000-0000-0000-000000000016', 99, 'file',
        '30000000-0000-0000-0000-000000000016/aaaaaaaa-0000-0000-0000-000000000002.pdf',
        'מפרט מעודכן.pdf', 'application/pdf');

insert into event_specs (event_id, source, url, title)
values ('30000000-0000-0000-0000-000000000016', 'link',
        'https://drive.example.com/spec-v3', 'מפרט אחרי סיור');

select t_eq('שלוש גרסאות נרשמו',
  (select count(*)::int from event_specs
    where event_id = '30000000-0000-0000-0000-000000000016'), 3);

select t_eq('המספור רץ 1,2,3 והקליינט אינו קובע אותו',
  (select array_agg(version order by version)::text from event_specs
    where event_id = '30000000-0000-0000-0000-000000000016'), '{1,2,3}');

select t_eq('הגרסה הפעילה היא הגבוהה שאינה מחוקה',
  (select version from event_specs
    where event_id = '30000000-0000-0000-0000-000000000016' and deleted_at is null
    order by version desc limit 1), 3);

select t_eq('וכאן היא הקישור, ולא קובץ',
  (select url from event_specs
    where event_id = '30000000-0000-0000-0000-000000000016' and deleted_at is null
    order by version desc limit 1), 'https://drive.example.com/spec-v3');

-- ===== 2. זהות המעלה נכפית מהשרת ===========================================

select t_eq('המעלה נחתם מהפרופיל של הקורא',
  (select uploaded_by::text from event_specs
    where event_id = '30000000-0000-0000-0000-000000000016' and version = 1),
  '20000000-0000-0000-0000-0000000016a1');

select t_eq('ושמו נשמר לצד המזהה',
  (select uploader_name from event_specs
    where event_id = '30000000-0000-0000-0000-000000000016' and version = 1),
  'רכזת מפרטים');

insert into event_specs (event_id, source, url, uploaded_by, uploader_name)
values ('30000000-0000-0000-0000-000000000016', 'link', 'https://example.com/forged',
        '20000000-0000-0000-0000-0000000016a3', 'מישהו אחר');

select t_eq('מעלה מזויף נדרס ולא נשמר',
  (select uploader_name from event_specs
    where event_id = '30000000-0000-0000-0000-000000000016' and version = 4),
  'רכזת מפרטים');

-- ===== 3. הגרסה אינה ניתנת לשינוי ==========================================
-- אין פוליסת update על הטבלה, ולכן כל UPDATE ישיר מהקליינט אינו נוגע בשורה —
-- גם למי שמחזיק את מפתח הניהול. t_rows מבדיל בין "נחסם" ל"לא עשה כלום".

select t_rows('UPDATE ישיר על storage_path אינו נוגע בשורה',
  $$update event_specs set storage_path = '30000000-0000-0000-0000-000000000016/hack.pdf'
     where event_id = '30000000-0000-0000-0000-000000000016' and version = 1$$, 0);

select t_rows('וגם לא על הכותרת',
  $$update event_specs set title = 'כותרת מוברחת'
     where event_id = '30000000-0000-0000-0000-000000000016' and version = 1$$, 0);

select t_eq('הקובץ של גרסה 1 לא זז',
  (select storage_path from event_specs
    where event_id = '30000000-0000-0000-0000-000000000016' and version = 1),
  '30000000-0000-0000-0000-000000000016/aaaaaaaa-0000-0000-0000-000000000001.pdf');

-- והטריגר חוסם את אותו שכתוב גם בנתיב ה-security definer, שבו RLS אינה קיימת
reset role;
select t_expect_fail('הטריגר חוסם שכתוב של גרסה גם ללא RLS',
  $$update event_specs set storage_path = 'x/y.pdf'
     where event_id = '30000000-0000-0000-0000-000000000016' and version = 1$$);
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000016a1', false);

-- ===== 4. הסרה רכה מחזירה את הקודמת לתפקיד =================================

select remove_event_spec((select id from event_specs
  where event_id = '30000000-0000-0000-0000-000000000016' and version = 4));
select remove_event_spec((select id from event_specs
  where event_id = '30000000-0000-0000-0000-000000000016' and version = 3));

select t_eq('אחרי הסרת שתי העליונות, הפעילה היא גרסה 2',
  (select version from event_specs
    where event_id = '30000000-0000-0000-0000-000000000016' and deleted_at is null
    order by version desc limit 1), 2);

select t_eq('והגרסאות המוסרות נעלמו מהקריאה',
  (select count(*)::int from event_specs
    where event_id = '30000000-0000-0000-0000-000000000016'), 2);

-- מספר של גרסה שהוסרה אינו חוזר לשימוש: העלאה חדשה היא 5, לא 3
insert into event_specs (event_id, source, url)
values ('30000000-0000-0000-0000-000000000016', 'link', 'https://drive.example.com/spec-v5');

select t_eq('מספר גרסה שהוסרה אינו ממוחזר',
  (select version from event_specs
    where event_id = '30000000-0000-0000-0000-000000000016' and deleted_at is null
    order by version desc limit 1), 5);

-- שחזור: הוא אותו מעבר בכיוון ההפוך, והוא פעולה של אדמין בלבד — לא מפני שהמפתח
-- חסר לרכזת, אלא מפני שפוליסת ה-select מסתירה ממנה את הגרסה שהיא עצמה הסירה,
-- ואי אפשר לשחזר שורה שאי אפשר למצוא.
select t_eq('הרכזת אינה רואה את הגרסה שהסירה',
  (select count(*)::int from event_specs
    where event_id = '30000000-0000-0000-0000-000000000016' and version = 3), 0);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000016a4', false);

select t_eq('האדמין כן רואה אותה',
  (select count(*)::int from event_specs
    where event_id = '30000000-0000-0000-0000-000000000016' and version = 3), 1);

select remove_event_spec((select id from event_specs
  where event_id = '30000000-0000-0000-0000-000000000016' and version = 3), true);

select t_eq('ואחרי שחזור היא חוזרת לרשימה החיה',
  (select count(*)::int from event_specs
    where event_id = '30000000-0000-0000-0000-000000000016' and deleted_at is null), 4);

select remove_event_spec((select id from event_specs
  where event_id = '30000000-0000-0000-0000-000000000016' and version = 3));

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000016a1', false);

-- ===== 5. צורת השורה =======================================================

select t_expect_fail('קובץ בלי storage_path נדחה',
  $$insert into event_specs (event_id, source, file_name)
    values ('30000000-0000-0000-0000-000000000016', 'file', 'ריק.pdf')$$);

select t_expect_fail('קישור שאינו http נדחה',
  $$insert into event_specs (event_id, source, url)
    values ('30000000-0000-0000-0000-000000000016', 'link', 'javascript:alert(1)')$$);

select t_expect_fail('source לא מוכר נדחה',
  $$insert into event_specs (event_id, source, url)
    values ('30000000-0000-0000-0000-000000000016', 'email', 'https://x.test/a')$$);

-- ===== 6. יומן הפעילות =====================================================

select t_eq('חמש העלאות ושחזור אחד רשמו spec_added',
  (select count(*)::int from event_activity
    where event_id = '30000000-0000-0000-0000-000000000016' and kind = 'spec_added'), 6);

select t_eq('ושלוש ההסרות רשמו spec_removed',
  (select count(*)::int from event_activity
    where event_id = '30000000-0000-0000-0000-000000000016' and kind = 'spec_removed'), 3);

select t_eq('שורת השחזור מסומנת ככזו',
  (select count(*)::int from event_activity
    where event_id = '30000000-0000-0000-0000-000000000016'
      and note like 'שוחזר מפרט:%'), 1);

select t_eq('שורת היומן מתארת את הגרסה כמשפט',
  (select note from event_activity
    where event_id = '30000000-0000-0000-0000-000000000016'
      and kind = 'spec_added' order by id limit 1),
  'הועלה מפרט: גרסה 1 · מפרט ראשוני.pdf');

select t_eq('והיומן זוכר מי עשה זאת',
  (select actor_name from event_activity
    where event_id = '30000000-0000-0000-0000-000000000016'
      and kind = 'spec_added' order by id limit 1), 'רכזת מפרטים');

-- ===== 7. השער על ה-Storage ================================================

select t_eq('נתיב תקין נפתח למי שמנהל מפרטים',
  app.may_touch_event_spec(
    '30000000-0000-0000-0000-000000000016/aaaaaaaa-0000-0000-0000-000000000001.pdf', true), true);

select t_eq('נתיב שאינו <uuid>/... נחסם',
  app.may_touch_event_spec('public/anything.pdf', false), false);

select t_eq('נתיב של אירוע שאינו קיים נחסם',
  app.may_touch_event_spec('30000000-0000-0000-0000-0000000000ff/x.pdf', false), false);

-- ===== 8. צופה בלבד ========================================================

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000016a2', false);

select t_eq('הצופה רואה את הגרסאות החיות',
  (select count(*)::int from event_specs
    where event_id = '30000000-0000-0000-0000-000000000016'), 3);

select t_expect_fail('אך אינו מעלה גרסה חדשה',
  $$insert into event_specs (event_id, source, url)
    values ('30000000-0000-0000-0000-000000000016', 'link', 'https://x.test/viewer')$$);

select t_expect_fail('ואינו מסיר גרסה קיימת',
  $$select remove_event_spec((select id from event_specs
      where event_id = '30000000-0000-0000-0000-000000000016' and version = 2))$$);

select t_eq('השער על ה-Storage פתוח לו לקריאה',
  app.may_touch_event_spec(
    '30000000-0000-0000-0000-000000000016/aaaaaaaa-0000-0000-0000-000000000001.pdf', false), true);

select t_eq('וסגור לו לכתיבה',
  app.may_touch_event_spec(
    '30000000-0000-0000-0000-000000000016/aaaaaaaa-0000-0000-0000-000000000001.pdf', true), false);

-- ===== 9. מי שאין לו את המפתח ==============================================

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000016a3', false);

select t_eq('בלי events.specs_view הרשימה ריקה',
  (select count(*)::int from event_specs
    where event_id = '30000000-0000-0000-0000-000000000016'), 0);

select t_eq('והשער על ה-Storage סגור לו',
  app.may_touch_event_spec(
    '30000000-0000-0000-0000-000000000016/aaaaaaaa-0000-0000-0000-000000000001.pdf', false), false);

select t_expect_fail('והעלאה נדחית',
  $$insert into event_specs (event_id, source, url)
    values ('30000000-0000-0000-0000-000000000016', 'link', 'https://x.test/nobody')$$);

reset role;
select set_config('request.jwt.claim.sub', '', false);

-- ===== 10. הדלי עצמו =======================================================

select t_eq('הדלי פרטי', (select public from storage.buckets where id = 'event-specs'), false);

select t_eq('ומגביל את סוגי הקבצים',
  (select 'application/pdf' = any(allowed_mime_types) and not ('text/html' = any(allowed_mime_types))
     from storage.buckets where id = 'event-specs'), true);

select t_eq('ארבע פוליסות על storage.objects',
  (select count(*)::int from pg_policies
    where schemaname = 'storage' and tablename = 'objects'
      and policyname like 'event_specs_objects_%'), 4);
