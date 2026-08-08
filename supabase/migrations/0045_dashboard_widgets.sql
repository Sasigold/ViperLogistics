-- 0045: הווידג׳טים שהמשתמש בנה
--
-- טבלה נפרדת מ-`dashboard_layouts` (0040) בכוונה. הפריסה אומרת *איפה* ווידג׳ט
-- יושב; השורה כאן אומרת *מה הוא*. ווידג׳ט אחד יכול לשבת בעשרים פריסות, ואם
-- ההגדרה שלו הייתה משוכפלת לתוך כל אחת מהן, "שיתפתי ותיקנתי" היה משאיר
-- תשע-עשרה עותקים ישנים.
--
-- ===== למה שיתוף אינו מדליף נתונים =========================================
--
-- זו כל טענת האבטחה של הפיצ׳ר, והיא נופלת מהתכנון ולא צריכה אכיפה נוספת:
--
--   1. **המפרט השמור אינו מכיל שום החלטת הרשאה.** לא רשימת מפתחות, לא מזהה
--      המחבר, ולא היקף נתונים שנפתר מראש. הוא אומר *מה לחשב*, ותו לא.
--   2. **`app.report_run` הוא `security invoker`**, ולכן כל מדד `sql` מצומצם
--      ע״י ה-RLS של הקורא — `tp_select`, `tct_select`, ופרדיקטי ההיקף של
--      0013 על `tasks`.
--   3. **כל שער קורא ל-`app.has` / `app.can_view_field` בלי שום ארגומנט
--      שמזהה את המחבר.** הם נפתרים מול `app.profile_id()`, שהוא הקורא.
--   4. **המסלול היחיד מגובה-definer הוא השכר**, ו-`app.payroll_*` /
--      `app.margin_*` דורשות את המפתחות בעצמן לפני שהן נוגעות בנתון.
--   5. **`dashboard_widgets_run` שולף את המפרטים דרך `dw_select`**, ולכן מי
--      שאינו רואה את הווידג׳ט אינו יכול להריץ אותו.
--
-- כלומר: שיתוף של ווידג׳ט רווח גולמי אינו חושף רווח גולמי לאיש. הוא רק *מציע*
-- אותו למי שכבר רשאי, ואצל כל השאר הוא מחזיר null והמסגרת משמיטה אותו.

create table dashboard_widgets (
  id           uuid primary key default gen_random_uuid(),
  profile_id   uuid not null references profiles(id) on delete cascade,
  title        text not null check (length(btrim(title)) between 1 and 60),
  subtitle     text check (subtitle is null or length(subtitle) <= 120),
  spec         jsonb not null,
  spec_version int not null default 1,
  icon         text,
  shared       boolean not null default false,
  shared_at    timestamptz,
  shared_by    uuid references profiles(id),
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  -- ווידג׳ט שיושב על עשרים דשבורדים אינו יכול להימחק קשה: הפריסות מחזיקות את
  -- המזהה שלו, ומחיקה קשה הייתה משאירה שם מזהה יתום. מחיקה רכה → המזהה אינו
  -- נפתר → כלל 1 ב-resolveLayout זורק אותו מהפריסה בשקט, בדיוק כמו ווידג׳ט
  -- סטטי שהוצא משימוש.
  deleted_at   timestamptz
);

create index dashboard_widgets_owner_idx
  on dashboard_widgets (profile_id) where deleted_at is null;
create index dashboard_widgets_shared_idx
  on dashboard_widgets (shared) where shared and deleted_at is null;

create trigger dashboard_widgets_updated before update on dashboard_widgets
  for each row execute function app.set_updated_at();
create trigger dashboard_widgets_audit after insert or update or delete on dashboard_widgets
  for each row execute function app.audit();

alter table dashboard_widgets enable row level security;

create policy dw_select on dashboard_widgets for select to authenticated
  using (deleted_at is null
     and (profile_id = (select app.profile_id())
       or shared
       or (select app.is_admin())));

-- מדיניות נפרדת מהקריאה, ובלי `or` שמכניס את השיתוף פנימה — מאותה סיבה
-- ש-0040 פיצלה `dl_write_own` מ-`dl_write_default`: אסור שיהיה ניסוח שבו
-- משתמש מגיע ליכולת שאין לו פשוט על ידי כתיבת עמודה.
--
-- ה-`with check` על `shared` הוא שער השיתוף עצמו: **כל שורה תוצאתית** עם
-- shared = true דורשת את המפתח, ולכן גם "לשתף עכשיו" וגם "לערוך ווידג׳ט
-- ששותף" דורשים אותו, בזמן שביטול שיתוף אינו דורש.
--
-- קצה ידוע ומכוון: בעלים ששיתף ואחר כך נשלל ממנו המפתח אינו יכול עוד לערוך
-- את הווידג׳ט — כל עדכון שלו עדיין מייצר shared = true. זה נכשל *סגור*, וזה
-- הכיוון הנכון. אם זה יהפוך לתלונה אמיתית, התיקון הוא RPC
-- `dashboard_widget_share(p_id, p_on)` וטריגר שמקפיא את העמודה מפני עדכון
-- ישיר — ולא הרפיה של המדיניות.
--
-- `deleted_at is null` ב-USING אינו קישוט: מדיניות `for all` היא **גם מדיניות
-- קריאה**, והיא permissive — כלומר היא מתאחדת ב-OR עם `dw_select`. בלי התנאי
-- הזה, הבעלים היה ממשיך לראות את הווידג׳טים שמחק דרך המדיניות הזו, ומחיקה
-- רכה לא הייתה מסתירה כלום ממנו. שחזור אינו פיצ׳ר, ולכן אין לזה מחיר.
create policy dw_write_own on dashboard_widgets for all to authenticated
  using      (deleted_at is null
              and profile_id = (select app.profile_id())
              and (select app.has('dashboard.build_widget')))
  with check (profile_id = (select app.profile_id())
              and (select app.has('dashboard.build_widget'))
              and (not shared or (select app.has('dashboard.share_widget'))));

comment on table dashboard_widgets is
  'ווידג׳טים שנבנו מהממשק. spec הוא מה לחשב בלבד — אין בו שום החלטת הרשאה, ולכן ווידג׳ט משותף מוערך מחדש מול המפתחות של כל קורא.';

-- ===== מחיקה רכה עוברת דרך RPC, ולא דרך UPDATE =============================
--
-- זו אינה העדפת סגנון אלא אילוץ של Postgres, והוא לא-מובן-מאליו: אחרי UPDATE,
-- **השורה החדשה נבדקת מחדש מול מדיניות ה-SELECT**. `dw_select` דורשת
-- `deleted_at is null`, ולכן `update ... set deleted_at = now()` נכשל תמיד עם
-- "new row violates row-level security policy" — הכתיבה מותרת, אבל התוצאה
-- שלה בלתי נראית, וזה נחשב הפרה.
--
-- הדרך היחידה להתחמק מזה בלי RPC היא להשאיר מדיניות כתיבה permissive רחבה
-- שמחזירה את השורה המחוקה לראייה — כלומר לוותר על ההסתרה עצמה. עדיף RPC.
--
-- שחזור אינו פיצ׳ר: ווידג׳ט שנמחק יורד מכל פריסה שמחזיקה אותו דרך כלל 1
-- ב-resolveLayout, ו"בטלתי" היה צריך להחזיר גם את המיקומים.
create or replace function dashboard_widget_delete(p_id uuid)
returns void language plpgsql volatile security definer set search_path = public as $$
declare v_owner uuid;
begin
  perform app.require('dashboard.build_widget');
  select profile_id into v_owner from dashboard_widgets
   where id = p_id and deleted_at is null;
  if not found then
    raise exception 'הווידג׳ט אינו קיים' using errcode = '42704';
  end if;
  -- definer, ולכן הבעלות נבדקת כאן במפורש ולא נשענת על ה-RLS שנעקפה
  if v_owner <> app.profile_id() and not app.is_admin() then
    raise exception 'אפשר למחוק רק ווידג׳ט משלך' using errcode = '42501';
  end if;
  update dashboard_widgets set deleted_at = now() where id = p_id;
end $$;

revoke execute on function public.dashboard_widget_delete(uuid) from anon, public;

-- ===== מסלול הדשבורד =======================================================
--
-- הלוך-חזור אחד ל-N ווידג׳טים, בצורת `dashboard_sections`: שנים-עשר ווידג׳טים
-- מותאמים אינם שתים-עשרה קריאות. מזהה שהקורא אינו רואה, או שאינו נפתר, מקבל
-- null — ושתי המשמעויות מגיעות לאותו מקום ומטופלות זהה במסך.

create or replace function dashboard_widgets_run(p_ids uuid[], p_from date, p_to date)
returns jsonb language plpgsql stable security invoker set search_path = public as $$
declare v_id uuid; v_spec jsonb; v_out jsonb := '{}'::jsonb; v_val jsonb; v_found boolean;
begin
  if coalesce(cardinality(p_ids), 0) > 20 then
    raise exception 'יותר מדי ווידג׳טים בבקשה אחת' using errcode = '22023';
  end if;

  foreach v_id in array coalesce(p_ids, '{}'::uuid[]) loop
    v_val := null;
    -- דרך ה-RLS של הטבלה: מי שאינו רואה את הווידג׳ט אינו מריץ אותו
    select spec into v_spec from dashboard_widgets where id = v_id;
    v_found := found;
    -- פתק אינו שאילתה; הוא נצבע בלקוח ואינו נוגע בנתונים כלל
    if v_found and coalesce(v_spec ->> 'variant', 'query') <> 'note' then
      v_val := app.report_run(v_spec, p_from, p_to);
    end if;
    v_out := v_out || jsonb_build_object(v_id::text, v_val);
  end loop;
  return v_out;
end $$;

revoke execute on function public.dashboard_widgets_run(uuid[], date, date) from anon, public;

-- ===== הקטלוג של הווידג׳טים המותאמים =======================================
--
-- **זו מכת הנגד לסחיפה.** הפונקציה מחזירה לכל ווידג׳ט את *איחוד כל מפתחות
-- ההרשאה* שהמקור, המדד, הפילוח ושדות הסינון של המפרט שלו דורשים, מחושב בשרת.
-- הלקוח שם את המערך הזה ישירות ב-`WidgetDef.perms`, ו-`widgetAllowed` הקיים
-- עובד עליו בלי שינוי.
--
-- כלומר **הלקוח לעולם אינו גוזר דרישת הרשאה ממפרט**. אין מראה שתסחף, כי גם
-- הקטלוג וגם המשמעויות שלו מוגשים.
--
-- `runnable` הוא אותה תשובה מהצד השני: האם *הקורא הזה* יכול להריץ. הקטלוג
-- במסך ההתאמה לא מציע ווידג׳ט משותף שלא ירוץ — אותה משמעת ש-CustomizeDrawer
-- כבר מפעילה על הווידג׳טים הסטטיים.

create or replace function dashboard_widget_catalog()
returns jsonb language plpgsql stable security invoker set search_path = public as $$
declare v jsonb;
begin
  perform app.require('dashboard.view');

  select coalesce(jsonb_agg(row_to_json(x) order by x.created_at), '[]') into v from (
    select w.id, w.profile_id, w.title, w.subtitle, w.spec, w.icon, w.shared,
           w.created_at, w.updated_at,
           (w.profile_id = (select app.profile_id())) as is_mine,
           coalesce(k.perms, '{}'::text[]) as perms,
           -- מדד שאינו קיים עוד, או פילוח שהוסר מהקטלוג: הווידג׳ט אינו רץ
           -- והמסך אומר "מבקש נתון שאינו קיים עוד" במקום להיעלם בשקט.
           coalesce(k.known, w.spec ->> 'variant' = 'note') as known,
           coalesce(k.runnable, true) as runnable
      from dashboard_widgets w
      left join lateral (
        select
          array(select distinct p from unnest(
                 coalesce(array[s.perm_key, m.perm_key, d.perm_key], '{}'::text[])
                 || coalesce(m.perm_all, '{}'::text[])
                 || coalesce(array(select f.perm_key from report_fields f
                                    where f.key in (select e ->> 'field'
                                                      from jsonb_array_elements(
                                                        coalesce(w.spec -> 'filters', '[]'::jsonb)) e)
                                      and f.perm_key is not null), '{}'::text[])) p
                 where p is not null) as perms,
          (m.key is not null
             and (w.spec #>> '{dimension,field}' is null or d.key is not null)) as known,
          (app.report_may_measure(m, exists (select 1 from app.scope_rows('tasks')
                                              where scope_type <> 'all'))
             and (d.key is null or app.report_may_field(d))) as runnable
        from report_sources s
        left join report_measures m on m.key = w.spec ->> 'measure' and m.source_key = s.key
        left join report_fields d on d.key = w.spec #>> '{dimension,field}' and d.source_key = s.key
       where s.key = w.spec ->> 'source') k on true
     where w.deleted_at is null) x;

  return v;
end $$;

revoke execute on function public.dashboard_widget_catalog() from anon, public;
