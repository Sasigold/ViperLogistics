\pset tuples_only on
\pset format unaligned

-- ===========================================================================
-- ‏79: ההתראות הולכות אחרי השרת (0238) — אין כתובת כתובה בקוד: הטריגר
-- קורא את הכתובת ואת הסוד מההגדרות של השרת; בלי הגדרה הוא שותק ואינו מפיל
-- את יצירת ההתראה; הסוד נגיש ל-service_role בלבד; מצב השליחה למנהל בלבד.
--
-- אין כאן Vault ואין pg_net, ולכן נבדק המסלול של ה-GUC. נתונים: אין.
-- ===========================================================================

-- הסיד מחזיר הרשאת הרצה לכל פונקציה; מה ש-0238 סגר נסגר כאן שוב.
revoke execute on function app.server_setting(text) from anon, authenticated, public;
revoke execute on function app.notify_dispatch_ping() from anon, authenticated, public;
revoke execute on function public.get_notify_dispatch_secret() from anon, authenticated, public;

\echo '--- אין כתובת כתובה בקוד ---'
select t_eq('הטריגר אינו מזכיר כתובת supabase.co',
  (select prosrc not like '%supabase.co%' from pg_proc
    where oid = 'app.notify_dispatch_ping'::regproc), true);

\echo '--- ההגדרות נקראות מהשרת ---'
select set_config('app.notify_dispatch_url', '', false);
select set_config('app.notify_dispatch_secret', '', false);
select t_eq('בלי הגדרה: אין כתובת', app.server_setting('notify_dispatch_url'), null::text);
select t_eq('בלי הגדרה: אין סוד', get_notify_dispatch_secret(), null::text);

select from (select set_config('app.notify_dispatch_url', 'https://vps.example/functions/v1/notify-dispatch', false)) x;
select from (select set_config('app.notify_dispatch_secret', 's79', false)) x;
select t_eq('הכתובת מה-GUC', app.server_setting('notify_dispatch_url'),
  'https://vps.example/functions/v1/notify-dispatch');
select t_eq('הסוד מה-GUC', get_notify_dispatch_secret(), 's79');

-- בלי pg_net הטריגר שותק — יצירת שורת שליחה לא נופלת
select t_expect_ok('הטריגר אינו מפיל הוספת שורת שליחה',
  $q$ with n as (insert into notifications (recipient_id, type, title)
                  select id, 'event_created', 'בדיקה 79' from profiles limit 1
                  returning id, recipient_id)
      insert into notification_deliveries (notification_id, recipient_id, channel, address, status)
      select id, recipient_id, 'email', 'c79@vl.test', 'skipped' from n $q$);

\echo '--- מי רשאי ---'
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000078a1', false);
select t_expect_fail('משתמש מאומת אינו קורא את הסוד', 'select get_notify_dispatch_secret()');
select t_expect_fail('משתמש מאומת אינו קורא הגדרת שרת', $q$ select app.server_setting('notify_dispatch_url') $q$);
select t_expect_fail('מצב השליחה: לא למי שאינו מנהל', 'select notify_dispatch_status()');
reset role;

select set_config('request.jwt.claim.sub',
  (select user_id::text from profiles
    where is_admin and is_active and deleted_at is null and user_id is not null limit 1), false);
set role authenticated;
select t_eq('מצב השליחה למנהל: הכתובת והסוד מוגדרים',
  (select s ->> 'url' || '|' || (s ->> 'secret_set') from notify_dispatch_status() s),
  'https://vps.example/functions/v1/notify-dispatch|true');
reset role;

select set_config('app.notify_dispatch_url', '', false);
select set_config('app.notify_dispatch_secret', '', false);
select set_config('request.jwt.claim.sub', '', false);
