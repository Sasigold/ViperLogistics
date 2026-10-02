-- 0203: הקיר נותן שם לכל צוות — `crew_names` בכל משימה בפיד
--
-- הווידג׳ט "צוותי שטח היום" שעל הקיר מציג מי עומד על כל משימה, ולא רק כמה.
-- ‏`tasks[]` של הפיד (0202) נשא עד היום מונים בלבד: ‏`assigned` (כמה אנשים),
-- ‏`team_lead_name`, ‏`contractor_names` ו-`trucks`. אין בהם שם של אף אחד מהצוות
-- חוץ מראש הצוות, והקיר לא יכול לנחש אותם — אין לו גישה לשום טבלה (0202).
--
-- ההוספה היא שדה אחד, ותוספת בלבד (החוזה של הפיד אינו קשיח, ‏`v` נשאר 1):
--
--   * ‏**`crew_names`** — מערך שמות (טקסט) של הצוות של המשימה, **אנשים** ולא
--     שורות: בדיוק ההגדרה של `assigned` ב-`app.wall_task_rows` (0201 §3 ו-0202 §3)
--     — פרופילים נבדלים מ-`task_assignments`, ועוד עובדי הקבלן מ-
--     `task_contractor_workers`, ועוד עובדי הלקוח מ-`task_customer_workers`.
--     מי שמשובץ גם כעובד וגם כנהג הוא שורה אחת במערך, כמו שהוא אדם אחד ב-
--     `assigned`.
--   * ‏**הסדר:** ראש הצוות ראשון, ואחריו כל השאר לפי האלף-בית (לפי ה-collation
--     של המסד, כמו שאר רשימות השמות בלו״ז), ובשוויון — לפי המזהה, כדי שהסדר יהיה
--     יציב בין קריאות. ראש הצוות הוא **אותה בחירה** של `team_lead_name`:
--     ראש צוות פנימי, ובהיעדרו ראש צוות של הקבלן, ובהיעדרו ראש צוות של הלקוח.
--     (לכל מאגר יש לכל היותר אחד — ‏`*_one_lead`; אם בכל זאת יושבים ראשי צוות
--     בשני מאגרים, הראשון בסדר הזה הוא שיוצא ראשון והאחר ממוין עם כולם.)
--   * ‏**שמות בלבד** (כלל 7): שם של עובד פנימי מ-`profiles.full_name`, ושל עובד
--     קבלן ועובד לקוח דרך `app.contractor_worker_identities` ו-
--     ‏`app.customer_worker_identities` (0201 §1), כמו ש-`team_lead_name` עושה.
--     אין טלפון, אין ת״ז, אין שכר ואין מזהה — לא כאן ולא ליד.
--   * ‏**תקרה של 40 שמות.** משימה גדולה לא תנפח את הפיד; מי שמעבר לארבעים נחתך
--     מסוף הרשימה (ראש הצוות נשאר ראשון), ו-`assigned` ממשיך לומר את המספר האמיתי.
--   * ‏**שם ריק מדלגים עליו.** ‏`full_name` הוא `not null` בשלוש הטבלאות, ולכן
--     "ריק" פירושו מחרוזת ריקה או רווחים בלבד. אין בקוד מוסכמה למקום-מחזיק
--     לשם חסר (שאר שדות השמות בפיד אינם ממציאים ערך במקום שם), ולא המצאנו כזו:
--     אדם בלי שם אינו מוצג. לכן `cardinality(crew_names)` שווה ל-`assigned`
--     בדיוק, חוץ משני מקרים — יש בצוות אדם בלי שם (הפער הוא מספרם), או שהצוות
--     עולה על ארבעים (התקרה). הבדיקות (58) מוודאות את השוויון על כל משימות
--     התמונה, ואת שני החריגים בנפרד. השמות יוצאים כפי ששמורים, בלי חיתוך
--     רווחים — כדי שהאיבר הראשון ב-`crew_names` יהיה זהה אות באות ל-`team_lead_name`.
--
-- מה שלא זז: הרשימה עדיין מסננת את `hidden_on_board` החוצה (משימה כזו אינה ב-
-- `tasks[]`, ולכן גם השמות שלה אינם), המונים וההתראות נספרים כמקודם, וכך המשמרות,
-- הנוכחות, הצי והכספים. ‏`app.wall_task_rows` **אינה משנה חתימה** — שינוי עמודות
-- ה-OUT שלה היה דורש drop — והעוזר החדש נקרא מבניית ה-JSON, רק עבור השורות
-- שנכנסות לרשימה (קומץ משימות בתמונה, ולכל אחת שלוש שליפות לפי אינדקס).
-- פונקציית הקצה `wall-feed` מעבירה את ה-JSON כמות שהוא, ולכן אינה משתנה ואינה
-- צריכה פריסה מחדש.

-- ===== 1. העוזר: שמות הצוות של משימה, ראש הצוות ראשון ========================
--
-- ‏`security definer`, כמו `app.wall_task_rows`: הקורא הוא בעל הפונקציה ולא
-- `authenticated`, ולכן ה-views של הזהות (0201) מחזירים את כל השמות. העוזר אינו
-- בודק אם המשימה חיה, מוסתרת או של ארקו — זו ההחלטה של `app.wall_task_rows`
-- שהוא נקרא ממנה, והוא נשלל מכולם (§3), כך שאין דרך אחרת להגיע אליו.
--
-- ‏`crew` הוא אדם אחד בשורה אחת מכל מאגר: הצוות הפנימי מקובץ לפי הפרופיל (שורת
-- תפקיד לכל תפקיד, ולכן עובד-ונהג הם שתי שורות שהופכות לאחת), ושני המאגרים
-- האחרים הם כבר שורה לאדם — המפתח הראשי שלהם הוא (task_id, worker_id).
-- ‏`picked` מסמן את ראש הצוות הנבחר: הראשון לפי (מאגר, מזהה) מבין מי שהוא ראש
-- צוות, באותו סדר מאגרים ש-`team_lead_name` נבחר בו.

create or replace function app.wall_task_crew(p_task_id uuid)
returns text[]
language sql stable security definer set search_path = public as $$
  with crew as (
    select 1 as pool, a.profile_id as pid, p.full_name as name,
           bool_or(a.role = 'team_lead') as is_lead
      from task_assignments a
      join profiles p on p.id = a.profile_id
     where a.task_id = p_task_id
     group by a.profile_id, p.full_name
    union all
    select 2, x.contractor_worker_id, cw.full_name, coalesce(x.role = 'team_lead', false)
      from task_contractor_workers x
      join app.contractor_worker_identities cw on cw.id = x.contractor_worker_id
     where x.task_id = p_task_id
    union all
    select 3, x.customer_worker_id, cuw.full_name, coalesce(x.role = 'team_lead', false)
      from task_customer_workers x
      join app.customer_worker_identities cuw on cuw.id = x.customer_worker_id
     where x.task_id = p_task_id
  ),
  ranked as (
    select c.*,
           (c.is_lead
            and row_number() over (order by c.is_lead desc, c.pool, c.pid) = 1) as picked
      from crew c
  )
  select coalesce(
           (array_agg(r.name order by r.picked desc, r.name, r.pid)
              filter (where r.name ~ '\S'))[1:40],
           '{}'::text[])
    from ranked r
$$;

comment on function app.wall_task_crew(uuid) is
  'שמות הצוות של משימה למסך הקיר (0203): אנשים — אותה הגדרה של assigned ב-'
  'app.wall_task_rows (פרופילים נבדלים + עובדי קבלן + עובדי לקוח) — ראש הצוות '
  'ראשון (אותה בחירה של team_lead_name), ואחריו כולם לפי האלף-בית ובשוויון לפי '
  'מזהה; עד 40 שמות, שם ריק מדלגים עליו. שמות בלבד: בלי טלפון, ת״ז, שכר או '
  'מזהה. אינה בודקת אם המשימה חיה — זו ההחלטה של app.wall_task_rows. נשללת מכולם.';

-- ===== 2. התמונה: אותו גוף של 0202, ושדה אחד נוסף ==========================
--
-- הגוף הוא הגוף של `app.wall_snapshot_at` מ-0202 §4, מילה במילה, כולל
-- `set timezone to 'UTC'` וכל ההערות. ההבדל היחיד הוא השורה
-- `'crew_names', to_jsonb(app.wall_task_crew(r.id))` ב-`tasks[]`, מיד אחרי
-- `team_lead_name`.

create or replace function app.wall_snapshot_at(p_now timestamptz, p_days int default 3)
returns jsonb
language plpgsql stable security definer
set search_path = public
-- חותמות הזמן ב-JSON יוצאות באזור הזמן של הסשן. UTC קבוע הופך אותן
-- ל-"…+00:00" בכל קריאה, בלי קשר למי שקרא.
set timezone to 'UTC'
as $$
declare
  v_now        timestamptz := coalesce(p_now, now());
  v_today      date;
  v_days       int := greatest(1, least(coalesce(p_days, 3), 14));
  v_week       date;
  v_month      date;
  v_month_end  date;
  v_horizon    timestamptz;
  v_auto       interval;
  v_tasks      jsonb;
  v_kpis       jsonb;
  v_under      jsonb;
  v_unpub      jsonb;
  v_shifts     jsonb;
  v_att        jsonb;
  v_late       jsonb;
  v_fleet      jsonb;
  v_margin     jsonb;
  v_forecast   numeric;
begin
  v_today     := (v_now at time zone 'Asia/Jerusalem')::date;
  -- השבוע מתחיל ביום ראשון (dow = 0)
  v_week      := v_today - extract(dow from v_today)::int;
  v_month     := make_date(extract(year from v_today)::int, extract(month from v_today)::int, 1);
  v_month_end := (v_month + interval '1 month')::date - 1;
  v_horizon   := v_now + interval '48 hours';
  -- אותו סף ואותה ברירת מחדל שהשעון סוגר בהם החתמה שנשכחה (0168)
  v_auto      := make_interval(hours => coalesce(
                   (app.attendance_config('attendance.clock') ->> 'auto_close_after_hours')::int, 16));

  -- ‏4.1 המשימות: הרשימה, המונים, ושתי רשימות ההתראה. טווח אחד שמכסה את
  -- שלושתם — הרשימה עד today+days, המונים שבעה ימים, וההתראות 48 שעות.
  with r as materialized (
    select x.*,
           -- ב-48 השעות הקרובות: מתחילה לפני האופק, ועוד לא נגמרה. משימה
           -- בלי שעה נשארת עד סוף היום שלה.
           (x.task_date <= v_today + 2
            and coalesce(x.start_at, x.task_date::timestamp at time zone 'Asia/Jerusalem') < v_horizon
            and case when x.end_at is not null then x.end_at > v_now
                     else x.task_date >= v_today end) as in_48h
      from app.wall_task_rows(v_today, v_today + greatest(v_days, 6)) x
  )
  select
    coalesce((select jsonb_agg(jsonb_build_object(
                'id',               r.id,
                'date',             r.task_date,
                'type_code',        r.type_code,
                'type_name',        r.type_name,
                'status_code',      r.status_code,
                'status_name',      r.status_name,
                'status_color',     r.status_color,
                'published',        r.published,
                'warehouse_at',     r.warehouse_at,
                'start_at',         r.start_at,
                'end_at',           r.end_at,
                'customer_name',    r.customer_name,
                'customer_color',   r.customer_color,
                'end_client_name',  r.end_client_name,
                'event_number',     r.event_number,
                'title',            r.title,
                'location',         r.location,
                'needed',           r.needed,
                'assigned',         r.assigned,
                'delegated',        r.delegated,
                'contractor_names', to_jsonb(r.contractor_names),
                'team_lead_name',   r.team_lead_name,
                -- ‏0203: שמות הצוות, ראש הצוות ראשון — שמות בלבד
                'crew_names',       to_jsonb(app.wall_task_crew(r.id)),
                'trucks',           to_jsonb(r.trucks))
                order by r.task_date, r.start_at nulls last, r.warehouse_at nulls last,
                         r.label, r.id)
                from r
               where r.task_date <= v_today + v_days and not r.hidden), '[]'::jsonb),
    (select jsonb_build_object(
       'tasks_today',      count(*) filter (where r.task_date = v_today),
       'setups_today',     count(*) filter (where r.task_date = v_today and r.type_code = 'setup'),
       'teardowns_today',  count(*) filter (where r.task_date = v_today and r.type_code = 'teardown'),
       'tasks_next_7d',    count(*) filter (where r.task_date <= v_today + 6),
       'understaffed_48h', count(*) filter (where r.in_48h and not r.status_terminal
                                              and r.needed > r.assigned),
       'unpublished_48h',  count(*) filter (where r.in_48h and not r.status_terminal
                                              and not r.published))
       from r),
    coalesce((select jsonb_agg(jsonb_build_object(
                'task_id', u.id, 'date', u.task_date, 'label', u.label,
                'needed', u.needed, 'assigned', u.assigned)
                order by u.start_at nulls last, u.task_date, u.label, u.id)
                from (select * from r
                       where r.in_48h and not r.status_terminal and r.needed > r.assigned
                       order by r.start_at nulls last, r.task_date, r.label, r.id
                       limit 10) u), '[]'::jsonb),
    coalesce((select jsonb_agg(jsonb_build_object(
                'task_id', u.id, 'date', u.task_date, 'label', u.label)
                order by u.start_at nulls last, u.task_date, u.label, u.id)
                from (select * from r
                       where r.in_48h and not r.status_terminal and not r.published
                       order by r.start_at nulls last, r.task_date, r.label, r.id
                       limit 10) u), '[]'::jsonb)
    into v_tasks, v_kpis, v_under, v_unpub;

  -- ‏4.2 במשמרת עכשיו: החתמה פתוחה שצעירה מסף הסגירה האוטומטית, ושלא נדחתה.
  -- התווית היא של המשימה הראשונה של ההחתמה — ‏task_ids ממוינות כמו המשמרת
  -- (0034).
  select coalesce(jsonb_agg(jsonb_build_object(
           'profile_id',   e.profile_id,
           'name',         p.full_name,
           'clock_in_at',  e.clock_in_at,
           'work_site',    e.work_site,
           'hours_so_far', round(extract(epoch from (v_now - e.clock_in_at)) / 3600.0, 2),
           'task_label',   (select concat_ws(' · ', c.name,
                                     coalesce(nullif(btrim(t.title), ''),
                                              nullif(btrim(ev.end_client_name), ''), tt.name))
                              from tasks t
                              join task_types tt on tt.id = t.task_type_id
                              left join events ev on ev.id = t.event_id
                              left join app.customer_identities c on c.id = t.customer_id
                             where t.id = e.task_ids[1]))
           order by e.clock_in_at, p.full_name), '[]'::jsonb)
    into v_shifts
    from attendance_entries e
    join profiles p on p.id = e.profile_id
   where e.clock_out_at is null
     and e.deleted_at is null
     and e.status <> 'rejected'
     and e.clock_in_at <= v_now
     and e.clock_in_at > v_now - v_auto;

  -- ‏4.3 שעות: מאושרות שנסגרו, ועוד השעות החיות של הפתוחות (באותה הגדרה של
  -- 4.2). החתמה שנדחתה אינה עבודה, ולכן גם אינה "עובד היום".
  with ent as (
    select e.profile_id, e.work_date,
           (e.clock_out_at is null and e.clock_in_at <= v_now
            and e.clock_in_at > v_now - v_auto) as is_open,
           case when e.clock_out_at is null then
                  case when e.clock_in_at <= v_now and e.clock_in_at > v_now - v_auto
                       then extract(epoch from (v_now - e.clock_in_at)) / 3600.0 else 0 end
                when e.status = 'approved' then coalesce(e.actual_hours, 0)
                else 0 end as hrs
      from attendance_entries e
     where e.deleted_at is null
       and e.status <> 'rejected'
       and e.work_date between v_week and v_today
  ),
  today_by as (
    select ent.profile_id, sum(ent.hrs) as hrs, bool_or(ent.is_open) as is_open
      from ent where ent.work_date = v_today
     group by ent.profile_id
  )
  select jsonb_build_object(
           'hours_today',   round(coalesce((select sum(hrs) from ent where work_date = v_today), 0), 2),
           'hours_week',    round(coalesce((select sum(hrs) from ent), 0), 2),
           'workers_today', (select count(*) from today_by),
           'by_worker_today', coalesce((
              select jsonb_agg(jsonb_build_object(
                       'profile_id', b.profile_id,
                       'name',       p.full_name,
                       'hours',      round(b.hrs, 2),
                       'open',       b.is_open)
                       order by b.hrs desc, p.full_name)
                from today_by b join profiles p on p.id = b.profile_id), '[]'::jsonb))
    into v_att;

  -- ‏4.4 מאחרים: ROADMAP §3.4. המועמדים הם מי שמשובץ למשימה **משובצת** היום
  -- או מחר — מחר, כי יציאה מהמחסן יכולה לסגת אל הערב של היום (0163).
  -- ‏`app.planned_shifts_many` גוזרת את המשמרת משלושת המאגרים (0178), ומשם
  -- נשארות רק אלה שהתחילו היום לפני יותר מ-15 דקות, בלי אף החתמה היום.
  with live as (
    select x.id from app.wall_task_rows(v_today, v_today + 1) x where x.published
  ),
  cand as (
    select a.profile_id as pid
      from task_assignments a join live l on l.id = a.task_id
    union
    select pr.id
      from task_contractor_workers w
      join live l on l.id = w.task_id
      join profiles pr on pr.contractor_worker_id = w.contractor_worker_id
    union
    select pr.id
      from task_customer_workers w
      join live l on l.id = w.task_id
      join profiles pr on pr.customer_worker_id = w.customer_worker_id
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'profile_id',    s.profile_id,
           'name',          p.full_name,
           'planned_start', s.shift_start,
           'minutes_late',  floor(extract(epoch from (v_now - s.shift_start)) / 60)::int,
           'task_label',    concat_ws(' · ', c.name, s.label))
           order by s.shift_start, p.full_name), '[]'::jsonb)
    into v_late
    from app.planned_shifts_many(array(select pid from cand), v_today, v_today) s
    join profiles p on p.id = s.profile_id
    left join app.customer_identities c on c.id = s.customer_id
   where p.deleted_at is null
     and p.is_active
     and s.shift_start < v_now - interval '15 minutes'
     and not exists (select 1 from attendance_entries e
                      where e.profile_id = s.profile_id
                        and e.work_date = v_today
                        and e.deleted_at is null)
     and coalesce((app.clock_rules(s.profile_id) ->> 'clock_enabled')::boolean, true);

  v_att := v_att || jsonb_build_object('late', v_late);

  -- ‏4.5 מסמכי רכב: הסינון של 0174, התוקף מול התאריך בישראל. הנוסחה זו של
  -- ‏vehicle_document_status (0089): פג לפני היום, "עומד לפוג" עד ימי ההתראה
  -- של הסוג. בלי תקרה: הצי קטן, והקיר מדפדף רשימה ארוכה בעצמו.
  select coalesce(jsonb_agg(jsonb_build_object(
           'vehicle_name', d.vehicle_name,
           'plate_number', d.plate_number,
           'kind_name',    d.kind_name,
           'expires_at',   d.expires_at,
           'days_left',    d.days_left,
           'status',       d.status)
           order by d.expires_at, d.vehicle_name, d.kind_name), '[]'::jsonb)
    into v_fleet
    from (select v.name as vehicle_name, v.plate_number, k.name as kind_name,
                 doc.expires_at, (doc.expires_at - v_today) as days_left,
                 case when doc.expires_at < v_today then 'expired' else 'expiring' end as status
            from vehicle_documents doc
            join vehicle_document_kinds k on k.id = doc.kind_id
            join vehicles v on v.id = doc.vehicle_id
           where doc.deleted_at is null and v.deleted_at is null and v.status <> 'sold'
             and doc.expires_at is not null
             and (doc.expires_at < v_today or doc.expires_at <= v_today + k.alert_days)) d;

  -- ‏4.6 כסף: כלל 6. מהחודש עד היום — הליבה של הרווח הגולמי; משאר החודש —
  -- אותו ביטוי הכנסה בדיוק, על מחר עד סוף החודש.
  v_margin := app.margin_summary_core(v_month, v_today);

  select coalesce((select sum(tp.price)
                     from app.task_revenue tp
                     join app.live_tasks t on t.id = tp.task_id and t.deleted_at is null
                    where t.task_date between v_today + 1 and v_month_end), 0)
       + coalesce((select sum(ei.amount)
                     from event_income ei
                     join app.live_events e on e.id = ei.event_id and e.deleted_at is null
                    where e.event_date between v_today + 1 and v_month_end), 0)
    into v_forecast;

  return jsonb_build_object(
    'v',            1,
    'source',       'viperlogistics',
    'generated_at', v_now,
    'today',        v_today,
    'days',         v_days,
    'tasks',        v_tasks,
    'shifts_now',   v_shifts,
    'attendance',   v_att,
    'kpis',         v_kpis || jsonb_build_object('workers_on_shift', jsonb_array_length(v_shifts)),
    'alerts', jsonb_build_object(
      'understaffed',        v_under,
      'unpublished',         v_unpub,
      'fleet_documents',     v_fleet,
      'attendance_pending',  (select count(*) from attendance_entries
                               where status = 'pending' and deleted_at is null),
      'correction_requests', (select count(*) from attendance_entries
                               where req_at is not null and deleted_at is null),
      -- ‏arco_outbound אינה מחזיקה מתי נכשלה, רק מתי נכנסה לתור (0184/0195)
      'integration_failures', jsonb_build_object(
        'viperflow', (select count(*) from viperflow_deliveries
                       where status = 'failed'
                         and received_at > v_now - interval '24 hours' and received_at <= v_now),
        'arco_in',   (select count(*) from arco_deliveries
                       where status = 'failed'
                         and received_at > v_now - interval '24 hours' and received_at <= v_now),
        'arco_out',  (select count(*) from arco_outbound
                       where status = 'failed'
                         and created_at > v_now - interval '24 hours' and created_at <= v_now))),
    'finance', jsonb_build_object(
      'month_start',            v_month,
      'month_end',              v_month_end,
      'revenue_mtd',            (v_margin ->> 'revenue')::numeric,
      'contractor_mtd',         (v_margin ->> 'contractor')::numeric,
      'payroll_mtd',            (v_margin ->> 'payroll')::numeric,
      'gross_mtd',              (v_margin ->> 'gross')::numeric,
      -- אחוזים (0..100), כפי ש-margin_summary מחזירה; null כשאין הכנסה
      'gross_pct',              (v_margin ->> 'pct')::numeric,
      'forecast_rest_of_month', round(v_forecast, 2),
      'unrated_shifts',         coalesce((v_margin ->> 'unrated_shifts')::int, 0)));
end $$;

comment on function app.wall_snapshot_at(timestamptz, int) is
  'התמונה של מסך הקיר ל"עכשיו" נתון (0202): משימות, במשמרת עכשיו, שעות, '
  'מאחרים, מונים, התראות וכספי החודש. כל משימה ברשימה נושאת גם crew_names — שמות '
  'הצוות, ראש הצוות ראשון (0203). p_days נחתך ל-1..14. נשללת מכולם — '
  'הדלת היחידה היא public.wall_snapshot מאחורי הסוד.';

-- ===== 3. ההרשאות ===========================================================
--
-- העוזר החדש נשלל מכולם, כמו שאר פונקציות ה-wall: ‏Supabase מעניק ל-anon,
-- ל-authenticated ול-service_role הרשאת הרצה כברירת מחדל ביצירה (ב-`public`;
-- ל-`app` אין ברירת מחדל כזו, אבל `PUBLIC` נותן הרצה לכולם), ולכן השלילה כאן
-- היא מה שסוגר אותו — כולל `service_role`, שאינו צריך אותו: `public.wall_snapshot`
-- היא security definer ופועלת בזהות הבעלים. ‏`app.wall_snapshot_at` נאמרת שוב:
-- ‏`create or replace` שומר הרשאות, אבל הקובץ עומד בפני עצמו. ‏`public.wall_snapshot`
-- אינה נוגעת — הדלת היחידה ש-service_role מריץ.
revoke all on function app.wall_task_crew(uuid)                  from public, anon, authenticated, service_role;
revoke all on function app.wall_snapshot_at(timestamptz, int)    from public, anon, authenticated, service_role;
