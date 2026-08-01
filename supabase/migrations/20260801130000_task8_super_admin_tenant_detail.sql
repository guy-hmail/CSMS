-- Task 8: complete the Super Admin tenant control plane.

create or replace function app_security.current_church_id()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
    select membership.church_id
    from public.users as app_user
    join public.church_members as membership on membership.user_id = app_user.id
    join public.churches as church on church.id = membership.church_id
    where app_user.auth_user_id = app_security.jwt_subject()
      and app_user.is_active = true
      and app_user.deleted_at is null
      and membership.status = 'active'
      and church.status in ('trial', 'active')
      and church.is_active = true
      and church.deleted_at is null
      and membership.church_id = nullif(
          nullif(current_setting('request.jwt.claims', true), '')::jsonb
              -> 'app_metadata' ->> 'active_church_id',
          ''
      )::uuid
    limit 1;
$$;

create or replace function public.get_platform_tenant_detail(p_tenant_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare result jsonb;
begin
    perform app_security.require_system_admin();
    select jsonb_build_object(
        'id', church.id,
        'code', church.code,
        'name', church.name,
        'slug', church.slug,
        'description', church.description,
        'timezone', church.timezone,
        'approvalMode', church.approval_mode,
        'weekEndsOn', case church.reporting_week_ends_on when 6 then 'saturday' else 'sunday' end,
        'status', church.status,
        'trialEndsAt', church.trial_ends_at,
        'createdAt', church.created_at,
        'updatedAt', church.updated_at,
        'provisioning', jsonb_build_object(
            'rootOuCount', (select count(*) from public.organization_units ou where ou.church_id = church.id and ou.parent_id is null and ou.is_active and ou.deleted_at is null),
            'ouTypeCount', (select count(*) from public.organization_unit_types t where t.church_id = church.id and t.is_active),
            'metricCount', (select count(*) from public.statistic_metrics m where m.church_id = church.id and m.is_active),
            'memberCount', (select count(*) from public.church_members cm where cm.church_id = church.id and cm.status = 'active'),
            'ready', (select count(*) = 1 from public.organization_units ou where ou.church_id = church.id and ou.parent_id is null and ou.is_active and ou.deleted_at is null)
                and (select count(*) >= 4 from public.organization_unit_types t where t.church_id = church.id and t.is_active)
                and (select count(*) >= 9 from public.statistic_metrics m where m.church_id = church.id and m.is_active)
        )
    ) into result
    from public.churches church
    where church.id = p_tenant_id and church.deleted_at is null;
    if result is null then raise exception using errcode = 'P0002', message = 'TENANT_NOT_FOUND'; end if;
    return result;
end;
$$;

create or replace function public.update_platform_tenant(p_tenant_id uuid, payload jsonb)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
    actor_user_id uuid := app_security.require_system_admin();
    previous public.churches%rowtype;
    next_name text := btrim(coalesce(payload ->> 'name', ''));
    next_slug text := lower(btrim(coalesce(payload ->> 'slug', '')));
    next_timezone text := btrim(coalesce(payload ->> 'timezone', ''));
    next_approval text := btrim(coalesce(payload ->> 'approvalMode', ''));
    next_week smallint;
begin
    select * into previous from public.churches where id = p_tenant_id and deleted_at is null for update;
    if previous.id is null then raise exception using errcode = 'P0002', message = 'TENANT_NOT_FOUND'; end if;
    if previous.status = 'closed' then raise exception using errcode = '55000', message = 'TENANT_CLOSED'; end if;
    if next_name = '' or length(next_name) > 255 then raise exception using errcode = '22023', message = 'TENANT_NAME_INVALID'; end if;
    if next_slug !~ '^[a-z0-9]+(?:-[a-z0-9]+)*$' or length(next_slug) > 100 then raise exception using errcode = '22023', message = 'TENANT_SLUG_INVALID'; end if;
    if exists (select 1 from public.churches where slug = next_slug and id <> p_tenant_id and deleted_at is null) then raise exception using errcode = '23505', message = 'TENANT_SLUG_EXISTS'; end if;
    if next_timezone = '' or length(next_timezone) > 100 then raise exception using errcode = '22023', message = 'TIMEZONE_INVALID'; end if;
    if next_approval not in ('auto_approve', 'approval_required') then raise exception using errcode = '22023', message = 'APPROVAL_MODE_INVALID'; end if;
    next_week := case lower(payload ->> 'weekEndsOn') when 'sunday' then 0 when 'saturday' then 6 else null end;
    if next_week is null then raise exception using errcode = '22023', message = 'WEEK_END_INVALID'; end if;

    update public.churches set
        name = next_name, slug = next_slug,
        description = nullif(btrim(coalesce(payload ->> 'description', '')), ''),
        timezone = next_timezone, approval_mode = next_approval,
        reporting_week_ends_on = next_week, updated_at = now()
    where id = p_tenant_id;

    insert into public.audit_logs(church_id, user_id, entity_type, entity_id, action, before_data, after_data)
    values (p_tenant_id, actor_user_id, 'churches', p_tenant_id, 'update_platform_tenant',
        jsonb_build_object('name', previous.name, 'slug', previous.slug, 'timezone', previous.timezone, 'approvalMode', previous.approval_mode, 'weekEndsOn', previous.reporting_week_ends_on),
        jsonb_build_object('name', next_name, 'slug', next_slug, 'timezone', next_timezone, 'approvalMode', next_approval, 'weekEndsOn', next_week));
end;
$$;

create or replace function public.list_platform_tenant_invitations(p_tenant_id uuid)
returns table(id uuid, email varchar, display_name varchar, permission varchar, status text, expires_at timestamptz, accepted_at timestamptz, revoked_at timestamptz, created_at timestamptz)
language plpgsql stable security definer set search_path = ''
as $$
begin
    perform app_security.require_system_admin();
    if not exists (select 1 from public.churches where churches.id = p_tenant_id and deleted_at is null) then raise exception using errcode = 'P0002', message = 'TENANT_NOT_FOUND'; end if;
    return query select invitation.id, invitation.email, invitation.display_name, invitation.permission,
        (case when invitation.status = 'pending' and invitation.expires_at <= now() then 'expired' else invitation.status end)::text,
        invitation.expires_at, invitation.accepted_at, invitation.revoked_at, invitation.created_at
    from public.tenant_invitations invitation where invitation.church_id = p_tenant_id
    order by invitation.created_at desc;
end;
$$;

create or replace function public.revoke_platform_tenant_invitation(p_tenant_id uuid, p_invitation_id uuid)
returns void language plpgsql security definer set search_path = ''
as $$
declare actor_user_id uuid := app_security.require_system_admin(); changed boolean;
begin
    update public.tenant_invitations set status = 'revoked', revoked_by = actor_user_id, revoked_at = now(), updated_at = now()
    where id = p_invitation_id and church_id = p_tenant_id and status = 'pending' returning true into changed;
    if not coalesce(changed, false) then raise exception using errcode = 'P0002', message = 'PENDING_INVITATION_NOT_FOUND'; end if;
    insert into public.audit_logs(church_id, user_id, entity_type, entity_id, action, after_data)
    values (p_tenant_id, actor_user_id, 'tenant_invitations', p_invitation_id, 'revoke_platform_tenant_invitation', jsonb_build_object('status', 'revoked'));
end;
$$;

create or replace function public.list_platform_tenant_activity(p_tenant_id uuid, p_limit integer default 50)
returns table(id uuid, action varchar, entity_type varchar, entity_id uuid, actor_name varchar, before_data jsonb, after_data jsonb, metadata jsonb, created_at timestamptz)
language plpgsql stable security definer set search_path = ''
as $$
begin
    perform app_security.require_system_admin();
    if p_limit < 1 or p_limit > 200 then raise exception using errcode = '22023', message = 'LIMIT_INVALID'; end if;
    return query select audit.id, audit.action, audit.entity_type, audit.entity_id,
        coalesce(actor.display_name, 'System')::varchar, audit.before_data, audit.after_data, audit.metadata, audit.created_at
    from public.audit_logs audit left join public.users actor on actor.id = audit.user_id
    where audit.church_id = p_tenant_id order by audit.created_at desc limit p_limit;
end;
$$;

create or replace function public.set_platform_tenant_status(p_tenant_id uuid, p_status text)
returns void language plpgsql security definer set search_path = ''
as $$
declare actor_user_id uuid := app_security.require_system_admin(); previous_status text;
begin
    if p_status not in ('active', 'suspended', 'closed') then raise exception using errcode = '22023', message = 'TENANT_STATUS_INVALID'; end if;
    select status into previous_status from public.churches where id = p_tenant_id and deleted_at is null for update;
    if previous_status is null then raise exception using errcode = 'P0002', message = 'TENANT_NOT_FOUND'; end if;
    if previous_status = 'closed' then raise exception using errcode = '55000', message = 'TENANT_CLOSED'; end if;
    update public.churches set status = p_status, is_active = p_status = 'active', updated_at = now() where id = p_tenant_id;
    insert into public.audit_logs(church_id, user_id, entity_type, entity_id, action, before_data, after_data, metadata)
    values (p_tenant_id, actor_user_id, 'churches', p_tenant_id, 'update_tenant_status', jsonb_build_object('status', previous_status), jsonb_build_object('status', p_status),
        case when p_status = 'closed' then jsonb_build_object('retentionPolicy', 'retain_indefinitely_no_hard_delete') else '{}'::jsonb end);
end;
$$;

revoke all on function public.get_platform_tenant_detail(uuid) from public;
revoke all on function public.update_platform_tenant(uuid, jsonb) from public;
revoke all on function public.list_platform_tenant_invitations(uuid) from public;
revoke all on function public.revoke_platform_tenant_invitation(uuid, uuid) from public;
revoke all on function public.list_platform_tenant_activity(uuid, integer) from public;
grant execute on function public.get_platform_tenant_detail(uuid) to authenticated;
grant execute on function public.update_platform_tenant(uuid, jsonb) to authenticated;
grant execute on function public.list_platform_tenant_invitations(uuid) to authenticated;
grant execute on function public.revoke_platform_tenant_invitation(uuid, uuid) to authenticated;
grant execute on function public.list_platform_tenant_activity(uuid, integer) to authenticated;
