-- 0115: עריכה של הלקוח מבטלת את האישור לביצוע
--
-- ‏0109 נתנה למנהל המערכת לסמן אירוע כ"מאושר לביצוע", והלקוח קורא את הסימון
-- בלוח השנה ובדף האירוע. מה שלא נאמר שם הוא מה קורה לסימון כשמה שאושר משתנה:
-- הלקוח הזיז את שעת ההקמה בשעתיים, והתג "מאושר לביצוע" נשאר במקומו. כלומר
-- המשרד אישר מפרט אחד, השטח קרא אישור על מפרט אחר, ואיש לא נדרש להסתכל שוב.
--
-- **רק עריכת הלקוח מבטלת** — לא של המשרד. המשרד הוא מי שמאשר, ואילו כל
-- שמירה שלו הייתה מורידה את האישור, האישור היה הופך לצעד שאי אפשר להשלים:
-- מסמנים, מתקנים פסיק, והסימון נעלם.
--
-- **הגלאי כבר קיים ואינו נכתב מחדש.** ‏0112 שאלה "האם השמירה הזו באמת שינתה
-- משהו" כדי להחליט אם לפלוט `event_updated`, וענתה על כך מיומן הפעילות:
-- שורת יומן שאינה 'note' שנכתבה בטרנזקציה הזו. זו בדיוק אותה שאלה, ולכן היא
-- נשאלת פעם אחת ומשרתת את שתי ההחלטות. רשימת עמודות שנייה, שאפשר לה להיפרד
-- מהראשונה, הייתה התשובה הגרועה כאן.
--
-- ומכיוון שהיומן הוא הגלאי, **בלוקי ההקמה והפירוק נכללים מאליהם**: מאז 0112
-- ‏`app.log_task_event_activity` כותב גם אותם, וזו הסיבה שההתראה נפלטת מסוף
-- ה-RPC ולא מטריגר שורה. שינוי בשעת ההקמה הוא שינוי בפרטי האירוע.
--
-- ===== והלו״ז =============================================================
--
-- עריכת תא בלו״ז אינה עוברת ב-`update_event` — היא `UPDATE tasks` ישיר —
-- ולכן היא מקבלת טריגר משלה. אותה הכרעה, אותו קהל: שעה, משך וכמות עובדים
-- הם בדיוק מה שהאישור מאשר, ולקוח שמזיז אותם מהלוח מזיז אותם באותה מידה.
--
-- ‏`status_id` **אינו** ברשימת העמודות, ובכוונה: מ-0117 הלקוח מזיז משימה
-- בין "טיוטה" ל"מתוכנן", וזה תכנון פנימי שלו — לא שינוי במה שסוכם.

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

  -- ===== הזנב (0112): הלקוח שמר — המנהל שומע. ו-0115: והאישור יורד =====
  if (select app.user_kind()) = 'customer_user' then
    select * into v_ev from events where id = p_event_id;
    select (s.code = 'cancelled') into v_now_cancelled
      from statuses s where s.id = v_ev.status_id;

    -- הגלאי של 0112, אבל **לתוך משתנה ולפני כל כתיבה נוספת של הפונקציה
    -- הזו ליומן**. שלילת האישור שלמטה כותבת שורת יומן משל עצמה (`approved_at`
    -- הוא עמודה נעקבת מאז 0109), ולו נשאל הגלאי אחריה הוא היה עונה "כן"
    -- בגלל עצמו — כל שמירה של לקוח על אירוע מאושר הייתה מדווחת כשינוי,
    -- גם שמירה שלא נגעה בדבר. הסדר כאן הוא ההגנה, לא ההערה.
    v_changed := exists (select 1 from event_activity
                          where event_id = p_event_id
                            and created_at >= transaction_timestamp()
                            and kind <> 'note');

    -- ‏0115: מה שהמשרד אישר אינו מה שעומד עכשיו בטופס.
    --
    -- רק עריכת ה**לקוח** מבטלת. המשרד הוא מי שמאשר, ועריכה שלו אינה סותרת
    -- את עצמה — אילו כל שמירה של מנהל הייתה מורידה את האישור, האישור היה
    -- הופך לצעד שאי אפשר להשלים.
    --
    -- לפני שתי היציאות המוקדמות שמתחת, ובכוונה: ביטול אירוע הוא בעצמו
    -- שינוי, ואירוע מבוטל שנשאר מסומן "מאושר לביצוע" הוא הצירוף היחיד
    -- שנקרא כשטות בלוח השנה.
    --
    -- הכתיבה עטופה ב-system_write מפני ש-app.events_approval_guard (0109)
    -- דוחה כל נגיעה ישירה בשתי העמודות; זו אותה עטיפה שב-set_event_approved.
    if v_changed and v_ev.approved_at is not null then
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

-- ===== 2. והלו״ז, שאינו עובר ב-update_event ===============================
--
-- ‏`after` ולא `before`: איננו משנים את השורה, רק מגיבים לה. ‏`security definer`
-- כדי שהכתיבה ל-`events` תעבור, ו-`app.system_write` כדי שהיא תעבור את
-- ‏`app.events_approval_guard` — אותה עטיפה של `set_event_approved`.
--
-- הדילוגים זהים לאלה של `app.enforce_customer_board_edit` (0109): כתיבה בלי
-- ‏JWT היא מיגרציה, וכתיבה מתוך `system_write` כבר אושרה במעלה הזרם — וזה גם
-- מה שמונע ביטול כפול כשהמקור הוא `update_event`, שעוטף את
-- ‏`apply_event_task_block` ב-system_write משלו.
create or replace function app.tasks_unapprove_event()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then return null; end if;
  if app.in_system_write() then return null; end if;
  if app.user_kind() <> 'customer_user' then return null; end if;
  if new.event_id is null then return null; end if;

  perform app.system_write(true);
  update events set approved_at = null, approved_by = null
   where id = new.event_id and approved_at is not null;
  perform app.system_write(false);
  return null;
end $$;

-- ‏`update of` ולא `update` חשוף: הרשימה היא מה שהאישור מאשר. ‏`updated_at`
-- לבדו אינו שינוי, ו-`status_id` הוא תכנון ולא מפרט (ראו הכותרת).
create trigger tasks_unapprove_event after update of
    task_date, warehouse_start_time, onsite_start_time, hours_count,
    worker_count, execution_method_id, truck_ids, location_text
  on tasks for each row execute function app.tasks_unapprove_event();

comment on function app.tasks_unapprove_event() is
  'עריכת לקוח בלו״ז מורידה את "מאושר לביצוע" מהאירוע (0115), כמו עריכה '
  'בטופס האירוע. סטטוס המשימה אינו ברשימה — הוא תכנון ולא מפרט.';
