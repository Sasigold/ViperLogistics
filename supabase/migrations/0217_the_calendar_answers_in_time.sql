-- 0217: לוח השנה עונה בזמן — "משובץ לאירוע" בלי לשאול הרשאות על כל שורה
--
-- התלונה: עובדים וקבלנים ראו בלוח השנה את כל האירועים, למרות שההיקף שלהם
-- הוא "רק מה שמשויך אליי". בדיקה במסד החי, בזהות כל אחד מהם: ה-RLS עונה
-- נכון — עובד רואה בדיוק את האירועים ששובץ אליהם. אבל השאילתה של לוח השנה
-- לקחה לעובד כזה **6.3 שניות** לחודש וחצי של אירועים.
--
-- ה-service worker (‏`src/sw.ts`) עונה על קריאות GET ל-Supabase ב-NetworkFirst
-- עם timeout של 4 שניות, ממטמון שנשמר לפי URL בלבד. מעבר ל-4 שניות הוא החזיר
-- את העותק השמור של אותו URL — וכשבאותו מכשיר נכנס קודם מנהל (או מי שבודק
-- "איך זה נראה אצל העובד"), העובד קיבל את לוח השנה המלא של המנהל. הצד של
-- ה-service worker מתוקן בקוד הלקוח (מטמון לפי משתמש, ניקוי ביציאה); כאן
-- מתוקנת האיטיות עצמה.
--
-- הסיבה: ‏`app.on_event_as_staff` (0082) שואלת `app.can_plan_tasks()` — שתי
-- קריאות ל-`app.has` — בתוך ה-exists, כלומר על כל שורת משימה ששויכה לקורא,
-- ובפוליסה היא נקראת על כל אירוע (~28ms לקריאה, ~56ms לאירוע). עכשיו
-- השאלה על ההרשאה נשאלת רק כשהקורא משובץ לאירוע במשימה שעדיין טיוטה —
-- התשובה זהה לזו של 0082: שיבוץ למשימה שפורסמה פותח תמיד; שיבוץ לטיוטה
-- פותח רק את מי שרשאי לתכנן; בלי שיבוץ — לא.

-- ===== 1. app.on_event_as_staff: ההרשאה נשאלת רק כשיש טיוטה =================

create or replace function app.on_event_as_staff(p_event_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select case
    when exists (
      select 1 from tasks t
      join task_assignments a on a.task_id = t.id
      where t.event_id = p_event_id and t.deleted_at is null
        and a.profile_id = app.profile_id()
        and t.status_id = (select s.id from statuses s
                            where s.entity = 'task' and s.code = 'assigned'
                              and s.deleted_at is null limit 1))
      then true
    -- מי שרשאי לתכנן רואה גם טיוטות: הוא זה שכותב אותן (0063 §4)
    when exists (
      select 1 from tasks t
      join task_assignments a on a.task_id = t.id
      where t.event_id = p_event_id and t.deleted_at is null
        and a.profile_id = app.profile_id())
      then app.can_plan_tasks()
    else false
  end
$$;

revoke execute on function app.on_event_as_staff(uuid) from anon, public;
grant execute on function app.on_event_as_staff(uuid) to authenticated;
