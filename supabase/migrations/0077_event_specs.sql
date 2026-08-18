-- 0077: מפרט האירוע — קובץ או קישור, גרסאות, והשוואה ביניהן
--
-- לכל אירוע מגיע מסמך מפרט מהלקוח: PDF, צילום של דף, או קישור למסמך משותף.
-- עד היום לא היה לו מקום — הוא נשלח בוואטסאפ, וכשהגיעה גרסה מעודכנת איש לא ידע
-- מה בדיוק השתנה מול מה שסוכם. ROADMAP 2.5 מנסח את זה בחדות: "Supabase Storage
-- אינו בשימוש באף מקום במערכת". הקובץ הזה פותח אותו, והוא הראשון שעושה זאת.
--
-- ארבע החלטות:
--
--   1. **"המפרט הפעיל" נגזר ואינו מסומן.** הפעיל הוא ה-version הגבוה ביותר שאינו
--      מחוק. אין עמודת is_current שאפשר להעמיד בסתירה לעצמה, והסרת הגרסה
--      העליונה מחזירה את הקודמת לתפקיד בלי שום כתיבה נוספת.
--   2. **העלאה היא INSERT ישיר תחת RLS, לא RPC.** זה הדפוס של הערת יומן
--      (0016), והוא היחיד שמשאיר את סקופ האירועים של הקורא (0013) כשער היחיד.
--      הסרה, לעומת זאת, חייבת להיות RPC — פוסטגרס מחילה את פוליסת ה-select גם
--      על השורה החדשה ב-UPDATE, ולכן שורה אינה יכולה להעלים את עצמה. זו בדיוק
--      הסיבה ש-soft_delete הוא security definer מאז 0012.
--   3. **הנתיב ב-Storage הוא החוזה:** '<event_id>/<uuid>.<ext>'. הפוליסה על
--      storage.objects קוראת ממנו את מזהה האירוע, ולכן ההרשאה על הקובץ היא
--      בדיוק ההרשאה על האירוע — בלי טבלת הצטלבות ובלי סנכרון.
--   4. **הדלי פרטי.** אין URL ציבורי למפרט של לקוח; הקריאה בקליינט היא תמיד
--      דרך createSignedUrl.
--
-- הערה למי שיריץ את זה מקומית: אשכול הבדיקות (supabase/tests) מקים סכמת storage
-- מינימלית ב-00_bootstrap.sql, ובלעדיה הבלוק של סעיף 6 מדלג על עצמו בשקט.

-- ===== 1. ערכי יומן חדשים ==================================================
-- בראש הקובץ במכוון: ערך enum חדש אינו ניתן לשימוש באותה טרנזקציה שהוסיפה אותו.
-- psql מריץ כל פקודה בטרנזקציה משלה, וגוף של פונקציה אינו מוערך בזמן ההגדרה —
-- אותו סידור שעבד ב-0049, כולל הקאסט המפורש שנדרש מאז 0051.

alter type event_activity_kind add value if not exists 'spec_added';
alter type event_activity_kind add value if not exists 'spec_removed';

-- ===== 2. הרשאות ===========================================================
-- מודול events קיים. implied_by נבחר כך שאיש אינו מקבל או מאבד יכולת ביום
-- הפריסה: מי שרואה אירוע רואה את המפרט שלו, ומי שעורך אירוע מעלה לו מפרט.
--
-- applies_to = staff בלבד. מפרט הוא מסמך פנימי בין הרכז ללקוח, ומשתמש פורטל
-- אינו רואה אותו. הרחבה עתידית היא הוספת 'customer_user' כאן וענף בפוליסות.

select app.register_permission('events.specs_view', 'events', 'צפייה במפרט האירוע',
  'המפרט הפעיל, היסטוריית הגרסאות והשוואה ביניהן', 'field', false, false,
  array['staff']::user_kind[], 'events.view', 210);

select app.register_permission('events.specs_manage', 'events', 'העלאת מפרט והסרתו',
  'העלאת קובץ או קישור כגרסה חדשה של המפרט, והסרת גרסה קיימת', 'action', false, false,
  array['staff']::user_kind[], 'events.edit', 220);

-- ===== 3. הטבלה ============================================================

create table event_specs (
  id            uuid primary key default gen_random_uuid(),
  event_id      uuid not null references events(id) on delete cascade,
  -- נקבע בטריגר ולא על ידי הקליינט. ראה סעיף 4.
  version       int  not null,
  source        text not null check (source in ('file', 'link')),
  -- source='file': הנתיב בתוך הדלי event-specs, '<event_id>/<uuid>.<ext>'
  storage_path  text,
  -- שם הקובץ כפי שהמעלה ראה אותו. נשמר ולא נגזר מהנתיב: הנתיב הוא uuid, והאדם
  -- מחפש את "מפרט סופי.pdf".
  file_name     text,
  mime_type     text,
  size_bytes    bigint check (size_bytes is null or size_bytes >= 0),
  -- source='link'
  url           text,
  title         text,
  note          text,
  -- מדונרמל לצד ה-FK, מאותה סיבה שכתובה ב-0016 על actor_name: פרופיל יכול
  -- להימחק, והיסטוריה ששכחה מי העלה אינה היסטוריה.
  uploaded_by   uuid references profiles(id) on delete set null,
  uploader_name text,
  created_at    timestamptz not null default now(),
  deleted_at    timestamptz,
  constraint event_specs_shape check (
    case source
      when 'file' then storage_path is not null and btrim(coalesce(file_name, '')) <> ''
      when 'link' then url ~ '^https?://'
    end)
);

-- שני האינדקסים אינם חופפים: הייחודי אוכף את מספור הגרסאות (כולל המחוקות —
-- מספר גרסה שנמחקה אינו חוזר לשימוש), והחלקי משרת את הקריאה של המסך.
create unique index event_specs_version_uk on event_specs (event_id, version);
create index event_specs_event_live_idx on event_specs (event_id, version desc)
  where deleted_at is null;

revoke all on event_specs from anon;

-- ===== 4. מספור הגרסאות וזהות המעלה ========================================
-- שתי העלאות במקביל לאותו אירוע היו קוראות את אותו max() ונופלות על האינדקס
-- הייחודי. הנעילה היא פר-אירוע ומשתחררת בסוף הטרנזקציה, ולכן היא זולה: היא
-- מעכבת רק העלאה שנייה לאותו אירוע ממש.
--
-- uploaded_by נכפה מהשרת ולא מתקבל מהקליינט — אחרת אפשר לחתום העלאה בשם אדם אחר.

create or replace function app.event_spec_before_insert()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_actor uuid := app.profile_id();
begin
  perform pg_advisory_xact_lock(hashtextextended(new.event_id::text, 0));
  select coalesce(max(version), 0) + 1 into new.version
    from event_specs where event_id = new.event_id;

  new.uploaded_by   := v_actor;
  new.uploader_name := (select full_name from profiles where id = v_actor);
  -- גרסה אינה נולדת מחוקה
  new.deleted_at    := null;
  return new;
end $$;

create trigger event_specs_before_insert before insert on event_specs
  for each row execute function app.event_spec_before_insert();

-- העדכון החוקי היחיד על גרסה קיימת הוא הסרתה או שחזורה (deleted_at). מי שיחליף
-- את storage_path של גרסה 2 בקובץ אחר ישכתב היסטוריה שהמערכת כבר רשמה ביומן,
-- ולכן הטריגר חוסם זאת גם בנתיב ה-security definer — שם RLS אינה קיימת בכלל.
create or replace function app.event_spec_before_update()
returns trigger language plpgsql set search_path = public as $$
begin
  if new.event_id     is distinct from old.event_id
  or new.version      is distinct from old.version
  or new.source       is distinct from old.source
  or new.storage_path is distinct from old.storage_path
  or new.url          is distinct from old.url
  or new.file_name    is distinct from old.file_name
  or new.uploaded_by  is distinct from old.uploaded_by
  or new.created_at   is distinct from old.created_at then
    raise exception 'גרסת מפרט אינה ניתנת לשינוי — אפשר להסיר אותה ולהעלות גרסה חדשה';
  end if;
  return new;
end $$;

create trigger event_specs_before_update before update on event_specs
  for each row execute function app.event_spec_before_update();

-- ===== 5. יומן הפעילות =====================================================
-- הטקסט נכתב ל-note ולא ל-old_value/new_value, מאותו נימוק שכתוב ב-0049: אלה
-- שייכים לרישום מסוג 'changed', שבו יש שדה שעבר מערך לערך. כאן אין שדה — יש
-- מפרט שהועלה או שהוסר.
--
-- field_key נשאר null, ולכן השורה עוברת את מסנן event_activity_feed (0016).

create or replace function app.event_spec_text(
  p_version int, p_source text, p_file_name text, p_url text, p_title text)
returns text language sql immutable as $$
  select concat_ws(' · ',
    'גרסה ' || p_version,
    nullif(btrim(coalesce(p_title, '')), ''),
    case when p_source = 'file' then p_file_name else p_url end)
$$;

create or replace function app.log_event_spec_activity()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_actor uuid := app.profile_id();
  v_name  text;
  v_text  text;
begin
  select full_name into v_name from profiles where id = v_actor;
  v_text := app.event_spec_text(new.version, new.source, new.file_name, new.url, new.title);

  if tg_op = 'INSERT' then
    insert into event_activity (event_id, kind, actor_profile_id, actor_name, note)
    values (new.event_id, 'spec_added'::event_activity_kind, v_actor, v_name,
            'הועלה מפרט: ' || v_text);
    return new;
  end if;

  -- הסרה היא UPDATE (מחיקה רכה), ולכן היא נבדקת כאן. שחזור הוא אותו מעבר בכיוון
  -- ההפוך ומקבל שורה משלו — יומן שמדלג על שחזור משקר.
  if (old.deleted_at is null) is distinct from (new.deleted_at is null) then
    insert into event_activity (event_id, kind, actor_profile_id, actor_name, note)
    values (new.event_id,
            (case when new.deleted_at is null then 'spec_added' else 'spec_removed' end)::event_activity_kind,
            v_actor, v_name,
            (case when new.deleted_at is null then 'שוחזר מפרט: ' else 'הוסר מפרט: ' end) || v_text);
  end if;
  return new;
end $$;

create trigger event_specs_activity after insert or update on event_specs
  for each row execute function app.log_event_spec_activity();

-- ===== 6. RLS ==============================================================
-- התבנית היא event_activity (0016), כולל עטיפת (select app.has(...)) שנדרשת
-- מאז 0028 כדי שהתנאי יהפוך ל-InitPlan ולא ירוץ פר-שורה.
--
-- ה-exists על events אינו קישוט: הוא זה שמחיל על המפרט את סקופ האירועים של
-- המשתמש (0013), בלי לשכפל את הפרדיקט לכאן.

alter table event_specs enable row level security;

create policy event_specs_select on event_specs for select to authenticated using (
  ((select app.is_admin()) or deleted_at is null)
  and ((select app.is_admin())
       or ((select app.user_kind()) = 'staff'
           and (select app.has('events.specs_view'))
           and exists (select 1 from events e where e.id = event_specs.event_id))));

create policy event_specs_insert on event_specs for insert to authenticated with check (
  ((select app.is_admin()) or (select app.has('events.specs_manage')))
  and exists (select 1 from events e where e.id = event_specs.event_id));

-- אין פוליסת update ואין פוליסת delete, במכוון. גרסה שנרשמה אינה משתנה, והסרתה
-- עוברת ב-remove_event_spec (סעיף 7) — מאותה סיבה בדיוק ש-soft_delete של אירוע
-- הוא RPC מסוג security definer מאז 0012: פוסטגרס מחילה את פוליסת ה-select גם
-- על השורה *החדשה* ב-UPDATE, ולכן שורה אינה יכולה להעלים את עצמה מעיני מי
-- שמחק אותה. מחיקה רכה תחת RLS אינה ניתנת לביטוי, והפתרון של הרפו הוא RPC.

-- ===== 7. הסרת גרסה =======================================================
-- security definer, ולכן הוא זה שאוכף את המפתח בעצמו. אותו חוזה כמו
-- soft_delete(p_table, p_id, p_restore) מ-0012, רק ממוקד: הוא אינו מקבל שם
-- טבלה, ואי אפשר להפנות אותו לשום מקום אחר.

create or replace function remove_event_spec(p_spec_id uuid, p_restore boolean default false)
returns void language plpgsql security definer set search_path = public as $$
declare v_exists boolean;
begin
  perform app.require('events.specs_manage',
    case when p_restore then 'אין לך הרשאה לשחזר מפרט' else 'אין לך הרשאה להסיר מפרט' end);

  select true into v_exists from event_specs where id = p_spec_id;
  if v_exists is null then raise exception 'גרסת המפרט לא נמצאה'; end if;

  update event_specs
     set deleted_at = case when p_restore then null else now() end
   where id = p_spec_id;
end $$;

revoke execute on function remove_event_spec(uuid, boolean) from anon;

-- ===== 8. הדלי ופוליסות ה-Storage ==========================================
-- השער הוא פונקציה אחת, ובמכוון security invoker ולא definer: כך ה-exists על
-- events שבתוכה רץ תחת ה-RLS של הקורא, והסקופ שלו חל על הקבצים בלי שורת קוד
-- נוספת. app.has/app.is_admin הן definer בעצמן, ולכן הן עובדות מכאן.

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
    if app.user_kind() is distinct from 'staff' then return false; end if;
    if p_write and not app.has('events.specs_manage') then return false; end if;
    if not p_write and not app.has('events.specs_view') then return false; end if;
  end if;

  return exists (select 1 from events e where e.id = v_event);
end $$;

-- הבלוק מותנה כדי שהמיגרציות ירוצו כמו שהן גם על אשכול פוסטגרס נקי. אשכול
-- הבדיקות מקים storage מינימלי ב-00_bootstrap.sql, ולכן שם הוא כן רץ.
do $$
begin
  if to_regclass('storage.buckets') is null or to_regclass('storage.objects') is null then
    raise notice '0077: אין סכמת storage — הדלי והפוליסות מדולגים';
    return;
  end if;

  -- 25MB. מפרט שמגיע כצילום מטלפון שוקל 3-8MB; PDF של אולם שלם מגיע ל-20.
  execute $sql$
    insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
    values ('event-specs', 'event-specs', false, 26214400, array[
      'application/pdf',
      'image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/heif'])
    on conflict (id) do update set
      public             = false,
      file_size_limit    = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types
  $sql$;

  -- הפוליסות בבלוק משלהן, עם מטפל בחריגה, ולא מתוך זהירות כללית:
  -- ב-Supabase ‏storage.objects שייכת ל-supabase_storage_admin, ו-postgres —
  -- התפקיד שמריץ מיגרציות — אינו חבר בו. ‏CREATE POLICY דורש בעלות, ולכן
  -- בפרויקט אמיתי הפקודות האלה נדחות ב-42501. זו תכונה קבועה של הפלטפורמה,
  -- לא תקלה, והמיגרציה כולה אינה צריכה ליפול בגללה: מה שהיא מוסיפה כאן הוא
  -- שער, וכשהשער חסר RLS דוחה הכול ממילא. הכשל סגור — העלאה לא תעבוד, אך
  -- שום קובץ אינו נחשף.
  --
  -- ה-insert על storage.buckets נשאר מחוץ למטפל במכוון: הוא כן מצליח
  -- (‏postgres מחזיק INSERT על הטבלה), ואם דווקא הוא ייפול זו שגיאה אמיתית.
  begin
    execute 'drop policy if exists event_specs_objects_read   on storage.objects';
    execute 'drop policy if exists event_specs_objects_insert on storage.objects';
    execute 'drop policy if exists event_specs_objects_update on storage.objects';
    execute 'drop policy if exists event_specs_objects_delete on storage.objects';

    execute $sql$
      create policy event_specs_objects_read on storage.objects for select to authenticated
        using (bucket_id = 'event-specs' and app.may_touch_event_spec(name, false))
    $sql$;
    execute $sql$
      create policy event_specs_objects_insert on storage.objects for insert to authenticated
        with check (bucket_id = 'event-specs' and app.may_touch_event_spec(name, true))
    $sql$;
    execute $sql$
      create policy event_specs_objects_update on storage.objects for update to authenticated
        using (bucket_id = 'event-specs' and app.may_touch_event_spec(name, true))
        with check (bucket_id = 'event-specs' and app.may_touch_event_spec(name, true))
    $sql$;
    -- delete נדרש: העלאה שהקובץ שלה עלה אך שורת ה-DB נדחתה מנקה אחריה את
    -- האובייקט, אחרת כל דחיית RLS משאירה קובץ יתום בדלי.
    execute $sql$
      create policy event_specs_objects_delete on storage.objects for delete to authenticated
        using (bucket_id = 'event-specs' and app.may_touch_event_spec(name, true))
    $sql$;
  exception when insufficient_privilege then
    raise warning '0077: אין בעלות על storage.objects — ארבע פוליסות המפרט לא נוצרו. יש להגדיר אותן ב-Dashboard → Storage → Policies על הדלי event-specs, עם הביטוי app.may_touch_event_spec(name, <false לקריאה / true לכתיבה>). עד אז RLS דוחה כל גישה לקבצים.';
  end;
end $$;
