-- ‏0181: מפת עומסים — המפה סופרת את מה שנדרש, ואת כל המשימות
--
-- שלוש תלונות, ושלושתן על אותו דבר: המפה ענתה על "מה כבר סודר" במקום על
-- ‏**"מה צריך לסדר"**, ולכן דווקא ביום שאיש עוד לא נגע בו היא הראתה ריק.
--
--   1. **משאיות.** ‏0173 ספרה `truck_ids` — המשאיות שכבר שובצו למשימה.
--      משימה שדורשת שלוש ואין לה אף אחת נספרה כאפס, וכך הממד שנועד להזהיר
--      מפני חוסר דיווח על חוסר רק אחרי שהוא כבר נפתר. מעכשיו הספירה היא
--      ‏`events.truck_count` — **הדרישה** — ולצדה, בנפרד, מה שכבר שובץ.
--   2. **ראשי צוות.** ‏`tasks.requires_team_lead` נקבע במחשבון התמחור, ושם
--      ברירת המחדל היא `false`; רוב המשימות במערכת נושאות אותו ריק או שקרי,
--      והמפה הסיקה מכך "אין צורך בראש צוות" על כמעט כל יום. הכלל האמיתי
--      נאמר במפורש: **כל משימה דורשת ראש צוות, למעט הובלה בלבד ואיסוף
--      עצמי.** הכלל הזה יושב עכשיו על אופן הביצוע — נתון, לא ניחוש — והוא
--      ניתן לעריכה בהגדרות ככל שיתווספו אופני ביצוע נוספים.
--   3. **משימות שנעלמו.** ‏`app.load_tasks` דרשה שעת התחלה ומשך גדול מאפס,
--      ולכן משימה בלי שעה נשרה מהציר — וגם מספירת המשימות של היום, מהדרישה
--      לעובדים, ומרשימת "מה רץ ביום הזה". יום עם תשע משימות שלשלוש מהן יש
--      שעה הראה "3". מעכשיו כל משימות היום נמצאות: מי שאין לה שעה אינה
--      יכולה לשבת על ציר השעות — אין לה מקום שם — אבל היא נספרת בסך היומי,
--      בדרישה, וברשימה, ומסומנת "ללא שעה".
--
-- ===== "שובץ מתוך נדרש" ====================================================
--
-- כל ממד חוזר עכשיו כזוג: הדרישה, ולצדה האיוש. העומס נמדד מול הדרישה — היא
-- מה שהיום מחייב — והאיוש הוא מה שכבר נפתר ממנה. שני המספרים נחוצים: אחד
-- אומר "כמה עבודה", והשני "כמה ממנה כבר לא שלי".

drop function if exists load_heatmap(date, date, text, uuid);
drop function if exists load_day(date, text, uuid);
drop function if exists app.load_slots(date, date, text, uuid);
drop function if exists app.load_tasks(date, date, text, uuid);

-- ===== 1. הכלל של ראש הצוות יושב על אופן הביצוע ============================
--
-- ‏`not null default true` — ברירת המחדל היא **כן**, כי זה הכלל: אופן ביצוע
-- חדש שמישהו יוסיף מחר ידרוש ראש צוות עד שייאמר אחרת, ולא להפך. שני
-- הפטורים נזרעים כאן: מה שמסומן `is_transport_only` (‏0092), ולצדו שני
-- השמות שהמשרד נקב בהם — "הובלה בלבד" ו"איסוף עצמי". השם נדרש **בזריעה
-- בלבד**, כי `is_transport_only` אינו נזרע לאף שורה ב-0092 והוא אינו מסומן
-- בהתקנות קיימות; מכאן והלאה הכלל יושב על העמודה ולא על השם, והוא נערך
-- במסך ההגדרות.
alter table execution_methods
  add column if not exists requires_team_lead boolean not null default true;

comment on column execution_methods.requires_team_lead is
  'האם משימה באופן ביצוע זה דורשת ראש צוות (0181). ברירת המחדל כן; הובלה '
  'בלבד ואיסוף עצמי נזרעו כלא-נדרש. מפת העומסים סופרת לפי העמודה הזו.';

update execution_methods
   set requires_team_lead = false
 where requires_team_lead
   and (is_transport_only or btrim(name) in ('הובלה בלבד', 'איסוף עצמי'));

-- ===== 2. המשימות שעל הציר — ועכשיו גם אלה שאין להן שעה ====================
--
-- ‏`win` הוא `null` למשימה בלי שעה, וזו אמירה ולא חוסר: אין לה מקום על ציר
-- השעות, ו-`&&` מול `null` אינו מתלכד עם אף משבצת — כך היא נופלת מהשעות
-- מאליה, בלי שאף צרכן יצטרך לזכור לסנן אותה. ‏`timed` הוא אותו מידע בצורה
-- שאפשר לספור בה.
create or replace function app.load_tasks(
  p_from date,
  p_to date,
  p_scope text default 'all',
  p_contractor_id uuid default null
)
returns table (
  task_id         uuid,
  task_date       date,
  event_id        uuid,
  timed           boolean,
  win             tstzrange,
  worker_need     int,
  staffed         int,
  needs_lead      boolean,
  lead_staffed    int,
  truck_need      int,
  truck_ids       uuid[],
  trucks_assigned int,
  customer_id     uuid,
  site            text,
  warehouse       uuid,
  delegated       boolean,
  contractor_id   uuid
)
language sql stable security invoker set search_path = public as $$
  select
    t.id,
    t.task_date,
    t.event_id,
    (coalesce(t.onsite_start_time, t.warehouse_start_time) is not null
       and coalesce(t.hours_count, 0) > 0) as timed,
    case
      when coalesce(t.onsite_start_time, t.warehouse_start_time) is null
        or coalesce(t.hours_count, 0) = 0 then null
      else tstzrange(
        case when t.warehouse_start_time is not null
             then app.warehouse_start_at(t.task_date, t.warehouse_start_time,
                                         t.onsite_start_time)
             else ((t.task_date + t.onsite_start_time) at time zone 'Asia/Jerusalem') end,
        ((t.task_date + coalesce(t.onsite_start_time, t.warehouse_start_time))
          at time zone 'Asia/Jerusalem')
          + make_interval(mins => round(coalesce(t.hours_count, 0) * 60)::int),
        '[)')
    end,
    t.worker_count,
    (select count(distinct a.profile_id) from task_assignments a where a.task_id = t.id)
    + (select count(*) from task_contractor_workers w where w.task_id = t.id)
    + (select count(*) from task_customer_workers o where o.task_id = t.id),
    /* הכלל של 0181: אופן הביצוע מכריע, ודריסה מפורשת על המשימה יכולה רק
       להוסיף דרישה ולא לבטל אותה. משימה בלי אופן ביצוע — נדרש, כי זו
       ברירת המחדל של הכלל. */
    coalesce(em.requires_team_lead, true) or coalesce(t.requires_team_lead, false),
    /* ראש צוות אחד לכל היותר מכל מקור (0003, ‏0121, ‏0133), ולכן 0 או 1. */
    (case when exists (select 1 from task_assignments a
                        where a.task_id = t.id and a.role = 'team_lead')
            or exists (select 1 from task_contractor_workers w
                        where w.task_id = t.id and w.role = 'team_lead')
            or exists (select 1 from task_customer_workers o
                        where o.task_id = t.id and o.role = 'team_lead')
          then 1 else 0 end),
    /* הדרישה למשאיות באה מהאירוע — זה השדה שבו היא נאמרת (‏`truck_count`,
       ‏0003, והוא גם משתנה במחשבון התמחור). בהיעדרו, מה ששובץ הוא הידיעה
       הטובה ביותר על הדרישה: עדיף להעריך לפי מה שכבר נעשה מאשר להכריז
       אפס על משימה שברור שיש בה משאית. */
    case when e.truck_count is not null then e.truck_count
         else coalesce(cardinality(t.truck_ids), 0) end,
    t.truck_ids,
    coalesce(cardinality(t.truck_ids), 0),
    t.customer_id,
    nullif(btrim(coalesce(t.location_text, e.location_text, '')), ''),
    coalesce(t.warehouse_id, c.warehouse_id),
    t.contractor_id is not null,
    t.contractor_id
  from tasks t
  left join events e            on e.id = t.event_id
  left join statuses es         on es.id = e.status_id
  left join customers c         on c.id = t.customer_id
  left join execution_methods em on em.id = t.execution_method_id
  where t.deleted_at is null
    and coalesce(es.code, '') <> 'cancelled'
    and (
      /* משימה מתוזמנת: הטווח רחב יום לכל צד, כי החלון שלה יכול לגלוש
         (‏0163). משימה בלי שעה: אין לה חלון שיגלוש, ולכן היא נספרת ביום
         שלה בלבד ואינה נשפכת אל הימים השכנים. */
      case when coalesce(t.onsite_start_time, t.warehouse_start_time) is null
                or coalesce(t.hours_count, 0) = 0
           then t.task_date between p_from and p_to
           else t.task_date between p_from - 1 and p_to
                or (t.task_date = p_to + 1
                    and t.warehouse_start_time is not null
                    and t.onsite_start_time is not null
                    and t.warehouse_start_time > t.onsite_start_time)
      end
    )
    and (
      case
        when p_scope = 'internal' then t.contractor_id is null
        when p_scope = 'contractor' then
          case
            when p_contractor_id is not null then t.contractor_id = p_contractor_id
            else t.contractor_id is not null
          end
        else true
      end
    )
$$;

grant execute on function app.load_tasks(date, date, text, uuid) to authenticated;

comment on function app.load_tasks(date, date, text, uuid) is
  'משימות הטווח עם החלון שלהן ועם מה שהן **דורשות** ומה שכבר אויש (0181). '
  'משימה בלי שעה חוזרת עם win = null: היא נספרת ביום, לא בשעה.';

-- ===== 3. משבצות השעה ======================================================
--
-- ‏`trucks` הוא מעכשיו **הדרישה**. משאית נספרת פעם אחת לאירוע גם כששתי
-- משימות שלו חופפות — ‏`truck_count` הוא של האירוע, וסכימה תמימה הייתה
-- מכפילה אותו — ומשימה בלי אירוע נספרת בפני עצמה.
create or replace function app.load_slots(
  p_from date,
  p_to date,
  p_scope text default 'all',
  p_contractor_id uuid default null
)
returns table (
  slot_day        date,
  slot_hour       int,
  tasks           int,
  workers         int,
  staffed         int,
  trucks          int,
  trucks_assigned int,
  leads           int,
  leads_staffed   int,
  customers       int,
  sites           int,
  warehouses      int,
  delegated       int
)
language sql stable security invoker set search_path = public as $$
  with lt as (
    select * from app.load_tasks(p_from, p_to, p_scope, p_contractor_id) where timed
  ),
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
    (select coalesce(sum(x.n), 0)
       from (select coalesce(l2.event_id::text, l2.task_id::text) as k,
                    max(l2.truck_need) as n
               from lt l2 where l2.win && s.win
              group by 1) x)::int,
    /* מה שכבר שובץ: משאית שמשרתת שתי משימות חופפות היא משאית אחת תפוסה. */
    (select count(distinct u.tid)
       from lt l2, lateral unnest(l2.truck_ids) u(tid)
      where l2.win && s.win)::int,
    coalesce(sum(case when l.needs_lead then 1 else 0 end), 0)::int,
    coalesce(sum(l.lead_staffed), 0)::int,
    count(distinct l.customer_id)::int,
    count(distinct l.site)::int,
    count(distinct l.warehouse)::int,
    coalesce(sum(case when l.delegated then 1 else 0 end), 0)::int
  from slots s
  left join lt l on l.win && s.win
  group by s.slot_day, s.slot_hour, s.win
$$;

grant execute on function app.load_slots(date, date, text, uuid) to authenticated;

comment on function app.load_slots(date, date, text, uuid) is
  'שורה לכל (יום, שעה) עם מה שנדרש באותו רגע ומה שאויש ממנו (0181). '
  'משאיות נספרות לפי דרישת האירוע, פעם אחת לאירוע.';

-- ===== 4. המפה החודשית =====================================================

create or replace function load_heatmap(
  p_from date,
  p_to date,
  p_scope text default 'all',
  p_contractor_id uuid default null
)
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
  if p_to - p_from > 400 then
    raise exception 'טווח גדול מדי' using errcode = '22023'; end if;

  if app.load_denied() then
    return jsonb_build_object('days', null, 'meta', jsonb_build_object('denied', true));
  end if;

  v_cap := app.load_capacity(p_scope, p_contractor_id);

  with s as (select * from app.load_slots(p_from, p_to, p_scope, p_contractor_id)),
  lt as (select * from app.load_tasks(p_from, p_to, p_scope, p_contractor_id)),
  peaks as (
    select
      s.slot_day,
      max(s.tasks)            as peak_tasks,
      max(s.workers)          as peak_workers,
      max(s.trucks)           as peak_trucks,
      max(s.trucks_assigned)  as peak_trucks_assigned,
      max(s.leads)            as peak_leads,
      max(s.leads_staffed)    as peak_leads_staffed,
      max(s.sites)            as peak_sites,
      max(s.warehouses)       as peak_warehouses,
      count(*) filter (where s.tasks > 0) as busy_hours
    from s group by s.slot_day
  ),
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
  /* הסך של היום — **כל** משימות היום, גם אלה שאין להן שעה. `task_date` ולא
     החלון: משימה שיוצאת מהמחסן ב-23:00 של אתמול היא משימה של היום שלה,
     וכך היא מוצגת בכל מסך אחר. */
  totals as (
    select
      l.task_date as slot_day,
      count(*)::int                                   as tasks,
      count(*) filter (where l.timed)::int            as timed_tasks,
      count(*) filter (where not l.timed)::int        as untimed_tasks,
      coalesce(sum(l.worker_need), 0)::int            as worker_need,
      coalesce(sum(l.staffed), 0)::int                as staffed,
      coalesce(sum(greatest(l.worker_need - l.staffed, 0)), 0)::int as gap,
      coalesce(sum(case when l.needs_lead then 1 else 0 end), 0)::int as lead_need,
      coalesce(sum(case when l.needs_lead then l.lead_staffed else 0 end), 0)::int as lead_staffed,
      coalesce(sum(extract(epoch from (upper(l.win) - lower(l.win))) / 3600.0
                   * l.worker_need) filter (where l.timed), 0)::numeric as worker_hours,
      count(*) filter (where l.delegated)::int        as delegated,
      count(distinct l.customer_id)::int              as customers,
      count(distinct l.site)::int                     as sites
    from lt l
   where l.task_date between p_from and p_to
    group by l.task_date
  ),
  /* המשאיות של היום — פעם אחת לאירוע, כמו בשעה. */
  truck_day as (
    select x.task_date,
           coalesce(sum(x.n), 0)::int as truck_need,
           coalesce(sum(x.a), 0)::int as truck_assigned
      from (select l.task_date,
                   coalesce(l.event_id::text, l.task_id::text) as k,
                   max(l.truck_need) as n,
                   max(l.trucks_assigned) as a
              from lt l
             where l.task_date between p_from and p_to
             group by 1, 2) x
     group by x.task_date
  )
  select jsonb_agg(jsonb_build_object(
           'day',             (p_from + n),
           /* ‏`tasks` הוא כל משימות היום. `timed` הוא מה שיושב על ציר
              השעות, ו-`untimed` מה שלא — והסכום שלהם הוא `tasks`. */
           'tasks',           coalesce(tt.tasks, 0),
           'timed',           coalesce(tt.timed_tasks, 0),
           'untimed',         coalesce(tt.untimed_tasks, 0),
           'worker_need',     coalesce(tt.worker_need, 0),
           'staffed',         coalesce(tt.staffed, 0),
           'gap',             coalesce(tt.gap, 0),
           'lead_need',       coalesce(tt.lead_need, 0),
           'lead_staffed',    coalesce(tt.lead_staffed, 0),
           'truck_need',      coalesce(td.truck_need, 0),
           'truck_assigned',  coalesce(td.truck_assigned, 0),
           'worker_hours',    round(coalesce(tt.worker_hours, 0), 2),
           'delegated',       coalesce(tt.delegated, 0),
           'customers',       coalesce(tt.customers, 0),
           'sites',           coalesce(tt.sites, 0),
           'peak_hour',       ph.slot_hour,
           'peak_tasks',      coalesce(pk.peak_tasks, 0),
           'peak_workers',    coalesce(pk.peak_workers, 0),
           'peak_trucks',     coalesce(pk.peak_trucks, 0),
           'peak_trucks_assigned', coalesce(pk.peak_trucks_assigned, 0),
           'peak_leads',      coalesce(pk.peak_leads, 0),
           'peak_leads_staffed',   coalesce(pk.peak_leads_staffed, 0),
           'peak_sites',      coalesce(pk.peak_sites, 0),
           'peak_warehouses', coalesce(pk.peak_warehouses, 0),
           'busy_hours',      coalesce(pk.busy_hours, 0))
         order by n)
    into v_days
    from generate_series(0, p_to - p_from) g(n)
    left join peaks     pk on pk.slot_day  = (p_from + n)
    left join peak_hour ph on ph.slot_day  = (p_from + n)
    left join totals    tt on tt.slot_day  = (p_from + n)
    left join truck_day td on td.task_date = (p_from + n);

  return jsonb_build_object(
    'days', coalesce(v_days, '[]'::jsonb),
    'meta', jsonb_build_object(
      'from', p_from,
      'to', p_to,
      'capacity', v_cap,
      'scope', p_scope,
      'contractor_id', p_contractor_id,
      'denied', false));
end $$;

revoke execute on function load_heatmap(date, date, text, uuid) from anon, public;
grant  execute on function load_heatmap(date, date, text, uuid) to authenticated;

comment on function load_heatmap(date, date, text, uuid) is
  'המפה החודשית (0181): שורה ליום עם הפסגה השעתית ועם הסך של **כל** משימות '
  'היום — גם אלה שאין להן שעה. כל ממד חוזר כדרישה ולצדה האיוש.';

-- ===== 5. הפילוח השעתי של יום ==============================================

create or replace function load_day(
  p_date date,
  p_scope text default 'all',
  p_contractor_id uuid default null
)
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

  v_cap := app.load_capacity(p_scope, p_contractor_id);

  select jsonb_agg(jsonb_build_object(
           'hour',            s.slot_hour,
           'tasks',           s.tasks,
           'workers',         s.workers,
           'staffed',         s.staffed,
           'gap',             greatest(s.workers - s.staffed, 0),
           'trucks',          s.trucks,
           'trucks_assigned', s.trucks_assigned,
           'leads',           s.leads,
           'leads_staffed',   s.leads_staffed,
           'customers',       s.customers,
           'sites',           s.sites,
           'warehouses',      s.warehouses,
           'delegated',       s.delegated)
         order by s.slot_hour)
    into v_hours
    from app.load_slots(p_date, p_date, p_scope, p_contractor_id) s;

  /* המשימות שנוגעות ביום — מתוזמנות שהחלון שלהן חופף אותו (לרבות אחת של
     אתמול שנמשכת לתוכו ויציאה למחסן שנסוגה אליו, 0163), וגם משימות היום
     שאין להן שעה: אין להן חלון, אבל הן כן עבודה של היום הזה. */
  select jsonb_agg(jsonb_build_object(
           'task_id',     v.id,
           'task_date',   v.task_date,
           'label',       coalesce(nullif(v.title, ''), v.end_client_name,
                                   v.customer_name, v.task_type_name),
           'task_type',   v.task_type_name,
           'customer',    v.customer_name,
           'color',       v.customer_color,
           'timed',       l.timed,
           'start',       lower(l.win),
           'end',         upper(l.win),
           'worker_need', l.worker_need,
           'staffed',     l.staffed,
           'needs_lead',  l.needs_lead,
           'lead_staffed', l.lead_staffed,
           'truck_need',  l.truck_need,
           'trucks',      l.trucks_assigned,
           'truck_names', v.truck_list,
           'site',        l.site,
           'delegated',   l.delegated,
           'contractor_id', l.contractor_id,
           'status_name', v.status_name,
           'status_color', v.status_color)
         /* הלא-מתוזמנות בסוף: אין להן מקום על הציר, ולכן גם לא בין השעות. */
         order by l.timed desc, lower(l.win), v.id)
    into v_tasks
    from app.load_tasks(p_date, p_date, p_scope, p_contractor_id) l
    join work_board_view v on v.id = l.task_id
   where (l.timed
          and l.win && tstzrange((p_date::timestamp       at time zone 'Asia/Jerusalem'),
                                 ((p_date + 1)::timestamp at time zone 'Asia/Jerusalem'), '[)'))
      or (not l.timed and l.task_date = p_date);

  return jsonb_build_object(
    'hours', coalesce(v_hours, '[]'::jsonb),
    'tasks', coalesce(v_tasks, '[]'::jsonb),
    'meta',  jsonb_build_object(
      'date', p_date,
      'capacity', v_cap,
      'scope', p_scope,
      'contractor_id', p_contractor_id,
      'denied', false));
end $$;

revoke execute on function load_day(date, text, uuid) from anon, public;
grant  execute on function load_day(date, text, uuid) to authenticated;

comment on function load_day(date, text, uuid) is
  'הפילוח השעתי של יום, ולצדו כל משימות היום — לרבות משימה בלי שעה, '
  'שחוזרת עם timed = false ובלי חלון (0181).';

-- ===== 6. השומר של 0164, על מה שנוצר כאן ===================================
do $$
declare
  v_bad text;
begin
  select string_agg(format('%s.%s → app.%s', pub.nspname, pub.proname, h.proname), ', ')
    into v_bad
    from (select p.oid, n.nspname, p.proname, p.prosrc
            from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname in ('public', 'app') and not p.prosecdef
             and p.proname in ('load_heatmap', 'load_day', 'load_slots', 'load_tasks')
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
