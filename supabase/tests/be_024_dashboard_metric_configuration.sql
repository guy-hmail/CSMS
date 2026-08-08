\set ON_ERROR_STOP on
select '1..1';
begin;

create function pg_temp.assert_true(condition boolean, message text)
returns void language plpgsql as $$ begin if condition is not true then raise exception 'BE-024 assertion: %', message; end if; end; $$;

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

create temporary table dashboard_calculated as
select (public.create_calculated_metric(jsonb_build_object(
  'code', 'DASHBOARD_TOTAL', 'name', 'คนมาคจ.รวม', 'category', 'attendance', 'unit', 'คน', 'sortOrder', 5,
  'sourceMetricIds', jsonb_build_array(
    '87000000-0000-4000-8000-000000000001', '87000000-0000-4000-8000-000000000008',
    '87000000-0000-4000-8000-000000000009', '87000000-0000-4000-8000-000000000010'
  )
)) #>> '{data,metricId}')::uuid id;

select public.update_dashboard_metric_settings(jsonb_build_object('metricIds', jsonb_build_array(
  (select id from dashboard_calculated), '87000000-0000-4000-8000-000000000001'
)));

create temporary table dashboard_summary as
select public.get_recursive_summary(
  '84000000-0000-4000-8000-000000000001', '88000000-0000-4000-8000-000000000002', null
) response;

select pg_temp.assert_true((
  select jsonb_array_length(response #> '{data,metrics}') = 2
    and response #>> '{data,metrics,0,metricCode}' = 'DASHBOARD_TOTAL'
    and response #>> '{data,metrics,0,metricKind}' = 'calculated'
    and (response #>> '{data,metrics,0,currentValue}')::numeric = 222
    and response #>> '{data,metrics,1,metricCode}' = 'ATTENDANCE'
  from dashboard_summary
), 'dashboard returns only selected raw/calculated metrics in configured order');

select pg_temp.assert_true((
  public.get_dashboard_trend(
    '84000000-0000-4000-8000-000000000001', 'DASHBOARD_TOTAL',
    '88000000-0000-4000-8000-000000000002', 1
  ) #>> '{data,points,0,value}'
)::numeric = 222, 'calculated dashboard trend is evaluated');

select pg_temp.assert_true((
  select jsonb_array_length(metric_items) = 2 and metric_items #>> '{0,metricCode}' = 'DASHBOARD_TOTAL'
  from jsonb_array_elements(public.get_child_ou_summary(
    '84000000-0000-4000-8000-000000000001', '88000000-0000-4000-8000-000000000002'
  ) #> '{data,children}') child,
  lateral (select child -> 'metrics' metric_items) selected_child
  limit 1
), 'child OU summary follows the dashboard metric selection');

select pg_temp.assert_true(not has_function_privilege(
  'anon', 'public.update_dashboard_metric_settings(jsonb)', 'EXECUTE'
), 'anonymous dashboard setting mutation is revoked');

select 'ok 1 - tenant dashboard metric selection and ordering';
rollback;
