-- 0184: כל שינוי באירוע של ארקו חוזר אליה
--
-- הבקשה: **"כל עדכון שמתבצע באירוע של לקוח ארקו — שיישלח webhook."**
--
-- השאלה היחידה שצריך להכריע כאן היא **מה נחשב עדכון**, והתשובה כבר כתובה
-- במסד: ‏`event_activity`. היומן שומע את שורת האירוע (0016), את אנשי הקשר
-- והספקים, את שדות המשימה — תאריך, שעה, שעות, עובדים, אופן ביצוע (0112) —
-- את הוספת משימה והסרתה (0049), את המפרטים (0077) ואת הצעת המחיר (0170).
-- כל כותביו הם טריגרי שורה סינכרוניים באותה טרנזקציה, ובדיוק מהסיבה הזו
-- ‏0112 כבר השתמשה בו כגלאי-השינוי של ההתראות: "האם השמירה הזו שינתה משהו"
-- היא "האם היומן קיבל שורה". מי שיבנה גלאי שני יבנה גלאי שיפגר אחריו.
--
-- ארבע הכרעות:
--
--   1. **שמירה אחת = הודעה אחת.** הטריגר הוא ברמת ההוראה ועם טבלת מעבר,
--      והשורה בתור ייחודית לזוג (אירוע, טרנזקציה). עריכה שנגעה בשמונה
--      שדות היא הודעה אחת עם שמונה שינויים ולא שמונה הודעות.
--
--   2. **הכתובת אינה במסד.** הטריגר מצלצל לפונקציית הקצה `arco-dispatch`,
--      והיא זו שמחזיקה את כתובת ה-webhook של Make כסוד שלה. זה גם מה
--      שנותן ניסיונות חוזרים: ‏pg_net הוא ירה-ושכח, ופונקציית קצה שמסמנת
--      מה נשלח היא מה שהופך תור לתור.
--
--   3. **התור מתנקז במלואו בכל צלצול.** גוף ריק לפונקציית הקצה פירושו
--      "קח את כל מה שממתין" — ולכן הודעה שנכשלה מקבלת הזדמנות נוספת
--      בשמירה הבאה, גם בלי מתזמן. אותה החלטה של 0046 §9.
--
--   4. **מה שארקו שלחה חוזר אליה מסומן.** קליטה מסמנת `app.actor_label`
--      בשם 'ארקו' (0183 §5), והתווית נשמרת על ההודעה כ-`origin`. התרחיש
--      בצד השני מחליט אם הוא רוצה את ההד שלו עצמו; בלי הסימון הוא לא
--      היה יכול.

-- ===== 1. התור =============================================================
create table arco_outbound (
  id              uuid primary key default gen_random_uuid(),
  connection_id   uuid references arco_connections(id) on delete cascade,
  event_id        uuid not null references events(id) on delete cascade,
  -- מזהה הטרנזקציה שכתבה ביומן. הוא מה שהופך שמירה אחת להודעה אחת.
  tx_id           text not null,
  origin          text,
  kinds           text[] not null default '{}',
  changes         jsonb  not null default '[]'::jsonb,
  status          text   not null default 'queued'
                    check (status in ('queued', 'sent', 'failed')),
  attempts        int    not null default 0,
  response_status int,
  last_error      text,
  created_at      timestamptz not null default now(),
  sent_at         timestamptz
);
create unique index arco_outbound_tx_uk on arco_outbound (event_id, tx_id);
create index arco_outbound_pending_idx on arco_outbound (created_at)
  where status <> 'sent';
create index arco_outbound_event_idx on arco_outbound (event_id, created_at desc);

alter table arco_outbound enable row level security;
revoke all on arco_outbound from anon;
grant select on arco_outbound to authenticated;
create policy arco_outbound_select on arco_outbound for select to authenticated
  using (app.has('integrations.view'));

-- ===== 2. הגלאי ============================================================
--
-- ‏`referencing new table` הוא מה שמאפשר להיות ברמת ההוראה ובכל זאת לדעת
-- בדיוק אילו שורות נכתבו. בלעדיו היינו צריכים לירות פר-שורה ולאחד אחר כך.
create or replace function app.arco_outbound_enqueue()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_new int;
begin
  with rows_by_event as (
    select a.event_id,
           array_agg(distinct a.kind::text) as kinds,
           jsonb_agg(jsonb_build_object(
             'kind',  a.kind,
             'field', a.field_key,
             'label', a.field_label,
             'old',   a.old_value,
             'new',   a.new_value,
             'note',  a.note,
             'actor', a.actor_name) order by a.id) as changes,
           max(a.actor_name) filter (where a.actor_name is not null) as actor
      from new_rows a
     group by a.event_id),
  targets as (
    select r.*, k.id as connection_id
      from rows_by_event r
      join events e on e.id = r.event_id
      join arco_connections k on k.customer_id = e.customer_id
     where k.is_active and k.notify_updates)
  insert into arco_outbound (connection_id, event_id, tx_id, origin, kinds, changes)
  select t.connection_id, t.event_id, pg_current_xact_id()::text,
         case when t.actor = 'ארקו' then 'arco' else 'viper' end,
         t.kinds, t.changes
    from targets t
  on conflict (event_id, tx_id) do update
    set kinds   = (select array_agg(distinct x)
                     from unnest(arco_outbound.kinds || excluded.kinds) x),
        changes = arco_outbound.changes || excluded.changes,
        status  = case when arco_outbound.status = 'sent' then 'queued'
                       else arco_outbound.status end;

  get diagnostics v_new = row_count;
  if v_new > 0 then perform app.arco_dispatch_ping(); end if;
  return null;
end $$;

create trigger event_activity_arco_outbound
  after insert on event_activity
  referencing new table as new_rows
  for each statement execute function app.arco_outbound_enqueue();

-- ===== 3. הצלצול ===========================================================
--
-- אותו דפוס, אותה חתימה ואותה שתיקה של `app.notify_dispatch_ping` (0046 §9):
-- בלי כתובת או בלי סוד הטריגר שותק, בלי pg_net הוא שותק, וכישלון בצלצול
-- אינו מבטל את השמירה שיצרה אותו. מה שנשאר הוא שורה בתור — שתישלח בצלצול
-- הבא או בניקוז המתוזמן.
create or replace function app.arco_dispatch_ping()
returns void language plpgsql security definer set search_path = public as $$
declare
  v_url    text := nullif(current_setting('app.arco_dispatch_url', true), '');
  v_secret text := nullif(current_setting('app.arco_dispatch_secret', true), '');
begin
  if v_url is null or v_secret is null then return; end if;
  if to_regproc('net.http_post') is null then return; end if;

  execute 'select net.http_post(url := $1, headers := $2, body := $3)'
  using v_url,
        jsonb_build_object('Content-Type', 'application/json', 'x-arco-secret', v_secret),
        '{}'::jsonb;
exception when others then
  raise notice 'arco dispatch ping failed: %', sqlerrm;
end $$;

-- ===== 4. מה שממתין, ומה שיצא =============================================
--
-- ‏security definer עם בדיקת מפתח, כי מי שקורא לזה הוא פונקציית הקצה בשם
-- המערכת. אדם שקורא לזה עם JWT חייב `integrations.manage` — אותו שער של
-- ‏`notification_pending` (0030).
--
-- חמישה ניסיונות ודי: הודעה שנדחית חמש פעמים אינה תקלה רגעית, והיא נשארת
-- שורה אדומה במסך במקום להמשיך לדפוק על דלת סגורה.
create or replace function arco_outbound_pending(p_limit int default 50)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is not null then
    perform app.require('integrations.manage', 'אין לך הרשאה לנקז את תור הדיווח');
  end if;

  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'outbound_id', o.id,
      'type',        'event.updated',
      'origin',      o.origin,
      'kinds',       to_jsonb(o.kinds),
      'changes',     o.changes,
      'attempts',    o.attempts,
      'occurred_at', o.created_at,
      'event',       app.arco_event_snapshot(o.event_id))
      order by o.created_at)
    from (select * from arco_outbound
           where status <> 'sent' and attempts < 5
           order by created_at
           limit greatest(coalesce(p_limit, 50), 1)) o), '[]'::jsonb);
end $$;

revoke execute on function arco_outbound_pending(int) from anon, public;
grant  execute on function arco_outbound_pending(int) to service_role, authenticated;

create or replace function arco_outbound_mark(
  p_id     uuid,
  p_ok     boolean,
  p_status int  default null,
  p_error  text default null)
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is not null then
    perform app.require('integrations.manage', 'אין לך הרשאה לסמן דיווח');
  end if;

  update arco_outbound set
    status          = case when p_ok then 'sent' else 'failed' end,
    attempts        = attempts + 1,
    response_status = p_status,
    last_error      = case when p_ok then null else left(coalesce(p_error, ''), 500) end,
    sent_at         = case when p_ok then now() else sent_at end
  where id = p_id;
end $$;

revoke execute on function arco_outbound_mark(uuid, boolean, int, text) from anon, public;
grant  execute on function arco_outbound_mark(uuid, boolean, int, text) to service_role, authenticated;

-- ===== 5. שליחה ידנית ======================================================
--
-- שתי דלתות למסך האינטגרציות: לצלצל שוב (מה שמנקז את כל מה שממתין), ולהחזיר
-- הודעה שנשרפה על חמשת ניסיונותיה לתור.
create or replace function arco_outbound_retry(p_id uuid default null)
returns int language plpgsql security definer set search_path = public as $$
declare v_count int;
begin
  perform app.require('integrations.manage', 'אין לך הרשאה לשלוח דיווח מחדש');

  update arco_outbound set status = 'queued', attempts = 0, last_error = null
   where status <> 'sent' and (p_id is null or id = p_id);
  get diagnostics v_count = row_count;

  perform app.arco_dispatch_ping();
  return v_count;
end $$;

revoke execute on function arco_outbound_retry(uuid) from anon, public;
grant  execute on function arco_outbound_retry(uuid) to authenticated;

revoke execute on function app.arco_outbound_enqueue() from anon, authenticated, public;
revoke execute on function app.arco_dispatch_ping()    from anon, authenticated, public;
