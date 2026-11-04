-- 0237: the permissions load in time
--
-- ‏`get_my_permissions` (0215) הוא הקריאה הראשונה של האפליקציה. הוא שאל את
-- ‏`app.has` פעמיים לכל מפתח פעיל (196 מפתחות: יכולות + המבנה הישן), ואת
-- ‏`app.can_view_field`/`app.can_edit_field` לכל שדה (94 שדות, ו-edit שואל את view
-- שוב). כל אחת מהן שולפת את הקורא מ-`profiles` מחדש — ‏`is_admin`, ‏`profile_id`,
-- ‏`user_kind`, ‏`my_role_ids` (שבעצמה שואלת את profile_id ואת user_kind) — כשמונה
-- שליפות לכל מפתח. אצל מנהל מערכת `is_admin` קוצר את הכול (160ms); אצל כל
-- השאר זה 1–1.7 שניות של מעבד. בממוצע 2.2 שניות, מקסימום 7.6 — וכשכמה עובדים
-- פותחים את האפליקציה יחד בבוקר, חלק עוברים את `statement_timeout` של 8 שניות
-- של `authenticated` (57014) ונתקעים על "לא הצלחנו לטעון את ההרשאות שלך".
--
-- כאן הקורא נשלף פעם אחת, התפקידים שבתוקף נשאלים פעם אחת, וכל המפתחות וכל
-- השדות מוכרעים בשאילתה אחת לכל אחד — באותם כללים בדיוק כמו `app.has` (0214) ו-
-- ‏`app.can_view_field`/`can_edit_field` (0010): מנהל → מפתח לא פעיל או שאינו חל
-- על הסוג ⇒ לא → הענקה אישית → תפקיד → ברירת מחדל לסוג → ברירת מחדל של המפתח
-- → שרשרת `implied_by` (עד 8). ‏`app.has` עצמה לא משתנה (היא זו ש-RLS שואל).
-- סוויטה 78 משווה את התשובה ל-`app.has` ולפונקציות השדות לכל פרסונה.
--
-- כל השאר בגוף הפונקציה כמו ב-0215.

-- ===== 1. get_my_permissions =====
create or replace function get_my_permissions()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_profile profiles;
  v_role_ids uuid[];
  v_caps jsonb; v_legacy jsonb; v_fields jsonb;
  v_roles jsonb; v_app_roles jsonb; v_customer jsonb; v_scopes jsonb; v_form jsonb;
  v_kinds jsonb; v_board jsonb;
begin
  select * into v_profile from profiles
    where user_id = auth.uid() and is_active and deleted_at is null;
  if v_profile.id is null then return null; end if;

  -- ‏0237: התפקידים שבתוקף, פעם אחת (סינון הסוג 0067 וכובע המנהל 0104).
  v_role_ids := app.my_role_ids();

  -- ‏0237: כל המפתחות בבת אחת — בבואה של `app.has` (0214).
  with recursive chain(root, key, depth) as (
    select r.key, r.key, 0 from permission_registry r where r.is_active
    union all
    select c.root, r.implied_by, c.depth + 1
    from chain c
    join permission_registry r on r.key = c.key
    where r.implied_by is not null and c.depth < 8
  ),
  -- ‏materialized: בלעדיו המתכנן משבץ את ה-CTE בתוך תת-שאילתה לכל מפתח, וכל
  -- מפתח מכריע מחדש את כל השרשרת (הריבוע שהיה כאן בטיוטה: 0.8 שניות).
  resolved as materialized (
    select c.root, c.depth, coalesce(
      (select g.allowed from user_permission_grants g
        where g.profile_id = v_profile.id and g.permission_key = c.key),
      (select bool_or(rp.allowed) from role_permissions rp
        where rp.role_id = any(v_role_ids) and rp.permission_key = c.key),
      (select k.allowed from kind_permission_defaults k
        where k.user_kind = v_profile.user_kind and k.permission_key = c.key),
      (select true from permission_registry r
        where r.key = c.key and r.is_active and r.default_allowed)
    ) as decided
    from chain c
  ),
  -- השכבה הראשונה בשרשרת שהכריעה (כמו `order by depth limit 1` ב-app.has)
  first_decided as (
    select distinct on (s.root) s.root, s.decided
      from resolved s
     where s.decided is not null
     order by s.root, s.depth
  )
  select coalesce(jsonb_object_agg(r.key, case
      when v_profile.is_admin then true
      when not coalesce(v_profile.user_kind = any (r.applies_to), false) then false
      else coalesce(fd.decided, false)
    end), '{}') into v_caps
    from permission_registry r
    left join first_decided fd on fd.root = r.key
   where r.is_active;

  select coalesce(jsonb_object_agg(resource, actions), '{}') into v_legacy from (
    select split_part(r.key, '.', 1) as resource,
           jsonb_object_agg(substr(r.key, strpos(r.key, '.') + 1),
                            coalesce((v_caps ->> r.key)::boolean, false)) as actions
    from permission_registry r
    where r.is_active
      and substr(r.key, strpos(r.key, '.') + 1) in ('view', 'create', 'edit', 'delete')
    group by 1) x;

  -- ‏0237: כל השדות בבת אחת — בבואה של `app.can_view_field`/`can_edit_field` (0010).
  select coalesce(jsonb_agg(jsonb_build_object(
      'entity', x.entity, 'field_key', x.field_key,
      'can_view', x.can_view, 'can_edit', x.can_edit)), '[]') into v_fields
  from (
    select fr.entity, fr.field_key, v.can_view,
           case
             when v_profile.is_admin then true
             when not v.can_view then false
             else coalesce(
               (select f.can_edit from field_permissions f
                 where f.profile_id = v_profile.id
                   and f.entity = fr.entity and f.field_key = fr.field_key),
               (select bool_or(f.can_edit) from field_permissions f
                 where f.role_id = any(v_role_ids)
                   and f.entity = fr.entity and f.field_key = fr.field_key),
               (select f.can_edit from field_permissions f
                 where f.profile_id is null and f.role_id is null
                   and f.user_kind = v_profile.user_kind
                   and f.entity = fr.entity and f.field_key = fr.field_key),
               fr.default_can_edit,
               true)
           end as can_edit
    from field_registry fr
    cross join lateral (
      select case
        when v_profile.is_admin then true
        else coalesce(
          (select f.can_view from field_permissions f
            where f.profile_id = v_profile.id
              and f.entity = fr.entity and f.field_key = fr.field_key),
          (select bool_or(f.can_view) from field_permissions f
            where f.role_id = any(v_role_ids)
              and f.entity = fr.entity and f.field_key = fr.field_key),
          (select f.can_view from field_permissions f
            where f.profile_id is null and f.role_id is null
              and f.user_kind = v_profile.user_kind
              and f.entity = fr.entity and f.field_key = fr.field_key),
          fr.default_can_view,
          true)
      end as can_view
    ) v
  ) x;

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
                              'can_create_events', c.can_create_events,
                              -- ‏0133: המסך צריך לדעת אם הלקוח הזה מבצע בעצמו,
                              -- כדי להציג לו את "הסגל שלי" ואת בורר "בוצע ע״י".
                              'performed_by_enabled', c.performed_by_enabled,
                              -- ‏0196: ואם לו״ז המחסן פתוח לו.
                              'warehouse_schedule_enabled', c.warehouse_schedule_enabled)
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
      -- ‏0178: החשבון שהוא עובד בסגל הלקוח נושא את שורת הסגל שלו,
      -- והמסך שואל אותה כדי לדעת שהוא עובד ולא מנהל.
      'customer_worker_id', v_profile.customer_worker_id,
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
    'board_config', v_board,
    -- ‏0215: הדפים שהוסתרו מהקורא — התפריט והנתב מסננים לפיהם.
    'hidden_pages', to_jsonb(app.hidden_pages()));
end $$;

revoke execute on function get_my_permissions() from anon, public;
grant execute on function get_my_permissions() to authenticated;
