-- 0150: חשבון שמשויך לקבלן מקבל שורת סגל מיד
--
-- הדיווח (בהמשך ל-0149): "למה אי אפשר להגדיר עליו ראש צוות, נהג ומעקב
-- איחורים?" — כל שלושת המתגים יושבים על שורת סגל (`contractor_worker_roles`
-- ו-`contractor_workers.lateness_tracked`), וחשבון משויך קיבל אותה עד כה רק
-- בשיבוץ הראשון (הגשר העצל של 0103/0121). עד אז הוא הופיע ברשימה כ"חשבון"
-- חסר מתגים — נראה כתקלה, והוא אכן חצי-עובד.
--
-- ההכרעה: **השיוך הוא הקבלה לסגל.** ברגע שחשבון נקשר לקבלן — במסך העובדים,
-- ביצירה, או בכל נתיב אחר — יש לו שורת סגל אצלו. הגשר העצל ב-
-- `contractor_assign_worker` נשאר כרשת ביטחון לנתונים שנכתבו מחוץ לטריגר,
-- אבל מעכשיו הוא לא אמור לפגוש חשבון בלי שורה.
--
-- **חיבור לפני יצירה**, ושתי סיבות לכך:
--
--   * מסך "העובדים שלי" מאפשר לקבלן להקליד עובד לרוסטר בשם בלבד. אם המשרד
--     פותח לאותו אדם חשבון אחר כך, יצירה עיוורת הייתה מכפילה אותו ברשימה —
--     פעם כשורה ידנית ופעם כחשבון.
--   * ‏0149 משאיר את השורה הישנה אצל הקבלן הקודם. חשבון שחוזר לקבלן שכבר
--     עבד אצלו (א ← ב ← א) צריך לחזור *לשורה שלו*, עם ההיסטוריה והתפקידים
--     שכבר הוגדרו בה, ולא לקבל שורה שנייה לצדה.
--
-- ההתאמה היא על שם מנורמל בתוך אותו קבלן, ורק לשורה שאין חשבון אחר שמצביע
-- עליה. שם הוא סימן חלש, ולכן הוא נסבל כאן דווקא: שתי שורות באותו שם אצל
-- אותו קבלן הן ממילא אותו אדם או תקלת הקלדה, ובשני המקרים איחוד עדיף על
-- כפילות. יחד עם 0149 זה סוגר את המעגל.

create or replace function app.sync_contractor_worker_link()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_worker uuid;
begin
  -- ‏0149: קישור נשמר רק כששורת הסגל שהוא מצביע עליה שייכת לקבלן של החשבון.
  if new.contractor_worker_id is not null
     and (new.contractor_id is null
          or (select w.contractor_id from contractor_workers w
               where w.id = new.contractor_worker_id) is distinct from new.contractor_id) then
    new.contractor_worker_id := null;
  end if;

  -- ‏0150: חשבון חי שמשויך לקבלן ואין לו שורת סגל — מחובר לשורה פנויה בשמו,
  -- ואם אין כזו, מקבל שורה חדשה. ‏`user_id` נשאר null במתכוון, כמו בגשר של
  -- ‏0121 (`contractor_workers_user_uq`).
  if new.contractor_id is not null
     and new.contractor_worker_id is null
     and new.deleted_at is null then

    select w.id into v_worker
      from contractor_workers w
     where w.contractor_id = new.contractor_id
       and w.deleted_at is null
       and btrim(w.full_name) = btrim(new.full_name)
       and not exists (select 1 from profiles p2
                        where p2.contractor_worker_id = w.id and p2.id <> new.id)
     order by w.created_at
     limit 1;

    if v_worker is null then
      insert into contractor_workers (contractor_id, full_name, phone)
      values (new.contractor_id, new.full_name, new.phone)
      returning id into v_worker;
    end if;

    new.contractor_worker_id := v_worker;
  end if;

  return new;
end $$;

-- הטריגר של 0149 כבר מאזין ל-insert ולעדכון של שתי העמודות; הגוף התחלף.

-- תיקון חד-פעמי: כל חשבון חי שכבר משויך ועדיין בלי שורת סגל. ה-UPDATE מפעיל
-- את הטריגר שלמעלה, ולכן החיבור-או-היצירה נעשה בו ולא כאן — הגדרה אחת.
update profiles p set contractor_worker_id = null
 where p.contractor_id is not null
   and p.contractor_worker_id is null
   and p.deleted_at is null;
