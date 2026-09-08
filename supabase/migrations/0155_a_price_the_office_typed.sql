-- 0155: מחיר לקבלן שהמשרד הקליד, ושהמנוע אינו דורס
--
-- מחיר הקבלן מחושב מאז 0091: תעריף לעובד × מספר העובדים, או מחיר הובלה,
-- או מחיר ברירת מחדל — ועליו תוספת מחסן ומינוס קנסות.
-- ‏`app.recompute_contractor_price` רצה על כל שינוי שנוגע בחשבון (שיבוץ עובד,
-- אי-התייצבות, שינוי תעריף, שינוי הגדרות הקבלן) וכותבת את התוצאה ל-`price`.
--
-- מה שלא היה אפשרי הוא לומר "לא במשימה הזו". קבלן שמוגדר לו תעריף לעובד —
-- וכזה הוא רוב הקטלוג — נעל את שדה המחיר במסך, וכל מספר שהוקלד בו נדרס
-- בחישוב הבא. משימה חריגה (יום ארוך במיוחד, סיכום טלפוני, פיצוי מוסכם)
-- נשארה בלי דרך להיכתב, ומי שרצה אותה נאלץ לשנות את התעריף של הקבלן כולו,
-- לתקן את המחיר, ולהחזיר — כלומר לזייף את ההגדרה לכל שאר המשימות שלו.
--
-- שלוש הכרעות:
--
-- 1. **דגל, ולא "מחיר שנכתב ידנית מזוהה לפי שוני".** ניחוש לפי הפרש מהחישוב
--    היה הופך כל שינוי בהגדרות הקבלן לדריסה שקטה או להקפאה שקטה, ואיש לא
--    היה יודע איזו מהן. `price_is_manual` הוא הצהרה: המספר הזה של המשרד.
--    זו אותה הכרעה בדיוק ש-`tasks.price_is_manual` (0017) עשתה בצד הלקוח.
--
-- 2. **מחיר ידני מוחק את הפירוט.** `price_parts` מתאר ממה הסכום מורכב —
--    בסיס, תוספת מחסן, קנסות — ומספר שהוקלד אינו מורכב מכלום. השארתו שם
--    הייתה מציגה למנהל פירוט שאינו מסתכם למספר שלידו. הקנסות אינם נעלמים
--    מהעולם: הם מוצגים בכרטיס העובדים ובדוחות, ומי שמקליד מחיר ידני מקליד
--    את מה שסוכם *במקום* החישוב.
--
-- 3. **`contractors.edit_pricing` ולא מפתח חדש.** זה המפתח של `price` עצמו
--    ב-`field_registry` מאז 0011, והדגל אינו יכולת אחרת — הוא אותה יכולת
--    בדיוק, על אותו שדה.

-- ===== 1. הדגל ===========================================================

alter table task_contractor_terms
  add column price_is_manual boolean not null default false;

comment on column task_contractor_terms.price_is_manual is
  'המחיר הוקלד ידנית ואינו מחושב. app.recompute_contractor_price מדלגת על '
  'השורה ומוחקת את price_parts, בדיוק כמו tasks.price_is_manual בצד הלקוח.';

-- הרישום הוא מה שמצמיד את הדגל להרשאה של המחיר עצמו: `enforce_field_perms`
-- (הטריגר יושב על הטבלה מ-0017) עוצרת כל מי שאין לו `contractors.edit_pricing`
-- על השדה הזה, בדיוק כפי שהיא עוצרת אותו על `price`. בלי השורה הזו מי
-- שמחזיק `contractors.mark_paid` בלבד — שגם הוא עובר את פוליסת הכתיבה —
-- היה יכול לשחרר את המחיר מהמנוע.
select app.register_field('task_terms', 'price_is_manual', 'מחיר ידני', 'contractors',
  'task_contractor_terms', 'price_is_manual', true, true, true, 'contractors.edit_pricing', 15);
select app.rebuild_secure_view('task_contractor_terms');

-- ===== 2. המנוע מכבד את מה שהוקלד ========================================
--
-- הגוף זהה ל-0108 פרט לענף אחד בראשו. הוא יושב אחרי היציאה על `paid_at`
-- ולפני כל שאר החישוב, כי שתי היציאות אומרות את אותו דבר: השורה הזו כבר
-- הוכרעה בידי אדם.
create or replace function app.recompute_contractor_price(p_task_id uuid, p_contractor_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_ct        contractors%rowtype;
  v_terms     task_contractor_terms%rowtype;
  v_task      tasks%rowtype;
  v_count     int     := 0;
  v_base      numeric := 0;
  v_surcharge numeric := 0;
  v_late      int     := 0;
  v_noshow    int     := 0;
  v_price     numeric;
  v_rate      numeric;
  v_transport boolean;
  v_active    boolean;
  v_grace     int;
  v_prev      boolean;
begin
  select * into v_terms from task_contractor_terms
   where task_id = p_task_id and contractor_id = p_contractor_id;
  if v_terms.task_id is null then return; end if;
  if v_terms.paid_at is not null then return; end if;

  -- ‏0155: מחיר ידני. המספר נשאר כפי שהוקלד, והפירוט יורד — הוא תיאר חישוב
  -- שאינו מה שמשולם. הניקוי נעשה כאן ולא בטריגר, כדי שגם שינוי מאוחר
  -- בהגדרות הקבלן — שקורא לפונקציה הזו — לא ישאיר פירוט ישן על השורה.
  if v_terms.price_is_manual then
    if v_terms.price_parts is not null then
      v_prev := app.in_system_write();
      perform app.system_write(true);
      update task_contractor_terms set price_parts = null
       where task_id = p_task_id and contractor_id = p_contractor_id;
      perform app.system_write(v_prev);
    end if;
    return;
  end if;

  select * into v_ct from contractors where id = p_contractor_id;
  if v_ct.id is null then return; end if;

  select * into v_task from tasks where id = p_task_id;

  v_transport := exists (select 1 from execution_methods em
                          where em.id = v_task.execution_method_id and em.is_transport_only);

  v_rate := coalesce(v_terms.price_per_worker, v_ct.price_per_worker);

  v_active := v_rate is not null
           or (v_transport and v_ct.transport_only_price is not null)
           or v_ct.warehouse_arrival_surcharge is not null
           or v_ct.lateness_penalty is not null
           or v_ct.no_show_penalty is not null;
  if not v_active then return; end if;

  -- רק העובדים של הקבלן הזה במשימה.
  select count(*) into v_count
    from task_contractor_workers tcw
    join contractor_workers cw on cw.id = tcw.contractor_worker_id
   where tcw.task_id = p_task_id and cw.contractor_id = p_contractor_id;

  if v_transport and v_ct.transport_only_price is not null then
    v_base := v_ct.transport_only_price;
  elsif v_rate is not null then
    v_base := v_rate * v_count;
  else
    v_base := coalesce(v_ct.default_task_price, 0);
  end if;

  if not v_transport and v_terms.work_site = 'warehouse' then
    v_surcharge := coalesce(v_ct.warehouse_arrival_surcharge, 0) * v_count;
  end if;

  v_grace := coalesce(v_ct.lateness_grace_minutes, 0);
  select coalesce(count(*) filter (
      where x.lateness_tracked and x.clock_in_at is not null and x.shift_start is not null
        and x.clock_in_at > x.shift_start + make_interval(mins => v_grace)), 0)
    into v_late
    from (
      select cw.lateness_tracked, e.clock_in_at, e.shift_start
        from task_contractor_workers tcw
        join contractor_workers cw on cw.id = tcw.contractor_worker_id
        left join profiles p on p.contractor_worker_id = cw.id and p.deleted_at is null
        left join lateral (
          select ae.clock_in_at, ae.shift_start
            from attendance_entries ae
           where ae.profile_id = p.id and ae.deleted_at is null
             and ae.status <> 'rejected' and p_task_id = any(ae.task_ids)
           order by ae.clock_in_at limit 1
        ) e on true
       where tcw.task_id = p_task_id and cw.contractor_id = p_contractor_id
    ) x;

  select coalesce(count(*) filter (where tcw.no_show), 0) into v_noshow
    from task_contractor_workers tcw
    join contractor_workers cw on cw.id = tcw.contractor_worker_id
   where tcw.task_id = p_task_id and cw.contractor_id = p_contractor_id;

  /* בלי ריצפה: קנס שגדול מהמחיר הוא חוב, ומספר שלילי הוא הדרך היחידה
     להעביר אותו הלאה אל סיכום הכספים ואל דוח הרווחיות. */
  v_price := round(
    v_base + v_surcharge
    - coalesce(v_ct.lateness_penalty, 0) * v_late
    - coalesce(v_ct.no_show_penalty, 0) * v_noshow, 2);

  v_prev := app.in_system_write();
  perform app.system_write(true);
  update task_contractor_terms
     set price = v_price,
         price_parts = jsonb_build_object(
           'base', round(v_base, 2), 'surcharge', round(v_surcharge, 2),
           'worker_count', v_count, 'transport', v_transport,
           'late_count', v_late, 'late_penalty_each', coalesce(v_ct.lateness_penalty, 0),
           'noshow_count', v_noshow, 'noshow_penalty_each', coalesce(v_ct.no_show_penalty, 0),
           'penalty_total', round(coalesce(v_ct.lateness_penalty, 0) * v_late
                                  + coalesce(v_ct.no_show_penalty, 0) * v_noshow, 2))
   where task_id = p_task_id and contractor_id = p_contractor_id;
  perform app.system_write(v_prev);
end $$;

comment on function app.recompute_contractor_price(uuid, uuid) is
  'מחיר הקבלן: בסיס/הובלה/לפי-עובד + תוספת מחסן×עובדים − קנסות איחור (אוטומטי) '
  'ואי-התייצבות (ידני). ללא ריצפת אפס (0108) — קנס גדול מהמחיר נשאר חוב. '
  'מ-0155 שורה עם price_is_manual אינה מחושבת כלל.';

-- ===== 3. כיבוי הדגל מחזיר את החישוב =====================================
--
-- בלי זה המחיר הידני היה נשאר על השורה גם אחרי שהמשרד ביטל את הידני, עד
-- שמישהו ייגע בשיבוץ. הטריגר יושב לצד `tct_rate_sync` ובאותה צורה: תנאי על
-- העמודה שהשתנתה, ואז אותה קריאה אחת.
--
-- ההדלקה אינה קוראת לחישוב במכוון — היא באה עם מספר שהמשרד הקליד, ופירוט
-- ישן שנשאר עליה ייעלם בחישוב הבא ממילא. גם היא עוברת כאן כדי שהניקוי לא
-- ימתין לו: הפונקציה מזהה `price_is_manual` ומוחקת את `price_parts`.
create or replace function app.tct_manual_sync()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.price_is_manual is distinct from old.price_is_manual then
    perform app.recompute_contractor_price(new.task_id, new.contractor_id);
  end if;
  return new;
end $$;

drop trigger if exists tct_manual_sync on task_contractor_terms;
create trigger tct_manual_sync after update of price_is_manual on task_contractor_terms
  for each row execute function app.tct_manual_sync();
