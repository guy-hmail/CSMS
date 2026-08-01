-- Provision each new tenant with an independent snapshot of the latest active
-- CSMS default metric template. Later tenant-level edits affect only that
-- tenant's statistic_metrics rows.

create or replace function public.create_platform_tenant(payload jsonb)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
    actor_user_id uuid;
    tenant_id uuid := gen_random_uuid();
    root_ou_id uuid := gen_random_uuid();
    root_type_id uuid := gen_random_uuid();
    attendance_metric_id uuid;
    default_metric_template public.metric_template_sets%rowtype;
    tenant_name text := btrim(coalesce(payload ->> 'name', ''));
    tenant_slug text := lower(btrim(coalesce(payload ->> 'slug', '')));
    root_name text := btrim(coalesce(payload ->> 'rootOuName', ''));
    admin_name text := btrim(coalesce(payload ->> 'adminName', ''));
    admin_email text := lower(btrim(coalesce(payload ->> 'adminEmail', '')));
    tenant_timezone text := btrim(coalesce(payload ->> 'timezone', 'Asia/Bangkok'));
    approval_mode_value text := btrim(coalesce(payload ->> 'approvalMode', 'auto_approve'));
    week_ends_on_value smallint;
    tenant_code text;
begin
    actor_user_id := app_security.require_system_admin();

    if tenant_name = '' or length(tenant_name) > 255 then
        raise exception using errcode = '22023', message = 'TENANT_NAME_INVALID';
    end if;
    if tenant_slug !~ '^[a-z0-9]+(?:-[a-z0-9]+)*$' or length(tenant_slug) > 100 then
        raise exception using errcode = '22023', message = 'TENANT_SLUG_INVALID';
    end if;
    if root_name = '' or length(root_name) > 255 then
        raise exception using errcode = '22023', message = 'ROOT_OU_NAME_INVALID';
    end if;
    if admin_name = '' or length(admin_name) > 255 then
        raise exception using errcode = '22023', message = 'ADMIN_NAME_INVALID';
    end if;
    if admin_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' or length(admin_email) > 255 then
        raise exception using errcode = '22023', message = 'ADMIN_EMAIL_INVALID';
    end if;
    if tenant_timezone = '' or length(tenant_timezone) > 100 then
        raise exception using errcode = '22023', message = 'TIMEZONE_INVALID';
    end if;
    if approval_mode_value not in ('auto_approve', 'approval_required') then
        raise exception using errcode = '22023', message = 'APPROVAL_MODE_INVALID';
    end if;

    week_ends_on_value := case lower(coalesce(payload ->> 'weekEndsOn', 'sunday'))
        when 'sunday' then 0
        when 'saturday' then 6
        else null
    end;
    if week_ends_on_value is null then
        raise exception using errcode = '22023', message = 'WEEK_END_INVALID';
    end if;

    if exists (
        select 1 from public.churches
        where slug = tenant_slug and deleted_at is null
    ) then
        raise exception using errcode = '23505', message = 'TENANT_SLUG_EXISTS';
    end if;

    select template.*
    into default_metric_template
    from public.metric_template_sets as template
    where template.code = 'CSMS_DEFAULT'
      and template.is_active = true
    order by template.version desc
    limit 1;

    if default_metric_template.id is null then
        raise exception using errcode = 'P0002', message = 'DEFAULT_METRIC_TEMPLATE_NOT_FOUND';
    end if;

    tenant_code := 'T-' || upper(substr(replace(tenant_id::text, '-', ''), 1, 12));

    insert into public.churches (
        id, code, slug, name, timezone, approval_mode,
        reporting_week_ends_on, status, trial_ends_at, is_active
    )
    values (
        tenant_id, tenant_code, tenant_slug, tenant_name, tenant_timezone,
        approval_mode_value, week_ends_on_value, 'trial', now() + interval '30 days', true
    );

    insert into public.organization_unit_types (
        id, church_id, code, name, sort_order,
        default_allow_data_entry, is_active, created_by
    )
    values
        (root_type_id, tenant_id, 'CHURCH', 'คริสตจักร', 10, false, true, actor_user_id),
        (gen_random_uuid(), tenant_id, 'REGION', 'ภาค', 20, false, true, actor_user_id),
        (gen_random_uuid(), tenant_id, 'DISTRICT', 'เขต', 30, false, true, actor_user_id),
        (gen_random_uuid(), tenant_id, 'GROUP', 'กลุ่ม', 40, true, true, actor_user_id);

    insert into public.organization_units (
        id, church_id, structure_root_id, parent_id, ou_type_id,
        code, name, path, level, sort_order, allow_data_entry, created_by
    )
    values (
        root_ou_id, tenant_id, root_ou_id, null, root_type_id,
        'ROOT', root_name, '/' || root_ou_id::text, 1, 10, false, actor_user_id
    );

    insert into public.statistic_metrics (
        id, church_id, source_template_set_id, source_template_code,
        code, name, description, category, unit, data_type,
        input_type, aggregation, default_value, min_value, max_value,
        is_required, sort_order, is_active
    )
    select
        gen_random_uuid(),
        tenant_id,
        default_metric_template.id,
        definition ->> 'code',
        definition ->> 'code',
        definition ->> 'name',
        nullif(definition ->> 'description', ''),
        definition ->> 'category',
        coalesce(nullif(definition ->> 'unit', ''), 'count'),
        coalesce(nullif(definition ->> 'dataType', ''), 'number'),
        case coalesce(nullif(definition ->> 'dataType', ''), 'number')
            when 'number' then 'number'
            when 'text' then 'text'
            else 'checkbox'
        end,
        case
            when coalesce(nullif(definition ->> 'dataType', ''), 'number') = 'number'
                then coalesce(nullif(definition ->> 'aggregation', ''), 'sum')
            else 'none'
        end,
        nullif(definition ->> 'defaultValue', '')::numeric,
        coalesce(nullif(definition ->> 'minValue', '')::numeric, 0),
        nullif(definition ->> 'maxValue', '')::numeric,
        coalesce((definition ->> 'required')::boolean, false),
        (ordinality * 10)::integer,
        true
    from jsonb_array_elements(default_metric_template.metric_definitions)
         with ordinality as metric_definition(definition, ordinality);

    select metric.id
    into attendance_metric_id
    from public.statistic_metrics as metric
    where metric.church_id = tenant_id
      and metric.code = 'ATTENDANCE';

    if attendance_metric_id is null then
        raise exception using errcode = 'P0002', message = 'DEFAULT_PRIMARY_METRIC_NOT_FOUND';
    end if;

    update public.churches
    set primary_metric_id = attendance_metric_id
    where id = tenant_id;

    insert into public.tenant_invitations (
        church_id, email, display_name, target_ou_id, permission,
        token_hash, status, expires_at, invited_by
    )
    values (
        tenant_id, admin_email, admin_name, root_ou_id, 'admin',
        encode(extensions.digest(gen_random_uuid()::text || clock_timestamp()::text, 'sha256'), 'hex'),
        'pending', now() + interval '7 days', actor_user_id
    );

    insert into public.audit_logs (
        church_id, user_id, entity_type, entity_id, action, after_data, metadata
    )
    values (
        tenant_id,
        actor_user_id,
        'churches',
        tenant_id,
        'create_tenant',
        jsonb_build_object(
            'name', tenant_name,
            'slug', tenant_slug,
            'status', 'trial',
            'root_ou_id', root_ou_id,
            'metric_template_id', default_metric_template.id,
            'metric_template_version', default_metric_template.version
        ),
        jsonb_build_object('admin_email', admin_email)
    );

    return tenant_id;
end;
$$;

revoke all on function public.create_platform_tenant(jsonb) from public;
grant execute on function public.create_platform_tenant(jsonb) to authenticated;
