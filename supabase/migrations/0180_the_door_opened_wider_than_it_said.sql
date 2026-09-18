-- 0180: הדלת שנפתחה לעובד הקבלן נפתחה רחבה ממה שנכתב עליה
--
-- ‏0148 §2 פתחה לעובד הקבלן את **דף האירוע**, וכתבה מפורשות מה היא אינה
-- פותחת: *"‏`events.list` נשאר סגור — רשימת כל האירועים אינה שלו. מה שנפתח
-- הוא הדף של אירוע שממילא מותר לו לקרוא."* המשפט הזה לא התקיים.
--
-- **הסיבה היא ההיסק, ולא ההענקה.** ‏0082 רשמה את `events.list` עם
-- `implied_by = 'events.view'` בכוונה — *"כל מי שמחזיק אותו היום ממשיך
-- לראות את הרשימה בלי שורת הענקה; מה שהוא מוסיף הוא היכולת לכבות אותה
-- בנפרד"* — ולכן הענקת `events.view` לבדה מדליקה גם את הרשימה. ‏0082 עצמה
-- ידעה זאת וכתבה שורת דחייה מפורשת לשלושת תפקידי השטח של הצוות; ‏0148
-- הסתמכה על "לא הענקנו", וזה לא מספיק.
--
-- **ולא רק הרשימה.** אותו היסק פתח לו גם את יומן הפעילות, את הייצוא ואת
-- אנשי הקשר של הלקוח — ו-0103 §2 כבר הכריעה במפורש שאיש הקשר של הלקוח אינו
-- שלו. ‏0079 §2א אמרה את המשפט הזה במילותיו, לעובד הצוות: *"לראות את האירוע
-- אינו לראות את המסמך שהלקוח שלח ואת מי שינה בו מה"*.
--
-- **והתיקון הוא השוואה, לא צמצום.** עובד הקבלן ועובד הצוות הם אותו אדם
-- בשטח, ולכן מודול האירועים שלהם צריך להיראות אותו דבר. ארבעת המפתחות
-- שתפקיד "עובד" מחזיק היום הם בדיוק אלה שנשארים גם כאן:
--
--   * `events.view` — הדלת שבגללה 0148 נכתבה;
--   * `events.activity_log` ו-`events.activity_note` — ‏0129 §4 פתחה אותם
--     לשטח כולו במפורש ("כל העובדים, כולל ראש צוות וכולל קבלנים ועובדי
--     קבלנים, יראו בתיעוד של האירוע רק הערות בלבד"), וכאן הם נכתבים כשורת
--     תפקיד ולא רק כברירת מחדל של הקהל — כדי שהדחייה הגורפת לא תבלע אותם;
--   * `events.specs_view` — אין לו `implied_by` והוא `default_allowed`,
--     ו-0102 השאירה אותו פתוח לשטח בכוונה: מי שנוסע לאירוע צריך את המפרט.
--     לכן אין עליו שורה כאן, בדיוק כפי שאין עליו שורה אצל "עובד".
--
-- ו-`events.activity_system_view` נשאר סגור: 0129 §1 דחתה אותו לקהל הקבלן
-- כולו, וזו ההבחנה שהיא נועדה לשמור — הערות כן, היסטוריית שדות לא.
--
-- ‏(`customer_worker` של 0178 נולד סגור: הוא נכתב עם `p_close_modules` על כל
--  המודולים הפעילים, ולכן `events.list` נושא אצלו שורת דחייה מהיום הראשון.
--  זו הסיבה שהתבנית ההיא עדיפה על "לא הענקנו".)

-- שורות דחייה מפורשות ולא היעדר הענקה, כדי שמפתח שייגזר מ-`events.view`
-- מחר לא ייפתח לו מעצמו.
insert into role_permissions (role_id, permission_key, allowed)
select r.id, pr.key, false
from permission_roles r
cross join permission_registry pr
where r.key = 'contractor_worker'
  and pr.module = 'events' and pr.is_active
  and pr.key not in ('events.view', 'events.activity_log',
                     'events.activity_note', 'events.specs_view')
on conflict (role_id, permission_key) do update set allowed = false;

insert into role_permissions (role_id, permission_key, allowed)
select r.id, k, true
from permission_roles r,
     unnest(array['events.view', 'events.activity_log', 'events.activity_note']) k
where r.key = 'contractor_worker'
on conflict (role_id, permission_key) do update set allowed = true;
