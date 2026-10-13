-- 0220: גם עובד של קבלן מקבל תלוש, ותלוש יכול להישאר בלי שיוך
--
-- בקשת הבעלים:
--
--   "שיהיה ניתן לשייך גם לעובדים של קבלנים שיש להם משתמש למערכת — שהם גם
--    יראו את התלוש. בנוסף שיהיה לי אפשרות לבחור 'ללא שיוך' ואז לא יופיע לי
--    שיש תלושים שלא משויכים."
--
-- ההכרעות:
--
--   1. **עובד קבלן עם משתמש = עוד מי שאפשר לשייך אליו.** `payslip_assign`
--      מקבל פרופיל `contractor_user` פעיל כמו איש צוות (0218 קיבל רק
--      `staff`). `payslips.view_own` חל עכשיו גם על `contractor_user`
--      (`applies_to`; ברירת המחדל שלו פתוחה, כמו לאיש צוות — זה התלוש שלו),
--      ו-`app.can_view_own_payslips` שואל את המפתח בלי לסנן לפי סוג. כך ה-RLS
--      על `payslips`, השער של Storage (`app.may_touch_payslip_file`) והמסך
--      "התלושים שלי" עובדים לו בלי שינוי. גם ההתראה `payslip_available`
--      נפתחת לקהל `contractor_user`. ההצעה (`app.payslip_suggest`) מכירה גם
--      אותם. הקבלן עצמו (המנהל) אינו רואה את התלושים של עובדיו — רק העובד
--      שהתלוש שויך אליו.
--
--   2. **הרשימה לשיוך — מהשרת.** `payslip_assignees()` מחזירה אנשי צוות ועובדי
--      קבלנים פעילים, עם שם הקבלן, למי שמנהל תלושים. הדפדפן לא קורא את
--      `profiles` של קבלנים ישירות (ה-RLS שלו אינו פתוח לזה, ולא צריך שיהיה).
--
--   3. **"ללא שיוך" היא החלטה.** `payslips.skipped_at` — התלוש נשאר בקובץ, אף
--      עובד אינו רואה אותו, והוא יורד מ"ממתינים לשיוך" ומהמונה של הקובץ. שיוך
--      מאוחר יותר מנקה את הסימון; `payslip_skip(id, false)` מחזיר אותו לממתינים.
--      סיכומי החודש סופרים תלושים משויכים **וגם** כאלה שסומנו "ללא שיוך": זה
--      עדיין תלוש ששולם, ועלות המעביד שלו אמיתית (למשל עובד שעזב ואין לו
--      משתמש). עמוד "לא תלוש" נשאר הסרה (`payslip_remove`) — הוא לא נספר.

-- ===== 1. עובד קבלן רואה את התלוש שלו =====================================

select app.register_permission('payslips.view_own', 'payslips', 'התלושים שלי',
  'העובד — איש צוות או עובד קבלן עם משתמש — רואה ומוריד את תלושי השכר ששויכו אליו',
  'access', true, false, array['staff', 'contractor_user']::user_kind[], null, 10);

create or replace function app.can_view_own_payslips()
returns boolean language sql stable security definer set search_path = public as $$
  -- ‏app.has כבר מסרב לסוג שאינו ב-applies_to (0214): staff ו-contractor_user
  select app.is_admin() or app.has('payslips.view_own')
$$;

revoke execute on function app.can_view_own_payslips() from anon, public;
grant  execute on function app.can_view_own_payslips() to authenticated;

select app.register_notification_type('payslip_available', 'תלוש שכר חדש',
  'תלוש שכר שויך אליי וזמין לצפייה ולהורדה',
  'תלושי שכר', array['admin', 'staff', 'contractor_user'], 'payslip', 'opt_out', 'opt_out', 'opt_in', 220);

-- מי שאפשר לשייך אליו תלוש: איש צוות או עובד קבלן, פעיל ולא מחוק.
create or replace function app.payslip_assignable(p_profile_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from profiles
                  where id = p_profile_id and deleted_at is null and is_active
                    and user_kind in ('staff', 'contractor_user'))
$$;

revoke execute on function app.payslip_assignable(uuid) from anon, public;
grant  execute on function app.payslip_assignable(uuid) to authenticated;

-- ההצעה (0218 §3) — אותו גוף, וגם עובדי קבלנים.
create or replace function app.payslip_suggest(p_link_key text, p_name text)
returns uuid language sql stable security definer set search_path = public as $$
  select coalesce(
    (select l.profile_id
       from payslip_links l
       join profiles p on p.id = l.profile_id
      where l.link_key = p_link_key
        and p.deleted_at is null
        and p.user_kind in ('staff', 'contractor_user')),
    (select case when count(*) = 1 then min(p.id::text)::uuid end
       from profiles p
      where p.deleted_at is null
        and p.user_kind in ('staff', 'contractor_user')
        and app.payslip_name_key(p_name) is not null
        and app.payslip_name_key(p.full_name) = app.payslip_name_key(p_name)))
$$;

revoke execute on function app.payslip_suggest(text, text) from anon, public;
grant  execute on function app.payslip_suggest(text, text) to authenticated;

-- ===== 2. הרשימה לשיוך =====================================================

create or replace function payslip_assignees()
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not app.can_manage_payslips() then
    raise exception 'אין לך הרשאה לנהל תלושי שכר' using errcode = '42501';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'id',              p.id,
             'full_name',       p.full_name,
             'user_kind',       p.user_kind,
             'contractor_name', c.name)
           order by (p.user_kind <> 'staff'), c.name nulls first, p.full_name)
      from profiles p
      left join contractors c on c.id = p.contractor_id and p.user_kind = 'contractor_user'
     where p.deleted_at is null and p.is_active
       and p.user_kind in ('staff', 'contractor_user')), '[]'::jsonb);
end $$;

revoke execute on function payslip_assignees() from anon, public;
grant  execute on function payslip_assignees() to authenticated;

-- ===== 3. "ללא שיוך" =======================================================

alter table payslips
  add column if not exists skipped_at timestamptz,
  add column if not exists skipped_by uuid references profiles(id) on delete set null;

comment on column payslips.skipped_at is
  'סומן "ללא שיוך" (0220): אינו ממתין לשיוך, אף עובד אינו רואה אותו, ונספר בסיכומי החודש.';

create or replace function payslip_skip(p_payslip_id uuid, p_skip boolean default true)
returns void language plpgsql security definer set search_path = public as $$
declare v_slip payslips;
begin
  if not app.can_manage_payslips() then
    raise exception 'אין לך הרשאה לנהל תלושי שכר' using errcode = '42501';
  end if;
  select * into v_slip from payslips where id = p_payslip_id and deleted_at is null for update;
  if not found then
    raise exception 'התלוש לא נמצא';
  end if;
  if coalesce(p_skip, true) and v_slip.profile_id is not null then
    raise exception 'התלוש משויך לעובד — יש לבטל את השיוך קודם';
  end if;
  update payslips set
    skipped_at = case when coalesce(p_skip, true) then now() end,
    skipped_by = case when coalesce(p_skip, true) then app.profile_id() end
  where id = p_payslip_id;
end $$;

revoke execute on function payslip_skip(uuid, boolean) from anon, public;
grant  execute on function payslip_skip(uuid, boolean) to authenticated;

-- payslip_assign (0218 §8) — אותו גוף; עובד קבלן מתקבל, ושיוך מנקה "ללא שיוך".
create or replace function payslip_assign(p_payslip_id uuid, p_profile_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_slip payslips;
  v_me   uuid := app.profile_id();
begin
  if not app.can_manage_payslips() then
    raise exception 'אין לך הרשאה לשייך תלושי שכר' using errcode = '42501';
  end if;
  select * into v_slip from payslips where id = p_payslip_id and deleted_at is null for update;
  if not found then
    raise exception 'התלוש לא נמצא';
  end if;
  if p_profile_id is not null and not app.payslip_assignable(p_profile_id) then
    raise exception 'העובד לא נמצא';
  end if;
  if v_slip.profile_id is not distinct from p_profile_id then
    return;
  end if;

  update payslips set
    profile_id  = p_profile_id,
    assigned_by = case when p_profile_id is null then null else v_me end,
    assigned_at = case when p_profile_id is null then null else now() end,
    skipped_at  = case when p_profile_id is null then skipped_at end,
    skipped_by  = case when p_profile_id is null then skipped_by end
  where id = p_payslip_id;

  if p_profile_id is not null then
    if v_slip.link_key is not null then
      insert into payslip_links (link_key, profile_id, updated_by)
      values (v_slip.link_key, p_profile_id, v_me)
      on conflict (link_key) do update set
        profile_id = excluded.profile_id,
        updated_by = excluded.updated_by,
        updated_at = now();
    end if;
    perform app.notify_payslip_available(p_payslip_id);
  end if;
end $$;

revoke execute on function payslip_assign(uuid, uuid) from anon, public;
grant  execute on function payslip_assign(uuid, uuid) to authenticated;

-- ===== 4. המסך של המנהל ====================================================

-- payslips_board (0218 §10) — אותו גוף; "ממתינים לשיוך" בלי מה שסומן "ללא
-- שיוך", השורה אומרת אם סומן ומי העובד (צוות או קבלן), והסיכומים סופרים גם
-- תלושים שסומנו "ללא שיוך".
create or replace function payslips_board(
  p_batch_id   uuid default null,
  p_period     date default null,
  p_unassigned boolean default false)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_manage boolean := app.can_manage_payslips();
  v_cost   boolean := app.can_view_payslip_costs();
  v_rows   jsonb;
begin
  if not (v_manage or v_cost) then
    raise exception 'אין לך הרשאה לצפות בתלושי השכר' using errcode = '42501';
  end if;

  with s as (
    select s.*, b.file_name, b.page_count, b.created_at as uploaded_at
      from payslips s
      join payslip_batches b on b.id = s.batch_id and b.deleted_at is null
     where s.deleted_at is null
       and (p_batch_id is null or s.batch_id = p_batch_id)
       and (p_period is null or s.period = date_trunc('month', p_period)::date)
       and (not p_unassigned or (s.profile_id is null and s.skipped_at is null))
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'id',                   s.id,
           'batch_id',             s.batch_id,
           'file_name',            s.file_name,
           'page_count',           s.page_count,
           'page_from',            s.page_from,
           'page_to',              s.page_to,
           'period',               s.period,
           'profile_id',           s.profile_id,
           'full_name',            p.full_name,
           'contractor_name',      pc.name,
           'assigned_at',          s.assigned_at,
           'skipped',              s.skipped_at is not null,
           'detected_kind',        s.detected_kind,
           'detected_name',        s.detected_name,
           'detected_employee_no', s.detected_employee_no,
           'detected_period',      s.detected_period,
           'suggested_profile_id', sg.id,
           'suggested_name',       sg.full_name,
           'has_previous',         exists (select 1 from payslips x
                                            where x.batch_id = s.batch_id and x.deleted_at is null
                                              and x.page_to = s.page_from - 1),
           -- עוד תלושים לאותו עובד ולאותו חודש — אולי כפול, אולי תלוש מתקן
           'same_month_count',     case when s.profile_id is null then 0 else
                                     (select count(*) from payslips x
                                       join payslip_batches xb on xb.id = x.batch_id and xb.deleted_at is null
                                      where x.profile_id = s.profile_id and x.period = s.period
                                        and x.deleted_at is null and x.id <> s.id) end,
           'amounts',              case when v_cost and a.payslip_id is not null
                                        then to_jsonb(a) - 'payslip_id' - 'updated_by' end)
         order by s.period desc, s.uploaded_at desc, s.page_from), '[]'::jsonb)
    into v_rows
    from s
    left join profiles p on p.id = s.profile_id
    left join contractors pc on pc.id = p.contractor_id and p.user_kind = 'contractor_user'
    left join payslip_amounts a on a.payslip_id = s.id
    left join lateral (
      select pp.id, pp.full_name
        from profiles pp
       where s.profile_id is null
         and s.skipped_at is null
         and s.detected_kind is distinct from 'other'
         and pp.id = app.payslip_suggest(s.link_key, s.detected_name)) sg on true;

  return jsonb_build_object(
    'can_manage',    v_manage,
    'can_view_cost', v_cost,
    'slips',         v_rows,
    'totals', case when v_cost then (
      select jsonb_build_object(
               'count',                  count(*),
               'with_amounts',           count(*) filter (where (r -> 'amounts' ->> 'gross_pay') is not null),
               'gross_pay',              coalesce(sum((r -> 'amounts' ->> 'gross_pay')::numeric), 0),
               'net_pay',                coalesce(sum((r -> 'amounts' ->> 'net_pay')::numeric), 0),
               'employer_contributions', coalesce(sum((r -> 'amounts' ->> 'employer_contributions')::numeric), 0),
               'employer_cost',          coalesce(sum((r -> 'amounts' ->> 'employer_cost')::numeric), 0))
        from jsonb_array_elements(v_rows) r
       where r ->> 'profile_id' is not null or (r ->> 'skipped')::boolean) end);
end $$;

revoke execute on function payslips_board(uuid, date, boolean) from anon, public;
grant  execute on function payslips_board(uuid, date, boolean) to authenticated;

-- payslip_batches_overview (0218 §10) — אותו גוף, ועוד כמה סומנו "ללא שיוך".
create or replace function payslip_batches_overview(p_limit int default 24)
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not (app.can_manage_payslips() or app.can_view_payslip_costs()) then
    raise exception 'אין לך הרשאה לצפות בתלושי השכר' using errcode = '42501';
  end if;

  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'id',          b.id,
             'file_name',   b.file_name,
             'page_count',  b.page_count,
             'period',      b.period,
             'created_at',  b.created_at,
             'read_at',     b.read_at,
             'uploaded_by', u.full_name,
             'slips',       (select count(*) from payslips s
                              where s.batch_id = b.id and s.deleted_at is null),
             'assigned',    (select count(*) from payslips s
                              where s.batch_id = b.id and s.deleted_at is null and s.profile_id is not null),
             'skipped',     (select count(*) from payslips s
                              where s.batch_id = b.id and s.deleted_at is null
                                and s.profile_id is null and s.skipped_at is not null),
             'read_pages',  (select count(*) from payslip_page_readings r where r.batch_id = b.id))
           order by b.created_at desc)
      from (select * from payslip_batches
             where deleted_at is null
             order by created_at desc
             limit greatest(1, least(coalesce(p_limit, 24), 200))) b
      left join profiles u on u.id = b.uploaded_by), '[]'::jsonb);
end $$;

revoke execute on function payslip_batches_overview(int) from anon, public;
grant  execute on function payslip_batches_overview(int) to authenticated;
