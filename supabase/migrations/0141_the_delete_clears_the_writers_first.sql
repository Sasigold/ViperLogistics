-- 0141: המחיקה מסלקת קודם את מי שכותב ליומן
--
-- הדיווח, מילה במילה מהמסך: **"לא ניתן למחוק לצמיתות: הפריט מקושר לרשומות
-- אחרות (event_activity)."** זו רשת הביטחון של 0137, והיא עשתה בדיוק את
-- עבודתה — היא תפסה `foreign_key_violation` אמיתי ונקבה בשמו במקום להחזיר
-- 23503 גולמי. מה שהיא חשפה הוא באג שהיה שם מאז 0124.
--
-- **מה קורה בפועל.** ל-`event_contacts` ול-`event_suppliers` יש טריגר
-- **`after delete`** שכותב שורת יומן (`log_event_contact_activity`,
-- `log_event_supplier_activity`). כשמוחקים את האירוע, פוסטגרס מוחקת קודם את
-- שורת ההורה ורק אז מריצה את פעולות ה-cascade — ולכן הטריגרים האלה רצים
-- כשהאירוע **כבר אינו קיים**, מנסים לכתוב ל-`event_activity` שמצביע עליו,
-- ונופלים על ה-FK. השם שהופיע בהודעה הוא של טבלת ה-INSERT שנכשל, לא של
-- הקישור שחסם.
--
-- **הפתרון הוא סדר, לא ניקוי נוסף.** שני הילדים האלה נמחקים במפורש בעודו
-- חי — הטריגרים שלהם כותבים בשקט שורת יומן, כפי שהם אמורים — ורק אחריהם
-- נמחק `event_activity` עצמו. מה שנשאר (`event_income`, `event_specs`,
-- `event_signatures`) נושא טריגרים ל-INSERT/UPDATE בלבד, ולכן ה-cascade
-- מטפל בו בלי להעיר איש.
--
-- **ולמה הבדיקה לא תפסה.** ב-`31_recycle_and_status_approval.sql` שורת הספק
-- נכתבה כ-`insert into event_suppliers … from (insert into suppliers …
-- returning id) s` — תחביר שאינו חוקי מחוץ ל-CTE. החבילה אינה רצה עם
-- `ON_ERROR_STOP`, ולכן ההוספה נכשלה בשקט והמחיקה נבדקה על אירוע בלי ספקים.
-- החבילה מתוקנת יחד עם המיגרציה הזו.
--
-- הגוף זהה ל-0137, בתוספת שלוש שורות בענף `events`.

create or replace function hard_delete(p_table text, p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_ok    boolean;
  v_block text;
begin
  if not app.is_admin() then
    raise exception 'רק מנהל מערכת יכול למחוק לצמיתות' using errcode = '42501';
  end if;

  -- אותה רשימה שסל המיחזור מציג. whitelist ולא format חופשי — p_table מגיע
  -- מהלקוח.
  if p_table not in ('events', 'vehicles', 'tasks', 'customers', 'contractors',
                     'contractor_workers', 'profiles', 'suppliers', 'trucks',
                     'vehicle_document_kinds', 'task_types', 'execution_methods',
                     'statuses') then
    raise exception 'טבלה לא נתמכת';
  end if;

  -- מוחקים לצמיתות רק פריט שכבר בסל.
  execute format('select exists(select 1 from %I where id = $1 and deleted_at is not null)', p_table)
    into v_ok using p_id;
  if not v_ok then
    raise exception 'ניתן למחוק לצמיתות רק פריט שכבר נמחק (בסל המיחזור)';
  end if;

  -- ===== מה שחוסם, ונאמר בשמו =============================================
  v_block := case p_table
    when 'customers' then (
      select string_agg(x, ', ') from (
        select 'אירועים'  as x where exists (select 1 from events where customer_id = p_id)
        union all select 'משימות'   where exists (select 1 from tasks where customer_id = p_id)
        union all select 'משתמשים'  where exists (select 1 from profiles where customer_id = p_id)
        union all select 'קבלות'    where exists (select 1 from receipts where customer_id = p_id)
        union all select 'ספקים'    where exists (select 1 from suppliers where customer_id = p_id)
        union all select 'סגל עובדים' where exists (select 1 from customer_workers where customer_id = p_id)
      ) t)
    when 'contractors' then (
      select string_agg(x, ', ') from (
        select 'משימות מואצלות' as x where exists (select 1 from task_contractor_terms where contractor_id = p_id)
        union all select 'משימות'  where exists (select 1 from tasks where contractor_id = p_id)
        union all select 'משתמשים' where exists (select 1 from profiles where contractor_id = p_id)
        union all select 'סגל עובדים' where exists (select 1 from contractor_workers where contractor_id = p_id)
      ) t)
    when 'contractor_workers' then (
      select string_agg(x, ', ') from (
        select 'חשבון התחברות' as x where exists (select 1 from profiles where contractor_worker_id = p_id)
      ) t)
    when 'profiles' then (
      select string_agg(x, ', ') from (
        select 'נוכחות' as x where exists (select 1 from attendance_entries where profile_id = p_id)
        union all select 'שיבוצים' where exists (select 1 from task_assignments where profile_id = p_id)
        union all select 'אירועים שיצר' where exists (select 1 from events where created_by = p_id)
        union all select 'משימות שיצר' where exists (select 1 from tasks where created_by = p_id)
      ) t)
    when 'task_types' then (
      select string_agg(x, ', ') from (
        select 'משימות' as x where exists (select 1 from tasks where task_type_id = p_id)
      ) t)
    when 'execution_methods' then (
      select string_agg(x, ', ') from (
        select 'משימות' as x where exists (select 1 from tasks where execution_method_id = p_id)
      ) t)
    when 'statuses' then (
      select string_agg(x, ', ') from (
        select 'אירועים' as x where exists (select 1 from events where status_id = p_id)
        union all select 'משימות' where exists (select 1 from tasks where status_id = p_id)
      ) t)
    when 'vehicle_document_kinds' then (
      select string_agg(x, ', ') from (
        select 'מסמכי רכב' as x where exists (select 1 from vehicle_documents where kind_id = p_id)
      ) t)
    else null end;

  if v_block is not null then
    raise exception 'לא ניתן למחוק לצמיתות: הפריט עדיין מקושר ל%. יש להסיר אותם קודם.', v_block
      using errcode = '23503';
  end if;

  -- ===== קישורים טהורים והצבעות רכות ======================================
  if p_table = 'events' then
    -- אירוע: המשימות מצביעות עליו בלי on delete cascade (0003), ולכן הן
    -- נמחקות תחילה — ומהן מדרדר cascade ל-task_pricing/‏task_assignments וכו׳.
    delete from tasks where event_id = p_id;

    -- ‏0141: ואחריהן, בסדר הזה בדיוק, שני הילדים שכותבים ליומן במחיקה —
    -- ורק אז היומן עצמו. פירוט הנימוק בראש הקובץ.
    delete from event_suppliers where event_id = p_id;
    delete from event_contacts  where event_id = p_id;
    delete from event_activity  where event_id = p_id;

  elsif p_table = 'suppliers' then
    delete from event_suppliers where supplier_id = p_id;

  elsif p_table = 'contractor_workers' then
    delete from task_contractor_workers where contractor_worker_id = p_id;

  elsif p_table = 'trucks' then
    -- המשאית היא תכנון ולא היסטוריה: מה שנשאר אחריה הוא משימה בלי משאית.
    delete from task_customer_workers where truck_id = p_id;
    update task_assignments set truck_id = null where truck_id = p_id;
    update tasks set truck_id = null where truck_id = p_id;
    update tasks set truck_ids = array_remove(truck_ids, p_id) where p_id = any(truck_ids);
    update vehicles set truck_id = null where truck_id = p_id;
  end if;

  begin
    execute format('delete from %I where id = $1', p_table) using p_id;
  exception when foreign_key_violation then
    -- רשת ביטחון: FK שנוסף אחרי 0137 ואינו מוכר לרשימה שלמעלה. שם האילוץ
    -- באנגלית מכוון את מי שיקרא את זה הרבה יותר מ"מקושר לשורות אחרות".
    raise exception 'לא ניתן למחוק לצמיתות: הפריט מקושר לרשומות אחרות (%).',
      coalesce(nullif(split_part(SQLERRM, '"', 2), ''), 'FK')
      using errcode = '23503';
  end;
end $$;

comment on function hard_delete(text, uuid) is
  'מחיקה לצמיתות מסל המיחזור (0124/0137). מ-0141 היא מסלקת קודם את הילדים '
  'שכותבים ליומן במחיקה, ורק אז את היומן עצמו — אחרת ה-cascade כותב שורה '
  'על אירוע שכבר אינו קיים.';
