-- 0107: החתמת לקוח על האירוע — שם החותם וחתימתו, ואופציה לצפות בה אחר כך
--
-- בסוף ההקמה ראש הצוות מגיש ללקוח את המכשיר, הלקוח חותם, והחתימה נשמרת על
-- האירוע. עד היום זה נעשה על דף נייר שהלך לאיבוד; כאן זה רשומה במערכת, מקושרת
-- לאירוע, שאפשר לצפות בה שוב.
--
-- מי רואה את הכפתור ומי מחתים: **ראש הצוות של ההקמה**, מנהל המערכת, והלקוח
-- עצמו — ולא עובד מן השורה ולא רכז אקראי במשרד. שלוש החלטות נגזרות מכך:
--
--   1. **"ראש צוות בהקמה" אינו מפתח במרשם אלא תפקיד על השורה.** אותו אדם הוא
--      ראש צוות באירוע אחד ועובד מן השורה בבא, בדיוק כמו `is_event_team_lead`
--      (0082) — אבל כאן ממוקד למשימת ההקמה, כי זה מה שהתבקש. לכן זו זרוע
--      בפוליסה ולא `role_permissions`.
--   2. **הלקוח מגיע דרך זהות ולא דרך מפתח.** משתמש פורטל של הלקוח (`customer_user`)
--      חותם ורואה את החתימה על האירוע *שלו* — נבדק דרך `exists(events)` שרץ
--      תחת ה-RLS שלו, בדיוק כמו שאר הפורטל.
--   3. **החתימה היא data URL בעמודת טקסט, לא Supabase Storage.** חתימת קנבס
--      שוקלת כמה עשרות KB, והשמירה כ-base64 תחת RLS פשוטה, עצמאית, ואינה
--      נגררת אל פוליסות ה-storage.objects שבפרויקט אמיתי נדחות בחוסר בעלות
--      (ראה 0077 §8). המפרט — קובץ כבד — שם ב-Storage; החתימה — קלה — כאן.
--
-- החתימה היא רשומה שאין לשנות: אין פוליסת update ואין פוליסת delete, ויש טריגר
-- שחוסם שכתוב גם בנתיב ה-security definer. החתמה חוזרת אינה מוחקת — היא מוסיפה
-- שורה, והאחרונה היא החתימה הפעילה. זה אותו עיקרון של מספור המפרט (0077):
-- היסטוריה אינה נדרסת.

-- ===== 1. ערך יומן חדש =====================================================
-- בראש הקובץ במכוון: ערך enum חדש אינו ניתן לשימוש באותה טרנזקציה שהוסיפה אותו.
-- psql מריץ כל פקודה בטרנזקציה משלה, וגוף של פונקציה אינו מוערך בזמן ההגדרה —
-- אותו סידור שעבד ב-0049 וב-0077, כולל הקאסט המפורש שנדרש מאז 0051.

alter type event_activity_kind add value if not exists 'customer_signed';

-- ===== 2. הרשאות ===========================================================
-- שני מפתחות למודול events, שניהם ל-staff בלבד וללא `implied_by` וללא הענקת
-- ברירת מחדל: המשמעות היא שאיש אינו מקבל אותם ביום הפריסה מלבד מנהל המערכת
-- (שעוקף את המרשם ממילא). ראש צוות ההקמה והלקוח מגיעים דרך זרועות הפוליסה
-- למטה, ולא דרך המפתחות האלה. מנהל מערכת שירצה לפתוח את החתימה גם לרכז משרדי
-- יכול להעניק לו את המפתחות — אבל זו בחירה, לא ברירת המחדל.
--
-- לא `implied_by = 'events.view'` (כמו שהמפרט עשה): אחרת כל מי שרואה אירוע
-- היה רואה את כפתור החתימה, וזה בדיוק ההפך ממה שהתבקש — רק ראש צוות ההקמה.

select app.register_permission('events.sign_view', 'events', 'צפייה בחתימת הלקוח',
  'צפייה בחתימה שנקלטה על האירוע — שם החותם והחתימה עצמה', 'field', false, false,
  array['staff']::user_kind[], null, 230);

select app.register_permission('events.sign_capture', 'events', 'החתמת לקוח',
  'קליטת חתימת לקוח על האירוע — שם וחתימה', 'action', false, false,
  array['staff']::user_kind[], null, 240);

-- ===== 3. ראש הצוות של ההקמה ===============================================
-- כמו `app.is_event_team_lead` (0082), אבל ממוקד למשימת ההקמה: ההצטרפות אל
-- `task_types` והתנאי `tt.code = 'setup'` הם כל ההבדל. אותו נימוק לפרסום:
-- ראשות צוות במשימת טיוטה אינה תפקיד אלא טיוטה של תפקיד, ולכן נדרש שהמשימה
-- פורסמה (או שהקורא רשאי לתכנן, שאז הוא רואה גם טיוטות).
--
-- security definer מאותה סיבה: היא נקראת מתוך פוליסה על `event_signatures`
-- ושואלת את `tasks`, ובלעדיו הייתה נכנסת ל-`tasks_select` בתוך ההערכה.

create or replace function app.is_event_setup_team_lead(p_event_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from tasks t
    join task_assignments a on a.task_id = t.id
    join task_types tt on tt.id = t.task_type_id
    where t.event_id = p_event_id and t.deleted_at is null
      and a.profile_id = app.profile_id() and a.role = 'team_lead'
      and tt.code = 'setup'
      and (app.can_plan_tasks()
           or t.status_id = (select s.id from statuses s
                              where s.entity = 'task' and s.code = 'assigned'
                                and s.deleted_at is null limit 1)))
$$;

comment on function app.is_event_setup_team_lead(uuid) is
  'האם הקורא רשום כראש צוות במשימת ההקמה של האירוע (שפורסמה). תפקיד פר-אירוע, '
  'ולכן הוא נבדק על השורה ולא במרשם ההרשאות (0107).';

-- ===== 4. הטבלה ============================================================

create table event_signatures (
  id             uuid primary key default gen_random_uuid(),
  event_id       uuid not null references events(id) on delete cascade,
  -- שם הלקוח כפי שהוקלד בעת ההחתמה. נתון, לא נגזר — הלקוח החותם אינו בהכרח
  -- "שם לקוח האירוע" שעל האירוע.
  signer_name    text not null,
  -- החתימה עצמה: data URL של תמונה (PNG מקנבס). נשמרת ולא מקושרת ל-Storage.
  signature_data text not null,
  -- מי החתים בפועל — ראש הצוות, הלקוח, או מנהל המערכת. נכפה מהשרת בטריגר.
  signed_by      uuid references profiles(id) on delete set null,
  signed_by_name text,
  created_at     timestamptz not null default now(),
  constraint event_signatures_name_ck check (btrim(signer_name) <> ''),
  -- data URL של תמונה בלבד, ובגבול גודל שמונע ניפוח: חתימת קנבס אמיתית היא
  -- עשרות KB, ו-2MB הוא תקרה נדיבה שחוסמת ניצול.
  constraint event_signatures_data_ck check (
    signature_data ~ '^data:image/(png|jpeg|webp);base64,[A-Za-z0-9+/=]+$'
    and length(signature_data) <= 2000000)
);

-- הקריאה של המסך: החתימה האחרונה של האירוע קודם.
create index event_signatures_event_idx on event_signatures (event_id, created_at desc);

revoke all on event_signatures from anon;

-- ===== 5. זהות המחתים ואי-שינוי ===========================================
-- signed_by נכפה מהשרת ולא מתקבל מהקליינט — אחרת אפשר לחתום בשם אדם אחר.
-- created_at נכפה גם הוא, כדי שחותמת הזמן של רשומת חתימה לא תזויף מהקליינט.

create or replace function app.event_signature_before_insert()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_actor uuid := app.profile_id();
begin
  new.signed_by      := v_actor;
  new.signed_by_name := (select full_name from profiles where id = v_actor);
  new.created_at     := now();
  return new;
end $$;

create trigger event_signatures_before_insert before insert on event_signatures
  for each row execute function app.event_signature_before_insert();

-- חתימה שנרשמה אינה משתנה. אין פוליסת update על הטבלה (סעיף 6), אבל הטריגר
-- חוסם את השכתוב גם בנתיב ה-security definer, שבו RLS אינה קיימת בכלל — אותה
-- הגנה בדיוק שגרסת מפרט מקבלת ב-0077.
create or replace function app.event_signature_before_update()
returns trigger language plpgsql set search_path = public as $$
begin
  raise exception 'חתימת לקוח אינה ניתנת לשינוי — אפשר להחתים מחדש כרשומה חדשה';
  return new;
end $$;

create trigger event_signatures_before_update before update on event_signatures
  for each row execute function app.event_signature_before_update();

-- ===== 6. RLS ==============================================================
-- התבנית היא event_specs (0077) ו-event_activity (0082), כולל עטיפת
-- (select app.has(...)) שנדרשת מאז 0028 כדי שהתנאי יהפוך ל-InitPlan.
--
-- ה-exists על events אינו קישוט: הוא זה שמחיל על החתימה את סקופ האירועים של
-- הקורא (0013) בלי לשכפל את הפרדיקט לכאן. עבור הלקוח הוא גם השער — הוא רואה
-- רק את האירועים של הלקוח שלו, ולכן הזרוע `customer_user` נשענת עליו.

alter table event_signatures enable row level security;

-- צפייה: מנהל מערכת; או ראש צוות ההקמה / מי שהוענק לו `sign_view` (staff);
-- או משתמש פורטל של הלקוח, על האירוע שלו.
create policy event_signatures_select on event_signatures for select to authenticated using (
  (select app.is_admin())
  or (exists (select 1 from events e where e.id = event_signatures.event_id)
      and (
        ((select app.user_kind()) = 'staff'
          and ((select app.has('events.sign_view'))
               or (select app.is_event_setup_team_lead(event_signatures.event_id))))
        or (select app.user_kind()) = 'customer_user')));

-- החתמה: אותו קהל בדיוק, עם המפתח `sign_capture` במקום `sign_view` לזרוע ה-staff.
create policy event_signatures_insert on event_signatures for insert to authenticated with check (
  (select app.is_admin())
  or (exists (select 1 from events e where e.id = event_signatures.event_id)
      and (
        ((select app.user_kind()) = 'staff'
          and ((select app.has('events.sign_capture'))
               or (select app.is_event_setup_team_lead(event_signatures.event_id))))
        or (select app.user_kind()) = 'customer_user')));

-- אין פוליסת update ואין פוליסת delete, במכוון: חתימה היא רשומה קבועה.

-- ===== 7. יומן הפעילות =====================================================
-- כמו המפרט (0077): הטקסט נכתב ל-note, ‏field_key נשאר null ולכן השורה עוברת
-- את מסנן event_activity_feed (0016). security definer כדי לעקוף את פוליסת
-- ה-insert המצומצמת של event_activity.

create or replace function app.log_event_signature_activity()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_actor uuid := app.profile_id();
  v_name  text;
begin
  select full_name into v_name from profiles where id = v_actor;
  insert into event_activity (event_id, kind, actor_profile_id, actor_name, note)
  values (new.event_id, 'customer_signed'::event_activity_kind, v_actor, v_name,
          'נקלטה חתימת לקוח: ' || new.signer_name);
  return new;
end $$;

create trigger event_signatures_activity after insert on event_signatures
  for each row execute function app.log_event_signature_activity();
