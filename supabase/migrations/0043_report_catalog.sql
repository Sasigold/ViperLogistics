-- 0043: קטלוג הדוחות — מה מותר לבנות ווידג׳ט מתוכו
--
-- **הקובץ הזה הוא גבול האבטחה של בונה הווידג׳טים.** המנוע (0044) אינו יודע דבר
-- על העולם מלבד מה שכתוב כאן: כל מקור, מדד, פילוח ותנאי סינון שהמשתמש יכול
-- לבקש הוא שורה באחת משלוש הטבלאות האלה, ובקשה שאין לה שורה נדחית.
--
-- ===== למה טבלה, ולמה לא רק טבלה ==========================================
--
-- הפיצול הוא על ציר אחד: **האם השורה פולטת ביטוי SQL, או רק מזהה ומטא-דאטה?**
--
--   • כאן, בטבלאות — ~40 שדות ו~20 מדדים. כל שורה נושאת **שם עמודה חשוף בלבד**,
--     שנפלט דרך `%I`, ועוד מטא-דאטה (יחידה, מפתח הרשאה, אגרגטים מותרים).
--     **אף שורה כאן אינה מכילה קטע SQL.**
--   • במנוע, ב-CASE קשיח — ארבעת המקורות ועשר צורות ה-join. אלה החלקים שפולטים
--     ביטויים (`left join lateral unnest(...)`, `a.status = 'approved'`), והם
--     בדיוק צורת `soft_delete` מ-0014: `case … else null` ואז `raise`.
--
-- למה לא CASE טהור: הקטלוג חייב להיות **מוגש ללקוח**, כדי שהבונה יציג תוויות
-- ויסנן פילוחים לפי המדד. CASE אי אפשר להגיש, ומראה בצד הלקוח סוחפת —
-- `PRICING_VARS` כבר הוכיחה את זה.
--
-- ===== למה אין כאן מדיניות כתיבה, גם לא לאדמין =============================
--
-- `field_registry` (0010) פתוחה לכתיבה ל-`app.is_admin()`, וזה בטוח שם: שורת
-- `field_registry` יכולה רק **לצמצם** גישה. שורת `report_fields` **מרחיבה** את
-- משטח ה-SQL — היא אומרת "מותר לקבץ לפי העמודה הזו". לכן:
--
--   **הכותב היחיד של הטבלאות האלה הוא תפקיד המיגרציה.**
--
-- זו סטייה מכוונת מהתקדים, והיא מה שהופך "אדמין שנפרץ" ל"אדמין שנפרץ" ולא
-- ל"הרצת SQL שרירותי".
--
-- ===== מה מחזיק את הטבלאות ואת ה-CASE ביחד =================================
--
-- שניהם יכולים לסחוף: שורה עם `join_key` שה-CASE אינו מכיר היא כשל בזמן ריצה.
-- לכן `06_report_builder.sql` מריצה בדיקת עשן שעוברת על **כל מדד × כל פילוח
-- מותר** ומוודאת שאין זריקה. סחיפה הופכת לכשל CI ולא לכשל ב-3 לפנות בוקר.

-- ===== 1. מקורות ===========================================================

create table report_sources (
  key           text primary key,
  label_he      text not null,
  -- כדי ש"ספירה" תיקרא "36 משימות" ולא "36"
  row_noun_he   text not null,
  -- כינוי הטבלה הראשית. נפלט דרך %I, ומשמש גם את עמודת התאריך.
  alias         text not null,
  date_col      text not null,
  perm_key      text references permission_registry(key),
  -- 'rls'     — ה-RLS של הקורא מצמצמת את השורות, וזה כל מנגנון ההיקף
  -- 'company' — הנתון הוא של כל החברה ואינו ניתן לצמצום (שכר). מדדים כאלה
  --             מסומנים requires_unscoped, ראה report_measures.
  scope_kind    text not null default 'rls' check (scope_kind in ('rls', 'company')),
  -- מוגש verbatim ב-meta של כל תוצאה, כמו 'scope':'approved_only' של
  -- payroll_summary. הכרטיס תמיד מצהיר מה נספר.
  scope_note_he text,
  sort_order    int not null default 100,
  -- השער: ה-CASE של ה-FROM במנוע מכיר בדיוק את הארבעה האלה. הוספת מקור היא
  -- מיגרציה שעורכת גם את ה-CASE, באותו commit.
  constraint report_sources_known
    check (key in ('tasks', 'events', 'attendance', 'payroll'))
);

-- ===== 2. מדדים ============================================================

create table report_measures (
  key          text primary key,
  source_key   text not null references report_sources(key) on delete cascade,
  label_he     text not null,
  hint_he      text,
  -- 'sql'    — אגרגט על עמודה של המקור, אולי דרך join
  -- 'engine' — מנותב ל-app.payroll_* / app.margin_* הקיימות. **לא נפלט SQL
  --            גנרי בכלל.** זה מה שמקיים את הכלל של 0039: מימוש שני מתיישן.
  impl         text not null check (impl in ('sql', 'engine')),
  join_key     text,          -- נפתר ב-CASE; לא מוכר → raise
  col          text,          -- שם עמודה חשוף, נפלט דרך %I
  col_type     text check (col_type in ('uuid','text','numeric','int','date','bool')),
  -- שתי צורות ביטוי בלבד, כי מדד אחד אינו agg(col):
  --   'plain'         → agg(col)
  --   'coalesce_paid' → sum(coalesce(paid_amount, price)) filter (paid_at is not null)
  expr_kind    text not null default 'plain'
               check (expr_kind in ('plain', 'coalesce_paid')),
  allowed_aggs text[] not null default '{sum}',
  default_agg  text not null default 'sum',
  -- מלכודת: task_contractor_terms.price ו-task_pricing.price הם not null,
  -- ולכן SUM לבדו אינו מבחין בין "לא סוכם מחיר" ל-"סוכם אפס". היעדר השורה
  -- הוא האות היחיד, והמנוע תמיד מחזיר ספירת נוכחות על העמודה הזו.
  presence_col text,
  unit         text not null default 'count'
               check (unit in ('count','money','hours','volume','percent')),
  -- perm_key הוא מפתח הדשבורד. perm_all הוא האיחוד שכולל גם את מפתח ה-RLS
  -- שמכניס את השורות בפועל — בלעדיו מתקבל 0 בטוח במקום null. הענף
  -- cost.contractor ב-0041 סובל מזה בדיוק: הוא נשען על dashboard.contractor_cost
  -- בזמן שהשורות מגיעות דרך tct_select שדורשת contractors.view_pricing.
  perm_key     text references permission_registry(key),
  perm_all     text[],
  -- שער ברמת עמודה. app.has לבדו הוא עקיפה: אפשר להחזיק pricing.revenue
  -- ולהישלל ב-field_permissions על ('task_pricing','price').
  field_entity text,
  field_key    text,
  -- עלות שכר היא של כל החברה. קורא עם היקף נתונים מצומצם היה מקבל
  -- "ההכנסות שלי פחות השכר של כולם" — מספר שגוי בביטחון.
  requires_unscoped boolean not null default false,
  -- הקצאה, לא join. הכרטיס נושא "משוער" והמנוע מחזיר allocated/unallocated.
  is_estimate  boolean not null default false,
  -- פילוח לפי משאית מכפיל שורות (unnest). סכום ברמת המשימה היה נספר פעמיים.
  fanout_safe  boolean not null default true,
  -- null = כל שדה קביץ של המקור. לא-null = רשימה סגורה, ו-'__none__' הוא
  -- הסימן ל"מותר להציג בלי פילוח בכלל".
  allowed_dims text[],
  sort_order   int not null default 100,
  constraint report_measures_default_agg check (default_agg = any (allowed_aggs)),
  constraint report_measures_sql_shape
    check (impl <> 'sql' or (col is not null and col_type is not null)
                          or expr_kind <> 'plain')
);

-- ===== 3. שדות (פילוח וסינון) ==============================================

create table report_fields (
  key          text primary key,
  source_key   text not null references report_sources(key) on delete cascade,
  label_he     text not null,
  kind         text not null check (kind in ('cat', 'time', 'num', 'bool')),
  join_key     text,          -- נפתר ב-CASE; לא מוכר → raise
  col          text not null, -- לפי מה מקבצים / מסננים
  col_type     text not null check (col_type in ('uuid','text','numeric','int','date','bool')),
  label_col    text,          -- מה מציגים, כשהקיבוץ הוא על מפתח
  color_col    text,          -- customers.color, statuses.color
  fans_out     boolean not null default false,
  -- nullable מניע גילוי נאות ב-UI בלבד. הנפילה עצמה נפתרת מבנית: **כל join
  -- של פילוח הוא LEFT, תמיד**, והתווית עוברת coalesce ל-null_label_he. כך
  -- המחלקה של "inner join השמיט בשקט את השורות בלי סטטוס" נעלמת, במקום
  -- להיות תלויה בבוליאני שמישהו הציב נכון.
  nullable     boolean not null default false,
  null_label_he text,
  is_estimate  boolean not null default false,
  can_group    boolean not null default true,
  can_filter   boolean not null default true,
  allowed_ops  text[] not null default '{}',
  perm_key     text references permission_registry(key),
  field_entity text,
  field_key    text,
  sort_order   int not null default 100
);

create index report_measures_source_idx on report_measures (source_key, sort_order);
create index report_fields_source_idx   on report_fields   (source_key, sort_order);

alter table report_sources  enable row level security;
alter table report_measures enable row level security;
alter table report_fields   enable row level security;

-- קריא לכל מי שמחובר: הבונה צריך את התוויות, וידיעה ששדה קיים אינה מעניקה
-- דבר — כל אחד מהם מגודר בנפרד בזמן ריצה, ב-app.report_run.
create policy rs_read on report_sources  for select to authenticated using (true);
create policy rm_read on report_measures for select to authenticated using (true);
create policy rf_read on report_fields   for select to authenticated using (true);

-- אין policy לכתיבה, בכוונה, גם לא לאדמין. ראה ההערה בראש הקובץ.

comment on table report_sources is
  'קטלוג בונה הווידג׳טים: מקורות. ה-CASE של ה-FROM ב-app.report_run מכיר בדיוק את השורות האלה.';
comment on table report_measures is
  'קטלוג בונה הווידג׳טים: מדדים. impl=engine מנותב ל-app.payroll_*/app.margin_* ואינו פולט SQL.';
comment on table report_fields is
  'קטלוג בונה הווידג׳טים: שדות לפילוח וסינון. col ו-label_col הם מזהים חשופים שנפלטים דרך %I.';

-- ===== 4. זריעה: מקורות ====================================================

insert into report_sources (key, label_he, row_noun_he, alias, date_col, perm_key,
                            scope_kind, scope_note_he, sort_order) values
  ('tasks',  'משימות', 'משימות', 't', 'task_date',  null, 'rls',
   'לפי תאריך המשימה, ללא משימות שנמחקו', 10),
  ('events', 'אירועים', 'אירועים', 'e', 'event_date', null, 'rls',
   'לפי תאריך האירוע, ללא אירועים שנמחקו', 20),
  ('attendance', 'נוכחות', 'משמרות', 'a', 'work_date', 'attendance.view_all', 'rls',
   'משמרות מאושרות בלבד', 30),
  -- המקור הזה אינו נשאל בשאילתה גנרית: כל המדדים שלו הם impl='engine'.
  -- app.attendance_pay_rows מבוטלת מ-authenticated, ולכן פונקציית invoker
  -- אינה יכולה לקרוא לה — וזו בדיוק הסיבה שהשכר מנותב לעוזרי definer.
  ('payroll', 'שכר ורווחיות', 'משמרות', 'r', 'work_date', 'dashboard.payroll', 'company',
   'משמרות מאושרות בלבד; הרווח אינו כולל תקורה', 40);

-- ===== 5. זריעה: שדות ======================================================
-- allowed_ops נבחרים לפי הטיפוס ולא "הכול לכולם": אופרטור שאין לו משמעות על
-- השדה הוא אופרטור שאין סיבה שהמנוע יידע לפלוט עליו.

insert into report_fields (key, source_key, label_he, kind, join_key, col, col_type,
                           label_col, color_col, fans_out, nullable, null_label_he,
                           can_group, can_filter, allowed_ops, perm_key,
                           field_entity, field_key, sort_order) values
  -- ── משימות ──────────────────────────────────────────────────────────────
  ('tasks.date', 'tasks', 'תאריך משימה', 'time', null, 'task_date', 'date',
   null, null, false, false, null, true, true,
   '{gte,lte,between}', null, 'task', 'task_date', 10),
  ('tasks.customer', 'tasks', 'לקוח', 'cat', 'customers', 'id', 'uuid',
   'name', 'color', false, true, 'ללא לקוח', true, true,
   '{eq,ne,in,not_in,is_null,is_not_null}', 'customers.view', 'customer', 'name', 20),
  ('tasks.status', 'tasks', 'סטטוס משימה', 'cat', 'task_status', 'id', 'uuid',
   'name', 'color', false, true, 'ללא סטטוס', true, true,
   '{eq,ne,in,not_in}', null, 'task', 'status_id', 30),
  ('tasks.type', 'tasks', 'סוג משימה', 'cat', 'task_types', 'id', 'uuid',
   'name', null, false, true, 'ללא סוג', true, true,
   '{eq,ne,in,not_in}', null, 'task', 'task_type_id', 40),
  ('tasks.method', 'tasks', 'אופן ביצוע', 'cat', 'exec_methods', 'id', 'uuid',
   'name', null, false, true, 'ללא אופן ביצוע', true, true,
   '{eq,ne,in,not_in}', null, 'task', 'execution_method_id', 50),
  -- fans_out: משימה רב-משאיתית מייצרת שורה למשאית. כל מדד שאינו fanout_safe
  -- נחסם מהפילוח הזה, ולכן "משימות לפי משאית" עובד ו"שעות לפי משאית" לא.
  ('tasks.truck', 'tasks', 'משאית', 'cat', 'trucks', 'id', 'uuid',
   'name', null, true, true, 'ללא משאית', true, false,
   '{}', null, 'task', 'truck_ids', 60),
  ('tasks.contractor', 'tasks', 'קבלן', 'cat', 'task_contractor', 'id', 'uuid',
   'name', null, false, true, 'ללא קבלן', true, true,
   '{eq,ne,in,not_in,is_null,is_not_null}', 'contractors.view', 'contractor', 'name', 70),
  ('tasks.hours_count', 'tasks', 'שעות משימה', 'num', null, 'hours_count', 'numeric',
   null, null, false, true, null, false, true,
   '{gt,gte,lt,lte,between,is_null,is_not_null}', null, 'task', 'hours_count', 80),
  ('tasks.worker_count', 'tasks', 'עובדים נדרשים', 'num', null, 'worker_count', 'int',
   null, null, false, false, null, false, true,
   '{eq,gt,gte,lt,lte,between}', null, 'task', 'worker_count', 90),
  ('tasks.requires_team_lead', 'tasks', 'דורש ראש צוות', 'bool', null,
   'requires_team_lead', 'bool', null, null, false, false, null, false, true,
   '{is_true,is_false}', null, 'task', 'requires_team_lead', 100),

  -- ── אירועים ─────────────────────────────────────────────────────────────
  ('events.date', 'events', 'תאריך אירוע', 'time', null, 'event_date', 'date',
   null, null, false, false, null, true, true,
   '{gte,lte,between}', null, 'event', 'event_date', 10),
  ('events.customer', 'events', 'לקוח', 'cat', 'ev_customers', 'id', 'uuid',
   'name', 'color', false, true, 'ללא לקוח', true, true,
   '{eq,ne,in,not_in,is_null,is_not_null}', 'customers.view', 'customer', 'name', 20),
  ('events.status', 'events', 'סטטוס אירוע', 'cat', 'ev_status', 'id', 'uuid',
   'name', 'color', false, true, 'ללא סטטוס', true, true,
   '{eq,ne,in,not_in}', null, 'event', 'status_id', 30),
  ('events.end_client', 'events', 'לקוח קצה', 'cat', null, 'end_client_name', 'text',
   null, null, false, true, 'ללא לקוח קצה', true, true,
   '{eq,ne,in,not_in,is_null,is_not_null}', null, 'event', 'end_client_name', 40),
  ('events.volume_m', 'events', 'נפח (מ״ק)', 'num', null, 'volume_m', 'numeric',
   null, null, false, true, null, false, true,
   '{gt,gte,lt,lte,between,is_null,is_not_null}', null, 'event', 'volume_m', 50),
  ('events.truck_count', 'events', 'משאיות נדרשות', 'num', null, 'truck_count', 'int',
   null, null, false, true, null, false, true,
   '{eq,gt,gte,lt,lte,between}', null, 'event', 'truck_count', 60),
  ('events.no_parking', 'events', 'ללא חניה', 'bool', null, 'no_parking', 'bool',
   null, null, false, false, null, false, true,
   '{is_true,is_false}', null, 'event', 'no_parking', 70),
  ('events.porterage', 'events', 'סבלות', 'bool', null, 'porterage', 'bool',
   null, null, false, false, null, false, true,
   '{is_true,is_false}', null, 'event', 'porterage', 80),

  -- ── נוכחות ──────────────────────────────────────────────────────────────
  ('attendance.date', 'attendance', 'תאריך משמרת', 'time', null, 'work_date', 'date',
   null, null, false, false, null, true, true,
   '{gte,lte,between}', null, null, null, 10),
  -- המפתח יושב על שורת הפילוח ולא על המדד, וכך שורה אחת מגדרת גם
  -- "שעות לפי עובד" וגם "שכר לפי עובד" — מה ש-0041 עושה ביד בשני מקומות.
  ('attendance.worker', 'attendance', 'עובד', 'cat', 'people', 'id', 'uuid',
   'full_name', null, false, false, null, true, true,
   '{eq,ne,in,not_in}', 'dashboard.all_workers', 'profile', 'full_name', 20),
  ('attendance.work_site', 'attendance', 'אתר עבודה', 'cat', null, 'work_site', 'text',
   null, null, false, true, 'ללא אתר', true, true,
   '{eq,ne,in,not_in,is_null,is_not_null}', null, null, null, 30),
  ('attendance.source', 'attendance', 'מקור הדיווח', 'cat', null, 'source', 'text',
   null, null, false, true, 'לא ידוע', true, true,
   '{eq,ne,in,not_in}', null, null, null, 40),

  -- ── שכר ורווחיות ────────────────────────────────────────────────────────
  -- אלה אינם עמודות שהמנוע מקבץ לפיהן: הם שמות הפילוחים שעוזרי ה-definer
  -- יודעים לספק. `col` ממולא כדי לספק את האילוץ ואינו נפלט לשום SQL.
  ('payroll.date', 'payroll', 'לפי זמן', 'time', null, 'work_date', 'date',
   null, null, false, false, null, true, false, '{}', null, null, null, 10),
  ('payroll.worker', 'payroll', 'לפי עובד', 'cat', null, 'profile_id', 'uuid',
   null, null, false, false, null, true, false, '{}',
   'dashboard.all_workers', 'profile', 'full_name', 20),
  ('payroll.customer', 'payroll', 'לפי לקוח (משוער)', 'cat', null, 'customer_id', 'uuid',
   null, null, false, false, null, true, false, '{}',
   'customers.view', 'customer', 'name', 30);

-- הקצאת שכר ללקוח עוברת דרך attendance_entries.task_ids במשקל hours_count.
-- זו הערכה, וזה הפילוח היחיד בקטלוג שנושא is_estimate — המנוע מחזיר לצידו
-- allocated/unallocated, והכרטיס מסרב להציג אחוזים כשהלא-משויך גדול מדי.
update report_fields set is_estimate = true where key = 'payroll.customer';

-- ===== 6. זריעה: מדדים =====================================================

insert into report_measures (key, source_key, label_he, hint_he, impl, join_key, col,
                             col_type, expr_kind, allowed_aggs, default_agg, presence_col,
                             unit, perm_key, perm_all, field_entity, field_key,
                             requires_unscoped, is_estimate, fanout_safe, allowed_dims,
                             sort_order) values
  -- ── משימות ──────────────────────────────────────────────────────────────
  ('tasks.count', 'tasks', 'מספר משימות', null, 'sql', null, 'id', 'uuid', 'plain',
   '{count_distinct}', 'count_distinct', null, 'count', null, null, null, null,
   false, false, true, null, 10),
  ('tasks.hours', 'tasks', 'שעות משימה', 'סכום hours_count של המשימות', 'sql', null,
   'hours_count', 'numeric', 'plain', '{sum,avg,max}', 'sum', null, 'hours',
   null, null, 'task', 'hours_count', false, false, false, null, 20),
  ('tasks.workers_needed', 'tasks', 'עובדים נדרשים', null, 'sql', null,
   'worker_count', 'int', 'plain', '{sum,avg,max}', 'sum', null, 'count',
   null, null, 'task', 'worker_count', false, false, false, null, 30),
  -- perm_all ולא perm_key: השורות מגיעות דרך tp_select שדורשת pricing.view,
  -- ו-pricing.revenue *נגזר* ממנה ולא להפך. מענק מפורש של pricing.revenue
  -- לבדו היה מייצר 0 שקט במקום null.
  ('revenue', 'tasks', 'הכנסות', 'מחיר המשימות בטווח', 'sql', 'task_pricing', 'price',
   'numeric', 'plain', '{sum,avg,max}', 'sum', 'task_id', 'money', null,
   '{pricing.revenue,pricing.view}', 'task_pricing', 'price', false, false, false, null, 40),
  ('contractor_cost', 'tasks', 'עלות קבלנים (מחויב)', null, 'sql', 'contractor_terms',
   'price', 'numeric', 'plain', '{sum,avg}', 'sum', 'task_id', 'money', null,
   '{dashboard.contractor_cost,contractors.view_pricing}', 'task_terms', 'price',
   false, false, false, null, 50),
  ('contractor_paid', 'tasks', 'עלות קבלנים (ששולם)', 'רק שורות עם paid_at', 'sql',
   'contractor_terms', 'price', 'numeric', 'coalesce_paid', '{sum}', 'sum', 'task_id',
   'money', null, '{dashboard.contractor_cost,contractors.view_pricing}',
   'task_terms', 'paid_amount', false, false, false, null, 60),

  -- ── אירועים ─────────────────────────────────────────────────────────────
  ('events.count', 'events', 'מספר אירועים', null, 'sql', null, 'id', 'uuid', 'plain',
   '{count_distinct}', 'count_distinct', null, 'count', null, null, null, null,
   false, false, true, null, 10),
  ('events.volume', 'events', 'נפח מטען (מ״ק)', null, 'sql', null, 'volume_m',
   'numeric', 'plain', '{sum,avg,max}', 'sum', null, 'volume', null, null,
   'event', 'volume_m', false, false, true, null, 20),
  ('events.trucks', 'events', 'משאיות נדרשות', null, 'sql', null, 'truck_count', 'int',
   'plain', '{sum,avg,max}', 'sum', null, 'count', null, null,
   'event', 'truck_count', false, false, true, null, 30),

  -- ── נוכחות: שעות בלי כסף ────────────────────────────────────────────────
  -- ההפרדה שמאפשרת לרכז משמרות לראות עומס בלי לראות שכר, בדיוק כמו
  -- attendance_report.
  ('attendance.hours', 'attendance', 'שעות עבודה', 'משמרות מאושרות בלבד', 'sql', null,
   'actual_hours', 'numeric', 'plain', '{sum,avg,max}', 'sum', null, 'hours',
   'attendance.view_all', null, null, null, false, false, true, null, 10),
  ('attendance.shifts', 'attendance', 'מספר משמרות', null, 'sql', null, 'id', 'uuid',
   'plain', '{count_distinct}', 'count_distinct', null, 'count',
   'attendance.view_all', null, null, null, false, false, true, null, 20),
  ('attendance.workers', 'attendance', 'עובדים שונים', null, 'sql', null, 'profile_id',
   'uuid', 'plain', '{count_distinct}', 'count_distinct', null, 'count',
   'attendance.view_all', null, null, null, false, false, true, null, 30),

  -- ── שכר ─────────────────────────────────────────────────────────────────
  -- כולם impl='engine': הצבר השבועי תלוי-סדר, ומימוש שני היה מתפצל מהדוח
  -- בשקט. זו התזה של 0039, ללא שינוי.
  ('payroll.total', 'payroll', 'עלות שכר', 'מהנוכחות המאושרת בלבד', 'engine', null,
   null, null, 'plain', '{sum}', 'sum', null, 'money', 'dashboard.payroll', null,
   null, null, false, false, true,
   '{__none__,payroll.date,payroll.worker,payroll.customer}', 10),
  ('payroll.paid_hours', 'payroll', 'שעות בתשלום', null, 'engine', null, null, null,
   'plain', '{sum}', 'sum', null, 'hours', 'dashboard.payroll', null, null, null,
   false, false, true, '{__none__,payroll.date,payroll.worker}', 20),
  ('payroll.overtime_hours', 'payroll', 'שעות נוספות', null, 'engine', null, null, null,
   'plain', '{sum}', 'sum', null, 'hours', 'dashboard.payroll', null, null, null,
   false, false, true, '{__none__}', 30),
  ('payroll.bonus', 'payroll', 'בונוסים', null, 'engine', null, null, null,
   'plain', '{sum}', 'sum', null, 'money', 'dashboard.payroll', null, null, null,
   false, false, true, '{__none__}', 40),
  ('payroll.shifts', 'payroll', 'משמרות בתשלום', null, 'engine', null, null, null,
   'plain', '{sum}', 'sum', null, 'count', 'dashboard.payroll', null, null, null,
   false, false, true, '{__none__}', 50),

  -- ── רווח גולמי ──────────────────────────────────────────────────────────
  -- ארבעה מפתחות יחד: רווח הוא חיסור, ולכן מי שרואה אותו יכול לגזור ממנו את
  -- הרכיבים. requires_unscoped כי עלות השכר היא של כל החברה.
  ('margin.gross', 'payroll', 'רווח גולמי', 'הכנסות פחות עלות קבלנים ועלות שכר. אינו כולל תקורה',
   'engine', null, null, null, 'plain', '{sum}', 'sum', null, 'money', null,
   '{dashboard.margin,dashboard.payroll,dashboard.contractor_cost,pricing.revenue}',
   null, null, true, false, true, '{__none__,payroll.date,payroll.customer}', 60),
  ('margin.pct', 'payroll', 'שיעור רווח גולמי', null, 'engine', null, null, null,
   'plain', '{sum}', 'sum', null, 'percent', null,
   '{dashboard.margin,dashboard.payroll,dashboard.contractor_cost,pricing.revenue}',
   null, null, true, false, true, '{__none__,payroll.date}', 70);
