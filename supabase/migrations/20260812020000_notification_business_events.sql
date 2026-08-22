-- Notifications Stage C (NT-007 and NT-008): transactional business events.
--
-- Business RPC wrappers enable a transaction-local context before invoking the
-- previously deployed implementation. Table triggers only emit while that
-- context is enabled, so seed/fixture maintenance and direct owner writes do
-- not manufacture user-facing events.

create or replace function app_security.notification_event_context_enabled()
returns boolean
language sql
stable
set search_path = ''
as $$
  select coalesce(current_setting('app.notification_event_context', true), '') = 'stage_c';
$$;

create or replace function app_security.enqueue_submission_status_event()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  recipient record;
  target_ou public.organization_units%rowtype;
  target_period public.statistic_periods%rowtype;
  event_name text;
  event_key text;
  event_title text;
  event_body text;
  event_link text;
  recipient_user_id uuid;
begin
  if not app_security.notification_event_context_enabled()
     or new.status is not distinct from old.status then
    return new;
  end if;

  select * into target_ou
  from public.organization_units
  where church_id = new.church_id and id = new.ou_id;

  select * into target_period
  from public.statistic_periods
  where church_id = new.church_id and id = new.period_id;

  if new.status = 'submitted' then
    event_name := 'submission_submitted';
    event_key := format('submission:%s:revision:%s:submitted', new.id, new.revision_no);
    event_title := 'มีรายงานรออนุมัติ';
    event_body := format('%s ส่งรายงาน %s แล้ว', target_ou.name, target_period.label);
    event_link := format('/app/approval?submissionId=%s', new.id);

    for recipient in
      select distinct membership.user_id
      from public.organization_units assigned
      join public.ou_members assignment
        on assignment.church_id = assigned.church_id
       and assignment.ou_id = assigned.id
       and assignment.permission in ('admin', 'manager', 'approver')
       and assignment.is_active and assignment.deleted_at is null
      join public.church_members membership
        on membership.church_id = assignment.church_id
       and membership.id = assignment.church_member_id
       and membership.status = 'active'
      join public.users app_user
        on app_user.id = membership.user_id
       and app_user.is_active and app_user.deleted_at is null
      where assigned.church_id = new.church_id
        and assigned.structure_root_id = target_ou.structure_root_id
        and assigned.is_active and assigned.deleted_at is null
        and (target_ou.path = assigned.path or target_ou.path like assigned.path || '/%')
    loop
      perform app_security.enqueue_notification(
        new.church_id, recipient.user_id, event_name, event_key,
        event_title, event_body, new.ou_id, event_link,
        jsonb_build_object(
          'submissionId', new.id,
          'periodId', new.period_id,
          'ouId', new.ou_id,
          'revisionNo', new.revision_no
        ),
        true
      );
    end loop;

    return new;
  end if;

  if new.status = 'approved' then
    event_name := 'submission_approved';
    recipient_user_id := new.submitted_by;
    event_title := 'รายงานได้รับการอนุมัติ';
    event_body := format('รายงาน %s ของ %s ได้รับการอนุมัติแล้ว', target_period.label, target_ou.name);
    event_link := format('/app/submissions?submissionId=%s', new.id);
  elsif new.status = 'returned' and old.status = 'edit_requested' then
    event_name := 'edit_request_resolved';
    recipient_user_id := old.edit_requested_by;
    event_title := 'คำขอแก้ไขได้รับการอนุมัติ';
    event_body := format('คุณสามารถแก้ไขรายงาน %s ของ %s ได้แล้ว', target_period.label, target_ou.name);
    event_link := format('/app/submissions?submissionId=%s', new.id);
  elsif new.status = 'returned' then
    event_name := 'submission_returned';
    recipient_user_id := new.submitted_by;
    event_title := 'รายงานถูกส่งกลับให้แก้ไข';
    event_body := format('กรุณาตรวจสอบและแก้ไขรายงาน %s ของ %s', target_period.label, target_ou.name);
    event_link := format('/app/submissions?submissionId=%s', new.id);
  elsif new.status = 'edit_requested' then
    event_name := 'edit_request_created';
    event_title := 'มีคำขอแก้ไขรายงาน';
    event_body := format('%s ขอแก้ไขรายงาน %s', target_ou.name, target_period.label);
    event_link := format('/app/approval?status=edit_requested&submissionId=%s', new.id);

    -- This mirrors edit_request_actor_context(): managers and administrators
    -- assigned at the target OU or an ancestor are the users who can act.
    for recipient in
      select distinct membership.user_id
      from public.organization_units assigned
      join public.ou_members assignment
        on assignment.church_id = assigned.church_id
       and assignment.ou_id = assigned.id
       and assignment.permission in ('admin', 'manager')
       and assignment.is_active and assignment.deleted_at is null
      join public.church_members membership
        on membership.church_id = assignment.church_id
       and membership.id = assignment.church_member_id
       and membership.status = 'active'
      join public.users app_user
        on app_user.id = membership.user_id
       and app_user.is_active and app_user.deleted_at is null
      where assigned.church_id = new.church_id
        and assigned.structure_root_id = target_ou.structure_root_id
        and assigned.is_active and assigned.deleted_at is null
        and (target_ou.path = assigned.path or target_ou.path like assigned.path || '/%')
    loop
      perform app_security.enqueue_notification(
        new.church_id, recipient.user_id, event_name,
        format('submission:%s:revision:%s:edit-request-created', new.id, new.revision_no),
        event_title, event_body, new.ou_id, event_link,
        jsonb_build_object(
          'submissionId', new.id,
          'periodId', new.period_id,
          'ouId', new.ou_id,
          'revisionNo', new.revision_no
        ),
        true
      );
    end loop;

    return new;
  else
    return new;
  end if;

  if recipient_user_id is null then
    return new;
  end if;

  event_key := format(
    'submission:%s:revision:%s:%s',
    new.id,
    new.revision_no,
    replace(event_name, '_', '-')
  );

  perform app_security.enqueue_notification(
    new.church_id, recipient_user_id, event_name, event_key,
    event_title, event_body, new.ou_id, event_link,
    jsonb_build_object(
      'submissionId', new.id,
      'periodId', new.period_id,
      'ouId', new.ou_id,
      'revisionNo', new.revision_no
    ),
    true
  );

  return new;
end;
$$;

create trigger trg_enqueue_submission_status_event
after update of status on public.statistic_submissions
for each row execute function app_security.enqueue_submission_status_event();

create or replace function app_security.refresh_reactivated_assignment_time()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if app_security.notification_event_context_enabled()
     and not old.is_active and new.is_active then
    new.assigned_at := now();
  end if;
  return new;
end;
$$;

create trigger trg_refresh_reactivated_assignment_time
before update of is_active on public.ou_members
for each row execute function app_security.refresh_reactivated_assignment_time();

create or replace function app_security.enqueue_ou_assignment_event()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  recipient_user_id uuid;
  target_ou_name text;
begin
  if not app_security.notification_event_context_enabled()
     or not new.is_active
     or new.deleted_at is not null
     or (tg_op = 'UPDATE' and old.is_active and old.deleted_at is null) then
    return new;
  end if;

  select membership.user_id, target_ou.name
  into recipient_user_id, target_ou_name
  from public.church_members membership
  join public.users app_user
    on app_user.id = membership.user_id
   and app_user.is_active and app_user.deleted_at is null
  join public.organization_units target_ou
    on target_ou.church_id = new.church_id
   and target_ou.id = new.ou_id
   and target_ou.is_active and target_ou.deleted_at is null
  where membership.church_id = new.church_id
    and membership.id = new.church_member_id
    and membership.status = 'active';

  if recipient_user_id is null then
    return new;
  end if;

  perform app_security.enqueue_notification(
    new.church_id,
    recipient_user_id,
    'ou_assignment_created',
    format('ou-assignment:%s:%s', new.id, extract(epoch from new.assigned_at)::numeric::text),
    'คุณได้รับสิทธิ์ใหม่',
    format('คุณได้รับสิทธิ์ %s ใน %s', new.permission, target_ou_name),
    new.ou_id,
    format('/app/organization?ouId=%s', new.ou_id),
    jsonb_build_object(
      'assignmentId', new.id,
      'ouId', new.ou_id,
      'permission', new.permission
    ),
    true
  );

  return new;
end;
$$;

create trigger trg_enqueue_ou_assignment_event
after insert or update of is_active on public.ou_members
for each row execute function app_security.enqueue_ou_assignment_event();

-- Move the deployed implementations behind internal-only names. Public
-- wrappers retain the API signatures and grants while enabling the trigger
-- context only for the duration of the business mutation.
alter function public.submit_statistics(jsonb) set schema app_security;
alter function app_security.submit_statistics(jsonb) rename to submit_statistics_without_notification_events;
alter function public.approve_submission(jsonb) set schema app_security;
alter function app_security.approve_submission(jsonb) rename to approve_submission_without_notification_events;
alter function public.return_submission_for_edit(jsonb) set schema app_security;
alter function app_security.return_submission_for_edit(jsonb) rename to return_submission_without_notification_events;
alter function public.request_submission_edit(jsonb) set schema app_security;
alter function app_security.request_submission_edit(jsonb) rename to request_submission_edit_without_notification_events;
alter function public.approve_submission_edit_request(jsonb) set schema app_security;
alter function app_security.approve_submission_edit_request(jsonb) rename to approve_edit_request_without_notification_events;
alter function public.assign_ou_member(jsonb) set schema app_security;
alter function app_security.assign_ou_member(jsonb) rename to assign_ou_member_without_notification_events;
alter function public.accept_tenant_invitations_for_user(uuid, text) set schema app_security;
alter function app_security.accept_tenant_invitations_for_user(uuid, text) rename to accept_invitations_without_notification_events;
alter function public.accept_tenant_invitation_by_token(uuid, text) set schema app_security;
alter function app_security.accept_tenant_invitation_by_token(uuid, text) rename to accept_invitation_by_token_without_notification_events;

create or replace function public.submit_statistics(p_payload jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare prior_context text := current_setting('app.notification_event_context', true); result jsonb;
begin
  perform set_config('app.notification_event_context', 'stage_c', true);
  result := app_security.submit_statistics_without_notification_events(p_payload);
  perform set_config('app.notification_event_context', coalesce(prior_context, ''), true);
  return result;
end;
$$;

create or replace function public.approve_submission(p_payload jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare prior_context text := current_setting('app.notification_event_context', true); result jsonb;
begin
  perform set_config('app.notification_event_context', 'stage_c', true);
  result := app_security.approve_submission_without_notification_events(p_payload);
  perform set_config('app.notification_event_context', coalesce(prior_context, ''), true);
  return result;
end;
$$;

create or replace function public.return_submission_for_edit(p_payload jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare prior_context text := current_setting('app.notification_event_context', true); result jsonb;
begin
  perform set_config('app.notification_event_context', 'stage_c', true);
  result := app_security.return_submission_without_notification_events(p_payload);
  perform set_config('app.notification_event_context', coalesce(prior_context, ''), true);
  return result;
end;
$$;

create or replace function public.request_submission_edit(p_payload jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare prior_context text := current_setting('app.notification_event_context', true); result jsonb;
begin
  perform set_config('app.notification_event_context', 'stage_c', true);
  result := app_security.request_submission_edit_without_notification_events(p_payload);
  perform set_config('app.notification_event_context', coalesce(prior_context, ''), true);
  return result;
end;
$$;

create or replace function public.approve_submission_edit_request(p_payload jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare prior_context text := current_setting('app.notification_event_context', true); result jsonb;
begin
  perform set_config('app.notification_event_context', 'stage_c', true);
  result := app_security.approve_edit_request_without_notification_events(p_payload);
  perform set_config('app.notification_event_context', coalesce(prior_context, ''), true);
  return result;
end;
$$;

create or replace function public.assign_ou_member(p_payload jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare prior_context text := current_setting('app.notification_event_context', true); result jsonb;
begin
  perform set_config('app.notification_event_context', 'stage_c', true);
  result := app_security.assign_ou_member_without_notification_events(p_payload);
  perform set_config('app.notification_event_context', coalesce(prior_context, ''), true);
  return result;
end;
$$;

create or replace function public.accept_tenant_invitations_for_user(p_user_id uuid, p_verified_email text)
returns integer language plpgsql security definer set search_path = '' as $$
declare prior_context text := current_setting('app.notification_event_context', true); result integer;
begin
  perform set_config('app.notification_event_context', 'stage_c', true);
  result := app_security.accept_invitations_without_notification_events(p_user_id, p_verified_email);
  perform set_config('app.notification_event_context', coalesce(prior_context, ''), true);
  return result;
end;
$$;

create or replace function public.accept_tenant_invitation_by_token(p_user_id uuid, p_raw_token text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare prior_context text := current_setting('app.notification_event_context', true); result jsonb;
begin
  perform set_config('app.notification_event_context', 'stage_c', true);
  result := app_security.accept_invitation_by_token_without_notification_events(p_user_id, p_raw_token);
  perform set_config('app.notification_event_context', coalesce(prior_context, ''), true);
  return result;
end;
$$;

revoke all on function app_security.notification_event_context_enabled() from public;
revoke all on function app_security.enqueue_submission_status_event() from public;
revoke all on function app_security.refresh_reactivated_assignment_time() from public;
revoke all on function app_security.enqueue_ou_assignment_event() from public;
revoke all on function app_security.submit_statistics_without_notification_events(jsonb) from public, anon, authenticated, service_role;
revoke all on function app_security.approve_submission_without_notification_events(jsonb) from public, anon, authenticated, service_role;
revoke all on function app_security.return_submission_without_notification_events(jsonb) from public, anon, authenticated, service_role;
revoke all on function app_security.request_submission_edit_without_notification_events(jsonb) from public, anon, authenticated, service_role;
revoke all on function app_security.approve_edit_request_without_notification_events(jsonb) from public, anon, authenticated, service_role;
revoke all on function app_security.assign_ou_member_without_notification_events(jsonb) from public, anon, authenticated, service_role;
revoke all on function app_security.accept_invitations_without_notification_events(uuid, text) from public, anon, authenticated, service_role;
revoke all on function app_security.accept_invitation_by_token_without_notification_events(uuid, text) from public, anon, authenticated, service_role;

revoke all on function public.submit_statistics(jsonb) from public;
revoke all on function public.approve_submission(jsonb) from public;
revoke all on function public.return_submission_for_edit(jsonb) from public;
revoke all on function public.request_submission_edit(jsonb) from public;
revoke all on function public.approve_submission_edit_request(jsonb) from public;
revoke all on function public.assign_ou_member(jsonb) from public;
revoke all on function public.accept_tenant_invitations_for_user(uuid, text) from public;
revoke all on function public.accept_tenant_invitation_by_token(uuid, text) from public;

grant execute on function public.submit_statistics(jsonb) to authenticated;
grant execute on function public.approve_submission(jsonb) to authenticated;
grant execute on function public.return_submission_for_edit(jsonb) to authenticated;
grant execute on function public.request_submission_edit(jsonb) to authenticated;
grant execute on function public.approve_submission_edit_request(jsonb) to authenticated;
grant execute on function public.assign_ou_member(jsonb) to authenticated;
grant execute on function public.accept_tenant_invitations_for_user(uuid, text) to service_role;
grant execute on function public.accept_tenant_invitation_by_token(uuid, text) to service_role;
