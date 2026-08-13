-- 0065: תקרת אורך המשמרת בדיווח ידני עולה מ-16 ל-24 שעות
--
-- 0024 קבעה 16 כתקרה לדיווח עצמי, ומשמרת ארוכה יותר נדחתה ב־
-- "משמרת מדווחת אינה יכולה לעלות על 16 שעות". בפועל יש משמרות כאלה — הקמה
-- שנמשכת לתוך הלילה ופירוק שמתחיל בבוקר שאחריו — והעובד נשאר בלי דרך לדווח
-- עליהן בכלל.
--
-- התקרה נשארת תקרה ולא נמחקת: היא מה שמפריד בין "משמרת ארוכה" לבין שעה
-- שהוקלדה עם ספרה מיותרת, והשגיאה הזו נכנסת אחר כך לשכר. 24 שעות הוא
-- הגבול הטבעי — מעבר לו הדיווח אינו מתאר יום עבודה אלא טעות הקלדה.
--
-- הערך יושב ב-app_settings ולא בקוד, ולכן מנהל יכול להזיז אותו שוב ממסך
-- הנוכחות בלי מיגרציה. `jsonb_set` עם create_if_missing כדי שגם התקנה שבה
-- הבלוק self_entry לא נזרע (0024 מתנה על `not (value ? 'self_entry')`)
-- תקבל ערך תקין ולא null.

update app_settings
   set value = jsonb_set(
         case when value ? 'self_entry' then value
              else value || jsonb_build_object('self_entry', jsonb_build_object(
                     'enabled', true, 'max_backdate_days', 14)) end,
         '{self_entry,max_hours}', '24'::jsonb, true),
       updated_at = now()
 where key = 'attendance.clock';
