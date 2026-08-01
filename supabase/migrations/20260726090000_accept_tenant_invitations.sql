-- Accept pending tenant invitations after LINE has verified the user's email.
-- This function is callable only by the service role from the line-auth Edge Function.

create or replace function public.accept_tenant_invitations_for_user(
    p_user_id uuid,
    p_verified_email text
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
    invitation record;
    membership_id uuid;
    assignment_id uuid;
    accepted_count integer := 0;
    normalized_email text := lower(btrim(coalesce(p_verified_email, '')));
begin
    if current_user not in ('postgres', 'service_role') then
        raise exception using errcode = '42501', message = 'SERVICE_ROLE_REQUIRED';
    end if;

    if normalized_email = '' then
        return 0;
    end if;

    if not exists (
        select 1
        from public.users as app_user
        where app_user.id = p_user_id
          and app_user.is_active = true
          and app_user.deleted_at is null
    ) then
        raise exception using errcode = 'P0002', message = 'USER_NOT_FOUND';
    end if;

    for invitation in
        select pending.*
        from public.tenant_invitations as pending
        join public.churches as church
          on church.id = pending.church_id
         and church.status in ('trial', 'active')
         and church.is_active = true
         and church.deleted_at is null
        where lower(pending.email) = normalized_email
          and pending.status = 'pending'
          and pending.expires_at > now()
        order by pending.created_at
        for update of pending
    loop
        insert into public.church_members (
            church_id, user_id, status, joined_at, created_by
        )
        values (
            invitation.church_id,
            p_user_id,
            'active',
            now(),
            invitation.invited_by
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
            invitation.church_id,
            invitation.target_ou_id,
            membership_id,
            invitation.permission,
            invitation.can_override,
            true,
            invitation.invited_by
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
            invitation.church_id,
            p_user_id,
            membership_id,
            invitation.target_ou_id,
            assignment_id,
            'tenant_invitations',
            invitation.id,
            'accept_tenant_invitation',
            jsonb_build_object('permission', invitation.permission)
        );

        accepted_count := accepted_count + 1;
    end loop;

    return accepted_count;
end;
$$;

revoke all on function public.accept_tenant_invitations_for_user(uuid, text) from public;
grant execute on function public.accept_tenant_invitations_for_user(uuid, text) to service_role;
