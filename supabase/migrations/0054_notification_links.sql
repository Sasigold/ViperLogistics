-- 0054: לחיצה על התראה מובילה לפריט עצמו
--
-- שני מסלולים מובילים מהתראה למסך, ואף אחד מהם לא עבד עד הסוף:
--
--   הפעמון (NotificationsBell) לא ניווט בכלל. השורות שם הן <li> בלי onClick,
--   שרק *נראות* לחיצות בזכות hover:bg-hover שנשאר בהן.
--
--   הפוש כן חישב כתובת, ב-linkFor שב-notify-dispatch, אבל היא זרקה את מזהה
--   המשימה ('task' → '/board' בלי id) והובילה כל נמען לאותו מקום. ‏/board מגודר
--   ב-board.view, שהיא הרשאת staff בלבד (0011), ולקבלן אין אותה — כלומר התראת
--   contractor_task הובילה אותו למסך "אין הרשאה".
--
-- שלוש החלטות:
--
--   1. **הכתובת מחושבת בשרת.** זו כבר ההחלטה שכתובה בראש src/sw.ts: ה-Service
--      Worker נשאר טיפש ומנווט לכתובת שקיבל, כי worker מתחלף לאט וכל שינוי
--      ניתוב היה ממתין עד שכל מכשיר יוריד גרסה חדשה. הרחבת אותו כלל לפעמון
--      נותנת מפת ניתוב *אחת*. שתי מפות — אחת ב-Deno ואחת ב-TypeScript — היו
--      נפרדות זו מזו בשקט בשינוי הראשון.
--
--   2. **הכתובת נשמרת על השורה ולא מחושבת בקריאה.** היא עובדה על הרגע שבו
--      ההתראה נולדה: תאריך המשימה שההתראה הצביעה עליו יכול לזוז אחר כך, ואז
--      הקישור היה מוביל לחודש אחר מזה שההודעה דיברה עליו. בנוסף מסלול הפוש
--      קורא ממילא שורה שטוחה, בלי לצרף טבלאות.
--
--   3. **הפיצול בין מסכים הוא לפי user_kind ולא לפי הרשאה.** app.has נשענת על
--      app.profile_id() של ה-session (0010) ואינה יכולה לענות על שאלה לגבי נמען
--      אחר בלי לשכפל את ה-CTE הרקורסיבי שלה. user_kind מפריד בדיוק במקום שבו
--      המסכים נפרדים ממילא — לקבלן יש /portal, ולצוות יש /board.

alter table notifications add column link text;

-- ===== 1. המפה =============================================================
-- ‏security definer: נקראת מתוך app.notify שרצה בהקשר של מי שגרם להתראה, והיא
-- צריכה לקרוא את הנמען, את המשימה ואת שורת הנוכחות — שלושתם מגודרים ב-RLS מול
-- הכותב ולא מול הנמען.
--
-- ישות שנמחקה בינתיים אינה שוברת דבר: התאריך יוצא null, הפרמטר מושמט, והמסך
-- נפתח על החודש הנוכחי במקום על זה של המשימה.
create or replace function app.notification_link(
  p_recipient uuid, p_type text, p_entity_type text, p_entity_id uuid)
returns text language plpgsql stable security definer set search_path = public as $$
declare v_kind text; v_date date;
begin
  if p_entity_id is null then return '/'; end if;

  if p_entity_type = 'event' then
    return '/events/' || p_entity_id;
  end if;

  if p_entity_type = 'task' then
    select user_kind::text into v_kind from profiles where id = p_recipient;
    if v_kind = 'contractor_user' then
      return '/portal?task=' || p_entity_id;
    end if;
    select task_date into v_date from tasks where id = p_entity_id;
    return '/board?task=' || p_entity_id
           || coalesce('&date=' || to_char(v_date, 'YYYY-MM-DD'), '');
  end if;

  if p_entity_type = 'attendance_entry' then
    -- attendance_submitted הולכת למנהל, ולכן לדוח הנוכחות; אישור ודחייה הולכים
    -- לעובד עצמו, ולכן למסך השעון שלו.
    if p_type = 'attendance_submitted' then
      select work_date into v_date from attendance_entries where id = p_entity_id;
      return '/attendance?entry=' || p_entity_id
             || coalesce('&date=' || to_char(v_date, 'YYYY-MM-DD'), '');
    end if;
    return '/my/attendance?entry=' || p_entity_id;
  end if;

  return '/';
end $$;

-- ===== 2. app.notify — הגרסה הרביעית ======================================
-- מוגדרת מחדש במלואה ולא נעטפת, מאותו נימוק שכתוב ב-0030 וב-0046: עטיפה הייתה
-- משאירה שתי פונקציות שמישהו יקרא לשגויה שבהן. הגוף זהה ל-0046 בתוספת link.
create or replace function app.notify(
  p_recipient uuid, p_type text, p_title text, p_body text,
  p_entity_type text default null, p_entity_id uuid default null)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_id    uuid;
  v_email text;
  v_muted boolean;
begin
  if p_recipient is null then return; end if;

  v_muted := not app.notification_enabled(p_recipient, p_type, 'inapp');

  insert into notifications (recipient_id, type, title, body, entity_type, entity_id, muted, link)
  values (p_recipient, p_type, p_title, p_body, p_entity_type, p_entity_id, v_muted,
          app.notification_link(p_recipient, p_type, p_entity_type, p_entity_id))
  returning id into v_id;

  select p.email into v_email from profiles p
   where p.id = p_recipient and p.is_active and p.deleted_at is null;

  insert into notification_deliveries
    (notification_id, recipient_id, channel, address, subscription_id)
  select v_id, p_recipient, 'email', v_email, null
   where v_email is not null and v_email <> ''
     and app.notification_enabled(p_recipient, p_type, 'email')
  union all
  select v_id, p_recipient, 'push', null, s.id
    from push_subscriptions s
   where s.profile_id = p_recipient
     and app.notification_enabled(p_recipient, p_type, 'push');
end $$;

-- ===== 3. התור שמזין את הפוש ==============================================
-- זהה ל-0046 בתוספת 'link'. משלוח שממתין ברגע זה נשלח עם הכתובת החדשה מיד,
-- בלי לחכות להתראה הבאה.
create or replace function notification_pending(p_limit int default 50)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  perform app.require('settings.audit_log');
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'delivery_id', d.id,
      'channel',     d.channel,
      'address',     d.address,
      'push_host',   split_part(s.endpoint, '/', 3),
      'title',       n.title,
      'body',        n.body,
      'type',        n.type,
      'entity_type', n.entity_type,
      'entity_id',   n.entity_id,
      'link',        n.link)
      order by d.created_at)
    from notification_deliveries d
    join notifications n on n.id = d.notification_id
    left join push_subscriptions s on s.id = d.subscription_id
    where d.status = 'pending' and d.attempts < 5
    limit greatest(1, least(p_limit, 200))
  ), '[]'::jsonb);
end $$;

revoke execute on function public.notification_pending(int) from anon, public;

-- ===== 4. מילוי לאחור =====================================================
-- בלי זה כל ההתראות שכבר בפעמון היו נשארות בלי קישור, כלומר לא-לחיצות — מה
-- שנראה כמו תקלה בדיוק במסך שהשינוי הזה בא לתקן.
update notifications n
   set link = app.notification_link(n.recipient_id, n.type, n.entity_type, n.entity_id)
 where n.link is null;
