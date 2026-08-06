-- 0011: the catalog — every module, capability and field in the system
--
-- This file is data, not structure. Adding a permission later means adding a
-- row here (or calling app.register_permission from a later migration); the
-- resolver, the RLS helpers and the admin screen all read from these tables,
-- so nothing else has to change.
--
-- `implied_by` is the important column. Every key that carves a slice out of a
-- coarser one names its parent, so granting the parent keeps working exactly
-- as it did before the slice existed. That is what lets this migration land on
-- a live database without anyone losing an ability they had yesterday.

-- ===== modules =====
insert into permission_modules (key, label_he, description_he, icon, sort_order) values
  ('dashboard',   'דשבורד',      'מונים, גרפים והתפלגויות',                  'LayoutDashboard', 10),
  ('calendar',    'לוח שנה',     'תצוגת חודש/שבוע/יום וגרירת תאריכים',        'Calendar',        20),
  ('board',       'לוח עבודה',   'טבלת המשימות, עריכה מהירה ועריכה מרובה',    'ClipboardList',   30),
  ('events',      'אירועים',     'אירועים, אנשי קשר, ספקים ותוספות',          'PartyPopper',     40),
  ('tasks',       'משימות',      'משימות, שיבוץ צוות והאצלה לקבלנים',         'Briefcase',       50),
  ('customers',   'לקוחות',      'לקוחות, קונפיגורציית טופס וספקים',          'Building2',       60),
  ('contractors', 'קבלנים',      'קבלנים, סגל עובדים, תמחור ותשלומים',        'HardHat',         70),
  ('users',       'עובדים',      'משתמשים, תפקידים והרשאות',                  'Users',           80),
  ('settings',    'הגדרות',      'נתוני בסיס, סל מיחזור ויומן פעילות',        'Settings',        90),
  ('portal',      'פורטל קבלן',  'המסך שהקבלן רואה',                          'HardHat',        100),
  ('system',      'מערכת',       'התראות, חיפוש וייצוא',                      'Zap',            110)
on conflict (key) do update set
  label_he = excluded.label_he,
  description_he = excluded.description_he,
  icon = excluded.icon,
  sort_order = excluded.sort_order;

-- ===== permissions =====
-- One statement, so the self-referencing implied_by FK is checked only at the
-- end and a child may sit above its parent in the list without failing.
insert into permission_registry (
  key, module, resource, action, label_he, description_he,
  category, is_dangerous, applies_to, implied_by, default_allowed, sort_order)
select
  v.key, v.module,
  split_part(v.key, '.', 1),
  substr(v.key, strpos(v.key, '.') + 1),
  v.label, v.descr, v.category, v.dangerous,
  string_to_array(v.applies, ',')::user_kind[],
  v.implied_by, v.dflt, v.sort
from (values
  -- ── dashboard ────────────────────────────────────────────────────────────
  ('dashboard.view',        'dashboard', 'צפייה בדשבורד',            'כניסה למסך הראשי',                          'access', false, 'staff,customer_user', null,             false, 10),
  ('dashboard.financial',   'dashboard', 'נתונים כספיים בדשבורד',    'סכומי תמחור ותשלומים בכרטיסים ובגרפים',     'field',  true,  'staff',               null,             false, 20),
  ('dashboard.all_workers', 'dashboard', 'סטטיסטיקות כל העובדים',    'התפלגות משימות לפי עובד — ולא רק שלי',      'field',  false, 'staff',               'dashboard.view', false, 30),
  ('dashboard.export',      'dashboard', 'ייצוא נתוני דשבורד',       null,                                        'action', false, 'staff',               'dashboard.view', false, 40),

  -- ── calendar ─────────────────────────────────────────────────────────────
  ('calendar.view',         'calendar',  'צפייה בלוח שנה',           null,                                        'access', false, 'staff,customer_user', 'events.view',    false, 10),
  ('calendar.drag',         'calendar',  'גרירת אירוע לתאריך אחר',   'שינוי תאריך אירוע בגרירה בלוח השנה',        'action', false, 'staff',               'events.change_date', false, 20),
  ('calendar.save_filters', 'calendar',  'שמירת פילטרים אישיים',     null,                                        'action', false, 'staff,customer_user', 'calendar.view',  false, 30),

  -- ── work board ───────────────────────────────────────────────────────────
  ('board.view',            'board',     'צפייה בלוח עבודה',         null,                                        'access', false, 'staff',               'tasks.view',     false, 10),
  ('board.inline_edit',     'board',     'עריכה מהירה בתוך הטבלה',   'עריכת תאים ישירות בלוח, בלי לפתוח משימה',   'action', false, 'staff',               'tasks.edit',     false, 20),
  ('board.bulk_edit',       'board',     'עריכה מרובה',              'שינוי כמה משימות בבת אחת',                  'action', true,  'staff',               'tasks.edit',     false, 30),
  ('board.export',          'board',     'ייצוא לוח העבודה',         null,                                        'action', false, 'staff',               'tasks.view',     false, 40),
  ('board.columns',         'board',     'שינוי עמודות ותצוגה',      null,                                        'action', false, 'staff',               'board.view',     false, 50),

  -- ── events ───────────────────────────────────────────────────────────────
  ('events.view',           'events', 'צפייה באירועים',              null,                                        'access', false, 'staff,customer_user,contractor_user', null,           false, 10),
  ('events.create',         'events', 'יצירת אירוע',                 null,                                        'crud',   false, 'staff,customer_user', null,            false, 20),
  ('events.edit',           'events', 'עריכת אירוע',                 null,                                        'crud',   false, 'staff,customer_user', null,            false, 30),
  ('events.delete',         'events', 'מחיקת אירוע',                 'מעביר לסל המיחזור',                         'crud',   true,  'staff',               null,            false, 40),
  ('events.restore',        'events', 'שחזור אירוע מסל המיחזור',     null,                                        'action', false, 'staff',               'events.edit',   false, 50),
  ('events.view_deleted',   'events', 'צפייה באירועים שנמחקו',       null,                                        'action', false, 'staff',               'events.delete', false, 55),
  ('events.duplicate',      'events', 'שכפול אירוע',                 null,                                        'action', false, 'staff',               'events.create', false, 60),
  ('events.import',         'events', 'ייבוא אירועים מאקסל',         'יצירה המונית — עוקפת הזנה ידנית',           'action', true,  'staff',               'events.create', false, 70),
  ('events.export',         'events', 'ייצוא אירועים לאקסל',         'כולל פרטי אנשי קשר אם יש הרשאה לראותם',     'action', true,  'staff',               'events.view',   false, 80),
  ('events.change_customer','events', 'שינוי הלקוח של האירוע',       null,                                        'field',  true,  'staff',               'events.edit',   false, 90),
  ('events.change_date',    'events', 'שינוי תאריך האירוע',          null,                                        'field',  false, 'staff,customer_user', 'events.edit',   false, 100),
  ('events.change_status',  'events', 'שינוי סטטוס האירוע',          null,                                        'field',  false, 'staff,customer_user', 'events.edit',   false, 110),
  ('events.manage_contacts','events', 'עריכת איש קשר של האירוע',     null,                                        'field',  false, 'staff,customer_user', 'events.edit',   false, 120),
  ('events.view_contacts',  'events', 'צפייה בפרטי איש קשר',         'שם וטלפון איש הקשר באירוע',                 'field',  true,  'staff,customer_user', 'events.view',   false, 125),
  ('events.manage_suppliers','events','עריכת ספקים באירוע',          null,                                        'field',  false, 'staff,customer_user', 'events.edit',   false, 130),
  ('events.manage_addons',  'events', 'עריכת תוספות',                'ללא חניה, סבלות, איסוף מספק',               'field',  false, 'staff,customer_user', 'events.edit',   false, 140),
  ('events.manage_setup',   'events', 'עריכת סקשני הקמה ופירוק',     'תאריך, שעה, כמות עובדים ואופן ביצוע',       'field',  false, 'staff,customer_user', 'events.edit',   false, 150),
  ('events.edit_notes',     'events', 'עריכת הערות לאירוע',          null,                                        'field',  false, 'staff,customer_user', 'events.edit',   false, 160),

  -- ── tasks ────────────────────────────────────────────────────────────────
  ('tasks.view',            'tasks', 'צפייה במשימות',                null,                                        'access', false, 'staff,customer_user,contractor_user', null,        false, 10),
  ('tasks.create',          'tasks', 'יצירת משימה',                  null,                                        'crud',   false, 'staff',                null,           false, 20),
  ('tasks.edit',            'tasks', 'עריכת משימה',                  'ההרשאה הגסה — ההרשאות שמתחתיה נגזרות ממנה', 'crud',   false, 'staff',                null,           false, 30),
  ('tasks.delete',          'tasks', 'מחיקת משימה',                  'מעביר לסל המיחזור',                         'crud',   true,  'staff',                null,           false, 40),
  ('tasks.restore',         'tasks', 'שחזור משימה מסל המיחזור',      null,                                        'action', false, 'staff',                'tasks.edit',   false, 50),
  ('tasks.view_deleted',    'tasks', 'צפייה במשימות שנמחקו',         null,                                        'action', false, 'staff',                'tasks.delete', false, 55),
  ('tasks.reschedule',      'tasks', 'שינוי תאריך ושעות',            'תאריך, תחילה במחסן, תחילה בשטח, כמות שעות', 'field',  false, 'staff',                'tasks.edit',   false, 70),
  ('tasks.change_status',   'tasks', 'שינוי סטטוס משימה',            null,                                        'field',  false, 'staff',                'tasks.edit',   false, 80),
  ('tasks.change_type',     'tasks', 'שינוי סוג משימה',              null,                                        'field',  false, 'staff',                'tasks.edit',   false, 90),
  ('tasks.change_worker_count','tasks','שינוי כמות עובדים נדרשת',    'התקרה שהקבלן מוגבל אליה',                   'field',  false, 'staff',                'tasks.edit',   false, 100),
  ('tasks.change_execution_method','tasks','שינוי אופן ביצוע',       null,                                        'field',  false, 'staff',                'tasks.edit',   false, 110),
  ('tasks.change_truck',    'tasks', 'שינוי משאית',                  null,                                        'field',  false, 'staff',                'tasks.edit',   false, 120),
  ('tasks.change_location', 'tasks', 'שינוי מיקום המשימה',           null,                                        'field',  false, 'staff',                'tasks.edit',   false, 130),
  ('tasks.edit_notes',      'tasks', 'עריכת הערות למשימה',           null,                                        'field',  false, 'staff',                'tasks.edit',   false, 140),
  ('tasks.assign.worker',   'tasks', 'שיבוץ עובדים',                 'הוספה והסרה של עובדים במשימה',              'action', false, 'staff',                'tasks.edit',   false, 150),
  ('tasks.assign.driver',   'tasks', 'שיבוץ נהגים',                  null,                                        'action', false, 'staff',                'tasks.edit',   false, 160),
  ('tasks.assign.team_lead','tasks', 'שיבוץ ראש צוות',               null,                                        'action', false, 'staff',                'tasks.edit',   false, 170),
  ('tasks.assign.truck',    'tasks', 'שיוך משאית לנהג',              null,                                        'action', false, 'staff',                'tasks.edit',   false, 180),
  ('tasks.assign.self',     'tasks', 'שיבוץ עצמי בלבד',              'העובד משבץ רק את עצמו — בלי הרשאה על אחרים','action', false, 'staff',                null,           false, 190),
  ('tasks.delegate',        'tasks', 'האצלת משימה לקבלן',            null,                                        'field',  true,  'staff',                'tasks.edit',   false, 200),
  ('tasks.bulk_edit',       'tasks', 'עריכה מרובה של משימות',        null,                                        'action', true,  'staff',                'tasks.edit',   false, 210),
  ('tasks.export',          'tasks', 'ייצוא משימות',                 null,                                        'action', false, 'staff',                'tasks.view',   false, 220),

  -- ── customers ────────────────────────────────────────────────────────────
  ('customers.view',        'customers', 'צפייה בלקוחות',            null,                                        'access', false, 'staff',                null,               false, 10),
  ('customers.create',      'customers', 'יצירת לקוח',               null,                                        'crud',   false, 'staff',                null,               false, 20),
  ('customers.edit',        'customers', 'עריכת לקוח',               null,                                        'crud',   false, 'staff',                null,               false, 30),
  ('customers.delete',      'customers', 'מחיקת לקוח',               null,                                        'crud',   true,  'staff',                null,               false, 40),
  ('customers.restore',     'customers', 'שחזור לקוח',               null,                                        'action', false, 'staff',                'customers.edit',   false, 50),
  ('customers.view_contact','customers', 'צפייה בפרטי קשר של לקוח',  'שם, טלפון ואימייל',                         'field',  true,  'staff',                'customers.view',   false, 60),
  ('customers.edit_contact','customers', 'עריכת פרטי קשר של לקוח',   null,                                        'field',  false, 'staff',                'customers.edit',   false, 65),
  ('customers.manage_form_fields','customers','קונפיגורציית טופס',   'אילו שדות מוצגים/מוסתרים/חובה פר-לקוח',     'action', false, 'staff',                'customers.edit',   false, 70),
  ('customers.manage_execution_methods','customers','אופני ביצוע ללקוח',null,                                     'action', false, 'staff',                'customers.edit',   false, 80),
  ('customers.manage_suppliers','customers','ניהול ספקים של הלקוח',  null,                                        'action', false, 'staff',                'customers.edit',   false, 90),
  ('customers.allow_event_creation','customers','הרשאת לקוח ליצור אירועים','פותח ללקוח יצירת אירועים בעצמו',      'action', true,  'staff',                'customers.edit',   false, 100),
  ('customers.change_color','customers', 'שינוי צבע הלקוח',          null,                                        'field',  false, 'staff',                'customers.edit',   false, 110),
  ('customers.export',      'customers', 'ייצוא לקוחות',             null,                                        'action', false, 'staff',                'customers.view',   false, 120),

  -- ── contractors ──────────────────────────────────────────────────────────
  ('contractors.view',      'contractors','צפייה בקבלנים',           null,                                        'access', false, 'staff',                null,                 false, 10),
  ('contractors.create',    'contractors','יצירת קבלן',              null,                                        'crud',   false, 'staff',                null,                 false, 20),
  ('contractors.edit',      'contractors','עריכת קבלן',              null,                                        'crud',   false, 'staff',                null,                 false, 30),
  ('contractors.delete',    'contractors','מחיקת קבלן',              null,                                        'crud',   true,  'staff',                null,                 false, 40),
  ('contractors.restore',   'contractors','שחזור קבלן',              null,                                        'action', false, 'staff',                'contractors.edit',   false, 50),
  ('contractors.manage_workers','contractors','ניהול סגל העובדים',   'הוספה והסרה של עובדי הקבלן',                'action', false, 'staff,contractor_user','contractors.edit',   false, 60),
  ('contractors.view_pricing','contractors','צפייה בתמחור',          'מחיר למשימה וסכומי תשלום',                  'field',  true,  'staff,contractor_user','contractors.view',   false, 70),
  ('contractors.edit_pricing','contractors','עריכת תמחור',           null,                                        'field',  true,  'staff',                'contractors.edit',   false, 80),
  ('contractors.mark_paid', 'contractors','סימון תשלום לקבלן',       null,                                        'action', true,  'staff',                'contractors.edit',   false, 90),
  ('contractors.assign_workers','contractors','שיבוץ עובדי קבלן למשימה',null,                                     'action', false, 'staff,contractor_user','contractors.edit',   false, 100),
  ('contractors.view_contact','contractors','צפייה בפרטי קשר של קבלן',null,                                       'field',  true,  'staff',                'contractors.view',   false, 110),
  ('contractors.export',    'contractors','ייצוא קבלנים',            null,                                        'action', false, 'staff',                'contractors.view',   false, 120),

  -- ── users ────────────────────────────────────────────────────────────────
  ('users.view',            'users', 'צפייה בעובדים',                null,                                        'access', false, 'staff',                null,          false, 10),
  ('users.create',          'users', 'יצירת משתמש',                  null,                                        'crud',   false, 'staff',                null,          false, 20),
  ('users.edit',            'users', 'עריכת משתמש',                  null,                                        'crud',   false, 'staff',                null,          false, 30),
  ('users.delete',          'users', 'מחיקת משתמש',                  null,                                        'crud',   true,  'staff',                null,          false, 40),
  ('users.restore',         'users', 'שחזור משתמש',                  null,                                        'action', false, 'staff',                'users.edit',  false, 50),
  ('users.view_contact',    'users', 'צפייה בטלפון ואימייל',         null,                                        'field',  true,  'staff',                'users.view',  false, 60),
  ('users.manage_staff_roles','users','ניהול תפקידי עובד',           'עובד / נהג / ראש צוות',                     'action', false, 'staff',                'users.edit',  false, 70),
  ('users.assign_roles',    'users', 'שיוך תפקידי הרשאה',            'צירוף משתמש לתפקיד קיים',                   'admin',  true,  'staff',                'users.edit',  false, 80),
  ('users.manage_permissions','users','עריכת הרשאות פר-משתמש',       'חריגות אישיות והרשאות שדה',                 'admin',  true,  'staff',                'users.edit',  false, 90),
  ('users.manage_scopes',   'users', 'עריכת היקף הנתונים',           'אילו לקוחות, קבלנים ותאריכים המשתמש רואה',  'admin',  true,  'staff',                'users.edit',  false, 100),
  ('users.create_login',    'users', 'יצירת חשבון התחברות',          null,                                        'action', true,  'staff',                'users.create',false, 110),
  ('users.reset_password',  'users', 'איפוס סיסמה',                  null,                                        'action', true,  'staff',                'users.edit',  false, 120),
  -- deliberately has no implied_by: granting "edit users" must never be a path
  -- to granting yourself the admin flag.
  ('users.set_admin',       'users', 'הגדרת מנהל מערכת',             'הענקת גישה מלאה — לא נגזר משום הרשאה אחרת', 'admin',  true,  'staff',                null,          false, 130),
  ('users.export',          'users', 'ייצוא עובדים',                 null,                                        'action', false, 'staff',                'users.view',  false, 140),

  -- ── settings ─────────────────────────────────────────────────────────────
  ('settings.view',         'settings','צפייה בהגדרות',              null,                                        'access', false, 'staff',                null,             false, 10),
  ('settings.edit',         'settings','עריכת הגדרות',               'ההרשאה הגסה לנתוני הבסיס',                  'crud',   false, 'staff',                null,             false, 20),
  ('settings.task_types',   'settings','ניהול סוגי משימות',          null,                                        'action', false, 'staff',                'settings.edit',  false, 30),
  ('settings.execution_methods','settings','ניהול אופני ביצוע',      null,                                        'action', false, 'staff',                'settings.edit',  false, 40),
  ('settings.statuses',     'settings','ניהול סטטוסים',              null,                                        'action', false, 'staff',                'settings.edit',  false, 50),
  ('settings.trucks',       'settings','ניהול משאיות',               null,                                        'action', false, 'staff',                'settings.edit',  false, 60),
  ('settings.recycle_bin',  'settings','סל מיחזור',                  'צפייה ושחזור של פריטים שנמחקו',             'action', false, 'staff',                'settings.view',  false, 70),
  ('settings.audit_log',    'settings','יומן פעילות',                'תמונות לפני/אחרי של כל שינוי במערכת',       'action', true,  'staff',                'settings.view',  false, 80),
  ('settings.permissions',  'settings','ניהול תפקידים והרשאות',      'עריכת התפקידים וברירות המחדל של המערכת',    'admin',  true,  'staff',                null,             false, 90),

  -- ── contractor portal ────────────────────────────────────────────────────
  ('portal.view',           'portal','כניסה לפורטל הקבלן',           null,                                        'access', false, 'contractor_user',      null,          true,  10),
  ('portal.assign_workers', 'portal','החלפת עובדים במשימה',          'בחירת עובדים מהסגל, עד כמות שהוגדרה',       'action', false, 'contractor_user',      'portal.view', true,  20),
  ('portal.view_financials','portal','צפייה בנתונים כספיים',         'צפוי, שולם ויתרה',                          'field',  true,  'contractor_user',      'portal.view', true,  30),
  ('portal.manage_workers', 'portal','ניהול סגל העובדים בפורטל',     null,                                        'action', false, 'contractor_user',      'portal.view', true,  40),

  -- ── system ───────────────────────────────────────────────────────────────
  ('notifications.view',    'system','צפייה בהתראות',                null,                                        'access', false, 'staff,customer_user,contractor_user', null, true,  10),
  ('search.global',         'system','חיפוש גלובלי',                 'תוצאות מסוננות ממילא לפי היקף הנתונים',     'access', false, 'staff,customer_user,contractor_user', null, true,  20)
) as v(key, module, label, descr, category, dangerous, applies, implied_by, dflt, sort)
on conflict (key) do update set
  module = excluded.module,
  label_he = excluded.label_he,
  description_he = excluded.description_he,
  category = excluded.category,
  is_dangerous = excluded.is_dangerous,
  applies_to = excluded.applies_to,
  implied_by = excluded.implied_by,
  default_allowed = excluded.default_allowed,
  sort_order = excluded.sort_order,
  is_active = true;

-- ===== fields =====
-- `edit_permission_key` is what turns a column into a capability: changing that
-- column requires that key rather than the generic per-field edit right. Columns
-- without one fall back to field_permissions, which defaults to editable.
insert into field_registry (
  entity, field_key, label_he, module, table_name, column_name,
  is_sensitive, default_can_view, default_can_edit, edit_permission_key, sort_order)
select v.entity, v.field, v.label, v.module, v.tbl, coalesce(v.col, v.field),
       v.sensitive, v.dview, v.dedit, v.perm, v.sort
from (values
  -- event ─────────────────────────────────────────────────────────────────
  ('event','end_client_name','לקוח סופי',      'events','events',null,false,true,true,null,                     10),
  ('event','event_number',   'מספר אירוע',     'events','events',null,false,true,true,null,                     20),
  ('event','event_date',     'תאריך אירוע',    'events','events',null,false,true,true,'events.change_date',     30),
  ('event','customer_id',    'לקוח',           'events','events',null,false,true,true,'events.change_customer', 40),
  ('event','status_id',      'סטטוס',          'events','events',null,false,true,true,'events.change_status',   50),
  ('event','location_text',  'מיקום',          'events','events',null,false,true,true,null,                     60),
  ('event','location_notes', 'הערות מיקום',    'events','events',null,false,true,true,null,                     70),
  ('event','volume_m',       'נפח (קוב)',      'events','events',null,false,true,true,null,                     80),
  ('event','truck_count',    'כמות משאיות',    'events','events',null,false,true,true,null,                     90),
  ('event','notes',          'הערות',          'events','events',null,false,true,true,'events.edit_notes',     100),
  ('event','no_parking',     'ללא חניה',       'events','events',null,false,true,true,'events.manage_addons',  110),
  ('event','porterage',      'סבלות',          'events','events',null,false,true,true,'events.manage_addons',  120),
  ('event','supplier_pickup','איסוף מספק',     'events','events',null,false,true,true,'events.manage_addons',  130),
  ('event','contact_name',   'שם איש קשר',     'events','event_contacts',null,true,true,true,'events.manage_contacts',140),
  ('event','contact_phone',  'טלפון איש קשר',  'events','event_contacts',null,true,true,true,'events.manage_contacts',150),

  -- task ──────────────────────────────────────────────────────────────────
  ('task','task_type_id',    'סוג משימה',      'tasks','tasks',null,false,true,true,'tasks.change_type',            10),
  ('task','title',           'כותרת',          'tasks','tasks',null,false,true,true,null,                           20),
  ('task','task_date',       'תאריך',          'tasks','tasks',null,false,true,true,'tasks.reschedule',             30),
  ('task','warehouse_start_time','תחילה במחסן','tasks','tasks',null,false,true,true,'tasks.reschedule',             40),
  ('task','onsite_start_time','תחילה בשטח',    'tasks','tasks',null,false,true,true,'tasks.reschedule',             50),
  ('task','hours_count',     'כמות שעות',      'tasks','tasks',null,false,true,true,'tasks.reschedule',             60),
  ('task','worker_count',    'כמות עובדים',    'tasks','tasks',null,false,true,true,'tasks.change_worker_count',    70),
  ('task','execution_method_id','אופן ביצוע',  'tasks','tasks',null,false,true,true,'tasks.change_execution_method',80),
  ('task','truck_id',        'משאית',          'tasks','tasks',null,false,true,true,'tasks.change_truck',           90),
  ('task','truck_free_text', 'משאית (מלל)',    'tasks','tasks',null,false,true,true,'tasks.change_truck',          100),
  ('task','status_id',       'סטטוס',          'tasks','tasks',null,false,true,true,'tasks.change_status',         110),
  ('task','contractor_id',   'קבלן',           'tasks','tasks',null,false,true,true,'tasks.delegate',              120),
  ('task','location_text',   'מיקום',          'tasks','tasks',null,false,true,true,'tasks.change_location',       130),
  ('task','notes',           'הערות',          'tasks','tasks',null,false,true,true,'tasks.edit_notes',            140),
  ('task','event_id',        'אירוע משויך',    'tasks','tasks',null,false,true,true,null,                          150),

  -- customer ──────────────────────────────────────────────────────────────
  ('customer','name',            'שם הלקוח',    'customers','customers',null,false,true,true,null,                            10),
  ('customer','color',           'צבע',         'customers','customers',null,false,true,true,'customers.change_color',        20),
  ('customer','can_create_events','רשאי ליצור אירועים','customers','customers',null,false,true,true,'customers.allow_event_creation',30),
  ('customer','contact_name',    'איש קשר',     'customers','customers',null,true,true,true,'customers.edit_contact',         40),
  ('customer','contact_phone',   'טלפון',       'customers','customers',null,true,true,true,'customers.edit_contact',         50),
  ('customer','contact_email',   'אימייל',      'customers','customers',null,true,true,true,'customers.edit_contact',         60),
  ('customer','notes',           'הערות',       'customers','customers',null,false,true,true,null,                            70),

  -- contractor ────────────────────────────────────────────────────────────
  ('contractor','name',             'שם הקבלן',      'contractors','contractors',null,false,true,true,null,                        10),
  ('contractor','contact_name',     'איש קשר',       'contractors','contractors',null,true,true,true,'contractors.view_contact',   20),
  ('contractor','phone',            'טלפון',         'contractors','contractors',null,true,true,true,'contractors.view_contact',   30),
  ('contractor','email',            'אימייל',        'contractors','contractors',null,true,true,true,'contractors.view_contact',   40),
  ('contractor','default_task_price','מחיר ברירת מחדל','contractors','contractors',null,true,true,true,'contractors.edit_pricing', 50),
  ('contractor','notes',            'הערות',         'contractors','contractors',null,false,true,true,null,                        60),

  -- profile ───────────────────────────────────────────────────────────────
  ('profile','full_name',    'שם מלא',          'users','profiles',null,false,true,true,null,                 10),
  ('profile','phone',        'טלפון',           'users','profiles',null,true,true,true,'users.view_contact',   20),
  ('profile','email',        'אימייל',          'users','profiles',null,true,true,true,'users.view_contact',   30),
  ('profile','user_kind',    'סוג משתמש',       'users','profiles',null,false,true,true,null,                  40),
  ('profile','is_admin',     'מנהל מערכת',      'users','profiles',null,true,true,true,'users.set_admin',      50),
  ('profile','is_active',    'פעיל',            'users','profiles',null,false,true,true,null,                  60),
  ('profile','customer_id',  'שיוך ללקוח',      'users','profiles',null,false,true,true,null,                  70),
  ('profile','contractor_id','שיוך לקבלן',      'users','profiles',null,false,true,true,null,                  80),
  ('profile','notes',        'הערות',           'users','profiles',null,false,true,true,null,                  90),

  -- contractor terms (money) ──────────────────────────────────────────────
  ('task_terms','price',      'מחיר לקבלן',     'contractors','task_contractor_terms',null,true,true,true,'contractors.edit_pricing',10),
  ('task_terms','paid_at',    'תאריך תשלום',    'contractors','task_contractor_terms',null,true,true,true,'contractors.mark_paid',   20),
  ('task_terms','paid_amount','סכום ששולם',     'contractors','task_contractor_terms',null,true,true,true,'contractors.mark_paid',   30),
  ('task_terms','notes',      'הערות תמחור',    'contractors','task_contractor_terms',null,true,true,true,'contractors.edit_pricing',40)
) as v(entity, field, label, module, tbl, col, sensitive, dview, dedit, perm, sort)
on conflict (entity, field_key) do update set
  label_he = excluded.label_he,
  module = excluded.module,
  table_name = excluded.table_name,
  column_name = excluded.column_name,
  is_sensitive = excluded.is_sensitive,
  default_can_view = excluded.default_can_view,
  default_can_edit = excluded.default_can_edit,
  edit_permission_key = excluded.edit_permission_key,
  sort_order = excluded.sort_order;

-- ===== carry the old model forward =====
-- Done before the system roles are seeded so that nothing depends on ordering,
-- and before the legacy tables are dropped so nothing is lost. Keys that no
-- longer exist in the registry are simply skipped.
insert into kind_permission_defaults (user_kind, permission_key, allowed)
select pd.user_kind, pd.resource || '.' || pd.action::text, pd.allowed
from permission_defaults pd
where exists (select 1 from permission_registry r
              where r.key = pd.resource || '.' || pd.action::text)
on conflict (user_kind, permission_key) do update set allowed = excluded.allowed;

insert into user_permission_grants (profile_id, permission_key, allowed)
select up.profile_id, up.resource || '.' || up.action::text, up.allowed
from user_permissions up
where exists (select 1 from permission_registry r
              where r.key = up.resource || '.' || up.action::text)
  and exists (select 1 from profiles p where p.id = up.profile_id)
on conflict (profile_id, permission_key) do update set allowed = excluded.allowed;

-- Baseline for kinds the old seed never mentioned.
insert into kind_permission_defaults (user_kind, permission_key, allowed) values
  ('contractor_user', 'portal.view', true),
  ('contractor_user', 'portal.assign_workers', true),
  ('contractor_user', 'portal.view_financials', true),
  ('contractor_user', 'portal.manage_workers', true),
  ('contractor_user', 'contractors.manage_workers', true),
  ('contractor_user', 'contractors.view_pricing', true),
  ('contractor_user', 'contractors.assign_workers', true),
  ('customer_user',   'calendar.view', true),
  ('customer_user',   'events.view_contacts', true),
  ('customer_user',   'events.manage_contacts', true)
on conflict (user_kind, permission_key) do nothing;

-- The old model is now fully represented in the new tables.
drop trigger permission_defaults_audit on permission_defaults;
drop trigger user_permissions_audit on user_permissions;
drop policy pd_admin on permission_defaults;
drop policy up_admin on user_permissions;
drop table permission_defaults;
drop table user_permissions;

-- ===== system roles =====
insert into permission_roles (key, name_he, description_he, user_kind, is_system, sort_order) values
  ('ops_manager',      'מנהל תפעול',      'כל התפעול והנתונים, למעט ניהול ההרשאות עצמן',        'staff',            true, 10),
  ('dispatcher',       'רכז שיבוצים',     'בונה ומשבץ אירועים ומשימות מקצה לקצה',                'staff',            true, 20),
  ('scheduler',        'משבץ',            'משבץ עובדים ונהגים בלבד — לא משנה זמנים ולא מאציל',   'staff',            true, 30),
  ('team_lead',        'ראש צוות',        'רואה את המשימות שלו ומעדכן סטטוס',                    'staff',            true, 40),
  ('driver',           'נהג',             'רואה את המשימות שלו ומעדכן סטטוס',                    'staff',            true, 50),
  ('worker',           'עובד',            'רואה רק את המשימות ששובץ אליהן',                      'staff',            true, 60),
  ('finance',          'כספים',           'תמחור קבלנים, תשלומים ונתונים כספיים',                'staff',            true, 70),
  ('hr',               'משאבי אנוש',      'ניהול עובדים וחשבונות התחברות',                       'staff',            true, 80),
  ('viewer',           'צופה',            'צפייה בלבד בכל המודולים התפעוליים',                   'staff',            true, 90),
  ('customer_manager', 'מנהל אצל הלקוח',  'יוצר ועורך את האירועים של הלקוח שלו',                 'customer_user',    true, 100),
  ('customer_viewer',  'צופה אצל הלקוח',  'צפייה בלבד באירועים של הלקוח שלו',                    'customer_user',    true, 110),
  ('contractor_manager','מנהל קבלן',      'פורטל הקבלן — משימות, סגל עובדים ונתונים כספיים',     'contractor_user',  true, 120)
on conflict (key) do update set
  name_he = excluded.name_he,
  description_he = excluded.description_he,
  sort_order = excluded.sort_order;

select app.set_role_permissions('ops_manager', array[
  'dashboard.view','dashboard.financial','dashboard.all_workers','dashboard.export',
  'calendar.view','calendar.drag','calendar.save_filters',
  'board.view','board.inline_edit','board.bulk_edit','board.export','board.columns',
  'events.view','events.create','events.edit','events.delete','events.restore',
  'events.view_deleted','events.duplicate','events.import','events.export',
  'events.change_customer','events.change_date','events.change_status',
  'events.manage_contacts','events.view_contacts','events.manage_suppliers',
  'events.manage_addons','events.manage_setup','events.edit_notes',
  'tasks.view','tasks.create','tasks.edit','tasks.delete','tasks.restore','tasks.view_deleted',
  'tasks.reschedule','tasks.change_status','tasks.change_type','tasks.change_worker_count',
  'tasks.change_execution_method','tasks.change_truck','tasks.change_location','tasks.edit_notes',
  'tasks.assign.worker','tasks.assign.driver','tasks.assign.team_lead','tasks.assign.truck',
  'tasks.delegate','tasks.bulk_edit','tasks.export',
  'customers.view','customers.create','customers.edit','customers.delete','customers.restore',
  'customers.view_contact','customers.edit_contact','customers.manage_form_fields',
  'customers.manage_execution_methods','customers.manage_suppliers',
  'customers.allow_event_creation','customers.change_color','customers.export',
  'contractors.view','contractors.create','contractors.edit','contractors.delete',
  'contractors.restore','contractors.manage_workers','contractors.view_pricing',
  'contractors.edit_pricing','contractors.mark_paid','contractors.assign_workers',
  'contractors.view_contact','contractors.export',
  'users.view','users.create','users.edit','users.view_contact','users.manage_staff_roles',
  'settings.view','settings.edit','settings.task_types','settings.execution_methods',
  'settings.statuses','settings.trucks','settings.recycle_bin','settings.audit_log',
  'notifications.view','search.global'],
  -- "everything except managing permissions" is only true if the users module
  -- is closed — otherwise users.edit would imply users.manage_permissions.
  array['users']);

select app.set_role_permissions('dispatcher', array[
  'dashboard.view','dashboard.all_workers',
  'calendar.view','calendar.drag','calendar.save_filters',
  'board.view','board.inline_edit','board.bulk_edit','board.export','board.columns',
  'events.view','events.create','events.edit','events.duplicate','events.export',
  'events.change_date','events.change_status','events.manage_contacts','events.view_contacts',
  'events.manage_suppliers','events.manage_addons','events.manage_setup','events.edit_notes',
  'tasks.view','tasks.create','tasks.edit','tasks.reschedule','tasks.change_status',
  'tasks.change_type','tasks.change_worker_count','tasks.change_execution_method',
  'tasks.change_truck','tasks.change_location','tasks.edit_notes',
  'tasks.assign.worker','tasks.assign.driver','tasks.assign.team_lead','tasks.assign.truck',
  'tasks.delegate','tasks.bulk_edit','tasks.export',
  'customers.view','customers.view_contact',
  'contractors.view','contractors.assign_workers',
  'users.view','notifications.view','search.global'],
  array['tasks','events','users']);

-- The role that motivated the whole design: staffs tasks and nothing else.
-- Note the absence of tasks.edit — the task row itself stays read-only for
-- them; their entire write surface is the assignment table.
select app.set_role_permissions('scheduler', array[
  'dashboard.view','calendar.view','board.view',
  'events.view','tasks.view',
  'tasks.assign.worker','tasks.assign.driver','tasks.assign.team_lead','tasks.assign.truck',
  'users.view','notifications.view','search.global'],
  array['tasks','board']);

select app.set_role_permissions('team_lead', array[
  'dashboard.view','calendar.view','board.view',
  'events.view','tasks.view','tasks.edit','tasks.change_status','tasks.edit_notes',
  'notifications.view','search.global'],
  array['tasks','board','events']);

select app.set_role_permissions('driver', array[
  'calendar.view','board.view','tasks.view','tasks.edit','tasks.change_status',
  'notifications.view','search.global'],
  array['tasks','board','events']);

select app.set_role_permissions('worker', array[
  'calendar.view','board.view','tasks.view','notifications.view','search.global'],
  array['tasks','board','events']);

select app.set_role_permissions('finance', array[
  'dashboard.view','dashboard.financial','dashboard.export',
  'board.view','board.export','events.view','events.export','tasks.view','tasks.export',
  'customers.view','customers.export',
  'contractors.view','contractors.view_pricing','contractors.edit_pricing',
  'contractors.mark_paid','contractors.export','contractors.view_contact',
  'notifications.view','search.global']);

select app.set_role_permissions('hr', array[
  'dashboard.view','users.view','users.create','users.edit','users.delete','users.restore',
  'users.view_contact','users.manage_staff_roles','users.create_login','users.reset_password',
  'users.export','notifications.view','search.global'],
  -- HR manages people, not the permission system: closing the module keeps
  -- users.edit from implying users.manage_permissions or users.set_admin.
  array['users']);

select app.set_role_permissions('viewer', array[
  'dashboard.view','calendar.view','board.view','events.view','events.view_contacts',
  'tasks.view','customers.view','contractors.view','users.view',
  'notifications.view','search.global']);

select app.set_role_permissions('customer_manager', array[
  'events.view','events.create','events.edit','events.change_date','events.change_status',
  'events.manage_contacts','events.view_contacts','events.manage_suppliers',
  'events.manage_addons','events.manage_setup','events.edit_notes',
  'calendar.view','calendar.save_filters','tasks.view','notifications.view','search.global'],
  -- A customer's own manager must never inherit events.change_customer and
  -- move an event onto another customer's books.
  array['events','tasks']);

select app.set_role_permissions('customer_viewer', array[
  'events.view','events.view_contacts','calendar.view','tasks.view',
  'notifications.view','search.global']);

select app.set_role_permissions('contractor_manager', array[
  'portal.view','portal.assign_workers','portal.view_financials','portal.manage_workers',
  'tasks.view','events.view','contractors.manage_workers','contractors.view_pricing',
  'contractors.assign_workers','notifications.view','search.global']);

-- ===== example data scopes attached to the narrow roles =====
-- A worker or driver has no business seeing the whole board; 'own' limits them
-- to tasks they are assigned to or created. Admins can widen this per person.
insert into permission_scopes (role_id, resource, scope_type)
select r.id, res.resource, 'own'::permission_scope_type
from permission_roles r
cross join (values ('tasks'), ('events')) as res(resource)
where r.key in ('worker', 'driver')
on conflict do nothing;
