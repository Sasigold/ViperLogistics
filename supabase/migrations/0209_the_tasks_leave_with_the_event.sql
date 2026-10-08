-- 0209: המשימות יוצאות עם האירוע
--
-- ‏**הבאג.** ‏`soft_delete('events', …)` מסמן `deleted_at` על האירוע בלבד, ולא
-- נוגע במשימות שלו (0123 כבר תיעד את זה, ותיקן רק את הלו״ז: `work_board_view`
-- בודק `e.deleted_at`). ‏`app.live_tasks` (0114) — הבסיס של כל ספירה ושל כל
-- סכום — בודק רק "האירוע בוטל", לא "האירוע נמחק". התוצאה: משימות של אירוע
-- שנמחק המשיכו להיספר בדשבורד ("משימות לפי לקוח" הראה 102 לשיא עיצובים מול
-- 61 בלו״ז), וגם בהכנסות, ברווחיות ובעלות הקבלנים. בפרודקשן, ברגע כתיבת
-- המיגרציה: 58 משימות של 29 אירועים מחוקים, ‏94,782 ₪ הכנסה ו-7,200 ₪ עלות
-- קבלן (אף שורה לא שולמה).
--
-- ‏**התיקון, שלוש שכבות:**
--   1. ‏`app.live_tasks` מוציאה גם משימה שהאירוע שלה נמחק — כך שום מסלול
--      שמסמן אירוע כמחוק בלי לעבור כאן לא יחזיר את הבאג.
--   2. ‏טריגר על `events`: מחיקת אירוע מוחקת את המשימות החיות שלו, באותה
--      חותמת זמן. שחזור האירוע משחזר בדיוק את המשימות שנמחקו **איתו** (אותה
--      חותמת) — משימה שנמחקה לבד לפני כן נשארת מחוקה.
--   3. ‏שחזור משימה בודדת של אירוע מחוק חסום: משחזרים את האירוע, והמשימות
--      חוזרות איתו.
-- ועוד מילוי לאחור של המשימות היתומות הקיימות, עם חותמת המחיקה של האירוע
-- שלהן — כדי ששחזור האירוע מסל המיחזור יחזיר גם אותן.
--
-- ‏**סדר הטריגרים.** ‏`events_release_crew` (0200) משחרר את הסגל של המשימות
-- **החיות** של האירוע. טריגרים מאותו סוג רצים בסדר אלפביתי, ולכן השם
-- ‏`events_z_tasks_follow_delete`: הסגל משתחרר קודם, והמשימות נמחקות אחריו.
--
-- ‏**משימות "לא בלו״ז" (0188)** נספרות בדשבורד — זה לא משתנה כאן. הן משימות
-- אמיתיות שפשוט לא מוצגות בלוח.

-- ===== 1. app.live_tasks מוציאה גם משימה של אירוע שנמחק =====================
-- הגוף זהה ל-0114, ותוספת אחת: `e.deleted_at is not null`. ‏`not exists`
-- נשאר: משימה עצמאית (בלי אירוע) היא משימה אמיתית ונשארת.
create or replace view app.live_tasks with (security_invoker = true) as
  select t.*
    from tasks t
   where t.deleted_at is null
     and not exists (select 1 from events e
                      where e.id = t.event_id
                        and (e.deleted_at is not null
                             or e.status_id = (select app.cancelled_event_status_id())));

comment on view app.live_tasks is
  'משימות שלא נמחקו ושהאירוע שלהן לא בוטל ולא נמחק (0114, 0209). משימה בלי אירוע נשארת.';

grant select on app.live_tasks to authenticated;

-- ===== 2. מחיקת אירוע מוחקת את המשימות שלו, ושחזורו משחזר אותן =============
create or replace function app.event_delete_cascades_tasks()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_prev boolean := app.in_system_write();
begin
  if old.deleted_at is null and new.deleted_at is not null then
    -- כתיבת מערכת: מי שמחק את האירוע אינו צריך הרשאה על כל שדה במשימה
    -- (לקוח שמוחק את האירוע שלו נתקל אחרת ב-enforce_customer_board_edit).
    perform app.system_write(true);
    update tasks set deleted_at = new.deleted_at
     where event_id = new.id and deleted_at is null;
    perform app.system_write(v_prev);
  elsif old.deleted_at is not null and new.deleted_at is null then
    perform app.system_write(true);
    update tasks set deleted_at = null
     where event_id = new.id and deleted_at = old.deleted_at;
    perform app.system_write(v_prev);
  end if;
  return null;
end $$;

comment on function app.event_delete_cascades_tasks() is
  'מחיקת אירוע מוחקת את משימותיו החיות באותה חותמת; שחזורו משחזר את מה '
  'שנמחק איתו (0209).';

revoke execute on function app.event_delete_cascades_tasks() from anon, public;

drop trigger if exists events_z_tasks_follow_delete on events;
create trigger events_z_tasks_follow_delete after update of deleted_at on events
  for each row execute function app.event_delete_cascades_tasks();

-- ===== 3. משימה של אירוע מחוק אינה משוחזרת לבד ============================
create or replace function app.task_restore_needs_live_event()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if old.deleted_at is not null and new.deleted_at is null
     and exists (select 1 from events e
                  where e.id = new.event_id and e.deleted_at is not null) then
    raise exception 'המשימה שייכת לאירוע שנמחק — שחזרו את האירוע, והמשימות יחזרו איתו'
      using errcode = '22023';
  end if;
  return new;
end $$;

comment on function app.task_restore_needs_live_event() is
  'חוסם שחזור משימה בודדת של אירוע מחוק (0209).';

revoke execute on function app.task_restore_needs_live_event() from anon, public;

drop trigger if exists tasks_restore_needs_live_event on tasks;
create trigger tasks_restore_needs_live_event before update of deleted_at on tasks
  for each row execute function app.task_restore_needs_live_event();

-- ===== 4. מילוי לאחור: המשימות היתומות נמחקות עם חותמת האירוע ==============
select app.system_write(true);
update tasks t
   set deleted_at = e.deleted_at
  from events e
 where e.id = t.event_id
   and e.deleted_at is not null
   and t.deleted_at is null;
select app.system_write(false);
