-- 0221: הסקירה סוגרת שלושה פתחים ב-0220
--
-- ‏Codex על PR #39:
--
--   1. **עובד קבלן בלי כניסה אינו ברשימה.** פרופיל `contractor_user` נוצר לפני
--      שהכניסה נפתחת (`ContractorDetailPage`), ואם פתיחת הכניסה נכשלה נשאר
--      פרופיל פעיל בלי `user_id` — תלוש ששויך אליו לא היה נראה לאיש.
--      `app.payslip_assignable` ו-`payslip_assignees()` דורשים `user_id` לעובד
--      קבלן. (איש צוות — כמו ב-0218: גם בלי כניסה עדיין, הכניסה נפתחת בנפרד.)
--
--   2. **"ללא שיוך" רק לתלוש.** עמוד שהקריאה זיהתה כ"לא תלוש" נסגר בהסרה
--      (`payslip_remove`), לא בסימון — אחרת היה נספר בסיכומי החודש כתלוש ששולם.
--
--   3. **קיבוץ מחדש אינו מוחק "ללא שיוך".** `payslip_apply_reading` מסרבת גם
--      כשבקובץ יש תלוש שסומן "ללא שיוך" (היא פותחת את התלושים מחדש מהעמודים,
--      והסימון היה הולך לאיבוד). המסך קורא במקרה הזה רק את הסכומים
--      (`payslip_refresh_amounts`), כמו בקובץ שיש בו תלוש משויך.

-- ===== 1. עובד קבלן — רק עם כניסה ==========================================

create or replace function app.payslip_assignable(p_profile_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from profiles
                  where id = p_profile_id and deleted_at is null and is_active
                    and (user_kind = 'staff' or (user_kind = 'contractor_user' and user_id is not null)))
$$;

revoke execute on function app.payslip_assignable(uuid) from anon, public;
grant  execute on function app.payslip_assignable(uuid) to authenticated;

-- payslip_assignees (0220 §2) — אותו גוף, ועובד קבלן רק עם כניסה.
create or replace function payslip_assignees()
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not app.can_manage_payslips() then
    raise exception 'אין לך הרשאה לנהל תלושי שכר' using errcode = '42501';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'id',              p.id,
             'full_name',       p.full_name,
             'user_kind',       p.user_kind,
             'contractor_name', c.name)
           order by (p.user_kind <> 'staff'), c.name nulls first, p.full_name)
      from profiles p
      left join contractors c on c.id = p.contractor_id and p.user_kind = 'contractor_user'
     where p.deleted_at is null and p.is_active
       and (p.user_kind = 'staff' or (p.user_kind = 'contractor_user' and p.user_id is not null))), '[]'::jsonb);
end $$;

revoke execute on function payslip_assignees() from anon, public;
grant  execute on function payslip_assignees() to authenticated;

-- ===== 2. "ללא שיוך" רק לתלוש ==============================================

-- payslip_skip (0220 §3) — אותו גוף, ועמוד "לא תלוש" נדחה.
create or replace function payslip_skip(p_payslip_id uuid, p_skip boolean default true)
returns void language plpgsql security definer set search_path = public as $$
declare v_slip payslips;
begin
  if not app.can_manage_payslips() then
    raise exception 'אין לך הרשאה לנהל תלושי שכר' using errcode = '42501';
  end if;
  select * into v_slip from payslips where id = p_payslip_id and deleted_at is null for update;
  if not found then
    raise exception 'התלוש לא נמצא';
  end if;
  if coalesce(p_skip, true) and v_slip.profile_id is not null then
    raise exception 'התלוש משויך לעובד — יש לבטל את השיוך קודם';
  end if;
  if coalesce(p_skip, true) and v_slip.detected_kind = 'other' then
    raise exception 'העמוד אינו תלוש — יש להסיר אותו ("לא תלוש") ולא לסמן "ללא שיוך"';
  end if;
  update payslips set
    skipped_at = case when coalesce(p_skip, true) then now() end,
    skipped_by = case when coalesce(p_skip, true) then app.profile_id() end
  where id = p_payslip_id;
end $$;

revoke execute on function payslip_skip(uuid, boolean) from anon, public;
grant  execute on function payslip_skip(uuid, boolean) to authenticated;

-- ===== 3. קיבוץ מחדש אינו מוחק "ללא שיוך" =================================

-- payslip_apply_reading (0219 §5) — אותו גוף; מסרבת גם כשסומן "ללא שיוך".
create or replace function payslip_apply_reading(p_batch_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_batch    payslip_batches;
  v_me       uuid := app.profile_id();
  v_read     int;
  p          int;
  r          jsonb;
  cur        jsonb;
  v_groups   jsonb := '[]'::jsonb;
  v_join     boolean;
  v_conflict boolean;
  v_same     boolean;
  v_idx      int;
  g          jsonb;
  a          jsonb;
  v_id       uuid;
  v_detected date;
  v_rk       text;
  v_ck       text;
begin
  if not app.can_manage_payslips() then
    raise exception 'אין לך הרשאה לנהל תלושי שכר' using errcode = '42501';
  end if;
  select * into v_batch from payslip_batches where id = p_batch_id and deleted_at is null for update;
  if not found then
    raise exception 'הקובץ לא נמצא';
  end if;
  if exists (select 1 from payslips
              where batch_id = p_batch_id and deleted_at is null
                and (profile_id is not null or skipped_at is not null)) then
    raise exception 'כבר שויכו תלושים מהקובץ הזה (או סומנו "ללא שיוך") — הקריאה אינה מחלקת אותו מחדש';
  end if;
  select count(*) into v_read from payslip_page_readings where batch_id = p_batch_id;
  if v_read = 0 then
    raise exception 'הקובץ עוד לא נקרא';
  end if;

  for p in 1 .. v_batch.page_count loop
    r := (select reading from payslip_page_readings where batch_id = p_batch_id and page_no = p);
    v_join := false;

    if cur is not null and r is not null
       and cur ->> 'kind' = 'payslip' and r ->> 'kind' = 'payslip' then
      v_rk := app.payslip_name_key(r ->> 'employee_name');
      v_ck := app.payslip_name_key(cur ->> 'employee_name');
      v_conflict :=
           (r ->> 'employee_no' is not null and cur ->> 'employee_no' is not null
            and r ->> 'employee_no' <> cur ->> 'employee_no')
        or (v_rk is not null and v_ck is not null and v_rk <> v_ck)
        or (r ->> 'period' is not null and cur ->> 'period' is not null
            and r ->> 'period' <> cur ->> 'period');
      v_same :=
           (r ->> 'employee_no' is not null and r ->> 'employee_no' = cur ->> 'employee_no')
        or (r ->> 'employee_no' is null and cur ->> 'employee_no' is null
            and v_rk is not null and v_rk = v_ck);
      v_idx := case when r ->> 'page_index' ~ '^[0-9]{1,3}$' then (r ->> 'page_index')::int end;
      v_join := not v_conflict and ((v_idx is not null and v_idx > 1) or (v_idx is null and v_same));
    end if;

    if v_join then
      cur := cur
        || jsonb_build_object('to', p)
        || jsonb_strip_nulls(jsonb_build_object(
             'employee_name', coalesce(cur ->> 'employee_name', r ->> 'employee_name'),
             'employee_no',   coalesce(cur ->> 'employee_no', r ->> 'employee_no'),
             'period',        coalesce(cur ->> 'period', r ->> 'period')))
        || jsonb_build_object('amounts',
             coalesce(cur -> 'amounts', '{}'::jsonb)
             || jsonb_strip_nulls(case when jsonb_typeof(r -> 'amounts') = 'object'
                                       then r -> 'amounts' else '{}'::jsonb end));
    else
      if cur is not null then
        v_groups := v_groups || jsonb_build_array(cur);
      end if;
      cur := jsonb_strip_nulls(jsonb_build_object(
        'from',          p,
        'to',            p,
        'kind',          case when r ->> 'kind' in ('payslip', 'other') then r ->> 'kind' end,
        'employee_name', nullif(btrim(r ->> 'employee_name'), ''),
        'employee_no',   nullif(btrim(r ->> 'employee_no'), ''),
        'period',        r ->> 'period'))
        || jsonb_build_object('amounts',
             jsonb_strip_nulls(case when jsonb_typeof(r -> 'amounts') = 'object'
                                    then r -> 'amounts' else '{}'::jsonb end));
    end if;
  end loop;
  v_groups := v_groups || jsonb_build_array(cur);

  -- אף תלוש בקובץ לא שויך (נבדק למעלה), ולכן אף עובד לא ראה אותם. הם
  -- יורדים בהסרה רכה ונפתחים מחדש מהעמודים (0218 §7).
  update payslips set deleted_at = now(), deleted_by = v_me
   where batch_id = p_batch_id and deleted_at is null;

  for g in select value from jsonb_array_elements(v_groups) loop
    v_detected := app.payslip_period(g ->> 'period');
    insert into payslips (
      batch_id, page_from, page_to, period,
      detected_kind, detected_name, detected_employee_no, detected_period, link_key)
    values (
      p_batch_id, (g ->> 'from')::int, (g ->> 'to')::int, coalesce(v_detected, v_batch.period),
      g ->> 'kind', left(g ->> 'employee_name', 120), left(g ->> 'employee_no', 40), v_detected,
      case when g ->> 'kind' = 'payslip'
           then app.payslip_link_key(left(g ->> 'employee_no', 40), left(g ->> 'employee_name', 120)) end)
    returning id into v_id;

    a := g -> 'amounts';
    if g ->> 'kind' = 'payslip' and a is not null and a <> '{}'::jsonb then
      perform app.payslip_amounts_put(v_id, a, 'reading');
    end if;
  end loop;

  update payslip_batches set read_at = now() where id = p_batch_id;

  return jsonb_build_object(
    'slips',      (select count(*) from payslips where batch_id = p_batch_id and deleted_at is null
                                                   and detected_kind is distinct from 'other'),
    'other',      (select count(*) from payslips where batch_id = p_batch_id and deleted_at is null
                                                   and detected_kind = 'other'),
    'read_pages', v_read,
    'pages',      v_batch.page_count);
end $$;

revoke execute on function payslip_apply_reading(uuid) from anon, public;
grant  execute on function payslip_apply_reading(uuid) to authenticated;
