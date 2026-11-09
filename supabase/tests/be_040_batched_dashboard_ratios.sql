\set ON_ERROR_STOP on
select '1..1';
begin;

create function pg_temp.assert_true(condition boolean, message text)
returns void language plpgsql as $$ begin if condition is not true then raise exception 'BE-040 assertion: %', message; end if; end; $$;

set local role authenticated;
select set_config('request.jwt.claim.sub', '80000000-0000-4000-8000-000000000002', true);
select set_config('request.jwt.claims', '{"sub":"80000000-0000-4000-8000-000000000002","app_metadata":{"active_church_id":"81000000-0000-4000-8000-000000000001"}}', true);



create temporary table grouped_ratio as
select (public.create_calculated_metric(jsonb_build_object(
 'code','ATTENDANCE_PER_CARE','name','Attendance per care meeting','category','attendance','unit','people',
 'operator','ratio','numeratorCount',4,'sourceMetricIds',jsonb_build_array(
 '87000000-0000-4000-8000-000000000001','87000000-0000-4000-8000-000000000008',
 '87000000-0000-4000-8000-000000000009','87000000-0000-4000-8000-000000000010',
 '87000000-0000-4000-8000-000000000011','87000000-0000-4000-8000-000000000012'
 ))) #>> '{data,metricId}')::uuid id;

reset role;
update public.statistic_metrics set show_on_dashboard=true where id=(select id from grouped_ratio);
-- Internal report reference is intentionally not granted to authenticated.
reset role;
do $test$
declare
 root_id uuid := '84000000-0000-4000-8000-000000000001';
 period_id uuid := '88000000-0000-4000-8000-000000000002';
 compare_id uuid;
 metric_id uuid := (select id from grouped_ratio);
 metric jsonb; point jsonb; child jsonb; expected numeric; end_date date;
begin
 select p.period_end into end_date from public.statistic_periods p where p.id=period_id;
 select p.id into compare_id from public.statistic_periods p where p.church_id=app_security.current_church_id()
  and p.period_end<end_date order by p.period_end desc limit 1;
 select value into metric from jsonb_array_elements(public.get_recursive_summary(root_id,period_id,compare_id) #> '{data,metrics}')
  where value->>'metricCode'='ATTENDANCE_PER_CARE';
 expected := app_security.report_metric_value(metric_id,root_id,end_date,end_date,true);
 perform pg_temp.assert_true((metric->>'currentValue')::numeric is not distinct from expected,'root summary agrees with report reference');
 if compare_id is not null then
  select p.period_end into end_date from public.statistic_periods p where p.id=compare_id;
  expected := app_security.report_metric_value(metric_id,root_id,end_date,end_date,true);
  perform pg_temp.assert_true((metric->>'compareValue')::numeric is not distinct from expected,'comparison agrees with reference');
 end if;
 for point in select value from jsonb_array_elements(public.get_dashboard_trend(root_id,'ATTENDANCE_PER_CARE',period_id,12) #> '{data,points}') loop
  expected := app_security.report_metric_value(metric_id,root_id,(point->>'periodEnd')::date,(point->>'periodEnd')::date,true);
  perform pg_temp.assert_true((point->>'value')::numeric is not distinct from expected,'each trend period agrees with reference');
 end loop;
 select p.period_end into end_date from public.statistic_periods p where p.id=period_id;
 for child in select value from jsonb_array_elements(public.get_child_ou_summary(root_id,period_id) #> '{data,children}') loop
  select value into metric from jsonb_array_elements(child->'metrics') where value->>'metricCode'='ATTENDANCE_PER_CARE';
  expected := app_security.report_metric_value(metric_id,(child->>'ouId')::uuid,end_date,end_date,true);
  perform pg_temp.assert_true((metric->>'value')::numeric is not distinct from expected,'child rollup agrees with reference');
 end loop;
end $test$;
select 'ok 1 - Batched root ratios match report reference';
rollback;
