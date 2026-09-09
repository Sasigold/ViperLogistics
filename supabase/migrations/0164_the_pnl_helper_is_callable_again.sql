-- 0164: ‏"רווחיות לפי משימה" חזרה לנפול על הרשאת הרצה — והפעם עם שומר
--
-- הדף מציג שוב "שגיאה בטעינת הדוח — אין לך הרשאה לבצע את הפעולה הזו". זו
-- אותה תקלה בדיוק שתוארה ב-0087, ואותה הודעה: המיפוי הגנרי של 42501
-- ב-`errors.ts`, כלומר Postgres סירב ולא `raise` מתוך ה-RPC (שהיה מגיע
-- בעברית שלו, "אין הרשאה לדוחות") ולא הדחייה הרכה `{rows: null, denied}`,
-- שאינה שגיאה בכלל.
--
-- ‏`public.task_pnl` הוא security **invoker** במכוון (0070 §4) — ספירת
-- ה-`truncated` שבתוכו חייבת לראות בדיוק את מה שהקורא רואה — ולכן
-- ‏`app.task_pnl_rows` נקראת בהרשאות הקורא. ‏0070:354 שללה אותה מ-
-- ‏`authenticated`, ‏0087 החזירה. במסד החי ה-ACL של הפונקציה חזר להיות
-- ‏`{postgres=X/postgres}` בלבד — כלומר ה-revoke של 0070 §3 הורץ שוב אחרי
-- ‏0087, כנראה בהרצה חוזרת של הקובץ — וההענקה נמחקה איתו.
--
-- ‏`grant` הוא אידמפוטנטי, ולכן השורה הזו בטוחה גם במסד שההענקה כבר קיימת בו.
-- ‏`anon` נשאר בחוץ, כפי שהיה.

grant execute on function app.task_pnl_rows(date, date, uuid, uuid, int) to authenticated;

-- ===========================================================================
-- השומר: מה ש-0087 השאיר כהערה הופך לבדיקה שרצה
--
-- ‏0087 תיעדה את השאילתה שמצאה את המקרה — אבל הערה אינה מונעת חזרה. כאן היא
-- הופכת לחלק מהמיגרציה: כל הרצה של חבילת המיגרציות (‏`npm run test:db`,
-- ובעקבותיה ה-CI) נופלת אם פונקציית `public` שהיא invoker קוראת לעוזר
-- ב-`app` ש-`authenticated` אינו רשאי להריץ. באג כזה אינו ניתן לגילוי
-- בבדיקה שרצה כ-superuser, כי superuser עוקף GRANTs — ולכן הוא חייב להיבדק
-- בשאלה על ה-ACL ולא בקריאה לפונקציה.
--
-- החשיפה שההענקה פותחת היא אפס-חדש: סכימת `app` אינה חשופה ב-PostgREST (רק
-- `public`), ולכן `app.task_pnl_rows` אינה נתיב REST בפני עצמה; הדלת היחידה
-- אליה היא `public.task_pnl`, ששלושת השערים שלו — `reports.view`, צרור
-- הרווח והיקף הנתונים — נבדקים לפני שהוא נקרא.
-- ===========================================================================

do $$
declare
  v_bad text;
begin
  select string_agg(format('public.%s → app.%s', pub.proname, h.proname), ', ')
    into v_bad
    from (select p.oid, p.proname, p.prosrc
            from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and not p.prosecdef
             and has_function_privilege('authenticated', p.oid, 'EXECUTE')) pub
    join (select p.oid, p.proname
            from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'app'
             and not has_function_privilege('authenticated', p.oid, 'EXECUTE')) h
      on pub.prosrc ~* ('app\.' || h.proname || '\s*\(');

  if v_bad is not null then
    raise exception
      'פונקציית public שהיא invoker קוראת לעוזר ב-app שאין ל-authenticated הרשאה להריץ: %',
      v_bad;
  end if;
end $$;
