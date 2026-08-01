-- Allow a system administrator to issue or rotate the first Root Admin invite
-- link for a platform-managed tenant. The raw token is returned only once.

create or replace function public.create_platform_admin_invite_link(
    p_tenant_id uuid,
    p_expires_in_days integer default 7
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    actor_user_id uuid := app_security.require_system_admin();
    tenant public.churches%rowtype;
    root_ou_id uuid;
    invitation public.tenant_invitations%rowtype;
    invitation_id uuid;
    raw_token text := replace(gen_random_uuid()::text, '-', '')
        || replace(gen_random_uuid()::text, '-', '');
    invitation_expires_at timestamptz;
begin
    if p_expires_in_days < 1 or p_expires_in_days > 30 then
        raise exception using errcode = '22023', message = 'INVITATION_EXPIRY_INVALID';
    end if;

    select *
    into tenant
    from public.churches
    where id = p_tenant_id
      and status in ('trial', 'active')
      and is_active
      and deleted_at is null
    for update;
    if tenant.id is null then
        raise exception using errcode = 'P0002', message = 'TENANT_NOT_AVAILABLE';
    end if;

    select organization.id
    into root_ou_id
    from public.organization_units as organization
    where organization.church_id = tenant.id
      and organization.parent_id is null
      and organization.is_active
      and organization.deleted_at is null
    order by organization.created_at, organization.id
    limit 1;
    if root_ou_id is null then
        raise exception using errcode = 'P0002', message = 'ROOT_OU_NOT_FOUND';
    end if;

    invitation_expires_at := now() + make_interval(days => p_expires_in_days);

    select pending.*
    into invitation
    from public.tenant_invitations as pending
    where pending.church_id = tenant.id
      and pending.target_ou_id = root_ou_id
      and pending.permission = 'admin'
      and pending.status = 'pending'
    order by pending.created_at
    limit 1
    for update;

    if invitation.id is null then
        invitation_id := gen_random_uuid();
        insert into public.tenant_invitations (
            id, church_id, email, target_ou_id, permission, can_override,
            token_hash, status, expires_at, invited_by
        )
        values (
            invitation_id, tenant.id, null, root_ou_id, 'admin', false,
            encode(extensions.digest(raw_token, 'sha256'), 'hex'),
            'pending', invitation_expires_at, actor_user_id
        );
    else
        invitation_id := invitation.id;
        update public.tenant_invitations
        set token_hash = encode(extensions.digest(raw_token, 'sha256'), 'hex'),
            expires_at = invitation_expires_at,
            accepted_by = null,
            accepted_at = null,
            revoked_by = null,
            revoked_at = null
        where id = invitation_id;
    end if;

    insert into public.audit_logs (
        church_id, user_id, ou_id, entity_type, entity_id, action, after_data
    )
    values (
        tenant.id, actor_user_id, root_ou_id, 'tenant_invitations',
        invitation_id, 'create_platform_admin_invite_link',
        jsonb_build_object(
            'permission', 'admin',
            'expiresAt', invitation_expires_at,
            'delivery', 'manual_link'
        )
    );

    return jsonb_build_object(
        'tenantId', tenant.id,
        'tenantName', tenant.name,
        'invitationId', invitation_id,
        'inviteToken', raw_token,
        'expiresAt', invitation_expires_at
    );
end;
$$;

revoke all on function public.create_platform_admin_invite_link(uuid, integer) from public;
grant execute on function public.create_platform_admin_invite_link(uuid, integer) to authenticated;
