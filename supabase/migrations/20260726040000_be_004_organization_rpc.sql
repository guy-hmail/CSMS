-- BE-004: Organization CRUD RPCs.

create or replace function app_security.require_current_user_id()
returns uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
    app_user_id uuid := app_security.current_user_id();
begin
    if app_security.jwt_subject() is null then
        raise exception 'AUTH_REQUIRED';
    end if;
    if app_user_id is null then
        raise exception 'USER_NOT_FOUND';
    end if;
    if app_security.current_church_id() is null then
        raise exception 'TENANT_CONTEXT_REQUIRED';
    end if;
    return app_user_id;
end;
$$;

create or replace function app_security.authorization_source(
    target_ou_id uuid,
    required_permissions text[]
)
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
    select assignment.id
    from public.organization_units as target
    join public.organization_units as assigned
      on assigned.church_id = target.church_id
     and assigned.structure_root_id = target.structure_root_id
     and (
         target.path = assigned.path
         or target.path like assigned.path || '/%'
     )
    join public.ou_members as assignment
      on assignment.church_id = assigned.church_id
     and assignment.ou_id = assigned.id
    join public.church_members as membership
      on membership.church_id = assignment.church_id
     and membership.id = assignment.church_member_id
    join public.users as app_user
      on app_user.id = membership.user_id
    where target.id = target_ou_id
      and target.church_id = app_security.current_church_id()
      and target.is_active
      and target.deleted_at is null
      and assigned.is_active
      and assigned.deleted_at is null
      and assignment.permission = any(required_permissions)
      and assignment.is_active
      and assignment.deleted_at is null
      and membership.status = 'active'
      and app_user.auth_user_id = app_security.jwt_subject()
      and app_user.is_active
      and app_user.deleted_at is null
    order by assigned.level desc, assignment.assigned_at desc, assignment.id
    limit 1;
$$;

create or replace function app_security.ou_tree_node(p_ou_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
    select jsonb_build_object(
        'id', organization.id,
        'parentId', organization.parent_id,
        'code', organization.code,
        'name', organization.name,
        'description', organization.description,
        'ouTypeId', organization.ou_type_id,
        'ouTypeName', ou_type.name,
        'level', organization.level,
        'path', organization.path,
        'sortOrder', organization.sort_order,
        'allowDataEntry', organization.allow_data_entry,
        'children', coalesce(
            (
                select jsonb_agg(
                    app_security.ou_tree_node(child.id)
                    order by child.sort_order, child.name, child.id
                )
                from public.organization_units as child
                where child.parent_id = organization.id
                  and child.church_id = organization.church_id
                  and child.is_active
                  and child.deleted_at is null
                  and app_security.can_view_ou(child.id)
            ),
            '[]'::jsonb
        )
    )
    from public.organization_units as organization
    join public.organization_unit_types as ou_type
      on ou_type.church_id = organization.church_id
     and ou_type.id = organization.ou_type_id
    where organization.id = p_ou_id
      and organization.church_id = app_security.current_church_id()
      and organization.is_active
      and organization.deleted_at is null
      and app_security.can_view_ou(organization.id);
$$;

create or replace function public.get_accessible_ou_tree()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
    ignored_user_id uuid := app_security.require_current_user_id();
    items jsonb;
begin
    select coalesce(
        jsonb_agg(
            app_security.ou_tree_node(organization.id)
            order by organization.sort_order, organization.name, organization.id
        ),
        '[]'::jsonb
    )
    into items
    from public.organization_units as organization
    where organization.church_id = app_security.current_church_id()
      and organization.is_active
      and organization.deleted_at is null
      and app_security.can_view_ou(organization.id)
      and (
          organization.parent_id is null
          or not app_security.can_view_ou(organization.parent_id)
      );

    return jsonb_build_object(
        'success', true,
        'data', jsonb_build_object('items', items)
    );
end;
$$;

create or replace function public.create_organization_unit(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    actor_user_id uuid := app_security.require_current_user_id();
    actor_membership_id uuid := app_security.current_church_member_id();
    parent_ou public.organization_units%rowtype;
    ou_type public.organization_unit_types%rowtype;
    source_assignment_id uuid;
    new_ou_id uuid := gen_random_uuid();
    allow_entry boolean;
    input_code text := upper(trim(p_payload ->> 'code'));
    input_name text := trim(p_payload ->> 'name');
begin
    if nullif(input_code, '') is null or length(input_code) > 50
       or nullif(input_name, '') is null or length(input_name) > 255 then
        raise exception 'VALIDATION_ERROR';
    end if;

    select *
    into parent_ou
    from public.organization_units
    where id = (p_payload ->> 'parentOuId')::uuid
      and church_id = app_security.current_church_id()
      and is_active
      and deleted_at is null
    for update;
    if parent_ou.id is null then raise exception 'PARENT_OU_NOT_FOUND'; end if;

    source_assignment_id := app_security.authorization_source(
        parent_ou.id,
        array['admin', 'manager']
    );
    if source_assignment_id is null then raise exception 'PERMISSION_DENIED'; end if;

    select *
    into ou_type
    from public.organization_unit_types
    where id = (p_payload ->> 'ouTypeId')::uuid
      and church_id = parent_ou.church_id
      and is_active
      and deleted_at is null;
    if ou_type.id is null then raise exception 'OU_TYPE_NOT_FOUND'; end if;

    allow_entry := case
        when p_payload ? 'allowDataEntry'
            then (p_payload ->> 'allowDataEntry')::boolean
        else ou_type.default_allow_data_entry
    end;

    insert into public.organization_units (
        id, church_id, structure_root_id, parent_id, ou_type_id,
        code, name, description, path, level, sort_order,
        allow_data_entry, created_by
    )
    values (
        new_ou_id, parent_ou.church_id, parent_ou.structure_root_id,
        parent_ou.id, ou_type.id, input_code, input_name,
        nullif(trim(p_payload ->> 'description'), ''),
        parent_ou.path || '/' || new_ou_id::text,
        parent_ou.level + 1,
        coalesce((p_payload ->> 'sortOrder')::integer, 0),
        allow_entry, actor_user_id
    );

    insert into public.audit_logs (
        church_id, user_id, actor_church_member_id, ou_id,
        source_ou_member_id, entity_type, entity_id, action, after_data
    )
    values (
        parent_ou.church_id, actor_user_id, actor_membership_id, new_ou_id,
        source_assignment_id, 'organization_units', new_ou_id, 'create',
        jsonb_build_object(
            'parentId', parent_ou.id, 'ouTypeId', ou_type.id,
            'code', input_code, 'name', input_name,
            'allowDataEntry', allow_entry
        )
    );

    return jsonb_build_object(
        'success', true,
        'data', jsonb_build_object('ouId', new_ou_id)
    );
exception
    when unique_violation then raise exception 'DUPLICATE_OU_CODE';
end;
$$;

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
    source_assignment_id uuid;
    before_snapshot jsonb;
    new_allow_entry boolean;
    new_code text := upper(trim(p_payload ->> 'code'));
    new_name text := trim(p_payload ->> 'name');
begin
    select *
    into target
    from public.organization_units
    where id = (p_payload ->> 'ouId')::uuid
      and church_id = app_security.current_church_id()
      and is_active
      and deleted_at is null
    for update;
    if target.id is null then raise exception 'OU_NOT_FOUND'; end if;

    source_assignment_id := app_security.authorization_source(
        target.id,
        array['admin', 'manager']
    );
    if source_assignment_id is null then raise exception 'PERMISSION_DENIED'; end if;
    if nullif(new_code, '') is null or length(new_code) > 50
       or nullif(new_name, '') is null or length(new_name) > 255 then
        raise exception 'VALIDATION_ERROR';
    end if;

    select *
    into target_type
    from public.organization_unit_types
    where id = (p_payload ->> 'ouTypeId')::uuid
      and church_id = target.church_id
      and deleted_at is null
      and (is_active or id = target.ou_type_id);
    if target_type.id is null then raise exception 'OU_TYPE_NOT_FOUND'; end if;

    new_allow_entry := coalesce(
        (p_payload ->> 'allowDataEntry')::boolean,
        target.allow_data_entry
    );
    if new_allow_entry and not target.allow_data_entry
       and exists (
           select 1
           from public.organization_units as child
           where child.church_id = target.church_id
             and child.parent_id = target.id
             and child.is_active
             and child.deleted_at is null
       )
       and coalesce((p_payload ->> 'confirmAdditiveParentEntry')::boolean, false) is false then
        raise exception 'ADDITIVE_PARENT_ENTRY_CONFIRMATION_REQUIRED';
    end if;

    before_snapshot := jsonb_build_object(
        'ouTypeId', target.ou_type_id, 'code', target.code,
        'name', target.name, 'description', target.description,
        'allowDataEntry', target.allow_data_entry, 'sortOrder', target.sort_order
    );

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
        before_data, after_data
    )
    values (
        target.church_id, actor_user_id, actor_membership_id, target.id,
        source_assignment_id, 'organization_units', target.id, 'update',
        before_snapshot,
        jsonb_build_object(
            'ouTypeId', target_type.id, 'code', new_code,
            'name', new_name,
            'description', nullif(trim(p_payload ->> 'description'), ''),
            'allowDataEntry', new_allow_entry,
            'sortOrder', coalesce((p_payload ->> 'sortOrder')::integer, target.sort_order)
        )
    );

    return jsonb_build_object(
        'success', true,
        'data', jsonb_build_object('ouId', target.id)
    );
exception
    when unique_violation then raise exception 'DUPLICATE_OU_CODE';
end;
$$;

create or replace function public.soft_delete_organization_unit(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    actor_user_id uuid := app_security.require_current_user_id();
    actor_membership_id uuid := app_security.current_church_member_id();
    target public.organization_units%rowtype;
    source_assignment_id uuid;
    reason text := trim(p_payload ->> 'reason');
begin
    if nullif(reason, '') is null then raise exception 'REASON_REQUIRED'; end if;
    select *
    into target
    from public.organization_units
    where id = (p_payload ->> 'ouId')::uuid
      and church_id = app_security.current_church_id()
      and is_active
      and deleted_at is null
    for update;
    if target.id is null then raise exception 'OU_NOT_FOUND'; end if;
    if target.parent_id is null then raise exception 'ROOT_OU_DELETE_FORBIDDEN'; end if;

    source_assignment_id := app_security.authorization_source(
        target.id,
        array['admin', 'manager']
    );
    if source_assignment_id is null then raise exception 'PERMISSION_DENIED'; end if;
    if exists (
        select 1 from public.organization_units
        where church_id = target.church_id
          and parent_id = target.id and is_active and deleted_at is null
    ) then raise exception 'OU_HAS_ACTIVE_CHILDREN'; end if;
    if exists (
        select 1 from public.statistic_submissions
        where church_id = target.church_id and ou_id = target.id
    ) then raise exception 'OU_HAS_SUBMISSION_HISTORY'; end if;

    update public.organization_units
    set is_active = false, deleted_at = now(), deleted_by = actor_user_id
    where id = target.id;

    update public.ou_members
    set is_active = false, deleted_at = now(), deleted_by = actor_user_id
    where church_id = target.church_id
      and ou_id = target.id and is_active and deleted_at is null;

    insert into public.audit_logs (
        church_id, user_id, actor_church_member_id, ou_id,
        source_ou_member_id, entity_type, entity_id, action,
        before_data, after_data, metadata
    )
    values (
        target.church_id, actor_user_id, actor_membership_id, target.id,
        source_assignment_id, 'organization_units', target.id, 'soft_delete',
        jsonb_build_object('isActive', true),
        jsonb_build_object('isActive', false, 'deletedAt', now()),
        jsonb_build_object('reason', reason)
    );

    return jsonb_build_object('success', true, 'data', jsonb_build_object('ouId', target.id));
end;
$$;

revoke all on function app_security.require_current_user_id() from public;
revoke all on function app_security.authorization_source(uuid, text[]) from public;
revoke all on function app_security.ou_tree_node(uuid) from public;
grant execute on function app_security.require_current_user_id() to authenticated;
grant execute on function app_security.authorization_source(uuid, text[]) to authenticated;
grant execute on function app_security.ou_tree_node(uuid) to authenticated;

revoke all on function public.get_accessible_ou_tree() from public;
revoke all on function public.create_organization_unit(jsonb) from public;
revoke all on function public.update_organization_unit(jsonb) from public;
revoke all on function public.soft_delete_organization_unit(jsonb) from public;
grant execute on function public.get_accessible_ou_tree() to authenticated;
grant execute on function public.create_organization_unit(jsonb) to authenticated;
grant execute on function public.update_organization_unit(jsonb) to authenticated;
grant execute on function public.soft_delete_organization_unit(jsonb) to authenticated;
