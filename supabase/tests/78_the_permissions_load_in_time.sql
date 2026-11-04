\pset tuples_only on
\pset format unaligned

-- ===========================================================================
-- ‏78: ההרשאות נטענות בזמן (0237) — `get_my_permissions` מכריע את כל המפתחות
-- ואת כל השדות בשאילתה אחת, ולכן צריך לענות בדיוק כמו `app.has` ו-
-- ‏`app.can_view_field`/`can_edit_field` שהוא החליף. הסוויטה משווה, לכל פרופיל
-- פעיל שהסוויטות הקודמות השאירו (כל סוג, תפקיד, הענקה ושדה שנבדקו לפניה),
-- ולפרסונה משלה עם הענקה אישית שסוגרת, הענקה למפתח שאינו חל על הסוג, שרשרת
-- ‏`implied_by` והרשאות שדה אישיות ולפי תפקיד.
--
-- הנתונים: משתמש ופרופיל משלה; הסוויטה משאירה אחריה את מה שיצרה.
-- ===========================================================================

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000078a1', 'c78-worker@vl.test');

insert into profiles (id, user_id, user_kind, is_admin, full_name) values
  ('20000000-0000-0000-0000-0000000078a1', '00000000-0000-0000-0000-0000000078a1',
   'staff', false, 'עובד 78');

-- תפקיד העובד + נהג, כמו בפרופיל שנתקע בייצור
insert into profile_roles (profile_id, role_id)
select '20000000-0000-0000-0000-0000000078a1', id from permission_roles
 where key in ('worker', 'driver');

-- הענקה אישית שסוגרת מפתח שהתפקיד פותח
insert into user_permission_grants (profile_id, permission_key, allowed)
select '20000000-0000-0000-0000-0000000078a1', rp.permission_key, false
  from role_permissions rp join permission_roles r on r.id = rp.role_id
  join permission_registry pr on pr.key = rp.permission_key
 where r.key = 'worker' and rp.allowed and pr.is_active and 'staff' = any (pr.applies_to)
 order by rp.permission_key limit 1;

-- הענקה אישית למפתח שאינו חל על איש צוות (חייבת להישאר "לא")
insert into user_permission_grants (profile_id, permission_key, allowed)
select '20000000-0000-0000-0000-0000000078a1', key, true
  from permission_registry
 where is_active and not ('staff' = any (applies_to))
 order by key limit 1;

-- הרשאות שדה: אישית (מוסתר) ולפי תפקיד (עריכה)
insert into field_permissions (profile_id, entity, field_key, can_view, can_edit)
select '20000000-0000-0000-0000-0000000078a1', entity, field_key, false, false
  from field_registry order by entity, field_key limit 1;
insert into field_permissions (role_id, entity, field_key, can_view, can_edit)
select r.id, f.entity, f.field_key, true, true
  from permission_roles r,
       (select entity, field_key from field_registry
         order by entity, field_key offset 1 limit 1) f
 where r.key = 'driver'
on conflict do nothing;

-- רשימת הפרופילים נאספת לפני `set role`: מתחתיו RLS היה מראה רק חלק מהם.
-- פרופיל אחד לכל "צורה" של הרשאות (סוג, מנהל, סט התפקידים, ההענקות האישיות
-- והרשאות השדה האישיות) — כל השאר היו עונים אותו דבר, וההשוואה (שמריצה את
-- הפונקציות האיטיות) על כל ~300 הפרופילים לוקחת דקות.
create table t78_users as
  select distinct on (sig) user_id, full_name from (
    select p.user_id, p.full_name, p.id = '20000000-0000-0000-0000-0000000078a1' as mine,
           concat_ws('|', p.user_kind, p.is_admin,
             (select string_agg(pr.role_id::text, ',' order by pr.role_id)
                from profile_roles pr where pr.profile_id = p.id),
             (select string_agg(g.permission_key || g.allowed, ',' order by g.permission_key)
                from user_permission_grants g where g.profile_id = p.id),
             (select string_agg(f.entity || f.field_key || f.can_view || f.can_edit, ','
                                order by f.entity, f.field_key)
                from field_permissions f where f.profile_id = p.id)) as sig
      from profiles p
     where p.is_active and p.deleted_at is null and p.user_id is not null) x
  order by sig, mine desc;
grant select on t78_users to authenticated;

-- ההשוואה: לכל פרופיל פעיל, התשובה של get_my_permissions מול הפונקציות.
create or replace function t78_mismatches() returns text[]
language plpgsql as $$
declare
  u record; v jsonb; out text[] := '{}'; n int := 0;
  exp_caps jsonb; exp_legacy jsonb; exp_fields jsonb; got_fields jsonb;
begin
  for u in select user_id, full_name from t78_users loop
    perform set_config('request.jwt.claim.sub', u.user_id::text, true);
    v := get_my_permissions();
    if v is null then continue; end if;
    n := n + 1;

    select coalesce(jsonb_object_agg(r.key, app.has(r.key)), '{}') into exp_caps
      from permission_registry r where r.is_active;
    if v -> 'capabilities' is distinct from exp_caps then
      out := out || (u.full_name || ': capabilities');
    end if;

    select coalesce(jsonb_object_agg(resource, actions), '{}') into exp_legacy from (
      select split_part(r.key, '.', 1) as resource,
             jsonb_object_agg(substr(r.key, strpos(r.key, '.') + 1), app.has(r.key)) as actions
      from permission_registry r
      where r.is_active
        and substr(r.key, strpos(r.key, '.') + 1) in ('view', 'create', 'edit', 'delete')
      group by 1) x;
    if v -> 'permissions' is distinct from exp_legacy then
      out := out || (u.full_name || ': permissions');
    end if;

    select coalesce(jsonb_object_agg(fr.entity || '.' || fr.field_key, jsonb_build_array(
             app.can_view_field(fr.entity, fr.field_key),
             app.can_edit_field(fr.entity, fr.field_key))), '{}') into exp_fields
      from field_registry fr;
    select coalesce(jsonb_object_agg((e ->> 'entity') || '.' || (e ->> 'field_key'),
             jsonb_build_array(e -> 'can_view', e -> 'can_edit')), '{}') into got_fields
      from jsonb_array_elements(v -> 'field_permissions') e;
    if got_fields is distinct from exp_fields then
      out := out || (u.full_name || ': field_permissions');
    end if;
  end loop;
  return array_prepend(n::text, out);
end $$;
grant execute on function t78_mismatches() to authenticated;

\echo '--- get_my_permissions עונה כמו app.has ופונקציות השדות ---'
set role authenticated;

create temp table t78_result as select t78_mismatches() m;
select t_eq('כל צורת הרשאות: יכולות, מבנה ישן והרשאות שדה זהים',
  (select array_to_string(m[2:], ', ') from t78_result), '');
select t_eq('ההשוואה עברה על יותר מעשר צורות',
  (select m[1]::int > 10 from t78_result), true);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000078a1', false);
select t_eq('הענקה אישית שסוגרת גוברת על התפקיד',
  (select (get_my_permissions() -> 'capabilities' ->> g.permission_key)::boolean
     from user_permission_grants g
    where g.profile_id = '20000000-0000-0000-0000-0000000078a1' and not g.allowed), false);
select t_eq('הענקה למפתח שאינו חל על הסוג אינה מוענקת',
  (select (get_my_permissions() -> 'capabilities' ->> g.permission_key)::boolean
     from user_permission_grants g
    where g.profile_id = '20000000-0000-0000-0000-0000000078a1' and g.allowed), false);
select t_eq('שדה שהוסתר אישית: לא נראה ולא נערך',
  (select e ->> 'can_view' || '/' || (e ->> 'can_edit')
     from jsonb_array_elements(get_my_permissions() -> 'field_permissions') e,
          (select entity, field_key from field_registry order by entity, field_key limit 1) f
    where e ->> 'entity' = f.entity and e ->> 'field_key' = f.field_key), 'false/false');

reset role;
select set_config('request.jwt.claim.sub', '', false);
drop table t78_users;

\echo '--- הזמן: עובד שאינו מנהל ---'
do $$
declare t timestamptz; ms numeric;
begin
  perform set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000078a1', true);
  t := clock_timestamp();
  perform get_my_permissions();
  ms := extract(epoch from clock_timestamp() - t) * 1000;
  raise notice 'get_my_permissions: % ms', round(ms);
end $$;
