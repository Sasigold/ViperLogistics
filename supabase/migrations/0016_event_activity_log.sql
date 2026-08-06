-- 0016: יומן פעילות של האירוע
--
-- (0014 and 0015 land from other branches; this file is numbered to sit after
-- them rather than to collide with them.)
--
-- What existed until now was an audit *table* rendered raw: table_name, action,
-- an array of column names. It answers "which row did the database touch",
-- which is a question an engineer asks. The question the coordinator asks is
-- "who took this event from 3 trucks to 5, and why" — and the "why" was never
-- anywhere, because nothing let a person type it.
--
-- So the raw screen retires and this takes its place: one readable row per
-- meaningful change to an event, values spelled out in Hebrew rather than as
-- column names, plus free-text entries anyone with the key may add.
--
-- audit_log itself stays. It is the tamper record that every table writes to
-- through app.audit(), and it is not this feature's job to throw that away —
-- what goes is its screen and its read policy, so nothing user-facing reads it
-- any more. A future screen that wants it back needs a policy of its own.

-- ===== 1. retire the raw audit-log screen ==================================

drop view if exists audit_log_secure;
drop function if exists app.redact_audit(text, jsonb);
drop policy if exists audit_read on audit_log;

-- The key goes with the screen. Every table that points at it does so with
-- `on delete cascade` (grants) or `on delete set null` (implied_by), so this
-- one statement takes the grants with it.
delete from permission_registry where key = 'settings.audit_log';

update permission_modules
   set description_he = 'נתוני בסיס, סל מיחזור והרשאות'
 where key = 'settings';

-- ===== 2. the log =========================================================

create type event_activity_kind as enum ('created', 'changed', 'note', 'deleted', 'restored');

create table event_activity (
  id bigint generated always as identity primary key,
  event_id uuid not null references events(id) on delete cascade,
  kind event_activity_kind not null,
  -- The actor is both referenced and denormalised: a profile can be deleted,
  -- and a log that forgets who wrote in it is not a log.
  actor_profile_id uuid references profiles(id) on delete set null,
  actor_name text,
  -- 'changed' rows only. field_key matches field_registry where one exists,
  -- which is what lets the read view apply the same field permissions the
  -- event screen applies; field_label is stored rather than joined so a
  -- renamed label doesn't rewrite history.
  field_key text,
  field_label text,
  old_value text,
  new_value text,
  -- 'note' rows only
  note text,
  created_at timestamptz not null default now(),
  constraint event_activity_shape check (
    case kind
      when 'changed' then field_key is not null and field_label is not null
      when 'note'    then btrim(coalesce(note, '')) <> ''
      else true
    end)
);
create index event_activity_event_idx on event_activity (event_id, created_at desc);
alter table event_activity enable row level security;

-- A column value as a person reads it: an id becomes the name it points at, a
-- boolean becomes כן/לא, a date becomes DD/MM/YYYY. Everything else is itself.
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
    else v
  end;
end $$;

-- ===== 3. what gets written ===============================================

-- The tracked list is deliberately shorter than the column list: search_tsv,
-- updated_at and the geocoder's lat/lng/place_id are machinery, and a log that
-- reports machinery buries the two lines that matter.
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

  -- Soft delete and restore are updates of deleted_at. They read as their own
  -- entries rather than as "deleted_at: — ← 06/08/2026".
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
  return new;
end $$;

create trigger events_activity after insert or update on events
  for each row execute function app.log_event_activity();

-- The contact lives on its own table but reads as part of the event, so it
-- logs to the same place. Both its columns are in field_registry, which means
-- the read view hides them from whoever may not see contact details anyway.
create or replace function app.log_event_contact_activity()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_actor uuid := app.profile_id();
  v_name  text;
  v_event uuid := coalesce(new.event_id, old.event_id);
  v_old   jsonb := case when tg_op = 'INSERT' then '{}'::jsonb else to_jsonb(old) end;
  v_new   jsonb := case when tg_op = 'DELETE' then '{}'::jsonb else to_jsonb(new) end;
  f       record;
begin
  select full_name into v_name from profiles where id = v_actor;

  for f in
    select * from unnest(array['contact_name','contact_phone'],
                         array['שם איש קשר','טלפון איש קשר']) as t(col, label)
  loop
    if v_old -> f.col is distinct from v_new -> f.col then
      insert into event_activity (
        event_id, kind, actor_profile_id, actor_name, field_key, field_label, old_value, new_value)
      values (v_event, 'changed', v_actor, v_name, f.col, f.label,
              app.event_value_text(f.col, v_old -> f.col),
              app.event_value_text(f.col, v_new -> f.col));
    end if;
  end loop;
  return coalesce(new, old);
end $$;

create trigger event_contacts_activity after insert or update or delete on event_contacts
  for each row execute function app.log_event_contact_activity();

-- Suppliers are a set, and update_event rewrites the set wholesale (delete
-- everything, insert what remains). Logging that naively writes "הוסר ספק א"
-- and "נוסף ספק א" on every save that touched a different field entirely.
-- So an insert first looks for its own removal earlier in the same
-- transaction and cancels the pair. now() is the transaction timestamp, which
-- is what makes "earlier in this save" expressible in a where clause.
create or replace function app.log_event_supplier_activity()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_actor    uuid := app.profile_id();
  v_name     text;
  v_supplier text;
  v_cancel   bigint;
begin
  select full_name into v_name from profiles where id = v_actor;

  if tg_op = 'INSERT' then
    select name into v_supplier from suppliers where id = new.supplier_id;
    delete from event_activity
     where id = (select id from event_activity
                  where event_id = new.event_id and kind = 'changed'
                    and field_key = 'suppliers' and created_at = now()
                    and new_value is null and old_value is not distinct from v_supplier
                  order by id limit 1)
    returning id into v_cancel;

    if v_cancel is null then
      insert into event_activity (
        event_id, kind, actor_profile_id, actor_name, field_key, field_label, new_value)
      values (new.event_id, 'changed', v_actor, v_name, 'suppliers', 'ספקים לאיסוף', v_supplier);
    end if;
    return new;
  end if;

  select name into v_supplier from suppliers where id = old.supplier_id;
  insert into event_activity (
    event_id, kind, actor_profile_id, actor_name, field_key, field_label, old_value)
  values (old.event_id, 'changed', v_actor, v_name, 'suppliers', 'ספקים לאיסוף', v_supplier);
  return old;
end $$;

create trigger event_suppliers_activity after insert or delete on event_suppliers
  for each row execute function app.log_event_supplier_activity();

-- ===== 4. free text =======================================================

-- Notes are written by the client straight into the table; this stamps the
-- author from the session rather than trusting the payload, and clears the
-- change-shaped columns so a note can't masquerade as a recorded change.
-- BEFORE triggers run ahead of the WITH CHECK, so the policy below still gets
-- to verify what this wrote.
create or replace function app.stamp_event_activity()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.actor_profile_id is null then
    new.actor_profile_id := app.profile_id();
  end if;
  if new.actor_name is null then
    select full_name into new.actor_name from profiles where id = new.actor_profile_id;
  end if;
  if new.kind = 'note' then
    new.note      := btrim(new.note);
    new.field_key := null;
    new.field_label := null;
    new.old_value := null;
    new.new_value := null;
  end if;
  return new;
end $$;

create trigger event_activity_stamp before insert on event_activity
  for each row execute function app.stamp_event_activity();

-- ===== 5. who may read and write it =======================================

select app.register_permission(
  'events.activity_log', 'events', 'צפייה ביומן פעילות של אירוע',
  'מי שינה מה ומתי, כולל תיעוד חופשי', 'action', false, false,
  array['staff','customer_user','contractor_user']::user_kind[], 'events.view', 170);

select app.register_permission(
  'events.activity_note', 'events', 'הוספת תיעוד חופשי ליומן',
  'רישום ידני ביומן הפעילות של האירוע', 'action', false, false,
  array['staff','customer_user']::user_kind[], 'events.edit', 180);

-- events carries the row scoping (customer, status, date window, own rows), so
-- referencing it inherits the whole of it rather than restating any of it.
create policy event_activity_select on event_activity for select to authenticated using (
  (select app.is_admin())
  or ((select app.has('events.activity_log'))
      and exists (select 1 from events e where e.id = event_activity.event_id)));

create policy event_activity_note_insert on event_activity for insert to authenticated with check (
  kind = 'note'
  and (select app.has('events.activity_note'))
  and actor_profile_id = (select app.profile_id())
  and exists (select 1 from events e where e.id = event_activity.event_id));

-- No update policy, by design: a log you can rewrite is a draft. Deleting is
-- left to admins, for the note that went in with the wrong event open.
create policy event_activity_admin_delete on event_activity for delete to authenticated
  using ((select app.is_admin()));

-- The reader's own field permissions decide which changes they see at all —
-- the same rule the event screen applies to the values themselves. Field keys
-- with no registry entry (suppliers) default to visible.
create or replace view event_activity_feed with (security_invoker = true) as
select a.id,
       a.event_id,
       a.kind,
       a.actor_profile_id,
       coalesce(p.full_name, a.actor_name) as actor_name,
       a.field_key,
       a.field_label,
       a.old_value,
       a.new_value,
       a.note,
       a.created_at
from event_activity a
left join profiles p on p.id = a.actor_profile_id
where a.field_key is null or app.can_view_field('event', a.field_key);

grant select on event_activity_feed to authenticated;
revoke all on event_activity_feed from anon;
revoke all on event_activity from anon;
