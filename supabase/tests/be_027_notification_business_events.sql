\set ON_ERROR_STOP on
select '1..1';
begin;

create function pg_temp.assert_true(condition boolean, message text)
returns void language plpgsql as $$
begin
  if condition is not true then raise exception 'BE-027 assertion: %', message; end if;
end;
$$;

insert into public.churches(id, code, slug, name, status, approval_mode)
values ('c1000000-0000-4000-8000-000000000001', 'NTC', 'notification-stage-c', 'Notification Stage C', 'active', 'approval_required');

insert into public.users(id, auth_user_id, line_user_id, display_name)
values
  ('c2000000-0000-4000-8000-000000000001', 'c3000000-0000-4000-8000-000000000001', 'stage-c-entry', 'Stage C Entry'),
  ('c2000000-0000-4000-8000-000000000002', 'c3000000-0000-4000-8000-000000000002', 'stage-c-approver', 'Stage C Approver'),
  ('c2000000-0000-4000-8000-000000000003', 'c3000000-0000-4000-8000-000000000003', 'stage-c-manager', 'Stage C Manager'),
  ('c2000000-0000-4000-8000-000000000004', 'c3000000-0000-4000-8000-000000000004', 'stage-c-sibling', 'Stage C Sibling'),
  ('c2000000-0000-4000-8000-000000000005', 'c3000000-0000-4000-8000-000000000005', 'stage-c-target', 'Stage C Target'),
  ('c2000000-0000-4000-8000-000000000006', 'c3000000-0000-4000-8000-000000000006', 'stage-c-invitee', 'Stage C Invitee');

insert into public.church_members(id, church_id, user_id, status)
values
  ('c4000000-0000-4000-8000-000000000001', 'c1000000-0000-4000-8000-000000000001', 'c2000000-0000-4000-8000-000000000001', 'active'),
  ('c4000000-0000-4000-8000-000000000002', 'c1000000-0000-4000-8000-000000000001', 'c2000000-0000-4000-8000-000000000002', 'active'),
  ('c4000000-0000-4000-8000-000000000003', 'c1000000-0000-4000-8000-000000000001', 'c2000000-0000-4000-8000-000000000003', 'active'),
  ('c4000000-0000-4000-8000-000000000004', 'c1000000-0000-4000-8000-000000000001', 'c2000000-0000-4000-8000-000000000004', 'active'),
  ('c4000000-0000-4000-8000-000000000005', 'c1000000-0000-4000-8000-000000000001', 'c2000000-0000-4000-8000-000000000005', 'active');

insert into public.organization_unit_types(id, church_id, code, name)
values ('c5000000-0000-4000-8000-000000000001', 'c1000000-0000-4000-8000-000000000001', 'GROUP', 'Group');

insert into public.organization_units(
  id, church_id, structure_root_id, parent_id, ou_type_id,
  code, name, path, level, allow_data_entry
)
values
  ('c6000000-0000-4000-8000-000000000001', 'c1000000-0000-4000-8000-000000000001', 'c6000000-0000-4000-8000-000000000001', null, 'c5000000-0000-4000-8000-000000000001', 'ROOT', 'Root', '/root', 1, false),
  ('c6000000-0000-4000-8000-000000000002', 'c1000000-0000-4000-8000-000000000001', 'c6000000-0000-4000-8000-000000000001', 'c6000000-0000-4000-8000-000000000001', 'c5000000-0000-4000-8000-000000000001', 'GROUP-A', 'Group A', '/root/group-a', 2, true),
  ('c6000000-0000-4000-8000-000000000003', 'c1000000-0000-4000-8000-000000000001', 'c6000000-0000-4000-8000-000000000001', 'c6000000-0000-4000-8000-000000000001', 'c5000000-0000-4000-8000-000000000001', 'GROUP-B', 'Group B', '/root/group-b', 2, true);

-- Fixture assignments are direct owner writes and must not emit notifications.
insert into public.ou_members(id, church_id, ou_id, church_member_id, permission)
values
  ('c7000000-0000-4000-8000-000000000001', 'c1000000-0000-4000-8000-000000000001', 'c6000000-0000-4000-8000-000000000002', 'c4000000-0000-4000-8000-000000000001', 'data_entry'),
  ('c7000000-0000-4000-8000-000000000002', 'c1000000-0000-4000-8000-000000000001', 'c6000000-0000-4000-8000-000000000002', 'c4000000-0000-4000-8000-000000000002', 'approver'),
  ('c7000000-0000-4000-8000-000000000003', 'c1000000-0000-4000-8000-000000000001', 'c6000000-0000-4000-8000-000000000001', 'c4000000-0000-4000-8000-000000000003', 'manager'),
  ('c7000000-0000-4000-8000-000000000004', 'c1000000-0000-4000-8000-000000000001', 'c6000000-0000-4000-8000-000000000003', 'c4000000-0000-4000-8000-000000000004', 'approver');

insert into public.user_preferences(
  church_id, church_member_id, notify_missing, notify_submitted, notify_approval
)
values
  ('c1000000-0000-4000-8000-000000000001', 'c4000000-0000-4000-8000-000000000001', true, true, false),
  ('c1000000-0000-4000-8000-000000000001', 'c4000000-0000-4000-8000-000000000002', true, false, true),
  ('c1000000-0000-4000-8000-000000000001', 'c4000000-0000-4000-8000-000000000003', true, true, true);

insert into public.statistic_periods(id, church_id, year, week_no, period_start, period_end, label)
values ('c8000000-0000-4000-8000-000000000001', 'c1000000-0000-4000-8000-000000000001', 2026, 31, '2026-07-27', '2026-08-02', '2026-W31');

insert into public.statistic_metrics(id, church_id, code, name, category, unit, min_value, is_required)
values ('c9000000-0000-4000-8000-000000000001', 'c1000000-0000-4000-8000-000000000001', 'ATT', 'Attendance', 'test', 'person', 0, true);

select pg_temp.assert_true(
  (select count(*) = 0 from public.notifications where church_id = 'c1000000-0000-4000-8000-000000000001'),
  'direct fixture writes do not emit business notifications'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', 'c3000000-0000-4000-8000-000000000001', true);
select set_config('request.jwt.claims', '{"sub":"c3000000-0000-4000-8000-000000000001","app_metadata":{"active_church_id":"c1000000-0000-4000-8000-000000000001"}}', true);
create temporary table stage_c_submit as
select public.submit_statistics(jsonb_build_object(
  'clientRequestId', 'ca000000-0000-4000-8000-000000000001',
  'expectedRevision', null,
  'ouId', 'c6000000-0000-4000-8000-000000000002',
  'periodId', 'c8000000-0000-4000-8000-000000000001',
  'values', jsonb_build_array(jsonb_build_object(
    'metricId', 'c9000000-0000-4000-8000-000000000001',
    'numericValue', 42, 'textValue', null, 'booleanValue', null
  ))
)) response;

select pg_temp.assert_true(
  public.submit_statistics(jsonb_build_object(
    'clientRequestId', 'ca000000-0000-4000-8000-000000000001',
    'expectedRevision', null,
    'ouId', 'c6000000-0000-4000-8000-000000000002',
    'periodId', 'c8000000-0000-4000-8000-000000000001',
    'values', jsonb_build_array(jsonb_build_object(
      'metricId', 'c9000000-0000-4000-8000-000000000001',
      'numericValue', 42, 'textValue', null, 'booleanValue', null
    ))
  )) = (select response from stage_c_submit),
  'idempotent business replay returns the original result'
);

reset role;
select pg_temp.assert_true(
  (select count(*) = 2 from public.notifications
   where church_id = 'c1000000-0000-4000-8000-000000000001'
     and event_type = 'submission_submitted'),
  'submitted event selects manager and approver in the OU ancestry once'
);
select pg_temp.assert_true(
  (select count(*) = 0 from public.notifications
   where recipient_user_id = 'c2000000-0000-4000-8000-000000000004'),
  'sibling-OU recipient is excluded'
);
select pg_temp.assert_true(
  (select count(*) = 1 from public.notification_deliveries delivery
   join public.notifications notification on notification.id = delivery.notification_id
   where notification.event_type = 'submission_submitted'
     and notification.church_id = 'c1000000-0000-4000-8000-000000000001'),
  'notify_submitted suppresses only the opted-out optional LINE delivery'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', 'c3000000-0000-4000-8000-000000000002', true);
select set_config('request.jwt.claims', '{"sub":"c3000000-0000-4000-8000-000000000002","app_metadata":{"active_church_id":"c1000000-0000-4000-8000-000000000001"}}', true);
select public.approve_submission(jsonb_build_object(
  'submissionId', ((select response #>> '{data,submissionId}' from stage_c_submit))::uuid,
  'expectedRevision', 1,
  'clientRequestId', 'ca000000-0000-4000-8000-000000000002',
  'reason', 'Checked'
));
select public.approve_submission(jsonb_build_object(
  'submissionId', ((select response #>> '{data,submissionId}' from stage_c_submit))::uuid,
  'expectedRevision', 1,
  'clientRequestId', 'ca000000-0000-4000-8000-000000000002',
  'reason', 'Checked'
));

reset role;
select pg_temp.assert_true(
  (select count(*) = 1 from public.notifications
   where event_type = 'submission_approved'
     and recipient_user_id = 'c2000000-0000-4000-8000-000000000001'),
  'approval notifies the server-resolved submitter'
);
select pg_temp.assert_true(
  (select count(*) = 0 from public.notification_deliveries delivery
   join public.notifications notification on notification.id = delivery.notification_id
   where notification.event_type = 'submission_approved'),
  'notify_approval opt-out keeps in-app notification but suppresses LINE outbox'
);

update public.user_preferences
set notify_approval = true
where church_id = 'c1000000-0000-4000-8000-000000000001'
  and church_member_id = 'c4000000-0000-4000-8000-000000000001';

set local role authenticated;
select set_config('request.jwt.claim.sub', 'c3000000-0000-4000-8000-000000000002', true);
select set_config('request.jwt.claims', '{"sub":"c3000000-0000-4000-8000-000000000002","app_metadata":{"active_church_id":"c1000000-0000-4000-8000-000000000001"}}', true);
select public.return_submission_for_edit(jsonb_build_object(
  'submissionId', ((select response #>> '{data,submissionId}' from stage_c_submit))::uuid,
  'expectedRevision', 1,
  'clientRequestId', 'ca000000-0000-4000-8000-000000000003',
  'reason', 'Please correct'
));

select set_config('request.jwt.claim.sub', 'c3000000-0000-4000-8000-000000000001', true);
select set_config('request.jwt.claims', '{"sub":"c3000000-0000-4000-8000-000000000001","app_metadata":{"active_church_id":"c1000000-0000-4000-8000-000000000001"}}', true);
select public.submit_statistics(jsonb_build_object(
  'clientRequestId', 'ca000000-0000-4000-8000-000000000004',
  'expectedRevision', 1,
  'ouId', 'c6000000-0000-4000-8000-000000000002',
  'periodId', 'c8000000-0000-4000-8000-000000000001',
  'values', jsonb_build_array(jsonb_build_object(
    'metricId', 'c9000000-0000-4000-8000-000000000001',
    'numericValue', 43, 'textValue', null, 'booleanValue', null
  ))
));
select public.request_submission_edit(jsonb_build_object(
  'submissionId', ((select response #>> '{data,submissionId}' from stage_c_submit))::uuid,
  'expectedRevision', 2,
  'clientRequestId', 'ca000000-0000-4000-8000-000000000005',
  'reason', 'Need another correction'
));

reset role;
select pg_temp.assert_true(
  (select count(*) = 1 from public.notifications
   where event_type = 'submission_returned'
     and recipient_user_id = 'c2000000-0000-4000-8000-000000000001'),
  'returned event notifies the submitter'
);
select pg_temp.assert_true(
  (select count(*) = 1 from public.notifications
   where event_type = 'edit_request_created'
     and recipient_user_id = 'c2000000-0000-4000-8000-000000000003'),
  'edit request selects the manager who can resolve it'
);
select pg_temp.assert_true(
  (select count(*) = 0 from public.notifications
   where event_type = 'edit_request_created'
     and recipient_user_id = 'c2000000-0000-4000-8000-000000000002'),
  'edit request excludes an approver who cannot resolve it'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', 'c3000000-0000-4000-8000-000000000003', true);
select set_config('request.jwt.claims', '{"sub":"c3000000-0000-4000-8000-000000000003","app_metadata":{"active_church_id":"c1000000-0000-4000-8000-000000000001"}}', true);
select public.approve_submission_edit_request(jsonb_build_object(
  'submissionId', ((select response #>> '{data,submissionId}' from stage_c_submit))::uuid,
  'expectedRevision', 2,
  'clientRequestId', 'ca000000-0000-4000-8000-000000000006',
  'reason', 'Approved for correction'
));

select public.assign_ou_member(jsonb_build_object(
  'ouId', 'c6000000-0000-4000-8000-000000000002',
  'churchMemberId', 'c4000000-0000-4000-8000-000000000005',
  'permission', 'viewer',
  'canOverride', false
));

reset role;
select pg_temp.assert_true(
  (select count(*) = 1 from public.notifications
   where event_type = 'edit_request_resolved'
     and recipient_user_id = 'c2000000-0000-4000-8000-000000000001'),
  'resolved edit request notifies its requester once'
);
select pg_temp.assert_true(
  (select count(*) = 1 from public.notifications
   where event_type = 'ou_assignment_created'
     and recipient_user_id = 'c2000000-0000-4000-8000-000000000005'),
  'business assignment notifies the assigned user once'
);

insert into public.tenant_invitations(
  id, church_id, email, display_name, target_ou_id, permission,
  can_override, token_hash, expires_at, invited_by
) values (
  'cb000000-0000-4000-8000-000000000001',
  'c1000000-0000-4000-8000-000000000001',
  'stage-c-invitee@example.test',
  'Stage C Invitee',
  'c6000000-0000-4000-8000-000000000002',
  'viewer',
  false,
  encode(extensions.digest('stage-c-invitation-token', 'sha256'), 'hex'),
  now() + interval '1 day',
  'c2000000-0000-4000-8000-000000000003'
);

set local role service_role;
select pg_temp.assert_true(
  public.accept_tenant_invitations_for_user(
    'c2000000-0000-4000-8000-000000000006',
    'stage-c-invitee@example.test'
  ) = 1,
  'service invitation acceptance succeeds'
);
select pg_temp.assert_true(
  public.accept_tenant_invitations_for_user(
    'c2000000-0000-4000-8000-000000000006',
    'stage-c-invitee@example.test'
  ) = 0,
  'accepted invitation replay performs no second assignment'
);
reset role;
select pg_temp.assert_true(
  (select count(*) = 1 from public.notifications
   where event_type = 'ou_assignment_created'
     and recipient_user_id = 'c2000000-0000-4000-8000-000000000006'),
  'accepted invitation notifies the newly assigned user once'
);
select pg_temp.assert_true(
  (select count(*) = 1 from public.notification_deliveries delivery
   join public.notifications notification on notification.id = delivery.notification_id
   where notification.event_type = 'ou_assignment_created'
     and notification.recipient_user_id = 'c2000000-0000-4000-8000-000000000006'),
  'accepted invitation creates its eligible LINE outbox row'
);

-- A direct owner write after RPC execution proves the transaction-local
-- context was restored and cannot leak into later statements.
insert into public.ou_members(
  church_id, ou_id, church_member_id, permission
) values (
  'c1000000-0000-4000-8000-000000000001',
  'c6000000-0000-4000-8000-000000000002',
  'c4000000-0000-4000-8000-000000000005',
  'data_entry'
);
select pg_temp.assert_true(
  (select count(*) = 1 from public.notifications
   where event_type = 'ou_assignment_created'
     and recipient_user_id = 'c2000000-0000-4000-8000-000000000005'),
  'notification context does not leak to direct writes'
);

select pg_temp.assert_true(
  (select count(*) = count(distinct recipient_user_id::text || ':' || event_key) from public.notifications
   where church_id = 'c1000000-0000-4000-8000-000000000001'),
  'deterministic event keys are unique per recipient and event'
);
select pg_temp.assert_true(
  not exists (
    select 1 from public.notifications
    where church_id = 'c1000000-0000-4000-8000-000000000001'
      and payload::text ~* '(line_user_id|token|secret|authorization)'
  ),
  'notification payloads contain no LINE identity or provider secret fields'
);
select pg_temp.assert_true(
  not exists (
    select 1 from public.audit_logs
    where church_id = 'c1000000-0000-4000-8000-000000000001'
      and concat_ws(' ', before_data::text, after_data::text, metadata::text)
          ~* '(line_user_id|stage-c-entry|stage-c-approver|stage-c-manager|token|secret|authorization)'
  ),
  'business audit rows contain no LINE identity, invitation token or provider secret fields'
);
select pg_temp.assert_true(
  not has_function_privilege(
    'authenticated',
    'app_security.submit_statistics_without_notification_events(jsonb)',
    'EXECUTE'
  ),
  'browser roles cannot bypass the event-enabled business wrapper'
);

select 'ok 1 - Stage C transactional submission, approval, edit-request and OU-assignment notifications';
rollback;
