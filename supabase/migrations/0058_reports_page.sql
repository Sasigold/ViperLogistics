-- 0058: מסך הדוחות
--
-- מנוע הדוחות (0043-0044) נבנה עבור הדשבורד, אבל אין בו שום דבר דשבורדי:
-- קטלוג, מפרט, והרצה מגודרת. מסך דוחות ייעודי — תבניות מוכנות, פילוחים
-- מרובים במקביל וייצוא — הוא צרכן שני של אותו מנוע, והקובץ הזה נותן לו את
-- שלושת הדברים שחסרים לו: שני מפתחות הרשאה, כניסה ציבורית משלו, ושער פנימי
-- שמכיר בשני המסכים.
--
-- מה שהקובץ הזה **אינו** עושה: הוא אינו מרחיב גישה לנתון כלשהו. כל מקור, מדד,
-- פילוח ושדה מגודרים בנפרד בתוך `app.report_run`, שהיא security invoker —
-- מפתח `reports.view` פותח את הדלת למסך, והמנוע ממשיך להכריע נתון-נתון.

-- ===== 1. המודול והמפתחות ==================================================

select app.register_module('reports', 'דוחות',
  'תבניות דוח, פילוחים חופשיים וייצוא', 'BarChart3', 15);

-- `implied_by 'dashboard.view'` — default_allowed שלו false (0011), ולכן אין
-- כאן את הדליפה ש-0042 מתעדת: השרשרת נעצרת במי שבאמת מחזיק את מפתח הדשבורד.
-- התוצאה ביום המיגרציה: כל מי שרואה דשבורד רואה דוחות, ואיש אינו מקבל נתון
-- שלא ראה אתמול. מענק עתידי של `reports.view` לבדו פותח את המסך בלי הדשבורד.
select app.register_permission(
  'reports.view', 'reports', 'צפייה בדוחות',
  'מסך הדוחות: תבניות מוכנות ופילוחים חופשיים מעל מנוע הדוחות',
  'access', false, false,
  array['staff']::user_kind[], 'dashboard.view', 10);

select app.register_permission(
  'reports.export', 'reports', 'ייצוא דוחות',
  'הורדת הדוח הנוכחי כ-Excel, CSV או הדפסה',
  'action', false, false,
  array['staff']::user_kind[], 'dashboard.export', 20);

-- ===== 2. השער הפנימי מכיר בשני המסכים =====================================
--
-- `app.report_run` נפתחה ב-0044 עם `app.require('dashboard.view')` — נכון לזמן
-- שהדשבורד היה הצרכן היחיד. מי שיוענק לו `reports.view` בלבד היה עובר את
-- העטיפה החדשה למטה ונופל כאן, ולכן השורה הראשונה מתרחבת ל-או-בין-שניים.
-- **שאר הגוף מועתק מ-0044 מילה במילה** — הבדיקות של 05/06 הן ההוכחה שדבר
-- אחר לא זז.

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
  -- שני מסכים, מנוע אחד: מפתח הדשבורד או מפתח הדוחות, כל אחד מהם מספיק.
  if not (app.has('dashboard.view') or app.has('reports.view')) then
    raise exception 'אין הרשאה לדוחות' using errcode = '42501';
  end if;

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

-- create or replace משמר את ההענקות של 0044 (revoke מ-anon/public, grant
-- ל-authenticated) — אין צורך לחזור עליהן.

-- ===== 3. הכניסה הציבורית של מסך הדוחות ====================================
--
-- אותה צורה בדיוק כמו `dashboard_widget_preview` (0044): המפרט מגיע כפרמטר,
-- שום דבר לא נשמר, והמנוע מגדר כל שדה בעצמו. ההבדל היחיד הוא המפתח שעל הדלת —
-- צפייה בדוחות היא קריאה, לא בנייה, ולכן היא אינה נשענת על
-- `dashboard.build_widget`.

create or replace function public.reports_run(p_spec jsonb, p_from date, p_to date)
returns jsonb language plpgsql stable security invoker set search_path = public as $$
begin
  if not app.has('reports.view') then
    raise exception 'אין הרשאה לדוחות' using errcode = '42501';
  end if;
  return app.report_run(p_spec, p_from, p_to);
end $$;

-- RPC חדש אינו בטוח כברירת מחדל — אותה רשימה מפורשת של 0008/0012/0044.
revoke execute on function public.reports_run(jsonb, date, date) from anon, public;
grant  execute on function public.reports_run(jsonb, date, date) to authenticated;
