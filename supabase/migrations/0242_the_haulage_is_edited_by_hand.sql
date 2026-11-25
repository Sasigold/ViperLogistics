-- 0242: ההובלה נערכת ביד, והסנכרון ממשיך לרוץ
--
-- אצל שיא עיצובים האירועים נולדים מהזמנה ב-ViperFlow, וארבעת סעיפי הכסף
-- שמגיעים משם — ריהוט חדש, ריהוט ישן, כיסאות, פריטים חופשיים — ועוד ההובלות,
-- נעולים לעריכה כל עוד הסנכרון רץ (0212 §9): "כדי לערוך אותו ביד יש לעצור את
-- הסנכרון לאירוע". הנעילה נכונה לסעיפי הריהוט, שהם מה שההזמנה אומרת. ההובלה
-- אינה כזו: המחיר שההזמנה נושאת הוא מה שהלקוח הזמין, ובפועל הבעלים מתקן אותו
-- — משאית שהתווספה, נסיעה שלא הייתה, מחיר שהוסכם בטלפון. עד כאן התיקון דרש
-- "עצירת סנכרון", שמקפיאה את *כל* האירוע: תאריכים, שעות, כמויות, סטטוס
-- ומפרט. בשביל מספר אחד.
--
-- מכאן:
--
--   1. ‏`income_categories.manual_override` — קטגוריה שהסכום שלה מגיע
--      מ-ViperFlow ומותר בכל זאת לערוך אותו ביד. נדלק כאן ל"הובלות" בלבד,
--      במיגרציה ולא במסך: כמו `viperflow_income_source` (0190), מי מקבל מה
--      נקבע כאן, ולא במתג שמעביר כסף בלי שאיש יראה.
--   2. ‏`event_income.is_manual` — השורה הזו נערכה ביד, והיא גוברת. הסנכרון
--      כבר אינו כותב את `amount` שלה, רק את `synced_amount` לצדה: המספר
--      שההזמנה אומרת עכשיו, לתצוגה ולחזרה.
--   3. חזרה: שדה ריק בחלון העריכה, או `event_income_release`, מחזירים את
--      השורה לסכום של ViperFlow ומשחררים את הנעילה.
--
-- מה *לא* משתנה: סעיפי הריהוט נשארים נעולים בדיוק כפי שהיו; אחוז החלוקה
-- (`viper_share_pct`) והעמלה הידנית (0212) נגזרים מהסכום כמו תמיד, ולכן סכום
-- ידני נספר בכל מקום שבו הסכום נספר — ‏`app.event_payment_dues`, הדשבורד,
-- הדוחות — בלי שאף אחד מהם יודע על 0242. ההתראה "ההזמנה השתנתה" (0190 §3)
-- ממשיכה לדווח על שינוי בהובלות, שהרי ה-snapshot נכתב מההזמנה ולא ממה
-- שהוחל — וזו בדיוק ההודעה שצריכה להגיע כשההזמנה זזה מתחת לסכום ידני.

-- ===== 1. הקטגוריה אומרת שמותר לערוך אותה =================================

alter table income_categories
  add column manual_override boolean not null default false;

comment on column income_categories.manual_override is
  'קטגוריה שמקבלת סכום מ-ViperFlow ומותר לערוך אותו ביד גם כשהסנכרון רץ — '
  'העריכה ננעלת והסנכרון מפסיק לדרוס אותה (0242). רק להובלות.';

update income_categories
   set manual_override = true
 where viperflow_income_source = 'trucking';

-- ===== 2. השורה זוכרת מה היד קבעה ומה ההזמנה אומרת =========================
--
-- ‏`synced_amount` נזרע מהסכום הקיים בשורות שמגיעות מ-ViperFlow: עד עכשיו הן
-- היו נעולות, ולכן הסכום ששמור בהן *הוא* מה שנמסר — וכך "חזרה לסכום
-- מ-ViperFlow" עובדת גם באירועים שכבר קיימים.

alter table event_income
  add column is_manual     boolean not null default false,
  add column synced_amount numeric(12,2),
  add column manual_set_at timestamptz,
  add column manual_set_by uuid references profiles(id) on delete set null;

comment on column event_income.is_manual is
  'הסכום נקבע ביד וגובר על ViperFlow (0242). רק בקטגוריה עם manual_override.';
comment on column event_income.synced_amount is
  'הסכום שהסנכרון מ-ViperFlow מסר אחרון לקטגוריה הזו (0242). null = לא נמסר.';

update event_income ei
   set synced_amount = ei.amount
  from income_categories ic, viperflow_links l
 where ic.id = ei.category_id
   and ic.viperflow_income_source is not null
   and l.event_id = ei.event_id;

-- ===== 3. הסנכרון אינו דורס סכום ידני ======================================
--
-- גוף 0192 §5, ועוד שער: שורה שנעולה ביד מקבלת רק את `synced_amount`. מחזירה
-- `false` כשלא כתבה את הכסף, כדי ששורת היומן של המתרגם לא תאמר שכתבה.

create or replace function app.viperflow_apply_income(
  p_event    uuid,
  p_customer uuid,
  p_source   text,
  p_amount   numeric)
returns boolean language plpgsql security definer set search_path = public as $$
declare
  v_cat    uuid;
  v_pct    numeric;
  v_manual boolean;
  v_sys    boolean := app.in_system_write();
begin
  if p_event is null or p_amount is null then return false; end if;

  select id into v_cat from income_categories
   where viperflow_income_source = p_source and is_active and deleted_at is null
   order by sort_order, id limit 1;
  if v_cat is null then return false; end if;

  select s.viper_share_pct into v_pct from customer_income_splits s
   where s.customer_id = p_customer and s.category_id = v_cat;
  if v_pct is null then return false; end if;

  select ei.is_manual into v_manual from event_income ei
   where ei.event_id = p_event and ei.category_id = v_cat;

  perform app.system_write(true);
  if coalesce(v_manual, false) then
    update event_income set synced_amount = p_amount
     where event_id = p_event and category_id = v_cat;
  else
    insert into event_income (event_id, category_id, amount, viper_share_pct, synced_amount)
    values (p_event, v_cat, p_amount, v_pct, p_amount)
    on conflict (event_id, category_id) do update
      set amount          = excluded.amount,
          viper_share_pct = excluded.viper_share_pct,
          synced_amount   = excluded.synced_amount;
  end if;
  if not v_sys then perform app.system_write(false); end if;

  return not coalesce(v_manual, false);
end $$;

comment on function app.viperflow_apply_income(uuid, uuid, text, numeric) is
  'כותב סכום מ-ViperFlow לקטגוריית ההכנסה שמסומנת לאותו מקור (0190, 0192). '
  'שורה שנערכה ביד (0242) מקבלת רק את synced_amount, והפונקציה מחזירה false.';

revoke execute on function app.viperflow_apply_income(uuid, uuid, text, numeric)
  from anon, authenticated, public;

-- ===== 4. העריכה ביד: השער של 0212, עם פתח להובלות =========================
create or replace function app.apply_event_income(p_event_id uuid, p_customer uuid, payload jsonb)
returns void language plpgsql security definer set search_path = public as $$
declare
  r        record;
  v_cat    uuid;
  v_amount numeric;
  v_pct    numeric;
  v_name   text;
  v_source text;
  v_override boolean;
  v_pin    boolean;
  v_synced boolean;
  v_found  boolean;
  v_now    numeric;
  v_actor  uuid := app.profile_id();
begin
  if not (payload ? 'event_income') then return; end if;
  if not app.has('finance.income_edit') then return; end if;

  -- ‏0212: null = האירוע אינו מקושר ל-ViperFlow.
  select l.sync_locked_at is null into v_synced
    from viperflow_links l where l.event_id = p_event_id;

  for r in select key, nullif(btrim(coalesce(value, '')), '') as raw
             from jsonb_each_text(coalesce(payload -> 'event_income', '{}'::jsonb))
  loop
    begin
      v_cat := r.key::uuid;
    exception when others then
      raise exception 'קטגוריית הכנסה לא מוכרת: %', r.key;
    end;
    v_name := null;
    v_source := null;
    v_override := null;
    select name, viperflow_income_source, manual_override
      into v_name, v_source, v_override
      from income_categories where id = v_cat;
    -- ‏0242: נעילה יש רק מול סנכרון. באירוע שאינו מקושר ל-ViperFlow כל
    -- הסכומים ממילא ידניים, ואין ממה להגן עליהם.
    v_pin := coalesce(v_override, false) and v_synced is not null;

    v_amount := null;
    if r.raw is not null then
      begin
        v_amount := r.raw::numeric;
      exception when others then
        raise exception 'ערך לא תקין בשדה "%": %', coalesce(v_name, r.key), r.raw;
      end;
      if v_amount < 0 then
        raise exception 'סכום שלילי אינו חוקי בשדה "%"', coalesce(v_name, r.key);
      end if;
    end if;

    -- ‏0212: הסכום של ViperFlow, באירוע שהסנכרון שלו רץ. ‏0242: קטגוריה
    -- שמסומנת `manual_override` — ההובלות — נערכת גם אז, והעריכה ננעלת
    -- (‏§3). ערך זהה למה שכבר שמור עובר בשקט בשני המקרים, ולכן שמירה של
    -- שדה אחר בטופס האירוע אינה נועלת סכום שאיש לא נגע בו.
    if coalesce(v_synced, false) and v_source is not null then
      select true, ei.amount into v_found, v_now
        from event_income ei where ei.event_id = p_event_id and ei.category_id = v_cat;
      if (v_amount is null and coalesce(v_found, false))
         or (v_amount is not null and v_now is distinct from v_amount) then
        if not coalesce(v_override, false) then
          raise exception 'הסכום של "%" מגיע מ-ViperFlow — כדי לערוך אותו ביד יש לעצור את הסנכרון לאירוע',
            coalesce(v_name, r.key);
        end if;
      else
        v_found := null;
        v_now := null;
        continue;
      end if;
      v_found := null;
      v_now := null;
    end if;

    -- ‏0242: בקטגוריה שנערכת ביד, שדה ריק אינו מוחק את השורה אלא מחזיר
    -- אותה לסכום שהגיע מ-ViperFlow — אם הגיע כזה. בלי סכום כזה (אירוע שאינו
    -- מקושר, או קטגוריה שטרם נמסרה) זו מחיקה, כמו ב-0068.
    if v_amount is null then
      if v_pin then
        update event_income
           set amount = synced_amount, is_manual = false,
               manual_set_at = null, manual_set_by = null
         where event_id = p_event_id and category_id = v_cat
           and synced_amount is not null;
        if found then continue; end if;
      end if;
      delete from event_income
       where event_id = p_event_id and category_id = v_cat;
      continue;
    end if;

    -- ה-snapshot: האחוז הנוכחי של הלקוח, ברגע הכתיבה. קטגוריה בלי שורת חלוקה
    -- אינה מופעלת ללקוח הזה — והזנה אליה היא טעות שצריך לשמוע עליה.
    v_pct := null;
    select s.viper_share_pct into v_pct
      from customer_income_splits s
      join income_categories ic on ic.id = s.category_id
     where s.customer_id = p_customer and s.category_id = v_cat
       and ic.deleted_at is null;
    if v_pct is null then
      raise exception 'הקטגוריה "%" אינה מופעלת ללקוח של האירוע',
        coalesce(v_name, r.key);
    end if;

    -- ‏0242: הזנה ביד בקטגוריה כזו ננעלת — ‏`is_manual` — וממנה והלאה
    -- הסנכרון רק מעדכן את `synced_amount` לצדה (‏§3). רק סכום שזז נועל:
    -- שמירה שחוזרת על הסכום הקיים אינה "עריכה ידנית".
    insert into event_income (event_id, category_id, amount, viper_share_pct,
                              is_manual, manual_set_at, manual_set_by)
    values (p_event_id, v_cat, v_amount, v_pct,
            v_pin,
            case when v_pin then now() end,
            case when v_pin then v_actor end)
    on conflict (event_id, category_id) do update set
      amount = excluded.amount,
      viper_share_pct = excluded.viper_share_pct,
      is_manual = event_income.is_manual
                  or (v_pin
                      and event_income.amount is distinct from excluded.amount),
      manual_set_at = case when v_pin
                            and event_income.amount is distinct from excluded.amount
                           then now() else event_income.manual_set_at end,
      manual_set_by = case when v_pin
                            and event_income.amount is distinct from excluded.amount
                           then v_actor else event_income.manual_set_by end;
  end loop;
end $$;

revoke execute on function app.apply_event_income(uuid, uuid, jsonb) from anon, authenticated, public;
-- ===== 5. הפירוט: מה ידני, ומה ההזמנה אומרת ================================
--
-- גוף 0212 §13, ועוד: בשורת הכנסה — ‏`manual_override`, ‏`is_manual`,
-- ‏`synced_amount` ו-`manual_set_at`, ו-`synced` (הנעילה בתצוגה) כבר אינו
-- דולק על שורה ידנית. בקטגוריות לחלון העריכה — אותם שדות, ו-`editable`
-- שנפתח לקטגוריה שמותר לערוך ביד.

create or replace function event_payment_summary(p_event_id uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_event   events;
  v_enabled boolean;
  v_row     app.event_payment_dues;
  v_lines   jsonb;
  v_pays    jsonb;
  v_link    viperflow_links;
  v_synced  boolean;
  v_can     boolean := app.can_edit_event_income();
  v_cats    jsonb;
begin
  if not app.can_view_event_payments() then
    raise exception 'אין לך הרשאה לצפות בתשלומי אירועים' using errcode = '42501';
  end if;

  select * into v_event from events where id = p_event_id and deleted_at is null;
  if v_event.id is null then raise exception 'אירוע לא נמצא'; end if;

  select event_payments_enabled into v_enabled from customers where id = v_event.customer_id;
  if not coalesce(v_enabled, false) then
    return jsonb_build_object('enabled', false);
  end if;

  select * into v_row from app.event_payment_dues where event_id = p_event_id;

  select * into v_link from viperflow_links where event_id = p_event_id;
  v_synced := v_link.event_id is not null and v_link.sync_locked_at is null;

  select coalesce(jsonb_agg(x.line order by x.sort, x.at), '[]'::jsonb) into v_lines from (
    select 0 as sort, null::timestamptz as at, jsonb_build_object(
             'key', 'logistics', 'label', 'לוגיסטיקה',
             'amount', round(v_row.logistics, 2), 'gross', null, 'pct', null) as line
     where v_row.logistics <> 0
    union all
    select (case when ei.commission_amount is null and not ic.manual_commission
                      and ei.viper_share_pct >= 100 then 1000 else 2000 end) + ic.sort_order, null,
           jsonb_build_object(
             'key', ic.id, 'label', ic.name, 'category_id', ic.id,
             'amount', app.income_viper_share(ei.amount, ei.viper_share_pct, ei.commission_amount),
             'gross', ei.amount,
             'pct', case when ic.manual_commission or ei.commission_amount is not null
                         then null else ei.viper_share_pct end,
             'manual_commission', ic.manual_commission,
             'commission', ei.commission_amount,
             'commission_basis', ei.commission_basis,
             'commission_set_at', ei.commission_set_at,
             'commission_stale', ei.commission_amount is not null
                                 and ei.commission_basis is distinct from ei.amount,
             -- ‏0242: שורה שנעולה בעריכה ידנית אינה "מגיעה מ-ViperFlow"
             -- יותר — היא כן ממשיכה לדעת מה הסכום שהגיע משם.
             'synced', v_synced and ic.viperflow_income_source is not null
                       and not ei.is_manual,
             'manual_override', ic.manual_override,
             'is_manual', ei.is_manual,
             'synced_amount', ei.synced_amount,
             'manual_set_at', ei.manual_set_at)
      from event_income ei
      join app.live_events le on le.id = ei.event_id
      join income_categories ic on ic.id = ei.category_id
     where ei.event_id = p_event_id
       and (ei.amount <> 0 or ei.commission_amount is not null)
    union all
    select 3000, ec.created_at,
           jsonb_build_object(
             'key', ec.id, 'label', ec.label, 'amount', ec.amount,
             'gross', null, 'pct', null, 'charge_id', ec.id, 'note', ec.note)
      from event_charges ec
      join app.live_events le on le.id = ec.event_id
     where ec.event_id = p_event_id and ec.deleted_at is null) x;

  select coalesce(jsonb_agg(jsonb_build_object(
           'id', r.id, 'amount', r.amount, 'received_at', r.received_at,
           'method', r.method, 'note', r.note, 'created_at', r.created_at,
           'created_by_name', p.full_name)
           order by r.received_at desc, r.created_at desc), '[]'::jsonb)
    into v_pays
    from receipts r
    left join profiles p on p.id = r.created_by
   where r.event_id = p_event_id and r.deleted_at is null;

  if v_can then
    select coalesce(jsonb_agg(jsonb_build_object(
             'id', ic.id, 'name', ic.name, 'family', ic.family,
             'amount', ei.amount,
             'manual_commission', ic.manual_commission,
             'source', ic.viperflow_income_source,
             'manual_override', ic.manual_override,
             -- ‏`ei` הוא left join: קטגוריה שאין עליה שורה אינה ידנית.
             'is_manual', coalesce(ei.is_manual, false),
             'synced_amount', ei.synced_amount,
             'editable', not (v_synced and ic.viperflow_income_source is not null
                              and not ic.manual_override))
             order by ic.sort_order, ic.name), '[]'::jsonb)
      into v_cats
      from customer_income_splits s
      join income_categories ic on ic.id = s.category_id
                               and ic.is_active and ic.deleted_at is null
      left join event_income ei on ei.event_id = p_event_id and ei.category_id = ic.id
     where s.customer_id = v_event.customer_id;
  end if;

  return jsonb_build_object(
    'enabled',   true,
    'cancelled', v_row.cancelled,
    'lines',     v_lines,
    'due',       round(v_row.due, 2),
    'paid',      round(v_row.paid, 2),
    'balance',   round(v_row.balance, 2),
    'payments',  v_pays,
    'can_manage', app.can_manage_event_payments(),
    'can_edit_income', v_can,
    'viperflow', case when v_link.event_id is not null
                      then jsonb_build_object('locked', v_link.sync_locked_at is not null) end,
    'income_categories', v_cats);
end $$;

revoke execute on function event_payment_summary(uuid) from anon, public;
grant  execute on function event_payment_summary(uuid) to authenticated;
-- ===== 6. חזרה לסכום של ViperFlow ==========================================
--
-- אותו מפתח של עריכת הסכומים (‏`finance.income_edit`). בלי סכום שנמסר
-- מ-ViperFlow אין לאן לחזור, והשורה — שהיא כולה מה שהיד הזינה — יורדת.

create or replace function event_income_release(p_event_id uuid, p_category_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_event  events;
  v_actor  uuid := app.profile_id();
  v_name   text;
  v_synced numeric;
  v_found  boolean;
begin
  if not app.can_edit_event_income() then
    raise exception 'אין לך הרשאה לערוך הכנסות' using errcode = '42501';
  end if;

  select * into v_event from events where id = p_event_id and deleted_at is null;
  if v_event.id is null then raise exception 'אירוע לא נמצא'; end if;

  select ic.name, ei.synced_amount, true
    into v_name, v_synced, v_found
    from event_income ei
    join income_categories ic on ic.id = ei.category_id
   where ei.event_id = p_event_id and ei.category_id = p_category_id
     and ei.is_manual;
  if not coalesce(v_found, false) then
    raise exception 'אין סכום ידני לשחרור בקטגוריה הזו';
  end if;

  if v_synced is null then
    delete from event_income
     where event_id = p_event_id and category_id = p_category_id;
  else
    update event_income
       set amount = v_synced, is_manual = false,
           manual_set_at = null, manual_set_by = null
     where event_id = p_event_id and category_id = p_category_id;
  end if;

  insert into event_activity (event_id, kind, actor_profile_id, actor_name, note)
  values (p_event_id, 'note', v_actor, (select full_name from profiles where id = v_actor),
          'הסכום של "' || v_name || '" חזר לסכום מ-ViperFlow');
end $$;

comment on function event_income_release(uuid, uuid) is
  'מבטל עריכה ידנית של סעיף הכנסה ומחזיר אותו לסכום שהסנכרון מסר (0242).';

revoke execute on function event_income_release(uuid, uuid) from anon, public;
grant  execute on function event_income_release(uuid, uuid) to authenticated;
