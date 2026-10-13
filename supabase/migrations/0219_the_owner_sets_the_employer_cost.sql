-- 0219: הבעלים קובע איך מחושבת עלות המעביד
--
-- בקשת הבעלים, אחרי הקריאה הראשונה של תלושים אמיתיים (0218):
--
--   "החישוב צריך להתבצע כך: נתונים כלליים — ברוטו ונטו. ניכויים מהעובד:
--    ביטוח לאומי, דמי בריאות, מיטב דש, מס הכנסה (בצד ימין למטה בתלוש).
--    תשלום מעסיק: פיצויים (בצד שמאל למעלה, 'פיצויים חודשי'), קופת גמל
--    ('קופ"ג מעסיק-חודשי'), ביטוח לאומי — חישוב באחוזים מתוך הסכום שחייב
--    במס ('חייב מ.ה.' בעמודה השמאלית), עם חלון בהגדרות שבו אני מזין
--    מדרגות: למשל עד 7,000 — 1%, ומ-7,000 עד 15,000 — 5%. סה"כ עלות לתלוש:
--    הברוטו + כל תשלומי המעסיק."
--
-- ההכרעות:
--
--   1. **עלות מעביד = ברוטו + תשלומי המעסיק.** בלי הפחתת זקיפות שווי
--      (0218 §4 הפחית אותן; הבעלים לא). העמודה המחושבת
--      `payslip_amounts.employer_cost` נשארת כמו שהיא — ברוטו − זקיפות +
--      הפרשות — ו-`imputed_income` פשוט תמיד ריקה מעכשיו (טריגר, §3). כך
--      הנוסחה היא בדיוק של הבעלים בלי לגעת בעמודה מחושבת (שינוי ביטוי של
--      עמודה מחושבת דורש הסרה ויצירה מחדש, והכלי שמחיל מיגרציות בייצור עוצר
--      על כל הסרה). הקריאה והטופס כבר אינם שואלים על זקיפות.
--
--   2. **ביטוח לאומי מעסיק מחושב, לא נקרא.** מ-`taxable_income` (חייב מ.ה.,
--      עמודה חדשה) לפי מדרגות שהבעלים מזין בהגדרות. המדרגות שוליות, כמו
--      בביטוח הלאומי: כל מדרגה חלה רק על החלק של ההכנסה שבתוכה. עד 7,000 —
--      1% ומ-7,000 עד 15,000 — 5%, על 10,000: 70 + 150 = 220. מעל המדרגה
--      האחרונה שיש לה תקרה — אין חיוב (תקרת ההכנסה המבוטחת); מדרגה אחרונה
--      בלי תקרה חלה על כל השאר. בלי "חייב מ.ה." או בלי מדרגות — אין ביטוח
--      לאומי מעסיק, והמסך אומר זאת.
--
--   3. **החישוב בטריגר, ושמירת מדרגות מחשבת מחדש את כל התלושים.** טריגר
--      BEFORE על `payslip_amounts` מחשב את `employer_national_insurance` בכל
--      כתיבה, ו-`payslip_ni_brackets_save` מעדכנת את כל השורות כדי שהטריגר
--      ירוץ שוב. משמעות: שינוי מדרגות משנה גם את העלות של חודשים קודמים.
--      אם יידרש "מדרגות לפי תקופה" — זה המקום להוסיף תאריך תחולה.
--
--   4. **דמי בריאות — רכיב נפרד** (`employee_health_tax`). עד עכשיו נקראו
--      יחד עם הביטוח הלאומי של העובד; הבעלים מונה אותם בנפרד. ניכויי העובד
--      הם מידע בלבד — אינם חלק מעלות המעביד (הם כבר בתוך הברוטו).
--
--   5. **קריאת הסכומים מחדש בלי לשבור שיוך.** בקובץ שכבר שויכו ממנו תלושים
--      `payslip_apply_reading` מסרבת (קיבוץ מחדש היה מוחק שיוך). התלושים
--      שכבר עלו נקראו לפני שהיה "חייב מ.ה." — ולכן `payslip_refresh_amounts`
--      מחילה את הקריאות על התלושים הקיימים, לפי טווח העמודים של כל אחד, בלי
--      לגעת בשיוך ובקיבוץ. תלוש שהסכומים שלו תוקנו ביד — לא נדרס.
--
--   6. **המדרגות — מי שרואה עלות מעביד** (`payslips.employer_cost`), גם
--      לקריאה וגם לכתיבה. נשמרות ב-`payslip_settings` (לא ב-`app_settings`,
--      שנקראת לכל משתמש מחובר), ומתועדות ביומן הביקורת.

-- ===== 1. רכיבים חדשים =====================================================

alter table payslip_amounts
  add column if not exists taxable_income      numeric(12, 2),
  add column if not exists employee_health_tax numeric(12, 2);

comment on column payslip_amounts.taxable_income is
  'חייב מ.ה. — הבסיס לביטוח לאומי מעסיק לפי המדרגות (0219 §2).';
comment on column payslip_amounts.employee_health_tax is
  'דמי בריאות שנוכו מהעובד (0219 §4). מידע — לא חלק מעלות המעביד.';
comment on column payslip_amounts.imputed_income is
  'מ-0219 תמיד ריקה: עלות המעביד היא ברוטו + תשלומי המעסיק, בלי הפחתת זקיפות.';
comment on column payslip_amounts.employer_national_insurance is
  'מ-0219 מחושב בטריגר מ-taxable_income לפי payslip_settings.employer_ni_brackets.';

-- ===== 2. ההגדרות ==========================================================

create table if not exists payslip_settings (
  key        text primary key check (key in ('employer_ni_brackets')),
  value      jsonb not null,
  updated_by uuid references profiles(id) on delete set null,
  updated_at timestamptz not null default now()
);

comment on table payslip_settings is
  'הגדרות התלושים (0219 §6). נקראת ונכתבת רק עם payslips.employer_cost; הכתיבה דרך RPC.';

insert into payslip_settings (key, value) values ('employer_ni_brackets', '[]'::jsonb)
on conflict (key) do nothing;

create trigger payslip_settings_audit after insert or update
  on payslip_settings for each row execute function app.audit();

alter table payslip_settings enable row level security;
revoke all on payslip_settings from anon, authenticated, public;
grant select on payslip_settings to authenticated;

create policy payslip_settings_select on payslip_settings for select to authenticated using (
  (select app.can_view_payslip_costs()));

-- ===== 3. ביטוח לאומי מעסיק ================================================

-- מדרגות שוליות: [{up_to, rate}], up_to עולה, רק האחרונה רשאית להיות null.
-- המדרגות כבר מנורמלות (payslip_ni_brackets_save); כאן רק החשבון.
create or replace function app.payslip_employer_ni(p_taxable numeric, p_brackets jsonb)
returns numeric language sql immutable set search_path = public as $$
  select case
    when p_taxable is null or p_brackets is null or jsonb_typeof(p_brackets) <> 'array'
         or jsonb_array_length(p_brackets) = 0 then null
    else round(coalesce((
      select sum(greatest(0, least(p_taxable, coalesce(x.up_to, p_taxable)) - x.lo) * x.rate / 100)
        from (select (b ->> 'up_to')::numeric as up_to,
                     (b ->> 'rate')::numeric  as rate,
                     coalesce(lag((b ->> 'up_to')::numeric) over (order by o), 0) as lo
                from jsonb_array_elements(p_brackets) with ordinality t(b, o)) x), 0), 2)
  end
$$;

revoke execute on function app.payslip_employer_ni(numeric, jsonb) from anon, public;
grant  execute on function app.payslip_employer_ni(numeric, jsonb) to authenticated;

create or replace function app.payslip_amounts_compute()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  new.imputed_income := null;
  new.employer_national_insurance := app.payslip_employer_ni(
    new.taxable_income,
    (select value from payslip_settings where key = 'employer_ni_brackets'));
  return new;
end $$;

revoke execute on function app.payslip_amounts_compute() from anon, authenticated, public;

create trigger payslip_amounts_compute before insert or update
  on payslip_amounts for each row execute function app.payslip_amounts_compute();

-- השורות הקיימות: בלי זקיפות, והביטוח הלאומי מחושב (עוד אין להן "חייב מ.ה.").
update payslip_amounts set imputed_income = null;

-- ===== 4. שמירת המדרגות ====================================================

create or replace function payslip_ni_brackets_save(p_brackets jsonb)
returns int language plpgsql security definer set search_path = public as $$
declare
  e      jsonb;
  n      int;
  i      int := 0;
  v_rate numeric;
  v_up   numeric;
  v_prev numeric := 0;
  v_out  jsonb := '[]'::jsonb;
begin
  if not app.can_view_payslip_costs() then
    raise exception 'אין לך הרשאה לערוך את מדרגות הביטוח הלאומי' using errcode = '42501';
  end if;
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

  insert into payslip_settings (key, value, updated_by)
  values ('employer_ni_brackets', v_out, app.profile_id())
  on conflict (key) do update set
    value      = excluded.value,
    updated_by = excluded.updated_by,
    updated_at = now();

  -- הטריגר מחשב מחדש בכל עדכון
  update payslip_amounts set employer_national_insurance = null;
  get diagnostics n = row_count;
  return n;
end $$;

revoke execute on function payslip_ni_brackets_save(jsonb) from anon, public;
grant  execute on function payslip_ni_brackets_save(jsonb) to authenticated;

-- ===== 5. כתיבת הסכומים — במקום אחד ========================================

-- הרכיבים שהקריאה והטופס מכירים (0219). זקיפות וביטוח לאומי מעסיק אינם
-- כאן: הטריגר (§3) קובע אותם. פנימית — רק מתוך פונקציות definer.
create or replace function app.payslip_amounts_put(p_payslip_id uuid, a jsonb, p_source text)
returns void language plpgsql security definer set search_path = public as $$
begin
  insert into payslip_amounts (
    payslip_id, gross_pay, net_pay, taxable_income,
    income_tax, employee_national_insurance, employee_health_tax, employee_pension, employee_study_fund,
    employer_pension, employer_severance, employer_study_fund, employer_other,
    printed_employer_cost, source, updated_by)
  values (
    p_payslip_id, app.payslip_num(a -> 'gross_pay'), app.payslip_num(a -> 'net_pay'),
    app.payslip_num(a -> 'taxable_income'),
    app.payslip_num(a -> 'income_tax'), app.payslip_num(a -> 'employee_national_insurance'),
    app.payslip_num(a -> 'employee_health_tax'),
    app.payslip_num(a -> 'employee_pension'), app.payslip_num(a -> 'employee_study_fund'),
    app.payslip_num(a -> 'employer_pension'), app.payslip_num(a -> 'employer_severance'),
    app.payslip_num(a -> 'employer_study_fund'), app.payslip_num(a -> 'employer_other'),
    app.payslip_num(a -> 'printed_employer_cost'), p_source, app.profile_id())
  on conflict (payslip_id) do update set
    gross_pay                   = excluded.gross_pay,
    net_pay                     = excluded.net_pay,
    taxable_income              = excluded.taxable_income,
    income_tax                  = excluded.income_tax,
    employee_national_insurance = excluded.employee_national_insurance,
    employee_health_tax         = excluded.employee_health_tax,
    employee_pension            = excluded.employee_pension,
    employee_study_fund         = excluded.employee_study_fund,
    employer_pension            = excluded.employer_pension,
    employer_severance          = excluded.employer_severance,
    employer_study_fund         = excluded.employer_study_fund,
    employer_other              = excluded.employer_other,
    printed_employer_cost       = excluded.printed_employer_cost,
    source                      = excluded.source,
    updated_by                  = excluded.updated_by,
    updated_at                  = now();
end $$;

revoke execute on function app.payslip_amounts_put(uuid, jsonb, text) from anon, authenticated, public;

-- payslip_apply_reading (0218 §7) — אותו גוף, והסכומים דרך app.payslip_amounts_put.
create or replace function payslip_apply_reading(p_batch_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_batch    payslip_batches;
  v_me       uuid := app.profile_id();
  v_read     int;
  p          int;
  r          jsonb;
  cur        jsonb;
  v_groups   jsonb := '[]'::jsonb;
  v_join     boolean;
  v_conflict boolean;
  v_same     boolean;
  v_idx      int;
  g          jsonb;
  a          jsonb;
  v_id       uuid;
  v_detected date;
  v_rk       text;
  v_ck       text;
begin
  if not app.can_manage_payslips() then
    raise exception 'אין לך הרשאה לנהל תלושי שכר' using errcode = '42501';
  end if;
  select * into v_batch from payslip_batches where id = p_batch_id and deleted_at is null for update;
  if not found then
    raise exception 'הקובץ לא נמצא';
  end if;
  if exists (select 1 from payslips
              where batch_id = p_batch_id and deleted_at is null and profile_id is not null) then
    raise exception 'כבר שויכו תלושים מהקובץ הזה — הקריאה אינה מחלקת אותו מחדש';
  end if;
  select count(*) into v_read from payslip_page_readings where batch_id = p_batch_id;
  if v_read = 0 then
    raise exception 'הקובץ עוד לא נקרא';
  end if;

  for p in 1 .. v_batch.page_count loop
    r := (select reading from payslip_page_readings where batch_id = p_batch_id and page_no = p);
    v_join := false;

    if cur is not null and r is not null
       and cur ->> 'kind' = 'payslip' and r ->> 'kind' = 'payslip' then
      v_rk := app.payslip_name_key(r ->> 'employee_name');
      v_ck := app.payslip_name_key(cur ->> 'employee_name');
      v_conflict :=
           (r ->> 'employee_no' is not null and cur ->> 'employee_no' is not null
            and r ->> 'employee_no' <> cur ->> 'employee_no')
        or (v_rk is not null and v_ck is not null and v_rk <> v_ck)
        or (r ->> 'period' is not null and cur ->> 'period' is not null
            and r ->> 'period' <> cur ->> 'period');
      v_same :=
           (r ->> 'employee_no' is not null and r ->> 'employee_no' = cur ->> 'employee_no')
        or (r ->> 'employee_no' is null and cur ->> 'employee_no' is null
            and v_rk is not null and v_rk = v_ck);
      v_idx := case when r ->> 'page_index' ~ '^[0-9]{1,3}$' then (r ->> 'page_index')::int end;
      v_join := not v_conflict and ((v_idx is not null and v_idx > 1) or (v_idx is null and v_same));
    end if;

    if v_join then
      cur := cur
        || jsonb_build_object('to', p)
        || jsonb_strip_nulls(jsonb_build_object(
             'employee_name', coalesce(cur ->> 'employee_name', r ->> 'employee_name'),
             'employee_no',   coalesce(cur ->> 'employee_no', r ->> 'employee_no'),
             'period',        coalesce(cur ->> 'period', r ->> 'period')))
        || jsonb_build_object('amounts',
             coalesce(cur -> 'amounts', '{}'::jsonb)
             || jsonb_strip_nulls(case when jsonb_typeof(r -> 'amounts') = 'object'
                                       then r -> 'amounts' else '{}'::jsonb end));
    else
      if cur is not null then
        v_groups := v_groups || jsonb_build_array(cur);
      end if;
      cur := jsonb_strip_nulls(jsonb_build_object(
        'from',          p,
        'to',            p,
        'kind',          case when r ->> 'kind' in ('payslip', 'other') then r ->> 'kind' end,
        'employee_name', nullif(btrim(r ->> 'employee_name'), ''),
        'employee_no',   nullif(btrim(r ->> 'employee_no'), ''),
        'period',        r ->> 'period'))
        || jsonb_build_object('amounts',
             jsonb_strip_nulls(case when jsonb_typeof(r -> 'amounts') = 'object'
                                    then r -> 'amounts' else '{}'::jsonb end));
    end if;
  end loop;
  v_groups := v_groups || jsonb_build_array(cur);

  -- אף תלוש בקובץ לא שויך (נבדק למעלה), ולכן אף עובד לא ראה אותם. הם
  -- יורדים בהסרה רכה ונפתחים מחדש מהעמודים (0218 §7).
  update payslips set deleted_at = now(), deleted_by = v_me
   where batch_id = p_batch_id and deleted_at is null;

  for g in select value from jsonb_array_elements(v_groups) loop
    v_detected := app.payslip_period(g ->> 'period');
    insert into payslips (
      batch_id, page_from, page_to, period,
      detected_kind, detected_name, detected_employee_no, detected_period, link_key)
    values (
      p_batch_id, (g ->> 'from')::int, (g ->> 'to')::int, coalesce(v_detected, v_batch.period),
      g ->> 'kind', left(g ->> 'employee_name', 120), left(g ->> 'employee_no', 40), v_detected,
      case when g ->> 'kind' = 'payslip'
           then app.payslip_link_key(left(g ->> 'employee_no', 40), left(g ->> 'employee_name', 120)) end)
    returning id into v_id;

    a := g -> 'amounts';
    if g ->> 'kind' = 'payslip' and a is not null and a <> '{}'::jsonb then
      perform app.payslip_amounts_put(v_id, a, 'reading');
    end if;
  end loop;

  update payslip_batches set read_at = now() where id = p_batch_id;

  return jsonb_build_object(
    'slips',      (select count(*) from payslips where batch_id = p_batch_id and deleted_at is null
                                                   and detected_kind is distinct from 'other'),
    'other',      (select count(*) from payslips where batch_id = p_batch_id and deleted_at is null
                                                   and detected_kind = 'other'),
    'read_pages', v_read,
    'pages',      v_batch.page_count);
end $$;

revoke execute on function payslip_apply_reading(uuid) from anon, public;
grant  execute on function payslip_apply_reading(uuid) to authenticated;

-- payslip_merge_previous (0218 §8) — אותו גוף; העתקת הסכומים דרך העזר.
create or replace function payslip_merge_previous(p_payslip_id uuid)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_slip payslips;
  v_prev payslips;
  v_amt  payslip_amounts;
begin
  if not app.can_manage_payslips() then
    raise exception 'אין לך הרשאה לנהל תלושי שכר' using errcode = '42501';
  end if;
  select * into v_slip from payslips where id = p_payslip_id and deleted_at is null for update;
  if not found then
    raise exception 'התלוש לא נמצא';
  end if;
  select * into v_prev from payslips
   where batch_id = v_slip.batch_id and deleted_at is null and page_to = v_slip.page_from - 1
   for update;
  if not found then
    raise exception 'אין לפניו תלוש בקובץ שאפשר לצרף אליו';
  end if;
  if v_slip.profile_id is not null and v_slip.profile_id is distinct from v_prev.profile_id then
    raise exception 'התלוש שויך לעובד אחר — יש לבטל את השיוך לפני הצירוף';
  end if;

  update payslips set page_to = v_slip.page_to where id = v_prev.id;

  if not exists (select 1 from payslip_amounts where payslip_id = v_prev.id and gross_pay is not null) then
    select * into v_amt from payslip_amounts where payslip_id = v_slip.id;
    if found then
      perform app.payslip_amounts_put(v_prev.id, to_jsonb(v_amt), v_amt.source);
    end if;
  end if;

  update payslips set deleted_at = now(), deleted_by = app.profile_id() where id = v_slip.id;
  return v_prev.id;
end $$;

revoke execute on function payslip_merge_previous(uuid) from anon, public;
grant  execute on function payslip_merge_previous(uuid) to authenticated;

-- payslip_amounts_save (0218 §9) — אותן בדיקות, הכתיבה דרך העזר.
create or replace function payslip_amounts_save(p_payslip_id uuid, p_amounts jsonb)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not app.can_view_payslip_costs() then
    raise exception 'אין לך הרשאה לערוך את סכומי התלוש' using errcode = '42501';
  end if;
  if p_amounts is null or jsonb_typeof(p_amounts) <> 'object' then
    raise exception 'סכומים לא תקינים';
  end if;
  if not exists (select 1 from payslips where id = p_payslip_id and deleted_at is null) then
    raise exception 'התלוש לא נמצא';
  end if;
  perform app.payslip_amounts_put(p_payslip_id, p_amounts, 'manual');
end $$;

revoke execute on function payslip_amounts_save(uuid, jsonb) from anon, public;
grant  execute on function payslip_amounts_save(uuid, jsonb) to authenticated;

-- ===== 6. קריאת הסכומים מחדש ===============================================

-- הקריאות השמורות של כל עמוד חלות על התלושים הקיימים בקובץ, לפי טווח
-- העמודים של כל תלוש (הערך האחרון לכל רכיב, כמו בקיבוץ). השיוך, החודש
-- והטווחים — לא משתנים. תלוש שהסכומים שלו הוקלדו ביד — לא נדרס.
create or replace function payslip_refresh_amounts(p_batch_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  s         payslips;
  r         jsonb;
  a         jsonb;
  p         int;
  v_updated int := 0;
  v_manual  int := 0;
begin
  if not app.can_manage_payslips() then
    raise exception 'אין לך הרשאה לנהל תלושי שכר' using errcode = '42501';
  end if;
  if not exists (select 1 from payslip_batches where id = p_batch_id and deleted_at is null) then
    raise exception 'הקובץ לא נמצא';
  end if;

  for s in select * from payslips
            where batch_id = p_batch_id and deleted_at is null
              and detected_kind is distinct from 'other'
            order by page_from
  loop
    if exists (select 1 from payslip_amounts where payslip_id = s.id and source = 'manual') then
      v_manual := v_manual + 1;
      continue;
    end if;
    a := '{}'::jsonb;
    for p in s.page_from .. s.page_to loop
      r := (select reading from payslip_page_readings where batch_id = p_batch_id and page_no = p);
      if r ->> 'kind' = 'payslip' and jsonb_typeof(r -> 'amounts') = 'object' then
        a := a || jsonb_strip_nulls(r -> 'amounts');
      end if;
    end loop;
    if a <> '{}'::jsonb then
      perform app.payslip_amounts_put(s.id, a, 'reading');
      v_updated := v_updated + 1;
    end if;
  end loop;

  update payslip_batches set read_at = now() where id = p_batch_id;
  return jsonb_build_object('updated', v_updated, 'manual', v_manual);
end $$;

revoke execute on function payslip_refresh_amounts(uuid) from anon, public;
grant  execute on function payslip_refresh_amounts(uuid) to authenticated;
