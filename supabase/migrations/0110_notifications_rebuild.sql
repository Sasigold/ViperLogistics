-- 0110: חוקי ההתראות נכתבים מחדש, והמנהל קובע על מי הם חלים
--
-- המנוע — הקטלוג, המטריצה, ההכרעה (0046/0086), המשפך app.notify (0054)
-- וצינור המשלוח — נשאר כמות שהוא. מה שמתחלף הוא כל שכבת *הפולטים*: אילו
-- אירועים עסקיים מדברים, אל מי, ובאילו מילים. הרשימה הישנה נבנתה בשכבות
-- (0004 ← 0047 ← 0064 ← 0105) וצברה שלושה סוגי עיוורון:
--
--   • ‏task_changed צפה ב-task_date וב-onsite_start_time בלבד. שינוי
--     warehouse_start_time — השעה שקובעת בפועל את תחילת המשמרת למי שמסומן
--     למחסן — עבר בשקט. הטריגר גם קרא את tasks.contractor_id, שמאז 0096 הוא
--     מראה של הקבלן הראשון בלבד, כך שקבלן שני לא שמע דבר.
--   • עובדי קבלן שמקושרים לאפליקציה לא קיבלו אף התראה: כל הפולטים דיברו אל
--     task_assignments (סגל) או אל משתמשי הקבלן, ואף אחד אל
--     task_contractor_workers.
--   • שורה של רגעים שהמשרד חי מהם — לקוח שערך אירוע, שביטל, שהעלה מפרט,
--     "אישור לביצוע" (0109), כניסה ויציאה בשעון — לא דיברו בכלל.
--
-- ומעבר לרשימה, יכולת אחת חדשה: **תחולה**. המנהל מגדיר, פר סוג התראה, על
-- אילו לקוחות / עובדים / קבלנים היא חלה. נושא שמחוץ לתחולה אינו יוצר שורה
-- בכלל — בשונה מ-muted (0046), שמתעד ומסנן: "לא רלוונטי" אינו "מושתק".
--
-- מה נשאר בלי שינוי: דיווח הנוכחות הידני (attendance_submitted /
-- attendance_approved / attendance_rejected, ‏0024) ותוקף מסמכי הרכב
-- (vehicle_document_expiring / expired, ‏0089).

-- ===== 1. הפולטים הישנים יורדים =============================================
-- טריגרים לפני פונקציות; חלק מהפונקציות מוחלפות בהמשך בשם זהה, אבל ההורדה
-- המפורשת כאן היא הרשימה המלאה של מה שנפרד ממנו.

drop trigger if exists task_assignments_notify         on task_assignments;
drop trigger if exists task_assignments_notify_removed on task_assignments;
drop trigger if exists tasks_notify_published          on tasks;
drop trigger if exists tasks_notify_time_change        on tasks;
drop trigger if exists tasks_notify_contractor         on tasks;               -- ירד כבר ב-0105; ליתר ביטחון
drop trigger if exists tct_notify_contractor           on task_contractor_terms;
drop trigger if exists events_notify_admins            on events;
drop trigger if exists events_notify_status            on events;

drop function if exists app.notify_assignment();
drop function if exists app.notify_assignment_removed();
drop function if exists app.notify_task_published();
drop function if exists app.notify_contractor_delegation();
drop function if exists app.notify_task_time_change();
drop function if exists app.notify_admins_event_created();
drop function if exists app.notify_event_status_change();

-- ===== 2. הקטלוג ============================================================
--
-- שלושה סוגים פורשים. deactivate ולא DELETE: ‏notifications.type הוא טקסט
-- חופשי ושורות היסטוריות ממשיכות להצביע על המפתחות האלה, ובדיקת 07 דורשת
-- שכל סוג שנפלט אי-פעם יהיה מוכר לקטלוג. שורת קטלוג כבויה עונה על שתיהן.
update notification_types set is_active = false
 where key in ('task_changed', 'event_status_changed', 'contractor_task');

-- שורות מדיניות של סוג שפרש הן החלטות על דבר שאינו קיים. החריגים האישיים
-- נשארים כהיסטוריה — הם ממילא אינם נקראים כשאין פולט.
delete from notification_policies
 where type in ('task_changed', 'event_status_changed', 'contractor_task');

-- הסוגים החדשים והמורחבים. register_notification_type (0046) עושה upsert
-- ואינו נוגע ב-is_active וב-required_permission של שורה קיימת.

-- משימות: מחזור הפרסום
select app.register_notification_type('task_published', 'המשימה שובצה',
  'המשימה עברה לסטטוס משובץ — לסגל, לקבלנים ולעובדי הקבלן שמשובצים אליה',
  'משימות', array['staff','contractor_user'], 'task', 'forced', 'opt_out', 'opt_in', 5);
select app.register_notification_type('task_unpublished', 'שיבוץ המשימה בוטל',
  'המשימה ירדה מסטטוס משובץ', 'משימות', array['staff','contractor_user'], 'task',
  'forced', 'opt_out', 'opt_in', 8);
select app.register_notification_type('task_assigned', 'שובצתי למשימה',
  'שיבוץ חדש שלי למשימה שכבר פורסמה', 'משימות', array['staff','contractor_user'], 'task',
  'forced', 'opt_out', 'opt_in', 10);
select app.register_notification_type('assignment_removed', 'הוסרתי משיבוץ למשימה',
  'שיבוץ שלי למשימה בוטל', 'משימות', array['staff','contractor_user'], 'task',
  'forced', 'opt_out', 'opt_in', 15);
select app.register_notification_type('task_time_changed', 'שינוי בזמני משימה ששובצתי אליה',
  'תאריך, שעת ההתחלה במחסן או שעת ההתחלה בשטח השתנו במשימה משובצת',
  'משימות', array['staff','contractor_user'], 'task', 'forced', 'opt_out', 'opt_in', 20);
select app.register_notification_type('contractor_worker_count_changed', 'כמות העובדים מהקבלן עודכנה',
  'המשרד שינה את מספר העובדים שהקבלן שלי אמור להביא למשימה משובצת',
  'משימות', array['contractor_user'], 'task', 'opt_out', 'opt_out', 'opt_in', 32);
select app.register_notification_type('contractor_worker_assigned', 'קבלן שיבץ עובד',
  'קבלן שיבץ עובד משלו למשימה', 'משימות', array['admin'], 'task',
  'opt_out', 'opt_out', 'opt_in', 34);

-- אירועים: מסלול הלקוח
select app.register_notification_type('event_created', 'לקוח פתח אירוע חדש',
  null, 'אירועים', array['admin'], 'event', 'opt_out', 'opt_out', 'opt_in', 40);
select app.register_notification_type('event_approved', 'האירוע שלי אושר לביצוע',
  'מנהל המערכת סימן את האירוע כמאושר לביצוע', 'אירועים', array['customer_user'], 'event',
  'forced', 'opt_out', 'opt_in', 42);
select app.register_notification_type('event_updated', 'לקוח עדכן אירוע',
  null, 'אירועים', array['admin'], 'event', 'opt_out', 'opt_out', 'opt_in', 44);
select app.register_notification_type('event_cancelled', 'לקוח ביטל אירוע',
  null, 'אירועים', array['admin'], 'event', 'forced', 'opt_out', 'opt_in', 46);
select app.register_notification_type('spec_uploaded', 'לקוח העלה מפרט חדש',
  null, 'אירועים', array['admin'], 'event', 'opt_out', 'opt_out', 'opt_in', 48);

-- נוכחות: השעון מדבר. מייל ב-opt_in (כבוי): כניסה ויציאה של כל עובד הן
-- הסוג הרועש ביותר במערכת, והפעמון + פוש הם הערוצים הנכונים לו.
select app.register_notification_type('attendance_clock_in', 'עובד ביצע כניסה',
  'החתמת כניסה בשעון — למנהלים על כולם, ולקבלן על העובדים שלו',
  'נוכחות', array['admin','contractor_user'], 'attendance_entry',
  'opt_out', 'opt_in', 'opt_in', 52);
select app.register_notification_type('attendance_clock_out', 'עובד ביצע יציאה',
  'החתמת יציאה בשעון — למנהלים על כולם, ולקבלן על העובדים שלו',
  'נוכחות', array['admin','contractor_user'], 'attendance_entry',
  'opt_out', 'opt_in', 'opt_in', 54);

-- ===== 3. תחולה =============================================================
--
-- שתי טבלאות דלילות, באותה פילוסופיה של notification_policies: שורה קיימת רק
-- כשמנהל שינה משהו. אין שורת מצב או mode='all' ⇒ הסוג חל על כולם;
-- mode='selected' ⇒ חל רק על הישויות שברשימה (וריקה ⇒ על אף אחד).
--
-- הבדיקה היא על *הנושא* של ההתראה: באירועים — הלקוח שהאירוע שלו; במשימות —
-- העובד הנמען (סגל) או הקבלן שמאחורי הנמען; בשעון — העובד או הקבלן שהחתים.
-- ‏pk עמודת id ולא המפתח הטבעי: כך app.audit() (0056) גוזר row_id בלי טיפול
-- מיוחד, כמו בכל טבלה אחרת.

create table notification_scope_modes (
  id          uuid primary key default gen_random_uuid(),
  type        text not null references notification_types(key) on delete cascade,
  entity_kind text not null check (entity_kind in ('customer','contractor','worker')),
  mode        text not null default 'all' check (mode in ('all','selected')),
  updated_at  timestamptz not null default now(),
  unique (type, entity_kind)
);

create table notification_scopes (
  id          uuid primary key default gen_random_uuid(),
  type        text not null references notification_types(key) on delete cascade,
  entity_kind text not null check (entity_kind in ('customer','contractor','worker')),
  entity_id   uuid not null,
  created_at  timestamptz not null default now(),
  unique (type, entity_kind, entity_id)
);

comment on table notification_scope_modes is
  'תחולת סוג התראה פר סוג-ישות (0110). אין שורה או all = חל על כולם.';
comment on table notification_scopes is
  'הישויות שנבחרו כשהתחולה selected (0110). customer=customers, contractor=contractors, worker=profiles.';

-- ‏entity_id אינו יכול להיות מפתח זר — הוא מצביע לשלוש טבלאות שונות — ולכן
-- הקיום נבדק בטריגר. בלעדיו הבורר במסך ההגדרות היה צובר שורות יתומות.
create or replace function app.notification_scope_check()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_missing boolean;
begin
  v_missing := case new.entity_kind
    when 'customer'   then not exists (select 1 from customers   where id = new.entity_id)
    when 'contractor' then not exists (select 1 from contractors where id = new.entity_id)
    when 'worker'     then not exists (select 1 from profiles    where id = new.entity_id)
  end;
  if v_missing then
    raise exception 'ישות % אינה קיימת עבור סוג התחולה %', new.entity_id, new.entity_kind;
  end if;
  return new;
end $$;

create trigger notification_scopes_check before insert or update on notification_scopes
  for each row execute function app.notification_scope_check();

alter table notification_scope_modes enable row level security;
alter table notification_scopes      enable row level security;
revoke all on notification_scope_modes, notification_scopes from anon;

create policy nsm_all on notification_scope_modes for all to authenticated
  using ((select app.is_admin()) or (select app.has('notifications.manage')))
  with check ((select app.is_admin()) or (select app.has('notifications.manage')));
create policy nsc_all on notification_scopes for all to authenticated
  using ((select app.is_admin()) or (select app.has('notifications.manage')))
  with check ((select app.is_admin()) or (select app.has('notifications.manage')));

create trigger notification_scope_modes_audit after insert or update or delete
  on notification_scope_modes for each row execute function app.audit();
create trigger notification_scopes_audit after insert or update or delete
  on notification_scopes for each row execute function app.audit();

-- ההכרעה. נקראת מהפולטים לפני app.notify: מחוץ לתחולה ⇒ אין שורה.
create or replace function app.notification_in_scope(p_type text, p_kind text, p_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select case
    when not exists (select 1 from notification_scope_modes m
                      where m.type = p_type and m.entity_kind = p_kind
                        and m.mode = 'selected')
      then true
    when p_id is null then false
    else exists (select 1 from notification_scopes s
                  where s.type = p_type and s.entity_kind = p_kind and s.entity_id = p_id)
  end
$$;

comment on function app.notification_in_scope(text, text, uuid) is
  'האם הנושא בתחולת הסוג (0110). ברירת המחדל — כן; selected מצמצם לרשימה.';

-- ===== 4. קהל של משימה ======================================================

-- "המנהלים של הקבלן": מי שמקושר לקבלן ומחזיק portal.view. זו בדיוק ההבחנה
-- שהמערכת כבר חיה איתה — כל contractor_user יורש את המפתח מברירת המחדל של
-- הסוג (0011), תפקיד contractor_worker דוחה אותו במפורש (0019), וכובע המנהל
-- גובר (0104). בלי הסינון הזה, "התראה לקבלן" הייתה מגיעה גם לכל עובד קבלן
-- מקושר — על משימות שהוא כלל אינו משובץ אליהן.
create or replace function app.contractor_managers(p_contractor uuid)
returns setof uuid language sql stable security definer set search_path = public as $$
  select p.id from profiles p
   where p.contractor_id = p_contractor
     and p.is_active and p.deleted_at is null
     and p.id in (select app.profiles_with('portal.view'))
$$;

comment on function app.contractor_managers(uuid) is
  'הפרופילים שמנהלים קבלן: מקושרים אליו ומחזיקים portal.view (0110).';

-- מקור אמת אחד לשאלה "אל מי משימה מדברת": הסגל המשובץ, מנהלי כל קבלן
-- שהמשימה הואצלה לו (כולל עובד עם כובע קבלן, 0075), ועובדי קבלן שמשובצים
-- אליה ומקושרים לאפליקציה. ‏group by הוא הדה-דופ: מי שחובש שני כובעים מקבל
-- התראה אחת. ‏any_warehouse — יש לאדם כובע כלשהו שמסומן למחסן — הוא מה
-- שמאפשר לסנן שינוי שנוגע רק לשעת המחסן.
create or replace function app.task_audience(p_task_id uuid, p_type text)
returns table (profile_id uuid, any_warehouse boolean)
language sql stable security definer set search_path = public as $$
  select x.profile_id, bool_or(x.work_site = 'warehouse')
  from (
    select a.profile_id, a.work_site,
           app.notification_in_scope(p_type, 'worker', a.profile_id) as in_scope
      from task_assignments a
      join profiles p on p.id = a.profile_id and p.is_active and p.deleted_at is null
     where a.task_id = p_task_id
    union all
    select m.id, coalesce(tct.work_site, 'field'),
           app.notification_in_scope(p_type, 'contractor', tct.contractor_id)
      from task_contractor_terms tct
      cross join lateral app.contractor_managers(tct.contractor_id) as m(id)
     where tct.task_id = p_task_id
    union all
    select p.id, coalesce(tcw.work_site, 'field'),
           app.notification_in_scope(p_type, 'contractor', cw.contractor_id)
      from task_contractor_workers tcw
      join contractor_workers cw on cw.id = tcw.contractor_worker_id
      join profiles p on p.contractor_worker_id = cw.id
                     and p.is_active and p.deleted_at is null
     where tcw.task_id = p_task_id
  ) x
  where x.in_scope
  group by x.profile_id
$$;

comment on function app.task_audience(uuid, text) is
  'כל מי שמשימה מדברת אליו, אחרי סינון תחולה ודה-דופ (0110). שורה לאדם.';

-- תווית משימה, בנוסח שכל הפולטים הקודמים חלקו.
create or replace function app.task_notify_label(p_task tasks)
returns text language sql stable security definer set search_path = public as $$
  select coalesce(nullif(p_task.title, ''),
                  (select tt.name from task_types tt where tt.id = p_task.task_type_id),
                  'משימה')
$$;

-- ===== 5. אירועים: מסלול הלקוח =============================================
--
-- כל פולטי האירועים מגודרים על "השחקן הוא לקוח": אירוע שנפתח או נערך על ידי
-- המשרד אינו חדשות למשרד. הזיהוי — created_by ביצירה (כמו 0004), ו-
-- app.user_kind() בעריכה: היצירה יכולה להגיע גם מכתיבת שירות בשם לקוח,
-- והעריכה תמיד נעשית בסשן של העורך.

create or replace function app.notify_event_created()
returns trigger language plpgsql security definer set search_path = public as $$
declare r record; v_creator profiles;
begin
  select * into v_creator from profiles where id = new.created_by;
  if v_creator.user_kind is distinct from 'customer_user' then return new; end if;
  if not app.notification_in_scope('event_created', 'customer', new.customer_id) then
    return new;
  end if;
  for r in select id from profiles
    where is_admin and is_active and deleted_at is null
      and id is distinct from app.profile_id()
  loop
    perform app.notify(r.id, 'event_created', 'אירוע חדש נוצר על ידי לקוח',
      (select name from customers where id = new.customer_id) ||
      ' — ' || to_char(new.event_date, 'DD/MM/YYYY'), 'event', new.id);
  end loop;
  return new;
end $$;

create trigger events_notify_admins after insert on events
  for each row execute function app.notify_event_created();

create or replace function app.notify_event_updated()
returns trigger language plpgsql security definer set search_path = public as $$
declare r record; v_label text; v_code text;
begin
  if app.user_kind() is distinct from 'customer_user' then return new; end if;
  -- מחיקה רכה אינה עריכה
  if new.deleted_at is not null or old.deleted_at is not null then return new; end if;
  -- מעבר ל"בוטל" מדווח על ידי notify_event_cancelled — לא פעמיים
  if old.status_id is distinct from new.status_id then
    select s.code into v_code from statuses s where s.id = new.status_id;
    if v_code = 'cancelled' then return new; end if;
  end if;
  -- עדכון שלא שינה דבר (או רק עמודות נגזרות) שותק
  if to_jsonb(old) - 'search_tsv' - 'updated_at' =
     to_jsonb(new) - 'search_tsv' - 'updated_at' then return new; end if;
  if not app.notification_in_scope('event_updated', 'customer', new.customer_id) then
    return new;
  end if;

  v_label := coalesce(new.end_client_name, new.event_number,
                      to_char(new.event_date, 'DD/MM/YYYY'));
  for r in select id from profiles
    where is_admin and is_active and deleted_at is null
      and id is distinct from app.profile_id()
  loop
    perform app.notify(r.id, 'event_updated', 'לקוח עדכן אירוע',
      (select name from customers where id = new.customer_id) || ' — ' || v_label,
      'event', new.id);
  end loop;
  return new;
end $$;

create trigger events_notify_updated after update on events
  for each row execute function app.notify_event_updated();

create or replace function app.notify_event_cancelled()
returns trigger language plpgsql security definer set search_path = public as $$
declare r record; v_label text; v_old text; v_new text;
begin
  if app.user_kind() is distinct from 'customer_user' then return new; end if;
  if new.deleted_at is not null then return new; end if;
  select s.code into v_old from statuses s where s.id = old.status_id;
  select s.code into v_new from statuses s where s.id = new.status_id;
  if v_new is distinct from 'cancelled' or v_old is not distinct from 'cancelled' then
    return new;
  end if;
  if not app.notification_in_scope('event_cancelled', 'customer', new.customer_id) then
    return new;
  end if;

  v_label := coalesce(new.end_client_name, new.event_number,
                      to_char(new.event_date, 'DD/MM/YYYY'));
  for r in select id from profiles
    where is_admin and is_active and deleted_at is null
      and id is distinct from app.profile_id()
  loop
    perform app.notify(r.id, 'event_cancelled', 'לקוח ביטל אירוע',
      (select name from customers where id = new.customer_id) || ' — ' || v_label,
      'event', new.id);
  end loop;
  return new;
end $$;

create trigger events_notify_cancelled after update of status_id on events
  for each row execute function app.notify_event_cancelled();

-- מפרט חדש. ‏uploaded_by כבר נחתם בשרת (0077), ולכן הוא עדות אמינה למי העלה.
create or replace function app.notify_spec_uploaded()
returns trigger language plpgsql security definer set search_path = public as $$
declare r record; v_event events; v_kind text; v_label text;
begin
  select user_kind::text into v_kind from profiles where id = new.uploaded_by;
  if v_kind is distinct from 'customer_user' then return new; end if;
  select * into v_event from events where id = new.event_id and deleted_at is null;
  if v_event.id is null then return new; end if;
  if not app.notification_in_scope('spec_uploaded', 'customer', v_event.customer_id) then
    return new;
  end if;

  v_label := coalesce(v_event.end_client_name, v_event.event_number,
                      to_char(v_event.event_date, 'DD/MM/YYYY'));
  for r in select id from profiles
    where is_admin and is_active and deleted_at is null
      and id is distinct from app.profile_id()
  loop
    perform app.notify(r.id, 'spec_uploaded', 'לקוח העלה מפרט חדש',
      (select name from customers where id = v_event.customer_id) || ' — ' || v_label ||
      ' (גרסה ' || new.version || ')', 'event', v_event.id);
  end loop;
  return new;
end $$;

create trigger event_specs_notify_uploaded after insert on event_specs
  for each row execute function app.notify_spec_uploaded();

-- "אישור לביצוע". הגוף מ-0109 במלואו — הקונבנציה מ-0030/0046: הגדרה מחדש,
-- לא עטיפה — בתוספת ההתראה ללקוח. רק המעבר לא-מאושר → מאושר מדבר: אישור
-- חוזר על אירוע שכבר אושר אינו חדשות, וביטול אישור נשאר עניין פנימי של המשרד.
create or replace function set_event_approved(p_event_id uuid, p_on boolean default true)
returns timestamptz language plpgsql security definer set search_path = public as $$
declare
  v_at    timestamptz;
  v_event events;
  v_label text;
  r       record;
begin
  if not app.is_admin() then
    raise exception 'אישור אירוע לביצוע שמור למנהל המערכת' using errcode = '42501';
  end if;
  select * into v_event from events where id = p_event_id and deleted_at is null;
  if v_event.id is null then
    raise exception 'האירוע לא נמצא' using errcode = '42501';
  end if;

  v_at := case when p_on then now() end;
  perform app.system_write(true);
  update events
     set approved_at = v_at,
         approved_by = case when p_on then app.profile_id() end
   where id = p_event_id;
  perform app.system_write(false);

  if p_on and v_event.approved_at is null
     and app.notification_in_scope('event_approved', 'customer', v_event.customer_id) then
    v_label := coalesce(v_event.end_client_name, v_event.event_number,
                        to_char(v_event.event_date, 'DD/MM/YYYY'));
    for r in select p.id from profiles p
      where p.customer_id = v_event.customer_id
        and p.user_kind = 'customer_user'
        and p.is_active and p.deleted_at is null
        and p.id is distinct from app.profile_id()
    loop
      perform app.notify(r.id, 'event_approved', 'האירוע אושר לביצוע',
        v_label || ' — ' || to_char(v_event.event_date, 'DD/MM/YYYY'), 'event', v_event.id);
    end loop;
  end if;

  return v_at;
end $$;

revoke execute on function public.set_event_approved(uuid, boolean) from anon, public;

-- ===== 6. משימות: מחזור הפרסום ==============================================

-- הפרסום וירידתו — לכל הקהל, בשני הכיוונים.
create or replace function app.notify_task_publication()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_old   text;
  v_new   text;
  v_type  text;
  v_title text;
  v_label text;
  r       record;
begin
  if new.deleted_at is not null then return new; end if;
  select s.code into v_old from statuses s where s.id = old.status_id;
  select s.code into v_new from statuses s where s.id = new.status_id;
  if v_new = 'assigned' and v_old is distinct from 'assigned' then
    v_type := 'task_published'; v_title := 'המשימה שובצה';
  elsif v_old = 'assigned' and v_new is distinct from 'assigned' then
    v_type := 'task_unpublished'; v_title := 'שיבוץ המשימה בוטל';
  else
    return new;
  end if;

  v_label := app.task_notify_label(new);
  for r in select ta.profile_id from app.task_audience(new.id, v_type) ta loop
    continue when r.profile_id is not distinct from app.profile_id();
    perform app.notify(r.profile_id, v_type, v_title,
      v_label || ' בתאריך ' || to_char(new.task_date, 'DD/MM/YYYY'), 'task', new.id);
  end loop;
  return new;
end $$;

create trigger tasks_notify_published after update of status_id on tasks
  for each row execute function app.notify_task_publication();

-- שיבוץ סגל אחרי שהמשימה כבר פורסמה. השער מ-0064 נשאר; נוספו תחולה ודילוג
-- על מי ששיבץ את עצמו.
create or replace function app.notify_assignment()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_task tasks;
begin
  if not app.task_is_published(new.task_id) then return new; end if;
  if new.profile_id is not distinct from app.profile_id() then return new; end if;
  if not app.notification_in_scope('task_assigned', 'worker', new.profile_id) then
    return new;
  end if;

  select * into v_task from tasks where id = new.task_id;
  perform app.notify(new.profile_id, 'task_assigned', 'שובצת למשימה',
    app.task_notify_label(v_task) || ' בתאריך ' || to_char(v_task.task_date, 'DD/MM/YYYY'),
    'task', new.task_id);
  return new;
end $$;

create trigger task_assignments_notify after insert on task_assignments
  for each row execute function app.notify_assignment();

create or replace function app.notify_assignment_removed()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_task tasks;
begin
  if not app.task_is_published(old.task_id) then return old; end if;
  select * into v_task from tasks where id = old.task_id and deleted_at is null;
  if not found then return old; end if;
  -- מי שהסיר את עצמו יודע שהסיר את עצמו
  if old.profile_id is not distinct from app.profile_id() then return old; end if;
  if not app.notification_in_scope('assignment_removed', 'worker', old.profile_id) then
    return old;
  end if;

  perform app.notify(old.profile_id, 'assignment_removed', 'השיבוץ שלך בוטל',
    app.task_notify_label(v_task) || ' בתאריך ' || to_char(v_task.task_date, 'DD/MM/YYYY'),
    'task', old.task_id);
  return old;
end $$;

create trigger task_assignments_notify_removed after delete on task_assignments
  for each row execute function app.notify_assignment_removed();

-- האצלה לקבלן. הגוף מ-0105, בתוספת שער הפרסום (עד עכשיו קבלן שמע גם על
-- טיוטות — בניגוד לכלל מ-0063 שעובד אינו שומע עליהן), התחולה, והסרת סינון
-- user_kind כדי שגם עובד עם כובע קבלן (0075) ישמע. הסוג הוא task_published:
-- מבחינת הקבלן זה בדיוק אותו רגע — "יש לך משימה" — ומתג נפרד היה שני מתגים
-- לכיבוי אותו דבר (הנימוק מ-0064 §"הפרסום עצמו").
create or replace function app.notify_contractor_delegation()
returns trigger language plpgsql security definer set search_path = public as $$
declare r record; v_task tasks;
begin
  if not app.task_is_published(new.task_id) then return new; end if;
  select * into v_task from tasks where id = new.task_id;
  if not app.notification_in_scope('task_published', 'contractor', new.contractor_id) then
    return new;
  end if;

  for r in select m.id from app.contractor_managers(new.contractor_id) as m(id)
    where m.id is distinct from app.profile_id()
  loop
    perform app.notify(r.id, 'task_published', 'משימה חדשה הוקצתה לך',
      app.task_notify_label(v_task) || ' בתאריך ' || to_char(v_task.task_date, 'DD/MM/YYYY'),
      'task', v_task.id);
  end loop;
  return new;
end $$;

create trigger tct_notify_contractor after insert on task_contractor_terms
  for each row execute function app.notify_contractor_delegation();

-- והצד הסימטרי: ביטול ההאצלה. הלקח מ-0047 — מחיקת משימה מפילה את השורות
-- בקסקייד, ומשימה שאיננה אינה מדברת.
create or replace function app.notify_contractor_undelegation()
returns trigger language plpgsql security definer set search_path = public as $$
declare r record; v_task tasks;
begin
  if not app.task_is_published(old.task_id) then return old; end if;
  select * into v_task from tasks where id = old.task_id and deleted_at is null;
  if not found then return old; end if;
  if not app.notification_in_scope('task_unpublished', 'contractor', old.contractor_id) then
    return old;
  end if;

  for r in select m.id from app.contractor_managers(old.contractor_id) as m(id)
    where m.id is distinct from app.profile_id()
  loop
    perform app.notify(r.id, 'task_unpublished', 'המשימה הוסרה מהקבלן שלך',
      app.task_notify_label(v_task) || ' בתאריך ' || to_char(v_task.task_date, 'DD/MM/YYYY'),
      'task', old.task_id);
  end loop;
  return old;
end $$;

create trigger tct_notify_undelegation after delete on task_contractor_terms
  for each row execute function app.notify_contractor_undelegation();

-- עובד קבלן שנוסף למשימה מפורסמת. שני קהלים בטריגר אחד, כי שניהם עדים לאותה
-- שורה: העובד עצמו (אם הוא מקושר לאפליקציה), והמנהלים — כשהמשבץ הוא צד
-- הקבלן ולא המשרד. הטריגר ולא contractor_assign_worker: הוא תופס כל מסלול
-- שכותב לטבלה, כולל שיבוץ של המשרד דרך המסכים שכותבים אליה ישירות.
create or replace function app.notify_contractor_worker_added()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_task    tasks;
  v_cw      contractor_workers;
  v_profile uuid;
  v_label   text;
  r         record;
begin
  if not app.task_is_published(new.task_id) then return new; end if;
  select * into v_task from tasks where id = new.task_id;
  select * into v_cw from contractor_workers where id = new.contractor_worker_id;
  v_label := app.task_notify_label(v_task) || ' בתאריך ' || to_char(v_task.task_date, 'DD/MM/YYYY');

  if app.notification_in_scope('task_assigned', 'contractor', v_cw.contractor_id) then
    select id into v_profile from profiles
     where contractor_worker_id = v_cw.id and is_active and deleted_at is null;
    if v_profile is not null and v_profile is distinct from app.profile_id() then
      perform app.notify(v_profile, 'task_assigned', 'שובצת למשימה', v_label, 'task', new.task_id);
    end if;
  end if;

  -- המשבץ הוא צד הקבלן (כולל עובד עם כובע קבלן) — המנהלים שומעים על זה
  if not app.is_admin() and app.contractor_id() = v_cw.contractor_id
     and app.notification_in_scope('contractor_worker_assigned', 'contractor', v_cw.contractor_id) then
    for r in select id from profiles where is_admin and is_active and deleted_at is null loop
      perform app.notify(r.id, 'contractor_worker_assigned',
        coalesce((select name from contractors where id = v_cw.contractor_id), 'קבלן') || ' שיבץ עובד למשימה',
        v_cw.full_name || ' — ' || v_label, 'task', new.task_id);
    end loop;
  end if;
  return new;
end $$;

create trigger tcw_notify_added after insert on task_contractor_workers
  for each row execute function app.notify_contractor_worker_added();

create or replace function app.notify_contractor_worker_removed()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_task tasks; v_cw contractor_workers; v_profile uuid;
begin
  if not app.task_is_published(old.task_id) then return old; end if;
  select * into v_task from tasks where id = old.task_id and deleted_at is null;
  if not found then return old; end if;
  select * into v_cw from contractor_workers where id = old.contractor_worker_id;
  if v_cw.id is null then return old; end if;
  if not app.notification_in_scope('assignment_removed', 'contractor', v_cw.contractor_id) then
    return old;
  end if;

  select id into v_profile from profiles
   where contractor_worker_id = v_cw.id and is_active and deleted_at is null;
  if v_profile is not null and v_profile is distinct from app.profile_id() then
    perform app.notify(v_profile, 'assignment_removed', 'השיבוץ שלך בוטל',
      app.task_notify_label(v_task) || ' בתאריך ' || to_char(v_task.task_date, 'DD/MM/YYYY'),
      'task', old.task_id);
  end if;
  return old;
end $$;

create trigger tcw_notify_removed after delete on task_contractor_workers
  for each row execute function app.notify_contractor_worker_removed();

-- שינוי זמנים במשימה משובצת. שלוש העמודות — כולל warehouse_start_time,
-- העיוורון שהמיגרציה הזו באה לתקן. כשרק שעת המחסן זזה, שומעים רק מי שמסומנים
-- למחסן: לשאר לא השתנה דבר. שינוי סטטוס באותו UPDATE שותק כאן —
-- notify_task_publication כבר דיבר, וההודעה שלו נושאת את הזמנים החדשים.
create or replace function app.notify_task_time_change()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  r         record;
  v_code    text;
  v_wh_only boolean;
  v_body    text;
begin
  if new.deleted_at is not null then return new; end if;
  if old.status_id is distinct from new.status_id then return new; end if;
  select s.code into v_code from statuses s where s.id = new.status_id;
  if v_code is distinct from 'assigned' then return new; end if;
  if old.task_date is not distinct from new.task_date
     and old.onsite_start_time is not distinct from new.onsite_start_time
     and old.warehouse_start_time is not distinct from new.warehouse_start_time then
    return new;
  end if;

  v_wh_only := old.warehouse_start_time is distinct from new.warehouse_start_time
           and old.task_date is not distinct from new.task_date
           and old.onsite_start_time is not distinct from new.onsite_start_time;

  v_body := app.task_notify_label(new)
         || ' עודכנה ל-' || to_char(new.task_date, 'DD/MM/YYYY')
         || coalesce(' | מחסן ' || to_char(new.warehouse_start_time, 'HH24:MI'), '')
         || coalesce(' | שטח ' || to_char(new.onsite_start_time, 'HH24:MI'), '');

  for r in select ta.profile_id, ta.any_warehouse
             from app.task_audience(new.id, 'task_time_changed') ta loop
    continue when r.profile_id is not distinct from app.profile_id();
    continue when v_wh_only and not r.any_warehouse;
    perform app.notify(r.profile_id, 'task_time_changed', 'שינוי בזמני משימה',
      v_body, 'task', new.id);
  end loop;
  return new;
end $$;

create trigger tasks_notify_time_change
  after update of task_date, onsite_start_time, warehouse_start_time on tasks
  for each row execute function app.notify_task_time_change();

-- המשרד שינה כמה עובדים הקבלן אמור להביא — למשתמשי אותו קבלן בלבד.
create or replace function app.notify_worker_count_change()
returns trigger language plpgsql security definer set search_path = public as $$
declare r record; v_task tasks;
begin
  if old.contractor_worker_count is not distinct from new.contractor_worker_count then
    return new;
  end if;
  if not app.task_is_published(new.task_id) then return new; end if;
  if not app.notification_in_scope('contractor_worker_count_changed', 'contractor', new.contractor_id) then
    return new;
  end if;
  select * into v_task from tasks where id = new.task_id;

  for r in select m.id from app.contractor_managers(new.contractor_id) as m(id)
    where m.id is distinct from app.profile_id()
  loop
    perform app.notify(r.id, 'contractor_worker_count_changed', 'עודכנה כמות העובדים למשימה',
      app.task_notify_label(v_task) || ' בתאריך ' || to_char(v_task.task_date, 'DD/MM/YYYY')
      || ' — ' || coalesce(new.contractor_worker_count::text, 'ללא הגבלה') || ' עובדים',
      'task', new.task_id);
  end loop;
  return new;
end $$;

create trigger tct_notify_worker_count after update of contractor_worker_count on task_contractor_terms
  for each row execute function app.notify_worker_count_change();

-- ===== 7. השעון מדבר ========================================================
--
-- הנמענים: כל המנהלים — על כולם, כולל עובדי קבלן; ומשתמשי הקבלן — על העובדים
-- שלהם (בלי מנהלים, שכבר קיבלו בלולאה הראשונה, ובלי המחתים עצמו). התחולה
-- נבחנת על *המחתים*: עובד סגל לפי worker, עובד קבלן לפי הקבלן שלו.
create or replace function app.notify_clock_event(
  p_actor uuid, p_type text, p_entry_id uuid, p_late boolean)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_name  text;
  v_cw    uuid;
  v_ctr   uuid;
  v_title text;
  v_body  text;
  r       record;
begin
  select p.full_name, p.contractor_worker_id, cw.contractor_id
    into v_name, v_cw, v_ctr
    from profiles p
    left join contractor_workers cw on cw.id = p.contractor_worker_id
   where p.id = p_actor;

  if v_cw is null then
    if not app.notification_in_scope(p_type, 'worker', p_actor) then return; end if;
  else
    if not app.notification_in_scope(p_type, 'contractor', v_ctr) then return; end if;
  end if;

  v_title := coalesce(v_name, 'עובד') ||
             case when p_type = 'attendance_clock_in'
                  then case when p_late then ' ביצע כניסה באיחור' else ' ביצע כניסה' end
                  else ' ביצע יציאה' end;
  v_body := 'בשעה ' || to_char(now() at time zone 'Asia/Jerusalem', 'HH24:MI') ||
            ' — ' || to_char(now() at time zone 'Asia/Jerusalem', 'DD/MM/YYYY');

  for r in select id from profiles
    where is_admin and is_active and deleted_at is null
      and id is distinct from p_actor
  loop
    perform app.notify(r.id, p_type, v_title, v_body, 'attendance_entry', p_entry_id);
  end loop;

  if v_ctr is not null then
    -- מנהלי הקבלן בלבד — עובד קבלן אינו שומע על הכניסות של עמיתיו; ומי
    -- שהוא גם אדמין כבר קיבל בלולאה הראשונה.
    for r in select m.id from app.contractor_managers(v_ctr) as m(id)
      join profiles p on p.id = m.id
      where not p.is_admin and m.id is distinct from p_actor
    loop
      perform app.notify(r.id, p_type, v_title, v_body, 'attendance_entry', p_entry_id);
    end loop;
  end if;
end $$;

comment on function app.notify_clock_event(uuid, text, uuid, boolean) is
  'התראת כניסה/יציאה בשעון (0110): מנהלים על כולם, קבלן על עובדיו.';

-- ‏attendance_clock_in — הגוף מ-0073 במלואו, בתוספת חישוב האיחור וההתראה.
-- איחור: עובד סגל — כל דקה אחרי shift_start הקפוא על השורה (הנימוק מ-0084:
-- בלי נקודת ייחוס מתוכננת "איחור" אינו מוגדר, ולכן מי שאין לו משמרת אינו
-- מאחר); עובד קבלן — אחרי דקות החסד של הקבלן שלו (0092), אותו סף שמזין את
-- קנסות האיחור.
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
  if not coalesce((v_rules ->> 'clock_enabled')::boolean, true) then
    raise exception 'שעון הנוכחות מושבת עבורך';
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

  v_grace := make_interval(mins => coalesce((v_rules ->> 'early_grace_minutes')::int, 15));
  v_shift := app.shift_at(v_me, now(), v_grace);

  if v_shift.shift_start is null then
    if not coalesce((v_rules ->> 'allow_clock_without_shift')::boolean, false) then
      raise exception 'אין לך משמרת משובצת כרגע. אם עבדת בלי שיבוץ, אפשר לדווח משמרת לאישור מנהל';
    end if;
    v_flags := v_flags || 'no_shift'::text;
  elsif now() < v_shift.shift_start - v_grace
        and not coalesce((v_rules ->> 'allow_early_clock_in')::boolean, false) then
    -- התחלה מוקדמת: חסימה, אלא אם הותרה במפורש לעובד הזה.
    raise exception 'לא ניתן להתחיל משמרת לפני השעה %',
      to_char(v_shift.shift_start at time zone 'Asia/Jerusalem', 'HH24:MI');
  end if;

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

-- ‏attendance_clock_out — הגוף מ-0082 במלואו (לא 0073: ‏0082 הוסיפה את מדידת
-- היציאה מול המחסן), בתוספת ההתראה.
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
  v_d_wh   numeric;
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
  v_site_lat := v_shift.end_lat;
  v_site_lng := v_shift.end_lng;

  -- מי שיצא מהמחסן מסיים באחת משתי נקודות: בשטח, או במחסן שאליו חזר.
  -- נבחרת הקרובה מביניהן, ובלי לוותר על כלום — מי שרחוק משתיהן עדיין נחסם.
  if v_shift.work_site = 'warehouse'
     and v_shift.start_lat is not null and v_shift.start_lng is not null
     and p_lat is not null and p_lng is not null then
    v_d_wh := app.haversine_km(p_lat, p_lng, v_shift.start_lat, v_shift.start_lng);
    v_d_site := case when v_site_lat is null or v_site_lng is null then null
                     else app.haversine_km(p_lat, p_lng, v_site_lat, v_site_lng) end;
    if v_d_site is null or v_d_wh < v_d_site then
      v_site_lat := v_shift.start_lat;
      v_site_lng := v_shift.start_lng;
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

-- ===== 8. הקישור בפעמון =====================================================
-- הגוף מ-0089 עם זרוע הנוכחות מורחבת: כניסה ויציאה הולכות לדוח הנוכחות —
-- המסך של מי שמקבל אותן (מנהל ומנהל קבלן כאחד), לא של מי שהחתים. אישור
-- ודחייה ממשיכים למסך השעון של העובד עצמו. לא נעטף — מאותו נימוק שכתוב
-- בכל גלגול קודם.
create or replace function app.notification_link(
  p_recipient uuid, p_type text, p_entity_type text, p_entity_id uuid)
returns text language plpgsql stable security definer set search_path = public as $$
declare v_date date;
begin
  if p_entity_id is null then return '/'; end if;

  if p_entity_type = 'event' then
    return '/events/' || p_entity_id;
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

  return '/';
end $$;
