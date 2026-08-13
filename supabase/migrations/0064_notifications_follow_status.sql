-- 0064: מתי התראת שיבוץ יוצאת, ולמי הקטלוג מציע מה
--
-- שני נושאים, ושניהם על אותה שאלה — "מי אמור לשמוע על זה בכלל".
--
-- ===== 1. שיבוץ מדבר רק כשהמשימה פורסמה ===================================
--
-- 0063 קבע שמשימה בטיוטה או במתוכנן אינה מגיעה לעובד. התראה עליה סותרת את
-- זה ישירות: "השיבוץ שלך בוטל" על משימה שהעובד מעולם לא ראה היא הודעה על
-- דבר שלא היה, והקישור שבה מוביל למשימה שהפוליסה כבר לא מחזירה.
--
-- ולכן שלושת המקומות זזים יחד:
--
--   • שיבוץ נוסף  → מודיע רק אם המשימה כבר משובצת
--   • שיבוץ הוסר  → מודיע רק אם המשימה כבר משובצת   ← מה שהתבקש
--   • המשימה עברה למשובץ → *עכשיו* מודיע לכל מי שכבר שובץ אליה
--
-- השלישי אינו קישוט. בלעדיו הרצף הרגיל — פותחים טיוטה, משבצים אליה עובדים,
-- ואז מפרסמים — היה שקט מקצה לקצה: בזמן השיבוץ הסטטוס עוד לא היה "משובץ",
-- ובזמן הפרסום כבר לא נגעו בשיבוצים. אף אחד לא היה מקבל דבר.

create or replace function app.task_is_published(p_task_id uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from tasks t
      join statuses s on s.id = t.status_id
     where t.id = p_task_id and t.deleted_at is null and s.code = 'assigned')
$$;

-- זהה ל-0004, בתוספת השער.
create or replace function app.notify_assignment()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_task tasks; v_label text;
begin
  if not app.task_is_published(new.task_id) then return new; end if;

  select * into v_task from tasks where id = new.task_id;
  v_label := coalesce(v_task.title,
                      (select tt.name from task_types tt where tt.id = v_task.task_type_id),
                      'משימה');
  perform app.notify(new.profile_id, 'task_assigned', 'שובצת למשימה',
    v_label || ' בתאריך ' || to_char(v_task.task_date, 'DD/MM/YYYY'), 'task', new.task_id);
  return new;
end $$;

-- זהה ל-0047, בתוספת השער. בדיקת "המשימה עדיין קיימת" שכבר הייתה שם נבלעת
-- בתוך app.task_is_published, שדורשת deleted_at is null ממילא.
create or replace function app.notify_assignment_removed()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_task tasks; v_label text;
begin
  if not app.task_is_published(old.task_id) then return old; end if;

  select * into v_task from tasks where id = old.task_id and deleted_at is null;
  if not found then return old; end if;

  -- מי שהסיר את עצמו יודע שהסיר את עצמו
  if old.profile_id is not distinct from app.profile_id() then return old; end if;

  v_label := coalesce(v_task.title,
                      (select tt.name from task_types tt where tt.id = v_task.task_type_id),
                      'משימה');
  perform app.notify(old.profile_id, 'assignment_removed', 'השיבוץ שלך בוטל',
    v_label || ' בתאריך ' || to_char(v_task.task_date, 'DD/MM/YYYY'), 'task', old.task_id);
  return old;
end $$;

-- הפרסום עצמו. הסוג הוא 'task_assigned' ולא סוג חדש: מבחינת העובד זה בדיוק
-- אותו אירוע — "יש לך משמרת" — ומתג נפרד במסך ההעדפות על אותו דבר היה שני
-- מתגים לכיבוי אותה הודעה.
create or replace function app.notify_task_published()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_old   text;
  v_new   text;
  v_label text;
  r       record;
begin
  if new.deleted_at is not null then return new; end if;

  select s.code into v_old from statuses s where s.id = old.status_id;
  select s.code into v_new from statuses s where s.id = new.status_id;
  if v_new is distinct from 'assigned' or v_old is not distinct from 'assigned' then
    return new;
  end if;

  v_label := coalesce(nullif(new.title, ''),
                      (select tt.name from task_types tt where tt.id = new.task_type_id),
                      'משימה');

  for r in select distinct a.profile_id from task_assignments a where a.task_id = new.id loop
    -- מי שפרסם יודע שפרסם
    continue when r.profile_id is not distinct from app.profile_id();
    perform app.notify(r.profile_id, 'task_assigned', 'שובצת למשימה',
      v_label || ' בתאריך ' || to_char(new.task_date, 'DD/MM/YYYY'), 'task', new.id);
  end loop;
  return new;
end $$;

drop trigger if exists tasks_notify_published on tasks;
create trigger tasks_notify_published after update of status_id on tasks
  for each row execute function app.notify_task_published();

-- ===== 2. מה מוצע בהגדרות ההתראות האישיות =================================
--
-- שני סוגים ישבו במסך של כל עובד אף שאף אחד מהם לא נשלח לעובד:
--
--   • "לקוח פתח אירוע חדש" — app.notify_admins_event_created (0004) רץ על
--     `where is_admin`, ותו לא. הקהל 'staff' בקטלוג פשוט לא תאם את הפולט.
--   • "עובד דיווח משמרת שממתינה לאישור" — יוצא ל-app.profiles_with(
--     'attendance.approve_entry'), כלומר למי שמאשר. זה כן יכול להיות staff
--     שאינו אדמין, ולכן הורדת הקהל כאן הייתה חוסמת דווקא את המנהל שמקבל.
--
-- ומכאן שתי תשובות שונות: הראשון מצטמצם לקהל 'admin', והשני מקבל תנאי
-- הרשאה — אותו מפתח שהפולט כבר בוחר לפיו. עמודה, ולא רשימת קהלים נוספת:
-- "מי מקבל את זה" כבר נענה במקום אחד, וזו הצמדה אליו.

alter table notification_types add column if not exists required_permission text;

comment on column notification_types.required_permission is
  'מפתח הרשאה שבלעדיו הסוג אינו מוצע במסכי ההעדפות. null = מוצע לכל הקהל.';

update notification_types set audiences = array['admin'] where key = 'event_created';
update notification_types set required_permission = 'attendance.approve_entry'
 where key = 'attendance_submitted';

-- זהה ל-0046, בתוספת התנאי.
create or replace function my_notification_settings()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_me uuid := app.profile_id();
begin
  if v_me is null then return '[]'::jsonb; end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', t.key, 'label_he', t.label_he, 'description_he', t.description_he,
      'group_he', t.group_he,
      'channels', jsonb_build_object(
        'inapp', app.notification_cell(v_me, t.key, 'inapp'),
        'email', app.notification_cell(v_me, t.key, 'email'),
        'push',  app.notification_cell(v_me, t.key, 'push')))
      order by t.sort_order, t.key)
    from notification_types t
   where t.is_active
     and app.notification_audience(v_me) = any (t.audiences)
     and (t.required_permission is null or app.has(t.required_permission))
  ), '[]'::jsonb);
end $$;

-- ואותו תנאי במסך החריגים של המנהל, כדי ששני המסכים לא יחלקו על מה קיים.
-- כאן השאלה היא על אדם אחר, ולכן app.profiles_with ולא app.has.
create or replace function notification_user_settings(p_profile uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  perform app.require('notifications.manage');
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', t.key, 'label_he', t.label_he, 'group_he', t.group_he,
      'channels', jsonb_build_object(
        'inapp', app.notification_cell(p_profile, t.key, 'inapp'),
        'email', app.notification_cell(p_profile, t.key, 'email'),
        'push',  app.notification_cell(p_profile, t.key, 'push')))
      order by t.sort_order, t.key)
    from notification_types t
   where t.is_active
     and app.notification_audience(p_profile) = any (t.audiences)
     and (t.required_permission is null
          or p_profile in (select app.profiles_with(t.required_permission)))
  ), '[]'::jsonb);
end $$;

-- והכתיבה נסגרת מאותו צד. מסך שאינו מציג מתג אבל שרת שמקבל אותו בקריאת
-- REST הוא חצי שער, וזו בדיוק ההערה שכבר נכתבה ב-0046 על אכיפה בלקוח.
create or replace function set_notification_preference(
  p_type text, p_channel text, p_enabled boolean)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_me   uuid := app.profile_id();
  v_mode text;
begin
  if v_me is null then raise exception 'אין משתמש מחובר' using errcode = '42501'; end if;
  if p_channel not in ('inapp','email','push') then
    raise exception 'ערוץ לא מוכר: %', p_channel;
  end if;
  if not exists (
    select 1 from notification_types t
     where t.key = p_type and t.is_active
       and app.notification_audience(v_me) = any (t.audiences)
       and (t.required_permission is null or app.has(t.required_permission))) then
    raise exception 'סוג התראה לא מוכר: %', p_type;
  end if;

  v_mode := (app.notification_cell(v_me, p_type, p_channel) ->> 'mode');
  if v_mode in ('off','forced') then
    raise exception 'ההתראה הזו נקבעה על ידי מנהל המערכת ואי אפשר לשנות אותה'
      using errcode = '42501';
  end if;

  insert into notification_preferences (profile_id, channel, type, enabled, updated_at)
  values (v_me, p_channel, p_type, p_enabled, now())
  on conflict (profile_id, channel, type) do update
    set enabled = excluded.enabled, updated_at = now();
end $$;

-- העדפה שכבר נשמרה על סוג שאינו מוצע עוד היא שורה מתה שממשיכה להשפיע על
-- app.notification_enabled. ניקוי חד-פעמי, ורק למי שאינו עומד בתנאי.
delete from notification_preferences p
 where p.type = 'event_created'
   and exists (select 1 from profiles pr where pr.id = p.profile_id and not pr.is_admin);

delete from notification_preferences p
 where p.type = 'attendance_submitted'
   and p.profile_id not in (select app.profiles_with('attendance.approve_entry'));
