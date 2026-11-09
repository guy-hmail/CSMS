\set ON_ERROR_STOP on
select '1..1';
begin;

create function pg_temp.assert_true(condition boolean, message text)
returns void language plpgsql as $$ begin if condition is not true then raise exception 'BE-038 assertion: %', message; end if; end; $$;

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
delete from public.statistic_values where submission_id='89000000-0000-4000-8000-000000000002'
 and metric_id=any((select calculation_source_metric_ids from public.statistic_metrics where id=(select id from grouped_ratio))::uuid[]);
insert into public.statistic_values(church_id,submission_id,metric_id,numeric_value)
select '81000000-0000-4000-8000-000000000001','89000000-0000-4000-8000-000000000002',v.id,v.amount
from public.statistic_metrics m cross join lateral unnest(m.calculation_source_metric_ids, array[60,20,10,5,7,3]) v(id,amount)
where m.id=(select id from grouped_ratio);
set local role authenticated;
create function pg_temp.report() returns jsonb language sql as $$
 select public.get_report_table('84000000-0000-4000-8000-000000000004','2026-07-26','2026-07-26')->'data';
$$;
select pg_temp.assert_true((pg_temp.report() #>> '{totals,ATTENDANCE_PER_CARE}')::numeric=10, '95 divided by 10 rounds to 10');
select pg_temp.assert_true(exists(select 1 from jsonb_array_elements(pg_temp.report()->'metrics') m
 where m->>'metricCode'='ATTENDANCE_PER_CARE' and (m->>'numeratorCount')::integer=4 and jsonb_array_length(m->'sourceMetricCodes')=6), 'report exposes both groups');
select public.update_calculated_metric(jsonb_build_object('metricId',(select id from grouped_ratio),'numeratorCount',3));
select pg_temp.assert_true((pg_temp.report() #>> '{totals,ATTENDANCE_PER_CARE}')::numeric=6, 'edited split evaluates 90 divided by 15');
reset role;
update public.statistic_values set numeric_value=0 where submission_id='89000000-0000-4000-8000-000000000002'
 and metric_id in ('87000000-0000-4000-8000-000000000010','87000000-0000-4000-8000-000000000011','87000000-0000-4000-8000-000000000012');
select pg_temp.assert_true(pg_temp.report() #>> '{totalErrors,ATTENDANCE_PER_CARE}'='DIVISION_BY_ZERO', 'all denominator fields zero');
delete from public.statistic_values where submission_id='89000000-0000-4000-8000-000000000002' and metric_id='87000000-0000-4000-8000-000000000008';
select pg_temp.assert_true(pg_temp.report() #>> '{totalErrors,ATTENDANCE_PER_CARE}'='MISSING_DATA', 'one missing operand takes precedence');
select 'ok 1 - Grouped ratio operands';
rollback;
