-- 0200: אירוע שבוטל או נמחק משחרר את מי שהיה משובץ אליו
--
-- ביטול אירוע (סטטוס "בוטל", 0036) ומחיקתו (soft_delete, 0123) הורידו אותו
-- מהלו״ז של המשרד — אבל לא נגעו במשימות שלו. משימה בסטטוס "משובץ" (0063)
-- נשארה משובצת, והסטטוס הזה הוא בדיוק מה שהעובד רואה לפיו: המשמרת נשארה
-- בלוח המשמרות שלו, השעון המשיך להיפתח לה, ואף אחד לא אמר לו שהאירוע ירד.
-- "משובץ" גבר על "בוטל".
--
-- מעכשיו, ברגע שאירוע עובר ל"בוטל" או נמחק, כל מי שמשובץ למשימה *משובצת*
-- שלו יורד ממנה ושומע על כך:
--
--   • סגל (task_assignments) — עובדים, נהגים וראש צוות;
--   • עובדי קבלן (task_contractor_workers);
--   • סגל הלקוח (task_customer_workers, 0133/0178);
--   • וההאצלה לקבלן (task_contractor_terms) — כמו במעבר לארקו (0135): בלי
--     זה מנהל הקבלן היה ממשיך לראות משימה ריקה ולשבץ אליה מחדש. האצלה
--     ששולמה נשארת — היא רישום כספי, ולא נמחק כזה בשקט.
--
-- ההודעה יוצאת מהפולטים הקיימים (0110) — אותו סוג, אותן העדפות ואותה תחולה —
-- ורק הכותרת אומרת למה: "האירוע בוטל — השיבוץ שלך בוטל". סגל הלקוח לא דיבר
-- עד היום בשום מסלול, ולכן הוא מדבר כאן, מהפונקציה עצמה.
--
-- מה *לא* משתחרר, ולמה:
--
--   • משימה שאינה "משובץ". טיוטה ו"מתוכנן" לא הגיעו לעובד מעולם (0063): אין
--     לו מה לראות ואין מה לבשר לו, והתכנון נשאר למקרה שהאירוע יחזור.
--   • משימה שעברה — ‏task_date לפני היום. מחיקת אירוע היא לא פעם ניקיון של
--     משהו שכבר קרה, והצוות שעבד בו הוא היסטוריה שהדוחות קוראים ממנה.
--   • משימה שכבר נפתחה עליה משמרת בשעון. מי שהחתים עליה עבד, והשיבוץ הוא מה
--     שמסביר את השעות שלו.
--
-- ביטול שהוחזר (או אירוע ששוחזר מהסל) אינו מחזיר את הצוות — המשרד משבץ מחדש,
-- וכל שיבוץ כזה על משימה משובצת כבר מודיע לבד (0110).

-- ===== 1. הכותרת יודעת למה ================================================
--
-- הדגל חי בטרנזקציה בלבד (set_config(..., true)), ורק לאורך המחיקות שלמטה.
-- כך שלושת הפולטים נשארים המקור היחיד להודעה, ומסלול אחר שמוחק שיבוץ —
-- הסרה ידנית, מעבר לארקו — ממשיך לדבר בנוסח הרגיל.

create or replace function app.crew_release_title(p_title text)
returns text language sql stable set search_path = public as $$
  select case when coalesce(current_setting('app.event_off', true), '') = 'on'
              then 'האירוע בוטל — ' || p_title
              else p_title end
$$;

comment on function app.crew_release_title(text) is
  'כותרת התראת הסרה: בזמן שאירוע משחרר את הצוות שלו (0200) היא נפתחת ב"האירוע בוטל".';

-- שלושת הפולטים — הגוף מ-0110 מילה במילה, והכותרת עוברת דרך הפונקציה.

create or replace function app.notify_assignment_removed()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_task tasks;
begin
  if not app.task_is_published(old.task_id) then return old; end if;
  select * into v_task from tasks where id = old.task_id and deleted_at is null;
  if not found then return old; end if;
  -- מי שהסיר את עצמו יודע שהסיר את עצמו
  if old.profile_id is not distinct from app.profile_id() then return old; end if;
  if not app.notification_in_scope('assignment_removed', 'worker', old.profile_id) then
    return old;
  end if;

  perform app.notify(old.profile_id, 'assignment_removed',
    app.crew_release_title('השיבוץ שלך בוטל'),
    app.task_notify_label(v_task) || ' בתאריך ' || to_char(v_task.task_date, 'DD/MM/YYYY'),
    'task', old.task_id);
  return old;
end $$;

create or replace function app.notify_contractor_worker_removed()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_task tasks; v_cw contractor_workers; v_profile uuid;
begin
  if not app.task_is_published(old.task_id) then return old; end if;
  select * into v_task from tasks where id = old.task_id and deleted_at is null;
  if not found then return old; end if;
  select * into v_cw from contractor_workers where id = old.contractor_worker_id;
  if v_cw.id is null then return old; end if;
  if not app.notification_in_scope('assignment_removed', 'contractor', v_cw.contractor_id) then
    return old;
  end if;

  select id into v_profile from profiles
   where contractor_worker_id = v_cw.id and is_active and deleted_at is null;
  if v_profile is not null and v_profile is distinct from app.profile_id() then
    perform app.notify(v_profile, 'assignment_removed',
      app.crew_release_title('השיבוץ שלך בוטל'),
      app.task_notify_label(v_task) || ' בתאריך ' || to_char(v_task.task_date, 'DD/MM/YYYY'),
      'task', old.task_id);
  end if;
  return old;
end $$;

create or replace function app.notify_contractor_undelegation()
returns trigger language plpgsql security definer set search_path = public as $$
declare r record; v_task tasks;
begin
  if not app.task_is_published(old.task_id) then return old; end if;
  select * into v_task from tasks where id = old.task_id and deleted_at is null;
  if not found then return old; end if;
  if not app.notification_in_scope('task_unpublished', 'contractor', old.contractor_id) then
    return old;
  end if;

  for r in select m.id from app.contractor_managers(old.contractor_id) as m(id)
    where m.id is distinct from app.profile_id()
  loop
    perform app.notify(r.id, 'task_unpublished',
      app.crew_release_title('המשימה הוסרה מהקבלן שלך'),
      app.task_notify_label(v_task) || ' בתאריך ' || to_char(v_task.task_date, 'DD/MM/YYYY'),
      'task', old.task_id);
  end loop;
  return old;
end $$;

-- ===== 2. השחרור ===========================================================
--
-- פונקציה נפרדת מהטריגר, כי אותו שחרור בדיוק רץ גם בסוף המיגרציה על
-- האירועים שכבר בוטלו או נמחקו לפניה.
--
-- הסדר הוא של 0135: סגל, עובדי קבלן ואז ההאצלה — ‏tcw_price_sync מחשב מחדש
-- את מחיר הקבלן על כל עובד שיורד, ועדיף שהשורה עוד תהיה שם כשהוא מחפש אותה.
-- ‏task_is_published נשאר אמת לאורך כל המחיקות — הסטטוס של המשימה לא זז —
-- ולכן הפולטים של 0110 מדברים כרגיל.

create or replace function app.release_event_crew(p_event_id uuid)
returns int language plpgsql security definer set search_path = public as $$
declare
  v_today date := (now() at time zone 'Asia/Jerusalem')::date;
  v_tasks uuid[];
  v_prev  text := current_setting('app.event_off', true);
  r       record;
begin
  select array_agg(t.id) into v_tasks
    from tasks t
    join statuses s on s.id = t.status_id
   where t.event_id = p_event_id
     and t.deleted_at is null
     and s.code = 'assigned'
     and (t.task_date is null or t.task_date >= v_today)
     and not exists (select 1 from attendance_entries ae
                      where ae.deleted_at is null and t.id = any(ae.task_ids));
  if v_tasks is null then return 0; end if;

  perform set_config('app.event_off', 'on', true);

  -- סגל הלקוח: לטבלה אין פולט משלה, ולכן ההודעה יוצאת מכאן — לפני שהשורות
  -- יורדות. אותו סוג, ותחולה לפי הלקוח, כמו עובד קבלן לפי הקבלן שלו.
  for r in
    select distinct t.id as task_id, pr.id as profile_id
      from task_customer_workers w
      join tasks t on t.id = w.task_id
      join profiles pr on pr.customer_worker_id = w.customer_worker_id
                      and pr.is_active and pr.deleted_at is null
     where w.task_id = any(v_tasks)
       and pr.id is distinct from app.profile_id()
       and app.notification_in_scope('assignment_removed', 'customer', t.customer_id)
  loop
    perform app.notify(r.profile_id, 'assignment_removed',
      app.crew_release_title('השיבוץ שלך בוטל'),
      (select app.task_notify_label(t) || ' בתאריך ' || to_char(t.task_date, 'DD/MM/YYYY')
         from tasks t where t.id = r.task_id),
      'task', r.task_id);
  end loop;

  delete from task_assignments        where task_id = any(v_tasks);
  delete from task_contractor_workers where task_id = any(v_tasks);
  delete from task_customer_workers   where task_id = any(v_tasks);
  delete from task_contractor_terms   where task_id = any(v_tasks) and paid_at is null;

  perform set_config('app.event_off', coalesce(v_prev, ''), true);
  return cardinality(v_tasks);
end $$;

comment on function app.release_event_crew(uuid) is
  'מוריד את כל מי שמשובץ למשימות המשובצות והעתידיות של אירוע, ומודיע להם '
  '(0200). משימה שכבר נפתחה עליה משמרת, והאצלה ששולמה, נשארות.';

-- כותבת ומוחקת בשם המערכת, ולכן אינה פתוחה לקריאה ישירה מאף תפקיד. הטריגר
-- קורא לה מתוך security definer, ושם ההרשאה היא של הבעלים.
revoke execute on function app.release_event_crew(uuid) from public, anon, authenticated;

-- ===== 3. הטריגר ===========================================================
--
-- ‏after ולא before: השחרור כותב לטבלאות אחרות, והוא צריך לראות את האירוע
-- כפי שנשמר. ‏of status_id, deleted_at: אלה שתי הדלתות — ‏update_event (ומסלולי
-- ViperFlow/ארקו שמבטלים דרכו) ו-soft_delete — וכל עדכון אחר של אירוע אינו
-- מעיר אותו.
--
-- מחיקה של אירוע שכבר בוטל: ‏events_delete_clears_cancelled (0123) מחזיר את
-- הסטטוס לברירת המחדל באותו UPDATE, ולכן הענף שמזהה כאן מחיקה אינו תלוי
-- בסטטוס. מה שכבר שוחרר בביטול אינו נמצא שוב, ומה ששובץ מאז — כן.

create or replace function app.event_off_releases_crew()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_cancelled uuid[];
begin
  select array_agg(id) into v_cancelled from statuses
   where entity = 'event' and code = 'cancelled';

  if (old.deleted_at is null and new.deleted_at is not null)
     or (new.deleted_at is null
         and coalesce(new.status_id = any(v_cancelled), false)
         and not coalesce(old.status_id = any(v_cancelled), false)) then
    perform app.release_event_crew(new.id);
  end if;
  return new;
end $$;

comment on function app.event_off_releases_crew() is
  'אירוע שעבר לבוטל או נמחק משחרר את הצוות של המשימות המשובצות שלו (0200).';

create trigger events_release_crew after update of status_id, deleted_at on events
  for each row execute function app.event_off_releases_crew();

-- ===== 4. מה שכבר בוטל ====================================================
--
-- אירועים שבוטלו או נמחקו לפני המיגרציה, ועדיין מחזיקים משימה משובצת עתידית
-- עם צוות — בדיוק המצב שהמיגרציה באה לסגור. אותם כללים בדיוק: משימה שעברה
-- או שנפתחה עליה משמרת נשארת כפי שהיא.

select app.release_event_crew(e.id)
  from events e
  left join statuses s on s.id = e.status_id
 where e.deleted_at is not null or s.code = 'cancelled';
