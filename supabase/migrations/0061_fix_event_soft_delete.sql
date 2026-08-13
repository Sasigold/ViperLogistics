-- 0061: מחיקת אירוע נכשלה שוב — אותה שגיאה שכבר תוקנה ב-0051
--
--   column "kind" is of type event_activity_kind but expression is of type text
--
-- 0051 תיקנה את app.log_event_activity והוסיפה ::event_activity_kind ל-CASE
-- שבוחר בין 'restored' ל-'deleted'. 0053 הוסיפה לאותה פונקציה לולאה על
-- custom_fields — אבל כתבה אותה מעל הגוף של 0016, זה שקדם לתיקון, ולכן
-- ה-CASE חזר להיות text ומחיקת אירוע חזרה ליפול ב-400 מאז.
--
-- כאן הגוף של 0053 במלואו, עם ההמרה של 0051 בחזרה במקומה. אין כאן שינוי
-- התנהגות מעבר לזה.
--
-- מה שמונע את החזרה הבאה: בדיקה ב-supabase/tests/02_escalation.sql שמוחקת
-- אירוע ומשחזרת אותו. שתי הפעמים שהבאג הזה חי בפרודקשן היו שתי פעמים שבהן
-- שום דבר לא קרא ל-UPDATE הזה בבדיקות.

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
