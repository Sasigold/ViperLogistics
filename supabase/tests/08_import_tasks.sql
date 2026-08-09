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
  ('00000000-0000-0000-0000-0000000000fa', 'no-import@vl.test');

insert into customers (id, name, can_create_events) values
  ('10000000-0000-0000-0000-000000000008', 'לקוח הייבוא', true);

insert into profiles (id, user_id, user_kind, is_admin, full_name) values
  ('20000000-0000-0000-0000-0000000000f8', '00000000-0000-0000-0000-0000000000f8',
   'staff', false, 'מייבא'),
  ('20000000-0000-0000-0000-0000000000f9', '00000000-0000-0000-0000-0000000000f9',
   'staff', false, 'מייבא בלי משימות'),
  ('20000000-0000-0000-0000-0000000000fa', '00000000-0000-0000-0000-0000000000fa',
   'staff', false, 'בלי ייבוא כלל');

insert into user_permission_grants (profile_id, permission_key, allowed) values
  ('20000000-0000-0000-0000-0000000000f8', 'events.view',   true),
  ('20000000-0000-0000-0000-0000000000f8', 'events.create', true),
  ('20000000-0000-0000-0000-0000000000f8', 'events.import', true),
  ('20000000-0000-0000-0000-0000000000f8', 'tasks.view',    true),
  ('20000000-0000-0000-0000-0000000000f8', 'tasks.create',  true),
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

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000fa', false);
select t_expect_fail('איש צוות בלי events.import אינו יכול לייבא כלל',
  $$select bulk_import_events($x$[{"customer_id":"10000000-0000-0000-0000-000000000008",
      "event_number":"IMP-22","event_date":"2026-05-09"}]$x$::jsonb)$$);

set role anon;
select set_config('request.jwt.claim.sub', '', false);
select t_expect_fail('anon אינו יכול להריץ את הייבוא',
  $$select bulk_import_events($x$[]$x$::jsonb)$$);

reset role;
