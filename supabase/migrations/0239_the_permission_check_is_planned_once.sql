-- 0239: the permission check is planned once
--
-- אחרי 0237 ההרשאות נטענות, אבל "לו״ז עבודה" (`work_board_view`, 0201) עדיין
-- איטי לכל מי שאינו מנהל מערכת: בייצור 1.4–1.7 שניות לשש שורות של איציק,
-- ועל שרת חלש יותר — מעבר ל-`statement_timeout`. בתוכנית השאילתה יש יותר מ-
-- 1,000 InitPlans: כל פוליסת RLS על כל טבלה שהתצוגה מצרפת שואלת את `app.has`
-- (127 פוליסות) או את `app.has_permission` (21), ולפעמים גם לכל שורה.
--
-- הבעיה אינה מה שהן שואלות אלא איך: הן `language sql` עם `security definer`
-- ו-`set search_path`, ולכן PostgreSQL אינו משבץ אותן בשאילתה (inline) ואינו
-- שומר את התוכנית שלהן — כל קריאה מתכננת מחדש את גוף הפונקציה. ל-`app.has`
-- זו שאילתה רקורסיבית עם ארבע תת-שאילתות: 5.1ms לקריאה בייצור,
-- ול-`has_permission`, שעוטפת אותה, 15ms. ‏plpgsql שומרת את התוכנית לכל
-- החיבור: 0.23ms לקריאה (פי 22), עם אותה תשובה לכל מפתח ולכל צורת הרשאות.
--
-- כאן חמש הפונקציות שבנתיב הזה עוברות ל-plpgsql, **באותה לוגיקה בדיוק**
-- (הגוף האחרון: `app.has` 0214, ‏`app.my_role_ids` 0104, ‏`has_permission`/
-- ‏`can_view_field`/`can_edit_field` 0010), והקורא נשלף פעם אחת לקריאה במקום
-- כמה פעמים. שום הרשאה לא משתנה; `app.profiles_with` ו-
-- ‏`src/lib/effectivePermission.ts` נשארים מראות של אותם כללים. סוויטה 80
-- משווה כל מפתח וכל שדה לגרסה הקודמת לכל צורת הרשאות.
--
-- כלל: פונקציית עזר שפוליסה קוראת לה, ושגופה יותר משליפה אחת פשוטה, נכתבת
-- ב-plpgsql.

-- ===== 1. app.has (0214) =====
create or replace function app.has(p_key text) returns boolean
language plpgsql stable security definer set search_path = public as $$
declare
  v_pid uuid; v_kind user_kind; v_admin boolean; v_roles uuid[]; v_ans boolean;
begin
  select id, user_kind, is_admin into v_pid, v_kind, v_admin
    from profiles where user_id = auth.uid() and is_active and deleted_at is null;
  if coalesce(v_admin, false) then return true; end if;
  if v_pid is null then return false; end if;
  -- ‏0214: מפתח לא פעיל, לא מוכר, או שאינו חל על סוג המשתמש — אינו מוענק
  -- בשום שכבה.
  if not exists (select 1 from permission_registry r
                  where r.key = p_key and r.is_active
                    and v_kind = any (r.applies_to)) then
    return false;
  end if;

  v_roles := app.my_role_ids();

  with recursive chain(key, depth) as (
    select p_key, 0
    union all
    select r.implied_by, c.depth + 1
    from chain c
    join permission_registry r on r.key = c.key
    where r.implied_by is not null and c.depth < 8
  )
  select x.decided into v_ans from (
    select c.depth, coalesce(
      (select g.allowed from user_permission_grants g
        where g.profile_id = v_pid and g.permission_key = c.key),
      (select bool_or(rp.allowed) from role_permissions rp
        where rp.role_id = any(v_roles) and rp.permission_key = c.key),
      (select k.allowed from kind_permission_defaults k
        where k.user_kind = v_kind and k.permission_key = c.key),
      (select true from permission_registry r
        where r.key = c.key and r.is_active and r.default_allowed)
    ) as decided
    from chain c
  ) x
  where x.decided is not null
  order by x.depth
  limit 1;

  return coalesce(v_ans, false);
end $$;

comment on function app.has(text) is
  'ההכרעה היחידה על מפתח (0010). מאז 0214: מפתח שאינו חל על סוג המשתמש (applies_to), '
  'או שאינו פעיל, אינו מוענק בשום שכבה. מאז 0239 ב-plpgsql (התוכנית נשמרת לחיבור).';

-- ===== 2. app.has_permission (0010) =====
create or replace function app.has_permission(p_resource text, p_action permission_action)
returns boolean language plpgsql stable security definer set search_path = public as $$
begin
  return app.has(p_resource || '.' || p_action::text);
end $$;

-- ===== 3. app.my_role_ids (0104) =====
create or replace function app.my_role_ids() returns uuid[]
language plpgsql stable security definer set search_path = public as $$
declare v_pid uuid; v_kind user_kind; v_ids uuid[];
begin
  select id, user_kind into v_pid, v_kind
    from profiles where user_id = auth.uid() and is_active and deleted_at is null;
  if v_pid is null then return '{}'::uuid[]; end if;

  with mine as (
    select r.id, r.key
    from profile_roles pr
    join permission_roles r on r.id = pr.role_id
    where pr.profile_id = v_pid and r.is_active and r.deleted_at is null
      -- 0067: תפקיד שנקשר לסוג משתמש אינו חל על סוג אחר
      and (r.user_kind is null or r.user_kind = v_kind)
  )
  select coalesce(array_agg(id), '{}'::uuid[]) into v_ids
  from mine
  where key <> 'contractor_worker'
     or not exists (select 1 from mine m2
                     where m2.key in ('contractor_manager', 'staff_contractor'));
  return v_ids;
end $$;

comment on function app.my_role_ids() is
  'התפקידים שבתוקף לקורא. מסנן תפקיד שאינו תואם לסוג המשתמש (0067), ומשמיט '
  'את תפקיד עובד הקבלן ממי שגם מנהל קבלן (0104): הכובע המנהל גובר. plpgsql מאז 0239.';

-- ===== 4. app.can_view_field (0010) =====
create or replace function app.can_view_field(p_entity text, p_field text)
returns boolean language plpgsql stable security definer set search_path = public as $$
declare v_pid uuid; v_kind user_kind; v_admin boolean;
begin
  select id, user_kind, is_admin into v_pid, v_kind, v_admin
    from profiles where user_id = auth.uid() and is_active and deleted_at is null;
  if coalesce(v_admin, false) then return true; end if;
  if v_pid is null then return false; end if;
  return coalesce(
    (select f.can_view from field_permissions f
      where f.profile_id = v_pid and f.entity = p_entity and f.field_key = p_field),
    (select bool_or(f.can_view) from field_permissions f
      where f.role_id = any(app.my_role_ids()) and f.entity = p_entity and f.field_key = p_field),
    (select f.can_view from field_permissions f
      where f.profile_id is null and f.role_id is null
        and f.user_kind = v_kind
        and f.entity = p_entity and f.field_key = p_field),
    (select fr.default_can_view from field_registry fr
      where fr.entity = p_entity and fr.field_key = p_field),
    true);
end $$;

-- ===== 5. app.can_edit_field (0010) =====
create or replace function app.can_edit_field(p_entity text, p_field text)
returns boolean language plpgsql stable security definer set search_path = public as $$
declare v_pid uuid; v_kind user_kind; v_admin boolean;
begin
  select id, user_kind, is_admin into v_pid, v_kind, v_admin
    from profiles where user_id = auth.uid() and is_active and deleted_at is null;
  if coalesce(v_admin, false) then return true; end if;
  if v_pid is null then return false; end if;
  if not app.can_view_field(p_entity, p_field) then return false; end if;
  return coalesce(
    (select f.can_edit from field_permissions f
      where f.profile_id = v_pid and f.entity = p_entity and f.field_key = p_field),
    (select bool_or(f.can_edit) from field_permissions f
      where f.role_id = any(app.my_role_ids()) and f.entity = p_entity and f.field_key = p_field),
    (select f.can_edit from field_permissions f
      where f.profile_id is null and f.role_id is null
        and f.user_kind = v_kind
        and f.entity = p_entity and f.field_key = p_field),
    (select fr.default_can_edit from field_registry fr
      where fr.entity = p_entity and fr.field_key = p_field),
    true);
end $$;
