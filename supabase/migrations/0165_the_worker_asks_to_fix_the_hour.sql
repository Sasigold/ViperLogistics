-- 0165: העובד מבקש לתקן שעה, והמנהל מכריע
--
-- עד כאן היו לעובד שני מצבים ותו לא: להחתים בשעון, או לדווח משמרת שלא הוחתמה
-- כלל (`attendance_submit_entry`, 0024). מה שלא היה לו הוא הדבר שקורה הכי
-- הרבה בשטח — **השעה על הרשומה הקיימת אינה נכונה**: יצא מהמחסן ב-06:40
-- והחתים 07:10, שכח להחתים יציאה והמשמרת נסגרה אוטומטית על 16 שעות (0020),
-- או שהיא עדיין פתוחה ואין לה שעת סיום בכלל. כל אלה חייבו מנהל שיפתח את
-- הרשומה ויתקן, ועד שיעשה זאת השעות בתלוש שגויות.
--
-- מ-0165 העובד מבקש, והמנהל מכריע. שלוש הכרעות:
--
-- 1. **הבקשה אינה נוגעת בשעות עד שתאושר.** היא יושבת בעמודות `req_*` לצד
--    הרשומה, והרשומה עצמה — הסטטוס שלה, השעות שלה, השכר שלה — נשארת בדיוק
--    כפי שהייתה. זו הסיבה שלא נבחר הנתיב הפשוט של "להפוך את הרשומה ל-pending
--    ולתת ל-`attendance_review_entry` להכריע": דחייה שם כותבת `rejected`, ומשמרת
--    שנדחתה אינה נספרת בכלל — כלומר עובד שביקש לתקן דקה היה מסתכן באיבוד
--    היום כולו. כאן דחייה מוחקת את הבקשה ומשאירה את המשמרת על מכונה.
--
-- 2. **הבקשה נושאת את הזוג המלא.** ‏`req_clock_in_at` תמיד מלא — גם כשכל מה
--    שהעובד רוצה לשנות הוא שעת היציאה — כדי שהמנהל יראה את המשמרת המוצעת
--    כמשמרת, ולא שני שדות שצריך להרכיב בראש. ‏`req_clock_out_at` יכול להישאר
--    ריק, וזה בדיוק המקרה של משמרת פתוחה שרק שעת הכניסה בה שגויה.
--
-- 3. **משמרת פתוחה מקבלת שעת סיום דרך אותה דלת.** ‏`attendance_submit_entry`
--    דורש שעת סיום כי הוא מתאר משמרת שהסתיימה; כאן הרשומה כבר קיימת, ומה
--    שחסר לה הוא הסוף. אישור הבקשה סוגר אותה בשעה שהעובד ביקש. עד האישור
--    היא נשארת פתוחה — כפי שהייתה ממילא — והסגירה האוטומטית של 0020 היא
--    עדיין רשת הביטחון שלא תיתן לה לחסום את השעון לנצח.
--
-- המדידה המקורית נשמרת ב-`raw_clock_in_at`/`raw_clock_out_at` בדיוק כמו
-- בתיקון של מנהל (0084 §5), ולכן תיקון שהתקבל אינו מוחק את מה שהשעון ראה.

-- ===== 1. הבקשה יושבת על הרשומה ===========================================
--
-- חמש עמודות ולא טבלה: לרשומת נוכחות יש בקשת תיקון אחת פתוחה לכל היותר
-- (בקשה שנייה דורסת את הראשונה, כמו טיוטה שנכתבת מחדש), וההכרעה מוחקת אותה.
-- טבלת היסטוריה של בקשות הייתה יומן ביקורת שני לצד `audit_log` שכבר מתעד
-- כל שינוי בשורה הזו.

alter table attendance_entries
  add column if not exists req_clock_in_at  timestamptz,
  add column if not exists req_clock_out_at timestamptz,
  add column if not exists req_note         text,
  add column if not exists req_by           uuid references profiles(id),
  add column if not exists req_at           timestamptz;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'attendance_req_pair') then
    alter table attendance_entries add constraint attendance_req_pair check (
      (req_at is null and req_by is null and req_clock_in_at is null and req_clock_out_at is null)
      or (req_at is not null and req_clock_in_at is not null));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'attendance_req_order') then
    alter table attendance_entries add constraint attendance_req_order check (
      req_clock_out_at is null or req_clock_in_at is null
      or req_clock_out_at > req_clock_in_at);
  end if;
end $$;

comment on column attendance_entries.req_clock_in_at is
  'שעת הכניסה שהעובד מבקש. הרשומה עצמה אינה משתנה עד שמנהל מאשר (0165).';
comment on column attendance_entries.req_clock_out_at is
  'שעת היציאה שהעובד מבקש, או null כשהמשמרת נשארת פתוחה (0165).';

create index if not exists attendance_pending_req_idx on attendance_entries (req_at)
  where req_at is not null and deleted_at is null;

-- ===== 2. המפתח ============================================================
--
-- ‏`implied_by = attendance.submit_entry`: מי שכבר רשאי לדווח משמרת שלא
-- הוחתמה רשאי גם לבקש תיקון של אחת שכן הוחתמה. שתיהן אותה פעולה מבחינת
-- הסיכון — העובד אומר מה קרה, ומנהל מאשר — והנגזרת חוסכת מכל תפקיד קיים
-- שורה חדשה במסך ההרשאות. מי שרוצה להפריד ביניהם כובה את החדש במפורש.

select app.register_permission(
  'attendance.request_correction', 'attendance', 'בקשת תיקון שעות',
  'בקשה לשנות שעת כניסה או יציאה במשמרת שלי, או להשלים שעת סיום חסרה — לאישור מנהל',
  'action', false, false,
  array['staff', 'contractor_user']::user_kind[], 'attendance.submit_entry', 37);

-- ===== 3. ההתראה ===========================================================
--
-- אחת בלבד, לכיוון המנהל. התשובה לעובד נוסעת על `attendance_approved` /
-- `attendance_rejected` שכבר קיימים: מבחינתו זו אותה שאלה ("מה קרה עם מה
-- ששלחתי") ואותו מסך, ושני מתגים נוספים במטריצה היו מבקשים ממנו להחליט על
-- הבחנה שאינה מעניינת אותו. הכותרת בגוף ההתראה היא שאומרת שמדובר בתיקון.

select app.register_notification_type('attendance_correction_requested',
  'עובד ביקש תיקון שעות', 'בקשה לשנות שעת כניסה או יציאה במשמרת קיימת',
  'נוכחות', array['admin','staff'], 'attendance_entry',
  'opt_out', 'opt_out', 'opt_in', 51);

update notification_types set required_permission = 'attendance.approve_entry'
 where key = 'attendance_correction_requested';

-- ===== 4. העובד מבקש ======================================================
--
-- הבדיקות הן אלה של הדיווח הידני (0084 §4), על אותן הגדרות פר-עובד: אורך
-- מרבי, חלון אחורה, ואי-חפיפה לרשומה אחרת. הן חלות על מה ש**מוצע**, כי זה
-- מה שייכתב אם הבקשה תאושר.

create or replace function attendance_request_correction(
  p_id uuid,
  p_clock_in timestamptz,
  p_clock_out timestamptz default null,
  p_note text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_me    uuid := app.profile_id();
  v_e     attendance_entries;
  v_rules jsonb;
  v_self  jsonb;
  v_hours numeric;
  v_max_h numeric;
  v_back  int;
  v_clash uuid;
  v_prev  boolean;
  v_name  text;
  r       record;
begin
  perform app.require('attendance.request_correction');
  if v_me is null then raise exception 'משתמש לא מזוהה' using errcode = '42501'; end if;

  select * into v_e from attendance_entries where id = p_id and deleted_at is null;
  if v_e.id is null then
    raise exception 'רשומת הנוכחות לא נמצאה';
  end if;
  -- שלי בלבד. זו אינה "עריכה בהיקף מצומצם" אלא בקשה, ולכן אין כאן זרוע של
  -- מנהל קבלן: מי שמתקן לאחרים עושה זאת ב-attendance_save_entry.
  if v_e.profile_id <> v_me then
    raise exception 'ניתן לבקש תיקון רק על משמרת שלך' using errcode = '42501';
  end if;
  if v_e.status = 'rejected' then
    raise exception 'משמרת שנדחתה אינה ניתנת לתיקון — יש לפנות למנהל';
  end if;

  v_rules := app.clock_rules(v_me);
  v_self  := coalesce(v_rules -> 'self_entry', '{}'::jsonb);

  if p_clock_in is null then
    raise exception 'חובה להזין שעת כניסה';
  end if;
  if p_clock_out is not null and p_clock_out <= p_clock_in then
    raise exception 'שעת היציאה חייבת להיות אחרי שעת הכניסה';
  end if;
  -- אותן דקות חסד של 0084: הפרש שעונים בין הטלפון לשרת אינו שעה עתידית.
  if p_clock_in > now() + interval '5 minutes'
     or (p_clock_out is not null and p_clock_out > now() + interval '5 minutes') then
    raise exception 'לא ניתן לבקש שעה שטרם הגיעה';
  end if;

  if p_clock_out is not null then
    v_hours := round((extract(epoch from (p_clock_out - p_clock_in)) / 3600.0)::numeric, 2);
    v_max_h := coalesce((v_self ->> 'max_hours')::numeric, 16);
    if v_hours > v_max_h then
      raise exception 'משמרת אינה יכולה לעלות על % שעות', round(v_max_h);
    end if;
  end if;

  v_back := coalesce((v_self ->> 'max_backdate_days')::int, 14);
  if p_clock_in < now() - make_interval(days => v_back) then
    raise exception 'ניתן לבקש תיקון רק על % הימים האחרונים. לתאריך מוקדם יותר יש לפנות למנהל', v_back;
  end if;

  -- חפיפה נבדקת על המוצע ולא על הקיים, והרשומה עצמה מוחרגת: משמרת אינה
  -- חופפת לעצמה. היא תיבדק שוב באישור, כי עד אז יכולה להיווצר אחרת.
  v_clash := app.attendance_overlap(v_me, p_clock_in, p_clock_out, p_id);
  if v_clash is not null then
    raise exception 'השעות המבוקשות חופפות לרשומת נוכחות אחרת שלך';
  end if;

  if p_clock_in = v_e.clock_in_at
     and p_clock_out is not distinct from v_e.clock_out_at then
    raise exception 'לא נעשה שינוי בשעות';
  end if;

  -- ‏`app.attendance_owner_edit_guard` (0027) חוסם לבעל השורה כל עמודה שאינה
  -- ‏`employee_note`, וזו רשימת היתר במכוון: עמודה חדשה נולדת חסומה. העטיפה
  -- כאן היא בדיוק הפטור שהוא מתאר — "כתיבה מתוך RPC שכבר אכף את הכללים שלו"
  -- — ולכן `req_*` אינן מצטרפות לרשימה, ו-PATCH ישיר מ-PostgREST על השורה
  -- ממשיך להיחסם. הדלת היחידה לבקשה היא הפונקציה הזו.
  v_prev := app.in_system_write();
  perform app.system_write(true);
  update attendance_entries
     set req_clock_in_at  = p_clock_in,
         req_clock_out_at = p_clock_out,
         req_note         = nullif(btrim(p_note), ''),
         req_by           = v_me,
         req_at           = now()
   where id = p_id;
  perform app.system_write(v_prev);

  select full_name into v_name from profiles where id = v_me;
  for r in select t.id from app.profiles_with('attendance.approve_entry') as t(id) loop
    perform app.notify(r.id, 'attendance_correction_requested', 'בקשת תיקון שעות ממתינה לאישור',
      v_name || ' ביקש לתקן את המשמרת מ-' || to_char(v_e.work_date, 'DD/MM/YYYY') || ' ל-' ||
      to_char(p_clock_in at time zone 'Asia/Jerusalem', 'HH24:MI') || '–' ||
      coalesce(to_char(p_clock_out at time zone 'Asia/Jerusalem', 'HH24:MI'), 'פתוחה'),
      'attendance_entry', p_id);
  end loop;

  return jsonb_build_object('ok', true, 'entry_id', p_id, 'requested_at', now());
end $$;

revoke execute on function public.attendance_request_correction(uuid, timestamptz, timestamptz, text)
  from anon, public;

-- ===== 5. והוא יכול לחזור בו ===============================================
--
-- מקביל ל-`attendance_delete_entry` על דיווח שממתין: כל עוד איש לא הכריע,
-- מי שביקש יכול למשוך. בלי זה בקשה שנשלחה בטעות הייתה מחייבת מנהל.

create or replace function attendance_cancel_correction(p_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_me   uuid := app.profile_id();
  v_e    attendance_entries;
  v_prev boolean;
begin
  perform app.require('attendance.request_correction');
  select * into v_e from attendance_entries where id = p_id and deleted_at is null;
  if v_e.id is null then
    raise exception 'רשומת הנוכחות לא נמצאה';
  end if;
  if v_e.profile_id <> v_me then
    raise exception 'ניתן לבטל רק בקשה שלך' using errcode = '42501';
  end if;
  if v_e.req_at is null then
    raise exception 'אין בקשת תיקון פתוחה על המשמרת הזו';
  end if;

  -- אותה עטיפה של §4, מאותה סיבה
  v_prev := app.in_system_write();
  perform app.system_write(true);
  update attendance_entries
     set req_clock_in_at = null, req_clock_out_at = null,
         req_note = null, req_by = null, req_at = null
   where id = p_id;
  perform app.system_write(v_prev);

  return jsonb_build_object('ok', true, 'entry_id', p_id);
end $$;

revoke execute on function public.attendance_cancel_correction(uuid) from anon, public;

-- ===== 6. המנהל מכריע =====================================================
--
-- שער ההרשאה זהה ל-`attendance_review_entry` (0091): מפתח משרדי מלא, או מנהל
-- קבלן על עובד מהסגל שלו. הכתיבה עטופה ב-`app.system_write` כי
-- `clock_in_at`/`clock_out_at` רשומות ב-`field_registry` תחת
-- `attendance.edit_entry`, והטריגר הגנרי בודק את *הקורא* — מנהל קבלן שמאשר
-- דרך הפורטל אינו מחזיק את המפתח הזה ואינו אמור להחזיק אותו.

create or replace function attendance_review_correction(
  p_id uuid, p_approve boolean, p_note text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_e     attendance_entries;
  v_clash uuid;
  v_prev  boolean;
  v_out   timestamptz;
begin
  select * into v_e from attendance_entries where id = p_id and deleted_at is null;
  if v_e.id is null then
    raise exception 'רשומת הנוכחות לא נמצאה';
  end if;

  if not app.has('attendance.approve_entry') then
    if not (app.has('portal.approve_attendance')
            and app.contractor_id() is not null
            and exists (select 1 from profiles p
                         where p.id = v_e.profile_id
                           and p.contractor_id = app.contractor_id())) then
      perform app.require('attendance.approve_entry');
    end if;
  end if;

  if v_e.req_at is null then
    raise exception 'אין בקשת תיקון פתוחה על המשמרת הזו';
  end if;
  if not p_approve and coalesce(nullif(p_note, ''), '') = '' then
    raise exception 'דחייה מחייבת נימוק';
  end if;

  -- ריק אינו "השאר פתוחה" אלא "לא ביקשתי לגעת ביציאה": בקשה בלי שעת יציאה
  -- על משמרת סגורה משאירה את שעת היציאה שלה כפי שהיא.
  v_out := coalesce(v_e.req_clock_out_at, v_e.clock_out_at);

  if p_approve then
    if v_out is not null and v_out <= v_e.req_clock_in_at then
      raise exception 'שעת היציאה שברשומה מוקדמת מהכניסה המבוקשת — יש לתקן את שתיהן יחד';
    end if;
    v_clash := app.attendance_overlap(v_e.profile_id, v_e.req_clock_in_at, v_out, p_id);
    if v_clash is not null then
      raise exception 'לא ניתן לאשר: קיימת רשומת נוכחות אחרת שחופפת לשעות האלה';
    end if;
  end if;

  v_prev := app.in_system_write();
  perform app.system_write(true);
  update attendance_entries
     set raw_clock_in_at  = case when p_approve then coalesce(raw_clock_in_at, clock_in_at)
                                 else raw_clock_in_at end,
         raw_clock_out_at = case when p_approve then coalesce(raw_clock_out_at, clock_out_at)
                                 else raw_clock_out_at end,
         clock_in_at  = case when p_approve then v_e.req_clock_in_at else clock_in_at end,
         clock_out_at = case when p_approve then v_out else clock_out_at end,
         flags = case when p_approve and not ('edited' = any(flags))
                      then flags || 'edited'::text else flags end,
         edited_by = case when p_approve then app.profile_id() else edited_by end,
         edited_at = case when p_approve then now() else edited_at end,
         manager_note = coalesce(nullif(p_note, ''), manager_note),
         req_clock_in_at = null, req_clock_out_at = null,
         req_note = null, req_by = null, req_at = null
   where id = p_id;
  perform app.system_write(v_prev);

  perform app.notify(v_e.profile_id,
    case when p_approve then 'attendance_approved' else 'attendance_rejected' end,
    case when p_approve then 'בקשת תיקון השעות אושרה' else 'בקשת תיקון השעות נדחתה' end,
    to_char(v_e.work_date, 'DD/MM/YYYY') ||
      case when nullif(p_note, '') is not null then ' — ' || p_note else '' end,
    'attendance_entry', p_id);

  return jsonb_build_object('ok', true, 'entry_id', p_id, 'approved', p_approve);
end $$;

revoke execute on function public.attendance_review_correction(uuid, boolean, text) from anon, public;

-- ===== 7. הדוח נושא את הבקשה ==============================================
--
-- ‏0153 במלואה, בתוספת מפתח אחד. הבקשה נקראת בשאילתת משנה מ-`attendance_entries`
-- ולא דרך `app.attendance_pay_row` — הטיפוס אינו גדל, ולכן אין `cascade`
-- ואין נגיעה בדשבורד, ברווחיות ובמסך העובד שנשענים על אותה פונקציה. זו
-- בדיוק ההכרעה של 0153 §2.

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
  v_money_all  boolean;
  v_money_own  boolean;
  v_from       date    := coalesce(p_from, current_date - 30);
  v_to         date    := coalesce(p_to, current_date);
  v_rows       jsonb;
begin
  if v_me is null then
    return jsonb_build_object('rows', '[]'::jsonb, 'totals', '{}'::jsonb, 'can_see_pay', false);
  end if;
  v_all    := v_admin or (v_kind = 'staff' and app.has('attendance.view_all'));
  v_portal := app.contractor_id() is not null and app.has('portal.attendance');
  if not (v_all or v_portal or app.has('attendance.view_own')) then
    raise exception 'אין לך הרשאה לצפות בדוח נוכחות' using errcode = '42501';
  end if;
  v_money_all := v_admin
              or (v_kind = 'staff' and app.has('attendance.view_pay'))
              or (app.contractor_id() is not null and app.has('portal.attendance_pay'));
  v_money_own := app.has('attendance.view_own_pay');

  select coalesce(jsonb_agg(jsonb_build_object(
    'id',             c.id,
    'profile_id',     c.profile_id,
    'full_name',      c.full_name,
    'contractor_id',  c.contractor_id,
    'work_date',      c.work_date,
    'seq',            c.seq,
    'shift_start',    c.shift_start,
    'shift_end',      c.shift_end,
    'planned_hours',  c.planned_hours,
    'work_site',      c.work_site,
    'work_place', case when c.work_site = 'warehouse' then (
      select wh.name
        from unnest(c.task_ids) tid
        join tasks t on t.id = tid and t.deleted_at is null
        left join customers cu on cu.id = t.customer_id
        join warehouses wh on wh.id = coalesce(t.warehouse_id, cu.warehouse_id)
                          and wh.deleted_at is null
       order by coalesce(t.warehouse_start_time, t.onsite_start_time), t.id
       limit 1) end,
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
    'clock_in_place',  c.clock_in_place,
    'clock_out_place', c.clock_out_place,
    'edited_at',      c.edited_at,
    'overtime_enabled', c.overtime_enabled,
    -- ‏0165: בקשת תיקון פתוחה, למי שרואה את השורה. היא אינה כסף ואינה סוד —
    -- היא הסיבה שהשעות שעל המסך אולי אינן השעות הנכונות, ומי שקורא את
    -- השורה צריך לדעת אותה לפני שהוא מסתמך עליה.
    'correction', (select case when e.req_at is not null then jsonb_build_object(
                      'clock_in_at',  e.req_clock_in_at,
                      'clock_out_at', e.req_clock_out_at,
                      'note',         e.req_note,
                      'at',           e.req_at) end
                     from attendance_entries e where e.id = c.id),
    'bonus_note',     case when v_money_all or (c.is_mine and v_money_own)
                           then c.bonus_note end,
    'pay', case when v_money_all or (c.is_mine and v_money_own)
                then c.pay
                else c.pay - array['hourly_rate', 'total', 'lines', 'bonus'] end)
    order by c.work_date desc, c.clock_in_at desc), '[]'::jsonb)
  into v_rows
  from app.attendance_pay_rows(
         v_from, v_to, p_profile_ids, p_contractor_id, p_only_flagged, p_status, 'auto') c;

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
      -- ‏0165: כמה שורות ממתינות לתיקון. האריח שסופר "ממתין לאישור" סופר
      -- סטטוס, והבקשה אינה סטטוס — בלי המונה הזה היא הייתה מחכה בלי שאיש
      -- ידע שהיא שם.
      'corrections',    (select count(*) from jsonb_array_elements(v_rows) r
                          where r -> 'correction' <> 'null'::jsonb
                            and r -> 'correction' is not null),
      'bonus',          case when v_money_all or v_money_own then
                        (select round(coalesce(sum((r #>> '{pay,bonus}')::numeric), 0), 2)
                          from jsonb_array_elements(v_rows) r
                         where r ->> 'status' = 'approved') end,
      'total',          case when v_money_all or v_money_own then
                        (select round(coalesce(sum((r #>> '{pay,total}')::numeric), 0), 2)
                          from jsonb_array_elements(v_rows) r
                         where r ->> 'status' = 'approved') end));
end $$;

revoke execute on function public.attendance_report(date, date, uuid[], uuid, boolean, text[])
  from anon, public;

-- ===== 8. והשעון יודע מה תלוי ועומד =======================================
--
-- ‏0159 במלואה, בתוספת `corrections`. ‏`to_jsonb(e)` שבתוך `today` ו-`reports`
-- כבר נושא את עמודות ה-`req_*` החדשות מאליו; מה שנוסף הוא הרשימה שמאפשרת
-- למסך להראות "ביקשת, ממתין" בלי לסרוק את החודש כולו.

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
    'location_required', app.clock_needs_location(v_rules, v_shift, v_open.id is not null),
    'can_submit', app.has('attendance.submit_entry'),
    'can_request_correction', app.has('attendance.request_correction'),
    'today',      (select coalesce(jsonb_agg(to_jsonb(e) order by e.clock_in_at), '[]'::jsonb)
                   from attendance_entries e
                   where e.profile_id = v_me and e.deleted_at is null
                     and e.work_date = (now() at time zone 'Asia/Jerusalem')::date),
    'reports',    (select coalesce(jsonb_agg(to_jsonb(e) order by e.clock_in_at desc), '[]'::jsonb)
                   from attendance_entries e
                   where e.profile_id = v_me and e.deleted_at is null
                     and e.source = 'manual' and e.status <> 'approved'
                     and e.work_date >= (now() at time zone 'Asia/Jerusalem')::date - 45),
    -- בקשות התיקון הפתוחות שלי, באותו חלון של 45 יום. הן מוצגות בשעון כדי
    -- שהעובד לא ישלח את אותה בקשה פעמיים בזמן שהראשונה ממתינה.
    'corrections', (select coalesce(jsonb_agg(to_jsonb(e) order by e.clock_in_at desc), '[]'::jsonb)
                    from attendance_entries e
                    where e.profile_id = v_me and e.deleted_at is null
                      and e.req_at is not null
                      and e.work_date >= (now() at time zone 'Asia/Jerusalem')::date - 45));
end $$;

comment on function attendance_my_status() is
  'מצב השעון של המשתמש: החתמה פתוחה, משמרת מתוכננת, דרישת מיקום, דיווחים ובקשות תיקון (0165).';

revoke execute on function public.attendance_my_status() from anon, public;
