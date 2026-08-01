-- BE-005: Weekly draft and submission RPCs.

create or replace function app_security.process_statistics_payload(
    p_payload jsonb,
    p_submit boolean
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    current_actor_user_id uuid := app_security.require_current_user_id();
    actor_membership_id uuid := app_security.current_church_member_id();
    tenant_id uuid := app_security.current_church_id();
    target_ou public.organization_units%rowtype;
    target_period public.statistic_periods%rowtype;
    tenant public.churches%rowtype;
    submission public.statistic_submissions%rowtype;
    source_assignment_id uuid;
    request_id uuid;
    request_hash text;
    prior_request public.api_idempotency_keys%rowtype;
    expected_revision integer;
    next_revision integer;
    next_status varchar(30);
    values_snapshot jsonb;
    before_snapshot jsonb;
    result jsonb;
    item_count integer;
    valid_count integer;
begin
    if jsonb_typeof(p_payload -> 'values') <> 'array' then
        raise exception 'VALIDATION_ERROR';
    end if;
    request_id := (p_payload ->> 'clientRequestId')::uuid;
    if request_id is null then raise exception 'CLIENT_REQUEST_ID_REQUIRED'; end if;
    request_hash := encode(extensions.digest(p_payload::text, 'sha256'), 'hex');

    select *
    into prior_request
    from public.api_idempotency_keys as idempotency
    where idempotency.church_id = tenant_id
      and idempotency.actor_user_id = current_actor_user_id
      and idempotency.operation = case when p_submit then 'submit_statistics' else 'save_statistics_draft' end
      and idempotency.client_request_id = request_id
    for update;
    if prior_request.id is not null then
        if prior_request.request_hash <> request_hash then
            raise exception 'IDEMPOTENCY_CONFLICT';
        end if;
        if prior_request.response_body is not null then
            return prior_request.response_body;
        end if;
    else
        insert into public.api_idempotency_keys (
            church_id, actor_user_id, operation, client_request_id,
            request_hash, expires_at
        )
        values (
            tenant_id, current_actor_user_id,
            case when p_submit then 'submit_statistics' else 'save_statistics_draft' end,
            request_id, request_hash, now() + interval '24 hours'
        );
    end if;

    select *
    into target_ou
    from public.organization_units
    where id = (p_payload ->> 'ouId')::uuid
      and church_id = tenant_id
      and is_active
      and deleted_at is null;
    if target_ou.id is null then raise exception 'OU_NOT_FOUND'; end if;
    if not target_ou.allow_data_entry then raise exception 'OU_DATA_ENTRY_DISABLED'; end if;

    source_assignment_id := app_security.authorization_source(
        target_ou.id,
        array['admin', 'manager']
    );
    if source_assignment_id is null
       and not app_security.has_permission_on_ou(target_ou.id, array['data_entry']) then
        raise exception 'PERMISSION_DENIED';
    end if;
    if source_assignment_id is null then
        select assignment.id
        into source_assignment_id
        from public.ou_members as assignment
        where assignment.church_id = tenant_id
          and assignment.ou_id = target_ou.id
          and assignment.church_member_id = actor_membership_id
          and assignment.permission = 'data_entry'
          and assignment.is_active
          and assignment.deleted_at is null
        limit 1;
    end if;

    select *
    into target_period
    from public.statistic_periods
    where id = (p_payload ->> 'periodId')::uuid
      and church_id = tenant_id
      and period_type = 'week';
    if target_period.id is null then raise exception 'PERIOD_NOT_FOUND'; end if;
    if target_period.status <> 'open' then raise exception 'PERIOD_LOCKED'; end if;

    select * into tenant from public.churches where id = tenant_id;
    values_snapshot := p_payload -> 'values';
    item_count := jsonb_array_length(values_snapshot);

    if exists (
        select 1
        from (
            select value ->> 'metricId' as metric_id, count(*) as occurrences
            from jsonb_array_elements(values_snapshot) as value
            group by value ->> 'metricId'
        ) as duplicate
        where duplicate.metric_id is null or duplicate.occurrences > 1
    ) then raise exception 'INVALID_METRIC_VALUE'; end if;

    select count(*)
    into valid_count
    from jsonb_to_recordset(values_snapshot) as input(
        "metricId" uuid,
        "numericValue" numeric,
        "textValue" text,
        "booleanValue" boolean
    )
    join public.statistic_metrics as metric
      on metric.id = input."metricId"
     and metric.church_id = tenant_id
     and metric.is_active
     and metric.deleted_at is null
    where num_nonnulls(
            input."numericValue",
            input."textValue",
            input."booleanValue"
        ) = 1
      and (
          (metric.data_type = 'number'
           and input."numericValue" is not null
           and (metric.min_value is null or input."numericValue" >= metric.min_value)
           and (metric.max_value is null or input."numericValue" <= metric.max_value))
          or (metric.data_type = 'text' and input."textValue" is not null)
          or (metric.data_type = 'boolean' and input."booleanValue" is not null)
      );
    if valid_count <> item_count then raise exception 'INVALID_METRIC_VALUE'; end if;

    if exists (
        select 1
        from public.statistic_metrics as required_metric
        where required_metric.church_id = tenant_id
          and required_metric.is_active
          and required_metric.deleted_at is null
          and required_metric.is_required
          and not exists (
              select 1
              from jsonb_array_elements(values_snapshot) as supplied
              where (supplied ->> 'metricId')::uuid = required_metric.id
          )
    ) then raise exception 'REQUIRED_METRIC_MISSING'; end if;

    select *
    into submission
    from public.statistic_submissions
    where church_id = tenant_id
      and period_id = target_period.id
      and ou_id = target_ou.id
      and deleted_at is null
    for update;

    if p_payload ? 'expectedRevision'
       and p_payload -> 'expectedRevision' <> 'null'::jsonb then
        expected_revision := (p_payload ->> 'expectedRevision')::integer;
    end if;

    if submission.id is null then
        if expected_revision is not null then raise exception 'REVISION_CONFLICT'; end if;
        submission.id := gen_random_uuid();
        next_revision := 1;
        insert into public.statistic_submissions (
            id, church_id, period_id, ou_id, status, revision_no,
            remarks, created_at, updated_at
        )
        values (
            submission.id, tenant_id, target_period.id, target_ou.id,
            'draft', next_revision, nullif(trim(p_payload ->> 'remarks'), ''),
            now(), now()
        );
        before_snapshot := null;
    else
        if submission.status = 'approved' then raise exception 'SUBMISSION_ALREADY_APPROVED'; end if;
        if submission.status not in ('draft', 'returned') then
            raise exception 'INVALID_STATUS_TRANSITION';
        end if;
        if expected_revision is null or expected_revision <> submission.revision_no then
            raise exception 'REVISION_CONFLICT';
        end if;
        before_snapshot := jsonb_build_object(
            'status', submission.status,
            'revisionNo', submission.revision_no,
            'remarks', submission.remarks
        );
        next_revision := submission.revision_no + 1;
        update public.statistic_submissions
        set revision_no = next_revision,
            remarks = nullif(trim(p_payload ->> 'remarks'), '')
        where id = submission.id;
    end if;

    delete from public.statistic_values
    where church_id = tenant_id and submission_id = submission.id;
    insert into public.statistic_values (
        church_id, submission_id, metric_id,
        numeric_value, text_value, boolean_value
    )
    select
        tenant_id, submission.id, input."metricId",
        input."numericValue", input."textValue", input."booleanValue"
    from jsonb_to_recordset(values_snapshot) as input(
        "metricId" uuid,
        "numericValue" numeric,
        "textValue" text,
        "booleanValue" boolean
    );

    if p_submit then
        next_status := case
            when tenant.approval_mode = 'auto_approve' then 'approved'
            else 'submitted'
        end;
        update public.statistic_submissions
        set status = next_status,
            submitted_by = current_actor_user_id,
            submitted_at = now(),
            approved_by = case when next_status = 'approved' then current_actor_user_id else null end,
            approved_at = case when next_status = 'approved' then now() else null end,
            rejected_by = null,
            rejected_at = null,
            returned_by = null,
            returned_at = null
        where id = submission.id;

        insert into public.approval_logs (
            church_id, submission_id, action, action_by,
            from_status, to_status, is_override
        )
        values (
            tenant_id, submission.id, 'submit', current_actor_user_id,
            coalesce(submission.status, 'draft'), next_status, false
        );
    else
        next_status := coalesce(submission.status, 'draft');
    end if;

    insert into public.submission_revisions (
        church_id, submission_id, revision_no, status,
        remarks, values_snapshot, changed_by
    )
    values (
        tenant_id, submission.id, next_revision, next_status,
        nullif(trim(p_payload ->> 'remarks'), ''),
        values_snapshot, current_actor_user_id
    );

    insert into public.audit_logs (
        church_id, user_id, actor_church_member_id, ou_id,
        source_ou_member_id, entity_type, entity_id, action,
        before_data, after_data, request_id
    )
    values (
        tenant_id, current_actor_user_id, actor_membership_id, target_ou.id,
        source_assignment_id, 'statistic_submissions', submission.id,
        case when p_submit then 'submit' else 'save_draft' end,
        before_snapshot,
        jsonb_build_object(
            'status', next_status,
            'revisionNo', next_revision,
            'remarks', nullif(trim(p_payload ->> 'remarks'), '')
        ),
        request_id
    );

    result := jsonb_build_object(
        'success', true,
        'data', jsonb_build_object(
            'submissionId', submission.id,
            'status', next_status,
            'revisionNo', next_revision
        )
    );
    update public.api_idempotency_keys as idempotency
    set response_body = result, response_status = 200
    where idempotency.church_id = tenant_id
      and idempotency.actor_user_id = current_actor_user_id
      and idempotency.operation = case when p_submit then 'submit_statistics' else 'save_statistics_draft' end
      and idempotency.client_request_id = request_id;
    return result;
end;
$$;

create or replace function public.save_statistics_draft(p_payload jsonb)
returns jsonb
language sql
security definer
set search_path = ''
as $$
    select app_security.process_statistics_payload(p_payload, false);
$$;

create or replace function public.submit_statistics(p_payload jsonb)
returns jsonb
language sql
security definer
set search_path = ''
as $$
    select app_security.process_statistics_payload(p_payload, true);
$$;

create or replace function public.get_submission_detail(p_submission_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
    ignored_user_id uuid := app_security.require_current_user_id();
    submission public.statistic_submissions%rowtype;
    values_data jsonb;
begin
    select *
    into submission
    from public.statistic_submissions
    where id = p_submission_id
      and church_id = app_security.current_church_id()
      and deleted_at is null;
    if submission.id is null or not app_security.can_view_ou(submission.ou_id) then
        raise exception 'SUBMISSION_NOT_FOUND';
    end if;

    select coalesce(
        jsonb_agg(
            jsonb_build_object(
                'metricId', metric.id,
                'metricCode', metric.code,
                'metricName', metric.name,
                'dataType', metric.data_type,
                'numericValue', value.numeric_value,
                'textValue', value.text_value,
                'booleanValue', value.boolean_value
            )
            order by metric.sort_order, metric.name
        ),
        '[]'::jsonb
    )
    into values_data
    from public.statistic_values as value
    join public.statistic_metrics as metric
      on metric.church_id = value.church_id
     and metric.id = value.metric_id
    where value.church_id = submission.church_id
      and value.submission_id = submission.id;

    return jsonb_build_object(
        'success', true,
        'data', jsonb_build_object(
            'submission', jsonb_build_object(
                'id', submission.id,
                'churchId', submission.church_id,
                'periodId', submission.period_id,
                'ouId', submission.ou_id,
                'status', submission.status,
                'remarks', submission.remarks,
                'revisionNo', submission.revision_no,
                'submittedBy', submission.submitted_by,
                'submittedAt', submission.submitted_at,
                'approvedBy', submission.approved_by,
                'approvedAt', submission.approved_at
            ),
            'values', values_data
        )
    );
end;
$$;

revoke all on function app_security.process_statistics_payload(jsonb, boolean) from public;
revoke all on function public.save_statistics_draft(jsonb) from public;
revoke all on function public.submit_statistics(jsonb) from public;
revoke all on function public.get_submission_detail(uuid) from public;
grant execute on function public.save_statistics_draft(jsonb) to authenticated;
grant execute on function public.submit_statistics(jsonb) to authenticated;
grant execute on function public.get_submission_detail(uuid) to authenticated;
