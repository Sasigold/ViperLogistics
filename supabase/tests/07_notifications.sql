\pset tuples_only on
\pset format unaligned

-- 07: מטריצת ההתראות, ערוץ ה-push וההכרעה שמאחוריהם (0046 + 0047)
--
-- החבילה רצה אחרונה ובכוונה: היא מדליקה את notifications.email ואת
-- notifications.push, וכל חבילה שרצה אחריה ומסתכלת על notification_deliveries
-- הייתה רואה תמונה אחרת. בסוף היא מחזירה את שני הערוצים לכבוי.
--
-- הדגש כאן אינו על "האם נכתבה שורה" אלא על *סדר ההכרעה*: מי גובר על מי כאשר
-- למנהל, לקהל, לחריג האישי ולמשתמש עצמו יש דעות סותרות. זו הפונקציונליות
-- שנתבקשה, וזה מה שנשבר בשקט כשמישהו יסדר מחדש את הסולם.

\echo ''
\echo '=== התראות: מטריצה, ערוצים והכרעה ==='

-- ===== 0. נקודת מוצא ================================================

\echo '--- ברירות מחדל ---'

-- 04 החזירה את המפתח לכבוי בסופה
select t_eq('ערוץ המייל כבוי בתחילת החבילה', app.email_enabled(), false);
select t_eq('וגם ערוץ ה-push',
  coalesce((app.attendance_config('notifications.push') ->> 'enabled')::boolean, false), false);

select t_eq('הקטלוג מכיר את תשעת הסוגים',
  (select count(*)::int from notification_types where is_active), 9);

-- הרוח מ-0030: מתג שהלקוח הציג ושום טריגר לא פלט
select t_eq('attendance_reviewed אינו בקטלוג',
  (select count(*)::int from notification_types where key = 'attendance_reviewed'), 0);
select t_eq('ובמקומו שני הסוגים האמיתיים',
  (select count(*)::int from notification_types
    where key in ('attendance_approved','attendance_rejected')), 2);

/*
 * שמירת דרך: כל סוג שנפלט בפועל על ידי המיגרציות חייב להיות בקטלוג. טריגר
 * שיתווסף מחר עם סוג שלא נרשם ייתן כאן כישלון ב-CI, במקום תא ריק במטריצת
 * המנהל שאיש לא ישים לב אליו.
 */
select t_eq('כל סוג שנפלט בפועל מוכר לקטלוג',
  (select count(*)::int from (select distinct type from notifications) n
    where not exists (select 1 from notification_types t where t.key = n.type)), 0);

-- ===== 1. תאימות לאחור: הסולם של 0030 ===============================
--
-- שמונה הדרגות שחבילת 04 מאשרת, הפעם דרך notification_enabled. אם המודל
-- החדש שינה התנהגות קיימת, זה המקום שבו זה יתגלה.

\echo '--- הסולם הישן, דרך המנוע החדש ---'

update profiles set email = 'n7@vl.test' where id = '20000000-0000-0000-0000-0000000000f1';
delete from notification_preferences where profile_id = '20000000-0000-0000-0000-0000000000f1';

select t_eq('ערוץ כבוי חוסם הכול',
  app.notification_enabled('20000000-0000-0000-0000-0000000000f1', 'task_assigned', 'email'), false);

update app_settings set value = jsonb_set(value, '{enabled}', 'true'::jsonb)
 where key = 'notifications.email';

select t_eq('ערוץ דלוק, בלי העדפות — נשלח',
  app.notification_enabled('20000000-0000-0000-0000-0000000000f1', 'task_assigned', 'email'), true);
select t_eq('ו-should_email מסכים איתו',
  app.should_email('20000000-0000-0000-0000-0000000000f1', 'task_assigned'), true);

insert into notification_preferences (profile_id, channel, type, enabled) values
  ('20000000-0000-0000-0000-0000000000f1', 'email', 'task_assigned', false);
select t_eq('סוג שהמשתמש כיבה אינו נשלח',
  app.notification_enabled('20000000-0000-0000-0000-0000000000f1', 'task_assigned', 'email'), false);
select t_eq('אבל סוג אחר ממשיך',
  app.notification_enabled('20000000-0000-0000-0000-0000000000f1', 'task_changed', 'email'), true);

insert into notification_preferences (profile_id, channel, type, enabled) values
  ('20000000-0000-0000-0000-0000000000f1', 'email', null, false);
select t_eq('כיבוי כללי חוסם סוג שלא הוגדר לו כלום',
  app.notification_enabled('20000000-0000-0000-0000-0000000000f1', 'task_changed', 'email'), false);
select t_eq('והעדפה לסוג גוברת על הכללי',
  app.notification_enabled('20000000-0000-0000-0000-0000000000f1', 'task_assigned', 'email'), false);

update app_settings set value = jsonb_set(value, '{muted_types}', '["task_changed"]'::jsonb)
 where key = 'notifications.email';
select t_eq('השתקה גלובלית גוברת על הכול',
  app.notification_enabled('20000000-0000-0000-0000-0000000000f1', 'task_changed', 'email'), false);
update app_settings set value = jsonb_set(value, '{muted_types}', '[]'::jsonb)
 where key = 'notifications.email';

delete from notification_preferences where profile_id = '20000000-0000-0000-0000-0000000000f1';

-- ===== 2. הבאג ב-0030 שתוקן =========================================

\echo '--- אילוץ הייחודיות ---'

insert into notification_preferences (profile_id, channel, type, enabled) values
  ('20000000-0000-0000-0000-0000000000f1', 'email', null, false);

-- לפני התיקון NULL היה "שונה מעצמו" והשורה השנייה נכנסה בשקט, כך שהמתג
-- הראשי במסך ההעדפות צבר שורה בכל לחיצה.
select t_expect_fail('שורה כללית שנייה נדחית עכשיו', $$
  insert into notification_preferences (profile_id, channel, type, enabled) values
    ('20000000-0000-0000-0000-0000000000f1', 'email', null, true)$$);

select t_expect_ok('ו-upsert על אותה שורה מעדכן במקום להכפיל', $$
  insert into notification_preferences (profile_id, channel, type, enabled)
  values ('20000000-0000-0000-0000-0000000000f1', 'email', null, true)
  on conflict (profile_id, channel, type) do update set enabled = excluded.enabled$$);

select t_eq('נשארה שורה כללית אחת',
  (select count(*)::int from notification_preferences
    where profile_id = '20000000-0000-0000-0000-0000000000f1'
      and channel = 'email' and type is null), 1);

delete from notification_preferences where profile_id = '20000000-0000-0000-0000-0000000000f1';

-- ===== 3. קהל =======================================================

\echo '--- הכרעת הקהל ---'

select t_eq('מנהל הוא admin ולא staff, למרות user_kind',
  app.notification_audience('20000000-0000-0000-0000-000000000001'), 'admin');
select t_eq('עובד רגיל הוא staff',
  app.notification_audience('20000000-0000-0000-0000-0000000000f1'), 'staff');
select t_eq('ומשתמש לקוח הוא customer_user',
  app.notification_audience('20000000-0000-0000-0000-0000000000c1'), 'customer_user');

update profiles set email = 'n7admin@vl.test' where id = '20000000-0000-0000-0000-000000000001';

-- אותו סוג, שתי מדיניות. זו כל הנקודה של המטריצה.
insert into notification_policies (audience, type, channel, mode) values
  ('staff', 'attendance_submitted', 'email', 'off'),
  ('admin', 'attendance_submitted', 'email', 'forced')
on conflict (audience, type, channel) do update set mode = excluded.mode;

select t_eq('עובד: כבוי לפי מדיניות הקהל',
  app.notification_enabled('20000000-0000-0000-0000-0000000000f1', 'attendance_submitted', 'email'), false);
select t_eq('מנהל: חובה לפי מדיניות הקהל',
  app.notification_enabled('20000000-0000-0000-0000-000000000001', 'attendance_submitted', 'email'), true);

-- ===== 4. הכפייה שנתבקשה ============================================

\echo '--- נעול וכבוי גוברים על המשתמש ---'

-- המשתמש מבקש במפורש לקבל. המנהל אמר שלא.
insert into notification_preferences (profile_id, channel, type, enabled) values
  ('20000000-0000-0000-0000-0000000000f1', 'email', 'attendance_submitted', true);
select t_eq('off גובר על משתמש שביקש כן',
  app.notification_enabled('20000000-0000-0000-0000-0000000000f1', 'attendance_submitted', 'email'), false);

-- המשתמש מבקש במפורש לא לקבל. המנהל אמר שכן.
insert into notification_preferences (profile_id, channel, type, enabled) values
  ('20000000-0000-0000-0000-000000000001', 'email', 'attendance_submitted', false);
select t_eq('forced גובר על משתמש שביקש לא',
  app.notification_enabled('20000000-0000-0000-0000-000000000001', 'attendance_submitted', 'email'), true);

-- opt_in: כבוי עד שמבקשים
insert into notification_policies (audience, type, channel, mode) values
  ('staff', 'event_created', 'email', 'opt_in')
on conflict (audience, type, channel) do update set mode = excluded.mode;
select t_eq('opt_in כבוי בלי העדפה',
  app.notification_enabled('20000000-0000-0000-0000-0000000000f1', 'event_created', 'email'), false);
insert into notification_preferences (profile_id, channel, type, enabled) values
  ('20000000-0000-0000-0000-0000000000f1', 'email', 'event_created', true);
select t_eq('ונדלק כשמבקשים',
  app.notification_enabled('20000000-0000-0000-0000-0000000000f1', 'event_created', 'email'), true);

-- ===== 5. חריג אישי גובר על הקהל ====================================

\echo '--- חריג אישי ---'

insert into notification_policy_overrides (profile_id, type, channel, mode) values
  ('20000000-0000-0000-0000-0000000000f1', 'attendance_submitted', 'email', 'forced');
select t_eq('החריג האישי גובר על מדיניות הקהל',
  app.notification_enabled('20000000-0000-0000-0000-0000000000f1', 'attendance_submitted', 'email'), true);
delete from notification_policy_overrides
 where profile_id = '20000000-0000-0000-0000-0000000000f1';
select t_eq('ומחיקתו מחזירה את הקהל לשלוט',
  app.notification_enabled('20000000-0000-0000-0000-0000000000f1', 'attendance_submitted', 'email'), false);

-- ===== 6. הפעמון וההשתקה ============================================

\echo '--- השתקת הפעמון ---'

insert into notification_policies (audience, type, channel, mode) values
  ('staff', 'event_created', 'inapp', 'off')
on conflict (audience, type, channel) do update set mode = excluded.mode;

select t_expect_ok('התראה מסוג מושתק', $$
  select app.notify('20000000-0000-0000-0000-0000000000f1', 'event_created',
    'אירוע חדש', 'בדיקת השתקה', null, null)$$);

select t_eq('השורה נכתבה בכל זאת — היא היומן',
  (select count(*)::int from notifications
    where recipient_id = '20000000-0000-0000-0000-0000000000f1'
      and type = 'event_created' and body = 'בדיקת השתקה'), 1);
select t_eq('אבל מסומנת muted',
  (select muted from notifications
    where recipient_id = '20000000-0000-0000-0000-0000000000f1'
      and type = 'event_created' and body = 'בדיקת השתקה'), true);

delete from notification_policies where audience = 'staff' and type = 'event_created';

-- ===== 7. Push ======================================================

\echo '--- ערוץ ה-push ---'

insert into push_subscriptions (profile_id, endpoint, p256dh, auth, user_agent) values
  ('20000000-0000-0000-0000-0000000000f1', 'https://fcm.googleapis.com/fcm/send/AAA', 'k1', 'a1', 'Chrome');

-- שני בלמים בלתי תלויים: הקטלוג אומר off, והמפתח אומר enabled=false
select t_eq('מכשיר רשום עדיין אינו מספיק — הערוץ כבוי',
  app.notification_enabled('20000000-0000-0000-0000-0000000000f1', 'task_assigned', 'push'), false);

update app_settings set value = jsonb_set(value, '{enabled}', 'true'::jsonb)
 where key = 'notifications.push';

select t_eq('גם אחרי הדלקת הערוץ — ברירת המחדל בקטלוג היא opt_in',
  app.notification_enabled('20000000-0000-0000-0000-0000000000f1', 'task_assigned', 'push'), false);

insert into notification_policies (audience, type, channel, mode) values
  ('staff', 'task_assigned', 'push', 'opt_out')
on conflict (audience, type, channel) do update set mode = excluded.mode;
select t_eq('ומדיניות opt_out פותחת אותו',
  app.notification_enabled('20000000-0000-0000-0000-0000000000f1', 'task_assigned', 'push'), true);

delete from notification_deliveries;
delete from notifications where recipient_id = '20000000-0000-0000-0000-0000000000f1';
delete from notification_preferences where profile_id = '20000000-0000-0000-0000-0000000000f1';

select t_expect_ok('התראה עם מכשיר אחד', $$
  select app.notify('20000000-0000-0000-0000-0000000000f1', 'task_assigned',
    'שובצת', 'push אחד', null, null)$$);

select t_eq('שורת push אחת',
  (select count(*)::int from notification_deliveries
    where recipient_id = '20000000-0000-0000-0000-0000000000f1' and channel = 'push'), 1);
select t_eq('ולצידה המייל',
  (select count(*)::int from notification_deliveries
    where recipient_id = '20000000-0000-0000-0000-0000000000f1' and channel = 'email'), 1);
select t_eq('שורת ה-push קשורה למנוי',
  (select count(*)::int from notification_deliveries
    where channel = 'push' and subscription_id is not null), 1);

-- מכשיר שני: שורה לכל מכשיר, אבל שורת התראה אחת
insert into push_subscriptions (profile_id, endpoint, p256dh, auth, user_agent) values
  ('20000000-0000-0000-0000-0000000000f1', 'https://updates.push.services.mozilla.com/wpush/BBB', 'k2', 'a2', 'Firefox');

delete from notification_deliveries;
delete from notifications where recipient_id = '20000000-0000-0000-0000-0000000000f1';

select t_expect_ok('התראה עם שני מכשירים', $$
  select app.notify('20000000-0000-0000-0000-0000000000f1', 'task_assigned',
    'שובצת', 'שני מכשירים', null, null)$$);

select t_eq('שתי שורות push',
  (select count(*)::int from notification_deliveries where channel = 'push'), 2);
select t_eq('אבל שורת התראה אחת בלבד',
  (select count(*)::int from notifications
    where recipient_id = '20000000-0000-0000-0000-0000000000f1' and body = 'שני מכשירים'), 1);

-- מנוי מת: ה-Edge Function מוחקת אותו, והמשלוחים התלויים בו הולכים בקסקייד
delete from push_subscriptions where endpoint = 'https://fcm.googleapis.com/fcm/send/AAA';
select t_eq('מחיקת מנוי מפילה את המשלוח שלו',
  (select count(*)::int from notification_deliveries where channel = 'push'), 1);

-- אילוץ היעד: שורה בלי כתובת ובלי מנוי אינה חוקית
select t_expect_fail('משלוח מייל בלי כתובת נדחה', $$
  insert into notification_deliveries (notification_id, recipient_id, channel)
  select id, recipient_id, 'email' from notifications limit 1$$);

-- ===== 8. RPCs ======================================================
--
-- מכאן ואילך נדרש עובד *בלי* הרשאות, וזה אינו f1: חבילה 06 מעניקה לו
-- מפתחות ומשאירה חלק מהם, ובכללם settings.edit — ומכיוון ש-
-- notifications.manage נגזר ממנו (implied_by), f1 הוא מנהל התראות לכל דבר
-- בשלב הזה. עובד ייעודי לחבילה הזו הוא מה שהופך את הטענות למשמעותיות.

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000007a1', 'notif@vl.test')
on conflict (id) do nothing;
insert into profiles (id, user_id, user_kind, is_admin, full_name, email) values
  ('20000000-0000-0000-0000-0000000007a1', '00000000-0000-0000-0000-0000000007a1',
   'staff', false, 'עובד לבדיקת התראות', 'notif@vl.test')
on conflict (id) do nothing;

\echo '--- ה-RPCs של המסכים ---'

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000007a1', false);

-- שישה ולא שמונה מאז 0064: "לקוח פתח אירוע חדש" צומצם לקהל 'admin' (הפולט
-- ממילא רץ על `where is_admin`), ו"עובד דיווח משמרת" קיבל
-- required_permission = attendance.approve_entry, שאין לעובד הזה.
select t_eq('my_notification_settings מחזיר רק סוגים של הקהל שלי',
  (select count(*)::int from jsonb_array_elements(my_notification_settings())), 6);

select t_eq('...ובכללם אין את שני הסוגים של המנהל',
  (select count(*)::int from jsonb_array_elements(my_notification_settings()) e
    where e ->> 'type' in ('event_created', 'attendance_submitted')), 0);

select t_expect_fail('וגם כתיבה ישירה עליהם נדחית', $$
  select set_notification_preference('attendance_submitted', 'email', true)$$);

select t_eq('task_assigned מסומן נעול בפעמון',
  (select (e -> 'channels' -> 'inapp' ->> 'locked')::boolean
     from jsonb_array_elements(my_notification_settings()) e
    where e ->> 'type' = 'task_assigned'), true);

select t_expect_fail('שינוי העדפה על סוג נעול נדחה בקול', $$
  select set_notification_preference('task_assigned', 'inapp', false)$$);

select t_expect_ok('אבל על ערוץ פתוח עובד', $$
  select set_notification_preference('task_assigned', 'email', false)$$);

select t_eq('וההעדפה נכנסה לתוקף',
  (select (e -> 'channels' -> 'email' ->> 'enabled')::boolean
     from jsonb_array_elements(my_notification_settings()) e
    where e ->> 'type' = 'task_assigned'), false);

select t_expect_fail('סוג שאינו קיים נדחה', $$
  select set_notification_preference('no_such_type', 'email', true)$$);

select t_expect_fail('עובד אינו מריץ את סטטיסטיקת המכשירים', $$
  select notification_push_stats()$$);
select t_expect_fail('ואינו קורא הגדרות של אחר', $$
  select notification_user_settings('20000000-0000-0000-0000-000000000001')$$);

reset role;
select set_config('request.jwt.claim.sub', '', false);

/*
 * anon (מי שאינו מחובר בכלל) לא אמור להריץ אף אחת מהפונקציות האלה, גם לא
 * את אלה שבטוחות "במקרה" (מחזירות [] או זורקות כשאין משתמש). ה-EXECUTE
 * חייב להיחסם ב-grant, לא להישען על ההתנהגות הפנימית של הפונקציה —
 * ראו את התיקון ב-0048 למה שקרה כשזה לא נאכף.
 */
set role anon;
select t_expect_fail('anon אינו מריץ my_notification_settings', $$
  select my_notification_settings()$$);
select t_expect_fail('anon אינו מריץ set_notification_preference', $$
  select set_notification_preference('task_assigned', 'email', true)$$);
reset role;

-- ===== 9. RLS =======================================================

\echo '--- RLS ---'

-- לעובד הייעודי יש מכשיר אחד משלו, ובעולם יש עוד כמה של אחרים
reset role;
select set_config('request.jwt.claim.sub', '', false);
insert into push_subscriptions (profile_id, endpoint, p256dh, auth) values
  ('20000000-0000-0000-0000-0000000007a1', 'https://fcm.googleapis.com/fcm/send/N7', 'k7', 'a7');

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000007a1', false);

select t_eq('עובד רואה רק את המכשירים של עצמו',
  (select count(*)::int from push_subscriptions), 1);
select t_eq('ואינו רואה את המטריצה בכלל',
  (select count(*)::int from notification_policies), 0);
select t_eq('ולא את החריגים',
  (select count(*)::int from notification_policy_overrides), 0);
select t_eq('אבל כן את הקטלוג — הוא צריך אותו למסך',
  (select count(*) > 0 from notification_types), true);

select t_rows('ואינו כותב מדיניות', $$
  insert into notification_policies (audience, type, channel, mode)
  values ('staff','contractor_task','email','off')$$, 0);

select t_rows('ואי אפשר לרשום מכשיר על שם אחר', $$
  insert into push_subscriptions (profile_id, endpoint, p256dh, auth)
  values ('20000000-0000-0000-0000-0000000000f2','https://x/DDD','k','a')$$, 0);

reset role;
select set_config('request.jwt.claim.sub', '', false);

-- ===== 10. ההרשאה ===================================================

\echo '--- הרשאת הניהול ---'

select t_eq('notifications.manage רשומה',
  (select count(*)::int from permission_registry where key = 'notifications.manage'), 1);
select t_eq('ואינה ניתנת כברירת מחדל',
  (select default_allowed from permission_registry where key = 'notifications.manage'), false);

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000007a1', false);
select t_eq('עובד מן השורה אינו מנהל התראות', app.has('notifications.manage'), false);
reset role;

/*
 * הנגזרת מ-settings.edit מכוונת ונבדקת: עורך ההגדרות כותב היום את
 * notifications.email, ופוליסת app_settings החדשה — שמייחדת את המפתחות
 * האלה ל-notifications.manage — הייתה נועלת אותו החוצה ברגע הפריסה.
 */
-- ההענקה עצמה עוברת דרך app.guard_permission_grant (0014), שדורש מנהל אמיתי
-- ולא סתם חיבור ללא זהות. לכן היא נעשית בזהות בעל המערכת.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false);
insert into user_permission_grants (profile_id, permission_key, allowed) values
  ('20000000-0000-0000-0000-0000000007a1', 'settings.edit', true)
on conflict (profile_id, permission_key) do update set allowed = true;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000007a1', false);
set role authenticated;
select t_eq('מי שמחזיק settings.edit יורש את ניהול ההתראות',
  app.has('notifications.manage'), true);
reset role;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false);
delete from user_permission_grants
 where profile_id = '20000000-0000-0000-0000-0000000007a1' and permission_key = 'settings.edit';
select set_config('request.jwt.claim.sub', '', false);
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false);
set role authenticated;
select t_eq('ובעל המערכת כן', app.has('notifications.manage'), true);
select t_expect_ok('ומריץ את סטטיסטיקת המכשירים', $$select notification_push_stats()$$);
reset role;
select set_config('request.jwt.claim.sub', '', false);

-- ===== 11. הפולטים החדשים (0047) ====================================

\echo '--- שינוי סטטוס אירוע ---'

delete from notifications where type = 'event_status_changed';

-- אירוע של הלקוח שיש לו משתמשים, ובסטטוס שאינו היעד — אחרת ה-update אינו
-- שינוי והטריגר שותק בצדק.
create temp table n7_event as
select e.id from events e
 where e.customer_id = '10000000-0000-0000-0000-000000000001'
   and e.deleted_at is null
   and e.status_id is distinct from
       (select id from statuses where entity = 'event' and code = 'approved' and deleted_at is null)
 limit 1;

update events set status_id = (select id from statuses
  where entity = 'event' and code = 'approved' and deleted_at is null)
 where id in (select id from n7_event);

select t_eq('משתמשי הלקוח קיבלו התראה',
  (select count(*)::int from notifications
    where type = 'event_status_changed'
      and recipient_id in ('20000000-0000-0000-0000-0000000000c1',
                           '20000000-0000-0000-0000-0000000000c2')), 2);
select t_eq('ואיש צוות לא קיבל — הסוג נשלח ללקוח',
  (select count(*)::int from notifications
    where type = 'event_status_changed'
      and recipient_id = '20000000-0000-0000-0000-0000000000f1'), 0);

-- update שאינו נוגע בסטטוס אינו מייצר דבר
update events set notes = coalesce(notes,'') || '.'
 where id in (select id from n7_event);
select t_eq('עדכון שאינו סטטוס אינו מתריע',
  (select count(*)::int from notifications
    where type = 'event_status_changed'
      and recipient_id in ('20000000-0000-0000-0000-0000000000c1',
                           '20000000-0000-0000-0000-0000000000c2')), 2);

\echo '--- שיבוץ, ביטול שיבוץ, ופרסום (0064) ---'

delete from notifications where type in ('assignment_removed', 'task_assigned');

create temp table n7_task as
select t.id from tasks t where t.deleted_at is null order by t.created_at limit 1;

-- ── משימה שטרם פורסמה: שני הכיוונים שקטים ─────────────────────────────
update tasks set status_id = (select id from statuses
  where entity = 'task' and code = 'draft' and deleted_at is null)
 where id in (select id from n7_task);

insert into task_assignments (task_id, profile_id, role)
select id, '20000000-0000-0000-0000-0000000000f2', 'worker' from n7_task
on conflict do nothing;

select t_eq('שיבוץ למשימה בטיוטה אינו מתריע',
  (select count(*)::int from notifications
    where type = 'task_assigned'
      and recipient_id = '20000000-0000-0000-0000-0000000000f2'), 0);

delete from task_assignments
 where profile_id = '20000000-0000-0000-0000-0000000000f2'
   and task_id in (select id from n7_task);

select t_eq('וגם הסרתו שקטה — העובד מעולם לא ראה את המשימה',
  (select count(*)::int from notifications
    where type = 'assignment_removed'
      and recipient_id = '20000000-0000-0000-0000-0000000000f2'), 0);

-- ── הפרסום עצמו מודיע למי שכבר שובץ ──────────────────────────────────
insert into task_assignments (task_id, profile_id, role)
select id, '20000000-0000-0000-0000-0000000000f2', 'worker' from n7_task
on conflict do nothing;

update tasks set status_id = (select id from statuses
  where entity = 'task' and code = 'assigned' and deleted_at is null)
 where id in (select id from n7_task);

select t_eq('מעבר ל"משובץ" מודיע למי ששובץ קודם',
  (select count(*)::int from notifications
    where type = 'task_assigned'
      and recipient_id = '20000000-0000-0000-0000-0000000000f2'), 1);

-- אותו סטטוס פעם שנייה אינו אירוע
update tasks set worker_count = coalesce(worker_count, 0) + 1
 where id in (select id from n7_task);
select t_eq('עדכון שאינו סטטוס אינו מתריע שוב',
  (select count(*)::int from notifications
    where type = 'task_assigned'
      and recipient_id = '20000000-0000-0000-0000-0000000000f2'), 1);

-- ── ומכאן הסרה כן מדברת ──────────────────────────────────────────────
delete from task_assignments
 where profile_id = '20000000-0000-0000-0000-0000000000f2'
   and task_id in (select id from n7_task);

select t_eq('הסרת שיבוץ ממשימה שפורסמה מודיעה לעובד',
  (select count(*)::int from notifications
    where type = 'assignment_removed'
      and recipient_id = '20000000-0000-0000-0000-0000000000f2'), 1);

-- מחיקת משימה מפילה שיבוצים בקסקייד. מטח התראות על משהו שאינו קיים הוא רעש.
delete from notifications where type = 'assignment_removed';
insert into tasks (event_id, task_type_id, task_date, status_id)
select e.id, (select id from task_types where deleted_at is null limit 1),
       -- משובץ במפורש: על משימה שלא פורסמה השקט מובטח ממילא (0064), והטענה
       -- כאן היא דווקא שגם משימה שפורסמה שותקת כשהיא נמחקת
       current_date + 30, (select id from statuses
                            where entity = 'task' and code = 'assigned' and deleted_at is null)
  from events e where e.deleted_at is null order by e.created_at limit 1;

insert into task_assignments (task_id, profile_id, role)
select id, '20000000-0000-0000-0000-0000000000f2', 'worker'
  from tasks order by created_at desc limit 1;

delete from tasks where id = (select id from tasks order by created_at desc limit 1);

select t_eq('מחיקת משימה אינה מייצרת התראות ביטול',
  (select count(*)::int from notifications where type = 'assignment_removed'), 0);

-- ===== 12. ניקוי =====================================================

update app_settings set value = jsonb_set(value, '{enabled}', 'false'::jsonb)
 where key in ('notifications.email', 'notifications.push');

select t_eq('שני הערוצים חזרו לכבוי', app.email_enabled(), false);

-- ===== 13. ה-endpoint של מנוי דחיפה (0077) ===========================
--
-- הטבלה נכתבת ישירות מהדפדפן, והערך נקרא בידי notify-dispatch ב-service role
-- כדי לבצע בקשה יוצאת. כל מה שאינו שירות דחיפה אמיתי הוא כתובת שמשתמש מחובר
-- בחר עבור השרת.

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000007a1', false);

select t_expect_ok('מנוי מ-FCM נכנס', $$
  insert into push_subscriptions (profile_id, endpoint, p256dh, auth)
  values ('20000000-0000-0000-0000-0000000007a1',
          'https://fcm.googleapis.com/fcm/send/abc123', 'k', 'a')$$);

select t_expect_ok('וגם מ-Apple', $$
  insert into push_subscriptions (profile_id, endpoint, p256dh, auth)
  values ('20000000-0000-0000-0000-0000000007a1',
          'https://web.push.apple.com/QRS', 'k', 'a')$$);

select t_expect_ok('וגם תת-דומיין של WNS', $$
  insert into push_subscriptions (profile_id, endpoint, p256dh, auth)
  values ('20000000-0000-0000-0000-0000000007a1',
          'https://db5p.notify.windows.com/w/?token=x', 'k', 'a')$$);

-- ה-SSRF עצמו: רשת פנימית, לולאה מקומית, ושירות המטא-דאטה של ענן
select t_expect_fail('כתובת פנימית נדחית', $$
  insert into push_subscriptions (profile_id, endpoint, p256dh, auth)
  values ('20000000-0000-0000-0000-0000000007a1',
          'https://10.0.0.5:8080/admin', 'k', 'a')$$);

select t_expect_fail('לוקאלהוסט נדחה', $$
  insert into push_subscriptions (profile_id, endpoint, p256dh, auth)
  values ('20000000-0000-0000-0000-0000000007a1',
          'https://127.0.0.1/health', 'k', 'a')$$);

select t_expect_fail('שירות המטא-דאטה נדחה', $$
  insert into push_subscriptions (profile_id, endpoint, p256dh, auth)
  values ('20000000-0000-0000-0000-0000000007a1',
          'https://169.254.169.254/latest/meta-data/', 'k', 'a')$$);

select t_expect_fail('http פשוט נדחה גם למארח מותר', $$
  insert into push_subscriptions (profile_id, endpoint, p256dh, auth)
  values ('20000000-0000-0000-0000-0000000007a1',
          'http://fcm.googleapis.com/fcm/send/x', 'k', 'a')$$);

-- מארח מותר כרכיב בתוך כתובת של מארח אחר: העיגון ב-^ הוא מה שחוסם את זה
select t_expect_fail('מארח מותר כקידומת של דומיין אחר נדחה', $$
  insert into push_subscriptions (profile_id, endpoint, p256dh, auth)
  values ('20000000-0000-0000-0000-0000000007a1',
          'https://fcm.googleapis.com.evil.test/x', 'k', 'a')$$);

select t_expect_fail('ומארח מותר בתוך הנתיב אינו הופך את היעד למותר', $$
  insert into push_subscriptions (profile_id, endpoint, p256dh, auth)
  values ('20000000-0000-0000-0000-0000000007a1',
          'https://evil.test/https://fcm.googleapis.com/', 'k', 'a')$$);

-- עדכון הוא הנתיב השני אל אותה עמודה, ו-ps_own מתירה אותו
select t_expect_fail('גם עדכון של שורה קיימת אינו יכול להוציא את הכתובת החוצה', $$
  update push_subscriptions set endpoint = 'https://192.168.1.1/x'
   where endpoint = 'https://fcm.googleapis.com/fcm/send/abc123'$$);

delete from push_subscriptions where profile_id = '20000000-0000-0000-0000-0000000007a1';

reset role;
select set_config('request.jwt.claim.sub', '', false);
