\pset tuples_only on
\pset format unaligned

-- ===========================================================================
-- 34: תשלום לקבוצה שלמה (0143), ואיסוף מספקים על הלו״ז (0144).
--
--   * **הסימון הקבוצתי** כותב לכל שורה את המחיר *שלה*, נעצר בקבלן שעל המסך
--     ואינו נוגע בשורה של קבלן אחר על אותה משימה, והוא הפיך.
--   * **RLS ממשיכה להכריע**: מנהל קבלן אינו מסמן תשלום — לא לעצמו ולא לאחר.
--   * **הלו״ז יודע שיש איסוף** ומאיזה ספקים, ואומר `false`/`null` כשאין.
--
-- החבילה מקימה לקוח, קבלנים, ספקים ושני אירועים משלה בחלון current_date+500,
-- ואינה נשענת על אף חבילה קודמת.
-- ===========================================================================

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000034a1', 'c34-admin@vl.test'),
  ('00000000-0000-0000-0000-0000000034a2', 'c34-ctrmgr@vl.test');

insert into customers (id, name) values
  ('10000000-0000-0000-0000-00000000034a', 'לקוח 34');

insert into contractors (id, name) values
  ('c0000000-0000-0000-0000-0000000034a1', 'קבלן A 34'),
  ('c0000000-0000-0000-0000-0000000034a2', 'קבלן B 34');

insert into profiles (id, user_id, user_kind, is_admin, full_name, contractor_id) values
  ('20000000-0000-0000-0000-0000000034a1', '00000000-0000-0000-0000-0000000034a1',
   'staff', true, 'מנהל מערכת 34', null),
  ('20000000-0000-0000-0000-0000000034a2', '00000000-0000-0000-0000-0000000034a2',
   'contractor_user', false, 'מנהל קבלן A 34', 'c0000000-0000-0000-0000-0000000034a1');

insert into user_permission_grants (profile_id, permission_key, allowed) values
  ('20000000-0000-0000-0000-0000000034a2', 'portal.view', true),
  ('20000000-0000-0000-0000-0000000034a2', 'portal.view_financials', true);

-- שני ספקים ללקוח, מוזרעים בסדר הפוך לסדר הא״ב כדי שהמיון ייבדק באמת
insert into suppliers (id, customer_id, name) values
  ('50000000-0000-0000-0000-0000000034b1', '10000000-0000-0000-0000-00000000034a', 'ספק ב 34'),
  ('50000000-0000-0000-0000-0000000034a1', '10000000-0000-0000-0000-00000000034a', 'ספק א 34');

-- אירוע עם איסוף, ואירוע בלעדיו
insert into events (id, customer_id, event_number, event_date, end_client_name, location_text,
                    supplier_pickup, status_id)
values
  ('30000000-0000-0000-0000-0000000034a1', '10000000-0000-0000-0000-00000000034a',
   'EV-34-A', current_date + 500, 'קצה 34', 'רחוב הבדיקה 34, תל אביב', true,
   (select id from statuses where entity = 'event' and code = 'planned' and deleted_at is null)),
  ('30000000-0000-0000-0000-0000000034a2', '10000000-0000-0000-0000-00000000034a',
   'EV-34-B', current_date + 500, 'קצה 34 ב', null, false,
   (select id from statuses where entity = 'event' and code = 'planned' and deleted_at is null));

insert into event_suppliers (event_id, supplier_id) values
  ('30000000-0000-0000-0000-0000000034a1', '50000000-0000-0000-0000-0000000034b1'),
  ('30000000-0000-0000-0000-0000000034a1', '50000000-0000-0000-0000-0000000034a1');

-- שתי המשימות של האירוע הראשון מואצלות לקבלן A, ואחת מהן גם לקבלן B
insert into task_contractor_terms (task_id, contractor_id, price, work_site)
select t.id, 'c0000000-0000-0000-0000-0000000034a1',
       case when tt.code = 'setup' then 700 else 900 end, 'field'
  from tasks t join task_types tt on tt.id = t.task_type_id
 where t.event_id = '30000000-0000-0000-0000-0000000034a1' and t.deleted_at is null;

insert into task_contractor_terms (task_id, contractor_id, price, work_site)
select t.id, 'c0000000-0000-0000-0000-0000000034a2', 400, 'field'
  from tasks t join task_types tt on tt.id = t.task_type_id
 where t.event_id = '30000000-0000-0000-0000-0000000034a1' and t.deleted_at is null
   and tt.code = 'setup';

\echo '--- 0143: סימון קבוצתי ---'
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000034a1', false);

select t_eq('שתי שורות הקבלן סומנו בקריאה אחת',
  (select set_contractor_terms_paid('c0000000-0000-0000-0000-0000000034a1',
     (select array_agg(t.id) from tasks t
       where t.event_id = '30000000-0000-0000-0000-0000000034a1' and t.deleted_at is null),
     true)), 2);

select t_eq('כל שורה קיבלה את המחיר שלה ולא מחיר אחיד',
  (select array_agg(distinct tct.paid_amount order by tct.paid_amount)
     from task_contractor_terms tct
     join tasks t on t.id = tct.task_id
    where t.event_id = '30000000-0000-0000-0000-0000000034a1'
      and tct.contractor_id = 'c0000000-0000-0000-0000-0000000034a1'),
  array[700, 900]::numeric[]);

select t_eq('ולכולן יש תאריך תשלום',
  (select count(*) from task_contractor_terms tct
     join tasks t on t.id = tct.task_id
    where t.event_id = '30000000-0000-0000-0000-0000000034a1'
      and tct.contractor_id = 'c0000000-0000-0000-0000-0000000034a1'
      and tct.paid_at is not null), 2::bigint);

select t_eq('השורה של הקבלן השני על אותה משימה לא נגעו בה (0096)',
  (select tct.paid_at from task_contractor_terms tct
     join tasks t on t.id = tct.task_id
    where t.event_id = '30000000-0000-0000-0000-0000000034a1'
      and tct.contractor_id = 'c0000000-0000-0000-0000-0000000034a2'), null::timestamptz);

select t_eq('הסימון הפיך',
  (select set_contractor_terms_paid('c0000000-0000-0000-0000-0000000034a1',
     (select array_agg(t.id) from tasks t
       where t.event_id = '30000000-0000-0000-0000-0000000034a1' and t.deleted_at is null),
     false)), 2);

select t_eq('ואחרי הביטול לא נשאר סכום ששולם',
  (select count(*) from task_contractor_terms tct
     join tasks t on t.id = tct.task_id
    where t.event_id = '30000000-0000-0000-0000-0000000034a1'
      and tct.contractor_id = 'c0000000-0000-0000-0000-0000000034a1'
      and (tct.paid_at is not null or tct.paid_amount is not null)), 0::bigint);

select t_eq('רשימה ריקה אינה נוגעת בדבר',
  (select set_contractor_terms_paid('c0000000-0000-0000-0000-0000000034a1', array[]::uuid[], true)), 0);

reset role;
select set_config('request.jwt.claim.sub', '', false);

\echo '--- 0143: מנהל קבלן אינו מסמן תשלום לעצמו ---'
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000034a2', false);
select t_eq('מנהל הקבלן אינו מסמן שולם — אף שורה',
  (select set_contractor_terms_paid('c0000000-0000-0000-0000-0000000034a1',
     (select array_agg(tct.task_id) from task_contractor_terms tct
       where tct.contractor_id = 'c0000000-0000-0000-0000-0000000034a1'),
     true)), 0);
reset role;
select set_config('request.jwt.claim.sub', '', false);

\echo '--- 0144: איסוף מספקים על הלו״ז ---'
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000034a1', false);

select t_eq('הלוח יודע שיש איסוף',
  (select bool_and(w.supplier_pickup) from work_board_view w
    where w.event_id = '30000000-0000-0000-0000-0000000034a1'), true);

select t_eq('ומביא את שמות הספקים לפי א״ב',
  (select w.supplier_names from work_board_view w
    where w.event_id = '30000000-0000-0000-0000-0000000034a1' limit 1),
  array['ספק א 34', 'ספק ב 34']::text[]);

select t_eq('אירוע בלי איסוף מדווח false',
  (select bool_or(w.supplier_pickup) from work_board_view w
    where w.event_id = '30000000-0000-0000-0000-0000000034a2'), false);

select t_eq('ובלי שמות',
  (select w.supplier_names from work_board_view w
    where w.event_id = '30000000-0000-0000-0000-0000000034a2' limit 1), null::text[]);

reset role;
select set_config('request.jwt.claim.sub', '', false);
