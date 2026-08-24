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

-- תשע-עשרה מאז 0110: אחת-עשרה פחות שלושה שפרשו (task_changed,
-- event_status_changed, contractor_task — כבויים אך נשארים בקטלוג, כי שורות
-- היסטוריות עדיין מצביעות עליהם) ועוד אחד-עשר חדשים. הספירה נשארת מדויקת
-- ולא הופכת ל-`>= 9`: קטלוג שגדל בלי שאיש שם לב הוא בדיוק מה שהבדיקה הזו
-- נועדה לתפוס.
select t_eq('הקטלוג מכיר את תשעה-עשר הסוגים הפעילים',
  (select count(*)::int from notification_types where is_active), 19);

select t_eq('שלושת הסוגים שפרשו עדיין מוכרים, כבויים',
  (select count(*)::int from notification_types
    where key in ('task_changed','event_status_changed','contractor_task')
      and not is_active), 3);

select t_eq('ולסוג שפרש אין שורות מדיניות',
  (select count(*)::int from notification_policies
    where type in ('task_changed','event_status_changed','contractor_task')), 0);

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

/*
 * ‏0086: ההעדפה האישית ירדה מהסולם. שתי השורות האלה נכתבות, ואינן מכריעות
 * דבר — ההחלטה היא של המנהל, פר-קהל או פר-אדם.
 */
insert into notification_preferences (profile_id, channel, type, enabled) values
  ('20000000-0000-0000-0000-0000000000f1', 'email', 'task_assigned', false);
select t_eq('סוג שהמשתמש כיבה לעצמו — נשלח בכל זאת',
  app.notification_enabled('20000000-0000-0000-0000-0000000000f1', 'task_assigned', 'email'), true);

insert into notification_preferences (profile_id, channel, type, enabled) values
  ('20000000-0000-0000-0000-0000000000f1', 'email', null, false);
select t_eq('וגם כיבוי כללי שלו אינו חוסם',
  app.notification_enabled('20000000-0000-0000-0000-0000000000f1', 'task_time_changed', 'email'), true);

update app_settings set value = jsonb_set(value, '{muted_types}', '["task_time_changed"]'::jsonb)
 where key = 'notifications.email';
select t_eq('השתקה גלובלית גוברת על הכול',
  app.notification_enabled('20000000-0000-0000-0000-0000000000f1', 'task_time_changed', 'email'), false);
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

\echo '--- המנהל מכריע, גם נגד מה שהמשתמש ביקש בעבר ---'

-- המשתמש ביקש במפורש לקבל. המנהל אמר שלא.
insert into notification_preferences (profile_id, channel, type, enabled) values
  ('20000000-0000-0000-0000-0000000000f1', 'email', 'attendance_submitted', true);
select t_eq('off גובר על משתמש שביקש כן',
  app.notification_enabled('20000000-0000-0000-0000-0000000000f1', 'attendance_submitted', 'email'), false);

-- המשתמש ביקש במפורש לא לקבל. המנהל אמר שכן.
insert into notification_preferences (profile_id, channel, type, enabled) values
  ('20000000-0000-0000-0000-000000000001', 'email', 'attendance_submitted', false);
select t_eq('forced גובר על משתמש שביקש לא',
  app.notification_enabled('20000000-0000-0000-0000-000000000001', 'attendance_submitted', 'email'), true);

/*
 * ‏0086: opt_in הוא "לא נשלח" ו-opt_out הוא "נשלח", ובקשת המשתמש אינה
 * משנה אף אחד מהם. עד אז הייתה זו נקודת הכניסה היחידה של המשתמש לסולם.
 */
insert into notification_policies (audience, type, channel, mode) values
  ('staff', 'event_created', 'email', 'opt_in')
on conflict (audience, type, channel) do update set mode = excluded.mode;
select t_eq('opt_in — לא נשלח',
  app.notification_enabled('20000000-0000-0000-0000-0000000000f1', 'event_created', 'email'), false);
insert into notification_preferences (profile_id, channel, type, enabled) values
  ('20000000-0000-0000-0000-0000000000f1', 'email', 'event_created', true);
select t_eq('וגם כשהמשתמש ביקש — עדיין לא נשלח',
  app.notification_enabled('20000000-0000-0000-0000-0000000000f1', 'event_created', 'email'), false);
update notification_policies set mode = 'opt_out'
 where audience = 'staff' and type = 'event_created' and channel = 'email';
select t_eq('ו-opt_out נשלח, גם למי שכיבה לעצמו',
  app.notification_enabled('20000000-0000-0000-0000-0000000000f1', 'event_created', 'email'),
  true);
update notification_preferences set enabled = false
 where profile_id = '20000000-0000-0000-0000-0000000000f1' and type = 'event_created';
select t_eq('...וזה נכון גם אחרי שהוא כיבה במפורש',
  app.notification_enabled('20000000-0000-0000-0000-0000000000f1', 'event_created', 'email'), true);
delete from notification_policies
 where audience = 'staff' and type = 'event_created' and channel = 'email';

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

-- שבעה מאז 0110: חמשת סוגי המשימות (שובצה, בוטל שיבוצה, שובצתי, הוסרתי,
-- שינוי זמנים) ושני סוגי הנוכחות האישיים. "עובד דיווח משמרת" נשאר מאחורי
-- required_permission = attendance.approve_entry, שאין לעובד הזה, וסוגי
-- הרכב מאחורי fleet.view.
select t_eq('my_notification_settings מחזיר רק סוגים של הקהל שלי',
  (select count(*)::int from jsonb_array_elements(my_notification_settings())), 7);

select t_eq('...ובכללם אין את שני הסוגים של המנהל',
  (select count(*)::int from jsonb_array_elements(my_notification_settings()) e
    where e ->> 'type' in ('event_created', 'attendance_submitted')), 0);

/*
 * ‏0086: אין העדפה אישית, ולכן אין גם כתיבה — לא לסוג נעול, לא לסוג פתוח,
 * ולא לסוג שאינו קיים. המסך קורא בלבד, והשרת אומר את אותו דבר.
 */
select t_expect_fail('כתיבת העדפה נדחית — סוג שאינו של הקהל שלי', $$
  select set_notification_preference('attendance_submitted', 'email', true)$$);
select t_expect_fail('...וגם על ערוץ שהיה פתוח עד 0086', $$
  select set_notification_preference('task_assigned', 'email', false)$$);
select t_expect_fail('...וגם על סוג שאינו קיים', $$
  select set_notification_preference('no_such_type', 'email', true)$$);

select t_eq('כל תא מסומן נעול — ההחלטה אינה של המשתמש',
  (select bool_and((e -> 'channels' -> ch ->> 'locked')::boolean)
     from jsonb_array_elements(my_notification_settings()) e,
          unnest(array['inapp','email','push']) ch), true);

select t_eq('וההעדפה שנשמרה בעבר אינה מכריעה',
  (select (e -> 'channels' -> 'email' ->> 'enabled')::boolean
     from jsonb_array_elements(my_notification_settings()) e
    where e ->> 'type' = 'task_assigned'), true);

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
/* ‏0086: גם לא את ההעדפות — לא את של אחרים, וגם לא את של עצמו. אין לו מה
   לעשות בהן, ומסך ההתראות שלו קורא הכול דרך my_notification_settings. */
select t_eq('ולא את טבלת ההעדפות',
  (select count(*)::int from notification_preferences), 0);
select t_rows('ואינו כותב לעצמו העדפה בדלת האחורית', $$
  insert into notification_preferences (profile_id, channel, type, enabled)
  values ('20000000-0000-0000-0000-0000000007a1','email','task_assigned',false)$$, 0);
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

-- ===== 11. הפולטים (0110) ===========================================
--
-- דמויות החבילה: לקוח אקמי (c1/c2) והמנהלים כבר קיימים; לצידם קבלן עם מנהל
-- קבלן, עובד קבלן מקושר לאפליקציה (עם תפקיד contractor_worker, שדוחה את
-- portal.view — כך מנהל ועובד נבדלים) ועובד קבלן בלי חשבון. האירועים
-- והמשימות נטועים ב-current_date+400, מעבר לטווח של כל חבילה אחרת.

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000007b1', 'n7-ctr-mgr@vl.test'),
  ('00000000-0000-0000-0000-0000000007b2', 'n7-ctr-worker@vl.test')
on conflict (id) do nothing;

insert into contractors (id, name) values
  ('70000000-0000-0000-0000-000000000701', 'קבלן הבדיקות');

insert into contractor_workers (id, contractor_id, full_name, user_id) values
  ('70000000-0000-0000-0000-000000000702', '70000000-0000-0000-0000-000000000701',
   'עובד קבלן מקושר', '00000000-0000-0000-0000-0000000007b2'),
  ('70000000-0000-0000-0000-000000000703', '70000000-0000-0000-0000-000000000701',
   'עובד קבלן בלי חשבון', null);

insert into profiles (id, user_id, user_kind, is_admin, full_name, contractor_id, contractor_worker_id) values
  ('20000000-0000-0000-0000-0000000007b1', '00000000-0000-0000-0000-0000000007b1',
   'contractor_user', false, 'מנהל הקבלן', '70000000-0000-0000-0000-000000000701', null),
  ('20000000-0000-0000-0000-0000000007b2', '00000000-0000-0000-0000-0000000007b2',
   'contractor_user', false, 'עובד הקבלן', '70000000-0000-0000-0000-000000000701',
   '70000000-0000-0000-0000-000000000702');

insert into profile_roles (profile_id, role_id)
select '20000000-0000-0000-0000-0000000007b1', id from permission_roles where key = 'contractor_manager';
insert into profile_roles (profile_id, role_id)
select '20000000-0000-0000-0000-0000000007b2', id from permission_roles where key = 'contractor_worker';

-- אירוע לתשתית המשימות (של המשרד — לא אמור להתריע), ומשימה בטיוטה
insert into events (id, customer_id, event_date, created_by) values
  ('30000000-0000-0000-0000-000000000710', '10000000-0000-0000-0000-000000000001',
   current_date + 400, '20000000-0000-0000-0000-000000000001');

insert into tasks (id, event_id, task_type_id, task_date, status_id) values
  ('60000000-0000-0000-0000-000000000711', '30000000-0000-0000-0000-000000000710',
   (select id from task_types where deleted_at is null limit 1),
   current_date + 400,
   (select id from statuses where entity = 'task' and code = 'draft' and deleted_at is null));

delete from notifications where type in (
  'event_created', 'event_approved', 'event_updated', 'event_cancelled', 'spec_uploaded',
  'task_published', 'task_unpublished', 'task_assigned', 'assignment_removed',
  'task_time_changed', 'contractor_worker_count_changed', 'contractor_worker_assigned',
  'attendance_clock_in', 'attendance_clock_out');

\echo '--- מסלול הלקוח: יצירה, אישור, עריכה, ביטול, מפרט ---'

-- ── לקוח פותח אירוע → מנהלים ─────────────────────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000c1', false);
insert into events (id, customer_id, event_date, created_by) values
  ('30000000-0000-0000-0000-000000000712', '10000000-0000-0000-0000-000000000001',
   current_date + 401, '20000000-0000-0000-0000-0000000000c1');
select set_config('request.jwt.claim.sub', '', false);

select t_eq('לקוח פתח אירוע — המנהל שומע',
  (select count(*)::int from notifications where type = 'event_created'
    and recipient_id = '20000000-0000-0000-0000-000000000001'), 1);

-- האירוע של המשרד (0710) לא התריע — created_by אינו לקוח
select t_eq('אירוע שפתח המשרד שקט',
  (select count(*)::int from notifications where type = 'event_created'
    and entity_id = '30000000-0000-0000-0000-000000000710'), 0);

-- ── "אישור לביצוע" → משתמשי הלקוח ────────────────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false);
select t_expect_ok('המנהל מאשר לביצוע', $$
  select set_event_approved('30000000-0000-0000-0000-000000000712', true)$$);

select t_eq('שני משתמשי הלקוח שמעו על האישור',
  (select count(*)::int from notifications where type = 'event_approved'
    and recipient_id in ('20000000-0000-0000-0000-0000000000c1',
                         '20000000-0000-0000-0000-0000000000c2')), 2);

select t_expect_ok('אישור חוזר', $$
  select set_event_approved('30000000-0000-0000-0000-000000000712', true)$$);
select t_eq('אישור על אירוע שכבר מאושר אינו מכפיל',
  (select count(*)::int from notifications where type = 'event_approved'
    and recipient_id in ('20000000-0000-0000-0000-0000000000c1',
                         '20000000-0000-0000-0000-0000000000c2')), 2);

select t_expect_ok('ביטול אישור', $$
  select set_event_approved('30000000-0000-0000-0000-000000000712', false)$$);
select t_eq('ביטול אישור שקט כלפי הלקוח',
  (select count(*)::int from notifications where type = 'event_approved'
    and recipient_id in ('20000000-0000-0000-0000-0000000000c1',
                         '20000000-0000-0000-0000-0000000000c2')), 2);

-- ── לקוח עורך אירוע → מנהלים ─────────────────────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000c1', false);
update events set notes = 'עדכון מהלקוח' where id = '30000000-0000-0000-0000-000000000712';
select set_config('request.jwt.claim.sub', '', false);

select t_eq('לקוח ערך אירוע — המנהל שומע',
  (select count(*)::int from notifications where type = 'event_updated'
    and recipient_id = '20000000-0000-0000-0000-000000000001'), 1);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false);
update events set notes = 'עדכון מהמשרד' where id = '30000000-0000-0000-0000-000000000712';
select set_config('request.jwt.claim.sub', '', false);
select t_eq('עריכה של המשרד שקטה',
  (select count(*)::int from notifications where type = 'event_updated'
    and recipient_id = '20000000-0000-0000-0000-000000000001'), 1);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000c1', false);
update events set notes = 'עדכון מהמשרד' where id = '30000000-0000-0000-0000-000000000712';
select set_config('request.jwt.claim.sub', '', false);
select t_eq('עדכון שאינו משנה דבר שקט',
  (select count(*)::int from notifications where type = 'event_updated'
    and recipient_id = '20000000-0000-0000-0000-000000000001'), 1);

-- ── לקוח מבטל אירוע → מנהלים, פעם אחת ────────────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000c1', false);
update events set status_id = (select id from statuses
  where entity = 'event' and code = 'cancelled' and deleted_at is null)
 where id = '30000000-0000-0000-0000-000000000712';
select set_config('request.jwt.claim.sub', '', false);

select t_eq('לקוח ביטל — המנהל שומע',
  (select count(*)::int from notifications where type = 'event_cancelled'
    and recipient_id = '20000000-0000-0000-0000-000000000001'), 1);
select t_eq('והביטול אינו נספר גם כעריכה',
  (select count(*)::int from notifications where type = 'event_updated'
    and recipient_id = '20000000-0000-0000-0000-000000000001'), 1);

-- ── לקוח מעלה מפרט → מנהלים ──────────────────────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000c1', false);
insert into event_specs (event_id, source, url, title) values
  ('30000000-0000-0000-0000-000000000710', 'link', 'https://example.test/spec-a', 'מפרט מהלקוח');
select set_config('request.jwt.claim.sub', '', false);

select t_eq('מפרט מלקוח — המנהל שומע',
  (select count(*)::int from notifications where type = 'spec_uploaded'
    and recipient_id = '20000000-0000-0000-0000-000000000001'), 1);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false);
insert into event_specs (event_id, source, url, title) values
  ('30000000-0000-0000-0000-000000000710', 'link', 'https://example.test/spec-b', 'מפרט מהמשרד');
select set_config('request.jwt.claim.sub', '', false);
select t_eq('מפרט שהעלה המשרד שקט',
  (select count(*)::int from notifications where type = 'spec_uploaded'
    and recipient_id = '20000000-0000-0000-0000-000000000001'), 1);

\echo '--- מחזור הפרסום של משימה ---'

-- ── שיבוצים בטיוטה שקטים לכולם ───────────────────────────────────────
insert into task_assignments (task_id, profile_id, role) values
  ('60000000-0000-0000-0000-000000000711', '20000000-0000-0000-0000-0000000000f1', 'worker');
insert into task_contractor_terms (task_id, contractor_id) values
  ('60000000-0000-0000-0000-000000000711', '70000000-0000-0000-0000-000000000701');
insert into task_contractor_workers (task_id, contractor_worker_id) values
  ('60000000-0000-0000-0000-000000000711', '70000000-0000-0000-0000-000000000702');

select t_eq('שיבוץ סגל, האצלה ועובד קבלן על טיוטה — שקט',
  (select count(*)::int from notifications
    where type in ('task_published', 'task_assigned')), 0);

-- ── הפרסום מדבר לכל הקהל, שורה לאדם ──────────────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false);
update tasks set status_id = (select id from statuses
  where entity = 'task' and code = 'assigned' and deleted_at is null)
 where id = '60000000-0000-0000-0000-000000000711';
select set_config('request.jwt.claim.sub', '', false);

select t_eq('העובד המשובץ שמע על הפרסום',
  (select count(*)::int from notifications where type = 'task_published'
    and recipient_id = '20000000-0000-0000-0000-0000000000f1'), 1);
select t_eq('מנהל הקבלן שמע',
  (select count(*)::int from notifications where type = 'task_published'
    and recipient_id = '20000000-0000-0000-0000-0000000007b1'), 1);
select t_eq('עובד הקבלן המקושר שמע',
  (select count(*)::int from notifications where type = 'task_published'
    and recipient_id = '20000000-0000-0000-0000-0000000007b2'), 1);
select t_eq('שורה אחת לאדם — שלושה נמענים, שלוש שורות',
  (select count(*)::int from notifications where type = 'task_published'
    and entity_id = '60000000-0000-0000-0000-000000000711'), 3);

-- ── הירידה מפרסום מדברת לאותו קהל ────────────────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false);
update tasks set status_id = (select id from statuses
  where entity = 'task' and code = 'planned' and deleted_at is null)
 where id = '60000000-0000-0000-0000-000000000711';
select set_config('request.jwt.claim.sub', '', false);

select t_eq('הירידה משיבוץ הגיעה לשלושתם',
  (select count(*)::int from notifications where type = 'task_unpublished'
    and entity_id = '60000000-0000-0000-0000-000000000711'
    and recipient_id in ('20000000-0000-0000-0000-0000000000f1',
                         '20000000-0000-0000-0000-0000000007b1',
                         '20000000-0000-0000-0000-0000000007b2')), 3);

-- חזרה לפרסום לקראת ההמשך
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false);
update tasks set status_id = (select id from statuses
  where entity = 'task' and code = 'assigned' and deleted_at is null)
 where id = '60000000-0000-0000-0000-000000000711';
select set_config('request.jwt.claim.sub', '', false);

\echo '--- שיבוץ פרטני אחרי הפרסום ---'

-- סגל: הוספה והסרה (עובד החבילה מ-§8, שאינו אדמין ואינו הקבלן)
insert into task_assignments (task_id, profile_id, role) values
  ('60000000-0000-0000-0000-000000000711', '20000000-0000-0000-0000-0000000007a1', 'worker');
select t_eq('עובד שנוסף אחרי הפרסום שומע',
  (select count(*)::int from notifications where type = 'task_assigned'
    and recipient_id = '20000000-0000-0000-0000-0000000007a1'), 1);

delete from task_assignments
 where task_id = '60000000-0000-0000-0000-000000000711'
   and profile_id = '20000000-0000-0000-0000-0000000007a1';
select t_eq('והסרתו מדברת',
  (select count(*)::int from notifications where type = 'assignment_removed'
    and recipient_id = '20000000-0000-0000-0000-0000000007a1'), 1);

-- עובד קבלן: הסרה והוספה מחדש
delete from task_contractor_workers
 where task_id = '60000000-0000-0000-0000-000000000711'
   and contractor_worker_id = '70000000-0000-0000-0000-000000000702';
select t_eq('עובד קבלן שהוסר שומע',
  (select count(*)::int from notifications where type = 'assignment_removed'
    and recipient_id = '20000000-0000-0000-0000-0000000007b2'), 1);

insert into task_contractor_workers (task_id, contractor_worker_id) values
  ('60000000-0000-0000-0000-000000000711', '70000000-0000-0000-0000-000000000702');
select t_eq('עובד קבלן שנוסף אחרי הפרסום שומע',
  (select count(*)::int from notifications where type = 'task_assigned'
    and recipient_id = '20000000-0000-0000-0000-0000000007b2'), 1);

select t_eq('שיבוץ שהוסיף המשרד אינו מתריע למנהלים',
  (select count(*)::int from notifications where type = 'contractor_worker_assigned'), 0);

-- האצלה: הסרה והוספה מחדש, אחרי פרסום
delete from task_contractor_terms
 where task_id = '60000000-0000-0000-0000-000000000711'
   and contractor_id = '70000000-0000-0000-0000-000000000701';
select t_eq('ביטול ההאצלה מדבר אל מנהל הקבלן',
  (select count(*)::int from notifications where type = 'task_unpublished'
    and recipient_id = '20000000-0000-0000-0000-0000000007b1'
    and title = 'המשימה הוסרה מהקבלן שלך'), 1);

insert into task_contractor_terms (task_id, contractor_id) values
  ('60000000-0000-0000-0000-000000000711', '70000000-0000-0000-0000-000000000701');
select t_eq('האצלה אחרי פרסום מדברת אל מנהל הקבלן',
  (select count(*)::int from notifications where type = 'task_published'
    and recipient_id = '20000000-0000-0000-0000-0000000007b1'
    and title = 'משימה חדשה הוקצתה לך'), 1);
select t_eq('ועובד הקבלן אינו שומע על ההאצלה',
  (select count(*)::int from notifications where type = 'task_published'
    and recipient_id = '20000000-0000-0000-0000-0000000007b2'
    and title = 'משימה חדשה הוקצתה לך'), 0);

\echo '--- קבלן משבץ עובד משלו ---'

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000007b1', false);
insert into task_contractor_workers (task_id, contractor_worker_id) values
  ('60000000-0000-0000-0000-000000000711', '70000000-0000-0000-0000-000000000703');
select set_config('request.jwt.claim.sub', '', false);

select t_eq('קבלן שיבץ עובד — המנהל שומע, עם שם הקבלן',
  (select count(*)::int from notifications where type = 'contractor_worker_assigned'
    and recipient_id = '20000000-0000-0000-0000-000000000001'
    and title like 'קבלן הבדיקות%'), 1);
select t_eq('עובד בלי חשבון אינו מקבל התראת שיבוץ',
  (select count(*)::int from notifications where type = 'task_assigned'
    and body like 'עובד קבלן בלי חשבון%'), 0);

\echo '--- כמות העובדים מהקבלן ---'

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false);
update task_contractor_terms set contractor_worker_count = 5
 where task_id = '60000000-0000-0000-0000-000000000711'
   and contractor_id = '70000000-0000-0000-0000-000000000701';
select set_config('request.jwt.claim.sub', '', false);

select t_eq('מנהל הקבלן שמע על הכמות החדשה',
  (select count(*)::int from notifications where type = 'contractor_worker_count_changed'
    and recipient_id = '20000000-0000-0000-0000-0000000007b1'
    and body like '%5 עובדים%'), 1);
select t_eq('עובד הקבלן לא — זה עניין של המנהל מולו',
  (select count(*)::int from notifications where type = 'contractor_worker_count_changed'
    and recipient_id = '20000000-0000-0000-0000-0000000007b2'), 0);

\echo '--- שינוי זמנים במשימה משובצת ---'

-- שינוי שעת שטח: כל הקהל שומע
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false);
update tasks set onsite_start_time = '09:00'
 where id = '60000000-0000-0000-0000-000000000711';
select set_config('request.jwt.claim.sub', '', false);

select t_eq('שינוי שעת שטח הגיע לעובד, למנהל הקבלן ולעובד הקבלן',
  (select count(*)::int from notifications where type = 'task_time_changed'
    and recipient_id in ('20000000-0000-0000-0000-0000000000f1',
                         '20000000-0000-0000-0000-0000000007b1',
                         '20000000-0000-0000-0000-0000000007b2')), 3);

-- שינוי שעת מחסן: רק מי שמסומן למחסן
update task_contractor_workers set work_site = 'warehouse'
 where task_id = '60000000-0000-0000-0000-000000000711'
   and contractor_worker_id = '70000000-0000-0000-0000-000000000702';

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false);
update tasks set warehouse_start_time = '07:00'
 where id = '60000000-0000-0000-0000-000000000711';
select set_config('request.jwt.claim.sub', '', false);

select t_eq('שינוי שעת מחסן — עובד הקבלן שבמחסן שמע',
  (select count(*)::int from notifications where type = 'task_time_changed'
    and recipient_id = '20000000-0000-0000-0000-0000000007b2'), 2);
select t_eq('ומי שבשטח לא',
  (select count(*)::int from notifications where type = 'task_time_changed'
    and recipient_id in ('20000000-0000-0000-0000-0000000000f1',
                         '20000000-0000-0000-0000-0000000007b1')), 2);

\echo '--- תחולה ---'

-- תחולת עובדים: selected בלי רשימה משתיק את הסגל, אך לא את צד הקבלן
insert into notification_scope_modes (type, entity_kind, mode) values
  ('task_time_changed', 'worker', 'selected');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false);
update tasks set onsite_start_time = '09:30'
 where id = '60000000-0000-0000-0000-000000000711';
select set_config('request.jwt.claim.sub', '', false);

select t_eq('עובד מחוץ לתחולה אינו מקבל — ואין שורה בכלל',
  (select count(*)::int from notifications where type = 'task_time_changed'
    and recipient_id = '20000000-0000-0000-0000-0000000000f1'), 1);
select t_eq('צד הקבלן, שתחולתו לא צומצמה, ממשיך לשמוע',
  (select count(*)::int from notifications where type = 'task_time_changed'
    and recipient_id = '20000000-0000-0000-0000-0000000007b1'), 2);

insert into notification_scopes (type, entity_kind, entity_id) values
  ('task_time_changed', 'worker', '20000000-0000-0000-0000-0000000000f1');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false);
update tasks set onsite_start_time = '10:15'
 where id = '60000000-0000-0000-0000-000000000711';
select set_config('request.jwt.claim.sub', '', false);

select t_eq('עובד שנבחר לתחולה חוזר לשמוע',
  (select count(*)::int from notifications where type = 'task_time_changed'
    and recipient_id = '20000000-0000-0000-0000-0000000000f1'), 2);

-- תחולת לקוחות על אירועים
insert into notification_scope_modes (type, entity_kind, mode) values
  ('event_created', 'customer', 'selected');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000c1', false);
insert into events (id, customer_id, event_date, created_by) values
  ('30000000-0000-0000-0000-000000000714', '10000000-0000-0000-0000-000000000001',
   current_date + 402, '20000000-0000-0000-0000-0000000000c1');
select set_config('request.jwt.claim.sub', '', false);

select t_eq('אירוע של לקוח מחוץ לתחולה שקט',
  (select count(*)::int from notifications where type = 'event_created'
    and recipient_id = '20000000-0000-0000-0000-000000000001'), 1);

insert into notification_scopes (type, entity_kind, entity_id) values
  ('event_created', 'customer', '10000000-0000-0000-0000-000000000001');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000c1', false);
insert into events (id, customer_id, event_date, created_by) values
  ('30000000-0000-0000-0000-000000000715', '10000000-0000-0000-0000-000000000001',
   current_date + 403, '20000000-0000-0000-0000-0000000000c1');
select set_config('request.jwt.claim.sub', '', false);

select t_eq('לקוח שנבחר לתחולה — ההתראה חוזרת',
  (select count(*)::int from notifications where type = 'event_created'
    and recipient_id = '20000000-0000-0000-0000-000000000001'), 2);

-- ישות שאינה קיימת נדחית בשער
select t_expect_fail('אי אפשר להוסיף לתחולה ישות שאינה קיימת', $$
  insert into notification_scopes (type, entity_kind, entity_id)
  values ('event_created', 'customer', '10000000-0000-0000-0000-0000000000ff')$$);

-- ותחולה נקראת רק דרך notifications.manage
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000007a1', false);
select t_eq('עובד מן השורה אינו רואה את התחולה',
  (select count(*)::int from notification_scope_modes), 0);
select t_rows('ואינו כותב אליה', $$
  insert into notification_scope_modes (type, entity_kind, mode)
  values ('event_created', 'contractor', 'selected')$$, 0);
reset role;
select set_config('request.jwt.claim.sub', '', false);

delete from notification_scopes;
delete from notification_scope_modes;

\echo '--- השעון מדבר ---'
-- החתמה אמיתית דרך ה-RPC נבדקת בחבילה 04 (כולל כותרת האיחור); כאן נבדקים
-- הנמענים והתחולה של app.notify_clock_event עצמה.

delete from notifications where type in ('attendance_clock_in', 'attendance_clock_out');

select app.notify_clock_event('20000000-0000-0000-0000-0000000000f1',
  'attendance_clock_in', null, false);
select t_eq('כניסת עובד סגל — המנהל שומע',
  (select count(*)::int from notifications where type = 'attendance_clock_in'
    and recipient_id = '20000000-0000-0000-0000-000000000001'
    and title = 'איש צוות ביצע כניסה'), 1);
select t_eq('מנהל הקבלן אינו שומע על עובד סגל',
  (select count(*)::int from notifications where type = 'attendance_clock_in'
    and recipient_id = '20000000-0000-0000-0000-0000000007b1'), 0);

select app.notify_clock_event('20000000-0000-0000-0000-0000000000f1',
  'attendance_clock_in', null, true);
select t_eq('איחור נרשם בכותרת',
  (select count(*)::int from notifications where type = 'attendance_clock_in'
    and recipient_id = '20000000-0000-0000-0000-000000000001'
    and title = 'איש צוות ביצע כניסה באיחור'), 1);

select app.notify_clock_event('20000000-0000-0000-0000-0000000007b2',
  'attendance_clock_in', null, false);
select t_eq('כניסת עובד קבלן — מנהל הקבלן שומע',
  (select count(*)::int from notifications where type = 'attendance_clock_in'
    and recipient_id = '20000000-0000-0000-0000-0000000007b1'), 1);
select t_eq('וגם המנהל, על כולם',
  (select count(*)::int from notifications where type = 'attendance_clock_in'
    and recipient_id = '20000000-0000-0000-0000-000000000001'), 3);
select t_eq('המחתים אינו שומע על עצמו',
  (select count(*)::int from notifications where type = 'attendance_clock_in'
    and recipient_id = '20000000-0000-0000-0000-0000000007b2'), 0);

select app.notify_clock_event('20000000-0000-0000-0000-0000000007b2',
  'attendance_clock_out', null, false);
select t_eq('יציאה — מנהל הקבלן שומע, בכותרת יציאה',
  (select count(*)::int from notifications where type = 'attendance_clock_out'
    and recipient_id = '20000000-0000-0000-0000-0000000007b1'
    and title = 'עובד הקבלן ביצע יציאה'), 1);

-- תחולה על השעון: צמצום לפי קבלן משתיק את עובדי הקבלן שלא נבחרו
insert into notification_scope_modes (type, entity_kind, mode) values
  ('attendance_clock_in', 'contractor', 'selected');
select app.notify_clock_event('20000000-0000-0000-0000-0000000007b2',
  'attendance_clock_in', null, false);
select t_eq('עובד של קבלן מחוץ לתחולה — אף אחד אינו שומע',
  (select count(*)::int from notifications where type = 'attendance_clock_in'
    and recipient_id = '20000000-0000-0000-0000-0000000007b1'), 1);
delete from notification_scope_modes;

-- ===== 12. ניקוי =====================================================

update app_settings set value = jsonb_set(value, '{enabled}', 'false'::jsonb)
 where key in ('notifications.email', 'notifications.push');

select t_eq('שני הערוצים חזרו לכבוי', app.email_enabled(), false);
