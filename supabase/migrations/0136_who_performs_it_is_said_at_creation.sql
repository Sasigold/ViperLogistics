-- 0136: "בוצע ע"י" נבחר כבר בהוספת האירוע, והמעבר מדבר
--
-- שני חצאים של אותו דיווח: **"משימה שהיתה על וייפר והועברה לארקו, וגם אם
-- הועברה מארקו לוויפר — תקפיץ התראה למנהל מערכת. ושיהיה אפשר לבחור ביצוע
-- ע"י ארקו או וויפר כבר בשלב הוספת האירוע."**
--
-- ‏0120 העמידה את הבורר בדף האירוע בלבד — כלומר אחרי שהאירוע כבר נוצר, שתי
-- המשימות כבר נולדו על וייפר, ומישהו צריך לזכור לחזור ולשנות. וכשהוא משנה,
-- איש אינו יודע: `performed_by` אינו ברשימת העמודות של יומן הפעילות (0112)
-- ואין לו סוג התראה. מעבר בין שתי זרועות הביצוע הוא בדיוק הסוג של שינוי
-- שמנהל המערכת צריך לשמוע עליו — הוא מזיז עבודה, ראייה וכסף בבת אחת.

-- ===== 1. שני שדות טופס חדשים ============================================
insert into form_fields (field_key, label_he, sort_order) values
  ('setup_performed_by',    'הקמה — בוצע ע״י',  24),
  ('teardown_performed_by', 'פירוק — בוצע ע״י', 25)
on conflict (field_key) do nothing;

-- ‏app.seed_customer_defaults() רץ רק ללקוח חדש — משלימים לקיימים.
insert into customer_form_fields (customer_id, field_key, state)
select c.id, f.field_key, 'visible'::field_state
from customers c cross join form_fields f
where f.field_key in ('setup_performed_by', 'teardown_performed_by')
on conflict do nothing;

-- ===== 2. הבלוק בטופס האירוע קורא אותם ===================================
--
-- הגוף זהה ל-0111 §2 מילה במילה, בתוספת `k_performed`. השער נכתב **בתוך**
-- הפונקציה, מאותו נימוק בדיוק שכתוב שם על המחיר: היא `security definer`
-- ורצה תחת `app.system_write` מתוך `create_event`, ולכן הפוליסות שמעליה —
-- וגם `set_task_performed_by` (0120) — פוסחות עליה. השאלה שהיא שואלת היא
-- אותה שאלה של 0120: מנהל מערכת, איש צוות עם `tasks.edit`, או משתמש הלקוח
-- על הלקוח שלו — ובכל המקרים רק כשהדגל `performed_by_enabled` דלוק.
--
-- ערך לא חוקי **נדחה** ואינו נדלג: להבדיל ממחיר שנשלח בלי הרשאה (טעות של
-- טיוטה ישנה), 'arko' שאינו 'arko' הוא ערך שהטופס לא יכול היה לייצר.
create or replace function app.apply_event_task_block(p_event_id uuid, p_code text, payload jsonb)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_type    task_types;
  v_event   events;
  v_task_id uuid;
  v_method  uuid;
  v_price   numeric;
  v_perf    text;
  v_enabled boolean;
  k_date    text := p_code || '_date';
  k_time    text := p_code || '_time';
  k_workers text := p_code || '_worker_count';
  k_hours   text := p_code || '_hours_count';
  k_method  text := p_code || '_execution_method';
  k_price   text := p_code || '_price';
  k_perf    text := p_code || '_performed_by';
begin
  if payload is null
     or not (payload ?| array[k_date, k_time, k_workers, k_hours, k_method, k_price, k_perf]) then
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
    -- ‏0111: ערך ריק אינו מוחק את ברירת המחדל שהטריגר מילא בלידה. "בלי אופן
    -- ביצוע" אינו מצב שהטופס יודע לבקש — הוא מציע רשימה, וריק בו פירושו
    -- "לא נגעתי".
    execution_method_id = case when payload ? k_method and nullif(payload ->> k_method, '') is not null
                            then (payload ->> k_method)::uuid else execution_method_id end
  where id = v_task_id;

  -- ‏0136: מי מבצע. כתיבה נפרדת ולא עמודה נוספת ב-update שלמעלה, כי היא
  -- נשענת על הרשאה משלה — ומשום שהיא צריכה לרוץ *אחרי* שהמשימה קיימת ולפני
  -- שדבר אחר נשען עליה.
  if payload ? k_perf then
    v_perf := nullif(payload ->> k_perf, '');
    if v_perf is not null then
      if v_perf not in ('viper', 'arko') then
        raise exception 'ערך לא חוקי לביצוע ע"י';
      end if;
      select coalesce(performed_by_enabled, false) into v_enabled
        from customers where id = v_event.customer_id;
      if not coalesce(v_enabled, false) then
        raise exception 'האפשרות "בוצע ע"י" אינה מופעלת ללקוח זה';
      end if;
      if not (app.is_admin()
              or (app.user_kind() = 'staff' and app.has('tasks.edit'))
              or (app.user_kind() = 'customer_user'
                  and v_event.customer_id = app.customer_id())) then
        raise exception 'אין לך הרשאה לקבוע מי מבצע את המשימה' using errcode = '42501';
      end if;
      update tasks set performed_by = v_perf where id = v_task_id;
    end if;
  end if;

  -- מחיר שהוזן בטופס הוא מחיר של אדם, ולכן הוא נכנס נעול (is_manual) —
  -- אחרת הטריגר שרץ שורה למעלה היה דורס אותו מיד.
  --
  -- שלושה תנאים, ולא אחד (0111): הכותב הוא צוות או מנהל מערכת — אותה שאלה
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

-- ===== 3. היומן שומע את המעבר ============================================
--
-- שני שינויים בפונקציה אחת: איבר רביעי-עשר בשלושת המערכים, ותרגום הערך
-- לעברית ב-`task_value_text` — 'arko' ביומן אינו מילה שמישהו קורא.
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
    when 'performed_by'         then case v when 'arko' then 'ארקו' else 'וייפר' end
    else v
  end;
end $$;

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
            'hours_count','worker_count','execution_method_id','title','performed_by'],
      array['task_date','task_onsite_start_time','task_warehouse_start_time',
            'task_hours_count','task_worker_count','task_execution_method','task_title',
            'task_performed_by'],
      array['תאריך','שעת התחלה בשטח','שעת התחלה במחסן',
            'כמות שעות','כמות עובדים','אופן ביצוע','כותרת','בוצע ע״י']) as t(col, fkey, label)
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

-- הטריגר עצמו לא השתנה ואינו נוצר מחדש.

-- ===== 4. ההתראה למנהלי המערכת ===========================================
--
-- קהל `admin` בלבד: המעבר אינו חדשות לעובד — הוא ממילא מקבל
-- `assignment_removed` כשהשיבוץ שלו יורד (0135) — והוא בהחלט חדשות למי
-- שאחראי על שתי הזרועות. הכותרת נוקבת בכיוון, כי "השתנה" בלי כיוון מחייב
-- לפתוח את המשימה כדי לדעת מה קרה.
select app.register_notification_type('task_performed_by_changed', 'המשימה עברה בין ארקו לוייפר',
  'מי מבצע את המשימה השתנה — לשני הכיוונים', 'משימות',
  array['admin'], 'task', 'forced', 'opt_out', 'opt_in', 22);

create or replace function app.notify_performed_by_changed()
returns trigger language plpgsql security definer set search_path = public as $$
declare r record; v_dir text; v_label text;
begin
  if new.performed_by is not distinct from old.performed_by then return new; end if;
  if not app.notification_in_scope('task_performed_by_changed', 'customer', new.customer_id) then
    return new;
  end if;

  v_dir := case when new.performed_by = 'arko' then 'וייפר ← ארקו' else 'ארקו ← וייפר' end;
  v_label := app.task_notify_label(new);

  for r in select id from profiles
    where is_admin and is_active and deleted_at is null
      and id is distinct from app.profile_id()
  loop
    perform app.notify(r.id, 'task_performed_by_changed',
      'המשימה עברה: ' || v_dir, v_label, 'task', new.id);
  end loop;
  return new;
end $$;

comment on function app.notify_performed_by_changed() is
  'מעבר משימה בין זרועות הביצוע מודיע למנהלי המערכת (0136), לשני הכיוונים.';

-- ‏`after`, ואחרי `tasks_clear_crew_on_arko` (0135) לפי סדר השמות: אם המעבר
-- ייחסם שם על האצלה ששולמה, לא תישלח התראה על מה שלא קרה.
create trigger tasks_z_notify_performed_by after update of performed_by on tasks
  for each row execute function app.notify_performed_by_changed();
