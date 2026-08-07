-- 0017: תמחור ללקוח — מחיר לכל משימה ומחשבון פר-לקוח
--
-- עד כאן הייתה במערכת רק צלע אחת של הכסף: task_contractor_terms.price, מה
-- שאנחנו משלמים לקבלן. מה שאנחנו גובים מהלקוח לא היה קיים בשום מקום.
--
-- הקובץ הזה מוסיף את הצלע השנייה. שלוש החלטות עומדות בבסיסו:
--
-- 1. המחיר יושב על המשימה, לא על האירוע. הקמה ופירוק הן ממילא שתי שורות
--    tasks שנוצרות אוטומטית (app.create_default_tasks), ולכן "מחיר להקמה"
--    ו"מחיר לפירוק" הם פשוט המחיר של שתי המשימות האלה. מחיר האירוע = הסכום.
--
-- 2. המחיר יושב בטבלת לוויין ולא בעמודה על tasks. הקליינט קורא את tasks
--    ישירות — אף אחד לא קורא את tasks_secure — ו-RLS ב-Postgres הוא ברמת
--    שורה בלבד. עמודה גולמית על tasks הייתה נקראת בידי כל מי שה-RLS נותן לו
--    לראות את השורה, כולל הקבלן שהמשימה הואצלה אליו. task_contractor_terms
--    פתרה בדיוק את זה בדיוק ככה, ו-task_pricing הולכת באותו תלם.
--
-- 3. המחשבון הוא דאטה, לא קוד. לקוח חדש עם נוסחה חדשה הוא שורת JSONB
--    ב-customer_pricing_rules, לא מיגרציה ולא פריסה.

-- ===== 1. שדות קלט חדשים על המשימה =========================================
-- שני אלה הם *דריסות* בלבד. במסלול הרגיל זמן הנסיעה נגזר מאזור הגיאופנס של
-- מיקום האירוע, וראש הצוות הוא קבוע במחשבון; העמודות כאן קיימות כדי שאירוע
-- חריג — אולם רחוק במיוחד, אירוע שדורש ראש צוות אף שהלקוח לא לוקח כזה — לא
-- יאלץ לשנות את המחשבון של כל הלקוח. NULL פירושו "לך לפי ההגדרה".

alter table tasks
  add column travel_hours numeric(5,2)
    check (travel_hours is null or travel_hours >= 0),
  add column requires_team_lead boolean;

comment on column tasks.travel_hours is
  'דריסת זמן נסיעה בכיוון אחד (שעות). NULL = לפי אזור הגיאופנס של מיקום האירוע.';
comment on column tasks.requires_team_lead is
  'דריסת "נדרש ראש צוות". NULL = לפי הקבוע במחשבון התמחור של הלקוח.';

-- ===== 2. אזורי גיאופנס =====================================================
-- זמן הנסיעה הוא פונקציה של המיקום שהלקוח בוחר, ולכן הוא נשלף ממפת אזורים
-- ולא מוזן ידנית. אזור עם customer_id הוא פרטי ללקוח; אזור עם NULL הוא
-- ברירת מחדל גלובלית, ואזור פרטי תמיד גובר עליו.
--
-- הגאומטריה נשמרת כ-JSONB ולא כטיפוס PostGIS במכוון: התוסף אמנם זמין
-- בפרויקט אבל לא מותקן, ומעטפת הבדיקות (supabase/tests/run.sh) מריצה את
-- המיגרציות על Postgres נקי — תלות בתוסף הייתה שוברת אותה. בהיקפים כאן
-- (עשרות אזורים ללקוח) בדיקת הכלה ב-plpgsql זולה לגמרי.

create table pricing_zones (
  id           uuid primary key default gen_random_uuid(),
  customer_id  uuid references customers(id) on delete cascade,
  name         text not null,
  shape        text not null default 'polygon' check (shape in ('polygon', 'circle')),
  -- polygon: מערך נקודות [[lat,lng], ...]
  points       jsonb,
  -- circle: מרכז ורדיוס
  center_lat   double precision,
  center_lng   double precision,
  radius_km    numeric(8,3) check (radius_km is null or radius_km > 0),
  -- מה שהאזור תורם לחישוב
  travel_hours numeric(5,2) not null default 0 check (travel_hours >= 0),
  surcharge    numeric(12,2) not null default 0,
  -- אזור קטן שיושב בתוך אזור גדול צריך priority נמוך יותר כדי לגבור עליו
  priority     int not null default 100,
  color        text not null default '#3563f0',
  notes        text,
  is_active    boolean not null default true,
  deleted_at   timestamptz,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  constraint pricing_zones_geometry check (
    (shape = 'polygon' and points is not null)
    or (shape = 'circle' and center_lat is not null and center_lng is not null and radius_km is not null))
);
create index pricing_zones_customer_idx on pricing_zones (customer_id) where deleted_at is null;
create trigger pricing_zones_updated before update on pricing_zones
  for each row execute function app.set_updated_at();

-- ===== 3. מצב תמחור, מחשבונים ומחירים ======================================

alter table customers add column pricing_mode text not null default 'manual'
  check (pricing_mode in ('manual', 'auto'));
comment on column customers.pricing_mode is
  'manual = המחיר מוזן ידנית; auto = מחושב ממחשבון התמחור של הלקוח.';

-- מחשבון אחד לכל (לקוח × סוג משימה). להקמה ולפירוק יש נוסחאות שונות, ולכן
-- הם שתי שורות ולא אחת.
create table customer_pricing_rules (
  id           uuid primary key default gen_random_uuid(),
  customer_id  uuid not null references customers(id) on delete cascade,
  task_type_id uuid not null references task_types(id) on delete cascade,
  config       jsonb not null default '{"version":1,"model":"line_items"}'::jsonb,
  is_active    boolean not null default true,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  unique (customer_id, task_type_id)
);
create trigger customer_pricing_rules_updated before update on customer_pricing_rules
  for each row execute function app.set_updated_at();

-- המחיר עצמו. breakdown שומר את שורות החישוב כדי שאפשר יהיה להראות ללקוח
-- *איך* הגיעו למספר, ולא רק את המספר.
create table task_pricing (
  task_id       uuid primary key references tasks(id) on delete cascade,
  price         numeric(12,2) not null default 0,
  is_manual     boolean not null default false,
  breakdown     jsonb,
  calculated_at timestamptz,
  updated_at    timestamptz not null default now()
);
create trigger task_pricing_updated before update on task_pricing
  for each row execute function app.set_updated_at();

-- ===== 4. הרשאות ===========================================================
-- applies_to לא כולל contractor_user באף מפתח. זו לא הגנת האמת — ה-RLS היא —
-- אבל היא מונעת מהמטריצה להציע בכלל את האפשרות להעניק לקבלן ראייה למחירי
-- הלקוח, וטעות שלא ניתן לבצע עדיפה על טעות שנתפסת.

select app.register_module('pricing', 'תמחור ללקוח',
  'מחירי הקמה ופירוק, מחשבוני לקוח ואזורי נסיעה', 'Calculator', 75);

select app.register_permission('pricing.view', 'pricing', 'צפייה במחיר ללקוח',
  'המחיר שהלקוח משלם — במשימה, באירוע ובפורטל', 'field', false, true,
  array['staff', 'customer_user']::user_kind[], null, 10);

select app.register_permission('pricing.edit', 'pricing', 'עריכת מחיר ידנית',
  'הזנת מחיר או דריסת מחיר שחושב אוטומטית', 'action', false, true,
  array['staff']::user_kind[], null, 20);

select app.register_permission('pricing.manage_rules', 'pricing', 'ניהול מחשבוני תמחור',
  'בניית המחשבון בהגדרות הלקוח ואזורי הנסיעה', 'action', false, true,
  array['staff']::user_kind[], null, 30);

select app.register_permission('pricing.revenue', 'pricing', 'סיכום הכנסות',
  'סך המחירים ללקוח בדשבורד', 'field', false, true,
  array['staff', 'customer_user']::user_kind[], 'pricing.view', 40);

select app.register_field('task_pricing', 'price', 'מחיר ללקוח', 'pricing',
  'task_pricing', 'price', true, false, false, 'pricing.edit', 10);
select app.register_field('task_pricing', 'is_manual', 'מחיר ידני', 'pricing',
  'task_pricing', 'is_manual', true, false, false, 'pricing.edit', 20);
select app.register_field('task_pricing', 'breakdown', 'פירוט החישוב', 'pricing',
  'task_pricing', 'breakdown', true, false, false, 'pricing.edit', 30);
select app.register_field('customer', 'pricing_mode', 'אופן תמחור', 'pricing',
  'customers', 'pricing_mode', false, true, false, 'pricing.manage_rules', 40);
select app.register_field('task', 'travel_hours', 'זמן נסיעה', 'pricing',
  'tasks', 'travel_hours', false, true, false, 'pricing.edit', 50);
select app.register_field('task', 'requires_team_lead', 'נדרש ראש צוות', 'pricing',
  'tasks', 'requires_team_lead', false, true, true, null, 60);

-- ===== 5. RLS ==============================================================

alter table pricing_zones enable row level security;
alter table customer_pricing_rules enable row level security;
alter table task_pricing enable row level security;

-- אין ענף contractor_user באף אחת מהפוליסות שלמטה. זו הנקודה.

create policy pz_select on pricing_zones for select to authenticated using (
  (select app.is_admin())
  or ((select app.user_kind()) = 'staff'
      and ((select app.has('pricing.manage_rules')) or (select app.has('pricing.view')))));
create policy pz_write on pricing_zones for all to authenticated
  using ((select app.is_admin()) or (select app.has('pricing.manage_rules')))
  with check ((select app.is_admin()) or (select app.has('pricing.manage_rules')));

create policy cpr_select on customer_pricing_rules for select to authenticated using (
  (select app.is_admin())
  or ((select app.user_kind()) = 'staff'
      and ((select app.has('pricing.manage_rules')) or (select app.has('pricing.view')))));
create policy cpr_write on customer_pricing_rules for all to authenticated
  using ((select app.is_admin()) or (select app.has('pricing.manage_rules')))
  with check ((select app.is_admin()) or (select app.has('pricing.manage_rules')));

-- הלקוח רואה את המחיר של המשימות שלו בלבד, ורק אם ניתן לו המפתח.
create policy tp_select on task_pricing for select to authenticated using (
  (select app.is_admin())
  or ((select app.user_kind()) = 'staff' and (select app.has('pricing.view')))
  or ((select app.user_kind()) = 'customer_user' and (select app.has('pricing.view'))
      and exists (select 1 from tasks t
                   where t.id = task_pricing.task_id
                     and t.customer_id = (select app.customer_id())
                     and t.deleted_at is null)));

create policy tp_write on task_pricing for all to authenticated
  using ((select app.is_admin()) or (select app.has('pricing.edit')))
  with check ((select app.is_admin()) or (select app.has('pricing.edit')));

do $$
declare t text;
begin
  foreach t in array array['pricing_zones', 'customer_pricing_rules', 'task_pricing']
  loop
    execute format(
      'create trigger %I_audit after insert or update or delete on %I
         for each row execute function app.audit()', t, t);
  end loop;
end $$;

create trigger task_pricing_field_perms before update on task_pricing
  for each row execute function app.enforce_field_perms();

-- ===== 6. גאומטריה =========================================================
-- Ray casting. הקואורדינטות נשמרות [lat, lng] — הסדר שבו events.location_lat
-- ו-location_lng כבר יושבים ושבו Leaflet עובד — ולכן lat הוא ציר ה-y.

create or replace function app.point_in_polygon(
  p_lat double precision, p_lng double precision, p_points jsonb)
returns boolean language plpgsql immutable as $$
declare
  n int; i int; j int;
  xi double precision; yi double precision;
  xj double precision; yj double precision;
  inside boolean := false;
begin
  if p_lat is null or p_lng is null
     or p_points is null or jsonb_typeof(p_points) <> 'array' then
    return false;
  end if;
  n := jsonb_array_length(p_points);
  if n < 3 then return false; end if;

  j := n - 1;
  for i in 0 .. n - 1 loop
    yi := (p_points -> i ->> 0)::double precision;
    xi := (p_points -> i ->> 1)::double precision;
    yj := (p_points -> j ->> 0)::double precision;
    xj := (p_points -> j ->> 1)::double precision;
    if (yi > p_lat) <> (yj > p_lat) then
      if yj <> yi and p_lng < (xj - xi) * (p_lat - yi) / (yj - yi) + xi then
        inside := not inside;
      end if;
    end if;
    j := i;
  end loop;
  return inside;
end $$;

create or replace function app.haversine_km(
  p_lat1 double precision, p_lng1 double precision,
  p_lat2 double precision, p_lng2 double precision)
returns double precision language sql immutable as $$
  select 6371 * 2 * asin(least(1, sqrt(
    power(sin(radians(p_lat2 - p_lat1) / 2), 2)
    + cos(radians(p_lat1)) * cos(radians(p_lat2))
      * power(sin(radians(p_lng2 - p_lng1) / 2), 2))))
$$;

-- האזור התקף לנקודה: אזור של הלקוח גובר על אזור גלובלי, ובתוך אותה רמה
-- priority נמוך גובר — כך שאזור קטן שיושב בתוך אזור גדול מנצח אותו.
create or replace function app.zone_for_point(
  p_customer_id uuid, p_lat double precision, p_lng double precision)
returns pricing_zones language sql stable security definer set search_path = public as $$
  select z.* from pricing_zones z
  where z.is_active and z.deleted_at is null
    and (z.customer_id = p_customer_id or z.customer_id is null)
    and case z.shape
          when 'polygon' then app.point_in_polygon(p_lat, p_lng, z.points)
          when 'circle'  then p_lat is not null and p_lng is not null
                              and app.haversine_km(p_lat, p_lng, z.center_lat, z.center_lng)
                                  <= z.radius_km::double precision
          else false
        end
  order by (z.customer_id is null), z.priority, z.name
  limit 1
$$;

-- ===== 7. מנוע החישוב ======================================================
-- app.price_calc היא פונקציה טהורה: היא לא נוגעת בשום טבלה, מקבלת את
-- הקונפיג ואת המשתנים ומחזירה סכום ופירוט. זה מה שמאפשר גם לחשב מחיר אמיתי
-- וגם להריץ תצוגה מקדימה חיה בבונה מאותו קוד בדיוק, בלי לשכפל אותו ב-TypeScript.

create or replace function app.jnum(j jsonb, k text, d numeric default 0)
returns numeric language sql immutable as $$
  select case when j ? k and jsonb_typeof(j -> k) in ('number', 'string')
                   and nullif(j ->> k, '') is not null
              then (j ->> k)::numeric else d end
$$;

create or replace function app.price_var_num(vars jsonb, k text)
returns numeric language sql immutable as $$
  select case when k is null or vars is null then 0
              when jsonb_typeof(vars -> k) = 'number' then (vars ->> k)::numeric
              when jsonb_typeof(vars -> k) = 'string' and nullif(vars ->> k, '') is not null
                then (vars ->> k)::numeric
              when jsonb_typeof(vars -> k) = 'boolean'
                then case when (vars ->> k)::boolean then 1 else 0 end
              else 0 end
$$;

-- טסט בודד: {"field":"volume_m","op":"gte","value":30}
-- קבוצה: {"all":[...]} או {"any":[...]}. NULL או ריק = תמיד אמת.
create or replace function app.price_cond(cond jsonb, vars jsonb)
returns boolean language plpgsql immutable as $$
declare
  item jsonb;
  v_field text;
  v_op text;
  v_raw text;
  v_num numeric;
  v_val jsonb;
begin
  if cond is null or cond = 'null'::jsonb or cond = '{}'::jsonb then return true; end if;

  if cond ? 'all' then
    for item in select * from jsonb_array_elements(cond -> 'all') loop
      if not app.price_cond(item, vars) then return false; end if;
    end loop;
    return true;
  end if;

  if cond ? 'any' then
    if jsonb_array_length(cond -> 'any') = 0 then return true; end if;
    for item in select * from jsonb_array_elements(cond -> 'any') loop
      if app.price_cond(item, vars) then return true; end if;
    end loop;
    return false;
  end if;

  v_field := cond ->> 'field';
  v_op    := coalesce(cond ->> 'op', 'is_true');
  if v_field is null then return true; end if;

  v_raw := vars ->> v_field;
  v_val := cond -> 'value';

  case v_op
    when 'is_true'  then return coalesce(v_raw, 'false') in ('true', 't', '1');
    when 'is_false' then return coalesce(v_raw, 'false') not in ('true', 't', '1');
    when 'eq'       then return v_raw is not distinct from (v_val #>> '{}');
    when 'ne'       then return v_raw is distinct from (v_val #>> '{}');
    when 'in'       then return v_val is not null and jsonb_typeof(v_val) = 'array'
                            and exists (select 1 from jsonb_array_elements(v_val) e
                                        where (e #>> '{}') = v_raw);
    when 'not_in'   then return v_val is null or jsonb_typeof(v_val) <> 'array'
                            or not exists (select 1 from jsonb_array_elements(v_val) e
                                           where (e #>> '{}') = v_raw);
    else
      v_num := app.price_var_num(vars, v_field);
      case v_op
        when 'gt'  then return v_num >  app.jnum(cond, 'value', 0);
        when 'gte' then return v_num >= app.jnum(cond, 'value', 0);
        when 'lt'  then return v_num <  app.jnum(cond, 'value', 0);
        when 'lte' then return v_num <= app.jnum(cond, 'value', 0);
        when 'between' then
          return jsonb_typeof(v_val) = 'array' and jsonb_array_length(v_val) = 2
             and v_num >= (v_val ->> 0)::numeric and v_num <= (v_val ->> 1)::numeric;
        else return true;
      end case;
  end case;
end $$;

-- שני מודלים, כי לתמחור אירועים יש שתי צורות שונות באמת ואי אפשר לכופף
-- אחת לתוך השנייה בלי שהיא תיראה כמו תרגיל:
--
--   worker_hours — סכום רכיבי זמן ⇒ שעות, כפול תעריף ⇒ מחיר לעובד, כפול
--                  כמות עובדים ⇒ סכום, ואז תוספות ומקדמים. זו הצורה של
--                  הקמה/פירוק: המחיר הוא בעצם שכר עבודה עם מקדם.
--
--   line_items   — סכום שורות בלתי תלויות: בסיס, תעריף ליחידה, מדרגות,
--                  תוספות מותנות. זה כרטיס תעריפים רגיל, ללקוח שמתמחר לפי
--                  קוב או לפי משאית ולא לפי אנשים.
--
-- שניהם חולקים את הזנב — מקדמים, הנחה, מינימום/מקסימום ועיגול — ואת מבנה
-- הפלט, כך שכל מי שקורא את התוצאה לא צריך לדעת באיזה מודל מדובר.
create or replace function app.price_calc(config jsonb, vars jsonb)
returns jsonb language plpgsql immutable as $$
declare
  v_model        text;
  v_vars         jsonb;
  c              jsonb;
  t              jsonb;
  v_hour_lines   jsonb := '[]'::jsonb;
  v_lines        jsonb := '[]'::jsonb;
  v_hours        numeric := 0;
  v_h            numeric;
  v_n            numeric;
  v_rate         numeric;
  v_per_worker   numeric := 0;
  v_base_workers numeric := 0;
  v_workers      numeric := 0;
  v_total        numeric := 0;
  v_subtotal     numeric := 0;
  v_amt          numeric;
  v_prev         numeric;
  v_units        numeric;
  v_remaining    numeric;
  v_cap          numeric;
  v_slice        numeric;
  v_label        text;
  v_step         numeric;
begin
  if config is null then config := '{}'::jsonb; end if;
  -- קבועי המחשבון (הפסקה, ספייר, "נדרש ראש צוות") משמשים כרצפה: משתנה
  -- אמיתי שהגיע מהמשימה גובר עליהם, ולכן דריסה נקודתית באירוע חריג עובדת
  -- בלי לגעת בהגדרות הלקוח.
  v_vars := coalesce(config -> 'constants', '{}'::jsonb) || coalesce(vars, '{}'::jsonb);
  v_model := coalesce(config ->> 'model', 'line_items');

  if v_model = 'worker_hours' then
    -- ── רכיבי הזמן ⇒ שעות ────────────────────────────────────────────────
    for c in select * from jsonb_array_elements(coalesce(config -> 'hours', '[]'::jsonb)) loop
      if coalesce((c ->> 'enabled')::boolean, true) and app.price_cond(c -> 'when', v_vars) then
        case coalesce(c ->> 'kind', 'const')
          when 'const' then
            v_h := app.jnum(c, 'hours', 0);
          when 'input' then
            v_h := app.price_var_num(v_vars, c ->> 'input') * app.jnum(c, 'multiplier', 1);
          when 'stepped' then
            -- "משאית אחת זה שעה, כל משאית נוספת עוד חצי שעה"
            v_n := app.price_var_num(v_vars, c ->> 'input');
            v_h := case when v_n <= 0 then 0
                        else app.jnum(c, 'first', 0)
                             + (v_n - 1) * app.jnum(c, 'each_additional', 0) end;
          else
            v_h := 0;
        end case;

        if v_h <> 0 then
          v_hours := v_hours + v_h;
          v_hour_lines := v_hour_lines || jsonb_build_object(
            'id', c ->> 'id', 'label', c ->> 'label', 'hours', round(v_h, 2));
        end if;
      end if;
    end loop;

    -- ── מחיר לעובד ───────────────────────────────────────────────────────
    v_rate := app.jnum(config, 'hour_rate', 0);
    v_per_worker := v_hours * v_rate + app.jnum(config, 'per_worker_fee', 0);

    -- ── כמות עובדים, כולל תוספות כמו "אין חניה ⇒ עובד נוסף" ─────────────
    v_base_workers := app.price_var_num(
      v_vars, coalesce(config -> 'workers' ->> 'input', 'worker_count'));
    v_workers := v_base_workers;
    for c in select * from jsonb_array_elements(
                 coalesce(config -> 'workers' -> 'adjustments', '[]'::jsonb)) loop
      if app.price_cond(c -> 'when', v_vars) then
        v_workers := v_workers + app.jnum(c, 'add', 0);
        v_lines := v_lines || jsonb_build_object(
          'id', c ->> 'id', 'label', c ->> 'label', 'amount', null,
          'detail', format('%s עובדים', trim_scale(app.jnum(c, 'add', 0))));
      end if;
    end loop;
    if v_workers < 0 then v_workers := 0; end if;

    v_total := v_workers * v_per_worker;
    v_lines := v_lines || jsonb_build_object(
      'id', 'labour', 'label', 'עבודה',
      'amount', round(v_total, 2),
      'detail', format('%s ש׳ × %s₪ + %s₪ = %s₪ לעובד × %s עובדים',
                       trim_scale(round(v_hours, 2)), trim_scale(v_rate),
                       trim_scale(app.jnum(config, 'per_worker_fee', 0)),
                       trim_scale(round(v_per_worker, 2)), trim_scale(v_workers)));

    -- ── תוספות אחרי ההכפלה בעובדים ──────────────────────────────────────
    for c in select * from jsonb_array_elements(
                 coalesce(config -> 'after_workers', '[]'::jsonb)) loop
      if app.price_cond(c -> 'when', v_vars) then
        case coalesce(c ->> 'kind', 'fixed')
          when 'fixed' then
            v_amt := app.jnum(c, 'amount', 0);
            v_label := null;
          when 'per_worker' then
            -- workers_basis מבדיל בין "לכל עובד שיוצא לשטח" לבין "לכל עובד
            -- שהוזמן". סבלות, למשל, נספרת לפי המקוריים ולא כוללת את העובד
            -- שנוסף בגלל היעדר חניה.
            v_n := case when coalesce(c ->> 'workers_basis', 'effective') = 'base'
                        then v_base_workers else v_workers end;
            v_amt := app.jnum(c, 'amount', 0) * v_n;
            v_label := format('%s₪ × %s עובדים',
                              trim_scale(app.jnum(c, 'amount', 0)), trim_scale(v_n));
          when 'percent' then
            v_amt := v_total * app.jnum(c, 'amount', 0) / 100;
            v_label := format('%s%% מ-%s₪',
                              trim_scale(app.jnum(c, 'amount', 0)), trim_scale(round(v_total, 2)));
          when 'var' then
            -- סכום שמגיע מהנתונים ולא מההגדרה — למשל תוספת האזור הגאוגרפי
            v_amt := app.price_var_num(v_vars, c ->> 'input') * app.jnum(c, 'multiplier', 1);
            v_label := c ->> 'input';
          else
            v_amt := 0; v_label := null;
        end case;

        if v_amt <> 0 then
          v_total := v_total + v_amt;
          v_lines := v_lines || jsonb_build_object(
            'id', c ->> 'id', 'label', c ->> 'label',
            'amount', round(v_amt, 2), 'detail', v_label);
        end if;
      end if;
    end loop;

  else
    -- ── line_items: כרטיס תעריפים ────────────────────────────────────────
    for c in select * from jsonb_array_elements(coalesce(config -> 'components', '[]'::jsonb)) loop
      if coalesce((c ->> 'enabled')::boolean, true) and app.price_cond(c -> 'when', v_vars) then
        v_label := null;
        case coalesce(c ->> 'kind', 'fixed')
          when 'fixed' then
            v_amt := app.jnum(c, 'amount', 0);

          when 'per_unit' then
            v_units := app.price_var_num(v_vars, c ->> 'input')
                       - app.jnum(c, 'included_units', 0);
            if v_units < 0 then v_units := 0; end if;
            if c ? 'min_units' and v_units < app.jnum(c, 'min_units', 0) then
              v_units := app.jnum(c, 'min_units', 0);
            end if;
            if c ? 'max_units' and v_units > app.jnum(c, 'max_units', 0) then
              v_units := app.jnum(c, 'max_units', 0);
            end if;
            v_amt := v_units * app.jnum(c, 'rate', 0);
            v_label := format('%s × %s₪', trim_scale(v_units), trim_scale(app.jnum(c, 'rate', 0)));

          when 'tiered' then
            v_units := app.price_var_num(v_vars, c ->> 'input');
            v_amt := 0;
            if coalesce(c ->> 'mode', 'flat') = 'flat' then
              -- המדרגה שהכמות נופלת בתוכה קובעת מחיר אחד
              for t in select * from jsonb_array_elements(coalesce(c -> 'tiers', '[]'::jsonb)) loop
                if v_amt = 0 then
                  if t -> 'up_to' is null or jsonb_typeof(t -> 'up_to') = 'null'
                     or v_units <= app.jnum(t, 'up_to', 0) then
                    v_amt := app.jnum(t, 'amount', 0);
                    v_label := format('עד %s', coalesce(t ->> 'up_to', '∞'));
                    exit;
                  end if;
                end if;
              end loop;
            else
              -- פרוסות: כל מדרגה מתומחרת על החלק שלה בלבד
              v_prev := 0;
              v_remaining := v_units;
              for t in select * from jsonb_array_elements(coalesce(c -> 'tiers', '[]'::jsonb)) loop
                exit when v_remaining <= 0;
                v_cap := case when t -> 'up_to' is null or jsonb_typeof(t -> 'up_to') = 'null'
                              then v_units else app.jnum(t, 'up_to', 0) end;
                v_slice := least(v_remaining, greatest(v_cap - v_prev, 0));
                v_amt := v_amt + v_slice * app.jnum(t, 'rate', 0);
                v_remaining := v_remaining - v_slice;
                v_prev := v_cap;
              end loop;
              v_label := format('%s יחידות מדורגות', trim_scale(v_units));
            end if;

          when 'surcharge' then
            if coalesce(c ->> 'amount_kind', 'fixed') = 'percent' then
              v_amt := v_total * app.jnum(c, 'amount', 0) / 100;
              v_label := format('%s%%', trim_scale(app.jnum(c, 'amount', 0)));
            else
              v_amt := app.jnum(c, 'amount', 0);
            end if;

          when 'var' then
            v_amt := app.price_var_num(v_vars, c ->> 'input') * app.jnum(c, 'multiplier', 1);
            v_label := c ->> 'input';

          else
            v_amt := 0;
        end case;

        if v_amt <> 0 then
          v_total := v_total + v_amt;
          v_lines := v_lines || jsonb_build_object(
            'id', c ->> 'id', 'label', c ->> 'label',
            'amount', round(v_amt, 2), 'detail', v_label);
        end if;
      end if;
    end loop;
  end if;

  -- ── זנב משותף לשני המודלים ─────────────────────────────────────────────
  v_subtotal := v_total;

  -- מקדמים מוכפלים בזה אחר זה (1.3 ואז 1.2 אינו 1.5), וכל אחד נרשם בפירוט
  -- כתוספת ולא כמכפלה, כדי שסכום השורות ישווה תמיד לסך הכול.
  for c in select * from jsonb_array_elements(coalesce(config -> 'multipliers', '[]'::jsonb)) loop
    if coalesce((c ->> 'enabled')::boolean, true) and app.price_cond(c -> 'when', v_vars) then
      v_step := app.jnum(c, 'factor', 1);
      v_amt := v_total * (v_step - 1);
      if v_amt <> 0 then
        v_total := v_total + v_amt;
        v_lines := v_lines || jsonb_build_object(
          'id', c ->> 'id', 'label', coalesce(c ->> 'label', format('מקדם ×%s', trim_scale(v_step))),
          'amount', round(v_amt, 2), 'detail', format('×%s', trim_scale(v_step)));
      end if;
    end if;
  end loop;

  if config ? 'discount' and jsonb_typeof(config -> 'discount') = 'object' then
    c := config -> 'discount';
    v_amt := case when coalesce(c ->> 'kind', 'percent') = 'percent'
                  then -v_total * app.jnum(c, 'amount', 0) / 100
                  else -app.jnum(c, 'amount', 0) end;
    if v_amt <> 0 then
      v_total := v_total + v_amt;
      v_lines := v_lines || jsonb_build_object(
        'id', 'discount', 'label', coalesce(c ->> 'label', 'הנחה'),
        'amount', round(v_amt, 2), 'detail', null);
    end if;
  end if;

  if config ? 'min_price' and jsonb_typeof(config -> 'min_price') = 'number'
     and v_total < app.jnum(config, 'min_price', 0) then
    v_amt := app.jnum(config, 'min_price', 0) - v_total;
    v_total := app.jnum(config, 'min_price', 0);
    v_lines := v_lines || jsonb_build_object(
      'id', 'min_price', 'label', 'השלמה למינימום',
      'amount', round(v_amt, 2), 'detail', null);
  end if;
  if config ? 'max_price' and jsonb_typeof(config -> 'max_price') = 'number'
     and v_total > app.jnum(config, 'max_price', 0) then
    v_amt := app.jnum(config, 'max_price', 0) - v_total;
    v_total := app.jnum(config, 'max_price', 0);
    v_lines := v_lines || jsonb_build_object(
      'id', 'max_price', 'label', 'הפחתה למקסימום',
      'amount', round(v_amt, 2), 'detail', null);
  end if;

  v_step := app.jnum(config -> 'rounding', 'to', 0);
  if v_step > 0 then
    v_total := case coalesce(config -> 'rounding' ->> 'mode', 'nearest')
                 when 'up'   then ceil(v_total / v_step) * v_step
                 when 'down' then floor(v_total / v_step) * v_step
                 else round(v_total / v_step) * v_step
               end;
  end if;

  return jsonb_build_object(
    'version', 1,
    'model', v_model,
    'total', round(v_total, 2),
    'subtotal', round(v_subtotal, 2),
    'hours', round(v_hours, 2),
    'per_worker', round(v_per_worker, 2),
    'base_workers', trim_scale(v_base_workers),
    'workers', trim_scale(v_workers),
    'hour_lines', v_hour_lines,
    'lines', v_lines);
end $$;

-- ===== 8. משתני החישוב ======================================================
-- מאחדת משימה, אירוע ואזור לאובייקט אחד שהמנוע יודע לקרוא. jsonb_strip_nulls
-- בסוף אינו קוסמטיקה: הוא מה שגורם לקבועי המחשבון לתפוס. משתנה שאין לו ערך
-- נעלם מהאובייקט, ולכן ה-|| מול config.constants לא דורס קבוע ב-NULL.

create or replace function app.pricing_vars(p_task_id uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  t        tasks;
  e        events;
  z        pricing_zones;
  v_code   text;
  v_method text;
  v_travel numeric;
begin
  select * into t from tasks where id = p_task_id;
  if t.id is null then return '{}'::jsonb; end if;

  select * into e from events where id = t.event_id;
  select code into v_code   from task_types       where id = t.task_type_id;
  select name into v_method from execution_methods where id = t.execution_method_id;

  -- זמן נסיעה: דריסה על המשימה גוברת, אחרת האזור שמיקום האירוע נופל בתוכו.
  v_travel := t.travel_hours;
  if e.location_lat is not null and e.location_lng is not null then
    z := app.zone_for_point(t.customer_id, e.location_lat, e.location_lng);
  end if;
  if v_travel is null then v_travel := z.travel_hours; end if;

  return jsonb_strip_nulls(jsonb_build_object(
    'task_type_code',      v_code,
    'worker_count',        t.worker_count,
    'hours_count',         t.hours_count,
    'worker_hours',        coalesce(t.hours_count, 0) * coalesce(t.worker_count, 0),
    'task_date',           t.task_date,
    'dow',                 extract(dow from t.task_date),
    'is_weekend',          extract(dow from t.task_date) in (5, 6),
    'start_hour',          extract(hour from t.onsite_start_time),
    'has_truck',           t.truck_id is not null,
    'execution_method_id', t.execution_method_id,
    'execution_method',    v_method,
    'travel_hours',        v_travel,
    'requires_team_lead',  t.requires_team_lead,
    'zone_name',           z.name,
    'zone_surcharge',      z.surcharge,
    'volume_m',            e.volume_m,
    'truck_count',         e.truck_count,
    'no_parking',          e.no_parking,
    'porterage',           e.porterage,
    'supplier_pickup',     e.supplier_pickup,
    'event_date',          e.event_date,
    'customer_id',         t.customer_id));
end $$;

-- ===== 9. חישוב מחדש ונעילה ידנית ==========================================

create or replace function app.recalc_task_price(p_task_id uuid, p_force boolean default false)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  t          tasks;
  v_existing task_pricing;
  v_mode     text;
  v_config   jsonb;
  v_result   jsonb;
  v_prev     boolean;
begin
  select * into t from tasks where id = p_task_id;
  if t.id is null or t.deleted_at is not null then return null; end if;

  -- מחיר שנערך ידנית הוא החלטה של אדם. חישוב אוטומטי לא דורס אותה; רק
  -- "חשב מחדש" מפורש (p_force) עושה זאת.
  select * into v_existing from task_pricing where task_id = p_task_id;
  if v_existing.task_id is not null and v_existing.is_manual and not p_force then
    return null;
  end if;

  select pricing_mode into v_mode from customers where id = t.customer_id;
  if coalesce(v_mode, 'manual') <> 'auto' then return null; end if;

  select config into v_config from customer_pricing_rules
   where customer_id = t.customer_id and task_type_id = t.task_type_id and is_active;
  -- אין מחשבון לסוג המשימה הזה — משאירים מה שיש. השבתת מחשבון לא אמורה
  -- לאפס מחירים שכבר חושבו.
  if v_config is null then return null; end if;

  v_result := app.price_calc(v_config, app.pricing_vars(p_task_id));

  -- שומר ומשחזר במקום לכבות. הפונקציה הזו נקראת מתוך טריגר על tasks, וטריגר
  -- כזה יורה גם באמצע create_event — שעוטף את שתי כתיבות הסקשן ב-system_write
  -- אחד משותף. כיבוי עיוור כאן היה מסיר את הדגל מהכתיבה של הפירוק, ואז
  -- enforce_field_perms היה חוסם ללקוח את חצי הטופס השני.
  v_prev := app.in_system_write();
  perform app.system_write(true);
  insert into task_pricing (task_id, price, is_manual, breakdown, calculated_at)
  values (p_task_id, (v_result ->> 'total')::numeric, false, v_result, now())
  on conflict (task_id) do update
    set price         = excluded.price,
        is_manual     = false,
        breakdown     = excluded.breakdown,
        calculated_at = excluded.calculated_at;
  perform app.system_write(v_prev);

  return v_result;
end $$;

-- כל כתיבה של אדם על המחיר נועלת אותו. הכתיבות של המנוע עטופות ב-system_write
-- ולכן אינן נועלות — זה ההבדל היחיד בין השתיים, ולכן הוא נבדק כאן ולא מחוץ
-- לטבלה, במקום שאי אפשר לעקוף.
create or replace function app.task_pricing_lock()
returns trigger language plpgsql set search_path = public as $$
begin
  if not app.in_system_write() and auth.uid() is not null then
    if tg_op = 'INSERT' or new.price is distinct from old.price then
      new.is_manual := true;
      new.breakdown := null;
    end if;
  end if;
  return new;
end $$;

create trigger task_pricing_lock before insert or update on task_pricing
  for each row execute function app.task_pricing_lock();

-- ===== 10. טריגרי חישוב מחדש ===============================================
-- כולם כותבים ל-task_pricing בלבד, ועליה יושב רק טריגר הנעילה — שאינו קורא
-- לחישוב. משום כך אין כאן רקורסיה, וזו סיבה נוספת לכך שהמחיר יושב בטבלה
-- נפרדת ולא בעמודה על tasks.

create or replace function app.tasks_recalc_price()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  perform app.recalc_task_price(new.id);
  return null;
end $$;

create trigger tasks_price after insert or update of
    task_type_id, worker_count, hours_count, task_date, onsite_start_time,
    execution_method_id, truck_id, customer_id, event_id, travel_hours, requires_team_lead
  on tasks for each row execute function app.tasks_recalc_price();

create or replace function app.events_recalc_prices()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  perform app.recalc_task_price(t.id)
    from tasks t where t.event_id = new.id and t.deleted_at is null;
  return null;
end $$;

create trigger events_price after update of
    volume_m, truck_count, no_parking, porterage, supplier_pickup,
    event_date, customer_id, location_lat, location_lng
  on events for each row execute function app.events_recalc_prices();

-- שינוי במחשבון או במפת האזורים נוגע רק באירועים שעוד לא היו. אירוע שעבר
-- כבר עשוי להיות מחויב, ושכתוב שקט שלו הוא לא תיקון אלא הפתעה. מי שכן רוצה
-- לשכתב היסטוריה עושה זאת מפורשות דרך recalculate_customer_prices.
create or replace function app.pricing_rule_recalc()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_customer uuid; v_type uuid;
begin
  if tg_op = 'DELETE' then
    v_customer := old.customer_id; v_type := old.task_type_id;
  else
    v_customer := new.customer_id; v_type := new.task_type_id;
  end if;
  perform app.recalc_task_price(t.id)
    from tasks t
   where t.customer_id = v_customer and t.task_type_id = v_type
     and t.deleted_at is null and t.task_date >= current_date;
  return null;
end $$;

create trigger customer_pricing_rules_recalc
  after insert or update or delete on customer_pricing_rules
  for each row execute function app.pricing_rule_recalc();

create or replace function app.customer_recalc_prices()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  perform app.recalc_task_price(t.id)
    from tasks t
   where t.customer_id = new.id and t.deleted_at is null and t.task_date >= current_date;
  return null;
end $$;

create trigger customers_pricing_mode after update of pricing_mode on customers
  for each row when (old.pricing_mode is distinct from new.pricing_mode)
  execute function app.customer_recalc_prices();

create or replace function app.zone_recalc_prices()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_customer uuid;
begin
  v_customer := case when tg_op = 'DELETE' then old.customer_id else new.customer_id end;
  perform app.recalc_task_price(t.id)
    from tasks t
   where t.deleted_at is null and t.task_date >= current_date
     and (v_customer is null or t.customer_id = v_customer);
  return null;
end $$;

create trigger pricing_zones_recalc after insert or update or delete on pricing_zones
  for each row execute function app.zone_recalc_prices();

-- ===== 11. RPCs ============================================================

-- הבונה במסך הלקוח מריץ את החישוב האמיתי על נתוני דוגמה. אין כאן העתק של
-- המנוע ב-TypeScript, ולכן אין שתי אמיתות שיכולות להיפרד זו מזו.
create or replace function preview_task_price(p_config jsonb, p_vars jsonb)
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  perform app.require('pricing.manage_rules');
  return app.price_calc(p_config, coalesce(p_vars, '{}'::jsonb));
end $$;

create or replace function recalculate_task_price(p_task_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_result jsonb;
begin
  perform app.require('pricing.edit');
  v_result := app.recalc_task_price(p_task_id, true);
  if v_result is null then
    raise exception 'אין מחשבון תמחור פעיל ללקוח ולסוג המשימה הזה' using errcode = 'P0002';
  end if;
  return v_result;
end $$;

-- שכתוב יזום, כולל אירועי עבר אם ביקשו במפורש.
create or replace function recalculate_customer_prices(
  p_customer_id uuid, p_from date default current_date)
returns int language plpgsql security definer set search_path = public as $$
declare v_count int := 0; r record;
begin
  perform app.require('pricing.manage_rules');
  for r in select t.id from tasks t
            where t.customer_id = p_customer_id and t.deleted_at is null
              and (p_from is null or t.task_date >= p_from)
  loop
    if app.recalc_task_price(r.id, true) is not null then v_count := v_count + 1; end if;
  end loop;
  return v_count;
end $$;

-- מאפשר לטופס האירוע להראות "אזור: השרון · 0.75 ש׳ נסיעה" ברגע שנבחרה כתובת.
create or replace function zone_for_location(
  p_customer_id uuid, p_lat double precision, p_lng double precision)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare z pricing_zones;
begin
  perform app.require('pricing.view');
  z := app.zone_for_point(p_customer_id, p_lat, p_lng);
  if z.id is null then return null; end if;
  return jsonb_build_object(
    'id', z.id, 'name', z.name, 'color', z.color,
    'travel_hours', z.travel_hours, 'surcharge', z.surcharge);
end $$;

-- ===== 12. חשיפה בקריאה ====================================================
-- work_board_view הוא נתיב הקריאה היחיד ללוח, לדף האירוע, לפורטל הקבלן
-- ולדשבורד, ולכן המחיר נכנס דרכו. create or replace view מתיר להוסיף עמודות
-- רק בסוף — הרשימה שלמעלה מועתקת מ-0012 כלשונה בכוונה.
--
-- ה-case מיותר מבחינה טכנית: ה-RLS על task_pricing כבר חוסם את ה-join
-- (security_invoker = true), והקבלן לא יקבל שורה גם בלעדיו. הוא כאן כדי
-- שמי שקורא את ההגדרה יראה את הכוונה ולא יסיק שהמחיר פתוח לכולם.
create or replace view work_board_view
with (security_invoker = true) as
select
  t.id,
  t.event_id,
  t.customer_id,
  c.name  as customer_name,
  c.color as customer_color,
  e.end_client_name,
  e.event_number,
  case when (select app.can_view_field('task', 'location_text'))
    then coalesce(t.location_text, e.location_text) end as location_text,
  e.volume_m,
  e.truck_count as event_truck_count,
  t.task_type_id,
  tt.name as task_type_name,
  tt.code as task_type_code,
  t.title,
  t.task_date,
  t.warehouse_start_time,
  t.onsite_start_time,
  t.onsite_end_time,
  t.hours_count,
  t.worker_count,
  t.execution_method_id,
  em.name as execution_method_name,
  t.truck_id,
  case when (select app.can_view_field('task', 'truck_id')) then tr.name end as truck_name,
  case when (select app.can_view_field('task', 'truck_free_text')) then t.truck_free_text end as truck_free_text,
  case when (select app.can_view_field('task', 'notes')) then t.notes end as notes,
  t.status_id,
  s.name  as status_name,
  s.color as status_color,
  s.is_terminal as status_is_terminal,
  t.contractor_id,
  case when (select app.has('contractors.view')) then ct.name end as contractor_name,
  t.created_at,
  t.updated_at,
  lead_p.full_name as team_lead_name,
  lead_a.profile_id as team_lead_id,
  workers.list  as workers,
  drivers.list  as drivers,
  cworkers.list as contractor_worker_list,
  case when (select app.has('pricing.view')) then tp.price end as customer_price,
  case when (select app.has('pricing.view')) then tp.is_manual end as price_is_manual,
  case when (select app.has('pricing.view')) then tp.breakdown end as price_breakdown,
  t.travel_hours,
  t.requires_team_lead
from tasks t
left join events e     on e.id = t.event_id
left join customers c  on c.id = t.customer_id
join task_types tt     on tt.id = t.task_type_id
left join execution_methods em on em.id = t.execution_method_id
left join trucks tr    on tr.id = t.truck_id
join statuses s        on s.id = t.status_id
left join contractors ct on ct.id = t.contractor_id
left join task_pricing tp on tp.task_id = t.id
left join lateral (
  select a.profile_id from task_assignments a
  where a.task_id = t.id and a.role = 'team_lead' limit 1
) lead_a on true
left join profiles lead_p on lead_p.id = lead_a.profile_id
left join lateral (
  select jsonb_agg(jsonb_build_object('profile_id', a.profile_id, 'name', p.full_name)
                   order by p.full_name) as list
  from task_assignments a join profiles p on p.id = a.profile_id
  where a.task_id = t.id and a.role = 'worker'
) workers on true
left join lateral (
  select jsonb_agg(jsonb_build_object('profile_id', a.profile_id, 'name', p.full_name,
                                      'truck_id', a.truck_id, 'truck_name', tr2.name)
                   order by p.full_name) as list
  from task_assignments a
  join profiles p on p.id = a.profile_id
  left join trucks tr2 on tr2.id = a.truck_id
  where a.task_id = t.id and a.role = 'driver'
) drivers on true
left join lateral (
  select jsonb_agg(jsonb_build_object('id', cw.id, 'name', cw.full_name)
                   order by cw.full_name) as list
  from task_contractor_workers tcw join contractor_workers cw on cw.id = tcw.contractor_worker_id
  where tcw.task_id = t.id
) cworkers on true
where t.deleted_at is null;

select app.rebuild_secure_view('tasks');
select app.rebuild_secure_view('customers');

-- ===== 13. סיכומים כספיים ===================================================
-- 'financial' הקיים הוא מה שיוצא לקבלנים. 'revenue' הוא מה שנכנס מלקוחות,
-- ולכן הוא מפתח נפרד עם הרשאה נפרדת: מי שמנהל תשלומים לקבלנים לא בהכרח
-- אמור לראות כמה גובים.
create or replace function dashboard_stats(p_from date, p_to date)
returns jsonb language sql stable security invoker set search_path = public as $$
  select jsonb_build_object(
    'events_count', (select count(*) from events
       where deleted_at is null and event_date between p_from and p_to),
    'tasks_count', (select count(*) from tasks
       where deleted_at is null and task_date between p_from and p_to),
    'tasks_today', (select count(*) from tasks
       where deleted_at is null and task_date = current_date),
    'tasks_week', (select count(*) from tasks
       where deleted_at is null
         and task_date between date_trunc('week', current_date)::date
         and (date_trunc('week', current_date) + interval '6 days')::date),
    'tasks_overdue', (select count(*) from tasks t join statuses s on s.id = t.status_id
       where t.deleted_at is null and t.task_date < current_date and not s.is_terminal),
    'available_workers', (select count(*) from profiles p
       where p.deleted_at is null and p.is_active and p.user_kind = 'staff'
         and not exists (select 1 from task_assignments a join tasks t on t.id = a.task_id
                         where a.profile_id = p.id and t.task_date = current_date and t.deleted_at is null)),
    'by_customer', (select coalesce(jsonb_agg(row_to_json(x)), '[]') from (
       select c.name, c.color, count(*) as cnt from tasks t join customers c on c.id = t.customer_id
       where t.deleted_at is null and t.task_date between p_from and p_to
       group by c.name, c.color order by cnt desc limit 12) x),
    'by_contractor', (select coalesce(jsonb_agg(row_to_json(x)), '[]') from (
       select ct.name, count(*) as cnt from tasks t join contractors ct on ct.id = t.contractor_id
       where t.deleted_at is null and t.task_date between p_from and p_to
       group by ct.name order by cnt desc limit 12) x),
    'by_worker', case when app.has('dashboard.all_workers') then
      (select coalesce(jsonb_agg(row_to_json(x)), '[]') from (
         select p.full_name as name, count(*) as cnt
         from task_assignments a
         join tasks t on t.id = a.task_id and t.deleted_at is null
           and t.task_date between p_from and p_to
         join profiles p on p.id = a.profile_id
         group by p.full_name order by cnt desc limit 12) x)
      else '[]'::jsonb end,
    'financial', case when app.has('dashboard.financial') then
      (select jsonb_build_object(
         'expected', coalesce(sum(tct.price), 0),
         'paid', coalesce(sum(tct.paid_amount) filter (where tct.paid_at is not null), 0))
       from task_contractor_terms tct
       join tasks t on t.id = tct.task_id and t.deleted_at is null
        and t.task_date between p_from and p_to)
      else null end,
    'revenue', case when app.has('pricing.revenue') then
      (select jsonb_build_object(
         'total', coalesce(sum(tp.price), 0),
         'priced_tasks', count(*) filter (where tp.price is not null),
         'by_customer', (select coalesce(jsonb_agg(row_to_json(y)), '[]') from (
            select c.name, c.color, coalesce(sum(tp2.price), 0) as total
            from task_pricing tp2
            join tasks t2 on t2.id = tp2.task_id and t2.deleted_at is null
             and t2.task_date between p_from and p_to
            join customers c on c.id = t2.customer_id
            group by c.name, c.color order by 3 desc limit 12) y))
       from task_pricing tp
       join tasks t on t.id = tp.task_id and t.deleted_at is null
        and t.task_date between p_from and p_to)
      else null end,
    'by_status', (select coalesce(jsonb_agg(row_to_json(x)), '[]') from (
       select s.name, s.color, count(*) as cnt from tasks t join statuses s on s.id = t.status_id
       where t.deleted_at is null and t.task_date between p_from and p_to
       group by s.name, s.color order by cnt desc) x))
$$;

-- security invoker, ולכן ה-RLS של task_pricing כבר מצמצם את זה לאירועי הלקוח
-- עצמו; המפתח מחליט רק אם הוא רואה את השורה בכלל.
create or replace function customer_dashboard(p_from date default null, p_to date default null)
returns jsonb language sql stable security invoker set search_path = public as $$
  with my_events as (
    select e.*, s.is_terminal
    from events e
    left join statuses s on s.id = e.status_id
    where e.deleted_at is null
      and (p_from is null or e.event_date >= p_from)
      and (p_to   is null or e.event_date <= p_to)
  ),
  my_tasks as (
    select t.*, s.is_terminal, s.name as status_name, s.color as status_color
    from tasks t
    join statuses s on s.id = t.status_id
    where t.deleted_at is null
      and (p_from is null or t.task_date >= p_from)
      and (p_to   is null or t.task_date <= p_to)
  )
  select jsonb_build_object(
    'events_count',    (select count(*) from my_events),
    'events_upcoming', (select count(*) from my_events
                         where event_date >= current_date and not coalesce(is_terminal, false)),
    'events_done',     (select count(*) from my_events where coalesce(is_terminal, false)),
    'tasks_count',     (select count(*) from my_tasks),
    'tasks_open',      (select count(*) from my_tasks where not is_terminal),
    'pricing_total',   case when app.has('pricing.view')
                         then (select coalesce(sum(tp.price), 0) from task_pricing tp
                                join my_tasks mt on mt.id = tp.task_id)
                         else null end,
    'by_status',       (select coalesce(jsonb_agg(jsonb_build_object(
                                 'name', status_name, 'color', status_color, 'cnt', cnt)), '[]')
                          from (select status_name, status_color, count(*) as cnt
                                  from my_tasks group by status_name, status_color
                                 order by count(*) desc) q),
    'next_events',     (select coalesce(jsonb_agg(jsonb_build_object(
                                 'id', id, 'event_date', event_date,
                                 'end_client_name', end_client_name,
                                 'location_text', location_text)), '[]')
                          from (select * from my_events
                                 where event_date >= current_date
                                 order by event_date limit 5) q))
$$;

-- ===== 14. שדות המחיר בטופס האירוע =========================================

insert into form_fields (field_key, label_he, sort_order) values
  ('setup_price',    'הקמה — מחיר ללקוח',  22),
  ('teardown_price', 'פירוק — מחיר ללקוח', 23)
on conflict (field_key) do nothing;

-- app.seed_customer_defaults() רץ רק ללקוחות חדשים. שני השדות האלה נכנסים
-- מוסתרים ולא גלויים, בניגוד לברירת המחדל של 0009: מחיר אינו שדה שרוצים
-- שיופיע אצל כל לקוח קיים ברגע שהמיגרציה עוברת.
insert into customer_form_fields (customer_id, field_key, state)
select c.id, f.field_key, 'hidden'::field_state
from customers c cross join form_fields f
where f.field_key in ('setup_price', 'teardown_price')
on conflict do nothing;

-- מרחיב את 0009 בטיפול במפתח <code>_price. שאר הסמנטיקה נשמרת כלשונה:
-- מפתח שאינו בתוך ה-payload לעולם לא מאפס עמודה.
create or replace function app.apply_event_task_block(p_event_id uuid, p_code text, payload jsonb)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_type    task_types;
  v_event   events;
  v_task_id uuid;
  v_method  uuid;
  v_price   numeric;
  k_date    text := p_code || '_date';
  k_time    text := p_code || '_time';
  k_workers text := p_code || '_worker_count';
  k_hours   text := p_code || '_hours_count';
  k_method  text := p_code || '_execution_method';
  k_price   text := p_code || '_price';
begin
  if payload is null
     or not (payload ?| array[k_date, k_time, k_workers, k_hours, k_method, k_price]) then
    return;
  end if;

  select * into v_type from task_types
    where code = p_code and is_active and deleted_at is null;
  if v_type.id is null then return; end if;  -- type disabled in settings — nothing to fill

  select * into v_event from events where id = p_event_id;
  if v_event.id is null then raise exception 'אירוע לא נמצא'; end if;

  -- אופן ביצוע חייב להיות בחיתוך: פעיל ∩ מותר לסוג המשימה ∩ מותר ללקוח
  if payload ? k_method then
    v_method := (nullif(payload ->> k_method, ''))::uuid;
    if v_method is not null and not exists (
         select 1 from execution_methods m
         join task_type_execution_methods ttm
           on ttm.execution_method_id = m.id and ttm.task_type_id = v_type.id
         join customer_execution_methods cem
           on cem.execution_method_id = m.id and cem.customer_id = v_event.customer_id
         where m.id = v_method and m.is_active and m.deleted_at is null)
    then
      raise exception 'אופן הביצוע שנבחר אינו זמין עבור % אצל לקוח זה', v_type.name;
    end if;
  end if;

  select t.id into v_task_id from tasks t
   where t.event_id = p_event_id and t.task_type_id = v_type.id and t.deleted_at is null
   order by t.created_at, t.id limit 1;

  -- המשימה נמחקה או שלא נוצרה אוטומטית — יוצרים אותה מחדש
  if v_task_id is null then
    insert into tasks (event_id, customer_id, task_type_id, task_date, status_id, worker_count, created_by)
    values (p_event_id, v_event.customer_id, v_type.id,
            coalesce((nullif(payload ->> k_date, ''))::date, v_event.event_date),
            (select id from statuses where entity = 'task' and is_default and deleted_at is null limit 1),
            0, app.profile_id())
    returning id into v_task_id;
  end if;

  update tasks set
    task_date           = case when payload ? k_date
                            then coalesce((nullif(payload ->> k_date, ''))::date, task_date)
                            else task_date end,
    onsite_start_time   = case when payload ? k_time
                            then (nullif(payload ->> k_time, ''))::time else onsite_start_time end,
    hours_count         = case when payload ? k_hours
                            then (nullif(payload ->> k_hours, ''))::numeric else hours_count end,
    worker_count        = case when payload ? k_workers
                            then coalesce((nullif(payload ->> k_workers, ''))::int, 0) else worker_count end,
    execution_method_id = case when payload ? k_method
                            then (nullif(payload ->> k_method, ''))::uuid else execution_method_id end
  where id = v_task_id;

  -- מחיר שהוזן בטופס הוא מחיר של אדם, ולכן הוא נכנס נעול (is_manual) —
  -- אחרת הטריגר שרץ שורה למעלה היה דורס אותו מיד. בלי המפתח הכתיבה נדלגת
  -- בשקט ולא נופלת: שדה שאינו גלוי למשתמש עשוי בכל זאת להישלח מטיוטה
  -- שנשמרה ב-localStorage, וזו לא סיבה להפיל יצירת אירוע.
  if payload ? k_price and app.has('pricing.edit') then
    v_price := (nullif(payload ->> k_price, ''))::numeric;
    if v_price is not null then
      insert into task_pricing (task_id, price, is_manual, breakdown, calculated_at)
      values (v_task_id, v_price, true, null, now())
      on conflict (task_id) do update
        set price = excluded.price, is_manual = true, breakdown = null;
    end if;
  end if;
end $$;

-- ===== 15. תבנית ההתחלה ====================================================
-- המחשבון הוא דאטה, אבל "דף ריק" הוא ממשק גרוע. הפונקציה הזו מחזירה את
-- נוסחת ההקמה/פירוק המקובלת כנקודת מוצא, והבונה במסך הלקוח פותח ממנה.
-- כל מספר כאן ניתן לשינוי במסך בלי לגעת בקוד — כולל התעריף, המקדמים
-- ומדרגות זמן המחסן, שהם בדיוק המספרים שמשתנים מלקוח ללקוח.
create or replace function app.default_pricing_config(p_code text)
returns jsonb language sql immutable as $$
  select case when p_code = 'teardown' then '{
    "version": 1,
    "model": "worker_hours",
    "hour_rate": 60,
    "per_worker_fee": 80,
    "constants": { "requires_team_lead": false },
    "hours": [
      { "id": "wh_start", "label": "זמן מחסן", "kind": "stepped",
        "input": "truck_count", "first": 0.5, "each_additional": 0.25 },
      { "id": "travel", "label": "נסיעה (הלוך-חזור)", "kind": "input",
        "input": "travel_hours", "multiplier": 2 },
      { "id": "work", "label": "עבודה באירוע", "kind": "input", "input": "hours_count" },
      { "id": "break", "label": "הפסקה", "kind": "const", "hours": 0.5 },
      { "id": "spare", "label": "ספייר", "kind": "const", "hours": 0.5 },
      { "id": "wh_end", "label": "מחסן בסיום", "kind": "stepped",
        "input": "truck_count", "first": 0.5, "each_additional": 0.25 }
    ],
    "workers": { "input": "worker_count", "adjustments": [
      { "id": "no_parking", "label": "אין חניה — עובד נוסף", "add": 1,
        "when": { "all": [ { "field": "no_parking", "op": "is_true" } ] } }
    ] },
    "after_workers": [
      { "id": "team_lead", "label": "ראש צוות", "kind": "fixed", "amount": 100,
        "when": { "all": [ { "field": "requires_team_lead", "op": "is_true" } ] } },
      { "id": "porterage", "label": "סבלות", "kind": "per_worker", "amount": 100,
        "workers_basis": "base",
        "when": { "all": [ { "field": "porterage", "op": "is_true" } ] } }
    ],
    "multipliers": [
      { "id": "m1", "label": "מקדם ×1.3", "factor": 1.3 },
      { "id": "m2", "label": "מקדם ×1.2", "factor": 1.2 }
    ],
    "min_price": null,
    "max_price": null,
    "rounding": { "mode": "nearest", "to": 1 }
  }'::jsonb
  when p_code = 'setup' then '{
    "version": 1,
    "model": "worker_hours",
    "hour_rate": 60,
    "per_worker_fee": 80,
    "constants": { "requires_team_lead": false },
    "hours": [
      { "id": "trucks", "label": "משאיות", "kind": "stepped",
        "input": "truck_count", "first": 1, "each_additional": 0.5 },
      { "id": "travel", "label": "נסיעה (הלוך-חזור)", "kind": "input",
        "input": "travel_hours", "multiplier": 2 },
      { "id": "work", "label": "עבודה באירוע", "kind": "input", "input": "hours_count" },
      { "id": "break", "label": "הפסקה", "kind": "const", "hours": 0.5 },
      { "id": "spare", "label": "ספייר", "kind": "const", "hours": 0.5 },
      { "id": "wh_end", "label": "מחסן בסיום", "kind": "stepped",
        "input": "truck_count", "first": 0.5, "each_additional": 0.25 }
    ],
    "workers": { "input": "worker_count", "adjustments": [
      { "id": "no_parking", "label": "אין חניה — עובד נוסף", "add": 1,
        "when": { "all": [ { "field": "no_parking", "op": "is_true" } ] } }
    ] },
    "after_workers": [
      { "id": "team_lead", "label": "ראש צוות", "kind": "fixed", "amount": 100,
        "when": { "all": [ { "field": "requires_team_lead", "op": "is_true" } ] } },
      { "id": "porterage", "label": "סבלות", "kind": "per_worker", "amount": 100,
        "workers_basis": "base",
        "when": { "all": [ { "field": "porterage", "op": "is_true" } ] } }
    ],
    "multipliers": [
      { "id": "m1", "label": "מקדם ×1.3", "factor": 1.3 },
      { "id": "m2", "label": "מקדם ×1.2", "factor": 1.2 }
    ],
    "min_price": null,
    "max_price": null,
    "rounding": { "mode": "nearest", "to": 1 }
  }'::jsonb
  else '{"version":1,"model":"line_items","components":[],
         "rounding":{"mode":"nearest","to":1}}'::jsonb end
$$;

create or replace function pricing_config_template(p_task_type_id uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_code text;
begin
  perform app.require('pricing.manage_rules');
  select code into v_code from task_types where id = p_task_type_id;
  return app.default_pricing_config(v_code);
end $$;

-- ===== 16. מחיקת אזור ======================================================
-- אזור נמחק בעדכון ישיר של deleted_at ולא דרך soft_delete. זו לא קיצור דרך:
-- soft_delete הוגדרה מחדש כבר שלוש פעמים (0006, 0012, 0014), וכל הוספת טבלה
-- אליה מחייבת להעתיק את כל גופה ולהסתכן בהחזרת גרסה ישנה של הבדיקות שנוספו
-- בדרך. הפוליסה pz_write כבר דורשת pricing.manage_rules בדיוק כמו שהמפתח
-- ברשימה ההיא היה דורש, ולכן אין כאן ויתור על שום בדיקה — רק על ההעתקה.
