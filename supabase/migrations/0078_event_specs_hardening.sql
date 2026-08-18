-- 0078: שתי הידוקים על 0077 שה-linter של Supabase תפס
--
-- שניהם התגלו בהרצת `get_advisors` מיד אחרי שהמיגרציה נחתה על הפרויקט האמיתי,
-- ואף אחד מהם אינו נראה באשכול הבדיקות המקומי — שם אין ברירות המחדל של
-- Supabase על תפקידי anon/authenticated, ואין linter.

-- ===== 1. PUBLIC עדיין יכול היה לקרוא ל-remove_event_spec =================
--
-- 0077 כתבה `revoke execute ... from anon`, וזו הייתה פקודה ריקה: ל-anon לא
-- הייתה הענקה ישירה מלכתחילה. ההרשאה מגיעה מ-PUBLIC, שמקבל EXECUTE על כל
-- פונקציה כברירת מחדל של פוסטגרס, ו-anon יורש ממנו. ה-ACL הראה את זה במפורש:
-- `{=X/postgres, ...}` — הרשומה עם הנמען הריק היא PUBLIC.
--
-- זו אותה מלכודת בדיוק ש-0048 קמה בשבילה, ולכן כל הרפו כותב
-- `from anon, public`. 0077 היא היחידה שסטתה מזה.
--
-- לא הייתה כאן חשיפה ממשית: הפונקציה פותחת ב-app.require('events.specs_manage'),
-- ומשתמש אנונימי אינו מחזיק פרופיל ולכן נדחה ב-42501. אבל "נכשל אחרי שנכנס"
-- אינו תחליף ל"לא נכנס", ושטח התקיפה של פונקציית security definer אינו מקום
-- להסתמך בו על שכבה שנייה.

revoke execute on function public.remove_event_spec(uuid, boolean) from anon, public;

-- ===== 2. search_path על app.event_spec_text ==============================
-- כל שאר הפונקציות של 0077 מקבעות אותו; זו נשמטה. היא אמנם קוראת רק ל-
-- concat_ws ו-nullif, אך פונקציה שנקראת מתוך טריגר של security definer אינה
-- המקום להשאיר בו search_path פתוח לשינוי מצד הקורא.

create or replace function app.event_spec_text(
  p_version int, p_source text, p_file_name text, p_url text, p_title text)
returns text language sql immutable set search_path = public as $$
  select concat_ws(' · ',
    'גרסה ' || p_version,
    nullif(btrim(coalesce(p_title, '')), ''),
    case when p_source = 'file' then p_file_name else p_url end)
$$;
