-- ‏0166: המשמרת נגמרת במקום שבו המשימה האחרונה נגמרת
--
-- ארבע הבהרות שנאמרו יחד, וכולן על אותו ציר — קצה אחד של המשמרת מול הקצה
-- השני:
--
--   1. **ההתחלה** היא המחסן למי שסומן "מחסן", ומיקום האירוע למי שסומן
--      "שטח". זה מה שהגזירה עושה מאז 0022, והוא נשאר כפי שהוא.
--   2. **הסיום — הזמן והמיקום — הוא של המשימה האחרונה במשמרת.** נגמרה
--      בשטח: השעה היא שעת השטח, והמיקום הוא מיקום האירוע. נגמרה במחסן:
--      נוספת אליה הנסיעה חזרה, והמיקום הוא המחסן.
--   3. **משימות שהזמנים שלהן חופפים אינן נספרות פעמיים**, והעובד רואה
--      שהן חופפות.
--   4. **ההחתמה נמדדת מול מחסן או שטח** — בכניסה לפי נקודת ההתחלה,
--      וביציאה לפי נקודת הסיום.
--
-- ‏(2) הוא תיקון ולא הרחבה. הגזירה שאלה עד היום את **המשימה הראשונה** אם
-- להוסיף את הנסיעה חזרה (`s_site`, שהוא `b_site` של הראשונה), ובאותה נשימה
-- קבעה שהמיקום בסיום הוא תמיד מיקום האירוע. שתי ההכרעות שגויות באותו מקרה
-- בדיוק: משמרת שיוצאת מהמחסן ומסיימת בשטח קיבלה נסיעה חזרה שאיש אינו נוסע,
-- ומשמרת שמתחילה בשטח ומסיימת במחסן לא קיבלה את הנסיעה שהיא כן נוסעת —
-- ובשתיהן שעת הסיום, השעות המתוכננות, וגם נקודת הייחוס להחתמת היציאה נגזרו
-- מהתשובה השגויה. ‏`work_site` על שורת המשמרת נשאר **שאלה על ההתחלה** בלבד,
-- וכל מי שקורא אותו (הכניסה, שם המחסן בדוח, הצ׳יפ בלוח) ממשיך לקבל בדיוק
-- את מה שקיבל.
--
-- ‏(3) נוגע במקום אחד: `shift_task_breakdown`. השעות המתוכננות של המשמרת
-- עצמה מעולם לא כפלו חפיפה — הן `סיום פחות התחלה` ולא סכום — אבל
-- ‏`totals.work_hours` במגירה **היה** `sum(hours_count)`, ולכן שתי משימות
-- 08:00–12:00 ו-10:00–14:00 הוצגו כשמונה שעות עבודה בתוך חלון של שש. מעכשיו
-- הוא איחוד החלונות, וכל משימה נושאת `overlap_minutes` — כמה ממנה כבר כוסה
-- על ידי מי שלפניה — כדי שהמסך יאמר *למה* המספר קטן מהסכום.
--
-- ‏(4) נגזר מ-(2): נקודת הסיום היא המחסן כשחוזרים אליו, והשטח כשמסיימים בו.
-- שתי נקודות סיום לגיטימיות נשמרו כפי שהן (0082) — מי שיצא לחזור למחסן
-- ומחתים יציאה עוד בשטח אינו נחסם — אלא שעכשיו הן נגזרות מהקצה הנכון:
-- ‏`end_lat/lng` הוא מקום הסיום, ו-`onsite_end_lat/lng` הוא השטח שממנו יוצאים.
--
-- ומה שנוסף לדוח: הקואורדינטות שנדגמו ברגע ההחתמה. הן נשמרות בטבלה מאז 0019
-- (`clock_in_lat/lng`, `clock_out_lat/lng`) ומעולם לא יצאו ממנה — הדוח הציג
-- מרחק ולא מקום, ו"240 מ׳ מהאתר" אינו אומר לאיזה צד. הן נוסעות לצד
-- ‏`clock_in_place` שכבר מגיע לכל מי שרשאי לקרוא את השורה: המיקום אינו כסף,
-- ולכן הוא אינו מגודר בנפרד (0153).

-- ===== 1. שני הקצוות על שורת המשמרת =======================================
--
-- ‏`end_lat/lng` שינו משמעות ולא רק ערך: עד כאן הם היו "מיקום האירוע של
-- המשימה האחרונה", ומעכשיו הם "המקום שבו המשמרת נגמרת". השטח לא אבד — הוא
-- עבר ל-`onsite_end_lat/lng`, ושם הוא משמש את מי שצריך אותו בשמו: היציאה
-- שמקבלת שתי נקודות לגיטימיות.

alter type app.planned_shift_row add attribute end_site text cascade;
alter type app.planned_shift_row add attribute end_warehouse_id uuid cascade;
alter type app.planned_shift_row add attribute end_warehouse_name text cascade;
alter type app.planned_shift_row add attribute onsite_end_lat double precision cascade;
alter type app.planned_shift_row add attribute onsite_end_lng double precision cascade;

-- ===== 2. הגזירה ==========================================================
--
-- ההגדרה זהה ל-0163 פרט לשלושה מקומות: שתי עמודות מחסן ב-`base`, חמש
-- אגרגציות "לפי המשימה האחרונה" ב-`shifts`, ובחירת הקצה ב-`select` הסופי.
create or replace function app.planned_shifts_many(
  p_profile_ids uuid[], p_from date, p_to date)
returns setof app.planned_shift_row
language plpgsql stable security definer set search_path = public as $$
declare v_gap interval;
begin
  v_gap := make_interval(mins => coalesce(
    (app.attendance_config('attendance.clock') ->> 'merge_gap_minutes')::int, 120));

  return query
  with mine as (
    select a.profile_id as pid, a.task_id as tid,
           bool_or(a.work_site = 'warehouse') as is_wh
      from task_assignments a
     where a.profile_id = any(p_profile_ids)
     group by a.profile_id, a.task_id
    union all
    select pr.id, w.task_id, bool_or(w.work_site = 'warehouse')
      from task_contractor_workers w
      join profiles pr on pr.contractor_worker_id = w.contractor_worker_id
     where pr.id = any(p_profile_ids)
     group by pr.id, w.task_id
  ),
  dedup as (
    select m.pid, m.tid, bool_or(m.is_wh) as is_wh
      from mine m group by m.pid, m.tid
  ),
  travel as (
    select u.tid, coalesce(app.task_travel_hours(u.tid), 0) as hrs
      from (select distinct d.tid from dedup d) u
  ),
  base as (
    select
      d.pid as b_pid,
      t.id as b_task,
      t.customer_id as b_cust,
      c.color as b_color,
      coalesce(nullif(t.title, ''), tt.name) as b_label,
      case when d.is_wh then 'warehouse' else 'field' end as b_site,
      -- ‏0163: ההגעה למחסן קודמת לעבודה בשטח, ולכן שעה שגדולה ממנה היא של
      -- הערב שלפני. שאר הענפים לא זזו.
      case when d.is_wh and t.warehouse_start_time is not null
           then app.warehouse_start_at(t.task_date, t.warehouse_start_time,
                                       t.onsite_start_time)
           else ((t.task_date + coalesce(t.onsite_start_time, t.warehouse_start_time))
                   at time zone 'Asia/Jerusalem') end as b_start,
      ((t.task_date + coalesce(t.onsite_start_time, t.warehouse_start_time))
        at time zone 'Asia/Jerusalem')
        + make_interval(mins => round(coalesce(t.hours_count, 0) * 60)::int) as b_end,
      tv.hrs as b_travel,
      case when d.is_wh then wh.lat else e.location_lat end as b_start_lat,
      case when d.is_wh then wh.lng else e.location_lng end as b_start_lng,
      e.location_lat as b_end_lat,
      e.location_lng as b_end_lng,
      case when d.is_wh then wh.id end   as b_wh_id,
      case when d.is_wh then wh.name end as b_wh_name,
      -- ‏0166: המחסן כנקודה, ולא רק כשם. עד כאן הוא נשלף רק דרך
      -- ‏`b_start_lat`, ולכן משמרת שחוזרת אליו בלי לצאת ממנו לא ידעה איפה הוא.
      case when d.is_wh then wh.lat end as b_wh_lat,
      case when d.is_wh then wh.lng end as b_wh_lng
    from dedup d
    join tasks t on t.id = d.tid
    join travel tv on tv.tid = d.tid
    left join events e on e.id = t.event_id
    left join customers c on c.id = t.customer_id
    left join warehouses wh
           on wh.id = coalesce(t.warehouse_id, c.warehouse_id)
          and wh.deleted_at is null
    join task_types tt on tt.id = t.task_type_id
    join statuses st on st.id = t.status_id
    where t.deleted_at is null
      -- ‏0163: ועוד משימה של היום שאחרי החלון, כשההגעה למחסן שלה נסוגה
      -- אל תוכו.
      and (t.task_date between p_from and p_to
           or (t.task_date = p_to + 1 and d.is_wh
               and t.warehouse_start_time is not null
               and t.onsite_start_time is not null
               and t.warehouse_start_time > t.onsite_start_time))
      and coalesce(t.onsite_start_time, t.warehouse_start_time) is not null
      -- משימה שטרם פורסמה אינה משמרת
      and st.code = 'assigned'
  ),
  ordered as (
    select b.*,
           max(b.b_end) over (
             partition by b.b_pid
             order by b.b_start, b.b_task
             rows between unbounded preceding and 1 preceding) as b_prev_end
    from base b
  ),
  flagged as (
    select o.*, case when o.b_prev_end is null or o.b_start - o.b_prev_end > v_gap
                     then 1 else 0 end as b_new
    from ordered o
  ),
  grouped as (
    select f.*, sum(f.b_new) over (
             partition by f.b_pid
             order by f.b_start, f.b_task
             rows between unbounded preceding and current row) as b_grp
    from flagged f
  ),
  shifts as (
    select
      g.b_pid        as s_pid,
      min(g.b_start) as s_start,
      max(g.b_end)   as s_core_end,
      (array_agg(g.b_travel   order by g.b_end desc, g.b_task desc))[1] as s_travel,
      (array_agg(g.b_task     order by g.b_end desc, g.b_task desc))[1] as s_last,
      (array_agg(g.b_end_lat  order by g.b_end desc, g.b_task desc))[1] as s_last_lat,
      (array_agg(g.b_end_lng  order by g.b_end desc, g.b_task desc))[1] as s_last_lng,
      -- ‏0166: הקצה השני נשאל מהמשימה האחרונה, באותו מיון שכבר בורר את
      -- הנסיעה שלה. ‏`b_wh_*` הם null כשהיא אינה משימת מחסן, וזה בדיוק
      -- המקרה שבו המשמרת נגמרת בשטח.
      (array_agg(g.b_site     order by g.b_end desc, g.b_task desc))[1] as s_end_site,
      (array_agg(g.b_wh_id    order by g.b_end desc, g.b_task desc))[1] as s_end_wh_id,
      (array_agg(g.b_wh_name  order by g.b_end desc, g.b_task desc))[1] as s_end_wh_name,
      (array_agg(g.b_wh_lat   order by g.b_end desc, g.b_task desc))[1] as s_end_wh_lat,
      (array_agg(g.b_wh_lng   order by g.b_end desc, g.b_task desc))[1] as s_end_wh_lng,
      (array_agg(g.b_task     order by g.b_start, g.b_task))[1] as s_first,
      (array_agg(g.b_site     order by g.b_start, g.b_task))[1] as s_site,
      (array_agg(g.b_start_lat order by g.b_start, g.b_task))[1] as s_first_lat,
      (array_agg(g.b_start_lng order by g.b_start, g.b_task))[1] as s_first_lng,
      (array_agg(g.b_label    order by g.b_start, g.b_task))[1] as s_label,
      (array_agg(g.b_cust     order by g.b_start, g.b_task))[1] as s_cust,
      (array_agg(g.b_color    order by g.b_start, g.b_task))[1] as s_color,
      (array_agg(g.b_wh_id    order by g.b_start, g.b_task))[1] as s_wh_id,
      (array_agg(g.b_wh_name  order by g.b_start, g.b_task))[1] as s_wh_name,
      array_agg(g.b_task order by g.b_start, g.b_task) as s_ids,
      count(*) as s_count
    from grouped g
    group by g.b_pid, g.b_grp
  )
  select
    s.s_pid,
    (s.s_start at time zone 'Asia/Jerusalem')::date,
    (row_number() over (
       partition by s.s_pid, (s.s_start at time zone 'Asia/Jerusalem')::date
       order by s.s_start))::int,
    s.s_start,
    s.s_core_end + make_interval(mins => round(v.travel * 60)::int),
    round((extract(epoch from
      (s.s_core_end + make_interval(mins => round(v.travel * 60)::int) - s.s_start)
      ) / 3600.0)::numeric, 2),
    -- ‏`work_site` הוא שאלה על ההתחלה, וכזה הוא נשאר: המחסן שיוצאים ממנו,
    -- או השטח שמגיעים אליו. הסיום נשאל בעמודה משלו.
    s.s_site,
    s.s_ids,
    s.s_first,
    s.s_last,
    s.s_first_lat, s.s_first_lng,
    -- ‏0166: מקום הסיום — המחסן שחוזרים אליו, או השטח שמסיימים בו.
    case when s.s_end_site = 'warehouse' then s.s_end_wh_lat else s.s_last_lat end,
    case when s.s_end_site = 'warehouse' then s.s_end_wh_lng else s.s_last_lng end,
    v.travel,
    case when s.s_count > 1 then s.s_label || ' +' || (s.s_count - 1)::text else s.s_label end,
    s.s_cust,
    s.s_color,
    s.s_wh_id,
    s.s_wh_name,
    s.s_end_site,
    s.s_end_wh_id,
    s.s_end_wh_name,
    -- השטח של המשימה האחרונה נשמר בשמו: הוא הנקודה השנייה שהיציאה מקבלת.
    s.s_last_lat,
    s.s_last_lng
  from shifts s
  -- ‏0166: הנסיעה חזרה שייכת למי ש**מסיים** במחסן, ולא למי שיצא ממנו.
  -- היא, בהגדרה, החזרה מהמשימה האחרונה אל המחסן — ולכן המשימה האחרונה היא
  -- שנשאלת. ההכרעה נגזרת פעם אחת כאן ומוזנת לשלושת הצרכנים שלה: שעת
  -- הסיום, השעות המתוכננות והעמודה עצמה.
  cross join lateral (
    select case when s.s_end_site = 'warehouse' then s.s_travel else 0 end as travel
  ) v
  -- ‏0163: המשמרת נתלית על היום שבו היא התחילה, וזה גם הטווח שנשאל.
  where (s.s_start at time zone 'Asia/Jerusalem')::date between p_from and p_to
  order by s.s_pid, s.s_start;
end $$;

comment on function app.planned_shifts_many(uuid[], date, date) is
  'גזירת המשמרות. ההתחלה לפי המשימה הראשונה, הסיום והמיקום שבו לפי האחרונה (0166).';

-- ===== 3. השעון: שתי נקודות סיום, מהקצה הנכון =============================
--
-- ‏`end_lat/lng` הוא כבר מקום הסיום, ולכן הענף שמחפש נקודה שנייה אינו שואל
-- עוד "האם יצאת ממחסן" אלא "האם נשאר שטח שאפשר להחתים ממנו". זו אותה
-- הקלה של 0082 מנוסחת מחדש: מי שנוסע חזרה למחסן ומחתים יציאה בשטח, רגע
-- לפני שהוא עולה לרכב, אינו נחסם.

create or replace function app.clock_needs_location(
  p_rules jsonb, p_shift app.planned_shift_row, p_clocking_out boolean)
returns boolean language sql stable set search_path = public as $$
  select coalesce((p_rules ->> 'requires_location')::boolean, false)
     and case
           when p_clocking_out then
             (p_shift.end_lat is not null and p_shift.end_lng is not null)
             or (p_shift.onsite_end_lat is not null and p_shift.onsite_end_lng is not null)
           else p_shift.start_lat is not null and p_shift.start_lng is not null
         end
$$;

comment on function app.clock_needs_location(jsonb, app.planned_shift_row, boolean) is
  'האם ההחתמה הבאה תדרוש קריאת מיקום — כלומר האם יש בכלל מול מה לאמת (0159).';

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
  v_d_end  numeric;
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
  -- ‏0166: נקודת הסיום היא המקום שבו המשמרת נגמרת — המחסן כשחוזרים אליו,
  -- והשטח כשמסיימים בו.
  v_site_lat := v_shift.end_lat;
  v_site_lng := v_shift.end_lng;

  -- ומי שחוזר למחסן מסיים באחת משתי נקודות: במחסן, או בשטח שממנו יצא אליו.
  -- נבחרת הקרובה מביניהן, ובלי לוותר על כלום — מי שרחוק משתיהן עדיין נחסם.
  if v_shift.onsite_end_lat is not null and v_shift.onsite_end_lng is not null then
    if p_lat is null or p_lng is null then
      -- אין מה להשוות, ולכן אין מה לבחור: נקודת הסיום היא הייחוס, וכשאין
      -- לה קואורדינטות השטח תופס את מקומה (0159).
      if v_site_lat is null or v_site_lng is null then
        v_site_lat := v_shift.onsite_end_lat;
        v_site_lng := v_shift.onsite_end_lng;
      end if;
    else
      v_d_site := app.haversine_km(p_lat, p_lng, v_shift.onsite_end_lat, v_shift.onsite_end_lng);
      v_d_end  := case when v_site_lat is null or v_site_lng is null then null
                       else app.haversine_km(p_lat, p_lng, v_site_lat, v_site_lng) end;
      if v_d_end is null or v_d_site < v_d_end then
        v_site_lat := v_shift.onsite_end_lat;
        v_site_lng := v_shift.onsite_end_lng;
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

revoke execute on function public.attendance_clock_out(double precision, double precision,
                                                       numeric, text) from anon, public;

-- ===== 4. איפה המשמרת נגמרה, לשורה בדוח ===================================
--
-- אותה גזירה של `app.planned_shifts_many` מנוסחת לשאלה אחת: מהי המשימה
-- האחרונה במשמרת הזו, ומהו האתר שלה *עבור העובד הזה*. `work_site` על שורת
-- הנוכחות הוא צילום של ההתחלה בלבד (הוא נכתב ברגע ההחתמה), ולכן הסיום נגזר
-- כאן מהמשימות — בדיוק כפי ש-0153 גזר את שם המחסן שבהתחלה.
--
-- מחזירה null כשאין משימות (דיווח ידני), ואז המסך נופל למה שכן ידוע.
create or replace function app.shift_end_place(p_profile_id uuid, p_task_ids uuid[])
returns jsonb language sql stable set search_path = public as $$
  with mine as (
    select a.task_id as tid, bool_or(a.work_site = 'warehouse') as is_wh
      from task_assignments a
     where a.profile_id = p_profile_id and a.task_id = any(p_task_ids)
     group by a.task_id
    union all
    select w.task_id, bool_or(w.work_site = 'warehouse')
      from task_contractor_workers w
      join profiles pr on pr.contractor_worker_id = w.contractor_worker_id
     where pr.id = p_profile_id and w.task_id = any(p_task_ids)
     group by w.task_id
  ),
  d as (select m.tid, bool_or(m.is_wh) as is_wh from mine m group by m.tid)
  select jsonb_build_object(
           'work_site',      case when l.is_wh then 'warehouse' else 'field' end,
           'warehouse_name', case when l.is_wh then l.wh_name end)
    from (
      select d.is_wh, wh.name as wh_name
        from d
        join tasks t on t.id = d.tid and t.deleted_at is null
        left join customers cu on cu.id = t.customer_id
        left join warehouses wh on wh.id = coalesce(t.warehouse_id, cu.warehouse_id)
                               and wh.deleted_at is null
       where coalesce(t.onsite_start_time, t.warehouse_start_time) is not null
       -- אותו מיון בדיוק שבורר את הנסיעה בגזירה: הסיום המאוחר, ואז ה-id.
       order by ((t.task_date + coalesce(t.onsite_start_time, t.warehouse_start_time))
                   at time zone 'Asia/Jerusalem')
                   + make_interval(mins => round(coalesce(t.hours_count, 0) * 60)::int) desc,
                t.id desc
       limit 1) l
$$;

comment on function app.shift_end_place(uuid, uuid[]) is
  'האתר והמחסן של המשימה האחרונה במשמרת — איפה היא נגמרה (0166).';

-- ===== 5. שורת הנוכחות נושאת את הקואורדינטות שנדגמו =======================
--
-- ארבע עמודות שכבר קיימות בטבלה מאז 0019 ומעולם לא יצאו ממנה. `create or
-- replace` בלי `cascade` על הפונקציה שמעליהן: `attendance_report` נשענת על
-- שמות ולא על מיקומים, והיא נכתבת מחדש כאן ממילא.

alter type app.attendance_pay_row add attribute clock_in_lat   double precision cascade;
alter type app.attendance_pay_row add attribute clock_in_lng   double precision cascade;
alter type app.attendance_pay_row add attribute clock_out_lat  double precision cascade;
alter type app.attendance_pay_row add attribute clock_out_lng  double precision cascade;

create or replace function app.attendance_pay_rows(
  p_from date,
  p_to   date,
  p_profile_ids   uuid[]  default null,
  p_contractor_id uuid    default null,
  p_only_flagged  boolean default false,
  p_status        text[]  default null,
  p_scope         text    default 'auto')
returns setof app.attendance_pay_row
language plpgsql stable security definer set search_path = public as $$
declare
  v_me         uuid    := app.profile_id();
  v_kind       text    := app.user_kind();
  v_admin      boolean := app.is_admin();
  v_all        boolean;
  v_portal     boolean;
  v_contractor uuid    := app.contractor_id();
  v_config     jsonb   := app.attendance_config('attendance.overtime');
  v_any        boolean := p_scope = 'all';
begin
  v_all    := v_admin or (v_kind = 'staff' and app.has('attendance.view_all'));
  -- 0075: מי שמקושר לקבלן, ולא מי שנולד כקבלן
  v_portal := v_contractor is not null and app.has('portal.attendance');

  return query
  with visible as (
    select e.*, p.full_name, p.contractor_id as p_contractor,
           (e.profile_id = v_me) as is_mine,
           coalesce(b.amount, 0) as bonus_amount,
           b.note as bonus_note
    from attendance_entries e
    join profiles p on p.id = e.profile_id
    left join attendance_entry_bonus b on b.entry_id = e.id
    where e.deleted_at is null
      and e.work_date between p_from and p_to
      and (
        v_any
        or e.profile_id = v_me
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
           coalesce(s.overtime_enabled, true) as overtime_enabled,
           app.attendance_calc(v_config, jsonb_build_object(
             'hours',             coalesce(w.actual_hours, 0),
             'min_hours',         s.min_hours_per_shift,
             -- ‏0152: ההחלטה יושבת על המשמרת, ולכן היא נוסעת עם השורה ולא
             -- עם הגדרות העובד — בדיוק כמו הבונוס שמעליה.
             'topup_waived',      w.topup_waived,
             'overtime_enabled',  coalesce(s.overtime_enabled, true),
             'hourly_rate',       s.hourly_rate,
             'dow',               extract(dow from w.work_date)::int,
             'week_hours_before', w.week_before,
             -- הבונוס יושב על המשמרת ולא על הגדרות העובד: הוא פר-משמרת.
             'bonus',             w.bonus_amount,
             -- ‏0084: האיחור נמדד מול המשמרת המתוכננת שנצמדה להחתמה. בלי
             -- משמרת אין ממה לאחר, ולכן 0 ולא null — "לא איחר".
             'late_minutes',      case when w.shift_start is null then 0
                                       else greatest(0, round(extract(epoch
                                              from (w.clock_in_at - w.shift_start)) / 60)) end,
             'late_forfeit_minutes', s.late_topup_forfeit_minutes,
             -- תוספת ראש צוות היא פר-משימה, ולכן היא נספרת על המשימות של
             -- המשמרת עצמה ולא על המשמרת כיחידה.
             'lead_bonus',        round(coalesce(s.team_lead_bonus, 0) * (
                                    select count(*) from unnest(w.task_ids) tid
                                     where exists (select 1 from task_assignments a
                                                    where a.task_id = tid
                                                      and a.profile_id = w.profile_id
                                                      and a.role = 'team_lead')), 2),
             'shift_bonus',       coalesce(s.shift_bonus, 0))) as pay
    from weekly w
    left join worker_pay_settings s on s.profile_id = w.profile_id
  )
  select c.id, c.profile_id, c.full_name, c.p_contractor,
         c.work_date, c.seq, c.shift_start, c.shift_end,
         c.planned_hours, c.work_site, c.task_ids,
         c.clock_in_at, c.clock_out_at, c.actual_hours,
         c.clock_in_distance_m, c.clock_out_distance_m,
         c.raw_clock_in_at, c.raw_clock_out_at,
         c.source, c.status, c.reviewed_at, c.flags,
         c.employee_note, c.manager_note, c.edited_at,
         c.is_mine, c.overtime_enabled, c.bonus_amount, c.bonus_note, c.pay,
         c.clock_in_place, c.clock_out_place,
         c.clock_in_lat, c.clock_in_lng, c.clock_out_lat, c.clock_out_lng
  from computed c;
end $$;

-- ===== 6. הדוח: איפה נכנסו, איפה יצאו, ואיפה בדיוק =========================
--
-- ההגדרה זהה ל-0165 — כולל בקשת התיקון והמונה שלה — פרט לשלוש קבוצות
-- מפתחות שנוספו: מקום הסיום, הקואורדינטות שנדגמו, והצירוף `end_work_site`
-- שהמסך נופל אליו כשאין שם מחסן.

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

-- ===== 7. פירוק המשמרת: החפיפה נראית, ואינה נספרת פעמיים ====================
--
-- שלושה שינויים מול 0163, וכולם באותה משפחה:
--
-- 1. **הנסיעה חזרה נשאלת מהמשימה האחרונה**, כמו בגזירה. עד כאן היא נגזרה
--    מ-`v_tasks -> 0` — המשימה הראשונה — ולכן המגירה והלוח יכלו להראות שתי
--    שעות סיום שונות לאותה משמרת. שתיהן חייבות להסכים, וזה הכלל שמשותף להן.
-- 2. **"מה קדם" נמדד מול המקסימום ולא מול הקודמת.** ‏`lag(end_at)` הניח
--    שמשימות אינן נבלעות זו בזו: משימה 08:00–14:00 ואחריה 09:00–10:00
--    ו-10:00–11:00 נתנה ל"אחרונה" פער חיובי מול מי שלפניה, בזמן ששתיהן
--    יושבות בתוך הראשונה. `max` על כל מה שקדם עונה נכון בשני המקרים.
-- 3. **‏`work_hours` הוא איחוד החלונות ולא סכומם.** שתי משימות שחופפות
--    שעתיים אינן שמונה שעות עבודה בתוך חלון של שש. הסכום עצמו לא נעלם —
--    ההפרש בינו לאיחוד יושב ב-`totals.overlap_hours`, ועל כל משימה נכתב
--    ‏`overlap_minutes`: כמה ממנה כבר כוסה על ידי מי שלפניה. בלי זה המסך היה
--    מציג מספר קטן מהסכום בלי לומר למה.

create or replace function shift_task_breakdown(p_profile_id uuid, p_task_ids uuid[])
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_ids      uuid[];
  v_staffing boolean;
  v_name     text;
  v_tasks    jsonb;
  v_last     jsonb;
  v_travel   numeric;
  v_work     numeric;
  v_sum      numeric;
begin
  if p_profile_id = app.profile_id() then
    perform app.require('attendance.view_schedule');
  elsif app.user_kind() = 'contractor_user' then
    if not (app.has('portal.attendance') and app.is_my_contractor_staff(p_profile_id)) then
      raise exception 'אין לך הרשאה לצפות במשמרות של עובד זה' using errcode = '42501';
    end if;
  else
    perform app.require('attendance.view_all');
  end if;

  select array_agg(distinct u) into v_ids
    from unnest(coalesce(p_task_ids, '{}'::uuid[])) u;

  select p.full_name into v_name from profiles p where p.id = p_profile_id;

  if v_ids is null then
    return jsonb_build_object(
      'profile_id', p_profile_id, 'full_name', v_name,
      'tasks', '[]'::jsonb,
      'totals', jsonb_build_object('tasks', 0, 'work_hours', 0,
                                   'travel_hours', 0, 'idle_minutes', 0,
                                   'overlap_hours', 0),
      'shift', jsonb_build_object('start', null, 'end', null,
                                  'work_site', null, 'warehouse_name', null,
                                  'end_work_site', null, 'end_warehouse_name', null));
  end if;

  v_staffing := app.is_admin() or app.has('board.view_staffing');

  with mine as (
    select a.task_id as tid,
           bool_or(a.work_site = 'warehouse') as is_wh,
           (array_agg(a.truck_id) filter (where a.truck_id is not null))[1] as my_truck
      from task_assignments a
     where a.profile_id = p_profile_id and a.task_id = any(v_ids)
     group by a.task_id
    union all
    select w.task_id, bool_or(w.work_site = 'warehouse'), null::uuid
      from task_contractor_workers w
      join profiles pr on pr.contractor_worker_id = w.contractor_worker_id
     where pr.id = p_profile_id and w.task_id = any(v_ids)
     group by w.task_id
  ),
  d as (
    select m.tid, bool_or(m.is_wh) as is_wh,
           (array_agg(m.my_truck) filter (where m.my_truck is not null))[1] as my_truck
      from mine m group by m.tid
  ),
  enriched as (
    select
      t.id as task_id,
      d.is_wh,
      -- ‏0094: כל התפקידים של האדם במשימה, מסודרים ראש צוות > נהג > עובד.
      (select array_agg(s.r order by s.pr) from (
         select distinct a.role::text as r,
                case a.role when 'team_lead' then 0 when 'driver' then 1 else 2 end as pr
           from task_assignments a
          where a.task_id = t.id and a.profile_id = p_profile_id) s) as my_roles,
      coalesce(nullif(t.title, ''), tt.name) as title,
      tt.name as type_name, tt.code as type_code,
      t.customer_id, c.name as cust_name, c.color as cust_color,
      t.event_id, e.event_number, e.end_client_name,
      coalesce(nullif(t.location_text, ''), e.location_text) as location_text,
      e.location_lat, e.location_lng,
      t.hours_count, t.worker_count, t.notes,
      st.name as status_name, st.color as status_color,
      coalesce(tr.name, nullif(t.truck_free_text, '')) as truck_name,
      tlist.list as truck_list,
      em.name as method_name,
      wh.id as wh_id, wh.name as wh_name,
      coalesce(app.task_travel_hours(t.id), 0) as travel,
      -- ‏0163: היציאה מהמחסן שקודמת לעבודה בשטח היא של הערב שלפני.
      case when d.is_wh and t.warehouse_start_time is not null
           then app.warehouse_start_at(t.task_date, t.warehouse_start_time,
                                       t.onsite_start_time)
      end as wh_start_at,
      ((t.task_date + coalesce(t.onsite_start_time, t.warehouse_start_time))
        at time zone 'Asia/Jerusalem') as start_at,
      ((t.task_date + coalesce(t.onsite_start_time, t.warehouse_start_time))
        at time zone 'Asia/Jerusalem') as onsite_at,
      ((t.task_date + coalesce(t.onsite_start_time, t.warehouse_start_time))
        at time zone 'Asia/Jerusalem')
        + make_interval(mins => round(coalesce(t.hours_count, 0) * 60)::int) as end_at,
      case when app.can_view_field('event', 'contact_phone')
                or app.is_event_team_lead(t.event_id)
           then ec.contact_name end as contact_name,
      case when app.can_view_field('event', 'contact_phone')
                or app.is_event_team_lead(t.event_id)
           then ec.contact_phone end as contact_phone,
      (select count(*) from task_assignments x where x.task_id = t.id)
        + (select count(*) from task_contractor_workers x where x.task_id = t.id)
        as assigned_count,
      case when v_staffing then (
        select jsonb_agg(q.o order by q.o ->> 'name') from (
          select jsonb_build_object('name', p2.full_name, 'work_site', a2.work_site) as o
            from task_assignments a2 join profiles p2 on p2.id = a2.profile_id
           where a2.task_id = t.id
          union all
          select jsonb_build_object('name', cw.full_name, 'work_site', w2.work_site)
            from task_contractor_workers w2
            join contractor_workers cw on cw.id = w2.contractor_worker_id
           where w2.task_id = t.id) q) end as team
    from d
    join tasks t on t.id = d.tid and t.deleted_at is null
    join task_types tt on tt.id = t.task_type_id
    left join events e on e.id = t.event_id
    left join event_contacts ec on ec.event_id = t.event_id
    left join customers c on c.id = t.customer_id
    left join statuses st on st.id = t.status_id
    left join trucks tr on tr.id = coalesce(d.my_truck, t.truck_id)
    left join execution_methods em on em.id = t.execution_method_id
    left join warehouses wh on wh.id = coalesce(t.warehouse_id, c.warehouse_id)
                           and wh.deleted_at is null
    left join lateral (
      select jsonb_agg(jsonb_build_object('id', tr3.id, 'name', tr3.name) order by u.ord) as list
        from unnest(t.truck_ids) with ordinality as u(truck_id, ord)
        join trucks tr3 on tr3.id = u.truck_id
    ) tlist on true
  ),
  numbered as (
    select x.*,
           row_number() over (order by x.start_at, x.task_id) as ord,
           -- ‏0166: המאוחר מבין הסיומים שקדמו, ולא הסיום של הקודמת. משימה
           -- שנבלעת בתוך אחת ארוכה ממנה אינה "אחריה".
           max(x.end_at) over (order by x.start_at, x.task_id
                               rows between unbounded preceding and 1 preceding) as prev_end
      from enriched x
  ),
  -- החלונות מאוחדים לאיים: איי הזמן שבהם באמת עובדים. אי חדש נפתח כשמשימה
  -- מתחילה אחרי שכל מה שלפניה כבר נגמר, וכל השאר מתמזג לתוך מה שפתוח.
  islands as (
    select n.*,
           sum(case when n.prev_end is null or n.start_at > n.prev_end then 1 else 0 end)
             over (order by n.ord rows between unbounded preceding and current row) as grp
      from numbered n
  ),
  merged as (
    select i.grp, min(i.start_at) as s, max(i.end_at) as e
      from islands i group by i.grp
  )
  select jsonb_agg(jsonb_build_object(
           'task_id',               n.task_id,
           'ord',                   n.ord,
           'title',                 n.title,
           'task_type_name',        n.type_name,
           'task_type_code',        n.type_code,
           'customer_id',           n.customer_id,
           'customer_name',         n.cust_name,
           'customer_color',        n.cust_color,
           'event_id',              n.event_id,
           'event_number',          n.event_number,
           'end_client_name',       n.end_client_name,
           'contact_name',          n.contact_name,
           'contact_phone',         n.contact_phone,
           'location_text',         n.location_text,
           'location_lat',          n.location_lat,
           'location_lng',          n.location_lng,
           'work_site',             case when n.is_wh then 'warehouse' else 'field' end,
           'warehouse_id',          n.wh_id,
           'warehouse_name',        n.wh_name,
           'warehouse_start_at',    n.wh_start_at,
           'start_at',              n.start_at,
           'onsite_start_at',       n.onsite_at,
           'end_at',                n.end_at,
           'hours_count',           n.hours_count,
           'travel_hours',          n.travel,
           'gap_minutes',           case when n.prev_end is null then null
                                    else greatest(0, round(extract(epoch
                                           from (n.start_at - n.prev_end)) / 60))::int end,
           -- ‏0166: כמה מהמשימה הזו כבר כוסה על ידי מה שלפניה. 0 בראשונה,
           -- ו-0 בכל משימה שמתחילה אחרי שהכול נגמר — כלומר ברוב המשמרות.
           'overlap_minutes',       case when n.prev_end is null then 0
                                    else greatest(0, round(extract(epoch
                                           from (least(n.end_at, n.prev_end) - n.start_at))
                                           / 60))::int end,
           'status_name',           n.status_name,
           'status_color',          n.status_color,
           'truck_name',            n.truck_name,
           'truck_list',            n.truck_list,
           'execution_method_name', n.method_name,
           'my_role',               n.my_roles,
           'worker_count',          n.worker_count,
           'assigned_count',        n.assigned_count,
           'team',                  n.team,
           'notes',                 n.notes)
         order by n.ord),
         (select round((coalesce(sum(extract(epoch from (m.e - m.s))), 0) / 3600.0)::numeric, 2)
            from merged m)
    into v_tasks, v_work
    from islands n;

  if coalesce(jsonb_array_length(v_tasks), 0) <> cardinality(v_ids) then
    raise exception 'אחת המשימות אינה שייכת למשמרת של עובד זה' using errcode = '42501';
  end if;

  -- המשימה האחרונה במשמרת — זו שנגמרת אחרונה, ולא זו שמתחילה אחרונה. היא
  -- שקובעת את הסיום: את המקום, ואת השאלה אם יש בכלל נסיעה חזרה.
  select r into v_last
    from jsonb_array_elements(v_tasks) r
   order by (r ->> 'end_at')::timestamptz desc, (r ->> 'task_id') desc
   limit 1;

  v_travel := case when v_last ->> 'work_site' = 'warehouse'
                   then coalesce((v_last ->> 'travel_hours')::numeric, 0)
                   else 0 end;

  select round(coalesce(sum((r ->> 'hours_count')::numeric), 0), 2) into v_sum
    from jsonb_array_elements(v_tasks) r;

  return jsonb_build_object(
    'profile_id', p_profile_id,
    'full_name',  v_name,
    'tasks',      v_tasks,
    'totals', jsonb_build_object(
      'tasks', jsonb_array_length(v_tasks),
      -- איחוד החלונות, ולא סכומם. ההפרש בין השניים הוא בדיוק החפיפה.
      'work_hours', v_work,
      'overlap_hours', greatest(0, round(v_sum - v_work, 2)),
      'travel_hours', v_travel,
      'idle_minutes', (select coalesce(sum((r ->> 'gap_minutes')::int), 0)
                         from jsonb_array_elements(v_tasks) r)),
    'shift', jsonb_build_object(
      'start', (select min(least((r ->> 'warehouse_start_at')::timestamptz,
                                 (r ->> 'start_at')::timestamptz))
                  from jsonb_array_elements(v_tasks) r),
      'end',   (select max((r ->> 'end_at')::timestamptz) from jsonb_array_elements(v_tasks) r)
                 + make_interval(mins => round(v_travel * 60)::int),
      'work_site',      v_tasks -> 0 ->> 'work_site',
      'warehouse_name', v_tasks -> 0 ->> 'warehouse_name',
      -- ‏0166: והקצה השני, באותה מגירה: איפה היום נגמר.
      'end_work_site',      v_last ->> 'work_site',
      'end_warehouse_name', case when v_last ->> 'work_site' = 'warehouse'
                                 then v_last ->> 'warehouse_name' end));
end $$;

comment on function shift_task_breakdown(uuid, uuid[]) is
  'פירוק המשמרת למשימות. הסיום לפי האחרונה, והחפיפה נספרת פעם אחת (0166).';
