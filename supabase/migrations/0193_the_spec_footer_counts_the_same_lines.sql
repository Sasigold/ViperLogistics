-- 0193: גם מסך המפרט סופר את אותן שורות
--
-- ‏0192 לימד את המתרגם לספור רק שורה ששמה ברשימה של החיבור, ושכח מקום אחד:
-- שתי המספרים שמתחת לרשימת הריהוט ("‏4 עובדים · 2 משאיות") עדיין נספרו לפי
-- ‏`line_type` בלבד — גם במסך החי וגם בנפילה הרכה. התוצאה הייתה אירוע
-- שאומר על עצמו שני דברים סותרים: שדה "כמות משאיות" אחד, והכיתוב מתחת
-- למפרט אחר. מספר שסותר מספר אחר באותו מסך גרוע משני המספרים.
--
-- הספירה יורדת מהלקוח אל ה-view: היא אותה שאלה, ולכן מוטב שתהיה לה תשובה
-- אחת. הפונקציה היא `security definer` כי היא צריכה לקרוא את רשימות השמות
-- שעל החיבור — הגדרה של המשרד — בשביל עובד שטח שרואה את האירוע ואינו רואה
-- את מסך החיבורים (0176 §5). מה שהוא מקבל הוא המספר, לא ההגדרה.

create or replace function app.viperflow_stored_quantity(p_event uuid, p_type text)
returns numeric language sql stable security definer set search_path = public as $$
  select nullif(sum(i.quantity), 0)
  from viperflow_order_items i
  join viperflow_links l       on l.event_id = i.event_id
  join viperflow_connections c on c.id = l.connection_id
  where i.event_id = p_event
    and i.line_type = p_type
    and not i.is_component
    and btrim(i.name) = any(case p_type
                              when 'truck'  then c.trucking_line_names
                              when 'worker' then c.crew_line_names
                              else '{}'::text[] end);
$$;

comment on function app.viperflow_stored_quantity(uuid, text) is
  'כמה הוזמן מסוג שורה, לפי רשימת השמות של החיבור — אותה ספירה של המתרגם (0193).';

revoke execute on function app.viperflow_stored_quantity(uuid, text)
  from anon, authenticated, public;

-- ה-view נבנה מחדש במלואו: הוספת עמודה ל-`create or replace view` דורשת
-- שהעמודות הקיימות יישארו בדיוק באותו סדר ובאותם שמות, ולכן הוא נכתב כאן
-- כמו שהוא ב-0177 §7 בתוספת שתי השורות האחרונות.
create or replace view viperflow_event_link with (security_invoker = true) as
select l.event_id,
       l.connection_id,
       l.order_id,
       l.order_number,
       l.order_status,
       l.last_synced_at,
       c.label as connection_label,
       (select count(*) from viperflow_order_items i
         where i.event_id = l.event_id and i.line_type = 'product'
           and not i.is_component) as furniture_lines,
       app.viperflow_stored_quantity(l.event_id, 'truck')  as truck_quantity,
       app.viperflow_stored_quantity(l.event_id, 'worker') as worker_quantity
from viperflow_links l
left join viperflow_connections c on c.id = l.connection_id;

grant select on viperflow_event_link to authenticated;
revoke all on viperflow_event_link from anon;
