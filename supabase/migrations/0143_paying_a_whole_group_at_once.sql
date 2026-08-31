-- 0143: משלמים לקבלן על קבוצה שלמה בפעם אחת
--
-- הדיווח: **"במשימות ותשלומים של קבלנים, שתהיה אפשרות להדגיש קבוצה ולסמן
-- שולם."**
--
-- הסימון עצמו כבר קיים — שורה אחת, לחיצה אחת — ומי שמשלם לקבלן על חודש
-- שלם עושה אותה עשרים פעם. הבחירה המרובה יושבת כולה במסך, אבל הכתיבה לא
-- יכולה לשבת שם: ‏`paid_amount` הוא ה-`price` **של אותה שורה**, ולכן
-- `update ... in (...)` יחיד אינו יכול לכתוב אותו נכון, ולולאה של עשרים
-- בקשות אינה אטומית — חצי קבוצה מסומנת וחצי לא.
--
-- הפונקציה היא **security invoker** (ברירת המחדל), ולכן היא אינה מרחיבה
-- דבר: ‏`tct_write` מ-0012 ממשיכה להכריע מי רשאי לכתוב — אדמין,
-- `contractors.edit_pricing` או `contractors.mark_paid` — ושורה שהמדיניות
-- אינה פותחת פשוט אינה מתעדכנת. הערך המוחזר הוא מספר השורות שנגעו בהן
-- בפועל, כדי שהמסך יוכל לומר את האמת.
--
-- ‏`p_contractor_id` הוא הגדר, ולא נוחות: מאז ריבוי הקבלנים (0096) למשימה
-- יכולות להיות כמה שורות terms, ומסמנים תשלום רק על השורה של הקבלן שעל
-- המסך — בדיוק כמו הסימון של שורה אחת.

create or replace function set_contractor_terms_paid(
  p_contractor_id uuid,
  p_task_ids      uuid[],
  p_paid          boolean)
returns int
language plpgsql
set search_path = public as $$
declare v_count int;
begin
  if p_contractor_id is null or p_task_ids is null or array_length(p_task_ids, 1) is null then
    return 0;
  end if;

  update task_contractor_terms
     set paid_at     = case when p_paid then now() end,
         paid_amount = case when p_paid then price end
   where contractor_id = p_contractor_id
     and task_id = any(p_task_ids);

  get diagnostics v_count = row_count;
  return v_count;
end $$;

-- ‏0126: ‏anon אינו מריץ RPC של המשרד.
revoke execute on function set_contractor_terms_paid(uuid, uuid[], boolean) from anon;
grant  execute on function set_contractor_terms_paid(uuid, uuid[], boolean) to authenticated;
