-- 0091: מנהל הקבלן — לו״ז נקי, תמחור לפי עובד, וסמכות על הסגל שלו
--
-- אוסף שינויים שכולם נוגעים באותו קהל: מנהל הקבלן והסגל שלו. חמישה נושאים,
-- כולם על ההבחנה בין "מה שהמשרד עושה" ל"מה שהקבלן עושה":
--
--   1. הלו״ז של מנהל הקבלן נקי מכלי המשרד — בלי סינון ובלי פתיחת כרטיס משימה
--      לעריכה, בדיוק כפי שנעשה לעובד השטח ב-0079. לחיצה על שם הלקוח מובילה
--      לאירוע ולא לעריכה.
--   2. התמחור לקבלן נגזר מ"סכום לעובד" כפול מספר העובדים שהקבלן שיבץ בפועל,
--      עם ברירת מחדל לקבלן ודריסה למשימה.
--   3. נקודת ההתחלה של הקבלן (שטח/מחסן) נשמרת על ה-terms וחלה אוטומטית על
--      עובדיו.
--   4. מנהל הקבלן מאשר דיווח נוכחות ידני של עובד מהסגל שלו — ורק שלו.
--   5. מנהל הקבלן רואה את כל המשובצים למשימה שהואצלה אליו (כולל אנשי משרד),
--      לקריאה בלבד.
--
-- ובנוסף תיקון: אריח "חסרים עובדים" בדשבורד ספר רק את `task_assignments` והתעלם
-- מעובדי הקבלן, ולכן משימה שהקבלן איישָׁ נותרה "חסרה". התיקון סופר את שניהם,
-- כמו שלוח המשמרות כבר עושה.

-- ===== 1. עמודות: תעריף לעובד, ונקודת התחלה לקבלן =========================
--
-- ‏`contractors.price_per_worker` הוא ברירת המחדל של הקבלן; אותו שדה על
-- ‏`task_contractor_terms` הוא דריסה למשימה בודדת. `default_task_price` הישן
-- נשאר כמחיר-משימה שטוח למי שאינו מתמחר לפי עובד — שני המצבים חיים זה לצד זה.
-- ‏`task_contractor_terms.work_site` היא נקודת ההתחלה שהמשרד קובע לקבלן,
-- שממנה יורשים עובדיו.
-- הגדרות התמחור בכרטיס הקבלן. `default_task_price` הקיים הוא "מחיר בסיס
-- למשימה". נוספים: תעריף-לעובד, תוספת הגעה למחסן, מחיר למשימת הובלה בלבד,
-- וקנסות איחור/אי-התייצבות. הקנסות והתוספות נשמרים כהגדרה; אופן החלתם על
-- התשלום בפועל נקבע בהמשך (ראו סיכום המשימה).
alter table contractors
  add column if not exists price_per_worker numeric(12,2),
  add column if not exists warehouse_arrival_surcharge numeric(12,2),
  add column if not exists transport_only_price numeric(12,2),
  add column if not exists lateness_penalty numeric(12,2),
  add column if not exists no_show_penalty numeric(12,2);

-- האיחור מתייחס רק לעובדים ספציפיים שהוגדרו מסגל הקבלן.
alter table contractor_workers
  add column if not exists lateness_tracked boolean not null default false;

alter table task_contractor_terms
  add column if not exists price_per_worker numeric(12,2),
  add column if not exists work_site text not null default 'field'
    check (work_site in ('field', 'warehouse'));

comment on column contractors.price_per_worker is
  'ברירת מחדל: הסכום שהקבלן מקבל לכל עובד. null = תמחור לפי מחיר-משימה שטוח.';
comment on column contractors.warehouse_arrival_surcharge is
  'תוספת קבועה לתשלום הקבלן כשהמשימה מתחילה במחסן.';
comment on column contractors.transport_only_price is
  'מחיר למשימה שהיא הובלה בלבד, במקום מחיר הבסיס.';
comment on column contractors.lateness_penalty is
  'סכום הקנס לאיחור של עובד שסומן למעקב איחורים.';
comment on column contractors.no_show_penalty is
  'סכום הקנס לאי-התייצבות של עובד.';
comment on column contractor_workers.lateness_tracked is
  'האם קנס האיחור של הקבלן חל על העובד הזה.';
comment on column task_contractor_terms.price_per_worker is
  'דריסת התעריף-לעובד למשימה זו. null = יורש מ-contractors.price_per_worker.';
comment on column task_contractor_terms.work_site is
  'נקודת ההתחלה שהמשרד קבע לקבלן במשימה. חלה אוטומטית על עובדי הקבלן.';

-- ===== 2. תמחור לפי עובד ==================================================
--
-- ‏המחיר = תעריף-לעובד (דריסת המשימה, אחרת ברירת המחדל של הקבלן) כפול מספר
-- העובדים שהקבלן שיבץ בפועל. שורה ששולמה מוגנת (0057) ואינה מחושבת מחדש; קבלן
-- בתמחור שטוח (אין תעריף-לעובד בשני המקומות) אינו מושפע כלל.

create or replace function app.recompute_contractor_price(p_task_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_rate  numeric;
  v_count int;
  v_prev  boolean;
begin
  -- התעריף האפקטיבי, ורק לשורה שטרם שולמה. שורה ששולמה מחזירה null כאן
  -- (בגלל `paid_at is null`) ולכן יוצאים בלי לגעת בה.
  select coalesce(tct.price_per_worker, ct.price_per_worker) into v_rate
    from task_contractor_terms tct
    join contractors ct on ct.id = tct.contractor_id
   where tct.task_id = p_task_id and tct.paid_at is null;
  if v_rate is null then return; end if;   -- תמחור שטוח, או שורה מוגנת — לא נוגעים

  select count(*) into v_count from task_contractor_workers where task_id = p_task_id;

  v_prev := app.in_system_write();
  perform app.system_write(true);
  update task_contractor_terms
     set price = round(v_rate * v_count, 2)
   where task_id = p_task_id;
  perform app.system_write(v_prev);
end $$;

comment on function app.recompute_contractor_price(uuid) is
  'מחשב מחדש את מחיר הקבלן למשימה = תעריף-לעובד × מספר העובדים שהקבלן שיבץ בפועל.';

-- שיבוץ/הסרה של עובד קבלן משנה את המספר, ולכן את המחיר.
create or replace function app.tcw_price_sync()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  perform app.recompute_contractor_price(coalesce(new.task_id, old.task_id));
  return coalesce(new, old);
end $$;

drop trigger if exists tcw_price_sync on task_contractor_workers;
create trigger tcw_price_sync after insert or delete on task_contractor_workers
for each row execute function app.tcw_price_sync();

-- שינוי דריסת התעריף על המשימה → חישוב מחדש של אותה משימה. הטריגר תלוי-עמודה,
-- ולכן עדכון ה-price ע״י החישוב עצמו אינו מפעיל אותו שוב.
create or replace function app.tct_rate_sync()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.price_per_worker is distinct from old.price_per_worker then
    perform app.recompute_contractor_price(new.task_id);
  end if;
  return new;
end $$;

drop trigger if exists tct_rate_sync on task_contractor_terms;
create trigger tct_rate_sync after update of price_per_worker on task_contractor_terms
for each row execute function app.tct_rate_sync();

-- שינוי ברירת המחדל של הקבלן → חישוב מחדש לכל משימותיו שאין להן דריסה משלהן
-- ושטרם שולמו.
create or replace function app.contractor_rate_sync()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.price_per_worker is distinct from old.price_per_worker then
    perform app.recompute_contractor_price(tct.task_id)
       from task_contractor_terms tct
      where tct.contractor_id = new.id
        and tct.paid_at is null
        and tct.price_per_worker is null;
  end if;
  return new;
end $$;

drop trigger if exists contractor_rate_sync on contractors;
create trigger contractor_rate_sync after update of price_per_worker on contractors
for each row execute function app.contractor_rate_sync();

-- בעת האצלה המחיר נזרע לפי מצב זה: בתמחור לפי עובד — 0 (טרם שובצו עובדים);
-- בתמחור שטוח — `default_task_price` כפי שהיה. הגוף זהה ל-0057 פרט לקריאה
-- ל-recompute בסופו, שהופכת את הזריעה לתלוית-מצב.
create or replace function app.sync_contractor_terms()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'UPDATE' and old.contractor_id is not null
     and old.contractor_id is distinct from new.contractor_id
     and exists (select 1 from task_contractor_terms
                  where task_id = new.id and paid_at is not null) then
    raise exception 'לא ניתן להסיר או להחליף קבלן במשימה שכבר שולם עליה. בטל תחילה את סימון התשלום בכרטיס הקבלן.';
  end if;
  perform app.system_write(true);
  if new.contractor_id is not null and
     (tg_op = 'INSERT' or old.contractor_id is distinct from new.contractor_id) then
    insert into task_contractor_terms (task_id, contractor_id, price)
    values (new.id, new.contractor_id,
            coalesce((select default_task_price from contractors where id = new.contractor_id), 0))
    on conflict (task_id) do update
      set contractor_id = excluded.contractor_id, price = excluded.price,
          paid_at = null, paid_amount = null;
    if tg_op = 'UPDATE' and old.contractor_id is not null then
      delete from task_contractor_workers where task_id = new.id;
    end if;
    -- אם לקבלן תעריף-לעובד, המחיר נגזר מהספירה (0 בעת ההאצלה) ולא מהשטוח.
    perform app.recompute_contractor_price(new.id);
  elsif new.contractor_id is null and tg_op = 'UPDATE' and old.contractor_id is not null then
    delete from task_contractor_terms where task_id = new.id;
    delete from task_contractor_workers where task_id = new.id;
  end if;
  perform app.system_write(false);
  return new;
end $$;

-- ===== 3. נקודת ההתחלה של הקבלן חלה על עובדיו =============================
--
-- כשהמשרד קובע לקבלן שטח/מחסן, זה חל אוטומטית על עובדיו: שינוי `work_site`
-- על ה-terms מתפשט לכל עובדי הקבלן שכבר שובצו למשימה.
create or replace function app.tct_worksite_sync()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.work_site is distinct from old.work_site then
    perform app.system_write(true);
    update task_contractor_workers set work_site = new.work_site where task_id = new.task_id;
    perform app.system_write(false);
  end if;
  return new;
end $$;

drop trigger if exists tct_worksite_sync on task_contractor_terms;
create trigger tct_worksite_sync after update of work_site on task_contractor_terms
for each row execute function app.tct_worksite_sync();

-- ‏`contractor_assign_worker`: ברירת המחדל של נקודת ההתחלה נגזרת מ-terms של
-- המשימה במקום מ-'field' קבוע, כך שעובד חדש יורש את מה שהמשרד קבע לקבלן.
-- ‏קורא שנוקב במפורש בנקודה גובר. שאר הגוף זהה ל-0072.
create or replace function contractor_assign_worker(
  p_task_id uuid,
  p_worker_id uuid default null,
  p_profile_id uuid default null,
  p_on boolean default true,
  p_work_site text default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_task_ctr uuid;
  v_mine     uuid := app.contractor_id();
  v_worker   uuid := p_worker_id;
  v_prof     profiles%rowtype;
  v_site     text := p_work_site;
begin
  if not (app.has('portal.assign_workers') or app.has('contractors.assign_workers')) then
    raise exception 'אין לך הרשאה לשבץ עובדי קבלן' using errcode = '42501';
  end if;

  -- ברירת המחדל: נקודת ההתחלה שהמשרד קבע לקבלן במשימה (0091), ואם לא נקבעה — שטח.
  if v_site is null then
    select coalesce(work_site, 'field') into v_site
      from task_contractor_terms where task_id = p_task_id;
    v_site := coalesce(v_site, 'field');
  end if;
  if v_site not in ('field', 'warehouse') then
    raise exception 'אתר עבודה לא חוקי: %', v_site using errcode = '22023';
  end if;

  select contractor_id into v_task_ctr
    from tasks where id = p_task_id and deleted_at is null;
  if v_task_ctr is null then
    raise exception 'המשימה לא נמצאה או שאינה מואצלת לקבלן' using errcode = '42501';
  end if;
  -- קבלן משבץ רק במשימות שלו; איש משרד צריך את המפתח המשרדי לכל קבלן.
  if v_task_ctr is distinct from v_mine then
    perform app.require('contractors.assign_workers');
  end if;

  -- פתרון הגשר: חשבון שנרשם תחת הקבלן ואין לו שורת רוסטר מקבל אחת עכשיו.
  if v_worker is null then
    if p_profile_id is null then
      raise exception 'חובה לנקוב בעובד או בחשבון' using errcode = '22023';
    end if;
    select * into v_prof from profiles
     where id = p_profile_id and deleted_at is null;
    if v_prof.id is null or v_prof.contractor_id is distinct from v_task_ctr then
      raise exception 'העובד אינו רשום תחת הקבלן של המשימה' using errcode = '42501';
    end if;
    v_worker := v_prof.contractor_worker_id;
    if v_worker is null then
      insert into contractor_workers (contractor_id, full_name, phone)
      values (v_task_ctr, v_prof.full_name, v_prof.phone)
      returning id into v_worker;
      update profiles set contractor_worker_id = v_worker where id = v_prof.id;
    end if;
  end if;

  -- העובד חייב להיות של הקבלן שהמשימה הואצלה אליו.
  if not exists (select 1 from contractor_workers cw
                  where cw.id = v_worker and cw.contractor_id = v_task_ctr
                    and cw.deleted_at is null) then
    raise exception 'העובד אינו בסגל של הקבלן שהמשימה הואצלה אליו' using errcode = '42501';
  end if;

  if p_on then
    insert into task_contractor_workers (task_id, contractor_worker_id, work_site)
    values (p_task_id, v_worker, v_site)
    on conflict (task_id, contractor_worker_id) do update set work_site = excluded.work_site;
  else
    delete from task_contractor_workers
     where task_id = p_task_id and contractor_worker_id = v_worker;
  end if;

  return v_worker;
end $$;

revoke execute on function
  public.contractor_assign_worker(uuid, uuid, uuid, boolean, text) from anon, public;

comment on function public.contractor_assign_worker(uuid, uuid, uuid, boolean, text) is
  'שיבוץ/הסרה של עובד קבלן במשימה. נקודת ההתחלה יורשת מ-terms של המשימה כשלא נמסרה.';

-- ===== 4. הלו״ז של מנהל הקבלן נקי מכלי המשרד ==============================
--
-- בדיוק כמו רצפת העובד ב-0079 §2ב: דחייה מפורשת ל-board.filter ול-
-- board.open_task. הלקוח כבר מגדר עליהם (canFilter/canOpenTask), ולכן אין
-- שינוי דפדפן — הסינון נעלם, ולחיצה על שם הלקוח מובילה לאירוע ולא לעריכה.
insert into role_permissions (role_id, permission_key, allowed)
select r.id, k, false
from permission_roles r,
     unnest(array['board.filter', 'board.open_task']) k
where r.key = 'contractor_manager'
on conflict (role_id, permission_key) do update set allowed = false;

-- ===== 5. מנהל הקבלן מאשר דיווח של הסגל שלו ================================
--
-- מפתח ייעודי, ולא `attendance.approve_entry` המשרדי: זה מתיר אישור *כל*
-- דיווח, בעוד שהזרוע כאן מוגבלת בגוף ה-RPC לעובדי הקבלן של המאשר בלבד.
select app.register_permission('portal.approve_attendance', 'portal',
  'אישור דיווחי נוכחות של הסגל',
  'מנהל קבלן מאשר או דוחה דיווח נוכחות ידני של עובד מהסגל שלו',
  'action', false, false,
  array['contractor_user']::user_kind[], null, 35);

insert into role_permissions (role_id, permission_key, allowed)
select r.id, 'portal.approve_attendance', true
from permission_roles r where r.key = 'contractor_manager'
on conflict (role_id, permission_key) do update set allowed = true;

-- ‏`attendance_review_entry`: הרשומה נקראת לפני שער ההרשאה כדי שהזרוע תוכל
-- לבחון את בעל הדיווח. מפתח משרדי מלא מאשר כל דיווח; מנהל קבלן מאשר רק דיווח
-- של עובד ששייך לקבלן שלו. שאר הגוף זהה ל-0024.
create or replace function attendance_review_entry(
  p_id uuid, p_approve boolean, p_note text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_e     attendance_entries;
  v_clash uuid;
  v_prev  boolean;
begin
  select * into v_e from attendance_entries where id = p_id and deleted_at is null;
  if v_e.id is null then
    raise exception 'רשומת הנוכחות לא נמצאה';
  end if;

  -- שער ההרשאה: מפתח משרדי מלא, או מנהל קבלן על עובד מהסגל שלו.
  if not app.has('attendance.approve_entry') then
    if not (app.has('portal.approve_attendance')
            and app.contractor_id() is not null
            and exists (select 1 from profiles p
                         where p.id = v_e.profile_id
                           and p.contractor_id = app.contractor_id())) then
      perform app.require('attendance.approve_entry');
    end if;
  end if;

  if v_e.status <> 'pending' then
    raise exception 'הדיווח כבר טופל';
  end if;
  if not p_approve and coalesce(nullif(p_note, ''), '') = '' then
    raise exception 'דחייה מחייבת נימוק';
  end if;

  -- החפיפה נבדקת שוב ולא רק בהגשה: מאז שהדיווח הוגש יכולה הייתה להיווצר
  -- החתמת שעון על אותן שעות, ואישור עיוור היה משלם עליהן פעמיים.
  if p_approve then
    v_clash := app.attendance_overlap(v_e.profile_id, v_e.clock_in_at, v_e.clock_out_at, v_e.id);
    if v_clash is not null then
      raise exception 'לא ניתן לאשר: קיימת רשומת נוכחות אחרת שחופפת לשעות האלה';
    end if;
  end if;

  v_prev := app.in_system_write();
  perform app.system_write(true);
  update attendance_entries
     set status = case when p_approve then 'approved' else 'rejected' end,
         manager_note = coalesce(nullif(p_note, ''), manager_note),
         reviewed_by = app.profile_id(),
         reviewed_at = now()
   where id = p_id;
  perform app.system_write(v_prev);

  perform app.notify(v_e.profile_id,
    case when p_approve then 'attendance_approved' else 'attendance_rejected' end,
    case when p_approve then 'דיווח הנוכחות אושר' else 'דיווח הנוכחות נדחה' end,
    to_char(v_e.work_date, 'DD/MM/YYYY') ||
      case when nullif(p_note, '') is not null then ' — ' || p_note else '' end,
    'attendance_entry', p_id);

  return jsonb_build_object('ok', true, 'entry_id', p_id,
                            'status', case when p_approve then 'approved' else 'rejected' end);
end $$;

-- ===== 6. מנהל הקבלן רואה את כל המשובצים למשימה שלו =======================
--
-- זרוע קבלן לפוליסות הראייה, מקבילה לזרוע הלקוח של 0066 §5: מנהל קבלן שמחזיק
-- board.view_staffing רואה מי משובץ למשימה שהואצלה אליו — כולל אנשי משרד —
-- ואת שמותיהם, בלי זכות שיבוץ. הבדיקות ב-security definer מאותה סיבה: הימנעות
-- מרקורסיה הדדית בין ta_select ל-tasks_select.
create or replace function app.assignment_on_my_contractor(p_task_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select app.contractor_id() is not null
     and exists (select 1 from tasks t
                  where t.id = p_task_id and t.deleted_at is null
                    and t.contractor_id = app.contractor_id())
$$;

create or replace function app.staff_on_my_contractor(p_profile_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select app.contractor_id() is not null
     and exists (select 1 from task_assignments a
                 join tasks t on t.id = a.task_id and t.deleted_at is null
                  where a.profile_id = p_profile_id
                    and t.contractor_id = app.contractor_id())
$$;

drop policy ta_select on task_assignments;
create policy ta_select on task_assignments for select to authenticated using (
  (select app.is_admin())
  or ((select app.user_kind()) = 'staff' and (select app.has_permission('tasks', 'view')))
  or profile_id = (select app.profile_id())
  or ((select app.user_kind()) = 'customer_user'
      and (select app.has('board.view_staffing'))
      and (select app.assignment_on_my_customer(task_id)))
  or ((select app.user_kind()) = 'contractor_user'
      and (select app.has('board.view_staffing'))
      and (select app.assignment_on_my_contractor(task_id))));

drop policy profiles_select on profiles;
create policy profiles_select on profiles for select to authenticated using (
  (select app.is_admin())
  or user_id = (select auth.uid())
  or (deleted_at is null and (
    ((select app.user_kind()) = 'staff' and user_kind = 'staff')
    or ((select app.user_kind()) = 'customer_user' and customer_id = (select app.customer_id()))
    or ((select app.user_kind()) = 'customer_user'
        and (select app.has('board.view_staffing'))
        and (select app.staff_on_my_customer(profiles.id)))
    or ((select app.user_kind()) = 'contractor_user'
        and (select app.has('board.view_staffing'))
        and (select app.staff_on_my_contractor(profiles.id))))));

-- ===== 6ב. עובד קבלן אינו רואה את מסך הכספים ==============================
--
-- ברירת המחדל של הסוג `contractor_user` הדליקה את `portal.*` לכולם (0011),
-- ולכן עובד קבלן ראה את פורטל הכספים אלא אם התפקיד הצר `contractor_worker`
-- דחה אותו במפורש (0019). חשבון שנוצר בלי אותו תפקיד — או שקיבל רק את גשר
-- ה-`contractor_worker_id` דרך שיבוץ — נפל חזרה לברירת המחדל של הסוג וראה את
-- הכספים.
--
-- ההיפוך: מפתחות הפורטל אינם ניתנים עוד בברירת המחדל של הסוג, אלא רק בתפקיד
-- `contractor_manager` במפורש (0011:443, layer 3). מנהל הקבלן אינו מאבד דבר —
-- ההרשאה שלו מגיעה מהתפקיד, לא מהסוג — ואילו עובד הקבלן (וכל חשבון בלי תפקיד
-- מנהל) חסום כברירת מחדל, לא כחריג. `portal.attendance` נשאר כפי שהוא: הוא
-- מסך המשמרות של הסגל, לא הכספים.
update kind_permission_defaults set allowed = false
 where user_kind = 'contractor_user'
   and permission_key in ('portal.view', 'portal.view_financials',
                          'portal.assign_workers', 'portal.manage_workers');

-- ===== 7. אריח "חסרים עובדים" סופר גם את עובדי הקבלן ======================
-- (הגדרת dashboard_sections מ-0090, עם התיקון בזרוע tasks.understaffed —
--  ראו הסימון למטה. הפונקציה משוכפלת במלואה כי Postgres מחליף פונקציה שלמה.)

-- ===== 8. work_board_view מחזיר את מחיר הקבלן =============================
-- (הגדרת ה-view מ-0079, עם עמודת contractor_price — ראו הסימון למטה.)

create or replace function dashboard_sections(
  p_sections text[], p_from date, p_to date, p_opts jsonb default '{}'::jsonb)
returns jsonb language plpgsql stable security invoker set search_path = public as $$
declare
  v_key    text;
  v_out    jsonb := '{}'::jsonb;
  v_bucket text := case when p_opts ->> 'bucket' in ('day','week','month')
                        then p_opts ->> 'bucket' else 'week' end;
  v_limit  int  := greatest(1, least(coalesce((p_opts ->> 'limit')::int, 12), 50));
  v_val    jsonb;
  v_m      jsonb;
  v_pct    numeric;
  v_margin boolean := app.has_all(array['dashboard.margin','dashboard.payroll',
                                        'dashboard.contractor_cost','pricing.revenue']);
  v_scoped boolean := exists (select 1 from app.scope_rows('tasks') where scope_type <> 'all');
begin
  if p_from is null or p_to is null then
    raise exception 'חסר טווח תאריכים' using errcode = '22023';
  end if;
  if p_to < p_from then
    raise exception 'טווח תאריכים הפוך' using errcode = '22023';
  end if;
  if p_to - p_from > 400 then
    raise exception 'טווח גדול מדי לדשבורד' using errcode = '22023';
  end if;
  -- 50 ולא 48: שני כרטיסי הצי של 0090 הצטרפו לרשימה שפריסה רחבה יכולה לבקש.
  if coalesce(array_length(p_sections, 1), 0) > 50 then
    raise exception 'יותר מדי סקשנים בבקשה אחת' using errcode = '22023';
  end if;

  foreach v_key in array coalesce(p_sections, '{}'::text[]) loop
    v_val := null;

    if v_key = 'revenue.trend' and app.has('pricing.revenue') then
      select coalesce(jsonb_agg(row_to_json(x) order by x.bucket), '[]') into v_val from (
        select u.bucket, round(sum(u.total), 2) as total from (
          select date_trunc(v_bucket, t.task_date)::date as bucket, sum(tp.price) as total
            from task_pricing tp
            join tasks t on t.id = tp.task_id and t.deleted_at is null
           where t.task_date between p_from and p_to
           group by 1
          union all
          select date_trunc(v_bucket, e.event_date)::date, sum(ei.amount)
            from event_income ei
            join events e on e.id = ei.event_id and e.deleted_at is null
           where e.event_date between p_from and p_to
           group by 1) u
         group by u.bucket) x;

    elsif v_key = 'revenue.forecast' and app.has('pricing.revenue') then
      select jsonb_build_object(
        'total', round(coalesce(sum(tp.price), 0)
                       + coalesce((select sum(ei.amount)
                                     from event_income ei
                                     join events e on e.id = ei.event_id and e.deleted_at is null
                                    where e.event_date > current_date), 0), 2),
        'tasks', count(*),
        'by_month', (select coalesce(jsonb_agg(row_to_json(y) order by y.bucket), '[]') from (
            select u.bucket, round(sum(u.total), 2) as total from (
              select date_trunc('month', t2.task_date)::date as bucket, sum(tp2.price) as total
                from task_pricing tp2
                join tasks t2 on t2.id = tp2.task_id and t2.deleted_at is null
               where t2.task_date > current_date
               group by 1
              union all
              select date_trunc('month', e2.event_date)::date, sum(ei2.amount)
                from event_income ei2
                join events e2 on e2.id = ei2.event_id and e2.deleted_at is null
               where e2.event_date > current_date
               group by 1) u
             group by u.bucket) y))
        into v_val
        from task_pricing tp
        join tasks t on t.id = tp.task_id and t.deleted_at is null
       where t.task_date > current_date;

    elsif v_key = 'pricing.quality' and app.has('pricing.view') then
      select jsonb_build_object(
        'total',    count(*),
        'unpriced', count(*) filter (where tp.task_id is null or tp.price = 0),
        'manual',   count(*) filter (where tp.is_manual),
        'auto',     count(*) filter (where tp.task_id is not null and not tp.is_manual and tp.price > 0),
        'unpriced_list', (select coalesce(jsonb_agg(row_to_json(y)), '[]') from (
            select t2.id, t2.task_date, coalesce(c2.name, t2.title, tt2.name) as label
              from tasks t2
              left join task_pricing tp2 on tp2.task_id = t2.id
              left join customers c2 on c2.id = t2.customer_id
              left join task_types tt2 on tt2.id = t2.task_type_id
             where t2.deleted_at is null and t2.task_date between p_from and p_to
               and (tp2.task_id is null or tp2.price = 0)
             order by t2.task_date desc limit 8) y))
        into v_val
        from tasks t
        left join task_pricing tp on tp.task_id = t.id
       where t.deleted_at is null and t.task_date between p_from and p_to;

    elsif v_key = 'cost.contractor' and app.has('dashboard.contractor_cost') then
      select jsonb_build_object(
        'expected',   round(coalesce(sum(tct.price), 0), 2),
        'paid',       round(coalesce(sum(coalesce(tct.paid_amount, tct.price))
                              filter (where tct.paid_at is not null), 0), 2),
        'unpaid',     round(coalesce(sum(tct.price) filter (where tct.paid_at is null), 0), 2),
        'unpaid_rows', count(*) filter (where tct.paid_at is null),
        'zero_rows',   count(*) filter (where tct.price = 0),
        'rows',        count(*),
        'aging', jsonb_build_object(
          'd0_30',  round(coalesce(sum(tct.price) filter (
                      where tct.paid_at is null and t.task_date > current_date - 30), 0), 2),
          'd31_60', round(coalesce(sum(tct.price) filter (
                      where tct.paid_at is null and t.task_date between current_date - 60 and current_date - 30), 0), 2),
          'd60',    round(coalesce(sum(tct.price) filter (
                      where tct.paid_at is null and t.task_date < current_date - 60), 0), 2)))
        into v_val
        from task_contractor_terms tct
        join tasks t on t.id = tct.task_id and t.deleted_at is null
       where t.task_date between p_from and p_to;

    elsif v_key = 'cost.by_contractor' and app.has('dashboard.contractor_cost') and app.has('contractors.view') then
      select coalesce(jsonb_agg(row_to_json(x)), '[]') into v_val from (
        select ct.name,
               round(sum(tct.price), 2) as expected,
               round(sum(coalesce(tct.paid_amount, tct.price)) filter (where tct.paid_at is not null), 2) as paid
          from task_contractor_terms tct
          join tasks t on t.id = tct.task_id and t.deleted_at is null
          join contractors ct on ct.id = tct.contractor_id
         where t.task_date between p_from and p_to
         group by ct.name order by 2 desc limit v_limit) x;

    elsif v_key = 'cost.contractor_unpaid' and app.has('dashboard.contractor_cost')
          and app.has('contractors.view_pricing') then
      select coalesce(jsonb_agg(row_to_json(x)), '[]') into v_val from (
        select t.id as task_id, t.task_date, ct.name as contractor, tct.price
          from task_contractor_terms tct
          join tasks t on t.id = tct.task_id and t.deleted_at is null
          join contractors ct on ct.id = tct.contractor_id
         where tct.paid_at is null and tct.price > 0 and t.task_date between p_from and p_to
         order by t.task_date limit v_limit) x;

    elsif v_key = 'cost.payroll' and app.has('dashboard.payroll') then
      v_val := app.payroll_summary(p_from, p_to);

    elsif v_key = 'cost.payroll_by_worker' and app.has('dashboard.payroll')
          and app.has('dashboard.all_workers') then
      v_val := app.payroll_by_worker(p_from, p_to, v_limit);

    elsif v_key = 'cost.payroll_trend' and app.has('dashboard.payroll') then
      v_val := app.payroll_trend(p_from, p_to, v_bucket);

    -- ── עלות מעביד: שכר מאושר כפול האחוז הגלובלי ─────────────────────────
    elsif v_key = 'cost.payroll_employer' and app.has('dashboard.payroll') then
      v_m := app.payroll_summary(p_from, p_to);
      v_pct := coalesce((select (value ->> 'pct')::numeric
                           from app_settings where key = 'finance.employer_cost'), 0);
      v_val := jsonb_build_object(
        'base',  v_m -> 'total',
        'pct',   v_pct,
        'total', round(coalesce((v_m ->> 'total')::numeric, 0) * (1 + v_pct / 100), 2),
        'unrated_shifts', v_m -> 'unrated_shifts');

    -- ── רווח גולמי: מימוש אחד, שני קוראים ─────────────────────────────────
    elsif v_key = 'margin.summary' and v_margin and not v_scoped then
      v_val := app.margin_summary(p_from, p_to);

    elsif v_key = 'margin.trend' and v_margin and not v_scoped then
      v_val := app.margin_trend(p_from, p_to, v_bucket);

    elsif v_key = 'margin.by_customer' and v_margin and not v_scoped and app.has('customers.view') then
      v_val := app.margin_by_customer(p_from, p_to, v_limit);

    -- ── סיכום רווח במתכונת המערכת הישנה: הכנסות − שכר×מעביד − קבלנים ─────
    -- אותו שער כמו margin.*: רווח הוא חיסור, ומי שרואה אותו רואה את הרכיבים.
    elsif v_key = 'finance.profit_summary' and v_margin and not v_scoped then
      v_m := app.margin_summary(p_from, p_to);
      v_pct := coalesce((select (value ->> 'pct')::numeric
                           from app_settings where key = 'finance.employer_cost'), 0);
      v_val := jsonb_build_object(
        'revenue',      v_m -> 'revenue',
        'payroll',      v_m -> 'payroll',
        'employer_pct', v_pct,
        'payroll_with_employer',
          round(coalesce((v_m ->> 'payroll')::numeric, 0) * (1 + v_pct / 100), 2),
        'contractor',   v_m -> 'contractor',
        'profit',
          round(coalesce((v_m ->> 'revenue')::numeric, 0)
                - coalesce((v_m ->> 'payroll')::numeric, 0) * (1 + v_pct / 100)
                - coalesce((v_m ->> 'contractor')::numeric, 0), 2),
        'pct', case when coalesce((v_m ->> 'revenue')::numeric, 0) > 0
                    then round((coalesce((v_m ->> 'revenue')::numeric, 0)
                                - coalesce((v_m ->> 'payroll')::numeric, 0) * (1 + v_pct / 100)
                                - coalesce((v_m ->> 'contractor')::numeric, 0))
                               / (v_m ->> 'revenue')::numeric * 100, 1) end,
        'unrated_shifts', v_m -> 'unrated_shifts',
        'excludes_overhead', true);

    -- ── הכנסות לפי קטגוריה ────────────────────────────────────────────────
    -- קטגוריה כבויה/מחוקה עם סכומים בטווח עדיין נספרת — ההיסטוריה אינה
    -- נעלמת כשמכבים קטגוריה.
    elsif v_key = 'income.by_category' and app.has('finance.income_view') then
      with cat as (
        select ic.id, ic.name, ic.family, ic.color, ic.sort_order,
               round(coalesce(sum(ei.amount) filter (where e.id is not null), 0), 2) as total
          from income_categories ic
          left join event_income ei on ei.category_id = ic.id
          left join events e on e.id = ei.event_id and e.deleted_at is null
               and e.event_date between p_from and p_to
         group by ic.id, ic.name, ic.family, ic.color, ic.sort_order
        having (ic.deleted_at is null and ic.is_active)
            or coalesce(sum(ei.amount) filter (where e.id is not null), 0) <> 0)
      select jsonb_build_object(
        'rows', coalesce((select jsonb_agg(row_to_json(c) order by c.sort_order) from cat c), '[]'::jsonb),
        'furniture_total', round(coalesce((select sum(total) from cat where family = 'furniture'), 0), 2),
        'logistics_total', round(coalesce((select sum(total) from cat where family = 'logistics'), 0), 2),
        'total', round(coalesce((select sum(total) from cat), 0), 2))
        into v_val;

    -- ── פילוח הכנסות: קטגוריה × לקוח, ותמחור המשימות כ"צוות" ─────────────
    elsif v_key = 'income.mix' and app.has('finance.income_view') and app.has('customers.view') then
      select coalesce(jsonb_agg(row_to_json(x)), '[]') into v_val from (
        select u.label, u.color, round(sum(u.total), 2) as total from (
          select ic.name || ' ' || c.name as label, ic.color as color, sum(ei.amount) as total
            from event_income ei
            join events e on e.id = ei.event_id and e.deleted_at is null
                 and e.event_date between p_from and p_to
            join customers c on c.id = e.customer_id
            join income_categories ic on ic.id = ei.category_id
           group by ic.name, c.name, ic.color
          union all
          select 'צוות ' || c.name, c.color, sum(tp.price)
            from task_pricing tp
            join tasks t on t.id = tp.task_id and t.deleted_at is null
                 and t.task_date between p_from and p_to
            join customers c on c.id = t.customer_id
           group by c.name, c.color) u
         group by u.label, u.color
        having sum(u.total) <> 0
         order by 3 desc limit v_limit) x;

    -- ── תשלום לוויפר: מה שהלקוחות חייבים, מה ששולם, והיתרה ───────────────
    -- owed = כל ההכנסות בטווח (ויפר גובה הכול ומעביר ללקוח את חלקו אחר כך);
    -- paid = תקבולים שנרשמו בטווח. שני השערים יחד: יתרה שנגזרת מחוב חלקי
    -- היא מספר שגוי, לא מספר חסר — התקדים של margin.
    elsif v_key = 'finance.receivables' and app.has('finance.receipts_view')
          and app.has('finance.income_view') then
      with rev as (
        select u.cid, sum(u.amount) as owed from (
          select e.customer_id as cid, ei.amount
            from event_income ei
            join events e on e.id = ei.event_id and e.deleted_at is null
           where e.event_date between p_from and p_to
          union all
          select t.customer_id, tp.price
            from task_pricing tp
            join tasks t on t.id = tp.task_id and t.deleted_at is null
           where t.task_date between p_from and p_to) u
         group by u.cid),
      rec as (
        select r.customer_id as cid, sum(r.amount) as paid, count(*) as cnt
          from receipts r
         where r.deleted_at is null and r.received_at between p_from and p_to
         group by r.customer_id)
      select jsonb_build_object(
        'owed',   round(coalesce((select sum(owed) from rev), 0), 2),
        'paid',   round(coalesce((select sum(paid) from rec), 0), 2),
        'unpaid', round(coalesce((select sum(owed) from rev), 0)
                        - coalesce((select sum(paid) from rec), 0), 2),
        'receipts_count', coalesce((select sum(cnt) from rec), 0),
        'by_customer', case when app.has('customers.view') then
          (select coalesce(jsonb_agg(row_to_json(y)), '[]') from (
             select c.name, c.color,
                    round(coalesce(v.owed, 0), 2) as owed,
                    round(coalesce(p.paid, 0), 2) as paid,
                    round(coalesce(v.owed, 0) - coalesce(p.paid, 0), 2) as unpaid
               from customers c
               left join rev v on v.cid = c.id
               left join rec p on p.cid = c.id
              where c.deleted_at is null and (v.cid is not null or p.cid is not null)
              order by 3 desc limit v_limit) y)
          else null end)
        into v_val;

    -- ── הכנסות ללקוח: חלקו של הלקוח, לפי ה-snapshot שנשמר על כל אירוע ─────
    elsif v_key = 'finance.client_share' and app.has('finance.income_view') then
      select jsonb_build_object(
        'total', round(coalesce(sum(ei.amount * (100 - ei.viper_share_pct) / 100), 0), 2),
        'rows', case when app.has('customers.view') then
          (select coalesce(jsonb_agg(row_to_json(y)), '[]') from (
             select c.name, c.color,
                    round(sum(ei2.amount * (100 - ei2.viper_share_pct) / 100), 2) as total
               from event_income ei2
               join events e2 on e2.id = ei2.event_id and e2.deleted_at is null
                    and e2.event_date between p_from and p_to
               join customers c on c.id = e2.customer_id
              group by c.name, c.color
             having sum(ei2.amount * (100 - ei2.viper_share_pct) / 100) <> 0
              order by 3 desc limit v_limit) y)
          else null end)
        into v_val
        from event_income ei
        join events e on e.id = ei.event_id and e.deleted_at is null
       where e.event_date between p_from and p_to;

    elsif v_key = 'tasks.by_type' then
      select coalesce(jsonb_agg(row_to_json(x)), '[]') into v_val from (
        select tt.name, count(*) as cnt
          from tasks t join task_types tt on tt.id = t.task_type_id
         where t.deleted_at is null and t.task_date between p_from and p_to
         group by tt.name order by 2 desc limit v_limit) x;

    elsif v_key = 'tasks.by_method' then
      select coalesce(jsonb_agg(row_to_json(x)), '[]') into v_val from (
        select em.name, count(*) as cnt
          from tasks t join execution_methods em on em.id = t.execution_method_id
         where t.deleted_at is null and t.task_date between p_from and p_to
         group by em.name order by 2 desc limit v_limit) x;

    elsif v_key = 'tasks.trend' then
      select coalesce(jsonb_agg(row_to_json(x) order by x.bucket), '[]') into v_val from (
        select bucket, sum(tasks) as tasks, sum(events) as events from (
          select date_trunc(v_bucket, t.task_date)::date as bucket, count(*) as tasks, 0 as events
            from tasks t where t.deleted_at is null and t.task_date between p_from and p_to
           group by 1
          union all
          select date_trunc(v_bucket, e.event_date)::date, 0, count(*)
            from events e where e.deleted_at is null and e.event_date between p_from and p_to
           group by 1) u
         group by bucket) x;

    elsif v_key = 'tasks.understaffed'
          and (app.has('dashboard.all_workers') or app.has('tasks.assign.worker')) then
      select jsonb_build_object(
        'count', count(*),
        'rows', (select coalesce(jsonb_agg(row_to_json(y)), '[]') from (
            select t2.id, t2.task_date, coalesce(c2.name, t2.title) as label,
                   t2.worker_count as needed,
                   -- ‏0091: עובדי הקבלן נספרים כמאיישים, כמו אנשי המשרד. בלי זה
                   -- משימה שהקבלן איישָׁ נותרה "חסרה" (task_contractor_workers).
                   ((select count(*) from task_assignments a2
                      where a2.task_id = t2.id and a2.role = 'worker')
                    + (select count(*) from task_contractor_workers cw2
                        where cw2.task_id = t2.id)) as assigned
              from tasks t2
              left join customers c2 on c2.id = t2.customer_id
              join statuses s2 on s2.id = t2.status_id
             where t2.deleted_at is null and t2.task_date between p_from and p_to
               and not s2.is_terminal and t2.worker_count > 0
               and ((select count(*) from task_assignments a3
                      where a3.task_id = t2.id and a3.role = 'worker')
                    + (select count(*) from task_contractor_workers cw3
                        where cw3.task_id = t2.id)) < t2.worker_count
             order by t2.task_date limit 8) y))
        into v_val
        from tasks t
        join statuses s on s.id = t.status_id
       where t.deleted_at is null and t.task_date between p_from and p_to
         and not s.is_terminal and t.worker_count > 0
         and ((select count(*) from task_assignments a
                where a.task_id = t.id and a.role = 'worker')
              + (select count(*) from task_contractor_workers cw
                  where cw.task_id = t.id)) < t.worker_count;

    elsif v_key = 'tasks.no_truck' then
      select jsonb_build_object('count', count(*)) into v_val
        from tasks t join statuses s on s.id = t.status_id
       where t.deleted_at is null and t.task_date between p_from and p_to
         and not s.is_terminal
         and coalesce(cardinality(t.truck_ids), 0) = 0 and t.truck_free_text is null;

    elsif v_key = 'fleet.utilization' then
      select coalesce(jsonb_agg(row_to_json(x)), '[]') into v_val from (
        select tr.name,
               count(distinct t.task_date) as days,
               count(*) as tasks
          from tasks t
          cross join lateral unnest(t.truck_ids) as u(truck_id)
          join trucks tr on tr.id = u.truck_id
         where t.deleted_at is null and t.task_date between p_from and p_to
         group by tr.name order by 2 desc limit v_limit) x;

    elsif v_key = 'events.by_customer' and app.has('customers.view') then
      select coalesce(jsonb_agg(row_to_json(x)), '[]') into v_val from (
        select c.name, c.color, count(*) as cnt
          from events e join customers c on c.id = e.customer_id
         where e.deleted_at is null and e.event_date between p_from and p_to
         group by c.name, c.color order by 3 desc limit v_limit) x;

    elsif v_key = 'events.funnel' then
      select coalesce(jsonb_agg(row_to_json(x)), '[]') into v_val from (
        select s.name, s.color, count(*) as cnt
          from events e join statuses s on s.id = e.status_id
         where e.deleted_at is null and e.event_date between p_from and p_to
         group by s.name, s.color, s.sort_order order by s.sort_order) x;

    elsif v_key = 'events.volume' and app.has('customers.view') then
      select jsonb_build_object(
        'volume_m', round(coalesce(sum(e.volume_m), 0), 2),
        'trucks',   coalesce(sum(e.truck_count), 0),
        'events',   count(*),
        'by_customer', (select coalesce(jsonb_agg(row_to_json(y)), '[]') from (
            select c2.name, c2.color,
                   round(coalesce(sum(e2.volume_m), 0), 2) as volume_m,
                   coalesce(sum(e2.truck_count), 0) as trucks
              from events e2 join customers c2 on c2.id = e2.customer_id
             where e2.deleted_at is null and e2.event_date between p_from and p_to
             group by c2.name, c2.color order by 3 desc limit v_limit) y))
        into v_val
        from events e
       where e.deleted_at is null and e.event_date between p_from and p_to;

    elsif v_key = 'customers.leaderboard' and app.has('customers.view') then
      select coalesce(jsonb_agg(row_to_json(x) order by x.events desc), '[]') into v_val from (
        select c.name, c.color,
               count(distinct e.id) as events,
               count(distinct t.id) as tasks,
               case when app.has('pricing.revenue')
                    then round(coalesce(sum(distinct_price.price), 0)
                               + coalesce((select sum(ei.amount)
                                             from event_income ei
                                             join events e3 on e3.id = ei.event_id
                                              and e3.deleted_at is null
                                              and e3.event_date between p_from and p_to
                                            where e3.customer_id = c.id), 0), 2) end as revenue,
               max(e.event_date) as last_event
          from customers c
          left join events e on e.customer_id = c.id and e.deleted_at is null
               and e.event_date between p_from and p_to
          left join tasks t on t.customer_id = c.id and t.deleted_at is null
               and t.task_date between p_from and p_to
          left join lateral (
            select tp.price from task_pricing tp where tp.task_id = t.id) distinct_price on true
         where c.deleted_at is null
         group by c.id, c.name, c.color
        having count(distinct e.id) > 0 or count(distinct t.id) > 0
         limit v_limit) x;

    elsif v_key = 'customers.inactive' and app.has('customers.view') then
      select coalesce(jsonb_agg(row_to_json(x)), '[]') into v_val from (
        select c.name, c.color,
               (select max(e2.event_date) from events e2
                 where e2.customer_id = c.id and e2.deleted_at is null) as last_event
          from customers c
         where c.deleted_at is null and c.is_active
           and not exists (select 1 from events e where e.customer_id = c.id
                             and e.deleted_at is null and e.event_date between p_from and p_to)
         order by 3 desc nulls last limit v_limit) x;

    elsif v_key = 'attendance.hours' and app.has('attendance.view_all') then
      select jsonb_build_object(
        'actual_hours', round(coalesce(sum(e.actual_hours), 0), 2),
        'shifts',       count(*),
        'workers',      count(distinct e.profile_id))
        into v_val
        from attendance_entries e
       where e.deleted_at is null and e.status = 'approved'
         and e.work_date between p_from and p_to;

    elsif v_key = 'attendance.hours_by_worker' and app.has('attendance.view_all') then
      select coalesce(jsonb_agg(row_to_json(x)), '[]') into v_val from (
        select p.full_name as name, round(sum(e.actual_hours), 2) as hours
          from attendance_entries e join profiles p on p.id = e.profile_id
         where e.deleted_at is null and e.status = 'approved'
           and e.work_date between p_from and p_to
         group by p.full_name order by 2 desc nulls last limit v_limit) x;

    elsif v_key = 'attendance.pending' and app.has('attendance.approve_entry') then
      select jsonb_build_object(
        'count', count(*),
        'hours', round(coalesce(sum(e.actual_hours), 0), 2),
        'rows', (select coalesce(jsonb_agg(row_to_json(y)), '[]') from (
            select e2.id, e2.work_date, p2.full_name, e2.actual_hours
              from attendance_entries e2 join profiles p2 on p2.id = e2.profile_id
             where e2.deleted_at is null and e2.status = 'pending'
             order by e2.work_date limit 8) y))
        into v_val
        from attendance_entries e
       where e.deleted_at is null and e.status = 'pending';

    elsif v_key = 'attendance.flags' and app.has('attendance.view_all') then
      select coalesce(jsonb_agg(row_to_json(x)), '[]') into v_val from (
        select f as flag, count(*) as cnt
          from attendance_entries e, unnest(e.flags) as f
         where e.deleted_at is null and e.work_date between p_from and p_to
         group by f order by 2 desc) x;

    elsif v_key = 'hr.headcount' and app.has('dashboard.all_workers') then
      select jsonb_build_object(
        'active', count(*) filter (where p.is_active),
        'staff',  count(*) filter (where p.is_active and p.user_kind = 'staff'))
        into v_val
        from profiles p where p.deleted_at is null;

    /* ההוצאה של הלקוח: אותו `task_pricing.price` שהוצג לו קודם כ"הכנסות".
       `by_event` ולא `by_customer` — ללקוח יש לקוח אחד, הוא עצמו, ומה שהוא
       רוצה לדעת הוא על איזה אירוע הלך הכסף. `end_client_name` הוא איך הוא
       מזהה אירוע; מספר האירוע הוא הנפילה כשאין. */
    elsif v_key = 'spend.summary' and app.has('finance.customer_spend') then
      select jsonb_build_object(
        'total', round(coalesce(sum(tp.price), 0), 2),
        'tasks', count(*),
        'by_event', (select coalesce(jsonb_agg(row_to_json(y) order by y.total desc), '[]') from (
            select e2.id, e2.event_date,
                   coalesce(nullif(e2.end_client_name, ''), 'אירוע ' || e2.event_number) as label,
                   round(sum(tp2.price), 2) as total
              from task_pricing tp2
              join tasks t2 on t2.id = tp2.task_id and t2.deleted_at is null
              join events e2 on e2.id = t2.event_id and e2.deleted_at is null
             where t2.task_date between p_from and p_to and tp2.price > 0
             group by e2.id, e2.event_date, e2.end_client_name, e2.event_number
             order by 4 desc limit v_limit) y),
        'by_bucket', (select coalesce(jsonb_agg(row_to_json(z) order by z.bucket), '[]') from (
            select date_trunc(v_bucket, t3.task_date)::date as bucket,
                   round(sum(tp3.price), 2) as total
              from task_pricing tp3
              join tasks t3 on t3.id = tp3.task_id and t3.deleted_at is null
             where t3.task_date between p_from and p_to
             group by 1) z))
        into v_val
        from task_pricing tp
        join tasks t on t.id = tp.task_id and t.deleted_at is null
       where t.task_date between p_from and p_to;
    /* צי הרכב (0089). שני הסקשנים אינם קוראים את p_from/p_to במכוון: תוקף
       מסמך הוא שאלה על היום ועל מה שאחריו, ולא על הטווח שנבחר בראש הדשבורד.
       הווידג׳טים מוצהרים בהתאם, ראו fleetWidgets.tsx. */
    elsif v_key = 'fleet.status' and app.has('fleet.view') then
      select jsonb_build_object(
        'total',     count(*),
        'active',    count(*) filter (where status = 'active'),
        'in_garage', count(*) filter (where status = 'in_garage'),
        'inactive',  count(*) filter (where status = 'inactive'))
        into v_val
        from vehicles where deleted_at is null and status <> 'sold';

    elsif v_key = 'fleet.documents_expiring'
          and app.has('fleet.view') and app.has('fleet.docs_view') then
      select coalesce(jsonb_agg(row_to_json(x) order by x.expires_at), '[]') into v_val from (
        select v.id as vehicle_id, v.name, v.plate_number,
               s.kind_name, s.expires_at, s.days_left, s.status
          from vehicle_document_status s
          join vehicles v on v.id = s.vehicle_id
         where s.deleted_at is null and v.deleted_at is null and v.status <> 'sold'
           and s.status in ('expired', 'expiring')
         order by s.expires_at limit v_limit) x;

    end if;

    v_out := v_out || jsonb_build_object(v_key, v_val);
  end loop;

  return v_out;
end $$;

revoke execute on function public.dashboard_sections(text[], date, date, jsonb) from anon, public;

-- ===== 8. work_board_view מחזיר את מחיר הקבלן (הגדרה מ-0079 + עמודה) =====
create or replace view work_board_view
with (security_invoker = true) as
select
  t.id,
  t.event_id,
  t.customer_id,
  c.name  as customer_name,
  c.color as customer_color,
  e.end_client_name,
  e.event_number,
  case when (select app.can_view_field('task', 'location_text'))
    then coalesce(t.location_text, e.location_text) end as location_text,
  e.volume_m,
  e.truck_count as event_truck_count,
  t.task_type_id,
  tt.name as task_type_name,
  tt.code as task_type_code,
  t.title,
  t.task_date,
  t.warehouse_start_time,
  t.onsite_start_time,
  t.onsite_end_time,
  t.hours_count,
  t.worker_count,
  t.execution_method_id,
  em.name as execution_method_name,
  t.truck_id,
  case when (select app.can_view_field('task', 'truck_id')) then tr.name end as truck_name,
  case when (select app.can_view_field('task', 'truck_free_text')) then t.truck_free_text end as truck_free_text,
  case when (select app.can_view_field('task', 'notes')) then t.notes end as notes,
  t.status_id,
  s.name  as status_name,
  s.color as status_color,
  s.is_terminal as status_is_terminal,
  t.contractor_id,
  case when (select app.has('contractors.view')) then ct.name end as contractor_name,
  t.created_at,
  t.updated_at,
  lead_p.full_name as team_lead_name,
  lead_a.profile_id as team_lead_id,
  workers.list  as workers,
  drivers.list  as drivers,
  cworkers.list as contractor_worker_list,
  case when (select app.has('pricing.view')) then tp.price end as customer_price,
  case when (select app.has('pricing.view')) then tp.is_manual end as price_is_manual,
  case when (select app.has('pricing.view')) then tp.breakdown end as price_breakdown,
  t.travel_hours,
  t.requires_team_lead,
  case when (select app.can_view_field('task', 'truck_ids')) then t.truck_ids end as truck_ids,
  case when (select app.can_view_field('task', 'truck_ids')) then tlist.list end as truck_list,
  coalesce(es.code = 'cancelled', false) as event_is_cancelled,
  s.code as status_code,
  -- ‏0091: התשלום לקבלן, בסוף הרשימה כי `create or replace view` מוסיף עמודות
  -- רק בקצה. גלוי למי שמחזיק contractors.view_pricing — ומנהל הקבלן ביניהם,
  -- כשה-RLS על ה-terms כבר מגביל אותו למשימות הקבלן שלו.
  case when (select app.has('contractors.view_pricing')) then tct.price end as contractor_price,
  case when (select app.has('contractors.view_pricing')) then tct.price_per_worker end as contractor_price_per_worker,
  tct.work_site as contractor_work_site
from tasks t
left join events e     on e.id = t.event_id
-- ‏0079: זהות בלבד, ובלי RLS — ראו את ההערה על ה-view. השורה עצמה כבר
-- מסוננת ב-tasks_select, ולכן "של מי המשימה" אינו מידע נוסף.
left join app.customer_identities c on c.id = t.customer_id
join task_types tt     on tt.id = t.task_type_id
left join execution_methods em on em.id = t.execution_method_id
left join trucks tr    on tr.id = t.truck_id
join statuses s        on s.id = t.status_id
left join contractors ct on ct.id = t.contractor_id
left join statuses es  on es.id = e.status_id
left join task_pricing tp on tp.task_id = t.id
left join task_contractor_terms tct on tct.task_id = t.id
left join lateral (
  select a.profile_id from task_assignments a
  where a.task_id = t.id and a.role = 'team_lead' limit 1
) lead_a on true
left join profiles lead_p on lead_p.id = lead_a.profile_id
left join lateral (
  select jsonb_agg(jsonb_build_object('profile_id', a.profile_id, 'name', p.full_name,
                                      'work_site', a.work_site)
                   order by p.full_name) as list
  from task_assignments a join profiles p on p.id = a.profile_id
  where a.task_id = t.id and a.role = 'worker'
) workers on true
left join lateral (
  select jsonb_agg(jsonb_build_object('profile_id', a.profile_id, 'name', p.full_name,
                                      'truck_id', a.truck_id, 'truck_name', tr2.name,
                                      'work_site', a.work_site)
                   order by p.full_name) as list
  from task_assignments a
  join profiles p on p.id = a.profile_id
  left join trucks tr2 on tr2.id = a.truck_id
  where a.task_id = t.id and a.role = 'driver'
) drivers on true
left join lateral (
  select jsonb_agg(jsonb_build_object('id', cw.id, 'name', cw.full_name,
                                      'work_site', tcw.work_site)
                   order by cw.full_name) as list
  from task_contractor_workers tcw join contractor_workers cw on cw.id = tcw.contractor_worker_id
  where tcw.task_id = t.id
) cworkers on true
left join lateral (
  select jsonb_agg(jsonb_build_object('id', tr3.id, 'name', tr3.name) order by u.ord) as list
  from unnest(t.truck_ids) with ordinality as u(truck_id, ord)
  join trucks tr3 on tr3.id = u.truck_id
) tlist on true
where t.deleted_at is null;
