-- 0205: האירוע אומר כמה מגיע עליו, כמה שולם וכמה נשאר
--
-- הבקשה, במילים של הבעלים: "באירועים של שיא עיצובים אני רוצה לרשום כמה כסף
-- קיבלתי מהאירוע, והאם קיבלתי את מלוא התמורה. אני נכנס לאירוע, רואה שמגיע לי
-- על הלוגיסטיקה, על ההובלה ועמלות מהריהוט הישן ומהחדש — סך הכול. לוחץ
-- 'אוסף תשלום', בוחר את כל הסכום או חלק ממנו, מזומן או אחר עם הערה, ושומר.
-- המערכת רושמת את התאריך וכמה נשאר. מחר עוד תשלום — עוד שורה." ובנוסף: מסך
-- שמראה את כל האירועים האלה בטווח תאריכים — מה שולם ומה לא, עם היסטוריה — ושני
-- כרטיסים בדשבורד: כמה שולם וכמה עוד לא, לפי חודש.
--
-- חמש הכרעות:
--
--   1. **"האירועים של שיא עיצובים" הוא דגל, לא שם.** ‏`customers.event_payments_enabled`
--      פותח את המודול ללקוח, בדיוק כמו `warehouse_schedule_enabled` (0196).
--      המיגרציה מדליקה אותו ללקוח שיש לו חיבור ViperFlow פעיל — שום מקום
--      בקוד אינו משווה לשם, ולקוח שני ידלק מכרטיס הלקוח.
--
--   2. **התשלום הוא תקבול.** טבלת `receipts` (0068) כבר היא יומן הכסף שנכנס,
--      וממנה ניזונים כרטיסי "שולם / לא שולם" של הדשבורד. טבלה שנייה הייתה
--      משאירה את שני המסכים סותרים: תשלום שנרשם על אירוע לא היה נספר ב"שולם"
--      הכללי. לכן התקבול מקבל שתי עמודות: ‏`event_id` (אופציונלי — תקבול על
--      החשבון השוטף נשאר כפי שהיה, וזו ההכרעה של 0068 §4) ו-`method`
--      (מזומן / אחר). תשלום על אירוע הוא תקבול שיודע על מה הוא.
--
--   3. **"מגיע לי" הוא החלק של וייפר.** הבעלים מנה אותו: לוגיסטיקה, הובלה,
--      ועמלות מהריהוט. כלומר: מחיר המשימות (`app.task_revenue` — הקמה, פירוק
--      ותוספות), ועוד כל שורת הכנסה של האירוע **כפול אחוז וייפר שנשמר עליה**
--      (`event_income.viper_share_pct`, ה-snapshot של 0068 §4). הובלות הן
--      100% ולכן נכנסות במלואן; ריהוט ישן/חדש נכנס כעמלה. בלי שמות קטגוריה
--      ובלי אחוזים קבועים בקוד — האחוז הוא מה שסוכם עם הלקוח.
--
--   4. **הכסף נספר בשרת.** סכום ההכנסה, העמלה והיתרה מחושבים כאן, דרך
--      `app.live_events` / `app.live_tasks` / `app.task_revenue` בלבד (0114):
--      אירוע שבוטל אינו חייב דבר, ותשלום שכבר התקבל עליו נשאר רשום ומופיע
--      כיתרת זכות. הדפדפן מציג.
--
--   5. **מפתח חדש, נגזר מהתקבולים.** ‏`finance.event_payments_view` ו-
--      `finance.event_payments_manage`, ‏implied_by ‏`finance.receipts_view` /
--      `finance.receipts_manage`: מי שמנהל תקבולים היום מנהל גם את אלה, ואפשר
--      לסגור לו את זה במפורש. ‏`applies_to = staff` — ובנוסף בדיקת user_kind
--      בתוך כל פונקציה, כי `app.has` אינו מכבד את applies_to: לקוח אינו רואה
--      את ההכנסה של וייפר, וזו בדיוק ההכנסה.

-- ===== 1. הרשאות ===========================================================

select app.register_permission('finance.event_payments_view', 'finance', 'תשלומי אירועים',
  'כמה מגיע על כל אירוע, כמה שולם ומה היתרה — בדף האירוע, במסך התשלומים ובדשבורד',
  'field', false, true, array['staff']::user_kind[], 'finance.receipts_view', 60);

select app.register_permission('finance.event_payments_manage', 'finance', 'רישום תשלומי אירועים',
  'הוספה ומחיקה של תשלום שהתקבל על אירוע',
  'action', false, true, array['staff']::user_kind[], 'finance.receipts_manage', 70);

-- ===== 2. הדגל על הלקוח ====================================================

alter table customers
  add column event_payments_enabled boolean not null default false;

comment on column customers.event_payments_enabled is
  'האם נרשמים תשלומים על האירועים של הלקוח הזה — כפתור "אוסף תשלום" ומסך התשלומים (0205).';

update customers c set event_payments_enabled = true
 where c.deleted_at is null
   and exists (select 1 from viperflow_connections v
                where v.customer_id = c.id and v.is_active and v.deleted_at is null);

-- ===== 3. התקבול יודע על איזה אירוע ובאיזה אמצעי ==========================
--
-- ‏`on delete set null`: מחיקה לצמיתות של אירוע (0137) אינה מוחקת כסף שהתקבל.
-- התקבול נשאר על הלקוח, כמו כל תקבול על החשבון.

alter table receipts
  add column event_id uuid references events(id) on delete set null,
  add column method   text check (method in ('cash', 'other'));

comment on column receipts.event_id is
  'האירוע שהתשלום התקבל עליו (0205). ריק = תקבול על החשבון השוטף (0068).';
comment on column receipts.method is
  'אמצעי התשלום: cash / other (0205). ריק בתקבולים שנרשמו לפני כן.';

-- תשלום על אירוע הוא תמיד חיובי. זיכוי ללקוח (0068: תקבול שלילי) נשאר
-- תקבול על החשבון — "שילם מינוס" על אירוע אינו תשלום שמישהו אסף.
alter table receipts
  add constraint receipts_event_payment_positive check (event_id is null or amount > 0);

create index receipts_event_live_idx on receipts (event_id)
  where event_id is not null and deleted_at is null;

-- הלקוח של התקבול הוא הלקוח של האירוע. פוליסת ה-update של 0068 עדיין מתירה
-- לערוך תקבול ישירות ממסך התקבולים, ושם בדיוק אפשר היה להעביר תשלום של אירוע
-- ללקוח אחר בלי לשים לב.
create or replace function app.receipts_event_guard()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_customer uuid;
begin
  if new.event_id is null then return new; end if;
  select customer_id into v_customer from events where id = new.event_id;
  if v_customer is null then
    raise exception 'האירוע של התשלום לא נמצא';
  end if;
  if new.customer_id is distinct from v_customer then
    raise exception 'תשלום על אירוע נרשם על הלקוח של האירוע';
  end if;
  return new;
end $$;

revoke execute on function app.receipts_event_guard() from anon, authenticated, public;

create trigger receipts_event_guard before insert or update of event_id, customer_id on receipts
  for each row execute function app.receipts_event_guard();

-- ===== 4. השער ============================================================
-- איש צוות עם המפתח, או מנהל מערכת. בדיקת user_kind מפורשת, כי `app.has`
-- אינו מכבד את applies_to (CLAUDE.md §2.8).

create or replace function app.can_view_event_payments()
returns boolean language sql stable security definer set search_path = public as $$
  select app.is_admin()
      or (app.user_kind() = 'staff' and app.has('finance.event_payments_view'))
$$;

create or replace function app.can_manage_event_payments()
returns boolean language sql stable security definer set search_path = public as $$
  select app.is_admin()
      or (app.user_kind() = 'staff' and app.has('finance.event_payments_manage'))
$$;

revoke execute on function app.can_view_event_payments() from anon, public;
revoke execute on function app.can_manage_event_payments() from anon, public;
grant  execute on function app.can_view_event_payments() to authenticated;
grant  execute on function app.can_manage_event_payments() to authenticated;

-- ===== 5. כמה מגיע, כמה שולם — שורה לאירוע =================================
--
-- נקרא רק מתוך הפונקציות שלמטה (security definer), ולכן אינו נפתח לאיש.
-- ‏`security_invoker` כמו שלושת ה-views של 0114 שהוא בנוי עליהם.
--
-- אירוע שבוטל: `app.live_tasks` כבר אינה מחזירה את המשימות שלו, וההכנסות
-- נספרות רק דרך `app.live_events` — כלומר "מגיע" הוא אפס בלי שום תנאי ביטול
-- כאן. מה ששולם עליו נשאר, ומופיע כיתרת זכות.

create or replace view app.event_payment_dues with (security_invoker = true) as
select e.id            as event_id,
       e.customer_id,
       e.event_date,
       e.end_client_name,
       e.event_number,
       not exists (select 1 from app.live_events le where le.id = e.id) as cancelled,
       coalesce(lg.total, 0)                             as logistics,
       coalesce(inc.share, 0)                            as income_share,
       coalesce(lg.total, 0) + coalesce(inc.share, 0)    as due,
       coalesce(pd.paid, 0)                              as paid,
       coalesce(lg.total, 0) + coalesce(inc.share, 0) - coalesce(pd.paid, 0) as balance,
       coalesce(pd.cnt, 0)                               as payments_count,
       pd.last_at                                        as last_paid_at
  from events e
  join customers c on c.id = e.customer_id and c.event_payments_enabled
  left join lateral (
    select sum(tr.price) as total
      from app.live_tasks t
      join app.task_revenue tr on tr.task_id = t.id
     where t.event_id = e.id) lg on true
  left join lateral (
    select sum(round(ei.amount * ei.viper_share_pct / 100, 2)) as share
      from event_income ei
      join app.live_events le on le.id = ei.event_id
     where ei.event_id = e.id) inc on true
  left join lateral (
    select sum(r.amount) as paid, count(*) as cnt, max(r.received_at) as last_at
      from receipts r
     where r.event_id = e.id and r.deleted_at is null) pd on true
 where e.deleted_at is null;

comment on view app.event_payment_dues is
  'לכל אירוע של לקוח שתשלומי אירועים פתוחים לו: כמה מגיע לוייפר (משימות + חלק '
  'וייפר מההכנסות), כמה שולם וכמה נשאר (0205). נקרא רק מתוך פונקציות definer.';

revoke all on app.event_payment_dues from anon, authenticated, public;

-- ===== 6. האירוע: הפירוט, התשלומים והיתרה ==================================
--
-- ‏`enabled = false` ללקוח שהמודול סגור לו — המסך פשוט אינו מציג את הכרטיס.

create or replace function event_payment_summary(p_event_id uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_event   events;
  v_enabled boolean;
  v_row     app.event_payment_dues;
  v_lines   jsonb;
  v_pays    jsonb;
begin
  if not app.can_view_event_payments() then
    raise exception 'אין לך הרשאה לצפות בתשלומי אירועים' using errcode = '42501';
  end if;

  select * into v_event from events where id = p_event_id and deleted_at is null;
  if v_event.id is null then raise exception 'אירוע לא נמצא'; end if;

  select event_payments_enabled into v_enabled from customers where id = v_event.customer_id;
  if not coalesce(v_enabled, false) then
    return jsonb_build_object('enabled', false);
  end if;

  select * into v_row from app.event_payment_dues where event_id = p_event_id;

  -- הפירוט: הלוגיסטיקה כשורה אחת (כל המשימות ותוספותיהן), ואחריה כל שורת
  -- הכנסה של האירוע עם החלק של וייפר ממנה — קודם מה שנכנס במלואו (הובלות),
  -- ואחריו העמלות, באותו סדר שהבעלים מנה אותן. באירוע שבוטל אין שורות.
  select coalesce(jsonb_agg(x.line order by x.sort), '[]'::jsonb) into v_lines from (
    select 0 as sort, jsonb_build_object(
             'key', 'logistics', 'label', 'לוגיסטיקה',
             'amount', round(v_row.logistics, 2), 'gross', null, 'pct', null) as line
     where v_row.logistics <> 0
    union all
    select (case when ei.viper_share_pct >= 100 then 1000 else 2000 end) + ic.sort_order,
           jsonb_build_object(
             'key', ic.id, 'label', ic.name,
             'amount', round(ei.amount * ei.viper_share_pct / 100, 2),
             'gross', ei.amount, 'pct', ei.viper_share_pct)
      from event_income ei
      join app.live_events le on le.id = ei.event_id
      join income_categories ic on ic.id = ei.category_id
     where ei.event_id = p_event_id and ei.amount <> 0) x;

  select coalesce(jsonb_agg(jsonb_build_object(
           'id', r.id, 'amount', r.amount, 'received_at', r.received_at,
           'method', r.method, 'note', r.note, 'created_at', r.created_at,
           'created_by_name', p.full_name)
           order by r.received_at desc, r.created_at desc), '[]'::jsonb)
    into v_pays
    from receipts r
    left join profiles p on p.id = r.created_by
   where r.event_id = p_event_id and r.deleted_at is null;

  return jsonb_build_object(
    'enabled',   true,
    'cancelled', v_row.cancelled,
    'lines',     v_lines,
    'due',       round(v_row.due, 2),
    'paid',      round(v_row.paid, 2),
    'balance',   round(v_row.balance, 2),
    'payments',  v_pays,
    'can_manage', app.can_manage_event_payments());
end $$;

revoke execute on function event_payment_summary(uuid) from anon, public;
grant  execute on function event_payment_summary(uuid) to authenticated;

-- ===== 7. אוסף תשלום ======================================================
--
-- התאריך: מה שנבחר, ואם לא נבחר — היום **בישראל**. ‏`current_date` של השרת
-- הוא UTC, ותשלום שנאסף ב-01:00 בלילה היה נרשם על אתמול.
--
-- סכום גבוה מהיתרה אינו נחסם: "מגיע" יכול להשתנות אחרי התשלום (מחיר שעודכן,
-- הזמנה שקטנה), ותשלום שכבר נאסף הוא עובדה. המסך מזהיר; השרת רושם.

create or replace function event_payment_add(
  p_event_id    uuid,
  p_amount      numeric,
  p_method      text,
  p_note        text default null,
  p_received_at date default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_event   events;
  v_enabled boolean;
  v_id      uuid;
begin
  if not app.can_manage_event_payments() then
    raise exception 'אין לך הרשאה לרשום תשלומים' using errcode = '42501';
  end if;

  select * into v_event from events where id = p_event_id and deleted_at is null;
  if v_event.id is null then raise exception 'אירוע לא נמצא'; end if;

  select event_payments_enabled into v_enabled from customers where id = v_event.customer_id;
  if not coalesce(v_enabled, false) then
    raise exception 'רישום תשלומים אינו פתוח ללקוח של האירוע';
  end if;

  if p_amount is null or p_amount <= 0 then
    raise exception 'סכום התשלום חייב להיות גדול מאפס';
  end if;
  if round(p_amount, 2) <> p_amount then
    raise exception 'סכום התשלום — עד שתי ספרות אחרי הנקודה';
  end if;
  if p_method is null or p_method not in ('cash', 'other') then
    raise exception 'יש לבחור אמצעי תשלום: מזומן או אחר';
  end if;

  insert into receipts (customer_id, event_id, amount, method, received_at, note, created_by)
  values (v_event.customer_id, p_event_id, p_amount, p_method,
          coalesce(p_received_at, (now() at time zone 'Asia/Jerusalem')::date),
          nullif(btrim(coalesce(p_note, '')), ''),
          app.profile_id())
  returning id into v_id;

  return v_id;
end $$;

revoke execute on function event_payment_add(uuid, numeric, text, text, date) from anon, public;
grant  execute on function event_payment_add(uuid, numeric, text, text, date) to authenticated;

-- מחיקה רכה (CLAUDE.md §2.10). רק תשלום על אירוע — תקבול על החשבון נמחק
-- ממסך התקבולים, כפי שהיה.
create or replace function event_payment_remove(p_receipt_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not app.can_manage_event_payments() then
    raise exception 'אין לך הרשאה למחוק תשלומים' using errcode = '42501';
  end if;

  update receipts set deleted_at = now()
   where id = p_receipt_id and event_id is not null and deleted_at is null;
  if not found then raise exception 'התשלום לא נמצא'; end if;
end $$;

revoke execute on function event_payment_remove(uuid) from anon, public;
grant  execute on function event_payment_remove(uuid) to authenticated;

-- ===== 8. מסך התשלומים ====================================================
--
-- כל האירועים של לקוחות שהמודול פתוח להם, בטווח תאריכי האירוע. אירוע שבוטל
-- נכנס רק אם שולם עליו משהו — אחרת אין בו מה לראות.

create or replace function event_payments_list(p_from date, p_to date)
returns table (
  event_id        uuid,
  event_date      date,
  end_client_name text,
  event_number    text,
  customer_id     uuid,
  customer_name   text,
  customer_color  text,
  cancelled       boolean,
  logistics       numeric,
  income_share    numeric,
  due             numeric,
  paid            numeric,
  balance         numeric,
  payments_count  int,
  last_paid_at    date)
language plpgsql stable security definer set search_path = public as $$
begin
  if not app.can_view_event_payments() then
    raise exception 'אין לך הרשאה לצפות בתשלומי אירועים' using errcode = '42501';
  end if;
  if p_from is null or p_to is null or p_to < p_from then
    raise exception 'טווח תאריכים לא תקין' using errcode = '22023';
  end if;
  -- אותה תקרה של הדשבורד: המסך מציג את הסיכום שלו מ-`event_payments_dashboard`,
  -- ושני טווחים מותרים שונים היו נותנים טבלה בלי סיכום.
  if p_to - p_from > 400 then
    raise exception 'טווח גדול מדי — עד שנה' using errcode = '22023';
  end if;

  return query
    select d.event_id, d.event_date, d.end_client_name, d.event_number,
           d.customer_id, c.name, c.color, d.cancelled,
           round(d.logistics, 2), round(d.income_share, 2),
           round(d.due, 2), round(d.paid, 2), round(d.balance, 2),
           d.payments_count::int, d.last_paid_at
      from app.event_payment_dues d
      join customers c on c.id = d.customer_id
     where d.event_date between p_from and p_to
       and (not d.cancelled or d.paid <> 0)
     order by d.event_date, d.end_client_name;
end $$;

revoke execute on function event_payments_list(date, date) from anon, public;
grant  execute on function event_payments_list(date, date) to authenticated;

-- ===== 9. הדשבורד =========================================================
--
-- לא סקשן ב-`dashboard_sections`: הכרטיסים שואלים בעצמם (dashboardContext.tsx
-- — "Anything a widget can fetch on its own still does"), וכך אין צורך
-- להגדיר מחדש פונקציה של 800 שורות בשביל ענף אחד.
--
-- הטווח הוא תאריך **האירוע**, לא תאריך התשלום: השאלה היא "מהאירועים של
-- אוקטובר, כמה עוד לא שולם" — גם אם התשלום יגיע בדצמבר.
--
-- ‏"לא שולם" הוא סכום היתרות החיוביות בלבד. אירוע ששולם ביתר אינו מקזז
-- אירוע אחר שלא שולם — שני אנשים שונים חייבים, או אינם חייבים, כל אחד את שלו.
--
-- ‏`months` הם שנים-עשר החודשים שמסתיימים בחודש של סוף הטווח, כמו
-- `customer.monthly` (0143), כדי שהגרף לא יתכווץ לעמודה אחת כשהטווח הוא חודש.
--
-- ‏null — למי שאינו רשאי; הכרטיס נעלם, בדיוק כמו סקשן אסור.

create or replace function event_payments_dashboard(p_from date, p_to date)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_start date;
  v_out   jsonb;
begin
  if not app.can_view_event_payments() then return null; end if;
  if p_from is null or p_to is null or p_to < p_from then
    raise exception 'טווח תאריכים לא תקין' using errcode = '22023';
  end if;
  if p_to - p_from > 400 then
    raise exception 'טווח גדול מדי לדשבורד' using errcode = '22023';
  end if;

  v_start := least(p_from, (date_trunc('month', p_to) - interval '11 months')::date);

  with d as (
    select * from app.event_payment_dues
     where event_date between v_start and p_to
       and (due <> 0 or paid <> 0)
  ), r as (
    select * from d where event_date between p_from and p_to
  )
  select jsonb_build_object(
    'due',          round(coalesce((select sum(due) from r), 0), 2),
    'paid',         round(coalesce((select sum(paid) from r), 0), 2),
    'unpaid',       round(coalesce((select sum(greatest(balance, 0)) from r), 0), 2),
    'events',       (select count(*) from r),
    'paid_events',  (select count(*) from r where due > 0 and balance <= 0),
    'open_events',  (select count(*) from r where balance > 0),
    'customers',    (select coalesce(jsonb_agg(c.name order by c.name), '[]'::jsonb)
                       from customers c
                      where c.event_payments_enabled and c.deleted_at is null),
    'months', (select coalesce(jsonb_agg(row_to_json(m) order by m.month), '[]'::jsonb) from (
        select date_trunc('month', event_date)::date      as month,
               count(*)                                   as events,
               round(sum(due), 2)                         as due,
               round(sum(paid), 2)                        as paid,
               round(sum(greatest(balance, 0)), 2)        as unpaid
          from d group by 1) m))
    into v_out;

  return v_out;
end $$;

revoke execute on function event_payments_dashboard(date, date) from anon, public;
grant  execute on function event_payments_dashboard(date, date) to authenticated;
