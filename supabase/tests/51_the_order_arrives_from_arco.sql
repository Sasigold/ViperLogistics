\pset tuples_only on
\pset format unaligned

-- ===========================================================================
-- 51: ההזמנה מגיעה מארקו — תרגום, מחיר, מפרט ודיווח חזרה (0182‏–0184).
--
-- החבילה מקימה לקוח, חיבור, מחשבון מחירים ושלושה פרופילים משלה ואינה נשענת
-- על אף חבילה קודמת. האירוע יושב על תאריכים קבועים ולא על `current_date + N`,
-- מאותו נימוק של חבילה 49: חצי מהבדיקה כאן היא על המרת אזור זמן, ותאריך שזז
-- עם יום ההרצה אינו יכול לאשר שהיא נכונה. היא רצה אחרונה כי היא משאירה
-- אחריה אירוע, משימות, מפרט, משלוחים ותור דיווח שאינם מנוקים.
-- ===========================================================================

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000051a1', 'arco-ops@vl.test'),
  ('00000000-0000-0000-0000-0000000051a2', 'arco-coord@vl.test');

insert into customers (id, name, pricing_mode, performed_by_enabled) values
  ('10000000-0000-0000-0000-000000000051', 'ארקו 51', 'auto', true);

insert into customer_pricing_rules (customer_id, task_type_id, config)
select '10000000-0000-0000-0000-000000000051', tt.id, app.default_pricing_config(tt.code)
  from task_types tt where tt.code in ('setup', 'teardown');

insert into profiles (id, user_id, user_kind, is_admin, full_name) values
  -- מנהל אינטגרציות: integrations.view + manage
  ('20000000-0000-0000-0000-0000000051a1', '00000000-0000-0000-0000-0000000051a1',
   'staff', false, 'מנהל אינטגרציות 51'),
  -- רכז: רואה אירועים, ואינו רואה את מסך החיבורים
  ('20000000-0000-0000-0000-0000000051a2', '00000000-0000-0000-0000-0000000051a2',
   'staff', false, 'רכז 51');

insert into user_permission_grants (profile_id, permission_key, allowed) values
  ('20000000-0000-0000-0000-0000000051a1', 'integrations.view', true),
  ('20000000-0000-0000-0000-0000000051a1', 'integrations.manage', true),
  ('20000000-0000-0000-0000-0000000051a2', 'events.view', true),
  ('20000000-0000-0000-0000-0000000051a2', 'integrations.view', false);


\echo '--- 1. החיבור נפתח, ורק בידי מי שמחזיק את המפתח ---'

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000051a2', false);
select t_expect_fail('רכז אינו פותח חיבור',
  $$select arco_set_connection('10000000-0000-0000-0000-000000000051', 'ניסיון')$$);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000051a1', false);
select t_expect_ok('מנהל אינטגרציות פותח חיבור',
  $$select arco_set_connection('10000000-0000-0000-0000-000000000051', 'ארקו 51')$$);
reset role;
select set_config('request.jwt.claim.sub', '', false);

create temporary table ak51 as
  select id as connection_id from arco_connections
   where customer_id = '10000000-0000-0000-0000-000000000051';
grant select on ak51 to authenticated;


\echo '--- 2. ההזמנה נעשית אירוע, ושתי המשימות שלו ---'

-- המעטפה כאן היא **בדיוק** בצורה שארקו שולחת: `DD/MM/YYYY` לתאריך,
-- ‏`DD/MM/YYYY HH:MM` לשעה, ובוליאני כ-`"1"` או כמחרוזת ריקה. הפירוק נשלח
-- כתאריך בלי שעה — וחצות אינה שעה (0183 §1), ולכן השעה נשארת ריקה.
\o /dev/null
select arco_ingest_event(jsonb_build_object(
  'order_number',                     '  #26-000233 ',
  'customer_name',                    'קבוצת אינטלקט',
  'location',                         'ירושלים',
  'location_notes',                   'כניסה מהחניון',
  'order_date',                       '02/10/2026',
  'event_status',                     'טרם אושר',
  'truck_quantity',                   '2',
  'volume',                           '15',
  'parking',                          '1',
  'porterage',                        '',
  'supplier_collection',              '0',
  'operational_contact_name',         'עינת',
  'operational_contact_phone',        '0528390829',
  'operational_notes',                'לתאם מעלית',
  'setup_date_and_time',              '01/10/2026 08:00',
  'setup_method',                     'הובלה בלבד',
  'setup_crew_size',                  '3',
  'setup_hours_quantity',             '4',
  'setup_execution_contractor',       'וייפר',
  'dismantling_date_and_time',        '03/10/2026',
  'dismantling_method',               'פירוק בלבד',
  'dismantling_crew_size',            '2',
  'dismantling_hours_quantity',       '3',
  'dismantling_execution_contractor', 'ארקו 51'),
  jsonb_build_object('connection_id', (select connection_id from ak51)));
\o

create temporary table ae51 as
  select id as event_id from events
   where customer_id = '10000000-0000-0000-0000-000000000051'
     and event_number = '26000233' and deleted_at is null;
grant select on ae51 to authenticated;

select t_eq('נפתח אירוע אחד', (select count(*)::int from ae51), 1);
select t_eq('מספר ההזמנה נשמר ספרות בלבד',
  (select event_number from events where id = (select event_id from ae51)), '26000233');
select t_eq('תאריך האירוע עבר דרך אזור הזמן',
  (select event_date from events where id = (select event_id from ae51)), '2026-10-02'::date);
select t_eq('הלקוח הסופי נשמר',
  (select end_client_name from events where id = (select event_id from ae51)), 'קבוצת אינטלקט');
select t_eq('כמות המשאיות',
  (select truck_count from events where id = (select event_id from ae51)), 2);
select t_eq('הנפח',
  (select volume_m from events where id = (select event_id from ae51)), 15::numeric);
select t_eq('חניה נרשמה כתוספת התמחור',
  (select no_parking from events where id = (select event_id from ae51)), true);
select t_eq('הערת המשרד נכתבה בלידה',
  (select notes from events where id = (select event_id from ae51)), 'לתאם מעלית');
select t_eq('איש הקשר נשמר',
  (select contact_phone from event_contacts where event_id = (select event_id from ae51)),
  '0528390829');
select t_eq('הסטטוס לפי מה שארקו שלחה',
  (select s.name from events e join statuses s on s.id = e.status_id
    where e.id = (select event_id from ae51)), 'טרם אושר');

select t_eq('נוצרו שתי משימות', (select count(*)::int from tasks
  where event_id = (select event_id from ae51) and deleted_at is null), 2);

create or replace function t51_task(p_code text, p_col text)
returns text language plpgsql as $$
declare v text;
begin
  execute format(
    'select (to_jsonb(t) ->> %L) from tasks t join task_types tt on tt.id = t.task_type_id
      where t.event_id = (select event_id from ae51) and tt.code = %L
        and t.deleted_at is null', p_col, p_code) into v;
  return v;
end $$;

select t_eq('ההקמה ביום ההקמה', t51_task('setup', 'task_date'), '2026-10-01');
select t_eq('ובשעה שנשלחה', t51_task('setup', 'onsite_start_time'), '08:00:00');
select t_eq('כמות העובדים בהקמה', t51_task('setup', 'worker_count'), '3');
select t_eq('שעות ההקמה', t51_task('setup', 'hours_count'), '4.00');
select t_eq('אופן הביצוע תורגם לפי שמו',
  (select m.name from tasks t join execution_methods m on m.id = t.execution_method_id
     join task_types tt on tt.id = t.task_type_id
    where t.event_id = (select event_id from ae51) and tt.code = 'setup'), 'הובלה בלבד');
select t_eq('ההקמה מבוצעת ע״י וייפר', t51_task('setup', 'performed_by'), 'viper');

select t_eq('הפירוק ביום שאחרי, אחרי ההמרה', t51_task('teardown', 'task_date'), '2026-10-03');
select t_eq('וחצות אינה שעה — השעה נשארה ריקה', t51_task('teardown', 'onsite_start_time'), null);
select t_eq('שם הלקוח כמבצע ⇒ הפירוק הוא של ארקו',
  t51_task('teardown', 'performed_by'), 'arko');

-- ‏`warehouse_start_time` אינה נשלחת מארקו ואינה נכתבת כאן (0183 §2).
select t_eq('שעת היציאה מהמחסן נשארה שלנו', t51_task('setup', 'warehouse_start_time'), null);


\echo '--- 3. המחיר: מה שהמנוע חישב, וזה מה שחוזר ---'

select t_eq('להקמה חושב מחיר',
  (select tp.price > 0 from task_pricing tp join tasks t on t.id = tp.task_id
     join task_types tt on tt.id = t.task_type_id
    where t.event_id = (select event_id from ae51) and tt.code = 'setup'), true);

-- משימה שהלקוח מבצע בעצמו שווה 0 (0120), וזה מה שנשלח חזרה.
select t_eq('ומשימת ארקו שווה אפס',
  (select tp.price from task_pricing tp join tasks t on t.id = tp.task_id
     join task_types tt on tt.id = t.task_type_id
    where t.event_id = (select event_id from ae51) and tt.code = 'teardown'), 0::numeric);

create temporary table asnap51 as
  select app.arco_event_snapshot((select event_id from ae51)) as snap;

select t_eq('התמונה מחזירה שתי משימות',
  (select jsonb_array_length(snap -> 'tasks') from asnap51), 2);
select t_eq('והסכום הוא סכום המשימות',
  (select (snap ->> 'total_price')::numeric from asnap51),
  (select coalesce(sum(tp.price), 0) from task_pricing tp join tasks t on t.id = tp.task_id
    where t.event_id = (select event_id from ae51) and t.deleted_at is null));
select t_eq('והמטבע נאמר במפורש', (select snap ->> 'currency' from asnap51), 'ILS');


\echo '--- 4. אותה הזמנה שוב אינה אירוע שני (והפעם בתאריך ISO) ---'

\o /dev/null
select arco_ingest_event(jsonb_build_object(
  'order_number',  '26000233',
  'location',      'תל אביב',
  'order_date',    '2026-10-01T21:00:00.000Z',
  'truck_quantity', 4,
  'operational_notes', 'הערה שהגיעה מאוחר'),
  jsonb_build_object('connection_id', (select connection_id from ak51)));
\o

select t_eq('עדיין אירוע אחד', (select count(*)::int from events
  where customer_id = '10000000-0000-0000-0000-000000000051' and deleted_at is null), 1);
select t_eq('והשדה שארקו מחזיקה נדרס',
  (select truck_count from events where id = (select event_id from ae51)), 4);
select t_eq('והמיקום התעדכן',
  (select location_text from events where id = (select event_id from ae51)), 'תל אביב');
-- §4 בכותרת של 0183: הערה של רכז אינה נמחקת בגלל שההזמנה השתנתה.
select t_eq('והערת המשרד לא נדרסה',
  (select notes from events where id = (select event_id from ae51)), 'לתאם מעלית');
-- מעטפה שלא נשאה את שעת ההקמה אינה אומרת עליה דבר, וגם לא "ביום האירוע".
select t_eq('ומשלוח חלקי לא גרר את ההקמה בחזרה ליום האירוע',
  t51_task('setup', 'task_date'), '2026-10-01');
select t_eq('ולא את הפירוק', t51_task('teardown', 'task_date'), '2026-10-03');

select t_eq('המשלוח נרשם כמוחל',
  (select status from arco_deliveries where kind = 'event'
    order by received_at desc limit 1), 'applied');


\echo '--- 5. הסטטוס זז קדימה, ולא אחורה ---'

update events set status_id = (select id from statuses
  where entity = 'event' and btrim(name) = 'מתקיים' and deleted_at is null)
 where id = (select event_id from ae51);

\o /dev/null
select arco_ingest_event(jsonb_build_object(
  'order_number', '26000233', 'order_date', '2026-10-01T21:00:00.000Z',
  'event_status', 'אישור סופי'),
  jsonb_build_object('connection_id', (select connection_id from ak51)));
\o

select t_eq('אירוע שהמשרד קידם אינו חוזר אחורה',
  (select s.name from events e join statuses s on s.id = e.status_id
    where e.id = (select event_id from ae51)), 'מתקיים');

\o /dev/null
select arco_ingest_event(jsonb_build_object(
  'order_number', '26000233', 'order_date', '2026-10-01T21:00:00.000Z',
  'event_status', 'בוטל'),
  jsonb_build_object('connection_id', (select connection_id from ak51)));
\o

select t_eq('אבל ביטול מבטל — תמיד',
  (select s.name from events e join statuses s on s.id = e.status_id
    where e.id = (select event_id from ae51)), 'בוטל');

update events set status_id = (select id from statuses
  where entity = 'event' and btrim(name) = 'טרם אושר' and deleted_at is null)
 where id = (select event_id from ae51);


\echo '--- 6. המפרט נרשם כגרסה, ולא פעמיים ---'

\o /dev/null
select arco_ingest_spec(jsonb_build_object(
  'order_number', '26000233',
  'file',         'https://live-public.origamicloud.ms/file/?f=aaa'),
  jsonb_build_object('connection_id', (select connection_id from ak51)));
\o

select t_eq('נרשמה גרסת מפרט אחת',
  (select count(*)::int from event_specs where event_id = (select event_id from ae51)), 1);
select t_eq('והיא קישור',
  (select source from event_specs where event_id = (select event_id from ae51)), 'link');

\o /dev/null
select arco_ingest_spec(jsonb_build_object(
  'order_number', '26000233',
  'file',         'https://live-public.origamicloud.ms/file/?f=aaa'),
  jsonb_build_object('connection_id', (select connection_id from ak51)));
\o
select t_eq('אותו קישור שוב אינו גרסה שנייה',
  (select count(*)::int from event_specs where event_id = (select event_id from ae51)), 1);

\o /dev/null
select arco_ingest_spec(jsonb_build_object(
  'order_number', '26000233',
  'file',         'https://live-public.origamicloud.ms/file/?f=bbb'),
  jsonb_build_object('connection_id', (select connection_id from ak51)));
\o
select t_eq('אבל מפרט מוחלף כן',
  (select count(*)::int from event_specs where event_id = (select event_id from ae51)), 2);

select t_eq('מפרט להזמנה שאין לה אירוע אינו שגיאה אלא שורה שממתינה',
  (select arco_ingest_spec(jsonb_build_object(
     'order_number', '99999999', 'file', 'https://example.com/x.pdf'),
     jsonb_build_object('connection_id', (select connection_id from ak51))) ->> 'status'),
  'ignored');

select t_eq('וקישור שאינו כתובת נופל כשורה אדומה',
  (select arco_ingest_spec(jsonb_build_object(
     'order_number', '26000233', 'file', 'לא כתובת'),
     jsonb_build_object('connection_id', (select connection_id from ak51))) ->> 'status'),
  'failed');


\echo '--- 7. כל שינוי באירוע נכנס לתור הדיווח ---'

-- מה שנכנס דרך ארקו מסומן `arco`; מה שהמשרד עשה מסומן `viper`. התרחיש
-- בצד השני הוא שמחליט אם הוא רוצה את ההד של עצמו.
select t_eq('הקליטה עצמה דיווחה על עצמה',
  (select count(*) > 0 from arco_outbound
    where event_id = (select event_id from ae51) and origin = 'arco'), true);

create temporary table ao51 as
  select count(*)::int as n from arco_outbound where event_id = (select event_id from ae51);

-- שמירה אחת שנגעה בשלושה שדות — הודעה אחת, שלושה שינויים.
update events set location_notes = 'חניון תת-קרקעי',
                  porterage = true,
                  volume_m = 22
 where id = (select event_id from ae51);

select t_eq('שמירה אחת = הודעה אחת',
  (select count(*)::int from arco_outbound where event_id = (select event_id from ae51)),
  (select n + 1 from ao51));

select t_eq('וההודעה נושאת את שלושת השינויים',
  (select jsonb_array_length(changes) from arco_outbound
    where event_id = (select event_id from ae51) order by created_at desc limit 1), 3);

select t_eq('ומסומנת כשינוי שלנו',
  (select origin from arco_outbound
    where event_id = (select event_id from ae51) order by created_at desc limit 1), 'viper');

-- שינוי בשדה של משימה הוא שינוי באירוע (0112), ולכן הוא מדווח גם הוא.
update tasks set worker_count = 5
 where event_id = (select event_id from ae51)
   and task_type_id = (select id from task_types where code = 'setup');

select t_eq('גם שינוי במשימה מדווח',
  (select count(*)::int from arco_outbound where event_id = (select event_id from ae51)),
  (select n + 2 from ao51));

select t_eq('וההודעה שממתינה נושאת את האירוע ואת המחירים שלו',
  (select (m -> 'event' -> 'tasks') is not null
     from jsonb_array_elements(arco_outbound_pending(50)) m limit 1), true);

-- לקוח אחר אינו נכנס לתור: החיבור הוא שקובע, לא השם.
insert into customers (id, name) values
  ('10000000-0000-0000-0000-000000000052', 'לקוח אחר 51');
insert into events (id, customer_id, event_date, event_number)
values ('30000000-0000-0000-0000-000000000051',
        '10000000-0000-0000-0000-000000000052', '2026-10-02', 'X51');
update events set volume_m = 9 where id = '30000000-0000-0000-0000-000000000051';
select t_eq('אירוע של לקוח בלי חיבור אינו מדווח',
  (select count(*)::int from arco_outbound
    where event_id = '30000000-0000-0000-0000-000000000051'), 0);

-- וכיבוי הדיווח עוצר אותו בלי לעצור את הקליטה.
update arco_connections set notify_updates = false
 where id = (select connection_id from ak51);
update events set location_notes = 'ללא דיווח'
 where id = (select event_id from ae51);
select t_eq('חיבור שכיבה את הדיווח שותק',
  (select count(*)::int from arco_outbound where event_id = (select event_id from ae51)),
  (select n + 2 from ao51));
update arco_connections set notify_updates = true
 where id = (select connection_id from ak51);


\echo '--- 8. החיבור כבוי: נרשם, ולא מתורגם ---'

update arco_connections set is_active = false where id = (select connection_id from ak51);
select t_eq('משלוח לחיבור כבוי מסומן ignored',
  (select arco_ingest_event(jsonb_build_object(
     'order_number', '26000999', 'order_date', '2026-10-01T21:00:00.000Z'),
     jsonb_build_object('connection_id', (select connection_id from ak51))) ->> 'status'),
  'ignored');
select t_eq('ולא נפתח ממנו אירוע',
  (select count(*)::int from events
    where customer_id = '10000000-0000-0000-0000-000000000051'
      and event_number = '26000999'), 0);
select t_eq('אבל המעטפה נשמרה להרצה מחדש',
  (select count(*)::int from arco_deliveries where order_number = '26000999'), 1);
update arco_connections set is_active = true where id = (select connection_id from ak51);


\echo '--- 9. הזמנה בלי מספר או בלי תאריך נופלת כשורה אדומה, ולא כשגיאת HTTP ---'

select t_eq('בלי מספר הזמנה',
  (select arco_ingest_event(jsonb_build_object('order_date', '2026-10-01T21:00:00.000Z'),
     jsonb_build_object('connection_id', (select connection_id from ak51))) ->> 'status'),
  'failed');
select t_eq('בלי תאריך',
  (select arco_ingest_event(jsonb_build_object('order_number', '26000888'),
     jsonb_build_object('connection_id', (select connection_id from ak51))) ->> 'status'),
  'failed');


\echo '--- 9א. שדה מקולקל אינו מפיל הזמנה שלמה ---'

-- ‏"[object Object]" אינו המצאה: כך נראה בדוגמה השמורה ב-Make שדה מספרי
-- שהצד השני שלח לתוכו אובייקט. ההזמנה נפתחת, והשדה פשוט אינו ידוע.
\o /dev/null
select arco_ingest_event(jsonb_build_object(
  'order_number',   '26000777',
  'order_date',     '05/10/2026',
  'truck_quantity', '[object Object]',
  'volume',         '',
  'parking',        'אולי'),
  jsonb_build_object('connection_id', (select connection_id from ak51)));
\o

select t_eq('ההזמנה נפתחה בכל זאת',
  (select count(*)::int from events
    where customer_id = '10000000-0000-0000-0000-000000000051'
      and event_number = '26000777' and deleted_at is null), 1);
select t_eq('והשדה המקולקל נשאר ריק',
  (select truck_count from events
    where customer_id = '10000000-0000-0000-0000-000000000051'
      and event_number = '26000777'), null::int);
select t_eq('ובוליאני שאינו מוכר אינו "כן"',
  (select no_parking from events
    where customer_id = '10000000-0000-0000-0000-000000000051'
      and event_number = '26000777'), false);
select t_eq('והתאריך נקרא בצורה שארקו שולחת',
  (select event_date from events
    where customer_id = '10000000-0000-0000-0000-000000000051'
      and event_number = '26000777'), '2026-10-05'::date);


\echo '--- 10. מי רואה את הצינור ---'

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000051a2', false);
select t_eq('רכז אינו רואה משלוחים', (select count(*)::int from arco_deliveries), 0);
select t_eq('ואינו רואה את תור הדיווח', (select count(*)::int from arco_outbound), 0);
select t_eq('ואינו רואה את החיבור', (select count(*)::int from arco_connections), 0);
select t_expect_fail('ואינו מזרים הזמנות',
  $$select arco_ingest_event('{"order_number":"1","order_date":"2026-10-01T21:00:00.000Z"}'::jsonb)$$);
select t_expect_fail('ואינו מריץ מחדש',
  $$select arco_replay((select id from arco_deliveries limit 1))$$);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000051a1', false);
select t_eq('מנהל האינטגרציות רואה',
  (select count(*) > 0 from arco_deliveries), true);
select t_eq('ומצב החיבור נקרא לו',
  (select jsonb_array_length(arco_connection_status()) > 0), true);

reset role;
select set_config('request.jwt.claim.sub', '', false);
