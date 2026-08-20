-- 0105: ריבוי קבלנים — מה שנשאר מחובר לעמודה המשוקפת
--
-- ‏0096 העביר את האמת של ההאצלה ל-`task_contractor_terms` (שורה לכל קבלן),
-- הפך את `tasks.contractor_id` לשיקוף של הקבלן הראשי — מתוחזק בטריגר על
-- ה-terms — והוריד את הטריגר הישן שסינכרן את הכיוון ההפוך. מה שנשאר מאחור הם
-- ארבעה נתיבים שממשיכים לדבר עם העמודה כאילו היא עדיין האמת, וכולם נכשלים
-- בשקט:
--
--   1. **הייבוא מאקסל** כותב `contractor_id` בעמודה, ומאז 0096 הוא אינו מאציל
--      דבר: הקבלן שבקובץ נעלם, ו"מחיר לקבלן" נופל על "נכתב בלי קבלן".
--   2. **`bulk_update_tasks`** מציע `contractor_id` בטלאי — כתיבה לשיקוף,
--      שהטריגר הבא ידרוס.
--   3. **התראת ההאצלה** יושבת על `AFTER UPDATE OF contractor_id ON tasks`,
--      כלומר על השיקוף: הקבלן הראשון מקבל אותה במקרה, הקבלן השני לא מקבל
--      אותה כלל, וביטול האצלה של הראשון שולח אותה למי שכבר קיבל.
--   4. **האריח "משימות לפי קבלן"** בדשבורד סופר דרך השיקוף, ולכן משימה
--      שהואצלה לשניים נספרת אצל אחד.
--
-- ולצדם חור שנפער כשהטריגר הישן ירד: `app.sync_contractor_terms` (0057) היא
-- שחסמה הסרה או החלפה של קבלן ששולם עליו, והיא רצה על אותו UPDATE שנעלם.
-- ‏`contractor_undelegate` בודקת `paid_at` בעצמה, ולכן הנתיב הנתמך מוגן —
-- אבל כתיבה ישירה לעמודה עקפה את הבדיקה ואת האמת גם יחד.

-- ===== 1. העמודה המשוקפת אינה ניתנת לכתיבה ================================
--
-- זו הנקודה שממנה כל השאר נגזר: כל עוד אפשר לכתוב ל-`tasks.contractor_id`,
-- כל קורא צריך לנחש אם הוא מסתכל על אמת או על שריד. הטריגר הופך את העמודה
-- לקריאה בלבד — מלבד השיקוף עצמו, שרץ תחת `app.system_write`.
--
-- הדילוג על קריאה בלי JWT הוא הקונבנציה של `app.enforce_field_perms` (0012):
-- מיגרציות וזריעה רצות כך, ואין להן מה לעקוף.
create or replace function app.guard_task_contractor_mirror()
returns trigger language plpgsql set search_path = public as $$
begin
  if auth.uid() is null or app.in_system_write() then return new; end if;

  if tg_op = 'INSERT' then
    if new.contractor_id is not null then
      raise exception 'האצלה לקבלן נעשית בכרטיס המשימה, לא בעמודה — צרו את המשימה ואז האצילו אותה'
        using errcode = '42501';
    end if;
  elsif new.contractor_id is distinct from old.contractor_id then
    raise exception 'הקבלן במשימה נקבע בהאצלה (task_contractor_terms) ולא בעמודה. הסרת קבלן ששולם עליו חסומה עד ביטול סימון התשלום.'
      using errcode = '42501';
  end if;
  return new;
end $$;

drop trigger if exists tasks_contractor_mirror_guard on tasks;
create trigger tasks_contractor_mirror_guard before insert or update on tasks
  for each row execute function app.guard_task_contractor_mirror();

-- הפונקציה שסינכרנה tasks→terms (0003, 0012, 0057, 0091) כבר אינה מחוברת לשום
-- טריגר מאז 0096, והיא נשארה בסכימה כשריד שאפשר לחבר בטעות. יורדת.
drop function if exists app.sync_contractor_terms();

-- ===== 2. התראת ההאצלה עוברת לשורת ה-terms ================================
--
-- הטריגר על `tasks` יורד *לפני* החלפת גוף הפונקציה, כי הגוף החדש קורא
-- ‏`new.task_id` — שדה שאינו קיים בשורת `tasks`.
drop trigger if exists tasks_notify_contractor on tasks;

create or replace function app.notify_contractor_delegation()
returns trigger language plpgsql security definer set search_path = public as $$
declare r record; v_task tasks; v_label text;
begin
  select * into v_task from tasks where id = new.task_id and deleted_at is null;
  if v_task.id is null then return new; end if;

  v_label := coalesce(nullif(v_task.title, ''),
                      (select tt.name from task_types tt where tt.id = v_task.task_type_id),
                      'משימה');
  for r in select id from profiles
    where contractor_id = new.contractor_id and user_kind = 'contractor_user'
      and is_active and deleted_at is null
  loop
    perform app.notify(r.id, 'contractor_task', 'משימה חדשה הוקצתה לך',
      v_label || ' בתאריך ' || to_char(v_task.task_date, 'DD/MM/YYYY'), 'task', v_task.id);
  end loop;
  return new;
end $$;

drop trigger if exists tct_notify_contractor on task_contractor_terms;
create trigger tct_notify_contractor after insert on task_contractor_terms
  for each row execute function app.notify_contractor_delegation();

comment on function app.notify_contractor_delegation() is
  'התראה לקבלן שהמשימה הואצלה אליו. יושבת על task_contractor_terms מ-0105: '
  'על tasks.contractor_id היא דילגה על הקבלן השני ושלחה כפול לראשון.';

-- ===== 3. עריכה מרובה מאצילה, ולא כותבת לשיקוף ============================
--
-- ‏`contractor_id` בטלאי נשאר חוזה קיים — מה שמשתנה הוא מה שהוא עושה: קבלן
-- מאציל את כל המשימות שנבחרו אליו (בלי לגרוע האצלות קיימות — זו המשמעות
-- היחידה שיש ל"קבלן" כשיכולים להיות כמה), וערך ריק מסיר את כולן. ההסרה
-- עוברת ב-`contractor_undelegate` ולכן היא מכבדת את חסימת התשלום.
create or replace function bulk_update_tasks(p_task_ids uuid[], p_patch jsonb)
returns integer language plpgsql security definer set search_path = public as $$
declare v_count int; v_ctr uuid; v_id uuid; r record;
begin
  perform app.require('tasks.bulk_edit', 'אין לך הרשאה לעריכה מרובה של משימות');
  update tasks set
    task_date            = case when p_patch ? 'task_date' then (p_patch ->> 'task_date')::date else task_date end,
    onsite_start_time    = case when p_patch ? 'onsite_start_time' then (nullif(p_patch ->> 'onsite_start_time',''))::time else onsite_start_time end,
    warehouse_start_time = case when p_patch ? 'warehouse_start_time' then (nullif(p_patch ->> 'warehouse_start_time',''))::time else warehouse_start_time end,
    hours_count          = case when p_patch ? 'hours_count' then (nullif(p_patch ->> 'hours_count',''))::numeric else hours_count end,
    worker_count         = case when p_patch ? 'worker_count' then coalesce((nullif(p_patch ->> 'worker_count',''))::int, 0) else worker_count end,
    execution_method_id  = case when p_patch ? 'execution_method_id' then (nullif(p_patch ->> 'execution_method_id',''))::uuid else execution_method_id end,
    truck_id             = case when p_patch ? 'truck_id' then (nullif(p_patch ->> 'truck_id',''))::uuid else truck_id end,
    truck_free_text      = case when p_patch ? 'truck_free_text' then nullif(p_patch ->> 'truck_free_text','') else truck_free_text end,
    status_id            = case when p_patch ? 'status_id' then (p_patch ->> 'status_id')::uuid else status_id end,
    notes                = case when p_patch ? 'notes' then nullif(p_patch ->> 'notes','') else notes end
  where id = any(p_task_ids) and deleted_at is null;
  get diagnostics v_count = row_count;

  if p_patch ? 'contractor_id' then
    v_ctr := (nullif(p_patch ->> 'contractor_id',''))::uuid;
    foreach v_id in array p_task_ids loop
      if not exists (select 1 from tasks where id = v_id and deleted_at is null) then
        continue;
      end if;
      if v_ctr is null then
        for r in select contractor_id from task_contractor_terms where task_id = v_id loop
          perform contractor_undelegate(v_id, r.contractor_id);
        end loop;
      else
        perform contractor_delegate(v_id, v_ctr);
      end if;
    end loop;
  end if;

  return v_count;
end $$;

revoke execute on function public.bulk_update_tasks(uuid[], jsonb) from anon, public;

-- ===== 4. הייבוא מאקסל מאציל דרך ה-terms ==================================
-- הגוף זהה ל-0076 פרט לשלוש נקודות: העמודה המשוקפת יורדת מה-UPDATE, ההאצלה
-- נכתבת כשורת terms מיד אחריו, ומחיר הקבלן מהקובץ נכתב על השורה של הקבלן
-- שבקובץ (או של הראשי, כשהקובץ לא נקב באחד).
CREATE OR REPLACE FUNCTION app.apply_import_tasks(p_event_id uuid, p_tasks jsonb)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
        travel_hours         = coalesce((nullif(t ->> 'travel_hours', ''))::numeric, travel_hours),
        requires_team_lead   = coalesce(app.import_bool('נדרש ראש צוות', t ->> 'requires_team_lead'),
                                        requires_team_lead),
        truck_free_text      = coalesce(nullif(t ->> 'truck_free_text', ''), truck_free_text),
        location_text        = coalesce(nullif(t ->> 'location_text', ''), location_text),
        notes                = coalesce(nullif(t ->> 'notes', ''), notes)
      where id = v_task_id;

      -- ===== ההאצלה: שורת terms, ולא העמודה =====
      -- ‏0096 העביר את האמת ל-task_contractor_terms והוריד את הטריגר שסינכרן
      -- ‏tasks.contractor_id אליה. הייבוא המשיך לכתוב את העמודה, ומאז לא האציל
      -- דבר: הקבלן שבקובץ נעלם, ו"מחיר לקבלן" נפל על "נכתב בלי קבלן".
      if v_contractor is not null then
        perform app.system_write(true);
        insert into task_contractor_terms (task_id, contractor_id, price)
        values (v_task_id, v_contractor,
                coalesce((select default_task_price from contractors where id = v_contractor), 0))
        on conflict (task_id, contractor_id) do nothing;
        perform app.system_write(false);
        perform app.recompute_contractor_price(v_task_id, v_contractor);
      end if;

      -- ===== הכסף, אחרי שכל הטריגרים של השורה למעלה סיימו =====
      v_price := (nullif(btrim(coalesce(t ->> 'contractor_price', '')), ''))::numeric;
      if v_price is not null then
        select exists (select 1 from task_contractor_terms where task_id = v_task_id)
          into v_has_terms;
        if not v_has_terms then
          raise exception 'מחיר לקבלן נכתב בלי קבלן — יש למלא גם את עמודת "קבלן"';
        end if;
        perform app.system_write(true);
        update task_contractor_terms set price = v_price
         where task_id = v_task_id
           and contractor_id = coalesce(
                 v_contractor,
                 (select tk.contractor_id from tasks tk where tk.id = v_task_id));
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
end $function$;


-- ===== 5. "משימות לפי קבלן" בדשבורד =====================================
-- האריח סופר דרך שורות ה-terms, ולכן משימה שהואצלה לשניים נספרת אצל שניהם.
CREATE OR REPLACE FUNCTION public.dashboard_stats(p_from date, p_to date)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  select jsonb_build_object(
    'events_count', (select count(*) from events
       where deleted_at is null and event_date between p_from and p_to),
    'events_upcoming', (select count(*) from events e
       left join statuses s on s.id = e.status_id
       where e.deleted_at is null and e.event_date >= current_date
         and not coalesce(s.is_terminal, false)),
    'events_done', (select count(*) from events e
       join statuses s on s.id = e.status_id
       where e.deleted_at is null and s.is_terminal
         and e.event_date between p_from and p_to),
    'tasks_count', (select count(*) from tasks
       where deleted_at is null and task_date between p_from and p_to),
    'tasks_open', (select count(*) from tasks t join statuses s on s.id = t.status_id
       where t.deleted_at is null and s.code is distinct from 'assigned'
         and t.task_date between p_from and p_to),
    'tasks_today', (select count(*) from tasks
       where deleted_at is null and task_date = current_date),
    'tasks_week', (select count(*) from tasks
       where deleted_at is null
         and task_date between date_trunc('week', current_date)::date
         and (date_trunc('week', current_date) + interval '6 days')::date),
    'tasks_overdue', (select count(*) from tasks t join statuses s on s.id = t.status_id
       where t.deleted_at is null and t.task_date < current_date
         and s.code is distinct from 'assigned'),
    'available_workers', case when app.has('dashboard.all_workers') then
      (select count(*) from profiles p
         where p.deleted_at is null and p.is_active and p.user_kind = 'staff'
           and not exists (select 1 from task_assignments a join tasks t on t.id = a.task_id
                           where a.profile_id = p.id and t.task_date = current_date
                             and t.deleted_at is null))
      else null end,
    'by_customer', case when app.has('customers.view') then
      (select coalesce(jsonb_agg(row_to_json(x)), '[]') from (
         select c.name, c.color, count(*) as cnt from tasks t join customers c on c.id = t.customer_id
         where t.deleted_at is null and t.task_date between p_from and p_to
         group by c.name, c.color order by cnt desc limit 12) x)
      else null end,
    'by_contractor', case when app.has('dashboard.contractors') then
      (select coalesce(jsonb_agg(row_to_json(x)), '[]') from (
         -- 0105: דרך שורות ה-terms ולא דרך העמודה המשוקפת — משימה שהואצלה
         -- לשני קבלנים נספרת אצל שניהם, וזו בדיוק השאלה שהאריח שואל.
         select ct.name, count(*) as cnt
           from task_contractor_terms tct
           join tasks t on t.id = tct.task_id
           join contractors ct on ct.id = tct.contractor_id
         where t.deleted_at is null and t.task_date between p_from and p_to
         group by ct.name order by cnt desc limit 12) x)
      else null end,
    'by_worker', case when app.has('dashboard.all_workers') then
      (select coalesce(jsonb_agg(row_to_json(x)), '[]') from (
         select p.full_name as name, count(*) as cnt
         from task_assignments a
         join tasks t on t.id = a.task_id and t.deleted_at is null
           and t.task_date between p_from and p_to
         join profiles p on p.id = a.profile_id
         group by p.full_name order by cnt desc limit 12) x)
      else null end,
    'financial', case when app.has('dashboard.financial') then
      (select jsonb_build_object(
         'expected', coalesce(sum(tct.price), 0),
         'paid', coalesce(sum(tct.paid_amount) filter (where tct.paid_at is not null), 0))
       from task_contractor_terms tct
       join tasks t on t.id = tct.task_id and t.deleted_at is null
        and t.task_date between p_from and p_to)
      else null end,
    'revenue', case when app.has('pricing.revenue') then
      (select jsonb_build_object(
         'total', coalesce(sum(tp.price), 0)
                  + coalesce((select sum(ei.amount)
                                from event_income ei
                                join events e on e.id = ei.event_id and e.deleted_at is null
                               where e.event_date between p_from and p_to), 0),
         'priced_tasks', count(*) filter (where tp.price is not null),
         'by_customer', case when app.has('customers.view') then
           (select coalesce(jsonb_agg(row_to_json(y) order by y.total desc), '[]') from (
              select u.name, u.color, round(sum(u.total), 2) as total from (
                select c.name, c.color, coalesce(sum(tp2.price), 0) as total
                from task_pricing tp2
                join tasks t2 on t2.id = tp2.task_id and t2.deleted_at is null
                 and t2.task_date between p_from and p_to
                join customers c on c.id = t2.customer_id
                group by c.name, c.color
                union all
                select c.name, c.color, coalesce(sum(ei2.amount), 0)
                from event_income ei2
                join events e2 on e2.id = ei2.event_id and e2.deleted_at is null
                 and e2.event_date between p_from and p_to
                join customers c on c.id = e2.customer_id
                group by c.name, c.color) u
              group by u.name, u.color order by 3 desc limit 12) y)
           else null end)
       from task_pricing tp
       join tasks t on t.id = tp.task_id and t.deleted_at is null
        and t.task_date between p_from and p_to)
      else null end,
    'by_status', (select coalesce(jsonb_agg(row_to_json(x)), '[]') from (
       select s.name, s.color, count(*) as cnt from tasks t join statuses s on s.id = t.status_id
       where t.deleted_at is null and t.task_date between p_from and p_to
       group by s.name, s.color order by cnt desc) x),
    'next_events', (select coalesce(jsonb_agg(row_to_json(x)), '[]') from (
       select e.id, e.event_date, e.end_client_name, e.event_number, e.location_text
       from events e
       where e.deleted_at is null and e.event_date >= current_date
       order by e.event_date limit 5) x))
$function$;


revoke execute on function public.dashboard_stats(date, date) from anon, public;

-- ===== 6. ההאצלה נבדקת מעל ה-RLS של טבלת הכסף ============================
--
-- ‏0098 העביר את זרועות הקבלן בפוליסות לבדיקת `exists` על
-- ‏`task_contractor_terms`. השורה הזאת נושאת מחירים, ולכן `tct_select` פותחת
-- אותה רק למי שמחזיק `contractors.view_pricing` — והתפקיד `contractor_worker`
-- סוגר את המודול כולו. תת-שאילתה בתוך פוליסה נשפטת תחת ה-RLS של הקורא, ולכן
-- ה-`exists` החזיר `false` לעובד הקבלן: **המשימות שלו נעלמו לו מהלוח**, ואיתן
-- המשמרת שנגזרת מהן.
--
-- לפני 0096 הבדיקה הייתה `tasks.contractor_id = app.contractor_id()` — עמודה
-- על אותה שורה, בלי RLS משלה — ולכן הבעיה נולדה עם המעבר ל-terms.
--
-- ‏`app.assignment_on_my_contractor` (0098 §עוזרי הראייה) שואלת בדיוק את אותה
-- שאלה והיא `security definer`, ולכן היא רואה את שורת ה-terms בלי לפתוח את
-- המחירים שבה. שאר הגוף זהה ל-0098.
drop policy tasks_select on tasks;
create policy tasks_select on tasks for select to authenticated using (
  (select app.is_admin())
  or (deleted_at is null
    and ((select app.scope_ids('tasks', 'customers')) is null
         or customer_id = any((select app.scope_ids('tasks', 'customers'))::uuid[]))
    and ((select app.scope_ids('tasks', 'contractors')) is null
         or contractor_id = any((select app.scope_ids('tasks', 'contractors'))::uuid[]))
    and ((select app.scope_ids('tasks', 'task_types')) is null
         or task_type_id = any((select app.scope_ids('tasks', 'task_types'))::uuid[]))
    and ((select app.scope_ids('tasks', 'statuses')) is null
         or status_id = any((select app.scope_ids('tasks', 'statuses'))::uuid[]))
    and ((select app.scope_ids('tasks', 'execution_methods')) is null
         or execution_method_id = any((select app.scope_ids('tasks', 'execution_methods'))::uuid[]))
    and ((select app.scope_ids('tasks', 'trucks')) is null
         or truck_id = any((select app.scope_ids('tasks', 'trucks'))::uuid[]))
    and ((select app.scope_date_from('tasks')) is null
         or task_date >= (select app.scope_date_from('tasks')))
    and ((select app.scope_date_to('tasks')) is null
         or task_date <= (select app.scope_date_to('tasks')))
    and (not (select app.scope_own('tasks'))
         or exists (select 1 from task_assignments a
                    where a.task_id = tasks.id and a.profile_id = (select app.profile_id()))
         or ((select app.user_kind()) <> 'staff'
             and created_by = (select app.profile_id())))
    and ((select app.user_kind()) <> 'staff'
         or (select app.can_plan_tasks())
         or (created_by = (select app.profile_id())
             and not (select app.scope_own('tasks')))
         or status_id = (select s.id from statuses s
                          where s.entity = 'task' and s.code = 'assigned'
                            and s.deleted_at is null limit 1))
    and (
      ((select app.user_kind()) = 'staff' and (select app.has('tasks.view')))
      or ((select app.user_kind()) = 'customer_user' and customer_id = (select app.customer_id()))
      or ((select app.user_kind()) = 'contractor_user'
          and (select app.assignment_on_my_contractor(tasks.id))
          and ((select app.has('portal.view'))
               or (status_id = (select s.id from statuses s
                                 where s.entity = 'task' and s.code = 'assigned'
                                   and s.deleted_at is null limit 1)
                   and (select app.on_task_as_contractor_worker(tasks.id)))))
      or exists (select 1 from task_assignments a
                 where a.task_id = tasks.id and a.profile_id = (select app.profile_id()))
    )));

-- אותה הצרה בטבלת עובדי הקבלן: העובד לא ראה מי עוד רשום איתו על המשימה.
drop policy if exists tcw_select on task_contractor_workers;
create policy tcw_select on task_contractor_workers for select to authenticated using (
  (select app.is_admin())
  or ((select app.user_kind()) = 'staff'
      and ((select app.has_permission('tasks','view'))
           or (select app.has_permission('contractors','view'))))
  or (select app.assignment_on_my_contractor(task_id)));
