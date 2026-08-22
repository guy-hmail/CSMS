-- Local browser-test fixture for the Stage B Notification Center.
-- Safe to replay because deterministic event keys are idempotent.
select app_security.enqueue_notification(
  '81000000-0000-4000-8000-000000000001',
  '80000000-0000-4000-8000-000000000001',
  'submission_submitted', 'stage-b-demo:submitted',
  'Weekly report pending approval', 'Group A submitted its weekly report',
  '84000000-0000-4000-8000-000000000004', '/app/approval',
  '{"submissionId":"89000000-0000-4000-8000-000000000002"}'::jsonb, false
);
select app_security.enqueue_notification(
  '81000000-0000-4000-8000-000000000001',
  '80000000-0000-4000-8000-000000000001',
  'missing_submission_reminder', 'stage-b-demo:missing',
  'Weekly report is missing', 'Group B has not submitted the current reporting period',
  '84000000-0000-4000-8000-000000000005', '/app/submissions', '{}'::jsonb, false
);
select app_security.enqueue_notification(
  '81000000-0000-4000-8000-000000000001',
  '80000000-0000-4000-8000-000000000001',
  'ou_assignment_created', 'stage-b-demo:assignment',
  'Access updated', 'You can now manage the Demo Church workspace',
  '84000000-0000-4000-8000-000000000001', '/app/organization', '{}'::jsonb, false
);

-- A second isolated Tenant verifies that switching clears the previous feed.
insert into public.churches(id, code, slug, name, status, is_active)
values ('81000000-0000-4000-8000-0000000000b2', 'STAGEB', 'stage-b-tenant', 'Stage B Test Tenant', 'active', true)
on conflict (id) do nothing;
insert into public.church_members(id, church_id, user_id, status)
values ('82000000-0000-4000-8000-0000000000b2', '81000000-0000-4000-8000-0000000000b2', '80000000-0000-4000-8000-000000000001', 'active')
on conflict (church_id, user_id) do nothing;
insert into public.organization_unit_types(id, church_id, code, name)
values ('83000000-0000-4000-8000-0000000000b2', '81000000-0000-4000-8000-0000000000b2', 'ROOT', 'Root')
on conflict (church_id, code) do nothing;
insert into public.organization_units(id, church_id, structure_root_id, ou_type_id, code, name, path, level)
values (
  '84000000-0000-4000-8000-0000000000b2', '81000000-0000-4000-8000-0000000000b2',
  '84000000-0000-4000-8000-0000000000b2', '83000000-0000-4000-8000-0000000000b2',
  'ROOT-STAGE-B', 'Stage B Root', '/84000000-0000-4000-8000-0000000000b2', 1
)
on conflict (id) do nothing;
insert into public.ou_members(church_id, ou_id, church_member_id, permission)
values (
  '81000000-0000-4000-8000-0000000000b2', '84000000-0000-4000-8000-0000000000b2',
  '82000000-0000-4000-8000-0000000000b2', 'admin'
)
on conflict (church_id, ou_id, church_member_id, permission) do nothing;
select app_security.enqueue_notification(
  '81000000-0000-4000-8000-0000000000b2',
  '80000000-0000-4000-8000-000000000001',
  'ou_assignment_created', 'stage-b-tenant:assignment',
  'Stage B tenant access', 'This notification belongs only to the second Tenant',
  '84000000-0000-4000-8000-0000000000b2', '/app/organization', '{}'::jsonb, false
);
