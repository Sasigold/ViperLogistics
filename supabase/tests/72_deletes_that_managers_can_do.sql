\pset tuples_only on
\pset format unaligned

-- ===========================================================================
-- ‏72: מחיקה שמנהל שאינו אדמין יכול לעשות (0225).
--
--   72b1 מנהל תקבולים       (finance.receipts_manage + receipts_view)
--   72b2 מנהל מחסנים        (attendance.manage_warehouses)
--   72b3 מנהל אזורי תמחור   (pricing.manage_rules)
--   72b4 מנהל עובדי קבלן    (contractors.view + contractors.manage_workers)
--   72c1 עובד בלי מפתחות
-- ===========================================================================

insert into auth.users (id, email)
select ('00000000-0000-0000-0000-0000000072' || s)::uuid, 'p72-' || s || '@vl.test'
  from unnest(array['b1','b2','b3','b4','c1']) s;

insert into profiles (id, user_id, user_kind, is_admin, full_name)
select ('20000000-0000-0000-0000-0000000072' || s)::uuid, ('00000000-0000-0000-0000-0000000072' || s)::uuid,
       'staff', false, 'בודק 72 ' || s
  from unnest(array['b1','b2','b3','b4','c1']) s;

insert into user_permission_grants (profile_id, permission_key, allowed) values
  ('20000000-0000-0000-0000-0000000072b1', 'finance.receipts_manage', true),
  ('20000000-0000-0000-0000-0000000072b1', 'finance.receipts_view', true),
  ('20000000-0000-0000-0000-0000000072b2', 'attendance.manage_warehouses', true),
  ('20000000-0000-0000-0000-0000000072b3', 'pricing.manage_rules', true),
  ('20000000-0000-0000-0000-0000000072b4', 'contractors.view', true),
  ('20000000-0000-0000-0000-0000000072b4', 'contractors.manage_workers', true);

insert into receipts (id, customer_id, amount)
select '30000000-0000-0000-0000-0000000072a1', id, 100 from customers order by id limit 1;
insert into warehouses (id, name) values ('30000000-0000-0000-0000-0000000072a2', 'מחסן 72');
insert into pricing_zones (id, name, shape, center_lat, center_lng, radius_km)
values ('30000000-0000-0000-0000-0000000072a3', 'אזור 72', 'circle', 32, 34.8, 5);
insert into contractor_workers (id, contractor_id, full_name)
select '30000000-0000-0000-0000-0000000072a4', id, 'עובד קבלן 72' from contractors order by id limit 1;

create or replace function t72_as(p text) returns void language sql as $$
  select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000072' || p, false);
$$;
grant execute on function t72_as(text) to authenticated;

create or replace function t72_deleted(p_table text, p_id uuid) returns boolean
language plpgsql stable security definer set search_path = public as $$
declare v boolean;
begin
  execute format('select deleted_at is not null from %I where id = $1', p_table) into v using p_id;
  return v;
end $$;
grant execute on function t72_deleted(text, uuid) to authenticated;

set role authenticated;

\echo '--- 1. הבאג: עדכון ישיר נדחה למי שאינו אדמין ---'
select t72_as('b1');
select t_expect_fail('עדכון deleted_at ישיר על תקבול',
  $$update receipts set deleted_at = now() where id = '30000000-0000-0000-0000-0000000072a1'$$);

\echo '--- 2. דרך soft_delete — כל מנהל במפתח שלו ---'
select t_expect_ok('תקבול', $$select soft_delete('receipts', '30000000-0000-0000-0000-0000000072a1')$$);
select t_eq('התקבול מחוק', t72_deleted('receipts', '30000000-0000-0000-0000-0000000072a1'), true);
select t_expect_ok('ומשוחזר', $$select soft_delete('receipts', '30000000-0000-0000-0000-0000000072a1', true)$$);
select t_eq('התקבול חי', t72_deleted('receipts', '30000000-0000-0000-0000-0000000072a1'), false);

select t72_as('b2');
select t_expect_ok('מחסן', $$select soft_delete('warehouses', '30000000-0000-0000-0000-0000000072a2')$$);
select t_eq('המחסן מחוק', t72_deleted('warehouses', '30000000-0000-0000-0000-0000000072a2'), true);

select t72_as('b3');
select t_expect_ok('אזור תמחור', $$select soft_delete('pricing_zones', '30000000-0000-0000-0000-0000000072a3')$$);
select t_eq('האזור מחוק', t72_deleted('pricing_zones', '30000000-0000-0000-0000-0000000072a3'), true);

select t72_as('b4');
select t_expect_ok('עובד קבלן', $$select soft_delete('contractor_workers', '30000000-0000-0000-0000-0000000072a4')$$);
select t_eq('עובד הקבלן מחוק', t72_deleted('contractor_workers', '30000000-0000-0000-0000-0000000072a4'), true);

\echo '--- 3. בלי המפתח — לא ---'
select t72_as('b2');
select t_expect_fail('מנהל מחסנים אינו מוחק תקבול',
  $$select soft_delete('receipts', '30000000-0000-0000-0000-0000000072a1')$$);
select t72_as('c1');
select t_expect_fail('עובד אינו משחזר מחסן',
  $$select soft_delete('warehouses', '30000000-0000-0000-0000-0000000072a2', true)$$);
select t_expect_fail('ואינו מוחק אזור',
  $$select soft_delete('pricing_zones', '30000000-0000-0000-0000-0000000072a3', true)$$);

reset role;
