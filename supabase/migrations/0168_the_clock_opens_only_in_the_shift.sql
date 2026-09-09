-- ‏0168: הכניסה נפתחת רק כשיש משמרת עכשיו
--
-- ‏"עובד או קבלן יכול להחתים כניסה רק אם יש לו משמרת בזמן הזה." זה הכלל
-- שהמערכת התכוונה לו מאז 0020, וגם אמרה אותו במפורש (0159: "משמרת משובצת
-- עדיין נדרשת") — אלא שהוא נאכף רק בקצה אחד.
--
-- ‏`app.shift_at` היא, לפי הגדרתה, "המשמרת שהחלון שלה מכיל את הרגע, **ואם
-- אין — הקרובה ביותר**". הנפילה הזו נכונה בהחתמת יציאה, שבה השאלה היא מול
-- איזו נקודה למדוד מישהו שכבר בפנים; בכניסה היא הפכה את השער לחצי שער:
--
--   * ‏`shift_start is null` תפס רק את מי שאין לו **שום** משמרת ביום שלפני,
--     בזה ובזה שאחריו. די בשיבוץ אחד בטווח הזה כדי שהענף לא ייגע בו.
--   * הענף השני חסם רק את מי שמוקדם מדי (`now() < shift_start - grace`).
--
-- ובין שני אלה נשארה פרוצה כל הצד המאוחר של הציר. משמרת של 08:00–14:00
-- פתחה את השעון ב-19:00 באותו ערב, ומשמרת של אתמול פתחה אותו היום — בשני
-- המקרים `shift_at` החזירה אותה כ"קרובה ביותר", `now()` כבר גדול
-- מ-`shift_start`, ואף אחד משני הענפים לא ירה. ההחתמה נכנסה, נצמדה למשמרת
-- שכבר נגמרה, ונרשמה על `work_date` שלה — כלומר גם השעות וגם היום היו של
-- משמרת אחרת. עובד שנשאר בשטח וביקש להחתים נוכחות שאין לה שיבוץ לא נחסם,
-- ומי שרצה לפתוח משמרת שנייה על גב הראשונה יכול היה.
--
-- **מה שמשתנה: הכניסה נשאלת "יש משמרת *עכשיו*?", ולא "יש משמרת בסביבה?".**
-- החלון הוא בדיוק זה של `shift_at` — `shift_start - grace` עד
-- ‏`shift_end + grace` — ולכן "עכשיו" אומר כאן את אותו הדבר שהוא אומר בכל
-- שאר המערכת. מי שאין לו כזו אינו מחתים, ושתי הדלתות שהיו פתוחות לו נשארות
-- פתוחות בדיוק כפי שהיו: ההגדרות `allow_early_clock_in` ו-
-- ‏`allow_clock_without_shift` שנקבעות פר-עובד, ומעליהן `attendance_submit_entry`
-- — דיווח משמרת לאישור מנהל, שהוא הנתיב שנבנה למקרה הזה עצמו (0024).
--
-- **וההכרעה נגזרת פעם אחת.** ‏`app.clock_in_gate` היא מקור האמת: היא זו
-- שהחתמה עוברת דרכה, והיא זו ש-`attendance_my_status` שואלת כדי שהמסך יידע
-- אם לצייר כפתור פעיל. בדיקה שהייתה נכתבת שנית בדפדפן הייתה נפרדת ממנה
-- ביום שבו אחת מהשתיים תשתנה — וגרוע מזה, היא הייתה קוסמטית: הטבלה חשופה
-- דרך PostgREST, והשער האמיתי הוא ה-RPC.

-- ===== 1. שלוש שאלות על ציר הזמן ==========================================
--
-- ‏`shift_at` ממשיכה להיות מה שהיא — היציאה נשענת עליה, ושם "הקרובה ביותר"
-- היא התשובה הנכונה. מה שנוסף כאן הן שלוש השאלות שהיא בלעה לתוך תשובה
-- אחת: מה מכיל את הרגע, מה בא אחריו, ומה נגמר לפניו.

create or replace function app.shift_covering(
  p_profile_id uuid, p_at timestamptz, p_grace interval)
returns app.planned_shift_row
language plpgsql stable security definer set search_path = public as $$
declare
  v_row  app.planned_shift_row;
  v_from date := (p_at at time zone 'Asia/Jerusalem')::date - 1;
  v_to   date := (p_at at time zone 'Asia/Jerusalem')::date + 1;
begin
  select s.* into v_row
    from app.planned_shifts(p_profile_id, v_from, v_to) s
   where p_at between s.shift_start - p_grace and s.shift_end + p_grace
   order by s.shift_start
   limit 1;
  return v_row;
end $$;

comment on function app.shift_covering(uuid, timestamptz, interval) is
  'המשמרת שהרגע הזה נמצא בתוכה, עם חסד בשני קצותיה. בלי נפילה ל"הקרובה" (0168).';

create or replace function app.shift_next(p_profile_id uuid, p_at timestamptz)
returns app.planned_shift_row
language plpgsql stable security definer set search_path = public as $$
declare
  v_row  app.planned_shift_row;
  v_from date := (p_at at time zone 'Asia/Jerusalem')::date - 1;
  v_to   date := (p_at at time zone 'Asia/Jerusalem')::date + 1;
begin
  select s.* into v_row
    from app.planned_shifts(p_profile_id, v_from, v_to) s
   where s.shift_start > p_at
   order by s.shift_start
   limit 1;
  return v_row;
end $$;

comment on function app.shift_next(uuid, timestamptz) is
  'המשמרת הבאה שטרם התחילה, בחלון של יממה לכל צד (0168).';

create or replace function app.shift_prev(p_profile_id uuid, p_at timestamptz)
returns app.planned_shift_row
language plpgsql stable security definer set search_path = public as $$
declare
  v_row  app.planned_shift_row;
  v_from date := (p_at at time zone 'Asia/Jerusalem')::date - 1;
  v_to   date := (p_at at time zone 'Asia/Jerusalem')::date + 1;
begin
  select s.* into v_row
    from app.planned_shifts(p_profile_id, v_from, v_to) s
   where s.shift_end < p_at
   order by s.shift_end desc
   limit 1;
  return v_row;
end $$;

comment on function app.shift_prev(uuid, timestamptz) is
  'המשמרת האחרונה שכבר נגמרה, בחלון של יממה לכל צד (0168).';

-- ===== 2. השעה שנאמרת לעובד ===============================================
--
-- שעה בלבד כשמדובר באותו יום, ושעה עם תאריך כשלא. זו הכרעת ניסוח ולא
-- חישוב, ולכן היא יושבת בפונקציה קטנה משלה ולא בתוך שלושה `format`.

create or replace function app.clock_when(p_at timestamptz, p_ref timestamptz)
returns text language sql stable set search_path = public as $$
  select to_char(p_at at time zone 'Asia/Jerusalem',
                 case when (p_at  at time zone 'Asia/Jerusalem')::date
                         = (p_ref at time zone 'Asia/Jerusalem')::date
                      then 'HH24:MI' else 'HH24:MI, DD/MM' end)
$$;

comment on function app.clock_when(timestamptz, timestamptz) is
  'שעה לעובד: בלי תאריך כשהיא של אותו יום, ועם תאריך כשלא (0168).';

-- ===== 3. השער ============================================================
--
-- פונקציה טהורה שאינה כותבת דבר, ומחזירה ארבעה דברים: לאיזו משמרת ההחתמה
-- תיצמד, אילו דגלים היא תישא, ואם היא נחסמת — למה ומה נאמר לעובד. ה-RPC
-- מריץ אותה ומרים חריגה; המסך מריץ אותה ומצייר לפיה. אין כאן שני מימושים.
--
-- סדר הענפים הוא ההכרעה כולה:
--
--   1. **שעון מושבת** — לפני הכול, כמו מאז 0020.
--   2. **יש משמרת עכשיו** — היא נפתחת, וזה המקרה השכיח.
--   3. **הותר לו להתחיל מוקדם** — הוא נצמד למשמרת **הבאה**, ולא ל"קרובה
--      ביותר". ההבדל הוא בדיוק מה שתיקנו: משמרת שנגמרה אינה משמרת שמתחילים
--      בה מוקדם, וההיתר הזה מדבר על קדימה בלבד.
--   4. **הותר לו להחתים בלי שיבוץ** — ההחתמה נכנסת בלי משמרת, מסומנת
--      ‏`no_shift`. ‏0020 הצמידה אותו לשורת המשמרת של "הקרובה ביותר" גם
--      כשהיא לא הייתה שלו — כלומר שאלה ממנה שעות מתוכננות, יום עבודה
--      ואיחור. עכשיו הרשומה אומרת את האמת: אין משמרת, ולכן אין מולה איחור
--      (0084) ויום העבודה הוא היום עצמו.
--   5. אחרת — סירוב, והשאלה היחידה שנשארה היא מה בדיוק להגיד.

create or replace function app.clock_in_gate(
  p_profile_id uuid,
  p_at timestamptz,
  out o_shift app.planned_shift_row,
  out o_flags text[],
  out o_reason text,
  out o_message text)
language plpgsql stable security definer set search_path = public as $$
declare
  v_rules jsonb    := app.clock_rules(p_profile_id);
  v_grace interval := make_interval(mins =>
                        coalesce((v_rules ->> 'early_grace_minutes')::int, 15));
  v_next  app.planned_shift_row;
  v_prev  app.planned_shift_row;
  v_to_next   interval;
  v_from_prev interval;
begin
  o_flags := '{}';

  if not coalesce((v_rules ->> 'clock_enabled')::boolean, true) then
    o_reason  := 'clock_disabled';
    o_message := 'שעון הנוכחות מושבת עבורך';
    return;
  end if;

  o_shift := app.shift_covering(p_profile_id, p_at, v_grace);
  if o_shift.shift_start is not null then return; end if;

  v_next := app.shift_next(p_profile_id, p_at);
  v_prev := app.shift_prev(p_profile_id, p_at);

  if v_next.shift_start is not null
     and coalesce((v_rules ->> 'allow_early_clock_in')::boolean, false) then
    o_shift := v_next;
    return;
  end if;

  if coalesce((v_rules ->> 'allow_clock_without_shift')::boolean, false) then
    o_flags := array['no_shift'];
    return;
  end if;

  -- הגבול הקרוב הוא שקובע מה נאמר: מי שהמשמרת שלו נגמרה לפני עשרים דקות
  -- צריך לשמוע עליה, ולא על זו של מחר בבוקר. השעה נאמרת עם תאריך כשהיא
  -- אינה של היום — "לפני השעה 08:00" על משמרת של מחר נקרא כמו עוד שעה.
  v_to_next   := case when v_next.shift_start is not null
                      then v_next.shift_start - p_at end;
  v_from_prev := case when v_prev.shift_end is not null
                      then p_at - v_prev.shift_end end;

  if v_from_prev is not null and (v_to_next is null or v_from_prev <= v_to_next) then
    o_reason  := 'shift_ended';
    o_message := format(
      'המשמרת שלך הסתיימה ב-%s. אם עבדת מעבר לה, אפשר לדווח משמרת לאישור מנהל',
      app.clock_when(v_prev.shift_end, p_at));
  elsif v_to_next is not null then
    o_reason  := 'too_early';
    o_message := format('לא ניתן להתחיל משמרת לפני השעה %s',
                        app.clock_when(v_next.shift_start, p_at));
  else
    o_reason  := 'no_shift';
    o_message := 'אין לך משמרת משובצת כרגע. אם עבדת בלי שיבוץ, '
              || 'אפשר לדווח משמרת לאישור מנהל';
  end if;
end $$;

comment on function app.clock_in_gate(uuid, timestamptz) is
  'האם מותר להחתים כניסה עכשיו, לאיזו משמרת היא תיצמד, ואם לא — למה (0168).';

-- ===== 4. ההחתמה ==========================================================
--
-- הגוף מ-0110 במלואו, ובו שינוי אחד: שלוש השורות שגזרו את המשמרת ואת
-- החסימות הוחלפו בקריאה אחת לשער. סדר הבדיקות נשמר בכוונה — "שעון מושבת"
-- לפני "כבר נרשמה כניסה", ושתיהן לפני שאלת המשמרת — כדי שהעובד ימשיך לקבל
-- את אותה הודעה על אותו מצב. השער טהור, ולכן קריאה מוקדמת שלו אינה עולה
-- דבר.

create or replace function attendance_clock_in(
  p_lat double precision default null,
  p_lng double precision default null,
  p_accuracy numeric default null,
  p_note text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_me    uuid := app.profile_id();
  v_rules jsonb;
  v_gate  record;
  v_shift app.planned_shift_row;
  v_open  attendance_entries;
  v_wh    warehouses;
  v_auto  int;
  v_dist  numeric;
  v_loc_flags text[];
  v_flags text[] := '{}';
  v_id    uuid;
  v_date  date;
  v_seq   int;
  v_prev  boolean;
  v_late  boolean;
begin
  perform app.require('attendance.clock');
  if v_me is null then raise exception 'משתמש לא מזוהה' using errcode = '42501'; end if;

  v_rules := app.clock_rules(v_me);
  select * into v_gate from app.clock_in_gate(v_me, now());

  if v_gate.o_reason = 'clock_disabled' then
    raise exception '%', v_gate.o_message;
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

  -- ‏0168: אין משמרת עכשיו — אין כניסה. הנוסח מגיע מהשער, כדי שמה שהמסך
  -- הראה שנייה לפני הלחיצה יהיה מה שהשרת אומר עליה.
  if v_gate.o_reason is not null then
    raise exception '%', v_gate.o_message;
  end if;

  v_shift := v_gate.o_shift;
  v_flags := v_flags || coalesce(v_gate.o_flags, '{}');

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

  v_late := v_shift.shift_start is not null
        and now() > v_shift.shift_start + make_interval(mins =>
              coalesce((select c.lateness_grace_minutes
                          from profiles p
                          join contractor_workers cw on cw.id = p.contractor_worker_id
                          join contractors c on c.id = cw.contractor_id
                         where p.id = v_me), 0));
  perform app.notify_clock_event(v_me, 'attendance_clock_in', v_id, v_late);

  return jsonb_build_object('ok', true, 'entry_id', v_id, 'distance_m', v_dist,
                            'warehouse', v_wh.name,
                            'flags', to_jsonb(v_flags), 'shift', to_jsonb(v_shift));
end $$;

comment on function attendance_clock_in(double precision, double precision, numeric, text) is
  'החתמת כניסה. נפתחת רק כשיש משמרת בזמן הזה, אלא אם הותר אחרת לעובד (0168).';

-- ===== 5. והמסך יודע את זה לפני הלחיצה ====================================
--
-- הגוף מ-0165 במלואו, בתוספת שני מפתחות. כפתור שנלחץ ונדחה הוא הדרך היקרה
-- ביותר להגיד "אין לך משמרת": העובד כבר אישר שיתוף מיקום והמתין לנעילת
-- לוויין לפני שהבקשה בכלל יצאה.
--
-- ‏`shift` נשאר מה שהיה — `shift_at`, כלומר המשמרת של עכשיו ואם אין הקרובה
-- לה — כי הכרטיס "משמרת מתוכננת" והטופס של דיווח ידני נשענים עליו, ומשמרת
-- שמתחילה בעוד שעתיים היא בדיוק מה שעובד רוצה לראות שם. מה שנגזר מהשער הוא
-- ‏*ההרשאה*, ולצידה `location_required`: הוא נשאל על המשמרת שההחתמה הבאה
-- באמת תיצמד אליה, ולא על השכנה שלה.

create or replace function attendance_my_status()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_me    uuid := app.profile_id();
  v_open  attendance_entries;
  v_shift app.planned_shift_row;
  v_gate  record;
  v_rules jsonb;
begin
  if v_me is null then return '{}'::jsonb; end if;
  perform app.require('attendance.view_own');
  v_rules := app.clock_rules(v_me);
  select * into v_open from attendance_entries
   where profile_id = v_me and clock_out_at is null and deleted_at is null;
  v_shift := app.shift_at(v_me, now(),
    make_interval(mins => coalesce((v_rules ->> 'early_grace_minutes')::int, 15)));
  select * into v_gate from app.clock_in_gate(v_me, now());
  return jsonb_build_object(
    'open_entry', case when v_open.id is not null then to_jsonb(v_open) end,
    'shift',      case when v_shift.shift_start is not null then to_jsonb(v_shift) end,
    'rules',      v_rules,
    'location_required', app.clock_needs_location(v_rules,
                           case when v_open.id is not null then v_shift
                                else v_gate.o_shift end,
                           v_open.id is not null),
    -- ‏0168: האם *כניסה* אפשרית עכשיו. כשיש משמרת פתוחה הכפתור ממילא מציע
    -- יציאה, ולכן המסך שואל את זה רק כשאין — אבל התשובה נשלחת תמיד, כי היא
    -- על השעה ולא על מה שהמסך מצייר כרגע.
    'can_clock_in',   v_gate.o_reason is null,
    'clock_in_block', case when v_gate.o_reason is not null
                           then jsonb_build_object('reason',  v_gate.o_reason,
                                                   'message', v_gate.o_message) end,
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
    'corrections', (select coalesce(jsonb_agg(to_jsonb(e) order by e.clock_in_at desc), '[]'::jsonb)
                    from attendance_entries e
                    where e.profile_id = v_me and e.deleted_at is null
                      and e.req_at is not null
                      and e.work_date >= (now() at time zone 'Asia/Jerusalem')::date - 45));
end $$;

comment on function attendance_my_status() is
  'מצב השעון: החתמה פתוחה, משמרת, דרישת מיקום, והאם כניסה אפשרית עכשיו (0168).';

-- ‏anon מחוץ למשטח, כמו בכל הצהרה מחדש של ה-RPC-ים האלה (0024, 0126).
revoke execute on function public.attendance_my_status() from anon, public;
revoke execute on function public.attendance_clock_in(double precision, double precision,
                                                      numeric, text) from anon, public;
