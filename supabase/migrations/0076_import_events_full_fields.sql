-- 0076: הקובץ המיובא נושא גם את הכסף, את התוספות ואת שאר שדות המשימה
--
-- 0052 הכניסה משימות לייבוא, אבל רק את שלד התכנון שלהן: סוג, שעות, כמות
-- עובדים, אופן ביצוע, משאית במלל, מיקום והערות. כל השאר — המחיר ללקוח, הקבלן
-- והמחיר שלו, מחסן היציאה, דריסות זמן הנסיעה וראש הצוות, ובאירוע עצמו
-- התוספות והספקים — נשארו מחוץ לקובץ. התוצאה היא בדיוק מה ש-0052 באה למנוע
-- בעצמה: אחרי ייבוא של חמישים אירועים עדיין נפתחת כל משימה ידנית, הפעם כדי
-- להקליד בה מחיר.
--
-- הקובץ כאן סוגר את הפער. ארבע החלטות:
--
--   1. **שמות נפתרים בשרת**, כמו סוג המשימה ואופן הביצוע ב-0052: מחסן, קבלן
--      וספק מגיעים מהקובץ כשם, והתרגום למזהה — כולל השאלה אם הספק בכלל שייך
--      ללקוח של האירוע — הוא כלל עסקי ומקומו כאן.
--   2. **מפתחות הכסף דורשים הרשאה משלהם, ומראש.** 0052 נמנעה במכוון מלדרוש
--      מפתחות שדה על שדות התכנון (אחרת "מותר לייבא אירועים" היה גורר בשקט את
--      tasks.reschedule ואת כל השאר), וזה נשאר. אבל המחיר ללקוח, המחיר לקבלן
--      וההאצלה אינם שדות תכנון: לכל אחד מהם מודול והרשאה משלו ו-RLS משלו
--      (0017, 0011), והייבוא לא יהיה הדלת האחורית אליהם. הבדיקה היא פר-קובץ
--      ולא פר-שורה, כמו בדיקת tasks.create של 0052 — מי שאין לו את המפתח
--      אמור לדעת את זה לפני שהמערכת יצרה חצי מהאירועים.
--   3. **מחיר שנכתב מהקובץ נכנס נעול** (is_manual), בדיוק כמו מחיר שהוקלד
--      בטופס האירוע (app.apply_event_task_block, 0017). בלי זה הטריגר
--      tasks_price — שיורה על אותו UPDATE שכתב את השעות — היה דורס מיד את
--      המספר שאדם כתב בקובץ.
--   4. **בוליאני הוא טקסט מתא באקסל.** app.import_bool מקבל 'כן'/'לא' לצד
--      true/false ו-1/0, וערך שאינו אחד מהם מפיל את השורה בהודעה שנוקבת בשם
--      העמודה — ולא ב-'invalid input syntax for type boolean'.
--
-- מה שלא נכנס לכאן במכוון: סטטוס אירוע וסטטוס משימה. לשניהם מחזור חיים משלהם
-- (0036, 0063) עם מעברים מותרים והרשאת פרסום, ועקיפה שלו דרך תא באקסל היא לא
-- שדה חסר אלא חור.

-- ===== 1. בוליאני מתא באקסל ================================================
-- מחזירה NULL לתא ריק — "לא נכתב" אינו "לא".

create or replace function app.import_bool(p_label text, p_raw text)
returns boolean language plpgsql immutable as $$
declare v text := lower(btrim(coalesce(p_raw, '')));
begin
  if v = '' then return null; end if;
  if v in ('כן', 'true', 't', 'yes', 'y', '1', 'v', '✓', 'ken') then return true; end if;
  if v in ('לא', 'false', 'f', 'no', 'n', '0', '-', 'lo') then return false; end if;
  raise exception 'ערך לא חוקי בעמודה "%": % — יש לכתוב כן או לא', p_label, btrim(p_raw);
end $$;

-- ===== 2. פתרון שמות לישויות של המשימה =====================================
-- אותה סלחנות של app.resolve_task_type (0052): רווחים ורישיות אינם מפילים תא
-- שאדם הקליד.

create or replace function app.resolve_warehouse(p_name text)
returns uuid language plpgsql stable security definer set search_path = public as $$
declare v_id uuid;
begin
  if nullif(btrim(coalesce(p_name, '')), '') is null then return null; end if;
  select id into v_id from warehouses
   where deleted_at is null and is_active
     and lower(btrim(name)) = lower(btrim(p_name))
   order by sort_order, id limit 1;
  if v_id is null then raise exception 'מחסן לא מוכר: %', btrim(p_name); end if;
  return v_id;
end $$;

create or replace function app.resolve_contractor(p_name text)
returns uuid language plpgsql stable security definer set search_path = public as $$
declare v_id uuid;
begin
  if nullif(btrim(coalesce(p_name, '')), '') is null then return null; end if;
  select id into v_id from contractors
   where deleted_at is null and is_active
     and lower(btrim(name)) = lower(btrim(p_name))
   order by name, id limit 1;
  if v_id is null then raise exception 'קבלן לא מוכר: %', btrim(p_name); end if;
  return v_id;
end $$;

-- ===== 3. שורת האירוע לפני create_event ====================================
-- create_event בונה רשימת עמודות מפורשת ומתעלמת בשקט ממפתח שאינו מוכר לה
-- (0015, 0053). לכן כל מה שהקובץ מוסיף חייב להיתרגם *כאן* למפתחות שהיא כן
-- מכירה: התוספות לבוליאנים, ועמודת "ספקים" למערך supplier_ids.
--
-- הספק שייך ללקוח (suppliers.customer_id, 0002), ולכן שם ספק של לקוח אחר הוא
-- שגיאה ולא התאמה שקטה. המפריד הוא פסיק או נקודה-פסיק, כי שני התווים מופיעים
-- באותה מידה בתא שנכתב ביד.

create or replace function app.normalize_import_event(p_row jsonb)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_out      jsonb := p_row - 'tasks' - 'row_key' - 'suppliers';
  v_customer uuid;
  v_ids      uuid[] := '{}';
  v_id       uuid;
  v_name     text;
  v_bool     boolean;
  k          text;
  v_labels   constant jsonb := jsonb_build_object(
    'no_parking', 'ללא חניה', 'porterage', 'סבלות', 'supplier_pickup', 'איסוף מספק');
begin
  foreach k in array array['no_parking', 'porterage', 'supplier_pickup'] loop
    if v_out ? k then
      v_bool := app.import_bool(v_labels ->> k, v_out ->> k);
      -- תא ריק אינו "לא": הוא נמחק מה-payload, ו-create_event תיקח את ברירת
      -- המחדל שלה במקום לכתוב false על תוספת שאיש לא נגע בה.
      v_out := case when v_bool is null then v_out - k
                    else jsonb_set(v_out, array[k], to_jsonb(v_bool)) end;
    end if;
  end loop;

  if nullif(btrim(coalesce(p_row ->> 'suppliers', '')), '') is not null then
    v_customer := coalesce(nullif(p_row ->> 'customer_id', '')::uuid, app.customer_id());
    for v_name in
      select btrim(x) from unnest(regexp_split_to_array(p_row ->> 'suppliers', '[,;]')) x
       where btrim(x) <> ''
    loop
      select s.id into v_id from suppliers s
       where s.customer_id = v_customer and s.deleted_at is null and s.is_active
         and lower(btrim(s.name)) = lower(v_name)
       order by s.name, s.id limit 1;
      if v_id is null then raise exception 'ספק לא מוכר אצל לקוח זה: %', v_name; end if;
      v_ids := v_ids || v_id;
    end loop;
    if cardinality(v_ids) > 0 then
      v_out := v_out || jsonb_build_object('supplier_ids', to_jsonb(v_ids));
    end if;
  end if;

  return v_out;
end $$;

-- ===== 4. המשימות של אירוע מיובא ===========================================
-- גוף 0052 במלואו, עם שש עמודות נוספות. שלוש נקודות ששומרות עליו:
--
--   • הדגל app.system_write מורם מחדש לפני *כל* כתיבה, ועכשיו יש סיבה שנייה
--     לכך מלבד זו של 0052: app.sync_contractor_terms (0057) — טריגר AFTER
--     UPDATE OF contractor_id — מרים את הדגל ומוריד אותו בסופו. ה-UPDATE
--     שמשייך קבלן מכבה אפוא את הדגל, וכתיבת המחירים שאחריו הייתה נשפטת מול
--     הרשאות השדה של המשתמש.
--   • המחירים נכתבים *אחרי* ה-UPDATE על tasks ולא לפניו, כי אותו UPDATE מפעיל
--     את tasks_price (0017) ואת sync_contractor_terms — הראשון היה דורס מחיר
--     ללקוח, והשני כותב את מחיר ברירת המחדל של הקבלן מעל מה שנכתב מהקובץ.
--   • "מחיר לקבלן" בלי קבלן אינו נכתב בשקט לשום מקום: אין שורת terms בלי
--     contractor_id (הטריגר הוא שיוצר אותה), ולכן זו שגיאה בשורה.

create or replace function app.apply_import_tasks(p_event_id uuid, p_tasks jsonb)
returns int language plpgsql security definer set search_path = public as $$
declare
  v_event      events;
  v_status     uuid;
  v_type       task_types;
  v_method     uuid;
  v_warehouse  uuid;
  v_contractor uuid;
  v_task_id    uuid;
  v_claimed    uuid[] := '{}';
  v_count      int := 0;
  v_price      numeric;
  v_has_terms  boolean;
  i            int := 0;
  t            jsonb;
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
      perform app.system_write(true);

      v_type       := app.resolve_task_type(t ->> 'task_type');
      v_warehouse  := app.resolve_warehouse(t ->> 'warehouse');
      v_contractor := app.resolve_contractor(t ->> 'contractor');

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
        warehouse_id         = coalesce(v_warehouse, warehouse_id),
        contractor_id        = coalesce(v_contractor, contractor_id),
        travel_hours         = coalesce((nullif(t ->> 'travel_hours', ''))::numeric, travel_hours),
        requires_team_lead   = coalesce(app.import_bool('נדרש ראש צוות', t ->> 'requires_team_lead'),
                                        requires_team_lead),
        truck_free_text      = coalesce(nullif(t ->> 'truck_free_text', ''), truck_free_text),
        location_text        = coalesce(nullif(t ->> 'location_text', ''), location_text),
        notes                = coalesce(nullif(t ->> 'notes', ''), notes)
      where id = v_task_id;

      -- ===== הכסף, אחרי שכל הטריגרים של השורה למעלה סיימו =====
      v_price := (nullif(btrim(coalesce(t ->> 'contractor_price', '')), ''))::numeric;
      if v_price is not null then
        select exists (select 1 from task_contractor_terms where task_id = v_task_id)
          into v_has_terms;
        if not v_has_terms then
          raise exception 'מחיר לקבלן נכתב בלי קבלן — יש למלא גם את עמודת "קבלן"';
        end if;
        perform app.system_write(true);
        update task_contractor_terms set price = v_price where task_id = v_task_id;
      end if;

      v_price := (nullif(btrim(coalesce(t ->> 'price', '')), ''))::numeric;
      if v_price is not null then
        perform app.system_write(true);
        insert into task_pricing (task_id, price, is_manual, breakdown, calculated_at)
        values (v_task_id, v_price, true, null, now())
        on conflict (task_id) do update
          set price = excluded.price, is_manual = true, breakdown = null;
      end if;

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

-- ===== 5. הייבוא עצמו ======================================================
-- גוף 0052, עם בדיקות ההרשאה של הכסף ועם נרמול שורת האירוע.
--
-- app.require נקראת פעם אחת לקובץ ולא פעם לשורה: היא זורקת 42501, כלומר לא
-- שורת שגיאה אלא כישלון של הקריאה כולה, וזה הדבר הנכון — מי שאין לו את
-- המפתח לא אמור לגלות זאת אחרי שנוצרו לו שלושים אירועים בלי מחיר.

create or replace function app.import_tasks_have(p_rows jsonb, p_keys text[])
returns boolean language sql stable set search_path = public as $$
  select exists (
    select 1
      from jsonb_array_elements(p_rows) e
      cross join lateral jsonb_array_elements(
        case when jsonb_typeof(e.value -> 'tasks') = 'array'
             then e.value -> 'tasks' else '[]'::jsonb end) t
      cross join lateral unnest(p_keys) as k(key)
     where nullif(btrim(coalesce(t.value ->> k.key, '')), '') is not null)
$$;

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

  -- זמן נסיעה הוא דריסה של מנוע התמחור ורשום תחת pricing.edit (0017), ולכן
  -- הוא נוסע יחד עם המחיר ולא עם שדות התכנון.
  if app.import_tasks_have(p_rows, array['price', 'travel_hours']) then
    perform app.require('pricing.edit', 'אין לך הרשאה להזין מחיר ללקוח');
  end if;
  if app.import_tasks_have(p_rows, array['contractor']) then
    perform app.require('tasks.delegate', 'אין לך הרשאה להאציל משימות לקבלן');
  end if;
  if app.import_tasks_have(p_rows, array['contractor_price']) then
    perform app.require('contractors.edit_pricing', 'אין לך הרשאה לעדכן מחיר לקבלן');
  end if;

  for r in select * from jsonb_array_elements(p_rows) loop
    i := i + 1;
    begin
      v_event_id := create_event(app.normalize_import_event(r));
      v_tasks := v_tasks + app.apply_import_tasks(v_event_id, r -> 'tasks');
      v_ok := v_ok + 1;
    exception when others then
      v_errors := v_errors || jsonb_build_object('row', i, 'error', sqlerrm);
    end;
  end loop;

  return jsonb_build_object('imported', v_ok, 'tasks_imported', v_tasks, 'errors', v_errors);
end $$;

-- ===== 6. הרשאות ===========================================================
-- אותה הקפדה של 0052: schema app פתוח ל-authenticated (0010:35), והפונקציות
-- שכותבות מתחת ל-app.system_write נסגרות גם בפניו. הדרך היחידה אליהן היא דרך
-- bulk_import_events, שבודקת את חמשת המפתחות שלמעלה.

revoke execute on function app.import_bool(text, text)               from anon, authenticated, public;
revoke execute on function app.resolve_warehouse(text)               from anon, authenticated, public;
revoke execute on function app.resolve_contractor(text)              from anon, authenticated, public;
revoke execute on function app.normalize_import_event(jsonb)         from anon, authenticated, public;
revoke execute on function app.import_tasks_have(jsonb, text[])      from anon, authenticated, public;
revoke execute on function app.apply_import_tasks(uuid, jsonb)       from anon, authenticated, public;
revoke execute on function bulk_import_events(jsonb)                 from anon, public;
