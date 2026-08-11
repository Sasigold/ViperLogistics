-- ===========================================================================
-- 0055 — אינדקסים על מפתחות זרים שנותרו בלי אינדקס
-- ===========================================================================
--
-- המשך ישיר של 0028: כל אינדקס כאן יושב על מפתח זר שמסתמכים עליו או
-- בשאילתות מסך או במחיקות בצד האב. שני סוגים:
--
-- 1. עמודות nullable שמצביעות על פרופיל/משתמש (actor, edited_by, shared_by):
--    כל מחיקת פרופיל סורקת את הטבלה כדי לממש את ה-on delete. אינדקס חלקי
--    (where not null) מכסה בדיוק את השורות שהמחיקה צריכה למצוא.
--
-- 2. הצד ההפוך של מפתח ראשי מורכב: ה-PK מכסה חיפוש לפי העמודה הראשונה
--    בלבד, וחיפוש לפי השנייה (permission_key, execution_method_id,
--    field_key) הוא סריקה מלאה.
--
-- permission_registry.implied_by ראוי להערה נפרדת: ה-CTE הרקורסיבי של
-- app.has() מצטרף דרך המפתח הראשי (r.key = c.key) ולא סורק את implied_by,
-- כך שהאינדקס אינו מאיץ את הכרעת ההרשאות עצמה. הערך שלו הוא ה-FK ההפוך —
-- implied_by מוגדר on delete set null, וכל מחיקה או עדכון מפתח ברישום
-- סורקים את הטבלה כולה בלעדיו.

create index if not exists permission_registry_implied_by_idx
  on permission_registry (implied_by) where implied_by is not null;

create index if not exists event_activity_actor_idx
  on event_activity (actor_profile_id) where actor_profile_id is not null;

create index if not exists dashboard_widgets_shared_by_idx
  on dashboard_widgets (shared_by) where shared_by is not null;

create index if not exists attendance_entries_edited_by_idx
  on attendance_entries (edited_by) where edited_by is not null;

create index if not exists attendance_entries_created_by_idx
  on attendance_entries (created_by) where created_by is not null;

create index if not exists attendance_entry_bonus_created_by_idx
  on attendance_entry_bonus (created_by) where created_by is not null;

create index if not exists role_permissions_key_idx
  on role_permissions (permission_key);

create index if not exists customer_execution_methods_method_idx
  on customer_execution_methods (execution_method_id);

create index if not exists user_form_fields_key_idx
  on user_form_fields (field_key);
