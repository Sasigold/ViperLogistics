-- 0104: הכובע המנהל גובר — גם כשהעובד אומר לא
--
-- הדיווח: "מנהל קבלן שהוא גם עובד לא רואה דוח עובדים". שני התפקידים על אותו
-- אדם — `contractor_manager` ו-`contractor_worker` — ובפועל הוא איבד את
-- `portal.attendance`, כלומר את "נוכחות הסגל שלי", את לוח המשמרות, ואת מסנן
-- העובדים בדוח. נשאר לו דוח של אדם אחד: עצמו.
--
-- **למה זה קרה, ולמה זה לא נראה בבדיקות.** שכבת התפקידים ב-`app.has` היא
-- `bool_or`, ולכן הענקה בתפקיד אחד גוברת על דחייה בתפקיד אחר — אבל רק אם
-- ההענקה קיימת כשורה. ‏`portal.attendance` הגיע למנהל הקבלן מברירת המחדל של
-- **הקהל** (0019), שהיא שכבה 3; לתפקיד `contractor_worker` יש שורת דחייה
-- מפורשת עליו (‏`close_modules` של 0019 כתב אותה), והיא שכבה 2. שכבה 2 מדברת
-- ראשונה, ולכן הדחייה של העובד ניצחה ברירת מחדל שאיש לא התכוון שתיסוג.
--
-- זה מחלקה של באגים, לא באג יחיד: כל מפתח שמנהל הקבלן מקבל מברירת המחדל של
-- הקהל ולא משורת תפקיד יתהפך ברגע שיוצמד לו גם תפקיד העובד. לכן שני תיקונים,
-- ולא אחד:
--
--   1. **הכלל**: מי שנושא תפקיד מנהל קבלן אינו נשפט לפי תפקיד עובד הקבלן.
--      זה מה שהתבקש במילים "מנהל קבלן תמיד יגביר על עובד קבלן", והוא נכתב
--      במקום אחד — `app.my_role_ids()` — ולכן הוא חל על ההרשאות, על הרשאות
--      השדה ועל ההיקפים גם יחד.
--   2. **הנתונים**: בסיס התפקיד של מנהל הקבלן נכתב מחדש כהענקות מפורשות.
--      בפרויקט אמיתי הוא נשחק (עריכות במסך ההרשאות מוחקות שורות), ומפתח
--      שהגיע בירושה הוא מפתח שאפשר לאבד בלי לדעת — בדיוק כפי שקרה כאן.

-- ===== 1. הכלל: תפקיד עובד הקבלן אינו חל על מי שגם מנהל אותו ==============
--
-- ‏`app.my_role_ids()` הוא המקום היחיד שמכריע אילו תפקידים בתוקף (0067 כבר
-- מסנן שם תפקיד שאינו תואם לסוג המשתמש), ולכן זה המקום היחיד שצריך לדעת על
-- הבכורה הזו.
--
-- הצמצום בטוח משתי סיבות שנבדקו ולא הונחו: ל-`contractor_worker` אין שורות
-- ב-`permission_scopes` ואין לו שורות ב-`field_permissions`, ולכן הסרתו אינה
-- מרחיבה שורות ואינה נוגעת בשדות. מה שהיא כן מסירה הן הדחיות שלו — וזה בדיוק
-- מה שהתבקש.
--
-- שני מפתחות השייכים לעובד ואינם למנהל — דיווח ידני והשכר של עצמו — עוברים
-- אליו בסעיף 2, כדי שהצמצום לא ייקח ממנו את מה שהוא כן צריך כעובד.
create or replace function app.my_role_ids() returns uuid[]
language sql stable security definer set search_path = public as $$
  with mine as (
    select r.id, r.key
    from profile_roles pr
    join permission_roles r on r.id = pr.role_id
    where pr.profile_id = app.profile_id() and r.is_active and r.deleted_at is null
      -- 0067: תפקיד שנקשר לסוג משתמש אינו חל על סוג אחר
      and (r.user_kind is null or r.user_kind = app.user_kind()::user_kind)
  )
  select coalesce(array_agg(id), '{}'::uuid[])
  from mine
  where key <> 'contractor_worker'
     or not exists (select 1 from mine m2
                     where m2.key in ('contractor_manager', 'staff_contractor'))
$$;

comment on function app.my_role_ids() is
  'התפקידים שבתוקף לקורא. מסנן תפקיד שאינו תואם לסוג המשתמש (0067), ומשמיט '
  'את תפקיד עובד הקבלן ממי שגם מנהל קבלן (0104): הכובע המנהל גובר.';

-- ===== 2. בסיס התפקיד של מנהל הקבלן, כהענקות מפורשות ======================
--
-- ‏`upsert` ולא `app.set_role_permissions`: היא מוחקת את *כל* שורות התפקיד,
-- כולל דחיות ששרדו מ-0072 ומ-0075 והחלטות שנקבעו במסך ההרשאות. כאן נכתבות
-- ההענקות בלבד, ומה שאינו ברשימה אינו נגרע.
--
-- ‏`portal.attendance` הוא הלב: הוא מה שהופך את `/attendance` ל"נוכחות הסגל
-- שלי", מה שפותח את לוח המשמרות ומה שמצייר את מסנן העובדים בדוח.
insert into role_permissions (role_id, permission_key, allowed)
select r.id, k, true
from permission_roles r,
     unnest(array[
       -- הפורטל שלו
       'portal.view', 'portal.assign_workers', 'portal.view_financials',
       'portal.manage_workers', 'portal.attendance', 'portal.attendance_pay',
       'portal.approve_attendance', 'portal.worker_settings',
       -- המסכים המשותפים (0072 §1)
       'calendar.view', 'board.view', 'board.view_staffing', 'board.columns',
       'tasks.view', 'notifications.view', 'notifications.preferences', 'search.global',
       'contractors.view_pricing',
       -- דף האירוע, היומן והמפרט (0103)
       'events.view', 'events.activity_log', 'events.activity_note',
       -- והוא גם עובד: שעון, משמרות, דיווח ידני והשכר של עצמו. שני האחרונים
       -- הגיעו עד היום מתפקיד העובד, וסעיף 1 מפסיק להחיל אותו עליו.
       'attendance.view_own', 'attendance.view_schedule', 'attendance.clock',
       'attendance.submit_entry', 'attendance.view_own_pay'
     ]) k
where r.key = 'contractor_manager'
on conflict (role_id, permission_key) do update set allowed = true;

-- ומה שנשאר סגור לו נשאר סגור, במפורש ולא בהיסק: הקטלוג והייצוא (0103),
-- והמפתחות המשרדיים על קבלנים אחרים (0075 §2).
insert into role_permissions (role_id, permission_key, allowed)
select r.id, k, false
from permission_roles r,
     unnest(array['events.list', 'events.export',
                  'contractors.assign_workers', 'contractors.manage_workers',
                  'attendance.view_all', 'attendance.manage_pay', 'attendance.manage_clock']) k
where r.key = 'contractor_manager'
on conflict (role_id, permission_key) do update set allowed = false;

-- אותו טיפול לעובד שמביא סגל (0075): הוא מקבל את הכובע הקבלני על תפקיד
-- השטח שלו, ולכן הוא צריך את אותן הענקות מפורשות — בלי מפתחות האירוע, שאותם
-- הוא מקבל מתפקיד השטח שלו ממילא.
insert into role_permissions (role_id, permission_key, allowed)
select r.id, k, true
from permission_roles r,
     unnest(array['portal.view', 'portal.assign_workers', 'portal.view_financials',
                  'portal.manage_workers', 'portal.attendance', 'portal.attendance_pay',
                  'portal.approve_attendance', 'portal.worker_settings',
                  'contractors.view_pricing']) k
where r.key = 'staff_contractor'
on conflict (role_id, permission_key) do update set allowed = true;
