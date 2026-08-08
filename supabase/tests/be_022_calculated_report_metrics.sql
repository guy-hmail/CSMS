\set ON_ERROR_STOP on
select '1..1';
begin;

create function pg_temp.assert_true(condition boolean, message text)
returns void language plpgsql as $$ begin if condition is not true then raise exception 'BE-022 assertion: %', message; end if; end; $$;

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

set local role authenticated;
select set_config('request.jwt.claim.sub', '80000000-0000-4000-8000-000000000002', true);
select set_config('request.jwt.claims', '{"sub":"80000000-0000-4000-8000-000000000002","app_metadata":{"active_church_id":"81000000-0000-4000-8000-000000000001"}}', true);

create temporary table calculated_metric as
select (public.create_calculated_metric(jsonb_build_object(
  'code', 'TOTAL_CHURCH_ATTENDANCE',
  'name', 'คนมาคจ.',
  'description', 'ผู้ใหญ่ + เด็ก + ผจ. + ผส.',
  'category', 'attendance',
  'unit', 'คน',
  'sortOrder', 15,
  'sourceMetricIds', jsonb_build_array(
    '87000000-0000-4000-8000-000000000001',
    '87000000-0000-4000-8000-000000000008',
    '87000000-0000-4000-8000-000000000009',
    '87000000-0000-4000-8000-000000000010'
  )
)) #>> '{data,metricId}')::uuid as id;

select pg_temp.assert_true((
  select metric_kind = 'calculated' and calculation_operator = 'sum'
    and cardinality(calculation_source_metric_ids) = 4
  from public.statistic_metrics where id = (select id from calculated_metric)
), 'calculated metric definition is saved');

create temporary table report_result as
select public.get_report_table('84000000-0000-4000-8000-000000000001', '2026-07-20', '2026-07-26') response;

select pg_temp.assert_true((
  select (response #>> '{data,totals,TOTAL_CHURCH_ATTENDANCE}')::numeric = 222
  from report_result
), (select 'report total calculates all four source metrics; actual=' || coalesce(response #>> '{data,totals,TOTAL_CHURCH_ATTENDANCE}', '<null>') from report_result));

select pg_temp.assert_true((
  select exists (
    select 1 from report_result, lateral jsonb_array_elements(response #> '{data,metrics}') metric
    where metric ->> 'metricCode' = 'TOTAL_CHURCH_ATTENDANCE'
      and metric ->> 'metricKind' = 'calculated'
      and jsonb_array_length(metric -> 'sourceMetricCodes') = 4
  )
), 'report metadata exposes the calculated field and its sources');

select pg_temp.assert_true((
  select count(*) = 2
  from jsonb_array_elements(public.get_report_trend(
    '84000000-0000-4000-8000-000000000001',
    'TOTAL_CHURCH_ATTENDANCE', '2026-07-13', '2026-07-26'
  ) #> '{data,points}') point
  where (point ->> 'value')::numeric in (114, 222)
), 'trend calculates the field for every report period');

select pg_temp.assert_true(not exists (
  select 1 from jsonb_array_elements(public.get_weekly_submission_context() #> '{data,metrics}') metric
  where metric ->> 'code' = 'TOTAL_CHURCH_ATTENDANCE'
), 'calculated field is excluded from the submission form');

reset role;
do $$ begin
  insert into public.statistic_values (church_id, submission_id, metric_id, numeric_value)
  values (
    '81000000-0000-4000-8000-000000000001',
    '89000000-0000-4000-8000-000000000002',
    (select id from calculated_metric), 999
  );
  raise exception 'BE-022 assertion: direct calculated value was accepted';
exception when others then
  if sqlerrm <> 'CALCULATED_METRIC_VALUE_FORBIDDEN' then raise; end if;
end $$;

set local role authenticated;
do $$ begin
  perform public.update_statistic_metric(jsonb_build_object(
    'metricId', '87000000-0000-4000-8000-000000000001',
    'isActive', false
  ));
  raise exception 'BE-022 assertion: active calculation source was deactivated';
exception when others then
  if sqlerrm <> 'PRIMARY_METRIC_DEACTIVATION_FORBIDDEN'
     and sqlerrm <> 'METRIC_USED_BY_CALCULATION' then raise; end if;
end $$;

select pg_temp.assert_true(
  not has_function_privilege('anon', 'public.create_calculated_metric(jsonb)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.update_calculated_metric(jsonb)', 'EXECUTE'),
  'anonymous calculated metric mutations are revoked'
);

select 'ok 1 - Calculated report metrics';
rollback;
