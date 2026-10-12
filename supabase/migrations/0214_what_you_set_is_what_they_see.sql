-- 0214: מה שמגדירים הוא מה שרואים — סדר בהרשאות
--
-- הדיווח, במילים של הבעלים: "פתאום אוראל רואה לוח שנה עם כל האירועים של כל
-- הלקוחות... זה חייב לעבוד טוב: אם אני עורך לקבלן שיראה רק את המשימות שלו —
-- הוא רואה רק את המשימות שלו; משתמש של לקוח רואה רק את האירועים של הלקוח
-- שלו; ואם אני נותן למישהו לראות אירועים — הוא רואה אותם בלוח השנה, ואם אני
-- נותן לו לראות מחירים — הוא רואה מחירים."
--
-- **מה קרה לאוראל.** אוראל הוא עובד בסגל של ארקו (חשבון `customer_user`,
-- ‏0178) ונפתח עם התפקיד "עובד אצל הלקוח", שנושא היקף `own` — רואה רק את מה
-- ששובץ אליו. התפקידים הוחלפו כמה פעמים, ובאחד בספטמבר נכתבה לו ישירות במסד
-- שורת היקף אישית `events = all`. לפי ההכרעה של 0010 שורה אישית אחת **מחליפה
-- את כל** שורות התפקיד על אותו מודול — ולכן "רק מה ששובץ אליי" נעלם, והוא רואה
-- את כל 1,155 האירועים של ארקו, כל אחד בשם לקוח הקצה שלו. לקוח אחר הוא לא ראה:
-- הגדר של סוג המשתמש ב-RLS החזיקה. אבל מה שהוגדר ומה שקרה נפרדו, ומסך
-- ההיקפים לא הראה את זה — הוא הציג למשתמש "ללא הגבלת נתונים... בכל הלקוחות".
--
-- הבדיקה שנעשתה כאן הלכה הלאה מאוראל: כל משתמש אמיתי במסד החי הורץ בזהותו
-- (בטרנזקציה שבוטלה) מול כל טבלה, וכל פונקציית `security definer` נקראה. מה
-- שנמצא אינו באג אחד אלא כמה מחלקות, וכל אחת נסגרת כאן ככלל ולא כמקרה:
--
--   1. **מפתח שאינו חל על סוג המשתמש הוענק בכל זאת** (§1). ‏`app.has` התעלם
--      מ-`applies_to` (המלכודת של 0026/0042), ולכן מנהלי לקוח החזיקו "הפקה
--      ושליחה של הצעת מחיר" ו"הסתרת משימה מהלו״ז" — מפתחות משרד בלבד — בירושה
--      מ"עריכת אירוע", בלי שהמטריצה הציגה להם אותם בכלל. מעכשיו מפתח שאינו חל
--      על הסוג אינו מוענק לו בשום שכבה, ומה שהמטריצה מציגה הוא כל מה שיש.
--   2. **הגבלת נתונים שפתחה גישה** (§2). שורה אישית מחליפה רק את שורות התפקיד
--      **מאותו סוג**; "ללא הגבלה" אישית היא הדרך המפורשת היחידה לבטל את כולן.
--      ורשימה ריקה ("לקוחות: —") סוגרת במקום לפתוח.
--   3. **"צפייה באירועים/משימות" לא נאכפה על לקוח וקבלן** (§3). הגדר של הסוג
--      הספיק לבדו; מי שהמפתח נחסם לו המשיך לקרוא הכול דרך ה-API ובלוח השנה.
--   4. **דליפות בין קבלנים ובין עובדים** (§4–§6): עובד צוות שהוא גם קבלן קרא את
--      התמחור של כל הקבלנים; עובד קבלן קרא וכתב את הסגל של קבלנים אחרים; מנהל
--      קבלן יכול היה לשבץ את העובד שלו למשימה של קבלן אחר ומשם לראות את האירוע
--      (תנאי טאוטולוגי, `tct.task_id = tct.task_id`); עובד עם "הגדרות שעון פר
--      עובד" קרא את התעריף השעתי של כולם ושינה בונוסים למשמרת; מחירי משימות
--      נפתחו לעובד מוגבל-היקף מעבר להיקף שלו.
--   5. **המטא-דאטה של ההרשאות** (§7) — מי מחזיק איזה תפקיד והרשאה — נקראה בין
--      לקוחות, וסכומי ההזמנה מ-ViperFlow (§8) נקראו על ידי כל מי שרואה את האירוע.
--
-- מה שאינו כאן במכוון: שינוי הגדרות של אנשים אמיתיים (אוראל, תפקיד "עובד"
-- שקיבל "הגדרות שעון פר-עובד"). אלה הכרעות של מנהל המערכת ונעשות במסך — מה
-- שהמיגרציה מבטיחה הוא שהמסך מראה אותן נכון ושהשרת אוכף בדיוק אותן.

-- ===== 1. מפתח שאינו חל על סוג המשתמש אינו מוענק לו ========================
--
-- ‏`applies_to` היה עד כאן "בשביל המטריצה" בלבד (README, "מלכודת ששווה
-- לזכור"): המטריצה מסתירה מפתח שאינו חל על הסוג, ו-`app.has` ממשיך להעניק
-- אותו בירושה. זו בדיוק ההגדרה של הרשאה שאי אפשר לראות ואי אפשר לחסום.
--
-- לפני שהכלל נאכף, המפתחות שסוג נוסף באמת משתמש בהם מקבלים אותו — כדי שאיש
-- לא יאבד יכולת שהייתה לו בכוונה (הרשימה נגזרה מהרצה על המסד החי של "מה כל
-- תפקיד ומשתמש מחזיק בפועל מחוץ ל-applies_to"):
--
--   * הלוח ולוח השנה של הקבלן (0071: "ללקוח ולקבלן אין מסכים משלהם"). התפקידים
--     שלו מחזיקים `board.view`/`calendar.view` במפורש מאז 0066, ושני תפקידי
--     הקבלן נשענים על `board.view_staffing` (‏`ta_select`) ועל צפייה באיש הקשר
--     של האירוע (0103) — אז הם נכנסים ל-`applies_to` שלהם.
--   * מפתחות הפורטל אצל איש צוות שהוא גם קבלן (`staff_contractor`, ‏0075).
--   * מחיקת אירוע אצל לקוח: ‏`soft_delete` תומכת בה (עם גדר "אירוע של הלקוח
--     שלי") ו-0209 בודקת אותה, והמפתח עצמו נרשם לצוות בלבד. ברירת המחדל של
--     קהל הלקוחות סוגרת אותו, ולכן איש אינו מקבל אותו — הוא רק נעשה גלוי
--     במטריצה למי שמנהל מערכת ירצה להעניק לו.
--
-- ושני מפתחות שהם של המשרד בהכרעה מתועדת יוצאים מקהל הקבלנים: ניהול הסגל
-- (0106) והשיבוץ המשרדי (0108). ברירת המחדל לקהל הקבלנים השאירה את הראשון
-- פתוח לעובד קבלן בלי תפקיד, ו-`cw_staff_write` (‏`for all`) פתחה לו בזכותו
-- קריאה וכתיבה של הסגל של **כל** הקבלנים.

update permission_registry
   set applies_to = array(select distinct k from unnest(applies_to || array['contractor_user']::user_kind[]) k
                          order by k)
 where key in ('board.view', 'board.view_staffing', 'board.open_task',
               'calendar.view', 'calendar.filter', 'calendar.save_filters',
               'events.view_contacts')
   and not ('contractor_user' = any (applies_to));

update permission_registry
   set applies_to = array(select distinct k from unnest(applies_to || array['staff']::user_kind[]) k
                          order by k)
 where key in ('portal.view', 'portal.assign_workers', 'portal.view_financials',
               'portal.approve_attendance', 'portal.manage_workers',
               'portal.attendance', 'portal.attendance_pay')
   and not ('staff' = any (applies_to));

update permission_registry
   set applies_to = array(select distinct k from unnest(applies_to || array['customer_user']::user_kind[]) k
                          order by k)
 where key = 'events.delete'
   and not ('customer_user' = any (applies_to));

update permission_registry
   set applies_to = array['staff']::user_kind[]
 where key in ('contractors.manage_workers', 'contractors.assign_workers');

-- "הסתרת משימה מהלו״ז" נרשמה ב-0188 עם `board.view` בעמדת ה-`implied_by`,
-- והכותרת שם קוראת לפרמטר "requires" — והכוונה כתובה במפורש: "אינו ניתן
-- כברירת מחדל לאיש, ומנהל המערכת מחזיק אותו ממילא". ‏`implied_by` הוא ההפך
-- מ-requires: הוא מעניק את המפתח לכל מי שפותח את הלוח, וכך כל מנהל לקוח יכול
-- היה להעלים משימה שלו מהלו״ז של המשרד. בפועל רק מנהלי מערכת סימנו משימות.
update permission_registry set implied_by = null where key = 'board.hide_task';

create or replace function app.has(p_key text) returns boolean
language sql stable security definer set search_path = public as $$
  with recursive chain(key, depth) as (
    select p_key, 0
    union all
    select r.implied_by, c.depth + 1
    from chain c
    join permission_registry r on r.key = c.key
    where r.implied_by is not null and c.depth < 8
  ),
  resolved as (
    select c.depth, coalesce(
      (select g.allowed from user_permission_grants g
        where g.profile_id = app.profile_id() and g.permission_key = c.key),
      (select bool_or(rp.allowed) from role_permissions rp
        where rp.role_id = any(app.my_role_ids()) and rp.permission_key = c.key),
      (select k.allowed from kind_permission_defaults k
        where k.user_kind = app.user_kind()::user_kind and k.permission_key = c.key),
      (select true from permission_registry r
        where r.key = c.key and r.is_active and r.default_allowed)
    ) as decided
    from chain c
  )
  select case
    when app.is_admin() then true
    when app.profile_id() is null then false
    -- ‏0214: מפתח לא פעיל, לא מוכר, או שאינו חל על סוג המשתמש — אינו מוענק
    -- בשום שכבה. זו השורה שהופכת את המטריצה למלאה: מה שהיא אינה מציגה לסוג,
    -- הוא גם אינו מחזיק.
    when not exists (select 1 from permission_registry r
                      where r.key = p_key and r.is_active
                        and app.user_kind()::user_kind = any (r.applies_to)) then false
    else coalesce(
      (select decided from resolved where decided is not null order by depth limit 1),
      false)
  end
$$;

comment on function app.has(text) is
  'ההכרעה היחידה על מפתח (0010). מאז 0214: מפתח שאינו חל על סוג המשתמש (applies_to), '
  'או שאינו פעיל, אינו מוענק בשום שכבה — כך שהמטריצה מציגה את כל מה שהמשתמש מחזיק.';

-- הבבואה של `app.has` לכל המשתמשים בבת אחת (0024) — נמענים של התראות. היא
-- אומרת עכשיו את אותם שני כללים: ‏`applies_to`, והתפקידים שבתוקף כפי ש-
-- ‏`app.my_role_ids()` מכריעה אותם (תפקיד מסוג אחר אינו חל; כובע מנהל הקבלן
-- גובר על כובע העובד, 0104). עד כאן היא ספרה כל תפקיד שהוצמד, גם כזה שאינו
-- מעניק דבר, ולכן יכלה לשלוח התראה למי שאינו רשאי לפתוח אותה.
create or replace function app.profiles_with(p_key text) returns setof uuid
language sql stable security definer set search_path = public as $$
  with recursive chain(key, depth) as (
    select p_key, 0
    union all
    select r.implied_by, c.depth + 1
    from chain c
    join permission_registry r on r.key = c.key
    where r.implied_by is not null and c.depth < 8
  ),
  applies as (
    select r.applies_to from permission_registry r where r.key = p_key and r.is_active
  ),
  held as (
    select p.id as profile_id, r.id as role_id, r.key as role_key
      from profiles p
      join profile_roles pr on pr.profile_id = p.id
      join permission_roles r on r.id = pr.role_id
     where p.is_active and p.deleted_at is null
       and r.is_active and r.deleted_at is null
       and (r.user_kind is null or r.user_kind = p.user_kind)
  ),
  people as (
    select p.id, p.user_kind, p.is_admin,
           coalesce((select array_agg(h.role_id) from held h
                      where h.profile_id = p.id
                        and (h.role_key <> 'contractor_worker'
                             or not exists (select 1 from held h2
                                             where h2.profile_id = p.id
                                               and h2.role_key in ('contractor_manager', 'staff_contractor')))),
                    '{}'::uuid[]) as roles
    from profiles p
    where p.is_active and p.deleted_at is null
  ),
  resolved as (
    select pe.id, c.depth, coalesce(
      (select g.allowed from user_permission_grants g
        where g.profile_id = pe.id and g.permission_key = c.key),
      (select bool_or(rp.allowed) from role_permissions rp
        where rp.role_id = any(pe.roles) and rp.permission_key = c.key),
      (select k.allowed from kind_permission_defaults k
        where k.user_kind = pe.user_kind and k.permission_key = c.key),
      (select true from permission_registry r
        where r.key = c.key and r.is_active and r.default_allowed)
    ) as decided
    from people pe cross join chain c
  )
  select pe.id from people pe
  where pe.is_admin
     or (exists (select 1 from applies a where pe.user_kind = any (a.applies_to))
         and coalesce((select rs.decided from resolved rs
                        where rs.id = pe.id and rs.decided is not null
                        order by rs.depth limit 1), false))
$$;

-- ===== 2. הגבלת נתונים מצמצמת — היא אינה פותחת =============================
--
-- ‏0010 קבעה: "השורות האישיות אם יש, אחרת האיחוד של שורות התפקידים", מחשש
-- שאיחוד היה מונע צמצום אישי (תפקיד "לקוחות א,ב" + אישי "לקוח א" = שוב א,ב).
-- המחיר היה הפוך ממה שנראה במסך: חלון תאריכים אישי לעובד שטח ביטל לו את
-- "רק מה שמשויך אליי" של התפקיד — כלומר הגבלה שנוספה **פתחה** לו את כל
-- האירועים בחלון. ההכרעה עוברת לרמת הסוג:
--
--   * שורה אישית מסוג מסוים מחליפה את שורות התפקיד **מאותו סוג בלבד** — הצמצום
--     האישי של "לקוחות" עדיין אפשרי, וה-`own` של התפקיד נשאר במקומו.
--   * ‏"ללא הגבלה" אישית (`all`) היא הדרך המפורשת היחידה לבטל את כל הגבלות
--     התפקיד, ומסך ההיקפים מציג אותה כך: "ההגבלות שמגיעות מהתפקיד בוטלו".
--     שורת `all` של **תפקיד** אינה מגבילה ואינה מבטלת דבר.
--   * מנהל מערכת אינו מוגבל בהיקף (0085) — בלי שינוי.

create or replace function app.scope_rows(p_resource text)
returns setof permission_scopes
language sql stable security definer set search_path = public as $$
  with mine as (
    select * from permission_scopes
     where not app.is_admin() and resource = p_resource and profile_id = app.profile_id()
  ),
  lifted as (
    select exists (select 1 from mine where scope_type = 'all') as yes
  )
  select m.* from mine m cross join lifted l
   where (m.scope_type = 'all') = l.yes
  union all
  select s.* from permission_scopes s cross join lifted l
   where not app.is_admin()
     and not l.yes
     and s.resource = p_resource
     and s.role_id = any (app.my_role_ids())
     and s.scope_type <> 'all'
     and not exists (select 1 from mine m where m.scope_type = s.scope_type)
$$;

comment on function app.scope_rows(text) is
  'שורות ההיקף שחלות על הקורא (0214): שורה אישית מחליפה את שורות התפקיד מאותו סוג '
  'בלבד, ו"ללא הגבלה" אישית (all) מבטלת את כולן. אדמין אינו מוגבל (0085).';

-- ‏null — המימד אינו מוגבל; מערך ריק — מוגבל לשום דבר. עד כאן רשימה ריקה
-- (`nullif(..., '{}')`) נקראה "ללא הגבלה", ולכן הגבלת "לקוחות" שנוספה ועוד לא
-- נבחר בה לקוח פתחה את כל הלקוחות — ואישית, היא גם ביטלה את ה-`own` של
-- התפקיד. מעכשיו היא סוגרת עד שנבחר בה ערך, והמסך אומר את זה.
create or replace function app.scope_ids(p_resource text, p_type permission_scope_type)
returns uuid[] language sql stable security definer set search_path = public as $$
  select case
    when exists (select 1 from app.scope_rows(p_resource) s where s.scope_type = p_type)
    then array(select distinct u from app.scope_rows(p_resource) s, unnest(s.scope_values) u
                where s.scope_type = p_type)
  end
$$;

-- "הקורא מצומצם במשימות" — השאלה ששערי הכספים כבר שואלים (0085, ‏
-- ‏`app.margin_require` ואחיותיה), בפונקציה אחת שהפוליסות של §5 יכולות לשאול
-- כ-InitPlan.
create or replace function app.tasks_scoped() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from app.scope_rows('tasks') where scope_type <> 'all')
$$;

revoke execute on function app.tasks_scoped() from anon, public;
grant execute on function app.tasks_scoped() to authenticated;

-- ===== 3. "צפייה באירועים / משימות" נאכפת על כל סוגי המשתמשים =============
--
-- בזרוע הצוות של `events_select` המפתח `events.view` תמיד נשאל; בזרועות הלקוח
-- והקבלן — לא. הגדר של הסוג ("של הלקוח שלי") הספיק לבדו, ולכן משתמש לקוח
-- שהמפתח נחסם לו המשיך לקרוא את כל האירועים של הלקוח דרך ה-API, ולוח השנה —
-- ש-`calendar.view` שלו פתוח לקהל הלקוחות כברירת מחדל — הציג אותם. אותו דבר
-- במשימות.
--
-- הזרועות אומרות עכשיו את מה שזרוע הצוות אומרת: המפתח, **או** שיבוץ אישי
-- לאירוע/למשימה. עובד ששובץ רואה את מה ששובץ אליו גם בלי המפתח — כמו
-- `app.on_event_as_staff` אצל הצוות — וזה גם מה שמחזיק את "רק מה שמשויך
-- אליי" של עובד הלקוח (0178) ושל עובד הקבלן.
--
-- וזרועות העובד עצמן נקשרות לתנאי שחסר בהן: עובד קבלן ששובץ למשימה נחשב
-- "משובץ" רק אם הקבלן שלו הוא שהמשימה הואצלה לו, ועובד לקוח — רק על משימה של
-- הלקוח שלו. בלי זה, שורת שיבוץ אחת שנכתבה בטעות (או דרך התנאי הטאוטולוגי
-- של §4) הייתה פותחת אירוע של לקוח אחר.

create or replace function app.on_task_as_contractor_worker(p_task_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from task_contractor_workers w
    join contractor_workers cw on cw.id = w.contractor_worker_id
    join profiles pr on pr.contractor_worker_id = w.contractor_worker_id
    join task_contractor_terms tct on tct.task_id = w.task_id
                                  and tct.contractor_id = cw.contractor_id
    where w.task_id = p_task_id and pr.id = app.profile_id())
$$;

create or replace function app.on_event_as_contractor_worker(p_event_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from tasks t
    join task_contractor_workers w on w.task_id = t.id
    join contractor_workers cw on cw.id = w.contractor_worker_id
    join profiles pr on pr.contractor_worker_id = w.contractor_worker_id
    join task_contractor_terms tct on tct.task_id = t.id
                                  and tct.contractor_id = cw.contractor_id
    where t.event_id = p_event_id and t.deleted_at is null
      and pr.id = app.profile_id()
      and t.status_id = (select s.id from statuses s
                          where s.entity = 'task' and s.code = 'assigned'
                            and s.deleted_at is null limit 1))
$$;

create or replace function app.on_task_as_customer_worker(p_task_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from task_customer_workers w
    join customer_workers cuw on cuw.id = w.customer_worker_id
    join profiles pr on pr.customer_worker_id = w.customer_worker_id
    join tasks t on t.id = w.task_id and t.customer_id = cuw.customer_id
    where w.task_id = p_task_id and pr.id = app.profile_id())
$$;

create or replace function app.on_event_as_customer_worker(p_event_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from tasks t
    join task_customer_workers w on w.task_id = t.id
    join customer_workers cuw on cuw.id = w.customer_worker_id
    join profiles pr on pr.customer_worker_id = w.customer_worker_id
    where t.event_id = p_event_id and t.deleted_at is null
      and t.customer_id = cuw.customer_id
      and pr.id = app.profile_id())
$$;

-- שתי הפוליסות מועתקות מ-0178 מילה במילה; השינוי הוא בזרועות הלקוח והקבלן
-- שבסוף כל אחת.

drop policy tasks_select on tasks;
create policy tasks_select on tasks for select to authenticated using (
  ((select app.is_admin()) and performed_by <> 'arko')
  or (deleted_at is null
    and ((select app.scope_ids('tasks', 'customers')) is null
         or customer_id = any((select app.scope_ids('tasks', 'customers'))::uuid[]))
    and ((select app.scope_ids('tasks', 'contractors')) is null
         or contractor_id = any((select app.scope_ids('tasks', 'contractors'))::uuid[]))
    and ((select app.scope_ids('tasks', 'task_types')) is null
         or task_type_id = any((select app.scope_ids('tasks', 'task_types'))::uuid[]))
    and ((select app.scope_ids('tasks', 'statuses')) is null
         or status_id = any((select app.scope_ids('tasks', 'statuses'))::uuid[]))
    and ((select app.scope_ids('tasks', 'execution_methods')) is null
         or execution_method_id = any((select app.scope_ids('tasks', 'execution_methods'))::uuid[]))
    and ((select app.scope_ids('tasks', 'trucks')) is null
         or truck_id = any((select app.scope_ids('tasks', 'trucks'))::uuid[]))
    and ((select app.scope_date_from('tasks')) is null
         or task_date >= (select app.scope_date_from('tasks')))
    and ((select app.scope_date_to('tasks')) is null
         or task_date <= (select app.scope_date_to('tasks')))
    and (not (select app.scope_own('tasks'))
         or exists (select 1 from task_assignments a
                    where a.task_id = tasks.id and a.profile_id = (select app.profile_id()))
         or (select app.assignment_on_my_contractor(tasks.id))
         or (select app.on_task_as_customer_worker(tasks.id))
         or ((select app.user_kind()) <> 'staff'
             and created_by = (select app.profile_id())))
    and ((select app.user_kind()) <> 'staff'
         or (select app.can_plan_tasks())
         or (created_by = (select app.profile_id())
             and not (select app.scope_own('tasks')))
         or ((select app.has('portal.view'))
             and (select app.assignment_on_my_contractor(tasks.id)))
         or status_id = (select s.id from statuses s
                          where s.entity = 'task' and s.code = 'assigned'
                            and s.deleted_at is null limit 1))
    and (
      ((select app.user_kind()) = 'staff' and (select app.has('tasks.view'))
          and performed_by <> 'arko')
      -- ‏0214: ‏`tasks.view`, או שיבוץ אישי למשימה.
      or ((select app.user_kind()) = 'customer_user' and customer_id = (select app.customer_id())
          and ((select app.has('tasks.view'))
               or (select app.on_task_as_customer_worker(tasks.id))))
      or ((select app.contractor_id()) is not null
          and performed_by <> 'arko'
          and (select app.assignment_on_my_contractor(tasks.id))
          and (((select app.has('portal.view')) and (select app.has('tasks.view')))
               or (status_id = (select s.id from statuses s
                                 where s.entity = 'task' and s.code = 'assigned'
                                   and s.deleted_at is null limit 1)
                   and (select app.on_task_as_contractor_worker(tasks.id)))))
      or (exists (select 1 from task_assignments a
                   where a.task_id = tasks.id and a.profile_id = (select app.profile_id()))
          and performed_by <> 'arko')
    )));

drop policy events_select on events;
create policy events_select on events for select to authenticated using (
  ((select app.is_admin()) and not (select app.event_all_tasks_arko(events.id)))
  or (deleted_at is null
    and ((select app.scope_ids('events', 'customers')) is null
         or customer_id = any((select app.scope_ids('events', 'customers'))::uuid[]))
    and ((select app.scope_ids('events', 'statuses')) is null
         or status_id = any((select app.scope_ids('events', 'statuses'))::uuid[]))
    and ((select app.scope_date_from('events')) is null
         or event_date >= (select app.scope_date_from('events')))
    and ((select app.scope_date_to('events')) is null
         or event_date <= (select app.scope_date_to('events')))
    and (not (select app.scope_own('events'))
         or (select app.on_event_as_staff(events.id))
         or (select app.event_on_my_contractor(events.id))
         or (select app.on_event_as_customer_worker(events.id))
         or ((select app.user_kind()) <> 'staff'
             and created_by = (select app.profile_id())))
    and (
      ((select app.user_kind()) = 'staff' and ((select app.has('events.view'))
         or (select app.on_event_as_staff(events.id))
         or ((select app.has('portal.view'))
             and (select app.event_on_my_contractor(events.id))))
         and not (select app.event_all_tasks_arko(events.id)))
      -- ‏0214: ‏`events.view`, או שיבוץ אישי לאירוע.
      or ((select app.user_kind()) = 'customer_user' and customer_id = (select app.customer_id())
          and ((select app.has('events.view'))
               or (select app.on_event_as_customer_worker(events.id))))
      or ((select app.contractor_id()) is not null and (
            ((select app.has('portal.view')) and (select app.has('events.view'))
             and (select app.event_on_my_contractor(events.id)))
            or (select app.on_event_as_contractor_worker(events.id))))
    )));

-- ===== 4. התמחור והסגל של קבלן הם שלו — לא של קבלן אחר =====================
--
-- (א) ‏`tct_select`: זרוע הצוות פתחה את **כל** שורות התמחור לכל איש צוות עם
-- ‏`contractors.view_pricing` — והמפתח הזה מגיע גם בתפקיד `staff_contractor`,
-- כלומר לכל עובד שלנו שהוא גם קבלן. במסד החי עובד כזה קרא כמה אנחנו משלמים
-- לחמישה קבלנים אחרים. איש צוות שמשויך לקבלן רואה מעכשיו את התמחור של הקבלן
-- שלו בלבד, אלא אם הוא מחזיק גם את מפתח המשרד `contractors.view`.
--
-- (ב) ‏`tct_write` הייתה `for all`, ולכן גם היא פתחה קריאה של כל השורות לכל
-- מי שמחזיק מפתח כתיבה. היא מתפצלת לשלוש פוליסות כתיבה (כלל 10 ב-CLAUDE.md),
-- באותו גדר משרדי.

drop policy tct_select on task_contractor_terms;
create policy tct_select on task_contractor_terms for select to authenticated using (
  (select app.is_admin())
  or ((select app.user_kind()) = 'staff'
      and ((select app.has('contractors.view_pricing'))
           or (select app.has('contractors.edit_pricing'))
           or (select app.has('contractors.mark_paid')))
      and ((select app.contractor_id()) is null or (select app.has('contractors.view'))))
  or (contractor_id = (select app.contractor_id())
      and (select app.has('contractors.view_pricing'))));

drop policy tct_write on task_contractor_terms;
create policy tct_insert on task_contractor_terms for insert to authenticated with check (
  (select app.is_admin())
  or ((select app.user_kind()) = 'staff'
      and ((select app.has('contractors.edit_pricing')) or (select app.has('contractors.mark_paid')))
      and ((select app.contractor_id()) is null or (select app.has('contractors.view')))));
create policy tct_update on task_contractor_terms for update to authenticated using (
  (select app.is_admin())
  or ((select app.user_kind()) = 'staff'
      and ((select app.has('contractors.edit_pricing')) or (select app.has('contractors.mark_paid')))
      and ((select app.contractor_id()) is null or (select app.has('contractors.view')))))
  with check (
  (select app.is_admin())
  or ((select app.user_kind()) = 'staff'
      and ((select app.has('contractors.edit_pricing')) or (select app.has('contractors.mark_paid')))
      and ((select app.contractor_id()) is null or (select app.has('contractors.view')))));
create policy tct_delete on task_contractor_terms for delete to authenticated using (
  (select app.is_admin())
  or ((select app.user_kind()) = 'staff'
      and ((select app.has('contractors.edit_pricing')) or (select app.has('contractors.mark_paid')))
      and ((select app.contractor_id()) is null or (select app.has('contractors.view')))));

-- (ג) ‏`tcw_contractor_insert/delete` (0098) כתבו `tct.task_id = task_id` בתוך
-- תת-שאילתה על `task_contractor_terms` — ו-`task_id` הלא-מוסמך נפתר לעמודה של
-- הטבלה הפנימית. התנאי היה `tct.task_id = tct.task_id`, כלומר "לקבלן שלי יש
-- תמחור על משימה כלשהי". מנהל קבלן יכול היה לשבץ את העובד שלו למשימה של
-- קבלן אחר — ומשם, דרך `app.on_event_as_contractor_worker`, לראות את האירוע
-- של לקוח אחר — ו-`DELETE` בלי סינון מחק את שיבוצי כל הקבלנים. השאלה עוברת
-- ל-`app.assignment_on_my_contractor`, אותה שאלה בדיוק כ-`security definer`
-- (0105: תת-שאילתה על טבלת הכסף נשפטת תחת ה-RLS של הקורא).

drop policy tcw_contractor_insert on task_contractor_workers;
create policy tcw_contractor_insert on task_contractor_workers for insert to authenticated
  with check (
    (select app.has('portal.assign_workers'))
    and app.assignment_on_my_contractor(task_contractor_workers.task_id)
    and exists (select 1 from contractor_workers cw
                where cw.id = task_contractor_workers.contractor_worker_id
                  and cw.contractor_id = (select app.contractor_id())
                  and cw.deleted_at is null));

drop policy tcw_contractor_delete on task_contractor_workers;
create policy tcw_contractor_delete on task_contractor_workers for delete to authenticated
  using (
    (select app.has('portal.assign_workers'))
    and app.assignment_on_my_contractor(task_contractor_workers.task_id)
    and exists (select 1 from contractor_workers cw
                where cw.id = task_contractor_workers.contractor_worker_id
                  and cw.contractor_id = (select app.contractor_id())));

-- (ד) ‏`cw_staff_write` (0012) היא `for all` על המפתח המשרדי בלי שום גדר — והיא
-- גם פוליסת קריאה. עם §1 המפתח כבר אינו מוענק לקבלן; הפוליסה מתפצלת ונגדרת
-- לצוות בכל זאת, כדי שהכתיבה לא תיפתח שוב ביום שמפתח יוענק בטעות.

drop policy cw_staff_write on contractor_workers;
create policy cw_staff_insert on contractor_workers for insert to authenticated with check (
  (select app.is_admin())
  or ((select app.user_kind()) = 'staff' and (select app.has('contractors.manage_workers'))));
create policy cw_staff_update on contractor_workers for update to authenticated
  using ((select app.is_admin())
         or ((select app.user_kind()) = 'staff' and (select app.has('contractors.manage_workers'))))
  with check ((select app.is_admin())
         or ((select app.user_kind()) = 'staff' and (select app.has('contractors.manage_workers'))));
create policy cw_staff_delete on contractor_workers for delete to authenticated using (
  (select app.is_admin())
  or ((select app.user_kind()) = 'staff' and (select app.has('contractors.manage_workers'))));

-- ===== 5. מחיר משימה נקרא רק על משימה שהקורא רואה ==========================
--
-- ‏`tp_select`/`tpa_select` פתחו לאיש צוות עם `pricing.view` את המחיר של כל
-- משימה במערכת, גם כשההיקף שלו מצומצם ללקוח אחד או "רק מה שמשויך אליי".
-- לקורא שאינו מצומצם אין כאן שינוי (InitPlan אחד, בלי בדיקה פר-שורה); לקורא
-- מצומצם המחיר הולך אחרי `tasks_select` — היקפים, פרסום והכול.

drop policy tp_select on task_pricing;
create policy tp_select on task_pricing for select to authenticated using (
  (select app.is_admin())
  or ((select app.user_kind()) = 'staff' and (select app.has('pricing.view'))
      and (not (select app.tasks_scoped())
           or exists (select 1 from tasks t where t.id = task_pricing.task_id)))
  or ((select app.user_kind()) = 'customer_user' and (select app.has('pricing.view'))
      and exists (select 1 from tasks t
                   where t.id = task_pricing.task_id
                     and t.customer_id = (select app.customer_id())
                     and t.deleted_at is null)));

drop policy tpa_select on task_price_addons;
create policy tpa_select on task_price_addons for select to authenticated using (
  ((select app.is_admin()) or deleted_at is null)
  and ((select app.is_admin())
       or ((select app.user_kind()) = 'staff' and (select app.has('pricing.view'))
           and (not (select app.tasks_scoped())
                or exists (select 1 from tasks t where t.id = task_price_addons.task_id)))
       or ((select app.user_kind()) = 'customer_user' and (select app.has('pricing.view'))
           and exists (select 1 from tasks t
                        where t.id = task_price_addons.task_id
                          and t.customer_id = (select app.customer_id())
                          and t.deleted_at is null))));

-- ===== 6. הגדרות השכר של עובד הן של המשרד ===================================
--
-- ‏`attendance.manage_clock` ("הגדרות שעון פר-עובד" — מיקום, רדיוס, התחלה
-- מוקדמת) פתח ב-`wps_select` את **כל** השורה של **כל** עובד, כולל התעריף
-- השעתי, וב-`wps_write` (‏`for all`) את הכתיבה לכל עמודה שאינה רשומה במרשם
-- השדות — והבונוס למשמרת, בונוס ראש הצוות והשלמת האיחור אינם רשומים בו. במסד
-- החי התפקיד "עובד" מחזיק את המפתח, ולכן כל עובד יכול היה לקרוא את שכר חבריו
-- ולשנות לעצמו בונוס. (הבדיקה נעשתה בטרנזקציה שבוטלה; שום ערך לא השתנה.)
--
--   * כל עמודה בטבלה נרשמת עכשיו כשדה, עם המפתח שכותב אותה — כסף תחת
--     `attendance.manage_pay`, שעון תחת `attendance.manage_clock` — כך
--     ש-`app.enforce_field_perms` מכסה את כולן.
--   * קריאת שורה של אדם אחר: מנהל מערכת, `attendance.view_pay`, או מנהל הקבלן
--     על הסגל שלו (0103). ‏`manage_clock` לבדו כבר אינו פותח אותה.
--   * כתיבה ישירה בטבלה: `attendance.manage_pay` בלבד, ולא `for all`.
--   * מי שמנהל שעון בלבד קורא וכותב דרך `worker_settings_for` /
--     ‏`worker_settings_save`, שמחזירות את השעון ומסתירות את הכסף.

select app.register_field('worker_pay', 'team_lead_bonus', 'בונוס ראש צוות', 'attendance',
  'worker_pay_settings', 'team_lead_bonus', true, false, false, 'attendance.manage_pay', 41);
select app.register_field('worker_pay', 'shift_bonus', 'בונוס למשמרת', 'attendance',
  'worker_pay_settings', 'shift_bonus', true, false, false, 'attendance.manage_pay', 42);
select app.register_field('worker_pay', 'late_topup_forfeit_minutes', 'איבוד השלמה באיחור', 'attendance',
  'worker_pay_settings', 'late_topup_forfeit_minutes', true, false, false, 'attendance.manage_pay', 43);
select app.register_field('worker_pay', 'notes', 'הערות שכר', 'attendance',
  'worker_pay_settings', 'notes', true, false, false, 'attendance.manage_pay', 44);
select app.register_field('worker_pay', 'clock_enabled', 'שעון נוכחות פעיל', 'attendance',
  'worker_pay_settings', 'clock_enabled', false, true, false, 'attendance.manage_clock', 45);
select app.register_field('worker_pay', 'location_radius_m', 'רדיוס מיקום', 'attendance',
  'worker_pay_settings', 'location_radius_m', false, true, false, 'attendance.manage_clock', 55);
select app.register_field('worker_pay', 'early_grace_minutes', 'דקות לפני המשימה', 'attendance',
  'worker_pay_settings', 'early_grace_minutes', false, true, false, 'attendance.manage_clock', 65);
select app.register_field('worker_pay', 'allow_clock_without_shift', 'החתמה בלי משמרת', 'attendance',
  'worker_pay_settings', 'allow_clock_without_shift', false, true, false, 'attendance.manage_clock', 70);
select app.rebuild_secure_view('worker_pay_settings');

update permission_registry
   set is_dangerous = true,
       description_he = 'מיקום נדרש, רדיוס והתחלה לפני המשימה לכל עובד. אינו פותח את השכר '
                        '— אבל מי שמחזיק אותו קובע אם עובד חייב להחתים במקום. אינו נדרש '
                        'כדי להחתים שעון (לזה יש "החתמת שעון").'
 where key = 'attendance.manage_clock';

drop policy wps_select on worker_pay_settings;
create policy wps_select on worker_pay_settings for select to authenticated using (
  (select app.is_admin())
  or profile_id = (select app.profile_id())
  or ((select app.user_kind()) = 'staff' and (select app.has('attendance.view_pay')))
  or (((select app.has('portal.attendance_pay')) or (select app.has('portal.worker_settings')))
      and app.is_my_contractor_staff(profile_id)));

drop policy wps_write on worker_pay_settings;
create policy wps_insert on worker_pay_settings for insert to authenticated with check (
  (select app.is_admin())
  or ((select app.user_kind()) = 'staff' and (select app.has('attendance.manage_pay'))));
create policy wps_update on worker_pay_settings for update to authenticated
  using ((select app.is_admin())
         or ((select app.user_kind()) = 'staff' and (select app.has('attendance.manage_pay'))))
  with check ((select app.is_admin())
         or ((select app.user_kind()) = 'staff' and (select app.has('attendance.manage_pay'))));
create policy wps_delete on worker_pay_settings for delete to authenticated using (
  (select app.is_admin())
  or ((select app.user_kind()) = 'staff' and (select app.has('attendance.manage_pay'))));

-- מי רשאי לקרוא את השורה של עובד, ומי רשאי לראות בה את הכסף. שתי שאלות,
-- כי מי שמנהל שעון צריך את השורה ואסור לו לראות את התעריף.
create or replace function app.worker_settings_access(p_profile_id uuid, out o_row boolean, out o_money boolean)
language sql stable security definer set search_path = public as $$
  select
    app.is_admin()
      or p_profile_id = app.profile_id()
      or (app.user_kind() = 'staff'
          and (app.has('attendance.view_pay') or app.has('attendance.manage_pay')
               or app.has('attendance.manage_clock')))
      or ((app.has('portal.attendance_pay') or app.has('portal.worker_settings'))
          and app.is_my_contractor_staff(p_profile_id)),
    app.is_admin()
      or (p_profile_id = app.profile_id() and app.has('attendance.view_own_pay'))
      or (app.user_kind() = 'staff'
          and (app.has('attendance.view_pay') or app.has('attendance.manage_pay')))
      or ((app.has('portal.attendance_pay') or app.has('portal.worker_settings'))
          and app.is_my_contractor_staff(p_profile_id))
$$;

revoke execute on function app.worker_settings_access(uuid) from anon, public;
grant execute on function app.worker_settings_access(uuid) to authenticated;

create or replace function public.worker_settings_for(p_profile_id uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_row worker_pay_settings; v_access record; v_out jsonb;
begin
  select * into v_access from app.worker_settings_access(p_profile_id);
  if not coalesce(v_access.o_row, false) then
    raise exception 'אין לך הרשאה לצפות בהגדרות של העובד הזה' using errcode = '42501';
  end if;
  select * into v_row from worker_pay_settings where profile_id = p_profile_id;
  if v_row.profile_id is null then return null; end if;
  v_out := to_jsonb(v_row);
  if not v_access.o_money then
    v_out := v_out - array['hourly_rate', 'overtime_enabled', 'min_hours_per_shift', 'travel_paid',
                           'team_lead_bonus', 'shift_bonus', 'late_topup_forfeit_minutes', 'notes'];
  end if;
  return v_out;
end $$;

revoke execute on function public.worker_settings_for(uuid) from anon, public;
grant execute on function public.worker_settings_for(uuid) to authenticated;

comment on function public.worker_settings_for(uuid) is
  'הגדרות השכר והשעון של עובד (0214). מי שרשאי רק לשעון מקבל את השורה בלי הכסף.';

-- כתיבה של המשרד, עמודה-עמודה: כל עמודה **שמשתנה** נבדקת מול המפתח שכותב
-- אותה במרשם השדות (§6 רשם את כולן) — אותו כלל של `app.enforce_field_perms`,
-- שבודק רק את מה שזז, ולכן כרטיס ששולח את כל הטופס עובר אצל מי שמחזיק רק
-- את אחד המפתחות. שורה חדשה נמדדת מול ברירות המחדל של הטבלה. מפתח שאינו
-- עמודה נזרק — אותה הכרעה של `portal_set_worker_settings` (0103), שנשארת
-- הדרך של מנהל הקבלן.
create or replace function public.worker_settings_save(p_profile_id uuid, p_settings jsonb)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_row worker_pay_settings; v_before jsonb; v_after jsonb;
  v_key text; v_perm text; v_label text;
  v_patch jsonb := coalesce(p_settings, '{}'::jsonb) - 'profile_id' - 'created_at' - 'updated_at';
begin
  if p_profile_id is null then
    raise exception 'חסר מזהה עובד' using errcode = '22023';
  end if;
  if not (app.is_admin() or app.user_kind() = 'staff') then
    raise exception 'אין לך הרשאה להגדיר את העובד הזה' using errcode = '42501';
  end if;
  if not exists (select 1 from profiles where id = p_profile_id and deleted_at is null) then
    raise exception 'העובד לא נמצא' using errcode = '22023';
  end if;

  select * into v_row from worker_pay_settings where profile_id = p_profile_id;
  if v_row.profile_id is null then
    v_row.overtime_enabled := true;
    v_row.travel_paid      := true;
  end if;
  v_before := to_jsonb(v_row);
  v_row := jsonb_populate_record(v_row, v_patch);
  v_row.profile_id := p_profile_id;
  v_after := to_jsonb(v_row);

  for v_key in select jsonb_object_keys(v_patch) loop
    select edit_permission_key, label_he into v_perm, v_label from field_registry
     where table_name = 'worker_pay_settings' and column_name = v_key;
    if not found then
      raise exception 'שדה לא מוכר: %', v_key using errcode = '22023';
    end if;
    continue when v_after -> v_key is not distinct from v_before -> v_key;
    if not (app.is_admin() or app.has(coalesce(v_perm, 'attendance.manage_pay'))) then
      raise exception 'אין לך הרשאה לשנות את השדה "%"', v_label using errcode = '42501';
    end if;
  end loop;

  perform app.system_write(true);
  insert into worker_pay_settings (
    profile_id, hourly_rate, overtime_enabled, min_hours_per_shift, travel_paid,
    team_lead_bonus, shift_bonus, late_topup_forfeit_minutes,
    clock_enabled, requires_location, location_radius_m,
    allow_early_clock_in, early_grace_minutes, allow_clock_without_shift, notes)
  values (
    v_row.profile_id, v_row.hourly_rate, v_row.overtime_enabled, v_row.min_hours_per_shift,
    v_row.travel_paid, v_row.team_lead_bonus, v_row.shift_bonus, v_row.late_topup_forfeit_minutes,
    v_row.clock_enabled, v_row.requires_location, v_row.location_radius_m,
    v_row.allow_early_clock_in, v_row.early_grace_minutes, v_row.allow_clock_without_shift, v_row.notes)
  on conflict (profile_id) do update set
    hourly_rate               = excluded.hourly_rate,
    overtime_enabled          = excluded.overtime_enabled,
    min_hours_per_shift       = excluded.min_hours_per_shift,
    travel_paid               = excluded.travel_paid,
    team_lead_bonus           = excluded.team_lead_bonus,
    shift_bonus               = excluded.shift_bonus,
    late_topup_forfeit_minutes = excluded.late_topup_forfeit_minutes,
    clock_enabled             = excluded.clock_enabled,
    requires_location         = excluded.requires_location,
    location_radius_m         = excluded.location_radius_m,
    allow_early_clock_in      = excluded.allow_early_clock_in,
    early_grace_minutes       = excluded.early_grace_minutes,
    allow_clock_without_shift = excluded.allow_clock_without_shift,
    notes                     = excluded.notes;
  perform app.system_write(false);
end $$;

revoke execute on function public.worker_settings_save(uuid, jsonb) from anon, public;
grant execute on function public.worker_settings_save(uuid, jsonb) to authenticated;

comment on function public.worker_settings_save(uuid, jsonb) is
  'כתיבת הגדרות שכר ושעון של עובד ע"י המשרד (0214): כל עמודה נבדקת מול המפתח שכותב '
  'אותה במרשם השדות — כסף תחת attendance.manage_pay, שעון תחת attendance.manage_clock.';

-- ===== 7. מי מחזיק איזו הרשאה — רק בתוך הארגון של הקורא ===================
--
-- ארבע טבלאות המטא-דאטה של ההרשאות (0010) נפתחו לקריאה לכל מי שמחזיק
-- `users.view` — מפתח שחל גם על משתמש לקוח. מנהל לקוח עם המפתח היה קורא את
-- התפקידים, ההענקות וההיקפים של כל משתמש במערכת. הקריאה נגדרת עכשיו לצוות,
-- או לאנשים שהקורא רשאי לנהל (`app.can_manage_profile`: אצל לקוח — אנשי
-- הלקוח שלו בלבד). פוליסות הכתיבה שהיו `for all` מתפצלות, כדי שלא יפתחו
-- בעצמן את הקריאה שנסגרה כאן.

drop policy profile_roles_read on profile_roles;
create policy profile_roles_read on profile_roles for select to authenticated using (
  (select app.is_admin()) or profile_id = (select app.profile_id())
  or ((select app.user_kind()) = 'staff' and (select app.has('users.view')))
  or app.can_manage_profile(profile_id));

drop policy user_grants_read on user_permission_grants;
create policy user_grants_read on user_permission_grants for select to authenticated using (
  (select app.is_admin()) or profile_id = (select app.profile_id())
  or ((select app.user_kind()) = 'staff' and (select app.has('users.view')))
  or app.can_manage_profile(profile_id));

drop policy permission_scopes_read on permission_scopes;
create policy permission_scopes_read on permission_scopes for select to authenticated using (
  (select app.is_admin()) or profile_id = (select app.profile_id())
  or ((select app.user_kind()) = 'staff' and (select app.has('users.view')))
  or (profile_id is not null and app.can_manage_profile(profile_id))
  -- שורות של תפקיד הן הגדרת הארגון ולא נתון של אדם, ונקראות כמו
  -- ‏`role_permissions` (‏`role_permissions_read`) — מסך ההיקפים מציג אותן
  -- כ"מהתפקיד" לצד ההיקף האישי.
  or (role_id is not null
      and ((select app.has('users.view')) or (select app.has('settings.permissions'))
           or role_id = any ((select app.my_role_ids())::uuid[]))));

drop policy fp_read on field_permissions;
create policy fp_read on field_permissions for select to authenticated using (
  (select app.is_admin()) or profile_id = (select app.profile_id())
  or ((select app.user_kind()) = 'staff' and (select app.has('users.view')))
  or (profile_id is not null and app.can_manage_profile(profile_id)));

drop policy profile_roles_write on profile_roles;
create policy profile_roles_insert on profile_roles for insert to authenticated with check (
  (select app.is_admin()) or (app.has('users.manage_permissions') and app.can_manage_profile(profile_id)));
create policy profile_roles_update on profile_roles for update to authenticated
  using ((select app.is_admin()) or (app.has('users.manage_permissions') and app.can_manage_profile(profile_id)))
  with check ((select app.is_admin()) or (app.has('users.manage_permissions') and app.can_manage_profile(profile_id)));
create policy profile_roles_delete on profile_roles for delete to authenticated using (
  (select app.is_admin()) or (app.has('users.manage_permissions') and app.can_manage_profile(profile_id)));

drop policy user_grants_write on user_permission_grants;
create policy user_grants_insert on user_permission_grants for insert to authenticated with check (
  (select app.is_admin()) or (app.has('users.manage_permissions') and app.can_manage_profile(profile_id)));
create policy user_grants_update on user_permission_grants for update to authenticated
  using ((select app.is_admin()) or (app.has('users.manage_permissions') and app.can_manage_profile(profile_id)))
  with check ((select app.is_admin()) or (app.has('users.manage_permissions') and app.can_manage_profile(profile_id)));
create policy user_grants_delete on user_permission_grants for delete to authenticated using (
  (select app.is_admin()) or (app.has('users.manage_permissions') and app.can_manage_profile(profile_id)));

drop policy permission_scopes_write on permission_scopes;
create policy permission_scopes_insert on permission_scopes for insert to authenticated with check (
  (select app.is_admin())
  or (app.has('users.manage_scopes') and profile_id is not null and app.can_manage_profile(profile_id)));
create policy permission_scopes_update on permission_scopes for update to authenticated
  using ((select app.is_admin())
         or (app.has('users.manage_scopes') and profile_id is not null and app.can_manage_profile(profile_id)))
  with check ((select app.is_admin())
         or (app.has('users.manage_scopes') and profile_id is not null and app.can_manage_profile(profile_id)));
create policy permission_scopes_delete on permission_scopes for delete to authenticated using (
  (select app.is_admin())
  or (app.has('users.manage_scopes') and profile_id is not null and app.can_manage_profile(profile_id)));

drop policy fp_write on field_permissions;
create policy fp_insert on field_permissions for insert to authenticated with check (
  (select app.is_admin())
  or (app.has('users.manage_permissions') and profile_id is not null and app.can_manage_profile(profile_id)));
create policy fp_update on field_permissions for update to authenticated
  using ((select app.is_admin())
         or (app.has('users.manage_permissions') and profile_id is not null and app.can_manage_profile(profile_id)))
  with check ((select app.is_admin())
         or (app.has('users.manage_permissions') and profile_id is not null and app.can_manage_profile(profile_id)));
create policy fp_delete on field_permissions for delete to authenticated using (
  (select app.is_admin())
  or (app.has('users.manage_permissions') and profile_id is not null and app.can_manage_profile(profile_id)));

-- ===== 8. סכומי ההזמנה מ-ViperFlow אינם חלק מ"האירוע נפתח לי" ==============
--
-- ‏`viperflow_links.order_snapshot` (0190) נושא את מה שההזמנה אמרה — כולל
-- ההובלה, הצוות, ההנחה וסכומי הריהוט — והפוליסה (0176) פותחת את השורה לכל
-- מי שהאירוע נפתח לו: עובד שטח, עובד קבלן. המסך קורא `viperflow_event_link`,
-- שאינו כולל את העמודה, ושום פונקציית invoker אינה קוראת אותה — רק המתרגם,
-- שהוא `security definer`. לכן העמודה נסגרת ברמת ההרשאה של Postgres, וכל
-- השאר נשאר כפי שהיה.

revoke select on table viperflow_links from authenticated, anon;
grant select (event_id, connection_id, order_id, order_number, order_status, order_updated_at,
              last_event_id, last_synced_at, created_at, truck_quantity, worker_quantity,
              sync_locked_at, sync_locked_by)
   on table viperflow_links to authenticated;

-- ===== 9. פונקציות `security definer` שענו על יותר ממה שהקורא רשאי =========
--
-- פונקציה כזו עוקפת RLS, ולכן הגדר שלה הוא כל הגדר. הסריקה עברה על כל אחת
-- שמשתמש מחובר רשאי להריץ; אלה שנמצאו פתוחות מדי:

-- (א) ‏`zone_for_location` (0017) — השער היחיד היה `pricing.view`, שמנהל לקוח
-- מחזיק, והלקוח שעליו נשאלה השאלה הגיע מהארגומנט. כך משתמש של לקוח אחד יכול
-- היה לשחזר את אזורי התמחור של לקוח אחר (שעות נסיעה ותוספת בשקלים). המסך כבר
-- אינו קורא לה; היא נשארת לצוות, באותו גדר של `pz_select`.
create or replace function public.zone_for_location(p_customer_id uuid, p_lat double precision, p_lng double precision)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare z pricing_zones;
begin
  if not (app.is_admin()
          or (app.user_kind() = 'staff'
              and (app.has('pricing.manage_rules') or app.has('pricing.view')
                   or app.has('attendance.manage_warehouses')))) then
    raise exception 'אין לך הרשאה לצפות באזורי התמחור' using errcode = '42501';
  end if;
  z := app.zone_for_point(p_customer_id, p_lat, p_lng);
  if z.id is null then return null; end if;
  return jsonb_build_object(
    'id', z.id, 'name', z.name, 'color', z.color,
    'travel_hours', z.travel_hours, 'surcharge', z.surcharge);
end $$;

revoke execute on function public.zone_for_location(uuid, double precision, double precision) from anon, public;
grant execute on function public.zone_for_location(uuid, double precision, double precision) to authenticated;

-- (ב) ‏`shift_task_breakdown` (0201) מחזירה את פרטי המשימות שמזהיהן נשלחו
-- אליה, ושאלה רק אם הן בשיבוץ של העובד — לא אם הן פורסמו. המזהה של טיוטה מגיע
-- לעובד בערוץ הסנכרון שלו (0101), ומכאן שם הלקוח, לקוח הקצה, המיקום, השעות
-- והצוות של משימה שעוד לא פורסמה. הגוף זהה ל-0201 פרט לסינון שאחרי `v_ids`.
create or replace function public.shift_task_breakdown(p_profile_id uuid, p_task_ids uuid[])
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_ids      uuid[];
  v_staffing boolean;
  v_name     text;
  v_tasks    jsonb;
  v_last     jsonb;
  v_travel   numeric;
  v_work     numeric;
  v_sum      numeric;
begin
  if p_profile_id = app.profile_id() then
    perform app.require('attendance.view_schedule');
  elsif app.user_kind() = 'contractor_user' then
    if not (app.has('portal.attendance') and app.is_my_contractor_staff(p_profile_id)) then
      raise exception 'אין לך הרשאה לצפות במשמרות של עובד זה' using errcode = '42501';
    end if;
  else
    perform app.require('attendance.view_all');
  end if;

  select array_agg(distinct u) into v_ids
    from unnest(coalesce(p_task_ids, '{}'::uuid[])) u;

  -- ‏0214: טיוטה אינה חלק מהמשמרת של איש עד שהיא מתפרסמת — אותו כלל של
  -- ‏`tasks_select` ושל `my_shifts`. מי שמתכנן משימות רואה גם טיוטות, וכך גם
  -- משימה שכבר נרשמה בנוכחות של העובד (היא היסטוריה, לא תכנון).
  if not (app.is_admin() or app.can_plan_tasks()) then
    select array_agg(u) into v_ids
      from unnest(v_ids) u
     where exists (select 1 from tasks t
                    where t.id = u
                      and t.status_id = (select s.id from statuses s
                                          where s.entity = 'task' and s.code = 'assigned'
                                            and s.deleted_at is null limit 1))
        or exists (select 1 from attendance_entries ae
                    where ae.profile_id = p_profile_id and ae.deleted_at is null
                      and u = any (ae.task_ids));
  end if;

  select p.full_name into v_name from profiles p where p.id = p_profile_id;

  if v_ids is null then
    return jsonb_build_object(
      'profile_id', p_profile_id, 'full_name', v_name,
      'tasks', '[]'::jsonb,
      'totals', jsonb_build_object('tasks', 0, 'work_hours', 0,
                                   'travel_hours', 0, 'idle_minutes', 0,
                                   'overlap_hours', 0),
      'shift', jsonb_build_object('start', null, 'end', null,
                                  'work_site', null, 'warehouse_name', null,
                                  'end_work_site', null, 'end_warehouse_name', null));
  end if;

  v_staffing := app.is_admin() or app.has('board.view_staffing');

  with mine as (
    select a.task_id as tid,
           bool_or(a.work_site = 'warehouse') as is_wh,
           (array_agg(a.truck_id) filter (where a.truck_id is not null))[1] as my_truck
      from task_assignments a
     where a.profile_id = p_profile_id and a.task_id = any(v_ids)
     group by a.task_id
    union all
    select w.task_id, bool_or(w.work_site = 'warehouse'), null::uuid
      from task_contractor_workers w
      join profiles pr on pr.contractor_worker_id = w.contractor_worker_id
     where pr.id = p_profile_id and w.task_id = any(v_ids)
     group by w.task_id
  ),
  d as (
    select m.tid, bool_or(m.is_wh) as is_wh,
           (array_agg(m.my_truck) filter (where m.my_truck is not null))[1] as my_truck
      from mine m group by m.tid
  ),
  enriched as (
    select
      t.id as task_id,
      d.is_wh,
      -- ‏0094: כל התפקידים של האדם במשימה, מסודרים ראש צוות > נהג > עובד.
      (select array_agg(s.r order by s.pr) from (
         select distinct a.role::text as r,
                case a.role when 'team_lead' then 0 when 'driver' then 1 else 2 end as pr
           from task_assignments a
          where a.task_id = t.id and a.profile_id = p_profile_id) s) as my_roles,
      coalesce(nullif(t.title, ''), tt.name) as title,
      tt.name as type_name, tt.code as type_code,
      t.customer_id, c.name as cust_name, c.color as cust_color,
      t.event_id, e.event_number, e.end_client_name,
      coalesce(nullif(t.location_text, ''), e.location_text) as location_text,
      e.location_lat, e.location_lng,
      t.hours_count, t.worker_count, t.notes,
      st.name as status_name, st.color as status_color,
      coalesce(tr.name, nullif(t.truck_free_text, '')) as truck_name,
      tlist.list as truck_list,
      em.name as method_name,
      wh.id as wh_id, wh.name as wh_name,
      coalesce(app.task_travel_hours(t.id), 0) as travel,
      -- ‏0163: היציאה מהמחסן שקודמת לעבודה בשטח היא של הערב שלפני.
      case when d.is_wh and t.warehouse_start_time is not null
           then app.warehouse_start_at(t.task_date, t.warehouse_start_time,
                                       t.onsite_start_time)
      end as wh_start_at,
      ((t.task_date + coalesce(t.onsite_start_time, t.warehouse_start_time))
        at time zone 'Asia/Jerusalem') as start_at,
      ((t.task_date + coalesce(t.onsite_start_time, t.warehouse_start_time))
        at time zone 'Asia/Jerusalem') as onsite_at,
      ((t.task_date + coalesce(t.onsite_start_time, t.warehouse_start_time))
        at time zone 'Asia/Jerusalem')
        + make_interval(mins => round(coalesce(t.hours_count, 0) * 60)::int) as end_at,
      case when app.can_view_field('event', 'contact_phone')
                or app.is_event_team_lead(t.event_id)
           then ec.contact_name end as contact_name,
      case when app.can_view_field('event', 'contact_phone')
                or app.is_event_team_lead(t.event_id)
           then ec.contact_phone end as contact_phone,
      -- ‏0201: אנשים, ולא שורות. ראש צוות שנוהג ועובד ששובץ גם כנהג — אחד.
      (select count(distinct x.profile_id) from task_assignments x where x.task_id = t.id)
        + (select count(*) from task_contractor_workers x where x.task_id = t.id)
        + (select count(*) from task_customer_workers x where x.task_id = t.id)
        as assigned_count,
      case when v_staffing then (
        select jsonb_agg(q.o order by q.o ->> 'name', q.o ->> 'key') from (
          select jsonb_build_object(
                   'key',       's:' || a2.profile_id,
                   'kind',      'staff',
                   'name',      min(p2.full_name),
                   'work_site', case when bool_or(a2.work_site = 'warehouse')
                                     then 'warehouse' else 'field' end) as o
            from task_assignments a2 join profiles p2 on p2.id = a2.profile_id
           where a2.task_id = t.id
           group by a2.profile_id
          union all
          select jsonb_build_object('key', 'c:' || cw.id, 'kind', 'contractor',
                                    'name', cw.full_name, 'work_site', w2.work_site)
            from task_contractor_workers w2
            join contractor_workers cw on cw.id = w2.contractor_worker_id
           where w2.task_id = t.id
          union all
          select jsonb_build_object('key', 'o:' || cuw.id, 'kind', 'customer',
                                    'name', cuw.full_name, 'work_site', w3.work_site)
            from task_customer_workers w3
            join customer_workers cuw on cuw.id = w3.customer_worker_id
           where w3.task_id = t.id) q) end as team
    from d
    join tasks t on t.id = d.tid and t.deleted_at is null
    join task_types tt on tt.id = t.task_type_id
    left join events e on e.id = t.event_id
    left join event_contacts ec on ec.event_id = t.event_id
    left join customers c on c.id = t.customer_id
    left join statuses st on st.id = t.status_id
    left join trucks tr on tr.id = coalesce(d.my_truck, t.truck_id)
    left join execution_methods em on em.id = t.execution_method_id
    left join warehouses wh on wh.id = coalesce(t.warehouse_id, c.warehouse_id)
                           and wh.deleted_at is null
    left join lateral (
      select jsonb_agg(jsonb_build_object('id', tr3.id, 'name', tr3.name) order by u.ord) as list
        from unnest(t.truck_ids) with ordinality as u(truck_id, ord)
        join trucks tr3 on tr3.id = u.truck_id
    ) tlist on true
  ),
  numbered as (
    select x.*,
           row_number() over (order by x.start_at, x.task_id) as ord,
           -- ‏0166: המאוחר מבין הסיומים שקדמו, ולא הסיום של הקודמת. משימה
           -- שנבלעת בתוך אחת ארוכה ממנה אינה "אחריה".
           max(x.end_at) over (order by x.start_at, x.task_id
                               rows between unbounded preceding and 1 preceding) as prev_end
      from enriched x
  ),
  -- החלונות מאוחדים לאיים: איי הזמן שבהם באמת עובדים. אי חדש נפתח כשמשימה
  -- מתחילה אחרי שכל מה שלפניה כבר נגמר, וכל השאר מתמזג לתוך מה שפתוח.
  islands as (
    select n.*,
           sum(case when n.prev_end is null or n.start_at > n.prev_end then 1 else 0 end)
             over (order by n.ord rows between unbounded preceding and current row) as grp
      from numbered n
  ),
  merged as (
    select i.grp, min(i.start_at) as s, max(i.end_at) as e
      from islands i group by i.grp
  )
  select jsonb_agg(jsonb_build_object(
           'task_id',               n.task_id,
           'ord',                   n.ord,
           'title',                 n.title,
           'task_type_name',        n.type_name,
           'task_type_code',        n.type_code,
           'customer_id',           n.customer_id,
           'customer_name',         n.cust_name,
           'customer_color',        n.cust_color,
           'event_id',              n.event_id,
           'event_number',          n.event_number,
           'end_client_name',       n.end_client_name,
           'contact_name',          n.contact_name,
           'contact_phone',         n.contact_phone,
           'location_text',         n.location_text,
           'location_lat',          n.location_lat,
           'location_lng',          n.location_lng,
           'work_site',             case when n.is_wh then 'warehouse' else 'field' end,
           'warehouse_id',          n.wh_id,
           'warehouse_name',        n.wh_name,
           'warehouse_start_at',    n.wh_start_at,
           'start_at',              n.start_at,
           'onsite_start_at',       n.onsite_at,
           'end_at',                n.end_at,
           'hours_count',           n.hours_count,
           'travel_hours',          n.travel,
           'gap_minutes',           case when n.prev_end is null then null
                                    else greatest(0, round(extract(epoch
                                           from (n.start_at - n.prev_end)) / 60))::int end,
           'overlap_minutes',       case when n.prev_end is null then 0
                                    else greatest(0, round(extract(epoch
                                           from (least(n.end_at, n.prev_end) - n.start_at))
                                           / 60))::int end,
           'status_name',           n.status_name,
           'status_color',          n.status_color,
           'truck_name',            n.truck_name,
           'truck_list',            n.truck_list,
           'execution_method_name', n.method_name,
           'my_role',               n.my_roles,
           'worker_count',          n.worker_count,
           'assigned_count',        n.assigned_count,
           'team',                  n.team,
           'notes',                 n.notes)
         order by n.ord),
         (select round((coalesce(sum(extract(epoch from (m.e - m.s))), 0) / 3600.0)::numeric, 2)
            from merged m)
    into v_tasks, v_work
    from islands n;

  if coalesce(jsonb_array_length(v_tasks), 0) <> cardinality(v_ids) then
    raise exception 'אחת המשימות אינה שייכת למשמרת של עובד זה' using errcode = '42501';
  end if;

  select r into v_last
    from jsonb_array_elements(v_tasks) r
   order by (r ->> 'end_at')::timestamptz desc, (r ->> 'task_id') desc
   limit 1;

  v_travel := case when v_last ->> 'work_site' = 'warehouse'
                   then coalesce((v_last ->> 'travel_hours')::numeric, 0)
                   else 0 end;

  select round(coalesce(sum((r ->> 'hours_count')::numeric), 0), 2) into v_sum
    from jsonb_array_elements(v_tasks) r;

  return jsonb_build_object(
    'profile_id', p_profile_id,
    'full_name',  v_name,
    'tasks',      v_tasks,
    'totals', jsonb_build_object(
      'tasks', jsonb_array_length(v_tasks),
      'work_hours', v_work,
      'overlap_hours', greatest(0, round(v_sum - v_work, 2)),
      'travel_hours', v_travel,
      'idle_minutes', (select coalesce(sum((r ->> 'gap_minutes')::int), 0)
                         from jsonb_array_elements(v_tasks) r)),
    'shift', jsonb_build_object(
      'start', (select min(least((r ->> 'warehouse_start_at')::timestamptz,
                                 (r ->> 'start_at')::timestamptz))
                  from jsonb_array_elements(v_tasks) r),
      'end',   (select max((r ->> 'end_at')::timestamptz) from jsonb_array_elements(v_tasks) r)
                 + make_interval(mins => round(v_travel * 60)::int),
      'work_site',      v_tasks -> 0 ->> 'work_site',
      'warehouse_name', v_tasks -> 0 ->> 'warehouse_name',
      'end_work_site',      v_last ->> 'work_site',
      'end_warehouse_name', case when v_last ->> 'work_site' = 'warehouse'
                                 then v_last ->> 'warehouse_name' end));
end $$;

-- (ג) ‏`set_event_approved` (0110) שולחת "האירוע אושר לביצוע" לכל משתמשי
-- הלקוח — גם לעובד בסגל הלקוח שרואה רק את מה ששובץ אליו (0178), עם שם האירוע
-- ותאריכו בגוף ההתראה. הנמענים הם עכשיו מי שהאירוע באמת נפתח לו: מי שמחזיק
-- `events.view` בלי היקף `own` על אירועים, או מי ששובץ לאירוע.

-- התפקידים שבתוקף לפרופיל נתון — ‏`app.my_role_ids()` של מישהו אחר. אותם
-- כללים בדיוק (0067, 0104), כדי שהשאלה "מה הוא רואה" תיענה כמו אצלו.
create or replace function app.role_ids_of(p_profile uuid) returns uuid[]
language sql stable security definer set search_path = public as $$
  with mine as (
    select r.id, r.key
      from profiles p
      join profile_roles pr on pr.profile_id = p.id
      join permission_roles r on r.id = pr.role_id
     where p.id = p_profile and r.is_active and r.deleted_at is null
       and (r.user_kind is null or r.user_kind = p.user_kind)
  )
  select coalesce(array_agg(id), '{}'::uuid[])
    from mine
   where key <> 'contractor_worker'
      or not exists (select 1 from mine m2 where m2.key in ('contractor_manager', 'staff_contractor'))
$$;

-- "רק מה שמשויך אליו" של פרופיל נתון על מודול — ההכרעה של `app.scope_rows`
-- (§2) למישהו אחר: "ללא הגבלה" אישית מבטלת; אחרת שורת `own` אישית או של
-- אחד התפקידים.
create or replace function app.profile_scope_own(p_profile uuid, p_resource text) returns boolean
language sql stable security definer set search_path = public as $$
  select not exists (select 1 from permission_scopes s
                      where s.profile_id = p_profile and s.resource = p_resource
                        and s.scope_type = 'all')
     and (exists (select 1 from permission_scopes s
                   where s.profile_id = p_profile and s.resource = p_resource
                     and s.scope_type = 'own')
          or exists (select 1 from permission_scopes s
                      where s.role_id = any (app.role_ids_of(p_profile))
                        and s.resource = p_resource and s.scope_type = 'own'))
$$;

revoke execute on function app.role_ids_of(uuid) from anon, public;
revoke execute on function app.profile_scope_own(uuid, text) from anon, public;

create or replace function public.set_event_approved(p_event_id uuid, p_on boolean default true)
returns timestamptz language plpgsql security definer set search_path = public as $$
declare
  v_at    timestamptz;
  v_event events;
  v_label text;
  r       record;
begin
  if not app.is_admin() then
    raise exception 'אישור אירוע לביצוע שמור למנהל המערכת' using errcode = '42501';
  end if;
  select * into v_event from events where id = p_event_id and deleted_at is null;
  if v_event.id is null then
    raise exception 'האירוע לא נמצא' using errcode = '42501';
  end if;

  v_at := case when p_on then now() end;
  perform app.system_write(true);
  update events
     set approved_at = v_at,
         approved_by = case when p_on then app.profile_id() end
   where id = p_event_id;
  perform app.system_write(false);

  if p_on and v_event.approved_at is null
     and app.notification_in_scope('event_approved', 'customer', v_event.customer_id) then
    v_label := coalesce(v_event.end_client_name, v_event.event_number,
                        to_char(v_event.event_date, 'DD/MM/YYYY'));
    for r in select p.id from profiles p
      where p.customer_id = v_event.customer_id
        and p.user_kind = 'customer_user'
        and p.is_active and p.deleted_at is null
        and p.id is distinct from app.profile_id()
        -- ‏0214: רק מי שהאירוע נפתח לו.
        and ((p.id in (select app.profiles_with('events.view'))
              and not app.profile_scope_own(p.id, 'events'))
             or exists (select 1 from tasks t
                          join task_customer_workers w on w.task_id = t.id
                          join customer_workers cuw on cuw.id = w.customer_worker_id
                         where t.event_id = v_event.id and t.deleted_at is null
                           and cuw.customer_id = v_event.customer_id
                           and p.customer_worker_id = w.customer_worker_id))
    loop
      perform app.notify(r.id, 'event_approved', 'האירוע אושר לביצוע',
        v_label || ' — ' || to_char(v_event.event_date, 'DD/MM/YYYY'), 'event', v_event.id);
    end loop;
  end if;

  return v_at;
end $$;

revoke execute on function public.set_event_approved(uuid, boolean) from anon, public;
grant execute on function public.set_event_approved(uuid, boolean) to authenticated;

-- (ד) ‏`event_quotes_insert/update` (0170) לא שאלו על סוג המשתמש, והמפתח
-- הגיע למנהלי לקוח בירושה (§1 סוגר את זה בשורש). ההצעה יוצאת בשם וייפר — צד
-- ולא הרשאה — ולכן הגדר נאמר גם בפוליסה, כמו ב-`event_quotes_select`.
drop policy event_quotes_insert on event_quotes;
create policy event_quotes_insert on event_quotes for insert to authenticated with check (
  ((select app.is_admin())
   or ((select app.user_kind()) = 'staff' and (select app.has('events.quote_send'))))
  and exists (select 1 from events e where e.id = event_quotes.event_id));

drop policy event_quotes_update on event_quotes;
create policy event_quotes_update on event_quotes for update to authenticated
  using (((select app.is_admin())
          or ((select app.user_kind()) = 'staff' and (select app.has('events.quote_send'))))
         and exists (select 1 from events e where e.id = event_quotes.event_id))
  with check (((select app.is_admin())
          or ((select app.user_kind()) = 'staff' and (select app.has('events.quote_send'))))
         and exists (select 1 from events e where e.id = event_quotes.event_id));

-- (ה) קבצי המפרט (0077/0113): ‏`events.specs_upload` פתוח לקהל הלקוחות, ושער
-- הכתיבה היה אחד ל-insert, ‏update ו-delete. כל משתמש לקוח — גם "צופה" — יכול
-- היה לדרוס או למחוק קובץ שהמשרד העלה, מעל לגרסאות הנעולות של
-- ‏`event_specs`. מעכשיו: קובץ שגרסה כבר מצביעה עליו נכתב ונמחק רק בידי מי
-- שמנהל מפרטים; מי שמעלה כותב רק נתיב חדש, ומוחק רק את מה שהעלה ונדחה
-- (הניקוי של `uploadSpec`). שער הקריאה לא זז: שירות האחסון בודק העלאה
-- בהכנסה שנקראת חזרה תחת אותה פוליסה, לפני ששורת הגרסה קיימת.

-- "גרסה כבר מצביעה על הנתיב" — בלי ה-RLS של הקורא, כדי שגרסה שהוסרה (ולכן
-- מוסתרת ממנו) תגן על הקובץ שלה בדיוק כמו גרסה חיה.
create or replace function app.spec_path_referenced(p_name text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from event_specs s where s.storage_path = p_name)
$$;

revoke execute on function app.spec_path_referenced(text) from anon, public;
grant execute on function app.spec_path_referenced(text) to authenticated;

create or replace function app.may_touch_event_spec(p_name text, p_write boolean)
returns boolean language plpgsql stable set search_path = public as $$
declare v_event uuid;
begin
  -- הנתיב הוא החוזה. כל דבר שאינו '<uuid>/...' בדלי הזה אינו שלנו, ואינו נפתח.
  begin
    v_event := split_part(p_name, '/', 1)::uuid;
  exception when others then
    return false;
  end;

  if not app.is_admin() then
    if p_write and not app.has('events.specs_upload') then return false; end if;
    if not p_write and not app.has('events.specs_view') then return false; end if;
    -- ‏0214: קובץ של גרסה קיימת — רק מי שמנהל מפרטים.
    if p_write and not app.has('events.specs_manage') and app.spec_path_referenced(p_name) then
      return false;
    end if;
  end if;

  return exists (select 1 from events e where e.id = v_event);
end $$;

comment on function app.may_touch_event_spec(text, boolean) is
  'השער היחיד לדלי event-specs (0077, 0113, 0214). קריאה: events.specs_view; כתיבה: '
  'events.specs_upload — ולקובץ שגרסה כבר מצביעה עליו רק events.specs_manage. שניהם '
  'באירוע שנפתח לקורא.';

-- (ו) שלוש טבלאות התצורה של לקוח — שדות הלוח, שדות הטופס ואופני הביצוע —
-- נקראו ב-`using (true)`, ולכן כל משתמש יכול היה למנות את כל הלקוחות במערכת
-- ואת התצורה של כל אחד. הצוות ממשיך לקרוא הכול; לקוח — את שלו; קבלן אינו
-- צריך אף אחת (התצורה היא של קהל הלקוח, 0109).
drop policy cbf_read on customer_board_fields;
create policy cbf_read on customer_board_fields for select to authenticated using (
  (select app.is_admin()) or (select app.user_kind()) = 'staff'
  or customer_id = (select app.customer_id()));

drop policy customer_form_fields_read on customer_form_fields;
create policy customer_form_fields_read on customer_form_fields for select to authenticated using (
  (select app.is_admin()) or (select app.user_kind()) = 'staff'
  or customer_id = (select app.customer_id()));

drop policy customer_execution_methods_read on customer_execution_methods;
create policy customer_execution_methods_read on customer_execution_methods for select to authenticated using (
  (select app.is_admin()) or (select app.user_kind()) = 'staff'
  or customer_id = (select app.customer_id()));

-- (ז) תפקידי עובד הקבלן (`contractor_worker_roles`) נכתבו בידי כל משתמש של
-- אותו קבלן, בלי מפתח — גם בידי עובד. הכתיבה היא ניהול סגל, ולכן היא הולכת
-- אחרי אותו מפתח של `cw_own_insert`/`cw_own_update`.
drop policy cwr_own_write on contractor_worker_roles;
create policy cwr_own_insert on contractor_worker_roles for insert to authenticated with check (
  (select app.has('portal.manage_workers'))
  and exists (select 1 from contractor_workers w
               where w.id = contractor_worker_roles.contractor_worker_id
                 and w.contractor_id = (select app.contractor_id())));
create policy cwr_own_update on contractor_worker_roles for update to authenticated
  using ((select app.has('portal.manage_workers'))
         and exists (select 1 from contractor_workers w
                      where w.id = contractor_worker_roles.contractor_worker_id
                        and w.contractor_id = (select app.contractor_id())))
  with check ((select app.has('portal.manage_workers'))
         and exists (select 1 from contractor_workers w
                      where w.id = contractor_worker_roles.contractor_worker_id
                        and w.contractor_id = (select app.contractor_id())));
create policy cwr_own_delete on contractor_worker_roles for delete to authenticated using (
  (select app.has('portal.manage_workers'))
  and exists (select 1 from contractor_workers w
               where w.id = contractor_worker_roles.contractor_worker_id
                 and w.contractor_id = (select app.contractor_id())));
