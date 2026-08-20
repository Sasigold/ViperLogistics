-- 0089: ניהול רכבים — הרכב כישות, ולא כערך ב-dropdown
--
-- `trucks` (0002) היא טבלת עזר של שם ומספר רישוי, וכל תפקידה הוא להיות ערך
-- בשיבוץ משימה. אין בה מקום למסמכי הרכב, אין תאריך טסט או ביטוח, אין כרטיס
-- דלק, ואין תשובה לשאלה "מי הנהג הקבוע של הרכב, ומי נהג בו במרץ". התוצאה
-- התפעולית היא שתוקף של טסט מתגלה כשעוצרים את הרכב.
--
-- שש החלטות:
--
--   1. **`vehicles` היא טבלה חדשה, ו-`trucks` נשארת במקומה.** כל מה שנשען על
--      `trucks` היום — `tasks.truck_ids`, `task_assignments.truck_id`,
--      `work_board_view`, `assignment_conflicts`, `scope_predicates` — ממשיך
--      לעבוד בלי לדעת שהמודול הזה קיים. הקישור ביניהן הוא `vehicles.truck_id`,
--      אופציונלי ו-1:1, והרכב הוא מקור האמת: טריגר דוחף ממנו את מספר הרישוי
--      אל המשאית המקושרת, כיוון אחד בלבד, כדי שהכפילות לא תסטה בשקט.
--   2. **סוגי המסמכים הם קטלוג, לא `check`.** טסט ורישיון רכב יש לכולם, אבל
--      אישור גז, רישיון מנוף ורישיון מוביל תלויים בצי. זו בדיוק הסיבה
--      ש-`task_types` ו-`statuses` הן טבלאות; `check` שמור כאן לקבוצות סגורות
--      (בעלות, סוג דלק, סטטוס).
--   3. **המסמך חוזר על דפוס 0077 ואינו ממציא אותו מחדש.** דלי פרטי, הנתיב הוא
--      החוזה `<vehicle_id>/<uuid>.<ext>`, שער `security invoker` אחד, והסרה
--      דרך RPC ‏`security definer` — כי מחיקה רכה תחת RLS אינה ניתנת לביטוי.
--   4. **הנהג הוא היסטוריה, לא עמודה.** `vehicle_driver_assignments` עם
--      `from_date`/`to_date`, הצמדה פתוחה אחת לרכב, ו-`vehicles.current_driver_id`
--      מדונרמל *מהטריגר בלבד* כדי שהרשימה תיקרא ב-PostgREST בשאילתה אחת.
--   5. **כרטיס הדלק הוא טבלה נפרדת, לא עמודות.** התקדים לשדה רגיש ברפו
--      (`contractors.view_contact`) חוסם כתיבה דרך `enforce_field_perms` אבל
--      אינו מסתיר את הערך בקריאה. ‏RLS היא row-level, ולכן טבלה נפרדת היא
--      הדרך היחידה שבה ה-PIN באמת אינו יוצא למי שאין לו את המפתח.
--   6. **התראת פקיעה נשלחת פעם אחת פר (מסמך, תאריך פקיעה, סף).** החידוש משנה
--      את `expires_at`, ולכן הוא דורך את ההתראה מחדש בלי איפוס ידני.

-- ===== 1. המודול והמפתחות ==================================================
-- ל-`fleet.view` **אין** implied_by, ובמפורש לא `settings.trucks`. הפיתוי היה
-- שם: מי שמנהל היום את רשימת המשאיות הוא בדיוק מי שינהל את הצי, ולא היה
-- מאבד דבר ביום הפריסה. אבל `app.has` מטפסת בשרשרת ה-implied_by, ורכזים
-- רבים מחזיקים `settings.trucks` — הוא המפתח שמתיר לתקן שם של משאית. כרטיס
-- הרכב מחזיק מחיר רכישה, עלות ליסינג חודשית וחוזה, ולכן ירושה משם הייתה
-- מוסרת את הכספים של הצי לכל מי שמורשה לתקן שם ב-dropdown. מודול חדש שאיש
-- עוד לא נשען עליו הוא בדיוק המקום שבו אפשר לא לשלם את המחיר הזה — וזו
-- העמדה של 0068 על `finance.receipts_manage`, מאותו נימוק.
--
-- שאר המפתחות דורשים הענקה מפורשת, ו-`applies_to = staff` בכולם: הצי אינו
-- מסך של לקוח ואינו מסך של קבלן.

select app.register_module('fleet', 'ניהול רכבים',
  'רכבי החברה — פרטים, מסמכים ותוקפם, נהג קבוע וכרטיס דלק', 'Truck', 74);

select app.register_permission('fleet.view', 'fleet', 'צפייה ברכבים',
  'רשימת הרכבים, כרטיס הרכב ותוקף המסמכים', 'action', false, false,
  array['staff']::user_kind[], null, 10);

select app.register_permission('fleet.create', 'fleet', 'הוספת רכב',
  null, 'action', false, false, array['staff']::user_kind[], null, 20);

select app.register_permission('fleet.edit', 'fleet', 'עריכת רכב',
  'פרטי הרכב, מד הקילומטרים, הבעלות והסטטוס', 'action', false, false,
  array['staff']::user_kind[], null, 30);

select app.register_permission('fleet.delete', 'fleet', 'מחיקת רכב',
  'העברה לסל המיחזור. הרכב יוצא מהרשימה ומהתראות הפקיעה', 'action', false, true,
  array['staff']::user_kind[], null, 40);

select app.register_permission('fleet.docs_view', 'fleet', 'צפייה במסמכי רכב',
  'טסט, רישיון, ביטוחים — התאריכים והקבצים הסרוקים', 'field', false, false,
  array['staff']::user_kind[], 'fleet.view', 50);

select app.register_permission('fleet.docs_manage', 'fleet', 'ניהול מסמכי רכב',
  'הוספת מסמך, העלאת קובץ סרוק והסרת מסמך', 'action', false, false,
  array['staff']::user_kind[], 'fleet.edit', 60);

select app.register_permission('fleet.drivers_manage', 'fleet', 'הצמדת נהג לרכב',
  'פתיחת הצמדה חדשה וסגירת הקיימת. ההיסטוריה נשמרת', 'action', false, false,
  array['staff']::user_kind[], 'fleet.edit', 70);

select app.register_permission('fleet.view_fuel_card', 'fleet', 'צפייה בכרטיס הדלק',
  'ספק, מספר הכרטיס וקוד ה-PIN של הדלקן', 'field', false, true,
  array['staff']::user_kind[], null, 80);

select app.register_permission('fleet.manage_fuel_card', 'fleet', 'ניהול כרטיס הדלק',
  'הזנה ועדכון של פרטי הדלקן', 'action', false, true,
  array['staff']::user_kind[], null, 90);

select app.register_permission('fleet.settings', 'fleet', 'ניהול סוגי מסמכי רכב',
  'הקטלוג שממנו נבחר סוג המסמך, וכמה ימים לפני הפקיעה מתריעים', 'action', false, false,
  array['staff']::user_kind[], 'settings.edit', 100);

-- ===== 2. הרכב =============================================================

create table vehicles (
  id                  uuid primary key default gen_random_uuid(),
  -- מספר הרישוי הוא הזהות בשטח, ולכן הוא חובה וייחודי בין החיים.
  plate_number        text not null,
  -- השם שבו קוראים לרכב בדיבור: "המשאית הגדולה", "V-101".
  name                text not null,
  -- הקישור לשורת השיבוץ. null = רכב מנוהל שאינו משובץ למשימות (רכב מנהלים,
  -- מלגזה שאינה יוצאת מהמחסן).
  truck_id            uuid unique references trucks(id) on delete set null,

  make                text,
  model               text,
  model_year          int check (model_year is null or model_year between 1950 and 2100),
  vin                 text,
  engine_number       text,
  color               text,
  category            text not null default 'truck'
                      check (category in ('truck','van','car','trailer','forklift','other')),
  -- דרגת הרישיון שנדרשת כדי לנהוג בו: B, C1, C, E, 1 (מלגזה)...
  license_class       text,
  fuel_type           text check (fuel_type in ('diesel','gasoline','electric','hybrid','lpg')),
  gearbox             text check (gearbox in ('manual','automatic')),
  seats               int check (seats is null or seats >= 0),
  gross_weight_kg     int check (gross_weight_kg is null or gross_weight_kg >= 0),
  payload_kg          int check (payload_kg is null or payload_kg >= 0),

  ownership           text not null default 'owned'
                      check (ownership in ('owned','leasing','rental')),
  leasing_company     text,
  leasing_monthly_cost numeric(12,2) check (leasing_monthly_cost is null or leasing_monthly_cost >= 0),
  leasing_end_date    date,
  purchase_date       date,
  purchase_price      numeric(12,2) check (purchase_price is null or purchase_price >= 0),

  odometer_km         int check (odometer_km is null or odometer_km >= 0),
  odometer_read_at    date,

  status              text not null default 'active'
                      check (status in ('active','in_garage','inactive','sold')),
  -- נגזרים מ-vehicle_driver_assignments ואינם נכתבים מהקליינט. ראה סעיף 5.
  current_driver_id   uuid references profiles(id) on delete set null,
  current_driver_name text,

  notes               text,
  -- אין `is_active` כאן, בשונה משאר טבלאות העזר: `status` הוא התשובה היחידה
  -- לשאלה אם הרכב זמין. שני דגלים שיכולים לסתור זה את זה הם בדיוק מה ש-0077
  -- סירבה לו כשלא הוסיפה `is_current` לצד מספר הגרסה.
  deleted_at          timestamptz,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);

create unique index vehicles_plate_uk on vehicles (lower(btrim(plate_number)))
  where deleted_at is null;
create index vehicles_status_live_idx on vehicles (status) where deleted_at is null;
create index vehicles_driver_idx on vehicles (current_driver_id) where deleted_at is null;

create trigger vehicles_updated before update on vehicles
  for each row execute function app.set_updated_at();
create trigger vehicles_audit after insert or update or delete on vehicles
  for each row execute function app.audit();

revoke all on vehicles from anon;

-- ===== 3. הרכב מול המשאית ==================================================
-- כיוון אחד בלבד: מה שנכתב על הרכב מוחל על שורת המשאית המקושרת. ההפך אינו
-- נכון במכוון — טאב "משאיות" בהגדרות נשאר מסך של רשימת שיבוץ, ואינו הופך
-- לדלת אחורית לעריכת נכס.
--
-- ה-update על trucks עובר תחת system_write כדי שלא ידרוש settings.trucks ממי
-- שמחזיק fleet.edit בלבד: ההרשאה כבר נבדקה על הרכב, וזו גזירה ולא פעולה
-- נפרדת. אותו נימוק שכתוב ב-0012 על soft_delete.

create or replace function app.sync_vehicle_truck()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.truck_id is null then return new; end if;

  if tg_op = 'INSERT'
     or new.truck_id     is distinct from old.truck_id
     or new.plate_number is distinct from old.plate_number
     or new.name         is distinct from old.name then
    perform app.system_write(true);
    update trucks
       set plate_number = new.plate_number,
           name         = new.name
     where id = new.truck_id
       and (plate_number is distinct from new.plate_number or name is distinct from new.name);
    perform app.system_write(false);
  end if;
  return new;
end $$;

create trigger vehicles_truck_sync after insert or update on vehicles
  for each row execute function app.sync_vehicle_truck();

-- קישור לשורת משאית קיימת, ויצירת אחת חדשה מהרכב. שניהם RPC ולא UPDATE ישיר:
-- הראשון חייב לאמת שהמשאית פנויה (העמודה ייחודית, וההודעה של Postgres על
-- הפרת אינדקס אינה משהו שמסך צריך להציג), והשני כותב ל-trucks.

create or replace function vehicle_link_truck(p_vehicle uuid, p_truck uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform app.require('fleet.edit', 'אין לך הרשאה לערוך רכב');
  if not exists (select 1 from vehicles where id = p_vehicle and deleted_at is null) then
    raise exception 'הרכב לא נמצא';
  end if;
  if p_truck is not null then
    if not exists (select 1 from trucks where id = p_truck and deleted_at is null) then
      raise exception 'המשאית לא נמצאה';
    end if;
    if exists (select 1 from vehicles where truck_id = p_truck and id <> p_vehicle) then
      raise exception 'המשאית כבר מקושרת לרכב אחר';
    end if;
  end if;
  update vehicles set truck_id = p_truck where id = p_vehicle;
end $$;

create or replace function vehicle_create_truck(p_vehicle uuid)
returns uuid language plpgsql security definer set search_path = public as $$
declare v vehicles; v_truck uuid;
begin
  perform app.require('fleet.edit', 'אין לך הרשאה לערוך רכב');
  select * into v from vehicles where id = p_vehicle and deleted_at is null;
  if v.id is null then raise exception 'הרכב לא נמצא'; end if;
  if v.truck_id is not null then return v.truck_id; end if;

  insert into trucks (name, plate_number) values (v.name, v.plate_number)
    returning id into v_truck;
  update vehicles set truck_id = v_truck where id = p_vehicle;
  return v_truck;
end $$;

revoke execute on function public.vehicle_link_truck(uuid, uuid) from anon, public;
revoke execute on function public.vehicle_create_truck(uuid) from anon, public;

-- ===== 4. מסמכי הרכב =======================================================
-- ‏alert_days הוא תכונה של *סוג* המסמך ולא של המסמך: על ביטוח חובה מתריעים
-- חודש מראש כי החידוש לוקח יום, ועל רישיון מנוף שלושה חודשים כי הוא דורש
-- בדיקה מתוזמנת. שינוי הסף בקטלוג מחיל את עצמו על כל המסמכים מהסוג הזה,
-- וההתראות שכבר נשלחו אינן נשלחות שוב (סעיף 7).

create table vehicle_document_kinds (
  id                  uuid primary key default gen_random_uuid(),
  key                 text not null unique,
  name                text not null,
  -- כמה חודשים תקף מסמך מהסוג הזה, למילוי אוטומטי של תאריך הפקיעה בטופס.
  default_valid_months int check (default_valid_months is null or default_valid_months > 0),
  alert_days          int not null default 30 check (alert_days between 0 and 365),
  -- מסמך חובה = רכב בלי מסמך תקף מהסוג הזה נספר ב"חסרים" במסך ובדשבורד.
  is_required         boolean not null default false,
  sort_order          int not null default 100,
  is_active           boolean not null default true,
  deleted_at          timestamptz,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);
create trigger vehicle_document_kinds_updated before update on vehicle_document_kinds
  for each row execute function app.set_updated_at();
create trigger vehicle_document_kinds_audit
  after insert or update or delete on vehicle_document_kinds
  for each row execute function app.audit();

revoke all on vehicle_document_kinds from anon;

-- הזריעה היא מה שנדרש בישראל לצי מעורב. `on conflict do nothing` כדי
-- שהרצה חוזרת של המיגרציה לא תדרוס סף שמנהל שינה.
insert into vehicle_document_kinds
  (key, name, default_valid_months, alert_days, is_required, sort_order) values
  ('annual_test',    'טסט שנתי',              12, 30, true,  10),
  ('vehicle_license','רישיון רכב',            12, 30, true,  20),
  ('insurance_mandatory','ביטוח חובה',        12, 30, true,  30),
  ('insurance_comprehensive','ביטוח מקיף',    12, 30, false, 40),
  ('insurance_third_party','ביטוח צד ג׳',     12, 30, false, 50),
  ('gas_approval',   'אישור מערכת גז',        12, 30, false, 60),
  ('crane_license',  'רישיון מנוף / עגורן',   12, 90, false, 70),
  ('tachograph',     'טכוגרף',                12, 30, false, 80),
  ('carrier_license','רישיון מוביל',          12, 60, false, 90),
  ('license_fee',    'אגרת רישוי',            12, 30, false, 100)
on conflict (key) do nothing;

create table vehicle_documents (
  id              uuid primary key default gen_random_uuid(),
  vehicle_id      uuid not null references vehicles(id) on delete cascade,
  kind_id         uuid not null references vehicle_document_kinds(id),
  document_number text,
  issued_at       date,
  -- null = מסמך בלי תוקף (חוזה, אישור חד-פעמי). הוא אינו נכנס להתראות.
  expires_at      date,
  cost            numeric(12,2) check (cost is null or cost >= 0),
  issuer          text,
  note            text,
  -- הקובץ הסרוק, בדיוק בחוזה של 0077: '<vehicle_id>/<uuid>.<ext>' בדלי
  -- הפרטי vehicle-docs. null = מסמך שנרשם בלי סריקה, וזה מותר.
  storage_path    text,
  file_name       text,
  mime_type       text,
  size_bytes      bigint check (size_bytes is null or size_bytes >= 0),
  -- מדונרמל לצד ה-FK, מאותה סיבה שכתובה ב-0016 על actor_name.
  created_by      uuid references profiles(id) on delete set null,
  creator_name    text,
  deleted_at      timestamptz,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  constraint vehicle_documents_dates check (issued_at is null or expires_at is null
                                            or expires_at >= issued_at),
  constraint vehicle_documents_file check (storage_path is null
                                           or btrim(coalesce(file_name, '')) <> '')
);

create index vehicle_documents_vehicle_idx on vehicle_documents (vehicle_id, expires_at)
  where deleted_at is null;
create index vehicle_documents_expiry_idx on vehicle_documents (expires_at)
  where deleted_at is null and expires_at is not null;

create trigger vehicle_documents_updated before update on vehicle_documents
  for each row execute function app.set_updated_at();
create trigger vehicle_documents_audit
  after insert or update or delete on vehicle_documents
  for each row execute function app.audit();

revoke all on vehicle_documents from anon;

-- זהות המעלה נכפית מהשרת ולא מתקבלת מהקליינט, כמו ב-0077: אחרת אפשר לחתום
-- מסמך בשם אדם אחר.
create or replace function app.vehicle_document_before_insert()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_actor uuid := app.profile_id();
begin
  new.created_by   := v_actor;
  new.creator_name := (select full_name from profiles where id = v_actor);
  new.deleted_at   := null;
  return new;
end $$;

create trigger vehicle_documents_before_insert before insert on vehicle_documents
  for each row execute function app.vehicle_document_before_insert();

-- ה-view הוא מה שהמסך קורא: הוא מחשב את התוקף פעם אחת, בשרת, מול הסף של
-- הסוג. `security_invoker = true` — המוסכמה מאז 0005 — ולכן ה-RLS של
-- vehicle_documents נשארת השער היחיד ואין כאן דלת שנייה.
create or replace view vehicle_document_status with (security_invoker = true) as
select d.id, d.vehicle_id, d.kind_id,
       k.key as kind_key, k.name as kind_name, k.alert_days, k.is_required,
       d.document_number, d.issued_at, d.expires_at, d.cost, d.issuer, d.note,
       d.storage_path, d.file_name, d.mime_type, d.size_bytes,
       d.created_by, d.creator_name, d.created_at, d.deleted_at,
       case
         when d.expires_at is null                              then 'no_expiry'
         when d.expires_at <  current_date                      then 'expired'
         when d.expires_at <= current_date + k.alert_days       then 'expiring'
         else 'valid'
       end as status,
       (d.expires_at - current_date) as days_left
  from vehicle_documents d
  join vehicle_document_kinds k on k.id = d.kind_id;

grant select on vehicle_document_status to authenticated;

-- הסרת מסמך היא RPC ולא UPDATE, מאותה סיבה שכתובה ב-0077 §7: פוסטגרס מחילה
-- את פוליסת ה-select גם על השורה החדשה ב-UPDATE, ולכן שורה אינה יכולה
-- להעלים את עצמה מעיני מי שמחק אותה.
create or replace function remove_vehicle_document(p_id uuid, p_restore boolean default false)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform app.require('fleet.docs_manage',
    case when p_restore then 'אין לך הרשאה לשחזר מסמך' else 'אין לך הרשאה להסיר מסמך' end);
  if not exists (select 1 from vehicle_documents where id = p_id) then
    raise exception 'המסמך לא נמצא';
  end if;
  update vehicle_documents
     set deleted_at = case when p_restore then null else now() end
   where id = p_id;
end $$;

revoke execute on function public.remove_vehicle_document(uuid, boolean) from anon, public;

-- ===== 5. הנהג של הרכב =====================================================
-- הצמדה היא טווח תאריכים, ולא עמודה על הרכב. השאלה שהמערכת חייבת לענות עליה
-- כשמגיע דוח תנועה או נזק היא "מי נהג ברכב ב-12 במרץ", ועמודה יחידה מוחקת את
-- התשובה בכל החלפה.

create table vehicle_driver_assignments (
  id           uuid primary key default gen_random_uuid(),
  vehicle_id   uuid not null references vehicles(id) on delete cascade,
  profile_id   uuid not null references profiles(id) on delete cascade,
  -- מדונרמל לצד ה-FK, מאותה סיבה שכתובה ב-0016 על actor_name: נהג שעזב
  -- והפרופיל שלו נמחק משאיר היסטוריה ששכחה מי נהג, וזו אינה היסטוריה.
  driver_name  text,
  from_date    date not null default current_date,
  -- null = ההצמדה הפעילה. יש לכל היותר אחת כזו לרכב.
  to_date      date,
  note         text,
  created_by   uuid references profiles(id) on delete set null,
  creator_name text,
  deleted_at   timestamptz,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  constraint vda_range check (to_date is null or to_date >= from_date)
);

create unique index vda_open_uk on vehicle_driver_assignments (vehicle_id)
  where to_date is null and deleted_at is null;
create index vda_vehicle_idx on vehicle_driver_assignments (vehicle_id, from_date desc)
  where deleted_at is null;
create index vda_profile_idx on vehicle_driver_assignments (profile_id, from_date desc)
  where deleted_at is null;

create trigger vda_updated before update on vehicle_driver_assignments
  for each row execute function app.set_updated_at();
create trigger vda_audit after insert or update or delete on vehicle_driver_assignments
  for each row execute function app.audit();

revoke all on vehicle_driver_assignments from anon;

-- `vehicles.current_driver_id` מדונרמל בכוונה, ולא מחושב ב-view: הרשימה
-- נקראת ב-PostgREST, שאין בו lateral, ובלי העמודה כל שורה הייתה דורשת
-- הלוך-חזור נוסף. המחיר הוא שהיא חייבת להיות בלתי-ניתנת לכתיבה מבחוץ, ושני
-- הטריגרים כאן הם מה שקונה את זה.
create or replace function app.sync_vehicle_driver()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_vehicles uuid[];
  v_id       uuid;
  v_driver   uuid;
  v_name     text;
begin
  if tg_op = 'DELETE' then
    v_vehicles := array[old.vehicle_id];
  elsif tg_op = 'UPDATE' and new.vehicle_id is distinct from old.vehicle_id then
    v_vehicles := array[old.vehicle_id, new.vehicle_id];
  else
    v_vehicles := array[new.vehicle_id];
  end if;

  foreach v_id in array v_vehicles loop
    select a.profile_id, coalesce(a.driver_name, p.full_name)
      into v_driver, v_name
      from vehicle_driver_assignments a
      left join profiles p on p.id = a.profile_id
     where a.vehicle_id = v_id and a.to_date is null and a.deleted_at is null
     order by a.from_date desc
     limit 1;

    perform app.system_write(true);
    update vehicles
       set current_driver_id = v_driver, current_driver_name = v_name
     where id = v_id
       and (current_driver_id is distinct from v_driver
            or current_driver_name is distinct from v_name);
    perform app.system_write(false);
  end loop;

  return coalesce(new, old);
end $$;

create trigger vda_sync_vehicle
  after insert or update or delete on vehicle_driver_assignments
  for each row execute function app.sync_vehicle_driver();

-- הצד השני של אותה החלטה: מי שכותב ישירות על vehicles אינו קובע מי הנהג.
-- app.in_system_write() הוא המנגנון הקיים לאותה הבחנה (0012), וכאן הוא מבדיל
-- בין הגזירה של הטריגר שלמעלה לבין שמירה של טופס.
create or replace function app.vehicle_driver_guard()
returns trigger language plpgsql set search_path = public as $$
begin
  if app.in_system_write() then return new; end if;
  if tg_op = 'INSERT' then
    new.current_driver_id   := null;
    new.current_driver_name := null;
  else
    new.current_driver_id   := old.current_driver_id;
    new.current_driver_name := old.current_driver_name;
  end if;
  return new;
end $$;

create trigger vehicles_driver_guard before insert or update on vehicles
  for each row execute function app.vehicle_driver_guard();

-- פתיחת הצמדה סוגרת את הקודמת באותה טרנזקציה. שתי כתיבות נפרדות מהקליינט היו
-- נופלות על האינדקס הייחודי בדיוק באמצע, ומשאירות רכב בלי נהג.
create or replace function assign_vehicle_driver(
  p_vehicle uuid, p_profile uuid,
  p_from date default current_date, p_note text default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_actor uuid := app.profile_id();
  v_open  vehicle_driver_assignments;
  v_id    uuid;
begin
  perform app.require('fleet.drivers_manage', 'אין לך הרשאה להצמיד נהג לרכב');

  if not exists (select 1 from vehicles where id = p_vehicle and deleted_at is null) then
    raise exception 'הרכב לא נמצא';
  end if;
  if not exists (select 1 from profiles
                  where id = p_profile and is_active and deleted_at is null) then
    raise exception 'הנהג לא נמצא';
  end if;

  select * into v_open from vehicle_driver_assignments
   where vehicle_id = p_vehicle and to_date is null and deleted_at is null
   for update;

  -- אותו נהג שכבר מוצמד: לא נפתחת הצמדה שנייה, וההיסטוריה אינה מתמלאת ברעש.
  if v_open.id is not null and v_open.profile_id = p_profile then
    return v_open.id;
  end if;

  if v_open.id is not null then
    -- greatest ולא p_from - 1 סתם: הצמדה שנפתחה היום ומוחלפת היום נסגרת היום,
    -- ולא ביום שלפני תחילתה — אחרת vda_range נופל.
    update vehicle_driver_assignments
       set to_date = greatest(p_from - 1, v_open.from_date)
     where id = v_open.id;
  end if;

  insert into vehicle_driver_assignments
    (vehicle_id, profile_id, driver_name, from_date, note, created_by, creator_name)
  values (p_vehicle, p_profile,
          (select full_name from profiles where id = p_profile),
          coalesce(p_from, current_date), p_note, v_actor,
          (select full_name from profiles where id = v_actor))
  returning id into v_id;

  return v_id;
end $$;

create or replace function end_vehicle_driver(p_vehicle uuid, p_to date default current_date)
returns void language plpgsql security definer set search_path = public as $$
declare v_open vehicle_driver_assignments;
begin
  perform app.require('fleet.drivers_manage', 'אין לך הרשאה לסיים הצמדת נהג');

  select * into v_open from vehicle_driver_assignments
   where vehicle_id = p_vehicle and to_date is null and deleted_at is null
   for update;
  if v_open.id is null then raise exception 'אין לרכב נהג מוצמד'; end if;

  update vehicle_driver_assignments
     set to_date = greatest(coalesce(p_to, current_date), v_open.from_date)
   where id = v_open.id;
end $$;

revoke execute on function public.assign_vehicle_driver(uuid, uuid, date, text) from anon, public;
revoke execute on function public.end_vehicle_driver(uuid, date) from anon, public;

-- ===== 6. כרטיס הדלק =======================================================
-- טבלה נפרדת ולא עמודות על vehicles, וזו החלטה על אכיפה ולא על סדר.
--
-- התקדים ברפו לשדה רגיש הוא field_registry: `contractors.view_contact` חוסם
-- *כתיבה* דרך app.enforce_field_perms, וההסתרה בקריאה נעשית בלקוח. עבור טלפון
-- של קבלן זה מספיק; עבור קוד PIN זה לא — מי שמחזיק fleet.view היה מקבל אותו
-- ב-PostgREST בלי לפתוח את המסך. ‏RLS היא row-level, ולכן השורה הרגישה חייבת
-- להיות שורה משלה.

create table vehicle_fuel_cards (
  id          uuid primary key default gen_random_uuid(),
  vehicle_id  uuid not null references vehicles(id) on delete cascade,
  provider    text,
  card_number text,
  pin_code    text,
  valid_until date,
  note        text,
  deleted_at  timestamptz,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create unique index vehicle_fuel_cards_vehicle_uk on vehicle_fuel_cards (vehicle_id)
  where deleted_at is null;

create trigger vehicle_fuel_cards_updated before update on vehicle_fuel_cards
  for each row execute function app.set_updated_at();

revoke all on vehicle_fuel_cards from anon;

-- ‏app.audit() הגנרית כותבת to_jsonb(new) שלם ל-audit_log, וכל מי שמחזיק
-- settings.audit_log היה קורא משם את ה-PIN — כלומר ההפרדה שהטבלה הזו קיימת
-- בשבילה הייתה נפרצת מהדלת האחורית. הטריגר כאן זהה לה פרט לשני שדות שמוחלפים
-- ב-'***' *אחרי* חישוב changed_cols: מי שינה, מתי, ואיזה שדה — כן נרשם.
create or replace function app.audit_fuel_card()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_old jsonb; v_new jsonb; v_changed text[]; v_row_id uuid;
  v_mask constant text[] := array['card_number', 'pin_code'];
  k text;
begin
  if tg_op = 'INSERT' then
    v_new := to_jsonb(new); v_row_id := new.id;
  elsif tg_op = 'UPDATE' then
    v_old := to_jsonb(old); v_new := to_jsonb(new); v_row_id := new.id;
    select coalesce(array_agg(key), '{}') into v_changed
      from jsonb_each(v_new) as n(key, value)
     where v_old -> key is distinct from value;
    if v_changed = '{}' then return new; end if;
  else
    v_old := to_jsonb(old); v_row_id := old.id;
  end if;

  foreach k in array v_mask loop
    if v_old ? k and v_old ->> k is not null then v_old := jsonb_set(v_old, array[k], '"***"'); end if;
    if v_new ? k and v_new ->> k is not null then v_new := jsonb_set(v_new, array[k], '"***"'); end if;
  end loop;

  insert into audit_log (actor_user_id, action, table_name, row_id, old_data, new_data, changed_cols)
  values (auth.uid(), tg_op::audit_action, tg_table_name, v_row_id, v_old, v_new, v_changed);
  return coalesce(new, old);
end $$;

create trigger vehicle_fuel_cards_audit
  after insert or update or delete on vehicle_fuel_cards
  for each row execute function app.audit_fuel_card();

-- ===== 7. RLS ==============================================================
-- מדיניות אחת לכל פועל, וכל קריאה ל-app.* עטופה ב-(select ...) כדי שתהפוך
-- ל-InitPlan ולא תרוץ פר-שורה — הכלל של 0028.
--
-- אין ענף customer_user ואין ענף contractor_user באף פוליסה: הצי הוא נכס של
-- החברה, ואינו מוצג לאיש מחוץ לצוות.

alter table vehicles                   enable row level security;
alter table vehicle_document_kinds     enable row level security;
alter table vehicle_documents          enable row level security;
alter table vehicle_driver_assignments enable row level security;
alter table vehicle_fuel_cards         enable row level security;

-- רק אדמין רואה מחוקים, בכל חמש הטבלאות — התבנית של receipts (0068).
create policy vehicles_select on vehicles for select to authenticated using (
  ((select app.is_admin()) or deleted_at is null)
  and ((select app.is_admin())
       or ((select app.user_kind()) = 'staff' and (select app.has('fleet.view')))));
create policy vehicles_insert on vehicles for insert to authenticated
  with check ((select app.is_admin()) or (select app.has('fleet.create')));
create policy vehicles_update on vehicles for update to authenticated
  using      ((select app.is_admin()) or (select app.has('fleet.edit')))
  with check ((select app.is_admin()) or (select app.has('fleet.edit')));

-- הקטלוג נקרא משני מסכים — כרטיס הרכב וההגדרות — ולכן הקריאה היא איחוד
-- המפתחות שלהם, והכתיבה צרה.
create policy vdk_select on vehicle_document_kinds for select to authenticated using (
  ((select app.is_admin()) or deleted_at is null)
  and ((select app.is_admin())
       or ((select app.user_kind()) = 'staff'
           and ((select app.has('fleet.view')) or (select app.has('fleet.settings'))))));
-- שתי פוליסות נפרדות ולא `for all`, בכוונה: `for all` הייתה חלה גם על
-- select, ומכיוון ש-Postgres מאחד פוליסות פרמיסיביות באותו פועל ב-OR, מי
-- שמחזיק fleet.settings היה רואה גם שורות מחוקות — בדיוק המקום שבו הפוליסה
-- הזו הייתה עוקפת בשקט את `deleted_at is null` של vdk_select. אותה מלכודת
-- קיימת ב-vfc_write למטה, ותוקנה שם באותה צורה.
create policy vdk_insert on vehicle_document_kinds for insert to authenticated
  with check ((select app.is_admin()) or (select app.has('fleet.settings')));
create policy vdk_update on vehicle_document_kinds for update to authenticated
  using      ((select app.is_admin()) or (select app.has('fleet.settings')))
  with check ((select app.is_admin()) or (select app.has('fleet.settings')));

create policy vehicle_documents_select on vehicle_documents for select to authenticated using (
  ((select app.is_admin()) or deleted_at is null)
  and ((select app.is_admin())
       or ((select app.user_kind()) = 'staff' and (select app.has('fleet.docs_view')))));
create policy vehicle_documents_insert on vehicle_documents for insert to authenticated
  with check ((select app.is_admin()) or (select app.has('fleet.docs_manage')));
-- ‏update כן קיים — תיקון תאריך או מספר מסמך הוא עריכה רגילה — אבל *הסרה*
-- עוברת ב-remove_vehicle_document (סעיף 4) ולא דרכו, מהסיבה שכתובה שם: שורה
-- אינה יכולה להעלים את עצמה מעיני מי שמחק אותה.
create policy vehicle_documents_update on vehicle_documents for update to authenticated
  using      ((select app.is_admin()) or (select app.has('fleet.docs_manage')))
  with check ((select app.is_admin()) or (select app.has('fleet.docs_manage')));

create policy vda_select on vehicle_driver_assignments for select to authenticated using (
  ((select app.is_admin()) or deleted_at is null)
  and ((select app.is_admin())
       or ((select app.user_kind()) = 'staff' and (select app.has('fleet.view')))));
-- אין פוליסת כתיבה כלל, במכוון: ההצמדה נפתחת ונסגרת אך ורק דרך
-- assign_vehicle_driver / end_vehicle_driver (security definer). הצמדה
-- שנפתחת בלי לסגור את הקודמת נופלת על vda_open_uk, וזו לא שגיאה שמסך צריך
-- לתרגם — היא מצב שה-RPC פשוט אינו מאפשר להגיע אליו.

-- זו הפוליסה שכל סעיף 6 קיים בשבילה.
create policy vfc_select on vehicle_fuel_cards for select to authenticated using (
  ((select app.is_admin()) or deleted_at is null)
  and ((select app.is_admin())
       or ((select app.user_kind()) = 'staff' and (select app.has('fleet.view_fuel_card')))));
-- שתי פוליסות נפרדות ולא `for all`, מאותה סיבה שכתובה ב-vdk למעלה.
create policy vfc_insert on vehicle_fuel_cards for insert to authenticated
  with check ((select app.is_admin()) or (select app.has('fleet.manage_fuel_card')));
create policy vfc_update on vehicle_fuel_cards for update to authenticated
  using      ((select app.is_admin()) or (select app.has('fleet.manage_fuel_card')))
  with check ((select app.is_admin()) or (select app.has('fleet.manage_fuel_card')));

-- ===== 8. הדלי ופוליסות ה-Storage ==========================================
-- זהה במבנה ל-0077 §8, כולל הנימוקים: הנתיב הוא החוזה, השער הוא
-- `security invoker` אחד כדי שה-RLS של הקורא תחול על הקבצים בלי שורת קוד
-- נוספת, והבלוק כולו עטוף כי ב-Supabase ‏storage.objects שייכת ל-
-- supabase_storage_admin ו-postgres אינו יכול ליצור עליה פוליסה.

create or replace function app.may_touch_vehicle_doc(p_name text, p_write boolean)
returns boolean language plpgsql stable set search_path = public as $$
declare v_vehicle uuid;
begin
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

do $$
begin
  if to_regclass('storage.buckets') is null or to_regclass('storage.objects') is null then
    raise notice '0089: אין סכמת storage — הדלי והפוליסות מדולגים';
    return;
  end if;

  -- 25MB, אותו גודל שנבחר ב-0077: צילום רישיון מהטלפון שוקל 3-8MB, וסריקת
  -- פוליסת ביטוח שלמה מגיעה ל-20.
  execute $sql$
    insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
    values ('vehicle-docs', 'vehicle-docs', false, 26214400, array[
      'application/pdf',
      'image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/heif'])
    on conflict (id) do update set
      public             = false,
      file_size_limit    = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types
  $sql$;

  begin
    execute 'drop policy if exists vehicle_docs_objects_read   on storage.objects';
    execute 'drop policy if exists vehicle_docs_objects_insert on storage.objects';
    execute 'drop policy if exists vehicle_docs_objects_update on storage.objects';
    execute 'drop policy if exists vehicle_docs_objects_delete on storage.objects';

    execute $sql$
      create policy vehicle_docs_objects_read on storage.objects for select to authenticated
        using (bucket_id = 'vehicle-docs' and app.may_touch_vehicle_doc(name, false))
    $sql$;
    execute $sql$
      create policy vehicle_docs_objects_insert on storage.objects for insert to authenticated
        with check (bucket_id = 'vehicle-docs' and app.may_touch_vehicle_doc(name, true))
    $sql$;
    execute $sql$
      create policy vehicle_docs_objects_update on storage.objects for update to authenticated
        using (bucket_id = 'vehicle-docs' and app.may_touch_vehicle_doc(name, true))
        with check (bucket_id = 'vehicle-docs' and app.may_touch_vehicle_doc(name, true))
    $sql$;
    -- delete נדרש מאותה סיבה כמו ב-0077: העלאה שהקובץ שלה עלה אך שורת ה-DB
    -- נדחתה מנקה אחריה, אחרת כל דחיית RLS משאירה קובץ יתום בדלי.
    execute $sql$
      create policy vehicle_docs_objects_delete on storage.objects for delete to authenticated
        using (bucket_id = 'vehicle-docs' and app.may_touch_vehicle_doc(name, true))
    $sql$;
  exception when insufficient_privilege then
    raise warning '0089: אין בעלות על storage.objects — ארבע פוליסות מסמכי הרכב לא נוצרו. יש להגדיר אותן ב-Dashboard → Storage → Policies על הדלי vehicle-docs, עם הביטוי app.may_touch_vehicle_doc(name, <false לקריאה / true לכתיבה>). עד אז RLS דוחה כל גישה לקבצים.';
  end;
end $$;

-- ===== 9. התראות פקיעה =====================================================

select app.register_notification_type('vehicle_document_expiring',
  'מסמך רכב עומד לפוג', 'טסט, ביטוח או רישיון שמתקרב לתאריך הפקיעה',
  'רכבים', array['admin','staff'], 'vehicle', 'opt_out', 'opt_out', 'opt_in', 210);

select app.register_notification_type('vehicle_document_expired',
  'מסמך רכב פג תוקף', 'המסמך כבר אינו בתוקף, והרכב אינו חוקי לנסיעה',
  'רכבים', array['admin','staff'], 'vehicle', 'forced', 'opt_out', 'opt_in', 220);

-- ‏required_permission (0064) הוא מה שמונע מהמטריצה להציע את המתגים האלה למי
-- שאינו רואה את הצי בכלל.
update notification_types set required_permission = 'fleet.view'
 where key in ('vehicle_document_expiring', 'vehicle_document_expired');

-- הקישור בפעמון. הגוף זהה ל-0072 בתוספת זרוע אחת, ולא נעטף — מאותו נימוק
-- שכתוב שם ובכל גלגול קודם שלו.
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
    if p_type = 'attendance_submitted' then
      select work_date into v_date from attendance_entries where id = p_entity_id;
      return '/attendance?entry=' || p_entity_id
             || coalesce('&date=' || to_char(v_date, 'YYYY-MM-DD'), '');
    end if;
    return '/my/attendance?entry=' || p_entity_id;
  end if;

  if p_entity_type = 'vehicle' then
    return '/vehicles/' || p_entity_id;
  end if;

  return '/';
end $$;

-- המפתח לאידמפוטנטיות. `expires_at` הוא חלק מהמפתח ולא עמודה נלווית: חידוש
-- המסמך משנה אותו, ולכן הוא דורך את ההתראה מחדש מעצמו. איפוס ידני לא נדרש,
-- ואי אפשר לשכוח אותו.
create table vehicle_document_alerts (
  document_id    uuid not null references vehicle_documents(id) on delete cascade,
  expires_at     date not null,
  threshold_days int  not null,
  sent_at        timestamptz not null default now(),
  primary key (document_id, expires_at, threshold_days)
);

alter table vehicle_document_alerts enable row level security;
revoke all on vehicle_document_alerts from anon;
-- אין פוליסה, במכוון: הטבלה היא יומן פנימי של הסוויפ. הבעלים (postgres) כותב
-- בה דרך security definer, ואיש מלבדו אינו קורא אותה.

-- הסוויפ. `security definer` כי הוא רץ בזהות של תזמון ולא של אדם, ואינו
-- מחזיר מידע על אף רכב — רק כמה התראות נשלחו. השער האמיתי הוא על מי *מקבל*:
-- app.profiles_with('fleet.view') מחזיר בדיוק את מי שמותר לו לדעת.
--
-- שלושה ספים לכל מסמך: הסף של הסוג (30 יום ברירת מחדל), 7 ימים, ויום הפקיעה
-- עצמו. `distinct` מונע כפילות כשהסף של הסוג הוא כבר 7 או 0.
--
-- **התראה אחת לכל מסמך בכל הרצה, גם כששלושה ספים בשלו יחד.** מסמך שנרשם
-- במערכת כשהוא כבר פג עומד בכל שלושת הספים באותו רגע, ושליחה של שלוש שורות
-- פעמון על אותו ביטוח היא בדיוק מה שגורם לאנשים לכבות את ההתראות. לכן כל
-- הספים שהגיעו נרשמים ביומן — הם לא יישלחו שוב לעולם — ורק הנמוך שבהם,
-- כלומר החמור, מייצר התראה. השאר נספרים כ-suppressed ומוחזרים, כדי שהדילוג
-- יהיה נראה ולא מסתורי.
create or replace function fleet_expiry_sweep()
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  r            record;
  v_recipient  uuid;
  v_type       text;
  v_title      text;
  v_body       text;
  v_due        int[];
  v_fresh      int[];
  v_left       int;
  v_docs       int := 0;
  v_sent       int := 0;
  v_suppressed int := 0;
begin
  -- קורא בלי JWT הוא התזמון בזהות service role — אותה הבחנה בדיוק שעושה
  -- app.enforce_field_perms מאז 0012. קורא עם JWT הוא אדם שלחץ "בדוק עכשיו",
  -- והוא חייב להחזיק מפתח: הסוויפ אינו מחזיר מידע, אבל הוא כן שולח דואר
  -- לכל מנהלי הצי, ולא כל אחד רשאי לייצר את זה.
  if auth.uid() is not null then
    perform app.require('fleet.edit', 'אין לך הרשאה להריץ בדיקת תוקף');
  end if;

  -- שתי הרצות במקביל — התזמון ולחיצה ידנית באותו רגע — היו נופלות זו על זו
  -- על המפתח הראשי של vehicle_document_alerts. הנעילה זולה כי היא גלובלית
  -- לסוויפ אחד, ומשתחררת בסוף הטרנזקציה. אותו מכשיר של 0077 §4.
  perform pg_advisory_xact_lock(hashtextextended('fleet_expiry_sweep', 0));

  for r in
    select d.id, d.vehicle_id, d.expires_at, k.alert_days,
           k.name as kind_name, v.name as vehicle_name, v.plate_number,
           v.current_driver_id
      from vehicle_documents d
      join vehicle_document_kinds k on k.id = d.kind_id
      join vehicles v on v.id = d.vehicle_id
     where d.deleted_at is null
       and d.expires_at is not null
       and v.deleted_at is null
       and v.status <> 'sold'
       and d.expires_at - current_date <= greatest(k.alert_days, 7)
     order by d.expires_at
  loop
    -- הספים שכבר הגיעו למסמך הזה
    select array_agg(distinct t) into v_due
      from unnest(array[r.alert_days, 7, 0]) t
     where r.expires_at - current_date <= t;
    if v_due is null then continue; end if;

    -- ומתוכם, מה שטרם נשלח. הסדר עולה, ולכן האיבר הראשון הוא החמור.
    select array_agg(t order by t) into v_fresh
      from unnest(v_due) t
     where not exists (
       select 1 from vehicle_document_alerts a
        where a.document_id = r.id and a.expires_at = r.expires_at and a.threshold_days = t);
    if v_fresh is null then continue; end if;

    insert into vehicle_document_alerts (document_id, expires_at, threshold_days)
    select r.id, r.expires_at, t from unnest(v_fresh) t
    on conflict do nothing;

    v_suppressed := v_suppressed + cardinality(v_fresh) - 1;
    v_docs       := v_docs + 1;
    v_left       := r.expires_at - current_date;

    -- 'פג' נקבע לפי התאריך ולא לפי הסף, כדי להסכים עם vehicle_document_status:
    -- ביום הפקיעה עצמו המסמך עדיין בתוקף, והוא "פג היום" ולא "פג".
    if v_left < 0 then
      v_type  := 'vehicle_document_expired';
      v_title := 'מסמך רכב פג תוקף';
      v_body  := r.kind_name || ' של ' || r.vehicle_name || ' (' || r.plate_number ||
                 ') פג ב-' || to_char(r.expires_at, 'DD/MM/YYYY');
    else
      v_type  := 'vehicle_document_expiring';
      v_title := 'מסמך רכב עומד לפוג';
      v_body  := r.kind_name || ' של ' || r.vehicle_name || ' (' || r.plate_number || ') ' ||
                 case when v_left = 0 then 'פג היום'
                      else 'פג ב-' || to_char(r.expires_at, 'DD/MM/YYYY') ||
                           ', בעוד ' || v_left || ' ימים' end;
    end if;

    for v_recipient in
      select p.id from app.profiles_with('fleet.view') as p(id)
      union
      select r.current_driver_id where r.current_driver_id is not null
    loop
      perform app.notify(v_recipient, v_type, v_title, v_body, 'vehicle', r.vehicle_id);
      v_sent := v_sent + 1;
    end loop;
  end loop;

  return jsonb_build_object('documents', v_docs, 'notifications', v_sent,
                           'suppressed', v_suppressed);
end $$;

revoke execute on function public.fleet_expiry_sweep() from anon, public;
-- ‏service_role לפונקציית ה-Edge המתוזמנת, ו-authenticated כדי שמנהל צי יוכל
-- ללחוץ "בדוק עכשיו" במסך. השער האמיתי הוא ה-app.require שבתוך הגוף; ההענקה
-- כאן רק מאפשרת להגיע אליו.
grant  execute on function public.fleet_expiry_sweep() to service_role, authenticated;

-- הסיכום שמזין את כרטיסי המונים במסך הרכבים. `security invoker` כדי שה-RLS
-- תצמצם אותו לבד, בדיוק כמו dashboard_sections.
create or replace function fleet_expiry_summary()
returns jsonb language sql stable security invoker set search_path = public as $$
  with docs as (
    select s.vehicle_id, s.status, s.is_required
      from vehicle_document_status s
      join vehicles v on v.id = s.vehicle_id
     where s.deleted_at is null and v.deleted_at is null and v.status <> 'sold'
  ),
  required_missing as (
    select count(*)::int as n
      from vehicles v
      cross join vehicle_document_kinds k
     where v.deleted_at is null and v.status <> 'sold'
       and k.is_required and k.is_active and k.deleted_at is null
       and not exists (
         select 1 from vehicle_documents d
          where d.vehicle_id = v.id and d.kind_id = k.id and d.deleted_at is null
            and (d.expires_at is null or d.expires_at >= current_date))
  )
  select jsonb_build_object(
    'vehicles', (select count(*)::int from vehicles
                  where deleted_at is null and status <> 'sold'),
    'valid',    (select count(*)::int from docs where status = 'valid'),
    'expiring', (select count(*)::int from docs where status = 'expiring'),
    'expired',  (select count(*)::int from docs where status = 'expired'),
    'missing_required', (select n from required_missing))
$$;

revoke execute on function public.fleet_expiry_summary() from anon, public;

-- ===== 10. סל המיחזור ======================================================
-- הגוף מועתק מ-0014:242 — ההגדרה החיה — בתוספת שני ענפים. מפתח אחד לשני
-- הכיוונים, כמו trucks ו-suppliers: אין `fleet.restore` נפרד, כי מי שמורשה
-- להוציא רכב מהרשימה מורשה גם להחזיר אותו. אותו דבר לגבי `vehicle_document_kinds`
-- מול `fleet.settings` — הטאב "סוגי מסמכי רכב" בהגדרות קורא ל-soft_delete על
-- הטבלה הזו בדיוק (כמו trucks/task_types/statuses), ובלי הענף כאן כל לחיצת
-- מחיקה שם הייתה נופלת על 'טבלה לא נתמכת'.
--
-- ‏vehicle_documents אינו כאן במכוון. להסרת מסמך יש כבר נתיב אחד —
-- remove_vehicle_document — ושחזור נעשה מכרטיס הרכב, בדיוק כמו גרסת מפרט
-- ב-0077. שני נתיבים לאותה מחיקה הם שני מקומות שאפשר לשכוח בהם בדיקה.

create or replace function soft_delete(p_table text, p_id uuid, p_restore boolean default false)
returns void language plpgsql security definer set search_path = public as $$
declare v_key text;
begin
  v_key := case p_table
    when 'events'             then case when p_restore then 'events.restore'      else 'events.delete' end
    when 'tasks'              then case when p_restore then 'tasks.restore'       else 'tasks.delete' end
    when 'customers'          then case when p_restore then 'customers.restore'   else 'customers.delete' end
    when 'contractors'        then case when p_restore then 'contractors.restore' else 'contractors.delete' end
    when 'contractor_workers' then 'contractors.manage_workers'
    when 'profiles'           then case when p_restore then 'users.restore'       else 'users.delete' end
    when 'suppliers'          then 'customers.manage_suppliers'
    when 'trucks'             then 'settings.trucks'
    when 'vehicles'           then 'fleet.delete'
    when 'vehicle_document_kinds' then 'fleet.settings'
    when 'task_types'         then 'settings.task_types'
    when 'execution_methods'  then 'settings.execution_methods'
    when 'statuses'           then 'settings.statuses'
    else null end;
  if v_key is null then raise exception 'טבלה לא נתמכת'; end if;
  perform app.require(v_key, 'אין לך הרשאה למחוק פריט זה');

  -- the key says "may delete this kind of thing"; this says "this one"
  if not app.is_admin() then
    if p_table = 'profiles' and not app.can_manage_profile(p_id) then
      raise exception 'אין לך הרשאה למחוק משתמש זה' using errcode = '42501';
    end if;
    if app.user_kind() = 'customer_user' then
      if p_table = 'events' then
        if not exists (select 1 from events
                       where id = p_id and customer_id = app.customer_id()) then
          raise exception 'אין לך הרשאה למחוק פריט זה' using errcode = '42501';
        end if;
      elsif p_table <> 'profiles' then
        raise exception 'אין לך הרשאה למחוק פריט זה' using errcode = '42501';
      end if;
    end if;
  end if;

  if p_table = 'task_types' and not p_restore
     and exists (select 1 from task_types where id = p_id and is_system) then
    raise exception 'לא ניתן למחוק סוג משימה מערכתי';
  end if;

  perform app.system_write(true);
  execute format('update %I set deleted_at = case when $2 then null else now() end where id = $1', p_table)
    using p_id, p_restore;
  perform app.system_write(false);
end $$;
