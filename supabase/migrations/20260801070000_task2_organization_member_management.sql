-- Task 2: audited OU member assignment mutations and safe OU moves.

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
    source_assignment public.ou_members%rowtype;
    items jsonb;
begin
    source_assignment_id := app_security.authorization_source(p_ou_id, array['admin']);
    if source_assignment_id is null then
        source_assignment_id := app_security.authorization_source(p_ou_id, array['manager']);
    end if;
    if source_assignment_id is null then
        raise exception using errcode = '42501', message = 'PERMISSION_DENIED';
    end if;

    select * into source_assignment
    from public.ou_members
    where id = source_assignment_id;

    select coalesce(
        jsonb_agg(
            jsonb_build_object(
                'assignmentId', assignment.id,
                'ouId', assignment.ou_id,
                'churchMemberId', assignment.church_member_id,
                'accountId', app_user.id,
                'displayName', app_user.display_name,
                'lineUserId', app_user.line_user_id,
                'email', app_user.email,
                'role', assignment.permission,
                'canOverride', assignment.can_override,
                'assignedAt', assignment.assigned_at,
                'canEdit', source_assignment.permission = 'admin'
                    or (
                        assignment.id <> source_assignment.id
                        and assignment.permission <> 'admin'
                        and not assignment.can_override
                    ),
                'canRemove', source_assignment.permission = 'admin'
                    or (
                        assignment.id <> source_assignment.id
                        and assignment.permission <> 'admin'
                        and not assignment.can_override
                    )
            )
            order by app_user.display_name, assignment.assigned_at, assignment.id
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
        'data', jsonb_build_object(
            'items', items,
            'assignableRoles', case
                when source_assignment.permission = 'admin'
                    then jsonb_build_array('admin', 'manager', 'data_entry', 'approver', 'viewer')
                else jsonb_build_array('manager', 'data_entry', 'approver', 'viewer')
            end,
            'canGrantOverride', source_assignment.permission = 'admin'
        )
    );
end;
$$;

create or replace function public.update_ou_member_assignment(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    actor_user_id uuid := app_security.require_current_user_id();
    actor_membership_id uuid := app_security.current_church_member_id();
    target_assignment public.ou_members%rowtype;
    target_ou public.organization_units%rowtype;
    source_assignment_id uuid;
    source_assignment public.ou_members%rowtype;
    requested_permission text := lower(btrim(coalesce(p_payload ->> 'permission', '')));
    requested_override boolean := coalesce((p_payload ->> 'canOverride')::boolean, false);
    before_snapshot jsonb;
begin
    if requested_permission not in ('admin', 'manager', 'data_entry', 'approver', 'viewer') then
        raise exception using errcode = '22023', message = 'ASSIGNMENT_PERMISSION_INVALID';
    end if;
    if requested_override and requested_permission <> 'approver' then
        raise exception using errcode = '22023', message = 'OVERRIDE_REQUIRES_APPROVER';
    end if;

    select assignment.*
    into target_assignment
    from public.ou_members as assignment
    join public.church_members as membership
      on membership.church_id = assignment.church_id
     and membership.id = assignment.church_member_id
     and membership.status = 'active'
    where assignment.id = (p_payload ->> 'assignmentId')::uuid
      and assignment.church_id = app_security.current_church_id()
      and assignment.is_active
      and assignment.deleted_at is null
    for update of assignment;
    if target_assignment.id is null then
        raise exception using errcode = 'P0002', message = 'OU_MEMBER_ASSIGNMENT_NOT_FOUND';
    end if;

    select * into target_ou
    from public.organization_units
    where id = target_assignment.ou_id
      and church_id = target_assignment.church_id
      and is_active
      and deleted_at is null;
    if target_ou.id is null then
        raise exception using errcode = 'P0002', message = 'OU_NOT_FOUND';
    end if;

    source_assignment_id := app_security.authorization_source(target_ou.id, array['admin']);
    if source_assignment_id is null then
        source_assignment_id := app_security.authorization_source(target_ou.id, array['manager']);
    end if;
    if source_assignment_id is null then
        raise exception using errcode = '42501', message = 'PERMISSION_DENIED';
    end if;

    select * into source_assignment
    from public.ou_members
    where id = source_assignment_id;

    if source_assignment.permission = 'manager' and (
        requested_permission = 'admin'
        or requested_override
        or target_assignment.id = source_assignment.id
        or target_assignment.permission = 'admin'
        or target_assignment.can_override
    ) then
        raise exception using errcode = '42501', message = 'MANAGER_ASSIGNMENT_CHANGE_NOT_ALLOWED';
    end if;

    if target_ou.parent_id is null
       and target_assignment.permission = 'admin'
       and requested_permission <> 'admin'
       and not exists (
           select 1
           from public.ou_members as other_assignment
           where other_assignment.church_id = target_assignment.church_id
             and other_assignment.ou_id = target_assignment.ou_id
             and other_assignment.permission = 'admin'
             and other_assignment.is_active
             and other_assignment.deleted_at is null
             and other_assignment.id <> target_assignment.id
       ) then
        raise exception using errcode = '23514', message = 'LAST_ROOT_ADMIN_REQUIRED';
    end if;

    if exists (
        select 1
        from public.ou_members as conflicting_assignment
        where conflicting_assignment.church_id = target_assignment.church_id
          and conflicting_assignment.ou_id = target_assignment.ou_id
          and conflicting_assignment.church_member_id = target_assignment.church_member_id
          and conflicting_assignment.permission = requested_permission
          and conflicting_assignment.id <> target_assignment.id
    ) then
        raise exception using errcode = '23505', message = 'DUPLICATE_OU_ASSIGNMENT';
    end if;

    if target_assignment.permission = requested_permission
       and target_assignment.can_override = requested_override then
        return jsonb_build_object(
            'success', true,
            'data', jsonb_build_object('assignmentId', target_assignment.id, 'changed', false)
        );
    end if;

    before_snapshot := jsonb_build_object(
        'permission', target_assignment.permission,
        'canOverride', target_assignment.can_override,
        'isActive', target_assignment.is_active
    );

    update public.ou_members
    set permission = requested_permission,
        can_override = requested_override,
        assigned_by = actor_user_id,
        assigned_at = now()
    where id = target_assignment.id;

    insert into public.audit_logs (
        church_id, user_id, actor_church_member_id, ou_id,
        source_ou_member_id, entity_type, entity_id, action,
        before_data, after_data
    )
    values (
        target_assignment.church_id, actor_user_id, actor_membership_id,
        target_assignment.ou_id, source_assignment_id, 'ou_members',
        target_assignment.id, 'update_assignment', before_snapshot,
        jsonb_build_object(
            'permission', requested_permission,
            'canOverride', requested_override,
            'isActive', true
        )
    );

    return jsonb_build_object(
        'success', true,
        'data', jsonb_build_object('assignmentId', target_assignment.id, 'changed', true)
    );
exception
    when unique_violation then
        raise exception using errcode = '23505', message = 'DUPLICATE_OU_ASSIGNMENT';
end;
$$;

create or replace function public.remove_ou_member(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    actor_user_id uuid := app_security.require_current_user_id();
    actor_membership_id uuid := app_security.current_church_member_id();
    target_assignment public.ou_members%rowtype;
    target_ou public.organization_units%rowtype;
    source_assignment_id uuid;
    source_assignment public.ou_members%rowtype;
    removal_reason text := btrim(coalesce(p_payload ->> 'reason', ''));
begin
    if removal_reason = '' or length(removal_reason) > 500 then
        raise exception using errcode = '22023', message = 'REMOVAL_REASON_REQUIRED';
    end if;

    select assignment.*
    into target_assignment
    from public.ou_members as assignment
    join public.church_members as membership
      on membership.church_id = assignment.church_id
     and membership.id = assignment.church_member_id
     and membership.status = 'active'
    where assignment.id = (p_payload ->> 'assignmentId')::uuid
      and assignment.church_id = app_security.current_church_id()
      and assignment.is_active
      and assignment.deleted_at is null
    for update of assignment;
    if target_assignment.id is null then
        raise exception using errcode = 'P0002', message = 'OU_MEMBER_ASSIGNMENT_NOT_FOUND';
    end if;

    select * into target_ou
    from public.organization_units
    where id = target_assignment.ou_id
      and church_id = target_assignment.church_id
      and is_active
      and deleted_at is null;
    if target_ou.id is null then
        raise exception using errcode = 'P0002', message = 'OU_NOT_FOUND';
    end if;

    source_assignment_id := app_security.authorization_source(target_ou.id, array['admin']);
    if source_assignment_id is null then
        source_assignment_id := app_security.authorization_source(target_ou.id, array['manager']);
    end if;
    if source_assignment_id is null then
        raise exception using errcode = '42501', message = 'PERMISSION_DENIED';
    end if;

    select * into source_assignment
    from public.ou_members
    where id = source_assignment_id;

    if source_assignment.permission = 'manager' and (
        target_assignment.id = source_assignment.id
        or target_assignment.permission = 'admin'
        or target_assignment.can_override
    ) then
        raise exception using errcode = '42501', message = 'MANAGER_ASSIGNMENT_REMOVE_NOT_ALLOWED';
    end if;

    if target_ou.parent_id is null
       and target_assignment.permission = 'admin'
       and not exists (
           select 1
           from public.ou_members as other_assignment
           where other_assignment.church_id = target_assignment.church_id
             and other_assignment.ou_id = target_assignment.ou_id
             and other_assignment.permission = 'admin'
             and other_assignment.is_active
             and other_assignment.deleted_at is null
             and other_assignment.id <> target_assignment.id
       ) then
        raise exception using errcode = '23514', message = 'LAST_ROOT_ADMIN_REQUIRED';
    end if;

    update public.ou_members
    set is_active = false,
        deleted_at = now(),
        deleted_by = actor_user_id
    where id = target_assignment.id;

    insert into public.audit_logs (
        church_id, user_id, actor_church_member_id, ou_id,
        source_ou_member_id, entity_type, entity_id, action,
        before_data, after_data, metadata
    )
    values (
        target_assignment.church_id, actor_user_id, actor_membership_id,
        target_assignment.ou_id, source_assignment_id, 'ou_members',
        target_assignment.id, 'remove_assignment',
        jsonb_build_object(
            'permission', target_assignment.permission,
            'canOverride', target_assignment.can_override,
            'isActive', true
        ),
        jsonb_build_object('isActive', false, 'deletedAt', now()),
        jsonb_build_object('reason', removal_reason)
    );

    return jsonb_build_object(
        'success', true,
        'data', jsonb_build_object('assignmentId', target_assignment.id)
    );
end;
$$;

create or replace function public.search_assignable_members(
    p_ou_id uuid,
    p_query text default ''
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
    ignored_user_id uuid := app_security.require_current_user_id();
    source_assignment_id uuid;
    search_text text := lower(btrim(coalesce(p_query, '')));
    items jsonb;
begin
    source_assignment_id := app_security.authorization_source(p_ou_id, array['admin']);
    if source_assignment_id is null then
        source_assignment_id := app_security.authorization_source(p_ou_id, array['manager']);
    end if;
    if source_assignment_id is null then
        raise exception using errcode = '42501', message = 'PERMISSION_DENIED';
    end if;

    select coalesce(jsonb_agg(result.item order by result.display_name, result.church_member_id), '[]'::jsonb)
    into items
    from (
        select
            membership.id as church_member_id,
            app_user.display_name,
            jsonb_build_object(
                'churchMemberId', membership.id,
                'accountId', app_user.id,
                'displayName', app_user.display_name,
                'lineUserId', app_user.line_user_id,
                'email', app_user.email,
                'existingRoles', coalesce(
                    (
                        select jsonb_agg(assignment.permission order by assignment.permission)
                        from public.ou_members as assignment
                        where assignment.church_id = membership.church_id
                          and assignment.ou_id = p_ou_id
                          and assignment.church_member_id = membership.id
                          and assignment.is_active
                          and assignment.deleted_at is null
                    ),
                    '[]'::jsonb
                )
            ) as item
        from public.church_members as membership
        join public.users as app_user
          on app_user.id = membership.user_id
         and app_user.is_active
         and app_user.deleted_at is null
        where membership.church_id = app_security.current_church_id()
          and membership.status = 'active'
          and (
              search_text = ''
              or lower(app_user.display_name) like '%' || search_text || '%'
              or lower(app_user.line_user_id) like '%' || search_text || '%'
              or lower(coalesce(app_user.email, '')) like '%' || search_text || '%'
          )
        limit 50
    ) as result;

    return jsonb_build_object('success', true, 'data', jsonb_build_object('items', items));
end;
$$;

create or replace function public.assign_ou_member(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    actor_user_id uuid := app_security.require_current_user_id();
    actor_membership_id uuid := app_security.current_church_member_id();
    target_ou public.organization_units%rowtype;
    target_membership public.church_members%rowtype;
    source_assignment_id uuid;
    source_assignment public.ou_members%rowtype;
    requested_permission text := lower(btrim(coalesce(p_payload ->> 'permission', '')));
    requested_override boolean := coalesce((p_payload ->> 'canOverride')::boolean, false);
    assignment_id uuid;
    was_active boolean := false;
begin
    if requested_permission not in ('admin', 'manager', 'data_entry', 'approver', 'viewer') then
        raise exception using errcode = '22023', message = 'ASSIGNMENT_PERMISSION_INVALID';
    end if;
    if requested_override and requested_permission <> 'approver' then
        raise exception using errcode = '22023', message = 'OVERRIDE_REQUIRES_APPROVER';
    end if;

    select * into target_ou
    from public.organization_units
    where id = (p_payload ->> 'ouId')::uuid
      and church_id = app_security.current_church_id()
      and is_active and deleted_at is null;
    if target_ou.id is null then raise exception using errcode = 'P0002', message = 'OU_NOT_FOUND'; end if;

    source_assignment_id := app_security.authorization_source(target_ou.id, array['admin']);
    if source_assignment_id is null then
        source_assignment_id := app_security.authorization_source(target_ou.id, array['manager']);
    end if;
    if source_assignment_id is null then raise exception using errcode = '42501', message = 'PERMISSION_DENIED'; end if;
    select * into source_assignment from public.ou_members where id = source_assignment_id;

    if source_assignment.permission = 'manager'
       and (requested_permission = 'admin' or requested_override) then
        raise exception using errcode = '42501', message = 'MANAGER_GRANT_NOT_ALLOWED';
    end if;

    select * into target_membership
    from public.church_members
    where id = (p_payload ->> 'churchMemberId')::uuid
      and church_id = target_ou.church_id
      and status = 'active';
    if target_membership.id is null then
        raise exception using errcode = 'P0002', message = 'CHURCH_MEMBER_NOT_FOUND';
    end if;

    select assignment.id, assignment.is_active and assignment.deleted_at is null
    into assignment_id, was_active
    from public.ou_members as assignment
    where assignment.church_id = target_ou.church_id
      and assignment.ou_id = target_ou.id
      and assignment.church_member_id = target_membership.id
      and assignment.permission = requested_permission
    for update;

    if was_active then
        raise exception using errcode = '23505', message = 'DUPLICATE_OU_ASSIGNMENT';
    end if;

    if assignment_id is null then
        insert into public.ou_members (
            church_id, ou_id, church_member_id, permission,
            can_override, assigned_by
        )
        values (
            target_ou.church_id, target_ou.id, target_membership.id,
            requested_permission, requested_override, actor_user_id
        )
        returning id into assignment_id;
    else
        update public.ou_members
        set is_active = true,
            can_override = requested_override,
            assigned_by = actor_user_id,
            assigned_at = now(),
            deleted_at = null,
            deleted_by = null
        where id = assignment_id;
    end if;

    insert into public.audit_logs (
        church_id, user_id, actor_church_member_id, ou_id,
        source_ou_member_id, entity_type, entity_id, action, after_data
    )
    values (
        target_ou.church_id, actor_user_id, actor_membership_id, target_ou.id,
        source_assignment_id, 'ou_members', assignment_id, 'assign_member',
        jsonb_build_object(
            'churchMemberId', target_membership.id,
            'permission', requested_permission,
            'canOverride', requested_override,
            'isActive', true
        )
    );

    return jsonb_build_object('success', true, 'data', jsonb_build_object('assignmentId', assignment_id));
end;
$$;

create or replace function public.list_ou_invitations(p_ou_id uuid)
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
    source_assignment_id := app_security.authorization_source(p_ou_id, array['admin']);
    if source_assignment_id is null then
        source_assignment_id := app_security.authorization_source(p_ou_id, array['manager']);
    end if;
    if source_assignment_id is null then
        raise exception using errcode = '42501', message = 'PERMISSION_DENIED';
    end if;

    select coalesce(
        jsonb_agg(
            jsonb_build_object(
                'invitationId', invitation.id,
                'displayName', invitation.display_name,
                'permission', invitation.permission,
                'canOverride', invitation.can_override,
                'status', case
                    when invitation.status = 'pending' and invitation.expires_at <= now() then 'expired'
                    else invitation.status
                end,
                'expiresAt', invitation.expires_at,
                'acceptedAt', invitation.accepted_at,
                'createdAt', invitation.created_at
            )
            order by invitation.created_at desc, invitation.id
        ),
        '[]'::jsonb
    )
    into items
    from public.tenant_invitations as invitation
    where invitation.church_id = app_security.current_church_id()
      and invitation.target_ou_id = p_ou_id;

    return jsonb_build_object('success', true, 'data', jsonb_build_object('items', items));
end;
$$;

create or replace function public.revoke_ou_invitation(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    actor_user_id uuid := app_security.require_current_user_id();
    actor_membership_id uuid := app_security.current_church_member_id();
    invitation public.tenant_invitations%rowtype;
    source_assignment_id uuid;
    source_assignment public.ou_members%rowtype;
    revocation_reason text := btrim(coalesce(p_payload ->> 'reason', ''));
begin
    if revocation_reason = '' or length(revocation_reason) > 500 then
        raise exception using errcode = '22023', message = 'REVOCATION_REASON_REQUIRED';
    end if;

    select * into invitation
    from public.tenant_invitations
    where id = (p_payload ->> 'invitationId')::uuid
      and church_id = app_security.current_church_id()
    for update;
    if invitation.id is null then raise exception using errcode = 'P0002', message = 'INVITATION_NOT_FOUND'; end if;
    if invitation.status <> 'pending' then raise exception using errcode = '22023', message = 'INVITATION_NOT_PENDING'; end if;

    source_assignment_id := app_security.authorization_source(invitation.target_ou_id, array['admin']);
    if source_assignment_id is null then
        source_assignment_id := app_security.authorization_source(invitation.target_ou_id, array['manager']);
    end if;
    if source_assignment_id is null then raise exception using errcode = '42501', message = 'PERMISSION_DENIED'; end if;
    select * into source_assignment from public.ou_members where id = source_assignment_id;
    if source_assignment.permission = 'manager'
       and (invitation.permission = 'admin' or invitation.can_override) then
        raise exception using errcode = '42501', message = 'MANAGER_INVITATION_CHANGE_NOT_ALLOWED';
    end if;

    update public.tenant_invitations
    set status = 'revoked', revoked_by = actor_user_id, revoked_at = now()
    where id = invitation.id;

    insert into public.audit_logs (
        church_id, user_id, actor_church_member_id, ou_id,
        source_ou_member_id, entity_type, entity_id, action,
        before_data, after_data, metadata
    )
    values (
        invitation.church_id, actor_user_id, actor_membership_id,
        invitation.target_ou_id, source_assignment_id, 'tenant_invitations',
        invitation.id, 'revoke_invitation',
        jsonb_build_object('status', invitation.status),
        jsonb_build_object('status', 'revoked', 'revokedAt', now()),
        jsonb_build_object('reason', revocation_reason)
    );

    return jsonb_build_object('success', true, 'data', jsonb_build_object('invitationId', invitation.id));
end;
$$;

create or replace function public.reissue_ou_invitation(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    actor_user_id uuid := app_security.require_current_user_id();
    actor_membership_id uuid := app_security.current_church_member_id();
    invitation public.tenant_invitations%rowtype;
    source_assignment_id uuid;
    source_assignment public.ou_members%rowtype;
    raw_token text := replace(gen_random_uuid()::text, '-', '') || replace(gen_random_uuid()::text, '-', '');
    expires_in_days integer := coalesce((p_payload ->> 'expiresInDays')::integer, 7);
    new_expires_at timestamptz;
begin
    if expires_in_days < 1 or expires_in_days > 30 then
        raise exception using errcode = '22023', message = 'INVITATION_EXPIRY_INVALID';
    end if;

    select * into invitation
    from public.tenant_invitations
    where id = (p_payload ->> 'invitationId')::uuid
      and church_id = app_security.current_church_id()
    for update;
    if invitation.id is null then raise exception using errcode = 'P0002', message = 'INVITATION_NOT_FOUND'; end if;
    if invitation.status = 'accepted' then raise exception using errcode = '22023', message = 'ACCEPTED_INVITATION_REISSUE_FORBIDDEN'; end if;

    source_assignment_id := app_security.authorization_source(invitation.target_ou_id, array['admin']);
    if source_assignment_id is null then
        source_assignment_id := app_security.authorization_source(invitation.target_ou_id, array['manager']);
    end if;
    if source_assignment_id is null then raise exception using errcode = '42501', message = 'PERMISSION_DENIED'; end if;
    select * into source_assignment from public.ou_members where id = source_assignment_id;
    if source_assignment.permission = 'manager'
       and (invitation.permission = 'admin' or invitation.can_override) then
        raise exception using errcode = '42501', message = 'MANAGER_INVITATION_CHANGE_NOT_ALLOWED';
    end if;

    new_expires_at := now() + make_interval(days => expires_in_days);
    update public.tenant_invitations
    set token_hash = encode(extensions.digest(raw_token, 'sha256'), 'hex'),
        status = 'pending',
        expires_at = new_expires_at,
        invited_by = actor_user_id,
        accepted_by = null,
        accepted_at = null,
        revoked_by = null,
        revoked_at = null
    where id = invitation.id;

    insert into public.audit_logs (
        church_id, user_id, actor_church_member_id, ou_id,
        source_ou_member_id, entity_type, entity_id, action,
        before_data, after_data
    )
    values (
        invitation.church_id, actor_user_id, actor_membership_id,
        invitation.target_ou_id, source_assignment_id, 'tenant_invitations',
        invitation.id, 'reissue_invitation',
        jsonb_build_object('status', invitation.status, 'expiresAt', invitation.expires_at),
        jsonb_build_object('status', 'pending', 'expiresAt', new_expires_at)
    );

    return jsonb_build_object(
        'success', true,
        'data', jsonb_build_object(
            'invitationId', invitation.id,
            'inviteToken', raw_token,
            'expiresAt', new_expires_at
        )
    );
end;
$$;

-- Extend the existing metadata update so an authorized move also recalculates
-- every descendant path and absolute level in the same transaction.
create or replace function public.update_organization_unit(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    actor_user_id uuid := app_security.require_current_user_id();
    actor_membership_id uuid := app_security.current_church_member_id();
    target public.organization_units%rowtype;
    target_type public.organization_unit_types%rowtype;
    new_parent public.organization_units%rowtype;
    source_assignment_id uuid;
    source_assignment public.ou_members%rowtype;
    new_parent_source_id uuid;
    before_snapshot jsonb;
    new_allow_entry boolean;
    new_code text := upper(trim(p_payload ->> 'code'));
    new_name text := trim(p_payload ->> 'name');
    old_path text;
    new_path text;
    level_delta integer := 0;
    requested_parent_id uuid;
begin
    select * into target
    from public.organization_units
    where id = (p_payload ->> 'ouId')::uuid
      and church_id = app_security.current_church_id()
      and is_active
      and deleted_at is null
    for update;
    if target.id is null then raise exception 'OU_NOT_FOUND'; end if;

    source_assignment_id := app_security.authorization_source(target.id, array['admin']);
    if source_assignment_id is null then
        source_assignment_id := app_security.authorization_source(target.id, array['manager']);
    end if;
    if source_assignment_id is null then raise exception 'PERMISSION_DENIED'; end if;
    select * into source_assignment from public.ou_members where id = source_assignment_id;

    if nullif(new_code, '') is null or length(new_code) > 50
       or nullif(new_name, '') is null or length(new_name) > 255 then
        raise exception 'VALIDATION_ERROR';
    end if;

    select * into target_type
    from public.organization_unit_types
    where id = (p_payload ->> 'ouTypeId')::uuid
      and church_id = target.church_id
      and deleted_at is null
      and (is_active or id = target.ou_type_id);
    if target_type.id is null then raise exception 'OU_TYPE_NOT_FOUND'; end if;

    new_allow_entry := coalesce((p_payload ->> 'allowDataEntry')::boolean, target.allow_data_entry);
    if new_allow_entry and not target.allow_data_entry
       and exists (
           select 1 from public.organization_units as child
           where child.church_id = target.church_id
             and child.parent_id = target.id
             and child.is_active and child.deleted_at is null
       )
       and coalesce((p_payload ->> 'confirmAdditiveParentEntry')::boolean, false) is false then
        raise exception 'ADDITIVE_PARENT_ENTRY_CONFIRMATION_REQUIRED';
    end if;

    old_path := target.path;
    new_path := target.path;

    if p_payload ? 'parentOuId' then
        if target.parent_id is null then
            if p_payload ->> 'parentOuId' is not null then
                raise exception 'ROOT_OU_MOVE_FORBIDDEN';
            end if;
        else
            if p_payload ->> 'parentOuId' is null then
                raise exception 'ROOT_OU_CREATE_FORBIDDEN';
            end if;
            requested_parent_id := (p_payload ->> 'parentOuId')::uuid;

            if requested_parent_id <> target.parent_id then
                select * into new_parent
                from public.organization_units
                where id = requested_parent_id
                  and church_id = target.church_id
                  and structure_root_id = target.structure_root_id
                  and is_active
                  and deleted_at is null
                for update;
                if new_parent.id is null then raise exception 'PARENT_OU_NOT_FOUND'; end if;
                if new_parent.path = target.path
                   or new_parent.path like target.path || '/%' then
                    raise exception 'OU_MOVE_CYCLE';
                end if;

                new_parent_source_id := app_security.authorization_source(new_parent.id, array['admin']);
                if new_parent_source_id is null then
                    new_parent_source_id := app_security.authorization_source(new_parent.id, array['manager']);
                end if;
                if new_parent_source_id is null then raise exception 'PERMISSION_DENIED'; end if;
                if source_assignment.permission = 'manager'
                   and source_assignment.ou_id = target.id then
                    raise exception 'MANAGER_SOURCE_OU_MOVE_FORBIDDEN';
                end if;

                new_path := new_parent.path || '/' || target.id::text;
                level_delta := (new_parent.level + 1) - target.level;
            end if;
        end if;
    end if;

    before_snapshot := jsonb_build_object(
        'parentId', target.parent_id, 'ouTypeId', target.ou_type_id,
        'code', target.code, 'name', target.name,
        'description', target.description,
        'allowDataEntry', target.allow_data_entry,
        'sortOrder', target.sort_order,
        'path', target.path, 'level', target.level
    );

    if new_path <> old_path then
        update public.organization_units as organization
        set path = new_path || substring(organization.path from length(old_path) + 1),
            level = organization.level + level_delta,
            parent_id = case when organization.id = target.id then new_parent.id else organization.parent_id end
        where organization.church_id = target.church_id
          and organization.structure_root_id = target.structure_root_id
          and (organization.path = old_path or organization.path like old_path || '/%');
    end if;

    update public.organization_units
    set ou_type_id = target_type.id,
        code = new_code,
        name = new_name,
        description = nullif(trim(p_payload ->> 'description'), ''),
        allow_data_entry = new_allow_entry,
        sort_order = coalesce((p_payload ->> 'sortOrder')::integer, target.sort_order)
    where id = target.id;

    insert into public.audit_logs (
        church_id, user_id, actor_church_member_id, ou_id,
        source_ou_member_id, entity_type, entity_id, action,
        before_data, after_data, metadata
    )
    values (
        target.church_id, actor_user_id, actor_membership_id, target.id,
        source_assignment_id, 'organization_units', target.id, 'update',
        before_snapshot,
        jsonb_build_object(
            'parentId', case when new_path <> old_path then new_parent.id else target.parent_id end,
            'ouTypeId', target_type.id, 'code', new_code, 'name', new_name,
            'description', nullif(trim(p_payload ->> 'description'), ''),
            'allowDataEntry', new_allow_entry,
            'sortOrder', coalesce((p_payload ->> 'sortOrder')::integer, target.sort_order),
            'path', new_path, 'level', target.level + level_delta
        ),
        case when new_path <> old_path
            then jsonb_build_object('newParentAuthorizationSourceId', new_parent_source_id)
            else '{}'::jsonb
        end
    );

    return jsonb_build_object('success', true, 'data', jsonb_build_object('ouId', target.id));
exception
    when unique_violation then raise exception 'DUPLICATE_OU_CODE';
end;
$$;

revoke all on function public.get_ou_members(uuid) from public;
revoke all on function public.update_ou_member_assignment(jsonb) from public;
revoke all on function public.remove_ou_member(jsonb) from public;
revoke all on function public.search_assignable_members(uuid, text) from public;
revoke all on function public.assign_ou_member(jsonb) from public;
revoke all on function public.list_ou_invitations(uuid) from public;
revoke all on function public.revoke_ou_invitation(jsonb) from public;
revoke all on function public.reissue_ou_invitation(jsonb) from public;
revoke all on function public.update_organization_unit(jsonb) from public;
grant execute on function public.get_ou_members(uuid) to authenticated;
grant execute on function public.update_ou_member_assignment(jsonb) to authenticated;
grant execute on function public.remove_ou_member(jsonb) to authenticated;
grant execute on function public.search_assignable_members(uuid, text) to authenticated;
grant execute on function public.assign_ou_member(jsonb) to authenticated;
grant execute on function public.list_ou_invitations(uuid) to authenticated;
grant execute on function public.revoke_ou_invitation(jsonb) to authenticated;
grant execute on function public.reissue_ou_invitation(jsonb) to authenticated;
grant execute on function public.update_organization_unit(jsonb) to authenticated;
