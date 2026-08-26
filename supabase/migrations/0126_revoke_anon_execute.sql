-- 0126: מסירים execute מ-anon על שני ה-RPCs החדשים
--
-- ‏0120/0124 עשו `revoke all ... from public`, אבל ב-Supabase לפונקציה חדשה
-- ב-`public` יש הרשאת ברירת-מחדל ישירה ל-`anon` (ALTER DEFAULT PRIVILEGES),
-- ש-`revoke from public` אינו נוגע בה — בדיוק הסיבה ש-RPCs אחרים בריפו כותבים
-- `revoke execute ... from anon, public`. הפונקציות ממילא בטוחות (הן דוחות
-- קורא בלי JWT/הרשאה), אבל השורה הזו מיישרת אותן עם הכלל ומכבה את ה-linter.

revoke execute on function public.set_task_performed_by(uuid, text) from anon;
revoke execute on function public.hard_delete(text, uuid) from anon;
