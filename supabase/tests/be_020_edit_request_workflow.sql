\set ON_ERROR_STOP on
select '1..1';
begin;

insert into public.users(id, auth_user_id, line_user_id, display_name) values
('a0000000-0000-4000-8000-000000000201','a0000000-0000-4000-8000-000000000211','edit-request-entry','Edit Request Entry'),
('a0000000-0000-4000-8000-000000000202','a0000000-0000-4000-8000-000000000212','edit-request-manager','Edit Request Manager');
insert into public.church_members(id, church_id, user_id, status) values
('a0000000-0000-4000-8000-000000000221','81000000-0000-4000-8000-000000000001','a0000000-0000-4000-8000-000000000201','active'),
('a0000000-0000-4000-8000-000000000222','81000000-0000-4000-8000-000000000001','a0000000-0000-4000-8000-000000000202','active');
insert into public.ou_members(id, church_id, ou_id, church_member_id, permission) values
('a0000000-0000-4000-8000-000000000231','81000000-0000-4000-8000-000000000001','84000000-0000-4000-8000-000000000004','a0000000-0000-4000-8000-000000000221','data_entry'),
('a0000000-0000-4000-8000-000000000232','81000000-0000-4000-8000-000000000001','84000000-0000-4000-8000-000000000004','a0000000-0000-4000-8000-000000000222','manager');

create function pg_temp.assert_true(condition boolean, message text)
returns void language plpgsql as $$ begin if condition is not true then raise exception 'BE-020 assertion: %', message; end if; end; $$;

set local role authenticated;
select set_config('request.jwt.claim.sub','a0000000-0000-4000-8000-000000000211',true);
select set_config('request.jwt.claims','{"sub":"a0000000-0000-4000-8000-000000000211","app_metadata":{"active_church_id":"81000000-0000-4000-8000-000000000001"}}',true);
select public.request_submission_edit(jsonb_build_object(
  'submissionId','89000000-0000-4000-8000-000000000002','expectedRevision',1,
  'clientRequestId','a0000000-0000-4000-8000-000000000241','reason','Incorrect attendance'
));
select pg_temp.assert_true((select status='edit_requested' and returned_at is null from public.statistic_submissions where id='89000000-0000-4000-8000-000000000002'), 'request remains locked');

select set_config('request.jwt.claim.sub','a0000000-0000-4000-8000-000000000212',true);
select set_config('request.jwt.claims','{"sub":"a0000000-0000-4000-8000-000000000212","app_metadata":{"active_church_id":"81000000-0000-4000-8000-000000000001"}}',true);
select pg_temp.assert_true((public.get_pending_edit_request_count() #>> '{data,count}')::integer=1, 'manager notification count');
select pg_temp.assert_true(jsonb_array_length(public.list_pending_submissions(null,null,'edit_requested') #> '{data,items}')=1, 'manager sees request queue');
select public.approve_submission_edit_request(jsonb_build_object(
  'submissionId','89000000-0000-4000-8000-000000000002','expectedRevision',1,
  'clientRequestId','a0000000-0000-4000-8000-000000000242','reason','Approved for correction'
));
select pg_temp.assert_true((select status='returned' and returned_at is not null from public.statistic_submissions where id='89000000-0000-4000-8000-000000000002'), 'manager approval unlocks submission');
select pg_temp.assert_true((public.get_pending_edit_request_count() #>> '{data,count}')::integer=0, 'notification clears after approval');

select set_config('request.jwt.claim.sub','a0000000-0000-4000-8000-000000000211',true);
select set_config('request.jwt.claims','{"sub":"a0000000-0000-4000-8000-000000000211","app_metadata":{"active_church_id":"81000000-0000-4000-8000-000000000001"}}',true);
select public.submit_statistics(jsonb_build_object(
  'submissionId','89000000-0000-4000-8000-000000000002','expectedRevision',1,
  'clientRequestId','a0000000-0000-4000-8000-000000000243','ouId','84000000-0000-4000-8000-000000000004',
  'periodId','88000000-0000-4000-8000-000000000002','values',jsonb_build_array(
    jsonb_build_object('metricId','87000000-0000-4000-8000-000000000001','numericValue',25,'textValue',null,'booleanValue',null)
  )
));
select pg_temp.assert_true((select edit_requested_at is null and edit_request_reason is null from public.statistic_submissions where id='89000000-0000-4000-8000-000000000002'), 'resubmission clears completed request metadata');

select 'ok 1 - edit request stays locked, notifies manager, and unlocks only after approval';
rollback;
