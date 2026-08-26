-- 0125: שינוי סטטוס אירוע אינו מבטל את האישור לביצוע
--
-- ‏0115 קבעה שעריכת לקוח מפילה את "מאושר לביצוע", והגלאי היה **כל** שורת יומן
-- שאינה `note` שנכתבה בטרנזקציה. אלא ש-`status_id` נרשם ביומן כשורת `changed`
-- (‏0016), ולכן שינוי סטטוס גרידא — מ"מתוכנן" ל"פעיל", וכדומה — נספר כשינוי
-- והפיל את האישור. זה בדיוק ההיפך מהכוונה של 0115: סטטוס הוא תכנון, לא שינוי
-- ב**מה שאושר**. הטריגר של הלו״ז כבר הוציא את `status_id` מרשימתו (0115:196),
-- ואת אותה הכרעה חסרה הזרוע של `update_event`.
--
-- **גלאי נפרד לאישור, נתון נפרד להתראה.** ‏`v_changed` נשאר מה שהיה — כל שינוי,
-- כולל סטטוס — ולכן ההתראה ללקוח (0112) אינה משתנה: המשרד עדיין שומע ששונה
-- הסטטוס. ‏`v_spec_changed` הוא אותו גלאי פחות שינוי-סטטוס-בלבד, והוא זה
-- שמכריע אם להוריד את האישור. שני משתנים ולא רשימת עמודות שנייה, כי היומן
-- הוא עדיין מקור האמת היחיד לשאלה "מה השתנה".
--
-- **ביטול אירוע הוא היוצא מן הכלל שנשמר.** אירוע שבוטל ונשאר "מאושר לביצוע"
-- הוא הצירוף היחיד שנקרא כשטות בלוח השנה (0115), ולכן מעבר ל"בוטל" ממשיך
-- להפיל את האישור — הוא נכלל ב-`v_spec_changed` דרך התנאי `v_now_cancelled`.

create or replace function update_event(p_event_id uuid, payload jsonb)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_customer_id uuid;
  v_profile_id uuid;
  v_was_cancelled boolean;
  v_now_cancelled boolean;
  v_ev events;
  v_label text;
  v_changed boolean;
  v_spec_changed boolean;
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

  -- ===== הזנב (0112): הלקוח שמר — המנהל שומע. ו-0115/0125: והאישור יורד =====
  if (select app.user_kind()) = 'customer_user' then
    select * into v_ev from events where id = p_event_id;
    select (s.code = 'cancelled') into v_now_cancelled
      from statuses s where s.id = v_ev.status_id;

    -- הגלאי של 0112 (כל שינוי) — לתוך משתנה ולפני כל כתיבה נוספת ליומן.
    v_changed := exists (select 1 from event_activity
                          where event_id = p_event_id
                            and created_at >= transaction_timestamp()
                            and kind <> 'note');

    -- ‏0125: גלאי האישור מחריג שינוי-סטטוס-בלבד. `status_id` נרשם עם
    -- ‏field_key='status_id' (0016), והוא תכנון ולא מפרט — בדיוק כפי שהטריגר
    -- של הלו״ז מחריג אותו. שאר השדות (כולל בלוקי הקמה/פירוק, שגם הם נכתבים
    -- ליומן מ-0112) עדיין מפילים את האישור.
    v_spec_changed := exists (select 1 from event_activity
                               where event_id = p_event_id
                                 and created_at >= transaction_timestamp()
                                 and kind <> 'note'
                                 and not (kind = 'changed' and field_key = 'status_id'));

    -- ‏0115: מה שהמשרד אישר אינו מה שעומד עכשיו בטופס. רק עריכת ה**לקוח**
    -- מבטלת. הכתיבה עטופה ב-system_write כי app.events_approval_guard (0109)
    -- דוחה כל נגיעה ישירה בשתי העמודות. מעבר ל"בוטל" מפיל אף הוא — צירוף
    -- "מבוטל + מאושר" הוא השטות היחידה בלוח השנה.
    if (v_spec_changed or coalesce(v_now_cancelled, false)) and v_ev.approved_at is not null then
      perform app.system_write(true);
      update events set approved_at = null, approved_by = null
       where id = p_event_id;
      perform app.system_write(false);
    end if;

    -- מעבר ל"בוטל" מדווח על ידי events_notify_cancelled — לא פעמיים
    if coalesce(v_now_cancelled, false) and not coalesce(v_was_cancelled, false) then
      return;
    end if;
    -- הגלאי: שמירה שלא כתבה שורת יומן לא שינתה דבר
    if not v_changed then
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
