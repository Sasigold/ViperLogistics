-- 0036 — מחזור החיים של סטטוס אירוע
--
-- לאירוע ארבעה סטטוסים: טרם אושר → אישור סופי → מתקיים, ובוטל בצד.
--
-- לסטטוס יש מעכשיו גם `code`. השם ניתן לשינוי ממסך ההגדרות, ולוח השנה צריך
-- לדעת מי מהם "בוטל" כדי להסתיר אותו כברירת מחדל — התאמה לפי שם הייתה
-- נשברת ברגע שמישהו מקליד "מבוטל". הקוד הוא הזהות היציבה, השם הוא התצוגה.
-- סטטוס שנוצר ידנית ממסך ההגדרות מקבל null, וזה בסדר: אין לו משמעות למערכת.
--
-- ארבע השורות הקיימות נכתבות מחדש במקום להימחק ולהיווצר. `events.status_id`
-- מצביע עליהן, ומחיקה הייתה מנתקת אירועים קיימים מהסטטוס שלהם.

alter table statuses add column if not exists code text;

comment on column statuses.code is
  'זהות יציבה לסטטוסי מערכת (pending/approved/active/cancelled). סטטוס שנוצר ידנית מחזיק null.';

create unique index if not exists statuses_entity_code
  on statuses (entity, code) where code is not null and deleted_at is null;

update statuses set code = 'pending',   name = 'טרם אושר',   color = '#f59e0b', sort_order = 1, is_terminal = false
  where entity = 'event' and name = 'מתוכנן';
update statuses set code = 'approved',  name = 'אישור סופי', color = '#22c55e', sort_order = 2, is_terminal = false
  where entity = 'event' and name = 'מאושר';
update statuses set code = 'active',    name = 'מתקיים',     color = '#3b82f6', sort_order = 3, is_terminal = false
  where entity = 'event' and name = 'הושלם';
update statuses set code = 'cancelled', name = 'בוטל',       color = '#ef4444', sort_order = 4, is_terminal = true
  where entity = 'event' and name = 'בוטל';

-- מסד שכבר עבר עריכה ידנית עלול לא להחזיק את אחד מהשמות שלמעלה. השלמה —
-- בלי לגעת בברירת המחדל, כי `statuses_one_default` מתיר אחת בלבד לישות.
insert into statuses (entity, name, color, sort_order, is_default, is_terminal, code)
select 'event', v.name, v.color, v.sort_order, false, v.is_terminal, v.code
from (values
  ('טרם אושר',   '#f59e0b', 1, false, 'pending'),
  ('אישור סופי', '#22c55e', 2, false, 'approved'),
  ('מתקיים',     '#3b82f6', 3, false, 'active'),
  ('בוטל',       '#ef4444', 4, true,  'cancelled')
) as v(name, color, sort_order, is_terminal, code)
where not exists (
  select 1 from statuses s where s.entity = 'event' and s.code = v.code and s.deleted_at is null
);

-- אירוע חדש נפתח על סטטוס ברירת המחדל, ולכן חייבת להיות אחת. מותנה, כדי
-- שלא לדרוס בחירה קיימת ולא להתנגש באינדקס בדרך.
update statuses set is_default = true
where id = (select id from statuses where entity = 'event' and code = 'pending' and deleted_at is null)
  and not exists (select 1 from statuses where entity = 'event' and is_default and deleted_at is null);
