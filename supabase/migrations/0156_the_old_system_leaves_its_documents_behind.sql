-- 0156: מה שהמערכת הישנה השאירה אחריה
--
-- **הקובץ הזה נכתב בדיעבד.** המיגרציה הוחלה ישירות על הפרודקשן ב-08/09/2026
-- (‏`20260908111454`), בלי לעבור בריפו, והיא נשלפה משם כלשונה כדי שסביבה
-- שנבנית מהקבצים — בדיקות, סביבת פיתוח, שחזור — תכיל אותה גם היא. עד כאן
-- הטבלה הייתה קיימת בפרודקשן ולא בשום מקום אחר, וזה בדיוק הפער ששחזור היה
-- מגלה ביום הגרוע.
--
-- **המספר אינו סדר ההחלה.** בפרודקשן היא רצה *לפני* 0152–0155; כאן היא
-- מקבלת את המספר הפנוי הבא, כי אלה כבר הוחלו שם בשמותיהן ואין לשנותם
-- למפרע. הסדר אינו משנה: הטבלה עומדת בפני עצמה ואינה נוגעת בדבר משלהן —
-- שתי ההצבעות היחידות שלה הן ל-`events` ול-`tasks`, שקיימות מ-0003.
--
-- מה שהיא עושה: מחזיקה את המסמכים כפי שהיו ב-Firestore לפני ההעברה, אחרי
-- פירוק מבנה ה-Values שלו ל-JSON רגיל ובלי להשמיט שדה. `doc_path` הוא
-- המפתח — הנתיב המלא, שממנו נגזרו גם מזהי האירוע והמשימה — ולכן ייבוא חוזר
-- של אותו מסמך אינו מכפיל שורה. `on delete set null` על שתי ההצבעות:
-- מחיקת אירוע במערכת החדשה אינה סיבה למחוק את מה שהיה עליו בישנה.
--
-- הקריאה היא של מנהל מערכת בלבד — זה ארכיון, לא מסך — ולכן פוליסה אחת
-- ל-select ואין כתיבה כלל: מה שנכנס לכאן נכנס בייבוא, מחוץ ל-API.

create table legacy_firestore_docs (
  doc_path    text primary key,
  collection  text not null,
  doc_id      text not null,
  event_id    uuid references events(id) on delete set null,
  task_id     uuid references tasks(id)  on delete set null,
  data        jsonb not null,
  imported_at timestamptz not null default now()
);

comment on table legacy_firestore_docs is
  'ארכיון המסמכים כפי שהיו ב-Firestore לפני ההעברה. קריאה בלבד, למנהלים.';
comment on column legacy_firestore_docs.doc_path is
  'הנתיב המלא ב-Firestore. ממנו נגזרים ה-UUID של האירוע והמשימה, ולכן הוא גם מפתח הייבוא.';
comment on column legacy_firestore_docs.data is
  'המסמך אחרי פירוק מבנה ה-Values של Firestore ל-JSON רגיל. שום שדה לא הושמט.';

create index legacy_firestore_docs_event on legacy_firestore_docs (event_id) where event_id is not null;
create index legacy_firestore_docs_task  on legacy_firestore_docs (task_id)  where task_id  is not null;
create index legacy_firestore_docs_coll  on legacy_firestore_docs (collection);

alter table legacy_firestore_docs enable row level security;

create policy legacy_firestore_docs_select on legacy_firestore_docs
  for select to authenticated using ((select app.is_admin()));

grant select on legacy_firestore_docs to authenticated;
