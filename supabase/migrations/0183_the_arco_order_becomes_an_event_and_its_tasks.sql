-- 0183: ההזמנה של ארקו הופכת לאירוע, ולשתי המשימות שלו
--
-- ‏0182 הניחה את הצינור; כאן יושב התרגום. שתי המערכות מתארות את אותו ערב
-- ועונות על שתי שאלות שונות — "מה הלקוח הזמין" מול "מי נוסע ומתי" — ולכן
-- התרגום אינו העתקת שדות אלא הכרעה על **מי הבעלים של כל שדה**:
--
--   ‏ארקו היא הבעלים של: מספר ההזמנה, תאריך האירוע, המיקום, שם הלקוח
--   הסופי, כמות המשאיות, הנפח, תוספות התמחור (חניה/סבלות/איסוף ספק),
--   איש הקשר, ושעות ההקמה והפירוק על כמות העובדים שבהן. אלה עובדות
--   שנקבעות מול הלקוח הסופי, ואצלנו אין מי שיקבע אותן — הן **נדרסות**
--   בכל משלוח, וזו כל הנקודה.
--
--   אנחנו הבעלים של: השיבוץ, הקבלן, המחיר הידני, המשאית, סטטוס המשימה,
--   הערות הרכז, שעת היציאה מהמחסן וכל השדות המותאמים. אלה **אינם נגעים**
--   לעולם.
--
-- ארבע הכרעות שנגזרות מזה:
--
--   1. **חצות אינה שעה.** ‏Origami מייצא תאריך-בלבד כחותמת של חצות מקומית,
--      ואותה חותמת בדיוק היא גם "הקמה ב-00:00" חוקית. אי אפשר להבדיל,
--      ולכן חצות נקראת כ"תאריך בלי שעה": התאריך נכתב, והשעה נשארת כפי
--      שהיא. משימה שתיפתח ב-00:00 בלי שאיש התכוון לכך היא משאית שיוצאת
--      בלילה.
--
--   2. **שעת המחסן אינה שלהם.** ‏`warehouse_start_time` נגזרת אצלנו מכלל
--      ‏0163 ומהחלטת הרכז, וארקו אינה שולחת אותה בכלל. היא אינה נכתבת כאן
--      ואינה נמחקת כאן.
--
--   3. **הערה של רכז אינה נמחקת.** ‏`events.notes` מתמלא פעם אחת, בלידה.
--      משלוח חוזר אינו כותב על מה שאדם כתב.
--
--   4. **הסטטוס זז קדימה, ולא אחורה.** ביטול מבטל — תמיד. שאר הסטטוסים
--      נכתבים בלידה, ובעדכון הם מקדמים רק אירוע שעדיין על "טרם אושר".
--      אירוע שהמשרד כבר סימן "מתקיים" לא יחזור אחורה בגלל משלוח שהגיע
--      באיחור.
--
-- **והמחיר.** התרחיש של פתיחת ההזמנה מחזיר לארקו את מחיר המשימות. אין כאן
-- מחשבון חדש: המחיר הוא מה ש-`task_pricing` כבר מחזיקה — הטריגר של 0017
-- מחשב אותו בעצמו ברגע שהמשימה נכתבת, וכל מה שהפונקציה כאן עושה הוא
-- לקרוא. משימה שסומנה `performed_by = 'arko'` שווה 0 (0120), ומחיר שאדם
-- נעל ידנית מוחזר כפי שהוא ומסומן `is_manual`.

-- ===== 1. ארבע פונקציות עזר טהורות =======================================

-- מה-UTC של Origami לשעון הקיר של ישראל. הנימוק המלא ב-0177 §1.
create or replace function app.arco_local(p_iso text)
returns timestamp language plpgsql stable set search_path = public as $$
begin
  if coalesce(btrim(p_iso), '') = '' then return null; end if;
  return (p_iso::timestamptz) at time zone 'Asia/Jerusalem';
exception when others then
  return null;
end $$;

-- מספר ההזמנה, ספרות בלבד — אותו ניקוי שהתרחיש עושה היום לפני Firestore
-- (0182 §2). בלעדיו "26000233 " ו-"#26000233" היו שני אירועים.
create or replace function app.arco_order_number(p_raw text)
returns text language sql immutable set search_path = public as $$
  select nullif(regexp_replace(coalesce(p_raw, ''), '[^0-9]', '', 'g'), '')
$$;

-- סטטוס אירוע לפי שמו כפי שארקו שולחת אותו. שם שאינו מוכר אינו שגיאה
-- ואינו ברירת מחדל: הוא פשוט "לא נאמר", והסטטוס הקיים נשאר.
create or replace function app.arco_status_id(p_name text)
returns uuid language sql stable set search_path = public as $$
  select s.id from statuses s
   where s.entity = 'event' and s.deleted_at is null
     and btrim(s.name) = btrim(coalesce(p_name, ''))
   limit 1
$$;

-- אופן ביצוע לפי שמו. אותו כלל: לא מוכר ⇒ null ⇒ לא נגענו.
create or replace function app.arco_execution_method_id(p_name text)
returns uuid language sql stable set search_path = public as $$
  select m.id from execution_methods m
   where m.deleted_at is null and m.is_active
     and btrim(m.name) = btrim(coalesce(p_name, ''))
   limit 1
$$;

-- ===== 2. המשימה שההזמנה קובעת את שעתה ===================================
--
-- ממלאת את המשימה שהטריגר של 0003 כבר יצר בלידת האירוע, ויוצרת אותה רק אם
-- אינה קיימת — אותו סדר של `app.viperflow_apply_task` (0177 §3).
--
-- ‏`p_performer` הוא שם מבצע ההקמה/הפירוק כפי שארקו רשמה אותו. שתי מילים
-- בלבד מוכרות לנו: שם הלקוח של החיבור פירושו "הלקוח מבצע בעצמו"
-- (‏`performed_by = 'arko'`, ומחיר 0 לפי 0120), וכל שם אחר — ובהם "וייפר" —
-- נשאר `'viper'`. שם של קבלן אינו מתורגם לשיבוץ קבלן: ההאצלה היא שלנו.
create or replace function app.arco_apply_task(
  p_event     uuid,
  p_code      text,
  p_date      date,
  p_onsite    time,
  p_hours     numeric,
  p_workers   int,
  p_method    text,
  p_performer text,
  p_self_name text)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_type    task_types;
  v_event   events;
  v_task_id uuid;
  v_method  uuid := app.arco_execution_method_id(p_method);
  v_by      text;
  v_sys     boolean := app.in_system_write();
begin
  if p_date is null and p_onsite is null and p_hours is null
     and p_workers is null and v_method is null then
    return null;
  end if;

  select * into v_type from task_types
   where code = p_code and is_active and deleted_at is null;
  -- סוג משימה שכובה במסך ההגדרות אינו נוצר מחדש מהאינטגרציה.
  if v_type.id is null then return null; end if;

  select * into v_event from events where id = p_event;
  if v_event.id is null then raise exception 'אירוע לא נמצא'; end if;

  if coalesce(btrim(p_self_name), '') <> ''
     and btrim(coalesce(p_performer, '')) = btrim(p_self_name) then
    v_by := 'arko';
  end if;

  select t.id into v_task_id from tasks t
   where t.event_id = p_event and t.task_type_id = v_type.id and t.deleted_at is null
   order by t.created_at, t.id
   limit 1;

  -- הדגל מורם לפני *כל* כתיבה ולא פעם אחת בראש: הטריגרים על tasks מכבים
  -- אותו בסופם (0177 §3).
  perform app.system_write(true);

  if v_task_id is null then
    insert into tasks (event_id, customer_id, task_type_id, task_date, status_id,
                       worker_count, created_by)
    values (p_event, v_event.customer_id, v_type.id,
            coalesce(p_date, v_event.event_date),
            (select id from statuses where entity = 'task' and is_default and deleted_at is null limit 1),
            0, null)
    returning id into v_task_id;
  end if;

  perform app.system_write(true);
  update tasks set
    task_date           = coalesce(p_date, task_date),
    onsite_start_time   = coalesce(p_onsite, onsite_start_time),
    hours_count         = coalesce(p_hours, hours_count),
    worker_count        = coalesce(p_workers, worker_count),
    execution_method_id = coalesce(v_method, execution_method_id),
    performed_by        = coalesce(v_by, performed_by)
  where id = v_task_id;

  if not v_sys then perform app.system_write(false); end if;
  return v_task_id;
end $$;

-- ===== 3. ההזמנה עצמה ====================================================

/**
 * מתרגמת הזמנה אחת לאירוע אחד, ומחזירה `{status, event_id, reason}`.
 *
 * ‏`status`: 'created' | 'updated' | 'ignored'.
 */
create or replace function app.arco_apply_order(p_connection uuid, p_order jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  k            arco_connections;
  v_number     text := app.arco_order_number(p_order ->> 'order_number');
  v_event      events;
  v_event_id   uuid;
  v_created    boolean := false;
  v_status     uuid := app.arco_status_id(p_order ->> 'event_status');
  v_cancelled  uuid;
  v_default    uuid;
  v_event_ts   timestamp := app.arco_local(p_order ->> 'order_date');
  v_setup_ts   timestamp := app.arco_local(p_order ->> 'setup_date_and_time');
  v_teardown_ts timestamp := app.arco_local(p_order ->> 'dismantling_date_and_time');
  v_date       date;
  v_contact_n  text := nullif(btrim(p_order ->> 'operational_contact_name'), '');
  v_contact_p  text := nullif(btrim(p_order ->> 'operational_contact_phone'), '');
  v_sys        boolean := app.in_system_write();
begin
  select * into k from arco_connections where id = p_connection;
  if k.id is null then
    return jsonb_build_object('status', 'ignored', 'reason', 'אין חיבור פעיל');
  end if;

  if v_number is null then
    raise exception 'מספר הזמנה חסר' using errcode = '22023';
  end if;

  v_date := coalesce(v_event_ts::date, v_setup_ts::date);
  if v_date is null then
    raise exception 'תאריך האירוע חסר' using errcode = '22023';
  end if;

  select id into v_cancelled from statuses
   where entity = 'event' and deleted_at is null and btrim(name) = 'בוטל' limit 1;
  select id into v_default from statuses
   where entity = 'event' and is_default and deleted_at is null limit 1;

  select * into v_event from events
   where customer_id = k.customer_id and event_number = v_number and deleted_at is null;

  perform app.system_write(true);

  if v_event.id is null then
    insert into events (customer_id, end_client_name, event_number, event_date,
      location_text, location_provider, location_place_id, location_lat, location_lng,
      location_notes, volume_m, truck_count, notes, status_id,
      no_parking, porterage, supplier_pickup, created_by)
    values (k.customer_id,
      nullif(btrim(p_order ->> 'customer_name'), ''),
      v_number,
      v_date,
      nullif(btrim(p_order ->> 'location'), ''),
      nullif(btrim(p_order ->> 'location_provider'), ''),
      nullif(btrim(p_order ->> 'location_place_id'), ''),
      (nullif(p_order ->> 'location_lat', ''))::double precision,
      (nullif(p_order ->> 'location_lng', ''))::double precision,
      nullif(btrim(p_order ->> 'location_notes'), ''),
      (nullif(p_order ->> 'volume', ''))::numeric,
      (nullif(p_order ->> 'truck_quantity', ''))::int,
      nullif(btrim(p_order ->> 'operational_notes'), ''),
      coalesce(v_status, v_default),
      coalesce((p_order ->> 'parking')::boolean, false),
      coalesce((p_order ->> 'porterage')::boolean, false),
      coalesce((p_order ->> 'supplier_collection')::boolean, false),
      null)
    returning id into v_event_id;
    v_created := true;
  else
    v_event_id := v_event.id;
    -- ‏`notes` אינו ברשימה: ראו §4 בכותרת.
    update events set
      end_client_name   = coalesce(nullif(btrim(p_order ->> 'customer_name'), ''), end_client_name),
      event_date        = v_date,
      location_text     = coalesce(nullif(btrim(p_order ->> 'location'), ''), location_text),
      location_provider = coalesce(nullif(btrim(p_order ->> 'location_provider'), ''), location_provider),
      location_place_id = coalesce(nullif(btrim(p_order ->> 'location_place_id'), ''), location_place_id),
      location_lat      = coalesce((nullif(p_order ->> 'location_lat', ''))::double precision, location_lat),
      location_lng      = coalesce((nullif(p_order ->> 'location_lng', ''))::double precision, location_lng),
      location_notes    = coalesce(nullif(btrim(p_order ->> 'location_notes'), ''), location_notes),
      volume_m          = coalesce((nullif(p_order ->> 'volume', ''))::numeric, volume_m),
      truck_count       = coalesce((nullif(p_order ->> 'truck_quantity', ''))::int, truck_count),
      no_parking        = coalesce((p_order ->> 'parking')::boolean, no_parking),
      porterage         = coalesce((p_order ->> 'porterage')::boolean, porterage),
      supplier_pickup   = coalesce((p_order ->> 'supplier_collection')::boolean, supplier_pickup),
      status_id         = case
                            when v_status is not null and v_status = v_cancelled then v_status
                            when v_status is not null and status_id = v_default  then v_status
                            else status_id
                          end
    where id = v_event_id;
  end if;

  if v_contact_n is not null or v_contact_p is not null then
    insert into event_contacts (event_id, contact_name, contact_phone)
    values (v_event_id, v_contact_n, v_contact_p)
    on conflict (event_id) do update
      set contact_name  = coalesce(excluded.contact_name, event_contacts.contact_name),
          contact_phone = coalesce(excluded.contact_phone, event_contacts.contact_phone);
  end if;

  -- ‏`v_setup_ts::date` ולא `coalesce(…, v_date)`: מעטפה שאינה נושאת את שעת
  -- ההקמה אינה אומרת "ההקמה ביום האירוע" — היא אינה אומרת עליה דבר, ומשימה
  -- שהרכז כבר הזיז אינה נגררת בחזרה בגלל משלוח חלקי. משימה שנולדת עכשיו
  -- ממילא יושבת על תאריך האירוע בזכות הטריגר של 0003.
  perform app.arco_apply_task(v_event_id, 'setup',
    v_setup_ts::date,
    -- חצות אינה שעה (§1 בכותרת)
    case when v_setup_ts is not null and v_setup_ts::time <> time '00:00' then v_setup_ts::time end,
    (nullif(p_order ->> 'setup_hours_quantity', ''))::numeric,
    (nullif(p_order ->> 'setup_crew_size', ''))::int,
    p_order ->> 'setup_method',
    p_order ->> 'setup_execution_contractor',
    (select c.name from customers c where c.id = k.customer_id));

  perform app.arco_apply_task(v_event_id, 'teardown',
    v_teardown_ts::date,
    case when v_teardown_ts is not null and v_teardown_ts::time <> time '00:00' then v_teardown_ts::time end,
    (nullif(p_order ->> 'dismantling_hours_quantity', ''))::numeric,
    (nullif(p_order ->> 'dismantling_crew_size', ''))::int,
    p_order ->> 'dismantling_method',
    p_order ->> 'dismantling_execution_contractor',
    (select c.name from customers c where c.id = k.customer_id));

  if not v_sys then perform app.system_write(false); end if;

  return jsonb_build_object(
    'status',   case when v_created then 'created' else 'updated' end,
    'event_id', v_event_id);
end $$;

-- ===== 4. מה האירוע מחזיר לארקו ==========================================
--
-- תמונת מצב אחת שמשרתת שני קוראים: התשובה לתרחיש פתיחת ההזמנה (§5) והדיווח
-- על כל שינוי (0184). מכאן שהיא **כן** מחזיקה מחירים — בניגוד ל-ViperFlow,
-- שם הבקשה הייתה ההפך המדויק. ארקו היא הלקוח שמשלם, והמחיר שלה הוא בדיוק
-- מה שהיא ביקשה לקבל.
create or replace function app.arco_event_snapshot(p_event uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  e      events;
  v_tasks jsonb;
begin
  select * into e from events where id = p_event;
  if e.id is null then return null; end if;

  select coalesce(jsonb_agg(x order by x ->> 'task_date', x ->> 'task_type'), '[]'::jsonb)
    into v_tasks
  from (
    select jsonb_build_object(
      'task_id',           t.id,
      'task_type',         tt.name,
      'task_type_code',    tt.code,
      'task_date',         t.task_date,
      'onsite_start_time', to_char(t.onsite_start_time, 'HH24:MI'),
      'onsite_end_time',   to_char(t.onsite_end_time, 'HH24:MI'),
      'hours_count',       t.hours_count,
      'worker_count',      t.worker_count,
      'execution_method',  (select m.name from execution_methods m where m.id = t.execution_method_id),
      'performed_by',      t.performed_by,
      'status',            (select s.name from statuses s where s.id = t.status_id),
      'price',             coalesce(p.price, 0),
      'price_is_manual',   coalesce(p.is_manual, false),
      'priced',            p.task_id is not null) as x
    from tasks t
    join task_types tt on tt.id = t.task_type_id
    left join task_pricing p on p.task_id = t.id
   where t.event_id = p_event and t.deleted_at is null) s;

  return jsonb_build_object(
    'event_id',        e.id,
    'order_number',    e.event_number,
    'end_client_name', e.end_client_name,
    'event_date',      e.event_date,
    'location',        e.location_text,
    'location_notes',  e.location_notes,
    'status',          (select s.name from statuses s where s.id = e.status_id),
    'truck_count',     e.truck_count,
    'volume_m',        e.volume_m,
    'no_parking',      e.no_parking,
    'porterage',       e.porterage,
    'supplier_pickup', e.supplier_pickup,
    'contact_name',    (select contact_name  from event_contacts where event_id = e.id),
    'contact_phone',   (select contact_phone from event_contacts where event_id = e.id),
    'updated_at',      e.updated_at,
    'tasks',           v_tasks,
    'total_price',     (select coalesce(sum((v ->> 'price')::numeric), 0)
                          from jsonb_array_elements(v_tasks) v),
    'currency',        'ILS');
end $$;

-- ===== 5. הכניסה: קריאה אחת ==============================================
--
-- שתי הפונקציות שלמטה הן היחידות שפונקציית הקצה קוראת. כל אחת רושמת את
-- המשלוח, מתרגמת, ומסמנת מה יצא.
--
-- **כישלון עסקי אינו שגיאה כלפי חוץ.** תרחיש ב-Make שמקבל 4xx עוצר, ומסמן
-- את עצמו כשבור — מעטפה אחת שלא ידענו לעכל הייתה מפילה את הצינור כולו.
-- לכן כל חריגה נתפסת כאן, נרשמת כ-'failed' עם הסיבה, והפונקציה מחזירה
-- תשובה תקינה. מה שנשאר הוא שורה אדומה במסך, וכפתור "הרץ מחדש".

create or replace function arco_ingest_event(p_payload jsonb, p_meta jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_conn   uuid;
  v_active boolean;
  v_row    uuid;
  v_result jsonb;
  v_number text := app.arco_order_number(p_payload ->> 'order_number');
begin
  -- קורא עם JWT הוא אדם שלחץ "הרץ מחדש"; בלי JWT זו פונקציית הקצה בזהות
  -- service role. אותה הבחנה של `viperflow_ingest` (0177 §5).
  if auth.uid() is not null then
    perform app.require('integrations.manage', 'אין לך הרשאה להזרים הזמנות ארקו');
  end if;

  -- מי כותב ביומן כשאיש לא לחץ (0176 §2).
  perform set_config('app.actor_label', 'ארקו', true);

  select id, is_active into v_conn, v_active from arco_connections
   where (p_meta ->> 'connection_id') is null
      or id = (p_meta ->> 'connection_id')::uuid
   order by created_at
   limit 1;

  insert into arco_deliveries (connection_id, kind, order_number, payload)
  values (v_conn, 'event', v_number, p_payload)
  returning id into v_row;

  if v_conn is null then
    v_result := jsonb_build_object('status', 'ignored', 'reason', 'לא הוגדר חיבור לארקו');
  elsif not coalesce(v_active, false) then
    v_result := jsonb_build_object('status', 'ignored', 'reason', 'החיבור כבוי');
  else
    begin
      v_result := app.arco_apply_order(v_conn, p_payload);
    exception when others then
      v_result := jsonb_build_object('status', 'failed', 'reason', sqlerrm);
    end;
  end if;

  if nullif(v_result ->> 'event_id', '') is not null then
    v_result := v_result || jsonb_build_object(
      'event', app.arco_event_snapshot((v_result ->> 'event_id')::uuid));
  end if;

  update arco_deliveries set
    status = case v_result ->> 'status'
               when 'created' then 'applied'
               when 'updated' then 'applied'
               when 'failed'  then 'failed'
               else 'ignored' end,
    reason       = v_result ->> 'reason',
    event_row_id = nullif(v_result ->> 'event_id', '')::uuid,
    result       = v_result,
    processed_at = now()
   where id = v_row;

  update arco_connections set last_seen_at = now() where id = v_conn;

  return v_result || jsonb_build_object('delivery', v_row);
end $$;

revoke execute on function arco_ingest_event(jsonb, jsonb) from anon, public;
grant  execute on function arco_ingest_event(jsonb, jsonb) to service_role, authenticated;

/**
 * המפרט. ארקו שולחת קישור לקובץ, ואנחנו רושמים אותו כגרסה חדשה ברשימת
 * המפרטים של האירוע (0077) — בדיוק כפי שהתרחיש מוסיף אותו היום למערך
 * ‏`mifrat` ב-Firestore. הגרסאות נצברות ואינן דורסות זו את זו: מפרט שהתחלף
 * שלוש פעמים הוא שלוש שורות, והאחרונה היא זו שמוצגת.
 *
 * מפרט זהה שנשלח פעמיים אינו נרשם פעמיים: אותה כתובת בדיוק, כשהיא כבר
 * הגרסה האחרונה החיה, היא משלוח חוזר ולא מפרט חדש.
 */
create or replace function arco_ingest_spec(p_payload jsonb, p_meta jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_conn    uuid;
  v_active  boolean;
  v_cust    uuid;
  v_row     uuid;
  v_number  text := app.arco_order_number(p_payload ->> 'order_number');
  v_url     text := nullif(btrim(p_payload ->> 'file'), '');
  v_event   uuid;
  v_result  jsonb;
  v_sys     boolean := app.in_system_write();
begin
  if auth.uid() is not null then
    perform app.require('integrations.manage', 'אין לך הרשאה להזרים מפרטים מארקו');
  end if;

  perform set_config('app.actor_label', 'ארקו', true);

  select id, is_active, customer_id into v_conn, v_active, v_cust
    from arco_connections
   where (p_meta ->> 'connection_id') is null
      or id = (p_meta ->> 'connection_id')::uuid
   order by created_at
   limit 1;

  insert into arco_deliveries (connection_id, kind, order_number, payload)
  values (v_conn, 'spec', v_number, p_payload)
  returning id into v_row;

  if v_conn is null then
    v_result := jsonb_build_object('status', 'ignored', 'reason', 'לא הוגדר חיבור לארקו');
  elsif not coalesce(v_active, false) then
    v_result := jsonb_build_object('status', 'ignored', 'reason', 'החיבור כבוי');
  elsif v_number is null or v_url is null then
    v_result := jsonb_build_object('status', 'failed', 'reason', 'חסר מספר הזמנה או קישור למפרט');
  elsif v_url !~ '^https?://' then
    v_result := jsonb_build_object('status', 'failed', 'reason', 'קישור המפרט אינו כתובת חוקית');
  else
    select id into v_event from events
     where customer_id = v_cust and event_number = v_number and deleted_at is null;

    if v_event is null then
      -- לא שגיאה: מפרט שהקדים את ההזמנה. השורה נשמרת, ו"הרץ מחדש" אחרי
      -- שהאירוע נפתח יצרף אותו.
      v_result := jsonb_build_object('status', 'ignored', 'reason',
        'לא נמצא אירוע עם מספר ההזמנה ' || v_number);
    elsif v_url = (select s.url from event_specs s
                    where s.event_id = v_event and s.deleted_at is null
                    order by s.version desc limit 1) then
      v_result := jsonb_build_object('status', 'ignored', 'event_id', v_event,
        'reason', 'המפרט הזה כבר הגרסה האחרונה');
    else
      begin
        perform app.system_write(true);
        insert into event_specs (event_id, source, url, title, note)
        values (v_event, 'link', v_url,
                coalesce(nullif(btrim(p_payload ->> 'title'), ''), 'מפרט מארקו'),
                'עודכן ע״י ארקו');
        if not v_sys then perform app.system_write(false); end if;
        v_result := jsonb_build_object('status', 'applied', 'event_id', v_event);
      exception when others then
        if not v_sys then perform app.system_write(false); end if;
        v_result := jsonb_build_object('status', 'failed', 'reason', sqlerrm);
      end;
    end if;
  end if;

  update arco_deliveries set
    status = case v_result ->> 'status'
               when 'applied' then 'applied'
               when 'failed'  then 'failed'
               else 'ignored' end,
    reason       = v_result ->> 'reason',
    event_row_id = nullif(v_result ->> 'event_id', '')::uuid,
    result       = v_result,
    processed_at = now()
   where id = v_row;

  update arco_connections set last_seen_at = now() where id = v_conn;

  return v_result || jsonb_build_object('delivery', v_row);
end $$;

revoke execute on function arco_ingest_spec(jsonb, jsonb) from anon, public;
grant  execute on function arco_ingest_spec(jsonb, jsonb) to service_role, authenticated;

-- ===== 6. הרצה מחדש ======================================================
--
-- המעטפה שמורה אצלנו (0182 §3), ולכן "הרץ מחדש" אינו מבקש מ-Make דבר.
-- השורה הישנה נמחקת ונכתבת מחדש, מאותו נימוק של `viperflow_replay`.
create or replace function arco_replay(p_delivery uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_row  arco_deliveries;
  v_meta jsonb;
begin
  perform app.require('integrations.manage', 'אין לך הרשאה להריץ מחדש משלוח');

  select * into v_row from arco_deliveries where id = p_delivery;
  if v_row.id is null then raise exception 'משלוח לא נמצא'; end if;

  v_meta := jsonb_build_object('connection_id', v_row.connection_id);
  delete from arco_deliveries where id = p_delivery;

  if v_row.kind = 'spec' then
    return arco_ingest_spec(v_row.payload, v_meta);
  end if;
  return arco_ingest_event(v_row.payload, v_meta);
end $$;

revoke execute on function arco_replay(uuid) from anon, public;
grant  execute on function arco_replay(uuid) to authenticated;

-- ===== 7. והמתרגם עצמו סגור בפני כולם ====================================
--
-- ‏schema app פתוח ל-authenticated (0010:35), והפונקציות שלמטה הן
-- ‏`security definer` שכותבות אירועים ומשימות מתחת ל-`app.system_write` —
-- כלומר עוקפות את השער ברמת העמודה. בלי ה-revoke, כל משתמש מאומת היה יכול
-- לקרוא להן ישירות ולכתוב אירוע בשם המערכת. הדרך היחידה להגיע אליהן היא
-- ה-RPC-ים שבסעיף 5, שאוכפים `integrations.manage` על כל קורא שיש לו JWT.
revoke execute on function app.arco_local(text)                 from anon, authenticated, public;
revoke execute on function app.arco_order_number(text)          from anon, authenticated, public;
revoke execute on function app.arco_status_id(text)             from anon, authenticated, public;
revoke execute on function app.arco_execution_method_id(text)   from anon, authenticated, public;
revoke execute on function app.arco_apply_task(uuid, text, date, time, numeric, int, text, text, text)
  from anon, authenticated, public;
revoke execute on function app.arco_apply_order(uuid, jsonb)    from anon, authenticated, public;
revoke execute on function app.arco_event_snapshot(uuid)        from anon, authenticated, public;
