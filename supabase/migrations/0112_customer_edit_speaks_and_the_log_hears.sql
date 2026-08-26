-- 0112: כל עריכת לקוח מדברת, והיומן שומע גם את המשימות
--
-- שתי תלונות ותיקון אחד שמחבר ביניהן:
--
--   1. **"לקוח ערך אירוע ולא קיבלתי התראה."** ‏event_updated (0110) ישב
--      כטריגר שורה על events, ועריכה מטופס האירוע נוגעת לעיתים קרובות רק
--      בלוויינים — איש קשר, ספקים, בלוק הקמה/פירוק — בלי לשנות את שורת
--      האירוע עצמה. גרוע מזה: הטריגר רץ בשלב ה-UPDATE של update_event, לפני
--      שכתיבות הלוויינים בכלל קרו, כך שטריגר-שורה מבנית אינו מסוגל לראות
--      אותן. ‏RLS (0014) מבטיח שכל כתיבת לקוח לאירוע עוברת דרך update_event
--      — ולכן "סוף update_event" הוא בדיוק "הלקוח שמר את הטופס", וההתראה
--      עוברת לשם.
--   2. **"היומן לא מספר הכול."** שינויי שדות משימה — תאריך, שעת שטח, שעת
--      מחסן, שעות, כמות עובדים, אופן ביצוע — לא נרשמו ביומן הפעילות בכלל.
--      חצי טופס האירוע (בלוקי ההקמה והפירוק) היה שקוף ליומן, וכך גם עריכות
--      מהלו״ז.
--
-- והחיבור: אחרי שהיומן שומע הכול, הוא נעשה גלאי-השינוי של ההתראה. כל כותבי
-- היומן הם טריגרי שורה סינכרוניים באותה טרנזקציה, ולכן בסוף update_event
-- השאלה "האם השמירה הזו שינתה משהו" היא בדיוק "האם היומן קיבל שורה
-- בטרנזקציה הזו". שמירה שלא שינתה דבר אינה כותבת שורות (כל הטריגרים משווים
-- old/new; מחיקת-והכנסת ספקים זהים מתקזזת, 0016) — ולכן היא גם שקטה.
--
-- מה נשאר בחוץ, בכוונה: כספים. ‏task_pricing ו-event_income אינם נרשמים
-- ביומן — אותו מותר לקרוא גם לראשי צוות בשטח (0082), וסכומים אינם עניינם.
-- המשמעות הנגזרת: עריכת הכנסות-בלבד אינה מפעילה את הגלאי — וללקוח ממילא
-- אין גישה לשדות ההכנסה בטופס.

-- ===== 1. הטריגר יורד ======================================================

drop trigger if exists events_notify_updated on events;
drop function if exists app.notify_event_updated();

-- והקטלוג אומר את הסמנטיקה החדשה. ‏register_notification_type אינו נוגע
-- ב-is_active וב-required_permission של שורה קיימת (0046).
select app.register_notification_type('event_updated', 'לקוח עדכן אירוע',
  'כל שמירה של לקוח בטופס האירוע ששינתה משהו — כולל אנשי קשר, ספקים והקמה/פירוק',
  'אירועים', array['admin'], 'event', 'opt_out', 'opt_out', 'opt_in', 44);

-- ===== 2. היומן שומע את שדות המשימה ========================================

-- ערך של שדה משימה, בצורה שאדם קורא. במודל app.event_value_text (0109).
create or replace function app.task_value_text(p_col text, p_val jsonb)
returns text language plpgsql stable security definer set search_path = public as $$
declare v text;
begin
  if p_val is null or jsonb_typeof(p_val) = 'null' then return null; end if;
  v := p_val #>> '{}';
  return case p_col
    when 'task_date'            then to_char(v::date, 'DD/MM/YYYY')
    when 'onsite_start_time'    then to_char(v::time, 'HH24:MI')
    when 'warehouse_start_time' then to_char(v::time, 'HH24:MI')
    when 'execution_method_id'  then (select m.name from execution_methods m where m.id = v::uuid)
    else v
  end;
end $$;

-- הגוף מ-0049 מילה במילה, בתוספת לולאת ההשוואה בסופו. שלוש הכרעות:
--
--   • **שער אותה-טרנזקציה** (`old.created_at < transaction_timestamp()`):
--     ‏apply_event_task_block יוצר משימה חסרה ומיד מעדכן אותה (0017/0111),
--     וכך גם ייבוא האקסל. בלי השער כל יצירה כזו הייתה מדברת פעמיים —
--     task_added ואחריו מטח שורות changed מול ערכי ברירת המחדל.
--   • **status_id אינו ברשימה**: הלוח מפרסם ומוריד משימות כל היום, למעבר
--     הזה יש התראות משלו (task_published/unpublished, 0110), ויומן שמשקף
--     את הלוח מפסיק להיקרא. הוספתו בעתיד היא איבר אחד בשלושת המערכים.
--   • **field_key בפרס task_\*** אינו רשום ב-field_registry ולכן גלוי לכל
--     קורא של הפיד — אלה שדות תפעוליים (שעות, כמויות), לא רגישים כמו
--     contact_phone. ‏field_label נושא את סוג המשימה ('הקמה — שעת התחלה
--     בשטח'), כך שאילוץ הצורה של 0016 מתקיים והטבלה במסך נקראת לבדה.
--
-- העברת משימה בין אירועים + שינוי שדה באותו UPDATE נרשמת כהסרה/הוספה בלבד
-- (ענף ההעברה חוזר ראשון) — המשפטים שם נושאים ממילא את הערכים הטריים.
create or replace function app.log_task_event_activity()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_actor uuid := app.profile_id();
  v_name  text;
  v_old   jsonb;
  v_new   jsonb;
  v_type_name text;
  f       record;
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

  -- שינויי שדות (0112): משימה חיה, על אותו אירוע, שלא נולדה בטרנזקציה הזו
  -- ולא שינתה מצב מחיקה.
  if new.event_id is not null
     and new.deleted_at is null and old.deleted_at is null
     and old.created_at < transaction_timestamp() then
    v_old := to_jsonb(old);
    v_new := to_jsonb(new);
    select tt.name into v_type_name from task_types tt where tt.id = new.task_type_id;
    for f in select * from unnest(
      array['task_date','onsite_start_time','warehouse_start_time',
            'hours_count','worker_count','execution_method_id','title'],
      array['task_date','task_onsite_start_time','task_warehouse_start_time',
            'task_hours_count','task_worker_count','task_execution_method','task_title'],
      array['תאריך','שעת התחלה בשטח','שעת התחלה במחסן',
            'כמות שעות','כמות עובדים','אופן ביצוע','כותרת']) as t(col, fkey, label)
    loop
      if v_old -> f.col is distinct from v_new -> f.col then
        insert into event_activity (event_id, kind, actor_profile_id, actor_name,
                                    field_key, field_label, old_value, new_value)
        values (new.event_id, 'changed', v_actor, v_name, f.fkey,
                coalesce(nullif(btrim(coalesce(new.title, '')), ''), v_type_name, 'משימה')
                  || ' — ' || f.label,
                app.task_value_text(f.col, v_old -> f.col),
                app.task_value_text(f.col, v_new -> f.col));
      end if;
    end loop;
  end if;

  return new;
end $$;

drop trigger if exists tasks_event_activity on tasks;
create trigger tasks_event_activity after insert or update or delete on tasks
  for each row execute function app.log_task_event_activity();

-- ===== 3. ההתראה יושבת בסוף update_event ===================================
--
-- הגוף מ-0068 מילה במילה, בתוספת לכידת הסטטוס לפני, והזנב אחרי. ההגדרה
-- מחדש מלאה ולא עטיפה — מאותו נימוק שכתוב ב-0030/0046/0054.
--
-- הזנב, כשהשחקן הוא לקוח:
--   • מעבר ל"בוטל" בקריאה הזו שקט כאן — events_notify_cancelled (0110) כבר
--     דיבר בזמן ה-UPDATE עצמו. ההשוואה היא מול הקוד שנלכד לפני, לא מול סדר
--     טריגרים.
--   • הגלאי: שורת יומן שאינה 'note' שנכתבה לאירוע הזה בטרנזקציה הזו.
--     ‏created_at של היומן הוא now() ,שהוא transaction_timestamp() — כל
--     הטריגרים סינכרוניים, והפונקציה definer ולכן ה-RLS של היומן אינו
--     מסתיר. אין שורות ⇒ השמירה לא שינתה דבר ⇒ שקט.
--   • תחולה (0110) ודילוג-שחקן כרגיל.
create or replace function update_event(p_event_id uuid, payload jsonb)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_customer_id uuid;
  v_profile_id uuid;
  v_was_cancelled boolean;
  v_now_cancelled boolean;
  v_ev events;
  v_label text;
  r record;
begin
  select customer_id into v_customer_id from events
    where id = p_event_id and deleted_at is null;
  if v_customer_id is null then raise exception 'אירוע לא נמצא'; end if;

  select (s.code = 'cancelled') into v_was_cancelled
    from events e left join statuses s on s.id = e.status_id
   where e.id = p_event_id;

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

  perform app.apply_event_income(p_event_id, v_customer_id, payload);

  perform app.system_write(true);
  perform app.apply_event_task_block(p_event_id, 'setup', payload);
  perform app.apply_event_task_block(p_event_id, 'teardown', payload);
  perform app.system_write(false);

  -- ===== הזנב (0112): הלקוח שמר — המנהל שומע =====
  if (select app.user_kind()) = 'customer_user' then
    select * into v_ev from events where id = p_event_id;
    select (s.code = 'cancelled') into v_now_cancelled
      from statuses s where s.id = v_ev.status_id;
    -- מעבר ל"בוטל" מדווח על ידי events_notify_cancelled — לא פעמיים
    if coalesce(v_now_cancelled, false) and not coalesce(v_was_cancelled, false) then
      return;
    end if;
    -- הגלאי: שמירה שלא כתבה שורת יומן לא שינתה דבר
    if not exists (select 1 from event_activity
                    where event_id = p_event_id
                      and created_at >= transaction_timestamp()
                      and kind <> 'note') then
      return;
    end if;
    if not app.notification_in_scope('event_updated', 'customer', v_customer_id) then
      return;
    end if;

    v_label := coalesce(v_ev.end_client_name, v_ev.event_number,
                        to_char(v_ev.event_date, 'DD/MM/YYYY'));
    for r in select id from profiles
      where is_admin and is_active and deleted_at is null
        and id is distinct from app.profile_id()
    loop
      perform app.notify(r.id, 'event_updated', 'לקוח עדכן אירוע',
        (select name from customers where id = v_customer_id) || ' — ' || v_label,
        'event', p_event_id);
    end loop;
  end if;
end $$;
