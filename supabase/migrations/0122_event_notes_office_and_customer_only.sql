-- 0122: תיעוד חופשי — למשרד וללקוח; לשטח ולקבלנים רק רשומות מערכת
--
-- ביומן האירוע שני סוגים: רשומות **מערכת** אוטומטיות (`kind <> 'note'` — שינוי,
-- יצירה, חתימה, תוספת) ו**מלל חופשי** שאדם כתב (`kind = 'note'`, "תיעוד").
-- המלל החופשי הוא "הסיבה שמאחורי השינוי, שיחה עם הלקוח" — ולכן שטח וקבלנים
-- רואים ממנו רק את רשומות המערכת; המשרד והלקוח רואים הכול.
--
-- **מפתח חדש `events.activity_note_view`, נגזר מ-`events.edit`.** מי שעורך
-- אירועים (המשרד, ומנהל הלקוח) מקבל אותו בהיסק; משתמש לקוח מקבל אותו בברירת
-- מחדל של סוג המשתמש. ראש-צוות שטח (רואה יומן רק דרך `is_event_team_lead`, בלי
-- `events.edit`) וקבלן (מחזיק `events.activity_log`/`note` מ-0103 אך לא
-- `events.edit`) — אינם מקבלים, ולכן נשארים עם רשומות המערכת בלבד.
--
-- **האכיפה בפוליסה ולא במסך.** שורת `note` פשוט אינה נקראת למי שאין לו המפתח.

select app.register_permission('events.activity_note_view', 'events',
  'צפייה בתיעוד חופשי',
  'רשומות מלל חופשי ביומן האירוע — לא רק רשומות מערכת',
  'access', false, false,
  array['staff', 'customer_user']::user_kind[], 'events.edit', 185);

-- משתמש לקוח רואה תיעוד בברירת מחדל (שכבה 4 קודמת ל-implied_by).
insert into kind_permission_defaults (user_kind, permission_key, allowed) values
  ('customer_user', 'events.activity_note_view', true)
on conflict (user_kind, permission_key) do nothing;

-- הפוליסה: הגוף מ-0082, ועוד תנאי שמסתיר `note` ממי שאין לו המפתח. ה-admin
-- (הזרוע הראשונה) רואה הכול.
drop policy event_activity_select on event_activity;
create policy event_activity_select on event_activity for select to authenticated using (
  (select app.is_admin())
  or (((select app.has('events.activity_log'))
       or (select app.is_event_team_lead(event_activity.event_id)))
      and exists (select 1 from events e where e.id = event_activity.event_id)
      and (kind <> 'note' or (select app.has('events.activity_note_view')))));
