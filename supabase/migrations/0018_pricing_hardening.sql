-- 0018: הקשחת המשטח שנוסף ב-0017
--
-- שני דברים ש-0017 החמיצה, ושהיועץ של Supabase סימן. שניהם כבר היו לקובץ
-- הזה תקדים — 0008 ו-0012 עשו בדיוק את אותו הדבר לגל הפונקציות שקדם — ולכן
-- זו לא החלטה חדשה אלא השלמה של שגרה קיימת.

-- ===== 1. נעילת search_path =================================================
-- פונקציה בלי search_path מקובע יורשת אותו מהקורא. הפונקציות כאן טהורות
-- ואינן SECURITY DEFINER בעצמן, אבל הן נקראות מתוך כאלה (app.recalc_task_price,
-- preview_task_price), ואז search_path עוין הופך אותן לנתיב הרחבת הרשאות:
-- די בסכימה קודמת ב-path שמגדירה round() או jsonb_array_elements() משלה.
--
-- הפונקציות שנוצרו ב-0017 עם security definer כבר קיבעו אותו בהגדרה עצמה;
-- אלה שלמטה הן היחידות שנשארו פתוחות.

alter function app.point_in_polygon(double precision, double precision, jsonb)
  set search_path = public;
alter function app.haversine_km(double precision, double precision, double precision, double precision)
  set search_path = public;
alter function app.jnum(jsonb, text, numeric)             set search_path = public;
alter function app.price_var_num(jsonb, text)             set search_path = public;
alter function app.price_cond(jsonb, jsonb)               set search_path = public;
alter function app.price_calc(jsonb, jsonb)               set search_path = public;
alter function app.default_pricing_config(text)           set search_path = public;
alter function app.task_pricing_lock()                    set search_path = public;

-- ===== 2. anon מחוץ ל-RPCs החדשים ==========================================
-- כל אחת מהן פותחת ב-app.require(...), ולכן anon היה נופל בה ממילא. הרווח
-- כאן הוא שהוא לא מגיע עד לשם: הפונקציה כבר לא מופיעה ב-API הפתוח, ולא
-- נשארת תלויה בכך שאיש לא ישכח את השורה הראשונה בגרסה הבאה שלה.

do $$
declare fn text;
begin
  foreach fn in array array[
    'preview_task_price(jsonb, jsonb)',
    'recalculate_task_price(uuid)',
    'recalculate_customer_prices(uuid, date)',
    'zone_for_location(uuid, double precision, double precision)',
    'pricing_config_template(uuid)']
  loop
    execute format('revoke execute on function public.%s from anon, public', fn);
  end loop;
end $$;
