-- 0222: תלוש "ללא שיוך" אינו נספר בסיכומים
--
-- הבעלים, על 0220 §3: "תלוש שלא משויך — שלא יופיע בכלל בסיכומים." סיכומי
-- החודש ב-`payslips_board` חוזרים לספור רק תלושים משויכים (כמו ב-0218); תלוש
-- שסומן "ללא שיוך" יוצא מהממתינים וגם מהסיכומים, ונשאר רק בקובץ (ובאשף השיוך,
-- שם אפשר לשייך אותו מאוחר יותר או להחזיר לממתינים).

-- payslips_board (0220 §4) — אותו גוף; הסיכומים רק על תלושים משויכים.
create or replace function payslips_board(
  p_batch_id   uuid default null,
  p_period     date default null,
  p_unassigned boolean default false)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_manage boolean := app.can_manage_payslips();
  v_cost   boolean := app.can_view_payslip_costs();
  v_rows   jsonb;
begin
  if not (v_manage or v_cost) then
    raise exception 'אין לך הרשאה לצפות בתלושי השכר' using errcode = '42501';
  end if;

  with s as (
    select s.*, b.file_name, b.page_count, b.created_at as uploaded_at
      from payslips s
      join payslip_batches b on b.id = s.batch_id and b.deleted_at is null
     where s.deleted_at is null
       and (p_batch_id is null or s.batch_id = p_batch_id)
       and (p_period is null or s.period = date_trunc('month', p_period)::date)
       and (not p_unassigned or (s.profile_id is null and s.skipped_at is null))
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'id',                   s.id,
           'batch_id',             s.batch_id,
           'file_name',            s.file_name,
           'page_count',           s.page_count,
           'page_from',            s.page_from,
           'page_to',              s.page_to,
           'period',               s.period,
           'profile_id',           s.profile_id,
           'full_name',            p.full_name,
           'contractor_name',      pc.name,
           'assigned_at',          s.assigned_at,
           'skipped',              s.skipped_at is not null,
           'detected_kind',        s.detected_kind,
           'detected_name',        s.detected_name,
           'detected_employee_no', s.detected_employee_no,
           'detected_period',      s.detected_period,
           'suggested_profile_id', sg.id,
           'suggested_name',       sg.full_name,
           'has_previous',         exists (select 1 from payslips x
                                            where x.batch_id = s.batch_id and x.deleted_at is null
                                              and x.page_to = s.page_from - 1),
           -- עוד תלושים לאותו עובד ולאותו חודש — אולי כפול, אולי תלוש מתקן
           'same_month_count',     case when s.profile_id is null then 0 else
                                     (select count(*) from payslips x
                                       join payslip_batches xb on xb.id = x.batch_id and xb.deleted_at is null
                                      where x.profile_id = s.profile_id and x.period = s.period
                                        and x.deleted_at is null and x.id <> s.id) end,
           'amounts',              case when v_cost and a.payslip_id is not null
                                        then to_jsonb(a) - 'payslip_id' - 'updated_by' end)
         order by s.period desc, s.uploaded_at desc, s.page_from), '[]'::jsonb)
    into v_rows
    from s
    left join profiles p on p.id = s.profile_id
    left join contractors pc on pc.id = p.contractor_id and p.user_kind = 'contractor_user'
    left join payslip_amounts a on a.payslip_id = s.id
    left join lateral (
      select pp.id, pp.full_name
        from profiles pp
       where s.profile_id is null
         and s.skipped_at is null
         and s.detected_kind is distinct from 'other'
         and pp.id = app.payslip_suggest(s.link_key, s.detected_name)) sg on true;

  return jsonb_build_object(
    'can_manage',    v_manage,
    'can_view_cost', v_cost,
    'slips',         v_rows,
    'totals', case when v_cost then (
      select jsonb_build_object(
               'count',                  count(*),
               'with_amounts',           count(*) filter (where (r -> 'amounts' ->> 'gross_pay') is not null),
               'gross_pay',              coalesce(sum((r -> 'amounts' ->> 'gross_pay')::numeric), 0),
               'net_pay',                coalesce(sum((r -> 'amounts' ->> 'net_pay')::numeric), 0),
               'employer_contributions', coalesce(sum((r -> 'amounts' ->> 'employer_contributions')::numeric), 0),
               'employer_cost',          coalesce(sum((r -> 'amounts' ->> 'employer_cost')::numeric), 0))
        from jsonb_array_elements(v_rows) r
       where r ->> 'profile_id' is not null) end);
end $$;

revoke execute on function payslips_board(uuid, date, boolean) from anon, public;
grant  execute on function payslips_board(uuid, date, boolean) to authenticated;
