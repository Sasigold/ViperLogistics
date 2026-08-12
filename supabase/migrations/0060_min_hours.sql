-- 0060: מינימום שעות לחיוב במודל worker_hours
--
-- לקוח שמזמין צוות לשלוש שעות עדיין מוציא יום עבודה: העובדים נסעו, התארגנו,
-- וחזרו. לכן למחשבון "שעות ועובדים" נוסף `min_hours` — רצפה על סכום רכיבי
-- הזמן. אם השטח + הנסיעות + ההפסקה הסתכמו ל-6 ומעלה, שום דבר לא משתנה; אם
-- הסתכמו לפחות, ההשלמה נרשמת כשורת זמן ("השלמה למינימום שעות") וסך השעות
-- עולה לרצפה, לפני ההכפלה בתעריף ובעובדים.
--
-- זה מקביל ל-min_price שקיים בזנב המשותף, רק ברובד השעות: min_price מרים
-- את המחיר הסופי, min_hours מרים את בסיס הזמן שכל השאר נגזר ממנו.
--
-- קונפיגים קיימים אינם משתנים: מחשבון בלי המפתח מתנהג בדיוק כפי שהתנהג.
-- מי שרוצה את הרצפה מגדיר אותה במחשבון של הלקוח; מחשבון חדש נולד עם 6
-- מהבונה בפרונט, לא מכאן.
--
-- הפונקציה נכתבת כאן במלואה כי אין דרך אחרת להחליף גוף של פונקציה ב-SQL.
-- שאר הגוף זהה ל-0050; מה שהשתנה הוא בלוק המינימום אחרי סכימת רכיבי הזמן.
-- set search_path נכתב בהגדרה עצמה, כי CREATE OR REPLACE מפיל את מה
-- ש-0018 קיבע ב-ALTER.

create or replace function app.price_calc(config jsonb, vars jsonb)
returns jsonb language plpgsql immutable set search_path = public as $$
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
  v_add          numeric;
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

    -- מינימום שעות לחיוב: רכיבי זמן שהסתכמו לפחות מהרצפה מושלמים אליה,
    -- וההשלמה נרשמת כשורת זמן כדי שהפירוט יסביר את המספר.
    if config ? 'min_hours' and jsonb_typeof(config -> 'min_hours') = 'number'
       and v_hours < app.jnum(config, 'min_hours', 0) then
      v_h := app.jnum(config, 'min_hours', 0) - v_hours;
      v_hours := app.jnum(config, 'min_hours', 0);
      v_hour_lines := v_hour_lines || jsonb_build_object(
        'id', 'min_hours', 'label', 'השלמה למינימום שעות', 'hours', round(v_h, 2));
    end if;

    -- ── מחיר לעובד ───────────────────────────────────────────────────────
    v_rate := app.jnum(config, 'hour_rate', 0);
    v_per_worker := v_hours * v_rate + app.jnum(config, 'per_worker_fee', 0);

    -- ── כמות עובדים, כולל תוספות כמו "אין חניה ⇒ עובד נוסף" ─────────────
    -- לתוספת שתי צורות. 'fixed' היא המקורית: מספר עובדים קבוע כשהתנאי
    -- מתקיים. 'per_unit' סופרת לפי נתון — "אין חניה ⇒ עובד לכל משאית" — כי
    -- הכאב של חנייה רחוקה גדל עם כמות המשאיות ולא עם עצם קיומה.
    -- 'rounding' קיים כי חצי עובד אינו אדם: 0.5 לכל משאית על שלוש משאיות
    -- הוא 1.5, ומי שמזמין רוצה לומר אם זה 1 או 2.
    v_base_workers := app.price_var_num(
      v_vars, coalesce(config -> 'workers' ->> 'input', 'worker_count'));
    v_workers := v_base_workers;
    for c in select * from jsonb_array_elements(
                 coalesce(config -> 'workers' -> 'adjustments', '[]'::jsonb)) loop
      if app.price_cond(c -> 'when', v_vars) then
        if coalesce(c ->> 'kind', 'fixed') = 'per_unit' then
          v_n   := app.price_var_num(v_vars, c ->> 'input');
          v_add := app.jnum(c, 'add', 0) * v_n;
          case coalesce(c ->> 'rounding', 'none')
            when 'up'      then v_add := ceil(v_add);
            when 'down'    then v_add := floor(v_add);
            when 'nearest' then v_add := round(v_add);
            else null;
          end case;
          v_label := format('%s × %s = %s עובדים',
                            trim_scale(v_n), trim_scale(app.jnum(c, 'add', 0)),
                            trim_scale(v_add));
        else
          v_add   := app.jnum(c, 'add', 0);
          v_label := format('%s עובדים', trim_scale(v_add));
        end if;

        v_workers := v_workers + v_add;
        v_lines := v_lines || jsonb_build_object(
          'id', c ->> 'id', 'label', c ->> 'label', 'amount', null,
          'detail', v_label);
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
