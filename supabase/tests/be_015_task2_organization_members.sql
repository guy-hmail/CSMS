\set ON_ERROR_STOP on

select '1..1';

begin;

insert into public.churches (id, code, slug, name, status)
values
    ('91000000-0000-4000-8000-000000000001', 'TASK2_A', 'task2-a', 'Task 2 Church A', 'active'),
    ('91000000-0000-4000-8000-000000000002', 'TASK2_B', 'task2-b', 'Task 2 Church B', 'active');

insert into public.users (id, auth_user_id, line_user_id, display_name, global_role)
values
    ('92000000-0000-4000-8000-000000000001', '92100000-0000-4000-8000-000000000001', 'task2-admin', 'Task 2 Admin', 'user'),
    ('92000000-0000-4000-8000-000000000002', '92100000-0000-4000-8000-000000000002', 'task2-manager', 'Task 2 Manager', 'user'),
    ('92000000-0000-4000-8000-000000000003', '92100000-0000-4000-8000-000000000003', 'task2-member', 'Task 2 Member', 'user'),
    ('92000000-0000-4000-8000-000000000004', '92100000-0000-4000-8000-000000000004', 'task2-other', 'Task 2 Other', 'user'),
    ('92000000-0000-4000-8000-000000000005', '92100000-0000-4000-8000-000000000005', 'task2-b-user', 'Task 2 Church B User', 'user');

insert into public.church_members (id, church_id, user_id, status)
values
    ('93000000-0000-4000-8000-000000000001', '91000000-0000-4000-8000-000000000001', '92000000-0000-4000-8000-000000000001', 'active'),
    ('93000000-0000-4000-8000-000000000002', '91000000-0000-4000-8000-000000000001', '92000000-0000-4000-8000-000000000002', 'active'),
    ('93000000-0000-4000-8000-000000000003', '91000000-0000-4000-8000-000000000001', '92000000-0000-4000-8000-000000000003', 'active'),
    ('93000000-0000-4000-8000-000000000004', '91000000-0000-4000-8000-000000000001', '92000000-0000-4000-8000-000000000004', 'active'),
    ('93000000-0000-4000-8000-000000000005', '91000000-0000-4000-8000-000000000002', '92000000-0000-4000-8000-000000000005', 'active');

insert into public.organization_unit_types (id, church_id, code, name)
values
    ('94000000-0000-4000-8000-000000000001', '91000000-0000-4000-8000-000000000001', 'GENERIC', 'Generic'),
    ('94000000-0000-4000-8000-000000000002', '91000000-0000-4000-8000-000000000002', 'GENERIC', 'Generic');

insert into public.organization_units (
    id, church_id, structure_root_id, parent_id, ou_type_id,
    code, name, path, level, allow_data_entry
)
values
    ('95000000-0000-4000-8000-000000000001', '91000000-0000-4000-8000-000000000001', '95000000-0000-4000-8000-000000000001', null, '94000000-0000-4000-8000-000000000001', 'ROOT-A', 'Root A', '/root-a', 1, false),
    ('95000000-0000-4000-8000-000000000002', '91000000-0000-4000-8000-000000000001', '95000000-0000-4000-8000-000000000001', '95000000-0000-4000-8000-000000000001', '94000000-0000-4000-8000-000000000001', 'BRANCH', 'Branch', '/root-a/branch', 2, false),
    ('95000000-0000-4000-8000-000000000003', '91000000-0000-4000-8000-000000000001', '95000000-0000-4000-8000-000000000001', '95000000-0000-4000-8000-000000000002', '94000000-0000-4000-8000-000000000001', 'MEMBERS', 'Members OU', '/root-a/branch/members', 3, true),
    ('95000000-0000-4000-8000-000000000004', '91000000-0000-4000-8000-000000000001', '95000000-0000-4000-8000-000000000001', '95000000-0000-4000-8000-000000000002', '94000000-0000-4000-8000-000000000001', 'MOVE', 'Move OU', '/root-a/branch/move', 3, false),
    ('95000000-0000-4000-8000-000000000005', '91000000-0000-4000-8000-000000000001', '95000000-0000-4000-8000-000000000001', '95000000-0000-4000-8000-000000000004', '94000000-0000-4000-8000-000000000001', 'MOVE-CHILD', 'Move Child', '/root-a/branch/move/child', 4, true),
    ('95000000-0000-4000-8000-000000000006', '91000000-0000-4000-8000-000000000001', '95000000-0000-4000-8000-000000000001', '95000000-0000-4000-8000-000000000002', '94000000-0000-4000-8000-000000000001', 'OTHER-PARENT', 'Other Parent', '/root-a/branch/other', 3, false),
    ('95000000-0000-4000-8000-000000000007', '91000000-0000-4000-8000-000000000001', '95000000-0000-4000-8000-000000000001', '95000000-0000-4000-8000-000000000002', '94000000-0000-4000-8000-000000000001', 'DELETE-ME', 'Delete Me', '/root-a/branch/delete-me', 3, true),
    ('95000000-0000-4000-8000-000000000008', '91000000-0000-4000-8000-000000000001', '95000000-0000-4000-8000-000000000001', '95000000-0000-4000-8000-000000000002', '94000000-0000-4000-8000-000000000001', 'HISTORY', 'History OU', '/root-a/branch/history', 3, true),
    ('95000000-0000-4000-8000-000000000009', '91000000-0000-4000-8000-000000000001', '95000000-0000-4000-8000-000000000001', '95000000-0000-4000-8000-000000000002', '94000000-0000-4000-8000-000000000001', 'ADMIN-TARGET', 'Admin Target', '/root-a/branch/admin-target', 3, true),
    ('95000000-0000-4000-8000-00000000000b', '91000000-0000-4000-8000-000000000002', '95000000-0000-4000-8000-00000000000b', null, '94000000-0000-4000-8000-000000000002', 'ROOT-B', 'Root B', '/root-b', 1, true);

insert into public.ou_members (
    id, church_id, ou_id, church_member_id, permission, can_override
)
values
    ('96000000-0000-4000-8000-000000000001', '91000000-0000-4000-8000-000000000001', '95000000-0000-4000-8000-000000000001', '93000000-0000-4000-8000-000000000001', 'admin', false),
    ('96000000-0000-4000-8000-000000000002', '91000000-0000-4000-8000-000000000001', '95000000-0000-4000-8000-000000000002', '93000000-0000-4000-8000-000000000002', 'manager', false),
    ('96000000-0000-4000-8000-000000000003', '91000000-0000-4000-8000-000000000001', '95000000-0000-4000-8000-000000000003', '93000000-0000-4000-8000-000000000003', 'viewer', false),
    ('96000000-0000-4000-8000-000000000004', '91000000-0000-4000-8000-000000000001', '95000000-0000-4000-8000-000000000009', '93000000-0000-4000-8000-000000000004', 'admin', false),
    ('96000000-0000-4000-8000-000000000005', '91000000-0000-4000-8000-000000000002', '95000000-0000-4000-8000-00000000000b', '93000000-0000-4000-8000-000000000005', 'admin', false);

insert into public.tenant_invitations (
    id, church_id, display_name, target_ou_id, permission,
    can_override, token_hash, status, expires_at, invited_by, created_at
)
values
    ('96500000-0000-4000-8000-000000000001', '91000000-0000-4000-8000-000000000001', 'Pending Viewer', '95000000-0000-4000-8000-000000000003', 'viewer', false, 'task2-pending-viewer', 'pending', now() + interval '1 day', '92000000-0000-4000-8000-000000000001', now()),
    ('96500000-0000-4000-8000-000000000002', '91000000-0000-4000-8000-000000000001', 'Expired Viewer', '95000000-0000-4000-8000-000000000003', 'viewer', false, 'task2-expired-viewer', 'pending', now() - interval '1 day', '92000000-0000-4000-8000-000000000001', now() - interval '2 days'),
    ('96500000-0000-4000-8000-000000000003', '91000000-0000-4000-8000-000000000001', 'Protected Admin', '95000000-0000-4000-8000-000000000003', 'admin', false, 'task2-protected-admin', 'pending', now() + interval '1 day', '92000000-0000-4000-8000-000000000001', now());

insert into public.statistic_periods (
    id, church_id, year, week_no, period_start, period_end, label
)
values (
    '97000000-0000-4000-8000-000000000001', '91000000-0000-4000-8000-000000000001',
    2026, 31, '2026-07-27', '2026-08-02', '2026-W31'
);

insert into public.statistic_submissions (
    id, church_id, period_id, ou_id, status
)
values (
    '98000000-0000-4000-8000-000000000001', '91000000-0000-4000-8000-000000000001',
    '97000000-0000-4000-8000-000000000001', '95000000-0000-4000-8000-000000000008', 'draft'
);

create function pg_temp.assert_true(condition boolean, failure_message text)
returns void
language plpgsql
as $$
begin
    if condition is not true then
        raise exception 'Task 2 assertion failed: %', failure_message;
    end if;
end;
$$;

set local role authenticated;
select set_config('request.jwt.claim.sub', '92100000-0000-4000-8000-000000000002', true);
select set_config('request.jwt.claims', '{"sub":"92100000-0000-4000-8000-000000000002","role":"authenticated","app_metadata":{"active_church_id":"91000000-0000-4000-8000-000000000001"}}', true);

select pg_temp.assert_true(
    public.get_ou_members('95000000-0000-4000-8000-000000000003') #>> '{data,canGrantOverride}' = 'false',
    'manager capability response'
);
select pg_temp.assert_true(
    public.get_ou_members('95000000-0000-4000-8000-000000000003') #>> '{data,items,0,canEdit}' = 'true',
    'manager can edit ordinary assignment'
);

select public.update_ou_member_assignment(jsonb_build_object(
    'assignmentId', '96000000-0000-4000-8000-000000000003',
    'permission', 'data_entry', 'canOverride', false
));
select pg_temp.assert_true(
    (select permission = 'data_entry' from public.ou_members where id = '96000000-0000-4000-8000-000000000003'),
    'manager updates ordinary assignment role'
);

do $$
begin
    begin
        perform public.update_ou_member_assignment(jsonb_build_object(
            'assignmentId', '96000000-0000-4000-8000-000000000003',
            'permission', 'approver', 'canOverride', true
        ));
        raise exception 'manager override grant was accepted';
    exception when others then
        if sqlerrm <> 'MANAGER_ASSIGNMENT_CHANGE_NOT_ALLOWED' then raise; end if;
    end;
    begin
        perform public.remove_ou_member(jsonb_build_object(
            'assignmentId', '96000000-0000-4000-8000-000000000002',
            'reason', 'self removal should fail'
        ));
        raise exception 'manager source removal was accepted';
    exception when others then
        if sqlerrm <> 'MANAGER_ASSIGNMENT_REMOVE_NOT_ALLOWED' then raise; end if;
    end;
    begin
        perform public.remove_ou_member(jsonb_build_object(
            'assignmentId', '96000000-0000-4000-8000-000000000004',
            'reason', 'admin removal should fail'
        ));
        raise exception 'manager admin removal was accepted';
    exception when others then
        if sqlerrm <> 'MANAGER_ASSIGNMENT_REMOVE_NOT_ALLOWED' then raise; end if;
    end;
end;
$$;

select public.assign_ou_member(jsonb_build_object(
    'ouId', '95000000-0000-4000-8000-000000000003',
    'churchMemberId', '93000000-0000-4000-8000-000000000004',
    'permission', 'viewer', 'canOverride', false
));
select pg_temp.assert_true(
    (select count(*) = 1 from public.ou_members
     where ou_id = '95000000-0000-4000-8000-000000000003'
       and church_member_id = '93000000-0000-4000-8000-000000000004'
       and permission = 'viewer' and is_active and deleted_at is null),
    'manager assigns existing tenant account'
);
select pg_temp.assert_true(
    jsonb_array_length(public.search_assignable_members('95000000-0000-4000-8000-000000000003', 'Task 2') #> '{data,items}') = 4,
    'assignable search is tenant isolated'
);
select pg_temp.assert_true(
    exists (
        select 1
        from jsonb_array_elements(public.list_ou_invitations('95000000-0000-4000-8000-000000000003') #> '{data,items}') as item
        where item ->> 'invitationId' = '96500000-0000-4000-8000-000000000002'
          and item ->> 'status' = 'expired'
    ),
    'invitation list derives expired status'
);
select public.revoke_ou_invitation(jsonb_build_object(
    'invitationId', '96500000-0000-4000-8000-000000000001',
    'reason', 'manager test revoke'
));
select pg_temp.assert_true(
    exists (
        select 1
        from jsonb_array_elements(public.list_ou_invitations('95000000-0000-4000-8000-000000000003') #> '{data,items}') as item
        where item ->> 'invitationId' = '96500000-0000-4000-8000-000000000001'
          and item ->> 'status' = 'revoked'
    ),
    'manager revokes ordinary invitation'
);
select public.reissue_ou_invitation(jsonb_build_object(
    'invitationId', '96500000-0000-4000-8000-000000000001',
    'expiresInDays', 7
));
select pg_temp.assert_true(
    exists (
        select 1
        from jsonb_array_elements(public.list_ou_invitations('95000000-0000-4000-8000-000000000003') #> '{data,items}') as item
        where item ->> 'invitationId' = '96500000-0000-4000-8000-000000000001'
          and item ->> 'status' = 'pending'
          and (item ->> 'expiresAt')::timestamptz > now()
    ),
    'invitation reissue stores a new pending link'
);

do $$
begin
    begin
        perform public.revoke_ou_invitation(jsonb_build_object(
            'invitationId', '96500000-0000-4000-8000-000000000003',
            'reason', 'manager must not revoke admin invite'
        ));
        raise exception 'manager admin invitation revoke was accepted';
    exception when others then
        if sqlerrm <> 'MANAGER_INVITATION_CHANGE_NOT_ALLOWED' then raise; end if;
    end;
    begin
        perform public.assign_ou_member(jsonb_build_object(
            'ouId', '95000000-0000-4000-8000-000000000003',
            'churchMemberId', '93000000-0000-4000-8000-000000000005',
            'permission', 'viewer', 'canOverride', false
        ));
        raise exception 'cross-tenant member assignment was accepted';
    exception when others then
        if sqlerrm <> 'CHURCH_MEMBER_NOT_FOUND' then raise; end if;
    end;
    begin
        perform public.soft_delete_organization_unit(jsonb_build_object(
            'ouId', '95000000-0000-4000-8000-000000000004', 'reason', 'has child'
        ));
        raise exception 'OU with active child was deleted';
    exception when others then
        if sqlerrm <> 'OU_HAS_ACTIVE_CHILDREN' then raise; end if;
    end;
    begin
        perform public.soft_delete_organization_unit(jsonb_build_object(
            'ouId', '95000000-0000-4000-8000-000000000008', 'reason', 'has history'
        ));
        raise exception 'OU with submission history was deleted';
    exception when others then
        if sqlerrm <> 'OU_HAS_SUBMISSION_HISTORY' then raise; end if;
    end;
end;
$$;

select public.update_organization_unit(jsonb_build_object(
    'ouId', '95000000-0000-4000-8000-000000000004',
    'parentOuId', '95000000-0000-4000-8000-000000000006',
    'ouTypeId', '94000000-0000-4000-8000-000000000001',
    'code', 'MOVE-UPDATED', 'name', 'Move OU Updated',
    'allowDataEntry', false, 'sortOrder', 12
));
select pg_temp.assert_true(
    (select parent_id = '95000000-0000-4000-8000-000000000002'
        and level = 3
        and path = '/root-a/branch/move'
        and code = 'MOVE'
        and name = 'Move OU Updated'
     from public.organization_units where id = '95000000-0000-4000-8000-000000000004'),
    'OU metadata updates while immutable code and hierarchy remain unchanged'
);
select pg_temp.assert_true(
    (select level = 4
        and path = '/root-a/branch/move/child'
     from public.organization_units where id = '95000000-0000-4000-8000-000000000005'),
    'metadata-only OU update leaves descendant hierarchy unchanged'
);

select public.soft_delete_organization_unit(jsonb_build_object(
    'ouId', '95000000-0000-4000-8000-000000000007', 'reason', 'safe cleanup'
));
reset role;
select pg_temp.assert_true(
    (select not is_active and deleted_at is not null from public.organization_units where id = '95000000-0000-4000-8000-000000000007'),
    'safe OU soft delete persists'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '92100000-0000-4000-8000-000000000001', true);
select set_config('request.jwt.claims', '{"sub":"92100000-0000-4000-8000-000000000001","role":"authenticated","app_metadata":{"active_church_id":"91000000-0000-4000-8000-000000000001"}}', true);

select public.update_ou_member_assignment(jsonb_build_object(
    'assignmentId', '96000000-0000-4000-8000-000000000003',
    'permission', 'approver', 'canOverride', true
));
select pg_temp.assert_true(
    (select permission = 'approver' and can_override from public.ou_members where id = '96000000-0000-4000-8000-000000000003'),
    'admin grants approver override'
);
select public.remove_ou_member(jsonb_build_object(
    'assignmentId', '96000000-0000-4000-8000-000000000003',
    'reason', 'role no longer required'
));
select pg_temp.assert_true(
    (select not is_active and deleted_at is not null and deleted_by = '92000000-0000-4000-8000-000000000001'
     from public.ou_members where id = '96000000-0000-4000-8000-000000000003'),
    'admin removes assignment with soft delete'
);

do $$
declare affected_rows integer;
begin
    begin
        update public.ou_members
        set permission = 'admin'
        where id = '96000000-0000-4000-8000-000000000002';
        get diagnostics affected_rows = row_count;
        if affected_rows <> 0 then raise exception 'direct OU member update bypassed RLS'; end if;
    exception when insufficient_privilege then null;
    end;

    begin
        perform public.update_ou_member_assignment(jsonb_build_object(
            'assignmentId', '96000000-0000-4000-8000-000000000005',
            'permission', 'viewer', 'canOverride', false
        ));
        raise exception 'cross-tenant assignment update was accepted';
    exception when others then
        if sqlerrm <> 'OU_MEMBER_ASSIGNMENT_NOT_FOUND' then raise; end if;
    end;

    begin
        perform public.remove_ou_member(jsonb_build_object(
            'assignmentId', '96000000-0000-4000-8000-000000000001',
            'reason', 'would remove final Root admin'
        ));
        raise exception 'last Root admin removal was accepted';
    exception when others then
        if sqlerrm <> 'LAST_ROOT_ADMIN_REQUIRED' then raise; end if;
    end;
end;
$$;

reset role;

select pg_temp.assert_true(
    (select count(*) >= 8 from public.audit_logs
     where church_id = '91000000-0000-4000-8000-000000000001'
       and action in ('update_assignment', 'remove_assignment', 'assign_member', 'update', 'soft_delete', 'revoke_invitation', 'reissue_invitation')),
    'Task 2 critical mutations are audited'
);

select 'ok 1 - Task 2 organization and member management';
rollback;
