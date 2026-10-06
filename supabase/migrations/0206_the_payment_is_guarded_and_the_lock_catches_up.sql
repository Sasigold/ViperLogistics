-- 0206: תשלום על אירוע נשמר מאחורי המפתח שלו, והשחרור משלים גם את מה שהגיע ברגע הנעילה
--
-- שני ממצאים של סקירת הקוד על 0204/0205 (PR #25):
--
--   1. **הדחייה של `finance.event_payments_manage` לא נאכפה על הטבלה.**
--      ‏0205 גידר את ה-RPCs במפתח החדש, אבל פוליסות ה-insert/update של
--      `receipts` (0068) עדיין שואלות רק על `finance.receipts_manage`, ומסך
--      התקבולים כותב לטבלה ישירות. מי שהמפתח החדש נסגר לו במפורש — וזו כל
--      הנקודה ב-implied_by שאפשר לדחות — עדיין יכול היה לרשום, לערוך ולמחוק
--      תשלום על אירוע דרך מסך התקבולים או ה-REST. התיקון: הטריגר של 0205
--      רץ עכשיו על **כל** insert/update, ותקבול שקשור לאירוע (לפני השינוי או
--      אחריו) נכתב רק בידי מי ש-`app.can_manage_event_payments()` עונה לו כן.
--      כתיבה בלי JWT (מיגרציה, שירות) אינה אדם, והיא עוברת כמו קודם.
--
--   2. **השחרור החמיץ משלוח שנכנס רגע לפני הנעילה.** ‏0204 בחר את המשלוח
--      להשלמה לפי `received_at >= sync_locked_at`. אבל `received_at` הוא
--      `now()` של טרנזקציית ה-Webhook — זמן *ההתחלה* שלה. משלוח שנכנס לטבלה,
--      חיכה על נעילת-הייעוץ בזמן שהנעילה נשמרה, ורק אז נדחה כ"נעול", נושא
--      זמן מוקדם מהנעילה — והשחרור דילג עליו. התיקון: הבחירה אינה לפי מתי
--      המשלוח הגיע אלא לפי מה שהוא אומר — המשלוח הנעול שחותמת ההזמנה שלו
--      (`data.updated_at`) חדשה מזו שכבר הוחלה על הקישור. משלוח ישן ממחזור
--      נעילה קודם אינו נבחר, כי החותמת שלו כבר אינה חדשה.

-- ===== 1. הטריגר על התקבולים ==============================================
-- גוף 0205, ועוד שער המפתח. ‏42501 כי זו הרשאה, לא כלל עסקי.

create or replace function app.receipts_event_guard()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_customer uuid;
begin
  -- ‏0206: תשלום על אירוע — לפני השינוי או אחריו — הוא של מי שמחזיק את
  -- המפתח שלו, גם כשהכתיבה מגיעה ישר לטבלה ולא דרך ה-RPC.
  if auth.uid() is not null
     and (new.event_id is not null
          or (tg_op = 'UPDATE' and old.event_id is not null))
     and not app.can_manage_event_payments() then
    raise exception 'אין לך הרשאה לרשום או לערוך תשלום על אירוע' using errcode = '42501';
  end if;

  if new.event_id is null then return new; end if;
  select customer_id into v_customer from events where id = new.event_id;
  if v_customer is null then
    raise exception 'האירוע של התשלום לא נמצא';
  end if;
  if new.customer_id is distinct from v_customer then
    raise exception 'תשלום על אירוע נרשם על הלקוח של האירוע';
  end if;
  return new;
end $$;

revoke execute on function app.receipts_event_guard() from anon, authenticated, public;

-- ‏0205 הפעיל אותו רק על `update of event_id, customer_id`, ולכן שינוי סכום
-- או מחיקה רכה עקפו אותו. עכשיו — כל עדכון.
drop trigger if exists receipts_event_guard on receipts;
create trigger receipts_event_guard before insert or update on receipts
  for each row execute function app.receipts_event_guard();

-- ===== 2. השחרור בוחר לפי חותמת ההזמנה ====================================
-- גוף 0204, ושאילתת הבחירה בלבד מוחלפת.

create or replace function viperflow_set_event_lock(p_event_id uuid, p_locked boolean)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_link     viperflow_links;
  v_actor    uuid := app.profile_id();
  v_name     text;
  v_delivery uuid;
  v_result   jsonb;
begin
  perform app.require('integrations.manage', 'אין לך הרשאה לעצור או לחדש סנכרון של אירוע');

  select * into v_link from viperflow_links where event_id = p_event_id;
  if v_link.event_id is null then
    raise exception 'האירוע לא הגיע מ-ViperFlow — אין סנכרון לעצור';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(v_link.connection_id::text || ':' || v_link.order_id::text, 0));
  select * into v_link from viperflow_links where event_id = p_event_id;

  -- כבר במצב המבוקש: אין שורת יומן ואין השלמה.
  if (v_link.sync_locked_at is not null) = coalesce(p_locked, false) then
    return jsonb_build_object('locked', v_link.sync_locked_at is not null,
                              'locked_at', v_link.sync_locked_at);
  end if;

  select full_name into v_name from profiles where id = v_actor;

  if p_locked then
    update viperflow_links set sync_locked_at = now(), sync_locked_by = v_actor
     where event_id = p_event_id;

    insert into event_activity (event_id, kind, actor_profile_id, actor_name, note)
    values (p_event_id, 'sync_locked'::event_activity_kind, v_actor, v_name,
            'הסנכרון מ-ViperFlow נעצר — סכומים, שעות, כמויות ומפרט לא ישתנו מההזמנה');

    return jsonb_build_object('locked', true, 'locked_at', now());
  end if;

  -- ── שחרור ────────────────────────────────────────────────────────────────
  -- ‏0206: המשלוח הנעול שהחותמת שלו חדשה ממה שכבר הוחל — בלי תנאי על זמן
  -- ההגעה (ראו §2 בראש הקובץ). החותמת נקראת רק כשהיא נראית כתאריך, כדי
  -- שמעטפה פגומה לא תפיל את השחרור כולו.
  select x.id into v_delivery
    from (select d.id, d.received_at,
                 case when (d.payload #>> '{data,updated_at}') ~ '^\d{4}-\d{2}-\d{2}'
                      then (d.payload #>> '{data,updated_at}')::timestamptz end as stamp
            from viperflow_deliveries d
           where d.connection_id = v_link.connection_id
             and d.entity_id = v_link.order_id::text
             and d.status = 'ignored'
             and d.reason = 'הסנכרון לאירוע הזה נעצר — ההזמנה נשמרה ולא הוחלה') x
   where x.stamp is not null
     and (v_link.order_updated_at is null or x.stamp > v_link.order_updated_at)
   order by x.stamp desc, x.received_at desc
   limit 1;

  update viperflow_links set sync_locked_at = null, sync_locked_by = null
   where event_id = p_event_id;

  insert into event_activity (event_id, kind, actor_profile_id, actor_name, note)
  values (p_event_id, 'sync_unlocked'::event_activity_kind, v_actor, v_name,
          case when v_delivery is null
               then 'הסנכרון מ-ViperFlow חודש — לא הגיעו שינויים בזמן העצירה'
               else 'הסנכרון מ-ViperFlow חודש — השינויים שהגיעו בזמן העצירה מוחלים עכשיו' end);

  if v_delivery is not null then
    v_result := viperflow_replay(v_delivery);
  end if;

  return jsonb_build_object('locked', false, 'locked_at', null,
                            'caught_up', v_delivery is not null,
                            'result', v_result);
end $$;

revoke execute on function viperflow_set_event_lock(uuid, boolean) from anon, public;
grant  execute on function viperflow_set_event_lock(uuid, boolean) to authenticated;
