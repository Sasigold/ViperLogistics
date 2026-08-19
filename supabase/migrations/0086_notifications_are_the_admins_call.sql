-- 0086: מי מקבל אילו התראות — החלטה של מנהל המערכת, ורק שלו
--
-- הדיווח: "שעובד לא יוכל לשלוט על מה לקבל התראות. שאף אחד במערכת לא יוכל
-- לשלוט. אני כאדמין שולט בזה עבור כל אחד או קבוצה."
--
-- שתי שכבות המנהל כבר קיימות מ-0046 ואינן משתנות כאן: `notification_policies`
-- לקהל (עובדים / קבלנים / לקוחות / מנהלים) ו-`notification_policy_overrides`
-- לאדם בודד. מה שיורד הוא השכבה השלישית — `notification_preferences`,
-- בחירתו של המשתמש עצמו — שישבה בתחתית הסולם ויכלה להפוך כל `opt_in`/`opt_out`
-- שהמנהל קבע.
--
-- למה להוריד ולא רק להסתיר את המסך: שורה שנכתבה פעם אחת ממשיכה להכריע לנצח.
-- עובד שכיבה לעצמו "שובצתי למשימה" לפני חצי שנה היה ממשיך לא לקבל, המנהל היה
-- רואה במטריצה "דלוק כברירת מחדל", ושניהם היו צודקים. זו בדיוק התמונה
-- שנתבקשה להיעלם.
--
-- הטבלה עצמה נשארת ואינה נמחקת: השורות שבה הן תיעוד של מה שאנשים ביקשו
-- בעבר, ומחיקה אינה חלק מהתיקון. מ-0086 שום החלטה אינה נשענת עליהן.
--
-- שני הערוצים שכן נשארים בידי המשתמש, ובכוונה: רישום *מכשיר* ל-push (זו
-- הרשאת דפדפן, לא העדפה — אי אפשר לרשום מכשיר בשבילו), וקריאת הפעמון.

-- ===== 1. הסולם, בלי הדרגה האחרונה ========================================
--
-- זהה ל-0046 §7 פרט לשלוש השורות שקראו את `notification_preferences`. המצב
-- שהתקבל מהמנהל הוא עכשיו גם התשובה: `off`/`opt_in` ⇒ לא, `opt_out`/`forced`
-- ⇒ כן. ארבעת המצבים נשארים בטבלאות כי הם ברירות המחדל שבקטלוג ומה שכבר
-- שמור במדיניות; מה שהשתנה הוא שכל אחד מהם מצביע עכשיו על תשובה אחת ויחידה.
create or replace function app.notification_enabled(
  p_profile uuid, p_type text, p_channel text)
returns boolean language plpgsql stable security definer set search_path = public as $$
declare
  v_cfg  jsonb;
  v_mode text;
begin
  if p_profile is null then return false; end if;

  -- 1. נמען לא פעיל או מחוק
  if not exists (select 1 from profiles p
                  where p.id = p_profile and p.is_active and p.deleted_at is null) then
    return false;
  end if;

  -- 2. הערוץ כבוי במערכת + 3. הסוג מושתק גלובלית
  if p_channel <> 'inapp' then
    v_cfg := app.attendance_config('notifications.' || p_channel);
    if not coalesce((v_cfg ->> 'enabled')::boolean, false) then return false; end if;
    if coalesce(v_cfg -> 'muted_types', '[]'::jsonb) ? p_type then return false; end if;
  end if;

  -- 4. חריג אישי שקבע מנהל
  select o.mode into v_mode from notification_policy_overrides o
   where o.profile_id = p_profile and o.type = p_type and o.channel = p_channel;

  -- 5. מדיניות הקהל
  if v_mode is null then
    select p.mode into v_mode from notification_policies p
     where p.audience = app.notification_audience(p_profile)
       and p.type = p_type and p.channel = p_channel;
  end if;

  -- 6. ברירת המחדל בקטלוג
  if v_mode is null then
    v_mode := app.notification_default_mode(p_type, p_channel);
  end if;

  -- 7. סוג שאינו בקטלוג — התאימות לאחור מ-0030
  if v_mode is null then
    v_mode := case when p_channel = 'push' then 'off' else 'opt_out' end;
  end if;

  return v_mode in ('opt_out', 'forced');
end $$;

-- ===== 2. התא, כפי שהמסכים מציירים אותו ===================================
--
-- ‏`locked` היה "המנהל קבע ואי אפשר לשנות", ונכון היה רק ל-off/forced. עכשיו
-- אין תא שאפשר לשנות, ולכן הוא true תמיד — ומסך ההעדפות מצייר לפיו סימן ולא
-- מתג. `mode` נשאר כפי שהוא: הוא עדיין מסביר *למה* ההתראה מגיעה או לא.
create or replace function app.notification_cell(p_profile uuid, p_type text, p_channel text)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_mode text;
  v_chan boolean := true;
begin
  select o.mode into v_mode from notification_policy_overrides o
   where o.profile_id = p_profile and o.type = p_type and o.channel = p_channel;
  if v_mode is null then
    select p.mode into v_mode from notification_policies p
     where p.audience = app.notification_audience(p_profile)
       and p.type = p_type and p.channel = p_channel;
  end if;
  if v_mode is null then v_mode := app.notification_default_mode(p_type, p_channel); end if;
  if v_mode is null then
    v_mode := case when p_channel = 'push' then 'off' else 'opt_out' end;
  end if;

  if p_channel <> 'inapp' then
    v_chan := coalesce(
      (app.attendance_config('notifications.' || p_channel) ->> 'enabled')::boolean, false);
  end if;

  return jsonb_build_object(
    'mode', v_mode,
    'enabled', app.notification_enabled(p_profile, p_type, p_channel),
    'locked', true,
    'channel_enabled', v_chan);
end $$;

-- ===== 3. הכתיבה נסגרת בשרת, לא במסך ======================================
--
-- המסך כבר אינו מציג מתג, אבל "נעול שאפשר לעקוף בקריאת REST אינו נעול"
-- (0046 §2). הפונקציה נשארת בחתימתה ומחזירה שגיאה מפורשת: לקוח ישן שנשאר
-- פתוח בטאב יקבל הודעה שאומרת מה קרה, ולא כישלון סתום.
create or replace function set_notification_preference(
  p_type text, p_channel text, p_enabled boolean)
returns void language plpgsql security definer set search_path = public as $$
begin
  raise exception 'ההתראות נקבעות על ידי מנהל המערכת ואי אפשר לשנות אותן כאן'
    using errcode = '42501';
end $$;

-- ===== 4. והדלת השנייה לאותה טבלה =========================================
--
-- ‏`np_write` של 0030 נתנה לכל אחד לכתוב את השורות של עצמו — כלומר לעקוף את
-- §3 בקריאת PostgREST ישירה. הכתיבה נשארת למי שממילא קובע מדיניות, כדי שלא
-- ייווצר מצב שבו הטבלה נגישה לעריכה למי שאינו יכול לקרוא אותה.
drop policy if exists np_select on notification_preferences;
drop policy if exists np_write  on notification_preferences;

create policy np_select on notification_preferences for select to authenticated
  using ((select app.is_admin()) or (select app.has('notifications.manage')));
create policy np_write on notification_preferences for all to authenticated
  using ((select app.is_admin()) or (select app.has('notifications.manage')))
  with check ((select app.is_admin()) or (select app.has('notifications.manage')));

-- ===== 5. תווית המפתח ====================================================
--
-- ‏`notifications.preferences` פותח עכשיו מסך קריאה: "אילו התראות מגיעות
-- אליי". השם נשאר — הוא מוזכר בניווט, ב-RouteGate ובתפקידים — והתווית
-- מיישרת קו עם מה שהוא באמת מרשה.
update permission_registry
   set label_he = 'צפייה בהתראות שמגיעות אליי',
       description_he = 'רשימת ההתראות שיגיעו למשתמש, לקריאה בלבד — הקביעה היא של מנהל המערכת'
 where key = 'notifications.preferences';
