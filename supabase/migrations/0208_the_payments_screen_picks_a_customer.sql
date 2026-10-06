-- 0208: מסך תשלומי האירועים מסנן לפי לקוח
--
-- הבקשה: "בדף תשלומי אירועים שיהיה פילטר אם יש לי יותר מלקוח מערכת אחד.
-- לדוגמא שיא עיצובים וקיסר." כלומר: כשהמתג "תשלומי אירועים" (0205) דלוק אצל
-- יותר מלקוח אחד, המסך `/payments` מציע לבחור לקוח — והטבלה וגם פס הסיכום
-- שמעליה מראים רק אותו.
--
-- שתי הכרעות:
--
--   1. **הסיכום מסונן בשרת.** פס הסיכום של המסך נשאל מ-`event_payments_dashboard`
--      ולא נספר בדפדפן (0205 §9, CLAUDE.md §2.1), ולכן גם הסינון שלו יושב
--      כאן: פרמטר `p_customer_id`. בלעדיו — בדיוק מה שהיה, כך שכרטיסי
--      הדשבורד, שאינם מעבירים אותו, אינם משתנים. השורות של הטבלה
--      כבר נושאות `customer_id` (‏`event_payments_list`), והסינון שלהן הוא
--      בחירת שורות ולא חישוב — הוא נשאר בדפדפן ואינו מחייב שאילתה חדשה.
--
--   2. **רשימת הלקוחות באה מהשרת.** ‏`customer_options` — כל הלקוחות שהמתג
--      דלוק אצלם (מזהה, שם, צבע), גם אם לאחד מהם אין אירועים בטווח. "יותר
--      מלקוח אחד" היא שאלה על ההגדרה, לא על החודש הנוכחי: הפילטר לא אמור
--      להופיע ולהיעלם כשמדפדפים בין חודשים. ‏`customers` (השמות שמהם הדשבורד
--      בונה את הכותרת) מצטמצם ללקוח שנבחר.
--
-- **שתי חתימות, בלי `drop` ובלי ברירת מחדל.** הגרסה עם הלקוח היא חתימה
-- חדשה (date, date, uuid), והגרסה הקיימת (date, date) נשארת ונעשית עטיפה
-- דקה שקוראת לה עם null. ל-`p_customer_id` אין `default` בכוונה: עם ברירת
-- מחדל, קריאה בשני פרמטרים הייתה מתאימה לשתי הפונקציות ו-PostgREST היה
-- נכשל על קריאה דו-משמעית. כך כל קריאה מתאימה לחתימה אחת בדיוק, ואין צורך
-- למחוק את הפונקציה הישנה — הכרטיסים והבדיקות שקוראים לה ממשיכים כמו שהם.

-- ===== 1. הסיכום, עם לקוח ==================================================

create or replace function event_payments_dashboard(
  p_from date, p_to date, p_customer_id uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_start date;
  v_out   jsonb;
begin
  if not app.can_view_event_payments() then return null; end if;
  if p_from is null or p_to is null or p_to < p_from then
    raise exception 'טווח תאריכים לא תקין' using errcode = '22023';
  end if;
  if p_to - p_from > 400 then
    raise exception 'טווח גדול מדי לדשבורד' using errcode = '22023';
  end if;

  v_start := least(p_from, (date_trunc('month', p_to) - interval '11 months')::date);

  with d as (
    select * from app.event_payment_dues
     where event_date between v_start and p_to
       and (due <> 0 or paid <> 0)
       and (p_customer_id is null or customer_id = p_customer_id)
  ), r as (
    select * from d where event_date between p_from and p_to
  )
  select jsonb_build_object(
    'due',          round(coalesce((select sum(due) from r), 0), 2),
    'paid',         round(coalesce((select sum(paid) from r), 0), 2),
    'unpaid',       round(coalesce((select sum(greatest(balance, 0)) from r), 0), 2),
    'events',       (select count(*) from r),
    'paid_events',  (select count(*) from r where due > 0 and balance <= 0),
    'open_events',  (select count(*) from r where balance > 0),
    'customers',    (select coalesce(jsonb_agg(c.name order by c.name), '[]'::jsonb)
                       from customers c
                      where c.event_payments_enabled and c.deleted_at is null
                        and (p_customer_id is null or c.id = p_customer_id)),
    'customer_options', (select coalesce(jsonb_agg(jsonb_build_object(
                              'id', c.id, 'name', c.name, 'color', c.color) order by c.name), '[]'::jsonb)
                       from customers c
                      where c.event_payments_enabled and c.deleted_at is null),
    'months', (select coalesce(jsonb_agg(row_to_json(m) order by m.month), '[]'::jsonb) from (
        select date_trunc('month', event_date)::date      as month,
               count(*)                                   as events,
               round(sum(due), 2)                         as due,
               round(sum(paid), 2)                        as paid,
               round(sum(greatest(balance, 0)), 2)        as unpaid
          from d group by 1) m))
    into v_out;

  return v_out;
end $$;

revoke execute on function event_payments_dashboard(date, date, uuid) from anon, public;
grant  execute on function event_payments_dashboard(date, date, uuid) to authenticated;

-- ===== 2. החתימה הישנה — כל הלקוחות =======================================
--
-- אותה חתימה ואותו טיפוס החזרה, ולכן `create or replace` שומר את ההרשאות
-- שלה (0205). השער (`app.can_view_event_payments`) נבדק בפונקציה שהיא קוראת לה.

create or replace function event_payments_dashboard(p_from date, p_to date)
returns jsonb language sql stable security definer set search_path = public as $$
  select event_payments_dashboard(p_from, p_to, null::uuid)
$$;

revoke execute on function event_payments_dashboard(date, date) from anon, public;
grant  execute on function event_payments_dashboard(date, date) to authenticated;
