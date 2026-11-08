-- 0240: קוד הרכב, פרטי הביטוח ורישיון הנהג
--
-- בקשת הבעלים: בכל רכב חלונית לקוד הרכב (הקודן / האימובילייזר) ולפרטי
-- הביטוח — חברה, פוליסה, סוג כיסוי, סוכן, ובעיקר הגיל המינימלי והוותק
-- המינימלי שהפוליסה מתירה לנהג. ובחלונית הנהגים: צילום רישיון הנהיגה של
-- הנהג ותוקפו.
--
-- ההחלטות:
-- * הקוד והביטוח הם עמודות על `vehicles` (0089 §2) ולא טבלה: לרכב פוליסה
--   אחת בכל רגע, והם נערכים באותו טופס ובאותו מפתח (`fleet.edit`) כמו שאר
--   פרטי הרכב. תוקף הפוליסה עצמו נשאר מסמך (`vehicle_documents`) — שם הוא
--   מתריע; עמודת תוקף נוספת כאן הייתה שני תאריכים שיכולים לסתור זה את זה.
-- * הרישיון שייך לנהג ולא לרכב: אותו רישיון משרת כל רכב שהוא מוצמד אליו.
--   לכן טבלה `driver_licenses` לפי פרופיל (שורה חיה אחת לכל נהג), והקובץ
--   בדלי `vehicle-docs` תחת `drivers/<profile_id>/...`. השער
--   `app.may_touch_vehicle_doc` (0089 §8) מכיר עכשיו גם את הנתיב הזה:
--   קריאה = `fleet.docs_view`, כתיבה = `fleet.drivers_manage`. הפוליסות על
--   storage.objects לא משתנות — רק הפונקציה שהן קוראות לה.
-- * תאריך עם שנה שגויה (20255 במקום 2025 — שדה date בדפדפן מקבל עד 6
--   ספרות בשנה) נשמר בפוסטגרס בלי תלונה, ובצד הלקוח `format` של date-fns
--   זרק עליו RangeError והפיל את דף הרכב. מעכשיו המסד מסרב לשנה מחוץ
--   ל-1900..2200 במסמכים וברישיונות (`not valid`: שורה ישנה שגויה אינה
--   חוסמת את ההגירה, ותיקון שלה עובר את הבדיקה), והלקוח מציג תאריך לא תקין
--   כפי שהוא במקום לקרוס.

-- ===== 1. קוד וביטוח על הרכב ================================================

alter table vehicles
  add column if not exists vehicle_code               text,
  add column if not exists insurance_company          text,
  add column if not exists insurance_policy_number    text,
  add column if not exists insurance_coverage         text
    check (insurance_coverage is null
           or insurance_coverage in ('comprehensive', 'third_party', 'mandatory_only')),
  add column if not exists insurance_agent            text,
  add column if not exists insurance_agent_phone      text,
  add column if not exists insurance_min_driver_age   int
    check (insurance_min_driver_age is null or insurance_min_driver_age between 16 and 99),
  add column if not exists insurance_min_license_years int
    check (insurance_min_license_years is null or insurance_min_license_years between 0 and 60),
  add column if not exists insurance_notes            text;

comment on column vehicles.vehicle_code is
  'קוד הרכב (קודן / אימובילייזר). נקרא בידי כל מי שרואה את הרכב (fleet.view), נכתב ב-fleet.edit';
comment on column vehicles.insurance_min_driver_age is
  'הגיל המינימלי של נהג לפי הפוליסה. מושווה בלקוח מול תאריך הלידה ברישיון הנהג';
comment on column vehicles.insurance_min_license_years is
  'הוותק המינימלי (שנים מהוצאת הרישיון הראשון) לפי הפוליסה';

-- ===== 2. תאריכים סבירים במסמכי הרכב =========================================

alter table vehicle_documents
  add constraint vehicle_documents_dates_sane check (
    (issued_at  is null or issued_at  between date '1900-01-01' and date '2200-12-31')
    and (expires_at is null or expires_at between date '1900-01-01' and date '2200-12-31')
  ) not valid;

-- ===== 3. רישיון הנהג ========================================================

create table if not exists driver_licenses (
  id               uuid primary key default gen_random_uuid(),
  profile_id       uuid not null references profiles(id) on delete cascade,
  license_number   text,
  -- הדרגות כפי שהן רשומות ברישיון: "B, C1, C". טקסט חופשי — ההיררכיה של
  -- הדרגות אינה נבדקת כאן.
  license_classes  text,
  -- תאריך הוצאת הרישיון הראשון — ממנו נגזר הוותק.
  first_issued_at  date,
  expires_at       date,
  -- ממנו נגזר הגיל, מול `vehicles.insurance_min_driver_age`.
  birth_date       date,
  storage_path     text,
  file_name        text,
  mime_type        text,
  size_bytes       bigint,
  note             text,
  deleted_at       timestamptz,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  constraint driver_licenses_dates_sane check (
    (first_issued_at is null or first_issued_at between date '1900-01-01' and date '2200-12-31')
    and (expires_at  is null or expires_at  between date '1900-01-01' and date '2200-12-31')
    and (birth_date  is null or birth_date  between date '1900-01-01' and date '2200-12-31')
  )
);

create unique index if not exists driver_licenses_profile_uk
  on driver_licenses (profile_id) where deleted_at is null;

create trigger driver_licenses_updated before update on driver_licenses
  for each row execute function app.set_updated_at();
create trigger driver_licenses_audit after insert or update or delete on driver_licenses
  for each row execute function app.audit();

revoke all on driver_licenses from anon;
grant select, insert, update on driver_licenses to authenticated;

alter table driver_licenses enable row level security;

-- אותה תבנית כמו vehicle_documents (0089 §7): רק אדמין רואה מחוקים, צוות
-- בלבד, ושתי פוליסות כתיבה נפרדות ולא `for all`.
create policy driver_licenses_select on driver_licenses for select to authenticated using (
  ((select app.is_admin()) or deleted_at is null)
  and ((select app.is_admin())
       or ((select app.user_kind()) = 'staff' and (select app.has('fleet.docs_view')))));
create policy driver_licenses_insert on driver_licenses for insert to authenticated
  with check ((select app.is_admin()) or (select app.has('fleet.drivers_manage')));
create policy driver_licenses_update on driver_licenses for update to authenticated
  using      ((select app.is_admin()) or (select app.has('fleet.drivers_manage')))
  with check ((select app.is_admin()) or (select app.has('fleet.drivers_manage')));

-- ===== 4. השער של הדלי מכיר את נתיב הרישיונות ================================
-- גוף 0089 §8 כמו שהוא, ועוד ענף אחד ל-'drivers/<profile_id>/...'.

create or replace function app.may_touch_vehicle_doc(p_name text, p_write boolean)
returns boolean language plpgsql stable set search_path = public as $$
declare
  v_vehicle uuid;
  v_profile uuid;
begin
  if split_part(p_name, '/', 1) = 'drivers' then
    begin
      v_profile := split_part(p_name, '/', 2)::uuid;
    exception when others then
      return false;
    end;

    if not app.is_admin() then
      if app.user_kind() is distinct from 'staff' then return false; end if;
      if p_write and not app.has('fleet.drivers_manage') then return false; end if;
      if not p_write and not app.has('fleet.docs_view') then return false; end if;
    end if;

    return exists (select 1 from profiles p where p.id = v_profile);
  end if;

  -- כל דבר שאינו '<uuid>/...' בדלי הזה אינו שלנו, ואינו נפתח.
  begin
    v_vehicle := split_part(p_name, '/', 1)::uuid;
  exception when others then
    return false;
  end;

  if not app.is_admin() then
    if app.user_kind() is distinct from 'staff' then return false; end if;
    if p_write and not app.has('fleet.docs_manage') then return false; end if;
    if not p_write and not app.has('fleet.docs_view') then return false; end if;
  end if;

  return exists (select 1 from vehicles v where v.id = v_vehicle);
end $$;
