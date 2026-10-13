-- 0225: מחיקה שמנהל שאינו אדמין יכול לעשות
--
-- ‏**הבאג.** ארבעה מסכים מחקו "מחיקה רכה" בעדכון ישיר מהדפדפן —
-- ‏`update ... set deleted_at = <השעון של המכשיר>` — על receipts (0068),
-- ‏warehouses (0022), pricing_zones (0071) ו-contractor_workers (0028). לכל
-- הארבע יש פוליסת קריאה בצורה "אדמין, או deleted_at is null". ב-UPDATE,
-- PostgreSQL בודק את השורה *החדשה* גם מול פוליסות הקריאה (ה-WHERE קורא את
-- הטבלה), והשורה החדשה — מחוקה — כבר אינה נראית למי שאינו אדמין. התוצאה:
-- ‏"new row violates row-level security policy" לכל מנהל שמחזיק את המפתח
-- ואינו אדמין. המחיקה עבדה רק לאדמין, ולכן איש לא ראה את זה. (אומת על
-- אשכול הבדיקה: מנהל תקבולים עם finance.receipts_manage נדחה.)
--
-- ‏**התיקון.** כלל 10: מחיקה רכה דרך פונקציית definer. ‏`soft_delete` (0089)
-- כבר עושה בדיוק את זה — בודקת מפתח, חותמת now() של השרת, ועוקפת את ה-RLS
-- בכתיבה עצמה. נוספים לה שלושה ענפים; contractor_workers כבר היה בה
-- ‏(contractors.manage_workers), והמסך פשוט לא השתמש בה. מפתח אחד לשני
-- הכיוונים, כמו trucks ו-suppliers: מי שמורשה להוריד מהרשימה מורשה להחזיר.
--
--   receipts       finance.receipts_manage  (אותו מפתח של receipts_update)
--   warehouses     attendance.manage_warehouses או settings.edit (warehouses_write)
--   pricing_zones  pricing.manage_rules     (pz_write)
--
-- הענפים החדשים פתוחים לצוות בלבד: לקוח נעצר כבר בבדיקה הקיימת ("רק אירוע
-- שלו"), וקבלן נעצר כאן במפורש.
--
-- הגוף מועתק מ-0089:979 — ההגדרה החיה — בתוספת הענפים והגדר לקבלן.

-- ===== 1. soft_delete =====================================================

create or replace function soft_delete(p_table text, p_id uuid, p_restore boolean default false)
returns void language plpgsql security definer set search_path = public as $$
declare v_key text;
begin
  v_key := case p_table
    when 'events'             then case when p_restore then 'events.restore'      else 'events.delete' end
    when 'tasks'              then case when p_restore then 'tasks.restore'       else 'tasks.delete' end
    when 'customers'          then case when p_restore then 'customers.restore'   else 'customers.delete' end
    when 'contractors'        then case when p_restore then 'contractors.restore' else 'contractors.delete' end
    when 'contractor_workers' then 'contractors.manage_workers'
    when 'profiles'           then case when p_restore then 'users.restore'       else 'users.delete' end
    when 'suppliers'          then 'customers.manage_suppliers'
    when 'trucks'             then 'settings.trucks'
    when 'vehicles'           then 'fleet.delete'
    when 'vehicle_document_kinds' then 'fleet.settings'
    when 'task_types'         then 'settings.task_types'
    when 'execution_methods'  then 'settings.execution_methods'
    when 'statuses'           then 'settings.statuses'
    -- ‏0225
    when 'receipts'           then 'finance.receipts_manage'
    when 'warehouses'         then case when app.has('settings.edit') then 'settings.edit'
                                        else 'attendance.manage_warehouses' end
    when 'pricing_zones'      then 'pricing.manage_rules'
    else null end;
  if v_key is null then raise exception 'טבלה לא נתמכת'; end if;
  perform app.require(v_key, 'אין לך הרשאה למחוק פריט זה');

  -- the key says "may delete this kind of thing"; this says "this one"
  if not app.is_admin() then
    if p_table = 'profiles' and not app.can_manage_profile(p_id) then
      raise exception 'אין לך הרשאה למחוק משתמש זה' using errcode = '42501';
    end if;
    if app.user_kind() = 'customer_user' then
      if p_table = 'events' then
        if not exists (select 1 from events
                       where id = p_id and customer_id = app.customer_id()) then
          raise exception 'אין לך הרשאה למחוק פריט זה' using errcode = '42501';
        end if;
      elsif p_table <> 'profiles' then
        raise exception 'אין לך הרשאה למחוק פריט זה' using errcode = '42501';
      end if;
    end if;
    -- ‏0225: הענפים החדשים הם מסכי משרד
    if p_table in ('receipts', 'warehouses', 'pricing_zones') and app.user_kind() <> 'staff' then
      raise exception 'אין לך הרשאה למחוק פריט זה' using errcode = '42501';
    end if;
  end if;

  if p_table = 'task_types' and not p_restore
     and exists (select 1 from task_types where id = p_id and is_system) then
    raise exception 'לא ניתן למחוק סוג משימה מערכתי';
  end if;

  perform app.system_write(true);
  execute format('update %I set deleted_at = case when $2 then null else now() end where id = $1', p_table)
    using p_id, p_restore;
  perform app.system_write(false);
end $$;

revoke execute on function soft_delete(text, uuid, boolean) from anon, public;
grant execute on function soft_delete(text, uuid, boolean) to authenticated;
