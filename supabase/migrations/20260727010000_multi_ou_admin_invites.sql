-- Allow an Admin on an ancestor OU to delegate Admin within that subtree.
-- Managers still cannot grant Admin or can_override. When an actor has
-- multiple assignments, privileged grants deliberately select an Admin
-- authorization source instead of a deeper Manager assignment.

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

    if requested_permission = 'admin' or requested_override then
        source_assignment_id := app_security.authorization_source(
            target_ou.id,
            array['admin']
        );
    else
        source_assignment_id := app_security.authorization_source(
            target_ou.id,
            array['admin', 'manager']
        );
    end if;

    if source_assignment_id is null then
        if requested_permission = 'admin' or requested_override then
            raise exception using errcode = '42501', message = 'ADMIN_GRANT_NOT_ALLOWED';
        end if;
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

revoke all on function public.create_ou_invite_link(jsonb) from public;
grant execute on function public.create_ou_invite_link(jsonb) to authenticated;
