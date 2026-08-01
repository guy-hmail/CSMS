-- BE-003: Authenticated identity read APIs.
-- LINE token verification and tenant claim mutation live in Edge Functions.

create or replace function public.list_my_tenants()
returns table (
    tenant_id uuid,
    slug varchar(100),
    name varchar(255),
    status varchar(30),
    membership_status varchar(20),
    is_current boolean,
    is_last_active boolean
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
    authenticated_user_id uuid := app_security.jwt_subject();
    app_user_id uuid;
    active_tenant_id uuid;
begin
    if authenticated_user_id is null then
        raise exception 'AUTH_REQUIRED';
    end if;

    select app_user.id, app_user.last_active_church_id
    into app_user_id, active_tenant_id
    from public.users as app_user
    where app_user.auth_user_id = authenticated_user_id
      and app_user.is_active = true
      and app_user.deleted_at is null;

    if app_user_id is null then
        raise exception 'USER_NOT_FOUND';
    end if;

    return query
    select
        church.id,
        church.slug,
        church.name,
        church.status,
        membership.status,
        church.id = app_security.current_church_id(),
        church.id = active_tenant_id
    from public.church_members as membership
    join public.churches as church
      on church.id = membership.church_id
    where membership.user_id = app_user_id
      and membership.status = 'active'
      and church.status in ('trial', 'active')
      and church.is_active = true
      and church.deleted_at is null
    order by church.name, church.id;
end;
$$;

create or replace function public.get_my_profile()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
    authenticated_user_id uuid := app_security.jwt_subject();
    app_user public.users%rowtype;
    selected_church public.churches%rowtype;
    permission_items jsonb;
begin
    if authenticated_user_id is null then
        raise exception 'AUTH_REQUIRED';
    end if;

    select *
    into app_user
    from public.users
    where auth_user_id = authenticated_user_id
      and is_active = true
      and deleted_at is null;

    if app_user.id is null then
        raise exception 'USER_NOT_FOUND';
    end if;

    select church.*
    into selected_church
    from public.churches as church
    where church.id = app_security.current_church_id();

    select coalesce(
        jsonb_agg(
            jsonb_build_object(
                'ouId', assignment.ou_id,
                'ouName', organization.name,
                'permission', assignment.permission,
                'canOverride', assignment.can_override
            )
            order by organization.path, assignment.permission
        ),
        '[]'::jsonb
    )
    into permission_items
    from public.ou_members as assignment
    join public.organization_units as organization
      on organization.church_id = assignment.church_id
     and organization.id = assignment.ou_id
    join public.church_members as membership
      on membership.church_id = assignment.church_id
     and membership.id = assignment.church_member_id
    where membership.user_id = app_user.id
      and membership.status = 'active'
      and assignment.church_id = selected_church.id
      and assignment.is_active = true
      and assignment.deleted_at is null
      and organization.is_active = true
      and organization.deleted_at is null;

    return jsonb_build_object(
        'user',
        jsonb_build_object(
            'id', app_user.id,
            'displayName', app_user.display_name,
            'pictureUrl', app_user.picture_url,
            'globalRole', app_user.global_role
        ),
        'currentTenant',
        case
            when selected_church.id is null then null
            else jsonb_build_object(
                'id', selected_church.id,
                'slug', selected_church.slug,
                'name', selected_church.name,
                'status', selected_church.status
            )
        end,
        'permissions',
        permission_items
    );
end;
$$;

revoke all on function public.list_my_tenants() from public;
revoke all on function public.get_my_profile() from public;
grant execute on function public.list_my_tenants() to authenticated;
grant execute on function public.get_my_profile() to authenticated;

create or replace function public.complete_tenant_switch(
    p_auth_user_id uuid,
    p_tenant_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
    app_user_id uuid;
    previous_tenant_id uuid;
    membership_id uuid;
begin
    select app_user.id, app_user.last_active_church_id
    into app_user_id, previous_tenant_id
    from public.users as app_user
    where app_user.auth_user_id = p_auth_user_id
      and app_user.is_active = true
      and app_user.deleted_at is null
    for update;

    if app_user_id is null then
        raise exception 'USER_NOT_FOUND';
    end if;

    select membership.id
    into membership_id
    from public.church_members as membership
    join public.churches as church
      on church.id = membership.church_id
    where membership.user_id = app_user_id
      and membership.church_id = p_tenant_id
      and membership.status = 'active'
      and church.status in ('trial', 'active')
      and church.is_active = true
      and church.deleted_at is null
    for update of membership;

    if membership_id is null then
        raise exception 'TENANT_ACCESS_DENIED';
    end if;

    update public.users
    set last_active_church_id = p_tenant_id
    where id = app_user_id;

    insert into public.audit_logs (
        church_id,
        user_id,
        actor_church_member_id,
        entity_type,
        entity_id,
        action,
        metadata
    )
    values (
        p_tenant_id,
        app_user_id,
        membership_id,
        'users',
        app_user_id,
        'switch_active_tenant',
        jsonb_build_object('previous_tenant_id', previous_tenant_id)
    );

    return membership_id;
end;
$$;

revoke all on function public.complete_tenant_switch(uuid, uuid) from public;
grant execute on function public.complete_tenant_switch(uuid, uuid) to service_role;
