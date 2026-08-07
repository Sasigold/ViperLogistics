-- 0028: אינדקסים חסרים, ושאריות של אופטימיזציה שכבר הוחלה ברובה
--
-- 0013 מסביר בכותרת שלו את הכלל: קריאה לפונקציה בתוך פוליסה צריכה להיות
-- עטופה ב-(select ...) כדי ש-Postgres יריץ אותה כ-InitPlan פעם אחת לשאילתה
-- במקום פעם לכל שורה שנסרקת. הכלל אכן הוחל — ובמקומות שהכי חשובים הוא הוחל
-- במלואו: tasks_select, events_select, ae_select ו-audit_read כולן עטופות
-- לגמרי. מה שנשאר הוא שאריות.
--
-- הסעיף הראשון כאן מטפל בשאריות שיש להן משמעות, והשאר נשאר כפי שהוא במכוון:
-- רוב הקריאות הלא-עטופות שנותרו יושבות על פוליסות כתיבה, שנבדקות פר-שורה
-- מושפעת — כלומר בדרך כלל שורה אחת — או על טבלאות ניהול קטנות. שכתוב פוליסת
-- אבטחה הוא הזדמנות לטעות, ואין סיבה לקחת אותה בלי רווח.

-- ===== 1. הקריאות שנשארו על נתיב קריאה של טבלה שגדלה ================
--
-- ארבע הטבלאות האלה גדלות עם העסק: שיבוץ לכל משימה, עובד קבלן לכל שיבוץ,
-- ספק לכל לקוח. app.has_permission נשארה שם לא עטופה, ולכן היא רצה מחדש
-- לכל שורה שנסרקת. הסמנטיקה זהה לחלוטין — רק תוכנית הריצה משתנה.

drop policy if exists ta_select on task_assignments;
create policy ta_select on task_assignments for select to authenticated using (
  (select app.is_admin())
  or ((select app.user_kind()) = 'staff' and (select app.has_permission('tasks','view')))
  or profile_id = (select app.profile_id()));

drop policy if exists tcw_select on task_contractor_workers;
create policy tcw_select on task_contractor_workers for select to authenticated using (
  (select app.is_admin())
  or ((select app.user_kind()) = 'staff'
      and ((select app.has_permission('tasks','view'))
           or (select app.has_permission('contractors','view'))))
  or exists (select 1 from tasks t where t.id = task_id
             and t.contractor_id = (select app.contractor_id()) and t.deleted_at is null));

drop policy if exists suppliers_select on suppliers;
create policy suppliers_select on suppliers for select to authenticated using (
  (select app.is_admin())
  or (deleted_at is null and (
    ((select app.user_kind()) = 'staff' and
       ((select app.has_permission('customers','view'))
        or (select app.has_permission('events','view'))))
    or customer_id = (select app.customer_id())
  )));

drop policy if exists cw_select on contractor_workers;
create policy cw_select on contractor_workers for select to authenticated using (
  (select app.is_admin())
  or (deleted_at is null and (
    ((select app.user_kind()) = 'staff' and (select app.has_permission('contractors','view')))
    or contractor_id = (select app.contractor_id())
  )));

-- role_permissions נקראת בכל מסך הרשאות והיא מכפלה של מפתחות בתפקידים, ולכן
-- היא היחידה מטבלאות הניהול ששווה את השכתוב. app.has מריצה CTE רקורסיבי על
-- שרשרת implied_by, וזה יקר לחזור עליו פר-שורה.
drop policy if exists role_permissions_read on role_permissions;
create policy role_permissions_read on role_permissions for select to authenticated
  using ((select app.is_admin())
         or (select app.has('users.view'))
         or (select app.has('settings.permissions')));

-- ===== 2. אינדקסים על עמודות שמשמשות בפרדיקטים ובצירופים ============
--
-- כל אחת מהן היא מפתח זר בלי אינדקס, וכולן מופיעות או בפרדיקטים של
-- permission_scopes בתוך פוליסות ה-SELECT של events/tasks, או בסינון רגיל
-- במסכים (סטטוס, משאית, אופן ביצוע). בלי scope מוגדר הענף מתקצר לפני
-- שנוגעים בעמודה, ולכן זה לא נצפה עד שמישהו מגדיר הגבלת נתונים — ואז זה
-- סריקה מלאה על הטבלה הגדולה בסכמה.
--
-- החלקיות (where deleted_at is null) עוקבת אחרי הדפוס של שאר האינדקסים
-- בסכמה: היא מתאימה בדיוק לצורת הפרדיקט שהפוליסות והשאילתות משתמשות בו.

create index if not exists events_status_idx on events (status_id) where deleted_at is null;
create index if not exists events_created_by_idx on events (created_by) where deleted_at is null;

create index if not exists tasks_execution_method_idx on tasks (execution_method_id) where deleted_at is null;
create index if not exists tasks_truck_idx on tasks (truck_id) where deleted_at is null;
create index if not exists tasks_created_by_idx on tasks (created_by) where deleted_at is null;
create index if not exists tasks_warehouse_idx on tasks (warehouse_id) where deleted_at is null;

-- אלה אינם נתיבי סריקה אלא מפתחות זרים בלי אינדקס: מחיקה או עדכון של השורה
-- שאליה הם מצביעים מחייבת סריקה מלאה כדי לאמת את האילוץ.
create index if not exists task_assignments_truck_idx on task_assignments (truck_id);
create index if not exists customers_warehouse_idx on customers (warehouse_id) where deleted_at is null;
create index if not exists event_suppliers_supplier_idx on event_suppliers (supplier_id);
create index if not exists customer_pricing_rules_task_type_idx on customer_pricing_rules (task_type_id);
