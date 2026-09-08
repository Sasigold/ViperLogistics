-- 0159: מקום בלי קואורדינטות אינו דורש מיקום — הוא רק אינו מאמת אותו
--
-- מ-0157 אפשר להקליד מיקום ידנית כשהחיפוש אינו מוצא אותו ("מתחם האירועים
-- בכניסה לקיבוץ, ליד השער הצפוני"), והקואורדינטות שלצידו הן שדה **לא חובה**.
-- אירוע כזה מגיע לשעון בלי נקודת ייחוס, וזה בדיוק המצב שהחוק הקיים טיפל בו
-- חצי-נכון:
--
--   * ‏`check_clock_location` כבר לא חסמה — אתר בלי קואורדינטות מתקבל
--     ומסומן `no_site_coords`, כפער נתונים במשרד ולא כאשמת העובד (0073).
--   * אבל השורה שלפניה עדיין דרשה **קריאת GPS**: "קריאה חסרה נדחית תמיד".
--     כלומר העובד נדרש לאשר מיקום, להמתין לנעילת לוויין, ולעבור טיים-אאוט —
--     הכול כדי שהערך שיתקבל יושלך מיד אחר כך, כי אין מולו מה להשוות.
--
-- באולם בקומת מרתף, בשדה בלי קליטה, או בטלפון שהרשאת המיקום שלו נחסמה
-- פעם אחת בעבר, ההחתמה פשוט לא נכנסה. "מכל מקום" שדורש GPS אינו מכל מקום.
--
-- **מה שמשתנה: כשאין נקודת ייחוס, אין דרישת מיקום.** לא הקריאה ולא המרחק.
-- ‏`no_site_coords` נשאר — הוא מה שאומר למנהל שהמשמרת הזו לא אומתה — ובאותה
-- נשימה נשמר גם ההפך: אתר או מחסן **שיש** להם קואורדינטות ממשיכים לדרוש
-- קריאה, ומי שאינו מוכן לשתף מיקום אינו מקבל בכך פטור.
--
-- **השעות לא זזו.** הגדר המקום נפתח, גדר הזמן עומדת: `attendance_clock_in`
-- ממשיכה לדרוש משמרת משובצת (אלא אם הותר אחרת לעובד) ולחסום כניסה לפני
-- תחילתה. כשהמיקום אינו מאמת דבר, השעות הן מה שמאמת — ולכן דווקא כאן חשוב
-- שהן יישארו כפי שהן.

-- ===== 1. הקריאה נדרשת רק כשיש מול מה להשוות אותה ==========================
--
-- ההיפוך היחיד ביחס ל-0073 הוא הסדר: קודם נשאלת השאלה "יש נקודת ייחוס?",
-- ורק אחריה "יש קריאה?". שאר הגוף — ניכוי הדיוק לפני ההשוואה, דגל הדיוק
-- הנמוך, והמרחק שנשמר על השורה — זהה מילה במילה.

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

  -- לאתר אין קואורדינטות — זה פער נתונים במשרד ולא של העובד, ולכן ההחתמה
  -- מתקבלת ומסומנת. גם קריאה אינה נדרשת: אין מולה מה להשוות, והדרישה
  -- הייתה חוסמת החתמה שממילא לא הייתה נבדקת.
  if p_site_lat is null or p_site_lng is null then
    if v_required then o_flags := o_flags || 'no_site_coords'::text; end if;
    return;
  end if;

  if v_required and (p_lat is null or p_lng is null) then
    raise exception 'חובה לאשר שיתוף מיקום כדי להחתים שעון';
  end if;

  if p_lat is null or p_lng is null then return; end if;

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

comment on function app.check_clock_location(jsonb, double precision, double precision,
                                             numeric, double precision, double precision) is
  'בדיקת מיקום ההחתמה. בלי נקודת ייחוס אין דרישה ואין חסימה — רק דגל (0159).';

-- ===== 2. אותה שאלה, לפני שהעובד לוחץ =====================================
--
-- המסך אינו יכול לגזור את זה בעצמו בלי לשכפל את ההכרעה, ושכפול כאן פירושו
-- מסך שמבקש GPS כשהשרת לא ידרוש אותו — או, גרוע יותר, מסך ששולח בלי מיקום
-- והשרת דוחה. התשובה נגזרת פעם אחת, כאן, ונשלחת לשעון בסטטוס.
--
-- הכניסה נמדדת מול נקודת ההתחלה (המחסן למי שיוצא ממנו, האתר לכל השאר),
-- והיציאה מול נקודת הסיום — ולמי שיצא מהמחסן גם מול המחסן שאליו חזר (0082).
-- לכן ביציאה מספיקה אחת מהשתיים כדי שהקריאה תידרש.

create or replace function app.clock_needs_location(
  p_rules jsonb, p_shift app.planned_shift_row, p_clocking_out boolean)
returns boolean language sql stable set search_path = public as $$
  select coalesce((p_rules ->> 'requires_location')::boolean, false)
     and case
           when p_clocking_out then
             (p_shift.end_lat is not null and p_shift.end_lng is not null)
             or (p_shift.work_site = 'warehouse'
                 and p_shift.start_lat is not null and p_shift.start_lng is not null)
           else p_shift.start_lat is not null and p_shift.start_lng is not null
         end
$$;

comment on function app.clock_needs_location(jsonb, app.planned_shift_row, boolean) is
  'האם ההחתמה הבאה תדרוש קריאת מיקום — כלומר האם יש בכלל מול מה לאמת (0159).';

-- ===== 3. היציאה בוחרת נקודת ייחוס גם כשאין קריאה =========================
--
-- הגוף מ-0110 במלואו, ובו שינוי אחד: בחירת "הקרובה מבין השתיים" דורשת
-- קריאה כדי להשוות, ובלעדיה השורה הזו דילגה על עצמה והשאירה את הייחוס על
-- `end_lat` — שהוא null בדיוק במקרה שלנו. התוצאה הייתה פטור למי שיצא
-- ממחסן **שיש** לו קואורדינטות, רק משום שלאירוע שבסופו אין. עכשיו, כשאין
-- קריאה, המחסן משמש כנקודת הייחוס, והדרישה נשארת על כנה.

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
  v_d_site numeric;
  v_d_wh   numeric;
begin
  perform app.require('attendance.clock');
  if v_me is null then raise exception 'משתמש לא מזוהה' using errcode = '42501'; end if;
  v_rules := app.clock_rules(v_me);

  select * into v_entry from attendance_entries
   where profile_id = v_me and clock_out_at is null and deleted_at is null;
  if v_entry.id is null then
    raise exception 'לא נמצאה משמרת פתוחה להחתמת יציאה';
  end if;

  -- היציאה נמדדת מול המשמרת של אותו זמן, או הקרובה לה.
  v_shift := app.shift_at(v_me, now(), make_interval(hours => 2));
  v_site_lat := v_shift.end_lat;
  v_site_lng := v_shift.end_lng;

  -- מי שיצא מהמחסן מסיים באחת משתי נקודות: בשטח, או במחסן שאליו חזר.
  -- נבחרת הקרובה מביניהן, ובלי לוותר על כלום — מי שרחוק משתיהן עדיין נחסם.
  if v_shift.work_site = 'warehouse'
     and v_shift.start_lat is not null and v_shift.start_lng is not null then
    if p_lat is null or p_lng is null then
      -- אין מה להשוות, ולכן אין מה לבחור: המחסן הוא הייחוס, וההחתמה בלי
      -- מיקום נדחית כמו בכל אתר שיש לו נקודה (0159).
      if v_site_lat is null or v_site_lng is null then
        v_site_lat := v_shift.start_lat;
        v_site_lng := v_shift.start_lng;
      end if;
    else
      v_d_wh := app.haversine_km(p_lat, p_lng, v_shift.start_lat, v_shift.start_lng);
      v_d_site := case when v_site_lat is null or v_site_lng is null then null
                       else app.haversine_km(p_lat, p_lng, v_site_lat, v_site_lng) end;
      if v_d_site is null or v_d_wh < v_d_site then
        v_site_lat := v_shift.start_lat;
        v_site_lng := v_shift.start_lng;
      end if;
    end if;
  end if;

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

  perform app.notify_clock_event(v_me, 'attendance_clock_out', v_entry.id, false);

  return jsonb_build_object('ok', true, 'entry_id', v_entry.id, 'distance_m', v_dist);
end $$;

-- ===== 4. מסך השעון מקבל את התשובה מראש ===================================
--
-- הגוף מ-0024 במלואו, בתוספת מפתח אחד. ‏`rules.requires_location` נשאר בפלט
-- כפי שהוא — הוא ההגדרה שנקבעה לעובד, וההסבר במסך נשען עליה — ולצידו יושבת
-- עכשיו התשובה לשאלה המעשית: האם *ההחתמה הבאה* תדרוש קריאה. היא נגזרת
-- מהמשמרת שנמצאה ומכיוון ההחתמה (משמרת פתוחה => יציאה), כדי שהמסך לא ינחש.

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

comment on function attendance_my_status() is
  'מצב השעון של המשתמש, ובכללו האם ההחתמה הבאה תדרוש קריאת מיקום (0159).';

-- ‏anon מחוץ למשטח, כמו בכל הצהרה מחדש של ה-RPC-ים האלה (0024, 0126).
revoke execute on function public.attendance_my_status() from anon, public;
revoke execute on function public.attendance_clock_out(double precision, double precision,
                                                       numeric, text) from anon, public;
