-- OU-scoped, single-use invitation links for manual delivery (for example via LINE).
-- The raw token is returned once; only its SHA-256 hash is stored.

alter table public.tenant_invitations
    alter column email drop not null;

drop index if exists public.uq_pending_tenant_invitation;

create unique index uq_pending_tenant_invitation
    on public.tenant_invitations (
        church_id,
        lower(email),
        target_ou_id,
        permission
    )
    where status = 'pending' and email is not null;

create or replace function public.create_ou_invite_link(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    actor_user_id uuid := app_security.require_current_user_id();
    actor_membership_id uuid := app_security.current_church_member_id();
    source_assignment_id uuid;
    source_assignment public.ou_members%rowtype;
    target_ou public.organization_units%rowtype;
    invitation_id uuid := gen_random_uuid();
    raw_token text := replace(gen_random_uuid()::text, '-', '')
        || replace(gen_random_uuid()::text, '-', '');
    requested_permission text := lower(btrim(coalesce(p_payload ->> 'permission', '')));
    requested_override boolean := coalesce((p_payload ->> 'canOverride')::boolean, false);
    expires_in_days integer := coalesce((p_payload ->> 'expiresInDays')::integer, 7);
    invitation_expires_at timestamptz;
begin
    if requested_permission not in ('admin', 'manager', 'data_entry', 'approver', 'viewer') then
        raise exception using errcode = '22023', message = 'INVITATION_PERMISSION_INVALID';
    end if;
    if requested_override and requested_permission <> 'approver' then
        raise exception using errcode = '22023', message = 'OVERRIDE_REQUIRES_APPROVER';
    end if;
    if expires_in_days < 1 or expires_in_days > 30 then
        raise exception using errcode = '22023', message = 'INVITATION_EXPIRY_INVALID';
    end if;

    select *
    into target_ou
    from public.organization_units
    where id = (p_payload ->> 'targetOuId')::uuid
      and church_id = app_security.current_church_id()
      and is_active
      and deleted_at is null;
    if target_ou.id is null then
        raise exception using errcode = 'P0002', message = 'TARGET_OU_NOT_FOUND';
    end if;

    source_assignment_id := app_security.authorization_source(
        target_ou.id,
        array['admin', 'manager']
    );
    if source_assignment_id is null then
        raise exception using errcode = '42501', message = 'PERMISSION_DENIED';
    end if;

    select *
    into source_assignment
    from public.ou_members
    where id = source_assignment_id;

    if source_assignment.permission = 'manager'
       and (requested_permission = 'admin' or requested_override) then
        raise exception using errcode = '42501', message = 'MANAGER_GRANT_NOT_ALLOWED';
    end if;

    -- Admin can only delegate Admin at the exact root where their own direct
    -- Admin assignment exists. This prevents privilege escalation in a subtree.
    if requested_permission = 'admin'
       and (
           target_ou.parent_id is not null
           or source_assignment.permission <> 'admin'
           or source_assignment.ou_id <> target_ou.id
       ) then
        raise exception using errcode = '42501', message = 'ADMIN_GRANT_NOT_ALLOWED';
    end if;

    invitation_expires_at := now() + make_interval(days => expires_in_days);

    insert into public.tenant_invitations (
        id, church_id, email, display_name, target_ou_id, permission,
        can_override, token_hash, status, expires_at, invited_by
    )
    values (
        invitation_id,
        target_ou.church_id,
        null,
        nullif(btrim(p_payload ->> 'displayName'), ''),
        target_ou.id,
        requested_permission,
        requested_override,
        encode(extensions.digest(raw_token, 'sha256'), 'hex'),
        'pending',
        invitation_expires_at,
        actor_user_id
    );

    insert into public.audit_logs (
        church_id, user_id, actor_church_member_id, ou_id,
        source_ou_member_id, entity_type, entity_id, action, after_data
    )
    values (
        target_ou.church_id, actor_user_id, actor_membership_id, target_ou.id,
        source_assignment_id, 'tenant_invitations', invitation_id,
        'create_ou_invite_link',
        jsonb_build_object(
            'permission', requested_permission,
            'canOverride', requested_override,
            'expiresAt', invitation_expires_at,
            'delivery', 'manual_link'
        )
    );

    return jsonb_build_object(
        'success', true,
        'data', jsonb_build_object(
            'invitationId', invitation_id,
            'inviteToken', raw_token,
            'expiresAt', invitation_expires_at
        )
    );
exception
    when invalid_text_representation then
        raise exception using errcode = '22023', message = 'INVITATION_PAYLOAD_INVALID';
end;
$$;

create or replace function public.accept_tenant_invitation_by_token(
    p_user_id uuid,
    p_raw_token text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    invitation public.tenant_invitations%rowtype;
    membership_id uuid;
    assignment_id uuid;
    supplied_hash text;
begin
    if current_user not in ('postgres', 'service_role') then
        raise exception using errcode = '42501', message = 'SERVICE_ROLE_REQUIRED';
    end if;
    if p_raw_token is null or length(p_raw_token) < 32 or length(p_raw_token) > 256 then
        raise exception using errcode = '22023', message = 'INVITATION_TOKEN_INVALID';
    end if;
    if not exists (
        select 1
        from public.users as app_user
        where app_user.id = p_user_id
          and app_user.is_active
          and app_user.deleted_at is null
    ) then
        raise exception using errcode = 'P0002', message = 'USER_NOT_FOUND';
    end if;

    supplied_hash := encode(extensions.digest(p_raw_token, 'sha256'), 'hex');

    select pending.*
    into invitation
    from public.tenant_invitations as pending
    join public.churches as church
      on church.id = pending.church_id
     and church.status in ('trial', 'active')
     and church.is_active
     and church.deleted_at is null
    join public.organization_units as target
      on target.church_id = pending.church_id
     and target.id = pending.target_ou_id
     and target.is_active
     and target.deleted_at is null
    where pending.token_hash = supplied_hash
    for update of pending;

    if invitation.id is null then
        raise exception using errcode = 'P0002', message = 'INVITATION_NOT_FOUND';
    end if;
    if invitation.status = 'accepted' and invitation.accepted_by = p_user_id then
        return jsonb_build_object(
            'tenantId', invitation.church_id,
            'ouId', invitation.target_ou_id,
            'permission', invitation.permission,
            'accepted', false
        );
    end if;
    if invitation.status <> 'pending' then
        raise exception using errcode = '23505', message = 'INVITATION_ALREADY_USED';
    end if;
    if invitation.expires_at <= now() then
        raise exception using errcode = '22023', message = 'INVITATION_EXPIRED';
    end if;

    insert into public.church_members (
        church_id, user_id, status, joined_at, created_by
    )
    values (
        invitation.church_id, p_user_id, 'active', now(), invitation.invited_by
    )
    on conflict (church_id, user_id) do update
    set status = 'active',
        joined_at = coalesce(public.church_members.joined_at, excluded.joined_at)
    returning id into membership_id;

    insert into public.ou_members (
        church_id, ou_id, church_member_id, permission,
        can_override, is_active, assigned_by
    )
    values (
        invitation.church_id, invitation.target_ou_id, membership_id,
        invitation.permission, invitation.can_override, true, invitation.invited_by
    )
    on conflict (church_id, ou_id, church_member_id, permission) do update
    set is_active = true,
        can_override = excluded.can_override,
        deleted_at = null,
        deleted_by = null
    returning id into assignment_id;

    update public.tenant_invitations
    set status = 'accepted',
        accepted_by = p_user_id,
        accepted_at = now()
    where id = invitation.id;

    insert into public.audit_logs (
        church_id, user_id, actor_church_member_id, ou_id,
        source_ou_member_id, entity_type, entity_id, action, metadata
    )
    values (
        invitation.church_id, p_user_id, membership_id, invitation.target_ou_id,
        assignment_id, 'tenant_invitations', invitation.id,
        'accept_tenant_invitation_by_token',
        jsonb_build_object('permission', invitation.permission)
    );

    return jsonb_build_object(
        'tenantId', invitation.church_id,
        'ouId', invitation.target_ou_id,
        'permission', invitation.permission,
        'accepted', true
    );
end;
$$;

create or replace function public.get_ou_members(p_ou_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
    ignored_user_id uuid := app_security.require_current_user_id();
    source_assignment_id uuid;
    items jsonb;
begin
    source_assignment_id := app_security.authorization_source(
        p_ou_id,
        array['admin', 'manager']
    );
    if source_assignment_id is null then
        raise exception using errcode = '42501', message = 'PERMISSION_DENIED';
    end if;

    select coalesce(
        jsonb_agg(
            jsonb_build_object(
                'assignmentId', assignment.id,
                'ouId', assignment.ou_id,
                'accountId', app_user.id,
                'displayName', app_user.display_name,
                'lineUserId', app_user.line_user_id,
                'email', app_user.email,
                'role', assignment.permission,
                'canOverride', assignment.can_override,
                'assignedAt', assignment.assigned_at
            )
            order by app_user.display_name, assignment.assigned_at
        ),
        '[]'::jsonb
    )
    into items
    from public.ou_members as assignment
    join public.church_members as membership
      on membership.church_id = assignment.church_id
     and membership.id = assignment.church_member_id
     and membership.status = 'active'
    join public.users as app_user
      on app_user.id = membership.user_id
     and app_user.is_active
     and app_user.deleted_at is null
    where assignment.church_id = app_security.current_church_id()
      and assignment.ou_id = p_ou_id
      and assignment.is_active
      and assignment.deleted_at is null;

    return jsonb_build_object(
        'success', true,
        'data', jsonb_build_object('items', items)
    );
end;
$$;

revoke all on function public.create_ou_invite_link(jsonb) from public;
grant execute on function public.create_ou_invite_link(jsonb) to authenticated;

revoke all on function public.accept_tenant_invitation_by_token(uuid, text) from public;
grant execute on function public.accept_tenant_invitation_by_token(uuid, text) to service_role;

revoke all on function public.get_ou_members(uuid) from public;
grant execute on function public.get_ou_members(uuid) to authenticated;
