-- 0160: מנהל מערכת מוחק משתמש לצמיתות
--
-- הבקשה: **"שתהיה אפשרות למנהל מערכת למחוק משתמשים לצמיתות מהמערכת."**
--
-- מה היה. למסך העובדים לא הייתה מחיקה בכלל — רק מתג "משתמש פעיל" ומחיקת
-- חשבון ההתחברות. סל המיחזור (0124) אמנם מציג `profiles` בשם "משתמשים",
-- אבל שני דברים חסמו את הדרך אליו ובתוכו:
--
--   1. **אי אפשר היה להכניס משתמש לסל.** ‏`soft_delete` תמכה ב-`profiles`
--      מאז 0012, אך אף מסך לא קרא לה עם הטבלה הזו.
--   2. **ומי שכן הגיע לסל נחסם.** ‏0137 רשמה `profiles` ברשימת החסימות:
--      נוכחות, שיבוצים, אירועים ומשימות שיצר. זה תיאור מדויק של כל עובד
--      אמיתי, כלומר "מחיקה לצמיתות" עבדה רק על שורה שמעולם לא עשתה דבר.
--
-- **ההכרעה: חשבון אינו היסטוריה.** ‏0137 חסמה בצדק לקוח שיש לו אירועים —
-- מחיקתו הייתה מוחקת את האירועים עצמם. אצל אדם ההפרדה חדה יותר, ולכן היא
-- נעשית כאן במפורש, בשלוש קטגוריות:
--
--   1. **מה ששייך לו נמחק איתו.** משמרות הנוכחות שלו והשיבוצים שלו —
--      ‏`profile_id` בשתיהן הוא `not null`, כלומר אין להן קיום בלעדיו.
--      זה *כן* אובדן נתונים, והוא נאמר למנהל לפני הלחיצה: ‏`user_delete_impact`
--      מחזירה בדיוק כמה משמרות וכמה שיבוצים ילכו, והמסך מציג את המספרים
--      במשפט האישור. מחיקה שקטה של שכר עבר היא בדיוק מה שאסור כאן.
--   2. **מה שרק מצביע עליו מתאפס.** אירוע שהוא יצר, משימה שהוא יצר, קבלה
--      שהוא רשם, משמרת של מישהו אחר שהוא ערך או אישר — כל אלה הם ההיסטוריה
--      של המשרד ולא שלו. השורה נשארת במקומה ומאבדת את השם בלבד.
--   3. **הרוסטר אינו נמחק.** שורת סגל אצל קבלן (`contractor_workers`) שורדת
--      את מחיקת החשבון, כמו ב-0149/0150: השורה שייכת לקבלן, והחשבון רק היה
--      מקושר אליה. מה שכן מתאפס הוא `contractor_workers.user_id` — הוא
--      מצביע ל-`auth.users` בלי `on delete`, ובלעדיו מחיקת חשבון ההתחברות
--      עצמו (בצד ה-Auth) הייתה נופלת על FK.
--
-- **הסל נשאר השער היחיד.** ‏`hard_delete` ממשיכה לדרוש `deleted_at is not
-- null` — מסך העובדים מוחק קודם רכות ורק אז לצמיתות, ולכן כישלון באמצע
-- משאיר את המשתמש בסל ולא במצב חצי-מחוק. ומה שנוסף: **אי אפשר למחוק את
-- עצמך.** ‏`admin-users` כבר אוסר את זה על השבתה ועל מחיקת התחברות, ואין
-- סיבה שהמחיקה החמורה מכולן תהיה הפרצה שדרכה מנהל מוחק את החשבון שהוא
-- מחובר בו כרגע.
--
-- **‏`app.system_write` סביב האיפוסים, ולא בגלל RLS.** ‏`events_approval_guard`
-- (0115) זורקת על כל שינוי ב-`approved_by` שאינו עובר דרך `set_event_approved`,
-- ובלי הדגל הזה מחיקת מנהל שאישר אירוע אחד הייתה נופלת עליו. אותו דגל גם
-- משתיק את `enforce_field_perms` ואת שומר הנוכחות, כמו ב-`soft_delete`.
--
-- **חשבון ההתחברות נמחק בצד ה-Auth.** ‏`auth.users` אינו נגזרת של המסד הזה
-- ואין מיגרציה שנוגעת בו: ‏`admin-users` מוחק אותו ב-service role מיד אחרי
-- שהפונקציה כאן חזרה בשלום, כמו בכל שאר פעולות ההתחברות.

create or replace function hard_delete(p_table text, p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_ok    boolean;
  v_block text;
  v_uid   uuid;
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

  -- ‏0160: החשבון שאתה מחובר בו אינו נתון למחיקה, גם כשאתה מנהל מערכת.
  if p_table = 'profiles' and p_id = app.profile_id() then
    raise exception 'לא ניתן למחוק את המשתמש שלך עצמך' using errcode = '42501';
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
    -- ורק אז היומן עצמו. פירוט הנימוק בראש הקובץ של 0141.
    delete from event_suppliers where event_id = p_id;
    delete from event_contacts  where event_id = p_id;
    delete from event_activity  where event_id = p_id;

  elsif p_table = 'profiles' then
    -- ‏0160: החשבון יורד, ההיסטוריה של המשרד נשארת בלי השם.
    select user_id into v_uid from profiles where id = p_id;

    -- ‏`events_approval_guard`,‏ `enforce_field_perms` ושומר הנוכחות מכריעים
    -- לפי מי שכותב; כאן כותבת המחיקה עצמה. ראו ראש הקובץ.
    perform app.system_write(true);

    -- 1. ייחוס מתאפס: השורה נשארת, השם יורד ממנה.
    update events             set created_by  = null where created_by  = p_id;
    update events             set approved_by = null where approved_by = p_id;
    update tasks              set created_by  = null where created_by  = p_id;
    update receipts           set created_by  = null where created_by  = p_id;
    update attendance_entries set created_by  = null where created_by  = p_id;
    update attendance_entries set edited_by   = null where edited_by   = p_id;
    update attendance_entries set reviewed_by = null where reviewed_by = p_id;
    update attendance_entry_bonus set created_by = null where created_by = p_id;
    update dashboard_layouts  set updated_by  = null where updated_by  = p_id;
    update dashboard_widgets  set shared_by   = null where shared_by   = p_id;

    -- 2. מה ששייך לו הולך איתו. ‏`attendance_entry_bonus` יורדת בקסקייד
    --    מהמשמרת, ושורות המחיקה נרשמות ב-audit_log כמו כל מחיקה אחרת.
    delete from task_assignments   where profile_id = p_id;
    delete from attendance_entries where profile_id = p_id;

    -- 3. ‏`notify_assignment_removed` כותב לו "השיבוץ שלך בוטל" על כל שיבוץ
    --    שנמחק כאן. השורות האלה ממילא יורדות בקסקייד עם הפרופיל, אבל הן
    --    נמחקות מפורשות לפניו כדי שתור המשלוח לא ייצא לדרך עם מייל לאדם
    --    שנמחק ברגע זה.
    delete from notifications where recipient_id = p_id;

    -- 4. הקישור מהרוסטר לחשבון ההתחברות. שורת הסגל עצמה נשארת אצל הקבלן
    --    (0149/0150); מה שמתאפס הוא ההצבעה ל-`auth.users`, שאין לה
    --    ‏`on delete` — ובלעדיה מחיקת ההתחברות ב-`admin-users` נופלת על FK.
    if v_uid is not null then
      update contractor_workers set user_id = null where user_id = v_uid;
    end if;

    perform app.system_write(false);

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
  'מחיקה לצמיתות מסל המיחזור (0124/0137/0141). מ-0160 היא יודעת גם למחוק '
  'משתמש: מה ששייך לו (משמרות, שיבוצים) יורד איתו, מה שרק מצביע עליו '
  '(אירוע/משימה/קבלה שיצר) מתאפס, ושורת הסגל אצל הקבלן נשארת.';

-- ===========================================================================
-- מה תעלה המחיקה — נאמר לפני הלחיצה, ולא אחריה
--
-- ‏`confirm` שכתוב בו "לא ניתן לשחזר" אינו אומר *מה* לא ניתן לשחזר. הפונקציה
-- הזו מחזירה את המספרים שמסך העובדים משבץ במשפט האישור: כמה משמרות וכמה
-- שיבוצים יימחקו (אלה ההפסדים), וכמה אירועים, משימות וקבלות יישארו בלי שם
-- היוצר (אלה לא). היא קריאה בלבד, ולכן היא זמינה גם למי שרק שוקל למחוק.
-- ===========================================================================

create or replace function user_delete_impact(p_profile uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_row profiles; v_out jsonb;
begin
  if not app.is_admin() then
    raise exception 'רק מנהל מערכת יכול למחוק משתמש לצמיתות' using errcode = '42501';
  end if;

  select * into v_row from profiles where id = p_profile;
  if not found then
    raise exception 'המשתמש לא נמצא';
  end if;

  select jsonb_build_object(
    'full_name',   v_row.full_name,
    'is_self',     p_profile = app.profile_id(),
    'has_login',   v_row.user_id is not null,
    -- יורד עם המשתמש
    'shifts',      (select count(*) from attendance_entries where profile_id = p_profile),
    'assignments', (select count(*) from task_assignments   where profile_id = p_profile),
    -- נשאר, בלי שם היוצר
    'events_created', (select count(*) from events   where created_by = p_profile),
    'tasks_created',  (select count(*) from tasks    where created_by = p_profile),
    'receipts',       (select count(*) from receipts where created_by = p_profile)
  ) into v_out;

  return v_out;
end $$;

revoke all on function user_delete_impact(uuid) from public;
grant execute on function user_delete_impact(uuid) to authenticated;

comment on function user_delete_impact(uuid) is
  'מה תעלה מחיקת המשתמש לצמיתות (0160): מה יימחק איתו (משמרות, שיבוצים) '
  'ומה יישאר בלי שם היוצר (אירועים, משימות, קבלות). מנהל מערכת בלבד.';
