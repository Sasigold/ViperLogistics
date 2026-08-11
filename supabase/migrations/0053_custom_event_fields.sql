-- 0053: שדות מותאמים אישית בטופס האירוע, פר-לקוח
--
-- טופס האירוע כבר דינמי — form_fields → customer_form_fields → user_form_fields
-- מצטלבות ב-app.form_config (0015) לכדי מוצג/מוסתר/חובה — אבל הקטלוג עצמו קבוע:
-- כל שורה ב-form_fields נולדה מ-insert בקובץ מיגרציה (0002, 0009, 0017), ל-events
-- אין מקום לערך שאינו עמודה, ו-create_event/update_event בונות רשימת עמודות
-- מפורשת ומתעלמות בשקט מכל מפתח לא מוכר. כלומר: שורה חדשה ב-form_fields היום
-- היא אינרטית — היא מופיעה בלשונית ההגדרות של הלקוח ואף מסך לא יודע לצייר אותה.
--
-- הקובץ כאן פותח את הקטלוג. שלוש החלטות:
--
--   1. **שדה מותאם הוא שורה רגילה ב-form_fields**, עם customer_id מלא (null =
--      שדה מערכת, כל הקיימים). זה מה שנותן בחינם את שלוש שכבות התצורה, את
--      app.strip_hidden_event_keys ואת app.validate_event_payload — כולן כבר
--      עובדות על מפתח שרירותי, כי app.event_payload_keys נופלת ל-array[key].
--      מה שנוסף הוא רק טיפוס לשדה, מקום לערך, וציור דינמי בדפדפן.
--   2. **הערך יושב ב-events.custom_fields jsonb.** העמודה אינה ב-field_registry,
--      ולכן app.enforce_field_perms (0012) מעבירה אותה ו-app.rebuild_secure_view
--      כותבת אותה כפי שהיא — וזו ההתנהגות הרצויה: השליטה בשדות האלה היא דרך
--      תצורת הטופס, לא דרך הרשאות עמודה. אין למי שמגדיר אותם דרך לרשום עמודה
--      חדשה ב-field_registry ממילא.
--   3. **המפתח נוצר בשרת**, לא בדפדפן. מפתח שהמשתמש בוחר יכול להתנגש בשם עמודה
--      אמיתית ('notes', 'event_date') ואז ה-payload יתפרש פעמיים.
--
-- מה שלא נעשה כאן: שדה מותאם *גלובלי*. הצורך שנוסח היה "שדה של לקוח", והוספת
-- טווח שני הייתה דורשת מסך ניהול שני והרשאה שנייה. customer_id הוא nullable
-- כדי שהתוספת הזו תהיה שורת insert ולא שינוי סכימה.

-- ===== 1. סכימה ============================================================

alter table form_fields
  add column customer_id uuid references customers(id) on delete cascade,
  add column field_type  text not null default 'text'
    check (field_type in ('text','textarea','number','date','time','select','checkbox')),
  add column options     jsonb not null default '[]'::jsonb,
  add column deleted_at  timestamptz;

-- שדה מותאם חייב טווח: שדה מערכת (customer_id is null) לא ניתן ליצור דרך ה-RPC
-- שכאן, ולכן שדה עם options אינו חייב customer_id — אבל שני שדות באותו לקוח לא
-- יישאו את אותה תווית, כי ההבחנה ביניהם במסך היא התווית בלבד.
create unique index form_fields_customer_label_idx
  on form_fields (customer_id, label_he) where deleted_at is null and customer_id is not null;
create index form_fields_customer_idx
  on form_fields (customer_id) where deleted_at is null;

alter table events add column custom_fields jsonb not null default '{}'::jsonb;

-- ===== 2. הצינור הקיים לומד על הטווח ======================================
-- בלי הסינון הזה שדה של לקוח א׳ מופיע בטופס של לקוח ב׳ — form_config סורקת את
-- form_fields כולה.
create or replace function app.form_config(p_customer uuid, p_profile uuid)
returns table (field_key text, state field_state)
language sql stable set search_path = public as $$
  select f.field_key,
         case
           when c.state = 'hidden'   or u.state = 'hidden'   then 'hidden'
           when c.state = 'required' or u.state = 'required' then 'required'
           else 'visible'
         end::field_state
  from form_fields f
  left join customer_form_fields c
         on c.customer_id = p_customer and c.field_key = f.field_key
  left join user_form_fields u
         on u.profile_id = p_profile and u.field_key = f.field_key
  where f.deleted_at is null
    and (f.customer_id is null or f.customer_id = p_customer)
$$;

-- לקוח חדש מקבל את שדות המערכת בלבד; שדות מותאמים שייכים ללקוח שיצר אותם
-- ומקבלים את שורת התצורה שלהם מהטריגר שלמטה.
create or replace function app.seed_customer_defaults()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into customer_execution_methods (customer_id, execution_method_id)
  select new.id, m.id from execution_methods m where m.deleted_at is null
  on conflict do nothing;
  insert into customer_form_fields (customer_id, field_key, state)
  select new.id, f.field_key, 'visible'::field_state
    from form_fields f where f.customer_id is null and f.deleted_at is null
  on conflict do nothing;
  return new;
end $$;

-- שדה מותאם בלי שורת customer_form_fields היה נשען על ברירת המחדל של
-- form_config ('visible'), אבל אז ה-SegmentedControl במסך הלקוח לא היה מוצא מה
-- להציג עד הלחיצה הראשונה. השורה נכתבת מיד.
create or replace function app.seed_custom_field_state()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.customer_id is not null then
    insert into customer_form_fields (customer_id, field_key, state)
    values (new.customer_id, new.field_key, 'visible')
    on conflict do nothing;
  end if;
  return new;
end $$;
create trigger form_fields_seed_state after insert on form_fields
  for each row execute function app.seed_custom_field_state();

-- ===== 3. ולידציית חובה מכירה תיבת סימון ==================================
-- זהה ל-0015 בשתי תוספות: שדה שנמחק אינו נדרש, ו"חובה" על תיבת סימון פירושו
-- שהיא מסומנת — 'false' הוא בדיוק המצב שהדרישה באה למנוע, ולא ערך שמילא אותה.
create or replace function app.validate_event_payload(
  p_customer uuid, p_profile uuid, payload jsonb, p_patch boolean)
returns void language plpgsql stable set search_path = public as $$
declare v_missing text[];
begin
  select coalesce(array_agg(f.label_he), '{}') into v_missing
  from app.form_config(p_customer, p_profile) cfg
  join form_fields f on f.field_key = cfg.field_key and f.deleted_at is null
  where cfg.state = 'required'
    and cfg.field_key <> 'addons'
    and (not p_patch
         or payload ? (case cfg.field_key when 'location' then 'location_text'
                                          else cfg.field_key end))
    and (case
           when f.field_type = 'checkbox'
             then nullif(nullif(payload ->> cfg.field_key, ''), 'false')
           when cfg.field_key = 'location' then nullif(payload ->> 'location_text', '')
           else nullif(payload ->> cfg.field_key, '')
         end) is null;
  if array_length(v_missing, 1) > 0 then
    raise exception 'שדות חובה חסרים: %', array_to_string(v_missing, ', ');
  end if;
end $$;

-- ===== 4. הערכים ==========================================================
-- מ-payload שטוח לאובייקט custom_fields, עם המרה לפי הטיפוס. שלוש נקודות:
--   • מפתח שאינו ב-payload אינו מוחזר כלל — כך update_event שומרת סמנטיקת patch
--     גם על השדות האלה: מה שלא נשלח נשאר.
--   • מפתח שנשלח ריק מוחזר כ-json null, כלומר "רוקן את השדה" — הבחנה שאי אפשר
--     לעשות בלי שני המצבים.
--   • המרה שנכשלת מרימה שגיאה בעברית עם שם השדה. בלי ה-block הפנימי ההודעה
--     הייתה 'invalid input syntax for type numeric', שאין לה משמעות למי שמילא
--     טופס בעברית.
create or replace function app.event_custom_patch(p_customer uuid, payload jsonb)
returns jsonb language plpgsql stable set search_path = public as $$
declare f record; v_out jsonb := '{}'::jsonb; v_raw text; v_val jsonb;
begin
  if p_customer is null then return v_out; end if;
  for f in
    select field_key, label_he, field_type, options
      from form_fields
     where customer_id = p_customer and deleted_at is null
  loop
    if not (payload ? f.field_key) then continue; end if;

    v_raw := nullif(btrim(coalesce(payload ->> f.field_key, '')), '');
    if v_raw is null then
      v_out := v_out || jsonb_build_object(f.field_key, null);
      continue;
    end if;

    if f.field_type = 'select'
       and not exists (select 1 from jsonb_array_elements_text(f.options) o
                        where o.value = v_raw) then
      raise exception 'ערך לא מוכר בשדה "%": %', f.label_he, v_raw;
    end if;

    begin
      v_val := case f.field_type
        when 'number'   then to_jsonb(v_raw::numeric)
        when 'date'     then to_jsonb(v_raw::date::text)
        when 'time'     then to_jsonb(to_char(v_raw::time, 'HH24:MI'))
        when 'checkbox' then to_jsonb(v_raw::boolean)
        else to_jsonb(v_raw)
      end;
    exception when others then
      raise exception 'ערך לא תקין בשדה "%": %', f.label_he, v_raw;
    end;

    v_out := v_out || jsonb_build_object(f.field_key, v_val);
  end loop;
  return v_out;
end $$;

-- ===== 5. create/update/duplicate =========================================
-- גוף זהה ל-0015 (ול-0012 עבור duplicate_event) למעט custom_fields.
create or replace function create_event(payload jsonb)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_customer_id uuid;
  v_profile_id uuid;
  v_event_id uuid;
  v_status uuid;
  r record;
begin
  v_profile_id := app.profile_id();

  if (select app.user_kind()) = 'customer_user' then
    v_customer_id := app.customer_id();
    if not app.has('events.create')
       or not exists (select 1 from customers c where c.id = v_customer_id
                      and c.can_create_events and c.deleted_at is null) then
      raise exception 'אין לך הרשאה ליצור אירועים' using errcode = '42501';
    end if;
    payload := app.strip_hidden_event_keys(v_profile_id, payload);
  elsif app.is_admin() or app.has('events.create') then
    v_customer_id := (payload ->> 'customer_id')::uuid;
    if v_customer_id is null then raise exception 'חובה לבחור לקוח'; end if;
    v_profile_id := null;
  else
    raise exception 'אין לך הרשאה ליצור אירועים' using errcode = '42501';
  end if;

  perform app.validate_event_payload(v_customer_id, v_profile_id, payload, false);

  if payload ->> 'event_date' is null then
    raise exception 'שדות חובה חסרים: תאריך אירוע';
  end if;

  v_status := coalesce((payload ->> 'status_id')::uuid,
    (select id from statuses where entity = 'event' and is_default and deleted_at is null limit 1));

  insert into events (customer_id, end_client_name, event_number, event_date,
    location_text, location_provider, location_place_id, location_lat, location_lng,
    location_notes, volume_m, truck_count, notes, status_id,
    no_parking, porterage, supplier_pickup, custom_fields, created_by)
  values (v_customer_id,
    nullif(payload ->> 'end_client_name',''),
    nullif(payload ->> 'event_number',''),
    (payload ->> 'event_date')::date,
    nullif(payload ->> 'location_text',''),
    nullif(payload ->> 'location_provider',''),
    nullif(payload ->> 'location_place_id',''),
    (payload ->> 'location_lat')::double precision,
    (payload ->> 'location_lng')::double precision,
    nullif(payload ->> 'location_notes',''),
    (nullif(payload ->> 'volume_m',''))::numeric,
    (nullif(payload ->> 'truck_count',''))::int,
    nullif(payload ->> 'notes',''),
    v_status,
    coalesce((payload ->> 'no_parking')::boolean, false),
    coalesce((payload ->> 'porterage')::boolean, false),
    coalesce((payload ->> 'supplier_pickup')::boolean, false),
    app.event_custom_patch(v_customer_id, payload),
    app.profile_id())
  returning id into v_event_id;

  if nullif(payload ->> 'contact_name','') is not null
     or nullif(payload ->> 'contact_phone','') is not null then
    insert into event_contacts (event_id, contact_name, contact_phone)
    values (v_event_id, nullif(payload ->> 'contact_name',''), nullif(payload ->> 'contact_phone',''));
  end if;

  if payload ? 'supplier_ids' then
    for r in select value::uuid as sid from jsonb_array_elements_text(payload -> 'supplier_ids') loop
      insert into event_suppliers (event_id, supplier_id) values (v_event_id, r.sid)
      on conflict do nothing;
    end loop;
  end if;

  perform app.system_write(true);
  perform app.apply_event_task_block(v_event_id, 'setup', payload);
  perform app.apply_event_task_block(v_event_id, 'teardown', payload);
  perform app.system_write(false);

  return v_event_id;
end $$;

create or replace function update_event(p_event_id uuid, payload jsonb)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_customer_id uuid;
  v_profile_id uuid;
begin
  select customer_id into v_customer_id from events
    where id = p_event_id and deleted_at is null;
  if v_customer_id is null then raise exception 'אירוע לא נמצא'; end if;

  if not (app.is_admin()
          or ((select app.user_kind()) = 'staff' and app.has('events.edit'))
          or ((select app.user_kind()) = 'customer_user'
              and v_customer_id = app.customer_id()
              and app.has('events.edit'))) then
    raise exception 'אין לך הרשאה לערוך אירוע זה' using errcode = '42501';
  end if;

  if (select app.user_kind()) = 'customer_user' then
    v_profile_id := app.profile_id();
    payload := app.strip_hidden_event_keys(v_profile_id, payload);
  end if;

  perform app.validate_event_payload(v_customer_id, v_profile_id, payload, true);

  update events set
    end_client_name = case when payload ? 'end_client_name' then nullif(payload ->> 'end_client_name','') else end_client_name end,
    event_number    = case when payload ? 'event_number' then nullif(payload ->> 'event_number','') else event_number end,
    event_date      = case when payload ? 'event_date' then (payload ->> 'event_date')::date else event_date end,
    location_text   = case when payload ? 'location_text' then nullif(payload ->> 'location_text','') else location_text end,
    location_provider = case when payload ? 'location_provider' then nullif(payload ->> 'location_provider','') else location_provider end,
    location_place_id = case when payload ? 'location_place_id' then nullif(payload ->> 'location_place_id','') else location_place_id end,
    location_lat    = case when payload ? 'location_lat' then (payload ->> 'location_lat')::double precision else location_lat end,
    location_lng    = case when payload ? 'location_lng' then (payload ->> 'location_lng')::double precision else location_lng end,
    location_notes  = case when payload ? 'location_notes' then nullif(payload ->> 'location_notes','') else location_notes end,
    volume_m        = case when payload ? 'volume_m' then (nullif(payload ->> 'volume_m',''))::numeric else volume_m end,
    truck_count     = case when payload ? 'truck_count' then (nullif(payload ->> 'truck_count',''))::int else truck_count end,
    notes           = case when payload ? 'notes' then nullif(payload ->> 'notes','') else notes end,
    status_id       = case when payload ? 'status_id' then (payload ->> 'status_id')::uuid else status_id end,
    no_parking      = case when payload ? 'no_parking' then (payload ->> 'no_parking')::boolean else no_parking end,
    porterage       = case when payload ? 'porterage' then (payload ->> 'porterage')::boolean else porterage end,
    supplier_pickup = case when payload ? 'supplier_pickup' then (payload ->> 'supplier_pickup')::boolean else supplier_pickup end,
    -- מיזוג ולא החלפה: app.event_custom_patch מחזירה רק מפתחות שנשלחו
    custom_fields   = custom_fields || app.event_custom_patch(v_customer_id, payload)
  where id = p_event_id;

  if payload ? 'contact_name' or payload ? 'contact_phone' then
    insert into event_contacts (event_id, contact_name, contact_phone)
    values (p_event_id, nullif(payload ->> 'contact_name',''), nullif(payload ->> 'contact_phone',''))
    on conflict (event_id) do update set
      contact_name  = case when payload ? 'contact_name' then nullif(payload ->> 'contact_name','') else event_contacts.contact_name end,
      contact_phone = case when payload ? 'contact_phone' then nullif(payload ->> 'contact_phone','') else event_contacts.contact_phone end;
  end if;

  if payload ? 'supplier_ids' then
    delete from event_suppliers where event_id = p_event_id;
    insert into event_suppliers (event_id, supplier_id)
    select p_event_id, value::uuid from jsonb_array_elements_text(payload -> 'supplier_ids')
    on conflict do nothing;
  end if;

  perform app.system_write(true);
  perform app.apply_event_task_block(p_event_id, 'setup', payload);
  perform app.apply_event_task_block(p_event_id, 'teardown', payload);
  perform app.system_write(false);
end $$;

create or replace function duplicate_event(p_event_id uuid, p_new_date date default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_old events; v_new_id uuid; v_shift int;
begin
  perform app.require('events.duplicate', 'אין לך הרשאה לשכפל אירועים');
  select * into v_old from events where id = p_event_id and deleted_at is null;
  if v_old.id is null then raise exception 'אירוע לא נמצא'; end if;
  v_shift := coalesce(p_new_date, v_old.event_date) - v_old.event_date;

  perform app.system_write(true);
  insert into events (customer_id, end_client_name, event_number, event_date,
    location_text, location_provider, location_place_id, location_lat, location_lng,
    location_notes, volume_m, truck_count, notes, status_id,
    no_parking, porterage, supplier_pickup, custom_fields, created_by)
  values (v_old.customer_id, v_old.end_client_name, null,
    v_old.event_date + v_shift,
    v_old.location_text, v_old.location_provider, v_old.location_place_id,
    v_old.location_lat, v_old.location_lng, v_old.location_notes,
    v_old.volume_m, v_old.truck_count, v_old.notes,
    (select id from statuses where entity='event' and is_default and deleted_at is null limit 1),
    v_old.no_parking, v_old.porterage, v_old.supplier_pickup, v_old.custom_fields,
    app.profile_id())
  returning id into v_new_id;

  if app.has('events.view_contacts') then
    insert into event_contacts (event_id, contact_name, contact_phone)
    select v_new_id, contact_name, contact_phone from event_contacts where event_id = p_event_id
    on conflict do nothing;
  end if;

  insert into event_suppliers (event_id, supplier_id)
  select v_new_id, supplier_id from event_suppliers where event_id = p_event_id
  on conflict do nothing;

  insert into tasks (event_id, customer_id, task_type_id, title, task_date,
    onsite_start_time, warehouse_start_time, hours_count, worker_count,
    execution_method_id, truck_id, truck_free_text, notes, status_id, location_text, created_by)
  select v_new_id, t.customer_id, t.task_type_id, t.title, t.task_date + v_shift,
    t.onsite_start_time, t.warehouse_start_time, t.hours_count, t.worker_count,
    t.execution_method_id, t.truck_id, t.truck_free_text, t.notes,
    (select id from statuses where entity='task' and is_default and deleted_at is null limit 1),
    t.location_text, app.profile_id()
  from tasks t
  join task_types tt on tt.id = t.task_type_id
  where t.event_id = p_event_id and t.deleted_at is null and not tt.auto_create_on_event;

  update tasks nt set
    onsite_start_time = ot.onsite_start_time,
    warehouse_start_time = ot.warehouse_start_time,
    hours_count = ot.hours_count,
    worker_count = ot.worker_count,
    execution_method_id = ot.execution_method_id
  from tasks ot
  join task_types tt on tt.id = ot.task_type_id and tt.auto_create_on_event
  where nt.event_id = v_new_id and ot.event_id = p_event_id
    and nt.task_type_id = ot.task_type_id and ot.deleted_at is null and nt.deleted_at is null;
  perform app.system_write(false);

  return v_new_id;
end $$;

-- ===== 6. יומן הפעילות ====================================================
-- ערך של שדה מותאם, כפי שאדם קורא אותו. app.event_value_text עובדת לפי שם
-- עמודה ואין לה מה לומר על מפתח שנוצר בזמן ריצה, ולכן ההמרה כאן לפי טיפוס.
create or replace function app.custom_value_text(p_type text, p_val jsonb)
returns text language plpgsql stable set search_path = public as $$
declare v text;
begin
  if p_val is null or jsonb_typeof(p_val) = 'null' then return null; end if;
  if jsonb_typeof(p_val) = 'boolean' then
    return case when p_val = 'true'::jsonb then 'כן' else 'לא' end;
  end if;
  v := p_val #>> '{}';
  if p_type = 'date' then return to_char(v::date, 'DD/MM/YYYY'); end if;
  return v;
end $$;

-- זהה ל-0016 בתוספת לולאה שנייה על custom_fields. השדות שם אינם עמודות ולכן
-- אינם יכולים להיכנס לרשימה הקבועה; ההשוואה היא מפתח-מפתח, כדי ששינוי בשדה
-- אחד לא יירשם כשינוי של האובייקט כולו.
create or replace function app.log_event_activity()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_actor uuid := app.profile_id();
  v_name  text;
  v_old   jsonb;
  v_new   jsonb;
  f       record;
begin
  select full_name into v_name from profiles where id = v_actor;

  if tg_op = 'INSERT' then
    insert into event_activity (event_id, kind, actor_profile_id, actor_name)
    values (new.id, 'created', v_actor, v_name);
    return new;
  end if;

  if (old.deleted_at is null) <> (new.deleted_at is null) then
    insert into event_activity (event_id, kind, actor_profile_id, actor_name)
    values (new.id,
            case when new.deleted_at is null then 'restored' else 'deleted' end,
            v_actor, v_name);
  end if;

  v_old := to_jsonb(old);
  v_new := to_jsonb(new);

  for f in
    select * from unnest(
      array['event_date','end_client_name','event_number','customer_id','status_id',
            'location_text','location_notes','volume_m','truck_count','notes',
            'no_parking','porterage','supplier_pickup'],
      array['תאריך אירוע','לקוח סופי','מספר אירוע','לקוח','סטטוס',
            'מיקום','הערות מיקום','נפח (קוב)','כמות משאיות','הערות',
            'ללא חניה','סבלות','איסוף מספק']) as t(col, label)
  loop
    if v_old -> f.col is distinct from v_new -> f.col then
      insert into event_activity (
        event_id, kind, actor_profile_id, actor_name, field_key, field_label, old_value, new_value)
      values (new.id, 'changed', v_actor, v_name, f.col, f.label,
              app.event_value_text(f.col, v_old -> f.col),
              app.event_value_text(f.col, v_new -> f.col));
    end if;
  end loop;

  if old.custom_fields is distinct from new.custom_fields then
    for f in
      select k.key as col,
             coalesce(ff.label_he, k.key) as label,
             ff.field_type as ftype,
             old.custom_fields -> k.key as old_val,
             new.custom_fields -> k.key as new_val
      from (select jsonb_object_keys(old.custom_fields || new.custom_fields) as key) k
      left join form_fields ff on ff.field_key = k.key
    loop
      if f.old_val is distinct from f.new_val then
        insert into event_activity (
          event_id, kind, actor_profile_id, actor_name, field_key, field_label, old_value, new_value)
        values (new.id, 'changed', v_actor, v_name, f.col, f.label,
                app.custom_value_text(f.ftype, f.old_val),
                app.custom_value_text(f.ftype, f.new_val));
      end if;
    end loop;
  end if;

  return new;
end $$;

-- ===== 7. ניהול הקטלוג ====================================================
-- דרך RPC ולא כתיבה ישירה לטבלה: המפתח נוצר בשרת, השדה מוגבל לטווח של לקוח,
-- והשער הוא customers.manage_form_fields — אותו מפתח ששולט בלשונית — ולא
-- settings.edit שמדיניות form_fields_write דורשת עבור קטלוג המערכת.
create or replace function create_custom_form_field(
  p_customer_id uuid, p_label text, p_type text default 'text',
  p_options jsonb default '[]'::jsonb)
returns text language plpgsql security definer set search_path = public as $$
declare v_key text; v_sort int;
begin
  perform app.require('customers.manage_form_fields', 'אין לך הרשאה להגדיר שדות טופס');
  if not exists (select 1 from customers where id = p_customer_id and deleted_at is null) then
    raise exception 'לקוח לא נמצא';
  end if;
  if nullif(btrim(coalesce(p_label, '')), '') is null then
    raise exception 'חובה לתת שם לשדה';
  end if;
  if p_type not in ('text','textarea','number','date','time','select','checkbox') then
    raise exception 'סוג שדה לא מוכר: %', p_type;
  end if;
  if p_type = 'select' and coalesce(jsonb_array_length(p_options), 0) = 0 then
    raise exception 'שדה בחירה מרשימה חייב לפחות ערך אחד';
  end if;
  if exists (select 1 from form_fields
              where customer_id = p_customer_id and deleted_at is null
                and label_he = btrim(p_label)) then
    raise exception 'כבר קיים שדה בשם "%"', btrim(p_label);
  end if;

  v_key := 'custom_' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 12);
  select coalesce(max(sort_order), 999) + 1 into v_sort
    from form_fields where customer_id = p_customer_id;

  insert into form_fields (field_key, label_he, sort_order, customer_id, field_type, options)
  values (v_key, btrim(p_label), v_sort, p_customer_id, p_type,
          case when p_type = 'select' then coalesce(p_options, '[]'::jsonb) else '[]'::jsonb end);

  return v_key;
end $$;

create or replace function update_custom_form_field(
  p_field_key text, p_label text default null, p_options jsonb default null,
  p_sort_order int default null)
returns void language plpgsql security definer set search_path = public as $$
declare v form_fields;
begin
  perform app.require('customers.manage_form_fields', 'אין לך הרשאה להגדיר שדות טופס');
  select * into v from form_fields where field_key = p_field_key and deleted_at is null;
  if v.field_key is null or v.customer_id is null then
    raise exception 'שדה מותאם אישית לא נמצא';
  end if;
  if p_label is not null and nullif(btrim(p_label), '') is null then
    raise exception 'חובה לתת שם לשדה';
  end if;
  if v.field_type = 'select' and p_options is not null
     and coalesce(jsonb_array_length(p_options), 0) = 0 then
    raise exception 'שדה בחירה מרשימה חייב לפחות ערך אחד';
  end if;

  update form_fields set
    label_he   = coalesce(nullif(btrim(p_label), ''), label_he),
    options    = case when v.field_type = 'select' then coalesce(p_options, options) else options end,
    sort_order = coalesce(p_sort_order, sort_order)
  where field_key = p_field_key;
end $$;

-- מחיקה רכה: אירועים שכבר נשמרו מחזיקים את הערך ב-custom_fields, ומחיקה קשה
-- הייתה משאירה שם מפתח בלי תווית — יומן הפעילות והייצוא היו מציגים 'custom_a1b2'.
create or replace function delete_custom_form_field(p_field_key text)
returns void language plpgsql security definer set search_path = public as $$
declare v form_fields;
begin
  perform app.require('customers.manage_form_fields', 'אין לך הרשאה להגדיר שדות טופס');
  select * into v from form_fields where field_key = p_field_key and deleted_at is null;
  if v.field_key is null or v.customer_id is null then
    raise exception 'שדה מותאם אישית לא נמצא';
  end if;
  update form_fields set deleted_at = now() where field_key = p_field_key;
  delete from customer_form_fields where field_key = p_field_key;
  delete from user_form_fields where field_key = p_field_key;
end $$;

revoke execute on function create_custom_form_field(uuid, text, text, jsonb) from anon, public;
revoke execute on function update_custom_form_field(text, text, jsonb, int)  from anon, public;
revoke execute on function delete_custom_form_field(text)                    from anon, public;
grant  execute on function create_custom_form_field(uuid, text, text, jsonb) to authenticated;
grant  execute on function update_custom_form_field(text, text, jsonb, int)  to authenticated;
grant  execute on function delete_custom_form_field(text)                    to authenticated;

-- ===== 8. קריאת הקטלוג ====================================================
-- form_fields_read מ-0005 היא using (true), מה שהיה נכון כשהקטלוג היה זהה
-- לכולם. עכשיו הוא מכיל שמות שדות שלקוח הגדיר, ולקוח אחר אינו צריך לראות אותם.
drop policy if exists form_fields_read on form_fields;
create policy form_fields_read on form_fields for select to authenticated using (
  customer_id is null
  or (select app.is_admin())
  or app.has('customers.view')
  or customer_id = (select app.customer_id()));

-- ===== 9. עמודה חדשה ב-events → לבנות מחדש את התצוגה הממוסכת ==============
select app.rebuild_secure_view('events');
