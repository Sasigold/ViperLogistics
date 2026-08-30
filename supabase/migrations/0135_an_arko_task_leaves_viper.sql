-- 0135: משימת ארקו נסגרת בפני וייפר — גם למי שכבר שובץ אליה
--
-- ‏0120 סינן `performed_by = 'arko'` בזרוע ה-staff של `tasks_select`, והשאירה
-- שתי פרצות שבשתיהן המשימה ממשיכה להיראות דווקא למי שהיה עליה:
--
--   1. **הזרוע האחרונה**, זו שנשענת על `task_assignments`, אינה שואלת על
--      `performed_by` כלל. רכז ששובץ למשימה לפני שהיא הועברה לארקו המשיך
--      לראות אותה, לפתוח אותה, ולקבל אותה בלוח המשמרות שלו.
--   2. **זרוע הקבלן** אינה שואלת אף היא. משימה שהואצלה לקבלן והועברה לארקו
--      נשארה גלויה לו — ולארקו אין דבר עם הקבלן של וייפר.
--
-- הכלל לאירוע אינו משתנה: הוא נעלם רק כשכל משימותיו החיות הן ארקו
-- (`app.event_all_tasks_arko`, 0120). אירוע מעורב נשאר גלוי לוייפר בזכות
-- המשימות שהיא עצמה מבצעת — וזה נכון: יש לה שם עבודה.
--
-- **והשיבוצים עצמם יורדים.** לסגור את הראייה ולהשאיר את השורה פירושו משמרת
-- יתומה: `app.planned_shifts` נגזרת מ-`task_assignments`, ולכן העובד המשיך
-- לראות ב-`/my/schedule` משמרת על משימה שאינו יכול לפתוח. הטריגר מוחק את
-- השיבוצים במעבר לארקו, והטריגר הקיים `task_assignments_notify_removed`
-- (0110) שולח לכל מי שהוסר `assignment_removed` — כלומר האנשים נודעים.
--
-- **חוץ ממה שכבר שולם עליו.** האצלה שסומנה כמשולמת אינה נמחקת ואינה מתעלמת:
-- המעבר עצמו נדחה, וקודם יש להסדיר את הכסף. אותו עיקרון של
-- `protect_paid_contractor_terms`.

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
    and (not (select app.scope_own('tasks'))
         or exists (select 1 from task_assignments a
                    where a.task_id = tasks.id and a.profile_id = (select app.profile_id()))
         or (select app.assignment_on_my_contractor(tasks.id))
         or ((select app.user_kind()) <> 'staff'
             and created_by = (select app.profile_id())))
    and ((select app.user_kind()) <> 'staff'
         or (select app.can_plan_tasks())
         or (created_by = (select app.profile_id())
             and not (select app.scope_own('tasks')))
         or ((select app.has('portal.view'))
             and (select app.assignment_on_my_contractor(tasks.id)))
         or status_id = (select s.id from statuses s
                          where s.entity = 'task' and s.code = 'assigned'
                            and s.deleted_at is null limit 1))
    and (
      ((select app.user_kind()) = 'staff' and (select app.has('tasks.view'))
          and performed_by <> 'arko')
      or ((select app.user_kind()) = 'customer_user' and customer_id = (select app.customer_id()))
      or ((select app.contractor_id()) is not null
          and performed_by <> 'arko'
          and (select app.assignment_on_my_contractor(tasks.id))
          and ((select app.has('portal.view'))
               or (status_id = (select s.id from statuses s
                                 where s.entity = 'task' and s.code = 'assigned'
                                   and s.deleted_at is null limit 1)
                   and (select app.on_task_as_contractor_worker(tasks.id)))))
      or (exists (select 1 from task_assignments a
                   where a.task_id = tasks.id and a.profile_id = (select app.profile_id()))
          and performed_by <> 'arko')
    )));

-- ===== המעבר לארקו מפנה את המשימה ========================================

create or replace function app.tasks_clear_crew_on_arko()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.performed_by <> 'arko' or old.performed_by = 'arko' then
    return new;
  end if;

  if exists (select 1 from task_contractor_terms
              where task_id = new.id and paid_at is not null) then
    raise exception 'לא ניתן להעביר לארקו משימה שההאצלה שלה כבר שולמה';
  end if;

  delete from task_assignments        where task_id = new.id;
  delete from task_contractor_workers where task_id = new.id;
  delete from task_contractor_terms   where task_id = new.id;

  return new;
end $$;

-- ‏`tasks.contractor_id` אינו נוגע כאן במכוון: מ-0096 הוא **שיקוף** של שורת
-- ההאצלה המוקדמת, ו-`mirror_task_contractor` מאפס אותו מעצמו כשהשורות יורדות.
-- כתיבה ישירה אליו היא בדיוק מה ש-0105 אסר.

comment on function app.tasks_clear_crew_on_arko() is
  'מעבר משימה לביצוע ארקו מפנה אותה מכל מי שכבר אינו רשאי לראותה (0135): '
  'שיבוצים פנימיים, סגל קבלן וההאצלה עצמה. האצלה ששולמה חוסמת את המעבר.';

create trigger tasks_clear_crew_on_arko after update of performed_by on tasks
  for each row execute function app.tasks_clear_crew_on_arko();
