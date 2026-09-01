-- 0149: קישור שורת הסגל נופל כשהחשבון עובר קבלן
--
-- הדיווח: "הוספתי את אביב תחת עובדי די אן אן ופה אני לא רואה אותו."
--
-- מה שקרה: לחשבון הייתה שורת סגל אצל הקבלן הקודם, ו-`profiles.contractor_worker_id`
-- המשיך להצביע עליה גם אחרי שמסך העובדים העביר את `contractor_id` לקבלן החדש.
-- שתי הזרועות של `contractor_assignable_workers` פספסו אותו יחד: זרוע הרוסטר
-- לא מוצאת אותו (שורת הסגל שלו יושבת אצל קבלן אחר), וזרוע החשבונות מדלגת
-- עליו (`contractor_worker_id is null` — ולו יש). התוצאה: החשבון משויך,
-- והקבלן אינו רואה אותו — לא ב"העובדים שלי" ולא בבורר השיבוץ.
--
-- ההכרעה: **הקישור הוא פר-קבלן.** שורת סגל היא שורה בסגל של קבלן מסוים,
-- וחשבון שעבר קבלן משאיר אותה מאחור — היא ההיסטוריה של השיבוצים אצל הקבלן
-- הקודם, והיא אינה נמחקת. הקישור מהחשבון אליה הוא שמתנתק, ובשיבוץ הראשון
-- אצל הקבלן החדש `contractor_assign_worker` יגשר שורת סגל חדשה (0121) —
-- בדיוק כמו חשבון שנולד משויך.
--
-- טריגר ולא תיקון במסך: מסך העובדים אינו הכותב היחיד של `contractor_id`,
-- וכל נתיב שמזיז שיוך היה צריך לזכור לנתק. השרת זוכר פעם אחת.

create or replace function app.sync_contractor_worker_link()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  -- קישור נשמר רק כששורת הסגל שהוא מצביע עליה שייכת לקבלן של החשבון.
  -- זה מכסה גם שיוך שירד (contractor_id = null) וגם החלפת קבלן.
  if new.contractor_worker_id is not null
     and (new.contractor_id is null
          or (select w.contractor_id from contractor_workers w
               where w.id = new.contractor_worker_id) is distinct from new.contractor_id) then
    new.contractor_worker_id := null;
  end if;
  return new;
end $$;

drop trigger if exists profiles_sync_contractor_worker_link on profiles;
create trigger profiles_sync_contractor_worker_link
  before insert or update of contractor_id, contractor_worker_id on profiles
  for each row execute function app.sync_contractor_worker_link();

-- תיקון חד-פעמי לשורות שכבר נפרדו: חשבון שהקישור שלו מצביע על שורת סגל
-- של קבלן אחר (או שאין לו קבלן כלל) מתנתק, ונופל לזרוע החשבונות של המאגר.
update profiles p set contractor_worker_id = null
 where p.contractor_worker_id is not null
   and (p.contractor_id is null
        or exists (select 1 from contractor_workers w
                    where w.id = p.contractor_worker_id
                      and w.contractor_id is distinct from p.contractor_id));
