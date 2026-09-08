-- 0152: המערכת הישנה משאירה את המסמכים שלה מאחור
--
-- ההעברה מ-Firestore (פרויקט nihol-mishmarot) מביאה שלוש קולקציות אירועים
-- ‏— achaotMechir (ארקו), caesar (קיסר), eventsCdesign (שיא עיצובים) — ואת
-- המשימות שלהן. למסמך אירוע שם יש עד 95 שדות, ול-`events` יש 26 עמודות.
-- ההפרש אינו זבל: הוא שדות שהמערכת הזאת אינה יודעת לתאר *עדיין*.
--
-- ‏**למה טבלה ולא custom_fields.** מה שיש לו מקבילה בטופס נכנס ל-
-- ‏`events.custom_fields` דרך `form_fields`, ושם הוא נראה ונערך. השאר —
-- מזהי משתמשים ישנים, דגלים שאיש כבר לא זוכר, מערכי צוות, מפתחות שקיבלו
-- משמעות ואיבדו אותה — אינו אמור להופיע בטופס ואינו אמור להיעלם. שמירתו
-- ב-`custom_fields` הייתה מזהמת את המבנה שהטופס קורא; מחיקתו הייתה הופכת
-- כל שאלה עתידית ("מה היה סטטוס הליקוט של האירוע הזה?") לבלתי ניתנת
-- למענה, כי פרויקט Firebase ייסגר.
--
-- ‏**זו טבלת ארכיון, לא מקור אמת.** שום קוד מוצר אינו קורא ממנה: היא
-- קיימת כדי שמיפוי עתידי יוכל להיבנות מכאן במקום לחזור ל-Firebase, וכדי
-- שאפשר יהיה להוכיח מה בדיוק נטען. אין לה טריגרים, אין לה audit, ואין לה
-- מדיניות כתיבה — היא נכתבת פעם אחת בידי סקריפט ההעברה, שרץ כ-postgres.
--
-- ‏`doc_path` הוא הנתיב המלא ב-Firestore והוא המפתח: ממנו נגזר גם ה-UUID
-- ‏(uuid_generate_v5 על מרחב שמות קבוע) שקיבלו האירוע והמשימה, ולכן הייבוא
-- אידמפוטנטי — הרצה שנייה פוגעת באותן שורות בדיוק.

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

-- קריאה למנהל בלבד: המסמכים מחזיקים טלפונים של אנשי קשר ומחירים, ואין
-- סיבה שעובד או לקוח יראו אותם. אין policy ל-insert/update/delete בכוונה.
create policy legacy_firestore_docs_select on legacy_firestore_docs
  for select to authenticated using ((select app.is_admin()));

grant select on legacy_firestore_docs to authenticated;
