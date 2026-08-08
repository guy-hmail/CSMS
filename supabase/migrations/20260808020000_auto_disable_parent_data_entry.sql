-- Keep data-entry OUs at the leaf edge of the organization tree.
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
    parent_data_entry_disabled boolean := false;
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

    if allow_entry and parent_ou.allow_data_entry then
        update public.organization_units
        set allow_data_entry = false,
            updated_at = now()
        where id = parent_ou.id;
        parent_data_entry_disabled := true;

        insert into public.audit_logs (
            church_id, user_id, actor_church_member_id, ou_id,
            source_ou_member_id, entity_type, entity_id, action,
            before_data, after_data, metadata
        )
        values (
            parent_ou.church_id, actor_user_id, actor_membership_id, parent_ou.id,
            source_assignment_id, 'organization_units', parent_ou.id, 'update',
            jsonb_build_object('allowDataEntry', true),
            jsonb_build_object('allowDataEntry', false),
            jsonb_build_object(
                'reason', 'child_data_entry_enabled',
                'childOuId', new_ou_id,
                'childOuName', input_name
            )
        );
    end if;

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
            'allowDataEntry', allow_entry,
            'parentDataEntryDisabled', parent_data_entry_disabled
        )
    );

    return jsonb_build_object(
        'success', true,
        'data', jsonb_build_object(
            'ouId', new_ou_id,
            'parentOuId', parent_ou.id,
            'parentOuName', parent_ou.name,
            'parentDataEntryDisabled', parent_data_entry_disabled
        )
    );
exception
    when unique_violation then raise exception 'DUPLICATE_OU_CODE';
end;
$$;

comment on function public.create_organization_unit(jsonb) is
'Creates a child OU and automatically disables direct data entry on its parent when the child accepts data.';
