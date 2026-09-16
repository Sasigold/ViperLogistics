-- 0176: האירוע מגיע מ-ViperFlow
--
-- ‏שיא עיצובים מנהלת את ההזמנות שלה ב-ViperFlow: שם יושבים הלקוח הסופי, תאריך
-- האירוע, האולם, שעת האספקה, שעת ההחזרה ורשימת הריהוט. אצלנו יושבת העבודה —
-- מי נוסע, מתי יוצאים מהמחסן, כמה עובדים, איזו משאית. עד היום החיבור בין
-- השניים היה אדם: מישהו קרא הזמנה במסך אחד והקליד אירוע במסך אחר, ובכל פעם
-- שהשעה זזה ב-ViperFlow מישהו היה צריך לזכור לחזור ולהזיז אותה גם כאן.
--
-- ‏ViperFlow כבר יודע לספר. יש לו API ציבורי ו-Webhooks חתומים (‏docs/API.md,
-- ‏docs/WEBHOOKS.md אצלו), והם מספרים על *כל* שינוי בהזמנה. שתי המיגרציות
-- ‏0176 ו-0177 הן הצד שלנו של אותה שיחה: הטבלאות, ההרשאות ומסך המשרד (כאן),
-- והתרגום מהזמנה לאירוע, למשימות שלו ולרשימת הריהוט (0177). המסך שמציג את
-- הרשימה הוא קוד לקוח בלבד ואין לו מיגרציה — הוא קורא את הטבלה שכאן.
--
-- חמש הכרעות יושבות בקובץ הזה:
--
--   1. **הסוד אינו במסד.** מפתח החתימה של ה-Webhook ומפתח ה-API של ViperFlow
--      הם סודות של פונקציית הקצה בלבד (`VIPERFLOW_WEBHOOK_SECRET`,
--      `VIPERFLOW_API_KEY`), ואינם נכתבים לשום טבלה ואינם נקראים בשום RPC.
--      ‏`app_settings` קריאה לכל משתמש מאומת (0005), וסוד שיושב בטבלה הוא סוד
--      שדולף ברגע שמישהו מוסיף לה עמודה למסך. מה שכן יושב כאן הוא *החיבור* —
--      לאיזה לקוח ההזמנות נכנסות, ומהי כתובת ה-API — וזה תצורה ולא סוד.
--
--   2. **אין מחירים.** ‏`viperflow_order_items` אינה מחזיקה עמודת מחיר, ולא
--      במקרה: הבקשה היא "רשימת הריהוט בלי מחירים", והדרך היחידה להבטיח שמחיר
--      לא ידלוף היא שלא יהיה לו מקום לשבת בו. ‏`unit_price`, `line_total`,
--      ‏`discount_percent` ו-`totals` מנוקים בפונקציית הקצה *לפני* שהמעטפה
--      נכתבת, והמתרגם (0177) אינו קורא אותם גם אם שרדו. שתי שכבות, כי שכבה
--      אחת היא הבטחה ושתיים הן מבנה.
--
--   3. **המעטפה נשמרת, ולא רק תוצאתה.** ‏ViperFlow שומר אצלו אירועי Webhook
--      שלושים יום בלבד. שורה ב-`viperflow_deliveries` היא מה שמאפשר להריץ
--      מחדש משלוח שנפל אצלנו — גם חודשיים אחרי, וגם בלי לבקש מהצד השני דבר.
--      זו גם הסיבה שכישלון *עסקי* אינו מחזיר שגיאת HTTP: ראו 0177 §6.
--
--   4. **המזהה של האירוע הוא מזהה ההזמנה, לא מספרה.** ‏`viperflow_links`
--      קושרת אירוע אחד להזמנה אחת לפי ה-uuid שלה. מספר ההזמנה
--      (`order_number`) הוא תצוגה — הוא יכול להשתנות, והוא גם יכול להתנגש
--      במספר אירוע שאדם הקליד — ולכן הוא נשמר אך אינו המפתח.
--
--   5. **הקריאה נגזרת מהאירוע.** אף טבלה כאן אינה כותבת פרדיקט ראייה משלה:
--      ‏`exists (select 1 from events e where e.id = …)` הוא שמחיל את כל היקפי
--      הראייה של `events_select` (0013) — עובד שרואה רק את האירוע ששובץ אליו
--      רואה רק את הריהוט שלו. אותו דפוס בדיוק של `event_specs` (0077 §6).
--
-- הכתיבה כולה שייכת ל-`service_role`: פונקציית הקצה היא הכותב היחיד, ואין
-- לאף טבלה כאן פוליסת insert/update/delete. משתמש מאומת קורא, ומשנה תצורה
-- דרך ה-RPC-ים שבסעיף 6 בלבד.

-- ===== 1. ערך יומן חדש ====================================================
-- בראש הקובץ במכוון, מאותה סיבה שכתובה ב-0077 §1: ערך enum חדש אינו ניתן
-- לשימוש באותה טרנזקציה שהוסיפה אותו, ו-psql מריץ כל פקודה בטרנזקציה משלה.
--
-- ‏'synced' ולא 'note'. הערה היא מלל שאדם כתב אל מי שנוסע לאירוע, והיא פתוחה
-- לשטח בדיוק בגלל זה (0129). סנכרון הוא רשומת מערכת — "ההזמנה עודכנה
-- ב-ViperFlow וההקמה זזה בשעה" — ולכן הוא נופל תחת
-- `events.activity_system_view` כמו כל שאר ההיסטוריה התפעולית, בלי שורת
-- מדיניות נוספת.

alter type event_activity_kind add value if not exists 'synced';

-- ===== 2. מי כותב ביומן כשאיש לא לחץ =====================================
--
-- כל כותבי היומן — האירוע (0016), המשימה (0112/0136), המפרט (0077), החתימה
-- (0107) וההצעה (0170) — פותחים באותן שתי שורות: `app.profile_id()` ואז
-- `full_name` שלו. לפונקציית הקצה אין `auth.uid()`, ולכן שתיהן מחזירות null
-- והיומן היה מציג שורה בלי כותב. "יומן ששכח מי כתב בו אינו יומן" — זו לשונה
-- של 0016 על `actor_name`, והיא נכונה גם כשהכותב אינו אדם.
--
-- טריגר אחד קטן על `event_activity` במקום להעתיק שש פונקציות כדי להוסיף
-- בכל אחת coalesce אחד. הוא נוגע *רק* בשורה שאין לה כותב כלל, ולכן שום
-- כתיבה קיימת אינה משנה את התנהגותה, והתווית נקראת מהטרנזקציה שכותבת —
-- 0177 מרימה אותה, וכל שאר המערכת פשוט לא מגדירה אותה.

create or replace function app.event_activity_actor_label()
returns trigger language plpgsql set search_path = public as $$
begin
  if new.actor_profile_id is null and coalesce(btrim(new.actor_name), '') = '' then
    new.actor_name := nullif(current_setting('app.actor_label', true), '');
  end if;
  return new;
end $$;

create trigger event_activity_actor_label before insert on event_activity
  for each row execute function app.event_activity_actor_label();

-- ===== 3. מודול הרשאות: אינטגרציות ========================================
--
-- מודול משלו ולא מפתח נוסף תחת `settings`: מסך ההגדרות עונה על "מה המערכת
-- יודעת" — סוגי משימה, סטטוסים, משאיות — והאינטגרציה עונה על "עם מי היא
-- מדברת". הן גם נשללות בנפרד: רכז שמסדר סוגי משימה אינו מי שמנתק חיבור.
--
-- שני מפתחות ולא אחד, באותה הפרדה של `integrations.view`/`integrations.manage`
-- בצד של ViperFlow: לראות שהחיבור חי ומה נכנס דרכו, לעומת לחבר, לנתק,
-- ולהריץ מחדש משלוח.

insert into permission_modules (key, label_he, description_he, icon, sort_order) values
  ('integrations', 'אינטגרציות', 'חיבור ל-ViperFlow: אירועים, משימות ורשימת ריהוט', 'Plug', 95)
on conflict (key) do update set
  label_he = excluded.label_he,
  description_he = excluded.description_he,
  icon = excluded.icon,
  sort_order = excluded.sort_order;

select app.register_permission('integrations.view', 'integrations',
  'צפייה בחיבורים ובמשלוחים',
  'מצב החיבור ל-ViperFlow, ורשימת האירועים שנכנסו דרכו',
  'access', false, false, array['staff']::user_kind[], null, 10);

-- ‏`is_dangerous` ולא `default_allowed`: המפתח פותח וסוגר צינור שכותב אירועים
-- ומשימות, ומסך ההרשאות צריך לומר את זה בקול. סדר הפרמטרים של
-- ‏`register_permission` הוא (…, category, default_allowed, dangerous, …).
select app.register_permission('integrations.manage', 'integrations',
  'חיבור, ניתוק והרצה מחדש',
  'קישור לקוח לחשבון ViperFlow, כיבוי החיבור, והרצה מחדש של משלוח שנכשל',
  'action', false, true, array['staff']::user_kind[], 'integrations.view', 20);

-- ===== 4. הטבלאות =========================================================

-- ‏4.1 החיבור. שורה אחת לכל חשבון ViperFlow שאנחנו מאזינים לו, והיא אומרת
-- דבר אחד חשוב: לאיזה *לקוח שלנו* ההזמנות שלו נכנסות. ‏שיא עיצובים היא
-- הראשונה, והיא אינה מוקשחת בקוד בשום מקום — לקוח שני יקבל שורה שנייה.
create table viperflow_connections (
  id            uuid primary key default gen_random_uuid(),
  -- האירועים שנוצרים מהחיבור הזה נולדים על הלקוח הזה, ואיתו כל הקונפיגורציה
  -- שלו: שדות הטופס, אופני הביצוע, המשאיות והתמחור.
  customer_id   uuid not null references customers(id),
  label         text not null,
  -- כתובת ה-API של ViperFlow, לגיבוי ולהשלמה (`viperflow-sync`).
  -- אינה סוד: הסוד הוא המפתח שנשלח אליה, והוא יושב בפונקציית הקצה.
  api_base_url  text not null default 'https://xmcopljkqmjrpvhujpev.supabase.co/functions/v1/api/v1'
    check (api_base_url ~ '^https://'),
  is_active     boolean not null default true,
  notes         text,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  deleted_at    timestamptz
);

-- לקוח אחד, חיבור פעיל אחד. שני חיבורים פעילים לאותו לקוח היו מייצרים שני
-- אירועים לאותה הזמנה, ואין שאלה שהתשובה לה היא "שניהם".
create unique index viperflow_connections_customer_uq on viperflow_connections (customer_id)
  where is_active and deleted_at is null;

create trigger viperflow_connections_updated before update on viperflow_connections
  for each row execute function app.set_updated_at();

-- ‏4.2 הקישור. אירוע אחד ↔ הזמנה אחת.
create table viperflow_links (
  event_id         uuid primary key references events(id) on delete cascade,
  connection_id    uuid not null references viperflow_connections(id) on delete cascade,
  -- ה-uuid של ההזמנה ב-ViperFlow. זה המפתח, ולא `order_number`.
  order_id         uuid not null,
  order_number     text,
  order_status     text,
  -- ‏`updated_at` של ההזמנה כפי שהגיע במעטפה. שומר את המערכת מפני משלוח
  -- ישן שעקף חדש: ‏ViperFlow מבטיח at-least-once ואינו מבטיח סדר.
  order_updated_at timestamptz,
  last_event_id    text,
  last_synced_at   timestamptz not null default now(),
  created_at       timestamptz not null default now(),
  unique (connection_id, order_id)
);
create index viperflow_links_order_idx on viperflow_links (connection_id, order_id);

-- ‏4.3 המשלוחים. מה שנכנס, מה נעשה איתו, ומה שאפשר להריץ מחדש.
create table viperflow_deliveries (
  id            uuid primary key default gen_random_uuid(),
  connection_id uuid references viperflow_connections(id) on delete set null,
  -- `evt_…` — מפתח ה-dedup של ViperFlow, יציב בין ניסיונות חוזרים. הייחודיות
  -- כאן היא כל מנגנון האי-כפילות של האינטגרציה: משלוח שני של אותו אירוע
  -- נדחה על האינדקס ונענה "duplicate".
  event_id      text not null unique check (event_id ~ '^evt_[0-9a-f]{32}$'),
  -- `whd_…` — המשלוח לנקודת הקצה הזו. לא מפתח: הוא פר-נקודת-קצה ולא פר-אירוע.
  delivery_id   text,
  event_type    text not null,
  attempt       int,
  -- ‏`api` / `app` / `inbound` / `system` — מי גרם לשינוי בצד של ViperFlow.
  origin        text,
  -- ה-uuid של ההזמנה, כטקסט: מעטפה פגומה לא תפיל insert.
  entity_id     text,
  occurred_at   timestamptz,
  received_at   timestamptz not null default now(),
  processed_at  timestamptz,
  status        text not null default 'received'
    check (status in ('received', 'processed', 'ignored', 'failed')),
  reason        text,
  event_row_id  uuid references events(id) on delete set null,
  -- המעטפה כפי שהתקבלה, אחרי ניקוי הכסף. ראו §2 בראש הקובץ.
  payload       jsonb not null default '{}'::jsonb
);
create index viperflow_deliveries_recent_idx on viperflow_deliveries (received_at desc);
create index viperflow_deliveries_status_idx on viperflow_deliveries (status, received_at desc)
  where status in ('received', 'failed');
create index viperflow_deliveries_event_idx on viperflow_deliveries (event_row_id)
  where event_row_id is not null;

-- ‏4.4 שורות ההזמנה — הריהוט. **בלי מחירים, ובמכוון בלי עמודה שתחזיק אותם.**
create table viperflow_order_items (
  id                      uuid primary key default gen_random_uuid(),
  event_id                uuid not null references events(id) on delete cascade,
  connection_id           uuid not null references viperflow_connections(id) on delete cascade,
  -- מזהי השורות ב-ViperFlow אינם יציבים בין עריכות (docs/API.md §11 אצלם),
  -- ולכן הם נשמרים רק כדי לקשור רכיב לאב שלו *בתוך אותו סנכרון*, ואינם
  -- מפתח לשום דבר. הסנכרון מחליף את הרשימה כולה ואינו מתאים שורה לשורה.
  external_item_id        uuid,
  parent_external_item_id uuid,
  -- `product` (קטלוג ומוצר חופשי), `worker` (סידור ואיסוף), `truck` (הובלה).
  -- ‏ViperFlow שומר לעצמו את הזכות להוסיף ערכים, ולכן אין כאן check.
  line_type               text not null,
  name                    text not null,
  quantity                numeric(12,2) not null default 0,
  spare_quantity          numeric(12,2) not null default 0,
  is_component            boolean not null default false,
  component_type          text,
  is_custom               boolean not null default false,
  -- הבחירות של הפריט — [{"group": "מפה", "value": "מפה לבנה"}]. השמות בלבד:
  -- מזהי הקטלוג של ViperFlow אינם אומרים דבר למי שקורא את הרשימה במחסן.
  options                 jsonb not null default '[]'::jsonb,
  notes                   text,
  -- סדר התצוגה כפי שהגיע: אב אחרי אב, והרכיבים של כל אב מיד אחריו.
  position                int not null,
  synced_at               timestamptz not null default now(),
  unique (event_id, position)
);
create index viperflow_order_items_event_idx on viperflow_order_items (event_id, position);

comment on table viperflow_order_items is
  'שורות ההזמנה מ-ViperFlow, בלי מחירים. אין כאן עמודת מחיר במכוון — ראו 0176 §2.';

-- ===== 5. RLS =============================================================
--
-- ארבע הטבלאות, ואף אחת מהן בלי פוליסת כתיבה: הכותב היחיד הוא `service_role`
-- דרך פונקציית הקצה, והוא עוקף RLS ממילא. שינוי תצורה עובר ב-RPC (סעיף 6),
-- שהוא `security definer` ואוכף את המפתח בעצמו.

alter table viperflow_connections   enable row level security;
alter table viperflow_links         enable row level security;
alter table viperflow_deliveries    enable row level security;
alter table viperflow_order_items   enable row level security;

revoke all on viperflow_connections  from anon;
revoke all on viperflow_links        from anon;
revoke all on viperflow_deliveries   from anon;
revoke all on viperflow_order_items  from anon;

-- החיבור והמשלוחים הם מסך של המשרד: מי שמחזיק את המפתח רואה, ואיש אחר לא.
create policy viperflow_connections_select on viperflow_connections for select to authenticated
  using ((select app.is_admin()) or (select app.has('integrations.view')));

create policy viperflow_deliveries_select on viperflow_deliveries for select to authenticated
  using ((select app.is_admin()) or (select app.has('integrations.view')));

-- הקישור, לעומתם, הוא עובדה על האירוע — "הוא הגיע מהזמנה ORD-2026-0412" —
-- ולכן הוא נקרא בדיוק על ידי מי שהאירוע נפתח לו, בלי מפתח נוסף. ה-exists על
-- events הוא כל הפרדיקט: הוא מחיל את היקפי הראייה של 0013 בלי לשכפל אותם.
create policy viperflow_links_select on viperflow_links for select to authenticated
  using ((select app.is_admin())
         or exists (select 1 from events e where e.id = viperflow_links.event_id));

-- והריהוט נקרא כמו המפרט, כי הוא המפרט: אותו מפתח, ואותו exists.
-- ‏`events.specs_view` פתוח כברירת מחדל לשלושת סוגי המשתמש מאז 0102, ולכן
-- מי שנוסע לאירוע קורא את רשימת הריהוט שלו — וזו בדיוק הכוונה.
create policy viperflow_order_items_select on viperflow_order_items for select to authenticated
  using ((select app.is_admin())
         or ((select app.has('events.specs_view'))
             and exists (select 1 from events e where e.id = viperflow_order_items.event_id)));

-- ===== 6. מסך המשרד: קריאה ותצורה =========================================
--
-- שלוש פונקציות, וכולן `security definer` שאוכפות את המפתח בעצמן — אותו
-- חוזה של `remove_event_spec` (0077 §7): לא מקבלות שם טבלה, ואי אפשר להפנות
-- אותן לשום מקום אחר.

/**
 * מצב החיבור, לכל חיבור: מתי נכנס אירוע אחרון, כמה נכנסו ביממה, וכמה נכשלו
 * ועדיין ממתינים להרצה מחדש. הספירות נגזרות מ-`viperflow_deliveries` ואינן
 * עמודות בטבלת החיבור — מונה שמתעדכן בכל משלוח הוא מונה שיוצא מסנכרון ברגע
 * שמישהו מוחק שורה.
 */
create or replace function viperflow_connection_status()
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  perform app.require('integrations.view');

  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id',            c.id,
      'label',         c.label,
      'customer_id',   c.customer_id,
      'customer_name', cu.name,
      'api_base_url',  c.api_base_url,
      'is_active',     c.is_active,
      'notes',         c.notes,
      'linked_events', (select count(*) from viperflow_links l where l.connection_id = c.id),
      'last_event_at', (select max(d.received_at) from viperflow_deliveries d
                         where d.connection_id = c.id),
      'received_24h',  (select count(*) from viperflow_deliveries d
                         where d.connection_id = c.id
                           and d.received_at > now() - interval '24 hours'),
      'failed_open',   (select count(*) from viperflow_deliveries d
                         where d.connection_id = c.id and d.status = 'failed')
    ) order by c.label)
    from viperflow_connections c
    join customers cu on cu.id = c.customer_id
    where c.deleted_at is null
  ), '[]'::jsonb);
end $$;

-- ‏`public` ולא רק `anon`: ברירת המחדל של פוסטגרס מעניקה EXECUTE ל-PUBLIC,
-- ו-revoke מ-anon לבדו משאיר לו את הדרך דרכה. אותה הקפדה של 0044:152.
revoke execute on function viperflow_connection_status() from anon, public;
grant  execute on function viperflow_connection_status() to authenticated;

/**
 * חיבור לקוח לחשבון ViperFlow, או כיבויו.
 *
 * ‏`p_connection_id` ריק פותח חיבור חדש; מלא מעדכן קיים. הכיבוי אינו מוחק
 * דבר: הקישורים והריהוט של אירועים שכבר נכנסו נשארים, וההאזנה נפסקת. מחיקה
 * של חיבור היא `deleted_at`, כמו בכל שאר הקטלוגים במערכת.
 */
create or replace function viperflow_set_connection(
  p_customer_id   uuid,
  p_label         text,
  p_is_active     boolean default true,
  p_api_base_url  text default null,
  p_notes         text default null,
  p_connection_id uuid default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  perform app.require('integrations.manage', 'אין לך הרשאה לנהל חיבורים');

  if not exists (select 1 from customers c where c.id = p_customer_id and c.deleted_at is null) then
    raise exception 'לקוח לא נמצא';
  end if;
  if coalesce(btrim(p_label), '') = '' then
    raise exception 'חובה לתת שם לחיבור';
  end if;

  if p_connection_id is null then
    insert into viperflow_connections (customer_id, label, is_active, api_base_url, notes)
    values (p_customer_id, btrim(p_label), coalesce(p_is_active, true),
            coalesce(nullif(btrim(p_api_base_url), ''),
                     'https://xmcopljkqmjrpvhujpev.supabase.co/functions/v1/api/v1'),
            nullif(btrim(p_notes), ''))
    returning id into v_id;
  else
    update viperflow_connections set
      customer_id  = p_customer_id,
      label        = btrim(p_label),
      is_active    = coalesce(p_is_active, is_active),
      api_base_url = coalesce(nullif(btrim(p_api_base_url), ''), api_base_url),
      notes        = nullif(btrim(p_notes), '')
    where id = p_connection_id and deleted_at is null
    returning id into v_id;
    if v_id is null then raise exception 'חיבור לא נמצא'; end if;
  end if;

  return v_id;
end $$;

revoke execute on function viperflow_set_connection(uuid, text, boolean, text, text, uuid)
  from anon, public;
grant  execute on function viperflow_set_connection(uuid, text, boolean, text, text, uuid)
  to authenticated;

/**
 * ניקוי משלוחים ישנים. אינו מתוזמן כאן במכוון — אין במערכת תשתית cron משלה
 * (‏0030 מזמינה את `notify-dispatch` דרך pg_net מטריגר, ותו לא) — והוא נקרא
 * מ-`viperflow-sync`, שרץ ממילא על תזמון חיצוני.
 *
 * משלוח שנכשל ולא הורץ מחדש אינו נמחק בשום גיל: הוא עבודה פתוחה.
 */
create or replace function viperflow_prune_deliveries(p_days int default 90)
returns int language plpgsql security definer set search_path = public as $$
declare v_count int;
begin
  -- קורא בלי JWT הוא התזמון בזהות service role; קורא עם JWT הוא אדם שלחץ
  -- "נקה עכשיו", והוא חייב להחזיק מפתח. אותה הבחנה בדיוק של
  -- `fleet_expiry_sweep` (0089).
  if auth.uid() is not null then
    perform app.require('integrations.manage', 'אין לך הרשאה לנקות משלוחים');
  end if;

  with gone as (
    delete from viperflow_deliveries
     where received_at < now() - make_interval(days => greatest(coalesce(p_days, 90), 7))
       and status <> 'failed'
    returning 1)
  select count(*) into v_count from gone;

  return v_count;
end $$;

revoke execute on function viperflow_prune_deliveries(int) from anon, public;
grant  execute on function viperflow_prune_deliveries(int) to service_role, authenticated;
