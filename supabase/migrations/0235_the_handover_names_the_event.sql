-- 0235: ההתראה על המעבר בין ארקו לוייפר נוקבת באירוע ומובילה אליו
--
-- הבקשה: **"כשלקוח ארקו מעביר משימות מארקו לווייפר או מווייפר לארקו — לחיצה
-- על ההתראה תכניס לדף האירוע, ובהתראה יהיה רשום איזה אירוע."**
--
-- עד כאן (0136, 0142) גוף ההתראה היה רק שם המשימה ("הקמה"), והקישור הוביל
-- ללו״ז (`/board?task=…`) כמו כל התראת משימה (0054, 0227). מנהל שקיבל
-- "המשימה עברה: וייפר ← ארקו · הקמה" לא ידע על איזה אירוע מדובר בלי לפתוח.
--
-- ‏1. הפולט כותב בגוף את האירוע: שם הלקוח הסופי (או שם הלקוח), מספר האירוע
--    ותאריכו, ואחריהם המשימה — "לקוח קצה · EV-29 · 05/03/2028 — הקמה".
--    הכותרת (הכיוון) לא השתנתה.
-- ‏2. ‏`app.notification_link` (אחרונה 0227, מועתקת במלואה): התראה מסוג
--    `task_performed_by_changed` מובילה ל-`/events/<event_id>`. הישות נשארת
--    המשימה (`entity_type = 'task'`), כדי שכל מה שנשען עליה ימשיך לעבוד.
--    הקהל הוא מנהלי מערכת בלבד, והם רואים כל אירוע.
-- ‏3. התראות קיימות מהסוג הזה מקבלות את הקישור והגוף החדשים.

-- ===== 1. תווית האירוע ======================================================

create or replace function app.event_notify_label(p_event_id uuid)
returns text language sql stable security definer set search_path = public as $$
  select concat_ws(' · ',
           coalesce(nullif(e.end_client_name, ''), c.name, 'אירוע'),
           nullif(e.event_number, ''),
           to_char(e.event_date, 'DD/MM/YYYY'))
    from events e
    left join customers c on c.id = e.customer_id
   where e.id = p_event_id
$$;

revoke execute on function app.event_notify_label(uuid) from anon, authenticated, public;

-- ===== 2. הפולט ==============================================================

create or replace function app.notify_performed_by_changed()
returns trigger language plpgsql security definer set search_path = public as $$
declare r record; v_dir text; v_label text;
begin
  if new.performed_by is not distinct from old.performed_by then return new; end if;
  if not app.notification_in_scope('task_performed_by_changed', 'customer', new.customer_id) then
    return new;
  end if;

  v_dir := case when new.performed_by = 'arko' then 'וייפר ← ארקו' else 'ארקו ← וייפר' end;
  v_label := concat_ws(' — ', app.event_notify_label(new.event_id), app.task_notify_label(new));

  for r in select id from profiles
    where is_admin and is_active and deleted_at is null
      and id is distinct from app.profile_id()
  loop
    perform app.notify(r.id, 'task_performed_by_changed',
      'המשימה עברה: ' || v_dir, v_label, 'task', new.id);
  end loop;
  return new;
end $$;

comment on function app.notify_performed_by_changed() is
  'מעבר משימה בין זרועות הביצוע מודיע למנהלי המערכת (0136), לשני הכיוונים; הגוף נוקב באירוע (0235).';

-- ===== 3. הקישור =============================================================

create or replace function app.notification_link(
  p_recipient uuid, p_type text, p_entity_type text, p_entity_id uuid)
returns text language plpgsql stable security definer set search_path = public as $$
declare v_date date; v_event uuid;
begin
  if p_entity_type = 'admin_mission' then
    return '/command' || coalesce('?m=' || p_entity_id, '');
  end if;

  if p_entity_id is null then return '/'; end if;

  if p_entity_type = 'event' then
    return '/events/' || p_entity_id;
  end if;

  -- ‏0235: המעבר בין ארקו לוייפר מוביל לדף האירוע של המשימה
  if p_entity_type = 'task' and p_type = 'task_performed_by_changed' then
    select event_id into v_event from tasks where id = p_entity_id;
    if v_event is not null then
      return '/events/' || v_event;
    end if;
  end if;

  if p_entity_type = 'task' then
    select task_date into v_date from tasks where id = p_entity_id;
    return '/board?task=' || p_entity_id
           || coalesce('&date=' || to_char(v_date, 'YYYY-MM-DD'), '');
  end if;

  if p_entity_type = 'attendance_entry' then
    if p_type in ('attendance_submitted', 'attendance_clock_in', 'attendance_clock_out') then
      select work_date into v_date from attendance_entries where id = p_entity_id;
      return '/attendance?entry=' || p_entity_id
             || coalesce('&date=' || to_char(v_date, 'YYYY-MM-DD'), '');
    end if;
    return '/my/attendance?entry=' || p_entity_id;
  end if;

  if p_entity_type = 'vehicle' then
    return '/vehicles/' || p_entity_id;
  end if;

  if p_entity_type = 'payslip' then
    return '/my/payslips';
  end if;

  return '/';
end $$;

-- ===== 4. התראות שכבר נשלחו ==================================================

update notifications n
   set link = '/events/' || t.event_id,
       body = concat_ws(' — ', app.event_notify_label(t.event_id), app.task_notify_label(t))
  from tasks t
 where n.type = 'task_performed_by_changed'
   and n.entity_type = 'task'
   and t.id = n.entity_id;
