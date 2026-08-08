-- 0040: הפריסה של הדשבורד נשמרת בשרת
--
-- הפריסה עוברת בין מכשירים, ולכן היא לא יכולה לשבת ב-localStorage כמו העדפות
-- לוח העבודה. הבחירה בטבלה ייעודית ולא ב-`saved_filters` — שנראית מתאימה,
-- ושלוח השנה כבר משתמש בה — נובעת מ-RLS: הפוליסה `sf_own` היא
-- `profile_id = app.profile_id()`, ולכן **שורת ברירת מחדל ארגונית שקריאה
-- לכולם היא בלתי אפשרית שם**. להרחיב את `sf_own` פירושו לשנות את האבטחה של
-- הפילטרים השמורים של לוח השנה, וזו לא עסקה משתלמת בשביל לחסוך מיגרציה.
-- בנוסף אין ל-`saved_filters` לא `updated_at` ולא אינדקס ייחודי, כלומר אין
-- יעד ל-`on conflict` ו"שמור פריסה" היה מרוץ בין שתי לשוניות פתוחות.
--
-- **אין כאן זריעה.** שורה חסרה פירושה "ברירת המחדל המובנית", בדיוק כמו
-- `notification_preferences` (0030). פתיחת הדשבורד לעולם לא יוצרת שורה, ושורת
-- ברירת מחדל ארגונית נולדת רק כשמנהל קובע אותה במפורש. זריעה הייתה מחייבת
-- לכתוב את הפריסה גם ב-SQL וגם ב-`registry.tsx`, ושני העתקים היו מתפצלים.

create table dashboard_layouts (
  id             uuid primary key default gen_random_uuid(),
  -- null = שורת ברירת מחדל (ארגונית או פר-סוג משתמש)
  profile_id     uuid references profiles(id) on delete cascade,
  -- על שורת ברירת מחדל: null = לכל סוגי המשתמשים
  user_kind      user_kind,
  -- null = הפריסה הפעילה; שם = תצוגה שמורה
  name           text check (name is null or length(btrim(name)) between 1 and 60),
  layout         jsonb not null default '{"v":1,"items":[],"hidden":[],"seen":[]}'::jsonb,
  layout_version int not null default 1,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  updated_by     uuid references profiles(id),
  -- שורת ברירת מחדל אינה שייכת לאיש, ושורה אישית אינה מתייחסת לסוג משתמש.
  -- בלי האילוץ הזה אפשר היה לכתוב שורה שהיא גם וגם, ואז לא ברור מי קורא אותה.
  constraint dashboard_layouts_target check (profile_id is null or user_kind is null)
);

-- אינדקס אחד מכסה את ארבעת המצבים, כי `nulls not distinct` הופך NULL לערך
-- ולא ל"לא ידוע":
--   (משתמש, null, null)     — הפריסה הפעילה שלו, אחת
--   (משתמש, null, 'כספים')  — תצוגה שמורה, שם ייחודי לכל משתמש
--   (null, null, null)      — ברירת המחדל הארגונית, אחת
--   (null, 'staff', null)   — ברירת מחדל לסוג משתמש, אחת לכל סוג
--
-- אינדקס אחד ולא שלושה חלקיים, כי `on conflict` אינו יכול להסיק אינדקס חלקי
-- דרך PostgREST (אין דרך להעביר את ה-WHERE שלו), ובלי זה "שמור פריסה" הופך
-- ל-select-ואז-insert-או-update — מרוץ בין שתי לשוניות פתוחות.
--
-- `coalesce(user_kind::text, '*')` היה הניסוח המתבקש והוא אינו אפשרי: הטלה של
-- enum ל-text היא stable ולא immutable, ולכן פסולה בביטוי אינדקס.
create unique index dashboard_layouts_key_uq
  on dashboard_layouts (profile_id, user_kind, name) nulls not distinct;

create trigger dashboard_layouts_updated before update on dashboard_layouts
  for each row execute function app.set_updated_at();

alter table dashboard_layouts enable row level security;

-- ברירות המחדל קריאות לכולם; שורה אישית לבעליה; ואדמין רואה הכול.
create policy dl_select on dashboard_layouts for select to authenticated
  using (profile_id is null
      or profile_id = (select app.profile_id())
      or (select app.is_admin()));

create policy dl_write_own on dashboard_layouts for all to authenticated
  using      (profile_id is not null and profile_id = (select app.profile_id()))
  with check (profile_id is not null and profile_id = (select app.profile_id()));

-- מדיניות נפרדת במכוון, ולא `or` בתוך הקודמת: כך אין ניסוח שבו משתמש מגיע
-- לשורת ברירת המחדל הארגונית פשוט על ידי כתיבת profile_id = null.
create policy dl_write_default on dashboard_layouts for all to authenticated
  using      (profile_id is null and (select app.has('dashboard.manage_default')))
  with check (profile_id is null and (select app.has('dashboard.manage_default')));

comment on table dashboard_layouts is
  'פריסת הדשבורד. שורה עם profile_id היא של משתמש; שורה בלעדיו היא ברירת מחדל.';
