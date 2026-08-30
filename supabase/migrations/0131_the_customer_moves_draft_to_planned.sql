-- 0131: הלקוח מזיז משימה מטיוטה למתוכנן, ובחזרה
--
-- הדיווח: **"לקוח יוכל לשנות סטטוס מטיוטה למתוכנן והפוך."** טיוטה ומתוכנן הם
-- סטטוסי **משימה** (0063) ולא של אירוע — לאירוע יש טרם-אושר/סופי/מתקיים/בוטל
-- (0036) — וזה בדיוק התכנון הפנימי של הלקוח, כפי שכבר נכתב בהערה של 0115.
--
-- שער הפרסום (`app.enforce_task_publish`, 0066/0117) חוסם רק כניסה ויציאה
-- מ"משובץ", ולכן `טיוטה ⇄ מתוכנן` פתוח בו ממילא. מה שחסם היה שכבת התפקיד:
-- `customer_manager` נסגר גורפית על מודול `tasks` דרך `close_modules` (0011),
-- ולכן `tasks.change_status` נשא עליו שורת דחייה מפורשת.
--
-- **שתי שורות ולא קריאה מחדש ל-`set_role_permissions`.** הפונקציה הזו מוחקת
-- את כל שורות התפקיד לפני שהיא כותבת, ומאז 0011 נוספו ל-`customer_manager`
-- מפתחות בשלוש מיגרציות שונות (0066, 0074). כתיבה ממוקדת אינה יכולה לאבד
-- אותם.
--
-- **`tasks.publish` אינו נפתח**, ולכן "משובץ" נשאר סגור ללקוח לשני הכיוונים —
-- וזה גם מה שהמסך מציג ממילא: `statusOptions` משמיטה את "משובץ" ממי שאינו
-- רשאי לפרסם.
--
-- **ושדה הלוח נשאר של המשרד.** ‏`app.enforce_customer_board_edit` (0109)
-- ידחה את הכתיבה עד שהמשרד יסמן ללקוח את שדה "סטטוס" כ"ניתן לעריכה" בכרטיס
-- הלקוח. זו אינה עקיפה של הדיווח אלא הכלל של 0109: הלוח הוא של המשרד, והוא
-- מחליט מה כל לקוח עורך. מה שנפתח כאן הוא המפתח; הברז נשאר אצל מי שהחזיק בו.

-- ‏`app.has` מתעלם מ-applies_to, וזה רק כדי שהמפתח יופיע במטריצה כשמגדירים
-- תפקיד לקוח — בדיוק כמו 0066 §2, שהשמיטה אותו.
update permission_registry
   set applies_to = array['staff', 'customer_user']::user_kind[]
 where key = 'board.inline_edit';

insert into role_permissions (role_id, permission_key, allowed)
select r.id, k, true
from permission_roles r, unnest(array['tasks.change_status', 'board.inline_edit']) k
where r.key = 'customer_manager'
on conflict (role_id, permission_key) do update set allowed = true;
