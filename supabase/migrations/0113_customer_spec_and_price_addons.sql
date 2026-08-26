-- 0113: המפרט מגיע מהלקוח, המחיר לא — ותוספת מחיר שיש לה מה להגיד
--
-- שלושה שינויים שנוגעים באותה תפירה בין הלקוח למשרד, ולכן הם יושבים יחד:
--
--   1. **הלקוח מעלה את המפרט בעצמו.** ‏0077 קבעה שהמפרט הוא מסמך פנימי,
--      ‏0102 פתחה את *הצפייה* בו לכל מי שרואה את האירוע והשאירה את ההעלאה
--      אצל המשרד. בפועל המפרט נולד אצל הלקוח — הוא זה שיודע מה צריך לקרות
--      באולם — ולכן הוא זה שצריך להעלות אותו, בלי לשלוח אותו בוואטסאפ לרכז
--      שיעלה אותו בשמו.
--   2. **המחיר אינו שדה של הלקוח.** הכלל עצמו כבר בשרת מאז 0111; מה שנשאר
--      היה מסך שהציע ללקוח להקליד מספר שיושלך בשקט. סעיף 2 כאן הוא הפניה
--      ולא קוד, כדי שמי שיחפש את הכלל במסד ימצא אותו.
--   3. **תוספת מחיר למשימה, עם הערה שהלקוח קורא.** אירוע חורג — קומה בלי
--      מעלית, שעתיים המתנה, משאית שנייה שהוזמנה ביום האירוע — נגמר היום
--      בשיחת טלפון על ההפרש. התוספת נרשמת על המשימה יחד עם המשפט שמסביר
--      אותה, והמשפט הזה הוא בדיוק מה שהלקוח רואה בכרטיס התמחור של האירוע.
--
-- ===========================================================================

-- ===== 0. ערכי יומן חדשים ==================================================
-- בראש הקובץ, כמו ב-0049/0077/0107: ערך enum חדש אינו ניתן לשימוש באותה
-- טרנזקציה שהוסיפה אותו, ו-psql מריץ כל פקודה בטרנזקציה משלה.

alter type event_activity_kind add value if not exists 'price_addon_added';
alter type event_activity_kind add value if not exists 'price_addon_removed';

-- ===== 1. ההעלאה מקבלת מפתח משלה ==========================================
--
-- עד כאן `events.specs_manage` ענה על שתי שאלות שונות בקול אחד: "מי מעלה
-- גרסה" ו"מי מוריד גרסה". לצורך 0102 §3 די היה בזה — שתי התשובות היו
-- "המשרד" — אבל ברגע שהלקוח מעלה, הן נפרדות: מסמך שהלקוח שלח הוא שלו,
-- והחלטה *להסיר* גרסה מההיסטוריה של האירוע היא של מי שמנהל את האירוע.
-- לקוח שהעלה גרסה שגויה מעלה אחריה גרסה נכונה — זה בדיוק מה שהמספור קיים
-- בשבילו — ולא מוחק את מה שכבר נראה.
--
-- ‏`implied_by = events.specs_manage`, ולכן איש צוות שמנהל מפרטים ממשיך
-- להעלות בלי שורה חדשה: השרשרת ב-`app.has` (0010) עולה למפתח הניהול
-- כשלמפתח ההעלאה עצמו אין דעה. מי שיש לו דעה — ברירת המחדל של סוג המשתמש
-- בסעיף הבא — עוצר בשכבה הראשונה, וזה בדיוק ההבדל בין לקוח לקבלן.
select app.register_permission('events.specs_upload', 'events', 'העלאת מפרט',
  'העלאת קובץ או קישור כגרסה חדשה של המפרט. הסרת גרסה קיימת היא מפתח נפרד',
  'action', false, false,
  array['staff', 'customer_user', 'contractor_user']::user_kind[], 'events.specs_manage', 215);

-- ותיאור מדויק יותר למפתח הניהול, שמכאן ואילך הוא בעיקר ההסרה.
select app.register_permission('events.specs_manage', 'events', 'ניהול מפרט האירוע',
  'העלאת גרסה חדשה של המפרט והסרת גרסה קיימת', 'action', false, false,
  array['staff']::user_kind[], 'events.edit', 220);

-- הלקוח מעלה, הקבלן לא. עובד הקבלן נוסע לאירוע ומבצע את מה שכתוב במפרט —
-- הוא אינו צד לתוכן שלו, ולכן הוא נשאר בצפייה בלבד (0102 §1).
--
-- ברירת המחדל של סוג המשתמש ולא הענקה אישית, מאותו נימוק שב-0102 §3: היא
-- מדברת *אחרי* המענק האישי ואחרי התפקיד (0042), ולכן מנהל מערכת שירצה
-- לשלול את זה מלקוח מסוים — או להחזיר את זה לקבלן מסוים — עדיין יכול.
insert into kind_permission_defaults (user_kind, permission_key, allowed) values
  ('customer_user',   'events.specs_upload', true),
  ('contractor_user', 'events.specs_upload', false)
on conflict (user_kind, permission_key) do update set allowed = excluded.allowed;

-- הפוליסה: ההעלאה נשענת על המפתח החדש, וה-exists על `events` נשאר מה שהוא
-- היה — הוא זה שמחיל את סקופ האירועים של הקורא (0013), ולכן לקוח יכול
-- להעלות מפרט לאירוע שלו בלבד בלי שנכתב כאן אף פרדיקט על לקוח.
drop policy if exists event_specs_insert on event_specs;
create policy event_specs_insert on event_specs for insert to authenticated with check (
  ((select app.is_admin()) or (select app.has('events.specs_upload')))
  and exists (select 1 from events e where e.id = event_specs.event_id));

-- אותו שער, על הדלי. הקריאה ממשיכה להישען על `events.specs_view` (0102 §5)
-- והכתיבה עוברת למפתח ההעלאה — ‏`remove_event_spec` היא מחיקה רכה ואינה
-- נוגעת באובייקט בדלי כלל, ולכן אין כאן צד שני שנפתח.
--
-- security invoker במכוון, כמו ב-0077 וב-0102: ה-exists על events רץ תחת
-- ה-RLS של הקורא, ולכן ההרשאה על הקובץ היא בדיוק ההרשאה על האירוע.
create or replace function app.may_touch_event_spec(p_name text, p_write boolean)
returns boolean language plpgsql stable set search_path = public as $$
declare v_event uuid;
begin
  -- הנתיב הוא החוזה. כל דבר שאינו '<uuid>/...' בדלי הזה אינו שלנו, ואינו נפתח.
  begin
    v_event := split_part(p_name, '/', 1)::uuid;
  exception when others then
    return false;
  end;

  if not app.is_admin() then
    if p_write and not app.has('events.specs_upload') then return false; end if;
    if not p_write and not app.has('events.specs_view') then return false; end if;
  end if;

  return exists (select 1 from events e where e.id = v_event);
end $$;

comment on function app.may_touch_event_spec(text, boolean) is
  'השער היחיד לדלי event-specs. קריאה נשענת על events.specs_view וכתיבה על '
  'events.specs_upload; סוג המשתמש נשאל במרשם ההרשאות ולא כאן (0102, 0113).';

-- ===== 2. שדה המחיר בטופס האירוע אינו נפתח ללקוח ==========================
--
-- אין כאן קוד, וזו התשובה: ‏0111 §2 כבר קבעה את הכלל בשרת. הענף שכותב
-- ‏`<code>_price` ב-`apply_event_task_block` שואל `app.user_kind() = 'staff'`
-- לפני שהוא שואל על המפתח, ולכן משתמש לקוח אינו כותב מחיר גם כשמישהו העניק
-- לו את `pricing.edit` וגם כשהשדה גלוי לו בטופס.
--
-- מה שנשאר היה בקליינט בלבד, ושם הוא תוקן: השדה נפתח ללקוח להקלדה, השמירה
-- שלחה אותו, והשרת השליך אותו בשקט — כלומר הלקוח ראה מספר שהזין, לחץ שמירה,
-- קיבל "נשמר", וחזר למסך שמראה את המחיר הישן. מכאן השדה מוצג לו נעול, עם
-- הסבר, ואינו נשלח כלל. השורות האלה קיימות כדי שמי שיחפש את הכלל במסד
-- ימצא את ההפניה במקום להסיק שהוא לא נאכף.

-- ===== 3. תוספת מחיר למשימה ===============================================
--
-- **למה שורות ולא עמודה על `task_pricing`.** אירוע חורג לא נושא חריגה אחת:
-- קומה בלי מעלית *ו*שעתיים המתנה הם שני משפטים שונים ושני סכומים שונים,
-- ולקוח שמקבל "תוספת 450 ₪" בלי לדעת ממה היא מורכבת מרים טלפון בדיוק כמו
-- קודם. כל תוספת היא שורה עם הסכום והמשפט שלה.
--
-- **ולמה לא לתוך `task_pricing.price`.** המחיר שם הוא תוצר המחשבון, ו-
-- ‏`recalculate_task_price` כותב אותו מחדש. תוספת שהתמזגה לתוכו הייתה
-- נמחקת בחישוב מחדש הראשון — או, גרוע מכך, נועלת את המשימה על `is_manual`
-- ומנתקת אותה מהמחשבון בגלל 80 ₪ של המתנה. השורות חיות לצד המחיר, והסכום
-- שהלקוח רואה הוא הצירוף.
--
-- **סכום שלילי מותר.** "הנחה על איחור שלנו" היא בדיוק אותה ישות עם אותו
-- משפט מוצג, ואין סיבה להמציא לה טבלה שנייה. אפס אינו מותר — תוספת שאינה
-- משנה דבר היא הערה, ולזה יש יומן.

create table task_price_addons (
  id           uuid primary key default gen_random_uuid(),
  task_id      uuid not null references tasks(id) on delete cascade,
  amount       numeric(12, 2) not null check (amount <> 0),
  -- ההערה אינה אופציונלית: כל הנקודה בתוספת הזו היא שהיא מסבירה את עצמה
  -- ללקוח, ותוספת בלי משפט היא בדיוק המספר חסר ההסבר שהיא באה להחליף.
  note         text not null check (btrim(note) <> ''),
  -- מדונרמל לצד ה-FK, כמו `actor_name` ב-0016: פרופיל יכול להימחק, והיסטוריה
  -- ששכחה מי הוסיף חיוב אינה היסטוריה.
  created_by   uuid references profiles(id) on delete set null,
  creator_name text,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz,
  deleted_at   timestamptz
);

create index task_price_addons_task_idx on task_price_addons (task_id)
  where deleted_at is null;

revoke all on task_price_addons from anon;

create trigger task_price_addons_updated_at before update on task_price_addons
  for each row execute function app.set_updated_at();

-- מי הוסיף נכפה מהשרת ולא מתקבל מהקליינט, מאותו נימוק שב-0077 §4: אחרת
-- אפשר לחתום חיוב בשם אדם אחר.
create or replace function app.task_price_addon_before_insert()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_actor uuid := app.profile_id();
begin
  new.created_by   := v_actor;
  new.creator_name := (select full_name from profiles where id = v_actor);
  new.deleted_at   := null;
  new.note         := btrim(new.note);
  return new;
end $$;

create trigger task_price_addons_before_insert before insert on task_price_addons
  for each row execute function app.task_price_addon_before_insert();

-- ===== 3א. RLS ============================================================
--
-- התבנית היא `task_pricing` (0017 §5) מילה במילה, וזו הנקודה: התוספת היא
-- חלק מאותו מספר, ולכן היא נראית בדיוק לאותם עיניים — הצוות עם `pricing.view`,
-- והלקוח על המשימות שלו בלבד. אין ענף `contractor_user` באף אחת מהזרועות,
-- מאותה סיבה שכתובה שם: מה שהלקוח משלם אינו עניינו של הקבלן.
--
-- הזרוע הראשונה — שורות שהוסרו לאדמין בלבד — היא של `event_specs` (0077 §6):
-- חיוב שירד מהחשבון נשאר בהיסטוריה של מי שמנהל אותה, ונעלם מהחשבון עצמו.

alter table task_price_addons enable row level security;

create policy tpa_select on task_price_addons for select to authenticated using (
  ((select app.is_admin()) or deleted_at is null)
  and ((select app.is_admin())
       or ((select app.user_kind()) = 'staff' and (select app.has('pricing.view')))
       or ((select app.user_kind()) = 'customer_user' and (select app.has('pricing.view'))
           and exists (select 1 from tasks t
                        where t.id = task_price_addons.task_id
                          and t.customer_id = (select app.customer_id())
                          and t.deleted_at is null))));

-- הכתיבה נשענת על אותו מפתח שדורס מחיר ידנית — תוספת היא החלטת תמחור של
-- אדם, ולא סוג חדש של החלטה. משתמש לקוח אינו כותב אותה גם אם המפתח הוענק
-- לו, מאותו נימוק שבסעיף 2: זה צד ולא הרשאה.
--
-- **ולמה שתי פוליסות ולא `for all` אחת**, כפי ש-`task_pricing` כתובה. פוליסה
-- מתירנית מסוג `for all` חלה גם על SELECT, והיא נוספת ב-OR לפוליסת הקריאה —
-- כלומר הזרוע "מוסרות לאדמין בלבד" שבשורה שמעל הייתה מתבטלת לכל מי שמחזיק
-- ‏`pricing.edit`, ותוספת שהוסרה הייתה ממשיכה להופיע לו ברשימה. ‏`task_pricing`
-- אינה סובלת מזה כי אין לה מחיקה רכה בכלל; כאן יש, ולכן הכתיבה נאמרת
-- במפורש על הפעולות שהיא באמת מתכוונת אליהן.
create policy tpa_insert on task_price_addons for insert to authenticated
  with check ((select app.is_admin())
              or ((select app.has('pricing.edit')) and (select app.user_kind()) = 'staff'));

-- העדכון קיים כדי לתקן סכום או ניסוח, ולא כדי להסיר: הסרה עוברת ב-RPC
-- (סעיף 3ג) מפני שפוסטגרס מחילה את פוליסת ה-select גם על השורה החדשה.
create policy tpa_update on task_price_addons for update to authenticated
  using ((select app.is_admin())
         or ((select app.has('pricing.edit')) and (select app.user_kind()) = 'staff'))
  with check ((select app.is_admin())
              or ((select app.has('pricing.edit')) and (select app.user_kind()) = 'staff'));

-- ===== 3ב. היומן =========================================================
--
-- הטקסט נכתב ל-note ולא ל-old_value/new_value, מאותו נימוק שב-0049 ו-0077:
-- אלה שייכים לרישום 'changed', שבו יש שדה שעבר מערך לערך. כאן אין שדה — יש
-- חיוב שנוסף או ירד. ‏field_key נשאר null, ולכן השורה עוברת את מסנן
-- ‏`event_activity_feed` (0016).
--
-- המשימה עשויה לא לשאת אירוע כלל (משימה עצמאית), ואז אין ליומן לאן להיכתב
-- והטריגר יוצא בשקט.
create or replace function app.log_task_price_addon()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_actor uuid := app.profile_id();
  v_name  text;
  v_event uuid;
  v_type  text;
  v_text  text;
begin
  select t.event_id, tt.name into v_event, v_type
    from tasks t join task_types tt on tt.id = t.task_type_id
   where t.id = new.task_id;
  if v_event is null then return new; end if;

  select full_name into v_name from profiles where id = v_actor;
  v_text := concat_ws(' · ', v_type, to_char(new.amount, 'FM999999990.00') || ' ₪', new.note);

  if tg_op = 'INSERT' then
    insert into event_activity (event_id, kind, actor_profile_id, actor_name, note)
    values (v_event, 'price_addon_added'::event_activity_kind, v_actor, v_name,
            'נוספה תוספת מחיר: ' || v_text);
    return new;
  end if;

  -- הסרה היא מחיקה רכה, ושחזור הוא אותו מעבר בכיוון ההפוך. יומן שמדלג על
  -- שחזור משקר, ולכן שניהם מקבלים שורה.
  if (old.deleted_at is null) is distinct from (new.deleted_at is null) then
    insert into event_activity (event_id, kind, actor_profile_id, actor_name, note)
    values (v_event,
            (case when new.deleted_at is null then 'price_addon_added' else 'price_addon_removed' end)::event_activity_kind,
            v_actor, v_name,
            (case when new.deleted_at is null then 'שוחזרה תוספת מחיר: ' else 'הוסרה תוספת מחיר: ' end) || v_text);
  end if;
  return new;
end $$;

create trigger task_price_addons_activity after insert or update on task_price_addons
  for each row execute function app.log_task_price_addon();

-- ===== 3ג. הסרה עוברת ב-RPC ==============================================
--
-- מאותה סיבה בדיוק ש-`remove_event_spec` הוא RPC (0077 §6): פוסטגרס מחילה
-- את פוליסת ה-select גם על השורה *החדשה* ב-UPDATE, ולכן שורה אינה יכולה
-- להעלים את עצמה מעיני מי שמחק אותה. ‏`tpa_update` מתירה את הכתיבה, אבל ה-
-- ‏`using` של `tpa_select` על השורה החדשה — שבה `deleted_at` כבר אינו null —
-- הייתה דוחה אותה לכל מי שאינו אדמין.

create or replace function remove_task_price_addon(p_addon_id uuid, p_restore boolean default false)
returns void language plpgsql security definer set search_path = public as $$
declare v_exists boolean;
begin
  perform app.require('pricing.edit',
    case when p_restore then 'אין לך הרשאה לשחזר תוספת מחיר' else 'אין לך הרשאה להסיר תוספת מחיר' end);
  if app.user_kind() is distinct from 'staff' and not app.is_admin() then
    raise exception 'תוספת מחיר היא החלטה של המשרד' using errcode = '42501';
  end if;

  select true into v_exists from task_price_addons where id = p_addon_id;
  if v_exists is null then raise exception 'תוספת המחיר לא נמצאה'; end if;

  update task_price_addons
     set deleted_at = case when p_restore then null else now() end
   where id = p_addon_id;
end $$;

revoke execute on function remove_task_price_addon(uuid, boolean) from anon, public;

-- ===== 3ד. סך התוספות של אירוע ===========================================
--
-- כרטיס התמחור באירוע כבר סוכם `task_pricing.price` על פני המשימות, והוא
-- זה שצריך לספר את הסיפור המלא. הפונקציה מחזירה שורה למשימה כדי שהמסך יציג
-- כל תוספת עם המשפט שלה מתחת למשימה שהיא נוספה עליה, ולא מספר אחד בתחתית.
--
-- security invoker: `tpa_select` היא שמכריעה מי רואה מה, וכך הלקוח מקבל את
-- התוספות של האירוע שלו בלבד בלי שנכתב כאן פרדיקט על לקוח.
create or replace function event_price_addons(p_event_id uuid)
returns table (
  id uuid, task_id uuid, task_label text,
  amount numeric, note text, created_at timestamptz, creator_name text)
language sql stable set search_path = public as $$
  select a.id, a.task_id, coalesce(nullif(btrim(t.title), ''), tt.name) as task_label,
         a.amount, a.note, a.created_at, a.creator_name
    from task_price_addons a
    join tasks t on t.id = a.task_id
    join task_types tt on tt.id = t.task_type_id
   where t.event_id = p_event_id and t.deleted_at is null and a.deleted_at is null
   order by t.task_date, a.created_at
$$;

revoke execute on function event_price_addons(uuid) from anon, public;
