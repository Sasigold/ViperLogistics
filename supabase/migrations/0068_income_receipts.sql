-- 0068: הכנסות לפי קטגוריה, חלוקת הכנסות ללקוח, תקבולים ועלות מעביד
--
-- המערכת הישנה של הבעלים ידעה שלושה דברים שלמערכת הזו אין: הכנסה שאינה נובעת
-- מתמחור משימה (ריהוט ישן/חדש שנמכר דרך אירוע), חלוקה של אותה הכנסה בין ויפר
-- ללקוח לפי אחוז מוסכם, ומעקב אחרי מה שהלקוח כבר העביר בפועל. הקובץ הזה מוסיף
-- את שלושתם, והסקשנים שמציגים אותם בדשבורד יושבים ב-0069.
--
-- ארבע החלטות:
--
--   1. **קטלוג הקטגוריות הוא נתונים, לא קוד.** במערכת הישנה הופיעו "הובלות"
--      ו"לוגיסטיקה" זו לצד זו — הרשימה אינה קבועה בשלוש. עמודת family
--      ('furniture'/'logistics') היא שמקבעת את שני ה-KPI המסכמים, כך שהוספת
--      קטגוריה אינה דורשת מיגרציה ואינה שוברת את הכרטיסים.
--   2. **הסכומים יושבים על האירוע** (טבלת-בת, שורה לקטגוריה) — כך אמר הבעלים
--      במפורש: שדות על האירוע, רק ללקוח שהופעלו לו קטגוריות. הכנסות "צוות"
--      נשארות ב-task_pricing כמו היום.
--   3. **האחוז נשמר על השורה בעת הכתיבה** (snapshot). שינוי עתידי של החלוקה
--      בכרטיס הלקוח משנה אירועים שייערכו מכאן והלאה, לא את ההיסטוריה — כך
--      "הכנסות ללקוח" של חודש שעבר נשאר המספר שסוכם אז.
--   4. **תקבול הוא שורת יומן**, לא דגל על אירוע: הלקוח מעביר סכומים על החשבון
--      השוטף, לא תשלום-לאירוע. "שולם" = סך התקבולים בטווח; "לא שולם" = החוב
--      פחות מה ששולם.

-- ===== 1. הרשאות ===========================================================
-- מודול חדש. implied_by נבחר כך שאיש אינו מקבל או מאבד יכולת ביום הפריסה:
-- מי שרואה הכנסות היום (pricing.revenue) רואה גם הכנסות קטגוריה, ומי שמחזיק
-- dashboard.financial רואה תקבולים. receipts_manage הוא היחיד שדורש הענקה
-- מפורשת — רישום כסף שנכנס אינו נגרר אחרי שום מפתח קיים.

select app.register_module('finance', 'הכנסות ותקבולים',
  'הכנסות לפי קטגוריה, חלוקת הכנסות ללקוח ורישום תקבולים', 'Banknote', 78);

select app.register_permission('finance.income_view', 'finance', 'הכנסות לפי קטגוריה',
  'סכומי ההכנסה שהוזנו על אירועים — בדשבורד ובאירוע', 'field', false, true,
  array['staff']::user_kind[], 'pricing.revenue', 10);

select app.register_permission('finance.income_edit', 'finance', 'הזנת הכנסות על אירוע',
  'מילוי ועדכון סכומי הקטגוריות בטופס האירוע', 'action', false, true,
  array['staff']::user_kind[], 'pricing.edit', 20);

select app.register_permission('finance.manage_splits', 'finance', 'ניהול חלוקת הכנסות',
  'קביעת אחוז ויפר מול הלקוח לכל קטגוריה, בכרטיס הלקוח', 'action', false, true,
  array['staff']::user_kind[], 'pricing.manage_rules', 30);

select app.register_permission('finance.receipts_view', 'finance', 'צפייה בתקבולים',
  'רישום התקבולים מהלקוחות, וכרטיסי שולם/לא שולם בדשבורד', 'field', false, true,
  array['staff']::user_kind[], 'dashboard.financial', 40);

select app.register_permission('finance.receipts_manage', 'finance', 'ניהול תקבולים',
  'הוספה, עריכה ומחיקה של תקבולים', 'action', false, true,
  array['staff']::user_kind[], null, 50);

-- ===== 2. קטלוג הקטגוריות ==================================================

create table income_categories (
  id         uuid primary key default gen_random_uuid(),
  name       text not null,
  family     text not null default 'logistics' check (family in ('furniture', 'logistics')),
  color      text not null default '#3563f0',
  sort_order int  not null default 100,
  is_active  boolean not null default true,
  deleted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create trigger income_categories_updated before update on income_categories
  for each row execute function app.set_updated_at();

insert into income_categories (name, family, color, sort_order) values
  ('ריהוט ישן', 'furniture', '#6366f1', 10),
  ('ריהוט חדש', 'furniture', '#8b5cf6', 20),
  ('לוגיסטיקה', 'logistics', '#14b8a6', 30),
  ('הובלות',    'logistics', '#f59e0b', 40);

-- ===== 3. חלוקת הכנסות פר לקוח =============================================
-- קיום שורה = הקטגוריה מופעלת ללקוח, וזה מה שמדליק את השדות בטופס האירוע.
-- נשמר רק חלקה של ויפר; חלק הלקוח נגזר (100 פחות) — מספר אחד אינו יכול
-- לסתור את עצמו.

create table customer_income_splits (
  customer_id     uuid not null references customers(id) on delete cascade,
  category_id     uuid not null references income_categories(id) on delete cascade,
  viper_share_pct numeric(5,2) not null default 100
                  check (viper_share_pct >= 0 and viper_share_pct <= 100),
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  primary key (customer_id, category_id)
);
create trigger customer_income_splits_updated before update on customer_income_splits
  for each row execute function app.set_updated_at();

-- ===== 4. הסכומים על האירוע ================================================
-- viper_share_pct הוא ה-snapshot: נלקח מחלוקת הלקוח בכל כתיבה של השורה.

create table event_income (
  event_id        uuid not null references events(id) on delete cascade,
  category_id     uuid not null references income_categories(id),
  amount          numeric(12,2) not null check (amount >= 0),
  viper_share_pct numeric(5,2) not null default 100
                  check (viper_share_pct >= 0 and viper_share_pct <= 100),
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  primary key (event_id, category_id)
);
create index event_income_category_idx on event_income (category_id);
create trigger event_income_updated before update on event_income
  for each row execute function app.set_updated_at();

-- ===== 5. תקבולים ==========================================================

create table receipts (
  id          uuid primary key default gen_random_uuid(),
  customer_id uuid not null references customers(id),
  -- שלילי מותר במכוון: זיכוי או החזר ללקוח הוא תקבול שלילי. אפס אינו רישום.
  amount      numeric(12,2) not null check (amount <> 0),
  received_at date not null default current_date,
  note        text,
  created_by  uuid references profiles(id),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  deleted_at  timestamptz
);
create index receipts_date_live_idx on receipts (received_at) where deleted_at is null;
create index receipts_customer_idx on receipts (customer_id, received_at) where deleted_at is null;
create trigger receipts_updated before update on receipts
  for each row execute function app.set_updated_at();

-- ===== 6. RLS ==============================================================
-- אין ענף customer_user או contractor_user באף פוליסה — אותה עמדה כמו תמחור
-- (0017): הכסף בין ויפר ללקוחות הוא עניין פנימי של הצוות.

alter table income_categories enable row level security;
alter table customer_income_splits enable row level security;
alter table event_income enable row level security;
alter table receipts enable row level security;

-- הקטלוג נקרא מארבעה מסכים — הגדרות, כרטיס לקוח, טופס אירוע ודשבורד — ולכן
-- השער הוא איחוד המפתחות שלהם. customers.view אינו כאן במכוון: הוא מפתח
-- ברירת מחדל של כל איש צוות, והקטלוג (והחלוקות שמצביעות עליו) הם מידע כספי.
create policy income_categories_read on income_categories for select to authenticated using (
  (select app.is_admin())
  or ((select app.user_kind()) = 'staff'
      and ((select app.has('finance.income_view'))
           or (select app.has('finance.income_edit'))
           or (select app.has('finance.manage_splits'))
           or (select app.has('settings.edit')))));
create policy income_categories_write on income_categories for all to authenticated
  using ((select app.is_admin()) or (select app.has('settings.edit')))
  with check ((select app.is_admin()) or (select app.has('settings.edit')));

-- טופס האירוע חייב לדעת אילו שדות להציג גם אצל מי שמזין אך אינו מנהל חלוקה,
-- ולכן הקריאה רחבה מהכתיבה — אך לא רחבה מהמפתחות הכספיים: האחוזים עצמם הם
-- תנאי מסחריים.
create policy cis_select on customer_income_splits for select to authenticated using (
  (select app.is_admin())
  or ((select app.user_kind()) = 'staff'
      and ((select app.has('finance.income_view'))
           or (select app.has('finance.income_edit'))
           or (select app.has('finance.manage_splits')))));
create policy cis_write on customer_income_splits for all to authenticated
  using ((select app.is_admin()) or (select app.has('finance.manage_splits')))
  with check ((select app.is_admin()) or (select app.has('finance.manage_splits')));

-- אין פוליסת כתיבה במכוון: הסכומים נכתבים אך ורק דרך create_event/update_event
-- (security definer), כמו task_pricing שנכתב רק דרך מנוע התמחור.
create policy event_income_read on event_income for select to authenticated using (
  (select app.is_admin())
  or ((select app.user_kind()) = 'staff'
      and ((select app.has('finance.income_view'))
           or (select app.has('finance.income_edit')))));

create policy receipts_read on receipts for select to authenticated using (
  ((select app.is_admin()) or deleted_at is null)
  and ((select app.is_admin())
       or ((select app.user_kind()) = 'staff'
           and (select app.has('finance.receipts_view')))));
create policy receipts_insert on receipts for insert to authenticated
  with check ((select app.is_admin()) or (select app.has('finance.receipts_manage')));
-- מחיקה = מחיקה רכה דרך update, ולכן אין פוליסת delete בכלל.
create policy receipts_update on receipts for update to authenticated
  using ((select app.is_admin()) or (select app.has('finance.receipts_manage')))
  with check ((select app.is_admin()) or (select app.has('finance.receipts_manage')));

-- ===== 7. עלות מעביד =======================================================
-- אחוז גלובלי אחד. app_settings פתוחה לקריאה לכל משתמש מאומת (0005) — אחוז
-- עלות המעביד, כמו סולם השעות הנוספות שכבר יושב שם, אינו חושף שכר של איש.
-- פוליסת הכתיבה מ-0046 כבר מתירה settings.edit לכל מפתח שאינו attendance/notifications.

insert into app_settings (key, value)
values ('finance.employer_cost', jsonb_build_object('pct', 30))
on conflict (key) do nothing;

-- ===== 8. הזרמת הסכומים דרך צינור האירוע ===================================
--
-- payload.event_income = אובייקט { "<category_uuid>": "1234.50" | null }.
-- אותה סמנטיקת patch של 0053: מפתח שאינו ב-payload אינו נגרר; ערך ריק/null
-- פירושו "רוקן" — מחיקת השורה.
--
-- מי שאין לו finance.income_edit: המפתח נשמט בשקט והאירוע נשמר — בדיוק כמו
-- app.strip_hidden_event_keys, כדי שטופס ישן/חסר-הרשאה לא יפיל שמירה שלמה.
-- קטגוריה שאינה מופעלת ללקוח היא לעומת זאת שגיאה מדוברת: זה מפרט פגום, לא
-- הפרש הרשאות.

create or replace function app.apply_event_income(p_event_id uuid, p_customer uuid, payload jsonb)
returns void language plpgsql security definer set search_path = public as $$
declare
  r record;
  v_cat uuid;
  v_amount numeric;
  v_pct numeric;
  v_name text;
begin
  if not (payload ? 'event_income') then return; end if;
  if not app.has('finance.income_edit') then return; end if;

  for r in select key, nullif(btrim(coalesce(value, '')), '') as raw
             from jsonb_each_text(coalesce(payload -> 'event_income', '{}'::jsonb))
  loop
    begin
      v_cat := r.key::uuid;
    exception when others then
      raise exception 'קטגוריית הכנסה לא מוכרת: %', r.key;
    end;
    select name into v_name from income_categories where id = v_cat;

    if r.raw is null then
      delete from event_income
       where event_id = p_event_id and category_id = v_cat;
      continue;
    end if;

    begin
      v_amount := r.raw::numeric;
    exception when others then
      raise exception 'ערך לא תקין בשדה "%": %', coalesce(v_name, r.key), r.raw;
    end;
    if v_amount < 0 then
      raise exception 'סכום שלילי אינו חוקי בשדה "%"', coalesce(v_name, r.key);
    end if;

    -- ה-snapshot: האחוז הנוכחי של הלקוח, ברגע הכתיבה. קטגוריה בלי שורת חלוקה
    -- אינה מופעלת ללקוח הזה — והזנה אליה היא טעות שצריך לשמוע עליה.
    select s.viper_share_pct into v_pct
      from customer_income_splits s
      join income_categories ic on ic.id = s.category_id
     where s.customer_id = p_customer and s.category_id = v_cat
       and ic.deleted_at is null;
    if v_pct is null then
      raise exception 'הקטגוריה "%" אינה מופעלת ללקוח של האירוע',
        coalesce(v_name, r.key);
    end if;

    insert into event_income (event_id, category_id, amount, viper_share_pct)
    values (p_event_id, v_cat, v_amount, v_pct)
    on conflict (event_id, category_id) do update set
      amount = excluded.amount,
      viper_share_pct = excluded.viper_share_pct;
  end loop;
end $$;

revoke execute on function app.apply_event_income(uuid, uuid, jsonb) from anon, authenticated, public;

-- ===== 9. create_event / update_event ======================================
-- גוף זהה ל-0053 מילה במילה, בתוספת קריאה אחת ל-app.apply_event_income.
-- duplicate_event אינו משתנה במכוון: סכומי הכנסה הם נתוני-אמת של אירוע מסוים,
-- לא תבנית — אירוע משוכפל מתחיל בלי הכנסות.

create or replace function create_event(payload jsonb)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_customer_id uuid;
  v_profile_id uuid;
  v_event_id uuid;
  v_status uuid;
  r record;
begin
  v_profile_id := app.profile_id();

  if (select app.user_kind()) = 'customer_user' then
    v_customer_id := app.customer_id();
    if not app.has('events.create')
       or not exists (select 1 from customers c where c.id = v_customer_id
                      and c.can_create_events and c.deleted_at is null) then
      raise exception 'אין לך הרשאה ליצור אירועים' using errcode = '42501';
    end if;
    payload := app.strip_hidden_event_keys(v_profile_id, payload);
  elsif app.is_admin() or app.has('events.create') then
    v_customer_id := (payload ->> 'customer_id')::uuid;
    if v_customer_id is null then raise exception 'חובה לבחור לקוח'; end if;
    v_profile_id := null;
  else
    raise exception 'אין לך הרשאה ליצור אירועים' using errcode = '42501';
  end if;

  perform app.validate_event_payload(v_customer_id, v_profile_id, payload, false);

  if payload ->> 'event_date' is null then
    raise exception 'שדות חובה חסרים: תאריך אירוע';
  end if;

  v_status := coalesce((payload ->> 'status_id')::uuid,
    (select id from statuses where entity = 'event' and is_default and deleted_at is null limit 1));

  insert into events (customer_id, end_client_name, event_number, event_date,
    location_text, location_provider, location_place_id, location_lat, location_lng,
    location_notes, volume_m, truck_count, notes, status_id,
    no_parking, porterage, supplier_pickup, custom_fields, created_by)
  values (v_customer_id,
    nullif(payload ->> 'end_client_name',''),
    nullif(payload ->> 'event_number',''),
    (payload ->> 'event_date')::date,
    nullif(payload ->> 'location_text',''),
    nullif(payload ->> 'location_provider',''),
    nullif(payload ->> 'location_place_id',''),
    (payload ->> 'location_lat')::double precision,
    (payload ->> 'location_lng')::double precision,
    nullif(payload ->> 'location_notes',''),
    (nullif(payload ->> 'volume_m',''))::numeric,
    (nullif(payload ->> 'truck_count',''))::int,
    nullif(payload ->> 'notes',''),
    v_status,
    coalesce((payload ->> 'no_parking')::boolean, false),
    coalesce((payload ->> 'porterage')::boolean, false),
    coalesce((payload ->> 'supplier_pickup')::boolean, false),
    app.event_custom_patch(v_customer_id, payload),
    app.profile_id())
  returning id into v_event_id;

  if nullif(payload ->> 'contact_name','') is not null
     or nullif(payload ->> 'contact_phone','') is not null then
    insert into event_contacts (event_id, contact_name, contact_phone)
    values (v_event_id, nullif(payload ->> 'contact_name',''), nullif(payload ->> 'contact_phone',''));
  end if;

  if payload ? 'supplier_ids' then
    for r in select value::uuid as sid from jsonb_array_elements_text(payload -> 'supplier_ids') loop
      insert into event_suppliers (event_id, supplier_id) values (v_event_id, r.sid)
      on conflict do nothing;
    end loop;
  end if;

  perform app.apply_event_income(v_event_id, v_customer_id, payload);

  perform app.system_write(true);
  perform app.apply_event_task_block(v_event_id, 'setup', payload);
  perform app.apply_event_task_block(v_event_id, 'teardown', payload);
  perform app.system_write(false);

  return v_event_id;
end $$;

create or replace function update_event(p_event_id uuid, payload jsonb)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_customer_id uuid;
  v_profile_id uuid;
begin
  select customer_id into v_customer_id from events
    where id = p_event_id and deleted_at is null;
  if v_customer_id is null then raise exception 'אירוע לא נמצא'; end if;

  if not (app.is_admin()
          or ((select app.user_kind()) = 'staff' and app.has('events.edit'))
          or ((select app.user_kind()) = 'customer_user'
              and v_customer_id = app.customer_id()
              and app.has('events.edit'))) then
    raise exception 'אין לך הרשאה לערוך אירוע זה' using errcode = '42501';
  end if;

  if (select app.user_kind()) = 'customer_user' then
    v_profile_id := app.profile_id();
    payload := app.strip_hidden_event_keys(v_profile_id, payload);
  end if;

  perform app.validate_event_payload(v_customer_id, v_profile_id, payload, true);

  update events set
    end_client_name = case when payload ? 'end_client_name' then nullif(payload ->> 'end_client_name','') else end_client_name end,
    event_number    = case when payload ? 'event_number' then nullif(payload ->> 'event_number','') else event_number end,
    event_date      = case when payload ? 'event_date' then (payload ->> 'event_date')::date else event_date end,
    location_text   = case when payload ? 'location_text' then nullif(payload ->> 'location_text','') else location_text end,
    location_provider = case when payload ? 'location_provider' then nullif(payload ->> 'location_provider','') else location_provider end,
    location_place_id = case when payload ? 'location_place_id' then nullif(payload ->> 'location_place_id','') else location_place_id end,
    location_lat    = case when payload ? 'location_lat' then (payload ->> 'location_lat')::double precision else location_lat end,
    location_lng    = case when payload ? 'location_lng' then (payload ->> 'location_lng')::double precision else location_lng end,
    location_notes  = case when payload ? 'location_notes' then nullif(payload ->> 'location_notes','') else location_notes end,
    volume_m        = case when payload ? 'volume_m' then (nullif(payload ->> 'volume_m',''))::numeric else volume_m end,
    truck_count     = case when payload ? 'truck_count' then (nullif(payload ->> 'truck_count',''))::int else truck_count end,
    notes           = case when payload ? 'notes' then nullif(payload ->> 'notes','') else notes end,
    status_id       = case when payload ? 'status_id' then (payload ->> 'status_id')::uuid else status_id end,
    no_parking      = case when payload ? 'no_parking' then (payload ->> 'no_parking')::boolean else no_parking end,
    porterage       = case when payload ? 'porterage' then (payload ->> 'porterage')::boolean else porterage end,
    supplier_pickup = case when payload ? 'supplier_pickup' then (payload ->> 'supplier_pickup')::boolean else supplier_pickup end,
    -- מיזוג ולא החלפה: app.event_custom_patch מחזירה רק מפתחות שנשלחו
    custom_fields   = custom_fields || app.event_custom_patch(v_customer_id, payload)
  where id = p_event_id;

  if payload ? 'contact_name' or payload ? 'contact_phone' then
    insert into event_contacts (event_id, contact_name, contact_phone)
    values (p_event_id, nullif(payload ->> 'contact_name',''), nullif(payload ->> 'contact_phone',''))
    on conflict (event_id) do update set
      contact_name  = case when payload ? 'contact_name' then nullif(payload ->> 'contact_name','') else event_contacts.contact_name end,
      contact_phone = case when payload ? 'contact_phone' then nullif(payload ->> 'contact_phone','') else event_contacts.contact_phone end;
  end if;

  if payload ? 'supplier_ids' then
    delete from event_suppliers where event_id = p_event_id;
    insert into event_suppliers (event_id, supplier_id)
    select p_event_id, value::uuid from jsonb_array_elements_text(payload -> 'supplier_ids')
    on conflict do nothing;
  end if;

  perform app.apply_event_income(p_event_id, v_customer_id, payload);

  perform app.system_write(true);
  perform app.apply_event_task_block(p_event_id, 'setup', payload);
  perform app.apply_event_task_block(p_event_id, 'teardown', payload);
  perform app.system_write(false);
end $$;
