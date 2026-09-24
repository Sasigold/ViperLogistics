-- ‏0198: העובד רואה את השכר שלו בדוח הנוכחות
--
-- ‏"תוודא שעובדים רואים את השכר שלהם בדוח נוכחות."
--
-- ‏`attendance.view_own_pay` ניתן לכל עובד צוות ולכל משתמש קבלן מאז 0019,
-- ו-`attendance_report` אכן מצרפת לשורות שלו את `pay.total`, `pay.bonus`
-- ואת הסיכום `totals.total`. אבל הדגל `can_see_pay` החזיר רק את
-- `v_money_all` — מי שרשאי לראות את הכסף של כולם — והמסך והייצוא מכריעים
-- רק לפיו (הכלל השני ב-exportAttendance: אין הכרעת הרשאה שנייה בדפדפן).
-- כך העובד קיבל את השכר שלו מהשרת ולא ראה אותו בשום מקום.
--
-- התיקון בדגל ולא במסך, כדי שההכרעה תישאר אחת: `can_see_pay` אמת גם כשכל
-- השורות בדוח הן של הקורא והוא מחזיק `view_own_pay`. דוח מעורב — מנהל עם
-- ‏view_all בלי view_pay, או קבלן שרואה את הסגל שלו — נשאר בלי עמודות כסף,
-- כי בשורות של האחרים אין סכום, ועמודה שחציה ריק הייתה נראית כמו "₪0".
-- מנהל כזה שמסנן לעצמו רואה את השכר שלו, בדיוק כמו עובד.
--
-- ההגדרה זהה ל-0166 פרט לדגל.

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
  -- 0075: מי שמקושר לקבלן, ולא מי שנולד כקבלן
  v_portal := app.contractor_id() is not null and app.has('portal.attendance');
  if not (v_all or v_portal or app.has('attendance.view_own')) then
    raise exception 'אין לך הרשאה לצפות בדוח נוכחות' using errcode = '42501';
  end if;
  v_money_all := v_admin
              or (v_kind = 'staff' and app.has('attendance.view_pay'))
              or (app.contractor_id() is not null and app.has('portal.attendance_pay'));
  v_money_own := app.has('attendance.view_own_pay');

  -- pay מחושב גם לשורה שממתינה לאישור, כי המאשר צריך לדעת מה הוא מאשר.
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
    -- ‏0153: שם המחסן שממנו יצאה המשמרת. המשימה הראשונה היא שקובעת — שם
    -- המשמרת התחילה — והמחסן שלה הוא זה של הלקוח, עם דריסה פר-משימה מעליו
    -- (0023). null למשמרת שטח ולדיווח ידני, ואז המסך נופל למה שכן ידוע.
    'work_place', case when c.work_site = 'warehouse' then (
      select wh.name
        from unnest(c.task_ids) tid
        join tasks t on t.id = tid and t.deleted_at is null
        left join customers cu on cu.id = t.customer_id
        join warehouses wh on wh.id = coalesce(t.warehouse_id, cu.warehouse_id)
                          and wh.deleted_at is null
       order by coalesce(t.warehouse_start_time, t.onsite_start_time), t.id
       limit 1) end,
    -- ‏0166: והצד השני — איפה המשמרת נגמרה. מחסן כשחוזרים אליו, שטח כשלא.
    'end_work_site',  ep.place ->> 'work_site',
    'end_work_place', ep.place ->> 'warehouse_name',
    'task_ids',       to_jsonb(c.task_ids),
    'clock_in_at',    c.clock_in_at,
    'clock_out_at',   c.clock_out_at,
    'actual_hours',   c.actual_hours,
    'in_distance_m',  c.clock_in_distance_m,
    'out_distance_m', c.clock_out_distance_m,
    -- ‏0166: הנקודה שנדגמה ברגע ההחתמה. מרחק אומר כמה, ולא לאיזה צד.
    'in_lat',         c.clock_in_lat,
    'in_lng',         c.clock_in_lng,
    'out_lat',        c.clock_out_lat,
    'out_lng',        c.clock_out_lng,
    'raw_clock_in_at',  c.raw_clock_in_at,
    'raw_clock_out_at', c.raw_clock_out_at,
    'source',         c.source,
    'status',         c.status,
    'reviewed_at',    c.reviewed_at,
    'flags',          to_jsonb(c.flags),
    'employee_note',  c.employee_note,
    'manager_note',   c.manager_note,
    -- ‏0084: המיקום במילים מגיע עד הדוח, כי שם המנהל מאשר את הדיווח הידני
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
         v_from, v_to, p_profile_ids, p_contractor_id, p_only_flagged, p_status, 'auto') c
  left join lateral (
    select app.shift_end_place(c.profile_id, c.task_ids) as place) ep on true;

  return jsonb_build_object(
    'rows', v_rows,
    -- ‏0198: גם מי שרואה רק את השכר של עצמו, כשכל הדוח הוא שלו. השורות
    -- כבר נשאו את הסכום שלו (`v_money_own` למטה ב-`pay`), אבל הדגל נשאר
    -- `v_money_all`, והמסך — שמכריע רק לפיו — הסתיר מהעובד את השכר שלו.
    'can_see_pay', v_money_all or (v_money_own and not exists (
                     select 1 from jsonb_array_elements(v_rows) r
                      where (r ->> 'profile_id')::uuid is distinct from v_me)
                   -- דוח ריק של מי שרואה אחרים אינו "הדוח שלו"
                   and (jsonb_array_length(v_rows) > 0 or not (v_all or v_portal))),
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

