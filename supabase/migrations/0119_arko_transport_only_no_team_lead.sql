-- 0119: ארקו — הובלה בלבד אינה נושאת ראש צוות
--
-- הכלל עצמו הוא **נתון ולא קוד**, כמו כל הבדל אחר בין לקוחות במערכת: 0118
-- פתחה את המשתנה ואת עורך התנאים, וכאן רק מסומן התנאי אצל הלקוח שביקש אותו.
-- אין כאן שום דבר שהמשרד לא היה יכול לעשות במסך התמחור — וזו הנקודה.
--
-- **‏`app.default_pricing_config` אינה משתנה.** התבנית היא מה שמחשבון של לקוח
-- **חדש** נולד איתו, ו"הובלה בלבד אינה נושאת ראש צוות" הוא תנאי מסחרי של
-- ארקו ולא מדיניות הבית. הטמעה בתבנית הייתה משנה בשקט את משמעות המחשבון של
-- כל לקוח עתידי, ונוגעת בפונקציה שמכפילה את אותו בלוק פעמיים (הקמה ופירוק)
-- ומזינה מספרים מקובעים בבדיקת התמחור — סיכון מרבי לדרישה שאינה קיימת.
--
-- **ואין כאן חישוב מחדש מפורש.** הטריגר על `customer_pricing_rules` (0017)
-- כבר מתמחר מחדש את המשימות העתידיות של אותו לקוח וסוג משימה; היסטוריה
-- אינה נכתבת מחדש, כי "אירוע שעבר כבר עשוי להיות מחויב, ושכתוב שקט שלו הוא
-- לא תיקון אלא הפתעה". מי שכן רוצה — מריץ `recalculate_customer_prices`
-- מהמסך, במפורש.
--
-- **הגנתי לכל אורכו:** אין לקוח בשם הזה (למשל באשכול הבדיקות) ⇒ אין שורות
-- ⇒ הצלחה שקטה. התנאי כבר קיים ⇒ אין כתיבה, ולכן גם אין הרצת חישוב מחדש
-- מיותרת. תנאים אחרים על אותה שורה ⇒ נשמרים; מתווספים אליהם ולא במקומם.

do $$
declare
  r        record;
  v_arr    jsonb;
  v_elem   jsonb;
  v_when   jsonb;
  v_new    jsonb;
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

    -- שני המערכים: `after_workers` הוא מקומה של השורה במודל worker_hours,
    -- ו-`components` במודל line_items. כיסוי שניהם פירושו שהכלל שורד גם
    -- החלפת מודל בעתיד.
    foreach k in array array['after_workers', 'components'] loop
      v_arr := v_config -> k;
      if v_arr is null or jsonb_typeof(v_arr) <> 'array' then continue; end if;

      v_out := '[]'::jsonb;
      for v_elem in select * from jsonb_array_elements(v_arr) loop
        if v_elem ->> 'id' = 'team_lead' then
          v_when := v_elem -> 'when';

          -- נרמול ל-{"all": [...]}. ‏`any` נעטף ולא נמחק: ‏all[ any[...] ]
          -- שקול ל-any[...], ולכן שום כלל אינו משנה משמעות.
          if v_when is null or jsonb_typeof(v_when) = 'null' or v_when = '{}'::jsonb then
            v_when := jsonb_build_object('all', '[]'::jsonb);
          elsif not (v_when ? 'all') then
            v_when := jsonb_build_object('all', jsonb_build_array(v_when));
          end if;

          -- idempotent: כל אזכור של המשתנה, בכל אופרטור, נחשב "כבר מוגדר"
          if not exists (select 1 from jsonb_array_elements(v_when -> 'all') t
                          where t ->> 'field' = 'is_transport_only') then
            v_new := v_when -> 'all' ||
                     jsonb_build_object('field', 'is_transport_only', 'op', 'is_false');
            v_when := jsonb_set(v_when, '{all}', v_new);
            v_elem := jsonb_set(v_elem, '{when}', v_when);
            v_touched := true;
          end if;
        end if;
        v_out := v_out || jsonb_build_array(v_elem);
      end loop;

      v_config := jsonb_set(v_config, array[k], v_out);
    end loop;

    -- כתיבה רק כשבאמת השתנה משהו: כתיבה ריקה עדיין מפעילה את טריגר החישוב
    if v_touched then
      update customer_pricing_rules set config = v_config where id = r.id;
    end if;
  end loop;
end $$;
