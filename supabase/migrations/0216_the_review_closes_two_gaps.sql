-- 0216: שני פערים שהסקירה של PR #33 מצאה ב-0214
--
-- שני הממצאים של הסקירה האוטומטית (Codex) על 0214 אומתו מול הקוד, ושניהם
-- נכונים. המיגרציה כתובה ב-`alter policy` ולא ב-`drop policy` + `create
-- policy`, כדי שתוחל במסד החי בדיוק כפי שהיא כאן (הכלי שמחיל מיגרציות עוצר
-- כל DROP לאישור שאינו מגיע — ראו CLAUDE.md §1).
--
--   1. **מטא-דאטה של הרשאות בין עמיתים** (0214 §7, 0215). בפוליסות הקריאה של
--      התפקידים, ההרשאות האישיות, ההיקפים, הרשאות השדות והדפים, הזרוע
--      `app.can_manage_profile(profile_id)` עמדה לבדה. אצל משתמש לקוח הפונקציה
--      עונה "כן" על כל אדם אחר מאותו לקוח **בלי לשאול על מפתח** — התיעוד שלה
--      (0014) אומר שמי שקורא לה מצמיד אליה את המפתח, כמו שפוליסות הכתיבה של
--      0214 עושות. כך כל משתמש לקוח, גם צופה בלי "צפייה בעובדים", קרא את
--      התפקידים, ההענקות וההיקפים של עמיתיו אצל אותו לקוח. (לקוח אחר לא —
--      הגדר של 0214 החזיק.) עכשיו הזרוע דורשת "צפייה בעובדים" או "עריכת
--      הרשאות פר-משתמש".
--   2. **התראת "האירוע אושר" מול היקף חלקי** (0214 §9ג). הנמענים סוננו לפי
--      "רק מה שמשויך אליו" בלבד, ולכן משתמש לקוח עם "צפייה באירועים" שהיקף
--      סטטוסים, חלון תאריכים או רשימת לקוחות (גם ריקה) מוציא ממנו את האירוע —
--      קיבל בכל זאת את שמו ואת התאריך שלו בהתראה, על אירוע שאינו רואה.
--      עכשיו האירוע נבדק מול כל ההיקף של הנמען, באותם כללים של
--      `events_select`.

-- ===== 1. מטא-דאטה של הרשאות: המפתח מוצמד ל-can_manage_profile ==========

alter policy profile_roles_read on profile_roles to authenticated using (
  (select app.is_admin()) or profile_id = (select app.profile_id())
  or ((select app.user_kind()) = 'staff' and (select app.has('users.view')))
  or (((select app.has('users.view')) or (select app.has('users.manage_permissions')))
      and app.can_manage_profile(profile_id)));

alter policy user_grants_read on user_permission_grants to authenticated using (
  (select app.is_admin()) or profile_id = (select app.profile_id())
  or ((select app.user_kind()) = 'staff' and (select app.has('users.view')))
  or (((select app.has('users.view')) or (select app.has('users.manage_permissions')))
      and app.can_manage_profile(profile_id)));

alter policy permission_scopes_read on permission_scopes to authenticated using (
  (select app.is_admin()) or profile_id = (select app.profile_id())
  or ((select app.user_kind()) = 'staff' and (select app.has('users.view')))
  or (profile_id is not null
      and ((select app.has('users.view')) or (select app.has('users.manage_permissions')))
      and app.can_manage_profile(profile_id))
  -- שורות של תפקיד הן הגדרת הארגון ולא נתון של אדם, ונקראות כמו
  -- ‏`role_permissions` (‏`role_permissions_read`) — מסך ההיקפים מציג אותן
  -- כ"מהתפקיד" לצד ההיקף האישי.
  or (role_id is not null
      and ((select app.has('users.view')) or (select app.has('settings.permissions'))
           or role_id = any ((select app.my_role_ids())::uuid[]))));

alter policy fp_read on field_permissions to authenticated using (
  (select app.is_admin()) or profile_id = (select app.profile_id())
  or ((select app.user_kind()) = 'staff' and (select app.has('users.view')))
  or (profile_id is not null
      and ((select app.has('users.view')) or (select app.has('users.manage_permissions')))
      and app.can_manage_profile(profile_id)));

alter policy page_visibility_read on page_visibility to authenticated using (
  (select app.is_admin())
  or profile_id = (select app.profile_id())
  or ((select app.user_kind()) = 'staff'
      and ((select app.has('users.view')) or (select app.has('settings.permissions'))))
  or (profile_id is not null
      and ((select app.has('users.view')) or (select app.has('users.manage_permissions')))
      and app.can_manage_profile(profile_id))
  or (role_id is not null
      and ((select app.has('users.view')) or (select app.has('settings.permissions'))
           or role_id = any ((select app.my_role_ids())::uuid[]))));

-- ===== 2. "האירוע אושר" — רק למי שהאירוע בתוך ההיקף שלו ===================
--
-- ‏`app.scope_rows` של מישהו אחר: אותה הכרעה בדיוק (0214 §2) — שורה אישית
-- מחליפה את שורות התפקיד מאותו סוג, "ללא הגבלה" אישית מבטלת את כולן, ומנהל
-- מערכת אינו מוגבל — על התפקידים שבתוקף לו (`app.role_ids_of`, 0214 §9ג).
create or replace function app.scope_rows_of(p_profile uuid, p_resource text)
returns setof permission_scopes
language sql stable security definer set search_path = public as $$
  with target as (
    select coalesce((select p.is_admin from profiles p where p.id = p_profile), false) as admin
  ),
  mine as (
    select s.* from permission_scopes s cross join target t
     where not t.admin and s.resource = p_resource and s.profile_id = p_profile
  ),
  lifted as (
    select exists (select 1 from mine where scope_type = 'all') as yes
  )
  select m.* from mine m cross join lifted l
   where (m.scope_type = 'all') = l.yes
  union all
  select s.* from permission_scopes s cross join lifted l cross join target t
   where not t.admin
     and not l.yes
     and s.resource = p_resource
     and s.role_id = any (app.role_ids_of(p_profile))
     and s.scope_type <> 'all'
     and not exists (select 1 from mine m where m.scope_type = s.scope_type)
$$;

-- האם האירוע בתוך היקף האירועים של משתמש לקוח נתון — כל המימדים ש-
-- ‏`events_select` בודק אצלו: לקוחות, סטטוסים (רשימה ריקה = שום דבר, 0214),
-- חלון תאריכים, ו"רק מה שמשויך אליו" (שובץ לאירוע כעובד בסגל, או יצר אותו).
-- שתי השאלות האחרות של `events_select` — הלקוח שלו, ו"צפייה באירועים" או
-- שיבוץ — נשאלות אצל מי שקורא לה.
create or replace function app.event_in_scope_of(p_profile uuid, p_event_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  with s as (select * from app.scope_rows_of(p_profile, 'events')),
  w as (
    select
      (select (current_date - max(x.days_back))::date from s x
        where x.scope_type = 'date_window' and x.days_back is not null) as d_from,
      (select (current_date + max(x.days_forward))::date from s x
        where x.scope_type = 'date_window' and x.days_forward is not null) as d_to
  )
  select exists (
    select 1 from events e cross join w
     where e.id = p_event_id
       and (not exists (select 1 from s where s.scope_type = 'customers')
            or e.customer_id = any (array(select unnest(s.scope_values) from s where s.scope_type = 'customers')))
       and (not exists (select 1 from s where s.scope_type = 'statuses')
            or e.status_id = any (array(select unnest(s.scope_values) from s where s.scope_type = 'statuses')))
       and (w.d_from is null or e.event_date >= w.d_from)
       and (w.d_to is null or e.event_date <= w.d_to)
       and (not exists (select 1 from s where s.scope_type = 'own')
            or e.created_by = p_profile
            or exists (select 1 from tasks t
                         join task_customer_workers tw on tw.task_id = t.id
                         join customer_workers cuw on cuw.id = tw.customer_worker_id
                         join profiles pr on pr.customer_worker_id = tw.customer_worker_id
                        where t.event_id = e.id and t.deleted_at is null
                          and t.customer_id = cuw.customer_id
                          and pr.id = p_profile)))
$$;

-- שתיהן עונות על אדם אחר, ולכן אינן נפתחות לקריאה ישירה — רק לפונקציות
-- המערכת שקוראות להן (כמו `app.role_ids_of`).
revoke execute on function app.scope_rows_of(uuid, text) from anon, public;
revoke execute on function app.event_in_scope_of(uuid, uuid) from anon, public;

-- מועתקת מ-0214 §9ג; השינוי הוא בסינון הנמענים בלבד.
create or replace function public.set_event_approved(p_event_id uuid, p_on boolean default true)
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
        -- ‏0214: רק מי שהאירוע נפתח לו — "צפייה באירועים", או שובץ אליו.
        and (p.id in (select app.profiles_with('events.view'))
             or exists (select 1 from tasks t
                          join task_customer_workers w on w.task_id = t.id
                          join customer_workers cuw on cuw.id = w.customer_worker_id
                         where t.event_id = v_event.id and t.deleted_at is null
                           and cuw.customer_id = v_event.customer_id
                           and p.customer_worker_id = w.customer_worker_id))
        -- ‏0216: ובתוך כל ההיקף שלו, ולא רק "רק מה שמשויך אליו".
        and app.event_in_scope_of(p.id, v_event.id)
    loop
      perform app.notify(r.id, 'event_approved', 'האירוע אושר לביצוע',
        v_label || ' — ' || to_char(v_event.event_date, 'DD/MM/YYYY'), 'event', v_event.id);
    end loop;
  end if;

  return v_at;
end $$;

revoke execute on function public.set_event_approved(uuid, boolean) from anon, public;
grant execute on function public.set_event_approved(uuid, boolean) to authenticated;
