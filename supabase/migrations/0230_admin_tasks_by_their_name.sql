-- 0230: משימות ניהול — שם רגיל לחדר המלחמה
--
-- בקשת הבעלים: "אל תקרא לזה חדר מלחמה אלא משהו יותר נורמלי."
--
-- הדף (0227) נקרא מעכשיו "משימות ניהול" בכל מקום שמשתמש רואה: המודול
-- והמפתח במטריצת ההרשאות, קבוצת ההתראות במסך ההעדפות, תיאור התראת השיבוץ,
-- וההודעה למי שאינו מנהל מערכת. השמות הפנימיים (`command`, `admin_missions`,
-- `app.require_war_room`) נשארים — אינם מוצגים לאיש.

-- ===== 1. המודול והמפתח =====================================================

select app.register_module('command', 'משימות ניהול',
  'המשימות של מנהלי המערכת — יעדים, תזכורות ומד איום', 'Siren', 5);

select app.register_permission('command.view', 'command', 'משימות ניהול',
  'המשימות של מנהלי המערכת. פתוח למנהלי מערכת בלבד — אין שכבה שמעניקה אותו לאחרים',
  'access', false, false, array[]::user_kind[], null, 10);

comment on table admin_missions is
  'משימות של מנהלי המערכת (0227) — "משימות ניהול". נכתבת רק דרך mission_*.';

-- ===== 2. ההודעה למי שאינו מנהל =============================================

create or replace function app.require_war_room()
returns void language plpgsql stable security definer set search_path = public as $$
begin
  if not coalesce(app.is_admin(), false) then
    raise exception 'משימות ניהול פתוחות למנהלי מערכת בלבד' using errcode = '42501';
  end if;
end $$;

revoke execute on function app.require_war_room() from anon, public;
grant  execute on function app.require_war_room() to authenticated;

-- ===== 3. ההתראות ===========================================================

select app.register_notification_type('mission_assigned', 'משימה שויכה אליי',
  'מנהל מערכת אחר שייך אליי משימת ניהול',
  'משימות ניהול', array['admin'], 'admin_mission', 'opt_out', 'off', 'opt_out', 300);
select app.register_notification_type('mission_daily_digest', 'בוקר 10:00: מה פתוח',
  'כל יום ב-10:00, כשיש לי משימות באיחור או להיום — כמה, וכמה זמן חוב הצטבר',
  'משימות ניהול', array['admin'], 'admin_mission', 'opt_out', 'off', 'opt_out', 303);
-- שני הסוגים שפרשו ב-0229 — אותה קבוצה, כדי שההיסטוריה לא תציג את השם הישן
update notification_types set group_he = 'משימות ניהול'
 where key in ('mission_due_soon', 'mission_overdue');
