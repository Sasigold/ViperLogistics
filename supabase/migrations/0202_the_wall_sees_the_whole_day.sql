-- 0202: מסך הקיר רואה את כל היום — פיד קריאה בלבד ל-ViperGroup
--
-- ‏ROADMAP §3.4 ("אין חדר בקרה ליום האירוע") אומר שאין מסך שמציג בזמן אמת
-- מי בשטח מול מי שאמור להיות, ושהנתונים כבר קיימים — ‏`attendance_entries`
-- מול `app.planned_shifts_many` (0178). מסך הפיקוד שעל הקיר (ViperGroup)
-- הוא המסך הזה, ועוד: המשימות של היום והימים הקרובים, מי במשמרת עכשיו,
-- שעות הנוכחות, מי מאחר, מונים, התראות, וכספי החודש עד היום.
--
-- הקיר אינו משתמש: אין לו `auth.uid()`, ולכן כל `app.has()` שקר אצלו. אי
-- אפשר לקרוא לו את `work_board_view` (‏security_invoker, וזהויות 0201),
-- את `dashboard_sections` או את `app.margin_summary` — הראשון סגור, השני
-- מחזיר null לכל סקשן, והשלישי זורק 42501. ומפתח service role על הקיר
-- היה פותח את כל המסד למכשיר שתלוי בסלון. לכן המערכת הזו מחזיקה את הפיד
-- בעצמה, והקיר מחזיק רק סוד אחד שאפשר לבטל:
--
--   * ‏**פונקציית הקצה `wall-feed`** (‏`--no-verify-jwt`) מעבירה את הכותרת
--     `x-wall-secret` אל `public.wall_snapshot`, עם מפתח ה-service role
--     שהפלטפורמה מזריקה לה. הקיר אינו רואה את המפתח לעולם.
--   * ‏**ב-Vault יושב רק ה-sha256 של הסוד**, לא הסוד עצמו, ולא ב-
--     `app_settings` (כלל 9 — היא קריאה לכל משתמש מאומת). הוא נקבע ומוחלף
--     ב-SQL ולא במיגרציה. **אפשר כמה סודות במקביל**: כל שורה ב-Vault ששמה
--     מתחיל ב-`wall_feed_secret` נחשבת, והסוד מתקבל אם ה-sha256 שלו שווה לאחת
--     מהן — `wall_feed_secret` לפריסת Vercel, `wall_feed_secret_minipc` ל-Mini
--     PC, וכן הלאה. כל קיר מחזיק סוד משלו, ואפשר להחליף או לבטל אחד בלי
--     לגעת באחרים:
--       select vault.create_secret(encode(sha256(convert_to('<סוד>','UTF8')),'hex'),
--                                  'wall_feed_secret_minipc', 'sha256 of the Mini PC wall secret');
--   * ‏**שתי שגיאות בלבד, ואף אחת מהן אינה 42501** — כלל 4 שומר את 42501
--     להרשאות. סוד שגוי או קצר → ‏`28P01` (‏401 בפונקציית הקצה); אין ב-Vault
--     אף שורה תקינה (‏`wall_feed_secret%` שערכה 64 תווי hex) → ‏`55000` (‏503).
--     שורה שערכה אינו hash מתעלמים ממנה, ואינה מפילה את השורות התקינות.
--   * ‏**הלוגיקה ב-`app.wall_snapshot_at(p_now, p_days)`**, שמקבלת את "עכשיו"
--     כפרמטר, כדי שחבילת הבדיקות תוכל לנעוץ את הזמן — חצות של ישראל,
--     איחור של 90 דקות — במקום לקוות לשעון. היא נשללת מכולם.
--
-- "היום" הוא התאריך **בישראל**: `(now() at time zone 'Asia/Jerusalem')::date`.
-- המסד רץ ב-UTC, ובקיץ 21:30 UTC הוא כבר 00:30 של מחר.
--
-- מה נספר, ולמה:
--
--   * ‏**המשימות** נקראות מהטבלאות ולא מהלו״ז (‏work_board_view אינו פתוח
--     לכאן), עם הסינון של הלו״ז: לא נמחקה, האירוע לא נמחק ולא בוטל (0114),
--     ולא משימה שארקו מבצעת (0120/0135 — היא אינה של וייפר). ‏"משובץ" (0063)
--     הוא "פורסם". הצוות הוא **אנשים** (0201): אדם אחד פעם אחת, מכל שלושת
--     המאגרים. ‏`hidden_on_board` (0188) מוריד משימה **מהרשימה בלבד** — היא
--     עדיין נספרת במונים ובהתראות על חוסר בצוות, כי היא עדיין עבודה שתתבצע.
--   * ‏**במשמרת עכשיו** — החתמה פתוחה שצעירה מסף הסגירה האוטומטית של השעון
--     (`attendance.clock.auto_close_after_hours`, ‏0019/0168). החתמה ישנה
--     ממנו נשכחה, והשעון יסגור אותה בכניסה הבאה; היא אינה "במשמרת".
--   * ‏**השעות** — מאושרות שנסגרו, ועוד השעות החיות של ההחתמות הפתוחות.
--     השבוע מתחיל ביום ראשון.
--   * ‏**מאחרים** — משמרת מתוכננת (0178) שהתחילה לפני יותר מ-15 דקות, בלי אף
--     החתמה של אותו אדם היום. מי שהשעון כבוי לו (`clock_enabled`, 0020) אינו
--     מחתים ולכן אינו "מאחר".
--   * ‏**מסמכי רכב** — הסינון של בעל המערכת מ-0174 (‏`fleet.documents_expiring`),
--     אבל התוקף מחושב מול התאריך בישראל ולא מול `current_date` של UTC ש-
--     `vehicle_document_status` (0089) נשען עליו.
--   * ‏**כסף** — כלל 6: רק דרך `app.task_revenue`/`app.live_*`, וזה בדיוק מה
--     ש-`app.margin_summary` (0186 §5) עושה. אבל היא שואלת את
--     `app.margin_require()` ו-`app.payroll_summary` שואלת את
--     `app.require('dashboard.payroll')`, ובלי משתמש שתיהן זורקות. לכן §1
--     מפצל כל אחת לליבה בלי שער ולעטיפה עם השער — הגוף הוא הגוף החי מילה
--     במילה, והעטיפות שומרות את השם, החתימה, ה-security definer וההרשאות.
--     ‏`finance.profit_summary` אינה בשימוש כאן: היא נוקבת בשמות לקוחות.
--
-- אין בפיד טלפון, אין שכר פר-אדם, ואין מזהה פנימי מלבד המזהה של השורה עצמה.

-- ===== 1. השכר והרווח הגולמי: ליבה בלי שער, ועטיפה עם השער ==================
--
-- ‏`app.payroll_summary_core` — הגוף של 0041 §1, מילה במילה, בלי
-- `perform app.require('dashboard.payroll')`. ‏`app.margin_summary_core` —
-- הגוף של 0186 §5, מילה במילה, בלי `perform app.margin_require()` ועם
-- הליבה של השכר במקום העטיפה שלו (‏`margin_require` כבר דורש את
-- `dashboard.payroll` בין ארבעת המפתחות שלו, ולכן הבדיקה השנייה הייתה כפולה).
--
-- שתי העטיפות נשארות `security definer` כמו שהיו, ולכן הן קוראות לליבה
-- בזהות הבעלים: הליבה אינה צריכה הרשאת הרצה לאף אחד, והיא נשללת מכולם —
-- מי שקורא לה ישירות עוקף את השער. ההרשאות על העטיפות אינן משתנות: `create
-- or replace` שומר אותן, ו-0044 §1 הוא שקבע אותן ל-margin_summary.

create or replace function app.payroll_summary_core(p_from date, p_to date)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v jsonb;
begin
  with approved as (
    select * from app.attendance_pay_rows(p_from, p_to, null, null, false, array['approved'], 'all')
  ),
  pending as (
    select * from app.attendance_pay_rows(p_from, p_to, null, null, false, array['pending'], 'all')
  )
  select jsonb_build_object(
    'total',          round(coalesce(sum((a.pay ->> 'total')::numeric), 0), 2),
    'bonus',          round(coalesce(sum((a.pay ->> 'bonus')::numeric), 0), 2),
    'paid_hours',     round(coalesce(sum((a.pay ->> 'paid_hours')::numeric), 0), 2),
    'base_hours',     round(coalesce(sum((a.pay ->> 'base_hours')::numeric), 0), 2),
    'overtime_hours', round(coalesce(sum((a.pay ->> 'overtime_hours')::numeric), 0), 2),
    'actual_hours',   round(coalesce(sum(a.actual_hours), 0), 2),
    'shifts',         count(*),
    'workers',        count(distinct a.profile_id),
    -- app.attendance_calc מחזירה total = null כשאין תעריף ואין בונוס, ולכן
    -- משמרת כזו נעלמת מ-sum() בשקט ועלות השכר מדווחת נמוך מדי. המונה הזה הוא
    -- מה שמאפשר לווידג׳ט לומר "X משמרות אינן נספרות" במקום לשקר בביטחון.
    'unrated_shifts', count(*) filter (where a.pay ->> 'hourly_rate' is null),
    'pending_shifts', (select count(*) from pending),
    'pending_hours',  (select round(coalesce(sum(actual_hours), 0), 2) from pending),
    -- הצהרה על מה נספר, שהמסך מציג כהערת מקור
    'scope',          'approved_only')
  into v from approved a;

  return v;
end $$;

comment on function app.payroll_summary_core(date, date) is
  'סיכום השכר של כל החברה בטווח, בלי שער (0202). הגוף של app.payroll_summary '
  '(0041) מילה במילה. נשללת מכולם: השער יושב אצל הקורא — app.payroll_summary '
  'למשתמש, ומסך הקיר מאחורי סוד ב-Vault.';

create or replace function app.payroll_summary(p_from date, p_to date)
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  perform app.require('dashboard.payroll');
  return app.payroll_summary_core(p_from, p_to);
end $$;

create or replace function app.margin_summary_core(p_from date, p_to date)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_rev numeric; v_con numeric; v_cov numeric; v_pay jsonb; v_net numeric;
begin
  v_pay := app.payroll_summary_core(p_from, p_to);

  select coalesce((select sum(tp.price)
                     from app.task_revenue tp
                     join app.live_tasks t on t.id = tp.task_id and t.deleted_at is null
                    where t.task_date between p_from and p_to), 0)
       + coalesce((select sum(ei.amount)
                     from event_income ei
                     join app.live_events e on e.id = ei.event_id and e.deleted_at is null
                    where e.event_date between p_from and p_to), 0)
    into v_rev;
  select coalesce(sum(tct.price), 0) into v_con
    from task_contractor_terms tct join app.live_tasks t on t.id = tct.task_id and t.deleted_at is null
   where t.task_date between p_from and p_to;

  -- ‏0186: השעות שמחיר הקבלן שמעליו כבר שילם עליהן. ‏`covered` כבר דורש
  -- משימה חיה ושורת terms, ולכן כאן נשאר רק חלון התאריכים.
  select coalesce(sum(s.amount), 0) into v_cov
    from app.payroll_task_spread(p_from, p_to) s
   where s.covered and s.task_date between p_from and p_to;

  v_net := round(coalesce((v_pay ->> 'total')::numeric, 0) - v_cov, 2);

  return jsonb_build_object(
    'revenue',    round(v_rev, 2),
    'contractor', round(v_con, 2),
    -- נטו: מה שהשעון הפיק, פחות מה שכבר שולם דרך הקבלן
    'payroll',    v_net,
    -- ושני המספרים שמהם הוא נבנה, כדי שההפרש יהיה ניתן ליישוב מול דוח הנוכחות
    'payroll_gross',      (v_pay -> 'total'),
    'contractor_covered', round(v_cov, 2),
    'gross',      round(v_rev - v_con - v_net, 2),
    'pct',        case when v_rev > 0
                       then round((v_rev - v_con - v_net) / v_rev * 100, 1) end,
    'unrated_shifts', (v_pay -> 'unrated_shifts'),
    'excludes_overhead', true);
end $$;

comment on function app.margin_summary_core(date, date) is
  'הרווח הגולמי של כל החברה בטווח, בלי שער (0202). הגוף של app.margin_summary '
  '(0186 §5) מילה במילה. נשללת מכולם: השער יושב אצל הקורא.';

create or replace function app.margin_summary(p_from date, p_to date)
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  perform app.margin_require();
  return app.margin_summary_core(p_from, p_to);
end $$;

revoke execute on function app.payroll_summary_core(date, date) from public, anon, authenticated;
revoke execute on function app.margin_summary_core(date, date)  from public, anon, authenticated;

-- העטיפה של הרווח: אותן הרשאות של 0044 §1, נאמרות שוב כדי שהקובץ יעמוד
-- בפני עצמו. העטיפה של השכר לא נגעה בהרשאות מעולם (0041), ולא נוגעת גם כאן.
revoke execute on function app.margin_summary(date, date) from anon, public;
grant  execute on function app.margin_summary(date, date) to authenticated;

-- ===== 2. הסוד: hash ב-Vault, השוואה ב-sha256 המובנה =======================
--
-- ‏`sha256()` של הליבה (11+) ולא pgcrypto: אין הרחבה שצריכה להיות מותקנת,
-- ואין `search_path` שצריך למצוא אותה. ההשוואה היא בין שני hash-ים, ולכן
-- היא אינה מדליפה דבר על הסוד עצמו גם כשהיא אינה בזמן קבוע.
--
-- **כמה סודות.** נקראות כל שורות `vault.decrypted_secrets` ששמן מתחיל ב-
-- `wall_feed_secret`, והסוד מתקבל אם ה-sha256 שלו שווה לאחת מהן. ההתאמה היא
-- `starts_with`, לא `LIKE 'wall_feed_secret%'`: ב-LIKE הקו התחתון הוא תו-כללי,
-- והשם `wallXfeedXsecret` היה נכנס. סוד אחר ב-Vault (`other_secret`, או שם
-- שהקידומת שלו באמצע) אינו נספר — גם אם ה-hash שלו שווה לזה של הסוד המוצג.
--
-- סוד קצר מ-32 תווים נדחה גם כשה-hash שלו נכון: סוד כזה ניתן לניחוש, ומי
-- שקבע אותו טעה. ערך ב-Vault שאינו 64 תווי hex אינו hash — כנראה הסוד
-- עצמו הודבק במקום ה-hash — ושורה כזו מתעלמים ממנה. אם לא נשארה אף שורה
-- תקינה זה "לא מוגדר" (‏55000) ולא "סוד שגוי": כך מי שמגדיר רואה 503 ומבין
-- שהבעיה אצלו, במקום 401 שנראה כמו סוד שגוי בקיר.

create or replace function app.wall_feed_check(p_secret text)
returns void language plpgsql stable security definer set search_path = public as $$
declare v_hashes text[];
begin
  select array_agg(x.h) into v_hashes
    from (select lower(btrim(s.decrypted_secret)) as h
            from vault.decrypted_secrets s
           where starts_with(s.name, 'wall_feed_secret')) x
   where x.h ~ '^[0-9a-f]{64}$';

  if v_hashes is null then
    raise exception 'פיד הקיר אינו מוגדר' using errcode = '55000';
  end if;

  if p_secret is null or length(p_secret) < 32
     or encode(sha256(convert_to(p_secret, 'UTF8')), 'hex') <> all (v_hashes) then
    raise exception 'סוד הקיר שגוי' using errcode = '28P01';
  end if;
end $$;

comment on function app.wall_feed_check(text) is
  'בודקת את סוד הקיר מול ה-sha256 שב-Vault: כל שורה ששמה מתחיל ב-'
  'wall_feed_secret (למשל wall_feed_secret ל-Vercel ו-wall_feed_secret_minipc '
  'ל-Mini PC), והסוד מתקבל אם הוא שווה לאחת מהן. שורה שאינה 64 תווי hex '
  'מתעלמים ממנה. 28P01 לסוד שגוי או קצר מ-32, ו-55000 כשאין hash תקין (0202).';

-- ===== 3. המשימות, שורה אחת לכל משימה חיה ===================================
--
-- עוזר אחד שהרשימה, המונים, ההתראות והמאחרים קוראים ממנו, כדי ש"משימה חיה"
-- תוגדר פעם אחת. ‏`hidden_on_board` יוצא כעמודה ולא כתנאי — מי שמציג
-- רשימה מסנן אותו, מי שסופר לא.
--
-- השמות של הלקוח, של עובד הקבלן ושל עובד הלקוח עוברים דרך views הזהות
-- (0079/0201), כמו בלו״ז: שם ולא יותר. כאן הם רואים הכול, כי הקורא הוא
-- בעל הפונקציה ולא `authenticated` — זה הענף של "קריאה בצד השרת" ב-0201 §1.

create or replace function app.wall_task_rows(p_from date, p_to date)
returns table (
  id              uuid,
  task_date       date,
  type_code       text,
  type_name       text,
  status_code     text,
  status_name     text,
  status_color    text,
  status_terminal boolean,
  published       boolean,
  warehouse_at    timestamptz,
  start_at        timestamptz,
  end_at          timestamptz,
  customer_name   text,
  customer_color  text,
  end_client_name text,
  event_number    text,
  title           text,
  location        text,
  needed          int,
  assigned        int,
  delegated       boolean,
  contractor_names text[],
  team_lead_name  text,
  trucks          text[],
  hidden          boolean,
  label           text)
language sql stable security definer set search_path = public as $$
  select
    t.id,
    t.task_date,
    tt.code,
    tt.name,
    s.code,
    s.name,
    s.color,
    coalesce(s.is_terminal, false),
    -- ‏0063: "משובץ" הוא פורסם — מה שהעובד רואה
    coalesce(s.code = 'assigned', false),
    -- ‏0163: יציאה מהמחסן שגדולה משעת השטח היא של הערב שלפני
    app.warehouse_start_at(t.task_date, t.warehouse_start_time, t.onsite_start_time),
    w.start_at,
    w.start_at + make_interval(mins => round(t.hours_count * 60)::int),
    c.name,
    c.color,
    e.end_client_name,
    e.event_number,
    nullif(btrim(t.title), ''),
    coalesce(nullif(btrim(t.location_text), ''), nullif(btrim(e.location_text), '')),
    coalesce(t.worker_count, 0),
    -- ‏0201: אנשים, ולא שורות — מי שהוא גם עובד וגם נהג נספר פעם אחת
    ((select count(distinct x.profile_id) from task_assignments x where x.task_id = t.id)
     + (select count(*) from task_contractor_workers x where x.task_id = t.id)
     + (select count(*) from task_customer_workers x where x.task_id = t.id))::int,
    exists (select 1 from task_contractor_terms x where x.task_id = t.id),
    array(select ct.name
            from task_contractor_terms x
            join contractors ct on ct.id = x.contractor_id
           where x.task_id = t.id
           order by x.created_at, ct.name),
    -- ראש צוות אחד למשימה, משלושת המאגרים, באותו סדר של הלו״ז (0128/0134)
    coalesce(
      (select p.full_name from task_assignments a join profiles p on p.id = a.profile_id
        where a.task_id = t.id and a.role = 'team_lead' limit 1),
      (select cw.full_name from task_contractor_workers x
         join app.contractor_worker_identities cw on cw.id = x.contractor_worker_id
        where x.task_id = t.id and x.role = 'team_lead' limit 1),
      (select cuw.full_name from task_customer_workers x
         join app.customer_worker_identities cuw on cuw.id = x.customer_worker_id
        where x.task_id = t.id and x.role = 'team_lead' limit 1)),
    -- ‏0035: הרשימה היא המקור, ו-truck_id הוא רק הראשון בה
    array(select tr.name
            from unnest(case when cardinality(t.truck_ids) > 0 then t.truck_ids
                             else array_remove(array[t.truck_id], null) end)
                 with ordinality as u(truck_id, ord)
            join trucks tr on tr.id = u.truck_id
           order by u.ord)
      || case when nullif(btrim(t.truck_free_text), '') is not null
              then array[btrim(t.truck_free_text)] else '{}'::text[] end,
    t.hidden_on_board,
    concat_ws(' · ', c.name,
              coalesce(nullif(btrim(t.title), ''), nullif(btrim(e.end_client_name), ''), tt.name))
  from tasks t
  join task_types tt on tt.id = t.task_type_id
  join statuses s    on s.id = t.status_id
  left join events e on e.id = t.event_id
  left join app.customer_identities c on c.id = t.customer_id
  cross join lateral (
    select (t.task_date + coalesce(t.onsite_start_time, t.warehouse_start_time))
             at time zone 'Asia/Jerusalem' as start_at) w
  where t.task_date between p_from and p_to
    and t.deleted_at is null
    and t.performed_by <> 'arko'
    -- ‏0114: משימה בלי אירוע היא משימה עצמאית אמיתית ונשארת
    and (t.event_id is null
         or (e.deleted_at is null
             and e.status_id is distinct from (select app.cancelled_event_status_id())))
$$;

comment on function app.wall_task_rows(date, date) is
  'משימות חיות בטווח (לא נמחקו, אירוע לא נמחק ולא בוטל, לא של ארקו) עם מה '
  'שמסך הקיר מציג: זמנים בישראל, צוות כאנשים (0201), ראש צוות, משאיות. '
  'hidden_on_board יוצא כעמודה ולא כתנאי (0202). נשללת מכולם.';

-- ===== 4. התמונה כולה, ל"עכשיו" נתון =======================================

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
  'מאחרים, מונים, התראות וכספי החודש. p_days נחתך ל-1..14. נשללת מכולם — '
  'הדלת היחידה היא public.wall_snapshot מאחורי הסוד.';

-- ===== 5. הדלת: סוד, ואז התמונה של עכשיו ===================================

create or replace function public.wall_snapshot(p_secret text, p_days int default 3)
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  perform app.wall_feed_check(p_secret);
  return app.wall_snapshot_at(now(), p_days);
end $$;

comment on function public.wall_snapshot(text, int) is
  'פיד הקריאה של מסך הקיר (ViperGroup), דרך פונקציית הקצה wall-feed בלבד. '
  'service_role בלבד; הסוד נבדק מול ה-sha256 שב-Vault (0202).';

-- כל הפונקציות החדשות נשללות מכולם. ‏Supabase מעניק ב-public הרשאת הרצה
-- ל-anon, ל-authenticated ול-service_role כברירת מחדל ביצירה, ולכן השלילה
-- כאן היא מה שסוגר אותן; ‏service_role מקבל בחזרה את הדלת בלבד.
revoke all on function app.wall_feed_check(text)                 from public, anon, authenticated;
revoke all on function app.wall_task_rows(date, date)            from public, anon, authenticated;
revoke all on function app.wall_snapshot_at(timestamptz, int)    from public, anon, authenticated;
revoke all on function public.wall_snapshot(text, int)           from public, anon, authenticated;
grant execute on function public.wall_snapshot(text, int)        to service_role;
