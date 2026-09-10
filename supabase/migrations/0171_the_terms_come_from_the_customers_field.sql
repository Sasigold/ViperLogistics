-- ‏0171: תנאי התשלום חוזרים להיות שדה של הלקוח
--
-- ‏0170 הוסיפה `events.payment_terms` כשדה מערכת, ובכך המציאה מחדש מנגנון
-- שכבר היה קיים: **שדות מותאמים פר-לקוח** (0053). לקיסר יש כבר שדה בשם
-- "תנאי תשלום" מסוג `select`, עם הערכים שהיא באמת עובדת מולם — "תאריך
-- הארוע", "שוטף + 30", "שוטף + 60", "שוטף + 90" — ומאות אירועים שלה
-- ממלאים אותו. גם לארקו יש שדה באותה תווית.
--
-- שדה המערכת שנוסף היה, לעומת זאת, **גרוע פעמיים**: הוא הופיע בטופס של כל
-- לקוח במערכת (‏0170 זרעה אותו `visible` לכולם), ולא נעשה בו שימוש אף
-- פעם — אפס אירועים נשאו בו ערך. ולכן הוא יורד כאן לגמרי, והמסמך קורא
-- מהשדה של הלקוח.
--
-- **מה שנשאר:** `event_quotes.payment_terms` אינו נוגע. הוא הצילום של מה
-- שהודפס על מסמך שכבר יצא, ואינו מצביע לשום מקום.
--
-- **צד הלקוח מוצא את השדה לפי התווית ולא לפי המפתח.** ‏`field_key` נוצר
-- בשרת כ-`custom_<uuid>` ולכן שונה אצל כל לקוח; התווית היא מה שהמנהל
-- הקליד, ויש עליה אינדקס ייחודי פר-לקוח (‏0053:41). ראו
-- `findPaymentTermsField` ב-`src/features/events/quote.ts`.

-- ===== 1. שלוש הפונקציות חוזרות למצבן שלפני 0170 ==========================
-- אותה טכניקה שבה 0170 הוחלה על הייצור, בכיוון ההפוך: הגוף החי נקרא
-- ב-`pg_get_functiondef`, השורה שנוספה מוסרת ממנו, והוא מורץ בחזרה. עוגן
-- שאינו נמצא **פעם אחת בדיוק** מפיל את המיגרציה — ולכן אין מצב שבו התוצאה
-- שונה ממה שהתכוונו לו בלי שנדע. הכתבה מחדש של 230 שורות הייתה מסוכנת
-- יותר, ולא פחות.
--
-- הן חוזרות **לפני** הפלת העמודה, כדי שלא יישאר אפילו רגע שבו פונקציה חיה
-- מפנה לעמודה שאינה קיימת.

do $mig$
declare
  v_src  text;
  v_from text;
begin
  -- ‏1א. היומן
  v_src := pg_get_functiondef('app.log_event_activity()'::regprocedure);

  v_from := $a$,'payment_terms'],$a$;
  if (length(v_src) - length(replace(v_src, v_from, ''))) / length(v_from) <> 1 then
    raise exception 'app.log_event_activity: עוגן רשימת העמודות לא נמצא פעם אחת';
  end if;
  v_src := replace(v_src, v_from, $a$],$a$);

  v_from := $a$,'תנאי תשלום']) as t(col, label)$a$;
  if (length(v_src) - length(replace(v_src, v_from, ''))) / length(v_from) <> 1 then
    raise exception 'app.log_event_activity: עוגן רשימת התוויות לא נמצא פעם אחת';
  end if;
  execute replace(v_src, v_from, $a$]) as t(col, label)$a$);

  -- ‏1ב. create_event
  v_src := pg_get_functiondef('public.create_event(jsonb)'::regprocedure);

  v_from := 'notes, payment_terms, status_id,';
  if (length(v_src) - length(replace(v_src, v_from, ''))) / length(v_from) <> 1 then
    raise exception 'create_event: עוגן רשימת העמודות לא נמצא פעם אחת';
  end if;
  v_src := replace(v_src, v_from, 'notes, status_id,');

  v_from := $a$    nullif(payload ->> 'payment_terms',''),
$a$;
  if (length(v_src) - length(replace(v_src, v_from, ''))) / length(v_from) <> 1 then
    raise exception 'create_event: עוגן שורת הערך לא נמצא פעם אחת';
  end if;
  execute replace(v_src, v_from, '');

  -- ‏1ג. update_event
  v_src := pg_get_functiondef('public.update_event(uuid, jsonb)'::regprocedure);

  v_from := $a$    payment_terms   = case when payload ? 'payment_terms' then nullif(payload ->> 'payment_terms','') else payment_terms end,
$a$;
  if (length(v_src) - length(replace(v_src, v_from, ''))) / length(v_from) <> 1 then
    raise exception 'update_event: עוגן שורת ה-set לא נמצא פעם אחת';
  end if;
  execute replace(v_src, v_from, '');
end $mig$;

-- ===== 2. השדה יורד מהקטלוג ומהמרשם ======================================
-- לפי הסדר: שורות התצורה שמצביעות עליו, אחר כך שורת הקטלוג עצמה (יש עליה
-- שני מפתחות זרים), ואז המרשם. ‏`field_permissions` אינה נושאת מפתח זר
-- ל-`field_registry`, ולכן שורות שנכתבו עליו ידנית מנוקות במפורש.

delete from customer_form_fields where field_key = 'payment_terms';
delete from user_form_fields     where field_key = 'payment_terms';
delete from form_fields          where field_key = 'payment_terms';
delete from field_permissions    where entity = 'event' and field_key = 'payment_terms';
delete from field_registry       where entity = 'event' and field_key = 'payment_terms';

-- ===== 3. והעמודה עצמה ===================================================
-- ‏`events_secure` נבנה מרשימת העמודות (0012), ו-`create or replace view`
-- אינו יכול להוריד עמודה מתצוגה קיימת — ולכן היא נמחקת ונבנית מחדש. אין
-- לה תלויות אחרות: אף תצוגה ואף פוליסה אינן קוראות ממנה.
--
-- ‏0170 הוסיפה את העמודה אתמול, ואף אירוע לא נשא בה ערך. אין מה לגבות.

drop view if exists events_secure;
alter table events drop column payment_terms;
select app.rebuild_secure_view('events');
