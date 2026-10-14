-- 0232: משימות ניהול בשפה רגילה
--
-- בקשת הבעלים: "תוריד גם את ה-DEFCON ואת הטקסטים המאיימים, וגם את רצף
-- הימים. שיהיה ברמה של מערכת SaaS."
--
-- הדף עצמו (0227) כבר אינו מציג רמת איום, חוב, רצף, נקודות או דרגות — זה
-- שינוי בלקוח בלבד; השרת ממשיך לחשב אותם (`missions_board.defcon/debt_seconds`,
-- `missions_stats.streak/xp_*`, `admin_missions.points`) והם פשוט אינם מוצגים,
-- כך שגם דף פתוח מגרסה קודמת ממשיך לעבוד. כאן מתחלף רק מה שהמשתמש קורא
-- מהשרת:
--
--   1. סיכום הבוקר (0229) — בלי אימוג'י ובלי "הן לא שוכחות": "2 משימות באיחור
--      · משימה להיום", וגוף "הוותיקה שבהן באיחור של 4 ימים." במקום "סך החוב".
--   2. תיאור המודול במטריצת ההרשאות — בלי "מד איום".
--   3. תיאור סוג ההתראה — בלי "כמה זמן חוב הצטבר".

-- ===== 1. סיכום הבוקר =======================================================

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
           max(now() - m.due_at) filter (where m.due_at < now())          as oldest
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
        when r.overdue > 0 and r.today > 0 then
          case when r.overdue = 1 then 'משימה אחת באיחור' else r.overdue || ' משימות באיחור' end
          || ' · ' || r.today || ' להיום'
        when r.overdue = 1 then 'משימה אחת באיחור'
        when r.overdue > 0 then r.overdue || ' משימות באיחור'
        when r.today = 1 then 'משימה אחת להיום'
        else r.today || ' משימות להיום'
      end,
      case when r.overdue > 0
        then case when r.overdue = 1 then 'היא באיחור של ' else 'הוותיקה שבהן באיחור של ' end
             || app.mission_span(r.oldest) || '.'
        else 'היעד של המשימות האלה היום.'
      end,
      'admin_mission', null);
    v_n := v_n + 1;
  end loop;
  return v_n;
end $$;

revoke execute on function app.missions_digest(date) from anon, authenticated, public;

-- ===== 2. המודול ============================================================

select app.register_module('command', 'משימות ניהול',
  'המשימות של מנהלי המערכת: יעדים ותזכורות', 'ListChecks', 5);

-- ===== 3. סוג ההתראה ========================================================

select app.register_notification_type('mission_daily_digest', 'בוקר 10:00: מה פתוח',
  'כל יום ב-10:00, כשיש לי משימות באיחור או להיום',
  'משימות ניהול', array['admin'], 'admin_mission', 'opt_out', 'off', 'opt_out', 303);
