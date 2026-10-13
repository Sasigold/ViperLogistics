-- 0218: התלוש מוצא את בעליו
--
-- בקשת הבעלים:
--
--   "רואה החשבון שולח לי קובץ PDF עם נגיד 12 תלושי שכר בפנים. אני רוצה
--    להעלות את הקובץ, ושעל כל תלוש תשאל אותי למי לשייך אותו — כל פעם מחדש,
--    עם כל התלושים שהעליתי. אחרי שאני משייך לעובד מהמערכת, העובד רואה כל
--    חודש את התלוש שלו. בנוסף אני רוצה לדעת מה עלות המעביד שלי לעובד —
--    שתקרא את התלוש ותוציא ממנו את העלות, כמו בחוק במדינת ישראל — ושזה לא
--    יוצג לעובד, רק לי כמנהל מערכת."
--
-- ההכרעות:
--
--   1. **הקובץ מתפצל לעמודים, והתלוש הוא טווח עמודים.** הדפדפן מפצל את
--      ה-PDF (pdf-lib, שכבר משמש להצעת המחיר) ומעלה כל עמוד כקובץ משלו:
--      `payslips/<batch_id>/<page>.pdf`. שורת `payslips` אומרת "עמודים X עד Y
--      בקובץ הזה הם תלוש אחד". כך איחוד תלוש של שני עמודים, או פיצול שגוי,
--      הם שינוי של שתי שורות — בלי לגעת בקבצים, ובלי שהשרת יצטרך ספריית PDF.
--      בהעלאה כל עמוד הוא תלוש (`payslip_batch_create`); הקריאה (§3) מאחדת.
--
--   2. **שיוך הוא פרסום.** תלוש ששויך לעובד נראה לו מיד (RLS על `payslips`,
--      והקבצים נפתחים לו דרך `app.may_touch_payslip_file`), ונשלחת לו התראה
--      `payslip_available`. ביטול השיוך מסתיר אותו שוב. אין שלב "פרסום" נפרד:
--      הבעלים ביקש "אחרי שאני משייך — זה יוצג לעובד".
--
--   3. **הקריאה האוטומטית: Claude, עמוד אחרי עמוד, בשרת.** פונקציית הקצה
--      `payslip-read` שולחת כל עמוד ל-Claude (structured outputs) ושומרת את
--      מה שנקרא ב-`payslip_page_readings` — טבלה סגורה שרק service_role כותב
--      אליה (`payslip_store_reading`), כדי שמה שנקרא מהתלוש לא יעבור דרך
--      הדפדפן ולא יהיה ניתן לזיוף משם. `payslip_apply_reading` מקבצת את
--      העמודים לתלושים כאן, במסד: עמוד שמסומן "דף 2 מתוך 2", או עמוד צמוד של
--      אותו עובד (מספר עובד, או שם כשאין מספר) לאותו חודש, מצטרף לתלוש שלפניו
--      — כל עוד הזהות לא סותרת. מפתח `ANTHROPIC_API_KEY` חסר → אין קריאה, וכל
--      השאר (פיצול, שיוך, צפייה, הקלדת הסכומים ביד) עובד בלעדיה.
--
--   4. **עלות מעביד מחושבת בשרת, לפי מבנה התלוש בישראל.** "ברוטו פחות נטו"
--      אינו עלות המעביד — זה מה שנוכה *מהעובד* (מס הכנסה, ביטוח לאומי ומס
--      בריאות של העובד, וחלק העובד בפנסיה ובקרן ההשתלמות), וכל זה כבר כלול
--      בברוטו. עלות המעביד היא הברוטו *ועוד* מה שהמעביד משלם מעליו:
--
--        עלות מעביד = סה"כ תשלומים (ברוטו)
--                   − זקיפות שווי שנכללו בברוטו ואינן כסף (שווי רכב, טלפון…)
--                   + תגמולי מעביד לפנסיה / ביטוח מנהלים
--                   + פיצויים
--                   + קרן השתלמות — חלק המעביד
--                   + ביטוח לאומי — חלק המעביד
--                   + הפרשות מעביד אחרות (אובדן כושר עבודה וכד')
--
--      העמודה `payslip_amounts.employer_cost` מחושבת (generated) מהרכיבים,
--      והרכיבים נשמרים כל אחד בנפרד כדי שאפשר יהיה לבדוק ולתקן. אם התלוש
--      מדפיס בעצמו "עלות מעביד" היא נשמרת ב-`printed_employer_cost`, והמסך
--      מתריע כשהשתיים אינן מתיישבות. חלק המעביד בביטוח הלאומי אינו מחושב כאן
--      מהשיעורים — השיעורים והתקרות משתנים כל שנה; כשהתלוש אינו מדפיס אותו
--      המסך אומר זאת, וניתן להקליד ביד.
--
--   5. **הסכומים סגורים לעובד.** `payslip_amounts` נקראת רק עם
--      `payslips.employer_cost`. העובד רואה את קובץ התלוש שלו — ושום מספר
--      שהמערכת חישבה ממנו. גם הטבלה הזו וגם הקריאות אינן מתועדות ביומן
--      הביקורת: `audit_log` נפתח ל-`settings.audit_log`, שאינו `employer_cost`.
--
--   6. **בלי תעודת זהות** — אותה הכרעה של 0210 §2. העובד בתלוש מזוהה לפי
--      "מספר עובד" אצל רואה החשבון (`e:`), ובהיעדרו לפי השם (`n:`, מנורמל,
--      בלי תלות בסדר המילים — "כהן משה" הוא "משה כהן"). הצימוד נזכר
--      ב-`payslip_links` בכל שיוך, ובחודש הבא התלוש מציע את העובד מעצמו.
--      ההצעה היא הצעה: המסך עדיין שואל על כל תלוש.
--
--   7. **שלוש הרשאות, אנשי צוות בלבד.** `payslips.view_own` (פתוח לכל עובד —
--      זה התלוש שלו), `payslips.manage` (העלאה, שיוך, כל התלושים; מסוכנת)
--      ו-`payslips.employer_cost` (הסכומים ועלות המעביד; מסוכנת). מנהל מערכת
--      מחזיק את כולן. הטבלאות נכתבות רק דרך פונקציות definer.

-- ===== 1. הרשאות ===========================================================

select app.register_module('payslips', 'תלושי שכר',
  'העלאת תלושי השכר מרואה החשבון, שיוך כל תלוש לעובד ועלות מעביד', 'Receipt', 86);

select app.register_permission('payslips.view_own', 'payslips', 'התלושים שלי',
  'העובד רואה ומוריד את תלושי השכר ששויכו אליו',
  'access', true, false, array['staff']::user_kind[], null, 10);

select app.register_permission('payslips.manage', 'payslips', 'ניהול תלושי שכר',
  'העלאת קובץ התלושים מרואה החשבון, שיוך כל תלוש לעובד, וצפייה בתלושים של כולם',
  'action', false, true, array['staff']::user_kind[], null, 20);

select app.register_permission('payslips.employer_cost', 'payslips', 'עלות מעביד',
  'הסכומים שנקראו מהתלושים — ברוטו, נטו, הפרשות המעביד ועלות המעביד — ותיקונם',
  'field', false, true, array['staff']::user_kind[], null, 30);

create or replace function app.can_view_own_payslips()
returns boolean language sql stable security definer set search_path = public as $$
  select app.is_admin()
      or (app.user_kind() = 'staff' and app.has('payslips.view_own'))
$$;

create or replace function app.can_manage_payslips()
returns boolean language sql stable security definer set search_path = public as $$
  select app.is_admin()
      or (app.user_kind() = 'staff' and app.has('payslips.manage'))
$$;

create or replace function app.can_view_payslip_costs()
returns boolean language sql stable security definer set search_path = public as $$
  select app.is_admin()
      or (app.user_kind() = 'staff' and app.has('payslips.employer_cost'))
$$;

revoke execute on function app.can_view_own_payslips() from anon, public;
revoke execute on function app.can_manage_payslips() from anon, public;
revoke execute on function app.can_view_payslip_costs() from anon, public;
grant  execute on function app.can_view_own_payslips() to authenticated;
grant  execute on function app.can_manage_payslips() to authenticated;
grant  execute on function app.can_view_payslip_costs() to authenticated;

-- ===== 2. הטבלאות ==========================================================

create table payslip_batches (
  id          uuid primary key default gen_random_uuid(),
  file_name   text not null,
  page_count  int  not null check (page_count between 1 and 200),
  -- החודש שנבחר בהעלאה. תלוש שהקריאה מצאה בו חודש אחר מקבל את שלו.
  period      date not null check (period = date_trunc('month', period)::date),
  -- מתי הקריאה האוטומטית קובצה לתלושים (payslip_apply_reading). null — טרם.
  read_at     timestamptz,
  uploaded_by uuid references profiles(id) on delete set null,
  created_at  timestamptz not null default now(),
  deleted_at  timestamptz,
  deleted_by  uuid references profiles(id) on delete set null
);

comment on table payslip_batches is
  'קובץ תלושים שהועלה (0218). כל עמוד שמור ב-Storage כ-payslips/<id>/<page>.pdf.';

create table payslips (
  id                   uuid primary key default gen_random_uuid(),
  batch_id             uuid not null references payslip_batches(id) on delete cascade,
  page_from            int  not null,
  page_to              int  not null,
  period               date not null check (period = date_trunc('month', period)::date),
  -- העובד שהתלוש שלו. null — טרם שויך (ואז אף עובד אינו רואה אותו).
  profile_id           uuid references profiles(id) on delete set null,
  assigned_by          uuid references profiles(id) on delete set null,
  assigned_at          timestamptz,
  -- מה שהקריאה מצאה בעמודים (§3). null — לא נקרא.
  detected_kind        text check (detected_kind in ('payslip', 'other')),
  detected_name        text,
  detected_employee_no text,
  detected_period      date,
  link_key             text,
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now(),
  deleted_at           timestamptz,
  deleted_by           uuid references profiles(id) on delete set null,
  constraint payslips_pages check (page_from >= 1 and page_to >= page_from)
);

comment on table payslips is
  'תלוש שכר = טווח עמודים בקובץ (0218). נכתב רק דרך payslip_* RPCs; העובד רואה רק את שלו.';

create index payslips_batch_idx on payslips (batch_id, page_from) where deleted_at is null;
create index payslips_profile_idx on payslips (profile_id, period) where deleted_at is null;
create index payslips_period_idx on payslips (period) where deleted_at is null;

create trigger payslips_updated_at before update on payslips
  for each row execute function app.set_updated_at();
create trigger payslip_batches_audit after insert or update or delete
  on payslip_batches for each row execute function app.audit();
create trigger payslips_audit after insert or update or delete
  on payslips for each row execute function app.audit();

-- הסכומים. שורה אחת לתלוש, כשיש מה לשמור (מהקריאה או ביד).
create table payslip_amounts (
  payslip_id                  uuid primary key references payslips(id) on delete cascade,
  -- סה"כ תשלומים
  gross_pay                   numeric(12, 2),
  -- נטו לתשלום
  net_pay                     numeric(12, 2),
  -- זקיפות שווי שנכללו בתוך gross_pay ואינן כסף ששולם (שווי רכב, טלפון…)
  imputed_income              numeric(12, 2),
  -- ניכויי העובד — מידע, לא נכנסים לעלות המעביד (הם כבר בתוך הברוטו)
  income_tax                  numeric(12, 2),
  employee_national_insurance numeric(12, 2),
  employee_pension            numeric(12, 2),
  employee_study_fund         numeric(12, 2),
  -- הפרשות המעביד, מעל הברוטו
  employer_pension            numeric(12, 2),
  employer_severance          numeric(12, 2),
  employer_study_fund         numeric(12, 2),
  employer_national_insurance numeric(12, 2),
  employer_other              numeric(12, 2),
  -- "עלות מעביד" כפי שהתלוש עצמו מדפיס, כשהוא מדפיס — להצלבה בלבד
  printed_employer_cost       numeric(12, 2),
  employer_contributions      numeric(12, 2) generated always as (
    coalesce(employer_pension, 0) + coalesce(employer_severance, 0)
    + coalesce(employer_study_fund, 0) + coalesce(employer_national_insurance, 0)
    + coalesce(employer_other, 0)) stored,
  employer_cost               numeric(12, 2) generated always as (
    case when gross_pay is null then null else
      gross_pay - coalesce(imputed_income, 0)
      + coalesce(employer_pension, 0) + coalesce(employer_severance, 0)
      + coalesce(employer_study_fund, 0) + coalesce(employer_national_insurance, 0)
      + coalesce(employer_other, 0) end) stored,
  -- כמה נוכה מהעובד בסך הכול (ברוטו פחות נטו) — מה שהעובד לא קיבל ביד
  deductions                  numeric(12, 2) generated always as (gross_pay - net_pay) stored,
  source                      text not null check (source in ('reading', 'manual')),
  updated_by                  uuid references profiles(id) on delete set null,
  updated_at                  timestamptz not null default now()
);

comment on table payslip_amounts is
  'סכומי התלוש ועלות המעביד (0218 §4). נקראת רק עם payslips.employer_cost.';

-- מה שנקרא מכל עמוד, כפי ש-payslip-read נרמלה אותו. רק service_role כותב.
create table payslip_page_readings (
  batch_id  uuid not null references payslip_batches(id) on delete cascade,
  page_no   int  not null check (page_no >= 1),
  reading   jsonb not null,
  model     text,
  read_at   timestamptz not null default now(),
  primary key (batch_id, page_no)
);

comment on table payslip_page_readings is
  'קריאת עמוד תלוש (0218 §3). נכתבת רק ב-payslip_store_reading (service_role), נקראת רק ב-definer.';

create table payslip_links (
  -- 'e:<מספר עובד>' כשיש, אחרת 'n:<שם מנורמל וממוין>'
  link_key   text primary key,
  profile_id uuid not null references profiles(id) on delete cascade,
  updated_by uuid references profiles(id) on delete set null,
  updated_at timestamptz not null default now()
);

comment on table payslip_links is
  'עובד בתלוש ↔ עובד במערכת (0218 §6). נכתב בכל payslip_assign.';

create trigger payslip_links_audit after insert or update or delete
  on payslip_links for each row execute function app.audit();

alter table payslip_batches enable row level security;
alter table payslips enable row level security;
alter table payslip_amounts enable row level security;
alter table payslip_page_readings enable row level security;
alter table payslip_links enable row level security;

revoke all on payslip_batches from anon, public;
revoke all on payslips from anon, public;
revoke all on payslip_amounts from anon, public;
revoke insert, update, delete, truncate on payslip_batches from authenticated;
revoke insert, update, delete, truncate on payslips from authenticated;
revoke insert, update, delete, truncate on payslip_amounts from authenticated;
grant select on payslip_batches to authenticated;
grant select on payslips to authenticated;
grant select on payslip_amounts to authenticated;
-- סגורות לגמרי, כמו 0210 §2: הכול דרך definer
revoke all on payslip_page_readings from anon, authenticated, public;
revoke all on payslip_links from anon, authenticated, public;

-- קריאה בלבד; אין פוליסת כתיבה, גם לא למנהל מערכת.
create policy payslip_batches_select on payslip_batches for select to authenticated using (
  deleted_at is null
  and ((select app.can_manage_payslips()) or (select app.can_view_payslip_costs())));

create policy payslips_select on payslips for select to authenticated using (
  deleted_at is null
  and ((profile_id = (select app.profile_id()) and (select app.can_view_own_payslips()))
       or (select app.can_manage_payslips())
       or (select app.can_view_payslip_costs())));

create policy payslip_amounts_select on payslip_amounts for select to authenticated using (
  (select app.can_view_payslip_costs()));

-- ===== 3. עזרים ============================================================

-- שם כמפתח: מנורמל כמו בסיבוס (app.cibus_norm), והמילים ממוינות — התלוש
-- מדפיס "כהן משה", והמערכת מכירה "משה כהן".
create or replace function app.payslip_name_key(p text)
returns text language sql immutable set search_path = public as $$
  select nullif(array_to_string(array(
           select w from unnest(string_to_array(app.cibus_norm(p), ' ')) w
            where w <> '' order by w), ' '), '')
$$;

create or replace function app.payslip_link_key(p_employee_no text, p_name text)
returns text language sql immutable set search_path = public as $$
  select case
    when nullif(regexp_replace(coalesce(p_employee_no, ''), '\s', '', 'g'), '') is not null
      then 'e:' || regexp_replace(p_employee_no, '\s', '', 'g')
    when app.payslip_name_key(p_name) is not null
      then 'n:' || app.payslip_name_key(p_name)
  end
$$;

-- העובד שהתלוש מציע: מה שנזכר מהשיוך הקודם, ואחרת התאמת שם יחידה בין אנשי
-- הצוות. שני "משה כהן" — אין הצעה.
create or replace function app.payslip_suggest(p_link_key text, p_name text)
returns uuid language sql stable security definer set search_path = public as $$
  select coalesce(
    (select l.profile_id
       from payslip_links l
       join profiles p on p.id = l.profile_id
      where l.link_key = p_link_key
        and p.deleted_at is null
        and p.user_kind = 'staff'),
    (select case when count(*) = 1 then min(p.id::text)::uuid end
       from profiles p
      where p.deleted_at is null
        and p.user_kind = 'staff'
        and app.payslip_name_key(p_name) is not null
        and app.payslip_name_key(p.full_name) = app.payslip_name_key(p_name)))
$$;

create or replace function app.payslip_period_label(p date)
returns text language sql immutable set search_path = public as $$
  select (array['ינואר', 'פברואר', 'מרץ', 'אפריל', 'מאי', 'יוני', 'יולי', 'אוגוסט',
                'ספטמבר', 'אוקטובר', 'נובמבר', 'דצמבר'])[extract(month from p)::int]
         || ' ' || extract(year from p)::int
$$;

-- סכום מ-JSON: מספר, או מחרוזת שהיא מספר. כל דבר אחר — null.
create or replace function app.payslip_num(p jsonb)
returns numeric language sql immutable set search_path = public as $$
  select case
    when p is null then null
    when jsonb_typeof(p) = 'number' and abs((p #>> '{}')::numeric) < 1000000000
      then round((p #>> '{}')::numeric, 2)
    when jsonb_typeof(p) = 'string' and btrim(p #>> '{}') ~ '^-?[0-9]{1,9}(\.[0-9]+)?$'
      then round(btrim(p #>> '{}')::numeric, 2)
  end
$$;

-- חודש מ-JSON: 'YYYY-MM-01' בשנים סבירות, אחרת null.
create or replace function app.payslip_period(p text)
returns date language sql immutable set search_path = public as $$
  select case when p ~ '^(20[0-9]{2})-(0[1-9]|1[0-2])-01$' then p::date end
$$;

-- ===== 4. הקבצים ===========================================================
--
-- הנתיב הוא החוזה: '<batch_id>/<page>.pdf', כמו 0089 §8. definer, והשער כולו
-- כתוב כאן (CLAUDE.md §2.5): עובד אינו רואה את `payslip_batches`, ולכן
-- פונקציה עם ה-RLS שלו לא הייתה מוצאת את הקובץ שלו.

create or replace function app.may_touch_payslip_file(p_name text, p_write boolean)
returns boolean language plpgsql stable security definer set search_path = public as $$
declare
  v_batch uuid;
  v_file  text;
  v_page  int;
begin
  if p_name is null or split_part(p_name, '/', 3) <> '' then
    return false;
  end if;
  v_file := split_part(p_name, '/', 2);
  if v_file !~ '^[1-9][0-9]{0,2}\.pdf$' then
    return false;
  end if;
  begin
    v_batch := split_part(p_name, '/', 1)::uuid;
  exception when others then
    return false;
  end;
  v_page := split_part(v_file, '.', 1)::int;

  -- מי שמנהל תלושים: כל עמוד שהקובץ יודע עליו, לקריאה ולכתיבה — גם אחרי
  -- שהקובץ הוסר, כי המסך מוחק את העמודים אחרי ההסרה, ו-DELETE עם WHERE
  -- עובר גם בפוליסת ה-SELECT.
  if app.can_manage_payslips() then
    return exists (select 1 from payslip_batches b
                    where b.id = v_batch and v_page <= b.page_count);
  end if;
  if p_write then
    return false;
  end if;

  if app.can_view_payslip_costs() then
    return exists (select 1 from payslip_batches b
                    where b.id = v_batch and b.deleted_at is null and v_page <= b.page_count);
  end if;

  return app.can_view_own_payslips() and exists (
    select 1
      from payslips s
      join payslip_batches b on b.id = s.batch_id
     where s.batch_id = v_batch
       and v_page between s.page_from and s.page_to
       and s.profile_id = app.profile_id()
       and s.deleted_at is null
       and b.deleted_at is null);
end $$;

revoke execute on function app.payslip_name_key(text) from anon, public;
revoke execute on function app.payslip_link_key(text, text) from anon, public;
revoke execute on function app.payslip_suggest(text, text) from anon, public;
revoke execute on function app.payslip_period_label(date) from anon, public;
revoke execute on function app.payslip_num(jsonb) from anon, public;
revoke execute on function app.payslip_period(text) from anon, public;
revoke execute on function app.may_touch_payslip_file(text, boolean) from anon, public;
grant  execute on function app.payslip_name_key(text) to authenticated;
grant  execute on function app.payslip_link_key(text, text) to authenticated;
grant  execute on function app.payslip_suggest(text, text) to authenticated;
grant  execute on function app.payslip_period_label(date) to authenticated;
grant  execute on function app.payslip_num(jsonb) to authenticated;
grant  execute on function app.payslip_period(text) to authenticated;
grant  execute on function app.may_touch_payslip_file(text, boolean) to authenticated;

do $$
begin
  if to_regclass('storage.buckets') is null or to_regclass('storage.objects') is null then
    raise notice '0218: אין סכמת storage — הדלי והפוליסות מדולגים';
    return;
  end if;

  -- עמוד אחד של תלוש שוקל עשרות KB; סריקה — עד 1-2MB. 10MB לעמוד הוא רצפה
  -- נדיבה, ורק PDF.
  execute $sql$
    insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
    values ('payslips', 'payslips', false, 10485760, array['application/pdf'])
    on conflict (id) do update set
      public             = false,
      file_size_limit    = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types
  $sql$;

  -- create בלבד, בלי להסיר קודם: הפוליסות חדשות, והכלי שמחיל מיגרציות
  -- בייצור עוצר על כל פקודת הסרה (CLAUDE.md §1).
  begin
    if not exists (select 1 from pg_policies where schemaname = 'storage' and tablename = 'objects'
                     and policyname = 'payslips_objects_read') then
      execute $sql$
        create policy payslips_objects_read on storage.objects for select to authenticated
          using (bucket_id = 'payslips' and app.may_touch_payslip_file(name, false))
      $sql$;
    end if;
    if not exists (select 1 from pg_policies where schemaname = 'storage' and tablename = 'objects'
                     and policyname = 'payslips_objects_insert') then
      execute $sql$
        create policy payslips_objects_insert on storage.objects for insert to authenticated
          with check (bucket_id = 'payslips' and app.may_touch_payslip_file(name, true))
      $sql$;
    end if;
    if not exists (select 1 from pg_policies where schemaname = 'storage' and tablename = 'objects'
                     and policyname = 'payslips_objects_update') then
      execute $sql$
        create policy payslips_objects_update on storage.objects for update to authenticated
          using (bucket_id = 'payslips' and app.may_touch_payslip_file(name, true))
          with check (bucket_id = 'payslips' and app.may_touch_payslip_file(name, true))
      $sql$;
    end if;
    if not exists (select 1 from pg_policies where schemaname = 'storage' and tablename = 'objects'
                     and policyname = 'payslips_objects_delete') then
      execute $sql$
        create policy payslips_objects_delete on storage.objects for delete to authenticated
          using (bucket_id = 'payslips' and app.may_touch_payslip_file(name, true))
      $sql$;
    end if;
  exception when insufficient_privilege then
    raise warning '0218: אין בעלות על storage.objects — ארבע פוליסות התלושים לא נוצרו. יש להגדיר אותן ב-Dashboard → Storage → Policies על הדלי payslips, עם הביטוי app.may_touch_payslip_file(name, <false לקריאה / true לכתיבה>). עד אז RLS דוחה כל גישה לקבצים.';
  end;
end $$;

-- ===== 5. ההתראה לעובד =====================================================

select app.register_notification_type('payslip_available', 'תלוש שכר חדש',
  'תלוש שכר שויך אליי וזמין לצפייה ולהורדה',
  'תלושי שכר', array['admin', 'staff'], 'payslip', 'opt_out', 'opt_out', 'opt_in', 220);

update notification_types set required_permission = 'payslips.view_own'
 where key = 'payslip_available';

create or replace function app.notify_payslip_available(p_payslip_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_slip payslips;
begin
  select * into v_slip from payslips where id = p_payslip_id and deleted_at is null;
  if v_slip.profile_id is null then return; end if;
  perform app.notify(v_slip.profile_id, 'payslip_available', 'תלוש שכר חדש',
    'תלוש השכר ל' || app.payslip_period_label(v_slip.period) || ' זמין לצפייה ולהורדה',
    'payslip', v_slip.id);
end $$;

revoke execute on function app.notify_payslip_available(uuid) from anon, authenticated, public;

-- גוף 0110, ועוד ענף אחד: התראה על תלוש פותחת את "התלושים שלי".
create or replace function app.notification_link(
  p_recipient uuid, p_type text, p_entity_type text, p_entity_id uuid)
returns text language plpgsql stable security definer set search_path = public as $$
declare v_date date;
begin
  if p_entity_id is null then return '/'; end if;

  if p_entity_type = 'event' then
    return '/events/' || p_entity_id;
  end if;

  if p_entity_type = 'task' then
    select task_date into v_date from tasks where id = p_entity_id;
    return '/board?task=' || p_entity_id
           || coalesce('&date=' || to_char(v_date, 'YYYY-MM-DD'), '');
  end if;

  if p_entity_type = 'attendance_entry' then
    if p_type in ('attendance_submitted', 'attendance_clock_in', 'attendance_clock_out') then
      select work_date into v_date from attendance_entries where id = p_entity_id;
      return '/attendance?entry=' || p_entity_id
             || coalesce('&date=' || to_char(v_date, 'YYYY-MM-DD'), '');
    end if;
    return '/my/attendance?entry=' || p_entity_id;
  end if;

  if p_entity_type = 'vehicle' then
    return '/vehicles/' || p_entity_id;
  end if;

  if p_entity_type = 'payslip' then
    return '/my/payslips';
  end if;

  return '/';
end $$;

-- ===== 6. העלאה ============================================================
--
-- הדפדפן קורא לזו לפני שהוא מעלה את העמודים: היא יוצרת את הקובץ ותלוש לכל
-- עמוד, והשער של Storage מתיר להעלות רק עמודים שהקובץ יודע עליהם.

create or replace function payslip_batch_create(p_file_name text, p_page_count int, p_period date)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_id     uuid;
  v_period date := date_trunc('month', p_period)::date;
begin
  if not app.can_manage_payslips() then
    raise exception 'אין לך הרשאה להעלות תלושי שכר' using errcode = '42501';
  end if;
  if p_page_count is null or p_page_count < 1 then
    raise exception 'הקובץ ריק';
  end if;
  if p_page_count > 200 then
    raise exception 'הקובץ גדול מדי — עד 200 עמודים בהעלאה אחת';
  end if;
  if v_period is null then
    raise exception 'יש לבחור את החודש של התלושים';
  end if;

  insert into payslip_batches (file_name, page_count, period, uploaded_by)
  values (coalesce(nullif(left(btrim(coalesce(p_file_name, '')), 200), ''), 'תלושים.pdf'),
          p_page_count, v_period, app.profile_id())
  returning id into v_id;

  insert into payslips (batch_id, page_from, page_to, period)
  select v_id, g, g, v_period from generate_series(1, p_page_count) g;

  return v_id;
end $$;

revoke execute on function payslip_batch_create(text, int, date) from anon, public;
grant  execute on function payslip_batch_create(text, int, date) to authenticated;

-- ===== 7. הקריאה ===========================================================

-- payslip-read בלבד (service_role). הקריאה מנורמלת שם; כאן רק נשמרת.
create or replace function payslip_store_reading(
  p_batch_id uuid, p_page int, p_reading jsonb, p_model text default null)
returns void language plpgsql security definer set search_path = public as $$
begin
  if p_reading is null or jsonb_typeof(p_reading) <> 'object' then
    raise exception 'קריאה לא תקינה';
  end if;
  if not exists (select 1 from payslip_batches
                  where id = p_batch_id and deleted_at is null and p_page between 1 and page_count) then
    raise exception 'העמוד לא נמצא';
  end if;

  insert into payslip_page_readings (batch_id, page_no, reading, model)
  values (p_batch_id, p_page, p_reading, left(p_model, 80))
  on conflict (batch_id, page_no) do update set
    reading = excluded.reading,
    model   = excluded.model,
    read_at = now();
end $$;

revoke execute on function payslip_store_reading(uuid, int, jsonb, text) from anon, authenticated, public;
grant  execute on function payslip_store_reading(uuid, int, jsonb, text) to service_role;

-- מקבצת את העמודים שנקראו לתלושים ומחליפה בהם את התלושים של הקובץ.
--
-- עמוד מצטרף לתלוש שלפניו כששניהם תלושים, הזהות אינה סותרת (מספר עובד,
-- שם וחודש — כל אחד מהם, כשהוא קיים בשניהם, שווה), ואחד מאלה:
--   • העמוד מסומן כהמשך ("דף 2 מתוך 2" — page_index > 1);
--   • אין סימון, והוא של אותו עובד (אותו מספר; או שניהם בלי מספר ואותו שם).
-- סימון עמודים של הקובץ כולו ("עמוד 3 מתוך 12") אינו מאחד שני עובדים: הזהות
-- שלהם סותרת. עמוד שלא נקרא, או שאינו תלוש, עומד לבדו.
--
-- הסכומים של תלוש רב-עמודי: לכל רכיב — הערך האחרון שנקרא (הסיכומים מודפסים
-- בעמוד האחרון). מסרבת כשכבר שויך תלוש מהקובץ: קיבוץ מחדש היה מוחק אותו.

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

  -- אף תלוש בקובץ לא שויך (נבדק למעלה), ולכן אף עובד לא ראה אותם. גם מה
  -- שהוסר ביד ("לא תלוש") חוזר — הקיבוץ מתחיל מהעמודים.
  delete from payslips where batch_id = p_batch_id;

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
      insert into payslip_amounts (
        payslip_id, gross_pay, net_pay, imputed_income,
        income_tax, employee_national_insurance, employee_pension, employee_study_fund,
        employer_pension, employer_severance, employer_study_fund, employer_national_insurance,
        employer_other, printed_employer_cost, source, updated_by)
      values (
        v_id, app.payslip_num(a -> 'gross_pay'), app.payslip_num(a -> 'net_pay'),
        app.payslip_num(a -> 'imputed_income'),
        app.payslip_num(a -> 'income_tax'), app.payslip_num(a -> 'employee_national_insurance'),
        app.payslip_num(a -> 'employee_pension'), app.payslip_num(a -> 'employee_study_fund'),
        app.payslip_num(a -> 'employer_pension'), app.payslip_num(a -> 'employer_severance'),
        app.payslip_num(a -> 'employer_study_fund'), app.payslip_num(a -> 'employer_national_insurance'),
        app.payslip_num(a -> 'employer_other'), app.payslip_num(a -> 'printed_employer_cost'),
        'reading', v_me);
    end if;
  end loop;

  update payslip_batches set read_at = now() where id = p_batch_id;

  return jsonb_build_object(
    'slips',      (select count(*) from payslips where batch_id = p_batch_id and detected_kind is distinct from 'other'),
    'other',      (select count(*) from payslips where batch_id = p_batch_id and detected_kind = 'other'),
    'read_pages', v_read,
    'pages',      v_batch.page_count);
end $$;

revoke execute on function payslip_apply_reading(uuid) from anon, public;
grant  execute on function payslip_apply_reading(uuid) to authenticated;

-- ===== 8. שיוך ותיקונים ====================================================

-- p_profile_id null מבטל את השיוך: התלוש יורד מעיני העובד.
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
  if p_profile_id is not null and not exists (
       select 1 from profiles where id = p_profile_id and deleted_at is null and user_kind = 'staff') then
    raise exception 'העובד לא נמצא';
  end if;
  if v_slip.profile_id is not distinct from p_profile_id then
    return;
  end if;

  update payslips set
    profile_id  = p_profile_id,
    assigned_by = case when p_profile_id is null then null else v_me end,
    assigned_at = case when p_profile_id is null then null else now() end
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

create or replace function payslip_set_period(p_payslip_id uuid, p_period date)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not app.can_manage_payslips() then
    raise exception 'אין לך הרשאה לנהל תלושי שכר' using errcode = '42501';
  end if;
  if p_period is null then
    raise exception 'יש לבחור חודש';
  end if;
  update payslips set period = date_trunc('month', p_period)::date
   where id = p_payslip_id and deleted_at is null;
  if not found then
    raise exception 'התלוש לא נמצא';
  end if;
end $$;

revoke execute on function payslip_set_period(uuid, date) from anon, public;
grant  execute on function payslip_set_period(uuid, date) to authenticated;

-- התלוש הוא המשך של זה שלפניו בקובץ: העמודים שלו עוברים אליו. הקודם שומר
-- את השיוך ואת החודש שלו; הסכומים — שלו, ואם אין לו ברוטו, של זה.
create or replace function payslip_merge_previous(p_payslip_id uuid)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_slip payslips;
  v_prev payslips;
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
    delete from payslip_amounts
     where payslip_id = v_prev.id
       and exists (select 1 from payslip_amounts where payslip_id = v_slip.id);
    update payslip_amounts set payslip_id = v_prev.id where payslip_id = v_slip.id;
  end if;

  delete from payslips where id = v_slip.id;
  return v_prev.id;
end $$;

revoke execute on function payslip_merge_previous(uuid) from anon, public;
grant  execute on function payslip_merge_previous(uuid) to authenticated;

-- ההפך: תלוש של כמה עמודים חוזר להיות עמוד-עמוד. הראשון שומר את השיוך
-- ואת הסכומים; כל עמוד נוסף נפתח כתלוש לא משויך, עם מה שנקרא ממנו.
create or replace function payslip_split(p_payslip_id uuid)
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
  if v_slip.page_to = v_slip.page_from then
    raise exception 'התלוש הוא עמוד אחד';
  end if;

  update payslips set page_to = page_from where id = p_payslip_id;

  insert into payslips (
    batch_id, page_from, page_to, period,
    detected_kind, detected_name, detected_employee_no, detected_period, link_key)
  select v_slip.batch_id, g, g,
         coalesce(app.payslip_period(r.reading ->> 'period'), v_slip.period),
         case when r.reading ->> 'kind' in ('payslip', 'other') then r.reading ->> 'kind' end,
         left(nullif(btrim(r.reading ->> 'employee_name'), ''), 120),
         left(nullif(btrim(r.reading ->> 'employee_no'), ''), 40),
         app.payslip_period(r.reading ->> 'period'),
         case when r.reading ->> 'kind' = 'payslip'
              then app.payslip_link_key(left(r.reading ->> 'employee_no', 40),
                                        left(r.reading ->> 'employee_name', 120)) end
    from generate_series(v_slip.page_from + 1, v_slip.page_to) g
    left join payslip_page_readings r on r.batch_id = v_slip.batch_id and r.page_no = g;
end $$;

revoke execute on function payslip_split(uuid) from anon, public;
grant  execute on function payslip_split(uuid) to authenticated;

-- הסרה רכה — עמוד שאינו תלוש, או תלוש שהועלה בטעות. יורד גם מעיני העובד.
create or replace function payslip_remove(p_payslip_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not app.can_manage_payslips() then
    raise exception 'אין לך הרשאה לנהל תלושי שכר' using errcode = '42501';
  end if;
  update payslips set deleted_at = now(), deleted_by = app.profile_id()
   where id = p_payslip_id and deleted_at is null;
  if not found then
    raise exception 'התלוש לא נמצא';
  end if;
end $$;

revoke execute on function payslip_remove(uuid) from anon, public;
grant  execute on function payslip_remove(uuid) to authenticated;

-- הקובץ כולו, וכל התלושים שבו — גם אלה ששויכו. המסך מוחק אחר כך את העמודים
-- מ-Storage (השער מתיר זאת גם לקובץ שהוסר).
create or replace function payslip_batch_remove(p_batch_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_me uuid := app.profile_id();
begin
  if not app.can_manage_payslips() then
    raise exception 'אין לך הרשאה לנהל תלושי שכר' using errcode = '42501';
  end if;
  update payslip_batches set deleted_at = now(), deleted_by = v_me
   where id = p_batch_id and deleted_at is null;
  if not found then
    raise exception 'הקובץ לא נמצא';
  end if;
  update payslips set deleted_at = now(), deleted_by = v_me
   where batch_id = p_batch_id and deleted_at is null;
end $$;

revoke execute on function payslip_batch_remove(uuid) from anon, public;
grant  execute on function payslip_batch_remove(uuid) to authenticated;

-- ===== 9. הסכומים ביד ======================================================

create or replace function payslip_amounts_save(p_payslip_id uuid, p_amounts jsonb)
returns void language plpgsql security definer set search_path = public as $$
declare a jsonb := p_amounts;
begin
  if not app.can_view_payslip_costs() then
    raise exception 'אין לך הרשאה לערוך את סכומי התלוש' using errcode = '42501';
  end if;
  if a is null or jsonb_typeof(a) <> 'object' then
    raise exception 'סכומים לא תקינים';
  end if;
  if not exists (select 1 from payslips where id = p_payslip_id and deleted_at is null) then
    raise exception 'התלוש לא נמצא';
  end if;

  insert into payslip_amounts (
    payslip_id, gross_pay, net_pay, imputed_income,
    income_tax, employee_national_insurance, employee_pension, employee_study_fund,
    employer_pension, employer_severance, employer_study_fund, employer_national_insurance,
    employer_other, printed_employer_cost, source, updated_by)
  values (
    p_payslip_id, app.payslip_num(a -> 'gross_pay'), app.payslip_num(a -> 'net_pay'),
    app.payslip_num(a -> 'imputed_income'),
    app.payslip_num(a -> 'income_tax'), app.payslip_num(a -> 'employee_national_insurance'),
    app.payslip_num(a -> 'employee_pension'), app.payslip_num(a -> 'employee_study_fund'),
    app.payslip_num(a -> 'employer_pension'), app.payslip_num(a -> 'employer_severance'),
    app.payslip_num(a -> 'employer_study_fund'), app.payslip_num(a -> 'employer_national_insurance'),
    app.payslip_num(a -> 'employer_other'), app.payslip_num(a -> 'printed_employer_cost'),
    'manual', app.profile_id())
  on conflict (payslip_id) do update set
    gross_pay                   = excluded.gross_pay,
    net_pay                     = excluded.net_pay,
    imputed_income              = excluded.imputed_income,
    income_tax                  = excluded.income_tax,
    employee_national_insurance = excluded.employee_national_insurance,
    employee_pension            = excluded.employee_pension,
    employee_study_fund         = excluded.employee_study_fund,
    employer_pension            = excluded.employer_pension,
    employer_severance          = excluded.employer_severance,
    employer_study_fund         = excluded.employer_study_fund,
    employer_national_insurance = excluded.employer_national_insurance,
    employer_other              = excluded.employer_other,
    printed_employer_cost       = excluded.printed_employer_cost,
    source                      = 'manual',
    updated_by                  = excluded.updated_by,
    updated_at                  = now();
end $$;

revoke execute on function payslip_amounts_save(uuid, jsonb) from anon, public;
grant  execute on function payslip_amounts_save(uuid, jsonb) to authenticated;

-- ===== 10. המסך של המנהל ===================================================
--
-- התלושים — של קובץ, של חודש, או רק אלה שממתינים לשיוך — עם העובד שהתלוש
-- מציע, והסכומים רק למי שמחזיק `payslips.employer_cost`. הסיכומים נספרים כאן
-- ולא בדפדפן, ורק על תלושים ששויכו (תלוש שממתין לשיוך עוד יכול להתברר ככפול
-- או כעמוד שאינו תלוש).

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
       and (not p_unassigned or s.profile_id is null)
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
           'assigned_at',          s.assigned_at,
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
    left join payslip_amounts a on a.payslip_id = s.id
    left join lateral (
      select pp.id, pp.full_name
        from profiles pp
       where s.profile_id is null
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
       where r ->> 'profile_id' is not null) end);
end $$;

revoke execute on function payslips_board(uuid, date, boolean) from anon, public;
grant  execute on function payslips_board(uuid, date, boolean) to authenticated;

-- הקבצים שהועלו, החדש ראשון: כמה תלושים בכל אחד, כמה שויכו, כמה עמודים נקראו.
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
