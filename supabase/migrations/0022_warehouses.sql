-- 0022: מחסנים כישות, ולא זוג קואורדינטות בהגדרות
--
-- 0019 הניח מחסן אחד ושמר את המיקום שלו בתוך app_settings['attendance.clock'].
-- לחברה יש כמה מחסנים, ולכן ההנחה ההיא שגויה בשורש: משמרת שמתחילה במחסן
-- צריכה להימדד מול *המחסן שממנו יוצאים*, לא מול "המחסן".
--
-- שתי החלטות:
--
-- 1. המשימה יכולה לנקוב במחסן (tasks.warehouse_id), אבל אינה חייבת. אילו
--    היינו דורשים זאת, כל משימה קיימת הייתה נשברת ביום השדרוג וכל רכז היה
--    צריך לתייג מאות שורות לפני שהשעון עובד שוב.
--
-- 2. כשהמשימה לא נקבה במחסן, ההחתמה נמדדת מול המחסן *הקרוב ביותר* שהעובד
--    נמצא לידו. זו לא הקלה: הוא עדיין חייב להיות בתוך הרדיוס של מחסן אמיתי,
--    ורק השאלה "איזה מהם" נענית לפי המיקום במקום לפי התיוג.

-- ===== 1. הטבלה ============================================================

create table warehouses (
  id         uuid primary key default gen_random_uuid(),
  name       text not null,
  address    text,
  lat        double precision,
  lng        double precision,
  -- NULL = לפי הרדיוס הגלובלי. מחסן בתוך אזור תעשייה צפוף מצדיק רדיוס אחר
  -- ממחסן בשטח פתוח, ולכן הדריסה יושבת על המחסן ולא רק על העובד.
  radius_m   int check (radius_m is null or radius_m > 0),
  color      text not null default '#64748b',
  notes      text,
  is_active  boolean not null default true,
  sort_order int not null default 0,
  deleted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index warehouses_name_uq on warehouses (name) where deleted_at is null;
create index warehouses_active_idx on warehouses (sort_order) where deleted_at is null and is_active;
create trigger warehouses_updated before update on warehouses
  for each row execute function app.set_updated_at();

alter table tasks add column warehouse_id uuid references warehouses(id);
comment on column tasks.warehouse_id is
  'מאיזה מחסן יוצאים במשימה הזו. NULL = לפי המחסן הקרוב ביותר בעת ההחתמה.';

-- ===== 2. העברת המחסן היחיד שהוגדר עד כה ===================================
-- מי שכבר מילא קואורדינטות ב-0019 לא צריך למלא אותן שוב.

insert into warehouses (name, lat, lng)
select coalesce(nullif(value #>> '{warehouse,label}', ''), 'המחסן'),
       (value #>> '{warehouse,lat}')::double precision,
       (value #>> '{warehouse,lng}')::double precision
from app_settings
where key = 'attendance.clock'
  and value #>> '{warehouse,lat}' is not null
  and value #>> '{warehouse,lng}' is not null
on conflict do nothing;

-- המפתח הישן נשאר בקונפיגורציה כדי לא לשבור עותק שעדיין קורא אותו, אבל
-- שום דבר בקוד כבר לא מסתכל עליו.
update app_settings
   set value = value - 'warehouse'
 where key = 'attendance.clock';

-- ===== 3. הרשאות ו-RLS =====================================================
-- הקריאה פתוחה לכל מאומת: הדפדפן צריך לדעת מול איזו נקודה הוא נמדד לפני
-- שהוא בכלל מציג כפתור החתמה. הכתיבה היא הגדרת מערכת.

select app.register_permission('attendance.manage_warehouses', 'attendance', 'ניהול מחסנים',
  'שמות ומיקומים של המחסנים שמהם יוצאים למשימות', 'action', false, false,
  array['staff']::user_kind[], 'attendance.settings', 125);

select app.register_field('task', 'warehouse_id', 'מחסן יציאה', 'attendance',
  'tasks', 'warehouse_id', false, true, true, 'tasks.change_location', 110);

alter table warehouses enable row level security;

create policy warehouses_select on warehouses for select to authenticated
  using ((select app.is_admin()) or deleted_at is null);

create policy warehouses_write on warehouses for all to authenticated
  using ((select app.is_admin())
         or (select app.has('attendance.manage_warehouses'))
         or (select app.has('settings.edit')))
  with check ((select app.is_admin())
         or (select app.has('attendance.manage_warehouses'))
         or (select app.has('settings.edit')));

create trigger warehouses_audit after insert or update or delete on warehouses
  for each row execute function app.audit();

-- ===== 4. המחסן הקרוב ביותר ================================================
-- ההיקפים כאן הם יחידות של מחסנים, ולכן סריקה מלאה זולה מכל אינדקס מרחבי.

create or replace function app.nearest_warehouse(
  p_lat double precision, p_lng double precision)
returns warehouses language sql stable security definer set search_path = public as $$
  select w.* from warehouses w
   where w.deleted_at is null and w.is_active
     and w.lat is not null and w.lng is not null
     and p_lat is not null and p_lng is not null
   order by app.haversine_km(p_lat, p_lng, w.lat, w.lng)
   limit 1
$$;

-- ===== 5. גזירת המשמרות, מודעת מחסנים ======================================
-- start_lat/start_lng הופכות ל"נקודת הייחוס להתחלה" ולא ל"מיקום האירוע":
-- מי שיוצא מהמחסן נמדד מול המחסן, ומי שמגיע לאתר מול האתר. הפרדת נקודת
-- ההתחלה מנקודת הסיום היא מה שמאפשר לשעון לשאול שאלה אחת בשני הקצוות.

alter type app.planned_shift_row add attribute warehouse_id uuid cascade;
alter type app.planned_shift_row add attribute warehouse_name text cascade;

create or replace function app.planned_shifts(p_profile_id uuid, p_from date, p_to date)
returns setof app.planned_shift_row
language plpgsql stable security definer set search_path = public as $$
declare v_gap interval;
begin
  v_gap := make_interval(mins => coalesce(
    (app.attendance_config('attendance.clock') ->> 'merge_gap_minutes')::int, 120));

  return query
  with mine as (
    -- עובד צוות
    select a.task_id as tid, bool_or(a.work_site = 'warehouse') as is_wh
      from task_assignments a
     where a.profile_id = p_profile_id
     group by a.task_id
    union all
    -- עובד קבלן, דרך הקישור בין ההתחברות לשורת הסגל
    select w.task_id, bool_or(w.work_site = 'warehouse')
      from task_contractor_workers w
      join profiles pr on pr.contractor_worker_id = w.contractor_worker_id
     where pr.id = p_profile_id
     group by w.task_id
  ),
  -- אותו אדם יכול להיות משובץ לאותה משימה בשני תפקידים (עובד וגם ראש
  -- צוות). מחסן גובר, כי מי שיוצא מהמחסן מתחיל שם בכל מקרה.
  dedup as (select m.tid, bool_or(m.is_wh) as is_wh from mine m group by m.tid),
  base as (
    select
      t.id as b_task,
      t.customer_id as b_cust,
      c.color as b_color,
      coalesce(nullif(t.title, ''), tt.name) as b_label,
      case when d.is_wh then 'warehouse' else 'field' end as b_site,
      ((t.task_date + case
          when d.is_wh and t.warehouse_start_time is not null then t.warehouse_start_time
          else coalesce(t.onsite_start_time, t.warehouse_start_time) end)
        at time zone 'Asia/Jerusalem') as b_start,
      ((t.task_date + coalesce(t.onsite_start_time, t.warehouse_start_time))
        at time zone 'Asia/Jerusalem')
        + make_interval(mins => round(coalesce(t.hours_count, 0) * 60)::int) as b_end,
      coalesce(app.task_travel_hours(t.id), 0) as b_travel,
      -- נקודת ההתחלה: המחסן למי שיוצא ממנו, האתר לכל השאר.
      case when d.is_wh then wh.lat else e.location_lat end as b_start_lat,
      case when d.is_wh then wh.lng else e.location_lng end as b_start_lng,
      -- נקודת הסיום היא תמיד האתר: שם נגמרת העבודה, גם למי שיצא מהמחסן.
      e.location_lat as b_end_lat,
      e.location_lng as b_end_lng,
      case when d.is_wh then wh.id end   as b_wh_id,
      case when d.is_wh then wh.name end as b_wh_name
    from dedup d
    join tasks t on t.id = d.tid
    left join events e on e.id = t.event_id
    left join customers c on c.id = t.customer_id
    left join warehouses wh on wh.id = t.warehouse_id and wh.deleted_at is null
    join task_types tt on tt.id = t.task_type_id
    where t.deleted_at is null
      and t.task_date between p_from and p_to
      -- משימה בלי אף שעה אינה יכולה להרכיב משמרת
      and coalesce(t.onsite_start_time, t.warehouse_start_time) is not null
  ),
  ordered as (
    select b.*,
           max(b.b_end) over (
             order by b.b_start, b.b_task
             rows between unbounded preceding and 1 preceding) as b_prev_end
    from base b
  ),
  flagged as (
    -- הפער נמדד עד סיום העבודה בשטח, בלי הנסיעה חזרה. אילו נמדד כולל
    -- נסיעה, עריכה של אזור גיאופנס הייתה מפצלת מחדש שבוע שכבר שולם.
    select o.*, case when o.b_prev_end is null or o.b_start - o.b_prev_end > v_gap
                     then 1 else 0 end as b_new
    from ordered o
  ),
  grouped as (
    select f.*, sum(f.b_new) over (
             order by f.b_start, f.b_task
             rows between unbounded preceding and current row) as b_grp
    from flagged f
  ),
  shifts as (
    select
      min(g.b_start) as s_start,
      max(g.b_end)   as s_core_end,
      -- הנסיעה חזרה מתווספת רק למשימה האחרונה במשמרת: בין שתי משימות
      -- שקרובות זו לזו אף אחד לא נוסע הביתה ובחזרה.
      (array_agg(g.b_travel   order by g.b_end desc, g.b_task desc))[1] as s_travel,
      (array_agg(g.b_task     order by g.b_end desc, g.b_task desc))[1] as s_last,
      (array_agg(g.b_end_lat  order by g.b_end desc, g.b_task desc))[1] as s_last_lat,
      (array_agg(g.b_end_lng  order by g.b_end desc, g.b_task desc))[1] as s_last_lng,
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
    group by g.b_grp
  )
  select
    p_profile_id,
    (s.s_start at time zone 'Asia/Jerusalem')::date,
    (row_number() over (
       partition by (s.s_start at time zone 'Asia/Jerusalem')::date
       order by s.s_start))::int,
    s.s_start,
    s.s_core_end + make_interval(mins => round(s.s_travel * 60)::int),
    round((extract(epoch from
      (s.s_core_end + make_interval(mins => round(s.s_travel * 60)::int) - s.s_start)
      ) / 3600.0)::numeric, 2),
    s.s_site,
    s.s_ids,
    s.s_first,
    s.s_last,
    s.s_first_lat, s.s_first_lng,
    s.s_last_lat,  s.s_last_lng,
    s.s_travel,
    case when s.s_count > 1 then s.s_label || ' +' || (s.s_count - 1)::text else s.s_label end,
    s.s_cust,
    s.s_color,
    s.s_wh_id,
    s.s_wh_name
  from shifts s
  order by s.s_start;
end $$;

-- ===== 6. השעון, מודע לכמה מחסנים ==========================================

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
  v_site_lat double precision;
  v_site_lng double precision;
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
    raise exception 'שעון הנוכחות מושבת עבורך' using errcode = '42501';
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
      raise exception 'כבר נרשמה כניסה למשמרת פתוחה' using errcode = '42501';
    end if;
  end if;

  v_grace := make_interval(mins => coalesce((v_rules ->> 'early_grace_minutes')::int, 15));
  v_shift := app.shift_at(v_me, now(), v_grace);

  if v_shift.shift_start is null then
    if not coalesce((v_rules ->> 'allow_clock_without_shift')::boolean, false) then
      raise exception 'אין לך משמרת משובצת כרגע' using errcode = '42501';
    end if;
    v_flags := v_flags || 'no_shift'::text;
  elsif now() < v_shift.shift_start - v_grace
        and not coalesce((v_rules ->> 'allow_early_clock_in')::boolean, false) then
    -- התחלה מוקדמת: חסימה, אלא אם הותרה במפורש לעובד הזה.
    raise exception 'לא ניתן להתחיל משמרת לפני השעה %',
      to_char(v_shift.shift_start at time zone 'Asia/Jerusalem', 'HH24:MI')
      using errcode = '42501';
  end if;

  -- נקודת הייחוס כבר נגזרה במשמרת: המחסן למי שיוצא ממנו, האתר לכל השאר.
  v_site_lat := v_shift.start_lat;
  v_site_lng := v_shift.start_lng;

  if v_shift.warehouse_id is not null then
    select * into v_wh from warehouses where id = v_shift.warehouse_id;
  elsif v_shift.work_site = 'warehouse' and v_site_lat is null then
    -- המשימה לא נקבה במחסן. במקום לוותר על הבדיקה, נמדדים מול המחסן
    -- הקרוב ביותר — העובד עדיין חייב להיות בתוך הרדיוס של מחסן אמיתי.
    select * into v_wh from app.nearest_warehouse(p_lat, p_lng);
    v_site_lat := v_wh.lat;
    v_site_lng := v_wh.lng;
  end if;

  -- רדיוס פר-מחסן גובר על הגלובלי, ודריסה אישית של העובד גוברת על שניהם.
  if v_wh.radius_m is not null and (select location_radius_m from worker_pay_settings
                                     where profile_id = v_me) is null then
    v_rules := v_rules || jsonb_build_object('location_radius_m', v_wh.radius_m);
  end if;

  select o_distance_m, o_flags into v_dist, v_loc_flags
    from app.check_clock_location(v_rules, p_lat, p_lng, p_accuracy, v_site_lat, v_site_lng);
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
    raise exception 'לא נמצאה משמרת פתוחה להחתמת יציאה' using errcode = '42501';
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
