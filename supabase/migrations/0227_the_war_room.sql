-- 0227: חדר המלחמה — המשימות של מנהלי המערכת
--
-- בקשת הבעלים:
--
--   "דף שיהיה זמין רק למנהלי המערכת, כמו to do list אבל ברמה הכי גבוהה.
--    משימה כמו 'התקנת מצלמות במחסן' עם תאריך יעד, ואם הוא עובר — שתהפוך
--    לאדומה. גרף, תמריץ לסיים כמה שיותר. אם לא סיימתי — משהו מפחיד, שאבין
--    שיש לי הרבה לבצע. אם ביצעתי — משהו שיעודד. לשייך משימה למנהל מערכת,
--    ולסנן לפי שלי או של כולם. תזכורות, משימות שלא בוצעו בזמן."
--
-- ההכרעות:
--
--   1. **מנהלי מערכת בלבד, בלי שכבה שיכולה לפתוח לאחרים.** המפתח
--      `command.view` נרשם עם `applies_to` ריק: מאז 0214 `app.has` עונה "לא"
--      על מפתח שאינו חל על סוג המשתמש, בכל שכבה — ולמנהל מערכת "כן" לפני כל
--      בדיקה. כך המפתח הוא בדיוק "מנהל מערכת", והמטריצה אינה מציגה אותו לאף
--      סוג (אין מה להעניק). הטבלאות והפונקציות שואלות `app.is_admin()` ישירות.
--
--   2. **המשימות אינן משימות של אירוע.** `tasks` הן הקמה ופירוק עם צוות, שכר
--      ומחיר; משימה של מנהל ("התקנת מצלמות") היא שורה אחרת לגמרי —
--      `admin_missions`, עם בעלים (מנהל מערכת), תאריך יעד ושעה, עדיפות 1–4,
--      צ'קליסט (`admin_mission_steps`) וחזרה (יומית/שבועית/חודשית).
--
--   3. **השרת מחשב את כל המספרים.** נקודות (XP), רמת האיום (DEFCON), החוב
--      (כמה זמן איחור מצטבר), הרצף וההישגים — כאן, כדי שהמסך רק יציג. הנקודות
--      נקבעות ברגע הסיום ונשמרות על השורה (`points`):
--        בסיס לפי עדיפות (100/60/40/25) · ×1.5 לסיום 24 שעות ומעלה לפני היעד ·
--        באיחור: חצי מהבסיס, שנמוג עד 0 אחרי 72 שעות · −10 על כל דחייה · לא
--        פחות מ-0.
--
--   4. **דחייה נספרת.** הזזת היעד קדימה (עריכה או "נודניק") מעלה את
--      `postpone_count`, נרשמת ביומן, ומורידה נקודות בסיום. המסך מציג אותה.
--
--   5. **רמת האיום (`app.mission_defcon`), כלל אחד:**
--        1 — 4 משימות באיחור ומעלה, או משימה שבאיחור יותר משבוע
--        2 — 2–3 באיחור, או משימה שבאיחור יותר מ-48 שעות
--        3 — משימה אחת באיחור, או משימה שהיעד שלה בשעה הקרובה
--        4 — יש משימה שהיעד שלה היום (שעון ישראל)
--        5 — שליטה מלאה
--
--   6. **הרצף הוא ימים נקיים**: ימים רצופים, עד היום, שבסופם לא נשארה אף
--      משימה באיחור — מאז המשימה הראשונה. יום בלי משימות אינו שובר אותו;
--      יום שנגמר באיחור — כן.
--
--   7. **תזכורות דרך `app.notify`** (פעמון + Push): שיבוץ אצל מנהל אחר,
--      24 שעות ושעה לפני היעד, ברגע שהיעד עובר, ומכתב בוקר מרוכז (מ-08:00)
--      למי שיש לו משימות באיחור. `missions_sweep()` אידמפוטנטית — כל תזכורת
--      נרשמת ב-`admin_mission_reminders` לפי (משימה, סוג, יעד), כך שהזזת
--      היעד מקבלת תזכורות חדשות בלי למחוק דבר. אין pg_cron: הזרוע המתוזמנת
--      היא פונקציית הקצה `mission-sweep` (כמו `fleet-expiry-sweep`), והדף
--      עצמו מריץ את הסריקה כשמנהל פותח אותו.
--
--   8. **בלי `delete`.** הסרה רכה (`deleted_at`) גם למשימה וגם לצעד — כלל
--      0218 על כלי ה-MCP, וכלל 0225 על מחיקה מהדפדפן.

-- ===== 1. הרשאה ============================================================

select app.register_module('command', 'חדר המלחמה',
  'המשימות של מנהלי המערכת — יעדים, תזכורות ומד איום', 'Siren', 5);

select app.register_permission('command.view', 'command', 'חדר המלחמה',
  'המשימות של מנהלי המערכת. פתוח למנהלי מערכת בלבד — אין שכבה שמעניקה אותו לאחרים',
  'access', false, false, array[]::user_kind[], null, 10);

-- ===== 2. הטבלאות ==========================================================

create table admin_missions (
  id             uuid primary key default gen_random_uuid(),
  title          text not null check (length(btrim(title)) between 1 and 200),
  description    text,
  owner_id       uuid not null references profiles(id),
  created_by     uuid references profiles(id) on delete set null,
  due_at         timestamptz not null,
  -- 1 = הכי דחוף
  priority       smallint not null default 2 check (priority between 1 and 4),
  recurrence     text not null default 'none'
                 check (recurrence in ('none', 'daily', 'weekly', 'monthly')),
  -- המופע הקודם בסדרה חוזרת (null — הראשון, או משימה שאינה חוזרת)
  previous_id    uuid references admin_missions(id) on delete set null,
  status         text not null default 'open' check (status in ('open', 'done')),
  done_at        timestamptz,
  done_by        uuid references profiles(id) on delete set null,
  postpone_count int not null default 0,
  points         int not null default 0,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  deleted_at     timestamptz,
  deleted_by     uuid references profiles(id) on delete set null,
  constraint admin_missions_done check ((status = 'done') = (done_at is not null))
);

comment on table admin_missions is
  'משימות של מנהלי המערכת (0227) — "חדר המלחמה". נכתבת רק דרך mission_*.';

create index admin_missions_open_idx on admin_missions (owner_id, due_at)
  where deleted_at is null and status = 'open';
create index admin_missions_done_idx on admin_missions (owner_id, done_at)
  where deleted_at is null and status = 'done';

create trigger admin_missions_updated before update on admin_missions
  for each row execute function app.set_updated_at();

create table admin_mission_steps (
  id         uuid primary key default gen_random_uuid(),
  mission_id uuid not null references admin_missions(id) on delete cascade,
  title      text not null check (length(btrim(title)) between 1 and 200),
  sort       int not null default 0,
  done_at    timestamptz,
  deleted_at timestamptz
);
create index admin_mission_steps_mission_idx on admin_mission_steps (mission_id) where deleted_at is null;

-- היומן — ממנו נגזר "מה קרה" (נוצרה, שובצה, נדחתה, בוצעה, נפתחה מחדש, הוסרה)
create table admin_mission_log (
  id         bigint generated always as identity primary key,
  mission_id uuid not null references admin_missions(id) on delete cascade,
  actor_id   uuid references profiles(id) on delete set null,
  kind       text not null check (kind in
               ('created', 'assigned', 'postponed', 'done', 'reopened', 'removed')),
  old_due    timestamptz,
  new_due    timestamptz,
  at         timestamptz not null default now()
);
create index admin_mission_log_mission_idx on admin_mission_log (mission_id, at);

-- תזכורת שנשלחה, לפי היעד שהיה בתוקף — יעד שזז מקבל תזכורות חדשות
create table admin_mission_reminders (
  mission_id uuid not null references admin_missions(id) on delete cascade,
  kind       text not null check (kind in ('due_24h', 'due_1h', 'overdue')),
  due_at     timestamptz not null,
  sent_at    timestamptz not null default now(),
  primary key (mission_id, kind, due_at)
);

-- מכתב הבוקר: אחד למנהל ליום
create table admin_mission_digests (
  profile_id uuid not null references profiles(id) on delete cascade,
  day        date not null,
  sent_at    timestamptz not null default now(),
  primary key (profile_id, day)
);

create table admin_achievements (
  profile_id uuid not null references profiles(id) on delete cascade,
  key        text not null,
  earned_at  timestamptz not null default now(),
  primary key (profile_id, key)
);

alter table admin_missions          enable row level security;
alter table admin_mission_steps     enable row level security;
alter table admin_mission_log       enable row level security;
alter table admin_mission_reminders enable row level security;
alter table admin_mission_digests   enable row level security;
alter table admin_achievements      enable row level security;

revoke all on admin_missions, admin_mission_steps, admin_mission_log, admin_achievements
  from anon, public;
revoke insert, update, delete, truncate
  on admin_missions, admin_mission_steps, admin_mission_log, admin_achievements
  from authenticated;
grant select on admin_missions, admin_mission_steps, admin_mission_log, admin_achievements
  to authenticated;
-- רישומי התזכורות סגורים לגמרי: רק הסריקה (definer) נוגעת בהם
revoke all on admin_mission_reminders, admin_mission_digests from anon, authenticated, public;

-- קריאה בלבד, ולמנהלי מערכת בלבד; כל כתיבה דרך definer
create policy admin_missions_select on admin_missions for select to authenticated
  using (deleted_at is null and (select app.is_admin()));
create policy admin_mission_steps_select on admin_mission_steps for select to authenticated
  using (deleted_at is null and (select app.is_admin()));
create policy admin_mission_log_select on admin_mission_log for select to authenticated
  using ((select app.is_admin()));
create policy admin_achievements_select on admin_achievements for select to authenticated
  using ((select app.is_admin()));

-- ===== 3. עזרים ============================================================

create or replace function app.require_war_room()
returns void language plpgsql stable security definer set search_path = public as $$
begin
  if not coalesce(app.is_admin(), false) then
    raise exception 'חדר המלחמה פתוח למנהלי מערכת בלבד' using errcode = '42501';
  end if;
end $$;

revoke execute on function app.require_war_room() from anon, public;
grant  execute on function app.require_war_room() to authenticated;

-- נקודות לסיום (§3 בכותרת). טהורה — גם הבדיקות קוראות לה.
create or replace function app.mission_points(
  p_priority smallint, p_due timestamptz, p_done timestamptz, p_postponed int)
returns int language sql immutable set search_path = public as $$
  select greatest(0, (
    case
      when p_done <= p_due - interval '24 hours' then round(b * 1.5)
      when p_done <= p_due then b
      else round(b * 0.5 * greatest(0, 1 - extract(epoch from p_done - p_due) / (72 * 3600.0)))
    end
    - 10 * coalesce(p_postponed, 0))::int)
  from (select case p_priority when 1 then 100 when 2 then 60 when 3 then 40 else 25 end::numeric as b) x
$$;

revoke execute on function app.mission_points(smallint, timestamptz, timestamptz, int) from anon, public;
grant  execute on function app.mission_points(smallint, timestamptz, timestamptz, int) to authenticated;

-- היום הנוכחי בשעון ישראל, וסוף יום נתון כרגע מוחלט
create or replace function app.mission_today()
returns date language sql stable set search_path = public as $$
  select (now() at time zone 'Asia/Jerusalem')::date
$$;

create or replace function app.mission_day_end(p_day date)
returns timestamptz language sql stable set search_path = public as $$
  select ((p_day + 1)::timestamp at time zone 'Asia/Jerusalem')
$$;

revoke execute on function app.mission_today() from anon, public;
revoke execute on function app.mission_day_end(date) from anon, public;
grant  execute on function app.mission_today() to authenticated;
grant  execute on function app.mission_day_end(date) to authenticated;

-- רמת האיום (§5). p_owner null — של כולם. פנימית: הדף מקבל אותה מ-missions_board.
create or replace function app.mission_defcon(p_owner uuid)
returns int language sql stable security definer set search_path = public as $$
  with open as (
    select due_at from admin_missions
     where deleted_at is null and status = 'open'
       and (p_owner is null or owner_id = p_owner)
  ), s as (
    select count(*) filter (where due_at < now())               as overdue,
           min(due_at) filter (where due_at < now())            as oldest,
           count(*) filter (where due_at >= now()
                              and due_at < now() + interval '1 hour') as within_hour,
           count(*) filter (where due_at >= now()
                              and due_at < app.mission_day_end(app.mission_today())) as today
      from open
  )
  select case
    when overdue >= 4 or oldest < now() - interval '7 days'  then 1
    when overdue >= 2 or oldest < now() - interval '48 hours' then 2
    when overdue >= 1 or within_hour > 0                       then 3
    when today > 0                                             then 4
    else 5
  end from s
$$;

revoke execute on function app.mission_defcon(uuid) from anon, authenticated, public;

-- היום-יום: לכל יום בחלון — כמה בוצעו (ומהן בזמן), כמה נשארו פתוחות ובאיחור
-- בסוף היום, וכמה שעות איחור הצטברו. היום עצמו נמדד עד עכשיו. פנימית.
create or replace function app.mission_daily(p_owner uuid, p_days int)
returns table (day date, done int, on_time int, open int, overdue int, debt_hours numeric)
language sql stable security definer set search_path = public as $$
  with ms as (
    select * from admin_missions m
     where (p_owner is null or m.owner_id = p_owner)
  ), days as (
    select d::date as day, least(app.mission_day_end(d::date), now()) as cut
      from generate_series(app.mission_today() - (greatest(p_days, 1) - 1), app.mission_today(),
                           interval '1 day') d
  )
  select dd.day,
    (select count(*)::int from ms
      where ms.deleted_at is null and ms.status = 'done'
        and (ms.done_at at time zone 'Asia/Jerusalem')::date = dd.day),
    (select count(*)::int from ms
      where ms.deleted_at is null and ms.status = 'done' and ms.done_at <= ms.due_at
        and (ms.done_at at time zone 'Asia/Jerusalem')::date = dd.day),
    (select count(*)::int from ms
      where ms.created_at < dd.cut
        and (ms.deleted_at is null or ms.deleted_at >= dd.cut)
        and (ms.done_at is null or ms.done_at >= dd.cut)),
    (select count(*)::int from ms
      where ms.created_at < dd.cut
        and (ms.deleted_at is null or ms.deleted_at >= dd.cut)
        and (ms.done_at is null or ms.done_at >= dd.cut)
        and ms.due_at < dd.cut),
    (select coalesce(round(sum(extract(epoch from dd.cut - ms.due_at)) / 3600.0, 1), 0)
       from ms
      where ms.created_at < dd.cut
        and (ms.deleted_at is null or ms.deleted_at >= dd.cut)
        and (ms.done_at is null or ms.done_at >= dd.cut)
        and ms.due_at < dd.cut)
  from days dd
  order by dd.day
$$;

revoke execute on function app.mission_daily(uuid, int) from anon, authenticated, public;

-- הרצף (§6): ימים נקיים רצופים עד היום, והשיא — מאז המשימה הראשונה. פנימית.
create or replace function app.mission_streak(p_owner uuid, out current_streak int, out best_streak int)
language plpgsql stable security definer set search_path = public as $$
declare
  v_first date;
  v_run   int := 0;
  r       record;
begin
  current_streak := 0;
  best_streak := 0;
  select (min(created_at) at time zone 'Asia/Jerusalem')::date into v_first
    from admin_missions where (p_owner is null or owner_id = p_owner);
  if v_first is null then return; end if;

  for r in
    select d.day, d.overdue from app.mission_daily(p_owner, least(app.mission_today() - v_first + 1, 730)) d
     where d.day >= v_first order by d.day
  loop
    if r.overdue = 0 then
      v_run := v_run + 1;
      best_streak := greatest(best_streak, v_run);
    else
      v_run := 0;
    end if;
  end loop;
  current_streak := v_run;
end $$;

revoke execute on function app.mission_streak(uuid) from anon, authenticated, public;

-- ההישגים שהבעלים זכה בהם עכשיו — רק החדשים חוזרים. פנימית.
create or replace function app.mission_award(p_profile uuid)
returns text[] language plpgsql security definer set search_path = public as $$
declare
  v_done     int;
  v_on_time  int;
  v_early    int;
  v_open     int;
  v_best_day int;
  v_streak   int;
  v_clean20  boolean;
  v_keys     text[] := '{}';
  v_new      text[];
begin
  select count(*),
         count(*) filter (where done_at <= due_at),
         count(*) filter (where done_at <= due_at - interval '24 hours')
    into v_done, v_on_time, v_early
    from admin_missions
   where owner_id = p_profile and deleted_at is null and status = 'done';

  select count(*) into v_open from admin_missions
   where owner_id = p_profile and deleted_at is null and status = 'open';

  select coalesce(max(n), 0) into v_best_day from (
    select count(*) n from admin_missions
     where owner_id = p_profile and deleted_at is null and status = 'done'
     group by (done_at at time zone 'Asia/Jerusalem')::date) x;

  select count(*) = 20 and bool_and(postpone_count = 0) into v_clean20 from (
    select postpone_count from admin_missions
     where owner_id = p_profile and deleted_at is null and status = 'done'
     order by done_at desc limit 20) x;

  select current_streak into v_streak from app.mission_streak(p_profile);

  if v_done >= 1 then v_keys := array_append(v_keys, 'first_blood'); end if;
  if v_on_time >= 10 then v_keys := array_append(v_keys, 'on_time_10'); end if;
  if v_early >= 10 then v_keys := array_append(v_keys, 'early_bird_10'); end if;
  if v_best_day >= 5 then v_keys := array_append(v_keys, 'five_in_a_day'); end if;
  if v_open = 0 and v_done >= 3 then v_keys := array_append(v_keys, 'inbox_zero'); end if;
  if coalesce(v_clean20, false) then v_keys := array_append(v_keys, 'no_snooze_20'); end if;
  if v_streak >= 7 and v_done >= 1 then v_keys := array_append(v_keys, 'streak_7'); end if;
  if v_streak >= 30 and v_done >= 1 then v_keys := array_append(v_keys, 'streak_30'); end if;
  if v_done >= 100 then v_keys := array_append(v_keys, 'century'); end if;

  with ins as (
    insert into admin_achievements (profile_id, key)
    select p_profile, k from unnest(v_keys) k
    on conflict do nothing
    returning key
  ) select coalesce(array_agg(key), '{}') into v_new from ins;
  return v_new;
end $$;

revoke execute on function app.mission_award(uuid) from anon, authenticated, public;

-- ===== 4. כתיבה ============================================================

-- יצירה ועריכה. p: title, description, owner_id, due_at, priority, recurrence,
-- steps: [{id?, title, done}] — רשימת הצעדים המלאה (מה שחסר בה מוסר).
create or replace function mission_save(p_id uuid, p jsonb)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_me    uuid := app.profile_id();
  v_old   admin_missions;
  v_id    uuid;
  v_title text := btrim(coalesce(p ->> 'title', ''));
  v_owner uuid := coalesce(nullif(p ->> 'owner_id', '')::uuid, v_me);
  v_due   timestamptz := nullif(p ->> 'due_at', '')::timestamptz;
  v_prio  smallint := coalesce(nullif(p ->> 'priority', '')::smallint, 2);
  v_rec   text := coalesce(nullif(p ->> 'recurrence', ''), 'none');
  v_keep  uuid[] := '{}';
  s       jsonb;
  v_sid   uuid;
  v_i     int := 0;
begin
  perform app.require_war_room();

  if v_title = '' then raise exception 'למשימה צריך שם'; end if;
  if length(v_title) > 200 then raise exception 'שם המשימה ארוך מדי — עד 200 תווים'; end if;
  if v_due is null then raise exception 'למשימה צריך תאריך יעד'; end if;
  if v_prio not between 1 and 4 then raise exception 'עדיפות היא 1 עד 4'; end if;
  if v_rec not in ('none', 'daily', 'weekly', 'monthly') then raise exception 'חזרה לא מוכרת'; end if;
  if not exists (select 1 from profiles where id = v_owner and is_admin and is_active and deleted_at is null) then
    raise exception 'אפשר לשייך משימה רק למנהל מערכת פעיל';
  end if;

  if p_id is null then
    insert into admin_missions (title, description, owner_id, created_by, due_at, priority, recurrence)
    values (v_title, nullif(btrim(coalesce(p ->> 'description', '')), ''), v_owner, v_me, v_due, v_prio, v_rec)
    returning id into v_id;
    insert into admin_mission_log (mission_id, actor_id, kind, new_due) values (v_id, v_me, 'created', v_due);
    if v_owner is distinct from v_me then
      insert into admin_mission_log (mission_id, actor_id, kind) values (v_id, v_me, 'assigned');
    end if;
  else
    select * into v_old from admin_missions where id = p_id and deleted_at is null for update;
    if v_old.id is null then raise exception 'המשימה לא נמצאה'; end if;
    v_id := p_id;

    update admin_missions set
      title          = v_title,
      description    = nullif(btrim(coalesce(p ->> 'description', '')), ''),
      owner_id       = v_owner,
      due_at         = v_due,
      priority       = v_prio,
      recurrence     = v_rec,
      postpone_count = postpone_count + case when v_old.status = 'open' and v_due > v_old.due_at then 1 else 0 end
     where id = p_id;

    if v_old.status = 'open' and v_due > v_old.due_at then
      insert into admin_mission_log (mission_id, actor_id, kind, old_due, new_due)
      values (p_id, v_me, 'postponed', v_old.due_at, v_due);
    end if;
    if v_owner is distinct from v_old.owner_id then
      insert into admin_mission_log (mission_id, actor_id, kind) values (p_id, v_me, 'assigned');
    end if;
  end if;

  -- הצעדים: הרשימה שנשלחה היא הרשימה
  if jsonb_typeof(p -> 'steps') = 'array' then
    for s in select * from jsonb_array_elements(p -> 'steps') loop
      v_i := v_i + 1;
      continue when btrim(coalesce(s ->> 'title', '')) = '';
      v_sid := nullif(s ->> 'id', '')::uuid;
      if v_sid is not null and exists (
           select 1 from admin_mission_steps where id = v_sid and mission_id = v_id and deleted_at is null) then
        update admin_mission_steps set
          title   = left(btrim(s ->> 'title'), 200),
          sort    = v_i,
          done_at = case when coalesce((s ->> 'done')::boolean, false)
                         then coalesce(done_at, now()) end
         where id = v_sid;
      else
        insert into admin_mission_steps (mission_id, title, sort, done_at)
        values (v_id, left(btrim(s ->> 'title'), 200), v_i,
                case when coalesce((s ->> 'done')::boolean, false) then now() end)
        returning id into v_sid;
      end if;
      v_keep := v_keep || v_sid;
    end loop;
    update admin_mission_steps set deleted_at = now()
     where mission_id = v_id and deleted_at is null and not (id = any (v_keep));
  end if;

  if v_owner is distinct from v_me and (p_id is null or v_owner is distinct from v_old.owner_id) then
    perform app.notify(v_owner, 'mission_assigned', 'משימה חדשה בשבילך',
      coalesce((select full_name from profiles where id = v_me), 'מנהל') || ' שייך אליך: ' || v_title
        || ' · יעד ' || to_char(v_due at time zone 'Asia/Jerusalem', 'DD/MM HH24:MI'),
      'admin_mission', v_id);
  end if;

  return v_id;
end $$;

revoke execute on function mission_save(uuid, jsonb) from anon, public;
grant  execute on function mission_save(uuid, jsonb) to authenticated;

-- סיום: הנקודות נקבעות כאן, משימה חוזרת מולידה את הבאה, והישגים מוענקים.
create or replace function mission_complete(p_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_me     uuid := app.profile_id();
  m        admin_missions;
  v_points int;
  v_before int;
  v_next   uuid;
  v_due    timestamptz;
  v_step   interval;
  v_new    text[];
begin
  perform app.require_war_room();

  select * into m from admin_missions where id = p_id and deleted_at is null for update;
  if m.id is null then raise exception 'המשימה לא נמצאה'; end if;
  if m.status = 'done' then raise exception 'המשימה כבר בוצעה'; end if;

  select coalesce(sum(points), 0) into v_before from admin_missions
   where owner_id = m.owner_id and deleted_at is null and status = 'done';

  v_points := app.mission_points(m.priority, m.due_at, now(), m.postpone_count);

  update admin_missions set status = 'done', done_at = now(), done_by = v_me, points = v_points
   where id = p_id;
  update admin_mission_steps set done_at = now()
   where mission_id = p_id and deleted_at is null and done_at is null;
  insert into admin_mission_log (mission_id, actor_id, kind) values (p_id, v_me, 'done');

  if m.recurrence <> 'none' then
    v_step := case m.recurrence when 'daily' then interval '1 day'
                                when 'weekly' then interval '7 days'
                                else interval '1 month' end;
    v_due := m.due_at + v_step;
    while v_due <= now() loop v_due := v_due + v_step; end loop;

    insert into admin_missions (title, description, owner_id, created_by, due_at, priority, recurrence, previous_id)
    values (m.title, m.description, m.owner_id, v_me, v_due, m.priority, m.recurrence, m.id)
    returning id into v_next;
    insert into admin_mission_steps (mission_id, title, sort)
    select v_next, title, sort from admin_mission_steps where mission_id = p_id and deleted_at is null;
    insert into admin_mission_log (mission_id, actor_id, kind, new_due) values (v_next, v_me, 'created', v_due);
  end if;

  v_new := app.mission_award(m.owner_id);

  return jsonb_build_object(
    'points', v_points,
    'on_time', now() <= m.due_at,
    'early', now() <= m.due_at - interval '24 hours',
    'xp_before', v_before,
    'xp_after', v_before + v_points,
    'achievements', to_jsonb(v_new),
    'next_id', v_next);
end $$;

revoke execute on function mission_complete(uuid) from anon, public;
grant  execute on function mission_complete(uuid) to authenticated;

-- ביטול סיום: הנקודות חוזרות לאפס. מופע חוזר שכבר נולד — נשאר.
create or replace function mission_reopen(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform app.require_war_room();
  update admin_missions set status = 'open', done_at = null, done_by = null, points = 0
   where id = p_id and deleted_at is null and status = 'done';
  if not found then raise exception 'המשימה לא נמצאה או שאינה בוצעה'; end if;
  insert into admin_mission_log (mission_id, actor_id, kind) values (p_id, app.profile_id(), 'reopened');
end $$;

revoke execute on function mission_reopen(uuid) from anon, public;
grant  execute on function mission_reopen(uuid) to authenticated;

-- "נודניק": היעד זז מעכשיו (או מהיעד, אם הוא עוד לפנינו). נספר כדחייה.
create or replace function mission_snooze(p_id uuid, p_minutes int)
returns timestamptz language plpgsql security definer set search_path = public as $$
declare
  m     admin_missions;
  v_due timestamptz;
begin
  perform app.require_war_room();
  if p_minutes is null or p_minutes < 1 or p_minutes > 60 * 24 * 90 then
    raise exception 'דחייה בין דקה ל-90 יום';
  end if;
  select * into m from admin_missions where id = p_id and deleted_at is null and status = 'open' for update;
  if m.id is null then raise exception 'המשימה לא נמצאה או שכבר בוצעה'; end if;

  v_due := greatest(m.due_at, now()) + make_interval(mins => p_minutes);
  update admin_missions set due_at = v_due, postpone_count = postpone_count + 1 where id = p_id;
  insert into admin_mission_log (mission_id, actor_id, kind, old_due, new_due)
  values (p_id, app.profile_id(), 'postponed', m.due_at, v_due);
  return v_due;
end $$;

revoke execute on function mission_snooze(uuid, int) from anon, public;
grant  execute on function mission_snooze(uuid, int) to authenticated;

create or replace function mission_remove(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform app.require_war_room();
  update admin_missions set deleted_at = now(), deleted_by = app.profile_id()
   where id = p_id and deleted_at is null;
  if not found then raise exception 'המשימה לא נמצאה'; end if;
  insert into admin_mission_log (mission_id, actor_id, kind) values (p_id, app.profile_id(), 'removed');
end $$;

revoke execute on function mission_remove(uuid) from anon, public;
grant  execute on function mission_remove(uuid) to authenticated;

create or replace function mission_step_toggle(p_step_id uuid)
returns boolean language plpgsql security definer set search_path = public as $$
declare v_done boolean;
begin
  perform app.require_war_room();
  update admin_mission_steps s set done_at = case when s.done_at is null then now() end
   where s.id = p_step_id and s.deleted_at is null
     and exists (select 1 from admin_missions m where m.id = s.mission_id and m.deleted_at is null)
  returning done_at is not null into v_done;
  if v_done is null then raise exception 'הצעד לא נמצא'; end if;
  return v_done;
end $$;

revoke execute on function mission_step_toggle(uuid) from anon, public;
grant  execute on function mission_step_toggle(uuid) to authenticated;

-- ===== 5. קריאה ============================================================

-- הלוח: כל הפתוחות, ומה שבוצע ב-7 הימים האחרונים, עם מצב הרוח של הדף.
-- p_owner null — של כולם. `now` הוא שעון השרת: הספירה לאחור בדפדפן נמדדת ממנו.
create or replace function missions_board(p_owner uuid default null)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v jsonb;
begin
  perform app.require_war_room();

  select jsonb_build_object(
    'now', now(),
    'defcon', app.mission_defcon(p_owner),
    'overdue', (select count(*) from admin_missions
                 where deleted_at is null and status = 'open' and due_at < now()
                   and (p_owner is null or owner_id = p_owner)),
    'debt_seconds', (select coalesce(sum(extract(epoch from now() - due_at)), 0)::bigint
                       from admin_missions
                      where deleted_at is null and status = 'open' and due_at < now()
                        and (p_owner is null or owner_id = p_owner)),
    'admins', coalesce((select jsonb_agg(jsonb_build_object('id', p.id, 'full_name', p.full_name)
                                         order by p.full_name)
                          from profiles p
                         where p.is_admin and p.is_active and p.deleted_at is null), '[]'),
    'missions', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', m.id, 'title', m.title, 'description', m.description,
               'owner_id', m.owner_id, 'owner_name', o.full_name,
               'created_by', m.created_by, 'due_at', m.due_at, 'priority', m.priority,
               'recurrence', m.recurrence, 'status', m.status, 'done_at', m.done_at,
               'postpone_count', m.postpone_count, 'points', m.points, 'created_at', m.created_at,
               'steps', coalesce((
                  select jsonb_agg(jsonb_build_object('id', s.id, 'title', s.title,
                                                      'done', s.done_at is not null) order by s.sort, s.id)
                    from admin_mission_steps s
                   where s.mission_id = m.id and s.deleted_at is null), '[]'))
             order by m.status, m.due_at)
        from admin_missions m
        join profiles o on o.id = m.owner_id
       where m.deleted_at is null
         and (p_owner is null or m.owner_id = p_owner)
         and (m.status = 'open' or m.done_at > now() - interval '7 days')), '[]')
  ) into v;
  return v;
end $$;

revoke execute on function missions_board(uuid) from anon, public;
grant  execute on function missions_board(uuid) to authenticated;

-- הסטטיסטיקה: XP, רצף, אחוז בזמן, הישגים וסדרה יומית לגרפים.
-- p_owner null — של כולם (ההישגים — של מי ששואל).
create or replace function missions_stats(p_owner uuid default null, p_days int default 84)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_days   int := least(greatest(coalesce(p_days, 84), 7), 365);
  v_streak record;
  v        jsonb;
begin
  perform app.require_war_room();
  select * into v_streak from app.mission_streak(p_owner);

  with done as (
    select * from admin_missions
     where deleted_at is null and status = 'done' and (p_owner is null or owner_id = p_owner)
  )
  select jsonb_build_object(
    'xp_total', (select coalesce(sum(points), 0) from done),
    'xp_week', (select coalesce(sum(points), 0) from done where done_at > now() - interval '7 days'),
    'done_total', (select count(*) from done),
    'done_30', (select count(*) from done where done_at > now() - interval '30 days'),
    'on_time_30', (select count(*) from done where done_at > now() - interval '30 days' and done_at <= due_at),
    'early_total', (select count(*) from done where done_at <= due_at - interval '24 hours'),
    'streak', v_streak.current_streak,
    'best_streak', v_streak.best_streak,
    'achievements', coalesce((
       select jsonb_agg(jsonb_build_object('key', key, 'earned_at', earned_at) order by earned_at)
         from admin_achievements where profile_id = coalesce(p_owner, app.profile_id())), '[]'),
    'daily', coalesce((
       select jsonb_agg(jsonb_build_object('day', d.day, 'done', d.done, 'on_time', d.on_time,
                                           'open', d.open, 'overdue', d.overdue,
                                           'debt_hours', d.debt_hours) order by d.day)
         from app.mission_daily(p_owner, v_days) d), '[]')
  ) into v;
  return v;
end $$;

revoke execute on function missions_stats(uuid, int) from anon, public;
grant  execute on function missions_stats(uuid, int) to authenticated;

-- ===== 6. תזכורות ==========================================================

select app.register_notification_type('mission_assigned', 'משימה שויכה אליי',
  'מנהל מערכת אחר שייך אליי משימה בחדר המלחמה',
  'חדר המלחמה', array['admin'], 'admin_mission', 'opt_out', 'off', 'opt_out', 300);
select app.register_notification_type('mission_due_soon', 'משימה מתקרבת ליעד',
  '24 שעות ושעה לפני היעד של משימה שלי',
  'חדר המלחמה', array['admin'], 'admin_mission', 'opt_out', 'off', 'opt_out', 301);
select app.register_notification_type('mission_overdue', 'משימה עברה את היעד',
  'ברגע שמשימה שלי עוברת את תאריך היעד',
  'חדר המלחמה', array['admin'], 'admin_mission', 'opt_out', 'off', 'opt_out', 302);
select app.register_notification_type('mission_daily_digest', 'בוקר: מה באיחור',
  'כל בוקר, כשיש לי משימות באיחור — כמה, וכמה זמן חוב הצטבר',
  'חדר המלחמה', array['admin'], 'admin_mission', 'opt_out', 'off', 'opt_out', 303);

-- גוף 0218, ועוד ענף אחד: התראה על משימה פותחת אותה בחדר המלחמה.
create or replace function app.notification_link(
  p_recipient uuid, p_type text, p_entity_type text, p_entity_id uuid)
returns text language plpgsql stable security definer set search_path = public as $$
declare v_date date;
begin
  if p_entity_type = 'admin_mission' then
    return '/command' || coalesce('?m=' || p_entity_id, '');
  end if;

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

  if p_entity_type = 'payslip' then
    return '/my/payslips';
  end if;

  return '/';
end $$;

-- משך קריא בעברית: "3 ימים ו-4 שעות", "5 שעות", "40 דקות"
create or replace function app.mission_span(p interval)
returns text language sql immutable set search_path = public as $$
  select case
    when s >= 86400 then (s / 86400)::int || ' ימים'
                          || case when (s % 86400) / 3600 >= 1
                                  then ' ו-' || ((s % 86400) / 3600)::int || ' שעות' else '' end
    when s >= 3600 then (s / 3600)::int || ' שעות'
    else greatest(1, (s / 60)::int) || ' דקות'
  end
  from (select greatest(0, floor(extract(epoch from p)))::bigint as s) x
$$;

revoke execute on function app.mission_span(interval) from anon, public;
grant  execute on function app.mission_span(interval) to authenticated;

-- הסריקה. בלי JWT — התזמון (service role); עם JWT — מנהל מערכת שפתח את הדף.
-- אידמפוטנטית: כל תזכורת נרשמת לפני שהיא נשלחת, ושתי הרצות במקביל ממתינות
-- זו לזו על נעילה מייעצת.
create or replace function missions_sweep()
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  r      record;
  v_sent int := 0;
  v_dig  int := 0;
  v_ok   boolean;
begin
  if auth.uid() is not null then
    perform app.require_war_room();
  end if;

  perform pg_advisory_xact_lock(hashtextextended('missions_sweep', 0));

  for r in
    select m.id, m.owner_id, m.title, m.due_at, k.kind
      from admin_missions m
      cross join (values ('due_24h', interval '24 hours'), ('due_1h', interval '1 hour')) k(kind, lead)
     where m.deleted_at is null and m.status = 'open'
       and m.due_at > now() and m.due_at <= now() + k.lead
       -- משימה שנוצרה כבר בתוך החלון אינה מקבלת "מתקרבת" מיד עם יצירתה
       and m.created_at <= m.due_at - k.lead
       -- ומי שמקבל "שעה" אינו מקבל באותה סריקה גם "24 שעות"
       and not (k.kind = 'due_24h' and m.due_at <= now() + interval '1 hour')
  loop
    insert into admin_mission_reminders (mission_id, kind, due_at) values (r.id, r.kind, r.due_at)
    on conflict do nothing returning true into v_ok;
    continue when v_ok is null;
    v_ok := null;
    perform app.notify(r.owner_id, 'mission_due_soon',
      case r.kind when 'due_1h' then '⏰ שעה ליעד' else '⏳ מחר היעד' end,
      r.title || ' · יעד ' || to_char(r.due_at at time zone 'Asia/Jerusalem', 'DD/MM HH24:MI')
        || ' · עוד ' || app.mission_span(r.due_at - now()),
      'admin_mission', r.id);
    v_sent := v_sent + 1;
  end loop;

  for r in
    select m.id, m.owner_id, m.title, m.due_at
      from admin_missions m
     where m.deleted_at is null and m.status = 'open' and m.due_at <= now()
  loop
    insert into admin_mission_reminders (mission_id, kind, due_at) values (r.id, 'overdue', r.due_at)
    on conflict do nothing returning true into v_ok;
    continue when v_ok is null;
    v_ok := null;
    perform app.notify(r.owner_id, 'mission_overdue', '⛔ באיחור: ' || r.title,
      'היעד עבר לפני ' || app.mission_span(now() - r.due_at) || '. כל שעה שעוברת נספרת.',
      'admin_mission', r.id);
    v_sent := v_sent + 1;
  end loop;

  -- מכתב הבוקר: מ-08:00 שעון ישראל, פעם ביום, למי שיש לו משימות באיחור
  if extract(hour from now() at time zone 'Asia/Jerusalem') >= 8 then
    for r in
      select m.owner_id, count(*) as n, sum(now() - m.due_at) as debt
        from admin_missions m
        join profiles p on p.id = m.owner_id and p.is_admin and p.is_active and p.deleted_at is null
       where m.deleted_at is null and m.status = 'open' and m.due_at < now()
       group by m.owner_id
    loop
      insert into admin_mission_digests (profile_id, day) values (r.owner_id, app.mission_today())
      on conflict do nothing returning true into v_ok;
      continue when v_ok is null;
      v_ok := null;
      perform app.notify(r.owner_id, 'mission_daily_digest',
        case when r.n = 1 then '🚨 משימה אחת באיחור' else '🚨 ' || r.n || ' משימות באיחור' end,
        'סך החוב: ' || app.mission_span(r.debt) || '. הן לא שוכחות — גם אתה לא.',
        'admin_mission', null);
      v_dig := v_dig + 1;
    end loop;
  end if;

  return jsonb_build_object('reminders', v_sent, 'digests', v_dig);
end $$;

revoke execute on function missions_sweep() from anon, public;
grant  execute on function missions_sweep() to service_role, authenticated;
