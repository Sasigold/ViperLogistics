-- 0024: דיווח משמרת ידני של עובד, בהמתנה לאישור
--
-- עד כאן היו לרשומת נוכחות שני נתיבים: השעון (0020 §7), שכל הבדיקות יושבות
-- בו, והנתיב הידני של המנהל (§8), שפטור מהן כי מי שמפעיל אותו מוסמך. לעובד
-- שהשעון שלו לא עבד — סוללה, קליטה, או פשוט שכח — לא הייתה דרך לומר "עבדתי
-- מ-08:00 עד 14:00" חוץ מלתפוס מנהל שיזין במקומו.
--
-- ארבע החלטות:
--
-- 1. אותה טבלה, ולא טבלת "בקשות" נפרדת. בקשה שאושרה היא רשומת נוכחות לכל
--    דבר; שתי טבלאות היו מחייבות העתקה בין שורה לשורה, ואת השאלה "לפי מי
--    מהן משלמים" בכל שאילתה בהמשך. עמודת status עונה עליה במקום אחד.
--
-- 2. 'approved' היא ברירת המחדל של העמודה. כל מה שכבר נרשם, וכל מה שנרשם
--    מהשעון או ביד של מנהל, נשאר מאושר בלי מיגרציית נתונים — רק הנתיב החדש
--    כותב 'pending'.
--
-- 3. "לא מחושב עד שאושר" נאכף בדוח ולא במנוע החישוב. app.attendance_calc
--    נשארת פונקציה טהורה על שעות, והדוח הוא זה שמוציא שורה שאינה מאושרת
--    מהצברים — גם מהסיכומים וגם מהצבר השבועי שמזין את התקרה השבועית.
--
-- 4. הדיווח נכתב דרך RPC ולא דרך פוליסת INSERT, מאותו נימוק שנוסח ב-0019:
--    טבלה חשופה דרך PostgREST, ולכן חלון האחורה, האיסור על חפיפה והאיסור
--    על דיווח עתידי חייבים לשבת ב-security definer. ו-status עצמו נרשם
--    ב-field_registry — בלי זה, פוליסת ה-UPDATE שמתירה לעובד לגעת בשורה
--    שלו (0019 §7) הייתה מתירה לו גם לאשר את עצמו.

-- ===== 1. הסטטוס על השורה ==================================================

alter table attendance_entries
  add column status text not null default 'approved'
    check (status in ('pending', 'approved', 'rejected')),
  add column reviewed_by uuid references profiles(id),
  add column reviewed_at timestamptz;

comment on column attendance_entries.status is
  'pending = דיווח עובד שממתין לאישור, ואינו נספר בשעות ובשכר. rejected = נדחה.';

create index attendance_pending_idx on attendance_entries (work_date desc)
  where status = 'pending' and deleted_at is null;

-- ===== 2. הגדרות הדיווח ====================================================
-- יושב בתוך attendance.clock ולא במפתח חדש, כדי ש-app.clock_rules תמשיך
-- להיות התשובה היחידה לשאלה "מה מותר לעובד הזה" ותביא גם את זה בלי קריאה
-- נוספת. הבלוק כולו nested, ולכן דריסה פר-עובד לא נדרשת כאן: מי שאסור לו
-- לדווח מקבל את זה דרך שלילת ההרשאה, ולא דרך עמודה.

update app_settings
   set value = value || jsonb_build_object('self_entry', jsonb_build_object(
         'enabled', true,
         -- כמה אחורה מותר לדווח. חלון פתוח לרווחה היה מזמין דיווחים על
         -- חודשים שכבר נסגרו בשכר.
         'max_backdate_days', 14,
         'max_hours', 16))
 where key = 'attendance.clock'
   and not (value ? 'self_entry');

-- ===== 3. הרשאות ===========================================================
-- שני מפתחות ולא אחד: "מותר לי לדווח על עצמי" הוא יכולת של כל עובד, ו"מותר
-- לי להפוך דיווח לשעות שמשולמות" הוא כוח של מנהל. implied_by קושר את השני
-- ל-attendance.edit_entry, כי מי שממילא רשאי לשנות שעות ברשומה קיימת אינו
-- צריך מפתח נוסף כדי לאשר אותה.

select app.register_permission('attendance.submit_entry', 'attendance', 'דיווח משמרת ידני',
  'דיווח משמרת שלא הוחתמה בשעון, לאישור מנהל', 'action', false, false,
  array['staff', 'contractor_user']::user_kind[], 'attendance.view_own', 35);

select app.register_permission('attendance.approve_entry', 'attendance', 'אישור דיווחי נוכחות',
  'אישור או דחייה של משמרות שעובדים דיווחו ידנית', 'action', false, true,
  array['staff']::user_kind[], 'attendance.edit_entry', 65);

-- default_can_edit=false: בלי מפתח האישור אף אחד לא נוגע בעמודות האלה, גם לא
-- בעל attendance.edit_entry שמתקן שעות. שלושתן רשומות ולא רק status, כי
-- "מי אישר ומתי" הוא רישום שצריך להיות בלתי ניתן לזיוף בדיוק כמו האישור
-- עצמו — ופוליסת ה-UPDATE של העובד על השורה שלו נעצרת רק כאן.
select app.register_field('attendance', 'status', 'סטטוס אישור', 'attendance',
  'attendance_entries', 'status', false, true, false, 'attendance.approve_entry', 85);
select app.register_field('attendance', 'reviewed_by', 'מי אישר', 'attendance',
  'attendance_entries', 'reviewed_by', false, true, false, 'attendance.approve_entry', 86);
select app.register_field('attendance', 'reviewed_at', 'מועד האישור', 'attendance',
  'attendance_entries', 'reviewed_at', false, true, false, 'attendance.approve_entry', 87);

insert into kind_permission_defaults (user_kind, permission_key, allowed) values
  ('staff',           'attendance.submit_entry', true),
  ('contractor_user', 'attendance.submit_entry', true)
on conflict (user_kind, permission_key) do nothing;

-- התפקידים הצרים נסגרו ב-p_close_modules על המודול (0011, 0019), ודחייה
-- מפורשת גוברת על implied_by. הם לא היו מקבלים את המפתח החדש בלי השורה הזו.
insert into role_permissions (role_id, permission_key, allowed)
select r.id, 'attendance.submit_entry', true
from permission_roles r
where r.key in ('worker', 'driver', 'team_lead', 'contractor_worker')
on conflict (role_id, permission_key) do update set allowed = true;

-- מי שמנהל את המודול כולו מקבל גם את מפתח האישור. grant_role_module מעניקה
-- לפי המרשם *ברגע הקריאה*, ולכן היא נקראת שוב ולא נסמכת על 0021.
select app.grant_role_module('ops_manager', 'attendance');
select app.grant_role_module('hr', 'attendance');

-- ===== 4. מי מאשר =========================================================
-- app.has עונה על "האם *אני* רשאי". להודעה על דיווח חדש צריך את השאלה
-- ההפוכה — "מי רשאי" — ולכן אותה שרשרת הכרעה בדיוק, מורצת פר-פרופיל.
-- שכפול הלוגיקה כאן הוא מכוון: החלופה היא לפרק את app.has לפונקציה
-- שמקבלת profile_id, ולשכתב איתה כל פוליסה במערכת.

create or replace function app.profiles_with(p_key text)
returns setof uuid language sql stable security definer set search_path = public as $$
  with recursive chain(key, depth) as (
    select p_key, 0
    union all
    select r.implied_by, c.depth + 1
    from chain c
    join permission_registry r on r.key = c.key
    where r.implied_by is not null and c.depth < 8
  ),
  people as (
    select p.id, p.user_kind, p.is_admin,
           coalesce((select array_agg(pr.role_id)
                       from profile_roles pr
                       join permission_roles r on r.id = pr.role_id
                      where pr.profile_id = p.id and r.is_active and r.deleted_at is null),
                    '{}'::uuid[]) as roles
    from profiles p
    where p.is_active and p.deleted_at is null
  ),
  resolved as (
    select pe.id, c.depth, coalesce(
      (select g.allowed from user_permission_grants g
        where g.profile_id = pe.id and g.permission_key = c.key),
      (select bool_or(rp.allowed) from role_permissions rp
        where rp.role_id = any(pe.roles) and rp.permission_key = c.key),
      (select k.allowed from kind_permission_defaults k
        where k.user_kind = pe.user_kind and k.permission_key = c.key),
      (select true from permission_registry r
        where r.key = c.key and r.is_active and r.default_allowed)
    ) as decided
    from people pe cross join chain c
  )
  select pe.id from people pe
  where pe.is_admin
     or coalesce((select rs.decided from resolved rs
                   where rs.id = pe.id and rs.decided is not null
                   order by rs.depth limit 1), false)
$$;

-- ===== 5. חפיפה ============================================================
-- דיווח שנופל על שעות שכבר נרשמו הוא כפל תשלום. רשומה שנדחתה אינה חוסמת:
-- אחרת עובד שדיווח שעה שגויה, נדחה, ובא לתקן — היה חסום ע"י הטעות שלו.

create or replace function app.attendance_overlap(
  p_profile_id uuid, p_from timestamptz, p_to timestamptz, p_exclude uuid default null)
returns uuid language sql stable security definer set search_path = public as $$
  select e.id from attendance_entries e
   where e.profile_id = p_profile_id
     and e.deleted_at is null
     and e.status <> 'rejected'
     and (p_exclude is null or e.id <> p_exclude)
     -- משמרת פתוחה נחשבת תופסת מרגע הכניסה ואילך
     and e.clock_in_at < coalesce(p_to, p_from + interval '1 minute')
     and coalesce(e.clock_out_at, 'infinity'::timestamptz) > p_from
   order by e.clock_in_at
   limit 1
$$;

-- ===== 6. הדיווח ===========================================================
-- שעת סיום היא חובה, ולא מטעמי נוחות: משמרת פתוחה היא מצב שהשעון מנהל
-- (attendance_one_open, סגירה אוטומטית), ודיווח ידני מתאר משמרת שכבר
-- הסתיימה. דיווח פתוח היה חוסם לעובד את השעון עד שמנהל יטפל בו.

create or replace function attendance_submit_entry(
  p_clock_in timestamptz,
  p_clock_out timestamptz,
  p_note text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_me    uuid := app.profile_id();
  v_rules jsonb;
  v_self  jsonb;
  v_max_h numeric;
  v_back  int;
  v_hours numeric;
  v_shift app.planned_shift_row;
  v_clash uuid;
  v_flags text[] := array['manual', 'self_reported'];
  v_date  date;
  v_seq   int;
  v_id    uuid;
  v_name  text;
  r       record;
begin
  perform app.require('attendance.submit_entry');
  if v_me is null then raise exception 'משתמש לא מזוהה' using errcode = '42501'; end if;

  v_rules := app.clock_rules(v_me);
  v_self  := coalesce(v_rules -> 'self_entry', '{}'::jsonb);
  if not coalesce((v_self ->> 'enabled')::boolean, true) then
    raise exception 'דיווח משמרת ידני אינו מופעל במערכת' using errcode = '42501';
  end if;

  if p_clock_in is null then
    raise exception 'חובה להזין שעת התחלה';
  end if;
  if p_clock_out is null then
    raise exception 'חובה להזין שעת סיום — דיווח ידני מתאר משמרת שהסתיימה';
  end if;
  if p_clock_out <= p_clock_in then
    raise exception 'שעת הסיום חייבת להיות אחרי שעת ההתחלה';
  end if;
  -- דקות ספורות של חסד, כדי שעובד שמדווח ברגע שירד מהמשאית לא ייחסם על
  -- הפרש שעונים בין הטלפון לשרת.
  if p_clock_out > now() + interval '5 minutes' then
    raise exception 'לא ניתן לדווח על משמרת שטרם הסתיימה';
  end if;

  v_hours := round((extract(epoch from (p_clock_out - p_clock_in)) / 3600.0)::numeric, 2);
  v_max_h := coalesce((v_self ->> 'max_hours')::numeric, 16);
  if v_hours > v_max_h then
    raise exception 'משמרת מדווחת אינה יכולה לעלות על % שעות', round(v_max_h);
  end if;

  v_back := coalesce((v_self ->> 'max_backdate_days')::int, 14);
  if p_clock_in < now() - make_interval(days => v_back) then
    raise exception 'ניתן לדווח רק על % הימים האחרונים. לתאריך מוקדם יותר יש לפנות למנהל', v_back;
  end if;

  v_clash := app.attendance_overlap(v_me, p_clock_in, p_clock_out);
  if v_clash is not null then
    raise exception 'כבר קיימת רשומת נוכחות שחופפת לשעות האלה';
  end if;

  -- המשמרת המתוכננת נצמדת רק אם הדיווח באמת נופל בתוכה (בתוספת חלון של
  -- שעתיים לכל צד). app.shift_at הייתה מחזירה גם את "הקרובה ביותר", ודיווח
  -- על יום שלא היה בו שיבוץ היה נתלה במשמרת של יום אחר.
  v_date := (p_clock_in at time zone 'Asia/Jerusalem')::date;
  select s.* into v_shift
    from app.planned_shifts(v_me, v_date - 1, v_date + 1) s
   where p_clock_in between s.shift_start - interval '2 hours'
                        and s.shift_end   + interval '2 hours'
   order by abs(extract(epoch from (s.shift_start - p_clock_in)))
   limit 1;

  if v_shift.shift_start is null then
    v_flags := v_flags || 'no_shift'::text;
  else
    v_date := (v_shift.shift_start at time zone 'Asia/Jerusalem')::date;
  end if;

  select coalesce(max(seq), 0) + 1 into v_seq from attendance_entries
   where profile_id = v_me and work_date = v_date and deleted_at is null;

  insert into attendance_entries (
    profile_id, work_date, seq, shift_start, shift_end, planned_hours, work_site, task_ids,
    clock_in_at, clock_out_at, source, status, flags, employee_note, created_by)
  values (
    v_me, v_date, v_seq, v_shift.shift_start, v_shift.shift_end, v_shift.planned_hours,
    v_shift.work_site, coalesce(v_shift.task_ids, '{}'),
    p_clock_in, p_clock_out, 'manual', 'pending', v_flags, nullif(p_note, ''), v_me)
  returning id into v_id;

  select full_name into v_name from profiles where id = v_me;
  for r in select t.id from app.profiles_with('attendance.approve_entry') as t(id) loop
    perform app.notify(r.id, 'attendance_submitted', 'דיווח נוכחות ממתין לאישור',
      v_name || ' דיווח משמרת ב-' || to_char(v_date, 'DD/MM/YYYY') || ' (' ||
      to_char(p_clock_in at time zone 'Asia/Jerusalem', 'HH24:MI') || '–' ||
      to_char(p_clock_out at time zone 'Asia/Jerusalem', 'HH24:MI') || ')',
      'attendance_entry', v_id);
  end loop;

  return jsonb_build_object('ok', true, 'entry_id', v_id, 'status', 'pending',
                            'work_date', v_date, 'hours', v_hours,
                            'flags', to_jsonb(v_flags));
end $$;

-- ===== 7. האישור ===========================================================
-- העטיפה ב-system_write היא אותה עטיפה של attendance_clock_out: status
-- ו-manager_note רשומים ב-field_registry, והטריגר הגנרי אינו מוותר גם
-- ל-security definer. ההרשאה כבר נאכפה בשורה הראשונה, ולכן הכתיבה עצמה
-- אינה צריכה לעבור בו שוב.

create or replace function attendance_review_entry(
  p_id uuid, p_approve boolean, p_note text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_e     attendance_entries;
  v_clash uuid;
  v_prev  boolean;
begin
  perform app.require('attendance.approve_entry');

  select * into v_e from attendance_entries where id = p_id and deleted_at is null;
  if v_e.id is null then
    raise exception 'רשומת הנוכחות לא נמצאה';
  end if;
  if v_e.status <> 'pending' then
    raise exception 'הדיווח כבר טופל';
  end if;
  if not p_approve and coalesce(nullif(p_note, ''), '') = '' then
    raise exception 'דחייה מחייבת נימוק';
  end if;

  -- החפיפה נבדקת שוב ולא רק בהגשה: מאז שהדיווח הוגש יכולה הייתה להיווצר
  -- החתמת שעון על אותן שעות, ואישור עיוור היה משלם עליהן פעמיים.
  if p_approve then
    v_clash := app.attendance_overlap(v_e.profile_id, v_e.clock_in_at, v_e.clock_out_at, v_e.id);
    if v_clash is not null then
      raise exception 'לא ניתן לאשר: קיימת רשומת נוכחות אחרת שחופפת לשעות האלה';
    end if;
  end if;

  v_prev := app.in_system_write();
  perform app.system_write(true);
  update attendance_entries
     set status = case when p_approve then 'approved' else 'rejected' end,
         manager_note = coalesce(nullif(p_note, ''), manager_note),
         reviewed_by = app.profile_id(),
         reviewed_at = now()
   where id = p_id;
  perform app.system_write(v_prev);

  perform app.notify(v_e.profile_id,
    case when p_approve then 'attendance_approved' else 'attendance_rejected' end,
    case when p_approve then 'דיווח הנוכחות אושר' else 'דיווח הנוכחות נדחה' end,
    to_char(v_e.work_date, 'DD/MM/YYYY') ||
      case when nullif(p_note, '') is not null then ' — ' || p_note else '' end,
    'attendance_entry', p_id);

  return jsonb_build_object('ok', true, 'entry_id', p_id,
                            'status', case when p_approve then 'approved' else 'rejected' end);
end $$;

-- משיכת דיווח: כל עוד הוא ממתין, הוא שייך לעובד ולא למערכת. אחרי שאושר או
-- נדחה הוא רשומת נוכחות ככל אחרת, ומחיקתה דורשת attendance.delete.
create or replace function attendance_delete_entry(p_id uuid, p_restore boolean default false)
returns void language plpgsql security definer set search_path = public as $$
declare v_e attendance_entries;
begin
  select * into v_e from attendance_entries where id = p_id;
  if v_e.id is null then
    raise exception 'רשומת הנוכחות לא נמצאה';
  end if;
  if not (not p_restore and v_e.status = 'pending' and v_e.profile_id = app.profile_id()) then
    perform app.require('attendance.delete');
  end if;
  update attendance_entries
     set deleted_at = case when p_restore then null else now() end
   where id = p_id;
end $$;

-- ===== 8. הדוח, מודע לסטטוס ================================================
-- פרמטר חדש מחייב הפלה ויצירה ולא create or replace: תוספת ארגומנט עם
-- ברירת מחדל הייתה יוצרת עומס-יתר שני, וקריאה בחמישה ארגומנטים הופכת
-- לדו-משמעית.

drop function if exists attendance_report(date, date, uuid[], uuid, boolean);

create or replace function attendance_report(
  p_from date default null,
  p_to   date default null,
  p_profile_ids uuid[] default null,
  p_contractor_id uuid default null,
  p_only_flagged boolean default false,
  p_status text[] default null)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_me         uuid    := app.profile_id();
  v_kind       text    := app.user_kind();
  v_admin      boolean := app.is_admin();
  v_all        boolean;
  v_portal     boolean;
  v_contractor uuid    := app.contractor_id();
  v_money_all  boolean;
  v_money_own  boolean;
  v_config     jsonb   := app.attendance_config('attendance.overtime');
  v_from       date    := coalesce(p_from, current_date - 30);
  v_to         date    := coalesce(p_to, current_date);
  v_rows       jsonb;
begin
  if v_me is null then
    return jsonb_build_object('rows', '[]'::jsonb, 'totals', '{}'::jsonb, 'can_see_pay', false);
  end if;
  v_all    := v_admin or (v_kind = 'staff' and app.has('attendance.view_all'));
  v_portal := v_kind = 'contractor_user' and app.has('portal.attendance');
  if not (v_all or v_portal or app.has('attendance.view_own')) then
    raise exception 'אין לך הרשאה לצפות בדוח נוכחות' using errcode = '42501';
  end if;
  v_money_all := v_admin
              or (v_kind = 'staff' and app.has('attendance.view_pay'))
              or (v_kind = 'contractor_user' and app.has('portal.attendance_pay'));
  v_money_own := app.has('attendance.view_own_pay');

  with visible as (
    select e.*, p.full_name, p.contractor_id as p_contractor,
           (e.profile_id = v_me) as is_mine
    from attendance_entries e
    join profiles p on p.id = e.profile_id
    where e.deleted_at is null
      and e.work_date between v_from and v_to
      and (
        e.profile_id = v_me
        or v_all
        or (v_portal and p.contractor_id is not null and p.contractor_id = v_contractor))
      and (p_profile_ids is null or e.profile_id = any(p_profile_ids))
      and (p_contractor_id is null or p.contractor_id = p_contractor_id)
      and (p_status is null or e.status = any(p_status))
      and (not p_only_flagged or coalesce(array_length(e.flags, 1), 0) > 0)
  ),
  -- הצבר השבועי סופר שעות מאושרות בלבד. דיווח שממתין לאישור אינו אמור
  -- לדחוף את המשמרת הבאה אל מעבר לתקרה השבועית לפני שהוכרע.
  weekly as (
    select v.*,
           coalesce(sum(case when v.status = 'approved' then v.actual_hours else 0 end) over (
             partition by v.profile_id, date_trunc('week', v.work_date)
             order by v.clock_in_at
             rows between unbounded preceding and 1 preceding), 0) as week_before
    from visible v
  ),
  computed as (
    select w.*,
           app.attendance_calc(v_config, jsonb_build_object(
             'hours',             coalesce(w.actual_hours, 0),
             'min_hours',         s.min_hours_per_shift,
             'overtime_enabled',  coalesce(s.overtime_enabled, true),
             'hourly_rate',       s.hourly_rate,
             'dow',               extract(dow from w.work_date)::int,
             'week_hours_before', w.week_before)) as pay
    from weekly w
    left join worker_pay_settings s on s.profile_id = w.profile_id
  )
  -- pay מחושב גם לשורה שממתינה לאישור, כי המאשר צריך לדעת מה הוא מאשר.
  -- מה שממתין אינו נספר הוא הסיכומים שלמטה, ולא התצוגה של השורה עצמה.
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',             c.id,
    'profile_id',     c.profile_id,
    'full_name',      c.full_name,
    'contractor_id',  c.p_contractor,
    'work_date',      c.work_date,
    'seq',            c.seq,
    'shift_start',    c.shift_start,
    'shift_end',      c.shift_end,
    'planned_hours',  c.planned_hours,
    'work_site',      c.work_site,
    'task_ids',       to_jsonb(c.task_ids),
    'clock_in_at',    c.clock_in_at,
    'clock_out_at',   c.clock_out_at,
    'actual_hours',   c.actual_hours,
    'in_distance_m',  c.clock_in_distance_m,
    'out_distance_m', c.clock_out_distance_m,
    'raw_clock_in_at',  c.raw_clock_in_at,
    'raw_clock_out_at', c.raw_clock_out_at,
    'source',         c.source,
    'status',         c.status,
    'reviewed_at',    c.reviewed_at,
    'flags',          to_jsonb(c.flags),
    'employee_note',  c.employee_note,
    'manager_note',   c.manager_note,
    'edited_at',      c.edited_at,
    -- הכסף מוסתר ברמת השורה ולא ברמת השאילתה: אותה קריאה משרתת את המנהל
    -- שרואה סכומים ואת רכז המשמרות שרואה רק שעות.
    'pay', case when v_money_all or (c.is_mine and v_money_own)
                then c.pay
                else c.pay - array['hourly_rate', 'total', 'lines'] end)
    order by c.work_date desc, c.clock_in_at desc), '[]'::jsonb)
  into v_rows
  from computed c;

  return jsonb_build_object(
    'rows', v_rows,
    'can_see_pay', v_money_all,
    'totals', jsonb_build_object(
      'entries',        jsonb_array_length(v_rows),
      'pending',        (select count(*) from jsonb_array_elements(v_rows) r
                          where r ->> 'status' = 'pending'),
      'pending_hours',  (select round(coalesce(sum((r ->> 'actual_hours')::numeric), 0), 2)
                          from jsonb_array_elements(v_rows) r
                         where r ->> 'status' = 'pending'),
      'actual_hours',   (select round(coalesce(sum((r ->> 'actual_hours')::numeric), 0), 2)
                          from jsonb_array_elements(v_rows) r
                         where r ->> 'status' = 'approved'),
      'paid_hours',     (select round(coalesce(sum((r #>> '{pay,paid_hours}')::numeric), 0), 2)
                          from jsonb_array_elements(v_rows) r
                         where r ->> 'status' = 'approved'),
      'overtime_hours', (select round(coalesce(sum((r #>> '{pay,overtime_hours}')::numeric), 0), 2)
                          from jsonb_array_elements(v_rows) r
                         where r ->> 'status' = 'approved'),
      'total',          case when v_money_all then
                        (select round(coalesce(sum((r #>> '{pay,total}')::numeric), 0), 2)
                          from jsonb_array_elements(v_rows) r
                         where r ->> 'status' = 'approved') end));
end $$;

-- ===== 9. מסך השעון ========================================================
-- הדיווחים הפתוחים של המשתמש מגיעים באותה קריאה שמציירת את הדף, כדי שלא
-- יידרש סבב נוסף רק כדי לדעת אם יש לו משהו שממתין.

create or replace function attendance_my_status()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_me    uuid := app.profile_id();
  v_open  attendance_entries;
  v_shift app.planned_shift_row;
  v_rules jsonb;
begin
  if v_me is null then return '{}'::jsonb; end if;
  perform app.require('attendance.view_own');
  v_rules := app.clock_rules(v_me);
  select * into v_open from attendance_entries
   where profile_id = v_me and clock_out_at is null and deleted_at is null;
  v_shift := app.shift_at(v_me, now(),
    make_interval(mins => coalesce((v_rules ->> 'early_grace_minutes')::int, 15)));
  return jsonb_build_object(
    'open_entry', case when v_open.id is not null then to_jsonb(v_open) end,
    'shift',      case when v_shift.shift_start is not null then to_jsonb(v_shift) end,
    'rules',      v_rules,
    'can_submit', app.has('attendance.submit_entry'),
    'today',      (select coalesce(jsonb_agg(to_jsonb(e) order by e.clock_in_at), '[]'::jsonb)
                   from attendance_entries e
                   where e.profile_id = v_me and e.deleted_at is null
                     and e.work_date = (now() at time zone 'Asia/Jerusalem')::date),
    -- כולל את מה שנדחה: עובד שדיווח וקיבל "לא" צריך לראות את זה ואת הסיבה,
    -- ולא לגלות בסוף החודש ששעות חסרות.
    'reports',    (select coalesce(jsonb_agg(to_jsonb(e) order by e.clock_in_at desc), '[]'::jsonb)
                   from attendance_entries e
                   where e.profile_id = v_me and e.deleted_at is null
                     and e.source = 'manual' and e.status <> 'approved'
                     and e.work_date >= (now() at time zone 'Asia/Jerusalem')::date - 45));
end $$;

-- ===== 10. anon מחוץ למשטח החדש ============================================

do $$
declare fn text;
begin
  foreach fn in array array[
    'attendance_report(date, date, uuid[], uuid, boolean, text[])',
    'attendance_submit_entry(timestamptz, timestamptz, text)',
    'attendance_review_entry(uuid, boolean, text)',
    'attendance_delete_entry(uuid, boolean)',
    'attendance_my_status()']
  loop
    execute format('revoke execute on function public.%s from anon, public', fn);
  end loop;
end $$;

select app.rebuild_secure_view('attendance_entries');
