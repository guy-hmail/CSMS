\set ON_ERROR_STOP on

select '1..1';

begin;

insert into public.churches (id, code, slug, name, status)
values
    ('00000000-0000-0000-0000-000000000031', 'AUTH_A', 'auth-a', 'Auth Church A', 'active'),
    ('00000000-0000-0000-0000-000000000032', 'AUTH_B', 'auth-b', 'Auth Church B', 'trial');

insert into public.users (
    id, auth_user_id, last_active_church_id, line_user_id, display_name
)
values (
    '10000000-0000-0000-0000-000000000031',
    'a3000000-0000-4000-8000-000000000031',
    '00000000-0000-0000-0000-000000000031',
    'line-auth-test',
    'Auth Test User'
);

insert into public.church_members (id, church_id, user_id, status)
values
    ('20000000-0000-0000-0000-000000000031', '00000000-0000-0000-0000-000000000031', '10000000-0000-0000-0000-000000000031', 'active'),
    ('20000000-0000-0000-0000-000000000032', '00000000-0000-0000-0000-000000000032', '10000000-0000-0000-0000-000000000031', 'active');

insert into public.organization_unit_types (id, church_id, code, name)
values (
    '30000000-0000-0000-0000-000000000031',
    '00000000-0000-0000-0000-000000000031',
    'ROOT',
    'Root'
);

insert into public.organization_units (
    id, church_id, structure_root_id, ou_type_id, code, name, path, level
)
values (
    '40000000-0000-0000-0000-000000000031',
    '00000000-0000-0000-0000-000000000031',
    '40000000-0000-0000-0000-000000000031',
    '30000000-0000-0000-0000-000000000031',
    'ROOT',
    'Root',
    '/auth-root',
    1
);

insert into public.ou_members (
    church_id, ou_id, church_member_id, permission
)
values (
    '00000000-0000-0000-0000-000000000031',
    '40000000-0000-0000-0000-000000000031',
    '20000000-0000-0000-0000-000000000031',
    'admin'
);

create function pg_temp.assert_true(condition boolean, failure_message text)
returns void
language plpgsql
as $$
begin
    if condition is not true then
        raise exception 'Identity assertion failed: %', failure_message;
    end if;
end;
$$;

set local role authenticated;
select set_config('request.jwt.claim.sub', 'a3000000-0000-4000-8000-000000000031', true);
select set_config(
    'request.jwt.claims',
    '{"sub":"a3000000-0000-4000-8000-000000000031","role":"authenticated","app_metadata":{"active_church_id":"00000000-0000-0000-0000-000000000031"}}',
    true
);

select pg_temp.assert_true(
    (select count(*) = 2 from public.list_my_tenants()),
    'list_my_tenants must return both active memberships'
);

select pg_temp.assert_true(
    (
        select count(*) = 1
        from public.list_my_tenants()
        where tenant_id = '00000000-0000-0000-0000-000000000031'
          and is_current
          and is_last_active
    ),
    'selected and last-active tenant flags'
);

select pg_temp.assert_true(
    public.get_my_profile() #>> '{currentTenant,id}'
      = '00000000-0000-0000-0000-000000000031',
    'get_my_profile selected tenant'
);

select pg_temp.assert_true(
    jsonb_array_length(public.get_my_profile() -> 'permissions') = 1,
    'get_my_profile direct permission list'
);

reset role;

set local role service_role;
select public.complete_tenant_switch(
    'a3000000-0000-4000-8000-000000000031',
    '00000000-0000-0000-0000-000000000032'
);
reset role;

select pg_temp.assert_true(
    (
        select last_active_church_id = '00000000-0000-0000-0000-000000000032'
        from public.users
        where id = '10000000-0000-0000-0000-000000000031'
    ),
    'complete_tenant_switch updates preference'
);

select pg_temp.assert_true(
    (
        select count(*) = 1
        from public.audit_logs
        where user_id = '10000000-0000-0000-0000-000000000031'
          and church_id = '00000000-0000-0000-0000-000000000032'
          and action = 'switch_active_tenant'
    ),
    'complete_tenant_switch writes audit event'
);

select 'ok 1 - BE-003 identity RPCs';
rollback;
