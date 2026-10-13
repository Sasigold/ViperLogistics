-- 0223: למדרגות יש תקופה
--
-- בקשת הבעלים: "כשאני מגדיר מדרגות לביטוח לאומי הוא מחיל רטרואקטיבי. אני רוצה
-- שתהיה לי אפשרות להגדיר תאריך תחולה ותאריך תפוגה."
--
-- ההכרעות:
--
--   1. **סט מדרגות לתקופה.** `payslip_ni_bracket_sets`: מדרגות + חודש תחולה
--      (`valid_from`) + חודש תפוגה (`valid_to`, כולל; ריק — בלי תפוגה). התקופות
--      הן חודשים, כמו `payslips.period`, ואינן חופפות. תלוש מחושב לפי הסט שחודש
--      התלוש בתוכו (`app.payslip_ni_brackets_for`); חודש שאין לו סט — אין ביטוח
--      לאומי מעסיק, והמסך אומר זאת. כך שינוי המדרגות של 2027 אינו נוגע בתלושי
--      2026.
--
--   2. **החישוב עדיין בטריגר (0219 §3), עכשיו לפי חודש התלוש.** שמירה או הסרה
--      של סט מחשבת מחדש את כל התלושים — כל אחד לפי הסט של החודש שלו, ולכן רק
--      תלושים בתקופה שהשתנתה זזים בפועל. גם שינוי חודש של תלוש
--      (`payslip_set_period`) מחשב אותו מחדש.
--
--   3. **כתיבה דרך RPC בלבד.** `payslip_ni_set_save` (יצירה או עדכון של סט)
--      ו-`payslip_ni_set_remove` (הסרה רכה — הכלי שמחיל מיגרציות בייצור עוצר על
--      מחיקה), שתיהן עם `payslips.employer_cost`. אותה בדיקת מדרגות של 0219
--      (`app.payslip_ni_normalize`).
--
--   4. **מה שכבר הוגדר עובר כמו שהוא.** המדרגות מ-`payslip_settings` (0219)
--      הופכות לסט אחד בלי תאריכים (מ-2000 ובלי תפוגה) — אותה תוצאה כמו היום, עד
--      שהבעלים יקבע לו תקופה. `payslip_settings` אינה נקראת יותר.
--      `payslip_ni_brackets_save` נשארת לתאימות: מחליפה את כל הסטים בסט אחד בלי
--      תאריכים.
--
--   5. **עובדי קבלנים אינם בסיכומים.** הבעלים: "בסיכומים אל תציג לי את העובדים
--      של הקבלן." תלוש ששויך לעובד קבלן (0220) נשאר אצל העובד, אבל סיכומי החודש
--      ב-`payslips_board` סופרים רק אנשי צוות; השורה מסומנת `contractor_worker`,
--      והמסך משאיר אותה מחוץ לטבלת החודש (כמו "ללא שיוך", 0222).

-- ===== 1. הטבלה ============================================================

create table if not exists payslip_ni_bracket_sets (
  id          uuid primary key default gen_random_uuid(),
  valid_from  date not null check (valid_from = date_trunc('month', valid_from)::date),
  valid_to    date check (valid_to = date_trunc('month', valid_to)::date),
  brackets    jsonb not null,
  created_by  uuid references profiles(id) on delete set null,
  updated_by  uuid references profiles(id) on delete set null,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  deleted_at  timestamptz,
  deleted_by  uuid references profiles(id) on delete set null,
  constraint payslip_ni_bracket_sets_term check (valid_to is null or valid_to >= valid_from)
);

comment on table payslip_ni_bracket_sets is
  'מדרגות ביטוח לאומי מעסיק לתקופה (0223). חודש התלוש בוחר את הסט; נכתבת רק דרך payslip_ni_set_*.';

create index if not exists payslip_ni_bracket_sets_from_idx
  on payslip_ni_bracket_sets (valid_from) where deleted_at is null;

create trigger payslip_ni_bracket_sets_updated_at before update on payslip_ni_bracket_sets
  for each row execute function app.set_updated_at();
create trigger payslip_ni_bracket_sets_audit after insert or update
  on payslip_ni_bracket_sets for each row execute function app.audit();

alter table payslip_ni_bracket_sets enable row level security;
revoke all on payslip_ni_bracket_sets from anon, authenticated, public;
grant select on payslip_ni_bracket_sets to authenticated;

create policy payslip_ni_bracket_sets_select on payslip_ni_bracket_sets for select to authenticated using (
  deleted_at is null and (select app.can_view_payslip_costs()));

-- ===== 2. עזרים ============================================================

-- בדיקת המדרגות ונרמולן — הגוף של 0219 §4, כפונקציה משותפת.
create or replace function app.payslip_ni_normalize(p_brackets jsonb)
returns jsonb language plpgsql immutable set search_path = public as $$
declare
  e      jsonb;
  n      int;
  i      int := 0;
  v_rate numeric;
  v_up   numeric;
  v_prev numeric := 0;
  v_out  jsonb := '[]'::jsonb;
begin
  if p_brackets is null or jsonb_typeof(p_brackets) <> 'array' then
    raise exception 'מדרגות לא תקינות';
  end if;
  n := jsonb_array_length(p_brackets);
  if n > 12 then
    raise exception 'עד 12 מדרגות';
  end if;

  for e in select value from jsonb_array_elements(p_brackets) loop
    i := i + 1;
    if jsonb_typeof(e) <> 'object' then
      raise exception 'מדרגה % אינה תקינה', i;
    end if;
    v_rate := app.payslip_num(e -> 'rate');
    if v_rate is null or v_rate < 0 or v_rate > 100 then
      raise exception 'מדרגה %: האחוז חייב להיות בין 0 ל-100', i;
    end if;
    if e -> 'up_to' is null or jsonb_typeof(e -> 'up_to') = 'null'
       or (jsonb_typeof(e -> 'up_to') = 'string' and btrim(e ->> 'up_to') = '') then
      if i < n then
        raise exception 'רק המדרגה האחרונה יכולה להיות בלי תקרה';
      end if;
      v_up := null;
    else
      v_up := app.payslip_num(e -> 'up_to');
      if v_up is null or v_up <= v_prev then
        raise exception 'מדרגה %: הסכום חייב להיות גדול מהמדרגה שלפניה', i;
      end if;
      v_prev := v_up;
    end if;
    v_out := v_out || jsonb_build_array(jsonb_build_object('up_to', trim_scale(v_up), 'rate', trim_scale(v_rate)));
  end loop;
  return v_out;
end $$;

revoke execute on function app.payslip_ni_normalize(jsonb) from anon, public;
grant  execute on function app.payslip_ni_normalize(jsonb) to authenticated;

-- הסט שחודש התלוש בתוכו. אין — null.
create or replace function app.payslip_ni_brackets_for(p_period date)
returns jsonb language sql stable security definer set search_path = public as $$
  select s.brackets
    from payslip_ni_bracket_sets s
   where s.deleted_at is null
     and p_period is not null
     and s.valid_from <= p_period
     and (s.valid_to is null or p_period <= s.valid_to)
   order by s.valid_from desc
   limit 1
$$;

revoke execute on function app.payslip_ni_brackets_for(date) from anon, public;
grant  execute on function app.payslip_ni_brackets_for(date) to authenticated;

-- כל התלושים מחושבים מחדש, כל אחד לפי החודש שלו (הטריגר של §3 רץ בכל עדכון).
-- פנימית — רק מתוך פונקציות definer.
create or replace function app.payslip_ni_recompute()
returns int language plpgsql security definer set search_path = public as $$
declare n int;
begin
  update payslip_amounts set employer_national_insurance = null where payslip_id is not null;
  get diagnostics n = row_count;
  return n;
end $$;

revoke execute on function app.payslip_ni_recompute() from anon, authenticated, public;

-- ===== 3. החישוב — לפי חודש התלוש ==========================================

-- app.payslip_amounts_compute (0219 §3) — אותו גוף; המדרגות של חודש התלוש.
create or replace function app.payslip_amounts_compute()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  new.imputed_income := null;
  new.employer_national_insurance := app.payslip_employer_ni(
    new.taxable_income,
    app.payslip_ni_brackets_for((select period from payslips where id = new.payslip_id)));
  return new;
end $$;

revoke execute on function app.payslip_amounts_compute() from anon, authenticated, public;

-- תלוש שעבר חודש — הביטוח הלאומי שלו לפי המדרגות של החודש החדש.
create or replace function app.payslip_period_recompute()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  update payslip_amounts set employer_national_insurance = null where payslip_id = new.id;
  return null;
end $$;

revoke execute on function app.payslip_period_recompute() from anon, authenticated, public;

create trigger payslips_period_recompute after update of period on payslips
  for each row when (old.period is distinct from new.period)
  execute function app.payslip_period_recompute();

-- ===== 4. שמירה והסרה ======================================================

create or replace function payslip_ni_set_save(
  p_id uuid, p_valid_from date, p_valid_to date, p_brackets jsonb)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_from date := date_trunc('month', p_valid_from)::date;
  v_to   date := date_trunc('month', p_valid_to)::date;
  v_br   jsonb;
  v_id   uuid := p_id;
begin
  if not app.can_view_payslip_costs() then
    raise exception 'אין לך הרשאה לערוך את מדרגות הביטוח הלאומי' using errcode = '42501';
  end if;
  if v_from is null then
    raise exception 'יש לבחור חודש תחולה';
  end if;
  if v_to is not null and v_to < v_from then
    raise exception 'חודש התפוגה לפני חודש התחולה';
  end if;
  v_br := app.payslip_ni_normalize(p_brackets);
  if jsonb_array_length(v_br) = 0 then
    raise exception 'יש להזין לפחות מדרגה אחת';
  end if;
  if v_id is not null and not exists (
       select 1 from payslip_ni_bracket_sets where id = v_id and deleted_at is null) then
    raise exception 'התקופה לא נמצאה';
  end if;
  if exists (
       select 1 from payslip_ni_bracket_sets s
        where s.deleted_at is null
          and s.id is distinct from v_id
          and s.valid_from <= coalesce(v_to, 'infinity'::date)
          and coalesce(s.valid_to, 'infinity'::date) >= v_from) then
    raise exception 'התקופה חופפת לתקופה אחרת של מדרגות — יש לקצר אחת מהן';
  end if;

  if v_id is null then
    insert into payslip_ni_bracket_sets (valid_from, valid_to, brackets, created_by, updated_by)
    values (v_from, v_to, v_br, app.profile_id(), app.profile_id())
    returning id into v_id;
  else
    update payslip_ni_bracket_sets set
      valid_from = v_from, valid_to = v_to, brackets = v_br, updated_by = app.profile_id()
    where id = v_id;
  end if;

  perform app.payslip_ni_recompute();
  return v_id;
end $$;

revoke execute on function payslip_ni_set_save(uuid, date, date, jsonb) from anon, public;
grant  execute on function payslip_ni_set_save(uuid, date, date, jsonb) to authenticated;

create or replace function payslip_ni_set_remove(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not app.can_view_payslip_costs() then
    raise exception 'אין לך הרשאה לערוך את מדרגות הביטוח הלאומי' using errcode = '42501';
  end if;
  update payslip_ni_bracket_sets set deleted_at = now(), deleted_by = app.profile_id()
   where id = p_id and deleted_at is null;
  if not found then
    raise exception 'התקופה לא נמצאה';
  end if;
  perform app.payslip_ni_recompute();
end $$;

revoke execute on function payslip_ni_set_remove(uuid) from anon, public;
grant  execute on function payslip_ni_set_remove(uuid) to authenticated;

-- payslip_ni_brackets_save (0219 §4) — לתאימות: סט אחד בלי תאריכים במקום כל
-- הסטים. רשימה ריקה — אין מדרגות בכלל.
create or replace function payslip_ni_brackets_save(p_brackets jsonb)
returns int language plpgsql security definer set search_path = public as $$
declare v_br jsonb;
begin
  if not app.can_view_payslip_costs() then
    raise exception 'אין לך הרשאה לערוך את מדרגות הביטוח הלאומי' using errcode = '42501';
  end if;
  v_br := app.payslip_ni_normalize(p_brackets);
  update payslip_ni_bracket_sets set deleted_at = now(), deleted_by = app.profile_id()
   where deleted_at is null;
  if jsonb_array_length(v_br) > 0 then
    insert into payslip_ni_bracket_sets (valid_from, valid_to, brackets, created_by, updated_by)
    values ('2000-01-01', null, v_br, app.profile_id(), app.profile_id());
  end if;
  return app.payslip_ni_recompute();
end $$;

revoke execute on function payslip_ni_brackets_save(jsonb) from anon, public;
grant  execute on function payslip_ni_brackets_save(jsonb) to authenticated;

-- ===== 5. מה שכבר הוגדר ====================================================

insert into payslip_ni_bracket_sets (valid_from, valid_to, brackets, created_by, updated_by)
select '2000-01-01', null, s.value, s.updated_by, s.updated_by
  from payslip_settings s
 where s.key = 'employer_ni_brackets'
   and jsonb_typeof(s.value) = 'array' and jsonb_array_length(s.value) > 0
   and not exists (select 1 from payslip_ni_bracket_sets where deleted_at is null);

select app.payslip_ni_recompute();

-- ===== 6. עובדי קבלנים אינם בסיכומים ======================================

-- payslips_board (0222) — אותו גוף; `contractor_worker` בשורה, והסיכומים רק על
-- תלושים של אנשי צוות.
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
           'contractor_worker',    p.user_kind = 'contractor_user',
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
       where r ->> 'profile_id' is not null
         and not coalesce((r ->> 'contractor_worker')::boolean, false)) end);
end $$;

revoke execute on function payslips_board(uuid, date, boolean) from anon, public;
grant  execute on function payslips_board(uuid, date, boolean) to authenticated;
