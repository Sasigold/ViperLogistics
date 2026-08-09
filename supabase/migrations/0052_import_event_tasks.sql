-- 0052: ייבוא אירוע יחד עם המשימות שלו
--
-- ייבוא האקסל (0006, ומאז 0012) יוצר אירועים בלבד. הטריגר events_default_tasks
-- (0003) אמנם פותח לכל אירוע משימת הקמה ומשימת פירוק, אבל הן ריקות — בלי שעות,
-- בלי עובדים ובלי אופן ביצוע — וכל משימה שאינה אחת מהשתיים לא נוצרת כלל. בפועל
-- אחרי ייבוא של חמישים אירועים מחכות חמישים עריכות ידניות, וזה מה שמרוקן את
-- הייבוא מתוכן.
--
-- הקובץ כאן מוסיף לכל שורה בייבוא מערך 'tasks' אופציונלי. שלוש החלטות:
--
--   1. סוג המשימה ואופן הביצוע נפתרים *בשרת* לפי שם. הדפדפן יכול לתרגם שם לקוח
--      ל-uuid כי רשימת הלקוחות ממילא בזיכרון שלו, אבל טבלת ההצלבה של אופני
--      ביצוע מותרים (סוג משימה ∩ לקוח) היא כלל עסקי, ומקומו בצד שבודק אותו.
--      הבדיקה כאן היא בדיוק זו של app.apply_event_task_block (0009), כולל נוסח
--      השגיאה.
--   2. שורת "הקמה" או "פירוק" בקובץ *ממלאת* את המשימה שהטריגר כבר יצר במקום
--      להוסיף שנייה לצדה. בלי זה כל אירוע מיובא היה יוצא עם ארבע משימות, שתיים
--      מהן ריקות.
--   3. משימה שנפסלה מגלגלת לאחור את כל שורת האירוע. bulk_import_events כבר
--      עוטף כל שורה ב-begin/exception, כלומר בתת-טרנזקציה, והוספת המשימות
--      נכנסת לתוכה. אירוע חצי-מיובא — קיים במסד אבל בלי המשימות שנכתבו עבורו —
--      גרוע מאירוע שלא נכנס ומדווח בשורת שגיאה שאפשר לתקן ולהעלות שוב.

-- ===== 1. פתרון סוג משימה לפי שם ==========================================
-- ההתאמה סלחנית לרווחים ולאותיות גדולות, כי הערך מגיע מתא באקסל שאדם הקליד.
-- code נבדק גם הוא, כדי שקובץ שנכתב באנגלית ('setup') לא ייפול.

create or replace function app.resolve_task_type(p_name text)
returns task_types language plpgsql stable security definer set search_path = public as $$
declare v_type task_types;
begin
  if nullif(btrim(coalesce(p_name, '')), '') is null then
    raise exception 'חסר סוג משימה';
  end if;
  select * into v_type from task_types
   where is_active and deleted_at is null
     and (lower(btrim(name)) = lower(btrim(p_name))
          or lower(btrim(coalesce(code, ''))) = lower(btrim(p_name)))
   order by sort_order, id
   limit 1;
  if v_type.id is null then
    raise exception 'סוג משימה לא מוכר: %', btrim(p_name);
  end if;
  return v_type;
end $$;

-- ===== 2. כתיבת המשימות של אירוע מיובא ====================================
-- app.system_write מורם מאותה סיבה שמתועדת ב-0015: הטריגר ברמת העמודה על
-- tasks שופט כתיבה מול הרשאות השדה של המשתמש, ובלעדיו "מותר לייבא אירועים"
-- היה דורש בשקט גם tasks.reschedule, tasks.change_worker_count וכל השאר.
-- הרישום ביומן האירוע לא צריך כאן דבר: הטריגר על tasks מ-0049 תופס גם את
-- המשימות האלה.

create or replace function app.apply_import_tasks(p_event_id uuid, p_tasks jsonb)
returns int language plpgsql security definer set search_path = public as $$
declare
  v_event    events;
  v_status   uuid;
  v_type     task_types;
  v_method   uuid;
  v_task_id  uuid;
  v_claimed  uuid[] := '{}';
  v_count    int := 0;
  i          int := 0;
  t          jsonb;
begin
  if p_tasks is null or jsonb_typeof(p_tasks) <> 'array' or jsonb_array_length(p_tasks) = 0 then
    return 0;
  end if;

  select * into v_event from events where id = p_event_id;
  if v_event.id is null then raise exception 'אירוע לא נמצא'; end if;

  select id into v_status from statuses
   where entity = 'task' and is_default and deleted_at is null limit 1;

  for t in select * from jsonb_array_elements(p_tasks) loop
    i := i + 1;
    begin
      -- הדגל מורם מחדש לפני *כל* כתיבה ולא פעם אחת בראש הפונקציה, כי
      -- app.sync_contractor_terms — טריגר AFTER INSERT על tasks (0003:191,
      -- 0012:90) — מרים את הדגל ומוריד אותו בסופו. משימה שנוספה כשורה חדשה
      -- הייתה מכבה אותו, וה-UPDATE שאחריה נשפט מול הרשאות השדה של המשתמש
      -- ונופל על "אין לך הרשאה לשנות את השדה …".
      perform app.system_write(true);

      v_type := app.resolve_task_type(t ->> 'task_type');

      v_method := null;
      if nullif(t ->> 'execution_method', '') is not null then
        select m.id into v_method
        from execution_methods m
        join task_type_execution_methods ttm
          on ttm.execution_method_id = m.id and ttm.task_type_id = v_type.id
        join customer_execution_methods cem
          on cem.execution_method_id = m.id and cem.customer_id = v_event.customer_id
        where m.is_active and m.deleted_at is null
          and lower(btrim(m.name)) = lower(btrim(t ->> 'execution_method'))
        limit 1;
        if v_method is null then
          raise exception 'אופן הביצוע שנבחר אינו זמין עבור % אצל לקוח זה', v_type.name;
        end if;
      end if;

      -- הקמה/פירוק: ממלאים את המשימה שהטריגר כבר יצר, ורק אם היא עדיין פנויה.
      -- שורה שנייה מאותו סוג באותו קובץ היא משימה נוספת אמיתית ולכן נוצרת.
      v_task_id := null;
      if v_type.auto_create_on_event then
        select tk.id into v_task_id from tasks tk
         where tk.event_id = p_event_id and tk.task_type_id = v_type.id
           and tk.deleted_at is null and not (tk.id = any(v_claimed))
         order by tk.created_at, tk.id
         limit 1;
      end if;

      if v_task_id is null then
        insert into tasks (event_id, customer_id, task_type_id, task_date, status_id,
                           worker_count, created_by)
        values (p_event_id, v_event.customer_id, v_type.id,
                coalesce((nullif(t ->> 'task_date', ''))::date, v_event.event_date),
                v_status, 0, app.profile_id())
        returning id into v_task_id;
      end if;
      v_claimed := v_claimed || v_task_id;

      perform app.system_write(true);
      update tasks set
        title                = coalesce(nullif(t ->> 'title', ''), title),
        task_date            = coalesce((nullif(t ->> 'task_date', ''))::date, task_date),
        warehouse_start_time = coalesce((nullif(t ->> 'warehouse_start_time', ''))::time, warehouse_start_time),
        onsite_start_time    = coalesce((nullif(t ->> 'onsite_start_time', ''))::time, onsite_start_time),
        hours_count          = coalesce((nullif(t ->> 'hours_count', ''))::numeric, hours_count),
        worker_count         = coalesce((nullif(t ->> 'worker_count', ''))::int, worker_count),
        execution_method_id  = coalesce(v_method, execution_method_id),
        truck_free_text      = coalesce(nullif(t ->> 'truck_free_text', ''), truck_free_text),
        location_text        = coalesce(nullif(t ->> 'location_text', ''), location_text),
        notes                = coalesce(nullif(t ->> 'notes', ''), notes)
      where id = v_task_id;

      v_count := v_count + 1;
    exception when others then
      -- ה-raise מגלגל את תת-הטרנזקציה של שורת האירוע כולה, ואיתה גם
      -- set_config המקומי של app.system_write — אין כאן מה לכבות ידנית.
      -- הבלוק קיים רק כדי לומר *איזו* משימה נפלה.
      raise exception 'משימה %: %', i, sqlerrm;
    end;
  end loop;

  perform app.system_write(false);
  return v_count;
end $$;

-- ===== 3. הייבוא עצמו =====================================================
-- אותו גוף כמו ב-0012, עם שלוש תוספות: דרישת ההרשאה השנייה, קריאת המשימות,
-- וספירתן בערך המוחזר. מפתחות 'tasks' ו-'row_key' מוסרים לפני create_event
-- כדי שהיא תמשיך לראות בדיוק את מה שראתה עד היום (row_key הוא מזהה פנימי של
-- הקובץ ואין לו מקום במסד).

create or replace function bulk_import_events(p_rows jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  r jsonb; i int := 0; v_ok int := 0; v_tasks int := 0; v_errors jsonb := '[]';
  v_event_id uuid;
begin
  perform app.require('events.import', 'אין לך הרשאה לייבא אירועים');

  if exists (
    select 1 from jsonb_array_elements(p_rows) e
     where jsonb_typeof(e.value -> 'tasks') = 'array'
       and jsonb_array_length(e.value -> 'tasks') > 0)
  then
    perform app.require('tasks.create', 'אין לך הרשאה ליצור משימות');
  end if;

  for r in select * from jsonb_array_elements(p_rows) loop
    i := i + 1;
    begin
      v_event_id := create_event(r - 'tasks' - 'row_key');
      v_tasks := v_tasks + app.apply_import_tasks(v_event_id, r -> 'tasks');
      v_ok := v_ok + 1;
    exception when others then
      v_errors := v_errors || jsonb_build_object('row', i, 'error', sqlerrm);
    end;
  end loop;

  return jsonb_build_object('imported', v_ok, 'tasks_imported', v_tasks, 'errors', v_errors);
end $$;

-- ===== 4. הרשאות ==========================================================
-- app.apply_import_tasks כותבת ל-tasks מתחת ל-app.system_write, כלומר מעקפת
-- את השער ברמת העמודה. schema app פתוח ל-authenticated (0010:35), ולכן היא
-- נסגרת גם בפניו ולא רק בפני anon — אותה הקפדה כמו ב-0044:152. הדרך היחידה
-- להגיע אליה היא דרך bulk_import_events, שבודקת events.import ו-tasks.create.
--
-- ל-bulk_import_events עצמה יש כבר revoke ב-0008 וב-0012; create or replace
-- אינו מאפס grants, וה-revoke חוזר כאן רק כדי שהקובץ יעמוד בפני עצמו.

revoke execute on function app.resolve_task_type(text)          from anon, authenticated, public;
revoke execute on function app.apply_import_tasks(uuid, jsonb)  from anon, authenticated, public;
revoke execute on function bulk_import_events(jsonb)            from anon, public;
