-- 0215: הבעלים בוחר אילו דפים כל אחד רואה
--
-- הבקשה, במילים של הבעלים: "שאוכל לשלוט אילו דפים יהיו פתוחים לכל אחד או
-- לכל סוג יוזר, כולל אדמין. למשל לאדמין לא יהיה מסך כספים, או לא יהיו לו
-- משמרות — זה לא רלוונטי לו, הוא לא עובד; משמרות צוות כן רלוונטי לו. לכל סוג
-- יוזר וגם פרטני פר עובד: איזה דפים חשופים לו ואיזה לא."
--
-- עד כאן מסך הוצג לפי ההרשאות בלבד (ועוד שלוש גדרות "מי הוא" ב-nav.ts:
-- עובד, קבלן, לקוח מבצע). זה עובד לכל מי שהמטריצה חלה עליו, ולא עובד למנהל
-- מערכת: `app.has` עונה לו "כן" על כל מפתח, ולכן הוא רואה את כל הדפים —
-- גם את "כספים ותשלומים" של הקבלן (`/portal`, שאצלו ריק תמיד), וגם את
-- "משמרות" ו"שעון נוכחות", כי שלושת מנהלי המערכת במסד החי רשומים גם כעובד,
-- נהג וראש צוות (`staff_roles`). ולמי שהמטריצה חלה עליו, הדרך היחידה להוריד
-- דף מהתפריט הייתה לחסום את המפתח שלו — וזה סוגר גם את הנתונים שמסכים
-- אחרים צריכים.
--
-- לכן שכבה נפרדת, "דפים":
--
--   * הרשאה אומרת מה **מותר**, והשרת אוכף אותה. דף אומר מה **מוצג** בתפריט
--     ונפתח באפליקציה. דף נפתח רק כששניהם מסכימים: הסתרה אינה פותחת דבר,
--     ואינה סוגרת נתונים — מנהל מערכת ממשיך להחזיק הכול בהגדרה, ומי שצריך
--     באמת לא לגשת לכספים צריך תפקיד בלי ההרשאה, לא דף מוסתר.
--   * שלוש רמות, כמו במטריצת ההרשאות: מנהלי מערכת (כקבוצה), תפקיד, ומשתמש
--     בודד. בכל רמה, לכל דף: מוצג / מוסתר / ירושה (אין שורה).
--   * ההכרעה (`app.hidden_pages`): שורה אישית קובעת. אחרת, בין הקבוצות שהמשתמש
--     שייך אליהן — התפקידים שבתוקף לו (`app.my_role_ids`) ו"מנהלי מערכת" אם
--     הוא אדמין — "מוצג" מפורש גובר על "מוסתר", בדיוק כמו `bool_or` של
--     `role_permissions`. אחרת מוצג.
--   * ההגדרות לעולם אינן מוסתרות ממנהל מערכת: משם מחזירים דף שהוסתר.
--
-- רשימת הדפים יושבת במסך (`src/app/pages.ts`), כמו שהתפריט יושב שם; המסד
-- שומר מפתח טקסט ואינו צריך לדעת מה הוא. מפתח שהמסך אינו מכיר פשוט אינו
-- מסתיר דבר.

-- ===== 1. הטבלה =============================================================

create table page_visibility (
  id          uuid primary key default gen_random_uuid(),
  page_key    text not null check (page_key ~ '^[a-z][a-z0-9_]{0,47}$'),
  -- שורה בלי תפקיד ובלי משתמש היא של "מנהלי מערכת" כקבוצה.
  role_id     uuid references permission_roles(id) on delete cascade,
  profile_id  uuid references profiles(id) on delete cascade,
  visible     boolean not null,
  updated_at  timestamptz not null default now(),
  updated_by  uuid references profiles(id) on delete set null,
  constraint page_visibility_one_subject check (role_id is null or profile_id is null),
  constraint page_visibility_unique unique nulls not distinct (page_key, role_id, profile_id)
);

comment on table page_visibility is
  'אילו דפים מוצגים (0215): שורה למנהלי מערכת (בלי תפקיד ובלי משתמש), לתפקיד או למשתמש. '
  'שכבת תצוגה בלבד — הנתונים נשלטים בהרשאות. נכתבת רק דרך page_visibility_set.';

create index page_visibility_profile_idx on page_visibility (profile_id) where profile_id is not null;
create index page_visibility_role_idx on page_visibility (role_id) where role_id is not null;

create trigger page_visibility_audit after insert or update or delete
  on page_visibility for each row execute function app.audit();

alter table page_visibility enable row level security;
revoke all on page_visibility from anon, public;
revoke insert, update, delete, truncate on page_visibility from authenticated;
grant select on page_visibility to authenticated;

-- קריאה: מי שמנהל משתמשים או תפקידים, ומי שהשורה עוסקת בו. הכתיבה עוברת
-- רק דרך `page_visibility_set`, ולכן אין כאן פוליסת כתיבה בכלל — גם מנהל
-- מערכת אינו כותב לטבלה ישירות.
create policy page_visibility_read on page_visibility for select to authenticated using (
  (select app.is_admin())
  or profile_id = (select app.profile_id())
  or ((select app.user_kind()) = 'staff'
      and ((select app.has('users.view')) or (select app.has('settings.permissions'))))
  or (profile_id is not null and app.can_manage_profile(profile_id))
  or (role_id is not null
      and ((select app.has('users.view')) or (select app.has('settings.permissions'))
           or role_id = any ((select app.my_role_ids())::uuid[]))));

-- ===== 2. הכתיבה ============================================================
--
-- ‏`p_visible`: ‏true מוצג, ‏false מוסתר, ‏null — ירושה (השורה נמחקת). בדיוק
-- אחד משלושת היעדים: מנהלי מערכת, תפקיד, משתמש.
--
--   * מנהלי מערכת — רק מנהל מערכת קובע מה יוצג להם, וכך גם למנהל מערכת בודד.
--   * תפקיד — מי שעורך תפקידים (`settings.permissions`), כמו `role_permissions`.
--   * משתמש — מי שעורך הרשאות פר-משתמש ורשאי לנהל אותו, כמו
--     `user_permission_grants` (0214 §7).

create or replace function public.page_visibility_set(
  p_page_key text, p_visible boolean,
  p_role_id uuid default null, p_profile_id uuid default null, p_admins boolean default false)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_admins       boolean := coalesce(p_admins, false);
  v_target_admin boolean := false;
begin
  if p_page_key is null or p_page_key !~ '^[a-z][a-z0-9_]{0,47}$' then
    raise exception 'מזהה דף לא תקין' using errcode = '22023';
  end if;
  if (case when v_admins then 1 else 0 end)
     + (case when p_role_id is not null then 1 else 0 end)
     + (case when p_profile_id is not null then 1 else 0 end) <> 1 then
    raise exception 'יש לבחור בדיוק אחד: מנהלי מערכת, תפקיד או משתמש' using errcode = '22023';
  end if;

  if v_admins then
    if not app.is_admin() then
      raise exception 'רק מנהל מערכת קובע אילו דפים יוצגו למנהלי מערכת' using errcode = '42501';
    end if;
  elsif p_role_id is not null then
    if not (app.is_admin() or app.has('settings.permissions')) then
      raise exception 'אין לך הרשאה לערוך תפקידים' using errcode = '42501';
    end if;
    if not exists (select 1 from permission_roles where id = p_role_id and deleted_at is null) then
      raise exception 'התפקיד לא נמצא' using errcode = '22023';
    end if;
  else
    select p.is_admin into v_target_admin from profiles p
     where p.id = p_profile_id and p.deleted_at is null;
    if not found then
      raise exception 'המשתמש לא נמצא' using errcode = '22023';
    end if;
    if v_target_admin and not app.is_admin() then
      raise exception 'רק מנהל מערכת קובע אילו דפים יוצגו למנהל מערכת' using errcode = '42501';
    end if;
    if not (app.is_admin()
            or (app.has('users.manage_permissions') and app.can_manage_profile(p_profile_id))) then
      raise exception 'אין לך הרשאה לערוך את הדפים של המשתמש הזה' using errcode = '42501';
    end if;
  end if;

  if p_page_key = 'settings' and p_visible is false and (v_admins or v_target_admin) then
    raise exception 'אי אפשר להסתיר את ההגדרות ממנהל מערכת — משם מחזירים דפים שהוסתרו'
      using errcode = '22023';
  end if;

  if p_visible is null then
    delete from page_visibility
     where page_key = p_page_key
       and role_id is not distinct from p_role_id
       and profile_id is not distinct from p_profile_id;
  else
    insert into page_visibility (page_key, role_id, profile_id, visible, updated_by)
    values (p_page_key, p_role_id, p_profile_id, p_visible, app.profile_id())
    on conflict on constraint page_visibility_unique do update
      set visible = excluded.visible, updated_at = now(), updated_by = excluded.updated_by;
  end if;
end $$;

revoke execute on function public.page_visibility_set(text, boolean, uuid, uuid, boolean) from anon, public;
grant execute on function public.page_visibility_set(text, boolean, uuid, uuid, boolean) to authenticated;

comment on function public.page_visibility_set(text, boolean, uuid, uuid, boolean) is
  'קביעת דף כמוצג/מוסתר/ירושה (0215) למנהלי מערכת, לתפקיד או למשתמש. ההגדרות אינן '
  'מוסתרות ממנהל מערכת.';

-- ===== 3. ההכרעה ============================================================
--
-- הדפים המוסתרים מהקורא. הבבואה שלה במסך היא `resolvePageVisibility`
-- (src/app/pages.ts), שמסבירה במסך העריכה *למה* דף מוסתר — ושתיהן משתנות יחד.

create or replace function app.hidden_pages() returns text[]
language sql stable security definer set search_path = public as $$
  with me as (
    select app.profile_id() as id, app.is_admin() as admin, app.my_role_ids() as roles
  ),
  personal as (
    select pv.page_key, pv.visible
      from page_visibility pv cross join me
     where pv.profile_id = me.id
  ),
  grouped as (
    select pv.page_key, bool_or(pv.visible) as visible
      from page_visibility pv cross join me
     where pv.profile_id is null
       and ((pv.role_id is null and me.admin) or pv.role_id = any (me.roles))
     group by pv.page_key
  )
  select coalesce(array_agg(k.page_key order by k.page_key), '{}'::text[])
    from (select page_key from personal union select page_key from grouped) k
    cross join me
    left join personal p on p.page_key = k.page_key
    left join grouped g on g.page_key = k.page_key
   where not coalesce(p.visible, g.visible, true)
     and not (me.admin and k.page_key = 'settings')
$$;

revoke execute on function app.hidden_pages() from anon, public;
grant execute on function app.hidden_pages() to authenticated;

-- ===== 4. ‏get_my_permissions ===============================================
--
-- מועתקת מ-0196 מילה במילה; השינוי היחיד הוא השדה `hidden_pages`.

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
