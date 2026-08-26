-- 0116: רשימת המשאיות של הלקוח
--
-- ‏`trucks` היא קטלוג אחד גלובלי מאז 0002, ובורר המשאיות בלו״ז מציע את כולו
-- לכל מי שפותח אותו. ללקוח שמשבץ משאית משלו זו רשימה של משאיות שאינן שלו:
-- הוא מחפש בתוך צי של חברה שלמה כדי למצוא את השתיים שהוא מכיר, ובדרך הוא
-- יכול לבחור אחת שאינה שלו כלל.
--
-- **המשרד קובע את הרשימה, והלקוח משבץ מתוכה.** זו ההכרעה, ולא "הלקוח מנהל
-- את הצי שלו": המשאית היא נכס של החברה — יש לה רישיון, ביטוח ונהג קבוע
-- (0089) — ומי שפותח משאית בקטלוג הוא גם מי שיודע של מי היא. הרשימה היא
-- קטלוג פר-לקוח, כמו `customer_execution_methods` (0002) ו-
-- ‏`customer_board_fields` (0109), ולא ישות חדשה.
--
-- **רשימה ריקה = אין הגבלה.** לקוח שלא הוגדרה לו רשימה ממשיך לראות את
-- הקטלוג כולו, בדיוק כמו `app.board_config` שמחזירה ריק לאיש צוות והמסך
-- קורא זאת כ"אין הגבלה פר-לקוח". זה מה שהופך את המיגרציה לחסרת אפקט ביום
-- שהיא עולה: אף לקוח אינו מאבד משאית, ואין כאן זריעה.

create table customer_trucks (
  customer_id uuid not null references customers(id) on delete cascade,
  truck_id    uuid not null references trucks(id)    on delete cascade,
  primary key (customer_id, truck_id)
);

comment on table customer_trucks is
  'אילו משאיות זמינות ללקוח מסוים בלו״ז (0116). ריק = כל הקטלוג. נקבע '
  'בידי המשרד; הלקוח משבץ מתוכה בלבד.';

alter table customer_trucks enable row level security;

-- הקריאה: המשרד רואה הכול (הלוח שלו מציג משימות של כמה לקוחות, והבורר בכל
-- שורה צריך את הרשימה של הלקוח *של המשימה*), והלקוח את שלו בלבד. זה צר יותר
-- מ-`cbf_read` של 0109 — שם `using (true)` היה הכרחי מפני שכל מסך מצייר
-- ממנה; כאן הרשימה של חברה אחת אינה עניינה של חברה אחרת.
create policy ct_read on customer_trucks for select to authenticated using (
  (select app.is_admin())
  or (select app.user_kind()) = 'staff'
  or customer_id = (select app.customer_id()));

-- הכתיבה: `settings.trucks` — אותו מפתח שכבר שולט בקטלוג הגלובלי, ו-
-- ‏`implied_by` שלו הוא `settings.edit` (0011), ולכן כל מי שמנהל היום נתוני
-- בסיס ממשיך לנהל גם את הרשימה בלי שורת הענקה חדשה. מי שפותח משאית בקטלוג
-- הוא גם מי שיודע של מי היא.
--
-- מפתח, ולא "מנהל מערכת בלבד" כמו ב-0109: שם ההכרעה הייתה על **גבול
-- הרשאות** ("מה הלקוח רשאי לשנות") ולכן נשמרה במפורש מחוץ למרשם; כאן זו
-- החלטה תפעולית על קטלוג, מאותו סוג בדיוק של `customer_execution_methods`.
create policy ct_write on customer_trucks for all to authenticated
  using ((select app.is_admin()) or (select app.has('settings.trucks')))
  with check ((select app.is_admin()) or (select app.has('settings.trucks')));

create trigger customer_trucks_audit after insert or update or delete
  on customer_trucks for each row execute function app.audit();

-- ===== 2. האכיפה: "מתוך הרשימה" הוא טענה על השרת =========================
--
-- אח לטריגר של 0109, ומאותו נימוק: מסך שמסנן בורר הוא נוחות, לא גבול. השדה
-- ‏`truck` בלו״ז נכתב ישירות ל-`tasks.truck_ids`, ומי שיודע לשלוח UPDATE
-- אינו עובר דרך הבורר.
--
-- ארבעת תנאי הדילוג זהים ל-`app.enforce_customer_board_edit` (0109) בדיוק:
-- כתיבה בלי JWT היא מיגרציה, כתיבה מתוך `system_write` כבר אושרה בהרשאה
-- גסה יותר במעלה הזרם, ואדמין ואיש צוות אינם הקהל של הכלל הזה. **המשרד
-- ממשיך לשבץ כל משאית** — הבורר שלו מסונן להצעה הנכונה, ולא נעול: משאית
-- מחוץ לרשימה בשעת לחץ היא החלטה תפעולית, לא עקיפה של כלל.
create or replace function app.enforce_customer_trucks()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_ctr uuid; v_bad text;
begin
  if auth.uid() is null then return new; end if;
  if app.in_system_write() then return new; end if;
  if app.is_admin() then return new; end if;
  if app.user_kind() <> 'customer_user' then return new; end if;

  -- כתיבה שלא נגעה במשאיות אינה נבדקת
  if tg_op = 'UPDATE'
     and new.truck_ids is not distinct from coalesce(old.truck_ids, '{}'::uuid[]) then
    return new;
  end if;
  if coalesce(cardinality(new.truck_ids), 0) = 0 then return new; end if;

  v_ctr := app.customer_id();
  if v_ctr is null then return new; end if;

  -- ריק = אין הגבלה
  if not exists (select 1 from customer_trucks where customer_id = v_ctr) then
    return new;
  end if;

  -- השם ולא המזהה: הודעה שאפשר לפעול לפיה
  select string_agg(coalesce(tr.name, '?'), ', ') into v_bad
    from unnest(new.truck_ids) as u(id)
    left join trucks tr on tr.id = u.id
   where not exists (select 1 from customer_trucks ct
                      where ct.customer_id = v_ctr and ct.truck_id = u.id);

  if v_bad is not null then
    raise exception 'המשאית "%" אינה ברשימת המשאיות שלך', v_bad
      using errcode = '42501';
  end if;
  return new;
end $$;

-- **שם הטריגר נושא משקל.** טריגרי שורה יורים לפי סדר אלפביתי של שמם, והם
-- כבר `tasks_customer_board_edit`, `tasks_field_perms`, `tasks_publish_guard`,
-- ‏`tasks_truck_sync` ו-`tasks_updated`. ‏`app.sync_task_trucks` (0035) **גוזר
-- את `truck_ids` מ-`truck_id`** — גם ב-INSERT וגם ב-UPDATE שנגע רק בעמודה
-- היחידה — ולכן בדיקה שרצה לפניו מפספסת בדיוק את הנתיב הזה. ‏`_z_` ממיין
-- אחרון, והבדיקה רואה את המערך הסופי.
create trigger tasks_z_customer_trucks before insert or update on tasks
  for each row execute function app.enforce_customer_trucks();

comment on function app.enforce_customer_trucks() is
  'לקוח משבץ רק משאיות מהרשימה שלו (0116). רשימה ריקה = כל הקטלוג. חל על '
  'customer_user בלבד — אצל המשרד הבורר מסונן ואינו נעול.';
