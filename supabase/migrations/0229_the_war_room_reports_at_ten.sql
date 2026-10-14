-- 0229: חדר המלחמה מדווח ב-10:00
--
-- בקשת הבעלים על 0227:
--
--   "תוריד את כל הקטע של ההישגים, ושיהיה תזכורת כל יום ב-10 בבוקר. לא צריך
--    כל רבע שעה. כל יום ב-10 בבוקר תריץ בדיקה, ואז תקפיץ את ההתראות."
--
-- ההכרעות:
--
--   1. **בלי הישגים.** `mission_complete` אינה מעניקה ואינה מחזירה הישגים,
--      ו-`missions_stats` אינה מחזירה אותם. נקודות, דרגות, רצף וגרפים —
--      נשארים. `app.mission_award` והטבלה `admin_achievements` אינם נמחקים
--      (כלי ה-MCP מחזיק כל DROP, ראו 0212) אלא משנים שם ל-`*_pre0229` ונסגרים —
--      בטוח למחוק ביד.
--
--   2. **סיכום אחד ביום, ב-10:00 שעון ישראל.** לכל מנהל שיש לו משימות באיחור
--      או שהיעד שלהן היום — התראה אחת ("🚨 3 באיחור · 2 להיום"), שפותחת את
--      חדר המלחמה (הבעלים בחר סיכום על פני התראה לכל משימה). "מחר היעד",
--      "שעה ליעד" ו"באיחור" לכל משימה פורשים (`is_active = false` — שורות
--      היסטוריות עדיין מצביעות עליהם). ההתראה על שיבוץ אצל מנהל אחר נשארת
--      מיידית (בחירת הבעלים).
--
--   3. **pg_cron במקום פונקציית קצה.** ההרחבה זמינה בפרויקט, כך שאין צורך
--      בסוד ובתזמון חיצוני; `mission-sweep` (שלא נפרסה) יוצאת מהריפו.
--      pg_cron עובד ב-UTC וישראל עוברת שעון: המשימה רצה ב-07:00 וב-08:00 UTC,
--      ו-`missions_sweep` שולחת רק משעה 10 בירושלים ופעם ביום לכל מנהל
--      (`admin_mission_digests`) — בקיץ 07:00 UTC הוא 10:00 וההרצה של 11:00
--      אינה שולחת שוב; בחורף 07:00 UTC הוא 09:00 ומדולגת.
--
--   4. **הדף אינו מריץ את הסריקה.** `missions_sweep` נסגרת ל-authenticated;
--      רק התזמון (ו-service_role) מריצים אותה. העבודה עצמה ב-
--      `app.missions_digest(day)` הפנימית, שהבדיקות קוראות לה ישירות.

-- ===== 1. בלי הישגים =======================================================

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

  -- ‏0228: מופע שנסגר, נפתח מחדש ונסגר שוב — המופע הבא כבר נולד בסגירה
  -- הראשונה (mission_reopen משאיר אותו), ולא נולד שני.
  if m.recurrence <> 'none'
     and not exists (select 1 from admin_missions c where c.previous_id = m.id and c.deleted_at is null) then
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

  return jsonb_build_object(
    'points', v_points,
    'on_time', now() <= m.due_at,
    'early', now() <= m.due_at - interval '24 hours',
    'xp_before', v_before,
    'xp_after', v_before + v_points,
    'next_id', v_next);
end $$;

revoke execute on function mission_complete(uuid) from anon, public;
grant  execute on function mission_complete(uuid) to authenticated;

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

alter function app.mission_award(uuid) rename to mission_award_pre0229;
revoke execute on function app.mission_award_pre0229(uuid) from anon, authenticated, public;

alter table admin_achievements rename to admin_achievements_pre0229;
revoke all on admin_achievements_pre0229 from anon, authenticated, public;

-- ===== 2. סוגי ההתראות =====================================================

update notification_types set is_active = false
 where key in ('mission_due_soon', 'mission_overdue');

select app.register_notification_type('mission_daily_digest', 'בוקר 10:00: מה פתוח',
  'כל יום ב-10:00, כשיש לי משימות באיחור או להיום — כמה, וכמה זמן חוב הצטבר',
  'חדר המלחמה', array['admin'], 'admin_mission', 'opt_out', 'off', 'opt_out', 303);

-- ===== 3. הסיכום ===========================================================

-- סיכום אחד למנהל ליום: מה באיחור, מה להיום, וכמה חוב. פנימית — התזמון קורא
-- לה דרך missions_sweep, והבדיקות ישירות.
create or replace function app.missions_digest(p_day date)
returns int language plpgsql security definer set search_path = public as $$
declare
  r     record;
  v_ok  boolean;
  v_n   int := 0;
  v_end timestamptz := app.mission_day_end(p_day);
begin
  for r in
    select m.owner_id,
           count(*) filter (where m.due_at < now())                    as overdue,
           count(*) filter (where m.due_at >= now() and m.due_at < v_end) as today,
           coalesce(sum(now() - m.due_at) filter (where m.due_at < now()), interval '0') as debt
      from admin_missions m
      join profiles p on p.id = m.owner_id and p.is_admin and p.is_active and p.deleted_at is null
     where m.deleted_at is null and m.status = 'open' and m.due_at < v_end
     group by m.owner_id
  loop
    insert into admin_mission_digests (profile_id, day) values (r.owner_id, p_day)
    on conflict do nothing returning true into v_ok;
    continue when v_ok is null;
    v_ok := null;
    perform app.notify(r.owner_id, 'mission_daily_digest',
      case
        when r.overdue > 0 and r.today > 0 then '🚨 ' || r.overdue || ' באיחור · ' || r.today || ' להיום'
        when r.overdue = 1 then '🚨 משימה אחת באיחור'
        when r.overdue > 0 then '🚨 ' || r.overdue || ' משימות באיחור'
        when r.today = 1 then '📋 משימה אחת להיום'
        else '📋 ' || r.today || ' משימות להיום'
      end,
      case when r.overdue > 0
        then 'סך החוב: ' || app.mission_span(r.debt) || '. הן לא שוכחות — גם אתה לא.'
        else 'היעד היום. סגור אותן לפני שהן מאדימות.'
      end,
      'admin_mission', null);
    v_n := v_n + 1;
  end loop;
  return v_n;
end $$;

revoke execute on function app.missions_digest(date) from anon, authenticated, public;

-- התזמון: משעה 10 בירושלים, פעם ביום לכל מנהל.
create or replace function missions_sweep()
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  perform pg_advisory_xact_lock(hashtextextended('missions_sweep', 0));
  if extract(hour from now() at time zone 'Asia/Jerusalem') < 10 then
    return jsonb_build_object('digests', 0, 'skipped', 'before 10:00');
  end if;
  return jsonb_build_object('digests', app.missions_digest(app.mission_today()));
end $$;

revoke execute on function missions_sweep() from anon, authenticated, public;
grant  execute on function missions_sweep() to service_role;

-- ===== 4. התזמון ===========================================================

do $$
begin
  create extension if not exists pg_cron;
  perform cron.schedule('war-room-10am', '0 7,8 * * *', 'select public.missions_sweep()');
exception when others then
  raise warning '0229: pg_cron אינו זמין (%) — הסיכום של 10:00 לא תוזמן. בפרויקט: Database → Extensions → pg_cron, ואז cron.schedule(''war-room-10am'', ''0 7,8 * * *'', ''select public.missions_sweep()'').', sqlerrm;
end $$;
