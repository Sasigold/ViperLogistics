-- 0139: משימת ארקו סגורה גם בפני מנהל המערכת
--
-- ‏0135 סגרה את זרוע ה-staff ואת זרוע הקבלן ב-`tasks_select`, אבל
-- `app.is_admin()` יושב בראש הפוליסה ועוקף את שתיהן — ולכן מנהל המערכת המשיך
-- לראות את הכול. הדיווח מבקש את ההפך: **"כשמשימות מסומנות ביצוע ע"י ארקו,
-- רק ארקו יראו את הארוע ואת המשימות שלו. מנהל המערכת לא."**
--
-- זו הכרעה ולא באג, ולכן היא נכתבת בזרוע ה-admin עצמה ולא במקום אחר: מי
-- שמבצע את העבודה הוא מי שרואה אותה, והמחיר שלה 0 ממילא (0120) — אין לוייפר
-- מה לתכנן שם ואין לה מה לגבות.
--
-- **מה שנובע מכך, במפורש:**
--
--   * ההתראה על מעבר **לארקו** (0136) ממשיכה להגיע למנהלי המערכת, והקישור
--     שבה יוביל למשימה שלא תיפתח להם. זה מכוון: ההתראה היא הידיעה שהעבודה
--     עברה, לא דלת אליה. הכיוון ההפוך — ארקו ← וייפר — נפתח כרגיל, וזה גם
--     הכיוון שבו יש מה לעשות.
--   * ‏`set_task_performed_by` ו-`hard_delete` הן `security definer` וקוראות
--     את הטבלה ישירות, ולכן מנהל מערכת שיודע את המזהה עדיין יכול להחזיר
--     משימה לוייפר. מה שנסגר הוא הראייה במסכים, לא הברז האחרון.
--   * ומה שנפתח במקביל, ב-0140: את **עובדי הלקוח** מנהל המערכת כן משבץ —
--     על משימות הוייפר של אותו לקוח, שאותן הוא רואה.
--
-- שתי הפוליסות מועתקות מילה במילה (‏tasks מ-0135, events מ-0120), והשינוי
-- היחיד הוא התנאי שנוסף לזרוע הראשונה.

drop policy tasks_select on tasks;
create policy tasks_select on tasks for select to authenticated using (
  ((select app.is_admin()) and performed_by <> 'arko')
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

drop policy events_select on events;
create policy events_select on events for select to authenticated using (
  ((select app.is_admin()) and not (select app.event_all_tasks_arko(events.id)))
  or (deleted_at is null
    and ((select app.scope_ids('events', 'customers')) is null
         or customer_id = any((select app.scope_ids('events', 'customers'))::uuid[]))
    and ((select app.scope_ids('events', 'statuses')) is null
         or status_id = any((select app.scope_ids('events', 'statuses'))::uuid[]))
    and ((select app.scope_date_from('events')) is null
         or event_date >= (select app.scope_date_from('events')))
    and ((select app.scope_date_to('events')) is null
         or event_date <= (select app.scope_date_to('events')))
    and (not (select app.scope_own('events'))
         or (select app.on_event_as_staff(events.id))
         or (select app.event_on_my_contractor(events.id))
         or ((select app.user_kind()) <> 'staff'
             and created_by = (select app.profile_id())))
    and (
      ((select app.user_kind()) = 'staff' and ((select app.has('events.view'))
         or (select app.on_event_as_staff(events.id))
         or ((select app.has('portal.view'))
             and (select app.event_on_my_contractor(events.id))))
         and not (select app.event_all_tasks_arko(events.id)))
      or ((select app.user_kind()) = 'customer_user' and customer_id = (select app.customer_id()))
      or ((select app.contractor_id()) is not null and (
            ((select app.has('portal.view'))
             and (select app.event_on_my_contractor(events.id)))
            or (select app.on_event_as_contractor_worker(events.id))))
    )));
