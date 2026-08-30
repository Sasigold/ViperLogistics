-- 0127: המכסה סופרת שורה פעם אחת, ולא פעמיים
--
-- הדיווח: "קבלן לא מצליח לשבץ ראש צוות כשהוא עובד יחיד — נרשם שכמות העובדים
-- חורגת".
--
-- ‏`tcw_limit` הוא `before insert` (0003), אבל מאז 0121 הכתיבה של
-- `contractor_assign_worker` היא `insert ... on conflict do update`: אותה
-- שורה נכתבת שוב כדי לשנות `work_site` או `role`. בפוסטגרס טריגר
-- `before insert` רץ **לפני** שההתנגשות מתגלה, ולכן הוא רץ גם בנתיב העדכון —
-- ובאותו רגע `v_current` כבר סופר את השורה שעומדת להתעדכן. קבלן שאמור להביא
-- עובד אחד, שיבץ אותו, ואז בחר לו "ראש צוות" — נמדד כשניים.
--
-- **המכסה היא על אנשים, לא על כתיבות.** ולכן התיקון אינו בספירה אלא בשאלה
-- מה נספר: עדכון של צמד שכבר קיים אינו ראש חדש על המשימה, והטריגר מדלג עליו.
-- ראש צוות של קבלן ממשיך להיספר במכסה ככל עובד אחר — הוא אדם שהקבלן מביא,
-- וזה גם מה ש-`app.recompute_contractor_price` (0108) מתמחר.
--
-- הגוף זהה ל-0097 מילה במילה, בתוספת הדילוג — ובתוספת `set search_path`,
-- שהיה על הפונקציה מ-0008 ואבד כש-0097 כתבה אותה מחדש בלעדיו.

create or replace function app.check_contractor_worker_limit()
returns trigger language plpgsql set search_path = public as $$
declare
  v_ctr uuid;
  v_limit int;
  v_current int;
begin
  -- עדכון של שורה קיימת (work_site / role) אינו מוסיף אדם למשימה.
  if exists (select 1 from task_contractor_workers
              where task_id = new.task_id
                and contractor_worker_id = new.contractor_worker_id) then
    return new;
  end if;

  select contractor_id into v_ctr from contractor_workers where id = new.contractor_worker_id;
  select coalesce(tct.contractor_worker_count, t.worker_count) into v_limit
    from tasks t
    left join task_contractor_terms tct on tct.task_id = t.id and tct.contractor_id = v_ctr
   where t.id = new.task_id;
  select count(*) into v_current
    from task_contractor_workers tcw
    join contractor_workers cw on cw.id = tcw.contractor_worker_id
   where tcw.task_id = new.task_id and cw.contractor_id = v_ctr;
  if v_limit is not null and v_limit > 0 and v_current >= v_limit then
    raise exception 'חריגה מכמות העובדים שהקבלן אמור להביא (%)', v_limit;
  end if;
  return new;
end $$;

comment on function app.check_contractor_worker_limit() is
  'תקרת שיבוץ עובדי קבלן (0093/0097). מ-0127 היא מדלגת על עדכון של צמד קיים, '
  'כי on conflict do update מפעיל גם הוא טריגר before insert.';
