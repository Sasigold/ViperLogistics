\pset tuples_only on
\pset format unaligned

-- ===========================================================================
-- ‏84: מסך הקיר רואה את העבודה ואת הרווח (0241).
--
-- יום D = current_date + 2000 — מעבר לכל טווח אחר (82 ביולי ארבע שנים קדימה,
-- 83 ב-+900, השאר עד +1300). "עכשיו" ננעץ ל-10:00 של D בישראל.
--
--   לו״ז מחסן: לקוח עם הדגל (W) ולקוח בלעדיו (N), אירועים ב-D+10 (כך שהתאריכים
--   הנגזרים נופלים מחוץ לחלון D..D+3). הכנה של W ב-D 09:00 לשעתיים
--   עם אישור סופי; החזרה של W ב-D בלי שעה; הכנה של N ב-D — לא בפיד.
--   משימות ניהול: באיחור (3 צעדים, אחד בוצע), להיום, למחרתיים, אחת שבוצעה
--   בזמן ואחת באיחור היום, ואחת שנמחקה. שאר המשימות במסד מוסתרות בטרנזקציה.
--   נוכחות: "מאחר 84" נכנס 20 דק׳ אחרי תחילת המשמרת, "בזמן 84" אחרי 2 דק׳;
--   "יצא 84" יצא ב-09:30, "יצא מזמן 84" ב-05:00, "חזר 84" יצא וחזר למשמרת.
--   רווח: הפיד מול הסקשן "רווח" של הדשבורד, באותו טווח.
-- ===========================================================================

-- ה-seed מעניק הכול ל-authenticated; ההרשאות של 0241 נאמרות שוב
revoke execute on function app.profit_summary_core(date, date) from public, anon, authenticated, service_role;
revoke execute on function app.profit_summary(date, date) from anon, public;
grant  execute on function app.profit_summary(date, date) to authenticated;
revoke execute on function app.warehouse_rows_core(date, date, uuid) from public, anon, authenticated, service_role;
revoke all on function app.wall_snapshot_at(timestamptz, int) from public, anon, authenticated, service_role;

create or replace function t84_day() returns date language sql stable as $$
  select current_date + 2000
$$;
create or replace function t84_at(p_offset int, p_time time) returns timestamptz
language sql stable as $$
  select ((t84_day() + p_offset) + p_time) at time zone 'Asia/Jerusalem'
$$;
create or replace function t84_snap() returns jsonb language sql stable as $$
  select app.wall_snapshot_at(t84_at(0, '10:00'), 3)
$$;
create or replace function t84_state(p_sql text) returns text language plpgsql as $$
begin
  execute p_sql;
  return 'ok';
exception when others then
  return sqlstate;
end $$;

-- ===== לו״ז המחסן ==========================================================

insert into customers (id, name, warehouse_schedule_enabled) values
  ('10000000-0000-0000-0000-00000000084a', 'מחסן 84', true),
  ('10000000-0000-0000-0000-00000000084b', 'רגיל 84', false);

insert into events (id, customer_id, event_number, end_client_name, event_date, status_id)
select v.id::uuid, v.cust::uuid, v.num, v.client, t84_day() + 10,
       (select id from statuses where entity = 'event' and code = 'pending' and deleted_at is null)
  from (values
    ('30000000-0000-0000-0000-00000000084a', '10000000-0000-0000-0000-00000000084a', 'EV-84-A', 'חתונה 84'),
    ('30000000-0000-0000-0000-00000000084b', '10000000-0000-0000-0000-00000000084a', 'EV-84-B', 'כנס 84'),
    ('30000000-0000-0000-0000-00000000084c', '10000000-0000-0000-0000-00000000084b', 'EV-84-C', 'רגיל 84')) v(id, cust, num, client);

insert into warehouse_tasks (event_id, customer_id, kind, task_date, start_time, duration_hours, final_approved)
values
  ('30000000-0000-0000-0000-00000000084a', '10000000-0000-0000-0000-00000000084a', 'prep',   t84_day(), '09:00', 2, true),
  ('30000000-0000-0000-0000-00000000084b', '10000000-0000-0000-0000-00000000084a', 'return', t84_day(), null,    null, false),
  ('30000000-0000-0000-0000-00000000084c', '10000000-0000-0000-0000-00000000084b', 'prep',   t84_day(), '09:00', 2, true);

select t_eq('לו״ז המחסן: שתי השורות של הלקוח עם הדגל ביום D',
  (select count(*)::int from jsonb_array_elements(t84_snap() -> 'warehouse_tasks') w
    where w ->> 'event_number' like 'EV-84-%' and (w ->> 'date')::date = t84_day()), 2);
select t_eq('לקוח בלי הדגל אינו בלו״ז המחסן',
  (select count(*)::int from jsonb_array_elements(t84_snap() -> 'warehouse_tasks') w
    where w ->> 'event_number' = 'EV-84-C'), 0);
select t_eq('ההכנה: 09:00–11:00 בישראל, אישור סופי, לא מוכן ולא נבדק',
  (select jsonb_build_array((w ->> 'start_at')::timestamptz = t84_at(0, '09:00'),
                            (w ->> 'end_at')::timestamptz = t84_at(0, '11:00'),
                            w ->> 'kind', w ->> 'final_approved', w ->> 'event_ready', w ->> 'checked',
                            w ->> 'customer_name')
     from jsonb_array_elements(t84_snap() -> 'warehouse_tasks') w
    where w ->> 'event_number' = 'EV-84-A' and w ->> 'kind' = 'prep'),
  '[true, true, "prep", "true", "false", "false", "מחסן 84"]'::jsonb);
select t_eq('החזרה בלי שעה — בלי start_at ובלי end_at',
  (select jsonb_build_array(w -> 'start_at', w -> 'end_at')
     from jsonb_array_elements(t84_snap() -> 'warehouse_tasks') w
    where w ->> 'event_number' = 'EV-84-B' and w ->> 'kind' = 'return'),
  '[null, null]'::jsonb);
select t_eq('הפיד = הליבה של הלו״ז באותו טווח (הכלל נכתב פעם אחת)',
  jsonb_array_length(t84_snap() -> 'warehouse_tasks'),
  (select count(*)::int from app.warehouse_rows_core(t84_day(), t84_day() + 3, null)));

-- ===== משימות ניהול ========================================================

insert into profiles (id, user_kind, is_admin, full_name) values
  ('20000000-0000-0000-0000-0000000084f1', 'staff', true, 'מנהלת 84');

insert into admin_missions (id, title, owner_id, due_at, priority, status, done_at, deleted_at, created_at) values
  ('74000000-0000-0000-0000-000000084001', 'באיחור 84',     '20000000-0000-0000-0000-0000000084f1', t84_at(0, '08:00'), 1, 'open', null, null, t84_at(-3, '08:00')),
  ('74000000-0000-0000-0000-000000084002', 'להיום 84',      '20000000-0000-0000-0000-0000000084f1', t84_at(0, '15:00'), 2, 'open', null, null, t84_at(-3, '08:00')),
  ('74000000-0000-0000-0000-000000084003', 'למחרתיים 84',   '20000000-0000-0000-0000-0000000084f1', t84_at(2, '12:00'), 3, 'open', null, null, t84_at(-3, '08:00')),
  ('74000000-0000-0000-0000-000000084004', 'בוצעה בזמן 84', '20000000-0000-0000-0000-0000000084f1', t84_at(0, '12:00'), 2, 'done', t84_at(0, '09:00'), null, t84_at(-3, '08:00')),
  ('74000000-0000-0000-0000-000000084005', 'בוצעה באיחור 84','20000000-0000-0000-0000-0000000084f1', t84_at(0, '07:00'), 2, 'done', t84_at(0, '08:30'), null, t84_at(-3, '08:00')),
  ('74000000-0000-0000-0000-000000084006', 'נמחקה 84',      '20000000-0000-0000-0000-0000000084f1', t84_at(0, '08:00'), 1, 'open', null, t84_at(-1, '08:00'), t84_at(-3, '08:00'));

insert into admin_mission_steps (mission_id, title, sort, done_at, deleted_at) values
  ('74000000-0000-0000-0000-000000084001', 'א', 1, t84_at(-1, '10:00'), null),
  ('74000000-0000-0000-0000-000000084001', 'ב', 2, null, null),
  ('74000000-0000-0000-0000-000000084001', 'ג', 3, null, null),
  ('74000000-0000-0000-0000-000000084001', 'נמחק', 4, null, t84_at(-1, '10:00'));

begin;
-- רק המשימות של החבילה הזו: השאר מוסתרות עד ה-rollback
update admin_missions set deleted_at = now()
 where deleted_at is null and id::text not like '74000000-0000-0000-0000-000000084%';

select t_eq('מונים: פתוחות 3, באיחור 1, להיום 1, בוצעו השבוע 2, מתוכן בזמן 1',
  (select jsonb_build_array(m -> 'open', m -> 'overdue', m -> 'due_today', m -> 'done_week', m -> 'done_week_on_time')
     from (select t84_snap() -> 'missions' as m) x),
  '[3, 1, 1, 2, 1]'::jsonb);
select t_eq('הפתוחות לפי יעד, בלי המחוקה',
  (select jsonb_agg(i ->> 'title' order by o)
     from jsonb_array_elements(t84_snap() -> 'missions' -> 'items') with ordinality as a(i, o)),
  '["באיחור 84", "להיום 84", "למחרתיים 84"]'::jsonb);
select t_eq('הצעדים: 3 חיים, אחד בוצע; שם הבעלים',
  (select jsonb_build_array(i -> 'steps_total', i -> 'steps_done', i ->> 'owner_name', i -> 'priority')
     from jsonb_array_elements(t84_snap() -> 'missions' -> 'items') i
    where i ->> 'title' = 'באיחור 84'),
  '[3, 1, "מנהלת 84", 1]'::jsonb);
select t_eq('בוצעו לאחרונה — האחרונה ראשונה',
  (select jsonb_agg(i ->> 'title' order by o)
     from jsonb_array_elements(t84_snap() -> 'missions' -> 'recent_done') with ordinality as a(i, o)),
  '["בוצעה בזמן 84", "בוצעה באיחור 84"]'::jsonb);
rollback;

-- ===== נוכחות: התחילו באיחור, סיימו לאחרונה ================================

insert into profiles (id, user_kind, is_admin, full_name) values
  ('20000000-0000-0000-0000-0000000084a1', 'staff', false, 'מאחר 84'),
  ('20000000-0000-0000-0000-0000000084a2', 'staff', false, 'בזמן 84'),
  ('20000000-0000-0000-0000-0000000084a3', 'staff', false, 'יצא 84'),
  ('20000000-0000-0000-0000-0000000084a4', 'staff', false, 'יצא מזמן 84'),
  ('20000000-0000-0000-0000-0000000084a5', 'staff', false, 'חזר 84');

-- ההקמה והפירוק שנולדים עם כל אירוע אינם חלק מהתרחיש
update tasks set deleted_at = now()
 where event_id in ('30000000-0000-0000-0000-00000000084a', '30000000-0000-0000-0000-00000000084b',
                    '30000000-0000-0000-0000-00000000084c');

insert into tasks (id, event_id, customer_id, task_type_id, task_date, title,
                   warehouse_start_time, onsite_start_time, hours_count, status_id, worker_count)
values ('62000000-0000-0000-0000-000000084001', '30000000-0000-0000-0000-00000000084a',
        '10000000-0000-0000-0000-00000000084a', (select id from task_types where code = 'setup' limit 1),
        t84_day(), 'הקמה 84', null, '08:00', 4,
        (select id from statuses where entity = 'task' and code = 'assigned' and deleted_at is null), 2);

insert into task_assignments (task_id, profile_id, role, work_site) values
  ('62000000-0000-0000-0000-000000084001', '20000000-0000-0000-0000-0000000084a1', 'worker', 'field'),
  ('62000000-0000-0000-0000-000000084001', '20000000-0000-0000-0000-0000000084a2', 'worker', 'field');

-- תחילת המשמרת כפי שהמערכת גוזרת אותה, ולא כפי שהבדיקה מנחשת
create temp table t84_plan as
select s.profile_id, min(s.shift_start) as shift_start
  from app.planned_shifts_many(array['20000000-0000-0000-0000-0000000084a1',
                                     '20000000-0000-0000-0000-0000000084a2']::uuid[], t84_day(), t84_day()) s
 group by s.profile_id;

select t_eq('לשני העובדים יש משמרת מתוכננת ביום D', (select count(*)::int from t84_plan), 2);

insert into attendance_entries (profile_id, work_date, seq, clock_in_at, clock_out_at, source, status, work_site)
select '20000000-0000-0000-0000-0000000084a1'::uuid, t84_day(), 1, shift_start + interval '20 minutes', null::timestamptz, 'clock', 'approved', 'field'
  from t84_plan where profile_id = '20000000-0000-0000-0000-0000000084a1'
union all
select '20000000-0000-0000-0000-0000000084a2'::uuid, t84_day(), 1, shift_start + interval '2 minutes', null::timestamptz, 'clock', 'approved', 'field'
  from t84_plan where profile_id = '20000000-0000-0000-0000-0000000084a2';

insert into attendance_entries (profile_id, work_date, seq, clock_in_at, clock_out_at, source, status, work_site) values
  ('20000000-0000-0000-0000-0000000084a3', t84_day(), 1, t84_at(0, '06:00'), t84_at(0, '09:30'), 'clock', 'approved', 'warehouse'),
  ('20000000-0000-0000-0000-0000000084a4', t84_day(), 1, t84_at(0, '01:00'), t84_at(0, '05:00'), 'clock', 'approved', 'field'),
  ('20000000-0000-0000-0000-0000000084a5', t84_day(), 1, t84_at(0, '06:00'), t84_at(0, '08:00'), 'clock', 'approved', 'field'),
  ('20000000-0000-0000-0000-0000000084a5', t84_day(), 2, t84_at(0, '09:00'), null,               'clock', 'approved', 'field');

select t_eq('התחיל באיחור: 20 דקות, עם תחילת המשמרת וההחתמה',
  (select jsonb_build_array(l -> 'minutes_late',
                            (l ->> 'planned_start')::timestamptz = (select shift_start from t84_plan
                                                                     where profile_id = '20000000-0000-0000-0000-0000000084a1'),
                            l ->> 'task_label' like '%הקמה 84%')
     from jsonb_array_elements(t84_snap() -> 'attendance' -> 'late_started') l
    where l ->> 'name' = 'מאחר 84'),
  '[20, true, true]'::jsonb);
select t_eq('שתי דקות אינן איחור על המסך (סף 5)',
  (select count(*)::int from jsonb_array_elements(t84_snap() -> 'attendance' -> 'late_started') l
    where l ->> 'name' = 'בזמן 84'), 0);
select t_eq('סיים לאחרונה: יצא ב-09:30 אחרי 3.5 שעות, מהמחסן',
  (select jsonb_build_array((l ->> 'clock_out_at')::timestamptz = t84_at(0, '09:30'), l -> 'hours', l ->> 'work_site')
     from jsonb_array_elements(t84_snap() -> 'attendance' -> 'ended_recently') l
    where l ->> 'name' = 'יצא 84'),
  '[true, 3.5, "warehouse"]'::jsonb);
select t_eq('מי שיצא לפני יותר מארבע שעות, ומי שחזר למשמרת — לא ברשימה',
  (select count(*)::int from jsonb_array_elements(t84_snap() -> 'attendance' -> 'ended_recently') l
    where l ->> 'name' in ('יצא מזמן 84', 'חזר 84')), 0);
select t_eq('ומי שחזר — במשמרת עכשיו',
  (select count(*)::int from jsonb_array_elements(t84_snap() -> 'shifts_now') l
    where l ->> 'name' = 'חזר 84'), 1);
select t_eq('המונים הישנים במקומם (late הוא עדיין "לא החתימו")',
  jsonb_typeof(t84_snap() -> 'attendance' -> 'late'), 'array');

-- ===== הרווח ==============================================================

select t_eq('רווח הקיר = הליבה מתחילת החודש עד היום',
  (select t84_snap() -> 'finance' -> 'profit'),
  (select jsonb_build_object(
            'revenue', c -> 'revenue', 'contractor', c -> 'contractor', 'payroll', c -> 'payroll',
            'employer_pct', c -> 'employer_pct', 'payroll_with_employer', c -> 'payroll_with_employer',
            'profit', c -> 'profit', 'pct', c -> 'pct')
     from (select app.profit_summary_core(date_trunc('month', t84_day())::date, t84_day()) c) x));

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false);
select t_eq('הבעלים: העטיפה = הסקשן "רווח" של הדשבורד = הליבה, באותו טווח',
  app.profit_summary(current_date - 40, current_date + 5)
    = dashboard_sections(array['finance.profit_summary'], current_date - 40, current_date + 5) -> 'finance.profit_summary',
  true);
select t_eq('authenticated אינו מריץ את הליבה',
  t84_state($$select app.profit_summary_core(current_date, current_date)$$), '42501');
select t_eq('ולא את ליבת המחסן',
  t84_state($$select * from app.warehouse_rows_core(current_date, current_date, null)$$), '42501');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000f3', false);
select t_eq('משתמש בלי מפתחות הרווח — העטיפה עונה 42501',
  t84_state($$select app.profit_summary(current_date, current_date)$$), '42501');
reset role;
