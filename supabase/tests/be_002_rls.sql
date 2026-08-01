\set ON_ERROR_STOP on

select '1..1';

begin;

insert into public.churches (id, code, slug, name, status)
values
    ('00000000-0000-0000-0000-00000000000a', 'RLS_A', 'rls-a', 'RLS Church A', 'active'),
    ('00000000-0000-0000-0000-00000000000b', 'RLS_B', 'rls-b', 'RLS Church B', 'active');

insert into public.users (
    id, auth_user_id, line_user_id, display_name, global_role
)
values
    ('10000000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-000000000001', 'rls-viewer', 'Viewer', 'user'),
    ('10000000-0000-0000-0000-000000000002', 'a1000000-0000-0000-0000-000000000002', 'rls-data-entry', 'Data Entry', 'user'),
    ('10000000-0000-0000-0000-000000000003', 'a1000000-0000-0000-0000-000000000003', 'rls-manager', 'Manager', 'user'),
    ('10000000-0000-0000-0000-000000000004', 'a1000000-0000-0000-0000-000000000004', 'rls-approver', 'Approver', 'user'),
    ('10000000-0000-0000-0000-000000000005', 'a1000000-0000-0000-0000-000000000005', 'rls-root-admin', 'Root Admin', 'user'),
    ('10000000-0000-0000-0000-000000000006', 'a1000000-0000-0000-0000-000000000006', 'rls-system-admin', 'System Admin', 'system_admin'),
    ('10000000-0000-0000-0000-000000000007', 'b1000000-0000-0000-0000-000000000001', 'rls-church-b', 'Church B User', 'user');

insert into public.church_members (id, church_id, user_id, status)
values
    ('20000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-00000000000a', '10000000-0000-0000-0000-000000000001', 'active'),
    ('20000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-00000000000a', '10000000-0000-0000-0000-000000000002', 'active'),
    ('20000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-00000000000a', '10000000-0000-0000-0000-000000000003', 'active'),
    ('20000000-0000-0000-0000-000000000004', '00000000-0000-0000-0000-00000000000a', '10000000-0000-0000-0000-000000000004', 'active'),
    ('20000000-0000-0000-0000-000000000005', '00000000-0000-0000-0000-00000000000a', '10000000-0000-0000-0000-000000000005', 'active'),
    ('20000000-0000-0000-0000-000000000006', '00000000-0000-0000-0000-00000000000a', '10000000-0000-0000-0000-000000000006', 'active'),
    ('20000000-0000-0000-0000-000000000007', '00000000-0000-0000-0000-00000000000b', '10000000-0000-0000-0000-000000000007', 'active');

insert into public.organization_unit_types (id, church_id, code, name)
values
    ('30000000-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-00000000000a', 'GENERIC', 'Generic'),
    ('30000000-0000-0000-0000-00000000000b', '00000000-0000-0000-0000-00000000000b', 'GENERIC', 'Generic');

insert into public.organization_units (
    id, church_id, structure_root_id, parent_id, ou_type_id,
    code, name, path, level, allow_data_entry
)
values
    ('40000000-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-00000000000a', '40000000-0000-0000-0000-00000000000a', null, '30000000-0000-0000-0000-00000000000a', 'ROOT', 'Root A', '/root-a', 1, false),
    ('40000000-0000-0000-0000-000000000011', '00000000-0000-0000-0000-00000000000a', '40000000-0000-0000-0000-00000000000a', '40000000-0000-0000-0000-00000000000a', '30000000-0000-0000-0000-00000000000a', 'REGION', 'Region A', '/root-a/region-a', 2, false),
    ('40000000-0000-0000-0000-000000000012', '00000000-0000-0000-0000-00000000000a', '40000000-0000-0000-0000-00000000000a', '40000000-0000-0000-0000-000000000011', '30000000-0000-0000-0000-00000000000a', 'DISTRICT', 'District A', '/root-a/region-a/district-a', 3, false),
    ('40000000-0000-0000-0000-000000000013', '00000000-0000-0000-0000-00000000000a', '40000000-0000-0000-0000-00000000000a', '40000000-0000-0000-0000-000000000012', '30000000-0000-0000-0000-00000000000a', 'LEAF_1', 'Leaf 1', '/root-a/region-a/district-a/leaf-1', 4, true),
    ('40000000-0000-0000-0000-000000000014', '00000000-0000-0000-0000-00000000000a', '40000000-0000-0000-0000-00000000000a', '40000000-0000-0000-0000-000000000012', '30000000-0000-0000-0000-00000000000a', 'LEAF_2', 'Leaf 2', '/root-a/region-a/district-a/leaf-2', 4, true),
    ('40000000-0000-0000-0000-00000000000b', '00000000-0000-0000-0000-00000000000b', '40000000-0000-0000-0000-00000000000b', null, '30000000-0000-0000-0000-00000000000b', 'ROOT', 'Root B', '/root-b', 1, true);

insert into public.ou_members (
    church_id, ou_id, church_member_id, permission
)
values
    ('00000000-0000-0000-0000-00000000000a', '40000000-0000-0000-0000-000000000011', '20000000-0000-0000-0000-000000000001', 'viewer'),
    ('00000000-0000-0000-0000-00000000000a', '40000000-0000-0000-0000-000000000013', '20000000-0000-0000-0000-000000000002', 'data_entry'),
    ('00000000-0000-0000-0000-00000000000a', '40000000-0000-0000-0000-000000000012', '20000000-0000-0000-0000-000000000003', 'manager'),
    ('00000000-0000-0000-0000-00000000000a', '40000000-0000-0000-0000-000000000011', '20000000-0000-0000-0000-000000000004', 'approver'),
    ('00000000-0000-0000-0000-00000000000a', '40000000-0000-0000-0000-00000000000a', '20000000-0000-0000-0000-000000000005', 'admin'),
    ('00000000-0000-0000-0000-00000000000b', '40000000-0000-0000-0000-00000000000b', '20000000-0000-0000-0000-000000000007', 'viewer');

insert into public.statistic_periods (
    id, church_id, year, week_no, period_start, period_end, label
)
values
    ('50000000-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-00000000000a', 2026, 30, '2026-07-20', '2026-07-26', '2026-W30'),
    ('50000000-0000-0000-0000-00000000000b', '00000000-0000-0000-0000-00000000000b', 2026, 30, '2026-07-20', '2026-07-26', '2026-W30');

insert into public.statistic_submissions (id, church_id, period_id, ou_id)
values
    ('60000000-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-00000000000a', '50000000-0000-0000-0000-00000000000a', '40000000-0000-0000-0000-000000000013'),
    ('60000000-0000-0000-0000-00000000000b', '00000000-0000-0000-0000-00000000000b', '50000000-0000-0000-0000-00000000000b', '40000000-0000-0000-0000-00000000000b');

insert into public.audit_logs (
    church_id, ou_id, entity_type, action
)
values
    ('00000000-0000-0000-0000-00000000000a', null, 'churches', 'update_settings'),
    ('00000000-0000-0000-0000-00000000000a', '40000000-0000-0000-0000-000000000013', 'statistic_submissions', 'save_draft'),
    ('00000000-0000-0000-0000-00000000000a', '40000000-0000-0000-0000-000000000013', 'approval_logs', 'approve'),
    ('00000000-0000-0000-0000-00000000000b', '40000000-0000-0000-0000-00000000000b', 'approval_logs', 'approve');

create function pg_temp.assert_true(
    condition boolean,
    failure_message text
)
returns void
language plpgsql
as $$
begin
    if condition is not true then
        raise exception 'RLS assertion failed: %', failure_message;
    end if;
end;
$$;

select pg_temp.assert_true(
    (
        select count(*) = 17
        from pg_class as relation
        join pg_namespace as namespace
          on namespace.oid = relation.relnamespace
        where namespace.nspname = 'public'
          and relation.relkind = 'r'
          and relation.relrowsecurity
          and relation.relforcerowsecurity
    ),
    'RLS must be enabled and forced on all 17 business tables'
);

select pg_temp.assert_true(
    (
        select count(*) >= 12
        from pg_proc as function
        join pg_namespace as namespace
          on namespace.oid = function.pronamespace
        where namespace.nspname = 'app_security'
    ),
    'Expected at least the 12 BE-002 app_security helper functions'
);

set local role authenticated;

-- Viewer inherits visibility down the assigned subtree, but cannot submit.
select set_config(
    'request.jwt.claims',
    '{"sub":"a1000000-0000-0000-0000-000000000001","role":"authenticated","app_metadata":{"active_church_id":"00000000-0000-0000-0000-00000000000a"}}',
    true
);
select set_config('request.jwt.claim.sub', 'a1000000-0000-0000-0000-000000000001', true);
select pg_temp.assert_true((select count(*) = 1 from public.churches), 'viewer tenant isolation');
select pg_temp.assert_true((select count(*) = 4 from public.organization_units), 'viewer subtree visibility');
select pg_temp.assert_true(not app_security.can_view_ou('40000000-0000-0000-0000-00000000000b'), 'viewer cross-tenant OU denial');
select pg_temp.assert_true(not app_security.can_submit_for_ou('40000000-0000-0000-0000-000000000013'), 'viewer submit denial');

-- Data-entry permission is direct-only and cannot see a sibling.
select set_config(
    'request.jwt.claims',
    '{"sub":"a1000000-0000-0000-0000-000000000002","role":"authenticated","app_metadata":{"active_church_id":"00000000-0000-0000-0000-00000000000a"}}',
    true
);
select set_config('request.jwt.claim.sub', 'a1000000-0000-0000-0000-000000000002', true);
select pg_temp.assert_true((select count(*) = 1 from public.organization_units), 'data-entry direct OU visibility');
select pg_temp.assert_true(app_security.can_submit_for_ou('40000000-0000-0000-0000-000000000013'), 'data-entry assigned OU submit');
select pg_temp.assert_true(not app_security.can_submit_for_ou('40000000-0000-0000-0000-000000000014'), 'data-entry sibling denial');

-- Manager inherits view/manage/submit permission down the district subtree.
select set_config(
    'request.jwt.claims',
    '{"sub":"a1000000-0000-0000-0000-000000000003","role":"authenticated","app_metadata":{"active_church_id":"00000000-0000-0000-0000-00000000000a"}}',
    true
);
select set_config('request.jwt.claim.sub', 'a1000000-0000-0000-0000-000000000003', true);
select pg_temp.assert_true((select count(*) = 3 from public.organization_units), 'manager subtree visibility');
select pg_temp.assert_true(app_security.can_manage_ou('40000000-0000-0000-0000-000000000013'), 'manager inherited management');
select pg_temp.assert_true(app_security.can_submit_for_ou('40000000-0000-0000-0000-000000000014'), 'manager inherited submit');
select pg_temp.assert_true((select count(*) = 1 from public.audit_logs), 'manager audit scope');

-- Approver sees descendant submissions and only approval audit events.
select set_config(
    'request.jwt.claims',
    '{"sub":"a1000000-0000-0000-0000-000000000004","role":"authenticated","app_metadata":{"active_church_id":"00000000-0000-0000-0000-00000000000a"}}',
    true
);
select set_config('request.jwt.claim.sub', 'a1000000-0000-0000-0000-000000000004', true);
select pg_temp.assert_true((select count(*) = 1 from public.statistic_submissions), 'approver descendant submission visibility');
select pg_temp.assert_true(app_security.can_approve_for_ou('40000000-0000-0000-0000-000000000013'), 'approver inherited approval');
select pg_temp.assert_true(not app_security.can_submit_for_ou('40000000-0000-0000-0000-000000000013'), 'approver submit denial');
select pg_temp.assert_true((select count(*) = 1 from public.audit_logs), 'approver audit scope');

-- Direct Root admin sees all tenant audit events.
select set_config(
    'request.jwt.claims',
    '{"sub":"a1000000-0000-0000-0000-000000000005","role":"authenticated","app_metadata":{"active_church_id":"00000000-0000-0000-0000-00000000000a"}}',
    true
);
select set_config('request.jwt.claim.sub', 'a1000000-0000-0000-0000-000000000005', true);
select pg_temp.assert_true((select count(*) = 3 from public.audit_logs), 'Root admin tenant audit visibility');

-- A system admin has no blanket access through normal tenant RLS.
select set_config(
    'request.jwt.claims',
    '{"sub":"a1000000-0000-0000-0000-000000000006","role":"authenticated","app_metadata":{"active_church_id":"00000000-0000-0000-0000-00000000000a"}}',
    true
);
select set_config('request.jwt.claim.sub', 'a1000000-0000-0000-0000-000000000006', true);
select pg_temp.assert_true((select count(*) = 0 from public.organization_units), 'system admin normal-client OU denial');
select pg_temp.assert_true((select count(*) = 0 from public.audit_logs), 'system admin normal-client audit denial');

-- Selecting an unjoined tenant produces no validated tenant context.
select set_config(
    'request.jwt.claims',
    '{"sub":"a1000000-0000-0000-0000-000000000001","role":"authenticated","app_metadata":{"active_church_id":"00000000-0000-0000-0000-00000000000b"}}',
    true
);
select set_config('request.jwt.claim.sub', 'a1000000-0000-0000-0000-000000000001', true);
select pg_temp.assert_true((select count(*) = 0 from public.churches), 'unjoined tenant denial');

-- Direct mutation remains blocked even for a Root admin.
select set_config(
    'request.jwt.claims',
    '{"sub":"a1000000-0000-0000-0000-000000000005","role":"authenticated","app_metadata":{"active_church_id":"00000000-0000-0000-0000-00000000000a"}}',
    true
);
select set_config('request.jwt.claim.sub', 'a1000000-0000-0000-0000-000000000005', true);
do $$
declare
    affected_rows bigint;
begin
    begin
        update public.churches
        set name = 'RLS bypass'
        where id = '00000000-0000-0000-0000-00000000000a';

        get diagnostics affected_rows = row_count;
        if affected_rows <> 0 then
            raise exception 'Direct church update was accepted';
        end if;
    exception
        when insufficient_privilege then null;
    end;

    begin
        insert into public.audit_logs (
            church_id, entity_type, action
        )
        values (
            '00000000-0000-0000-0000-00000000000a',
            'audit_logs',
            'forged'
        );
        raise exception 'Direct audit insert was accepted';
    exception
        when insufficient_privilege then null;
    end;
end;
$$;

reset role;
select 'ok 1 - BE-002 row-level security';
rollback;
