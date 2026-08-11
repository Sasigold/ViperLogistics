-- ===========================================================================
-- 0057 — רשומת תשלום לקבלן אינה נמחקת בהיסח הדעת
-- ===========================================================================
--
-- app.sync_contractor_terms (הוגדרה ב-0003, נוכחית מ-0012) מסנכרנת את
-- task_contractor_terms עם tasks.contractor_id, ועד עכשיו עשתה זאת גם
-- כשהרשומה כבר סומנה כשולמה: הסרת קבלן מחקה את השורה על ה-paid_at
-- וה-paid_amount שבה, והחלפת קבלן איפסה אותם דרך on conflict do update.
-- בשני המקרים רשומת תשלום כספית נעלמת כתוצאת לוואי של עריכת משימה.
--
-- ההכרעה — סירוב מפורש ולא שימור השורה: שורת terms שמצביעה על קבלן שכבר
-- אינו על המשימה סותרת את ההנחה של כל מי שקורא אותה (הפורטל, מסך הקבלן,
-- הדוחות). במקום זה ההסרה נחסמת עד שמבטלים את סימון התשלום במפורש —
-- אותו תקדים של טריגר מגבלת העובדים ב-0003. ההודעה בעברית עוברת
-- כמות-שהיא דרך errorMessage() אל הטוסט.
--
-- הבדיקה יושבת לפני app.system_write(true): חריגה מפילה את כל ה-statement
-- ולכן אין צורך בניקוי הדגל.

create or replace function app.sync_contractor_terms()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'UPDATE' and old.contractor_id is not null
     and old.contractor_id is distinct from new.contractor_id
     and exists (select 1 from task_contractor_terms
                  where task_id = new.id and paid_at is not null) then
    raise exception 'לא ניתן להסיר או להחליף קבלן במשימה שכבר שולם עליה. בטל תחילה את סימון התשלום בכרטיס הקבלן.';
  end if;
  perform app.system_write(true);
  if new.contractor_id is not null and
     (tg_op = 'INSERT' or old.contractor_id is distinct from new.contractor_id) then
    insert into task_contractor_terms (task_id, contractor_id, price)
    values (new.id, new.contractor_id,
            coalesce((select default_task_price from contractors where id = new.contractor_id), 0))
    on conflict (task_id) do update
      set contractor_id = excluded.contractor_id, price = excluded.price,
          paid_at = null, paid_amount = null;
    if tg_op = 'UPDATE' and old.contractor_id is not null then
      delete from task_contractor_workers where task_id = new.id;
    end if;
  elsif new.contractor_id is null and tg_op = 'UPDATE' and old.contractor_id is not null then
    delete from task_contractor_terms where task_id = new.id;
    delete from task_contractor_workers where task_id = new.id;
  end if;
  perform app.system_write(false);
  return new;
end $$;
