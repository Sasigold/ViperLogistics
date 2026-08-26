-- 0117: פרסום הוא מתג, לא דלת חד-כיוונית
--
-- ‏0066 שמרה על הכיוון האחד: מעבר לסטטוס "משובץ" דורש `tasks.publish`, כי
-- זה הרגע שבו העובד רואה את המשימה, היא מופיעה בלוח המשמרות שלו והוא מקבל
-- עליה התראה (0063/0064). הכיוון ההפוך נשאר פתוח לרווחה — ומי שאינו רשאי
-- לפרסם יכול היה להוריד משימה מפרסום, לשלוח `task_unpublished` לכל הצוות
-- ולהעלים משמרת מ-`/my/schedule` של מי שכבר תכנן את יומו לפיה.
--
-- ההגדרה של "פרסום" לא השתנתה; מה שהשתנה הוא שהיא חלה על שני קצותיה. אותו
-- מפתח שומר על שניהם, מפני שזו אותה החלטה מהכיוון השני.
--
-- **על כל מי שאינו מחזיק את המפתח, ולא על הלקוח בלבד.** ‏`driver` ו-`team_lead`
-- נדחים מ-`tasks.publish` במפורש ב-0066, ורכז שיש לו `tasks.change_status`
-- בלי `tasks.publish` הוא בדיוק אותו מקרה. צמצום הכלל ל-`customer_user` היה
-- יוצר אי-סימטריה שנקראת כבאג ברגע שנתקלים בה: "אני יכול להוריד מפרסום אבל
-- לא להעלות". השאלה היא על המפתח, לא על הקהל — וזה בדיוק הנימוק שכתוב ב-0066
-- לכך שהשער יושב על הטבלה: היא צוואר הבקבוק שכל נתיבי הכתיבה עוברים בו,
-- ‏`TaskDrawer`, תא הלו״ז ו-`bulk_update_tasks` כאחד.
--
-- הגוף של 0066 מילה במילה, בתוספת הענף השני. ארבעת תנאי הדילוג נשמרים.

create or replace function app.enforce_task_publish()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_assigned uuid;
begin
  if auth.uid() is null then return new; end if;
  if app.in_system_write() then return new; end if;
  if app.is_admin() then return new; end if;

  select id into v_assigned from statuses
   where entity = 'task' and code = 'assigned' and deleted_at is null limit 1;

  if new.status_id = v_assigned
     and (tg_op = 'INSERT' or old.status_id is distinct from new.status_id) then
    perform app.require('tasks.publish', 'אין לך הרשאה לפרסם משימה (סטטוס "משובץ")');
  end if;

  -- ⟵ 0117: והירידה מ"משובץ" היא אותו מפתח
  if tg_op = 'UPDATE' and old.status_id = v_assigned
     and new.status_id is distinct from old.status_id then
    perform app.require('tasks.publish',
      'משימה משובצת יורדת מהסטטוס הזה רק בידי מי שרשאי לפרסם');
  end if;

  return new;
end $$;

comment on function app.enforce_task_publish() is
  'שער הפרסום (0066), לשני הכיוונים (0117): מי שאינו מחזיק tasks.publish '
  'אינו מעלה משימה ל"משובץ" ואינו מוריד אותה משם.';

-- הטריגר עצמו לא השתנה ואינו נוצר מחדש — `create or replace function` מספיק.
