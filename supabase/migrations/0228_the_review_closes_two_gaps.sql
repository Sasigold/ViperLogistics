-- 0228: הסקירה סוגרת שני פערים ב-0227
--
-- ‏Codex על PR #44:
--
--   1. **מופע חוזר אחד לכל סגירה.** `mission_reopen` משאיר את המופע הבא
--      שנולד בסגירה הראשונה, ו-`mission_complete` הוליד עוד אחד בכל סגירה
--      חוזרת — פתיחה וסגירה שוב ושוב הכפילו את המשימה ואת התזכורות שלה.
--      עכשיו נולד מופע רק אם אין כבר מופע חי שהמשימה הזו היא הקודם שלו.
--
--   2. **משימה שבוצעה קפואה בניקוד שלה.** הנקודות וההישגים נקבעים בסגירה
--      לפי הבעלים, היעד והעדיפות. עריכה של משימה שבוצעה יכלה להעביר את ה-XP
--      למנהל אחר (וההישג נשאר אצל הראשון) או להזיז את היעד ולשנות בדיעבד את
--      אחוז "בזמן". עכשיו `mission_save` שומר את שלושתם כפי שהם על משימה
--      שבוצעה; שם, הערות וצעדים נשארים ניתנים לעריכה. למי שרוצה לשנות אותם —
--      "החזרה לפתוחות" קודם (שמבטלת את הנקודות). ובדרך: בעריכה, הבדיקה
--      "מנהל מערכת פעיל" חלה רק כשהבעלים *משתנה* — עריכת שם של משימה
--      ששייכת למנהל שכבר אינו פעיל אינה נכשלת עליו.
--
-- שני הגופים הועתקו במלואם מ-0227.

-- ===== 1. mission_save ======================================================

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

  if p_id is null then
    if not exists (select 1 from profiles where id = v_owner and is_admin and is_active and deleted_at is null) then
      raise exception 'אפשר לשייך משימה רק למנהל מערכת פעיל';
    end if;
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

    -- ‏0228: משימה שבוצעה — הנקודות וההישגים כבר נקבעו לפי הבעלים, היעד
    -- והעדיפות שלה; אלה נשארים. שם, הערות וצעדים — עדיין ניתנים לעריכה.
    if v_old.status = 'done' then
      v_owner := v_old.owner_id;
      v_due   := v_old.due_at;
      v_prio  := v_old.priority;
    end if;

    if v_owner is distinct from v_old.owner_id
       and not exists (select 1 from profiles where id = v_owner and is_admin and is_active and deleted_at is null) then
      raise exception 'אפשר לשייך משימה רק למנהל מערכת פעיל';
    end if;

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

-- ===== 2. mission_complete ==================================================

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
