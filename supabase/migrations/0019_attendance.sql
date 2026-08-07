-- 0019: נוכחות ומשמרות — סכמה, הרשאות ו-RLS
--
-- עד כאן המערכת ידעה לתכנן עבודה ולא ידעה למדוד אותה. יש שעת התחלה במחסן,
-- שעת התחלה בשטח, מספר שעות וזמן נסיעה — כולם *מתוכננים* — ואין שום עמודה
-- שאומרת מתי מישהו באמת הגיע, מתי הלך, וכמה זה עלה. התעריף השעתי היחיד
-- בקוד (PricingConfig.hour_rate) הוא מה שגובים מהלקוח, לא מה שמשלמים לעובד.
--
-- הקובץ הזה מוסיף את הצלע החסרה. ארבע החלטות עומדות בבסיסו:
--
-- 1. המשמרת אינה טבלה. היא *נגזרת* מהמשימות ששובצו לעובד (0020). משמרת
--    כשורה שמורה הייתה מתיישנת בכל שינוי שעה במשימה, והיינו צריכים לתחזק
--    סנכרון בין שני מקורות שאין דרך לדעת מי מהם צודק.
--
-- 2. ההחתמה נכתבת אך ורק דרך RPC. "מיקום נדרש" הוא חסימה מוחלטת, ובדיקה
--    שיושבת בדפדפן היא קוסמטית — הטבלה חשופה דרך PostgREST. לכן אין
--    לעובד פוליסת INSERT כלל: הכתיבה עוברת ב-security definer שאוכף.
--
-- 3. השכר אינו נשמר. הוא מחושב בקריאה מתוך הרשומות ומהגדרות העובד, ולכן
--    אין כאן is_manual, אין recalc ואין שורות שמתיישנות. מי שאין לו
--    attendance.view_pay מקבל את השעות בלי הסכומים — מאותה שאילתה.
--
-- 4. עובד קבלן מחתים כמו כל אחד אחר. הוא מקבל שורת profiles שמקושרת
--    לשורת הסגל שלו (§2), ולא נתיב הרשאות מקביל. app.has() מחזיר false
--    כשאין profile, ולכן בלי השורה הזו שום דבר במערכת לא היה עובד עבורו.

-- ===== 1. שטח או מחסן, פר-משובץ ============================================
-- על שורת השיבוץ ולא על המשימה, בדיוק כמו task_assignments.truck_id: אותה
-- משימה יכולה לכלול אנשים שאוספים ציוד מהמחסן ואנשים שמגיעים ישר לאתר.
-- text+check ולא enum — כמו pricing_zones.shape ו-customers.pricing_mode
-- (0017), שכן ערך שנוסף ל-enum אי אפשר להסיר.

alter table task_assignments
  add column work_site text not null default 'field'
    check (work_site in ('field', 'warehouse'));
alter table task_contractor_workers
  add column work_site text not null default 'field'
    check (work_site in ('field', 'warehouse'));

comment on column task_assignments.work_site is
  'מהיכן העובד מתחיל: field = ישר לשטח, warehouse = מהמחסן.';

-- ===== 2. עובד קבלן שמחתים =================================================
-- contractor_workers.user_id קיים מ-0001 אבל מעולם לא היה ייחודי, ולכן
-- "איזה עובד הוא המשתמש הזה" לא הייתה שאלה שאפשר לענות עליה.

create unique index contractor_workers_user_uq on contractor_workers (user_id)
  where user_id is not null and deleted_at is null;

alter table profiles
  add column contractor_worker_id uuid unique references contractor_workers(id);

comment on column profiles.contractor_worker_id is
  'קישור התחברות של עובד קבלן לשורת הסגל שלו. NULL לכל שאר המשתמשים.';

-- ===== 3. הגדרות שכר ושעון פר-עובד =========================================
-- טבלת לוויין ולא עמודות על profiles, מאותו נימוק שנוסח ב-0017 עבור
-- task_pricing: RLS ב-Postgres הוא ברמת שורה בלבד, ו-profiles_select נותן
-- לכל עובד צוות לראות כל שורת עובד צוות. תעריף שעתי כעמודה על profiles היה
-- גלוי לכל החברה.
--
-- כל עמודת כלל בשעון היא nullable במכוון: NULL פירושו "לך לפי ההגדרה
-- הגלובלית". עם not null default, "מעולם לא הוגדר" ו"הוגדר במפורש כבוי"
-- היו אותו ערך, ואדמין שמדליק את ברירת המחדל הגלובלית לא היה משפיע על איש.

create table worker_pay_settings (
  profile_id             uuid primary key references profiles(id) on delete cascade,
  -- שכר
  hourly_rate            numeric(10,2) check (hourly_rate is null or hourly_rate >= 0),
  overtime_enabled       boolean not null default true,
  min_hours_per_shift    numeric(5,2)
    check (min_hours_per_shift is null or (min_hours_per_shift >= 0 and min_hours_per_shift <= 24)),
  travel_paid            boolean not null default true,
  -- שעון
  clock_enabled          boolean,
  requires_location      boolean,
  location_radius_m      int check (location_radius_m is null or location_radius_m > 0),
  allow_early_clock_in   boolean,
  early_grace_minutes    int check (early_grace_minutes is null or early_grace_minutes >= 0),
  allow_clock_without_shift boolean,
  notes                  text,
  created_at             timestamptz not null default now(),
  updated_at             timestamptz not null default now()
);
create trigger worker_pay_settings_updated before update on worker_pay_settings
  for each row execute function app.set_updated_at();

comment on column worker_pay_settings.min_hours_per_shift is
  'השלמה לשעות: משמרת קצרה מהערך הזה משולמת כאילו נמשכה אותו. NULL = אין השלמה.';

-- ===== 4. רשומת הנוכחות ====================================================
-- שורה אחת למשמרת, עם כניסה ויציאה. המיקום מוקפא בזמן הכתיבה — גם נקודת
-- הייחוס וגם המרחק — כי חישוב מחדש מאוחר יותר היה משנה רשומה קיימת ברגע
-- שמישהו עורך את כתובת האירוע.

create table attendance_entries (
  id           uuid primary key default gen_random_uuid(),
  profile_id   uuid not null references profiles(id),
  work_date    date not null,
  seq          int not null default 1,
  -- המשמרת המתוכננת שאליה נצמדה ההחתמה, כפי שנראתה באותו רגע
  shift_start   timestamptz,
  shift_end     timestamptz,
  planned_hours numeric(6,2),
  work_site     text check (work_site is null or work_site in ('field', 'warehouse')),
  task_ids      uuid[] not null default '{}',

  clock_in_at        timestamptz not null,
  clock_in_lat       double precision,
  clock_in_lng       double precision,
  clock_in_accuracy_m numeric(8,1),
  clock_in_distance_m numeric(10,1),
  clock_out_at        timestamptz,
  clock_out_lat       double precision,
  clock_out_lng       double precision,
  clock_out_accuracy_m numeric(8,1),
  clock_out_distance_m numeric(10,1),
  -- מה שהשעון מדד, לפני תיקון של מנהל
  raw_clock_in_at  timestamptz,
  raw_clock_out_at timestamptz,

  actual_hours numeric(6,2) generated always as (
    case when clock_out_at is not null
      then round((extract(epoch from (clock_out_at - clock_in_at)) / 3600.0)::numeric, 2)
    end) stored,

  source text not null default 'clock' check (source in ('clock', 'manual')),
  -- דגלים פתוחים ולא enum: בדיקה חדשה מוסיפה קוד בלי DDL.
  -- no_site_coords · no_shift · low_accuracy · auto_closed · reattached · edited
  flags text[] not null default '{}',

  employee_note text,
  manager_note  text,
  edited_by     uuid references profiles(id),
  edited_at     timestamptz,
  created_by    uuid references profiles(id),
  deleted_at    timestamptz,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  constraint attendance_order check (clock_out_at is null or clock_out_at > clock_in_at)
);

-- כניסה כפולה נחסמת במסד ולא רק ב-RPC
create unique index attendance_one_open on attendance_entries (profile_id)
  where clock_out_at is null and deleted_at is null;
create unique index attendance_seq_uq on attendance_entries (profile_id, work_date, seq)
  where deleted_at is null;
create index attendance_profile_date_idx on attendance_entries (profile_id, work_date)
  where deleted_at is null;
create index attendance_date_idx on attendance_entries (work_date) where deleted_at is null;
create index attendance_flags_idx on attendance_entries using gin (flags);

create trigger attendance_entries_updated before update on attendance_entries
  for each row execute function app.set_updated_at();

-- הטיפוס של משמרת נגזרת. טיפוס בעל שם ולא returns table, כדי ש-app.shift_at
-- תוכל להחזיר שורה בודדת מאותו מבנה בלי לשכפל את רשימת העמודות.
create type app.planned_shift_row as (
  profile_id     uuid,
  work_date      date,
  seq            int,
  shift_start    timestamptz,
  shift_end      timestamptz,
  planned_hours  numeric,
  work_site      text,
  task_ids       uuid[],
  first_task_id  uuid,
  last_task_id   uuid,
  start_lat      double precision,
  start_lng      double precision,
  end_lat        double precision,
  end_lng        double precision,
  travel_hours   numeric,
  label          text,
  customer_id    uuid,
  customer_color text
);

-- ===== 5. הגדרות גלובליות ==================================================
-- app_settings קיימת מ-0002 עם RLS כתוב, ולא הייתה בשימוש עד כאן.
-- on conflict do nothing כדי שהרצה חוזרת לא תדרוס קונפיגורציה מכווננת.

insert into app_settings (key, value) values
  ('attendance.overtime', jsonb_build_object(
     'version', 1,
     -- חוק שעות עבודה ומנוחה כברירת מחדל, וכולו ניתן לעריכה מהמסך.
     -- hours=null פירושו "וכל מה שמעל", אותה מוסכמה של מדרגות התמחור.
     'daily', jsonb_build_object(
       'base_hours', 8,
       'tiers', jsonb_build_array(
         jsonb_build_object('hours', 2,    'rate', 1.25),
         jsonb_build_object('hours', null, 'rate', 1.5))),
     'rest_day', jsonb_build_object(
       'dow', jsonb_build_array(6),
       'base_hours', 8,
       'base_rate', 1.5,
       'tiers', jsonb_build_array(
         jsonb_build_object('hours', 2,    'rate', 1.75),
         jsonb_build_object('hours', null, 'rate', 2.0))),
     'weekly', jsonb_build_object('enabled', false, 'base_hours', 42, 'rate', 1.25),
     'rounding', jsonb_build_object('minutes', 0, 'mode', 'nearest'),
     'top_up', jsonb_build_object('counts_toward_overtime', false))),

  ('attendance.clock', jsonb_build_object(
     'version', 1,
     'merge_gap_minutes', 120,
     'clock_enabled', true,
     'requires_location', false,
     'location_radius_m', 300,
     'allow_early_clock_in', false,
     'early_grace_minutes', 15,
     'allow_clock_without_shift', false,
     'max_accuracy_m', 500,
     'auto_close_after_hours', 16,
     'warehouse', jsonb_build_object('lat', null, 'lng', null, 'label', 'המחסן')))
on conflict (key) do nothing;

-- ===== 6. הרשאות ===========================================================
-- שני צירים נפרדים במכוון: מי רואה *שעות* ומי רואה *כסף*. מנהל משמרת צריך
-- את הראשון בלי השני, וחשב שכר את השני בלי המסך התפעולי, ולכן
-- attendance.view_pay אינו נגזר מ-attendance.view_all ולהפך.
--
-- applies_to לא כולל customer_user באף מפתח: טעות שאי אפשר לבצע עדיפה על
-- טעות שנתפסת.

select app.register_module('attendance', 'נוכחות ומשמרות',
  'שעון נוכחות, לוח משמרות, שעות נוספות ושכר שעתי', 'Clock', 85);

select app.register_permission('attendance.view_own', 'attendance', 'הנוכחות שלי',
  'ההחתמות והשעות של המשתמש עצמו', 'access', false, false,
  array['staff', 'contractor_user']::user_kind[], null, 10);

select app.register_permission('attendance.view_schedule', 'attendance', 'לוח המשמרות שלי',
  'תצוגת השבוע של המשמרות הנגזרות מהמשימות', 'access', false, false,
  array['staff', 'contractor_user']::user_kind[], 'attendance.view_own', 20);

select app.register_permission('attendance.clock', 'attendance', 'החתמת שעון',
  'כניסה ויציאה ממשמרת', 'action', false, false,
  array['staff', 'contractor_user']::user_kind[], 'attendance.view_own', 30);

select app.register_permission('attendance.view_own_pay', 'attendance', 'השכר שלי',
  'הסכומים בדוח הנוכחות של המשתמש עצמו', 'field', false, false,
  array['staff', 'contractor_user']::user_kind[], 'attendance.view_own', 40);

select app.register_permission('attendance.view_all', 'attendance', 'דוח נוכחות של כולם',
  'שעות של כל העובדים, עם פילטרים', 'access', false, false,
  array['staff']::user_kind[], null, 50);

select app.register_permission('attendance.edit_entry', 'attendance', 'תיקון החתמות',
  'שינוי שעות של רשומת נוכחות קיימת', 'action', false, true,
  array['staff']::user_kind[], null, 60);

select app.register_permission('attendance.manual_entry', 'attendance', 'הזנת נוכחות ידנית',
  'רישום משמרת עבור עובד, בלי בדיקת מיקום', 'action', false, true,
  array['staff']::user_kind[], 'attendance.edit_entry', 70);

select app.register_permission('attendance.delete', 'attendance', 'מחיקת רשומת נוכחות',
  null, 'crud', false, true, array['staff']::user_kind[], null, 80);

select app.register_permission('attendance.manage_clock', 'attendance', 'הגדרות שעון פר-עובד',
  'מיקום נדרש, רדיוס והתחלה מוקדמת', 'action', false, false,
  array['staff']::user_kind[], null, 90);

select app.register_permission('attendance.view_pay', 'attendance', 'צפייה בשכר של עובדים',
  'תעריף שעתי וסכומים לתשלום', 'field', false, true,
  array['staff']::user_kind[], null, 100);

select app.register_permission('attendance.manage_pay', 'attendance', 'עריכת שכר עובדים',
  'תעריף לשעה, שעות נוספות והשלמה לשעות', 'action', false, true,
  array['staff']::user_kind[], 'attendance.view_pay', 110);

select app.register_permission('attendance.settings', 'attendance', 'הגדרות שעות נוספות',
  'מדרגות שעות נוספות, עיגול והגדרות השעון הגלובליות', 'action', false, true,
  array['staff']::user_kind[], null, 120);

select app.register_permission('attendance.export', 'attendance', 'ייצוא דוח נוכחות',
  null, 'action', false, false, array['staff']::user_kind[], 'attendance.view_all', 130);

select app.register_permission('portal.attendance', 'portal', 'נוכחות עובדי הקבלן',
  'דוח הנוכחות של הסגל שלי בפורטל', 'access', false, false,
  array['contractor_user']::user_kind[], 'portal.view', 45);

select app.register_permission('portal.attendance_pay', 'portal', 'שכר עובדי הקבלן',
  'הסכומים בדוח הנוכחות של הסגל שלי', 'field', false, true,
  array['contractor_user']::user_kind[], null, 46);

-- שדות: מה שמסומן sensitive נעלם מהתצוגה המאובטחת למי שאין לו את המפתח,
-- והטריגר הגנרי חוסם את הכתיבה אליו בכל נתיב.
select app.register_field('worker_pay', 'hourly_rate', 'תעריף לשעה', 'attendance',
  'worker_pay_settings', 'hourly_rate', true, false, false, 'attendance.manage_pay', 10);
select app.register_field('worker_pay', 'overtime_enabled', 'זכאי לשעות נוספות', 'attendance',
  'worker_pay_settings', 'overtime_enabled', true, false, false, 'attendance.manage_pay', 20);
select app.register_field('worker_pay', 'min_hours_per_shift', 'השלמה לשעות', 'attendance',
  'worker_pay_settings', 'min_hours_per_shift', true, false, false, 'attendance.manage_pay', 30);
select app.register_field('worker_pay', 'travel_paid', 'זמן נסיעה בתשלום', 'attendance',
  'worker_pay_settings', 'travel_paid', true, false, false, 'attendance.manage_pay', 40);
select app.register_field('worker_pay', 'requires_location', 'נדרש מיקום', 'attendance',
  'worker_pay_settings', 'requires_location', false, true, false, 'attendance.manage_clock', 50);
select app.register_field('worker_pay', 'allow_early_clock_in', 'התחלה לפני המשימה', 'attendance',
  'worker_pay_settings', 'allow_early_clock_in', false, true, false, 'attendance.manage_clock', 60);

-- שעות הכניסה והיציאה: כל אחד רואה, רק attendance.edit_entry עורך. זה מה
-- שהופך את פוליסת ה-UPDATE של העובד על השורה שלו לבטוחה — היא מתירה את
-- השורה, והטריגר מצמצם אותה לעמודה אחת (employee_note).
select app.register_field('attendance', 'clock_in_at', 'שעת כניסה', 'attendance',
  'attendance_entries', 'clock_in_at', false, true, false, 'attendance.edit_entry', 70);
select app.register_field('attendance', 'clock_out_at', 'שעת יציאה', 'attendance',
  'attendance_entries', 'clock_out_at', false, true, false, 'attendance.edit_entry', 80);
select app.register_field('attendance', 'manager_note', 'הערת מנהל', 'attendance',
  'attendance_entries', 'manager_note', false, true, false, 'attendance.edit_entry', 90);
select app.register_field('assignment', 'work_site', 'שטח / מחסן', 'attendance',
  'task_assignments', 'work_site', false, true, true, null, 100);

-- ברירות מחדל לפי סוג משתמש: לכל עובד יש שעון. נעשה כאן ולא דרך
-- default_allowed במרשם, כי default_allowed היה חל גם על customer_user.
insert into kind_permission_defaults (user_kind, permission_key, allowed) values
  ('staff',           'attendance.view_own',      true),
  ('staff',           'attendance.view_schedule', true),
  ('staff',           'attendance.clock',         true),
  ('staff',           'attendance.view_own_pay',  true),
  ('contractor_user', 'attendance.view_own',      true),
  ('contractor_user', 'attendance.view_schedule', true),
  ('contractor_user', 'attendance.clock',         true),
  ('contractor_user', 'attendance.view_own_pay',  true),
  ('contractor_user', 'portal.attendance',        true)
on conflict (user_kind, permission_key) do nothing;

-- תפקיד צר לעובד קבלן מן השורה. בלעדיו כל contractor_user יורש מ-0011 את
-- portal.view_financials ואת contractors.view_pricing — כלומר עובד שקיבל
-- התחברות כדי להחתים שעון היה רואה את כל הכספים של הקבלן.
-- p_close_modules הוא מה שכותב את הדחיות המפורשות שגוברות על ברירת המחדל.
insert into permission_roles (key, name_he, description_he, user_kind, is_system, sort_order)
values ('contractor_worker', 'עובד קבלן', 'החתמת שעון וצפייה במשמרות שלו בלבד',
        'contractor_user', true, 125)
on conflict (key) do update set
  name_he = excluded.name_he,
  description_he = excluded.description_he,
  sort_order = excluded.sort_order;

select app.set_role_permissions('contractor_worker',
  array['attendance.view_own', 'attendance.view_schedule', 'attendance.clock',
        'attendance.view_own_pay', 'notifications.view'],
  array['portal', 'contractors', 'attendance']);

-- ===== 7. RLS ==============================================================

alter table worker_pay_settings enable row level security;
alter table attendance_entries  enable row level security;

-- מי הקבלן של העובד הזה. משמש את זרוע הקבלן בכל הפוליסות שלמטה, ונשמר
-- כפונקציה כדי שהפוליסה תישאר קצרה ותרוץ כ-InitPlan.
create or replace function app.is_my_contractor_staff(p_profile_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select p_profile_id is not null
     and app.contractor_id() is not null
     and exists (select 1 from profiles p
                  where p.id = p_profile_id
                    and p.contractor_id = app.contractor_id()
                    and p.deleted_at is null)
$$;

create policy wps_select on worker_pay_settings for select to authenticated using (
  (select app.is_admin())
  or profile_id = (select app.profile_id())
  or ((select app.user_kind()) = 'staff'
      and ((select app.has('attendance.view_pay')) or (select app.has('attendance.manage_clock'))))
  or ((select app.user_kind()) = 'contractor_user'
      and (select app.has('portal.attendance_pay'))
      and app.is_my_contractor_staff(profile_id)));

create policy wps_write on worker_pay_settings for all to authenticated
  using ((select app.is_admin())
         or (select app.has('attendance.manage_pay'))
         or (select app.has('attendance.manage_clock')))
  with check ((select app.is_admin())
         or (select app.has('attendance.manage_pay'))
         or (select app.has('attendance.manage_clock')));

-- העובד רואה את שלו; מנהל עם המפתח רואה את כולם; קבלן רואה את הסגל שלו.
create policy ae_select on attendance_entries for select to authenticated using (
  (select app.is_admin())
  or (deleted_at is null and (
    profile_id = (select app.profile_id())
    or ((select app.user_kind()) = 'staff' and (select app.has('attendance.view_all')))
    or ((select app.user_kind()) = 'contractor_user'
        and (select app.has('portal.attendance'))
        and app.is_my_contractor_staff(profile_id)))));

-- אין כאן זרוע לעובד. ההחתמה הרגילה עוברת ב-attendance_clock_in, שהוא
-- security definer ולכן עוקף את הפוליסה הזו אחרי שאכף את כל הכללים.
-- זה מה שהופך את "נדרש מיקום" לחסימה אמיתית ולא להצעה.
create policy ae_insert on attendance_entries for insert to authenticated with check (
  (select app.is_admin()) or (select app.has('attendance.manual_entry')));

create policy ae_update on attendance_entries for update to authenticated
  using ((select app.is_admin())
         or (select app.has('attendance.edit_entry'))
         or (profile_id = (select app.profile_id()) and deleted_at is null))
  with check ((select app.is_admin())
         or (select app.has('attendance.edit_entry'))
         or (profile_id = (select app.profile_id()) and deleted_at is null));

create policy ae_delete on attendance_entries for delete to authenticated
  using ((select app.is_admin()) or (select app.has('attendance.delete')));

-- app_settings נכתבה עד כה רק ע"י settings.edit. מפתחות הנוכחות שייכים
-- למי שמנהל שעות נוספות, ופוליסה נוספת רק מרחיבה — ולכן החלפה ולא הוספה.
drop policy if exists app_settings_write on app_settings;
create policy app_settings_write on app_settings for all to authenticated
  using ((select app.is_admin())
         or (key like 'attendance.%' and (select app.has('attendance.settings')))
         or (key not like 'attendance.%' and (select app.has('settings.edit'))))
  with check ((select app.is_admin())
         or (key like 'attendance.%' and (select app.has('attendance.settings')))
         or (key not like 'attendance.%' and (select app.has('settings.edit'))));

-- ===== 8. טריגרים ==========================================================

do $$
declare t text;
begin
  foreach t in array array['worker_pay_settings', 'attendance_entries']
  loop
    execute format(
      'create trigger %I_audit after insert or update or delete on %I
         for each row execute function app.audit()', t, t);
  end loop;
end $$;

create trigger worker_pay_settings_field_perms before update on worker_pay_settings
  for each row execute function app.enforce_field_perms();
create trigger attendance_entries_field_perms before update on attendance_entries
  for each row execute function app.enforce_field_perms();

select app.rebuild_secure_view('worker_pay_settings');
select app.rebuild_secure_view('attendance_entries');

-- מחיקת נוכחות אינה עוברת ב-soft_delete הגנרי: המיפוי שם מתרגם משאב
-- לזוג resource.delete / resource.edit, ו-"עריכת נוכחות" כאן היא
-- attendance.edit_entry — שם אחר. RPC ייעודי זול יותר מלכופף את המיפוי.
create or replace function attendance_delete_entry(p_id uuid, p_restore boolean default false)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform app.require('attendance.delete');
  update attendance_entries
     set deleted_at = case when p_restore then null else now() end
   where id = p_id;
end $$;
revoke execute on function public.attendance_delete_entry(uuid, boolean) from anon, public;
