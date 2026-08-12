\pset tuples_only on
\pset format unaligned

-- ================= מסך הדוחות (0058) =================
--
-- שלוש טענות, כל אחת שומרת על משהו אחר:
--
--   1. **המפתח החדש עומד לבדו.** משתמש עם `reports.view` בלבד — בלי מפתח
--      הדשבורד — מקבל שורות מ-`reports_run`. זה השער הפנימי המורחב של 0058;
--      בלעדיו העטיפה החדשה הייתה עוברת והמנוע היה זורק בפנים.
--   2. **בלי שני המפתחות — דלת סגורה.** לא null ולא [], אלא 42501.
--   3. **מסך הדוחות אינו מרחיב נתונים.** גדרות המדדים הכספיים נשארות בדיוק
--      כפי שהיו: `reports.view` פותח את המסך, ו-revenue עדיין מוחזר denied
--      למי שאין לו את מפתחות התמחור.
--
-- הדמויות של 04-06: f3 עובד ללא תפקידי הרשאה (מחזיק dashboard.view דרך ברירת
-- המחדל של staff), a1 בעלים.

\echo '--- רישום ---'

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false);

select t_eq('reports.view רשום ונגזר ממפתח הדשבורד',
  (select implied_by from permission_registry where key = 'reports.view'), 'dashboard.view');
select t_eq('reports.export רשום ונגזר מייצוא הדשבורד',
  (select implied_by from permission_registry where key = 'reports.export'), 'dashboard.export');

-- הגזירה עובדת בזמן בדיקה: f3 מחזיק dashboard.view דרך ברירת המחדל של staff,
-- ולכן reports.view חייב לחזור true בלי שום מענק מפורש.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000f3', false);
select t_eq('מי שמחזיק dashboard.view מחזיק reports.view בירושה',
  app.has('reports.view'), true);

\echo '--- reports.view עומד לבדו ---'

-- f3 נהפך ל"קורא דוחות בלבד": שלילה אישית של מפתח הדשבורד, מענק אישי של
-- מפתח הדוחות. מענק אישי גובר על ברירת מחדל ועל ירושה — זו בדיוק הדמות
-- שהשער הישן `app.require('dashboard.view')` היה זורק עליה.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false);
insert into user_permission_grants (profile_id, permission_key, allowed) values
  ('20000000-0000-0000-0000-0000000000f3', 'dashboard.view', false),
  ('20000000-0000-0000-0000-0000000000f3', 'reports.view',  true)
on conflict (profile_id, permission_key) do update set allowed = excluded.allowed;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000f3', false);
select t_eq('הדמות אכן בלי מפתח הדשבורד', app.has('dashboard.view'), false);

select t_eq('reports_run: מדד תפעולי מחזיר שורות בלי dashboard.view',
  (reports_run('{"variant":"query","source":"tasks","measure":"tasks.count","agg":"count_distinct"}',
               current_date - 30, current_date + 30)) -> 'rows' <> 'null'::jsonb, true);

select t_eq('reports_run: פילוח לפי סטטוס רץ גם הוא',
  (reports_run('{"variant":"query","source":"tasks","measure":"tasks.count","agg":"count_distinct",
                 "dimension":{"type":"cat","field":"tasks.status"}}',
               current_date - 30, current_date + 30)) -> 'rows' <> 'null'::jsonb, true);

\echo '--- המסך אינו מרחיב נתונים ---'

-- המדד הכספי נשאר מאחורי המפתחות שלו. rows=null ו-denied, לא 0 — מוסכמת 06.
select t_eq('reports_run: הכנסות בלי מפתחות תמחור → null',
  (reports_run('{"variant":"query","source":"tasks","measure":"revenue","agg":"sum"}',
               current_date - 30, current_date + 30)) -> 'rows', 'null'::jsonb);
select t_eq('...ומסומן denied',
  (reports_run('{"variant":"query","source":"tasks","measure":"revenue","agg":"sum"}',
               current_date - 30, current_date + 30)) #>> '{meta,denied}', 'true');
select t_eq('reports_run: עלות שכר בלי dashboard.payroll → null',
  (reports_run('{"variant":"query","source":"payroll","measure":"payroll.total","agg":"sum"}',
               current_date - 30, current_date + 30)) -> 'rows', 'null'::jsonb);

\echo '--- בלי שני המפתחות: הדלת סגורה ---'

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false);
update user_permission_grants set allowed = false
 where profile_id = '20000000-0000-0000-0000-0000000000f3'
   and permission_key = 'reports.view';

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000f3', false);
select t_expect_fail('reports_run בלי אף מפתח נדחה',
  $q$ select reports_run('{"variant":"query","source":"tasks","measure":"tasks.count","agg":"count_distinct"}',
                         current_date - 30, current_date + 30) $q$);

-- והמסלול הישן לא זז: המנוע עצמו עדיין נעול בפני מי שאין לו אף מפתח.
select t_expect_fail('גם app.report_run עצמה נדחית',
  $q$ select app.report_run('{"variant":"query","source":"tasks","measure":"tasks.count","agg":"count_distinct"}',
                            current_date - 30, current_date + 30) $q$);

\echo '--- ניקוי ---'

-- f3 חוזר למצב הזרוע: בלי מענקים אישיים, כפי ש-04 השאירה אותו.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false);
delete from user_permission_grants
 where profile_id = '20000000-0000-0000-0000-0000000000f3'
   and permission_key in ('dashboard.view', 'reports.view');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000f3', false);
select t_eq('f3 חזר להחזיק dashboard.view דרך ברירת המחדל',
  app.has('dashboard.view'), true);
