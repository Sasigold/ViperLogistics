-- 0226: לו״ז המחסן נגזר מהשטח — הכנה 3 ימים לפני ההקמה, החזרה לפי שעת הסיום
--
-- הדיווח: **"המשימות מחסן שנוצרות — ההכנה ל-3 ימים לפני תאריך ההקמה,
-- וההחזרה: אם שעת הסיום בשטח היא עד 10 של אותו היום אז לאותו היום, ואם
-- אחרי — ליום שלמחרת. אם עורכים את שעות ההקמה והפירוק, זה יעדכן גם את
-- משימות המחסן. ובדף האירוע הלקוח יראה את משימות לו״ז המחסן של האירוע.
-- רק ללקוח ארקו."**
--
-- **"רק ארקו" הוא עדיין הדגל.** לו״ז המחסן כולו קיים רק ללקוח שהדגל
-- `customers.warehouse_schedule_enabled` דלוק אצלו (0196), והוא דלוק רק
-- לארקו. הכלל החדש חי בתוך הלו״ז, ולכן אינו נוגע באף לקוח אחר — ושום דבר
-- כאן אינו משווה לשם.
--
-- **הכלל.** ההכנה = יום ההקמה המוקדם פחות 3 ימים (בלי הקמה — יום האירוע
-- פחות 3). ההחזרה = לכל משימת פירוק, רגע הסיום בשטח הוא יום הפירוק + שעת
-- ההתחלה בשטח + מספר השעות (כמו `onsite_end_time`, אבל כחותמת זמן, כך
-- שפירוק שחוצה חצות נופל ביום שאחריו). סיום עד 10:00 כולל — ההחזרה ביום
-- הסיום; אחרי 10:00 — ביום שלמחרת. פירוק בלי שעה או בלי משך — שעת הסיום
-- אינה ידועה, וההחזרה ביום שלמחרת. כמה פירוקים — המאוחר מביניהם. בלי פירוק
-- בכלל — יום האירוע + 1.
--
-- **העריכה בשטח גוררת את המחסן.** התאריך עדיין נגזר בקריאה (0196), ולכן
-- הזזת הקמה או פירוק כבר מזיזה את ההכנה וההחזרה — כל עוד המחסן לא קבע להן
-- יום ביד. החדש: כשיום, שעת ההתחלה בשטח או מספר השעות של הקמה/פירוק
-- משתנים (או שמשימה כזו נוספת, נמחקת או משנה סוג), היום שנקבע ביד לעמודה
-- המתאימה מתנקה, והיא חוזרת להיות נגזרת. הבקשה היא שהשינוי בשטח יגיע
-- למחסן; יום ידני שהיה נשאר היה מסתיר אותו.
--
-- **בדף האירוע.** `warehouse_event_tasks(event_id)` מחזירה את שתי השורות של
-- האירוע, באותה צורה ובאותו שער (`app.warehouse_customer_visible`) כמו
-- `warehouse_schedule` — לקוח ארקו עם `warehouse.view` (מנהל וצופה, 0196)
-- רואה אותן; לקוח אחר מקבל רשימה ריקה. שתיהן נשענות על פונקציה פנימית אחת,
-- `app.warehouse_rows`, כדי שהכלל ייכתב פעם אחת.

-- ===== 1. התאריכים הנגזרים ================================================

create or replace function app.warehouse_anchor_dates(p_event_id uuid, p_event_date date)
returns table (prep_date date, return_date date)
language sql stable security definer set search_path = public as $$
  select
    coalesce(
      (select min(t.task_date) from tasks t join task_types tt on tt.id = t.task_type_id
        where t.event_id = p_event_id and t.deleted_at is null and tt.code = 'setup'),
      p_event_date) - 3,
    coalesce(
      (select max(case
                when t.onsite_start_time is null or t.hours_count is null then t.task_date + 1
                else (x.end_at)::date
                     + case when (x.end_at)::time <= time '10:00' then 0 else 1 end
              end)
         from tasks t
         join task_types tt on tt.id = t.task_type_id
         cross join lateral (
           select t.task_date + t.onsite_start_time
                  + make_interval(mins => round(coalesce(t.hours_count, 0) * 60)::int) as end_at
         ) x
        where t.event_id = p_event_id and t.deleted_at is null and tt.code = 'teardown'),
      p_event_date + 1)
$$;

comment on function app.warehouse_anchor_dates(uuid, date) is
  'לו״ז מחסן (0226): הכנה = הקמה − 3 ימים; החזרה = יום סיום הפירוק אם הסתיים עד 10:00, אחרת למחרת.';

revoke execute on function app.warehouse_anchor_dates(uuid, date) from anon, public, authenticated;

-- ===== 2. השורות — פעם אחת לשתי הכניסות ===================================
--
-- ‏`p_event_id` מלא: שתי השורות של האירוע הזה, בלי חלון תאריכים. ריק:
-- כל האירועים בטווח, כמו 0196. השער בפנים, ולכן גם מי שיקבל אותה (הסיד של
-- הבדיקות מחזיר הרשאות לכל פונקציה) אינו רואה יותר מהלו״ז.
create or replace function app.warehouse_rows(p_from date, p_to date, p_event_id uuid)
returns table (
  event_id        uuid,
  kind            warehouse_task_kind,
  customer_id     uuid,
  customer_name   text,
  customer_color  text,
  event_number    text,
  end_client_name text,
  event_date      date,
  task_date       date,
  date_is_manual  boolean,
  start_time      time,
  duration_hours  numeric,
  notes           text,
  final_approved  boolean,
  event_ready     boolean,
  checked         boolean,
  updated_at      timestamptz)
language sql stable security definer set search_path = public as $$
  with ev as (
    select e.id, e.customer_id, e.event_number, e.end_client_name, e.event_date,
           c.name as customer_name, c.color as customer_color
      from events e
      join customers c on c.id = e.customer_id
     where e.deleted_at is null
       and e.status_id is distinct from (select app.cancelled_event_status_id())
       and (case when p_event_id is null
                 then e.event_date between p_from - 31 and p_to + 31
                 else e.id = p_event_id end)
       and app.warehouse_customer_visible(e.customer_id)
  ),
  wr as (
    select ev.id as event_id, k.kind, ev.customer_id, ev.customer_name, ev.customer_color,
           ev.event_number, ev.end_client_name, ev.event_date,
           coalesce(w.task_date,
                    case k.kind when 'prep' then d.prep_date else d.return_date end) as task_date,
           w.task_date is not null as date_is_manual,
           w.start_time, coalesce(w.duration_hours, 0) as duration_hours, w.notes,
           coalesce(w.final_approved, false) as final_approved,
           coalesce(w.event_ready, false) as event_ready,
           coalesce(w.checked, false) as checked,
           w.updated_at
      from ev
      cross join lateral app.warehouse_anchor_dates(ev.id, ev.event_date) d
      cross join (values ('prep'::warehouse_task_kind), ('return'::warehouse_task_kind)) k(kind)
      left join warehouse_tasks w on w.event_id = ev.id and w.kind = k.kind
  )
  select * from wr
   where p_event_id is not null or task_date between p_from and p_to
$$;

revoke execute on function app.warehouse_rows(date, date, uuid) from anon, public, authenticated;

-- ===== 3. הלו״ז — אותה חתימה, הכלל החדש ===================================

create or replace function warehouse_schedule(p_from date, p_to date)
returns table (
  event_id        uuid,
  kind            warehouse_task_kind,
  customer_id     uuid,
  customer_name   text,
  customer_color  text,
  event_number    text,
  end_client_name text,
  event_date      date,
  task_date       date,
  date_is_manual  boolean,
  start_time      time,
  duration_hours  numeric,
  notes           text,
  final_approved  boolean,
  event_ready     boolean,
  checked         boolean,
  updated_at      timestamptz)
language sql stable security definer set search_path = public as $$
  select * from app.warehouse_rows(p_from, p_to, null) r
   order by r.task_date, r.start_time nulls last, r.kind, r.event_number
$$;

comment on function warehouse_schedule(date, date) is
  'לו״ז המחסן בטווח (0196, הכלל 0226): הכנה והחזרה לכל אירוע של לקוח שהמודול פתוח לו.';

revoke execute on function warehouse_schedule(date, date) from anon, public;
grant execute on function warehouse_schedule(date, date) to authenticated;

-- ===== 4. בדף האירוע ======================================================

create or replace function warehouse_event_tasks(p_event_id uuid)
returns table (
  event_id        uuid,
  kind            warehouse_task_kind,
  customer_id     uuid,
  customer_name   text,
  customer_color  text,
  event_number    text,
  end_client_name text,
  event_date      date,
  task_date       date,
  date_is_manual  boolean,
  start_time      time,
  duration_hours  numeric,
  notes           text,
  final_approved  boolean,
  event_ready     boolean,
  checked         boolean,
  updated_at      timestamptz)
language sql stable security definer set search_path = public as $$
  select * from app.warehouse_rows(null, null, p_event_id) r
   order by r.kind
$$;

comment on function warehouse_event_tasks(uuid) is
  'משימות לו״ז המחסן של אירוע אחד, לדף האירוע (0226). ריק כשהמודול סגור ללקוח או לקורא.';

revoke execute on function warehouse_event_tasks(uuid) from anon, public;
grant execute on function warehouse_event_tasks(uuid) to authenticated;

-- ===== 5. עריכה בשטח מנקה את היום הידני ===================================

create or replace function app.warehouse_follow_field()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_old_code text;
  v_new_code text;
begin
  select code into v_new_code from task_types where id = new.task_type_id;
  if tg_op = 'UPDATE' then
    select code into v_old_code from task_types where id = old.task_type_id;
  end if;

  if coalesce(v_new_code, '') not in ('setup', 'teardown')
     and coalesce(v_old_code, '') not in ('setup', 'teardown') then
    return null;
  end if;

  update warehouse_tasks w set task_date = null
   where w.task_date is not null
     and (   (w.event_id = new.event_id
              and w.kind = case v_new_code when 'setup' then 'prep'::warehouse_task_kind
                                           when 'teardown' then 'return'::warehouse_task_kind end)
          or (tg_op = 'UPDATE' and w.event_id = old.event_id
              and w.kind = case v_old_code when 'setup' then 'prep'::warehouse_task_kind
                                           when 'teardown' then 'return'::warehouse_task_kind end));
  return null;
end $$;

revoke execute on function app.warehouse_follow_field() from anon, public, authenticated;

create trigger tasks_warehouse_follow_ins after insert on tasks
  for each row when (new.event_id is not null)
  execute function app.warehouse_follow_field();

create trigger tasks_warehouse_follow_upd after update of
    task_date, onsite_start_time, hours_count, deleted_at, task_type_id, event_id on tasks
  for each row when (
       old.task_date is distinct from new.task_date
    or old.onsite_start_time is distinct from new.onsite_start_time
    or old.hours_count is distinct from new.hours_count
    or old.deleted_at is distinct from new.deleted_at
    or old.task_type_id is distinct from new.task_type_id
    or old.event_id is distinct from new.event_id)
  execute function app.warehouse_follow_field();
