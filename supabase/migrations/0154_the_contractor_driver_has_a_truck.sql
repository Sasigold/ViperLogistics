-- 0154: גם לנהג של הקבלן יש משאית
--
-- ‏`task_assignments.truck_id` קיים מ-0003 לאיש הצוות, ו-`task_customer_workers.truck_id`
-- מ-0133 לסגל של הלקוח. עובד הקבלן — שמאז 0121 יכול להיות מוגדר נהג ומשובץ
-- ככזה — היה היחיד משלושת המאגרים שאין לו במה לנסוע: הוא סומן "נהג" על
-- המשימה, והשאלה "באיזו משאית" נשארה בלי מקום להיכתב בו.
--
-- שלוש הכרעות, ושלושתן זהות למה שכבר הוכרע ב-0133/0140 לסגל הלקוח:
--
-- 1. **עמודה על שורת השיבוץ, לא על העובד.** המשאית היא של המשימה הזו ולא
--    תכונה של הנהג — מחר הוא נוסע באחרת — ולכן היא יושבת במקום שבו יושבים
--    גם התפקיד ואתר העבודה.
-- 2. **הרשימה היא של הלקוח, כשיש לו כזו (0116).** אותה בדיקה בדיוק שבה
--    `customer_assign_worker` מגבילה את סגל הלקוח: רשימה ריקה = כל הקטלוג,
--    כדי שלא יהיו שלושה מסכים עם שלוש תשובות.
-- 3. **משאית שייכת לנהג.** תפקיד שאינו 'driver' עם משאית נדחה במפורש ולא
--    נבלע בשקט: מי שמוריד עובד מתפקיד הנהג מוריד גם את המשאית, וזה מה
--    שהמסך שולח.
--
-- החתימה גדלה בפרמטר, והישנה נמחקת ולא נשארת לצידה — 0024 §8: שתיהן היו
-- נקראות באותם שישה ארגומנטים, וזו בדיוק העמימות שהוזהרנו מפניה.

-- ===== 1. העמודה =========================================================

alter table task_contractor_workers add column truck_id uuid references trucks(id);

comment on column task_contractor_workers.truck_id is
  'המשאית של עובד הקבלן במשימה הזו. רק לתפקיד driver, ומוגבלת לרשימת '
  'המשאיות של הלקוח כשיש לו כזו (0116).';

create index task_contractor_workers_truck_idx
  on task_contractor_workers (truck_id) where truck_id is not null;

-- ===== 2. השיבוץ ==========================================================
--
-- זהה ל-0128 פרט למשאית: פרמטר, שתי בדיקות, ועמודה ב-upsert.
drop function if exists contractor_assign_worker(uuid, uuid, uuid, boolean, text, staff_role);

create or replace function contractor_assign_worker(
  p_task_id uuid,
  p_worker_id uuid default null,
  p_profile_id uuid default null,
  p_on boolean default true,
  p_work_site text default null,
  p_role staff_role default null,
  p_truck_id uuid default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_ctr    uuid;
  v_mine   uuid := app.contractor_id();
  v_worker uuid := p_worker_id;
  v_prof   profiles%rowtype;
  v_site   text := p_work_site;
  v_cust   uuid;
begin
  if not (app.has('portal.assign_workers') or app.has('contractors.assign_workers')) then
    raise exception 'אין לך הרשאה לשבץ עובדי קבלן' using errcode = '42501';
  end if;

  -- פתרון העובד והקבלן שלו.
  if v_worker is null then
    if p_profile_id is null then
      raise exception 'חובה לנקוב בעובד או בחשבון' using errcode = '22023';
    end if;
    select * into v_prof from profiles where id = p_profile_id and deleted_at is null;
    if v_prof.id is null then
      raise exception 'העובד לא נמצא' using errcode = '42501';
    end if;
    v_ctr := v_prof.contractor_id;
    v_worker := v_prof.contractor_worker_id;
    if v_worker is null then
      if v_ctr is null then
        raise exception 'לחשבון אין קבלן משויך' using errcode = '42501';
      end if;
      insert into contractor_workers (contractor_id, full_name, phone)
      values (v_ctr, v_prof.full_name, v_prof.phone)
      returning id into v_worker;
      update profiles set contractor_worker_id = v_worker where id = v_prof.id;
    end if;
  else
    select contractor_id into v_ctr from contractor_workers
     where id = v_worker and deleted_at is null;
  end if;
  if v_ctr is null then
    raise exception 'לא נמצא קבלן לעובד' using errcode = '42501';
  end if;

  -- המשימה חייבת להיות מואצלת לקבלן של העובד.
  if not exists (select 1 from task_contractor_terms
                  where task_id = p_task_id and contractor_id = v_ctr) then
    raise exception 'המשימה אינה מואצלת לקבלן של העובד' using errcode = '42501';
  end if;

  -- קבלן משבץ רק את עובדיו; איש משרד צריך את המפתח המשרדי לקבלן אחר.
  if v_ctr is distinct from v_mine then
    perform app.require('contractors.assign_workers');
  end if;

  -- ‏0121: שיבוץ לתפקיד דורש שהעובד מוגדר בו. null = עובד רגיל.
  if p_role in ('team_lead', 'driver')
     and not exists (select 1 from contractor_worker_roles
                      where contractor_worker_id = v_worker and role = p_role) then
    raise exception 'העובד אינו מוגדר בתפקיד המבוקש' using errcode = '42501';
  end if;

  -- ‏0128: ראש צוות אחד למשימה — פנימי או של קבלן, ולא אחד מכל סוג.
  if p_on and p_role = 'team_lead' then
    if exists (select 1 from task_assignments a
                where a.task_id = p_task_id and a.role = 'team_lead') then
      raise exception 'למשימה כבר מוגדר ראש צוות' using errcode = '42501';
    end if;
    if exists (select 1 from task_contractor_workers tcw
                where tcw.task_id = p_task_id and tcw.role = 'team_lead'
                  and tcw.contractor_worker_id is distinct from v_worker) then
      raise exception 'למשימה כבר מוגדר ראש צוות' using errcode = '42501';
    end if;
  end if;

  -- ‏0154: המשאית.
  --
  -- ‏`tasks.assign.truck` נדרש רק כשהיא **משתנה**, ולא כשהיא נשלחת: הקורא
  -- שולח את מצב השורה כולו בכל קריאה (אחרת ה-upsert מוחק את מה שלא נשלח),
  -- ומנהל קבלן שמזיז את אתר העבודה של נהג אינו אמור להיחסם על משאית שהמשרד
  -- קבע ושהוא רק מחזיר כפי שהיא. המשאית היא נכס של המשרד, ולכן שינוי שלה
  -- הוא של מי שמחזיק את המפתח שכבר שומר עליה ב-`task_assignments` (0012).
  if p_on and p_truck_id is distinct from
       (select truck_id from task_contractor_workers
         where task_id = p_task_id and contractor_worker_id = v_worker) then
    perform app.require('tasks.assign.truck');
  end if;

  -- המשאית היא של הנהג. תפקיד אחר עם משאית נדחה במפורש — שיבוץ ש"שכח"
  -- להוריד אותה בשינוי תפקיד הוא באג של הקורא, ובליעה שקטה שלה הייתה
  -- משאירה משאית תפוסה על מי שאינו נוהג בה.
  if p_on and p_truck_id is not null then
    if p_role is distinct from 'driver' then
      raise exception 'משאית משויכת לנהג בלבד' using errcode = '22023';
    end if;
    if not exists (select 1 from trucks t where t.id = p_truck_id and t.deleted_at is null) then
      raise exception 'המשאית לא נמצאה' using errcode = '42501';
    end if;
    -- אותה הגבלה של 0116: רשימת המשאיות של הלקוח, וריקה = כל הקטלוג.
    select customer_id into v_cust from tasks where id = p_task_id;
    if exists (select 1 from customer_trucks where customer_id = v_cust)
       and not exists (select 1 from customer_trucks
                        where customer_id = v_cust and truck_id = p_truck_id) then
      raise exception 'המשאית אינה ברשימת המשאיות של הלקוח' using errcode = '42501';
    end if;
  end if;

  -- ‏0111: נקודת ההתחלה היא של המשרד. בלי המפתח המשרדי מה שנשלח מהקורא נזרק.
  if not app.has('contractors.assign_workers') then
    v_site := null;
  end if;
  if v_site is null then
    select coalesce(work_site, 'field') into v_site
      from task_contractor_terms where task_id = p_task_id and contractor_id = v_ctr;
    v_site := coalesce(v_site, 'field');
  end if;
  if v_site not in ('field', 'warehouse') then
    raise exception 'אתר עבודה לא חוקי: %', v_site using errcode = '22023';
  end if;

  if p_on then
    insert into task_contractor_workers (task_id, contractor_worker_id, work_site, role, truck_id)
    values (p_task_id, v_worker, v_site, p_role,
            case when p_role = 'driver' then p_truck_id end)
    on conflict (task_id, contractor_worker_id) do update
      set work_site = excluded.work_site,
          role      = excluded.role,
          truck_id  = excluded.truck_id;
  else
    delete from task_contractor_workers
     where task_id = p_task_id and contractor_worker_id = v_worker;
  end if;

  return v_worker;
end $$;

comment on function contractor_assign_worker(uuid, uuid, uuid, boolean, text, staff_role, uuid) is
  'שיבוץ עובד קבלן למשימה, עם תפקיד (0121) וראש צוות אחד למשימה (0128). '
  'מ-0154 גם המשאית של הנהג — מוגבלת לרשימת המשאיות של הלקוח, כמו בסגל שלו.';

revoke execute on function public.contractor_assign_worker(uuid, uuid, uuid, boolean, text, staff_role, uuid)
  from anon, public;

-- ===== 3. מחיקת משאית לצמיתות מנקה גם אותה ===============================
--
-- הגוף זהה ל-0141 מילה במילה, בתוספת שורה אחת בענף `trucks`. בלעדיה מחיקה
-- לצמיתות של משאית שנהג של קבלן משובץ עליה הייתה נופלת על ה-FK, ורשת
-- הביטחון של 0137 הייתה מחזירה את שם האילוץ במקום לנקות.
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
    -- ‏0154: ולעובד הקבלן — ניקוי ולא מחיקה. שורת השיבוץ שלו נושאת גם תפקיד
    -- ואתר עבודה, ומחיקת משאית אינה סיבה להוריד אותו מהמשימה.
    update task_contractor_workers set truck_id = null where truck_id = p_id;
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
  'מחיקה לצמיתות מסל המיחזור (0124/0137/0141). מ-0154 מחיקת משאית מנקה גם '
  'את שורות עובדי הקבלן שנסעו בה, ומשאירה אותם על המשימה בלי משאית.';
