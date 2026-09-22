-- 0191: תווית הסטטוס נועלת את הנתיב שלה
--
-- ‏`app.viperflow_status_label` נולדה ב-0190 בלי `set search_path`, והיא
-- היחידה בסכימה `app` שכך. היא אינה נוגעת בשום טבלה ולכן אין בה מה לחטוף,
-- אבל הכלל כאן אינו "איפה זה מסוכן" אלא "כל פונקציה נועלת את הנתיב" — חריג
-- אחד הוא מה שמלמד שאפשר. ‏`''` ולא `public`: היא באמת אינה מחפשת דבר.
create or replace function app.viperflow_status_label(p_status text)
returns text language sql immutable set search_path = '' as $$
  select case p_status
    when 'draft'     then 'טיוטה'
    when 'confirmed' then 'מאושרת'
    when 'picked'    then 'נאספה'
    when 'delivered' then 'נמסרה'
    when 'returned'  then 'הוחזרה'
    when 'cancelled' then 'בוטלה'
    else coalesce(p_status, '') end;
$$;

revoke execute on function app.viperflow_status_label(text)
  from anon, authenticated, public;
