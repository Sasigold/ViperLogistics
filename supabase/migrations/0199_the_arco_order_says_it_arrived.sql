-- 0199: הזמנה שארקו דוחפת דרך Make מגיעה גם כהתראה
--
-- ‏"כשארקו דוחפים אירוע דרך ה-Make — שתהיה לי גם התראה במערכת."
--
-- עד היום משלוח מארקו היה שקט לגמרי: האירוע נפתח, המשימות נכתבו, ושורה
-- נוספה במסך האינטגרציות — ואיש לא ידע על כך עד שנכנס לחפש. ‏`event_created`
-- (0110) אינו יורה, כי הוא מגודר על "הפותח הוא משתמש לקוח", ולאירוע של ארקו
-- אין `created_by` בכלל.
--
-- ארבע הכרעות:
--
--   1. **הגלאי הוא שורת המשלוח, לא האירוע.** ‏`arco_ingest_event` ו-
--      ‏`arco_ingest_spec` (0183) מסיימות כל משלוח בעדכון אחד של
--      ‏`arco_deliveries` שקובע סטטוס ומחזיק את התשובה המלאה. טריגר על העדכון
--      הזה יודע בדיוק מה קרה — נפתח, עודכן, מפרט, נכשל — בלי לגעת בשתי
--      הפונקציות, ו"הרץ מחדש" (שכותב שורה חדשה) מקבל את אותו טיפול בחינם.
--
--   2. **עדכון בלי שינוי אינו חדשות.** ‏Make שולח את אותה הזמנה שוב ושוב, ורובן
--      אינן משנות דבר. "האם השתנה משהו" היא "האם היומן קיבל שורה" — אותו גלאי
--      של 0112 ו-0184 — ושורות היומן של הטרנזקציה הזו הן מה שההתראה מפרטת.
--
--   3. **כישלון הוא הראשון שצריך לשמוע עליו.** מעטפה שלא נקלטה אינה מחזירה
--      שגיאה ל-Make (0183 §5), ולכן בלי התראה היא שורה אדומה שאיש לא רואה.
--      הזמנה שלא נקלטה היא בדיוק הזמנה שארקו חושבת שנמצאת אצלנו.
--
--   4. **סוג אחד, ארבע כותרות.** המנהל מכבה או מצמצם "הזמנות מארקו" כיחידה
--      אחת במטריצה, ואינו צריך לדעת שיש מאחוריה ארבעה מסלולים.

-- ===== 1. הסוג ============================================================

select app.register_notification_type('arco_order_received',
  'הזמנה מארקו',
  'ארקו דחפה הזמנה דרך Make: אירוע חדש, עדכון שינה משהו, מפרט חדש, '
  'או הזמנה שלא נקלטה',
  'אירועים', array['admin'], 'event', 'forced', 'opt_out', 'opt_in', 50);

-- ===== 2. מה השמירה הזו שינתה ==============================================
--
-- שורות היומן שנכתבו בטרנזקציה הנוכחית, כשורות לאדם. ‏`created_at` הוא
-- ‏`now()` — שעת תחילת הטרנזקציה — ולכן השוואה מדויקת אליו היא "נכתב עכשיו".
-- ‏'synced' אינו שינוי אלא הערת סנכרון, ו-'created' אינו עדכון.
create or replace function app.arco_tx_changes(p_event uuid)
returns text[] language sql stable security definer set search_path = public as $$
  select coalesce(array_agg(line order by id), '{}')
    from (
      select a.id,
             case a.kind
               when 'changed' then
                 a.field_label || ': ' || coalesce(left(a.new_value, 100), '—')
                 || ' (היה ' || coalesce(left(a.old_value, 100), '—') || ')'
               else coalesce(nullif(btrim(a.note), ''), a.kind::text)
             end as line
        from event_activity a
       where a.event_id = p_event
         and a.created_at = now()
         and a.kind not in ('created', 'synced')) s
$$;

comment on function app.arco_tx_changes(uuid) is
  'מה השמירה הנוכחית שינתה באירוע, לפי היומן — לגוף ההתראה על הזמנת ארקו (0199).';

-- ===== 3. ההתראה ==========================================================
create or replace function app.arco_notify_delivery()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  r          record;
  v_customer uuid;
  v_cname    text;
  v_event    events;
  v_label    text;
  v_title    text;
  v_body     text;
  v_changes  text[];
begin
  -- רק המעבר מ"התקבל" ל"עובד" — עדכון מאוחר של אותה שורה אינו משלוח חדש.
  if old.processed_at is not null or new.processed_at is null then return new; end if;

  select customer_id into v_customer from arco_connections where id = new.connection_id;
  if v_customer is null then return new; end if;
  if not app.notification_in_scope('arco_order_received', 'customer', v_customer) then
    return new;
  end if;

  v_cname := coalesce((select name from customers where id = v_customer), 'ארקו');
  select * into v_event from events where id = new.event_row_id and deleted_at is null;
  v_label := v_cname || coalesce(' · הזמנה ' || coalesce(v_event.event_number, new.order_number), '');

  if new.status = 'failed' then
    v_title := 'הזמנה מארקו לא נקלטה';
    v_body  := v_label || ' — ' || coalesce(new.reason, 'סיבה לא ידועה');

  elsif new.status = 'applied' and v_event.id is not null and new.kind = 'spec' then
    v_title := 'מפרט חדש מארקו';
    v_body  := v_label || coalesce(' · ' || v_event.end_client_name, '')
            || ' · ' || to_char(v_event.event_date, 'DD/MM/YYYY');

  elsif new.status = 'applied' and v_event.id is not null
        and new.result ->> 'status' = 'created' then
    v_title := 'אירוע חדש מארקו';
    v_body  := v_label || coalesce(' · ' || v_event.end_client_name, '')
            || ' · ' || to_char(v_event.event_date, 'DD/MM/YYYY')
            || coalesce(' · ' || v_event.location_text, '');

  elsif new.status = 'applied' and v_event.id is not null
        and new.result ->> 'status' = 'updated' then
    v_changes := app.arco_tx_changes(v_event.id);
    -- §2 בכותרת: משלוח חוזר שלא שינה דבר אינו חדשות.
    if cardinality(v_changes) = 0 then return new; end if;
    v_title := 'ארקו עדכנה הזמנה';
    v_body  := v_label || ' — ' || array_to_string(v_changes, ' · ');

  else
    -- 'ignored': חיבור כבוי, מפרט שהקדים את ההזמנה, מפרט זהה — אין מה לבשר.
    return new;
  end if;

  -- כל מנהלי המערכת. אין כאן `app.profile_id()` לסנן — המשלוח אינו אדם,
  -- ו"הרץ מחדש" של מנהל הוא בדיוק מה שהוא רוצה לראות שהצליח.
  for r in select id from profiles
    where is_admin and is_active and deleted_at is null
  loop
    perform app.notify(r.id, 'arco_order_received', v_title, left(v_body, 500),
      case when v_event.id is not null then 'event' end, v_event.id);
  end loop;

  return new;
end $$;

create trigger arco_deliveries_notify
  after update on arco_deliveries
  for each row execute function app.arco_notify_delivery();

-- ===== 4. והחדשות סגורות כמו הוותיקות (0183 §7) ============================
revoke execute on function app.arco_tx_changes(uuid)  from anon, authenticated, public;
revoke execute on function app.arco_notify_delivery() from anon, authenticated, public;
