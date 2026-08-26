-- 0096b: מנוע התמחור לפי (משימה, קבלן)
--
-- מכיוון שלמשימה יש עכשיו כמה שורות terms, החישוב עובר לפר-קבלן. הגרסה עם
-- ארגומנט אחד (task) מריצה את כולם; הגרסה עם שני ארגומנטים מחשבת קבלן אחד.

-- קבלן אחד במשימה.
create or replace function app.recompute_contractor_price(p_task_id uuid, p_contractor_id uuid)
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
  select * into v_terms from task_contractor_terms
   where task_id = p_task_id and contractor_id = p_contractor_id;
  if v_terms.task_id is null or v_terms.paid_at is not null then return; end if;
  select * into v_ct from contractors where id = p_contractor_id;
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

  -- רק העובדים של הקבלן הזה במשימה.
  select count(*) into v_count
    from task_contractor_workers tcw
    join contractor_workers cw on cw.id = tcw.contractor_worker_id
   where tcw.task_id = p_task_id and cw.contractor_id = p_contractor_id;

  if v_transport and v_ct.transport_only_price is not null then
    v_base := v_ct.transport_only_price;
  elsif v_rate is not null then
    v_base := v_rate * v_count;
  else
    v_base := coalesce(v_ct.default_task_price, 0);
  end if;

  if not v_transport and v_terms.work_site = 'warehouse' then
    v_surcharge := coalesce(v_ct.warehouse_arrival_surcharge, 0) * v_count;
  end if;

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
       where tcw.task_id = p_task_id and cw.contractor_id = p_contractor_id
    ) x;

  select coalesce(count(*) filter (where tcw.no_show), 0) into v_noshow
    from task_contractor_workers tcw
    join contractor_workers cw on cw.id = tcw.contractor_worker_id
   where tcw.task_id = p_task_id and cw.contractor_id = p_contractor_id;

  v_price := greatest(0, round(
    v_base + v_surcharge
    - coalesce(v_ct.lateness_penalty, 0) * v_late
    - coalesce(v_ct.no_show_penalty, 0) * v_noshow, 2));

  v_prev := app.in_system_write();
  perform app.system_write(true);
  update task_contractor_terms
     set price = v_price,
         price_parts = jsonb_build_object(
           'base', round(v_base, 2), 'surcharge', round(v_surcharge, 2),
           'worker_count', v_count, 'transport', v_transport,
           'late_count', v_late, 'late_penalty_each', coalesce(v_ct.lateness_penalty, 0),
           'noshow_count', v_noshow, 'noshow_penalty_each', coalesce(v_ct.no_show_penalty, 0),
           'penalty_total', round(coalesce(v_ct.lateness_penalty, 0) * v_late
                                  + coalesce(v_ct.no_show_penalty, 0) * v_noshow, 2))
   where task_id = p_task_id and contractor_id = p_contractor_id;
  perform app.system_write(v_prev);
end $$;

-- כל הקבלנים במשימה.
create or replace function app.recompute_contractor_price(p_task_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare r record;
begin
  for r in select contractor_id from task_contractor_terms where task_id = p_task_id loop
    perform app.recompute_contractor_price(p_task_id, r.contractor_id);
  end loop;
end $$;

-- ===== טריגרים: לפי הקבלן של העובד/השורה ==================================

-- שיבוץ/הסרת עובד → הקבלן של אותו עובד.
create or replace function app.tcw_price_sync()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_ctr uuid;
begin
  select contractor_id into v_ctr from contractor_workers
   where id = coalesce(new.contractor_worker_id, old.contractor_worker_id);
  if v_ctr is not null then
    perform app.recompute_contractor_price(coalesce(new.task_id, old.task_id), v_ctr);
  end if;
  return coalesce(new, old);
end $$;

create or replace function app.tcw_noshow_sync()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_ctr uuid;
begin
  if new.no_show is distinct from old.no_show then
    select contractor_id into v_ctr from contractor_workers where id = new.contractor_worker_id;
    if v_ctr is not null then
      perform app.recompute_contractor_price(new.task_id, v_ctr);
    end if;
  end if;
  return new;
end $$;

-- שינוי תעריף/מחיר על שורת terms → אותו קבלן.
create or replace function app.tct_rate_sync()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.price_per_worker is distinct from old.price_per_worker then
    perform app.recompute_contractor_price(new.task_id, new.contractor_id);
  end if;
  return new;
end $$;

-- שינוי נקודת התחלה על שורת terms → עובדי אותו קבלן בלבד, ואז חישוב מחדש.
create or replace function app.tct_worksite_sync()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.work_site is distinct from old.work_site then
    perform app.system_write(true);
    update task_contractor_workers tcw
       set work_site = new.work_site
      from contractor_workers cw
     where tcw.contractor_worker_id = cw.id
       and tcw.task_id = new.task_id and cw.contractor_id = new.contractor_id;
    perform app.system_write(false);
    perform app.recompute_contractor_price(new.task_id, new.contractor_id);
  end if;
  return new;
end $$;

-- שינוי הגדרות הקבלן → כל שורותיו שטרם שולמו.
create or replace function app.contractor_rate_sync()
returns trigger language plpgsql security definer set search_path = public as $$
declare r record;
begin
  for r in select task_id from task_contractor_terms
            where contractor_id = new.id and paid_at is null loop
    perform app.recompute_contractor_price(r.task_id, new.id);
  end loop;
  return new;
end $$;

-- ===== תקרת שיבוץ לפי הקבלן של העובד ======================================
create or replace function app.check_contractor_worker_limit()
returns trigger language plpgsql as $$
declare
  v_ctr uuid;
  v_limit int;
  v_current int;
begin
  select contractor_id into v_ctr from contractor_workers where id = new.contractor_worker_id;
  select coalesce(tct.contractor_worker_count, t.worker_count) into v_limit
    from tasks t
    left join task_contractor_terms tct on tct.task_id = t.id and tct.contractor_id = v_ctr
   where t.id = new.task_id;
  select count(*) into v_current
    from task_contractor_workers tcw
    join contractor_workers cw on cw.id = tcw.contractor_worker_id
   where tcw.task_id = new.task_id and cw.contractor_id = v_ctr;
  if v_limit is not null and v_limit > 0 and v_current >= v_limit then
    raise exception 'חריגה מכמות העובדים שהקבלן אמור להביא (%)', v_limit;
  end if;
  return new;
end $$;

-- ===== שיבוץ עובד קבלן — הקבלן נגזר מהעובד ================================
-- הקבלן של העובד (contractor_workers.contractor_id) קובע לאיזו שורת terms הוא
-- שייך; המשימה חייבת להיות מואצלת לאותו קבלן. כך אפשר לשבץ עובדים של כמה
-- קבלנים לאותה משימה.
create or replace function contractor_assign_worker(
  p_task_id uuid,
  p_worker_id uuid default null,
  p_profile_id uuid default null,
  p_on boolean default true,
  p_work_site text default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_ctr    uuid;
  v_mine   uuid := app.contractor_id();
  v_worker uuid := p_worker_id;
  v_prof   profiles%rowtype;
  v_site   text := p_work_site;
begin
  if not (app.has('portal.assign_workers') or app.has('contractors.assign_workers')) then
    raise exception 'אין לך הרשאה לשבץ עובדי קבלן' using errcode = '42501';
  end if;

  -- פתרון העובד והקבלן שלו.
  if v_worker is null then
    if p_profile_id is null then
      raise exception 'חובה לנקוב בעובד או בחשבון' using errcode = '22023';
    end if;
    select * into v_prof from profiles where id = p_profile_id and deleted_at is null;
    if v_prof.id is null then
      raise exception 'העובד לא נמצא' using errcode = '42501';
    end if;
    v_ctr := v_prof.contractor_id;
    v_worker := v_prof.contractor_worker_id;
    if v_worker is null then
      if v_ctr is null then
        raise exception 'לחשבון אין קבלן משויך' using errcode = '42501';
      end if;
      insert into contractor_workers (contractor_id, full_name, phone)
      values (v_ctr, v_prof.full_name, v_prof.phone)
      returning id into v_worker;
      update profiles set contractor_worker_id = v_worker where id = v_prof.id;
    end if;
  else
    select contractor_id into v_ctr from contractor_workers
     where id = v_worker and deleted_at is null;
  end if;
  if v_ctr is null then
    raise exception 'לא נמצא קבלן לעובד' using errcode = '42501';
  end if;

  -- המשימה חייבת להיות מואצלת לקבלן של העובד.
  if not exists (select 1 from task_contractor_terms
                  where task_id = p_task_id and contractor_id = v_ctr) then
    raise exception 'המשימה אינה מואצלת לקבלן של העובד' using errcode = '42501';
  end if;

  -- קבלן משבץ רק את עובדיו; איש משרד צריך את המפתח המשרדי לקבלן אחר.
  if v_ctr is distinct from v_mine then
    perform app.require('contractors.assign_workers');
  end if;

  if v_site is null then
    select coalesce(work_site, 'field') into v_site
      from task_contractor_terms where task_id = p_task_id and contractor_id = v_ctr;
    v_site := coalesce(v_site, 'field');
  end if;
  if v_site not in ('field', 'warehouse') then
    raise exception 'אתר עבודה לא חוקי: %', v_site using errcode = '22023';
  end if;

  if p_on then
    insert into task_contractor_workers (task_id, contractor_worker_id, work_site)
    values (p_task_id, v_worker, v_site)
    on conflict (task_id, contractor_worker_id) do update set work_site = excluded.work_site;
  else
    delete from task_contractor_workers
     where task_id = p_task_id and contractor_worker_id = v_worker;
  end if;

  return v_worker;
end $$;

revoke execute on function
  public.contractor_assign_worker(uuid, uuid, uuid, boolean, text) from anon, public;
