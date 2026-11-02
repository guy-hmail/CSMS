\set ON_ERROR_STOP on
select '1..1';
begin;

create function pg_temp.assert_true(condition boolean, message text)
returns void language plpgsql as $$ begin if condition is not true then raise exception 'BE-037 assertion: %', message; end if; end; $$;

-- Keep the seed-based assertions isolated from OUs created during local UI testing.
update public.organization_units
set is_active = false, allow_data_entry = false
where church_id = '81000000-0000-4000-8000-000000000001'
  and id not in (
    '84000000-0000-4000-8000-000000000001',
    '84000000-0000-4000-8000-000000000002',
    '84000000-0000-4000-8000-000000000003',
    '84000000-0000-4000-8000-000000000004',
    '84000000-0000-4000-8000-000000000005'
  );
update public.organization_units
set is_active = true, allow_data_entry = true
where id in (
  '84000000-0000-4000-8000-000000000004',
  '84000000-0000-4000-8000-000000000005'
);


select pg_temp.assert_true(app_security.ratio_result(0, 5) = '{"value":0,"error":null}'::jsonb, 'zero numerator is a valid zero');
select pg_temp.assert_true(app_security.ratio_result(0, 0) = '{"value":null,"error":"DIVISION_BY_ZERO"}'::jsonb, 'zero over zero is undefined');
select pg_temp.assert_true(app_security.ratio_result(null, 0) ->> 'error' = 'MISSING_DATA', 'missing data takes precedence');
select pg_temp.assert_true((app_security.ratio_result(5, 2) ->> 'value')::numeric = 3, 'half rounds up');
select pg_temp.assert_true((app_security.ratio_result(7, 3) ->> 'value')::numeric = 2, 'fraction below half rounds down');
select pg_temp.assert_true((app_security.ratio_result(-5, 2) ->> 'value')::numeric = -3, 'negative half rounds away from zero');
set local role authenticated;
select set_config('request.jwt.claim.sub', '80000000-0000-4000-8000-000000000002', true);
select set_config('request.jwt.claims', '{"sub":"80000000-0000-4000-8000-000000000002","app_metadata":{"active_church_id":"81000000-0000-4000-8000-000000000001"}}', true);


create temporary table ratio_metric as
select (public.create_calculated_metric(jsonb_build_object(
 'code', 'TEST_RATIO', 'name', 'Test ratio', 'category', 'attendance', 'unit', 'ratio',
 'operator', 'ratio', 'sourceMetricIds', jsonb_build_array(
 '87000000-0000-4000-8000-000000000008', '87000000-0000-4000-8000-000000000001')
)) #>> '{data,metricId}')::uuid id;
select pg_temp.assert_true((select calculation_source_metric_ids[1] = '87000000-0000-4000-8000-000000000008'::uuid from public.statistic_metrics where id = (select id from ratio_metric)), 'operand order is preserved');
select pg_temp.assert_true(not has_function_privilege('anon', 'app_security.report_ratio_result(uuid,uuid,date,date,boolean)', 'EXECUTE'), 'ratio helper is not publicly callable');
reset role;
update public.statistic_metrics set show_on_dashboard = true where id = (select id from ratio_metric);

-- Exercise all report/dashboard endpoints for each edge case using one approved OU.
do $$
declare scenario record; result jsonb; metric jsonb; root_id uuid := '84000000-0000-4000-8000-000000000001';
 leaf_id uuid := '84000000-0000-4000-8000-000000000004'; period_id uuid := '88000000-0000-4000-8000-000000000002';
begin
 for scenario in select * from (values
  (0::numeric, 5::numeric, 0::numeric, null::text),
  (5, 0, null, 'DIVISION_BY_ZERO'), (0, 0, null, 'DIVISION_BY_ZERO'),
  (null, 5, null, 'MISSING_DATA'), (5, null, null, 'MISSING_DATA'),
  (null, 0, null, 'MISSING_DATA'), (7, 3, 2, null), (5, 2, 3, null)
 ) cases(a,b,expected,reason) loop
  delete from public.statistic_values where submission_id = '89000000-0000-4000-8000-000000000002'
    and metric_id in ('87000000-0000-4000-8000-000000000008','87000000-0000-4000-8000-000000000001');
  insert into public.statistic_values(church_id, submission_id, metric_id, numeric_value)
    select '81000000-0000-4000-8000-000000000001', '89000000-0000-4000-8000-000000000002', id::uuid, value
    from (values ('87000000-0000-4000-8000-000000000008', scenario.a), ('87000000-0000-4000-8000-000000000001', scenario.b)) operands(id,value)
    where value is not null;
  result := public.get_report_table(leaf_id, '2026-07-26', '2026-07-26') -> 'data';
  perform pg_temp.assert_true((result #>> '{totals,TEST_RATIO}')::numeric is not distinct from scenario.expected, 'report total');
  perform pg_temp.assert_true(result #>> '{totalErrors,TEST_RATIO}' is not distinct from scenario.reason, 'report total reason');
  perform pg_temp.assert_true(result #>> '{rows,0,errors,TEST_RATIO}' is not distinct from scenario.reason, 'report row reason');
  perform pg_temp.assert_true(result #>> '{metrics,0,sourceMetricCodes}' is not null or exists (select 1 from jsonb_array_elements(result -> 'metrics') m where m ->> 'metricCode' = 'TEST_RATIO'), 'ratio metadata');
  result := public.get_report_trend(leaf_id, 'TEST_RATIO', '2026-07-26', '2026-07-26') #> '{data,points,0}';
  perform pg_temp.assert_true((result ->> 'value')::numeric is not distinct from scenario.expected and result ->> 'error' is not distinct from scenario.reason, 'report trend preserves null and reason');
  select m into metric from jsonb_array_elements(public.get_recursive_summary(leaf_id, period_id) #> '{data,metrics}') m where m ->> 'metricCode' = 'TEST_RATIO';
  perform pg_temp.assert_true((metric ->> 'currentValue')::numeric is not distinct from scenario.expected and metric ->> 'error' is not distinct from scenario.reason, 'dashboard KPI');
  select m into metric from jsonb_array_elements(public.get_child_ou_summary((select parent_id from public.organization_units where id = leaf_id), period_id) #> '{data,children}') child, lateral jsonb_array_elements(child -> 'metrics') m where child ->> 'ouId' = leaf_id::text and m ->> 'metricCode' = 'TEST_RATIO';
  perform pg_temp.assert_true((metric ->> 'value')::numeric is not distinct from scenario.expected and metric ->> 'error' is not distinct from scenario.reason, 'child OU summary');
  result := public.get_dashboard_trend(leaf_id, 'TEST_RATIO', period_id, 1) #> '{data,points,0}';
  perform pg_temp.assert_true((result ->> 'value')::numeric is not distinct from scenario.expected and result ->> 'error' is not distinct from scenario.reason, 'dashboard trend');
 end loop;
end $$;

-- The combined ratio is 6 / 6 = 1, not the sum of rounded row ratios (3 + 0).
update public.statistic_values set numeric_value = case when metric_id = '87000000-0000-4000-8000-000000000008' then 1 else 4 end
where submission_id = '89000000-0000-4000-8000-000000000003' and metric_id in ('87000000-0000-4000-8000-000000000008','87000000-0000-4000-8000-000000000001');
select pg_temp.assert_true((public.get_report_table('84000000-0000-4000-8000-000000000001', '2026-07-26', '2026-07-26') #>> '{data,totals,TEST_RATIO}')::numeric = 1, 'ratio of sums, rounded once');

-- All rows missing an operand, including absence of the value row, stay missing.
delete from public.statistic_values where submission_id = '89000000-0000-4000-8000-000000000002' and metric_id = '87000000-0000-4000-8000-000000000008';
select pg_temp.assert_true(public.get_report_table('84000000-0000-4000-8000-000000000001', '2026-07-26', '2026-07-26') #>> '{data,totalErrors,TEST_RATIO}' = 'MISSING_DATA', 'partial data cannot silently produce a ratio');
select pg_temp.assert_true(public.get_report_trend('84000000-0000-4000-8000-000000000004', 'TEST_RATIO', '2020-01-01', '2020-01-01') #> '{data,points}' = '[]'::jsonb, 'empty date range is supported');

set local role authenticated;
select public.update_calculated_metric(jsonb_build_object('metricId', (select id from ratio_metric), 'sourceMetricIds', jsonb_build_array('87000000-0000-4000-8000-000000000001','87000000-0000-4000-8000-000000000001')));
select pg_temp.assert_true((public.get_report_table('84000000-0000-4000-8000-000000000004', '2026-07-26', '2026-07-26') #>> '{data,totals,TEST_RATIO}')::numeric = 1, 'A divided by A is allowed');
do $$ begin
 perform public.update_calculated_metric(jsonb_build_object('metricId', (select id from ratio_metric), 'operator', 'invalid'));
 raise exception 'invalid operator accepted';
exception when others then if sqlerrm <> 'CALCULATION_OPERATOR_INVALID' then raise; end if;
end $$;
select 'ok 1 - Ratio calculated metrics';
rollback;
