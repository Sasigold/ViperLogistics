-- 0169: הצעת מחיר ללקוח הקצה — מסמך, מספר, ושליחה שנרשמת
--
-- לוייפר יש מנוע תמחור מצוין ואין מסמך מסחרי אחד. ‏`docs/ROADMAP.md` §1.5
-- מנסח את זה במפורש: "אין הצעת מחיר, אין הזמנת עבודה חתומה, אין חשבונית".
-- הקובץ הזה סוגר את החוליה הראשונה — **הצעת מחיר** — ולא יותר מזה.
--
-- מי מקבל את המסמך: **לקוח הקצה**, שהוא הלקוח של הלקוח. קיסר מביאה את
-- האירוע, ומי שמשלם ומי שקורא את ההצעה הוא בעל השמחה. לכן המסמך פונה אל
-- `events.end_client_name` ואל `event_contacts`, ולא אל `customers.contact_*`
-- שהם אנשי הקשר של קיסר עצמה.
--
-- חמש הכרעות:
--
--   1. **הדגל, לא השם.** ‏`customers.quote_enabled` הוא מה שהלוגיקה בודקת,
--      וההצמדה לקיסר היא `update` חד-פעמי לפי שם — בדיוק כמו הדלקת
--      `performed_by_enabled` לארקו ב-0120 ו-`commission_pct` לקיסר ב-0143.
--      לקוח נוסף בעתיד הוא שורה במסד, לא שורת קוד.
--   2. **מספר המסמך הוא מספר האירוע.** לא נוצר מספור שני שיכול לסתור אותו.
--      ‏`version` קיים לצדו כהיסטוריה פנימית — הפקה שנייה של אותה הצעה היא
--      גרסה 2 של אותו מספר מסמך — והוא אינו מודפס על הנייר.
--   3. **צילום ולא הפניה.** ‏`event_quotes` שומרת את השורות, הסכומים, תנאי
--      התשלום וההערות **כפי שהודפסו**. מחיר שישתנה מחר לא ישכתב הצעה שכבר
--      נשלחה ללקוח; מסמך מסחרי שמשנה את עצמו למפרע אינו ראיה.
--   4. **הנתיב בדלי הוא החוזה** — `<event_id>/<uuid>.pdf` — ולכן ההרשאה על
--      הקובץ היא ההרשאה על האירוע, בלי טבלת הצטלבות. אותו דפוס של 0077.
--   5. **היומן מדווח על שליחה, לא על הפקה.** הורדה למחשב אינה אירוע מול
--      הלקוח; שליחה כן. הטריגר כותב שורה רק כש-`sent_at` עובר מ-null לערך.
--
-- ובדרך נסגר עוד פער קטן מה-ROADMAP (§1.6): `events.payment_terms`. תנאי
-- התשלום מודפסים על ההצעה, ולכן הם חייבים להיות שדה של האירוע ולא הערה
-- שנכתבת בגוף המסמך בכל פעם מחדש.

-- ===== 1. ערך היומן החדש ==================================================
-- בראש הקובץ במכוון: ערך enum חדש אינו ניתן לשימוש באותה טרנזקציה שהוסיפה
-- אותו. אותו סידור של 0049, 0077, 0107 ו-0113.

alter type event_activity_kind add value if not exists 'quote_sent';

-- ===== 2. הדגל פר-לקוח ====================================================

alter table customers add column quote_enabled boolean not null default false;

comment on column customers.quote_enabled is
  'האם דף האירוע של הלקוח מציע הפקת הצעת מחיר ללקוח הקצה (0169). הדגל הוא מה '
  'שהלוגיקה בודקת — ההצמדה לקיסר היא נתון חד-פעמי, לא קוד.';

-- הדלקה לקיסר — נתון, לא קוד. אין לקוח כזה (אשכול בדיקות) ⇒ אפס שורות.
update customers set quote_enabled = true
 where name ilike '%קיסר%' and deleted_at is null;

-- ===== 3. תנאי תשלום הם שדה של האירוע =====================================
-- ‏ROADMAP §1.6 מבקש גם מסגרת אשראי ושוטף+X פר-לקוח; זה מחוץ להיקף כאן.
-- מה שנדרש למסמך הוא המשפט שיודפס בו, והוא נקבע פר-אירוע.

alter table events add column payment_terms text;

insert into form_fields (field_key, label_he, sort_order) values
  ('payment_terms', 'תנאי תשלום', 24)
on conflict (field_key) do nothing;

-- ‏app.seed_customer_defaults() רץ רק ללקוחות חדשים. השדה נכנס **גלוי**,
-- כברירת המחדל של 0009 ולא כזו של 0017: תנאי תשלום אינם מספר רגיש, והם
-- שאלה שנשאלת בכל אירוע אצל כל לקוח.
insert into customer_form_fields (customer_id, field_key, state)
select c.id, 'payment_terms', 'visible'::field_state
from customers c
on conflict do nothing;

-- במרשם השדות: לא רגיש, נראה לכל מי שרואה אירוע, ונערך עם `events.edit`
-- הגנרי — אין לו מפתח עריכה משלו.
select app.register_field('event', 'payment_terms', 'תנאי תשלום', 'events',
  'events', 'payment_terms', false, true, true, null, 155);

-- ‏`events_secure` נבנה מהעמודות של הטבלה (0012), ולכן הוא צריך להיבנות
-- מחדש אחרי שנוספה לה אחת.
select app.rebuild_secure_view('events');

-- ===== 4. ההרשאות =========================================================
-- מודול events קיים. שני מפתחות ולא אחד, באותו פיצול של 0113 על המפרט:
-- "מי רואה שהופקה הצעה" ו"מי מפיק ושולח" הן שתי שאלות.
--
-- applies_to = staff בלבד. הצעת מחיר היא הדיון הכספי של המשרד מול לקוח
-- הקצה; משתמש לקוח אינו מפיק אותה בשם וייפר, וקבלן אינו צד לה.

select app.register_permission('events.quote_view', 'events', 'צפייה בהצעות המחיר של האירוע',
  'ההצעות שהופקו לאירוע, הסכומים שבהן ומתי נשלחו', 'access', false, false,
  array['staff']::user_kind[], 'events.edit', 230);

select app.register_permission('events.quote_send', 'events', 'הפקה ושליחה של הצעת מחיר',
  'הפקת מסמך הצעת מחיר ללקוח הקצה ושליחתו אליו', 'action', false, false,
  array['staff']::user_kind[], 'events.quote_view', 240);

-- ‏`applies_to` כבר סוגר את שני הקהלים האחרים, ולכן אין כאן שורות
-- `kind_permission_defaults` — בדיוק כמו מפתחות המפרט ב-0077. מה שנשאר
-- לכתוב הוא הדחייה לשלושת תפקידי השטח: `events.quote_view` נגזר מ-
-- `events.edit`, ותפקיד שטח שמחזיק אותו במקום כלשהו היה יורש איתו גם את
-- הצעות המחיר. שכבת התפקיד מדברת לפני ההיסק, ולכן שש השורות גוברות.
insert into role_permissions (role_id, permission_key, allowed)
select r.id, k, false
from permission_roles r, unnest(array['events.quote_view', 'events.quote_send']) k
where r.key in ('worker', 'driver', 'team_lead')
on conflict (role_id, permission_key) do update set allowed = false;

-- ===== 5. הטבלה ===========================================================
-- ‏`lines` הוא הצילום: מה שהודפס, בסדר שבו הודפס, עם התוויות והסכומים כפי
-- שהלקוח קרא אותם. שדות הסכום יושבים בעמודות משלהם ולא נגזרים מה-jsonb, כי
-- "כמה נשלח ללקוח" היא שאלה שנשאלת בשאילתה.

create table event_quotes (
  id              uuid primary key default gen_random_uuid(),
  event_id        uuid not null references events(id) on delete cascade,
  -- נקבע בטריגר ולא על ידי הקליינט. ראו סעיף 6.
  version         int  not null,
  -- צילום של events.event_number בזמן ההפקה. אותו מספר בכל הגרסאות; אירוע
  -- שמספרו ישתנה מחר לא ישכתב מסמך שכבר יצא.
  document_number text not null check (btrim(document_number) <> ''),
  storage_path    text not null,
  file_name       text not null check (btrim(file_name) <> ''),
  size_bytes      bigint check (size_bytes is null or size_bytes >= 0),
  -- [{ kind, label, when_text, amount }] — השורות כפי שהודפסו
  lines           jsonb not null default '[]'::jsonb
                  check (jsonb_typeof(lines) = 'array'),
  subtotal        numeric(12,2) not null,
  vat_pct         numeric(5,2)  not null check (vat_pct >= 0),
  vat_amount      numeric(12,2) not null,
  total           numeric(12,2) not null,
  payment_terms   text,
  -- ההערות הידניות שהמפיק הוסיף. המשפט הקבוע נבנה בקליינט ואינו נשמר כאן:
  -- הוא נגזר ממספר האירוע, משם הלקוח ומתאריך השליחה, ושלושתם כבר בשורה.
  notes           text,
  -- מדונרמל לצד ה-FK, מאותה סיבה שכתובה ב-0016 על actor_name: פרופיל יכול
  -- להימחק, והיסטוריה ששכחה מי הפיק אינה היסטוריה.
  issued_by       uuid references profiles(id) on delete set null,
  issuer_name     text,
  sent_at         timestamptz,
  created_at      timestamptz not null default now(),
  deleted_at      timestamptz
);

-- הייחודי אוכף את המספור (כולל המחוקות — מספר גרסה שירדה אינו חוזר
-- לשימוש), והחלקי משרת את קריאת המסך.
create unique index event_quotes_version_uk on event_quotes (event_id, version);
create index event_quotes_event_live_idx on event_quotes (event_id, version desc)
  where deleted_at is null;

revoke all on event_quotes from anon;

comment on table event_quotes is
  'הצעת מחיר שהופקה לאירוע ונשלחה ללקוח הקצה (0169). מספר המסמך הוא מספר '
  'האירוע; version הוא היסטוריה פנימית ואינו מודפס.';

-- ===== 6. מספור הגרסאות וזהות המפיק =======================================
-- שתי הפקות במקביל לאותו אירוע היו קוראות את אותו max() ונופלות על האינדקס
-- הייחודי. הנעילה פר-אירוע ומשתחררת בסוף הטרנזקציה — היא מעכבת רק הפקה
-- שנייה לאותו אירוע ממש. אותו גוף של app.event_spec_before_insert (0077).

create or replace function app.event_quote_before_insert()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_actor uuid := app.profile_id();
begin
  perform pg_advisory_xact_lock(hashtextextended(new.event_id::text, 0));
  select coalesce(max(version), 0) + 1 into new.version
    from event_quotes where event_id = new.event_id;

  new.issued_by   := v_actor;
  new.issuer_name := (select full_name from profiles where id = v_actor);
  -- הצעה אינה נולדת מחוקה
  new.deleted_at  := null;
  return new;
end $$;

create trigger event_quotes_before_insert before insert on event_quotes
  for each row execute function app.event_quote_before_insert();

-- העדכונים החוקיים על שורה קיימת הם שניים: סימון שנשלחה, והסרה/שחזור.
-- מי שיחליף את storage_path או את הסכומים של הצעה שכבר נשלחה ישכתב מסמך
-- שהלקוח מחזיק בידו — ולכן החסימה יושבת בטריגר, שחל גם בנתיב security
-- definer שבו RLS אינה קיימת.
create or replace function app.event_quote_before_update()
returns trigger language plpgsql set search_path = public as $$
begin
  if new.event_id        is distinct from old.event_id
  or new.version         is distinct from old.version
  or new.document_number is distinct from old.document_number
  or new.storage_path    is distinct from old.storage_path
  or new.file_name       is distinct from old.file_name
  or new.lines           is distinct from old.lines
  or new.subtotal        is distinct from old.subtotal
  or new.vat_pct         is distinct from old.vat_pct
  or new.vat_amount      is distinct from old.vat_amount
  or new.total           is distinct from old.total
  or new.notes           is distinct from old.notes
  or new.payment_terms   is distinct from old.payment_terms
  or new.issued_by       is distinct from old.issued_by
  or new.created_at      is distinct from old.created_at then
    raise exception 'הצעת מחיר שהופקה אינה ניתנת לשינוי — אפשר להפיק גרסה חדשה';
  end if;

  -- שליחה קורית פעם אחת. שליחה חוזרת היא גרסה חדשה, אחרת "מתי נשלח" הופך
  -- לשאלה שאין לה תשובה אחת.
  if old.sent_at is not null and new.sent_at is distinct from old.sent_at then
    raise exception 'הצעת מחיר שנשלחה אינה נשלחת שוב — יש להפיק גרסה חדשה';
  end if;
  return new;
end $$;

create trigger event_quotes_before_update before update on event_quotes
  for each row execute function app.event_quote_before_update();

-- ===== 7. יומן הפעילות ====================================================
-- הטקסט נכתב ל-note ולא ל-old_value/new_value, מאותו נימוק של 0049 ו-0077:
-- אלה שייכים לרישום 'changed', שבו יש שדה שעבר מערך לערך. כאן אין שדה — יש
-- מסמך שנשלח. ‏field_key נשאר null, ולכן השורה עוברת את המסנן של
-- event_activity_feed (0016).
--
-- **רק שליחה נרשמת.** הפקה שנעצרה בהורדה למחשב אינה אירוע מול הלקוח, ושורת
-- יומן שאומרת "נשלחה הצעה" על מסמך שלא יצא היא שקר על מה שקרה.

create or replace function app.log_event_quote_activity()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_actor uuid := app.profile_id();
  v_name  text;
begin
  if new.sent_at is null then return new; end if;
  if tg_op = 'UPDATE' and old.sent_at is not null then return new; end if;

  select full_name into v_name from profiles where id = v_actor;

  insert into event_activity (event_id, kind, actor_profile_id, actor_name, note)
  values (new.event_id, 'quote_sent'::event_activity_kind, v_actor, v_name,
          concat_ws(' · ',
            'נשלחה הצעת מחיר מס׳ ' || new.document_number,
            'סה״כ ' || trim(to_char(new.total, 'FM999,999,999.00')) || ' ₪',
            case when new.version > 1 then 'גרסה ' || new.version end));
  return new;
end $$;

create trigger event_quotes_activity after insert or update on event_quotes
  for each row execute function app.log_event_quote_activity();

-- ===== 8. RLS =============================================================
-- התבנית היא event_specs (0077), כולל עטיפת (select app.has(...)) שנדרשת
-- מאז 0028. ה-exists על events הוא מה שמחיל את סקופ האירועים של הקורא (0013)
-- על ההצעות, בלי לשכפל את הפרדיקט לכאן.

alter table event_quotes enable row level security;

create policy event_quotes_select on event_quotes for select to authenticated using (
  ((select app.is_admin()) or deleted_at is null)
  and ((select app.is_admin())
       or ((select app.user_kind()) = 'staff'
           and (select app.has('events.quote_view'))
           and exists (select 1 from events e where e.id = event_quotes.event_id))));

create policy event_quotes_insert on event_quotes for insert to authenticated with check (
  ((select app.is_admin()) or (select app.has('events.quote_send')))
  and exists (select 1 from events e where e.id = event_quotes.event_id));

-- ‏UPDATE קיים כאן, בשונה מ-event_specs: הכתיבה החוקית היחידה היא סימון
-- `sent_at`, והיא אינה מעלימה את השורה מעיני הכותב — ולכן היא כן ניתנת
-- לביטוי תחת RLS. הטריגר של סעיף 6 הוא זה שמצמצם אותה לשדה אחד.
create policy event_quotes_update on event_quotes for update to authenticated
  using (((select app.is_admin()) or (select app.has('events.quote_send')))
         and exists (select 1 from events e where e.id = event_quotes.event_id))
  with check (((select app.is_admin()) or (select app.has('events.quote_send')))
         and exists (select 1 from events e where e.id = event_quotes.event_id));

-- אין פוליסת delete: הצעה שהופקה נשארת בהיסטוריה. מחיקה שמורה ל-soft_delete
-- הגנרי של אדמין, כמו בכל שאר הרפו.

-- ===== 9. פרטי החברה ======================================================
-- מסמך שיוצא ללקוח קצה נושא את פרטי החברה, ועד היום לא היה להם מקום בכלל —
-- לא ח.פ, לא טלפון, לא כתובת מייל. הם נכנסים ל-app_settings ולא לקוד: מספר
-- טלפון שמשתנה אינו דורש פריסה.
--
-- הפוליסה `app_settings_write` (0046) כבר מכסה מפתח שאינו attendance.% ואינו
-- notifications.% תחת `settings.edit`, ולכן אין מה לגעת בה.
--
-- `vat_pct` יושב כאן ולא ב-finance.*: הוא מה שמודפס על המסמך הזה. מנוע
-- התמחור אינו יודע עליו דבר, ו-task_pricing.price נשאר מספר אחד לפני מע״מ.

insert into app_settings (key, value) values
  ('company.details', jsonb_build_object(
    'name',         'וייפר מיקור חוץ לעסקים בע״מ',
    'tax_id',       '516766748',
    'phone',        '0747600960',
    'email',        'office@viper-tech.co.il',
    'logo_path',    null,
    'vat_pct',      18,
    'quote_footer', 'מסמך זה נוצר ע״י וייפר מערכות'))
on conflict (key) do nothing;

-- ===== 10. היומן מכיר את תנאי התשלום ======================================
-- הגוף מ-0109 עם שורה אחת נוספת בכל אחד משני המערכים. שינוי בתנאי התשלום
-- הוא בדיוק סוג השינוי שהיומן קיים בשבילו: הוא מזיז כסף, והוא נעשה בשיחה.

create or replace function app.log_event_activity()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_actor uuid := app.profile_id();
  v_name  text;
  v_old   jsonb;
  v_new   jsonb;
  f       record;
begin
  select full_name into v_name from profiles where id = v_actor;

  if tg_op = 'INSERT' then
    insert into event_activity (event_id, kind, actor_profile_id, actor_name)
    values (new.id, 'created', v_actor, v_name);
    return new;
  end if;

  -- מחיקה רכה ושחזור הם UPDATE של deleted_at, ונקראים כשורות משל עצמם.
  if (old.deleted_at is null) <> (new.deleted_at is null) then
    insert into event_activity (event_id, kind, actor_profile_id, actor_name)
    values (new.id,
            (case when new.deleted_at is null then 'restored' else 'deleted' end)::event_activity_kind,
            v_actor, v_name);
  end if;

  v_old := to_jsonb(old);
  v_new := to_jsonb(new);

  for f in
    select * from unnest(
      array['event_date','end_client_name','event_number','customer_id','status_id',
            'location_text','location_notes','volume_m','truck_count','notes',
            'no_parking','porterage','supplier_pickup','approved_at','payment_terms'],
      array['תאריך אירוע','לקוח סופי','מספר אירוע','לקוח','סטטוס',
            'מיקום','הערות מיקום','נפח (קוב)','כמות משאיות','הערות',
            'ללא חניה','סבלות','איסוף מספק','אישור לביצוע','תנאי תשלום']) as t(col, label)
  loop
    if v_old -> f.col is distinct from v_new -> f.col then
      insert into event_activity (
        event_id, kind, actor_profile_id, actor_name, field_key, field_label, old_value, new_value)
      values (new.id, 'changed', v_actor, v_name, f.col, f.label,
              app.event_value_text(f.col, v_old -> f.col),
              app.event_value_text(f.col, v_new -> f.col));
    end if;
  end loop;

  if old.custom_fields is distinct from new.custom_fields then
    for f in
      select k.key as col,
             coalesce(ff.label_he, k.key) as label,
             ff.field_type as ftype,
             old.custom_fields -> k.key as old_val,
             new.custom_fields -> k.key as new_val
      from (select jsonb_object_keys(old.custom_fields || new.custom_fields) as key) k
      left join form_fields ff on ff.field_key = k.key
    loop
      if f.old_val is distinct from f.new_val then
        insert into event_activity (
          event_id, kind, actor_profile_id, actor_name, field_key, field_label, old_value, new_value)
        values (new.id, 'changed', v_actor, v_name, f.col, f.label,
                app.custom_value_text(f.ftype, f.old_val),
                app.custom_value_text(f.ftype, f.new_val));
      end if;
    end loop;
  end if;

  return new;
end $$;

-- ===== 11. create_event / update_event ====================================
-- גוף זהה ל-0068 (יצירה) ול-0125 (עדכון) מילה במילה, בתוספת עמודה אחת.
-- העמודות ב-create_event מפורטות בשמן מאז 0053, ולכן שדה חדש חייב להירשם
-- בשלוש הרשימות — אחרת הוא נכתב רק בעריכה ולעולם לא ביצירה.

create or replace function create_event(payload jsonb)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_customer_id uuid;
  v_profile_id uuid;
  v_event_id uuid;
  v_status uuid;
  r record;
begin
  v_profile_id := app.profile_id();

  if (select app.user_kind()) = 'customer_user' then
    v_customer_id := app.customer_id();
    if not app.has('events.create')
       or not exists (select 1 from customers c where c.id = v_customer_id
                      and c.can_create_events and c.deleted_at is null) then
      raise exception 'אין לך הרשאה ליצור אירועים' using errcode = '42501';
    end if;
    payload := app.strip_hidden_event_keys(v_profile_id, payload);
  elsif app.is_admin() or app.has('events.create') then
    v_customer_id := (payload ->> 'customer_id')::uuid;
    if v_customer_id is null then raise exception 'חובה לבחור לקוח'; end if;
    v_profile_id := null;
  else
    raise exception 'אין לך הרשאה ליצור אירועים' using errcode = '42501';
  end if;

  perform app.validate_event_payload(v_customer_id, v_profile_id, payload, false);

  if payload ->> 'event_date' is null then
    raise exception 'שדות חובה חסרים: תאריך אירוע';
  end if;

  v_status := coalesce((payload ->> 'status_id')::uuid,
    (select id from statuses where entity = 'event' and is_default and deleted_at is null limit 1));

  insert into events (customer_id, end_client_name, event_number, event_date,
    location_text, location_provider, location_place_id, location_lat, location_lng,
    location_notes, volume_m, truck_count, notes, payment_terms, status_id,
    no_parking, porterage, supplier_pickup, custom_fields, created_by)
  values (v_customer_id,
    nullif(payload ->> 'end_client_name',''),
    nullif(payload ->> 'event_number',''),
    (payload ->> 'event_date')::date,
    nullif(payload ->> 'location_text',''),
    nullif(payload ->> 'location_provider',''),
    nullif(payload ->> 'location_place_id',''),
    (payload ->> 'location_lat')::double precision,
    (payload ->> 'location_lng')::double precision,
    nullif(payload ->> 'location_notes',''),
    (nullif(payload ->> 'volume_m',''))::numeric,
    (nullif(payload ->> 'truck_count',''))::int,
    nullif(payload ->> 'notes',''),
    nullif(payload ->> 'payment_terms',''),
    v_status,
    coalesce((payload ->> 'no_parking')::boolean, false),
    coalesce((payload ->> 'porterage')::boolean, false),
    coalesce((payload ->> 'supplier_pickup')::boolean, false),
    app.event_custom_patch(v_customer_id, payload),
    app.profile_id())
  returning id into v_event_id;

  if nullif(payload ->> 'contact_name','') is not null
     or nullif(payload ->> 'contact_phone','') is not null then
    insert into event_contacts (event_id, contact_name, contact_phone)
    values (v_event_id, nullif(payload ->> 'contact_name',''), nullif(payload ->> 'contact_phone',''));
  end if;

  if payload ? 'supplier_ids' then
    for r in select value::uuid as sid from jsonb_array_elements_text(payload -> 'supplier_ids') loop
      insert into event_suppliers (event_id, supplier_id) values (v_event_id, r.sid)
      on conflict do nothing;
    end loop;
  end if;

  perform app.apply_event_income(v_event_id, v_customer_id, payload);

  perform app.system_write(true);
  perform app.apply_event_task_block(v_event_id, 'setup', payload);
  perform app.apply_event_task_block(v_event_id, 'teardown', payload);
  perform app.system_write(false);

  return v_event_id;
end $$;

create or replace function update_event(p_event_id uuid, payload jsonb)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_customer_id uuid;
  v_profile_id uuid;
  v_was_cancelled boolean;
  v_now_cancelled boolean;
  v_ev events;
  v_label text;
  v_changed boolean;
  v_spec_changed boolean;
  r record;
begin
  select customer_id into v_customer_id from events
    where id = p_event_id and deleted_at is null;
  if v_customer_id is null then raise exception 'אירוע לא נמצא'; end if;

  select (s.code = 'cancelled') into v_was_cancelled
    from events e left join statuses s on s.id = e.status_id
   where e.id = p_event_id;

  if not (app.is_admin()
          or ((select app.user_kind()) = 'staff' and app.has('events.edit'))
          or ((select app.user_kind()) = 'customer_user'
              and v_customer_id = app.customer_id()
              and app.has('events.edit'))) then
    raise exception 'אין לך הרשאה לערוך אירוע זה' using errcode = '42501';
  end if;

  if (select app.user_kind()) = 'customer_user' then
    v_profile_id := app.profile_id();
    payload := app.strip_hidden_event_keys(v_profile_id, payload);
  end if;

  perform app.validate_event_payload(v_customer_id, v_profile_id, payload, true);

  update events set
    end_client_name = case when payload ? 'end_client_name' then nullif(payload ->> 'end_client_name','') else end_client_name end,
    event_number    = case when payload ? 'event_number' then nullif(payload ->> 'event_number','') else event_number end,
    event_date      = case when payload ? 'event_date' then (payload ->> 'event_date')::date else event_date end,
    location_text   = case when payload ? 'location_text' then nullif(payload ->> 'location_text','') else location_text end,
    location_provider = case when payload ? 'location_provider' then nullif(payload ->> 'location_provider','') else location_provider end,
    location_place_id = case when payload ? 'location_place_id' then nullif(payload ->> 'location_place_id','') else location_place_id end,
    location_lat    = case when payload ? 'location_lat' then (payload ->> 'location_lat')::double precision else location_lat end,
    location_lng    = case when payload ? 'location_lng' then (payload ->> 'location_lng')::double precision else location_lng end,
    location_notes  = case when payload ? 'location_notes' then nullif(payload ->> 'location_notes','') else location_notes end,
    volume_m        = case when payload ? 'volume_m' then (nullif(payload ->> 'volume_m',''))::numeric else volume_m end,
    truck_count     = case when payload ? 'truck_count' then (nullif(payload ->> 'truck_count',''))::int else truck_count end,
    notes           = case when payload ? 'notes' then nullif(payload ->> 'notes','') else notes end,
    payment_terms   = case when payload ? 'payment_terms' then nullif(payload ->> 'payment_terms','') else payment_terms end,
    status_id       = case when payload ? 'status_id' then (payload ->> 'status_id')::uuid else status_id end,
    no_parking      = case when payload ? 'no_parking' then (payload ->> 'no_parking')::boolean else no_parking end,
    porterage       = case when payload ? 'porterage' then (payload ->> 'porterage')::boolean else porterage end,
    supplier_pickup = case when payload ? 'supplier_pickup' then (payload ->> 'supplier_pickup')::boolean else supplier_pickup end,
    -- מיזוג ולא החלפה: app.event_custom_patch מחזירה רק מפתחות שנשלחו
    custom_fields   = custom_fields || app.event_custom_patch(v_customer_id, payload)
  where id = p_event_id;

  if payload ? 'contact_name' or payload ? 'contact_phone' then
    insert into event_contacts (event_id, contact_name, contact_phone)
    values (p_event_id, nullif(payload ->> 'contact_name',''), nullif(payload ->> 'contact_phone',''))
    on conflict (event_id) do update set
      contact_name  = case when payload ? 'contact_name' then nullif(payload ->> 'contact_name','') else event_contacts.contact_name end,
      contact_phone = case when payload ? 'contact_phone' then nullif(payload ->> 'contact_phone','') else event_contacts.contact_phone end;
  end if;

  if payload ? 'supplier_ids' then
    delete from event_suppliers where event_id = p_event_id;
    insert into event_suppliers (event_id, supplier_id)
    select p_event_id, value::uuid from jsonb_array_elements_text(payload -> 'supplier_ids')
    on conflict do nothing;
  end if;

  perform app.apply_event_income(p_event_id, v_customer_id, payload);

  perform app.system_write(true);
  perform app.apply_event_task_block(p_event_id, 'setup', payload);
  perform app.apply_event_task_block(p_event_id, 'teardown', payload);
  perform app.system_write(false);

  -- ===== הזנב (0112): הלקוח שמר — המנהל שומע. ו-0115/0125: והאישור יורד =====
  if (select app.user_kind()) = 'customer_user' then
    select * into v_ev from events where id = p_event_id;
    select (s.code = 'cancelled') into v_now_cancelled
      from statuses s where s.id = v_ev.status_id;

    -- הגלאי של 0112 (כל שינוי) — לתוך משתנה ולפני כל כתיבה נוספת ליומן.
    v_changed := exists (select 1 from event_activity
                          where event_id = p_event_id
                            and created_at >= transaction_timestamp()
                            and kind <> 'note');

    -- ‏0125: גלאי האישור מחריג שינוי-סטטוס-בלבד. `status_id` נרשם עם
    -- ‏field_key='status_id' (0016), והוא תכנון ולא מפרט — בדיוק כפי שהטריגר
    -- של הלו״ז מחריג אותו. שאר השדות (כולל בלוקי הקמה/פירוק, שגם הם נכתבים
    -- ליומן מ-0112) עדיין מפילים את האישור.
    v_spec_changed := exists (select 1 from event_activity
                               where event_id = p_event_id
                                 and created_at >= transaction_timestamp()
                                 and kind <> 'note'
                                 and not (kind = 'changed' and field_key = 'status_id'));

    -- ‏0115: מה שהמשרד אישר אינו מה שעומד עכשיו בטופס. רק עריכת ה**לקוח**
    -- מבטלת. הכתיבה עטופה ב-system_write כי app.events_approval_guard (0109)
    -- דוחה כל נגיעה ישירה בשתי העמודות. מעבר ל"בוטל" מפיל אף הוא — צירוף
    -- "מבוטל + מאושר" הוא השטות היחידה בלוח השנה.
    if (v_spec_changed or coalesce(v_now_cancelled, false)) and v_ev.approved_at is not null then
      perform app.system_write(true);
      update events set approved_at = null, approved_by = null
       where id = p_event_id;
      perform app.system_write(false);
    end if;

    -- מעבר ל"בוטל" מדווח על ידי events_notify_cancelled — לא פעמיים
    if coalesce(v_now_cancelled, false) and not coalesce(v_was_cancelled, false) then
      return;
    end if;
    -- הגלאי: שמירה שלא כתבה שורת יומן לא שינתה דבר
    if not v_changed then
      return;
    end if;
    if not app.notification_in_scope('event_updated', 'customer', v_customer_id) then
      return;
    end if;

    v_label := coalesce(v_ev.end_client_name, v_ev.event_number,
                        to_char(v_ev.event_date, 'DD/MM/YYYY'));
    for r in select id from profiles
      where is_admin and is_active and deleted_at is null
        and id is distinct from app.profile_id()
    loop
      perform app.notify(r.id, 'event_updated', 'לקוח עדכן אירוע',
        (select name from customers where id = v_customer_id) || ' — ' || v_label,
        'event', p_event_id);
    end loop;
  end if;
end $$;

-- ===== 12. הדלי של ההצעות ופוליסות ה-Storage ==============================
-- השער הוא פונקציה אחת, security invoker במכוון ולא definer: כך ה-exists על
-- events שבתוכה רץ תחת ה-RLS של הקורא, והסקופ שלו חל על הקבצים בלי שורת קוד
-- נוספת. אותו חוזה של app.may_touch_event_spec (0077).

create or replace function app.may_touch_event_quote(p_name text, p_write boolean)
returns boolean language plpgsql stable set search_path = public as $$
declare v_event uuid;
begin
  -- הנתיב הוא החוזה. כל דבר שאינו '<uuid>/...' בדלי הזה אינו שלנו.
  begin
    v_event := split_part(p_name, '/', 1)::uuid;
  exception when others then
    return false;
  end;

  if not app.is_admin() then
    if app.user_kind() is distinct from 'staff' then return false; end if;
    if p_write and not app.has('events.quote_send') then return false; end if;
    if not p_write and not app.has('events.quote_view') then return false; end if;
  end if;

  return exists (select 1 from events e where e.id = v_event);
end $$;

-- הלוגו הוא נכס של החברה ולא של אירוע, ולכן דלי שני ושער שני. הקריאה פתוחה
-- לכל מאומת — לוגו אינו סוד, וכל מי שמפיק מסמך צריך אותו — והכתיבה היא של
-- מי שמנהל הגדרות.
create or replace function app.may_touch_company_asset(p_write boolean)
returns boolean language sql stable set search_path = public as $$
  select case when p_write then app.is_admin() or app.has('settings.edit') else true end
$$;

do $$
begin
  if to_regclass('storage.buckets') is null or to_regclass('storage.objects') is null then
    raise notice '0169: אין סכמת storage — הדלים והפוליסות מדולגים';
    return;
  end if;

  -- ‏10MB. הצעת מחיר היא PDF וקטורי בן עמוד או שניים; מי שמגיע לשם חורג
  -- מהתבנית ולא מהמגבלה.
  execute $sql$
    insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
    values ('event-quotes', 'event-quotes', false, 10485760, array['application/pdf'])
    on conflict (id) do update set
      public             = false,
      file_size_limit    = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types
  $sql$;

  -- ‏PNG/JPEG בלבד, ולא מתוך שמרנות: pdf-lib מטמיע את שני הפורמטים האלה
  -- ואינו יודע לרנדר SVG. דלי שמקבל SVG היה מבטיח לוגו שלא יופיע במסמך.
  execute $sql$
    insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
    values ('company-assets', 'company-assets', false, 2097152, array['image/png', 'image/jpeg'])
    on conflict (id) do update set
      public             = false,
      file_size_limit    = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types
  $sql$;

  -- הפוליסות בבלוק משלהן עם מטפל בחריגה, מאותה סיבה שכתובה ב-0077 §8:
  -- ב-Supabase ‏storage.objects שייכת ל-supabase_storage_admin, ו-postgres
  -- אינו חבר בו. הכשל סגור — העלאה לא תעבוד, ושום קובץ אינו נחשף.
  begin
    execute 'drop policy if exists event_quotes_objects_read   on storage.objects';
    execute 'drop policy if exists event_quotes_objects_insert on storage.objects';
    execute 'drop policy if exists event_quotes_objects_update on storage.objects';
    execute 'drop policy if exists event_quotes_objects_delete on storage.objects';

    execute $sql$
      create policy event_quotes_objects_read on storage.objects for select to authenticated
        using (bucket_id = 'event-quotes' and app.may_touch_event_quote(name, false))
    $sql$;
    execute $sql$
      create policy event_quotes_objects_insert on storage.objects for insert to authenticated
        with check (bucket_id = 'event-quotes' and app.may_touch_event_quote(name, true))
    $sql$;
    execute $sql$
      create policy event_quotes_objects_update on storage.objects for update to authenticated
        using (bucket_id = 'event-quotes' and app.may_touch_event_quote(name, true))
        with check (bucket_id = 'event-quotes' and app.may_touch_event_quote(name, true))
    $sql$;
    -- delete נדרש: הפקה שהקובץ שלה עלה אך שורת ה-DB נדחתה מנקה אחריה, אחרת
    -- כל דחיית RLS משאירה קובץ יתום בדלי.
    execute $sql$
      create policy event_quotes_objects_delete on storage.objects for delete to authenticated
        using (bucket_id = 'event-quotes' and app.may_touch_event_quote(name, true))
    $sql$;

    execute 'drop policy if exists company_assets_objects_read   on storage.objects';
    execute 'drop policy if exists company_assets_objects_write  on storage.objects';
    execute 'drop policy if exists company_assets_objects_update on storage.objects';
    execute 'drop policy if exists company_assets_objects_delete on storage.objects';

    execute $sql$
      create policy company_assets_objects_read on storage.objects for select to authenticated
        using (bucket_id = 'company-assets' and app.may_touch_company_asset(false))
    $sql$;
    execute $sql$
      create policy company_assets_objects_write on storage.objects for insert to authenticated
        with check (bucket_id = 'company-assets' and app.may_touch_company_asset(true))
    $sql$;
    execute $sql$
      create policy company_assets_objects_update on storage.objects for update to authenticated
        using (bucket_id = 'company-assets' and app.may_touch_company_asset(true))
        with check (bucket_id = 'company-assets' and app.may_touch_company_asset(true))
    $sql$;
    execute $sql$
      create policy company_assets_objects_delete on storage.objects for delete to authenticated
        using (bucket_id = 'company-assets' and app.may_touch_company_asset(true))
    $sql$;
  exception when insufficient_privilege then
    raise warning '0169: אין בעלות על storage.objects — פוליסות הדלים event-quotes ו-company-assets לא נוצרו. יש להגדיר אותן ב-Dashboard → Storage → Policies עם הביטויים app.may_touch_event_quote(name, <false/true>) ו-app.may_touch_company_asset(<false/true>). עד אז RLS דוחה כל גישה לקבצים.';
  end;
end $$;
