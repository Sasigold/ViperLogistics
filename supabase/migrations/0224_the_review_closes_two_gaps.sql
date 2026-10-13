-- 0224: הסקירה סוגרת שני פתחים ב-0223
--
-- ‏Codex על PR #40:
--
--   1. **`app.payslip_ni_brackets_for` פנימית.** היא definer, וההרשאה ל-
--      authenticated אפשרה לכל משתמש מחובר לקרוא דרכה את המדרגות — מעבר ל-RLS
--      של `payslip_ni_bracket_sets` (`payslips.employer_cost`). רק הטריגר קורא לה,
--      ולכן ההרשאה נשללת.
--
--   2. **אין חפיפה גם בשמירות במקביל.** שתי שמירות בו-זמנית היו עוברות שתיהן את
--      בדיקת החפיפה לפני שאחת מהן נכתבה. `payslip_ni_set_save` ו-
--      `payslip_ni_brackets_save` נועלות נעילת ייעוץ לטרנזקציה לפני הבדיקה, כך
--      שהשמירות עוברות אחת-אחת.

-- ===== 1. העזר — פנימי =====================================================

revoke execute on function app.payslip_ni_brackets_for(date) from anon, authenticated, public;

-- ===== 2. שמירה אחת בכל פעם ================================================

-- payslip_ni_set_save (0223 §4) — אותו גוף, ונעילה לפני בדיקת החפיפה.
create or replace function payslip_ni_set_save(
  p_id uuid, p_valid_from date, p_valid_to date, p_brackets jsonb)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_from date := date_trunc('month', p_valid_from)::date;
  v_to   date := date_trunc('month', p_valid_to)::date;
  v_br   jsonb;
  v_id   uuid := p_id;
begin
  if not app.can_view_payslip_costs() then
    raise exception 'אין לך הרשאה לערוך את מדרגות הביטוח הלאומי' using errcode = '42501';
  end if;
  -- כתיבה אחת בכל פעם: שתי שמירות במקביל היו עוברות שתיהן את בדיקת החפיפה
  perform pg_advisory_xact_lock(hashtext('payslip_ni_bracket_sets'));
  if v_from is null then
    raise exception 'יש לבחור חודש תחולה';
  end if;
  if v_to is not null and v_to < v_from then
    raise exception 'חודש התפוגה לפני חודש התחולה';
  end if;
  v_br := app.payslip_ni_normalize(p_brackets);
  if jsonb_array_length(v_br) = 0 then
    raise exception 'יש להזין לפחות מדרגה אחת';
  end if;
  if v_id is not null and not exists (
       select 1 from payslip_ni_bracket_sets where id = v_id and deleted_at is null) then
    raise exception 'התקופה לא נמצאה';
  end if;
  if exists (
       select 1 from payslip_ni_bracket_sets s
        where s.deleted_at is null
          and s.id is distinct from v_id
          and s.valid_from <= coalesce(v_to, 'infinity'::date)
          and coalesce(s.valid_to, 'infinity'::date) >= v_from) then
    raise exception 'התקופה חופפת לתקופה אחרת של מדרגות — יש לקצר אחת מהן';
  end if;

  if v_id is null then
    insert into payslip_ni_bracket_sets (valid_from, valid_to, brackets, created_by, updated_by)
    values (v_from, v_to, v_br, app.profile_id(), app.profile_id())
    returning id into v_id;
  else
    update payslip_ni_bracket_sets set
      valid_from = v_from, valid_to = v_to, brackets = v_br, updated_by = app.profile_id()
    where id = v_id;
  end if;

  perform app.payslip_ni_recompute();
  return v_id;
end $$;

revoke execute on function payslip_ni_set_save(uuid, date, date, jsonb) from anon, public;
grant  execute on function payslip_ni_set_save(uuid, date, date, jsonb) to authenticated;

-- payslip_ni_brackets_save (0223 §4) — אותו גוף, ואותה נעילה.
create or replace function payslip_ni_brackets_save(p_brackets jsonb)
returns int language plpgsql security definer set search_path = public as $$
declare v_br jsonb;
begin
  if not app.can_view_payslip_costs() then
    raise exception 'אין לך הרשאה לערוך את מדרגות הביטוח הלאומי' using errcode = '42501';
  end if;
  -- כתיבה אחת בכל פעם: שתי שמירות במקביל היו עוברות שתיהן את בדיקת החפיפה
  perform pg_advisory_xact_lock(hashtext('payslip_ni_bracket_sets'));
  v_br := app.payslip_ni_normalize(p_brackets);
  update payslip_ni_bracket_sets set deleted_at = now(), deleted_by = app.profile_id()
   where deleted_at is null;
  if jsonb_array_length(v_br) > 0 then
    insert into payslip_ni_bracket_sets (valid_from, valid_to, brackets, created_by, updated_by)
    values ('2000-01-01', null, v_br, app.profile_id(), app.profile_id());
  end if;
  return app.payslip_ni_recompute();
end $$;

revoke execute on function payslip_ni_brackets_save(jsonb) from anon, public;
grant  execute on function payslip_ni_brackets_save(jsonb) to authenticated;
