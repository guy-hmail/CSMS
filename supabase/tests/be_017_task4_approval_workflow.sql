\set ON_ERROR_STOP on
select '1..1';
begin;

insert into public.churches (id, code, slug, name, status, approval_mode)
values
('00000000-0000-0000-0000-000000000171', 'APPR', 'approval-test', 'Approval Test', 'active', 'approval_required'),
('00000000-0000-0000-0000-000000000172', 'AUTO', 'approval-auto', 'Approval Auto', 'active', 'auto_approve');
insert into public.users (id, auth_user_id, line_user_id, display_name)
values
('10000000-0000-0000-0000-000000000171', 'a7000000-0000-4000-8000-000000000171', 'task4-entry', 'Data Entry'),
('10000000-0000-0000-0000-000000000172', 'a7000000-0000-4000-8000-000000000172', 'task4-approver', 'Approver'),
('10000000-0000-0000-0000-000000000173', 'a7000000-0000-4000-8000-000000000173', 'task4-senior', 'Senior Approver'),
('10000000-0000-0000-0000-000000000174', 'a7000000-0000-4000-8000-000000000174', 'task4-auto', 'Auto Entry');
insert into public.church_members (id, church_id, user_id, status)
values
('20000000-0000-0000-0000-000000000171', '00000000-0000-0000-0000-000000000171', '10000000-0000-0000-0000-000000000171', 'active'),
('20000000-0000-0000-0000-000000000172', '00000000-0000-0000-0000-000000000171', '10000000-0000-0000-0000-000000000172', 'active'),
('20000000-0000-0000-0000-000000000173', '00000000-0000-0000-0000-000000000171', '10000000-0000-0000-0000-000000000173', 'active'),
('20000000-0000-0000-0000-000000000174', '00000000-0000-0000-0000-000000000172', '10000000-0000-0000-0000-000000000174', 'active');
insert into public.organization_unit_types (id, church_id, code, name)
values
('30000000-0000-0000-0000-000000000171', '00000000-0000-0000-0000-000000000171', 'GROUP', 'Group'),
('30000000-0000-0000-0000-000000000172', '00000000-0000-0000-0000-000000000172', 'GROUP', 'Group');
insert into public.organization_units (id, church_id, structure_root_id, parent_id, ou_type_id, code, name, path, level, allow_data_entry)
values
('40000000-0000-0000-0000-000000000171', '00000000-0000-0000-0000-000000000171', '40000000-0000-0000-0000-000000000171', null, '30000000-0000-0000-0000-000000000171', 'ROOT', 'Root', '/root', 1, false),
('40000000-0000-0000-0000-000000000172', '00000000-0000-0000-0000-000000000171', '40000000-0000-0000-0000-000000000171', '40000000-0000-0000-0000-000000000171', '30000000-0000-0000-0000-000000000171', 'GROUP', 'Group', '/root/group', 2, true),
('40000000-0000-0000-0000-000000000174', '00000000-0000-0000-0000-000000000172', '40000000-0000-0000-0000-000000000174', null, '30000000-0000-0000-0000-000000000172', 'AUTO', 'Auto Root', '/auto', 1, true);
insert into public.ou_members (id, church_id, ou_id, church_member_id, permission, can_override)
values
('41000000-0000-0000-0000-000000000171', '00000000-0000-0000-0000-000000000171', '40000000-0000-0000-0000-000000000172', '20000000-0000-0000-0000-000000000171', 'data_entry', false),
('41000000-0000-0000-0000-000000000172', '00000000-0000-0000-0000-000000000171', '40000000-0000-0000-0000-000000000172', '20000000-0000-0000-0000-000000000172', 'approver', false),
('41000000-0000-0000-0000-000000000173', '00000000-0000-0000-0000-000000000171', '40000000-0000-0000-0000-000000000171', '20000000-0000-0000-0000-000000000173', 'approver', false),
('41000000-0000-0000-0000-000000000174', '00000000-0000-0000-0000-000000000172', '40000000-0000-0000-0000-000000000174', '20000000-0000-0000-0000-000000000174', 'data_entry', false);
insert into public.statistic_periods (id, church_id, year, week_no, period_start, period_end, label)
values
('50000000-0000-0000-0000-000000000171', '00000000-0000-0000-0000-000000000171', 2026, 28, '2026-07-06', '2026-07-12', '2026-W28'),
('50000000-0000-0000-0000-000000000172', '00000000-0000-0000-0000-000000000171', 2026, 29, '2026-07-13', '2026-07-19', '2026-W29'),
('50000000-0000-0000-0000-000000000174', '00000000-0000-0000-0000-000000000172', 2026, 28, '2026-07-06', '2026-07-12', '2026-W28');
insert into public.statistic_metrics (id, church_id, code, name, category, unit, min_value, is_required)
values
('60000000-0000-0000-0000-000000000171', '00000000-0000-0000-0000-000000000171', 'ATT', 'Attendance', 'test', 'person', 0, true),
('60000000-0000-0000-0000-000000000174', '00000000-0000-0000-0000-000000000172', 'ATT', 'Attendance', 'test', 'person', 0, true);

create function pg_temp.assert_true(condition boolean, message text)
returns void language plpgsql as $$ begin if condition is not true then raise exception 'BE-017 assertion: %', message; end if; end; $$;
create function pg_temp.action_fails(p_submission uuid, p_request uuid)
returns boolean language plpgsql as $$
begin
  perform public.approve_submission(jsonb_build_object('submissionId', p_submission, 'expectedRevision', 1, 'clientRequestId', p_request));
  return false;
exception when others then return true;
end; $$;
create function pg_temp.detail_fails(p_submission uuid)
returns boolean language plpgsql as $$
begin
  perform public.get_approval_submission_detail(p_submission);
  return false;
exception when others then return true;
end; $$;

set local role authenticated;
select set_config('request.jwt.claim.sub', 'a7000000-0000-4000-8000-000000000171', true);
select set_config('request.jwt.claims', '{"sub":"a7000000-0000-4000-8000-000000000171","app_metadata":{"active_church_id":"00000000-0000-0000-0000-000000000171"}}', true);
create temporary table submit_one as select public.submit_statistics(jsonb_build_object(
  'clientRequestId', '70000000-0000-4000-8000-000000000171', 'expectedRevision', null,
  'ouId', '40000000-0000-0000-0000-000000000172', 'periodId', '50000000-0000-0000-0000-000000000171',
  'values', jsonb_build_array(jsonb_build_object('metricId', '60000000-0000-0000-0000-000000000171', 'numericValue', 20, 'textValue', null, 'booleanValue', null))
)) response;
select pg_temp.assert_true((select response #>> '{data,status}' = 'submitted' from submit_one), 'approval-required submit remains submitted');
select pg_temp.assert_true(jsonb_array_length(public.list_pending_submissions(null, null, 'submitted') #> '{data,items}') = 0, 'data-entry user cannot see approval queue');

select set_config('request.jwt.claim.sub', 'a7000000-0000-4000-8000-000000000172', true);
select set_config('request.jwt.claims', '{"sub":"a7000000-0000-4000-8000-000000000172","app_metadata":{"active_church_id":"00000000-0000-0000-0000-000000000171"}}', true);
select pg_temp.assert_true(jsonb_array_length(public.list_pending_submissions(null, null, 'submitted') #> '{data,items}') = 1, 'nearest approver sees pending queue');
select pg_temp.assert_true((public.get_recursive_summary('40000000-0000-0000-0000-000000000172', '50000000-0000-0000-0000-000000000171', null) #>> '{data,metrics,0,currentValue}') is null, 'submitted value excluded from official summary');
create temporary table approve_one as select public.approve_submission(jsonb_build_object(
  'submissionId', ((select response #>> '{data,submissionId}' from submit_one))::uuid,
  'expectedRevision', 1, 'clientRequestId', '70000000-0000-4000-8000-000000000172', 'reason', 'Checked'
)) response;
select pg_temp.assert_true((select response #>> '{data,status}' = 'approved' from approve_one), 'approve transition');
select pg_temp.assert_true(public.approve_submission(jsonb_build_object(
  'submissionId', ((select response #>> '{data,submissionId}' from submit_one))::uuid,
  'expectedRevision', 1, 'clientRequestId', '70000000-0000-4000-8000-000000000172', 'reason', 'Checked'
)) = (select response from approve_one), 'approval replay is idempotent');
select pg_temp.assert_true((public.get_recursive_summary('40000000-0000-0000-0000-000000000172', '50000000-0000-0000-0000-000000000171', null) #>> '{data,metrics,0,currentValue}')::numeric = 20, 'approved value enters official summary');
select pg_temp.assert_true(pg_temp.action_fails(((select response #>> '{data,submissionId}' from submit_one))::uuid, '70000000-0000-4000-8000-000000000179'), 'second committed transition loses');
select public.return_submission_for_edit(jsonb_build_object(
  'submissionId', ((select response #>> '{data,submissionId}' from submit_one))::uuid,
  'expectedRevision', 1, 'clientRequestId', '70000000-0000-4000-8000-000000000173', 'reason', 'Please correct'
));
select pg_temp.assert_true((public.get_approval_submission_detail(((select response #>> '{data,submissionId}' from submit_one))::uuid) #>> '{data,submission,status}') = 'returned', 'approved record returned for correction');

select set_config('request.jwt.claim.sub', 'a7000000-0000-4000-8000-000000000173', true);
select set_config('request.jwt.claims', '{"sub":"a7000000-0000-4000-8000-000000000173","app_metadata":{"active_church_id":"00000000-0000-0000-0000-000000000171"}}', true);
reset role;
select pg_temp.assert_true(not coalesce((app_security.approval_actor_context('40000000-0000-0000-0000-000000000172') ->> 'canAct')::boolean, false), 'senior approver without override cannot bypass nearest approver');
update public.ou_members set can_override = true where id = '41000000-0000-0000-0000-000000000173';
select pg_temp.assert_true((app_security.approval_actor_context('40000000-0000-0000-0000-000000000172') ->> 'isOverride')::boolean, 'senior approver with override is identified');

set local role authenticated;
select set_config('request.jwt.claim.sub', 'a7000000-0000-4000-8000-000000000174', true);
select set_config('request.jwt.claims', '{"sub":"a7000000-0000-4000-8000-000000000174","app_metadata":{"active_church_id":"00000000-0000-0000-0000-000000000172"}}', true);
select public.submit_statistics(jsonb_build_object(
  'clientRequestId', '70000000-0000-4000-8000-000000000174', 'expectedRevision', null,
  'ouId', '40000000-0000-0000-0000-000000000174', 'periodId', '50000000-0000-0000-0000-000000000174',
  'values', jsonb_build_array(jsonb_build_object('metricId', '60000000-0000-0000-0000-000000000174', 'numericValue', 9, 'textValue', null, 'booleanValue', null))
));
select pg_temp.assert_true((select count(*) = 0 from public.statistic_submissions where church_id = '00000000-0000-0000-0000-000000000172' and status = 'submitted'), 'auto-approve tenant has no pending submission');
select pg_temp.assert_true(pg_temp.detail_fails(((select response #>> '{data,submissionId}' from submit_one))::uuid), 'cross-tenant approval detail is hidden');

reset role;
select pg_temp.assert_true((select count(*) = 2 from public.approval_logs where submission_id = ((select response #>> '{data,submissionId}' from submit_one))::uuid and action in ('approve', 'return')), 'workflow history records both actions');
select pg_temp.assert_true((select count(*) = 2 from public.audit_logs where entity_id = ((select response #>> '{data,submissionId}' from submit_one))::uuid and action in ('approve', 'return')), 'workflow actions are audited');
select pg_temp.assert_true((select bool_and(reason is not null) from public.approval_logs where submission_id = ((select response #>> '{data,submissionId}' from submit_one))::uuid and action in ('approve', 'return')), 'action reasons persist');
select pg_temp.assert_true(not has_function_privilege('anon', 'public.approve_submission(jsonb)', 'EXECUTE'), 'anonymous mutation execution revoked');

select 'ok 1 - Task 4 approval workflow, isolation, override and concurrency';
rollback;
