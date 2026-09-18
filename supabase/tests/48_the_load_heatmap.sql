\pset tuples_only on
\pset format unaligned

-- ===========================================================================
-- ‏48: מפת העומסים (0173).
--
-- שלוש שאלות: האם השעה סופרת **מקבילות** ולא סכום, האם החלון נפתח במקום
-- הנכון (כולל היציאה למחסן שנסוגה ליום שלפני), ומי בכלל מקבל מספרים.
--
-- החבילה מקימה עולם משלה ב-`current_date + 700`, מעבר לכל טווח אחר, ולכן
-- אפשר לקבוע בה מספרים מדויקים. התקרה נכתבת במפורש ל-`ops.capacity` כדי
-- שהאחוזים והפסגה לא יתלו בגודל המאגר שחבילות אחרות זרעו.
--
-- אריתמטיקת היום הראשי (D), כדי שהמספרים למטה לא ייראו שרירותיים:
--
--   T1  08:00 ‏+4ש׳  → ‏[08,12)   3 עובדים   ‏TR1        ראש צוות
--   T2  10:00 ‏+4ש׳  → ‏[10,14)   2 עובדים   ‏TR1,TR2    ראש צוות
--   T3  15:00 ‏+2ש׳  → ‏[15,17)   5 עובדים   ‏TR3        (ראש צוות לפי 0181)
--   T4  בלי שעה     → אינה על הציר, ונספרת בכל זאת בסך היום (0181)
--
--   שעה 08–09:  משימה 1, ‏3 עובדים, ‏1 משאית,  ‏1 ראש צוות
--   שעה 10–11:  משימות 2, ‏5 עובדים, ‏2 משאיות, ‏2 ראשי צוות   ← הפסגה
--   שעה 12–13:  משימה 1 (‏T2 בלבד), ‏2 עובדים, ‏2 משאיות
--   שעה 14:     ריקה — ‏T2 נסגרת ב-14:00, והחלון הוא `[)`
--   שעה 15–16:  משימה 1, ‏5 עובדים, ‏1 משאית,  ‏1 ראש צוות (0181: כל משימה
--               שאינה הובלה בלבד/איסוף עצמי דורשת ראש צוות)
--
--   סך היום: ‏4 משימות — ‏3 מתוזמנות ואחת בלי שעה, והדרישה היא של כולן:
--            ‏3+2+5+4 = 14 עובדים. שעות-עובד נספרות מהמתוזמנות בלבד,
--            כי רק להן יש משך: ‏3×4 + 2×4 + 5×2 = 30
--
--   התקרה: עובדים 10, משאיות 4, ראשי צוות 2. ביחסים, שעה 10 היא
--   ‏max(5/10, 2/4, 2/2) = 1.0 ושעה 15 היא max(5/10, 1/4, 0) = 0.5,
--   ולכן `peak_hour` הוא 10 — הצוואר הוא ראשי הצוות ולא העובדים.
-- ===========================================================================

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000048a0', 'load48-admin@vl.test'),
  ('00000000-0000-0000-0000-0000000048a1', 'load48-ops@vl.test'),
  ('00000000-0000-0000-0000-0000000048a2', 'load48-nokey@vl.test'),
  ('00000000-0000-0000-0000-0000000048a3', 'load48-scoped@vl.test'),
  ('00000000-0000-0000-0000-0000000048a4', 'load48-customer@vl.test');

insert into customers (id, name) values
  ('10000000-0000-0000-0000-00000000048a', 'לקוח 48'),
  ('10000000-0000-0000-0000-00000000048b', 'לקוח 48 שני');

insert into contractors (id, name) values
  ('11000000-0000-0000-0000-00000000048a', 'קבלן 48');

insert into profiles (id, user_id, user_kind, is_admin, full_name) values
  ('20000000-0000-0000-0000-0000000048a0', '00000000-0000-0000-0000-0000000048a0',
   'staff', true, 'מנהל 48');

insert into profiles (id, user_id, user_kind, full_name) values
  ('20000000-0000-0000-0000-0000000048a1', '00000000-0000-0000-0000-0000000048a1',
   'staff', 'רכז תפעול 48'),
  ('20000000-0000-0000-0000-0000000048a2', '00000000-0000-0000-0000-0000000048a2',
   'staff', 'עובד משרד 48 בלי מפתח'),
  ('20000000-0000-0000-0000-0000000048a3', '00000000-0000-0000-0000-0000000048a3',
   'staff', 'רכז 48 בהיקף מצומצם');

insert into profiles (id, user_id, user_kind, full_name, customer_id) values
  ('20000000-0000-0000-0000-0000000048a4', '00000000-0000-0000-0000-0000000048a4',
   'customer_user', 'מנהל לקוח 48', '10000000-0000-0000-0000-00000000048a');

-- שני עובדים שישובצו, כדי שפער האיוש יהיה מספר ולא הנחה.
insert into profiles (id, user_kind, full_name) values
  ('20000000-0000-0000-0000-0000000048b1', 'staff', 'עובד 48 א'),
  ('20000000-0000-0000-0000-0000000048b2', 'staff', 'עובד 48 ב');
insert into staff_roles (profile_id, role) values
  ('20000000-0000-0000-0000-0000000048b1', 'worker'),
  ('20000000-0000-0000-0000-0000000048b2', 'worker');

insert into user_permission_grants (profile_id, permission_key, allowed) values
  ('20000000-0000-0000-0000-0000000048a1', 'reports.load',  true),
  ('20000000-0000-0000-0000-0000000048a1', 'board.view',    true),
  ('20000000-0000-0000-0000-0000000048a1', 'customers.view', true),
  -- ‏a2: איש משרד מן השורה — הדלת סגורה, ולכן 42501 ולא `denied` רך.
  ('20000000-0000-0000-0000-0000000048a2', 'reports.load',  false),
  ('20000000-0000-0000-0000-0000000048a2', 'reports.view',  false),
  ('20000000-0000-0000-0000-0000000048a2', 'dashboard.view', false),
  -- ‏a3: המפתח כן, ההיקף לא.
  ('20000000-0000-0000-0000-0000000048a3', 'reports.load',  true),
  ('20000000-0000-0000-0000-0000000048a3', 'board.view',    true),
  -- ‏a4: לקוח שהמפתח הוענק לו בטעות. `applies_to` הוא staff בלבד, וגם אילו
  -- היה נתפס — `app.load_denied` חוסמת אותו על `user_kind`.
  ('20000000-0000-0000-0000-0000000048a4', 'reports.load',  true);

insert into permission_scopes (profile_id, resource, scope_type, scope_values) values
  ('20000000-0000-0000-0000-0000000048a3', 'tasks', 'customers',
   array['10000000-0000-0000-0000-00000000048a']::uuid[]);

insert into trucks (id, name) values
  ('12000000-0000-0000-0000-00000000048a', 'משאית 48 א'),
  ('12000000-0000-0000-0000-00000000048b', 'משאית 48 ב'),
  ('12000000-0000-0000-0000-00000000048c', 'משאית 48 ג');

insert into warehouses (id, name) values
  ('13000000-0000-0000-0000-00000000048a', 'מחסן 48');

-- התאריכים. `+700` מרחיק את החבילה מכל טווח אחר, ו-`d0` מעוגן ליום ראשון
-- כדי ששום דבר כאן לא ייפול על גבול חודש באמצע הטווח.
create temp table t48 as
select date_trunc('week', current_date + 700)::date + 6      as d0,
       date_trunc('week', current_date + 700)::date + 7      as d1,
       date_trunc('week', current_date + 700)::date + 8      as d2,
       date_trunc('week', current_date + 700)::date + 9      as d3,
       date_trunc('week', current_date + 700)::date + 10     as d4,
       date_trunc('week', current_date + 700)::date + 11     as d5,
       date_trunc('week', current_date + 700)::date + 4      as dfrom,
       date_trunc('week', current_date + 700)::date + 12     as dto;
grant select on t48 to authenticated;

insert into events (id, customer_id, event_date, location_text, status_id)
select '30000000-0000-0000-0000-00000000048a', '10000000-0000-0000-0000-00000000048a',
       d0, 'הרצל 1, תל אביב',
       (select id from statuses where entity = 'event' and code = 'planned'
                                  and deleted_at is null)
from t48;

-- האירוע השני בוטל, וכל מה שתלוי בו יורד מהמפה.
insert into events (id, customer_id, event_date, location_text, status_id)
select '30000000-0000-0000-0000-00000000048b', '10000000-0000-0000-0000-00000000048b',
       d2, 'ביאליק 9, רמת גן',
       (select id from statuses where entity = 'event' and code = 'cancelled'
                                  and deleted_at is null)
from t48;

-- ‏0009 יוצר הקמה ופירוק לכל אירוע חדש. הן אינן חלק מהאריתמטיקה כאן.
delete from tasks where event_id in ('30000000-0000-0000-0000-00000000048a',
                                     '30000000-0000-0000-0000-00000000048b');

insert into tasks (id, event_id, customer_id, task_type_id, task_date, status_id,
                   title, onsite_start_time, warehouse_start_time, hours_count,
                   worker_count, truck_ids, requires_team_lead, warehouse_id)
select v.id, v.event, v.cust,
       (select id from task_types where code = 'setup' limit 1),
       v.d,
       (select id from statuses where entity = 'task' and code = 'assigned'
                                  and deleted_at is null),
       v.title, v.onsite, v.wh, v.hours, v.workers, v.trucks, v.lead,
       '13000000-0000-0000-0000-00000000048a'
from (values
  -- היום הראשי
  ('61000000-0000-0000-0000-000000048001'::uuid, '30000000-0000-0000-0000-00000000048a'::uuid,
   '10000000-0000-0000-0000-00000000048a'::uuid, (select d0 from t48), 'T1',
   '08:00'::time, null::time, 4::numeric, 3,
   array['12000000-0000-0000-0000-00000000048a']::uuid[], true),
  ('61000000-0000-0000-0000-000000048002', '30000000-0000-0000-0000-00000000048a',
   '10000000-0000-0000-0000-00000000048a', (select d0 from t48), 'T2',
   '10:00', null, 4, 2,
   array['12000000-0000-0000-0000-00000000048a',
         '12000000-0000-0000-0000-00000000048b']::uuid[], true),
  ('61000000-0000-0000-0000-000000048003', '30000000-0000-0000-0000-00000000048a',
   '10000000-0000-0000-0000-00000000048a', (select d0 from t48), 'T3',
   '15:00', null, 2, 5,
   array['12000000-0000-0000-0000-00000000048c']::uuid[], false),
  -- בלי שעה: אינה על הציר
  ('61000000-0000-0000-0000-000000048004', '30000000-0000-0000-0000-00000000048a',
   '10000000-0000-0000-0000-00000000048a', (select d0 from t48), 'T4',
   null, null, 3, 4, '{}'::uuid[], false),
  -- ‏d1: יציאה מהמחסן ב-05:00, שטח ב-07:00 ועוד 3 שעות → ‏[05,10)
  ('61000000-0000-0000-0000-000000048005', '30000000-0000-0000-0000-00000000048a',
   '10000000-0000-0000-0000-00000000048a', (select d1 from t48), 'T5',
   '07:00', '05:00', 3, 4,
   array['12000000-0000-0000-0000-00000000048a']::uuid[], false),
  -- ‏d3: יציאה מהמחסן ב-23:00 ושטח ב-06:00 → ההגעה נסוגה ל-d2 בערב (0163)
  ('61000000-0000-0000-0000-000000048006', '30000000-0000-0000-0000-00000000048a',
   '10000000-0000-0000-0000-00000000048a', (select d3 from t48), 'T6',
   '06:00', '23:00', 2, 2,
   array['12000000-0000-0000-0000-00000000048b']::uuid[], false),
  -- ‏d2: על האירוע שבוטל — לא תיספר לעולם
  ('61000000-0000-0000-0000-000000048007', '30000000-0000-0000-0000-00000000048b',
   '10000000-0000-0000-0000-00000000048b', (select d2 from t48), 'T7 מבוטלת',
   '09:00', null, 4, 9, '{}'::uuid[], true),
  -- ‏d3: 22:00 ועוד 3 שעות — נשפכת אחרי חצות אל d4
  ('61000000-0000-0000-0000-000000048009', '30000000-0000-0000-0000-00000000048a',
   '10000000-0000-0000-0000-00000000048a', (select d3 from t48), 'T9 לילית',
   '22:00', null, 3, 2, '{}'::uuid[], false),
  -- ‏d2: תימחק רכות מיד אחרי הזריעה
  ('61000000-0000-0000-0000-000000048008', '30000000-0000-0000-0000-00000000048a',
   '10000000-0000-0000-0000-00000000048a', (select d2 from t48), 'T8 מחוקה',
   '09:00', null, 4, 7, '{}'::uuid[], true)
) as v(id, event, cust, d, title, onsite, wh, hours, workers, trucks, lead);

update tasks set deleted_at = now()
 where id = '61000000-0000-0000-0000-000000048008';

-- שני משובצים על T1 בלבד: הדרישה 3, המאויש 2, והפער 1.
insert into task_assignments (task_id, profile_id, role) values
  ('61000000-0000-0000-0000-000000048001', '20000000-0000-0000-0000-0000000048b1', 'worker'),
  ('61000000-0000-0000-0000-000000048001', '20000000-0000-0000-0000-0000000048b2', 'worker'),
  -- אותו אדם גם כנהג על אותה משימה: ראש אחד, לא שניים.
  ('61000000-0000-0000-0000-000000048001', '20000000-0000-0000-0000-0000000048b2', 'driver');

-- ‏T2 הואצלה לקבלן — לא כדי להוריד עומס, אלא כדי שהעמודה תדע לומר עליו.
insert into task_contractor_terms (task_id, contractor_id, price) values
  ('61000000-0000-0000-0000-000000048002', '11000000-0000-0000-0000-00000000048a', 100);

-- התקרה, במפורש: שלושת המספרים אינם תלויים במה שחבילות אחרות זרעו.
insert into app_settings (key, value) values
  ('ops.capacity', jsonb_build_object('workers', 10, 'trucks', 4, 'team_leads', 2))
on conflict (key) do update set value = excluded.value;

-- ===== עוזרים ==============================================================
--
-- אותה הכרעה של 13: הקריאות חוזרות, והאסרשנים נקראים כשהן מקוצרות לשם.

create or replace function t48map() returns jsonb language sql stable as $$
  select load_heatmap((select dfrom from t48), (select dto from t48))
$$;
grant execute on function t48map() to authenticated;

create or replace function t48day(p_day date) returns jsonb language sql stable as $$
  select (select e from jsonb_array_elements(t48map() -> 'days') e
           where e ->> 'day' = p_day::text)
$$;
grant execute on function t48day(date) to authenticated;

create or replace function t48hour(p_day date, p_hour int) returns jsonb
language sql stable as $$
  select (select h from jsonb_array_elements(load_day(p_day) -> 'hours') h
           where (h ->> 'hour')::int = p_hour)
$$;
grant execute on function t48hour(date, int) to authenticated;

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000048a1', false);

\echo '--- 1. השעה סופרת מקבילות, לא סכום ---'

select t_eq('08:00 — משימה אחת',
  ((select t48hour(d0, 8) from t48) ->> 'tasks')::int, 1);
select t_eq('08:00 — שלושה עובדים',
  ((select t48hour(d0, 8) from t48) ->> 'workers')::int, 3);
select t_eq('10:00 — שתי המשימות חופפות',
  ((select t48hour(d0, 10) from t48) ->> 'tasks')::int, 2);
select t_eq('10:00 — חמישה עובדים בו-זמנית',
  ((select t48hour(d0, 10) from t48) ->> 'workers')::int, 5);
select t_eq('10:00 — שתי משאיות, ולא שלוש: TR1 משרתת את שתיהן',
  ((select t48hour(d0, 10) from t48) ->> 'trucks')::int, 2);
select t_eq('10:00 — שני ראשי צוות',
  ((select t48hour(d0, 10) from t48) ->> 'leads')::int, 2);
select t_eq('12:00 — T1 נסגרה, ונשארה T2 בלבד',
  ((select t48hour(d0, 12) from t48) ->> 'tasks')::int, 1);
select t_eq('14:00 — החלון הוא [) ולכן השעה ריקה',
  ((select t48hour(d0, 14) from t48) ->> 'tasks')::int, 0);
-- ‏0181: T4 אינה מסומנת `requires_team_lead`, ובכל זאת נדרש לה ראש צוות —
-- אופן הביצוע שלה אינו הובלה בלבד ואינו איסוף עצמי, וזה הכלל.
select t_eq('15:00 — חמישה עובדים, ונדרש להם ראש צוות',
  ((select t48hour(d0, 15) from t48) ->> 'leads')::int, 1);
select t_eq('ואף אחד לא שובץ בו',
  ((select t48hour(d0, 15) from t48) ->> 'leads_staffed')::int, 0);
select t_eq('ואותה שעה כן נושאת את חמשת העובדים',
  ((select t48hour(d0, 15) from t48) ->> 'workers')::int, 5);
select t_eq('היום כולו: 24 שעות',
  jsonb_array_length((select load_day(d0) from t48) -> 'hours'), 24);

\echo '--- 2. הפסגה היא הצוואר שנסגר ראשון ---'

select t_eq('פסגת העובדים',
  ((select t48day(d0) from t48) ->> 'peak_workers')::int, 5);
select t_eq('פסגת המשימות החופפות',
  ((select t48day(d0) from t48) ->> 'peak_tasks')::int, 2);
select t_eq('פסגת המשאיות',
  ((select t48day(d0) from t48) ->> 'peak_trucks')::int, 2);
select t_eq('פסגת ראשי הצוות',
  ((select t48day(d0) from t48) ->> 'peak_leads')::int, 2);
-- ‏15:00 נושאת את אותם חמישה עובדים, ובכל זאת 10:00 היא הפסגה: היחס מול
-- התקרה הוא שמכריע, ובו ראשי הצוות מגיעים ל-100% ועובדים ל-50%.
select t_eq('והשעה העמוסה היא 10:00 — ראשי הצוות, לא העובדים',
  ((select t48day(d0) from t48) ->> 'peak_hour')::int, 10);
-- ‏{8,9,10,11} ∪ {10,11,12,13} ∪ {15,16} — שמונה שעות, ולא עשר: החפיפה
-- נספרת פעם אחת, וזה בדיוק ההבדל בין "שעות עסוקות" לבין סכום המשכים.
select t_eq('שמונה שעות עסוקות ביום',
  ((select t48day(d0) from t48) ->> 'busy_hours')::int, 8);

\echo '--- 3. סך היום נספר מהמשימות, לא מהשעות ---'

select t_eq('ארבע משימות ביום — גם זו שאין לה שעה',
  ((select t48day(d0) from t48) ->> 'tasks')::int, 4);
select t_eq('שלוש מהן על ציר השעות',
  ((select t48day(d0) from t48) ->> 'timed')::int, 3);
select t_eq('ואחת בלי שעה — נספרת בנפרד ולא נעלמת',
  ((select t48day(d0) from t48) ->> 'untimed')::int, 1);
select t_eq('ארבעה-עשר עובדים נדרשים — הדרישה של כל ארבע',
  ((select t48day(d0) from t48) ->> 'worker_need')::int, 14);
select t_eq('שעות-עובד: 3×4 + 2×4 + 5×2',
  ((select t48day(d0) from t48) ->> 'worker_hours')::numeric, 30::numeric);
select t_eq('שני משובצים, והאדם שמופיע בשני תפקידים נספר פעם אחת',
  ((select t48day(d0) from t48) ->> 'staffed')::int, 2);
select t_eq('ולכן פער האיוש הוא 12',
  ((select t48day(d0) from t48) ->> 'gap')::int, 12);
select t_eq('ארבעה ראשי צוות נדרשים — אחד לכל משימה',
  ((select t48day(d0) from t48) ->> 'lead_need')::int, 4);
select t_eq('ואף אחד מהם לא שובץ',
  ((select t48day(d0) from t48) ->> 'lead_staffed')::int, 0);
select t_eq('משימה אחת הואצלה',
  ((select t48day(d0) from t48) ->> 'delegated')::int, 1);

\echo '--- 4. החלון נפתח ביציאה מהמחסן ---'

select t_eq('05:00 — היציאה למחסן פותחת את החלון',
  ((select t48hour(d1, 5) from t48) ->> 'tasks')::int, 1);
select t_eq('04:00 — עוד לפניה, ולכן ריקה',
  ((select t48hour(d1, 4) from t48) ->> 'tasks')::int, 0);
select t_eq('09:00 — עדיין בתוך החלון',
  ((select t48hour(d1, 9) from t48) ->> 'tasks')::int, 1);
select t_eq('10:00 — השטח נגמר, והחלון איתו',
  ((select t48hour(d1, 10) from t48) ->> 'tasks')::int, 0);
select t_eq('חמש שעות עסוקות',
  ((select t48day(d1) from t48) ->> 'busy_hours')::int, 5);

-- ‏0163: יציאה ב-23:00 לשטח של 06:00 נופלת בערב שלפני. היום שבו היא נופלת
-- הוא d2, והמשימה עצמה נשארת של d3 — בדיוק כפי שכל מסך אחר מציג אותה.
select t_eq('היציאה שנסוגה: 23:00 של היום שלפני כן תפוסה',
  ((select t48hour(d2, 23) from t48) ->> 'tasks')::int, 1);
select t_eq('אבל המשימה נספרת ליום שלה',
  ((select t48day(d3) from t48) ->> 'tasks')::int, 2);
select t_eq('וביום שלפניה אין משימות משלו',
  ((select t48day(d2) from t48) ->> 'tasks')::int, 0);
-- ומצד הרשימה: `load_day` של d2 כן מציג אותה, כי היא נוגעת ביום.
select t_eq('ורשימת היום כן מציגה אותה, כי היא נוגעת בו',
  (select count(*)::int from jsonb_array_elements((select load_day(d2) from t48) -> 'tasks') x
    where x ->> 'task_id' = '61000000-0000-0000-0000-000000048006'), 1);

-- הצד השני של אותו גבול: משימה שנמשכת אחרי חצות. הטווח של `app.load_tasks`
-- הוא טווח של זמן ולא של תאריכי משימה, ולכן היא נוגעת גם ביום שאחריה.
select t_eq('חצות: המשימה הלילית נשפכת אל היום שאחריה',
  ((select t48hour(d4, 0) from t48) ->> 'tasks')::int, 1);
select t_eq('ונגמרת ב-01:00',
  ((select t48hour(d4, 1) from t48) ->> 'tasks')::int, 0);
select t_eq('ובכל זאת אינה משימה של אותו יום',
  ((select t48day(d4) from t48) ->> 'tasks')::int, 0);
select t_eq('אבל כן מופיעה ברשימת היום שלו',
  (select count(*)::int from jsonb_array_elements((select load_day(d4) from t48) -> 'tasks') x
    where x ->> 'task_id' = '61000000-0000-0000-0000-000000048009'), 1);

\echo '--- 5. מה שאינו נספר ---'

select t_eq('משימה על אירוע שבוטל אינה על המפה',
  (select count(*)::int from jsonb_array_elements((select load_day(d2) from t48) -> 'tasks') x
    where x ->> 'task_id' = '61000000-0000-0000-0000-000000048007'), 0);
select t_eq('וגם לא בשעה שלה',
  ((select t48hour(d2, 9) from t48) ->> 'tasks')::int, 0);
select t_eq('משימה שנמחקה רכות אינה על המפה',
  (select count(*)::int from jsonb_array_elements((select load_day(d2) from t48) -> 'tasks') x
    where x ->> 'task_id' = '61000000-0000-0000-0000-000000048008'), 0);
-- ‏0181: היא כן ברשימה, ומסומנת `timed = false` — אין לה מקום על הציר,
-- אבל היא עבודה של היום ואי אפשר לשתוק עליה.
select t_eq('ומשימה בלי שעה כן ברשימת היום',
  (select count(*)::int from jsonb_array_elements((select load_day(d0) from t48) -> 'tasks') x
    where x ->> 'task_id' = '61000000-0000-0000-0000-000000048004'), 1);
select t_eq('ומסומנת שאין לה שעה',
  (select (x ->> 'timed')::boolean from jsonb_array_elements((select load_day(d0) from t48) -> 'tasks') x
    where x ->> 'task_id' = '61000000-0000-0000-0000-000000048004'), false);
select t_eq('ואין לה חלון',
  (select (x -> 'start') = 'null'::jsonb from jsonb_array_elements((select load_day(d0) from t48) -> 'tasks') x
    where x ->> 'task_id' = '61000000-0000-0000-0000-000000048004'), true);

\echo '--- 6. רשימת היום אומרת בגלל מה ---'

select t_eq('ארבע משימות ברשימה',
  jsonb_array_length((select load_day(d0) from t48) -> 'tasks'), 4);
select t_eq('והראשונה היא המוקדמת ביותר',
  ((select load_day(d0) from t48) -> 'tasks' -> 0 ->> 'label'), 'T1');
select t_eq('עם הדרישה שלה',
  (((select load_day(d0) from t48) -> 'tasks' -> 0 ->> 'worker_need'))::int, 3);
select t_eq('ומה שכבר מאויש עליה',
  (((select load_day(d0) from t48) -> 'tasks' -> 0 ->> 'staffed'))::int, 2);
select t_eq('ומספר המשאיות שהיא תופסת',
  (((select load_day(d0) from t48) -> 'tasks' -> 1 ->> 'trucks'))::int, 2);
select t_eq('ומי מהן הואצלה',
  (((select load_day(d0) from t48) -> 'tasks' -> 1 ->> 'delegated'))::boolean, true);

\echo '--- 7. התקרה ---'

select t_eq('התקרה שהוגדרה היא זו שחוזרת',
  ((select t48map() -> 'meta' -> 'capacity' ->> 'team_leads'))::int, 2);
select t_eq('ומוצהר עליה שהיא הוגדרה ולא נגזרה',
  ((select t48map() -> 'meta' -> 'capacity' -> 'source' ->> 'team_leads')), 'configured');
select t_eq('ואותה תקרה מגיעה גם לפילוח היומי',
  (((select load_day(d0) from t48) -> 'meta' -> 'capacity' ->> 'workers'))::int, 10);

\echo '--- 8. מי מקבל מספרים ---'

select t_eq('הרכז מקבל את כל ימי הטווח',
  jsonb_array_length(t48map() -> 'days'), (select (dto - dfrom + 1)::int from t48));
select t_eq('ואינו נדחה',
  (t48map() -> 'meta' ->> 'denied')::boolean, false);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000048a3', false);
select t_eq('קורא בהיקף מצומצם אינו מקבל מפה חלקית',
  (t48map() -> 'days') = 'null'::jsonb, true);
select t_eq('אלא דחייה מפורשת',
  (t48map() -> 'meta' ->> 'denied')::boolean, true);
select t_eq('ואותה דחייה גם ביום הבודד',
  ((select load_day(d0) from t48) -> 'meta' ->> 'denied')::boolean, true);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000048a4', false);
select t_eq('לקוח אינו מקבל את העומס של העסק',
  (t48map() -> 'meta' ->> 'denied')::boolean, true);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000048a2', false);
select t_expect_fail('בלי המפתח הדלת נסגרת, ולא מחזירה מפה ריקה',
  'select load_heatmap(current_date, current_date)');
select t_expect_fail('וגם היום הבודד',
  'select load_day(current_date)');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000048a0', false);
select t_eq('מנהל מערכת רואה הכול',
  (t48map() -> 'meta' ->> 'denied')::boolean, false);

\echo '--- 9. הגבולות וה-ACL ---'

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000048a1', false);
select t_expect_fail('טווח הפוך נדחה',
  'select load_heatmap(current_date + 5, current_date)');
select t_expect_fail('וטווח גדול מדי',
  'select load_heatmap(current_date, current_date + 500)');
select t_expect_fail('וטווח חסר',
  'select load_heatmap(null, current_date)');

reset role;
select t_eq('anon אינו רשאי להריץ את המפה',
  has_function_privilege('anon', 'load_heatmap(date,date)', 'EXECUTE'), false);
select t_eq('ולא את היום',
  has_function_privilege('anon', 'load_day(date)', 'EXECUTE'), false);
select t_eq('ו-authenticated כן',
  has_function_privilege('authenticated', 'load_heatmap(date,date)', 'EXECUTE'), true);

select set_config('request.jwt.claim.sub', '', false);

\echo '--- 10. מה שנדרש, ולא מה ששובץ (0181) ---'

reset role;

-- אירוע שלישי, וביום משלו: כאן הדרישה נאמרת במפורש — ‏`truck_count` על
-- האירוע — ואילו בשטח שובצה משאית אחת בלבד.
insert into events (id, customer_id, event_date, location_text, truck_count, status_id)
select '30000000-0000-0000-0000-00000000048c', '10000000-0000-0000-0000-00000000048a',
       d5, 'סוקולוב 3, הרצליה', 3,
       (select id from statuses where entity = 'event' and code = 'planned'
                                  and deleted_at is null)
from t48;
delete from tasks where event_id = '30000000-0000-0000-0000-00000000048c';

insert into tasks (id, event_id, customer_id, task_type_id, task_date, status_id,
                   title, onsite_start_time, hours_count, worker_count, truck_ids,
                   requires_team_lead, execution_method_id)
select v.id, '30000000-0000-0000-0000-00000000048c',
       '10000000-0000-0000-0000-00000000048a',
       (select id from task_types where code = 'setup' limit 1),
       (select d5 from t48),
       (select id from statuses where entity = 'task' and code = 'assigned'
                                  and deleted_at is null),
       v.title, v.onsite, v.hours, v.workers, v.trucks, v.lead,
       (select id from execution_methods where btrim(name) = v.method
                                           and deleted_at is null limit 1)
from (values
  -- שתי משימות של אותו אירוע, באותה שעה: הדרישה למשאיות היא של האירוע,
  -- ונספרת פעם אחת ולא פעמיים.
  ('62000000-0000-0000-0000-000000048010'::uuid, 'T10', '10:00'::time, 2::numeric, 2,
   array['12000000-0000-0000-0000-00000000048a']::uuid[], null::boolean, 'סידור'),
  ('62000000-0000-0000-0000-000000048011', 'T11', '10:00', 2, 2, '{}'::uuid[], null, 'סידור'),
  -- הובלה בלבד ואיסוף עצמי — שני הפטורים
  ('62000000-0000-0000-0000-000000048012', 'T12', '14:00', 2, 2, '{}'::uuid[], null, 'הובלה בלבד'),
  ('62000000-0000-0000-0000-000000048013', 'T13', '14:00', 2, 2, '{}'::uuid[], null, 'איסוף עצמי'),
  -- ולצדם משימה רגילה, שראש הצוות שלה כבר שובץ
  ('62000000-0000-0000-0000-000000048014', 'T14', '14:00', 2, 2, '{}'::uuid[], null, 'סידור')
) as v(id, title, onsite, hours, workers, trucks, lead, method);

insert into task_assignments (task_id, profile_id, role) values
  ('62000000-0000-0000-0000-000000048014', '20000000-0000-0000-0000-0000000048b1', 'team_lead');

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000048a1', false);

select t_eq('10:00 — שלוש משאיות נדרשות, כפי שנאמר על האירוע',
  ((select t48hour(d5, 10) from t48) ->> 'trucks')::int, 3);
select t_eq('ורק אחת שובצה בפועל',
  ((select t48hour(d5, 10) from t48) ->> 'trucks_assigned')::int, 1);
select t_eq('שתי משימות של אותו אירוע אינן מכפילות את הדרישה',
  ((select t48hour(d5, 10) from t48) ->> 'tasks')::int, 2);

select t_eq('14:00 — שלוש משימות',
  ((select t48hour(d5, 14) from t48) ->> 'tasks')::int, 3);
select t_eq('ורק אחת מהן דורשת ראש צוות: הובלה בלבד ואיסוף עצמי פטורות',
  ((select t48hour(d5, 14) from t48) ->> 'leads')::int, 1);
select t_eq('והוא כבר שובץ',
  ((select t48hour(d5, 14) from t48) ->> 'leads_staffed')::int, 1);

select t_eq('סך היום: שלוש משאיות נדרשות',
  ((select t48day(d5) from t48) ->> 'truck_need')::int, 3);
select t_eq('ואחת משובצת',
  ((select t48day(d5) from t48) ->> 'truck_assigned')::int, 1);
select t_eq('שלושה ראשי צוות נדרשים ביום',
  ((select t48day(d5) from t48) ->> 'lead_need')::int, 3);
select t_eq('ואחד מהם שובץ',
  ((select t48day(d5) from t48) ->> 'lead_staffed')::int, 1);
