\set ON_ERROR_STOP on
select '1..1';
begin;

create function pg_temp.assert_true(condition boolean, message text)
returns void language plpgsql as $$ begin if condition is not true then raise exception 'BE-039 assertion: %', message; end if; end; $$;

set local role authenticated;
select set_config('request.jwt.claim.sub', '80000000-0000-4000-8000-000000000002', true);
select set_config('request.jwt.claims', '{"sub":"80000000-0000-4000-8000-000000000002","app_metadata":{"active_church_id":"81000000-0000-4000-8000-000000000001"}}', true);



create temporary table saved as
select (public.create_calculated_metric(jsonb_build_object(
  'code','BB_RATIO','name','อัตราการเรียนรวี','category','attendance','unit','คน','sortOrder',140,
  'description','อัตราการเรียนรวี','operator','ratio','numeratorCount',1,
  'sourceMetricIds',jsonb_build_array('87000000-0000-4000-8000-000000000002',
    '87000000-0000-4000-8000-000000000001','87000000-0000-4000-8000-000000000005')
)) #>> '{data,metricId}')::uuid id;
select pg_temp.assert_true(exists(select 1 from public.statistic_metrics where id=(select id from saved)
  and code='BB_RATIO' and ratio_numerator_count=1 and cardinality(calculation_source_metric_ids)=3 and sort_order=140), 'screenshot values can be saved');
select 'ok 1 - BB_RATIO form values saved';
rollback;
