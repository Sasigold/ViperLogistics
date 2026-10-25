\pset tuples_only on
\pset format unaligned

-- ===========================================================================
-- ‏77: עוזר הוואטסאפ (0236) — מי מחזיק את המפתח, קוד הקישור ופדיונו, מי רואה
-- מה, איפה מותר לענות (משתתפי הקבוצה), וכמה עובדות שהבוט נשען עליהן כשהוא
-- כותב בשם המשתמש: הרשאות השדות נאכפות, הרצת ניסיון שמתבטלת אינה משאירה
-- התראה, ופעולה ממתינה נתפסת פעם אחת.
--
-- הנתונים ב-current_date + 1300; הסוויטה משאירה אחריה את מה שיצרה.
-- ===========================================================================

-- הסיד של הבדיקות מחזיר הרשאת הרצה לכל פונקציה; מה ש-0236 סגר נסגר כאן שוב.
revoke execute on function app.wa_code_hash(text) from anon, authenticated, public;
revoke execute on function app.wa_phone(text) from anon, authenticated, public;
revoke execute on function app.wa_allowed(uuid) from anon, authenticated, public;
revoke execute on function app.wa_sender(text) from anon, authenticated, public;
revoke execute on function app.wa_participants_ok(jsonb, text) from anon, authenticated, public;
revoke execute on function app.wa_participants_hold(jsonb, text, text[]) from anon, authenticated, public;
revoke execute on function app.wa_link_redeem(text, text, text) from anon, authenticated, public;
revoke execute on function app.wa_chat_bind(text, text, boolean, uuid, jsonb, text) from anon, authenticated, public;
revoke execute on function app.wa_chat_participants_set(text, jsonb, text) from anon, authenticated, public;
revoke execute on function app.wa_chat_dm(text, text) from anon, authenticated, public;
revoke execute on function app.wa_chat_unbind(text, uuid) from anon, authenticated, public;
-- (וגם הרשאות הטבלאות: הסיד פותח את כולן ל-authenticated)
revoke insert, update, delete, truncate on wa_links, wa_chats, wa_messages from authenticated;
revoke all on wa_link_codes, wa_link_attempts, wa_pending from anon, authenticated, public;

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000077a1', 'c77-office@vl.test'),
  ('00000000-0000-0000-0000-0000000077a2', 'c77-worker@vl.test'),
  ('00000000-0000-0000-0000-0000000077a3', 'c77-planner@vl.test'),
  ('00000000-0000-0000-0000-0000000077a4', 'c77-client@vl.test');

insert into customers (id, name) values
  ('10000000-0000-0000-0000-00000000077a', 'לקוח 77');

insert into profiles (id, user_id, user_kind, is_admin, full_name, customer_id) values
  ('20000000-0000-0000-0000-0000000077a1', '00000000-0000-0000-0000-0000000077a1',
   'staff', false, 'משרד 77', null),
  ('20000000-0000-0000-0000-0000000077a2', '00000000-0000-0000-0000-0000000077a2',
   'staff', false, 'עובד 77', null),
  ('20000000-0000-0000-0000-0000000077a3', '00000000-0000-0000-0000-0000000077a3',
   'staff', false, 'מתכנן 77', null),
  ('20000000-0000-0000-0000-0000000077a4', '00000000-0000-0000-0000-0000000077a4',
   'customer_user', false, 'לקוח 77', '10000000-0000-0000-0000-00000000077a');

-- משרד 77 עובד מול העוזר; לקוח 77 מקבל את המפתח אישית — ובכל זאת לא יחזיק בו.
-- המתכנן עורך משימות, עם שורת deny מפורשת לשינוי זמנים (המפתח נגזר מ-tasks.edit).
insert into user_permission_grants (profile_id, permission_key, allowed) values
  ('20000000-0000-0000-0000-0000000077a1', 'assistant.whatsapp', true),
  ('20000000-0000-0000-0000-0000000077a4', 'assistant.whatsapp', true),
  ('20000000-0000-0000-0000-0000000077a3', 'assistant.whatsapp', true),
  ('20000000-0000-0000-0000-0000000077a3', 'tasks.view', true),
  ('20000000-0000-0000-0000-0000000077a3', 'tasks.edit', true),
  ('20000000-0000-0000-0000-0000000077a3', 'tasks.create', true),
  ('20000000-0000-0000-0000-0000000077a3', 'tasks.reschedule', false);

insert into events (id, customer_id, event_number, event_date, status_id)
values ('30000000-0000-0000-0000-00000000077a', '10000000-0000-0000-0000-00000000077a',
        'EV-77', current_date + 1300,
        (select id from statuses where entity = 'event' and code = 'pending' and deleted_at is null));

-- ההקמה האוטומטית של האירוע — משובצת, עם עובד 77, כדי ששינוי זמנים יוליד התראה
update tasks set status_id = (select id from statuses where entity = 'task' and code = 'assigned' and deleted_at is null),
                 onsite_start_time = '08:00', hours_count = 4
 where event_id = '30000000-0000-0000-0000-00000000077a'
   and task_type_id = (select id from task_types where code = 'setup' limit 1);

insert into task_assignments (task_id, profile_id, role, work_site)
select t.id, '20000000-0000-0000-0000-0000000077a2', 'worker', 'field'
  from tasks t
 where t.event_id = '30000000-0000-0000-0000-00000000077a'
   and t.task_type_id = (select id from task_types where code = 'setup' limit 1);

-- אופן ביצוע ברירת מחדל להקמה אצל הלקוח, מתוך מה שמותר לסוג המשימה (לקוח חדש
-- מקבל את כל אופני הביצוע מטריגר; כאן רק מסמנים אחד מהם כברירת מחדל)
insert into customer_execution_methods (customer_id, execution_method_id)
select '10000000-0000-0000-0000-00000000077a', ttm.execution_method_id
  from task_type_execution_methods ttm
  join task_types tt on tt.id = ttm.task_type_id and tt.code = 'setup'
  join execution_methods m on m.id = ttm.execution_method_id and m.is_active and m.deleted_at is null
 limit 1
on conflict do nothing;
update customer_execution_methods set is_default_setup = false
 where customer_id = '10000000-0000-0000-0000-00000000077a';
update customer_execution_methods set is_default_setup = true
 where customer_id = '10000000-0000-0000-0000-00000000077a'
   and execution_method_id = (
     select ttm.execution_method_id
       from task_type_execution_methods ttm
       join task_types tt on tt.id = ttm.task_type_id and tt.code = 'setup'
       join execution_methods m on m.id = ttm.execution_method_id and m.is_active and m.deleted_at is null
      order by m.id limit 1);

create temp table w77 (k text primary key, v text);
grant all on w77 to authenticated;

-- ===== 1. המפתח ============================================================

\echo '--- המפתח ---'
select t_eq('המפתח חל על צוות בלבד',
  (select applies_to::text from permission_registry where key = 'assistant.whatsapp'), '{staff}');
select t_eq('וכבוי כברירת מחדל',
  (select default_allowed from permission_registry where key = 'assistant.whatsapp'), false);

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000077a1', false);
select t_eq('משרד 77 מחזיק את המפתח', app.has('assistant.whatsapp'), true);
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000077a2', false);
select t_eq('עובד 77 אינו מחזיק', app.has('assistant.whatsapp'), false);
select t_expect_fail('ואינו מקבל קוד', $$ select wa_link_code_create() $$);
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000077a4', false);
select t_eq('משתמש לקוח אינו מחזיק גם עם הענקה אישית', app.has('assistant.whatsapp'), false);
select t_expect_fail('ואינו מקבל קוד', $$ select wa_link_code_create() $$);
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false);
select t_eq('מנהל מערכת מחזיק', app.has('assistant.whatsapp'), true);
reset role;
select set_config('request.jwt.claim.sub', '', false);

-- ===== 2. הקוד והפדיון =====================================================

\echo '--- הקוד והפדיון ---'
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000077a1', false);
insert into w77 select 'code1', wa_link_code_create() ->> 'code';
select t_eq('קוד בן שש ספרות', (select v ~ '^[0-9]{6}$' from w77 where k = 'code1'), true);
select t_expect_fail('הקודים סגורים גם לבעליהם', $$ select * from wa_link_codes $$);
select t_expect_fail('והפדיון אינו פתוח מהדפדפן', $$
  select app.wa_link_redeem((select v from w77 where k = 'code1'), '972500000771@c.us', 'x') $$);
reset role;
select set_config('request.jwt.claim.sub', '', false);

select t_eq('שולח בצורה לא מוכרת נדחה',
  app.wa_link_redeem((select v from w77 where k = 'code1'), 'not-a-sender', 'x') ->> 'reason', 'bad_sender');
select t_eq('קוד שגוי נדחה',
  app.wa_link_redeem(case when (select v from w77 where k = 'code1') = '000000' then '000001' else '000000' end,
                     '972500000779@c.us', 'x') ->> 'reason', 'bad_code');
select t_eq('הפדיון מקשר', app.wa_link_redeem((select v from w77 where k = 'code1'),
  '972500000771@c.us', 'משרד בוואטסאפ') ->> 'ok', 'true');
select t_eq('המספר שייך עכשיו למשרד 77',
  (select profile_id from app.wa_sender('972500000771@c.us')), '20000000-0000-0000-0000-0000000077a1'::uuid);
select t_eq('ומותר לו לעבוד מול העוזר', (select allowed from app.wa_sender('972500000771@c.us')), true);
select t_eq('אותו קוד אינו נפדה פעמיים',
  app.wa_link_redeem((select v from w77 where k = 'code1'), '972500000772@c.us', 'x') ->> 'reason', 'bad_code');
select t_eq('ההתראה בפעמון יצאה',
  (select count(*)::int from notifications
    where recipient_id = '20000000-0000-0000-0000-0000000077a1' and type = 'whatsapp_linked'), 1);
select t_eq('והיא מובילה לעמוד ההתראות',
  (select link from notifications
    where recipient_id = '20000000-0000-0000-0000-0000000077a1' and type = 'whatsapp_linked'), '/my/notifications');
select t_eq('המספר בהתראה כתוב כמו בישראל',
  (select body like '%0500000771%' from notifications
    where recipient_id = '20000000-0000-0000-0000-0000000077a1' and type = 'whatsapp_linked'), true);

-- קוד שפג תוקפו
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000077a1', false);
insert into w77 select 'code2', wa_link_code_create() ->> 'code';
reset role;
select set_config('request.jwt.claim.sub', '', false);
update wa_link_codes set expires_at = now() - interval '1 minute'
 where profile_id = '20000000-0000-0000-0000-0000000077a1';
select t_eq('קוד שפג תוקפו נדחה',
  app.wa_link_redeem((select v from w77 where k = 'code2'), '972500000773@c.us', 'x') ->> 'reason', 'bad_code');

-- מספר חדש לאותו פרופיל משחרר את הקודם
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000077a1', false);
insert into w77 select 'code3', wa_link_code_create() ->> 'code';
reset role;
select set_config('request.jwt.claim.sub', '', false);
select t_eq('מספר שני לאותו פרופיל', app.wa_link_redeem((select v from w77 where k = 'code3'),
  '972500000774@c.us', null) ->> 'ok', 'true');
select t_eq('והמספר הקודם שוחרר', (select count(*)::int from app.wa_sender('972500000771@c.us')), 0);
select t_eq('קישור פעיל אחד לפרופיל',
  (select count(*)::int from wa_links
    where profile_id = '20000000-0000-0000-0000-0000000077a1' and revoked_at is null), 1);

-- אותו מספר עובר לפרופיל אחר (המתכנן): הקישור הקודם שלו מתנתק
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000077a3', false);
insert into w77 select 'code4', wa_link_code_create() ->> 'code';
reset role;
select set_config('request.jwt.claim.sub', '', false);
select t_eq('המספר עובר למתכנן', app.wa_link_redeem((select v from w77 where k = 'code4'),
  '972500000774@c.us', null) ->> 'ok', 'true');
select t_eq('ושייך לו בלבד', (select string_agg(profile_id::text, ',') from app.wa_sender('972500000774@c.us')),
  '20000000-0000-0000-0000-0000000077a3');
select t_eq('למשרד 77 לא נשאר קישור פעיל',
  (select count(*)::int from wa_links
    where profile_id = '20000000-0000-0000-0000-0000000077a1' and revoked_at is null), 0);

-- חזרה למצב: משרד 77 מקושר למספר 771
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000077a1', false);
insert into w77 select 'code5', wa_link_code_create() ->> 'code';
reset role;
select set_config('request.jwt.claim.sub', '', false);
select t_eq('משרד 77 מתחבר שוב', app.wa_link_redeem((select v from w77 where k = 'code5'),
  '972500000771@c.us', null) ->> 'ok', 'true');

-- מי שאיבד את המפתח: הקוד נצרך והקישור לא נוצר; ומי שמקושר — מאבד את ההיתר
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000077a1', false);
insert into w77 select 'code6', wa_link_code_create() ->> 'code';
reset role;
select set_config('request.jwt.claim.sub', '', false);
update user_permission_grants set allowed = false
 where profile_id = '20000000-0000-0000-0000-0000000077a1' and permission_key = 'assistant.whatsapp';
select t_eq('בלי המפתח — אין פדיון',
  app.wa_link_redeem((select v from w77 where k = 'code6'), '972500000775@c.us', null) ->> 'reason', 'not_allowed');
select t_eq('והקישור הקיים כבר לא מתיר עבודה', (select allowed from app.wa_sender('972500000771@c.us')), false);
update user_permission_grants set allowed = true
 where profile_id = '20000000-0000-0000-0000-0000000077a1' and permission_key = 'assistant.whatsapp';
update profiles set is_active = false where id = '20000000-0000-0000-0000-0000000077a1';
select t_eq('פרופיל לא פעיל — אין היתר', (select allowed from app.wa_sender('972500000771@c.us')), false);
update profiles set is_active = true where id = '20000000-0000-0000-0000-0000000077a1';
select t_eq('ובחזרה — יש', (select allowed from app.wa_sender('972500000771@c.us')), true);

-- חמישה ניסיונות כושלים בשעה — ואז גם קוד נכון נדחה
do $$ begin perform app.wa_link_redeem('000000', '972500000776@c.us', null) from generate_series(1, 5); end $$;
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000077a3', false);
insert into w77 select 'code7', wa_link_code_create() ->> 'code';
reset role;
select set_config('request.jwt.claim.sub', '', false);
select t_eq('אחרי חמישה כישלונות המספר נחסם לשעה',
  app.wa_link_redeem((select v from w77 where k = 'code7'), '972500000776@c.us', null) ->> 'reason', 'too_many');
select t_eq('ומספר אחר פודה את אותו קוד', app.wa_link_redeem((select v from w77 where k = 'code7'),
  '972500000777@c.us', null) ->> 'ok', 'true');

-- ===== 3. מי רואה מה =======================================================

\echo '--- מי רואה מה ---'
select app.wa_chat_dm('972500000771@c.us', 'משרד 77');
insert into wa_messages (message_id, direction, chat_id, wa_id, profile_id, body, status) values
  ('W77-MSG-1', 'in', '972500000771@c.us', '972500000771@c.us', '20000000-0000-0000-0000-0000000077a1', 'מה יש מחר?', 'answered'),
  ('W77-MSG-2', 'in', '972500000777@c.us', '972500000777@c.us', '20000000-0000-0000-0000-0000000077a3', 'שלום', 'answered');

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000077a1', false);
select t_eq('משרד 77 רואה את הקישור שלו בלבד',
  (select string_agg(profile_id::text, ',') from wa_links where revoked_at is null),
  '20000000-0000-0000-0000-0000000077a1');
select t_eq('ואת ההודעות שלו בלבד', (select string_agg(message_id, ',') from wa_messages
  where message_id like 'W77-%'), 'W77-MSG-1');
select t_eq('ואינו רואה את הצ''אטים', (select count(*)::int from wa_chats), 0);
select t_expect_fail('ואינו כותב קישור בעצמו', $$
  insert into wa_links (profile_id, wa_id) values ('20000000-0000-0000-0000-0000000077a1', '972500000770@c.us') $$);
select t_expect_fail('ואינו נוגע בפעולות הממתינות', $$ select * from wa_pending $$);
select t_expect_fail('ואינו מנתק את הקישור של אחר', $$
  select wa_unlink((select id from wa_links where profile_id = '20000000-0000-0000-0000-0000000077a3' and revoked_at is null)) $$);
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000077a2', false);
select t_eq('עובד 77 לא רואה קישורים', (select count(*)::int from wa_links where profile_id::text like '20000000-0000-0000-0000-0000000077%'), 0);
select t_eq('ולא הודעות', (select count(*)::int from wa_messages where message_id like 'W77-%'), 0);
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false);
select t_eq('מנהל מערכת רואה את כל ההודעות', (select count(*)::int from wa_messages where message_id like 'W77-%'), 2);
select t_eq('ואת הצ''אט הפרטי', (select count(*)::int from wa_chats where chat_id = '972500000771@c.us'), 1);
select t_expect_fail('גם מנהל אינו קורא את הקודים', $$ select * from wa_link_codes $$);
select t_expect_fail('והפונקציות הפנימיות סגורות', $$ select * from app.wa_sender('972500000771@c.us') $$);
reset role;
select set_config('request.jwt.claim.sub', '', false);

-- ===== 4. איפה מותר לענות ==================================================

\echo '--- משתתפי הקבוצה ---'
-- הבעלים (מנהל) מקושר למספר 701; הבוט הוא 999
insert into wa_links (profile_id, wa_id) values ('20000000-0000-0000-0000-000000000001', '972500000701@c.us');

select t_eq('הבוט ומשתמש מקושר — מותר',
  app.wa_participants_ok('[{"id":"972500000999@c.us"},{"id":"972500000701@c.us"}]'::jsonb, '972500000999@c.us'), true);
select t_eq('ועוד משתתף לא מוכר — אסור',
  app.wa_participants_ok('[{"id":"972500000999@c.us"},{"id":"972500000701@c.us"},{"id":"972500000888@c.us"}]'::jsonb,
                         '972500000999@c.us'), false);
update user_permission_grants set allowed = false
 where profile_id = '20000000-0000-0000-0000-0000000077a1' and permission_key = 'assistant.whatsapp';
select t_eq('(משרד 77 בלי המפתח) — אסור',
  app.wa_participants_ok('[{"id":"972500000701@c.us"},{"id":"972500000771@c.us"}]'::jsonb, '972500000999@c.us'), false);
update user_permission_grants set allowed = true
 where profile_id = '20000000-0000-0000-0000-0000000077a1' and permission_key = 'assistant.whatsapp';
select t_eq('משתתף שמזוהה רק ב-lid אינו מוכר',
  app.wa_participants_ok('[{"id":"972500000701@c.us"},{"id":"","lid":"12345678901234@lid","phoneNumber":""}]'::jsonb,
                         '972500000999@c.us'), false);
select t_eq('מזוהה לפי מספר הטלפון שבשדה phoneNumber',
  app.wa_participants_ok('[{"id":"12345678901234@lid","phoneNumber":"972500000701@c.us"}]'::jsonb, '972500000999@c.us'), true);
select t_eq('קבוצה בלי בני אדם — אסור', app.wa_participants_ok('[{"id":"972500000999@c.us"}]'::jsonb, '972500000999@c.us'), false);

select t_eq('נתוני כסף: הבעלים לבד — מותר',
  app.wa_participants_hold('[{"id":"972500000701@c.us"}]'::jsonb, '972500000999@c.us', array['pricing.revenue']), true);
select t_eq('ועם משרד 77, שאין לו את המפתח — אסור',
  app.wa_participants_hold('[{"id":"972500000701@c.us"},{"id":"972500000771@c.us"}]'::jsonb, '972500000999@c.us',
                           array['pricing.revenue']), false);

select t_expect_fail('רק מנהל מחבר קבוצה', $$
  select app.wa_chat_bind('120363000000000077@g.us', 'קבוצה 77', true, '20000000-0000-0000-0000-0000000077a1',
                          '[]'::jsonb, '972500000999@c.us') $$);
select t_eq('מנהל מחבר; כל המשתתפים מוכרים', app.wa_chat_bind('120363000000000077@g.us', 'קבוצה 77', true,
  '20000000-0000-0000-0000-000000000001',
  '[{"id":"972500000999@c.us"},{"id":"972500000701@c.us"},{"id":"972500000771@c.us"}]'::jsonb,
  '972500000999@c.us') ->> 'participants_ok', 'true');
select t_eq('נכנס משתתף זר — הבוט מפסיק לענות בה', app.wa_chat_participants_set('120363000000000077@g.us',
  '[{"id":"972500000999@c.us"},{"id":"972500000701@c.us"},{"id":"972500000888@c.us"}]'::jsonb, '972500000999@c.us'), false);
select t_eq('ונרשם', (select participants_ok from wa_chats where chat_id = '120363000000000077@g.us'), false);

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000077a1', false);
select t_expect_fail('משרד 77 אינו מנתק קבוצה', $$ select wa_chat_unbind('120363000000000077@g.us') $$);
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false);
select t_expect_ok('מנהל מנתק', $$ select wa_chat_unbind('120363000000000077@g.us') $$);
select t_eq('והקבוצה כבר לא פעילה', (select active from wa_chats where chat_id = '120363000000000077@g.us'), false);
select t_expect_ok('מנהל מנתק גם קישור של אחר', $$
  select wa_unlink((select id from wa_links where profile_id = '20000000-0000-0000-0000-0000000077a3' and revoked_at is null)) $$);
reset role;
select set_config('request.jwt.claim.sub', '', false);
select t_eq('מחברים שוב', app.wa_chat_bind('120363000000000077@g.us', null, true,
  '20000000-0000-0000-0000-000000000001', '[{"id":"972500000701@c.us"}]'::jsonb, '972500000999@c.us') ->> 'ok', 'true');
select t_expect_fail('"כבה כאן" ממי שאינו מנהל נדחה', $$
  select app.wa_chat_unbind('120363000000000077@g.us', '20000000-0000-0000-0000-0000000077a1') $$);
select t_eq('ומנהל מכבה', app.wa_chat_unbind('120363000000000077@g.us', '20000000-0000-0000-0000-000000000001'), true);
select t_eq('והשם נשמר מהחיבור הראשון', (select name from wa_chats where chat_id = '120363000000000077@g.us'), 'קבוצה 77');

-- ===== 5. מה שהבוט נשען עליו כשהוא כותב בשם המשתמש =========================

\echo '--- כתיבה בשם המשתמש ---'
insert into w77 select 'setup', t.id::text from tasks t
 where t.event_id = '30000000-0000-0000-0000-00000000077a'
   and t.task_type_id = (select id from task_types where code = 'setup' limit 1);

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000077a3', false);
select t_expect_fail('שורת deny מפורשת ל-tasks.reschedule חוסמת שינוי שעה, גם עם tasks.edit', $$
  update tasks set onsite_start_time = '09:00' where id = (select v::uuid from w77 where k = 'setup') $$);
reset role;
select set_config('request.jwt.claim.sub', '', false);
update user_permission_grants set allowed = true
 where profile_id = '20000000-0000-0000-0000-0000000077a3' and permission_key = 'tasks.reschedule';

-- הרצת ניסיון: השינוי וההתראה לעובד נבלעים כשהטרנזקציה (כאן: תת-טרנזקציה) מתבטלת
create or replace function t77_dryrun(p_task uuid) returns text language plpgsql as $$
declare n int;
begin
  begin
    update tasks set onsite_start_time = '10:00' where id = p_task;
    get diagnostics n = row_count;
    raise exception 'rollback %', n;
  exception when others then
    return sqlerrm;
  end;
end $$;
grant execute on function t77_dryrun(uuid) to authenticated;

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000077a3', false);
select t_eq('הרצת הניסיון נגעה בשורה אחת', t77_dryrun((select v::uuid from w77 where k = 'setup')), 'rollback 1');
reset role;
select t_eq('ולא השאירה דבר: השעה נשארה', (select onsite_start_time::text from tasks
  where id = (select v::uuid from w77 where k = 'setup')), '08:00:00');
select t_eq('ולא התראה לעובד', (select count(*)::int from notifications
  where recipient_id = '20000000-0000-0000-0000-0000000077a2' and type = 'task_time_changed'), 0);

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000077a3', false);
select t_rows('השינוי האמיתי, עם updated_at כתנאי (כמו הלוח)', $$
  update tasks set onsite_start_time = '10:00'
   where id = (select v::uuid from w77 where k = 'setup')
     and updated_at = (select updated_at from tasks where id = (select v::uuid from w77 where k = 'setup')) $$, 1);
select t_rows('תנאי updated_at ישן — אפס שורות', $$
  update tasks set onsite_start_time = '11:00'
   where id = (select v::uuid from w77 where k = 'setup')
     and updated_at = '2000-01-01'::timestamptz $$, 0);
reset role;
select t_eq('והעובד קיבל התראה אחת', (select count(*)::int from notifications
  where recipient_id = '20000000-0000-0000-0000-0000000077a2' and type = 'task_time_changed'), 1);

-- משימה חדשה: אופן הביצוע ברירת המחדל נכנס כשהבוט שולח את customer_id
select t_eq('ללקוח יש אופן ביצוע ברירת מחדל להקמה', (select count(*)::int from customer_execution_methods
  where customer_id = '10000000-0000-0000-0000-00000000077a' and is_default_setup), 1);
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000077a3', false);
with x as (
  insert into tasks (event_id, customer_id, task_type_id, task_date, status_id)
  values ('30000000-0000-0000-0000-00000000077a', '10000000-0000-0000-0000-00000000077a',
          (select id from task_types where code = 'setup' limit 1), current_date + 1300,
          (select id from statuses where entity = 'task' and code = 'draft' and deleted_at is null))
  returning id)
insert into w77 select 'with_customer', id::text from x;
reset role;
select t_eq('עם customer_id — אופן הביצוע של הלקוח',
  (select execution_method_id from tasks where id = (select v::uuid from w77 where k = 'with_customer')),
  (select execution_method_id from customer_execution_methods
    where customer_id = '10000000-0000-0000-0000-00000000077a' and is_default_setup));

-- שינוי תאריך האירוע לבדו אינו מזיז את המשימות (הבוט מזיז אותן בנפרד)
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false);
set role authenticated;
select t_expect_ok('update_event עם event_date בלבד', $$
  select update_event('30000000-0000-0000-0000-00000000077a', jsonb_build_object('event_date', current_date + 1301)) $$);
reset role;
select set_config('request.jwt.claim.sub', '', false);
select t_eq('ההקמה נשארה בתאריך שלה', (select task_date from tasks
  where id = (select v::uuid from w77 where k = 'setup')), current_date + 1300);

-- ===== 6. פעולה ממתינה נתפסת פעם אחת ======================================

\echo '--- פעולה ממתינה ---'
insert into wa_pending (chat_id, profile_id, ops, preview)
values ('972500000771@c.us', '20000000-0000-0000-0000-0000000077a1', '[]'::jsonb, array['x']);
select t_eq('פעולה פתוחה אחת לאדם בצ''אט', (select count(*)::int from wa_pending
  where chat_id = '972500000771@c.us' and status in ('pending', 'running')), 1);
select t_expect_fail('שנייה באותו צ''אט נדחית', $$
  insert into wa_pending (chat_id, profile_id, ops, preview)
  values ('972500000771@c.us', '20000000-0000-0000-0000-0000000077a1', '[]'::jsonb, array['y']) $$);
select t_rows('האישור הראשון תופס אותה', $$
  update wa_pending set status = 'running'
   where chat_id = '972500000771@c.us' and profile_id = '20000000-0000-0000-0000-0000000077a1'
     and status = 'pending' and expires_at > now() $$, 1);
select t_rows('והשני כבר לא', $$
  update wa_pending set status = 'running'
   where chat_id = '972500000771@c.us' and profile_id = '20000000-0000-0000-0000-0000000077a1'
     and status = 'pending' and expires_at > now() $$, 0);
update wa_pending set status = 'done', finished_at = now() where chat_id = '972500000771@c.us';

drop function t77_dryrun(uuid);
