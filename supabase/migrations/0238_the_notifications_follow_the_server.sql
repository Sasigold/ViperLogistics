-- 0238: the notifications follow the server
--
-- המערכת עברה מ-Supabase בענן לשרת פרטי (VPS), וההתראות (push ומייל)
-- הפסיקו לצאת. הסיבה: בייצור, `app.notify_dispatch_ping` (הטריגר על
-- `notification_deliveries`, 0046 §9) הוחלף מחוץ למאגר (`secure_notify_dispatch_vault`)
-- בגרסה שכתובת פונקציית השליחה *כתובה בה בקוד* —
-- ‏`https://qdrbhwxnijjmprtzxfai.supabase.co/functions/v1/notify-dispatch` — והסוד
-- נקרא מ-Vault. העתק של מסד הנתונים ב-VPS המשיך אפוא לקרוא לפונקציה שבענן,
-- וזו ניקזה את התור של הענן, לא של ה-VPS. בנוסף, סוד ב-Vault שהועתק בגיבוי
-- מוצפן במפתח של השרת הישן ואינו נפתח בשרת החדש.
--
-- מעכשיו שום כתובת אינה כתובה בקוד. הכתובת והסוד נקראים, לפי הסדר:
--   1. ‏Vault: ‏`notify_dispatch_url`, ‏`notify_dispatch_secret`;
--   2. ‏GUC: ‏`alter database postgres set app.notify_dispatch_url/secret` (0030).
-- בלי כתובת או בלי סוד הטריגר שותק (כמו תמיד) — ההתראה בפעמון נשמרת, רק
-- ה-push והמייל ממתינים בתור עד שיוגדרו.
--
-- ‏`get_notify_dispatch_secret` (ש-`notify-dispatch` קורא כדי לאמת את הכותרת
-- ‏`x-dispatch-secret`) היה קיים רק בייצור; הוא נכנס כאן למאגר, עם אותה
-- שרשרת. ‏service_role בלבד. ‏`notify_dispatch_status()` (מנהל מערכת) אומר מה
-- חסר, בלי לחשוף את הסוד. ההוראות המלאות להפעלה בשרת: `docs/SELF_HOSTING.md`.

-- ===== 1. app.server_setting: ‏Vault ואחריו GUC =====
create or replace function app.server_setting(p_name text)
returns text language plpgsql stable security definer set search_path = public as $$
declare v text;
begin
  -- ‏Vault אינו קיים בכל התקנה (בסביבת הבדיקות אין אותו), ולכן דינמי.
  if to_regclass('vault.decrypted_secrets') is not null then
    begin
      execute 'select decrypted_secret from vault.decrypted_secrets where name = $1 limit 1'
        into v using p_name;
    exception when others then
      v := null; -- סוד שהוצפן בשרת אחר אינו נפתח כאן
    end;
  end if;
  return coalesce(nullif(v, ''), nullif(current_setting('app.' || p_name, true), ''));
end $$;

revoke execute on function app.server_setting(text) from anon, authenticated, public;

-- ===== 2. הטריגר: בלי כתובת כתובה בקוד =====
create or replace function app.notify_dispatch_ping()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_url text := app.server_setting('notify_dispatch_url');
  v_secret text := app.server_setting('notify_dispatch_secret');
begin
  if v_url is null or v_secret is null then return null; end if;
  if to_regproc('net.http_post') is null then return null; end if;

  -- גוף ריק = ניקוז מלא: מה שנכשל קודם מקבל הזדמנות נוספת באותה קריאה.
  execute
    'select net.http_post(url := $1, headers := $2, body := $3)'
  using
    v_url,
    jsonb_build_object('Content-Type', 'application/json', 'x-dispatch-secret', v_secret),
    '{}'::jsonb;
  return null;
exception when others then
  raise notice 'notify dispatch ping failed: %', sqlerrm;
  return null;
end $$;

revoke execute on function app.notify_dispatch_ping() from anon, authenticated, public;

-- ===== 3. הסוד ש-notify-dispatch מאמת מולו =====
create or replace function public.get_notify_dispatch_secret()
returns text language plpgsql stable security definer set search_path = public as $$
begin
  return app.server_setting('notify_dispatch_secret');
end $$;

revoke execute on function public.get_notify_dispatch_secret() from anon, authenticated, public;
grant execute on function public.get_notify_dispatch_secret() to service_role;

-- ===== 4. מה חסר (למנהל מערכת, בלי הסוד) =====
create or replace function public.notify_dispatch_status()
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not app.is_admin() then
    raise exception 'רק מנהל מערכת' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'url', app.server_setting('notify_dispatch_url'),
    'secret_set', app.server_setting('notify_dispatch_secret') is not null,
    'pg_net', to_regproc('net.http_post') is not null,
    'push_enabled', coalesce((select (value ->> 'enabled')::boolean
                                from app_settings where key = 'notifications.push'), false),
    'pending', (select count(*) from notification_deliveries where status = 'pending'),
    'oldest_pending', (select min(created_at) from notification_deliveries where status = 'pending'),
    'last_sent', (select max(sent_at) from notification_deliveries where status = 'sent'),
    'last_errors', coalesce((select jsonb_agg(e) from (
        select last_error as e from notification_deliveries
         where last_error is not null order by created_at desc limit 5) x), '[]'::jsonb));
end $$;

revoke execute on function public.notify_dispatch_status() from anon, public;
grant execute on function public.notify_dispatch_status() to authenticated;
