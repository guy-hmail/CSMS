-- FE-007 backend: audited tenant-wide settings mutations.
-- All functions derive the tenant from the authenticated session and require
-- an active direct admin assignment on the active Root OU Level 1.

create or replace function app_security.require_direct_root_admin()
returns uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
    ignored_user_id uuid := app_security.require_current_user_id();
    source_assignment_id uuid;
begin
    select assignment.id
    into source_assignment_id
    from public.organization_units as root_ou
    join public.ou_members as assignment
      on assignment.church_id = root_ou.church_id
     and assignment.ou_id = root_ou.id
    join public.church_members as membership
      on membership.church_id = assignment.church_id
     and membership.id = assignment.church_member_id
    join public.users as app_user
      on app_user.id = membership.user_id
    where root_ou.church_id = app_security.current_church_id()
      and root_ou.parent_id is null
      and root_ou.level = 1
      and root_ou.is_active
      and root_ou.deleted_at is null
      and assignment.permission = 'admin'
      and assignment.is_active
      and assignment.deleted_at is null
      and membership.status = 'active'
      and app_user.auth_user_id = app_security.jwt_subject()
      and app_user.is_active
      and app_user.deleted_at is null
    order by assignment.assigned_at desc, assignment.id
    limit 1;

    if source_assignment_id is null then
        raise exception 'DIRECT_ROOT_ADMIN_REQUIRED';
    end if;

    return source_assignment_id;
end;
$$;

create or replace function public.update_tenant_settings(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    actor_user_id uuid := app_security.require_current_user_id();
    actor_membership_id uuid := app_security.current_church_member_id();
    source_assignment_id uuid := app_security.require_direct_root_admin();
    target public.churches%rowtype;
    root_ou_id uuid;
    before_snapshot jsonb;
    input_name text;
    input_timezone text;
    input_approval_mode text;
    input_week_end smallint;
    input_primary_metric_id uuid;
begin
    select *
    into target
    from public.churches
    where id = app_security.current_church_id()
      and is_active
      and deleted_at is null
    for update;
    if target.id is null then raise exception 'TENANT_NOT_FOUND'; end if;

    select ou_id into root_ou_id
    from public.ou_members
    where id = source_assignment_id
      and church_id = target.id;

    input_name := trim(coalesce(p_payload ->> 'name', target.name));
    input_timezone := trim(coalesce(p_payload ->> 'timezone', target.timezone));
    input_approval_mode := coalesce(p_payload ->> 'approvalMode', target.approval_mode);
    input_week_end := coalesce(
        nullif(p_payload ->> 'reportingWeekEndsOn', '')::smallint,
        target.reporting_week_ends_on
    );
    input_primary_metric_id := case
        when p_payload ? 'primaryMetricId'
          and nullif(p_payload ->> 'primaryMetricId', '') is not null
            then (p_payload ->> 'primaryMetricId')::uuid
        when p_payload ? 'primaryMetricId' then null
        else target.primary_metric_id
    end;

    if nullif(input_name, '') is null or length(input_name) > 255
       or nullif(input_timezone, '') is null
       or not exists (
           select 1
           from pg_catalog.pg_timezone_names
           where name = input_timezone
       )
       or input_approval_mode not in ('auto_approve', 'approval_required')
       or input_week_end not between 0 and 6 then
        raise exception 'VALIDATION_ERROR';
    end if;

    if input_primary_metric_id is not null
       and not exists (
           select 1
           from public.statistic_metrics
           where id = input_primary_metric_id
             and church_id = target.id
             and data_type = 'number'
             and is_active
             and deleted_at is null
       ) then
        raise exception 'PRIMARY_METRIC_NOT_FOUND';
    end if;

    before_snapshot := jsonb_build_object(
        'name', target.name,
        'timezone', target.timezone,
        'approvalMode', target.approval_mode,
        'reportingWeekEndsOn', target.reporting_week_ends_on,
        'primaryMetricId', target.primary_metric_id
    );

    update public.churches
    set name = input_name,
        timezone = input_timezone,
        approval_mode = input_approval_mode,
        reporting_week_ends_on = input_week_end,
        primary_metric_id = input_primary_metric_id
    where id = target.id;

    insert into public.audit_logs (
        church_id, user_id, actor_church_member_id, ou_id,
        source_ou_member_id, entity_type, entity_id, action,
        before_data, after_data
    )
    values (
        target.id, actor_user_id, actor_membership_id, root_ou_id,
        source_assignment_id, 'churches', target.id, 'update_settings',
        before_snapshot,
        jsonb_build_object(
            'name', input_name,
            'timezone', input_timezone,
            'approvalMode', input_approval_mode,
            'reportingWeekEndsOn', input_week_end,
            'primaryMetricId', input_primary_metric_id
        )
    );

    return jsonb_build_object('success', true, 'data', jsonb_build_object('tenantId', target.id));
exception
    when invalid_text_representation or numeric_value_out_of_range then
        raise exception 'VALIDATION_ERROR';
end;
$$;

create or replace function public.create_organization_unit_type(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    actor_user_id uuid := app_security.require_current_user_id();
    actor_membership_id uuid := app_security.current_church_member_id();
    source_assignment_id uuid := app_security.require_direct_root_admin();
    tenant_id uuid := app_security.current_church_id();
    root_ou_id uuid;
    new_id uuid := gen_random_uuid();
    input_code text := upper(trim(p_payload ->> 'code'));
    input_name text := trim(p_payload ->> 'name');
    input_description text := nullif(trim(p_payload ->> 'description'), '');
    input_sort_order integer := coalesce((p_payload ->> 'sortOrder')::integer, 0);
    input_default_allow boolean := coalesce(
        (p_payload ->> 'defaultAllowDataEntry')::boolean,
        false
    );
begin
    if nullif(input_code, '') is null
       or input_code !~ '^[A-Z][A-Z0-9_]{0,49}$'
       or nullif(input_name, '') is null
       or length(input_name) > 150
       or input_sort_order < 0 then
        raise exception 'VALIDATION_ERROR';
    end if;

    select ou_id into root_ou_id
    from public.ou_members
    where id = source_assignment_id
      and church_id = tenant_id;

    insert into public.organization_unit_types (
        id, church_id, code, name, description, sort_order,
        default_allow_data_entry, created_by
    )
    values (
        new_id, tenant_id, input_code, input_name, input_description,
        input_sort_order, input_default_allow, actor_user_id
    );

    insert into public.audit_logs (
        church_id, user_id, actor_church_member_id, ou_id,
        source_ou_member_id, entity_type, entity_id, action, after_data
    )
    values (
        tenant_id, actor_user_id, actor_membership_id, root_ou_id,
        source_assignment_id, 'organization_unit_types', new_id, 'create',
        jsonb_build_object(
            'code', input_code,
            'name', input_name,
            'description', input_description,
            'sortOrder', input_sort_order,
            'defaultAllowDataEntry', input_default_allow,
            'isActive', true
        )
    );

    return jsonb_build_object('success', true, 'data', jsonb_build_object('ouTypeId', new_id));
exception
    when unique_violation then raise exception 'DUPLICATE_OU_TYPE_CODE';
    when invalid_text_representation or numeric_value_out_of_range then
        raise exception 'VALIDATION_ERROR';
end;
$$;

create or replace function public.update_organization_unit_type(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    actor_user_id uuid := app_security.require_current_user_id();
    actor_membership_id uuid := app_security.current_church_member_id();
    source_assignment_id uuid := app_security.require_direct_root_admin();
    target public.organization_unit_types%rowtype;
    root_ou_id uuid;
    before_snapshot jsonb;
    input_name text;
    input_description text;
    input_sort_order integer;
    input_default_allow boolean;
    input_is_active boolean;
begin
    select *
    into target
    from public.organization_unit_types
    where id = (p_payload ->> 'ouTypeId')::uuid
      and church_id = app_security.current_church_id()
      and deleted_at is null
    for update;
    if target.id is null then raise exception 'OU_TYPE_NOT_FOUND'; end if;

    select ou_id into root_ou_id
    from public.ou_members
    where id = source_assignment_id
      and church_id = target.church_id;

    input_name := trim(coalesce(p_payload ->> 'name', target.name));
    input_description := case
        when p_payload ? 'description'
            then nullif(trim(p_payload ->> 'description'), '')
        else target.description
    end;
    input_sort_order := coalesce(
        nullif(p_payload ->> 'sortOrder', '')::integer,
        target.sort_order
    );
    input_default_allow := coalesce(
        (p_payload ->> 'defaultAllowDataEntry')::boolean,
        target.default_allow_data_entry
    );
    input_is_active := coalesce(
        (p_payload ->> 'isActive')::boolean,
        target.is_active
    );

    if nullif(input_name, '') is null
       or length(input_name) > 150
       or input_sort_order < 0 then
        raise exception 'VALIDATION_ERROR';
    end if;

    if not input_is_active
       and exists (
           select 1
           from public.organization_units
           where church_id = target.church_id
             and parent_id is null
             and level = 1
             and ou_type_id = target.id
             and is_active
             and deleted_at is null
       ) then
        raise exception 'ROOT_OU_TYPE_DEACTIVATION_FORBIDDEN';
    end if;

    before_snapshot := jsonb_build_object(
        'code', target.code,
        'name', target.name,
        'description', target.description,
        'sortOrder', target.sort_order,
        'defaultAllowDataEntry', target.default_allow_data_entry,
        'isActive', target.is_active
    );

    update public.organization_unit_types
    set name = input_name,
        description = input_description,
        sort_order = input_sort_order,
        default_allow_data_entry = input_default_allow,
        is_active = input_is_active
    where id = target.id;

    insert into public.audit_logs (
        church_id, user_id, actor_church_member_id, ou_id,
        source_ou_member_id, entity_type, entity_id, action,
        before_data, after_data
    )
    values (
        target.church_id, actor_user_id, actor_membership_id, root_ou_id,
        source_assignment_id, 'organization_unit_types', target.id, 'update',
        before_snapshot,
        jsonb_build_object(
            'code', target.code,
            'name', input_name,
            'description', input_description,
            'sortOrder', input_sort_order,
            'defaultAllowDataEntry', input_default_allow,
            'isActive', input_is_active
        )
    );

    return jsonb_build_object('success', true, 'data', jsonb_build_object('ouTypeId', target.id));
exception
    when invalid_text_representation or numeric_value_out_of_range then
        raise exception 'VALIDATION_ERROR';
end;
$$;

create or replace function public.create_statistic_metric(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    actor_user_id uuid := app_security.require_current_user_id();
    actor_membership_id uuid := app_security.current_church_member_id();
    source_assignment_id uuid := app_security.require_direct_root_admin();
    tenant_id uuid := app_security.current_church_id();
    root_ou_id uuid;
    new_id uuid := gen_random_uuid();
    input_code text := upper(trim(p_payload ->> 'code'));
    input_name text := trim(p_payload ->> 'name');
    input_description text := nullif(trim(p_payload ->> 'description'), '');
    input_category text := lower(trim(p_payload ->> 'category'));
    input_unit text := trim(p_payload ->> 'unit');
    input_data_type text := p_payload ->> 'dataType';
    input_input_type text;
    input_aggregation text := p_payload ->> 'aggregation';
    input_default numeric := nullif(p_payload ->> 'defaultValue', '')::numeric;
    input_min numeric := nullif(p_payload ->> 'minValue', '')::numeric;
    input_max numeric := nullif(p_payload ->> 'maxValue', '')::numeric;
    input_required boolean := coalesce((p_payload ->> 'isRequired')::boolean, false);
    input_sort_order integer := coalesce((p_payload ->> 'sortOrder')::integer, 0);
begin
    input_input_type := case input_data_type
        when 'number' then 'number'
        when 'text' then 'text'
        when 'boolean' then 'checkbox'
        else null
    end;

    if nullif(input_code, '') is null
       or input_code !~ '^[A-Z][A-Z0-9_]{0,79}$'
       or nullif(input_name, '') is null
       or length(input_name) > 255
       or nullif(input_category, '') is null
       or length(input_category) > 80
       or nullif(input_unit, '') is null
       or length(input_unit) > 50
       or input_input_type is null
       or input_aggregation not in ('sum', 'avg', 'max', 'min', 'none')
       or input_sort_order < 0
       or (input_data_type <> 'number' and (
           input_aggregation <> 'none'
           or input_default is not null
           or input_min is not null
           or input_max is not null
       ))
       or (input_min is not null and input_max is not null and input_min > input_max)
       or (input_default is not null and input_min is not null and input_default < input_min)
       or (input_default is not null and input_max is not null and input_default > input_max) then
        raise exception 'VALIDATION_ERROR';
    end if;

    select ou_id into root_ou_id
    from public.ou_members
    where id = source_assignment_id
      and church_id = tenant_id;

    insert into public.statistic_metrics (
        id, church_id, code, name, description, category, unit,
        data_type, input_type, aggregation, default_value, min_value,
        max_value, is_required, sort_order
    )
    values (
        new_id, tenant_id, input_code, input_name, input_description,
        input_category, input_unit, input_data_type, input_input_type,
        input_aggregation, input_default, input_min, input_max,
        input_required, input_sort_order
    );

    insert into public.audit_logs (
        church_id, user_id, actor_church_member_id, ou_id,
        source_ou_member_id, entity_type, entity_id, action, after_data
    )
    values (
        tenant_id, actor_user_id, actor_membership_id, root_ou_id,
        source_assignment_id, 'statistic_metrics', new_id, 'create',
        jsonb_build_object(
            'code', input_code,
            'name', input_name,
            'description', input_description,
            'category', input_category,
            'unit', input_unit,
            'dataType', input_data_type,
            'inputType', input_input_type,
            'aggregation', input_aggregation,
            'defaultValue', input_default,
            'minValue', input_min,
            'maxValue', input_max,
            'isRequired', input_required,
            'sortOrder', input_sort_order,
            'isActive', true
        )
    );

    return jsonb_build_object('success', true, 'data', jsonb_build_object('metricId', new_id));
exception
    when unique_violation then raise exception 'DUPLICATE_METRIC_CODE';
    when invalid_text_representation or numeric_value_out_of_range then
        raise exception 'VALIDATION_ERROR';
end;
$$;

create or replace function public.update_statistic_metric(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    actor_user_id uuid := app_security.require_current_user_id();
    actor_membership_id uuid := app_security.current_church_member_id();
    source_assignment_id uuid := app_security.require_direct_root_admin();
    target public.statistic_metrics%rowtype;
    root_ou_id uuid;
    before_snapshot jsonb;
    input_name text;
    input_description text;
    input_category text;
    input_unit text;
    input_aggregation text;
    input_default numeric;
    input_min numeric;
    input_max numeric;
    input_required boolean;
    input_sort_order integer;
    input_is_active boolean;
begin
    select *
    into target
    from public.statistic_metrics
    where id = (p_payload ->> 'metricId')::uuid
      and church_id = app_security.current_church_id()
      and deleted_at is null
    for update;
    if target.id is null then raise exception 'METRIC_NOT_FOUND'; end if;

    select ou_id into root_ou_id
    from public.ou_members
    where id = source_assignment_id
      and church_id = target.church_id;

    input_name := trim(coalesce(p_payload ->> 'name', target.name));
    input_description := case
        when p_payload ? 'description'
            then nullif(trim(p_payload ->> 'description'), '')
        else target.description
    end;
    input_category := lower(trim(coalesce(p_payload ->> 'category', target.category)));
    input_unit := trim(coalesce(p_payload ->> 'unit', target.unit));
    input_aggregation := coalesce(p_payload ->> 'aggregation', target.aggregation);
    input_default := case when p_payload ? 'defaultValue'
        then nullif(p_payload ->> 'defaultValue', '')::numeric else target.default_value end;
    input_min := case when p_payload ? 'minValue'
        then nullif(p_payload ->> 'minValue', '')::numeric else target.min_value end;
    input_max := case when p_payload ? 'maxValue'
        then nullif(p_payload ->> 'maxValue', '')::numeric else target.max_value end;
    input_required := coalesce((p_payload ->> 'isRequired')::boolean, target.is_required);
    input_sort_order := coalesce(
        nullif(p_payload ->> 'sortOrder', '')::integer,
        target.sort_order
    );
    input_is_active := coalesce((p_payload ->> 'isActive')::boolean, target.is_active);

    if nullif(input_name, '') is null
       or length(input_name) > 255
       or nullif(input_category, '') is null
       or length(input_category) > 80
       or nullif(input_unit, '') is null
       or length(input_unit) > 50
       or input_aggregation not in ('sum', 'avg', 'max', 'min', 'none')
       or input_sort_order < 0
       or (target.data_type <> 'number' and (
           input_aggregation <> 'none'
           or input_default is not null
           or input_min is not null
           or input_max is not null
       ))
       or (input_min is not null and input_max is not null and input_min > input_max)
       or (input_default is not null and input_min is not null and input_default < input_min)
       or (input_default is not null and input_max is not null and input_default > input_max) then
        raise exception 'VALIDATION_ERROR';
    end if;

    if not input_is_active
       and exists (
           select 1
           from public.churches
           where id = target.church_id
             and primary_metric_id = target.id
       ) then
        raise exception 'PRIMARY_METRIC_DEACTIVATION_FORBIDDEN';
    end if;

    before_snapshot := jsonb_build_object(
        'code', target.code,
        'name', target.name,
        'description', target.description,
        'category', target.category,
        'unit', target.unit,
        'dataType', target.data_type,
        'inputType', target.input_type,
        'aggregation', target.aggregation,
        'defaultValue', target.default_value,
        'minValue', target.min_value,
        'maxValue', target.max_value,
        'isRequired', target.is_required,
        'sortOrder', target.sort_order,
        'isActive', target.is_active
    );

    update public.statistic_metrics
    set name = input_name,
        description = input_description,
        category = input_category,
        unit = input_unit,
        aggregation = input_aggregation,
        default_value = input_default,
        min_value = input_min,
        max_value = input_max,
        is_required = input_required,
        sort_order = input_sort_order,
        is_active = input_is_active
    where id = target.id;

    insert into public.audit_logs (
        church_id, user_id, actor_church_member_id, ou_id,
        source_ou_member_id, entity_type, entity_id, action,
        before_data, after_data
    )
    values (
        target.church_id, actor_user_id, actor_membership_id, root_ou_id,
        source_assignment_id, 'statistic_metrics', target.id, 'update',
        before_snapshot,
        jsonb_build_object(
            'code', target.code,
            'name', input_name,
            'description', input_description,
            'category', input_category,
            'unit', input_unit,
            'dataType', target.data_type,
            'inputType', target.input_type,
            'aggregation', input_aggregation,
            'defaultValue', input_default,
            'minValue', input_min,
            'maxValue', input_max,
            'isRequired', input_required,
            'sortOrder', input_sort_order,
            'isActive', input_is_active
        )
    );

    return jsonb_build_object('success', true, 'data', jsonb_build_object('metricId', target.id));
exception
    when invalid_text_representation or numeric_value_out_of_range then
        raise exception 'VALIDATION_ERROR';
end;
$$;

revoke all on function app_security.require_direct_root_admin() from public;
grant execute on function app_security.require_direct_root_admin() to authenticated;

revoke all on function public.update_tenant_settings(jsonb) from public;
revoke all on function public.create_organization_unit_type(jsonb) from public;
revoke all on function public.update_organization_unit_type(jsonb) from public;
revoke all on function public.create_statistic_metric(jsonb) from public;
revoke all on function public.update_statistic_metric(jsonb) from public;

grant execute on function public.update_tenant_settings(jsonb) to authenticated;
grant execute on function public.create_organization_unit_type(jsonb) to authenticated;
grant execute on function public.update_organization_unit_type(jsonb) to authenticated;
grant execute on function public.create_statistic_metric(jsonb) to authenticated;
grant execute on function public.update_statistic_metric(jsonb) to authenticated;
