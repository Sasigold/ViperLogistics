-- 0137: מחיקה לצמיתות שיודעת לנקות, ושאומרת מה חוסם
--
-- הדיווח: **"אין אפשרות למחוק ארועים לצמיתות, הוא רושם שזה מקושר לשורות
-- נוספות."** ההודעה הזו היא המיפוי של `23503` ב-`src/lib/errors.ts` — כלומר
-- ‏`foreign_key_violation` גולמי הגיע עד המסך.
--
-- ‏0124 טיפלה בילד היחיד של `events` שאינו `on delete cascade` (‏`tasks`),
-- וב**אירוע** היא אכן עובדת. מה שלא טופל הוא כל שאר הרשימה הלבנה שהיא
-- עצמה פתחה: `trucks`, `statuses`, `task_types`, `execution_methods`,
-- `customers`, `contractors`, `contractor_workers`, `profiles`, `suppliers`
-- — כולן מוצבעות בלי cascade, וכל לחיצה עליהן החזירה בדיוק את ההודעה הזו.
-- הסל מציג את כולן באותה רשימה נפתחת ובאותו כפתור אדום, ולכן מבחינת מי
-- שלוחץ זה באג אחד ולא תשעה.
--
-- **שלוש קטגוריות, ולא ניקוי גורף.**
--
--   1. **קישור טהור נמחק.** ‏`event_suppliers`, ‏`task_contractor_workers`,
--      `task_customer_workers` — שורות שכל תוכנן הוא "זה קשור לזה", ואין
--      להן קיום בלי שני הצדדים.
--   2. **הצבעה רכה מתאפסת.** המשאית של משימה, של שיבוץ ושל עובד סגל היא
--      תכנון, לא היסטוריה: משאית שירדה מהצי משאירה את המשימה במקומה בלי
--      משאית. גם `tasks.truck_ids` — מערך, ולכן `array_remove` ולא NULL.
--   3. **כל השאר נחסם, בשמו.** לקוח עם אירועים, סוג משימה שמשימות מצביעות
--      עליו, סטטוס שבשימוש, חשבון שיש לו נוכחות — אלה אינם "תלויות טכניות"
--      אלא היסטוריה, ומחיקה שלהם היא איבוד נתונים. ההודעה נוקבת **במה**
--      חוסם, כי "מקושר לשורות אחרות" אינו אומר למי שקורא אותו מה לעשות.
--
-- ורשת ביטחון אחרונה: `exception when foreign_key_violation` סביב המחיקה
-- עצמה, שמתרגמת כל FK שנוסף בעתיד להודעה עברית עם שם הטבלה — במקום
-- להתגלגל ל-23503 ולהודעה הגנרית.

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
  'מחיקה לצמיתות מסל המיחזור (0124). מ-0137 היא מנקה קישורים טהורים ומאפסת '
  'הצבעות רכות, וחוסמת בהודעה שנוקבת בשם מה שנשאר — במקום 23503 גולמי.';
