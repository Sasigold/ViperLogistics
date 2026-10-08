-- 0211: סיבוס — רק עובדים, ומי שלא זוהה אינו "בלי נוכחות"
--
-- שני תיקונים ל-0210, מסקירת הקוד של הבקשה:
--
--   1. **מי שטרם זוהה אינו חריגה.** משיכה של עובד סיבוס שעוד לא צומד לעובד
--      במערכת נספרה ב-`totals.unmatched_*` של `cibus_report` — "בלי נוכחות" —
--      אף שאין מול מה לבדוק אותה. בייבוא ראשון, כשחלק מהשמות טרם צומדו, זה
--      ניפח את החריגות ולא הסתכם עם הפירוט לפי עובד (שמסנן `profile_id`).
--      מעכשיו "בלי נוכחות" הוא רק של מי שזוהה; מי שלא זוהה נספר לבד
--      (`unlinked_*`, ללא שינוי).
--
--   2. **הניחוש והצימוד — אנשי צוות בלבד.** `app.cibus_guess_profile` חיפש בכל
--      `profiles`, ושם יחיד שתאם משתמש לקוח או קבלן היה מצומד אליו אוטומטית.
--      סיבוס הוא כרטיס של עובדי החברה, ומסך הצימוד מציע רק אנשי צוות — ולכן
--      גם `cibus_link` דוחה פרופיל שאינו `staff`.
--
-- שלוש הפונקציות מוגדרות מחדש בשלמותן (CLAUDE.md §2.15).

-- ===== 1. ניחוש: אנשי צוות בלבד ==========================================

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
       and p.user_kind = 'staff'
       and app.cibus_norm(p.full_name) in (select n from names))
  select case when (select count(*) from hits) = 1 then (select id from hits) end
$$;

revoke execute on function app.cibus_guess_profile(text, text, text) from anon, public;
grant  execute on function app.cibus_guess_profile(text, text, text) to authenticated;

-- ===== 2. צימוד ידני: אנשי צוות בלבד =====================================

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
    if not exists (select 1 from profiles
                    where id = p_profile_id and deleted_at is null and user_kind = 'staff') then
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

-- ===== 3. הדוח: "בלי נוכחות" רק למי שזוהה ================================

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
               -- ‏0211: מי שטרם זוהה לא נבדק מול נוכחות, ולכן אינו "בלי נוכחות"
               'unmatched_count',  count(*) filter (where r ->> 'entry_id' is null
                                                      and r ->> 'profile_id' is not null),
               'unmatched_amount', coalesce(sum((r ->> 'amount')::numeric)
                                      filter (where r ->> 'entry_id' is null
                                                and r ->> 'profile_id' is not null), 0),
               'unlinked_count',   count(*) filter (where r ->> 'profile_id' is null),
               'unlinked_amount',  coalesce(sum((r ->> 'amount')::numeric)
                                      filter (where r ->> 'profile_id' is null), 0))
        from jsonb_array_elements(v_rows) r),
    'last_import_at', (select max(imported_at) from cibus_transactions));
end $$;

revoke execute on function cibus_report(date, date, uuid[]) from anon, public;
grant  execute on function cibus_report(date, date, uuid[]) to authenticated;
