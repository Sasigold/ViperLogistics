-- 0080: מה שהצוות רואה — ומה שראש הצוות רואה מעבר לזה
--
-- שישה דיווחים, כולם על אותו קהל: `user_kind = 'staff'` בתפקיד שטח — עובד,
-- נהג, ראש צוות. חמישה מהם הם גבולות ראייה, ואחד הוא באג בשעון.
--
-- שניים מהם נולדו ב-0079 עצמה, ולכן הם קודם כול תיקון שלה:
--
--   * ‏`app.event_visible` (0005) היא security definer ששואלת רק
--     `has('events.view')` — בלי היקפי השורות. כל עוד למפתח הזה לא היה עובד
--     שטח, ההשמטה לא הזיקה; מרגע ש-0079 הדליק לו אותו, הפונקציה מחזירה
--     `true` על **כל** אירוע במערכת, וכל פוליסה שנשענת עליה (ספקים, אנשי
--     קשר) נפתחה איתה.
--   * ודף `/events` נפתח לו יחד עם דף האירוע, כי לשניהם היה מפתח אחד.
--
-- והשאר:
--
--   * בלוח השנה הצוות ראה אירוע גם כשהמשימה שלו בו עדיין טיוטה.
--     ‏`tasks_select` כבר סוגרת את זה בלוח העבודה מאז 0063; `events_select`
--     מעולם לא שאלה על סטטוס.
--   * ראש צוות באירוע צריך את מה שהעובד אינו צריך: את יומן האירוע, את
--     היכולת לתעד בו, ואת שם הטלפון של איש הקשר. זה אינו מפתח — זה תפקיד
--     **באירוע הזה**, ולכן הוא נבדק על השורה ולא במרשם.
--   * ומי שיוצא מהמחסן וחוזר אליו נחסם ביציאה, כי היא נמדדה מול מיקום
--     האירוע בלבד.

-- ===== 1. ‏event_visible חוזרת להיות מה ש-events_select אומרת =============
--
-- הפונקציה נכתבה ב-0005 כ-security definer עם ההערה "replicates event
-- visibility without RLS recursion", והשכפול הזה הוא הבאג: היא העתיקה את
-- שכבת המפתח ולא את שכבת ההיקפים, ולכן היא נעשית שגויה בכל פעם שההיקפים
-- מבחינים בין שני קוראים שמחזיקים את אותו מפתח.
--
-- החשש מרקורסיה אינו חל: היא נקראת מפוליסות על `event_contacts` ועל
-- `event_suppliers` בלבד, ו-`events_select` אינה מפנה לאף אחת מהשתיים.
-- כשהיא עוברת ל-invoker היא מפסיקה לשכפל את הפוליסה ומתחילה *לשאול* אותה,
-- ולכן היא לא יכולה עוד לסטות ממנה — לא היום ולא בשינוי הבא.
create or replace function app.event_visible(p_event_id uuid)
returns boolean language sql stable set search_path = public as $$
  select exists (select 1 from events e where e.id = p_event_id)
$$;

comment on function app.event_visible(uuid) is
  'האם הקורא רואה את האירוע. invoker במכוון (0080): התשובה היא בדיוק '
  'events_select, כולל היקפי השורות, ולא העתק שלה שמתיישן.';

-- ===== 2. רשימת האירועים היא מפתח נפרד מדף האירוע =========================
--
-- ‏`events.view` שולט בשלושה דברים בבת אחת: זרוע ה-staff ב-`events_select`,
-- הנתיב `/events/:id` והנתיב `/events`. ‏0079 הדליק אותו לעובד כדי לפתוח את
-- הראשון והשני, וקיבל את השלישי בלי לבקש — קטלוג של כל האירועים שהוא רשאי
-- לראות, מסך שאין לו בו מה לעשות.
--
-- המפתח החדש נגזר מ-`events.view`, ולכן כל מי שמחזיק אותו היום ממשיך לראות
-- את הרשימה בלי שורת הענקה; מה שהוא מוסיף הוא היכולת לכבות אותה בנפרד.
select app.register_permission('events.list', 'events',
  'מסך רשימת האירועים',
  'הקטלוג ב-/events. דף האירוע עצמו נשלט ב-events.view',
  'access', false, false,
  array['staff', 'customer_user', 'contractor_user']::user_kind[],
  'events.view', 15);

-- שלושת תפקידי השטח. נהג וראש צוות ממילא חסומים היום דרך `events.view`,
-- והשורה כאן היא מה שמחזיק אותם חסומים אם וכאשר הוא ייפתח להם גם.
insert into role_permissions (role_id, permission_key, allowed)
select r.id, 'events.list', false
from permission_roles r
where r.key in ('worker', 'driver', 'team_lead')
on conflict (role_id, permission_key) do update set allowed = false;

-- ===== 3. משימה שטרם פורסמה אינה מזמינה גם את האירוע שלה ==================
--
-- ‏0063 קבעה את הכלל בצד המשימות: מי שכל זיקתו למשימה היא שהוא משובץ אליה
-- רואה רק את מה שפורסם ("משובץ"). ‏`events_select` נשענת על אותה זיקה בדיוק
-- — "יש באירוע משימה שאני רשום עליה" — ומעולם לא שאלה על הסטטוס, ולכן
-- טיוטה שהרכז עוד עובד עליה הופיעה בלוח השנה של העובד.
--
-- הפונקציה מרכזת את השאלה במקום אחד, כמו `app.on_event_as_contractor_worker`
-- (0066) שכבר עושה בדיוק את זה בזרוע הקבלן — כולל תנאי הסטטוס, שהיה שם
-- מלכתחילה. security definer מאותו נימוק: היא נקראת מתוך פוליסה על `events`
-- ושואלת את `tasks`, ובלעדיו הייתה נכנסת ל-`tasks_select` בתוך ההערכה של
-- `events_select`.
create or replace function app.on_event_as_staff(p_event_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from tasks t
    join task_assignments a on a.task_id = t.id
    where t.event_id = p_event_id and t.deleted_at is null
      and a.profile_id = app.profile_id()
      -- מי שרשאי לתכנן רואה גם טיוטות: הוא זה שכותב אותן (0063 §4)
      and (app.can_plan_tasks()
           or t.status_id = (select s.id from statuses s
                              where s.entity = 'task' and s.code = 'assigned'
                                and s.deleted_at is null limit 1)))
$$;

-- זהה ל-0067 פרט לשני המקומות שבהם תת-השאילתה על השיבוץ הוחלפה בפונקציה.
drop policy events_select on events;
create policy events_select on events for select to authenticated using (
  (select app.is_admin())
  or (deleted_at is null
    and ((select app.scope_ids('events', 'customers')) is null
         or customer_id = any((select app.scope_ids('events', 'customers'))::uuid[]))
    and ((select app.scope_ids('events', 'statuses')) is null
         or status_id = any((select app.scope_ids('events', 'statuses'))::uuid[]))
    and ((select app.scope_date_from('events')) is null
         or event_date >= (select app.scope_date_from('events')))
    and ((select app.scope_date_to('events')) is null
         or event_date <= (select app.scope_date_to('events')))
    and (not (select app.scope_own('events'))
         or created_by = (select app.profile_id())
         or (select app.on_event_as_staff(events.id)))
    and (
      ((select app.user_kind()) = 'staff' and ((select app.has('events.view'))
         or (select app.on_event_as_staff(events.id))))
      or ((select app.user_kind()) = 'customer_user' and customer_id = (select app.customer_id()))
      or ((select app.user_kind()) = 'contractor_user' and (
            ((select app.has('portal.view')) and exists (
               select 1 from tasks t where t.event_id = events.id
                 and t.contractor_id = (select app.contractor_id()) and t.deleted_at is null))
            or (select app.on_event_as_contractor_worker(events.id))))
    )));

-- ===== 4. ראש הצוות של האירוע ==============================================
--
-- "מי שמוגדר כראש צוות באחת ממשימות האירוע" אינו מפתח במרשם אלא עובדה על
-- השורה: אותו אדם הוא ראש צוות באירוע אחד ועובד מן השורה באירוע הבא, ואותה
-- שאלה נענית אחרת בכל אירוע. לכן זו זרוע בפוליסה ולא `role_permissions`.
--
-- מה שהיא פותחת: יומן האירוע (קריאה וכתיבת תיעוד) ואיש הקשר של הלקוח — שם
-- וטלפון. שלושה דברים שראש צוות בשטח צריך כדי לנהל את היום, ושעובד מן השורה
-- אינו צריך.
--
-- אותו תנאי פרסום של סעיף 3: ראשות צוות במשימה שעדיין טיוטה אינה תפקיד, היא
-- טיוטה של תפקיד.
create or replace function app.is_event_team_lead(p_event_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from tasks t
    join task_assignments a on a.task_id = t.id
    where t.event_id = p_event_id and t.deleted_at is null
      and a.profile_id = app.profile_id() and a.role = 'team_lead'
      and (app.can_plan_tasks()
           or t.status_id = (select s.id from statuses s
                              where s.entity = 'task' and s.code = 'assigned'
                                and s.deleted_at is null limit 1)))
$$;

comment on function app.is_event_team_lead(uuid) is
  'האם הקורא רשום כראש צוות באחת ממשימות האירוע שפורסמו. תפקיד פר-אירוע, '
  'ולכן הוא נבדק על השורה ולא במרשם ההרשאות.';

-- 4א. היומן. הזרוע הקיימת (מפתח + אירוע גלוי) נשארת מילה במילה, ולידה
-- הזרוע החדשה. ‏`exists (events ...)` בשתיהן נבדק תחת ה-RLS של הקורא, ולכן
-- ראש צוות אינו מקבל כאן יומן של אירוע שאינו רואה ממילא.
drop policy event_activity_select on event_activity;
create policy event_activity_select on event_activity for select to authenticated using (
  (select app.is_admin())
  or (((select app.has('events.activity_log'))
       or (select app.is_event_team_lead(event_activity.event_id)))
      and exists (select 1 from events e where e.id = event_activity.event_id)));

drop policy event_activity_note_insert on event_activity;
create policy event_activity_note_insert on event_activity for insert to authenticated with check (
  kind = 'note'
  and ((select app.has('events.activity_note'))
       or (select app.is_event_team_lead(event_activity.event_id)))
  and actor_profile_id = (select app.profile_id())
  and exists (select 1 from events e where e.id = event_activity.event_id));

-- 4ב. איש הקשר. ‏`can_view_field` נשאר הנתיב של המשרד; ראש הצוות מגיע
-- מהזרוע השנייה, ו-`event_visible` שמאחוריה היא מעכשיו (סעיף 1) בדיוק
-- ההיקף של `events_select`.
drop policy event_contacts_select on event_contacts;
create policy event_contacts_select on event_contacts for select to authenticated using (
  (select app.is_admin())
  or (((select app.can_view_field('event', 'contact_phone'))
       or (select app.is_event_team_lead(event_id)))
      and (select app.event_visible(event_id))));

-- ===== 5. יציאה ממחסן נמדדת מול המחסן ======================================
--
-- ‏0023 קבעה ש"נקודת הסיום היא תמיד האתר: שם נגמרת העבודה, גם למי שיצא
-- מהמחסן", וזה נכון לגזירת השעות — אבל לא לשאלה "איפה העובד עומד כשהוא
-- מחתים יציאה". מי שיצא מהמחסן חוזר אליו (0079 §4 סופרת לו בדיוק את הנסיעה
-- הזו), ולכן הוא מחתים יציאה כשהוא כבר שם — והבדיקה מול מיקום האירוע חסמה
-- אותו במקום שאליו המערכת עצמה שלחה אותו.
--
-- התיקון אינו "לוותר על הבדיקה" אלא להכיר בשתי נקודות סיום לגיטימיות:
-- האתר, והמחסן שממנו יצא. שתיהן כבר יושבות על שורת המשמרת —
-- `end_lat/end_lng` הוא האתר ו-`start_lat/start_lng` הוא המחסן — ולכן אין
-- כאן שליפה חדשה אלא בחירה של הקרובה מבין השתיים. מי שהגיע לשטח ממשיך
-- להימדד מול האתר בלבד, כי משם הוא גם התחיל.
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

  return jsonb_build_object('ok', true, 'entry_id', v_entry.id, 'distance_m', v_dist);
end $$;
