-- 0130: ברירת מחדל להקמה, ברירת מחדל לפירוק, וברירת מחדל לשאר
--
-- ‏0111 נתן ללקוח **אופן ביצוע אחד** שכל משימה חדשה נולדת איתו. בשטח ההקמה
-- והפירוק כמעט אף פעם אינן אותו אופן — "צוות לשטח" מקימים ו"איסוף" מפרקים —
-- ולכן ברירת מחדל אחת נכונה לכל היותר לחצי מהמשימות, ומישהו מתקן את השנייה
-- ידנית בכל אירוע. הדיווח: **"בהגדרות הלקוח 'אופני ביצוע', כשאני מגדיר
-- ברירת מחדל, שתהיה ברירת מחדל נפרדת להקמה ולפירוק."**
--
-- **שלוש ולא שתיים.** לסוגי המשימות שאינם הקמה ופירוק (סידור, איסוף, הובלה
-- נוספת...) אין בלוק בטופס האירוע, אבל הם כן נוצרים בלו״ז ובייבוא — ואם
-- הפיצול היה מותיר אותם בלי ברירת מחדל, 0111 היה נסוג עבורם. לכן `is_default`
-- **נשאר**, ומשמעותו מצטמצמת ל"ברירת המחדל הכללית"; שתי העמודות החדשות
-- גוברות עליה כשסוג המשימה נקוב.
--
-- הדגלים נשארים על שורת ההרשאה מאותם שני נימוקים של 0111: ברירת מחדל חייבת
-- להיות אחד מהאופנים שהותרו ללקוח, וכשמסירים ללקוח אופן — כל שלושת הדגלים
-- יורדים איתו.

alter table customer_execution_methods
  add column if not exists is_default_setup    boolean not null default false,
  add column if not exists is_default_teardown boolean not null default false;

create unique index cem_one_default_setup
  on customer_execution_methods (customer_id) where is_default_setup;
create unique index cem_one_default_teardown
  on customer_execution_methods (customer_id) where is_default_teardown;

comment on column customer_execution_methods.is_default is
  'ברירת המחדל הכללית — לסוגי משימות שאינם הקמה או פירוק (0111, צומצם ב-0130).';
comment on column customer_execution_methods.is_default_setup is
  'אופן הביצוע שמשימת הקמה חדשה של הלקוח נולדת איתו (0130). אחד לכל היותר.';
comment on column customer_execution_methods.is_default_teardown is
  'אופן הביצוע שמשימת פירוק חדשה של הלקוח נולדת איתו (0130). אחד לכל היותר.';

-- ===== Backfill: מה שהיה ברירת מחדל אחת הופך לשלוש ========================
-- רק כשהאופן באמת מותר לאותו סוג משימה — אחרת היינו כותבים דגל שהטריגר
-- ממילא מדלג עליו, ומראים במסך כוכב שאינו עושה דבר.
update customer_execution_methods cem
   set is_default_setup = true
 where cem.is_default
   and exists (select 1 from task_type_execution_methods ttm
                join task_types tt on tt.id = ttm.task_type_id
               where ttm.execution_method_id = cem.execution_method_id
                 and tt.code = 'setup');

update customer_execution_methods cem
   set is_default_teardown = true
 where cem.is_default
   and exists (select 1 from task_type_execution_methods ttm
                join task_types tt on tt.id = ttm.task_type_id
               where ttm.execution_method_id = cem.execution_method_id
                 and tt.code = 'teardown');

-- ===== הטריגר בוחר לפי קוד סוג המשימה =====================================
-- הגוף זהה ל-0111, והשינוי היחיד הוא איזה דגל נבדק. שאר החיתוך (פעיל, לא
-- מחוק, מותר לסוג המשימה) נשאר מילה במילה — כולל הסיבה שהוא שם: אחרת
-- הטריגר היה כותב ערך ש-`app.apply_event_task_block` דוחה בעצמה.
create or replace function app.tasks_default_execution_method()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_code text;
begin
  if new.execution_method_id is not null or new.customer_id is null then
    return new;
  end if;

  select tt.code into v_code from task_types tt where tt.id = new.task_type_id;

  select cem.execution_method_id into new.execution_method_id
    from customer_execution_methods cem
    join execution_methods m on m.id = cem.execution_method_id
   where cem.customer_id = new.customer_id
     and case v_code
           when 'setup'    then cem.is_default_setup
           when 'teardown' then cem.is_default_teardown
           else cem.is_default
         end
     and m.is_active and m.deleted_at is null
     and (new.task_type_id is null
          or exists (select 1 from task_type_execution_methods ttm
                      where ttm.execution_method_id = cem.execution_method_id
                        and ttm.task_type_id = new.task_type_id))
   limit 1;
  return new;
end $$;

comment on function app.tasks_default_execution_method() is
  'אופן הביצוע שמשימה חדשה נולדת איתו (0111). מ-0130 הוא נבחר לפי קוד סוג '
  'המשימה: הקמה, פירוק, או ברירת המחדל הכללית לשאר.';
