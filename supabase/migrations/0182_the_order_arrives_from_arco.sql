-- 0182: ההזמנה מגיעה מארקו
--
-- ‏ארקו מנהלת את ההזמנות שלה ב-Origami, והגשר בין שתי המערכות הוא שני
-- תרחישים ב-Make שכבר רצים היום: אחד נפתח כשנפתחת הזמנה, ואחד כשמתחלף
-- המפרט. עד היום שניהם כתבו ל-Firestore של המערכת הקודמת בלבד. המעבר
-- ל-Supabase אינו מחליף אותם — הוא **מוסיף** להם תחנה: אותו webhook, אותו
-- מודול Firestore, ואחריו מודול HTTP שמדבר איתנו. שתי המערכות מתעדכנות
-- זו לצד זו, וכיבוי הישנה יהיה יום אחד מחיקה של מודול אחד ולא פרויקט.
--
-- שלוש המיגרציות 0182–0184 הן הצד שלנו של אותה שיחה: הטבלאות וההרשאות
-- (כאן), התרגום מהזמנה לאירוע ולמשימותיו (0183), והדיווח חזרה על כל שינוי
-- (0184).
--
-- ארבע הכרעות יושבות בקובץ הזה, וכולן חוזרות על מה ש-0176 כבר הכריעה
-- מול ViperFlow — במכוון: שתי אינטגרציות שנראות אותו דבר הן שתי אינטגרציות
-- שאפשר לתחזק.
--
--   1. **הסוד אינו במסד.** הסוד המשותף שבו ‏Make מזדהה מולנו, וכתובת
--      ה-webhook שאליה אנחנו מדווחים חזרה, הם סודות של פונקציות הקצה
--      (`ARCO_INTAKE_SECRET`, `ARCO_EVENT_WEBHOOK_URL`). ‏`app_settings`
--      קריאה לכל משתמש מאומת (0005), וכתובת webhook של Make היא מפתח
--      לכל דבר: מי שמחזיק אותה יכול לכתוב לתרחיש. מה שיושב כאן הוא
--      *החיבור* — לאיזה לקוח ההזמנות נכנסות — וזו תצורה ולא סוד.
--
--   2. **מספר ההזמנה הוא המפתח.** בניגוד ל-ViperFlow, ל-Origami אין אצלנו
--      ‏uuid יציב שאפשר להיאחז בו: מה ששני התרחישים נושאים הוא
--      ‏`order_number`, וזה גם מה שהמערכת הקודמת שמרה בשדה `makat` — אחרי
--      שהיא מוחקת ממנו כל תו שאינו ספרה. אנחנו עושים את אותו ניקוי בדיוק
--      ושומרים את התוצאה ב-`events.event_number`, שעליו כבר יושב אינדקס
--      ייחודי לכל לקוח (0003). כך "הזמנה 26000233" היא אותו אירוע בשתי
--      המערכות, ותרחיש המפרט מוצא את האירוע באותה שאילתה שהוא מצא בה את
--      מסמך ה-Firestore.
--
--   3. **המעטפה נשמרת, ולא רק תוצאתה.** ‏`arco_deliveries` היא מה שמאפשר
--      להריץ מחדש משלוח שנפל — גם שבוע אחרי, וגם בלי לבקש מ-Make דבר.
--      זו גם הסיבה שכישלון עסקי אינו מחזיר שגיאת HTTP (0183 §5).
--
--   4. **הקריאה נגזרת מהאירוע.** אף טבלה כאן אינה כותבת פרדיקט ראייה
--      משלה: `exists (select 1 from events e …)` הוא שמחיל את כל היקפי
--      הראייה של `events_select` (0013).
--
-- הכתיבה כולה שייכת ל-`service_role`: פונקציות הקצה הן הכותב היחיד, ואין
-- לאף טבלה כאן פוליסת insert/update/delete.

-- ===== 1. מודול ההרשאות מקבל דייר שני ====================================
-- ‏`integrations` נולד ב-0176 עם ViperFlow בלבד בתיאור. אותו מפתח משרת גם
-- את ארקו — רכז שרשאי לחבר ולנתק אינטגרציה רשאי לשתיהן — ולכן מה שמשתנה
-- הוא המשפט במסך, ולא ההרשאה.
update permission_modules
   set description_he = 'חיבורים למערכות חיצוניות: ViperFlow, ארקו — אירועים, משימות ומפרטים'
 where key = 'integrations';

-- ===== 2. החיבור =========================================================
--
-- שורה אחת לכל חשבון Origami שאנחנו מקשיבים לו, והיא אומרת דבר אחד חשוב:
-- לאיזה *לקוח שלנו* ההזמנות שלו נכנסות. ‏`is_active` היא מתג הכיבוי: חיבור
-- כבוי ממשיך לרשום משלוחים ואינו מתרגם אותם, וכך אפשר לעצור את הצינור
-- בלי לגעת בתרחיש שרץ בצד השני.
--
-- ‏`notify_updates` הוא הצד השני של החיבור: האם כל שינוי באירוע של הלקוח
-- הזה מדווח חזרה (0184). הוא נפרד מ-`is_active` בכוונה — אפשר להפסיק
-- לדווח בלי להפסיק לקלוט, ולהפך.
create table arco_connections (
  id             uuid primary key default gen_random_uuid(),
  customer_id    uuid not null unique references customers(id),
  name           text not null,
  is_active      boolean not null default true,
  notify_updates boolean not null default true,
  -- מה נקלט לאחרונה, לתצוגה במסך האינטגרציות בלבד
  last_seen_at   timestamptz,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);
create trigger arco_connections_updated before update on arco_connections
  for each row execute function app.set_updated_at();

-- הלקוח — נתון, לא קוד. אין לקוח כזה (אשכול בדיקות) ⇒ אפס שורות, ואשף
-- החיבור במסך האינטגרציות פותח אותו ביד.
insert into arco_connections (customer_id, name)
select c.id, 'ארקו'
  from customers c
 where c.name ilike '%ארקו%' and c.deleted_at is null
 order by c.created_at
 limit 1
on conflict (customer_id) do nothing;

-- ===== 3. המשלוחים =======================================================
--
-- כל קריאה שנכנסת מ-Make נרשמת כאן — גם כזו שלא הצליחה, ובמיוחד כזו.
-- ‏`request_id` הוא מזהה הקריאה שפונקציית הקצה מייצרת; שני ניסיונות של
-- אותו תרחיש על אותה הזמנה הם שתי שורות, כי ל-Make אין מזהה משלוח יציב
-- שאפשר להכריע לפיו כפילות. מה שמונע כפילות *עסקית* הוא המפתח שבסעיף 2:
-- הזמנה שכבר יש לה אירוע מתעדכנת ואינה נפתחת שוב.
create table arco_deliveries (
  id            uuid primary key default gen_random_uuid(),
  connection_id uuid references arco_connections(id) on delete set null,
  -- 'event' — תרחיש פתיחת ההזמנה; 'spec' — תרחיש המפרט
  kind          text not null check (kind in ('event', 'spec')),
  order_number  text,
  payload       jsonb not null,
  status        text not null default 'received'
                  check (status in ('received', 'applied', 'ignored', 'failed')),
  reason        text,
  event_row_id  uuid references events(id) on delete set null,
  result        jsonb,
  received_at   timestamptz not null default now(),
  processed_at  timestamptz
);
create index arco_deliveries_recent_idx on arco_deliveries (received_at desc);
create index arco_deliveries_status_idx on arco_deliveries (status, received_at desc);
create index arco_deliveries_event_idx  on arco_deliveries (event_row_id)
  where event_row_id is not null;
create index arco_deliveries_order_idx  on arco_deliveries (order_number, received_at desc);

-- ===== 4. מי רואה מה =====================================================
--
-- קריאה למשתמש מאומת שיש לו `integrations.view`; כתיבה — לאיש. פונקציות
-- הקצה עובדות בזהות `service_role`, ש-RLS אינה חלה עליה.
alter table arco_connections enable row level security;
alter table arco_deliveries  enable row level security;
revoke all on arco_connections from anon;
revoke all on arco_deliveries  from anon;
grant select on arco_connections to authenticated;
grant select on arco_deliveries  to authenticated;

create policy arco_connections_select on arco_connections for select to authenticated
  using (app.has('integrations.view'));

-- המעטפה עצמה נראית רק למי שרשאי לראות אינטגרציות, ולא לכל מי שרואה את
-- האירוע: היא מכילה את מה שארקו שלחה, על כל שדותיה, ובהן שדות שהמסך שלנו
-- אינו מציג לאיש.
create policy arco_deliveries_select on arco_deliveries for select to authenticated
  using (app.has('integrations.view'));

-- ===== 5. מה המסך שואל ===================================================

/**
 * מצב החיבור: הלקוח, הדלקה/כיבוי, ומה נכנס לאחרונה.
 */
create or replace function arco_connection_status()
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  perform app.require('integrations.view', 'אין לך הרשאה לראות אינטגרציות');

  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id',             k.id,
      'name',           k.name,
      'customer_id',    k.customer_id,
      'customer_name',  (select c.name from customers c where c.id = k.customer_id),
      'is_active',      k.is_active,
      'notify_updates', k.notify_updates,
      'last_seen_at',   k.last_seen_at,
      'failed_24h',     (select count(*) from arco_deliveries d
                          where d.connection_id = k.id and d.status = 'failed'
                            and d.received_at > now() - interval '24 hours'),
      'applied_24h',    (select count(*) from arco_deliveries d
                          where d.connection_id = k.id and d.status = 'applied'
                            and d.received_at > now() - interval '24 hours'))
      order by k.created_at)
    from arco_connections k), '[]'::jsonb);
end $$;

revoke execute on function arco_connection_status() from anon, public;
grant  execute on function arco_connection_status() to authenticated;

/**
 * פתיחת חיבור, כיבויו, והחלטה אם הוא מדווח חזרה.
 *
 * הלקוח נבחר ואינו מוקשח בקוד — בשום מקום באינטגרציה אין השוואה לשם
 * 'ארקו'. מה שקושר הוא `arco_connections.customer_id`.
 */
create or replace function arco_set_connection(
  p_customer_id    uuid,
  p_name           text    default 'ארקו',
  p_is_active      boolean default true,
  p_notify_updates boolean default true)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  perform app.require('integrations.manage', 'אין לך הרשאה לנהל אינטגרציות');

  if not exists (select 1 from customers c
                  where c.id = p_customer_id and c.deleted_at is null) then
    raise exception 'לקוח לא נמצא';
  end if;

  insert into arco_connections (customer_id, name, is_active, notify_updates)
  values (p_customer_id, coalesce(nullif(btrim(p_name), ''), 'ארקו'),
          p_is_active, p_notify_updates)
  on conflict (customer_id) do update
    set name           = excluded.name,
        is_active      = excluded.is_active,
        notify_updates = excluded.notify_updates
  returning id into v_id;

  return v_id;
end $$;

revoke execute on function arco_set_connection(uuid, text, boolean, boolean) from anon, public;
grant  execute on function arco_set_connection(uuid, text, boolean, boolean) to authenticated;

/**
 * ניקוי. משלוח שנכשל אינו נמחק בשום גיל — הוא עבודה פתוחה.
 * אותו כלל, ואותה חתימה, של `viperflow_prune_deliveries` (0176 §6).
 */
create or replace function arco_prune_deliveries(p_days int default 90)
returns int language plpgsql security definer set search_path = public as $$
declare v_count int;
begin
  if auth.uid() is not null then
    perform app.require('integrations.manage', 'אין לך הרשאה לנקות משלוחים');
  end if;

  delete from arco_deliveries
   where received_at < now() - make_interval(days => greatest(p_days, 7))
     and status <> 'failed';
  get diagnostics v_count = row_count;
  return v_count;
end $$;

revoke execute on function arco_prune_deliveries(int) from anon, public;
grant  execute on function arco_prune_deliveries(int) to service_role, authenticated;
