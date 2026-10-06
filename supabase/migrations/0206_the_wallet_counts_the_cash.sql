-- 0206: חיוב ידני על אירוע, וארנק המזומנים
--
-- שתי בקשות של הבעלים, על גבי כרטיס התשלומים של 0205:
--
--   "אני רוצה להוסיף שם עוד דברים לחיוב — למשל עלות ייצור, אלף שקל — ואז
--    רשום שאני צריך לקבל על האירוע עוד אלף שקל."
--
--   "ארנק מזומנים: כל תשלום שעדכנתי שהוא שולם במזומן נכנס לארנק. אני נכנס
--    לארנק ורואה כמה כסף יש לי שם, ויכול להכניס הוצאות ידנית — קניתי אוטו,
--    עשרת אלפים — והוא מראה לי את יתרת הארנק."
--
-- ההכרעות:
--
--   1. **חיוב הוא שורה משלו, לא תוספת למחיר משימה.** ‏`task_price_addons` הם
--      של המשימה, ונספרים גם בתמחור, ברווחיות ובמה שהלקוח רואה. "עלות ייצור"
--      שהבעלים גובה על האירוע אינה מחיר של הקמה או של פירוק — היא סכום נוסף
--      שמגיע על האירוע. לכן `event_charges`, והיא נכנסת ל"מגיע" של 0205
--      בלבד (`app.event_payment_dues`), ומשם ממילא למסך התשלומים ולדשבורד.
--      לא לרווחיות ולא לדוחות — שם הכנסה היא `event_income` (0068).
--
--   2. **אירוע שבוטל אינו חייב דבר — גם לא חיוב ידני.** אותו כלל של 0205 §4:
--      החיוב נספר דרך `app.live_events`. מי שרוצה לגבות דמי ביטול מחזיר את
--      האירוע או רושם תקבול על החשבון.
--
--   3. **הארנק אינו טבלה של יתרה, הוא סכום.** כל תקבול שאמצעי התשלום שלו
--      `cash` (0205 §3) הוא כסף שנכנס לארנק — מכל לקוח, גם על אירוע שבוטל
--      אחרי שהכסף נאסף: הכסף ביד. תקבול שנמחק (מחיקה רכה) יוצא מהארנק.
--      מה שהבעלים מוסיף ביד נשמר ב-`cash_wallet_entries`: הוצאה (יורדת)
--      או הכנסה ידנית (נכנסת — יתרת פתיחה, מזומן שהגיע שלא מאירוע). היתרה
--      נספרת בכל קריאה; אין מספר שמור שיכול לסטות מהשורות.
--
--   4. **הארנק פרטי.** מפתחות חדשים `finance.cash_wallet_view` / `_manage`,
--      בלי implied_by: רכז שאוסף תשלומים אינו רואה בזה את הוצאות הבעלים.
--      מנהל מערכת רואה; לכל אחר — הרשאה מפורשת. אנשי צוות בלבד, ובדיקת
--      user_kind בתוך הפונקציות (CLAUDE.md §2.8).
--
--   5. **שתי הטבלאות נכתבות ונקראות רק דרך פונקציות definer.** RLS דלוק
--      בלי פוליסות, וההרשאות על הטבלאות נשללות — כמו `app.event_payment_dues`.

-- ===== 1. הרשאות ===========================================================

select app.register_permission('finance.cash_wallet_view', 'finance', 'ארנק מזומנים',
  'יתרת המזומן: כל תשלום שהתקבל במזומן, פחות ההוצאות שנרשמו בארנק',
  'field', false, true, array['staff']::user_kind[], null, 80);

select app.register_permission('finance.cash_wallet_manage', 'finance', 'ניהול ארנק מזומנים',
  'הוספה ומחיקה של הוצאה או הכנסה ידנית בארנק המזומנים',
  'action', false, true, array['staff']::user_kind[], null, 90);

create or replace function app.can_view_cash_wallet()
returns boolean language sql stable security definer set search_path = public as $$
  select app.is_admin()
      or (app.user_kind() = 'staff' and app.has('finance.cash_wallet_view'))
$$;

create or replace function app.can_manage_cash_wallet()
returns boolean language sql stable security definer set search_path = public as $$
  select app.is_admin()
      or (app.user_kind() = 'staff' and app.has('finance.cash_wallet_manage'))
$$;

revoke execute on function app.can_view_cash_wallet() from anon, public;
revoke execute on function app.can_manage_cash_wallet() from anon, public;
grant  execute on function app.can_view_cash_wallet() to authenticated;
grant  execute on function app.can_manage_cash_wallet() to authenticated;

-- ===== 2. חיוב ידני על אירוע ===============================================

create table event_charges (
  id          uuid primary key default gen_random_uuid(),
  event_id    uuid not null references events(id) on delete cascade,
  label       text not null check (btrim(label) <> ''),
  amount      numeric(12, 2) not null check (amount > 0),
  note        text,
  created_by  uuid references profiles(id) on delete set null,
  created_at  timestamptz not null default now(),
  deleted_at  timestamptz
);

comment on table event_charges is
  'חיוב ידני על אירוע ("עלות ייצור 1,000") — נוסף ל"מגיע" של תשלומי האירוע (0206). '
  'נכתב ונקרא רק דרך event_charge_add/remove ו-event_payment_summary.';

create index event_charges_event_live_idx on event_charges (event_id) where deleted_at is null;

alter table event_charges enable row level security;
revoke all on event_charges from anon, authenticated, public;

-- ===== 3. "מגיע" כולל את החיובים ===========================================
--
-- ההגדרה של 0205 כמעט כמו שהיא. `charges` נוסף בסוף (create or replace view
-- מוסיף עמודות רק בסוף), ונכנס ל-`due` ול-`balance`.

create or replace view app.event_payment_dues with (security_invoker = true) as
select e.id            as event_id,
       e.customer_id,
       e.event_date,
       e.end_client_name,
       e.event_number,
       not exists (select 1 from app.live_events le where le.id = e.id) as cancelled,
       coalesce(lg.total, 0)                             as logistics,
       coalesce(inc.share, 0)                            as income_share,
       coalesce(lg.total, 0) + coalesce(inc.share, 0) + coalesce(ch.total, 0) as due,
       coalesce(pd.paid, 0)                              as paid,
       coalesce(lg.total, 0) + coalesce(inc.share, 0) + coalesce(ch.total, 0)
         - coalesce(pd.paid, 0)                          as balance,
       coalesce(pd.cnt, 0)                               as payments_count,
       pd.last_at                                        as last_paid_at,
       coalesce(ch.total, 0)                             as charges
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
    select sum(ec.amount) as total
      from event_charges ec
      join app.live_events le on le.id = ec.event_id
     where ec.event_id = e.id and ec.deleted_at is null) ch on true
  left join lateral (
    select sum(r.amount) as paid, count(*) as cnt, max(r.received_at) as last_at
      from receipts r
     where r.event_id = e.id and r.deleted_at is null) pd on true
 where e.deleted_at is null;

comment on view app.event_payment_dues is
  'לכל אירוע של לקוח שתשלומי אירועים פתוחים לו: כמה מגיע לוייפר (משימות + חלק '
  'וייפר מההכנסות + חיובים ידניים), כמה שולם וכמה נשאר (0205, 0206). '
  'נקרא רק מתוך פונקציות definer.';

revoke all on app.event_payment_dues from anon, authenticated, public;

-- ===== 4. הפירוט של האירוע כולל את החיובים =================================
--
-- ההגדרה של 0205, ועוד: שורת חיוב לכל חיוב ידני, אחרי העמלות, עם `charge_id`
-- (המסך מוחק לפיו) ו-`note`.

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

  select coalesce(jsonb_agg(x.line order by x.sort, x.at), '[]'::jsonb) into v_lines from (
    select 0 as sort, null::timestamptz as at, jsonb_build_object(
             'key', 'logistics', 'label', 'לוגיסטיקה',
             'amount', round(v_row.logistics, 2), 'gross', null, 'pct', null) as line
     where v_row.logistics <> 0
    union all
    select (case when ei.viper_share_pct >= 100 then 1000 else 2000 end) + ic.sort_order, null,
           jsonb_build_object(
             'key', ic.id, 'label', ic.name,
             'amount', round(ei.amount * ei.viper_share_pct / 100, 2),
             'gross', ei.amount, 'pct', ei.viper_share_pct)
      from event_income ei
      join app.live_events le on le.id = ei.event_id
      join income_categories ic on ic.id = ei.category_id
     where ei.event_id = p_event_id and ei.amount <> 0
    union all
    select 3000, ec.created_at,
           jsonb_build_object(
             'key', ec.id, 'label', ec.label, 'amount', ec.amount,
             'gross', null, 'pct', null, 'charge_id', ec.id, 'note', ec.note)
      from event_charges ec
      join app.live_events le on le.id = ec.event_id
     where ec.event_id = p_event_id and ec.deleted_at is null) x;

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

-- ===== 5. הוספה ומחיקה של חיוב =============================================
--
-- אותו מפתח של רישום תשלום: מי שאוסף כסף על האירוע הוא גם מי שאומר כמה מגיע.

create or replace function event_charge_add(
  p_event_id uuid,
  p_label    text,
  p_amount   numeric,
  p_note     text default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_event   events;
  v_enabled boolean;
  v_id      uuid;
begin
  if not app.can_manage_event_payments() then
    raise exception 'אין לך הרשאה להוסיף חיובים' using errcode = '42501';
  end if;

  select * into v_event from events where id = p_event_id and deleted_at is null;
  if v_event.id is null then raise exception 'אירוע לא נמצא'; end if;

  select event_payments_enabled into v_enabled from customers where id = v_event.customer_id;
  if not coalesce(v_enabled, false) then
    raise exception 'תשלומי אירועים אינם פתוחים ללקוח של האירוע';
  end if;
  if not exists (select 1 from app.live_events le where le.id = p_event_id) then
    raise exception 'האירוע בוטל — אין עליו חיובים';
  end if;

  if nullif(btrim(coalesce(p_label, '')), '') is null then
    raise exception 'יש לכתוב על מה החיוב';
  end if;
  if p_amount is null or p_amount <= 0 then
    raise exception 'סכום החיוב חייב להיות גדול מאפס';
  end if;
  if round(p_amount, 2) <> p_amount then
    raise exception 'סכום החיוב — עד שתי ספרות אחרי הנקודה';
  end if;

  insert into event_charges (event_id, label, amount, note, created_by)
  values (p_event_id, btrim(p_label), p_amount,
          nullif(btrim(coalesce(p_note, '')), ''), app.profile_id())
  returning id into v_id;

  return v_id;
end $$;

revoke execute on function event_charge_add(uuid, text, numeric, text) from anon, public;
grant  execute on function event_charge_add(uuid, text, numeric, text) to authenticated;

create or replace function event_charge_remove(p_charge_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not app.can_manage_event_payments() then
    raise exception 'אין לך הרשאה למחוק חיובים' using errcode = '42501';
  end if;

  update event_charges set deleted_at = now()
   where id = p_charge_id and deleted_at is null;
  if not found then raise exception 'החיוב לא נמצא'; end if;
end $$;

revoke execute on function event_charge_remove(uuid) from anon, public;
grant  execute on function event_charge_remove(uuid) to authenticated;

-- ===== 6. ארנק המזומנים — השורות הידניות ===================================

create table cash_wallet_entries (
  id          uuid primary key default gen_random_uuid(),
  kind        text not null check (kind in ('expense', 'income')),
  entry_date  date not null,
  amount      numeric(12, 2) not null check (amount > 0),
  label       text not null check (btrim(label) <> ''),
  note        text,
  created_by  uuid references profiles(id) on delete set null,
  created_at  timestamptz not null default now(),
  deleted_at  timestamptz
);

comment on table cash_wallet_entries is
  'הוצאה או הכנסה ידנית בארנק המזומנים (0206). הסכום תמיד חיובי; הכיוון ב-kind. '
  'נכתב ונקרא רק דרך cash_wallet / cash_wallet_entry_add / cash_wallet_entry_remove.';

create index cash_wallet_entries_live_idx on cash_wallet_entries (entry_date) where deleted_at is null;

alter table cash_wallet_entries enable row level security;
revoke all on cash_wallet_entries from anon, authenticated, public;

-- כל תנועה בארנק, בסימן שלה: מזומן שהתקבל (+), הכנסה ידנית (+), הוצאה (−).
create or replace view app.cash_wallet_moves with (security_invoker = true) as
select r.id, 'payment'::text as source, r.received_at as move_date, r.amount as amount,
       r.created_at, r.created_by, r.note, r.event_id, r.customer_id, null::text as label
  from receipts r
 where r.method = 'cash' and r.deleted_at is null
union all
select w.id, w.kind, w.entry_date,
       case w.kind when 'expense' then -w.amount else w.amount end,
       w.created_at, w.created_by, w.note, null, null, w.label
  from cash_wallet_entries w
 where w.deleted_at is null;

comment on view app.cash_wallet_moves is
  'כל תנועות ארנק המזומנים בסימן שלהן (0206). נקרא רק מתוך פונקציות definer.';

revoke all on app.cash_wallet_moves from anon, authenticated, public;

-- ===== 7. הארנק: יתרה, וסיכום ותנועות בטווח ================================
--
-- ‏`balance` — יתרת הארנק היום (כל התנועות, בלי קשר לטווח). ‏`opening` —
-- היתרה לפני תחילת הטווח, ו-`closing` — בסופו; כל תנועה בטווח נושאת את
-- היתרה אחריה (`running`), כמו בדף בנק. הסדר: לפי תאריך, ובתוך היום לפי
-- זמן הרישום.

create or replace function cash_wallet(p_from date, p_to date)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_out jsonb;
begin
  if not app.can_view_cash_wallet() then
    raise exception 'אין לך הרשאה לצפות בארנק המזומנים' using errcode = '42501';
  end if;
  if p_from is null or p_to is null or p_to < p_from then
    raise exception 'טווח תאריכים לא תקין' using errcode = '22023';
  end if;

  with m as (
    select * from app.cash_wallet_moves
  ), before as (
    select coalesce(sum(amount), 0) as v from m where move_date < p_from
  ), r as (
    select m.*,
           (select v from before)
             + sum(m.amount) over (order by m.move_date, m.created_at, m.id) as running
      from m where m.move_date between p_from and p_to
  )
  select jsonb_build_object(
    'balance',   round((select coalesce(sum(amount), 0) from m), 2),
    'opening',   round((select v from before), 2),
    'cash_in',   round(coalesce((select sum(amount) from r where source = 'payment'), 0), 2),
    'income',    round(coalesce((select sum(amount) from r where source = 'income'), 0), 2),
    'expenses',  round(coalesce((select -sum(amount) from r where source = 'expense'), 0), 2),
    'closing',   round((select v from before) + coalesce((select sum(amount) from r), 0), 2),
    'can_manage', app.can_manage_cash_wallet(),
    'entries', (select coalesce(jsonb_agg(jsonb_build_object(
        'id',              r.id,
        'source',          r.source,
        'date',            r.move_date,
        'amount',          round(r.amount, 2),
        'running',         round(r.running, 2),
        'label',           r.label,
        'note',            r.note,
        'event_id',        r.event_id,
        'event_name',      e.end_client_name,
        'event_number',    e.event_number,
        'customer_name',   c.name,
        'created_by_name', p.full_name,
        'created_at',      r.created_at)
        order by r.move_date desc, r.created_at desc, r.id desc), '[]'::jsonb)
      from r
      left join events e    on e.id = r.event_id
      left join customers c on c.id = r.customer_id
      left join profiles p  on p.id = r.created_by))
    into v_out;

  return v_out;
end $$;

revoke execute on function cash_wallet(date, date) from anon, public;
grant  execute on function cash_wallet(date, date) to authenticated;

-- ===== 8. הוצאה / הכנסה ידנית ==============================================
--
-- התאריך: מה שנבחר, ואם לא — היום בישראל (0205 §7).

create or replace function cash_wallet_entry_add(
  p_kind       text,
  p_amount     numeric,
  p_label      text,
  p_note       text default null,
  p_entry_date date default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_id uuid;
begin
  if not app.can_manage_cash_wallet() then
    raise exception 'אין לך הרשאה לעדכן את ארנק המזומנים' using errcode = '42501';
  end if;
  if p_kind is null or p_kind not in ('expense', 'income') then
    raise exception 'יש לבחור הוצאה או הכנסה';
  end if;
  if nullif(btrim(coalesce(p_label, '')), '') is null then
    raise exception 'יש לכתוב על מה';
  end if;
  if p_amount is null or p_amount <= 0 then
    raise exception 'הסכום חייב להיות גדול מאפס';
  end if;
  if round(p_amount, 2) <> p_amount then
    raise exception 'הסכום — עד שתי ספרות אחרי הנקודה';
  end if;

  insert into cash_wallet_entries (kind, entry_date, amount, label, note, created_by)
  values (p_kind,
          coalesce(p_entry_date, (now() at time zone 'Asia/Jerusalem')::date),
          p_amount, btrim(p_label),
          nullif(btrim(coalesce(p_note, '')), ''),
          app.profile_id())
  returning id into v_id;

  return v_id;
end $$;

revoke execute on function cash_wallet_entry_add(text, numeric, text, text, date) from anon, public;
grant  execute on function cash_wallet_entry_add(text, numeric, text, text, date) to authenticated;

-- מחיקה רכה של שורה ידנית בלבד. מזומן שהתקבל על אירוע יוצא מהארנק כשהתשלום
-- נמחק בכרטיס האירוע — שם הוא נרשם, ושם הוא נמחק.
create or replace function cash_wallet_entry_remove(p_entry_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not app.can_manage_cash_wallet() then
    raise exception 'אין לך הרשאה לעדכן את ארנק המזומנים' using errcode = '42501';
  end if;

  update cash_wallet_entries set deleted_at = now()
   where id = p_entry_id and deleted_at is null;
  if not found then raise exception 'השורה לא נמצאה'; end if;
end $$;

revoke execute on function cash_wallet_entry_remove(uuid) from anon, public;
grant  execute on function cash_wallet_entry_remove(uuid) to authenticated;
