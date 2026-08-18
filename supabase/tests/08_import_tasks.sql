\pset tuples_only on
\pset format unaligned

-- ================= ייבוא אירועים עם משימות (0052) =================
-- החבילה מקימה לקוח ושני אנשי צוות משלה ואינה נשענת על ההרשאות של f1, ש-06
-- מזיזה הלוך ושוב.
--
-- מה שלא נבדק כאן במכוון: ה-revoke על app.apply_import_tasks. 01_seed מריץ
-- `grant execute on all functions in schema public, app to authenticated`
-- *אחרי* המיגרציות ומחזיר אותו, ולכן אין לבדיקה כאן מה לומר על הפרודקשן.
-- ההגנה שנבדקת היא זו שאי אפשר לעקוף בהגדרות: app.require בתוך הפונקציה.

reset role;
select set_config('request.jwt.claim.sub', '', false);

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000f8', 'importer@vl.test'),
  ('00000000-0000-0000-0000-0000000000f9', 'importer-no-tasks@vl.test'),
  ('00000000-0000-0000-0000-0000000000fa', 'no-import@vl.test'),
  ('00000000-0000-0000-0000-0000000000fc', 'importer-no-money@vl.test');

insert into customers (id, name, can_create_events) values
  ('10000000-0000-0000-0000-000000000008', 'לקוח הייבוא', true),
  ('10000000-0000-0000-0000-000000000009', 'לקוח הייבוא ב׳', true);

-- הישויות שהקובץ נוקב בהן בשם (0076). הספק השני שייך ללקוח האחר, וקיים כדי
-- לבדוק שהתאמה לפי שם אינה חוצה לקוחות.
insert into warehouses (id, name) values
  ('70000000-0000-0000-0000-0000000000f1', 'מחסן הייבוא');
insert into contractors (id, name, default_task_price) values
  ('40000000-0000-0000-0000-0000000000f1', 'קבלן הייבוא', 500);
insert into suppliers (customer_id, name) values
  ('10000000-0000-0000-0000-000000000008', 'ספק הייבוא'),
  ('10000000-0000-0000-0000-000000000008', 'ספק הבמות'),
  ('10000000-0000-0000-0000-000000000009', 'ספק זר');

insert into profiles (id, user_id, user_kind, is_admin, full_name) values
  ('20000000-0000-0000-0000-0000000000f8', '00000000-0000-0000-0000-0000000000f8',
   'staff', false, 'מייבא'),
  ('20000000-0000-0000-0000-0000000000f9', '00000000-0000-0000-0000-0000000000f9',
   'staff', false, 'מייבא בלי משימות'),
  ('20000000-0000-0000-0000-0000000000fa', '00000000-0000-0000-0000-0000000000fa',
   'staff', false, 'בלי ייבוא כלל'),
  ('20000000-0000-0000-0000-0000000000fc', '00000000-0000-0000-0000-0000000000fc',
   'staff', false, 'מייבא בלי מפתחות כסף');

insert into user_permission_grants (profile_id, permission_key, allowed) values
  ('20000000-0000-0000-0000-0000000000f8', 'events.view',   true),
  ('20000000-0000-0000-0000-0000000000f8', 'events.create', true),
  ('20000000-0000-0000-0000-0000000000f8', 'events.import', true),
  ('20000000-0000-0000-0000-0000000000f8', 'tasks.view',    true),
  ('20000000-0000-0000-0000-0000000000f8', 'tasks.create',  true),
  -- מפתחות הכסף של 0076. pricing.view ו-contractors.view אינם נדרשים לייבוא
  -- עצמו אלא לקריאה חזרה של מה שנכתב — ה-RLS על שתי טבלאות המחירים.
  ('20000000-0000-0000-0000-0000000000f8', 'pricing.edit',  true),
  ('20000000-0000-0000-0000-0000000000f8', 'pricing.view',  true),
  ('20000000-0000-0000-0000-0000000000f8', 'tasks.delegate', true),
  ('20000000-0000-0000-0000-0000000000f8', 'contractors.view', true),
  ('20000000-0000-0000-0000-0000000000f8', 'contractors.edit_pricing', true),
  -- fb מייבא אירועים ומשימות, אבל אף עמודת כסף אינה פתוחה לו
  ('20000000-0000-0000-0000-0000000000fc', 'events.view',   true),
  ('20000000-0000-0000-0000-0000000000fc', 'events.create', true),
  ('20000000-0000-0000-0000-0000000000fc', 'events.import', true),
  ('20000000-0000-0000-0000-0000000000fc', 'tasks.view',    true),
  ('20000000-0000-0000-0000-0000000000fc', 'tasks.create',  true),
  ('20000000-0000-0000-0000-0000000000f9', 'events.view',   true),
  ('20000000-0000-0000-0000-0000000000f9', 'events.create', true),
  ('20000000-0000-0000-0000-0000000000f9', 'events.import', true),
  ('20000000-0000-0000-0000-0000000000f9', 'tasks.create',  false),
  -- events.import הוא implied_by events.create (0011:72), ולכן שלילה מפורשת
  -- של שניהם היא הדרך לתאר "איש צוות שאינו מייבא".
  ('20000000-0000-0000-0000-0000000000fa', 'events.view',   true),
  ('20000000-0000-0000-0000-0000000000fa', 'events.create', false),
  ('20000000-0000-0000-0000-0000000000fa', 'events.import', false);

-- bulk_import_events כותבת שורות שה-SELECT הקורא לה אינו רואה בתמונת המצב
-- שלו, בדיוק כמו create_event ב-01_seed. העטיפה קוראת אותן בהוראה נפרדת.
create or replace function t_import(p_rows jsonb)
returns jsonb language plpgsql as $$
declare v jsonb; v_event uuid; v_tasks int; v_number text;
begin
  v := bulk_import_events(p_rows);
  v_number := p_rows -> 0 ->> 'event_number';
  select id into v_event from events
   where event_number = v_number and deleted_at is null;
  select count(*) into v_tasks from tasks
   where event_id = v_event and deleted_at is null;
  return v || jsonb_build_object(
    'event_found', v_event is not null,
    'task_count', coalesce(v_tasks, 0),
    'error_count', jsonb_array_length(v -> 'errors'),
    'first_error', v -> 'errors' -> 0 ->> 'error');
end $$;
grant execute on function t_import(jsonb) to authenticated;

-- שדה במשימה שנכתבה, לפי סוג המשימה — כדי לבדוק שהערכים מהקובץ הגיעו ליעדם
create or replace function t_task_field(p_number text, p_type text, p_field text)
returns text language plpgsql as $$
declare v text;
begin
  execute format($f$
    select t.%I::text from tasks t
      join events e on e.id = t.event_id
      join task_types tt on tt.id = t.task_type_id
     where e.event_number = $1 and tt.name = $2 and t.deleted_at is null
     order by t.created_at, t.id limit 1$f$, p_field)
    into v using p_number, p_type;
  return v;
end $$;
grant execute on function t_task_field(text,text,text) to authenticated;

-- אותה שליפה על שדה של האירוע
create or replace function t_event_field(p_number text, p_field text)
returns text language plpgsql as $$
declare v text;
begin
  execute format($f$
    select e.%I::text from events e
     where e.event_number = $1 and e.deleted_at is null limit 1$f$, p_field)
    into v using p_number;
  return v;
end $$;
grant execute on function t_event_field(text,text) to authenticated;

-- הספקים שנקשרו לאירוע, לפי שם
create or replace function t_event_suppliers(p_number text)
returns text language sql stable as $$
  select string_agg(s.name, ', ' order by s.name)
    from event_suppliers es
    join suppliers s on s.id = es.supplier_id
    join events e on e.id = es.event_id
   where e.event_number = p_number and e.deleted_at is null
$$;
grant execute on function t_event_suppliers(text) to authenticated;

-- שתי צלעות הכסף של המשימה, ושמו של הקבלן שהיא הואצלה אליו. שלושתן קוראות
-- טבלאות שה-RLS שומר עליהן, ולכן הן רצות כמי שקורא להן ולא כ-definer: מה
-- שהן מחזירות הוא מה שהמייבא באמת רואה אחרי הייבוא.
create or replace function t_task_price(p_number text, p_type text)
returns numeric language sql stable as $$
  select tp.price from task_pricing tp
    join tasks t on t.id = tp.task_id
    join events e on e.id = t.event_id
    join task_types tt on tt.id = t.task_type_id
   where e.event_number = p_number and tt.name = p_type and t.deleted_at is null
   order by t.created_at, t.id limit 1
$$;
grant execute on function t_task_price(text,text) to authenticated;

create or replace function t_task_price_manual(p_number text, p_type text)
returns boolean language sql stable as $$
  select tp.is_manual from task_pricing tp
    join tasks t on t.id = tp.task_id
    join events e on e.id = t.event_id
    join task_types tt on tt.id = t.task_type_id
   where e.event_number = p_number and tt.name = p_type and t.deleted_at is null
   order by t.created_at, t.id limit 1
$$;
grant execute on function t_task_price_manual(text,text) to authenticated;

create or replace function t_terms_price(p_number text, p_type text)
returns numeric language sql stable as $$
  select ct.price from task_contractor_terms ct
    join tasks t on t.id = ct.task_id
    join events e on e.id = t.event_id
    join task_types tt on tt.id = t.task_type_id
   where e.event_number = p_number and tt.name = p_type and t.deleted_at is null
   order by t.created_at, t.id limit 1
$$;
grant execute on function t_terms_price(text,text) to authenticated;

create or replace function t_task_contractor(p_number text, p_type text)
returns text language sql stable as $$
  select c.name from tasks t
    join contractors c on c.id = t.contractor_id
    join events e on e.id = t.event_id
    join task_types tt on tt.id = t.task_type_id
   where e.event_number = p_number and tt.name = p_type and t.deleted_at is null
   order by t.created_at, t.id limit 1
$$;
grant execute on function t_task_contractor(text,text) to authenticated;

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000f8', false);

\echo '--- אירוע עם משימה נוספת ---'
select t_eq('הייבוא מדווח אירוע אחד',
  (t_import($$[{"customer_id":"10000000-0000-0000-0000-000000000008",
                "event_number":"IMP-1","event_date":"2026-05-01",
                "tasks":[{"task_type":"סידור","worker_count":"4","onsite_start_time":"09:00"}]}]$$::jsonb)
   ->> 'imported')::int, 1);
select t_eq('ומשימה אחת',
  (t_import($$[{"customer_id":"10000000-0000-0000-0000-000000000008",
                "event_number":"IMP-2","event_date":"2026-05-01",
                "tasks":[{"task_type":"סידור","worker_count":"4"}]}]$$::jsonb)
   ->> 'tasks_imported')::int, 1);
-- ההקמה והפירוק נוצרות מהטריגר, והסידור נוסף עליהן
select t_eq('לאירוע יש שלוש משימות: הקמה, פירוק, וסידור',
  (t_import($$[{"customer_id":"10000000-0000-0000-0000-000000000008",
                "event_number":"IMP-3","event_date":"2026-05-01",
                "tasks":[{"task_type":"סידור","worker_count":"4"}]}]$$::jsonb)
   ->> 'task_count')::int, 3);
select t_eq('כמות העובדים מהקובץ נכתבה למשימה',
  t_task_field('IMP-3', 'סידור', 'worker_count'), '4');
select t_eq('תאריך משימה שלא נכתב נלקח מתאריך האירוע',
  t_task_field('IMP-3', 'סידור', 'task_date'), '2026-05-01');

\echo '--- הקמה ופירוק: מילוי ולא הכפלה ---'
select t_eq('שורת הקמה בקובץ אינה מייצרת משימה רביעית',
  (t_import($$[{"customer_id":"10000000-0000-0000-0000-000000000008",
                "event_number":"IMP-4","event_date":"2026-05-02",
                "tasks":[{"task_type":"הקמה","worker_count":"6","hours_count":"4",
                          "onsite_start_time":"08:00","warehouse_start_time":"06:00"},
                         {"task_type":"פירוק","worker_count":"3"}]}]$$::jsonb)
   ->> 'task_count')::int, 2);
select t_eq('שעת היציאה מהמחסן נכתבה להקמה הקיימת',
  t_task_field('IMP-4', 'הקמה', 'warehouse_start_time'), '06:00:00');
select t_eq('כמות העובדים בפירוק התעדכנה',
  t_task_field('IMP-4', 'פירוק', 'worker_count'), '3');
select t_eq('שורת הקמה שנייה באותו קובץ היא משימה נוספת אמיתית',
  (t_import($$[{"customer_id":"10000000-0000-0000-0000-000000000008",
                "event_number":"IMP-5","event_date":"2026-05-03",
                "tasks":[{"task_type":"הקמה","worker_count":"6"},
                         {"task_type":"הקמה","worker_count":"2","onsite_start_time":"14:00"}]}]$$::jsonb)
   ->> 'task_count')::int, 3);
select t_eq('גם ה-code האנגלי מזוהה כסוג משימה',
  (t_import($$[{"customer_id":"10000000-0000-0000-0000-000000000008",
                "event_number":"IMP-6","event_date":"2026-05-04",
                "tasks":[{"task_type":"setup","worker_count":"5"}]}]$$::jsonb)
   ->> 'task_count')::int, 2);

\echo '--- שורה שנפסלה מתגלגלת כולה ---'
select t_eq('סוג משימה לא מוכר מדווח בשגיאה',
  (t_import($$[{"customer_id":"10000000-0000-0000-0000-000000000008",
                "event_number":"IMP-7","event_date":"2026-05-05",
                "tasks":[{"task_type":"קסם שחור"}]}]$$::jsonb)
   ->> 'error_count')::int, 1);
select t_eq('והשגיאה נושאת את מספר המשימה ואת שם הסוג',
  (t_import($$[{"customer_id":"10000000-0000-0000-0000-000000000008",
                "event_number":"IMP-8","event_date":"2026-05-05",
                "tasks":[{"task_type":"סידור"},{"task_type":"קסם שחור"}]}]$$::jsonb)
   ->> 'first_error'), 'משימה 2: סוג משימה לא מוכר: קסם שחור');
select t_eq('האירוע עצמו לא נוצר — לא נשאר אירוע חצי מיובא',
  (t_import($$[{"customer_id":"10000000-0000-0000-0000-000000000008",
                "event_number":"IMP-9","event_date":"2026-05-05",
                "tasks":[{"task_type":"קסם שחור"}]}]$$::jsonb)
   ->> 'event_found')::boolean, false);
-- 'איסוף' מותר לסוגי משימה גנריים אך לא להקמה (0002:131)
select t_eq('אופן ביצוע שאינו מותר לסוג המשימה נפסל',
  (t_import($$[{"customer_id":"10000000-0000-0000-0000-000000000008",
                "event_number":"IMP-10","event_date":"2026-05-06",
                "tasks":[{"task_type":"הקמה","execution_method":"איסוף"}]}]$$::jsonb)
   ->> 'first_error'), 'משימה 1: אופן הביצוע שנבחר אינו זמין עבור הקמה אצל לקוח זה');
select t_eq('אופן ביצוע שמותר לסוג המשימה מתקבל',
  (t_import($$[{"customer_id":"10000000-0000-0000-0000-000000000008",
                "event_number":"IMP-11","event_date":"2026-05-06",
                "tasks":[{"task_type":"הקמה","execution_method":"הובלה בלבד"}]}]$$::jsonb)
   ->> 'error_count')::int, 0);

\echo '--- תאימות לאחור ---'
select t_eq('שורה בלי מפתח tasks מתנהגת כמו קודם',
  (t_import($$[{"customer_id":"10000000-0000-0000-0000-000000000008",
                "event_number":"IMP-12","event_date":"2026-05-07"}]$$::jsonb)
   ->> 'task_count')::int, 2);
select t_eq('ומדווחת אפס משימות מיובאות',
  (t_import($$[{"customer_id":"10000000-0000-0000-0000-000000000008",
                "event_number":"IMP-13","event_date":"2026-05-07"}]$$::jsonb)
   ->> 'tasks_imported')::int, 0);
select t_eq('row_key אינו מגיע ל-create_event ואינו מפיל אותה',
  (t_import($$[{"row_key":"1","customer_id":"10000000-0000-0000-0000-000000000008",
                "event_number":"IMP-14","event_date":"2026-05-07",
                "tasks":[{"task_type":"סידור"}]}]$$::jsonb)
   ->> 'imported')::int, 1);

\echo '--- מחירים, קבלן, מחסן ותוספות (0076) ---'
select t_eq('שורה עם מחיר ללקוח מיובאת בלי שגיאה',
  (t_import($$[{"customer_id":"10000000-0000-0000-0000-000000000008",
                "event_number":"IMP-30","event_date":"2026-06-01",
                "tasks":[{"task_type":"סידור","worker_count":"3","price":"2400"}]}]$$::jsonb)
   ->> 'error_count')::int, 0);
select t_eq('והמחיר ללקוח נכתב למשימה',
  t_task_price('IMP-30', 'סידור'), 2400::numeric);
-- בלי is_manual הטריגר tasks_price היה מחשב מחדש ודורס את מה שנכתב בקובץ
select t_eq('והוא נעול כמחיר ידני',
  t_task_price_manual('IMP-30', 'סידור'), true);

select t_eq('קבלן ומחיר לקבלן מהקובץ מיובאים',
  (t_import($$[{"customer_id":"10000000-0000-0000-0000-000000000008",
                "event_number":"IMP-31","event_date":"2026-06-02",
                "tasks":[{"task_type":"סידור","contractor":"קבלן הייבוא",
                          "contractor_price":"900"}]}]$$::jsonb)
   ->> 'error_count')::int, 0);
select t_eq('המשימה הואצלה לקבלן',
  t_task_contractor('IMP-31', 'סידור'), 'קבלן הייבוא');
-- app.sync_contractor_terms פותחת את השורה על default_task_price=500;
-- 900 הוא מה שהקובץ אמר, כלומר הכתיבה קרתה *אחרי* הטריגר
select t_eq('ומחיר הקבלן מהקובץ גובר על מחיר ברירת המחדל שלו',
  t_terms_price('IMP-31', 'סידור'), 900::numeric);

select t_eq('מחיר לקבלן בלי קבלן הוא שגיאה, ולא כתיבה שנעלמת',
  (t_import($$[{"customer_id":"10000000-0000-0000-0000-000000000008",
                "event_number":"IMP-32","event_date":"2026-06-03",
                "tasks":[{"task_type":"סידור","contractor_price":"900"}]}]$$::jsonb)
   ->> 'first_error'),
  'משימה 1: מחיר לקבלן נכתב בלי קבלן — יש למלא גם את עמודת "קבלן"');
select t_eq('קבלן לא מוכר מדווח בשמו',
  (t_import($$[{"customer_id":"10000000-0000-0000-0000-000000000008",
                "event_number":"IMP-33","event_date":"2026-06-03",
                "tasks":[{"task_type":"סידור","contractor":"קבלן שלא קיים"}]}]$$::jsonb)
   ->> 'first_error'), 'משימה 1: קבלן לא מוכר: קבלן שלא קיים');

select t_eq('מחסן, זמן נסיעה וראש צוות נכתבים למשימה',
  (t_import($$[{"customer_id":"10000000-0000-0000-0000-000000000008",
                "event_number":"IMP-34","event_date":"2026-06-04",
                "tasks":[{"task_type":"סידור","warehouse":"מחסן הייבוא",
                          "travel_hours":"1.5","requires_team_lead":"true"}]}]$$::jsonb)
   ->> 'error_count')::int, 0);
select t_eq('המחסן נפתר לפי שם',
  t_task_field('IMP-34', 'סידור', 'warehouse_id'), '70000000-0000-0000-0000-0000000000f1');
select t_eq('זמן הנסיעה נכתב',
  t_task_field('IMP-34', 'סידור', 'travel_hours'), '1.50');
select t_eq('ודריסת ראש הצוות נכתבה',
  t_task_field('IMP-34', 'סידור', 'requires_team_lead'), 'true');
select t_eq('מחסן לא מוכר מדווח בשמו',
  (t_import($$[{"customer_id":"10000000-0000-0000-0000-000000000008",
                "event_number":"IMP-35","event_date":"2026-06-04",
                "tasks":[{"task_type":"סידור","warehouse":"מחסן שלא קיים"}]}]$$::jsonb)
   ->> 'first_error'), 'משימה 1: מחסן לא מוכר: מחסן שלא קיים');

\echo '--- כן/לא ---'
select t_eq('התוספות של האירוע נקראות מ"כן" ומ"לא"',
  (t_import($$[{"customer_id":"10000000-0000-0000-0000-000000000008",
                "event_number":"IMP-36","event_date":"2026-06-05",
                "no_parking":"כן","porterage":"לא","supplier_pickup":"true"}]$$::jsonb)
   ->> 'error_count')::int, 0);
select t_eq('"כן" נכתב כאמת',   t_event_field('IMP-36', 'no_parking'), 'true');
select t_eq('"לא" נכתב כשקר',   t_event_field('IMP-36', 'porterage'), 'false');
select t_eq('וגם true מתקבל',   t_event_field('IMP-36', 'supplier_pickup'), 'true');
-- תא ריק אינו "לא": המפתח יורד מה-payload ו-create_event לוקחת את ברירת המחדל
select t_eq('תוספת שהתא שלה ריק אינה נכתבת כשקר יזום',
  (t_import($$[{"customer_id":"10000000-0000-0000-0000-000000000008",
                "event_number":"IMP-37","event_date":"2026-06-05","no_parking":""}]$$::jsonb)
   ->> 'error_count')::int, 0);
select t_eq('והיא נשארת על ברירת המחדל', t_event_field('IMP-37', 'no_parking'), 'false');
select t_eq('ערך שאינו כן/לא מפיל את השורה בשם העמודה',
  (t_import($$[{"customer_id":"10000000-0000-0000-0000-000000000008",
                "event_number":"IMP-38","event_date":"2026-06-05","porterage":"אולי"}]$$::jsonb)
   ->> 'first_error'), 'ערך לא חוקי בעמודה "סבלות": אולי — יש לכתוב כן או לא');
select t_eq('וגם בעמודת ראש הצוות שבמשימה',
  (t_import($$[{"customer_id":"10000000-0000-0000-0000-000000000008",
                "event_number":"IMP-39","event_date":"2026-06-05",
                "tasks":[{"task_type":"סידור","requires_team_lead":"אולי"}]}]$$::jsonb)
   ->> 'first_error'),
  'משימה 1: ערך לא חוקי בעמודה "נדרש ראש צוות": אולי — יש לכתוב כן או לא');

\echo '--- ספקים לפי שם ---'
select t_eq('שני ספקים בתא אחד נקשרים לאירוע',
  (t_import($$[{"customer_id":"10000000-0000-0000-0000-000000000008",
                "event_number":"IMP-40","event_date":"2026-06-06",
                "suppliers":"ספק הייבוא, ספק הבמות"}]$$::jsonb)
   ->> 'error_count')::int, 0);
select t_eq('ושניהם נכתבו', t_event_suppliers('IMP-40'), 'ספק הבמות, ספק הייבוא');
-- ההתאמה לפי שם אינה חוצה לקוחות: 'ספק זר' קיים, אבל אצל לקוח אחר
select t_eq('ספק של לקוח אחר נפסל',
  (t_import($$[{"customer_id":"10000000-0000-0000-0000-000000000008",
                "event_number":"IMP-41","event_date":"2026-06-06",
                "suppliers":"ספק זר"}]$$::jsonb)
   ->> 'first_error'), 'ספק לא מוכר אצל לקוח זה: ספק זר');
select t_eq('והאירוע שנשא אותו לא נוצר',
  (t_import($$[{"customer_id":"10000000-0000-0000-0000-000000000008",
                "event_number":"IMP-42","event_date":"2026-06-06",
                "suppliers":"ספק זר"}]$$::jsonb)
   ->> 'event_found')::boolean, false);

\echo '--- ההרשאות ---'
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000f9', false);
select t_expect_ok('בלי tasks.create עדיין אפשר לייבא אירועים בלי משימות',
  $$select bulk_import_events($x$[{"customer_id":"10000000-0000-0000-0000-000000000008",
      "event_number":"IMP-20","event_date":"2026-05-08"}]$x$::jsonb)$$);
select t_expect_fail('בלי tasks.create ייבוא שנושא משימות נדחה',
  $$select bulk_import_events($x$[{"customer_id":"10000000-0000-0000-0000-000000000008",
      "event_number":"IMP-21","event_date":"2026-05-08",
      "tasks":[{"task_type":"סידור"}]}]$x$::jsonb)$$);
select t_eq('והאירוע שנשא אותן לא נוצר',
  (select count(*) from events where event_number = 'IMP-21' and deleted_at is null), 0::bigint);

-- fb מייבא אירועים ומשימות, אבל אין לו אף מפתח כסף. שלוש העמודות נבדקות
-- מראש ולכן הן מפילות את *כל* הקריאה, ולא שורה בודדת בתוכה.
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000fc', false);
select t_expect_ok('בלי מפתחות כסף אפשר לייבא משימה רגילה',
  $$select bulk_import_events($x$[{"customer_id":"10000000-0000-0000-0000-000000000008",
      "event_number":"IMP-50","event_date":"2026-06-10",
      "tasks":[{"task_type":"סידור","worker_count":"2"}]}]$x$::jsonb)$$);
select t_expect_fail('בלי pricing.edit קובץ שנושא מחיר ללקוח נדחה',
  $$select bulk_import_events($x$[{"customer_id":"10000000-0000-0000-0000-000000000008",
      "event_number":"IMP-51","event_date":"2026-06-10",
      "tasks":[{"task_type":"סידור","price":"1000"}]}]$x$::jsonb)$$);
select t_eq('והאירוע שנשא אותו לא נוצר',
  (select count(*) from events where event_number = 'IMP-51' and deleted_at is null), 0::bigint);
-- זמן נסיעה הוא דריסה של מנוע התמחור, ורשום תחת אותו מפתח
select t_expect_fail('בלי pricing.edit גם זמן נסיעה נדחה',
  $$select bulk_import_events($x$[{"customer_id":"10000000-0000-0000-0000-000000000008",
      "event_number":"IMP-52","event_date":"2026-06-10",
      "tasks":[{"task_type":"סידור","travel_hours":"1"}]}]$x$::jsonb)$$);
select t_expect_fail('בלי tasks.delegate קובץ שנושא קבלן נדחה',
  $$select bulk_import_events($x$[{"customer_id":"10000000-0000-0000-0000-000000000008",
      "event_number":"IMP-53","event_date":"2026-06-10",
      "tasks":[{"task_type":"סידור","contractor":"קבלן הייבוא"}]}]$x$::jsonb)$$);
select t_expect_fail('בלי contractors.edit_pricing קובץ שנושא מחיר לקבלן נדחה',
  $$select bulk_import_events($x$[{"customer_id":"10000000-0000-0000-0000-000000000008",
      "event_number":"IMP-54","event_date":"2026-06-10",
      "tasks":[{"task_type":"סידור","contractor":"קבלן הייבוא","contractor_price":"900"}]}]$x$::jsonb)$$);

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000fa', false);
select t_expect_fail('איש צוות בלי events.import אינו יכול לייבא כלל',
  $$select bulk_import_events($x$[{"customer_id":"10000000-0000-0000-0000-000000000008",
      "event_number":"IMP-22","event_date":"2026-05-09"}]$x$::jsonb)$$);

set role anon;
select set_config('request.jwt.claim.sub', '', false);
select t_expect_fail('anon אינו יכול להריץ את הייבוא',
  $$select bulk_import_events($x$[]$x$::jsonb)$$);

\echo '--- מחיר מהקובץ מול מחשבון אוטומטי ---'
-- הלקוח השני עובר ל-pricing_mode='auto' עם מחשבון להקמה ולפירוק. זו הבדיקה
-- שכל סעיף 3 של 0076 עומד עליה: ה-UPDATE שכותב את השעות מפעיל את tasks_price,
-- והמחיר מהקובץ נכתב אחריו ונעול — אחרת המחשבון היה דורס אותו באותה שורה.
reset role;
select set_config('request.jwt.claim.sub', '', false);
update customers set pricing_mode = 'auto' where id = '10000000-0000-0000-0000-000000000009';
insert into customer_pricing_rules (customer_id, task_type_id, config)
select '10000000-0000-0000-0000-000000000009', tt.id, app.default_pricing_config(tt.code)
  from task_types tt where tt.code in ('setup', 'teardown');

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000f8', false);
select t_eq('אירוע ללקוח עם מחשבון אוטומטי מיובא',
  (t_import($$[{"customer_id":"10000000-0000-0000-0000-000000000009",
                "event_number":"IMP-60","event_date":"2026-06-20","truck_count":"2",
                "tasks":[{"task_type":"הקמה","worker_count":"4","hours_count":"4","price":"3333"},
                         {"task_type":"פירוק","worker_count":"4","hours_count":"2"}]}]$$::jsonb)
   ->> 'error_count')::int, 0);
select t_eq('המחיר מהקובץ גובר על מה שהמחשבון חישב באותו UPDATE',
  t_task_price('IMP-60', 'הקמה'), 3333::numeric);
select t_eq('והוא נעול', t_task_price_manual('IMP-60', 'הקמה'), true);
select t_eq('הפירוק, שלא נכתב לו מחיר, חושב מהמחשבון ונשאר פתוח',
  t_task_price_manual('IMP-60', 'פירוק'), false);
select t_eq('ולפירוק אכן חושב מחיר',
  (t_task_price('IMP-60', 'פירוק') > 0), true);

reset role;
