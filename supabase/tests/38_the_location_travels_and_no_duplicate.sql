\pset tuples_only on
\pset format unaligned

-- ===========================================================================
-- 38: המיקום של האירוע נוסע למשימות (0158), ושכפול האירוע ירד (0157).
--
-- החבילה מקימה לקוח, אירוע ושתי דמויות משלה ב-`current_date + 550`, מעבר לכל
-- טווח שחבילה אחרת נוגעת בו. היא משאירה אחריה משימות שאינן מנוקות.
--
-- שלוש המשימות הן שלושת המצבים שהמיקום יכול להיות בהם, ולא שלוש וריאציות
-- על אותו דבר:
--
--   * ‏**העתק** — משימה שהמיקום שלה הוא בדיוק מה שהאירוע אמר. כך נולדו
--     משימות של אירוע משוכפל (0006) ושל ייבוא שמילא את עמודת "מיקום
--     המשימה", וזו המשימה שהפסיקה לעקוב אחרי האירוע.
--   * ‏**דריסה** — מיקום אחר לגמרי. הקמה במחסן בזמן שהאירוע באולם היא
--     הכרעה, ואסור לה להימחק.
--   * ‏**ריק** — יורש דרך ה-coalesce של הלו״ז מאז 0005, ואמור להישאר ריק:
--     כתיבת ערך אליו הייתה מקפיאה אותו.
--
-- העריכה נעשית בידי **רכז שאין לו `tasks.change_location`**, וזה לב הבדיקה
-- ולא פרט: מי שרשאי לערוך את מיקום האירוע אינו נדרש להחזיק גם את מפתח
-- הלו״ז, והמעבר דרך `app.system_write` הוא מה שמאפשר זאת בלי לפתוח את
-- העמודה לכתיבה ישירה.
-- ===========================================================================

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000038a1', 'c38-admin@vl.test'),
  ('00000000-0000-0000-0000-0000000038a2', 'c38-office@vl.test');

insert into customers (id, name) values
  ('10000000-0000-0000-0000-000000000381', 'לקוח 38');

insert into profiles (id, user_id, user_kind, is_admin, full_name) values
  ('20000000-0000-0000-0000-0000000038a1', '00000000-0000-0000-0000-0000000038a1', 'staff', true,  'מנהל 38'),
  ('20000000-0000-0000-0000-0000000038a2', '00000000-0000-0000-0000-0000000038a2', 'staff', false, 'רכז 38');

-- ‏`events.edit` בלבד. ‏`tasks.change_location` נדחה במפורש ולא רק "לא ניתן",
-- כדי שהבדיקה תעמוד גם אם ברירת המחדל של המפתח תשתנה יום אחד.
insert into user_permission_grants (profile_id, permission_key, allowed) values
  ('20000000-0000-0000-0000-0000000038a2', 'events.edit', true),
  ('20000000-0000-0000-0000-0000000038a2', 'tasks.change_location', false);

insert into events (id, customer_id, event_number, event_date, end_client_name, location_text, status_id)
values ('30000000-0000-0000-0000-000000000381', '10000000-0000-0000-0000-000000000381',
        'EV-38', current_date + 550, 'קצה 38', 'אולם הדקל, ראשון לציון',
        (select id from statuses where entity = 'event' and code = 'pending' and deleted_at is null));

insert into tasks (id, event_id, customer_id, task_type_id, task_date, status_id, location_text)
select v.tid,
       '30000000-0000-0000-0000-000000000381',
       '10000000-0000-0000-0000-000000000381',
       (select id from task_types order by sort_order limit 1),
       current_date + 550,
       (select id from statuses where entity = 'task' order by sort_order limit 1),
       v.loc
  from (values
    ('40000000-0000-0000-0000-000000000381'::uuid, 'אולם הדקל, ראשון לציון'),  -- העתק
    ('40000000-0000-0000-0000-000000000382'::uuid, 'מחסן צפון'),               -- דריסה
    ('40000000-0000-0000-0000-000000000383'::uuid, null)                       -- ריק
  ) as v(tid, loc);


\echo '--- הרכז אינו מחזיק את מפתח מיקום המשימה ---'

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000038a2', false);

select t_eq('לרכז 38 אין tasks.change_location', app.has('tasks.change_location'), false);
select t_eq('אבל יש לו events.edit', app.has('events.edit'), true);

\echo '--- שינוי המיקום באירוע נוסע להעתק, ולא לדריסה ולא לריק ---'

select t_expect_ok('הרכז משנה את מיקום האירוע',
  $$select update_event('30000000-0000-0000-0000-000000000381',
      '{"location_text": "היכל התרבות, חיפה"}'::jsonb)$$);

reset role;
select set_config('request.jwt.claim.sub', '', false);

select t_eq('האירוע נושא את המיקום החדש',
  (select location_text from events where id = '30000000-0000-0000-0000-000000000381'),
  'היכל התרבות, חיפה');
select t_eq('המשימה שנשאה העתק עברה איתו',
  (select location_text from tasks where id = '40000000-0000-0000-0000-000000000381'),
  'היכל התרבות, חיפה');
select t_eq('המשימה עם מיקום משלה לא נגעו בה',
  (select location_text from tasks where id = '40000000-0000-0000-0000-000000000382'),
  'מחסן צפון');
select t_eq('והמשימה בלי מיקום נשארה בלי מיקום',
  (select location_text from tasks where id = '40000000-0000-0000-0000-000000000383'),
  null::text);

-- הריק אינו "לא עודכן" אלא "יורש": הלו״ז מציג לו את מיקום האירוע החדש.
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000038a1', false);
select t_eq('ובלו״ז היא מציגה את המיקום החדש של האירוע',
  (select location_text from work_board_view
    where id = '40000000-0000-0000-0000-000000000383'),
  'היכל התרבות, חיפה');
reset role;
select set_config('request.jwt.claim.sub', '', false);


\echo '--- שמירה שאינה נוגעת במיקום אינה מזיזה דבר ---'

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000038a2', false);
select t_expect_ok('שמירה של שם לקוח הקצה בלבד',
  $$select update_event('30000000-0000-0000-0000-000000000381',
      '{"end_client_name": "קצה 38 מעודכן"}'::jsonb)$$);
reset role;
select set_config('request.jwt.claim.sub', '', false);

select t_eq('הדריסה שרדה גם את השמירה הזאת',
  (select location_text from tasks where id = '40000000-0000-0000-0000-000000000382'),
  'מחסן צפון');


\echo '--- ריקון המיקום באירוע מרוקן את ההעתקים ומחזיר אותם לירושה ---'

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000038a2', false);
select t_expect_ok('הרכז מרוקן את מיקום האירוע',
  $$select update_event('30000000-0000-0000-0000-000000000381',
      '{"location_text": ""}'::jsonb)$$);
reset role;
select set_config('request.jwt.claim.sub', '', false);

select t_eq('לאירוע אין עוד מיקום',
  (select location_text from events where id = '30000000-0000-0000-0000-000000000381'), null::text);
select t_eq('וההעתק התרוקן איתו',
  (select location_text from tasks where id = '40000000-0000-0000-0000-000000000381'), null::text);
select t_eq('והדריסה עדיין שם',
  (select location_text from tasks where id = '40000000-0000-0000-0000-000000000382'), 'מחסן צפון');


\echo '--- שכפול אירוע ירד מהמערכת (0157) ---'

select t_eq('duplicate_event אינה קיימת עוד',
  (select count(*)::int from pg_proc p
     join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'duplicate_event'),
  0);

select t_eq('והמפתח events.duplicate ירד מהמרשם הפעיל',
  (select is_active from permission_registry where key = 'events.duplicate'), false);

-- המפתח לא נמחק: שורות ההרשאה שנכתבו עליו הן תיעוד, ומחיקה הייתה גוררת אותן.
select t_eq('אבל השורה עצמה נשארה במרשם',
  (select count(*)::int from permission_registry where key = 'events.duplicate'), 1);
