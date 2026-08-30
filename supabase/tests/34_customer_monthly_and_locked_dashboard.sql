\pset tuples_only on
\pset format unaligned

-- ===========================================================================
-- 34: הסיכום החודשי של הלקוח, והדשבורד שאינו שלו לסדר (0143–0144).
--
-- החבילה מקימה **שני** לקוחות משל עצמה ב-`current_date + 500`: אחד עם עמלה
-- (10% מעל 2,000) ואחד בלי. שניהם מזוהים לפי id ולעולם לא לפי שם — וזה עצמו
-- מה שמוכיח את הטענה המרכזית של 0143: הלוגיקה בודקת את `commission_pct`,
-- וההצמדה לקיסר היא נתון חד-פעמי ולא תנאי בקוד.
--
-- מה שנבדק כאן ולא נבדק בשום מקום אחר:
--
--   * שהסף **חמור**: אירוע ב-2,000 בדיוק אינו מזכה, ואירוע ב-2,000.01 כן.
--     "גבוה מ-" הוא ההבדל בין `>` ל-`>=`, והוא שקט לגמרי כשהוא שגוי.
--   * שסכום האירוע נמדד על **כל** משימותיו ולא על החלון: אירוע שנחתך בקצה
--     הטווח היה יורד מתחת לסף מסיבה טכנית, ומאבד ללקוח כסף.
--   * שלקוח בלי עמלה מקבל `commission` = null, ולא אפס — זה ההבדל בין
--     כרטיס שנעלם לכרטיס שכתוב בו 0 ₪.
--   * שהלקוח אינו יכול לכתוב את הפריסה שלו. עד 0144 `dl_write_own` לא שאלה
--     מפתח כלל, ולכן הנעילה הייתה מסך בלבד ובקשה ישירה הייתה עוברת.
--
-- הזריעה רצה בלי JWT (auth.uid() = null) ולכן הטריגרים מדלגים.
-- ===========================================================================

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000034a1', 'c34-com-mgr@vl.test'),
  ('00000000-0000-0000-0000-0000000034a2', 'c34-plain-mgr@vl.test'),
  ('00000000-0000-0000-0000-0000000034a3', 'c34-com-viewer@vl.test'),
  ('00000000-0000-0000-0000-0000000034a4', 'c34-staff@vl.test');

-- הלקוח עם העמלה, והלקוח בלי. שניהם נכתבים לפי id.
insert into customers (id, name, commission_pct, commission_min_event) values
  ('10000000-0000-0000-0000-000000000341', 'לקוח עמלה 34', 10, 2000),
  ('10000000-0000-0000-0000-000000000342', 'לקוח רגיל 34', null, 0);

insert into profiles (id, user_id, user_kind, full_name, customer_id) values
  ('20000000-0000-0000-0000-0000000034a1', '00000000-0000-0000-0000-0000000034a1',
   'customer_user', 'מנהל אצל לקוח העמלה', '10000000-0000-0000-0000-000000000341'),
  ('20000000-0000-0000-0000-0000000034a2', '00000000-0000-0000-0000-0000000034a2',
   'customer_user', 'מנהל אצל הלקוח הרגיל', '10000000-0000-0000-0000-000000000342'),
  ('20000000-0000-0000-0000-0000000034a3', '00000000-0000-0000-0000-0000000034a3',
   'customer_user', 'צופה אצל לקוח העמלה', '10000000-0000-0000-0000-000000000341');

insert into profiles (id, user_id, user_kind, full_name) values
  ('20000000-0000-0000-0000-0000000034a4', '00000000-0000-0000-0000-0000000034a4',
   'staff', 'איש צוות 34');

insert into profile_roles (profile_id, role_id)
select p.pid, r.id from (values
  ('20000000-0000-0000-0000-0000000034a1'::uuid, 'customer_manager'),
  ('20000000-0000-0000-0000-0000000034a2'::uuid, 'customer_manager'),
  ('20000000-0000-0000-0000-0000000034a3'::uuid, 'customer_viewer'),
  ('20000000-0000-0000-0000-0000000034a4'::uuid, 'dispatcher')
) as p(pid, rkey) join permission_roles r on r.key = p.rkey;

-- ‏`create_default_tasks` נולדת עם כל אירוע ותתמחר לבד; כאן המחירים נכתבים
-- ידנית כדי שהסף ייבדק על מספרים מדויקים ולא על מה שהמחשבון החזיר.
create temporary table t34(ev uuid, tk uuid, cust uuid, d date, price numeric);
insert into t34 values
  -- לקוח העמלה, בחודש של היום: מעל הסף, בדיוק על הסף, ומתחתיו
  ('30000000-0000-0000-0000-000000000341', '60000000-0000-0000-0000-000000000341',
   '10000000-0000-0000-0000-000000000341', current_date + 500, 5000),
  ('30000000-0000-0000-0000-000000000342', '60000000-0000-0000-0000-000000000342',
   '10000000-0000-0000-0000-000000000341', current_date + 500, 2000),
  ('30000000-0000-0000-0000-000000000343', '60000000-0000-0000-0000-000000000343',
   '10000000-0000-0000-0000-000000000341', current_date + 500, 2000.01),
  -- אירוע של הלקוח **האחר**, כדי שהטענה על RLS תהיה בעלת תוכן
  ('30000000-0000-0000-0000-000000000344', '60000000-0000-0000-0000-000000000344',
   '10000000-0000-0000-0000-000000000342', current_date + 500, 9000),
  -- אירוע שבוטל: אינו הכנסה ואינו ספירה (0114)
  ('30000000-0000-0000-0000-000000000345', '60000000-0000-0000-0000-000000000345',
   '10000000-0000-0000-0000-000000000341', current_date + 500, 7000);

insert into events (id, customer_id, event_number, event_date, end_client_name, status_id)
select ev, cust, 9340 + row_number() over (order by ev), d, 'אירוע 34',
       (select id from statuses where entity = 'event' and deleted_at is null
         order by sort_order limit 1)
  from t34;

insert into tasks (id, event_id, customer_id, task_type_id, task_date, hours_count, worker_count, status_id)
select tk, ev, cust, (select id from task_types where code = 'setup' limit 1), d, 4, 2,
       (select id from statuses where entity = 'task' and code = 'assigned' and deleted_at is null)
  from t34;

insert into task_pricing (task_id, price, is_manual) select tk, price, true from t34;

-- ‏0114: אירוע שבוטל יורד משניהם.
update events set status_id = (select id from statuses where entity = 'event' and code = 'cancelled')
 where id = '30000000-0000-0000-0000-000000000345';

-- **אירוע שנחתך בקצה הטווח.** שתי משימות באותו אירוע, אחת בתוך הטווח שיישאל
-- ואחת מחוצה לו. יחד 2,500 — כלומר מעל הסף רק אם סוכמות שתיהן.
insert into events (id, customer_id, event_number, event_date, end_client_name, status_id)
select '30000000-0000-0000-0000-000000000346', '10000000-0000-0000-0000-000000000341',
       9346, current_date + 500, 'אירוע חוצה טווח',
       (select id from statuses where entity = 'event' and deleted_at is null
         order by sort_order limit 1);

insert into tasks (id, event_id, customer_id, task_type_id, task_date, hours_count, worker_count, status_id)
select v.tk, '30000000-0000-0000-0000-000000000346', '10000000-0000-0000-0000-000000000341',
       (select id from task_types where code = 'setup' limit 1), v.d, 4, 2,
       (select id from statuses where entity = 'task' and code = 'assigned' and deleted_at is null)
  from (values ('60000000-0000-0000-0000-000000000346'::uuid, current_date + 500),
               ('60000000-0000-0000-0000-000000000347'::uuid, current_date + 520)) as v(tk, d);

insert into task_pricing (task_id, price, is_manual) values
  ('60000000-0000-0000-0000-000000000346', 1300, true),
  ('60000000-0000-0000-0000-000000000347', 1200, true);

set role authenticated;


-- ===== §1: מי מחזיק את המפתח ==============================================

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000034a1', false);
select t_eq('מנהל לקוח: יש finance.customer_monthly', app.has('finance.customer_monthly'), true);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000034a3', false);
select t_eq('צופה אצל הלקוח: אין finance.customer_monthly',
  app.has('finance.customer_monthly'), false);
select t_eq('ולכן הסקשן חוזר null ולא אפס',
  (dashboard_sections(array['customer.monthly'], current_date + 499, current_date + 501)
     -> 'customer.monthly'), 'null'::jsonb);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000034a4', false);
select t_eq('איש צוות: אין finance.customer_monthly', app.has('finance.customer_monthly'), false);
select t_eq('ולאיש צוות הסקשן חוזר null — אין לו "אירועים שלי"',
  (dashboard_sections(array['customer.monthly'], current_date + 499, current_date + 501)
     -> 'customer.monthly'), 'null'::jsonb);


-- ===== §2: הספירה, הסכום, והלקוח האחר =====================================

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000034a1', false);

-- ‏5000 + 2000 + 2000.01 + 2500 (החוצה טווח) = 11500.01. האירוע שבוטל אינו
-- נספר, ושל הלקוח האחר אינו נראה כלל.
select t_eq('ארבעה אירועים חיים בטווח — הביטול והלקוח האחר אינם בהם',
  ((dashboard_sections(array['customer.monthly'], current_date + 499, current_date + 501)
      -> 'customer.monthly' ->> 'events')::int), 4);

select t_eq('והסכום הוא סך התמחור של המשימות שלו',
  ((dashboard_sections(array['customer.monthly'], current_date + 499, current_date + 501)
      -> 'customer.monthly' ->> 'total')::numeric), 11500.01::numeric);


-- ===== §3: הסף חמור, והוא נמדד על האירוע ולא על החלון =====================
--
-- ‏5000 ⇒ 500 · ‏2000 בדיוק ⇒ 0 · ‏2000.01 ⇒ 200 · החוצה טווח 2500 ⇒ 250.
-- סך הכול 950. אם הסף היה `>=` היינו מקבלים 1150, ואם סכום האירוע היה נחתך
-- בטווח היינו מקבלים 700 — שתי טעויות שהמספר הזה מפריד ביניהן.

select t_eq('העמלה: 10% מכל אירוע שחצה ממש את 2,000',
  ((dashboard_sections(array['customer.monthly'], current_date + 499, current_date + 501)
      -> 'customer.monthly' ->> 'commission')::numeric), 950.00::numeric);

select t_eq('והסף עצמו חוזר ללקוח, כדי שהכרטיס יוכל להסביר את עצמו',
  ((dashboard_sections(array['customer.monthly'], current_date + 499, current_date + 501)
      -> 'customer.monthly' ->> 'commission_min')::numeric), 2000.00::numeric);
select t_eq('וגם האחוז',
  ((dashboard_sections(array['customer.monthly'], current_date + 499, current_date + 501)
      -> 'customer.monthly' ->> 'commission_pct')::numeric), 10.00::numeric);


-- ===== §4: הטבלה החודשית ==================================================
--
-- החלון שלה אינו נחתך ב-`p_from`, ולכן טווח של יום אחד עדיין מחזיר את החודש
-- שלם — זו כל הסיבה שהיא קיימת בנפרד מהכרטיסים.

select t_eq('הטבלה מחזירה שורות גם כשהטווח יום אחד',
  ((dashboard_sections(array['customer.monthly'], current_date + 500, current_date + 500)
      -> 'customer.monthly' -> 'months' -> 0 ->> 'events')::int) is not null, true);

select t_eq('ובחודש של האירועים יש ארבעה מהם',
  ((select (m ->> 'events')::int
      from jsonb_array_elements(
             dashboard_sections(array['customer.monthly'], current_date + 500, current_date + 500)
               -> 'customer.monthly' -> 'months') m
     where (m ->> 'month')::date = date_trunc('month', current_date + 500)::date)), 4);


-- ===== §5: לקוח בלי עמלה — null, ולא אפס ==================================

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000034a2', false);

select t_eq('לקוח בלי עמלה: commission הוא null, כדי שהכרטיס ייעלם',
  (dashboard_sections(array['customer.monthly'], current_date + 499, current_date + 501)
     -> 'customer.monthly' -> 'commission'), 'null'::jsonb);

select t_eq('והסכום שלו אינו נפגע מכך',
  ((dashboard_sections(array['customer.monthly'], current_date + 499, current_date + 501)
      -> 'customer.monthly' ->> 'total')::numeric), 9000.00::numeric);

select t_eq('והוא רואה את האירוע שלו בלבד',
  ((dashboard_sections(array['customer.monthly'], current_date + 499, current_date + 501)
      -> 'customer.monthly' ->> 'events')::int), 1);


-- ===== §6: הדשבורד אינו שלו לסדר (0144) ===================================

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000034a1', false);
select t_eq('מנהל לקוח: אין dashboard.customize', app.has('dashboard.customize'), false);
select t_eq('מנהל לקוח: אין dashboard.change_range', app.has('dashboard.change_range'), false);
select t_eq('מנהל לקוח: אין dashboard.build_widget', app.has('dashboard.build_widget'), false);
select t_eq('מנהל לקוח: אין dashboard.export', app.has('dashboard.export'), false);
select t_eq('אבל dashboard.view נשאר — אחרת אין לו מסך', app.has('dashboard.view'), true);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000034a3', false);
select t_eq('גם לצופה אצל הלקוח אין dashboard.customize',
  app.has('dashboard.customize'), false);

-- ולא רק הכפתור: `dl_write_own` שואלת מעכשיו את המפתח.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000034a1', false);
select t_expect_fail('ולכן כתיבת פריסה מהלקוח נדחית ב-RLS',
  $$insert into dashboard_layouts (profile_id, layout)
    values ('20000000-0000-0000-0000-0000000034a1', '{"items":[]}'::jsonb)$$);

-- ואיש הצוות ממשיך לסדר את שלו, בלי שאיבד דבר.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000034a4', false);
select t_eq('איש צוות: dashboard.customize נשאר', app.has('dashboard.customize'), true);
select t_eq('ובורר הטווח נשאר לו', app.has('dashboard.change_range'), true);
select t_expect_ok('והוא כותב את הפריסה של עצמו',
  $$insert into dashboard_layouts (profile_id, layout)
    values ('20000000-0000-0000-0000-0000000034a4', '{"items":[]}'::jsonb)$$);

reset role;
