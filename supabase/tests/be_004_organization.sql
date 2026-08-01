\set ON_ERROR_STOP on
select '1..1';
begin;

insert into public.churches (id, code, slug, name, status)
values
('00000000-0000-0000-0000-000000000041', 'ORG', 'org', 'Organization Test', 'active'),
('00000000-0000-0000-0000-000000000042', 'OTHER', 'other', 'Other Tenant', 'active');

insert into public.users (id, auth_user_id, line_user_id, display_name)
values
('10000000-0000-0000-0000-000000000041', 'a4000000-0000-4000-8000-000000000041', 'org-manager', 'Manager'),
('10000000-0000-0000-0000-000000000042', 'a4000000-0000-4000-8000-000000000042', 'org-viewer', 'Viewer');

insert into public.church_members (id, church_id, user_id, status)
values
('20000000-0000-0000-0000-000000000041', '00000000-0000-0000-0000-000000000041', '10000000-0000-0000-0000-000000000041', 'active'),
('20000000-0000-0000-0000-000000000042', '00000000-0000-0000-0000-000000000041', '10000000-0000-0000-0000-000000000042', 'active');

insert into public.organization_unit_types (
    id, church_id, code, name, default_allow_data_entry
)
values (
    '30000000-0000-0000-0000-000000000041',
    '00000000-0000-0000-0000-000000000041',
    'GENERIC', 'Generic', true
);

insert into public.organization_units (
    id, church_id, structure_root_id, ou_type_id, code, name, path, level
)
values (
    '40000000-0000-0000-0000-000000000041',
    '00000000-0000-0000-0000-000000000041',
    '40000000-0000-0000-0000-000000000041',
    '30000000-0000-0000-0000-000000000041',
    'ROOT', 'Root', '/org-root', 1
);

insert into public.ou_members (church_id, ou_id, church_member_id, permission)
values
('00000000-0000-0000-0000-000000000041', '40000000-0000-0000-0000-000000000041', '20000000-0000-0000-0000-000000000041', 'manager'),
('00000000-0000-0000-0000-000000000041', '40000000-0000-0000-0000-000000000041', '20000000-0000-0000-0000-000000000042', 'viewer');

create function pg_temp.assert_true(condition boolean, message text)
returns void language plpgsql as $$
begin
    if condition is not true then raise exception 'BE-004 assertion: %', message; end if;
end;
$$;

set local role authenticated;
select set_config('request.jwt.claim.sub', 'a4000000-0000-4000-8000-000000000041', true);
select set_config('request.jwt.claims', '{"sub":"a4000000-0000-4000-8000-000000000041","app_metadata":{"active_church_id":"00000000-0000-0000-0000-000000000041"}}', true);

create temporary table created_ous as
select (public.create_organization_unit(jsonb_build_object(
    'parentOuId', '40000000-0000-0000-0000-000000000041',
    'ouTypeId', '30000000-0000-0000-0000-000000000041',
    'code', 'GROUP-A', 'name', 'Group A'
)) #>> '{data,ouId}')::uuid as id;

select pg_temp.assert_true(
    (select allow_data_entry and level = 2 from public.organization_units where id = (select id from created_ous)),
    'create inherits type default and computes level'
);

select public.update_organization_unit(jsonb_build_object(
    'ouId', (select id from created_ous),
    'ouTypeId', '30000000-0000-0000-0000-000000000041',
    'code', 'GROUP-A', 'name', 'Group A Updated',
    'allowDataEntry', true, 'sortOrder', 20
));

select pg_temp.assert_true(
    (select name = 'Group A Updated' and sort_order = 20 from public.organization_units where id = (select id from created_ous)),
    'update metadata'
);
select pg_temp.assert_true(
    jsonb_array_length(public.get_accessible_ou_tree() #> '{data,items,0,children}') = 1,
    'nested accessible tree'
);

select public.soft_delete_organization_unit(jsonb_build_object(
    'ouId', (select id from created_ous), 'reason', 'test cleanup'
));
reset role;
select pg_temp.assert_true(
    (select not is_active and deleted_at is not null from public.organization_units where id = (select id from created_ous)),
    'soft delete'
);
select pg_temp.assert_true(
    (
        select count(*) = 3
        from public.audit_logs
        where church_id = '00000000-0000-0000-0000-000000000041'
    ),
    'all mutations audited'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', 'a4000000-0000-4000-8000-000000000042', true);
select set_config('request.jwt.claims', '{"sub":"a4000000-0000-4000-8000-000000000042","app_metadata":{"active_church_id":"00000000-0000-0000-0000-000000000041"}}', true);
do $$
begin
    begin
        perform public.create_organization_unit(jsonb_build_object(
            'parentOuId', '40000000-0000-0000-0000-000000000041',
            'ouTypeId', '30000000-0000-0000-0000-000000000041',
            'code', 'DENIED', 'name', 'Denied'
        ));
        raise exception 'viewer create was accepted';
    exception when others then
        if sqlerrm <> 'PERMISSION_DENIED' then raise; end if;
    end;
end;
$$;

reset role;
select 'ok 1 - BE-004 organization RPCs';
rollback;
