-- 0093: קנס אי-התייצבות ידני, תוספת מחסן לפי מספר עובדים, וכמות עובדים לקבלן
--
--   * קנס אי-התייצבות מופעל בסימון ידני של המנהל (task_contractor_workers.no_show),
--     ולא בזיהוי אוטומטי מהנוכחות. איחור נשאר אוטומטי.
--   * תוספת הגעה למחסן מוכפלת במספר העובדים ששובצו.
--   * לקבלן כמות עובדים משלו (task_contractor_terms.contractor_worker_count),
--     בלתי תלויה בכמות שהמשימה צריכה — והיא גם התקרה לשיבוץ עובדיו.
--   * פירוט התמחור והקנסות נשמר ב-price_parts כדי שהמנהל יראה ממה מורכב המחיר.
--   * מנהל הקבלן לא רואה את בורר התצוגה/העמודות (board.columns נדחה לו).

-- ===== 1. עמודות =========================================================
alter table task_contractor_workers
  add column if not exists no_show boolean not null default false;

alter table task_contractor_terms
  add column if not exists contractor_worker_count int
    check (contractor_worker_count is null or contractor_worker_count >= 0),
  add column if not exists price_parts jsonb;

comment on column task_contractor_workers.no_show is
  'המנהל סימן שהעובד לא התייצב. מפעיל את קנס אי-ההתייצבות (0093).';
comment on column task_contractor_terms.contractor_worker_count is
  'כמה עובדים הקבלן מביא — תקרת השיבוץ, בלתי תלויה ב-tasks.worker_count (0093).';
comment on column task_contractor_terms.price_parts is
  'פירוט חישוב מחיר הקבלן: בסיס, תוספת מחסן, וקנסות (0093).';

-- ===== 2. תקרת השיבוץ לפי כמות העובדים של הקבלן ===========================
create or replace function app.check_contractor_worker_limit()
returns trigger language plpgsql as $$
declare
  v_limit int;
  v_current int;
begin
  -- התקרה היא הכמות שהקבלן מביא, ואם לא הוגדרה — כמות המשימה (0093).
  select coalesce(tct.contractor_worker_count, t.worker_count) into v_limit
    from tasks t
    left join task_contractor_terms tct on tct.task_id = t.id
   where t.id = new.task_id;
  select count(*) into v_current from task_contractor_workers where task_id = new.task_id;
  if v_limit is not null and v_limit > 0 and v_current >= v_limit then
    raise exception 'חריגה מכמות העובדים שהקבלן אמור להביא (%)', v_limit;
  end if;
  return new;
end $$;

-- ===== 3. מנוע התמחור, גרסה 2 ============================================
--
-- תוספת מחסן מוכפלת במספר העובדים; אי-התייצבות נספרת מהסימון הידני; ופירוט
-- החישוב נשמר ב-price_parts. איחור נשאר אוטומטי מהנוכחות.
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

  v_transport := exists (select 1 from execution_methods em
                          where em.id = v_task.execution_method_id and em.is_transport_only);

  v_rate := coalesce(v_terms.price_per_worker, v_ct.price_per_worker);

  v_active := v_rate is not null
           or (v_transport and v_ct.transport_only_price is not null)
           or v_ct.warehouse_arrival_surcharge is not null
           or v_ct.lateness_penalty is not null
           or v_ct.no_show_penalty is not null;
  if not v_active then return; end if;

  select count(*) into v_count from task_contractor_workers where task_id = p_task_id;

  if v_transport and v_ct.transport_only_price is not null then
    v_base := v_ct.transport_only_price;
  elsif v_rate is not null then
    v_base := v_rate * v_count;
  else
    v_base := coalesce(v_ct.default_task_price, 0);
  end if;

  -- תוספת מחסן מוכפלת במספר העובדים ששובצו (0093).
  if not v_transport and v_terms.work_site = 'warehouse' then
    v_surcharge := coalesce(v_ct.warehouse_arrival_surcharge, 0) * v_count;
  end if;

  -- איחור: אוטומטי מהנוכחות, לעובד שסומן למעקב ואיחר מעבר לדקות החסד.
  v_grace := coalesce(v_ct.lateness_grace_minutes, 0);
  select coalesce(count(*) filter (
      where x.lateness_tracked and x.clock_in_at is not null and x.shift_start is not null
        and x.clock_in_at > x.shift_start + make_interval(mins => v_grace)), 0)
    into v_late
    from (
      select cw.lateness_tracked, e.clock_in_at, e.shift_start
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

  -- אי-התייצבות: מהסימון הידני של המנהל (0093), לא מהנוכחות.
  select coalesce(count(*) filter (where no_show), 0) into v_noshow
    from task_contractor_workers where task_id = p_task_id;

  v_price := greatest(0, round(
    v_base + v_surcharge
    - coalesce(v_ct.lateness_penalty, 0) * v_late
    - coalesce(v_ct.no_show_penalty, 0) * v_noshow, 2));

  v_prev := app.in_system_write();
  perform app.system_write(true);
  update task_contractor_terms
     set price = v_price,
         price_parts = jsonb_build_object(
           'base', round(v_base, 2),
           'surcharge', round(v_surcharge, 2),
           'worker_count', v_count,
           'transport', v_transport,
           'late_count', v_late,
           'late_penalty_each', coalesce(v_ct.lateness_penalty, 0),
           'noshow_count', v_noshow,
           'noshow_penalty_each', coalesce(v_ct.no_show_penalty, 0),
           'penalty_total', round(coalesce(v_ct.lateness_penalty, 0) * v_late
                                  + coalesce(v_ct.no_show_penalty, 0) * v_noshow, 2))
   where task_id = p_task_id;
  perform app.system_write(v_prev);
end $$;

comment on function app.recompute_contractor_price(uuid) is
  'מחיר הקבלן: בסיס/הובלה/לפי-עובד + תוספת מחסן×עובדים − קנסות איחור (אוטומטי) ואי-התייצבות (ידני). שומר פירוט ב-price_parts.';

-- סימון/ביטול אי-התייצבות מפעיל חישוב מחדש.
create or replace function app.tcw_noshow_sync()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.no_show is distinct from old.no_show then
    perform app.recompute_contractor_price(new.task_id);
  end if;
  return new;
end $$;

drop trigger if exists tcw_noshow_sync on task_contractor_workers;
create trigger tcw_noshow_sync after update of no_show on task_contractor_workers
for each row execute function app.tcw_noshow_sync();

-- ===== 4. מנהל הקבלן בלי בורר התצוגה/העמודות =============================
insert into role_permissions (role_id, permission_key, allowed)
select r.id, 'board.columns', false
from permission_roles r where r.key = 'contractor_manager'
on conflict (role_id, permission_key) do update set allowed = false;
