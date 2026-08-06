\pset tuples_only on
\pset format unaligned

-- ================= as the client admin =================
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000c1', false);

\echo '--- profile creation / mutation ---'
select t_expect_fail('cannot create a staff profile',
  $$insert into profiles (full_name, user_kind) values ('חדר','staff')$$);
select t_expect_fail('cannot create an admin profile',
  $$insert into profiles (full_name, user_kind, customer_id, is_admin)
    values ('חדר','customer_user','10000000-0000-0000-0000-000000000001',true)$$);
select t_expect_fail('cannot create a user under another customer',
  $$insert into profiles (full_name, user_kind, customer_id)
    values ('חדר','customer_user','10000000-0000-0000-0000-000000000002')$$);
select t_expect_fail('cannot attach a login on insert',
  $$insert into profiles (full_name, user_kind, customer_id, user_id)
    values ('חדר','customer_user','10000000-0000-0000-0000-000000000001',
            '00000000-0000-0000-0000-0000000000a1')$$);
select t_rows('cannot make self admin (no row touched)',
  $$update profiles set is_admin = true where id = '20000000-0000-0000-0000-0000000000c1'$$, 0);
select t_eq('still not an admin afterwards',
  (select is_admin from profiles where id = '20000000-0000-0000-0000-0000000000c1'), false);
select t_expect_fail('cannot move a sub-user to another customer',
  $$update profiles set customer_id = '10000000-0000-0000-0000-000000000002'
     where id = '20000000-0000-0000-0000-0000000000c2'$$);
select t_expect_fail('cannot hijack a login by setting user_id',
  $$update profiles set user_id = '00000000-0000-0000-0000-0000000000a1'
     where id = '20000000-0000-0000-0000-0000000000c2'$$);
select t_rows('cannot edit a staff profile',
  $$update profiles set full_name = 'נחטף' where id = '20000000-0000-0000-0000-0000000000f1'$$, 0);
select t_expect_ok('CAN create a sub-user in own customer',
  $$insert into profiles (full_name, user_kind, customer_id)
    values ('תת-משתמש ב','customer_user','10000000-0000-0000-0000-000000000001')$$);
select t_expect_ok('CAN rename their own sub-user',
  $$update profiles set full_name = 'תת-משתמש מעודכן'
     where id = '20000000-0000-0000-0000-0000000000c2'$$);

\echo '--- permission grants ---'
select t_expect_fail('cannot grant to self',
  $$insert into user_permission_grants values ('20000000-0000-0000-0000-0000000000c1','settings.edit',true)$$);
select t_expect_fail('cannot grant a key it does not hold',
  $$insert into user_permission_grants values ('20000000-0000-0000-0000-0000000000c2','contractors.view',true)$$);
select t_expect_fail('cannot grant a key that is not client-facing',
  $$insert into user_permission_grants values ('20000000-0000-0000-0000-0000000000c2','settings.permissions',true)$$);
select t_expect_fail('cannot grant to the owner admin',
  $$insert into user_permission_grants values ('20000000-0000-0000-0000-000000000001','users.edit',true)$$);
select t_expect_fail('cannot grant to a staff user',
  $$insert into user_permission_grants values ('20000000-0000-0000-0000-0000000000f1','events.edit',true)$$);
select t_expect_ok('CAN grant a client-facing key it holds',
  $$insert into user_permission_grants values ('20000000-0000-0000-0000-0000000000c2','events.create',true)$$);
select t_expect_ok('CAN deny a key it does not hold (taking away is safe)',
  $$insert into user_permission_grants values ('20000000-0000-0000-0000-0000000000c2','contractors.view',false)$$);
select t_expect_fail('cannot assign a role to itself',
  $$insert into profile_roles (profile_id, role_id)
    select '20000000-0000-0000-0000-0000000000c1', id from permission_roles limit 1$$);
select t_expect_fail('cannot write a kind-wide field default',
  $$insert into field_permissions (user_kind, entity, field_key, can_view)
    values ('staff','event','contact_phone',true)$$);
select t_expect_fail('cannot widen its own data scope',
  $$insert into permission_scopes (profile_id, resource, scope_type)
    values ('20000000-0000-0000-0000-0000000000c1','events','all')$$);

\echo '--- upsert paths the UI actually uses ---'
select t_expect_ok('upsert a sub-user grant (insert leg)',
  $$insert into user_permission_grants values ('20000000-0000-0000-0000-0000000000c2','tasks.view',true)
    on conflict (profile_id, permission_key) do update set allowed = excluded.allowed$$);
select t_expect_ok('upsert the same grant again (update leg)',
  $$insert into user_permission_grants values ('20000000-0000-0000-0000-0000000000c2','tasks.view',false)
    on conflict (profile_id, permission_key) do update set allowed = excluded.allowed$$);
select t_expect_ok('upsert a per-user form field override',
  $$insert into user_form_fields values ('20000000-0000-0000-0000-0000000000c2','notes','hidden')
    on conflict (profile_id, field_key) do update set state = excluded.state$$);
select t_expect_fail('cannot set a form override on self',
  $$insert into user_form_fields values ('20000000-0000-0000-0000-0000000000c1','notes','hidden')$$);
select t_expect_fail('cannot set a form override on another tenant''s user',
  $$insert into user_form_fields values ('20000000-0000-0000-0000-000000000001','notes','hidden')$$);
select t_expect_ok('can delete a sub-user override (back to default)',
  $$delete from user_form_fields where profile_id = '20000000-0000-0000-0000-0000000000c2'$$);

\echo '--- direct table writes (must go through the RPCs) ---'
select t_expect_fail('cannot insert an event directly',
  $$insert into events (customer_id, event_date)
    values ('10000000-0000-0000-0000-000000000001', current_date)$$);
select t_rows('cannot update an event directly (no row touched)',
  $$update events set volume_m = 99 where customer_id = '10000000-0000-0000-0000-000000000001'$$, 0);
select t_rows('cannot edit the customer row',
  $$update customers set name = 'נחטף' where id = '10000000-0000-0000-0000-000000000001'$$, 0);
select t_rows('cannot rewrite the company form config',
  $$update customer_form_fields set state = 'visible'
     where customer_id = '10000000-0000-0000-0000-000000000001' and field_key = 'volume_m'$$, 0);

\echo '--- reads are tenant-scoped ---'
select t_eq('sees no staff_roles', (select count(*)::int from staff_roles), 0);
select t_eq('sees only own-customer profiles',
  (select count(*)::int from profiles where customer_id is distinct from '10000000-0000-0000-0000-000000000001'), 0);
select t_eq('sees no other customer events',
  (select count(*)::int from events where customer_id <> '10000000-0000-0000-0000-000000000001'), 0);
select t_eq('the catalog is readable (the matrix needs it)',
  (select (count(*) > 0) from permission_registry), true);

\echo '--- soft_delete is object-scoped, not just key-scoped ---'
select t_expect_fail('cannot soft-delete the owner profile',
  $$select soft_delete('profiles','20000000-0000-0000-0000-000000000001')$$);
select t_expect_fail('cannot soft-delete another customer event',
  $$select soft_delete('events','30000000-0000-0000-0000-000000000002')$$);

\echo '--- create_event honours the merged field config ---'
select t_expect_fail('rejects a payload missing a user-level required field',
  $$select create_event('{"event_date":"2026-09-01"}'::jsonb)$$);
select t_eq('ignores a spoofed customer_id and files under own customer',
  (t_created_event('{"event_date":"2026-09-01","event_number":"A-1",
                     "customer_id":"10000000-0000-0000-0000-000000000002"}'::jsonb)).customer_id,
  '10000000-0000-0000-0000-000000000001'::uuid);
select t_eq('strips a company-hidden field from the payload',
  (t_created_event('{"event_date":"2026-09-02","event_number":"A-2","volume_m":"99"}'::jsonb)).volume_m,
  null::numeric);
select t_eq('keeps a field that is NOT hidden',
  (t_created_event('{"event_date":"2026-09-03","event_number":"A-3","truck_count":"4"}'::jsonb)).truck_count,
  4);

\echo '--- the RPC path still works end to end for a client ---'
-- 0014 removed customer_user from events_update, so the RPC is now the only way
-- a client can edit at all — worth proving rather than assuming. This also
-- covers the nested setup/teardown write running inside app.system_write.
select t_eq('update_event still works for the owning client',
  (t_updated_event((select id from events where event_number = 'A-3'),
                   '{"end_client_name":"שם מעודכן"}'::jsonb)).end_client_name,
  'שם מעודכן');
select t_eq('update_event ignores a company-hidden field',
  (t_updated_event((select id from events where event_number = 'A-3'),
                   '{"volume_m":"77"}'::jsonb)).volume_m,
  null::numeric);
select t_expect_ok('saving setup/teardown times does not trip the task column gate',
  $$select update_event((select id from events where event_number = 'A-3'),
      '{"setup_time":"08:30","teardown_time":"23:00"}'::jsonb)$$);
select t_eq('the auto setup/teardown tasks are visible to the client',
  (select count(*)::int from tasks t join events e on e.id = t.event_id
    where e.event_number = 'A-3' and t.deleted_at is null), 2);

-- ================= regression: staff and admin are unaffected =================
reset role;
\echo '--- staff regression ---'
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000f1', false);
select t_eq('plain staff still sees the staff roster', (select (count(*) > 0) from staff_roles), true);
select t_eq('plain staff still sees events', (select (count(*) > 0) from events), true);

reset role;
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false);
\echo '--- owner/admin regression ---'
select t_expect_ok('admin creates an event via the RPC',
  $$select create_event('{"event_date":"2026-10-01","customer_id":"10000000-0000-0000-0000-000000000001"}'::jsonb)$$);
select t_expect_ok('admin still writes events directly',
  $$update events set notes = 'ok' where customer_id = '10000000-0000-0000-0000-000000000001'$$);
select t_expect_ok('admin grants any key',
  $$insert into user_permission_grants values ('20000000-0000-0000-0000-0000000000c1','settings.edit',true)$$);
select t_expect_ok('admin sets a kind-wide field default',
  $$insert into field_permissions (user_kind, entity, field_key, can_view)
    values ('customer_user','event','contact_phone',false)$$);
select t_expect_ok('admin can promote someone to admin',
  $$update profiles set is_admin = true where id = '20000000-0000-0000-0000-0000000000f2'$$);
select t_eq('admin sees every event', (select (count(*) >= 2) from events), true);
reset role;
