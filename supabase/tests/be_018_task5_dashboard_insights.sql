\set ON_ERROR_STOP on
select '1..1';
begin;

create function pg_temp.assert_true(condition boolean, message text)
returns void language plpgsql as $$ begin if condition is not true then raise exception 'BE-018 assertion: %', message; end if; end; $$;

set local role authenticated;
select set_config('request.jwt.claim.sub', '80000000-0000-4000-8000-000000000002', true);
select set_config('request.jwt.claims', '{"sub":"80000000-0000-4000-8000-000000000002","app_metadata":{"active_church_id":"81000000-0000-4000-8000-000000000001"}}', true);

create temporary table status_result as
select public.get_submission_status_summary('84000000-0000-4000-8000-000000000001', '88000000-0000-4000-8000-000000000002') response;
select pg_temp.assert_true((select response #>> '{data,summary,totalExpected}' = '2' and response #>> '{data,summary,approved}' = '2' from status_result), 'seed reporting OUs are complete');

create temporary table child_result as
select public.get_child_ou_summary('84000000-0000-4000-8000-000000000001', '88000000-0000-4000-8000-000000000002') response;
select pg_temp.assert_true((select response #>> '{data,children,0,ouName}' = 'ภาคกลาง' from child_result), 'direct child returned');
select pg_temp.assert_true((select (response #>> '{data,children,0,metrics,0,value}')::numeric = 175 from child_result), 'child subtree sum has no duplicate');
select pg_temp.assert_true((select response #>> '{data,children,0,status}' = 'approved' from child_result), 'child completeness status');

create temporary table trend_result as
select public.get_dashboard_trend('84000000-0000-4000-8000-000000000001', 'ATTENDANCE', '88000000-0000-4000-8000-000000000002', 12) response;
select pg_temp.assert_true((select response #>> '{data,metricCode}' = 'ATTENDANCE' from trend_result), 'trend metric metadata');
select pg_temp.assert_true((
  select count(*) = 2
  from trend_result, lateral jsonb_array_elements(response #> '{data,points}') point
  where (point ->> 'periodId', (point ->> 'value')::numeric) in (
    ('88000000-0000-4000-8000-000000000001', 90::numeric),
    ('88000000-0000-4000-8000-000000000002', 175::numeric)
  )
), 'approved trend values match their periods');

reset role;
update public.organization_units set allow_data_entry = true where id = '84000000-0000-4000-8000-000000000002';
insert into public.statistic_submissions (id, church_id, period_id, ou_id, status, submitted_by, submitted_at, approved_by, approved_at)
values ('89000000-0000-4000-8000-000000000018', '81000000-0000-4000-8000-000000000001', '88000000-0000-4000-8000-000000000002', '84000000-0000-4000-8000-000000000002', 'approved', '80000000-0000-4000-8000-000000000001', now(), '80000000-0000-4000-8000-000000000001', now());
insert into public.statistic_values (church_id, submission_id, metric_id, numeric_value)
values ('81000000-0000-4000-8000-000000000001', '89000000-0000-4000-8000-000000000018', '87000000-0000-4000-8000-000000000001', 10);
insert into public.statistic_periods (id, church_id, year, week_no, period_start, period_end, label)
values ('88000000-0000-4000-8000-000000000018', '81000000-0000-4000-8000-000000000001', 2026, 32, '2026-08-03', '2026-08-09', '2026-W32');
insert into public.statistic_submissions (id, church_id, period_id, ou_id, status, submitted_by, submitted_at)
values ('89000000-0000-4000-8000-000000000019', '81000000-0000-4000-8000-000000000001', '88000000-0000-4000-8000-000000000018', '84000000-0000-4000-8000-000000000004', 'submitted', '80000000-0000-4000-8000-000000000001', now());
insert into public.statistic_values (church_id, submission_id, metric_id, numeric_value)
values ('81000000-0000-4000-8000-000000000001', '89000000-0000-4000-8000-000000000019', '87000000-0000-4000-8000-000000000001', 999);
update public.churches set approval_mode = 'approval_required' where id = '81000000-0000-4000-8000-000000000001';

set local role authenticated;
select set_config('request.jwt.claim.sub', '80000000-0000-4000-8000-000000000002', true);
select set_config('request.jwt.claims', '{"sub":"80000000-0000-4000-8000-000000000002","app_metadata":{"active_church_id":"81000000-0000-4000-8000-000000000001"}}', true);
select pg_temp.assert_true((public.get_recursive_summary('84000000-0000-4000-8000-000000000001', '88000000-0000-4000-8000-000000000002', null) #>> '{data,metrics,0,currentValue}')::numeric = 185, 'parent direct value is additive exactly once');
select pg_temp.assert_true((public.get_submission_status_summary('84000000-0000-4000-8000-000000000001', '88000000-0000-4000-8000-000000000018') #>> '{data,summary,pending}') = '1', 'pending completeness is visible');
select pg_temp.assert_true((public.get_recursive_summary('84000000-0000-4000-8000-000000000001', '88000000-0000-4000-8000-000000000018', null) #>> '{data,metrics,0,currentValue}') is null, 'approval-required pending value excluded from official total');
select pg_temp.assert_true((public.get_dashboard_trend('84000000-0000-4000-8000-000000000001', 'ATTENDANCE', '88000000-0000-4000-8000-000000000018', 1) #>> '{data,points,0,value}')::numeric = 0, 'pending value excluded from trend');
select pg_temp.assert_true(not has_function_privilege('anon', 'public.get_dashboard_trend(uuid,text,uuid,integer)', 'EXECUTE'), 'anonymous dashboard execution revoked');

select 'ok 1 - Task 5 dashboard completeness, child rollup and trend';
rollback;
