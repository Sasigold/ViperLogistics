-- 0030: התראות שיוצאות מהמערכת
--
-- app.notify() כותב שורה ל-notifications, ו-NotificationsBell מציג אותה
-- ב-Realtime. מי שלא פתח את המסך לא יודע כלום — וזה כולל את מי ששובץ
-- למשימה מחר בבוקר, את הקבלן שקיבל האצלה, ואת המנהל שממתין לאשר דיווח.
--
-- שלושה כללים מעצבים את מה שלמטה:
--
-- 1. הנקודה היחידה שמכירה *כל* התראה היא app.notify. החיבור נעשה שם ולא
--    בכל טריגר בנפרד, אחרת התראה שתתווסף מחר תישכח.
-- 2. המשלוח אינו חלק מהכתיבה. שורת התראה נכתבת גם כשהדואר לא זמין, ולהפך:
--    כישלון שליחה לא מפיל את השמירה של המשימה שגרמה לה. לכן יש outbox.
-- 3. שום דבר לא נשלח עד שמפעיל מדליק את זה. שדרוג שמתחיל לפתע להציף
--    עובדים במיילים הוא תקלה, גם אם כל שורה בו נכונה.

-- ===== 1. מה נשלח, למי, ובאיזה ערוץ =================================

create table notification_deliveries (
  id              uuid primary key default gen_random_uuid(),
  notification_id uuid not null references notifications(id) on delete cascade,
  recipient_id    uuid not null references profiles(id) on delete cascade,
  channel         text not null check (channel in ('email')),
  address         text,
  status          text not null default 'pending'
                    check (status in ('pending', 'sent', 'failed', 'skipped')),
  attempts        int not null default 0,
  last_error      text,
  created_at      timestamptz not null default now(),
  sent_at         timestamptz
);
create index notification_deliveries_pending_idx
  on notification_deliveries (created_at) where status = 'pending';
create index notification_deliveries_notification_idx
  on notification_deliveries (notification_id);

-- העדפה פר-משתמש ופר-סוג. היעדר שורה משמעו ברירת המחדל של הערוץ, ולכן
-- מי שלא נגע בכלום מקבל את ההתנהגות הרגילה בלי שנכתבה לו שורה.
create table notification_preferences (
  profile_id uuid not null references profiles(id) on delete cascade,
  channel    text not null check (channel in ('email')),
  -- null = כל הסוגים. שורה עם סוג ספציפי גוברת עליה.
  type       text,
  enabled    boolean not null,
  updated_at timestamptz not null default now(),
  unique (profile_id, channel, type)
);
create index notification_preferences_profile_idx
  on notification_preferences (profile_id);

alter table notification_deliveries enable row level security;
alter table notification_preferences enable row level security;

-- יומן המשלוח הוא נתון תפעולי: אדמין רואה, אחרים לא. לעובד אין מה לעשות
-- איתו, ולכן הוא לא נפתח לבעל השורה.
create policy nd_select on notification_deliveries for select to authenticated
  using ((select app.is_admin()) or (select app.has('settings.audit_log')));

-- ההעדפות הן של המשתמש עצמו. אדמין רואה ועורך, כדי שיוכל לכבות ערוץ
-- למישהו שביקש בטלפון.
create policy np_select on notification_preferences for select to authenticated
  using ((select app.is_admin()) or profile_id = (select app.profile_id()));
create policy np_write on notification_preferences for all to authenticated
  using ((select app.is_admin()) or profile_id = (select app.profile_id()))
  with check ((select app.is_admin()) or profile_id = (select app.profile_id()));

-- ===== 2. ההכרעה: האם לשלוח ========================================

insert into app_settings (key, value) values
  ('notifications.email', jsonb_build_object(
    -- כבוי עד שמפעיל מדליק. זו הנקודה שבה שדרוג מפסיק להיות מפתיע.
    'enabled', false,
    -- סוגים שאינם ראויים למייל גם כשהערוץ דלוק
    'muted_types', jsonb_build_array(),
    'from', 'ViperLogistics <noreply@example.com>'))
on conflict (key) do nothing;

create or replace function app.email_enabled()
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((app.attendance_config('notifications.email') ->> 'enabled')::boolean, false)
$$;

/**
 * ההכרעה פר-נמען ופר-סוג. סדר: מפתח כבוי גלובלית ⇒ לא; סוג מושתק ⇒ לא;
 * העדפה לסוג ⇒ היא; העדפה כללית ⇒ היא; אחרת ⇒ כן.
 */
create or replace function app.should_email(p_profile uuid, p_type text)
returns boolean language plpgsql stable security definer set search_path = public as $$
declare
  v_cfg jsonb := app.attendance_config('notifications.email');
  v_pref boolean;
begin
  if not coalesce((v_cfg ->> 'enabled')::boolean, false) then return false; end if;
  if coalesce(v_cfg -> 'muted_types', '[]'::jsonb) ? p_type then return false; end if;

  select enabled into v_pref from notification_preferences
   where profile_id = p_profile and channel = 'email' and type = p_type;
  if found then return v_pref; end if;

  select enabled into v_pref from notification_preferences
   where profile_id = p_profile and channel = 'email' and type is null;
  if found then return v_pref; end if;

  return true;
end $$;

-- ===== 3. ה-outbox, מחובר בנקודה האחת שמכירה כל התראה ===============
--
-- app.notify נשאר האחראי היחיד. הוא מוגדר מחדש כאן במלואו ולא נעטף, כי
-- עטיפה הייתה משאירה שתי פונקציות שמישהו יקרא לשגויה שבהן.
create or replace function app.notify(
  p_recipient uuid, p_type text, p_title text, p_body text,
  p_entity_type text default null, p_entity_id uuid default null)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_id uuid;
  v_email text;
begin
  if p_recipient is null then return; end if;
  insert into notifications (recipient_id, type, title, body, entity_type, entity_id)
  values (p_recipient, p_type, p_title, p_body, p_entity_type, p_entity_id)
  returning id into v_id;

  -- המשלוח נרשם ואינו מבוצע. כישלון של ספק דואר לא אמור להפיל את השמירה
  -- של המשימה שגרמה להתראה, וגם לא להאט אותה בקריאת רשת.
  if app.should_email(p_recipient, p_type) then
    select p.email into v_email from profiles p
     where p.id = p_recipient and p.is_active and p.deleted_at is null;
    if v_email is not null and v_email <> '' then
      insert into notification_deliveries (notification_id, recipient_id, channel, address)
      values (v_id, p_recipient, 'email', v_email);
    end if;
  end if;
end $$;

-- ===== 4. הניקוז =====================================================
--
-- מי שמנקז את ה-outbox הוא notify-dispatch. הוא נקרא בשתי דרכים, ובכוונה
-- לא רק באחת:
--
--   • pg_net מהטריגר שלמטה — מיידי, וזמין בפרודקשן.
--   • קריאה חיצונית ל-notification_pending()/notification_mark() — לתזמון,
--     ולניסיון חוזר על מה שנכשל.
--
-- pg_net אינו קיים על Postgres רגיל, וחבילת הבדיקות מריצה את המיגרציות על
-- אשכול כזה. לכן הכול כאן מותנה בקיום בפועל ולא בהנחה.
do $$
begin
  create extension if not exists pg_net with schema extensions;
exception when others then
  raise notice 'pg_net unavailable — delivery falls back to polling the outbox';
end $$;

/**
 * היעד והסוד אינם יושבים ב-app_settings: היא קריאה לכל משתמש מאומת דרך
 * PostgREST. הם נקראים מהגדרות מסד הנתונים, שמפעיל קובע פעם אחת:
 *
 *   alter database postgres set app.notify_dispatch_url = 'https://<ref>.supabase.co/functions/v1/notify-dispatch';
 *   alter database postgres set app.notify_dispatch_secret = '<אקראי>';
 *
 * בלי שניהם הטריגר שותק, וה-outbox ממתין לניקוז חיצוני.
 */
create or replace function app.notify_dispatch_ping()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_url text := nullif(current_setting('app.notify_dispatch_url', true), '');
  v_secret text := nullif(current_setting('app.notify_dispatch_secret', true), '');
begin
  if v_url is null or v_secret is null then return null; end if;
  if to_regproc('net.http_post') is null then return null; end if;

  execute
    'select net.http_post(url := $1, headers := $2, body := $3)'
  using
    v_url,
    jsonb_build_object('Content-Type', 'application/json', 'x-dispatch-secret', v_secret),
    jsonb_build_object('delivery_id', new.id);
  return null;
exception when others then
  -- התראה שלא נשלחה אינה סיבה לבטל את מה שיצר אותה
  raise notice 'notify dispatch ping failed: %', sqlerrm;
  return null;
end $$;

create trigger notification_deliveries_dispatch after insert on notification_deliveries
  for each row execute function app.notify_dispatch_ping();

/**
 * מה שממתין למשלוח. security definer עם בדיקת מפתח, כי מי שקורא לזה הוא
 * ה-Edge Function בשם המערכת ולא המשתמש שההתראה שלו.
 */
create or replace function notification_pending(p_limit int default 50)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  perform app.require('settings.audit_log');
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'delivery_id', d.id,
      'address',     d.address,
      'title',       n.title,
      'body',        n.body,
      'type',        n.type,
      'entity_type', n.entity_type,
      'entity_id',   n.entity_id)
      order by d.created_at)
    from notification_deliveries d
    join notifications n on n.id = d.notification_id
    where d.status = 'pending' and d.attempts < 5
    limit greatest(1, least(p_limit, 200))
  ), '[]'::jsonb);
end $$;

create or replace function notification_mark(
  p_delivery_id uuid, p_status text, p_error text default null)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform app.require('settings.audit_log');
  if p_status not in ('sent', 'failed', 'skipped') then
    raise exception 'סטטוס משלוח לא מוכר: %', p_status;
  end if;
  update notification_deliveries
     set status     = p_status,
         attempts   = attempts + 1,
         last_error = p_error,
         sent_at    = case when p_status = 'sent' then now() else sent_at end
   where id = p_delivery_id;
end $$;

revoke execute on function public.notification_pending(int) from anon, public;
revoke execute on function public.notification_mark(uuid, text, text) from anon, public;

-- ===== 5. הרשאה למסך ההעדפות ========================================
select app.register_permission('notifications.preferences', 'settings',
  'העדפות התראות', 'באילו ערוצים לקבל אילו התראות', 'access',
  true, false, array['staff','customer_user','contractor_user']::user_kind[], null, 95);
