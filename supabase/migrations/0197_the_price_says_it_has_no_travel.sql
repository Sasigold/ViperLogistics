-- ‏0197: המחיר אומר שאין בו נסיעה
--
-- ‏"אם ארקו דוחפים אירוע בלי מיקום שנמצא בגיאופנס, או שהכניסו מיקום ידני,
-- שיהיה סימון באדום שאומר שהמחיר הוא ללא חישוב זמן הנסיעה למיקום."
--
-- זמן הנסיעה של משימה נגזר מאזור התמחור שהפין של האירוע נופל בתוכו
-- (‏`app.task_travel_hours`, 0020). כשאין פין, או שהפין נופל מחוץ לכל אזור,
-- הוא חוזר `null` — והמחשבון סופר אפס שעות נסיעה. המחיר שיוצא נראה סופי
-- לגמרי, והוא נמוך מהאמת. 0185 סגרה חלק מהחור (ירושת פין מאולם מוכר), אבל
-- מה שנשאר פתוח צריך להיראות לעין ולא רק להיות נכון במסד.
--
-- שלוש סיבות, לפי סדר העדיפות שבו הן נבדקות:
--
--   * ‏`no_pin`  — אין פין כלל: ארקו שלחה טקסט שהגיאוקודר לא מצא ואין אולם
--                 קודם באותו שם לרשת ממנו, או מיקום ידני בלי קואורדינטות.
--   * ‏`manual`  — יש פין, אבל המיקום הוזן ביד (אין `location_provider`: הוא
--                 לא נבחר מהגיאוקודר). אין מי שמאשר שהקואורדינטות שהוקלדו
--                 נכונות, ולכן זמן הנסיעה אינו מחושב "באמת".
--   * ‏`no_zone` — יש פין, אבל הוא נופל מחוץ לכל אזור תמחור פעיל של הלקוח
--                 (‏`zone_for_point` אינו מחזיר אזור).
--
-- אירוע נסמן רק אם יש בו לפחות משימה אחת שהמחיר שלה *תלוי* בזה: מתומחרת,
-- לא ידנית, ובלי דריסת `travel_hours` על המשימה עצמה. מחיר שרכז הקליד ביד,
-- או משימה שזמן הנסיעה שלה נקבע ידנית, כבר כוללים את מה שצריך.
--
-- ‏`security invoker`, מאותו נימוק של `event_task_totals` (0169): ‏RLS על
-- האירועים ועל המשימות מכריעה מה חוזר, ו-`customer_price` ממוסך למי שאין לו
-- ‏`pricing.view` — ולכן קורא כזה אינו מקבל אף שורה.

create or replace function event_travel_gaps(p_event_ids uuid[])
returns table (
  event_id uuid,
  reason   text)
language sql stable set search_path = public as $$
  select e.id,
         case
           when e.location_lat is null or e.location_lng is null  then 'no_pin'
           when nullif(btrim(e.location_provider), '') is null    then 'manual'
           else 'no_zone'
         end
    from events e
   where e.id = any (p_event_ids)
     and exists (
       select 1 from work_board_view v
        where v.event_id = e.id
          and v.customer_price is not null
          and not coalesce(v.price_is_manual, false)
          and v.travel_hours is null)
     and (
       nullif(btrim(e.location_provider), '') is null
       or e.location_lat is null or e.location_lng is null
       or (app.zone_for_point(e.customer_id, e.location_lat, e.location_lng)).travel_hours is null)
$$;
revoke execute on function event_travel_gaps(uuid[]) from anon, public;
grant  execute on function event_travel_gaps(uuid[]) to authenticated;
