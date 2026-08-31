\pset tuples_only on
\pset format unaligned

-- ================= dashboard_layouts =================
-- הטבלה מחזיקה שני סוגי שורות בסכימה אחת — פריסה של משתמש ופריסת ברירת מחדל —
-- וההפרדה ביניהן היא כל האבטחה שיש כאן. שתי הפוליסות נכתבו בנפרד במכוון, ומה
-- שנבדק למטה הוא בדיוק מה שההפרדה אמורה למנוע: משתמש שמגיע לשורה הארגונית על
-- ידי כתיבת profile_id = null.
--
-- הדמויות נבחרו בקפידה, כי לא כל "איש צוות" בזריעה הוא איש צוות רגיל:
--   f3 — עובד ללא תפקידי הרשאה. זה מי שאמור להיחסם.
--   f1 — נושא את התפקיד ops_manager, ולכן מחזיק settings.edit ודרכו,
--        ב-implied_by, גם dashboard.manage_default. הוא הצד החיובי.
--   f2 — הפך לאדמין בחבילה קודמת, ולכן אינו מעיד על כלום כאן.

\echo '--- פריסת הדשבורד: שורה אישית ---'

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000f3', false);

select t_expect_ok('עובד שומר פריסה משלו',
  $$insert into dashboard_layouts (profile_id, layout)
    values ('20000000-0000-0000-0000-0000000000f3',
            '{"v":1,"items":[{"id":"ops.tasks_today","size":"sm"}],"hidden":[],"seen":[]}')$$);

select t_expect_fail('ואינו יכול לשמור פריסה בשם מישהו אחר',
  $$insert into dashboard_layouts (profile_id, layout)
    values ('20000000-0000-0000-0000-0000000000f1', '{"v":1,"items":[],"hidden":[],"seen":[]}')$$);

-- האינדקס הוא (profile_id, user_kind, name) עם nulls not distinct, ולכן NULL
-- הוא ערך: שורה פעילה שנייה לאותו משתמש מתנגשת ואינה נכנסת בשקט.
select t_expect_fail('שורה פעילה שנייה לאותו משתמש נדחית',
  $$insert into dashboard_layouts (profile_id, layout)
    values ('20000000-0000-0000-0000-0000000000f3', '{"v":1,"items":[],"hidden":[],"seen":[]}')$$);

select t_expect_ok('אבל תצוגה שמורה בשם כן מותרת',
  $$insert into dashboard_layouts (profile_id, name, layout)
    values ('20000000-0000-0000-0000-0000000000f3', 'כספים',
            '{"v":1,"items":[],"hidden":[],"seen":[]}')$$);

select t_expect_fail('ושם כפול לאותו משתמש נדחה',
  $$insert into dashboard_layouts (profile_id, name, layout)
    values ('20000000-0000-0000-0000-0000000000f3', 'כספים',
            '{"v":1,"items":[],"hidden":[],"seen":[]}')$$);

-- שורה שהיא גם אישית וגם מכוונת לסוג משתמש אינה מצב שמישהו יודע לקרוא.
select t_expect_fail('שורה שהיא גם אישית וגם פר-סוג נדחית',
  $$insert into dashboard_layouts (profile_id, user_kind, layout)
    values ('20000000-0000-0000-0000-0000000000f3', 'staff',
            '{"v":1,"items":[],"hidden":[],"seen":[]}')$$);

\echo '--- ברירת המחדל הארגונית ---'

-- זו ההסלמה שהמדיניות הנפרדת קיימת כדי לחסום: dl_write_own נכשלת על
-- profile_id is null, ו-dl_write_default דורשת מפתח שלעובד הזה אין.
select t_expect_fail('עובד בלי המפתח אינו יכול לכתוב ברירת מחדל ארגונית',
  $$insert into dashboard_layouts (profile_id, layout)
    values (null, '{"v":1,"items":[],"hidden":[],"seen":[]}')$$);

select t_expect_fail('וגם לא ברירת מחדל לסוג משתמש',
  $$insert into dashboard_layouts (profile_id, user_kind, layout)
    values (null, 'staff', '{"v":1,"items":[],"hidden":[],"seen":[]}')$$);

-- ================= as an ops manager =================
-- לא אדמין: הוא מגיע ל-dashboard.manage_default דרך settings.edit שבתפקיד,
-- וזו בדיוק ההורשה ש-implied_by נועדה לתת.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000f1', false);

select t_expect_ok('מנהל תפעול שומר פריסה משלו',
  $$insert into dashboard_layouts (profile_id, layout)
    values ('20000000-0000-0000-0000-0000000000f1', '{"v":1,"items":[],"hidden":[],"seen":[]}')$$);

select t_expect_ok('ומחזיק את המפתח דרך settings.edit, ולכן קובע ברירת מחדל ארגונית',
  $$insert into dashboard_layouts (profile_id, layout)
    values (null, '{"v":1,"items":[{"id":"ops.tasks_today","size":"sm"}],"hidden":[],"seen":[]}')$$);

select t_expect_fail('ושנייה כללית נדחית',
  $$insert into dashboard_layouts (profile_id, layout)
    values (null, '{"v":1,"items":[],"hidden":[],"seen":[]}')$$);

select t_expect_ok('אבל ברירת מחדל לסוג משתמש היא שורה אחרת',
  $$insert into dashboard_layouts (profile_id, user_kind, layout)
    values (null, 'staff', '{"v":1,"items":[],"hidden":[],"seen":[]}')$$);

\echo '--- מי רואה מה ---'

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000f3', false);

select t_eq('עובד רואה את שתי שורות ברירת המחדל',
  (select count(*)::int from dashboard_layouts where profile_id is null), 2);

select t_eq('ואינו רואה את הפריסה של עובד אחר',
  (select count(*)::int from dashboard_layouts
    where profile_id = '20000000-0000-0000-0000-0000000000f1'), 0);

select t_rows('ואינו יכול למחוק ברירת מחדל ארגונית',
  $$delete from dashboard_layouts where profile_id is null$$, 0);

select t_rows('ולא את הפריסה של עובד אחר',
  $$delete from dashboard_layouts where profile_id = '20000000-0000-0000-0000-0000000000f1'$$, 0);

select t_eq('הבעלים רואה את שתי השורות שלו',
  (select count(*)::int from dashboard_layouts
    where profile_id = '20000000-0000-0000-0000-0000000000f3'), 2);

select t_expect_ok('ויכול למחוק את שלו',
  $$delete from dashboard_layouts
     where profile_id = '20000000-0000-0000-0000-0000000000f3' and name = 'כספים'$$);

\echo '--- dashboard_sections: 0 אומר אין, null אומר לא בשבילך ---'

-- כל התכנון של הדשבורד נשען על ההבחנה הזו: המסך מצייר 0 ומשמיט null. סקשן
-- שיחזיר 0 או [] למי שאין לו מפתח היה אומר "אין נתונים בטווח", וזו טענה אחרת
-- לגמרי — ושקרית.
select t_eq('עובד ללא מפתחות: הכנסות',
  (dashboard_sections(array['revenue.trend'], current_date - 30, current_date, '{}') -> 'revenue.trend'),
  'null'::jsonb);
select t_eq('עובד ללא מפתחות: עלות קבלנים',
  (dashboard_sections(array['cost.contractor'], current_date - 30, current_date, '{}') -> 'cost.contractor'),
  'null'::jsonb);
select t_eq('עובד ללא מפתחות: עלות שכר',
  (dashboard_sections(array['cost.payroll'], current_date - 30, current_date, '{}') -> 'cost.payroll'),
  'null'::jsonb);
select t_eq('עובד ללא מפתחות: רווח גולמי',
  (dashboard_sections(array['margin.summary'], current_date - 30, current_date, '{}') -> 'margin.summary'),
  'null'::jsonb);
select t_eq('עובד ללא מפתחות: איכות תמחור',
  (dashboard_sections(array['pricing.quality'], current_date - 30, current_date, '{}') -> 'pricing.quality'),
  'null'::jsonb);
select t_eq('עובד ללא מפתחות: שעות נוכחות',
  (dashboard_sections(array['attendance.hours'], current_date - 30, current_date, '{}') -> 'attendance.hours'),
  'null'::jsonb);

-- ...אבל סקשן תפעולי שאינו מגודר כן מגיע, מצומצם ב-RLS לשורות שהקורא רואה.
select t_eq('אבל סקשן תפעולי אינו null',
  (dashboard_sections(array['tasks.by_type'], current_date - 180, current_date + 180, '{}')
     -> 'tasks.by_type') is not null, true);

-- שרת ישן מול לקוח חדש חייב להתדרדר לפחות כרטיסים ולא לשגיאה.
select t_eq('מפתח סקשן לא מוכר חוזר null ולא זורק',
  (dashboard_sections(array['no.such.section'], current_date - 30, current_date, '{}')
     -> 'no.such.section'), 'null'::jsonb);

select t_expect_fail('טווח הפוך נדחה',
  $$select dashboard_sections(array['tasks.by_type'], current_date, current_date - 5, '{}')$$);
select t_expect_fail('טווח גדול מדי נדחה',
  $$select dashboard_sections(array['tasks.by_type'], current_date - 500, current_date, '{}')$$);
select t_expect_fail('יותר מדי סקשנים בבקשה אחת נדחה',
  $$select dashboard_sections(
      -- התקרה עלתה ל-48 ב-0069 (ששת סקשני ההכנסה), ל-50 ב-0090 (שני כרטיסי
      -- הצי) ול-51 ב-0143 (`customer.monthly`). הבדיקה רודפת אחריה במכוון:
      -- תקרה שעלתה בלי שאיש שם לב היא בדיוק מה שהיא נועדה לתפוס.
      (select array_agg('k' || g) from generate_series(1,52) g),
      current_date - 5, current_date, '{}')$$);

-- ================= as the owner admin =================
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false);

select t_eq('אדמין כן מקבל עלות שכר',
  (dashboard_sections(array['cost.payroll'], current_date - 180, current_date + 180, '{}')
     #>> '{cost.payroll,scope}'), 'approved_only');

-- הרווח הוא חיסור של שלושה מספרים שהמסך מציג גם בנפרד, ולכן הוא חייב להסתדר
-- מולם. אם זה לא מסתדר, אחד מהם מסונן אחרת מהאחרים.
select t_eq('הרווח הגולמי הוא בדיוק הכנסות פחות קבלנים פחות שכר',
  (select round((m ->> 'revenue')::numeric - (m ->> 'contractor')::numeric
               - (m ->> 'payroll')::numeric, 2)
     from (select dashboard_sections(array['margin.summary'],
                    current_date - 180, current_date + 180, '{}') -> 'margin.summary' as m) s),
  (select round((m ->> 'gross')::numeric, 2)
     from (select dashboard_sections(array['margin.summary'],
                    current_date - 180, current_date + 180, '{}') -> 'margin.summary' as m) s));

-- משמרת בלי תעריף מחזירה total = null ונופלת מ-sum(). בלי המונה הזה עלות
-- השכר הייתה מדווחת נמוך מדי בלי שאיש ידע.
select t_eq('משמרת ללא תעריף נספרת בנפרד ואינה נחשבת אפס',
  ((dashboard_sections(array['cost.payroll'], current_date - 180, current_date + 180, '{}')
      #>> '{cost.payroll,unrated_shifts}')::int > 0), true);

-- `price` הוא not null default 0, ולכן סכום לבדו אינו מבחין בין "לא סוכם
-- מחיר" ל-"סוכם אפס".
select t_eq('שורות קבלן בסכום אפס נספרות בנפרד',
  ((dashboard_sections(array['cost.contractor'], current_date - 180, current_date + 180, '{}')
      #>> '{cost.contractor,zero_rows}')::int >= 0), true);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000f3', false);

\echo '--- מנוע השכר: נקודת כניסה אחת ---'

-- אין כאן טענה על הרשאת ההרצה של app.attendance_pay_rows: 01_seed.sql מריצה
-- `grant execute on all functions in schema public, app to authenticated` אחרי
-- כל המיגרציות, כדי שעוזרי ה-RLS יהיו נגישים לתפקיד הקורא. הרשאות פר-פונקציה
-- בסכמת app פשוט אינן ניתנות לצפייה מכאן. מה שכן מגן עליה בפרודקשן הוא
-- ש-PostgREST חושף את public בלבד, והשלילה במיגרציה היא שכבה נוספת.
--
-- מה שכן נבדק — וזה מה שהיה נשבר בשקט — הוא שהדוח באמת יושב על הפונקציה ואינו
-- מחזיק עותק שני של ה-CTE-ים. ההשוואה נעשית כאדמין במכוון: רק אצלו scope
-- 'auto' פותח את אותה קבוצת שורות ש-'all' מחזיר, ולכן שני האגפים מדברים על
-- אותם נתונים. אצל עובד רגיל הם *אמורים* להיות שונים, וזה נבדק מיד אחר כך.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false);

select t_eq('סיכום השעות בדוח שווה לחישוב ישיר מעל attendance_pay_rows',
  (select round(coalesce(sum(actual_hours), 0), 2)
     from app.attendance_pay_rows(current_date - 400, current_date + 400,
                                  null, null, false, array['approved'], 'all')),
  (select round(coalesce(sum((r ->> 'actual_hours')::numeric), 0), 2)
     from jsonb_array_elements(
            (attendance_report(current_date - 400, current_date + 400) -> 'rows')) r
    where r ->> 'status' = 'approved'));

select t_eq('ואותו דבר לסכום לתשלום',
  (select round(coalesce(sum((pay ->> 'total')::numeric), 0), 2)
     from app.attendance_pay_rows(current_date - 400, current_date + 400,
                                  null, null, false, array['approved'], 'all')),
  (select round(coalesce(sum((r #>> '{pay,total}')::numeric), 0), 2)
     from jsonb_array_elements(
            (attendance_report(current_date - 400, current_date + 400) -> 'rows')) r
    where r ->> 'status' = 'approved'));

-- 'auto' אינו 'all': עובד ללא attendance.view_all רואה את שורותיו בלבד, וזה
-- בדיוק ההבדל שמצדיק את קיומו של הפרמטר.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000f3', false);

select t_eq('עובד רגיל ב-auto רואה פחות ממה ש-all מחזיר',
  (select (select count(*) from app.attendance_pay_rows(
              current_date - 400, current_date + 400, null, null, false, null, 'auto'))
        < (select count(*) from app.attendance_pay_rows(
              current_date - 400, current_date + 400, null, null, false, null, 'all'))),
  true);

reset role;
