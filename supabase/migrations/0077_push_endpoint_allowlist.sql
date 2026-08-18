-- 0077: ה-endpoint של מנוי דחיפה הוא כתובת שהשרת פונה אליה, ולכן הוא לא
--       יכול להיות כל כתובת.
--
-- ‏push_subscriptions.endpoint נכתב ישירות מהדפדפן דרך PostgREST — `ps_own`
-- (0046) היא `for all` על השורות של המשתמש עצמו — ונשמר כ-`text` בלי שום
-- אילוץ על הסכימה או על המארח. ‏notify-dispatch, שרץ ב-service role, שולף
-- את השורה ומבצע בקשת HTTP יוצאת אל הערך שנשמר שם. כלומר: כל משתמש מחובר
-- יכול להכתיב לשרת לאן לפנות.
--
-- וזו אינה פנייה עיוורת. גוף ה-catch בפונקציה מסתעף לפי הסטטוס שחזר — 404
-- ו-410 מוחקים את השורה, 400 ו-413 כותבים את הסטטוס ל-last_error, וכל השאר
-- נכנס לניסיון חוזר — והשורה הזו קריאה לבעליה. זהו אורקל בן שלושה מצבים על
-- מארחים ופורטים פנימיים, מתוך רשת היציאה של הפרויקט.
--
-- ההגנה הנכונה היא במסד ולא בפונקציה: הפונקציה החיה אינה מסונכרנת עם הקובץ
-- שב-repo (ראו את ההערה בראש notify-dispatch/index.ts), ואילוץ כאן חל על
-- שתי הגרסאות ועל כל מי שיכתוב לטבלה בעתיד.
--
-- הרשימה היא של שירותי הדחיפה שדפדפנים מנפיקים מהם בפועל. שירות חדש שיתווסף
-- ייכשל בהכנסה — בקול, עם שגיאה — ולא יידחף בשקט; הוספתו היא שורה אחת כאן.
-- זו ההחלטה הנכונה בין השתיים: רשימת היתר שמפספסת מארח מייצרת תקלה שמתגלה,
-- ורשימת חסימה שמפספסת מארח מייצרת חור שלא מתגלה.

-- שורה שאינה עומדת באילוץ אינה יכולה להיות מנוי לגיטימי: אף דפדפן לא הנפיק
-- אותה. מחיקה לפני ההוספה כדי שהאילוץ ייכנס מאומת ולא NOT VALID — אחרת
-- בדיוק השורות שבגללן הוא נכתב היו נשארות פטורות ממנו. המחיר אפסי:
-- `usePushSync` מיישר את מנוי הדפדפן מול המסד בכל עליית אפליקציה, ולכן מנוי
-- אמיתי שנמחק כאן בטעות נרשם מחדש לבד.
delete from push_subscriptions
 where endpoint !~ '^https://(fcm\.googleapis\.com|android\.googleapis\.com|updates\.push\.services\.mozilla\.com|[a-z0-9-]+\.notify\.windows\.com|web\.push\.apple\.com)/';

alter table push_subscriptions
  add constraint push_subscriptions_endpoint_host
  check (endpoint ~ '^https://(fcm\.googleapis\.com|android\.googleapis\.com|updates\.push\.services\.mozilla\.com|[a-z0-9-]+\.notify\.windows\.com|web\.push\.apple\.com)/');

comment on constraint push_subscriptions_endpoint_host on push_subscriptions is
  'ה-endpoint נכתב מהדפדפן ונקרא בידי notify-dispatch ב-service role. בלי האילוץ הזה הוא SSRF.';
