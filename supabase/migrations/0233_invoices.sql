-- 0233: חשבוניות — סריקה, תיקייה לחודש, ייצוא לרואה החשבון וחיבור Gmail
--
-- בקשת הבעלים:
--
--   "אני רוצה סקשן של חשבוניות. אני מעלה חשבונית (PDF, או מצלם — והתמונה
--    נשמרת כ-PDF), המודל של Anthropic סורק אותה ומקטלג: תאריך, סכום, על מה
--    זה יצא, השורות. אחר כך אני מייצא הכול לרואה החשבון בצורה מסודרת. בנוסף —
--    לחבר את ה-Gmail שלי, שיסרוק וימשוך משם חשבוניות, רק כאלה שיצאו עבור
--    החברות שאני מגדיר. מסודר בתיקייה לפי חודשים, עם סיכום — כמה סך הכול
--    וכמה מע"מ."
--
-- ההכרעות:
--
--   1. **מנהלי מערכת בלבד** (הכרעת הבעלים). המפתח `invoices.manage` נרשם עם
--      `applies_to` ריק — כמו `command.view` (0227), אין שכבה שמעניקה אותו
--      לאחרים — וכל פונקציה כאן שואלת `app.require_invoices()`.
--
--   2. **כל חשבונית היא קובץ PDF אחד** ב-Storage: `invoices/<id>.pdf`. צילום
--      הופך ל-PDF בדפדפן (pdf-lib, כמו התלושים ב-0218), וקובץ תמונה שמגיע
--      במייל הופך ל-PDF בפונקציית הקצה. כך התיקייה שנשלחת לרואה החשבון אחידה.
--      אותו קובץ פעמיים (sha256) נדחה כל עוד הראשון לא הוסר.
--
--   3. **הקריאה: Claude, בשרת** (`invoice-read`, אותו דפוס של `payslip-read`).
--      מה שנקרא נכתב רק דרך `invoice_store_reading` (service_role) — ולא דורס
--      חשבונית שמישהו כבר אישר או תיקן ביד (`reviewed_at`); אז הקריאה נשמרת
--      רק ב-`raw_reading`, להשוואה.
--
--   4. **החודש של רואה החשבון** (`period`) הוא חודש תאריך החשבונית, וניתן
--      לשינוי — חשבונית מ-31 בחודש שהגיעה באיחור יכולה להיכנס לחודש הבא.
--      בלי תאריך — חודש ההעלאה. זו "התיקייה".
--
--   5. **הכסף מחושב בשרת** (CLAUDE.md §2.1): `invoices_board(period)` מחזיר
--      את החשבוניות, את הסיכום (לפני מע"מ, מע"מ, סה"כ), את הפילוח לפי סוג
--      הוצאה ואת התיקיות (חודשים). חשבונית זיכוי נשמרת בסכומים שליליים,
--      ולכן סכום פשוט נכון. מטבע זר אינו נספר בסיכום בשקלים — הוא נספר בנפרד.
--
--   6. **החברות שהחשבונית יצאה עבורן** (`invoice_companies`: שם, ח.פ., שמות
--      נוספים). חשבונית שהועלתה ביד נשמרת תמיד ומסומנת בחברה שזוהתה. מה
--      שמגיע מ-Gmail נשמר **רק** כשהנמען שנקרא מהחשבונית הוא אחת החברות —
--      לפי ח.פ. (ספרות בלבד), ואחרת לפי שם או שם נוסף (`app.cibus_norm`).
--      בלי חברות מוגדרות — Gmail אינו מושך דבר.
--
--   7. **Gmail: חיבור OAuth ישיר, קריאה בלבד.** פונקציית הקצה `invoice-gmail`
--      מנהלת את ההסכמה מול Google ושומרת את ה-refresh token בטבלה סגורה
--      (`invoice_gmail_accounts`), שאיש מלבד service_role אינו קורא — גם לא
--      מנהל מערכת. המסך רואה רק כתובת, מצב וזמן סריקה (`invoice_gmail_status`).
--      כל הודעה שנבדקה נרשמת (`invoice_gmail_messages`), כך שאינה נקראת שוב.
--      הסריקה האוטומטית — pg_cron כל 3 שעות, דרך pg_net, כשהוגדרו
--      `app.invoice_gmail_url` ו-`app.invoice_gmail_secret` (כמו arco, 0184).
--
--   8. **בלי DROP ובלי DELETE** (CLAUDE.md §1): הסרה היא `deleted_at`, גם של
--      שורות חשבונית שהוחלפו בשמירה.

-- ===== 1. הרשאה ============================================================

select app.register_module('invoices', 'חשבוניות',
  'חשבוניות ספקים: סריקה, תיקייה לכל חודש, ייצוא לרואה החשבון וחיבור Gmail', 'Receipt', 87);

select app.register_permission('invoices.manage', 'invoices', 'חשבוניות',
  'חשבוניות הספקים. פתוח למנהלי מערכת בלבד — אין שכבה שמעניקה אותו לאחרים',
  'access', false, false, array[]::user_kind[], null, 10);

create or replace function app.require_invoices()
returns void language plpgsql stable security definer set search_path = public as $$
begin
  if not coalesce(app.is_admin(), false) then
    raise exception 'החשבוניות פתוחות למנהלי מערכת בלבד' using errcode = '42501';
  end if;
end $$;

revoke execute on function app.require_invoices() from anon, public;
grant  execute on function app.require_invoices() to authenticated;

-- ===== 2. הטבלאות ==========================================================

create table invoice_companies (
  id         uuid primary key default gen_random_uuid(),
  name       text not null check (length(btrim(name)) between 1 and 200),
  -- ח.פ. / ע.מ. — ספרות בלבד
  tax_id     text check (tax_id ~ '^[0-9]{5,12}$'),
  -- שמות נוספים שהחברה מופיעה בהם בחשבוניות ("וייפר מיקור חוץ", "Viper Outsourcing")
  aliases    text[] not null default '{}',
  active     boolean not null default true,
  created_by uuid references profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

comment on table invoice_companies is
  'החברות שחשבוניות יוצאות עבורן (0233 §6). Gmail מושך רק חשבוניות שהנמען בהן הוא אחת מהן.';

create trigger invoice_companies_updated before update on invoice_companies
  for each row execute function app.set_updated_at();

create table invoice_gmail_accounts (
  id             uuid primary key default gen_random_uuid(),
  email          text not null,
  -- סודי: נקרא רק ב-service_role (פונקציית הקצה). null — נותק.
  refresh_token  text,
  -- תוספת לשאילתת החיפוש ב-Gmail ("from:billing@…", "label:חשבוניות")
  query_extra    text not null default '' check (length(query_extra) <= 300),
  active         boolean not null default true,
  connected_by   uuid references profiles(id) on delete set null,
  connected_at   timestamptz not null default now(),
  -- עד מתי נסרק במלואו; הסריקה הבאה מתחילה יומיים לפני
  synced_until   timestamptz,
  last_run_at    timestamptz,
  last_error     text,
  deleted_at     timestamptz
);

create unique index invoice_gmail_accounts_email on invoice_gmail_accounts (lower(email))
  where deleted_at is null;

comment on table invoice_gmail_accounts is
  'חשבון Gmail מחובר (0233 §7). סגורה לגמרי: המסך קורא רק דרך invoice_gmail_status.';

create table invoices (
  id                uuid primary key default gen_random_uuid(),
  source            text not null check (source in ('upload', 'camera', 'gmail')),
  file_name         text not null check (length(file_name) between 1 and 300),
  -- invoices/<id>.pdf
  file_path         text not null,
  file_sha256       text not null check (file_sha256 ~ '^[0-9a-f]{64}$'),
  read_status       text not null default 'pending'
                    check (read_status in ('pending', 'done', 'failed')),
  read_error        text,
  read_model        text,
  read_at           timestamptz,
  raw_reading       jsonb,
  doc_type          text not null default 'tax_invoice'
                    check (doc_type in ('tax_invoice', 'tax_invoice_receipt', 'receipt', 'credit', 'other')),
  vendor_name       text,
  vendor_tax_id     text,
  invoice_number    text,
  issue_date        date,
  -- החודש של רואה החשבון — "התיקייה"
  period            date not null check (period = date_trunc('month', period)::date),
  currency          text not null default 'ILS' check (currency ~ '^[A-Z]{3}$'),
  amount_before_vat numeric(12, 2),
  vat_amount        numeric(12, 2),
  total_amount      numeric(12, 2),
  category          text not null default 'other' check (category in (
                      'subcontractors', 'equipment', 'vehicle', 'fuel', 'rent', 'utilities',
                      'communication', 'software', 'office', 'food', 'professional',
                      'marketing', 'insurance', 'travel', 'maintenance', 'other')),
  description       text,
  recipient_name    text,
  recipient_tax_id  text,
  company_id        uuid references invoice_companies(id) on delete set null,
  notes             text,
  reviewed_at       timestamptz,
  reviewed_by       uuid references profiles(id) on delete set null,
  gmail_account_id  uuid references invoice_gmail_accounts(id) on delete set null,
  gmail_message_id  text,
  gmail_from        text,
  gmail_subject     text,
  gmail_date        timestamptz,
  created_by        uuid references profiles(id) on delete set null,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  deleted_at        timestamptz,
  deleted_by        uuid references profiles(id) on delete set null
);

comment on table invoices is
  'חשבונית ספק = קובץ PDF אחד (0233). נכתבת רק דרך invoice_* RPCs; מנהלי מערכת בלבד.';

create unique index invoices_sha_live on invoices (file_sha256) where deleted_at is null;
create index invoices_period_idx on invoices (period) where deleted_at is null;

create trigger invoices_updated before update on invoices
  for each row execute function app.set_updated_at();
create trigger invoices_audit after insert or update or delete
  on invoices for each row execute function app.audit();

create table invoice_lines (
  id          uuid primary key default gen_random_uuid(),
  invoice_id  uuid not null references invoices(id) on delete cascade,
  line_no     int not null check (line_no >= 1),
  description text not null,
  quantity    numeric(12, 3),
  unit_price  numeric(12, 2),
  total       numeric(12, 2),
  deleted_at  timestamptz
);

create index invoice_lines_invoice_idx on invoice_lines (invoice_id, line_no) where deleted_at is null;

create table invoice_gmail_messages (
  account_id   uuid not null references invoice_gmail_accounts(id) on delete cascade,
  message_id   text not null,
  processed_at timestamptz not null default now(),
  imported     int not null default 0,
  skipped      int not null default 0,
  note         text,
  primary key (account_id, message_id)
);

comment on table invoice_gmail_messages is
  'הודעות Gmail שכבר נבדקו (0233 §7) — כדי שלא ייקראו שוב. נכתבת רק ב-service_role.';

alter table invoice_companies enable row level security;
alter table invoice_gmail_accounts enable row level security;
alter table invoices enable row level security;
alter table invoice_lines enable row level security;
alter table invoice_gmail_messages enable row level security;

revoke all on invoice_companies, invoices, invoice_lines from anon, public;
revoke insert, update, delete, truncate on invoice_companies, invoices, invoice_lines from authenticated;
grant select on invoice_companies, invoices, invoice_lines to authenticated;
revoke all on invoice_gmail_accounts, invoice_gmail_messages from anon, authenticated, public;

-- קריאה בלבד, למנהלי מערכת; אין פוליסת כתיבה.
create policy invoice_companies_select on invoice_companies for select to authenticated
  using (deleted_at is null and (select app.is_admin()));
create policy invoices_select on invoices for select to authenticated
  using (deleted_at is null and (select app.is_admin()));
create policy invoice_lines_select on invoice_lines for select to authenticated
  using (deleted_at is null and (select app.is_admin()));

-- ===== 3. עזרים ============================================================

create or replace function app.invoice_digits(p text)
returns text language sql immutable set search_path = public as $$
  select nullif(regexp_replace(coalesce(p, ''), '[^0-9]', '', 'g'), '')
$$;

-- טקסט נקי מ-JSON: רווחים מכווצים, אורך מוגבל, ריק — null.
create or replace function app.invoice_text(p jsonb, p_max int)
returns text language sql immutable set search_path = public as $$
  select case when p is null or jsonb_typeof(p) <> 'string' then null
    else nullif(left(btrim(regexp_replace(p #>> '{}', '\s+', ' ', 'g')), p_max), '') end
$$;

create or replace function app.invoice_date(p jsonb)
returns date language plpgsql immutable set search_path = public as $$
declare
  v text := case when p is not null and jsonb_typeof(p) = 'string' then btrim(p #>> '{}') end;
  d date;
begin
  if v is null or v !~ '^\d{4}-\d{2}-\d{2}$' then return null; end if;
  d := v::date;
  if d < date '2000-01-01' or d > date '2099-12-31' then return null; end if;
  return d;
exception when others then
  return null;
end $$;

-- החברה שהחשבונית יצאה עבורה: ח.פ. שווה, ואחרת שם או שם נוסף שמופיע בשם הנמען.
create or replace function app.invoice_company_for(p_name text, p_tax_id text)
returns uuid language sql stable security definer set search_path = public as $$
  select c.id
    from invoice_companies c
   where c.deleted_at is null and c.active
     and ((app.invoice_digits(p_tax_id) is not null and c.tax_id = app.invoice_digits(p_tax_id))
          or (app.cibus_norm(p_name) is not null
              and exists (select 1 from unnest(array[c.name] || c.aliases) n
                           where length(coalesce(app.cibus_norm(n), '')) >= 2
                             and position(app.cibus_norm(n) in app.cibus_norm(p_name)) > 0)))
   order by (c.tax_id is not null and c.tax_id = app.invoice_digits(p_tax_id)) desc, c.created_at
   limit 1
$$;

create or replace function app.may_touch_invoice_file(p_name text)
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(app.is_admin(), false)
     and p_name ~ '^[0-9a-f-]{36}\.pdf$'
     and exists (select 1 from invoices i where i.id = split_part(p_name, '.', 1)::uuid)
$$;

revoke execute on function app.invoice_digits(text) from anon, public;
revoke execute on function app.invoice_text(jsonb, int) from anon, public;
revoke execute on function app.invoice_date(jsonb) from anon, public;
revoke execute on function app.invoice_company_for(text, text) from anon, authenticated, public;
revoke execute on function app.may_touch_invoice_file(text) from anon, public;
grant  execute on function app.invoice_digits(text) to authenticated;
grant  execute on function app.invoice_text(jsonb, int) to authenticated;
grant  execute on function app.invoice_date(jsonb) to authenticated;
grant  execute on function app.may_touch_invoice_file(text) to authenticated;

-- ===== 4. הקובץ ============================================================

do $$
begin
  if to_regclass('storage.buckets') is null or to_regclass('storage.objects') is null then
    raise notice '0233: אין סכמת storage — הדלי והפוליסות מדולגים';
    return;
  end if;

  execute $sql$
    insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
    values ('invoices', 'invoices', false, 15728640, array['application/pdf'])
    on conflict (id) do update set
      public             = false,
      file_size_limit    = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types
  $sql$;

  begin
    if not exists (select 1 from pg_policies where schemaname = 'storage' and tablename = 'objects'
                     and policyname = 'invoices_objects_read') then
      execute $sql$
        create policy invoices_objects_read on storage.objects for select to authenticated
          using (bucket_id = 'invoices' and app.may_touch_invoice_file(name))
      $sql$;
    end if;
    if not exists (select 1 from pg_policies where schemaname = 'storage' and tablename = 'objects'
                     and policyname = 'invoices_objects_insert') then
      execute $sql$
        create policy invoices_objects_insert on storage.objects for insert to authenticated
          with check (bucket_id = 'invoices' and app.may_touch_invoice_file(name))
      $sql$;
    end if;
  exception when insufficient_privilege then
    raise warning '0233: אין בעלות על storage.objects — פוליסות החשבוניות לא נוצרו. יש להגדיר ב-Dashboard → Storage → Policies על הדלי invoices: select ו-insert עם app.may_touch_invoice_file(name).';
  end;
end $$;

-- ===== 5. מה שהמנהל עושה ===================================================

-- שורת חשבונית חדשה לפני ההעלאה. מחזירה את הנתיב שאליו הדפדפן מעלה.
create or replace function invoice_create(p_file_name text, p_source text, p_sha256 text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_id  uuid := gen_random_uuid();
  v_dup uuid;
begin
  perform app.require_invoices();
  if p_source not in ('upload', 'camera') then
    raise exception 'מקור לא מוכר';
  end if;
  if coalesce(p_sha256, '') !~ '^[0-9a-f]{64}$' then
    raise exception 'קובץ לא תקין';
  end if;
  select id into v_dup from invoices where file_sha256 = p_sha256 and deleted_at is null;
  if v_dup is not null then
    return jsonb_build_object('duplicate_of', v_dup);
  end if;
  insert into invoices (id, source, file_name, file_path, file_sha256, period, created_by)
  values (v_id, p_source, left(coalesce(nullif(btrim(p_file_name), ''), 'חשבונית.pdf'), 300),
          'invoices/' || v_id || '.pdf', p_sha256,
          date_trunc('month', (now() at time zone 'Asia/Jerusalem'))::date, app.profile_id());
  return jsonb_build_object('id', v_id, 'path', v_id || '.pdf');
end $$;

-- שמירה ביד: השדות, השורות (מחליפות את הקודמות) ואישור.
create or replace function invoice_save(p_id uuid, p jsonb)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_inv   invoices;
  v_line  jsonb;
  v_n     int := 0;
  v_issue date;
begin
  perform app.require_invoices();
  select * into v_inv from invoices where id = p_id and deleted_at is null for update;
  if not found then raise exception 'החשבונית לא נמצאה'; end if;

  v_issue := case when p ? 'issue_date' then app.invoice_date(p -> 'issue_date') else v_inv.issue_date end;

  if p ? 'doc_type' and (p ->> 'doc_type') not in
     ('tax_invoice', 'tax_invoice_receipt', 'receipt', 'credit', 'other') then
    raise exception 'סוג מסמך לא מוכר';
  end if;
  if p ? 'category' and (p ->> 'category') not in (
     'subcontractors', 'equipment', 'vehicle', 'fuel', 'rent', 'utilities', 'communication',
     'software', 'office', 'food', 'professional', 'marketing', 'insurance', 'travel',
     'maintenance', 'other') then
    raise exception 'סוג הוצאה לא מוכר';
  end if;

  update invoices set
    doc_type          = coalesce(case when p ? 'doc_type' then p ->> 'doc_type' end, doc_type),
    vendor_name       = case when p ? 'vendor_name' then app.invoice_text(p -> 'vendor_name', 200) else vendor_name end,
    vendor_tax_id     = case when p ? 'vendor_tax_id' then left(app.invoice_digits(p ->> 'vendor_tax_id'), 12) else vendor_tax_id end,
    invoice_number    = case when p ? 'invoice_number' then app.invoice_text(p -> 'invoice_number', 60) else invoice_number end,
    issue_date        = v_issue,
    period            = case
                          when p ? 'period' and app.invoice_date(p -> 'period') is not null
                            then date_trunc('month', app.invoice_date(p -> 'period'))::date
                          when p ? 'issue_date' and v_issue is not null
                            then date_trunc('month', v_issue)::date
                          else period end,
    currency          = case when p ? 'currency' and upper(p ->> 'currency') ~ '^[A-Z]{3}$'
                          then upper(p ->> 'currency') else currency end,
    amount_before_vat = case when p ? 'amount_before_vat' then app.payslip_num(p -> 'amount_before_vat') else amount_before_vat end,
    vat_amount        = case when p ? 'vat_amount' then app.payslip_num(p -> 'vat_amount') else vat_amount end,
    total_amount      = case when p ? 'total_amount' then app.payslip_num(p -> 'total_amount') else total_amount end,
    category          = coalesce(case when p ? 'category' then p ->> 'category' end, category),
    description       = case when p ? 'description' then app.invoice_text(p -> 'description', 300) else description end,
    company_id        = case when p ? 'company_id' then
                          (select c.id from invoice_companies c
                            where c.id = nullif(p ->> 'company_id', '')::uuid and c.deleted_at is null)
                          else company_id end,
    notes             = case when p ? 'notes' then app.invoice_text(p -> 'notes', 1000) else notes end,
    reviewed_at       = case when coalesce((p ->> 'reviewed')::boolean, true) then now() else null end,
    reviewed_by       = case when coalesce((p ->> 'reviewed')::boolean, true) then app.profile_id() else null end
  where id = p_id;

  if p ? 'lines' and jsonb_typeof(p -> 'lines') = 'array' then
    update invoice_lines set deleted_at = now() where invoice_id = p_id and deleted_at is null;
    for v_line in select value from jsonb_array_elements(p -> 'lines') loop
      continue when app.invoice_text(v_line -> 'description', 300) is null;
      v_n := v_n + 1;
      exit when v_n > 200;
      insert into invoice_lines (invoice_id, line_no, description, quantity, unit_price, total)
      values (p_id, v_n, app.invoice_text(v_line -> 'description', 300),
              app.payslip_num(v_line -> 'quantity'), app.payslip_num(v_line -> 'unit_price'),
              app.payslip_num(v_line -> 'total'));
    end loop;
  end if;
end $$;

create or replace function invoice_remove(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform app.require_invoices();
  update invoices set deleted_at = now(), deleted_by = app.profile_id()
   where id = p_id and deleted_at is null;
  if not found then raise exception 'החשבונית לא נמצאה'; end if;
end $$;

-- חשבונית שהקריאה שלה נכשלה, או שרוצים לקרוא מחדש: חוזרת ל"ממתינה".
create or replace function invoice_mark_pending(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform app.require_invoices();
  update invoices set read_status = 'pending', read_error = null
   where id = p_id and deleted_at is null;
end $$;

create or replace function invoice_company_save(p_id uuid, p jsonb)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_id      uuid;
  v_name    text := app.invoice_text(p -> 'name', 200);
  v_tax     text := app.invoice_digits(p ->> 'tax_id');
  v_aliases text[];
begin
  perform app.require_invoices();
  if v_name is null then raise exception 'יש להזין שם חברה'; end if;
  if v_tax is not null and v_tax !~ '^[0-9]{5,12}$' then raise exception 'ח.פ. לא תקין'; end if;
  select coalesce(array_agg(a) filter (where a is not null), '{}') into v_aliases
    from (select app.invoice_text(e, 200) a
            from jsonb_array_elements(case when jsonb_typeof(p -> 'aliases') = 'array'
                                           then p -> 'aliases' else '[]'::jsonb end) e) s;
  if p_id is null then
    insert into invoice_companies (name, tax_id, aliases, active, created_by)
    values (v_name, v_tax, v_aliases, coalesce((p ->> 'active')::boolean, true), app.profile_id())
    returning id into v_id;
  else
    update invoice_companies
       set name = v_name, tax_id = v_tax, aliases = v_aliases,
           active = coalesce((p ->> 'active')::boolean, active)
     where id = p_id and deleted_at is null
    returning id into v_id;
    if v_id is null then raise exception 'החברה לא נמצאה'; end if;
  end if;
  return v_id;
end $$;

create or replace function invoice_company_remove(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform app.require_invoices();
  update invoice_companies set deleted_at = now() where id = p_id and deleted_at is null;
end $$;

-- ===== 6. מה שהמסך קורא ====================================================

create or replace function app.invoice_json(i invoices)
returns jsonb language sql stable security definer set search_path = public as $$
  select to_jsonb(i) - 'raw_reading' - 'file_sha256' - 'deleted_at' - 'deleted_by'
    || jsonb_build_object(
         'company_name', (select c.name from invoice_companies c where c.id = i.company_id),
         'duplicate', exists (
            select 1 from invoices o
             where o.id <> i.id and o.deleted_at is null
               and i.vendor_tax_id is not null and i.invoice_number is not null
               and o.vendor_tax_id = i.vendor_tax_id and o.invoice_number = i.invoice_number
               and o.doc_type = i.doc_type),
         'lines', coalesce((
            select jsonb_agg(jsonb_build_object('line_no', l.line_no, 'description', l.description,
                     'quantity', l.quantity, 'unit_price', l.unit_price, 'total', l.total)
                     order by l.line_no)
              from invoice_lines l where l.invoice_id = i.id and l.deleted_at is null), '[]'::jsonb))
$$;

revoke execute on function app.invoice_json(invoices) from anon, authenticated, public;

-- החודש (התיקייה): החשבוניות, הסיכום, הפילוח, ורשימת התיקיות.
create or replace function invoices_board(p_period date)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_period date := date_trunc('month', coalesce(p_period, now()))::date;
begin
  perform app.require_invoices();
  return jsonb_build_object(
    'period', v_period,
    'invoices', coalesce((
      select jsonb_agg(app.invoice_json(i) order by i.issue_date desc nulls last, i.created_at desc)
        from invoices i where i.deleted_at is null and i.period = v_period), '[]'::jsonb),
    'totals', (
      select jsonb_build_object(
        'count', count(*),
        'before_vat', coalesce(sum(amount_before_vat) filter (where currency = 'ILS'), 0),
        'vat', coalesce(sum(vat_amount) filter (where currency = 'ILS'), 0),
        'total', coalesce(sum(total_amount) filter (where currency = 'ILS'), 0),
        'foreign', count(*) filter (where currency <> 'ILS'),
        'unread', count(*) filter (where read_status <> 'done' and reviewed_at is null),
        'unreviewed', count(*) filter (where reviewed_at is null),
        'missing_total', count(*) filter (where total_amount is null))
        from invoices where deleted_at is null and period = v_period),
    'categories', coalesce((
      select jsonb_agg(c order by c.total desc)
        from (select category, count(*) as count,
                     coalesce(sum(total_amount), 0) as total, coalesce(sum(vat_amount), 0) as vat
                from invoices
               where deleted_at is null and period = v_period and currency = 'ILS'
               group by category) c), '[]'::jsonb),
    'months', coalesce((
      select jsonb_agg(m order by m.period desc)
        from (select period, count(*) as count,
                     coalesce(sum(total_amount) filter (where currency = 'ILS'), 0) as total,
                     coalesce(sum(vat_amount) filter (where currency = 'ILS'), 0) as vat,
                     count(*) filter (where reviewed_at is null) as unreviewed
                from invoices where deleted_at is null
               group by period order by period desc limit 36) m), '[]'::jsonb));
end $$;

create or replace function invoice_gmail_status()
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  perform app.require_invoices();
  return jsonb_build_object(
    'accounts', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', a.id, 'email', a.email, 'active', a.active, 'query_extra', a.query_extra,
               'connected_at', a.connected_at, 'synced_until', a.synced_until,
               'last_run_at', a.last_run_at, 'last_error', a.last_error,
               'connected', a.refresh_token is not null,
               'messages', (select count(*) from invoice_gmail_messages m where m.account_id = a.id),
               'imported', (select count(*) from invoices i
                             where i.gmail_account_id = a.id and i.deleted_at is null))
             order by a.connected_at)
        from invoice_gmail_accounts a where a.deleted_at is null), '[]'::jsonb),
    'companies', (select count(*) from invoice_companies where deleted_at is null and active));
end $$;

create or replace function invoice_gmail_settings_save(p_id uuid, p_query_extra text, p_active boolean)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform app.require_invoices();
  update invoice_gmail_accounts
     set query_extra = left(btrim(coalesce(p_query_extra, '')), 300),
         active = coalesce(p_active, active)
   where id = p_id and deleted_at is null;
  if not found then raise exception 'החשבון לא נמצא'; end if;
end $$;

-- ניתוק: הטוקן נמחק מיד. (ההרשאה אצל Google מבוטלת ב-myaccount.google.com.)
create or replace function invoice_gmail_disconnect(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform app.require_invoices();
  update invoice_gmail_accounts set refresh_token = null, active = false, deleted_at = now()
   where id = p_id and deleted_at is null;
end $$;

-- ===== 7. מה שרק פונקציות הקצה כותבות (service_role) =======================

-- מה שנקרא מהחשבונית. חשבונית שאושרה ביד אינה נדרסת — רק raw_reading מתעדכן.
create or replace function invoice_store_reading(p_id uuid, p_reading jsonb, p_model text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_inv   invoices;
  v_issue date := app.invoice_date(p_reading -> 'issue_date');
  v_line  jsonb;
  v_n     int := 0;
begin
  select * into v_inv from invoices where id = p_id and deleted_at is null for update;
  if not found then raise exception 'החשבונית לא נמצאה'; end if;

  if v_inv.reviewed_at is not null then
    update invoices set raw_reading = p_reading, read_model = p_model, read_at = now(),
                        read_status = 'done', read_error = null
     where id = p_id;
    return jsonb_build_object('applied', false);
  end if;

  update invoices set
    raw_reading       = p_reading,
    read_model        = p_model,
    read_at           = now(),
    read_status       = 'done',
    read_error        = null,
    doc_type          = case when (p_reading ->> 'doc_type') in
                          ('tax_invoice', 'tax_invoice_receipt', 'receipt', 'credit', 'other')
                          then p_reading ->> 'doc_type' else 'other' end,
    vendor_name       = app.invoice_text(p_reading -> 'vendor_name', 200),
    vendor_tax_id     = left(app.invoice_digits(p_reading ->> 'vendor_tax_id'), 12),
    invoice_number    = app.invoice_text(p_reading -> 'invoice_number', 60),
    issue_date        = v_issue,
    period            = coalesce(date_trunc('month', v_issue)::date, period),
    currency          = case when upper(coalesce(p_reading ->> 'currency', '')) ~ '^[A-Z]{3}$'
                          then upper(p_reading ->> 'currency') else 'ILS' end,
    amount_before_vat = app.payslip_num(p_reading -> 'amount_before_vat'),
    vat_amount        = app.payslip_num(p_reading -> 'vat_amount'),
    total_amount      = app.payslip_num(p_reading -> 'total_amount'),
    category          = case when (p_reading ->> 'category') in (
                          'subcontractors', 'equipment', 'vehicle', 'fuel', 'rent', 'utilities',
                          'communication', 'software', 'office', 'food', 'professional',
                          'marketing', 'insurance', 'travel', 'maintenance', 'other')
                          then p_reading ->> 'category' else 'other' end,
    description       = app.invoice_text(p_reading -> 'description', 300),
    recipient_name    = app.invoice_text(p_reading -> 'recipient_name', 200),
    recipient_tax_id  = left(app.invoice_digits(p_reading ->> 'recipient_tax_id'), 12),
    company_id        = coalesce(company_id, app.invoice_company_for(
                          p_reading ->> 'recipient_name', p_reading ->> 'recipient_tax_id'))
  where id = p_id;

  update invoice_lines set deleted_at = now() where invoice_id = p_id and deleted_at is null;
  if jsonb_typeof(p_reading -> 'lines') = 'array' then
    for v_line in select value from jsonb_array_elements(p_reading -> 'lines') loop
      continue when app.invoice_text(v_line -> 'description', 300) is null;
      v_n := v_n + 1;
      exit when v_n > 200;
      insert into invoice_lines (invoice_id, line_no, description, quantity, unit_price, total)
      values (p_id, v_n, app.invoice_text(v_line -> 'description', 300),
              app.payslip_num(v_line -> 'quantity'), app.payslip_num(v_line -> 'unit_price'),
              app.payslip_num(v_line -> 'total'));
    end loop;
  end if;
  return jsonb_build_object('applied', true);
end $$;

create or replace function invoice_read_failed(p_id uuid, p_error text)
returns void language sql security definer set search_path = public as $$
  update invoices set read_status = 'failed', read_error = left(p_error, 300), read_at = now()
   where id = p_id and deleted_at is null and reviewed_at is null
$$;

-- החברה שהחשבונית יצאה עבורה, לפי מה שנקרא (Gmail מחליט לפיה אם לשמור).
create or replace function invoice_company_match(p_name text, p_tax_id text)
returns uuid language sql stable security definer set search_path = public as $$
  select app.invoice_company_for(p_name, p_tax_id)
$$;

-- חשבונית מ-Gmail: השורה נוצרת עם הקריאה, אחרי שהקובץ כבר עלה ל-<p_id>.pdf.
-- null — אותו קובץ כבר קיים (והפונקציה מוחקת את מה שהעלתה).
create or replace function invoice_gmail_import(
  p_id uuid, p_account_id uuid, p_message jsonb, p_file_name text, p_sha256 text, p_reading jsonb, p_model text)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_id uuid := p_id;
begin
  if exists (select 1 from invoices where file_sha256 = p_sha256 and deleted_at is null) then
    return null;
  end if;
  insert into invoices (id, source, file_name, file_path, file_sha256, period,
                        gmail_account_id, gmail_message_id, gmail_from, gmail_subject, gmail_date)
  values (v_id, 'gmail', left(coalesce(nullif(btrim(p_file_name), ''), 'חשבונית.pdf'), 300),
          'invoices/' || v_id || '.pdf', p_sha256,
          date_trunc('month', coalesce((p_message ->> 'date')::timestamptz, now()) at time zone 'Asia/Jerusalem')::date,
          p_account_id, p_message ->> 'id', left(p_message ->> 'from', 300),
          left(p_message ->> 'subject', 300), (p_message ->> 'date')::timestamptz);
  perform invoice_store_reading(v_id, p_reading, p_model);
  return v_id;
end $$;

create or replace function invoice_gmail_connect(p_profile_id uuid, p_email text, p_refresh_token text)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_id uuid;
begin
  if not exists (select 1 from profiles where id = p_profile_id and is_admin and deleted_at is null) then
    raise exception 'רק מנהל מערכת מחבר Gmail';
  end if;
  if coalesce(p_refresh_token, '') = '' or coalesce(p_email, '') !~ '@' then
    raise exception 'החיבור לא הושלם';
  end if;
  update invoice_gmail_accounts
     set refresh_token = p_refresh_token, active = true, connected_by = p_profile_id,
         connected_at = now(), last_error = null
   where lower(email) = lower(p_email) and deleted_at is null
  returning id into v_id;
  if v_id is null then
    insert into invoice_gmail_accounts (email, refresh_token, connected_by)
    values (lower(p_email), p_refresh_token, p_profile_id)
    returning id into v_id;
  end if;
  return v_id;
end $$;

-- מה שהסריקה צריכה: החשבונות הפעילים, עם הטוקן. service_role בלבד.
create or replace function invoice_gmail_accounts_due(p_id uuid)
returns table (id uuid, email text, refresh_token text, query_extra text, synced_until timestamptz)
language sql stable security definer set search_path = public as $$
  select a.id, a.email, a.refresh_token, a.query_extra, a.synced_until
    from invoice_gmail_accounts a
   where a.deleted_at is null and a.active and a.refresh_token is not null
     and (p_id is null or a.id = p_id)
$$;

create or replace function invoice_gmail_seen(p_account_id uuid, p_message_ids text[])
returns text[] language sql stable security definer set search_path = public as $$
  select coalesce(array_agg(message_id), '{}') from invoice_gmail_messages
   where account_id = p_account_id and message_id = any(p_message_ids)
$$;

create or replace function invoice_gmail_mark(
  p_account_id uuid, p_message_id text, p_imported int, p_skipped int, p_note text)
returns void language sql security definer set search_path = public as $$
  insert into invoice_gmail_messages (account_id, message_id, imported, skipped, note)
  values (p_account_id, p_message_id, coalesce(p_imported, 0), coalesce(p_skipped, 0), left(p_note, 300))
  on conflict (account_id, message_id) do update
    set imported = excluded.imported, skipped = excluded.skipped, note = excluded.note,
        processed_at = now()
$$;

-- סוף ריצה: synced_until מתקדם רק כשהחיפוש מוצה (p_synced_until לא null).
create or replace function invoice_gmail_run_done(p_account_id uuid, p_synced_until timestamptz, p_error text)
returns void language sql security definer set search_path = public as $$
  update invoice_gmail_accounts
     set last_run_at = now(),
         last_error = left(p_error, 300),
         synced_until = coalesce(p_synced_until, synced_until)
   where id = p_account_id
$$;

-- ===== 8. הרשאות הרצה ======================================================

revoke execute on function invoice_create(text, text, text) from anon, public;
revoke execute on function invoice_save(uuid, jsonb) from anon, public;
revoke execute on function invoice_remove(uuid) from anon, public;
revoke execute on function invoice_mark_pending(uuid) from anon, public;
revoke execute on function invoice_company_save(uuid, jsonb) from anon, public;
revoke execute on function invoice_company_remove(uuid) from anon, public;
revoke execute on function invoices_board(date) from anon, public;
revoke execute on function invoice_gmail_status() from anon, public;
revoke execute on function invoice_gmail_settings_save(uuid, text, boolean) from anon, public;
revoke execute on function invoice_gmail_disconnect(uuid) from anon, public;
grant  execute on function invoice_create(text, text, text) to authenticated;
grant  execute on function invoice_save(uuid, jsonb) to authenticated;
grant  execute on function invoice_remove(uuid) to authenticated;
grant  execute on function invoice_mark_pending(uuid) to authenticated;
grant  execute on function invoice_company_save(uuid, jsonb) to authenticated;
grant  execute on function invoice_company_remove(uuid) to authenticated;
grant  execute on function invoices_board(date) to authenticated;
grant  execute on function invoice_gmail_status() to authenticated;
grant  execute on function invoice_gmail_settings_save(uuid, text, boolean) to authenticated;
grant  execute on function invoice_gmail_disconnect(uuid) to authenticated;

-- service_role בלבד
revoke execute on function invoice_store_reading(uuid, jsonb, text) from anon, authenticated, public;
revoke execute on function invoice_read_failed(uuid, text) from anon, authenticated, public;
revoke execute on function invoice_company_match(text, text) from anon, authenticated, public;
revoke execute on function invoice_gmail_import(uuid, uuid, jsonb, text, text, jsonb, text) from anon, authenticated, public;
revoke execute on function invoice_gmail_connect(uuid, text, text) from anon, authenticated, public;
revoke execute on function invoice_gmail_accounts_due(uuid) from anon, authenticated, public;
revoke execute on function invoice_gmail_seen(uuid, text[]) from anon, authenticated, public;
revoke execute on function invoice_gmail_mark(uuid, text, int, int, text) from anon, authenticated, public;
revoke execute on function invoice_gmail_run_done(uuid, timestamptz, text) from anon, authenticated, public;
grant  execute on function invoice_store_reading(uuid, jsonb, text) to service_role;
grant  execute on function invoice_read_failed(uuid, text) to service_role;
grant  execute on function invoice_company_match(text, text) to service_role;
grant  execute on function invoice_gmail_import(uuid, uuid, jsonb, text, text, jsonb, text) to service_role;
grant  execute on function invoice_gmail_connect(uuid, text, text) to service_role;
grant  execute on function invoice_gmail_accounts_due(uuid) to service_role;
grant  execute on function invoice_gmail_seen(uuid, text[]) to service_role;
grant  execute on function invoice_gmail_mark(uuid, text, int, int, text) to service_role;
grant  execute on function invoice_gmail_run_done(uuid, timestamptz, text) to service_role;

-- ===== 9. הסריקה האוטומטית של Gmail ========================================

create or replace function app.invoice_gmail_kick()
returns void language plpgsql security definer set search_path = public as $$
declare
  v_url    text := nullif(current_setting('app.invoice_gmail_url', true), '');
  v_secret text := nullif(current_setting('app.invoice_gmail_secret', true), '');
begin
  if v_url is null or v_secret is null then return; end if;
  if to_regproc('net.http_post') is null then return; end if;
  if not exists (select 1 from invoice_gmail_accounts
                  where deleted_at is null and active and refresh_token is not null) then
    return;
  end if;
  execute 'select net.http_post(url := $1, headers := $2, body := $3)'
  using v_url,
        jsonb_build_object('Content-Type', 'application/json', 'x-sync-secret', v_secret),
        jsonb_build_object('action', 'sync');
exception when others then
  raise notice 'invoice gmail kick failed: %', sqlerrm;
end $$;

revoke execute on function app.invoice_gmail_kick() from anon, authenticated, public;

do $$
begin
  create extension if not exists pg_cron;
  perform cron.schedule('invoice-gmail-sync', '23 */3 * * *', 'select app.invoice_gmail_kick()');
exception when others then
  raise warning '0233: pg_cron אינו זמין (%) — הסריקה האוטומטית של Gmail לא תוזמנה. בפרויקט: cron.schedule(''invoice-gmail-sync'', ''23 */3 * * *'', ''select app.invoice_gmail_kick()'').', sqlerrm;
end $$;
