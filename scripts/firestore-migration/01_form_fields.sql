-- שדות מותאמים אישית לשלושת הלקוחות, כדי שהשדות מ-Firestore שאין להם עמודה
-- ייכנסו ל-events.custom_fields ויוצגו בטופס במקום להיעלם.
--
-- המפתח נגזר דטרמיניסטית מ-md5(שם לקוח|תווית) ולא מ-gen_random_uuid כמו
-- ב-create_custom_form_field: הרצה חוזרת של הייבוא חייבת לפגוע באותו מפתח,
-- אחרת ה-custom_fields שכבר נטענו היו מצביעים על שדה יתום.

begin;

with wanted(customer_name, label_he, field_type, options, sort_order) as (
  values
    -- שיא עיצובים: המקבילות לשדות שכבר הוגדרו אצל קיסר
    ('שיא עיצובים', 'מחיר ריהוט',       'number', '[]'::jsonb, 1000),
    ('שיא עיצובים', 'מחיר חדש',         'number', '[]'::jsonb, 1001),
    ('שיא עיצובים', 'קישור ל-Eruit',    'text',   '[]'::jsonb, 1002),
    -- ארקו: שדות הכסף שאין להם עמודה. ה"פירוט" הוא טקסט חופשי שמתאר את
    -- החיוב ("סה״כ כולל הובלות", "לינה", "סבלות") ולא סכום.
    ('ארקו', 'סכום הובלה',       'number', '[]'::jsonb, 1000),
    ('ארקו', 'מחיר לוגיסטיקה',   'number', '[]'::jsonb, 1001),
    ('ארקו', 'פירוט לוגיסטיקה',  'text',   '[]'::jsonb, 1002),
    ('ארקו', 'מחיר הובלה',       'number', '[]'::jsonb, 1003),
    ('ארקו', 'פירוט הובלה',      'text',   '[]'::jsonb, 1004),
    ('ארקו', 'מתגלגל להובלה',    'number', '[]'::jsonb, 1005),
    ('ארקו', 'תנאי תשלום',       'text',   '[]'::jsonb, 1006)
)
insert into form_fields (field_key, label_he, sort_order, customer_id, field_type, options)
select 'custom_' || substr(md5(w.customer_name || '|' || w.label_he), 1, 12),
       w.label_he, w.sort_order, c.id, w.field_type, w.options
from wanted w
join customers c on c.name = w.customer_name and c.deleted_at is null
where not exists (
  select 1 from form_fields f
   where f.customer_id = c.id and f.label_he = w.label_he and f.deleted_at is null
);

-- שדה חדש נראה ללקוח שלו בלבד; seed_customer_defaults רץ רק על לקוח חדש.
insert into customer_form_fields (customer_id, field_key, state)
select f.customer_id, f.field_key, 'visible'::field_state
from form_fields f
where f.customer_id is not null and f.deleted_at is null
on conflict do nothing;

-- "תנאי תשלום" של קיסר הוגדר עם שלוש אפשרויות; במקור יש גם "שוטף 60".
update form_fields
   set options = options || '["שוטף + 60"]'::jsonb
 where field_type = 'select'
   and label_he = 'תנאי תשלום'
   and customer_id = (select id from customers where name = 'קיסר' and deleted_at is null)
   and deleted_at is null
   and not options @> '["שוטף + 60"]'::jsonb;

commit;
