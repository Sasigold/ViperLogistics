-- 0051: מחיקת אירוע נכשלה — "column kind is of type event_activity_kind but expression is of type text"
--
-- ב-0016 הרישום של מחיקה/שחזור נכתב כך:
--
--   values (new.id,
--           case when new.deleted_at is null then 'restored' else 'deleted' end, ...)
--
-- שתי הזרועות של ה-CASE הן ליטרלים ללא טיפוס, ולכן PostgreSQL פותר את כל
-- הביטוי ל-text — בניגוד לליטרל בודד ב-VALUES, שנצבע לפי טיפוס העמודה. מ-text
-- ל-enum אין המרה אוטומטית בהשמה, ולכן כל UPDATE שמשנה את deleted_at על events
-- נופל: גם המחיקה הרכה וגם השחזור מסל המיחזור, מאז 0016.
--
-- 0049 כבר כתבה את אותו דפוס עם ::event_activity_kind מפורש. זה מיישר את 0016
-- לאותה צורה. אין כאן שינוי התנהגות מעבר לזה — שאר גוף הפונקציה זהה.

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
  return new;
end $$;
