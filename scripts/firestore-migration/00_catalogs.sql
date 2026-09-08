-- הרחבת הקטלוגים לקראת ייבוא הנתונים מ-Firestore (פרויקט nihol-mishmarot).
--
-- הקובץ אידמפוטנטי: כל הוספה מוגנת ב-`where not exists`, ולכן הרצה חוזרת
-- אינה יוצרת כפילויות. הוא נוגע *רק* בקטלוגים — האירועים והמשימות עצמם
-- נטענים בקבצים 10/20/30/40, שנבנים בידי build.mjs.
--
-- מה שנוסף כאן נגזר ישירות מהערכים שנמצאו במקור, אחרי איחוד הכפילויות
-- שסוכם מול הלקוח ("רק הרכבה" = "הרכבה בלבד", "רק פירוק" = "פירוק בלבד").

begin;

-- ── סטטוסי אירוע ─────────────────────────────────────────────────────────
-- ארבעת הסטטוסים הקיימים (pending/approved/active/cancelled) מכסים את רוב
-- הערכים. חמישה ערכים במקור אינם נופלים על אף אחד מהם, והם שלבים אמיתיים
-- בזרימת העבודה הישנה — 700+ אירועים יושבים עליהם, ולכן הם נוספים ולא
-- מקופלים פנימה. `code` נשאר null: אלה אינם סטטוסי מערכת.
insert into statuses (entity, name, color, sort_order, is_default, is_terminal)
select 'event', v.name, v.color, v.sort_order, false, v.is_terminal
from (values
  ('הזמנה חדשה',            '#94a3b8', 10, false),
  ('תומחר',                 '#0ea5e9', 11, false),
  ('בהמתנה לתמחור מחדש',    '#f97316', 12, false),
  ('הקמה בוצעה',            '#a3e635', 13, false),
  ('אירוע בוצע',            '#16a34a', 14, true)
) as v(name, color, sort_order, is_terminal)
where not exists (
  select 1 from statuses s
   where s.entity = 'event' and s.name = v.name and s.deleted_at is null
);

-- ── אופני ביצוע ──────────────────────────────────────────────────────────
-- "הכל" הוא הערך הנפוץ ביותר במקור (1,368 משימות) ואין לו מקבילה בקטלוג.
-- הערכים שמופיעים פחות מחמש פעמים נכנסים כ-is_active=false: הנתון נשמר
-- והשורה הקיימת ממשיכה להציג אותו, אבל הבורר של משימה חדשה אינו מתמלא
-- בזנב ארוך של ערכים חד-פעמיים.
insert into execution_methods (name, sort_order, is_active)
select v.name, v.sort_order, v.is_active
from (values
  ('הכל',                   10, true),
  ('הרכבת ברים ומזנונים',   11, true),
  ('פירוק ברים ומזנונים',   12, true),
  ('מחסן',                  13, true),
  ('צוות לשטח+נהג',         20, false),
  ('השלמה',                 21, false),
  ('עובד הפקה',             22, false),
  ('פגישת ספקים',           23, false),
  ('החברה',                 24, false),
  ('הרכבת בינויים',         25, false)
) as v(name, sort_order, is_active)
where not exists (
  select 1 from execution_methods m where m.name = v.name and m.deleted_at is null
);

-- אופן ביצוע חדש צריך להיות מותר לסוג המשימה ולשלושת הלקוחות, אחרת המשימה
-- תיטען עם ערך שהמסך אינו מציע ועריכה ראשונה תאפס אותו.
insert into task_type_execution_methods (task_type_id, execution_method_id)
select t.id, m.id from task_types t, execution_methods m
where m.name in ('הכל','הרכבת ברים ומזנונים','פירוק ברים ומזנונים','מחסן',
                 'צוות לשטח+נהג','השלמה','עובד הפקה','פגישת ספקים','החברה','הרכבת בינויים')
  and t.deleted_at is null and m.deleted_at is null
on conflict do nothing;

insert into customer_execution_methods (customer_id, execution_method_id)
select c.id, m.id from customers c, execution_methods m
where c.deleted_at is null and m.deleted_at is null
on conflict do nothing;

-- ── סוגי משימה ───────────────────────────────────────────────────────────
-- מעבר להקמה/פירוק, במקור יש 22 ערכי `akameOperok` חד-פעמיים ("צילומים",
-- "מחליף לאולג", "הובלה לכפר קאסם"...). הם נכנסים תחת "אחר", והמחרוזת
-- המקורית נשמרת ב-tasks.title כדי שהמשימה תישאר קריאה.
insert into task_types (name, sort_order, is_active)
select v.name, v.sort_order, true
from (values ('עבודה במחסן', 10), ('אחר', 11)) as v(name, sort_order)
where not exists (
  select 1 from task_types t where t.name = v.name and t.deleted_at is null
);

insert into task_type_execution_methods (task_type_id, execution_method_id)
select t.id, m.id from task_types t, execution_methods m
where t.name in ('עבודה במחסן','אחר') and t.deleted_at is null and m.deleted_at is null
on conflict do nothing;

-- ── קבלנים ───────────────────────────────────────────────────────────────
-- לפי השם שרשום על המסמך (cablanName / cablan[].name). קולקציית users אינה
-- נכנסת להעברה, ולכן אין כאן קישור למשתמש.
insert into contractors (name, is_active)
select v.name, true
from (values ('מחמוד'), ('אביתר'), ('יעקב'), ('רותם')) as v(name)
where not exists (
  select 1 from contractors c where btrim(c.name) = v.name and c.deleted_at is null
);

-- ── משאיות ───────────────────────────────────────────────────────────────
-- מתוך המערך `rechev`. "הגעה עצמית" אינה משאית ונשארת בטקסט החופשי.
insert into trucks (name, is_active)
select v.name, true
from (values ('משאית חדשה'), ('משאית ישנה'), ('קיה'), ('פרייבט')) as v(name)
where not exists (
  select 1 from trucks t where btrim(t.name) = v.name and t.deleted_at is null
);

commit;
