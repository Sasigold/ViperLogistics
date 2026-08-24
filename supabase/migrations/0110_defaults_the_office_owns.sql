-- 0110: שלוש ברירות מחדל שהמשרד מחזיק, ומי שמולן אינו בוחר
--
-- אותו קו של 0109, בשלוש נקודות נוספות שבהן המערכת שאלה שאלה שכבר יש לה
-- תשובה — או נתנה לצד הלא נכון לענות עליה:
--
--   1. **אופן ביצוע ברירת מחדל פר לקוח.** ‏`customer_execution_methods` ידעה
--      *אילו* אופנים מותרים ללקוח, ולא איזה מהם הרגיל. כל משימה חדשה נולדה
--      בלי אופן ביצוע, ומישהו מילא אותו ידנית בכל פעם מחדש.
--   2. **מחיר המשימה מתוך טופס האירוע.** ‏`app.apply_event_task_block` (0017)
--      היא `security definer`, ולכן היא **עוקפת** את `tp_write` שהוצרה ב-0109
--      — היא שאלה `pricing.edit` לבדה, כלומר בדיוק את השאלה שאותה מיגרציה
--      קבעה שאינה מספיקה. זו הדלת האחורית של אותו איסור.
--   3. **נקודת ההתחלה של עובדי הקבלן.** ה-RPC קיבל `p_work_site` מהקורא
--      ונפל חזרה לשורת ה-terms רק כשהוא היה `null`. הקבלן שלח משם ערך, ובכך
--      דרס את מה שהמשרד קבע לו.

-- ===== 1. אופן ביצוע ברירת מחדל פר לקוח ===================================
--
-- דגל על שורת ההרשאה ולא עמודה על `customers`, משתי סיבות: ברירת המחדל
-- **חייבת** להיות אחד מהאופנים שהותרו ללקוח, וה-FK הזה כבר קיים בשורה; וכשמסירים
-- ללקוח אופן ביצוע, הדגל יורד איתו במקום להישאר מצביע על מה שכבר אינו מותר.
alter table customer_execution_methods
  add column if not exists is_default boolean not null default false;

create unique index cem_one_default
  on customer_execution_methods (customer_id) where is_default;

comment on column customer_execution_methods.is_default is
  'אופן הביצוע שכל משימה חדשה של הלקוח נולדת איתו (0110). אחד לכל היותר.';

-- טריגר ולא מילוי ב-RPC אחד: משימה נוצרת מטופס האירוע, מהמשימות האוטומטיות,
-- מהייבוא, מהלו״ז ומכרטיס המשימה — וברירת מחדל שמכירה רק חלק מהדלתות אינה
-- ברירת מחדל. ‏BEFORE INSERT, ולכן היא נכנסת לפני שמנוע המחיר (AFTER) קורא
-- את השורה, והמחיר הראשון כבר מחושב לפי האופן הנכון.
--
-- החיתוך נשמר: אופן שאינו פעיל, או שאינו מותר לסוג המשימה הזה, אינו נבחר —
-- אחרת הטריגר היה כותב ערך ש-`app.apply_event_task_block` דוחה בעצמה.
create or replace function app.tasks_default_execution_method()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.execution_method_id is not null or new.customer_id is null then
    return new;
  end if;
  select cem.execution_method_id into new.execution_method_id
    from customer_execution_methods cem
    join execution_methods m on m.id = cem.execution_method_id
   where cem.customer_id = new.customer_id
     and cem.is_default
     and m.is_active and m.deleted_at is null
     and (new.task_type_id is null
          or exists (select 1 from task_type_execution_methods ttm
                      where ttm.execution_method_id = cem.execution_method_id
                        and ttm.task_type_id = new.task_type_id))
   limit 1;
  return new;
end $$;

create trigger tasks_default_method before insert on tasks
  for each row execute function app.tasks_default_execution_method();

-- ===== 2. מחיר המשימה אינו נכתב מטופס האירוע בידי הלקוח ===================
--
-- הגוף זהה ל-0017 §14 פרט לבלוק המחיר, ושם שני שינויים:
--
--   * **מי כותב.** אותה שאלה ש-`tp_write` שואלת מאז 0109 — מנהל מערכת, או
--     איש צוות עם `pricing.edit`. פונקציית `security definer` שנשענת על מפתח
--     לבדו היא פרצה בפוליסה שמעליה, לא קיצור דרך.
--   * **מה מותר לשלוח.** שדה שהוגדר `hidden` ללקוח הזה אינו נכתב גם בשביל
--     הצוות. ההערה המקורית כאן כבר ידעה ששדה מוסתר "עשוי בכל זאת להישלח
--     מטיוטה שנשמרה ב-localStorage" — ומה שנשלח מטיוטה נכתב. מעכשיו
--     ההסתרה בכרטיס הלקוח היא גם החסימה, וזו הדרך שבה מנהל המערכת חוסם
--     עריכת מחיר ללקוח מסוים.
create or replace function app.apply_event_task_block(p_event_id uuid, p_code text, payload jsonb)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_type    task_types;
  v_event   events;
  v_task_id uuid;
  v_method  uuid;
  v_price   numeric;
  k_date    text := p_code || '_date';
  k_time    text := p_code || '_time';
  k_workers text := p_code || '_worker_count';
  k_hours   text := p_code || '_hours_count';
  k_method  text := p_code || '_execution_method';
  k_price   text := p_code || '_price';
begin
  if payload is null
     or not (payload ?| array[k_date, k_time, k_workers, k_hours, k_method, k_price]) then
    return;
  end if;

  select * into v_type from task_types
    where code = p_code and is_active and deleted_at is null;
  if v_type.id is null then return; end if;  -- type disabled in settings — nothing to fill

  select * into v_event from events where id = p_event_id;
  if v_event.id is null then raise exception 'אירוע לא נמצא'; end if;

  -- אופן ביצוע חייב להיות בחיתוך: פעיל ∩ מותר לסוג המשימה ∩ מותר ללקוח
  if payload ? k_method then
    v_method := (nullif(payload ->> k_method, ''))::uuid;
    if v_method is not null and not exists (
         select 1 from execution_methods m
         join task_type_execution_methods ttm
           on ttm.execution_method_id = m.id and ttm.task_type_id = v_type.id
         join customer_execution_methods cem
           on cem.execution_method_id = m.id and cem.customer_id = v_event.customer_id
         where m.id = v_method and m.is_active and m.deleted_at is null)
    then
      raise exception 'אופן הביצוע שנבחר אינו זמין עבור % אצל לקוח זה', v_type.name;
    end if;
  end if;

  select t.id into v_task_id from tasks t
   where t.event_id = p_event_id and t.task_type_id = v_type.id and t.deleted_at is null
   order by t.created_at, t.id limit 1;

  -- המשימה נמחקה או שלא נוצרה אוטומטית — יוצרים אותה מחדש
  if v_task_id is null then
    insert into tasks (event_id, customer_id, task_type_id, task_date, status_id, worker_count, created_by)
    values (p_event_id, v_event.customer_id, v_type.id,
            coalesce((nullif(payload ->> k_date, ''))::date, v_event.event_date),
            (select id from statuses where entity = 'task' and is_default and deleted_at is null limit 1),
            0, app.profile_id())
    returning id into v_task_id;
  end if;

  update tasks set
    task_date           = case when payload ? k_date
                            then coalesce((nullif(payload ->> k_date, ''))::date, task_date)
                            else task_date end,
    onsite_start_time   = case when payload ? k_time
                            then (nullif(payload ->> k_time, ''))::time else onsite_start_time end,
    hours_count         = case when payload ? k_hours
                            then (nullif(payload ->> k_hours, ''))::numeric else hours_count end,
    worker_count        = case when payload ? k_workers
                            then coalesce((nullif(payload ->> k_workers, ''))::int, 0) else worker_count end,
    -- ‏0110: ערך ריק אינו מוחק את ברירת המחדל שהטריגר מילא בלידה. "בלי אופן
    -- ביצוע" אינו מצב שהטופס יודע לבקש — הוא מציע רשימה, וריק בו פירושו
    -- "לא נגעתי".
    execution_method_id = case when payload ? k_method and nullif(payload ->> k_method, '') is not null
                            then (payload ->> k_method)::uuid else execution_method_id end
  where id = v_task_id;

  -- מחיר שהוזן בטופס הוא מחיר של אדם, ולכן הוא נכנס נעול (is_manual) —
  -- אחרת הטריגר שרץ שורה למעלה היה דורס אותו מיד.
  --
  -- שלושה תנאים, ולא אחד (0110): הכותב הוא צוות או מנהל מערכת — אותה שאלה
  -- ש-`tp_write` שואלת, כי `security definer` כאן פוסחת עליה; המפתח בידו;
  -- והשדה לא הוסתר ללקוח הזה. בלי אחד מהם הכתיבה נדלגת בשקט ולא נופלת:
  -- שדה שאינו גלוי עשוי בכל זאת להישלח מטיוטה שנשמרה ב-localStorage, וזו
  -- לא סיבה להפיל יצירת אירוע — אבל היא בהחלט סיבה לא לכתוב.
  if payload ? k_price
     and app.user_kind() = 'staff'
     and (app.is_admin() or app.has('pricing.edit'))
     and coalesce((select state from customer_form_fields
                    where customer_id = v_event.customer_id and field_key = k_price),
                  'visible'::field_state) <> 'hidden'
  then
    v_price := (nullif(payload ->> k_price, ''))::numeric;
    if v_price is not null then
      insert into task_pricing (task_id, price, is_manual, breakdown, calculated_at)
      values (v_task_id, v_price, true, null, now())
      on conflict (task_id) do update
        set price = excluded.price, is_manual = true, breakdown = null;
    end if;
  end if;
end $$;

-- ===== 3. עובדי הקבלן מתחילים מאיפה שנקבע לקבלן ===========================
--
-- נקודת ההתחלה היא החלטה תפעולית של המשרד: היא קובעת את שעת ההתחלה במשמרת
-- ואת המיקום שמולו נמדדת ההחתמה, ולכן היא גם מזיזה כסף. היא נקבעת פעם אחת
-- על שורת ההאצלה, ועובדי הקבלן יורשים אותה — זה מה ש-0091 כתבה, ומה שה-RPC
-- אפשר לעקוף.
--
-- הפרמטר נשאר בחתימה ולא נמחק: למשרד יש שימוש אמיתי בדריסה נקודתית, ומחיקתו
-- הייתה שוברת את הקוראים הקיימים. מה שמשתנה הוא מי רשאי לנקוב בו — מי שאין
-- לו את המפתח המשרדי מקבל את שורת ה-terms, ולא שגיאה: הוא לא ביקש דבר חורג,
-- הוא פשוט אינו הצד שמחליט.
create or replace function contractor_assign_worker(
  p_task_id uuid,
  p_worker_id uuid default null,
  p_profile_id uuid default null,
  p_on boolean default true,
  p_work_site text default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_ctr    uuid;
  v_mine   uuid := app.contractor_id();
  v_worker uuid := p_worker_id;
  v_prof   profiles%rowtype;
  v_site   text := p_work_site;
begin
  if not (app.has('portal.assign_workers') or app.has('contractors.assign_workers')) then
    raise exception 'אין לך הרשאה לשבץ עובדי קבלן' using errcode = '42501';
  end if;

  -- פתרון העובד והקבלן שלו.
  if v_worker is null then
    if p_profile_id is null then
      raise exception 'חובה לנקוב בעובד או בחשבון' using errcode = '22023';
    end if;
    select * into v_prof from profiles where id = p_profile_id and deleted_at is null;
    if v_prof.id is null then
      raise exception 'העובד לא נמצא' using errcode = '42501';
    end if;
    v_ctr := v_prof.contractor_id;
    v_worker := v_prof.contractor_worker_id;
    if v_worker is null then
      if v_ctr is null then
        raise exception 'לחשבון אין קבלן משויך' using errcode = '42501';
      end if;
      insert into contractor_workers (contractor_id, full_name, phone)
      values (v_ctr, v_prof.full_name, v_prof.phone)
      returning id into v_worker;
      update profiles set contractor_worker_id = v_worker where id = v_prof.id;
    end if;
  else
    select contractor_id into v_ctr from contractor_workers
     where id = v_worker and deleted_at is null;
  end if;
  if v_ctr is null then
    raise exception 'לא נמצא קבלן לעובד' using errcode = '42501';
  end if;

  -- המשימה חייבת להיות מואצלת לקבלן של העובד.
  if not exists (select 1 from task_contractor_terms
                  where task_id = p_task_id and contractor_id = v_ctr) then
    raise exception 'המשימה אינה מואצלת לקבלן של העובד' using errcode = '42501';
  end if;

  -- קבלן משבץ רק את עובדיו; איש משרד צריך את המפתח המשרדי לקבלן אחר.
  if v_ctr is distinct from v_mine then
    perform app.require('contractors.assign_workers');
  end if;

  -- ‏0110: נקודת ההתחלה היא של המשרד. בלי המפתח המשרדי מה שנשלח מהקורא
  -- נזרק, ושורת ההאצלה היא שקובעת — תמיד, ולא רק כשלא נשלח דבר.
  if not app.has('contractors.assign_workers') then
    v_site := null;
  end if;
  if v_site is null then
    select coalesce(work_site, 'field') into v_site
      from task_contractor_terms where task_id = p_task_id and contractor_id = v_ctr;
    v_site := coalesce(v_site, 'field');
  end if;
  if v_site not in ('field', 'warehouse') then
    raise exception 'אתר עבודה לא חוקי: %', v_site using errcode = '22023';
  end if;

  if p_on then
    insert into task_contractor_workers (task_id, contractor_worker_id, work_site)
    values (p_task_id, v_worker, v_site)
    on conflict (task_id, contractor_worker_id) do update set work_site = excluded.work_site;
  else
    delete from task_contractor_workers
     where task_id = p_task_id and contractor_worker_id = v_worker;
  end if;

  return v_worker;
end $$;

revoke execute on function
  public.contractor_assign_worker(uuid, uuid, uuid, boolean, text) from anon, public;

-- שינוי נקודת ההתחלה על שורת ההאצלה מחיל אותה על עובדי אותו קבלן (0097),
-- וזה מה שהופך את הכלל שלמעלה לשלם: המשרד מזיז את השורה, והעובדים זזים איתה.
