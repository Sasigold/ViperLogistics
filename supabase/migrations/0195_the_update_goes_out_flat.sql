-- 0195: עדכון באירוע של ארקו יוצא ישר מהמסד, שטוח
--
-- הבקשה: **"כשמעדכנים אירוע ב-ViperLogistics של לקוח ארקו — שלח webhook"**,
-- לכתובת שהיא נתנה, בצורה שטוחה אחת: 26 שדות, כל ערך מחרוזת, בדיוק כמו
-- הדוגמה ששלחה (`"trucks_count": "1"`, `"parking": "true"`, `"setup_price":
-- "1600.0"`).
--
-- ‏0184 כבר יודעת *מתי*: התור `arco_outbound` מתמלא מכל שמירה ששינתה משהו.
-- מה שחסר היה *איך זה יוצא*. הצלצול של 0184 עובר דרך `arco-dispatch`, שתלויה
-- בשני GUC-ים ובשלושה סודות של פונקציות קצה — ואף אחד מהם לא הוגדר, ולכן
-- התור רק התמלא. כאן המסד שולח בעצמו, דרך `pg_net`, ואין עוד תלות בסודות.
--
-- ארבע הכרעות:
--
--   1. **השליחה בזמן ה-commit, לא בזמן ההוראה.** שמירה אחת יכולה לגעת
--      באירוע ואחר כך במשימות שלו, בכמה הוראות. טריגר אילוץ דחוי על שורת
--      התור רץ פעם אחת לשורה — כלומר פעם אחת לזוג (אירוע, טרנזקציה) —
--      ורק אחרי שכל ההוראות רצו, ולכן התמונה שיוצאת היא הסופית. ובגלל
--      ש-pg_net שולח רק אחרי commit, שמירה שהתבטלה אינה שולחת כלום.
--
--   2. **רק מה שנעשה אצלנו.** ‏`origin = 'arco'` הוא הד של הזמנה שארקו עצמה
--      שלחה (0184 §4). הבקשה היא "כשמעדכנים ב-ViperLogistics", והד כזה היה
--      עלול לחזור אליה ולסגור מעגל. הוא נרשם בתור כ-'skipped'.
--
--   3. **הכתובת אינה בריפו ואינה קריאה לאיש.** היא יושבת בטבלה פרטית
--      (`app.arco_webhook_targets`) בלי שום הרשאה ל-authenticated, ומוזנת
--      ב-SQL ולא במיגרציה. מי שמחזיק אותה יכול לכתוב לתרחיש שלה.
--
--   4. **pg_net הוא ירה-ושכח, והתור הוא מה שזוכר.** השורה עוברת ל-'sending'
--      עם מזהה הבקשה, ו-`app.arco_outbound_reconcile` קורא את התשובה
--      מ-`net._http_response` ומסמן 'sent' או 'failed'. הוא רץ בכל שליחה
--      ובכל "שלח שוב", כך שהמצב מתיישב בלי מתזמן.

-- ===== 1. היעד =============================================================
create table app.arco_webhook_targets (
  connection_id uuid primary key references arco_connections(id) on delete cascade,
  url           text not null check (url ~ '^https://'),
  updated_at    timestamptz not null default now()
);
revoke all on app.arco_webhook_targets from public, anon, authenticated;

-- ===== 2. התור יודע מה נשלח ===============================================
alter table arco_outbound drop constraint arco_outbound_status_check;
alter table arco_outbound add constraint arco_outbound_status_check
  check (status in ('queued', 'sending', 'sent', 'failed', 'skipped'));
alter table arco_outbound add column request_id bigint;

-- ‏0184 §3 צלצלה ל-`arco-dispatch`. עכשיו המסד שולח בעצמו, וצלצול שני היה
-- שולח כל עדכון פעמיים ברגע שמישהו יגדיר את ה-GUC-ים.
create or replace function app.arco_dispatch_ping()
returns void language plpgsql as $$ begin null; end $$;

-- ‏'sending' ו-'skipped' אינם עבודה פתוחה של `arco-dispatch`.
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
           where status in ('queued', 'failed') and attempts < 5
           order by created_at
           limit greatest(coalesce(p_limit, 50), 1)) o), '[]'::jsonb);
end $$;

-- ===== 3. הצורה השטוחה =====================================================
--
-- מספר כפי ש-Java כותב double: ‏`3` הוא "3.0", ‏`3.5` הוא "3.5". כך נראית
-- הדוגמה, וכך הצד השני מצפה לקרוא.
create or replace function app.arco_decimal_text(p numeric)
returns text language sql immutable set search_path = public as $$
  select case when p is null then null
              when p = trunc(p) then trunc(p)::text || '.0'
              else rtrim(p::text, '0') end
$$;

create or replace function app.arco_flat_payload(p_event uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  e         events;
  v_client  text;
  v_setup   record;
  v_down    record;
begin
  select * into e from events where id = p_event;
  if e.id is null then return null; end if;
  select c.name into v_client from customers c where c.id = e.customer_id;

  -- המשימה הראשונה מכל סוג. באירוע של ארקו יש אחת מכל אחד (0183 §2).
  select t.task_date, t.onsite_start_time, t.worker_count, t.hours_count,
         t.performed_by, m.name as method, p.price
    into v_setup
    from tasks t
    join task_types tt on tt.id = t.task_type_id and tt.code = 'setup'
    left join execution_methods m on m.id = t.execution_method_id
    left join task_pricing p on p.task_id = t.id
   where t.event_id = e.id and t.deleted_at is null
   order by t.task_date, t.onsite_start_time nulls last, t.created_at
   limit 1;

  select t.task_date, t.onsite_start_time, t.worker_count, t.hours_count,
         t.performed_by, m.name as method, p.price
    into v_down
    from tasks t
    join task_types tt on tt.id = t.task_type_id and tt.code = 'teardown'
    left join execution_methods m on m.id = t.execution_method_id
    left join task_pricing p on p.task_id = t.id
   where t.event_id = e.id and t.deleted_at is null
   order by t.task_date, t.onsite_start_time nulls last, t.created_at
   limit 1;

  -- מחרוזת שאין לה ערך יוצאת "", ומספר שאין לו ערך יוצא null: "" בשדה
  -- Integer היה נכשל בפענוח בצד השני, ו-null פירושו "לא ידוע".
  return jsonb_build_object(
    'customer_name',       coalesce(e.end_client_name, ''),
    'order_number',        coalesce(e.event_number, ''),
    'location',            coalesce(e.location_text, ''),
    'location_notes',      coalesce(e.location_notes, ''),
    'date',                coalesce(to_char(e.event_date, 'DD/MM/YYYY'), ''),
    'event_status',        coalesce((select s.name from statuses s where s.id = e.status_id), ''),
    'trucks_count',        e.truck_count::text,
    'volume',              app.arco_decimal_text(e.volume_m),
    'supplier_pickup',     coalesce(e.supplier_pickup, false)::text,
    -- ‏`parking` של ארקו נקלט כ-`no_parking` (0183 §3), וחוזר באותו מסלול.
    'parking',             coalesce(e.no_parking, false)::text,
    'porters',             coalesce(e.porterage, false)::text,
    'contact_name',        coalesce((select contact_name  from event_contacts where event_id = e.id), ''),
    'phone',               coalesce((select contact_phone from event_contacts where event_id = e.id), ''),
    'operational_notes',   coalesce(e.notes, ''),
    'setup_datetime',      coalesce(concat_ws(' ', to_char(v_setup.task_date, 'DD/MM/YYYY'),
                                                   to_char(v_setup.onsite_start_time, 'HH24:MI')), ''),
    'setup_method',        coalesce(v_setup.method, ''),
    'setup_workers',       v_setup.worker_count::text,
    'setup_hours',         app.arco_decimal_text(v_setup.hours_count),
    -- מבצע ההקמה, באותן שתי מילים שהקליטה מכירה (0183 §2).
    'setup_contractor',    case when v_setup.performed_by is null then ''
                                when v_setup.performed_by = 'arko' then coalesce(v_client, '')
                                else 'וייפר' end,
    'setup_price',         app.arco_decimal_text(v_setup.price),
    'teardown_datetime',   coalesce(concat_ws(' ', to_char(v_down.task_date, 'DD/MM/YYYY'),
                                                   to_char(v_down.onsite_start_time, 'HH24:MI')), ''),
    'teardown_method',     coalesce(v_down.method, ''),
    'teardown_workers',    v_down.worker_count::text,
    'teardown_hours',      app.arco_decimal_text(v_down.hours_count),
    'teardown_contractor', case when v_down.performed_by is null then ''
                                when v_down.performed_by = 'arko' then coalesce(v_client, '')
                                else 'וייפר' end,
    'teardown_price',      app.arco_decimal_text(v_down.price));
end $$;

-- ===== 4. התשובות שחזרו ====================================================
create or replace function app.arco_outbound_reconcile()
returns void language plpgsql security definer set search_path = public as $$
begin
  if to_regclass('net._http_response') is null then return; end if;

  execute $q$
    update arco_outbound o set
      status          = case when r.status_code between 200 and 299 then 'sent' else 'failed' end,
      response_status = r.status_code,
      last_error      = case when r.status_code between 200 and 299 then null
                             else left(coalesce(r.error_msg, r.content, ''), 500) end,
      sent_at         = case when r.status_code between 200 and 299 then r.created else o.sent_at end
      from net._http_response r
     where o.status = 'sending' and r.id = o.request_id
  $q$;

  -- ‏pg_net מוחק תשובות אחרי שש שעות. מה שלא נענה עד אז לא ייענה.
  update arco_outbound set status = 'failed', last_error = 'no response'
   where status = 'sending' and created_at < now() - interval '6 hours';
end $$;

-- ===== 5. השליחה ===========================================================
create or replace function app.arco_outbound_send(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  o      arco_outbound;
  v_url  text;
  v_req  bigint;
begin
  select * into o from arco_outbound where id = p_id;
  if o.id is null or o.status not in ('queued', 'failed') then return; end if;

  if o.origin = 'arco' then
    update arco_outbound set status = 'skipped' where id = p_id;
    return;
  end if;

  select url into v_url from app.arco_webhook_targets where connection_id = o.connection_id;
  -- בלי כתובת או בלי pg_net השורה נשארת בתור, והיא תצא ב"שלח שוב".
  if v_url is null or to_regproc('net.http_post') is null then return; end if;

  execute 'select net.http_post(url := $1, body := $2, headers := $3)'
     into v_req
    using v_url,
          app.arco_flat_payload(o.event_id),
          jsonb_build_object('Content-Type', 'application/json');

  update arco_outbound set status = 'sending', request_id = v_req, attempts = attempts + 1
   where id = p_id;
exception when others then
  -- כישלון בשליחה אינו מבטל את השמירה שיצרה אותה.
  update arco_outbound set status = 'failed', attempts = attempts + 1,
         last_error = left(sqlerrm, 500)
   where id = p_id;
end $$;

create or replace function app.arco_outbound_on_commit()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  perform app.arco_outbound_reconcile();
  perform app.arco_outbound_send(new.id);
  return null;
end $$;

-- דחוי: רץ פעם אחת לשורה, ב-commit, אחרי כל ההוראות של אותה שמירה (§1).
create constraint trigger arco_outbound_send_on_commit
  after insert on arco_outbound
  deferrable initially deferred
  for each row execute function app.arco_outbound_on_commit();

-- ===== 6. "שלח שוב" ========================================================
create or replace function arco_outbound_retry(p_id uuid default null)
returns int language plpgsql security definer set search_path = public as $$
declare
  v_count int := 0;
  r       record;
begin
  perform app.require('integrations.manage', 'אין לך הרשאה לשלוח דיווח מחדש');
  perform app.arco_outbound_reconcile();

  for r in select id from arco_outbound
            where status in ('queued', 'failed') and (p_id is null or id = p_id)
            order by created_at
  loop
    perform app.arco_outbound_send(r.id);
    v_count := v_count + 1;
  end loop;
  return v_count;
end $$;

revoke execute on function arco_outbound_retry(uuid) from anon, public;
grant  execute on function arco_outbound_retry(uuid) to authenticated;

revoke execute on function app.arco_decimal_text(numeric)  from anon, authenticated, public;
revoke execute on function app.arco_flat_payload(uuid)     from anon, authenticated, public;
revoke execute on function app.arco_outbound_reconcile()   from anon, authenticated, public;
revoke execute on function app.arco_outbound_send(uuid)    from anon, authenticated, public;
revoke execute on function app.arco_outbound_on_commit()   from anon, authenticated, public;
