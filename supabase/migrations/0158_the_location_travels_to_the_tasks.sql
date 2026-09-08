-- 0158: המיקום של האירוע נוסע גם למשימות שלו
--
-- הלו״ז מציג `coalesce(t.location_text, e.location_text)` מאז 0005, ולכן
-- משימה **שאין לה מיקום משלה** ממילא עוקבת אחרי האירוע. מה שלא עקב הוא
-- משימה שנושאת *העתק* של מיקום האירוע, ושתי דרכים יצרו בדיוק כזאת:
--
--   * ‏`duplicate_event` (0006, ירדה ב-0157) העתיקה `t.location_text` אל
--     משימות האירוע החדש. עותק שנולד מאירוע שכבר היה לו מיקום החזיק אותו
--     על כל משימה — ואז שינוי המיקום בטופס האירוע החדש לא הזיז אותן.
--   * הייבוא מאקסל (0052, 0076): לגיליון "משימות" יש עמודת "מיקום המשימה",
--     ומי שמילא בה את כתובת האירוע קיבל את אותו העתק בדיוק.
--
-- התוצאה בשטח היא הגרועה מכולן: המסך מציג לעובד את הכתובת **הישנה** בלי
-- שום סימן לכך שהיא ישנה — האירוע כבר עודכן, והלו״ז מספר סיפור אחר.
--
-- **ההעתק עוקב, הדריסה נשארת.** התנאי הוא `location_text = old.location_text`
-- — משימה שהמיקום שלה היה מה שהאירוע אמר, ממשיכה לומר מה שהאירוע אומר.
-- משימה עם מיקום *אחר* היא הכרעה מפורשת של מי שכתב אותה (הקמה במחסן בזמן
-- שהאירוע באולם), והיא אינה נדרסת. משימה בלי מיקום (‏null) אינה נכללת —
-- ‏`null = ...` אינו true — וזה הנכון: היא כבר יורשת דרך ה-coalesce, וכתיבת
-- ערך אליה הייתה **מקפיאה** אותה על הערך הזה לתמיד. ריקון המיקום באירוע
-- מרוקן איתו את ההעתקים, ומחזיר אותם לירושה.
--
-- **‏`security definer` ו-`system_write`.** שתי גדרות עומדות בין העדכון הזה
-- לבין המשימות: ‏RLS על `tasks`, ו-`app.enforce_field_perms` שדורש
-- ‏`tasks.change_location` על העמודה (0011, 0012). מי שרשאי לערוך את מיקום
-- ה**אירוע** אינו נדרש להחזיק גם את המפתח של הלו״ז — זה בדיוק המקרה ש-
-- ‏`app.system_write` נועד לו, כמו ב-`apply_event_task_block` וב-
-- ‏`sync_contractor_terms`.
--
-- הדגל **מוחזר למה שהיה** ולא מכובה בעיוורון: הייבוא מריץ את העדכון על
-- ‏`events` בתוך חלון system_write משלו, וכיבוי גורף כאן היה מכבה אותו
-- באמצע ומחזיר את שאר הייבוא לשיפוט פר-שדה.
--
-- ‏`after update of location_text` — עמודה אחת, ולכן שמירה שלא נגעה במיקום
-- אינה מריצה כאן דבר. ‏`return null` כי זה טריגר AFTER: הוא אינו משנה את
-- השורה, רק מגיב לה.

create or replace function app.tasks_follow_event_location()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_sys boolean := app.in_system_write();
begin
  if new.location_text is not distinct from old.location_text then
    return null;
  end if;

  perform app.system_write(true);
  update tasks set location_text = new.location_text
   where event_id = new.id
     and deleted_at is null
     and location_text = old.location_text;
  if not v_sys then perform app.system_write(false); end if;

  return null;
end $$;

create trigger events_location_to_tasks after update of location_text on events
  for each row execute function app.tasks_follow_event_location();

comment on function app.tasks_follow_event_location() is
  'שינוי מיקום באירוע נוסע למשימות שנשאו העתק של המיקום הקודם (0158). '
  'משימה בלי מיקום יורשת ממילא ב-coalesce, ומשימה עם מיקום אחר אינה נדרסת.';
