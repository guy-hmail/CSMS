\set ON_ERROR_STOP on
select '1..1';
begin;

create function pg_temp.assert_true(condition boolean, message text)
returns void language plpgsql as $$
begin
    if condition is not true then raise exception 'BE-011 assertion: %', message; end if;
end;
$$;

insert into public.users (
    id, auth_user_id, line_user_id, display_name, global_role
)
values (
    '10000000-0000-0000-0000-000000000118',
    'a1000000-0000-4000-8000-000000000118',
    'platform-invite-system-admin',
    'System Admin',
    'system_admin'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', 'a1000000-0000-4000-8000-000000000118', true);
select set_config(
    'request.jwt.claims',
    '{"sub":"a1000000-0000-4000-8000-000000000118","role":"authenticated"}',
    true
);

create temporary table first_invite as
select public.create_platform_admin_invite_link(
    '81000000-0000-4000-8000-000000000001',
    7
) as result;

create temporary table rotated_invite as
select public.create_platform_admin_invite_link(
    '81000000-0000-4000-8000-000000000001',
    14
) as result;

reset role;

select pg_temp.assert_true(
    (select result #>> '{invitationId}' from first_invite)
        = (select result #>> '{invitationId}' from rotated_invite),
    'rotation reuses the pending Root Admin invitation'
);
select pg_temp.assert_true(
    (select result #>> '{inviteToken}' from first_invite)
        <> (select result #>> '{inviteToken}' from rotated_invite),
    'rotation returns a new raw token'
);
select pg_temp.assert_true(
    (
        select invitation.token_hash
            = encode(
                extensions.digest(
                    (select result #>> '{inviteToken}' from rotated_invite),
                    'sha256'
                ),
                'hex'
            )
        from public.tenant_invitations as invitation
        where invitation.id = (
            select (result #>> '{invitationId}')::uuid
            from rotated_invite
        )
    ),
    'database stores only the latest token hash'
);
select pg_temp.assert_true(
    (
        select permission = 'admin'
          and target_ou_id = '84000000-0000-4000-8000-000000000001'
          and expires_at > now() + interval '13 days'
        from public.tenant_invitations
        where id = (
            select (result #>> '{invitationId}')::uuid
            from rotated_invite
        )
    ),
    'invite is scoped to Root Admin with requested expiry'
);

insert into public.users (
    id, auth_user_id, line_user_id, display_name, global_role
)
values (
    '10000000-0000-0000-0000-000000000119',
    'a1000000-0000-4000-8000-000000000119',
    'platform-invite-non-admin',
    'Non Admin',
    'user'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', 'a1000000-0000-4000-8000-000000000119', true);
select set_config(
    'request.jwt.claims',
    '{"sub":"a1000000-0000-4000-8000-000000000119","role":"authenticated"}',
    true
);
do $$
begin
    begin
        perform public.create_platform_admin_invite_link(
            '81000000-0000-4000-8000-000000000001',
            7
        );
        raise exception 'non-system-admin invite was accepted';
    exception when insufficient_privilege then
        if sqlerrm <> 'SYSTEM_ADMIN_REQUIRED' then raise; end if;
    end;
end;
$$;

reset role;
select 'ok 1 - BE-011 platform admin invite';
rollback;
