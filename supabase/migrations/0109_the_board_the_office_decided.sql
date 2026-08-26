-- 0109: מה שהלקוח רואה בלו״ז, מה שהוא עורך, ומה שאושר לביצוע
--
-- שלוש הכרעות, וכולן על אותו גבול: מה שייך ללקוח לקבוע, ומה שייך למשרד.
--
--   1. **הלקוח אינו כותב את המחיר שהוא משלם.** ‏`tp_write` (0017) נשענה על
--      `pricing.edit` לבדה, בלי לשאול מי הכותב — ומפתח הוא דבר שאפשר להעניק
--      בטעות במסך ההרשאות. הצד של המשלם והצד של המקבל אינם סימטריים, ולכן
--      הכתיבה נעשית לשל **הצוות**, ולא של מי שמחזיק את המפתח.
--   2. **מי מחליט מה בלו״ז.** עד כה מה שהלקוח ראה ומה שהוא ערך בלוח נגזר
--      מהמפתחות שלו — כלומר מהתפקיד, שהוא רוחבי לכל הלקוחות. עכשיו זו הכרעה
--      **פר-לקוח**, בדיוק כמו שדות טופס האירוע (0002/0015): שדה בלו״ז הוא
--      מוסתר, נראה, או ניתן לעריכה — והכתיבה בקונפיגורציה היא של מנהל
--      המערכת בלבד.
--   3. **אירוע מאושר לביצוע.** סימון שמנהל המערכת נותן, הלקוח קורא, וממנו
--      הוא יודע שהעבודה שלו ננעלה. ‏`approved_at` ולא בוליאני: "מתי אושר"
--      ו"על ידי מי" הן השאלות שנשאלות אחר כך, ובוליאני לא היה יודע לענות.

-- ===== 1. הלקוח אינו כותב את המחיר שהוא משלם =============================
--
-- שתי שכבות, ובכוונה: המפתח נסגר בשכבת הקהל כדי שכל תפקיד לקוח שייכתב בעתיד
-- ייוולד סגור (זה בדיוק הנימוק של 0074 §1), והפוליסה מפסיקה לשאול רק על
-- המפתח כדי שגם הענקה אישית שגויה לא תפתח כתיבה. ‏`pricing.view` נשאר פתוח:
-- בלעדיו הלקוח אינו קורא את התמחור של המשימות שלו, וזה הנתון שההוצאה שלו
-- נבנית ממנו.
insert into kind_permission_defaults (user_kind, permission_key, allowed)
select 'customer_user'::user_kind, k, false
  from unnest(array['pricing.edit', 'pricing.manage_rules']) as k
on conflict (user_kind, permission_key) do update set allowed = false;

update role_permissions rp
   set allowed = false
  from permission_roles r
 where r.id = rp.role_id
   and r.user_kind = 'customer_user'
   and rp.permission_key in ('pricing.edit', 'pricing.manage_rules');

drop policy tp_write on task_pricing;
create policy tp_write on task_pricing for all to authenticated
  using ((select app.is_admin())
    or ((select app.user_kind()) = 'staff' and (select app.has('pricing.edit'))))
  with check ((select app.is_admin())
    or ((select app.user_kind()) = 'staff' and (select app.has('pricing.edit'))));

comment on policy tp_write on task_pricing is
  'מחיר המשימה נכתב בידי הצוות בלבד (0109). הלקוח קורא אותו דרך tp_select — '
  'הוא הצד שמשלם, ולא הצד שקובע כמה.';

-- ===== 2. קטלוג שדות הלו״ז, וקונפיגורציה פר-לקוח =========================
--
-- הקטלוג הוא טבלה ולא מערך בקוד, מאותה סיבה שמרשם ההרשאות הוא טבלה: שדה
-- שייכתב בלוח מחר יופיע במסך הניהול מפני שהוא נרשם, ולא מפני שמישהו זכר
-- לעדכן קבוע. ‏`column_name` הוא מה שהופך את הקונפיגורציה לניתנת לאכיפה —
-- בלעדיו "ניתן לעריכה" הוא טענה על מסך בלבד. שדה בלי עמודה (צוות, קבלן,
-- מספר אירוע) אינו נכתב מהלוח ממילא, ולכן עבורו רק "מוסתר/נראה" משמעותיים.
create table board_fields (
  field_key   text primary key,
  label_he    text not null,
  /* העמודה ב-`tasks` שהשדה כותב, כשהוא כותב. ‏null היא התשובה לשלושה
     מקרים: שדה קריאה בלוח (מיקום, סוג משימה), שדה שנכתב לטבלה אחרת (שיבוץ,
     האצלה), ושדה **נגזר** — `onsite_end_time` מחושב בטריגר מהשעה ומהמשך,
     ולכן הוא זז גם בעריכה שלא נגעה בו, ובדיקה שלו הייתה חוסמת כל כתיבה. */
  column_name text,
  sort_order  int  not null default 0
);

comment on table board_fields is
  'קטלוג השדות שהלו״ז מצייר (0109). מזין את מסך "שדות הלו״ז" בכרטיס הלקוח '
  'ואת הטריגר שאוכף מה שהוגדר שם.';

create type board_field_state as enum ('hidden', 'visible', 'editable');

create table customer_board_fields (
  customer_id uuid not null references customers(id) on delete cascade,
  field_key   text not null references board_fields(field_key) on delete cascade,
  state       board_field_state not null default 'visible',
  primary key (customer_id, field_key)
);

comment on table customer_board_fields is
  'מה שלקוח מסוים רואה ועורך בלו״ז (0109). נכתב בידי מנהל המערכת בלבד.';

insert into board_fields (field_key, label_he, column_name, sort_order) values
  ('end_client',              'לקוח',            null,                   10),
  ('event_number',            'מס׳ אירוע',       null,                   20),
  ('location',                'מיקום',           null,                   30),
  ('task_type',               'סוג משימה',       null,                   40),
  ('warehouse_start_time',    'התחלה במחסן',     'warehouse_start_time', 50),
  ('onsite_start_time',       'התחלה בשטח',      'onsite_start_time',    60),
  /* נגזר מהשעה ומהמשך בטריגר על הטבלה, ולכן הוא זז גם בעריכה שלא נגעה בו —
     ‏`column_name` שלו null מאותה סיבה שהוא לקריאה בלבד בלוח. */
  ('onsite_end_time',         'סיום בשטח',       null,                   70),
  ('hours_count',             'משך',             'hours_count',          80),
  ('worker_count',            'כמות עובדים',     'worker_count',         90),
  ('event_truck_count',       'משאיות באירוע',   null,                  100),
  ('volume_m',                'נפח',             null,                  110),
  ('truck',                   'משאיות',          'truck_ids',           120),
  ('execution_method',        'אופן ביצוע',      'execution_method_id', 130),
  ('team_lead',               'ראש צוות',        null,                  140),
  ('team',                    'צוות',            null,                  150),
  ('contractor',              'קבלן',            null,                  160),
  ('contractor_worker_count', 'עובדים להביא',    null,                  170),
  ('status',                  'סטטוס',           'status_id',           180),
  ('notes',                   'הערות',           'notes',               190)
on conflict (field_key) do update set
  label_he    = excluded.label_he,
  column_name = excluded.column_name,
  sort_order  = excluded.sort_order;

-- לקוח קיים ולקוח חדש כאחד מתחילים ב"רואה, אינו עורך".
--
-- זו הכרעה ולא ברירת מחדל טכנית: עד כאן הלוח של הלקוח היה פתוח לעריכה בכל
-- שדה שהמפתחות שלו התירו — כלומר מנהל לקוח שינה שעות, כמות עובדים ואופן
-- ביצוע, וכל אחד מהם מריץ מחדש את `app.recalc_task_price` ולכן מזיז את מה
-- שהוא ישלם. מעכשיו העריכה נפתחת שדה-שדה, במפורש, בידי מנהל המערכת.
insert into customer_board_fields (customer_id, field_key, state)
select c.id, f.field_key, 'visible'::board_field_state
  from customers c cross join board_fields f
on conflict do nothing;

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
  -- שדות הלו״ז (0109): לקוח חדש רואה הכול ואינו עורך דבר.
  insert into customer_board_fields (customer_id, field_key, state)
  select new.id, f.field_key, 'visible'::board_field_state from board_fields f
  on conflict do nothing;
  return new;
end $$;

-- שדה שנרשם בקטלוג אחרי שהלקוחות כבר קיימים מקבל שורה לכל אחד מהם מיד,
-- מאותו נימוק שבגללו 0053 עושה זאת לשדה טופס: בלי השורה ה-SegmentedControl
-- במסך לא יודע מה להציג עד הלחיצה הראשונה.
create or replace function app.seed_board_field_state()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into customer_board_fields (customer_id, field_key, state)
  select c.id, new.field_key, 'visible'::board_field_state from customers c
  on conflict do nothing;
  return new;
end $$;
create trigger board_fields_seed_state after insert on board_fields
  for each row execute function app.seed_board_field_state();

-- ===== 2ב. מה הקורא מקבל =================================================
--
-- ‏`hidden`/`visible`/`editable` לכל שדה, ללקוח של הקורא. לאיש צוות אין
-- קונפיגורציה כזו — הלוח שלו נשלט במפתחות, כמו תמיד — ולכן הפונקציה מחזירה
-- לו ריק, וזה מה שהמסך קורא כ"אין הגבלה פר-לקוח".
create or replace function app.board_config(p_customer uuid)
returns table (field_key text, state board_field_state)
language sql stable set search_path = public as $$
  select f.field_key, coalesce(c.state, 'visible'::board_field_state)
    from board_fields f
    left join customer_board_fields c
           on c.customer_id = p_customer and c.field_key = f.field_key
   where p_customer is not null
   order by f.sort_order
$$;

comment on function app.board_config(uuid) is
  'מה שלקוח מסוים רואה ועורך בלו״ז (0109). ריק למי שאינו משויך ללקוח.';

-- ===== 2ג. האכיפה: "ניתן לעריכה" הוא טענה על השרת =========================
--
-- אח לטריגר הגנרי של 0012, ולא הרחבה שלו: זה קורא מקטלוג אחר, שואל שאלה על
-- ה**לקוח** ולא על התפקיד, וחל על קהל אחד בלבד. שני התנאים הראשונים זהים
-- לשלו מאותן סיבות בדיוק — כתיבה בלי JWT היא מיגרציה, וכתיבה מתוך
-- `app.system_write` כבר אושרה בהרשאה גסה יותר במעלה הזרם.
--
-- שדה בלי `column_name` אינו נבדק כאן מפני שאינו נכתב לטבלה הזאת; מה שמגן
-- עליו הוא הפוליסה של הטבלה שהוא כן נכתב לה (`task_assignments`,
-- `task_contractor_terms`), ושם ללקוח אין דריסת רגל מלכתחילה.
create or replace function app.enforce_customer_board_edit()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_old jsonb := to_jsonb(old);
  v_new jsonb := to_jsonb(new);
  v_ctr uuid;
  r     record;
begin
  if auth.uid() is null then return new; end if;
  if app.in_system_write() then return new; end if;
  if app.is_admin() then return new; end if;
  if app.user_kind() <> 'customer_user' then return new; end if;

  v_ctr := app.customer_id();
  if v_ctr is null then return new; end if;

  for r in
    select f.field_key, f.label_he, f.column_name,
           coalesce(c.state, 'visible'::board_field_state) as state
      from board_fields f
      left join customer_board_fields c
             on c.customer_id = v_ctr and c.field_key = f.field_key
     where f.column_name is not null
  loop
    if v_old -> r.column_name is not distinct from v_new -> r.column_name then
      continue;
    end if;
    if r.state <> 'editable' then
      raise exception 'השדה "%" אינו פתוח לעריכה עבורך', r.label_he
        using errcode = '42501';
    end if;
  end loop;
  return new;
end $$;

create trigger tasks_customer_board_edit before update on tasks
  for each row execute function app.enforce_customer_board_edit();

-- ===== 2ד. RLS: קריאה לכולם, כתיבה למנהל המערכת ==========================
--
-- הקריאה פתוחה מפני שהיא **חייבת** להיות: הלקוח קורא את הקונפיגורציה של
-- עצמו כדי לדעת מה לצייר, והמשרד קורא את של כולם כדי לערוך אותה. הכתיבה
-- היא של מנהל המערכת בלבד — זו כל הבקשה. אין כאן מפתח במרשם בכוונה: מפתח
-- אפשר להעניק, ו"רק מנהל מערכת" נאמר כדי שלא יהיה אפשר.
alter table board_fields enable row level security;
alter table customer_board_fields enable row level security;

create policy board_fields_read on board_fields for select to authenticated using (true);
create policy board_fields_write on board_fields for all to authenticated
  using ((select app.is_admin())) with check ((select app.is_admin()));

create policy cbf_read on customer_board_fields for select to authenticated using (true);
create policy cbf_write on customer_board_fields for all to authenticated
  using ((select app.is_admin())) with check ((select app.is_admin()));

create trigger customer_board_fields_audit after insert or update or delete
  on customer_board_fields for each row execute function app.audit();

-- ===== 3. אירוע מאושר לביצוע =============================================
--
-- ‏`approved_at` ולא בוליאני: "מתי" ו"מי" הן השאלות שנשאלות אחרי "האם",
-- ובוליאני מאבד את שתיהן. שתי העמודות נכתבות דרך RPC בלבד, וטריגר חוסם
-- כתיבה ישירה — אחרת כל מי שמחזיק `events.edit` (ובכללם מנהל הלקוח) היה
-- מאשר לעצמו את האירוע שלו.
alter table events add column approved_at timestamptz;
alter table events add column approved_by uuid references profiles(id);

comment on column events.approved_at is
  'מתי מנהל המערכת אישר את האירוע לביצוע (0109). null = לא אושר.';
comment on column events.approved_by is 'מי אישר (0109).';

create or replace function app.events_approval_guard()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if app.in_system_write() then return new; end if;
  if new.approved_at is distinct from old.approved_at
     or new.approved_by is distinct from old.approved_by then
    raise exception 'אישור אירוע לביצוע נעשה דרך set_event_approved בלבד'
      using errcode = '42501';
  end if;
  return new;
end $$;

create trigger events_approval_guard before update on events
  for each row execute function app.events_approval_guard();

create or replace function set_event_approved(p_event_id uuid, p_on boolean default true)
returns timestamptz language plpgsql security definer set search_path = public as $$
declare v_at timestamptz;
begin
  if not app.is_admin() then
    raise exception 'אישור אירוע לביצוע שמור למנהל המערכת' using errcode = '42501';
  end if;
  if not exists (select 1 from events where id = p_event_id and deleted_at is null) then
    raise exception 'האירוע לא נמצא' using errcode = '42501';
  end if;

  v_at := case when p_on then now() end;
  perform app.system_write(true);
  update events
     set approved_at = v_at,
         approved_by = case when p_on then app.profile_id() end
   where id = p_event_id;
  perform app.system_write(false);
  return v_at;
end $$;

revoke execute on function public.set_event_approved(uuid, boolean) from anon, public;

comment on function public.set_event_approved(uuid, boolean) is
  'סימון/ביטול "מאושר לביצוע" על אירוע (0109). מנהל מערכת בלבד; הלקוח קורא '
  'את התוצאה בלוח השנה ובדף האירוע.';

-- ‏`events_secure` נבנה מהעמודות של הטבלה (0012), ולכן הוא צריך להיבנות מחדש
-- אחרי שנוספו לה שתיים.
select app.rebuild_secure_view('events');

-- ===== 3ב. והיומן מדווח עליו =============================================
-- הגוף מ-0061 עם שורה אחת ברשימה הנעקבת, ועם `approved_at` שנקרא כמילה
-- ולא כחותמת זמן.
create or replace function app.event_value_text(p_col text, p_val jsonb)
returns text language plpgsql stable security definer set search_path = public as $$
declare v text;
begin
  if p_val is null or jsonb_typeof(p_val) = 'null' then return null; end if;
  if jsonb_typeof(p_val) = 'boolean' then
    return case when p_val = 'true'::jsonb then 'כן' else 'לא' end;
  end if;
  v := p_val #>> '{}';
  return case p_col
    when 'customer_id' then (select c.name from customers c where c.id = v::uuid)
    when 'status_id'   then (select s.name from statuses s where s.id = v::uuid)
    when 'event_date'  then to_char(v::date, 'DD/MM/YYYY')
    -- הערך הוא חותמת זמן, והשאלה היא "האם": שורת יומן שאומרת תאריך ושעה
    -- מחביאה את מה שקרה מאחורי מספר.
    when 'approved_at' then 'מאושר'
    else v
  end;
end $$;

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

  -- מחיקה רכה ושחזור הם UPDATE של deleted_at, ונקראים כשורות משל עצמם.
  if (old.deleted_at is null) <> (new.deleted_at is null) then
    insert into event_activity (event_id, kind, actor_profile_id, actor_name)
    values (new.id,
            (case when new.deleted_at is null then 'restored' else 'deleted' end)::event_activity_kind,
            v_actor, v_name);
  end if;

  v_old := to_jsonb(old);
  v_new := to_jsonb(new);

  for f in
    select * from unnest(
      array['event_date','end_client_name','event_number','customer_id','status_id',
            'location_text','location_notes','volume_m','truck_count','notes',
            'no_parking','porterage','supplier_pickup','approved_at'],
      array['תאריך אירוע','לקוח סופי','מספר אירוע','לקוח','סטטוס',
            'מיקום','הערות מיקום','נפח (קוב)','כמות משאיות','הערות',
            'ללא חניה','סבלות','איסוף מספק','אישור לביצוע']) as t(col, label)
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

-- ===== 4. הקורא מקבל את הקונפיגורציה עם שאר ההרשאות ======================
--
-- באותו מקום שבו `form_config` כבר יושבת: המסך מקבל את שתיהן בעלייה, ואינו
-- מבקש עוד שאילתה כדי לדעת מה לצייר. הגוף זהה ל-0026 פרט לשורה אחת.
create or replace function get_my_permissions()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_profile profiles;
  v_caps jsonb; v_legacy jsonb; v_fields jsonb;
  v_roles jsonb; v_app_roles jsonb; v_customer jsonb; v_scopes jsonb; v_form jsonb;
  v_kinds jsonb; v_board jsonb;
begin
  select * into v_profile from profiles
    where user_id = auth.uid() and is_active and deleted_at is null;
  if v_profile.id is null then return null; end if;

  select coalesce(jsonb_object_agg(r.key, app.has(r.key)), '{}') into v_caps
    from permission_registry r where r.is_active;

  select coalesce(jsonb_object_agg(resource, actions), '{}') into v_legacy from (
    select split_part(r.key, '.', 1) as resource,
           jsonb_object_agg(substr(r.key, strpos(r.key, '.') + 1), app.has(r.key)) as actions
    from permission_registry r
    where r.is_active
      and substr(r.key, strpos(r.key, '.') + 1) in ('view', 'create', 'edit', 'delete')
    group by 1) x;

  select coalesce(jsonb_agg(jsonb_build_object(
      'entity', fr.entity, 'field_key', fr.field_key,
      'can_view', app.can_view_field(fr.entity, fr.field_key),
      'can_edit', app.can_edit_field(fr.entity, fr.field_key))), '[]') into v_fields
    from field_registry fr;

  select coalesce(jsonb_agg(role), '[]') into v_roles
    from staff_roles where profile_id = v_profile.id;

  select coalesce(jsonb_agg(jsonb_build_object(
      'id', r.id, 'key', r.key, 'name_he', r.name_he)), '[]') into v_app_roles
    from profile_roles pr join permission_roles r on r.id = pr.role_id
    where pr.profile_id = v_profile.id and r.is_active and r.deleted_at is null;

  select coalesce(jsonb_agg(jsonb_build_object(
      'resource', s.resource, 'scope_type', s.scope_type,
      'values', s.scope_values, 'days_back', s.days_back,
      'days_forward', s.days_forward)), '[]') into v_scopes
    from (select distinct resource from permission_scopes) res
    cross join lateral app.scope_rows(res.resource) s;

  if v_profile.customer_id is not null then
    select jsonb_build_object('id', c.id, 'name', c.name, 'color', c.color,
                              'can_create_events', c.can_create_events)
      into v_customer from customers c where c.id = v_profile.customer_id;
  end if;

  select coalesce(jsonb_agg(jsonb_build_object('field_key', field_key, 'state', state)), '[]')
    into v_form from app.form_config(v_profile.customer_id, v_profile.id);

  -- ‏0109: ריק לאיש צוות, ולכן הלוח שלו נשלט במפתחות כפי שהיה תמיד.
  select coalesce(jsonb_agg(jsonb_build_object('field_key', field_key, 'state', state)), '[]')
    into v_board from app.board_config(v_profile.customer_id);

  -- הלקוח והקבלן של הקורא מועברים כפי שהם: אצל עובד צוות הענף ב-
  -- may_create_profile אינו מסתכל עליהם, ואצל לקוח או קבלן זו בדיוק ההשוואה
  -- שהפונקציה עושה מול app.customer_id()/app.contractor_id().
  select coalesce(jsonb_agg(kind), '[]'::jsonb) into v_kinds from (
    select 'staff' as kind
      where app.may_create_profile('staff', null, null, false)
    union all
    select 'customer_user'
      where app.may_create_profile('customer_user', v_profile.customer_id, null, false)
    union all
    select 'contractor_user'
      where app.may_create_profile('contractor_user', null, v_profile.contractor_id, false)
  ) q;

  return jsonb_build_object(
    'profile', jsonb_build_object(
      'id', v_profile.id, 'full_name', v_profile.full_name,
      'user_kind', v_profile.user_kind, 'is_admin', v_profile.is_admin,
      'customer_id', v_profile.customer_id, 'contractor_id', v_profile.contractor_id,
      'phone', v_profile.phone, 'email', v_profile.email),
    'roles', v_roles,
    'app_roles', v_app_roles,
    'customer', v_customer,
    'permissions', v_legacy,
    'capabilities', v_caps,
    'creatable_user_kinds', v_kinds,
    'field_permissions', v_fields,
    'scopes', coalesce(v_scopes, '[]'::jsonb),
    'form_config', v_form,
    'board_config', v_board);
end $$;
