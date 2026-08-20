-- 0092: מנוע התמחור של הקבלן — בסיס/מחסן/הובלה, פחות קנסות
--
-- ‏0091 הוסיף את הגדרות התמחור והקנסות בכרטיס הקבלן אבל לא חיבר אותן לחישוב.
-- כאן `app.recompute_contractor_price` הופך למנוע מלא שגוזר את מחיר המשימה
-- לקבלן מהכללים, לפי מה שסוכם:
--
--   מחיר = בסיס + תוספת מחסן − קנסות
--
--   * בסיס: משימת הובלה-בלבד (לפי אופן הביצוע) משתמשת ב-`transport_only_price`
--     במקום הבסיס; אחרת, אם יש תעריף-לעובד — מספר העובדים ששובצו × התעריף;
--     אחרת `default_task_price` (מחיר הבסיס).
--   * תוספת מחסן: `warehouse_arrival_surcharge` כשנקודת ההתחלה של הקבלן היא
--     מחסן (לא בהובלה-בלבד).
--   * קנסות שמתקזזים אוטומטית: קנס איחור לכל עובד שסומן למעקב ואיחר מעבר
--     לדקות החסד, וקנס אי-התייצבות לכל עובד שלא החתים כלל במשמרת.
--
-- המנוע פעיל רק כשמוגדר לקבלן כלל כלשהו (תעריף-לעובד / הובלה / תוספת מחסן /
-- קנס); קבלן בתמחור שטוח בלבד (מחיר משימה ידני) אינו מושפע, כמו קודם. שורה
-- ששולמה מוגנת (0057) ואינה מחושבת מחדש.
--
-- מגבלה מכוונת: הזיהוי מונע-אירועים. איחור מזוהה בהחתמה; אי-התייצבות מזוהה
-- כשמשימה שכבר עברה מחושבת מחדש (החתמה של עובד אחר באותה משימה, סגירה
-- אוטומטית, או עריכה). אין כאן ג׳וב לילי שיגזור קנס על צוות שלא החתים כלל.

-- ===== 1. עמודות: זיהוי הובלה, ודקות חסד לאיחור ===========================
alter table execution_methods
  add column if not exists is_transport_only boolean not null default false;

alter table contractors
  add column if not exists lateness_grace_minutes int
    check (lateness_grace_minutes is null or lateness_grace_minutes >= 0);

comment on column execution_methods.is_transport_only is
  'משימה באופן ביצוע זה מתומחרת לקבלן לפי מחיר ההובלה, במקום מחיר הבסיס (0092).';
comment on column contractors.lateness_grace_minutes is
  'דקות חסד לפני שאיחור נחשב לקנס. null = 0.';

-- ===== 2. המנוע =========================================================
create or replace function app.recompute_contractor_price(p_task_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_ct        contractors%rowtype;
  v_terms     task_contractor_terms%rowtype;
  v_task      tasks%rowtype;
  v_rate      numeric;
  v_transport boolean;
  v_count     int;
  v_base      numeric;
  v_surcharge numeric := 0;
  v_grace     int;
  v_late      int;
  v_noshow    int;
  v_price     numeric;
  v_active    boolean;
  v_prev      boolean;
begin
  select * into v_terms from task_contractor_terms where task_id = p_task_id;
  if v_terms.task_id is null or v_terms.paid_at is not null then return; end if;
  select * into v_ct from contractors where id = v_terms.contractor_id;
  if v_ct.id is null then return; end if;
  select * into v_task from tasks where id = p_task_id;

  -- "הובלה בלבד" נקבע לפי אופן הביצוע של המשימה.
  v_transport := exists (select 1 from execution_methods em
                          where em.id = v_task.execution_method_id and em.is_transport_only);

  -- תעריף-לעובד אפקטיבי: דריסת המשימה, אחרת ברירת המחדל של הקבלן.
  v_rate := coalesce(v_terms.price_per_worker, v_ct.price_per_worker);

  -- המנוע פעיל רק אם יש כלל תמחור/קנס. אחרת המחיר נשאר ידני/שטוח.
  v_active := v_rate is not null
           or (v_transport and v_ct.transport_only_price is not null)
           or v_ct.warehouse_arrival_surcharge is not null
           or v_ct.lateness_penalty is not null
           or v_ct.no_show_penalty is not null;
  if not v_active then return; end if;

  select count(*) into v_count from task_contractor_workers where task_id = p_task_id;

  -- בסיס: הובלה גוברת, אחרת לפי-עובד, אחרת מחיר הבסיס.
  if v_transport and v_ct.transport_only_price is not null then
    v_base := v_ct.transport_only_price;
  elsif v_rate is not null then
    v_base := v_rate * v_count;
  else
    v_base := coalesce(v_ct.default_task_price, 0);
  end if;

  -- תוספת מחסן: כשנקודת ההתחלה של הקבלן היא מחסן, ולא בהובלה-בלבד.
  if not v_transport and v_terms.work_site = 'warehouse' then
    v_surcharge := coalesce(v_ct.warehouse_arrival_surcharge, 0);
  end if;

  -- קנסות. איחור = החתמה אחרי שעת ההתחלה המתוכננת (שמוקפאת על הרשומה) מעבר
  -- לדקות החסד, לעובד שסומן למעקב. אי-התייצבות = עובד עם חשבון שלא החתים כלל,
  -- ורק למשימה שכבר עברה (task_date < היום) כדי לא לקנוס לפני תום המשמרת.
  v_grace := coalesce(v_ct.lateness_grace_minutes, 0);
  select
    coalesce(count(*) filter (
      where x.lateness_tracked and x.clock_in_at is not null and x.shift_start is not null
        and x.clock_in_at > x.shift_start + make_interval(mins => v_grace)), 0),
    coalesce(count(*) filter (
      where x.profile_id is not null and x.clock_in_at is null
        and v_task.task_date < current_date), 0)
    into v_late, v_noshow
    from (
      select cw.lateness_tracked, p.id as profile_id, e.clock_in_at, e.shift_start
        from task_contractor_workers tcw
        join contractor_workers cw on cw.id = tcw.contractor_worker_id
        left join profiles p on p.contractor_worker_id = cw.id and p.deleted_at is null
        left join lateral (
          select ae.clock_in_at, ae.shift_start
            from attendance_entries ae
           where ae.profile_id = p.id and ae.deleted_at is null
             and ae.status <> 'rejected' and p_task_id = any(ae.task_ids)
           order by ae.clock_in_at limit 1
        ) e on true
       where tcw.task_id = p_task_id
    ) x;

  v_price := greatest(0, round(
    v_base + v_surcharge
    - coalesce(v_ct.lateness_penalty, 0) * v_late
    - coalesce(v_ct.no_show_penalty, 0) * v_noshow, 2));

  v_prev := app.in_system_write();
  perform app.system_write(true);
  update task_contractor_terms set price = v_price where task_id = p_task_id;
  perform app.system_write(v_prev);
end $$;

comment on function app.recompute_contractor_price(uuid) is
  'גוזר את מחיר הקבלן למשימה: בסיס/הובלה/לפי-עובד + תוספת מחסן − קנסות איחור ואי-התייצבות.';

-- ===== 3. טריגרים נוספים שמניעים חישוב מחדש ===============================
--
-- הטריגרים של 0091 (שיבוץ עובד, שינוי תעריף-לעובד) ממשיכים לקרוא לאותה
-- פונקציה, שעכשיו מחשבת את המחיר המלא. כאן מתווספים המניעים החדשים.

-- שינוי אופן הביצוע של משימה מואצלת → ייתכן ששינה סטטוס הובלה.
create or replace function app.task_contractor_price_sync()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.contractor_id is not null
     and new.execution_method_id is distinct from old.execution_method_id then
    perform app.recompute_contractor_price(new.id);
  end if;
  return new;
end $$;

drop trigger if exists task_contractor_price_sync on tasks;
create trigger task_contractor_price_sync after update of execution_method_id on tasks
for each row execute function app.task_contractor_price_sync();

-- נקודת ההתחלה של הקבלן משתנה → תוספת מחסן משתנה. (בנוסף להתפשטות לעובדים
-- שכבר קיימת ב-0091.)
create or replace function app.tct_worksite_sync()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.work_site is distinct from old.work_site then
    perform app.system_write(true);
    update task_contractor_workers set work_site = new.work_site where task_id = new.task_id;
    perform app.system_write(false);
    perform app.recompute_contractor_price(new.task_id);
  end if;
  return new;
end $$;

-- שינוי הגדרת קנס/מחיר בכרטיס הקבלן → חישוב מחדש לכל משימותיו שטרם שולמו.
create or replace function app.contractor_rate_sync()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  perform app.recompute_contractor_price(tct.task_id)
     from task_contractor_terms tct
    where tct.contractor_id = new.id and tct.paid_at is null;
  return new;
end $$;

drop trigger if exists contractor_rate_sync on contractors;
create trigger contractor_rate_sync after update of
  price_per_worker, default_task_price, warehouse_arrival_surcharge,
  transport_only_price, lateness_penalty, no_show_penalty, lateness_grace_minutes
  on contractors
for each row execute function app.contractor_rate_sync();

-- סימון/ביטול מעקב איחורים לעובד → חישוב מחדש למשימותיו שטרם שולמו.
create or replace function app.cw_lateness_sync()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.lateness_tracked is distinct from old.lateness_tracked then
    perform app.recompute_contractor_price(tcw.task_id)
       from task_contractor_workers tcw
       join task_contractor_terms t on t.task_id = tcw.task_id and t.paid_at is null
      where tcw.contractor_worker_id = new.id;
  end if;
  return new;
end $$;

drop trigger if exists cw_lateness_sync on contractor_workers;
create trigger cw_lateness_sync after update of lateness_tracked on contractor_workers
for each row execute function app.cw_lateness_sync();

-- סימון אופן ביצוע כ"הובלה" → חישוב מחדש למשימות המואצלות שמשתמשות בו.
create or replace function app.em_transport_sync()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.is_transport_only is distinct from old.is_transport_only then
    perform app.recompute_contractor_price(t.id)
       from tasks t
       join task_contractor_terms tt on tt.task_id = t.id and tt.paid_at is null
      where t.execution_method_id = new.id;
  end if;
  return new;
end $$;

drop trigger if exists em_transport_sync on execution_methods;
create trigger em_transport_sync after update of is_transport_only on execution_methods
for each row execute function app.em_transport_sync();

-- החתמת נוכחות (כניסה/יציאה/עריכה/מחיקה/אישור) → חישוב מחדש של משימות הקבלן
-- שברשומה, כדי שקנסות איחור ואי-התייצבות יתעדכנו. `task_ids` הוא צילום
-- המשימות שהרכיבו את המשמרת (0019), ולכן הוא הקישור המדויק.
create or replace function app.attendance_contractor_penalty_sync()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_tids uuid[] := array[]::uuid[];
  v_tid  uuid;
begin
  if tg_op in ('INSERT', 'UPDATE') then v_tids := v_tids || coalesce(new.task_ids, '{}'); end if;
  if tg_op in ('UPDATE', 'DELETE') then v_tids := v_tids || coalesce(old.task_ids, '{}'); end if;
  for v_tid in select distinct u from unnest(v_tids) u where u is not null loop
    if exists (select 1 from tasks t where t.id = v_tid and t.contractor_id is not null) then
      perform app.recompute_contractor_price(v_tid);
    end if;
  end loop;
  return coalesce(new, old);
end $$;

drop trigger if exists attendance_contractor_penalty_sync on attendance_entries;
create trigger attendance_contractor_penalty_sync
after insert or update or delete on attendance_entries
for each row execute function app.attendance_contractor_penalty_sync();
