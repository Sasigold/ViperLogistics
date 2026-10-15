-- 0234: הלקוח רואה גם את עובדי הקבלן בלו״ז
--
-- ‏**הבקשה (בעל המערכת).** לקוח ארקו רואה בלו״ז העבודה את שמות אנשי הצוות
-- הפנימיים ואת עובדי הלקוח, אבל לא את עובדי הקבלן שעל אותה משימה — ובכלל זה
-- ראש צוות של קבלן, שתא ראש הצוות נשאר אצלו ריק.
--
-- ‏**למה.** ‏`work_board_view` (0201) הוא `security_invoker`, ושלוש הרשימות שבו
-- עוברות דרך ה-RLS של טבלאות השיבוץ. ‏`ta_select` (0091) פותחת ללקוח את
-- השיבוצים הפנימיים במשימות שלו כשהוא מחזיק `board.view_staffing`; ‏`tcuw_select`
-- (0133) פותחת את עובדי הלקוח לכל מי שרואה את המשימה; אבל ל-`tcw_select`
-- (0105) אין זרוע ללקוח בכלל — צוות, קבלן, ומי שהמשימה הואצלה לקבלן שלו. השם
-- עצמו כבר עובר דרך `app.contractor_worker_identities` (שם וקבלן בלבד, 0201),
-- כך שהשורה החסרה היא שורת השיבוץ ולא פרטי העובד.
--
-- ושער שני: `app.contractor_worker_identities` (0201) נותנת שם לעובד קבלן רק
-- לצוות, לאדמין ולקבלן שלו — כך שגם שורת שיבוץ גלויה הייתה מגיעה ללקוח בלי
-- שם, והרשימה ב-view נשארת ריקה.
--
-- ‏**התיקון.** ‏`tcw_select` מקבלת את אותה זרוע ש-`ta_select` נותנת ללקוח: לקוח
-- שמחזיק `board.view_staffing`, במשימה של הלקוח שלו (`app.assignment_on_my_customer`,
-- definer, 0066). אותו מפתח, אותה גדר — "מי עומד על המשימה" היא שאלה אחת, בלי
-- קשר למאגר שהאדם בא ממנו. ‏`customer_board_fields` (‏`team`/`team_lead`, 0109)
-- ממשיך להכריע בממשק מה כל לקוח רואה; טלפון ות״ז נשארים מאחורי
-- `contractor_workers` (‏`cw_select`), שלא נפתחת כאן. ו-`contractor_worker_identities`
-- נותנת ללקוח שמחזיק את המפתח את השם של עובד קבלן שמשובץ למשימה **של הלקוח
-- שלו** — לא את סגל הקבלן כולו.
--
-- אין כאן שם של לקוח: כל לקוח שמחזיק את המפתח מקבל את אותה תשובה. בייצור
-- התפקיד `customer_manager` מחזיק אותו (וגם ברירת המחדל לסוג, 0066), וצופה,
-- עובד לקוח ומחסן לא. לקוח שלא צריך לראות שמות — `customer_board_fields`.
-- זה הופך במכוון את מה ש-0201 §3 השאיר ("מה שהלקוח לא ראה — לא רואה"), והחבילה
-- 56 עוברת לכלל החדש.
--
-- ‏`alter policy` ולא `drop`/`create` (כלי ה-MCP מחזיק כל `drop`).

-- ===== 1. tcw_select ======================================================

alter policy tcw_select on task_contractor_workers using (
  (select app.is_admin())
  or ((select app.user_kind()) = 'staff'
      and ((select app.has_permission('tasks','view'))
           or (select app.has_permission('contractors','view'))))
  or (select app.assignment_on_my_contractor(task_id))
  or ((select app.user_kind()) = 'customer_user'
      and (select app.has('board.view_staffing'))
      and (select app.assignment_on_my_customer(task_id))));

-- ===== 2. contractor_worker_identities ====================================
-- הגוף של 0201 כפי שהוא, ועוד זרוע אחת ללקוח. ה-view רץ כבעליו, ולכן ה-exists
-- קורא את השיבוצים ואת המשימות בלי RLS — הגדר כתובה בו במפורש.

create or replace view app.contractor_worker_identities as
  select cw.id, cw.contractor_id, cw.full_name
    from contractor_workers cw
   where current_user not in ('authenticated', 'anon')
      or (select app.is_admin())
      or (select app.user_kind()) = 'staff'
      or cw.contractor_id = (select app.contractor_id())
      or ((select app.user_kind()) = 'customer_user'
          and (select app.has('board.view_staffing'))
          and exists (select 1 from task_contractor_workers tcw
                        join tasks t on t.id = tcw.task_id
                       where tcw.contractor_worker_id = cw.id
                         and t.deleted_at is null
                         and t.customer_id = (select app.customer_id())));

grant select on app.contractor_worker_identities to authenticated;
