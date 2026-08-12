-- 0059: רווחיות לקוחות — ה-RPC של הדף
--
-- דף P&L פר לקוח: הכנסות, עלות קבלנים, שכר משויך, רווח גולמי ואחוזו. כל
-- החשבון כבר קיים — `app.margin_by_customer` (0044) מחזיר את שלושת הרכיבים
-- לכל לקוח ו-`app.margin_summary` את השורה התחתונה — והקובץ הזה רק מרכיב
-- מהם תשובה אחת למסך, עם החיסור והאחוז מחושבים **כאן, בשרת**: הכלל של
-- exportDashboard — שום מספר אינו מחושב בלקוח — מחייב שגם רווח-פר-שורה יגיע
-- מוכן.
--
-- הרשאות, שתי שכבות כמו reports_run (0058):
--   • `reports.view` על הדלת — בלעדיו 42501, כמו כל מסך.
--   • צרור הרווח (ארבעת המפתחות של 0038) + `customers.view` + היקף נתונים
--     מלא — בלעדיהם `{rows: null, denied}` ולא שגיאה: הדף קיים, הנתון אינו
--     בשבילך. אותם תנאים בדיוק ש-`app.margin_require` זורק עליהם, נבדקים כאן
--     ברכות לפני שהעוזר נקרא.

create or replace function public.customer_profitability(p_from date, p_to date, p_limit int default 50)
returns jsonb language plpgsql stable security invoker set search_path = public as $$
declare
  v       jsonb;
  v_sum   jsonb;
  v_rows  jsonb;
  v_lim   int := greatest(1, least(coalesce(p_limit, 50), 50));
  v_total int;
begin
  if not app.has('reports.view') then
    raise exception 'אין הרשאה לדוחות' using errcode = '42501';
  end if;

  -- אותם ארבעה גבולות של dashboard_sections ושל המנוע
  if p_from is null or p_to is null then
    raise exception 'חסר טווח תאריכים' using errcode = '22023'; end if;
  if p_to < p_from then
    raise exception 'טווח תאריכים הפוך' using errcode = '22023'; end if;
  if p_to - p_from > 400 then
    raise exception 'טווח גדול מדי לדשבורד' using errcode = '22023'; end if;

  -- התנאים של app.margin_require + customers.view, בגרסת null-ולא-raise
  if not app.has_all(array['dashboard.margin','dashboard.payroll',
                           'dashboard.contractor_cost','pricing.revenue',
                           'customers.view'])
     or exists (select 1 from app.scope_rows('tasks') where scope_type <> 'all') then
    return jsonb_build_object('rows', null, 'meta', jsonb_build_object('denied', true));
  end if;

  v     := app.margin_by_customer(p_from, p_to, v_lim);
  v_sum := app.margin_summary(p_from, p_to);

  -- החיסור והאחוז פר שורה — בשרת, מאותם שלושה מספרים שהעוזר החזיר
  select coalesce(jsonb_agg(jsonb_build_object(
           'name',       e ->> 'name',
           'color',      e ->> 'color',
           'revenue',    (e ->> 'revenue')::numeric,
           'contractor', (e ->> 'contractor')::numeric,
           'payroll',    (e ->> 'payroll')::numeric,
           'gross',      round((e ->> 'revenue')::numeric - (e ->> 'contractor')::numeric
                               - (e ->> 'payroll')::numeric, 2),
           'pct',        case when (e ->> 'revenue')::numeric > 0
                              then round(((e ->> 'revenue')::numeric - (e ->> 'contractor')::numeric
                                          - (e ->> 'payroll')::numeric)
                                         / (e ->> 'revenue')::numeric * 100, 1) end
         ) order by (e ->> 'revenue')::numeric desc), '[]')
    into v_rows
    from jsonb_array_elements(v -> 'rows') e;

  -- truncated אמיתי, לא ניחוש: מונים כמה לקוחות יש בטווח מול כמה חזרו.
  -- security invoker — הספירה רואה את מה שהקורא רואה, וההיקף כבר אומת מלא.
  select count(distinct t.customer_id) into v_total
    from tasks t
   where t.deleted_at is null and t.customer_id is not null
     and t.task_date between p_from and p_to;

  return jsonb_build_object(
    'rows', v_rows,
    'summary', v_sum,
    'meta', jsonb_build_object(
      'allocated',         v -> 'allocated',
      'unallocated',       v -> 'unallocated',
      'estimated',         true,
      'excludes_overhead', true,
      'unrated_shifts',    v_sum -> 'unrated_shifts',
      'truncated',         v_total > jsonb_array_length(v_rows),
      'scope_note',        'משימות ללא לקוח אינן משתתפות בפילוח; שכר שאינו משויך למשימה מופיע כ"לא משויך"'));
end $$;

-- RPC חדש אינו בטוח כברירת מחדל — אותה רשימה מפורשת של 0008/0012/0044/0058.
revoke execute on function public.customer_profitability(date, date, int) from anon, public;
grant  execute on function public.customer_profitability(date, date, int) to authenticated;
