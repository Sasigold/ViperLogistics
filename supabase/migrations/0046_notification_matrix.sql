-- 0046: מי מקבל אילו התראות, ובאילו ערוצים
--
-- עד כאן היו שני ערוצים: הפעמון (0004) והמייל (0030). לשניהם הייתה אותה
-- מגבלה — ההחלטה מה יוצא הייתה של המשתמש בלבד. למנהל לא הייתה שום דרך לומר
-- "עובד שמשובץ למשמרת מחר *יקבל* על זה הודעה", ולא "אל תטרידו לקוחות
-- בדיווחי נוכחות". המסך היחיד היה /my/notifications, וכל אחד ישב שם לבדו.
--
-- המיגרציה הזו מוסיפה שכבת מדיניות מעל ההעדפה האישית, וערוץ שלישי (push)
-- שמסתמך עליה. ארבעה עקרונות מעצבים אותה:
--
-- 1. סוגי ההתראות הם *קטלוג בבסיס הנתונים*, לא מערך ב-TSX. סוג שיתווסף מחר
--    יופיע במטריצת המנהל ובמסך ההעדפות מפני שהוא נרשם, ולא מפני שמישהו זכר
--    לעדכן קבוע בלקוח. זו בדיוק הגישה של permission_registry.
-- 2. ההכרעה "האם לשלוח" יושבת בפונקציה *אחת*, app.notification_enabled.
--    "נעול" שאפשר לעקוף בקריאת REST אינו נעול, ולכן האכיפה אינה בלקוח.
-- 3. ההתנהגות הקיימת אינה משתנה. ברירות המחדל של המייל בקטלוג הן opt_out,
--    וטבלאות המדיניות נולדות ריקות — ולכן סולם ההכרעה נוחת בדיוק על אותן
--    דרגות שבהן נחת app.should_email עד היום. push נולד כבוי פעמיים: גם
--    בקטלוג וגם במפתח ההגדרות.
-- 4. שורת ההתראה נכתבת תמיד. גם כשהפעמון מושתק לסוג הזה — הרשומה היא היומן,
--    ו-notification_deliveries תלויה בה במפתח זר. מה שההשתקה עושה הוא לסמן
--    את השורה muted, והמסכים מסננים.

-- ===== 1. קטלוג הסוגים ==============================================

create table notification_types (
  key                text primary key,
  label_he           text not null,
  description_he     text,
  group_he           text not null default 'כללי',
  -- למי הסוג הזה רלוונטי בכלל. תא במטריצה לקהל שאינו כאן מרונדר "—".
  -- זה טקסט ולא user_kind[]: 'admin' אינו user_kind אלא profiles.is_admin,
  -- ודחיסתו לתוך האנום הייתה מקלקלת את משמעותו בכל שאר המערכת.
  audiences          text[] not null default array['admin','staff','contractor_user','customer_user'],
  entity_type        text,
  default_mode_inapp text not null default 'opt_out',
  default_mode_email text not null default 'opt_out',
  default_mode_push  text not null default 'off',
  is_active          boolean not null default true,
  sort_order         int not null default 100,
  constraint nt_modes check (
    default_mode_inapp in ('off','opt_in','opt_out','forced') and
    default_mode_email in ('off','opt_in','opt_out','forced') and
    default_mode_push  in ('off','opt_in','opt_out','forced')),
  constraint nt_audiences check (
    audiences <@ array['admin','staff','contractor_user','customer_user'])
);

create or replace function app.register_notification_type(
  p_key text, p_label text,
  p_description text default null,
  p_group text default 'כללי',
  p_audiences text[] default array['admin','staff','contractor_user','customer_user'],
  p_entity_type text default null,
  p_inapp text default 'opt_out',
  p_email text default 'opt_out',
  p_push  text default 'off',
  p_sort int default 100)
returns void language sql security definer set search_path = public as $$
  insert into notification_types (
    key, label_he, description_he, group_he, audiences, entity_type,
    default_mode_inapp, default_mode_email, default_mode_push, sort_order)
  values (p_key, p_label, p_description, p_group, p_audiences, p_entity_type,
          p_inapp, p_email, p_push, p_sort)
  on conflict (key) do update set
    label_he           = excluded.label_he,
    description_he     = excluded.description_he,
    group_he           = excluded.group_he,
    audiences          = excluded.audiences,
    entity_type        = excluded.entity_type,
    default_mode_inapp = excluded.default_mode_inapp,
    default_mode_email = excluded.default_mode_email,
    default_mode_push  = excluded.default_mode_push,
    sort_order         = excluded.sort_order;
$$;

-- שבעת הסוגים שהמערכת פולטת היום, לפי app.notify_* ב-0004 וה-RPCs ב-0024.
-- שימו לב ל-attendance_approved / attendance_rejected: הלקוח החזיק עד היום
-- מתג בשם attendance_reviewed שאף טריגר לא פלט, ולכן ההעדפה שנכתבה דרכו
-- מעולם לא נקראה. הקטלוג הוא מה שמחסל את הרוח הזו.
select app.register_notification_type('task_assigned', 'שובצתי למשימה',
  'שיבוץ חדש שלי למשימה', 'משימות', array['staff'], 'task',
  'forced', 'opt_out', 'opt_in', 10);
select app.register_notification_type('task_changed', 'שינוי בזמני משימה ששובצתי אליה',
  'תאריך או שעת התייצבות שהשתנו', 'משימות', array['staff','contractor_user'], 'task',
  'forced', 'opt_out', 'opt_in', 20);
select app.register_notification_type('contractor_task', 'משימה חדשה הוקצתה לקבלן שלי',
  null, 'משימות', array['contractor_user'], 'task',
  'forced', 'opt_out', 'opt_in', 30);
select app.register_notification_type('event_created', 'לקוח פתח אירוע חדש',
  null, 'אירועים', array['admin','staff'], 'event',
  'opt_out', 'opt_out', 'opt_in', 40);
select app.register_notification_type('attendance_submitted', 'עובד דיווח משמרת שממתינה לאישור',
  null, 'נוכחות', array['admin','staff'], 'attendance_entry',
  'opt_out', 'opt_out', 'opt_in', 50);
select app.register_notification_type('attendance_approved', 'הדיווח שלי אושר',
  null, 'נוכחות', array['staff'], 'attendance_entry',
  'opt_out', 'opt_out', 'opt_in', 60);
select app.register_notification_type('attendance_rejected', 'הדיווח שלי נדחה',
  null, 'נוכחות', array['staff'], 'attendance_entry',
  'forced', 'opt_out', 'opt_in', 70);

-- ===== 2. קהל =======================================================
--
-- אדמין גובר על סוג המשתמש. מנהל הוא staff מבחינת user_kind, ואילו הכפיפו
-- אותו לשורת "עובדים" במטריצה, כל שינוי שנועד לעובדים היה חל גם עליו.
create or replace function app.notification_audience(p_profile uuid)
returns text language sql stable security definer set search_path = public as $$
  select case when p.is_admin then 'admin' else p.user_kind::text end
    from profiles p where p.id = p_profile
$$;

-- ===== 3. המדיניות ==================================================

create table notification_policies (
  audience   text not null check (audience in ('admin','staff','contractor_user','customer_user')),
  type       text not null references notification_types(key) on delete cascade,
  channel    text not null check (channel in ('inapp','email','push')),
  mode       text not null check (mode in ('off','opt_in','opt_out','forced')),
  updated_at timestamptz not null default now(),
  primary key (audience, type, channel)
);

-- חריג פר-משתמש, שנקבע *על ידי מנהל*. מובחן מ-notification_preferences,
-- שהיא בחירתו של המשתמש עצמו: מנהל שמכבה ערוץ למישהו שביקש בטלפון אינו
-- אמור למחוק בכך את שאר ההעדפות של אותו אדם, ולא להיראות כאילו הוא בחר בהן.
create table notification_policy_overrides (
  profile_id uuid not null references profiles(id) on delete cascade,
  type       text not null references notification_types(key) on delete cascade,
  channel    text not null check (channel in ('inapp','email','push')),
  mode       text not null check (mode in ('off','opt_in','opt_out','forced')),
  note       text,
  updated_at timestamptz not null default now(),
  primary key (profile_id, type, channel)
);

-- שתיהן נולדות ריקות, וזו אינה עצלות: טבלה דלילה קריאה. מה שהמנהל באמת
-- שינה הוא בדיוק `select * from notification_policies`, ולא 108 שורות
-- שצריך להשוות אל מול ברירות המחדל כדי לדעת מה מהן משמעותי.

-- ===== 4. מנויי Push ================================================

create table push_subscriptions (
  id            uuid primary key default gen_random_uuid(),
  profile_id    uuid not null references profiles(id) on delete cascade,
  -- ייחודי גלובלית ולא פר-משתמש: ה-endpoint שייך לדפדפן, לא לאדם. שני
  -- אנשים שמתחלפים על אותו מכשיר חייבים להעביר בעלות על השורה, אחרת
  -- ההתראות של הראשון היו ממשיכות להגיע אחרי שהשני התחבר.
  endpoint      text not null unique,
  p256dh        text not null,
  auth          text not null,
  user_agent    text,
  created_at    timestamptz not null default now(),
  last_seen_at  timestamptz not null default now(),
  failure_count int not null default 0,
  last_error    text
);
create index push_subscriptions_profile_idx on push_subscriptions (profile_id);

-- ===== 5. הרחבת ה-outbox וההעדפות ===================================
--
-- שמות האילוצים נוצרו אוטומטית ב-0030, ולכן הם נמחקים לפי חיפוש בקטלוג
-- ולא לפי שם מנוחש. שם שנוחש נכון על אשכול אחד ולא על אחר הוא מיגרציה
-- שנופלת בפרודקשן אחרי שעברה בבדיקות.
do $$
declare c text;
begin
  for c in select conname from pg_constraint
    where conrelid = 'notification_deliveries'::regclass and contype = 'c'
      and pg_get_constraintdef(oid) like '%channel%'
  loop execute format('alter table notification_deliveries drop constraint %I', c); end loop;

  for c in select conname from pg_constraint
    where conrelid = 'notification_preferences'::regclass and contype = 'c'
      and pg_get_constraintdef(oid) like '%channel%'
  loop execute format('alter table notification_preferences drop constraint %I', c); end loop;
end $$;

alter table notification_deliveries
  add constraint notification_deliveries_channel_check check (channel in ('email','push')),
  add column subscription_id uuid references push_subscriptions(id) on delete cascade;

-- משלוח מייל חייב כתובת, ומשלוח push חייב מנוי. בלי זה שורה חסרת יעד הייתה
-- יושבת ב-pending לנצח ומבזבזת חמישה ניסיונות.
alter table notification_deliveries
  add constraint notification_deliveries_target check (
    (channel = 'email' and address is not null) or
    (channel = 'push'  and subscription_id is not null));

create index notification_deliveries_subscription_idx
  on notification_deliveries (subscription_id) where subscription_id is not null;

alter table notification_preferences
  add constraint notification_preferences_channel_check
  check (channel in ('inapp','email','push'));

/*
 * תיקון באג חי.
 *
 * האילוץ ב-0030 היה `unique (profile_id, channel, type)`, וב-PostgreSQL
 * ברירת המחדל היא NULLS DISTINCT: שתי שורות עם type = null אינן מתנגשות.
 * מסך ההעדפות עושה upsert עם onConflict על שלושת העמודות, ולכן *כל* לחיצה
 * על המתג הראשי "קבלת מיילים" הוסיפה שורה חדשה במקום לעדכן, ו-should_email
 * קרא באמצעות `select ... into` אחת מהן באופן שרירותי. המתג הראשי שבור
 * היום, וללא התיקון הזה הוא היה נשאר שבור גם במסך החדש.
 */
delete from notification_preferences a using notification_preferences b
 where a.ctid < b.ctid and a.profile_id = b.profile_id
   and a.channel = b.channel and a.type is not distinct from b.type;

do $$
declare c text;
begin
  for c in select conname from pg_constraint
    where conrelid = 'notification_preferences'::regclass and contype = 'u'
  loop execute format('alter table notification_preferences drop constraint %I', c); end loop;
end $$;

alter table notification_preferences
  add constraint notification_preferences_uq
  unique nulls not distinct (profile_id, channel, type);

-- השתקת פעמון. השורה נכתבת תמיד — היא הרשומה, והיא עוגן ה-FK של ה-outbox.
alter table notifications add column muted boolean not null default false;

-- ===== 6. RLS =======================================================

alter table notification_types enable row level security;
alter table notification_policies enable row level security;
alter table notification_policy_overrides enable row level security;
alter table push_subscriptions enable row level security;

-- הקטלוג נכתב על ידי מיגרציות בלבד, כמו permission_registry. אין policy
-- לכתיבה, ולכן גם אדמין אינו יכול לערוך אותו דרך PostgREST.
create policy nt_select on notification_types for select to authenticated using (true);

-- המדיניות אינה נקראת ישירות על ידי המשתמש: מסך ההעדפות עובר דרך RPC
-- מסוג definer. אחרת "נעול על ידי מנהל" היה דולף כטבלה שלמה לכל עובד.
create policy npol_all on notification_policies for all to authenticated
  using ((select app.is_admin()) or (select app.has('notifications.manage')))
  with check ((select app.is_admin()) or (select app.has('notifications.manage')));
create policy npo_all on notification_policy_overrides for all to authenticated
  using ((select app.is_admin()) or (select app.has('notifications.manage')))
  with check ((select app.is_admin()) or (select app.has('notifications.manage')));

/*
 * מנויים: הבעלים בלבד, ובכוונה גם לא אדמין.
 *
 * p256dh ו-auth הם מפתחות ההצפנה של המכשיר, ואין שום מסך שזקוק להם. מנהל
 * שרוצה לדעת כמה מכשירים רשומים מקבל ספירה דרך notification_push_stats,
 * ומנהל שרוצה לנתק מכשיר אבוד עושה זאת דרך notification_forget_device —
 * שתיהן definer, ואף אחת מהן אינה מחזירה מפתח.
 */
create policy ps_own on push_subscriptions for all to authenticated
  using (profile_id = (select app.profile_id()))
  with check (profile_id = (select app.profile_id()));

-- ===== 7. ההכרעה ====================================================

create or replace function app.notification_default_mode(p_type text, p_channel text)
returns text language sql stable security definer set search_path = public as $$
  select case p_channel
    when 'inapp' then t.default_mode_inapp
    when 'email' then t.default_mode_email
    when 'push'  then t.default_mode_push
  end from notification_types t where t.key = p_type
$$;

/**
 * האם ההתראה p_type יוצאת אל p_profile בערוץ p_channel.
 *
 * הסולם, מלמעלה למטה, והראשון שנוגע מכריע:
 *
 *   1. נמען לא פעיל או מחוק           ⇒ לא
 *   2. הערוץ כבוי במערכת              ⇒ לא   (inapp תמיד דלוק — הוא היומן)
 *   3. הסוג מושתק גלובלית             ⇒ לא   (muted_types, פתח המילוט מ-0030)
 *   4. חריג אישי שקבע מנהל            ⇒ המצב שבו
 *   5. מדיניות הקהל                   ⇒ המצב שבו
 *   6. ברירת המחדל בקטלוג             ⇒ המצב שבו
 *   7. סוג שאינו בקטלוג               ⇒ opt_out למייל ולפעמון, off ל-push
 *
 *   ואז, על המצב שהתקבל:
 *      off    ⇒ לא          forced ⇒ כן
 *      opt_in / opt_out ⇒ ההעדפה האישית: שורה לסוג, אחרת שורה כללית,
 *                          אחרת opt_out ⇒ כן / opt_in ⇒ לא
 *
 * דרגה 7 היא מה ששומר על התאימות לאחור: סוג שנפלט מטריגר שטרם נרשם בקטלוג
 * ממשיך להתנהג בדיוק כמו ב-0030 ולא נעלם בשקט.
 */
create or replace function app.notification_enabled(
  p_profile uuid, p_type text, p_channel text)
returns boolean language plpgsql stable security definer set search_path = public as $$
declare
  v_cfg  jsonb;
  v_mode text;
  v_pref boolean;
begin
  if p_profile is null then return false; end if;

  -- 1
  if not exists (select 1 from profiles p
                  where p.id = p_profile and p.is_active and p.deleted_at is null) then
    return false;
  end if;

  -- 2 + 3
  if p_channel <> 'inapp' then
    v_cfg := app.attendance_config('notifications.' || p_channel);
    if not coalesce((v_cfg ->> 'enabled')::boolean, false) then return false; end if;
    if coalesce(v_cfg -> 'muted_types', '[]'::jsonb) ? p_type then return false; end if;
  end if;

  -- 4
  select o.mode into v_mode from notification_policy_overrides o
   where o.profile_id = p_profile and o.type = p_type and o.channel = p_channel;

  -- 5
  if v_mode is null then
    select p.mode into v_mode from notification_policies p
     where p.audience = app.notification_audience(p_profile)
       and p.type = p_type and p.channel = p_channel;
  end if;

  -- 6
  if v_mode is null then
    v_mode := app.notification_default_mode(p_type, p_channel);
  end if;

  -- 7
  if v_mode is null then
    v_mode := case when p_channel = 'push' then 'off' else 'opt_out' end;
  end if;

  if v_mode = 'off'    then return false; end if;
  if v_mode = 'forced' then return true;  end if;

  select enabled into v_pref from notification_preferences
   where profile_id = p_profile and channel = p_channel and type = p_type;
  if found then return v_pref; end if;

  select enabled into v_pref from notification_preferences
   where profile_id = p_profile and channel = p_channel and type is null;
  if found then return v_pref; end if;

  return v_mode = 'opt_out';
end $$;

-- app.notify קורא לזה, וחבילת הבדיקות של 0030 נשענת עליו. נשאר כקליפה דקה
-- ולא כלוגיקה מקבילה, כדי שלא ייווצרו שתי אמיתות על אותה שאלה.
create or replace function app.should_email(p_profile uuid, p_type text)
returns boolean language sql stable security definer set search_path = public as $$
  select app.notification_enabled(p_profile, p_type, 'email')
$$;

-- ===== 8. app.notify — הגרסה השלישית ================================
--
-- מוגדרת מחדש במלואה ולא נעטפת, מאותו נימוק שנכתב ב-0030: עטיפה הייתה
-- משאירה שתי פונקציות שמישהו יקרא לשגויה שבהן.
--
-- כל שורות המשלוח נכתבות בהוראה *אחת*. הטריגר שמנקז אותן הוא statement-level
-- (סעיף 9), ולכן התראה אחת עם ארבעה מכשירים יורה קריאת HTTP אחת ולא חמש.
create or replace function app.notify(
  p_recipient uuid, p_type text, p_title text, p_body text,
  p_entity_type text default null, p_entity_id uuid default null)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_id    uuid;
  v_email text;
  v_muted boolean;
begin
  if p_recipient is null then return; end if;

  v_muted := not app.notification_enabled(p_recipient, p_type, 'inapp');

  insert into notifications (recipient_id, type, title, body, entity_type, entity_id, muted)
  values (p_recipient, p_type, p_title, p_body, p_entity_type, p_entity_id, v_muted)
  returning id into v_id;

  -- חשבון מושבת או מחוק אינו מקבל דבר. notification_enabled כבר חוסם, אבל
  -- הכתובת נדרשת ממילא ולכן השאילתה הזו משרתת את שתי המטרות.
  select p.email into v_email from profiles p
   where p.id = p_recipient and p.is_active and p.deleted_at is null;

  insert into notification_deliveries
    (notification_id, recipient_id, channel, address, subscription_id)
  select v_id, p_recipient, 'email', v_email, null
   where v_email is not null and v_email <> ''
     and app.notification_enabled(p_recipient, p_type, 'email')
  union all
  select v_id, p_recipient, 'push', null, s.id
    from push_subscriptions s
   where s.profile_id = p_recipient
     and app.notification_enabled(p_recipient, p_type, 'push');
end $$;

-- ===== 9. ניקוז ברמת ההוראה =========================================
--
-- הטריגר של 0030 היה for each row. עם ערוץ אחד זה היה שקול, אבל התראה
-- שיוצאת לארבעה מכשירים ולמייל הייתה מייצרת חמש קריאות pg_net לאותה
-- פונקציה — שכולן מנקזות ממילא את אותו תור. statement-level יורה פעם אחת.
create or replace function app.notify_dispatch_ping()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_url text := nullif(current_setting('app.notify_dispatch_url', true), '');
  v_secret text := nullif(current_setting('app.notify_dispatch_secret', true), '');
begin
  if v_url is null or v_secret is null then return null; end if;
  if to_regproc('net.http_post') is null then return null; end if;

  -- גוף ריק = ניקוז מלא. ממילא זו ההתנהגות הרצויה: מה שנכשל קודם מקבל
  -- הזדמנות נוספת באותה קריאה.
  execute
    'select net.http_post(url := $1, headers := $2, body := $3)'
  using
    v_url,
    jsonb_build_object('Content-Type', 'application/json', 'x-dispatch-secret', v_secret),
    '{}'::jsonb;
  return null;
exception when others then
  raise notice 'notify dispatch ping failed: %', sqlerrm;
  return null;
end $$;

drop trigger if exists notification_deliveries_dispatch on notification_deliveries;
create trigger notification_deliveries_dispatch after insert on notification_deliveries
  for each statement execute function app.notify_dispatch_ping();

-- ===== 10. מפתח ההגדרות של push =====================================

insert into app_settings (key, value) values
  ('notifications.push', jsonb_build_object(
    'enabled', false,
    'muted_types', jsonb_build_array(),
    /*
     * המפתח הפומבי בלבד, והבחנה שקל לפספס: app_settings פתוחה לקריאה לכל
     * משתמש מאומת (0005: `for select using (true)`), ולכן כל מה שיושב כאן
     * גלוי לכל עובד וכל לקוח. המפתח הפרטי של VAPID חי אך ורק במשתני הסביבה
     * של notify-dispatch, בדיוק כמו app.notify_dispatch_secret שאינו כאן.
     */
    'vapid_public_key', ''))
on conflict (key) do nothing;

-- הפוליסה מ-0019 נתנה notifications.% למחזיק settings.edit. מפתחות ההתראות
-- שייכים מעכשיו גם למי שמנהל אותן, ולכן החלפה ולא הוספה — בדיוק כפי ש-0019
-- עשה בשעתו לנוכחות.
drop policy if exists app_settings_write on app_settings;
create policy app_settings_write on app_settings for all to authenticated
  using ((select app.is_admin())
         or (key like 'attendance.%'    and (select app.has('attendance.settings')))
         or (key like 'notifications.%' and (select app.has('notifications.manage')))
         or (key not like 'attendance.%' and key not like 'notifications.%'
             and (select app.has('settings.edit'))))
  with check ((select app.is_admin())
         or (key like 'attendance.%'    and (select app.has('attendance.settings')))
         or (key like 'notifications.%' and (select app.has('notifications.manage')))
         or (key not like 'attendance.%' and key not like 'notifications.%'
             and (select app.has('settings.edit'))));

-- ===== 11. הרשאה ====================================================
--
-- implied_by = settings.edit במכוון: מי שעורך הגדרות כבר כותב היום את
-- notifications.email, והפוליסה שלמעלה הייתה נועלת אותו החוצה ברגע הפריסה.
select app.register_permission('notifications.manage', 'settings',
  'ניהול התראות', 'מי מקבל אילו התראות ובאילו ערוצים', 'action',
  false, false, array['staff']::user_kind[], 'settings.edit', 96);

-- ===== 12. RPCs =====================================================

/**
 * מה *אני* מקבל, אחרי כל שכבות ההכרעה.
 *
 * זו נקודת האמת היחידה של מסך ההעדפות. מירור של הסולם ב-TypeScript היה
 * הדבר שמתיישן — ולכן הלקוח מקבל כאן גם enabled וגם locked, ולא מחשב דבר.
 * אין app.require: notifications.preferences הוא default_allowed, וכל בעל
 * חשבון מגיע למסך הזה ממילא.
 */
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
  ), '[]'::jsonb);
end $$;

-- תא בודד: המצב שהוכרע, האם יוצא בפועל, והאם המשתמש רשאי לגעת.
create or replace function app.notification_cell(p_profile uuid, p_type text, p_channel text)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_mode text;
  v_chan boolean := true;
begin
  select o.mode into v_mode from notification_policy_overrides o
   where o.profile_id = p_profile and o.type = p_type and o.channel = p_channel;
  if v_mode is null then
    select p.mode into v_mode from notification_policies p
     where p.audience = app.notification_audience(p_profile)
       and p.type = p_type and p.channel = p_channel;
  end if;
  if v_mode is null then v_mode := app.notification_default_mode(p_type, p_channel); end if;
  if v_mode is null then
    v_mode := case when p_channel = 'push' then 'off' else 'opt_out' end;
  end if;

  if p_channel <> 'inapp' then
    v_chan := coalesce(
      (app.attendance_config('notifications.' || p_channel) ->> 'enabled')::boolean, false);
  end if;

  return jsonb_build_object(
    'mode', v_mode,
    'enabled', app.notification_enabled(p_profile, p_type, p_channel),
    'locked', v_mode in ('off','forced'),
    'channel_enabled', v_chan);
end $$;

/**
 * שינוי העדפה אישית.
 *
 * דוחה במפורש סוג שהמנהל נעל או כיבה, במקום להיכשל בשקט. מתג שנדלק בממשק
 * ולא משנה דבר בשרת גרוע יותר ממתג שאומר למה הוא לא זז.
 */
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
  if not exists (select 1 from notification_types where key = p_type and is_active) then
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

-- ספירת מכשירים למסך המנהל. definer, ובלי להחזיר ולו מפתח אחד.
create or replace function notification_push_stats()
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  perform app.require('notifications.manage');
  return coalesce((
    select jsonb_object_agg(a, jsonb_build_object('devices', d, 'people', p))
    from (
      select app.notification_audience(s.profile_id) as a,
             count(*)::int as d, count(distinct s.profile_id)::int as p
        from push_subscriptions s
       group by 1
    ) q
  ), '{}'::jsonb);
end $$;

-- ניתוק מכשיר אבוד על ידי מנהל, בלי לפתוח לו קריאה לטבלה.
create or replace function notification_forget_device(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform app.require('notifications.manage');
  delete from push_subscriptions where id = p_id;
end $$;

-- הגדרות של משתמש אחר, למסך החריגים.
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
  ), '[]'::jsonb);
end $$;

-- התור שממתין, מורחב לערוצים. ה-endpoint המלא אינו מוחזר — רק שירות הדחיפה,
-- שזה מה שמעניין כשמאבחנים "כל ההתראות לאנדרואיד נכשלות".
create or replace function notification_pending(p_limit int default 50)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  perform app.require('settings.audit_log');
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'delivery_id', d.id,
      'channel',     d.channel,
      'address',     d.address,
      'push_host',   split_part(s.endpoint, '/', 3),
      'title',       n.title,
      'body',        n.body,
      'type',        n.type,
      'entity_type', n.entity_type,
      'entity_id',   n.entity_id)
      order by d.created_at)
    from notification_deliveries d
    join notifications n on n.id = d.notification_id
    left join push_subscriptions s on s.id = d.subscription_id
    where d.status = 'pending' and d.attempts < 5
    limit greatest(1, least(p_limit, 200))
  ), '[]'::jsonb);
end $$;

revoke execute on function public.notification_pending(int) from anon, public;
revoke execute on function public.notification_push_stats() from anon, public;
revoke execute on function public.notification_forget_device(uuid) from anon, public;
revoke execute on function public.notification_user_settings(uuid) from anon, public;
revoke execute on function public.my_notification_settings() from anon;
revoke execute on function public.set_notification_preference(text, text, boolean) from anon;
