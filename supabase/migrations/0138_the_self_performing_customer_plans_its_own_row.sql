-- 0138: מי שמבצע בעצמו — הלוח שלו פתוח לו
--
-- ‏0109 קבע ששדות הלוח של הלקוח סגורים לעריכה עד שהמשרד פותח אותם, וזו הכרעה
-- נכונה: הלוח הוא של המשרד, והוא זה שמחליט מה כל לקוח עורך. אבל **לקוח שמבצע
-- את המשימות שלו בעצמו הוא לא "לקוח שעורך את התכנון של המשרד"** — הוא זה
-- שמתכנן. משימה שסומנה שהוא מבצע אותה אינה מתוכננת אצל אף אחד אחר: המחיר
-- שלה 0 (0120), היא מוסתרת מוייפר (0135), והסגל שעליה הוא שלו (0133).
--
-- לכן שני שדות נפתחים לו כברירת מחדל — **המשאיות** ו**הסטטוס** — ורק לו:
-- התנאי הוא `performed_by_enabled`, ולא "כל לקוח". שני אלה הם מה שנשאר בלו״ז
-- אחרי שסגל העובדים כבר עובר ב-RPC משלו: הרכבים שיוצאים, וההזזה בין טיוטה
-- למתוכנן (0131).
--
-- **וזו פתיחה, לא עקיפה.** ‏`app.enforce_customer_board_edit` (0109) לא זזה,
-- ‏`customer_board_fields` נשארת הטבלה שמכריעה, והמשרד יכול לסגור אותם בכרטיס
-- הלקוח בדיוק כמו שהוא פותח שדות לכל לקוח אחר. מה שמשתנה הוא נקודת הפתיחה.
--
-- ‏`do update` ולא `do nothing`: לקוח קיים כבר נושא שורת 'visible' מ-0109,
-- ו-`do nothing` היה משאיר אותה — כלומר לא עושה דבר.

insert into customer_board_fields (customer_id, field_key, state)
select c.id, k, 'editable'::board_field_state
from customers c, unnest(array['truck', 'status']) k
where c.performed_by_enabled and c.deleted_at is null
on conflict (customer_id, field_key) do update set state = 'editable';

-- לקוח שהדגל שלו נדלק מאוחר יותר. `app.seed_customer_defaults` (0109) כותב
-- 'visible' לכל השדות בלידה, ואינו יודע על הדגל — שנקבע בכרטיס הלקוח אחריה.
create or replace function app.customer_self_performing_board()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.performed_by_enabled and not coalesce(old.performed_by_enabled, false) then
    insert into customer_board_fields (customer_id, field_key, state)
    select new.id, k, 'editable'::board_field_state from unnest(array['truck', 'status']) k
    on conflict (customer_id, field_key) do update set state = 'editable';
  end if;
  return new;
end $$;

comment on function app.customer_self_performing_board() is
  'לקוח שסומן כמבצע בעצמו מקבל את שדות המשאיות והסטטוס פתוחים לעריכה בלוח '
  '(0138). המשרד יכול לסגור אותם אחר כך — זו נקודת פתיחה, לא עקיפה.';

create trigger customers_self_performing_board
  after insert or update of performed_by_enabled on customers
  for each row execute function app.customer_self_performing_board();
