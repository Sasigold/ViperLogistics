-- 0236: עוזר וואטסאפ — שאלות ושינויים מתוך קבוצת הוואטסאפ, בהרשאות של מי שכותב
--
-- בקשת הבעלים: **"שתיקח את קבוצת הוואטסאפ שקיימת ב-Viper One, ושאוכל לשלוח
-- שם דברים ולקבל תשובות — גם לשאול, גם להכניס דברים למערכת וגם לשנות."**
-- ההכרעות שלו: הקבוצה הופכת לקבוצה של ViperLogistics בלבד; כל שינוי מחכה
-- ל"כן"; בגרסה הראשונה גם שיבוץ ופרסום, תשלומים ומזומן וצילום חשבונית ספק.
--
-- מה שהמיגרציה הזו בונה הוא רק הצד של המסד. ההודעות עצמן נכנסות לפונקציית
-- הקצה `whatsapp-webhook` (Green API, אותו מספר בוט של Viper One), וראו
-- `docs/WHATSAPP.md`. העקרונות שהמסד נושא:
--
--   1. **הבוט אינו משתמש-על.** הפונקציה מריצה כל קריאה בשם מי שכתב — בטרנזקציה
--      עם `set local role authenticated` ו-`request.jwt.claims` שלו, בדיוק כמו
--      הבדיקות — ולכן RLS, ‏`app.has`, ‏`app.require` והטריגרים פוסקים כאילו לחץ
--      בדפדפן. מה שכאן הוא רק "מי זה" ו"איפה מותר לענות".
--
--   2. **מי זה: קוד חד-פעמי.** משתמש מבקש קוד במסך (`wa_link_code_create`) ושולח
--      אותו לבוט בצ'אט פרטי; הפונקציה פודה אותו (`app.wa_link_redeem`) ומקשרת את
--      מזהה הוואטסאפ של השולח לפרופיל. כך אין מספרי טלפון להקליד, וזה עובד גם עם
--      מזהי ה-`@lid` החדשים של וואטסאפ. חמישה ניסיונות כושלים בשעה למספר, ובסוף
--      התראה בפעמון ("וואטסאפ חובר לחשבון שלך") למקרה שזה לא היה הוא.
--
--   3. **איפה מותר לענות.** צ'אט פרטי של משתמש מקושר — תמיד. קבוצה — רק אחרי
--      שמנהל מערכת מקושר חיבר אותה ("הפעל כאן"), ורק כל עוד *כל* המשתתפים בה הם
--      משתמשים מקושרים ופעילים (`app.wa_participants_ok`): תשובה בקבוצה גלויה לכל
--      חבריה. נתוני כסף בקבוצה דורשים בנוסף שלכולם יש את המפתח
--      (`app.wa_participants_hold`).
--
--   4. **המפתח** `assistant.whatsapp` חל על צוות בלבד (0214: מפתח שאינו חל על
--      הסוג אינו מוענק בשום שכבה), כבוי כברירת מחדל; מנהלי מערכת מחזיקים אותו.
--
--   5. **הפונקציה רצה בלי `auth.uid()`** כשהיא כותבת לטבלאות של עצמה, ולכן כל
--      פונקציה פנימית כאן מקבלת את הפרופיל במפורש ובודקת אותו דרך
--      `app.profiles_with` — בכל הודעה, לא רק בזמן הקישור.
--
--   6. **בלי DROP ובלי DELETE** (CLAUDE.md §1): ניתוק הוא `revoked_at`, וניתוק
--      קבוצה הוא `active = false`.

-- ===== 1. הרשאה ============================================================

select app.register_module('assistant', 'עוזר וואטסאפ',
  'עבודה מול המערכת מתוך וואטסאפ: שאלות, ושינויים שמחכים לאישור', 'MessageCircle', 88);

select app.register_permission('assistant.whatsapp', 'assistant', 'עוזר וואטסאפ',
  'לחבר את הוואטסאפ שלי ולעבוד מולו. הבוט פועל בהרשאות שלי בדיוק, וכל שינוי מחכה לאישור שלי',
  'access', false, false, array['staff']::user_kind[], null, 10);

-- ===== 2. הטבלאות ==========================================================

create table wa_links (
  id           uuid primary key default gen_random_uuid(),
  profile_id   uuid not null references profiles(id) on delete cascade,
  -- מזהה השולח כפי ש-Green API מוסר אותו: "9725…@c.us", או "…@lid"
  wa_id        text not null check (wa_id ~ '^[0-9]{5,20}@(c\.us|lid)$'),
  display_name text,
  linked_at    timestamptz not null default now(),
  revoked_at   timestamptz,
  revoked_by   uuid references profiles(id) on delete set null
);

-- מספר אחד לפרופיל, ופרופיל אחד למספר
create unique index wa_links_active_wa on wa_links (wa_id) where revoked_at is null;
create unique index wa_links_active_profile on wa_links (profile_id) where revoked_at is null;

comment on table wa_links is
  'מספר וואטסאפ שמחובר לפרופיל (0236 §2). נכתבת רק בפדיון קוד ובניתוק.';

create table wa_link_codes (
  profile_id uuid primary key references profiles(id) on delete cascade,
  code_hash  text not null,
  expires_at timestamptz not null,
  used_at    timestamptz,
  created_at timestamptz not null default now()
);

create index wa_link_codes_hash on wa_link_codes (code_hash);

comment on table wa_link_codes is
  'הקוד החד-פעמי האחרון של כל פרופיל (0236 §2). סגורה: רק הפונקציות שכאן נוגעות בה.';

create table wa_link_attempts (
  id         bigint generated always as identity primary key,
  wa_id      text not null,
  ok         boolean not null,
  created_at timestamptz not null default now()
);

create index wa_link_attempts_wa on wa_link_attempts (wa_id, created_at desc);

create table wa_chats (
  -- "1203…@g.us" לקבוצה, "9725…@c.us" לצ'אט פרטי
  chat_id                 text primary key
                          check (chat_id ~ '^[0-9]{5,20}(-[0-9]{5,20})?@(c\.us|g\.us|lid)$'),
  is_group                boolean not null,
  name                    text,
  active                  boolean not null default true,
  bound_by                uuid references profiles(id) on delete set null,
  bound_at                timestamptz not null default now(),
  unbound_at              timestamptz,
  unbound_by              uuid references profiles(id) on delete set null,
  -- [{id, lid, phoneNumber}] כפי ש-getGroupData החזיר, ומתי נבדק
  participants            jsonb not null default '[]'::jsonb,
  participants_checked_at timestamptz,
  -- כל משתתף אנושי הוא משתמש מקושר ופעיל (§3)
  participants_ok         boolean not null default false,
  -- מתי הבוט הודיע בקבוצה שהפסיק לענות בה (כדי לא לחזור על זה)
  blocked_notice_at       timestamptz,
  -- חזקת העיבוד: הודעה אחת בכל רגע לכל צ'אט, השאר בתור
  busy_until              timestamptz
);

comment on table wa_chats is
  'הצ''אטים שהעוזר עונה בהם (0236 §3): קבוצה שמנהל חיבר, או צ''אט פרטי של משתמש מקושר.';

create table wa_messages (
  id           uuid primary key default gen_random_uuid(),
  -- המזהה של Green API; ייחודי, ולכן הודעה שנמסרה פעמיים מעובדת פעם אחת
  message_id   text unique,
  direction    text not null check (direction in ('in', 'out')),
  chat_id      text not null,
  wa_id        text,
  profile_id   uuid references profiles(id) on delete set null,
  kind         text not null default 'text',
  body         text,
  status       text not null default 'received' check (status in
               ('received', 'queued', 'processing', 'answered', 'ignored', 'failed', 'sent')),
  error        text,
  meta         jsonb not null default '{}'::jsonb,
  -- השעה שבה ההודעה נשלחה בוואטסאפ (timestamp של Green API)
  sent_at      timestamptz,
  created_at   timestamptz not null default now(),
  processed_at timestamptz
);

create index wa_messages_chat_idx on wa_messages (chat_id, created_at desc);
create index wa_messages_queue_idx on wa_messages (chat_id, created_at) where status = 'queued';

comment on table wa_messages is
  'כל הודעה שנכנסה לעוזר או יצאה ממנו (0236): יומן, זיכרון השיחה והתור.';

create table wa_pending (
  id                 uuid primary key default gen_random_uuid(),
  chat_id            text not null,
  profile_id         uuid not null references profiles(id) on delete cascade,
  -- [{op, args, expect}] — מה שירוץ בדיוק אחרי "כן"
  ops                jsonb not null,
  -- השורות שהמשתמש ראה (נכתבות בקוד, לא בניסוח של המודל)
  preview            text[] not null,
  status             text not null default 'pending' check (status in
                     ('pending', 'running', 'done', 'failed', 'superseded', 'cancelled', 'expired')),
  result             jsonb,
  error              text,
  request_message_id text,
  confirm_message_id text,
  created_at         timestamptz not null default now(),
  expires_at         timestamptz not null default now() + interval '15 minutes',
  finished_at        timestamptz
);

-- פעולה פתוחה אחת לכל אדם בכל צ'אט; בקשה חדשה מחליפה את הקודמת
create unique index wa_pending_one_open on wa_pending (chat_id, profile_id)
  where status in ('pending', 'running');

comment on table wa_pending is
  'שינויים שמחכים ל"כן" (0236). סגורה: רק פונקציית הקצה קוראת וכותבת בה.';

alter table wa_links enable row level security;
alter table wa_link_codes enable row level security;
alter table wa_link_attempts enable row level security;
alter table wa_chats enable row level security;
alter table wa_messages enable row level security;
alter table wa_pending enable row level security;

revoke all on wa_links, wa_chats, wa_messages from anon, public;
revoke insert, update, delete, truncate on wa_links, wa_chats, wa_messages from authenticated;
grant select on wa_links, wa_chats, wa_messages to authenticated;
revoke all on wa_link_codes, wa_link_attempts, wa_pending from anon, authenticated, public;

-- קריאה בלבד; אין פוליסת כתיבה — הכתיבה בפונקציות definer ובפונקציית הקצה.
create policy wa_links_select on wa_links for select to authenticated
  using (profile_id = (select app.profile_id()) or (select app.is_admin()));
create policy wa_chats_select on wa_chats for select to authenticated
  using ((select app.is_admin()));
create policy wa_messages_select on wa_messages for select to authenticated
  using (profile_id = (select app.profile_id()) or (select app.is_admin()));

-- ===== 3. מי זה, ואיפה מותר לענות ==========================================

create or replace function app.wa_code_hash(p_code text)
returns text language sql immutable set search_path = public as $$
  select encode(sha256(convert_to(coalesce(btrim(p_code), ''), 'UTF8')), 'hex')
$$;

-- "972501234567@c.us" ← "+972 50-123-4567"; מזהה @lid נשאר כמו שהוא.
create or replace function app.wa_phone(p_wa_id text)
returns text language sql immutable set search_path = public as $$
  select case
    when p_wa_id ~ '^972[0-9]{8,9}@c\.us$' then '0' || substr(split_part(p_wa_id, '@', 1), 4)
    when p_wa_id ~ '^[0-9]+@c\.us$'        then '+' || split_part(p_wa_id, '@', 1)
    else p_wa_id end
$$;

-- מותר לו לעבוד מול העוזר עכשיו: פעיל, עם כניסה, ומחזיק במפתח. נשאל בכל הודעה.
create or replace function app.wa_allowed(p_profile uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from profiles p
                  where p.id = p_profile and p.is_active and p.deleted_at is null
                    and p.user_id is not null)
     and exists (select 1 from app.profiles_with('assistant.whatsapp') x where x = p_profile)
$$;

create or replace function app.wa_sender(p_wa_id text)
returns table (link_id uuid, profile_id uuid, user_id uuid, full_name text,
               is_admin boolean, allowed boolean)
language sql stable security definer set search_path = public as $$
  select l.id, p.id, p.user_id, p.full_name, p.is_admin, app.wa_allowed(p.id)
    from wa_links l
    join profiles p on p.id = l.profile_id
   where l.wa_id = p_wa_id and l.revoked_at is null
$$;

-- כל משתתף אנושי בקבוצה (כולם חוץ מהבוט) הוא משתמש מקושר שמותר לו לעבוד מול
-- העוזר. משתתף שמזוהה רק ב-lid נחשב מוכר רק אם הקישור שלו נעשה באותו lid.
create or replace function app.wa_participants_ok(p_participants jsonb, p_bot text)
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(bool_and(exists (
           select 1 from wa_links l
            where l.revoked_at is null
              and l.wa_id in (x ->> 'id', x ->> 'phoneNumber', x ->> 'lid')
              and app.wa_allowed(l.profile_id))), false)
    from jsonb_array_elements(coalesce(p_participants, '[]'::jsonb)) x
   where coalesce(x ->> 'id', '') is distinct from p_bot
     and coalesce(x ->> 'phoneNumber', '') is distinct from p_bot
$$;

-- ולכל אחד מהם יש לפחות אחד מהמפתחות (נתוני כסף בקבוצה, §3).
create or replace function app.wa_participants_hold(p_participants jsonb, p_bot text, p_keys text[])
returns boolean language sql stable security definer set search_path = public as $$
  with holders as (
    select distinct h as profile_id
      from unnest(coalesce(p_keys, '{}'::text[])) k
      cross join lateral app.profiles_with(k) h
  )
  select coalesce(bool_and(exists (
           select 1 from wa_links l
             join holders h on h.profile_id = l.profile_id
            where l.revoked_at is null
              and l.wa_id in (x ->> 'id', x ->> 'phoneNumber', x ->> 'lid'))), false)
    from jsonb_array_elements(coalesce(p_participants, '[]'::jsonb)) x
   where coalesce(x ->> 'id', '') is distinct from p_bot
     and coalesce(x ->> 'phoneNumber', '') is distinct from p_bot
$$;

-- ===== 4. הקישור ===========================================================

-- קוד בן שש ספרות לעשר דקות. קוד חדש מחליף את הקודם של אותו אדם.
create or replace function wa_link_code_create()
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_me   uuid := app.profile_id();
  v_code text;
  v_exp  timestamptz := now() + interval '10 minutes';
begin
  perform app.require('assistant.whatsapp', 'אין לך הרשאה לעוזר הוואטסאפ');
  if v_me is null then
    raise exception 'לא מחובר' using errcode = '42501';
  end if;

  for i in 1..20 loop
    v_code := lpad(((('x' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 8))::bit(32)::bigint)
                     % 1000000)::text, 6, '0');
    -- קוד שמישהו אחר מחזיק עכשיו אינו ניתן פעמיים
    exit when not exists (select 1 from wa_link_codes
                           where code_hash = app.wa_code_hash(v_code)
                             and used_at is null and expires_at > now() and profile_id <> v_me);
  end loop;

  insert into wa_link_codes (profile_id, code_hash, expires_at, used_at, created_at)
  values (v_me, app.wa_code_hash(v_code), v_exp, null, now())
  on conflict (profile_id) do update
    set code_hash = excluded.code_hash, expires_at = excluded.expires_at,
        used_at = null, created_at = now();

  return jsonb_build_object(
    'code', v_code,
    'expires_at', v_exp,
    'bot', coalesce((select value from app_settings where key = 'whatsapp.bot'), '{}'::jsonb));
end $$;

-- הפדיון, מפונקציית הקצה (בלי auth.uid). מחזיר {ok, reason?, profile_id, full_name}.
create or replace function app.wa_link_redeem(p_code text, p_wa_id text, p_name text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_row  wa_link_codes;
  v_fail int;
begin
  if coalesce(p_wa_id, '') !~ '^[0-9]{5,20}@(c\.us|lid)$' then
    return jsonb_build_object('ok', false, 'reason', 'bad_sender');
  end if;

  select count(*) into v_fail from wa_link_attempts
   where wa_id = p_wa_id and not ok and created_at > now() - interval '1 hour';
  if v_fail >= 5 then
    return jsonb_build_object('ok', false, 'reason', 'too_many');
  end if;

  select * into v_row from wa_link_codes
   where code_hash = app.wa_code_hash(p_code) and used_at is null and expires_at > now()
   order by created_at desc
   limit 1
   for update;
  if not found then
    insert into wa_link_attempts (wa_id, ok) values (p_wa_id, false);
    return jsonb_build_object('ok', false, 'reason', 'bad_code');
  end if;

  update wa_link_codes set used_at = now() where profile_id = v_row.profile_id;

  if not app.wa_allowed(v_row.profile_id) then
    insert into wa_link_attempts (wa_id, ok) values (p_wa_id, false);
    return jsonb_build_object('ok', false, 'reason', 'not_allowed');
  end if;

  -- המספר עובר לפרופיל הזה, והמספר הקודם של הפרופיל משתחרר
  update wa_links set revoked_at = now()
   where revoked_at is null and (wa_id = p_wa_id or profile_id = v_row.profile_id);
  insert into wa_links (profile_id, wa_id, display_name)
  values (v_row.profile_id, p_wa_id, left(nullif(btrim(p_name), ''), 100));
  insert into wa_link_attempts (wa_id, ok) values (p_wa_id, true);

  perform app.notify(v_row.profile_id, 'whatsapp_linked', 'וואטסאפ חובר לחשבון שלך',
    'המספר ' || app.wa_phone(p_wa_id) || ' מחובר עכשיו לעוזר הוואטסאפ בשמך. '
      || 'אם זה לא אתה — נתק אותו בעמוד ההתראות.',
    'profile', v_row.profile_id);

  return jsonb_build_object('ok', true, 'profile_id', v_row.profile_id,
    'full_name', (select full_name from profiles where id = v_row.profile_id));
end $$;

-- ניתוק: שלי, או של כל אחד בידי מנהל מערכת.
create or replace function wa_unlink(p_link_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  update wa_links set revoked_at = now(), revoked_by = app.profile_id()
   where id = p_link_id and revoked_at is null
     and (profile_id = app.profile_id() or coalesce(app.is_admin(), false));
  if not found then
    raise exception 'הקישור לא נמצא';
  end if;
end $$;

-- ===== 5. הצ'אטים ==========================================================

-- "הפעל כאן" בקבוצה, מפונקציית הקצה. רק מנהל מערכת מקושר ופעיל מחבר.
create or replace function app.wa_chat_bind(
  p_chat_id text, p_name text, p_is_group boolean, p_profile uuid,
  p_participants jsonb, p_bot text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_ok boolean;
begin
  if not exists (select 1 from profiles
                  where id = p_profile and is_admin and is_active and deleted_at is null)
     or not app.wa_allowed(p_profile) then
    raise exception 'רק מנהל מערכת מחבר קבוצה לעוזר' using errcode = '42501';
  end if;

  v_ok := not p_is_group or app.wa_participants_ok(p_participants, p_bot);

  insert into wa_chats (chat_id, is_group, name, active, bound_by, bound_at,
                        participants, participants_checked_at, participants_ok)
  values (p_chat_id, p_is_group, left(nullif(btrim(p_name), ''), 200), true, p_profile, now(),
          coalesce(p_participants, '[]'::jsonb), now(), v_ok)
  on conflict (chat_id) do update
    set is_group = excluded.is_group,
        name = coalesce(excluded.name, wa_chats.name),
        active = true, bound_by = excluded.bound_by, bound_at = now(),
        unbound_at = null, unbound_by = null,
        participants = excluded.participants,
        participants_checked_at = now(),
        participants_ok = excluded.participants_ok,
        blocked_notice_at = null;

  return jsonb_build_object('ok', true, 'participants_ok', v_ok);
end $$;

-- הבדיקה החוזרת (כל שעה, ובכל הודעה ממי שאינו מוכר). מחזיר אם מותר לענות.
create or replace function app.wa_chat_participants_set(p_chat_id text, p_participants jsonb, p_bot text)
returns boolean language plpgsql security definer set search_path = public as $$
declare v_ok boolean := app.wa_participants_ok(p_participants, p_bot);
begin
  update wa_chats
     set participants = coalesce(p_participants, '[]'::jsonb),
         participants_checked_at = now(),
         participants_ok = v_ok,
         blocked_notice_at = case when v_ok then null else blocked_notice_at end
   where chat_id = p_chat_id and is_group;
  return v_ok;
end $$;

-- צ'אט פרטי: נרשם בהודעה הראשונה של משתמש מקושר, כדי שתהיה לו חזקת עיבוד.
create or replace function app.wa_chat_dm(p_chat_id text, p_name text)
returns void language sql security definer set search_path = public as $$
  insert into wa_chats (chat_id, is_group, name, active, participants_ok)
  values (p_chat_id, false, left(nullif(btrim(p_name), ''), 200), true, true)
  on conflict (chat_id) do update
    set name = coalesce(excluded.name, wa_chats.name)
$$;

-- "כבה כאן" / ניתוק מהמסך: מנהלי מערכת.
create or replace function wa_chat_unbind(p_chat_id text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not coalesce(app.is_admin(), false) then
    raise exception 'רק מנהל מערכת מנתק קבוצה' using errcode = '42501';
  end if;
  update wa_chats set active = false, unbound_at = now(), unbound_by = app.profile_id()
   where chat_id = p_chat_id and active and is_group;
  if not found then
    raise exception 'הקבוצה אינה מחוברת';
  end if;
end $$;

-- אותו ניתוק מתוך הקבוצה ("כבה כאן"), מפונקציית הקצה.
create or replace function app.wa_chat_unbind(p_chat_id text, p_profile uuid)
returns boolean language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from profiles
                  where id = p_profile and is_admin and is_active and deleted_at is null) then
    raise exception 'רק מנהל מערכת מנתק קבוצה' using errcode = '42501';
  end if;
  update wa_chats set active = false, unbound_at = now(), unbound_by = p_profile
   where chat_id = p_chat_id and active and is_group;
  return found;
end $$;

-- ===== 6. ההתראה על קישור ==================================================

select app.register_notification_type('whatsapp_linked', 'וואטסאפ חובר לחשבון',
  'מספר וואטסאפ חובר לעוזר הוואטסאפ בשמי — כדי שאדע אם זה לא הייתי אני',
  'חשבון', array['admin', 'staff'], 'profile', 'forced', 'opt_out', 'opt_in', 240);

update notification_types set required_permission = 'assistant.whatsapp'
 where key = 'whatsapp_linked';

-- ‏`app.notification_link` (אחרונה 0235, מועתקת במלואה): ההתראה מובילה לעמוד
-- ההתראות, שבו רואים את המספר המחובר ומנתקים אותו.
create or replace function app.notification_link(
  p_recipient uuid, p_type text, p_entity_type text, p_entity_id uuid)
returns text language plpgsql stable security definer set search_path = public as $$
declare v_date date; v_event uuid;
begin
  if p_type = 'whatsapp_linked' then
    return '/my/notifications';
  end if;

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

-- ===== 7. מספר הבוט ========================================================
-- נכתב בפונקציית הקצה מתוך instanceData.wid. אינו סוד: הוא מוצג במסך כדי
-- שהמשתמש יוכל לפתוח צ'אט פרטי עם הבוט.

insert into app_settings (key, value) values ('whatsapp.bot', '{}'::jsonb)
on conflict (key) do nothing;

-- ===== 8. הרשאות הרצה ======================================================

revoke execute on function wa_link_code_create() from anon, public;
revoke execute on function wa_unlink(uuid) from anon, public;
revoke execute on function wa_chat_unbind(text) from anon, public;
grant  execute on function wa_link_code_create() to authenticated;
grant  execute on function wa_unlink(uuid) to authenticated;
grant  execute on function wa_chat_unbind(text) to authenticated;

-- פנימיות: פונקציית הקצה בלבד
revoke execute on function app.wa_code_hash(text) from anon, authenticated, public;
revoke execute on function app.wa_phone(text) from anon, authenticated, public;
revoke execute on function app.wa_allowed(uuid) from anon, authenticated, public;
revoke execute on function app.wa_sender(text) from anon, authenticated, public;
revoke execute on function app.wa_participants_ok(jsonb, text) from anon, authenticated, public;
revoke execute on function app.wa_participants_hold(jsonb, text, text[]) from anon, authenticated, public;
revoke execute on function app.wa_link_redeem(text, text, text) from anon, authenticated, public;
revoke execute on function app.wa_chat_bind(text, text, boolean, uuid, jsonb, text) from anon, authenticated, public;
revoke execute on function app.wa_chat_participants_set(text, jsonb, text) from anon, authenticated, public;
revoke execute on function app.wa_chat_dm(text, text) from anon, authenticated, public;
revoke execute on function app.wa_chat_unbind(text, uuid) from anon, authenticated, public;
grant  execute on function app.wa_code_hash(text) to service_role;
grant  execute on function app.wa_phone(text) to service_role;
grant  execute on function app.wa_allowed(uuid) to service_role;
grant  execute on function app.wa_sender(text) to service_role;
grant  execute on function app.wa_participants_ok(jsonb, text) to service_role;
grant  execute on function app.wa_participants_hold(jsonb, text, text[]) to service_role;
grant  execute on function app.wa_link_redeem(text, text, text) to service_role;
grant  execute on function app.wa_chat_bind(text, text, boolean, uuid, jsonb, text) to service_role;
grant  execute on function app.wa_chat_participants_set(text, jsonb, text) to service_role;
grant  execute on function app.wa_chat_dm(text, text) to service_role;
grant  execute on function app.wa_chat_unbind(text, uuid) to service_role;
