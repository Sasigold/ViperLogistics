\pset tuples_only on
\pset format unaligned

-- ================= מנוע החישוב (פונקציה טהורה) =================
-- רץ כ-postgres: אין כאן RLS לבדוק, רק אריתמטיקה.

\echo '--- worker_hours: הנוסחה המלאה של הקמה ---'
-- 3 משאיות ⇒ 1 + 2×0.5 = 2 ש׳ · נסיעה 0.5×2 = 1 · עבודה 4 · הפסקה 0.5
-- ספייר 0.5 · מחסן בסיום 0.5 + 2×0.25 = 1  ⇒  9 שעות
-- 9×60 + 80 = 620₪ לעובד · 4 עובדים + 1 (אין חניה) = 5 ⇒ 3100
-- + 100 ראש צוות + 100×4 סבלות (לפי המקוריים) = 3600 · ×1.3 · ×1.2 = 5616
select t_eq('סך הכול להקמה = 5616',
  (app.price_calc(app.default_pricing_config('setup'),
    '{"truck_count":3,"travel_hours":0.5,"hours_count":4,"worker_count":4,
      "no_parking":true,"porterage":true,"requires_team_lead":true}'::jsonb) ->> 'total')::numeric,
  5616::numeric);

select t_eq('צבר השעות = 9',
  (app.price_calc(app.default_pricing_config('setup'),
    '{"truck_count":3,"travel_hours":0.5,"hours_count":4,"worker_count":4}'::jsonb)
   ->> 'hours')::numeric, 9::numeric);

select t_eq('מחיר לעובד = 620',
  (app.price_calc(app.default_pricing_config('setup'),
    '{"truck_count":3,"travel_hours":0.5,"hours_count":4,"worker_count":4}'::jsonb)
   ->> 'per_worker')::numeric, 620::numeric);

select t_eq('"אין חניה" מוסיף עובד להכפלה',
  (app.price_calc(app.default_pricing_config('setup'),
    '{"truck_count":3,"travel_hours":0.5,"hours_count":4,"worker_count":4,
      "no_parking":true}'::jsonb) ->> 'workers')::numeric, 5::numeric);

-- ההבדל בין 4 ל-5 עובדים בסבלות הוא 100₪ לפני מקדמים ו-156₪ אחריהם. אם
-- workers_basis ידלוף ל-effective המספר הזה יזוז, ולכן הוא נבדק במפורש.
select t_eq('סבלות נספרת לפי העובדים המקוריים, לא כולל תוספת החניה',
  (app.price_calc(app.default_pricing_config('setup'),
    '{"truck_count":3,"travel_hours":0.5,"hours_count":4,"worker_count":4,
      "no_parking":true,"porterage":true}'::jsonb) ->> 'total')::numeric,
  5460::numeric);

select t_eq('בלי ראש צוות ובלי סבלות = 4836',
  (app.price_calc(app.default_pricing_config('setup'),
    '{"truck_count":3,"travel_hours":0.5,"hours_count":4,"worker_count":4,
      "no_parking":true}'::jsonb) ->> 'total')::numeric, 4836::numeric);

\echo '--- worker_hours: מינימום שעות לחיוב ---'
-- 3 שטח + 0.5×2 נסיעה = 4 ש׳, והרצפה של 6 משלימה: 6×100×2 עובדים = 1200
select t_eq('min_hours משלים צבר נמוך ל-6',
  (app.price_calc('{"model":"worker_hours","hour_rate":100,"per_worker_fee":0,"min_hours":6,
     "hours":[{"id":"w","kind":"input","input":"hours_count"},
              {"id":"t","kind":"input","input":"travel_hours","multiplier":2}],
     "workers":{"input":"worker_count"}}'::jsonb,
    '{"hours_count":3,"travel_hours":0.5,"worker_count":2}'::jsonb) ->> 'hours')::numeric,
  6::numeric);

select t_eq('ההשלמה נכנסת גם למחיר',
  (app.price_calc('{"model":"worker_hours","hour_rate":100,"per_worker_fee":0,"min_hours":6,
     "hours":[{"id":"w","kind":"input","input":"hours_count"},
              {"id":"t","kind":"input","input":"travel_hours","multiplier":2}],
     "workers":{"input":"worker_count"}}'::jsonb,
    '{"hours_count":3,"travel_hours":0.5,"worker_count":2}'::jsonb) ->> 'total')::numeric,
  1200::numeric);

select t_eq('צבר מעל הרצפה לא נוגעים בו',
  (app.price_calc('{"model":"worker_hours","hour_rate":100,"per_worker_fee":0,"min_hours":6,
     "hours":[{"id":"w","kind":"input","input":"hours_count"},
              {"id":"t","kind":"input","input":"travel_hours","multiplier":2}],
     "workers":{"input":"worker_count"}}'::jsonb,
    '{"hours_count":8,"travel_hours":0.5,"worker_count":2}'::jsonb) ->> 'hours')::numeric,
  9::numeric);

select t_eq('בלי min_hours ההתנהגות כמו שהייתה',
  (app.price_calc('{"model":"worker_hours","hour_rate":100,"per_worker_fee":0,
     "hours":[{"id":"w","kind":"input","input":"hours_count"},
              {"id":"t","kind":"input","input":"travel_hours","multiplier":2}],
     "workers":{"input":"worker_count"}}'::jsonb,
    '{"hours_count":3,"travel_hours":0.5,"worker_count":2}'::jsonb) ->> 'hours')::numeric,
  4::numeric);

-- ההשלמה מוסברת בפירוט השעות, כדי שהמזין יבין מאיפה הגיע המספר
select t_eq('ההשלמה מופיעה כשורת זמן',
  (select count(*) from jsonb_array_elements(
     app.price_calc('{"model":"worker_hours","hour_rate":100,"per_worker_fee":0,"min_hours":6,
       "hours":[{"id":"w","kind":"input","input":"hours_count"}],
       "workers":{"input":"worker_count"}}'::jsonb,
      '{"hours_count":3,"worker_count":1}'::jsonb) -> 'hour_lines') l
    where l ->> 'id' = 'min_hours' and (l ->> 'hours')::numeric = 3),
  1::bigint);

\echo '--- worker_hours: מקרי קצה ברכיב המדורג ---'
select t_eq('משאית אחת = שעה אחת',
  (app.price_calc('{"model":"worker_hours","hour_rate":1,"per_worker_fee":0,
     "hours":[{"id":"t","kind":"stepped","input":"truck_count","first":1,"each_additional":0.5}],
     "workers":{"input":"worker_count"}}'::jsonb,
    '{"truck_count":1,"worker_count":1}'::jsonb) ->> 'hours')::numeric, 1::numeric);

select t_eq('אפס משאיות = אפס שעות (ולא "first" בחינם)',
  (app.price_calc('{"model":"worker_hours","hour_rate":1,"per_worker_fee":0,
     "hours":[{"id":"t","kind":"stepped","input":"truck_count","first":1,"each_additional":0.5}],
     "workers":{"input":"worker_count"}}'::jsonb,
    '{"truck_count":0,"worker_count":1}'::jsonb) ->> 'hours')::numeric, 0::numeric);

select t_eq('הקבועים תופסים כשאין משתנה',
  (app.price_calc('{"model":"worker_hours","hour_rate":100,"per_worker_fee":0,
     "constants":{"requires_team_lead":true},
     "hours":[{"id":"b","kind":"const","hours":1}],
     "workers":{"input":"worker_count"},
     "after_workers":[{"id":"l","kind":"fixed","amount":100,
       "when":{"all":[{"field":"requires_team_lead","op":"is_true"}]}}]}'::jsonb,
    '{"worker_count":1}'::jsonb) ->> 'total')::numeric, 200::numeric);

select t_eq('משתנה אמיתי גובר על קבוע',
  (app.price_calc('{"model":"worker_hours","hour_rate":100,"per_worker_fee":0,
     "constants":{"requires_team_lead":true},
     "hours":[{"id":"b","kind":"const","hours":1}],
     "workers":{"input":"worker_count"},
     "after_workers":[{"id":"l","kind":"fixed","amount":100,
       "when":{"all":[{"field":"requires_team_lead","op":"is_true"}]}}]}'::jsonb,
    '{"worker_count":1,"requires_team_lead":false}'::jsonb) ->> 'total')::numeric, 100::numeric);

select t_eq('שני מקדמים מוכפלים ברצף ולא מתחברים',
  (app.price_calc('{"model":"worker_hours","hour_rate":100,"per_worker_fee":0,
     "hours":[{"id":"b","kind":"const","hours":1}],"workers":{"input":"worker_count"},
     "multipliers":[{"id":"a","factor":1.3},{"id":"b","factor":1.2}]}'::jsonb,
    '{"worker_count":1}'::jsonb) ->> 'total')::numeric, 156::numeric);

\echo '--- line_items ---'
select t_eq('בסיס + תעריף ליחידה עם יחידות כלולות',
  (app.price_calc('{"model":"line_items","components":[
     {"id":"b","kind":"fixed","amount":1000},
     {"id":"v","kind":"per_unit","input":"volume_m","rate":50,"included_units":20}]}'::jsonb,
    '{"volume_m":30}'::jsonb) ->> 'total')::numeric, 1500::numeric);

select t_eq('יחידות כלולות לא יורדות מתחת לאפס',
  (app.price_calc('{"model":"line_items","components":[
     {"id":"v","kind":"per_unit","input":"volume_m","rate":50,"included_units":20}]}'::jsonb,
    '{"volume_m":5}'::jsonb) ->> 'total')::numeric, 0::numeric);

select t_eq('מדרגות flat: 45 קוב נופל במדרגה השנייה',
  (app.price_calc('{"model":"line_items","components":[
     {"id":"t","kind":"tiered","input":"volume_m","mode":"flat","tiers":[
       {"up_to":30,"amount":1500},{"up_to":60,"amount":2400},{"up_to":null,"amount":3200}]}]}'::jsonb,
    '{"volume_m":45}'::jsonb) ->> 'total')::numeric, 2400::numeric);

select t_eq('מדרגות flat: מעל הכול נופל למדרגה הפתוחה',
  (app.price_calc('{"model":"line_items","components":[
     {"id":"t","kind":"tiered","input":"volume_m","mode":"flat","tiers":[
       {"up_to":30,"amount":1500},{"up_to":60,"amount":2400},{"up_to":null,"amount":3200}]}]}'::jsonb,
    '{"volume_m":90}'::jsonb) ->> 'total')::numeric, 3200::numeric);

-- 30×50 + 30×40 + 20×30 = 1500 + 1200 + 600
select t_eq('מדרגות progressive מתמחרות פרוסה-פרוסה',
  (app.price_calc('{"model":"line_items","components":[
     {"id":"t","kind":"tiered","input":"volume_m","mode":"progressive","tiers":[
       {"up_to":30,"rate":50},{"up_to":60,"rate":40},{"up_to":null,"rate":30}]}]}'::jsonb,
    '{"volume_m":80}'::jsonb) ->> 'total')::numeric, 3300::numeric);

select t_eq('תוספת באחוזים מחושבת על מה שנצבר עד אליה',
  (app.price_calc('{"model":"line_items","components":[
     {"id":"b","kind":"fixed","amount":1000},
     {"id":"s","kind":"surcharge","amount_kind":"percent","amount":15,
      "when":{"all":[{"field":"no_parking","op":"is_true"}]}}]}'::jsonb,
    '{"no_parking":true}'::jsonb) ->> 'total')::numeric, 1150::numeric);

select t_eq('תוספת מותנית שלא התקיימה לא נספרת',
  (app.price_calc('{"model":"line_items","components":[
     {"id":"b","kind":"fixed","amount":1000},
     {"id":"s","kind":"surcharge","amount":500,
      "when":{"all":[{"field":"no_parking","op":"is_true"}]}}]}'::jsonb,
    '{"no_parking":false}'::jsonb) ->> 'total')::numeric, 1000::numeric);

select t_eq('מינימום מרים מחיר נמוך',
  (app.price_calc('{"model":"line_items","min_price":900,
     "components":[{"id":"b","kind":"fixed","amount":400}]}'::jsonb,
    '{}'::jsonb) ->> 'total')::numeric, 900::numeric);

select t_eq('עיגול כלפי מעלה לעשרות',
  (app.price_calc('{"model":"line_items","rounding":{"mode":"up","to":10},
     "components":[{"id":"b","kind":"fixed","amount":1041}]}'::jsonb,
    '{}'::jsonb) ->> 'total')::numeric, 1050::numeric);

\echo '--- תנאים ---'
select t_eq('all דורש את כולם',      app.price_cond('{"all":[{"field":"a","op":"is_true"},{"field":"b","op":"is_true"}]}'::jsonb, '{"a":true,"b":false}'::jsonb), false);
select t_eq('any מסתפק באחד',        app.price_cond('{"any":[{"field":"a","op":"is_true"},{"field":"b","op":"is_true"}]}'::jsonb, '{"a":true,"b":false}'::jsonb), true);
select t_eq('gte על מספר',           app.price_cond('{"field":"v","op":"gte","value":30}'::jsonb, '{"v":30}'::jsonb), true);
select t_eq('lt על מספר',            app.price_cond('{"field":"v","op":"lt","value":30}'::jsonb, '{"v":30}'::jsonb), false);
select t_eq('in על רשימה',           app.price_cond('{"field":"dow","op":"in","value":[5,6]}'::jsonb, '{"dow":5}'::jsonb), true);
select t_eq('between כולל קצוות',    app.price_cond('{"field":"v","op":"between","value":[10,20]}'::jsonb, '{"v":20}'::jsonb), true);
select t_eq('תנאי ריק = תמיד אמת',   app.price_cond(null, '{}'::jsonb), true);
select t_eq('is_true על שדה חסר = שקר', app.price_cond('{"field":"nope","op":"is_true"}'::jsonb, '{}'::jsonb), false);

\echo '--- גאומטריה ---'
-- ריבוע גס סביב גוש דן
select t_eq('נקודה בתוך הפוליגון',
  app.point_in_polygon(32.08, 34.78, '[[31.9,34.6],[32.3,34.6],[32.3,35.0],[31.9,35.0]]'::jsonb), true);
select t_eq('נקודה מחוץ לפוליגון',
  app.point_in_polygon(31.25, 34.79, '[[31.9,34.6],[32.3,34.6],[32.3,35.0],[31.9,35.0]]'::jsonb), false);
select t_eq('פוליגון עם פחות מ-3 נקודות אינו מכיל דבר',
  app.point_in_polygon(32.08, 34.78, '[[31.9,34.6],[32.3,34.6]]'::jsonb), false);
select t_eq('פוליגון NULL אינו מפיל את החישוב',
  app.point_in_polygon(32.08, 34.78, null), false);
select t_eq('מרחק תל אביב—ירושלים בערך 54 ק״מ',
  round(app.haversine_km(32.0853, 34.7818, 31.7683, 35.2137)::numeric), 54::numeric);

-- ================= אינטגרציה: המחיר על משימה אמיתית =================
\echo '--- חישוב אוטומטי מקצה לקצה ---'

insert into customers (id, name, can_create_events, pricing_mode) values
  ('10000000-0000-0000-0000-0000000000b1', 'לקוח אוטומטי', true, 'auto');

insert into customer_pricing_rules (customer_id, task_type_id, config)
select '10000000-0000-0000-0000-0000000000b1', tt.id, app.default_pricing_config(tt.code)
from task_types tt where tt.code in ('setup', 'teardown');

-- אזור גיאופנס סביב גוש דן: 0.5 שעת נסיעה
insert into pricing_zones (customer_id, name, shape, points, travel_hours, priority) values
  (null, 'גוש דן', 'polygon', '[[31.9,34.6],[32.3,34.6],[32.3,35.0],[31.9,35.0]]'::jsonb, 0.5, 100);

insert into events (id, customer_id, event_date, truck_count, volume_m,
                    location_lat, location_lng, no_parking, porterage)
values ('30000000-0000-0000-0000-0000000000d1', '10000000-0000-0000-0000-0000000000b1',
        current_date + 10, 3, 40, 32.08, 34.78, true, true);

-- הטריגר events_default_tasks יצר הקמה ופירוק; ממלאים את שעות העבודה
update tasks set hours_count = 4, worker_count = 4
 where event_id = '30000000-0000-0000-0000-0000000000d1';

select t_eq('להקמה חושב מחיר אוטומטית',
  (select tp.price from task_pricing tp
    join tasks t on t.id = tp.task_id
    join task_types tt on tt.id = t.task_type_id
   where t.event_id = '30000000-0000-0000-0000-0000000000d1' and tt.code = 'setup'),
  5460::numeric);

select t_eq('זמן הנסיעה נשאב מהאזור הגאוגרפי',
  (app.pricing_vars((select t.id from tasks t join task_types tt on tt.id = t.task_type_id
     where t.event_id = '30000000-0000-0000-0000-0000000000d1' and tt.code = 'setup'))
   ->> 'travel_hours')::numeric, 0.5::numeric);

select t_eq('גם לפירוק חושב מחיר, ובנוסחה שלו',
  (select tp.price from task_pricing tp
    join tasks t on t.id = tp.task_id
    join task_types tt on tt.id = t.task_type_id
   where t.event_id = '30000000-0000-0000-0000-0000000000d1' and tt.code = 'teardown'),
  4992::numeric);

-- שינוי בכמות העובדים חייב להזיז את המחיר
update tasks set worker_count = 6
 where event_id = '30000000-0000-0000-0000-0000000000d1'
   and task_type_id = (select id from task_types where code = 'setup');

select t_eq('שינוי בכמות העובדים מחשב מחדש',
  (select tp.price from task_pricing tp
    join tasks t on t.id = tp.task_id
    join task_types tt on tt.id = t.task_type_id
   where t.event_id = '30000000-0000-0000-0000-0000000000d1' and tt.code = 'setup'),
  7706::numeric);

-- שינוי באירוע (מספר משאיות) חייב להזיז את שתי המשימות
update events set truck_count = 5 where id = '30000000-0000-0000-0000-0000000000d1';

select t_eq('שינוי במספר המשאיות באירוע מחשב מחדש את ההקמה',
  (select tp.price from task_pricing tp
    join tasks t on t.id = tp.task_id
    join task_types tt on tt.id = t.task_type_id
   where t.event_id = '30000000-0000-0000-0000-0000000000d1' and tt.code = 'setup'),
  8689::numeric);

\echo '--- הנעילה הידנית ---'
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false);

select t_expect_ok('אדמין מזין מחיר ידנית',
  $$update task_pricing set price = 4000 where task_id =
      (select t.id from tasks t join task_types tt on tt.id = t.task_type_id
        where t.event_id = '30000000-0000-0000-0000-0000000000d1' and tt.code = 'setup')$$);

reset role;
select set_config('request.jwt.claim.sub', '', false);

select t_eq('כתיבה ידנית מסמנת is_manual',
  (select tp.is_manual from task_pricing tp
    join tasks t on t.id = tp.task_id
    join task_types tt on tt.id = t.task_type_id
   where t.event_id = '30000000-0000-0000-0000-0000000000d1' and tt.code = 'setup'), true);

update events set truck_count = 2 where id = '30000000-0000-0000-0000-0000000000d1';

select t_eq('מחיר נעול שורד שינוי באירוע',
  (select tp.price from task_pricing tp
    join tasks t on t.id = tp.task_id
    join task_types tt on tt.id = t.task_type_id
   where t.event_id = '30000000-0000-0000-0000-0000000000d1' and tt.code = 'setup'),
  4000::numeric);

select t_eq('אבל הפירוק, שלא ננעל, כן זז',
  (select tp.is_manual from task_pricing tp
    join tasks t on t.id = tp.task_id
    join task_types tt on tt.id = t.task_type_id
   where t.event_id = '30000000-0000-0000-0000-0000000000d1' and tt.code = 'teardown'), false);

select t_eq('"חשב מחדש" שובר את הנעילה',
  (app.recalc_task_price(
     (select t.id from tasks t join task_types tt on tt.id = t.task_type_id
       where t.event_id = '30000000-0000-0000-0000-0000000000d1' and tt.code = 'setup'),
     true) ->> 'total')::numeric,
  7215::numeric);

\echo '--- לקוח ידני לא מקבל חישוב ---'
insert into customers (id, name, pricing_mode) values
  ('10000000-0000-0000-0000-0000000000b2', 'לקוח ידני', 'manual');
insert into customer_pricing_rules (customer_id, task_type_id, config)
select '10000000-0000-0000-0000-0000000000b2', tt.id, app.default_pricing_config(tt.code)
from task_types tt where tt.code = 'setup';
insert into events (id, customer_id, event_date, truck_count)
values ('30000000-0000-0000-0000-0000000000d2', '10000000-0000-0000-0000-0000000000b2',
        current_date + 10, 3);

select t_eq('לקוח במצב ידני לא מקבל מחיר אוטומטי, גם כשיש לו מחשבון',
  (select count(*) from task_pricing tp join tasks t on t.id = tp.task_id
    where t.event_id = '30000000-0000-0000-0000-0000000000d2'), 0::bigint);

-- ================= הרשאות =================
\echo '--- הקבלן לא רואה את מחיר הלקוח ---'

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000e1', 'contractor@vl.test');
insert into contractors (id, name) values
  ('40000000-0000-0000-0000-0000000000e1', 'קבלן משנה');
insert into profiles (id, user_id, user_kind, full_name, contractor_id) values
  ('20000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-0000000000e1',
   'contractor_user', 'איש הקבלן', '40000000-0000-0000-0000-0000000000e1');

-- מאצילים לו את משימת ההקמה, כדי שהשורה ב-tasks תהיה גלויה לו
update tasks set contractor_id = '40000000-0000-0000-0000-0000000000e1'
 where event_id = '30000000-0000-0000-0000-0000000000d1'
   and task_type_id = (select id from task_types where code = 'setup');

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000e1', false);

select t_eq('הקבלן אכן רואה את המשימה עצמה',
  (select count(*) from tasks where event_id = '30000000-0000-0000-0000-0000000000d1'
     and contractor_id = '40000000-0000-0000-0000-0000000000e1'), 1::bigint);
select t_eq('אבל אף שורת תמחור אינה נראית לו',
  (select count(*) from task_pricing), 0::bigint);
select t_eq('ולא מחשבונים',
  (select count(*) from customer_pricing_rules), 0::bigint);
select t_eq('ולא אזורי נסיעה',
  (select count(*) from pricing_zones), 0::bigint);
select t_eq('גם בלוח העבודה המחיר ריק',
  (select count(*) from work_board_view where customer_price is not null), 0::bigint);
select t_rows('ואינו יכול לכתוב מחיר (אף שורה לא נגעה)',
  $$update task_pricing set price = 1$$, 0);

\echo '--- הלקוח רואה רק עם המפתח, ורק את שלו ---'
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000c1', false);
select t_eq('בלי pricing.view הלקוח לא רואה מחירים',
  (select count(*) from task_pricing), 0::bigint);

reset role;
select set_config('request.jwt.claim.sub', '', false);
insert into user_permission_grants (profile_id, permission_key, allowed) values
  ('20000000-0000-0000-0000-0000000000c1', 'pricing.view', true);

-- אירוע של הלקוח הזה, עם מחיר
update customers set pricing_mode = 'auto' where id = '10000000-0000-0000-0000-000000000001';
insert into customer_pricing_rules (customer_id, task_type_id, config)
select '10000000-0000-0000-0000-000000000001', tt.id, app.default_pricing_config(tt.code)
from task_types tt where tt.code = 'setup'
on conflict do nothing;
insert into events (id, customer_id, event_date, truck_count)
values ('30000000-0000-0000-0000-0000000000d3', '10000000-0000-0000-0000-000000000001',
        current_date + 12, 2);
update tasks set worker_count = 2, hours_count = 3
 where event_id = '30000000-0000-0000-0000-0000000000d3';

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000c1', false);

select t_eq('עם המפתח הלקוח רואה את המחיר של האירוע שלו',
  (select count(*) from task_pricing tp join tasks t on t.id = tp.task_id
    where t.event_id = '30000000-0000-0000-0000-0000000000d3'), 1::bigint);
select t_eq('ולא את זה של לקוח אחר',
  (select count(*) from task_pricing tp join tasks t on t.id = tp.task_id
    where t.event_id = '30000000-0000-0000-0000-0000000000d1'), 0::bigint);
select t_rows('ואינו יכול לערוך מחיר (אף שורה לא נגעה)',
  $$update task_pricing set price = 1$$, 0);
select t_expect_fail('ואינו יכול לבנות מחשבון',
  $$insert into customer_pricing_rules (customer_id, task_type_id, config)
    select '10000000-0000-0000-0000-000000000001', id, '{}'::jsonb from task_types limit 1$$);

reset role;
select set_config('request.jwt.claim.sub', '', false);

\echo '--- create_event עדיין עובד ללקוח אחרי הוספת טריגר התמחור ---'
-- הטריגר על tasks יורה באמצע ה-system_write המשותף של create_event. אם
-- recalc_task_price היה מכבה את הדגל במקום לשחזר אותו, סקשן הפירוק היה
-- נחסם כאן ב-enforce_field_perms. זו הבדיקה שתופסת את זה.
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000c1', false);

select t_expect_ok('לקוח יוצר אירוע עם שני הסקשנים',
  $$select create_event(jsonb_build_object(
      'event_date', (current_date + 20)::text, 'event_number', 'X-1',
      'truck_count', '2',
      'setup_worker_count', '3', 'setup_hours_count', '4', 'setup_date', (current_date + 20)::text,
      'teardown_worker_count', '2', 'teardown_hours_count', '2', 'teardown_date', (current_date + 21)::text))$$);

reset role;
select set_config('request.jwt.claim.sub', '', false);

select t_eq('שני הסקשנים אכן נכתבו',
  (select count(*) from tasks t join events e on e.id = t.event_id
    where e.event_number = 'X-1' and t.worker_count > 0), 2::bigint);

\echo '--- אזורי נסיעה ---'
select t_eq('האזור נבחר לפי הנקודה',
  (select name from app.zone_for_point(null, 32.08, 34.78)), 'גוש דן');
select t_eq('נקודה מחוץ לכל אזור לא מחזירה כלום',
  (select count(*) from (select (app.zone_for_point(null, 29.55, 34.95)).id) q where q.id is not null), 0::bigint);

-- אזור פרטי ללקוח חייב לגבור על גלובלי, גם כשהגלובלי עדיף ב-priority
insert into pricing_zones (customer_id, name, shape, points, travel_hours, priority) values
  ('10000000-0000-0000-0000-0000000000b1', 'גוש דן — הסכם מיוחד', 'polygon',
   '[[31.9,34.6],[32.3,34.6],[32.3,35.0],[31.9,35.0]]'::jsonb, 0.25, 900);

select t_eq('אזור של הלקוח גובר על גלובלי גם עם priority גרוע יותר',
  (select travel_hours from app.zone_for_point('10000000-0000-0000-0000-0000000000b1', 32.08, 34.78)),
  0.25::numeric);
select t_eq('ולקוח אחר ממשיך לקבל את הגלובלי',
  (select travel_hours from app.zone_for_point('10000000-0000-0000-0000-0000000000b2', 32.08, 34.78)),
  0.5::numeric);

select t_expect_ok('מחיקת אזור מסמנת deleted_at',
  $$update pricing_zones set deleted_at = now() where name = 'גוש דן — הסכם מיוחד'$$);
select t_eq('ואחרי המחיקה חוזרים לאזור הגלובלי',
  (select travel_hours from app.zone_for_point('10000000-0000-0000-0000-0000000000b1', 32.08, 34.78)),
  0.5::numeric);

-- pz_select הייתה פוליסת ה-SELECT היחידה בסכמה בלי deleted_at is null, ולכן
-- אזור שנמחק המשיך להופיע ברשימה לכל מי שמחזיק pricing.view. החישוב עצמו
-- (app.zone_for_point) סינן נכון — הבדיקה שמעל מוכיחה את זה — ולכן זו הייתה
-- דליפת קריאה בלבד, ודווקא משום כך אף אחד לא נתקל בה.
insert into user_permission_grants (profile_id, permission_key, allowed) values
  ('20000000-0000-0000-0000-0000000000f1', 'pricing.view', true)
on conflict (profile_id, permission_key) do update set allowed = excluded.allowed;

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000f1', false);

select t_eq('אזור שנמחק אינו נראה גם למי שרשאי לראות אזורים',
  (select count(*) from pricing_zones where name = 'גוש דן — הסכם מיוחד'), 0::bigint);

select t_eq('ואזור חי כן נראה לו',
  (select count(*) from pricing_zones where name = 'גוש דן'), 1::bigint);

reset role;
select set_config('request.jwt.claim.sub', '', false);

-- ===== 0057: רשומת תשלום לקבלן חוסמת הסרה והחלפה ============================
--
-- ההאצלה מהסעיף הקודם עדיין עומדת: משימת ההקמה של האירוע d1 מואצלת לקבלן
-- e1. מסמנים את השורה כמשולמת ומוודאים ששני נתיבי הסנכרון — הסרה (delete)
-- והחלפה (on conflict do update שמאפס את התשלום) — נחסמים עד ביטול הסימון.
\echo '--- תשלום לקבלן מגן על שורת התנאים (0057) ---'

update task_contractor_terms
   set paid_at = now(), paid_amount = 500
 where task_id = (select id from tasks
                   where event_id = '30000000-0000-0000-0000-0000000000d1'
                     and contractor_id = '40000000-0000-0000-0000-0000000000e1');

select t_eq('הסימון אכן נרשם',
  (select count(*) from task_contractor_terms tct
    join tasks t on t.id = tct.task_id
   where t.event_id = '30000000-0000-0000-0000-0000000000d1'
     and tct.paid_at is not null), 1::bigint);

select t_expect_fail('אי אפשר להסיר קבלן ממשימה ששולם עליה',
  $$update tasks set contractor_id = null
     where event_id = '30000000-0000-0000-0000-0000000000d1'
       and contractor_id = '40000000-0000-0000-0000-0000000000e1'$$);

insert into contractors (id, name) values
  ('40000000-0000-0000-0000-0000000000e2', 'קבלן מחליף');

select t_expect_fail('ואי אפשר להחליף אותו בקבלן אחר',
  $$update tasks set contractor_id = '40000000-0000-0000-0000-0000000000e2'
     where event_id = '30000000-0000-0000-0000-0000000000d1'
       and contractor_id = '40000000-0000-0000-0000-0000000000e1'$$);

update task_contractor_terms
   set paid_at = null, paid_amount = null
 where task_id = (select id from tasks
                   where event_id = '30000000-0000-0000-0000-0000000000d1'
                     and contractor_id = '40000000-0000-0000-0000-0000000000e1');

select t_expect_ok('אחרי ביטול הסימון ההסרה עוברת',
  $$update tasks set contractor_id = null
     where event_id = '30000000-0000-0000-0000-0000000000d1'
       and contractor_id = '40000000-0000-0000-0000-0000000000e1'$$);

select t_eq('ושורת התנאים נמחקה כרגיל',
  (select count(*) from task_contractor_terms tct
    join tasks t on t.id = tct.task_id
   where t.event_id = '30000000-0000-0000-0000-0000000000d1'), 0::bigint);

-- ===== 0056: שינוי ב-app_settings מותיר עקבה ================================
--
-- מפתח זמני נכנס ונמחק, כדי לא להשאיר שאריות לחבילות הבאות. no-op update
-- לא נבדק בכוונה: app.audit() מדלג על עדכון בלי עמודות שהשתנו.
\echo '--- audit על app_settings (0056) ---'

insert into app_settings (key, value) values ('test.audit_probe', '{"v": 1}'::jsonb);
update app_settings set value = '{"v": 2}'::jsonb where key = 'test.audit_probe';
delete from app_settings where key = 'test.audit_probe';

select t_eq('שלוש הפעולות על המפתח הזמני נרשמו ביומן',
  (select count(*) from audit_log
    where table_name = 'app_settings'
      and row_id = md5('app_settings:test.audit_probe')::uuid), 3::bigint);

select t_eq('והערך הקודם נשמר בעדכון',
  (select old_data -> 'value' ->> 'v' from audit_log
    where table_name = 'app_settings'
      and row_id = md5('app_settings:test.audit_probe')::uuid
      and action = 'UPDATE'), '1');
