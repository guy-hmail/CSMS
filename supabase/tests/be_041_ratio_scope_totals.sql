\set ON_ERROR_STOP on
select '1..1';
begin;

create function pg_temp.assert_true(condition boolean, message text)
returns void language plpgsql as $$ begin if condition is not true then raise exception 'BE-041 assertion: %', message; end if; end; $$;

set local role authenticated;
select set_config('request.jwt.claim.sub', '80000000-0000-4000-8000-000000000002', true);
select set_config('request.jwt.claims', '{"sub":"80000000-0000-4000-8000-000000000002","app_metadata":{"active_church_id":"81000000-0000-4000-8000-000000000001"}}', true);




create temporary table scope_ratio as
select (public.create_calculated_metric(jsonb_build_object('code','SCOPE_RATIO','name','Scope ratio',
 'category','attendance','unit','%','operator','ratio','numeratorCount',1,
 'sourceMetricIds',jsonb_build_array('87000000-0000-4000-8000-000000000008','87000000-0000-4000-8000-000000000001')
)) #>> '{data,metricId}')::uuid id;
reset role;
update public.statistic_metrics set show_on_dashboard=true where id=(select id from scope_ratio);
delete from public.statistic_values where submission_id in ('89000000-0000-4000-8000-000000000002','89000000-0000-4000-8000-000000000003')
 and metric_id in ('87000000-0000-4000-8000-000000000008','87000000-0000-4000-8000-000000000001');
insert into public.statistic_values(church_id,submission_id,metric_id,numeric_value) values
 ('81000000-0000-4000-8000-000000000001','89000000-0000-4000-8000-000000000002','87000000-0000-4000-8000-000000000008',8),
 ('81000000-0000-4000-8000-000000000001','89000000-0000-4000-8000-000000000003','87000000-0000-4000-8000-000000000001',2);
set local role authenticated;
select pg_temp.assert_true((public.get_report_table('84000000-0000-4000-8000-000000000001','2026-07-26','2026-07-26') #>> '{data,totals,SCOPE_RATIO}')::numeric=400, 'root report uses available numerator and denominator from different submissions');
select pg_temp.assert_true(public.get_report_table('84000000-0000-4000-8000-000000000004','2026-07-26','2026-07-26') #>> '{data,totalErrors,SCOPE_RATIO}'='MISSING_DATA', 'leaf without a denominator remains missing');
select pg_temp.assert_true(exists(select 1 from jsonb_array_elements(public.get_recursive_summary('84000000-0000-4000-8000-000000000001','88000000-0000-4000-8000-000000000002') #> '{data,metrics}') m
 where m->>'metricCode'='SCOPE_RATIO' and (m->>'currentValue')::numeric=400 and m->>'error' is null), 'root KPI computes ratio of scope totals');
select pg_temp.assert_true((public.get_dashboard_trend('84000000-0000-4000-8000-000000000001','SCOPE_RATIO','88000000-0000-4000-8000-000000000002',1) #>> '{data,points,0,value}')::numeric=400, 'root trend matches scope totals');
select 'ok 1 - Ratios aggregate each side over the selected scope';
rollback;
