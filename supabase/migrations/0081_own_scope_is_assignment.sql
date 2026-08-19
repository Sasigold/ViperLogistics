-- 0081: "שלי" של עובד שטח הוא מה ששובץ אליו, לא מה שהוא יצר
--
-- הדיווח: עובד רואה בלו״ז העבודה את כל המשימות של האירוע, ולא רק את זו
-- ששובץ אליה.
--
-- ההיקף 'own' נולד ב-0011 כ"מה שהוא משובץ אליו או יצר", ושתי הזרועות ישבו
-- מאז זו לצד זו בפוליסות הקריאה. לעובד לקוח הצירוף נכון: הוא יוצר אירועים
-- ("customers.allow_event_creation") והם שלו גם כשאיש עדיין לא שובץ. לעובד
-- שטח הזרוע השנייה היא דלת צדדית: חשבון שיצר משימות בגלגול קודם — ייבוא,
-- בדיקה, תפקיד שהוחלף — ממשיך לראות אותן לתמיד, כולל טיוטות שמעולם לא
-- פורסמו, ואיש אינו יכול לכבות את זה ממסך ההרשאות.
--
-- ההכרעה: למי שסוגו staff, ‏'own' פירושו שיבוץ ותו לא. מי שמתכנן — יצירת
-- משימה גוררת tasks.create, שכבר פותח את app.can_plan_tasks — ממילא אינו
-- חי מהזרוע הזו, ולתפקידי השטח (עובד, נהג, ראש צוות — היחידים שנושאים
-- 'own' כברירת מחדל) היא מעולם לא הייתה ההתנהגות המצופה. לסוגים האחרים
-- דבר אינו משתנה.
--
-- שתי הפוליסות משוכתבות מילה במילה מהגרסה הקודמת שלהן — tasks_select
-- מ-0066 §6 ו-events_select מ-0067 §3 — פרט לזרוע ה-scope_own שבכל אחת.

drop policy tasks_select on tasks;
create policy tasks_select on tasks for select to authenticated using (
  (select app.is_admin())
  or (deleted_at is null
    and ((select app.scope_ids('tasks', 'customers')) is null
         or customer_id = any((select app.scope_ids('tasks', 'customers'))::uuid[]))
    and ((select app.scope_ids('tasks', 'contractors')) is null
         or contractor_id = any((select app.scope_ids('tasks', 'contractors'))::uuid[]))
    and ((select app.scope_ids('tasks', 'task_types')) is null
         or task_type_id = any((select app.scope_ids('tasks', 'task_types'))::uuid[]))
    and ((select app.scope_ids('tasks', 'statuses')) is null
         or status_id = any((select app.scope_ids('tasks', 'statuses'))::uuid[]))
    and ((select app.scope_ids('tasks', 'execution_methods')) is null
         or execution_method_id = any((select app.scope_ids('tasks', 'execution_methods'))::uuid[]))
    and ((select app.scope_ids('tasks', 'trucks')) is null
         or truck_id = any((select app.scope_ids('tasks', 'trucks'))::uuid[]))
    and ((select app.scope_date_from('tasks')) is null
         or task_date >= (select app.scope_date_from('tasks')))
    and ((select app.scope_date_to('tasks')) is null
         or task_date <= (select app.scope_date_to('tasks')))
    -- ‏0081: לעובד שטח "שלי" הוא השיבוץ; היצירה נשארת זרוע רק למי שאינו staff
    and (not (select app.scope_own('tasks'))
         or exists (select 1 from task_assignments a
                    where a.task_id = tasks.id and a.profile_id = (select app.profile_id()))
         or ((select app.user_kind()) <> 'staff'
             and created_by = (select app.profile_id())))
    and ((select app.user_kind()) <> 'staff'
         or (select app.can_plan_tasks())
         or created_by = (select app.profile_id())
         or status_id = (select s.id from statuses s
                          where s.entity = 'task' and s.code = 'assigned'
                            and s.deleted_at is null limit 1))
    and (
      ((select app.user_kind()) = 'staff' and (select app.has('tasks.view')))
      or ((select app.user_kind()) = 'customer_user' and customer_id = (select app.customer_id()))
      or ((select app.user_kind()) = 'contractor_user'
          and contractor_id = (select app.contractor_id())
          and ((select app.has('portal.view'))
               or (status_id = (select s.id from statuses s
                                 where s.entity = 'task' and s.code = 'assigned'
                                   and s.deleted_at is null limit 1)
                   and (select app.on_task_as_contractor_worker(tasks.id)))))
      or exists (select 1 from task_assignments a
                 where a.task_id = tasks.id and a.profile_id = (select app.profile_id()))
    )));

-- אותה הכרעה על אירועים: העובד רואה אירוע כי הוא משובץ למשימה בתוכו, לא כי
-- החשבון שלו יצר אותו אי-פעם. בלי זה הלוח שלו היה ממשיך להציג אירועים שאין
-- לו בהם משימה — בעוד שמשימותיהם, אחרי השכתוב שלמעלה, כבר אינן מוצגות לו.
drop policy events_select on events;
create policy events_select on events for select to authenticated using (
  (select app.is_admin())
  or (deleted_at is null
    and ((select app.scope_ids('events', 'customers')) is null
         or customer_id = any((select app.scope_ids('events', 'customers'))::uuid[]))
    and ((select app.scope_ids('events', 'statuses')) is null
         or status_id = any((select app.scope_ids('events', 'statuses'))::uuid[]))
    and ((select app.scope_date_from('events')) is null
         or event_date >= (select app.scope_date_from('events')))
    and ((select app.scope_date_to('events')) is null
         or event_date <= (select app.scope_date_to('events')))
    -- ‏0081: כמו במשימות — שיבוץ, לא יצירה
    and (not (select app.scope_own('events'))
         or exists (select 1 from tasks t
                    where t.event_id = events.id and t.deleted_at is null
                      and exists (select 1 from task_assignments a
                                  where a.task_id = t.id and a.profile_id = (select app.profile_id())))
         or ((select app.user_kind()) <> 'staff'
             and created_by = (select app.profile_id())))
    and (
      ((select app.user_kind()) = 'staff' and ((select app.has('events.view'))
         or exists (select 1 from tasks t
                    join task_assignments a on a.task_id = t.id
                    where t.event_id = events.id and t.deleted_at is null
                      and a.profile_id = (select app.profile_id()))))
      or ((select app.user_kind()) = 'customer_user' and customer_id = (select app.customer_id()))
      or ((select app.user_kind()) = 'contractor_user' and (
            ((select app.has('portal.view')) and exists (
               select 1 from tasks t where t.event_id = events.id
                 and t.contractor_id = (select app.contractor_id()) and t.deleted_at is null))
            or (select app.on_event_as_contractor_worker(events.id))))
    )));
