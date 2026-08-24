\pset tuples_only on
\pset format unaligned

-- ===========================================================================
-- 21: החתמת לקוח על האירוע (0107).
--
-- מי רואה ומחתים: ראש הצוות של *ההקמה*, מנהל המערכת, והלקוח — ולא ראש צוות
-- של הפירוק, ולא רכז משרדי בלי מפתח. החבילה מקימה לקוח, אירוע, שש דמויות
-- ומשימות משלה ואינה נשענת על אף חבילה קודמת. האירוע יושב ב-current_date+350
-- כדי שלא ייתפס בטווח של אף חבילה אחרת.
--
-- הזריעה רצה בלי JWT (auth.uid()=null), ולכן טריגר הפרסום מדלג ואפשר להזריע
-- משימה "משובצת" ישירות — בדיוק כמו חבילה 18.
-- ===========================================================================

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000021a1', 'sig-setup-lead@vl.test'),
  ('00000000-0000-0000-0000-0000000021a2', 'sig-teardown-lead@vl.test'),
  ('00000000-0000-0000-0000-0000000021a3', 'sig-office@vl.test'),
  ('00000000-0000-0000-0000-0000000021a4', 'sig-admin@vl.test'),
  ('00000000-0000-0000-0000-0000000021a5', 'sig-client@vl.test'),
  ('00000000-0000-0000-0000-0000000021a6', 'sig-office-granted@vl.test');

insert into customers (id, name) values
  ('10000000-0000-0000-0000-000000000021', 'לקוח חתימות');

insert into profiles (id, user_id, user_kind, is_admin, full_name, customer_id) values
  -- ראש צוות ההקמה: אין לו שום מפתח חתימה — הוא מגיע דרך התפקיד על השורה
  ('20000000-0000-0000-0000-0000000021a1', '00000000-0000-0000-0000-0000000021a1',
   'staff', false, 'ראש צוות ההקמה', null),
  -- ראש צוות הפירוק: תפקיד באירוע, אך לא בהקמה — ולכן חסום
  ('20000000-0000-0000-0000-0000000021a2', '00000000-0000-0000-0000-0000000021a2',
   'staff', false, 'ראש צוות הפירוק', null),
  -- רכז משרדי עם events.view בלבד: בלי מפתח חתימה אינו רואה כלום
  ('20000000-0000-0000-0000-0000000021a3', '00000000-0000-0000-0000-0000000021a3',
   'staff', false, 'רכז משרדי', null),
  -- מנהל מערכת: עוקף הכול
  ('20000000-0000-0000-0000-0000000021a4', '00000000-0000-0000-0000-0000000021a4',
   'staff', true, 'מנהל מערכת', null),
  -- משתמש הלקוח: היחיד עם customer_id, מגיע דרך זהות
  ('20000000-0000-0000-0000-0000000021a5', '00000000-0000-0000-0000-0000000021a5',
   'customer_user', false, 'איש קשר אצל הלקוח', '10000000-0000-0000-0000-000000000021'),
  -- רכז משרדי שהוענקו לו המפתחות במפורש: מוכיח שנתיב המפתח עובד
  ('20000000-0000-0000-0000-0000000021a6', '00000000-0000-0000-0000-0000000021a6',
   'staff', false, 'רכז מורשה', null);

insert into user_permission_grants (profile_id, permission_key, allowed) values
  ('20000000-0000-0000-0000-0000000021a1', 'events.view', true),
  ('20000000-0000-0000-0000-0000000021a2', 'events.view', true),
  ('20000000-0000-0000-0000-0000000021a3', 'events.view', true),
  ('20000000-0000-0000-0000-0000000021a3', 'events.sign_view', false),
  ('20000000-0000-0000-0000-0000000021a3', 'events.sign_capture', false),
  ('20000000-0000-0000-0000-0000000021a6', 'events.view', true),
  ('20000000-0000-0000-0000-0000000021a6', 'events.sign_view', true),
  ('20000000-0000-0000-0000-0000000021a6', 'events.sign_capture', true);

insert into events (id, customer_id, end_client_name, event_date, location_text) values
  ('30000000-0000-0000-0000-000000000021',
   '10000000-0000-0000-0000-000000000021', 'לקוח הקצה', current_date + 350, 'ירושלים');

-- שתי משימות משובצות משלנו: הקמה ופירוק. (יצירת האירוע כבר הריצה בלוק הקמה/פירוק
-- אוטומטי, אבל לאיש אינו משובץ בו כראש צוות, ולכן הוא אינו משפיע על הבדיקה.)
insert into tasks (id, event_id, customer_id, task_type_id, task_date, status_id, worker_count)
select v.id, '30000000-0000-0000-0000-000000000021',
       '10000000-0000-0000-0000-000000000021',
       (select id from task_types where code = v.tcode limit 1),
       current_date + 350,
       (select id from statuses where entity = 'task' and code = 'assigned' and deleted_at is null),
       1
from (values
  ('61000000-0000-0000-0000-000000021001'::uuid, 'setup'),
  ('61000000-0000-0000-0000-000000021002'::uuid, 'teardown')
) as v(id, tcode);

-- ראש צוות ההקמה על משימת ההקמה; ראש צוות הפירוק על משימת הפירוק.
insert into task_assignments (task_id, profile_id, role, work_site) values
  ('61000000-0000-0000-0000-000000021001', '20000000-0000-0000-0000-0000000021a1', 'team_lead', 'field'),
  ('61000000-0000-0000-0000-000000021002', '20000000-0000-0000-0000-0000000021a2', 'team_lead', 'field');

-- ===== 1. "ראש צוות בהקמה" מובחן מראש צוות הפירוק ==========================

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000021a1', false);
select t_eq('ראש צוות ההקמה מזוהה ככזה',
  app.is_event_setup_team_lead('30000000-0000-0000-0000-000000000021'), true);
reset role;
select set_config('request.jwt.claim.sub', '', false);

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000021a2', false);
select t_eq('ראש צוות הפירוק אינו ראש צוות ההקמה',
  app.is_event_setup_team_lead('30000000-0000-0000-0000-000000000021'), false);
reset role;
select set_config('request.jwt.claim.sub', '', false);

-- ===== 2. ראש צוות ההקמה מחתים, ורואה ======================================

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000021a1', false);

insert into event_signatures (event_id, signer_name, signature_data)
values ('30000000-0000-0000-0000-000000000021', 'דוד כהן',
        'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCA');

select t_eq('נרשמה חתימה אחת',
  (select count(*)::int from event_signatures
    where event_id = '30000000-0000-0000-0000-000000000021'), 1);

select t_eq('ושם החותם נשמר',
  (select signer_name from event_signatures
    where event_id = '30000000-0000-0000-0000-000000000021'), 'דוד כהן');

-- זהות המחתים נכפית מהשרת: גם אם הקליינט שולח signed_by אחר, הוא נדרס
insert into event_signatures (event_id, signer_name, signature_data, signed_by, signed_by_name)
values ('30000000-0000-0000-0000-000000000021', 'רבקה לוי',
        'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCB',
        '20000000-0000-0000-0000-0000000021a2', 'מישהו אחר');

select t_eq('המחתים נחתם מהפרופיל של הקורא, לא מהקליינט',
  (select signed_by::text from event_signatures
    where event_id = '30000000-0000-0000-0000-000000000021' and signer_name = 'רבקה לוי'),
  '20000000-0000-0000-0000-0000000021a1');

select t_eq('ושמו נשמר לצד המזהה',
  (select signed_by_name from event_signatures
    where event_id = '30000000-0000-0000-0000-000000000021' and signer_name = 'רבקה לוי'),
  'ראש צוות ההקמה');

-- ===== 3. החתימה אינה ניתנת לשינוי =========================================
-- אין פוליסת update, ולכן UPDATE ישיר תחת RLS אינו נוגע בשורה
select t_rows('UPDATE ישיר על החתימה אינו נוגע בשורה',
  $$update event_signatures set signer_name = 'מזויף'
     where event_id = '30000000-0000-0000-0000-000000000021'$$, 0);

-- ===== 4. צורת הנתונים =====================================================

select t_expect_fail('חתימה שאינה data URL של תמונה נדחית',
  $$insert into event_signatures (event_id, signer_name, signature_data)
    values ('30000000-0000-0000-0000-000000000021', 'רות', 'לא-חתימה')$$);

select t_expect_fail('שם חותם ריק נדחה',
  $$insert into event_signatures (event_id, signer_name, signature_data)
    values ('30000000-0000-0000-0000-000000000021', '   ',
            'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCA')$$);

reset role;
select set_config('request.jwt.claim.sub', '', false);

-- והטריגר חוסם שכתוב גם בנתיב ה-security definer, שבו RLS אינה קיימת
select t_expect_fail('הטריגר חוסם שכתוב של חתימה גם ללא RLS',
  $$update event_signatures set signer_name = 'x'
     where event_id = '30000000-0000-0000-0000-000000000021'$$);

-- ===== 5. ראש צוות הפירוק חסום =============================================

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000021a2', false);

select t_eq('ראש צוות הפירוק אינו רואה חתימות',
  (select count(*)::int from event_signatures
    where event_id = '30000000-0000-0000-0000-000000000021'), 0);

select t_expect_fail('ואינו מחתים',
  $$insert into event_signatures (event_id, signer_name, signature_data)
    values ('30000000-0000-0000-0000-000000000021', 'פירוק',
            'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCA')$$);

reset role;
select set_config('request.jwt.claim.sub', '', false);

-- ===== 6. רכז משרדי בלי מפתח חסום ==========================================

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000021a3', false);

select t_eq('רכז בלי מפתח החתמה אינו רואה חתימות',
  (select count(*)::int from event_signatures
    where event_id = '30000000-0000-0000-0000-000000000021'), 0);

select t_expect_fail('ואינו מחתים',
  $$insert into event_signatures (event_id, signer_name, signature_data)
    values ('30000000-0000-0000-0000-000000000021', 'רכז',
            'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCA')$$);

reset role;
select set_config('request.jwt.claim.sub', '', false);

-- ===== 7. הלקוח רואה ומחתים על האירוע שלו ==================================

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000021a5', false);

select t_eq('הלקוח רואה את חתימות האירוע שלו',
  (select count(*)::int from event_signatures
    where event_id = '30000000-0000-0000-0000-000000000021'), 2);

insert into event_signatures (event_id, signer_name, signature_data)
values ('30000000-0000-0000-0000-000000000021', 'הלקוח בכבודו',
        'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCC');

select t_eq('והוא מחתים בעצמו',
  (select count(*)::int from event_signatures
    where event_id = '30000000-0000-0000-0000-000000000021'), 3);

reset role;
select set_config('request.jwt.claim.sub', '', false);

-- ===== 8. רכז מורשה — נתיב המפתח ===========================================

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000021a6', false);

select t_eq('רכז מורשה רואה את החתימות דרך המפתח',
  (select count(*)::int from event_signatures
    where event_id = '30000000-0000-0000-0000-000000000021'), 3);

select t_expect_ok('ומחתים דרך המפתח',
  $$insert into event_signatures (event_id, signer_name, signature_data)
    values ('30000000-0000-0000-0000-000000000021', 'מורשה',
            'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCA')$$);

reset role;
select set_config('request.jwt.claim.sub', '', false);

-- ===== 9. מנהל המערכת רואה הכול ============================================

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000021a4', false);

select t_eq('מנהל המערכת רואה את כל החתימות',
  (select count(*)::int from event_signatures
    where event_id = '30000000-0000-0000-0000-000000000021'), 4);

reset role;
select set_config('request.jwt.claim.sub', '', false);

-- ===== 10. יומן הפעילות ====================================================

select t_eq('כל החתמה רשמה שורת customer_signed ביומן',
  (select count(*)::int from event_activity
    where event_id = '30000000-0000-0000-0000-000000000021' and kind = 'customer_signed'), 4);

select t_eq('ושורת היומן נושאת את שם החותם',
  (select count(*)::int from event_activity
    where event_id = '30000000-0000-0000-0000-000000000021'
      and kind = 'customer_signed' and note like 'נקלטה חתימת לקוח: דוד כהן'), 1);
