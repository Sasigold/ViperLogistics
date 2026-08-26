-- 0108: מי משבץ, מי רואה, וכמה זה עולה כשהקנס גדול מהמחיר
--
-- ארבעה דיווחים, שלוש הכרעות. שלושתן על אותה שאלה שחוזרת מאז 0075: המערכת
-- שואלת **מי אתה** (`user_kind`) במקום **למי אתה שייך** (`contractor_id`) —
-- ופעם אחת היא שואלת את המפתח הלא נכון לגמרי.
--
--   1. **עובד קבלן אינו משבץ.** ‏0091 §6ב כיבה את ברירת המחדל של הקהל על
--      `portal.assign_workers`, אבל `contractors.assign_workers` — המפתח
--      ה*משרדי*, "כל קבלן" — נשאר `true` לכל `contractor_user` מאז 0011.
--      ‏`contractor_assign_worker` מקבל כל אחד מהשניים, והוא `security definer`
--      ולכן הפוליסה על `task_contractor_workers` (שדורשת רק את הראשון) לא
--      עצרה אותו. התוצאה: חשבון של עובד קבלן בלי תפקיד שיבץ עובדים בלו״ז —
--      ולא רק של הקבלן שלו.
--   2. **הכובע הקבלני נשאל על העמודה.** דו-כובע (‏`staff` עם `contractor_id`,
--      ‏0075) לא ראה בלו״ז את המשימות שהואצלו לקבלן שלו, ולכן מסך הכספים שלו
--      החזיר אפסים: `contractor_dashboard` הוא `security invoker`, שורת
--      ה-terms נראית לו — ושורת ה-`tasks` שמעליה לא.
--   3. **קנס יכול לרדת מתחת לאפס.** ‏`greatest(0, …)` (0092) הפך קנס שגדול
--      מהמחיר ל"אפס", והמנהל ראה משימה שלא עלתה כלום במקום חוב.

-- ===== 1. עובד קבלן אינו משבץ ============================================
--
-- ‏`contractors.assign_workers` הוא המפתח שבו איש משרד משבץ סגל של קבלן זר
-- (‏`contractor_assign_worker`, הענף "היקף זר"), ואין לו מה לעשות בברירת
-- המחדל של קהל הקבלנים. ‏0075 §2 כבר הוריד אותו משני תפקידי הקבלן; מה שנשאר
-- הוא החשבון בלי תפקיד, שנפל חזרה לשכבת הקהל.
--
-- מנהל הקבלן אינו מאבד דבר: הוא משבץ דרך `portal.assign_workers`, שהוא מחזיק
-- כשורת תפקיד מפורשת (0104 §2), וכך גם העובד שמביא סגל (`staff_contractor`).
-- ‏`insert … on conflict do update` ולא `update`: השורה קיימת מ-0011, אבל
-- פרויקט שנזרע אחרת לא היה מקבל אותה כלל — ואז ה-`update` לא היה עושה דבר
-- והמפתח היה נשאר פתוח דרך שכבת ברירת המחדל של המפתח.
insert into kind_permission_defaults (user_kind, permission_key, allowed) values
  ('contractor_user', 'contractors.assign_workers', false)
on conflict (user_kind, permission_key) do update set allowed = false;

-- ובמפורש על התפקיד הצר, כדי ששני המפתחות יאמרו "לא" באותה שכבה ולא אחד
-- בשכבת התפקיד והשני בשכבת הקהל. ‏`upsert` ולא `set_role_permissions`, שמוחקת
-- את כל שורות התפקיד.
insert into role_permissions (role_id, permission_key, allowed)
select r.id, k, false
from permission_roles r,
     unnest(array['portal.assign_workers', 'contractors.assign_workers']) k
where r.key = 'contractor_worker'
on conflict (role_id, permission_key) do update set allowed = false;

-- ===== 2. הכובע הקבלני נשאל על העמודה, לא על סוג המשתמש ==================
--
-- שלוש נגיעות באותה פוליסה, כולן באותו כיוון:
--
--   * **זרוע הקבלן** (`user_kind = 'contractor_user'`) הופכת ל-
--     `app.contractor_id() is not null`. חשבון `contractor_user` תמיד נושא
--     ‏`contractor_id` (‏`profiles_contractor_kind`, 0001), ולכן זו הרחבה
--     לדו-כובע בלבד ולא שינוי לאף אחד אחר.
--   * **היקף `own`** — משימה שהואצלה לקבלן שלי היא "שלי" באותו מובן שבו
--     שיבוץ הוא שלי (0081). בלי זה הדו-כובע, שנושא גם תפקיד שטח עם היקף
--     ‏`own`, נחסם על המשימות של הקבלן שלו: זה מה שהחזיר אפסים בכספים.
--   * **שער הפרסום** (0082) — "צוות רואה רק מה שפורסם" נכתב על עובד שטח.
--     מנהל קבלן רואה את המשימה שהואצלה אליו בכל סטטוס; הדו-כובע, שהוא אותו
--     קבלן בדיוק, אינו אמור לראות פחות ממנו.
--
-- שאר הגוף זהה ל-0105.
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
      ((select app.user_kind()) = 'staff' and (select app.has('tasks.view')))
      or ((select app.user_kind()) = 'customer_user' and customer_id = (select app.customer_id()))
      or ((select app.contractor_id()) is not null
          and (select app.assignment_on_my_contractor(tasks.id))
          and ((select app.has('portal.view'))
               or (status_id = (select s.id from statuses s
                                 where s.entity = 'task' and s.code = 'assigned'
                                   and s.deleted_at is null limit 1)
                   and (select app.on_task_as_contractor_worker(tasks.id)))))
      or exists (select 1 from task_assignments a
                 where a.task_id = tasks.id and a.profile_id = (select app.profile_id()))
    )));

-- העוזר המקביל ל-`app.assignment_on_my_contractor` (0098) ברמת האירוע. עד כה
-- הוא נכתב בגוף הפוליסה כתת-שאילתה; כאן הוא נדרש בשלושה מקומות, והפונקציה
-- היא גם מה שמאפשר ל-`InitPlan` להריץ אותו פעם אחת.
create or replace function app.event_on_my_contractor(p_event_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select app.contractor_id() is not null
     and exists (select 1 from tasks t
                   join task_contractor_terms tct on tct.task_id = t.id
                  where t.event_id = p_event_id
                    and tct.contractor_id = app.contractor_id()
                    and t.deleted_at is null)
$$;

comment on function app.event_on_my_contractor(uuid) is
  'האם לאירוע יש משימה שהואצלה לקבלן של הקורא (0108). נשאל על העמודה '
  '`profiles.contractor_id` ולא על סוג המשתמש, ולכן הוא נכון גם לדו-כובע.';

-- אותה הכרעה על האירועים: הדו-כובע פותח את היומן ואת דף האירוע על מה
-- שהואצל לקבלן שלו. הגוף מ-0098 עם זרוע הקבלן וזרוע ההיקף מוחלפות.
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
    and (not (select app.scope_own('events'))
         or (select app.on_event_as_staff(events.id))
         or (select app.event_on_my_contractor(events.id))
         or ((select app.user_kind()) <> 'staff'
             and created_by = (select app.profile_id())))
    and (
      ((select app.user_kind()) = 'staff' and ((select app.has('events.view'))
         or (select app.on_event_as_staff(events.id))
         or ((select app.has('portal.view'))
             and (select app.event_on_my_contractor(events.id)))))
      or ((select app.user_kind()) = 'customer_user' and customer_id = (select app.customer_id()))
      or ((select app.contractor_id()) is not null and (
            ((select app.has('portal.view'))
             and (select app.event_on_my_contractor(events.id)))
            or (select app.on_event_as_contractor_worker(events.id))))
    )));

-- ===== 3. הקנס יורד מתחת לאפס ============================================
--
-- ‏`greatest(0, …)` הפך "הקבלן חייב לנו" ל"הקבלן לא מקבל כלום", ושתי הטענות
-- אינן אותו דבר: קנס אי-התייצבות של שני עובדים על משימה בת 300 ש״ח הוא חוב
-- שצריך להתקזז מול משימה אחרת, לא הנחה. מה שנשאר חסום הוא הריצפה בלבד —
-- הפירוט ב-`price_parts` לא השתנה, ולכן המנהל ממשיך לראות ממה מורכב המספר.
--
-- שאר הגוף זהה ל-0097.
create or replace function app.recompute_contractor_price(p_task_id uuid, p_contractor_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_ct        contractors%rowtype;
  v_terms     task_contractor_terms%rowtype;
  v_task      tasks%rowtype;
  v_count     int     := 0;
  v_base      numeric := 0;
  v_surcharge numeric := 0;
  v_late      int     := 0;
  v_noshow    int     := 0;
  v_price     numeric;
  v_rate      numeric;
  v_transport boolean;
  v_active    boolean;
  v_grace     int;
  v_prev      boolean;
begin
  select * into v_terms from task_contractor_terms
   where task_id = p_task_id and contractor_id = p_contractor_id;
  if v_terms.task_id is null then return; end if;
  if v_terms.paid_at is not null then return; end if;

  select * into v_ct from contractors where id = p_contractor_id;
  if v_ct.id is null then return; end if;

  select * into v_task from tasks where id = p_task_id;

  v_transport := exists (select 1 from execution_methods em
                          where em.id = v_task.execution_method_id and em.is_transport_only);

  v_rate := coalesce(v_terms.price_per_worker, v_ct.price_per_worker);

  v_active := v_rate is not null
           or (v_transport and v_ct.transport_only_price is not null)
           or v_ct.warehouse_arrival_surcharge is not null
           or v_ct.lateness_penalty is not null
           or v_ct.no_show_penalty is not null;
  if not v_active then return; end if;

  -- רק העובדים של הקבלן הזה במשימה.
  select count(*) into v_count
    from task_contractor_workers tcw
    join contractor_workers cw on cw.id = tcw.contractor_worker_id
   where tcw.task_id = p_task_id and cw.contractor_id = p_contractor_id;

  if v_transport and v_ct.transport_only_price is not null then
    v_base := v_ct.transport_only_price;
  elsif v_rate is not null then
    v_base := v_rate * v_count;
  else
    v_base := coalesce(v_ct.default_task_price, 0);
  end if;

  if not v_transport and v_terms.work_site = 'warehouse' then
    v_surcharge := coalesce(v_ct.warehouse_arrival_surcharge, 0) * v_count;
  end if;

  v_grace := coalesce(v_ct.lateness_grace_minutes, 0);
  select coalesce(count(*) filter (
      where x.lateness_tracked and x.clock_in_at is not null and x.shift_start is not null
        and x.clock_in_at > x.shift_start + make_interval(mins => v_grace)), 0)
    into v_late
    from (
      select cw.lateness_tracked, e.clock_in_at, e.shift_start
        from task_contractor_workers tcw
        join contractor_workers cw on cw.id = tcw.contractor_worker_id
        left join profiles p on p.contractor_worker_id = cw.id and p.deleted_at is null
        left join lateral (
          select ae.clock_in_at, ae.shift_start
            from attendance_entries ae
           where ae.profile_id = p.id and ae.deleted_at is null
             and ae.status <> 'rejected' and p_task_id = any(ae.task_ids)
           order by ae.clock_in_at limit 1
        ) e on true
       where tcw.task_id = p_task_id and cw.contractor_id = p_contractor_id
    ) x;

  select coalesce(count(*) filter (where tcw.no_show), 0) into v_noshow
    from task_contractor_workers tcw
    join contractor_workers cw on cw.id = tcw.contractor_worker_id
   where tcw.task_id = p_task_id and cw.contractor_id = p_contractor_id;

  /* בלי ריצפה: קנס שגדול מהמחיר הוא חוב, ומספר שלילי הוא הדרך היחידה
     להעביר אותו הלאה אל סיכום הכספים ואל דוח הרווחיות. */
  v_price := round(
    v_base + v_surcharge
    - coalesce(v_ct.lateness_penalty, 0) * v_late
    - coalesce(v_ct.no_show_penalty, 0) * v_noshow, 2);

  v_prev := app.in_system_write();
  perform app.system_write(true);
  update task_contractor_terms
     set price = v_price,
         price_parts = jsonb_build_object(
           'base', round(v_base, 2), 'surcharge', round(v_surcharge, 2),
           'worker_count', v_count, 'transport', v_transport,
           'late_count', v_late, 'late_penalty_each', coalesce(v_ct.lateness_penalty, 0),
           'noshow_count', v_noshow, 'noshow_penalty_each', coalesce(v_ct.no_show_penalty, 0),
           'penalty_total', round(coalesce(v_ct.lateness_penalty, 0) * v_late
                                  + coalesce(v_ct.no_show_penalty, 0) * v_noshow, 2))
   where task_id = p_task_id and contractor_id = p_contractor_id;
  perform app.system_write(v_prev);
end $$;

comment on function app.recompute_contractor_price(uuid, uuid) is
  'מחיר הקבלן: בסיס/הובלה/לפי-עובד + תוספת מחסן×עובדים − קנסות איחור (אוטומטי) '
  'ואי-התייצבות (ידני). ללא ריצפת אפס (0108) — קנס גדול מהמחיר נשאר חוב.';
