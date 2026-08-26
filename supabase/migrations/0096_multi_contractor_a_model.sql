-- 0096a: כמה קבלנים על משימה אחת — המודל
--
-- ‏task_contractor_terms הופך לרב-שורות למשימה (PK מורכב), ושורה לכל קבלן
-- שהואצל אליו — כל אחת עם מחיר, תעריף-לעובד, כמות עובדים, נקודת התחלה וקנסות
-- משלה. `tasks.contractor_id` נשאר כשיקוף של הקבלן ה"ראשי" (המוקדם), לתאימות
-- עם קריאות שעדיין מציגות ערך יחיד, ומתוחזק בטריגר על ה-terms.
--
-- ההאצלה עוברת עכשיו דרך RPC (delegate/undelegate) ולא דרך כתיבה ל-
-- tasks.contractor_id, ולכן הטריגר הישן שסינכרן tasks→terms מוסר.

-- ===== 1. מפתח מורכב =====================================================
alter table task_contractor_terms drop constraint task_contractor_terms_pkey;
alter table task_contractor_terms add primary key (task_id, contractor_id);

-- ===== 2. המודל הישן (tasks→terms) מוסר ==================================
-- הטריגר `tasks_contractor_terms` (0003) הריץ את sync_contractor_terms שהניח
-- שורה אחת ('on conflict (task_id)'). מעכשיו ה-terms הוא מקור האמת.
drop trigger if exists tasks_contractor_terms on tasks;

-- ‏tasks.contractor_id הופך לשיקוף של הקבלן הראשי (המוקדם לפי created_at).
create or replace function app.mirror_task_contractor()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_task uuid := coalesce(new.task_id, old.task_id);
begin
  perform app.system_write(true);
  update tasks set contractor_id = (
      select contractor_id from task_contractor_terms
       where task_id = v_task
       order by created_at, contractor_id limit 1)
   where id = v_task;
  perform app.system_write(false);
  return coalesce(new, old);
end $$;

drop trigger if exists mirror_task_contractor on task_contractor_terms;
create trigger mirror_task_contractor after insert or delete on task_contractor_terms
for each row execute function app.mirror_task_contractor();

-- ===== 3. האצלה/ביטול האצלה דרך RPC ======================================
create or replace function contractor_delegate(p_task_id uuid, p_contractor_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform app.require('tasks.delegate');
  if not exists (select 1 from tasks where id = p_task_id and deleted_at is null) then
    raise exception 'המשימה לא נמצאה' using errcode = '42501';
  end if;
  perform app.system_write(true);
  insert into task_contractor_terms (task_id, contractor_id, price)
  values (p_task_id, p_contractor_id,
          coalesce((select default_task_price from contractors where id = p_contractor_id), 0))
  on conflict (task_id, contractor_id) do nothing;
  perform app.system_write(false);
  perform app.recompute_contractor_price(p_task_id, p_contractor_id);
end $$;

create or replace function contractor_undelegate(p_task_id uuid, p_contractor_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform app.require('tasks.delegate');
  if exists (select 1 from task_contractor_terms
              where task_id = p_task_id and contractor_id = p_contractor_id and paid_at is not null) then
    raise exception 'לא ניתן להסיר קבלן ששולם עליו. בטל תחילה את סימון התשלום.';
  end if;
  perform app.system_write(true);
  -- עובדי אותו קבלן במשימה יורדים איתו.
  delete from task_contractor_workers tcw
   using contractor_workers cw
   where tcw.contractor_worker_id = cw.id
     and tcw.task_id = p_task_id and cw.contractor_id = p_contractor_id;
  delete from task_contractor_terms
   where task_id = p_task_id and contractor_id = p_contractor_id;
  perform app.system_write(false);
end $$;

revoke execute on function public.contractor_delegate(uuid, uuid) from anon, public;
revoke execute on function public.contractor_undelegate(uuid, uuid) from anon, public;

comment on function public.contractor_delegate(uuid, uuid) is
  'האצלת משימה לקבלן (0096) — מוסיף שורת terms. תומך בכמה קבלנים על משימה.';
comment on function public.contractor_undelegate(uuid, uuid) is
  'ביטול האצלה לקבלן במשימה (0096) — מסיר את שורת ה-terms ואת עובדי הקבלן.';
