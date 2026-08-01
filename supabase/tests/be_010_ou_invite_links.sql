\set ON_ERROR_STOP on
select '1..1';
begin;

insert into public.churches (id, code, slug, name, status)
values ('00000000-0000-0000-0000-000000000110', 'INVITE', 'invite-test', 'Invite Test', 'active');

insert into public.users (id, auth_user_id, line_user_id, display_name)
values
('10000000-0000-0000-0000-000000000110', 'a1000000-0000-4000-8000-000000000110', 'invite-admin', 'Invite Admin'),
('10000000-0000-0000-0000-000000000111', 'a1000000-0000-4000-8000-000000000111', 'invite-recipient', 'Recipient'),
('10000000-0000-0000-0000-000000000112', 'a1000000-0000-4000-8000-000000000112', 'invite-other', 'Other User');

insert into public.church_members (id, church_id, user_id, status)
values
(
    '20000000-0000-0000-0000-000000000110',
    '00000000-0000-0000-0000-000000000110',
    '10000000-0000-0000-0000-000000000110',
    'active'
),
(
    '20000000-0000-0000-0000-000000000112',
    '00000000-0000-0000-0000-000000000110',
    '10000000-0000-0000-0000-000000000112',
    'active'
);

insert into public.organization_unit_types (id, church_id, code, name)
values (
    '30000000-0000-0000-0000-000000000110',
    '00000000-0000-0000-0000-000000000110',
    'GENERIC',
    'Generic'
);

insert into public.organization_units (
    id, church_id, structure_root_id, parent_id, ou_type_id, code, name, path, level
)
values
(
    '40000000-0000-0000-0000-000000000110',
    '00000000-0000-0000-0000-000000000110',
    '40000000-0000-0000-0000-000000000110',
    null,
    '30000000-0000-0000-0000-000000000110',
    'ROOT',
    'Root',
    '/invite-root',
    1
),
(
    '40000000-0000-0000-0000-000000000111',
    '00000000-0000-0000-0000-000000000110',
    '40000000-0000-0000-0000-000000000110',
    '40000000-0000-0000-0000-000000000110',
    '30000000-0000-0000-0000-000000000110',
    'GROUP',
    'Group',
    '/invite-root/group',
    2
);

insert into public.ou_members (
    id, church_id, ou_id, church_member_id, permission
)
values
(
    '50000000-0000-0000-0000-000000000110',
    '00000000-0000-0000-0000-000000000110',
    '40000000-0000-0000-0000-000000000110',
    '20000000-0000-0000-0000-000000000110',
    'admin'
),
(
    '50000000-0000-0000-0000-000000000112',
    '00000000-0000-0000-0000-000000000110',
    '40000000-0000-0000-0000-000000000111',
    '20000000-0000-0000-0000-000000000112',
    'manager'
);

create function pg_temp.assert_true(condition boolean, message text)
returns void language plpgsql as $$
begin
    if condition is not true then raise exception 'BE-010 assertion: %', message; end if;
end;
$$;

set local role authenticated;
select set_config(
    'request.jwt.claims',
    '{"sub":"a1000000-0000-4000-8000-000000000110","app_metadata":{"active_church_id":"00000000-0000-0000-0000-000000000110"}}',
    true
);

create temporary table invite_result as
select public.create_ou_invite_link(jsonb_build_object(
    'targetOuId', '40000000-0000-0000-0000-000000000111',
    'permission', 'data_entry',
    'expiresInDays', 7
)) as result;

reset role;

select pg_temp.assert_true(
    length((select result #>> '{data,inviteToken}' from invite_result)) = 64,
    'raw token returned once'
);
select pg_temp.assert_true(
    (
        select token_hash <> (select result #>> '{data,inviteToken}' from invite_result)
          and email is null
          and permission = 'data_entry'
        from public.tenant_invitations
        where id = (select (result #>> '{data,invitationId}')::uuid from invite_result)
    ),
    'only token hash and scoped permission stored'
);

create temporary table accepted_result as
select public.accept_tenant_invitation_by_token(
    '10000000-0000-0000-0000-000000000111',
    (select result #>> '{data,inviteToken}' from invite_result)
) as result;

select pg_temp.assert_true(
    (select (result ->> 'accepted')::boolean from accepted_result),
    'first redemption accepted'
);
select pg_temp.assert_true(
    exists (
        select 1
        from public.church_members as membership
        join public.ou_members as assignment
          on assignment.church_id = membership.church_id
         and assignment.church_member_id = membership.id
        where membership.user_id = '10000000-0000-0000-0000-000000000111'
          and assignment.ou_id = '40000000-0000-0000-0000-000000000111'
          and assignment.permission = 'data_entry'
          and assignment.is_active
    ),
    'membership and OU permission created'
);
select pg_temp.assert_true(
    not (
        select (public.accept_tenant_invitation_by_token(
            '10000000-0000-0000-0000-000000000111',
            (select result #>> '{data,inviteToken}' from invite_result)
        ) ->> 'accepted')::boolean
    ),
    'same user retry is idempotent'
);

do $$
begin
    begin
        perform public.accept_tenant_invitation_by_token(
            '10000000-0000-0000-0000-000000000112',
            (select result #>> '{data,inviteToken}' from invite_result)
        );
        raise exception 'used token was accepted by another user';
    exception when unique_violation then
        if sqlerrm <> 'INVITATION_ALREADY_USED' then raise; end if;
    end;
end;
$$;

set local role authenticated;
select pg_temp.assert_true(
    jsonb_array_length(public.get_ou_members(
        '40000000-0000-0000-0000-000000000111'
    ) #> '{data,items}') = 2,
    'authorized manager UI can list every exact OU member'
);

create temporary table root_admin_invite_result as
select public.create_ou_invite_link(jsonb_build_object(
    'targetOuId', '40000000-0000-0000-0000-000000000110',
    'permission', 'admin',
    'expiresInDays', 7
)) as result;

create temporary table group_admin_invite_result as
select public.create_ou_invite_link(jsonb_build_object(
    'targetOuId', '40000000-0000-0000-0000-000000000111',
    'permission', 'admin',
    'expiresInDays', 7
)) as result;

reset role;

select public.accept_tenant_invitation_by_token(
    '10000000-0000-0000-0000-000000000111',
    (select result #>> '{data,inviteToken}' from root_admin_invite_result)
);
select public.accept_tenant_invitation_by_token(
    '10000000-0000-0000-0000-000000000111',
    (select result #>> '{data,inviteToken}' from group_admin_invite_result)
);

select pg_temp.assert_true(
    (
        select count(*) = 2
        from public.ou_members as assignment
        join public.church_members as membership
          on membership.church_id = assignment.church_id
         and membership.id = assignment.church_member_id
        where membership.user_id = '10000000-0000-0000-0000-000000000111'
          and assignment.permission = 'admin'
          and assignment.is_active
          and assignment.deleted_at is null
    ),
    'same LINE user keeps direct Admin assignments on Root and Group'
);

set local role authenticated;
select set_config(
    'request.jwt.claims',
    '{"sub":"a1000000-0000-4000-8000-000000000111","app_metadata":{"active_church_id":"00000000-0000-0000-0000-000000000110"}}',
    true
);
select pg_temp.assert_true(
    jsonb_array_length(public.get_my_profile() -> 'permissions') = 3,
    'profile returns every OU assignment without overwriting'
);

select set_config(
    'request.jwt.claims',
    '{"sub":"a1000000-0000-4000-8000-000000000112","app_metadata":{"active_church_id":"00000000-0000-0000-0000-000000000110"}}',
    true
);
do $$
begin
    begin
        perform public.create_ou_invite_link(jsonb_build_object(
            'targetOuId', '40000000-0000-0000-0000-000000000111',
            'permission', 'admin',
            'expiresInDays', 7
        ));
        raise exception 'Manager Admin grant was accepted';
    exception when insufficient_privilege then
        if sqlerrm <> 'ADMIN_GRANT_NOT_ALLOWED' then raise; end if;
    end;
end;
$$;

select set_config(
    'request.jwt.claims',
    '{"sub":"a1000000-0000-4000-8000-000000000111","app_metadata":{"active_church_id":"00000000-0000-0000-0000-000000000110"}}',
    true
);
create temporary table expired_invite_result as
select public.create_ou_invite_link(jsonb_build_object(
    'targetOuId', '40000000-0000-0000-0000-000000000111',
    'permission', 'viewer',
    'expiresInDays', 1
)) as result;

reset role;

update public.tenant_invitations
set created_at = now() - interval '2 days',
    expires_at = now() - interval '1 day'
where id = (
    select (result #>> '{data,invitationId}')::uuid
    from expired_invite_result
);

do $$
begin
    begin
        perform public.accept_tenant_invitation_by_token(
            '10000000-0000-0000-0000-000000000112',
            (select result #>> '{data,inviteToken}' from expired_invite_result)
        );
        raise exception 'expired token was accepted';
    exception when invalid_parameter_value then
        if sqlerrm <> 'INVITATION_EXPIRED' then raise; end if;
    end;
end;
$$;

select pg_temp.assert_true(
    (
        select count(*) = 7
        from public.audit_logs
        where entity_type = 'tenant_invitations'
          and church_id = '00000000-0000-0000-0000-000000000110'
    ),
    'link creations and redemption audited'
);

select 'ok 1 - BE-010 OU invite links';
rollback;
