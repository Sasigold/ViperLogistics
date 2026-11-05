\pset tuples_only on
\pset format unaligned

-- ===========================================================================
-- ‏80: בדיקת ההרשאה מתוכננת פעם אחת (0239) — `app.has`, ‏`has_permission`,
-- ‏`my_role_ids`, ‏`can_view_field`, ‏`can_edit_field` עברו ל-plpgsql באותה
-- לוגיקה. כאן יושבים העתקים של הגרסאות הקודמות ב-SQL (0214/0104/0010), והם
-- נשאלים מול החדשות לכל מפתח, לכל שדה ולכל צורת הרשאות שהסוויטות הקודמות
-- השאירו (כמו 78, כולל הפרסונה שלה עם הענקה סוגרת והרשאות שדה).
--
-- נתונים: אין; הסוויטה מסירה אחריה את ההעתקים.
-- ===========================================================================

create or replace function t80_my_role_ids() returns uuid[]
language sql stable security definer set search_path = public as $$
  with mine as (
    select r.id, r.key
    from profile_roles pr
    join permission_roles r on r.id = pr.role_id
    where pr.profile_id = app.profile_id() and r.is_active and r.deleted_at is null
      and (r.user_kind is null or r.user_kind = app.user_kind()::user_kind)
  )
  select coalesce(array_agg(id), '{}'::uuid[])
  from mine
  where key <> 'contractor_worker'
     or not exists (select 1 from mine m2
                     where m2.key in ('contractor_manager', 'staff_contractor'))
$$;

create or replace function t80_has(p_key text) returns boolean
language sql stable security definer set search_path = public as $$
  with recursive chain(key, depth) as (
    select p_key, 0
    union all
    select r.implied_by, c.depth + 1
    from chain c
    join permission_registry r on r.key = c.key
    where r.implied_by is not null and c.depth < 8
  ),
  resolved as (
    select c.depth, coalesce(
      (select g.allowed from user_permission_grants g
        where g.profile_id = app.profile_id() and g.permission_key = c.key),
      (select bool_or(rp.allowed) from role_permissions rp
        where rp.role_id = any(t80_my_role_ids()) and rp.permission_key = c.key),
      (select k.allowed from kind_permission_defaults k
        where k.user_kind = app.user_kind()::user_kind and k.permission_key = c.key),
      (select true from permission_registry r
        where r.key = c.key and r.is_active and r.default_allowed)
    ) as decided
    from chain c
  )
  select case
    when app.is_admin() then true
    when app.profile_id() is null then false
    when not exists (select 1 from permission_registry r
                      where r.key = p_key and r.is_active
                        and app.user_kind()::user_kind = any (r.applies_to)) then false
    else coalesce(
      (select decided from resolved where decided is not null order by depth limit 1),
      false)
  end
$$;

create or replace function t80_can_view_field(p_entity text, p_field text)
returns boolean language sql stable security definer set search_path = public as $$
  select case
    when app.is_admin() then true
    when app.profile_id() is null then false
    else coalesce(
      (select f.can_view from field_permissions f
        where f.profile_id = app.profile_id() and f.entity = p_entity and f.field_key = p_field),
      (select bool_or(f.can_view) from field_permissions f
        where f.role_id = any(t80_my_role_ids()) and f.entity = p_entity and f.field_key = p_field),
      (select f.can_view from field_permissions f
        where f.profile_id is null and f.role_id is null
          and f.user_kind = app.user_kind()::user_kind
          and f.entity = p_entity and f.field_key = p_field),
      (select fr.default_can_view from field_registry fr
        where fr.entity = p_entity and fr.field_key = p_field),
      true)
  end
$$;

create or replace function t80_can_edit_field(p_entity text, p_field text)
returns boolean language sql stable security definer set search_path = public as $$
  select case
    when app.is_admin() then true
    when app.profile_id() is null then false
    when not t80_can_view_field(p_entity, p_field) then false
    else coalesce(
      (select f.can_edit from field_permissions f
        where f.profile_id = app.profile_id() and f.entity = p_entity and f.field_key = p_field),
      (select bool_or(f.can_edit) from field_permissions f
        where f.role_id = any(t80_my_role_ids()) and f.entity = p_entity and f.field_key = p_field),
      (select f.can_edit from field_permissions f
        where f.profile_id is null and f.role_id is null
          and f.user_kind = app.user_kind()::user_kind
          and f.entity = p_entity and f.field_key = p_field),
      (select fr.default_can_edit from field_registry fr
        where fr.entity = p_entity and fr.field_key = p_field),
      true)
  end
$$;

-- פרופיל אחד לכל צורת הרשאות (כמו 78), ועוד: פרופיל לא פעיל ומשתמש בלי פרופיל.
create table t80_users as
  select distinct on (sig) user_id from (
    select p.user_id,
           concat_ws('|', p.user_kind, p.is_admin, p.is_active, p.deleted_at is null,
             (select string_agg(pr.role_id::text, ',' order by pr.role_id)
                from profile_roles pr where pr.profile_id = p.id),
             (select string_agg(g.permission_key || g.allowed, ',' order by g.permission_key)
                from user_permission_grants g where g.profile_id = p.id),
             (select string_agg(f.entity || f.field_key || f.can_view || f.can_edit, ','
                                order by f.entity, f.field_key)
                from field_permissions f where f.profile_id = p.id)) as sig
      from profiles p where p.user_id is not null) x
  order by sig;
insert into t80_users values ('00000000-0000-0000-0000-00000000dead');

create or replace function t80_mismatches() returns text[]
language plpgsql as $$
declare u record; out text[] := '{}'; n int := 0; bad int;
begin
  for u in select user_id from t80_users loop
    perform set_config('request.jwt.claim.sub', u.user_id::text, true);
    n := n + 1;
    select count(*) into bad from permission_registry r
     where app.has(r.key) is distinct from t80_has(r.key);
    if bad > 0 then out := out || (u.user_id::text || ': has ×' || bad); end if;
    -- סדר המערך אינו מובטח (array_agg בלי order by) ואינו משנה: כל קורא שואל `= any`.
    if (select array_agg(x order by x) from unnest(app.my_role_ids()) x)
       is distinct from (select array_agg(x order by x) from unnest(t80_my_role_ids()) x) then
      out := out || (u.user_id::text || ': my_role_ids');
    end if;
    select count(*) into bad from field_registry fr
     where app.can_view_field(fr.entity, fr.field_key) is distinct from t80_can_view_field(fr.entity, fr.field_key)
        or app.can_edit_field(fr.entity, fr.field_key) is distinct from t80_can_edit_field(fr.entity, fr.field_key);
    if bad > 0 then out := out || (u.user_id::text || ': fields ×' || bad); end if;
    select count(*) into bad from permission_registry r
     where substr(r.key, strpos(r.key, '.') + 1) in ('view', 'create', 'edit', 'delete')
       and app.has_permission(split_part(r.key, '.', 1), substr(r.key, strpos(r.key, '.') + 1)::permission_action)
           is distinct from t80_has(r.key);
    if bad > 0 then out := out || (u.user_id::text || ': has_permission ×' || bad); end if;
  end loop;
  return array_prepend(n::text, out);
end $$;

grant select on t80_users to authenticated;
grant execute on function t80_mismatches(), t80_has(text), t80_my_role_ids(),
  t80_can_view_field(text, text), t80_can_edit_field(text, text) to authenticated;

\echo '--- app.has ושאר הבדיקות ב-plpgsql עונות כמו גרסאות ה-SQL ---'
set role authenticated;
create temp table t80_result as select t80_mismatches() m;
select t_eq('כל צורת הרשאות: has, has_permission, my_role_ids, שדות — זהים',
  (select array_to_string(m[2:], ', ') from t80_result), '');
select t_eq('ההשוואה עברה על יותר מעשר צורות',
  (select m[1]::int > 10 from t80_result), true);
reset role;
select set_config('request.jwt.claim.sub', '', false);

select t_eq('חמש הפונקציות כתובות ב-plpgsql',
  (select count(*)::int from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     join pg_language l on l.oid = p.prolang
    where n.nspname = 'app' and l.lanname = 'plpgsql'
      and p.proname in ('has', 'has_permission', 'my_role_ids', 'can_view_field', 'can_edit_field')), 5);

\echo '--- הזמן: app.has לעובד שאינו מנהל ---'
do $$
declare t timestamptz; i int; x boolean;
begin
  perform set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000078a1', true);
  t := clock_timestamp();
  for i in 1..200 loop x := app.has('board.view'); end loop;
  raise notice 'app.has: % us', round(extract(epoch from clock_timestamp() - t) * 1e6 / 200);
  t := clock_timestamp();
  for i in 1..200 loop x := t80_has('board.view'); end loop;
  raise notice 'before 0239: % us', round(extract(epoch from clock_timestamp() - t) * 1e6 / 200);
end $$;

drop table t80_users;
drop function t80_mismatches(), t80_has(text), t80_can_edit_field(text, text),
  t80_can_view_field(text, text), t80_my_role_ids();
