-- 0073: קוד שגיאה מתאר מחלקה, לא סיבה
--
-- מהשטח הגיעה תלונה שלחיצה על "כניסה" בשעון הנוכחות אומרת "אין לך הרשאה" —
-- למי שההרשאה שלו תקינה לגמרי. היא לא הייתה תלויה בהרשאות בכלל: הרוב המכריע
-- של המקרים הוא עובד שאין לו כרגע משמרת משובצת (`allow_clock_without_shift`
-- הוא false כברירת מחדל), והשעון סירב — נכון — עם ההודעה 'אין לך משמרת
-- משובצת כרגע'.
--
-- מה שהפך סירוב נכון להודעה שגויה הוא ש-RPC-ים של השעון נשאו `errcode =
-- '42501'` על כל סירוב, גם על כללים עסקיים. ‏42501 הוא `insufficient_privilege`
-- — מה ש-`app.require` מדווח וגם מה שפוליסת RLS מחזירה — ולכן צד הלקוח מיפה
-- אותו, בצדק, ל"אין לך הרשאה לבצע את הפעולה הזו". שש סיבות שונות נכנסו לצינור
-- אחד ויצאו ממנו כתווית אחת, ולא הנכונה.
--
-- הקוד חוזר לתאר מחלקה: ‏42501 נשאר ל-`app.require` ולזהות (משתמש לא מזוהה),
-- וכל כלל עסקי — אין משמרת, משמרת פתוחה, שעון מושבת, מוקדם מדי, מחוץ לרדיוס,
-- חובה לשתף מיקום — נזרק בלי `using errcode`, כלומר `P0001`, כמו שאר
-- הוולידציות ב-`attendance_submit_entry` שכבר עשו זאת נכון.
--
-- הצד השני של אותו תיקון יושב ב-`src/lib/errors.ts`: שם הסדר הפוך עכשיו,
-- וההודעה שנכתבה בגוף הפונקציה קודמת למיפוי לפי קוד. שתי השכבות נחוצות —
-- הקוד כדי שהתווית הגנרית תהיה נכונה כשאין הודעה, והסדר כדי שהודעה שיש
-- תמיד תנצח אותה.
--
-- הגופים כאן מועתקים מהגרסאות האחרונות (`app.check_clock_location` מ-0020,
-- `attendance_clock_in` מ-0023, `attendance_clock_out` מ-0022,
-- `attendance_submit_entry` מ-0024) ללא שינוי, פרט לקודים ולניסוח אחד.

-- ===== 1. בדיקת המיקום ======================================================

create or replace function app.check_clock_location(
  p_rules jsonb, p_lat double precision, p_lng double precision,
  p_accuracy numeric, p_site_lat double precision, p_site_lng double precision,
  out o_distance_m numeric, out o_flags text[])
language plpgsql stable set search_path = public as $$
declare
  v_required boolean := coalesce((p_rules ->> 'requires_location')::boolean, false);
  v_radius   numeric := coalesce((p_rules ->> 'location_radius_m')::numeric, 300);
  v_max_acc  numeric := coalesce((p_rules ->> 'max_accuracy_m')::numeric, 500);
begin
  o_flags := '{}';
  o_distance_m := null;

  if v_required and (p_lat is null or p_lng is null) then
    raise exception 'חובה לאשר שיתוף מיקום כדי להחתים שעון';
  end if;

  if p_lat is null or p_lng is null then return; end if;

  -- לאתר אין קואורדינטות — זה פער נתונים במשרד ולא של העובד, ולכן
  -- ההחתמה מתקבלת ומסומנת במקום להיחסם.
  if p_site_lat is null or p_site_lng is null then
    if v_required then o_flags := o_flags || 'no_site_coords'::text; end if;
    return;
  end if;

  o_distance_m := round((app.haversine_km(p_lat, p_lng, p_site_lat, p_site_lng) * 1000)::numeric, 1);

  if v_required then
    -- דיוק ה-GPS מנוכה לפני ההשוואה: חוסמים רק כשהעובד *מוכח* מחוץ
    -- לרדיוס, ולא כשקריאה גסה מציבה אותו שם.
    if o_distance_m - coalesce(p_accuracy, 0) > v_radius then
      raise exception 'המיקום שלך מרוחק % מ׳ מהאתר (מותר עד % מ׳)',
        round(o_distance_m), round(v_radius);
    end if;
    if coalesce(p_accuracy, 0) > v_max_acc then
      o_flags := o_flags || 'low_accuracy'::text;
    end if;
  end if;
end $$;

-- ===== 2. כניסה =============================================================
--
-- ההודעה על היעדר משמרת מקבלת גם המשך: העובד שקורא אותה עבד בפועל, והנתיב
-- שפתוח בפניו — דיווח משמרת שלא הוחתמה, לאישור מנהל — כבר קיים במסך ממש
-- מתחת לכפתור. הודעה שאומרת רק "לא" מותירה אותו בלי מה לעשות איתה.

create or replace function attendance_clock_in(
  p_lat double precision default null,
  p_lng double precision default null,
  p_accuracy numeric default null,
  p_note text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_me    uuid := app.profile_id();
  v_rules jsonb;
  v_shift app.planned_shift_row;
  v_open  attendance_entries;
  v_wh    warehouses;
  v_grace interval;
  v_auto  int;
  v_dist  numeric;
  v_loc_flags text[];
  v_flags text[] := '{}';
  v_id    uuid;
  v_date  date;
  v_seq   int;
  v_prev  boolean;
begin
  perform app.require('attendance.clock');
  if v_me is null then raise exception 'משתמש לא מזוהה' using errcode = '42501'; end if;

  v_rules := app.clock_rules(v_me);
  if not coalesce((v_rules ->> 'clock_enabled')::boolean, true) then
    raise exception 'שעון הנוכחות מושבת עבורך';
  end if;

  -- משמרת פתוחה שנשכחה נסגרת אוטומטית אחרי הסף, כדי שלא תחסום לנצח.
  v_auto := coalesce((v_rules ->> 'auto_close_after_hours')::int, 16);
  select * into v_open from attendance_entries
   where profile_id = v_me and clock_out_at is null and deleted_at is null;
  if v_open.id is not null then
    if now() - v_open.clock_in_at > make_interval(hours => v_auto) then
      v_prev := app.in_system_write();
      perform app.system_write(true);
      update attendance_entries
         set clock_out_at = clock_in_at + make_interval(hours => v_auto),
             flags = flags || 'auto_closed'::text
       where id = v_open.id;
      perform app.system_write(v_prev);
    else
      raise exception 'כבר נרשמה כניסה למשמרת פתוחה';
    end if;
  end if;

  v_grace := make_interval(mins => coalesce((v_rules ->> 'early_grace_minutes')::int, 15));
  v_shift := app.shift_at(v_me, now(), v_grace);

  if v_shift.shift_start is null then
    if not coalesce((v_rules ->> 'allow_clock_without_shift')::boolean, false) then
      raise exception 'אין לך משמרת משובצת כרגע. אם עבדת בלי שיבוץ, אפשר לדווח משמרת לאישור מנהל';
    end if;
    v_flags := v_flags || 'no_shift'::text;
  elsif now() < v_shift.shift_start - v_grace
        and not coalesce((v_rules ->> 'allow_early_clock_in')::boolean, false) then
    -- התחלה מוקדמת: חסימה, אלא אם הותרה במפורש לעובד הזה.
    raise exception 'לא ניתן להתחיל משמרת לפני השעה %',
      to_char(v_shift.shift_start at time zone 'Asia/Jerusalem', 'HH24:MI');
  end if;

  -- נקודת הייחוס כבר נגזרה במשמרת: המחסן של הלקוח למי שיוצא ממנו, האתר
  -- לכל השאר. אין כאן נפילה ל"המחסן הקרוב" — היא הייתה מתירה החתמה
  -- מהמחסן של לקוח אחר. כשאין מחסן מוגדר, check_clock_location מסמן
  -- no_site_coords ולא חוסם, כמו כל פער נתונים אחר במשרד.
  if v_shift.warehouse_id is not null then
    select * into v_wh from warehouses where id = v_shift.warehouse_id;
    -- רדיוס פר-מחסן גובר על הגלובלי; דריסה אישית של העובד גוברת על שניהם.
    if v_wh.radius_m is not null and (select location_radius_m from worker_pay_settings
                                       where profile_id = v_me) is null then
      v_rules := v_rules || jsonb_build_object('location_radius_m', v_wh.radius_m);
    end if;
  end if;

  select o_distance_m, o_flags into v_dist, v_loc_flags
    from app.check_clock_location(v_rules, p_lat, p_lng, p_accuracy,
                                  v_shift.start_lat, v_shift.start_lng);
  v_flags := v_flags || coalesce(v_loc_flags, '{}');

  v_date := coalesce((v_shift.shift_start at time zone 'Asia/Jerusalem')::date,
                     (now() at time zone 'Asia/Jerusalem')::date);
  select coalesce(max(seq), 0) + 1 into v_seq from attendance_entries
   where profile_id = v_me and work_date = v_date and deleted_at is null;

  insert into attendance_entries (
    profile_id, work_date, seq, shift_start, shift_end, planned_hours, work_site, task_ids,
    clock_in_at, raw_clock_in_at, clock_in_lat, clock_in_lng, clock_in_accuracy_m,
    clock_in_distance_m, flags, employee_note, created_by)
  values (
    v_me, v_date, v_seq, v_shift.shift_start, v_shift.shift_end, v_shift.planned_hours,
    v_shift.work_site, coalesce(v_shift.task_ids, '{}'),
    now(), now(), p_lat, p_lng, p_accuracy, v_dist, v_flags, nullif(p_note, ''), v_me)
  returning id into v_id;

  return jsonb_build_object('ok', true, 'entry_id', v_id, 'distance_m', v_dist,
                            'warehouse', v_wh.name,
                            'flags', to_jsonb(v_flags), 'shift', to_jsonb(v_shift));
end $$;

-- ===== 3. יציאה =============================================================

create or replace function attendance_clock_out(
  p_lat double precision default null,
  p_lng double precision default null,
  p_accuracy numeric default null,
  p_note text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_me    uuid := app.profile_id();
  v_rules jsonb;
  v_entry attendance_entries;
  v_shift app.planned_shift_row;
  v_site_lat double precision;
  v_site_lng double precision;
  v_dist  numeric;
  v_loc_flags text[];
  v_prev  boolean;
begin
  perform app.require('attendance.clock');
  if v_me is null then raise exception 'משתמש לא מזוהה' using errcode = '42501'; end if;
  v_rules := app.clock_rules(v_me);

  select * into v_entry from attendance_entries
   where profile_id = v_me and clock_out_at is null and deleted_at is null;
  if v_entry.id is null then
    raise exception 'לא נמצאה משמרת פתוחה להחתמת יציאה';
  end if;

  -- היציאה נמדדת מול המשמרת של אותו זמן, או הקרובה לה. העבודה נגמרת בשטח
  -- גם למי שיצא מהמחסן, ולכן נקודת הסיום היא מיקום האירוע.
  v_shift := app.shift_at(v_me, now(), make_interval(hours => 2));
  v_site_lat := v_shift.end_lat;
  v_site_lng := v_shift.end_lng;

  select o_distance_m, o_flags into v_dist, v_loc_flags
    from app.check_clock_location(v_rules, p_lat, p_lng, p_accuracy, v_site_lat, v_site_lng);

  -- clock_in_at/clock_out_at רשומות ב-field_registry עם מפתח עריכה
  -- attendance.edit_entry, והטריגר הגנרי אינו מוותר גם ל-security definer.
  v_prev := app.in_system_write();
  perform app.system_write(true);
  update attendance_entries
     set clock_out_at = now(),
         raw_clock_out_at = now(),
         clock_out_lat = p_lat,
         clock_out_lng = p_lng,
         clock_out_accuracy_m = p_accuracy,
         clock_out_distance_m = v_dist,
         flags = flags || coalesce(v_loc_flags, '{}'),
         employee_note = coalesce(nullif(p_note, ''), employee_note)
   where id = v_entry.id;
  perform app.system_write(v_prev);

  return jsonb_build_object('ok', true, 'entry_id', v_entry.id, 'distance_m', v_dist);
end $$;

-- ===== 4. דיווח ידני ========================================================
--
-- כאן רק שורה אחת משתנה: שאר הוולידציות בפונקציה הזאת כבר נזרקו בלי
-- `using errcode`, וזו הייתה החריגה היחידה.

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
    raise exception 'דיווח משמרת ידני אינו מופעל במערכת';
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
