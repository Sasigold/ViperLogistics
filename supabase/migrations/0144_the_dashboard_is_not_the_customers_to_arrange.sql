-- 0144: הדשבורד של הלקוח אינו שלו לסדר
--
-- ‏`dashboard.customize` נרשם ב-0038 כ"מותר כברירת מחדל", ובנימוק נכון:
-- לסדר את הדשבורד של עצמך אינו נתון שנחשף אלא העדפת תצוגה. מה שלא נאמר שם
-- הוא שהקהל כלל גם את הלקוח — ולכן הלקוח יכול היום לגרור ווידג׳טים, להסתיר
-- אותם, לבנות חדשים ולשמור תצוגות. זה נסגר כאן, יחד עם בורר הטווח.
--
-- ‏**מלכודת שחייבת להיאמר**, אחרת התיקון נראה כאילו נעשה ולא נעשה:
-- ‏`app.has` **אינו** מסתכל על `applies_to` (0026, 0042), ו-
-- ‏`app.register_permission` **אינו** מעדכן `default_allowed` ב-`on conflict`.
-- כלומר צמצום ה-`applies_to` לבדו אינו שולל דבר. הוא נשאר כאן בשביל מטריצת
-- ההרשאות ובשביל השומר של 0014, והשלילה עצמה יושבת בשתי השכבות שמדברות —
-- ‏`kind` ו-`role` — בדפוס של 0074 §2.


-- ===== 1. הקהל שברישום =====================================================

select app.register_permission(
  'dashboard.customize', 'dashboard', 'התאמת דשבורד אישית',
  'בחירת ווידג׳טים, גודלם וסדרם, ושמירת התצוגה',
  'action', true, false,
  array['staff']::user_kind[], 'dashboard.view', 50);

-- ===== 2. בורר הטווח =======================================================
--
-- מפתח ולא תנאי מקודד על `user_kind`. הוא מסך בלבד ואין לו מקבילה בשרת —
-- בדיוק כמו `dashboard.customize` עצמו — אבל זה מה שמאפשר למשרד לפתוח אותו
-- ללקוח אחד בלי לגעת באחרים, ומה שמציג אותו במסך ההרשאות במקום להסתיר את
-- ההכרעה בתוך TSX.
--
-- ‏`default_allowed` דלוק: לצוות ולקבלן אין כאן שינוי, וברירת המחדל היא
-- שהטווח פתוח. הלקוח נשלל בשתי השכבות שלמטה, ונשאר על `defaultRange()` —
-- החודש הנוכחי, שהוא בדיוק מה שהוא נשאל עליו.

select app.register_permission(
  'dashboard.change_range', 'dashboard', 'שינוי טווח התאריכים בדשבורד',
  'הפריסטים ושני שדות התאריך בראש המסך. בלעדיו הדשבורד מציג את החודש הנוכחי',
  'action', true, false,
  array['staff', 'contractor_user']::user_kind[], 'dashboard.view', 55);


-- ===== 3. השלילה, בשתי השכבות שמדברות ======================================
--
-- ‏`dashboard.export` כבר יושב כאן מ-0066, ואינו חוזר.

insert into kind_permission_defaults (user_kind, permission_key, allowed) values
  ('customer_user', 'dashboard.customize',      false),
  ('customer_user', 'dashboard.change_range',   false),
  ('customer_user', 'dashboard.build_widget',   false),
  ('customer_user', 'dashboard.share_widget',   false),
  ('customer_user', 'dashboard.manage_default', false)
on conflict (user_kind, permission_key) do update set allowed = excluded.allowed;

-- התפקיד גובר על ה-kind, ולכן אותה שלילה חוזרת בו. עדכון **וגם** הוספה
-- מפורשת: תפקיד שאין לו שורה בכלל היה נשען על ירושה שתשתנה בעתיד.
update role_permissions rp
   set allowed = false
  from permission_roles r
 where r.id = rp.role_id
   and r.user_kind = 'customer_user'
   and rp.permission_key in ('dashboard.customize', 'dashboard.change_range',
                             'dashboard.build_widget', 'dashboard.share_widget',
                             'dashboard.manage_default');

insert into role_permissions (role_id, permission_key, allowed)
select r.id, k, false
  from permission_roles r
 cross join unnest(array['dashboard.customize', 'dashboard.change_range',
                         'dashboard.build_widget', 'dashboard.share_widget',
                         'dashboard.manage_default']) as k
 where r.user_kind = 'customer_user'
on conflict (role_id, permission_key) do update set allowed = false;

-- וההענקה הפרטנית, שגוברת על שתיהן. שורה שניתנה בטעות במסך ההרשאות הייתה
-- מחזירה ללקוח בודק את כל מה שנסגר כאן, בלי שאיש ידע.
delete from user_permission_grants g
 using profiles p
 where p.id = g.profile_id
   and p.user_kind = 'customer_user'
   and g.permission_key in ('dashboard.customize', 'dashboard.change_range',
                            'dashboard.build_widget', 'dashboard.share_widget',
                            'dashboard.manage_default');


-- ===== 4. ומה שהופך את זה ליותר מכפתור מוסתר ================================
--
-- ‏`dl_write_own` (0040) התירה לכל משתמש מאומת לכתוב את שורת הפריסה של עצמו
-- בלי שום בדיקת מפתח — כלומר הנעילה עד כאן הייתה מסך בלבד, ובקשת PostgREST
-- ישירה הייתה עוברת. הפוליסה שואלת מעכשיו גם את המפתח.
--
-- צוות וקבלן ממשיכים לפתור `true` מברירת המחדל של הרישום, וכל נתיבי הכתיבה
-- ב-`useDashboardLayout` יזומים על ידי המשתמש מתוך מסך ההתאמה — ולכן איש
-- אינו מאבד שמירה שקטה. ‏`dl_select` לא זזה: קריאת הפריסה שלך אינה שינוי,
-- ולקוח חייב להמשיך לקרוא את שלו כדי שיהיה לו מסך.

drop policy dl_write_own on dashboard_layouts;
create policy dl_write_own on dashboard_layouts for all to authenticated
  using      (profile_id is not null and profile_id = (select app.profile_id())
              and (select app.has('dashboard.customize')))
  with check (profile_id is not null and profile_id = (select app.profile_id())
              and (select app.has('dashboard.customize')));
