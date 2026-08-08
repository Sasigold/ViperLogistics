-- 0048: my_notification_settings ו-set_notification_preference נחסמו רק
-- מ-anon ולא גם מ-public ב-0046. anon יורש הרשאות דרך חברותו ב-PUBLIC,
-- ולכן revoke שמכוון רק אליו לא סגר בפועל את הגישה — התבנית הנכונה, שהשאר
-- בקובץ עקבו אחריה, היא revoke משני התפקידים (ראו 0030).
--
-- שתי הפונקציות בטוחות בפועל למשתמש אנונימי (מחזירות [] / זורקות 42501),
-- ולכן זה לא היה חור אבטחה בפועל — אבל זו לא הייתה הכוונה, ולינטר האבטחה
-- של Supabase צדק כשסימן את זה.
revoke execute on function public.my_notification_settings() from public;
revoke execute on function public.set_notification_preference(text, text, boolean) from public;
