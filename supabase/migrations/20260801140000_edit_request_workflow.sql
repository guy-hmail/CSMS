-- Allow submitters to request an edit while keeping the submission locked until
-- a manager or administrator approves the request.

alter table public.statistic_submissions
    add column edit_requested_by uuid references public.users(id),
    add column edit_requested_at timestamptz,
    add column edit_request_reason text;

alter table public.statistic_submissions
    drop constraint ck_submission_status,
    drop constraint ck_submission_status_timestamps;

alter table public.statistic_submissions
    add constraint ck_submission_status
        check (status in ('draft', 'submitted', 'approved', 'rejected', 'edit_requested', 'returned')),
    add constraint ck_submission_edit_request_actor check (
        (edit_requested_by is null) = (edit_requested_at is null)
    ),
    add constraint ck_submission_status_timestamps check (
        (status = 'draft' and submitted_at is null and approved_at is null and rejected_at is null and returned_at is null)
        or (status = 'submitted' and submitted_at is not null and approved_at is null and rejected_at is null and returned_at is null)
        or (status = 'approved' and submitted_at is not null and approved_at is not null and rejected_at is null and returned_at is null)
        or (status = 'rejected' and submitted_at is not null and rejected_at is not null and returned_at is null)
        or (status = 'edit_requested' and submitted_at is not null and rejected_at is null and returned_at is null)
        or (status = 'returned' and submitted_at is not null and returned_at is not null and rejected_at is null)
    );

create or replace function app_security.clear_completed_edit_request()
returns trigger language plpgsql set search_path = '' as $$
begin
    if old.status in ('edit_requested', 'returned') and new.status in ('submitted', 'approved') then
        new.edit_requested_by := null;
        new.edit_requested_at := null;
        new.edit_request_reason := null;
    end if;
    return new;
end;
$$;

create trigger trg_clear_completed_edit_request
before update on public.statistic_submissions
for each row execute function app_security.clear_completed_edit_request();

create or replace function app_security.edit_request_actor_context(p_ou_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
    tenant_id uuid := app_security.current_church_id();
    actor_membership_id uuid := app_security.current_church_member_id();
    source_assignment public.ou_members%rowtype;
begin
    select assignment.* into source_assignment
    from public.organization_units target
    join public.organization_units assigned
      on assigned.church_id = target.church_id
     and assigned.structure_root_id = target.structure_root_id
     and (target.path = assigned.path or target.path like assigned.path || '/%')
    join public.ou_members assignment
      on assignment.church_id = assigned.church_id and assignment.ou_id = assigned.id
    where target.id = p_ou_id and target.church_id = tenant_id
      and target.is_active and target.deleted_at is null
      and assigned.is_active and assigned.deleted_at is null
      and assignment.church_member_id = actor_membership_id
      and assignment.permission in ('admin', 'manager')
      and assignment.is_active and assignment.deleted_at is null
    order by assigned.level desc,
      case assignment.permission when 'admin' then 0 else 1 end,
      assignment.assigned_at desc
    limit 1;

    return jsonb_build_object(
      'canAct', source_assignment.id is not null,
      'sourceAssignmentId', source_assignment.id,
      'permission', source_assignment.permission
    );
end;
$$;

create or replace function public.request_submission_edit(p_payload jsonb)
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
    request_id uuid := (p_payload ->> 'clientRequestId')::uuid;
    expected_revision integer := (p_payload ->> 'expectedRevision')::integer;
    reason text := nullif(trim(p_payload ->> 'reason'), '');
    source_assignment_id uuid;
    result jsonb;
begin
    if request_id is null then raise exception 'CLIENT_REQUEST_ID_REQUIRED'; end if;
    if expected_revision is null then raise exception 'EXPECTED_REVISION_REQUIRED'; end if;
    if reason is null then raise exception 'REASON_REQUIRED'; end if;

    select * into submission
    from public.statistic_submissions
    where id = (p_payload ->> 'submissionId')::uuid
      and church_id = tenant_id and deleted_at is null
    for update;
    if submission.id is null then raise exception 'SUBMISSION_NOT_FOUND'; end if;
    if submission.revision_no <> expected_revision then raise exception 'REVISION_CONFLICT'; end if;
    if submission.status not in ('submitted', 'approved') then raise exception 'INVALID_STATUS_TRANSITION'; end if;
    if not app_security.can_submit_for_ou(submission.ou_id) then raise exception 'PERMISSION_DENIED'; end if;

    select assignment.id into source_assignment_id
    from public.ou_members assignment
    join public.organization_units assigned on assigned.id = assignment.ou_id and assigned.church_id = assignment.church_id
    join public.organization_units target on target.id = submission.ou_id and target.church_id = assigned.church_id
    where assignment.church_member_id = actor_membership_id
      and assignment.is_active and assignment.deleted_at is null
      and assignment.permission in ('admin', 'manager', 'data_entry')
      and (target.path = assigned.path or target.path like assigned.path || '/%')
    order by assigned.level desc limit 1;

    update public.statistic_submissions
    set status = 'edit_requested', edit_requested_by = current_actor_user_id,
        edit_requested_at = now(), edit_request_reason = reason, updated_at = now()
    where id = submission.id;

    insert into public.approval_logs(church_id, submission_id, action, action_by, from_status, to_status, reason)
    values (tenant_id, submission.id, 'request_edit', current_actor_user_id, submission.status, 'edit_requested', reason);
    insert into public.audit_logs(church_id, user_id, actor_church_member_id, ou_id, source_ou_member_id,
      entity_type, entity_id, action, before_data, after_data, metadata, request_id)
    values (tenant_id, current_actor_user_id, actor_membership_id, submission.ou_id, source_assignment_id,
      'statistic_submissions', submission.id, 'request_edit',
      jsonb_build_object('status', submission.status, 'revisionNo', submission.revision_no),
      jsonb_build_object('status', 'edit_requested', 'revisionNo', submission.revision_no),
      jsonb_build_object('reason', reason), request_id);

    result := jsonb_build_object('success', true, 'data', jsonb_build_object(
      'submissionId', submission.id, 'status', 'edit_requested', 'revisionNo', submission.revision_no
    ));
    return result;
end;
$$;

create or replace function public.approve_submission_edit_request(p_payload jsonb)
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
    note text := nullif(trim(p_payload ->> 'reason'), '');
begin
    if request_id is null then raise exception 'CLIENT_REQUEST_ID_REQUIRED'; end if;
    if expected_revision is null then raise exception 'EXPECTED_REVISION_REQUIRED'; end if;
    select * into submission from public.statistic_submissions
    where id = (p_payload ->> 'submissionId')::uuid and church_id = tenant_id and deleted_at is null
    for update;
    if submission.id is null then raise exception 'SUBMISSION_NOT_FOUND'; end if;
    if submission.revision_no <> expected_revision then raise exception 'REVISION_CONFLICT'; end if;
    if submission.status <> 'edit_requested' then raise exception 'INVALID_STATUS_TRANSITION'; end if;
    actor_context := app_security.edit_request_actor_context(submission.ou_id);
    if not coalesce((actor_context ->> 'canAct')::boolean, false) then raise exception 'PERMISSION_DENIED'; end if;

    update public.statistic_submissions
    set status = 'returned', approval_note = coalesce(note, edit_request_reason),
        approved_by = null, approved_at = null, rejected_by = null, rejected_at = null,
        returned_by = current_actor_user_id, returned_at = now(), updated_at = now()
    where id = submission.id;
    insert into public.approval_logs(church_id, submission_id, action, action_by, from_status, to_status, reason)
    values (tenant_id, submission.id, 'approve_edit_request', current_actor_user_id, 'edit_requested', 'returned', note);
    insert into public.audit_logs(church_id, user_id, actor_church_member_id, ou_id, source_ou_member_id,
      entity_type, entity_id, action, before_data, after_data, metadata, request_id)
    values (tenant_id, current_actor_user_id, actor_membership_id, submission.ou_id,
      (actor_context ->> 'sourceAssignmentId')::uuid, 'statistic_submissions', submission.id,
      'approve_edit_request', jsonb_build_object('status', 'edit_requested', 'revisionNo', submission.revision_no),
      jsonb_build_object('status', 'returned', 'revisionNo', submission.revision_no),
      jsonb_build_object('requestReason', submission.edit_request_reason, 'note', note), request_id);
    return jsonb_build_object('success', true, 'data', jsonb_build_object(
      'submissionId', submission.id, 'status', 'returned', 'revisionNo', submission.revision_no
    ));
end;
$$;

-- Approval queue reads use the normal approver context, except edit requests,
-- which are intentionally routed to managers and administrators.
create or replace function public.list_pending_submissions(
    p_period_id uuid default null, p_ou_id uuid default null, p_status text default 'submitted'
)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
    ignored_user_id uuid := app_security.require_current_user_id();
    tenant_id uuid := app_security.current_church_id();
    tenant_mode text; items_data jsonb; periods_data jsonb; ous_data jsonb;
    filter_ou public.organization_units%rowtype;
begin
    if p_status is not null and p_status not in ('submitted','approved','rejected','edit_requested','returned') then raise exception 'INVALID_STATUS_FILTER'; end if;
    if p_period_id is not null and not exists (select 1 from public.statistic_periods where id=p_period_id and church_id=tenant_id) then raise exception 'PERIOD_NOT_FOUND'; end if;
    if p_ou_id is not null then
      select * into filter_ou from public.organization_units where id=p_ou_id and church_id=tenant_id and is_active and deleted_at is null;
      if filter_ou.id is null or not (
        case when p_status = 'edit_requested' then coalesce((app_security.edit_request_actor_context(filter_ou.id)->>'canAct')::boolean,false)
        else coalesce((app_security.approval_actor_context(filter_ou.id)->>'canAct')::boolean,false) end
      ) then raise exception 'OU_NOT_FOUND'; end if;
    end if;
    select approval_mode into tenant_mode from public.churches where id=tenant_id;
    select coalesce(jsonb_agg(jsonb_build_object(
      'id',submission.id,'status',submission.status,'revisionNo',submission.revision_no,'remarks',submission.remarks,
      'submittedAt',submission.submitted_at,'approvedAt',submission.approved_at,'editRequestReason',submission.edit_request_reason,
      'editRequestedAt',submission.edit_requested_at,'periodId',period.id,'periodLabel',period.label,'periodEnd',period.period_end,
      'ouId',ou.id,'ouName',ou.name,'ouCode',ou.code,'submittedByName',submitter.display_name,
      'metricCount',(select count(*) from public.statistic_values value where value.church_id=tenant_id and value.submission_id=submission.id),
      'isOverride',coalesce((app_security.approval_actor_context(ou.id)->>'isOverride')::boolean,false)
    ) order by coalesce(submission.edit_requested_at,submission.submitted_at) desc nulls last), '[]'::jsonb) into items_data
    from public.statistic_submissions submission
    join public.statistic_periods period on period.church_id=submission.church_id and period.id=submission.period_id
    join public.organization_units ou on ou.church_id=submission.church_id and ou.id=submission.ou_id
    left join public.users submitter on submitter.id=submission.submitted_by
    where submission.church_id=tenant_id and submission.deleted_at is null
      and (p_status is null or submission.status=p_status) and (p_period_id is null or submission.period_id=p_period_id)
      and (p_ou_id is null or ou.path=filter_ou.path or ou.path like filter_ou.path||'/%')
      and (case when submission.status='edit_requested'
        then coalesce((app_security.edit_request_actor_context(ou.id)->>'canAct')::boolean,false)
        else coalesce((app_security.approval_actor_context(ou.id)->>'canAct')::boolean,false) end);
    select coalesce(jsonb_agg(jsonb_build_object('id',id,'label',label,'periodEnd',period_end) order by period_end desc),'[]'::jsonb)
      into periods_data from public.statistic_periods where church_id=tenant_id and period_type='week';
    select coalesce(jsonb_agg(jsonb_build_object('id',ou.id,'name',ou.name,'code',ou.code,'path',ou.path,'level',ou.level) order by ou.path,ou.sort_order,ou.name),'[]'::jsonb)
      into ous_data from public.organization_units ou where ou.church_id=tenant_id and ou.is_active and ou.deleted_at is null
      and (case when p_status='edit_requested' then coalesce((app_security.edit_request_actor_context(ou.id)->>'canAct')::boolean,false)
        else coalesce((app_security.approval_actor_context(ou.id)->>'canAct')::boolean,false) end);
    return jsonb_build_object('success',true,'data',jsonb_build_object('approvalMode',tenant_mode,'items',items_data,'periods',periods_data,'organizationUnits',ous_data));
end; $$;

create or replace function public.get_approval_submission_detail(p_submission_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  ignored_user_id uuid := app_security.require_current_user_id(); tenant_id uuid := app_security.current_church_id();
  submission public.statistic_submissions%rowtype; approval_context jsonb; edit_context jsonb; values_data jsonb; logs_data jsonb;
begin
  select * into submission from public.statistic_submissions where id=p_submission_id and church_id=tenant_id and deleted_at is null;
  if submission.id is null then raise exception 'SUBMISSION_NOT_FOUND'; end if;
  approval_context:=app_security.approval_actor_context(submission.ou_id); edit_context:=app_security.edit_request_actor_context(submission.ou_id);
  if not coalesce((approval_context->>'canAct')::boolean,false)
     and not (submission.status='edit_requested' and coalesce((edit_context->>'canAct')::boolean,false)) then raise exception 'SUBMISSION_NOT_FOUND'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('metricId',metric.id,'metricCode',metric.code,'metricName',metric.name,'unit',metric.unit,
    'dataType',metric.data_type,'numericValue',value.numeric_value,'textValue',value.text_value,'booleanValue',value.boolean_value)
    order by metric.sort_order,metric.name),'[]'::jsonb) into values_data
  from public.statistic_values value join public.statistic_metrics metric on metric.church_id=value.church_id and metric.id=value.metric_id
  where value.church_id=tenant_id and value.submission_id=submission.id;
  select coalesce(jsonb_agg(jsonb_build_object('id',log.id,'action',log.action,'fromStatus',log.from_status,'toStatus',log.to_status,
    'isOverride',log.is_override,'reason',log.reason,'createdAt',log.created_at,'actorName',actor.display_name)
    order by log.created_at desc,log.id desc),'[]'::jsonb) into logs_data
  from public.approval_logs log join public.users actor on actor.id=log.action_by
  where log.church_id=tenant_id and log.submission_id=submission.id;
  return jsonb_build_object('success',true,'data',jsonb_build_object(
    'submission',jsonb_build_object('id',submission.id,'status',submission.status,'revisionNo',submission.revision_no,'remarks',submission.remarks,
      'ouId',submission.ou_id,'periodId',submission.period_id,'submittedAt',submission.submitted_at,'approvedAt',submission.approved_at,
      'approvalNote',submission.approval_note,'editRequestReason',submission.edit_request_reason,'editRequestedAt',submission.edit_requested_at),
    'values',values_data,'history',logs_data,'capabilities',jsonb_build_object(
      'canApprove',submission.status='submitted' and coalesce((approval_context->>'canAct')::boolean,false),
      'canReject',submission.status='submitted' and coalesce((approval_context->>'canAct')::boolean,false),
      'canReturn',submission.status in ('submitted','approved') and coalesce((approval_context->>'canAct')::boolean,false),
      'canApproveEditRequest',submission.status='edit_requested' and coalesce((edit_context->>'canAct')::boolean,false),
      'isOverride',coalesce((approval_context->>'isOverride')::boolean,false))));
end; $$;

create or replace function public.get_pending_edit_request_count()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare ignored_user_id uuid := app_security.require_current_user_id(); tenant_id uuid := app_security.current_church_id(); pending_count integer;
begin
  select count(*) into pending_count from public.statistic_submissions submission
  where submission.church_id=tenant_id and submission.status='edit_requested' and submission.deleted_at is null
    and coalesce((app_security.edit_request_actor_context(submission.ou_id)->>'canAct')::boolean,false);
  return jsonb_build_object('success',true,'data',jsonb_build_object('count',pending_count));
end; $$;

revoke all on function app_security.edit_request_actor_context(uuid) from public;
revoke all on function app_security.clear_completed_edit_request() from public;
revoke all on function public.request_submission_edit(jsonb) from public;
revoke all on function public.approve_submission_edit_request(jsonb) from public;
revoke all on function public.get_pending_edit_request_count() from public;
grant execute on function public.request_submission_edit(jsonb) to authenticated;
grant execute on function public.approve_submission_edit_request(jsonb) to authenticated;
grant execute on function public.get_pending_edit_request_count() to authenticated;
