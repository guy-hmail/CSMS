-- BE-007: Append-only audit enforcement and authorized audit read API.

create or replace function app_security.redact_audit_json(input jsonb)
returns jsonb
language plpgsql
immutable
security definer
set search_path = ''
as $$
declare
    result jsonb;
begin
    if input is null then return null; end if;
    if jsonb_typeof(input) = 'object' then
        select coalesce(
            jsonb_object_agg(
                entry.key,
                case
                    when lower(entry.key) = any(array[
                        'password', 'secret', 'token', 'tokenhash',
                        'token_hash', 'idtoken', 'id_token', 'rawtoken',
                        'raw_token', 'authorization', 'email', 'phone',
                        'lineuserid', 'line_user_id'
                    ]) then '"[REDACTED]"'::jsonb
                    else app_security.redact_audit_json(entry.value)
                end
            ),
            '{}'::jsonb
        )
        into result
        from jsonb_each(input) as entry;
        return result;
    elsif jsonb_typeof(input) = 'array' then
        select coalesce(
            jsonb_agg(app_security.redact_audit_json(element.value)),
            '[]'::jsonb
        )
        into result
        from jsonb_array_elements(input) as element;
        return result;
    end if;
    return input;
end;
$$;

create or replace function app_security.prevent_audit_log_mutation()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
    raise exception 'AUDIT_LOG_IMMUTABLE';
end;
$$;

create trigger trg_audit_logs_immutable
before update or delete on public.audit_logs
for each row execute function app_security.prevent_audit_log_mutation();

create or replace function public.get_audit_logs(p_filters jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
    ignored_user_id uuid := app_security.require_current_user_id();
    tenant_id uuid := app_security.current_church_id();
    filter_ou_id uuid;
    filter_entity_id uuid;
    filter_actor_id uuid;
    filter_entity_type text := nullif(trim(p_filters ->> 'entityType'), '');
    filter_action text := nullif(trim(p_filters ->> 'action'), '');
    from_date date;
    to_date date;
    page_number integer := greatest(coalesce((p_filters ->> 'page')::integer, 1), 1);
    page_size integer := least(greatest(coalesce((p_filters ->> 'pageSize')::integer, 20), 1), 100);
    total_count bigint;
    items jsonb;
begin
    filter_ou_id := nullif(p_filters ->> 'ouId', '')::uuid;
    filter_entity_id := nullif(p_filters ->> 'entityId', '')::uuid;
    filter_actor_id := nullif(p_filters ->> 'actorUserId', '')::uuid;
    from_date := nullif(p_filters ->> 'fromDate', '')::date;
    to_date := nullif(p_filters ->> 'toDate', '')::date;

    if filter_ou_id is not null
       and not app_security.has_subtree_permission(
           filter_ou_id,
           array['admin', 'manager', 'approver']
       ) then
        raise exception 'AUDIT_SCOPE_DENIED';
    end if;

    with visible as (
        select audit.*
        from public.audit_logs as audit
        where app_security.can_view_audit_log(
                audit.church_id,
                audit.ou_id,
                audit.entity_type,
                audit.action
              )
          and (filter_ou_id is null or audit.ou_id = filter_ou_id)
          and (filter_entity_type is null or audit.entity_type = filter_entity_type)
          and (filter_entity_id is null or audit.entity_id = filter_entity_id)
          and (filter_actor_id is null or audit.user_id = filter_actor_id)
          and (filter_action is null or audit.action = filter_action)
          and (from_date is null or audit.created_at >= from_date::timestamptz)
          and (to_date is null or audit.created_at < (to_date + 1)::timestamptz)
    )
    select count(*) into total_count from visible;

    with visible as (
        select audit.*
        from public.audit_logs as audit
        where app_security.can_view_audit_log(
                audit.church_id,
                audit.ou_id,
                audit.entity_type,
                audit.action
              )
          and (filter_ou_id is null or audit.ou_id = filter_ou_id)
          and (filter_entity_type is null or audit.entity_type = filter_entity_type)
          and (filter_entity_id is null or audit.entity_id = filter_entity_id)
          and (filter_actor_id is null or audit.user_id = filter_actor_id)
          and (filter_action is null or audit.action = filter_action)
          and (from_date is null or audit.created_at >= from_date::timestamptz)
          and (to_date is null or audit.created_at < (to_date + 1)::timestamptz)
        order by audit.created_at desc, audit.id desc
        limit page_size
        offset (page_number - 1) * page_size
    )
    select coalesce(
        jsonb_agg(
            jsonb_build_object(
                'id', visible.id,
                'churchId', visible.church_id,
                'ouId', visible.ou_id,
                'userId', visible.user_id,
                'actorChurchMemberId', visible.actor_church_member_id,
                'sourceOuMemberId', visible.source_ou_member_id,
                'entityType', visible.entity_type,
                'entityId', visible.entity_id,
                'action', visible.action,
                'beforeData', app_security.redact_audit_json(visible.before_data),
                'afterData', app_security.redact_audit_json(visible.after_data),
                'metadata', app_security.redact_audit_json(visible.metadata),
                'requestId', visible.request_id,
                'createdAt', visible.created_at
            )
            order by visible.created_at desc, visible.id desc
        ),
        '[]'::jsonb
    )
    into items
    from visible;

    return jsonb_build_object(
        'success', true,
        'data', jsonb_build_object(
            'items', items,
            'page', page_number,
            'pageSize', page_size,
            'total', total_count
        )
    );
end;
$$;

revoke all on function app_security.redact_audit_json(jsonb) from public;
revoke all on function app_security.prevent_audit_log_mutation() from public;
revoke all on function public.get_audit_logs(jsonb) from public;
grant execute on function public.get_audit_logs(jsonb) to authenticated;
