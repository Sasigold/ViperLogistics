-- 0044: מנוע הדוחות — הצד שפולט SQL
--
-- 0043 אמרה מה מותר. הקובץ הזה מרכיב מזה שאילתה, וכל שורה בו נכתבה מול השאלה
-- "איך זה יכול להישבר".
--
-- ===== שלושה כללים שמחזיקים את הכול ========================================
--
--   1. **מזהים דרך `%I`, ערכים דרך פרמטר, ולא כלום אחר.** אין בקובץ הזה אף
--      מקום שבו טקסט מהמפרט מוטמע במחרוזת SQL. שם עמודה עובר `%I` אחרי שנשלף
--      משורת קטלוג; ערך סינון עובר כאיבר במערך jsonb יחיד ($3) והביטוי מפנה
--      אליו באינדקס שנקבע ב-plpgsql.
--   2. **כל צורת SQL היא CASE סגור עם `else null` ואז `raise`** — צורת
--      `soft_delete` מ-0014. אין `format` על ערך שלא עבר CASE.
--   3. **אין `app.has` בתוך ה-SQL שנפלט.** כל החלטת הרשאה קורית ב-plpgsql
--      *לפני* שהמחרוזת נבנית, ולכן השאילתה המופקת נקייה מפונקציות הרשאה.
--      ה-RLS שהיא מפעילה כבר נושאת את הרמת ה-InitPlan שלה מ-0013 ומ-0028.
--
-- ===== שלוש תוצאות, מובחנות במכוון ========================================
--
--   • **הרשאה נדחתה** → `{"rows": null, "meta": {"denied": true}}`.
--     `0` אומר "אין", `null` אומר "לא בשבילך" — מוסכמת 0026 ו-0041. המסגרת
--     משמיטה את הווידג׳ט. `raise` היה שם ריבוע אדום על הדשבורד של מישהו בגלל
--     ווידג׳ט שקולגה שיתף איתו.
--   • **מפתח לא מוכר** (הפרשי גרסה, שדה שהוצא) → `{"rows": null,
--     "meta": {"unsupported": "<key>"}}`. **המפרט לעולם לא נמחק ולא נכתב
--     מחדש**; המסך מציג את הכותרת ואומר שהנתון אינו קיים עוד.
--   • **מפרט פגום** — אופרטור שאינו ב-allowed_ops, צירוף מדד×פילוח לא חוקי,
--     טיפוס jsonb שגוי, יותר מדי סינונים → **raise 22023**. אלה אינם יכולים
--     לנבוע מהפרשי גרסה, רק מבקשה שנבנתה ביד. להיכשל סגור וברעש.

-- ===== 1. חילוץ הרווח הגולמי ===============================================
--
-- שלושת ענפי `margin.*` ב-0041 מחושבים כאן, ו-`dashboard_sections` נכתבת מחדש
-- מעליהם בסוף הקובץ. אותה תזה של 0039: הבונה והווידג׳טים הסטטיים חייבים לקרוא
-- **מימוש אחד**, כי מימוש שני מתיישן. ההוכחה שדבר לא השתנה היא שהטענות
-- הקיימות ב-05_dashboard.sql ממשיכות לעבור ללא נגיעה.
--
-- security definer, כמו app.payroll_*: הן חייבות לקרוא את השכר, וזה עובר דרך
-- app.attendance_pay_rows שמבוטלת מ-authenticated. הן דורשות את המפתחות בעצמן.

create or replace function app.margin_require() returns void
language plpgsql stable security definer set search_path = public as $$
begin
  -- ארבעה מפתחות יחד: רווח הוא חיסור, ולכן מי שרואה אותו יכול לגזור ממנו את
  -- הרכיבים, ואין טעם להעמיד פנים שאפשר להראות רווח בלי להראות עלות.
  if not app.has_all(array['dashboard.margin','dashboard.payroll',
                           'dashboard.contractor_cost','pricing.revenue']) then
    raise exception 'אין הרשאה לרווח גולמי' using errcode = '42501';
  end if;
  -- ...ובתנאי שהקורא רואה את כל המשימות. עלות השכר היא של כל החברה ואינה
  -- ניתנת לצמצום, ולכן קורא מצומצם היה מקבל "ההכנסות שלי פחות השכר של כולם".
  if exists (select 1 from app.scope_rows('tasks') where scope_type <> 'all') then
    raise exception 'רווח גולמי אינו זמין להיקף נתונים מצומצם' using errcode = '42501';
  end if;
end $$;

create or replace function app.margin_summary(p_from date, p_to date)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_rev numeric; v_con numeric; v_pay jsonb;
begin
  perform app.margin_require();
  v_pay := app.payroll_summary(p_from, p_to);

  select coalesce(sum(tp.price), 0) into v_rev
    from task_pricing tp join tasks t on t.id = tp.task_id and t.deleted_at is null
   where t.task_date between p_from and p_to;
  select coalesce(sum(tct.price), 0) into v_con
    from task_contractor_terms tct join tasks t on t.id = tct.task_id and t.deleted_at is null
   where t.task_date between p_from and p_to;

  return jsonb_build_object(
    'revenue',    round(v_rev, 2),
    'contractor', round(v_con, 2),
    'payroll',    (v_pay -> 'total'),
    'gross',      round(v_rev - v_con - coalesce((v_pay ->> 'total')::numeric, 0), 2),
    'pct',        case when v_rev > 0
                       then round((v_rev - v_con - coalesce((v_pay ->> 'total')::numeric, 0))
                                  / v_rev * 100, 1) end,
    'unrated_shifts', (v_pay -> 'unrated_shifts'),
    'excludes_overhead', true);
end $$;

create or replace function app.margin_trend(p_from date, p_to date, p_bucket text default 'week')
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v jsonb; v_b text := case when p_bucket in ('day','week','month','quarter')
                                  then p_bucket else 'week' end;
begin
  perform app.margin_require();
  select coalesce(jsonb_agg(row_to_json(x) order by x.bucket), '[]') into v from (
    select coalesce(b.bucket, p.bucket) as bucket,
           round(coalesce(b.revenue, 0), 2)    as revenue,
           round(coalesce(b.contractor, 0), 2) as contractor,
           round(coalesce(p.total, 0), 2)      as payroll,
           round(coalesce(b.revenue, 0) - coalesce(b.contractor, 0) - coalesce(p.total, 0), 2) as gross
      from (
        select date_trunc(v_b, t.task_date)::date as bucket,
               sum(tp.price) as revenue, sum(tct.price) as contractor
          from tasks t
          left join task_pricing tp on tp.task_id = t.id
          left join task_contractor_terms tct on tct.task_id = t.id
         where t.deleted_at is null and t.task_date between p_from and p_to
         group by 1) b
      full join (
        select (e ->> 'bucket')::date as bucket, (e ->> 'total')::numeric as total
          from jsonb_array_elements(app.payroll_trend(p_from, p_to, v_b)) e) p
        on p.bucket = b.bucket) x;
  return v;
end $$;

create or replace function app.margin_by_customer(p_from date, p_to date, p_limit int default 12)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v jsonb; v_alloc jsonb;
begin
  perform app.margin_require();
  if not app.has('customers.view') then
    raise exception 'אין הרשאה ללקוחות' using errcode = '42501';
  end if;
  v_alloc := app.payroll_task_alloc(p_from, p_to);

  select jsonb_build_object(
    'rows', (select coalesce(jsonb_agg(row_to_json(x) order by x.revenue desc), '[]') from (
        select c.name, c.color,
               round(coalesce(sum(tp.price), 0), 2)  as revenue,
               round(coalesce(sum(tct.price), 0), 2) as contractor,
               round(coalesce((select (a ->> 'payroll')::numeric
                                 from jsonb_array_elements(v_alloc -> 'by_customer') a
                                where a ->> 'name' = c.name), 0), 2) as payroll
          from tasks t
          join customers c on c.id = t.customer_id
          left join task_pricing tp on tp.task_id = t.id
          left join task_contractor_terms tct on tct.task_id = t.id
         where t.deleted_at is null and t.task_date between p_from and p_to
         group by c.name, c.color
         limit greatest(1, least(coalesce(p_limit, 12), 50))) x),
    'unallocated', (v_alloc -> 'unallocated'),
    'allocated',   (v_alloc -> 'allocated'),
    'estimated', true)
    into v;
  return v;
end $$;

revoke execute on function app.margin_require()                        from anon, authenticated, public;
revoke execute on function app.margin_summary(date, date)              from anon, authenticated, public;
revoke execute on function app.margin_trend(date, date, text)          from anon, authenticated, public;
revoke execute on function app.margin_by_customer(date, date, int)     from anon, authenticated, public;

-- ===== 2. עוזרי הרכבה — ה-CASE-ים הסגורים ==================================
--
-- כולם `immutable` ו-`set search_path`: הם נקראים מתוך פונקציית invoker, ואין
-- להם גישה לנתונים בכלל — הם ממפים מזהה לצורה, ותו לא.

-- מקור → ה-FROM
create or replace function app.report_source_sql(p_key text) returns text
language sql immutable set search_path = public as $$
  select case p_key
    when 'tasks'      then 'tasks t'
    when 'events'     then 'events e'
    -- profiles נכנס כאן כי הפילוח "לפי עובד" זקוק לשם, וזה join פנימי מבחינה
    -- לוגית: לכל שורת נוכחות יש בעלים.
    when 'attendance' then 'attendance_entries a join profiles p on p.id = a.profile_id'
    -- 'payroll' אינו כאן במכוון: כל מדדיו הם impl='engine'. app.attendance_pay_rows
    -- מבוטלת מ-authenticated, ולכן פונקציית invoker אינה יכולה לקרוא לה גם אם
    -- ננסה — וזו בדיוק הסיבה שהשכר מנותב לעוזרי definer.
    else null end
$$;

-- מקור → ה-WHERE שאינו ניתן לעריכה. **המלכודות יושבות כאן ולא בקטלוג**, ולכן
-- אי אפשר לכתוב מפרט שמבטל אותן.
create or replace function app.report_source_where(p_key text) returns text
language sql immutable set search_path = public as $$
  select case p_key
    when 'tasks'      then 't.deleted_at is null'
    when 'events'     then 'e.deleted_at is null'
    -- 'approved' ולא "הכול": שעות ממתינות אינן שעות שעבדו עליהן עדיין, וזו
    -- אותה הגדרה שכל דוח הנוכחות משתמש בה. ה-meta מצהיר על זה בכל תוצאה.
    when 'attendance' then 'a.deleted_at is null and a.status = ''approved'''
    else null end
$$;

-- join_key → קטע ה-join. כל אחד מהם **LEFT**, תמיד, בלי יוצא מן הכלל: כך
-- שורה שאין לה לקוח או סטטוס מקבלת דלי "ללא ..." במקום להיעלם מהספירה. זו
-- מלכודת שנפתרת מבנית ולא בבוליאני שמישהו צריך להציב נכון.
create or replace function app.report_join_sql(p_key text) returns text
language sql immutable set search_path = public as $$
  select case p_key
    when 'customers'        then ' left join customers c on c.id = t.customer_id and c.deleted_at is null'
    when 'task_status'      then ' left join statuses s on s.id = t.status_id'
    when 'task_types'       then ' left join task_types tt on tt.id = t.task_type_id'
    when 'exec_methods'     then ' left join execution_methods em on em.id = t.execution_method_id'
    -- LEFT lateral ולא CROSS: cross join על מערך ריק מוחק את המשימה מהתוצאה,
    -- ומשימה בלי משאית היא בדיוק מה ש"משימות לפי משאית" צריך להראות.
    when 'trucks'           then ' left join lateral unnest(t.truck_ids) as u(truck_id) on true'
                                 ' left join trucks tr on tr.id = u.truck_id'
    when 'task_contractor'  then ' left join contractors ct on ct.id = t.contractor_id and ct.deleted_at is null'
    when 'task_pricing'     then ' left join task_pricing tp on tp.task_id = t.id'
    when 'contractor_terms' then ' left join task_contractor_terms tct on tct.task_id = t.id'
    when 'ev_customers'     then ' left join customers ec on ec.id = e.customer_id and ec.deleted_at is null'
    when 'ev_status'        then ' left join statuses es on es.id = e.status_id'
    -- profiles כבר ב-FROM של attendance; הפילוח רק צריך את הכינוי.
    when 'people'           then ''
    else null end
$$;

-- join_key → הכינוי. נגזר כאן ולא נשמר בקטלוג, כדי שכינוי וקטע ה-join לא
-- יוכלו להיפרד זה מזה.
create or replace function app.report_join_alias(p_key text, p_source text) returns text
language sql immutable set search_path = public as $$
  select case
    when p_key is null then case p_source
      when 'tasks' then 't' when 'events' then 'e' when 'attendance' then 'a' else null end
    else case p_key
      when 'customers'        then 'c'
      when 'task_status'      then 's'
      when 'task_types'       then 'tt'
      when 'exec_methods'     then 'em'
      when 'trucks'           then 'tr'
      when 'task_contractor'  then 'ct'
      when 'task_pricing'     then 'tp'
      when 'contractor_terms' then 'tct'
      when 'ev_customers'     then 'ec'
      when 'ev_status'        then 'es'
      when 'people'           then 'p'
      else null end
  end
$$;

-- שם האגרגט. **אינו מוטמע מהמפרט**: גם מפרט שעבר את בדיקת allowed_aggs
-- אינו יכול להזריק דרך שם האגרגט, כי הוא עובר דרך ה-CASE הזה.
create or replace function app.report_agg_sql(p_agg text, p_alias text, p_col text) returns text
language sql immutable set search_path = public as $$
  select case p_agg
    when 'sum'            then format('sum(%I.%I)', p_alias, p_col)
    when 'avg'            then format('avg(%I.%I)', p_alias, p_col)
    when 'min'            then format('min(%I.%I)', p_alias, p_col)
    when 'max'            then format('max(%I.%I)', p_alias, p_col)
    when 'count'          then format('count(%I.%I)', p_alias, p_col)
    when 'count_distinct' then format('count(distinct %I.%I)', p_alias, p_col)
    else null end
$$;

-- הטלה של ערך סינון. הטיפוס מגיע מ-report_fields.col_type — enum סגור,
-- לעולם לא מהקלט.
create or replace function app.report_cast(p_type text) returns text
language sql immutable set search_path = public as $$
  select case p_type
    when 'uuid' then 'uuid' when 'text' then 'text' when 'numeric' then 'numeric'
    when 'int' then 'int'   when 'date' then 'date' when 'bool' then 'boolean'
    else null end
$$;

/**
 * תנאי סינון יחיד → פרדיקט.
 *
 * `p_idx` הוא סידורי הסינון, והוא נקבע ב-plpgsql. **לכל סינון בדיוק תא אחד**
 * ב-$3, גם ל-between (מערך בן שניים) וגם לאופרטורים חסרי ערך (null בתא) —
 * ולכן אין ספירת arity שאפשר לטעות בה.
 *
 * אופרטור שאינו מוכר מחזיר null, והקורא **זורק**. זה ההפך מ-app.price_cond
 * (0017) שמחזיר true על תנאי לא מוכר: לתמחור "נכשל פתוח" הוא ברירת מחדל
 * סבירה, לפילטר זה אומר להציג יותר שורות ממה שהמחבר ביקש.
 */
create or replace function app.report_filter_sql(
  p_alias text, p_col text, p_type text, p_op text, p_idx int) returns text
language sql immutable set search_path = public as $$
  select case p_op
    when 'eq'  then format('%I.%I = ($3 ->> %s)::%s',  p_alias, p_col, p_idx, app.report_cast(p_type))
    when 'ne'  then format('%I.%I <> ($3 ->> %s)::%s', p_alias, p_col, p_idx, app.report_cast(p_type))
    when 'gt'  then format('%I.%I > ($3 ->> %s)::%s',  p_alias, p_col, p_idx, app.report_cast(p_type))
    when 'gte' then format('%I.%I >= ($3 ->> %s)::%s', p_alias, p_col, p_idx, app.report_cast(p_type))
    when 'lt'  then format('%I.%I < ($3 ->> %s)::%s',  p_alias, p_col, p_idx, app.report_cast(p_type))
    when 'lte' then format('%I.%I <= ($3 ->> %s)::%s', p_alias, p_col, p_idx, app.report_cast(p_type))
    when 'in'  then format('%I.%I in (select v::%s from jsonb_array_elements_text($3 -> %s) v)',
                           p_alias, p_col, app.report_cast(p_type), p_idx)
    when 'not_in' then format('(%I.%I is null or %I.%I not in (select v::%s from jsonb_array_elements_text($3 -> %s) v))',
                           p_alias, p_col, p_alias, p_col, app.report_cast(p_type), p_idx)
    when 'between' then format('%I.%I between ($3 #>> array[%L,''0''])::%s and ($3 #>> array[%L,''1''])::%s',
                           p_alias, p_col, p_idx::text, app.report_cast(p_type),
                           p_idx::text, app.report_cast(p_type))
    when 'is_null'     then format('%I.%I is null',     p_alias, p_col)
    when 'is_not_null' then format('%I.%I is not null', p_alias, p_col)
    when 'is_true'     then format('%I.%I is true',     p_alias, p_col)
    when 'is_false'    then format('%I.%I is not true', p_alias, p_col)
    else null end
$$;

-- ===== 3. שערי ההרשאה ======================================================
-- מופרדים לפונקציות כדי שיהיו קריאים אחד-אחד, ולא כדי שייקראו פעמיים.

create or replace function app.report_may_measure(p_m report_measures, p_scoped boolean)
returns boolean language sql stable security invoker set search_path = public as $$
  select case
    when p_m.perm_key is not null and not app.has(p_m.perm_key) then false
    -- perm_all ולא perm_key: מפתח הדשבורד לבדו אינו מספיק כשהשורות מגיעות
    -- דרך RLS שדורשת מפתח אחר. בלי זה מתקבל 0 בטוח במקום null.
    when p_m.perm_all is not null and not app.has_all(p_m.perm_all) then false
    -- שער ברמת עמודה. app.has לבדו הוא עקיפה: אפשר להחזיק pricing.revenue
    -- ולהישלל ב-field_permissions על ('task_pricing','price').
    when p_m.field_entity is not null
     and not app.can_view_field(p_m.field_entity, p_m.field_key) then false
    when p_m.requires_unscoped and p_scoped then false
    else true end
$$;

create or replace function app.report_may_field(p_f report_fields)
returns boolean language sql stable security invoker set search_path = public as $$
  select case
    when p_f.perm_key is not null and not app.has(p_f.perm_key) then false
    when p_f.field_entity is not null
     and not app.can_view_field(p_f.field_entity, p_f.field_key) then false
    else true end
$$;

-- ===== 4. מדדי מנוע — שכר ורווח ============================================
--
-- **אין כאן SQL גנרי בכלל.** המפרט נבדק, וההרצה מנותבת לעוזר definer קיים.
-- זו התזה של 0039 מיושמת שנית: הצבר השבועי תלוי-סדר, וכל ניסיון לחשב אותו
-- מחדש בשאילתה גנרית היה מתפצל מהדוח בשקט.

create or replace function app.report_engine_measure(
  p_m report_measures, p_dim text, p_bucket text, p_from date, p_to date, p_limit int)
returns jsonb language plpgsql stable security invoker set search_path = public as $$
declare
  v_rows jsonb := '[]'::jsonb;
  v_meta jsonb;
  v_sum  jsonb;
  v_key  text;
  v_tot  numeric;
  v_est  boolean := false;
  v_alloc jsonb;
begin
  v_meta := jsonb_build_object('measure', p_m.key, 'unit', p_m.unit,
                               'dimension', p_dim, 'scope_note', 'משמרות מאושרות בלבד');

  -- ── שכר ────────────────────────────────────────────────────────────────
  if p_m.key like 'payroll.%' then
    v_key := case p_m.key
      when 'payroll.total'           then 'total'
      when 'payroll.paid_hours'      then 'paid_hours'
      when 'payroll.overtime_hours'  then 'overtime_hours'
      when 'payroll.bonus'           then 'bonus'
      when 'payroll.shifts'          then 'shifts'
      else null end;
    if v_key is null then
      return jsonb_build_object('rows', null,
               'meta', jsonb_build_object('unsupported', p_m.key));
    end if;

    if p_dim is null then
      v_sum  := app.payroll_summary(p_from, p_to);
      v_tot  := coalesce((v_sum ->> v_key)::numeric, 0);
      v_rows := jsonb_build_array(jsonb_build_object(
                  'key', null, 'label', p_m.label_he, 'color', null,
                  'value', v_tot, 'n', coalesce((v_sum ->> 'shifts')::int, 0)));
      -- המונה של 0041: משמרת בלי תעריף נעלמת מ-sum() בשקט, ובלי המספר הזה
      -- עלות השכר מדווחת נמוך מדי בלי שאיש יידע.
      v_meta := v_meta || jsonb_build_object('unrated_shifts', v_sum -> 'unrated_shifts');

    elsif p_dim = 'payroll.date' then
      select coalesce(jsonb_agg(jsonb_build_object(
               'key', e ->> 'bucket', 'label', e ->> 'bucket', 'color', null,
               'value', case when v_key = 'paid_hours' then (e ->> 'hours')::numeric
                             else (e ->> 'total')::numeric end,
               'n', 0) order by e ->> 'bucket'), '[]')
        into v_rows
        from jsonb_array_elements(app.payroll_trend(p_from, p_to, p_bucket)) e;

    elsif p_dim = 'payroll.worker' then
      select coalesce(jsonb_agg(jsonb_build_object(
               'key', e ->> 'name', 'label', e ->> 'name', 'color', null,
               'value', case when v_key = 'paid_hours' then (e ->> 'hours')::numeric
                             else (e ->> 'total')::numeric end,
               'n', 0)), '[]')
        into v_rows
        from jsonb_array_elements(app.payroll_by_worker(p_from, p_to, p_limit)) e;

    elsif p_dim = 'payroll.customer' then
      v_alloc := app.payroll_task_alloc(p_from, p_to);
      v_est := true;
      select coalesce(jsonb_agg(jsonb_build_object(
               'key', e ->> 'name', 'label', e ->> 'name', 'color', e ->> 'color',
               'value', (e ->> 'payroll')::numeric, 'n', 0)), '[]')
        into v_rows
        from jsonb_array_elements(v_alloc -> 'by_customer') e;
      v_meta := v_meta || jsonb_build_object(
                  'allocated', v_alloc -> 'allocated', 'unallocated', v_alloc -> 'unallocated');
    else
      return jsonb_build_object('rows', null, 'meta', jsonb_build_object('unsupported', p_dim));
    end if;

  -- ── רווח גולמי ─────────────────────────────────────────────────────────
  elsif p_m.key in ('margin.gross', 'margin.pct') then
    v_key := case p_m.key when 'margin.gross' then 'gross' else 'pct' end;

    if p_dim is null then
      v_sum  := app.margin_summary(p_from, p_to);
      v_rows := jsonb_build_array(jsonb_build_object(
                  'key', null, 'label', p_m.label_he, 'color', null,
                  'value', (v_sum ->> v_key)::numeric, 'n', 0));
      v_meta := v_meta || jsonb_build_object(
                  'unrated_shifts', v_sum -> 'unrated_shifts',
                  'revenue', v_sum -> 'revenue', 'contractor', v_sum -> 'contractor',
                  'payroll', v_sum -> 'payroll', 'excludes_overhead', true);

    elsif p_dim = 'payroll.date' then
      select coalesce(jsonb_agg(jsonb_build_object(
               'key', e ->> 'bucket', 'label', e ->> 'bucket', 'color', null,
               'value', case when v_key = 'pct'
                             then case when (e ->> 'revenue')::numeric > 0
                                       then round((e ->> 'gross')::numeric
                                                  / (e ->> 'revenue')::numeric * 100, 1) end
                             else (e ->> 'gross')::numeric end,
               'n', 0) order by e ->> 'bucket'), '[]')
        into v_rows
        from jsonb_array_elements(app.margin_trend(p_from, p_to, p_bucket)) e;
      v_meta := v_meta || jsonb_build_object('excludes_overhead', true);

    elsif p_dim = 'payroll.customer' and p_m.key = 'margin.gross' then
      v_alloc := app.margin_by_customer(p_from, p_to, p_limit);
      v_est := true;
      select coalesce(jsonb_agg(jsonb_build_object(
               'key', e ->> 'name', 'label', e ->> 'name', 'color', e ->> 'color',
               'value', round((e ->> 'revenue')::numeric - (e ->> 'contractor')::numeric
                              - (e ->> 'payroll')::numeric, 2),
               'n', 0)), '[]')
        into v_rows
        from jsonb_array_elements(v_alloc -> 'rows') e;
      v_meta := v_meta || jsonb_build_object(
                  'allocated', v_alloc -> 'allocated', 'unallocated', v_alloc -> 'unallocated',
                  'excludes_overhead', true);
    else
      return jsonb_build_object('rows', null, 'meta', jsonb_build_object('unsupported', p_dim));
    end if;
  else
    return jsonb_build_object('rows', null, 'meta', jsonb_build_object('unsupported', p_m.key));
  end if;

  select coalesce(sum((e ->> 'value')::numeric), 0) into v_tot
    from jsonb_array_elements(v_rows) e;

  return jsonb_build_object('rows', v_rows, 'meta', v_meta || jsonb_build_object(
    'total', case when p_dim is null
                  then (v_rows -> 0 ->> 'value')::numeric else round(v_tot, 2) end,
    'row_count', jsonb_array_length(v_rows),
    'estimated', v_est,
    'bucket', case when p_dim = 'payroll.date' then p_bucket end));
end $$;

-- ===== 5. המנוע ============================================================

create or replace function app.report_run(p_spec jsonb, p_from date, p_to date)
returns jsonb language plpgsql stable security invoker set search_path = public as $$
declare
  v_src    report_sources%rowtype;
  v_m      report_measures%rowtype;
  v_d      report_fields%rowtype;
  v_f      report_fields%rowtype;
  v_scoped boolean;
  v_agg    text;
  v_bucket text;
  v_limit  int;
  v_dimkey text;
  v_from   text;
  v_where  text;
  v_join   text := '';
  v_seen   text[] := '{}';
  v_group  text;
  v_label  text;
  v_color  text;
  v_aggsql text;
  v_pres   text := '0';
  v_zero   text := '0';
  v_order  text;
  v_alias  text;
  v_malias text;
  v_sql    text;
  v_res    jsonb;
  v_params jsonb := '[]'::jsonb;
  v_idx    int := 0;
  f        jsonb;
  v_op     text;
  v_val    jsonb;
  v_frag   text;
begin
  perform app.require('dashboard.view');

  -- ── גבולות, בדיוק ארבעת אלה של dashboard_sections ──────────────────────
  if p_from is null or p_to is null then
    raise exception 'חסר טווח תאריכים' using errcode = '22023'; end if;
  if p_to < p_from then
    raise exception 'טווח תאריכים הפוך' using errcode = '22023'; end if;
  if p_to - p_from > 400 then
    raise exception 'טווח גדול מדי לדשבורד' using errcode = '22023'; end if;
  if coalesce(jsonb_array_length(p_spec -> 'filters'), 0) > 8 then
    raise exception 'יותר מדי תנאי סינון' using errcode = '22023'; end if;

  -- פתק לעולם אינו מגיע למנוע: הוא נצבע בלקוח ואינו נוגע בנתונים.
  if p_spec ->> 'variant' = 'note' then
    raise exception 'פתק אינו שאילתה' using errcode = '22023'; end if;

  v_scoped := exists (select 1 from app.scope_rows('tasks') where scope_type <> 'all');
  v_bucket := case when p_spec #>> '{dimension,bucket}' in ('day','week','month','quarter')
                   then p_spec #>> '{dimension,bucket}' else 'week' end;
  v_limit  := greatest(1, least(coalesce((p_spec ->> 'limit')::int, 12), 50));

  -- ── מקור ────────────────────────────────────────────────────────────────
  select * into v_src from report_sources where key = p_spec ->> 'source';
  if not found then
    return jsonb_build_object('rows', null,
             'meta', jsonb_build_object('unsupported', p_spec ->> 'source'));
  end if;
  if v_src.perm_key is not null and not app.has(v_src.perm_key) then
    return jsonb_build_object('rows', null, 'meta', jsonb_build_object('denied', true));
  end if;

  -- ── מדד ─────────────────────────────────────────────────────────────────
  select * into v_m from report_measures
   where key = p_spec ->> 'measure' and source_key = v_src.key;
  if not found then
    return jsonb_build_object('rows', null,
             'meta', jsonb_build_object('unsupported', p_spec ->> 'measure'));
  end if;
  if not app.report_may_measure(v_m, v_scoped) then
    return jsonb_build_object('rows', null,
             'meta', jsonb_build_object('denied', true,
                                        'scoped', v_m.requires_unscoped and v_scoped));
  end if;

  v_agg := coalesce(p_spec ->> 'agg', v_m.default_agg);
  if not (v_agg = any (v_m.allowed_aggs)) then
    raise exception 'סוג החישוב אינו נתמך למדד הזה' using errcode = '22023';
  end if;

  -- ── הפילוח, ולפניו החוקיות ─────────────────────────────────────────────
  v_dimkey := p_spec #>> '{dimension,field}';
  if v_dimkey is not null then
    select * into v_d from report_fields
     where key = v_dimkey and source_key = v_src.key and can_group;
    if not found then
      return jsonb_build_object('rows', null,
               'meta', jsonb_build_object('unsupported', v_dimkey));
    end if;
    if not app.report_may_field(v_d) then
      return jsonb_build_object('rows', null, 'meta', jsonb_build_object('denied', true));
    end if;
    if v_m.allowed_dims is not null and not (v_d.key = any (v_m.allowed_dims)) then
      raise exception 'הפילוח הזה אינו חוקי למדד הזה' using errcode = '22023';
    end if;
    -- unnest מכפיל שורות. סכום ברמת המשימה על פילוח כזה נספר פעמיים, ומספר
    -- שגוי בביטחון גרוע ממספר שחסר.
    if v_d.fans_out and not v_m.fanout_safe then
      raise exception 'המדד הזה אינו ניתן לפילוח שמכפיל שורות' using errcode = '22023';
    end if;
  elsif v_m.allowed_dims is not null and not ('__none__' = any (v_m.allowed_dims)) then
    raise exception 'המדד הזה מחייב פילוח' using errcode = '22023';
  end if;

  -- ── מדדי מנוע: יוצאים כאן, בלי לפלוט SQL ───────────────────────────────
  if v_m.impl = 'engine' then
    return app.report_engine_measure(v_m, v_dimkey, v_bucket, p_from, p_to, v_limit);
  end if;

  -- ── FROM ────────────────────────────────────────────────────────────────
  v_from  := app.report_source_sql(v_src.key);
  v_where := app.report_source_where(v_src.key);
  if v_from is null or v_where is null then
    raise exception 'מקור נתונים אינו נתמך בשאילתה גנרית' using errcode = '22023';
  end if;

  -- ── ה-join-ים, כל אחד פעם אחת ──────────────────────────────────────────
  -- אותו join שמשמש גם את המדד וגם את הפילוח היה נפלט פעמיים ומתנגש בכינוי.
  if v_m.join_key is not null and not (v_m.join_key = any (v_seen)) then
    v_frag := app.report_join_sql(v_m.join_key);
    if v_frag is null then raise exception 'צירוף לא נתמך' using errcode = '22023'; end if;
    v_join := v_join || v_frag;  v_seen := v_seen || v_m.join_key;
  end if;
  if v_dimkey is not null and v_d.join_key is not null and not (v_d.join_key = any (v_seen)) then
    v_frag := app.report_join_sql(v_d.join_key);
    if v_frag is null then raise exception 'צירוף לא נתמך' using errcode = '22023'; end if;
    v_join := v_join || v_frag;  v_seen := v_seen || v_d.join_key;
  end if;

  -- ── ביטוי האגרגט ───────────────────────────────────────────────────────
  v_malias := app.report_join_alias(v_m.join_key, v_src.key);
  if v_m.expr_kind = 'coalesce_paid' then
    -- המדד היחיד שאינו agg(col): "ששולם" הוא coalesce של סכום ששולם על המחיר
    -- המוסכם, ורק על שורות שיש להן paid_at.
    v_aggsql := 'sum(coalesce(tct.paid_amount, tct.price)) filter (where tct.paid_at is not null)';
  else
    if v_malias is null then raise exception 'צירוף לא נתמך' using errcode = '22023'; end if;
    v_aggsql := app.report_agg_sql(v_agg, v_malias, v_m.col);
    if v_aggsql is null then raise exception 'סוג חישוב לא נתמך' using errcode = '22023'; end if;
  end if;

  -- ── ספירת נוכחות ───────────────────────────────────────────────────────
  -- price הוא not null default 0, ולכן SUM לבדו אינו מבחין בין "לא סוכם
  -- מחיר" ל-"סוכם אפס". היעדר השורה הוא האות היחיד, והמספרים האלה הם מה
  -- שמאפשר לכרטיס לומר "X משימות ללא תמחור" במקום לשקר בביטחון.
  if v_m.presence_col is not null and v_malias is not null then
    v_pres := format('count(*) filter (where %I.%I is not null)', v_malias, v_m.presence_col);
    if v_m.col is not null then
      v_zero := format('count(*) filter (where %I.%I = 0)', v_malias, v_m.col);
    end if;
  end if;

  -- ── קיבוץ ותוויות ──────────────────────────────────────────────────────
  if v_dimkey is null then
    v_group := 'null::text';
    v_label := quote_literal(v_m.label_he);
    v_color := 'null::text';
  else
    v_alias := app.report_join_alias(v_d.join_key, v_src.key);
    if v_alias is null then raise exception 'צירוף לא נתמך' using errcode = '22023'; end if;
    if v_d.kind = 'time' then
      -- התווית **חייבת** להיות אותו ביטוי כמו המפתח. הקיבוץ הוא על
      -- (key, label, color), ולכן תווית שהיא התאריך הגולמי הייתה מפצלת כל
      -- חודש חזרה לימים — הדליים היו נראים נכון והמספרים היו של יום בודד.
      v_group := format('date_trunc(%L, %I.%I)::date::text', v_bucket, v_alias, v_d.col);
      v_label := v_group;
    else
      v_group := format('%I.%I::text', v_alias, v_d.col);
      -- coalesce לתווית "ללא ..." — יחד עם ה-LEFT join, זה מה שמונע מהשורות
      -- חסרות-הסטטוס להיעלם בשקט מהתפלגות.
      v_label := format('coalesce(%I.%I::text, %L)', v_alias,
                        coalesce(v_d.label_col, v_d.col),
                        coalesce(v_d.null_label_he, '—'));
    end if;
    v_color := case when v_d.color_col is null then 'null::text'
                    else format('%I.%I::text', v_alias, v_d.color_col) end;
  end if;

  -- ── סינון: מזהים דרך %I, ערכים דרך $3 ──────────────────────────────────
  for f in select * from jsonb_array_elements(coalesce(p_spec -> 'filters', '[]'::jsonb)) loop
    select * into v_f from report_fields
     where key = f ->> 'field' and source_key = v_src.key and can_filter;
    if not found then
      return jsonb_build_object('rows', null,
               'meta', jsonb_build_object('unsupported', f ->> 'field'));
    end if;
    if not app.report_may_field(v_f) then
      return jsonb_build_object('rows', null, 'meta', jsonb_build_object('denied', true));
    end if;
    v_op := f ->> 'op';
    if v_op is null or not (v_op = any (v_f.allowed_ops)) then
      raise exception 'תנאי סינון לא נתמך' using errcode = '22023';
    end if;

    -- צורת הערך נבדקת לפני ההטלה, כדי שמפרט פגום ייתן 22023 מדובר ולא
    -- שגיאת המרה סתומה.
    v_val := coalesce(f -> 'value', 'null'::jsonb);
    if v_op in ('in', 'not_in') then
      if jsonb_typeof(v_val) <> 'array' or jsonb_array_length(v_val) = 0 then
        raise exception 'תנאי סינון דורש רשימת ערכים' using errcode = '22023'; end if;
    elsif v_op = 'between' then
      if jsonb_typeof(v_val) <> 'array' or jsonb_array_length(v_val) <> 2 then
        raise exception 'תנאי סינון דורש טווח של שני ערכים' using errcode = '22023'; end if;
    elsif v_op in ('is_null', 'is_not_null', 'is_true', 'is_false') then
      v_val := 'null'::jsonb;
    else
      if jsonb_typeof(v_val) in ('array', 'object', 'null') then
        raise exception 'תנאי סינון דורש ערך יחיד' using errcode = '22023'; end if;
    end if;

    v_alias := app.report_join_alias(v_f.join_key, v_src.key);
    if v_alias is null then raise exception 'צירוף לא נתמך' using errcode = '22023'; end if;
    if v_f.join_key is not null and not (v_f.join_key = any (v_seen)) then
      v_frag := app.report_join_sql(v_f.join_key);
      if v_frag is null then raise exception 'צירוף לא נתמך' using errcode = '22023'; end if;
      v_join := v_join || v_frag;  v_seen := v_seen || v_f.join_key;
    end if;

    v_frag := app.report_filter_sql(v_alias, v_f.col, v_f.col_type, v_op, v_idx);
    if v_frag is null then raise exception 'תנאי סינון לא נתמך' using errcode = '22023'; end if;
    v_where  := v_where || ' and ' || v_frag;
    v_params := v_params || jsonb_build_array(v_val);
    v_idx    := v_idx + 1;
  end loop;

  -- ── מיון ────────────────────────────────────────────────────────────────
  v_order := case when p_spec #>> '{sort,by}' = 'dimension' then 'key' else 'value' end
          || case when p_spec #>> '{sort,dir}' = 'asc' then ' asc' else ' desc nulls last' end;

  -- ── ההרכבה ──────────────────────────────────────────────────────────────
  -- ה-CTE מחושב פעם אחת ומשמש גם לשורות (חתוכות ב-limit) וגם לסכומים (על
  -- הכול), ולכן "סך הכול" אינו סכום העשירייה הראשונה.
  v_sql := format(
    'with g as (select %s as key, %s as label, %s as color, %s as value,'
    || ' count(*) as n, %s as present, %s as zero'
    || ' from %s%s where %s and %I.%I between $1 and $2%s)'
    || ' select jsonb_build_object('
    || '''rows'', coalesce((select jsonb_agg(row_to_json(x)) from'
    || ' (select key, label, color, round(value, 2) as value, n from g order by %s limit $4) x), ''[]''::jsonb),'
    || '''total'', round(coalesce(sum(value), 0), 2),'
    || '''row_count'', count(*), ''present'', coalesce(sum(present), 0),'
    || '''zero'', coalesce(sum(zero), 0), ''n_total'', coalesce(sum(n), 0)) from g',
    v_group, v_label, v_color, v_aggsql, v_pres, v_zero,
    v_from, v_join, v_where, v_src.alias, v_src.date_col,
    case when v_dimkey is null then '' else ' group by 1, 2, 3' end,
    v_order);

  execute v_sql into v_res using p_from, p_to, v_params, v_limit;

  return jsonb_build_object(
    'rows', coalesce(v_res -> 'rows', '[]'::jsonb),
    'meta', jsonb_build_object(
      'measure', v_m.key, 'agg', v_agg, 'unit', v_m.unit,
      'dimension', v_dimkey,
      'bucket', case when v_dimkey is not null and v_d.kind = 'time' then v_bucket end,
      'total', v_res -> 'total',
      'row_count', v_res -> 'row_count',
      'truncated', coalesce((v_res ->> 'row_count')::int, 0) > v_limit,
      'presence', case when v_m.presence_col is null then null else jsonb_build_object(
        'present', v_res -> 'present',
        'missing', coalesce((v_res ->> 'n_total')::numeric, 0)
                   - coalesce((v_res ->> 'present')::numeric, 0),
        'zero',    v_res -> 'zero') end,
      'fans_out', coalesce(v_dimkey is not null and v_d.fans_out, false),
      'estimated', coalesce(v_dimkey is not null and v_d.is_estimate, false) or v_m.is_estimate,
      'scope_note', v_src.scope_note_he,
      'scoped', false));
end $$;

-- ===== 6. שני העטיפים הציבוריים ============================================

/**
 * מסלול הטיוטה. מקבל את המפרט **כפרמטר**, ולכן אין צורך לשמור כלום כדי לצפות
 * מראש — בדיוק `preview_task_price(p_config, p_vars)` מ-0017. זה בטוח כי
 * המנוע מגדר כל שדה בעצמו, ולא משנה מה הלקוח שלח.
 */
create or replace function dashboard_widget_preview(p_spec jsonb, p_from date, p_to date)
returns jsonb language plpgsql stable security invoker set search_path = public as $$
begin
  if not app.has('dashboard.build_widget') then
    raise exception 'אין הרשאה לבניית ווידג׳ט' using errcode = '42501';
  end if;
  return app.report_run(p_spec, p_from, p_to);
end $$;

-- `dashboard_widgets_run` — מסלול הדשבורד — יושב ב-0045, אחרי הטבלה שהוא קורא.

-- RPC חדש אינו בטוח כברירת מחדל: 0008 ו-0012 מבטלים execute מ-anon ומ-public
-- לפי רשימת חתימות מפורשת, ואלה מצטרפות אליה.
revoke execute on function public.dashboard_widget_preview(jsonb, date, date) from anon, public;
revoke execute on function app.report_run(jsonb, date, date)                  from anon, public;

-- ===== 7. dashboard_sections קוראת עכשיו את אותו מימוש =====================
--
-- שלושת ענפי margin.* מוחלפים בקריאה לעוזרים שנוצרו למעלה. הפלט זהה — זו כל
-- הבדיקה: הטענות הקיימות ב-05_dashboard.sql ממשיכות לעבור ללא נגיעה.
--
-- שים לב לשינוי דק אחד ומכוון: העוזרים **זורקים** כשאין הרשאה, בזמן
-- ש-dashboard_sections צריכה להחזיר null. לכן התנאי `v_margin and not
-- v_scoped` נשאר בדיוק במקומו, והעוזר אינו נקרא כשהוא לא מתקיים.

create or replace function dashboard_sections(
  p_sections text[], p_from date, p_to date, p_opts jsonb default '{}'::jsonb)
returns jsonb language plpgsql stable security invoker set search_path = public as $$
declare
  v_key    text;
  v_out    jsonb := '{}'::jsonb;
  v_bucket text := case when p_opts ->> 'bucket' in ('day','week','month')
                        then p_opts ->> 'bucket' else 'week' end;
  v_limit  int  := greatest(1, least(coalesce((p_opts ->> 'limit')::int, 12), 50));
  v_val    jsonb;
  v_margin boolean := app.has_all(array['dashboard.margin','dashboard.payroll',
                                        'dashboard.contractor_cost','pricing.revenue']);
  v_scoped boolean := exists (select 1 from app.scope_rows('tasks') where scope_type <> 'all');
begin
  if p_from is null or p_to is null then
    raise exception 'חסר טווח תאריכים' using errcode = '22023';
  end if;
  if p_to < p_from then
    raise exception 'טווח תאריכים הפוך' using errcode = '22023';
  end if;
  if p_to - p_from > 400 then
    raise exception 'טווח גדול מדי לדשבורד' using errcode = '22023';
  end if;
  if coalesce(array_length(p_sections, 1), 0) > 40 then
    raise exception 'יותר מדי סקשנים בבקשה אחת' using errcode = '22023';
  end if;

  foreach v_key in array coalesce(p_sections, '{}'::text[]) loop
    v_val := null;

    if v_key = 'revenue.trend' and app.has('pricing.revenue') then
      select coalesce(jsonb_agg(row_to_json(x) order by x.bucket), '[]') into v_val from (
        select date_trunc(v_bucket, t.task_date)::date as bucket,
               round(sum(tp.price), 2) as total
          from task_pricing tp
          join tasks t on t.id = tp.task_id and t.deleted_at is null
         where t.task_date between p_from and p_to
         group by 1) x;

    elsif v_key = 'revenue.forecast' and app.has('pricing.revenue') then
      select jsonb_build_object(
        'total', round(coalesce(sum(tp.price), 0), 2),
        'tasks', count(*),
        'by_month', (select coalesce(jsonb_agg(row_to_json(y) order by y.bucket), '[]') from (
            select date_trunc('month', t2.task_date)::date as bucket,
                   round(sum(tp2.price), 2) as total
              from task_pricing tp2
              join tasks t2 on t2.id = tp2.task_id and t2.deleted_at is null
             where t2.task_date > current_date
             group by 1) y))
        into v_val
        from task_pricing tp
        join tasks t on t.id = tp.task_id and t.deleted_at is null
       where t.task_date > current_date;

    elsif v_key = 'pricing.quality' and app.has('pricing.view') then
      select jsonb_build_object(
        'total',    count(*),
        'unpriced', count(*) filter (where tp.task_id is null or tp.price = 0),
        'manual',   count(*) filter (where tp.is_manual),
        'auto',     count(*) filter (where tp.task_id is not null and not tp.is_manual and tp.price > 0),
        'unpriced_list', (select coalesce(jsonb_agg(row_to_json(y)), '[]') from (
            select t2.id, t2.task_date, coalesce(c2.name, t2.title, tt2.name) as label
              from tasks t2
              left join task_pricing tp2 on tp2.task_id = t2.id
              left join customers c2 on c2.id = t2.customer_id
              left join task_types tt2 on tt2.id = t2.task_type_id
             where t2.deleted_at is null and t2.task_date between p_from and p_to
               and (tp2.task_id is null or tp2.price = 0)
             order by t2.task_date desc limit 8) y))
        into v_val
        from tasks t
        left join task_pricing tp on tp.task_id = t.id
       where t.deleted_at is null and t.task_date between p_from and p_to;

    elsif v_key = 'cost.contractor' and app.has('dashboard.contractor_cost') then
      select jsonb_build_object(
        'expected',   round(coalesce(sum(tct.price), 0), 2),
        'paid',       round(coalesce(sum(coalesce(tct.paid_amount, tct.price))
                              filter (where tct.paid_at is not null), 0), 2),
        'unpaid',     round(coalesce(sum(tct.price) filter (where tct.paid_at is null), 0), 2),
        'unpaid_rows', count(*) filter (where tct.paid_at is null),
        'zero_rows',   count(*) filter (where tct.price = 0),
        'rows',        count(*),
        'aging', jsonb_build_object(
          'd0_30',  round(coalesce(sum(tct.price) filter (
                      where tct.paid_at is null and t.task_date > current_date - 30), 0), 2),
          'd31_60', round(coalesce(sum(tct.price) filter (
                      where tct.paid_at is null and t.task_date between current_date - 60 and current_date - 30), 0), 2),
          'd60',    round(coalesce(sum(tct.price) filter (
                      where tct.paid_at is null and t.task_date < current_date - 60), 0), 2)))
        into v_val
        from task_contractor_terms tct
        join tasks t on t.id = tct.task_id and t.deleted_at is null
       where t.task_date between p_from and p_to;

    elsif v_key = 'cost.by_contractor' and app.has('dashboard.contractor_cost') and app.has('contractors.view') then
      select coalesce(jsonb_agg(row_to_json(x)), '[]') into v_val from (
        select ct.name,
               round(sum(tct.price), 2) as expected,
               round(sum(coalesce(tct.paid_amount, tct.price)) filter (where tct.paid_at is not null), 2) as paid
          from task_contractor_terms tct
          join tasks t on t.id = tct.task_id and t.deleted_at is null
          join contractors ct on ct.id = tct.contractor_id
         where t.task_date between p_from and p_to
         group by ct.name order by 2 desc limit v_limit) x;

    elsif v_key = 'cost.contractor_unpaid' and app.has('dashboard.contractor_cost')
          and app.has('contractors.view_pricing') then
      select coalesce(jsonb_agg(row_to_json(x)), '[]') into v_val from (
        select t.id as task_id, t.task_date, ct.name as contractor, tct.price
          from task_contractor_terms tct
          join tasks t on t.id = tct.task_id and t.deleted_at is null
          join contractors ct on ct.id = tct.contractor_id
         where tct.paid_at is null and tct.price > 0 and t.task_date between p_from and p_to
         order by t.task_date limit v_limit) x;

    elsif v_key = 'cost.payroll' and app.has('dashboard.payroll') then
      v_val := app.payroll_summary(p_from, p_to);

    elsif v_key = 'cost.payroll_by_worker' and app.has('dashboard.payroll')
          and app.has('dashboard.all_workers') then
      v_val := app.payroll_by_worker(p_from, p_to, v_limit);

    elsif v_key = 'cost.payroll_trend' and app.has('dashboard.payroll') then
      v_val := app.payroll_trend(p_from, p_to, v_bucket);

    -- ── רווח גולמי: מימוש אחד, שני קוראים ─────────────────────────────────
    elsif v_key = 'margin.summary' and v_margin and not v_scoped then
      v_val := app.margin_summary(p_from, p_to);

    elsif v_key = 'margin.trend' and v_margin and not v_scoped then
      v_val := app.margin_trend(p_from, p_to, v_bucket);

    elsif v_key = 'margin.by_customer' and v_margin and not v_scoped and app.has('customers.view') then
      v_val := app.margin_by_customer(p_from, p_to, v_limit);

    elsif v_key = 'tasks.by_type' then
      select coalesce(jsonb_agg(row_to_json(x)), '[]') into v_val from (
        select tt.name, count(*) as cnt
          from tasks t join task_types tt on tt.id = t.task_type_id
         where t.deleted_at is null and t.task_date between p_from and p_to
         group by tt.name order by 2 desc limit v_limit) x;

    elsif v_key = 'tasks.by_method' then
      select coalesce(jsonb_agg(row_to_json(x)), '[]') into v_val from (
        select em.name, count(*) as cnt
          from tasks t join execution_methods em on em.id = t.execution_method_id
         where t.deleted_at is null and t.task_date between p_from and p_to
         group by em.name order by 2 desc limit v_limit) x;

    elsif v_key = 'tasks.trend' then
      select coalesce(jsonb_agg(row_to_json(x) order by x.bucket), '[]') into v_val from (
        select bucket, sum(tasks) as tasks, sum(events) as events from (
          select date_trunc(v_bucket, t.task_date)::date as bucket, count(*) as tasks, 0 as events
            from tasks t where t.deleted_at is null and t.task_date between p_from and p_to
           group by 1
          union all
          select date_trunc(v_bucket, e.event_date)::date, 0, count(*)
            from events e where e.deleted_at is null and e.event_date between p_from and p_to
           group by 1) u
         group by bucket) x;

    elsif v_key = 'tasks.understaffed'
          and (app.has('dashboard.all_workers') or app.has('tasks.assign.worker')) then
      select jsonb_build_object(
        'count', count(*),
        'rows', (select coalesce(jsonb_agg(row_to_json(y)), '[]') from (
            select t2.id, t2.task_date, coalesce(c2.name, t2.title) as label,
                   t2.worker_count as needed,
                   (select count(*) from task_assignments a2
                     where a2.task_id = t2.id and a2.role = 'worker') as assigned
              from tasks t2
              left join customers c2 on c2.id = t2.customer_id
              join statuses s2 on s2.id = t2.status_id
             where t2.deleted_at is null and t2.task_date between p_from and p_to
               and not s2.is_terminal and t2.worker_count > 0
               and (select count(*) from task_assignments a3
                     where a3.task_id = t2.id and a3.role = 'worker') < t2.worker_count
             order by t2.task_date limit 8) y))
        into v_val
        from tasks t
        join statuses s on s.id = t.status_id
       where t.deleted_at is null and t.task_date between p_from and p_to
         and not s.is_terminal and t.worker_count > 0
         and (select count(*) from task_assignments a
               where a.task_id = t.id and a.role = 'worker') < t.worker_count;

    elsif v_key = 'tasks.no_truck' then
      select jsonb_build_object('count', count(*)) into v_val
        from tasks t join statuses s on s.id = t.status_id
       where t.deleted_at is null and t.task_date between p_from and p_to
         and not s.is_terminal
         and coalesce(cardinality(t.truck_ids), 0) = 0 and t.truck_free_text is null;

    elsif v_key = 'fleet.utilization' then
      select coalesce(jsonb_agg(row_to_json(x)), '[]') into v_val from (
        select tr.name,
               count(distinct t.task_date) as days,
               count(*) as tasks
          from tasks t
          cross join lateral unnest(t.truck_ids) as u(truck_id)
          join trucks tr on tr.id = u.truck_id
         where t.deleted_at is null and t.task_date between p_from and p_to
         group by tr.name order by 2 desc limit v_limit) x;

    elsif v_key = 'events.by_customer' and app.has('customers.view') then
      select coalesce(jsonb_agg(row_to_json(x)), '[]') into v_val from (
        select c.name, c.color, count(*) as cnt
          from events e join customers c on c.id = e.customer_id
         where e.deleted_at is null and e.event_date between p_from and p_to
         group by c.name, c.color order by 3 desc limit v_limit) x;

    elsif v_key = 'events.funnel' then
      select coalesce(jsonb_agg(row_to_json(x)), '[]') into v_val from (
        select s.name, s.color, count(*) as cnt
          from events e join statuses s on s.id = e.status_id
         where e.deleted_at is null and e.event_date between p_from and p_to
         group by s.name, s.color, s.sort_order order by s.sort_order) x;

    elsif v_key = 'events.volume' and app.has('customers.view') then
      select jsonb_build_object(
        'volume_m', round(coalesce(sum(e.volume_m), 0), 2),
        'trucks',   coalesce(sum(e.truck_count), 0),
        'events',   count(*),
        'by_customer', (select coalesce(jsonb_agg(row_to_json(y)), '[]') from (
            select c2.name, c2.color,
                   round(coalesce(sum(e2.volume_m), 0), 2) as volume_m,
                   coalesce(sum(e2.truck_count), 0) as trucks
              from events e2 join customers c2 on c2.id = e2.customer_id
             where e2.deleted_at is null and e2.event_date between p_from and p_to
             group by c2.name, c2.color order by 3 desc limit v_limit) y))
        into v_val
        from events e
       where e.deleted_at is null and e.event_date between p_from and p_to;

    elsif v_key = 'customers.leaderboard' and app.has('customers.view') then
      select coalesce(jsonb_agg(row_to_json(x) order by x.events desc), '[]') into v_val from (
        select c.name, c.color,
               count(distinct e.id) as events,
               count(distinct t.id) as tasks,
               case when app.has('pricing.revenue')
                    then round(coalesce(sum(distinct_price.price), 0), 2) end as revenue,
               max(e.event_date) as last_event
          from customers c
          left join events e on e.customer_id = c.id and e.deleted_at is null
               and e.event_date between p_from and p_to
          left join tasks t on t.customer_id = c.id and t.deleted_at is null
               and t.task_date between p_from and p_to
          left join lateral (
            select tp.price from task_pricing tp where tp.task_id = t.id) distinct_price on true
         where c.deleted_at is null
         group by c.name, c.color
        having count(distinct e.id) > 0 or count(distinct t.id) > 0
         limit v_limit) x;

    elsif v_key = 'customers.inactive' and app.has('customers.view') then
      select coalesce(jsonb_agg(row_to_json(x)), '[]') into v_val from (
        select c.name, c.color,
               (select max(e2.event_date) from events e2
                 where e2.customer_id = c.id and e2.deleted_at is null) as last_event
          from customers c
         where c.deleted_at is null and c.is_active
           and not exists (select 1 from events e where e.customer_id = c.id
                             and e.deleted_at is null and e.event_date between p_from and p_to)
         order by 3 desc nulls last limit v_limit) x;

    elsif v_key = 'attendance.hours' and app.has('attendance.view_all') then
      select jsonb_build_object(
        'actual_hours', round(coalesce(sum(e.actual_hours), 0), 2),
        'shifts',       count(*),
        'workers',      count(distinct e.profile_id))
        into v_val
        from attendance_entries e
       where e.deleted_at is null and e.status = 'approved'
         and e.work_date between p_from and p_to;

    elsif v_key = 'attendance.hours_by_worker' and app.has('attendance.view_all') then
      select coalesce(jsonb_agg(row_to_json(x)), '[]') into v_val from (
        select p.full_name as name, round(sum(e.actual_hours), 2) as hours
          from attendance_entries e join profiles p on p.id = e.profile_id
         where e.deleted_at is null and e.status = 'approved'
           and e.work_date between p_from and p_to
         group by p.full_name order by 2 desc nulls last limit v_limit) x;

    elsif v_key = 'attendance.pending' and app.has('attendance.approve_entry') then
      select jsonb_build_object(
        'count', count(*),
        'hours', round(coalesce(sum(e.actual_hours), 0), 2),
        'rows', (select coalesce(jsonb_agg(row_to_json(y)), '[]') from (
            select e2.id, e2.work_date, p2.full_name, e2.actual_hours
              from attendance_entries e2 join profiles p2 on p2.id = e2.profile_id
             where e2.deleted_at is null and e2.status = 'pending'
             order by e2.work_date limit 8) y))
        into v_val
        from attendance_entries e
       where e.deleted_at is null and e.status = 'pending';

    elsif v_key = 'attendance.flags' and app.has('attendance.view_all') then
      select coalesce(jsonb_agg(row_to_json(x)), '[]') into v_val from (
        select f as flag, count(*) as cnt
          from attendance_entries e, unnest(e.flags) as f
         where e.deleted_at is null and e.work_date between p_from and p_to
         group by f order by 2 desc) x;

    elsif v_key = 'hr.headcount' and app.has('dashboard.all_workers') then
      select jsonb_build_object(
        'active', count(*) filter (where p.is_active),
        'staff',  count(*) filter (where p.is_active and p.user_kind = 'staff'))
        into v_val
        from profiles p where p.deleted_at is null;

    end if;

    v_out := v_out || jsonb_build_object(v_key, v_val);
  end loop;

  return v_out;
end $$;

revoke execute on function public.dashboard_sections(text[], date, date, jsonb) from anon, public;

-- ===== 8. אינדקסים =========================================================
-- הבונה הופך group-by שרירותי לנגיש, וזה מגיע לצירופים ששום ווידג׳ט סטטי לא
-- ביקש. `statement_timeout = 8s` על authenticated נשאר רשת הביטחון לשאר.
create index if not exists tasks_exec_date_idx
  on tasks (execution_method_id, task_date) where deleted_at is null;
create index if not exists tasks_type_date_idx
  on tasks (task_type_id, task_date) where deleted_at is null;
create index if not exists events_status_date_idx
  on events (status_id, event_date) where deleted_at is null;
