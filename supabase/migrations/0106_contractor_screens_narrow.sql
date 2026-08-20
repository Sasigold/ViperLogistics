-- 0106: מה שאין לקבלן על המסך
--
-- שלוש הצרות, כולן על אותו קהל ואף אחת מהן אינה עניין של אבטחת שורות — הן
-- הכרעות על מי מחזיק את הכלי:
--
--   1. **הגדרות שכר ושעון של הסגל אינן של הקבלן.** ‏0103 פתח לו אותן עם
--      `portal.worker_settings`; ההכרעה מתהפכת כאן. מה שנשאר לו במסך "העובדים
--      שלי" הוא לראות את הרשימה ולהוסיף עובד — ותו לא.
--   2. **בורר התצוגה והסינון בלו״ז אינם שלו.** ‏`board.columns` ו-`board.filter`
--      הם כלי התכנון שמעל הלוח (0079), והם נגזרים מ-`board.view` — כלומר
--      נדלקים בהיסק לכל מי שפותח את הלוח. שלושת תפקידי השטח כבר סגורים להם
--      מאז 0079; שני תפקידי הקבלן מצטרפים אליהם.
--
-- המפתח `portal.worker_settings` נשאר במרשם, וכך גם ה-RPC והזרוע בפוליסה:
-- שניהם נשענים עליו, ומי שאינו מחזיק אותו נדחה בשניהם. כלומר ההכרעה הפוכה
-- אבל הדלת נשארת — אפשר להעניק אותו במסך ההרשאות לקבלן מסוים בלי מיגרציה.

-- ===== 1. הגדרות העובדים חוזרות למשרד ====================================
insert into role_permissions (role_id, permission_key, allowed)
select r.id, 'portal.worker_settings', false
from permission_roles r where r.key in ('contractor_manager', 'staff_contractor')
on conflict (role_id, permission_key) do update set allowed = false;

-- וגם ברירת המחדל של הקהל אומרת לא, כדי שחשבון קבלן בלי תפקיד לא ייפול
-- לשום ירושה עתידית. `default_allowed` של המפתח הוא false ממילא (0103), וזו
-- השכבה שמעליו.
insert into kind_permission_defaults (user_kind, permission_key, allowed) values
  ('contractor_user', 'portal.worker_settings', false)
on conflict (user_kind, permission_key) do update set allowed = excluded.allowed;

-- ===== 2. כלי התכנון שמעל הלו״ז =========================================
-- ‏`board.view` נשאר: הקבלן רואה את הלוח. מה שיורד הוא בורר התצוגה והשדות
-- (`board.columns`) ושורת הסינון והחיפוש (`board.filter`) — בדיוק כפי ש-0079
-- סגר אותם לעובד השטח. בלי `board.columns` הלוח נעול על תצוגה אחת, ו-
-- `localStorage` אינו נקרא ואינו נכתב במצב הזה (ראו 0079).
insert into role_permissions (role_id, permission_key, allowed)
select r.id, k, false
from permission_roles r, unnest(array['board.columns', 'board.filter']) k
where r.key in ('contractor_manager', 'contractor_worker')
on conflict (role_id, permission_key) do update set allowed = false;
