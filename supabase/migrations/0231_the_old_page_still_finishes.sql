-- 0231: התשובה של mission_complete נשארת תואמת לדפים פתוחים
--
-- ‏Codex על PR #45: 0229 הוציאה את `achievements` מהתשובה של
-- `mission_complete`, אבל דפדפן שעדיין מחזיק את הגרסה הקודמת של הדף (טאב פתוח,
-- או ה-PWA המותקן עד שהוא מתעדכן) קורא `r.achievements.forEach(...)` אחרי
-- סיום — ובלי המפתח הסיום עצמו מצליח, והמסך זורק שגיאה. המפתח חוזר, תמיד
-- כמערך ריק; אין עוד הישגים. הגוף כולו מ-0229.

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
    -- ‏0231: תמיד ריק — דפדפן עם הגרסה הקודמת של הדף עדיין קורא את המפתח
    'achievements', '[]'::jsonb,
    'next_id', v_next);
end $$;

revoke execute on function mission_complete(uuid) from anon, public;
grant  execute on function mission_complete(uuid) to authenticated;
