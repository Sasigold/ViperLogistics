\pset tuples_only on
\pset format unaligned

-- ===========================================================================
-- 28: "הובלה בלבד" בתמחור הלקוח (0118).
--
-- הבדיקה היא על ה**מנגנון**, לא על ארקו: 0119 היא מיגרציית נתונים ללקוח
-- שאינו קיים באשכול הזה, ומה שראוי לנעול הוא שהמשתנה מגיע למנוע ושהתנאי
-- עליו באמת מוריד את השורה. אותו כלל בדיוק שהמשרד יסמן במסך התמחור לכל
-- לקוח אחר.
--
-- החלון הוא current_date + 440, מעבר ל-430 של 27.
-- ===========================================================================

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000028a1', 'c28-admin@vl.test');

insert into customers (id, name, pricing_mode) values
  ('10000000-0000-0000-0000-00000000028a', 'לקוח 28', 'auto');

insert into profiles (id, user_id, user_kind, is_admin, full_name) values
  ('20000000-0000-0000-0000-0000000028a1', '00000000-0000-0000-0000-0000000028a1',
   'staff', true, 'מנהל מערכת 28');

-- אופן ביצוע אחד רגיל ואחד שהוא הובלה בלבד, שניהם מותרים ללקוח ולהקמה
insert into execution_methods (id, name, is_transport_only, is_active) values
  ('80000000-0000-0000-0000-000000028001', 'צוות לשטח 28', false, true),
  ('80000000-0000-0000-0000-000000028002', 'הובלה בלבד 28', true,  true);

insert into task_type_execution_methods (task_type_id, execution_method_id)
select (select id from task_types where code = 'setup' limit 1), x.id
from (values ('80000000-0000-0000-0000-000000028001'::uuid),
             ('80000000-0000-0000-0000-000000028002'::uuid)) as x(id);

insert into customer_execution_methods (customer_id, execution_method_id)
select '10000000-0000-0000-0000-00000000028a', x.id
from (values ('80000000-0000-0000-0000-000000028001'::uuid),
             ('80000000-0000-0000-0000-000000028002'::uuid)) as x(id);

-- מחשבון מינימלי: 100 ₪ לשעה לעובד, ותוספת ראש צוות של 500 ₪ — מספר גדול
-- וברור, כדי ששום עיגול לא יסתיר אם הוא נכנס או לא.
insert into customer_pricing_rules (customer_id, task_type_id, config, is_active)
values ('10000000-0000-0000-0000-00000000028a',
        (select id from task_types where code = 'setup' limit 1),
        '{"model":"worker_hours",
          "hour_rate":100,
          "constants":{"requires_team_lead":true},
          "hours":[{"id":"base","kind":"input","input":"hours_count","multiplier":1}],
          "workers":{"input":"worker_count"},
          "after_workers":[
            {"id":"team_lead","label":"ראש צוות","kind":"fixed","amount":500,
             "when":{"all":[{"field":"requires_team_lead","op":"is_true"}]}}]}'::jsonb,
        true);

insert into events (id, customer_id, event_number, event_date, end_client_name, status_id)
values ('30000000-0000-0000-0000-00000000028a', '10000000-0000-0000-0000-00000000028a',
        'EV-28', current_date + 440, 'לקוח קצה 28',
        (select id from statuses where entity = 'event' and code = 'planned' and deleted_at is null));

update tasks set deleted_at = now() where event_id = '30000000-0000-0000-0000-00000000028a';

-- משימה אחת "צוות לשטח": 2 עובדים × 3 שעות × 100 = 600, ועוד 500 ראש צוות
insert into tasks (id, event_id, customer_id, task_type_id, task_date,
                   onsite_start_time, hours_count, worker_count,
                   execution_method_id, status_id)
values ('61000000-0000-0000-0000-000000028001',
        '30000000-0000-0000-0000-00000000028a', '10000000-0000-0000-0000-00000000028a',
        (select id from task_types where code = 'setup' limit 1), current_date + 440,
        '09:00', 3, 2, '80000000-0000-0000-0000-000000028001',
        (select id from statuses where entity = 'task' and code = 'draft' and deleted_at is null));

\echo '--- הובלה בלבד כמשתנה של המחשבון ---'

select t_eq('המשתנה מגיע למנוע',
  (app.pricing_vars('61000000-0000-0000-0000-000000028001') ->> 'is_transport_only')::boolean,
  false);

select t_eq('ולפני התנאי, ראש הצוות נגבה כרגיל',
  (select price from task_pricing where task_id = '61000000-0000-0000-0000-000000028001'),
  1100::numeric);

-- ...ועכשיו הכלל שהמשרד מסמן במסך: "רק כשזו אינה הובלה בלבד"
update customer_pricing_rules
   set config = jsonb_set(config, '{after_workers,0,when,all}',
         '[{"field":"requires_team_lead","op":"is_true"},
           {"field":"is_transport_only","op":"is_false"}]'::jsonb)
 where customer_id = '10000000-0000-0000-0000-00000000028a';

select t_eq('הכלל אינו נוגע במשימה שאינה הובלה בלבד',
  (select price from task_pricing where task_id = '61000000-0000-0000-0000-000000028001'),
  1100::numeric);

-- אותה משימה בדיוק, באופן ביצוע שהוא הובלה בלבד
update tasks set execution_method_id = '80000000-0000-0000-0000-000000028002'
 where id = '61000000-0000-0000-0000-000000028001';

select t_eq('והמשתנה התהפך',
  (app.pricing_vars('61000000-0000-0000-0000-000000028001') ->> 'is_transport_only')::boolean,
  true);

select t_eq('ותוספת ראש הצוות ירדה — 500 ₪ פחות',
  (select price from task_pricing where task_id = '61000000-0000-0000-0000-000000028001'),
  600::numeric);

select t_eq('והיא גם אינה מופיעה בפירוט, ולא רק בסכום',
  (select count(*)::int from jsonb_array_elements(
     (select breakdown -> 'lines' from task_pricing
       where task_id = '61000000-0000-0000-0000-000000028001')) e
    where e ->> 'id' = 'team_lead'), 0);

-- ובחזרה, כדי שיהיה ברור שזה תנאי ולא מחיקה
update tasks set execution_method_id = '80000000-0000-0000-0000-000000028001'
 where id = '61000000-0000-0000-0000-000000028001';

select t_eq('ובאופן ביצוע אחר היא חוזרת',
  (select price from task_pricing where task_id = '61000000-0000-0000-0000-000000028001'),
  1100::numeric);

-- משימה בלי אופן ביצוע כלל: is_false אמור להתקיים על מפתח נעדר, ולכן
-- התוספת נגבית — ההתנהגות שהייתה לפני 0118, ללא שינוי
insert into tasks (id, event_id, customer_id, task_type_id, task_date,
                   onsite_start_time, hours_count, worker_count,
                   execution_method_id, status_id)
values ('61000000-0000-0000-0000-000000028002',
        '30000000-0000-0000-0000-00000000028a', '10000000-0000-0000-0000-00000000028a',
        (select id from task_types where code = 'setup' limit 1), current_date + 440,
        '09:00', 3, 2, null,
        (select id from statuses where entity = 'task' and code = 'draft' and deleted_at is null));

select t_eq('ומשימה בלי אופן ביצוע ממשיכה לשאת אותה, כמו קודם',
  (select price from task_pricing where task_id = '61000000-0000-0000-0000-000000028002'),
  1100::numeric);

-- ===== 0132: התנאי הוא אופן הביצוע, ולא "נדרש ראש צוות" ==================
--
-- ‏0119 הותירה את שני התנאים זה לצד זה, ולכן השורה נגבתה רק כשמישהו סימן
-- במפורש "נדרש ראש צוות" *וגם* אופן הביצוע אינו הובלה בלבד. ‏0132 מורידה את
-- הראשון אצל ארקו. אין ארקו באשכול הזה, ולכן — כמו כל החבילה — מה שנבדק הוא
-- ה**כלל** שהיא כותבת: תנאי אחד, על אופן הביצוע.
-- שני שינויים בשורה אחת: התנאי מצטמצם לאופן הביצוע, ו-`constants` מתרוקן
-- כדי ש-`requires_team_lead` באמת לא יהיה מסומן בשום מקום.
update customer_pricing_rules
   set config = jsonb_set(
         jsonb_set(config, '{after_workers,0,when,all}',
           '[{"field":"is_transport_only","op":"is_false"}]'::jsonb),
         '{constants}', '{}'::jsonb)
 where customer_id = '10000000-0000-0000-0000-00000000028a';

select t_eq('המשימה אינה מסומנת "נדרש ראש צוות"',
  (select requires_team_lead from tasks where id = '61000000-0000-0000-0000-000000028001'),
  null::boolean);

-- ובכל זאת, באופן ביצוע רגיל, השורה נגבית — זה בדיוק מה ש-0132 משנה.
select t_eq('ובכל זאת השורה נגבית — התנאי הוא אופן הביצוע (0132)',
  (select price from task_pricing where task_id = '61000000-0000-0000-0000-000000028001'),
  1100::numeric);

-- והובלה בלבד ממשיכה להוריד אותה, בלי שאיש סימן דבר.
update tasks set execution_method_id = '80000000-0000-0000-0000-000000028002'
 where id = '61000000-0000-0000-0000-000000028001';

select t_eq('ובהובלה בלבד היא יורדת, גם בלי הסימון',
  (select price from task_pricing where task_id = '61000000-0000-0000-0000-000000028001'),
  600::numeric);
