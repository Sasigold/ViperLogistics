-- 0101: סנכרון און-ליין של המשימות והאירועים — לקהל הרלוונטי בלבד
--
-- הדרישה: שינוי שמשתמש אחד עושה במשימה או באירוע יופיע אצל המחוברים האחרים
-- בלי רענון ידני. אבל לא שידור לכולם: עובד שמחובר ואינו משובץ למשימה — האות
-- לא מגיע אליו כלל, ומשתמש לקוח/קבלן שומע רק על מה ששלו.
--
-- למה broadcast ולא postgres_changes: השייכות של משימה לעובד יושבת
-- ב-task_assignments ולא בעמודה על tasks, ולכן אין לה ביטוי כ-filter של
-- postgres_changes; ו-tasks_select (0083) היא פוליסה כבדה ש-Realtime היה מריץ
-- מחדש לכל מנוי על כל שינוי. כאן הקהל מחושב פעם אחת, בתוך טרנזקציית הכתיבה,
-- וההרשאה לערוץ נבדקת פעם אחת בהצטרפות (RLS על realtime.messages).
--
-- ההודעה היא אות בלבד — ישות, סוג, מזהים, ומי כתב — בלי נתונים. הלקוח שמקבל
-- אותה מרענן את השאילתות הפעילות שלו דרך work_board_view, שמפעיל מחדש את
-- ה-RLS המדויק. לכן אות שמגיע למי שרואה רק חלק מהעמודות אינו מדליף דבר.
--
-- הערוצים:
--   sync:profile:<id>    — כל מחובר; משימות שהוא משובץ אליהן, ושיבוץ/הסרה שלו
--   sync:customer:<id>   — משתמשי הלקוח, וסגל שהיקפו מוגבל ללקוחות אלה
--   sync:contractor:<id> — משתמשי הקבלן, וסגל שהיקפו מוגבל לקבלנים אלה
--   sync:staff           — אדמין וסגל בלי היקף מגביל (הסדרנים) — כל שינוי
--
-- הטריגרים הם ברמת המשפט (transition tables): ייבוא אקסל שמכניס מאות משימות
-- במשפט אחד שולח הודעה אחת לכל ערוץ, לא מאות.

-- ===== חישוב הקהל =====

-- כל הערוצים שמשימה נתונה מעניינת: הסדרנים, הלקוח, הקבלנים שהיא הואצלה
-- אליהם (task_contractor_terms מאז 0096; ‏p_contractor הוא שיקוף הקבלן הראשי,
-- שנשאר כרשת ביטחון למחיקה קשיחה שה-cascade כבר גרף את ה-terms שלה), וכל מי
-- שמשובץ — סגל דרך task_assignments, ועובד קבלן עם חשבון דרך
-- contractor_workers.user_id.
create or replace function app.task_sync_topics(p_id uuid, p_customer uuid, p_contractor uuid)
returns text[] language sql stable security definer set search_path = public as $$
  select array['sync:staff']
      || case when p_customer   is not null then array['sync:customer:'   || p_customer]   else '{}'::text[] end
      || case when p_contractor is not null then array['sync:contractor:' || p_contractor] else '{}'::text[] end
      || coalesce((select array_agg(distinct 'sync:contractor:' || tct.contractor_id)
                   from task_contractor_terms tct where tct.task_id = p_id), '{}'::text[])
      || coalesce((select array_agg(distinct 'sync:profile:' || a.pid)
                   from (select ta.profile_id as pid
                           from task_assignments ta where ta.task_id = p_id
                         union
                         select p.id
                           from task_contractor_workers tcw
                           join contractor_workers cw on cw.id = tcw.contractor_worker_id
                           join profiles p on p.user_id = cw.user_id
                          where tcw.task_id = p_id) a), '{}'::text[])
$$;

-- הקהל של אירוע: הסדרנים, הלקוח, והקבלנים והמשובצים של המשימות שלו — כי שינוי
-- באירוע (תאריך, מיקום) משנה את שורות הלו״ז שכולם רואים. חסום מלמעלה: לאירוע
-- קומץ משימות.
create or replace function app.event_sync_topics(p_id uuid, p_customer uuid)
returns text[] language sql stable security definer set search_path = public as $$
  select array['sync:staff']
      || case when p_customer is not null then array['sync:customer:' || p_customer] else '{}'::text[] end
      || coalesce((select array_agg(distinct 'sync:contractor:' || tct.contractor_id)
                   from task_contractor_terms tct
                   join tasks t on t.id = tct.task_id
                  where t.event_id = p_id), '{}'::text[])
      || coalesce((select array_agg(distinct 'sync:profile:' || a.pid)
                   from (select ta.profile_id as pid
                           from task_assignments ta
                           join tasks t on t.id = ta.task_id
                          where t.event_id = p_id
                         union
                         select p.id
                           from task_contractor_workers tcw
                           join tasks t on t.id = tcw.task_id
                           join contractor_workers cw on cw.id = tcw.contractor_worker_id
                           join profiles p on p.user_id = cw.user_id
                          where t.event_id = p_id) a), '{}'::text[])
$$;

-- שליחה אחת לכל ערוץ, בלי כפילויות; ואם Realtime אינו זמין — הכתיבה עצמה
-- אינה נכשלת. האות הוא שיפור חוויה, לא תנאי לשמירה.
create or replace function app.sync_send(p_topics text[], p_payload jsonb)
returns void language plpgsql security definer set search_path = public as $$
declare t text;
begin
  if p_topics is null then return; end if;
  for t in select distinct x from unnest(p_topics) x where x is not null loop
    perform realtime.send(p_payload, 'sync', t, true);
  end loop;
exception when others then null;
end $$;

revoke execute on function app.task_sync_topics(uuid, uuid, uuid) from anon, public;
revoke execute on function app.event_sync_topics(uuid, uuid) from anon, public;
revoke execute on function app.sync_send(text[], jsonb) from anon, public;

-- ===== משימות =====

-- INSERT ו-UPDATE ו-DELETE נבדלים רק בטבלאות המעבר הזמינות להם, ולכן שלושתם
-- עוברים דרך גוף אחד. ב-UPDATE נשלח איחוד הקהל הישן והחדש: משימה שעברה לקבלן
-- אחר מאותתת גם למי שאיבד אותה, כדי שהיא תיעלם מהמסך שלו.
create or replace function app.tasks_sync_ins() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_topics text[]; v_ids uuid[]; v_events uuid[];
begin
  select array_agg(distinct s.t),
         array_agg(distinct s.id),
         array_agg(distinct s.event_id) filter (where s.event_id is not null)
    into v_topics, v_ids, v_events
    from (select r.id, r.event_id,
                 unnest(app.task_sync_topics(r.id, r.customer_id, r.contractor_id)) as t
            from new_rows r) s;
  if v_ids is not null then
    perform app.sync_send(v_topics, jsonb_build_object(
      'v', 1, 'entity', 'task', 'kind', 'insert',
      'ids', to_jsonb(v_ids), 'event_ids', to_jsonb(coalesce(v_events, '{}'::uuid[])),
      'actor', app.profile_id()));
  end if;
  return null;
end $$;

create or replace function app.tasks_sync_upd() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_topics text[]; v_ids uuid[]; v_events uuid[];
begin
  select array_agg(distinct s.t),
         array_agg(distinct s.id),
         array_agg(distinct s.event_id) filter (where s.event_id is not null)
    into v_topics, v_ids, v_events
    from (select r.id, r.event_id,
                 unnest(app.task_sync_topics(r.id, r.customer_id, r.contractor_id)) as t
            from new_rows r
          union all
          select r.id, r.event_id,
                 unnest(app.task_sync_topics(r.id, r.customer_id, r.contractor_id)) as t
            from old_rows r) s;
  if v_ids is not null then
    perform app.sync_send(v_topics, jsonb_build_object(
      'v', 1, 'entity', 'task', 'kind', 'update',
      'ids', to_jsonb(v_ids), 'event_ids', to_jsonb(coalesce(v_events, '{}'::uuid[])),
      'actor', app.profile_id()));
  end if;
  return null;
end $$;

-- מחיקה קשיחה נדירה (soft_delete מגיע כ-UPDATE), אבל כשהיא קורית — השיבוצים
-- כבר נמחקו ב-cascade, ולכן task_sync_topics לא ימצא אותם; הלקוח והקבלן עדיין
-- על השורה הישנה, והסדרנים תמיד שומעים.
create or replace function app.tasks_sync_del() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_topics text[]; v_ids uuid[]; v_events uuid[];
begin
  select array_agg(distinct s.t),
         array_agg(distinct s.id),
         array_agg(distinct s.event_id) filter (where s.event_id is not null)
    into v_topics, v_ids, v_events
    from (select r.id, r.event_id,
                 unnest(app.task_sync_topics(r.id, r.customer_id, r.contractor_id)) as t
            from old_rows r) s;
  if v_ids is not null then
    perform app.sync_send(v_topics, jsonb_build_object(
      'v', 1, 'entity', 'task', 'kind', 'delete',
      'ids', to_jsonb(v_ids), 'event_ids', to_jsonb(coalesce(v_events, '{}'::uuid[])),
      'actor', app.profile_id()));
  end if;
  return null;
end $$;

drop trigger if exists tasks_sync_ins on tasks;
create trigger tasks_sync_ins after insert on tasks
  referencing new table as new_rows
  for each statement execute function app.tasks_sync_ins();
drop trigger if exists tasks_sync_upd on tasks;
create trigger tasks_sync_upd after update on tasks
  referencing old table as old_rows new table as new_rows
  for each statement execute function app.tasks_sync_upd();
drop trigger if exists tasks_sync_del on tasks;
create trigger tasks_sync_del after delete on tasks
  referencing old table as old_rows
  for each statement execute function app.tasks_sync_del();

-- ===== אירועים =====

create or replace function app.events_sync_ins() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_topics text[]; v_ids uuid[];
begin
  select array_agg(distinct s.t), array_agg(distinct s.id)
    into v_topics, v_ids
    from (select r.id, unnest(app.event_sync_topics(r.id, r.customer_id)) as t
            from new_rows r) s;
  if v_ids is not null then
    perform app.sync_send(v_topics, jsonb_build_object(
      'v', 1, 'entity', 'event', 'kind', 'insert',
      'ids', to_jsonb(v_ids), 'actor', app.profile_id()));
  end if;
  return null;
end $$;

create or replace function app.events_sync_upd() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_topics text[]; v_ids uuid[];
begin
  select array_agg(distinct s.t), array_agg(distinct s.id)
    into v_topics, v_ids
    from (select r.id, unnest(app.event_sync_topics(r.id, r.customer_id)) as t
            from new_rows r
          union all
          select r.id, unnest(app.event_sync_topics(r.id, r.customer_id)) as t
            from old_rows r) s;
  if v_ids is not null then
    perform app.sync_send(v_topics, jsonb_build_object(
      'v', 1, 'entity', 'event', 'kind', 'update',
      'ids', to_jsonb(v_ids), 'actor', app.profile_id()));
  end if;
  return null;
end $$;

create or replace function app.events_sync_del() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_topics text[]; v_ids uuid[];
begin
  select array_agg(distinct s.t), array_agg(distinct s.id)
    into v_topics, v_ids
    from (select r.id, unnest(app.event_sync_topics(r.id, r.customer_id)) as t
            from old_rows r) s;
  if v_ids is not null then
    perform app.sync_send(v_topics, jsonb_build_object(
      'v', 1, 'entity', 'event', 'kind', 'delete',
      'ids', to_jsonb(v_ids), 'actor', app.profile_id()));
  end if;
  return null;
end $$;

drop trigger if exists events_sync_ins on events;
create trigger events_sync_ins after insert on events
  referencing new table as new_rows
  for each statement execute function app.events_sync_ins();
drop trigger if exists events_sync_upd on events;
create trigger events_sync_upd after update on events
  referencing old table as old_rows new table as new_rows
  for each statement execute function app.events_sync_upd();
drop trigger if exists events_sync_del on events;
create trigger events_sync_del after delete on events
  referencing old table as old_rows
  for each statement execute function app.events_sync_del();

-- ===== שיבוצים =====
--
-- השיבוץ הוא הדרך שבה עובד לומד שמשימה נהייתה שלו — או חדלה להיות שלו. ולכן
-- הערוץ האישי של מי שנוסף/הוסר מקבל את האות במפורש, גם כשהשורה כבר איננה
-- (ב-DELETE ‏task_sync_topics כבר לא רואה אותו). שאר קהל המשימה שומע גם הוא:
-- שמות המשובצים מצוירים בלו״ז של כולם.

create or replace function app.ta_sync_topics_of(p_task uuid)
returns text[] language sql stable security definer set search_path = public as $$
  select coalesce((select app.task_sync_topics(t.id, t.customer_id, t.contractor_id)
                     from tasks t where t.id = p_task), array['sync:staff'])
$$;
revoke execute on function app.ta_sync_topics_of(uuid) from anon, public;

create or replace function app.assignments_sync() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_topics text[]; v_ids uuid[]; v_events uuid[];
begin
  -- הפונקציה משרתת את שלושת הטריגרים: ב-INSERT קיימת רק new_rows, ב-DELETE רק
  -- old_rows, וב-UPDATE שתיהן — ולכן ההצבה דרך משתני ה-TG.
  if tg_op in ('INSERT', 'UPDATE') then
    select array_agg(distinct s.t), array_agg(distinct s.task_id)
      into v_topics, v_ids
      from (select r.task_id, 'sync:profile:' || r.profile_id as t from new_rows r
            union all
            select r.task_id, unnest(app.ta_sync_topics_of(r.task_id)) from new_rows r) s;
  end if;
  if tg_op in ('DELETE', 'UPDATE') then
    select array_agg(distinct s.t) || coalesce(v_topics, '{}'::text[]),
           array_agg(distinct s.task_id) || coalesce(v_ids, '{}'::uuid[])
      into v_topics, v_ids
      from (select r.task_id, 'sync:profile:' || r.profile_id as t from old_rows r
            union all
            select r.task_id, unnest(app.ta_sync_topics_of(r.task_id)) from old_rows r) s;
  end if;
  select array_agg(distinct t.event_id) filter (where t.event_id is not null)
    into v_events from tasks t where t.id = any(coalesce(v_ids, '{}'::uuid[]));
  if v_ids is not null then
    perform app.sync_send(v_topics, jsonb_build_object(
      'v', 1, 'entity', 'task', 'kind', 'assignment',
      'ids', to_jsonb(v_ids), 'event_ids', to_jsonb(coalesce(v_events, '{}'::uuid[])),
      'actor', app.profile_id()));
  end if;
  return null;
end $$;

drop trigger if exists ta_sync_ins on task_assignments;
create trigger ta_sync_ins after insert on task_assignments
  referencing new table as new_rows
  for each statement execute function app.assignments_sync();
drop trigger if exists ta_sync_upd on task_assignments;
create trigger ta_sync_upd after update on task_assignments
  referencing old table as old_rows new table as new_rows
  for each statement execute function app.assignments_sync();
drop trigger if exists ta_sync_del on task_assignments;
create trigger ta_sync_del after delete on task_assignments
  referencing old table as old_rows
  for each statement execute function app.assignments_sync();

-- עובדי קבלן: אותה תבנית, אלא שהערוץ האישי קיים רק למי שיש לו חשבון —
-- ההמרה עוברת דרך contractor_workers.user_id → profiles. סימון אי-התייצבות
-- (0095) הוא UPDATE כאן, והוא משנה את המחיר שהלו״ז מציג — ולכן גם הוא מאותת.
create or replace function app.tcw_sync() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_topics text[]; v_ids uuid[]; v_events uuid[];
begin
  if tg_op in ('INSERT', 'UPDATE') then
    select array_agg(distinct s.t), array_agg(distinct s.task_id)
      into v_topics, v_ids
      from (select r.task_id, 'sync:profile:' || p.id as t
              from new_rows r
              join contractor_workers cw on cw.id = r.contractor_worker_id
              join profiles p on p.user_id = cw.user_id
            union all
            select r.task_id, unnest(app.ta_sync_topics_of(r.task_id)) from new_rows r) s;
  end if;
  if tg_op in ('DELETE', 'UPDATE') then
    select array_agg(distinct s.t) || coalesce(v_topics, '{}'::text[]),
           array_agg(distinct s.task_id) || coalesce(v_ids, '{}'::uuid[])
      into v_topics, v_ids
      from (select r.task_id, 'sync:profile:' || p.id as t
              from old_rows r
              join contractor_workers cw on cw.id = r.contractor_worker_id
              join profiles p on p.user_id = cw.user_id
            union all
            select r.task_id, unnest(app.ta_sync_topics_of(r.task_id)) from old_rows r) s;
  end if;
  select array_agg(distinct t.event_id) filter (where t.event_id is not null)
    into v_events from tasks t where t.id = any(coalesce(v_ids, '{}'::uuid[]));
  if v_ids is not null then
    perform app.sync_send(v_topics, jsonb_build_object(
      'v', 1, 'entity', 'task', 'kind', 'assignment',
      'ids', to_jsonb(v_ids), 'event_ids', to_jsonb(coalesce(v_events, '{}'::uuid[])),
      'actor', app.profile_id()));
  end if;
  return null;
end $$;

drop trigger if exists tcw_sync_ins on task_contractor_workers;
create trigger tcw_sync_ins after insert on task_contractor_workers
  referencing new table as new_rows
  for each statement execute function app.tcw_sync();
drop trigger if exists tcw_sync_upd on task_contractor_workers;
create trigger tcw_sync_upd after update on task_contractor_workers
  referencing old table as old_rows new table as new_rows
  for each statement execute function app.tcw_sync();
drop trigger if exists tcw_sync_del on task_contractor_workers;
create trigger tcw_sync_del after delete on task_contractor_workers
  referencing old table as old_rows
  for each statement execute function app.tcw_sync();

-- האצלה לקבלן (0096): שורת terms היא מה שהופך משימה ל"שלו", ולכן הקבלן
-- שנוסף/הוסר שומע במפורש — בביטול ההאצלה השורה כבר איננה, ו-task_sync_topics
-- לא ימצא אותו. גם שינוי במחיר/קנסות (UPDATE) מאותת: המספרים על הלו״ז שלו.
create or replace function app.tct_sync() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_topics text[]; v_ids uuid[]; v_events uuid[];
begin
  if tg_op in ('INSERT', 'UPDATE') then
    select array_agg(distinct s.t), array_agg(distinct s.task_id)
      into v_topics, v_ids
      from (select r.task_id, 'sync:contractor:' || r.contractor_id as t from new_rows r
            union all
            select r.task_id, unnest(app.ta_sync_topics_of(r.task_id)) from new_rows r) s;
  end if;
  if tg_op in ('DELETE', 'UPDATE') then
    select array_agg(distinct s.t) || coalesce(v_topics, '{}'::text[]),
           array_agg(distinct s.task_id) || coalesce(v_ids, '{}'::uuid[])
      into v_topics, v_ids
      from (select r.task_id, 'sync:contractor:' || r.contractor_id as t from old_rows r
            union all
            select r.task_id, unnest(app.ta_sync_topics_of(r.task_id)) from old_rows r) s;
  end if;
  select array_agg(distinct t.event_id) filter (where t.event_id is not null)
    into v_events from tasks t where t.id = any(coalesce(v_ids, '{}'::uuid[]));
  if v_ids is not null then
    perform app.sync_send(v_topics, jsonb_build_object(
      'v', 1, 'entity', 'task', 'kind', 'assignment',
      'ids', to_jsonb(v_ids), 'event_ids', to_jsonb(coalesce(v_events, '{}'::uuid[])),
      'actor', app.profile_id()));
  end if;
  return null;
end $$;

drop trigger if exists tct_sync_ins on task_contractor_terms;
create trigger tct_sync_ins after insert on task_contractor_terms
  referencing new table as new_rows
  for each statement execute function app.tct_sync();
drop trigger if exists tct_sync_upd on task_contractor_terms;
create trigger tct_sync_upd after update on task_contractor_terms
  referencing old table as old_rows new table as new_rows
  for each statement execute function app.tct_sync();
drop trigger if exists tct_sync_del on task_contractor_terms;
create trigger tct_sync_del after delete on task_contractor_terms
  referencing old table as old_rows
  for each statement execute function app.tct_sync();

-- ===== מי רשאי להצטרף לאיזה ערוץ =====
--
-- ההצטרפות לערוץ פרטי עוברת דרך פוליסת SELECT על realtime.messages, כשהערוץ
-- המבוקש זמין כ-realtime.topic(). הפוליסה גסה במתכוון — היא שומרת ערוצים, לא
-- שורות נתונים: מי שעבר אותה מקבל אותות בלבד, והנתונים עצמם נקראים מחדש דרך
-- ה-RLS המלא של הטבלאות.
--
--   * הערוץ האישי — של בעליו בלבד.
--   * ערוץ לקוח — משתמש הלקוח עצמו, או סגל שהיקף המשימות שלו נקוב באותו לקוח
--     (ולא היקף 'own': מי שרואה רק את שיבוציו נשאר בערוץ האישי).
--   * ערוץ קבלן — סימטרי.
--   * sync:staff — אדמין, או סגל בלי 'own' ובלי היקף לקוחות/קבלנים: הסדרנים.
drop policy if exists sync_topics_read on realtime.messages;
create policy sync_topics_read on realtime.messages
for select to authenticated using (
  realtime.messages.extension = 'broadcast' and (
    realtime.topic() = 'sync:profile:' || app.profile_id()::text
    or (app.user_kind() = 'customer_user'
        and realtime.topic() = 'sync:customer:' || app.customer_id()::text)
    or (app.user_kind() = 'contractor_user'
        and realtime.topic() = 'sync:contractor:' || app.contractor_id()::text)
    or (app.user_kind() = 'staff' and not app.scope_own('tasks')
        and realtime.topic() like 'sync:customer:%'
        and split_part(realtime.topic(), ':', 3) = any(coalesce(
              (select array_agg(u::text) from unnest(app.scope_ids('tasks','customers')) u),
              '{}'::text[])))
    or (app.user_kind() = 'staff' and not app.scope_own('tasks')
        and realtime.topic() like 'sync:contractor:%'
        and split_part(realtime.topic(), ':', 3) = any(coalesce(
              (select array_agg(u::text) from unnest(app.scope_ids('tasks','contractors')) u),
              '{}'::text[])))
    or (realtime.topic() = 'sync:staff'
        and (app.is_admin()
             or (app.user_kind() = 'staff'
                 and not app.scope_own('tasks')
                 and app.scope_ids('tasks','customers') is null
                 and app.scope_ids('tasks','contractors') is null)))
  )
);
