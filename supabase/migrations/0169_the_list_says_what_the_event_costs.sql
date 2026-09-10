-- ‏0169: רשימת האירועים אומרת כמה האירוע עולה
--
-- ‏"בדף אירועים יש עמודה שבה רשום סכום הריהוט. שיהיה רשום שם המחיר של כל
-- המשימות ביחד, והכותרת תהיה מחיר."
--
-- העמודה שהמשרד הצביע עליה היא **שדה של לקוח** — ‏`form_fields` פר-לקוח,
-- מספר שמישהו הקליד בטופס — ולא הכסף שהמערכת חישבה. המספר שהוא ביקש כבר
-- קיים, אבל רק בדף האירוע: כרטיס "סך תמחור" מסכם שם את `task_pricing.price`
-- של כל משימות האירוע ומוסיף עליו את תוספות המחיר (0113). הרשימה לא ידעה
-- לומר אותו על שורה, כי היא נשלפת מ-`events` ומשם אין דרך אל המשימות.
--
-- **פונקציה שמקבלת מזהים, ולא עמודה ב-`events`.** סכום נגזר שנשמר על השורה
-- הוא סכום שצריך לתחזק בכל שינוי תמחור, בכל תוספת ובכל מחיקה רכה של משימה —
-- ‏0113 ו-0155 היו נוגעות בו שתיהן. הרשימה שואלת על מה שהיא הציגה בפועל
-- (עד 200 שורות), ומקבלת שורה לכל אירוע שיש לו משימות.
--
-- ‏`p_event_ids` ולא סינון שמשוכפל כאן: לרשימה יש חיפוש, סינון לפי לקוח,
-- ומתג "אירועים שבוטלו". שכפול שלושתם בשרת היה מקום שני שבו הם יכולים
-- להיפרד זה מזה. הקריאה היא RPC (POST) ולכן המערך אינו עובר ב-query string,
-- ומאתיים מזהים אינם מתקרבים לגבול של שורת בקשה.
--
-- **‏`security invoker` — וזו ההכרעה שמחזיקה את ההרשאות כאן.** ‏`customer_price`
-- ב-`work_board_view` ממוסך למי שאין לו `pricing.view` (הוא חוזר `null`),
-- ו-`tpa_select` דורשת את אותו מפתח בדיוק מהתוספות. הפונקציה אינה מוסיפה
-- פרדיקט משלה ואינה יכולה לעקוף אף אחד מהשניים: קורא בלי המפתח מקבל שורה
-- בלי סכום, בדיוק כפי שהוא מקבל בדף האירוע. ‏RLS על `tasks` היא שמכריעה
-- אילו אירועים בכלל מחזירים שורה.
--
-- ‏(ראו האזהרה ב-README על `public` invoker שקורא לעוזר ב-`app`: כל העוזרים
-- שהתצוגה נשענת עליהם — `app.has`, `app.can_view_field`, `app.contractor_id`
-- — כבר מורצים על ידי `authenticated` בכל קריאה ישירה ל-`work_board_view`
-- מהדפדפן, ולכן אין כאן ACL חדש להעניק.)

create or replace function event_task_totals(p_event_ids uuid[])
returns table (
  event_id     uuid,
  price_total  numeric,
  priced_tasks integer,
  task_count   integer)
language sql stable set search_path = public as $$
  select v.event_id,
         /* ‏`null` ולא `0`: אירוע שאיש עוד לא תמחר אינו אירוע ששווה אפס,
            והעמודה מציירת מקף במקום סכום. ‏`coalesce` על כל אחד מהשניים
            כדי שמשימה בלי מחיר לא תבלע תוספת שכן קיימת עליה — אותה הכרעה
            של `orphanAddons` בכרטיס התמחור. */
         case when count(v.customer_price) = 0 and count(a.total) = 0 then null
              else coalesce(sum(v.customer_price), 0) + coalesce(sum(a.total), 0) end,
         count(v.customer_price)::int,
         count(*)::int
    from work_board_view v
    left join lateral (
      select sum(x.amount) as total
        from task_price_addons x
       where x.task_id = v.id and x.deleted_at is null) a on true
   where v.event_id = any (p_event_ids)
   group by v.event_id
$$;

-- ‏`anon` לא, ו-`authenticated` במפורש: ההרשאה של Supabase לתפקיד הזה מגיעה
-- מ-`alter default privileges` בפרויקט החי, ובאשכול הבדיקות היא באה מ-`public`
-- שנשלל כאן. הענקה מפורשת אומרת את אותו דבר בשני המקומות.
revoke execute on function event_task_totals(uuid[]) from anon, public;
grant  execute on function event_task_totals(uuid[]) to authenticated;
