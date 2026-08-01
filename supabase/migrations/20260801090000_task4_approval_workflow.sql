-- Task 4: approval queue, detail and audited workflow mutations.

create or replace function app_security.approval_actor_context(p_ou_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
    tenant_id uuid := app_security.current_church_id();
    actor_membership_id uuid := app_security.current_church_member_id();
    target_ou public.organization_units%rowtype;
    source_assignment public.ou_members%rowtype;
    source_level integer;
    source_parent_id uuid;
    nearest_approver_level integer;
    can_act boolean := false;
    is_override boolean := false;
begin
    select * into target_ou
    from public.organization_units
    where id = p_ou_id and church_id = tenant_id and is_active and deleted_at is null;
    if target_ou.id is null or actor_membership_id is null then
        return jsonb_build_object('canAct', false);
    end if;

    select max(assigned.level) into nearest_approver_level
    from public.organization_units as assigned
    join public.ou_members as assignment
      on assignment.church_id = assigned.church_id and assignment.ou_id = assigned.id
    join public.church_members as membership
      on membership.church_id = assignment.church_id and membership.id = assignment.church_member_id
    join public.users as app_user on app_user.id = membership.user_id
    where assigned.church_id = tenant_id
      and assigned.structure_root_id = target_ou.structure_root_id
      and (target_ou.path = assigned.path or target_ou.path like assigned.path || '/%')
      and assigned.is_active and assigned.deleted_at is null
      and assignment.permission = 'approver' and assignment.is_active and assignment.deleted_at is null
      and membership.status = 'active'
      and app_user.is_active and app_user.deleted_at is null;

    select assignment.*
    into source_assignment
    from public.organization_units as assigned
    join public.ou_members as assignment
      on assignment.church_id = assigned.church_id and assignment.ou_id = assigned.id
    where assigned.church_id = tenant_id
      and assigned.structure_root_id = target_ou.structure_root_id
      and (target_ou.path = assigned.path or target_ou.path like assigned.path || '/%')
      and assigned.is_active and assigned.deleted_at is null
      and assignment.church_member_id = actor_membership_id
      and assignment.permission in ('admin', 'approver')
      and assignment.is_active and assignment.deleted_at is null
    order by assigned.level desc,
      case assignment.permission when 'admin' then 0 else 1 end,
      assignment.assigned_at desc
    limit 1;

    if source_assignment.id is not null then
        select assigned.level, assigned.parent_id into source_level, source_parent_id
        from public.organization_units as assigned
        where assigned.id = source_assignment.ou_id and assigned.church_id = tenant_id;
    end if;

    if source_assignment.id is not null then
        if source_assignment.permission = 'admin' then
            can_act := nearest_approver_level is not null or source_parent_id is null;
            is_override := can_act and nearest_approver_level is not null and source_level < nearest_approver_level;
        elsif source_level = nearest_approver_level then
            can_act := true;
        elsif source_assignment.can_override then
            can_act := true;
            is_override := true;
        end if;
    end if;

    return jsonb_build_object(
        'canAct', can_act,
        'sourceAssignmentId', source_assignment.id,
        'permission', source_assignment.permission,
        'isOverride', is_override
    );
end;
$$;

create or replace function public.list_pending_submissions(
    p_period_id uuid default null,
    p_ou_id uuid default null,
    p_status text default 'submitted'
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
    ignored_user_id uuid := app_security.require_current_user_id();
    tenant_id uuid := app_security.current_church_id();
    tenant_mode text;
    items_data jsonb;
    periods_data jsonb;
    ous_data jsonb;
    filter_ou public.organization_units%rowtype;
begin
    if p_status is not null and p_status not in ('submitted', 'approved', 'rejected', 'returned') then
        raise exception 'INVALID_STATUS_FILTER';
    end if;
    if p_period_id is not null and not exists (
        select 1 from public.statistic_periods where id = p_period_id and church_id = tenant_id
    ) then raise exception 'PERIOD_NOT_FOUND'; end if;
    if p_ou_id is not null then
        select * into filter_ou from public.organization_units
        where id = p_ou_id and church_id = tenant_id and is_active and deleted_at is null;
        if filter_ou.id is null or not coalesce((app_security.approval_actor_context(filter_ou.id) ->> 'canAct')::boolean, false) then
            raise exception 'OU_NOT_FOUND';
        end if;
    end if;

    select approval_mode into tenant_mode from public.churches where id = tenant_id;

    select coalesce(jsonb_agg(jsonb_build_object(
        'id', submission.id,
        'status', submission.status,
        'revisionNo', submission.revision_no,
        'remarks', submission.remarks,
        'submittedAt', submission.submitted_at,
        'approvedAt', submission.approved_at,
        'periodId', period.id,
        'periodLabel', period.label,
        'periodEnd', period.period_end,
        'ouId', ou.id,
        'ouName', ou.name,
        'ouCode', ou.code,
        'submittedByName', submitter.display_name,
        'metricCount', (select count(*) from public.statistic_values value where value.church_id = tenant_id and value.submission_id = submission.id),
        'isOverride', coalesce((app_security.approval_actor_context(ou.id) ->> 'isOverride')::boolean, false)
    ) order by submission.submitted_at desc nulls last, period.period_end desc), '[]'::jsonb)
    into items_data
    from public.statistic_submissions as submission
    join public.statistic_periods as period on period.church_id = submission.church_id and period.id = submission.period_id
    join public.organization_units as ou on ou.church_id = submission.church_id and ou.id = submission.ou_id
    left join public.users as submitter on submitter.id = submission.submitted_by
    where submission.church_id = tenant_id
      and submission.deleted_at is null
      and (p_status is null or submission.status = p_status)
      and (p_period_id is null or submission.period_id = p_period_id)
      and (p_ou_id is null or ou.path = filter_ou.path or ou.path like filter_ou.path || '/%')
      and coalesce((app_security.approval_actor_context(ou.id) ->> 'canAct')::boolean, false);

    select coalesce(jsonb_agg(jsonb_build_object(
        'id', period.id, 'label', period.label, 'periodEnd', period.period_end
    ) order by period.period_end desc), '[]'::jsonb)
    into periods_data
    from public.statistic_periods as period
    where period.church_id = tenant_id and period.period_type = 'week';

    select coalesce(jsonb_agg(jsonb_build_object(
        'id', ou.id, 'name', ou.name, 'code', ou.code, 'path', ou.path, 'level', ou.level
    ) order by ou.path, ou.sort_order, ou.name), '[]'::jsonb)
    into ous_data
    from public.organization_units as ou
    where ou.church_id = tenant_id and ou.is_active and ou.deleted_at is null
      and coalesce((app_security.approval_actor_context(ou.id) ->> 'canAct')::boolean, false);

    return jsonb_build_object('success', true, 'data', jsonb_build_object(
        'approvalMode', tenant_mode,
        'items', items_data,
        'periods', periods_data,
        'organizationUnits', ous_data
    ));
end;
$$;

create or replace function public.get_approval_submission_detail(p_submission_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
    ignored_user_id uuid := app_security.require_current_user_id();
    tenant_id uuid := app_security.current_church_id();
    submission public.statistic_submissions%rowtype;
    actor_context jsonb;
    values_data jsonb;
    logs_data jsonb;
begin
    select * into submission from public.statistic_submissions
    where id = p_submission_id and church_id = tenant_id and deleted_at is null;
    if submission.id is null then raise exception 'SUBMISSION_NOT_FOUND'; end if;
    actor_context := app_security.approval_actor_context(submission.ou_id);
    if not coalesce((actor_context ->> 'canAct')::boolean, false) then raise exception 'SUBMISSION_NOT_FOUND'; end if;

    select coalesce(jsonb_agg(jsonb_build_object(
        'metricId', metric.id, 'metricCode', metric.code, 'metricName', metric.name,
        'unit', metric.unit, 'dataType', metric.data_type,
        'numericValue', value.numeric_value, 'textValue', value.text_value,
        'booleanValue', value.boolean_value
    ) order by metric.sort_order, metric.name), '[]'::jsonb)
    into values_data
    from public.statistic_values value
    join public.statistic_metrics metric on metric.church_id = value.church_id and metric.id = value.metric_id
    where value.church_id = tenant_id and value.submission_id = submission.id;

    select coalesce(jsonb_agg(jsonb_build_object(
        'id', log.id, 'action', log.action, 'fromStatus', log.from_status,
        'toStatus', log.to_status, 'isOverride', log.is_override,
        'reason', log.reason, 'createdAt', log.created_at,
        'actorName', actor.display_name
    ) order by log.created_at desc, log.id desc), '[]'::jsonb)
    into logs_data
    from public.approval_logs log
    join public.users actor on actor.id = log.action_by
    where log.church_id = tenant_id and log.submission_id = submission.id;

    return jsonb_build_object('success', true, 'data', jsonb_build_object(
        'submission', jsonb_build_object(
            'id', submission.id, 'status', submission.status, 'revisionNo', submission.revision_no,
            'remarks', submission.remarks, 'ouId', submission.ou_id, 'periodId', submission.period_id,
            'submittedAt', submission.submitted_at, 'approvedAt', submission.approved_at,
            'approvalNote', submission.approval_note
        ),
        'values', values_data,
        'history', logs_data,
        'capabilities', jsonb_build_object(
            'canApprove', submission.status = 'submitted',
            'canReject', submission.status = 'submitted',
            'canReturn', submission.status in ('submitted', 'approved'),
            'isOverride', coalesce((actor_context ->> 'isOverride')::boolean, false)
        )
    ));
end;
$$;

create or replace function app_security.process_approval_action(p_payload jsonb, p_action text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    current_actor_user_id uuid := app_security.require_current_user_id();
    actor_membership_id uuid := app_security.current_church_member_id();
    tenant_id uuid := app_security.current_church_id();
    submission public.statistic_submissions%rowtype;
    actor_context jsonb;
    request_id uuid := (p_payload ->> 'clientRequestId')::uuid;
    expected_revision integer := (p_payload ->> 'expectedRevision')::integer;
    reason text := nullif(trim(p_payload ->> 'reason'), '');
    next_status text;
    prior_request public.api_idempotency_keys%rowtype;
    request_hash text;
    result jsonb;
begin
    if p_action not in ('approve', 'reject', 'return') then raise exception 'INVALID_APPROVAL_ACTION'; end if;
    if request_id is null then raise exception 'CLIENT_REQUEST_ID_REQUIRED'; end if;
    if expected_revision is null then raise exception 'EXPECTED_REVISION_REQUIRED'; end if;
    if p_action in ('reject', 'return') and reason is null then raise exception 'REASON_REQUIRED'; end if;
    request_hash := encode(extensions.digest(p_payload::text, 'sha256'), 'hex');

    select * into prior_request from public.api_idempotency_keys key
    where key.church_id = tenant_id and key.actor_user_id = current_actor_user_id
      and key.operation = p_action || '_statistics' and key.client_request_id = request_id
    for update;
    if prior_request.id is not null then
        if prior_request.request_hash <> request_hash then raise exception 'IDEMPOTENCY_CONFLICT'; end if;
        if prior_request.response_body is not null then return prior_request.response_body; end if;
    else
        insert into public.api_idempotency_keys(church_id, actor_user_id, operation, client_request_id, request_hash, expires_at)
        values (tenant_id, current_actor_user_id, p_action || '_statistics', request_id, request_hash, now() + interval '24 hours');
    end if;

    select * into submission from public.statistic_submissions
    where id = (p_payload ->> 'submissionId')::uuid and church_id = tenant_id and deleted_at is null
    for update;
    if submission.id is null then raise exception 'SUBMISSION_NOT_FOUND'; end if;
    if submission.revision_no <> expected_revision then raise exception 'REVISION_CONFLICT'; end if;
    actor_context := app_security.approval_actor_context(submission.ou_id);
    if not coalesce((actor_context ->> 'canAct')::boolean, false) then raise exception 'PERMISSION_DENIED'; end if;

    if p_action in ('approve', 'reject') and submission.status <> 'submitted' then raise exception 'INVALID_STATUS_TRANSITION'; end if;
    if p_action = 'return' and submission.status not in ('submitted', 'approved') then raise exception 'INVALID_STATUS_TRANSITION'; end if;
    next_status := case p_action when 'approve' then 'approved' when 'reject' then 'rejected' else 'returned' end;

    update public.statistic_submissions
    set status = next_status,
        approval_note = reason,
        approved_by = case when p_action = 'approve' then current_actor_user_id else null end,
        approved_at = case when p_action = 'approve' then now() else null end,
        rejected_by = case when p_action = 'reject' then current_actor_user_id else null end,
        rejected_at = case when p_action = 'reject' then now() else null end,
        returned_by = case when p_action = 'return' then current_actor_user_id else null end,
        returned_at = case when p_action = 'return' then now() else null end,
        updated_at = now()
    where id = submission.id;

    insert into public.approval_logs(church_id, submission_id, action, action_by, from_status, to_status, is_override, reason)
    values (tenant_id, submission.id, p_action, current_actor_user_id, submission.status, next_status,
      coalesce((actor_context ->> 'isOverride')::boolean, false), reason);
    insert into public.audit_logs(church_id, user_id, actor_church_member_id, ou_id, source_ou_member_id,
      entity_type, entity_id, action, before_data, after_data, metadata, request_id)
    values (tenant_id, current_actor_user_id, actor_membership_id, submission.ou_id,
      (actor_context ->> 'sourceAssignmentId')::uuid, 'statistic_submissions', submission.id, p_action,
      jsonb_build_object('status', submission.status, 'revisionNo', submission.revision_no),
      jsonb_build_object('status', next_status, 'revisionNo', submission.revision_no),
      jsonb_build_object('reason', reason, 'isOverride', coalesce((actor_context ->> 'isOverride')::boolean, false)), request_id);

    result := jsonb_build_object('success', true, 'data', jsonb_build_object(
      'submissionId', submission.id, 'status', next_status, 'revisionNo', submission.revision_no
    ));
    update public.api_idempotency_keys key set response_body = result, response_status = 200
    where key.church_id = tenant_id and key.actor_user_id = current_actor_user_id
      and key.operation = p_action || '_statistics' and key.client_request_id = request_id;
    return result;
end;
$$;

create or replace function public.approve_submission(p_payload jsonb) returns jsonb
language sql security definer set search_path = '' as $$ select app_security.process_approval_action(p_payload, 'approve'); $$;
create or replace function public.reject_submission(p_payload jsonb) returns jsonb
language sql security definer set search_path = '' as $$ select app_security.process_approval_action(p_payload, 'reject'); $$;
create or replace function public.return_submission_for_edit(p_payload jsonb) returns jsonb
language sql security definer set search_path = '' as $$ select app_security.process_approval_action(p_payload, 'return'); $$;

revoke all on function app_security.approval_actor_context(uuid) from public;
revoke all on function app_security.process_approval_action(jsonb, text) from public;
revoke all on function public.list_pending_submissions(uuid, uuid, text) from public;
revoke all on function public.get_approval_submission_detail(uuid) from public;
revoke all on function public.approve_submission(jsonb) from public;
revoke all on function public.reject_submission(jsonb) from public;
revoke all on function public.return_submission_for_edit(jsonb) from public;
grant execute on function public.list_pending_submissions(uuid, uuid, text) to authenticated;
grant execute on function public.get_approval_submission_detail(uuid) to authenticated;
grant execute on function public.approve_submission(jsonb) to authenticated;
grant execute on function public.reject_submission(jsonb) to authenticated;
grant execute on function public.return_submission_for_edit(jsonb) to authenticated;
