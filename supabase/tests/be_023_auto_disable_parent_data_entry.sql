\set ON_ERROR_STOP on
select '1..1';
begin;

insert into public.churches (id, code, slug, name, status)
values ('98000000-0000-4000-8000-000000000001', 'LEAF-RULE', 'leaf-rule', 'Leaf Rule Test', 'active');

insert into public.users (id, auth_user_id, line_user_id, display_name)
values ('98000000-0000-4000-8000-000000000002', '98000000-0000-4000-8000-000000000003', 'leaf-rule-admin', 'Leaf Rule Admin');

insert into public.church_members (id, church_id, user_id, status)
values ('98000000-0000-4000-8000-000000000004', '98000000-0000-4000-8000-000000000001', '98000000-0000-4000-8000-000000000002', 'active');

insert into public.organization_unit_types (id, church_id, code, name, default_allow_data_entry)
values ('98000000-0000-4000-8000-000000000005', '98000000-0000-4000-8000-000000000001', 'REPORTING', 'Reporting OU', true);

insert into public.organization_units (
  id, church_id, structure_root_id, ou_type_id, code, name, path, level, allow_data_entry
) values (
  '98000000-0000-4000-8000-000000000006', '98000000-0000-4000-8000-000000000001',
  '98000000-0000-4000-8000-000000000006', '98000000-0000-4000-8000-000000000005',
  'ROOT', 'Reporting Parent', '/leaf-rule-root', 1, true
);

insert into public.ou_members (id, church_id, ou_id, church_member_id, permission)
values (
  '98000000-0000-4000-8000-000000000007', '98000000-0000-4000-8000-000000000001',
  '98000000-0000-4000-8000-000000000006', '98000000-0000-4000-8000-000000000004', 'admin'
);

create function pg_temp.assert_true(condition boolean, message text)
returns void language plpgsql as $$
begin
  if condition is not true then raise exception 'BE-023 assertion: %', message; end if;
end;
$$;

set local role authenticated;
select set_config('request.jwt.claim.sub', '98000000-0000-4000-8000-000000000003', true);
select set_config(
  'request.jwt.claims',
  '{"sub":"98000000-0000-4000-8000-000000000003","app_metadata":{"active_church_id":"98000000-0000-4000-8000-000000000001"}}',
  true
);

create temporary table create_result as
select public.create_organization_unit(jsonb_build_object(
  'parentOuId', '98000000-0000-4000-8000-000000000006',
  'ouTypeId', '98000000-0000-4000-8000-000000000005',
  'code', 'CHILD',
  'name', 'Reporting Child',
  'allowDataEntry', true
)) as response;

reset role;

select pg_temp.assert_true(
  not (select allow_data_entry from public.organization_units where id = '98000000-0000-4000-8000-000000000006'),
  'parent direct data entry is disabled'
);

select pg_temp.assert_true(
  (select (response #>> '{data,parentDataEntryDisabled}')::boolean from create_result),
  'response tells the frontend that the parent changed'
);

select pg_temp.assert_true(
  exists (
    select 1 from public.audit_logs
    where entity_id = '98000000-0000-4000-8000-000000000006'
      and action = 'update'
      and metadata ->> 'reason' = 'child_data_entry_enabled'
      and after_data ->> 'allowDataEntry' = 'false'
  ),
  'automatic parent change is audited'
);

select 'ok 1 - creating a reporting child disables reporting on its parent';
rollback;
