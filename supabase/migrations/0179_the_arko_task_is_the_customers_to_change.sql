-- 0179: במשימה שארקו מבצעת — ארקו משנה הכול; במשימה של וייפר, כלום
--
-- הדיווח: **"שלקוח ארקו יוכל לשבץ עובדים ומשאיות למשימות שמבוצעות ע״י ארקו,
-- וגם לשנות כל דבר במשימות שלו. במשימות שמבוצעות ע״י וייפר הוא לא יכול לשנות
-- כלום, בדיוק כמו היום."**
--
-- שני חצאים של משפט אחד, ו-**הגבול ביניהם הוא `performed_by`** — לא הלקוח,
-- ולא המפתח. עד כאן הגבול היה הלקוח: `app.enforce_customer_board_edit` (0109)
-- שואלת מה מנהל המערכת פתח ל**לקוח הזה** בכרטיס שלו, והתשובה חלה על כל
-- משימותיו כאחת. ‏0138 כבר נגעה בקצה הזה כשפתחה לו שני שדות כברירת מחדל,
-- ואמרה את הנימוק במלואו: "לקוח שמבצע את המשימות שלו בעצמו אינו לקוח שעורך
-- את התכנון של המשרד — הוא זה שמתכנן". מה שהיא לא עשתה הוא להסיק את המסקנה
-- **פר-משימה**, וזה מה שכאן.
--
-- **במשימה שהלקוח מבצע, הלוח כולו שלו.** אין למשרד מה לשמור שם: המחיר 0
-- (0120), המשימה מוסתרת מוייפר וגם ממנהל המערכת (0135/0139), השיבוץ עליה
-- הוא סגל הלקוח (0133), וההאצלה הוסרה ממנה (0135). שדה שנשאר נעול היה נעול
-- בפני היחיד שיש לו מה לעשות איתו.
--
-- **ובמשימה של וייפר לא זז דבר.** ‏`customer_board_fields` נשארת הטבלה
-- שמכריעה, `app.enforce_customer_board_edit` ממשיכה לרוץ עליה מילה במילה,
-- ומה שהמשרד פתח או סגר בכרטיס הלקוח הוא מה שיהיה. התוספת כאן היא ענף
-- דילוג אחד, והתנאי שלו צר ככל שאפשר לנסח: המשימה של הלקוח של הקורא, הוא
-- מסומן כמבצע בעצמו, והיא מסומנת שהוא מבצע אותה — לפני העריכה ואחריה.
--
-- **והשיבוץ עצמו כבר עובד** ואינו נוגע כאן: `customer_assign_worker` (0133)
-- משבץ עובד, תפקיד ומשאית-של-נהג, והמשאיות של המשימה הן שדה `truck` בלוח —
-- שעד עכשיו היה פתוח בזכות 0138 ומעכשיו בזכות הכלל, לא בזכות שורה בטבלה.

-- ===== 1. השאלה, פעם אחת ================================================
--
-- שני הטריגרים שלמטה שואלים אותה, והמסך שואל אותה על כל שורה בלו״ז. היא
-- `security definer` משום שהיא קוראת את `customers` דרך
-- `app.customer_self_performing` (0140), שכבר נכתבה בדיוק לשימוש הזה.
create or replace function app.task_performed_by_caller(
  p_customer_id uuid, p_performed_by text)
returns boolean language sql stable security definer set search_path = public as $$
  select app.user_kind() = 'customer_user'
     and p_customer_id is not null
     and p_customer_id = app.customer_id()
     and coalesce(p_performed_by, 'viper') <> 'viper'
     and app.customer_self_performing(p_customer_id)
$$;

comment on function app.task_performed_by_caller(uuid, text) is
  'האם המשימה הזו היא של הקורא לבצע (0179): הלקוח שלו, שמסומן כמבצע בעצמו, '
  'והמשימה סומנה שהוא מבצע אותה. זה הגבול שבין "הלוח של המשרד" ל"הלוח שלו".';

revoke execute on function app.task_performed_by_caller(uuid, text) from anon;
grant execute on function app.task_performed_by_caller(uuid, text) to authenticated;

-- ===== 2. שדות הלו״ז: דילוג על משימה שהיא שלו ============================
-- הגוף זהה ל-0109 בתוספת ענף אחד, והוא נבדק אחרי `v_ctr` — כי בלי לקוח
-- לקורא אין בכלל שאלה.
create or replace function app.enforce_customer_board_edit()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_old jsonb := to_jsonb(old);
  v_new jsonb := to_jsonb(new);
  v_ctr uuid;
  r     record;
begin
  if auth.uid() is null then return new; end if;
  if app.in_system_write() then return new; end if;
  if app.is_admin() then return new; end if;
  if app.user_kind() <> 'customer_user' then return new; end if;

  v_ctr := app.customer_id();
  if v_ctr is null then return new; end if;

  -- ‏0179: משימה שהלקוח מבצע בעצמו — הלוח שלה שלו, על כל שדותיו. **לפני
  -- העריכה ואחריה**: משימה שחוזרת בעריכה הזו לוייפר חוזרת גם לכללים שלה.
  if app.task_performed_by_caller(new.customer_id, new.performed_by)
     and app.task_performed_by_caller(old.customer_id, old.performed_by) then
    return new;
  end if;

  for r in
    select f.field_key, f.label_he, f.column_name,
           coalesce(c.state, 'visible'::board_field_state) as state
      from board_fields f
      left join customer_board_fields c
             on c.customer_id = v_ctr and c.field_key = f.field_key
     where f.column_name is not null
  loop
    if v_old -> r.column_name is not distinct from v_new -> r.column_name then
      continue;
    end if;
    if r.state <> 'editable' then
      raise exception 'השדה "%" אינו פתוח לעריכה עבורך', r.label_he
        using errcode = '42501';
    end if;
  end loop;
  return new;
end $$;

comment on function app.enforce_customer_board_edit() is
  'מה שהלקוח עורך בלו״ז נקבע בכרטיס שלו (0109) — פרט למשימה שהוא עצמו '
  'מבצע, שהיא שלו לתכנן במלואה (0179).';

-- ===== 3. והפרסום שלה גם הוא שלו ========================================
--
-- "לשנות כל דבר" כולל את הסטטוס, וסטטוס כולל את "משובץ". ‏`tasks.publish`
-- סגור ללקוח ברמת ה-kind מאז 0066, וזה נכון: פרסום הוא ההכרזה של המשרד
-- לצוות שלו שהלוח סופי. במשימה שארקו מבצעת אין צוות של וייפר להכריז לו —
-- **יש את הסגל שלה**, ומשמרת נגזרת רק ממשימה משובצת (0020). בלי זה עובד
-- ארקו לא היה רואה ב-`/my/schedule` דבר, והלוח שלה היה נעול על "מתוכנן"
-- לנצח.
--
-- השער נשאר במקומו לכל השאר, ובכלל זה לאותו לקוח עצמו על משימות וייפר שלו.
create or replace function app.enforce_task_publish()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_assigned uuid;
begin
  if auth.uid() is null then return new; end if;
  if app.in_system_write() then return new; end if;
  if app.is_admin() then return new; end if;

  -- ‏0179: המשימה שהוא מבצע — הוא גם מפרסם אותה לסגל שלו.
  if app.task_performed_by_caller(new.customer_id, new.performed_by) then
    return new;
  end if;

  select id into v_assigned from statuses
   where entity = 'task' and code = 'assigned' and deleted_at is null limit 1;

  if new.status_id = v_assigned
     and (tg_op = 'INSERT' or old.status_id is distinct from new.status_id) then
    perform app.require('tasks.publish', 'אין לך הרשאה לפרסם משימה (סטטוס "משובץ")');
  end if;

  if tg_op = 'UPDATE' and old.status_id = v_assigned
     and new.status_id is distinct from old.status_id then
    perform app.require('tasks.publish',
      'משימה משובצת יורדת מהסטטוס הזה רק בידי מי שרשאי לפרסם');
  end if;

  return new;
end $$;

comment on function app.enforce_task_publish() is
  'שער הפרסום (0066), לשני הכיוונים (0117) — ופתוח ללקוח על המשימות שהוא '
  'עצמו מבצע (0179).';

-- ===== 4. והלו״ז מוסר את התשובה למסך =====================================
--
-- ‏`customer_self_performing` כבר על השורה מ-0140, ו-`performed_by` מ-0120 —
-- כלומר המסך יכול לשאול את אותה שאלה בדיוק בלי עמודה נוספת ובלי קריאה
-- נוספת. ‏`app.task_performed_by_caller` היא הניסוח שלה בשרת, והיא נשארת
-- הגבול; מה שהמסך עושה איתה הוא רק לא לצייר תא נעול שהשרת יקבל.
