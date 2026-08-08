-- 0047: שני סוגי התראה חדשים
--
-- מיגרציה נפרדת מ-0046 בכוונה. 0046 היא המנוע — הקטלוג, המטריצה וההכרעה.
-- כאן יושבים *הפולטים*, ומי שירצה מחר לבטל התראה מסוימת יוכל להסיר טריגר
-- בלי לגעת במנוע שכל שאר הסוגים תלויים בו.
--
-- הסוגים נבחרו כדי לסגור שני חורים אמיתיים:
--
--   • ללקוח לא יצאה עד היום שום התראה. event_created, הסוג היחיד שנוגע בו,
--     נשלח דווקא *למנהלים*. ציר "לקוחות" במטריצת ההגדרות היה נולד ריק,
--     ושליטה על משהו שאינו קיים אינה שליטה.
--   • ביטול שיבוץ היה שקט לחלוטין. שיבוץ מודיע לעובד (0004), והסרתו — לא,
--     כך שעובד שהוסר ממשמרת המשיך להתכונן אליה.

-- ===== 1. שינוי סטטוס אירוע → משתמשי הלקוח ==========================
--
-- הנקודה היא טריגר ולא ה-RPC update_event, משלוש סיבות: update_event כבר
-- הוגדרה מחדש פעמיים (0006 ← 0009 ← 0015) והייתה נדרשת הגדרה רביעית מלאה;
-- הסטטוס נכתב גם ישירות מלוח העבודה ומלוח השנה; ו-0016 כבר קבע את
-- `after update on events` כנקודת החיבור המקובלת לשינויים באירוע.

select app.register_notification_type('event_status_changed', 'סטטוס האירוע שלי השתנה',
  'האירוע עבר לסטטוס אחר — אושר, מתקיים או בוטל', 'אירועים',
  array['admin','staff','customer_user'], 'event',
  'opt_out', 'opt_out', 'opt_in', 45);

create or replace function app.notify_event_status_change()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_actor  uuid := app.profile_id();
  v_status text;
  v_label  text;
  r record;
begin
  if old.status_id is not distinct from new.status_id then return new; end if;
  -- מחיקה רכה מגיעה כ-update והייתה נראית כשינוי סטטוס. אינה.
  if new.deleted_at is not null then return new; end if;

  select s.name into v_status from statuses s where s.id = new.status_id;
  v_label := coalesce(new.end_client_name, new.event_number,
                      to_char(new.event_date, 'DD/MM/YYYY'));

  for r in select p.id from profiles p
    where p.customer_id = new.customer_id
      and p.user_kind = 'customer_user'
      and p.is_active and p.deleted_at is null
      -- `is distinct from` ולא `<>`: app.profile_id() הוא null בכתיבת
      -- service-role ובמיגרציות, ו-`<>` מול null היה מסנן את כולם החוצה.
      and p.id is distinct from v_actor
  loop
    perform app.notify(r.id, 'event_status_changed', 'סטטוס האירוע עודכן',
      v_label || ' — ' || coalesce(v_status, '—'), 'event', new.id);
  end loop;
  return new;
end $$;

create trigger events_notify_status after update of status_id on events
  for each row execute function app.notify_event_status_change();

-- ===== 2. ביטול שיבוץ → העובד =======================================

select app.register_notification_type('assignment_removed', 'הוסרתי משיבוץ למשימה',
  'שיבוץ שלי למשימה בוטל', 'משימות', array['staff'], 'task',
  'forced', 'opt_out', 'opt_in', 15);

create or replace function app.notify_assignment_removed()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_task tasks; v_label text;
begin
  /*
   * מחיקת משימה מפילה את השיבוצים בקסקייד (0003: on delete cascade).
   * בלי הבדיקה הזו, מחיקה אחת של משימה הייתה שולחת "השיבוץ שלך בוטל" לכל
   * מי ששובץ אליה — רעש על משהו שכבר אינו קיים. אם המשימה איננה, שקט.
   */
  select * into v_task from tasks where id = old.task_id and deleted_at is null;
  if not found then return old; end if;

  -- מי שהסיר את עצמו יודע שהסיר את עצמו
  if old.profile_id is not distinct from app.profile_id() then return old; end if;

  v_label := coalesce(v_task.title,
                      (select tt.name from task_types tt where tt.id = v_task.task_type_id),
                      'משימה');
  perform app.notify(old.profile_id, 'assignment_removed', 'השיבוץ שלך בוטל',
    v_label || ' בתאריך ' || to_char(v_task.task_date, 'DD/MM/YYYY'), 'task', old.task_id);
  return old;
end $$;

create trigger task_assignments_notify_removed after delete on task_assignments
  for each row execute function app.notify_assignment_removed();

-- ===== 3. ציר הלקוחות אינו נולד ריק =================================
--
-- ברירות המחדל בקטלוג כבר נותנות ללקוח מייל על שינוי סטטוס. השורה המפורשת
-- כאן קיימת כדי שהמנהל *יראה* אותה במטריצה כהחלטה שנקבעה, ולא כתא ריק
-- שמתנהג במקרה נכון.
insert into notification_policies (audience, type, channel, mode) values
  ('customer_user', 'event_status_changed', 'inapp', 'opt_out'),
  ('customer_user', 'event_status_changed', 'email', 'opt_out'),
  ('customer_user', 'event_status_changed', 'push',  'opt_in')
on conflict (audience, type, channel) do nothing;
