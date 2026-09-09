-- 0161: מסירים execute מ-anon על ה-RPC של 0160
--
-- אותו דבר בדיוק ש-0126 תיקן ל-`hard_delete`, ומאותה סיבה: ‏0160 כתבה
-- `revoke all ... from public`, אבל ב-Supabase לפונקציה חדשה ב-`public` יש
-- הרשאת ברירת-מחדל **ישירה** ל-`anon` (‏ALTER DEFAULT PRIVILEGES), ו-
-- `revoke from public` אינו נוגע בה. ה-linter של Supabase סימן את זה מיד
-- אחרי הפריסה, וזו הסיבה שהוא קיים.
--
-- הפונקציה עצמה בטוחה — היא פותחת ב-`app.is_admin()` ודוחה כל קורא אחר,
-- ולקורא בלי JWT הוא מחזיר false — אבל שורת ההרשאות אינה המקום להסתמך על
-- כך שהגוף יסרב. זה גם הכלל שכל שאר ה-RPCs בריפו כתובים לפיו.

revoke execute on function public.user_delete_impact(uuid) from anon;
