-- 0197: ה-Webhook של ViperFlow מוצא את החיבור שלו
--
-- התקלה: **אף משלוח של ViperFlow לא נקלט דרך ה-Webhook.** כל קריאה ל-
-- `viperflow-webhook` חזרה ב-503, ובלוג: `function min(uuid) does not exist`.
-- מה שכן נכנס נכנס רק מ"סנכרון עכשיו", ולכן שינוי ב-ViperFlow הגיע אלינו
-- רק כשמישהו לחץ.
--
-- הסיבה: כשהכתובת אינה נושאת מזהה חיבור, `viperflow_ingest` (0177 §5) בוחר
-- את החיבור הפעיל היחיד עם `min(c.id)` — ול-uuid אין `min` בפוסטגרס. המסלול
-- הזה הוא בדיוק המסלול של ה-Webhook בכתובת הרגילה; הסנכרון מעביר
-- `connection_id` ולכן מעולם לא הגיע אליו, וגם הבדיקות ב-49 העבירו אותו
-- תמיד. חריגה שם קורית **לפני** שהמשלוח נרשם, ולכן לא נשארה אפילו שורה
-- אדומה במסך — רק 503, ש-ViperFlow מנסה שוב ושוב.
--
-- התיקון: `(array_agg(c.id))[1]` במקום `min(c.id)`. הבחירה נשמרת רק כשהספירה
-- היא 1, ולכן איזה מהם "ראשון" אינו משנה. שאר הפונקציה זהה ל-0177 אות באות.
--
-- משלוחים שנדחו ב-503 עדיין בתור של ViperFlow (שומר 30 יום ומנסה שוב), והם
-- ייקלטו מעצמם בניסיון הבא. אם בינתיים נקודת הקצה כובתה שם — להדליק אותה
-- מחדש, ו"סנכרון עכשיו" משלים את מה שהוחמץ.

create or replace function viperflow_ingest(p_envelope jsonb, p_meta jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_event_id   text := p_envelope ->> 'id';
  v_type       text := p_envelope ->> 'type';
  v_data       jsonb := p_envelope -> 'data';
  v_conn       uuid;
  v_active     int;
  v_row        uuid;
  v_result     jsonb;
  v_entity     text;
begin
  -- קורא עם JWT הוא אדם שלחץ "הרץ מחדש" (§6); בלי JWT זו פונקציית הקצה
  -- בזהות service role. אותה הבחנה של `fleet_expiry_sweep` (0089).
  if auth.uid() is not null then
    perform app.require('integrations.manage', 'אין לך הרשאה להזרים אירועי ViperFlow');
  end if;

  if coalesce(v_event_id, '') !~ '^evt_[0-9a-f]{32}$' or coalesce(v_type, '') = '' then
    raise exception 'מעטפה פגומה' using errcode = '22023';
  end if;

  -- מי כותב ביומן כשאיש לא לחץ (0176 §2). התווית מקומית לטרנזקציה, ולכן
  -- שינויי השדות שהטריגרים של 0016/0112 ירשמו בהמשך יישאו את השם הזה —
  -- ורק הם: כל שאר המערכת פשוט אינה מגדירה את ה-GUC הזה.
  perform set_config('app.actor_label', 'ViperFlow', true);

  -- החיבור: לפי מה שפונקציית הקצה זיהתה מהנתיב, ואם לא — החיבור הפעיל
  -- **היחיד**.
  --
  -- ‏`into` על שאילתה שמחזירה שתי שורות לוקח את הראשונה ולא מתלונן, וזה היה
  -- מפיל הזמנה של לקוח אחד על הלקוח השני. לכן הספירה: אחד נבחר, יותר מאחד
  -- נרשם ככישלון עם סיבה שאומרת בדיוק מה לעשות — להוסיף את מזהה החיבור
  -- לכתובת נקודת הקצה.
  v_conn := nullif(p_meta ->> 'connection_id', '')::uuid;
  if v_conn is null then
    select count(*), (array_agg(c.id))[1] into v_active, v_conn
      from viperflow_connections c
     where c.is_active and c.deleted_at is null;
    if v_active <> 1 then v_conn := null; end if;
  end if;

  v_entity := v_data ->> 'id';

  insert into viperflow_deliveries (
    connection_id, event_id, delivery_id, event_type, attempt, origin,
    entity_id, occurred_at, payload)
  values (
    v_conn, v_event_id, nullif(p_meta ->> 'delivery_id', ''), v_type,
    nullif(p_meta ->> 'attempt', '')::int, nullif(p_meta ->> 'origin', ''),
    v_entity, nullif(p_envelope ->> 'created_at', '')::timestamptz, p_envelope)
  on conflict (event_id) do nothing
  returning id into v_row;

  -- ניסיון חוזר של אותו אירוע. ‏ViperFlow מבטיח at-least-once, והאינדקס
  -- הייחודי הוא כל מנגנון האי-כפילות.
  --
  -- ‏`force` מדלג גם על זה, ובכוונה: הוא הכלי של מי שאומר "המצב אצלנו שגוי,
  -- משוך שוב" — ותשובת "כבר ראינו את המעטפה הזו" היא בדיוק מה שהוא מנסה
  -- לעקוף. השורה הקיימת נכתבת מחדש ואינה מוכפלת.
  if v_row is null then
    if not coalesce((p_meta ->> 'force')::boolean, false) then
      return jsonb_build_object('status', 'duplicate', 'event_id', v_event_id);
    end if;
    select id into v_row from viperflow_deliveries where event_id = v_event_id;
  end if;

  begin
    if v_type = 'webhook.test' then
      v_result := jsonb_build_object('status', 'ignored', 'reason', 'אירוע בדיקה');
    elsif v_conn is null then
      v_result := jsonb_build_object('status', 'failed', 'reason',
        case when coalesce(v_active, 0) > 1
             then 'יש ' || v_active || ' חיבורים פעילים ולא נאמר לאיזה מהם — יש להוסיף את מזהה החיבור לכתובת נקודת הקצה'
             else 'אין חיבור ViperFlow פעיל' end);
    elsif v_type in ('order.created', 'order.updated', 'order.confirmed',
                     'order.status_changed', 'order.picked', 'order.delivered',
                     'order.returned', 'order.cancelled', 'order.deleted') then
      v_result := app.viperflow_apply_order(
        v_conn, v_data, v_type, coalesce((p_meta ->> 'force')::boolean, false));
    else
      -- ‏41 סוגי אירוע קיימים אצלם, ורובם אינם אומרים דבר על עבודה שלנו.
      -- הם נרשמים כדי שיהיה אפשר לראות מה נכנס, ולא מתורגמים.
      v_result := jsonb_build_object('status', 'ignored',
                                     'reason', 'סוג אירוע שאינו מתורגם');
    end if;
  exception when others then
    -- **לא כל כישלון הוא כישלון עסקי.** ‏deadlock מול רכז ששומר את אותו
    -- אירוע, נעילה שלא התפנתה, או statement_timeout על הזמנה כבדה — כולם
    -- ייעלמו בניסיון הבא, ולכן הם צריכים להיזרק החוצה: ה-RPC ייכשל,
    -- פונקציית הקצה תענה 503, ו-ViperFlow ינסה שוב לפי לוח הזמנים שלו.
    -- ‏`failed` שמור למה שלא ישתנה מעצמו — "הזמנה בלי תאריך אירוע" — ושם
    -- דווקא נכון להחזיר 200, כי ניסיון חוזר רק יבזבז את עשרת הכישלונות
    -- שאחריהם הם מכבים את נקודת הקצה.
    if sqlstate like '40%' or sqlstate like '53%' or sqlstate in ('55P03', '57014') then
      raise;
    end if;

    update viperflow_deliveries set
      status = 'failed', reason = left(sqlerrm, 500), processed_at = now()
     where id = v_row;
    return jsonb_build_object('status', 'failed', 'event_id', v_event_id,
                              'reason', sqlerrm);
  end;

  update viperflow_deliveries set
    status = case v_result ->> 'status'
               when 'processed' then 'processed'
               when 'stale'     then 'ignored'
               when 'failed'    then 'failed'
               else 'ignored' end,
    reason = coalesce(v_result ->> 'reason',
                      case when v_result ->> 'status' = 'stale'
                           then 'משלוח ישן — כבר הוחל עדכון חדש יותר' end),
    event_row_id = nullif(v_result ->> 'event_id', '')::uuid,
    processed_at = now()
   where id = v_row;

  return v_result || jsonb_build_object('delivery', v_row);
end $$;

revoke execute on function viperflow_ingest(jsonb, jsonb) from anon, public;
grant  execute on function viperflow_ingest(jsonb, jsonb) to service_role, authenticated;
