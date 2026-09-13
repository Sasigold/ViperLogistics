-- ‏0173: מפת עומסים — החודש אומר איפה הוא צפוף, והיום אומר באיזו שעה
--
-- ‏"אני רוצה לדעת מה מצב העומס על העסק שלי. מפה חודשית כמו hot map, וכשאני
-- לוחץ על היום — גרף יומי על כל שעה, ואני רואה מה הכי עמוס."
--
-- כל מסך שקיים היום עונה על "מה יש": הלו״ז מונה משימות, לוח השנה מציג אותן
-- לפי יום, ולוח המשמרות מראה מי משובץ. אף אחד מהם אינו עונה על **"כמה זה
-- מתוך מה שאני מסוגל"** — וזו שאלה אחרת: שתי משימות ביום הן יום ריק, ושתי
-- משימות *באותה שעה* עם שתים־עשרה עובדים ושלוש משאיות הן יום שאי אפשר
-- לקחת בו עוד עבודה. ההבדל בין השתיים אינו בכמות אלא בחפיפה, ולכן המידה
-- כאן היא **מקבילות**, לא סכום.
--
-- ===== מה נמדד, ולמה דווקא זה ==============================================
--
-- הבקשה נקבה בשלושה: כמות עובדים בו-זמנית, כמות משימות חופפות, וכמות
-- משאיות. שלושתם כאן, ולצדם מה שמשפיע על העומס האמיתי ואינו נראה בשלושתם:
--
--   • **ראשי צוות.** ראש צוות אחד למשימה (‏`task_assignments_one_lead`,
--     ‏0003), ולכן חמש משימות מקבילות דורשות חמישה — וזה הצוואר שנסגר
--     ראשון, הרבה לפני מאגר העובדים. משימה מכריזה על הצורך ב-
--     ‏`requires_team_lead`, ובהיעדר דריסה לפי מה שמנוע התמחור קבע.
--   • **פער האיוש.** ‏`worker_count` הוא מה שהמשימה *דורשת*; השיבוצים הם מה
--     שכבר יש. ההפרש הוא העומס שעוד לא נפתר, והוא מה שהופך יום "מלא"
--     ליום שמישהו צריך לעשות בו משהו עכשיו.
--   • **פיזור גיאוגרפי.** שלוש משימות באותה שעה בשלושה אתרים אינן שלוש
--     משימות באתר אחד: ביניהן יש נסיעה, והיא אינה נספרת בשעות של אף אחת.
--   • **לחץ על המחסן.** משימות שיוצאות מאותו מחסן באותה שעה מתחרות על אותו
--     רציף העמסה. זה עומס אמיתי שאינו נראה בשום ספירה של אנשים.
--   • **הישענות על קבלנים.** מה שהואצל אינו יורד מהעומס — הוא **הראיה**
--     שהכושר הפנימי כבר נגמר. לכן הוא נמדד ומוצג, ואינו מנוכה.
--
-- ===== החלון של משימה ======================================================
--
-- אותה נוסחה בדיוק של `app.task_window` (0029, ‏0163) ושל
-- ‏`app.planned_shifts_many` (0166): הפתיחה היא היציאה מהמחסן כשיש כזו —
-- דרך `app.warehouse_start_at`, שיודע ששעה הגדולה משעת השטח היא של הערב
-- שלפני — והסגירה היא שעת השטח ועוד `hours_count`. היא משוכפלת כאן ולא
-- נקראת פר-משימה מפני שהיא נמדדת מול **כל שעה בטווח**: קריאה לפונקציה
-- ‏`stable` בתוך join כזה היא הפרש של סדר גודל בזמן, ולא של אחוזים.
--
-- ‏**משימה בלי שעה אינה על הציר.** אין לה חלון, ולכן אין שעה שאפשר לתלות
-- אותה בה; היא נספרת ב-`untimed` על היום, כדי שהמספר לא ייעלם בשקט.
--
-- ===== התקרה ===============================================================
--
-- אחוז עומס בלי מכנה הוא ספירה, לא מצב. המכנה הוא `app_settings['ops.capacity']`
-- — שלושה מספרים שהמשרד קובע — וכשהוא ריק הוא **נגזר מהמאגר בפועל**: הסגל
-- הפעיל ועובדי הקבלנים הפעילים, המשאיות הפעילות, ומי שמוגדר ראש צוות.
-- הגזירה היא ברירת מחדל ולא הכרעה: `meta.capacity.source` אומר לכל ממד אם
-- המספר הוגדר או נגזר, כדי שהמסך יוכל לומר את זה במקום להציג אחוז שנראה
-- סמכותי יותר ממה שהוא.
--
-- העומס עצמו הוא **המרבי מבין הממדים** ולא ממוצע שלהם: צוואר בקבוק אחד סוגר
-- את היום גם כשכל השאר פנוי, וממוצע היה מדלל אותו עד שהוא נעלם. ‏`bottleneck`
-- נושא את שם הממד שניצח, כי "‏87%" בלי "ממה" אינו מידע שאפשר לפעול לפיו.
--
-- ===== ההרשאה ==============================================================
--
-- ‏`reports.load`, ‏`implied_by 'reports.view'` — מי שרואה דוחות רואה את המפה
-- ביום המיגרציה, ואיש אינו מקבל נתון שלא ראה אתמול. ‏`security invoker`, ולכן
-- ‏RLS של `tasks` היא שמכריעה אילו שורות נספרות. וכאן ההכרעה השנייה: קורא
-- שיש לו **היקף נתונים מצומצם** מקבל `denied` ולא מספרים — מפת עומסים
-- שנבנתה על חלק מהמשימות אינה מפה חלקית אלא מפה **שגויה**, כי המכנה שלה
-- הוא כל העסק. זו אותה הכרעה של `task_pnl` (0070 §4) ומאותו טעם.

-- ===== 1. המפתח ============================================================

select app.register_permission(
  'reports.load', 'reports', 'מפת עומסים',
  'מפת העומס החודשית והפילוח השעתי — משימות חופפות, עובדים, משאיות וראשי צוות',
  'access', false, false,
  array['staff']::user_kind[], 'reports.view', 30);

-- ===== 2. התקרה ============================================================
--
-- ‏`null` בכל אחד מהשלושה = "לך לפי המאגר", ולא אפס. המפתח אינו מתחיל ב-
-- ‏`attendance.` או ב-`notifications.`, ולכן הוא נופל לענף `settings.edit`
-- של הפוליסה מ-0046 ואין כאן פוליסה חדשה לכתוב.

insert into app_settings (key, value) values
  ('ops.capacity', jsonb_build_object(
    'workers', null, 'trucks', null, 'team_leads', null))
on conflict (key) do nothing;

comment on table app_settings is
  'הגדרות גלובליות לפי מפתח. attendance.* לפי attendance.settings, '
  'notifications.* לפי notifications.manage, וכל השאר לפי settings.edit (0046). '
  'ops.capacity הוא תקרת הכושר של מפת העומסים (0173).';

/**
 * שלוש התקרות, ולצד כל אחת מאין היא באה.
 *
 * ‏`security definer`: הספירה חייבת לראות את כל הסגל ואת כל הצי גם כשהקורא
 * אינו רשאי לפתוח את רשומות העובדים — היא מחזירה **מספרים בלבד**, בלי שם
 * ובלי שורה, ולכן אין כאן דלת לשום דבר. הקריאה עצמה מגודרת ב-`reports.load`
 * אצל מי שקורא לה.
 */
create or replace function app.load_capacity()
returns jsonb language sql stable security definer set search_path = public as $$
  with cfg as (
    select coalesce((select value from app_settings where key = 'ops.capacity'),
                    '{}'::jsonb) as v
  ),
  derived as (
    select
      (select count(*) from profiles p
        where p.deleted_at is null and p.is_active
          and exists (select 1 from staff_roles r where r.profile_id = p.id))
      + (select count(*) from contractor_workers w
          join contractors c on c.id = w.contractor_id
         where w.deleted_at is null and w.is_active
           and c.deleted_at is null and c.is_active) as workers,
      (select count(*) from trucks t
        where t.deleted_at is null and t.is_active) as trucks,
      (select count(*) from profiles p
        where p.deleted_at is null and p.is_active
          and exists (select 1 from staff_roles r
                       where r.profile_id = p.id and r.role = 'team_lead'))
      + (select count(*) from contractor_workers w
          join contractors c on c.id = w.contractor_id
         where w.deleted_at is null and w.is_active
           and c.deleted_at is null and c.is_active
           and exists (select 1 from contractor_worker_roles r
                        where r.contractor_worker_id = w.id and r.role = 'team_lead'))
        as team_leads
  )
  select jsonb_build_object(
    'workers',    coalesce((cfg.v ->> 'workers')::numeric,    d.workers),
    'trucks',     coalesce((cfg.v ->> 'trucks')::numeric,     d.trucks),
    'team_leads', coalesce((cfg.v ->> 'team_leads')::numeric, d.team_leads),
    /* מאין בא כל מספר. המסך אומר "נגזר מהמאגר" ולא מציג אחוז כאילו מישהו
       הכריע אותו — וזה ההבדל בין מדידה לבין ניחוש שנראה כמו מדידה. */
    'source', jsonb_build_object(
      'workers',    case when cfg.v ->> 'workers'    is null then 'derived' else 'configured' end,
      'trucks',     case when cfg.v ->> 'trucks'     is null then 'derived' else 'configured' end,
      'team_leads', case when cfg.v ->> 'team_leads' is null then 'derived' else 'configured' end))
  from cfg, derived d
$$;

grant execute on function app.load_capacity() to authenticated;

comment on function app.load_capacity() is
  'תקרת הכושר של מפת העומסים (0173): app_settings[''ops.capacity''], '
  'וכל ערך חסר נגזר מהמאגר הפעיל. source אומר על כל ממד אם הוגדר או נגזר.';

-- ===== 3. המשימות שעל הציר =================================================
--
-- ‏`security invoker` — `tasks` תחת RLS, ולכן קורא רואה כאן בדיוק את מה
-- שהוא רואה בלו״ז. אירוע שבוטל אינו נספר (0114), משימה מחוקה רכות אינה
-- נספרת (0062), ומשימה בלי שעה אינה על הציר כלל.
--
-- העמודות הן מה שכל שאר הפונקציות בקובץ צריכות: החלון, הדרישה, מה שכבר
-- מאויש, והמשאיות. ‏`set-returning` ולא view, כדי שהטווח יהיה פרמטר ולא
-- פרדיקט שכל קורא צריך לזכור לכתוב.
create or replace function app.load_tasks(p_from date, p_to date)
returns table (
  task_id     uuid,
  task_date   date,
  win         tstzrange,
  worker_need int,
  staffed     int,
  needs_lead  boolean,
  truck_ids   uuid[],
  customer_id uuid,
  site        text,
  warehouse   uuid,
  delegated   boolean)
language sql stable security invoker set search_path = public as $$
  select
    t.id,
    t.task_date,
    tstzrange(
      /* אותה פתיחה של app.task_window: היציאה מהמחסן כשיש כזו, והיא זו
         שנסוגה ליום שלפני כשהיא גדולה משעת השטח (0163). */
      case when t.warehouse_start_time is not null
           then app.warehouse_start_at(t.task_date, t.warehouse_start_time,
                                       t.onsite_start_time)
           else ((t.task_date + t.onsite_start_time) at time zone 'Asia/Jerusalem') end,
      ((t.task_date + coalesce(t.onsite_start_time, t.warehouse_start_time))
        at time zone 'Asia/Jerusalem')
        + make_interval(mins => round(coalesce(t.hours_count, 0) * 60)::int),
      '[)'),
    t.worker_count,
    /* מי שכבר משובץ — פנימי, של קבלן, ושל לקוח שמבצע בעצמו — בלי לכפול את
       מי שמשובץ בשני תפקידים על אותה משימה (0003: `unique (task_id,
       profile_id, role)` מרשה עובד שהוא גם נהג). */
    (select count(distinct a.profile_id) from task_assignments a where a.task_id = t.id)
    + (select count(*) from task_contractor_workers w where w.task_id = t.id)
    + (select count(*) from task_customer_workers o where o.task_id = t.id),
    /* ‏null = לפי הקבוע במחשבון (0017), ובו ברירת המחדל היא "לא נדרש". */
    coalesce(t.requires_team_lead, false),
    t.truck_ids,
    t.customer_id,
    /* המיקום של המשימה, ובהיעדרו של האירוע — אותו סדר של הלו״ז (0158). */
    nullif(btrim(coalesce(t.location_text, e.location_text, '')), ''),
    coalesce(t.warehouse_id, c.warehouse_id),
    /* ‏`tasks.contractor_id` ולא `exists` על `task_contractor_terms`: הטבלה
       ההיא מסוננת ב-`tct_select` (0012) למי שאין לו `contractors.view_pricing`,
       ולכן היא הייתה עונה "לא הואצל" למי שרק אינו רשאי לראות את המחיר.
       העמודה כאן מסונכרנת לשורות ה-terms בטריגר של 0096, והיא על השורה
       שהקורא ממילא רואה — כלומר שאלה על עובדה, לא על מפתח כספי. */
    t.contractor_id is not null
  from tasks t
  left join events e     on e.id = t.event_id
  left join statuses es  on es.id = e.status_id
  left join customers c  on c.id = t.customer_id
  where t.deleted_at is null
    and coalesce(es.code, '') <> 'cancelled'
    /* הטווח כאן הוא טווח של **זמן**, לא של תאריכי משימה, ולכן הוא רחב יום
       לכל צד. משימה של אמש שנמשכת אחרי חצות נוגעת בבוקר של היום הראשון,
       והשורות שנשפכות החוצה נופלות ממילא: השעות מסננות בחפיפה, והסיכום
       היומי מצטרף ב-`left join` על ימי הטווח בלבד. */
    and (t.task_date between p_from - 1 and p_to
         /* ‏0163, ואותה שורה בדיוק ב-`app.planned_shifts_many` (0166): יציאה
            למחסן ששעתה גדולה משעת השטח היא של הערב שלפני, ולכן משימה של
            היום שאחרי הטווח **נוגעת בו**. בלי השורה הזו הלילה האחרון של כל
            טווח היה נראה פנוי, והתא במפה היה משקר דווקא על העומס שקשה
            ביותר לאייש. */
         or (t.task_date = p_to + 1
             and t.warehouse_start_time is not null
             and t.onsite_start_time is not null
             and t.warehouse_start_time > t.onsite_start_time))
    and coalesce(t.onsite_start_time, t.warehouse_start_time) is not null
    and coalesce(t.hours_count, 0) > 0
$$;

grant execute on function app.load_tasks(date, date) to authenticated;

comment on function app.load_tasks(date, date) is
  'משימות הטווח עם חלון הזמן שלהן ומה שהן צורכות (0173). invoker — RLS של '
  'tasks מכריעה. משימה בלי שעה או בלי משך אינה על הציר.';

-- ===== 4. השעה =============================================================
--
-- שורה לכל (יום, שעה) בטווח, ובה כמה מכל דבר רץ *באותו רגע*. משימה נספרת
-- בשעה שהחלון שלה חופף לה, ולכן משימה בת ארבע שעות נספרת בארבע שעות —
-- וזו כל הנקודה: שתי משימות של יום אחד שאינן חופפות אינן עומס, ושתיים
-- שחופפות כן.
--
-- השעות נמנות **לפי Asia/Jerusalem**, כמו כל דבר אחר שנקרא על ידי בן אדם
-- במערכת הזו, ולכן יום הוא 24 שעות מקומיות ולא 24 שעות UTC.
create or replace function app.load_slots(p_from date, p_to date)
returns table (
  slot_day   date,
  slot_hour  int,
  tasks      int,
  workers    int,
  staffed    int,
  trucks     int,
  leads      int,
  customers  int,
  sites      int,
  warehouses int,
  delegated  int)
language sql stable security invoker set search_path = public as $$
  with lt as (select * from app.load_tasks(p_from, p_to)),
  /* ‏`::timestamp` מפורש, ומניית ימים ב-offset במקום `generate_series` על
     תאריכים. שתי ההכרעות הן אותה הכרעה: ל-`date` יש המרה משתמעת גם
     ל-`timestamp` וגם ל-`timestamptz`, ו-Postgres בוחר את השני — ואז
     ‏`at time zone` פועל **בכיוון ההפוך** ומחזיר שעון-קיר במקום רגע. כל
     השעות היו יוצאות מוזזות בגודל ההיסט מ-UTC, בשקט וללא שגיאה.
     (‏24 משבצות ליום גם בשני ימי מעבר השעון בשנה — ההיסט נופל ב-02:00,
     שעה שאין בה משימות, ולכן הפשטות עדיפה כאן על דיוק שאיש לא ירגיש.) */
  slots as (
    select (p_from + n) as slot_day, h as slot_hour,
           tstzrange((((p_from + n)::timestamp + make_interval(hours => h))
                       at time zone 'Asia/Jerusalem'),
                     (((p_from + n)::timestamp + make_interval(hours => h + 1))
                       at time zone 'Asia/Jerusalem'),
                     '[)') as win
      from generate_series(0, p_to - p_from) n
      cross join generate_series(0, 23) h
  )
  select
    s.slot_day,
    s.slot_hour,
    count(l.task_id)::int,
    coalesce(sum(l.worker_need), 0)::int,
    coalesce(sum(l.staffed), 0)::int,
    /* משאית שמשרתת שתי משימות חופפות היא משאית אחת תפוסה, ולכן distinct
       ולא סכום — וזה ההבדל בין "כמה משאיות צריך" לבין "כמה שורות יש". */
    (select count(distinct u.tid)
       from lt l2, lateral unnest(l2.truck_ids) u(tid)
      where l2.win && s.win)::int,
    coalesce(sum(case when l.needs_lead then 1 else 0 end), 0)::int,
    count(distinct l.customer_id)::int,
    count(distinct l.site)::int,
    count(distinct l.warehouse)::int,
    coalesce(sum(case when l.delegated then 1 else 0 end), 0)::int
  from slots s
  left join lt l on l.win && s.win
  /* ‏`s.win` בקיבוץ ולא רק שני המפתחות: תת-השאילתה של המשאיות מתואמת אליו,
     ושוויון פונקציונלי שברור לקורא אינו ידוע למתכנן. */
  group by s.slot_day, s.slot_hour, s.win
$$;

grant execute on function app.load_slots(date, date) to authenticated;

comment on function app.load_slots(date, date) is
  'שורה לכל (יום, שעה) בטווח עם מה שרץ באותו רגע (0173). משימה נספרת בכל '
  'שעה שהחלון שלה חופף לה — מקבילות, לא סכום.';

-- ===== 5. השער ============================================================
--
-- שני התנאים של `task_pnl` (0070 §4), מאותו טעם: המפתח זורק 42501 כי הדף
-- לא היה צריך להיפתח, וההיקף המצומצם מחזיר `denied` רך כי הדף כן קיים —
-- פשוט לא בשבילך. ‏`stable` ולא `volatile`, כמו כל קריאת דוח.
create or replace function app.load_denied()
returns boolean language sql stable security invoker set search_path = public as $$
  select exists (select 1 from app.scope_rows('tasks') where scope_type <> 'all')
      or not (app.is_admin() or app.user_kind() = 'staff')
$$;

grant execute on function app.load_denied() to authenticated;

comment on function app.load_denied() is
  'האם מפת העומסים מסרבת להחזיר מספרים לקורא הזה (0173): היקף נתונים '
  'מצומצם, או קורא שאינו מהמשרד. מפה שנבנתה על חלק מהמשימות היא מפה שגויה.';

-- ===== 6. המפה החודשית =====================================================

create or replace function load_heatmap(p_from date, p_to date)
returns jsonb language plpgsql stable security invoker set search_path = public as $$
declare
  v_cap  jsonb;
  v_days jsonb;
begin
  if not app.has('reports.load') then
    raise exception 'אין הרשאה למפת העומסים' using errcode = '42501';
  end if;

  if p_from is null or p_to is null then
    raise exception 'חסר טווח תאריכים' using errcode = '22023'; end if;
  if p_to < p_from then
    raise exception 'טווח תאריכים הפוך' using errcode = '22023'; end if;
  /* אותו גבול של הדשבורד ושל הדוחות — שנה ועוד קצת, וכאן הוא גם גבול
     חישובי: כל יום הוא 24 שורות. */
  if p_to - p_from > 400 then
    raise exception 'טווח גדול מדי' using errcode = '22023'; end if;

  if app.load_denied() then
    return jsonb_build_object('days', null, 'meta', jsonb_build_object('denied', true));
  end if;

  v_cap := app.load_capacity();

  with s as (select * from app.load_slots(p_from, p_to)),
  /* היום, וממנו שני מספרים שונים: הפסגה — השעה הצפופה ביותר, שהיא
     התשובה ל"כמה זה מתוך מה שאני מסוגל" — והסך, שהוא נפח העבודה. יום של
     שתי משימות זו אחר זו וְיום של שתיים חופפות נושאים אותו סך ופסגה
     שונה, וזה בדיוק ההבדל שהמפה נועדה להראות. */
  peaks as (
    select
      s.slot_day,
      max(s.tasks)      as peak_tasks,
      max(s.workers)    as peak_workers,
      max(s.trucks)     as peak_trucks,
      max(s.leads)      as peak_leads,
      max(s.sites)      as peak_sites,
      max(s.warehouses) as peak_warehouses,
      count(*) filter (where s.tasks > 0) as busy_hours
    from s group by s.slot_day
  ),
  /* השעה שבה הפסגה נמדדה. `distinct on` על אותו סדר שקובע את `peak_*`:
     הראשונה מבין השעות ששוברות את השיא, כדי ש"השעה העמוסה" תהיה זו
     שהעומס *התחיל* בה ולא זו שהוא נגמר בה. */
  peak_hour as (
    select distinct on (s.slot_day) s.slot_day, s.slot_hour
      from s
     where s.tasks > 0
     order by s.slot_day,
              greatest(
                case when (v_cap ->> 'workers')::numeric    > 0
                     then s.workers::numeric / (v_cap ->> 'workers')::numeric    else 0 end,
                case when (v_cap ->> 'trucks')::numeric     > 0
                     then s.trucks::numeric  / (v_cap ->> 'trucks')::numeric     else 0 end,
                case when (v_cap ->> 'team_leads')::numeric > 0
                     then s.leads::numeric   / (v_cap ->> 'team_leads')::numeric else 0 end) desc,
              s.workers desc, s.slot_hour
  ),
  /* הסך של היום — מהמשימות עצמן ולא מהשעות, אחרת משימה בת ארבע שעות
     הייתה נספרת ארבע פעמים. `task_date` ולא החלון: משימה שיוצאת מהמחסן
     ב-23:00 של אתמול היא משימה של היום שלה, וכך היא מוצגת בכל מסך אחר. */
  totals as (
    select
      l.task_date as slot_day,
      count(*)::int                                   as tasks,
      coalesce(sum(l.worker_need), 0)::int            as worker_need,
      coalesce(sum(l.staffed), 0)::int                as staffed,
      coalesce(sum(greatest(l.worker_need - l.staffed, 0)), 0)::int as gap,
      coalesce(sum(extract(epoch from (upper(l.win) - lower(l.win))) / 3600.0
                   * l.worker_need), 0)::numeric      as worker_hours,
      count(*) filter (where l.delegated)::int        as delegated,
      count(distinct l.customer_id)::int              as customers,
      count(distinct l.site)::int                     as sites
    from app.load_tasks(p_from, p_to) l
    group by l.task_date
  ),
  /* משימות היום שאין להן שעה. אין להן חלון ולכן אין להן מקום על הציר,
     אבל הן כן עבודה — והשתיקה עליהן הייתה הופכת יום עמוס ליום ריק. */
  untimed as (
    select t.task_date, count(*)::int as untimed_tasks
      from tasks t
      left join events e    on e.id = t.event_id
      left join statuses es on es.id = e.status_id
     where t.deleted_at is null
       and coalesce(es.code, '') <> 'cancelled'
       and t.task_date between p_from and p_to
       and (coalesce(t.onsite_start_time, t.warehouse_start_time) is null
            or coalesce(t.hours_count, 0) = 0)
     group by t.task_date
  )
  /* אותה מניית-offset של `app.load_slots`, ומאותו טעם: `generate_series`
     על תאריכים מחזיר `timestamptz`, ו-`::date` עליו נחתך לפי אזור הזמן של
     הסשן ולא לפי זה של המשתמש. */
  select jsonb_agg(jsonb_build_object(
           'day',             (p_from + n),
           'tasks',           coalesce(tt.tasks, 0),
           'untimed',         coalesce(u.untimed_tasks, 0),
           'worker_need',     coalesce(tt.worker_need, 0),
           'staffed',         coalesce(tt.staffed, 0),
           'gap',             coalesce(tt.gap, 0),
           'worker_hours',    round(coalesce(tt.worker_hours, 0), 2),
           'delegated',       coalesce(tt.delegated, 0),
           'customers',       coalesce(tt.customers, 0),
           'sites',           coalesce(tt.sites, 0),
           'peak_hour',       ph.slot_hour,
           'peak_tasks',      coalesce(pk.peak_tasks, 0),
           'peak_workers',    coalesce(pk.peak_workers, 0),
           'peak_trucks',     coalesce(pk.peak_trucks, 0),
           'peak_leads',      coalesce(pk.peak_leads, 0),
           'peak_sites',      coalesce(pk.peak_sites, 0),
           'peak_warehouses', coalesce(pk.peak_warehouses, 0),
           'busy_hours',      coalesce(pk.busy_hours, 0))
         order by n)
    into v_days
    from generate_series(0, p_to - p_from) g(n)
    left join peaks     pk on pk.slot_day  = (p_from + n)
    left join peak_hour ph on ph.slot_day  = (p_from + n)
    left join totals    tt on tt.slot_day  = (p_from + n)
    left join untimed   u  on u.task_date  = (p_from + n);

  return jsonb_build_object(
    'days', coalesce(v_days, '[]'::jsonb),
    'meta', jsonb_build_object(
      'from', p_from, 'to', p_to, 'capacity', v_cap, 'denied', false));
end $$;

revoke execute on function load_heatmap(date, date) from anon, public;
grant  execute on function load_heatmap(date, date) to authenticated;

comment on function load_heatmap(date, date) is
  'המפה החודשית של מפת העומסים (0173): שורה ליום עם הפסגה השעתית שלו ועם '
  'הסך שלו. האחוז עצמו מחושב בדפדפן מול meta.capacity.';

-- ===== 7. היום ============================================================
--
-- מה שנפתח בלחיצה על תא במפה: עשרים וארבע שעות, ולצדן המשימות עצמן — כי
-- "‏14:00 הוא הכי עמוס" הוא תשובה שמיד אחריה באה השאלה "בגלל מה", והיא
-- צריכה להיענות באותה קריאה ולא בקריאה שנייה למסך אחר.
create or replace function load_day(p_date date)
returns jsonb language plpgsql stable security invoker set search_path = public as $$
declare
  v_cap   jsonb;
  v_hours jsonb;
  v_tasks jsonb;
begin
  if not app.has('reports.load') then
    raise exception 'אין הרשאה למפת העומסים' using errcode = '42501';
  end if;
  if p_date is null then
    raise exception 'חסר תאריך' using errcode = '22023'; end if;

  if app.load_denied() then
    return jsonb_build_object('hours', null, 'tasks', null,
                              'meta', jsonb_build_object('denied', true));
  end if;

  v_cap := app.load_capacity();

  select jsonb_agg(jsonb_build_object(
           'hour',       s.slot_hour,
           'tasks',      s.tasks,
           'workers',    s.workers,
           'staffed',    s.staffed,
           'gap',        greatest(s.workers - s.staffed, 0),
           'trucks',     s.trucks,
           'leads',      s.leads,
           'customers',  s.customers,
           'sites',      s.sites,
           'warehouses', s.warehouses,
           'delegated',  s.delegated)
         order by s.slot_hour)
    into v_hours
    from app.load_slots(p_date, p_date) s;

  /* המשימות שנוגעות ביום הזה — לרבות אחת של אתמול שנמשכת לתוכו, ואחת של
     מחר שהיציאה שלה למחסן נסוגה אליו (0163). ‏`app.load_tasks` כבר מרחיב
     את הטווח לשני הצדדים, ו-`&&` על חלון היום מכריע בסוף בלי לשאול על
     ‏`task_date` בכלל. */
  select jsonb_agg(jsonb_build_object(
           'task_id',     v.id,
           'task_date',   v.task_date,
           'label',       coalesce(nullif(v.title, ''), v.end_client_name,
                                   v.customer_name, v.task_type_name),
           'task_type',   v.task_type_name,
           'customer',    v.customer_name,
           'color',       v.customer_color,
           'start',       lower(l.win),
           'end',         upper(l.win),
           'worker_need', l.worker_need,
           'staffed',     l.staffed,
           'needs_lead',  l.needs_lead,
           'trucks',      coalesce(cardinality(l.truck_ids), 0),
           'truck_names', v.truck_list,
           'site',        l.site,
           'delegated',   l.delegated,
           'status_name', v.status_name,
           'status_color', v.status_color)
         order by lower(l.win), v.id)
    into v_tasks
    from app.load_tasks(p_date, p_date) l
    join work_board_view v on v.id = l.task_id
   where l.win && tstzrange((p_date::timestamp       at time zone 'Asia/Jerusalem'),
                            ((p_date + 1)::timestamp at time zone 'Asia/Jerusalem'), '[)');

  return jsonb_build_object(
    'hours', coalesce(v_hours, '[]'::jsonb),
    'tasks', coalesce(v_tasks, '[]'::jsonb),
    'meta',  jsonb_build_object('date', p_date, 'capacity', v_cap, 'denied', false));
end $$;

revoke execute on function load_day(date) from anon, public;
grant  execute on function load_day(date) to authenticated;

comment on function load_day(date) is
  'הפילוח השעתי של יום אחד במפת העומסים (0173), ולצדו המשימות שנוגעות בו — '
  'גם אחת של אתמול שנמשכת לתוכו וגם יציאה למחסן שנסוגה אליו מהיום שאחריו.';

-- ===== 8. השומר של 0164, על מה שנוצר כאן ===================================
--
-- אותה בדיקה בדיוק, מצומצמת לארבע הפונקציות של הקובץ הזה: הן רצות *אחרי*
-- ‏0164 ולכן הבדיקה שם אינה יכולה לראות אותן. שלוש מהן invoker וקוראות
-- ל-`app.has`, ל-`app.load_capacity`, ל-`app.load_slots`, ל-`app.load_tasks`,
-- ל-`app.load_denied`, ל-`app.scope_rows` ול-`app.warehouse_start_at`.
do $$
declare
  v_bad text;
begin
  select string_agg(format('%s.%s → app.%s', pub.nspname, pub.proname, h.proname), ', ')
    into v_bad
    from (select p.oid, n.nspname, p.proname, p.prosrc
            from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname in ('public', 'app') and not p.prosecdef
             and p.proname in ('load_heatmap', 'load_day', 'load_slots', 'load_tasks',
                               'load_denied')
             and has_function_privilege('authenticated', p.oid, 'EXECUTE')) pub
    join (select p.oid, p.proname
            from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'app'
             and not has_function_privilege('authenticated', p.oid, 'EXECUTE')) h
      on pub.prosrc ~* ('app\.' || h.proname || '\s*\(');

  if v_bad is not null then
    raise exception
      'פונקציית invoker של מפת העומסים קוראת לעוזר ב-app שאין ל-authenticated הרשאה להריץ: %',
      v_bad;
  end if;
end $$;
