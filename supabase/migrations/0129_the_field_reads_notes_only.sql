-- 0129: בתיעוד האירוע — השטח והקבלנים רואים הערות, ורק אותן
--
-- ‏0122 שאלה "מי רשאי לקרוא מלל חופשי", וענתה: המשרד והלקוח. הדיווח מהשטח
-- הופך את השאלה: **"כל העובדים, כולל ראש צוות וכולל קבלנים ועובדי קבלנים,
-- יראו בתיעוד של האירוע רק הערות בלבד."**
--
-- זו אינה הרחבה של 0122 אלא היפוך שלה, ולכן גם השער מתהפך. ההערה היא מה
-- שנכתב *אל* מי שנוסע לאירוע — "הלקוח ביקש להתחיל שעה מאוחר יותר", "הכניסה
-- מאחור" — ולכן היא בדיוק מה שהשטח צריך. רשומות המערכת, לעומת זאת, הן
-- ההיסטוריה התפעולית של האירוע: מי שינה איזה שדה וממה למה. זה דיון של המשרד
-- מול הלקוח, והוא שדורש מעכשיו מפתח.
--
-- **מפתח חדש `events.activity_system_view`,** נגזר מ-`events.edit` כדי שהמשרד
-- ומנהל הלקוח לא יאבדו דבר, ומוענק במפורש לכל תפקיד משרדי שאינו תפקיד שטח —
-- כי "צופה" מחזיק יומן בלי `events.edit`, ואסור שהיפוך הכלל יגזול ממנו את
-- ההיסטוריה. ‏`events.activity_note_view` (0122) חדל לשמש כשער ויורד מהמרשם
-- הפעיל; השורות שנכתבו עליו נשארות, ואינן נקראות עוד.
--
-- **וגם כותבים.** ‏`events.activity_note` נפתח לשלושת תפקידי השטח. עד היום
-- ראש צוות יכול היה לכתוב רק דרך `app.is_event_team_lead` ובמשימה שפורסמה,
-- ועובד ונהג לא יכלו כלל — ומדיניות ה-INSERT (0082) אינה משתנה, רק מי מחזיק
-- את המפתח.

-- ===== 1. המפתח החדש ======================================================
select app.register_permission('events.activity_system_view', 'events',
  'צפייה ברשומות המערכת ביומן',
  'ההיסטוריה האוטומטית של האירוע — שינויי שדות, מפרט, חתימה ותוספות. בלעדיו נראות הערות בלבד',
  'access', false, false,
  array['staff', 'customer_user']::user_kind[], 'events.edit', 186);

-- ההכרעה נכתבת בשתי שכבות, בדיוק כמו שעשתה 0103 §2 עם איש הקשר של הלקוח:
-- **היתר לקהל, ודחייה מפורשת לתפקידי השטח.** מי שמחזיק יומן ואינו איש שטח —
-- המשרד על כל תפקידיו, כולל "צופה" שאין לו `events.edit`, ומשתמש לקוח על
-- שני תפקידיו — ממשיך לראות הכול; וקהל הקבלן נדחה כקהל. שכבת התפקיד מדברת
-- לפני שכבת הקהל (`app.has`), ולכן שלוש שורות הדחייה למטה גוברות.
insert into kind_permission_defaults (user_kind, permission_key, allowed) values
  ('staff',          'events.activity_system_view', true),
  ('customer_user',  'events.activity_system_view', true),
  ('contractor_user','events.activity_system_view', false)
on conflict (user_kind, permission_key) do update set allowed = excluded.allowed;

insert into role_permissions (role_id, permission_key, allowed)
select r.id, 'events.activity_system_view', false
from permission_roles r
where r.key in ('worker', 'driver', 'team_lead')
on conflict (role_id, permission_key) do update set allowed = false;

-- וההיתר נכתב גם כשורת תפקיד לכל תפקיד משרדי, ולא רק כברירת מחדל של הקהל.
-- שכבת התפקידים היא `bool_or`, ולכן בלי השורה הזו אדם שנושא גם תפקיד משרדי
-- וגם תפקיד שטח היה נשפט לפי הדחייה לבדה — בדיוק מחלקת הבאגים ש-0104 תיארה,
-- ואותה מסקנה: הכובע המנהל גובר.
insert into role_permissions (role_id, permission_key, allowed)
select r.id, 'events.activity_system_view', true
from permission_roles r
where r.user_kind = 'staff' and r.key not in ('worker', 'driver', 'team_lead')
on conflict (role_id, permission_key) do update set allowed = true;

-- ===== 2. הפוליסה: 'note' פתוח, כל השאר דורש מפתח =========================
drop policy event_activity_select on event_activity;
create policy event_activity_select on event_activity for select to authenticated using (
  (select app.is_admin())
  or (((select app.has('events.activity_log'))
       or (select app.is_event_team_lead(event_activity.event_id)))
      and exists (select 1 from events e where e.id = event_activity.event_id)
      and (kind = 'note' or (select app.has('events.activity_system_view')))));

-- ===== 3. השער הישן יורד ==================================================
-- הוא אינו נמחק: השורות שנכתבו עליו במסך ההרשאות הן תיעוד של הכרעות שנעשו,
-- והמפתח פשוט חדל להישאל. אותו דפוס של סוגי ההתראה שהוצאו משימוש ב-0110.
update permission_registry set is_active = false
 where key = 'events.activity_note_view';

-- ===== 4. השטח מקבל יומן, ובו הערות ======================================
-- ‏0079 §2א ו-0080 כתבו לשלושת תפקידי השטח דחייה גורפת על כל מודול האירועים,
-- ושני המפתחות האלה נלכדו בה. אותו נימוק שהפך את `events.specs_view` ב-0102
-- חל כאן: מי שנוסע לאירוע הוא בדיוק מי שההערה נכתבה עבורו.
insert into role_permissions (role_id, permission_key, allowed)
select r.id, k, true
from permission_roles r, unnest(array['events.activity_log', 'events.activity_note']) k
where r.key in ('worker', 'driver', 'team_lead')
on conflict (role_id, permission_key) do update set allowed = true;

-- עובד קבלן שנוצר משיבוץ (`contractor_assign_worker`) נולד בלי תפקיד, ולכן
-- שכבת התפקידים שותקת עליו ומכריעה שכבת הקהל. מנהל הקבלן ועובד-הקבלן-שהוא-
-- גם-עובד כבר מחזיקים את שני המפתחות מ-0103.
insert into kind_permission_defaults (user_kind, permission_key, allowed) values
  ('contractor_user', 'events.activity_log',  true),
  ('contractor_user', 'events.activity_note', true)
on conflict (user_kind, permission_key) do update set allowed = true;
