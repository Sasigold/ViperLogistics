-- 0132: ראש צוות אצל ארקו — בכל מקרה שאינו הובלה בלבד
--
-- הדיווח: **"להגדיר מחדש בונוס לראש צוות אצל ארקו בכל מקרה שזה לא אופן ביצוע
-- הובלה בלבד."**
--
-- ‏0119 הוסיפה לשורת "ראש צוות" את התנאי `is_transport_only is_false`, אבל
-- השאירה לצדו את התנאי המקורי מהתבנית — `requires_team_lead is_true`. התוצאה
-- היא **וגם**: השורה נגבית רק כשמישהו סימן במפורש "נדרש ראש צוות" *וגם*
-- אופן הביצוע אינו הובלה בלבד. ‏`requires_team_lead` הוא דריסה ידנית שברוב
-- המשימות נשארת NULL, ולכן בפועל השורה כמעט אינה נגבית.
--
-- מה שנאמר בדיווח הוא תנאי אחד: **אופן הביצוע**. ולכן `requires_team_lead`
-- יורד מהשורה של ארקו, ו-`is_transport_only is_false` נשאר לבדו.
--
-- אותו דפוס של 0119 מילה במילה — אותו מעבר על שני המערכים, אותו נרמול, אותה
-- כתיבה רק כשבאמת השתנה משהו — ומאותם נימוקים: הכלל הוא **נתון ולא קוד**
-- (‏`app.default_pricing_config` אינה נגעת, כדי שלקוח חדש לא יירש תנאי מסחרי
-- של ארקו), אין חישוב מחדש מפורש (הטריגר על `customer_pricing_rules` מתמחר
-- את העתיד; היסטוריה אינה נכתבת מחדש), והכול הגנתי: אין לקוח כזה ⇒ אין שורות;
-- התנאי כבר במצבו הסופי ⇒ אין כתיבה.

do $$
declare
  r        record;
  v_arr    jsonb;
  v_elem   jsonb;
  v_when   jsonb;
  v_all    jsonb;
  v_out    jsonb;
  v_config jsonb;
  v_touched boolean;
  k        text;
begin
  for r in
    select cpr.id, cpr.config
      from customer_pricing_rules cpr
      join customers c on c.id = cpr.customer_id
     where c.name ilike '%ארקו%' and c.deleted_at is null
  loop
    v_config  := r.config;
    v_touched := false;

    foreach k in array array['after_workers', 'components'] loop
      v_arr := v_config -> k;
      if v_arr is null or jsonb_typeof(v_arr) <> 'array' then continue; end if;

      v_out := '[]'::jsonb;
      for v_elem in select * from jsonb_array_elements(v_arr) loop
        if v_elem ->> 'id' = 'team_lead' then
          v_when := v_elem -> 'when';

          if v_when is null or jsonb_typeof(v_when) = 'null' or v_when = '{}'::jsonb then
            v_when := jsonb_build_object('all', '[]'::jsonb);
          elsif not (v_when ? 'all') then
            v_when := jsonb_build_object('all', jsonb_build_array(v_when));
          end if;

          -- מסננים החוצה את התנאי על `requires_team_lead`, ומשאירים את השאר.
          select coalesce(jsonb_agg(t), '[]'::jsonb) into v_all
            from jsonb_array_elements(v_when -> 'all') t
           where t ->> 'field' is distinct from 'requires_team_lead';

          -- ומוודאים שהתנאי היחיד שכן צריך להיות שם — קיים (0119).
          if not exists (select 1 from jsonb_array_elements(v_all) t
                          where t ->> 'field' = 'is_transport_only') then
            v_all := v_all || jsonb_build_object('field', 'is_transport_only', 'op', 'is_false');
          end if;

          if v_all is distinct from (v_when -> 'all') then
            v_elem := jsonb_set(v_elem, '{when}', jsonb_set(v_when, '{all}', v_all));
            v_touched := true;
          end if;
        end if;
        v_out := v_out || jsonb_build_array(v_elem);
      end loop;

      v_config := jsonb_set(v_config, array[k], v_out);
    end loop;

    if v_touched then
      update customer_pricing_rules set config = v_config where id = r.id;
    end if;
  end loop;
end $$;
