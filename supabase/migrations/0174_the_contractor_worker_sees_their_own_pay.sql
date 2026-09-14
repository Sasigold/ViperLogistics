-- 0174: עובד קבלן חוזר לראות את השכר שלו בדוח הנוכחות
--
-- ‏0019 וגם 0072 §3 העניקו לתפקיד `contractor_worker` את `attendance.view_own_pay`
-- במפורש (יחד עם `attendance.submit_entry`, כדי שיראה בונוס/שכר בדוח שלו בלי
-- לפתוח לו את פורטל הקבלן). בסביבת הייצור ההרשאה נמצאה כבויה — מישהו כיבה
-- אותה דרך מסך ניהול ההרשאות אחרי שהמיגרציות רצו. זו החזרה המפורשת שלה
-- למצב שהמיגרציות המקוריות קבעו.
insert into role_permissions (role_id, permission_key, allowed)
select r.id, 'attendance.view_own_pay', true
from permission_roles r
where r.key = 'contractor_worker'
on conflict (role_id, permission_key) do update set allowed = true;
