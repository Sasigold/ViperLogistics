-- 0185: הפין נוסע עם האולם
--
-- המחיר של ארקו נגזר, בין השאר, מ-`travel_hours` — ואלה באים מאזור התמחור
-- שהפין של האירוע נופל בתוכו (0017). ארקו שולחת **טקסט בלבד**: "חוות רונית",
-- "ירושלים". ‏`arco-intake` מתרגמת אותו לפין דרך `geocode-proxy`, אבל
-- גיאוקודר הוא שירות חיצוני: הוא לא מכיר כל אולם, הוא נופל, ולפעמים הוא
-- מוחלף. אירוע בלי פין הוא אירוע עם אפס שעות נסיעה — כלומר **מחיר נמוך
-- מהאמת, שנשלח ללקוח כאילו הוא סופי**.
--
-- ומה שיש לנו הוא דבר שהגיאוקודר אינו יכול לדעת: **את האולם הזה כבר
-- נסענו אליו.** אותו לקוח, אותו שם מיקום בדיוק, ופין שרכז כבר סימן — זו
-- התשובה הטובה ביותר שיש, והיא טובה יותר מהגיאוקודר עצמו: היא כוללת את
-- התיקון שאדם עשה ביד אחרי שהפין הראשון נפל ליד.
--
-- שלוש הכרעות:
--
--   1. **רק כשאין פין במעטפה.** מה שהגיאוקודר החזיר גובר תמיד; הירושה
--      ממלאת חור ואינה דורסת דבר.
--   2. **אותו לקוח בלבד.** "המחסן" של לקוח אחד אינו "המחסן" של אחר.
--   3. **התאמת טקסט מלאה, אחרי btrim.** לא דמיון, לא trigram: פין שגוי
--      גרוע מאין פין, כי הוא מייצר מחיר שגוי בשקט במקום שדה ריק שנראה
--      לעין במסך.
--
-- זה אינו קוד של ארקו והוא אינו מזכיר אותה: כל אינטגרציה שתפתח אירוע לפי
-- שם מיקום תקבל את אותה ירושה.

create or replace function app.inherit_location_pin()
returns trigger language plpgsql security definer set search_path = public as $$
declare r record;
begin
  if new.location_lat is not null or new.location_lng is not null then
    return new;
  end if;
  if coalesce(btrim(new.location_text), '') = '' then return new; end if;

  select e.location_lat, e.location_lng, e.location_provider, e.location_place_id
    into r
    from events e
   where e.customer_id = new.customer_id
     and e.deleted_at is null
     and e.id is distinct from new.id
     and btrim(e.location_text) = btrim(new.location_text)
     and e.location_lat is not null and e.location_lng is not null
   order by e.created_at desc
   limit 1;

  if r.location_lat is null then return new; end if;

  new.location_lat      := r.location_lat;
  new.location_lng      := r.location_lng;
  new.location_provider := coalesce(new.location_provider, r.location_provider);
  new.location_place_id := coalesce(new.location_place_id, r.location_place_id);
  return new;
end $$;

-- ‏before insert בלבד. עריכה של אירוע קיים היא החלטה של אדם שרואה את המפה,
-- ואין לה מה לרשת: מי שמחק פין ביד התכוון למחוק אותו.
create trigger events_inherit_location_pin before insert on events
  for each row execute function app.inherit_location_pin();

revoke execute on function app.inherit_location_pin() from anon, authenticated, public;
