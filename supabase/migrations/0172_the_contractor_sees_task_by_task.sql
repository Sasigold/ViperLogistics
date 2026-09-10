-- ‏0172: הקבלן רואה משימה־משימה, ולא רק סכום אחד
--
-- ‏"שלקבלן יהיה גם סיכום של כל המשימות שהוא ביצע עם מחיר לכל משימה."
--
-- מסך הכספים של הקבלן (`/portal`) ענה עד כה בארבעה מספרים בלבד: כמה משימות,
-- כמה צפוי, כמה שולם וכמה נותר. זו תשובה נכונה לשאלה "כמה", ואין בה תשובה
-- לשאלה שבאה מיד אחריה — **על מה**. הפירוט הזה כבר קיים במערכת, אבל רק
-- בצד המשרד: לשונית "משימות ותשלומים" בכרטיס הקבלן (`/contractors/:id`)
-- מציגה בדיוק את השורות האלה, ולקבלן עצמו אין אליה דרך. ‏0172 נותנת לו את
-- אותה רשימה — לקריאה בלבד: המחיר וסימון התשלום נשארים של המשרד.
--
-- **הרשימה נשענת על `tasks` ולא על `task_contractor_terms`.** זה ההבדל
-- היחיד שאינו סגנוני. ‏`tct_select` (0012) פותחת לקבלן את שורת התמחור שלו
-- רק אם הוא מחזיק `contractors.view_pricing`, ולכן `join` על הטבלה הזו הוא
-- גם שער הכסף וגם שער הקיום: קבלן בלי המפתח לא היה מקבל שורה בלי מחיר אלא
-- לא היה מקבל שורה בכלל, ו"סיכום המשימות שביצעתי" היה נעלם בשלמותו בגלל
-- מפתח *כספי*. כאן השורות באות מ-`tasks` — ‏`tasks_select` כבר מכריעה
-- שקבלן עם `portal.view` רואה את מה שהואצל אליו (0139) — והתמחור מצטרף
-- ב-`left join`, כך שהיעדר המפתח משמיט את המחיר ולא את המשימה.
--
-- ‏`app.assignment_on_my_contractor` (0098) היא "המשימה הזו שלי?" בדיוק כפי
-- שהפוליסה שואלת אותה. היא `security definer` ולכן אינה נחסמת ב-RLS של
-- ‏`task_contractor_terms`, והשורות עצמן ממילא כבר סוננו: היא מסננת מתוך מה
-- שמותר לקורא לראות, ואינה פותחת שורה חדשה. לקורא שאינו קבלן
-- (‏`app.contractor_id()` ריק) היא מחזירה `false` תמיד — הפונקציה הזו היא
-- המסך של הקבלן, ולמשרד יש את כרטיס הקבלן.
--
-- **שני שערי כסף, ושניהם נשמרים.** ‏`portal.view_financials` הוא המסכה
-- במסך הזה (וכך `contractor_dashboard` מאז 0100), ו-`contractors.view_pricing`
-- הוא זה שמחזיר בכלל את שורת ה-terms. מי שאין לו אחד מהם מקבל `null`
-- במחיר, בסכום ששולם ובתאריך התשלום — ולא אפס, שהוא מספר ולא "אין לי רשות
-- לדעת".
--
-- ‏`p_limit` ולא רשימה בלי סוף: "טווח מותאם" בלי תאריכים הוא כל התקופה, ומי
-- שעובד עם וייפר שנתיים יגרור עשרות אלפי שורות אל טלפון. התקרה היא 2000
-- והברירה 500; המסך משווה את מספר השורות שקיבל למונה של `contractor_dashboard`
-- ואומר לקבלן שהרשימה נקטעה, במקום להציג חלק ולהיראות שלם.

create or replace function contractor_tasks(
  p_from  date default null,
  p_to    date default null,
  p_limit int  default 500)
returns table (
  task_id         uuid,
  task_date       date,
  title           text,
  task_type_name  text,
  status_name     text,
  status_color    text,
  is_terminal     boolean,
  event_id        uuid,
  event_date      date,
  event_number    text,
  end_client_name text,
  customer_name   text,
  location_text   text,
  worker_count    int,
  price           numeric,
  price_parts     jsonb,
  paid_at         timestamptz,
  paid_amount     numeric)
language sql stable security invoker set search_path = public as $$
  select
    t.id,
    t.task_date,
    nullif(t.title, ''),
    tt.name,
    s.name,
    s.color,
    s.is_terminal,
    t.event_id,
    e.event_date,
    e.event_number,
    e.end_client_name,
    /* ‏`app.customer_identities` (0079) — שם וצבע בלבד, על שורה שכבר סוננה.
       זה אותו שם לקוח שהקבלן רואה על השורה בלו״ז, ולא פתיחה של `customers`. */
    c.name,
    /* המיקום של המשימה גובר על זה של האירוע, כמו ב-`work_board_view`, ותחת
       אותה הרשאת שדה. */
    case when (select app.can_view_field('task', 'location_text'))
      then coalesce(t.location_text, e.location_text) end,
    t.worker_count,
    case when (select app.has('portal.view_financials')) then tct.price end,
    case when (select app.has('portal.view_financials')) then tct.price_parts end,
    case when (select app.has('portal.view_financials')) then tct.paid_at end,
    case when (select app.has('portal.view_financials')) then tct.paid_amount end
  from tasks t
  join task_types tt on tt.id = t.task_type_id
  join statuses   s  on s.id = t.status_id
  left join events e on e.id = t.event_id
  left join app.customer_identities c on c.id = t.customer_id
  left join task_contractor_terms tct
         on tct.task_id = t.id and tct.contractor_id = (select app.contractor_id())
  where t.deleted_at is null
    and (select app.assignment_on_my_contractor(t.id))
    and (p_from is null or t.task_date >= p_from)
    and (p_to   is null or t.task_date <= p_to)
  /* היום האחרון ראשון, וכשיש כמה משימות באותו יום — לפי שעת ההתחלה, כדי
     שהקמה ופירוק של אותו יום ישבו בסדר שבו הם קרו. */
  order by t.task_date desc, t.onsite_start_time nulls last, tt.name
  limit greatest(1, least(coalesce(p_limit, 500), 2000))
$$;

-- ‏`anon` לא, ו-`authenticated` במפורש — אותה הכרעה של 0169.
revoke execute on function contractor_tasks(date, date, int) from anon, public;
grant  execute on function contractor_tasks(date, date, int) to authenticated;

-- ===== המונה והרשימה סופרים אותו דבר =======================================
--
-- ‏`contractor_dashboard` (0100) סופר דרך `join task_contractor_terms`, ולכן
-- הוא נושא בדיוק את הפגם שתואר למעלה: קבלן בלי `contractors.view_pricing`
-- קיבל `tasks_count = 0` — לא "אין לי רשות לראות מחיר" אלא "לא עבדת". עכשיו
-- כשיש רשימה לצדו, ההפרש היה נראה על המסך: כרטיס שאומר 0 מעל שתים־עשרה
-- שורות. הספירות עוברות לאותו מקור בדיוק כמו הרשימה — `tasks` תחת RLS ועם
-- `app.assignment_on_my_contractor` — והכסף נשאר ב-`left join` על ה-terms,
-- מסוכה ב-`portal.view_financials` כפי שהייתה.
--
-- הסכומים לא זזו: מי שרואה את שורות ה-terms מקבל בדיוק את אותם ארבעה
-- מספרים, ומי שאינו רואה אותן קיבל אפסים גם קודם — רק שעכשיו הוא מקבל
-- אפסים לצד מונה משימות שאומר את האמת.
create or replace function contractor_dashboard(p_from date default null, p_to date default null)
returns jsonb language sql stable security invoker set search_path = public as $$
  with my_tasks as (
    select t.id, t.task_date, tct.price, tct.paid_at, tct.paid_amount, s.is_terminal
    from tasks t
    join statuses s on s.id = t.status_id
    left join task_contractor_terms tct
           on tct.task_id = t.id and tct.contractor_id = (select app.contractor_id())
    where t.deleted_at is null
      and (select app.assignment_on_my_contractor(t.id))
      and (p_from is null or t.task_date >= p_from)
      and (p_to is null or t.task_date <= p_to)
  )
  select jsonb_build_object(
    'tasks_count', (select count(*) from my_tasks),
    'expected_total', case when app.has('portal.view_financials')
      then (select coalesce(sum(price), 0) from my_tasks) else null end,
    'paid_total', case when app.has('portal.view_financials')
      then (select coalesce(sum(coalesce(paid_amount, price)), 0) from my_tasks where paid_at is not null) else null end,
    /* משימה שאין עליה שורת terms נראית (למי שרשאי לראות אותן) כמשימה בלי
       מחיר, ו-`coalesce(price, 0)` מוסיף לה אפס — לא כפל ולא `null` שבולע
       את כל הסכום. */
    'unpaid_total', case when app.has('portal.view_financials')
      then (select coalesce(sum(coalesce(price, 0)), 0) from my_tasks where paid_at is null) else null end,
    'completed_count', (select count(*) from my_tasks where is_terminal),
    'upcoming_count', (select count(*) from my_tasks where task_date >= current_date and not is_terminal))
$$;

revoke execute on function contractor_dashboard(date, date) from anon, public;
grant  execute on function contractor_dashboard(date, date) to authenticated;

-- ===== השומר של 0164, על שתי הפונקציות שכאן ================================
--
-- ‏0164 הפך את "פונקציית `public` שהיא invoker קוראת לעוזר ב-`app` שאסור
-- ל-`authenticated` להריץ" לבדיקה שנופלת בחבילת המיגרציות. הבדיקה ההיא רצה
-- *לפני* הקובץ הזה, ולכן היא אינה יכולה לראות את שתי הפונקציות שנוצרו כאן —
-- ושתיהן invoker וקוראות ל-`app.has`, ל-`app.contractor_id`,
-- ל-`app.can_view_field` ול-`app.assignment_on_my_contractor`. אותה שאלה
-- בדיוק, מצומצמת לשתיהן.
do $$
declare
  v_bad text;
begin
  select string_agg(format('public.%s → app.%s', pub.proname, h.proname), ', ')
    into v_bad
    from (select p.oid, p.proname, p.prosrc
            from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and not p.prosecdef
             and p.proname in ('contractor_tasks', 'contractor_dashboard')
             and has_function_privilege('authenticated', p.oid, 'EXECUTE')) pub
    join (select p.oid, p.proname
            from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'app'
             and not has_function_privilege('authenticated', p.oid, 'EXECUTE')) h
      on pub.prosrc ~* ('app\.' || h.proname || '\s*\(');

  if v_bad is not null then
    raise exception
      'פונקציית public שהיא invoker קוראת לעוזר ב-app שאין ל-authenticated הרשאה להריץ: %',
      v_bad;
  end if;
end $$;

comment on function contractor_tasks(date, date, int) is
  'סיכום המשימות של הקבלן הקורא בטווח תאריכים, עם המחיר לכל משימה (0172). '
  'שורות מ-tasks תחת RLS; המחיר מ-task_contractor_terms, מסוכה ב-portal.view_financials.';
