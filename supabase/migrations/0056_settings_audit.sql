-- ===========================================================================
-- 0056 — יומן ביקורת על טבלאות התצורה
-- ===========================================================================
--
-- app_settings מחזיקה בין השאר את attendance.overtime — מדרגות השעות
-- הנוספות שמזינות את חישוב השכר של כולם. עד עכשיו שינוי בה לא הותיר שום
-- עקבה: מי שינה, מתי, ומה היה הערך הקודם. אותו דין לתפקידי הסגל
-- (staff_roles) ולמטריצת ההתראות (notification_policies והחברות).
--
-- המלכודת: app.audit() (הגדרה אחרונה ב-0010) גוזרת row_id מסוג uuid
-- מ-id או מאחד ה-fallbacks (task_id, event_id, profile_id...), ומדלגת
-- בשקט על שורה שאין לה מפתח כזה. לשלוש מהטבלאות כאן המפתח טקסטואלי —
-- app_settings(key), notification_types(key),
-- notification_policies(audience, type, channel) — ולכן חיבור הטריגר
-- כמות-שהוא היה רושם בדיוק כלום. בעקבות התקדים של 0010 ("teach it the
-- new synthetic sources"), מלמדים את הפונקציה לגזור uuid דטרמיניסטי
-- מהמפתח הטקסטואלי: md5 של שם הטבלה והמפתח נוצק ל-uuid, כך שכל
-- ההיסטוריה של הגדרה אחת חולקת row_id אחד וניתנת לשליפה יחד.

create or replace function app.audit()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_old jsonb; v_new jsonb; v_changed text[]; v_row_id uuid;
begin
  if tg_op = 'INSERT' then
    v_new := to_jsonb(new); v_row_id := (v_new ->> 'id')::uuid;
  elsif tg_op = 'UPDATE' then
    v_old := to_jsonb(old); v_new := to_jsonb(new); v_row_id := (v_new ->> 'id')::uuid;
    select coalesce(array_agg(key), '{}') into v_changed
    from jsonb_each(v_new) as n(key, value)
    where v_old -> key is distinct from value;
    if v_changed = '{}' then return new; end if;
  else
    v_old := to_jsonb(old); v_row_id := (v_old ->> 'id')::uuid;
  end if;
  if v_row_id is null then
    v_row_id := coalesce(
      (coalesce(v_new, v_old) ->> 'task_id')::uuid,
      (coalesce(v_new, v_old) ->> 'event_id')::uuid,
      (coalesce(v_new, v_old) ->> 'profile_id')::uuid,
      (coalesce(v_new, v_old) ->> 'customer_id')::uuid,
      (coalesce(v_new, v_old) ->> 'role_id')::uuid);
  end if;
  -- מפתח טקסטואלי -> uuid דטרמיניסטי. עמודת key קודמת, אחרת המפתח
  -- המשולש של notification_policies. השרשור אחרי כל ה-fallbacks של
  -- uuid כדי לא לשנות row_id של אף טבלה שכבר נרשמת.
  if v_row_id is null then
    v_row_id := case
      when coalesce(v_new, v_old) ? 'key'
        then md5(tg_table_name || ':' || (coalesce(v_new, v_old) ->> 'key'))::uuid
      when tg_table_name = 'notification_policies'
        then md5(tg_table_name || ':' || (coalesce(v_new, v_old) ->> 'audience')
                 || ':' || (coalesce(v_new, v_old) ->> 'type')
                 || ':' || (coalesce(v_new, v_old) ->> 'channel'))::uuid
    end;
  end if;
  if v_row_id is null then return coalesce(new, old); end if;
  insert into audit_log (actor_user_id, action, table_name, row_id, old_data, new_data, changed_cols)
  values (auth.uid(), tg_op::audit_action, tg_table_name, v_row_id, v_old, v_new, v_changed);
  return coalesce(new, old);
end $$;

do $$
declare t text;
begin
  foreach t in array array[
    'app_settings', 'staff_roles',
    'notification_types', 'notification_policies', 'notification_policy_overrides']
  loop
    execute format(
      'create trigger %I_audit after insert or update or delete on %I
         for each row execute function app.audit()', t, t);
  end loop;
end $$;
