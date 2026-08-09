-- 0049: משימות ביומן הפעילות של האירוע
--
-- ביומן (0016) נרשם מה שקורה לאירוע עצמו: הוא נוצר, שדה בו השתנה, מישהו
-- כתב הערה. מה שלא נרשם בו עד היום הוא הדבר שהאירוע בעצם מורכב ממנו —
-- המשימות. אירוע שיצא עם הקמה ופירוק וקיבל אחר כך עוד משימת פירוק בשעה
-- אחרת נראה ביומן בדיוק כמו אירוע שלא נגעו בו, וזו בדיוק השאלה שהרכז שואל
-- ("מי הוסיף את המשימה הזו, ומתי").
--
-- הרישום נעשה בטריגר על tasks ולא בקריאה מכל מסך שיוצר משימה, כי המשימות
-- נולדות בכמה נתיבים שונים — create_event יוצרת אוטומטית הקמה ופירוק,
-- add_event_task, שכפול משימה, ומסך המשימות עצמו. טריגר תופס את כולם, כולל
-- את אלה שייכתבו בעתיד.

-- ===== 1. שני סוגי רישום חדשים ============================================
-- הערכים נוספים כאן ונמצאים בשימוש רק בזמן ריצה (בתוך גוף פונקציה), ולכן
-- אין כאן ההגבלה של "ערך חדש אינו שמיש באותה טרנזקציה".

alter type event_activity_kind add value if not exists 'task_added';
alter type event_activity_kind add value if not exists 'task_removed';

-- ===== 2. איך משימה נקראת ביומן ===========================================
-- שם המשימה כפי שאדם היה מתאר אותה: הכותרת אם נכתבה, אחרת סוג המשימה, ואז
-- התאריך וכמות העובדים. השם נשמר כטקסט ברגע הרישום ולא נשלף בקריאה, מאותה
-- סיבה ש-0016 שומרת field_label: שינוי שם של סוג משימה לא אמור לשכתב את
-- ההיסטוריה.
create or replace function app.task_activity_text(
  p_task_type_id uuid, p_title text, p_task_date date, p_worker_count int)
returns text language sql stable security definer set search_path = public as $$
  select concat_ws(' · ',
    coalesce(nullif(btrim(coalesce(p_title, '')), ''),
             (select tt.name from task_types tt where tt.id = p_task_type_id),
             'משימה'),
    to_char(p_task_date, 'DD/MM/YYYY'),
    case when coalesce(p_worker_count, 0) > 0 then p_worker_count || ' עובדים' end)
$$;

-- ===== 3. הטריגר ==========================================================
-- הטקסט נכתב ל-note ולא ל-old_value/new_value במכוון: אלה שייכים לרישום
-- מסוג 'changed', שבו יש שדה שעבר מערך לערך. כאן אין שדה — יש משימה שנוספה
-- או ירדה — והיומן מציג את השורה כמשפט אחד.
--
-- מחיקה רכה (deleted_at) היא UPDATE, ולכן היא נבדקת כאן ולא ב-DELETE. מחיקה
-- קשה נתפסת בענף DELETE, לשלמות.
create or replace function app.log_task_event_activity()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_actor uuid := app.profile_id();
  v_name  text;
begin
  select full_name into v_name from profiles where id = v_actor;

  if tg_op = 'INSERT' then
    if new.event_id is not null and new.deleted_at is null then
      insert into event_activity (event_id, kind, actor_profile_id, actor_name, note)
      values (new.event_id, 'task_added', v_actor, v_name,
              'נוספה משימה: ' || app.task_activity_text(
                new.task_type_id, new.title, new.task_date, new.worker_count));
    end if;
    return new;
  end if;

  if tg_op = 'DELETE' then
    if old.event_id is not null and old.deleted_at is null then
      insert into event_activity (event_id, kind, actor_profile_id, actor_name, note)
      values (old.event_id, 'task_removed', v_actor, v_name,
              'הוסרה משימה: ' || app.task_activity_text(
                old.task_type_id, old.title, old.task_date, old.worker_count));
    end if;
    return old;
  end if;

  -- העברה בין אירועים: יורדת מהיומן של הישן ונכנסת ליומן של החדש
  if new.event_id is distinct from old.event_id then
    if old.event_id is not null and old.deleted_at is null then
      insert into event_activity (event_id, kind, actor_profile_id, actor_name, note)
      values (old.event_id, 'task_removed', v_actor, v_name,
              'הוסרה משימה: ' || app.task_activity_text(
                old.task_type_id, old.title, old.task_date, old.worker_count));
    end if;
    if new.event_id is not null and new.deleted_at is null then
      insert into event_activity (event_id, kind, actor_profile_id, actor_name, note)
      values (new.event_id, 'task_added', v_actor, v_name,
              'נוספה משימה: ' || app.task_activity_text(
                new.task_type_id, new.title, new.task_date, new.worker_count));
    end if;
    return new;
  end if;

  if new.event_id is not null
     and (old.deleted_at is null) is distinct from (new.deleted_at is null) then
    insert into event_activity (event_id, kind, actor_profile_id, actor_name, note)
    values (new.event_id,
            (case when new.deleted_at is null then 'task_added' else 'task_removed' end)::event_activity_kind,
            v_actor, v_name,
            case when new.deleted_at is null then 'שוחזרה משימה: ' else 'הוסרה משימה: ' end
              || app.task_activity_text(
                   new.task_type_id, new.title, new.task_date, new.worker_count));
  end if;

  return new;
end $$;

drop trigger if exists tasks_event_activity on tasks;
create trigger tasks_event_activity after insert or update or delete on tasks
  for each row execute function app.log_task_event_activity();
