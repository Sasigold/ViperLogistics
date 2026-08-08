\pset tuples_only on
\pset format unaligned

-- ================= בונה הווידג׳טים =================
--
-- שלוש קבוצות של טענות, וכל אחת שומרת על משהו אחר:
--
--   1. **שלמות הקטלוג.** הטבלאות (0043) וה-CASE-ים (0044) יכולים לסחוף זה
--      מזה. בדיקת העשן עוברת על כל מדד × כל פילוח מותר ומוודאת שאין זריקה,
--      ולכן `join_key` שה-CASE אינו מכיר הופך לכשל CI ולא לכשל ב-3 לפנות בוקר.
--   2. **מוסכמת 0/null.** מדד כספי לקורא בלי מפתח חייב להחזיר `rows = null`
--      ו-`denied`, לא `0` ולא `[]`. כל התכנון של המסגרת נשען על ההבחנה הזו.
--   3. **המפרט אינו קלט ל-SQL.** מקור, שדה, אופרטור ואגרגט שאינם שורה בקטלוג
--      נדחים לפני שנבנית מחרוזת.
--
-- הדמויות זהות לאלה של 05: f3 עובד ללא תפקידי הרשאה, f1 ops_manager, a1 בעלים.

\echo '--- שלמות הקטלוג ---'

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false);

-- perm_key הוא FK; perm_all הוא מערך ואין לו FK, ולכן מפתח מומצא בתוכו היה
-- שוקע בשקט ומחזיר denied לכולם לנצח.
select t_eq('כל מפתח ב-perm_all קיים ברישום ההרשאות',
  (select count(*)::int from report_measures m, unnest(m.perm_all) k
    where not exists (select 1 from permission_registry r where r.key = k)), 0);

select t_eq('כל זוג שדה במדדים קיים ב-field_registry',
  (select count(*)::int from report_measures m
    where m.field_entity is not null
      and not exists (select 1 from field_registry f
                       where f.entity = m.field_entity and f.field_key = m.field_key)), 0);

select t_eq('כל זוג שדה בפילוחים קיים ב-field_registry',
  (select count(*)::int from report_fields d
    where d.field_entity is not null
      and not exists (select 1 from field_registry f
                       where f.entity = d.field_entity and f.field_key = d.field_key)), 0);

select t_eq('כל allowed_dims מצביע על שדה קביץ קיים',
  (select count(*)::int from report_measures m, unnest(m.allowed_dims) k
    where k <> '__none__'
      and not exists (select 1 from report_fields f
                       where f.key = k and f.source_key = m.source_key and f.can_group)), 0);

select t_eq('כל שדה שניתן לסינון מצהיר על אופרטורים',
  (select count(*)::int from report_fields where can_filter and cardinality(allowed_ops) = 0
    and source_key <> 'payroll'), 0);

-- בדיקת העשן. זו הטענה שמשלמת על הפיצול טבלה/CASE: כל צירוף חוקי חייב לרוץ.
reset role;
create or replace function t_smoke() returns text language plpgsql as $$
declare m record; d text; r jsonb; bad text := '';
begin
  for m in select * from report_measures loop
    for d in
      select k from unnest(coalesce(m.allowed_dims, array['__none__'] ||
             array(select key from report_fields f
                    where f.source_key = m.source_key and f.can_group
                      and (not f.fans_out or m.fanout_safe)))) k
    loop
      begin
        r := app.report_run(
          jsonb_build_object('variant','query','source',m.source_key,'measure',m.key,
            'agg', m.default_agg,
            'dimension', case when d = '__none__' then null
                              else jsonb_build_object('type','cat','field',d) end),
          current_date - 30, current_date + 30);
        if r -> 'rows' = 'null'::jsonb then
          bad := bad || format(' [%s/%s → %s]', m.key, d, r -> 'meta');
        end if;
      exception when others then
        bad := bad || format(' [%s/%s ✗ %s]', m.key, d, sqlerrm);
      end;
    end loop;
  end loop;
  if bad = '' then return 'pass  ✓ כל צירוף מדד×פילוח רץ לאדמין'; end if;
  return 'FAIL  ✗ כל צירוף מדד×פילוח רץ לאדמין —' || bad;
end $$;
grant execute on function t_smoke() to authenticated;
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false);
select t_smoke();

\echo '--- 0 אומר אין, null אומר לא בשבילך ---'

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000f3', false);

-- הטענה המרכזית של הפיצ׳ר. `0` כאן היה אומר לעובד "החברה לא הרוויחה כלום".
select t_eq('עובד ללא מפתחות: הכנסות → null',
  (app.report_run('{"variant":"query","source":"tasks","measure":"revenue","agg":"sum"}',
                  current_date - 30, current_date + 30)) -> 'rows', 'null'::jsonb);
select t_eq('...ומסומן denied',
  (app.report_run('{"variant":"query","source":"tasks","measure":"revenue","agg":"sum"}',
                  current_date - 30, current_date + 30)) #>> '{meta,denied}', 'true');
select t_eq('עובד ללא מפתחות: עלות קבלנים → null',
  (app.report_run('{"variant":"query","source":"tasks","measure":"contractor_cost","agg":"sum"}',
                  current_date - 30, current_date + 30)) -> 'rows', 'null'::jsonb);
select t_eq('עובד ללא מפתחות: עלות שכר → null',
  (app.report_run('{"variant":"query","source":"payroll","measure":"payroll.total","agg":"sum"}',
                  current_date - 30, current_date + 30)) -> 'rows', 'null'::jsonb);
select t_eq('עובד ללא מפתחות: רווח גולמי → null',
  (app.report_run('{"variant":"query","source":"payroll","measure":"margin.gross","agg":"sum"}',
                  current_date - 30, current_date + 30)) -> 'rows', 'null'::jsonb);
select t_eq('עובד ללא מפתחות: שעות נוכחות → null',
  (app.report_run('{"variant":"query","source":"attendance","measure":"attendance.hours","agg":"sum"}',
                  current_date - 30, current_date + 30)) -> 'rows', 'null'::jsonb);

-- אבל מדד תפעולי אינו null: אחרת הבדיקות למעלה היו עוברות גם אם הכול שבור.
select t_eq('אבל מדד תפעולי אינו null',
  (app.report_run('{"variant":"query","source":"tasks","measure":"tasks.count","agg":"count_distinct"}',
                  current_date - 30, current_date + 30)) -> 'rows' <> 'null'::jsonb, true);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false);
select t_eq('אדמין כן מקבל הכנסות',
  (app.report_run('{"variant":"query","source":"tasks","measure":"revenue","agg":"sum"}',
                  current_date - 30, current_date + 30)) -> 'rows' <> 'null'::jsonb, true);

\echo '--- שערים: העקיפות שהמנוע סוגר ---'

-- ברמת עמודה. אדמין עוקף הכול, ולכן הבדיקה רצה על f1 שמקבל את המפתחות ידנית.
-- `task_pricing.price` רשום כרגיש, ולכן צריך גם מענק שדה מפורש — וזה בדיוק מה
-- שהופך את הזוג הזה לשני שערים נפרדים ולא לאחד.
insert into user_permission_grants (profile_id, permission_key, allowed) values
  ('20000000-0000-0000-0000-0000000000f1', 'pricing.revenue', true),
  ('20000000-0000-0000-0000-0000000000f1', 'pricing.view', true)
on conflict (profile_id, permission_key) do update set allowed = true;

delete from field_permissions
 where profile_id = '20000000-0000-0000-0000-0000000000f1' and entity = 'task_pricing';
insert into field_permissions (profile_id, entity, field_key, can_view, can_edit)
values ('20000000-0000-0000-0000-0000000000f1', 'task_pricing', 'price', true, false);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000f1', false);
select t_eq('עם המפתחות ועם השדה, ההכנסות נגישות',
  (app.report_run('{"variant":"query","source":"tasks","measure":"revenue","agg":"sum"}',
                  current_date - 30, current_date + 30)) -> 'rows' <> 'null'::jsonb, true);

-- **העקיפה**: app.has ממשיך להחזיר true, ובכל זאת אסור להראות את העמודה. בלי
-- field_entity/field_key על שורת המדד, המנוע היה מחזיר כאן מספרים.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false);
update field_permissions set can_view = false
 where profile_id = '20000000-0000-0000-0000-0000000000f1'
   and entity = 'task_pricing' and field_key = 'price';

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000f1', false);
select t_eq('...אבל pricing.revenue עדיין נראה מוחזק',
  app.has('pricing.revenue'), true);
select t_eq('...ובכל זאת שלילת השדה חוסמת',
  (app.report_run('{"variant":"query","source":"tasks","measure":"revenue","agg":"sum"}',
                  current_date - 30, current_date + 30)) #>> '{meta,denied}', 'true');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false);
update field_permissions set can_view = true
 where profile_id = '20000000-0000-0000-0000-0000000000f1'
   and entity = 'task_pricing' and field_key = 'price';

-- **§0.5**: מפתח הדשבורד לבדו אינו מספיק כשהשורות מגיעות דרך RLS אחרת. בלי
-- perm_all, מי שמחזיק dashboard.contractor_cost ולא contractors.view_pricing
-- היה מקבל 0 בטוח במקום null.
insert into user_permission_grants (profile_id, permission_key, allowed) values
  ('20000000-0000-0000-0000-0000000000f1', 'dashboard.contractor_cost', true)
on conflict (profile_id, permission_key) do update set allowed = true;
insert into user_permission_grants (profile_id, permission_key, allowed) values
  ('20000000-0000-0000-0000-0000000000f1', 'contractors.view_pricing', false)
on conflict (profile_id, permission_key) do update set allowed = false;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000f1', false);
select t_eq('עלות קבלנים בלי מפתח ה-RLS: null, לא אפס',
  (app.report_run('{"variant":"query","source":"tasks","measure":"contractor_cost","agg":"sum"}',
                  current_date - 30, current_date + 30)) -> 'rows', 'null'::jsonb);

-- פילוח לפי עובד תלוי במפתח שיושב על שורת ה*שדה*, לא על המדד — כך שורה אחת
-- מגדרת גם "שעות לפי עובד" וגם "שכר לפי עובד". f1 מחזיק את המפתח דרך התפקיד,
-- ולכן השלילה כאן מפורשת: מענק אישי גובר על תפקיד.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false);
insert into user_permission_grants (profile_id, permission_key, allowed) values
  ('20000000-0000-0000-0000-0000000000f1', 'dashboard.all_workers', false)
on conflict (profile_id, permission_key) do update set allowed = false;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000f1', false);
select t_eq('פילוח לפי עובד בלי dashboard.all_workers נחסם',
  (app.report_run('{"variant":"query","source":"attendance","measure":"attendance.shifts",
                    "agg":"count_distinct","dimension":{"type":"cat","field":"attendance.worker"}}',
                  current_date - 30, current_date + 30)) -> 'rows', 'null'::jsonb);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false);
update user_permission_grants set allowed = true
 where profile_id = '20000000-0000-0000-0000-0000000000f1'
   and permission_key = 'dashboard.all_workers';

-- v_scoped: עלות השכר היא של כל החברה ואינה ניתנת לצמצום, ולכן קורא עם היקף
-- נתונים מוגבל היה מקבל "ההכנסות שלי פחות השכר של כולם".
insert into user_permission_grants (profile_id, permission_key, allowed) values
  ('20000000-0000-0000-0000-0000000000f1', 'dashboard.margin', true),
  ('20000000-0000-0000-0000-0000000000f1', 'dashboard.payroll', true),
  ('20000000-0000-0000-0000-0000000000f1', 'contractors.view_pricing', true)
on conflict (profile_id, permission_key) do update set allowed = true;
insert into permission_scopes (profile_id, resource, scope_type, scope_values)
values ('20000000-0000-0000-0000-0000000000f1', 'tasks', 'customers',
        array['10000000-0000-0000-0000-000000000001']::uuid[]);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000f1', false);
select t_eq('רווח גולמי לקורא מצומצם: null ומסומן scoped',
  (app.report_run('{"variant":"query","source":"payroll","measure":"margin.gross","agg":"sum"}',
                  current_date - 30, current_date + 30)) #>> '{meta,scoped}', 'true');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false);
delete from permission_scopes
 where profile_id = '20000000-0000-0000-0000-0000000000f1' and resource = 'tasks';

\echo '--- המלכודות ---'

-- LEFT join ולא INNER: אירוע בלי סטטוס חייב לנחות בדלי "ללא סטטוס" ולא
-- להיעלם מההתפלגות. זו המחלקה שנפתרה מבנית ולא בבוליאני.
select t_eq('אירוע ללא סטטוס מקבל דלי משלו',
  (select count(*)::int from jsonb_array_elements(
     (app.report_run('{"variant":"query","source":"events","measure":"events.count",
                       "agg":"count_distinct","dimension":{"type":"cat","field":"events.status"},
                       "limit":50}', current_date - 190, current_date + 190)) -> 'rows') e
    where e ->> 'label' = 'ללא סטטוס') > 0, true);

-- LEFT lateral ולא CROSS: משימה בלי משאיות נמחקת לגמרי ב-cross join, ולכן
-- "משימות לפי משאית" היה מראה רק את המשימות שכבר שובצו.
select t_eq('משימה ללא משאית נשארת בפילוח לפי משאית',
  (select count(*)::int from jsonb_array_elements(
     (app.report_run('{"variant":"query","source":"tasks","measure":"tasks.count",
                       "agg":"count_distinct","dimension":{"type":"cat","field":"tasks.truck"},
                       "limit":50}', current_date - 190, current_date + 190)) -> 'rows') e
    where e ->> 'label' = 'ללא משאית') > 0, true);

-- fan-out: הסכום הלא-מפולח והמפולח חייבים להסכים, כי count(distinct) עמיד
select t_eq('פילוח שמכפיל שורות אינו משנה את הסך הכול',
  (app.report_run('{"variant":"query","source":"tasks","measure":"tasks.count","agg":"count_distinct",
                    "dimension":{"type":"cat","field":"tasks.truck"},"limit":50}',
                  current_date - 190, current_date + 190)) #>> '{meta,total}',
  (app.report_run('{"variant":"query","source":"tasks","measure":"tasks.count","agg":"count_distinct"}',
                  current_date - 190, current_date + 190)) #>> '{meta,total}');

select t_eq('...ומסומן fans_out',
  (app.report_run('{"variant":"query","source":"tasks","measure":"tasks.count","agg":"count_distinct",
                    "dimension":{"type":"cat","field":"tasks.truck"}}',
                  current_date - 190, current_date + 190)) #>> '{meta,fans_out}', 'true');

-- price הוא not null default 0, ולכן SUM לבדו אינו מבחין בין "לא תומחר"
-- ל-"תומחר באפס". presence.missing הוא מה שמאפשר לכרטיס להצהיר.
select t_eq('נוכחות התמחור נספרת בנפרד מהסכום',
  ((app.report_run('{"variant":"query","source":"tasks","measure":"revenue","agg":"sum"}',
                   current_date - 190, current_date + 190)) #>> '{meta,presence,missing}')::numeric > 0, true);

-- דלי הזמן חייב להיות מקובץ באמת. לפני התיקון הקיבוץ היה על (מפתח, תווית)
-- והתווית הייתה התאריך הגולמי, ולכן כל חודש התפצל חזרה לימים.
select t_eq('פילוח חודשי מקבץ באמת',
  (select count(*)::int from jsonb_array_elements(
     (app.report_run('{"variant":"query","source":"tasks","measure":"tasks.count",
                       "agg":"count_distinct","dimension":{"type":"time","field":"tasks.date",
                       "bucket":"month"},"limit":50}',
                     current_date - 200, current_date + 200)) -> 'rows') e
    where (e ->> 'key') <> (e ->> 'label')), 0);

-- ניטרליות החילוץ, בסגנון 0039: הבונה ו-dashboard_sections חייבים להסכים
select t_eq('הרווח במנוע שווה לרווח ב-dashboard_sections',
  (app.report_run('{"variant":"query","source":"payroll","measure":"margin.gross","agg":"sum"}',
                  current_date - 200, current_date + 200)) #>> '{meta,total}',
  (dashboard_sections(array['margin.summary'], current_date - 200, current_date + 200))
    #>> '{margin.summary,gross}');

select t_eq('ועלות השכר שווה ל-cost.payroll',
  (app.report_run('{"variant":"query","source":"payroll","measure":"payroll.total","agg":"sum"}',
                  current_date - 200, current_date + 200)) #>> '{meta,total}',
  (dashboard_sections(array['cost.payroll'], current_date - 200, current_date + 200))
    #>> '{cost.payroll,total}');

-- הקצאה: המשויך ועוד הלא-משויך שווים לסך הכול הלא-מפולח
select t_eq('הקצאת שכר ללקוח מסומנת כהערכה',
  (app.report_run('{"variant":"query","source":"payroll","measure":"payroll.total","agg":"sum",
                    "dimension":{"type":"cat","field":"payroll.customer"}}',
                  current_date - 200, current_date + 200)) #>> '{meta,estimated}', 'true');

select t_eq('משויך + לא משויך = הסכום הלא מפולח',
  (((app.report_run('{"variant":"query","source":"payroll","measure":"payroll.total","agg":"sum",
                      "dimension":{"type":"cat","field":"payroll.customer"}}',
                    current_date - 200, current_date + 200)) #>> '{meta,allocated}')::numeric
   + ((app.report_run('{"variant":"query","source":"payroll","measure":"payroll.total","agg":"sum",
                      "dimension":{"type":"cat","field":"payroll.customer"}}',
                    current_date - 200, current_date + 200)) #>> '{meta,unallocated}')::numeric),
  ((app.report_run('{"variant":"query","source":"payroll","measure":"payroll.total","agg":"sum"}',
                   current_date - 200, current_date + 200)) #>> '{meta,total}')::numeric);

\echo '--- הזרקה וניצול ---'

-- הטענה החשובה כאן אינה "זרק" אלא "לא נבנתה מחרוזת": מקור ושדה נפתרים משורה
-- בקטלוג, ומחרוזת שאינה שורה לעולם אינה מגיעה ל-format.
select t_eq('מקור מוזרק אינו מוכר',
  (app.report_run('{"variant":"query","source":"tasks; drop table tasks --","measure":"tasks.count"}',
                  current_date - 30, current_date + 30)) -> 'rows', 'null'::jsonb);
select t_eq('...והטבלה שרדה',
  (select count(*)::int from pg_tables where tablename = 'tasks'), 1);

select t_eq('שדה מוזרק אינו מוכר',
  (app.report_run('{"variant":"query","source":"tasks","measure":"tasks.count","agg":"count_distinct",
                    "dimension":{"type":"cat","field":"id) or true --"}}',
                  current_date - 30, current_date + 30)) -> 'rows', 'null'::jsonb);

-- עמודה אמיתית שאינה שורה בקטלוג: הבדיקה שמוכיחה שהקטלוג הוא הגבול ולא הסכימה
select t_eq('עמודה אמיתית שאינה בקטלוג נדחית',
  (app.report_run('{"variant":"query","source":"tasks","measure":"tasks.count","agg":"count_distinct",
                    "dimension":{"type":"cat","field":"tasks.notes"}}',
                  current_date - 30, current_date + 30)) -> 'rows', 'null'::jsonb);

select t_expect_fail('אגרגט שאינו ב-allowed_aggs נדחה',
  $$select app.report_run('{"variant":"query","source":"tasks","measure":"tasks.count","agg":"sum"}',
                          current_date - 30, current_date + 30)$$);
select t_expect_fail('אגרגט מוזרק נדחה',
  $$select app.report_run('{"variant":"query","source":"tasks","measure":"tasks.hours","agg":"sum(x); drop"}',
                          current_date - 30, current_date + 30)$$);
select t_expect_fail('אופרטור סינון שאינו מוכר נדחה ולא מתקבל בשקט',
  $$select app.report_run('{"variant":"query","source":"tasks","measure":"tasks.count","agg":"count_distinct",
      "filters":[{"id":"a","field":"tasks.worker_count","op":"matches","value":1}]}',
                          current_date - 30, current_date + 30)$$);
select t_expect_fail('ערך סינון בצורה שגויה נדחה',
  $$select app.report_run('{"variant":"query","source":"tasks","measure":"tasks.count","agg":"count_distinct",
      "filters":[{"id":"a","field":"tasks.worker_count","op":"between","value":[1]}]}',
                          current_date - 30, current_date + 30)$$);
select t_expect_fail('יותר מדי תנאי סינון נדחה',
  $$select app.report_run(jsonb_build_object('variant','query','source','tasks','measure','tasks.count',
      'agg','count_distinct','filters',
      (select jsonb_agg(jsonb_build_object('id', i::text, 'field','tasks.worker_count','op','gte','value',1))
         from generate_series(1, 20) i)), current_date - 30, current_date + 30)$$);
select t_expect_fail('פילוח שאינו חוקי למדד נדחה',
  $$select app.report_run('{"variant":"query","source":"payroll","measure":"payroll.bonus","agg":"sum",
      "dimension":{"type":"cat","field":"payroll.worker"}}', current_date - 30, current_date + 30)$$);
select t_expect_fail('מדד שאינו עמיד לפילוח מכפיל-שורות נדחה',
  $$select app.report_run('{"variant":"query","source":"tasks","measure":"tasks.hours","agg":"sum",
      "dimension":{"type":"cat","field":"tasks.truck"}}', current_date - 30, current_date + 30)$$);
select t_expect_fail('פתק אינו שאילתה',
  $$select app.report_run('{"variant":"note","body":"שלום"}', current_date - 30, current_date + 30)$$);
select t_expect_fail('טווח הפוך נדחה',
  $$select app.report_run('{"variant":"query","source":"tasks","measure":"tasks.count"}',
                          current_date + 10, current_date)$$);
select t_expect_fail('טווח גדול מדי נדחה',
  $$select app.report_run('{"variant":"query","source":"tasks","measure":"tasks.count"}',
                          current_date - 500, current_date)$$);

select t_eq('limit גדול מדי נצבט',
  (select count(*)::int <= 50 from jsonb_array_elements(
    (app.report_run('{"variant":"query","source":"tasks","measure":"tasks.count","agg":"count_distinct",
                      "dimension":{"type":"cat","field":"tasks.customer"},"limit":100000}',
                    current_date - 190, current_date + 190)) -> 'rows')), true);

\echo '--- אחסון ושיתוף ---'

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000f3', false);

select t_expect_ok('עובד שומר ווידג׳ט משלו',
  $$insert into dashboard_widgets (id, profile_id, title, spec)
    values ('90000000-0000-0000-0000-000000000001',
            '20000000-0000-0000-0000-0000000000f3', 'המשימות שלי',
            '{"v":1,"variant":"query","source":"tasks","measure":"tasks.count","agg":"count_distinct"}')$$);

select t_expect_fail('ואינו שומר בשם מישהו אחר',
  $$insert into dashboard_widgets (profile_id, title, spec)
    values ('20000000-0000-0000-0000-0000000000f1', 'לא שלי', '{"v":1,"variant":"note","body":"x"}')$$);

-- שער השיתוף: המפתח נבדק על השורה התוצאתית, ולכן גם יצירה וגם עדכון נחסמים
select t_expect_fail('ואינו יכול ליצור ווידג׳ט משותף',
  $$insert into dashboard_widgets (profile_id, title, spec, shared)
    values ('20000000-0000-0000-0000-0000000000f3', 'משותף', '{"v":1,"variant":"note","body":"x"}', true)$$);

select t_rows('ואינו יכול לשתף ווידג׳ט קיים',
  $$update dashboard_widgets set shared = true
     where id = '90000000-0000-0000-0000-000000000001'$$, 0);

-- ...ועם המפתח, כן
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false);
insert into user_permission_grants (profile_id, permission_key, allowed) values
  ('20000000-0000-0000-0000-0000000000f3', 'dashboard.share_widget', true)
on conflict (profile_id, permission_key) do update set allowed = true;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000f3', false);
select t_rows('עם המפתח השיתוף עובר',
  $$update dashboard_widgets set shared = true
     where id = '90000000-0000-0000-0000-000000000001'$$, 1);

select t_expect_ok('ופתק פרטי נשמר בלי המפתח',
  $$insert into dashboard_widgets (id, profile_id, title, spec)
    values ('90000000-0000-0000-0000-000000000002',
            '20000000-0000-0000-0000-0000000000f3', 'תזכורת',
            '{"v":1,"variant":"note","body":"לבדוק תמחור"}')$$);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000f1', false);
select t_eq('אחר רואה את המשותף',
  (select count(*)::int from dashboard_widgets
    where id = '90000000-0000-0000-0000-000000000001'), 1);
select t_eq('ואינו רואה את הפרטי',
  (select count(*)::int from dashboard_widgets
    where id = '90000000-0000-0000-0000-000000000002'), 0);
select t_rows('ואינו יכול לערוך את המשותף של אחר',
  $$update dashboard_widgets set title = 'נחטף'
     where id = '90000000-0000-0000-0000-000000000001'$$, 0);
select t_rows('ואינו יכול למחוק אותו',
  $$delete from dashboard_widgets where id = '90000000-0000-0000-0000-000000000001'$$, 0);

-- מחיקה רכה: המזהה יושב בפריסות, ולכן הוא נעלם מהקריאה ולא מהטבלה.
--
-- **UPDATE ישיר חייב להיכשל**, וזה לא סגנון אלא Postgres: השורה החדשה נבדקת
-- מחדש מול מדיניות ה-SELECT, ו-dw_select דורשת deleted_at is null. הבדיקה
-- הזו מתעדת את האילוץ, כי בלעדיה מישהו "יפשט" את ה-RPC בחזרה ל-UPDATE.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000f1', false);
select t_expect_fail('אחר אינו מוחק ווידג׳ט של מישהו אחר',
  $$select dashboard_widget_delete('90000000-0000-0000-0000-000000000002')$$);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000f3', false);
select t_expect_fail('UPDATE ישיר על deleted_at נחסם',
  $$update dashboard_widgets set deleted_at = now()
     where id = '90000000-0000-0000-0000-000000000002'$$);
select t_expect_ok('הבעלים מוחק דרך ה-RPC',
  $$select dashboard_widget_delete('90000000-0000-0000-0000-000000000002')$$);
select t_eq('ושורה מחוקה רכות נעלמת גם מהבעלים',
  (select count(*)::int from dashboard_widgets
    where id = '90000000-0000-0000-0000-000000000002'), 0);
select t_expect_fail('ומחיקה חוזרת אינה מוצאת אותה',
  $$select dashboard_widget_delete('90000000-0000-0000-0000-000000000002')$$);

\echo '--- מסלול הדשבורד והקטלוג ---'

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000f3', false);
select t_eq('dashboard_widgets_run מחזיר מפתח לכל מזהה',
  (select count(*)::int from jsonb_object_keys(
    dashboard_widgets_run(array['90000000-0000-0000-0000-000000000001']::uuid[],
                          current_date - 30, current_date + 30))), 1);

select t_eq('...ומזהה שאינו קיים חוזר null ולא זורק',
  (dashboard_widgets_run(array['90000000-0000-0000-0000-0000000000ff']::uuid[],
                         current_date - 30, current_date + 30))
    -> '90000000-0000-0000-0000-0000000000ff', 'null'::jsonb);

select t_expect_fail('יותר מדי ווידג׳טים בבקשה אחת נדחה',
  $$select dashboard_widgets_run(
      (select array_agg(gen_random_uuid()) from generate_series(1, 40)),
      current_date - 30, current_date + 30)$$);

-- מכת הנגד לסחיפה: הלקוח לא גוזר הרשאות ממפרט, השרת מוסר אותן
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false);
insert into dashboard_widgets (id, profile_id, title, spec, shared)
values ('90000000-0000-0000-0000-000000000003',
        '20000000-0000-0000-0000-000000000001', 'הכנסות לפי לקוח',
        '{"v":1,"variant":"query","source":"tasks","measure":"revenue","agg":"sum",
          "dimension":{"type":"cat","field":"tasks.customer"}}', true)
on conflict (id) do nothing;

select t_eq('הקטלוג מוסר את מפתחות ההרשאה של המפרט',
  (select (w ->> 'perms')::jsonb ?& array['pricing.revenue','pricing.view','customers.view']
     from jsonb_array_elements(dashboard_widget_catalog()) w
    where w ->> 'id' = '90000000-0000-0000-0000-000000000003'), true);

select t_eq('...ומסמן ווידג׳ט שהמפרט שלו מוכר',
  (select w ->> 'known' from jsonb_array_elements(dashboard_widget_catalog()) w
    where w ->> 'id' = '90000000-0000-0000-0000-000000000003'), 'true');

-- מדד שנעלם מהקטלוג: המפרט נשמר, הווידג׳ט מסומן לא-מוכר, ושום דבר לא זורק
insert into dashboard_widgets (id, profile_id, title, spec)
values ('90000000-0000-0000-0000-000000000004',
        '20000000-0000-0000-0000-000000000001', 'מדד שהוסר',
        '{"v":1,"variant":"query","source":"tasks","measure":"revenue_v0","agg":"sum"}')
on conflict (id) do nothing;

select t_eq('מדד שאינו קיים עוד מסומן לא-מוכר ולא נמחק',
  (select w ->> 'known' from jsonb_array_elements(dashboard_widget_catalog()) w
    where w ->> 'id' = '90000000-0000-0000-0000-000000000004'), 'false');

select t_eq('...והמפרט נשאר כפי שהוא',
  (select spec ->> 'measure' from dashboard_widgets
    where id = '90000000-0000-0000-0000-000000000004'), 'revenue_v0');

select t_eq('...וההרצה שלו מחזירה unsupported ולא זורקת',
  (dashboard_widgets_run(array['90000000-0000-0000-0000-000000000004']::uuid[],
                         current_date - 30, current_date + 30))
    #>> '{90000000-0000-0000-0000-000000000004,meta,unsupported}', 'revenue_v0');

\echo '--- העטיף הציבורי ---'

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000c1', false);
select t_expect_fail('משתמש פורטל אינו מגיע לתצוגה המקדימה של הבונה',
  $$select dashboard_widget_preview('{"variant":"query","source":"tasks","measure":"tasks.count"}',
                                    current_date - 30, current_date + 30)$$);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000f3', false);
select t_eq('ואיש צוות כן',
  (dashboard_widget_preview('{"variant":"query","source":"tasks","measure":"tasks.count","agg":"count_distinct"}',
                            current_date - 30, current_date + 30)) -> 'rows' <> 'null'::jsonb, true);

reset role;
