-- 0210: סיבוס מול השעון
--
-- בקשת הבעלים:
--
--   "יש לי את קובץ הסיבוס שעובדים משכו. אני רוצה אופציה בדוח הנוכחות לייבא
--    אותו, ושליד כל דיווח נוכחות יהיה רשום אם העובד משך סיבוס, כמה ואיפה.
--    צריך לוודא שהייתה נוכחות בזמן המשיכה, או עד שעה לפני או אחרי. ותסכם לי
--    את המשיכות שבהן לא היה דיווח נוכחות לעובד."
--
-- ההכרעות:
--
--   1. **המשיכות נשמרות, לא רק מוצגות.** הקובץ החודשי מיובא פעם אחת, וכל מי
--      שפותח את הדוח אחר כך רואה אותו — גם על מחשב אחר, גם אחרי ריענון.
--      מספר העסקה של סיבוס הוא המפתח (`txn_no`), ולכן ייבוא חוזר של אותו
--      קובץ (או של קובץ שחופף לו) מעדכן ולא מכפיל.
--
--   2. **בלי תעודת זהות.** הקובץ נושא ת.ז., והיא לא נשמרת: `profiles` אינה
--      מחזיקה ת.ז. ממילא, ואין סיבה שהמסד יחזיק עותק של מידע רגיש רק כדי
--      לזהות עובד. הזיהוי הוא לפי "מס' משתמש" של סיבוס (קבוע לכרטיס), ומי
--      שאין לו — לפי השם.
--
--   3. **עובד סיבוס ↔ עובד במערכת נזכר.** `cibus_user_links` שומרת את הצימוד
--      פעם אחת. בייבוא הראשון השם מנחש (שם פרטי + משפחה, בשני הסדרים, מול
--      `profiles.full_name`; רק התאמה יחידה נחשבת). מה שלא נוחש — או נוחש לא
--      נכון — מצומד ביד (`cibus_link`), וחל מיד על כל המשיכות שלו, גם אלה
--      שכבר יובאו, וגם על הייבוא של החודש הבא.
--
--   4. **"הייתה נוכחות" נבדק בשרת, בכל קריאה.** משיכה שייכת לדיווח נוכחות
--      של אותו עובד כשהיא נופלת בין הכניסה ליציאה, או עד שעה לפני הכניסה /
--      אחרי היציאה (`app.cibus_entry_for`). דיווח שנדחה אינו נוכחות; דיווח
--      שממתין לאישור כן — הוא עוד יכול להיות מאושר, וההצלבה לא אמורה להשתנות
--      כשמנהל לוחץ "אשר". משמרת פתוחה נמדדת עד עכשיו. כשכמה דיווחים נוגעים
--      במשיכה — הקרוב ביותר (זה שהיא בתוכו קודם).
--      ההצלבה אינה עמודה שמורה: דיווח שתוקן, נמחק או נוסף אחרי הייבוא משנה
--      אותה מעצמו.
--
--   5. **משיכה שייכת לחודש של המשמרת שלה.** משיכה ב-00:25 ב-1 בחודש שנפלה
--      בתוך משמרת של ה-31 מופיעה בדוח של החודש הקודם, ליד המשמרת. משיכה בלי
--      נוכחות שייכת לחודש של התאריך שלה. כך כל משיכה נספרת בחודש אחד בדיוק.
--
--   6. **הרשאה משלה.** `attendance.cibus` — ייבוא, צימוד וצפייה. נגזרת
--      מ-`attendance.view_pay`: מי שרואה שכר של כולם רואה גם כמה נמשך בסיבוס.
--      אנשי צוות בלבד. הטבלאות סגורות (RLS בלי פוליסות, כמו 0207 §5), והכול
--      עובר דרך פונקציות definer.

-- ===== 1. הרשאה ============================================================

select app.register_permission('attendance.cibus', 'attendance', 'סיבוס',
  'ייבוא קובץ הסיבוס החודשי, צימוד עובדים והצלבת המשיכות מול דיווחי הנוכחות',
  'action', false, false, array['staff']::user_kind[], 'attendance.view_pay', 135);

-- grant_role_module מעניקה לפי המרשם ברגע הקריאה (ראו 0033)
select app.grant_role_module('ops_manager', 'attendance');
select app.grant_role_module('hr', 'attendance');

create or replace function app.can_cibus()
returns boolean language sql stable security definer set search_path = public as $$
  select app.is_admin()
      or (app.user_kind() = 'staff' and app.has('attendance.cibus'))
$$;

revoke execute on function app.can_cibus() from anon, public;
grant  execute on function app.can_cibus() to authenticated;

-- ===== 2. הטבלאות ==========================================================

create table cibus_user_links (
  -- 'u:<מס' משתמש>' כשיש, אחרת 'n:<שם מנורמל>'
  link_key    text primary key,
  profile_id  uuid not null references profiles(id) on delete cascade,
  -- true כשהצימוד נוחש מהשם בייבוא, false כשנקבע ביד
  is_auto     boolean not null default false,
  created_by  uuid references profiles(id) on delete set null,
  updated_at  timestamptz not null default now()
);

comment on table cibus_user_links is
  'עובד בסיבוס ↔ עובד במערכת (0210). נכתב ב-cibus_import (ניחוש לפי שם) וב-cibus_link (ביד).';

create trigger cibus_user_links_audit after insert or update or delete
  on cibus_user_links for each row execute function app.audit();

create table cibus_transactions (
  id             uuid primary key default gen_random_uuid(),
  -- "מס' עסקה" בקובץ. ייבוא חוזר מעדכן לפיו.
  txn_no         bigint not null unique,
  occurred_at    timestamptz not null,
  link_key       text not null,
  cibus_user_no  bigint,
  employee_name  text not null,
  merchant       text,
  deal_type      text,
  amount         numeric(10, 2) not null,
  company_part   numeric(10, 2),
  employee_part  numeric(10, 2),
  -- מועתק מ-cibus_user_links בכל ייבוא ובכל צימוד. null = טרם צומד.
  profile_id     uuid references profiles(id) on delete set null,
  imported_by    uuid references profiles(id) on delete set null,
  imported_at    timestamptz not null default now()
);

comment on table cibus_transactions is
  'משיכות סיבוס מיובאות (0210). ההצלבה מול הנוכחות מחושבת בקריאה — app.cibus_entry_for.';

create index cibus_transactions_occurred_idx on cibus_transactions (occurred_at);
create index cibus_transactions_profile_idx on cibus_transactions (profile_id, occurred_at);
create index cibus_transactions_link_idx on cibus_transactions (link_key);

alter table cibus_user_links enable row level security;
alter table cibus_transactions enable row level security;
revoke all on cibus_user_links from anon, authenticated, public;
revoke all on cibus_transactions from anon, authenticated, public;

-- ===== 3. עזרים ============================================================

-- שם להשוואה: בלי גרשיים, מקפים ורווחים כפולים.
create or replace function app.cibus_norm(p text)
returns text language sql immutable set search_path = public as $$
  select nullif(lower(btrim(regexp_replace(
           translate(coalesce(p, ''), '"''`״׳-.', '       '), '\s+', ' ', 'g'))), '')
$$;

create or replace function app.cibus_link_key(p_user_no bigint, p_name text)
returns text language sql immutable set search_path = public as $$
  select case when p_user_no is not null then 'u:' || p_user_no
              else 'n:' || coalesce(app.cibus_norm(p_name), '?') end
$$;

-- ניחוש לפי שם: רק התאמה יחידה. שני "משה כהן" במערכת — אין ניחוש.
create or replace function app.cibus_guess_profile(p_first text, p_last text, p_full text)
returns uuid language sql stable security definer set search_path = public as $$
  with names as (
    select n from unnest(array[
      app.cibus_norm(p_full),
      app.cibus_norm(coalesce(p_first, '') || ' ' || coalesce(p_last, '')),
      app.cibus_norm(coalesce(p_last, '') || ' ' || coalesce(p_first, ''))]) n
    where n is not null),
  hits as (
    select distinct p.id
      from profiles p
     where p.deleted_at is null
       and app.cibus_norm(p.full_name) in (select n from names))
  select case when (select count(*) from hits) = 1 then (select id from hits) end
$$;

-- הדיווח שהמשיכה נופלת בו, או עד שעה לפניו / אחריו. ראו §4 למעלה.
create or replace function app.cibus_entry_for(p_profile_id uuid, p_at timestamptz)
returns uuid language sql stable security definer set search_path = public as $$
  select e.id
    from attendance_entries e
   where p_profile_id is not null
     and e.profile_id = p_profile_id
     and e.deleted_at is null
     and e.status <> 'rejected'
     and p_at >= e.clock_in_at - interval '1 hour'
     and p_at <= coalesce(e.clock_out_at, greatest(now(), e.clock_in_at)) + interval '1 hour'
   order by greatest(e.clock_in_at - p_at,
                     p_at - coalesce(e.clock_out_at, greatest(now(), e.clock_in_at)),
                     interval '0'),
            e.clock_in_at
   limit 1
$$;

revoke execute on function app.cibus_norm(text) from anon, public;
revoke execute on function app.cibus_link_key(bigint, text) from anon, public;
revoke execute on function app.cibus_guess_profile(text, text, text) from anon, public;
revoke execute on function app.cibus_entry_for(uuid, timestamptz) from anon, public;
grant  execute on function app.cibus_norm(text) to authenticated;
grant  execute on function app.cibus_link_key(bigint, text) to authenticated;
grant  execute on function app.cibus_guess_profile(text, text, text) to authenticated;
grant  execute on function app.cibus_entry_for(uuid, timestamptz) to authenticated;

-- ===== 4. ייבוא ============================================================
--
-- הדפדפן קורא את קובץ ה-Excel ושולח שורות מפוענחות. השעה נשלחת כפי שהיא
-- כתובה בקובץ — שעון ישראל, בלי אזור זמן — והשרת הוא שממקם אותה, כדי
-- שאזור הזמן של המחשב שמייבא לא יזיז משיכה ממשמרת למשמרת.
--
-- כל שורה: txn_no, occurred_local ('2026-08-31T00:25'), user_no, first_name,
-- last_name, employee_name, merchant, deal_type, amount, company_part,
-- employee_part.

create or replace function cibus_import(p_rows jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_me       uuid := app.profile_id();
  r          jsonb;
  v_txn      bigint;
  v_at       timestamptz;
  v_user_no  bigint;
  v_name     text;
  v_amount   numeric;
  v_key      text;
  v_profile  uuid;
  v_inserted boolean;
  v_ins      int := 0;
  v_upd      int := 0;
begin
  if not app.can_cibus() then
    raise exception 'אין לך הרשאה לייבא סיבוס' using errcode = '42501';
  end if;
  if p_rows is null or jsonb_typeof(p_rows) <> 'array' or jsonb_array_length(p_rows) = 0 then
    raise exception 'לא נמצאו משיכות בקובץ';
  end if;
  if jsonb_array_length(p_rows) > 10000 then
    raise exception 'הקובץ גדול מדי — עד 10,000 משיכות בייבוא אחד';
  end if;

  for r in select * from jsonb_array_elements(p_rows) loop
    v_txn     := nullif(r ->> 'txn_no', '')::bigint;
    v_user_no := nullif(r ->> 'user_no', '')::bigint;
    v_name    := nullif(btrim(coalesce(r ->> 'employee_name',
                   coalesce(r ->> 'first_name', '') || ' ' || coalesce(r ->> 'last_name', ''))), '');
    v_amount  := nullif(r ->> 'amount', '')::numeric;
    if v_txn is null then
      raise exception 'משיכה בלי מספר עסקה';
    end if;
    if v_name is null then
      raise exception 'משיכה % בלי שם עובד', v_txn;
    end if;
    if v_amount is null then
      raise exception 'משיכה % בלי סכום', v_txn;
    end if;
    begin
      v_at := (r ->> 'occurred_local')::timestamp at time zone 'Asia/Jerusalem';
    exception when others then
      raise exception 'משיכה %: תאריך ושעה לא תקינים', v_txn;
    end;
    if v_at is null then
      raise exception 'משיכה %: תאריך ושעה לא תקינים', v_txn;
    end if;

    v_key := app.cibus_link_key(v_user_no, v_name);
    select profile_id into v_profile from cibus_user_links where link_key = v_key;
    if v_profile is null then
      v_profile := app.cibus_guess_profile(r ->> 'first_name', r ->> 'last_name', v_name);
      if v_profile is not null then
        insert into cibus_user_links (link_key, profile_id, is_auto, created_by)
        values (v_key, v_profile, true, v_me)
        on conflict (link_key) do nothing;
      end if;
    end if;

    insert into cibus_transactions (
      txn_no, occurred_at, link_key, cibus_user_no, employee_name, merchant, deal_type,
      amount, company_part, employee_part, profile_id, imported_by)
    values (
      v_txn, v_at, v_key, v_user_no, v_name,
      nullif(btrim(coalesce(r ->> 'merchant', '')), ''),
      nullif(btrim(coalesce(r ->> 'deal_type', '')), ''),
      round(v_amount, 2),
      round(nullif(r ->> 'company_part', '')::numeric, 2),
      round(nullif(r ->> 'employee_part', '')::numeric, 2),
      v_profile, v_me)
    on conflict (txn_no) do update set
      occurred_at   = excluded.occurred_at,
      link_key      = excluded.link_key,
      cibus_user_no = excluded.cibus_user_no,
      employee_name = excluded.employee_name,
      merchant      = excluded.merchant,
      deal_type     = excluded.deal_type,
      amount        = excluded.amount,
      company_part  = excluded.company_part,
      employee_part = excluded.employee_part,
      profile_id    = excluded.profile_id,
      imported_by   = excluded.imported_by,
      imported_at   = now()
    returning (xmax = 0) into v_inserted;

    if v_inserted then v_ins := v_ins + 1; else v_upd := v_upd + 1; end if;
  end loop;

  return jsonb_build_object(
    'inserted', v_ins,
    'updated',  v_upd,
    -- מי מהקובץ טרם צומד לעובד במערכת — המסך מציע לצמד אותם מיד
    'unlinked', coalesce((
      select jsonb_agg(jsonb_build_object('link_key', u.link_key, 'employee_name', u.employee_name)
                       order by u.employee_name)
        from (select distinct on (c.link_key) c.link_key, c.employee_name
                from cibus_transactions c
               where c.profile_id is null
                 and c.txn_no in (select (x ->> 'txn_no')::bigint from jsonb_array_elements(p_rows) x)
               order by c.link_key, c.imported_at desc) u), '[]'::jsonb));
end $$;

revoke execute on function cibus_import(jsonb) from anon, public;
grant  execute on function cibus_import(jsonb) to authenticated;

-- ===== 5. צימוד ידני =======================================================
--
-- p_profile_id null מבטל את הצימוד: המשיכות חוזרות ל"לא צומד".

create or replace function cibus_link(p_link_key text, p_profile_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not app.can_cibus() then
    raise exception 'אין לך הרשאה לצמד עובדי סיבוס' using errcode = '42501';
  end if;
  if p_link_key is null
     or (not exists (select 1 from cibus_transactions where link_key = p_link_key)
         and not exists (select 1 from cibus_user_links where link_key = p_link_key)) then
    raise exception 'עובד הסיבוס לא נמצא';
  end if;

  if p_profile_id is null then
    delete from cibus_user_links where link_key = p_link_key;
  else
    if not exists (select 1 from profiles where id = p_profile_id and deleted_at is null) then
      raise exception 'העובד לא נמצא';
    end if;
    insert into cibus_user_links (link_key, profile_id, is_auto, created_by)
    values (p_link_key, p_profile_id, false, app.profile_id())
    on conflict (link_key) do update set
      profile_id = excluded.profile_id,
      is_auto    = false,
      created_by = excluded.created_by,
      updated_at = now();
  end if;

  update cibus_transactions set profile_id = p_profile_id where link_key = p_link_key;
end $$;

revoke execute on function cibus_link(text, uuid) from anon, public;
grant  execute on function cibus_link(text, uuid) to authenticated;

-- ===== 6. הדוח =============================================================
--
-- המשיכות של החודש (ראו §5 למעלה), כל אחת עם הדיווח שהיא נופלת בו, וסיכום
-- לפי עובד: כמה נמשך בתוך משמרות וכמה בלי נוכחות. הסכומים נספרים כאן ולא
-- בדפדפן.

create or replace function cibus_report(
  p_from date,
  p_to   date,
  p_profile_ids uuid[] default null)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_rows jsonb;
begin
  if not app.can_cibus() then
    raise exception 'אין לך הרשאה לצפות בסיבוס' using errcode = '42501';
  end if;
  if p_from is null or p_to is null or p_to < p_from then
    raise exception 'טווח תאריכים לא תקין';
  end if;

  with cand as (
    -- יומיים לכל צד: משמרת של ה-31 יכולה להימשך אל תוך ה-1
    select c.*, app.cibus_entry_for(c.profile_id, c.occurred_at) as entry_id
      from cibus_transactions c
     where c.occurred_at >= (p_from - 2)::timestamp at time zone 'Asia/Jerusalem'
       and c.occurred_at <  (p_to + 3)::timestamp at time zone 'Asia/Jerusalem'
       and (p_profile_ids is null or c.profile_id = any(p_profile_ids))
  ), kept as (
    select cand.*, e.work_date as entry_date, p.full_name
      from cand
      left join attendance_entries e on e.id = cand.entry_id
      left join profiles p on p.id = cand.profile_id
     where case when cand.entry_id is not null
                then e.work_date between p_from and p_to
                else (cand.occurred_at at time zone 'Asia/Jerusalem')::date between p_from and p_to end
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'id',            k.id,
           'txn_no',        k.txn_no,
           'occurred_at',   k.occurred_at,
           'link_key',      k.link_key,
           'employee_name', k.employee_name,
           'profile_id',    k.profile_id,
           'full_name',     k.full_name,
           'merchant',      k.merchant,
           'deal_type',     k.deal_type,
           'amount',        k.amount,
           'entry_id',      k.entry_id)
         order by k.occurred_at), '[]'::jsonb)
    into v_rows
    from kept k;

  return jsonb_build_object(
    'transactions', v_rows,
    'employees', coalesce((
      select jsonb_agg(jsonb_build_object(
               'profile_id',       g.profile_id,
               'full_name',        g.full_name,
               'count',            g.cnt,
               'amount',           g.amt,
               'matched_count',    g.m_cnt,
               'matched_amount',   g.m_amt,
               'unmatched_count',  g.u_cnt,
               'unmatched_amount', g.u_amt)
             order by g.full_name)
        from (select (r ->> 'profile_id')::uuid as profile_id,
                     max(r ->> 'full_name') as full_name,
                     count(*) as cnt,
                     sum((r ->> 'amount')::numeric) as amt,
                     count(*) filter (where r ->> 'entry_id' is not null) as m_cnt,
                     coalesce(sum((r ->> 'amount')::numeric)
                                filter (where r ->> 'entry_id' is not null), 0) as m_amt,
                     count(*) filter (where r ->> 'entry_id' is null) as u_cnt,
                     coalesce(sum((r ->> 'amount')::numeric)
                                filter (where r ->> 'entry_id' is null), 0) as u_amt
                from jsonb_array_elements(v_rows) r
               where r ->> 'profile_id' is not null
               group by 1) g), '[]'::jsonb),
    -- עובדי סיבוס שטרם צומדו לעובד במערכת. אין מול מה להצליב אותם.
    'unlinked', coalesce((
      select jsonb_agg(jsonb_build_object(
               'link_key',      g.link_key,
               'employee_name', g.employee_name,
               'count',         g.cnt,
               'amount',        g.amt)
             order by g.employee_name)
        from (select r ->> 'link_key' as link_key,
                     max(r ->> 'employee_name') as employee_name,
                     count(*) as cnt,
                     sum((r ->> 'amount')::numeric) as amt
                from jsonb_array_elements(v_rows) r
               where r ->> 'profile_id' is null
               group by 1) g), '[]'::jsonb),
    'totals', (
      select jsonb_build_object(
               'count',            count(*),
               'amount',           coalesce(sum((r ->> 'amount')::numeric), 0),
               'matched_count',    count(*) filter (where r ->> 'entry_id' is not null),
               'matched_amount',   coalesce(sum((r ->> 'amount')::numeric)
                                      filter (where r ->> 'entry_id' is not null), 0),
               'unmatched_count',  count(*) filter (where r ->> 'entry_id' is null),
               'unmatched_amount', coalesce(sum((r ->> 'amount')::numeric)
                                      filter (where r ->> 'entry_id' is null), 0),
               'unlinked_count',   count(*) filter (where r ->> 'profile_id' is null),
               'unlinked_amount',  coalesce(sum((r ->> 'amount')::numeric)
                                      filter (where r ->> 'profile_id' is null), 0))
        from jsonb_array_elements(v_rows) r),
    'last_import_at', (select max(imported_at) from cibus_transactions));
end $$;

revoke execute on function cibus_report(date, date, uuid[]) from anon, public;
grant  execute on function cibus_report(date, date, uuid[]) to authenticated;
