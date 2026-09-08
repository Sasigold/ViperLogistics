-- 0153: השורה בדוח אומרת איפה המשמרת הייתה
--
-- מתחת לשעת הכניסה, בכל שורה בדוח הנוכחות, יש שורת מיקום. עד כאן היא הציגה
-- אחד משלושה קבועים שנכתבו בקוד המסך: "שטח", "מחסן", ו — כשלא היה ידוע דבר
-- — "מרכז לוגיסטי". השניים האחרונים הם מה שהיה אמור להיות שם שם המחסן
-- (ההערה בקוד המסך אומרת זאת במפורש), והשלישי הוא מלל שהמציא מיקום.
--
-- הקבוע הזה נפל בדיוק על הדיווח הידני. שם `work_site` הוא null — אין משמרת
-- משובצת שממנה לגזור אותו — ולכן כל משמרת שעובד דיווח בעצמו הוצגה כאילו
-- הייתה ב"מרכז לוגיסטי", בזמן שהמיקום האמיתי שלה כתוב על השורה מאז 0084:
-- `clock_in_place` הוא שדה חובה בדיווח ידני, כי אין שם GPS לאמת מולו.
--
-- שתי החלטות:
--
-- 1. **המחסן נגזר כאן ולא נשמר על הרשומה.** ההחתמה אינה מציינת מחסן — היא
--    מודדת מרחק מולו ושומרת את המרחק — ולכן "מאיזה מחסן יצאה המשמרת" היא
--    שאלה על המשימות שהרכיבו אותה. הגזירה היא בדיוק זו של `app.planned_shifts`
--    מאז 0023: המחסן של הלקוח, ודריסה פר-משימה מעליו.
--
-- 2. **רק `attendance_report` משתנה, לא הטיפוס.** `app.attendance_pay_rows`
--    כבר מחזירה את `task_ids` ואת `work_site`, והשם נגזר מהם כאן — ולכן אין
--    `alter type ... cascade` ואין נגיעה בדשבורד, ברווחיות ובמסך העובד,
--    ששלושתם נשענים על אותה פונקציה ואינם מציגים שורת מיקום.
--
-- המיקום אינו כסף, ולכן הוא אינו מגודר: הוא נוסע לצד `clock_in_place`
-- שכבר מגיע לכל מי שרשאי לקרוא את השורה.

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
  -- מה שממתין אינו נספר הוא הסיכומים שלמטה, ולא התצוגה של השורה עצמה.
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
    -- ‏0153: שם המחסן שממנו יצאה המשמרת, למשמרת שיצאה ממחסן. המשימה
    -- הראשונה היא שקובעת — שם המשמרת התחילה — והמחסן שלה הוא זה של הלקוח,
    -- עם דריסה פר-משימה מעליו (0023). null למשמרת שטח ולדיווח ידני, ואז
    -- המסך נופל למה שכן ידוע: המיקום שנכתב בדיווח, או סוג האתר.
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
    -- ‏0084: המיקום במילים מגיע עד הדוח, כי שם המנהל מאשר את הדיווח הידני
    'clock_in_place',  c.clock_in_place,
    'clock_out_place', c.clock_out_place,
    'edited_at',      c.edited_at,
    -- לא כסף אלא כלל: אם השעות הנוספות חלות על העובד הזה בכלל. אין כאן מה
    -- להסתיר — הוא נגזר מאותה הגדרה שהעובד רואה בכרטיס שלו.
    'overtime_enabled', c.overtime_enabled,
    -- הנימוק הולך עם הסכום: מי שאינו רואה כמה, אינו רואה גם למה. הוא מגודר
    -- בתנאי הכסף ולא נמצא ליד manager_note שכולם רואים.
    'bonus_note',     case when v_money_all or (c.is_mine and v_money_own)
                           then c.bonus_note end,
    -- הכסף מוסתר ברמת השורה ולא ברמת השאילתה: אותה קריאה משרתת את המנהל
    -- שרואה סכומים ואת רכז המשמרות שרואה רק שעות. bonus מצטרף לרשימה כי
    -- הוא סכום בשקלים ולא נתון תפעולי.
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
      -- סיכום משלו ולא רק בלוע ב-total: המסך והייצוא צריכים להראות כמה מהסכום
      -- אינו שעות, בלי לגזור אותו מהפרש. הוא *כלול* ב-total ואינו נוסף עליו.
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
