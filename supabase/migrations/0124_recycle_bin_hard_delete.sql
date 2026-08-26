-- 0124: מחיקה לצמיתות מסל המיחזור
--
-- ‏soft_delete יודע רק לסמן ולבטל `deleted_at`, וסל המיחזור (0012) הציע רק
-- "שחזור". מעכשיו אפשר גם למחוק לצמיתות — אבל **רק את מה שכבר בסל** (‏
-- `deleted_at is not null`), ורק מנהל מערכת. אין דרך למחוק לצמיתות פריט חי:
-- המחיקה הרכה היא עדיין השער היחיד, וזו רק דלת היציאה ממנו.

create or replace function hard_delete(p_table text, p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_ok boolean;
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

  -- אירוע: המשימות מצביעות עליו בלי on delete cascade (0003), ולכן הן
  -- נמחקות תחילה — ומהן מדרדר cascade ל-task_pricing/‏task_assignments וכו׳.
  if p_table = 'events' then
    delete from tasks where event_id = p_id;
  end if;

  execute format('delete from %I where id = $1', p_table) using p_id;
end $$;

revoke all on function hard_delete(text, uuid) from public;
grant execute on function hard_delete(text, uuid) to authenticated;
